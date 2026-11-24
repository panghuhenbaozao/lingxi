import AVFoundation
import Speech
import UIKit

/// 键盘内嵌「🎙️ 实时语音转换」面板（v5.7.0 真正键盘内免跳转直录版）：
/// - 支持 6 种实时模式：说中文→英语 / 说英语→中文 / 中→日 / 日→中 / 中文速记 / 英文速记；
/// - 真正无需跳出微信/抖音、不依赖 App Group、不依赖 127.0.0.1 回环的键盘内直录架构：
///   1. 优先复用已预热的后台引擎（若 App Group 后台已在线）；
///   2. 否则直接启动内嵌 1×1 `WebKitAudioCaptureEngine`（`WKWebView` + `getUserMedia` + `AudioContext` 16kHz PCM，绕过 `AVAudioEngine` `561017449` 沙盒拦截！）；
///   3. 实时 16kHz PCM 流同时送入 Apple `SFSpeechAudioBufferRecognitionRequest`（边说边出字 + 实时流式双语翻译），并在停止后若端侧未授权/未出字时自动把 WAV 音频交给 Gemini / Whisper 云端直译兜底！
///   4. 任何权限不足或系统限制均即时给出明确原因与一键「全屏同传」「✨ 译框内听写」兜底，绝不静默没反应！
final class VoiceInputPanelView: UIView {
    var onInsertText: ((String) -> Void)?
    var onReplaceBeforeCursor: ((Int, String) -> Void)?
    var onFetchHostInputContext: (() -> String)?
    var onWarmUpHostVoiceEngine: ((@escaping (Bool) -> Void) -> Void)?
    var onOpenFullVoiceWorkbench: ((VoiceTranslateMode, @escaping (Bool) -> Void) -> Void)?
    var onOpenPermissions: ((@escaping (Bool) -> Void) -> Void)?
    var onClose: (() -> Void)?

    private var theme: ResolvedTheme?
    private var hasFullAccess = false
    private var mode: VoiceTranslateMode = .zhToEn

    // 录音与转写状态
    private enum ActiveCaptureSource {
        case none
        case webKitDirect
        case hostBridge
    }
    private var captureSource: ActiveCaptureSource = .none
    private var isRecording: Bool { captureSource != .none }
    private var isStartingMic = false
    private var hostEngineWarm = false
    private var isProbing = false
    private var transcriptText = ""
    private var translatedText = ""
    private var pendingReplaceCount = 0
    private var statusMessage = "点击左下「🎙️ 开始说话」，直接在键盘内实时语音转换"

    // Tier 1: 键盘内免跳转 WKWebView 麦克风 + SFSpeechAudioBufferRecognitionRequest（零 AVAudioEngine，彻底绕过 561017449）
    private var webCaptureEngine: WebKitAudioCaptureEngine?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private let pcmFormat16k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    private var liveTranslateDebounceTask: Task<Void, Never>?
    private var liveTranslateStreamTask: Task<Void, Never>?
    private var lastTranslatedSourceSnapshot = ""
    private var recordedDurationStart: CFTimeInterval = 0

    // 通用 AI 翻译 / 音频云端识别客户端
    private let aiClient = AIClient(timeout: 30)

    // Tier 2: 后台语音桥接监听（App Group 已通时复用）
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

    private let utilityBar = UIStackView()
    private let dictationConvertBtn = ActionClosureButton(type: .system)
    private let fullWorkbenchBtn = ActionClosureButton(type: .system)

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
        liveTranslateDebounceTask?.cancel()
        liveTranslateStreamTask?.cancel()
        speechRequest?.endAudio()
        speechTask?.cancel()
        webCaptureEngine?.teardown()
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
            self?.teardownWebAudio()
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
        resultTextView.font = .systemFont(ofSize: 14, weight: .medium)
        resultTextView.layer.cornerRadius = 11
        resultTextView.layer.cornerCurve = .continuous
        resultTextView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        addSubview(resultTextView)

