import UIKit

/// 键盘顶部工具与智能状态栏（50pt 默认高度，可调 44–64pt）：
/// - 空闲常规态（极简白 / 墨玉设计）：
///   左侧主功能胶囊区 `[✨ 灵犀 AI]` `[译]` + 右侧轻量工具按钮 `[剪贴板]` `[设置]`（彻底移除表情/光标移动与 ⋯ 折叠杂乱项）
/// - 剪贴板 / 短信验证码独占接管态（Full-Bar Takeover）：
///   当检测到新复制内容或短信验证码时，自动隐藏常规工具栏按钮，整栏切换为「验证码一键填入 / 刚复制内容预览与粘贴」智能胶囊条；
///   粘贴或关闭后立即恢复常规工具栏。
/// - 拼音输入中：上方紧凑音节分词/纠错预览 + 候选词横向滚动条
/// - 边打边译 / AI 提问态：专享流式预览与快捷上屏控制条
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
        case toggleEditPad
        case toggleQuickSettings
        case toggleLayoutQuick
        case undoDelete
        case insertOTP(String)
        case pasteCaptured(String)
        case directPasteFallback
        case askAIForClipboard(String)
        case clipboardIntentAI(ClipboardIntentAction, String)
        case selectionQuickAI(title: String, instruction: String)
        case executeInlineAICommand(command: String, replaceCount: Int)
        case tapComposingSyllable(Int)
        case askAIForWord(String)
        case saveWordAsPhrase(String)
        case dismissClipboardBanner
        case forgetWord(word: String, py: String)
        case pinWord(word: String, py: String)
        case pickFirstChar(String)
        case pickLastChar(String)
        case sendAIPrompt
        case cancelAIPrompt
    }

    var onAction: ((Action) -> Void)?
    var onSelectCandidate: ((Int) -> Void)?
    var onLongPressCandidate: ((Int, UIView) -> Void)?
    var onToggleExpandCandidates: (() -> Void)?

    private let bottomHairline = UIView()
    private let composingScrollView = ToolbarHorizontalScrollView()
    private let composingLabel = UILabel()
    private let composingSyllableStack = UIStackView()
    private var lastSyllableSignature = ""
    private var activeEditingSyllableIdx: Int?
    let candidateBar = CandidateBarView()

    // 空闲功能区：可横向平滑滚动的双簇容器（宽屏自然左右分列，窄屏/多按钮自动可滑不遮挡）
    private let idleContainer = UIView()
    private let idleScrollView = ToolbarHorizontalScrollView()
    private let leftClusterStack = UIStackView()
    private let rightClusterStack = UIStackView()
    private let aiButton = UIButton(type: .system)
    private let translateButton = UIButton(type: .system)
    private let clipboardButton = UIButton(type: .system)
    private let layoutButton = UIButton(type: .system)
    private let editPadButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)

    // 框选即改（Selection In-Place Magic）：检测到宿主输入框选中文字时自动替换顶栏
    private let selectionMagicScroll = ToolbarHorizontalScrollView()
    private let selectionMagicStack = UIStackView()
    private var isSelectionMagicActive = false

    // 随打随唤内联 AI 指令条（检测到输入框以 @ai / /ai / // 结尾时零切换一键执行）
    private let inlineAICommandBar = UIView()
    private let inlineAICommandBtn = ActionClosureButton(type: .system)
    private var activeInlineCommand: InlineAICommandMatch?

    // 剪贴板 / 短信验证码全栏独占接管胶囊（Full-Bar Takeover）
    private let bannerContainer = UIView()
    private let bannerStack = UIStackView()
    private let pasteTargetView = PasteTargetView()
    private var pasteControl: UIPasteControl?
    private var currentBannerState: ClipboardBannerState = .hidden
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
    private var toolbarLayout: [ToolbarItemConfig] = defaultToolbarLayout
    private var showComposingStrip = true
    private var undoConfiguredVisible = true
    private var lastToolbarLayoutKey = ""

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

        bottomHairline.isUserInteractionEnabled = false
        addSubview(bottomHairline)

        composingScrollView.showsHorizontalScrollIndicator = false
        composingScrollView.showsVerticalScrollIndicator = false
        composingScrollView.alwaysBounceHorizontal = true
        composingScrollView.isHidden = true
        addSubview(composingScrollView)

        composingLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        composingLabel.lineBreakMode = .byClipping
        composingScrollView.addSubview(composingLabel)

        composingSyllableStack.axis = .horizontal
        composingSyllableStack.alignment = .center
        composingSyllableStack.spacing = 2
        composingSyllableStack.isHidden = true
        composingScrollView.addSubview(composingSyllableStack)

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

        idleScrollView.showsHorizontalScrollIndicator = false
        idleScrollView.showsVerticalScrollIndicator = false
        idleScrollView.alwaysBounceHorizontal = true
        idleScrollView.delaysContentTouches = false
        idleContainer.addSubview(idleScrollView)

        leftClusterStack.axis = .horizontal
        leftClusterStack.alignment = .center
        leftClusterStack.spacing = 8
        idleScrollView.addSubview(leftClusterStack)

        rightClusterStack.axis = .horizontal
        rightClusterStack.alignment = .center
        rightClusterStack.spacing = 6
        idleScrollView.addSubview(rightClusterStack)

        // 左侧核心胶囊：灵犀 AI + 译
        configurePrimaryPillButton(
            aiButton,
            title: "灵犀 AI",
            symbol: "sparkles",
            action: #selector(didTapAI)
        )
        configurePrimaryPillButton(
            translateButton,
            title: "译",
            symbol: "character.bubble",
            action: #selector(didTapTranslate)
        )

        // 右侧工具胶囊：撤销、九键切换、剪贴板、快捷设置
        configureUtilityButton(
            clipboardButton,
            title: nil,
            symbol: "doc.on.clipboard",
            accessibilityLabel: "剪贴板",
            action: #selector(didTapClipboard)
        )
        configureUtilityButton(
            layoutButton,
            title: "九键",
            symbol: nil,
            accessibilityLabel: "切换九键与26键",
            action: #selector(didTapLayout)
        )
        configureUtilityButton(
            editPadButton,
            title: nil,
            symbol: "cursorarrow.and.square.on.square.dashed",
            accessibilityLabel: "专业光标编辑台",
            action: #selector(didTapEditPad)
        )
        configureUtilityButton(
            settingsButton,
            title: nil,
            symbol: "slider.horizontal.3",
            accessibilityLabel: "键盘快捷设置",
            action: #selector(didTapSettings)
        )

        undoButton.setTitle(" 撤销", for: .normal)
        let undoImg = UIImage(
            systemName: "arrow.uturn.backward",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        )
        undoButton.setImage(undoImg, for: .normal)
        undoButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        undoButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        undoButton.layer.cornerRadius = 15
        undoButton.layer.cornerCurve = .continuous
        undoButton.isHidden = true
        undoButton.accessibilityLabel = "撤销"
        undoButton.addTarget(self, action: #selector(didTapUndo), for: .touchUpInside)

        leftClusterStack.addArrangedSubview(aiButton)
        leftClusterStack.addArrangedSubview(translateButton)
        [undoButton, layoutButton, editPadButton, clipboardButton, settingsButton].forEach {
            rightClusterStack.addArrangedSubview($0)
        }

        // 框选即改顶栏胶囊条
        selectionMagicScroll.isHidden = true
        idleContainer.addSubview(selectionMagicScroll)
        selectionMagicStack.axis = .horizontal
        selectionMagicStack.alignment = .center
        selectionMagicStack.spacing = 6
        selectionMagicScroll.addSubview(selectionMagicStack)
        setupSelectionMagicPills()

        // 随打随唤内联 @ai 指令执行条
        inlineAICommandBar.isHidden = true
        idleContainer.addSubview(inlineAICommandBar)
        inlineAICommandBtn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .bold)
        inlineAICommandBtn.titleLabel?.lineBreakMode = .byTruncatingTail
        inlineAICommandBtn.layer.cornerRadius = 15
        inlineAICommandBtn.layer.cornerCurve = .continuous
        inlineAICommandBtn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        inlineAICommandBtn.actionHandler = { [weak self] in
            guard let self, let match = self.activeInlineCommand else { return }
            self.onAction?(.executeInlineAICommand(command: match.command, replaceCount: match.fullMatchCount))
        }
        inlineAICommandBar.addSubview(inlineAICommandBtn)

        // 全栏接管胶囊容器（复制内容 / 短信验证码到来时整栏替换显示）
        bannerContainer.isHidden = true
        bannerContainer.layer.cornerRadius = 18
        bannerContainer.layer.cornerCurve = .continuous
        bannerContainer.layer.borderWidth = 0.5
        idleContainer.addSubview(bannerContainer)

        bannerStack.axis = .horizontal
        bannerStack.alignment = .center
        bannerStack.spacing = 6
        bannerContainer.addSubview(bannerStack)

        wordActionContainer.isHidden = true
        addSubview(wordActionContainer)

        setupAIPromptBar()
        setupTranslateBar()
    }

    private func configurePrimaryPillButton(_ btn: UIButton, title: String, symbol: String, action: Selector) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        btn.setImage(UIImage(systemName: symbol, withConfiguration: cfg), for: .normal)
        btn.setTitle(" " + title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 11, bottom: 6, right: 11)
        btn.layer.cornerRadius = 15
        btn.layer.cornerCurve = .continuous
        btn.layer.borderWidth = 0.5
        btn.addTarget(self, action: action, for: .touchUpInside)
    }

    private func configureUtilityButton(
        _ btn: UIButton,
        title: String?,
        symbol: String?,
        accessibilityLabel: String,
        action: Selector
    ) {
        if let symbol {
            let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            btn.setImage(UIImage(systemName: symbol, withConfiguration: cfg), for: .normal)
        }
        if let title {
            let prefix = symbol == nil ? "" : " "
            btn.setTitle("\(prefix)\(title)", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        } else {
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
        }
        btn.layer.cornerRadius = 15
        btn.layer.cornerCurve = .continuous
        btn.layer.borderWidth = 0.5
        btn.accessibilityLabel = accessibilityLabel
        btn.addTarget(self, action: action, for: .touchUpInside)
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
            btn.layer.cornerCurve = .continuous
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
        aiPromptSendBtn.layer.cornerRadius = 14
        aiPromptSendBtn.layer.cornerCurve = .continuous
        aiPromptSendBtn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 11, bottom: 5, right: 11)
        aiPromptSendBtn.actionHandler = { [weak self] in self?.onAction?(.sendAIPrompt) }
        aiPromptBar.addSubview(aiPromptSendBtn)

        aiPromptCancelBtn.setTitle("取消", for: .normal)
        aiPromptCancelBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        aiPromptCancelBtn.layer.cornerRadius = 14
        aiPromptCancelBtn.layer.cornerCurve = .continuous
        aiPromptCancelBtn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 9, bottom: 5, right: 9)
        aiPromptCancelBtn.actionHandler = { [weak self] in self?.onAction?(.cancelAIPrompt) }
        aiPromptBar.addSubview(aiPromptCancelBtn)
    }

    private func button(for id: ToolbarButtonID) -> UIButton {
        switch id {
        case .ai: return aiButton
        case .translate: return translateButton
        case .clipboard: return clipboardButton
        case .layout: return layoutButton
        case .editPad: return editPadButton
        case .settings: return settingsButton
        case .undo: return undoButton
        }
    }

    private func setupSelectionMagicPills() {
        let items: [(String, String)] = [
            ("✨ 润色选中", "请保持原意，将用户选中的这段文字润色得更加流畅自然得体。只输出改写后的文字。"),
            ("🌐 译为英文", "Translate the selected text into natural, idiomatic English. Output only the translation."),
            ("🌐 译为中文", "将选中的外文翻译成地道自然的简体中文。只输出译文。"),
            ("✂️ 缩成一句", "将用户选中的文字精简浓缩为一两句重点清晰的表达。只输出精简后的文字。"),
            ("👔 更正式", "将用户选中的文字改写为正式得体的职场商务口吻。只输出改写后的文字。"),
            ("💬 温和一点", "将用户选中的文字改写得更温和礼貌、高情商。只输出改写后的文字。"),
        ]
        for (title, inst) in items {
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            btn.layer.cornerRadius = 14
            btn.layer.cornerCurve = .continuous
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
            btn.actionHandler = { [weak self] in
                self?.onAction?(.selectionQuickAI(title: title, instruction: inst))
            }
            selectionMagicStack.addArrangedSubview(btn)
        }
    }

    /// 按配置应用左右分簇排序与显隐
    private func applyToolbarConfiguration() {
        let sorted = LingxiSettings.normalizedToolbarLayout(toolbarLayout)
        let key = sorted.map { "\($0.buttonID.rawValue):\($0.isVisible ? 1 : 0)" }.joined(separator: ",")
        guard key != lastToolbarLayoutKey else { return }
        lastToolbarLayoutKey = key

        for item in sorted {
            let btn = button(for: item.buttonID)
            if item.buttonID.isPrimaryLeftAction {
                leftClusterStack.addArrangedSubview(btn)
            } else {
                rightClusterStack.addArrangedSubview(btn)
            }
            if item.buttonID == .undo {
                undoConfiguredVisible = item.isVisible
                btn.isHidden = !item.isVisible || undoButton.isHidden
            } else {
                btn.isHidden = !item.isVisible
            }
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pasteTargetView.frame = CGRect(x: 2, y: 2, width: 4, height: 4)
        bottomHairline.frame = CGRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5)

        if hasCandidates {
            let showComposing = !(composingLabel.text ?? "").isEmpty || !composingSyllableStack.isHidden
            composingScrollView.isHidden = !showComposing
            if showComposing {
                composingScrollView.frame = CGRect(x: 12, y: 2, width: max(0, bounds.width - 24), height: 17)
                if !composingSyllableStack.isHidden {
                    let stackW = max(composingScrollView.bounds.width, ceil(composingSyllableStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width) + 6)
                    composingSyllableStack.frame = CGRect(x: 0, y: 0, width: stackW, height: 17)
                    composingScrollView.contentSize = CGSize(width: stackW, height: 17)
                } else {
                    let fitW = ceil(composingLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 17)).width) + 6
                    let contentW = max(composingScrollView.bounds.width, fitW)
                    composingLabel.frame = CGRect(x: 0, y: 0, width: contentW, height: 17)
                    composingScrollView.contentSize = CGSize(width: contentW, height: 17)
                }
                if composingScrollView.contentSize.width > composingScrollView.bounds.width {
                    composingScrollView.contentOffset = CGPoint(x: composingScrollView.contentSize.width - composingScrollView.bounds.width, y: 0)
                } else {
                    composingScrollView.contentOffset = .zero
                }
                candidateBar.frame = CGRect(x: 0, y: 17, width: bounds.width, height: max(28, bounds.height - 17))
            } else {
                candidateBar.frame = bounds
            }
        } else {
            composingScrollView.isHidden = true
        }

        idleContainer.frame = bounds
        idleScrollView.frame = bounds
        let pillH: CGFloat = 30
        let pillY = (bounds.height - pillH) / 2

        let leftSize = leftClusterStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        leftClusterStack.frame = CGRect(x: 12, y: pillY, width: leftSize.width, height: pillH)

        let rightSize = rightClusterStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let rightX = max(leftClusterStack.frame.maxX + 10, bounds.width - 12 - rightSize.width)
        rightClusterStack.frame = CGRect(x: rightX, y: pillY, width: rightSize.width, height: pillH)
        let idleContentW = max(bounds.width, rightClusterStack.frame.maxX + 12)
        idleScrollView.contentSize = CGSize(width: idleContentW, height: bounds.height)
        idleScrollView.isScrollEnabled = idleContentW > bounds.width + 1

        if !selectionMagicScroll.isHidden {
            selectionMagicScroll.frame = bounds
            let sw = max(bounds.width - 20, ceil(selectionMagicStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width) + 16)
            selectionMagicStack.frame = CGRect(x: 10, y: pillY, width: sw, height: pillH)
            selectionMagicScroll.contentSize = CGSize(width: sw + 16, height: bounds.height)
        }

        if !inlineAICommandBar.isHidden {
            inlineAICommandBar.frame = bounds
            inlineAICommandBtn.frame = CGRect(x: 12, y: pillY, width: max(80, bounds.width - 24), height: pillH)
        }

        // 全栏独占接管胶囊：当用户新复制内容或收到验证码时，占据整个顶栏宽度
        let bannerH: CGFloat = min(36, bounds.height - 10)
        bannerContainer.frame = CGRect(
            x: 10,
            y: (bounds.height - bannerH) / 2,
            width: max(0, bounds.width - 20),
            height: bannerH
        )
        bannerStack.frame = bannerContainer.bounds.insetBy(dx: 8, dy: 3)

        wordActionContainer.frame = bounds

        aiPromptBar.frame = bounds
        let cancelW: CGFloat = 52
        let sendW: CGFloat = 64
        aiPromptCancelBtn.frame = CGRect(x: bounds.width - cancelW - 10, y: (bounds.height - 30) / 2, width: cancelW, height: 30)
        aiPromptSendBtn.frame = CGRect(x: aiPromptCancelBtn.frame.minX - sendW - 6, y: (bounds.height - 30) / 2, width: sendW, height: 30)
        aiPromptLabel.frame = CGRect(x: 12, y: (bounds.height - 30) / 2, width: max(40, aiPromptSendBtn.frame.minX - 18), height: 30)

        translateBar.frame = bounds
        let tCloseW: CGFloat = 24
        let tLangW: CGFloat = 42
        let tToneW: CGFloat = 34
        let tSrcW: CGFloat = 26
        let tCommitW: CGFloat = 40
        let tH: CGFloat = 28
        let tY: CGFloat = (bounds.height - tH) / 2
        translateCloseBtn.frame = CGRect(x: bounds.width - 8 - tCloseW, y: tY, width: tCloseW, height: tH)
        translateLangBtn.frame = CGRect(x: translateCloseBtn.frame.minX - 4 - tLangW, y: tY, width: tLangW, height: tH)
        translateToneBtn.frame = CGRect(x: translateLangBtn.frame.minX - 4 - tToneW, y: tY, width: tToneW, height: tH)
        translateSourceBtn.frame = CGRect(x: translateToneBtn.frame.minX - 4 - tSrcW, y: tY, width: tSrcW, height: tH)
        translateCommitBtn.frame = CGRect(x: translateSourceBtn.frame.minX - 4 - tCommitW, y: tY, width: tCommitW, height: tH)
        let textW = max(56, translateCommitBtn.frame.minX - 14)
        translateSourceLabel.frame = CGRect(x: 10, y: 4, width: textW, height: 15)
        translateResultLabel.frame = CGRect(x: 10, y: 20, width: textW, height: 22)
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.toolbarBg
        bottomHairline.backgroundColor = theme.keyBorder.withAlphaComponent(0.65)
        composingLabel.textColor = theme.candidateHighlight

        stylePrimaryButtons(theme: theme, aiActive: false, translateActive: isTranslateBarActive)

        for btn in [clipboardButton, layoutButton, editPadButton, settingsButton] {
            btn.backgroundColor = theme.keyFill.withAlphaComponent(0.92)
            btn.tintColor = theme.keyText
            btn.setTitleColor(theme.keyText, for: .normal)
            btn.layer.borderColor = theme.keyBorder.withAlphaComponent(0.85).cgColor
        }

        for sub in selectionMagicStack.arrangedSubviews {
            if let btn = sub as? UIButton {
                btn.backgroundColor = theme.accentFill.withAlphaComponent(0.16)
                btn.setTitleColor(theme.candidateHighlight, for: .normal)
                btn.layer.borderWidth = 0.6
                btn.layer.borderColor = theme.accentFill.withAlphaComponent(0.40).cgColor
            }
        }

        undoButton.backgroundColor = theme.accentFill
        undoButton.tintColor = theme.accentText
        undoButton.setTitleColor(theme.accentText, for: .normal)

        bannerContainer.backgroundColor = theme.keyFill
        bannerContainer.layer.borderColor = theme.candidateHighlight.withAlphaComponent(0.28).cgColor

        aiPromptBar.backgroundColor = theme.accentFill.withAlphaComponent(0.10)
        aiPromptLabel.textColor = theme.keyText
        inlineAICommandBtn.backgroundColor = theme.accentFill
        inlineAICommandBtn.setTitleColor(theme.accentText, for: .normal)
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
        translateLangBtn.backgroundColor = theme.keyFill.withAlphaComponent(0.92)
        translateLangBtn.setTitleColor(theme.keyText, for: .normal)
        translateCloseBtn.backgroundColor = theme.specialKeyFill
        translateCloseBtn.tintColor = theme.keyText

        candidateBar.apply(theme: theme)
        rebuildBanner(force: true)
    }

    private func stylePrimaryButtons(theme: ResolvedTheme, aiActive: Bool, translateActive: Bool) {
        if aiActive {
            aiButton.backgroundColor = theme.accentFill
            aiButton.tintColor = theme.accentText
            aiButton.setTitleColor(theme.accentText, for: .normal)
            aiButton.layer.borderColor = UIColor.clear.cgColor
        } else {
            aiButton.backgroundColor = theme.accentFill.withAlphaComponent(0.10)
            aiButton.tintColor = theme.candidateHighlight
            aiButton.setTitleColor(theme.candidateHighlight, for: .normal)
            aiButton.layer.borderColor = theme.candidateHighlight.withAlphaComponent(0.26).cgColor
        }

        if translateActive {
            translateButton.backgroundColor = theme.accentFill
            translateButton.tintColor = theme.accentText
            translateButton.setTitleColor(theme.accentText, for: .normal)
            translateButton.layer.borderColor = UIColor.clear.cgColor
        } else {
            translateButton.backgroundColor = theme.keyFill.withAlphaComponent(0.92)
            translateButton.tintColor = theme.keyText
            translateButton.setTitleColor(theme.keyText, for: .normal)
            translateButton.layer.borderColor = theme.keyBorder.withAlphaComponent(0.85).cgColor
        }
    }

    func update(
        composingDisplay: String,
        composingSyllables: [String] = [],
        activeSyllableIndex: Int? = nil,
        candidates: [PinyinCandidate],
        expanded: Bool,
        showUndo: Bool,
        bannerState: ClipboardBannerState,
        aiPanelActive: Bool,
        layoutMode: KeyboardLayoutMode,
        aiPromptDraft: String?,
        translateState: TranslateBarState? = nil,
        selectedHostText: String? = nil,
        inlineAICommand: InlineAICommandMatch? = nil,
        hasFullAccess: Bool,
        toolbarLayout: [ToolbarItemConfig] = defaultToolbarLayout,
        showComposingStrip: Bool = true
    ) {
        self.toolbarLayout = toolbarLayout
        self.showComposingStrip = showComposingStrip
        self.activeEditingSyllableIdx = activeSyllableIndex
        applyToolbarConfiguration()
        self.hasCandidates = !candidates.isEmpty
        self.currentBannerState = bannerState
        self.hasFullAccess = hasFullAccess
        self.isAIPromptMode = (aiPromptDraft != nil)
        self.isTranslateBarActive = (translateState != nil)
        self.isSelectionMagicActive = (selectedHostText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) && !hasCandidates && !isAIPromptMode && !isTranslateBarActive && bannerState == .hidden
        self.activeInlineCommand = (!hasCandidates && !isAIPromptMode && !isTranslateBarActive && bannerState == .hidden && !isSelectionMagicActive && hasFullAccess) ? inlineAICommand : nil

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

        if showComposingStrip && composingSyllables.count >= 2 {
            composingLabel.text = ""
            composingLabel.isHidden = true
            composingSyllableStack.isHidden = false
            rebuildSyllableChips(composingSyllables, activeIndex: activeSyllableIndex)
        } else {
            composingSyllableStack.isHidden = true
            composingLabel.isHidden = false
            composingLabel.text = showComposingStrip ? composingDisplay : ""
        }
        candidateBar.isHidden = !hasCandidates
        idleContainer.isHidden = hasCandidates || (!aiPromptBar.isHidden) || (!translateBar.isHidden)
        undoButton.isHidden = !showUndo || !undoConfiguredVisible

        // 当剪贴板新内容或短信验证码胶囊激活，或者宿主输入框存在选中文字触发「框选即改」/ `@ai` 指令时，切换顶栏展示
        let isBannerTakeoverActive = (currentBannerState != .hidden)
        let isInlineAIActive = (activeInlineCommand != nil)
        if let cmd = activeInlineCommand {
            inlineAICommandBtn.setTitle("✨ 点此执行 AI：\(cmd.command)", for: .normal)
        }
        inlineAICommandBar.isHidden = !isInlineAIActive
        selectionMagicScroll.isHidden = !isSelectionMagicActive
        leftClusterStack.isHidden = isBannerTakeoverActive || isSelectionMagicActive || isInlineAIActive
        rightClusterStack.isHidden = isBannerTakeoverActive || isSelectionMagicActive || isInlineAIActive
        idleScrollView.isHidden = isBannerTakeoverActive || isSelectionMagicActive || isInlineAIActive

        if let theme {
            stylePrimaryButtons(theme: theme, aiActive: aiPanelActive, translateActive: isTranslateBarActive)
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

        let aiWordBtn = makeCapsuleButton(title: "✨换说法", bg: theme.accentFill.withAlphaComponent(0.18), fg: theme.candidateHighlight) { [weak self] in
            guard let self, let pending = self.pendingWordAction else { return }
            self.wordActionContainer.isHidden = true
            self.onAction?(.askAIForWord(pending.word))
        }
        let savePhraseBtn = makeCapsuleButton(title: "+短语", bg: theme.keyFill.withAlphaComponent(0.9), fg: theme.keyText) { [weak self] in
            guard let self, let pending = self.pendingWordAction else { return }
            self.wordActionContainer.isHidden = true
            self.onAction?(.saveWordAsPhrase(pending.word))
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

        arranged.append(contentsOf: [aiWordBtn, savePhraseBtn, pinBtn, forgetBtn, cancelBtn])
        arranged.forEach { stack.addArrangedSubview($0) }
        wordActionContainer.addSubview(stack)
        wordActionContainer.isHidden = false
    }

    private func rebuildBanner() {
        rebuildBanner(force: false)
    }

    /// 构建全宽独占顶栏的「短信验证码 / 新复制内容」智能胶囊
    private func rebuildBanner(force: Bool) {
        let bannerKey = "\(currentBannerState)|\(hasFullAccess)"
        if !force && bannerKey == lastBannerKey { return }
        lastBannerKey = bannerKey

        bannerStack.arrangedSubviews.forEach {
            bannerStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }

        let wasHidden = bannerContainer.isHidden
        let isTakeover = (currentBannerState != .hidden)
        leftClusterStack.isHidden = isTakeover
        rightClusterStack.isHidden = isTakeover

        switch currentBannerState {
        case .hidden:
            bannerContainer.isHidden = true
            bannerContainer.alpha = 1.0
            bannerContainer.transform = .identity

        case .detectedNewContent(_, let isURL, let isNumber):
            bannerContainer.isHidden = false
            if wasHidden {
                bannerContainer.alpha = 0.0
                bannerContainer.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
                UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    self.bannerContainer.alpha = 1.0
                    self.bannerContainer.transform = .identity
                }
            }

            let badge = makeTagBadge(
                icon: isURL ? "link" : (isNumber ? "number.square.fill" : "doc.on.clipboard.fill"),
                text: isURL ? "新链接" : (isNumber ? "验证码/数字" : "刚复制"),
                theme: theme
            )
            let hintLabel = UILabel()
            hintLabel.text = isNumber ? "检测到复制的数字或验证码" : "检测到刚复制的新内容"
            hintLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
            hintLabel.textColor = theme.keyText
            hintLabel.lineBreakMode = .byTruncatingTail
            hintLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            var cfg = UIPasteControl.Configuration()
            cfg.displayMode = .iconAndLabel
            cfg.cornerStyle = .capsule
            cfg.baseBackgroundColor = theme.accentFill
            cfg.baseForegroundColor = theme.accentText
            let control = UIPasteControl(configuration: cfg)
            control.target = pasteTargetView
            control.translatesAutoresizingMaskIntoConstraints = false
            control.heightAnchor.constraint(equalToConstant: 26).isActive = true
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            self.pasteControl = control

            bannerStack.addArrangedSubview(badge)
            bannerStack.addArrangedSubview(hintLabel)
            bannerStack.addArrangedSubview(control)

            if hasFullAccess {
                let fallbackBtn = makeCapsuleButton(
                    title: "直贴",
                    bg: theme.specialKeyFill,
                    fg: theme.keyText
                ) { [weak self] in
                    self?.onAction?(.directPasteFallback)
                }
                bannerStack.addArrangedSubview(fallbackBtn)
            }
            bannerStack.addArrangedSubview(makeCloseButton(tint: theme.keyHintText))

        case .readyPreview(let item):
            bannerContainer.isHidden = false
            if wasHidden {
                bannerContainer.alpha = 0.0
                bannerContainer.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
                UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    self.bannerContainer.alpha = 1.0
                    self.bannerContainer.transform = .identity
                }
            }
            let singleLine = item.text
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let code = item.extractedCode {
                // 模式 A：短信/通知验证码全栏独占提醒（支持左右滑动浏览完整短信内容）
                let badge = makeTagBadge(icon: "message.badge.filled.fill", text: "验证码", theme: theme)

                let codePreviewView = ScrollableBannerTextView(
                    text: "\(code)  ·  \(singleLine)",
                    font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                    textColor: theme.keyText,
                    accessibilityLabel: "验证码 \(code)，左右滑动查看完整短信，点按填入"
                ) { [weak self] in
                    self?.onAction?(.insertOTP(code))
                }

                let fillBtn = makeCapsuleButton(
                    title: "填入 \(code)",
                    bg: theme.accentFill,
                    fg: theme.accentText
                ) { [weak self] in
                    self?.onAction?(.insertOTP(code))
                }

                bannerStack.addArrangedSubview(badge)
                bannerStack.addArrangedSubview(codePreviewView)
                bannerStack.addArrangedSubview(fillBtn)

                if singleLine.count > code.count + 4 {
                    let fullBtn = makeCapsuleButton(
                        title: "全文",
                        bg: theme.specialKeyFill,
                        fg: theme.keyText
                    ) { [weak self] in
                        self?.onAction?(.pasteCaptured(item.text))
                    }
                    bannerStack.addArrangedSubview(fullBtn)
                }
                bannerStack.addArrangedSubview(makeCloseButton(tint: theme.keyHintText))
            } else {
                // 模式 B：刚复制的内容全栏独占预览与一键粘贴（支持左右滑动查看完整复制文字）
                let (icon, tagTitle): (String, String) = {
                    switch item.category {
                    case .url: return ("link", "新链接")
                    case .phone: return ("phone.fill", "号码")
                    case .code: return ("number.square.fill", "验证码")
                    case .text: return ("doc.on.clipboard.fill", "刚复制")
                    }
                }()
                let badge = makeTagBadge(icon: icon, text: tagTitle, theme: theme)

                let contentView = ScrollableBannerTextView(
                    text: singleLine,
                    font: .systemFont(ofSize: 13, weight: .medium),
                    textColor: theme.keyText,
                    accessibilityLabel: "刚复制的内容：\(singleLine)，左右滑动查看全文，点按直接粘贴"
                ) { [weak self] in
                    self?.onAction?(.pasteCaptured(item.text))
                }

                let pasteBtn = makeCapsuleButton(
                    title: "粘贴",
                    bg: theme.accentFill,
                    fg: theme.accentText
                ) { [weak self] in
                    self?.onAction?(.pasteCaptured(item.text))
                }

                bannerStack.addArrangedSubview(badge)
                bannerStack.addArrangedSubview(contentView)
                // 剪贴板语义意图直达胶囊（如复制了外文/提问/报错/长段文字，顶栏 1 步直达 AI 处理）
                if hasFullAccess, let intent = SmartContextPromptDetector.detectClipboardIntent(for: item.text) {
                    let aiIntentBtn = makeCapsuleButton(
                        title: intent.badge,
                        bg: theme.accentFill.withAlphaComponent(0.16),
                        fg: theme.candidateHighlight
                    ) { [weak self] in
                        self?.onAction?(.clipboardIntentAI(intent, item.text))
                    }
                    bannerStack.addArrangedSubview(aiIntentBtn)
                }
                bannerStack.addArrangedSubview(pasteBtn)
                bannerStack.addArrangedSubview(makeCloseButton(tint: theme.keyHintText))
            }
        }
        setNeedsLayout()
    }

    private func makeTagBadge(icon: String, text: String, theme: ResolvedTheme) -> UIView {
        let pill = UIButton(type: .system)
        pill.isUserInteractionEnabled = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
        pill.setImage(UIImage(systemName: icon, withConfiguration: cfg), for: .normal)
        pill.setTitle(" " + text, for: .normal)
        pill.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        pill.tintColor = theme.candidateHighlight
        pill.setTitleColor(theme.candidateHighlight, for: .normal)
        pill.backgroundColor = theme.accentFill.withAlphaComponent(0.12)
        pill.layer.cornerRadius = 12
        pill.layer.cornerCurve = .continuous
        pill.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        pill.setContentHuggingPriority(.required, for: .horizontal)
        pill.setContentCompressionResistancePriority(.required, for: .horizontal)
        return pill
    }

    private func makeCapsuleButton(title: String, bg: UIColor, fg: UIColor, handler: @escaping () -> Void) -> UIButton {
        let btn = ActionClosureButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        btn.backgroundColor = bg
        btn.setTitleColor(fg, for: .normal)
        btn.layer.cornerRadius = 13
        btn.layer.cornerCurve = .continuous
        btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        btn.actionHandler = handler
        return btn
    }

    private func makeCloseButton(tint: UIColor) -> UIButton {
        let btn = ActionClosureButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 10.5, weight: .bold)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        btn.tintColor = tint
        btn.accessibilityLabel = "关闭剪贴板提示并恢复工具栏"
        btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        btn.actionHandler = { [weak self] in
            self?.onAction?(.dismissClipboardBanner)
        }
        return btn
    }

    private func rebuildSyllableChips(_ syllables: [String], activeIndex: Int?) {
        let sig = "\(syllables.joined(separator: "'"))|\(activeIndex ?? -1)|\(theme?.preset.id ?? "")"
        guard sig != lastSyllableSignature else { return }
        lastSyllableSignature = sig
        composingSyllableStack.arrangedSubviews.forEach {
            composingSyllableStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }
        for (idx, syl) in syllables.enumerated() {
            if idx > 0 {
                let sep = UILabel()
                sep.text = "'"
                sep.font = .systemFont(ofSize: 11, weight: .medium)
                sep.textColor = theme.keyHintText
                composingSyllableStack.addArrangedSubview(sep)
            }
            let btn = ActionClosureButton(type: .custom)
            let isSelected = (activeIndex == idx)
            btn.setTitle(syl, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: isSelected ? .bold : .semibold)
            btn.setTitleColor(isSelected ? theme.accentText : theme.candidateHighlight, for: .normal)
            btn.backgroundColor = isSelected ? theme.accentFill : .clear
            btn.layer.cornerRadius = 4
            btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: isSelected ? 4 : 1, bottom: 0, right: isSelected ? 4 : 1)
            btn.actionHandler = { [weak self] in
                self?.onAction?(.tapComposingSyllable(idx))
            }
            composingSyllableStack.addArrangedSubview(btn)
        }
    }

    @objc private func didTapAI() { onAction?(.toggleAI) }
    @objc private func didTapTranslate() { onAction?(.toggleTranslateMode) }
    @objc private func didTapClipboard() { onAction?(.toggleClipboard) }
    @objc private func didTapLayout() { onAction?(.toggleLayoutQuick) }
    @objc private func didTapEditPad() { onAction?(.toggleEditPad) }
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

