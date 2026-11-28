import UIKit

/// 允许手指落在按钮/胶囊上时依然可以顺滑拖拽滚动的通用 ScrollView（解决 iOS 默认 UIControl 拦截滚动的痛点）。
final class LingxiScrollView: UIScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
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

/// 横向高速候选词滚动栏（支持长按词条进行置顶/忘词操作）。
final class CandidateBarView: UIView {
    var onSelectCandidate: ((Int) -> Void)?
    var onLongPressCandidate: ((Int, UIView) -> Void)?
    var onToggleExpand: (() -> Void)?
    var onDismissSuggestions: (() -> Void)?
    var onDismissKeyboard: (() -> Void)?

    private let scrollView = LingxiScrollView()
    private let stackView = UIStackView()
    // 防闪烁：使用 .custom 而非 .system——system 按钮在重复 setImage/setTitle 时会做系统淡入淡出动画
    private let expandButton = UIButton(type: .custom)
    /// 仅在空闲「联想预测」状态显示：点一下立刻关掉联想条，恢复顶部 AI / 译 / 语音 / 设置栏
    private let dismissSuggestionsButton = UIButton(type: .custom)
    /// 一键收起键盘按钮（在联想态或候选较少时常驻最右侧）
    private let dismissKeyboardButton = UIButton(type: .custom)
    private var buttonPool: [UIButton] = []
    private var longPressPool: [UILongPressGestureRecognizer] = []
    private var candidates: [PinyinCandidate] = []
    private var isIdlePredictionMode = false
    private var theme: ResolvedTheme?
    /// 候选词主字号（可由设置页调节，默认 16.5）
    private var candidateFontSize: CGFloat = 16.5
    /// 上次布局时实际生效的字号：开启拼音预览条且栏高较低时，会按可用高度自动收敛
    private var appliedFontSize: CGFloat = 16.5
    /// 上次布局时的可用高度，高度变化后需重算生效字号并重建按钮
    private var lastLayoutHeight: CGFloat = 0
    /// 防闪烁：上次应用的候选签名与展开状态，未变化时跳过整轮重建
    private var lastSignature = ""
    private var lastExpanded = false
    /// 防闪烁：每个按钮已应用的配置签名，未变化时跳过标题/背景/边框重设
    private var buttonAppliedKeys: [String] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        scrollView.addSubview(stackView)

        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        expandButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: config), for: .normal)
        expandButton.accessibilityLabel = "展开候选栏"
        expandButton.addTarget(self, action: #selector(handleExpandTap), for: .touchUpInside)
        addSubview(expandButton)

        let closeCfg = UIImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
        dismissSuggestionsButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: closeCfg), for: .normal)
        dismissSuggestionsButton.accessibilityLabel = "关闭联想"
        dismissSuggestionsButton.isHidden = true
        dismissSuggestionsButton.addTarget(self, action: #selector(handleDismissSuggestionsTap), for: .touchUpInside)
        addSubview(dismissSuggestionsButton)

        let kbCfg = UIImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
        dismissKeyboardButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: kbCfg), for: .normal)
        dismissKeyboardButton.accessibilityLabel = "收起键盘"
        dismissKeyboardButton.isHidden = true
        dismissKeyboardButton.addTarget(self, action: #selector(handleDismissKeyboardTap), for: .touchUpInside)
        addSubview(dismissKeyboardButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 10, bounds.height > 10 else { return }
        // 栏高变化（设置页调节或拼音预览条显隐）后，实际生效字号可能随之收敛/恢复，需重建按钮
        if abs(bounds.height - lastLayoutHeight) > 0.5 {
            lastLayoutHeight = bounds.height
            let size = effectiveFontSize()
            if abs(size - appliedFontSize) > 0.05 {
                appliedFontSize = size
                for i in buttonAppliedKeys.indices { buttonAppliedKeys[i] = "" }
                reloadButtons()
            }
        }
        var rightEdge = bounds.width - 2
        let btnW: CGFloat = 34
        if !dismissKeyboardButton.isHidden {
            dismissKeyboardButton.frame = CGRect(x: rightEdge - btnW, y: 0, width: btnW, height: bounds.height)
            rightEdge = dismissKeyboardButton.frame.minX
        }
        if !dismissSuggestionsButton.isHidden {
            dismissSuggestionsButton.frame = CGRect(x: rightEdge - btnW, y: 0, width: btnW, height: bounds.height)
            rightEdge = dismissSuggestionsButton.frame.minX
        }
        if !expandButton.isHidden {
            expandButton.frame = CGRect(x: rightEdge - btnW, y: 0, width: btnW, height: bounds.height)
            rightEdge = expandButton.frame.minX
        }
        scrollView.frame = CGRect(x: 0, y: 0, width: max(0, rightEdge - 2), height: bounds.height)
        let visibleButtons = stackView.arrangedSubviews.filter { !$0.isHidden }
        let measuredWidth = visibleButtons.reduce(CGFloat(0)) { acc, v in
            let w = v.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: scrollView.bounds.height)).width
            return acc + max(32, ceil(w))
        } + CGFloat(max(0, visibleButtons.count - 1)) * stackView.spacing
        let fitWidth = ceil(stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
        // 绝不把 UIStackView 的 frame 强行拉宽到 scrollView.bounds.width，防止少量候选词被横向扯散
        let targetWidth = max(measuredWidth, fitWidth)
        stackView.frame = CGRect(x: 6, y: 0, width: targetWidth, height: scrollView.bounds.height)
        scrollView.contentSize = CGSize(width: max(scrollView.bounds.width, stackView.frame.maxX + 10), height: scrollView.bounds.height)
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        expandButton.tintColor = theme.keyHintText
        dismissSuggestionsButton.tintColor = theme.keyHintText
        dismissKeyboardButton.tintColor = theme.keyHintText
        // 主题变化后强制所有按钮重新应用配色
        for i in buttonAppliedKeys.indices { buttonAppliedKeys[i] = "" }
        reloadButtons()
    }

    /// 实际生效字号：候选条可用高度容纳不下设置字号时自动收敛（下限 12）
    /// 典型场景：候选栏高度调到最低 44 且开启拼音预览条（占 16）时，候选条仅剩 28，22pt 字号会溢出到拼音条
    private func effectiveFontSize() -> CGFloat {
        let available = bounds.height - 10
        guard available > 0 else { return candidateFontSize }
        return min(candidateFontSize, max(12, floor((available / 1.2) * 2) / 2))
    }

    /// 应用新的候选字号：清空按钮配置缓存并重建，保证立即生效
    func applyCandidateFontSize(_ size: CGFloat) {
        guard abs(size - candidateFontSize) > 0.05 else { return }
        candidateFontSize = size
        appliedFontSize = effectiveFontSize()
        for i in buttonAppliedKeys.indices { buttonAppliedKeys[i] = "" }
        reloadButtons()
        setNeedsLayout()
    }

    func updateCandidates(_ newList: [PinyinCandidate], expanded: Bool, isIdlePredictionMode: Bool = false) {
        // 防闪烁：refreshUI 在打字链路中高频触发，候选与状态均未变化时整体跳过
        let signature = "\(isIdlePredictionMode)|" + newList.map { "\($0.word)\u{1}\($0.codeHint)\u{1}\($0.source)" }.joined(separator: "\u{2}")
        if signature == lastSignature && expanded == lastExpanded { return }
        lastSignature = signature
        lastExpanded = expanded
        self.candidates = newList
        self.isIdlePredictionMode = isIdlePredictionMode
        let iconName = expanded ? "chevron.up" : "chevron.down"
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        expandButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        expandButton.accessibilityLabel = expanded ? "收起候选栏" : "展开候选栏"
        if isIdlePredictionMode {
            // 联想预测状态：显示「× 关闭联想」+「⌨️⌄ 收起键盘」，随时恢复顶部 AI/译/语音栏或一键收键盘
            expandButton.isHidden = true
            dismissSuggestionsButton.isHidden = false
            dismissKeyboardButton.isHidden = false
        } else {
            dismissSuggestionsButton.isHidden = true
            let showExpand = newList.count > 4
            expandButton.isHidden = !showExpand
            dismissKeyboardButton.isHidden = showExpand
        }
        scrollView.setContentOffset(.zero, animated: false)
        reloadButtons()
        setNeedsLayout()
    }

    private func ensureButton(at idx: Int) -> (UIButton, UILongPressGestureRecognizer) {
        while buttonPool.count <= idx {
            // 防闪烁：使用 .custom 而非 .system——system 按钮在 setTitle/setAttributedTitle 时触发内置标题淡入淡出动画（UIView 层级，CATransaction 禁不掉），逐键刷新即闪烁；.custom 无此动画
            let btn = UIButton(type: .custom)
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
            btn.layer.cornerRadius = 8
            btn.setContentHuggingPriority(.required, for: .horizontal)
            btn.setContentCompressionResistancePriority(.required, for: .horizontal)
            btn.addTarget(self, action: #selector(handleCandidateTap(_:)), for: .touchUpInside)

            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            lp.minimumPressDuration = 0.42
            btn.addGestureRecognizer(lp)

            stackView.addArrangedSubview(btn)
            buttonPool.append(btn)
            longPressPool.append(lp)
            buttonAppliedKeys.append("")
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
        // 关闭隐式动画，避免边框/背景色渐变在 refreshUI 动画上下文中造成闪烁
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let visibleCount = min(candidates.count, 64)

        for idx in 0..<visibleCount {
            let cand = candidates[idx]
            let (btn, lp) = ensureButton(at: idx)
            btn.isHidden = false
            btn.tag = idx

            let isPrimary = (idx == 0 && cand.source != .prediction)
            let needsBolt = (cand.source == .smartHelper) && !Self.isPureEmojiOrSymbol(cand.word)
            let displayWord = cand.word.replacingOccurrences(of: "\n", with: " ")
            let prefixMark = needsBolt ? "⚡ " : ""
            let mainFont = UIFont.systemFont(ofSize: appliedFontSize, weight: isPrimary ? .semibold : .regular)
            // 轻盈中选态：首选 = 主题色文字 + 淡色底（iOS 原生候选栏观感），其余 = ink 文字
            let mainColor = isPrimary ? theme.candidateHighlight : theme.candidateText

            // 防闪烁：按钮配置未变化时跳过重设（重设标题/背景/边框会引起视觉抖动）
            let configKey = "\(isPrimary)|\(prefixMark)\(displayWord)|\(cand.codeHint)|\(appliedFontSize)"
            if buttonAppliedKeys[idx] == configKey {
                lp.isEnabled = (cand.source == .dictionary || cand.source == .userLearned)
                continue
            }
            buttonAppliedKeys[idx] = configKey

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
                ? theme.candidateHighlight.withAlphaComponent(0.13)
                : .clear
            // 对齐微信输入法 / iOS 原生极简通透候选栏：首选胶囊高亮，次选无繁琐方框干扰视线
            btn.layer.borderWidth = 0
            lp.isEnabled = (cand.source == .dictionary || cand.source == .userLearned)
        }

        for idx in visibleCount..<buttonPool.count {
            buttonPool[idx].isHidden = true
        }
    }

    @objc private func handleCandidateTap(_ sender: UIButton) {
        // 点选反馈由 KVC selectCandidate 统一承担（triggerKeyFeedback + triggerCursorTick + 音效），此处不再重复震动。
        onSelectCandidate?(sender.tag)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let view = gesture.view else { return }
        onLongPressCandidate?(view.tag, view)
    }

    @objc private func handleExpandTap() {
        onToggleExpand?()
    }

    @objc private func handleDismissSuggestionsTap() {
        onDismissSuggestions?()
    }

    @objc private func handleDismissKeyboardTap() {
        onDismissKeyboard?()
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
    /// 点击展开面板内的音节胶囊切换查看任意第 k 个音节的全部单字（nil 表示回到整句/综合候选）
    var onSelectSyllable: ((Int?) -> Void)?
    var onClose: (() -> Void)?

    private let filterControl = UISegmentedControl(items: Filter.allCases.map(\.title))
    private let syllableScroll = LingxiScrollView()
    private let syllableStack = UIStackView()
    private let toneControl = UISegmentedControl(items: MandarinTone.allCases.map(\.label))
    private let closeButton = ActionClosureButton(type: .system)
    private let scrollView = LingxiScrollView()
    private let gridContainer = UIView()
    private let emptyHintLabel = UILabel()
    private var gridButtonPool: [UIButton] = []
    private var allCandidates: [PinyinCandidate] = []
    private var currentSyllables: [String] = []
    private var activeSyllableIndex: Int?
    private var visibleIndices: [Int] = []
    private var currentFilter: Filter = .all
    private var currentTone: MandarinTone = .all
    private var theme: ResolvedTheme?
    /// 候选词主字号（与单行候选条联动，默认 16.5）
    private var candidateFontSize: CGFloat = 16.5
    /// 防闪烁：上次应用的候选签名，未变化时跳过重置筛选与全量重建
    private var lastSignature = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        filterControl.selectedSegmentIndex = 0
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        addSubview(filterControl)

        syllableScroll.showsHorizontalScrollIndicator = false
        syllableScroll.isHidden = true
        addSubview(syllableScroll)

        syllableStack.axis = .horizontal
        syllableStack.alignment = .center
        syllableStack.spacing = 6
        syllableScroll.addSubview(syllableStack)

        toneControl.selectedSegmentIndex = 0
        toneControl.isHidden = true
        toneControl.addTarget(self, action: #selector(toneChanged), for: .valueChanged)
        addSubview(toneControl)

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

        emptyHintLabel.text = "当前筛选条件下暂无候选"
        emptyHintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyHintLabel.textAlignment = .center
        emptyHintLabel.isHidden = true
        scrollView.addSubview(emptyHintLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 10, bounds.height > 10 else { return }
        let pad: CGFloat = 8
        let closeW: CGFloat = 52
        closeButton.frame = CGRect(x: bounds.width - pad - closeW, y: 6, width: closeW, height: 28)
        filterControl.frame = CGRect(x: pad, y: 6, width: max(120, closeButton.frame.minX - pad - 6), height: 28)

        var scrollY = filterControl.frame.maxY + 4
        let showSyllables = currentSyllables.count >= 2
        syllableScroll.isHidden = !showSyllables
        if showSyllables {
            let sylH: CGFloat = 28
            syllableScroll.frame = CGRect(x: 0, y: scrollY, width: bounds.width, height: sylH)
            let fitW = ceil(syllableStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
            syllableStack.frame = CGRect(x: pad, y: 1, width: fitW, height: sylH - 2)
            syllableScroll.contentSize = CGSize(width: max(bounds.width, fitW + pad * 2), height: sylH)
            scrollY = syllableScroll.frame.maxY + 4
        }

        let showTone = (currentFilter == .singleChar) || (activeSyllableIndex != nil)
        toneControl.isHidden = !showTone
        if showTone {
            toneControl.frame = CGRect(x: pad, y: scrollY, width: bounds.width - pad * 2, height: 26)
            scrollY = toneControl.frame.maxY + 4
        }
        scrollView.frame = CGRect(x: 0, y: scrollY, width: bounds.width, height: max(40, bounds.height - scrollY))
        emptyHintLabel.frame = CGRect(x: 16, y: 18, width: max(80, bounds.width - 32), height: 24)
        layoutButtons()
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.toolbarBg.withAlphaComponent(0.98)
        for seg in [filterControl, toneControl] {
            seg.selectedSegmentTintColor = theme.accentFill
            seg.backgroundColor = theme.specialKeyFill
            seg.setTitleTextAttributes([.foregroundColor: theme.accentText, .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .selected)
            seg.setTitleTextAttributes([.foregroundColor: theme.keyText, .font: UIFont.systemFont(ofSize: 12, weight: .medium)], for: .normal)
        }
        closeButton.backgroundColor = theme.specialKeyFill
        closeButton.setTitleColor(theme.keyText, for: .normal)
        emptyHintLabel.textColor = theme.keyHintText
        rebuildSyllablePills()
        rebuildButtons()
    }

    func update(
        candidates: [PinyinCandidate],
        syllables: [String] = [],
        activeSyllableIndex: Int? = nil
    ) {
        let sylKey = syllables.joined(separator: "'") + "#\(activeSyllableIndex ?? -1)"
        let signature = sylKey + "|" + candidates.map { "\($0.word)\u{1}\($0.codeHint)\u{1}\($0.source)" }.joined(separator: "\u{2}")
        if signature == lastSignature { return }
        lastSignature = signature
        self.allCandidates = candidates
        self.currentSyllables = syllables
        self.activeSyllableIndex = activeSyllableIndex
        if activeSyllableIndex != nil {
            currentFilter = .singleChar
            filterControl.selectedSegmentIndex = Filter.singleChar.rawValue
        } else {
            currentFilter = .all
            filterControl.selectedSegmentIndex = 0
        }
        currentTone = .all
        toneControl.selectedSegmentIndex = 0
        rebuildSyllablePills()
        rebuildButtons()
        setNeedsLayout()
        scrollView.setContentOffset(.zero, animated: false)
    }

    private func rebuildSyllablePills() {
        syllableStack.arrangedSubviews.forEach {
            syllableStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme, currentSyllables.count >= 2 else { return }

        let allBtn = ActionClosureButton(type: .custom)
        let isAllActive = (activeSyllableIndex == nil)
        allBtn.setTitle("整句/逐字", for: .normal)
        allBtn.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        allBtn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
        allBtn.layer.cornerRadius = 11
        allBtn.layer.cornerCurve = .continuous
        allBtn.backgroundColor = isAllActive ? theme.accentFill : theme.specialKeyFill
        allBtn.setTitleColor(isAllActive ? theme.accentText : theme.keyText, for: .normal)
        allBtn.actionHandler = { [weak self] in
            self?.onSelectSyllable?(nil)
        }
        syllableStack.addArrangedSubview(allBtn)

        for (idx, syl) in currentSyllables.enumerated() {
            let pill = ActionClosureButton(type: .custom)
            let isSelected = (activeSyllableIndex == idx)
            pill.setTitle("第\(idx + 1)字·\(syl)", for: .normal)
            pill.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
            pill.contentEdgeInsets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
            pill.layer.cornerRadius = 11
            pill.layer.cornerCurve = .continuous
            pill.backgroundColor = isSelected ? theme.accentFill : theme.specialKeyFill
            pill.setTitleColor(isSelected ? theme.accentText : theme.keyText, for: .normal)
            pill.actionHandler = { [weak self] in
                self?.onSelectSyllable?(idx)
            }
            syllableStack.addArrangedSubview(pill)
        }
    }

    @objc private func filterChanged() {
        currentFilter = Filter(rawValue: filterControl.selectedSegmentIndex) ?? .all
        if currentFilter != .singleChar {
            currentTone = .all
            toneControl.selectedSegmentIndex = 0
        }
        rebuildButtons()
        setNeedsLayout()
        scrollView.setContentOffset(.zero, animated: false)
    }

    @objc private func toneChanged() {
        currentTone = MandarinTone(rawValue: toneControl.selectedSegmentIndex) ?? .all
        rebuildButtons()
        scrollView.setContentOffset(.zero, animated: false)
    }

    /// 应用新的候选字号：网格按钮与行高随字号派生，立即重建
    func applyCandidateFontSize(_ size: CGFloat) {
        guard abs(size - candidateFontSize) > 0.05 else { return }
        candidateFontSize = size
        rebuildButtons()
        setNeedsLayout()
    }

    private func ensureGridButton(at idx: Int) -> UIButton {
        while gridButtonPool.count <= idx {
            let btn = UIButton(type: .custom)
            btn.titleLabel?.lineBreakMode = .byTruncatingTail
            btn.layer.cornerRadius = 8
            btn.layer.cornerCurve = .continuous
            btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            btn.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)

            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            lp.minimumPressDuration = 0.45
            btn.addGestureRecognizer(lp)
            gridContainer.addSubview(btn)
            gridButtonPool.append(btn)
        }
        return gridButtonPool[idx]
    }

    private func rebuildButtons() {
        // 复用按钮池并关闭隐式动画：即使展开 400+ 同音生僻单字或切换声调筛选，也能 0 分配毫秒级秒切
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let theme else { return }

        visibleIndices = allCandidates.indices.filter { idx in
            let w = allCandidates[idx].word
            switch currentFilter {
            case .all:
                return true
            case .singleChar:
                guard w.count == 1 else { return false }
                if currentTone == .all { return true }
                return PinyinToneClassifier.tone(for: w) == currentTone.rawValue
            case .phrases:
                return w.count >= 2
            }
        }
        emptyHintLabel.isHidden = !visibleIndices.isEmpty

        for (poolIdx, origIdx) in visibleIndices.enumerated() {
            let cand = allCandidates[origIdx]
            let btn = ensureGridButton(at: poolIdx)
            btn.isHidden = false
            btn.tag = origIdx
            let mainFont = UIFont.systemFont(ofSize: candidateFontSize + 0.5, weight: origIdx == 0 ? .semibold : .regular)
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
                btn.setTitle(nil, for: .normal)
                btn.setAttributedTitle(attr, for: .normal)
            } else {
                btn.setAttributedTitle(nil, for: .normal)
                btn.setTitle(cand.word, for: .normal)
                btn.titleLabel?.font = mainFont
                btn.setTitleColor(mainColor, for: .normal)
            }
            btn.backgroundColor = theme.keyFill.withAlphaComponent(0.78)
        }
        for idx in visibleIndices.count..<gridButtonPool.count {
            gridButtonPool[idx].isHidden = true
        }
        setNeedsLayout()
    }

    private func layoutButtons() {
        let padding: CGFloat = 8
        let spacing: CGFloat = 8
        let maxWidth = max(100, bounds.width - padding * 2)
        var x: CGFloat = padding
        var y: CGFloat = padding
        let rowHeight: CGFloat = candidateFontSize + 21.5

        for idx in 0..<min(visibleIndices.count, gridButtonPool.count) {
            let sub = gridButtonPool[idx]
            let intrinsic = sub.sizeThatFits(CGSize(width: maxWidth, height: rowHeight))
            let width = min(maxWidth, max(46, intrinsic.width))
            if x + width > bounds.width - padding && x > padding {
                x = padding
                y += rowHeight + spacing
            }
            sub.frame = CGRect(x: x, y: y, width: width, height: rowHeight)
            x += width + spacing
        }
        let totalHeight = visibleIndices.isEmpty ? scrollView.bounds.height : (y + rowHeight + padding)
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
