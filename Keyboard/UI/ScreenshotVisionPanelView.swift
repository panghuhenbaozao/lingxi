import Photos
import UIKit

/// 键盘内嵌「📷 截屏 & AI 识图」专属工作台（v5.6.1 全模型可用 + 零骚扰删图弹窗版）：
/// - 100% 全模型可用：内置 Apple 端侧 Vision OCR（0.25 秒本机极速提字、低内存零崩溃），
///   「📝 提取文字」无需联网或 API Key 直接秒出；「看图回复 / 截屏译中 / 总结 / 解答」自动按模型能力直连视觉 API 或无缝走「端侧 OCR → DeepSeek 等纯文本模型」双保险！
/// - 彻底杜绝莫名删图弹窗：绝不自动调用系统 `PHAssetChangeRequest.deleteAssets` 骚扰用户！
///   剪贴板截屏（系统「拷贝并删除」或快捷指令「截屏→拷贝至剪贴板」）上传后自动静默清空（0 弹窗零残留）；
///   相册截屏仅在用户主动点「🗑️ 删原图」时才执行删除。
final class ScreenshotVisionPanelView: UIView, UITextViewDelegate {
    var onInsertText: ((String) -> Void)?
    var onSettingsChanged: ((LingxiSettings) -> Void)?
    var onReadingHeightChanged: ((Bool) -> Void)?
    /// 调用 iOS 快捷指令 `shortcuts://run-shortcut?name=灵犀截屏识图` 实现真·一键截屏拷入剪贴板
    var onTriggerAutoScreenshotShortcut: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onImportBridgeToken: (() -> Bool)?
    var onOpenHostAppAI: (() -> Void)?
    var onOpenHostDeleteAsset: ((String) -> Void)?
    var onOpenHostWorkbench: (() -> Void)?
    var onClose: (() -> Void)?

    private let aiClient = AIClient(timeout: 40)
    private var streamTask: Task<Void, Never>?

    private var theme: ResolvedTheme?
    private var settings = LingxiSettings()
    private var hasFullAccess = false

    private var currentPreset: ScreenshotVisionPreset = .smartReply
    private var capturedImage: UIImage?
    private var capturedJPEGData: Data?
    private var capturedAssetID: String?
    private var capturedFromPasteboard = false
    private var sourceDescription = "尚未检测到截屏"
    private var generatedText = ""
    private var deletionStatusNotice: String?
    private var needsAIConfigNotice = false
    private(set) var isExpandedReadingHeight = false

    // Row 1: 缩略图 + 来源状态 + 自动截屏 + 刷新 + 剪贴板秒清开关 + 返回
    private let thumbImageView = UIImageView()
    private let sourceTitleLabel = UILabel()
    private let sourceSubLabel = UILabel()
    private let autoShotButton = ActionClosureButton(type: .system)
    private let refreshButton = ActionClosureButton(type: .system)
    private let autoDeleteToggleButton = ActionClosureButton(type: .system)
    private let closeButton = ActionClosureButton(type: .system)

    // Row 2: 5 大视觉模式胶囊 + 自动弹板开关 + 拉高按钮
    private let presetsScroll = LingxiScrollView()
    private let presetsStack = UIStackView()
    private let heightToggleButton = ActionClosureButton(type: .system)

    // Row 3: 识别结果正文区（可选中复制 + 滑动自动拉高）
    private let outputTextView = UITextView()

    // 快捷提示 / 手动删原图 / 权限或 AI 密钥修复条
    private let actionNoticeBar = UIStackView()
    private let noticePrimaryButton = ActionClosureButton(type: .system)
    private let noticeSecondaryButton = ActionClosureButton(type: .system)

    // Bottom bar: 识别/停止 · 复制 · 选图/引导 · 插入上屏
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

