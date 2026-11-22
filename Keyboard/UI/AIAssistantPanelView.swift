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
    private var generatedText = ""

    // UI
    private let topBar = UIStackView()
    private let contextSegmented = UISegmentedControl(items: ["当前输入", "剪贴板"])
    private let askFreeButton = ActionClosureButton(type: .system)
    private let closeButton = ActionClosureButton(type: .system)

    private let sourceLabel = UILabel()
    private let actionsScroll = UIScrollView()
    private let actionsStack = UIStackView()
    private let outputTextView = UITextView()
    private let refineScroll = UIScrollView()
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
        askFreeButton.actionHandler = { [weak self] in
            self?.streamTask?.cancel()
            self?.onRequestPromptInput?()
        }
        topBar.addArrangedSubview(askFreeButton)

        closeButton.setTitle("返回", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        closeButton.layer.cornerRadius = 8
        closeButton.actionHandler = { [weak self] in
            self?.streamTask?.cancel()
            self?.onClose?()
        }
        topBar.addArrangedSubview(closeButton)

        sourceLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        sourceLabel.numberOfLines = 1
        sourceLabel.lineBreakMode = .byTruncatingTail
        addSubview(sourceLabel)

        actionsScroll.showsHorizontalScrollIndicator = false
        addSubview(actionsScroll)
        actionsStack.axis = .horizontal
        actionsStack.spacing = 6
        actionsStack.alignment = .center
        actionsScroll.addSubview(actionsStack)

        outputTextView.isEditable = false
        outputTextView.font = .systemFont(ofSize: 14, weight: .regular)
        outputTextView.layer.cornerRadius = 10
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
            bottomBar.addArrangedSubview(btn)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 8
        topBar.frame = CGRect(x: pad, y: 6, width: bounds.width - pad * 2, height: 28)
        sourceLabel.frame = CGRect(x: pad + 2, y: topBar.frame.maxY + 4, width: bounds.width - pad * 2 - 4, height: 15)

        let actY = sourceLabel.frame.maxY + 5
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
        rebuildActionButtons(theme: theme)
        refreshContextPreview()

        if let preferredAction {
            runAction(preferredAction)
        } else if generatedText.isEmpty {
            showIdleGuidance()
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
        for action in AIPresetAction.allCases {
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(action.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            btn.backgroundColor = theme.accentFill.withAlphaComponent(0.15)
            btn.setTitleColor(theme.candidateHighlight, for: .normal)
            btn.layer.cornerRadius = 14
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 11, bottom: 5, right: 11)
            btn.actionHandler = { [weak self] in
                self?.runAction(action)
            }
            actionsStack.addArrangedSubview(btn)
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
        if text.isEmpty {
            sourceLabel.text = sourceMode == .inputContext
                ? "语境：输入框为空（可先打字或切换到剪贴板）"
                : "语境：暂无剪贴板记录"
        } else {
            let compact = text.replacingOccurrences(of: "\n", with: " ")
            sourceLabel.text = "语境：\(compact)"
        }
    }

    private func showIdleGuidance() {
        let config = AIConfig.load()
        if !hasFullAccess {
            outputTextView.text = "⚠️ 请前往 系统设置 -> 通用 -> 键盘 -> 灵犀输入法 开启「允许完全访问」，键盘扩展才可联网请求 AI。"
        } else if !config.isConfigured {
            outputTextView.text = "✨ 尚未配置 API Key。请打开主 App「灵犀输入法 -> AI 助手」，填入 Gemini API Key 或 DeepSeek 等兼容接口密钥。"
        } else {
            outputTextView.text = "点击上方任意技能（如「润色优化」「高情商回复」「译为英文」「小红书风」），即可实时流式生成并一键上屏。"
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
        rebuildActionButtons(theme: theme)

        sourceLabel.text = "提问：\(question)"
        let contextNote = beforeCursorText.isEmpty ? "" : "\n\n【当前输入上下文参考】\n\(beforeCursorText)"
        let fullPrompt = question + contextNote
        let sysPrompt = "你是内嵌在 iOS 输入法中的灵犀 AI 助手。请直接给出高质量、简洁、可直接发送给对方的回复或答案，不要过多客套。"

        lastCustomPrompt = (fullPrompt, sysPrompt)
        streamPrompt(prompt: fullPrompt, systemInstruction: sysPrompt)
    }

    private var lastCustomPrompt: (prompt: String, sys: String)?

    private func runAction(_ action: AIPresetAction) {
        lastAction = action
        lastCustomPrompt = nil
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
