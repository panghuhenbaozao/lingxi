import Photos
import UIKit

/// 极简高效键盘内嵌 AI 工作台（v5.5 升级）：
/// - 顶部「可打字 + 可粘贴」输入框 + 「📷 截屏识图」+ 6 项核心高频技能 + 🕒 历史记录 + ⤢ 阅读拉高；
/// - 全链路流式 45ms 节流刷新 + `AITextSanitizer` 自动净化 `*` / `**` / `###` Markdown 符号；
/// - 支持键盘内直传最新截屏给 AI 多模态识别并在上传后自动清理原截屏。
final class AIAssistantPanelView: UIView, UITextViewDelegate {
    var onInsertText: ((String) -> Void)?
    var onReplaceBeforeCursor: ((Int, String) -> Void)?
    /// 点击输入框开始在键盘中打字（携带当前输入框草稿，键盘上方常驻 AI 输入条随时可见）
    var onBeginTypingPrompt: ((String) -> Void)?
    /// 翻看回答 / 打开历史记录 / 点击拉高按钮时通知宿主控制器平滑拉高或还原键盘高度
    var onReadingHeightChanged: ((Bool) -> Void)?
    var onOpenFullAccessSettings: ((@escaping (Bool) -> Void) -> Void)?
    var onOpenHostAppAI: ((@escaping (Bool) -> Void) -> Void)?
    var onImportBridgeToken: (() -> Bool)?
    /// 键盘内触发一键截屏识图
    var onTriggerScreenshotVision: (() -> Void)?
    /// 唤起主 App 截屏识图工作台（可携带待删除截屏 assetID 完成系统删除确认）
    var onOpenScreenshotWorkbench: ((String?) -> Void)?
    var onClose: (() -> Void)?

    private static let coreActions: [AIPresetAction] = [
        .polish, .eqReply, .translateEn, .translateZh, .proofread, .summarize
    ]

    private let client = AIClient()
    private var streamTask: Task<Void, Never>?

    private var theme: ResolvedTheme?
    private var hasFullAccess = false
    /// 当前 AI 输入框里的内容（可打字、可粘贴、可自动带入当前输入框文本）
    private(set) var inputDraftText = ""
    /// 用于「替换」宿主输入框光标前文本的字数（仅当输入来源于宿主光标前文本时 > 0）
    private var hostReplaceCount = 0
    private var lastAction: AIPresetAction? = nil
    private var lastCustomTemplateID: String?
    private var lastRunPair: (prompt: String, sys: String, title: String, preferFast: Bool, preferDeep: Bool)?
    private var pinnedCustomPrompts: [CustomAIPromptTemplate] = []
    private var generatedText = ""
    private var thinkingText = ""
    private var isThinkingExpanded = false
    private var showingHistory = false
    private var pendingDeleteScreenshotAssetID: String?
    private var screenshotStatusNotice: String?
    private(set) var isExpandedReadingHeight = false

    // Row 1: 顶部可打字 / 可粘贴输入框
    private let inputBoxButton = ActionClosureButton(type: .custom)
    private let inputTextLabel = UILabel()
    private let pasteButton = ActionClosureButton(type: .system)
    private let clearInputButton = ActionClosureButton(type: .system)
    private let sendButton = ActionClosureButton(type: .system)
    private let closeButton = ActionClosureButton(type: .system)

    // Row 2: 6 大核心精简能力条 + 右侧固定 [🕒历史] [⤢拉高]
    private let actionsScroll = LingxiScrollView()
    private let actionsStack = UIStackView()
    private let historyToggleButton = ActionClosureButton(type: .system)
    private let heightToggleButton = ActionClosureButton(type: .system)

    // 思考过程独立折叠区（仅模型真实输出思考链时出现）
    private let thoughtToggleButton = ActionClosureButton(type: .system)
    private let thoughtTextView = UITextView()

    // 流式正文输出区（支持自由长按选中复制 + 上下滑动翻看自动拉高键盘）
    private let outputTextView = UITextView()

    // 内置 AI 历史记录抽屉列表
    private let historyScroll = LingxiScrollView()
    private let historyStack = UIStackView()

    // 权限 / 配置一键修复条（未开完全访问或未同步 Key 时显式展示）
    private let permissionBar = UIStackView()
    private let permissionPrimaryButton = ActionClosureButton(type: .system)
    private let permissionSecondaryButton = ActionClosureButton(type: .system)

    // 底部清爽 4 键：重试/停止 · 复制 · 替换 · 插入
    private let bottomBar = UIStackView()
    private let stopOrRetryButton = ActionClosureButton(type: .system)
    private let copyButton = ActionClosureButton(type: .system)
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
        // 1. 可点击打字的 AI 输入框
        inputBoxButton.layer.cornerRadius = 11
        inputBoxButton.layer.cornerCurve = .continuous
        inputBoxButton.layer.borderWidth = 0.8
        inputBoxButton.accessibilityLabel = "AI 输入框，点按开始打字"
        inputBoxButton.actionHandler = { [weak self] in
            guard let self else { return }
            self.streamTask?.cancel()
            self.onBeginTypingPrompt?(self.inputDraftText)
        }
        addSubview(inputBoxButton)

        inputTextLabel.font = .systemFont(ofSize: 13, weight: .medium)
        inputTextLabel.numberOfLines = 1
        inputTextLabel.lineBreakMode = .byTruncatingHead
        inputTextLabel.isUserInteractionEnabled = false
        inputBoxButton.addSubview(inputTextLabel)

        pasteButton.setTitle("粘贴", for: .normal)
        pasteButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        pasteButton.layer.cornerRadius = 10
        pasteButton.layer.cornerCurve = .continuous
        pasteButton.actionHandler = { [weak self] in self?.handlePasteIntoInputBox() }
        addSubview(pasteButton)

        let clrImg = UIImage(
            systemName: "xmark.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
        clearInputButton.setImage(clrImg, for: .normal)
        clearInputButton.accessibilityLabel = "清空输入框"
        clearInputButton.isHidden = true
        clearInputButton.actionHandler = { [weak self] in self?.handleClearInputBox() }
        addSubview(clearInputButton)

        sendButton.setTitle("发送", for: .normal)
        sendButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .bold)
        sendButton.layer.cornerRadius = 10
        sendButton.layer.cornerCurve = .continuous
        sendButton.actionHandler = { [weak self] in self?.handleSendFreeQuestion() }
        addSubview(sendButton)