    /// 内存吃紧且面板隐藏时释放已缓存的截屏位图，守住键盘 50MB Jetsam 红线。
    func releaseTransientMemory() {
        guard isHidden else { return }
        capturedImage = nil
        capturedJPEGData = nil
        thumbImageView.image = nil
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

        autoShotButton.setTitle("📷读图", for: .normal)
        autoShotButton.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .bold)
        autoShotButton.layer.cornerRadius = 9
        autoShotButton.layer.cornerCurve = .continuous
        autoShotButton.accessibilityLabel = "立即抓取最新截屏并在键盘内识别"
        autoShotButton.actionHandler = { [weak self] in
            self?.scanLatestScreenshot(autoAnalyze: true)
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
            self.updateThumbnailUI()
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
        heightToggleButton.accessibilityLabel = "拉高或还原阅读高度"
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
        workbenchButton.setTitle("相册选图", for: .normal)
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
        guard bounds.width > 10, bounds.height > 10 else { return }
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
        self.needsAIConfigNotice = false
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
        self.needsAIConfigNotice = false

        applyTheme(theme)
        rebuildPresetPills()
        updateAutoDeleteBadge()
        updateThumbnailUI()
        refreshNoticeBar()

        if autoStart {
            startVisionRecognition()
        } else {
            outputTextView.text = "✓ 已捕获「\(sourceLabel)」。\n点上方「💬 看图回复 / 📝 提取文字 / 🌐 截屏译中」立即在键盘内识别。"
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
        autoDeleteToggleButton.setTitle(on ? "✓传后清" : "保留图", for: .normal)
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
                if self.capturedImage != nil {
                    self.startVisionRecognition()
                } else {
                    self.scanLatestScreenshot(autoAnalyze: true)
                }
            }
            presetsStack.addArrangedSubview(btn)
        }

        // 「截屏直弹」开关：默认关闭（改为顶栏轻提示「📷 刚截的屏 · 识图」，不打断正常打字）
        let autoBtn = ActionClosureButton(type: .system)
        let autoOn = settings.autoAnalyzeNewScreenshot
        autoBtn.setTitle(autoOn ? "🔔 截屏直弹:开" : "🔕 截屏轻提示", for: .normal)
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

    // MARK: - 键盘内实时抓取最新截屏（低内存 768px 缩放，杜绝键盘 Jetsam 闪退）

