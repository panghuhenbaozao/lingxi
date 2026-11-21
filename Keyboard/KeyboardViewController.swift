import UIKit

/// 灵犀输入法容器根视图：实现 `UIInputViewAudioFeedback` 以支持系统原生按键音兜底。
private final class LingxiInputRootView: UIView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController {
    private static let toolbarHeight: CGFloat = 50

    private enum ActivePanel {
        case letters
        case numbers
        case symbolsEmoji
        case clipboard
        case textEditing
        case ai
        case quickSettings
    }

    // 核心引擎与服务
    private var engine: PinyinEngine?
    private let feedback = FeedbackManager()
    private let pasteMonitor = PasteboardMonitor()

    // 配置与外观
    private var settings = LingxiSettings.load()
    private var themeCustomization = ThemeCustomization.load()
    private var resolvedTheme = ResolvedTheme.resolve(isDarkAppearance: false, targetSize: CGSize(width: 430, height: 280))
    private var heightConstraint: NSLayoutConstraint?

    // 视图层级
    private let rootContainer = LingxiInputRootView()
    private let backdropView = KeyboardBackdropView()
    private lazy var toolbarView = TopToolbarView { [weak self] text in
        self?.handleCapturedPasteFromToolbar(text)
    }
    private let bodyContainer = UIView()
    private let lettersCanvas = KeyboardCanvasView()
    private let t9Canvas = T9KeyboardCanvasView()
    private let numberPad = NumberPadView()
    private let expandedCandidates = ExpandedCandidatesView()
    private let symbolEmojiPanel = SymbolEmojiPanelView()
    private let clipboardPanel = ClipboardPanelView()
    private let textEditingPanel = TextEditingPanelView()
    private let aiPanel = AIAssistantPanelView()
    private let quickSettingsPanel = QuickSettingsSheetView()

    // 中文/英文输入状态机
    private var activePanel: ActivePanel = .letters
    private var isEnglishMode = false
    private var shiftState: ShiftState = .lowercase
    private var rawComposing = ""
    private var lockedT9Syllables: [String] = []
    private var t9LeftSyllables: [String] = []
    private var currentTokens: [PinyinToken] = []
    private var currentCorrectedHint: String?
    private var currentCandidates: [PinyinCandidate] = []
    private var isCandidatesExpanded = false
    private var pendingPhraseSegments: [(word: String, py: String)] = []
    private var lastCommittedWord: String?

    // 表情拼音搜索态（紧凑结果条 + 字母键盘组合）
    private var isEmojiSearchMode = false
    private var emojiSearchQuery = ""
    private var lettersTopConstraint: NSLayoutConstraint?
    private var symbolFullBottomConstraint: NSLayoutConstraint?
    private var symbolCompactHeightConstraint: NSLayoutConstraint?

    // 边打边译状态（译：中文边打边流式译为目标语种）
    private var isTranslateMode = false
    private var translateSourceBuffer = ""
    private var translatePreviewText = ""
    private var translateIsStreaming = false
    private var translateErrorText: String?
    private var translateDebounceWorkItem: DispatchWorkItem?
    private var translateTask: Task<Void, Never>?
    private var translateCache: [String: String] = [:]
    private var translateCacheOrder: [String] = []
    private static let maxTranslateCacheEntries = 64
    private lazy var translateClient = AIClient(timeout: 20)

    // 英文输入联想状态
    private var englishComposing = ""

    // AI 自由提问本地草稿模式（避免键盘内置 TextField 抢占宿主 FirstResponder）
    private var aiPromptDraft: String?

    // 退格重选（上屏后按 ⌫ 立刻撤销文本、恢复拼音，并同步回退 UserLexicon 误学记录）
    private struct SelectionUndoRecord {
        let committedText: String
        let rawComposing: String
        let prevLastCommittedWord: String?
        let inTranslateBuffer: Bool
        let learnRecord: UserLearnRecord?
        let extraLearnRecord: UserLearnRecord?
        let createdAt: TimeInterval = CACurrentMediaTime()
        /// 退格重选仅在上屏后极短时间窗内有效（对齐微信/Gboard 手感），
        /// 超时后按普通删除处理，避免用户正常删字时拼音被意外恢复回来
        static let validityWindow: TimeInterval = 6.0
        var isExpired: Bool { CACurrentMediaTime() - createdAt > Self.validityWindow }
    }
    private var lastSelectionUndo: SelectionUndoRecord?

    // 智能中文弯引号配对状态、五笔 86、U 模式拆字/笔画 & 滑行输入状态
    private var openDoubleQuote = false
    private var openSingleQuote = false
    private var wubiEmptyCode = false
    private var wubiDisplayBuffer: String?
    private var uModeDisplayBuffer: String?
    private var isLastInputFromGlide = false

