import AVFoundation
import Foundation
import Network
import Speech
import UIKit

/// 主 App 后台语音引擎（v5.6.1 真正可后台录音的 讯飞 / 豆包 / Wispr Flow 核心原理版）：
///
/// 关键修复（解决 iOS 16–18+ 后台启动 `AVAudioEngine.start()` 必报 `CannotStartRecording` 的根本原因）：
/// 1. 在前台 `warmUp()` 时就一次性启动 `AVAudioEngine` 并挂好常驻 `inputNode` Tap，切入后台后**永不 stop 引擎**！
/// 2. 未说话期间（`isCapturingSpeech == false`），Tap 内直接丢弃音频帧（近乎 0% CPU）；
/// 3. 键盘发来 `.start` 命令时，无需在后台重新 `setActive` 或 `audioEngine.start()`，只需创建
///    `SFSpeechAudioBufferRecognitionRequest` 并将原子开关置为开启，常驻 Tap 立刻无缝灌入 PCM 音频流！
/// 4. 保活播放器采用极低非零音量（`0.001`）+ 15 分钟无操作自动休眠省电，兼顾稳定性与续航。
@MainActor
final class BackgroundVoiceEngine: ObservableObject {
    static let shared = BackgroundVoiceEngine()

    /// 线程安全的实时音频投递槽：由后台音频渲染线程读取，主线程切换起停，零锁零卡顿。
    private final class CaptureSink {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?
        private var active: Bool = false

        func begin(with req: SFSpeechAudioBufferRecognitionRequest) {
            lock.lock()
            request = req
            active = true
            lock.unlock()
        }

        func end() -> SFSpeechAudioBufferRecognitionRequest? {
            lock.lock()
            let prev = request
            request = nil
            active = false
            lock.unlock()
            return prev
        }

        func appendIfActive(_ buffer: AVAudioPCMBuffer) -> Bool {
            lock.lock()
            let isOn = active
            let req = request
            lock.unlock()
            guard isOn, let req else { return false }
            req.append(buffer)
            return true
        }
    }

    @Published private(set) var isWarm: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var liveState: VoiceIPCState = VoiceIPCState()

    private let audioEngine = AVAudioEngine()
    private let captureSink = CaptureSink()
    private let aiClient = AIClient(timeout: 25)
    private var recognitionTask: SFSpeechRecognitionTask?
    private var translateDebounceTask: Task<Void, Never>?
    private var translateStreamTask: Task<Void, Never>?
    private var heartbeatTimer: Timer?
    private var keepAlivePlayer: AVAudioPlayer?
    private var commandObserver: AppGroupNotifications.Observer?
    private var listener: NWListener?
    private let listenerQueue = DispatchQueue(label: "com.lingxi.voice.loopback", qos: .userInteractive)

    private var activeMode: VoiceTranslateMode = .zhToEn
    private var lastTranslatedSnapshot: String = ""
    private var lastStateBroadcastTime: CFTimeInterval = 0
    private var lastActivityTime: Date = Date()
    private var tapInstalled = false
    /// 闲置超过 15 分钟自动释放后台音频会话省电
    private static let idleShutdownSeconds: TimeInterval = 15 * 60

    private init() {
        commandObserver = AppGroupNotifications.Observer(name: AppGroupNotifications.voiceCommand) { [weak self] in
            Task { @MainActor in
                self?.handleSharedCommand()
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleAudioInterruption(note)
            }
        }
    }

    /// 预热后台语音引擎（必须在主 App 前台执行一次）：申请权限 + 启动常驻 `AVAudioEngine` + 启动双通道 IPC。
    func warmUp() async -> (ok: Bool, message: String) {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            return (false, "请先在系统设置中授予「语音识别」权限，才能使用键盘内语音转换。")
        }

        let micOK = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard micOK else {
            return (false, "请先在系统设置中授予「麦克风」权限，才能采集语音。")
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true)

            do {
                try ensureAudioEngineRunning()
            } catch {
                // 冷启动通过 lingxi://voice-warmup 切前台时，给系统音频路由 250ms 完成激活后自动重试一次
                try? await Task.sleep(nanoseconds: 250_000_000)
                try session.setActive(true)
                try ensureAudioEngineRunning()
            }
            startSilentKeepAliveIfNeeded()
            startLoopbackServerIfNeeded()