        utilityBar.axis = .horizontal
        utilityBar.spacing = 6
        utilityBar.distribution = .fill
        addSubview(utilityBar)

        dictationConvertBtn.setTitle("✨ 译框内听写", for: .normal)
        dictationConvertBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        dictationConvertBtn.layer.cornerRadius = 9
        dictationConvertBtn.layer.cornerCurve = .continuous
        dictationConvertBtn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        dictationConvertBtn.actionHandler = { [weak self] in
            self?.handleDictationConvertTap()
        }
        utilityBar.addArrangedSubview(dictationConvertBtn)

        fullWorkbenchBtn.setTitle("全屏同传", for: .normal)
        fullWorkbenchBtn.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        fullWorkbenchBtn.layer.cornerRadius = 9
        fullWorkbenchBtn.layer.cornerCurve = .continuous
        fullWorkbenchBtn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        fullWorkbenchBtn.setContentHuggingPriority(.required, for: .horizontal)
        fullWorkbenchBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        fullWorkbenchBtn.actionHandler = { [weak self] in
            self?.triggerFullWorkbenchWithFeedback()
        }
        utilityBar.addArrangedSubview(fullWorkbenchBtn)

        bottomBar.axis = .horizontal
        bottomBar.spacing = 6
        bottomBar.distribution = .fill
        addSubview(bottomBar)

