import AVFoundation
import Speech
import UIKit

/// 键盘内嵌「🎙️ 实时语音转换」面板（v5.6 新增，彻底留在键盘内部，不跳出微信/抖音！）：
/// - 支持 6 种实时模式：说中文→英语 / 说英语→中文 / 中→日 / 日→中 / 中文速记 / 英文速记；
/// - 双引擎自动无缝衔接：
///   1. 优先连接已预热的后台语音引擎（App Group + 本机 127.0.0.1 双通道，零跳转实时回传语音与双语译文）；
///   2. 后台引擎未预热时自动尝试键盘内直录（`AVAudioEngine` + `SFSpeechRecognizer`）；
///   3. 若被 iOS 沙盒拦截（`561017449`），在面板内给出「⚡ 一键激活后台语音引擎（仅需点 1 次）」按钮。
final class VoiceInputPanelView: UIView {
    var onInsertText: ((String) -> Void)?
    var onWarmUpHostVoiceEngine: (() -> Void)?
    var onOpenFullVoiceWorkbench: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onClose: (() -> Void)?

    private var theme: ResolvedTheme?
    private var hasFullAccess = false
    private var mode: VoiceTranslateMode = .zhToEn

    // 录音与转写状态
    private var isRecording = false
    private var usingHostBridge = false
    private var hostEngineWarm = false
    private var transcriptText = ""
    private var translatedText = ""
    private var statusMessage = "点击下方「开始说话」，在键盘内直接实时语音转换"

    // 键盘内直录引擎（Tier 2）
    private let localAudioEngine = AVAudioEngine()
    private var localRequest: SFSpeechAudioBufferRecognitionRequest?
    private var localTask: SFSpeechRecognitionTask?
    private let aiClient = AIClient(timeout: 25)
    private var localTranslateDebounce: Task<Void, Never>?
    private var localTranslateStream: Task<Void, Never>?
    private var lastLocalTranslatedSource = ""

    // 后台语音桥接监听（Tier 1）
    private var stateObserver: AppGroupNotifications.Observer?
    private var bridgePollTimer: Timer?

    // UI 控件
    private let modeScroll = LingxiScrollView()
    private let modeStack = UIStackView()
    private let flipButton = ActionClosureButton(type: .system)
    private let closeButton = ActionClosureButton(type: .system)

    private let statusPillLabel = UILabel()
    private let levelBarTrack = UIView()
    private let levelBarFill = UIView()
    private var currentAudioLevel: CGFloat = 0

    private let sourceCard = UIView()
    private let sourceLabel = UILabel()
    private let resultTextView = UITextView()

    private let activationBar = UIStackView()
    private let activateEngineButton = ActionClosureButton(type: .system)
    private let fallbackWorkbenchButton = ActionClosureButton(type: .system)

    private let bottomBar = UIStackView()
    private let recordButton = ActionClosureButton(type: .system)
    private let clearButton = ActionClosureButton(type: .system)
    private let copyButton = ActionClosureButton(type: .system)
    private let insertButton = ActionClosureButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        stateObserver = AppGroupNotifications.Observer(name: AppGroupNotifications.voiceState) { [weak self] in
            self?.syncFromSharedStateIfAvailable()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        bridgePollTimer?.invalidate()
        localTranslateDebounce?.cancel()
        localTranslateStream?.cancel()
        if localAudioEngine.isRunning {
            localAudioEngine.stop()
            localAudioEngine.inputNode.removeTap(onBus: 0)
        }
        localRequest?.endAudio()
        localTask?.cancel()
    }