        closeButton.setTitle("返回", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        closeButton.layer.cornerRadius = 10
        closeButton.layer.cornerCurve = .continuous
        closeButton.actionHandler = { [weak self] in
            self?.streamTask?.cancel()
            self?.setExpandedReadingHeight(false)
            self?.onClose?()
        }
        addSubview(closeButton)

        // 2. 6 大核心精简能力条 + 右侧固定 [历史] [拉高]
        actionsScroll.showsHorizontalScrollIndicator = false
        addSubview(actionsScroll)
        actionsStack.axis = .horizontal
        actionsStack.spacing = 6
        actionsStack.alignment = .center
        actionsScroll.addSubview(actionsStack)

        historyToggleButton.setTitle("历史", for: .normal)
        let histImg = UIImage(systemName: "clock.arrow.circlepath", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        historyToggleButton.setImage(histImg, for: .normal)
        historyToggleButton.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        historyToggleButton.layer.cornerRadius = 14
        historyToggleButton.layer.cornerCurve = .continuous
        historyToggleButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        historyToggleButton.actionHandler = { [weak self] in self?.toggleHistoryDrawer() }
        addSubview(historyToggleButton)

        let expandImg = UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        heightToggleButton.setImage(expandImg, for: .normal)
        heightToggleButton.accessibilityLabel = "拉高阅读高度"
        heightToggleButton.layer.cornerRadius = 14
        heightToggleButton.layer.cornerCurve = .continuous
        heightToggleButton.actionHandler = { [weak self] in
            guard let self else { return }
            self.setExpandedReadingHeight(!self.isExpandedReadingHeight)
        }
        addSubview(heightToggleButton)

        // 3. 可折叠思考过程
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
        thoughtTextView.isSelectable = true
        thoughtTextView.font = .systemFont(ofSize: 11.5, weight: .regular)
        thoughtTextView.layer.cornerRadius = 8
        thoughtTextView.layer.cornerCurve = .continuous
        thoughtTextView.textContainerInset = UIEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        thoughtTextView.isHidden = true
        addSubview(thoughtTextView)

        // 4. 正文输出区（显式开启自由选中复制 + 翻看滑动自动拉高键盘）
        outputTextView.isEditable = false
        outputTextView.isSelectable = true
        outputTextView.delegate = self
        outputTextView.font = .systemFont(ofSize: 14.5, weight: .regular)
        outputTextView.layer.cornerRadius = 11
        outputTextView.layer.cornerCurve = .continuous
        outputTextView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        addSubview(outputTextView)

        // 5. 历史记录抽屉
        historyScroll.showsVerticalScrollIndicator = true
        historyScroll.isHidden = true
        addSubview(historyScroll)
        historyStack.axis = .vertical
        historyStack.spacing = 8
        historyStack.alignment = .fill
        historyScroll.addSubview(historyStack)

        // 6. 一键权限 / 配置修复条
        permissionBar.axis = .horizontal
        permissionBar.spacing = 6
        permissionBar.distribution = .fill
        permissionBar.isHidden = true
        addSubview(permissionBar)

        permissionPrimaryButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .bold)
        permissionPrimaryButton.layer.cornerRadius = 9
        permissionPrimaryButton.layer.cornerCurve = .continuous
        permissionPrimaryButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        permissionPrimaryButton.actionHandler = { [weak self] in
            self?.handlePermissionPrimaryTap()
        }
        permissionBar.addArrangedSubview(permissionPrimaryButton)

        permissionSecondaryButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        permissionSecondaryButton.layer.cornerRadius = 9
        permissionSecondaryButton.layer.cornerCurve = .continuous
        permissionSecondaryButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        permissionSecondaryButton.setContentHuggingPriority(.required, for: .horizontal)
        permissionSecondaryButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        permissionSecondaryButton.isHidden = true
        permissionSecondaryButton.actionHandler = { [weak self] in
            self?.handlePermissionSecondaryTap()
        }
        permissionBar.addArrangedSubview(permissionSecondaryButton)

        // 7. 底部 4 键：重试 · 复制 · 替换 · 插入
        bottomBar.axis = .horizontal
        bottomBar.distribution = .fillEqually
        bottomBar.spacing = 6
        addSubview(bottomBar)

        stopOrRetryButton.setTitle("重试", for: .normal)
        stopOrRetryButton.actionHandler = { [weak self] in self?.handleStopOrRetry() }

        copyButton.setTitle("复制", for: .normal)
        copyButton.actionHandler = { [weak self] in self?.handleCopyGeneratedText() }

        replaceButton.setTitle("替换", for: .normal)
        replaceButton.actionHandler = { [weak self] in self?.handleReplace() }

        insertButton.setTitle("插入", for: .normal)
        insertButton.actionHandler = { [weak self] in self?.handleInsert() }

        for btn in [stopOrRetryButton, copyButton, replaceButton, insertButton] {
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            btn.layer.cornerRadius = 9
            btn.layer.cornerCurve = .continuous
            bottomBar.addArrangedSubview(btn)
        }
    }

