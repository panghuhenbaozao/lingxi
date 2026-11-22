import UIKit

/// 内嵌 AI 灵犀写作面板 v5.0：
/// - 流式思考过程独立折叠（绝不把 <think> 草稿插入输入框）
/// - 顶部一键切换思考模式与对话场景人设（领导/同事/密友/社交/学术）
/// - 博弈军师三策略气泡墙（一眼看破潜台词 + 3 种立场一键上屏）
/// - 语境自动识别置顶推荐提示词 + 用户自定义提示词库实时同步
final class AIAssistantPanelView: UIView {
    enum SourceMode: Int {
        case inputContext = 0
        case clipboard = 1
    }

    var onInsertText: ((String) -> Void)?
    var onReplaceBeforeCursor: ((Int, String) -> Void)?
    var onRequestPromptInput: (() -> Void)?
    var onClose: (() -> Void)?

    private let client = AIClient()
    private var streamTask: Task<Void, Never>?

    private var theme: ResolvedTheme?
    private var hasFullAccess = false
    private var beforeCursorText = ""
    private var beforeCursorReplaceCount = 0
    private var clipboardText = ""
    private var sourceMode: SourceMode = .inputContext
    private var lastAction: AIPresetAction = .polish
    private var lastCustomTemplateID: String?
    private var cachedCustomPrompts: [CustomAIPromptTemplate] = []
    private var currentRecommendation: SmartContextRecommendation?
    private var generatedText = ""
    private var thinkingText = ""
    private var isThinkingExpanded = false
    private var strategistResult: NegotiationStrategistResult?
    private var lastCustomPrompt: (prompt: String, sys: String)?

    // UI
    private let topBar = UIStackView()
    private let contextSegmented = UISegmentedControl(items: ["输入", "剪贴板"])
    private let sceneButton = ActionClosureButton(type: .system)
    private let thinkingButton = ActionClosureButton(type: .system)
    private let askFreeButton = ActionClosureButton(type: .system)
    private let closeButton = ActionClosureButton(type: .system)

    private let sourceScroll = LingxiScrollView()
    private let sourceLabel = UILabel()
    private let actionsScroll = LingxiScrollView()
    private let actionsStack = UIStackView()

    // 思考过程独立折叠区
    private let thoughtToggleButton = ActionClosureButton(type: .system)
    private let thoughtTextView = UITextView()

    // 常规流式正文输出区
    private let outputTextView = UITextView()

    // 博弈军师三策略卡片区
    private let strategistScroll = LingxiScrollView()
    private let strategistStack = UIStackView()

