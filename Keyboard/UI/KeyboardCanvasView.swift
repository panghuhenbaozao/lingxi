import UIKit

/// 单个按键的几何与逻辑模型。
private struct KeyModel {
    enum Kind {
        case character(primary: String, secondary: String?, downPunct: String?, alternatives: [String])
        case shiftOrSegment
        case backspace
        case mode123
        case globe
        case langToggle
        case space
        case punctuation(primary: String, alternatives: [String])
        case returnKey
    }

    let id: String
    let kind: Kind
    let rect: CGRect
    let isSpecial: Bool
    let isAccent: Bool
}

enum ShiftState {
    case lowercase
    case shifted
    case capsLocked
}

/// 纯 UIKit 高性能键盘画布：
/// - 零延迟触摸反馈与多指快速连打抢先上屏（Rollover Commit）
/// - 上滑直接输入副字符（如 Q 上滑出 1）
/// - 长按多选气泡（划选 1-0 与标点）
/// - 空格键触控板滑动移光标
/// - 退格键长按加速删除 & 左滑整段清屏（带撤销）
/// - 左右单手模式侧边快捷条
final class KeyboardCanvasView: UIView {
    enum Event {
        case character(String)
        case segmentSeparator
        case shiftTap
        case shiftDoubleTap
        case backspaceTap
        case backspaceRepeat
        case backspaceSwipeClear
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
        case glideCompleted(touchPoints: [CGPoint], keyCenters: [Character: CGPoint], keyPitch: CGFloat)
    }

    var onEvent: ((Event) -> Void)?

    private var theme: ResolvedTheme?
    private var settings = LingxiSettings.load()
    private var isEnglishMode = false
    private var isComposing = false
    private var shiftState: ShiftState = .lowercase
    private var needsGlobeKey = true
    private var returnTitle = "换行"
    private var returnHighlighted = false
    private var validNextLetters: Set<Character> = []

    private struct LayoutSignature: Equatable {
        let width: CGFloat
        let height: CGFloat
        let handedness: HandednessMode
        let isEnglishMode: Bool
        let needsGlobeKey: Bool
        let shiftState: ShiftState
        let inputScheme: InputScheme
        let punctuationStyle: PunctuationStyle
        let showNumberRow: Bool
        let themeID: String
    }

    private var keys: [KeyModel] = []
    private var keyViews: [String: KeyCapView] = [:]
    private var lastLayoutSignature: LayoutSignature?
    private let keysContainer = UIView()
    private let glideTrailLayer = CAShapeLayer()
    private let popupView = KeyPopupView()

    // 单手模式侧边条
    private let sideRailStack = UIStackView()

    // 多指触摸跟踪
    private struct ActiveTouch {
        var keyID: String
        let startPoint: CGPoint
        let startTime: CFTimeInterval
        var longPressTriggered: Bool
        var flickedSecondary: Bool
        var flickedDown: Bool
        var trackpadActive: Bool
        var lastTrackpadX: CGFloat
        var backspaceSwipedLeft: Bool
        var glideActive: Bool
        var glidePoints: [CGPoint]
        var visitedLetterKeys: [String]
        var pathLength: CGFloat
    }

    private var activeTouches: [UITouch: ActiveTouch] = [:]
    private var longPressWorkItems: [UITouch: DispatchWorkItem] = [:]
    private var repeatDeleteTimer: Timer?
    private var repeatDeleteCount = 0
    private var lastShiftTapTime: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        addSubview(keysContainer)

