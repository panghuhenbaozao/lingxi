import AVFoundation
import Speech
import SwiftUI
import UIKit

struct VoiceTranslationHistoryItem: Identifiable, Equatable {
    let id = UUID()
    let mode: VoiceTranslateMode
    let source: String
    let target: String
    let createdAt: Date = Date()
}

/// 实时双语语音识别 + 边说边流式 AI 翻译控制器（支持说中文转英语、说英语转中文、中日互译及纯语音转写，动态切换 SFSpeechRecognizer 语种）。
@MainActor
final class VoiceLiveTranslatorController: ObservableObject {
    @Published var mode: VoiceTranslateMode = .zhToEn
    @Published var transcript: String = ""
    @Published var translatedText: String = ""
    @Published var isRecording: Bool = false
    @Published var isTranslating: Bool = false
    @Published var audioLevel: CGFloat = 0
    @Published var statusText: String = "点下方麦克风直接开口说话，支持边说边实时双语转换"
    @Published var errorText: String? = nil
    @Published var permissionDenied: Bool = false
    @Published var history: [VoiceTranslationHistoryItem] = []

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let aiClient = AIClient(timeout: 30)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var liveTranslateDebounceTask: Task<Void, Never>?
    private var translateStreamTask: Task<Void, Never>?
    private var lastTranslatedSnapshot = ""
    private var pausedBackgroundEngineWasWarm = false

    func selectMode(_ newMode: VoiceTranslateMode) {
        guard mode != newMode else { return }
        if isRecording { stop(runFinalTranslate: false) }
        mode = newMode
        transcript = ""
        translatedText = ""
        lastTranslatedSnapshot = ""
        errorText = nil
        statusText = "已切换为「\(newMode.shortTitle)」，点麦克风开始说话"
    }

    func flipDirection() {
        selectMode(mode.flipped)
    }

    func clearAll() {
        if isRecording { stop(runFinalTranslate: false) }
        liveTranslateDebounceTask?.cancel()
        translateStreamTask?.cancel()
        transcript = ""
        translatedText = ""
        lastTranslatedSnapshot = ""
        isTranslating = false
        errorText = nil
    }

    func toggleRecording(aiConfig: AIConfig) {
        if isRecording {
            stop(runFinalTranslate: true, aiConfig: aiConfig)
        } else {
            Task { await start(aiConfig: aiConfig) }
        }
    }

    func start(aiConfig: AIConfig) async {
        permissionDenied = false
        errorText = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // 1. 请求语音识别权限
        let speechAuth = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechAuth == .authorized else {
            permissionDenied = true
            statusText = "请授予「语音识别」权限以启用实时语音转换"
            return
        }

        // 2. 请求麦克风权限（避免首次录音静默失败）
        let micGranted = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
        guard micGranted else {
            permissionDenied = true
            statusText = "请授予「麦克风」权限以采集实时语音"
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: mode.sourceLocaleID)),
              recognizer.isAvailable else {
            errorText = "当前设备暂不支持「\(mode.sourceLanguageLabel)」系统语音识别，请确认网络或系统听写可用。"
            return
        }

