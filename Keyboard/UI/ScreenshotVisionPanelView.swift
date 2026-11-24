import Photos
import UIKit

/// 键盘内嵌「📷 自动截屏 & AI 识图」专属工作台（v5.6 新增，彻底留在键盘内完成识图与插入，绝不强跳主 App！）：
/// - 顶部实时展示刚抓取的截屏缩略图 + 来源时间 + 「⚡ 自动截屏」「↻ 刷新」「✓ 传后删」「返回」；
/// - 5 大高频视觉技能（看图回复 / 提取文字 / 截屏译中 / 总结重点 / 解答分析）+ 「🔔 自动识屏」开关；
/// - 流式输出经过 `AITextSanitizer` 彻底净化（0 个 `*` 符号），上传完成后按设置自动删除原截屏；
/// - 支持一键「复制」「插入上屏」直接填进微信/抖音输入框！
final class ScreenshotVisionPanelView: UIView, UITextViewDelegate {
    var onInsertText: ((String) -> Void)?
    var onSettingsChanged: ((LingxiSettings) -> Void)?
    var onReadingHeightChanged: ((Bool) -> Void)?
    /// 调用 iOS 快捷指令 `shortcuts://run-shortcut?name=灵犀截屏识图` 实现真·一键截屏拷入剪贴板
    var onTriggerAutoScreenshotShortcut: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onOpenHostDeleteAsset: ((String) -> Void)?
    var onOpenHostWorkbench: (() -> Void)?
    var onClose: (() -> Void)?

    private let aiClient = AIClient(timeout: 40)
    private var streamTask: Task<Void, Never>?

    private var theme: ResolvedTheme?
    private var settings = LingxiSettings.load()
    private var hasFullAccess = false

    private var currentPreset: ScreenshotVisionPreset = .smartReply
    private var capturedImage: UIImage?
    private var capturedJPEGData: Data?
    private var capturedAssetID: String?
    private var capturedFromPasteboard = false
    private var sourceDescription = "尚未检测到截屏"
    private var generatedText = ""
    private var deletionStatusNotice: String?
    private var pendingHostDeleteAssetID: String?
    private(set) var isExpandedReadingHeight = false

    // Row 1: 缩略图 + 来源状态 + 自动截屏 + 刷新 + 传后删开关 + 返回
    private let thumbImageView = UIImageView()
    private let sourceTitleLabel = UILabel()
    private let sourceSubLabel = UILabel()
    private let autoShotButton = ActionClosureButton(type: .system)
    private let refreshButton = ActionClosureButton(type: .system)
    private let autoDeleteToggleButton = ActionClosureButton(type: .system)
    private let closeButton = ActionClosureButton(type: .system)

    // Row 2: 5 大视觉模式胶囊 + 自动识屏开关 + 拉高按钮
    private let presetsScroll = LingxiScrollView()
    private let presetsStack = UIStackView()
    private let heightToggleButton = ActionClosureButton(type: .system)

    // Row 3: 识别结果正文区（可选中复制 + 滑动自动拉高）
    private let outputTextView = UITextView()

    // 快捷提示/删图确认/权限修复条
    private let actionNoticeBar = UIStackView()
    private let noticePrimaryButton = ActionClosureButton(type: .system)
    private let noticeSecondaryButton = ActionClosureButton(type: .system)

