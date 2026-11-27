import UIKit

/// 键盘内嵌「😊 表情 · 颜文字 · 全符号」高速面板：
/// - 五大分类：常用 / 表情 / 颜文字 / 中文标点 / 序号数学符号
/// - 复用按钮池 + 零闪烁极速切换，支持底部一键回字母盘、空格与长按连续退格
final class EmojiSymbolPanelView: UIView {
    enum Category: Int, CaseIterable {
        case recent = 0
        case emoji = 1
        case kaomoji = 2
        case punctuation = 3
        case mathAndUnits = 4
        case layoutPack = 5

        var title: String {
            switch self {
            case .recent: return "🕒 常用"
            case .emoji: return "😊 表情"
            case .kaomoji: return "颜文字"
            case .punctuation: return "，。标点"
            case .mathAndUnits: return "①∑ 符号"
            case .layoutPack: return "⚡ 布局专属"
            }
        }

        var isWideCell: Bool {
            self == .kaomoji || self == .layoutPack
        }
    }

    enum EmojiSubgroup: Int, CaseIterable {
        case all = 0
        case emotion = 1
        case gesture = 2
        case work = 3
        case food = 4
        case celebrate = 5
        case animal = 6

        var title: String {
            switch self {
            case .all: return "全部"
            case .emotion: return "情绪"
            case .gesture: return "手势"
            case .work: return "职场"
            case .food: return "美食"
            case .celebrate: return "祝福"
            case .animal: return "动物"
            }
        }

        var emojis: [String] {
            switch self {
            case .all:
                return EmojiSymbolPanelView.richEmojis
            case .emotion:
                return [
                    "😂", "🤣", "😊", "😄", "😁", "😆", "😅", "🥹",
                    "🥺", "😭", "😢", "😤", "😡", "🤯", "😱", "😨",
                    "😍", "🥰", "😘", "😗", "☺️", "😳", "🤗", "🤭",
                    "🤔", "🤨", "😐", "😑", "🙄", "😏", "🫠", "🫡",
                    "😴", "😪", "😵‍💫", "🤒", "😷", "🤧", "🤮", "🥳",
                    "😎", "🤓", "🧐", "🤠", "😇", "😈", "👻", "🤖",
                ]
            case .gesture:
                return [
                    "👍", "👎", "👏", "🙌", "🙏", "🤝", "👌", "✌️",
                    "🤞", "🫶", "💪", "👋", "🤦", "🤷", "🙇", "👀",
                    "🫡", "🤗", "❤️", "💔", "💕", "💖", "💯", "🔥",
                ]
            case .work:
                return [
                    "🫡", "👌", "✅", "🙏", "💪", "👏", "🤝", "☕️",
                    "💻", "📱", "📝", "📚", "💡", "🎯", "🚀", "⏰",
                    "📅", "📊", "🔧", "🐛", "🔒", "⚠️", "❌", "🚫",
                    "❓", "❗", "✨", "🔥", "💯", "🎉", "🐟", "😩",
                ]
            case .food:
                return [
                    "☕️", "🧋", "🍺", "🍻", "🥂", "🍵", "🍉", "🍓",
                    "🍎", "🍔", "🍟", "🍕", "🍜", "🍲", "🍣", "🍱",
                    "🍚", "🍰", "🎂", "🍦", "🍢", "🥐", "🥗", "🍿",
                ]
            case .celebrate:
                return [
                    "🎉", "🎊", "🎈", "🎂", "🎁", "🧧", "🏆", "🥇",
                    "❤️", "🧡", "💛", "💚", "💙", "💜", "💕", "💖",
                    "🌹", "💐", "🌸", "🌺", "🍀", "✨", "🌟", "💫",
                    "💰", "💍", "🥳", "🥂", "🍻", "💯", "🔥", "🌈",
                ]
            case .animal:
                return [
                    "🐶", "🐱", "🐼", "🐰", "🦊", "🐻", "🐨", "🐯",
                    "🦁", "🐮", "🐷", "🐸", "🐵", "🦄", "🐝", "🦋",
                    "🐟", "🦆", "☀️", "🌙", "🌈", "🌧️", "❄️", "🌸",
                ]
            }
        }
    }

    var onInsertText: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onSpace: (() -> Void)?
    var onClose: (() -> Void)?