            isWarm = true
            lastActivityTime = Date()
            startHeartbeatTimer()
            liveState.engineWarm = true
            liveState.isRecording = false
            liveState.errorText = nil
            liveState.statusText = "✓ 后台语音引擎已就绪 · 切回微信/抖音即可在键盘内直接说话"
            broadcastState(force: true)
            return (true, "✓ 后台语音引擎已激活！请点左上角返回原 App，即可在键盘内直接点「🎙️ 开始说话」实时转换（无需再次跳出）。")
        } catch {
            return (false, "激活语音引擎失败：\(error.localizedDescription)")
        }
    }

    func shutdown() {
        stopCapture(runFinalTranslate: false)
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        listener?.cancel()
        listener = nil
        isWarm = false
        liveState.engineWarm = false
        liveState.isRecording = false
        broadcastState(force: true)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 核心：在前台启动常驻 `AVAudioEngine` 与 `inputNode` Tap，确保切入后台后随时可无报错收音。
    private func ensureAudioEngineRunning() throws {
        if audioEngine.isRunning && tapInstalled {
            return
        }
        let inputNode = audioEngine.inputNode
        if tapInstalled {
            inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        let format = inputNode.inputFormat(forBus: 0)
        guard format.channelCount > 0 && format.sampleRate > 0 else {
            throw NSError(domain: "LingxiVoice", code: -10, userInfo: [NSLocalizedDescriptionKey: "未检测到可用麦克风输入通道"])
        }
        let sink = self.captureSink
        // 传入 format: nil 自动跟随硬件采样率（蓝牙/听筒切换永不崩溃）
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard sink.appendIfActive(buffer) else { return }
            let lvl = Self.computeLevel(buffer)
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.liveState.audioLevel = lvl
                self.broadcastState(force: false)
            }
        }
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func handleAudioInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }
        if type == .began {
            stopCapture(runFinalTranslate: false)
        } else if type == .ended, isWarm {
            try? AVAudioSession.sharedInstance().setActive(true)
            try? ensureAudioEngineRunning()
            keepAlivePlayer?.play()
        }
    }

    // MARK: - 极低非零音量保活（volume = 0.001，防止 mediaserverd 将 0.0 静默挂起）

    private func startSilentKeepAliveIfNeeded() {
        if keepAlivePlayer?.isPlaying == true { return }
        let wavData = Self.makeSilentWAVData(durationSeconds: 1.0, sampleRate: 8000)
        if let player = try? AVAudioPlayer(data: wavData) {
            player.numberOfLoops = -1
            player.volume = 0.001
            player.prepareToPlay()
            player.play()
            keepAlivePlayer = player
        }
    }

    private static func makeSilentWAVData(durationSeconds: Double, sampleRate: Int) -> Data {
        let numSamples = Int(Double(sampleRate) * durationSeconds)
        let dataSize = UInt32(numSamples * 2)
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        var chunkSize = UInt32(36) + dataSize
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append("WAVEfmt ".data(using: .ascii)!)
        var subchunk1Size: UInt32 = 16
        var audioFormat: UInt16 = 1
        var numChannels: UInt16 = 1
        var sr: UInt32 = UInt32(sampleRate)
        var byteRate: UInt32 = UInt32(sampleRate * 2)
        var blockAlign: UInt16 = 2
        var bitsPerSample: UInt16 = 16
        data.append(Data(bytes: &subchunk1Size, count: 4))
        data.append(Data(bytes: &audioFormat, count: 2))
        data.append(Data(bytes: &numChannels, count: 2))
        data.append(Data(bytes: &sr, count: 4))
        data.append(Data(bytes: &byteRate, count: 4))
        data.append(Data(bytes: &blockAlign, count: 2))
        data.append(Data(bytes: &bitsPerSample, count: 2))
        data.append("data".data(using: .ascii)!)
        var subchunk2Size = dataSize
        data.append(Data(bytes: &subchunk2Size, count: 4))
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        let timer = Timer(timeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isWarm else { return }
                if !self.isRecording && Date().timeIntervalSince(self.lastActivityTime) > Self.idleShutdownSeconds {
                    self.shutdown()
                    return
                }
                self.liveState.engineWarm = self.audioEngine.isRunning
                self.broadcastState(force: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    // MARK: - 接收键盘命令

    private func handleSharedCommand() {
        guard let cmd = VoiceIPCBridge.readCommandFromShared() else { return }
        handleCommand(cmd)
    }

    private func handleCommand(_ cmd: VoiceIPCCommand) {
        lastActivityTime = Date()
        let mode = VoiceTranslateMode(rawValue: cmd.modeRaw) ?? activeMode
        switch cmd.action {
        case .ping:
            liveState.engineWarm = isWarm && audioEngine.isRunning
            broadcastState(force: true)
        case .start:
            startCapture(mode: mode)
        case .stop:
            stopCapture(runFinalTranslate: true)
        case .clear:
            stopCapture(runFinalTranslate: false)
            liveState.transcript = ""
            liveState.translatedText = ""
            liveState.errorText = nil
            liveState.statusText = "已清空"
            broadcastState(force: true)
        }
    }

    /// 键盘发来 `.start`：绝不在后台重启 `AVAudioEngine`，直接向已在运行的常驻引擎挂载识别请求！
    private func startCapture(mode: VoiceTranslateMode) {
        activeMode = mode
        stopCapture(runFinalTranslate: false)
        lastTranslatedSnapshot = ""

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: mode.sourceLocaleID)),
              recognizer.isAvailable else {
            liveState.errorText = "当前设备暂不支持「\(mode.sourceLanguageLabel)」语音识别"
            broadcastState(force: true)
            return
        }

        if !audioEngine.isRunning {
            do {
                try ensureAudioEngineRunning()
            } catch {
                isWarm = false
                liveState.engineWarm = false
                liveState.isRecording = false
                liveState.errorText = "后台音频引擎已休眠，请点下方重新激活一次"
                broadcastState(force: true)
                return
            }
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            req.addsPunctuation = true
        }
        captureSink.begin(with: req)

        isRecording = true
        liveState.engineWarm = true
        liveState.isRecording = true
        liveState.isTranslating = false
        liveState.modeRaw = mode.rawValue
        liveState.transcript = ""
        liveState.translatedText = ""
        liveState.errorText = nil
        liveState.statusText = "🎙️ 正在听「\(mode.sourceLanguageLabel)」…"
        broadcastState(force: true)

        recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.liveState.transcript = text
                    self.scheduleLiveTranslate(for: text)
                    self.broadcastState(force: true)
                    if result.isFinal {
                        self.stopCapture(runFinalTranslate: true)
                    }
                } else if let error, self.isRecording {
                    let nsErr = error as NSError
                    // 忽略正常取消 (216) 与无语音超时 (1110)
                    if nsErr.code != 216 && nsErr.code != 1110 {
                        self.liveState.errorText = "语音识别中断(\(nsErr.code))：\(error.localizedDescription)"
                    }
                    self.stopCapture(runFinalTranslate: true)
                }
            }
        }
    }

    /// 停止本次收音（保持 `AVAudioEngine` 常驻运行，确保下一次在微信里点说话依然 0ms 可用！）
    private func stopCapture(runFinalTranslate: Bool) {
        let prevReq = captureSink.end()
        prevReq?.endAudio()
        if runFinalTranslate {
            recognitionTask?.finish()
        } else {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
        isRecording = false
        liveState.isRecording = false
        liveState.audioLevel = 0
        broadcastState(force: true)

        let snap = liveState.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if runFinalTranslate && !snap.isEmpty {
            runTranslationNow(for: snap)
        }
    }

    private func scheduleLiveTranslate(for text: String) {
        translateDebounceTask?.cancel()
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        translateDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled, let self else { return }
            self.runTranslationNow(for: clean)
        }
    }

    private func runTranslationNow(for sourceText: String) {
        let clean = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if clean == lastTranslatedSnapshot && !liveState.translatedText.isEmpty {
            return
        }
        let cfg = AIConfig.load()
        guard cfg.isConfigured else {
            liveState.isTranslating = false
            if !activeMode.isTranslationMode {
                liveState.translatedText = AITextSanitizer.clean(clean, streaming: false)
            } else {
                liveState.errorText = "语音原文已识别；填写 AI Key 后可实时自动双语互译"
            }
            broadcastState(force: true)
            return
        }

        translateStreamTask?.cancel()
        liveState.isTranslating = true
        liveState.errorText = nil
        let modeSnap = activeMode
        broadcastState(force: true)

        translateStreamTask = Task { [weak self] in
            guard let self else { return }
            var acc = ""
            do {
                for try await chunk in self.aiClient.streamText(
                    prompt: clean,
                    systemInstruction: modeSnap.systemPrompt,
                    config: cfg,
                    featureTag: "in_keyboard_voice_translate",
                    preferFast: true
                ) {
                    if Task.isCancelled { return }
                    acc += chunk
                    self.liveState.translatedText = AITextSanitizer.clean(acc, streaming: true)
                    self.broadcastState(force: false)
                }
                if Task.isCancelled { return }
                self.liveState.translatedText = AITextSanitizer.clean(acc, streaming: false)
                self.liveState.isTranslating = false
                self.lastTranslatedSnapshot = clean
                self.liveState.statusText = "✓ 转换完成 · 点「插入上屏」直接发送"
                self.broadcastState(force: true)
            } catch is CancellationError {
            } catch {
                self.liveState.isTranslating = false
                self.liveState.errorText = "翻译失败：\(error.localizedDescription)"
                self.broadcastState(force: true)
            }
        }
    }

    private func broadcastState(force: Bool) {
        let now = CACurrentMediaTime()
        if !force && now - lastStateBroadcastTime < 0.08 {
            return
        }
        lastStateBroadcastTime = now
        liveState.updatedAt = Date().timeIntervalSince1970
        VoiceIPCBridge.writeStateToShared(liveState)
    }

    private nonisolated static func computeLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return min(1.0, max(0.0, Double(sqrt(sum / Float(n)) * 10.0)))
    }

    // MARK: - 本机回环微 HTTP 服务 (127.0.0.1:48921)

    private func startLoopbackServerIfNeeded() {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: VoiceIPCBridge.loopbackPort) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)
        guard let newListener = try? NWListener(using: params) else { return }
        newListener.newConnectionHandler = { [weak self] conn in
            self?.handleLoopbackConnection(conn)
        }
        newListener.stateUpdateHandler = { [weak self] st in
            if case .failed = st {
                Task { @MainActor [weak self] in
                    self?.listener?.cancel()
                    self?.listener = nil
                }
            }
        }
        newListener.start(queue: listenerQueue)
        listener = newListener
    }

    private nonisolated func handleLoopbackConnection(_ conn: NWConnection) {
        conn.start(queue: listenerQueue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self, let data, let raw = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            let firstLine = raw.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let requestTarget: String = {
                let parts = firstLine.split(separator: " ")
                return parts.count >= 2 ? String(parts[1]) : ""
            }()
            let bodyPart: Data? = raw.range(of: "\r\n\r\n").map { Data(raw[$0.upperBound...].utf8) }

            // 解析单包 GET /voice/cmd?action=...&mode=... 或兼容 POST /voice/command JSON Body
            var parsedCmd: VoiceIPCCommand?
            if requestTarget.hasPrefix("/voice/cmd"),
               let comps = URLComponents(string: "http://127.0.0.1\(requestTarget)"),
               let actionRaw = comps.queryItems?.first(where: { $0.name == "action" })?.value,
               let action = VoiceIPCCommand.Action(rawValue: actionRaw) {
                let modeRaw = comps.queryItems?.first(where: { $0.name == "mode" })?.value ?? VoiceTranslateMode.zhToEn.rawValue
                parsedCmd = VoiceIPCCommand(action: action, modeRaw: modeRaw)
            } else if firstLine.contains("POST /voice/command"),
                      let bodyPart,
                      !bodyPart.isEmpty,
                      let cmd = try? JSONDecoder().decode(VoiceIPCCommand.self, from: bodyPart) {
                parsedCmd = cmd
            }

            Task { @MainActor in
                if let parsedCmd {
                    self.handleCommand(parsedCmd)
                }
                self.liveState.engineWarm = self.isWarm && self.audioEngine.isRunning
                self.liveState.updatedAt = Date().timeIntervalSince1970
                let json = (try? JSONEncoder().encode(self.liveState)) ?? Data("{}".utf8)
                let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n"
                var payload = Data(header.utf8)
                payload.append(json)
                conn.send(content: payload, completion: .contentProcessed { _ in
                    conn.cancel()
                })
            }
        }
    }
}
