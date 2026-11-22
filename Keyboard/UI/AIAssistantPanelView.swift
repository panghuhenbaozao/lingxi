import UIKit

/// 内嵌 AI 灵犀写作面板（流式响应、上下文改写、回复剪贴板、趣味文风）。
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

    // UI
    private let topBar = UIStackView()
    private let contextSegmented = UISegmentedControl(items: ["当前输入", "剪贴板"])
    private let askFreeButton = ActionClosureButton(type: .system)
    private let closeButton = ActionClosureButton(type: .system)

    private let sourceScroll = LingxiScrollView()
    private let sourceLabel = UILabel()
    private let actionsScroll = LingxiScrollView()
    private let actionsStack = UIStackView()
    private let outputTextView = UITextView()
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
        topBar.spacing = 8
        topBar.alignment = .center
        addSubview(topBar)

        contextSegmented.selectedSegmentIndex = 0
        contextSegmented.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)
        topBar.addArrangedSubview(contextSegmented)

        askFreeButton.setTitle("💬自由问", for: .normal)
        askFreeButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        askFreeButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 9, bottom: 5, right: 9)
        askFreeButton.layer.cornerRadius = 8
        askFreeButton.layer.cornerCurve = .continuous
        askFreeButton.actionHandler = { [weak self] in
            self?.streamTask?.cancel()
            self?.onRequestPromptInput?()
        }
        topBar.addArrangedSubview(askFreeButton)

        closeButton.setTitle("返回", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
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

        outputTextView.isEditable = false
        outputTextView.font = .systemFont(ofSize: 14, weight: .regular)
        outputTextView.layer.cornerRadius = 10
        outputTextView.layer.cornerCurve = .continuous
        outputTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        addSubview(outputTextView)

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

        let outY = actionsScroll.frame.maxY + 6
        let outBottom = refineScroll.isHidden ? bottomBar.frame.minY : refineScroll.frame.minY
        outputTextView.frame = CGRect(x: pad, y: outY, width: bounds.width - pad * 2, height: max(36, outBottom - outY - 6))
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
        // 替换计数只算到剥除尾部空白后的文本，不吞用户的尾随空格
        self.beforeCursorReplaceCount = self.beforeCursorText.count
        self.clipboardText = (clipboardText ?? ClipboardStore.items().first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if let preferredAction {
            if preferredAction == .replyClipboard && !self.clipboardText.isEmpty {
                sourceMode = .clipboard
            } else {
                sourceMode = self.beforeCursorText.isEmpty && !self.clipboardText.isEmpty ? .clipboard : .inputContext
            }
            contextSegmented.selectedSegmentIndex = sourceMode.rawValue
        } else {
            sourceMode = (self.beforeCursorText.isEmpty && !self.clipboardText.isEmpty) ? .clipboard : .inputContext
            contextSegmented.selectedSegmentIndex = sourceMode.rawValue
        }

        applyTheme(theme)
        reloadPromptsAndRecommendation()
        rebuildActionButtons(theme: theme)
        refreshContextPreview()

        if let preferredAction {
            runAction(preferredAction)
        } else if generatedText.isEmpty {
            showIdleGuidance()
        }
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
        backgroundColor = theme.canvasTop.withAlphaComponent(0.96)
        contextSegmented.selectedSegmentTintColor = theme.accentFill
        contextSegmented.backgroundColor = theme.specialKeyFill
        contextSegmented.setTitleTextAttributes([.foregroundColor: theme.accentText], for: .selected)
        contextSegmented.setTitleTextAttributes([.foregroundColor: theme.keyText], for: .normal)
        askFreeButton.backgroundColor = theme.accentFill.withAlphaComponent(0.18)
        askFreeButton.setTitleColor(theme.candidateHighlight, for: .normal)
        closeButton.backgroundColor = theme.specialKeyFill
        closeButton.setTitleColor(theme.keyText, for: .normal)
        sourceLabel.textColor = theme.keyHintText

        outputTextView.backgroundColor = theme.keyFill.withAlphaComponent(0.9)
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

        // 1. 语境智能推荐的自定义提示词优先置顶
        var orderedCustom: [CustomAIPromptTemplate] = []
        var seenCustom = Set<String>()
        for id in recCustomIDs {
            if let tpl = cachedCustomPrompts.first(where: { $0.id == id }), seenCustom.insert(tpl.id).inserted {
                orderedCustom.append(tpl)
            }
        }
        // 2. 其余置顶/AI 定制提示词
        for tpl in cachedCustomPrompts where (tpl.isPinned || tpl.isAIGenerated) && seenCustom.insert(tpl.id).inserted {
            orderedCustom.append(tpl)
        }
        for tpl in cachedCustomPrompts where seenCustom.insert(tpl.id).inserted {
            orderedCustom.append(tpl)
        }

        // 3. 语境智能推荐的内置预设技能放前排，其余内置技能紧随其后
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
                : (isRecommended ? theme.accentFill.withAlphaComponent(0.22) : theme.accentFill.withAlphaComponent(0.12))
            btn.setTitleColor(isSelected ? theme.accentText : theme.candidateHighlight, for: .normal)
            btn.layer.cornerRadius = 14
            btn.layer.cornerCurve = .continuous
            if isRecommended && !isSelected {
                btn.layer.borderWidth = 0.8
                btn.layer.borderColor = theme.accentFill.withAlphaComponent(0.45).cgColor
            } else {
                btn.layer.borderWidth = 0
            }
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 11, bottom: 5, right: 11)
            btn.actionHandler = handler
            actionsStack.addArrangedSubview(btn)
        }

        // 先放语境推荐的内置 Top-2 与推荐自定义提示词，再放其余自定义与内置技能，兼顾顺手与发现性
        for tpl in orderedCustom where recCustomSet.contains(tpl.id) {
            makeSkillPill(
                title: tpl.title,
                isSelected: lastCustomTemplateID == tpl.id,
                isRecommended: true,
                isCustom: true
            ) { [weak self] in
                self?.runCustomTemplate(tpl)
            }
        }
        for action in orderedPresets where recPresetSet.contains(action) {
            makeSkillPill(
                title: action.title,
                isSelected: action == lastAction && lastCustomPrompt == nil && lastCustomTemplateID == nil,
                isRecommended: true,
                isCustom: false
            ) { [weak self] in
                self?.runAction(action)
            }
        }
        for tpl in orderedCustom where !recCustomSet.contains(tpl.id) {
            makeSkillPill(
                title: tpl.title,
                isSelected: lastCustomTemplateID == tpl.id,
                isRecommended: false,
                isCustom: true
            ) { [weak self] in
                self?.runCustomTemplate(tpl)
            }
        }
        for action in orderedPresets where !recPresetSet.contains(action) {
            makeSkillPill(
                title: action.title,
                isSelected: action == lastAction && lastCustomPrompt == nil && lastCustomTemplateID == nil,
                isRecommended: false,
                isCustom: false
            ) { [weak self] in
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
        if !hasFullAccess {
            outputTextView.text = "⚠️ 请前往 系统设置 -> 通用 -> 键盘 -> 灵犀输入法 开启「允许完全访问」，键盘扩展才可联网请求 AI。"
        } else if !config.isConfigured {
            outputTextView.text = "✨ 尚未配置 API Key。请打开主 App「灵犀输入法 -> AI 助手」，填入 Gemini API Key 或 DeepSeek 等兼容接口密钥。"
        } else {
            let customCount = config.customPrompts.count
            let recNote = currentRecommendation.map { "（\($0.badgeTitle)）" } ?? ""
            outputTextView.text = "点击上方带「✦」的智能推荐技能或你的 \(customCount) 个专属提示词，即可实时流式生成并一键上屏\(recNote)。"
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

    private var lastCustomPrompt: (prompt: String, sys: String)?

    private func runCustomTemplate(_ template: CustomAIPromptTemplate) {
        lastCustomTemplateID = template.id
        if let theme {
            rebuildActionButtons(theme: theme)
        }
        let source: String
        switch sourceMode {
        case .inputContext:
            source = beforeCursorText.isEmpty ? clipboardText : beforeCursorText
        case .clipboard:
            source = clipboardText.isEmpty ? beforeCursorText : clipboardText
        }
        guard !source.isEmpty else {
            outputTextView.text = "请先在输入框中写几句话，或先复制一段内容，再点上方「\(template.title)」提示词技能。"
            return
        }
        let sys = template.effectiveSystemPrompt
        lastCustomPrompt = (source, sys)
        streamPrompt(prompt: source, systemInstruction: sys)
    }

    private func runAction(_ action: AIPresetAction) {
        lastAction = action
        lastCustomTemplateID = nil
        lastCustomPrompt = nil
        if let theme {
            rebuildActionButtons(theme: theme)
        }
        let source = activeSourceText(for: action)
        guard !source.isEmpty else {
            outputTextView.text = "请先在输入框中写几句话，或先复制一段内容，再点上方 AI 技能。"
            return
        }
        streamPrompt(prompt: source, systemInstruction: action.systemPrompt)
    }

    private func streamPrompt(prompt: String, systemInstruction: String) {
        streamTask?.cancel()

        guard hasFullAccess else {
            outputTextView.text = "⚠️ 需要开启「允许完全访问」才可联网调用 AI。"
            return
        }

        let config = AIConfig.load()
        guard config.isConfigured else {
            outputTextView.text = "⚠️ 请先在「灵犀输入法 App -> AI 助手」配置 API Key。"
            return
        }

        generatedText = ""
        outputTextView.text = "✨ 灵犀正在思考…"
        stopOrRetryButton.setTitle("停止生成", for: .normal)
        updateActionButtonsEnabled()

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                var accumulated = ""
                let featureTag = self.lastCustomPrompt != nil ? "ai_ask" : self.lastAction.rawValue
                for try await delta in client.streamText(
                    prompt: prompt,
                    systemInstruction: systemInstruction,
                    config: config,
                    featureTag: featureTag
                ) {
                    if Task.isCancelled { break }
                    accumulated += delta
                    await MainActor.run {
                        self.generatedText = accumulated
                        self.outputTextView.text = accumulated
                        let end = NSRange(location: max(0, accumulated.utf16.count - 1), length: 0)
                        self.outputTextView.scrollRangeToVisible(end)
                    }
                }
                await MainActor.run {
                    if self.generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.outputTextView.text = "⚠️ 模型未返回有效内容，请检查模型配置或重试"
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
        streamPrompt(prompt: current, systemInstruction: instruction)
    }

    private func updateActionButtonsEnabled() {
        let ready = !generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        refineScroll.isHidden = !ready
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
        if let theme {
            rebuildActionButtons(theme: theme)
        }
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