    private let topScroll = LingxiScrollView()
    private let categoryStack = UIStackView()
    private let subgroupScroll = LingxiScrollView()
    private let subgroupStack = UIStackView()
    private let gridScroll = LingxiScrollView()
    private let gridContainer = UIView()
    private let bottomBar = UIStackView()
    private let backButton = ActionClosureButton(type: .system)
    private let spaceButton = ActionClosureButton(type: .system)
    private let deleteButton = ActionClosureButton(type: .system)

    private var categoryButtons: [UIButton] = []
    private var subgroupButtons: [UIButton] = []
    private var cellPool: [UIButton] = []
    private var currentCategory: Category = .emoji
    private var currentSubgroup: EmojiSubgroup = .all
    private var currentItems: [String] = []
    private var packQuickTokens: [String] = []
    private var theme: ResolvedTheme?
    private var repeatTimer: Timer?
    private var repeatCount = 0

    static let defaultFrequentEmojis: [String] = [
        "😂", "🤣", "😊", "🥹", "😭", "😍", "🥰", "😘",
        "👍", "🙏", "👌", "💪", "🎉", "❤️", "🔥", "✨",
        "🤔", "😅", "🙄", "🥺", "😎", "🥳", "🤗", "🫡",
    ]

    static let richEmojis: [String] = [
        "😂", "🤣", "😊", "😄", "😁", "😆", "😅", "🥹",
        "🥺", "😭", "😢", "😤", "😡", "🤯", "😱", "😨",
        "😍", "🥰", "😘", "😗", "☺️", "😳", "🤗", "🤭",
        "🤔", "🤨", "😐", "😑", "🙄", "😏", "🫠", "🫡",
        "😴", "😪", "😵‍💫", "🤒", "😷", "🤧", "🤮", "🥳",
        "😎", "🤓", "🧐", "🤠", "😇", "😈", "👻", "🤖",
        "👍", "👎", "👏", "🙌", "🙏", "🤝", "👌", "✌️",
        "🤞", "🫶", "💪", "👋", "🤦", "🤷", "🙇", "👀",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "💔",
        "💕", "💖", "💯", "🔥", "✨", "🌟", "💫", "💥",
        "🎉", "🎊", "🎈", "🎂", "🎁", "🧧", "🏆", "🥇",
        "🌹", "💐", "🌸", "🌺", "🍀", "☀️", "🌙", "🌈",
        "☕️", "🧋", "🍺", "🍻", "🥂", "🍉", "🍓", "🍎",
        "🍔", "🍟", "🍕", "🍜", "🍲", "🍣", "🍰", "🍦",
        "🐶", "🐱", "🐼", "🐰", "🦊", "🐻", "🐨", "🐯",
        "🦁", "🐮", "🐷", "🐸", "🐵", "🦄", "🐝", "🦋",
        "🚀", "✈️", "🚗", "🏠", "💻", "📱", "📷", "💡",
        "📚", "📝", "✅", "❌", "⚠️", "🚫", "❓", "❗",
    ]

    static let curatedKaomojis: [String] = [
        "(≧▽≦)", "ヽ(✿ﾟ▽ﾟ)ノ", "(｡•̀ᴗ-)✧", "(๑•̀ㅂ•́)و✧",
        "(づ￣ 3￣)づ", "(ﾉ´▽｀)ﾉ♪", "(✿◡‿◡)", "(´▽`ʃ♡ƪ)",
        "(╥﹏╥)", "(つД`)ノ", "(´•ω•̥`)", "(｡•́︿•̀｡)",
        "(ー_ー)!!", "¯\\_(ツ)_/¯", "(⊙_⊙)?", "(°ー°〃)",
        "(╯°□°）╯︵ ┻━┻", "┬─┬ ノ( ' - 'ノ)", "(ง •_•)ง", "✧(≖ ◡ ≖✿)",
        "ʕ•ᴥ•ʔ", "(=^･ω･^=)", "૮₍ ˶•⤙•˶ ₎ა", "(✪ω✪)",
        "( ´･･)ﾉ(._.`)", "(￣▽￣)~*", "(〃'▽'〃)", "(¬‿¬)",
        "o(*￣︶￣*)o", "Σ(っ °Д °;)っ", "(˘•ω•˘)", "(≧∇≦)ﾉ",
    ]

