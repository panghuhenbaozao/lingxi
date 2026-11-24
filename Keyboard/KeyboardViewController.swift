import Photos
import UIKit

/// 灵犀输入法容器根视图：实现 `UIInputViewAudioFeedback` 以支持系统原生按键音兜底。
private final class LingxiInputRootView: UIView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController, PHPhotoLibraryChangeObserver {
    private static let toolbarHeight: CGFloat = 50
    /// 顶部栏实际高度：默认 50，可由设置页候选栏高度调节（44-64）
    private var effectiveToolbarHeight: CGFloat { CGFloat(settings.candidateBarHeight) }

    private enum ActivePanel {
        case letters
        case numbers
        case clipboard
        case ai
        case voice
        case screenshot
        case quickSettings
        case editPad
    }

    // 核心引擎与服务
    private var engine: PinyinEngine?
    private let feedback = FeedbackManager()
    private let pasteMonitor = PasteboardMonitor()

    // 配置与外观
    private var settings = LingxiSettings.load(force: true)
    private var themeCustomization = ThemeCustomization.load(force: true)
    private var resolvedTheme = ResolvedTheme.resolve(isDarkAppearance: false, targetSize: CGSize(width: 430, height: 280))
    private var lastResolvedDarkAppearance: Bool?
    private var themeDarwinObserver: AppGroupNotifications.Observer?
    private var settingsDarwinObserver: AppGroupNotifications.Observer?
    private var aiConfigDarwinObserver: AppGroupNotifications.Observer?
    private var heightConstraint: NSLayoutConstraint?
    /// 顶部常驻实时输入坞高度约束（实时翻译 88pt / AI 打字框 50pt / 平时 0pt，绝不被候选词遮挡）
    private var liveDockHeightConstraint: NSLayoutConstraint?
    /// 顶部工具栏（候选栏）高度约束：设置页调整候选栏高度后需同步更新，否则键盘总高变了但候选栏区域不变
    private var toolbarHeightConstraint: NSLayoutConstraint?

    // 视图层级
    private let rootContainer = LingxiInputRootView()
    private let backdropView = KeyboardBackdropView()
    private let liveDockView = LiveInputDockView()
    private lazy var toolbarView = TopToolbarView { [weak self] text in
        self?.handleCapturedPasteFromToolbar(text)
    }
    private let bodyContainer = UIView()
    private let lettersCanvas = KeyboardCanvasView()
    private let t9Canvas = T9KeyboardCanvasView()
    private let numberPad = NumberPadView()
    private let expandedCandidates = ExpandedCandidatesView()
    private let clipboardPanel = ClipboardPanelView()
    private let aiPanel = AIAssistantPanelView()
    private let voicePanel = VoiceInputPanelView()
    private let screenshotPanel = ScreenshotVisionPanelView()
    private let quickSettingsPanel = QuickSettingsSheetView()
    private let editPadPanel = TextEditingPadView()

    private struct PendingDetectedScreenshot {
        let image: UIImage
        let jpegData: Data
        let sourceLabel: String
        let assetID: String?
        let fromPasteboard: Bool
        let detectedAt: Date
    }

    // 截屏检测（PHPhotoLibraryChangeObserver + 剪贴板图片变更：默认仅顶栏轻提示，绝不强行抢占键盘或乱弹删图框）
    private var isObservingPhotoLibrary = false
    private var lastHandledScreenshotAssetID: String?
    private var lastHandledPasteboardImageChangeCount: Int = -1
    private var pendingDetectedScreenshot: PendingDetectedScreenshot?
    private var awaitingShortcutScreenshot = false

    // 中文/英文输入状态机
    private var activePanel: ActivePanel = .letters
    private var isEnglishMode = false
    private var shiftState: ShiftState = .lowercase
    private var rawComposing = ""
    private var lockedT9Syllables: [String] = []
    private var t9LeftSyllables: [String] = []
    private var currentTokens: [PinyinToken] = []
    private var editingSyllableIndex: Int?
    private var savedSentenceCandidatesBeforeEdit: [PinyinCandidate] = []
    private var lastAIInsertedText: String?
    private var currentCorrectedHint: String?
    private var currentCandidates: [PinyinCandidate] = []
    private var isCandidatesExpanded = false
    private var pendingPhraseSegments: [(word: String, py: String)] = []
    private var lastCommittedWord: String?
    /// 精确追踪当前宿主输入框是否存在未上屏的 markedText 及其字符长度，避免空设引起 XPC 抖动或残留幽灵拼音。
    private var hasActiveMarkedText = false
    private var activeMarkedTextLength = 0

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

    // 撤销删除、双击空格句号与防吞字时序保护
    private var undoBuffer: (deletedText: String, wasComposing: Bool)?
    private var undoHideTimer: Timer?
    private var lastSpaceTapTime: CFTimeInterval = 0
    private var lastInternalEditTime: CFTimeInterval = 0
    private var lastUserKeystrokeTime: CFTimeInterval = 0
    private var lastReturnTapTime: CFTimeInterval = 0
    private var lastHostFieldSignature: String = ""
    private var lastAdaptedTraitSignature: String = ""

    // 打字习惯会话聚合器（仅记录数值行为指标到 App Group，绝不含输入原文）
    private var sessionHabitStartedAt: Date?
    private var sessionCommittedChars: Int = 0
    private var sessionCommittedWords: Int = 0
    private var sessionDeleteCount: Int = 0
    private var sessionUndoLearnCount: Int = 0
    private var sessionGlideWords: Int = 0
    private var sessionTypoCorrectedCount: Int = 0
    private var sessionConfusionCounts: [String: Int] = [:]

    // MARK: - 生命周期