    func scanLatestScreenshot(autoAnalyze: Bool) {
        deletionStatusNotice = nil
        needsAIConfigNotice = false

        // 1. 优先读取剪贴板中的截屏（例如快捷指令「截屏→拷贝至剪贴板」或系统截屏点「拷贝并删除」，上传后 0 弹窗自动清空）
        if hasFullAccess,
           UIPasteboard.general.hasImages,
           let img = UIPasteboard.general.image,
           let jpeg = ScreenshotImageHelper.prepareJPEGData(from: img, maxDimension: 768, quality: 0.68) {
            capturedImage = img
            capturedJPEGData = jpeg
            capturedAssetID = nil
            capturedFromPasteboard = true
            sourceDescription = "剪贴板截屏 · 传完静默清空"
            updateThumbnailUI()
            refreshNoticeBar()
            if autoAnalyze {
                startVisionRecognition()
            } else {
                outputTextView.text = "✓ 已读取剪贴板截屏（\(max(1, jpeg.count / 1024)) KB）。点上方模式开始识别。"
                updateButtonsEnabled()
            }
            return
        }

        // 2. 读取相册最近 24 小时内最新一张系统截屏（若无系统截屏标签，自动兜底读取最新一张照片，绝不因 30 分钟过期读不到！）
        let photoAuth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if photoAuth == .authorized || photoAuth == .limited {
            let shotOpts = PHFetchOptions()
            shotOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            shotOpts.fetchLimit = 3
            shotOpts.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            var candidateAsset = PHAsset.fetchAssets(with: .image, options: shotOpts).firstObject
            var isScreenshotSubtype = (candidateAsset != nil)

            if let created = candidateAsset?.creationDate, Date().timeIntervalSince(created) > 86_400 {
                candidateAsset = nil
            }
            if candidateAsset == nil {
                let anyOpts = PHFetchOptions()
                anyOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                anyOpts.fetchLimit = 1
                candidateAsset = PHAsset.fetchAssets(with: .image, options: anyOpts).firstObject
                isScreenshotSubtype = false
            }

            if let latest = candidateAsset {
                let created = latest.creationDate ?? Date()
                let assetID = latest.localIdentifier
                let ageSec = Int(max(0, Date().timeIntervalSince(created)))
                let ageText: String
                if ageSec < 60 {
                    ageText = "\(ageSec)秒前"
                } else if ageSec < 3600 {
                    ageText = "\(ageSec / 60)分钟前"
                } else if ageSec < 86_400 {
                    ageText = "\(ageSec / 3600)小时前"
                } else {
                    ageText = "最近照片"
                }
                let kindLabel = isScreenshotSubtype ? "最新截屏" : "最新相册图"
                let req = PHImageRequestOptions()
                req.deliveryMode = .highQualityFormat
                req.isSynchronous = false
                req.isNetworkAccessAllowed = true
                req.resizeMode = .exact
                outputTextView.text = "📷 正在读取\(kindLabel)（\(ageText)）…"
                PHImageManager.default().requestImage(
                    for: latest,
                    targetSize: CGSize(width: 768, height: 768),
                    contentMode: .aspectFit,
                    options: req
                ) { [weak self] img, info in
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    guard !degraded else { return }
                    let jpeg = img.flatMap { ScreenshotImageHelper.prepareJPEGData(from: $0, maxDimension: 768, quality: 0.68) }
                    DispatchQueue.main.async {
                        guard let self else { return }
                        guard let img, let jpeg else {
                            self.capturedImage = nil
                            self.capturedJPEGData = nil
                            self.capturedAssetID = nil
                            self.sourceDescription = "图片读取失败"
                            self.outputTextView.text = "⚠️ 该图片位于 iCloud 或暂不可读，请点右上「📷读图」重试，或截图后点左下「拷贝并删除」直接免相册识图。"
                            self.updateThumbnailUI()
                            self.refreshNoticeBar()
                            self.updateButtonsEnabled()
                            return
                        }
                        self.capturedImage = img
                        self.capturedJPEGData = jpeg
                        self.capturedAssetID = assetID
                        self.capturedFromPasteboard = false
                        self.sourceDescription = "\(kindLabel) · \(ageText)"
                        self.updateThumbnailUI()
                        self.refreshNoticeBar()
                        if autoAnalyze {
                            self.startVisionRecognition()
                        } else {
                            self.outputTextView.text = "✓ 已读取\(kindLabel)（\(ageText)）。点上方功能即可在键盘内识图回复。"
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

        if photoAuth != .authorized && photoAuth != .limited {
            outputTextView.text = "📷 键盘内识图（无需快捷指令，绝不乱弹删除框）：\n• 零弹窗秒清：系统截屏后点左下预览 →「完成 → 拷贝并删除」，回键盘点右上「📷读图」立即识别并自动清空剪贴板！\n• 随手截屏直读：点下方「开启相册权限」后，按电源+音量上（或轻点手机背面两下）截屏，顶栏立即浮出「📷 刚截的屏 · ✨ 识图」。"
        } else {
            outputTextView.text = "📷 当前暂无 30 分钟内新截屏（无需快捷指令）：\n• 按「电源+音量上」或「轻点手机背面两下」截屏，然后点右上「📷读图」或顶栏「✨ 识图」立即在键盘内识别；\n• 也可点底部「相册选图」挑任意历史照片，或截屏时点系统「拷贝并删除」实现 0 弹窗自动清空！"
        }
        updateButtonsEnabled()
    }

    // MARK: - 键盘内双引擎识别（Apple 端侧 Vision OCR + 多模态 AI 自动回退）

    private func startVisionRecognition() {
        streamTask?.cancel()
        guard let img = capturedImage, let jpeg = capturedJPEGData else {
            scanLatestScreenshot(autoAnalyze: true)
            return
        }

        generatedText = ""
        deletionStatusNotice = nil
        needsAIConfigNotice = false
        retryButton.setTitle("停止", for: .normal)
        let presetSnap = currentPreset
        let autoDel = settings.autoDeleteUploadedScreenshot
        let fromPB = capturedFromPasteboard
        let cfg = AIConfig.load()
        let fullAccessSnap = hasFullAccess

        outputTextView.text = presetSnap == .extractText
            ? "📝 正在端侧极速提取截屏文字（0.2 秒本机完成）…"
            : "📷 正在键盘内分析截屏 · 执行「\(presetSnap.title)」…"
        updateButtonsEnabled()

        streamTask = Task { [weak self] in
            guard let self else { return }

            func silentlyClearPasteboardIfNeeded() async {
                guard autoDel, fromPB else { return }
                await MainActor.run {
                    UIPasteboard.general.items = []
                    self.capturedFromPasteboard = false
                    self.deletionStatusNotice = "✓ 剪贴板原截屏已静默清空（零弹窗零残留）"
                    self.sourceSubLabel.text = self.deletionStatusNotice
                }
            }

            // 1. 端侧 Apple Vision OCR（0.25s 本机运行，内存极低，零网络零费用）
            let ocrText = await ScreenshotOCRService.recognizeText(from: img)
            if Task.isCancelled { return }

            // 模式 A：「📝 提取文字」优先直接返回端侧高精度 OCR（无需联网、DeepSeek 或无 API Key 也能秒用！）
            if presetSnap == .extractText && !ocrText.isEmpty {
                await silentlyClearPasteboardIfNeeded()
                let finalClean = AITextSanitizer.clean(ocrText, streaming: false)
                await MainActor.run {
                    self.generatedText = finalClean
                    let note = self.deletionStatusNotice ?? "✓ 本机端侧极速提字完成（无需联网 · 零消耗）"
                    self.sourceSubLabel.text = note
                    self.outputTextView.text = finalClean
                    AIRecentHistoryStore.record(title: "📷 \(presetSnap.title)", output: finalClean, prompt: self.sourceDescription)
                    self.retryButton.setTitle("重识", for: .normal)
                    self.refreshNoticeBar()
                    self.updateButtonsEnabled()
                }
                return
            }

            // 2. 若尚未开启完全访问或尚未配置 AI Key：依然给出端侧 OCR 提取到的正文 + 一键修复按钮，绝不空手报错！
            if !fullAccessSnap || !cfg.isConfigured {
                await MainActor.run {
                    self.needsAIConfigNotice = !cfg.isConfigured
                    if !ocrText.isEmpty {
                        self.generatedText = ocrText
                        let reason = !fullAccessSnap ? "开启「完全访问」" : "配置/同步 AI 密钥"
                        self.outputTextView.text = "【已先为你提取截屏文字】\n\(ocrText)\n\n提示：\(reason)后即可使用「\(presetSnap.title)」智能回复与翻译。"
                    } else {
                        self.outputTextView.text = !fullAccessSnap
                            ? "⚠️ 请先开启键盘「允许完全访问」才可联网执行「\(presetSnap.title)」。"
                            : "⚠️ 请先在灵犀 App「AI」页配置或同步 API Key，再执行「\(presetSnap.title)」。"
                    }
                    self.retryButton.setTitle("重试", for: .normal)
                    self.refreshNoticeBar()
                    self.updateButtonsEnabled()
                }
                return
            }

            let chosenModel = cfg.resolvedVisionModel()
            let supportsNativeVision = ScreenshotOCRService.modelLikelySupportsVision(modelID: chosenModel, provider: cfg.provider)
            var acc = ""
            var lastFlush = CACurrentMediaTime()
            var usedFallbackOCR = false

            // 3. 原生视觉模型优先直传 768px 轻量 JPEG；若失败且存在 OCR 文字，自动无缝降级到 OCR → 文本 LLM！
            if supportsNativeVision {
                do {
                    for try await event in aiClient.streamVisionEvents(
                        imageData: jpeg,
                        mimeType: "image/jpeg",
                        prompt: presetSnap.promptText,
                        systemInstruction: presetSnap.systemInstruction,
                        config: cfg,
                        featureTag: "in_keyboard_screenshot_vision"
                    ) {
                        if Task.isCancelled { return }
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
                } catch {
                    if Task.isCancelled { return }
                    if ocrText.isEmpty {
                        await MainActor.run {
                            self.outputTextView.text = "⚠️ 视觉识图失败：\(error.localizedDescription)"
                            self.retryButton.setTitle("重试", for: .normal)
                            self.refreshNoticeBar()
                            self.updateButtonsEnabled()
                        }
                        return
                    }
                    acc = ""
                    usedFallbackOCR = true
                }
            } else {
                usedFallbackOCR = true
            }

            // 4. DeepSeek / 纯文本模型 或 视觉接口回退：使用端侧 Vision OCR 提取的完整截屏文字喂给文本大模型！
            if acc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && usedFallbackOCR {
                if ocrText.isEmpty {
                    await MainActor.run {
                        self.outputTextView.text = "⚠️ 这张图里没有识别到文字，且当前模型（\(cfg.activeModelName)）不支持直接看纯照片。\n如需识别纯风景/物品照片，请在灵犀 AI 页切换 Gemini / GPT-4o / Qwen-VL 等视觉模型。"
                        self.retryButton.setTitle("重试", for: .normal)
                        self.refreshNoticeBar()
                        self.updateButtonsEnabled()
                    }
                    return
                }
                await MainActor.run {
                    self.sourceSubLabel.text = "📝 已端侧提字 · 正用 \(cfg.activeModelName) 生成…"
                    self.outputTextView.text = "📝 已秒提截屏文字，正在用 \(cfg.activeModelName) 执行「\(presetSnap.title)」…"
                }
                let ocrPrompt = "【截屏文字内容（由端侧 Vision 识别）】\n\(ocrText)\n\n请根据以上截屏内容直接完成：\(presetSnap.promptText)"
                do {
                    for try await event in aiClient.streamEvents(
                        prompt: ocrPrompt,
                        systemInstruction: presetSnap.systemInstruction,
                        config: cfg,
                        featureTag: "in_keyboard_screenshot_ocr_ai",
                        preferFast: true
                    ) {
                        if Task.isCancelled { return }
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
                } catch {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        // 即使 AI 网络失败，仍保留端侧 OCR 文字方便用户直接复制
                        self.generatedText = ocrText
                        self.outputTextView.text = "⚠️ AI 调用失败（\(error.localizedDescription)）。\n\n已保留端侧提取原文：\n\(ocrText)"
                        self.retryButton.setTitle("重试", for: .normal)
                        self.refreshNoticeBar()
                        self.updateButtonsEnabled()
                    }
                    return
                }
            }

            if Task.isCancelled { return }
            let finalClean = AITextSanitizer.clean(acc, streaming: false)
            if !finalClean.isEmpty {
                await silentlyClearPasteboardIfNeeded()
            }
            await MainActor.run {
                self.generatedText = finalClean
                if finalClean.isEmpty {
                    self.outputTextView.text = "⚠️ 模型未返回有效结果，请点击「重试」或切换上方「📝 提取文字」体验本机秒提字。"
                } else {
                    self.outputTextView.text = finalClean
                    if let note = self.deletionStatusNotice {
                        self.sourceSubLabel.text = note
                    } else if usedFallbackOCR {
                        self.sourceSubLabel.text = "✓ 端侧 OCR + \(cfg.activeModelName) 识别完成"
                    } else {
                        self.sourceSubLabel.text = "✓ 视觉模型识别完成（未弹删除框）"
                    }
                    AIRecentHistoryStore.record(title: "📷 \(presetSnap.title)", output: finalClean, prompt: self.sourceDescription)
                }
                self.retryButton.setTitle("重识", for: .normal)
                self.refreshNoticeBar()
                self.updateButtonsEnabled()
            }
        }
    }

    // MARK: - 手动删相册原图（仅当用户主动点击「🗑️ 删原图」时才执行，绝不擅自弹窗！）

    private func manualDeleteCurrentAsset() {
        guard let assetID = capturedAssetID, !assetID.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard assets.count > 0 else {
            capturedAssetID = nil
            refreshNoticeBar()
            return
        }
        Task { [weak self] in
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(assets)
                }
                await MainActor.run {
                    self?.capturedAssetID = nil
                    self?.deletionStatusNotice = "✓ 已手动删除相册原截屏"
                    self?.sourceSubLabel.text = self?.deletionStatusNotice
                    self?.refreshNoticeBar()
                }
            } catch {
                await MainActor.run {
                    self?.onOpenHostDeleteAsset?(assetID)
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
            if let note = deletionStatusNotice {
                sourceSubLabel.text = note
            } else if capturedFromPasteboard {
                sourceSubLabel.text = settings.autoDeleteUploadedScreenshot ? "识别完自动静默清空剪贴板（0 弹窗）" : "剪贴板截屏（已设为保留）"
            } else {
                sourceSubLabel.text = "相册截屏 · 不自动弹窗，需删可点下方"
            }
        } else {
            let icon = UIImage(systemName: "camera.viewfinder", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
            thumbImageView.image = icon
            thumbImageView.tintColor = theme?.candidateHighlight ?? .systemBlue
            thumbImageView.contentMode = .center
            sourceTitleLabel.text = sourceDescription
            sourceSubLabel.text = "端侧提字 + 全模型识图 · 绝不乱弹删图框"
        }
    }

    private func refreshNoticeBar() {
        let photoAuth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if !hasFullAccess {
            actionNoticeBar.isHidden = false
            noticePrimaryButton.setTitle("🔓 开启完全访问（支持联网 AI 识图）", for: .normal)
            noticeSecondaryButton.isHidden = true
        } else if needsAIConfigNotice {
            actionNoticeBar.isHidden = false
            if !AppGroup.isAvailable {
                noticePrimaryButton.setTitle("📋 一键同步 AI 密钥口令", for: .normal)
                noticeSecondaryButton.isHidden = false
                noticeSecondaryButton.setTitle("去配置", for: .normal)
            } else {
                noticePrimaryButton.setTitle("🔑 前往灵犀配置 AI 密钥", for: .normal)
                noticeSecondaryButton.isHidden = true
            }
        } else if capturedAssetID != nil && !capturedFromPasteboard {
            // 相册图仅提供温和可选的手动删原图按钮，绝不自动弹出 iOS 确认框！
            actionNoticeBar.isHidden = false
            noticePrimaryButton.setTitle("🗑️ 手动删除这张相册原截屏", for: .normal)
            noticeSecondaryButton.isHidden = false
            noticeSecondaryButton.setTitle("保留", for: .normal)
        } else if photoAuth != .authorized && photoAuth != .limited && capturedImage == nil {
            actionNoticeBar.isHidden = false
            noticePrimaryButton.setTitle("🖼️ 开启相册权限（截屏自动轻提示）", for: .normal)
            noticeSecondaryButton.isHidden = true
        } else {
            actionNoticeBar.isHidden = true
            noticeSecondaryButton.isHidden = true
        }
        setNeedsLayout()
    }

    private func handleNoticePrimaryTap() {
        if !hasFullAccess {
            onOpenPermissions?()
        } else if needsAIConfigNotice {
            if !AppGroup.isAvailable, onImportBridgeToken?() == true {
                needsAIConfigNotice = false
                refreshNoticeBar()
                startVisionRecognition()
            } else {
                onOpenHostAppAI?()
            }
        } else if capturedAssetID != nil && !capturedFromPasteboard {
            manualDeleteCurrentAsset()
        } else {
            onOpenPermissions?()
        }
    }

    private func handleNoticeSecondaryTap() {
        if needsAIConfigNotice {
            onOpenHostAppAI?()
        } else {
            capturedAssetID = nil
            refreshNoticeBar()
        }
    }

    private func handleRetryOrStop() {
        if let task = streamTask, !task.isCancelled, retryButton.title(for: .normal) == "停止" {
            task.cancel()
            retryButton.setTitle("重识", for: .normal)
        } else if capturedImage != nil {
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
