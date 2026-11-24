import UIKit

/// 键盘内嵌「🎙️ 实时语音转换」面板（v5.6.1 真机实测彻底修复版，彻底留在键盘内部，不跳出微信/抖音！）：
/// - 支持 6 种实时模式：说中文→英语 / 说英语→中文 / 中→日 / 日→中 / 中文速记 / 英文速记；
/// - 底层接入主 App 常驻 `BackgroundVoiceEngine`（前台启动永不 stop 的 `AVAudioEngine` + 单包 GET 回环指令 + 绕过系统代理 + App Group 双通道），
///   彻底告别 iOS 键盘扩展直录必报 `561017449` 与后台重启引擎必报 `CannotStartRecording` 的死循环；
/// - 引擎在线时：顶栏绿灯显示「🟢 键盘内语音在线」，点「🎙️ 开始说话」零跳转即时录音并流式双语互译；
/// - 引擎未激活时：主按钮直接显示「⚡ 先激活后台语音（仅 1 次）」，同步手势栈内 1 键拉起激活，切回微信即可无限次键盘内直说！
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
    private var hostEngineWarm = false
    private var isProbing = false
    private var transcriptText = ""
    private var translatedText = ""
    private var statusMessage = "正在检测后台语音引擎状态…"

    // 后台语音桥接监听
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

        activateEngineButton.setTitle("⚡ 一键激活键盘语音（仅需 1 次）", for: .normal)
        activateEngineButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        activateEngineButton.layer.cornerRadius = 9
        activateEngineButton.layer.cornerCurve = .continuous
        activateEngineButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        activateEngineButton.actionHandler = { [weak self] in
            guard let self else { return }
            if !self.hasFullAccess {
                self.onOpenPermissions?()
            } else {
                self.onWarmUpHostVoiceEngine?()
            }
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
        recordButton.actionHandler = { [weak self] in self?.handlePrimaryRecordTap() }

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
        // 先同步检查共享容器缓存，避免 UI 闪烁
        let sharedWarm = VoiceIPCBridge.readStateFromShared()?.isHeartbeatFresh == true
        self.hostEngineWarm = sharedWarm
        applyTheme(theme)
        rebuildModePills()
        updateEngineStateUI(warm: sharedWarm, updateStatusIfIdle: true)
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
        if isRecording {
            let cmd = VoiceIPCCommand(action: .stop, modeRaw: mode.rawValue)
            Task { _ = await VoiceIPCBridge.sendCommandToHost(cmd) }
        }
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
        statusMessage = hostEngineWarm
            ? "🟢 已切至「\(newMode.shortTitle)」· 点下方直接开口说话"
            : "🟡 已切至「\(newMode.shortTitle)」· 点下方激活后台语音引擎后即可直说"
        rebuildModePills()
        refreshDisplays()
    }

    // MARK: - 探活后台语音引擎 & 开始/停止录音

    private func probeHostVoiceEngine() {
        guard !isProbing else { return }
        isProbing = true
        Task { [weak self] in
            let state = await VoiceIPCBridge.fetchStateFromHost()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isProbing = false
                let warm = state?.isHeartbeatFresh == true
                self.updateEngineStateUI(warm: warm, updateStatusIfIdle: true)
                if let state, state.isRecording {
                    self.applyHostState(state)
                    self.startBridgePollTimer()
                }
            }
        }
    }

    private func updateEngineStateUI(warm: Bool, updateStatusIfIdle: Bool) {
        hostEngineWarm = warm
        if !hasFullAccess {
            activationBar.isHidden = false
            activateEngineButton.setTitle("🔓 前往开启完全访问权限", for: .normal)
            if updateStatusIfIdle && !isRecording {
                statusMessage = "⚠️ 请先开启键盘「允许完全访问」才可连接语音引擎"
            }
        } else if warm {
            activationBar.isHidden = true
            if updateStatusIfIdle && !isRecording && transcriptText.isEmpty {
                statusMessage = "🟢 后台语音引擎在线 · 在键盘内直接点「开始说话」"
            }
        } else {
            activationBar.isHidden = false
            activateEngineButton.setTitle("⚡ 一键激活键盘语音（仅需 1 次）", for: .normal)
            if updateStatusIfIdle && !isRecording && transcriptText.isEmpty {
                statusMessage = "🟡 首次需激活后台语音（点 1 次返回后，可一直在键盘内直说）"
            }
        }
        updateRecordButtonStyle()
        refreshDisplays()
    }

    /// 关键修复：所有会触发 `openURL`（激活后台语音 / 开权限）的操作都在用户点击的同步栈里直接调用，
    /// 绝不放进 async Task 丢失用户手势上下文！
    private func handlePrimaryRecordTap() {
        if isRecording {
            stopCurrentRecording()
            return
        }
        if !hasFullAccess {
            onOpenPermissions?()
            return
        }
        if !hostEngineWarm {
            // 同步直接唤起灵犀 App 完成 1 次常驻音频引擎激活（激活后用户点左上角返回原 App 即可在键盘内无限次直说）
            statusMessage = "⚡ 正在唤起灵犀激活常驻语音引擎，激活后点左上角返回即可直说…"
            refreshDisplays()
            onWarmUpHostVoiceEngine?()
            return
        }
        startHostBridgeRecording()
    }

    private func startHostBridgeRecording() {
        statusMessage = "🎙️ 正在启动收音…"
        transcriptText = ""
        translatedText = ""
        refreshDisplays()

        let modeRaw = mode.rawValue
        Task { [weak self] in
            guard let self else { return }
            let cmd = VoiceIPCCommand(action: .start, modeRaw: modeRaw)
            let updated = await VoiceIPCBridge.sendCommandToHost(cmd)
            await MainActor.run {
                if let updated, updated.engineWarm {
                    self.hostEngineWarm = true
                    self.isRecording = updated.isRecording
                    self.activationBar.isHidden = true
                    self.transcriptText = updated.transcript
                    self.translatedText = AITextSanitizer.clean(updated.translatedText, streaming: updated.isTranslating)
                    if let err = updated.errorText, !err.isEmpty {
                        self.statusMessage = "⚠️ \(err)"
                    } else if updated.isRecording {
                        self.statusMessage = "🎙️ 正在听「\(self.mode.sourceLanguageLabel)」· 说完点停止或直接插入"
                        self.startBridgePollTimer()
                    } else {
                        self.statusMessage = "⚠️ 后台引擎未能开始录音，请点下方重新激活一次"
                        self.updateEngineStateUI(warm: false, updateStatusIfIdle: false)
                    }
                    self.updateRecordButtonStyle()
                    self.refreshDisplays()
                } else {
                    // 后台引擎已被系统回收或尚未预热：立即切回「一键激活」状态并清晰提示
                    self.isRecording = false
                    self.hostEngineWarm = false
                    self.activationBar.isHidden = false
                    self.activateEngineButton.setTitle("⚡ 重新激活后台语音（仅需 1 次）", for: .normal)
                    self.statusMessage = "🟡 后台语音引擎已休眠 · 请点左下「⚡ 激活键盘语音」重新激活一次"
                    self.updateRecordButtonStyle()
                    self.refreshDisplays()
                }
            }
        }
    }

    private func stopCurrentRecording() {
        isRecording = false
        statusMessage = "✨ 正在完成最终转写与翻译…"
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            guard let self, !self.isRecording else { return }
            self.bridgePollTimer?.invalidate()
            self.bridgePollTimer = nil
        }
    }

    // MARK: - 后台语音引擎实时同步

    private func startBridgePollTimer() {
        bridgePollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.20, repeats: true) { [weak self] _ in
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
        let wasWarm = hostEngineWarm
        hostEngineWarm = st.isHeartbeatFresh
        if !hostEngineWarm && wasWarm {
            activationBar.isHidden = false
            activateEngineButton.setTitle("⚡ 重新激活后台语音", for: .normal)
        } else if hostEngineWarm {
            activationBar.isHidden = true
        }
        isRecording = st.isRecording
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
        } else if !hasFullAccess {
            recordButton.setTitle("🔓 开启完全访问", for: .normal)
            recordButton.backgroundColor = theme.accentFill
            recordButton.setTitleColor(theme.accentText, for: .normal)
        } else if hostEngineWarm {
            recordButton.setTitle("🎙️ 开始说话", for: .normal)
            recordButton.backgroundColor = theme.accentFill
            recordButton.setTitleColor(theme.accentText, for: .normal)
        } else {
            recordButton.setTitle("⚡ 激活键盘语音", for: .normal)
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
                ? "🟢 键盘内语音引擎已就绪（无需跳出当前 App）\n点左下「🎙️ 开始说话」，说完自动完成「\(mode.shortTitle)」并支持一键插入上屏。"
                : "为什么首次需要点一次激活？\niOS 系统限制键盘进程不能直接独占麦克风，必须由灵犀主 App 在前台开启 1 次常驻语音引擎（与讯飞/豆包原理相同）。\n点下方「⚡ 激活键盘语音」后立即返回，之后可一直在微信/抖音键盘内直接说话不跳出！也可点「全屏同传」立即可用。"
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
        statusMessage = hostEngineWarm ? "🟢 已清空 · 点「开始说话」重新录入" : "已清空"
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
}