    // Bottom bar: 重试/停止 · 复制 · 选图 · 插入上屏
    private let bottomBar = UIStackView()
    private let retryButton = ActionClosureButton(type: .system)
    private let copyButton = ActionClosureButton(type: .system)
    private let workbenchButton = ActionClosureButton(type: .system)
    private let insertButton = ActionClosureButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        streamTask?.cancel()
    }

    private func setupViews() {
        thumbImageView.contentMode = .scaleAspectFill
        thumbImageView.clipsToBounds = true
        thumbImageView.layer.cornerRadius = 8
        thumbImageView.layer.cornerCurve = .continuous
        thumbImageView.layer.borderWidth = 0.6
        addSubview(thumbImageView)

        sourceTitleLabel.font = .systemFont(ofSize: 12.5, weight: .bold)
        sourceTitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(sourceTitleLabel)

        sourceSubLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        sourceSubLabel.lineBreakMode = .byTruncatingTail
        addSubview(sourceSubLabel)

        autoShotButton.setTitle("⚡截屏", for: .normal)
        autoShotButton.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .bold)
        autoShotButton.layer.cornerRadius = 9
        autoShotButton.layer.cornerCurve = .continuous
        autoShotButton.accessibilityLabel = "调用快捷指令一键自动截屏"
        autoShotButton.actionHandler = { [weak self] in
            self?.handleTriggerAutoScreenshot()
        }
        addSubview(autoShotButton)

        let refImg = UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        refreshButton.setImage(refImg, for: .normal)
        refreshButton.layer.cornerRadius = 9
        refreshButton.layer.cornerCurve = .continuous
        refreshButton.accessibilityLabel = "刷新抓取最新截屏"
        refreshButton.actionHandler = { [weak self] in
            self?.scanLatestScreenshot(autoAnalyze: true)
        }
        addSubview(refreshButton)

        autoDeleteToggleButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        autoDeleteToggleButton.layer.cornerRadius = 9
        autoDeleteToggleButton.layer.cornerCurve = .continuous
        autoDeleteToggleButton.actionHandler = { [weak self] in
            guard let self else { return }
            self.settings.autoDeleteUploadedScreenshot.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.updateAutoDeleteBadge()
        }
        addSubview(autoDeleteToggleButton)

        closeButton.setTitle("返回", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        closeButton.layer.cornerRadius = 9
        closeButton.layer.cornerCurve = .continuous
        closeButton.actionHandler = { [weak self] in
            self?.streamTask?.cancel()
            self?.setExpandedReadingHeight(false)
            self?.onClose?()
        }
        addSubview(closeButton)

        presetsScroll.showsHorizontalScrollIndicator = false
        addSubview(presetsScroll)
        presetsStack.axis = .horizontal
        presetsStack.spacing = 6
        presetsStack.alignment = .center
        presetsScroll.addSubview(presetsStack)

        let expImg = UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        heightToggleButton.setImage(expImg, for: .normal)
        heightToggleButton.layer.cornerRadius = 13
        heightToggleButton.layer.cornerCurve = .continuous
        heightToggleButton.actionHandler = { [weak self] in
            guard let self else { return }
            self.setExpandedReadingHeight(!self.isExpandedReadingHeight)
        }
        addSubview(heightToggleButton)

        outputTextView.isEditable = false
        outputTextView.isSelectable = true
        outputTextView.delegate = self
        outputTextView.font = .systemFont(ofSize: 14, weight: .regular)
        outputTextView.layer.cornerRadius = 11
        outputTextView.layer.cornerCurve = .continuous
        outputTextView.textContainerInset = UIEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        addSubview(outputTextView)

        actionNoticeBar.axis = .horizontal
        actionNoticeBar.spacing = 6
        actionNoticeBar.distribution = .fill
        actionNoticeBar.isHidden = true
        addSubview(actionNoticeBar)

        noticePrimaryButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        noticePrimaryButton.layer.cornerRadius = 9
        noticePrimaryButton.layer.cornerCurve = .continuous
        noticePrimaryButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        noticePrimaryButton.actionHandler = { [weak self] in self?.handleNoticePrimaryTap() }
        actionNoticeBar.addArrangedSubview(noticePrimaryButton)

        noticeSecondaryButton.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        noticeSecondaryButton.layer.cornerRadius = 9
        noticeSecondaryButton.layer.cornerCurve = .continuous
        noticeSecondaryButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
        noticeSecondaryButton.setContentHuggingPriority(.required, for: .horizontal)
        noticeSecondaryButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        noticeSecondaryButton.isHidden = true
        noticeSecondaryButton.actionHandler = { [weak self] in self?.handleNoticeSecondaryTap() }
        actionNoticeBar.addArrangedSubview(noticeSecondaryButton)

        bottomBar.axis = .horizontal
        bottomBar.distribution = .fillEqually
        bottomBar.spacing = 6
        addSubview(bottomBar)

        retryButton.setTitle("识别", for: .normal)
        retryButton.actionHandler = { [weak self] in self?.handleRetryOrStop() }
        copyButton.setTitle("复制", for: .normal)
        copyButton.actionHandler = { [weak self] in self?.handleCopy() }
        workbenchButton.setTitle("选图/引导", for: .normal)
        workbenchButton.actionHandler = { [weak self] in self?.onOpenHostWorkbench?() }
        insertButton.setTitle("插入上屏", for: .normal)
        insertButton.actionHandler = { [weak self] in self?.handleInsert() }

        for btn in [retryButton, copyButton, workbenchButton, insertButton] {
            btn.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
            btn.layer.cornerRadius = 9
            btn.layer.cornerCurve = .continuous
            bottomBar.addArrangedSubview(btn)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === outputTextView,
              !isExpandedReadingHeight,
              scrollView.contentSize.height > scrollView.bounds.height + 10 else {
            return
        }
        setExpandedReadingHeight(true)
    }

    private func setExpandedReadingHeight(_ expanded: Bool) {
        guard isExpandedReadingHeight != expanded else { return }
        isExpandedReadingHeight = expanded
        onReadingHeightChanged?(expanded)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 8
        let topY: CGFloat = 7
        let row1H: CGFloat = 36

        let closeW: CGFloat = 42
        let delW: CGFloat = 54
        let refW: CGFloat = 30
        let shotW: CGFloat = 50

        closeButton.frame = CGRect(x: bounds.width - pad - closeW, y: topY, width: closeW, height: row1H)
        autoDeleteToggleButton.frame = CGRect(x: closeButton.frame.minX - 4 - delW, y: topY, width: delW, height: row1H)
        refreshButton.frame = CGRect(x: autoDeleteToggleButton.frame.minX - 4 - refW, y: topY, width: refW, height: row1H)
        autoShotButton.frame = CGRect(x: refreshButton.frame.minX - 4 - shotW, y: topY, width: shotW, height: row1H)

        thumbImageView.frame = CGRect(x: pad, y: topY, width: row1H, height: row1H)
        let titleX = thumbImageView.frame.maxX + 7
        let titleW = max(50, autoShotButton.frame.minX - 6 - titleX)
        sourceTitleLabel.frame = CGRect(x: titleX, y: topY + 2, width: titleW, height: 17)
        sourceSubLabel.frame = CGRect(x: titleX, y: topY + 19, width: titleW, height: 14)

        let row2Y = thumbImageView.frame.maxY + 6
        let row2H: CGFloat = 30
        let hBtnW: CGFloat = 30
        heightToggleButton.frame = CGRect(x: bounds.width - pad - hBtnW, y: row2Y, width: hBtnW, height: row2H)
        let scrollW = max(80, heightToggleButton.frame.minX - 6)
        presetsScroll.frame = CGRect(x: 0, y: row2Y, width: scrollW, height: row2H)
        let natW = ceil(presetsStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
        presetsStack.frame = CGRect(x: pad, y: 0, width: natW, height: row2H)
        presetsScroll.contentSize = CGSize(width: max(scrollW, natW + pad * 2), height: row2H)

        let bottomH: CGFloat = 36
        bottomBar.frame = CGRect(x: pad, y: bounds.height - bottomH - 7, width: bounds.width - pad * 2, height: bottomH)

        var contentBottom = bottomBar.frame.minY
        if !actionNoticeBar.isHidden {
            let noticeH: CGFloat = 32
            actionNoticeBar.frame = CGRect(x: pad, y: contentBottom - noticeH - 6, width: bounds.width - pad * 2, height: noticeH)
            contentBottom = actionNoticeBar.frame.minY
        }

        let outY = presetsScroll.frame.maxY + 6
        outputTextView.frame = CGRect(x: pad, y: outY, width: bounds.width - pad * 2, height: max(54, contentBottom - outY - 6))
    }

    // MARK: - 外部入口

    func prepare(
        theme: ResolvedTheme,
        settings: LingxiSettings,
        hasFullAccess: Bool,
        autoAnalyzeLatest: Bool
    ) {
        self.theme = theme
        self.settings = settings
        self.hasFullAccess = hasFullAccess
        applyTheme(theme)
        rebuildPresetPills()
        updateAutoDeleteBadge()
        scanLatestScreenshot(autoAnalyze: autoAnalyzeLatest)
    }

    func presentDetectedScreenshot(
        image: UIImage,
        jpegData: Data,
        sourceLabel: String,
        assetID: String?,
        fromPasteboard: Bool,
        theme: ResolvedTheme,
        settings: LingxiSettings,
        hasFullAccess: Bool,
        autoStart: Bool
    ) {
        self.theme = theme
        self.settings = settings
        self.hasFullAccess = hasFullAccess
        self.capturedImage = image
        self.capturedJPEGData = jpegData
        self.capturedAssetID = assetID
        self.capturedFromPasteboard = fromPasteboard
        self.sourceDescription = sourceLabel
        self.deletionStatusNotice = nil
        self.pendingHostDeleteAssetID = nil

        applyTheme(theme)
        rebuildPresetPills()
        updateAutoDeleteBadge()
        updateThumbnailUI()
        refreshNoticeBar()

        if autoStart {
            startVisionRecognition()
        } else {
            outputTextView.text = "✓ 已自动捕获「\(sourceLabel)」。\n点上方「💬 看图回复 / 📝 提取文字 / 🌐 截屏译中」立即在键盘内识别。"
            updateButtonsEnabled()
        }
    }

    func applyTheme(_ theme: ResolvedTheme) {
        self.theme = theme
        backgroundColor = theme.canvasTop.withAlphaComponent(0.98)

        thumbImageView.backgroundColor = theme.specialKeyFill
        thumbImageView.layer.borderColor = theme.keyBorder.cgColor
        sourceTitleLabel.textColor = theme.keyText
        sourceSubLabel.textColor = theme.keyHintText

        autoShotButton.backgroundColor = theme.accentFill.withAlphaComponent(0.16)
        autoShotButton.setTitleColor(theme.candidateHighlight, for: .normal)
        refreshButton.backgroundColor = theme.specialKeyFill
        refreshButton.tintColor = theme.keyText
        closeButton.backgroundColor = theme.specialKeyFill
        closeButton.setTitleColor(theme.keyText, for: .normal)

        heightToggleButton.backgroundColor = theme.specialKeyFill
        heightToggleButton.tintColor = theme.keyText

        outputTextView.backgroundColor = theme.keyFill.withAlphaComponent(0.96)
        outputTextView.textColor = theme.keyText
        outputTextView.tintColor = theme.accentFill

        noticePrimaryButton.backgroundColor = theme.accentFill
        noticePrimaryButton.setTitleColor(theme.accentText, for: .normal)
        noticeSecondaryButton.backgroundColor = theme.specialKeyFill
        noticeSecondaryButton.setTitleColor(theme.keyText, for: .normal)

        retryButton.backgroundColor = theme.specialKeyFill
        retryButton.setTitleColor(theme.keyText, for: .normal)
        copyButton.backgroundColor = theme.specialKeyFill
        copyButton.setTitleColor(theme.keyText, for: .normal)
        workbenchButton.backgroundColor = theme.specialKeyFill
        workbenchButton.setTitleColor(theme.keyText, for: .normal)
        insertButton.backgroundColor = theme.accentFill
        insertButton.setTitleColor(theme.accentText, for: .normal)

        updateAutoDeleteBadge()
    }

    private func updateAutoDeleteBadge() {
        let on = settings.autoDeleteUploadedScreenshot
        autoDeleteToggleButton.setTitle(on ? "✓传后删" : "保留图", for: .normal)
        if let theme {
            autoDeleteToggleButton.backgroundColor = on ? theme.accentFill.withAlphaComponent(0.18) : theme.specialKeyFill
            autoDeleteToggleButton.setTitleColor(on ? theme.candidateHighlight : theme.keyHintText, for: .normal)
        }
    }

    private func rebuildPresetPills() {
        presetsStack.arrangedSubviews.forEach {
            presetsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let theme else { return }

        for p in ScreenshotVisionPreset.allCases {
            let active = (p == currentPreset)
            let btn = ActionClosureButton(type: .system)
            btn.setTitle(p.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            btn.backgroundColor = active ? theme.accentFill : theme.keyFill
            btn.setTitleColor(active ? theme.accentText : theme.keyText, for: .normal)
            btn.layer.cornerRadius = 13
            btn.layer.cornerCurve = .continuous
            btn.layer.borderWidth = active ? 0 : 0.5
            btn.layer.borderColor = theme.keyBorder.cgColor
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
            btn.actionHandler = { [weak self] in
                guard let self else { return }
                self.currentPreset = p
                self.rebuildPresetPills()
                if self.capturedJPEGData != nil {
                    self.startVisionRecognition()
                } else {
                    self.scanLatestScreenshot(autoAnalyze: true)
                }
            }
            presetsStack.addArrangedSubview(btn)
        }

        // 「自动识屏」开关胶囊：截屏后自动弹出本面板并开始 AI 识图
        let autoBtn = ActionClosureButton(type: .system)
        let autoOn = settings.autoAnalyzeNewScreenshot
        autoBtn.setTitle(autoOn ? "🔔 自动识屏:开" : "🔕 自动识屏:关", for: .normal)
        autoBtn.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .semibold)
        autoBtn.backgroundColor = autoOn ? theme.accentFill.withAlphaComponent(0.16) : theme.specialKeyFill
        autoBtn.setTitleColor(autoOn ? theme.candidateHighlight : theme.keyHintText, for: .normal)
        autoBtn.layer.cornerRadius = 13
        autoBtn.layer.cornerCurve = .continuous
        autoBtn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
        autoBtn.actionHandler = { [weak self] in
            guard let self else { return }
            self.settings.autoAnalyzeNewScreenshot.toggle()
            self.settings.save()
            self.onSettingsChanged?(self.settings)
            self.rebuildPresetPills()
        }
        presetsStack.addArrangedSubview(autoBtn)
        setNeedsLayout()
    }

    // MARK: - 键盘内实时抓取最新截屏（剪贴板优先 → 相册最新截屏）

    func scanLatestScreenshot(autoAnalyze: Bool) {
        pendingHostDeleteAssetID = nil
        deletionStatusNotice = nil

        // 1. 优先读取剪贴板中的截屏（例如快捷指令「截屏→拷贝至剪贴板」或系统截屏点「拷贝并删除」）
        if hasFullAccess,
           UIPasteboard.general.hasImages,
           let img = UIPasteboard.general.image,
           let jpeg = ScreenshotImageHelper.prepareJPEGData(from: img) {
            capturedImage = img
            capturedJPEGData = jpeg
            capturedAssetID = nil
            capturedFromPasteboard = true
            sourceDescription = "剪贴板截屏 · 传完秒清"
            updateThumbnailUI()
            refreshNoticeBar()
            if autoAnalyze {
                startVisionRecognition()
            } else {
                outputTextView.text = "✓ 已读取剪贴板截屏（\(max(1, jpeg.count / 1024)) KB）。点上方「看图回复 / 提取文字 / 截屏译中」开始识别。"
                updateButtonsEnabled()
            }
            return
        }

        // 2. 读取相册最近 30 分钟内最新一张系统截屏
        let photoAuth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if photoAuth == .authorized || photoAuth == .limited {
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            opts.fetchLimit = 3
            opts.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            let fetched = PHAsset.fetchAssets(with: .image, options: opts)
            if let latest = fetched.firstObject,
               let created = latest.creationDate,
               Date().timeIntervalSince(created) <= 1800 {
                let assetID = latest.localIdentifier
                let ageSec = Int(max(0, Date().timeIntervalSince(created)))
                let ageText = ageSec < 60 ? "\(ageSec)秒前" : "\(ageSec / 60)分钟前"
                let req = PHImageRequestOptions()
                req.deliveryMode = .highQualityFormat
                req.isSynchronous = false
                req.isNetworkAccessAllowed = true
                req.resizeMode = .fast
                outputTextView.text = "📷 正在读取最新截屏（\(ageText)）…"
                PHImageManager.default().requestImage(
                    for: latest,
                    targetSize: CGSize(width: 1280, height: 1280),
                    contentMode: .aspectFit,
                    options: req
                ) { [weak self] img, info in
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    guard !degraded, let self, let img,
                          let jpeg = ScreenshotImageHelper.prepareJPEGData(from: img) else { return }
                    DispatchQueue.main.async {
                        self.capturedImage = img
                        self.capturedJPEGData = jpeg
                        self.capturedAssetID = assetID
                        self.capturedFromPasteboard = false
                        self.sourceDescription = "最新截屏 · \(ageText)"
                        self.updateThumbnailUI()
                        self.refreshNoticeBar()
                        if autoAnalyze {
                            self.startVisionRecognition()
                        } else {
                            self.outputTextView.text = "✓ 已自动读取最新截屏（\(ageText)）。点上方功能即可在键盘内识图回复。"
                            self.updateButtonsEnabled()
                        }
                    }
                }
                return
            }
        }

        // 3. 尚未截取新图或未授权相册
        capturedImage = nil
        capturedJPEGData = nil
        capturedAssetID = nil
        capturedFromPasteboard = false
        sourceDescription = (photoAuth == .authorized || photoAuth == .limited) ? "等待新截屏" : "未授权相册截屏读取"
        updateThumbnailUI()
        refreshNoticeBar()

        if !hasFullAccess {
            outputTextView.text = "⚠️ 请先开启「允许完全访问」权限，再使用键盘内截屏 AI 识图。"
        } else if photoAuth != .authorized && photoAuth != .limited {
            outputTextView.text = "📷 在键盘内自动识图只需 1 步：\n1. 点下方「一键授权相册」允许读取/清理截屏；\n2. 以后在微信/抖音随手截屏（电源+音量上 或 轻点手机背面），键盘 1 秒内自动抓图识图，无需切换 App！"
        } else {
            outputTextView.text = "📷 键盘已开启实时截屏监听（当前暂无 30 分钟内新截屏）：\n• 直接按「电源+音量上」或「轻点背面两下」截屏，键盘将自动抓图并识别；\n• 也可点右上「⚡截屏」触发苹果快捷指令「灵犀截屏识图」（2步：截屏→拷贝至剪贴板，传完自动清空不留相册）。"
        }
        updateButtonsEnabled()
    }

    // MARK: - 键盘内多模态 AI 流式识别 + 上传后自动删除原截屏

    private func startVisionRecognition() {
        streamTask?.cancel()
        guard hasFullAccess else {
            refreshNoticeBar()
            outputTextView.text = "⚠️ 请先开启键盘「允许完全访问」才可联网识图。"
            return
        }
        let cfg = AIConfig.load()
        guard cfg.isConfigured else {
            refreshNoticeBar()
            outputTextView.text = "⚠️ 请先在灵犀 App「AI」页配置 API Key（推荐 Gemini / GPT-4o / Qwen-VL 等视觉模型）。"
            return
        }
        guard let jpeg = capturedJPEGData else {
            scanLatestScreenshot(autoAnalyze: true)
            return
        }

        generatedText = ""
        deletionStatusNotice = nil
        pendingHostDeleteAssetID = nil
        retryButton.setTitle("停止", for: .normal)
        let kb = max(1, jpeg.count / 1024)
        outputTextView.text = "📷 正在键盘内上传截屏（\(kb) KB）· 执行「\(currentPreset.title)」…"
        updateButtonsEnabled()

        let presetSnap = currentPreset
        let autoDel = settings.autoDeleteUploadedScreenshot
        let fromPB = capturedFromPasteboard
        let assetID = capturedAssetID

        streamTask = Task { [weak self] in
            guard let self else { return }
            var acc = ""
            var lastFlush = CACurrentMediaTime()
            var cleanedUp = false

            func cleanupOriginalScreenshotIfNeeded() async {
                guard autoDel, !cleanedUp else { return }
                cleanedUp = true
                if fromPB {
                    await MainActor.run {
                        UIPasteboard.general.items = []
                        self.capturedFromPasteboard = false
                        self.deletionStatusNotice = "✓ 已自动清空剪贴板原截屏（零相册残留）"
                        self.sourceSubLabel.text = self.deletionStatusNotice
                    }
                }
                if let assetID, !assetID.isEmpty {
                    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
                    if assets.count > 0 {
                        do {
                            try await PHPhotoLibrary.shared().performChanges {
                                PHAssetChangeRequest.deleteAssets(assets)
                            }
                            await MainActor.run {
                                self.capturedAssetID = nil
                                self.pendingHostDeleteAssetID = nil
                                self.deletionStatusNotice = "✓ 原截屏已从相册自动删除"
                                self.sourceSubLabel.text = self.deletionStatusNotice
                                self.refreshNoticeBar()
                            }
                        } catch {
                            await MainActor.run {
                                self.pendingHostDeleteAssetID = assetID
                                self.deletionStatusNotice = "点下方「确认删原图」一键清理相册原截屏"
                                self.sourceSubLabel.text = self.deletionStatusNotice
                                self.refreshNoticeBar()
                            }
                        }
                    }
                }
            }

            do {
                for try await event in aiClient.streamVisionEvents(
                    imageData: jpeg,
                    mimeType: "image/jpeg",
                    prompt: presetSnap.promptText,
                    systemInstruction: presetSnap.systemInstruction,
                    config: cfg,
                    featureTag: "in_keyboard_screenshot_vision"
                ) {
                    if Task.isCancelled { break }
                    if case .answer(let delta) = event {
                        acc += delta
                        let now = CACurrentMediaTime()
                        if now - lastFlush >= 0.045 {
                            lastFlush = now
                            let clean = AITextSanitizer.clean(acc, streaming: true)
                            await MainActor.run {
                                self.generatedText = clean
                                self.outputTextView.text = clean
                                let end = NSRange(location: max(0, clean.utf16.count - 1), length: 0)
                                self.outputTextView.scrollRangeToVisible(end)
                            }
                        }
                    }
                }
                if !Task.isCancelled {
                    await cleanupOriginalScreenshotIfNeeded()
                }
                let finalClean = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    self.generatedText = finalClean
                    if finalClean.isEmpty {
                        self.outputTextView.text = "⚠️ 模型未返回识别文本，请确认当前模型支持图片识别（如 Gemini / GPT-4o / Qwen-VL）。"
                    } else {
                        let tail = self.deletionStatusNotice.map { "\n\n\($0)" } ?? ""
                        self.outputTextView.text = finalClean + tail
                        AIRecentHistoryStore.record(title: "📷 \(presetSnap.title)", output: finalClean, prompt: self.sourceDescription)
                    }
                    self.retryButton.setTitle("重识", for: .normal)
                    self.updateButtonsEnabled()
                }
            } catch {
                await MainActor.run {
                    self.outputTextView.text = "⚠️ 截屏识图失败：\(error.localizedDescription)"
                    self.retryButton.setTitle("重试", for: .normal)
                    self.updateButtonsEnabled()
                }
            }
        }
    }

    // MARK: - 辅助方法

    private func updateThumbnailUI() {
        if let img = capturedImage {
            thumbImageView.image = img
            thumbImageView.contentMode = .scaleAspectFill
            sourceTitleLabel.text = sourceDescription
            sourceSubLabel.text = deletionStatusNotice ?? (settings.autoDeleteUploadedScreenshot ? "识别上传后将自动清理原截屏" : "当前设置为保留原截屏")
        } else {
            let icon = UIImage(systemName: "camera.viewfinder", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
            thumbImageView.image = icon
            thumbImageView.tintColor = theme?.candidateHighlight ?? .systemBlue
            thumbImageView.contentMode = .center
            sourceTitleLabel.text = sourceDescription
            sourceSubLabel.text = "截屏后自动识别 · 支持快捷指令一键截屏"
        }
    }

    private func refreshNoticeBar() {
        let photoAuth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if !hasFullAccess {
            actionNoticeBar.isHidden = false
            noticePrimaryButton.setTitle("🔓 一键前往开启完全访问权限", for: .normal)
            noticeSecondaryButton.isHidden = true
        } else if let delID = pendingHostDeleteAssetID, !delID.isEmpty {
            actionNoticeBar.isHidden = false
            noticePrimaryButton.setTitle("🗑️ 一键确认删除刚上传的原截屏", for: .normal)
            noticeSecondaryButton.isHidden = false
            noticeSecondaryButton.setTitle("暂不删", for: .normal)
        } else if photoAuth != .authorized && photoAuth != .limited {
            actionNoticeBar.isHidden = false
            noticePrimaryButton.setTitle("🖼️ 一键开启相册权限（自动抓图与删图）", for: .normal)
            noticeSecondaryButton.isHidden = true
        } else {
            actionNoticeBar.isHidden = true
            noticeSecondaryButton.isHidden = true
        }
        setNeedsLayout()
    }

    private func handleTriggerAutoScreenshot() {
        onTriggerAutoScreenshotShortcut?()
    }

    private func handleNoticePrimaryTap() {
        if !hasFullAccess {
            onOpenPermissions?()
        } else if let delID = pendingHostDeleteAssetID, !delID.isEmpty {
            pendingHostDeleteAssetID = nil
            refreshNoticeBar()
            onOpenHostDeleteAsset?(delID)
        } else {
            onOpenPermissions?()
        }
    }

    private func handleNoticeSecondaryTap() {
        pendingHostDeleteAssetID = nil
        refreshNoticeBar()
    }

    private func handleRetryOrStop() {
        if let task = streamTask, !task.isCancelled, retryButton.title(for: .normal) == "停止" {
            task.cancel()
            retryButton.setTitle("重识", for: .normal)
        } else if capturedJPEGData != nil {
            startVisionRecognition()
        } else {
            scanLatestScreenshot(autoAnalyze: true)
        }
    }

    private func handleCopy() {
        let out = AITextSanitizer.clean(generatedText, streaming: false)
        guard !out.isEmpty else { return }
        UIPasteboard.general.string = out
        _ = ClipboardStore.record(out)
        copyButton.setTitle("✓已复", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.setTitle("复制", for: .normal)
        }
    }

    private func handleInsert() {
        let out = AITextSanitizer.clean(generatedText, streaming: false)
        guard !out.isEmpty else { return }
        setExpandedReadingHeight(false)
        onInsertText?(out)
    }

    private func updateButtonsEnabled() {
        let ready = !AITextSanitizer.clean(generatedText, streaming: false).isEmpty
        copyButton.isEnabled = ready
        copyButton.alpha = ready ? 1.0 : 0.45
        insertButton.isEnabled = ready
        insertButton.alpha = ready ? 1.0 : 0.45
        setNeedsLayout()
    }
}
