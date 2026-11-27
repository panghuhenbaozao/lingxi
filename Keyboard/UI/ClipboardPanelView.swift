import UIKit

/// 剪贴板历史（含多选拼段/净链/分字段速填）、个人速填名片夹、草稿防丢黑匣子、离线救场话术与短语趣味面板。
final class ClipboardPanelView: UIView {
    enum Tab: Int, CaseIterable {
        case history = 0
        case cards = 1
        case drafts = 2
        case scripts = 3
        case phrases = 4

        var title: String {
            switch self {
            case .history: return "剪贴板"
            case .cards: return "名片"
            case .drafts: return "草稿"
            case .scripts: return "话术"
            case .phrases: return "短语"
            }
        }
    }

    var onInsertText: ((String) -> Void)?
    var onSendToAI: ((String) -> Void)?
    var onStylishFontChanged: ((StylishFontStyle) -> Void)?
    var onClose: (() -> Void)?

    private let headerStack = UIStackView()
    private let subActionBar = UIView()
    private let pasteTarget = PasteTargetView()
    private var pasteNowControl: UIPasteControl?
    private let mergeToggleButton = ActionClosureButton(type: .system)
    private let mergeCommitButton = ActionClosureButton(type: .system)
    private let clearUnpinnedButton = ActionClosureButton(type: .system)
    private let clearDraftsButton = ActionClosureButton(type: .system)
    private let backButton = ActionClosureButton(type: .system)

    private let scrollView = LingxiScrollView()
    private let listStack = UIStackView()

    private var currentTab: Tab = .history
    private var selectedScriptCategory: SocialScriptCategory = .politeRefuse
    private var theme: ResolvedTheme?
    private var activeFontStyle: StylishFontStyle = .normal
    private var explodedItemID: UUID?
    private var isMergeMode = false
    private var selectedMergeIDs: [UUID] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        pasteTarget.onPasteText = { [weak self] text in
            // 保险箱复制的敏感内容与无痕模式均不写入剪贴板历史
            if !ConcealedPasteboard.isConcealed() && !LingxiSettings.load().incognitoModeEnabled {
                _ = ClipboardStore.record(text, changeCount: UIPasteboard.general.changeCount)
            }
            self?.reloadContent()
        }
        addSubview(pasteTarget)

        headerStack.axis = .horizontal
        headerStack.distribution = .fillEqually
        headerStack.spacing = 5
        addSubview(headerStack)

        addSubview(subActionBar)

        mergeToggleButton.setTitle("拼段", for: .normal)
        mergeToggleButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        mergeToggleButton.actionHandler = { [weak self] in
            guard let self else { return }
            self.isMergeMode.toggle()
            if !self.isMergeMode {
                self.selectedMergeIDs.removeAll()
            }
            self.reloadContent()
        }
        subActionBar.addSubview(mergeToggleButton)

        mergeCommitButton.setTitle("合并上屏", for: .normal)
        mergeCommitButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        mergeCommitButton.isHidden = true
        mergeCommitButton.actionHandler = { [weak self] in
            guard let self else { return }
            let all = ClipboardStore.items()
            let ordered = self.selectedMergeIDs.compactMap { id in
                all.first(where: { $0.id == id })?.text
            }
            guard !ordered.isEmpty else { return }
            let combined = ordered.joined(separator: "\n")
            self.isMergeMode = false
            self.selectedMergeIDs.removeAll()
            self.onInsertText?(combined)
            self.reloadContent()
        }
        subActionBar.addSubview(mergeCommitButton)

        clearUnpinnedButton.setTitle("清未置顶", for: .normal)
        clearUnpinnedButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        clearUnpinnedButton.actionHandler = { [weak self] in
            ClipboardStore.clearUnpinned()
            self?.selectedMergeIDs.removeAll()
            self?.reloadContent()
        }
        subActionBar.addSubview(clearUnpinnedButton)

        clearDraftsButton.setTitle("清空草稿", for: .normal)
        clearDraftsButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        clearDraftsButton.isHidden = true
        clearDraftsButton.actionHandler = { [weak self] in
            DraftRecoveryStore.clearAll()
            self?.reloadContent()
        }
        subActionBar.addSubview(clearDraftsButton)

