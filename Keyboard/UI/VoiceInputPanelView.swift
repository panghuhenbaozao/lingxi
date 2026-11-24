import UIKit

/// 键盘内嵌「🎙️ 实时语音转换」面板（v5.6.2 全场景可用 + 零静默失灵版）：
/// - 支持 6 种实时模式：说中文→英语 / 说英语→中文 / 中→日 / 日→中 / 中文速记 / 英文速记；
/// - 三重保障覆盖所有真机与签名方式（正式签名 / 巨魔 / 免费个人 Apple ID 侧载）：
///   1. 后台引擎在线（App Group 或本机回环已连上）：绿灯「🟢 键盘内语音在线」，点「🎙️ 开始说话」零跳转直接在键盘内实时录音与双语互译；
///   2. 免费侧载沙盒隔离（App Group 被系统剥离且回环受限）：主按钮直接一键拉起「🎙️ 开麦实时互译」（自动带当前语种方向开麦录音，说完自动复制回微信顶栏）；
///   3. 零跳转系统听写转换「✨ 译框内听写」：点 iPhone 右下角苹果原生麦克风说完话，点一下本按钮直接在键盘内实时转成目标语言并原地替换，全程不离开微信！
/// - 所有按钮均带即时视觉反馈与真实失败原因诊断，彻底杜绝「点了没反应也不报错」！
final class VoiceInputPanelView: UIView {
    var onInsertText: ((String) -> Void)?
    /// 原地替换光标前指定字数（用于把苹果系统听写刚说进输入框的中文/英文一键原地替换为译文）
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
    private var isRecording = false
    private var hostEngineWarm = false
    private var probeChannel = "none"
    private var probeDetail = ""
    private var isProbing = false
    private var transcriptText = ""
    private var translatedText = ""
    private var pendingReplaceCount = 0
    private var statusMessage = "正在检测语音引擎状态…"

    // 键盘内直译（用于「✨ 译框内听写 / 剪贴板」）
    private let aiClient = AIClient(timeout: 25)
    private var inlineTranslateTask: Task<Void, Never>?

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
    private let secondaryPrimaryBtn = ActionClosureButton(type: .system)
    private let secondaryRightBtn = ActionClosureButton(type: .system)

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
        inlineTranslateTask?.cancel()
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
        resultTextView.font = .systemFont(ofSize: 14, weight: .medium)
        resultTextView.layer.cornerRadius = 11
        resultTextView.layer.cornerCurve = .continuous
        resultTextView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        addSubview(resultTextView)

        activationBar.axis = .horizontal
        activationBar.spacing = 6
        activationBar.distribution = .fill
        activationBar.isHidden = false
        addSubview(activationBar)

        secondaryPrimaryBtn.setTitle("✨ 译框内听写", for: .normal)
        secondaryPrimaryBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        secondaryPrimaryBtn.layer.cornerRadius = 9
        secondaryPrimaryBtn.layer.cornerCurve = .continuous
        secondaryPrimaryBtn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        secondaryPrimaryBtn.actionHandler = { [weak self] in
            self?.handleSecondaryPrimaryTap()
        }
        activationBar.addArrangedSubview(secondaryPrimaryBtn)

        secondaryRightBtn.setTitle("⚡ 后台保活", for: .normal)
        secondaryRightBtn.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        secondaryRightBtn.layer.cornerRadius = 9
        secondaryRightBtn.layer.cornerCurve = .continuous
        secondaryRightBtn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
        secondaryRightBtn.setContentHuggingPriority(.required, for: .horizontal)
        secondaryRightBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        secondaryRightBtn.actionHandler = { [weak self] in
            self?.handleSecondaryRightTap()
        }
        activationBar.addArrangedSubview(secondaryRightBtn)

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

        var contentBottom = bottomBar.frame.minY
        if !activationBar.isHidden {
            let actH: CGFloat = 32
            activationBar.frame = CGRect(x: pad, y: contentBottom - actH - 6, width: bounds.width - pad * 2, height: actH)
            contentBottom = activationBar.frame.minY
        }

        let srcY = levelBarTrack.frame.maxY + 5
        let srcH: CGFloat = 34
        sourceCard.frame = CGRect(x: pad, y: srcY, width: bounds.width - pad * 2, height: srcH)
        sourceLabel.frame = sourceCard.bounds.insetBy(dx: 9, dy: 4)

