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
    @Published var statusText: String = "点下方麦克风开始说话，边说边转换"
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
        statusText = "已切换为「\(newMode.shortTitle)」"
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

    private var isStarting = false

    func start(aiConfig: AIConfig) async {
        // 防止连点导致两次启动音频引擎
        guard !isStarting, !isRecording else { return }
        isStarting = true
        defer { isStarting = false }
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
            statusText = "需要「语音识别」权限才能把说的话转成文字"
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
            statusText = "需要「麦克风」权限才能录音"
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: mode.sourceLocaleID)),
              recognizer.isAvailable else {
            errorText = "这台设备暂时无法识别「\(mode.sourceLanguageLabel)」，请检查网络，或在系统设置里确认已开启听写。"
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
                errorText = "没有检测到可用的麦克风，请检查麦克风权限或蓝牙耳机连接。"
                recognitionRequest = nil
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                restoreBackgroundEngineIfNeeded()
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
            statusText = "正在听（\(mode.shortTitle)），说完点「说完了」"

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
            restoreBackgroundEngineIfNeeded()
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
            statusText = "正在完成最终转换…"
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
                errorText = "还没有填写 AI 密钥：原文已经识别出来了，填好密钥后就能自动翻译。"
            } else {
                let report = VoiceTranscriptCleaner.clean(clean)
                translatedText = report.cleaned
                statusText = "离线去口水完成：\(report.summaryBadge)"
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
                    self.statusText = "转换完成，可以复制或朗读"
                }
                if recordHistory && !finalOut.isEmpty {
                    let item = VoiceTranslationHistoryItem(mode: modeSnap, source: clean, target: finalOut)
                    self.history.insert(item, at: 0)
                    if self.history.count > 15 { self.history = Array(self.history.prefix(15)) }
                    // 录音结束完成精准校译后自动写入剪贴板与历史，切回微信/聊天软件顶栏立刻弹出一键粘贴胶囊
                    UIPasteboard.general.string = finalOut
                    _ = ClipboardStore.record(finalOut)
                    self.statusText = "结果已自动复制，切回聊天 App 点键盘顶栏即可粘贴"
                }
            } catch is CancellationError {
                // 新的语音片段到来，自然取消旧任务
            } catch {
                self.isTranslating = false
                self.errorText = "转换失败：\(error.localizedDescription)"
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

/// 实时语音同传工作台（v6）：语种切换 → 原文 → 译文 → 底部固定大号麦克风；本次记录可复制、朗读。
struct VoiceLiveTranslatorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var controller = VoiceLiveTranslatorController()
    @State private var toast: String?
    @State private var confirmClear = false
    @State private var showOfflineCleanDiff = false
    @State private var lastOfflineCleanedOriginal = ""
    @FocusState private var editorFocused: Bool

    private var hasContent: Bool {
        !controller.transcript.isEmpty || !controller.translatedText.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.md) {
                    languageCard
                    sourceCard
                    resultCard
                    if !controller.history.isEmpty {
                        historySection
                    }
                }
                .lxReadableWidth()
                .padding(.horizontal, Design.Spacing.md)
                .padding(.top, Design.Spacing.xs)
                .padding(.bottom, Design.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                micBar
            }
            .navigationTitle("语音同传")
            .navigationBarTitleDisplayMode(.inline)
            .lxToast($toast)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        controller.stop(runFinalTranslate: false)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if hasContent {
                        Button("清空") {
                            confirmClear = true
                        }
                        .disabled(controller.isRecording)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { editorFocused = false }
                }
            }
            .confirmationDialog("清空原文和译文？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    controller.clearAll()
                }
            } message: {
                Text("本次记录列表会保留。")
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
            .onChange(of: controller.isRecording) { recording in
                if recording { editorFocused = false }
            }
            .onDisappear {
                controller.stop(runFinalTranslate: false)
                controller.restoreBackgroundEngineIfNeeded()
            }
        }
    }

    // MARK: - 1. 语种与模式

    private var languageCard: some View {
        LXCard {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    languageLabel(controller.mode.sourceLanguageLabel, caption: "你说", highlighted: false)

                    Button {
                        controller.flipDirection()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 40, height: 40)
                            .background(Color(Design.Palette.accent), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.isRecording)
                    .opacity(controller.isRecording ? 0.4 : 1)
                    .accessibilityLabel("互换语言方向")

                    languageLabel(controller.mode.targetLanguageLabel, caption: controller.mode.isTranslationMode ? "译成" : "整理为", highlighted: true)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(VoiceTranslateMode.allCases) { m in
                            modeChip(m)
                        }
                    }
                }
            }
        }
    }

    private func languageLabel(_ text: String, caption: String, highlighted: Bool) -> some View {
        VStack(spacing: 2) {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Color(Design.Palette.stone))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(highlighted ? Color(Design.Palette.accent) : Color(Design.Palette.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            highlighted ? Color(Design.Palette.accentSoft) : Color(Design.Palette.surface),
            in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func modeChip(_ m: VoiceTranslateMode) -> some View {
        let active = controller.mode == m
        return Button {
            controller.selectMode(m)
        } label: {
            Text(m.pillTitle)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(controller.isRecording)
        .opacity(controller.isRecording && !active ? 0.4 : 1)
        .accessibilityLabel(m.shortTitle)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - 2. 原文

    private var sourceCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(controller.isRecording ? Color(Design.Palette.error) : Color(Design.Palette.hairline))
                        .frame(width: 8, height: 8)
                    Text(controller.isRecording ? "正在听…" : "原文")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(controller.isRecording ? Color(Design.Palette.error) : Color(Design.Palette.stone))
                    if !controller.transcript.isEmpty {
                        Text("\(controller.transcript.count) 字")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    Spacer()
                    if !controller.isRecording {
                        Button {
                            pasteSource()
                        } label: {
                            Label("粘贴", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                    }
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $controller.transcript)
                        .focused($editorFocused)
                        .font(.body)
                        .frame(minHeight: 96, maxHeight: 160)
                        .scrollContentBackground(.hidden)
                        // 录音时由语音识别实时写入，禁止手动编辑以免被识别结果覆盖
                        .disabled(controller.isRecording)
                    if controller.transcript.isEmpty {
                        Text(controller.mode.sourceLocaleID == "en-US"
                             ? "Tap the mic and speak English, or paste text here."
                             : "点下方麦克风开始说话，也可以直接输入或粘贴文字。")
                            .font(.body)
                            .foregroundStyle(Color(Design.Palette.muted))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

                if !controller.transcript.isEmpty && !controller.isRecording {
                    HStack(spacing: 8) {
                        Button {
                            editorFocused = false
                            controller.translateCurrentTranscript(aiConfig: appState.aiConfig)
                        } label: {
                            Label(controller.mode.isTranslationMode ? "翻译这段文字" : "AI 精修整理", systemImage: "arrow.down")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                        .disabled(controller.isTranslating)

                        Button {
                            editorFocused = false
                            let raw = controller.transcript
                            let report = VoiceTranscriptCleaner.clean(raw)
                            lastOfflineCleanedOriginal = raw
                            showOfflineCleanDiff = report.hasChanges
                            controller.translatedText = report.cleaned
                            controller.errorText = nil
                            controller.statusText = "离线口述清洗（0ms）：\(report.summaryBadge)"
                            toast = report.summaryBadge
                        } label: {
                            Label("离线去口水", systemImage: "waveform")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                        .disabled(controller.isTranslating)
                    }
                }
            }
        }
    }

    // MARK: - 3. 译文

    private var resultCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(controller.mode.targetLanguageLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.accent))
                    if controller.isTranslating {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer()
                    if !controller.translatedText.isEmpty && !controller.isTranslating {
                        if !lastOfflineCleanedOriginal.isEmpty && lastOfflineCleanedOriginal != controller.translatedText {
                            Button {
                                showOfflineCleanDiff.toggle()
                            } label: {
                                Label(showOfflineCleanDiff ? "看成品" : "红绿对照", systemImage: "arrow.left.arrow.right")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                        }
                        Button {
                            controller.speakText(controller.translatedText)
                        } label: {
                            Label("朗读", systemImage: "speaker.wave.2")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                    }
                }

                if let err = controller.errorText {
                    errorBlock(err)
                } else if controller.translatedText.isEmpty {
                    Text(controller.isTranslating ? "正在转换…" : "说完或输入后，结果会实时显示在这里。")
                        .font(.subheadline)
                        .foregroundStyle(Color(Design.Palette.muted))
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                } else if showOfflineCleanDiff && !lastOfflineCleanedOriginal.isEmpty && lastOfflineCleanedOriginal != controller.translatedText {
                    let diff = AITextDiffEngine.diff(original: lastOfflineCleanedOriginal, revised: controller.translatedText)
                    LXDiffHighlightText(report: diff)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                } else {
                    Text(controller.translatedText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !controller.translatedText.isEmpty && !controller.isTranslating {
                    HStack(spacing: 8) {
                        Button {
                            copyAndNotify(controller.translatedText, label: "已复制，切回聊天 App 后点键盘顶栏即可粘贴")
                        } label: {
                            Label("复制结果", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))

                        if controller.mode.isTranslationMode && !controller.transcript.isEmpty {
                            Button {
                                copyAndNotify("\(controller.transcript)\n\(controller.translatedText)", label: "已复制双语对照")
                            } label: {
                                Text("复制双语")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                        }
                    }
                }
            }
        }
    }

    private func errorBlock(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.warning))
                Text(LXToastText.clean(err))
                    .font(.footnote)
                    .foregroundStyle(Color(Design.Palette.ink))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !appState.aiConfig.isConfigured {
                Button {
                    controller.stop(runFinalTranslate: false)
                    appState.requestedTab = 2
                    dismiss()
                } label: {
                    Label("去填写 AI 密钥", systemImage: "key.fill")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(Design.Palette.warning).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 4. 底部固定麦克风

    private var micBar: some View {
        VStack(spacing: 8) {
            if controller.permissionDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("去设置开启麦克风和语音识别", systemImage: "gearshape.fill")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.warning)))
            }

            Text(LXToastText.clean(controller.statusText))
                .font(.caption)
                .foregroundStyle(Color(Design.Palette.stone))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)

            Button {
                editorFocused = false
                controller.toggleRecording(aiConfig: appState.aiConfig)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        if controller.isRecording && !reduceMotion {
                            Circle()
                                .fill(Color.white.opacity(0.28))
                                .frame(width: 28 + controller.audioLevel * 18, height: 28 + controller.audioLevel * 18)
                                .animation(.easeOut(duration: 0.12), value: controller.audioLevel)
                        }
                        Image(systemName: controller.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .frame(width: 40, height: 40)

                    Text(controller.isRecording ? "说完了" : "开始说话")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(Color.white)
                .background(
                    controller.isRecording ? Color(Design.Palette.error) : Color(Design.Palette.accent),
                    in: RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isRecording ? "停止录音" : "开始说话，\(controller.mode.shortTitle)")
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    // MARK: - 5. 本次记录

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本次记录 · \(controller.history.count)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(Design.Palette.slate))
                .padding(.leading, 4)

            ForEach(controller.history) { item in
                LXCard {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                LXTag(text: item.mode.pillTitle, tint: Color(Design.Palette.accent), filled: true)
                                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Color(Design.Palette.stone))
                            }
                            Text(item.source)
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                                .lineLimit(2)
                            Text(item.target)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            copyAndNotify(item.target, label: "已复制「\(item.target.prefix(16))」")
                        }

                        VStack(spacing: 6) {
                            iconButton("speaker.wave.2", label: "朗读") {
                                controller.speakText(item.target, localeID: item.mode.outputSpeechLocaleID)
                            }
                            iconButton("doc.on.doc", label: "复制") {
                                copyAndNotify(item.target, label: "已复制「\(item.target.prefix(16))」")
                            }
                        }
                    }
                }
            }
        }
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.accent))
                .frame(width: 36, height: 36)
                .background(Color(Design.Palette.accentSoft), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Actions

    private func pasteSource() {
        guard let clip = ConcealedPasteboard.readNonConcealedStringForUserPaste() else {
            toast = ConcealedPasteboard.isConcealed()
                ? "受保护的保险箱内容不可直接粘贴翻译"
                : "剪贴板是空的"
            return
        }
        controller.transcript = clip
        controller.translateCurrentTranscript(aiConfig: appState.aiConfig)
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
        toast = label
    }
}
