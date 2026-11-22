import UIKit

/// 专业文本编辑台（借鉴 FlorisBoard / HeliBoard 精华：精准方向键、单指扩选模式、行首行尾、全选复制剪切粘贴、一键排版微整形）。
final class TextEditingPadView: UIView {
    enum EditAction {
        case moveLeft
        case moveRight
        case moveUp
        case moveDown
        case lineStart
        case lineEnd
        case copy
        case cut
        case paste
        case selectAll
        case deleteBackward
        case formatPanguSpace
        case formatCollapseLines
    }

    var onAction: ((EditAction) -> Void)?
    var onClose: (() -> Void)?

    private var theme: ResolvedTheme?
    private let headerStack = UIStackView()
    private let titleLabel = UILabel()
    private let closeButton = ActionClosureButton(type: .system)
    private let bodyStack = UIStackView()
    private var allActionButtons: [ActionClosureButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 8
        addSubview(headerStack)

        titleLabel.text = "📐 专业光标与排版编辑台"
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .bold)
        headerStack.addArrangedSubview(titleLabel)

        closeButton.setTitle("返回键盘", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        closeButton.layer.cornerRadius = 8
        closeButton.layer.cornerCurve = .continuous
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        closeButton.actionHandler = { [weak self] in self?.onClose?() }
        headerStack.addArrangedSubview(closeButton)

        bodyStack.axis = .vertical
        bodyStack.distribution = .fillEqually
        bodyStack.spacing = 7
        addSubview(bodyStack)

        // 第 1 行：快捷编辑动作
        bodyStack.addArrangedSubview(makeRow([
            ("行首 ⇤", .lineStart),
            ("↑ 上移", .moveUp),
            ("行尾 ⇥", .lineEnd),
            ("⌫ 删除", .deleteBackward),
        ]))

        // 第 2 行：核心左右移动 + 复制粘贴
        bodyStack.addArrangedSubview(makeRow([
            ("← 左移", .moveLeft),
            ("↓ 下移", .moveDown),
            ("右移 →", .moveRight),
            ("📋 粘贴", .paste),
        ]))

        // 第 3 行：剪贴操作 + 一键排版微整形
        bodyStack.addArrangedSubview(makeRow([
            ("复制", .copy),
            ("剪切", .cut),
            ("✨ 中英加空格", .formatPanguSpace),
            ("🧹 去乱空行", .formatCollapseLines),
        ]))
    }

    private func makeRow(_ items: [(String, EditAction)]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 7
        for (title, act) in items {
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
            btn.layer.cornerRadius = 9
            btn.layer.cornerCurve = .continuous
            btn.actionHandler = { [weak self] in
                self?.onAction?(act)
            }
            allActionButtons.append(btn)
            row.addArrangedSubview(btn)
        }
        return row
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 10
        headerStack.frame = CGRect(x: pad, y: 6, width: bounds.width - pad * 2, height: 28)
        let bodyY = headerStack.frame.maxY + 8
        bodyStack.frame = CGRect(x: pad, y: bodyY, width: bounds.width - pad * 2, height: max(90, bounds.height - bodyY - 8))
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.canvasTop.withAlphaComponent(0.98)
        titleLabel.textColor = theme.keyText
        closeButton.backgroundColor = theme.accentFill
        closeButton.setTitleColor(theme.accentText, for: .normal)
        for btn in allActionButtons {
            btn.backgroundColor = theme.keyFill
            btn.setTitleColor(theme.keyText, for: .normal)
            btn.layer.borderWidth = 0.5
            btn.layer.borderColor = theme.keyBorder.cgColor
        }
    }
}