        backButton.setTitle("返回", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        backButton.actionHandler = { [weak self] in self?.onClose?() }
        subActionBar.addSubview(backButton)

        scrollView.showsVerticalScrollIndicator = true
        addSubview(scrollView)

        listStack.axis = .vertical
        listStack.spacing = 8
        listStack.alignment = .fill
        scrollView.addSubview(listStack)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pasteTarget.frame = CGRect(x: 0, y: 0, width: 1, height: 1)

        let pad: CGFloat = 8
        headerStack.frame = CGRect(x: pad, y: 6, width: bounds.width - pad * 2, height: 30)

        let subY = headerStack.frame.maxY + 6
        subActionBar.frame = CGRect(x: pad, y: subY, width: bounds.width - pad * 2, height: 30)
        backButton.frame = CGRect(x: subActionBar.bounds.width - 54, y: 0, width: 54, height: 28)

        if let pasteNowControl {
            pasteNowControl.frame = CGRect(x: 0, y: 0, width: 108, height: 28)
        }
        if isMergeMode {
            mergeToggleButton.frame = CGRect(x: 0, y: 0, width: 56, height: 28)
            mergeCommitButton.frame = CGRect(x: 62, y: 0, width: min(140, max(92, backButton.frame.minX - 68)), height: 28)
        } else {
            mergeToggleButton.frame = CGRect(x: 114, y: 0, width: 50, height: 28)
            clearUnpinnedButton.frame = CGRect(x: 170, y: 0, width: 68, height: 28)
        }
        clearDraftsButton.frame = CGRect(x: 0, y: 0, width: 76, height: 28)

        let scrollY = subActionBar.frame.maxY + 6
        scrollView.frame = CGRect(x: 0, y: scrollY, width: bounds.width, height: max(40, bounds.height - scrollY - 4))

        let targetW = max(100, bounds.width - pad * 2)
        let fitSize = listStack.systemLayoutSizeFitting(
            CGSize(width: targetW, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        listStack.frame = CGRect(x: pad, y: 2, width: targetW, height: fitSize.height)
        scrollView.contentSize = CGSize(width: bounds.width, height: fitSize.height + 12)
    }

    func configure(theme: ResolvedTheme, activeFontStyle: StylishFontStyle, initialTab: Tab? = nil) {
        self.theme = theme
        self.activeFontStyle = activeFontStyle
        if let initialTab {
            self.currentTab = initialTab
        }
        backgroundColor = theme.canvasTop.withAlphaComponent(0.96)
        backButton.backgroundColor = theme.specialKeyFill
        backButton.setTitleColor(theme.keyText, for: .normal)
        backButton.layer.cornerRadius = 8
        backButton.layer.cornerCurve = .continuous

        for btn in [clearUnpinnedButton, clearDraftsButton] {
            btn.backgroundColor = theme.specialKeyFill
            btn.setTitleColor(theme.keyHintText, for: .normal)
            btn.layer.cornerRadius = 8
            btn.layer.cornerCurve = .continuous
        }

        mergeToggleButton.layer.cornerRadius = 8
        mergeToggleButton.layer.cornerCurve = .continuous
        mergeCommitButton.backgroundColor = theme.accentFill
        mergeCommitButton.setTitleColor(theme.accentText, for: .normal)
        mergeCommitButton.layer.cornerRadius = 8
        mergeCommitButton.layer.cornerCurve = .continuous

        rebuildPasteControl(theme: theme)
        rebuildHeader()
        reloadContent()
    }

    private func rebuildPasteControl(theme: ResolvedTheme) {
        pasteNowControl?.removeFromSuperview()
        var cfg = UIPasteControl.Configuration()
        cfg.displayMode = .iconAndLabel
        cfg.cornerStyle = .capsule
        cfg.baseBackgroundColor = theme.accentFill
        cfg.baseForegroundColor = theme.accentText
        let control = UIPasteControl(configuration: cfg)
        control.target = pasteTarget
        subActionBar.addSubview(control)
        pasteNowControl = control
    }

    private func rebuildHeader() {
        headerStack.arrangedSubviews.forEach {
            headerStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }
        for tab in Tab.allCases {
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(tab.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            let active = (tab == currentTab)
            btn.backgroundColor = active ? theme.accentFill : theme.specialKeyFill
            btn.setTitleColor(active ? theme.accentText : theme.keyText, for: .normal)
            btn.layer.cornerRadius = 8
            btn.layer.cornerCurve = .continuous
            btn.actionHandler = { [weak self] in
                guard let self else { return }
                self.currentTab = tab
                if tab != .history {
                    self.isMergeMode = false
                    self.selectedMergeIDs.removeAll()
                }
                self.rebuildHeader()
                self.reloadContent()
                self.scrollView.setContentOffset(.zero, animated: false)
            }
            headerStack.addArrangedSubview(btn)
        }
    }

    func reloadContent() {
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }

        let showHistoryControls = (currentTab == .history)
        pasteNowControl?.isHidden = !showHistoryControls || isMergeMode
        mergeToggleButton.isHidden = !showHistoryControls
        clearUnpinnedButton.isHidden = !showHistoryControls || isMergeMode
        mergeCommitButton.isHidden = !(showHistoryControls && isMergeMode)
        clearDraftsButton.isHidden = (currentTab != .drafts)

        mergeToggleButton.setTitle(isMergeMode ? "取消" : "拼段", for: .normal)
        mergeToggleButton.backgroundColor = isMergeMode ? theme.accentFill.withAlphaComponent(0.18) : theme.specialKeyFill
        mergeToggleButton.setTitleColor(isMergeMode ? theme.candidateHighlight : theme.keyText, for: .normal)
        mergeCommitButton.setTitle("合并上屏 (\(selectedMergeIDs.count))", for: .normal)
        mergeCommitButton.isEnabled = !selectedMergeIDs.isEmpty
        mergeCommitButton.alpha = selectedMergeIDs.isEmpty ? 0.45 : 1.0

        switch currentTab {
        case .history:
            let items = ClipboardStore.items()
            if items.isEmpty {
                listStack.addArrangedSubview(makeEmptyLabel("暂无剪贴板记录\n点击左上角按钮可直接读取当前系统剪贴板（零弹窗）", theme: theme))
            } else {
                for item in items {
                    listStack.addArrangedSubview(makeClipboardRow(item: item, theme: theme))
                }
            }

        case .cards:
            let cards = PersonalFillCardStore.load()
            if cards.isEmpty {
                listStack.addArrangedSubview(makeEmptyLabel("还没有常用速填名片\n在主 App「剪贴板 → 个人速填名片夹」新建，或在剪贴板里点「+存名片」一键收藏\n收藏后在任意输入框敲 vdz / vkp 也能秒调", theme: theme))
            } else {
                for card in cards {
                    listStack.addArrangedSubview(makePersonalCardRow(card: card, theme: theme))
                }
            }

        case .drafts:
            let drafts = DraftRecoveryStore.load()
            if drafts.isEmpty {
                listStack.addArrangedSubview(makeEmptyLabel("🛟 草稿防丢黑匣子目前为空\n打满 18 字以上长回复会自动在本地保存 24 小时（绝不记录密码框与无痕模式，永不上云）", theme: theme))
            } else {
                for rec in drafts {
                    listStack.addArrangedSubview(makeDraftRow(record: rec, theme: theme))
                }
            }

        case .scripts:
            listStack.addArrangedSubview(makeScriptCategoryStrip(theme: theme))
            let scripts = SocialScriptBank.filter(category: selectedScriptCategory)
            for script in scripts {
                listStack.addArrangedSubview(makeScriptRow(script, theme: theme))
            }

        case .phrases:
            listStack.addArrangedSubview(makeQuickStampRow(theme: theme))
            let phrases = QuickPhraseStore.load()
            for phrase in phrases {
                listStack.addArrangedSubview(makePhraseRow(phrase: phrase, theme: theme))
            }
            listStack.addArrangedSubview(makeFunWorkshopSection(theme: theme))
        }
        setNeedsLayout()
    }

    // MARK: - 1. 剪贴板行（防诈 + 净链 + 地址开票单字段速填 + 一键存名片 + 多选拼段）

    private func makeClipboardRow(item: ClipboardItem, theme: ResolvedTheme) -> UIView {
        let card = UIView()
        let isSelectedForMerge = selectedMergeIDs.contains(item.id)
        card.backgroundColor = isSelectedForMerge
            ? theme.accentFill.withAlphaComponent(0.16)
            : theme.keyFill.withAlphaComponent(0.92)
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous
        if isSelectedForMerge {
            card.layer.borderWidth = 1.0
            card.layer.borderColor = theme.accentFill.cgColor
        }

        let rowStack = UIStackView()
        rowStack.axis = .vertical
        rowStack.spacing = 6
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            rowStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            rowStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            rowStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
        ])

        let textButton = ActionClosureButton(type: .system)
        textButton.contentHorizontalAlignment = .left
        textButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        textButton.titleLabel?.numberOfLines = 2
        textButton.setTitleColor(theme.keyText, for: .normal)
        let mergePrefix: String
        if isMergeMode {
            if let idx = selectedMergeIDs.firstIndex(of: item.id) {
                mergePrefix = "[\(idx + 1)] "
            } else {
                mergePrefix = "○ "
            }
        } else {
            mergePrefix = ""
        }
        textButton.setTitle(mergePrefix + item.text, for: .normal)
        textButton.actionHandler = { [weak self] in
            guard let self else { return }
            if self.isMergeMode {
                if let idx = self.selectedMergeIDs.firstIndex(of: item.id) {
                    self.selectedMergeIDs.remove(at: idx)
                } else if self.selectedMergeIDs.count < 8 {
                    self.selectedMergeIDs.append(item.id)
                }
                self.reloadContent()
            } else {
                self.onInsertText?(item.text)
            }
        }
        rowStack.addArrangedSubview(textButton)

        let scamReport = CommunicationGuardEngine.analyzeScam(item.text)
        let parsedInfo = SmartInfoParser.parse(item.text)
        let linkReport = LinkPrivacyCleaner.clean(item.text)

        let metaStack = UIStackView()
        metaStack.axis = .horizontal
        metaStack.spacing = 5
        metaStack.alignment = .center

        let badge = UILabel()
        badge.text = (item.isPinned ? "📌 " : "") + item.category.badgeText
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = theme.candidateHighlight
        metaStack.addArrangedSubview(badge)

        if scamReport.isRisky {
            let warnLbl = UILabel()
            warnLbl.text = scamReport.level == .highRisk ? "🚨防诈" : "⚠️风险"
            warnLbl.font = .systemFont(ofSize: 10.5, weight: .bold)
            warnLbl.textColor = scamReport.level == .highRisk ? .systemRed : .systemOrange
            metaStack.addArrangedSubview(warnLbl)
        }

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metaStack.addArrangedSubview(spacer)

        if let code = item.extractedCode {
            let otpBtn = makeMiniPill("填入 \(code)", bg: theme.accentFill, fg: theme.accentText) { [weak self] in
                self?.onInsertText?(code)
            }
            metaStack.addArrangedSubview(otpBtn)
        }

        if linkReport.hasChanges, let cleanTarget = linkReport.extractedCleanURL ?? (linkReport.cleanedText.isEmpty ? nil : linkReport.cleanedText) {
            let cleanBtn = makeMiniPill("🧼净链", bg: theme.accentFill.withAlphaComponent(0.18), fg: theme.candidateHighlight) { [weak self] in
                self?.onInsertText?(cleanTarget)
            }
            metaStack.addArrangedSubview(cleanBtn)
        }

        let aiBtn = makeMiniPill("AI回复", bg: theme.accentFill.withAlphaComponent(0.16), fg: theme.candidateHighlight) { [weak self] in
            self?.onSendToAI?(item.text)
        }
        let bangBtn = makeMiniPill(explodedItemID == item.id ? "收起" : "炸词", bg: theme.specialKeyFill, fg: theme.keyText) { [weak self] in
            guard let self else { return }
            self.explodedItemID = (self.explodedItemID == item.id) ? nil : item.id
            self.reloadContent()
        }
        let pinBtn = makeMiniPill(item.isPinned ? "解置" : "置顶", bg: theme.specialKeyFill, fg: theme.keyText) { [weak self] in
            ClipboardStore.togglePin(id: item.id)
            self?.reloadContent()
        }
        let delBtn = makeMiniPill("删", bg: UIColor.systemRed.withAlphaComponent(0.14), fg: .systemRed) { [weak self] in
            ClipboardStore.delete(id: item.id)
            self?.selectedMergeIDs.removeAll { $0 == item.id }
            self?.reloadContent()
        }
        [aiBtn, bangBtn, pinBtn, delBtn].forEach { metaStack.addArrangedSubview($0) }
        rowStack.addArrangedSubview(metaStack)

        // 万能结构化拆解单字段速填条 + 一键存名片
        if let parsedInfo, !parsedInfo.fields.isEmpty {
            rowStack.addArrangedSubview(makeSmartInfoStripView(parsedInfo, rawText: item.text, theme: theme))
        }

        if explodedItemID == item.id {
            rowStack.addArrangedSubview(makeBigBangChipsView(for: item.text, theme: theme))
        }
        return card
    }