    private let refineScroll = LingxiScrollView()
    private let refineStack = UIStackView()
    private let bottomBar = UIStackView()
    private let stopOrRetryButton = ActionClosureButton(type: .system)
    private let replaceButton = ActionClosureButton(type: .system)
    private let insertButton = ActionClosureButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        streamTask?.cancel()
    }

    private func setupViews() {
        topBar.axis = .horizontal
        topBar.spacing = 5
        topBar.alignment = .center
        addSubview(topBar)

        contextSegmented.selectedSegmentIndex = 0
        contextSegmented.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)
        topBar.addArrangedSubview(contextSegmented)

        sceneButton.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        sceneButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 7, bottom: 4, right: 7)
        sceneButton.layer.cornerRadius = 8
        sceneButton.layer.cornerCurve = .continuous
        sceneButton.actionHandler = { [weak self] in self?.cycleScenePersona() }
        topBar.addArrangedSubview(sceneButton)

        thinkingButton.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        thinkingButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 7, bottom: 4, right: 7)
        thinkingButton.layer.cornerRadius = 8
        thinkingButton.layer.cornerCurve = .continuous
        thinkingButton.actionHandler = { [weak self] in self?.cycleThinkingMode() }
        topBar.addArrangedSubview(thinkingButton)

        askFreeButton.setTitle("💬问", for: .normal)
        askFreeButton.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        askFreeButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 7, bottom: 4, right: 7)
        askFreeButton.layer.cornerRadius = 8
        askFreeButton.layer.cornerCurve = .continuous
        askFreeButton.actionHandler = { [weak self] in
            self?.streamTask?.cancel()
            self?.onRequestPromptInput?()
        }
        topBar.addArrangedSubview(askFreeButton)

        closeButton.setTitle("返回", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        closeButton.layer.cornerRadius = 8
        closeButton.layer.cornerCurve = .continuous
        closeButton.actionHandler = { [weak self] in
            self?.streamTask?.cancel()
            self?.onClose?()
        }
        topBar.addArrangedSubview(closeButton)

        sourceScroll.showsHorizontalScrollIndicator = false
        sourceScroll.showsVerticalScrollIndicator = false
        sourceScroll.alwaysBounceHorizontal = true
        addSubview(sourceScroll)

        sourceLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        sourceLabel.numberOfLines = 1
        sourceLabel.lineBreakMode = .byClipping
        sourceScroll.addSubview(sourceLabel)

        actionsScroll.showsHorizontalScrollIndicator = false
        addSubview(actionsScroll)
        actionsStack.axis = .horizontal
        actionsStack.spacing = 6
        actionsStack.alignment = .center
        actionsScroll.addSubview(actionsStack)

        thoughtToggleButton.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        thoughtToggleButton.contentHorizontalAlignment = .leading
        thoughtToggleButton.contentEdgeInsets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        thoughtToggleButton.layer.cornerRadius = 7
        thoughtToggleButton.layer.cornerCurve = .continuous
        thoughtToggleButton.isHidden = true
        thoughtToggleButton.actionHandler = { [weak self] in
            guard let self else { return }
            self.isThinkingExpanded.toggle()
            self.updateThoughtHeader()
            self.setNeedsLayout()
        }
        addSubview(thoughtToggleButton)

        thoughtTextView.isEditable = false
        thoughtTextView.font = .systemFont(ofSize: 11.5, weight: .regular)
        thoughtTextView.layer.cornerRadius = 8
        thoughtTextView.layer.cornerCurve = .continuous
        thoughtTextView.textContainerInset = UIEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        thoughtTextView.isHidden = true
        addSubview(thoughtTextView)

        outputTextView.isEditable = false
        outputTextView.font = .systemFont(ofSize: 14, weight: .regular)
        outputTextView.layer.cornerRadius = 10
        outputTextView.layer.cornerCurve = .continuous
        outputTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        addSubview(outputTextView)

        strategistScroll.showsVerticalScrollIndicator = true
        strategistScroll.isHidden = true
        addSubview(strategistScroll)
        strategistStack.axis = .vertical
        strategistStack.spacing = 6
        strategistStack.alignment = .fill
        strategistScroll.addSubview(strategistStack)

        refineScroll.showsHorizontalScrollIndicator = false
        refineScroll.isHidden = true
        addSubview(refineScroll)
        refineStack.axis = .horizontal
        refineStack.spacing = 6
        refineStack.alignment = .center
        refineScroll.addSubview(refineStack)

        let refinements: [(String, String)] = [
            ("精简一半", "把这段内容精简一半，保留核心信息，只输出修改结果。"),
            ("更正式", "把这段内容改写得更加专业、正式、条理清晰，适合职场/商务沟通，只输出修改结果。"),
            ("更委婉", "把这段内容改写得更加委婉礼貌、高情商，只输出修改结果。"),
            ("更幽默", "把这段内容改写得更风趣幽默一点，只输出修改结果。"),
            ("转英文", "Translate this into natural, idiomatic English. Output only the translation."),
            ("加Emoji", "给这段话自然地加上贴合语境的 Emoji 表情，只输出修改结果。"),
        ]
        for (title, instruction) in refinements {
            let chip = ActionClosureButton(type: .system)
            chip.setTitle("↻ \(title)", for: .normal)
            chip.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
            chip.layer.cornerRadius = 11
            chip.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
            chip.actionHandler = { [weak self] in
                self?.refineCurrentOutput(instruction: instruction)
            }
            refineStack.addArrangedSubview(chip)
        }

        bottomBar.axis = .horizontal
        bottomBar.distribution = .fillEqually
        bottomBar.spacing = 8
        addSubview(bottomBar)

        stopOrRetryButton.setTitle("换个说法", for: .normal)
        stopOrRetryButton.actionHandler = { [weak self] in self?.handleStopOrRetry() }

        replaceButton.setTitle("替换原文", for: .normal)
        replaceButton.actionHandler = { [weak self] in self?.handleReplace() }

        insertButton.setTitle("插入光标", for: .normal)
        insertButton.actionHandler = { [weak self] in self?.handleInsert() }

        for btn in [stopOrRetryButton, replaceButton, insertButton] {
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            btn.layer.cornerRadius = 8
            btn.layer.cornerCurve = .continuous
            bottomBar.addArrangedSubview(btn)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 8
        topBar.frame = CGRect(x: pad, y: 6, width: bounds.width - pad * 2, height: 28)
        let sourceRect = CGRect(x: pad + 2, y: topBar.frame.maxY + 4, width: bounds.width - pad * 2 - 4, height: 16)
        sourceScroll.frame = sourceRect
        let fitSource = sourceLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: sourceRect.height))
        let sourceW = max(sourceRect.width, ceil(fitSource.width) + 8)
        sourceLabel.frame = CGRect(x: 0, y: 0, width: sourceW, height: sourceRect.height)
        sourceScroll.contentSize = CGSize(width: sourceW, height: sourceRect.height)

        let actY = sourceScroll.frame.maxY + 5
        actionsScroll.frame = CGRect(x: 0, y: actY, width: bounds.width, height: 32)
        let stackW = max(bounds.width - pad * 2, actionsStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
        actionsStack.frame = CGRect(x: pad, y: 0, width: stackW, height: 32)
        actionsScroll.contentSize = CGSize(width: stackW + pad * 2, height: 32)

        let bottomH: CGFloat = 34
        bottomBar.frame = CGRect(x: pad, y: bounds.height - bottomH - 6, width: bounds.width - pad * 2, height: bottomH)

        let refineH: CGFloat = refineScroll.isHidden ? 0 : 28
        if !refineScroll.isHidden {
            refineScroll.frame = CGRect(x: 0, y: bottomBar.frame.minY - refineH - 4, width: bounds.width, height: refineH)
            let rw = max(bounds.width - pad * 2, refineStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
            refineStack.frame = CGRect(x: pad, y: 0, width: rw, height: refineH)
            refineScroll.contentSize = CGSize(width: rw + pad * 2, height: refineH)
        }

        var contentY = actionsScroll.frame.maxY + 5
        let contentBottom = refineScroll.isHidden ? bottomBar.frame.minY : refineScroll.frame.minY

        if !thoughtToggleButton.isHidden {
            thoughtToggleButton.frame = CGRect(x: pad, y: contentY, width: bounds.width - pad * 2, height: 22)
            contentY = thoughtToggleButton.frame.maxY + 3
            if isThinkingExpanded {
                thoughtTextView.isHidden = false
                let thH = min(56, max(32, (contentBottom - contentY) * 0.36))
                thoughtTextView.frame = CGRect(x: pad, y: contentY, width: bounds.width - pad * 2, height: thH)
                contentY = thoughtTextView.frame.maxY + 4
            } else {
                thoughtTextView.isHidden = true
            }
        } else {
            thoughtTextView.isHidden = true
        }

        let contentRect = CGRect(x: pad, y: contentY, width: bounds.width - pad * 2, height: max(36, contentBottom - contentY - 6))
        outputTextView.frame = contentRect

        if !strategistScroll.isHidden {
            strategistScroll.frame = contentRect
            let sw = max(80, contentRect.width)
            let fit = strategistStack.systemLayoutSizeFitting(
                CGSize(width: sw, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            strategistStack.frame = CGRect(x: 0, y: 0, width: sw, height: fit.height)
            strategistScroll.contentSize = CGSize(width: sw, height: fit.height + 6)
        }
    }

    func prepare(
        theme: ResolvedTheme,
        hasFullAccess: Bool,
        beforeCursor: String,
        clipboardText: String?,
        preferredAction: AIPresetAction? = nil
    ) {
        self.theme = theme
        self.hasFullAccess = hasFullAccess
        let nonLeading = String(beforeCursor.drop(while: { $0.isWhitespace }))
        self.beforeCursorText = nonLeading.trimmingCharacters(in: .whitespacesAndNewlines)
        self.beforeCursorReplaceCount = self.beforeCursorText.count
        self.clipboardText = (clipboardText ?? ClipboardStore.items().first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if let preferredAction {
            if preferredAction.needsClipboardFallback && !self.clipboardText.isEmpty {
                sourceMode = .clipboard
            } else {
                sourceMode = self.beforeCursorText.isEmpty && !self.clipboardText.isEmpty ? .clipboard : .inputContext
            }
            contextSegmented.selectedSegmentIndex = sourceMode.rawValue
        } else {
            sourceMode = (self.beforeCursorText.isEmpty && !self.clipboardText.isEmpty) ? .clipboard : .inputContext
            contextSegmented.selectedSegmentIndex = sourceMode.rawValue
        }

        refreshTopQuickPills()
        applyTheme(theme)
        reloadPromptsAndRecommendation()
        rebuildActionButtons(theme: theme)
        refreshContextPreview()

        if let preferredAction {
            runAction(preferredAction)
        } else if generatedText.isEmpty && strategistResult == nil {
            showIdleGuidance()
        }
    }

    /// 供「框选即改」或「剪贴板意图胶囊」直接注入自定义指令并立即流式运行。
    func runDirectInstruction(
        title: String,
        instruction: String,
        sourceText: String,
        replaceCount: Int,
        theme: ResolvedTheme,
        hasFullAccess: Bool
    ) {
        self.theme = theme
        self.hasFullAccess = hasFullAccess
        self.beforeCursorText = sourceText
        self.beforeCursorReplaceCount = replaceCount
        self.sourceMode = replaceCount > 0 ? .inputContext : .clipboard
        contextSegmented.selectedSegmentIndex = sourceMode.rawValue

        refreshTopQuickPills()
        applyTheme(theme)
        reloadPromptsAndRecommendation()
        rebuildActionButtons(theme: theme)
        sourceLabel.text = "⚡ \(title)  |  \(sourceText.replacingOccurrences(of: "\n", with: " "))"
        lastCustomTemplateID = nil
        lastCustomPrompt = (sourceText, instruction)
        streamPrompt(prompt: sourceText, systemInstruction: instruction, preferFast: true)
    }

    private func refreshTopQuickPills() {
        let cfg = AIConfig.load()
        let sceneShort = cfg.activeScenePersona == .auto ? "场景" : String(cfg.activeScenePersona.shortTitle.prefix(4))
        sceneButton.setTitle(sceneShort, for: .normal)
        thinkingButton.setTitle("🧠\(cfg.thinkingMode.shortBadge)", for: .normal)
    }

    private func cycleScenePersona() {
        var cfg = AIConfig.load()
        let all = AIScenePersona.allCases
        if let idx = all.firstIndex(of: cfg.activeScenePersona) {
            cfg.activeScenePersona = all[(idx + 1) % all.count]
        } else {
            cfg.activeScenePersona = .bossClient
        }
        cfg.save()
        refreshTopQuickPills()
        if let theme { applyTheme(theme) }
        sourceLabel.text = "✨ 已切换沟通对象：\(cfg.activeScenePersona.shortTitle)"
        setNeedsLayout()
    }

    private func cycleThinkingMode() {
        var cfg = AIConfig.load()
        let modes: [AIThinkingMode] = [.off, .auto, .low, .medium, .high]
        if let idx = modes.firstIndex(of: cfg.thinkingMode) {
            cfg.thinkingMode = modes[(idx + 1) % modes.count]
        } else {
            cfg.thinkingMode = .medium
        }
        cfg.save()
        refreshTopQuickPills()
        if let theme { applyTheme(theme) }
        sourceLabel.text = "🧠 思考模式已切换：\(cfg.thinkingMode.displayName)"
        setNeedsLayout()
    }

    private func reloadPromptsAndRecommendation() {
        let cfg = AIConfig.load()
        cachedCustomPrompts = cfg.customPrompts
        if cfg.smartContextRecommendEnabled {
            let text = sourceMode == .inputContext ? beforeCursorText : clipboardText
            currentRecommendation = SmartContextPromptDetector.analyze(
                text: text,
                isClipboard: sourceMode == .clipboard,
                customPrompts: cachedCustomPrompts
            )
        } else {
            currentRecommendation = nil
        }
    }

    private func applyTheme(_ theme: ResolvedTheme) {
        backgroundColor = theme.canvasTop.withAlphaComponent(0.98)
        contextSegmented.selectedSegmentTintColor = theme.accentFill
        contextSegmented.backgroundColor = theme.specialKeyFill
        contextSegmented.setTitleTextAttributes([.foregroundColor: theme.accentText, .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold)], for: .selected)
        contextSegmented.setTitleTextAttributes([.foregroundColor: theme.keyText, .font: UIFont.systemFont(ofSize: 11.5, weight: .medium)], for: .normal)

        let cfg = AIConfig.load()
        sceneButton.backgroundColor = cfg.activeScenePersona == .auto ? theme.specialKeyFill : theme.accentFill.withAlphaComponent(0.22)
        sceneButton.setTitleColor(cfg.activeScenePersona == .auto ? theme.keyText : theme.candidateHighlight, for: .normal)

        thinkingButton.backgroundColor = cfg.thinkingMode.isEnabled ? theme.accentFill.withAlphaComponent(0.22) : theme.specialKeyFill
        thinkingButton.setTitleColor(cfg.thinkingMode.isEnabled ? theme.candidateHighlight : theme.keyHintText, for: .normal)

        askFreeButton.backgroundColor = theme.accentFill.withAlphaComponent(0.18)
        askFreeButton.setTitleColor(theme.candidateHighlight, for: .normal)
        closeButton.backgroundColor = theme.specialKeyFill
        closeButton.setTitleColor(theme.keyText, for: .normal)
        sourceLabel.textColor = theme.keyHintText

        thoughtToggleButton.backgroundColor = theme.specialKeyFill.withAlphaComponent(0.85)
        thoughtToggleButton.setTitleColor(theme.keyHintText, for: .normal)
        thoughtTextView.backgroundColor = theme.specialKeyFill.withAlphaComponent(0.55)
        thoughtTextView.textColor = theme.keyHintText

        outputTextView.backgroundColor = theme.keyFill.withAlphaComponent(0.95)
        outputTextView.textColor = theme.keyText

        for sub in refineStack.arrangedSubviews {
            if let btn = sub as? UIButton {
                btn.backgroundColor = theme.specialKeyFill
                btn.setTitleColor(theme.keyText, for: .normal)
            }
        }

        stopOrRetryButton.backgroundColor = theme.specialKeyFill
        stopOrRetryButton.setTitleColor(theme.keyText, for: .normal)

        replaceButton.backgroundColor = theme.specialKeyFill
        replaceButton.setTitleColor(theme.keyText, for: .normal)

        insertButton.backgroundColor = theme.accentFill
        insertButton.setTitleColor(theme.accentText, for: .normal)
    }

    private func rebuildActionButtons(theme: ResolvedTheme) {
        actionsStack.arrangedSubviews.forEach {
            actionsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let recCustomIDs = currentRecommendation?.recommendedCustomIDs ?? []
        let recPresets = currentRecommendation?.recommendedPresets ?? []
        let recCustomSet = Set(recCustomIDs)
        let recPresetSet = Set(recPresets)

        var orderedCustom: [CustomAIPromptTemplate] = []
        var seenCustom = Set<String>()
        for id in recCustomIDs {
            if let tpl = cachedCustomPrompts.first(where: { $0.id == id }), seenCustom.insert(tpl.id).inserted {
                orderedCustom.append(tpl)
            }
        }
        for tpl in cachedCustomPrompts where (tpl.isPinned || tpl.isAIGenerated) && seenCustom.insert(tpl.id).inserted {
            orderedCustom.append(tpl)
        }
        for tpl in cachedCustomPrompts where seenCustom.insert(tpl.id).inserted {
            orderedCustom.append(tpl)
        }

        var orderedPresets: [AIPresetAction] = []
        var seenPresets = Set<AIPresetAction>()
        for act in recPresets where seenPresets.insert(act).inserted {
            orderedPresets.append(act)
        }
        for act in AIPresetAction.allCases where seenPresets.insert(act).inserted {
            orderedPresets.append(act)
        }

        func makeSkillPill(title: String, isSelected: Bool, isRecommended: Bool, isCustom: Bool, handler: @escaping () -> Void) {
            let btn = ActionClosureButton(type: .system)
            let prefix = isRecommended ? "✦ " : (isCustom ? "★ " : "")
            btn.setTitle("\(prefix)\(title)", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            btn.backgroundColor = isSelected
                ? theme.accentFill
                : (isRecommended ? theme.accentFill.withAlphaComponent(0.22) : theme.keyFill)
            btn.setTitleColor(isSelected ? theme.accentText : (isRecommended ? theme.candidateHighlight : theme.keyText), for: .normal)
            btn.layer.cornerRadius = 14
            btn.layer.cornerCurve = .continuous
            if isRecommended && !isSelected {
                btn.layer.borderWidth = 0.8
                btn.layer.borderColor = theme.accentFill.withAlphaComponent(0.55).cgColor
            } else if !isSelected {
                btn.layer.borderWidth = 0.5
                btn.layer.borderColor = theme.keyBorder.cgColor
            } else {
                btn.layer.borderWidth = 0
            }
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 11, bottom: 5, right: 11)
            btn.actionHandler = handler
            actionsStack.addArrangedSubview(btn)
        }

        for tpl in orderedCustom where recCustomSet.contains(tpl.id) {
            makeSkillPill(title: tpl.title, isSelected: lastCustomTemplateID == tpl.id, isRecommended: true, isCustom: true) { [weak self] in
                self?.runCustomTemplate(tpl)
            }
        }
        for action in orderedPresets where recPresetSet.contains(action) {
            makeSkillPill(title: action.title, isSelected: action == lastAction && lastCustomPrompt == nil && lastCustomTemplateID == nil, isRecommended: true, isCustom: false) { [weak self] in
                self?.runAction(action)
            }
        }
        for tpl in orderedCustom where !recCustomSet.contains(tpl.id) {
            makeSkillPill(title: tpl.title, isSelected: lastCustomTemplateID == tpl.id, isRecommended: false, isCustom: true) { [weak self] in
                self?.runCustomTemplate(tpl)
            }
        }
        for action in orderedPresets where !recPresetSet.contains(action) {
            makeSkillPill(title: action.title, isSelected: action == lastAction && lastCustomPrompt == nil && lastCustomTemplateID == nil, isRecommended: false, isCustom: false) { [weak self] in
                self?.runAction(action)
            }
        }
        setNeedsLayout()
    }

    private func activeSourceText(for action: AIPresetAction) -> String {
        if action.needsClipboardFallback && !clipboardText.isEmpty && sourceMode == .clipboard {
            return clipboardText
        }
        switch sourceMode {
        case .inputContext:
            return beforeCursorText.isEmpty ? clipboardText : beforeCursorText
        case .clipboard:
            return clipboardText.isEmpty ? beforeCursorText : clipboardText
        }
    }

    private func refreshContextPreview() {
        let text = sourceMode == .inputContext ? beforeCursorText : clipboardText
        let badgePrefix = currentRecommendation.map { "\($0.badgeTitle)  |  " } ?? ""
        if text.isEmpty {
            sourceLabel.text = sourceMode == .inputContext
                ? "\(badgePrefix)语境：输入框为空（可先打字或切换到剪贴板）"
                : "\(badgePrefix)语境：暂无剪贴板记录"
        } else {
            let compact = text.replacingOccurrences(of: "\n", with: " ")
            sourceLabel.text = "\(badgePrefix)语境：\(compact)"
        }
        setNeedsLayout()
    }

    private func showIdleGuidance() {
        let config = AIConfig.load()
        strategistScroll.isHidden = true
        outputTextView.isHidden = false
        thoughtToggleButton.isHidden = true
        thoughtTextView.isHidden = true
        if !hasFullAccess {
            outputTextView.text = "⚠️ 请前往 系统设置 -> 通用 -> 键盘 -> 灵犀输入法 开启「允许完全访问」，键盘扩展才可联网请求 AI。"
        } else if !config.isConfigured {
            outputTextView.text = "✨ 尚未配置 API Key。请打开主 App「灵犀输入法 -> AI 智脑」，支持一键拉取模型或手动填写，并可配置思考模式。"
        } else {
            let customCount = config.customPrompts.count
            let recNote = currentRecommendation.map { "（\($0.badgeTitle)）" } ?? ""
            outputTextView.text = "点击上方带「✦」的智能推荐技能、「博弈军师」三策略回复，或你的 \(customCount) 个专属提示词即可实时流式生成\(recNote)。顶部可随时切换沟通对象与思考模式。"
        }
        updateActionButtonsEnabled()
    }

    func runCustomQuestion(
        _ question: String,
        theme: ResolvedTheme,
        hasFullAccess: Bool,
        beforeCursor: String
    ) {
        self.theme = theme
        self.hasFullAccess = hasFullAccess
        let nonLeading = String(beforeCursor.drop(while: { $0.isWhitespace }))
        self.beforeCursorText = nonLeading.trimmingCharacters(in: .whitespacesAndNewlines)
        self.beforeCursorReplaceCount = self.beforeCursorText.count
        refreshTopQuickPills()
        applyTheme(theme)
        reloadPromptsAndRecommendation()
        rebuildActionButtons(theme: theme)

        sourceLabel.text = "提问：\(question)"
        let contextNote = beforeCursorText.isEmpty ? "" : "\n\n【当前输入上下文参考】\n\(beforeCursorText)"
        let fullPrompt = question + contextNote
        let sysPrompt = "你是内嵌在 iOS 输入法中的灵犀 AI 助手。请直接给出高质量、简洁、可直接发送给对方的回复或答案，不要过多客套。"

        lastCustomTemplateID = nil
        lastCustomPrompt = (fullPrompt, sysPrompt)
        streamPrompt(prompt: fullPrompt, systemInstruction: sysPrompt)
    }

    private func runCustomTemplate(_ template: CustomAIPromptTemplate) {
        lastCustomTemplateID = template.id
        if let theme { rebuildActionButtons(theme: theme) }
        let source: String
        switch sourceMode {
        case .inputContext:
            source = beforeCursorText.isEmpty ? clipboardText : beforeCursorText
        case .clipboard:
            source = clipboardText.isEmpty ? beforeCursorText : clipboardText
        }
        guard !source.isEmpty else {
            strategistScroll.isHidden = true
            outputTextView.isHidden = false
            outputTextView.text = "请先在输入框中写几句话，或先复制一段内容，再点上方「\(template.title)」提示词技能。"
            return
        }
        let sys = template.effectiveSystemPrompt
        lastCustomPrompt = (source, sys)
        streamPrompt(prompt: source, systemInstruction: sys, preferDeep: template.useDeepModel)
    }

    private func runAction(_ action: AIPresetAction) {
        lastAction = action
        lastCustomTemplateID = nil
        lastCustomPrompt = nil
        if let theme { rebuildActionButtons(theme: theme) }
        let source = activeSourceText(for: action)
        guard !source.isEmpty else {
            strategistScroll.isHidden = true
            outputTextView.isHidden = false
            outputTextView.text = "请先在输入框中写几句话，或先复制一段内容，再点上方 AI 技能。"
            return
        }
        if action == .strategist {
            runStrategistMode(message: source)
            return
        }
        streamPrompt(prompt: source, systemInstruction: action.systemPrompt, preferFast: !action.prefersDeepModel, preferDeep: action.prefersDeepModel)
    }

    private func runStrategistMode(message: String) {
        streamTask?.cancel()
        guard hasFullAccess else {
            outputTextView.text = "⚠️ 需要开启「允许完全访问」才可调用博弈军师。"
            return
        }
        let config = AIConfig.load()
        guard config.isConfigured else {
            outputTextView.text = "⚠️ 请先在主 App「AI 智脑」配置模型与 API Key。"
            return
        }

        strategistResult = nil
        strategistScroll.isHidden = true
        outputTextView.isHidden = false
        thoughtToggleButton.isHidden = true
        thoughtTextView.isHidden = true
        generatedText = ""
        outputTextView.text = "🧠 博弈军师正在洞察对方潜台词并拟定 3 套策略回复…"
        stopOrRetryButton.setTitle("停止生成", for: .normal)
        updateActionButtonsEnabled()

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let res = try await AIAutoInsightService.runNegotiationStrategist(message: message, config: config, client: self.client)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.strategistResult = res
                    self.renderStrategistCards(res)
                    self.stopOrRetryButton.setTitle("换三套策略", for: .normal)
                    self.updateActionButtonsEnabled()
                }
            } catch {
                await MainActor.run {
                    self.strategistScroll.isHidden = true
                    self.outputTextView.isHidden = false
                    self.outputTextView.text = "博弈军师生成失败：\(error.localizedDescription)"
                    self.stopOrRetryButton.setTitle("重试", for: .normal)
                    self.updateActionButtonsEnabled()
                }
            }
        }
    }

    private func renderStrategistCards(_ res: NegotiationStrategistResult) {
        guard let theme else { return }
        strategistStack.arrangedSubviews.forEach {
            strategistStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let insightLbl = UILabel()
        insightLbl.text = "🔍 潜台词洞察：\(res.subtext)"
        insightLbl.font = .systemFont(ofSize: 12, weight: .semibold)
        insightLbl.textColor = theme.candidateHighlight
        insightLbl.numberOfLines = 0
        strategistStack.addArrangedSubview(insightLbl)

        for opt in res.options {
            let card = ActionClosureButton(type: .custom)
            card.backgroundColor = theme.keyFill.withAlphaComponent(0.95)
            card.layer.cornerRadius = 10
            card.layer.cornerCurve = .continuous
            card.layer.borderWidth = 0.6
            card.layer.borderColor = theme.keyBorder.cgColor
            card.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
            card.contentHorizontalAlignment = .leading
            card.titleLabel?.numberOfLines = 0
            card.titleLabel?.lineBreakMode = .byWordWrapping

            let attr = NSMutableAttributedString(
                string: "\(opt.tag) · \(opt.toneLabel)\n",
                attributes: [.font: UIFont.systemFont(ofSize: 11.5, weight: .bold), .foregroundColor: theme.candidateHighlight]
            )
            attr.append(NSAttributedString(
                string: opt.reply,
                attributes: [.font: UIFont.systemFont(ofSize: 13.5, weight: .regular), .foregroundColor: theme.keyText]
            ))
            card.setAttributedTitle(attr, for: .normal)
            card.actionHandler = { [weak self] in
                self?.onInsertText?(opt.reply)
            }
            strategistStack.addArrangedSubview(card)
        }

        outputTextView.isHidden = true
        strategistScroll.isHidden = false
        setNeedsLayout()
    }

    private func updateThoughtHeader() {
        let arrow = isThinkingExpanded ? "▾" : "▸"
        thoughtToggleButton.setTitle("💭 思考过程（\(thinkingText.count) 字 · 点击\(isThinkingExpanded ? "收起" : "展开")）\(arrow)", for: .normal)
    }

    private func streamPrompt(prompt: String, systemInstruction: String, preferFast: Bool = false, preferDeep: Bool = false) {
        streamTask?.cancel()

        guard hasFullAccess else {
            outputTextView.text = "⚠️ 需要开启「允许完全访问」才可联网调用 AI。"
            return
        }

        let config = AIConfig.load()
        guard config.isConfigured else {
            outputTextView.text = "⚠️ 请先在「灵犀输入法 App -> AI 智脑」配置 API Key。"
            return
        }

        strategistResult = nil
        strategistScroll.isHidden = true
        outputTextView.isHidden = false
        generatedText = ""
        thinkingText = ""
        isThinkingExpanded = false
        thoughtToggleButton.isHidden = true
        thoughtTextView.isHidden = true
        thoughtTextView.text = ""
        outputTextView.text = config.thinkingMode.isEnabled ? "🧠 灵犀正在思考中…" : "✨ 灵犀正在生成…"
        stopOrRetryButton.setTitle("停止生成", for: .normal)
        updateActionButtonsEnabled()

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                var accumulatedAnswer = ""
                var accumulatedThought = ""
                let featureTag = self.lastCustomPrompt != nil ? "ai_ask" : self.lastAction.rawValue
                for try await event in client.streamEvents(
                    prompt: prompt,
                    systemInstruction: systemInstruction,
                    config: config,
                    featureTag: featureTag,
                    preferFast: preferFast,
                    preferDeep: preferDeep
                ) {
                    if Task.isCancelled { break }
                    switch event {
                    case .thought(let delta):
                        accumulatedThought += delta
                        if config.showThinkingProcess {
                            await MainActor.run {
                                self.thinkingText = accumulatedThought
                                self.thoughtToggleButton.isHidden = false
                                self.updateThoughtHeader()
                                self.thoughtTextView.text = accumulatedThought
                                if self.generatedText.isEmpty {
                                    self.outputTextView.text = "🧠 深度思考中（已推演 \(accumulatedThought.count) 字，点上方可展开过程）…"
                                }
                                self.setNeedsLayout()
                            }
                        }
                    case .answer(let delta):
                        accumulatedAnswer += delta
                        await MainActor.run {
                            self.generatedText = accumulatedAnswer
                            self.outputTextView.text = accumulatedAnswer
                            let end = NSRange(location: max(0, accumulatedAnswer.utf16.count - 1), length: 0)
                            self.outputTextView.scrollRangeToVisible(end)
                        }
                    }
                }
                await MainActor.run {
                    if self.generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.outputTextView.text = "⚠️ 模型未返回有效正文，请检查模型或思考模式设置后重试"
                    }
                    self.stopOrRetryButton.setTitle("换个说法", for: .normal)
                    self.updateActionButtonsEnabled()
                }
            } catch {
                await MainActor.run {
                    self.outputTextView.text = "生成出错：\(error.localizedDescription)"
                    self.stopOrRetryButton.setTitle("重试", for: .normal)
                    self.updateActionButtonsEnabled()
                }
            }
        }
    }

    private func refineCurrentOutput(instruction: String) {
        let current = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return }
        lastCustomPrompt = (current, instruction)
        streamPrompt(prompt: current, systemInstruction: instruction, preferFast: true)
    }

    private func updateActionButtonsEnabled() {
        let ready = !generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        refineScroll.isHidden = !ready || !strategistScroll.isHidden
        setNeedsLayout()
        insertButton.isEnabled = ready
        insertButton.alpha = ready ? 1.0 : 0.48
        let canReplace = ready && sourceMode == .inputContext && beforeCursorReplaceCount > 0
        replaceButton.isEnabled = canReplace
        replaceButton.alpha = canReplace ? 1.0 : 0.45
    }

    @objc private func sourceChanged() {
        sourceMode = SourceMode(rawValue: contextSegmented.selectedSegmentIndex) ?? .inputContext
        reloadPromptsAndRecommendation()
        if let theme { rebuildActionButtons(theme: theme) }
        refreshContextPreview()
        updateActionButtonsEnabled()
    }

    private func handleStopOrRetry() {
        if let task = streamTask, !task.isCancelled, stopOrRetryButton.title(for: .normal) == "停止生成" {
            task.cancel()
            stopOrRetryButton.setTitle("换个说法", for: .normal)
        } else if let custom = lastCustomPrompt {
            streamPrompt(prompt: custom.prompt, systemInstruction: custom.sys)
        } else {
            runAction(lastAction)
        }
    }

    private func handleReplace() {
        let trimmed = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, beforeCursorReplaceCount > 0 else { return }
        onReplaceBeforeCursor?(beforeCursorReplaceCount, trimmed)
    }

    private func handleInsert() {
        let trimmed = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onInsertText?(trimmed)
    }
}