    private func setupViews() {
        modeScroll.showsHorizontalScrollIndicator = false
        addSubview(modeScroll)
        modeStack.axis = .horizontal
        modeStack.spacing = 6
        modeStack.alignment = .center
        modeScroll.addSubview(modeStack)

        flipButton.setTitle("⇄", for: .normal)
        flipButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        flipButton.layer.cornerRadius = 10
        flipButton.layer.cornerCurve = .continuous
        flipButton.accessibilityLabel = "一键互换语种方向"
        flipButton.actionHandler = { [weak self] in
            guard let self else { return }
            self.selectMode(self.mode.flipped)
        }
        addSubview(flipButton)

        closeButton.setTitle("返回", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        closeButton.layer.cornerRadius = 10
        closeButton.layer.cornerCurve = .continuous
        closeButton.actionHandler = { [weak self] in
            self?.stopAllRecording(runFinalTranslate: false)
            self?.onClose?()
        }
        addSubview(closeButton)

        statusPillLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        statusPillLabel.numberOfLines = 1
        statusPillLabel.lineBreakMode = .byTruncatingTail
        addSubview(statusPillLabel)

        levelBarTrack.layer.cornerRadius = 2.5
        levelBarTrack.clipsToBounds = true
        addSubview(levelBarTrack)
        levelBarFill.layer.cornerRadius = 2.5
        levelBarTrack.addSubview(levelBarFill)

        sourceCard.layer.cornerRadius = 9
        sourceCard.layer.cornerCurve = .continuous
        addSubview(sourceCard)

        sourceLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        sourceLabel.numberOfLines = 2
        sourceLabel.lineBreakMode = .byTruncatingHead
        sourceCard.addSubview(sourceLabel)

        resultTextView.isEditable = false
        resultTextView.isSelectable = true
        resultTextView.font = .systemFont(ofSize: 14.5, weight: .medium)
        resultTextView.layer.cornerRadius = 11
        resultTextView.layer.cornerCurve = .continuous
        resultTextView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        addSubview(resultTextView)

        activationBar.axis = .horizontal
        activationBar.spacing = 6
        activationBar.distribution = .fill
        activationBar.isHidden = true
        addSubview(activationBar)

        activateEngineButton.setTitle("⚡ 激活键盘内语音（仅需 1 次）", for: .normal)
        activateEngineButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        activateEngineButton.layer.cornerRadius = 9
        activateEngineButton.layer.cornerCurve = .continuous
        activateEngineButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        activateEngineButton.actionHandler = { [weak self] in
            self?.onWarmUpHostVoiceEngine?()
        }
        activationBar.addArrangedSubview(activateEngineButton)

        fallbackWorkbenchButton.setTitle("全屏同传", for: .normal)
        fallbackWorkbenchButton.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        fallbackWorkbenchButton.layer.cornerRadius = 9
        fallbackWorkbenchButton.layer.cornerCurve = .continuous
        fallbackWorkbenchButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
        fallbackWorkbenchButton.setContentHuggingPriority(.required, for: .horizontal)
        fallbackWorkbenchButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        fallbackWorkbenchButton.actionHandler = { [weak self] in
            self?.onOpenFullVoiceWorkbench?()
        }
        activationBar.addArrangedSubview(fallbackWorkbenchButton)

        bottomBar.axis = .horizontal
        bottomBar.spacing = 6
        bottomBar.distribution = .fill
        addSubview(bottomBar)

        recordButton.setTitle("🎙️ 开始说话", for: .normal)
        recordButton.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .bold)
        recordButton.layer.cornerRadius = 10
        recordButton.layer.cornerCurve = .continuous
        recordButton.actionHandler = { [weak self] in self?.toggleRecording() }

        clearButton.setTitle("清空", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        clearButton.layer.cornerRadius = 10
        clearButton.layer.cornerCurve = .continuous
        clearButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
        clearButton.actionHandler = { [weak self] in self?.handleClear() }

        copyButton.setTitle("复制", for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        copyButton.layer.cornerRadius = 10
        copyButton.layer.cornerCurve = .continuous
        copyButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        copyButton.actionHandler = { [weak self] in self?.handleCopy() }

        insertButton.setTitle("插入上屏", for: .normal)
        insertButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        insertButton.layer.cornerRadius = 10
        insertButton.layer.cornerCurve = .continuous
        insertButton.widthAnchor.constraint(equalToConstant: 78).isActive = true
        insertButton.actionHandler = { [weak self] in self?.handleInsert() }

        [recordButton, clearButton, copyButton, insertButton].forEach { bottomBar.addArrangedSubview($0) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 8
        let topY: CGFloat = 7
        let topH: CGFloat = 30
        let closeW: CGFloat = 44
        let flipW: CGFloat = 34

        closeButton.frame = CGRect(x: bounds.width - pad - closeW, y: topY, width: closeW, height: topH)
        flipButton.frame = CGRect(x: closeButton.frame.minX - 5 - flipW, y: topY, width: flipW, height: topH)

        let modeW = max(80, flipButton.frame.minX - 6)
        modeScroll.frame = CGRect(x: 0, y: topY, width: modeW, height: topH)
        let natW = ceil(modeStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
        modeStack.frame = CGRect(x: pad, y: 0, width: natW, height: topH)
        modeScroll.contentSize = CGSize(width: max(modeW, natW + pad * 2), height: topH)

        let statusY = modeScroll.frame.maxY + 5
        statusPillLabel.frame = CGRect(x: pad + 2, y: statusY, width: bounds.width - pad * 2 - 4, height: 16)

        let lvlY = statusPillLabel.frame.maxY + 3
        let trackW = max(40, bounds.width - pad * 2)
        levelBarTrack.frame = CGRect(x: pad, y: lvlY, width: trackW, height: 5)
        let fillW = isRecording ? max(8, trackW * min(1, max(0.06, currentAudioLevel))) : 0
        levelBarFill.frame = CGRect(x: 0, y: 0, width: fillW, height: 5)

        let bottomH: CGFloat = 38
        bottomBar.frame = CGRect(x: pad, y: bounds.height - bottomH - 7, width: bounds.width - pad * 2, height: bottomH)

        var contentBottom = bottomBar.frame.minY
        if !activationBar.isHidden {
            let actH: CGFloat = 34
            activationBar.frame = CGRect(x: pad, y: contentBottom - actH - 6, width: bounds.width - pad * 2, height: actH)
            contentBottom = activationBar.frame.minY
        }

        let srcY = levelBarTrack.frame.maxY + 6
        let srcH: CGFloat = 38
        sourceCard.frame = CGRect(x: pad, y: srcY, width: bounds.width - pad * 2, height: srcH)
        sourceLabel.frame = sourceCard.bounds.insetBy(dx: 9, dy: 4)

        let resY = sourceCard.frame.maxY + 6
        resultTextView.frame = CGRect(x: pad, y: resY, width: bounds.width - pad * 2, height: max(46, contentBottom - resY - 6))
    }

    // MARK: - 生命周期与配置

    func prepare(theme: ResolvedTheme, hasFullAccess: Bool) {
        self.theme = theme
        self.hasFullAccess = hasFullAccess
        applyTheme(theme)
        rebuildModePills()
        refreshDisplays()
        probeHostVoiceEngine()
    }

    func applyTheme(_ theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.canvasTop.withAlphaComponent(0.98)

        flipButton.backgroundColor = theme.specialKeyFill
        flipButton.setTitleColor(theme.candidateHighlight, for: .normal)
        closeButton.backgroundColor = theme.specialKeyFill
        closeButton.setTitleColor(theme.keyText, for: .normal)

        statusPillLabel.textColor = theme.keyHintText
        levelBarTrack.backgroundColor = theme.specialKeyFill
        levelBarFill.backgroundColor = isRecording ? .systemRed : theme.accentFill

        sourceCard.backgroundColor = theme.specialKeyFill.withAlphaComponent(0.65)
        sourceLabel.textColor = theme.keyText

        resultTextView.backgroundColor = theme.keyFill.withAlphaComponent(0.96)
        resultTextView.textColor = theme.keyText
        resultTextView.tintColor = theme.accentFill

        activateEngineButton.backgroundColor = theme.accentFill
        activateEngineButton.setTitleColor(theme.accentText, for: .normal)
        fallbackWorkbenchButton.backgroundColor = theme.specialKeyFill
        fallbackWorkbenchButton.setTitleColor(theme.keyText, for: .normal)

        updateRecordButtonStyle()
        clearButton.backgroundColor = theme.specialKeyFill
        clearButton.setTitleColor(theme.keyText, for: .normal)
        copyButton.backgroundColor = theme.specialKeyFill
        copyButton.setTitleColor(theme.keyText, for: .normal)
        insertButton.backgroundColor = theme.accentFill
        insertButton.setTitleColor(theme.accentText, for: .normal)
    }

    func stopAllRecording(runFinalTranslate: Bool = false) {
        bridgePollTimer?.invalidate()
        bridgePollTimer = nil
        if usingHostBridge && isRecording {
            let cmd = VoiceIPCCommand(action: .stop, modeRaw: mode.rawValue)
            Task { _ = await VoiceIPCBridge.sendCommandToHost(cmd) }
        }
        stopLocalRecording(runFinalTranslate: runFinalTranslate)
        isRecording = false
        currentAudioLevel = 0
        updateRecordButtonStyle()
        setNeedsLayout()
    }

    private func rebuildModePills() {
        modeStack.arrangedSubviews.forEach {
            modeStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }
        for m in VoiceTranslateMode.allCases {
            let active = (m == mode)
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(m.pillTitle, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            btn.backgroundColor = active ? theme.accentFill : theme.keyFill
            btn.setTitleColor(active ? theme.accentText : theme.keyText, for: .normal)
            btn.layer.cornerRadius = 13
            btn.layer.cornerCurve = .continuous
            btn.layer.borderWidth = active ? 0 : 0.5
            btn.layer.borderColor = theme.keyBorder.cgColor
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            btn.actionHandler = { [weak self] in
                self?.selectMode(m)
            }
            modeStack.addArrangedSubview(btn)
        }
        setNeedsLayout()
    }

    private func selectMode(_ newMode: VoiceTranslateMode) {
        guard mode != newMode else { return }
        if isRecording { stopAllRecording(runFinalTranslate: false) }
        mode = newMode
        transcriptText = ""
        translatedText = ""
        lastLocalTranslatedSource = ""
        statusMessage = "已切至「\(newMode.shortTitle)」· 点下方直接开口说话"
        rebuildModePills()
        refreshDisplays()
    }

    // MARK: - 探活后台语音引擎 & 开始/停止录音

    private func probeHostVoiceEngine() {
        Task { [weak self] in
            let state = await VoiceIPCBridge.fetchStateFromHost()
            await MainActor.run { [weak self] in
                guard let self else { return }
                let warm = state?.isHeartbeatFresh == true
                self.hostEngineWarm = warm
                if warm {
                    self.activationBar.isHidden = true
                    if !self.isRecording && self.transcriptText.isEmpty {
                        self.statusMessage = "✓ 后台语音引擎已就绪 · 在键盘内直接点「开始说话」"
                    }
                    self.refreshDisplays()
                }
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopCurrentRecording()
        } else {
            startRecordingSmart()
        }
    }

    private func startRecordingSmart() {
        guard hasFullAccess else {
            statusMessage = "⚠️ 需开启「允许完全访问」才可在键盘内语音转换"
            activationBar.isHidden = false
            activateEngineButton.setTitle("🔓 前往开启完全访问权限", for: .normal)
            refreshDisplays()
            return
        }

        statusMessage = "🎙️ 正在启动键盘内语音引擎…"
        refreshDisplays()

        Task { [weak self] in
            guard let self else { return }
            // 1. 优先连接已预热的后台语音引擎（零跳转，对齐 讯飞 / 豆包 / Wispr Flow）
            if let probed = await VoiceIPCBridge.fetchStateFromHost(), probed.isHeartbeatFresh {
                let cmd = VoiceIPCCommand(action: .start, modeRaw: self.mode.rawValue)
                let updated = await VoiceIPCBridge.sendCommandToHost(cmd)
                await MainActor.run {
                    self.hostEngineWarm = true
                    self.usingHostBridge = true
                    self.isRecording = true
                    self.activationBar.isHidden = true
                    self.transcriptText = updated?.transcript ?? ""
                    self.translatedText = updated?.translatedText ?? ""
                    self.statusMessage = "🎙️ 正在听「\(self.mode.sourceLanguageLabel)」· 说完点停止或直接插入"
                    self.startBridgePollTimer()
                    self.updateRecordButtonStyle()
                    self.refreshDisplays()
                }
                return
            }

            // 2. 尝试键盘扩展内原生直录（iOS 17/18 已授权麦克风设备可直接工作）
            await MainActor.run {
                self.startLocalInKeyboardRecording()
            }
        }
    }

    private func stopCurrentRecording() {
        if usingHostBridge {
            isRecording = false
            statusMessage = "✨ 正在完成最终校译…"
            updateRecordButtonStyle()
            refreshDisplays()
            let cmd = VoiceIPCCommand(action: .stop, modeRaw: mode.rawValue)
            Task { [weak self] in
                if let st = await VoiceIPCBridge.sendCommandToHost(cmd) {
                    await MainActor.run {
                        self?.applyHostState(st)
                    }
                }
            }
            // 再短轮询 2 秒等待最终 AI 译文返回后停止
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, !self.isRecording else { return }
                self.bridgePollTimer?.invalidate()
                self.bridgePollTimer = nil
            }
        } else {
            stopLocalRecording(runFinalTranslate: true)
        }
    }

    // MARK: - Tier 1: 后台语音引擎实时同步

    private func startBridgePollTimer() {
        bridgePollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.22, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let st = await VoiceIPCBridge.fetchStateFromHost() else { return }
                await MainActor.run {
                    self?.applyHostState(st)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        bridgePollTimer = timer
    }

    private func syncFromSharedStateIfAvailable() {
        guard !isHidden, let st = VoiceIPCBridge.readStateFromShared() else { return }
        applyHostState(st)
    }

    private func applyHostState(_ st: VoiceIPCState) {
        hostEngineWarm = st.isHeartbeatFresh
        if usingHostBridge || st.isRecording {
            isRecording = st.isRecording
            transcriptText = st.transcript
            translatedText = AITextSanitizer.clean(st.translatedText, streaming: st.isTranslating)
            currentAudioLevel = CGFloat(st.audioLevel)
            if let err = st.errorText, !err.isEmpty {
                statusMessage = "⚠️ \(err)"
            } else if !st.statusText.isEmpty {
                statusMessage = st.statusText
            }
            updateRecordButtonStyle()
            refreshDisplays()
        }
    }

    // MARK: - Tier 2: 键盘扩展内原生直录（AVAudioEngine + SFSpeechRecognizer）

    private func startLocalInKeyboardRecording() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: mode.sourceLocaleID)),
              recognizer.isAvailable else {
            showWarmUpRequired(reason: "当前系统未在键盘进程开放「\(mode.sourceLanguageLabel)」语音直录")
            return
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioSession.sharedInstance().recordPermission == .granted else {
            showWarmUpRequired(reason: "尚未激活后台语音引擎或未授权麦克风/语音权限")
            return
        }

        stopLocalRecording(runFinalTranslate: false)
        transcriptText = ""
        translatedText = ""
        lastLocalTranslatedSource = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if #available(iOS 16.0, *) {
                req.addsPunctuation = true
            }
            localRequest = req

            let node = localAudioEngine.inputNode
            node.removeTap(onBus: 0)
            let fmt = node.outputFormat(forBus: 0)
            node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                req.append(buf)
                let lvl = Self.computeLevel(buf)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isRecording, !self.usingHostBridge else { return }
                    self.currentAudioLevel = lvl
                    self.setNeedsLayout()
                }
            }
            localAudioEngine.prepare()
            try localAudioEngine.start()

            usingHostBridge = false
            isRecording = true
            activationBar.isHidden = true
            statusMessage = "🎙️ 正在键盘内直录「\(mode.sourceLanguageLabel)」…"
            updateRecordButtonStyle()
            refreshDisplays()

            localTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcriptText = result.bestTranscription.formattedString
                        self.scheduleLocalTranslate(for: self.transcriptText)
                        self.refreshDisplays()
                        if result.isFinal {
                            self.stopLocalRecording(runFinalTranslate: true)
                        }
                    } else if let error, self.isRecording {
                        let nsErr = error as NSError
                        if nsErr.code != 216 && nsErr.code != 1110 {
                            self.statusMessage = "⚠️ 识别中断：\(error.localizedDescription)"
                        }
                        self.stopLocalRecording(runFinalTranslate: true)
                    }
                }
            }
        } catch {
            // iOS 沙盒拦截键盘直录（典型 OSStatus 561017449 / !pri）：引导一键激活后台语音引擎（仅需点 1 次！）
            showWarmUpRequired(reason: "iOS 要求先一键激活后台语音引擎，激活后即可在键盘内无限次直接说话不跳出")
        }
    }

    private func showWarmUpRequired(reason: String) {
        isRecording = false
        usingHostBridge = false
        activationBar.isHidden = false
        activateEngineButton.setTitle("⚡ 一键激活后台语音（仅需 1 次）", for: .normal)
        statusMessage = "ℹ️ \(reason)"
        updateRecordButtonStyle()
        refreshDisplays()
    }

    private func stopLocalRecording(runFinalTranslate: Bool) {
        if localAudioEngine.isRunning {
            localAudioEngine.stop()
            localAudioEngine.inputNode.removeTap(onBus: 0)
        }
        localRequest?.endAudio()
        localRequest = nil
        localTask?.cancel()
        localTask = nil
        if !usingHostBridge {
            isRecording = false
            currentAudioLevel = 0
            updateRecordButtonStyle()
            if runFinalTranslate {
                runLocalTranslateNow(for: transcriptText)
            }
            refreshDisplays()
        }
    }

    private func scheduleLocalTranslate(for source: String) {
        localTranslateDebounce?.cancel()
        let clean = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        localTranslateDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                self.runLocalTranslateNow(for: clean)
            }
        }
    }

    private func runLocalTranslateNow(for source: String) {
        let clean = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if clean == lastLocalTranslatedSource && !translatedText.isEmpty { return }
        let cfg = AIConfig.load()
        guard cfg.isConfigured else {
            if !mode.isTranslationMode {
                translatedText = AITextSanitizer.clean(clean, streaming: false)
            } else {
                statusMessage = "✓ 语音已转文字（配置 AI Key 后自动双语互译）"
            }
            refreshDisplays()
            return
        }

        localTranslateStream?.cancel()
        let modeSnap = mode
        localTranslateStream = Task { [weak self] in
            guard let self else { return }
            var acc = ""
            var lastFlush = CACurrentMediaTime()
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
                    let now = CACurrentMediaTime()
                    if now - lastFlush >= 0.05 {
                        lastFlush = now
                        let cleaned = AITextSanitizer.clean(acc, streaming: true)
                        await MainActor.run {
                            self.translatedText = cleaned
                            self.refreshDisplays()
                        }
                    }
                }
                let finalClean = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    self.translatedText = finalClean
                    self.lastLocalTranslatedSource = clean
                    self.statusMessage = "✓ 转换完成 · 点「插入上屏」直接输入"
                    self.refreshDisplays()
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    self.statusMessage = "⚠️ 翻译失败：\(error.localizedDescription)"
                    self.refreshDisplays()
                }
            }
        }
    }

    // MARK: - UI 刷新与按钮动作

    private var preferredOutputText: String {
        let t = AITextSanitizer.clean(translatedText, streaming: false)
        if !t.isEmpty { return t }
        return AITextSanitizer.clean(transcriptText, streaming: false)
    }

    private func updateRecordButtonStyle() {
        guard let theme else { return }
        if isRecording {
            recordButton.setTitle("⏹ 停止说话", for: .normal)
            recordButton.backgroundColor = .systemRed
            recordButton.setTitleColor(.white, for: .normal)
        } else {
            recordButton.setTitle("🎙️ 开始说话", for: .normal)
            recordButton.backgroundColor = theme.accentFill
            recordButton.setTitleColor(theme.accentText, for: .normal)
        }
        levelBarFill.backgroundColor = isRecording ? .systemRed : theme.accentFill
    }

    private func refreshDisplays() {
        statusPillLabel.text = statusMessage
        if transcriptText.isEmpty {
            sourceLabel.text = "🎙️ \(mode.sourceLanguageLabel)原文：等待开口说话…"
            sourceLabel.textColor = theme?.keyHintText ?? .secondaryLabel
        } else {
            sourceLabel.text = "🎙️ \(transcriptText)"
            sourceLabel.textColor = theme?.keyText ?? .label
        }

        let displayRes = preferredOutputText
        if displayRes.isEmpty {
            resultTextView.text = hostEngineWarm
                ? "✓ 后台语音引擎在线（无需切出 App）\n点左下「🎙️ 开始说话」，说完自动「\(mode.shortTitle)」并支持一键插入上屏。"
                : "在键盘内直接实时语音转换（\(mode.shortTitle)）：\n• 点左下「🎙️ 开始说话」开始录音\n• 若首次提示激活后台引擎，点一次激活按钮后即可在任意 App 键盘内无限次直接说话不跳转。"
            resultTextView.textColor = theme?.keyHintText ?? .secondaryLabel
        } else {
            resultTextView.text = displayRes
            resultTextView.textColor = theme?.keyText ?? .label
        }

        let hasOut = !displayRes.isEmpty
        copyButton.isEnabled = hasOut
        copyButton.alpha = hasOut ? 1.0 : 0.45
        insertButton.isEnabled = hasOut
        insertButton.alpha = hasOut ? 1.0 : 0.45
        setNeedsLayout()
    }

    private func handleClear() {
        stopAllRecording(runFinalTranslate: false)
        transcriptText = ""
        translatedText = ""
        lastLocalTranslatedSource = ""
        statusMessage = "已清空 · 点击「开始说话」重新录入"
        if hostEngineWarm {
            let cmd = VoiceIPCCommand(action: .clear, modeRaw: mode.rawValue)
            Task { _ = await VoiceIPCBridge.sendCommandToHost(cmd) }
        }
        refreshDisplays()
    }

    private func handleCopy() {
        let out = preferredOutputText
        guard !out.isEmpty else { return }
        UIPasteboard.general.string = out
        _ = ClipboardStore.record(out)
        copyButton.setTitle("✓已复", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.setTitle("复制", for: .normal)
        }
    }

    private func handleInsert() {
        let out = preferredOutputText
        guard !out.isEmpty else { return }
        stopAllRecording(runFinalTranslate: false)
        onInsertText?(out)
    }

    private static func computeLevel(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return CGFloat(min(1.0, max(0.0, sqrt(sum / Float(n)) * 10.0)))
    }
}
