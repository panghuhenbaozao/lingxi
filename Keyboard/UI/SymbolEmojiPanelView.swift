import UIKit

/// Emoji、颜文字与分类符号面板。
final class SymbolEmojiPanelView: UIView {
    enum Tab: Int, CaseIterable {
        case emoji = 0
        case kaomoji = 1
        case chineseSymbols = 2
        case englishSymbols = 3

        var title: String {
            switch self {
            case .emoji: return "Emoji"
            case .kaomoji: return "颜文字"
            case .chineseSymbols: return "中文符号"
            case .englishSymbols: return "英文/数学"
            }
        }
    }

    var onInsert: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onClose: (() -> Void)?
    var onRequestSearchMode: (() -> Void)?
    var onExitSearchMode: (() -> Void)?

    private let searchBarBtn = ActionClosureButton(type: .system)
    private let exitSearchBtn = ActionClosureButton(type: .system)
    private let headerStack = UIStackView()
    private let scrollView = UIScrollView()
    private let gridContainer = UIView()
    private let emptySearchLabel = UILabel()
    private let footerView = UIView()
    private let backButton = ActionClosureButton(type: .system)
    private let deleteButton = ActionClosureButton(type: .system)

    private var currentTab: Tab = .emoji
    private var theme: ResolvedTheme?
    private var recentEmojis: [String] = []
    private var repeatDeleteTimer: Timer?
    private var isSearchMode = false
    private var searchQuery = ""
    private var searchResults: [EmojiEntry] = []
    private static let recentKey = "lingxi_recent_emojis"

    private let emojis: [String] = [
        "😂", "🥹", "😭", "😍", "🥰", "😘", "😊", "😁", "🤣", "😅",
        "😎", "🤔", "🫠", "🫡", "🤭", "🫣", "😴", "🤯", "😱", "😡",
        "👍", "👎", "👏", "🙌", "🤝", "🙏", "💪", "✌️", "👌", "🫶",
        "❤️", "🩷", "💔", "🔥", "✨", "🎉", "💯", "🌟", "⚡️", "🍀",
        "☕️", "🧋", "🍺", "🎂", "🍜", "🍕", "🐱", "🐶", "🐼", "🚀",
    ]

    private let kaomojis: [String] = [
        "(≧▽≦)", "ヾ(≧▽≦*)o", "ヽ(✿ﾟ▽ﾟ)ノ", "(ﾉ´▽｀)ﾉ♪", "(つ´ω`)つ",
        "(づ￣ 3￣)づ", "(*^▽^*)", "(｡•̀ᴗ-)✧", "(๑•̀ㅂ•́)و✧", "✧*｡٩(ˊᗜˋ*)و✧*｡",
        "(╥﹏╥)", "(つД`)ノ", "(´；ω；`)", "(⊙_⊙)?", "(ー_ー)!!",
        "┐(´д`)┌", "(￣▽￣)ノ", "╮(￣▽￣)╭", "(╯°□°）╯︵ ┻━┻", "┬─┬ノ( º _ ºノ)",
        "ʕ•ᴥ•ʔ", "(=^･ω･^=)", "૮ ・ﻌ・ა", "(ง •_•)ง", "ε=ε=ε=┏(゜ロ゜;)┛",
    ]

    private let cnSymbols: [String] = [
        "，", "。", "？", "！", "、", "；", "：", "“", "”", "‘",
        "’", "（", "）", "【", "】", "《", "》", "「", "」", "『",
        "』", "……", "——", "·", "～", "￥", "％", "℃", "‰", "※",
        "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩",
        "★", "☆", "●", "○", "■", "□", "▲", "▼", "→", "←",
    ]

    private let enSymbols: [String] = [
        ",", ".", "?", "!", ":", ";", "'", "\"", "(", ")",
        "[", "]", "{", "}", "<", ">", "/", "\\", "|", "_",
        "-", "+", "=", "*", "^", "%", "$", "#", "@", "&",
        "~", "`", "±", "×", "÷", "≈", "≠", "≤", "≥", "∞",
        "√", "π", "α", "β", "γ", "Δ", "Σ", "Ω", "°", "•",
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadRecent()
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        repeatDeleteTimer?.invalidate()
    }

