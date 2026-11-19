import UIKit

/// 仓输入法 (Hamster) / Gboard / 微信输入法同款「文本编辑与光标控制面板」：
/// - 左侧四向十字方向键（↑ ↓ ← →，支持长按连发高速移光标）+ 行首(Home) / 行尾(End) 一键跳转；
/// - 右侧高频编辑动作：向后删(⌫，支持连发)、向前删(⌦ Forward Delete，支持连发)、复制上下文、粘贴、清空当前行、换行与返回键盘。
final class TextEditingPanelView: UIView {
    enum Action {
        case moveLeft
        case moveRight
        case moveUp
        case moveDown
        case moveLineStart
        case moveLineEnd
        case deleteBackward
        case deleteForward
        case copyContext
        case pasteClipboard
        case clearCurrentLine
        case insertNewline
        case close
    }

    var onAction: ((Action) -> Void)?

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let closeBtn = ActionClosureButton(type: .system)

    // 左侧十字导航区
    private let dpadContainer = UIView()
    private let upBtn = RepeatHoldButton(type: .system)
    private let downBtn = RepeatHoldButton(type: .system)
    private let leftBtn = RepeatHoldButton(type: .system)
    private let rightBtn = RepeatHoldButton(type: .system)
    private let homeBtn = ActionClosureButton(type: .system)
    private let endBtn = ActionClosureButton(type: .system)

    // 右侧动作网格
    private let actionsContainer = UIView()
    private let backDelBtn = RepeatHoldButton(type: .system)
    private let fwdDelBtn = RepeatHoldButton(type: .system)
    private let copyBtn = ActionClosureButton(type: .system)
    private let pasteBtn = ActionClosureButton(type: .system)
    private let clearLineBtn = ActionClosureButton(type: .system)
    private let newlineBtn = ActionClosureButton(type: .system)