/// 允许在 UIButton/UIControl 上直接横滑触发滚动的专用横向 ScrollView（解决 iOS 默认 UIControl 拦截横向拖拽的问题）。
private final class ToolbarHorizontalScrollView: UIScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = true
        delaysContentTouches = false
        canCancelContentTouches = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        return true
    }
}

/// 顶栏可左右横向滑动的复制文本 / 短信预览组件：长文本不再截断，支持手指左右顺滑滚动查看全文并点按粘贴。
private final class ScrollableBannerTextView: UIView, UIScrollViewDelegate {
    private let scrollView = ToolbarHorizontalScrollView()
    private let textLabel = UILabel()
    private let fadeMaskLayer = CAGradientLayer()
    private let onTapHandler: () -> Void

    init(text: String, font: UIFont, textColor: UIColor, accessibilityLabel: String, onTap: @escaping () -> Void) {
        self.onTapHandler = onTap
        super.init(frame: .zero)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        scrollView.delegate = self
        addSubview(scrollView)

        fadeMaskLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        fadeMaskLayer.endPoint = CGPoint(x: 1.0, y: 0.5)

        textLabel.text = text
        textLabel.font = font
        textLabel.textColor = textColor
        textLabel.lineBreakMode = .byClipping
        textLabel.numberOfLines = 1
        textLabel.isUserInteractionEnabled = true
        textLabel.isAccessibilityElement = true
        textLabel.accessibilityLabel = accessibilityLabel
        textLabel.accessibilityTraits = .button
        scrollView.addSubview(textLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleTap() {
        UIView.animate(withDuration: 0.08, animations: {
            self.textLabel.alpha = 0.55
        }) { _ in
            UIView.animate(withDuration: 0.14) {
                self.textLabel.alpha = 1.0
            }
        }
        onTapHandler()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 30)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        let fit = textLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: max(28, bounds.height)))
        let textW = ceil(fit.width)
        let contentW = max(bounds.width, textW + 20)
        textLabel.frame = CGRect(x: 2, y: 0, width: max(bounds.width - 4, textW + 16), height: bounds.height)
        scrollView.contentSize = CGSize(width: contentW, height: bounds.height)
        updateEdgeFadeMask()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateEdgeFadeMask()
    }

    private func updateEdgeFadeMask() {
        let maxOffset = scrollView.contentSize.width - scrollView.bounds.width
        guard maxOffset > 4 else {
            layer.mask = nil
            return
        }
        let showLeftFade = scrollView.contentOffset.x > 4
        let showRightFade = scrollView.contentOffset.x < maxOffset - 4
        guard showLeftFade || showRightFade else {
            layer.mask = nil
            return
        }
        let opaque = UIColor.black.cgColor
        let clear = UIColor.clear.cgColor
        fadeMaskLayer.frame = bounds
        fadeMaskLayer.colors = [
            showLeftFade ? clear : opaque,
            opaque,
            opaque,
            showRightFade ? clear : opaque
        ]
        fadeMaskLayer.locations = [0.0, 0.08, 0.90, 1.0]
        layer.mask = fadeMaskLayer
    }
}
