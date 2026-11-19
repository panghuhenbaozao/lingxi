import UIKit

/// 横向高速候选词滚动栏（支持长按词条进行置顶/忘词操作）。
final class CandidateBarView: UIView {
    var onSelectCandidate: ((Int) -> Void)?
    var onLongPressCandidate: ((Int, UIView) -> Void)?
    var onToggleExpand: (() -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let expandButton = UIButton(type: .system)
    private var buttonPool: [UIButton] = []
    private var longPressPool: [UILongPressGestureRecognizer] = []
    private var candidates: [PinyinCandidate] = []
    private var theme: ResolvedTheme?

    override init(frame: CGRect) {
        super.init(frame: frame)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delaysContentTouches = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        scrollView.addSubview(stackView)

        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        expandButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: config), for: .normal)
        expandButton.addTarget(self, action: #selector(handleExpandTap), for: .touchUpInside)
        addSubview(expandButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let expandWidth: CGFloat = 34
        expandButton.frame = CGRect(x: bounds.width - expandWidth - 2, y: 0, width: expandWidth, height: bounds.height)
        scrollView.frame = CGRect(x: 0, y: 0, width: max(0, bounds.width - expandWidth - 4), height: bounds.height)
        let targetWidth = max(scrollView.bounds.width, stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
        stackView.frame = CGRect(x: 6, y: 0, width: targetWidth, height: scrollView.bounds.height)
        scrollView.contentSize = CGSize(width: stackView.frame.maxX + 8, height: scrollView.bounds.height)
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        expandButton.tintColor = theme.keyHintText
        reloadButtons()
    }

    func updateCandidates(_ newList: [PinyinCandidate], expanded: Bool) {
        self.candidates = newList
        let iconName = expanded ? "chevron.up" : "chevron.down"
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        expandButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        expandButton.isHidden = newList.count <= 4
        scrollView.setContentOffset(.zero, animated: false)
        reloadButtons()
        setNeedsLayout()
    }

    private func ensureButton(at idx: Int) -> (UIButton, UILongPressGestureRecognizer) {
        while buttonPool.count <= idx {
            let btn = UIButton(type: .system)
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
            btn.layer.cornerRadius = 8
            btn.addTarget(self, action: #selector(handleCandidateTap(_:)), for: .touchUpInside)

            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            lp.minimumPressDuration = 0.42
            btn.addGestureRecognizer(lp)

            stackView.addArrangedSubview(btn)
            buttonPool.append(btn)
            longPressPool.append(lp)
        }
        return (buttonPool[idx], longPressPool[idx])
    }

    private static func isPureEmojiOrSymbol(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first else { return false }
        if text.hasPrefix("(") { return true }
        return first.properties.isEmojiPresentation ||
               (first.value >= 0x2190 && first.value <= 0x2BFF)
    }

    private func reloadButtons() {
        guard let theme else { return }
        let visibleCount = min(candidates.count, 24)

        for idx in 0..<visibleCount {
            let cand = candidates[idx]
            let (btn, lp) = ensureButton(at: idx)
            btn.isHidden = false
            btn.tag = idx

            let isPrimary = (idx == 0 && cand.source != .prediction)
            let needsBolt = (cand.source == .smartHelper) && !Self.isPureEmojiOrSymbol(cand.word)
            let displayWord = cand.word.replacingOccurrences(of: "\n", with: " ")
            let prefixMark = needsBolt ? "⚡ " : ""
            let mainFont = UIFont.systemFont(ofSize: 16.5, weight: isPrimary ? .semibold : .regular)
            let mainColor = isPrimary ? theme.candidateHighlight : theme.candidateText

            if !cand.codeHint.isEmpty {
                let attr = NSMutableAttributedString(
                    string: "\(prefixMark)\(displayWord)",
                    attributes: [.font: mainFont, .foregroundColor: mainColor]
                )
                attr.append(NSAttributedString(
                    string: " \(cand.codeHint)",
                    attributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                        .foregroundColor: theme.keyHintText,
                    ]
                ))
                btn.setTitle(nil, for: .normal)
                btn.setAttributedTitle(attr, for: .normal)
            } else {
                btn.setAttributedTitle(nil, for: .normal)
                btn.setTitle("\(prefixMark)\(displayWord)", for: .normal)
                btn.titleLabel?.font = mainFont
                btn.setTitleColor(mainColor, for: .normal)
            }
            btn.backgroundColor = isPrimary
                ? theme.candidateHighlight.withAlphaComponent(0.12)
                : .clear
            lp.isEnabled = (cand.source == .dictionary || cand.source == .userLearned)
        }

        for idx in visibleCount..<buttonPool.count {
            buttonPool[idx].isHidden = true
        }
    }

    @objc private func handleCandidateTap(_ sender: UIButton) {
        onSelectCandidate?(sender.tag)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let view = gesture.view else { return }
        onLongPressCandidate?(view.tag, view)
    }

    @objc private func handleExpandTap() {
        onToggleExpand?()
    }
}

/// 展开后的多行候选词网格面板（支持「全部 / 只看单字 / 只看词组」筛选，方便快速定位生僻单字）。
final class ExpandedCandidatesView: UIView {
    enum Filter: Int, CaseIterable {
        case all = 0
        case singleChar = 1
        case phrases = 2

        var title: String {
            switch self {
            case .all: return "全部"
            case .singleChar: return "只看单字"
            case .phrases: return "只看词组"
            }
        }
    }

    var onSelectCandidate: ((Int) -> Void)?
    var onLongPressCandidate: ((Int, UIView) -> Void)?
    var onClose: (() -> Void)?

    private let filterControl = UISegmentedControl(items: Filter.allCases.map(\.title))
    private let closeButton = ActionClosureButton(type: .system)
    private let scrollView = UIScrollView()
    private let gridContainer = UIView()
    private var allCandidates: [PinyinCandidate] = []
    private var visibleIndices: [Int] = []
    private var currentFilter: Filter = .all
    private var theme: ResolvedTheme?

    override init(frame: CGRect) {
        super.init(frame: frame)
        filterControl.selectedSegmentIndex = 0
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        addSubview(filterControl)

        closeButton.setTitle("收起", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        closeButton.layer.cornerRadius = 8
        closeButton.actionHandler = { [weak self] in
            self?.onClose?()
        }
        addSubview(closeButton)

        scrollView.showsVerticalScrollIndicator = true
        addSubview(scrollView)
        scrollView.addSubview(gridContainer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 8
        let closeW: CGFloat = 52
        closeButton.frame = CGRect(x: bounds.width - pad - closeW, y: 6, width: closeW, height: 28)
        filterControl.frame = CGRect(x: pad, y: 6, width: max(120, closeButton.frame.minX - pad - 6), height: 28)
        let scrollY = filterControl.frame.maxY + 4
        scrollView.frame = CGRect(x: 0, y: scrollY, width: bounds.width, height: max(40, bounds.height - scrollY))
        layoutButtons()
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.toolbarBg.withAlphaComponent(0.96)
        filterControl.selectedSegmentTintColor = theme.accentFill
        filterControl.backgroundColor = theme.specialKeyFill
        filterControl.setTitleTextAttributes([.foregroundColor: theme.accentText], for: .selected)
        filterControl.setTitleTextAttributes([.foregroundColor: theme.keyText], for: .normal)
        closeButton.backgroundColor = theme.specialKeyFill
        closeButton.setTitleColor(theme.keyText, for: .normal)
        rebuildButtons()
    }

    func update(candidates: [PinyinCandidate]) {
        self.allCandidates = candidates
        currentFilter = .all
        filterControl.selectedSegmentIndex = 0
        rebuildButtons()
        scrollView.setContentOffset(.zero, animated: false)
    }

    @objc private func filterChanged() {
        currentFilter = Filter(rawValue: filterControl.selectedSegmentIndex) ?? .all
        rebuildButtons()
        scrollView.setContentOffset(.zero, animated: false)
    }

    private func rebuildButtons() {
        gridContainer.subviews.forEach { $0.removeFromSuperview() }
        guard let theme else { return }

        visibleIndices = allCandidates.indices.filter { idx in
            let w = allCandidates[idx].word
            switch currentFilter {
            case .all: return true
            case .singleChar: return w.count == 1
            case .phrases: return w.count >= 2
            }
        }

        for origIdx in visibleIndices {
            let cand = allCandidates[origIdx]
            let btn = UIButton(type: .system)
            btn.tag = origIdx
            let mainFont = UIFont.systemFont(ofSize: 17, weight: origIdx == 0 ? .semibold : .regular)
            let mainColor = origIdx == 0 ? theme.candidateHighlight : theme.candidateText
            if !cand.codeHint.isEmpty {
                let attr = NSMutableAttributedString(
                    string: cand.word,
                    attributes: [.font: mainFont, .foregroundColor: mainColor]
                )
                attr.append(NSAttributedString(
                    string: " \(cand.codeHint)",
                    attributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                        .foregroundColor: theme.keyHintText,
                    ]
                ))
                btn.setAttributedTitle(attr, for: .normal)
            } else {
                btn.setTitle(cand.word, for: .normal)
                btn.titleLabel?.font = mainFont
                btn.setTitleColor(mainColor, for: .normal)
            }
            btn.titleLabel?.lineBreakMode = .byTruncatingTail
            btn.backgroundColor = theme.keyFill.withAlphaComponent(0.75)
            btn.layer.cornerRadius = 8
            btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            btn.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)

            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            lp.minimumPressDuration = 0.45
            btn.addGestureRecognizer(lp)
            gridContainer.addSubview(btn)
        }
        setNeedsLayout()
    }

    private func layoutButtons() {
        let padding: CGFloat = 8
        let spacing: CGFloat = 8
        let maxWidth = max(100, bounds.width - padding * 2)
        var x: CGFloat = padding
        var y: CGFloat = padding
        let rowHeight: CGFloat = 38

        for sub in gridContainer.subviews {
            let intrinsic = sub.sizeThatFits(CGSize(width: maxWidth, height: rowHeight))
            let width = min(maxWidth, max(48, intrinsic.width))
            if x + width > bounds.width - padding && x > padding {
                x = padding
                y += rowHeight + spacing
            }
            sub.frame = CGRect(x: x, y: y, width: width, height: rowHeight)
            x += width + spacing
        }
        let totalHeight = y + rowHeight + padding
        gridContainer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(scrollView.bounds.height, totalHeight))
        scrollView.contentSize = gridContainer.frame.size
    }

    @objc private func handleTap(_ sender: UIButton) {
        onSelectCandidate?(sender.tag)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let view = gesture.view else { return }
        onLongPressCandidate?(view.tag, view)
    }
}
