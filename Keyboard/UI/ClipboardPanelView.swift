import UIKit

/// 剪贴板历史、置顶常用短语与趣味工具（花样字体 / 骰子 / 抽签）抽屉面板。
final class ClipboardPanelView: UIView {
    enum Tab: Int, CaseIterable {
        case history = 0
        case phrases = 1
        case funWorkshop = 2

        var title: String {
            switch self {
            case .history: return "剪贴板"
            case .phrases: return "常用短语"
            case .funWorkshop: return "趣味玩法"
            }
        }
    }

    var onInsertText: ((String) -> Void)?
    var onSendToAI: ((String) -> Void)?
    var onStylishFontChanged: ((StylishFontStyle) -> Void)?
    var onClose: (() -> Void)?

    private let headerStack = UIStackView()
    private let subActionBar = UIView()
    private let pasteTarget = PasteTargetView()
    private var pasteNowControl: UIPasteControl?
    private let clearUnpinnedButton = ActionClosureButton(type: .system)
    private let backButton = ActionClosureButton(type: .system)

    private let scrollView = LingxiScrollView()
    private let listStack = UIStackView()

    private var currentTab: Tab = .history
    private var theme: ResolvedTheme?
    private var activeFontStyle: StylishFontStyle = .normal
    private var explodedItemID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        pasteTarget.onPasteText = { [weak self] text in
            _ = ClipboardStore.record(text, changeCount: UIPasteboard.general.changeCount)
            self?.reloadContent()
        }
        addSubview(pasteTarget)

        headerStack.axis = .horizontal
        headerStack.distribution = .fillEqually
        headerStack.spacing = 6
        addSubview(headerStack)

        addSubview(subActionBar)

        clearUnpinnedButton.setTitle("清空未置顶", for: .normal)
        clearUnpinnedButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        clearUnpinnedButton.actionHandler = { [weak self] in
            ClipboardStore.clearUnpinned()
            self?.reloadContent()
        }
        subActionBar.addSubview(clearUnpinnedButton)

