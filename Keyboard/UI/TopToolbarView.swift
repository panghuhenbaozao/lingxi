import UIKit

/// 键盘顶部工具与候选条（46pt 高度）：
/// - 空闲时：快捷功能按钮 + 剪贴板智能胶囊（零弹窗 UIPasteControl / 验证码提取）
/// - 拼音输入中：上方紧凑音节分词/纠错预览 + 候选词横向滚动条
/// - AI 自由提问模式：高亮提问草稿栏 + 一键发送问 AI
final class TopToolbarView: UIView {
    struct TranslateBarState: Equatable {
        var targetLanguage: String
        var formalTone: Bool
        var sourceText: String
        var translatedText: String
        var isTranslating: Bool
        var errorText: String?
    }

    enum Action {
        case toggleAI
        case toggleTranslateMode
        case cycleTranslateTarget
        case toggleTranslateTone
        case commitTranslatedText
        case commitTranslateSource
        case toggleClipboard
        case toggleEmoji
        case toggleTextEditing
        case toggleQuickSettings
        case toggleLayoutQuick
        case undoDelete
        case insertOTP(String)
        case pasteCaptured(String)
        case directPasteFallback
        case askAIForClipboard(String)
        case dismissClipboardBanner
        case forgetWord(word: String, py: String)
        case pinWord(word: String, py: String)
        case pickFirstChar(String)
        case pickLastChar(String)
        case sendAIPrompt
        case cancelAIPrompt
        /// v4：聚合面板内触发被收纳按钮的动作
        case overflowTrigger(ToolbarButtonID)
    }

    var onAction: ((Action) -> Void)?
    var onSelectCandidate: ((Int) -> Void)?
    var onLongPressCandidate: ((Int, UIView) -> Void)?
    var onToggleExpandCandidates: (() -> Void)?

    private let composingLabel = UILabel()
    let candidateBar = CandidateBarView()

    // 空闲功能区
    private let idleContainer = UIView()
    private let buttonsStack = UIStackView()
    private let aiButton = UIButton(type: .system)
    private let translateButton = UIButton(type: .system)
    private let clipboardButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    private let editButton = UIButton(type: .system)
    private let layoutButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    /// v4 极简态：『⋯』聚合按钮——收纳被配置隐藏的低频按钮，点开弹出选择面板
    private let overflowButton = UIButton(type: .system)
    /// 聚合面板（半屏菜单）：展示被收起的按钮，选中即触发对应动作
    private let overflowPanel = UIView()
    private var overflowPanelButtons: [(id: ToolbarButtonID, btn: UIButton)] = []
    private var isOverflowPanelVisible = false
    /// 当前被收纳的按钮清单（applyToolbarConfiguration 时更新，主题重建用）
    private var currentHiddenIDs: [ToolbarButtonID] = []

    // 剪贴板智能胶囊
    private let bannerContainer = UIView()
    private let bannerScroll = UIScrollView()
    private let bannerStack = UIStackView()
    private let pasteTargetView = PasteTargetView()
    private var pasteControl: UIPasteControl?
    private var currentBannerState: ClipboardBannerState = .hidden
    /// 防闪烁：上次重建剪贴板胶囊时的状态签名，未变化时跳过全量重建
    private var lastBannerKey = ""

    // 长按候选词操作浮条
    private let wordActionContainer = UIView()
    private var pendingWordAction: (word: String, py: String)?

    // AI 自由提问草稿条
    private let aiPromptBar = UIView()
    private let aiPromptLabel = UILabel()
    private let aiPromptSendBtn = ActionClosureButton(type: .system)
    private let aiPromptCancelBtn = ActionClosureButton(type: .system)

    // 边打边译（Live Translate）预览条
    private let translateBar = UIView()
    private let translateSourceLabel = UILabel()
    private let translateResultLabel = UILabel()
    private let translateCommitBtn = ActionClosureButton(type: .system)
    private let translateSourceBtn = ActionClosureButton(type: .system)
    private let translateToneBtn = ActionClosureButton(type: .system)
    private let translateLangBtn = ActionClosureButton(type: .system)
    private let translateCloseBtn = ActionClosureButton(type: .system)

    private var theme: ResolvedTheme?
    private var hasCandidates = false
    private var isAIPromptMode = false
    private var isTranslateBarActive = false
    private var hasFullAccess = false
    private var onCapturedPaste: ((String) -> Void)?
    /// 工具栏布局配置（按钮排序 + 显隐），默认与原始固定顺序一致
    private var toolbarLayout: [ToolbarItemConfig] = defaultToolbarLayout
    /// 拼音/组合串预览条显隐开关
    private var showComposingStrip = true
    /// 撤销按钮是否被配置允许显示（与实际 showUndo 状态叠加）
    private var undoConfiguredVisible = true