        recordButton.setTitle("🎙️ 开始说话", for: .normal)
        recordButton.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .bold)
        recordButton.layer.cornerRadius = 10
        recordButton.layer.cornerCurve = .continuous
        recordButton.actionHandler = { [weak self] in self?.handlePrimaryRecordTap() }

        clearButton.setTitle("清空", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        clearButton.layer.cornerRadius = 10
        clearButton.layer.cornerCurve = .continuous
        clearButton.widthAnchor.constraint(equalToConstant: 46).isActive = true
        clearButton.actionHandler = { [weak self] in self?.handleClear() }

        copyButton.setTitle("复制", for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        copyButton.layer.cornerRadius = 10
        copyButton.layer.cornerCurve = .continuous
        copyButton.widthAnchor.constraint(equalToConstant: 50).isActive = true
        copyButton.actionHandler = { [weak self] in self?.handleCopy() }

        insertButton.setTitle("插入上屏", for: .normal)
        insertButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        insertButton.layer.cornerRadius = 10
        insertButton.layer.cornerCurve = .continuous
        insertButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
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

        let utilH: CGFloat = 32
        utilityBar.frame = CGRect(x: pad, y: bottomBar.frame.minY - utilH - 6, width: bounds.width - pad * 2, height: utilH)

        let srcY = levelBarTrack.frame.maxY + 5
        let srcH: CGFloat = 34
        sourceCard.frame = CGRect(x: pad, y: srcY, width: bounds.width - pad * 2, height: srcH)
        sourceLabel.frame = sourceCard.bounds.insetBy(dx: 9, dy: 4)

        let resY = sourceCard.frame.maxY + 5
        let availH = max(24, utilityBar.frame.minY - resY - 5)
        resultTextView.frame = CGRect(x: pad, y: resY, width: bounds.width - pad * 2, height: availH)
    }

    // MARK: - 生命周期与配置

    func prepare(theme: ResolvedTheme, hasFullAccess: Bool) {
        self.theme = theme
        self.hasFullAccess = hasFullAccess
        let sharedWarm = VoiceIPCBridge.readStateFromShared()?.isHeartbeatFresh == true
        self.hostEngineWarm = sharedWarm
        applyTheme(theme)
        rebuildModePills()
        if !hasFullAccess {
            statusMessage = "⚠️ 请先开启「允许完全访问」权限，即可在键盘内直接录音并实时互译"
        } else if !isRecording {
            statusMessage = "🟢 键盘内语音已就绪 · 直接点左下「🎙️ 开始说话」（无需跳出 App）"
        }
        updateRecordButtonStyle()
        refreshDisplays()
        probeHostVoiceEngine()
        // 提前在后台预热隐藏 WKWebView（几乎 0 内存），点「开始说话」0 延迟开麦
        if hasFullAccess && !sharedWarm {
            ensureWebCaptureEngine().prewarmIfNeeded()
        }
    }

    func refreshEngineStatus(hasFullAccess: Bool) {
        self.hasFullAccess = hasFullAccess
        probeHostVoiceEngine()
        updateRecordButtonStyle()
        refreshDisplays()
    }

    func teardownWebAudio() {
        webCaptureEngine?.teardown()
        webCaptureEngine = nil
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

        dictationConvertBtn.backgroundColor = theme.accentFill.withAlphaComponent(0.16)
        dictationConvertBtn.setTitleColor(theme.candidateHighlight, for: .normal)
        fullWorkbenchBtn.backgroundColor = theme.specialKeyFill
        fullWorkbenchBtn.setTitleColor(theme.keyText, for: .normal)

        updateRecordButtonStyle()
        clearButton.backgroundColor = theme.specialKeyFill
        clearButton.setTitleColor(theme.keyText, for: .normal)
        copyButton.backgroundColor = theme.specialKeyFill
        copyButton.setTitleColor(theme.keyText, for: .normal)
        insertButton.backgroundColor = theme.accentFill
        insertButton.setTitleColor(theme.accentText, for: .normal)
    }

    func stopAllRecording(runFinalTranslate: Bool = false) {
        isStartingMic = false
        bridgePollTimer?.invalidate()
        bridgePollTimer = nil
        liveTranslateDebounceTask?.cancel()
        if !runFinalTranslate {
            liveTranslateStreamTask?.cancel()
        }
        switch captureSource {
        case .hostBridge:
            let cmd = VoiceIPCCommand(action: .stop, modeRaw: mode.rawValue)
            Task { _ = await VoiceIPCBridge.sendCommandToHost(cmd) }
        case .webKitDirect:
            _ = webCaptureEngine?.stopCapture()
            stopSpeechRecognizer(finish: runFinalTranslate)
        case .none:
            _ = webCaptureEngine?.stopCapture()
            stopSpeechRecognizer(finish: false)
        }
        captureSource = .none
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
        if isRecording || isStartingMic { stopAllRecording(runFinalTranslate: false) }
        mode = newMode
        transcriptText = ""
        translatedText = ""
        lastTranslatedSourceSnapshot = ""
        pendingReplaceCount = 0
        statusMessage = "已切至「\(newMode.shortTitle)」· 点左下「🎙️ 开始说话」直接开口"
        rebuildModePills()
        refreshDisplays()
    }

    // MARK: - 主录音按钮（永不卡死在激活页，点击即真正在键盘内开麦！）

    private func handlePrimaryRecordTap() {
        if isRecording || isStartingMic {
            stopCurrentRecording()
            return
        }
        if !hasFullAccess {
            statusMessage = "🔓 正在打开权限设置…"
            refreshDisplays()
            onOpenPermissions? { [weak self] opened in
                guard let self, !opened else { return }
                self.statusMessage = "⚠️ 请前往「设置 → 通用 → 键盘 → 灵犀输入法」打开「允许完全访问」"
                self.refreshDisplays()
            }
            return
        }

        // 若后台主 App 引擎已在线（App Group 已打通），优先复用；否则直接启动键盘内免跳转 WebKit 麦克风！
        if hostEngineWarm {
            startHostBridgeRecording()
        } else {
            startWebKitDirectInKeyboardRecording()
        }
    }

    // MARK: - Tier 1: 键盘内免跳转 WebKit 麦克风 + SFSpeechAudioBuffer + 云端 WAV 双引擎

    private func ensureWebCaptureEngine() -> WebKitAudioCaptureEngine {
        if let existing = webCaptureEngine { return existing }
        let engine = WebKitAudioCaptureEngine(hostView: self)
        engine.onStarted = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isStartingMic else { return }
                self.isStartingMic = false
                self.captureSource = .webKitDirect
                self.recordedDurationStart = CACurrentMediaTime()
                let hasLiveASR = (self.speechRequest != nil)
                self.statusMessage = hasLiveASR
                    ? "🎙️ 正在键盘内实时收音「\(self.mode.sourceLanguageLabel)」· 说完点停止"
                    : "🎙️ 正在键盘内录音「\(self.mode.sourceLanguageLabel)」· 说完点停止即自动识别翻译"
                self.updateRecordButtonStyle()
                self.refreshDisplays()
            }
        }
        engine.onPCMChunk = { [weak self] pcmData, rms in
            self?.handleWebKitPCMChunk(pcmData, rms: rms)
        }
        engine.onError = { [weak self] code, readable in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isStartingMic = false
                self.captureSource = .none
                self.currentAudioLevel = 0
                self.stopSpeechRecognizer(finish: false)
                self.statusMessage = "⚠️ \(readable)"
                self.resultTextView.text = "⚠️ 键盘内麦克风未启动（\(code)）：\(readable)\n\n请任选一种立即可用方式：\n1. 点下方「全屏同传」立即在灵犀主界面开麦授权并实时互译（说完自动复制回微信）；\n2. 或点手机右下角苹果系统麦克风 🎙️ 说完话，再点「✨ 译框内听写」免跳转原地秒译！"
                self.resultTextView.textColor = self.theme?.keyText ?? .label
                self.updateRecordButtonStyle()
                self.setNeedsLayout()
            }
        }
        self.webCaptureEngine = engine
        return engine
    }

    private func startWebKitDirectInKeyboardRecording() {
        stopAllRecording(runFinalTranslate: false)
        isStartingMic = true
        transcriptText = ""
        translatedText = ""
        lastTranslatedSourceSnapshot = ""
        pendingReplaceCount = 0
        currentAudioLevel = 0
        statusMessage = "🎙️ 正在打开键盘内麦克风…"
        updateRecordButtonStyle()
        refreshDisplays()

        // 同时尝试挂载 Apple SFSpeechAudioBufferRecognitionRequest（纯内存推 PCM，不碰 AVAudioEngine 零 561017449！）
        startLiveSpeechRecognizerIfAuthorized()

        // 启动 WKWebView getUserMedia 16kHz 麦克风采集
        ensureWebCaptureEngine().startCapture()

        // 5 秒启动看门狗：如果 WebKit 既没回调 started 也没回调 err，绝不无限卡死，明确提示原因！
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self, self.isStartingMic else { return }
            self.isStartingMic = false
            _ = self.webCaptureEngine?.stopCapture()
            self.stopSpeechRecognizer(finish: false)
            self.statusMessage = "⚠️ 键盘内麦克风响应超时 · 请点「全屏同传」先授予麦克风权限，或用右下角系统麦+「✨ 译框内听写」"
            self.updateRecordButtonStyle()
            self.refreshDisplays()
        }
    }

    private func startLiveSpeechRecognizerIfAuthorized() {
        stopSpeechRecognizer(finish: false)
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            attachSpeechRecognitionSession()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    guard let self, newStatus == .authorized, (self.isStartingMic || self.isRecording) else { return }
                    self.attachSpeechRecognitionSession()
                }
            }
        default:
            break
        }
    }

    private func attachSpeechRecognitionSession() {
        stopSpeechRecognizer(finish: false)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: mode.sourceLocaleID)),
              recognizer.isAvailable else {
            return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            req.addsPunctuation = true
        }
        if recognizer.supportsOnDeviceRecognition {
            // 优先使用离线识别（更稳不掉线，若未下载离线模型可由云端 WAV 兜底）
            req.requiresOnDeviceRecognition = false
        }
        self.speechRequest = req
        self.speechTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        self.transcriptText = text
                        self.scheduleLiveTranslate(for: text)
                        self.refreshDisplays()
                    }
                } else if error != nil {
                    // 端侧流式识别如被扩展沙盒中断，不中断 WKWebView 录音，停止时自动走云端 WAV 识别翻译！
                    self.speechRequest = nil
                    self.speechTask = nil
                }
            }
        }
    }

    private func stopSpeechRecognizer(finish: Bool) {
        speechRequest?.endAudio()
        if finish {
            speechTask?.finish()
        } else {
            speechTask?.cancel()
        }
        speechRequest = nil
        speechTask = nil
    }

    private func handleWebKitPCMChunk(_ pcm16Data: Data, rms: Float) {
        // 1. 实时把 16kHz PCM16 转为 Float32 AVAudioPCMBuffer 灌入 SFSpeechAudioBufferRecognitionRequest
        if let req = speechRequest, let fmt = pcmFormat16k {
            let samples = AudioWAVEncoder.pcm16ToFloat32Samples(pcm16Data)
            if !samples.isEmpty,
               let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)),
               let ch = buf.floatChannelData?[0] {
                buf.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { src in
                    if let base = src.baseAddress {
                        ch.initialize(from: base, count: samples.count)
                    }
                }
                req.append(buf)
            }
        }
        // 2. 更新实时音频波形条
        DispatchQueue.main.async { [weak self] in
            guard let self, self.captureSource == .webKitDirect else { return }
            self.currentAudioLevel = CGFloat(min(1.0, max(0.05, rms)))
            self.setNeedsLayout()
        }
    }

    private func stopCurrentRecording() {
        if isStartingMic {
            stopAllRecording(runFinalTranslate: false)
            statusMessage = "已取消启动录音"
            refreshDisplays()
            return
        }
        switch captureSource {
        case .hostBridge:
            captureSource = .none
            currentAudioLevel = 0
            statusMessage = "✨ 正在完成最终转写与翻译…"
            updateRecordButtonStyle()
            refreshDisplays()
            let cmd = VoiceIPCCommand(action: .stop, modeRaw: mode.rawValue)
            Task { [weak self] in
                if let st = await VoiceIPCBridge.sendCommandToHost(cmd) {
                    await MainActor.run { self?.applyHostState(st) }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
                guard let self, !self.isRecording else { return }
                self.bridgePollTimer?.invalidate()
                self.bridgePollTimer = nil
            }

        case .webKitDirect:
            let pcmData = webCaptureEngine?.stopCapture() ?? Data()
            stopSpeechRecognizer(finish: true)
            captureSource = .none
            currentAudioLevel = 0
            updateRecordButtonStyle()

            let sec = Double(pcmData.count) / 32_000.0
            let existingTranscript = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)

            if !existingTranscript.isEmpty {
                statusMessage = "✨ 正在完成最终双语校译…"
                refreshDisplays()
                runLiveTranslateNow(for: existingTranscript)
            } else if pcmData.count >= 4_800 {
                // 已经成功录到真实音频（>= 0.15s），但端侧 SFSpeech 尚未返回文字 → 自动打包 WAV 发给多模态/Whisper AI 直译！
                runCloudAudioFallback(pcm16Data: pcmData, durationSec: sec)
            } else {
                statusMessage = "ℹ️ 录音时间过短或未采集到声音，请按住说话清晰发音后点停止"
                refreshDisplays()
            }

        case .none:
            break
        }
    }

    private func runCloudAudioFallback(pcm16Data: Data, durationSec: Double) {
        let cfg = AIConfig.load()
        guard cfg.isConfigured else {
            statusMessage = "⚠️ 已录到 \(String(format: "%.1f", durationSec))s 语音，请先授权「语音识别」或同步 AI 密钥"
            resultTextView.text = "✓ 键盘内已成功录到 \(String(format: "%.1f", durationSec)) 秒语音！\n但尚未授权苹果「语音识别」权限，且未配置 AI 密钥。\n• 点下方「全屏同传」授权一次即可支持本机离线实时转写；\n• 或在灵犀「AI」页配置 Gemini / OpenAI 密钥直接云端语音转换。"
            resultTextView.textColor = theme?.keyText ?? .label
            refreshDisplays()
            return
        }

        let wav = AudioWAVEncoder.encodePCM16MonoToWAV(pcm16Data: pcm16Data, sampleRate: 16_000)
        let modeSnap = mode
        statusMessage = "✨ 已录到 \(String(format: "%.1f", durationSec))s 语音，正在智能识别并转换…"
        refreshDisplays()

        liveTranslateStreamTask?.cancel()
        liveTranslateStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let res = try await self.aiClient.transcribeAndTranslateAudio(wavData: wav, mode: modeSnap, config: cfg)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.transcriptText = res.transcript
                    self.translatedText = AITextSanitizer.clean(res.translated, streaming: false)
                    self.statusMessage = "✓ 识别转换完成 · 点右下「插入上屏」直接发送"
                    self.refreshDisplays()
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    self.statusMessage = "⚠️ 已录到 \(String(format: "%.1f", durationSec))s 语音，但云端语音接口报错"
                    self.resultTextView.text = "✓ 键盘内已成功录到 \(String(format: "%.1f", durationSec)) 秒声音！\n原因：当前模型（\(cfg.activeModelName)）不支持直接上传 WAV 音频（\(error.localizedDescription)），且尚未开启苹果本机「语音识别」权限。\n\n立即可用解法：\n1. 点下方「全屏同传」授予一次苹果「语音识别」权限（之后回键盘内即可实时免费出字 + 用任意模型翻译！）；\n2. 或切换 Gemini 视觉/音频模型直接云端秒识别。"
                    self.resultTextView.textColor = self.theme?.keyText ?? .label
                    self.setNeedsLayout()
                }
            }
        }
    }

    // MARK: - 边说边实时流式双语翻译

    private func scheduleLiveTranslate(for text: String) {
        liveTranslateDebounceTask?.cancel()
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        liveTranslateDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                self.runLiveTranslateNow(for: clean)
            }
        }
    }

    private func runLiveTranslateNow(for source: String) {
        let clean = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if clean == lastTranslatedSourceSnapshot && !translatedText.isEmpty { return }
        let cfg = AIConfig.load()
        guard cfg.isConfigured else {
            if !mode.isTranslationMode {
                translatedText = AITextSanitizer.clean(clean, streaming: false)
                statusMessage = "✓ 语音转文字完成 · 点右下「插入上屏」"
            } else {
                statusMessage = "✓ 语音原文已识别（配置 AI Key 后自动双语互译）"
            }
            refreshDisplays()
            return
        }

        liveTranslateStreamTask?.cancel()
        let modeSnap = mode
        liveTranslateStreamTask = Task { [weak self] in
            guard let self else { return }
            var acc = ""
            var lastFlush = CACurrentMediaTime()
            do {
                for try await chunk in self.aiClient.streamText(
                    prompt: clean,
                    systemInstruction: modeSnap.systemPrompt,
                    config: cfg,
                    featureTag: "in_keyboard_voice_live_translate",
                    preferFast: true
                ) {
                    if Task.isCancelled { return }
                    acc += chunk
                    let now = CACurrentMediaTime()
                    if now - lastFlush >= 0.045 {
                        lastFlush = now
                        let cleaned = AITextSanitizer.clean(acc, streaming: true)
                        await MainActor.run {
                            self.translatedText = cleaned
                            self.refreshDisplays()
                        }
                    }
                }
                if Task.isCancelled { return }
                let finalClean = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    self.translatedText = finalClean
                    self.lastTranslatedSourceSnapshot = clean
                    if !self.isRecording {
                        self.statusMessage = "✓ 语音转换完成 · 点右下「插入上屏」直接发送"
                    }
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

    // MARK: - Tier 2: 后台语音引擎复用（当 App Group 后台已在线时）

    private func probeHostVoiceEngine() {
        guard !isProbing else { return }
        isProbing = true
        Task { [weak self] in
            let res = await VoiceIPCBridge.probeHostEngine()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isProbing = false
                self.hostEngineWarm = res.isWarm
                if let st = res.state, st.isRecording {
                    self.captureSource = .hostBridge
                    self.applyHostState(st)
                    self.startBridgePollTimer()
                }
            }
        }
    }

    private func startHostBridgeRecording() {
        statusMessage = "🎙️ 正在启动后台语音引擎…"
        transcriptText = ""
        translatedText = ""
        pendingReplaceCount = 0
        refreshDisplays()

        let modeRaw = mode.rawValue
        Task { [weak self] in
            guard let self else { return }
            let cmd = VoiceIPCCommand(action: .start, modeRaw: modeRaw)
            let updated = await VoiceIPCBridge.sendCommandToHost(cmd)
            await MainActor.run {
                if let updated, updated.engineWarm, updated.isRecording {
                    self.hostEngineWarm = true
                    self.captureSource = .hostBridge
                    self.transcriptText = updated.transcript
                    self.translatedText = AITextSanitizer.clean(updated.translatedText, streaming: updated.isTranslating)
                    self.statusMessage = "🎙️ 正在听「\(self.mode.sourceLanguageLabel)」· 说完点停止"
                    self.startBridgePollTimer()
                    self.updateRecordButtonStyle()
                    self.refreshDisplays()
                } else {
                    // 后台引擎已休眠 → 无缝自动切换键盘内 WebKit 直接录音，绝不报错中断用户！
                    self.hostEngineWarm = false
                    self.startWebKitDirectInKeyboardRecording()
                }
            }
        }
    }

    private func startBridgePollTimer() {
        bridgePollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.20, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let st = await VoiceIPCBridge.fetchStateFromHost() else { return }
                await MainActor.run { self?.applyHostState(st) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        bridgePollTimer = timer
    }

    private func syncFromSharedStateIfAvailable() {
        guard !isHidden, captureSource == .hostBridge, let st = VoiceIPCBridge.readStateFromShared() else { return }
        applyHostState(st)
    }

    private func applyHostState(_ st: VoiceIPCState) {
        hostEngineWarm = st.isHeartbeatFresh
        if !st.isRecording && captureSource == .hostBridge {
            captureSource = .none
        }
        if !st.transcript.isEmpty || st.isRecording {
            transcriptText = st.transcript
        }
        let cleanedTrans = AITextSanitizer.clean(st.translatedText, streaming: st.isTranslating)
        if !cleanedTrans.isEmpty || st.isRecording {
            translatedText = cleanedTrans
        }
        currentAudioLevel = CGFloat(st.audioLevel)
        if let err = st.errorText, !err.isEmpty {
            statusMessage = "⚠️ \(err)"
        } else if !st.statusText.isEmpty {
            statusMessage = st.statusText
        }
        if !st.isRecording && !st.isTranslating {
            bridgePollTimer?.invalidate()
            bridgePollTimer = nil
        }
        updateRecordButtonStyle()
        refreshDisplays()
    }

    // MARK: - 辅助工具按钮：✨ 译框内听写 & 全屏同传

    private func handleDictationConvertTap() {
        if !hasFullAccess {
            handlePrimaryRecordTap()
            return
        }
        liveTranslateStreamTask?.cancel()
        let hostText = (onFetchHostInputContext?() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pbText = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let source: String
        let replaceLen: Int
        if !hostText.isEmpty {
            let lastPara = hostText.components(separatedBy: .newlines).last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? hostText
            source = String(lastPara.suffix(180))
            replaceLen = source.count
        } else if !pbText.isEmpty {
            source = String(pbText.prefix(240))
            replaceLen = 0
        } else {
            statusMessage = "ℹ️ 可点右下角苹果系统麦 🎙️ 说出中文/英文，再点「✨ 译框内听写」原地秒译！"
            refreshDisplays()
            return
        }

        let cfg = AIConfig.load()
        guard cfg.isConfigured else {
            transcriptText = source
            translatedText = ""
            pendingReplaceCount = 0
            statusMessage = "⚠️ 尚未配置/同步 AI 密钥，请先在灵犀「AI」页填写或同步口令"
            refreshDisplays()
            return
        }

        transcriptText = source
        translatedText = ""
        pendingReplaceCount = replaceLen
        lastTranslatedSourceSnapshot = ""
        statusMessage = "✨ 正在将刚说的话转为「\(mode.targetLanguageLabel)」…"
        refreshDisplays()
        runLiveTranslateNow(for: source)
    }

    private func triggerFullWorkbenchWithFeedback() {
        stopAllRecording(runFinalTranslate: false)
        statusMessage = "🎙️ 正在打开「\(mode.shortTitle)」全屏实时同传…"
        refreshDisplays()
        onOpenFullVoiceWorkbench?(mode) { [weak self] opened in
            guard let self, !opened else { return }
            self.statusMessage = "⚠️ 宿主限制了自动跳转，请直接在键盘内点「🎙️ 开始说话」或切回「灵犀」App"
            self.refreshDisplays()
        }
    }

    // MARK: - UI 刷新与底部按钮动作

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
        } else if isStartingMic {
            recordButton.setTitle("⏳ 开麦中…", for: .normal)
            recordButton.backgroundColor = .systemOrange
            recordButton.setTitleColor(.white, for: .normal)
        } else if !hasFullAccess {
            recordButton.setTitle("🔓 开启完全访问", for: .normal)
            recordButton.backgroundColor = theme.accentFill
            recordButton.setTitleColor(theme.accentText, for: .normal)
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
            sourceLabel.text = "🎙️ \(mode.sourceLanguageLabel)原文：点左下「🎙️ 开始说话」直接开口…"
            sourceLabel.textColor = theme?.keyHintText ?? .secondaryLabel
        } else {
            sourceLabel.text = "🎙️ \(transcriptText)"
            sourceLabel.textColor = theme?.keyText ?? .label
        }

        let displayRes = preferredOutputText
        if displayRes.isEmpty {
            if isRecording {
                resultTextView.text = "🎙️ 正在聆听你的声音（\(mode.shortTitle)）…\n说完点左下「⏹ 停止说话」，实时译文会自动出现在这里并可一键插入上屏。"
            } else {
                resultTextView.text = "键盘内免跳转实时语音转换（\(mode.shortTitle)）：\n• 直接点左下「🎙️ 开始说话」即可在当前软件键盘内录音并实时转换（无需跳出 App）\n• 也可点手机右下角苹果系统麦克风说完，再点「✨ 译框内听写」原地替换为目标语种。"
            }
            resultTextView.textColor = theme?.keyHintText ?? .secondaryLabel
        } else {
            resultTextView.text = displayRes
            resultTextView.textColor = theme?.keyText ?? .label
        }

        let hasOut = !displayRes.isEmpty
        insertButton.setTitle(pendingReplaceCount > 0 ? "替换上屏" : "插入上屏", for: .normal)
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
        lastTranslatedSourceSnapshot = ""
        pendingReplaceCount = 0
        statusMessage = "已清空 · 点左下「🎙️ 开始说话」重新录入"
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
        if pendingReplaceCount > 0, let replace = onReplaceBeforeCursor {
            let count = pendingReplaceCount
            pendingReplaceCount = 0
            replace(count, out)
        } else {
            onInsertText?(out)
        }
    }
}