        glideTrailLayer.fillColor = UIColor.clear.cgColor
        glideTrailLayer.lineWidth = 5.5
        glideTrailLayer.lineCap = .round
        glideTrailLayer.lineJoin = .round
        glideTrailLayer.zPosition = 999
        keysContainer.layer.addSublayer(glideTrailLayer)

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
        isEnglishMode: Bool,
        isComposing: Bool,
        shiftState: ShiftState,
        needsGlobeKey: Bool,
        returnTitle: String,
        returnHighlighted: Bool,
        validNextLetters: Set<Character> = []
    ) {
        let fullVisualChanged =
            self.theme?.preset.id != theme.preset.id ||
            self.theme?.customization != theme.customization ||
            self.settings != settings ||
            self.isEnglishMode != isEnglishMode ||
            self.shiftState != shiftState ||
            self.needsGlobeKey != needsGlobeKey
        let lightStateChanged =
            self.isComposing != isComposing ||
            self.returnTitle != returnTitle ||
            self.returnHighlighted != returnHighlighted

        self.theme = theme
        self.settings = settings
        self.isEnglishMode = isEnglishMode
        self.isComposing = isComposing
        self.shiftState = shiftState
        self.needsGlobeKey = needsGlobeKey
        self.returnTitle = returnTitle
        self.returnHighlighted = returnHighlighted
        self.validNextLetters = validNextLetters

        guard fullVisualChanged || lightStateChanged || lastLayoutSignature == nil else { return }

        // 极致性能热路径：打字过程中仅 isComposing / returnTitle 切换时，只局部刷新 Shift 与 Return 两颗键帽，
        // 避免每打一个字就重绘全部 30 颗键帽与重建 30 条阴影路径（提速 ~15x）！
        if !fullVisualChanged && lastLayoutSignature != nil {
            syncComposingDependentKeysOnly()
            return
        }

        glideTrailLayer.strokeColor = theme.candidateHighlight.withAlphaComponent(0.72).cgColor
        popupView.apply(theme: theme)
        rebuildLayout(forceSync: true)
    }

    private func syncComposingDependentKeysOnly() {
        guard let theme else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if let retIdx = keys.firstIndex(where: { $0.id == "k_return" }) {
            let old = keys[retIdx]
            if old.isAccent != returnHighlighted {
                keys[retIdx] = KeyModel(
                    id: old.id,
                    kind: old.kind,
                    rect: old.rect,
                    isSpecial: old.isSpecial,
                    isAccent: returnHighlighted
                )
            }
            let updatedRet = keys[retIdx]
            if let cap = keyViews[updatedRet.id] {
                let isPressed = activeTouches.values.contains { $0.keyID == updatedRet.id }
                cap.configure(
                    model: updatedRet,
                    theme: theme,
                    showHints: settings.showSecondaryHints,
                    showDownHints: settings.showDownwardHints && settings.swipeDownForPunctuation,
                    isEnglishMode: isEnglishMode,
                    isComposing: isComposing,
                    shiftState: shiftState,
                    scheme: settings.inputScheme,
                    returnTitle: returnTitle,
                    isPressed: isPressed
                )
            }
        }
        if let shiftModel = keys.first(where: { $0.id == "k_shift" }),
           let cap = keyViews[shiftModel.id] {
            let isPressed = activeTouches.values.contains { $0.keyID == shiftModel.id }
            cap.configure(
                model: shiftModel,
                theme: theme,
                showHints: settings.showSecondaryHints,
                showDownHints: settings.showDownwardHints && settings.swipeDownForPunctuation,
                isEnglishMode: isEnglishMode,
                isComposing: isComposing,
                shiftState: shiftState,
                scheme: settings.inputScheme,
                returnTitle: returnTitle,
                isPressed: isPressed
            )
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildLayout(forceSync: false)
    }

    // MARK: - 布局构建

    private func rebuildLayout(forceSync: Bool = true) {
        guard bounds.width > 40, bounds.height > 80 else { return }

        let totalW = bounds.width
        let totalH = bounds.height
        let isOneHanded = settings.handedness != .full && totalW >= 320
        let sig = LayoutSignature(
            width: totalW,
            height: totalH,
            handedness: settings.handedness,
            isEnglishMode: isEnglishMode,
            needsGlobeKey: needsGlobeKey,
            shiftState: shiftState,
            inputScheme: settings.inputScheme,
            punctuationStyle: settings.punctuationStyle,
            showNumberRow: settings.showNumberRow,
            themeID: theme?.preset.id ?? ""
        )

        let geometryChanged = (sig != lastLayoutSignature)
        if geometryChanged {
            lastLayoutSignature = sig
            let railWidth: CGFloat = isOneHanded ? 48 : 0
            let gridWidth = totalW - (isOneHanded ? railWidth + 8 : 0)

            let gridX: CGFloat
            let railX: CGFloat
            switch settings.handedness {
            case .full:
                gridX = 0
                railX = 0
            case .left:
                gridX = 0
                railX = gridWidth + 4
            case .right:
                gridX = railWidth + 8
                railX = 4
            }

            keysContainer.frame = CGRect(x: gridX, y: 0, width: gridWidth, height: totalH)
            if isOneHanded {
                sideRailStack.isHidden = false
                sideRailStack.frame = CGRect(x: railX, y: 8, width: railWidth, height: totalH - 14)
                rebuildSideRail()
            } else {
                sideRailStack.isHidden = true
            }

            keys = buildKeyModels(in: keysContainer.bounds.size)
            syncKeyViews()
        } else if forceSync {
            // 更新返回键高亮等可能独立变化的轻量状态
            if let retIdx = keys.firstIndex(where: { $0.id == "k_return" }) {
                let old = keys[retIdx]
                if old.isAccent != returnHighlighted {
                    keys[retIdx] = KeyModel(
                        id: old.id,
                        kind: old.kind,
                        rect: old.rect,
                        isSpecial: old.isSpecial,
                        isAccent: returnHighlighted
                    )
                }
            }
            syncKeyViews()
        }
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
            btn.actionHandler = { [weak self] in
                self?.onEvent?(event)
            }
            sideRailStack.addArrangedSubview(btn)
        }
    }

    private func buildKeyModels(in size: CGSize) -> [KeyModel] {
        var result: [KeyModel] = []
        let hPad: CGFloat = 4
        let vTop: CGFloat = 6
        let vBottom: CGFloat = 5
        let rowSpacing: CGFloat = 8
        let colSpacing: CGFloat = size.width < 340 ? 4 : 5.5

        let usableW = size.width - hPad * 2
        let hasNumRow = settings.showNumberRow
        let numRows: CGFloat = hasNumRow ? 5.0 : 4.0
        let effRowSpacing: CGFloat = hasNumRow ? 6.5 : rowSpacing
        let rowH = (size.height - vTop - vBottom - effRowSpacing * (numRows - 1)) / numRows
        let r1Unit = (usableW - colSpacing * 9) / 10.0

        var currentRowY = vTop
        if hasNumRow {
            let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
            for (idx, d) in digits.enumerated() {
                let x = hPad + CGFloat(idx) * (r1Unit + colSpacing)
                let rect = CGRect(x: x, y: currentRowY, width: r1Unit, height: rowH)
                result.append(KeyModel(
                    id: "k_num_\(d)",
                    kind: .character(primary: d, secondary: nil, downPunct: nil, alternatives: [d]),
                    rect: rect,
                    isSpecial: false,
                    isAccent: false
                ))
            }
            currentRowY += rowH + effRowSpacing
        }

        let uAlts = (!isEnglishMode && settings.inputScheme != .quanpin) ? ["U", "7", "u", "ü"] : ["7", "u", "ü"]
        let row1Keys: [(String, String, String, [String])] = [
            ("q", "1", "~", ["1", "q"]), ("w", "2", "!", ["2", "w"]), ("e", "3", "?", ["3", "e", "é"]),
            ("r", "4", "、", ["4", "r"]), ("t", "5", "：", ["5", "t"]), ("y", "6", "；", ["6", "y"]),
            ("u", "7", "“", uAlts), ("i", "8", "（", ["8", "i"]), ("o", "9", "）", ["9", "o"]),
            ("p", "0", "-", ["0", "p"]),
        ]
        let row2Keys: [(String, String?, String?, [String])] = [
            ("a", "@", "，", ["@", "a"]), ("s", "#", "。", ["#", "s"]), ("d", "$", "￥", ["$", "￥", "d"]),
            ("f", "%", "「", ["%", "f"]), ("g", "&", "」", ["&", "g"]), ("h", "*", "…", ["*", "h"]),
            ("j", "-", "—", ["-", "—", "j"]), ("k", "+", "=", ["+", "k"]), ("l", "/", "、", ["/", "、", "l"]),
        ]
        let vSecondary = (!isEnglishMode && settings.inputScheme != .quanpin) ? "V" : "；"
        let vAlts = (!isEnglishMode && settings.inputScheme != .quanpin) ? ["V", ";", "；", "v"] : [";", "；", "v"]
        let row3Keys: [(String, String?, String?, [String])] = [
            ("z", "（", "《", ["（", "(", "z"]), ("x", "）", "》", ["）", ")", "x"]),
            ("c", "：", "【", [":", "：", "c"]), ("v", vSecondary, "】", vAlts),
            ("b", "“", "”", ["“", "”", "\"", "b"]), ("n", "？", "？", ["?", "？", "n"]),
            ("m", "！", "！", ["!", "！", "m"]),
        ]

        // Row 1 (10 keys)
        for (idx, item) in row1Keys.enumerated() {
            let x = hPad + CGFloat(idx) * (r1Unit + colSpacing)
            let rect = CGRect(x: x, y: currentRowY, width: r1Unit, height: rowH)
            let char = displayedChar(item.0)
            let customUp = settings.customSwipeUpMap[item.0].flatMap { $0.isEmpty ? nil : $0 } ?? item.1
            let customDown = settings.customSwipeDownMap[item.0].flatMap { $0.isEmpty ? nil : $0 } ?? item.2
            result.append(KeyModel(
                id: "k_\(item.0)",
                kind: .character(primary: char, secondary: customUp, downPunct: customDown, alternatives: item.3),
                rect: rect,
                isSpecial: false,
                isAccent: false
            ))
        }

        // Row 2 (9 keys centered)
        let r2Y = currentRowY + rowH + effRowSpacing
        let r2RowW = r1Unit * 9 + colSpacing * 8
        let r2StartX = (size.width - r2RowW) / 2.0
        for (idx, item) in row2Keys.enumerated() {
            let x = r2StartX + CGFloat(idx) * (r1Unit + colSpacing)
            let rect = CGRect(x: x, y: r2Y, width: r1Unit, height: rowH)
            let char = displayedChar(item.0)
            let customUp = settings.customSwipeUpMap[item.0].flatMap { $0.isEmpty ? nil : $0 } ?? item.1
            let customDown = settings.customSwipeDownMap[item.0].flatMap { $0.isEmpty ? nil : $0 } ?? item.2
            result.append(KeyModel(
                id: "k_\(item.0)",
                kind: .character(primary: char, secondary: customUp, downPunct: customDown, alternatives: item.3),
                rect: rect,
                isSpecial: false,
                isAccent: false
            ))
        }

        // Row 3 (Shift/分词 + 7 letters + Backspace)
        let r3Y = r2Y + rowH + effRowSpacing
        let modW = max(r1Unit * 1.32, (usableW - r1Unit * 7 - colSpacing * 8) / 2.0)
        result.append(KeyModel(
            id: "k_shift",
            kind: .shiftOrSegment,
            rect: CGRect(x: hPad, y: r3Y, width: modW, height: rowH),
            isSpecial: true,
            isAccent: false
        ))

        let r3LettersW = r1Unit * 7 + colSpacing * 6
        let r3LettersX = (size.width - r3LettersW) / 2.0
        for (idx, item) in row3Keys.enumerated() {
            let x = r3LettersX + CGFloat(idx) * (r1Unit + colSpacing)
            let rect = CGRect(x: x, y: r3Y, width: r1Unit, height: rowH)
            let char = displayedChar(item.0)
            let customUp = settings.customSwipeUpMap[item.0].flatMap { $0.isEmpty ? nil : $0 } ?? item.1
            let customDown = settings.customSwipeDownMap[item.0].flatMap { $0.isEmpty ? nil : $0 } ?? item.2
            result.append(KeyModel(
                id: "k_\(item.0)",
                kind: .character(primary: char, secondary: customUp, downPunct: customDown, alternatives: item.3),
                rect: rect,
                isSpecial: false,
                isAccent: false
            ))
        }

        result.append(KeyModel(
            id: "k_backspace",
            kind: .backspace,
            rect: CGRect(x: size.width - hPad - modW, y: r3Y, width: modW, height: rowH),
            isSpecial: true,
            isAccent: false
        ))

        // Row 4 (123, [🌐], 中/英, 空格, 标点, Return)
        let r4Y = r3Y + rowH + effRowSpacing
        let k123W = r1Unit * 1.25
        let kGlobeW = needsGlobeKey ? r1Unit * 1.1 : 0
        let kLangW = r1Unit * 1.15
        let kPuncW = r1Unit * 1.15
        let kReturnW = r1Unit * 1.85

        var cursorX = hPad
        result.append(KeyModel(
            id: "k_123",
            kind: .mode123,
            rect: CGRect(x: cursorX, y: r4Y, width: k123W, height: rowH),
            isSpecial: true,
            isAccent: false
        ))
        cursorX += k123W + colSpacing

        if needsGlobeKey {
            result.append(KeyModel(
                id: "k_globe",
                kind: .globe,
                rect: CGRect(x: cursorX, y: r4Y, width: kGlobeW, height: rowH),
                isSpecial: true,
                isAccent: false
            ))
            cursorX += kGlobeW + colSpacing
        }

        result.append(KeyModel(
            id: "k_lang",
            kind: .langToggle,
            rect: CGRect(x: cursorX, y: r4Y, width: kLangW, height: rowH),
            isSpecial: true,
            isAccent: false
        ))
        cursorX += kLangW + colSpacing

        let fixedTailW = kPuncW + kReturnW + colSpacing * 2 + hPad
        let spaceW = max(r1Unit * 2.0, size.width - cursorX - fixedTailW)
        result.append(KeyModel(
            id: "k_space",
            kind: .space,
            rect: CGRect(x: cursorX, y: r4Y, width: spaceW, height: rowH),
            isSpecial: false,
            isAccent: false
        ))
        cursorX += spaceW + colSpacing

        let puncPrimary: String
        let puncAlts: [String]
        if isEnglishMode {
            puncPrimary = "."
            puncAlts = [".", ",", "?", "!", "'", ";"]
        } else if settings.inputScheme.usesSemicolonFinal {
            // 微软/搜狗/紫光双拼：分号键 `;` 一键直达韵母 ing，长按仍可划选常用标点
            puncPrimary = ";"
            puncAlts = [";", "，", "。", "？", "！", "、"]
        } else if settings.punctuationStyle == .halfwidth {
            puncPrimary = ","
            puncAlts = [",", ".", "?", "!", ";", ":"]
        } else {
            puncPrimary = "，"
            puncAlts = ["，", "。", "？", "！", "、", "；"]
        }
        result.append(KeyModel(
            id: "k_punc",
            kind: .punctuation(primary: puncPrimary, alternatives: puncAlts),
            rect: CGRect(x: cursorX, y: r4Y, width: kPuncW, height: rowH),
            isSpecial: false,
            isAccent: false
        ))
        cursorX += kPuncW + colSpacing

        result.append(KeyModel(
            id: "k_return",
            kind: .returnKey,
            rect: CGRect(x: cursorX, y: r4Y, width: size.width - hPad - cursorX, height: rowH),
            isSpecial: true,
            isAccent: returnHighlighted
        ))

        return result
    }

    private func displayedChar(_ lower: String) -> String {
        if isEnglishMode && shiftState != .lowercase {
            return lower.uppercased()
        }
        return lower
    }

    private func syncKeyViews() {
        guard let theme else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let activeIDs = Set(keys.map(\.id))
        for (id, view) in keyViews where !activeIDs.contains(id) {
            view.removeFromSuperview()
            keyViews.removeValue(forKey: id)
        }

        for model in keys {
            let cap: KeyCapView
            if let existing = keyViews[model.id] {
                cap = existing
            } else {
                cap = KeyCapView()
                keysContainer.addSubview(cap)
                keyViews[model.id] = cap
            }
            cap.frame = model.rect
            let isPressed = activeTouches.values.contains { $0.keyID == model.id }
            cap.configure(
                model: model,
                theme: theme,
                showHints: settings.showSecondaryHints,
                showDownHints: settings.showDownwardHints && settings.swipeDownForPunctuation,
                isEnglishMode: isEnglishMode,
                isComposing: isComposing,
                shiftState: shiftState,
                scheme: settings.inputScheme,
                returnTitle: returnTitle,
                isPressed: isPressed
            )
        }
    }

    // MARK: - 零延迟多指触摸与手势识别

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: keysContainer)
            guard let hitKey = nearestKey(at: pt) else { continue }

            // Rollover：如果有前一个尚未抬起的字符/标点/空格键，按下新键瞬间立即按 FIFO 顺序先提交前一个键
            flushPreviousCharacterTouches(excluding: touch)

            var initialVisited: [String] = []
            if case .character(let p, _, _, _) = hitKey.kind,
               p.count == 1,
               let c = p.lowercased().first,
               c >= "a" && c <= "z" {
                initialVisited = [String(c)]
                let dx = Double(pt.x - hitKey.rect.midX)
                let dy = Double(pt.y - hitKey.rect.midY)
                TouchOffsetCalibrator.shared.recordTouch(key: String(c), dx: dx, dy: dy)
            }

            let track = ActiveTouch(
                keyID: hitKey.id,
                startPoint: pt,
                startTime: CACurrentMediaTime(),
                longPressTriggered: false,
                flickedSecondary: false,
                flickedDown: false,
                trackpadActive: false,
                lastTrackpadX: pt.x,
                backspaceSwipedLeft: false,
                glideActive: false,
                glidePoints: [pt],
                visitedLetterKeys: initialVisited,
                pathLength: 0
            )
            activeTouches[touch] = track
            setKeyPressed(hitKey.id, pressed: true)
            showInitialPopupIfNeeded(for: hitKey)

            scheduleLongPress(for: touch, key: hitKey)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard var track = activeTouches[touch],
                  let key = keys.first(where: { $0.id == track.keyID }) else { continue }
            let pt = touch.location(in: keysContainer)
            let dx = pt.x - track.startPoint.x
            let dy = pt.y - track.startPoint.y

            switch key.kind {
            case .space:
                let trackpadTriggerX: CGFloat = isComposing ? 18 : 10
                if settings.spacebarTrackpadEnabled && (track.trackpadActive || abs(dx) >= trackpadTriggerX) {
                    if !track.trackpadActive {
                        track.trackpadActive = true
                        track.lastTrackpadX = pt.x
                        cancelLongPress(for: touch)
                        KeyboardVibrator.shared.softTap()
                    }
                    let delta = pt.x - track.lastTrackpadX
                    let stepWidth: CGFloat = 10
                    if abs(delta) >= stepWidth {
                        let steps = Int(delta / stepWidth)
                        track.lastTrackpadX += CGFloat(steps) * stepWidth
                        // 每步敲击由 KVC cursorMove 的 triggerCursorTick + triggerCursorSound 承担，不再重复 spaceTick。
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
            case .character(_, let secondary, let downPunct, _):
                if track.longPressTriggered && popupView.isShowingAlternatives {
                    let hostPt = touch.location(in: self)
                    if popupView.updateSelection(atHostPoint: hostPt) {
                        KeyboardVibrator.shared.softTap()
                    }
                    break
                }

                // 上划/下滑快捷输入（flick）优先于滑行激活判定：垂直快速滑动先落定 flick，
                // 否则从字母键垂直滑动扫过相邻键时会被抢先判为滑行，导致角落字符打不出来
                if settings.swipeUpForHint, let sec = secondary, dy <= -20, abs(dy) > abs(dx) * 0.75 {
                    if !track.flickedSecondary {
                        track.flickedSecondary = true
                        track.flickedDown = false
                        cancelLongPress(for: touch)
                        activeTouches[touch] = track
                        let anchorInHost = keysContainer.convert(key.rect, to: self)
                        popupView.showSingle(text: sec, anchorRect: anchorInHost, in: bounds)
                    }
                } else if settings.swipeDownForPunctuation, let down = downPunct, dy >= 20, abs(dy) > abs(dx) * 0.75 {
                    if !track.flickedDown {
                        track.flickedDown = true
                        track.flickedSecondary = false
                        cancelLongPress(for: touch)
                        activeTouches[touch] = track
                        let anchorInHost = keysContainer.convert(key.rect, to: self)
                        popupView.showSingle(text: down, anchorRect: anchorInHost, in: bounds)
                    }
                }

                // 记录滑行轨迹并检测是否已跨越至少 2 个不同字母键（启用滑行输入时）
                let canGlide = settings.glideTypingEnabled && (isEnglishMode || settings.inputScheme == .quanpin)
                if canGlide && !track.visitedLetterKeys.isEmpty {
                    if let lastPt = track.glidePoints.last {
                        let stepD = hypot(pt.x - lastPt.x, pt.y - lastPt.y)
                        if stepD >= 3.0 {
                            track.pathLength += stepD
                            track.glidePoints.append(pt)
                        }
                    }
                    if let hovered = nearestKey(at: pt),
                       case .character(let hp, _, _, _) = hovered.kind,
                       hp.count == 1,
                       let hc = hp.lowercased().first,
                       hc >= "a" && hc <= "z" {
                        let hs = String(hc)
                        if track.visitedLetterKeys.last != hs {
                            track.visitedLetterKeys.append(hs)
                        }
                    }
                    let isShortVerticalFlick = (track.flickedSecondary || track.flickedDown)
                        && track.visitedLetterKeys.count <= 2
                        && track.pathLength < 72
                        && abs(dy) > abs(dx) * 1.5
                    let elapsed = CACurrentMediaTime() - track.startTime
                    if !track.glideActive && !isShortVerticalFlick && elapsed >= 0.09 && track.visitedLetterKeys.count >= 2 && track.pathLength >= 52 {
                        track.glideActive = true
                        track.flickedSecondary = false
                        track.flickedDown = false
                        cancelLongPress(for: touch)
                        popupView.hide()
                    }
                    if track.glideActive {
                        updateGlideTrail(with: track.glidePoints)
                        activeTouches[touch] = track
                        break
                    }
                    activeTouches[touch] = track
                }

            case .punctuation:
                if track.longPressTriggered && popupView.isShowingAlternatives {
                    let hostPt = touch.location(in: self)
                    if popupView.updateSelection(atHostPoint: hostPt) {
                        KeyboardVibrator.shared.softTap()
                    }
                }

            default:
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            finishTouch(touch, commit: true)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            finishTouch(touch, commit: false)
        }
    }

    private func finishTouch(_ touch: UITouch, commit: Bool) {
        cancelLongPress(for: touch)
        guard var track = activeTouches.removeValue(forKey: touch) else { return }
        setKeyPressed(track.keyID, pressed: false)

        if track.glideActive {
            fadeOutGlideTrail()
            if commit && track.visitedLetterKeys.count >= 2 {
                let (centers, pitch) = letterKeyCentersAndPitch()
                onEvent?(.glideCompleted(touchPoints: track.glidePoints, keyCenters: centers, keyPitch: pitch))
            }
            if activeTouches.isEmpty {
                popupView.hide()
            }
            return
        }

        if let key = keys.first(where: { $0.id == track.keyID }) {
            if case .backspace = key.kind {
                stopRepeatDelete()
            }
            if commit && !track.longPressTriggered && !track.flickedSecondary && !track.flickedDown {
                let pt = touch.location(in: keysContainer)
                let dx = pt.x - track.startPoint.x
                let dy = pt.y - track.startPoint.y
                if case .character(_, let secondary, let downPunct, _) = key.kind,
                   abs(dy) > abs(dx) * 0.75 {
                    if settings.swipeUpForHint && secondary != nil && dy <= -20 {
                        track.flickedSecondary = true
                    } else if settings.swipeDownForPunctuation && downPunct != nil && dy >= 20 {
                        track.flickedDown = true
                    }
                }
            }
            if commit {
                commitKey(key, track: track)
            }
        }
        if activeTouches.isEmpty {
            if !commit || popupView.isShowingAlternatives {
                popupView.hide()
            } else {
                popupView.scheduleHide()
            }
        }
    }

    private func flushPreviousCharacterTouches(excluding newTouch: UITouch) {
        // 按按下时间戳严格 FIFO 顺序抢先提交，覆盖字母、标点与非触控板态空格：
        // 彻底杜绝双手快速连打「空格 → 发送」「。 → 发送」「字母 → 空格 → 发送」时后键先触发导致吞字或漏标点。
        let toFlush = activeTouches
            .filter { $0.key != newTouch }
            .sorted { $0.value.startTime < $1.value.startTime }
        for (existingTouch, track) in toFlush {
            guard let key = keys.first(where: { $0.id == track.keyID }) else { continue }
            let shouldFlush: Bool
            switch key.kind {
            case .character:
                shouldFlush = !track.longPressTriggered && !track.glideActive
            case .punctuation:
                shouldFlush = !track.longPressTriggered
            case .space:
                shouldFlush = !track.longPressTriggered && !track.trackpadActive
            default:
                shouldFlush = false
            }
            if shouldFlush {
                cancelLongPress(for: existingTouch)
                activeTouches.removeValue(forKey: existingTouch)
                setKeyPressed(track.keyID, pressed: false)
                commitKey(key, track: track)
            }
        }
    }

    private func commitKey(_ key: KeyModel, track: ActiveTouch) {
        switch key.kind {
        case .character(let primary, let secondary, let downPunct, _):
            // 提交反馈由 KVC 事件回调的 triggerKeyFeedback 统一承担（含音效与强度映射），
            // 此处不再重复触发 mediumTap，避免同刻双震粘连。
            if track.longPressTriggered, let picked = popupView.selectedText {
                onEvent?(.character(picked))
            } else if track.flickedSecondary, let sec = secondary {
                onEvent?(.character(sec))
            } else if track.flickedDown, let down = downPunct {
                onEvent?(.character(down))
            } else {
                onEvent?(.character(primary))
            }
        case .punctuation(let primary, _):
            if track.longPressTriggered, let picked = popupView.selectedText {
                onEvent?(.character(picked))
            } else {
                onEvent?(.character(primary))
            }
        case .shiftOrSegment:
            if !isEnglishMode && isComposing {
                onEvent?(.segmentSeparator)
            } else {
                let now = CACurrentMediaTime()
                if now - lastShiftTapTime < 0.35 {
                    lastShiftTapTime = 0
                    onEvent?(.shiftDoubleTap)
                } else {
                    lastShiftTapTime = now
                    onEvent?(.shiftTap)
                }
            }
        case .backspace:
            if !track.longPressTriggered && !track.backspaceSwipedLeft {
                onEvent?(.backspaceTap)
            }
        case .mode123:
            onEvent?(.switchToNumberPad)
        case .globe:
            onEvent?(.nextKeyboard)
        case .langToggle:
            onEvent?(.toggleLanguage)
        case .space:
            if !track.trackpadActive {
                onEvent?(.spaceTap)
            }
        case .returnKey:
            onEvent?(.returnKeyTap)
        }
    }

    // MARK: - 长按与连续删词

    private func scheduleLongPress(for touch: UITouch, key: KeyModel) {
        let delay: TimeInterval
        switch key.kind {
        case .backspace:
            delay = 0.30
        case .character(_, _, _, let alts) where !alts.isEmpty:
            delay = 0.32
        case .punctuation(_, let alts) where !alts.isEmpty:
            delay = 0.30
        case .space:
            // 正在组词选候选期间禁用长按空格触发触控板，防止手指在空格稍停顿超过 0.22s 就把上屏空格吞掉
            guard settings.spacebarTrackpadEnabled && !isComposing else { return }
            delay = 0.42
        default:
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, var track = self.activeTouches[touch], track.keyID == key.id else { return }
            track.longPressTriggered = true
            self.activeTouches[touch] = track

            switch key.kind {
            case .backspace:
                self.startRepeatDelete()
                KeyboardVibrator.shared.heavyTap()
            case .character(_, _, _, let alts):
                let anchor = self.keysContainer.convert(key.rect, to: self)
                self.popupView.showAlternatives(alts, anchorRect: anchor, in: self.bounds)
            case .punctuation(_, let alts):
                let anchor = self.keysContainer.convert(key.rect, to: self)
                self.popupView.showAlternatives(alts, anchorRect: anchor, in: self.bounds)
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
        // 必须注册到 .common mode：手指按住期间 runloop 处于 tracking mode，
        // scheduledTimer 默认只在 default mode 触发，会导致长按只能删一下
        let timer = Timer(timeInterval: 0.085, repeats: true) { [weak self] timer in
            guard let self else { return }
            self.repeatDeleteCount += 1
            self.onEvent?(.backspaceRepeat)
            // 连删 12 次后提速到 0.05s/次，对齐 iOS 系统键盘连删加速手感
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

    private func showInitialPopupIfNeeded(for key: KeyModel) {
        guard settings.keyPopupEnabled else { return }
        switch key.kind {
        case .character(let primary, _, _, _), .punctuation(let primary, _):
            let anchor = keysContainer.convert(key.rect, to: self)
            popupView.showSingle(text: primary, anchorRect: anchor, in: bounds)
        default:
            break
        }
    }

    private func setKeyPressed(_ keyID: String, pressed: Bool) {
        keyViews[keyID]?.setPressed(pressed)
    }

    private func updateGlideTrail(with points: [CGPoint]) {
        guard points.count >= 2 else { return }
        let path = UIBezierPath()
        path.move(to: points[0])
        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            for i in 1..<(points.count - 1) {
                let mid = CGPoint(x: (points[i].x + points[i + 1].x) * 0.5, y: (points[i].y + points[i + 1].y) * 0.5)
                path.addQuadCurve(to: mid, controlPoint: points[i])
            }
            if let last = points.last {
                path.addLine(to: last)
            }
        }
        glideTrailLayer.removeAllAnimations()
        glideTrailLayer.opacity = 1.0
        glideTrailLayer.path = path.cgPath
    }

    private func fadeOutGlideTrail() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.0
        anim.duration = 0.18
        glideTrailLayer.opacity = 0.0
        glideTrailLayer.add(anim, forKey: "fadeGlide")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) { [weak self] in
            if self?.glideTrailLayer.opacity == 0.0 {
                self?.glideTrailLayer.path = nil
            }
        }
    }

    private func letterKeyCentersAndPitch() -> ([Character: CGPoint], CGFloat) {
        var centers: [Character: CGPoint] = [:]
        var qCenter: CGPoint?
        var wCenter: CGPoint?
        for key in keys {
            if case .character(let primary, _, _, _) = key.kind,
               primary.count == 1,
               let ch = primary.lowercased().first,
               ch >= "a" && ch <= "z" {
                let mid = CGPoint(x: key.rect.midX, y: key.rect.midY)
                centers[ch] = mid
                if ch == "q" { qCenter = mid }
                if ch == "w" { wCenter = mid }
            }
        }
        let pitch: CGFloat
        if let q = qCenter, let w = wCenter, w.x > q.x {
            pitch = w.x - q.x
        } else {
            pitch = max(28, keysContainer.bounds.width / 10.0)
        }
        return (centers, pitch)
    }

    private func nearestKey(at point: CGPoint) -> KeyModel? {
        // 1. 若落点位于按键核心内圈（留出 1.5pt 键缝缓冲），直接命中该键
        if let coreHit = keys.first(where: { $0.rect.insetBy(dx: 1.5, dy: 1.5).contains(point) }) {
            return coreHit
        }
        // 2. 边缘/键缝区域：紧凑扩边（Apple 原生手感 ~5pt/键宽，防误触抢占邻键）
        //    + 动态下一合法拼音按键热区加权（降低 26% 有效距离）
        let gridW = keysContainer.bounds.width
        let gridH = keysContainer.bounds.height
        let useDynamicBias = settings.dynamicKeyHitBoxEnabled && !validNextLetters.isEmpty && !isEnglishMode
        var best: KeyModel?
        var bestDist = CGFloat.infinity
        for key in keys {
            var hitRect = key.rect.insetBy(dx: -3, dy: -5)
            if key.id == "k_a" {
                hitRect = CGRect(x: 0, y: hitRect.minY, width: hitRect.maxX, height: hitRect.height)
            } else if key.id == "k_l" {
                hitRect = CGRect(x: hitRect.minX, y: hitRect.minY, width: max(hitRect.width, gridW - hitRect.minX), height: hitRect.height)
            } else if key.id == "k_123" {
                hitRect = CGRect(x: 0, y: hitRect.minY, width: hitRect.maxX, height: max(hitRect.height, gridH - hitRect.minY))
            } else if key.id == "k_return" {
                hitRect = CGRect(x: hitRect.minX, y: hitRect.minY, width: max(hitRect.width, gridW - hitRect.minX), height: max(hitRect.height, gridH - hitRect.minY))
            } else if key.id == "k_space" {
                hitRect = key.rect.insetBy(dx: -2, dy: -4)
            }
            guard hitRect.contains(point) else { continue }
            let dx = point.x - key.rect.midX
            let dy = point.y - key.rect.midY
            var dist = dx * dx + dy * dy
            if useDynamicBias,
               case .character(let primary, _, _, _) = key.kind,
               let ch = primary.lowercased().first,
               validNextLetters.contains(ch) {
                dist *= 0.74
            }
            if dist < bestDist {
                bestDist = dist
                best = key
            }
        }
        return best
    }
}

// MARK: - 单个按键视图

private final class KeyCapView: UIView {
    private let bgView = UIView()
    private let primaryLabel = UILabel()
    private let secondaryLabel = UILabel()
    private let downHintLabel = UILabel()
    private let doubleHintLabel = UILabel()
    private let iconView = UIImageView()

    private var theme: ResolvedTheme?
    private var model: KeyModel?
    private var spaceGradLayer: CAGradientLayer?
    private var lastShadowBounds: CGRect = .zero
    private var lastShadowRadius: CGFloat = -1

    private static let cachedShiftImage = UIImage(systemName: "shift")
    private static let cachedShiftFillImage = UIImage(systemName: "shift.fill")
    private static let cachedCapsLockImage = UIImage(systemName: "capslock.fill")
    private static let cachedDeleteImage = UIImage(systemName: "delete.left")
    private static let cachedGlobeImage = UIImage(systemName: "globe")

    private static let doublePinyinHintsByScheme: [InputScheme: [String: String]] = {
        var dict: [InputScheme: [String: String]] = [:]
        for scheme in InputScheme.allCases where scheme.isDoublePinyin {
            dict[scheme] = PinyinSegmenter.doublePinyinKeycapHints(for: scheme)
        }
        return dict
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        bgView.layer.shadowOffset = CGSize(width: 0, height: 1)
        bgView.layer.shadowRadius = 0.6
        addSubview(bgView)

        primaryLabel.textAlignment = .center
        primaryLabel.adjustsFontSizeToFitWidth = true
        primaryLabel.minimumScaleFactor = 0.72
        addSubview(primaryLabel)

        secondaryLabel.textAlignment = .right
        secondaryLabel.font = .systemFont(ofSize: 9.5, weight: .medium)
        addSubview(secondaryLabel)

        downHintLabel.textAlignment = .right
        downHintLabel.font = .systemFont(ofSize: 8.5, weight: .regular)
        addSubview(downHintLabel)

        doubleHintLabel.textAlignment = .left
        doubleHintLabel.font = .systemFont(ofSize: 8.0, weight: .semibold)
        doubleHintLabel.adjustsFontSizeToFitWidth = true
        doubleHintLabel.minimumScaleFactor = 0.7
        addSubview(doubleHintLabel)

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
            updateShadowPathIfNeeded(bounds: bgView.bounds, radius: theme.keyCornerRadius)
        }
        primaryLabel.frame = bounds.insetBy(dx: 3, dy: 2)
        secondaryLabel.frame = CGRect(x: 0, y: 2, width: bounds.width - 3, height: 11)
        downHintLabel.frame = CGRect(x: 0, y: bounds.height - 12, width: bounds.width - 3, height: 10)
        doubleHintLabel.frame = CGRect(x: 3, y: bounds.height - 12, width: max(10, bounds.width * 0.65), height: 10)
        iconView.frame = bounds.insetBy(dx: max(8, bounds.width * 0.28), dy: max(10, bounds.height * 0.28))
    }

    private func updateShadowPathIfNeeded(bounds: CGRect, radius: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        if lastShadowBounds == bounds && abs(lastShadowRadius - radius) < 0.05 {
            return
        }
        lastShadowBounds = bounds
        lastShadowRadius = radius
        bgView.layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    }

    func configure(
        model: KeyModel,
        theme: ResolvedTheme,
        showHints: Bool,
        showDownHints: Bool,
        isEnglishMode: Bool,
        isComposing: Bool,
        shiftState: ShiftState,
        scheme: InputScheme,
        returnTitle: String,
        isPressed: Bool
    ) {
        self.model = model
        self.theme = theme

        bgView.layer.cornerCurve = .continuous
        bgView.layer.cornerRadius = theme.keyCornerRadius
        bgView.layer.shadowColor = theme.keyShadowColor.cgColor
        bgView.layer.shadowOpacity = theme.keyShadowOpacity
        bgView.layer.shadowOffset = CGSize(width: 0, height: 1)
        bgView.layer.borderWidth = 0.5
        bgView.layer.borderColor = theme.keyBorder.withAlphaComponent(theme.preset.isDark ? 0.22 : 0.18).cgColor
        updateShadowPathIfNeeded(bounds: bgView.bounds, radius: theme.keyCornerRadius)

        iconView.isHidden = true
        primaryLabel.isHidden = false
        secondaryLabel.isHidden = true
        downHintLabel.isHidden = true
        doubleHintLabel.isHidden = true

        let weight: UIFont.Weight = theme.boldKeyLabel ? .semibold : .regular

        switch model.kind {
        case .character(let primary, let secondary, let downPunct, _):
            primaryLabel.text = primary
            primaryLabel.font = .systemFont(ofSize: 22, weight: weight)
            primaryLabel.textColor = theme.keyText
            if showHints, let secondary {
                secondaryLabel.text = secondary
                secondaryLabel.textColor = theme.keyHintText
                secondaryLabel.isHidden = false
            }
            if showDownHints, let downPunct {
                downHintLabel.text = downPunct
                downHintLabel.textColor = theme.keyHintText.withAlphaComponent(0.7)
                downHintLabel.isHidden = false
            }
            if !isEnglishMode && showHints {
                let lower = primary.lowercased()
                if scheme.isDoublePinyin, let spHint = Self.doublePinyinHintsByScheme[scheme]?[lower] {
                    doubleHintLabel.text = spHint
                    doubleHintLabel.textColor = theme.candidateHighlight.withAlphaComponent(0.78)
                    doubleHintLabel.isHidden = false
                } else if scheme.isWubi && lower == "z" {
                    doubleHintLabel.text = "拼音"
                    doubleHintLabel.textColor = theme.candidateHighlight.withAlphaComponent(0.78)
                    doubleHintLabel.isHidden = false
                } else if scheme == .quanpin && lower == "u" {
                    doubleHintLabel.text = "拆字"
                    doubleHintLabel.textColor = theme.candidateHighlight.withAlphaComponent(0.72)
                    doubleHintLabel.isHidden = false
                } else if scheme == .quanpin && lower == "v" {
                    doubleHintLabel.text = "工具"
                    doubleHintLabel.textColor = theme.candidateHighlight.withAlphaComponent(0.72)
                    doubleHintLabel.isHidden = false
                }
            }
        case .punctuation(let primary, _):
            primaryLabel.text = primary
            primaryLabel.font = .systemFont(ofSize: 20, weight: weight)
            primaryLabel.textColor = theme.keyText
            if !isEnglishMode && showHints && scheme.usesSemicolonFinal && primary == ";" {
                doubleHintLabel.text = "ing"
                doubleHintLabel.textColor = theme.candidateHighlight.withAlphaComponent(0.85)
                doubleHintLabel.isHidden = false
            }
        case .shiftOrSegment:
            if !isEnglishMode && isComposing {
                primaryLabel.text = "分词"
                primaryLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
                primaryLabel.textColor = theme.keyText
            } else {
                primaryLabel.isHidden = true
                iconView.isHidden = false
                switch shiftState {
                case .lowercase: iconView.image = Self.cachedShiftImage
                case .shifted: iconView.image = Self.cachedShiftFillImage
                case .capsLocked: iconView.image = Self.cachedCapsLockImage
                }
                iconView.tintColor = (shiftState != .lowercase && isEnglishMode) ? theme.accentFill : theme.keyText
            }
        case .backspace:
            primaryLabel.isHidden = true
            iconView.isHidden = false
            iconView.image = Self.cachedDeleteImage
            iconView.tintColor = theme.keyText
        case .mode123:
            primaryLabel.text = "123"
            primaryLabel.font = .systemFont(ofSize: 15, weight: .medium)
            primaryLabel.textColor = theme.keyText
        case .globe:
            primaryLabel.isHidden = true
            iconView.isHidden = false
            iconView.image = Self.cachedGlobeImage
            iconView.tintColor = theme.keyText
        case .langToggle:
            primaryLabel.text = isEnglishMode ? "英/中" : "中/英"
            primaryLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            primaryLabel.textColor = theme.keyText
        case .space:
            primaryLabel.text = isEnglishMode ? "Lingxi · English" : "灵犀 · \(scheme.shortBadge)"
            primaryLabel.font = .systemFont(ofSize: 14, weight: .regular)
            primaryLabel.textColor = theme.keyHintText
        case .returnKey:
            primaryLabel.text = returnTitle
            primaryLabel.font = .systemFont(ofSize: 15.5, weight: .semibold)
            primaryLabel.textColor = model.isAccent ? theme.accentText : theme.keyText
        }

        setPressed(isPressed)
    }

    func setPressed(_ pressed: Bool) {
        guard let theme, let model else { return }
        // 苹果质感圆角键帽：按下微移 +1pt，配合立体底影与清晰细描边，确保白色键帽圆角清晰利落
        bgView.transform = pressed ? CGAffineTransform(translationX: 0, y: 1) : .identity
        bgView.layer.cornerCurve = .continuous
        bgView.layer.cornerRadius = theme.keyCornerRadius
        bgView.layer.borderWidth = 0.5
        bgView.layer.borderColor = theme.keyBorder.withAlphaComponent(theme.preset.isDark ? 0.22 : 0.18).cgColor
        bgView.layer.shadowColor = theme.keyShadowColor.cgColor
        bgView.layer.shadowOpacity = pressed ? 0 : theme.keyShadowOpacity
        bgView.layer.shadowOffset = CGSize(width: 0, height: 1)
        bgView.layer.shadowRadius = pressed ? 0 : 0.6
        if model.isAccent {
            bgView.backgroundColor = pressed ? theme.accentPressedFill : theme.accentFill
        } else if model.isSpecial {
            bgView.backgroundColor = pressed ? theme.specialKeyPressedFill : theme.specialKeyFill
        } else {
            bgView.backgroundColor = pressed ? theme.keyPressedFill : theme.keyFill
        }

        // 空格键：严格对齐连续圆角边界，避免渐变层溢出键帽圆角外沿
        if case .space = model.kind, spaceGradLayer == nil {
            let grad = CAGradientLayer()
            grad.startPoint = CGPoint(x: 0, y: 0.5)
            grad.endPoint = CGPoint(x: 1, y: 0.5)
            bgView.layer.addSublayer(grad)
            spaceGradLayer = grad
        }
        if let grad = spaceGradLayer {
            grad.colors = [
                theme.keyFill.withAlphaComponent(0.0).cgColor,
                theme.keyFill.withAlphaComponent(0.45).cgColor,
                theme.keyFill.withAlphaComponent(0.45).cgColor,
                theme.keyFill.withAlphaComponent(0.0).cgColor
            ]
            grad.locations = [0, 0.08, 0.92, 1]
            grad.frame = bgView.bounds
            grad.cornerRadius = theme.keyCornerRadius
            grad.cornerCurve = .continuous
        }
    }
}