    private func setupViews() {
        searchBarBtn.setTitle("🔍 拼音 / 英文搜表情与符号（如 kaixin / jiantou）", for: .normal)
        searchBarBtn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .medium)
        searchBarBtn.titleLabel?.lineBreakMode = .byTruncatingHead
        searchBarBtn.contentHorizontalAlignment = .leading
        searchBarBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        searchBarBtn.layer.cornerRadius = 8
        searchBarBtn.actionHandler = { [weak self] in
            guard let self, !self.isSearchMode else { return }
            self.onRequestSearchMode?()
        }
        addSubview(searchBarBtn)

        exitSearchBtn.setTitle("返回", for: .normal)
        exitSearchBtn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        exitSearchBtn.layer.cornerRadius = 8
        exitSearchBtn.isHidden = true
        exitSearchBtn.actionHandler = { [weak self] in
            self?.onExitSearchMode?()
        }
        addSubview(exitSearchBtn)

        headerStack.axis = .horizontal
        headerStack.distribution = .fillEqually
        headerStack.spacing = 6
        addSubview(headerStack)

        scrollView.showsVerticalScrollIndicator = true
        addSubview(scrollView)
        scrollView.addSubview(gridContainer)

        emptySearchLabel.text = "未找到匹配表情，换个拼音或英文试试"
        emptySearchLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        emptySearchLabel.textAlignment = .center
        emptySearchLabel.isHidden = true
        scrollView.addSubview(emptySearchLabel)

