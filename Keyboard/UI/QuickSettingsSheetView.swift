import UIKit

/// 键盘内快捷设置抽屉（免跳转 App 即可实时切换方案、单手模式、高度、皮肤、音效震动）。
final class QuickSettingsSheetView: UIView {
    var onSettingsChanged: ((LingxiSettings) -> Void)?
    var onThemeChanged: ((ThemeCustomization) -> Void)?
    var onBridgeSyncNow: (() -> Void)?
    var onOpenEditPad: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onClose: (() -> Void)?

    private let scrollView = LingxiScrollView()
    private let stackView = UIStackView()
    private var theme: ResolvedTheme?
    private var settings = LingxiSettings.load(force: true)
    private var customization = ThemeCustomization.load(force: true)
    private var isSystemDark: Bool = false

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

    func configure(theme: ResolvedTheme, settings: LingxiSettings, customization: ThemeCustomization, isSystemDark: Bool = false) {
        self.theme = theme
        self.settings = settings
        self.customization = customization
        self.isSystemDark = isSystemDark
        backgroundColor = theme.canvasTop.withAlphaComponent(0.97)
        rebuild()
    }

    func updateTheme(
        _ theme: ResolvedTheme,
        settings: LingxiSettings? = nil,
        customization: ThemeCustomization? = nil,
        isSystemDark: Bool? = nil
    ) {
        self.theme = theme
        if let settings { self.settings = settings }
        if let customization { self.customization = customization }
        if let isSystemDark { self.isSystemDark = isSystemDark }
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
        let todayChars = TypingStatsStore.shared.summary().todayChars
        title.text = todayChars > 0 ? "⚙️ 灵犀快捷设置 · 今日 \(todayChars) 字" : "⚙️ 灵犀快捷设置"
        title.font = .systemFont(ofSize: 14.5, weight: .bold)
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

        // 免费侧载沙盒隔离时：提供一键认领/同步主 App 外观与设置的云桥接横幅
        if !AppGroup.isAvailable {
            let paired = SideloadConfigBridge.isPairedInThisProcess
            let bridgeBtn = ActionClosureButton(type: .system)
            let stateText = paired
                ? "☁️ 云桥接已连 · 点此立即同步主 App 外观与设置"
                : "⚠️ 免费侧载沙盒隔离 · 主 App 复制凭证后点此同步"
            bridgeBtn.setTitle(stateText, for: .normal)
            bridgeBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            bridgeBtn.titleLabel?.lineBreakMode = .byTruncatingTail
            bridgeBtn.backgroundColor = paired ? theme.accentFill.withAlphaComponent(0.18) : UIColor.systemOrange.withAlphaComponent(0.20)
            bridgeBtn.setTitleColor(paired ? theme.candidateHighlight : UIColor.systemOrange, for: .normal)
            bridgeBtn.layer.cornerRadius = 9
            bridgeBtn.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
            bridgeBtn.actionHandler = { [weak self] in
                self?.onBridgeSyncNow?()
            }
            stackView.addArrangedSubview(bridgeBtn)
        }

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

        let schemeScroll = LingxiScrollView()
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

        // 1.5 场景键盘布局包（标准 / 仓式效率 / 程序员极客 / 写作创作者 / 商务办公，键盘内 1 键秒切）
        let packLabel = UILabel()
        packLabel.text = "场景布局包（含划动命令 / 数字行 / 盘古空格）"
        packLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        packLabel.textColor = theme.keyHintText
        stackView.addArrangedSubview(packLabel)

        let packScroll = LingxiScrollView()
        packScroll.showsHorizontalScrollIndicator = false
        packScroll.translatesAutoresizingMaskIntoConstraints = false
        packScroll.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let packRow = UIStackView()
        packRow.axis = .horizontal
        packRow.spacing = 6
        for pack in CustomKeyboardLayoutPack.builtInPacks {
            let active = (pack.id == settings.activeLayoutPackID)
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(pack.name, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            btn.backgroundColor = active ? theme.accentFill : theme.keyFill
            btn.setTitleColor(active ? theme.accentText : theme.keyText, for: .normal)
            btn.layer.cornerRadius = 8
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
            btn.actionHandler = { [weak self] in
                guard let self else { return }
                pack.apply(to: &self.settings)
                self.settings.save()
                self.onSettingsChanged?(self.settings)
                self.rebuild()
            }
            packRow.addArrangedSubview(btn)
        }
        packRow.translatesAutoresizingMaskIntoConstraints = false
        packScroll.addSubview(packRow)
        NSLayoutConstraint.activate([
            packRow.topAnchor.constraint(equalTo: packScroll.topAnchor),
            packRow.bottomAnchor.constraint(equalTo: packScroll.bottomAnchor),
            packRow.leadingAnchor.constraint(equalTo: packScroll.leadingAnchor),
            packRow.trailingAnchor.constraint(equalTo: packScroll.trailingAnchor),
            packRow.heightAnchor.constraint(equalTo: packScroll.heightAnchor),
        ])
        stackView.addArrangedSubview(packScroll)

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

        // 4. 外观模式（跟随系统 / 浅色 / 深色）与快速皮肤切换（与主 App「外观」页 100% 同源实时同步）
        stackView.addArrangedSubview(makeSegmentedRow(
            label: "外观模式",
            options: KeyboardAppearanceMode.allCases.map(\.displayName),
            selectedIndex: KeyboardAppearanceMode.allCases.firstIndex(of: customization.appearanceMode) ?? 0,
            theme: theme
        ) { [weak self] idx in
            guard let self else { return }
            let mode = KeyboardAppearanceMode.allCases[idx]
            self.customization.applyAppearanceMode(mode)
            self.customization.save()
            self.onThemeChanged?(self.customization)
        })

        let skinLabel = UILabel()
        skinLabel.text = "主题皮肤 · \(theme.preset.name)（\(customization.appearanceMode.displayName)）"
        skinLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        skinLabel.textColor = theme.keyHintText
        stackView.addArrangedSubview(skinLabel)

        let skinScroll = LingxiScrollView()
        skinScroll.showsHorizontalScrollIndicator = false
        skinScroll.translatesAutoresizingMaskIntoConstraints = false
        skinScroll.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let skinRow = UIStackView()
        skinRow.axis = .horizontal
        skinRow.spacing = 6
        let activePresetID = theme.preset.id
        let hasActiveCustom = theme.preset.isDark
            ? customization.hasDarkCustomOverrides
            : customization.hasLightCustomOverrides
        for preset in KeyboardThemePreset.presets {
            let active = (preset.id == activePresetID && !hasActiveCustom)
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(preset.name, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            btn.backgroundColor = active ? theme.accentFill : theme.keyFill
            btn.setTitleColor(active ? theme.accentText : theme.keyText, for: .normal)
            btn.layer.cornerRadius = 8
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
            btn.actionHandler = { [weak self] in
                guard let self else { return }
                self.customization.applyPresetSelection(preset, isSystemDark: self.isSystemDark)
                self.customization.save()
                self.onThemeChanged?(self.customization)
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

        // 4.8 隐身无痕模式一键隐私开关（对标 HeliBoard / FlorisBoard：暂停词库学习、剪贴板记录、统计与 AI 历史）
        let incognitoBtn = ActionClosureButton(type: .system)
        incognitoBtn.setTitle(
            settings.incognitoModeEnabled ? "🕶 无痕模式已开启（点此退出 · 零记录）" : "🕶 开启隐身无痕模式（暂停词库/剪贴板/统计）",
            for: .normal
        )
        incognitoBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        incognitoBtn.titleLabel?.lineBreakMode = .byTruncatingTail
        incognitoBtn.backgroundColor = settings.incognitoModeEnabled
            ? UIColor.systemOrange.withAlphaComponent(0.22)
            : theme.specialKeyFill
        incognitoBtn.setTitleColor(settings.incognitoModeEnabled ? UIColor.systemOrange : theme.keyText, for: .normal)
        incognitoBtn.layer.cornerRadius = 9
        incognitoBtn.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        incognitoBtn.actionHandler = { [weak self] in
            guard let self else { return }
            self.settings.incognitoModeEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        }
        stackView.addArrangedSubview(incognitoBtn)

        // 4.6 长辈 / 护眼大字关怀一键模式 + 选词轻声播报
        let careRow = UIStackView()
        careRow.axis = .horizontal
        careRow.distribution = .fillEqually
        careRow.spacing = 6
        careRow.addArrangedSubview(makeToggleChip("👴 大字关怀", on: settings.elderCareModeEnabled, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.setElderCareMode(!self.settings.elderCareModeEnabled)
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        careRow.addArrangedSubview(makeToggleChip("🔊 选词播报", on: settings.speakSelectedCandidateEnabled, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.speakSelectedCandidateEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        stackView.addArrangedSubview(careRow)

        // 5. 高频开关（精简为 2 排 6 个常用开关 + 1 排快捷能力，更多细节统一收口至主 App「设置」）
        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.distribution = .fillEqually
        row1.spacing = 6

        row1.addArrangedSubview(makeToggleChip("按键音", on: settings.keySoundEnabled, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.keySoundEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        row1.addArrangedSubview(makeToggleChip("震动", on: settings.hapticStrength != .off, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.hapticStrength = (self.settings.hapticStrength == .off) ? .light : .off
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        row1.addArrangedSubview(makeToggleChip(
            settings.traditionalChineseEnabled ? "繁体·\(settings.traditionalVariant.shortBadge)" : "简体",
            on: settings.traditionalChineseEnabled,
            theme: theme
        ) { [weak self] in
            guard let self else { return }
            self.settings.traditionalChineseEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        stackView.addArrangedSubview(row1)

        if settings.traditionalChineseEnabled {
            stackView.addArrangedSubview(makeSegmentedRow(
                label: "繁体标准",
                options: TraditionalChineseVariant.allCases.map(\.shortBadge).enumerated().map { idx, _ in
                    switch TraditionalChineseVariant.allCases[idx] {
                    case .standard: return "标准繁"
                    case .taiwanPhrase: return "台湾正体"
                    case .hongKong: return "香港繁"
                    }
                },
                selectedIndex: TraditionalChineseVariant.allCases.firstIndex(of: settings.traditionalVariant) ?? 1,
                theme: theme
            ) { [weak self] idx in
                guard let self else { return }
                self.settings.traditionalVariant = TraditionalChineseVariant.allCases[idx]
                self.settings.save()
                self.onSettingsChanged?(self.settings)
                self.rebuild()
            })
        }

        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.distribution = .fillEqually
        row2.spacing = 6

        row2.addArrangedSubview(makeToggleChip("智能联想", on: settings.bigramPredictionEnabled, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.bigramPredictionEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        row2.addArrangedSubview(makeToggleChip("标点:\(settings.punctuationStyle.shortBadge)", on: settings.punctuationStyle == .fullwidth, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.punctuationStyle = (self.settings.punctuationStyle == .fullwidth) ? .halfwidth : .fullwidth
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        row2.addArrangedSubview(makeToggleChip("顶部数字行", on: settings.showNumberRow, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.showNumberRow.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        stackView.addArrangedSubview(row2)

        let row3 = UIStackView()
        row3.axis = .horizontal
        row3.distribution = .fillEqually
        row3.spacing = 6

        row3.addArrangedSubview(makeToggleChip("滑行输入", on: settings.glideTypingEnabled, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.glideTypingEnabled.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        row3.addArrangedSubview(makeToggleChip("截屏传后删", on: settings.autoDeleteUploadedScreenshot, theme: theme) { [weak self] in
            guard let self else { return }
            self.settings.autoDeleteUploadedScreenshot.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuild()
        })
        row3.addArrangedSubview(makeToggleChip("🔐 一键权限", on: false, theme: theme) { [weak self] in
            self?.onOpenPermissions?()
        })
        stackView.addArrangedSubview(row3)

        let row4 = UIStackView()
        row4.axis = .horizontal
        row4.distribution = .fillEqually
        row4.spacing = 6

        row4.addArrangedSubview(makeToggleChip("译:\(settings.translateTargetLang)", on: true, theme: theme) { [weak self] in
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
        row4.addArrangedSubview(makeToggleChip("📐 编辑台", on: false, theme: theme) { [weak self] in
            self?.onOpenEditPad?()
        })
        stackView.addArrangedSubview(row4)

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
        lbl.textColor = theme.keyText.withAlphaComponent(0.82)
        lbl.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let seg = ActionSegmentedControl(items: options)
        seg.selectedSegmentIndex = selectedIndex
        // 显式注入深浅主题高对比配色，彻底解决暗色模式下系统分段器文字发黑看不清的真机 Bug
        seg.backgroundColor = theme.specialKeyFill
        seg.selectedSegmentTintColor = theme.accentFill
        seg.setTitleTextAttributes([
            .foregroundColor: theme.accentText,
            .font: UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        ], for: .selected)
        seg.setTitleTextAttributes([
            .foregroundColor: theme.keyText,
            .font: UIFont.systemFont(ofSize: 12.5, weight: .medium)
        ], for: .normal)
        seg.onChange = onSelect

        row.addArrangedSubview(lbl)
        row.addArrangedSubview(seg)
        return row
    }

    private func makeToggleChip(_ title: String, on: Bool, theme: ResolvedTheme, action: @escaping () -> Void) -> UIButton {
        let btn = ActionClosureButton(type: .system)
        btn.setTitle(on ? "✓ \(title)" : title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        // 高对比配色：开启态用主题强调色实底白字，关闭态用立体键帽底+清晰主文字+细描边，暗色/亮色均一眼看清
        btn.backgroundColor = on ? theme.accentFill : theme.keyFill
        btn.setTitleColor(on ? theme.accentText : theme.keyText, for: .normal)
        btn.layer.cornerRadius = 8
        btn.layer.cornerCurve = .continuous
        btn.layer.borderWidth = on ? 0 : 0.6
        btn.layer.borderColor = theme.keyBorder.cgColor
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
