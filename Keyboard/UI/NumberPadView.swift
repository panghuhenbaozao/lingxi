import UIKit

/// 独立数字九宫格与快捷符号面板（支持四则运算算式直出）。
final class NumberPadView: UIView {
    enum Event {
        case insertText(String)
        case backspace
        case returnKey
        case backToLetters
        case space
    }

    var onEvent: ((Event) -> Void)?

    private let leftSymbolScroll = UIScrollView()
    private let leftSymbolStack = UIStackView()
    private let gridContainer = UIView()
    private var theme: ResolvedTheme?
    private var isChineseMode = true
    private var returnTitle = "换行"
    private var repeatTimer: Timer?

    private let chineseSideSymbols = ["，", "。", "？", "！", "：", "；", "、", "（", "）", "「", "」", "…", "—", "￥", "@", "#"]
    private let englishSideSymbols = [",", ".", "?", "!", ":", ";", "(", ")", "[", "]", "_", "$", "@", "#", "%", "&"]

    override init(frame: CGRect) {
        super.init(frame: frame)
        leftSymbolScroll.showsVerticalScrollIndicator = false
        addSubview(leftSymbolScroll)

        leftSymbolStack.axis = .vertical
        leftSymbolStack.spacing = 6
        leftSymbolStack.distribution = .fill
        leftSymbolScroll.addSubview(leftSymbolStack)

        addSubview(gridContainer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        repeatTimer?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutAll()
    }

    func configure(theme: ResolvedTheme, isChineseMode: Bool, returnTitle: String = "换行") {
        self.theme = theme
        self.isChineseMode = isChineseMode
        self.returnTitle = returnTitle
        rebuildButtons()
        setNeedsLayout()
    }

    private func rebuildButtons() {
        leftSymbolStack.arrangedSubviews.forEach {
            leftSymbolStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        gridContainer.subviews.forEach { $0.removeFromSuperview() }
        guard let theme else { return }

        let syms = isChineseMode ? chineseSideSymbols : englishSideSymbols
        for sym in syms {
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(sym, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
            btn.setTitleColor(theme.keyText, for: .normal)
            btn.backgroundColor = theme.specialKeyFill
            btn.layer.cornerRadius = theme.keyCornerRadius
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 36).isActive = true
            btn.actionHandler = { [weak self] in
                self?.onEvent?(.insertText(sym))
            }
            leftSymbolStack.addArrangedSubview(btn)
        }

        // 4行5列布局：[1 2 3 + ⌫], [4 5 6 - =], [7 8 9 * 空格], [返回 0 . / ⏎]
        let rows: [[(title: String, isSpecial: Bool, isAccent: Bool, event: Event)]] = [
            [("1", false, false, .insertText("1")), ("2", false, false, .insertText("2")), ("3", false, false, .insertText("3")),
             ("+", true, false, .insertText("+")), ("⌫", true, false, .backspace)],
            [("4", false, false, .insertText("4")), ("5", false, false, .insertText("5")), ("6", false, false, .insertText("6")),
             ("-", true, false, .insertText("-")), ("=", true, false, .insertText("="))],
            [("7", false, false, .insertText("7")), ("8", false, false, .insertText("8")), ("9", false, false, .insertText("9")),
             ("×", true, false, .insertText("*")), ("空格", true, false, .space)],
            [("返回", true, false, .backToLetters), ("0", false, false, .insertText("0")), (".", false, false, .insertText(".")),
             ("÷", true, false, .insertText("/")), (returnTitle, true, true, .returnKey)],
        ]

        for (rIdx, row) in rows.enumerated() {
            for (cIdx, item) in row.enumerated() {
                let btn = ActionClosureButton(type: .system)
                btn.tag = rIdx * 10 + cIdx
                btn.setTitle(item.title, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: item.isSpecial ? 15 : 21, weight: item.isSpecial ? .semibold : .regular)
                btn.setTitleColor(item.isAccent ? theme.accentText : theme.keyText, for: .normal)
                btn.backgroundColor = item.isAccent ? theme.accentFill : (item.isSpecial ? theme.specialKeyFill : theme.keyFill)
                btn.layer.cornerRadius = theme.keyCornerRadius
                btn.layer.shadowColor = theme.keyShadowColor.cgColor
                btn.layer.shadowOpacity = theme.keyShadowOpacity
                btn.layer.shadowOffset = CGSize(width: 0, height: 1)
                btn.layer.shadowRadius = 0.6
                btn.actionHandler = { [weak self] in
                    self?.onEvent?(item.event)
                }
                if case .backspace = item.event {
                    let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleBackspaceLongPress(_:)))
                    lp.minimumPressDuration = 0.32
                    btn.addGestureRecognizer(lp)
                }
                gridContainer.addSubview(btn)
            }
        }
    }

    @objc private func handleBackspaceLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            repeatTimer?.invalidate()
            onEvent?(.backspace)
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in
                self?.onEvent?(.backspace)
            }
        case .ended, .cancelled, .failed:
            repeatTimer?.invalidate()
            repeatTimer = nil
        default:
            break
        }
    }

    private func layoutAll() {
        let pad: CGFloat = 6
        let sideW: CGFloat = 54
        leftSymbolScroll.frame = CGRect(x: pad, y: pad, width: sideW, height: max(0, bounds.height - pad * 2))
        let sideContentH = CGFloat(leftSymbolStack.arrangedSubviews.count) * 42
        leftSymbolStack.frame = CGRect(x: 0, y: 0, width: sideW, height: sideContentH)
        leftSymbolScroll.contentSize = CGSize(width: sideW, height: sideContentH)

        let gridX = pad + sideW + 8
        let gridW = max(100, bounds.width - gridX - pad)
        let gridH = max(80, bounds.height - pad * 2)
        gridContainer.frame = CGRect(x: gridX, y: pad, width: gridW, height: gridH)

        let gap: CGFloat = 6
        let cellW = (gridW - gap * 4) / 5.0
        let cellH = (gridH - gap * 3) / 4.0

        for sub in gridContainer.subviews {
            let r = sub.tag / 10
            let c = sub.tag % 10
            sub.frame = CGRect(
                x: CGFloat(c) * (cellW + gap),
                y: CGFloat(r) * (cellH + gap),
                width: cellW,
                height: cellH
            )
        }
    }
}