        let resY = sourceCard.frame.maxY + 5
        let availH = max(24, contentBottom - resY - 5)
        resultTextView.frame = CGRect(x: pad, y: resY, width: bounds.width - pad * 2, height: availH)
    }

    // MARK: - 生命周期与配置

    func prepare(theme: ResolvedTheme, hasFullAccess: Bool) {
        self.theme = theme
        self.hasFullAccess = hasFullAccess
        let sharedWarm = VoiceIPCBridge.readStateFromShared()?.isHeartbeatFresh == true
        self.hostEngineWarm = sharedWarm
        self.probeChannel = sharedWarm ? "AppGroup" : "none"
        applyTheme(theme)
        rebuildModePills()
        updateEngineStateUI(warm: sharedWarm, updateStatusIfIdle: true)
        probeHostVoiceEngine()
    }

    /// 宿主 App 回到前台（`viewWillAppear`）时自动复查后台语音引擎是否已激活，消除「激活完回来按钮不变」问题。
    func refreshEngineStatus(hasFullAccess: Bool) {
        self.hasFullAccess = hasFullAccess
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

        secondaryPrimaryBtn.backgroundColor = theme.accentFill.withAlphaComponent(0.16)
        secondaryPrimaryBtn.setTitleColor(theme.candidateHighlight, for: .normal)
        secondaryRightBtn.backgroundColor = theme.specialKeyFill
        secondaryRightBtn.setTitleColor(theme.keyText, for: .normal)

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
        inlineTranslateTask?.cancel()
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
        pendingReplaceCount = 0
        statusMessage = hostEngineWarm
            ? "🟢 已切至「\(newMode.shortTitle)」· 点左下「🎙️ 开始说话」"
            : "已切至「\(newMode.shortTitle)」· 点左下直接开麦，或点「✨ 译框内听写」"
        rebuildModePills()
        refreshDisplays()
    }

    // MARK: - 探活后台语音引擎

    private func probeHostVoiceEngine() {
        guard !isProbing else { return }
        isProbing = true
        Task { [weak self] in
            let res = await VoiceIPCBridge.probeHostEngine()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isProbing = false
                self.probeChannel = res.channel
                self.probeDetail = res.detail
                self.updateEngineStateUI(warm: res.isWarm, updateStatusIfIdle: true)
                if let st = res.state, st.isRecording {
                    self.applyHostState(st)
                    self.startBridgePollTimer()
                }
            }
        }
    }

    private func updateEngineStateUI(warm: Bool, updateStatusIfIdle: Bool) {
        hostEngineWarm = warm
        activationBar.isHidden = false
        if !hasFullAccess {
            secondaryPrimaryBtn.setTitle("🔓 开启「允许完全访问」权限", for: .normal)
            secondaryRightBtn.setTitle("全屏同传", for: .normal)
            if updateStatusIfIdle && !isRecording {
                statusMessage = "⚠️ 请先开启「允许完全访问」，才可联网互译与连接语音引擎"
            }
        } else if warm {
            secondaryPrimaryBtn.setTitle("✨ 译框内刚说的话", for: .normal)
            secondaryRightBtn.setTitle("全屏同传", for: .normal)
            if updateStatusIfIdle && !isRecording && transcriptText.isEmpty {
                let ch = probeChannel == "AppGroup" ? "共享直连" : "本机回环"
                statusMessage = "🟢 键盘内语音引擎在线（\(ch)）· 直接点左下开口说话"
            }
        } else if AppGroup.isAvailable {
            secondaryPrimaryBtn.setTitle("✨ 译框内听写", for: .normal)
            secondaryRightBtn.setTitle("全屏同传", for: .normal)
            if updateStatusIfIdle && !isRecording && transcriptText.isEmpty {
                statusMessage = "🟡 点左下激活 1 次后台语音后可键盘内直说；也可点右侧「全屏同传」"
            }
        } else {
            // 免费个人 Apple ID 侧载（App Group 被系统隔离）：主按钮直达「开麦实时互译」，并常驻「✨ 译框内听写」零跳转方案！
            secondaryPrimaryBtn.setTitle("✨ 译框内听写(零跳转)", for: .normal)
            secondaryRightBtn.setTitle("⚡ 试连后台", for: .normal)
            if updateStatusIfIdle && !isRecording && transcriptText.isEmpty {
                statusMessage = "🎙️ 点左下「开麦实时互译」直接录音；或用右下角系统麦克风说完点「✨ 译框内听写」"
            }
        }
        updateRecordButtonStyle()
        refreshDisplays()
    }

    // MARK: - 主按钮 & 辅助按钮（所有操作即时反馈 + 失败必报错提示，绝不静默没反应！）

    private func handlePrimaryRecordTap() {
        if isRecording {
            stopCurrentRecording()
            return
        }
        if !hasFullAccess {
            statusMessage = "🔓 正在打开权限设置…"
            refreshDisplays()
            onOpenPermissions? { [weak self] opened in
                guard let self, !opened else { return }
                self.statusMessage = "⚠️ 系统禁止自动跳转，请手动前往「设置 → 通用 → 键盘 → 灵犀输入法」开启完全访问"
                self.refreshDisplays()
            }
            return
        }
        if hostEngineWarm {
            startHostBridgeRecording()
            return
        }
        if AppGroup.isAvailable {
            // App Group 已打通：先一键激活后台常驻语音，并安排自动轮询探活（即使在灵犀自带试打框里也会 1 秒自动变绿！）
            triggerWarmUpWithFeedback()
        } else {
            // 免费侧载沙盒隔离：直接拉起主 App 全屏实时语音同传（自动带当前语种开麦，说完自动复制回微信）！
            triggerFullWorkbenchWithFeedback()
        }
    }

    private func handleSecondaryPrimaryTap() {
        if !hasFullAccess {
            handlePrimaryRecordTap()
            return
        }
        translateHostInputOrClipboardInPlace()
    }

    private func handleSecondaryRightTap() {
        if hostEngineWarm || AppGroup.isAvailable || !hasFullAccess {
            triggerFullWorkbenchWithFeedback()
        } else {
            triggerWarmUpWithFeedback()
        }
    }

    private func triggerWarmUpWithFeedback() {
        statusMessage = "⚡ 正在唤起灵犀激活常驻语音引擎…"
        refreshDisplays()
        onWarmUpHostVoiceEngine? { [weak self] opened in
            guard let self else { return }
            if opened {
                self.statusMessage = "⚡ 已发送激活指令：若在灵犀内测试请稍等 1 秒自动变绿；若已跳主 App，点左上角返回即可直说"
                self.refreshDisplays()
                // 若用户正处于灵犀自身试打区，应用不会切屏，主动连续探活 3 次自动刷新为绿灯！
                for delay in [0.6, 1.4, 2.6] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.probeHostVoiceEngine()
                    }
                }
            } else {
                self.statusMessage = "⚠️ 当前宿主 App 拦截了快捷跳转，请切回桌面打开「灵犀」点「激活键盘语音」，或用右下角系统麦说完点「✨ 译框内听写」"
                self.refreshDisplays()
            }
        }
    }

    private func triggerFullWorkbenchWithFeedback() {
        statusMessage = "🎙️ 正在打开「\(mode.shortTitle)」实时语音同传…"
        refreshDisplays()
        onOpenFullVoiceWorkbench?(mode) { [weak self] opened in
            guard let self else { return }
            if !opened {
                self.statusMessage = "⚠️ 系统拦截了自动跳转，请切回「灵犀」App 点「语音同传」，或用键盘右下角苹果麦克风说完点「✨ 译框内听写」"
                self.refreshDisplays()
            }
        }
    }

    /// 零跳转终极招：读取输入框刚通过苹果原生听写说出的文字（或剪贴板），在键盘内直接实时转换成目标语种并支持原地替换！
    private func translateHostInputOrClipboardInPlace() {
        inlineTranslateTask?.cancel()
        let hostText = (onFetchHostInputContext?() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pbText = hasFullAccess ? (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""

        let source: String
        let replaceLen: Int
        if !hostText.isEmpty {
            // 取光标前最后一段/最后 180 字
            let lastPara = hostText.components(separatedBy: .newlines).last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? hostText
            source = String(lastPara.suffix(180))
            replaceLen = source.count
        } else if !pbText.isEmpty {
            source = String(pbText.prefix(240))
            replaceLen = 0
        } else {
            statusMessage = "ℹ️ 请先点手机右下角苹果系统麦克风 🎙️ 说出中文或英文，再点「✨ 译框内听写」即可免跳转秒译！"
            refreshDisplays()
            return
        }

        let cfg = AIConfig.load()
        guard cfg.isConfigured else {
            transcriptText = source
            translatedText = ""
            pendingReplaceCount = 0
            statusMessage = "⚠️ 尚未配置/同步 AI 密钥，请在灵犀「AI」页填写或一键同步口令后再转换"
            refreshDisplays()
            return
        }

        transcriptText = source
        translatedText = ""
        pendingReplaceCount = replaceLen
        statusMessage = "✨ 正在将刚说的话转为「\(mode.targetLanguageLabel)」…"
        refreshDisplays()

        let modeSnap = mode
        inlineTranslateTask = Task { [weak self] in
            guard let self else { return }
            var acc = ""
            var lastFlush = CACurrentMediaTime()
            do {
                for try await chunk in self.aiClient.streamText(
                    prompt: source,
                    systemInstruction: modeSnap.systemPrompt,
                    config: cfg,
                    featureTag: "in_keyboard_dictation_translate",
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
                let finalOut = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    self.translatedText = finalOut
                    self.statusMessage = replaceLen > 0
                        ? "✓ 转换完成 · 点右下「替换上屏」把刚说的话直接换为译文"
                        : "✓ 转换完成 · 点右下「插入上屏」直接发送"
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

    // MARK: - 后台语音引擎录音与轮询

    private func startHostBridgeRecording() {
        statusMessage = "🎙️ 正在启动键盘内收音…"
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
                if let updated, updated.engineWarm {
                    self.hostEngineWarm = true
                    self.isRecording = updated.isRecording
                    self.transcriptText = updated.transcript
                    self.translatedText = AITextSanitizer.clean(updated.translatedText, streaming: updated.isTranslating)
                    if let err = updated.errorText, !err.isEmpty {
                        self.statusMessage = "⚠️ \(err)"
                    } else if updated.isRecording {
                        self.statusMessage = "🎙️ 正在听「\(self.mode.sourceLanguageLabel)」· 说完点停止或直接插入"
                        self.startBridgePollTimer()
                    } else {
                        self.statusMessage = "⚠️ 后台引擎未能开始录音，请点下方重新激活或使用「全屏同传」"
                        self.updateEngineStateUI(warm: false, updateStatusIfIdle: false)
                    }
                    self.updateRecordButtonStyle()
                    self.refreshDisplays()
                } else {
                    self.isRecording = false
                    self.hostEngineWarm = false
                    self.statusMessage = "⚠️ 后台语音引擎未响应（可能已休眠或被系统隔离），请点左下直接开麦同传或重新激活"
                    self.updateEngineStateUI(warm: false, updateStatusIfIdle: false)
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
        hostEngineWarm = st.isHeartbeatFresh
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
        } else if AppGroup.isAvailable {
            recordButton.setTitle("⚡ 激活键盘语音", for: .normal)
            recordButton.backgroundColor = theme.accentFill
            recordButton.setTitleColor(theme.accentText, for: .normal)
        } else {
            recordButton.setTitle("🎙️ 开麦实时互译", for: .normal)
            recordButton.backgroundColor = theme.accentFill
            recordButton.setTitleColor(theme.accentText, for: .normal)
        }
        levelBarFill.backgroundColor = isRecording ? .systemRed : theme.accentFill
    }

    private func refreshDisplays() {
        statusPillLabel.text = statusMessage
        if transcriptText.isEmpty {
            sourceLabel.text = "🎙️ \(mode.sourceLanguageLabel)原文：等待开口说话或听写…"
            sourceLabel.textColor = theme?.keyHintText ?? .secondaryLabel
        } else {
            sourceLabel.text = "🎙️ \(transcriptText)"
            sourceLabel.textColor = theme?.keyText ?? .label
        }

        let displayRes = preferredOutputText
        if displayRes.isEmpty {
            if hostEngineWarm {
                resultTextView.text = "🟢 后台语音引擎已就绪（无需跳出当前 App）\n点左下「🎙️ 开始说话」，说完自动完成「\(mode.shortTitle)」并一键插入上屏。"
            } else if AppGroup.isAvailable {
                resultTextView.text = "两种立即可用语音转换方式（\(mode.shortTitle)）：\n1. 点左下「⚡ 激活键盘语音」开启 1 次后台引擎，返回后直接在键盘内无限次说话不跳出；\n2. 也可直接点手机右下角苹果系统麦克风说完，再点「✨ 译框内听写」原地转成目标语种！"
            } else {
                resultTextView.text = "检测到当前为免费侧载签名（系统已隔离 App Group 跨进程通信）：\n• 方式 1（零跳转不离微信）：点手机右下角苹果系统麦克风 🎙️ 说中文或英文，再点「✨ 译框内听写(零跳转)」原地秒译替换！\n• 方式 2（一键全屏同传）：点左下「🎙️ 开麦实时互译」自动开麦边说边译并自动复制回微信。"
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
        pendingReplaceCount = 0
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
        if pendingReplaceCount > 0, let replace = onReplaceBeforeCursor {
            let count = pendingReplaceCount
            pendingReplaceCount = 0
            replace(count, out)
        } else {
            onInsertText?(out)
        }
    }
}