    private func makeSmartInfoStripView(_ parsed: SmartInfoParseResult, rawText: String, theme: ResolvedTheme) -> UIView {
        let stripScroll = LingxiScrollView()
        stripScroll.showsHorizontalScrollIndicator = false
        stripScroll.showsVerticalScrollIndicator = false
        stripScroll.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let stripStack = UIStackView()
        stripStack.axis = .horizontal
        stripStack.alignment = .center
        stripStack.spacing = 6
        stripStack.translatesAutoresizingMaskIntoConstraints = false
        stripScroll.addSubview(stripStack)

        NSLayoutConstraint.activate([
            stripStack.topAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.topAnchor),
            stripStack.bottomAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.bottomAnchor),
            stripStack.leadingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.leadingAnchor),
            stripStack.trailingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.trailingAnchor),
            stripStack.heightAnchor.constraint(equalTo: stripScroll.frameLayoutGuide.heightAnchor),
        ])

        let kindLabel = UILabel()
        kindLabel.text = parsed.kind.badgeLabel
        kindLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        kindLabel.textColor = theme.keyHintText
        stripStack.addArrangedSubview(kindLabel)

        for field in parsed.fields {
            let pill = makeMiniPill(
                "填\(field.label)",
                bg: theme.accentFill.withAlphaComponent(0.14),
                fg: theme.candidateHighlight
            ) { [weak self] in
                self?.onInsertText?(field.value)
            }
            pill.accessibilityLabel = "单独填入\(field.label)：\(field.value)"
            stripStack.addArrangedSubview(pill)
        }

        let saveCardPill = makeMiniPill("+存名片", bg: theme.specialKeyFill, fg: theme.keyText) { [weak self] in
            if let card = PersonalFillCardStore.buildCardFromRawText(rawText) {
                PersonalFillCardStore.upsert(card)
                self?.currentTab = .cards
                self?.rebuildHeader()
                self?.reloadContent()
            }
        }
        stripStack.addArrangedSubview(saveCardPill)
        return stripScroll
    }

    // MARK: - 2. 个人速填名片夹卡片

    private func makePersonalCardRow(card: PersonalFillCard, theme: ResolvedTheme) -> UIView {
        let box = UIView()
        box.backgroundColor = theme.keyFill.withAlphaComponent(0.92)
        box.layer.cornerRadius = 10
        box.layer.cornerCurve = .continuous

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = 6
        vStack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            vStack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            vStack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            vStack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
        ])

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 6

        let titleLbl = UILabel()
        titleLbl.text = "\(card.kind.badgePrefix) \(card.title)"
        titleLbl.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLbl.textColor = theme.keyText
        header.addArrangedSubview(titleLbl)

        let sp = UIView()
        sp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(sp)

        let fullBtn = makeMiniPill("填整张", bg: theme.accentFill, fg: theme.accentText) { [weak self] in
            self?.onInsertText?(card.formattedFullText)
        }
        header.addArrangedSubview(fullBtn)
        vStack.addArrangedSubview(header)

        let previewLbl = UILabel()
        previewLbl.text = card.compactOneLine
        previewLbl.font = .systemFont(ofSize: 12, weight: .regular)
        previewLbl.textColor = theme.keyHintText
        previewLbl.numberOfLines = 1
        vStack.addArrangedSubview(previewLbl)

        let stripScroll = LingxiScrollView()
        stripScroll.showsHorizontalScrollIndicator = false
        stripScroll.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let stripStack = UIStackView()
        stripStack.axis = .horizontal
        stripStack.alignment = .center
        stripStack.spacing = 6
        stripStack.translatesAutoresizingMaskIntoConstraints = false
        stripScroll.addSubview(stripStack)
        NSLayoutConstraint.activate([
            stripStack.topAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.topAnchor),
            stripStack.bottomAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.bottomAnchor),
            stripStack.leadingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.leadingAnchor),
            stripStack.trailingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.trailingAnchor),
            stripStack.heightAnchor.constraint(equalTo: stripScroll.frameLayoutGuide.heightAnchor),
        ])

        for field in card.nonEmptyFields {
            let pill = makeMiniPill(
                "填\(field.label)",
                bg: theme.accentFill.withAlphaComponent(0.14),
                fg: theme.candidateHighlight
            ) { [weak self] in
                self?.onInsertText?(field.value)
            }
            stripStack.addArrangedSubview(pill)
        }
        vStack.addArrangedSubview(stripScroll)
        return box
    }

    // MARK: - 3. 草稿防丢黑匣子卡片

    private func makeDraftRow(record: SavedDraftRecord, theme: ResolvedTheme) -> UIView {
        let card = UIView()
        card.backgroundColor = theme.keyFill.withAlphaComponent(0.92)
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = 6
        vStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            vStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            vStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            vStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
        ])

        let textBtn = ActionClosureButton(type: .system)
        textBtn.contentHorizontalAlignment = .left
        textBtn.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .regular)
        textBtn.titleLabel?.numberOfLines = 3
        textBtn.setTitleColor(theme.keyText, for: .normal)
        textBtn.setTitle(record.singleLinePreview, for: .normal)
        textBtn.actionHandler = { [weak self] in
            self?.onInsertText?(record.text)
        }
        vStack.addArrangedSubview(textBtn)

        let meta = UIStackView()
        meta.axis = .horizontal
        meta.spacing = 6
        meta.alignment = .center

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let infoLbl = UILabel()
        infoLbl.text = "🛟 \(record.charCount)字 · \(fmt.string(from: record.updatedAt))"
        infoLbl.font = .systemFont(ofSize: 11, weight: .semibold)
        infoLbl.textColor = theme.candidateHighlight
        meta.addArrangedSubview(infoLbl)

        let sp = UIView()
        sp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        meta.addArrangedSubview(sp)

        let restoreBtn = makeMiniPill("一键捞回", bg: theme.accentFill, fg: theme.accentText) { [weak self] in
            self?.onInsertText?(record.text)
        }
        let delBtn = makeMiniPill("删", bg: UIColor.systemRed.withAlphaComponent(0.14), fg: .systemRed) { [weak self] in
            DraftRecoveryStore.delete(id: record.id)
            self?.reloadContent()
        }
        meta.addArrangedSubview(restoreBtn)
        meta.addArrangedSubview(delBtn)
        vStack.addArrangedSubview(meta)
        return card
    }

    // MARK: - 4. 离线高情商救场话术口袋

    private func makeScriptCategoryStrip(theme: ResolvedTheme) -> UIView {
        let stripScroll = LingxiScrollView()
        stripScroll.showsHorizontalScrollIndicator = false
        stripScroll.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stripScroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: stripScroll.frameLayoutGuide.heightAnchor),
        ])

        for cat in SocialScriptCategory.allCases {
            let active = (cat == selectedScriptCategory)
            let btn = makeMiniPill(
                cat.rawValue,
                bg: active ? theme.accentFill : theme.specialKeyFill,
                fg: active ? theme.accentText : theme.keyText
            ) { [weak self] in
                self?.selectedScriptCategory = cat
                self?.reloadContent()
            }
            stack.addArrangedSubview(btn)
        }
        return stripScroll
    }

    private func makeScriptRow(_ script: SocialScriptItem, theme: ResolvedTheme) -> UIView {
        let card = UIView()
        card.backgroundColor = theme.keyFill.withAlphaComponent(0.92)
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = 4
        vStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            vStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            vStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            vStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
        ])

        let head = UILabel()
        head.text = "【\(script.scenario) · \(script.tone.rawValue)】"
        head.font = .systemFont(ofSize: 11.5, weight: .semibold)
        head.textColor = theme.candidateHighlight
        vStack.addArrangedSubview(head)

        let bodyBtn = ActionClosureButton(type: .system)
        bodyBtn.contentHorizontalAlignment = .left
        bodyBtn.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .regular)
        bodyBtn.titleLabel?.numberOfLines = 3
        bodyBtn.setTitleColor(theme.keyText, for: .normal)
        bodyBtn.setTitle(script.text, for: .normal)
        bodyBtn.actionHandler = { [weak self] in
            self?.onInsertText?(script.text)
        }
        vStack.addArrangedSubview(bodyBtn)
        return card
    }

    // MARK: - 5. BigBang / 常用短语 / 趣味工具

    private func makeBigBangChipsView(for text: String, theme: ResolvedTheme) -> UIView {
        let tokens = BigBangTokenizer.tokenize(text)
        let container = FlowChipsView()
        let maxW = max(140, bounds.width - 36)
        container.configure(tokens: tokens, theme: theme, availableWidth: maxW) { [weak self] chosen in
            self?.onInsertText?(chosen)
        }
        return container
    }

    private func makeQuickStampRow(theme: ResolvedTheme) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 6

        let dateBtn = makeMiniPill("📅 今天日期", bg: theme.accentFill.withAlphaComponent(0.14), fg: theme.candidateHighlight) { [weak self] in
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "zh_CN")
            fmt.dateFormat = "yyyy年M月d日 EEEE"
            self?.onInsertText?(fmt.string(from: Date()))
        }
        dateBtn.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let timeBtn = makeMiniPill("⏰ 当前时间", bg: theme.accentFill.withAlphaComponent(0.14), fg: theme.candidateHighlight) { [weak self] in
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            self?.onInsertText?(fmt.string(from: Date()))
        }
        timeBtn.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let geo = GeoLocationContext.load()
        let locText = geo.isPopulated ? geo.compactLocationLabel : "我的位置"
        let locTitle = geo.isPopulated ? "📍 \(geo.shortCityName)" : "📍 位置"
        let locBtn = makeMiniPill(locTitle, bg: theme.accentFill.withAlphaComponent(0.14), fg: theme.candidateHighlight) { [weak self] in
            self?.onInsertText?(locText)
        }
        locBtn.heightAnchor.constraint(equalToConstant: 32).isActive = true

        [dateBtn, timeBtn, locBtn].forEach { row.addArrangedSubview($0) }
        return row
    }

    private func makePhraseRow(phrase: QuickPhrase, theme: ResolvedTheme) -> UIView {
        let card = ActionClosureButton(type: .system)
        card.backgroundColor = theme.keyFill.withAlphaComponent(0.88)
        card.layer.cornerRadius = 10
        card.contentHorizontalAlignment = .left
        card.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        card.titleLabel?.numberOfLines = 2
        card.setTitle("【\(phrase.category) · \(phrase.title)】\(phrase.content)", for: .normal)
        card.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .regular)
        card.setTitleColor(theme.keyText, for: .normal)
        card.actionHandler = { [weak self] in
            self?.onInsertText?(phrase.content)
        }
        return card
    }

    private func makeFunWorkshopSection(theme: ResolvedTheme) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 10

        let funTitle = UILabel()
        funTitle.text = "🎲 一键趣味上屏"
        funTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        funTitle.textColor = theme.candidateHighlight
        container.addArrangedSubview(funTitle)

        let funButtonsRow = UIStackView()
        funButtonsRow.axis = .horizontal
        funButtonsRow.distribution = .fillEqually
        funButtonsRow.spacing = 6
        let toys: [(String, () -> String)] = [
            ("🎲 骰子", { FunGenerator.rollDice() }),
            ("🪙 抛硬币", { FunGenerator.flipCoin() }),
            ("🍽️ 吃什么", { FunGenerator.randomMeal() }),
            ("🎋 今日签", { FunGenerator.randomFortune() }),
        ]
        for (title, gen) in toys {
            let btn = makeMiniPill(title, bg: theme.keyFill, fg: theme.keyText) { [weak self] in
                self?.onInsertText?(gen())
            }
            btn.heightAnchor.constraint(equalToConstant: 34).isActive = true
            funButtonsRow.addArrangedSubview(btn)
        }
        container.addArrangedSubview(funButtonsRow)

        if let latest = ClipboardStore.items().first?.text, !latest.isEmpty {
            let fmtTitle = UILabel()
            fmtTitle.text = "🛠️ 转换最近剪贴板并上屏"
            fmtTitle.font = .systemFont(ofSize: 13, weight: .semibold)
            fmtTitle.textColor = theme.candidateHighlight
            container.addArrangedSubview(fmtTitle)

            let fmtRow = UIStackView()
            fmtRow.axis = .horizontal
            fmtRow.distribution = .fillEqually
            fmtRow.spacing = 5
            let variant = LingxiSettings.load().traditionalVariant
            let transforms: [(String, (String) -> String)] = [
                ("净链", { let r = LinkPrivacyCleaner.clean($0); return r.extractedCleanURL ?? r.cleanedText }),
                ("排版", { OfflineTextLinter.autoFix($0) }),
                ("脱敏", { AIPrivacyShield.sanitize($0, customTerms: AIConfig.load().privacyCustomTerms).sanitizedText }),
                ("防限流", { OfflineTextLinter.autoReplacePlatformRisks($0) }),
                ("繁⇄简", {
                    let t = ChineseScriptConverter.toTraditional($0, variant: variant)
                    return t != $0 ? t : ChineseScriptConverter.toSimplified($0, normalizeRegionalTerms: true)
                }),
            ]
            for (title, fn) in transforms {
                let btn = makeMiniPill(title, bg: theme.specialKeyFill, fg: theme.keyText) { [weak self] in
                    self?.onInsertText?(fn(latest))
                }
                btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
                fmtRow.addArrangedSubview(btn)
            }
            container.addArrangedSubview(fmtRow)
        }

        let fontTitle = UILabel()
        fontTitle.text = "✨ 英文花样字体模式（开启后英文输入自动变形）"
        fontTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        fontTitle.textColor = theme.candidateHighlight
        container.addArrangedSubview(fontTitle)

        for style in StylishFontStyle.allCases {
            let active = (style == activeFontStyle)
            let btn = ActionClosureButton(type: .system)
            btn.backgroundColor = active ? theme.accentFill : theme.keyFill.withAlphaComponent(0.88)
            btn.setTitleColor(active ? theme.accentText : theme.keyText, for: .normal)
            btn.layer.cornerRadius = 9
            btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            btn.contentHorizontalAlignment = .left
            btn.setTitle("\(style.displayName)    \(style.previewSample)", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 14, weight: active ? .semibold : .regular)
            btn.actionHandler = { [weak self] in
                self?.activeFontStyle = style
                self?.onStylishFontChanged?(style)
                self?.reloadContent()
            }
            container.addArrangedSubview(btn)
        }

        return container
    }

    private func makeMiniPill(_ title: String, bg: UIColor, fg: UIColor, handler: @escaping () -> Void) -> ActionClosureButton {
        let btn = ActionClosureButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        btn.backgroundColor = bg
        btn.setTitleColor(fg, for: .normal)
        btn.layer.cornerRadius = 7
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        btn.actionHandler = handler
        return btn
    }

    private func makeEmptyLabel(_ text: String, theme: ResolvedTheme) -> UIView {
        let lbl = UILabel()
        lbl.text = text
        lbl.numberOfLines = 0
        lbl.textAlignment = .center
        lbl.font = .systemFont(ofSize: 13.5, weight: .regular)
        lbl.textColor = theme.keyHintText
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.heightAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
        return lbl
    }
}