        stop(runFinalTranslate: false)
        // 若后台保活语音引擎正在占用麦克风，先礼让释放避免两个 AVAudioEngine 互相冲突
        if BackgroundVoiceEngine.shared.isWarm {
            pausedBackgroundEngineWasWarm = BackgroundVoiceEngine.shared.pauseForForegroundVoice()
        }
        transcript = ""
        translatedText = ""
        lastTranslatedSnapshot = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if #available(iOS 16.0, *) {
                req.addsPunctuation = true
            }
            self.recognitionRequest = req

            let inputNode = audioEngine.inputNode
            let hwFormat = inputNode.inputFormat(forBus: 0)
            guard hwFormat.channelCount > 0 && hwFormat.sampleRate > 0 else {
                errorText = "未检测到可用麦克风通道，请检查系统麦克风权限或蓝牙耳机连接。"
                return
            }
            inputNode.removeTap(onBus: 0)
            // 使用 format: nil 自动匹配当前硬件采样率，蓝牙耳机切换绝不崩溃
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                req.append(buffer)
                let level = Self.computeNormalizedLevel(from: buffer)
                Task { @MainActor [weak self] in
                    self?.audioLevel = level
                }
            }
            audioEngine.prepare()
            try audioEngine.start()

            isRecording = true
            statusText = "🎙️ 正在聆听（\(mode.shortTitle)）… 边说边实时转换"

            recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty && text != self.transcript {
                            self.transcript = text
                            self.scheduleLiveTranslation(for: text, aiConfig: aiConfig)
                        }
                        if result.isFinal {
                            self.stop(runFinalTranslate: true, aiConfig: aiConfig)
                        }
                    } else if let error {
                        // 忽略主动停止时的取消错误
                        let ns = error as NSError
                        if self.isRecording && ns.code != 216 && ns.code != 203 {
                            self.errorText = "识别中断：\(error.localizedDescription)"
                            self.stop(runFinalTranslate: !self.transcript.isEmpty, aiConfig: aiConfig)
                        }
                    }
                }
            }
        } catch {
            errorText = "麦克风启动失败：\(error.localizedDescription)"
            stop(runFinalTranslate: false)
        }
    }

    func stop(runFinalTranslate: Bool, aiConfig: AIConfig = AIConfig.load()) {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if runFinalTranslate && !clean.isEmpty {
            statusText = "录音已结束，正在完成最终校译…"
            triggerTranslationNow(for: clean, aiConfig: aiConfig, recordHistory: true)
        } else if clean.isEmpty {
            statusText = "点下方麦克风开始说话（\(mode.shortTitle)）"
        }
    }

    func restoreBackgroundEngineIfNeeded() {
        if pausedBackgroundEngineWasWarm {
            pausedBackgroundEngineWasWarm = false
            BackgroundVoiceEngine.shared.resumeAfterForegroundVoiceIfNeeded(wasWarm: true)
        }
    }

    /// 手动编辑或粘贴文本后立即触发转换
    func translateCurrentTranscript(aiConfig: AIConfig) {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        triggerTranslationNow(for: clean, aiConfig: aiConfig, recordHistory: true)
    }

    func speakText(_ text: String, localeID: String? = nil) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if isRecording {
            stop(runFinalTranslate: false)
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = AVSpeechSynthesisVoice(language: localeID ?? mode.outputSpeechLocaleID)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    // MARK: - 实时流式翻译

    private func scheduleLiveTranslation(for text: String, aiConfig: AIConfig) {
        liveTranslateDebounceTask?.cancel()
        liveTranslateDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            self.triggerTranslationNow(for: text, aiConfig: aiConfig, recordHistory: false)
        }
    }

    private func triggerTranslationNow(for sourceText: String, aiConfig: AIConfig, recordHistory: Bool) {
        let clean = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if !recordHistory && clean == lastTranslatedSnapshot && !translatedText.isEmpty {
            return
        }

        guard aiConfig.isConfigured else {
            isTranslating = false
            if mode.isTranslationMode {
                errorText = "尚未配置 AI API Key：语音识别原文已就绪，前往「AI 智脑」填写 Key 后即可自动实时中英互译。"
            } else {
                translatedText = TextFormatterToolbox.addPanguSpaces(TextFormatterToolbox.collapseBlankLines(clean))
            }
            return
        }

        translateStreamTask?.cancel()
        isTranslating = true
        errorText = nil
        let modeSnap = mode

        translateStreamTask = Task { [weak self] in
            guard let self else { return }
            var acc = ""
            do {
                for try await chunk in self.aiClient.streamText(
                    prompt: clean,
                    systemInstruction: modeSnap.systemPrompt,
                    config: aiConfig,
                    featureTag: "voice_live_translate",
                    preferFast: true
                ) {
                    if Task.isCancelled { return }
                    acc += chunk
                    self.translatedText = AITextSanitizer.clean(acc, streaming: true)
                }
                if Task.isCancelled { return }
                let finalOut = AITextSanitizer.clean(acc, streaming: false)
                self.translatedText = finalOut
                self.lastTranslatedSnapshot = clean
                self.isTranslating = false
                if !self.isRecording {
                    self.statusText = "✓ 转换完成，可点下方直接复制或朗读"
                }
                if recordHistory && !finalOut.isEmpty {
                    let item = VoiceTranslationHistoryItem(mode: modeSnap, source: clean, target: finalOut)
                    self.history.insert(item, at: 0)
                    if self.history.count > 15 { self.history = Array(self.history.prefix(15)) }
                    // 录音结束完成精准校译后自动写入剪贴板与历史，切回微信/聊天软件顶栏立刻弹出一键粘贴胶囊
                    UIPasteboard.general.string = finalOut
                    _ = ClipboardStore.record(finalOut)
                    self.statusText = "✓ 已自动复制译文！切回原 App 点键盘顶栏即可直接上屏"
                }
            } catch is CancellationError {
                // 新的语音片段到来，自然取消旧任务
            } catch {
                self.isTranslating = false
                self.errorText = "实时翻译失败：\(error.localizedDescription)"
            }
        }
    }

    private nonisolated static func computeNormalizedLevel(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameCount {
            let s = channelData[i]
            sum += s * s
        }
        let rms = sqrt(sum / Float(frameCount))
        let scaled = min(1.0, max(0.0, rms * 10.0))
        return CGFloat(scaled)
    }
}