        addSubview(footerView)
        backButton.setTitle("返回键盘", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        backButton.actionHandler = { [weak self] in self?.onClose?() }
        footerView.addSubview(backButton)

        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.accessibilityLabel = "删除"
        deleteButton.accessibilityHint = "点按删除一个字符，长按连续删除"
        deleteButton.actionHandler = { [weak self] in self?.onBackspace?() }
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleDeleteLongPress(_:)))
        lp.minimumPressDuration = 0.32
        deleteButton.addGestureRecognizer(lp)
        footerView.addSubview(deleteButton)
    }

    @objc private func handleDeleteLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            repeatDeleteTimer?.invalidate()
            onBackspace?()
            repeatDeleteTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in
                self?.onBackspace?()
            }
        case .ended, .cancelled, .failed:
            repeatDeleteTimer?.invalidate()
            repeatDeleteTimer = nil
        default:
            break
        }
    }

    func setSearchMode(_ enabled: Bool, query: String = "", resolvedChineseWords: [String] = []) {
        isSearchMode = enabled
        headerStack.isHidden = enabled
        footerView.isHidden = enabled
        exitSearchBtn.isHidden = !enabled
        scrollView.showsHorizontalScrollIndicator = enabled
        scrollView.showsVerticalScrollIndicator = !enabled
        updateSearchQuery(query, resolvedChineseWords: resolvedChineseWords)
    }

    func updateSearchQuery(_ query: String, resolvedChineseWords: [String] = []) {
        searchQuery = query
        if isSearchMode {
            let prompt = query.isEmpty ? "请点下方字母键搜表情/符号 (如 kaixin / chigua / jiantou)" : query
            searchBarBtn.setTitle("🔍 搜表情: \(prompt)", for: .normal)
            searchResults = EmojiCatalog.search(query, resolvedChineseWords: resolvedChineseWords, limit: 30)
        } else {
            searchBarBtn.setTitle("🔍 拼音 / 英文搜表情与符号（如 kaixin / jiantou）", for: .normal)
            searchResults = []
        }
        rebuildGrid()
        scrollView.setContentOffset(.zero, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 8
        let searchH: CGFloat = 28

        if isSearchMode {
            let exitW: CGFloat = 54
            exitSearchBtn.frame = CGRect(x: bounds.width - pad - exitW, y: 4, width: exitW, height: searchH)
            searchBarBtn.frame = CGRect(x: pad, y: 4, width: max(60, exitSearchBtn.frame.minX - pad - 6), height: searchH)
            let scrollY = searchBarBtn.frame.maxY + 4
            scrollView.frame = CGRect(x: 0, y: scrollY, width: bounds.width, height: max(36, bounds.height - scrollY - 2))
        } else {
            searchBarBtn.frame = CGRect(x: pad, y: 5, width: bounds.width - pad * 2, height: searchH)
            let headerH: CGFloat = 30
            let footerH: CGFloat = 36
            headerStack.frame = CGRect(x: pad, y: searchBarBtn.frame.maxY + 5, width: bounds.width - pad * 2, height: headerH)
            footerView.frame = CGRect(x: 0, y: bounds.height - footerH - 4, width: bounds.width, height: footerH)
            backButton.frame = CGRect(x: pad, y: 2, width: 100, height: footerH - 4)
            deleteButton.frame = CGRect(x: bounds.width - pad - 66, y: 2, width: 66, height: footerH - 4)

            let scrollY = headerStack.frame.maxY + 6
            scrollView.frame = CGRect(x: 0, y: scrollY, width: bounds.width, height: max(40, footerView.frame.minY - scrollY - 4))
        }
        layoutItems()
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.canvasTop.withAlphaComponent(0.95)
        searchBarBtn.backgroundColor = theme.keyFill.withAlphaComponent(0.92)
        searchBarBtn.setTitleColor(isSearchMode ? theme.candidateHighlight : theme.keyHintText, for: .normal)
        exitSearchBtn.backgroundColor = theme.specialKeyFill
        exitSearchBtn.setTitleColor(theme.keyText, for: .normal)
        emptySearchLabel.textColor = theme.keyHintText

        backButton.backgroundColor = theme.specialKeyFill
        backButton.setTitleColor(theme.keyText, for: .normal)
        backButton.layer.cornerRadius = theme.keyCornerRadius

        deleteButton.backgroundColor = theme.specialKeyFill
        deleteButton.tintColor = theme.keyText
        deleteButton.layer.cornerRadius = theme.keyCornerRadius

        rebuildHeader()
        rebuildGrid()
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
            btn.actionHandler = { [weak self] in
                self?.currentTab = tab
                self?.rebuildHeader()
                self?.rebuildGrid()
                self?.scrollView.setContentOffset(.zero, animated: false)
            }
            headerStack.addArrangedSubview(btn)
        }
    }

    private func rebuildGrid() {
        gridContainer.subviews.forEach { $0.removeFromSuperview() }
        guard let theme else { return }

        if isSearchMode {
            searchBarBtn.setTitleColor(searchQuery.isEmpty ? theme.keyHintText : theme.candidateHighlight, for: .normal)
            emptySearchLabel.isHidden = !searchResults.isEmpty
            for entry in searchResults {
                let btn = ActionClosureButton(type: .system)
                btn.setTitle(entry.symbol, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: entry.isSymbol ? 19 : 24, weight: .regular)
                btn.titleLabel?.adjustsFontSizeToFitWidth = true
                btn.titleLabel?.minimumScaleFactor = 0.7
                btn.setTitleColor(theme.keyText, for: .normal)
                btn.backgroundColor = theme.keyFill.withAlphaComponent(0.9)
                btn.layer.cornerRadius = 8
                let sym = entry.symbol
                let isEmoji = !entry.isSymbol
                btn.actionHandler = { [weak self] in
                    guard let self else { return }
                    if isEmoji {
                        self.recordRecentEmoji(sym)
                    }
                    self.onInsert?(sym)
                }
                gridContainer.addSubview(btn)
            }
            setNeedsLayout()
            return
        }

        emptySearchLabel.isHidden = true
        searchBarBtn.setTitleColor(theme.keyHintText, for: .normal)

        var items: [String] = []
        var seen = Set<String>()
        func appendUnique(_ list: [String]) {
            for item in list where seen.insert(item).inserted {
                items.append(item)
            }
        }

        switch currentTab {
        case .emoji:
            appendUnique(recentEmojis)
            appendUnique(emojis)
            appendUnique(EmojiCatalog.all.filter { !$0.isSymbol }.map(\.symbol))
        case .kaomoji:
            appendUnique(kaomojis)
        case .chineseSymbols:
            appendUnique(cnSymbols)
            appendUnique(EmojiCatalog.all.filter { $0.isSymbol && !$0.symbol.unicodeScalars.allSatisfy(\.isASCII) }.map(\.symbol))
        case .englishSymbols:
            appendUnique(enSymbols)
            appendUnique(EmojiCatalog.all.filter { $0.isSymbol && $0.symbol.unicodeScalars.allSatisfy(\.isASCII) }.map(\.symbol))
        }

        for item in items {
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(item, for: .normal)
            let isKaomoji = (currentTab == .kaomoji)
            btn.titleLabel?.font = .systemFont(ofSize: isKaomoji ? 13.5 : (currentTab == .emoji ? 24 : 18), weight: .regular)
            btn.titleLabel?.adjustsFontSizeToFitWidth = true
            btn.titleLabel?.minimumScaleFactor = 0.7
            btn.setTitleColor(theme.keyText, for: .normal)
            btn.backgroundColor = theme.keyFill.withAlphaComponent(0.8)
            btn.layer.cornerRadius = 8
            btn.actionHandler = { [weak self] in
                guard let self else { return }
                if self.currentTab == .emoji {
                    self.recordRecentEmoji(item)
                }
                self.onInsert?(item)
            }
            gridContainer.addSubview(btn)
        }
        setNeedsLayout()
    }

    private func layoutItems() {
        let pad: CGFloat = 8
        let gap: CGFloat = 6
        let usableW = max(100, bounds.width - pad * 2)

        if isSearchMode {
            emptySearchLabel.frame = scrollView.bounds
            let h = max(32, scrollView.bounds.height - 4)
            var x: CGFloat = pad
            for sub in gridContainer.subviews {
                let w: CGFloat = 42
                sub.frame = CGRect(x: x, y: 2, width: w, height: h)
                x += w + gap
            }
            let contentW = max(bounds.width, x + pad - gap)
            gridContainer.frame = CGRect(x: 0, y: 0, width: contentW, height: scrollView.bounds.height)
            scrollView.contentSize = gridContainer.frame.size
            return
        }

        if currentTab == .kaomoji {
            let cols = usableW > 380 ? 3 : 2
            let cellW = (usableW - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH: CGFloat = 38
            for (idx, sub) in gridContainer.subviews.enumerated() {
                let r = idx / cols
                let c = idx % cols
                sub.frame = CGRect(
                    x: pad + CGFloat(c) * (cellW + gap),
                    y: CGFloat(r) * (cellH + gap),
                    width: cellW,
                    height: cellH
                )
            }
            let rows = (gridContainer.subviews.count + cols - 1) / cols
            let h = CGFloat(rows) * (cellH + gap) + 6
            gridContainer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: h)
            scrollView.contentSize = gridContainer.frame.size
        } else {
            let cols = currentTab == .emoji ? 8 : 7
            let cellW = (usableW - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH: CGFloat = 38
            for (idx, sub) in gridContainer.subviews.enumerated() {
                let r = idx / cols
                let c = idx % cols
                sub.frame = CGRect(
                    x: pad + CGFloat(c) * (cellW + gap),
                    y: CGFloat(r) * (cellH + gap),
                    width: cellW,
                    height: cellH
                )
            }
            let rows = (gridContainer.subviews.count + cols - 1) / cols
            let h = CGFloat(rows) * (cellH + gap) + 6
            gridContainer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: h)
            scrollView.contentSize = gridContainer.frame.size
        }
    }

    private func loadRecent() {
        recentEmojis = RecentEmojiStore.load()
    }

    private func recordRecentEmoji(_ emoji: String) {
        RecentEmojiStore.record(emoji)
        recentEmojis = RecentEmojiStore.load()
    }
}