    private var theme: ResolvedTheme?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        titleLabel.text = "✥ 文本编辑与光标精控"
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .bold)
        addSubview(titleLabel)

        statusLabel.text = "长按方向键或删除键可连续高速操作"
        statusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        statusLabel.textAlignment = .right
        addSubview(statusLabel)

        closeBtn.setTitle("返回键盘", for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        closeBtn.layer.cornerRadius = 8
        closeBtn.actionHandler = { [weak self] in self?.onAction?(.close) }
        addSubview(closeBtn)

        addSubview(dpadContainer)
        configureDpadButton(upBtn, title: "↑ 上移", action: .moveUp)
        configureDpadButton(downBtn, title: "↓ 下移", action: .moveDown)
        configureDpadButton(leftBtn, title: "← 左移", action: .moveLeft)
        configureDpadButton(rightBtn, title: "右移 →", action: .moveRight)

        homeBtn.setTitle("⇤ 行首", for: .normal)
        homeBtn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        homeBtn.layer.cornerRadius = 9
        homeBtn.actionHandler = { [weak self] in self?.onAction?(.moveLineStart) }
        dpadContainer.addSubview(homeBtn)

        endBtn.setTitle("行尾 ⇥", for: .normal)
        endBtn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        endBtn.layer.cornerRadius = 9
        endBtn.actionHandler = { [weak self] in self?.onAction?(.moveLineEnd) }
        dpadContainer.addSubview(endBtn)

        addSubview(actionsContainer)
        configureHoldActionButton(backDelBtn, title: "⌫ 向后删", action: .deleteBackward)
        configureHoldActionButton(fwdDelBtn, title: "向前删 ⌦", action: .deleteForward)
        configureTapActionButton(copyBtn, title: "📋 复制文本", action: .copyContext)
        configureTapActionButton(pasteBtn, title: "📥 粘贴", action: .pasteClipboard)
        configureTapActionButton(clearLineBtn, title: "🧹 清空本行", action: .clearCurrentLine)
        configureTapActionButton(newlineBtn, title: "↵ 换行", action: .insertNewline)
    }

    private func configureDpadButton(_ btn: RepeatHoldButton, title: String, action: Action) {
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
        btn.layer.cornerRadius = 10
        btn.onTrigger = { [weak self] in self?.onAction?(action) }
        dpadContainer.addSubview(btn)
    }

    private func configureHoldActionButton(_ btn: RepeatHoldButton, title: String, action: Action) {
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.layer.cornerRadius = 10
        btn.onTrigger = { [weak self] in self?.onAction?(action) }
        actionsContainer.addSubview(btn)
    }

    private func configureTapActionButton(_ btn: ActionClosureButton, title: String, action: Action) {
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.layer.cornerRadius = 10
        btn.actionHandler = { [weak self] in self?.onAction?(action) }
        actionsContainer.addSubview(btn)
    }

    func showStatusToast(_ message: String) {
        statusLabel.text = message
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.canvasTop.withAlphaComponent(0.96)
        titleLabel.textColor = theme.keyText
        statusLabel.textColor = theme.candidateHighlight

        closeBtn.backgroundColor = theme.accentFill
        closeBtn.setTitleColor(theme.accentText, for: .normal)

        for btn in [upBtn, downBtn, leftBtn, rightBtn] {
            btn.backgroundColor = theme.keyFill
            btn.setTitleColor(theme.keyText, for: .normal)
        }
        for btn in [homeBtn, endBtn] {
            btn.backgroundColor = theme.specialKeyFill
            btn.setTitleColor(theme.keyText, for: .normal)
        }
        for btn in [backDelBtn, fwdDelBtn, copyBtn, pasteBtn, clearLineBtn, newlineBtn] as [UIButton] {
            btn.backgroundColor = theme.keyFill
            btn.setTitleColor(theme.keyText, for: .normal)
        }
        clearLineBtn.setTitleColor(.systemRed, for: .normal)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 10
        let headerH: CGFloat = 28
        let closeW: CGFloat = 74

        closeBtn.frame = CGRect(x: bounds.width - pad - closeW, y: 6, width: closeW, height: headerH)
        titleLabel.frame = CGRect(x: pad, y: 6, width: 155, height: headerH)
        statusLabel.frame = CGRect(
            x: titleLabel.frame.maxX + 4,
            y: 6,
            width: max(40, closeBtn.frame.minX - titleLabel.frame.maxX - 10),
            height: headerH
        )

        let bodyY = closeBtn.frame.maxY + 8
        let bodyH = max(100, bounds.height - bodyY - pad)
        let usableW = bounds.width - pad * 2
        let colGap: CGFloat = 10
        let leftW = floor(usableW * 0.48)
        let rightW = usableW - leftW - colGap

        dpadContainer.frame = CGRect(x: pad, y: bodyY, width: leftW, height: bodyH)
        actionsContainer.frame = CGRect(x: pad + leftW + colGap, y: bodyY, width: rightW, height: bodyH)

        // 左侧 3 行布局：第 1 行 [行首][↑][行尾]，第 2 行 [← 左移][右移 →]，第 3 行 [↓ 下移]
        let gap: CGFloat = 6
        let rH = (bodyH - gap * 2) / 3.0
        let thirdW = (leftW - gap * 2) / 3.0
        let halfLeftW = (leftW - gap) / 2.0

        homeBtn.frame = CGRect(x: 0, y: 0, width: thirdW, height: rH)
        upBtn.frame = CGRect(x: thirdW + gap, y: 0, width: thirdW, height: rH)
        endBtn.frame = CGRect(x: (thirdW + gap) * 2, y: 0, width: thirdW, height: rH)

        leftBtn.frame = CGRect(x: 0, y: rH + gap, width: halfLeftW, height: rH)
        rightBtn.frame = CGRect(x: halfLeftW + gap, y: rH + gap, width: halfLeftW, height: rH)

        downBtn.frame = CGRect(x: thirdW + gap, y: (rH + gap) * 2, width: thirdW, height: rH)

        // 右侧 3 行 x 2 列网格
        let halfRightW = (rightW - gap) / 2.0
        let rightButtons: [UIView] = [backDelBtn, fwdDelBtn, copyBtn, pasteBtn, clearLineBtn, newlineBtn]
        for (idx, btn) in rightButtons.enumerated() {
            let r = idx / 2
            let c = idx % 2
            btn.frame = CGRect(
                x: CGFloat(c) * (halfRightW + gap),
                y: CGFloat(r) * (rH + gap),
                width: halfRightW,
                height: rH
            )
        }
    }
}

/// 支持按下立即触发一次、长按 0.30s 后以 0.075s 周期连续触发的操控按钮。
/// 通过 `didSet` 挂载事件，兼容 `RepeatHoldButton(type: .system)` 的 UIKit 工厂构造路径。
private final class RepeatHoldButton: UIButton {
    var onTrigger: (() -> Void)? {
        didSet {
            removeTarget(self, action: #selector(touchDown), for: .touchDown)
            removeTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
            addTarget(self, action: #selector(touchDown), for: .touchDown)
            addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
    }
    private var holdTimer: Timer?

    deinit {
        holdTimer?.invalidate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            touchUp()
        }
    }

    @objc private func touchDown() {
        holdTimer?.invalidate()
        onTrigger?()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.30, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.holdTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in
                self?.onTrigger?()
            }
        }
    }

    @objc private func touchUp() {
        holdTimer?.invalidate()
        holdTimer = nil
    }
}