/// 旗舰「实时语音同传转换」工作台（说中文实时转英文 / 说英文实时转中文 / 中日互译 / 朗读 / 一键复制回键盘）。
struct VoiceLiveTranslatorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = VoiceLiveTranslatorController()
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    modeSwitcherCard
                    sourceCard
                    resultCard
                    micActionCard
                    if !controller.history.isEmpty {
                        historySection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("实时语音同传")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        controller.stop(runFinalTranslate: false)
                        dismiss()
                    }
                }
                if !controller.transcript.isEmpty || !controller.translatedText.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("清空") {
                            controller.clearAll()
                        }
                        .font(.subheadline)
                    }
                }
            }
            .onAppear {
                applyPendingExternalLaunchIfNeeded()
            }
            .onChange(of: appState.voiceTranslatorAutoStart) { shouldStart in
                if shouldStart {
                    applyPendingExternalLaunchIfNeeded()
                }
            }
            .onChange(of: appState.voiceTranslatorInitialMode) { newMode in
                if newMode != nil {
                    applyPendingExternalLaunchIfNeeded()
                }
            }
            .onDisappear {
                controller.stop(runFinalTranslate: false)
                controller.restoreBackgroundEngineIfNeeded()
            }
        }
    }

    // MARK: - 1. 顶部语种互换条

    private var modeSwitcherCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(controller.mode.sourceLanguageLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(Design.Palette.surface))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    controller.flipDirection()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 34)
                        .background(Color(Design.Palette.accent))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("一键互换语种方向")

                Text(controller.mode.targetLanguageLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.accent))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(Design.Palette.accentSoft))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(VoiceTranslateMode.allCases) { m in
                        let active = controller.mode == m
                        Button(m.pillTitle) {
                            controller.selectMode(m)
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
                        .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 2. 实时语音原文卡片

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(controller.isRecording ? Color(Design.Palette.error) : Color(Design.Palette.accent))
                    .frame(width: 8, height: 8)
                Text("🎙️ \(controller.mode.sourceLanguageLabel)（可边说边改，也可粘贴）")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("粘贴") {
                    if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                        controller.transcript = clip
                        controller.translateCurrentTranscript(aiConfig: appState.aiConfig)
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(Color(Design.Palette.accent))
                .buttonStyle(.plain)

                if !controller.transcript.isEmpty && !controller.isRecording {
                    Button("立即转译") {
                        controller.translateCurrentTranscript(aiConfig: appState.aiConfig)
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(Design.Palette.accentSoft))
                    .foregroundStyle(Color(Design.Palette.accent))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
            }

            ZStack(alignment: .topLeading) {
                if controller.transcript.isEmpty {
                    Text(controller.mode.sourceLocaleID == "en-US"
                         ? "Speak English here, or paste English text to translate into Chinese in real time…"
                         : "按下方开始说话，或直接粘贴文字实时转换…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $controller.transcript)
                    .font(.body)
                    .frame(minHeight: 88, maxHeight: 140)
                    .scrollContentBackground(.hidden)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 3. 实时转换结果卡片

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("🌐 \(controller.mode.targetLanguageLabel)")
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.accent))
                if controller.isTranslating {
                    ProgressView().scaleEffect(0.7)
                    Text("实时转换中…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !controller.translatedText.isEmpty {
                    Button {
                        controller.speakText(controller.translatedText)
                    } label: {
                        Label("朗读", systemImage: "speaker.wave.2.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color(Design.Palette.surface))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let err = controller.errorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠️ \(err)")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if !appState.aiConfig.isConfigured {
                        Button("一键前往 AI 智脑填写 Key") {
                            appState.requestedTab = 2
                            dismiss()
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(Design.Palette.accent))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                    }
                }
            } else if controller.translatedText.isEmpty {
                Text("开始说话后，实时译文会逐字流式显示在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                Text(controller.isTranslating ? "\(controller.translatedText) ▍" : controller.translatedText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            }

            if !controller.translatedText.isEmpty || !controller.transcript.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        let text = controller.translatedText.isEmpty ? controller.transcript : controller.translatedText
                        copyAndNotify(text, label: "已复制转换结果，切回聊天软件点键盘顶栏即粘贴")
                    } label: {
                        Label("复制结果给键盘", systemImage: "doc.on.doc.fill")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(Color(Design.Palette.accent))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if !controller.transcript.isEmpty && !controller.translatedText.isEmpty {
                        Button {
                            let both = "\(controller.transcript)\n\(controller.translatedText)"
                            copyAndNotify(both, label: "已复制双语对照")
                        } label: {
                            Text("复制双语")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(Color(Design.Palette.surface))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let toast {
                Text(toast)
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.success))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 4. 大号实时录音触发区

    private var micActionCard: some View {
        VStack(spacing: 10) {
            Text(controller.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if controller.permissionDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("一键前往系统设置开启语音与麦克风权限", systemImage: "gearshape.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                controller.toggleRecording(aiConfig: appState.aiConfig)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        if controller.isRecording {
                            Circle()
                                .fill(Color.white.opacity(0.28))
                                .frame(width: 30 + controller.audioLevel * 18, height: 30 + controller.audioLevel * 18)
                                .animation(.easeOut(duration: 0.12), value: controller.audioLevel)
                        }
                        Image(systemName: controller.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .frame(width: 44, height: 44)

                    Text(controller.isRecording
                         ? "停止说话（实时完成校译）"
                         : "开始说话 · \(controller.mode.shortTitle)")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(controller.isRecording ? Color(Design.Palette.error) : Color(Design.Palette.accent))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 5. 本次同传历史记录

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本次同传记录（点按复制，点喇叭朗读）")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(controller.history) { item in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.mode.pillTitle)
                            .font(.caption2.bold())
                            .foregroundStyle(Color(Design.Palette.accent))
                        Text(item.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.target)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        copyAndNotify(item.target, label: "✓ 已复制「\(item.target.prefix(16))…」")
                    }

                    Button {
                        controller.speakText(item.target, localeID: item.mode.outputSpeechLocaleID)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.accent))
                            .padding(8)
                            .background(Color(Design.Palette.accentSoft))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func applyPendingExternalLaunchIfNeeded() {
        if let initMode = appState.voiceTranslatorInitialMode {
            appState.voiceTranslatorInitialMode = nil
            controller.selectMode(initMode)
        }
        if appState.voiceTranslatorAutoStart {
            appState.voiceTranslatorAutoStart = false
            if !controller.isRecording {
                Task { await controller.start(aiConfig: appState.aiConfig) }
            }
        }
    }

    private func copyAndNotify(_ text: String, label: String) {
        UIPasteboard.general.string = text
        appState.addClipboardEntry(text)
        withAnimation { toast = "✓ \(label)" }
    }
}
