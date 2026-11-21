import UIKit

/// 键盘内快捷设置抽屉（免跳转 App 即可实时切换方案、单手模式、高度、皮肤、音效震动）。
final class QuickSettingsSheetView: UIView {
    var onSettingsChanged: ((LingxiSettings) -> Void)?
    var onThemeChanged: ((ThemeCustomization) -> Void)?
    var onClose: (() -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var theme: ResolvedTheme?
    private var settings = LingxiSettings.load()
    private var customization = ThemeCustomization.load()

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsVerticalScrollIndicator = true
        addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 10
        stackView.alignment = .fill
        scrollView.addSubview(stackView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        let pad: CGFloat = 10
        let w = max(100, bounds.width - pad * 2)
        let fit = stackView.systemLayoutSizeFitting(
            CGSize(width: w, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        stackView.frame = CGRect(x: pad, y: 8, width: w, height: fit.height)
        scrollView.contentSize = CGSize(width: bounds.width, height: fit.height + 16)
    }

    func configure(theme: ResolvedTheme, settings: LingxiSettings, customization: ThemeCustomization) {
        self.theme = theme
        self.settings = settings
        self.customization = customization
        backgroundColor = theme.canvasTop.withAlphaComponent(0.97)
        rebuild()
    }

    func updateTheme(_ theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.canvasTop.withAlphaComponent(0.97)
        rebuild()
    }

    private func rebuild() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }

        // 标题行
        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        let title = UILabel()
        title.text = "⚙️ 灵犀快捷设置"
        title.font = .systemFont(ofSize: 15, weight: .bold)
        title.textColor = theme.keyText
        let closeBtn = ActionClosureButton(type: .system)
        closeBtn.setTitle("完成", for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
        closeBtn.backgroundColor = theme.accentFill
        closeBtn.setTitleColor(theme.accentText, for: .normal)
        closeBtn.layer.cornerRadius = 8
        closeBtn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        closeBtn.actionHandler = { [weak self] in self?.onClose?() }
        header.addArrangedSubview(title)
        header.addArrangedSubview(closeBtn)
        stackView.addArrangedSubview(header)

        // 0. 键盘布局模式（26键 / 九宫格）
        stackView.addArrangedSubview(makeSegmentedRow(
            label: "键盘布局",
            options: KeyboardLayoutMode.allCases.map(\.displayName),
            selectedIndex: KeyboardLayoutMode.allCases.firstIndex(of: settings.layoutMode) ?? 0,
            theme: theme
        ) { [weak self] idx in
            guard let self else { return }
            self.settings.layoutMode = KeyboardLayoutMode.allCases[idx]
            self.settings.save()
            self.onSettingsChanged?(self.settings)
        })

        // 1. 输入方案（可横向滑动切换全拼 + 7 种双拼 + 五笔 86）
        let schemeLabel = UILabel()
        schemeLabel.text = "输入方案（全拼 / 7种双拼 / 五笔86）"
        schemeLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        schemeLabel.textColor = theme.keyHintText
        stackView.addArrangedSubview(schemeLabel)

        let schemeScroll = UIScrollView()
        schemeScroll.showsHorizontalScrollIndicator = false
        schemeScroll.translatesAutoresizingMaskIntoConstraints = false
        schemeScroll.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let schemeRow = UIStackView()
        schemeRow.axis = .horizontal
        schemeRow.spacing = 6
        for scheme in InputScheme.allCases {
            let active = (scheme == settings.inputScheme)
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(scheme.displayName, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            btn.backgroundColor = active ? theme.accentFill : theme.keyFill
            btn.setTitleColor(active ? theme.accentText : theme.keyText, for: .normal)
            btn.layer.cornerRadius = 8
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
            btn.actionHandler = { [weak self] in
                guard let self else { return }
                self.settings.inputScheme = scheme
                if scheme.isWubi && self.settings.layoutMode == .t9Nine {
                    self.settings.layoutMode = .qwerty26
                }
                self.settings.save()
                self.onSettingsChanged?(self.settings)
                self.rebuild()
            }
            schemeRow.addArrangedSubview(btn)
        }
        schemeRow.translatesAutoresizingMaskIntoConstraints = false
        schemeScroll.addSubview(schemeRow)
        NSLayoutConstraint.activate([
            schemeRow.topAnchor.constraint(equalTo: schemeScroll.topAnchor),
            schemeRow.bottomAnchor.constraint(equalTo: schemeScroll.bottomAnchor),
            schemeRow.leadingAnchor.constraint(equalTo: schemeScroll.leadingAnchor),
            schemeRow.trailingAnchor.constraint(equalTo: schemeScroll.trailingAnchor),
            schemeRow.heightAnchor.constraint(equalTo: schemeScroll.heightAnchor),
        ])
        stackView.addArrangedSubview(schemeScroll)

        // 2. 单手模式
        stackView.addArrangedSubview(makeSegmentedRow(
            label: "单手模式",
            options: HandednessMode.allCases.map(\.displayName),
            selectedIndex: HandednessMode.allCases.firstIndex(of: settings.handedness) ?? 0,
            theme: theme
        ) { [weak self] idx in
            guard let self else { return }
            self.settings.handedness = HandednessMode.allCases[idx]
            self.settings.save()
            self.onSettingsChanged?(self.settings)
        })

        // 3. 键盘高度
        stackView.addArrangedSubview(makeSegmentedRow(
            label: "键盘高度",
            options: KeyboardHeightPreset.allCases.map(\.displayName),
            selectedIndex: KeyboardHeightPreset.allCases.firstIndex(of: settings.heightPreset) ?? 1,
            theme: theme
        ) { [weak self] idx in
            guard let self else { return }
            self.settings.heightPreset = KeyboardHeightPreset.allCases[idx]
            self.settings.save()
            self.onSettingsChanged?(self.settings)
        })

        // 4. 快速皮肤切换
        let skinLabel = UILabel()
        skinLabel.text = "主题皮肤"
        skinLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        skinLabel.textColor = theme.keyHintText
        stackView.addArrangedSubview(skinLabel)

        let skinScroll = UIScrollView()
        skinScroll.showsHorizontalScrollIndicator = false
        skinScroll.translatesAutoresizingMaskIntoConstraints = false
        skinScroll.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let skinRow = UIStackView()
        skinRow.axis = .horizontal
        skinRow.spacing = 6
        for preset in KeyboardThemePreset.presets {
            let active = (preset.id == customization.selectedThemeID)
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(preset.name, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            btn.backgroundColor = active ? theme.accentFill : theme.keyFill
            btn.setTitleColor(active ? theme.accentText : theme.keyText, for: .normal)
            btn.layer.cornerRadius = 8
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
            btn.actionHandler = { [weak self] in
                guard let self else { return }
                self.customization.selectedThemeID = preset.id
                self.customization.adaptiveDarkMode = false
                self.customization.save()
                self.onThemeChanged?(self.customization)
                self.rebuild()
            }
            skinRow.addArrangedSubview(btn)
        }
        skinRow.translatesAutoresizingMaskIntoConstraints = false
        skinScroll.addSubview(skinRow)
        NSLayoutConstraint.activate([
            skinRow.topAnchor.constraint(equalTo: skinScroll.topAnchor),
            skinRow.bottomAnchor.constraint(equalTo: skinScroll.bottomAnchor),
            skinRow.leadingAnchor.constraint(equalTo: skinScroll.leadingAnchor),
            skinRow.trailingAnchor.constraint(equalTo: skinScroll.trailingAnchor),
            skinRow.heightAnchor.constraint(equalTo: skinScroll.heightAnchor),
        ])
        stackView.addArrangedSubview(skinScroll)

        // 5. 常用开关
        let toggleRow = UIStackView()
        toggleRow.axis = .horizontal
        toggleRow.distribution = .fillEqually
        toggleRow.spacing = 6

        toggleRow.addArrangedSubview(makeToggleChip("按键音", on: settings.keySoundEnabled, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.keySoundEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        toggleRow.addArrangedSubview(makeToggleChip("震动反馈", on: settings.hapticStrength != .off, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.hapticStrength = (self.settings.hapticStrength == .off) ? .light : .off
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        toggleRow.addArrangedSubview(makeToggleChip("成对标点", on: settings.autoPairPunctuation, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.autoPairPunctuation.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        stackView.addArrangedSubview(toggleRow)

        let extraRow = UIStackView()
        extraRow.axis = .horizontal
        extraRow.distribution = .fillEqually
        extraRow.spacing = 6

        extraRow.addArrangedSubview(makeToggleChip(settings.traditionalChineseEnabled ? "繁体输出" : "简体输出", on: settings.traditionalChineseEnabled, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.traditionalChineseEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        extraRow.addArrangedSubview(makeToggleChip("中英空格", on: settings.panguSpaceLetters, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.panguSpaceLetters.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        extraRow.addArrangedSubview(makeToggleChip("中数空格", on: settings.panguSpaceDigits, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.panguSpaceDigits.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        stackView.addArrangedSubview(extraRow)

        let smartRow = UIStackView()
        smartRow.axis = .horizontal
        smartRow.distribution = .fillEqually
        smartRow.spacing = 6

        smartRow.addArrangedSubview(makeToggleChip("拼写纠错", on: settings.typoCorrectionEnabled, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.typoCorrectionEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        smartRow.addArrangedSubview(makeToggleChip("表情联想", on: settings.emojiSuggestionEnabled, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.emojiSuggestionEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        smartRow.addArrangedSubview(makeToggleChip("译:\(settings.translateTargetLang)", on: true, theme: theme) { [weak self] in
            guard let self else { return }
            let langs = TranslateTargetLanguage.allCases.map(\.rawValue)
            if let idx = langs.firstIndex(of: self.settings.translateTargetLang) {
                self.settings.translateTargetLang = langs[(idx + 1) % langs.count]
            } else {
                self.settings.translateTargetLang = langs.first ?? "英文"
            }
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        stackView.addArrangedSubview(smartRow)

        let wowRow = UIStackView()
        wowRow.axis = .horizontal
        wowRow.distribution = .fillEqually
        wowRow.spacing = 6

        wowRow.addArrangedSubview(makeToggleChip("标点:\(settings.punctuationStyle.shortBadge)", on: settings.punctuationStyle == .fullwidth, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.punctuationStyle = (self.settings.punctuationStyle == .fullwidth) ? .halfwidth : .fullwidth
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        if settings.inputScheme.isWubi {
            wowRow.addArrangedSubview(makeToggleChip("四码直出", on: settings.wubiAutoCommitUnique4, theme: theme) { [weak self] in
                guard let self else { return }
                self.settings.wubiAutoCommitUnique4.toggle()
                self.settings.save()
                self.onSettingsChanged?(self.settings)
                self.rebuild()
            })
            wowRow.addArrangedSubview(makeToggleChip("编码提示", on: settings.wubiShowCodeHints, theme: theme) { [weak self] in
                guard let self else { return }
                self.settings.wubiShowCodeHints.toggle()
                self.settings.save()
                self.onSettingsChanged?(self.settings)
                self.rebuild()
            })
        } else {
            wowRow.addArrangedSubview(makeToggleChip("弯引号配对", on: settings.smartQuotePairing, theme: theme) { [weak self] in
                guard let self else { return }
                self.settings.smartQuotePairing.toggle()
                self.settings.save()
                self.onSettingsChanged?(self.settings)
                self.rebuild()
            })
            wowRow.addArrangedSubview(makeToggleChip("学习阈值:\(settings.autoLearnThreshold)次", on: settings.autoLearnThreshold > 1, theme: theme) { [weak self] in
                guard let self else { return }
                self.settings.autoLearnThreshold = (self.settings.autoLearnThreshold % 5) + 1
                self.settings.save()
                self.onSettingsChanged?(self.settings)
                self.rebuild()
            })
        }
        stackView.addArrangedSubview(wowRow)

        let proRow = UIStackView()
        proRow.axis = .horizontal
        proRow.distribution = .fillEqually
        proRow.spacing = 6

        proRow.addArrangedSubview(makeToggleChip("滑行输入", on: settings.glideTypingEnabled, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.glideTypingEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        proRow.addArrangedSubview(makeToggleChip("顶部数字行", on: settings.showNumberRow, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.showNumberRow.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        proRow.addArrangedSubview(makeToggleChip("动态防误触", on: settings.dynamicKeyHitBoxEnabled, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.dynamicKeyHitBoxEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        stackView.addArrangedSubview(proRow)

        setNeedsLayout()
    }

    private func makeSegmentedRow(
        label: String,
        options: [String],
        selectedIndex: Int,
        theme: ResolvedTheme,
        onSelect: @escaping (Int) -> Void
    ) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center

        let lbl = UILabel()
        lbl.text = label
        lbl.font = .systemFont(ofSize: 12.5, weight: .semibold)
        lbl.textColor = theme.keyHintText
        lbl.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let seg = ActionSegmentedControl(items: options)
        seg.selectedSegmentIndex = selectedIndex
        seg.onChange = onSelect

        row.addArrangedSubview(lbl)
        row.addArrangedSubview(seg)
        return row
    }

    private func makeToggleChip(_ title: String, on: Bool, theme: ResolvedTheme, action: @escaping () -> Void) -> UIButton {
        let btn = ActionClosureButton(type: .system)
        btn.setTitle(on ? "✓ \(title)" : title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        btn.backgroundColor = on ? theme.accentFill.withAlphaComponent(0.18) : theme.specialKeyFill
        btn.setTitleColor(on ? theme.candidateHighlight : theme.keyHintText, for: .normal)
        btn.layer.cornerRadius = 8
        btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
        // VoiceOver：开关 chip 暴露纯净功能名与选中状态，避免读出标题中的对勾符号
        btn.accessibilityLabel = title
        btn.accessibilityTraits = on ? [.button, .selected] : [.button]
        btn.actionHandler = action
        return btn
    }
}

private final class ActionSegmentedControl: UISegmentedControl {
    var onChange: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(changed), for: .valueChanged)
    }

    override init(items: [Any]?) {
        super.init(items: items)
        addTarget(self, action: #selector(changed), for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func changed() {
        onChange?(selectedSegmentIndex)
    }
}
