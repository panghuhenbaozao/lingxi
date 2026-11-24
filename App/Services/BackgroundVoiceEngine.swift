import AVFoundation
import Foundation
import Network
import Speech
import UIKit

/// 主 App 后台语音引擎（对齐 讯飞输入法 / 豆包输入法 / Wispr Flow 生产级架构）：
/// - 依靠 `UIBackgroundModes: [audio]` 保持超低功耗静音音频会话在后台驻留；
/// - 同时监听 App Group Darwin 通知与本机回环 `127.0.0.1:48921`（免费侧载无 App Group 也能 0ms 互通！）；
/// - 键盘内点「说话」时零跳转接管麦克风、`SFSpeechRecognizer` 实时转写与 AI 双语流式转换，并实时推回键盘面板。
@MainActor
final class BackgroundVoiceEngine: ObservableObject {
    static let shared = BackgroundVoiceEngine()

    @Published private(set) var isWarm: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var liveState: VoiceIPCState = VoiceIPCState()

    private let audioEngine = AVAudioEngine()
    private let aiClient = AIClient(timeout: 25)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
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

    private init() {
        commandObserver = AppGroupNotifications.Observer(name: AppGroupNotifications.voiceCommand) { [weak self] in
            Task { @MainActor in
                self?.handleSharedCommand()
            }
        }
    }

    /// 预热后台语音引擎（申请权限 + 启用静音后台保活音频会话 + 启动本机 127.0.0.1 通信桥）。
    func warmUp() async -> (ok: Bool, message: String) {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            return (false, "请先授予「语音识别」权限，才能在键盘内实时语音转换。")
        }

        let micOK = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard micOK else {
            return (false, "请先授予「麦克风」权限，才能在键盘内采集语音。")
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true)
            startSilentKeepAliveIfNeeded()
            startLoopbackServerIfNeeded()
            isWarm = true
            startHeartbeatTimer()
            liveState.engineWarm = true
            liveState.errorText = nil
            liveState.statusText = "后台语音引擎已就绪 · 切回任意 App 即可在键盘内直接语音转换"
            broadcastState(force: true)
            return (true, "✓ 后台语音引擎已激活！现在切回微信/抖音，点键盘「🎙️语音」即可在键盘内直接说话转换，不再跳出 App。")
        } catch {
            return (false, "激活音频会话失败：\(error.localizedDescription)")
        }
    }

    func shutdown() {
        stopRecording(runFinalTranslate: false)
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        listener?.cancel()
        listener = nil
        isWarm = false
        liveState.engineWarm = false
        liveState.isRecording = false
        broadcastState(force: true)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 静音保活音频（44.1kHz 1s 零振幅 WAV，内存 < 90KB，确保切后台后不被系统挂起）

    private func startSilentKeepAliveIfNeeded() {
        if keepAlivePlayer?.isPlaying == true { return }
        let wavData = Self.makeSilentWAVData(durationSeconds: 1.0, sampleRate: 8000)
        if let player = try? AVAudioPlayer(data: wavData) {
            player.numberOfLoops = -1
            player.volume = 0.0
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
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isWarm else { return }
                self.broadcastState(force: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    // MARK: - 接收键盘命令（App Group + 127.0.0.1 HTTP）

    private func handleSharedCommand() {
        guard let cmd = VoiceIPCBridge.readCommandFromShared() else { return }
        handleCommand(cmd)
    }

    private func handleCommand(_ cmd: VoiceIPCCommand) {
        let mode = VoiceTranslateMode(rawValue: cmd.modeRaw) ?? activeMode
        switch cmd.action {
        case .ping:
            broadcastState(force: true)
        case .start:
            startRecording(mode: mode)
        case .stop:
            stopRecording(runFinalTranslate: true)
        case .clear:
            stopRecording(runFinalTranslate: false)
            liveState.transcript = ""
            liveState.translatedText = ""
            liveState.errorText = nil
            liveState.statusText = "已清空"
            broadcastState(force: true)
        }
    }

    private func startRecording(mode: VoiceTranslateMode) {
        activeMode = mode
        stopRecording(runFinalTranslate: false)
        lastTranslatedSnapshot = ""

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: mode.sourceLocaleID)),
              recognizer.isAvailable else {
            liveState.errorText = "当前设备暂不支持「\(mode.sourceLanguageLabel)」语音识别"
            broadcastState(force: true)
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if #available(iOS 16.0, *) {
                req.addsPunctuation = true
            }
            recognitionRequest = req

            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                req.append(buffer)
                let lvl = Self.computeLevel(buffer)
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.liveState.audioLevel = lvl
                    self.broadcastState(force: false)
                }
            }

            audioEngine.prepare()
            try audioEngine.start()

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
                            self.stopRecording(runFinalTranslate: true)
                        }
                    } else if let error, self.isRecording {
                        let nsErr = error as NSError
                        if nsErr.code != 216 && nsErr.code != 1110 {
                            self.liveState.errorText = error.localizedDescription
                        }
                        self.stopRecording(runFinalTranslate: true)
                    }
                }
            }
        } catch {
            liveState.isRecording = false
            liveState.errorText = "启动录音失败：\(error.localizedDescription)"
            broadcastState(force: true)
        }
    }

    private func stopRecording(runFinalTranslate: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        liveState.isRecording = false
        liveState.audioLevel = 0

        let snap = liveState.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if runFinalTranslate && !snap.isEmpty {
            runTranslationNow(for: snap)
        } else {
            broadcastState(force: true)
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

    // MARK: - 本机回环微 HTTP 服务 (127.0.0.1:48921)，免费侧载无 App Group 也能 0ms 互通

    private func startLoopbackServerIfNeeded() {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: VoiceIPCBridge.loopbackPort) else { return }
        let params = NWParameters.tcp
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
            let bodyPart: Data? = raw.range(of: "\r\n\r\n").map { Data(raw[$0.upperBound...].utf8) }

            Task { @MainActor in
                if firstLine.contains("POST /voice/command"),
                   let bodyPart,
                   let cmd = try? JSONDecoder().decode(VoiceIPCCommand.self, from: bodyPart) {
                    self.handleCommand(cmd)
                }
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
