import UIKit

/// T9 九宫格中文拼音画布：
/// - 左侧垂直音节筛选栏（输入数字时显示候选拼音音节如 ni / mi，空闲时为高频标点）
/// - 中央 3x4 九宫格按键（1 分词/标点、2-9 拼音数字键、底部 123 / 🌐 / 中英 / 空格）
/// - 右侧功能列（退格连删+左滑清屏、重输/标点、自适应高个发送键）
/// - 支持空格触控板滑移光标 & 左右单手模式
final class T9KeyboardCanvasView: UIView {
    enum Event {
        case digit(Character)
        case segmentSeparator
        case selectSyllable(String)
        case insertSymbol(String)
        case backspaceTap
        case backspaceRepeat
        case backspaceSwipeClear
        case clearComposing
        case spaceTap
        case cursorMove(steps: Int)
        case switchToNumberPad
        case nextKeyboard
        case toggleLanguage
        case returnKeyTap
        case sideRailToggleFull
        case sideRailSwapHand
        case sideRailClipboard
        case sideRailAI
    }

    var onEvent: ((Event) -> Void)?

    fileprivate struct T9KeyModel {
        enum Kind {
            case digit(Character, letters: String)
            case separatorOrPunct
            case mode123
            case globe
            case langToggle
            case space
            case backspace
            case clearOrComma
            case returnKey
        }
        let id: String
        let kind: Kind
        let rect: CGRect
        let isSpecial: Bool
        let isAccent: Bool
    }

    private var theme: ResolvedTheme?
    private var settings = LingxiSettings.load()
    private var isComposing = false
    private var needsGlobeKey = true
    private var returnTitle = "换行"
    private var returnHighlighted = false
    private var leftSyllables: [String] = []
    private var lockedSyllables: [String] = []

    private let gridHost = UIView()
    private let leftScroll = LingxiScrollView()
    private let leftStack = UIStackView()
    private let sideRailStack = UIStackView()
    private let popupView = KeyPopupView()

    private struct LayoutSignature: Equatable {
        let width: CGFloat
        let height: CGFloat
        let handedness: HandednessMode
        let needsGlobeKey: Bool
    }

    private struct LeftSignature: Equatable {
        let isComposing: Bool
        let leftSyllables: [String]
        let lockedSyllables: [String]
        let width: CGFloat
        let themeID: String
    }

    private var keyModels: [T9KeyModel] = []
    private var keyViews: [String: T9KeyCapView] = [:]
    private var lastLayoutSignature: LayoutSignature?
    private var lastLeftSignature: LeftSignature?

    private struct ActiveTouch {
        var keyID: String
        let startPoint: CGPoint
        let startTime: CFTimeInterval
        var longPressTriggered: Bool
        var trackpadActive: Bool
        var lastTrackpadX: CGFloat
        var backspaceSwipedLeft: Bool
    }

    private var activeTouches: [UITouch: ActiveTouch] = [:]
    private var longPressWorkItems: [UITouch: DispatchWorkItem] = [:]
    private var repeatDeleteTimer: Timer?
    private var repeatDeleteCount = 0

    private let idlePunctuations = ["，", "。", "？", "！", "、", "：", "；", "…", "～", "@"]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        addSubview(gridHost)

        leftScroll.showsVerticalScrollIndicator = false
        leftScroll.layer.cornerRadius = 8
        gridHost.addSubview(leftScroll)

        leftStack.axis = .vertical
        leftStack.spacing = 4
        leftStack.alignment = .fill
        leftScroll.addSubview(leftStack)

        sideRailStack.axis = .vertical
        sideRailStack.distribution = .fillEqually
        sideRailStack.spacing = 8
        sideRailStack.isHidden = true
        addSubview(sideRailStack)

        addSubview(popupView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        repeatDeleteTimer?.invalidate()
    }