    init(onCapturedPaste: @escaping (String) -> Void) {
        self.onCapturedPaste = onCapturedPaste
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        pasteTargetView.onPasteText = { [weak self] text in
            self?.onCapturedPaste?(text)
        }
        addSubview(pasteTargetView)

        composingLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        composingLabel.isHidden = true
        addSubview(composingLabel)

        candidateBar.isHidden = true
        candidateBar.onSelectCandidate = { [weak self] idx in
            self?.onSelectCandidate?(idx)
        }
        candidateBar.onLongPressCandidate = { [weak self] idx, view in
            self?.onLongPressCandidate?(idx, view)
        }
        candidateBar.onToggleExpand = { [weak self] in
            self?.onToggleExpandCandidates?()
        }
        addSubview(candidateBar)

        addSubview(idleContainer)
        buttonsStack.axis = .horizontal
        buttonsStack.alignment = .fill // .fill：系统按钮被拉伸到 44pt，触摸目标符合 HIG
        buttonsStack.spacing = 3
        idleContainer.addSubview(buttonsStack)

        configureToolButton(aiButton, title: "AI", symbol: "sparkles", action: #selector(didTapAI))
        configureToolButton(translateButton, title: "译", symbol: nil, action: #selector(didTapTranslate))
        configureToolButton(clipboardButton, title: nil, symbol: "doc.on.clipboard", action: #selector(didTapClipboard))
        configureToolButton(emojiButton, title: nil, symbol: "face.smiling", action: #selector(didTapEmoji))
        configureToolButton(editButton, title: nil, symbol: "arrow.up.and.down.and.arrow.left.and.right", action: #selector(didTapEdit))
        configureToolButton(layoutButton, title: "九键", symbol: nil, action: #selector(didTapLayout))
        configureToolButton(settingsButton, title: nil, symbol: "slider.horizontal.3", action: #selector(didTapSettings))
        configureToolButton(overflowButton, title: nil, symbol: "ellipsis", action: #selector(didTapOverflow))
        // VoiceOver：纯图标按钮补充功能标签（带文字标题的按钮沿用标题）
        clipboardButton.accessibilityLabel = "剪贴板"
        emojiButton.accessibilityLabel = "表情符号"
        editButton.accessibilityLabel = "文本编辑面板"
        settingsButton.accessibilityLabel = "键盘设置"
        overflowButton.accessibilityLabel = "更多功能"

        undoButton.setTitle(" 撤销", for: .normal)
        let undoImg = UIImage(systemName: "arrow.uturn.backward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        undoButton.setImage(undoImg, for: .normal)
        undoButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        undoButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        undoButton.layer.cornerRadius = 13
        undoButton.isHidden = true
        undoButton.accessibilityLabel = "撤销"
        undoButton.addTarget(self, action: #selector(didTapUndo), for: .touchUpInside)

        [aiButton, translateButton, clipboardButton, emojiButton, editButton, layoutButton, settingsButton, undoButton, overflowButton].forEach {
            buttonsStack.addArrangedSubview($0)
        }

        bannerContainer.isHidden = true
        idleContainer.addSubview(bannerContainer)
        bannerScroll.showsHorizontalScrollIndicator = false
        bannerScroll.delaysContentTouches = false
        bannerContainer.addSubview(bannerScroll)
        bannerStack.axis = .horizontal
        bannerStack.alignment = .center
        bannerStack.spacing = 6
        bannerScroll.addSubview(bannerStack)

        wordActionContainer.isHidden = true
        addSubview(wordActionContainer)

        // v4 聚合面板：横排胶囊浮层，覆盖工具栏区域（与词操作浮条同层）
        // 点击面板任意处关闭（cancelsTouchesInView=false，按钮 touchUpInside 不受影响）
        let overflowDismissTap = UITapGestureRecognizer(target: self, action: #selector(didTapOverflowDismiss))
        overflowDismissTap.cancelsTouchesInView = false
        overflowPanel.addGestureRecognizer(overflowDismissTap)
        overflowPanel.isHidden = true
        overflowPanel.layer.cornerRadius = 14
        overflowPanel.layer.shadowColor = UIColor.black.cgColor
        overflowPanel.layer.shadowOpacity = 0.12
        overflowPanel.layer.shadowRadius = 8
        overflowPanel.layer.shadowOffset = CGSize(width: 0, height: 3)
        addSubview(overflowPanel)

        setupAIPromptBar()
        setupTranslateBar()
    }

    private func setupTranslateBar() {
        translateBar.isHidden = true
        addSubview(translateBar)

        translateSourceLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        translateSourceLabel.lineBreakMode = .byTruncatingHead
        translateBar.addSubview(translateSourceLabel)

        translateResultLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        translateResultLabel.lineBreakMode = .byTruncatingHead
        translateBar.addSubview(translateResultLabel)

        func styleBtn(_ btn: ActionClosureButton, title: String, size: CGFloat = 11.5) {
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: size, weight: .semibold)
            btn.titleLabel?.adjustsFontSizeToFitWidth = true
            btn.titleLabel?.minimumScaleFactor = 0.75
            btn.layer.cornerRadius = 11
            translateBar.addSubview(btn)
        }

        styleBtn(translateCommitBtn, title: "上屏", size: 12)
        translateCommitBtn.actionHandler = { [weak self] in self?.onAction?(.commitTranslatedText) }

        styleBtn(translateSourceBtn, title: "原")
        translateSourceBtn.accessibilityLabel = "上屏原文"
        translateSourceBtn.actionHandler = { [weak self] in self?.onAction?(.commitTranslateSource) }

        styleBtn(translateToneBtn, title: "口语", size: 11)
        translateToneBtn.accessibilityHint = "点按切换口语或正式语气"
        translateToneBtn.actionHandler = { [weak self] in self?.onAction?(.toggleTranslateTone) }

        styleBtn(translateLangBtn, title: "英文")
        translateLangBtn.accessibilityHint = "点按切换目标语言"
        translateLangBtn.actionHandler = { [weak self] in self?.onAction?(.cycleTranslateTarget) }

        let xCfg = UIImage.SymbolConfiguration(pointSize: 10.5, weight: .bold)
        translateCloseBtn.setImage(UIImage(systemName: "xmark", withConfiguration: xCfg), for: .normal)
        translateCloseBtn.accessibilityLabel = "关闭翻译栏"
        translateCloseBtn.layer.cornerRadius = 11
        translateCloseBtn.actionHandler = { [weak self] in self?.onAction?(.toggleTranslateMode) }
        translateBar.addSubview(translateCloseBtn)
    }

    private func setupAIPromptBar() {
        aiPromptBar.isHidden = true
        addSubview(aiPromptBar)

        aiPromptLabel.font = .systemFont(ofSize: 13, weight: .medium)
        aiPromptLabel.lineBreakMode = .byTruncatingHead
        aiPromptBar.addSubview(aiPromptLabel)

        aiPromptSendBtn.setTitle("问 AI", for: .normal)
        aiPromptSendBtn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .bold)
        aiPromptSendBtn.layer.cornerRadius = 12
        aiPromptSendBtn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        aiPromptSendBtn.actionHandler = { [weak self] in self?.onAction?(.sendAIPrompt) }
        aiPromptBar.addSubview(aiPromptSendBtn)

        aiPromptCancelBtn.setTitle("取消", for: .normal)
        aiPromptCancelBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        aiPromptCancelBtn.layer.cornerRadius = 12
        aiPromptCancelBtn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        aiPromptCancelBtn.actionHandler = { [weak self] in self?.onAction?(.cancelAIPrompt) }
        aiPromptBar.addSubview(aiPromptCancelBtn)
    }

    private func button(for id: ToolbarButtonID) -> UIButton {
        switch id {
        case .ai: return aiButton
        case .translate: return translateButton
        case .clipboard: return clipboardButton
        case .emoji: return emojiButton
        case .edit: return editButton
        case .layout: return layoutButton
        case .settings: return settingsButton
        case .undo: return undoButton
        }
    }

    /// 防抖动：上次应用的工具栏布局签名，未变化时跳过重排（update 在打字链路高频触发）
    private var lastToolbarLayoutKey = ""

    /// 按配置重排工具栏按钮顺序并应用显隐（undo 的实际显隐还与 showUndo 叠加）
    private func applyToolbarConfiguration() {
        let sorted = LingxiSettings.normalizedToolbarLayout(toolbarLayout)
        let key = sorted.map { "\($0.buttonID.rawValue):\($0.isVisible ? 1 : 0)" }.joined(separator: ",")
        guard key != lastToolbarLayoutKey else { return }
        lastToolbarLayoutKey = key
        var hiddenIDs: [ToolbarButtonID] = []
        for item in sorted {
            let btn = button(for: item.buttonID)
            buttonsStack.addArrangedSubview(btn)
            if item.buttonID == .undo {
                undoConfiguredVisible = item.isVisible
                btn.isHidden = !item.isVisible || undoButton.isHidden
            } else {
                btn.isHidden = !item.isVisible
                if !item.isVisible { hiddenIDs.append(item.buttonID) }
            }
        }
        // v4 极简态：『⋯』固定在栈尾，仅当存在被收纳按钮时显示；面板内容同步重建
        buttonsStack.addArrangedSubview(overflowButton)
        overflowButton.isHidden = hiddenIDs.isEmpty
        currentHiddenIDs = hiddenIDs
        rebuildOverflowPanel(hiddenIDs: hiddenIDs)
        setNeedsLayout()
    }

    private func configureToolButton(_ btn: UIButton, title: String?, symbol: String?, action: Selector) {
        if let symbol {
            let cfg = UIImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
            btn.setImage(UIImage(systemName: symbol, withConfiguration: cfg), for: .normal)
        }
        if let title {
            let prefix = symbol == nil ? "" : " "
            btn.setTitle("\(prefix)\(title)", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 6.5, bottom: 5, right: 6.5)
        } else {
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6.5, bottom: 6, right: 6.5)
        }
        btn.layer.cornerRadius = 13
        btn.addTarget(self, action: action, for: .touchUpInside)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pasteTargetView.frame = CGRect(x: 2, y: 2, width: 4, height: 4)

        if hasCandidates {
            let showComposing = !(composingLabel.text ?? "").isEmpty
            composingLabel.isHidden = !showComposing
            if showComposing {
                composingLabel.frame = CGRect(x: 12, y: 2, width: bounds.width - 24, height: 15)
                candidateBar.frame = CGRect(x: 0, y: 16, width: bounds.width, height: max(28, bounds.height - 16))
            } else {
                candidateBar.frame = bounds
            }
        } else {
            composingLabel.isHidden = true
        }

        idleContainer.frame = bounds
        let buttonsSize = buttonsStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let buttonsWidth = min(buttonsSize.width, bounds.width - 12)
        // 新布局：工具按钮 44pt 打底（符合触摸目标规范），AI 按钮最醒目
        let toolH: CGFloat = 44
        buttonsStack.frame = CGRect(x: 8, y: (bounds.height - toolH) / 2, width: buttonsWidth, height: toolH)

        let bannerX = buttonsStack.frame.maxX + 6
        let bannerW = max(0, bounds.width - bannerX - 6)
        bannerContainer.frame = CGRect(x: bannerX, y: 4, width: bannerW, height: bounds.height - 8)
        bannerScroll.frame = bannerContainer.bounds
        let contentW = max(bannerW, bannerStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
        bannerStack.frame = CGRect(x: 0, y: 0, width: contentW, height: bannerScroll.bounds.height)
        bannerScroll.contentSize = bannerStack.frame.size

        wordActionContainer.frame = bounds

        // v4 聚合面板与工具栏同层覆盖；stack 跟随面板实际尺寸（构建时面板 bounds 尚为零，不能只靠 autoresizing）
        overflowPanel.frame = bounds
        if let stack = overflowPanel.subviews.first as? UIStackView {
            stack.frame = overflowPanel.bounds.insetBy(dx: 8, dy: 0)
        }

        aiPromptBar.frame = bounds
        let cancelW: CGFloat = 50
        let sendW: CGFloat = 62
        aiPromptCancelBtn.frame = CGRect(x: bounds.width - cancelW - 8, y: 8, width: cancelW, height: 30)
        aiPromptSendBtn.frame = CGRect(x: aiPromptCancelBtn.frame.minX - sendW - 6, y: 8, width: sendW, height: 30)
        aiPromptLabel.frame = CGRect(x: 12, y: 8, width: max(40, aiPromptSendBtn.frame.minX - 18), height: 30)

        translateBar.frame = bounds
        let tCloseW: CGFloat = 24
        let tLangW: CGFloat = 40
        let tToneW: CGFloat = 34
        let tSrcW: CGFloat = 26
        let tCommitW: CGFloat = 38
        let tY: CGFloat = 9
        let tH: CGFloat = 28
        translateCloseBtn.frame = CGRect(x: bounds.width - 6 - tCloseW, y: tY, width: tCloseW, height: tH)
        translateLangBtn.frame = CGRect(x: translateCloseBtn.frame.minX - 4 - tLangW, y: tY, width: tLangW, height: tH)
        translateToneBtn.frame = CGRect(x: translateLangBtn.frame.minX - 4 - tToneW, y: tY, width: tToneW, height: tH)
        translateSourceBtn.frame = CGRect(x: translateToneBtn.frame.minX - 4 - tSrcW, y: tY, width: tSrcW, height: tH)
        translateCommitBtn.frame = CGRect(x: translateSourceBtn.frame.minX - 4 - tCommitW, y: tY, width: tCommitW, height: tH)
        let textW = max(56, translateCommitBtn.frame.minX - 14)
        translateSourceLabel.frame = CGRect(x: 10, y: 3, width: textW, height: 15)
        translateResultLabel.frame = CGRect(x: 10, y: 19, width: textW, height: 22)
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.toolbarBg
        composingLabel.textColor = theme.candidateHighlight

        aiButton.backgroundColor = theme.accentFill.withAlphaComponent(0.14)
        aiButton.tintColor = theme.candidateHighlight
        aiButton.setTitleColor(theme.candidateHighlight, for: .normal)

        translateButton.backgroundColor = theme.keyFill.withAlphaComponent(0.75)
        translateButton.tintColor = theme.keyText
        translateButton.setTitleColor(theme.keyText, for: .normal)

        for btn in [clipboardButton, emojiButton, editButton, layoutButton, settingsButton, overflowButton] {
            btn.backgroundColor = theme.keyFill.withAlphaComponent(0.75)
            btn.tintColor = theme.keyText
            btn.setTitleColor(theme.keyText, for: .normal)
        }
        overflowPanel.backgroundColor = theme.toolbarBg
        undoButton.backgroundColor = theme.accentFill
        undoButton.tintColor = theme.accentText
        undoButton.setTitleColor(theme.accentText, for: .normal)

        aiPromptBar.backgroundColor = theme.accentFill.withAlphaComponent(0.12)
        aiPromptLabel.textColor = theme.keyText
        aiPromptSendBtn.backgroundColor = theme.accentFill
        aiPromptSendBtn.setTitleColor(theme.accentText, for: .normal)
        aiPromptCancelBtn.backgroundColor = theme.specialKeyFill
        aiPromptCancelBtn.setTitleColor(theme.keyText, for: .normal)

        translateBar.backgroundColor = theme.accentFill.withAlphaComponent(0.08)
        translateSourceLabel.textColor = theme.keyHintText
        translateResultLabel.textColor = theme.candidateHighlight
        translateCommitBtn.backgroundColor = theme.accentFill
        translateCommitBtn.setTitleColor(theme.accentText, for: .normal)
        translateSourceBtn.backgroundColor = theme.specialKeyFill
        translateSourceBtn.setTitleColor(theme.keyText, for: .normal)
        translateToneBtn.backgroundColor = theme.specialKeyFill
        translateToneBtn.setTitleColor(theme.keyText, for: .normal)
        translateLangBtn.backgroundColor = theme.keyFill.withAlphaComponent(0.9)
        translateLangBtn.setTitleColor(theme.keyText, for: .normal)
        translateCloseBtn.backgroundColor = theme.specialKeyFill
        translateCloseBtn.tintColor = theme.keyText

        candidateBar.apply(theme: theme)
        // 主题变化后强制重建胶囊以应用新配色
        rebuildBanner(force: true)
        // v4：主题变化后同步重建聚合面板配色
        rebuildOverflowPanel(hiddenIDs: currentHiddenIDs)
    }

    func update(
        composingDisplay: String,
        candidates: [PinyinCandidate],
        expanded: Bool,
        showUndo: Bool,
        bannerState: ClipboardBannerState,
        aiPanelActive: Bool,
        layoutMode: KeyboardLayoutMode,
        aiPromptDraft: String?,
        translateState: TranslateBarState? = nil,
        hasFullAccess: Bool,
        toolbarLayout: [ToolbarItemConfig] = defaultToolbarLayout,
        showComposingStrip: Bool = true
    ) {
        self.toolbarLayout = toolbarLayout
        self.showComposingStrip = showComposingStrip
        applyToolbarConfiguration()
        self.hasCandidates = !candidates.isEmpty
        self.currentBannerState = bannerState
        self.hasFullAccess = hasFullAccess
        self.isAIPromptMode = (aiPromptDraft != nil)
        self.isTranslateBarActive = (translateState != nil)

        layoutButton.setTitle(layoutMode == .qwerty26 ? "九键" : "26键", for: .normal)

        if let draft = aiPromptDraft, !hasCandidates {
            aiPromptBar.isHidden = false
            aiPromptLabel.text = draft.isEmpty ? "✨ 输入要问 AI 的问题…" : "✨ 问AI：\(draft)"
            aiPromptSendBtn.isEnabled = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            aiPromptSendBtn.alpha = aiPromptSendBtn.isEnabled ? 1.0 : 0.45
        } else {
            aiPromptBar.isHidden = true
        }

        if let tr = translateState, !hasCandidates, aiPromptDraft == nil {
            translateBar.isHidden = false
            let srcShow = tr.sourceText.isEmpty ? "请照常输入中文（停顿或标点自动译）" : tr.sourceText
            translateSourceLabel.text = "译 · 中→\(tr.targetLanguage) | \(srcShow)"
            if let err = tr.errorText, !err.isEmpty {
                translateResultLabel.text = "⚠️ \(err)"
            } else if tr.isTranslating && tr.translatedText.isEmpty {
                translateResultLabel.text = "正在流式翻译…"
            } else if tr.translatedText.isEmpty {
                translateResultLabel.text = "翻译预览将实时显示在这里（空格/回车上屏）"
            } else {
                translateResultLabel.text = tr.isTranslating ? "\(tr.translatedText) ▍" : tr.translatedText
            }
            // 方向指示：输入中文时译向目标语言，输入外文时译回中文（双向互译）；
            // 尚未输入时默认展示主用方向 中→目标语言
            let hasForeign = tr.sourceText.range(of: "[A-Za-z]", options: .regularExpression) != nil
            let hasChinese = tr.sourceText.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil
            let directionLabel = (hasForeign && !hasChinese) ? "英→中" : "中→\(tr.targetLanguage)"
            translateLangBtn.setTitle(directionLabel, for: .normal)
            translateLangBtn.accessibilityLabel = "翻译方向：\(directionLabel)"
            translateToneBtn.setTitle(tr.formalTone ? "正式" : "口语", for: .normal)
            translateToneBtn.accessibilityLabel = "译文语气：\(tr.formalTone ? "正式" : "口语")"
            if let theme {
                translateToneBtn.backgroundColor = tr.formalTone
                    ? theme.accentFill.withAlphaComponent(0.20)
                    : theme.specialKeyFill
                translateToneBtn.setTitleColor(tr.formalTone ? theme.candidateHighlight : theme.keyText, for: .normal)
            }
            let canCommitTranslated = !tr.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            translateCommitBtn.isEnabled = canCommitTranslated
            translateCommitBtn.alpha = canCommitTranslated ? 1.0 : 0.45
            let canCommitSource = !tr.sourceText.isEmpty
            translateSourceBtn.isEnabled = canCommitSource
            translateSourceBtn.alpha = canCommitSource ? 1.0 : 0.45
        } else {
            translateBar.isHidden = true
        }

        composingLabel.text = showComposingStrip ? composingDisplay : ""
        candidateBar.isHidden = !hasCandidates
        // v4：聚合面板打开时工具按钮区保持隐藏（update 高频触发不能破坏面板态）
        idleContainer.isHidden = hasCandidates || (!aiPromptBar.isHidden) || (!translateBar.isHidden) || isOverflowPanelVisible
        // v4：离开空闲态时自动收起聚合面板
        if hasCandidates || (!aiPromptBar.isHidden) || (!translateBar.isHidden) {
            if isOverflowPanelVisible { hideOverflowPanel() }
        }
        undoButton.isHidden = !showUndo || !undoConfiguredVisible

        if let theme {
            aiButton.backgroundColor = aiPanelActive
                ? theme.accentFill
                : theme.accentFill.withAlphaComponent(0.14)
            let aiTint = aiPanelActive ? theme.accentText : theme.candidateHighlight
            aiButton.tintColor = aiTint
            aiButton.setTitleColor(aiTint, for: .normal)

            translateButton.backgroundColor = isTranslateBarActive
                ? theme.accentFill
                : theme.keyFill.withAlphaComponent(0.75)
            let trTint = isTranslateBarActive ? theme.accentText : theme.keyText
            translateButton.tintColor = trTint
            translateButton.setTitleColor(trTint, for: .normal)
        }

        if hasCandidates {
            candidateBar.updateCandidates(candidates, expanded: expanded)
        }
        rebuildBanner()
        setNeedsLayout()
    }

    func showWordActionBar(word: String, py: String, isPinned: Bool) {
        guard let theme else { return }
        pendingWordAction = (word, py)
        wordActionContainer.subviews.forEach { $0.removeFromSuperview() }
        wordActionContainer.backgroundColor = theme.toolbarBg

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5
        stack.frame = wordActionContainer.bounds.insetBy(dx: 8, dy: 4)
        stack.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let title = UILabel()
        title.text = "「\(word)」"
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = theme.keyText
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var arranged: [UIView] = [title]
        if word.count >= 2, let first = word.first, let last = word.last {
            let firstStr = String(first)
            let lastStr = String(last)
            let firstBtn = makeCapsuleButton(title: "首「\(firstStr)」", bg: theme.keyFill.withAlphaComponent(0.9), fg: theme.keyText) { [weak self] in
                self?.wordActionContainer.isHidden = true
                self?.onAction?(.pickFirstChar(firstStr))
            }
            let lastBtn = makeCapsuleButton(title: "尾「\(lastStr)」", bg: theme.keyFill.withAlphaComponent(0.9), fg: theme.keyText) { [weak self] in
                self?.wordActionContainer.isHidden = true
                self?.onAction?(.pickLastChar(lastStr))
            }
            arranged.append(firstBtn)
            arranged.append(lastBtn)
        }

        let pinBtn = makeCapsuleButton(title: isPinned ? "解置" : "置顶", bg: theme.accentFill.withAlphaComponent(0.16), fg: theme.candidateHighlight) { [weak self] in
            guard let self, let pending = self.pendingWordAction else { return }
            self.wordActionContainer.isHidden = true
            self.onAction?(.pinWord(word: pending.word, py: pending.py))
        }
        let forgetBtn = makeCapsuleButton(title: "遗忘", bg: UIColor.systemRed.withAlphaComponent(0.15), fg: .systemRed) { [weak self] in
            guard let self, let pending = self.pendingWordAction else { return }
            self.wordActionContainer.isHidden = true
            self.onAction?(.forgetWord(word: pending.word, py: pending.py))
        }
        let cancelBtn = makeCapsuleButton(title: "取消", bg: theme.specialKeyFill, fg: theme.keyText) { [weak self] in
            self?.wordActionContainer.isHidden = true
        }

        arranged.append(contentsOf: [pinBtn, forgetBtn, cancelBtn])
        arranged.forEach { stack.addArrangedSubview($0) }
        wordActionContainer.addSubview(stack)
        wordActionContainer.isHidden = false
    }

    private func rebuildBanner() {
        rebuildBanner(force: false)
    }

    private func rebuildBanner(force: Bool) {
        // 防闪烁：refreshUI 高频触发本方法，剪贴板状态未变化时跳过全量重建（含 UIPasteControl 重建）
        let bannerKey = "\(currentBannerState)|\(hasFullAccess)"
        if !force && bannerKey == lastBannerKey { return }
        lastBannerKey = bannerKey
        bannerStack.arrangedSubviews.forEach {
            bannerStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }

        switch currentBannerState {
        case .hidden:
            bannerContainer.isHidden = true
        case .detectedNewContent(_, let isURL, let isNumber):
            bannerContainer.isHidden = false
            var cfg = UIPasteControl.Configuration()
            cfg.displayMode = .iconAndLabel
            cfg.cornerStyle = .capsule
            cfg.baseBackgroundColor = theme.accentFill
            cfg.baseForegroundColor = theme.accentText
            let control = UIPasteControl(configuration: cfg)
            control.target = pasteTargetView
            control.translatesAutoresizingMaskIntoConstraints = false
            control.heightAnchor.constraint(equalToConstant: 28).isActive = true
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            self.pasteControl = control

            let hintLabel = UILabel()
            hintLabel.text = isURL ? "🔗新链接" : (isNumber ? "🔢新数字" : "📋新复制")
            hintLabel.font = .systemFont(ofSize: 12, weight: .medium)
            hintLabel.textColor = theme.candidateText

            bannerStack.addArrangedSubview(hintLabel)
            bannerStack.addArrangedSubview(control)

            // 当某些宿主 App 限制 UIPasteControl 时，提供直接读取兜底按钮
            if hasFullAccess {
                let fallbackBtn = makeCapsuleButton(
                    title: "直贴",
                    bg: theme.keyFill.withAlphaComponent(0.9),
                    fg: theme.keyText
                ) { [weak self] in
                    self?.onAction?(.directPasteFallback)
                }
                bannerStack.addArrangedSubview(fallbackBtn)
            }
            bannerStack.addArrangedSubview(makeCloseButton(tint: theme.keyHintText))

        case .readyPreview(let item):
            bannerContainer.isHidden = false
            if let code = item.extractedCode {
                let otpBtn = makeCapsuleButton(
                    title: "🔢 填验证码 \(code)",
                    bg: theme.accentFill,
                    fg: theme.accentText
                ) { [weak self] in
                    self?.onAction?(.insertOTP(code))
                }
                bannerStack.addArrangedSubview(otpBtn)
            }

            let preview = item.text.replacingOccurrences(of: "\n", with: " ")
            let clipped = preview.count > 12 ? String(preview.prefix(12)) + "…" : preview
            let pasteBtn = makeCapsuleButton(
                title: "📋 \(clipped)",
                bg: theme.keyFill.withAlphaComponent(0.9),
                fg: theme.keyText
            ) { [weak self] in
                self?.onAction?(.pasteCaptured(item.text))
            }
            let aiReplyBtn = makeCapsuleButton(
                title: "✨ AI回",
                bg: theme.accentFill.withAlphaComponent(0.16),
                fg: theme.candidateHighlight
            ) { [weak self] in
                self?.onAction?(.askAIForClipboard(item.text))
            }
            bannerStack.addArrangedSubview(pasteBtn)
            bannerStack.addArrangedSubview(aiReplyBtn)
            bannerStack.addArrangedSubview(makeCloseButton(tint: theme.keyHintText))
        }
        setNeedsLayout()
    }

    private func makeCapsuleButton(title: String, bg: UIColor, fg: UIColor, handler: @escaping () -> Void) -> UIButton {
        let btn = ActionClosureButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        btn.backgroundColor = bg
        btn.setTitleColor(fg, for: .normal)
        btn.layer.cornerRadius = 13
        btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        btn.actionHandler = handler
        return btn
    }

    private func makeCloseButton(tint: UIColor) -> UIButton {
        let btn = ActionClosureButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        btn.tintColor = tint
        btn.accessibilityLabel = "关闭剪贴板提示"
        btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        btn.actionHandler = { [weak self] in
            self?.onAction?(.dismissClipboardBanner)
        }
        return btn
    }

    // MARK: v4 聚合面板（⋯）

    /// 重建聚合面板：横排胶囊按钮（被收纳功能）+ 收起按钮
    private func rebuildOverflowPanel(hiddenIDs: [ToolbarButtonID]) {
        overflowPanel.subviews.forEach { $0.removeFromSuperview() }
        overflowPanelButtons = []
        guard !hiddenIDs.isEmpty, let theme else { return }
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.frame = overflowPanel.bounds.insetBy(dx: 8, dy: 0)
        stack.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        for id in hiddenIDs {
            let btn = ActionClosureButton(type: .system)
            let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            btn.setImage(UIImage(systemName: id.symbolName, withConfiguration: cfg), for: .normal)
            btn.setTitle(" " + overflowDisplayName(for: id), for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            btn.backgroundColor = theme.keyFill.withAlphaComponent(0.9)
            btn.tintColor = theme.keyText
            btn.setTitleColor(theme.keyText, for: .normal)
            btn.layer.cornerRadius = 13
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
            btn.accessibilityLabel = overflowDisplayName(for: id)
            btn.actionHandler = { [weak self] in
                self?.hideOverflowPanel()
                self?.onAction?(.overflowTrigger(id))
            }
            stack.addArrangedSubview(btn)
            overflowPanelButtons.append((id, btn))
        }
        let closeBtn = ActionClosureButton(type: .system)
        let xCfg = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        closeBtn.setImage(UIImage(systemName: "chevron.up", withConfiguration: xCfg), for: .normal)
        closeBtn.tintColor = theme.keyHintText
        closeBtn.accessibilityLabel = "收起更多功能"
        closeBtn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        closeBtn.actionHandler = { [weak self] in self?.hideOverflowPanel() }
        stack.addArrangedSubview(closeBtn)
        overflowPanel.addSubview(stack)
    }

    /// 聚合面板按钮显示名
    private func overflowDisplayName(for id: ToolbarButtonID) -> String {
        switch id {
        case .ai: return "AI 助手"
        case .translate: return "边打边译"
        case .clipboard: return "剪贴板"
        case .emoji: return "表情"
        case .edit: return "文本编辑"
        case .layout: return "九键/26键"
        case .settings: return "快捷设置"
        case .undo: return "撤销"
        }
    }

    private func showOverflowPanel() {
        guard !overflowPanelButtons.isEmpty else { return }
        isOverflowPanelVisible = true
        overflowPanel.isHidden = false
        idleContainer.isHidden = true
        setNeedsLayout()
    }

    private func hideOverflowPanel() {
        guard isOverflowPanelVisible else { return }
        isOverflowPanelVisible = false
        overflowPanel.isHidden = true
        // 恢复空闲区可见性：与 update() 的判定一致
        idleContainer.isHidden = hasCandidates || (!aiPromptBar.isHidden) || (!translateBar.isHidden)
        setNeedsLayout()
    }

    @objc private func didTapOverflow() {
        isOverflowPanelVisible ? hideOverflowPanel() : showOverflowPanel()
    }

    /// v4：点击聚合面板空白处关闭（按钮自身点击由 actionHandler 处理，重复 hide 有 guard 无副作用）
    @objc private func didTapOverflowDismiss() {
        if isOverflowPanelVisible { hideOverflowPanel() }
    }

    @objc private func didTapAI() { onAction?(.toggleAI) }
    @objc private func didTapTranslate() { onAction?(.toggleTranslateMode) }
    @objc private func didTapClipboard() { onAction?(.toggleClipboard) }
    @objc private func didTapEmoji() { onAction?(.toggleEmoji) }
    @objc private func didTapEdit() { onAction?(.toggleTextEditing) }
    @objc private func didTapLayout() { onAction?(.toggleLayoutQuick) }
    @objc private func didTapSettings() { onAction?(.toggleQuickSettings) }
    @objc private func didTapUndo() { onAction?(.undoDelete) }
}

final class ActionClosureButton: UIButton {
    var actionHandler: (() -> Void)? {
        didSet {
            removeTarget(self, action: #selector(trigger), for: .touchUpInside)
            addTarget(self, action: #selector(trigger), for: .touchUpInside)
        }
    }

    @objc private func trigger() {
        actionHandler?()
    }
}
