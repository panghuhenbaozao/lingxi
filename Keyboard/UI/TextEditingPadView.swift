import UIKit

/// 专业文本编辑台 v2（借鉴 FlorisBoard / HeliBoard / WeType 精华）：
/// - 4 行 16 键桌面级控制：精准 4 向光标、行首/行尾、撤销、按词删、隐私安全粘贴/复制/剪切；
/// - 零联网文本工坊行：离线文案体检排版（修重复字+标点+盘古空格）、一键隐私脱敏、OpenCC 繁⇄简互转、一键去乱空行。
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
        case undo
        case deleteWordBefore
        case offlineLintFix
        case privacyRedact
        case toggleTraditional
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
    private var standardButtons: [ActionClosureButton] = []
    private var smartToolButtons: [ActionClosureButton] = []

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

        titleLabel.text = "📐 专业光标与离线排版编辑台"
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
        bodyStack.spacing = 6
        addSubview(bodyStack)

        // 第 1 行：行首/上移/行尾/退格
        bodyStack.addArrangedSubview(makeRow([
            ("行首 ⇤", .lineStart),
            ("↑ 上移", .moveUp),
            ("行尾 ⇥", .lineEnd),
            ("⌫ 删除", .deleteBackward),
        ], smartStyle: false))

        // 第 2 行：核心方向 + 撤销
        bodyStack.addArrangedSubview(makeRow([
            ("← 左移", .moveLeft),
            ("↓ 下移", .moveDown),
            ("右移 →", .moveRight),
            ("↶ 撤销", .undo),
        ], smartStyle: false))

        // 第 3 行：隐私粘贴 / 复制 / 剪切 / 按词删
        bodyStack.addArrangedSubview(makeRow([
            ("📋 粘贴", .paste),
            ("复制", .copy),
            ("剪切", .cut),
            ("✂️ 删前词", .deleteWordBefore),
        ], smartStyle: false))

        // 第 4 行：零联网智能文本工具
        bodyStack.addArrangedSubview(makeRow([
            ("🩺 离线排版", .offlineLintFix),
            ("🛡️ 脱敏", .privacyRedact),
            ("繁⇄简", .toggleTraditional),
            ("🧹 去空行", .formatCollapseLines),
        ], smartStyle: true))
    }

    private func makeRow(_ items: [(String, EditAction)], smartStyle: Bool) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 6
        for (title, act) in items {
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: smartStyle ? 12.5 : 13, weight: .semibold)
            btn.titleLabel?.adjustsFontSizeToFitWidth = true
            btn.titleLabel?.minimumScaleFactor = 0.78
            btn.layer.cornerRadius = 9
            btn.layer.cornerCurve = .continuous
            btn.actionHandler = { [weak self] in
                self?.onAction?(act)
            }
            if smartStyle {
                smartToolButtons.append(btn)
            } else {
                standardButtons.append(btn)
            }
            row.addArrangedSubview(btn)
        }
        return row
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 10
        headerStack.frame = CGRect(x: pad, y: 6, width: bounds.width - pad * 2, height: 26)
        let bodyY = headerStack.frame.maxY + 7
        bodyStack.frame = CGRect(x: pad, y: bodyY, width: bounds.width - pad * 2, height: max(120, bounds.height - bodyY - 8))
    }

    func apply(theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.canvasTop.withAlphaComponent(0.98)
        titleLabel.textColor = theme.keyText
        closeButton.backgroundColor = theme.accentFill
        closeButton.setTitleColor(theme.accentText, for: .normal)
        for btn in standardButtons {
            btn.backgroundColor = theme.keyFill
            btn.setTitleColor(theme.keyText, for: .normal)
            btn.layer.borderWidth = 0.5
            btn.layer.borderColor = theme.keyBorder.cgColor
        }
        for btn in smartToolButtons {
            btn.backgroundColor = theme.accentFill.withAlphaComponent(0.14)
            btn.setTitleColor(theme.candidateHighlight, for: .normal)
            btn.layer.borderWidth = 0.5
            btn.layer.borderColor = theme.accentFill.withAlphaComponent(0.28).cgColor
        }
    }
}