    func configure(
        theme: ResolvedTheme,
        settings: LingxiSettings,
        isComposing: Bool,
        leftSyllables: [String],
        lockedSyllables: [String],
        needsGlobeKey: Bool,
        returnTitle: String,
        returnHighlighted: Bool
    ) {
        // 防闪烁：与 26 键画布对齐的视觉去重——refreshCanvas 随 refreshUI 高频触发，
        // 视觉字段未变化时跳过全量键帽重设，仅让左栏音节走 LeftSignature 去重
        let visualChanged =
            self.theme?.preset.id != theme.preset.id ||
            self.theme?.customization != theme.customization ||
            self.settings != settings ||
            self.isComposing != isComposing ||
            self.needsGlobeKey != needsGlobeKey ||
            self.returnTitle != returnTitle ||
            self.returnHighlighted != returnHighlighted
        self.theme = theme
        self.settings = settings
        self.isComposing = isComposing
        self.leftSyllables = leftSyllables
        self.lockedSyllables = lockedSyllables
        self.needsGlobeKey = needsGlobeKey
        self.returnTitle = returnTitle
        self.returnHighlighted = returnHighlighted

        if visualChanged || lastLayoutSignature == nil {
            popupView.apply(theme: theme)
            rebuildLayout(forceSync: true)
        } else {
            rebuildLayout(forceSync: false)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildLayout(forceSync: false)
    }

    // MARK: - 布局

    private func rebuildLayout(forceSync: Bool = true) {
        guard bounds.width > 60, bounds.height > 80 else { return }
        let totalW = bounds.width
        let totalH = bounds.height
        let isOneHanded = settings.handedness != .full && totalW >= 320
        let sig = LayoutSignature(
            width: totalW,
            height: totalH,
            handedness: settings.handedness,
            needsGlobeKey: needsGlobeKey
        )
        let pad: CGFloat = 5
        let gap: CGFloat = 5.5
        let railWidth: CGFloat = isOneHanded ? 46 : 0
        let hostW = totalW - (isOneHanded ? railWidth + 8 : 0)
        let leftColW = min(64, max(48, hostW * 0.165))

        let layoutChanged = (sig != lastLayoutSignature)
        if layoutChanged {
            lastLayoutSignature = sig
            let hostX: CGFloat
            let railX: CGFloat
            switch settings.handedness {
            case .full:
                hostX = 0
                railX = 0
            case .left:
                hostX = 0
                railX = hostW + 4
            case .right:
                hostX = railWidth + 8
                railX = 4
            }

            gridHost.frame = CGRect(x: hostX, y: 0, width: hostW, height: totalH)
            if isOneHanded {
                sideRailStack.isHidden = false
                sideRailStack.frame = CGRect(x: railX, y: 8, width: railWidth, height: totalH - 14)
                rebuildSideRail()
            } else {
                sideRailStack.isHidden = true
            }

            let rowH = (totalH - pad * 2 - gap * 3) / 4.0
            let rightColW = min(72, max(54, hostW * 0.185))
            leftScroll.frame = CGRect(x: pad, y: pad, width: leftColW, height: rowH * 3 + gap * 2)

            let centerX = pad + leftColW + gap
            let centerW = max(90, hostW - centerX - rightColW - gap - pad)
            let keyW = (centerW - gap * 2) / 3.0
            let rightX = centerX + centerW + gap

            var models: [T9KeyModel] = []
            let digits: [(Character, String)] = [
                ("1", "@ / ."), ("2", "ABC"), ("3", "DEF"),
                ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
                ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
            ]
            for (idx, item) in digits.enumerated() {
                let r = idx / 3
                let c = idx % 3
                let rect = CGRect(
                    x: centerX + CGFloat(c) * (keyW + gap),
                    y: pad + CGFloat(r) * (rowH + gap),
                    width: keyW,
                    height: rowH
                )
                if item.0 == "1" {
                    models.append(T9KeyModel(id: "t9_1", kind: .separatorOrPunct, rect: rect, isSpecial: false, isAccent: false))
                } else {
                    models.append(T9KeyModel(id: "t9_\(item.0)", kind: .digit(item.0, letters: item.1), rect: rect, isSpecial: false, isAccent: false))
                }
            }

            let r3Y = pad + (rowH + gap) * 3
            models.append(T9KeyModel(
                id: "t9_123",
                kind: .mode123,
                rect: CGRect(x: pad, y: r3Y, width: leftColW, height: rowH),
                isSpecial: true,
                isAccent: false
            ))

            var bx = centerX
            if needsGlobeKey {
                let gw = keyW * 0.65
                models.append(T9KeyModel(
                    id: "t9_globe",
                    kind: .globe,
                    rect: CGRect(x: bx, y: r3Y, width: gw, height: rowH),
                    isSpecial: true,
                    isAccent: false
                ))
                bx += gw + gap
            }

            let langW = keyW * 0.72
            models.append(T9KeyModel(
                id: "t9_lang",
                kind: .langToggle,
                rect: CGRect(x: bx, y: r3Y, width: langW, height: rowH),
                isSpecial: true,
                isAccent: false
            ))
            bx += langW + gap

            let spaceW = max(keyW, rightX - gap - bx)
            models.append(T9KeyModel(
                id: "t9_space",
                kind: .space,
                rect: CGRect(x: bx, y: r3Y, width: spaceW, height: rowH),
                isSpecial: false,
                isAccent: false
            ))

            models.append(T9KeyModel(
                id: "t9_bs",
                kind: .backspace,
                rect: CGRect(x: rightX, y: pad, width: rightColW, height: rowH),
                isSpecial: true,
                isAccent: false
            ))
            models.append(T9KeyModel(
                id: "t9_clear",
                kind: .clearOrComma,
                rect: CGRect(x: rightX, y: pad + rowH + gap, width: rightColW, height: rowH),
                isSpecial: true,
                isAccent: false
            ))
            models.append(T9KeyModel(
                id: "t9_return",
                kind: .returnKey,
                rect: CGRect(x: rightX, y: pad + (rowH + gap) * 2, width: rightColW, height: rowH * 2 + gap),
                isSpecial: true,
                isAccent: returnHighlighted
            ))

            self.keyModels = models
        } else if forceSync, let retIdx = keyModels.firstIndex(where: { $0.id == "t9_return" }) {
            let old = keyModels[retIdx]
            if old.isAccent != returnHighlighted {
                keyModels[retIdx] = T9KeyModel(
                    id: old.id,
                    kind: old.kind,
                    rect: old.rect,
                    isSpecial: old.isSpecial,
                    isAccent: returnHighlighted
                )
            }
        }

        let leftSig = LeftSignature(
            isComposing: isComposing,
            leftSyllables: leftSyllables,
            lockedSyllables: lockedSyllables,
            width: leftColW,
            themeID: theme?.preset.id ?? ""
        )
        if leftSig != lastLeftSignature {
            lastLeftSignature = leftSig
            rebuildLeftColumn(width: leftColW)
        }
        if forceSync || layoutChanged {
            syncKeyViews()
        }
    }

    private func rebuildLeftColumn(width: CGFloat) {
        leftStack.arrangedSubviews.forEach {
            leftStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }
        leftScroll.backgroundColor = theme.specialKeyFill.withAlphaComponent(0.65)

        if isComposing {
            let items = leftSyllables.isEmpty ? lockedSyllables : leftSyllables
            for syl in items {
                let btn = ActionClosureButton(type: .system)
                btn.setTitle(syl, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
                btn.setTitleColor(theme.candidateHighlight, for: .normal)
                btn.backgroundColor = theme.keyFill.withAlphaComponent(0.9)
                btn.layer.cornerRadius = 6
                btn.translatesAutoresizingMaskIntoConstraints = false
                btn.heightAnchor.constraint(equalToConstant: 33).isActive = true
                btn.actionHandler = { [weak self] in
                    self?.onEvent?(.selectSyllable(syl))
                }
                leftStack.addArrangedSubview(btn)
            }
        } else {
            for sym in idlePunctuations {
                let btn = ActionClosureButton(type: .system)
                btn.setTitle(sym, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
                btn.setTitleColor(theme.keyText, for: .normal)
                btn.backgroundColor = theme.keyFill.withAlphaComponent(0.72)
                btn.layer.cornerRadius = 6
                btn.translatesAutoresizingMaskIntoConstraints = false
                btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
                btn.actionHandler = { [weak self] in
                    self?.onEvent?(.insertSymbol(sym))
                }
                leftStack.addArrangedSubview(btn)
            }
        }

        let contentH = CGFloat(leftStack.arrangedSubviews.count) * 37
        leftStack.frame = CGRect(x: 3, y: 3, width: max(20, width - 6), height: contentH)
        leftScroll.contentSize = CGSize(width: width, height: contentH + 6)
    }

    private func rebuildSideRail() {
        sideRailStack.arrangedSubviews.forEach {
            sideRailStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }
        let swapIcon = settings.handedness == .left ? "arrow.right.to.line" : "arrow.left.to.line"
        let items: [(String, String, Event)] = [
            ("arrow.up.left.and.arrow.down.right", "切换全尺寸键盘", .sideRailToggleFull),
            (swapIcon, "切换左右手布局", .sideRailSwapHand),
            ("doc.on.clipboard", "剪贴板", .sideRailClipboard),
            ("sparkles", "AI 助手", .sideRailAI),
        ]
        let symCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        for (icon, label, event) in items {
            let btn = ActionClosureButton(type: .system)
            btn.setImage(UIImage(systemName: icon, withConfiguration: symCfg), for: .normal)
            btn.tintColor = theme.keyText
            btn.backgroundColor = theme.specialKeyFill
            btn.layer.cornerRadius = theme.keyCornerRadius
            btn.accessibilityLabel = label
            btn.actionHandler = { [weak self] in self?.onEvent?(event) }
            sideRailStack.addArrangedSubview(btn)
        }
    }

    private func syncKeyViews() {
        guard let theme else { return }
        let activeIDs = Set(keyModels.map(\.id))
        for (id, view) in keyViews where !activeIDs.contains(id) {
            view.removeFromSuperview()
            keyViews.removeValue(forKey: id)
        }
        for model in keyModels {
            let cap: T9KeyCapView
            if let existing = keyViews[model.id] {
                cap = existing
            } else {
                cap = T9KeyCapView()
                gridHost.addSubview(cap)
                keyViews[model.id] = cap
            }
            cap.frame = model.rect
            let pressed = activeTouches.values.contains { $0.keyID == model.id }
            cap.configure(
                kind: model.kind,
                isSpecial: model.isSpecial,
                isAccent: model.isAccent,
                theme: theme,
                isComposing: isComposing,
                returnTitle: returnTitle,
                isPressed: pressed
            )
        }
    }

    // MARK: - 触摸处理（防串手 + 空格触控板 + 退格左滑清屏）

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: gridHost)
            guard let model = nearestKey(at: pt) else { continue }
            flushPreviousDigits(excluding: touch)

            activeTouches[touch] = ActiveTouch(
                keyID: model.id,
                startPoint: pt,
                startTime: CACurrentMediaTime(),
                longPressTriggered: false,
                trackpadActive: false,
                lastTrackpadX: pt.x,
                backspaceSwipedLeft: false
            )
            keyViews[model.id]?.setPressed(true)

            if case .digit(let d, _) = model.kind, settings.keyPopupEnabled {
                let anchor = gridHost.convert(model.rect, to: self)
                popupView.showSingle(text: String(d), anchorRect: anchor, in: bounds)
            }
            scheduleLongPress(for: touch, model: model)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard var track = activeTouches[touch],
                  let model = keyModels.first(where: { $0.id == track.keyID }) else { continue }
            let pt = touch.location(in: gridHost)
            let dx = pt.x - track.startPoint.x

            switch model.kind {
            case .space:
                let trackpadTriggerX: CGFloat = isComposing ? 20 : 14
                if settings.spacebarTrackpadEnabled && (track.trackpadActive || abs(dx) >= trackpadTriggerX) {
                    if !track.trackpadActive {
                        track.trackpadActive = true
                        track.lastTrackpadX = pt.x
                        cancelLongPress(for: touch)
                    }
                    let delta = pt.x - track.lastTrackpadX
                    if abs(delta) >= 10 {
                        let steps = Int(delta / 10)
                        track.lastTrackpadX += CGFloat(steps) * 10
                        onEvent?(.cursorMove(steps: steps))
                    }
                    activeTouches[touch] = track
                }
            case .backspace:
                if dx <= -36 && !track.backspaceSwipedLeft {
                    track.backspaceSwipedLeft = true
                    cancelLongPress(for: touch)
                    stopRepeatDelete()
                    activeTouches[touch] = track
                    onEvent?(.backspaceSwipeClear)
                }
            default:
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { finishTouch(touch, commit: true) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { finishTouch(touch, commit: false) }
    }

    private func finishTouch(_ touch: UITouch, commit: Bool) {
        cancelLongPress(for: touch)
        guard let track = activeTouches.removeValue(forKey: touch) else { return }
        keyViews[track.keyID]?.setPressed(false)

        if let model = keyModels.first(where: { $0.id == track.keyID }) {
            if case .backspace = model.kind { stopRepeatDelete() }
            if commit { commitModel(model, track: track) }
        }
        if activeTouches.isEmpty {
            if commit {
                popupView.scheduleHide()
            } else {
                popupView.hide()
            }
        }
    }

    private func flushPreviousDigits(excluding newTouch: UITouch) {
        let toFlush = activeTouches
            .filter { $0.key != newTouch }
            .sorted { $0.value.startTime < $1.value.startTime }
        for (t, track) in toFlush {
            guard let model = keyModels.first(where: { $0.id == track.keyID }) else { continue }
            let shouldFlush: Bool
            switch model.kind {
            case .digit, .clearOrComma, .separatorOrPunct:
                shouldFlush = !track.longPressTriggered
            case .space:
                shouldFlush = !track.longPressTriggered && !track.trackpadActive
            default:
                shouldFlush = false
            }
            if shouldFlush {
                cancelLongPress(for: t)
                activeTouches.removeValue(forKey: t)
                keyViews[track.keyID]?.setPressed(false)
                commitModel(model, track: track)
            }
        }
    }

    private func commitModel(_ model: T9KeyModel, track: ActiveTouch) {
        switch model.kind {
        case .digit(let d, _):
            if track.longPressTriggered {
                onEvent?(.insertSymbol(String(d)))
            } else {
                onEvent?(.digit(d))
            }
        case .separatorOrPunct:
            if isComposing {
                onEvent?(.segmentSeparator)
            } else {
                onEvent?(.insertSymbol("@"))
            }
        case .mode123:
            onEvent?(.switchToNumberPad)
        case .globe:
            onEvent?(.nextKeyboard)
        case .langToggle:
            onEvent?(.toggleLanguage)
        case .space:
            if !track.trackpadActive { onEvent?(.spaceTap) }
        case .backspace:
            if !track.longPressTriggered && !track.backspaceSwipedLeft {
                onEvent?(.backspaceTap)
            }
        case .clearOrComma:
            if isComposing {
                onEvent?(.clearComposing)
            } else {
                onEvent?(.insertSymbol("，"))
            }
        case .returnKey:
            onEvent?(.returnKeyTap)
        }
    }

    private func scheduleLongPress(for touch: UITouch, model: T9KeyModel) {
        let delay: TimeInterval
        switch model.kind {
        case .backspace: delay = 0.34
        case .digit: delay = 0.42
        case .space:
            guard settings.spacebarTrackpadEnabled && !isComposing else { return }
            delay = 0.42
        default: return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, var track = self.activeTouches[touch], track.keyID == model.id else { return }
            track.longPressTriggered = true
            self.activeTouches[touch] = track
            switch model.kind {
            case .backspace:
                self.startRepeatDelete()
            case .space:
                track.trackpadActive = true
                self.activeTouches[touch] = track
                self.onEvent?(.cursorMove(steps: 0))
            default:
                break
            }
        }
        longPressWorkItems[touch] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelLongPress(for touch: UITouch) {
        longPressWorkItems.removeValue(forKey: touch)?.cancel()
    }

    private func startRepeatDelete() {
        stopRepeatDelete()
        repeatDeleteCount = 0
        onEvent?(.backspaceRepeat)
        // 与 26 键一致：Timer 注册到 .common mode，避免按住期间 tracking mode 下连删失效
        let timer = Timer(timeInterval: 0.085, repeats: true) { [weak self] timer in
            guard let self else { return }
            self.repeatDeleteCount += 1
            self.onEvent?(.backspaceRepeat)
            // 连删 12 次后提速到 0.05s/次
            if self.repeatDeleteCount == 12 {
                timer.invalidate()
                let fast = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                    self?.onEvent?(.backspaceRepeat)
                }
                RunLoop.main.add(fast, forMode: .common)
                self.repeatDeleteTimer = fast
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatDeleteTimer = timer
    }

    private func stopRepeatDelete() {
        repeatDeleteTimer?.invalidate()
        repeatDeleteTimer = nil
    }

    private func nearestKey(at point: CGPoint) -> T9KeyModel? {
        if let exact = keyModels.first(where: { $0.rect.contains(point) }) {
            return exact
        }
        var best: T9KeyModel?
        var bestDist = CGFloat.infinity
        for m in keyModels where m.rect.insetBy(dx: -8, dy: -8).contains(point) {
            let dx = point.x - m.rect.midX
            let dy = point.y - m.rect.midY
            let d = dx * dx + dy * dy
            if d < bestDist {
                bestDist = d
                best = m
            }
        }
        return best
    }
}

private final class T9KeyCapView: UIView {
    private let bgView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let iconView = UIImageView()

    private var theme: ResolvedTheme?
    private var isSpecial = false
    private var isAccent = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        bgView.layer.shadowOffset = CGSize(width: 0, height: 1)
        bgView.layer.shadowRadius = 0.6
        addSubview(bgView)

        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        addSubview(titleLabel)

        subtitleLabel.textAlignment = .center
        subtitleLabel.font = .systemFont(ofSize: 9.5, weight: .semibold)
        addSubview(subtitleLabel)

        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bgView.frame = bounds
        if let theme {
            bgView.layer.shadowPath = UIBezierPath(roundedRect: bgView.bounds, cornerRadius: theme.keyCornerRadius).cgPath
        }
        if subtitleLabel.isHidden {
            titleLabel.frame = bounds.insetBy(dx: 4, dy: 2)
        } else {
            titleLabel.frame = CGRect(x: 4, y: 4, width: bounds.width - 8, height: bounds.height * 0.56)
            subtitleLabel.frame = CGRect(x: 4, y: bounds.height * 0.56, width: bounds.width - 8, height: bounds.height * 0.36)
        }
        iconView.frame = bounds.insetBy(dx: max(10, bounds.width * 0.28), dy: max(10, bounds.height * 0.28))
    }

    func configure(
        kind: T9KeyboardCanvasView.T9KeyModel.Kind,
        isSpecial: Bool,
        isAccent: Bool,
        theme: ResolvedTheme,
        isComposing: Bool,
        returnTitle: String,
        isPressed: Bool
    ) {
        self.theme = theme
        self.isSpecial = isSpecial
        self.isAccent = isAccent

        bgView.layer.cornerCurve = .continuous
        bgView.layer.cornerRadius = theme.keyCornerRadius
        bgView.layer.shadowColor = theme.keyShadowColor.cgColor
        bgView.layer.shadowOpacity = theme.keyShadowOpacity
        bgView.layer.shadowOffset = CGSize(width: 0, height: 1)
        bgView.layer.borderWidth = 0.5
        bgView.layer.borderColor = theme.keyBorder.withAlphaComponent(theme.preset.isDark ? 0.24 : 0.32).cgColor

        iconView.isHidden = true
        titleLabel.isHidden = false
        subtitleLabel.isHidden = true

        switch kind {
        case .digit(let d, let letters):
            titleLabel.text = letters
            titleLabel.font = .systemFont(ofSize: 16.5, weight: theme.boldKeyLabel ? .bold : .medium)
            titleLabel.textColor = theme.keyText
            subtitleLabel.text = String(d)
            subtitleLabel.textColor = theme.keyHintText
            subtitleLabel.isHidden = false
        case .separatorOrPunct:
            titleLabel.text = isComposing ? "分词" : "@"
            titleLabel.font = .systemFont(ofSize: 15.5, weight: .semibold)
            titleLabel.textColor = theme.keyText
            subtitleLabel.text = isComposing ? "'" : "符号"
            subtitleLabel.textColor = theme.keyHintText
            subtitleLabel.isHidden = false
        case .mode123:
            titleLabel.text = "123"
            titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
            titleLabel.textColor = theme.keyText
        case .globe:
            titleLabel.isHidden = true
            iconView.isHidden = false
            iconView.image = UIImage(systemName: "globe")
            iconView.tintColor = theme.keyText
        case .langToggle:
            titleLabel.text = "中/英"
            titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
            titleLabel.textColor = theme.keyText
        case .space:
            titleLabel.text = "灵犀 · 九键"
            titleLabel.font = .systemFont(ofSize: 13.5, weight: .regular)
            titleLabel.textColor = theme.keyHintText
        case .backspace:
            titleLabel.isHidden = true
            iconView.isHidden = false
            iconView.image = UIImage(systemName: "delete.left")
            iconView.tintColor = theme.keyText
        case .clearOrComma:
            titleLabel.text = isComposing ? "重输" : "，。"
            titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            titleLabel.textColor = theme.keyText
        case .returnKey:
            titleLabel.text = returnTitle
            titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
            titleLabel.textColor = isAccent ? theme.accentText : theme.keyText
        }
        setPressed(isPressed)
        setNeedsLayout()
    }

    func setPressed(_ pressed: Bool) {
        guard let theme else { return }
        // 与 26 键画布一致：按下微移 +1pt 并收起阴影，形成统一的“压实”反馈
        bgView.transform = pressed ? CGAffineTransform(translationX: 0, y: 1) : .identity
        bgView.layer.shadowRadius = pressed ? 0 : 0.6
        if isAccent {
            bgView.backgroundColor = pressed ? theme.accentPressedFill : theme.accentFill
        } else if isSpecial {
            bgView.backgroundColor = pressed ? theme.specialKeyPressedFill : theme.specialKeyFill
        } else {
            bgView.backgroundColor = pressed ? theme.keyPressedFill : theme.keyFill
        }
    }
}