    deinit {
        if isObservingPhotoLibrary {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        settings = LingxiSettings.load(force: true)
        themeCustomization = ThemeCustomization.load(force: true)
        let darkNow = isDarkInterface
        lastResolvedDarkAppearance = darkNow
        resolvedTheme = ResolvedTheme.resolve(
            customization: themeCustomization,
            isDarkAppearance: darkNow,
            targetSize: CGSize(width: 430, height: 280)
        )
        setupHierarchy()
        wireCallbacks()
        registerSharedContainerObservers()
        applyThemeAndSettings()
        preloadEngine()
    }

    private func registerSharedContainerObservers() {
        themeDarwinObserver = AppGroupNotifications.Observer(name: AppGroupNotifications.themeChanged) { [weak self] in
            self?.reloadConfigurationIfNeeded()
        }
        settingsDarwinObserver = AppGroupNotifications.Observer(name: AppGroupNotifications.settingsChanged) { [weak self] in
            self?.reloadConfigurationIfNeeded()
        }
        aiConfigDarwinObserver = AppGroupNotifications.Observer(name: AppGroupNotifications.aiConfigChanged) { [weak self] in
            guard let self else { return }
            KeyboardPermissionHeartbeat.record(hasFullAccess: self.hasFullAccess, aiConfigured: AIConfig.load().isConfigured)
            if self.activePanel == .ai {
                self.aiPanel.refreshAfterConfigChange(hasFullAccess: self.hasFullAccess)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !AppGroup.isAvailable && hasFullAccess {
            tryImportBridgeTokenFromPasteboardIfPresent()
        }
        KeyboardPermissionHeartbeat.record(hasFullAccess: hasFullAccess, aiConfigured: AIConfig.load().isConfigured)
        reloadConfigurationIfNeeded()
        lastHostFieldSignature = currentHostFieldSignature
        adaptToHostTraits()
        feedback.prepare()
        refreshClipboardState()
        updateReturnKeyAppearance()
        autoCapitalizeIfNeeded()
        if activePanel == .ai {
            aiPanel.refreshAfterConfigChange(hasFullAccess: hasFullAccess)
        } else if activePanel == .voice {
            voicePanel.refreshEngineStatus(hasFullAccess: hasFullAccess)
        }
        registerPhotoScreenshotObserverIfNeeded()
        checkPasteboardScreenshotOnAppearIfNeeded()
        if !AppGroup.isAvailable && hasFullAccess && SideloadConfigBridge.isPairedInThisProcess {
            triggerSideloadBridgeSync(force: false)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        voicePanel.stopAllRecording(runFinalTranslate: false)
        voicePanel.teardownWebAudio()
        TypingStatsStore.shared.flush()
        flushTypingHabitSessionIfNeeded()
        TouchOffsetCalibrator.shared.flush()
        if !AppGroup.isAvailable && hasFullAccess && SideloadConfigBridge.isPairedInThisProcess {
            triggerSideloadBridgeSync(force: false)
        }
    }

    @discardableResult
    private func tryImportBridgeTokenFromPasteboardIfPresent() -> Bool {
        guard hasFullAccess,
              UIPasteboard.general.hasStrings,
              let text = UIPasteboard.general.string,
              text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(SideloadConfigBridge.tokenPrefix) else {
            return false
        }
        let ok = SideloadConfigBridge.importPairingToken(text)
        if ok {
            ClipboardStore.markChangeCountHandled(UIPasteboard.general.changeCount)
            // 导入完成后立即清空剪贴板中的一次性密钥口令，防止敏感 Key 滞留系统剪贴板
            UIPasteboard.general.string = ""
            ClipboardStore.markChangeCountHandled(UIPasteboard.general.changeCount)
            reloadConfigurationIfNeeded()
            if activePanel == .ai {
                aiPanel.refreshAfterConfigChange(hasFullAccess: hasFullAccess)
            }
            if SideloadConfigBridge.isPairedInThisProcess {
                triggerSideloadBridgeSync(force: true)
            }
        }
        return ok
    }

    /// 兼容 iOS 16–18 与 APPLICATION_EXTENSION_API_ONLY=YES 的同步安全 URL 跳转：
    /// 必须在用户点击事件的同步调用栈内直接查找 UIApplication 并调用非弃用 openURL:options:completionHandler:，
    /// 避免异步切线程后丢失用户点击手势上下文导致 iOS 静默拒绝跳转（解决点击语音无法拉起主 App 的问题）。
    private func openURLFromExtension(_ url: URL, completion: @escaping (Bool) -> Void) {
        let modernSelector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication,
               current.responds(to: modernSelector),
               let imp = current.method(for: modernSelector) {
                typealias OpenURLIMP = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
                let fn = unsafeBitCast(imp, to: OpenURLIMP.self)
                let callback: @convention(block) (Bool) -> Void = { [weak self] success in
                    DispatchQueue.main.async {
                        if success {
                            completion(true)
                        } else if let ctx = self?.extensionContext {
                            ctx.open(url) { ctxOpened in
                                DispatchQueue.main.async { completion(ctxOpened) }
                            }
                        } else {
                            completion(false)
                        }
                    }
                }
                fn(current, modernSelector, url as NSURL, [:] as NSDictionary, callback)
                return
            }
            responder = current.next
        }
        if let ctx = extensionContext {
            ctx.open(url) { opened in
                DispatchQueue.main.async { completion(opened) }
            }
        } else {
            completion(false)
        }
    }

    private func triggerSideloadBridgeSync(force: Bool) {
        guard !AppGroup.isAvailable && hasFullAccess && SideloadConfigBridge.isPairedInThisProcess else { return }
        Task { [weak self] in
            let report = await SideloadConfigBridge.syncIfNeeded(force: force)
            guard let self, report != nil else { return }
            await MainActor.run {
                self.reloadConfigurationIfNeeded()
            }
        }
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
        // 仅在「跟随系统」模式下且系统给出了明确的明暗样式（忽略切换过渡时的 .unspecified 抖动）时才切换皮肤，
        // 彻底杜绝锁定浅色/深色主题时在微信/抖音/搜索框之间乱切键盘颜色。
        if styleChanged && traitCollection.userInterfaceStyle != .unspecified {
            let darkNow = isDarkInterface
            if themeCustomization.appearanceMode == .followSystem && darkNow != lastResolvedDarkAppearance {
                lastResolvedDarkAppearance = darkNow
                resolvedTheme = ResolvedTheme.resolve(
                    customization: themeCustomization,
                    isDarkAppearance: darkNow,
                    targetSize: view.bounds.size.width > 10 ? view.bounds.size : CGSize(width: 430, height: 280)
                )
                applyThemeAndSettings()
            } else if lastResolvedDarkAppearance == nil {
                lastResolvedDarkAppearance = darkNow
            }
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

    private var currentHostFieldSignature: String {
        let kb = (textDocumentProxy.keyboardType ?? .default).rawValue
        let ret = (textDocumentProxy.returnKeyType ?? .default).rawValue
        return "\(kb)|\(ret)|\(isSecureField)"
    }

    private func markUserKeystroke() {
        lastUserKeystrokeTime = CACurrentMediaTime()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let now = CACurrentMediaTime()
        let fieldSig = currentHostFieldSignature
        let hostFieldChanged = !lastHostFieldSignature.isEmpty && lastHostFieldSignature != fieldSig
        lastHostFieldSignature = fieldSig

        let sinceInternalEdit = now - lastInternalEditTime
        let sinceKeystroke = now - lastUserKeystrokeTime
        let sinceReturn = now - lastReturnTapTime

        if aiPromptDraft == nil {
            if hostFieldChanged {
                adaptToHostTraits()
            } else if sinceInternalEdit >= InputStabilityGuard.internalEditEchoWindow {
                adaptToHostTraits()
            }

            let shouldClearComposing = InputStabilityGuard.shouldClearComposingOnTextDidChange(
                hasRawComposing: !rawComposing.isEmpty,
                hasEnglishComposing: !englishComposing.isEmpty,
                hasActiveMarkedText: hasActiveMarkedText,
                hostFieldChanged: hostFieldChanged,
                secondsSinceLastInternalEdit: sinceInternalEdit,
                secondsSinceLastKeystroke: sinceKeystroke,
                secondsSinceLastReturn: sinceReturn
            )

            if shouldClearComposing {
                lastSelectionUndo = nil
                openDoubleQuote = false
                openSingleQuote = false
                if hostFieldChanged {
                    // 切换到了新输入框：旧框里的 markedText 已不适用，只重置本地标志避免往新框误发空 setMarkedText
                    hasActiveMarkedText = false
                    activeMarkedTextLength = 0
                    clearAllComposing(clearMarkedInHost: false)
                } else {
                    clearAllComposing(clearMarkedInHost: true)
                }
                refreshUI()
                autoCapitalizeIfNeeded()
            } else {
                // 保护正在输入中的中文/拼音不被发送后的异步 textDidChange 误清空（彻底根治点发送后莫名吞字）
                if InputStabilityGuard.shouldClearEnglishComposingOnTextDidChange(
                    englishComposing: englishComposing,
                    documentBeforeInput: textDocumentProxy.documentContextBeforeInput,
                    hostFieldChanged: hostFieldChanged,
                    secondsSinceLastInternalEdit: sinceInternalEdit,
                    secondsSinceLastKeystroke: sinceKeystroke,
                    secondsSinceLastReturn: sinceReturn
                ) {
                    englishComposing = ""
                    currentCandidates = []
                    refreshToolbar()
                }
                if InputStabilityGuard.shouldRefreshIdleSuggestionsOnTextDidChange(
                    hasRawComposing: !rawComposing.isEmpty,
                    hasEnglishComposing: !englishComposing.isEmpty,
                    hostFieldChanged: hostFieldChanged,
                    secondsSinceLastInternalEdit: sinceInternalEdit,
                    secondsSinceLastKeystroke: sinceKeystroke,
                    secondsSinceLastReturn: sinceReturn
                ) {
                    lastSelectionUndo = nil
                    openDoubleQuote = false
                    openSingleQuote = false
                    updateIdleSuggestions()
                    autoCapitalizeIfNeeded()
                }
            }
        }
        updateReturnKeyAppearance()
        // 打字热路径绝不频繁跨进程查 UIPasteboard，避免每敲一字卡顿
        if rawComposing.isEmpty && englishComposing.isEmpty && sinceKeystroke >= 0.8 {
            refreshClipboardState(force: false)
        }
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

        liveDockView.translatesAutoresizingMaskIntoConstraints = false
        rootContainer.addSubview(liveDockView)

        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        rootContainer.addSubview(toolbarView)

        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        rootContainer.addSubview(bodyContainer)

        NSLayoutConstraint.activate([
            liveDockView.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            liveDockView.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            liveDockView.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            { let c = liveDockView.heightAnchor.constraint(equalToConstant: 0); self.liveDockHeightConstraint = c; return c }(),

            toolbarView.topAnchor.constraint(equalTo: liveDockView.bottomAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            { let c = toolbarView.heightAnchor.constraint(equalToConstant: effectiveToolbarHeight); self.toolbarHeightConstraint = c; return c }(),

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
            clipboardPanel,
            aiPanel,
            voicePanel,
            screenshotPanel,
            quickSettingsPanel,
            editPadPanel,
        ]
        for panel in subpanels {
            panel.translatesAutoresizingMaskIntoConstraints = false
            bodyContainer.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
                panel.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
                panel.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
            ])
        }

        let totalH = effectiveToolbarHeight + CGFloat(settings.heightPreset.bodyHeight)
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
        let newSettings = LingxiSettings.load(force: true)
        let newTheme = ThemeCustomization.load(force: true)
        let darkNow = isDarkInterface
        let darkMismatch = (newTheme.appearanceMode == .followSystem && darkNow != lastResolvedDarkAppearance)
        if newSettings != settings || newTheme != themeCustomization || darkMismatch {
            let schemeOrLayoutChanged = newSettings.inputScheme != settings.inputScheme || newSettings.layoutMode != settings.layoutMode
            settings = newSettings
            themeCustomization = newTheme
            lastResolvedDarkAppearance = darkNow
            resolvedTheme = ResolvedTheme.resolve(
                customization: themeCustomization,
                isDarkAppearance: darkNow,
                targetSize: view.bounds.size.width > 10 ? view.bounds.size : CGSize(width: 430, height: 280)
            )
            if schemeOrLayoutChanged {
                clearAllComposing()
            }
            toolbarHeightConstraint?.constant = effectiveToolbarHeight
            updatePreferredHeight()
            applyThemeAndSettings()
        }
    }

    private var isDarkInterface: Bool {
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return true
        case .light:
            return false
        case .unspecified:
            if let appearance = textDocumentProxy.keyboardAppearance {
                if appearance == .dark { return true }
                if appearance == .light { return false }
            }
            return lastResolvedDarkAppearance ?? false
        @unknown default:
            return lastResolvedDarkAppearance ?? false
        }
    }

    private var isUsingT9Layout: Bool {
        settings.layoutMode == .t9Nine && !isEnglishMode && !settings.inputScheme.isWubi
    }

    private var activeContextBeforeCursor: String? {
        aiPromptDraft ?? (isTranslateMode ? translateSourceBuffer : textDocumentProxy.documentContextBeforeInput)
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
        if activePanel == .ai {
            if aiPanel.isExpandedReadingHeight {
                bodyH = isCompactLandscape ? max(baseH, 218) : max(baseH, 380)
            } else {
                bodyH = isCompactLandscape ? max(baseH, 194) : max(baseH, 312)
            }
        } else if activePanel == .screenshot {
            if screenshotPanel.isExpandedReadingHeight {
                bodyH = isCompactLandscape ? max(baseH, 218) : max(baseH, 380)
            } else {
                bodyH = isCompactLandscape ? max(baseH, 194) : max(baseH, 316)
            }
        } else if activePanel == .voice {
            bodyH = isCompactLandscape ? max(baseH, 194) : max(baseH, 296)
        } else if activePanel == .clipboard {
            bodyH = isCompactLandscape ? max(baseH, 184) : max(baseH, 268)
        } else {
            bodyH = baseH
        }
        let dockH = currentLiveDockMode().preferredHeight
        let totalH = dockH + effectiveToolbarHeight + bodyH
        if let lc = liveDockHeightConstraint, abs(lc.constant - dockH) > 0.5 {
            lc.constant = dockH
        }
        if let hc = heightConstraint, abs(hc.constant - totalH) > 0.5 {
            hc.constant = totalH
        }
    }

    private var currentLiveComposingPreview: String {
        if !rawComposing.isEmpty {
            return currentTokens.isEmpty ? rawComposing : PinyinSegmenter.displayPinyin(for: currentTokens)
        }
        return ""
    }

    private func currentLiveDockMode() -> LiveInputDockView.Mode {
        if activePanel != .ai, let draft = aiPromptDraft {
            return .aiDraft(draft: draft, liveComposing: currentLiveComposingPreview)
        }
        if isTranslateMode && activePanel != .ai {
            return .translate(LiveInputDockView.TranslateState(
                targetLanguage: settings.translateTargetLang,
                formalTone: settings.translateFormalTone,
                sourceText: translateSourceBuffer,
                liveComposing: currentLiveComposingPreview,
                translatedText: translatePreviewText,
                isTranslating: translateIsStreaming,
                errorText: translateErrorText
            ))
        }
        return .hidden
    }

    private func readLatestClipboardForDock() -> String? {
        if hasFullAccess,
           let sys = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sys.isEmpty,
           !ClipboardClassifier.isSensitiveContent(sys) {
            return sys
        }
        return ClipboardStore.items().first?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 键盘内自动截屏监听（PHPhotoLibraryChangeObserver + 剪贴板图片变更）与键盘内语音/识图入口

    private func registerPhotoScreenshotObserverIfNeeded() {
        guard hasFullAccess, !isObservingPhotoLibrary else { return }
        let st = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard st == .authorized || st == .limited else { return }
        // 记录当前最新截屏 ID，防止刚打开键盘时把几小时前的旧截屏误判为新截屏
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 1
        opts.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        if let latest = PHAsset.fetchAssets(with: .image, options: opts).firstObject {
            lastHandledScreenshotAssetID = latest.localIdentifier
        }
        PHPhotoLibrary.shared().register(self)
        isObservingPhotoLibrary = true
    }

    private func checkPasteboardScreenshotOnAppearIfNeeded() {
        guard hasFullAccess else { return }
        let pb = UIPasteboard.general
        guard pb.hasImages else { return }
        let count = pb.changeCount
        guard count != lastHandledPasteboardImageChangeCount else { return }
        lastHandledPasteboardImageChangeCount = count
        guard let img = pb.image,
              let jpeg = ScreenshotImageHelper.prepareJPEGData(from: img, maxDimension: 768, quality: 0.68) else { return }

        let shouldAutoOpen = awaitingShortcutScreenshot || settings.autoAnalyzeNewScreenshot
        awaitingShortcutScreenshot = false
        if shouldAutoOpen {
            pendingDetectedScreenshot = nil
            switchToPanel(.screenshot, autoPrepareScreenshot: false)
            screenshotPanel.presentDetectedScreenshot(
                image: img,
                jpegData: jpeg,
                sourceLabel: "剪贴板截屏 · 传完静默清空",
                assetID: nil,
                fromPasteboard: true,
                theme: resolvedTheme,
                settings: settings,
                hasFullAccess: hasFullAccess,
                autoStart: true
            )
        } else {
            // 默认无打扰轻提示：在顶栏浮出「📷 剪贴板截屏 · ✨ 识图」，点一下即识，继续打字自动消失
            pendingDetectedScreenshot = PendingDetectedScreenshot(
                image: img,
                jpegData: jpeg,
                sourceLabel: "剪贴板截屏 · 传完静默清空",
                assetID: nil,
                fromPasteboard: true,
                detectedAt: Date()
            )
            refreshToolbar()
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            opts.fetchLimit = 1
            opts.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            guard let latest = PHAsset.fetchAssets(with: .image, options: opts).firstObject,
                  let created = latest.creationDate,
                  Date().timeIntervalSince(created) <= 20 else {
                return
            }
            let assetID = latest.localIdentifier
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.hasFullAccess,
                      assetID != self.lastHandledScreenshotAssetID else { return }
                self.lastHandledScreenshotAssetID = assetID

                let req = PHImageRequestOptions()
                req.deliveryMode = .highQualityFormat
                req.isSynchronous = false
                req.isNetworkAccessAllowed = true
                req.resizeMode = .exact
                PHImageManager.default().requestImage(
                    for: latest,
                    targetSize: CGSize(width: 768, height: 768),
                    contentMode: .aspectFit,
                    options: req
                ) { [weak self] img, info in
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    guard !degraded, let self, let img,
                          let jpeg = ScreenshotImageHelper.prepareJPEGData(from: img, maxDimension: 768, quality: 0.68) else { return }
                    DispatchQueue.main.async {
                        if self.settings.autoAnalyzeNewScreenshot {
                            self.pendingDetectedScreenshot = nil
                            self.switchToPanel(.screenshot, autoPrepareScreenshot: false)
                            self.screenshotPanel.presentDetectedScreenshot(
                                image: img,
                                jpegData: jpeg,
                                sourceLabel: "刚刚捕获的新截屏",
                                assetID: assetID,
                                fromPasteboard: false,
                                theme: self.resolvedTheme,
                                settings: self.settings,
                                hasFullAccess: self.hasFullAccess,
                                autoStart: true
                            )
                        } else {
                            // 关键改进：截屏后绝不强行劫持键盘，更绝不自动弹删除确认框！仅在顶栏温和提示，想识图点一下就行
                            self.pendingDetectedScreenshot = PendingDetectedScreenshot(
                                image: img,
                                jpegData: jpeg,
                                sourceLabel: "刚刚捕获的新截屏",
                                assetID: assetID,
                                fromPasteboard: false,
                                detectedAt: Date()
                            )
                            self.refreshToolbar()
                        }
                    }
                }
            }
        }
    }

    private func openHostScreenshotWorkbench(deleteAssetID: String? = nil) {
        let urlStr: String
        if let assetID = deleteAssetID, !assetID.isEmpty,
           let encoded = assetID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlStr = "lingxi://screenshot-ai?deleteId=\(encoded)"
        } else {
            urlStr = "lingxi://screenshot-ai?auto=1"
        }
        guard let url = URL(string: urlStr) else { return }
        openURLFromExtension(url) { _ in }
    }

    private func triggerAutoScreenshotShortcut() {
        // 不再跳转用户尚未安装的苹果快捷指令（避免提示「没有这个命令」），改为直接在键盘内读取最新截屏或打开选图工作台
        openHostScreenshotWorkbench(deleteAssetID: nil)
    }

    private func handleOpenScreenshotAI() {
        commitRawIfNeeded()
        if !AppGroup.isAvailable && hasFullAccess {
            _ = tryImportBridgeTokenFromPasteboardIfPresent()
        }
        // 彻底留在键盘内完成截屏预览、AI 识图、自动删图与插入上屏，绝不强跳主 App！
        switchToPanel(activePanel == .screenshot ? .letters : .screenshot)
    }

    private func openHostPermissionsCenter(completion: ((Bool) -> Void)? = nil) {
        if let url = URL(string: "lingxi://permissions") {
            openURLFromExtension(url) { [weak self] opened in
                if opened {
                    completion?(true)
                } else if let self, let sysURL = URL(string: "app-settings:") {
                    self.openURLFromExtension(sysURL) { sysOpened in
                        completion?(sysOpened)
                    }
                } else {
                    completion?(false)
                }
            }
        } else {
            completion?(false)
        }
    }

    private func handleOpenInKeyboardVoicePanel() {
        commitRawIfNeeded()
        if !AppGroup.isAvailable && hasFullAccess {
            _ = tryImportBridgeTokenFromPasteboardIfPresent()
        }
        // 彻底留在键盘内完成语音识别与双语实时转换，绝不强跳主 App！
        switchToPanel(activePanel == .voice ? .letters : .voice)
    }

    private func openHostVoiceWarmUp(completion: ((Bool) -> Void)? = nil) {
        guard let url = URL(string: "lingxi://voice-warmup") else {
            completion?(false)
            return
        }
        openURLFromExtension(url) { opened in
            completion?(opened)
        }
    }

    private func openHostVoiceTranslator(mode: VoiceTranslateMode? = nil, completion: ((Bool) -> Void)? = nil) {
        var urlStr = "lingxi://voice-translate?autostart=1"
        if let mode {
            urlStr += "&mode=\(mode.rawValue)"
        }
        guard let url = URL(string: urlStr) else {
            completion?(false)
            return
        }
        openURLFromExtension(url) { opened in
            completion?(opened)
        }
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

        clipboardPanel.onInsertText = { [weak self] text in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .letter, settings: self.settings, hasFullAccess: self.hasFullAccess)
            let rendered = DynamicTemplateEngine.render(
                text,
                clipboard: ClipboardStore.items().first?.text,
                selectedText: self.textDocumentProxy.selectedText
            )
            self.insertFinalText(rendered, checkPairing: false)
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

        aiPanel.onInsertText = { [weak self] text in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .modifier, settings: self.settings, hasFullAccess: self.hasFullAccess)
            self.exitTransientAIAndTranslateModes()
            self.lastAIInsertedText = text
            self.insertDirectlyIntoHost(text)
            self.switchToPanel(.letters)
        }
        aiPanel.onReplaceBeforeCursor = { [weak self] deleteCount, replacement in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .modifier, settings: self.settings, hasFullAccess: self.hasFullAccess)
            self.exitTransientAIAndTranslateModes()
            self.lastAIInsertedText = replacement
            self.performEdit {
                for _ in 0..<deleteCount {
                    self.textDocumentProxy.deleteBackward()
                }
                self.textDocumentProxy.insertText(replacement)
            }
            if self.shouldAllowPanguSpace, self.settings.typingStatsEnabled, !replacement.isEmpty {
                TypingStatsStore.shared.recordCommit(text: replacement)
            }
            self.switchToPanel(.letters)
        }
        liveDockView.onAction = { [weak self] action in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .modifier, settings: self.settings, hasFullAccess: self.hasFullAccess)
            switch action {
            case .cycleTranslateTarget:
                self.cycleTranslateTargetLanguage()
            case .toggleTranslateTone:
                self.settings.translateFormalTone.toggle()
                self.settings.save()
                self.translateErrorText = nil
                if !self.translateSourceBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.triggerTranslation(immediately: true)
                } else {
                    self.refreshToolbar()
                }
            case .pasteIntoTranslate:
                if let clip = self.readLatestClipboardForDock(), !clip.isEmpty {
                    self.clearAllComposing()
                    self.translateSourceBuffer = clip
                    self.triggerTranslation(immediately: true)
                } else {
                    self.translateErrorText = self.hasFullAccess ? "剪贴板为空，请先复制要翻译的内容" : "需开启「允许完全访问」才可读取剪贴板"
                    self.refreshToolbar()
                }
            case .openVoiceTranslator:
                self.handleOpenInKeyboardVoicePanel()
            case .clearTranslateSource:
                self.cancelLiveTranslation()
                self.clearAllComposing()
                self.translateSourceBuffer = ""
                self.translatePreviewText = ""
                self.translateIsStreaming = false
                self.translateErrorText = nil
                self.refreshUI()
            case .closeTranslate:
                self.toggleTranslateMode()
            case .commitTranslatedText:
                self.commitTranslatedOutput()
            case .commitTranslateSource:
                self.commitTranslateSourceOutput()
            case .tapTranslateErrorFix:
                if !self.hasFullAccess {
                    if let url = URL(string: "app-settings:") {
                        self.openURLFromExtension(url) { _ in }
                    }
                } else if let url = URL(string: "lingxi://ai-settings") {
                    self.openURLFromExtension(url) { _ in }
                }
            case .pasteIntoAIDraft:
                if let clip = self.readLatestClipboardForDock(), !clip.isEmpty {
                    let existing = self.aiPromptDraft ?? ""
                    self.aiPromptDraft = existing.isEmpty ? clip : (existing + " " + clip)
                    self.refreshUI()
                }
            case .clearAIDraft:
                self.clearAllComposing()
                self.aiPromptDraft = ""
                self.refreshUI()
            case .sendAIDraft:
                self.handleToolbarAction(.sendAIPrompt)
            case .returnToAIPanel:
                self.commitRawIfNeeded()
                let draft = self.aiPromptDraft ?? ""
                self.aiPromptDraft = nil
                self.switchToPanel(.ai)
                self.aiPanel.prepare(
                    theme: self.resolvedTheme,
                    hasFullAccess: self.hasFullAccess,
                    beforeCursor: self.textDocumentProxy.documentContextBeforeInput ?? "",
                    clipboardText: nil,
                    preferredAction: nil,
                    preservedDraft: draft
                )
            }
        }