        backButton.setTitle("返回", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        backButton.actionHandler = { [weak self] in self?.onClose?() }
        subActionBar.addSubview(backButton)

        scrollView.showsVerticalScrollIndicator = true
        addSubview(scrollView)

        listStack.axis = .vertical
        listStack.spacing = 8
        listStack.alignment = .fill
        scrollView.addSubview(listStack)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pasteTarget.frame = CGRect(x: 0, y: 0, width: 1, height: 1)

        let pad: CGFloat = 8
        headerStack.frame = CGRect(x: pad, y: 6, width: bounds.width - pad * 2, height: 30)

        let subY = headerStack.frame.maxY + 6
        subActionBar.frame = CGRect(x: pad, y: subY, width: bounds.width - pad * 2, height: 30)
        backButton.frame = CGRect(x: subActionBar.bounds.width - 58, y: 0, width: 58, height: 28)

        if let pasteNowControl {
            pasteNowControl.frame = CGRect(x: 0, y: 0, width: 124, height: 28)
        }
        clearUnpinnedButton.frame = CGRect(x: 132, y: 0, width: 82, height: 28)

        let scrollY = subActionBar.frame.maxY + 6
        scrollView.frame = CGRect(x: 0, y: scrollY, width: bounds.width, height: max(40, bounds.height - scrollY - 4))

        let targetW = max(100, bounds.width - pad * 2)
        let fitSize = listStack.systemLayoutSizeFitting(
            CGSize(width: targetW, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        listStack.frame = CGRect(x: pad, y: 2, width: targetW, height: fitSize.height)
        scrollView.contentSize = CGSize(width: bounds.width, height: fitSize.height + 12)
    }

    func configure(theme: ResolvedTheme, activeFontStyle: StylishFontStyle, initialTab: Tab? = nil) {
        self.theme = theme
        self.activeFontStyle = activeFontStyle
        if let initialTab {
            self.currentTab = initialTab
        }
        backgroundColor = theme.canvasTop.withAlphaComponent(0.96)
        backButton.backgroundColor = theme.specialKeyFill
        backButton.setTitleColor(theme.keyText, for: .normal)
        backButton.layer.cornerRadius = 8
        backButton.layer.cornerCurve = .continuous

        clearUnpinnedButton.backgroundColor = theme.specialKeyFill
        clearUnpinnedButton.setTitleColor(theme.keyHintText, for: .normal)
        clearUnpinnedButton.layer.cornerRadius = 8
        clearUnpinnedButton.layer.cornerCurve = .continuous

        rebuildPasteControl(theme: theme)
        rebuildHeader()
        reloadContent()
    }

    private func rebuildPasteControl(theme: ResolvedTheme) {
        pasteNowControl?.removeFromSuperview()
        var cfg = UIPasteControl.Configuration()
        cfg.displayMode = .iconAndLabel
        cfg.cornerStyle = .capsule
        cfg.baseBackgroundColor = theme.accentFill
        cfg.baseForegroundColor = theme.accentText
        let control = UIPasteControl(configuration: cfg)
        control.target = pasteTarget
        subActionBar.addSubview(control)
        pasteNowControl = control
    }

    private func rebuildHeader() {
        headerStack.arrangedSubviews.forEach {
            headerStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }
        for tab in Tab.allCases {
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(tab.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            let active = (tab == currentTab)
            btn.backgroundColor = active ? theme.accentFill : theme.specialKeyFill
            btn.setTitleColor(active ? theme.accentText : theme.keyText, for: .normal)
            btn.layer.cornerRadius = 8
            btn.layer.cornerCurve = .continuous
            btn.actionHandler = { [weak self] in
                self?.currentTab = tab
                self?.rebuildHeader()
                self?.reloadContent()
                self?.scrollView.setContentOffset(.zero, animated: false)
            }
            headerStack.addArrangedSubview(btn)
        }
    }

    func reloadContent() {
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }

        let showHistoryControls = (currentTab == .history)
        pasteNowControl?.isHidden = !showHistoryControls
        clearUnpinnedButton.isHidden = !showHistoryControls

        switch currentTab {
        case .history:
            let items = ClipboardStore.items()
            if items.isEmpty {
                listStack.addArrangedSubview(makeEmptyLabel("暂无剪贴板记录\n点击左上角按钮可直接读取当前系统剪贴板（零弹窗）", theme: theme))
            } else {
                for item in items {
                    listStack.addArrangedSubview(makeClipboardRow(item: item, theme: theme))
                }
            }

        case .phrases:
            let phrases = QuickPhraseStore.load()
            for phrase in phrases {
                listStack.addArrangedSubview(makePhraseRow(phrase: phrase, theme: theme))
            }

        case .funWorkshop:
            listStack.addArrangedSubview(makeFunWorkshopSection(theme: theme))
        }
        setNeedsLayout()
    }

    private func makeClipboardRow(item: ClipboardItem, theme: ResolvedTheme) -> UIView {
        let card = UIView()
        card.backgroundColor = theme.keyFill.withAlphaComponent(0.92)
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous

        let rowStack = UIStackView()
        rowStack.axis = .vertical
        rowStack.spacing = 6
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            rowStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            rowStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            rowStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
        ])

        let textButton = ActionClosureButton(type: .system)
        textButton.contentHorizontalAlignment = .left
        textButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        textButton.titleLabel?.numberOfLines = 2
        textButton.setTitleColor(theme.keyText, for: .normal)
        textButton.setTitle(item.text, for: .normal)
        textButton.actionHandler = { [weak self] in
            self?.onInsertText?(item.text)
        }
        rowStack.addArrangedSubview(textButton)

        let metaStack = UIStackView()
        metaStack.axis = .horizontal
        metaStack.spacing = 6
        metaStack.alignment = .center

        let badge = UILabel()
        badge.text = (item.isPinned ? "📌 " : "") + item.category.badgeText
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = theme.candidateHighlight
        metaStack.addArrangedSubview(badge)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metaStack.addArrangedSubview(spacer)

        if let code = item.extractedCode {
            let otpBtn = makeMiniPill("填入 \(code)", bg: theme.accentFill, fg: theme.accentText) { [weak self] in
                self?.onInsertText?(code)
            }
            metaStack.addArrangedSubview(otpBtn)
        }

        let aiBtn = makeMiniPill("AI回复", bg: theme.accentFill.withAlphaComponent(0.16), fg: theme.candidateHighlight) { [weak self] in
            self?.onSendToAI?(item.text)
        }
        let bangBtn = makeMiniPill(explodedItemID == item.id ? "收起分词" : "炸词", bg: theme.specialKeyFill, fg: theme.keyText) { [weak self] in
            guard let self else { return }
            self.explodedItemID = (self.explodedItemID == item.id) ? nil : item.id
            self.reloadContent()
        }
        let pinBtn = makeMiniPill(item.isPinned ? "取消置顶" : "置顶", bg: theme.specialKeyFill, fg: theme.keyText) { [weak self] in
            ClipboardStore.togglePin(id: item.id)
            self?.reloadContent()
        }
        let delBtn = makeMiniPill("删", bg: UIColor.systemRed.withAlphaComponent(0.14), fg: .systemRed) { [weak self] in
            ClipboardStore.delete(id: item.id)
            self?.reloadContent()
        }
        [aiBtn, bangBtn, pinBtn, delBtn].forEach { metaStack.addArrangedSubview($0) }
        rowStack.addArrangedSubview(metaStack)

        if explodedItemID == item.id {
            rowStack.addArrangedSubview(makeBigBangChipsView(for: item.text, theme: theme))
        }
        return card
    }