/// 自适应流式折行词片容器（用于 BigBang 剪贴板炸词挑选）。
private final class FlowChipsView: UIView {
    private var chipButtons: [UIButton] = []
    private var heightConstraint: NSLayoutConstraint?

    func configure(tokens: [String], theme: ResolvedTheme, availableWidth: CGFloat, onTap: @escaping (String) -> Void) {
        subviews.forEach { $0.removeFromSuperview() }
        chipButtons.removeAll()
        for tok in tokens {
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(tok, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            btn.backgroundColor = theme.accentFill.withAlphaComponent(0.12)
            btn.setTitleColor(theme.candidateHighlight, for: .normal)
            btn.layer.cornerRadius = 7
            btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
            btn.actionHandler = { onTap(tok) }
            addSubview(btn)
            chipButtons.append(btn)
        }
        let h = layoutChips(width: availableWidth)
        if heightConstraint == nil {
            let hc = heightAnchor.constraint(equalToConstant: h)
            hc.priority = UILayoutPriority(999)
            hc.isActive = true
            heightConstraint = hc
        } else {
            heightConstraint?.constant = h
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 20 else { return }
        let h = layoutChips(width: bounds.width)
        if let heightConstraint, abs(heightConstraint.constant - h) > 1 {
            heightConstraint.constant = h
        }
    }

    @discardableResult
    private func layoutChips(width: CGFloat) -> CGFloat {
        guard width > 20, !chipButtons.isEmpty else { return 0 }
        var x: CGFloat = 0
        var y: CGFloat = 4
        let gap: CGFloat = 6
        let rowH: CGFloat = 28

        for btn in chipButtons {
            let w = min(width, max(28, btn.sizeThatFits(CGSize(width: width, height: rowH)).width))
            if x + w > width && x > 0 {
                x = 0
                y += rowH + gap
            }
            btn.frame = CGRect(x: x, y: y, width: w, height: rowH)
            x += w + gap
        }
        return y + rowH + 4
    }
}
