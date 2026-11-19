import UIKit

/// 按键放大气泡与长按多选备选字符浮窗。
final class KeyPopupView: UIView {
    private let bubbleLayer = CAShapeLayer()
    private let singleLabel = UILabel()
    private let alternativesStack = UIStackView()

    private var alternativeLabels: [UILabel] = []
    private var alternatives: [String] = []
    private(set) var selectedAlternativeIndex: Int = 0
    private(set) var isShowingAlternatives: Bool = false

    private var hideWorkItem: DispatchWorkItem?
    private var theme: ResolvedTheme?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true

        bubbleLayer.shadowOffset = CGSize(width: 0, height: 3)
        bubbleLayer.shadowRadius = 7
        bubbleLayer.shadowOpacity = 0.25
        layer.addSublayer(bubbleLayer)

        singleLabel.textAlignment = .center
        singleLabel.font = .systemFont(ofSize: 26, weight: .regular)
        addSubview(singleLabel)

        alternativesStack.axis = .horizontal
        alternativesStack.alignment = .fill
        alternativesStack.distribution = .fillEqually
        alternativesStack.spacing = 4
        alternativesStack.isHidden = true
        addSubview(alternativesStack)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        bubbleLayer.fillColor = theme.keyFill.withAlphaComponent(0.98).cgColor
        bubbleLayer.shadowColor = theme.keyShadowColor.cgColor
        singleLabel.textColor = theme.keyText
        refreshAlternativeHighlights()
    }

    /// 显示单个按键上方放大气泡。
    func showSingle(text: String, anchorRect: CGRect, in hostBounds: CGRect) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        isShowingAlternatives = false
        alternatives = []
        alternativesStack.isHidden = true
        singleLabel.isHidden = false
        singleLabel.text = text

        let bubbleWidth = max(anchorRect.width + 16, 46)
        let bubbleHeight: CGFloat = 46
        let rawX = anchorRect.midX - bubbleWidth / 2
        let clampedX = min(max(4, rawX), max(4, hostBounds.width - bubbleWidth - 4))
        let y = max(-42, anchorRect.minY - bubbleHeight + 4)

        frame = CGRect(x: clampedX, y: y, width: bubbleWidth, height: bubbleHeight)
        singleLabel.frame = CGRect(x: 0, y: 2, width: bubbleWidth, height: bubbleHeight - 6)
        updateBubblePath(rect: bounds)
        isHidden = false
        alpha = 1.0
    }

    /// 显示长按备选字符选择器，并返回默认选中索引。
    func showAlternatives(_ items: [String], anchorRect: CGRect, in hostBounds: CGRect) {
        guard !items.isEmpty else { return }
        hideWorkItem?.cancel()
        hideWorkItem = nil
        isShowingAlternatives = true
        alternatives = items
        selectedAlternativeIndex = 0

        singleLabel.isHidden = true
        alternativesStack.isHidden = false
        alternativesStack.arrangedSubviews.forEach {
            alternativesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        alternativeLabels.removeAll()

        for item in items {
            let lbl = UILabel()
            lbl.text = item
            lbl.textAlignment = .center
            lbl.font = .systemFont(ofSize: 19, weight: .medium)
            lbl.layer.cornerRadius = 7
            lbl.layer.masksToBounds = true
            alternativesStack.addArrangedSubview(lbl)
            alternativeLabels.append(lbl)
        }

        let itemWidth: CGFloat = 35
        let paddingH: CGFloat = 8
        let totalWidth = min(hostBounds.width - 12, CGFloat(items.count) * itemWidth + paddingH * 2 + CGFloat(items.count - 1) * 4)
        let bubbleHeight: CGFloat = 44

        let preferredX = anchorRect.midX - totalWidth / 2
        let clampedX = min(max(6, preferredX), max(6, hostBounds.width - totalWidth - 6))
        let y = max(-42, anchorRect.minY - bubbleHeight + 2)

        frame = CGRect(x: clampedX, y: y, width: totalWidth, height: bubbleHeight)
        alternativesStack.frame = CGRect(x: paddingH, y: 4, width: totalWidth - paddingH * 2, height: bubbleHeight - 8)
        updateBubblePath(rect: bounds)
        refreshAlternativeHighlights()
        isHidden = false
        alpha = 1.0
    }

    /// 拖动手指实时更新长按选中项，索引发生变化时返回 true（用于触发轻震提示）。
    @discardableResult
    func updateSelection(atHostPoint point: CGPoint) -> Bool {
        guard isShowingAlternatives, !alternatives.isEmpty else { return false }
        let localX = point.x - frame.minX - alternativesStack.frame.minX
        let stackWidth = max(1, alternativesStack.frame.width)
        let ratio = min(max(0, localX / stackWidth), 0.9999)
        let nextIndex = Int(ratio * CGFloat(alternatives.count))
        guard nextIndex != selectedAlternativeIndex else { return false }
        selectedAlternativeIndex = nextIndex
        refreshAlternativeHighlights()
        return true
    }

    var selectedText: String? {
        guard isShowingAlternatives, alternatives.indices.contains(selectedAlternativeIndex) else {
            return nil
        }
        return alternatives[selectedAlternativeIndex]
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        isHidden = true
        alpha = 1.0
        isShowingAlternatives = false
        alternatives = []
    }

    /// 抬指后短暂停留 45ms 再隐去，使极速连打也能清晰感知按键视觉反馈。
    func scheduleHide(delay: TimeInterval = 0.045) {
        hideWorkItem?.cancel()
        isShowingAlternatives = false
        alternatives = []
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isHidden = true
            self.alpha = 1.0
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func updateBubblePath(rect: CGRect) {
        bubbleLayer.frame = rect
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 11)
        bubbleLayer.path = path.cgPath
    }

    private func refreshAlternativeHighlights() {
        guard let theme else { return }
        for (idx, lbl) in alternativeLabels.enumerated() {
            let selected = (idx == selectedAlternativeIndex)
            lbl.backgroundColor = selected ? theme.accentFill : .clear
            lbl.textColor = selected ? theme.accentText : theme.keyText
        }
    }
}