    // 翻看长回答时自动拉高键盘高度，阅读更顺手
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === outputTextView,
              !isExpandedReadingHeight,
              scrollView.contentSize.height > scrollView.bounds.height + 10 else {
            return
        }
        setExpandedReadingHeight(true)
    }

    private func setExpandedReadingHeight(_ expanded: Bool) {
        guard isExpandedReadingHeight != expanded else { return }
        isExpandedReadingHeight = expanded
        updateHeightToggleIcon()
        onReadingHeightChanged?(expanded)
    }

    private func updateHeightToggleIcon() {
        let symbol = isExpandedReadingHeight
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right"
        let img = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        heightToggleButton.setImage(img, for: .normal)
        heightToggleButton.accessibilityLabel = isExpandedReadingHeight ? "还原键盘高度" : "拉高阅读高度"
        if let theme {
            heightToggleButton.backgroundColor = isExpandedReadingHeight ? theme.accentFill.withAlphaComponent(0.20) : theme.specialKeyFill
            heightToggleButton.tintColor = isExpandedReadingHeight ? theme.candidateHighlight : theme.keyText
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 8

        // Row 1: 顶部输入框 + 粘贴 + 发送 + 返回
        let topY: CGFloat = 7
        let topH: CGFloat = 34
        let closeW: CGFloat = 44
        let sendW: CGFloat = 46
        let pasteW: CGFloat = 42

        closeButton.frame = CGRect(x: bounds.width - pad - closeW, y: topY, width: closeW, height: topH)
        sendButton.frame = CGRect(x: closeButton.frame.minX - 5 - sendW, y: topY, width: sendW, height: topH)
        pasteButton.frame = CGRect(x: sendButton.frame.minX - 5 - pasteW, y: topY, width: pasteW, height: topH)

        let boxW = max(90, pasteButton.frame.minX - 6 - pad)
        inputBoxButton.frame = CGRect(x: pad, y: topY, width: boxW, height: topH)

        let clearW: CGFloat = clearInputButton.isHidden ? 0 : 24
        if !clearInputButton.isHidden {
            clearInputButton.frame = CGRect(x: inputBoxButton.frame.maxX - clearW - 4, y: topY + (topH - 24) / 2, width: 24, height: 24)
        }
        inputTextLabel.frame = CGRect(x: 10, y: 0, width: max(30, boxW - 16 - clearW), height: topH)

        // Row 2: 精简 6 项核心快捷动作 + 右侧固定 [历史] [拉高]
        let actY = inputBoxButton.frame.maxY + 6
        let actH: CGFloat = 30
        let heightBtnW: CGFloat = 30
        let histBtnW: CGFloat = 56
        heightToggleButton.frame = CGRect(x: bounds.width - pad - heightBtnW, y: actY, width: heightBtnW, height: actH)
        historyToggleButton.frame = CGRect(x: heightToggleButton.frame.minX - 5 - histBtnW, y: actY, width: histBtnW, height: actH)

        let actionsW = max(80, historyToggleButton.frame.minX - 6)
        actionsScroll.frame = CGRect(x: 0, y: actY, width: actionsW, height: actH)
        let actionsNaturalW = ceil(actionsStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
        actionsStack.frame = CGRect(x: pad, y: 0, width: actionsNaturalW, height: actH)
        actionsScroll.contentSize = CGSize(width: max(actionsW, actionsNaturalW + pad * 2), height: actH)

        // Bottom bar
        let bottomH: CGFloat = 36
        bottomBar.frame = CGRect(x: pad, y: bounds.height - bottomH - 7, width: bounds.width - pad * 2, height: bottomH)

        var contentBottom = bottomBar.frame.minY
        if !permissionBar.isHidden {
            let permH: CGFloat = 34
            permissionBar.frame = CGRect(x: pad, y: contentBottom - permH - 6, width: bounds.width - pad * 2, height: permH)
            contentBottom = permissionBar.frame.minY
        }

        var contentY = actionsScroll.frame.maxY + 6
        if !showingHistory && !thoughtToggleButton.isHidden {
            thoughtToggleButton.frame = CGRect(x: pad, y: contentY, width: bounds.width - pad * 2, height: 22)
            contentY = thoughtToggleButton.frame.maxY + 3
            if isThinkingExpanded {
                thoughtTextView.isHidden = false
                let thH = min(64, max(36, (contentBottom - contentY) * 0.32))
                thoughtTextView.frame = CGRect(x: pad, y: contentY, width: bounds.width - pad * 2, height: thH)
                contentY = thoughtTextView.frame.maxY + 4
            } else {
                thoughtTextView.isHidden = true
            }
        } else {
            thoughtTextView.isHidden = true
        }

        let contentRect = CGRect(
            x: pad,
            y: contentY,
            width: bounds.width - pad * 2,
            height: max(48, contentBottom - contentY - 6)
        )
        outputTextView.frame = contentRect

        if !historyScroll.isHidden {
            historyScroll.frame = contentRect
            let hw = max(80, contentRect.width)
            let fit = historyStack.systemLayoutSizeFitting(
                CGSize(width: hw, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            historyStack.frame = CGRect(x: 0, y: 0, width: hw, height: fit.height)
            historyScroll.contentSize = CGSize(width: hw, height: fit.height + 10)
        }
    }

    // MARK: - 外部入口

    func prepare(
        theme: ResolvedTheme,
        hasFullAccess: Bool,
        beforeCursor: String,
        clipboardText: String?,
        preferredAction: AIPresetAction? = nil,
        preservedDraft: String? = nil
    ) {
        self.theme = theme
        self.hasFullAccess = hasFullAccess
        self.showingHistory = false
        historyScroll.isHidden = true
        outputTextView.isHidden = false

        let cleanBefore = beforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanClip = (clipboardText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if let draft = preservedDraft {
            self.inputDraftText = draft
            self.hostReplaceCount = 0
        } else if !cleanClip.isEmpty {
            self.inputDraftText = cleanClip
            self.hostReplaceCount = 0
        } else if !cleanBefore.isEmpty {
            self.inputDraftText = cleanBefore
            self.hostReplaceCount = cleanBefore.count
        } else if inputDraftText.isEmpty {
            self.hostReplaceCount = 0
        }

        reloadPinnedPrompts()
        applyTheme(theme)
        rebuildActionButtons(theme: theme)
        refreshInputBoxDisplay()

        if let preferredAction {
            runAction(preferredAction)
        } else if generatedText.isEmpty {
            showIdleGuidance()
        } else {
            refreshPermissionBarVisibility()
        }
    }

    func runCustomQuestion(
        _ question: String,
        theme: ResolvedTheme,
        hasFullAccess: Bool,
        beforeCursor: String
    ) {
        self.theme = theme
        self.hasFullAccess = hasFullAccess
        self.showingHistory = false
        historyScroll.isHidden = true
        outputTextView.isHidden = false

        let cleanQ = question.trimmingCharacters(in: .whitespacesAndNewlines)
        self.inputDraftText = cleanQ
        let cleanBefore = beforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hostReplaceCount = cleanBefore.isEmpty ? 0 : cleanBefore.count

        reloadPinnedPrompts()
        applyTheme(theme)
        rebuildActionButtons(theme: theme)
        refreshInputBoxDisplay()

        let contextNote = (cleanBefore.isEmpty || cleanBefore == cleanQ) ? "" : "\n\n【当前输入上下文参考】\n\(cleanBefore)"
        let fullPrompt = cleanQ + contextNote
        let sysPrompt = "你是内嵌在 iOS 输入法中的灵犀 AI 助手。请直接给出高质量、简洁、可直接发送的结果，不要多余客套。"

        lastAction = nil
        lastCustomTemplateID = nil
        lastRunPair = (fullPrompt, sysPrompt, "自由提问", false, false)
        streamPrompt(prompt: fullPrompt, systemInstruction: sysPrompt, featureTag: "ai_ask", displayPrompt: cleanQ)
    }

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
        self.showingHistory = false
        historyScroll.isHidden = true
        outputTextView.isHidden = false
        self.inputDraftText = sourceText
        self.hostReplaceCount = replaceCount

        reloadPinnedPrompts()
        applyTheme(theme)
        rebuildActionButtons(theme: theme)
        refreshInputBoxDisplay()

        lastAction = nil
        lastCustomTemplateID = nil
        lastRunPair = (sourceText, instruction, title, true, false)
        streamPrompt(prompt: sourceText, systemInstruction: instruction, featureTag: "ai_direct", displayPrompt: sourceText, preferFast: true)
    }

    func refreshAfterConfigChange(hasFullAccess: Bool) {
        self.hasFullAccess = hasFullAccess
        reloadPinnedPrompts()
        if let theme {
            applyTheme(theme)
            rebuildActionButtons(theme: theme)
        }
        if generatedText.isEmpty && !showingHistory {
            showIdleGuidance()
        } else {
            refreshPermissionBarVisibility()
        }
    }

    func applyTheme(_ theme: ResolvedTheme) {
        backgroundColor = theme.canvasTop.withAlphaComponent(0.98)

        inputBoxButton.backgroundColor = theme.keyFill
        inputBoxButton.layer.borderColor = theme.accentFill.withAlphaComponent(0.45).cgColor
        refreshInputBoxDisplay()

        pasteButton.backgroundColor = theme.specialKeyFill
        pasteButton.setTitleColor(theme.keyText, for: .normal)
        clearInputButton.tintColor = theme.keyHintText

        sendButton.backgroundColor = theme.accentFill
        sendButton.setTitleColor(theme.accentText, for: .normal)

        closeButton.backgroundColor = theme.specialKeyFill
        closeButton.setTitleColor(theme.keyText, for: .normal)

        historyToggleButton.backgroundColor = showingHistory ? theme.accentFill : theme.specialKeyFill
        historyToggleButton.setTitleColor(showingHistory ? theme.accentText : theme.keyText, for: .normal)
        historyToggleButton.tintColor = showingHistory ? theme.accentText : theme.keyText

        updateHeightToggleIcon()

        thoughtToggleButton.backgroundColor = theme.specialKeyFill.withAlphaComponent(0.85)
        thoughtToggleButton.setTitleColor(theme.keyHintText, for: .normal)
        thoughtTextView.backgroundColor = theme.specialKeyFill.withAlphaComponent(0.55)
        thoughtTextView.textColor = theme.keyHintText

        outputTextView.backgroundColor = theme.keyFill.withAlphaComponent(0.96)
        outputTextView.textColor = theme.keyText
        outputTextView.tintColor = theme.accentFill

        permissionPrimaryButton.backgroundColor = theme.accentFill
        permissionPrimaryButton.setTitleColor(theme.accentText, for: .normal)
        permissionSecondaryButton.backgroundColor = theme.specialKeyFill
        permissionSecondaryButton.setTitleColor(theme.keyText, for: .normal)

        stopOrRetryButton.backgroundColor = theme.specialKeyFill
        stopOrRetryButton.setTitleColor(theme.keyText, for: .normal)

        copyButton.backgroundColor = theme.specialKeyFill
        copyButton.setTitleColor(theme.keyText, for: .normal)

        replaceButton.backgroundColor = theme.specialKeyFill
        replaceButton.setTitleColor(theme.keyText, for: .normal)

        insertButton.backgroundColor = theme.accentFill
        insertButton.setTitleColor(theme.accentText, for: .normal)
    }

    // MARK: - 历史记录抽屉

    private func toggleHistoryDrawer() {
        showingHistory.toggle()
        if showingHistory {
            setExpandedReadingHeight(true)
            rebuildHistoryList()
            outputTextView.isHidden = true
            thoughtToggleButton.isHidden = true
            thoughtTextView.isHidden = true
            historyScroll.isHidden = false
        } else {
            historyScroll.isHidden = true
            outputTextView.isHidden = false
            thoughtToggleButton.isHidden = thinkingText.isEmpty
        }
        if let theme { applyTheme(theme) }
        setNeedsLayout()
    }

    private func rebuildHistoryList() {
        historyStack.arrangedSubviews.forEach {
            historyStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }
        let items = AIRecentHistoryStore.load()

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center

        let titleLbl = UILabel()
        titleLbl.text = items.isEmpty ? "🕒 暂无 AI 回答历史" : "🕒 最近 AI 回答（共 \(items.count) 条 · 点卡片看全文）"
        titleLbl.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLbl.textColor = theme.keyHintText
        header.addArrangedSubview(titleLbl)

        if !items.isEmpty {
            let clearBtn = ActionClosureButton(type: .system)
            clearBtn.setTitle("清空", for: .normal)
            clearBtn.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
            clearBtn.setTitleColor(.systemRed, for: .normal)
            clearBtn.actionHandler = { [weak self] in
                AIRecentHistoryStore.clear()
                self?.rebuildHistoryList()
            }
            header.addArrangedSubview(clearBtn)
        }
        historyStack.addArrangedSubview(header)

        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"

        for item in items {
            let card = UIView()
            card.backgroundColor = theme.keyFill.withAlphaComponent(0.96)
            card.layer.cornerRadius = 11
            card.layer.cornerCurve = .continuous
            card.layer.borderWidth = 0.6
            card.layer.borderColor = theme.keyBorder.cgColor

            let inner = UIStackView()
            inner.axis = .vertical
            inner.spacing = 6
            inner.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(inner)
            NSLayoutConstraint.activate([
                inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
                inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
                inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            ])

            let topMeta = UIStackView()
            topMeta.axis = .horizontal
            topMeta.alignment = .center
            topMeta.spacing = 6

            let tagLbl = UILabel()
            tagLbl.text = "\(item.title) · \(fmt.string(from: item.createdAt))"
            tagLbl.font = .systemFont(ofSize: 11, weight: .bold)
            tagLbl.textColor = theme.candidateHighlight
            tagLbl.setContentHuggingPriority(.defaultLow, for: .horizontal)
            topMeta.addArrangedSubview(tagLbl)

            let copyCardBtn = ActionClosureButton(type: .system)
            copyCardBtn.setTitle("复制", for: .normal)
            copyCardBtn.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
            copyCardBtn.backgroundColor = theme.specialKeyFill
            copyCardBtn.setTitleColor(theme.keyText, for: .normal)
            copyCardBtn.layer.cornerRadius = 7
            copyCardBtn.contentEdgeInsets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
            copyCardBtn.actionHandler = { [weak copyCardBtn] in
                UIPasteboard.general.string = item.output
                _ = ClipboardStore.record(item.output)
                copyCardBtn?.setTitle("✓已复制", for: .normal)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    copyCardBtn?.setTitle("复制", for: .normal)
                }
            }
            topMeta.addArrangedSubview(copyCardBtn)

            let insertCardBtn = ActionClosureButton(type: .system)
            insertCardBtn.setTitle("插入", for: .normal)
            insertCardBtn.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .bold)
            insertCardBtn.backgroundColor = theme.accentFill
            insertCardBtn.setTitleColor(theme.accentText, for: .normal)
            insertCardBtn.layer.cornerRadius = 7
            insertCardBtn.contentEdgeInsets = UIEdgeInsets(top: 3, left: 9, bottom: 3, right: 9)
            insertCardBtn.actionHandler = { [weak self] in
                self?.onInsertText?(item.output)
            }
            topMeta.addArrangedSubview(insertCardBtn)
            inner.addArrangedSubview(topMeta)

            let previewBtn = ActionClosureButton(type: .custom)
            previewBtn.contentHorizontalAlignment = .leading
            previewBtn.titleLabel?.numberOfLines = 4
            previewBtn.titleLabel?.lineBreakMode = .byTruncatingTail
            let attr = NSMutableAttributedString()
            if !item.prompt.isEmpty {
                attr.append(NSAttributedString(
                    string: "问：\(item.prompt.prefix(36))\n",
                    attributes: [.font: UIFont.systemFont(ofSize: 11.5, weight: .medium), .foregroundColor: theme.keyHintText]
                ))
            }
            attr.append(NSAttributedString(
                string: item.output,
                attributes: [.font: UIFont.systemFont(ofSize: 13.5, weight: .regular), .foregroundColor: theme.keyText]
            ))
            previewBtn.setAttributedTitle(attr, for: .normal)
            previewBtn.actionHandler = { [weak self] in
                guard let self else { return }
                self.showingHistory = false
                self.historyScroll.isHidden = true
                self.outputTextView.isHidden = false
                if !item.prompt.isEmpty {
                    self.inputDraftText = item.prompt
                    self.refreshInputBoxDisplay()
                }
                self.generatedText = item.output
                self.outputTextView.text = item.output
                self.outputTextView.contentOffset = .zero
                self.setExpandedReadingHeight(true)
                if let t = self.theme { self.applyTheme(t) }
                self.updateActionButtonsEnabled()
            }
            inner.addArrangedSubview(previewBtn)

            historyStack.addArrangedSubview(card)
        }
        setNeedsLayout()
    }

    // MARK: - 内部 UI 刷新与输入交互

    private func reloadPinnedPrompts() {
        let cfg = AIConfig.load()
        pinnedCustomPrompts = cfg.customPrompts.filter(\.isPinned)
    }

    private func refreshInputBoxDisplay() {
        let trimmed = inputDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            inputTextLabel.text = "✎ 点此打字问 AI，或点右侧「粘贴」…"
            inputTextLabel.textColor = theme?.keyHintText ?? .secondaryLabel
            clearInputButton.isHidden = true
            sendButton.alpha = 0.50
        } else {
            inputTextLabel.text = trimmed.replacingOccurrences(of: "\n", with: " ")
            inputTextLabel.textColor = theme?.keyText ?? .label
            clearInputButton.isHidden = false
            sendButton.alpha = 1.0
        }
        setNeedsLayout()
    }

    private func handlePasteIntoInputBox() {
        let clipText: String? = {
            if hasFullAccess, let sys = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !sys.isEmpty {
                if !ClipboardClassifier.isSensitiveContent(sys) {
                    return sys
                }
            }
            return ClipboardStore.items().first?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        guard let pasted = clipText, !pasted.isEmpty else {
            showingHistory = false
            historyScroll.isHidden = true
            outputTextView.isHidden = false
            outputTextView.text = hasFullAccess
                ? "📋 剪贴板为空：先复制一段聊天消息或文章，再点「粘贴」即可直接让 AI 处理。"
                : "⚠️ 开启「允许完全访问」后即可一键读取系统剪贴板；也可以直接点上方输入框打字。"
            refreshPermissionBarVisibility()
            return
        }

        showingHistory = false
        historyScroll.isHidden = true
        outputTextView.isHidden = false
        inputDraftText = pasted
        hostReplaceCount = 0
        refreshInputBoxDisplay()
        outputTextView.text = "✓ 已粘贴（\(pasted.count) 字）。点「发送」直接问 AI，或点下方「润色 / 回复 / 译英 / 译中」一键处理。"
    }

    private func handleClearInputBox() {
        inputDraftText = ""
        hostReplaceCount = 0
        generatedText = ""
        thinkingText = ""
        thoughtToggleButton.isHidden = true
        thoughtTextView.isHidden = true
        showingHistory = false
        historyScroll.isHidden = true
        outputTextView.isHidden = false
        refreshInputBoxDisplay()
        showIdleGuidance()
    }

    private func handleSendFreeQuestion() {
        let q = inputDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            onBeginTypingPrompt?("")
            return
        }
        let sys = "你是内嵌在 iOS 输入法中的灵犀 AI 助手。请直接给出高质量、简洁、可直接发送的结果，不要多余客套。"
        lastAction = nil
        lastCustomTemplateID = nil
        lastRunPair = (q, sys, "自由提问", false, false)
        if let theme { rebuildActionButtons(theme: theme) }
        streamPrompt(prompt: q, systemInstruction: sys, featureTag: "ai_ask", displayPrompt: q)
    }

    private func rebuildActionButtons(theme: ResolvedTheme) {
        actionsStack.arrangedSubviews.forEach {
            actionsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        func addPill(title: String, selected: Bool, handler: @escaping () -> Void) {
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            btn.backgroundColor = selected ? theme.accentFill : theme.keyFill
            btn.setTitleColor(selected ? theme.accentText : theme.keyText, for: .normal)
            btn.layer.cornerRadius = 14
            btn.layer.cornerCurve = .continuous
            btn.layer.borderWidth = selected ? 0 : 0.5
            btn.layer.borderColor = theme.keyBorder.cgColor
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
            btn.actionHandler = handler
            actionsStack.addArrangedSubview(btn)
        }

        addPill(title: "📷 截屏识图", selected: false) { [weak self] in
            self?.onTriggerScreenshotVision?()
        }

        for action in Self.coreActions {
            let shortTitle: String
            switch action {
            case .polish: shortTitle = "✨ 润色"
            case .eqReply: shortTitle = "💬 回复"
            case .translateEn: shortTitle = "🌐 译英"
            case .translateZh: shortTitle = "🇨🇳 译中"
            case .proofread: shortTitle = "✓ 纠错"
            case .summarize: shortTitle = "✂️ 精简"
            default: shortTitle = action.title
            }
            addPill(title: shortTitle, selected: lastAction == action && lastCustomTemplateID == nil) { [weak self] in
                self?.runAction(action)
            }
        }

        for tpl in pinnedCustomPrompts {
            addPill(title: "★ \(tpl.title)", selected: lastCustomTemplateID == tpl.id) { [weak self] in
                self?.runCustomTemplate(tpl)
            }
        }
        setNeedsLayout()
    }

    private func resolveWorkingTextOrFallback() -> String {
        let draft = inputDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty { return draft }
        if hasFullAccess,
           let sys = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sys.isEmpty,
           !ClipboardClassifier.isSensitiveContent(sys) {
            inputDraftText = sys
            hostReplaceCount = 0
            refreshInputBoxDisplay()
            return sys
        }
        if let clip = ClipboardStore.items().first?.text.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
            inputDraftText = clip
            hostReplaceCount = 0
            refreshInputBoxDisplay()
            return clip
        }
        return ""
    }

    private func runAction(_ action: AIPresetAction) {
        lastAction = action
        lastCustomTemplateID = nil
        if let theme { rebuildActionButtons(theme: theme) }
        let source = resolveWorkingTextOrFallback()
        guard !source.isEmpty else {
            showingHistory = false
            historyScroll.isHidden = true
            outputTextView.isHidden = false
            outputTextView.text = "请先点上方输入框打字，或点「粘贴」放入内容，再点「\(action.title)」。"
            refreshPermissionBarVisibility()
            return
        }
        lastRunPair = (source, action.systemPrompt, action.title, !action.prefersDeepModel, action.prefersDeepModel)
        streamPrompt(
            prompt: source,
            systemInstruction: action.systemPrompt,
            featureTag: action.rawValue,
            displayPrompt: source,
            preferFast: !action.prefersDeepModel,
            preferDeep: action.prefersDeepModel
        )
    }

    private func runCustomTemplate(_ template: CustomAIPromptTemplate) {
        lastAction = nil
        lastCustomTemplateID = template.id
        if let theme { rebuildActionButtons(theme: theme) }
        let source = resolveWorkingTextOrFallback()
        guard !source.isEmpty else {
            showingHistory = false
            historyScroll.isHidden = true
            outputTextView.isHidden = false
            outputTextView.text = "请先点上方输入框打字，或点「粘贴」放入内容，再点「\(template.title)」。"
            refreshPermissionBarVisibility()
            return
        }
        let sys = template.effectiveSystemPrompt
        lastRunPair = (source, sys, template.title, false, template.useDeepModel)
        streamPrompt(prompt: source, systemInstruction: sys, featureTag: "custom_prompt", displayPrompt: source, preferDeep: template.useDeepModel)
    }

    // MARK: - 权限与引导

    private func refreshPermissionBarVisibility() {
        let config = AIConfig.load()
        if !hasFullAccess {
            permissionBar.isHidden = false
            permissionPrimaryButton.setTitle("🔓 一键前往开启完全访问权限", for: .normal)
            permissionSecondaryButton.isHidden = true
        } else if !config.isConfigured {
            permissionBar.isHidden = false
            permissionPrimaryButton.setTitle("⚡ 前往灵犀 App 配置 AI", for: .normal)
            permissionSecondaryButton.isHidden = AppGroup.isAvailable
            if !AppGroup.isAvailable {
                permissionSecondaryButton.setTitle("📋 导入同步口令", for: .normal)
            }
        } else if pendingDeleteScreenshotAssetID != nil {
            permissionBar.isHidden = false
            permissionPrimaryButton.setTitle("🗑️ 一键彻底删除已上传的原截屏", for: .normal)
            permissionSecondaryButton.isHidden = false
            permissionSecondaryButton.setTitle("暂不删", for: .normal)
        } else {
            permissionBar.isHidden = true
            permissionSecondaryButton.isHidden = true
        }
        setNeedsLayout()
    }

    private func handlePermissionPrimaryTap() {
        if !hasFullAccess {
            onOpenFullAccessSettings? { [weak self] opened in
                guard let self else { return }
                if !opened {
                    self.outputTextView.text = "📱 iOS 限制无完全访问时自动跳转。\n请到桌面打开「设置」→「灵犀输入法」→「键盘」→ 打开「允许完全访问」，开启后切回即可正常使用 AI。"
                }
            }
        } else if !AIConfig.load().isConfigured {
            onOpenHostAppAI? { [weak self] opened in
                guard let self else { return }
                if !opened {
                    self.outputTextView.text = "✨ 请切到主屏幕打开「灵犀输入法 App → AI 智脑」填写 API Key；免费侧载填完后点「同步给键盘」再切回即可。"
                }
            }
        } else if let assetID = pendingDeleteScreenshotAssetID {
            pendingDeleteScreenshotAssetID = nil
            refreshPermissionBarVisibility()
            onOpenScreenshotWorkbench?(assetID)
        }
    }

    private func handlePermissionSecondaryTap() {
        if pendingDeleteScreenshotAssetID != nil {
            pendingDeleteScreenshotAssetID = nil
            refreshPermissionBarVisibility()
            return
        }
        let ok = onImportBridgeToken?() ?? false
        if ok {
            let cfg = AIConfig.load()
            refreshAfterConfigChange(hasFullAccess: hasFullAccess)
            outputTextView.text = cfg.isConfigured
                ? "✓ 已导入 AI 配置（\(cfg.activeModelName)）！现在可直接在上方打字或粘贴提问。"
                : "✓ 已导入配置，请确认已在主 App「AI 智脑」填好 API Key 后再同步。"
        } else {
            outputTextView.text = "⚠️ 剪贴板中未检测到同步口令。请先在「灵犀 App → AI 智脑」点「同步给键盘」再回来点此按钮。"
        }
    }

    private func showIdleGuidance() {
        let config = AIConfig.load()
        thoughtToggleButton.isHidden = true
        thoughtTextView.isHidden = true
        if !hasFullAccess {
            outputTextView.text = "⚠️ 未开启键盘「允许完全访问」权限，无法联网调用 AI。\n点下方按钮前往「设置 → 灵犀输入法 → 键盘」打开「允许完全访问」即可。"
        } else if !config.isConfigured {
            outputTextView.text = AppGroup.isAvailable
                ? "✨ 尚未填写 AI API Key。点下方按钮直达「灵犀 App → AI 智脑」填好即可使用。"
                : "✨ 免费侧载沙盒隔离：点下方打开「灵犀 App → AI 智脑」点击「同步给键盘」再切回即可。"
        } else if !inputDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outputTextView.text = "✓ 已就绪（\(config.activeModelName)）\n点「发送」直接问 AI，或点上方「润色 / 回复 / 译英 / 译中」一键生成。"
        } else {
            outputTextView.text = "✓ 已就绪（\(config.activeModelName)）\n• 点上方输入框可直接打字问 AI，或点「粘贴」放入内容\n• 回答正文支持长按自由选词复制，也支持一键「复制 / 插入」\n• 点右侧「历史」可随时翻阅历史回答并自动拉高阅读空间"
        }
        refreshPermissionBarVisibility()
        updateActionButtonsEnabled()
    }

    // MARK: - 流式推理

    private func updateThoughtHeader() {
        let arrow = isThinkingExpanded ? "▾" : "▸"
        thoughtToggleButton.setTitle("💭 思考过程 (\(thinkingText.count)字) \(arrow)", for: .normal)
    }

    /// 键盘内直接对刚截取/复制的截屏执行多模态 AI 识别，上传后按设置自动删除原截屏。
    func runScreenshotVision(
        imageData: Data,
        sourceLabel: String,
        assetLocalIdentifier: String?,
        clearPasteboardAfterUpload: Bool,
        autoDelete: Bool,
        customPrompt: String? = nil,
        theme: ResolvedTheme,
        hasFullAccess: Bool
    ) {
        self.theme = theme
        self.hasFullAccess = hasFullAccess
        self.showingHistory = false
        self.pendingDeleteScreenshotAssetID = nil
        self.screenshotStatusNotice = nil
        historyScroll.isHidden = true
        outputTextView.isHidden = false

        let cleanCustom = (customPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let preset: ScreenshotVisionPreset = .smartReply
        let effectivePrompt = cleanCustom.isEmpty ? preset.promptText : cleanCustom
        let effectiveSys = cleanCustom.isEmpty
            ? preset.systemInstruction
            : "你是内嵌在 iOS 输入法中的视觉 AI 助手。请结合截图画面精准回答用户问题，只输出干净自然、可直接复制发送的纯文本。"
        self.inputDraftText = cleanCustom.isEmpty ? "📷 截屏识图（\(sourceLabel)）" : cleanCustom
        self.hostReplaceCount = 0

        reloadPinnedPrompts()
        applyTheme(theme)
        rebuildActionButtons(theme: theme)
        refreshInputBoxDisplay()

        guard hasFullAccess else {
            showIdleGuidance()
            return
        }
        let config = AIConfig.load()
        guard config.isConfigured else {
            showIdleGuidance()
            return
        }

        streamTask?.cancel()
        permissionBar.isHidden = true
        generatedText = ""
        thinkingText = ""
        thoughtToggleButton.isHidden = true
        thoughtTextView.isHidden = true
        let kbSize = max(1, imageData.count / 1024)
        outputTextView.text = "📷 正在上传截屏（\(kbSize) KB · \(sourceLabel)）并调用 AI 识别…"
        stopOrRetryButton.setTitle("停止", for: .normal)
        updateActionButtonsEnabled()

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                var accumulatedAnswer = ""
                var lastRenderAt = CACurrentMediaTime()
                var cleanupTriggered = false

                func performPostUploadCleanupIfNeeded() async {
                    guard autoDelete, !cleanupTriggered else { return }
                    cleanupTriggered = true
                    if clearPasteboardAfterUpload {
                        await MainActor.run {
                            UIPasteboard.general.items = []
                            self.screenshotStatusNotice = "✓ 已上传识别并自动清空剪贴板原截屏"
                        }
                    }
                    if let assetID = assetLocalIdentifier, !assetID.isEmpty {
                        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
                        if assets.count > 0 {
                            do {
                                try await PHPhotoLibrary.shared().performChanges {
                                    PHAssetChangeRequest.deleteAssets(assets)
                                }
                                await MainActor.run {
                                    self.pendingDeleteScreenshotAssetID = nil
                                    self.screenshotStatusNotice = "✓ 已上传识别并自动删除相册原截屏"
                                    self.refreshPermissionBarVisibility()
                                }
                            } catch {
                                // iOS 键盘扩展沙盒不允许直接弹出系统删除相册确认框时，一键交由主 App 完成删除
                                await MainActor.run {
                                    self.pendingDeleteScreenshotAssetID = assetID
                                    self.screenshotStatusNotice = "ℹ️ 已上传识别完成，点下方按钮一键彻底删除相册原截屏"
                                    self.refreshPermissionBarVisibility()
                                }
                            }
                        }
                    }
                }

                for try await event in client.streamVisionEvents(
                    imageData: imageData,
                    mimeType: "image/jpeg",
                    prompt: effectivePrompt,
                    systemInstruction: effectiveSys,
                    config: config,
                    featureTag: "screenshot_vision"
                ) {
                    if Task.isCancelled { break }
                    if case .answer(let delta) = event {
                        accumulatedAnswer += delta
                        let now = CACurrentMediaTime()
                        if now - lastRenderAt >= 0.045 {
                            lastRenderAt = now
                            let cleanStream = AITextSanitizer.clean(accumulatedAnswer, streaming: true)
                            await MainActor.run {
                                self.generatedText = cleanStream
                                self.outputTextView.text = cleanStream
                                let end = NSRange(location: max(0, cleanStream.utf16.count - 1), length: 0)
                                self.outputTextView.scrollRangeToVisible(end)
                            }
                        }
                    }
                }
                if !Task.isCancelled {
                    await performPostUploadCleanupIfNeeded()
                }
                let finalClean = AITextSanitizer.clean(accumulatedAnswer, streaming: false)
                await MainActor.run {
                    self.generatedText = finalClean
                    if finalClean.isEmpty {
                        self.outputTextView.text = "⚠️ 当前模型未返回图片识别内容，请确认所选模型支持视觉识图（如 Gemini Flash / GPT-4o / Qwen-VL）。"
                    } else {
                        let suffix = self.screenshotStatusNotice.map { "\n\n\($0)" } ?? ""
                        self.outputTextView.text = finalClean + suffix
                        AIRecentHistoryStore.record(
                            title: "📷 截屏识图",
                            output: finalClean,
                            prompt: self.inputDraftText
                        )
                    }
                    self.stopOrRetryButton.setTitle("重试", for: .normal)
                    self.updateActionButtonsEnabled()
                }
            } catch {
                await MainActor.run {
                    self.outputTextView.text = "⚠️ 截屏识图失败：\(error.localizedDescription)\n提示：请确保当前 AI 模型支持图片识别。"
                    self.stopOrRetryButton.setTitle("重试", for: .normal)
                    self.updateActionButtonsEnabled()
                }
            }
        }
    }

    private func streamPrompt(
        prompt: String,
        systemInstruction: String,
        featureTag: String,
        displayPrompt: String = "",
        preferFast: Bool = false,
        preferDeep: Bool = false
    ) {
        streamTask?.cancel()

        guard hasFullAccess else {
            showIdleGuidance()
            return
        }
        let config = AIConfig.load()
        guard config.isConfigured else {
            showIdleGuidance()
            return
        }

        showingHistory = false
        pendingDeleteScreenshotAssetID = nil
        screenshotStatusNotice = nil
        historyScroll.isHidden = true
        outputTextView.isHidden = false
        if let theme { applyTheme(theme) }

        permissionBar.isHidden = true
        generatedText = ""
        thinkingText = ""
        isThinkingExpanded = false
        thoughtToggleButton.isHidden = true
        thoughtTextView.isHidden = true
        thoughtTextView.text = ""
        outputTextView.text = config.thinkingMode.isEnabled ? "🧠 正在思考生成中…" : "✨ 正在生成中…"
        stopOrRetryButton.setTitle("停止", for: .normal)
        updateActionButtonsEnabled()

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                var accumulatedAnswer = ""
                var accumulatedThought = ""
                var lastAnswerFlush = CACurrentMediaTime()
                var lastThoughtFlush = CACurrentMediaTime()
                for try await event in client.streamEvents(
                    prompt: prompt,
                    systemInstruction: systemInstruction,
                    config: config,
                    featureTag: featureTag,
                    preferFast: preferFast,
                    preferDeep: preferDeep
                ) {
                    if Task.isCancelled { break }
                    let now = CACurrentMediaTime()
                    switch event {
                    case .thought(let delta):
                        accumulatedThought += delta
                        if config.showThinkingProcess && (now - lastThoughtFlush >= 0.08) {
                            lastThoughtFlush = now
                            let snapThought = AITextSanitizer.clean(accumulatedThought, streaming: true)
                            await MainActor.run {
                                self.thinkingText = snapThought
                                self.thoughtToggleButton.isHidden = false
                                self.updateThoughtHeader()
                                self.thoughtTextView.text = snapThought
                                if self.generatedText.isEmpty {
                                    self.outputTextView.text = "🧠 思考中（已推演 \(snapThought.count) 字）…"
                                }
                                self.setNeedsLayout()
                            }
                        }
                    case .answer(let delta):
                        accumulatedAnswer += delta
                        if now - lastAnswerFlush >= 0.045 {
                            lastAnswerFlush = now
                            let cleanStream = AITextSanitizer.clean(accumulatedAnswer, streaming: true)
                            await MainActor.run {
                                self.generatedText = cleanStream
                                self.outputTextView.text = cleanStream
                                let end = NSRange(location: max(0, cleanStream.utf16.count - 1), length: 0)
                                self.outputTextView.scrollRangeToVisible(end)
                            }
                        }
                    }
                }
                let finalClean = AITextSanitizer.clean(accumulatedAnswer, streaming: false)
                let finalThought = AITextSanitizer.clean(accumulatedThought, streaming: false)
                await MainActor.run {
                    self.generatedText = finalClean
                    if config.showThinkingProcess && !finalThought.isEmpty {
                        self.thinkingText = finalThought
                        self.thoughtToggleButton.isHidden = false
                        self.updateThoughtHeader()
                        self.thoughtTextView.text = finalThought
                    }
                    if finalClean.isEmpty {
                        self.outputTextView.text = "⚠️ 模型未返回正文，请检查模型配置或点击重试。"
                    } else {
                        self.outputTextView.text = finalClean
                        AIRecentHistoryStore.record(
                            title: self.lastRunPair?.title ?? "AI 助手",
                            output: finalClean,
                            prompt: displayPrompt.isEmpty ? self.inputDraftText : displayPrompt
                        )
                    }
                    self.stopOrRetryButton.setTitle("重试", for: .normal)
                    self.updateActionButtonsEnabled()
                }
            } catch {
                await MainActor.run {
                    self.outputTextView.text = "⚠️ 生成失败：\(error.localizedDescription)"
                    self.stopOrRetryButton.setTitle("重试", for: .normal)
                    self.updateActionButtonsEnabled()
                }
            }
        }
    }

    private func updateActionButtonsEnabled() {
        let ready = !generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        setNeedsLayout()
        copyButton.isEnabled = ready
        copyButton.alpha = ready ? 1.0 : 0.45
        insertButton.isEnabled = ready
        insertButton.alpha = ready ? 1.0 : 0.45
        let canReplace = ready && hostReplaceCount > 0
        replaceButton.isEnabled = canReplace
        replaceButton.alpha = canReplace ? 1.0 : 0.42
    }

    private func handleCopyGeneratedText() {
        let trimmed = AITextSanitizer.clean(generatedText, streaming: false)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
        _ = ClipboardStore.record(trimmed)
        copyButton.setTitle("✓已复制", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            self?.copyButton.setTitle("复制", for: .normal)
        }
    }

    private func handleStopOrRetry() {
        if let task = streamTask, !task.isCancelled, stopOrRetryButton.title(for: .normal) == "停止" {
            task.cancel()
            stopOrRetryButton.setTitle("重试", for: .normal)
        } else if let pair = lastRunPair {
            streamPrompt(
                prompt: pair.prompt,
                systemInstruction: pair.sys,
                featureTag: "ai_retry",
                displayPrompt: inputDraftText,
                preferFast: pair.preferFast,
                preferDeep: pair.preferDeep
            )
        } else {
            handleSendFreeQuestion()
        }
    }

    private func handleReplace() {
        let trimmed = AITextSanitizer.clean(generatedText, streaming: false)
        guard !trimmed.isEmpty, hostReplaceCount > 0 else { return }
        setExpandedReadingHeight(false)
        onReplaceBeforeCursor?(hostReplaceCount, trimmed)
    }

    private func handleInsert() {
        let trimmed = AITextSanitizer.clean(generatedText, streaming: false)
        guard !trimmed.isEmpty else { return }
        setExpandedReadingHeight(false)
        onInsertText?(trimmed)
    }
}