    /// BigBang 炸词选词片区：按语义拆分成独立小芯片，点按单挑粘贴某段号/地址/关键词。
    private func makeBigBangChipsView(for text: String, theme: ResolvedTheme) -> UIView {
        let tokens = BigBangTokenizer.tokenize(text)
        let container = FlowChipsView()
        let maxW = max(140, bounds.width - 36)
        container.configure(tokens: tokens, theme: theme, availableWidth: maxW) { [weak self] chosen in
            self?.onInsertText?(chosen)
        }
        return container
    }

    private func makePhraseRow(phrase: QuickPhrase, theme: ResolvedTheme) -> UIView {
        let card = ActionClosureButton(type: .system)
        card.backgroundColor = theme.keyFill.withAlphaComponent(0.88)
        card.layer.cornerRadius = 10
        card.contentHorizontalAlignment = .left
        card.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        card.titleLabel?.numberOfLines = 2
        card.setTitle("【\(phrase.category) · \(phrase.title)】\(phrase.content)", for: .normal)
        card.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .regular)
        card.setTitleColor(theme.keyText, for: .normal)
        card.actionHandler = { [weak self] in
            self?.onInsertText?(phrase.content)
        }
        return card
    }

    private func makeFunWorkshopSection(theme: ResolvedTheme) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 10

        // 1. 一键随机小彩蛋
        let funTitle = UILabel()
        funTitle.text = "🎲 一键趣味上屏"
        funTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        funTitle.textColor = theme.candidateHighlight
        container.addArrangedSubview(funTitle)

        let funButtonsRow = UIStackView()
        funButtonsRow.axis = .horizontal
        funButtonsRow.distribution = .fillEqually
        funButtonsRow.spacing = 6
        let toys: [(String, () -> String)] = [
            ("🎲 骰子", { FunGenerator.rollDice() }),
            ("🪙 抛硬币", { FunGenerator.flipCoin() }),
            ("🍽️ 吃什么", { FunGenerator.randomMeal() }),
            ("🎋 今日签", { FunGenerator.randomFortune() }),
        ]
        for (title, gen) in toys {
            let btn = makeMiniPill(title, bg: theme.keyFill, fg: theme.keyText) { [weak self] in
                self?.onInsertText?(gen())
            }
            btn.heightAnchor.constraint(equalToConstant: 34).isActive = true
            funButtonsRow.addArrangedSubview(btn)
        }
        container.addArrangedSubview(funButtonsRow)

        // 1.5 最近剪贴板快捷格式转换（全大写/全小写/简繁互转/去换行）
        if let latest = ClipboardStore.items().first?.text, !latest.isEmpty {
            let fmtTitle = UILabel()
            fmtTitle.text = "🛠️ 转换最近剪贴板并上屏"
            fmtTitle.font = .systemFont(ofSize: 13, weight: .semibold)
            fmtTitle.textColor = theme.candidateHighlight
            container.addArrangedSubview(fmtTitle)

            let fmtRow = UIStackView()
            fmtRow.axis = .horizontal
            fmtRow.distribution = .fillEqually
            fmtRow.spacing = 6
            let transforms: [(String, (String) -> String)] = [
                ("大写", { $0.uppercased() }),
                ("小写", { $0.lowercased() }),
                ("转繁", { ChineseScriptConverter.toTraditional($0) }),
                ("转简", { ChineseScriptConverter.toSimplified($0) }),
                ("去换行", { $0.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: "") }),
            ]
            for (title, fn) in transforms {
                let btn = makeMiniPill(title, bg: theme.specialKeyFill, fg: theme.keyText) { [weak self] in
                    self?.onInsertText?(fn(latest))
                }
                btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
                fmtRow.addArrangedSubview(btn)
            }
            container.addArrangedSubview(fmtRow)
        }

        // 2. 花样英文字体切换
        let fontTitle = UILabel()
        fontTitle.text = "✨ 英文花样字体模式（开启后英文输入自动变形）"
        fontTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        fontTitle.textColor = theme.candidateHighlight
        container.addArrangedSubview(fontTitle)

        for style in StylishFontStyle.allCases {
            let active = (style == activeFontStyle)
            let btn = ActionClosureButton(type: .system)
            btn.backgroundColor = active ? theme.accentFill : theme.keyFill.withAlphaComponent(0.88)
            btn.setTitleColor(active ? theme.accentText : theme.keyText, for: .normal)
            btn.layer.cornerRadius = 9
            btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            btn.contentHorizontalAlignment = .left
            btn.setTitle("\(style.displayName)    \(style.previewSample)", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 14, weight: active ? .semibold : .regular)
            btn.actionHandler = { [weak self] in
                self?.activeFontStyle = style
                self?.onStylishFontChanged?(style)
                self?.reloadContent()
            }
            container.addArrangedSubview(btn)
        }

        return container
    }

    private func makeMiniPill(_ title: String, bg: UIColor, fg: UIColor, handler: @escaping () -> Void) -> ActionClosureButton {
        let btn = ActionClosureButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        btn.backgroundColor = bg
        btn.setTitleColor(fg, for: .normal)
        btn.layer.cornerRadius = 7
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        btn.actionHandler = handler
        return btn
    }

    private func makeEmptyLabel(_ text: String, theme: ResolvedTheme) -> UIView {
        let lbl = UILabel()
        lbl.text = text
        lbl.numberOfLines = 0
        lbl.textAlignment = .center
        lbl.font = .systemFont(ofSize: 13.5, weight: .regular)
        lbl.textColor = theme.keyHintText
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.heightAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
        return lbl
    }
}