        aiPanel.onBeginTypingPrompt = { [weak self] existingDraft in
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
            self.aiPromptDraft = existingDraft
            self.switchToPanel(.letters)
        }
        aiPanel.onReadingHeightChanged = { [weak self] _ in
            guard let self else { return }
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.updatePreferredHeight()
                self.view.layoutIfNeeded()
            }
        }
        aiPanel.onOpenFullAccessSettings = { [weak self] done in
            guard let self else { done(false); return }
            if let settingsURL = URL(string: "app-settings:") {
                self.openURLFromExtension(settingsURL) { [weak self] opened in
                    if opened {
                        done(true)
                    } else if let self, let appPermURL = URL(string: "lingxi://permissions") {
                        self.openURLFromExtension(appPermURL, completion: done)
                    } else {
                        done(false)
                    }
                }
            } else {
                done(false)
            }
        }
        aiPanel.onOpenHostAppAI = { [weak self] done in
            guard let self, let url = URL(string: "lingxi://ai-settings") else {
                done(false)
                return
            }
            self.openURLFromExtension(url, completion: done)
        }
        aiPanel.onImportBridgeToken = { [weak self] in
            self?.tryImportBridgeTokenFromPasteboardIfPresent() ?? false
        }
        aiPanel.onTriggerScreenshotVision = { [weak self] in
            self?.handleOpenScreenshotAI()
        }
        aiPanel.onOpenScreenshotWorkbench = { [weak self] deleteAssetID in
            self?.openHostScreenshotWorkbench(deleteAssetID: deleteAssetID)
        }
        aiPanel.onClose = { [weak self] in
            self?.aiPromptDraft = nil
            self?.switchToPanel(.letters)
        }

        voicePanel.onInsertText = { [weak self] text in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .modifier, settings: self.settings, hasFullAccess: self.hasFullAccess)
            self.exitTransientAIAndTranslateModes()
            self.insertDirectlyIntoHost(text)
            self.switchToPanel(.letters)
        }
        voicePanel.onReplaceBeforeCursor = { [weak self] deleteCount, replacement in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .modifier, settings: self.settings, hasFullAccess: self.hasFullAccess)
            self.exitTransientAIAndTranslateModes()
            self.performEdit {
                for _ in 0..<deleteCount {
                    self.textDocumentProxy.deleteBackward()
                }
                self.textDocumentProxy.insertText(replacement)
            }
            if self.shouldAllowPanguSpace, self.settings.typingStatsEnabled, !replacement.isEmpty {
                TypingStatsStore.shared.recordCommit(text: replacement)
            }
            self.switchToPanel(.letters)
        }
        voicePanel.onFetchHostInputContext = { [weak self] in
            self?.textDocumentProxy.documentContextBeforeInput ?? ""
        }
        voicePanel.onWarmUpHostVoiceEngine = { [weak self] done in
            self?.openHostVoiceWarmUp(completion: done)
        }
        voicePanel.onOpenFullVoiceWorkbench = { [weak self] mode, done in
            self?.openHostVoiceTranslator(mode: mode, completion: done)
        }
        voicePanel.onOpenPermissions = { [weak self] done in
            self?.openHostPermissionsCenter(completion: done)
        }
        voicePanel.onClose = { [weak self] in
            self?.switchToPanel(.letters)
        }

        screenshotPanel.onInsertText = { [weak self] text in
            guard let self else { return }
            self.feedback.triggerKeyFeedback(tone: .modifier, settings: self.settings, hasFullAccess: self.hasFullAccess)
            self.exitTransientAIAndTranslateModes()
            self.insertDirectlyIntoHost(text)
            self.switchToPanel(.letters)
        }
        screenshotPanel.onSettingsChanged = { [weak self] updated in
            self?.settings = updated
            self?.triggerSideloadBridgeSync(force: true)
        }
        screenshotPanel.onReadingHeightChanged = { [weak self] _ in
            guard let self else { return }
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.updatePreferredHeight()
                self.view.layoutIfNeeded()
            }
        }
        screenshotPanel.onTriggerAutoScreenshotShortcut = { [weak self] in
            self?.triggerAutoScreenshotShortcut()
        }
        screenshotPanel.onOpenPermissions = { [weak self] in
            self?.openHostPermissionsCenter()
        }
        screenshotPanel.onImportBridgeToken = { [weak self] in
            self?.tryImportBridgeTokenFromPasteboardIfPresent() ?? false
        }
        screenshotPanel.onOpenHostAppAI = { [weak self] in
            guard let url = URL(string: "lingxi://ai-settings") else { return }
            self?.openURLFromExtension(url) { _ in }
        }
        screenshotPanel.onOpenHostDeleteAsset = { [weak self] assetID in
            self?.openHostScreenshotWorkbench(deleteAssetID: assetID)
        }
        screenshotPanel.onOpenHostWorkbench = { [weak self] in
            self?.openHostScreenshotWorkbench(deleteAssetID: nil)
        }
        screenshotPanel.onClose = { [weak self] in
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
            } else if !updated.bigramPredictionEnabled {
                self.currentCandidates = []
                self.lastCommittedWord = nil
            }
            if translateLangChanged && self.isTranslateMode && !self.translateSourceBuffer.isEmpty {
                self.triggerTranslation(immediately: true)
            }
            self.applyThemeAndSettings()
            self.triggerSideloadBridgeSync(force: true)
        }
        quickSettingsPanel.onThemeChanged = { [weak self] updatedTheme in
            guard let self else { return }
            let darkNow = self.isDarkInterface
            self.themeCustomization = updatedTheme
            self.lastResolvedDarkAppearance = darkNow
            self.resolvedTheme = ResolvedTheme.resolve(
                customization: updatedTheme,
                isDarkAppearance: darkNow,
                targetSize: self.view.bounds.size.width > 10 ? self.view.bounds.size : CGSize(width: 430, height: 280)
            )
            self.applyThemeAndSettings()
            self.triggerSideloadBridgeSync(force: true)
        }
        quickSettingsPanel.onBridgeSyncNow = { [weak self] in
            guard let self else { return }
            if !self.tryImportBridgeTokenFromPasteboardIfPresent() {
                self.triggerSideloadBridgeSync(force: true)
            }
        }
        quickSettingsPanel.onOpenEditPad = { [weak self] in
            self?.switchToPanel(.editPad)
        }
        quickSettingsPanel.onOpenPermissions = { [weak self] in
            self?.openHostPermissionsCenter()
        }
        quickSettingsPanel.onClose = { [weak self] in
            self?.switchToPanel(.letters)
        }

        editPadPanel.onAction = { [weak self] action in
            self?.handleEditPadAction(action)
        }
        editPadPanel.onClose = { [weak self] in
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
            markUserKeystroke()
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
        markUserKeystroke()
        lastSpaceTapTime = 0
        guard let engine else { return }
        clearUndoBuffer()

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
            markUserKeystroke()
            lastSpaceTapTime = 0
            feedback.triggerKeyFeedback(tone: .letter, settings: settings, hasFullAccess: hasFullAccess)
            clearUndoBuffer()
            rawComposing.append(d)
            recomputeCandidates()

        case .segmentSeparator:
            markUserKeystroke()
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            if !rawComposing.isEmpty && rawComposing.last != "'" {
                rawComposing.append("'")
                recomputeCandidates()
            }

        case .selectSyllable(let syl):
            markUserKeystroke()
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            lockedT9Syllables.append(syl)
            recomputeCandidates()

        case .insertSymbol(let sym):
            markUserKeystroke()
            lastSpaceTapTime = 0
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
            markUserKeystroke()
            lastSpaceTapTime = 0
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
            markUserKeystroke()
            feedback.triggerKeyFeedback(tone: .delete, settings: settings, hasFullAccess: hasFullAccess)
            performBackspace(isRepeat: false)
            updateIdleSuggestions()
        case .space:
            markUserKeystroke()
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            insertFinalText(" ", checkPairing: false)
        case .returnKey:
            feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
            handleReturnTap()
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
            } else if let draft = aiPromptDraft {
                commitRawIfNeeded()
                aiPromptDraft = nil
                switchToPanel(.ai)
                aiPanel.prepare(
                    theme: resolvedTheme,
                    hasFullAccess: hasFullAccess,
                    beforeCursor: textDocumentProxy.documentContextBeforeInput ?? "",
                    clipboardText: nil,
                    preferredAction: nil,
                    preservedDraft: draft
                )
            } else {
                openAIPanel(preferredAction: nil, explicitClipboard: nil)
            }
        case .toggleTranslateMode:
            toggleTranslateMode()
        case .openScreenshotAI:
            handleOpenScreenshotAI()
        case .analyzeDetectedScreenshot:
            if let pending = pendingDetectedScreenshot {
                pendingDetectedScreenshot = nil
                switchToPanel(.screenshot, autoPrepareScreenshot: false)
                screenshotPanel.presentDetectedScreenshot(
                    image: pending.image,
                    jpegData: pending.jpegData,
                    sourceLabel: pending.sourceLabel,
                    assetID: pending.assetID,
                    fromPasteboard: pending.fromPasteboard,
                    theme: resolvedTheme,
                    settings: settings,
                    hasFullAccess: hasFullAccess,
                    autoStart: true
                )
            } else {
                handleOpenScreenshotAI()
            }
        case .dismissDetectedScreenshot:
            pendingDetectedScreenshot = nil
            refreshToolbar()
        case .openVoiceTranslator:
            handleOpenInKeyboardVoicePanel()
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
        case .toggleEditPad:
            switchToPanel(activePanel == .editPad ? .letters : .editPad)
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
        case .clipboardIntentAI(let intent, let text):
            pasteMonitor.dismissCurrent()
            if let customInst = intent.customInstruction {
                switchToPanel(.ai)
                aiPanel.runDirectInstruction(
                    title: intent.badge,
                    instruction: customInst,
                    sourceText: text,
                    replaceCount: 0,
                    theme: resolvedTheme,
                    hasFullAccess: hasFullAccess
                )
            } else {
                openAIPanel(preferredAction: intent.action, explicitClipboard: text)
            }
        case .selectionQuickAI(let title, let instruction):
            let sel = (textDocumentProxy.selectedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sel.isEmpty else { return }
            switchToPanel(.ai)
            aiPanel.runDirectInstruction(
                title: title,
                instruction: instruction,
                sourceText: sel,
                replaceCount: 1,
                theme: resolvedTheme,
                hasFullAccess: hasFullAccess
            )
        case .executeInlineAICommand(let command, let replaceCount):
            switchToPanel(.ai)
            aiPanel.runDirectInstruction(
                title: "@ai 随打即唤",
                instruction: "请严格按用户的直接指令完成写作或回答，只直接输出可直接发送的结果正文，不要多余解释与引号。",
                sourceText: command,
                replaceCount: replaceCount,
                theme: resolvedTheme,
                hasFullAccess: hasFullAccess
            )
        case .tapComposingSyllable(let idx):
            enterRetroactiveSyllableEdit(at: idx)
        case .askAIForWord(let word):
            switchToPanel(.ai)
            aiPanel.runDirectInstruction(
                title: "换更高级说法",
                instruction: "请给「\(word)」提供3个更得体、高级或生动的中文替换说法或完整例句，简洁直接。",
                sourceText: word,
                replaceCount: 0,
                theme: resolvedTheme,
                hasFullAccess: hasFullAccess
            )
        case .saveWordAsPhrase(let word):
            QuickPhraseStore.add(title: String(word.prefix(6)), content: word, category: "常用")
            refreshToolbar()
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
        case .dismissSuggestions:
            isCandidatesExpanded = false
            currentCandidates = []
            lastCommittedWord = nil
            refreshUI()
        case .dismissKeyboard:
            dismissKeyboard()
        }
    }

    // MARK: - 拼音 / 英文 / 纠错处理核心

    private func handleCharacterInput(_ ch: String) {
        markUserKeystroke()
        lastSpaceTapTime = 0
        clearUndoBuffer()
        lastSelectionUndo = nil

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
            // 中英数零切换混输：全拼拼音串（>=2 字母）中直接敲数字（如 mingtian3dianjian -> 明天3点见）保持组合态
            if settings.inputScheme == .quanpin && !isUsingT9Layout && ch.count == 1 && ch.allSatisfy(\.isNumber) && !isVToolHead && rawComposing.count >= 2 && rawComposing.contains(where: \.isLetter) {
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
        markUserKeystroke()
        lastSelectionUndo = nil

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

        if isTranslateMode {
            // 实时翻译模式下按空格自然输入空格（不误断英文句子）；按回车「译·上屏」或点上方「上屏」提交译文
            if !translateSourceBuffer.isEmpty {
                insertFinalText(" ", checkPairing: false)
                refreshUI()
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
        let now = CACurrentMediaTime()
        lastUserKeystrokeTime = now
        lastSpaceTapTime = 0
        lastSelectionUndo = nil

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

        // 先快照 AI 润色差异，避免在发送临界路径上做磁盘 I/O 阻塞 "\n" 投递
        let aiOrigSnapshot = lastAIInsertedText
        let beforeSnapshot = (aiOrigSnapshot != nil)
            ? textDocumentProxy.documentContextBeforeInput?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        // 发送前彻底清净残留状态，并记录 lastReturnTapTime 供 textDidChange 防吞字保护窗使用
        lastReturnTapTime = now
        lastAIInsertedText = nil
        englishComposing = ""
        lastCommittedWord = nil
        currentCandidates = []
        isCandidatesExpanded = false
        pendingPhraseSegments.removeAll()
        openDoubleQuote = false
        openSingleQuote = false
        clearMarkedTextIfNeeded()

        // 回车 / 发送键永远直接投递给宿主输入框（微信发送、Safari 搜索、备忘录换行），绝不允许被翻译框或草稿拦截吞掉！
        performEdit {
            self.textDocumentProxy.insertText("\n")
        }
        refreshUI()
        autoCapitalizeIfNeeded()

        if let aiOrig = aiOrigSnapshot,
           let finalBefore = beforeSnapshot,
           !finalBefore.isEmpty, finalBefore != aiOrig, finalBefore.count <= 400 {
            DispatchQueue.global(qos: .utility).async {
                var cfg = AIConfig.load()
                AIAutoInsightService.learnFromUserEditDiff(aiOriginal: aiOrig, userFinal: finalBefore, into: &cfg.styleDNA)
                cfg.save()
            }
        }
    }

    private func performBackspace(isRepeat: Bool = false) {
        markUserKeystroke()
        lastSpaceTapTime = 0
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

        // 已上屏后按 ⌫：绝不把旧拼音重新拉回屏幕（避免“打出去的字还在、拼音又回来了”的干扰体验）。
        // 仅在静默后台撤回刚刚误学的词频记录，然后直接执行标准单字符退格删除。
        if !isRepeat, let selUndo = lastSelectionUndo, !selUndo.isExpired {
            lastSelectionUndo = nil
            sessionUndoLearnCount += 1
            if let rec = selUndo.learnRecord {
                engine?.userLexicon.undoLearn(rec)
            }
            if let extra = selUndo.extraLearnRecord {
                engine?.userLexicon.undoLearn(extra)
            }
            if selUndo.learnRecord != nil || selUndo.extraLearnRecord != nil {
                engine?.invalidateCache()
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
        clearMarkedTextIfNeeded()
        sessionDeleteCount += 1
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
        if englishComposing.isEmpty && !currentCandidates.isEmpty {
            currentCandidates = []
            refreshToolbar()
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

    private func clearAllComposing(clearMarkedInHost: Bool = true) {
        rawComposing = ""
        lockedT9Syllables.removeAll()
        t9LeftSyllables.removeAll()
        currentTokens = []
        editingSyllableIndex = nil
        savedSentenceCandidatesBeforeEdit = []
        currentCorrectedHint = nil
        wubiEmptyCode = false
        wubiDisplayBuffer = nil
        uModeDisplayBuffer = nil
        isLastInputFromGlide = false
        currentCandidates = []
        isCandidatesExpanded = false
        pendingPhraseSegments.removeAll()
        englishComposing = ""
        if clearMarkedInHost {
            clearMarkedTextIfNeeded()
        } else {
            hasActiveMarkedText = false
            activeMarkedTextLength = 0
        }
    }

    private func clearMarkedTextIfNeeded() {
        guard hasActiveMarkedText else { return }
        hasActiveMarkedText = false
        activeMarkedTextLength = 0
        performEdit {
            self.textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            self.textDocumentProxy.unmarkText()
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
        // 每次输入或退格重算候选时，必须退出音节局部回改态，避免旧句缓存污染新候选选词
        editingSyllableIndex = nil
        savedSentenceCandidatesBeforeEdit = []
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
            let hadUModeHits = !merged.isEmpty
            // 修复「点 u 不显示字母 / 输 u 开头英文无候选」Bug：
            // 始终保留原文与英文前缀直出候选（如 u / ui / url / user / update），同时完整保留拆字/笔画命中置顶！
            var seenU = Set(merged.map(\.word))
            if seenU.insert(rawComposing).inserted {
                merged.insert(
                    PinyinCandidate(
                        word: rawComposing,
                        py: "",
                        lp: hadUModeHits ? -5.0 : 0.0,
                        consumed: rawComposing.count,
                        isExact: true,
                        source: .englishDirect
                    ),
                    at: hadUModeHits ? min(1, merged.count) : 0
                )
            }
            if settings.smartEnglishCandidate {
                for (idx, ew) in engine.queryEnglish(prefix: rawComposing, limit: 6).enumerated()
                where seenU.insert(ew).inserted {
                    merged.append(PinyinCandidate(
                        word: ew,
                        py: "",
                        lp: -2.0 - Double(idx) * 0.1,
                        consumed: rawComposing.count,
                        isExact: ew.lowercased() == rawComposing.lowercased(),
                        source: .englishDirect
                    ))
                }
            }
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
        guard settings.inlineComposingEnabled, aiPromptDraft == nil, !isTranslateMode, !isEnglishMode else {
            clearMarkedTextIfNeeded()
            return
        }
        let marked = currentCorrectedHint ?? (currentTokens.isEmpty ? rawComposing : PinyinSegmenter.displayPinyin(for: currentTokens))
        guard !marked.isEmpty else {
            clearMarkedTextIfNeeded()
            return
        }
        hasActiveMarkedText = true
        activeMarkedTextLength = marked.count
        performEdit {
            self.textDocumentProxy.setMarkedText(marked, selectedRange: NSRange(location: marked.utf16.count, length: 0))
        }
    }

    private func selectCandidate(at index: Int) {
        guard currentCandidates.indices.contains(index) else { return }
        markUserKeystroke()
        lastSpaceTapTime = 0
        // 选词反馈：一次按键级震动 + 一声音效即可，不再叠加 triggerCursorTick（双震会粘连）。
        feedback.triggerKeyFeedback(tone: .letter, settings: settings, hasFullAccess: hasFullAccess)
        feedback.triggerCursorSound(settings: settings)
        clearUndoBuffer()
        let cand = currentCandidates[index]

        // 点击拼音条音节「免退格局部换字」：把选中的同音单字直接拼回整句第 idx 位并恢复整句首位！
        if let editIdx = editingSyllableIndex, !savedSentenceCandidatesBeforeEdit.isEmpty {
            let baseList = savedSentenceCandidatesBeforeEdit
            editingSyllableIndex = nil
            savedSentenceCandidatesBeforeEdit = []
            if let baseSent = baseList.first {
                var chars = Array(baseSent.word)
                if editIdx >= 0 && editIdx < chars.count, let newCh = cand.word.first {
                    chars[editIdx] = newCh
                    let patchedWord = String(chars)
                    let patchedCand = PinyinCandidate(
                        word: patchedWord,
                        py: baseSent.py,
                        lp: baseSent.lp + 2.0,
                        consumed: baseSent.consumed,
                        isExact: true,
                        source: baseSent.source
                    )
                    var merged = [patchedCand] + baseList.filter { $0.word != patchedWord }
                    if merged.isEmpty { merged = [patchedCand] }
                    currentCandidates = merged
                    expandedCandidates.update(candidates: merged)
                    refreshUI()
                    return
                }
            }
        }

        // 英文模式下点选补全词或滑行替换词，替换掉已输入的前缀或刚滑行上屏的词
        if isEnglishMode && cand.source == .englishDirect {
            let expectedPrefix: String
            if !englishComposing.isEmpty {
                expectedPrefix = englishComposing
            } else if let glideUndo = lastSelectionUndo, glideUndo.rawComposing.isEmpty, !glideUndo.committedText.isEmpty {
                expectedPrefix = glideUndo.committedText
            } else {
                expectedPrefix = ""
            }
            if !expectedPrefix.isEmpty {
                let prevWord = lastSelectionUndo?.prevLastCommittedWord
                englishComposing = ""
                currentCandidates = []
                let kbType = textDocumentProxy.keyboardType ?? .default
                let suppressSpace = (kbType == .emailAddress || kbType == .URL || kbType == .webSearch || cand.word.contains("."))
                let trailing = suppressSpace ? "" : " "
                let replacement = cand.word + trailing
                if aiPromptDraft != nil {
                    var d = aiPromptDraft ?? ""
                    let del = InputStabilityGuard.safeEnglishReplacementDeleteLength(expectedPrefix: expectedPrefix, documentBeforeInput: d)
                    if del > 0 { d.removeLast(del) }
                    aiPromptDraft = d + replacement
                    refreshUI()
                } else if isTranslateMode {
                    let del = InputStabilityGuard.safeEnglishReplacementDeleteLength(expectedPrefix: expectedPrefix, documentBeforeInput: translateSourceBuffer)
                    if del > 0 { translateSourceBuffer.removeLast(del) }
                    appendToTranslateSource(replacement)
                } else {
                    let safeDeleteLen = InputStabilityGuard.safeEnglishReplacementDeleteLength(
                        expectedPrefix: expectedPrefix,
                        documentBeforeInput: textDocumentProxy.documentContextBeforeInput
                    )
                    performEdit {
                        for _ in 0..<safeDeleteLen {
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
        editingSyllableIndex = nil
        savedSentenceCandidatesBeforeEdit = []
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
        // 关键防吞字优化：当直接上屏到宿主输入框时，绝不先发 setMarkedText("") + unmarkText() 再 insertText（3次异步XPC易丢字），
        // 而是由 insertText 单次原子替换并取消 markedText；仅重定向到 AI 草稿/翻译框时才单独清理宿主 markedText。
        let replacingMarkedLen: Int
        if aiPromptDraft == nil && !isTranslateMode {
            replacingMarkedLen = hasActiveMarkedText ? activeMarkedTextLength : 0
            hasActiveMarkedText = false
            activeMarkedTextLength = 0
        } else {
            replacingMarkedLen = 0
            clearMarkedTextIfNeeded()
        }
        if isLastInputFromGlide {
            sessionGlideWords += 1
        }
        if currentCorrectedHint != nil {
            sessionTypoCorrectedCount += 1
        }
        if settings.inputScheme == .quanpin && !prevRaw.isEmpty && !cand.py.isEmpty {
            let detected = TypingHabitTracker.detectPinyinConfusions(rawInput: prevRaw, resolvedPinyin: cand.py)
            for (k, v) in detected where v > 0 {
                sessionConfusionCounts[k, default: 0] += v
            }
        }
        let actualInserted = insertFinalText(outputWord, checkPairing: false, replacingMarkedLength: replacingMarkedLen)

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
        let willInsertToHost = !clean.isEmpty && aiPromptDraft == nil && !isTranslateMode
        let replacingMarkedLen = (willInsertToHost && hasActiveMarkedText) ? activeMarkedTextLength : 0
        clearAllComposing(clearMarkedInHost: !willInsertToHost)
        if !clean.isEmpty {
            insertFinalText(clean, checkPairing: false, replacingMarkedLength: replacingMarkedLen)
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
    private func insertFinalText(_ text: String, checkPairing: Bool, replacingMarkedLength: Int = 0) -> String {
        if text != "\n" {
            if let draft = aiPromptDraft {
                aiPromptDraft = draft + text
                refreshToolbar()
                return text
            }

            if isTranslateMode {
                appendToTranslateSource(text)
                return text
            }
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
               text != "\n",
               (self.settings.panguSpaceLetters || self.settings.panguSpaceDigits) {
                var effectiveBefore = self.textDocumentProxy.documentContextBeforeInput
                if replacingMarkedLength > 0, let rawBefore = effectiveBefore {
                    effectiveBefore = rawBefore.count >= replacingMarkedLength
                        ? String(rawBefore.dropLast(replacingMarkedLength))
                        : ""
                }
                if PanguSpacer.needsLeadingSpace(
                    beforeCursor: effectiveBefore,
                    inserting: text,
                    spaceLetters: self.settings.panguSpaceLetters,
                    spaceDigits: self.settings.panguSpaceDigits
                ) {
                    inserted = " " + text
                    self.textDocumentProxy.insertText(inserted)
                    return
                }
            }

            self.textDocumentProxy.insertText(text)
        }
        // 打字统计与实时习惯画像采样：仅统计真实上屏文本；密码/邮箱/网址等隐私框与换行键不统计
        if self.shouldAllowPanguSpace, !inserted.isEmpty, inserted != "\n" {
            if self.settings.typingStatsEnabled {
                TypingStatsStore.shared.recordCommit(text: inserted)
            }
            if self.sessionHabitStartedAt == nil {
                self.sessionHabitStartedAt = Date()
            }
            self.sessionCommittedChars += inserted.count
            self.sessionCommittedWords += 1
            if self.sessionCommittedChars >= 8 {
                self.flushTypingHabitSessionIfNeeded()
            }
        }
        return inserted
    }

    private func flushTypingHabitSessionIfNeeded() {
        guard sessionCommittedChars > 0 else { return }
        let start = sessionHabitStartedAt ?? Date()
        let dur = max(1, min(300, Int(Date().timeIntervalSince(start))))
        let event = TypingHabitEventPayload(
            startedAt: Int(start.timeIntervalSince1970),
            durationSeconds: dur,
            committedChars: sessionCommittedChars,
            committedWords: max(1, sessionCommittedWords),
            deleteCount: sessionDeleteCount,
            undoLearnCount: sessionUndoLearnCount,
            glideWords: sessionGlideWords,
            typoCorrectedCount: sessionTypoCorrectedCount,
            schemeID: settings.inputScheme.rawValue,
            layoutID: settings.layoutMode.rawValue,
            confusionCounts: sessionConfusionCounts
        )
        sessionHabitStartedAt = nil
        sessionCommittedChars = 0
        sessionCommittedWords = 0
        sessionDeleteCount = 0
        sessionUndoLearnCount = 0
        sessionGlideWords = 0
        sessionTypoCorrectedCount = 0
        sessionConfusionCounts = [:]
        // 异步落盘，彻底避免每打满 8 字时主线程同步写 JSON 引发掉帧
        DispatchQueue.global(qos: .utility).async {
            _ = TypingHabitTracker.shared.recordTypingEvent(event)
        }
    }

    private func insertDirectlyIntoHost(_ text: String) {
        performEdit {
            if self.shouldAllowPanguSpace,
               text != "\n",
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
        if shouldAllowPanguSpace, settings.typingStatsEnabled, text != "\n", !text.isEmpty {
            TypingStatsStore.shared.recordCommit(text: text)
        }
    }

    /// 上屏 AI 回答或翻译结果后彻底收起翻译框与 AI 草稿态，立刻恢复正常键盘与宿主「发送」键。
    private func exitTransientAIAndTranslateModes() {
        cancelLiveTranslation()
        aiPromptDraft = nil
        isTranslateMode = false
        translateSourceBuffer = ""
        translatePreviewText = ""
        translateIsStreaming = false
        translateErrorText = nil
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
            aiPromptDraft = nil
            clearAllComposing()
            if !AppGroup.isAvailable && hasFullAccess {
                _ = tryImportBridgeTokenFromPasteboardIfPresent()
            }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: work)
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
                    config: cfg,
                    featureTag: "live_translate",
                    preferFast: true
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
                        self.translatePreviewText = AITextSanitizer.clean(accumulated, streaming: true)
                        self.translateIsStreaming = true
                        self.translateErrorText = nil
                        self.refreshToolbar()
                    }
                }
                try Task.checkCancellation()
                let finalResult = AITextSanitizer.clean(accumulated, streaming: false)
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
        let src = translateSourceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return }
        lastSelectionUndo = nil
        insertDirectlyIntoHost(out)
        AIRecentHistoryStore.record(title: "实时翻译", output: out, prompt: src)
        // 上屏后自动关闭翻译框架并恢复普通键盘，确保紧接着点「发送」键能直接发出去！
        exitTransientAIAndTranslateModes()
        refreshUI()
    }

    private func commitTranslateSourceOutput() {
        let out = translateSourceBuffer
        guard !out.isEmpty else { return }
        lastSelectionUndo = nil
        insertDirectlyIntoHost(out)
        exitTransientAIAndTranslateModes()
        refreshUI()
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

    private func refreshClipboardState(force: Bool = true) {
        guard !isSecureField else {
            pasteMonitor.dismissCurrent()
            refreshToolbar()
            return
        }
        pasteMonitor.refresh(settings: settings, force: force) { [weak self] _ in
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
        if !AppGroup.isAvailable && hasFullAccess {
            _ = tryImportBridgeTokenFromPasteboardIfPresent()
        }
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

    private func switchToPanel(_ target: ActivePanel, autoPrepareScreenshot: Bool = true) {
        if activePanel == .voice && target != .voice {
            voicePanel.stopAllRecording(runFinalTranslate: false)
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
        case .quickSettings:
            reloadConfigurationIfNeeded()
            quickSettingsPanel.configure(
                theme: resolvedTheme,
                settings: settings,
                customization: themeCustomization,
                isSystemDark: isDarkInterface
            )
        case .numbers:
            let (retTitle, _) = returnKeyAppearance()
            numberPad.configure(theme: resolvedTheme, isChineseMode: !isEnglishMode, returnTitle: retTitle)
        case .editPad:
            editPadPanel.apply(theme: resolvedTheme)
        case .voice:
            voicePanel.prepare(theme: resolvedTheme, hasFullAccess: hasFullAccess)
        case .screenshot:
            if autoPrepareScreenshot {
                screenshotPanel.prepare(
                    theme: resolvedTheme,
                    settings: settings,
                    hasFullAccess: hasFullAccess,
                    autoAnalyzeLatest: true
                )
            }
        case .letters, .ai:
            break
        }
        refreshUI()
    }

    private func updateVisiblePanel() {
        let showMainLetters = (activePanel == .letters) && !isCandidatesExpanded
        lettersCanvas.isHidden = !showMainLetters || isUsingT9Layout
        t9Canvas.isHidden = !showMainLetters || !isUsingT9Layout
        expandedCandidates.isHidden = !isCandidatesExpanded
        numberPad.isHidden = (activePanel != .numbers)
        clipboardPanel.isHidden = (activePanel != .clipboard)
        aiPanel.isHidden = (activePanel != .ai)
        voicePanel.isHidden = (activePanel != .voice)
        screenshotPanel.isHidden = (activePanel != .screenshot)
        quickSettingsPanel.isHidden = (activePanel != .quickSettings)
        editPadPanel.isHidden = (activePanel != .editPad)
    }

    private func applyThemeAndSettings() {
        // 强制锁死自身 tintColor 与背景底色，彻底防止抖音/B站/其他宿主 App 的紫色系统主题色渗入键盘按钮
        view.tintColor = resolvedTheme.accentFill
        rootContainer.tintColor = resolvedTheme.accentFill
        rootContainer.backgroundColor = resolvedTheme.canvasTop
        backdropView.apply(theme: resolvedTheme)
        liveDockView.apply(theme: resolvedTheme)
        toolbarView.apply(theme: resolvedTheme)
        expandedCandidates.apply(theme: resolvedTheme)
        editPadPanel.apply(theme: resolvedTheme)
        // 候选字号可调：单行候选条与展开网格联动应用
        toolbarView.candidateBar.applyCandidateFontSize(CGFloat(settings.candidateFontSize))
        expandedCandidates.applyCandidateFontSize(CGFloat(settings.candidateFontSize))
        let (retTitle, _) = returnKeyAppearance()
        numberPad.configure(theme: resolvedTheme, isChineseMode: !isEnglishMode, returnTitle: retTitle)
        if activePanel == .quickSettings {
            quickSettingsPanel.updateTheme(
                resolvedTheme,
                settings: settings,
                customization: themeCustomization,
                isSystemDark: isDarkInterface
            )
        } else if activePanel == .clipboard {
            clipboardPanel.configure(
                theme: resolvedTheme,
                activeFontStyle: StylishFontStyle(rawValue: settings.stylishFontID) ?? .normal
            )
        } else if activePanel == .ai {
            aiPanel.applyTheme(resolvedTheme)
        } else if activePanel == .voice {
            voicePanel.applyTheme(resolvedTheme)
        } else if activePanel == .screenshot {
            screenshotPanel.applyTheme(resolvedTheme)
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

        // 当用户未在主动拼写 (rawComposing 与 englishComposing 均为空) 且存在未处理的「新复制内容 / 短信验证码」时，
        // 顶栏优先展示全栏剪贴板/验证码接管胶囊，暂不展示闲置下一词联想，确保复制即见！
        let isActivelyComposing = !rawComposing.isEmpty || !englishComposing.isEmpty
        let effectiveCandidates = (!isActivelyComposing && pasteMonitor.bannerState != .hidden)
            ? []
            : currentCandidates

        let isVToolActive = !rawComposing.isEmpty && !isEnglishMode && !isUsingT9Layout && SmartCandidateHelper.isVToolQuery(rawComposing, scheme: settings.inputScheme)
        let composingSyllables: [String] = (!rawComposing.isEmpty && !isUsingT9Layout && !isVToolActive && !settings.traditionalChineseEnabled && currentCorrectedHint == nil && wubiDisplayBuffer == nil && uModeDisplayBuffer == nil && currentTokens.count >= 2 && currentTokens.allSatisfy({ !($0.lockedSyllable ?? $0.text).isEmpty }))
            ? currentTokens.map { $0.lockedSyllable ?? $0.text }
            : []
        let activeSelectedText: String? = (!isActivelyComposing && settings.selectionMagicEnabled && !isSecureField)
            ? textDocumentProxy.selectedText
            : nil
        let inlineAICmd: InlineAICommandMatch? = (!isSecureField && !isActivelyComposing && activePanel == .letters)
            ? InlineAICommandDetector.detect(in: textDocumentProxy.documentContextBeforeInput ?? "")
            : nil

        liveDockView.update(mode: currentLiveDockMode())
        updatePreferredHeight()

        if isActivelyComposing {
            pendingDetectedScreenshot = nil
        } else if let pending = pendingDetectedScreenshot, Date().timeIntervalSince(pending.detectedAt) > 45 {
            pendingDetectedScreenshot = nil
        }
        let screenshotPillLabel: String? = (!isActivelyComposing && activePanel == .letters)
            ? pendingDetectedScreenshot.map { $0.fromPasteboard ? "📷 剪贴板截屏" : "📷 刚截的屏" }
            : nil

        let isIdlePredictionMode = !isActivelyComposing && !effectiveCandidates.isEmpty
        toolbarView.update(
            composingDisplay: composingDisplay,
            composingSyllables: composingSyllables,
            activeSyllableIndex: editingSyllableIndex,
            candidates: effectiveCandidates,
            expanded: isCandidatesExpanded,
            showUndo: undoBuffer != nil,
            bannerState: pasteMonitor.bannerState,
            aiPanelActive: activePanel == .ai,
            layoutMode: settings.layoutMode,
            aiPromptDraft: aiPromptDraft,
            translateState: translateState,
            selectedHostText: activeSelectedText,
            inlineAICommand: inlineAICmd,
            hasFullAccess: hasFullAccess,
            toolbarLayout: settings.toolbarLayout,
            showComposingStrip: settings.showComposingStrip,
            isIdlePredictionMode: isIdlePredictionMode,
            screenshotDetectedLabel: screenshotPillLabel
        )
    }

    // MARK: - v5.0 专业编辑台与长句点击音节免退格回溯改字

    private func enterRetroactiveSyllableEdit(at idx: Int) {
        guard currentTokens.indices.contains(idx), let engine else { return }
        if editingSyllableIndex == idx {
            editingSyllableIndex = nil
            if !savedSentenceCandidatesBeforeEdit.isEmpty {
                currentCandidates = savedSentenceCandidatesBeforeEdit
                savedSentenceCandidatesBeforeEdit = []
                expandedCandidates.update(candidates: currentCandidates)
            }
            refreshUI()
            return
        }
        if savedSentenceCandidatesBeforeEdit.isEmpty {
            savedSentenceCandidatesBeforeEdit = currentCandidates
        }
        editingSyllableIndex = idx
        let singleList = engine.candidatesForSingleToken(currentTokens[idx], isT9: isUsingT9Layout, settings: settings, limit: 48)
        if !singleList.isEmpty {
            currentCandidates = singleList
            expandedCandidates.update(candidates: singleList)
        }
        refreshUI()
    }

    private func handleEditPadAction(_ action: TextEditingPadView.EditAction) {
        feedback.triggerKeyFeedback(tone: .modifier, settings: settings, hasFullAccess: hasFullAccess)
        switch action {
        case .moveLeft:
            performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: -1) }
        case .moveRight:
            performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: 1) }
        case .moveUp:
            performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: -16) }
        case .moveDown:
            performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: 16) }
        case .lineStart:
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            let rev = before.reversed()
            let dist = rev.firstIndex(of: "\n").map { rev.distance(from: rev.startIndex, to: $0) } ?? before.count
            if dist > 0 { performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: -dist) } }
        case .lineEnd:
            let after = textDocumentProxy.documentContextAfterInput ?? ""
            let dist = after.firstIndex(of: "\n").map { after.distance(from: after.startIndex, to: $0) } ?? after.count
            if dist > 0 { performEdit { self.textDocumentProxy.adjustTextPosition(byCharacterOffset: dist) } }
        case .copy:
            if let sel = textDocumentProxy.selectedText, !sel.isEmpty {
                UIPasteboard.general.string = sel
                _ = ClipboardStore.record(sel)
            }
        case .cut:
            if let sel = textDocumentProxy.selectedText, !sel.isEmpty {
                UIPasteboard.general.string = sel
                _ = ClipboardStore.record(sel)
                performEdit { self.textDocumentProxy.deleteBackward() }
            }
        case .paste:
            if let txt = UIPasteboard.general.string ?? ClipboardStore.items().first?.text, !txt.isEmpty {
                insertDirectlyIntoHost(txt)
            }
        case .selectAll:
            break
        case .deleteBackward:
            performBackspace(isRepeat: false)
        case .formatPanguSpace:
            if let sel = textDocumentProxy.selectedText, !sel.isEmpty {
                let formatted = TextFormatterToolbox.addPanguSpaces(sel)
                performEdit {
                    self.textDocumentProxy.deleteBackward()
                    self.textDocumentProxy.insertText(formatted)
                }
            } else if let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty {
                let chunk = String(before.suffix(120))
                let formatted = TextFormatterToolbox.addPanguSpaces(chunk)
                if formatted != chunk {
                    performEdit {
                        for _ in 0..<chunk.count { self.textDocumentProxy.deleteBackward() }
                        self.textDocumentProxy.insertText(formatted)
                    }
                }
            }
        case .formatCollapseLines:
            if let sel = textDocumentProxy.selectedText, !sel.isEmpty {
                let formatted = TextFormatterToolbox.collapseBlankLines(sel)
                performEdit {
                    self.textDocumentProxy.deleteBackward()
                    self.textDocumentProxy.insertText(formatted)
                }
            } else if let clip = UIPasteboard.general.string ?? ClipboardStore.items().first?.text, !clip.isEmpty {
                insertDirectlyIntoHost(TextFormatterToolbox.collapseBlankLines(clip))
            }
        }
    }

    private func refreshCanvas() {
        let (title, accent) = returnKeyAppearance()
        if isUsingT9Layout {
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
        } else {
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
        }
    }

    private func updateReturnKeyAppearance() {
        refreshCanvas()
    }

    private func returnKeyAppearance() -> (title: String, highlighted: Bool) {
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