    // 撤销删除与双击空格句号
    private var undoBuffer: (deletedText: String, wasComposing: Bool)?
    private var undoHideTimer: Timer?
    private var lastSpaceTapTime: CFTimeInterval = 0
    private var lastInternalEditTime: CFTimeInterval = 0
    private var lastAdaptedTraitSignature: String = ""

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        resolvedTheme = ResolvedTheme.resolve(
            customization: themeCustomization,
            isDarkAppearance: isDarkInterface,
            targetSize: CGSize(width: 430, height: 280)
        )
        setupHierarchy()
        wireCallbacks()
        applyThemeAndSettings()
        preloadEngine()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadConfigurationIfNeeded()
        adaptToHostTraits()
        feedback.prepare()
        refreshClipboardState()
        updateReturnKeyAppearance()
        autoCapitalizeIfNeeded()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updatePreferredHeight()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let styleChanged = previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle
        let sizeClassChanged = previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass
            || previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass
        if sizeClassChanged {
            updatePreferredHeight()
        }
        if styleChanged {
            resolvedTheme = ResolvedTheme.resolve(
                customization: themeCustomization,
                isDarkAppearance: isDarkInterface,
                targetSize: view.bounds.size.width > 10 ? view.bounds.size : CGSize(width: 430, height: 280)
            )
            applyThemeAndSettings()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updatePreferredHeight()
        })
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        engine?.releaseMemory()
        translateCache.removeAll(keepingCapacity: false)
        translateCacheOrder.removeAll(keepingCapacity: false)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let isExternalChange = (CACurrentMediaTime() - lastInternalEditTime) >= 0.22
        if isExternalChange && aiPromptDraft == nil {
            lastSelectionUndo = nil
            openDoubleQuote = false
            openSingleQuote = false
            adaptToHostTraits()
            if !rawComposing.isEmpty || !englishComposing.isEmpty {
                clearAllComposing()
                refreshUI()
            } else {
                updateIdleSuggestions()
            }
            autoCapitalizeIfNeeded()
        }
        updateReturnKeyAppearance()
        refreshClipboardState()
    }

    // MARK: - 视图初始化

    private func setupHierarchy() {
        rootContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootContainer)
        NSLayoutConstraint.activate([
            rootContainer.topAnchor.constraint(equalTo: view.topAnchor),
            rootContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rootContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        backdropView.translatesAutoresizingMaskIntoConstraints = false
        rootContainer.addSubview(backdropView)
        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor),
            backdropView.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
        ])

        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        rootContainer.addSubview(toolbarView)

        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        rootContainer.addSubview(bodyContainer)

        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: Self.toolbarHeight),

            bodyContainer.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            bodyContainer.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            bodyContainer.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor),
        ])

        let subpanels: [UIView] = [
            lettersCanvas,
            t9Canvas,
            numberPad,
            expandedCandidates,
            symbolEmojiPanel,
            clipboardPanel,
            textEditingPanel,
            aiPanel,
            quickSettingsPanel,
        ]
        for panel in subpanels {
            panel.translatesAutoresizingMaskIntoConstraints = false
            bodyContainer.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            ])
            if panel === lettersCanvas {
                let top = panel.topAnchor.constraint(equalTo: bodyContainer.topAnchor)
                self.lettersTopConstraint = top
                NSLayoutConstraint.activate([
                    top,
                    panel.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
                ])
            } else if panel === symbolEmojiPanel {
                let fullBottom = panel.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor)
                self.symbolFullBottomConstraint = fullBottom
                self.symbolCompactHeightConstraint = panel.heightAnchor.constraint(equalToConstant: 80)
                NSLayoutConstraint.activate([
                    panel.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
                    fullBottom,
                ])
            } else {
                NSLayoutConstraint.activate([
                    panel.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
                    panel.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
                ])
            }
        }

        let totalH = Self.toolbarHeight + CGFloat(settings.heightPreset.bodyHeight)
        let hc = view.heightAnchor.constraint(equalToConstant: totalH)
        hc.priority = UILayoutPriority(999)
        hc.isActive = true
        self.heightConstraint = hc

        updateVisiblePanel()
    }

    private func preloadEngine() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let eng = PinyinEngine()
            eng.userLexicon.pruneStaleEntries()
            DispatchQueue.main.async {
                self?.engine = eng
                if self?.rawComposing.isEmpty == false || self?.englishComposing.isEmpty == false {
                    self?.recomputeCandidates()
                }
            }
        }
    }

    private func reloadConfigurationIfNeeded() {
        let newSettings = LingxiSettings.load()
        let newTheme = ThemeCustomization.load()
        if newSettings != settings || newTheme != themeCustomization {
            let schemeOrLayoutChanged = newSettings.inputScheme != settings.inputScheme || newSettings.layoutMode != settings.layoutMode
            settings = newSettings
            themeCustomization = newTheme
            resolvedTheme = ResolvedTheme.resolve(
                customization: themeCustomization,
                isDarkAppearance: isDarkInterface,
                targetSize: view.bounds.size.width > 10 ? view.bounds.size : CGSize(width: 430, height: 280)
            )
            if schemeOrLayoutChanged {
                clearAllComposing()
            }
            updatePreferredHeight()
            applyThemeAndSettings()
        }
    }

    private var isDarkInterface: Bool {
        traitCollection.userInterfaceStyle == .dark
    }

    private var isUsingT9Layout: Bool {
        settings.layoutMode == .t9Nine && !isEnglishMode && !settings.inputScheme.isWubi
    }

    private var activeContextBeforeCursor: String? {
        aiPromptDraft ?? (isTranslateMode ? translateSourceBuffer : textDocumentProxy.documentContextBeforeInput)
    }

    private func resolveEmojiSearchWords(for query: String) -> [String] {
        guard !query.isEmpty, let engine else { return [] }
        var searchSettings = settings
        searchSettings.inputScheme = .quanpin
        searchSettings.smartEnglishCandidate = false
        let res = engine.query(raw: query, settings: searchSettings, contextBeforeCursor: nil, limit: 8)
        return res.candidates.map(\.word)
    }

    private var isSecureField: Bool {
        textDocumentProxy.isSecureTextEntry == true
    }

    /// 密码框、邮箱、网址输入框中不自动插入中英/中数盘古空格（对齐 WowType `autospace.rs`）。
    private var shouldAllowPanguSpace: Bool {
        guard !isSecureField else { return false }
        let kbType = textDocumentProxy.keyboardType ?? .default
        switch kbType {
        case .emailAddress, .URL, .webSearch, .twitter, .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad:
            return false
        default:
            return true
        }
    }

    /// 根据宿主输入框的 `keyboardType` 与密码属性自动适配面板与隐私策略。
    private func adaptToHostTraits() {
        let kbType = textDocumentProxy.keyboardType ?? .default
        let sig = "\(kbType.rawValue)-\(isSecureField)"
        guard sig != lastAdaptedTraitSignature else { return }
        lastAdaptedTraitSignature = sig

        switch kbType {
        case .numberPad, .phonePad, .decimalPad, .numbersAndPunctuation, .asciiCapableNumberPad:
            if activePanel == .letters {
                switchToPanel(.numbers)
            }
        case .emailAddress, .URL, .asciiCapable, .twitter, .webSearch:
            if activePanel == .numbers {
                switchToPanel(.letters)
            }
            if !isEnglishMode {
                isEnglishMode = true
                shiftState = .lowercase
                refreshUI()
            }
        default:
            if isSecureField && !isEnglishMode {
                isEnglishMode = true
                shiftState = .lowercase
                refreshUI()
            }
        }
    }

    private func updatePreferredHeight() {
        let isCompactLandscape = traitCollection.verticalSizeClass == .compact
        let isRegularPad = traitCollection.horizontalSizeClass == .regular && traitCollection.verticalSizeClass == .regular
        let numRowExtra: CGFloat = (settings.showNumberRow && !isUsingT9Layout) ? (isCompactLandscape ? 22 : 34) : 0
        var baseH = CGFloat(settings.heightPreset.bodyHeight) + numRowExtra
        if isCompactLandscape {
            // iPhone 横屏自动收紧键盘高度，防止遮挡宿主 App 输入框
            baseH = min(baseH, settings.showNumberRow ? 184 : 168)
        } else if isRegularPad {
            baseH += 26
        }
        let bodyH: CGFloat
        if activePanel == .ai || activePanel == .clipboard || isEmojiSearchMode {
            bodyH = isCompactLandscape ? max(baseH, 184) : max(baseH, 252)
        } else {
            bodyH = baseH
        }
        heightConstraint?.constant = Self.toolbarHeight + bodyH
    }

    // MARK: - 事件绑定

    private func wireCallbacks() {
        toolbarView.onSelectCandidate = { [weak self] idx in
            self?.selectCandidate(at: idx)
        }
        toolbarView.onLongPressCandidate = { [weak self] idx, _ in
            self?.handleLongPressCandidate(at: idx)
        }
        toolbarView.onToggleExpandCandidates = { [weak self] in
            guard let self else { return }
            self.isCandidatesExpanded.toggle()
            self.expandedCandidates.update(candidates: self.currentCandidates)
            self.updateVisiblePanel()
            self.refreshToolbar()
        }
        toolbarView.onAction = { [weak self] action in
            self?.handleToolbarAction(action)
        }

        expandedCandidates.onSelectCandidate = { [weak self] idx in
            self?.selectCandidate(at: idx)
        }
        expandedCandidates.onLongPressCandidate = { [weak self] idx, _ in
            self?.handleLongPressCandidate(at: idx)
        }
        expandedCandidates.onClose = { [weak self] in
            guard let self else { return }
            self.isCandidatesExpanded = false
            self.updateVisiblePanel()
            self.refreshToolbar()
        }

        lettersCanvas.onEvent = { [weak self] event in
            self?.handleCanvasEvent(event)
        }

        t9Canvas.onEvent = { [weak self] event in
            self?.handleT9Event(event)
        }

        numberPad.onEvent = { [weak self] event in
            self?.handleNumberPadEvent(event)
        }

        symbolEmojiPanel.onInsert = { [weak self] text in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .letter, settings: self.settings, hasFullAccess: self.hasFullAccess)
            self.insertFinalText(text, checkPairing: true)
        }
        symbolEmojiPanel.onBackspace = { [weak self] in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .delete, settings: self.settings, hasFullAccess: self.hasFullAccess)
            self.performBackspace(isRepeat: false)
        }
        symbolEmojiPanel.onClose = { [weak self] in
            self?.switchToPanel(.letters)
        }
        symbolEmojiPanel.onRequestSearchMode = { [weak self] in
            guard let self else { return }
            self.clearAllComposing()
            self.isEmojiSearchMode = true
            self.emojiSearchQuery = ""
            self.activePanel = .letters
            self.symbolEmojiPanel.setSearchMode(true, query: "")
            self.updatePreferredHeight()
            self.updateVisiblePanel()
            self.refreshUI()
        }
        symbolEmojiPanel.onExitSearchMode = { [weak self] in
            guard let self else { return }
            self.isEmojiSearchMode = false
            self.emojiSearchQuery = ""
            self.symbolEmojiPanel.setSearchMode(false, query: "")
            self.updatePreferredHeight()
            self.switchToPanel(.symbolsEmoji)
        }

        clipboardPanel.onInsertText = { [weak self] text in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .letter, settings: self.settings, hasFullAccess: self.hasFullAccess)
            self.insertFinalText(text, checkPairing: false)
        }
        clipboardPanel.onSendToAI = { [weak self] text in
            self?.openAIPanel(preferredAction: .replyClipboard, explicitClipboard: text)
        }
        clipboardPanel.onStylishFontChanged = { [weak self] style in
            guard let self else { return }
            self.settings.stylishFontID = style.rawValue
            self.settings.save()
        }
        clipboardPanel.onClose = { [weak self] in
            self?.switchToPanel(.letters)
        }

        textEditingPanel.onAction = { [weak self] action in
            self?.handleTextEditingAction(action)
        }

        aiPanel.onInsertText = { [weak self] text in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .modifier, settings: self.settings, hasFullAccess: self.hasFullAccess)
            self.aiPromptDraft = nil
            self.insertDirectlyIntoHost(text)
            self.switchToPanel(.letters)
        }
        aiPanel.onReplaceBeforeCursor = { [weak self] deleteCount, replacement in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .modifier, settings: self.settings, hasFullAccess: self.hasFullAccess)
            self.aiPromptDraft = nil
            self.performEdit {
                for _ in 0..<deleteCount {
                    self.textDocumentProxy.deleteBackward()
                }
                self.textDocumentProxy.insertText(replacement)
            }
            self.switchToPanel(.letters)
        }
        aiPanel.onRequestPromptInput = { [weak self] in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .modifier, settings: self.settings, hasFullAccess: self.hasFullAccess)
            if self.isTranslateMode {
                self.cancelLiveTranslation()
                self.isTranslateMode = false
                self.translateSourceBuffer = ""
                self.translatePreviewText = ""
                self.translateErrorText = nil
            }
            self.clearAllComposing()
            self.aiPromptDraft = ""
            self.switchToPanel(.letters)
        }
        aiPanel.onClose = { [weak self] in
            self?.aiPromptDraft = nil
            self?.switchToPanel(.letters)
        }

        quickSettingsPanel.onSettingsChanged = { [weak self] updated in
            guard let self else { return }
            let layoutOrSchemeChanged = updated.layoutMode != self.settings.layoutMode || updated.inputScheme != self.settings.inputScheme
            let translateLangChanged = updated.translateTargetLang != self.settings.translateTargetLang
            self.settings = updated
            if layoutOrSchemeChanged {
                self.clearAllComposing()
            }
            self.updatePreferredHeight()
            if !self.rawComposing.isEmpty {
                self.recomputeCandidates()
            }
            if translateLangChanged && self.isTranslateMode && !self.translateSourceBuffer.isEmpty {
                self.triggerTranslation(immediately: true)
            }
            self.applyThemeAndSettings()
        }
        quickSettingsPanel.onThemeChanged = { [weak self] updatedTheme in
            guard let self else { return }
            self.themeCustomization = updatedTheme
            self.resolvedTheme = ResolvedTheme.resolve(
                customization: updatedTheme,
                isDarkAppearance: self.isDarkInterface,
                targetSize: self.view.bounds.size.width > 10 ? self.view.bounds.size : CGSize(width: 430, height: 280)
            )
            self.applyThemeAndSettings()
        }
        quickSettingsPanel.onClose = { [weak self] in
            self?.switchToPanel(.letters)
        }
    }

    // MARK: - 26键事件处理

    private func handleCanvasEvent(_ event: KeyboardCanvasView.Event) {
        switch event {
        case .character(let ch):
            feedback.triggerKeyFeedback(tone: .letter, settings: settings, hasFullAccess: hasFullAccess)
            handleCharacterInput(ch)

        case .segmentSeparator:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            if !rawComposing.isEmpty && rawComposing.last != "'" {
                rawComposing.append("'")
                recomputeCandidates()
            }

        case .shiftTap:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            if !isEnglishMode {
                isEnglishMode = true
                shiftState = .shifted
                clearAllComposing()
                refreshUI()
            } else {
                shiftState = (shiftState == .lowercase) ? .shifted : .lowercase
                refreshCanvas()
            }

        case .shiftDoubleTap:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            isEnglishMode = true
            shiftState = (shiftState == .capsLocked) ? .lowercase : .capsLocked
            clearAllComposing()
            refreshUI()

        case .backspaceTap:
            feedback.triggerKeyFeedback(tone: .delete, settings: settings, hasFullAccess: hasFullAccess)
            performBackspace(isRepeat: false)

        case .backspaceRepeat:
            feedback.triggerKeyFeedback(tone: .delete, settings: settings, hasFullAccess: hasFullAccess)
            performBackspace(isRepeat: true)

        case .backspaceSwipeClear:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            performSwipeDelete()

        case .spaceTap:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            handleSpaceTap()

        case .cursorMove(let steps):
            feedback.triggerCursorTick(settings: settings)
            feedback.triggerCursorSound(settings: settings)
            if steps != 0 && aiPromptDraft == nil {
                lastSelectionUndo = nil
                performEdit {
                    self.textDocumentProxy.adjustTextPosition(byCharacterOffset: steps)
                }
            }

        case .switchToNumberPad:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            commitRawIfNeeded()
            switchToPanel(.numbers)

        case .nextKeyboard:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            advanceToNextInputMode()

        case .toggleLanguage:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            toggleChineseEnglish()

        case .returnKeyTap:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            handleReturnTap()

        case .sideRailToggleFull:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            settings.handedness = .full
            settings.save()
            refreshCanvas()

        case .sideRailSwapHand:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            settings.handedness = (settings.handedness == .left) ? .right : .left
            settings.save()
            refreshCanvas()

        case .sideRailClipboard:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            switchToPanel(.clipboard)

        case .sideRailAI:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            openAIPanel(preferredAction: nil, explicitClipboard: nil)

        case .glideCompleted(let touchPoints, let keyCenters, let keyPitch):
            feedback.triggerKeyFeedback(tone: .letter, settings: settings, hasFullAccess: hasFullAccess)
            feedback.triggerCursorSound(settings: settings)
            handleGlideInput(touchPoints: touchPoints, keyCenters: keyCenters, keyPitch: keyPitch)
        }
    }

    private func handleGlideInput(
        touchPoints: [CGPoint],
        keyCenters: [Character: CGPoint],
        keyPitch: CGFloat
    ) {
        guard let engine else { return }
        clearUndoBuffer()

        if isEmojiSearchMode { return }

        // 若上一段滑行或拼音尚未上屏，先自动上屏首候选，实现连续滑行成句
        if !isEnglishMode && !rawComposing.isEmpty {
            if let top = currentCandidates.first {
                commitCandidate(top)
            } else {
                commitRawIfNeeded()
            }
        }

        let glideCands = GlideTypingDecoder.decodeTouchPath(
            touchPoints: touchPoints,
            keyCenters: keyCenters,
            keyPitch: keyPitch,
            engine: engine,
            isEnglish: isEnglishMode,
            limit: 12
        )
        guard let best = glideCands.first else { return }

        if isEnglishMode {
            let prevWord = lastCommittedWord
            let actual = insertFinalText(best.word + " ", checkPairing: false)
            englishComposing = ""
            currentCandidates = Array(glideCands.dropFirst())
            lastSelectionUndo = SelectionUndoRecord(
                committedText: actual,
                rawComposing: "",
                prevLastCommittedWord: prevWord,
                inTranslateBuffer: isTranslateMode,
                learnRecord: nil,
                extraLearnRecord: nil
            )
            refreshUI()
        } else {
            let pyFlat = best.py.replacingOccurrences(of: "'", with: "")
            rawComposing = pyFlat.isEmpty ? best.word : pyFlat
            isLastInputFromGlide = true
            recomputeCandidates()
            // 确保几何得分最高的滑行候选词排在第 1 位
            var reordered: [PinyinCandidate] = []
            var seen = Set<String>()
            for gc in glideCands {
                let word = settings.traditionalChineseEnabled ? ChineseScriptConverter.toTraditional(gc.word) : gc.word
                let cand = PinyinCandidate(
                    word: word,
                    py: gc.py,
                    lp: gc.lp,
                    consumed: rawComposing.count,
                    isExact: true,
                    source: .dictionary
                )
                if seen.insert(cand.word).inserted {
                    reordered.append(cand)
                }
            }
            for c in currentCandidates where seen.insert(c.word).inserted {
                reordered.append(c)
            }
            currentCandidates = reordered
            expandedCandidates.update(candidates: reordered)
            refreshUI()
        }
    }

    // MARK: - T9 九宫格事件处理

    private func handleT9Event(_ event: T9KeyboardCanvasView.Event) {
        switch event {
        case .digit(let d):
            feedback.triggerKeyFeedback(tone: .letter, settings: settings, hasFullAccess: hasFullAccess)
            clearUndoBuffer()
            rawComposing.append(d)
            recomputeCandidates()

        case .segmentSeparator:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            if !rawComposing.isEmpty && rawComposing.last != "'" {
                rawComposing.append("'")
                recomputeCandidates()
            }

        case .selectSyllable(let syl):
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            lockedT9Syllables.append(syl)
            recomputeCandidates()

        case .insertSymbol(let sym):
            feedback.triggerKeyFeedback(tone: .letter, settings: settings, hasFullAccess: hasFullAccess)
            if !rawComposing.isEmpty {
                if let top = currentCandidates.first {
                    commitCandidate(top)
                } else {
                    commitRawIfNeeded()
                }
            }
            let converted = SmartPunctuation.convert(
                sym,
                style: settings.punctuationStyle,
                beforeCursor: activeContextBeforeCursor,
                smartQuotePairing: settings.smartQuotePairing,
                openDoubleQuote: &openDoubleQuote,
                openSingleQuote: &openSingleQuote
            )
            insertFinalText(converted, checkPairing: true)

        case .backspaceTap:
            feedback.triggerKeyFeedback(tone: .delete, settings: settings, hasFullAccess: hasFullAccess)
            performBackspace(isRepeat: false)

        case .backspaceRepeat:
            feedback.triggerKeyFeedback(tone: .delete, settings: settings, hasFullAccess: hasFullAccess)
            performBackspace(isRepeat: true)

        case .backspaceSwipeClear:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            performSwipeDelete()

        case .clearComposing:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            clearAllComposing()
            refreshUI()

        case .spaceTap:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            handleSpaceTap()

        case .cursorMove(let steps):
            feedback.triggerCursorTick(settings: settings)
            feedback.triggerCursorSound(settings: settings)
            if steps != 0 && aiPromptDraft == nil {
                lastSelectionUndo = nil
                performEdit {
                    self.textDocumentProxy.adjustTextPosition(byCharacterOffset: steps)
                }
            }

        case .switchToNumberPad:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            commitRawIfNeeded()
            switchToPanel(.numbers)

        case .nextKeyboard:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            advanceToNextInputMode()

        case .toggleLanguage:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            toggleChineseEnglish()

        case .returnKeyTap:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            handleReturnTap()

        case .sideRailToggleFull:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            settings.handedness = .full
            settings.save()
            refreshCanvas()

        case .sideRailSwapHand:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            settings.handedness = (settings.handedness == .left) ? .right : .left
            settings.save()
            refreshCanvas()

        case .sideRailClipboard:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            switchToPanel(.clipboard)

        case .sideRailAI:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            openAIPanel(preferredAction: nil, explicitClipboard: nil)
        }
    }

    private func toggleChineseEnglish() {
        commitRawIfNeeded()
        englishComposing = ""
        isEnglishMode.toggle()
        shiftState = .lowercase
        if isEnglishMode {
            autoCapitalizeIfNeeded()
        }
        refreshUI()
    }

    private func handleNumberPadEvent(_ event: NumberPadView.Event) {
        switch event {
        case .insertText(let str):
            feedback.triggerKeyFeedback(tone: .letter, settings: settings, hasFullAccess: hasFullAccess)
            let finalText = isEnglishMode
                ? str
                : SmartPunctuation.convert(
                    str,
                    style: settings.punctuationStyle,
                    beforeCursor: activeContextBeforeCursor,
                    smartQuotePairing: settings.smartQuotePairing,
                    openDoubleQuote: &openDoubleQuote,
                    openSingleQuote: &openSingleQuote
                )
            insertFinalText(finalText, checkPairing: true)
            updateIdleSuggestions()
        case .backspace:
            feedback.triggerKeyFeedback(tone: .delete, settings: settings, hasFullAccess: hasFullAccess)
            performBackspace(isRepeat: false)
            updateIdleSuggestions()
        case .space:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            insertFinalText(" ", checkPairing: false)
        case .returnKey:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            insertFinalText("\n", checkPairing: false)
        case .backToLetters:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            switchToPanel(.letters)
        }
    }

    private func handleToolbarAction(_ action: TopToolbarView.Action) {
        feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
        switch action {
        case .toggleAI:
            if activePanel == .ai {
                aiPromptDraft = nil
                switchToPanel(.letters)
            } else {
                openAIPanel(preferredAction: nil, explicitClipboard: nil)
            }
        case .toggleTranslateMode:
            toggleTranslateMode()
        case .cycleTranslateTarget:
            cycleTranslateTargetLanguage()
        case .toggleTranslateTone:
            settings.translateFormalTone.toggle()
            settings.save()
            translateErrorText = nil
            if !translateSourceBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                triggerTranslation(immediately: true)
            } else {
                refreshToolbar()
            }
        case .commitTranslatedText:
            commitTranslatedOutput()
        case .commitTranslateSource:
            commitTranslateSourceOutput()
        case .toggleClipboard:
            switchToPanel(activePanel == .clipboard ? .letters : .clipboard)
        case .toggleEmoji:
            if isEmojiSearchMode {
                exitEmojiSearchMode(openLetters: true)
            } else {
                switchToPanel(activePanel == .symbolsEmoji ? .letters : .symbolsEmoji)
            }
        case .toggleTextEditing:
            commitRawIfNeeded()
            switchToPanel(activePanel == .textEditing ? .letters : .textEditing)
        case .toggleQuickSettings:
            switchToPanel(activePanel == .quickSettings ? .letters : .quickSettings)
        case .toggleLayoutQuick:
            clearAllComposing()
            settings.layoutMode = (settings.layoutMode == .qwerty26) ? .t9Nine : .qwerty26
            settings.save()
            refreshUI()
        case .undoDelete:
            restoreUndoBuffer()
        case .insertOTP(let code):
            insertFinalText(code, checkPairing: false)
            pasteMonitor.dismissCurrent()
            refreshToolbar()
        case .pasteCaptured(let text):
            insertFinalText(text, checkPairing: false)
            pasteMonitor.dismissCurrent()
            refreshToolbar()
        case .directPasteFallback:
            if let text = UIPasteboard.general.string, !text.isEmpty {
                handleCapturedPasteFromToolbar(text)
            }
        case .askAIForClipboard(let text):
            openAIPanel(preferredAction: .replyClipboard, explicitClipboard: text)
        case .dismissClipboardBanner:
            pasteMonitor.dismissCurrent()
            refreshToolbar()
        case .forgetWord(let word, let py):
            engine?.userLexicon.forget(word: word, py: py.isEmpty ? nil : py)
            engine?.invalidateCache()
            recomputeCandidates()
        case .pinWord(let word, let py):
            if !py.isEmpty {
                engine?.userLexicon.learn(word: word, py: py)
                engine?.userLexicon.togglePin(word: word, py: py)
                engine?.invalidateCache()
                recomputeCandidates()
            }
        case .pickFirstChar(let ch), .pickLastChar(let ch):
            commitPickedSingleCharacter(ch)
        case .sendAIPrompt:
            commitRawIfNeeded()
            let question = (aiPromptDraft ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            aiPromptDraft = nil
            guard !question.isEmpty else {
                switchToPanel(.ai)
                return
            }
            switchToPanel(.ai)
            aiPanel.runCustomQuestion(
                question,
                theme: resolvedTheme,
                hasFullAccess: hasFullAccess,
                beforeCursor: textDocumentProxy.documentContextBeforeInput ?? ""
            )
        case .cancelAIPrompt:
            aiPromptDraft = nil
            clearAllComposing()
            switchToPanel(.ai)
        }
    }

    // MARK: - 拼音 / 英文 / 纠错处理核心

    private func handleCharacterInput(_ ch: String) {
        clearUndoBuffer()
        lastSelectionUndo = nil

        if isEmojiSearchMode {
            if ch.count == 1, let scalar = ch.unicodeScalars.first, scalar.isASCII,
               CharacterSet.alphanumerics.contains(scalar) {
                emojiSearchQuery.append(ch.lowercased())
                symbolEmojiPanel.updateSearchQuery(
                    emojiSearchQuery,
                    resolvedChineseWords: resolveEmojiSearchWords(for: emojiSearchQuery)
                )
            }
            return
        }

        if isEnglishMode {
            let styled = applyActiveStylishFont(ch)
            insertFinalText(styled, checkPairing: true)
            if ch.count == 1, let s = ch.unicodeScalars.first, CharacterSet.letters.contains(s),
               settings.stylishFontID == StylishFontStyle.normal.rawValue {
                englishComposing.append(ch)
                recomputeEnglishSuggestions()
            } else {
                englishComposing = ""
                updateIdleSuggestions()
            }
            if shiftState == .shifted {
                shiftState = .lowercase
                refreshCanvas()
            }
            return
        }

        // 双拼 / 五笔下使用大写 `V` 启动工具模式、大写 `U` 启动拆字与笔画反查模式（不与小写 v/u 键冲突）
        if !isUsingT9Layout && settings.inputScheme != .quanpin && (ch == "V" || ch == "U") && rawComposing.isEmpty {
            rawComposing = ch
            recomputeCandidates()
            return
        }

        // 若前一次是滑行输入生成的待选词，继续敲普通字母前先保持自然衔接
        isLastInputFromGlide = false

        // 微软 / 搜狗 / 紫光双拼：分号键 `;` 作为韵母 ing 参与组合
        if !isUsingT9Layout && settings.inputScheme.usesSemicolonFinal && ch == ";" && !rawComposing.isEmpty &&
            !SmartCandidateHelper.isVToolQuery(rawComposing, scheme: settings.inputScheme) {
            rawComposing.append(";")
            recomputeCandidates()
            return
        }

        // 五笔 86 模式输入流（a-y 4码、四码唯一自动上屏、第5码顶字、空码重敲清空、z 临时拼音与反查）
        if !isUsingT9Layout && settings.inputScheme.isWubi && !rawComposing.hasPrefix("V") && !rawComposing.hasPrefix("U") {
            if ch.count == 1, let scalar = ch.unicodeScalars.first, scalar.isASCII, CharacterSet.letters.contains(scalar) {
                let lower = ch.lowercased()
                if rawComposing.hasPrefix("z") {
                    rawComposing.append(lower)
                    recomputeCandidates()
                    return
                }
                if rawComposing.isEmpty && lower == "z" {
                    rawComposing = "z"
                    recomputeCandidates()
                    return
                }
                if let firstChar = lower.first, firstChar >= "a" && firstChar <= "y" {
                    if wubiEmptyCode {
                        rawComposing = ""
                        wubiEmptyCode = false
                        wubiDisplayBuffer = nil
                    } else if rawComposing.count >= 4 {
                        // 第 5 码顶字：先把当前 4 码首候选上屏，再用新码开启下一字
                        if let top = currentCandidates.first {
                            commitCandidate(top)
                        } else {
                            clearAllComposing()
                        }
                    }
                    rawComposing.append(lower)
                    recomputeCandidates(allowWubiAutoCommit: true)
                    return
                }
            }
        }

        // 中文模式下输入字母进入拼音/双拼/V工具组合
        if ch.count == 1, let scalar = ch.unicodeScalars.first, CharacterSet.letters.contains(scalar) {
            rawComposing.append(ch.lowercased())
            recomputeCandidates()
            return
        }

        if !rawComposing.isEmpty {
            let isVToolHead = (settings.inputScheme == .quanpin && rawComposing.lowercased().hasPrefix("v"))
                || (settings.inputScheme != .quanpin && rawComposing.hasPrefix("V"))
            let isVToolBody = isVToolHead &&
                rawComposing.dropFirst().allSatisfy { $0.isNumber || "+-*/%^().=".contains($0) }
            if isDigitOrMath(ch),
               (isVToolBody || rawComposing.allSatisfy({ $0.isNumber || "+-*/%^().=".contains($0) })) {
                rawComposing.append(ch)
                recomputeCandidates()
                return
            }
            if wubiEmptyCode {
                clearAllComposing()
            } else if let top = currentCandidates.first {
                commitCandidate(top)
            } else {
                commitRawIfNeeded()
            }
        }

        let finalPunct = SmartPunctuation.convert(
            ch,
            style: settings.punctuationStyle,
            beforeCursor: activeContextBeforeCursor,
            smartQuotePairing: settings.smartQuotePairing,
            openDoubleQuote: &openDoubleQuote,
            openSingleQuote: &openSingleQuote
        )
        insertFinalText(finalPunct, checkPairing: true)
        updateIdleSuggestions()
    }

    private func isDigitOrMath(_ s: String) -> Bool {
        s.count == 1 && "0123456789+-*/%^().=".contains(s)
    }

    private func handleSpaceTap() {
        lastSelectionUndo = nil

        if isEmojiSearchMode {
            if !emojiSearchQuery.isEmpty,
               let top = EmojiCatalog.search(
                   emojiSearchQuery,
                   resolvedChineseWords: resolveEmojiSearchWords(for: emojiSearchQuery),
                   limit: 1
               ).first {
                insertFinalText(top.symbol, checkPairing: false)
            }
            exitEmojiSearchMode(openLetters: true)
            return
        }

        if !isEnglishMode && !rawComposing.isEmpty {
            let isBareVTool = (rawComposing.lowercased() == "v" && settings.inputScheme == .quanpin)
                || (rawComposing == "V" && settings.inputScheme != .quanpin)
            if isBareVTool, CustomWordStore.match(rawInput: rawComposing).isEmpty {
                clearAllComposing()
                switchToPanel(.clipboard)
                return
            }
            if wubiEmptyCode {
                clearAllComposing()
                refreshUI()
                return
            }
            if let top = currentCandidates.first {
                commitCandidate(top)
            } else {
                commitRawIfNeeded()
            }
            return
        }
        englishComposing = ""
        currentCandidates = []

        if aiPromptDraft != nil {
            insertFinalText(" ", checkPairing: false)
            refreshUI()
            return
        }

        if isTranslateMode && !translateSourceBuffer.isEmpty {
            if !translatePreviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commitTranslatedOutput()
            } else {
                triggerTranslation(immediately: true)
            }
            return
        }

        let now = CACurrentMediaTime()
        if settings.doubleSpacePeriod,
           now - lastSpaceTapTime < 0.55,
           let before = textDocumentProxy.documentContextBeforeInput,
           before.hasSuffix(" "),
           before.count >= 2 {
            let prevChar = before[before.index(before.endIndex, offsetBy: -2)]
            if !prevChar.isWhitespace && !".。!！?？,，".contains(prevChar) {
                lastSpaceTapTime = 0
                performEdit {
                    self.textDocumentProxy.deleteBackward()
                    self.textDocumentProxy.insertText(self.isEnglishMode ? ". " : "。")
                }
                return
            }
        }
        lastSpaceTapTime = now
        insertFinalText(" ", checkPairing: false)
        refreshUI()
    }

    private func handleReturnTap() {
        lastSelectionUndo = nil

        if isEmojiSearchMode {
            if !emojiSearchQuery.isEmpty,
               let top = EmojiCatalog.search(
                   emojiSearchQuery,
                   resolvedChineseWords: resolveEmojiSearchWords(for: emojiSearchQuery),
                   limit: 1
               ).first {
                insertFinalText(top.symbol, checkPairing: false)
            }
            exitEmojiSearchMode(openLetters: true)
            return
        }

        if aiPromptDraft != nil && rawComposing.isEmpty {
            handleToolbarAction(.sendAIPrompt)
            return
        }
        if !isEnglishMode && !rawComposing.isEmpty {
            commitRawIfNeeded()
            return
        }
        if isTranslateMode && !translateSourceBuffer.isEmpty {
            if !translatePreviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commitTranslatedOutput()
            } else {
                triggerTranslation(immediately: true)
            }
            return
        }
        englishComposing = ""
        insertFinalText("\n", checkPairing: false)
        lastCommittedWord = nil
    }

    private func performBackspace(isRepeat: Bool = false) {
        if isEmojiSearchMode {
            if !emojiSearchQuery.isEmpty {
                emojiSearchQuery.removeLast()
                symbolEmojiPanel.updateSearchQuery(
                    emojiSearchQuery,
                    resolvedChineseWords: resolveEmojiSearchWords(for: emojiSearchQuery)
                )
            } else {
                exitEmojiSearchMode(openLetters: false)
            }
            return
        }

        if !rawComposing.isEmpty {
            lastSelectionUndo = nil
            // 若刚刚是滑行输入生成的整词，按一次退格直接清空整段滑行拼音（Gboard / 微信输入法同款手感）
            if isLastInputFromGlide {
                isLastInputFromGlide = false
                clearAllComposing()
                refreshUI()
                return
            }
            rawComposing.removeLast()
            // 若 T9 锁定音节已超过剩余数字长度，回退最后一个锁
            let lockedDigits = lockedT9Syllables.reduce(0) { $0 + PinyinSegmenter.t9Code(for: $1).count }
            if lockedDigits > rawComposing.replacingOccurrences(of: "'", with: "").count, !lockedT9Syllables.isEmpty {
                lockedT9Syllables.removeLast()
            }
            if rawComposing.isEmpty {
                clearAllComposing()
                refreshUI()
            } else {
                recomputeCandidates()
            }
            return
        }

        // 退格重选：紧接上屏后点按 ⌫，撤销已上屏词条、回退误学记录，并恢复原拼音/编码重选
        if !isRepeat, let selUndo = lastSelectionUndo, !selUndo.isExpired {
            lastSelectionUndo = nil
            if let rec = selUndo.learnRecord {
                engine?.userLexicon.undoLearn(rec)
            }
            if let extra = selUndo.extraLearnRecord {
                engine?.userLexicon.undoLearn(extra)
            }
            if selUndo.learnRecord != nil || selUndo.extraLearnRecord != nil {
                engine?.invalidateCache()
            }
            if selUndo.inTranslateBuffer && isTranslateMode {
                if translateSourceBuffer.hasSuffix(selUndo.committedText) {
                    translateSourceBuffer.removeLast(selUndo.committedText.count)
                    scheduleLiveTranslation(for: translateSourceBuffer)
                }
                lastCommittedWord = selUndo.prevLastCommittedWord
                rawComposing = selUndo.rawComposing
                recomputeCandidates()
                return
            } else if !selUndo.inTranslateBuffer && !isTranslateMode {
                let before = textDocumentProxy.documentContextBeforeInput ?? ""
                if before.isEmpty || before.hasSuffix(selUndo.committedText) {
                    performEdit {
                        for _ in 0..<selUndo.committedText.count {
                            self.textDocumentProxy.deleteBackward()
                        }
                    }
                    lastCommittedWord = selUndo.prevLastCommittedWord
                    rawComposing = selUndo.rawComposing
                    recomputeCandidates()
                    return
                }
            }
        }
        lastSelectionUndo = nil

        if let draft = aiPromptDraft {
            if !draft.isEmpty {
                aiPromptDraft = String(draft.dropLast())
            }
            refreshUI()
            return
        }

        if isTranslateMode && !translateSourceBuffer.isEmpty {
            translateSourceBuffer.removeLast()
            if translateSourceBuffer.isEmpty {
                cancelLiveTranslation()
                translatePreviewText = ""
                translateErrorText = nil
                refreshToolbar()
            } else {
                scheduleLiveTranslation(for: translateSourceBuffer)
            }
            return
        }

        if !englishComposing.isEmpty {
            englishComposing.removeLast()
            recomputeEnglishSuggestions()
        }
        pendingPhraseSegments.removeAll()
        lastCommittedWord = nil
        performEdit {
            // 成对括号智能退格连删：光标位于空括号中间（如 `（|）`、`(|)`）按 ⌫ 一次删掉整对
            if !isRepeat,
               self.settings.autoPairPunctuation,
               let left = self.textDocumentProxy.documentContextBeforeInput?.last,
               let right = self.textDocumentProxy.documentContextAfterInput?.first,
               Self.isMatchingBracketPair(left: left, right: right) {
                self.textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
                self.textDocumentProxy.deleteBackward()
                self.textDocumentProxy.deleteBackward()
            } else {
                self.textDocumentProxy.deleteBackward()
            }
        }
        autoCapitalizeIfNeeded()
    }

    private static func isMatchingBracketPair(left: Character, right: Character) -> Bool {
        switch (left, right) {
        case ("(", ")"), ("[", "]"), ("（", "）"), ("「", "」"), ("【", "】"), ("《", "》"), ("“", "”"), ("‘", "’"):
            return true
        default:
            return false
        }
    }

    private func performSwipeDelete() {
        lastSelectionUndo = nil

        if isEmojiSearchMode {
            emojiSearchQuery = ""
            symbolEmojiPanel.updateSearchQuery("")
            return
        }

        if !rawComposing.isEmpty {
            let cleared = rawComposing
            clearAllComposing()
            setUndoBuffer(text: cleared, wasComposing: true)
            refreshUI()
            return
        }

        if let draft = aiPromptDraft, !draft.isEmpty {
            setUndoBuffer(text: draft, wasComposing: false)
            aiPromptDraft = ""
            refreshToolbar()
            return
        }

        if isTranslateMode && !translateSourceBuffer.isEmpty {
            setUndoBuffer(text: translateSourceBuffer, wasComposing: false)
            cancelLiveTranslation()
            translateSourceBuffer = ""
            translatePreviewText = ""
            translateErrorText = nil
            refreshToolbar()
            return
        }

        englishComposing = ""
        guard let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty else { return }
        let boundaries: Set<Character> = ["\n", "。", "，", "？", "！", ".", ",", "?", "!", " "]
        var count = 0
        var deletedReversed: [Character] = []
        for ch in before.reversed() {
            if count > 0 && boundaries.contains(ch) { break }
            deletedReversed.append(ch)
            count += 1
            if count >= 16 { break }
        }
        let deleted = String(deletedReversed.reversed())
        performEdit {
            for _ in 0..<count {
                self.textDocumentProxy.deleteBackward()
            }
        }
        setUndoBuffer(text: deleted, wasComposing: false)
        refreshToolbar()
    }

    private func clearAllComposing() {
        rawComposing = ""
        lockedT9Syllables.removeAll()
        t9LeftSyllables.removeAll()
        currentTokens = []
        currentCorrectedHint = nil
        wubiEmptyCode = false
        wubiDisplayBuffer = nil
        uModeDisplayBuffer = nil
        isLastInputFromGlide = false
        currentCandidates = []
        isCandidatesExpanded = false
        pendingPhraseSegments.removeAll()
        englishComposing = ""
        if settings.inlineComposingEnabled && aiPromptDraft == nil {
            performEdit {
                self.textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
                self.textDocumentProxy.unmarkText()
            }
        }
    }

    private func recomputeEnglishSuggestions() {
        guard !englishComposing.isEmpty else {
            updateIdleSuggestions()
            return
        }
        let kbType = textDocumentProxy.keyboardType ?? .default
        let contextBefore = aiPromptDraft ?? (isTranslateMode ? translateSourceBuffer : textDocumentProxy.documentContextBeforeInput)
        var cands = SmartCandidateHelper.contextCompletions(
            beforeCursor: contextBefore,
            isEmailField: kbType == .emailAddress,
            isURLField: kbType == .URL || kbType == .webSearch,
            englishPrefix: englishComposing
        )
        var seen = Set(cands.map(\.word))
        if let engine {
            for (idx, w) in engine.queryEnglish(prefix: englishComposing, limit: 8).enumerated()
            where seen.insert(w).inserted {
                cands.append(PinyinCandidate(
                    word: w,
                    py: "",
                    lp: Double(-idx),
                    consumed: englishComposing.count,
                    isExact: false,
                    source: .englishDirect
                ))
            }
        }
        currentCandidates = cands
        expandedCandidates.update(candidates: currentCandidates)
        refreshToolbar()
    }

    private func recomputeCandidates(allowWubiAutoCommit: Bool = false) {
        guard !rawComposing.isEmpty else {
            wubiEmptyCode = false
            wubiDisplayBuffer = nil
            uModeDisplayBuffer = nil
            updateIdleSuggestions()
            return
        }
        guard let engine else {
            currentTokens = []
            currentCorrectedHint = nil
            wubiEmptyCode = false
            wubiDisplayBuffer = nil
            uModeDisplayBuffer = nil
            currentCandidates = [PinyinCandidate(word: rawComposing, py: "", lp: 0, consumed: rawComposing.count, isExact: false, source: .englishDirect)]
            refreshUI()
            return
        }

        let contextBefore = activeContextBeforeCursor
        var merged: [PinyinCandidate]
        wubiEmptyCode = false
        wubiDisplayBuffer = nil
        uModeDisplayBuffer = nil

        if !isUsingT9Layout && SmartCandidateHelper.isUToolQuery(rawComposing, scheme: settings.inputScheme) {
            let uRes = engine.queryUMode(raw: rawComposing, limit: 36)
            currentTokens = []
            currentCorrectedHint = nil
            uModeDisplayBuffer = uRes.displayBuffer
            merged = uRes.candidates
        } else if isUsingT9Layout {
            let res = engine.queryT9(
                digits: rawComposing,
                lockedSyllables: lockedT9Syllables,
                settings: settings,
                contextBeforeCursor: contextBefore
            )
            currentTokens = res.tokens
            t9LeftSyllables = res.leftSyllables
            currentCorrectedHint = nil
            merged = res.candidates

            // 九宫格同样支持 WowType 首位候选中文词 Emoji 推荐（如「今天好开心😊」）
            if settings.emojiSuggestionEnabled, let topWord = merged.first?.word {
                var existing = Set(merged.map(\.word))
                var insertAt = min(2, merged.count)
                for rec in EmojiCatalog.recommendForTopCandidate(topWord) where existing.insert(rec.word).inserted {
                    merged.insert(
                        PinyinCandidate(word: rec.word, py: "", lp: -4.0, consumed: rawComposing.count, isExact: false, source: .smartHelper),
                        at: min(insertAt, merged.count)
                    )
                    insertAt += 1
                }
            }
        } else if settings.inputScheme.isWubi && !rawComposing.hasPrefix("V") {
            let res = engine.queryWubi(
                raw: rawComposing,
                settings: settings,
                contextBeforeCursor: contextBefore,
                limit: 36
            )
            currentTokens = []
            currentCorrectedHint = nil
            wubiEmptyCode = res.isEmptyCode
            wubiDisplayBuffer = res.displayBuffer
            merged = res.candidates

            if allowWubiAutoCommit && res.isUnique4 && settings.wubiAutoCommitUnique4, let only = merged.first {
                currentCandidates = merged
                commitCandidate(only)
                return
            }

            // 五笔下同样支持自定义短语与首位候选 Emoji 推荐
            if !res.isTempPinyin {
                let customMatches = CustomWordStore.match(rawInput: rawComposing)
                for (idx, entry) in customMatches.enumerated() {
                    let cand = PinyinCandidate(word: entry.expandedWord, py: "", lp: 15.0 - Double(idx) * 0.1, consumed: rawComposing.count, isExact: true, source: .smartHelper)
                    if !merged.contains(where: { $0.word == cand.word }) {
                        merged.insert(cand, at: idx)
                    }
                }
            }
            if settings.emojiSuggestionEnabled, let topWord = merged.first?.word {
                var existing = Set(merged.map(\.word))
                var insertAt = min(2, merged.count)
                for rec in EmojiCatalog.recommendForTopCandidate(topWord) where existing.insert(rec.word).inserted {
                    merged.insert(
                        PinyinCandidate(word: rec.word, py: "", lp: -4.0, consumed: rawComposing.count, isExact: false, source: .smartHelper),
                        at: min(insertAt, merged.count)
                    )
                    insertAt += 1
                }
            }
        } else {
            let isVTool = SmartCandidateHelper.isVToolQuery(rawComposing, scheme: settings.inputScheme)
            if isVTool {
                currentTokens = []
                currentCorrectedHint = nil
                merged = []
            } else {
                let res = engine.query(raw: rawComposing, settings: settings, contextBeforeCursor: contextBefore)
                currentTokens = res.tokens
                currentCorrectedHint = res.correctedHint
                merged = res.candidates
            }

            let enWords = (settings.smartEnglishCandidate && !isVTool) ? engine.queryEnglish(prefix: rawComposing, limit: 4) : []
            let helperCands = SmartCandidateHelper.extraCandidates(
                forRawInput: rawComposing,
                settings: settings,
                consumedLength: rawComposing.count,
                englishWords: enWords,
                topChineseWord: merged.first?.word
            )
            var existingWords = Set(merged.map(\.word))
            var frontInsertIndex = 0
            var emojiInsertIndex = min(2, merged.count)
            for hc in helperCands where existingWords.insert(hc.word).inserted {
                if hc.source == .smartHelper && hc.lp > 0 {
                    merged.insert(hc, at: frontInsertIndex)
                    frontInsertIndex += 1
                    emojiInsertIndex = min(frontInsertIndex + 2, merged.count)
                } else if hc.source == .smartHelper {
                    let idx = min(emojiInsertIndex, merged.count)
                    merged.insert(hc, at: idx)
                    emojiInsertIndex += 1
                } else {
                    merged.append(hc)
                }
            }

            let isBareVTool = (rawComposing.lowercased() == "v" && settings.inputScheme == .quanpin)
                || (rawComposing == "V" && settings.inputScheme != .quanpin)
            if isBareVTool && frontInsertIndex == 0 {
                let toolboxHint = PinyinCandidate(
                    word: "🧰 打开百宝箱（空格）",
                    py: "",
                    lp: 20.0,
                    consumed: 1,
                    isExact: true,
                    source: .smartHelper
                )
                merged.insert(toolboxHint, at: 0)
            }
        }

        // 若开启繁体中文输出，保持英文/数字/符号不变，对中文候选实时转为繁体（保留五笔编码提示）
        if settings.traditionalChineseEnabled {
            merged = merged.map { c in
                let converted = (c.source == .englishDirect) ? c.word : ChineseScriptConverter.toTraditional(c.word)
                return PinyinCandidate(
                    word: converted,
                    py: c.py,
                    lp: c.lp,
                    consumed: c.consumed,
                    isExact: c.isExact,
                    source: c.source,
                    codeHint: c.codeHint
                )
            }
        }

        currentCandidates = merged
        expandedCandidates.update(candidates: merged)
        syncInlineMarkedTextIfEnabled()
        refreshUI()
    }

    private func syncInlineMarkedTextIfEnabled() {
        guard settings.inlineComposingEnabled, aiPromptDraft == nil, !isEnglishMode else { return }
        let marked = currentCorrectedHint ?? (currentTokens.isEmpty ? rawComposing : PinyinSegmenter.displayPinyin(for: currentTokens))
        performEdit {
            self.textDocumentProxy.setMarkedText(marked, selectedRange: NSRange(location: marked.utf16.count, length: 0))
        }
    }

    private func selectCandidate(at index: Int) {
        guard currentCandidates.indices.contains(index) else { return }
        // 选词反馈：一次按键级震动 + 一声音效即可，不再叠加 triggerCursorTick（双震会粘连）。
        feedback.triggerKeyFeedback(tone: .letter, settings: settings, hasFullAccess: hasFullAccess)
        feedback.triggerCursorSound(settings: settings)
        clearUndoBuffer()
        let cand = currentCandidates[index]

        // 英文模式下点选补全词或滑行替换词，替换掉已输入的前缀或刚滑行上屏的词
        if isEnglishMode && cand.source == .englishDirect {
            let deleteLen: Int
            if !englishComposing.isEmpty {
                deleteLen = englishComposing.count
            } else if let glideUndo = lastSelectionUndo, glideUndo.rawComposing.isEmpty, !glideUndo.committedText.isEmpty {
                deleteLen = glideUndo.committedText.count
            } else {
                deleteLen = 0
            }
            if deleteLen > 0 {
                let prevWord = lastSelectionUndo?.prevLastCommittedWord
                englishComposing = ""
                currentCandidates = []
                let kbType = textDocumentProxy.keyboardType ?? .default
                let suppressSpace = (kbType == .emailAddress || kbType == .URL || kbType == .webSearch || cand.word.contains("."))
                let trailing = suppressSpace ? "" : " "
                let replacement = cand.word + trailing
                if aiPromptDraft != nil {
                    var d = aiPromptDraft ?? ""
                    if d.count >= deleteLen { d.removeLast(deleteLen) }
                    aiPromptDraft = d + replacement
                    refreshUI()
                } else if isTranslateMode {
                    if translateSourceBuffer.count >= deleteLen {
                        translateSourceBuffer.removeLast(deleteLen)
                    }
                    appendToTranslateSource(replacement)
                } else {
                    performEdit {
                        for _ in 0..<deleteLen {
                            self.textDocumentProxy.deleteBackward()
                        }
                        self.textDocumentProxy.insertText(replacement)
                    }
                    lastSelectionUndo = SelectionUndoRecord(
                        committedText: replacement,
                        rawComposing: "",
                        prevLastCommittedWord: prevWord,
                        inTranslateBuffer: false,
                        learnRecord: nil,
                        extraLearnRecord: nil
                    )
                    refreshToolbar()
                }
                return
            }
        }

        commitCandidate(cand)
    }

    private func commitCandidate(_ cand: PinyinCandidate) {
        isCandidatesExpanded = false
        clearUndoBuffer()
        let isBareVTool = (rawComposing.lowercased() == "v" && settings.inputScheme == .quanpin)
            || (rawComposing == "V" && settings.inputScheme != .quanpin)
        if cand.source == .smartHelper && isBareVTool && cand.word.contains("百宝箱") {
            clearAllComposing()
            switchToPanel(.clipboard)
            return
        }

        let prevRaw = rawComposing
        let wasInTranslate = isTranslateMode
        let prevWord = lastCommittedWord
        let outputWord = (settings.traditionalChineseEnabled && cand.source != .englishDirect)
            ? ChineseScriptConverter.toTraditional(cand.word)
            : cand.word
        if settings.inlineComposingEnabled && aiPromptDraft == nil {
            performEdit {
                self.textDocumentProxy.unmarkText()
            }
        }
        let actualInserted = insertFinalText(outputWord, checkPairing: false)

        // 若用户选择了带 Emoji 的推荐候选（如「今天好开心😊」或独立「😊」），同步记入 RecentEmojiStore
        if cand.source == .smartHelper {
            for scalar in cand.word.unicodeScalars where scalar.properties.isEmojiPresentation {
                RecentEmojiStore.record(String(scalar))
                break
            }
        }

        var learnedRecord: UserLearnRecord?
        var combinedLearnRecord: UserLearnRecord?
        if settings.userLearningEnabled && !isSecureField && cand.source != .wubi, !cand.py.isEmpty {
            let recordBigram = settings.bigramPredictionEnabled && prevWord != nil && (rawComposing.isEmpty || pendingPhraseSegments.isEmpty)
            let prevForRecord = recordBigram ? prevWord : nil
            learnedRecord = engine?.userLexicon.learn(word: cand.word, py: cand.py, prevWord: prevForRecord)
            if let prevForRecord {
                engine?.userLexicon.learnBigram(prev: prevForRecord, next: cand.word)
            }
            pendingPhraseSegments.append((cand.word, cand.py))
        }
        lastCommittedWord = cand.word

        let consumed = min(cand.consumed, rawComposing.count)
        if consumed > 0 && consumed < rawComposing.count {
            lastSelectionUndo = nil
            rawComposing.removeFirst(consumed)
            if rawComposing.hasPrefix("'") { rawComposing.removeFirst() }
            lockedT9Syllables.removeAll()
            recomputeCandidates()
        } else {
            rawComposing = ""
            lockedT9Syllables.removeAll()
            t9LeftSyllables.removeAll()
            currentTokens = []
            currentCorrectedHint = nil
            wubiEmptyCode = false
            wubiDisplayBuffer = nil
            uModeDisplayBuffer = nil
            isLastInputFromGlide = false
            if settings.userLearningEnabled && !isSecureField && cand.source != .wubi && pendingPhraseSegments.count >= 2 {
                let combinedWord = pendingPhraseSegments.map(\.word).joined()
                let combinedPy = pendingPhraseSegments.map(\.py).joined(separator: "'")
                // 对齐 WowType COMPOSED_WORD_MAX_CHARS = 4：仅将 4 字以内分段拼出的新词（人名/术语/成语）收入自造词库
                if combinedWord.count <= 4 {
                    combinedLearnRecord = engine?.userLexicon.learn(word: combinedWord, py: combinedPy)
                    engine?.invalidateCache()
                }
            }
            pendingPhraseSegments.removeAll()
            if !prevRaw.isEmpty && aiPromptDraft == nil {
                lastSelectionUndo = SelectionUndoRecord(
                    committedText: actualInserted,
                    rawComposing: prevRaw,
                    prevLastCommittedWord: prevWord,
                    inTranslateBuffer: wasInTranslate,
                    learnRecord: learnedRecord,
                    extraLearnRecord: combinedLearnRecord
                )
            } else {
                lastSelectionUndo = nil
            }
            updateIdleSuggestions()
        }
    }

    private func commitRawIfNeeded() {
        guard !rawComposing.isEmpty else { return }
        let clean = rawComposing.replacingOccurrences(of: "'", with: "")
        clearAllComposing()
        if !clean.isEmpty {
            insertFinalText(clean, checkPairing: false)
        }
        refreshUI()
    }

    private func updateIdleSuggestions() {
        guard rawComposing.isEmpty && englishComposing.isEmpty else { return }
        var suggestions: [PinyinCandidate] = []
        let kbType = textDocumentProxy.keyboardType ?? .default
        let contextBefore = aiPromptDraft ?? (isTranslateMode ? translateSourceBuffer : textDocumentProxy.documentContextBeforeInput)

        // 1. 实时算式求值（同时支持 `125*8=` 与未敲等号的 `125*8`）
        if aiPromptDraft == nil,
           let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty {
            let tail = String(before.suffix(48))
            let exprSlice: String
            if let eqStart = tail.lastIndex(where: { !($0.isNumber || "+-*/%×÷^().=".contains($0)) }) {
                exprSlice = String(tail[tail.index(after: eqStart)...])
            } else {
                exprSlice = tail
            }
            if let calc = InlineCalculator.evaluateIfExpression(exprSlice) {
                let output = exprSlice.hasSuffix("=") ? calc.result : "=\(calc.result)"
                suggestions.append(PinyinCandidate(word: output, py: "", lp: 10, consumed: 0, isExact: true, source: .smartHelper))
            }
        }

        // 2. 上下文邮箱域名与网址前后缀快捷补全（@ -> gmail.com / qq.com / 163.com）
        if !isSecureField {
            suggestions.append(contentsOf: SmartCandidateHelper.contextCompletions(
                beforeCursor: contextBefore,
                isEmailField: kbType == .emailAddress,
                isURLField: kbType == .URL || kbType == .webSearch,
                englishPrefix: ""
            ))
        }

        // 3. 中文场景下的 Emoji 推荐与二元上下文下一词预测
        if !isEnglishMode && !isSecureField, let lastWord = lastCommittedWord {
            if settings.emojiSuggestionEnabled {
                for emoji in SmartCandidateHelper.emojiPredictions(forCommittedWord: lastWord) {
                    suggestions.append(PinyinCandidate(word: emoji, py: "", lp: 2.0, consumed: 0, isExact: false, source: .smartHelper))
                }
            }
            if settings.bigramPredictionEnabled,
               let nextWords = engine?.predictNext(after: lastWord, userLearning: settings.userLearningEnabled, limit: 10) {
                for (idx, w) in nextWords.enumerated() {
                    let word = settings.traditionalChineseEnabled ? ChineseScriptConverter.toTraditional(w) : w
                    suggestions.append(PinyinCandidate(
                        word: word,
                        py: "",
                        lp: Double(-idx),
                        consumed: 0,
                        isExact: false,
                        source: .prediction
                    ))
                }
            }
        }

        currentCandidates = suggestions
        refreshUI()
    }

    private func handleLongPressCandidate(at index: Int) {
        guard currentCandidates.indices.contains(index) else { return }
        let cand = currentCandidates[index]
        guard cand.source == .dictionary || cand.source == .userLearned else { return }
        feedback.triggerCursorTick(settings: settings)
        feedback.triggerCursorSound(settings: settings)
        let isPinned = engine?.userLexicon.allEntries(limit: 100)
            .first(where: { $0.word == cand.word && $0.py == cand.py })?.isPinned ?? false
        toolbarView.showWordActionBar(word: cand.word, py: cand.py, isPinned: isPinned)
    }

    // MARK: - 文本插入、盘古空格、成对标点、AI 草稿 & 边打边译拦截

    @discardableResult
    private func insertFinalText(_ text: String, checkPairing: Bool) -> String {
        if let draft = aiPromptDraft {
            aiPromptDraft = draft + text
            refreshToolbar()
            return text
        }

        if isTranslateMode {
            appendToTranslateSource(text)
            return text
        }

        var inserted = text
        performEdit {
            if checkPairing && self.settings.autoPairPunctuation {
                // 若光标右侧紧邻即将输入的闭括号（自动配对生成的），直接越过不重复插入
                let closers: Set<String> = [")", "]", "）", "」", "】", "》"]
                if closers.contains(text),
                   let nextChar = self.textDocumentProxy.documentContextAfterInput?.first,
                   String(nextChar) == text {
                    self.textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
                    inserted = ""
                    return
                }
                let pairs: [String: String] = [
                    "（": "（）", "「": "「」", "【": "【】", "《": "《》", "(": "()", "[": "[]",
                ]
                if let paired = pairs[text] {
                    self.textDocumentProxy.insertText(paired)
                    self.textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
                    inserted = paired
                    return
                }
            }

            if self.shouldAllowPanguSpace,
               (self.settings.panguSpaceLetters || self.settings.panguSpaceDigits),
               PanguSpacer.needsLeadingSpace(
                   beforeCursor: self.textDocumentProxy.documentContextBeforeInput,
                   inserting: text,
                   spaceLetters: self.settings.panguSpaceLetters,
                   spaceDigits: self.settings.panguSpaceDigits
               ) {
                inserted = " " + text
                self.textDocumentProxy.insertText(inserted)
                return
            }

            self.textDocumentProxy.insertText(text)
        }
        // 打字统计（WowType 借鉴）：仅统计真实上屏文本；密码/邮箱/网址等隐私框不统计
        if self.settings.typingStatsEnabled,
           self.shouldAllowPanguSpace,
           !inserted.isEmpty {
            TypingStatsStore.shared.recordCommit(text: inserted)
        }
        return inserted
    }

    private func insertDirectlyIntoHost(_ text: String) {
        performEdit {
            if self.shouldAllowPanguSpace,
               (self.settings.panguSpaceLetters || self.settings.panguSpaceDigits),
               PanguSpacer.needsLeadingSpace(
                   beforeCursor: self.textDocumentProxy.documentContextBeforeInput,
                   inserting: text,
                   spaceLetters: self.settings.panguSpaceLetters,
                   spaceDigits: self.settings.panguSpaceDigits
               ) {
                self.textDocumentProxy.insertText(" " + text)
            } else {
                self.textDocumentProxy.insertText(text)
            }
        }
    }

    // MARK: - 文本编辑与光标精控面板处理

    private func handleTextEditingAction(_ action: TextEditingPanelView.Action) {
        feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
        lastSelectionUndo = nil
        switch action {
        case .moveLeft:
            performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: -1) }
        case .moveRight:
            performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: 1) }
        case .moveUp:
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            let lines = before.components(separatedBy: "\n")
            if lines.count >= 2 {
                let curCol = lines.last?.count ?? 0
                let prevLineLen = lines[lines.count - 2].count
                let targetCol = min(curCol, prevLineLen)
                let delta = -(curCol + 1 + (prevLineLen - targetCol))
                performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: delta) }
            } else if !before.isEmpty {
                performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: -before.count) }
            }
        case .moveDown:
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            let after = textDocumentProxy.documentContextAfterInput ?? ""
            let curCol = before.components(separatedBy: "\n").last?.count ?? 0
            let afterLines = after.components(separatedBy: "\n")
            if afterLines.count >= 2 {
                let toEndOfCurLine = afterLines[0].count
                let nextLineLen = afterLines[1].count
                let targetCol = min(curCol, nextLineLen)
                let delta = toEndOfCurLine + 1 + targetCol
                performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: delta) }
            } else if !after.isEmpty {
                performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: after.count) }
            }
        case .moveLineStart:
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            let curCol = before.components(separatedBy: "\n").last?.count ?? 0
            if curCol > 0 {
                performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: -curCol) }
            }
            textEditingPanel.showStatusToast("⇤ 已跳至当前行首")
        case .moveLineEnd:
            let after = textDocumentProxy.documentContextAfterInput ?? ""
            let rem = after.components(separatedBy: "\n").first?.count ?? 0
            if rem > 0 {
                performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: rem) }
            }
            textEditingPanel.showStatusToast("已跳至当前行尾 ⇥")
        case .deleteBackward:
            performEdit { self.textDocumentProxy.deleteBackward() }
        case .deleteForward:
            let after = textDocumentProxy.documentContextAfterInput ?? ""
            guard !after.isEmpty else { return }
            performEdit {
                self.textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
                self.textDocumentProxy.deleteBackward()
            }
        case .copyContext:
            let selected = textDocumentProxy.selectedText ?? ""
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            let after = textDocumentProxy.documentContextAfterInput ?? ""
            let target = !selected.isEmpty ? selected : (before + after)
            guard !target.isEmpty else {
                textEditingPanel.showStatusToast("当前输入框为空")
                return
            }
            _ = ClipboardStore.record(target)
            if hasFullAccess {
                UIPasteboard.general.string = target
            }
            textEditingPanel.showStatusToast("✓ 已复制 \(target.count) 字到剪贴板")
        case .pasteClipboard:
            var textToPaste: String?
            if hasFullAccess, let sys = UIPasteboard.general.string, !sys.isEmpty {
                textToPaste = sys
            } else if let latest = ClipboardStore.items().first?.text, !latest.isEmpty {
                textToPaste = latest
            }
            guard let text = textToPaste else {
                textEditingPanel.showStatusToast("剪贴板暂无可粘贴内容")
                return
            }
            insertFinalText(text, checkPairing: false)
            textEditingPanel.showStatusToast("✓ 已粘贴 \(text.count) 字")
        case .clearCurrentLine:
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            let after = textDocumentProxy.documentContextAfterInput ?? ""
            let leftPart = before.components(separatedBy: "\n").last ?? ""
            let rightPart = after.components(separatedBy: "\n").first ?? ""
            let totalLine = leftPart + rightPart
            guard !totalLine.isEmpty else { return }
            performEdit {
                if !rightPart.isEmpty {
                    self.textDocumentProxy.adjustTextPosition(byCharacterOffset: rightPart.count)
                }
                for _ in 0..<totalLine.count {
                    self.textDocumentProxy.deleteBackward()
                }
            }
            setUndoBuffer(text: totalLine, wasComposing: false)
            textEditingPanel.showStatusToast("🧹 已清空本行（可点顶部撤销）")
        case .insertNewline:
            insertFinalText("\n", checkPairing: false)
        case .close:
            switchToPanel(.letters)
        }
    }

    private func commitPickedSingleCharacter(_ ch: String) {
        isCandidatesExpanded = false
        let chosen = settings.traditionalChineseEnabled ? ChineseScriptConverter.toTraditional(ch) : ch
        clearAllComposing()
        _ = insertFinalText(chosen, checkPairing: false)
        lastCommittedWord = ch
        updateIdleSuggestions()
        refreshUI()
    }

    private func exitEmojiSearchMode(openLetters: Bool) {
        isEmojiSearchMode = false
        emojiSearchQuery = ""
        symbolEmojiPanel.setSearchMode(false, query: "")
        switchToPanel(openLetters ? .letters : .symbolsEmoji)
    }

    private func toggleTranslateMode() {
        if isTranslateMode {
            cancelLiveTranslation()
            isTranslateMode = false
            translateSourceBuffer = ""
            translatePreviewText = ""
            translateIsStreaming = false
            translateErrorText = nil
            refreshUI()
        } else {
            if isEmojiSearchMode {
                isEmojiSearchMode = false
                emojiSearchQuery = ""
                symbolEmojiPanel.setSearchMode(false, query: "")
            }
            aiPromptDraft = nil
            clearAllComposing()
            isTranslateMode = true
            translateSourceBuffer = ""
            translatePreviewText = ""
            translateIsStreaming = false
            if !hasFullAccess {
                translateErrorText = "需开启「允许完全访问」才可联网翻译"
            } else if !AIConfig.load().isConfigured {
                translateErrorText = "请先在 App 中填写 AI Key"
            } else {
                translateErrorText = nil
            }
            switchToPanel(.letters)
        }
    }

    private func cycleTranslateTargetLanguage() {
        let langs = TranslateTargetLanguage.allCases.map(\.rawValue)
        if let idx = langs.firstIndex(of: settings.translateTargetLang) {
            settings.translateTargetLang = langs[(idx + 1) % langs.count]
        } else {
            settings.translateTargetLang = langs.first ?? "英文"
        }
        settings.save()
        translateErrorText = nil
        if !translateSourceBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            triggerTranslation(immediately: true)
        } else {
            refreshToolbar()
        }
    }

    private func appendToTranslateSource(_ text: String) {
        translateSourceBuffer.append(text)
        let immediate = text.last.map { "。？！?!.\n".contains($0) } ?? false
        if immediate {
            triggerTranslation(immediately: true)
        } else {
            scheduleLiveTranslation(for: translateSourceBuffer)
        }
    }

    private func cancelLiveTranslation() {
        translateDebounceWorkItem?.cancel()
        translateDebounceWorkItem = nil
        translateTask?.cancel()
        translateTask = nil
    }

    private func scheduleLiveTranslation(for source: String) {
        translateDebounceWorkItem?.cancel()
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelLiveTranslation()
            translatePreviewText = ""
            translateIsStreaming = false
            translateErrorText = nil
            refreshToolbar()
            return
        }

        let key = "\(settings.translateTargetLang)|\(settings.translateFormalTone)|\(trimmed)"
        if let cached = translateCache[key] {
            cancelLiveTranslation()
            translatePreviewText = cached
            translateIsStreaming = false
            translateErrorText = nil
            refreshToolbar()
            return
        }

        translateErrorText = nil
        refreshToolbar()
        let work = DispatchWorkItem { [weak self] in
            self?.triggerTranslation(immediately: true)
        }
        translateDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func triggerTranslation(immediately: Bool) {
        _ = immediately
        translateDebounceWorkItem?.cancel()
        translateDebounceWorkItem = nil

        let sourceSnapshot = translateSourceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let langSnapshot = settings.translateTargetLang
        let formalSnapshot = settings.translateFormalTone
        guard !sourceSnapshot.isEmpty else {
            cancelLiveTranslation()
            translatePreviewText = ""
            translateIsStreaming = false
            translateErrorText = nil
            refreshToolbar()
            return
        }

        let cacheKey = "\(langSnapshot)|\(formalSnapshot)|\(sourceSnapshot)"
        if let cached = translateCache[cacheKey] {
            translateTask?.cancel()
            translatePreviewText = cached
            translateIsStreaming = false
            translateErrorText = nil
            refreshToolbar()
            return
        }

        guard hasFullAccess else {
            translateIsStreaming = false
            translateErrorText = "需开启「允许完全访问」才可联网翻译"
            refreshToolbar()
            return
        }

        let cfg = AIConfig.load()
        guard cfg.isConfigured else {
            translateIsStreaming = false
            translateErrorText = "请先在 App 中填写 AI Key"
            refreshToolbar()
            return
        }

        translateTask?.cancel()
        translatePreviewText = ""
        translateIsStreaming = true
        translateErrorText = nil
        refreshToolbar()

        translateTask = Task { [weak self] in
            var accumulated = ""
            guard let self else { return }
            do {
                let system = TranslateTargetLanguage.systemPrompt(for: langSnapshot, formal: formalSnapshot)
                for try await chunk in self.translateClient.streamText(
                    prompt: sourceSnapshot,
                    systemInstruction: system,
                    config: cfg
                ) {
                    try Task.checkCancellation()
                    accumulated += chunk
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.isTranslateMode,
                              self.settings.translateTargetLang == langSnapshot,
                              self.translateSourceBuffer.trimmingCharacters(in: .whitespacesAndNewlines) == sourceSnapshot else {
                            return
                        }
                        self.translatePreviewText = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.translateIsStreaming = true
                        self.translateErrorText = nil
                        self.refreshToolbar()
                    }
                }
                try Task.checkCancellation()
                let finalResult = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run { [weak self] in
                    guard let self,
                          self.isTranslateMode,
                          self.settings.translateTargetLang == langSnapshot,
                          self.translateSourceBuffer.trimmingCharacters(in: .whitespacesAndNewlines) == sourceSnapshot else {
                        return
                    }
                    self.translatePreviewText = finalResult
                    self.translateIsStreaming = false
                    if !finalResult.isEmpty {
                        self.storeTranslateCache(key: cacheKey, value: finalResult)
                    }
                    self.refreshToolbar()
                }
            } catch is CancellationError {
                // 正常取消（继续输入或退出译模式）
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.isTranslateMode,
                          self.settings.translateTargetLang == langSnapshot,
                          self.translateSourceBuffer.trimmingCharacters(in: .whitespacesAndNewlines) == sourceSnapshot else {
                        return
                    }
                    self.translateIsStreaming = false
                    self.translateErrorText = error.localizedDescription
                    self.refreshToolbar()
                }
            }
        }
    }

    private func storeTranslateCache(key: String, value: String) {
        if translateCache[key] == nil {
            if translateCacheOrder.count >= Self.maxTranslateCacheEntries, let oldest = translateCacheOrder.first {
                translateCacheOrder.removeFirst()
                translateCache.removeValue(forKey: oldest)
            }
            translateCacheOrder.append(key)
        }
        translateCache[key] = value
    }

    private func commitTranslatedOutput() {
        let out = translatePreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return }
        cancelLiveTranslation()
        lastSelectionUndo = nil
        insertDirectlyIntoHost(out)
        translateSourceBuffer = ""
        translatePreviewText = ""
        translateIsStreaming = false
        translateErrorText = nil
        refreshToolbar()
    }

    private func commitTranslateSourceOutput() {
        let out = translateSourceBuffer
        guard !out.isEmpty else { return }
        cancelLiveTranslation()
        lastSelectionUndo = nil
        insertDirectlyIntoHost(out)
        translateSourceBuffer = ""
        translatePreviewText = ""
        translateIsStreaming = false
        translateErrorText = nil
        refreshToolbar()
    }

    private func applyActiveStylishFont(_ text: String) -> String {
        let style = StylishFontStyle(rawValue: settings.stylishFontID) ?? .normal
        return StylishTextConverter.convert(text, style: style)
    }

    private func performEdit(_ block: () -> Void) {
        lastInternalEditTime = CACurrentMediaTime()
        block()
        lastInternalEditTime = CACurrentMediaTime()
    }

    private func autoCapitalizeIfNeeded() {
        guard isEnglishMode, settings.autoCapitalizeEnglish, shiftState != .capsLocked else { return }
        let before = aiPromptDraft ?? (isTranslateMode ? translateSourceBuffer : (textDocumentProxy.documentContextBeforeInput ?? ""))
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || before.hasSuffix(". ") || before.hasSuffix("! ") || before.hasSuffix("? ") || before.hasSuffix("\n") {
            shiftState = .shifted
        } else if shiftState == .shifted {
            shiftState = .lowercase
        }
        refreshCanvas()
    }

    // MARK: - 剪贴板与 AI

    private func refreshClipboardState() {
        guard !isSecureField else {
            pasteMonitor.dismissCurrent()
            refreshToolbar()
            return
        }
        pasteMonitor.refresh(settings: settings) { [weak self] _ in
            self?.refreshToolbar()
        }
    }

    private func handleCapturedPasteFromToolbar(_ text: String) {
        feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
        let result = pasteMonitor.handleCapturedPaste(text, settings: settings)
        if result.shouldOfferOTPChoice {
            refreshToolbar()
        } else {
            insertFinalText(text, checkPairing: false)
            refreshToolbar()
        }
    }

    private func openAIPanel(preferredAction: AIPresetAction?, explicitClipboard: String?) {
        commitRawIfNeeded()
        switchToPanel(.ai)
        let hostBefore = textDocumentProxy.documentContextBeforeInput ?? ""
        let before = (hostBefore.isEmpty && isTranslateMode && !translateSourceBuffer.isEmpty) ? translateSourceBuffer : hostBefore
        aiPanel.prepare(
            theme: resolvedTheme,
            hasFullAccess: hasFullAccess,
            beforeCursor: before,
            clipboardText: explicitClipboard,
            preferredAction: preferredAction
        )
    }

    // MARK: - 撤销删除

    private func setUndoBuffer(text: String, wasComposing: Bool) {
        guard !text.isEmpty else { return }
        undoBuffer = (text, wasComposing)
        undoHideTimer?.invalidate()
        undoHideTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            self?.clearUndoBuffer()
        }
        refreshToolbar()
    }

    private func clearUndoBuffer() {
        guard undoBuffer != nil else { return }
        undoBuffer = nil
        undoHideTimer?.invalidate()
        undoHideTimer = nil
        refreshToolbar()
    }

    private func restoreUndoBuffer() {
        guard let undo = undoBuffer else { return }
        clearUndoBuffer()
        if undo.wasComposing {
            rawComposing = undo.deletedText
            recomputeCandidates()
        } else {
            insertFinalText(undo.deletedText, checkPairing: false)
        }
    }

    // MARK: - 面板切换与主题刷新

    private func switchToPanel(_ target: ActivePanel) {
        if isEmojiSearchMode {
            isEmojiSearchMode = false
            emojiSearchQuery = ""
            symbolEmojiPanel.setSearchMode(false, query: "")
        }
        activePanel = target
        isCandidatesExpanded = false
        updatePreferredHeight()
        updateVisiblePanel()

        switch target {
        case .clipboard:
            clipboardPanel.configure(
                theme: resolvedTheme,
                activeFontStyle: StylishFontStyle(rawValue: settings.stylishFontID) ?? .normal
            )
        case .textEditing:
            textEditingPanel.apply(theme: resolvedTheme)
        case .quickSettings:
            quickSettingsPanel.configure(theme: resolvedTheme, settings: settings, customization: themeCustomization)
        case .symbolsEmoji:
            symbolEmojiPanel.apply(theme: resolvedTheme)
        case .numbers:
            let (retTitle, _) = returnKeyAppearance()
            numberPad.configure(theme: resolvedTheme, isChineseMode: !isEnglishMode, returnTitle: retTitle)
        case .letters, .ai:
            break
        }
        refreshUI()
    }

    private func updateVisiblePanel() {
        if isEmojiSearchMode {
            symbolFullBottomConstraint?.isActive = false
            symbolCompactHeightConstraint?.isActive = true
            lettersTopConstraint?.constant = 80
            lettersCanvas.isHidden = false
            t9Canvas.isHidden = true
            expandedCandidates.isHidden = true
            numberPad.isHidden = true
            symbolEmojiPanel.isHidden = false
            clipboardPanel.isHidden = true
            textEditingPanel.isHidden = true
            aiPanel.isHidden = true
            quickSettingsPanel.isHidden = true
            return
        }

        symbolCompactHeightConstraint?.isActive = false
        symbolFullBottomConstraint?.isActive = true
        lettersTopConstraint?.constant = 0

        let showMainLetters = (activePanel == .letters) && !isCandidatesExpanded
        lettersCanvas.isHidden = !showMainLetters || isUsingT9Layout
        t9Canvas.isHidden = !showMainLetters || !isUsingT9Layout
        expandedCandidates.isHidden = !isCandidatesExpanded
        numberPad.isHidden = (activePanel != .numbers)
        symbolEmojiPanel.isHidden = (activePanel != .symbolsEmoji)
        clipboardPanel.isHidden = (activePanel != .clipboard)
        textEditingPanel.isHidden = (activePanel != .textEditing)
        aiPanel.isHidden = (activePanel != .ai)
        quickSettingsPanel.isHidden = (activePanel != .quickSettings)
    }

    private func applyThemeAndSettings() {
        backdropView.apply(theme: resolvedTheme)
        toolbarView.apply(theme: resolvedTheme)
        expandedCandidates.apply(theme: resolvedTheme)
        let (retTitle, _) = returnKeyAppearance()
        numberPad.configure(theme: resolvedTheme, isChineseMode: !isEnglishMode, returnTitle: retTitle)
        symbolEmojiPanel.apply(theme: resolvedTheme)
        textEditingPanel.apply(theme: resolvedTheme)
        if activePanel == .quickSettings {
            quickSettingsPanel.updateTheme(resolvedTheme)
        }
        refreshUI()
    }

    private func refreshUI() {
        refreshToolbar()
        refreshCanvas()
        updateVisiblePanel()
    }

    private func refreshToolbar() {
        var composingDisplay: String
        if rawComposing.isEmpty {
            // 英文联想模式：输入中预览要可见（打字就有显示，不能空）
            composingDisplay = englishComposing
        } else if !isEnglishMode && !isUsingT9Layout && SmartCandidateHelper.isVToolQuery(rawComposing, scheme: settings.inputScheme) {
            if rawComposing.count == 1 && CustomWordStore.match(rawInput: rawComposing).isEmpty {
                let keyHint = settings.inputScheme == .quanpin ? "v" : "V"
                composingDisplay = "🧰 \(keyHint)模式 · 输数字转大写 / 算式 / rq时间"
            } else {
                composingDisplay = "🧰 \(rawComposing)"
            }
        } else if let uDisp = uModeDisplayBuffer, !uDisp.isEmpty {
            composingDisplay = "🔍 \(uDisp)"
        } else if let wbDisp = wubiDisplayBuffer, !wbDisp.isEmpty {
            composingDisplay = "五笔 · \(wbDisp)"
        } else if let fix = currentCorrectedHint {
            composingDisplay = "✨ 纠错: \(fix)"
        } else if !currentTokens.isEmpty {
            composingDisplay = PinyinSegmenter.displayPinyin(for: currentTokens)
        } else {
            composingDisplay = rawComposing
        }
        if !composingDisplay.isEmpty && settings.traditionalChineseEnabled && !composingDisplay.hasPrefix("🧰") {
            composingDisplay = "[繁] " + composingDisplay
        }

        let translateState: TopToolbarView.TranslateBarState? = isTranslateMode
            ? TopToolbarView.TranslateBarState(
                targetLanguage: settings.translateTargetLang,
                formalTone: settings.translateFormalTone,
                sourceText: translateSourceBuffer,
                translatedText: translatePreviewText,
                isTranslating: translateIsStreaming,
                errorText: translateErrorText
            )
            : nil

        toolbarView.update(
            composingDisplay: composingDisplay,
            candidates: currentCandidates,
            expanded: isCandidatesExpanded,
            showUndo: undoBuffer != nil,
            bannerState: pasteMonitor.bannerState,
            aiPanelActive: activePanel == .ai,
            layoutMode: settings.layoutMode,
            aiPromptDraft: aiPromptDraft,
            translateState: translateState,
            hasFullAccess: hasFullAccess
        )
    }

    private func refreshCanvas() {
        let (title, accent) = returnKeyAppearance()
        let nextLetters: Set<Character> = (!isEnglishMode && !rawComposing.isEmpty)
            ? (engine?.segmenter.validNextLetters(for: rawComposing, scheme: settings.inputScheme) ?? [])
            : []
        lettersCanvas.configure(
            theme: resolvedTheme,
            settings: settings,
            isEnglishMode: isEnglishMode,
            isComposing: !rawComposing.isEmpty,
            shiftState: shiftState,
            needsGlobeKey: needsInputModeSwitchKey,
            returnTitle: title,
            returnHighlighted: accent,
            validNextLetters: nextLetters
        )
        t9Canvas.configure(
            theme: resolvedTheme,
            settings: settings,
            isComposing: !rawComposing.isEmpty,
            leftSyllables: t9LeftSyllables,
            lockedSyllables: lockedT9Syllables,
            needsGlobeKey: needsInputModeSwitchKey,
            returnTitle: title,
            returnHighlighted: accent
        )
    }

    private func updateReturnKeyAppearance() {
        refreshCanvas()
    }

    private func returnKeyAppearance() -> (title: String, highlighted: Bool) {
        if isEmojiSearchMode {
            return ("搜表情", true)
        }
        if aiPromptDraft != nil && rawComposing.isEmpty {
            return ("问 AI", true)
        }
        if !isEnglishMode && !rawComposing.isEmpty {
            return ("确认", false)
        }
        if isTranslateMode && !translateSourceBuffer.isEmpty {
            return ("译·上屏", true)
        }
        switch textDocumentProxy.returnKeyType {
        case .send: return ("发送", true)
        case .search: return ("搜索", true)
        case .go: return ("前往", true)
        case .done: return ("完成", true)
        case .next: return ("下一项", true)
        case .join: return ("加入", true)
        case .route: return ("路线", true)
        default: return ("换行", false)
        }
    }
}