/// 自适应流式折行词片容器（用于 BigBang 剪贴板炸词挑选）。
private final class FlowChipsView: UIView {
    private var chipButtons: [UIButton] = []
    private var heightConstraint: NSLayoutConstraint?

    func configure(tokens: [String], theme: ResolvedTheme, availableWidth: CGFloat, onTap: @escaping (String) -> Void) {
        subviews.forEach { $0.removeFromSuperview() }
        chipButtons.removeAll()
        for tok in tokens {
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(tok, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            btn.backgroundColor = theme.accentFill.withAlphaComponent(0.12)
            btn.setTitleColor(theme.candidateHighlight, for: .normal)
            btn.layer.cornerRadius = 7
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
            btn.actionHandler = { onTap(tok) }
            addSubview(btn)
            chipButtons.append(btn)
        }
        let h = layoutChips(width: availableWidth)
        if heightConstraint == nil {
            let hc = heightAnchor.constraint(equalToConstant: h)
            hc.priority = UILayoutPriority(999)
            hc.isActive = true
            heightConstraint = hc
        } else {
            heightConstraint?.constant = h
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 20 else { return }
        let h = layoutChips(width: bounds.width)
        if let heightConstraint, abs(heightConstraint.constant - h) > 1 {
            heightConstraint.constant = h
        }
    }

    @discardableResult
    private func layoutChips(width: CGFloat) -> CGFloat {
        guard width > 20, !chipButtons.isEmpty else { return 0 }
        var x: CGFloat = 0
        var y: CGFloat = 4
        let gap: CGFloat = 6
        let rowH: CGFloat = 28

        for btn in chipButtons {
            let w = min(width, max(28, btn.sizeThatFits(CGSize(width: width, height: rowH)).width))
            if x + w > width && x > 0 {
                x = 0
                y += rowH + gap
            }
            btn.frame = CGRect(x: x, y: y, width: w, height: rowH)
            x += w + gap
        }
        return y + rowH + 4
    }
}