    static let chineseAndCommonPunctuations: [String] = [
        "，", "。", "？", "！", "、", "：", "；", "…",
        "……", "—", "——", "～", "·", "“", "”", "‘",
        "’", "「", "」", "『", "』", "【", "】", "《",
        "》", "〈", "〉", "（", "）", "[", "]", "{",
        "}", "(", ")", ",", ".", "?", "!", ":",
        ";", "\"", "'", "/", "\\", "|", "@", "#",
        "￥", "$", "%", "^", "&", "*", "_", "~",
    ]

    static let mathAndNumberSymbols: [String] = [
        "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧",
        "⑨", "⑩", "Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ",
        "+", "-", "×", "÷", "=", "≠", "≈", "±",
        "<", ">", "≤", "≥", "√", "∞", "∵", "∴",
        "%", "‰", "°", "℃", "℉", "㎡", "㎞", "㎏",
        "→", "←", "↑", "↓", "↗", "↘", "↔", "⇒",
        "✓", "✗", "★", "☆", "●", "○", "◆", "◇",
        "▲", "△", "■", "□", "•", "§", "№", "※",
        "¥", "$", "€", "£", "©", "®", "™", "♪",
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        repeatTimer?.invalidate()
    }

    private func setupViews() {
        topScroll.showsHorizontalScrollIndicator = false
        addSubview(topScroll)

        categoryStack.axis = .horizontal
        categoryStack.alignment = .center
        categoryStack.spacing = 6
        topScroll.addSubview(categoryStack)

        for cat in Category.allCases {
            let btn = UIButton(type: .custom)
            btn.tag = cat.rawValue
            btn.setTitle(cat.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 11, bottom: 5, right: 11)
            btn.layer.cornerRadius = 13
            btn.layer.cornerCurve = .continuous
            btn.addTarget(self, action: #selector(handleCategoryTap(_:)), for: .touchUpInside)
            categoryStack.addArrangedSubview(btn)
            categoryButtons.append(btn)
        }

        subgroupScroll.showsHorizontalScrollIndicator = false
        addSubview(subgroupScroll)

        subgroupStack.axis = .horizontal
        subgroupStack.alignment = .center
        subgroupStack.spacing = 6
        subgroupScroll.addSubview(subgroupStack)

        for group in EmojiSubgroup.allCases {
            let btn = UIButton(type: .custom)
            btn.tag = group.rawValue
            btn.setTitle(group.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
            btn.contentEdgeInsets = UIEdgeInsets(top: 3, left: 9, bottom: 3, right: 9)
            btn.layer.cornerRadius = 10
            btn.layer.cornerCurve = .continuous
            btn.addTarget(self, action: #selector(handleSubgroupTap(_:)), for: .touchUpInside)
            subgroupStack.addArrangedSubview(btn)
            subgroupButtons.append(btn)
        }

        gridScroll.showsVerticalScrollIndicator = true
        addSubview(gridScroll)
        gridScroll.addSubview(gridContainer)

        bottomBar.axis = .horizontal
        bottomBar.distribution = .fillProportionally
        bottomBar.spacing = 8
        addSubview(bottomBar)

        backButton.setTitle("ABC 返回键盘", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
        backButton.layer.cornerRadius = 9
        backButton.layer.cornerCurve = .continuous
        backButton.actionHandler = { [weak self] in
            self?.onClose?()
        }

        spaceButton.setTitle("空格", for: .normal)
        spaceButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        spaceButton.layer.cornerRadius = 9
        spaceButton.layer.cornerCurve = .continuous
        spaceButton.actionHandler = { [weak self] in
            self?.onSpace?()
        }

        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        deleteButton.layer.cornerRadius = 9
        deleteButton.layer.cornerCurve = .continuous
        deleteButton.accessibilityLabel = "退格删除"
        deleteButton.actionHandler = { [weak self] in
            self?.onBackspace?()
        }
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleDeleteLongPress(_:)))
        lp.minimumPressDuration = 0.30
        deleteButton.addGestureRecognizer(lp)

        bottomBar.addArrangedSubview(backButton)
        bottomBar.addArrangedSubview(spaceButton)
        bottomBar.addArrangedSubview(deleteButton)
    }

    func configure(theme: ResolvedTheme, preferredCategory: Category? = nil, packQuickTokens: [String] = []) {
        self.theme = theme
        self.packQuickTokens = packQuickTokens
        if let preferredCategory {
            self.currentCategory = preferredCategory
        } else if currentCategory == .recent && RecentEmojiStore.load().isEmpty {
            self.currentCategory = .emoji
        }
        backgroundColor = theme.canvasTop
        backButton.backgroundColor = theme.specialKeyFill
        backButton.setTitleColor(theme.keyText, for: .normal)
        spaceButton.backgroundColor = theme.keyFill
        spaceButton.setTitleColor(theme.keyText, for: .normal)
        deleteButton.backgroundColor = theme.specialKeyFill
        deleteButton.tintColor = theme.keyText

        refreshCategoryStyles()
        reloadItems()
    }

    private func refreshCategoryStyles() {
        guard let theme else { return }
        for (idx, btn) in categoryButtons.enumerated() {
            let active = (idx == currentCategory.rawValue)
            btn.backgroundColor = active ? theme.accentFill : theme.specialKeyFill
            btn.setTitleColor(active ? theme.accentText : theme.keyText, for: .normal)
        }
        subgroupScroll.isHidden = (currentCategory != .emoji)
        for (idx, btn) in subgroupButtons.enumerated() {
            let active = (idx == currentSubgroup.rawValue)
            btn.backgroundColor = active ? theme.accentFill.withAlphaComponent(0.18) : .clear
            btn.setTitleColor(active ? theme.candidateHighlight : theme.keyHintText, for: .normal)
        }
    }

    private func items(for category: Category) -> [String] {
        switch category {
        case .recent:
            let recents = RecentEmojiStore.load()
            var merged = recents
            var seen = Set(recents)
            for fallback in Self.defaultFrequentEmojis where seen.insert(fallback).inserted {
                merged.append(fallback)
                if merged.count >= 32 { break }
            }
            return merged
        case .emoji:
            return currentSubgroup.emojis
        case .kaomoji:
            return Self.curatedKaomojis
        case .punctuation:
            return Self.chineseAndCommonPunctuations
        case .mathAndUnits:
            return Self.mathAndNumberSymbols
        case .layoutPack:
            if !packQuickTokens.isEmpty { return packQuickTokens }
            return CustomKeyboardLayoutPack.find(id: "developer")?.quickStripTokens ?? ["()", "{}", "[]", "「」", "《》", "——"]
        }
    }

    private func ensureCell(at idx: Int) -> UIButton {
        while cellPool.count <= idx {
            let btn = UIButton(type: .custom)
            btn.layer.cornerRadius = 8
            btn.layer.cornerCurve = .continuous
            btn.titleLabel?.adjustsFontSizeToFitWidth = true
            btn.titleLabel?.minimumScaleFactor = 0.65
            btn.addTarget(self, action: #selector(handleItemTap(_:)), for: .touchUpInside)
            gridContainer.addSubview(btn)
            cellPool.append(btn)
        }
        return cellPool[idx]
    }

    private func reloadItems() {
        guard let theme else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        currentItems = items(for: currentCategory)
        let isWide = currentCategory.isWideCell
        let isEmojiCat = (currentCategory == .emoji || currentCategory == .recent)
        let font: UIFont = isWide
            ? .systemFont(ofSize: 13.5, weight: .medium)
            : (isEmojiCat ? .systemFont(ofSize: 24) : .systemFont(ofSize: 18, weight: .medium))

        for (idx, item) in currentItems.enumerated() {
            let btn = ensureCell(at: idx)
            btn.isHidden = false
            btn.tag = idx
            if let cmd = KeyboardSwipeCommand.parse(item) {
                btn.setTitle("\(cmd.keycapBadge) \(cmd.displayTitle)", for: .normal)
                btn.setTitleColor(theme.candidateHighlight, for: .normal)
                btn.backgroundColor = theme.accentFill.withAlphaComponent(0.14)
            } else {
                btn.setTitle(item, for: .normal)
                btn.setTitleColor(theme.keyText, for: .normal)
                btn.backgroundColor = isEmojiCat ? theme.keyFill.withAlphaComponent(0.55) : theme.keyFill
            }
            btn.titleLabel?.font = font
        }
        for idx in currentItems.count..<cellPool.count {
            cellPool[idx].isHidden = true
        }
        gridScroll.setContentOffset(.zero, animated: false)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 8
        let topH: CGFloat = 32
        let botH: CGFloat = 38

        topScroll.frame = CGRect(x: 0, y: 4, width: bounds.width, height: topH)
        let catSize = categoryStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        categoryStack.frame = CGRect(x: pad, y: 2, width: catSize.width, height: topH - 4)
        topScroll.contentSize = CGSize(width: max(bounds.width, catSize.width + pad * 2), height: topH)

        let showSubgroup = (currentCategory == .emoji)
        subgroupScroll.isHidden = !showSubgroup
        let subH: CGFloat = showSubgroup ? 26 : 0
        if showSubgroup {
            subgroupScroll.frame = CGRect(x: 0, y: topScroll.frame.maxY + 2, width: bounds.width, height: subH)
            let subSize = subgroupStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            subgroupStack.frame = CGRect(x: pad, y: 1, width: subSize.width, height: subH - 2)
            subgroupScroll.contentSize = CGSize(width: max(bounds.width, subSize.width + pad * 2), height: subH)
        }

        bottomBar.frame = CGRect(x: pad, y: max(topH + subH + 8, bounds.height - botH - 5), width: max(80, bounds.width - pad * 2), height: botH)

        let gridY = (showSubgroup ? subgroupScroll.frame.maxY : topScroll.frame.maxY) + 4
        let gridH = max(48, bottomBar.frame.minY - gridY - 6)
        gridScroll.frame = CGRect(x: 0, y: gridY, width: bounds.width, height: gridH)

        let cols: Int = currentCategory.isWideCell ? (bounds.width > 500 ? 5 : 3) : (bounds.width > 500 ? 11 : 8)
        let gap: CGFloat = 6
        let usableW = max(120, bounds.width - pad * 2)
        let cellW = floor((usableW - gap * CGFloat(cols - 1)) / CGFloat(cols))
        let cellH: CGFloat = currentCategory.isWideCell ? 38 : 40

        for idx in 0..<min(currentItems.count, cellPool.count) {
            let r = idx / cols
            let c = idx % cols
            cellPool[idx].frame = CGRect(
                x: pad + CGFloat(c) * (cellW + gap),
                y: 4 + CGFloat(r) * (cellH + gap),
                width: cellW,
                height: cellH
            )
        }
        let rows = (currentItems.count + cols - 1) / max(1, cols)
        let totalH = max(gridH, CGFloat(rows) * (cellH + gap) + 8)
        gridContainer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: totalH)
        gridScroll.contentSize = CGSize(width: bounds.width, height: totalH)
    }

    @objc private func handleCategoryTap(_ sender: UIButton) {
        guard let cat = Category(rawValue: sender.tag), cat != currentCategory else { return }
        currentCategory = cat
        refreshCategoryStyles()
        reloadItems()
    }

    @objc private func handleSubgroupTap(_ sender: UIButton) {
        guard let group = EmojiSubgroup(rawValue: sender.tag), group != currentSubgroup else { return }
        currentSubgroup = group
        refreshCategoryStyles()
        reloadItems()
    }

    @objc private func handleItemTap(_ sender: UIButton) {
        guard currentItems.indices.contains(sender.tag) else { return }
        let text = currentItems[sender.tag]
        if currentCategory == .emoji || currentCategory == .recent {
            RecentEmojiStore.record(text)
        }
        onInsertText?(text)
    }

    @objc private func handleDeleteLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            repeatTimer?.invalidate()
            repeatCount = 0
            onBackspace?()
            let timer = Timer(timeInterval: 0.085, repeats: true) { [weak self] t in
                guard let self else { return }
                self.repeatCount += 1
                self.onBackspace?()
                if self.repeatCount == 12 {
                    t.invalidate()
                    let fast = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                        self?.onBackspace?()
                    }
                    RunLoop.main.add(fast, forMode: .common)
                    self.repeatTimer = fast
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            repeatTimer = timer
        case .ended, .cancelled, .failed:
            repeatTimer?.invalidate()
            repeatTimer = nil
            repeatCount = 0
        default:
            break
        }
    }
}
