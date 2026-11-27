import Photos
import PhotosUI
import SwiftUI
import UIKit

/// 线程安全的「只执行一次」标记，用于保护 continuation 不被重复恢复
private final class ResumeOnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    /// 第一次调用返回 true，之后都返回 false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// App 内显示用：去掉键盘共用标题里的 emoji，配 SF Symbols 图标（键盘侧仍用原标题）
private extension ScreenshotVisionPreset {
    var appPlainTitle: String {
        switch self {
        case .smartReply: return "看图回复"
        case .extractText: return "提取文字"
        case .translateZh: return "翻译成中文"
        case .summarize: return "总结重点"
        case .explainSolve: return "解答分析"
        }
    }

    var appSymbol: String {
        switch self {
        case .smartReply: return "bubble.left.and.bubble.right"
        case .extractText: return "text.viewfinder"
        case .translateZh: return "globe"
        case .summarize: return "list.bullet.rectangle"
        case .explainSolve: return "lightbulb"
        }
    }

    var appHint: String {
        switch self {
        case .smartReply: return "根据聊天截图写一句回复"
        case .extractText: return "本机识别，无需联网"
        case .translateZh: return "外文截图翻译成中文"
        case .summarize: return "提炼要点和待办"
        case .explainSolve: return "看懂报错、题目或界面"
        }
    }
}

/// 截屏识图工作台（v6）：截屏预览 → 选择识别方式 → 结果（自动复制）→ 原图清理设置。
/// - 打开时自动读取剪贴板截屏或相册最新截屏，也可手动选图；
/// - 「提取文字」优先用本机 Vision OCR，其余调用多模态 AI，不支持看图的模型自动回退为「OCR 文字 → 文本模型」；
/// - 开启「识别后清理原截屏」时：剪贴板截屏直接替换，相册截屏由系统弹窗确认后删除。
struct ScreenshotVisionView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: ScreenshotVisionPreset = .smartReply
    @State private var customQuestion: String = ""
    @State private var previewImage: UIImage?
    @State private var currentAssetID: String?
    @State private var imageFromPasteboard: Bool = false
    @State private var sourceBadge: String = "等待截屏"
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isLoadingImage = false

    @State private var resultText: String = ""
    @State private var isAnalyzing: Bool = false
    @State private var statusBanner: String?
    @State private var statusIsError: Bool = false
    @State private var photoAuthStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var streamTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var showTips = false
    @FocusState private var questionFocused: Bool

    private let aiClient = AIClient(timeout: 45)

    private var hasPhotoReadWrite: Bool {
        photoAuthStatus == .authorized || photoAuthStatus == .limited
    }

    private var trimmedQuestion: String {
        customQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.md) {
                    previewCard
                    presetCard
                    resultCard
                    cleanupCard
                    tipsCard
                }
                .lxReadableWidth()
                .padding(.horizontal, Design.Spacing.md)
                .padding(.top, Design.Spacing.xs)
                .padding(.bottom, Design.Spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("截屏识图")
            .navigationBarTitleDisplayMode(.inline)
            .lxToast($toast)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        streamTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.showPermissionsCenter = true
                    } label: {
                        Image(systemName: hasPhotoReadWrite ? "checkmark.shield" : "exclamationmark.shield")
                    }
                    .accessibilityLabel("权限中心")
                }
            }
            .onAppear {
                handleOnAppear()
            }
            .onDisappear {
                streamTask?.cancel()
            }
            .onChange(of: photoPickerItem) { newItem in
                guard let newItem else { return }
                isLoadingImage = true
                Task {
                    let data = try? await newItem.loadTransferable(type: Data.self)
                    let img = data.flatMap { UIImage(data: $0) }
                    await MainActor.run {
                        self.isLoadingImage = false
                        self.photoPickerItem = nil
                        guard let img else {
                            self.toast = "无法读取这张图片，换一张试试"
                            return
                        }
                        self.setPreview(img, assetID: newItem.itemIdentifier, fromPasteboard: false, badge: "相册图片")
                    }
                }
            }
        }
    }

    // MARK: - 1. 截屏预览

    private var previewCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    LXTag(
                        text: sourceBadge,
                        icon: previewImage == nil ? "photo" : "checkmark",
                        tint: previewImage == nil ? Color(Design.Palette.slate) : Color(Design.Palette.accent),
                        filled: previewImage != nil
                    )
                    if appState.aiConfig.isConfigured {
                        LXTag(
                            text: appState.aiConfig.resolvedVisionModel(),
                            icon: ScreenshotOCRService.modelLikelySupportsVision(
                                modelID: appState.aiConfig.resolvedVisionModel(),
                                provider: appState.aiConfig.provider
                            ) ? "eye" : "text.viewfinder",
                            tint: Color(Design.Palette.stone)
                        )
                    }
                    Spacer()
                    Button {
                        Task { await loadLatestScreenshot(autoRun: false) }
                    } label: {
                        Label("最新截屏", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                    .disabled(isLoadingImage || isAnalyzing)
                }

                Group {
                    if let img = previewImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                                    .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
                            )
                            .accessibilityLabel("截屏预览")
                    } else {
                        VStack(spacing: 8) {
                            if isLoadingImage {
                                ProgressView()
                            } else {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 30))
                                    .foregroundStyle(Color(Design.Palette.muted))
                            }
                            Text(isLoadingImage ? "正在读取图片…" : "还没有截屏")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text(hasPhotoReadWrite
                                 ? "截一张屏再回来点「最新截屏」，或从相册选、从剪贴板粘贴。"
                                 : "允许访问照片后可以自动读取最新截屏；也可以从剪贴板粘贴。")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 12)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
                    }
                }

                HStack(spacing: 8) {
                    PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("相册选图", systemImage: "photo.stack")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                    .disabled(isAnalyzing)

                    Button {
                        loadFromPasteboard()
                    } label: {
                        Label("粘贴截屏", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                    .disabled(isAnalyzing)
                }

                if !hasPhotoReadWrite {
                    Button {
                        Task { await requestPhotoPermissionAndLoad() }
                    } label: {
                        Label(photoAuthStatus == .denied || photoAuthStatus == .restricted ? "去设置允许访问照片" : "允许访问照片，自动读取截屏", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                }
            }
        }
    }

    // MARK: - 2. 识别方式

    private var presetCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("想让 AI 做什么")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(ScreenshotVisionPreset.allCases) { preset in
                        presetTile(preset)
                    }
                }

                HStack(spacing: 8) {
                    TextField("或者直接问：这张图里的快递几点到？", text: $customQuestion)
                        .font(.subheadline)
                        .focused($questionFocused)
                        .submitLabel(.send)
                        .onSubmit { startVisionAnalysis() }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous))

                    if isAnalyzing {
                        Button("停止") {
                            streamTask?.cancel()
                            isAnalyzing = false
                            statusIsError = false
                            statusBanner = "已停止"
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false, tint: Color(Design.Palette.error)))
                    } else {
                        Button("识别") {
                            questionFocused = false
                            startVisionAnalysis()
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                        .disabled(previewImage == nil)
                    }
                }
            }
        }
    }

    private func presetTile(_ preset: ScreenshotVisionPreset) -> some View {
        let active = selectedPreset == preset && trimmedQuestion.isEmpty
        return Button {
            selectedPreset = preset
            customQuestion = ""
            questionFocused = false
            if previewImage != nil && !isAnalyzing {
                startVisionAnalysis()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: preset.appSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active ? Color.white : Color(Design.Palette.accent))
                    .frame(width: 30, height: 30)
                    .background(
                        active ? Color.white.opacity(0.2) : Color(Design.Palette.accentSoft),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.appPlainTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                        .lineLimit(1)
                    Text(preset.appHint)
                        .font(.caption2)
                        .foregroundStyle(active ? Color.white.opacity(0.85) : Color(Design.Palette.stone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                active ? Color(Design.Palette.accent) : Color(Design.Palette.canvas),
                in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                    .stroke(active ? Color.clear : Color(Design.Palette.hairline), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isAnalyzing)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - 3. 结果

    private var resultCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("识别结果")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    if isAnalyzing {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer()
                }

                if let statusBanner {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : (isAnalyzing ? "hourglass" : "checkmark.circle.fill"))
                            .font(.caption)
                            .foregroundStyle(statusIsError ? Color(Design.Palette.warning) : (isAnalyzing ? Color(Design.Palette.stone) : Color(Design.Palette.success)))
                            .padding(.top, 1)
                        Text(LXToastText.clean(statusBanner))
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if resultText.isEmpty {
                    Text(previewImage == nil
                         ? "先在上面准备一张截屏。"
                         : "选一种识别方式，结果会显示在这里并自动复制。")
                        .font(.subheadline)
                        .foregroundStyle(Color(Design.Palette.muted))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } else {
                    Text(resultText)
                        .font(.body)
                        .foregroundStyle(Color(Design.Palette.ink))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))

                    if !isAnalyzing {
                        HStack(spacing: 8) {
                            Button {
                                UIPasteboard.general.string = resultText
                                _ = ClipboardStore.record(resultText)
                                toast = "已复制，切回聊天 App 点键盘顶栏即可发送"
                            } label: {
                                Label("复制结果", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))

                            Button {
                                startVisionAnalysis()
                            } label: {
                                Label("重新识别", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                        }
                    }
                }
            }
        }
    }

    // MARK: - 4. 原截屏清理

    private var cleanupCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 10) {
                LXToggleRow(
                    "识别后清理原截屏",
                    subtitle: "剪贴板里的截屏直接替换；相册里的截屏会由系统弹窗确认后删除",
                    isOn: $appState.settings.autoDeleteUploadedScreenshot
                )

                if currentAssetID != nil && !imageFromPasteboard {
                    Divider()
                    HStack {
                        Text("这张图来自相册")
                            .font(.footnote)
                            .foregroundStyle(Color(Design.Palette.stone))
                        Spacer()
                        Button(role: .destructive) {
                            Task { await deleteCurrentScreenshotNow() }
                        } label: {
                            Label("现在删除", systemImage: "trash")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false, tint: Color(Design.Palette.error)))
                    }
                }
            }
        }
    }

    // MARK: - 5. 键盘内快速识图技巧（默认折叠）

    private var tipsCard: some View {
        LXCard {
            DisclosureGroup(isExpanded: $showTips) {
                VStack(alignment: .leading, spacing: 12) {
                    tipRow(
                        number: 1,
                        title: "轻点背面截屏（推荐）",
                        detail: "系统设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下 → 截屏。之后在聊天里轻拍手机背面截屏，键盘顶栏会出现识图入口。"
                    )
                    tipRow(
                        number: 2,
                        title: "截屏后不留在相册",
                        detail: "截屏后点左下角预览 → 右上角「完成」→「拷贝并删除」，再到键盘里识图，相册里不会留下截屏。"
                    )
                }
                .padding(.top, 10)
            } label: {
                Label("在键盘里更快地识图", systemImage: "keyboard")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
            }
            .tint(Color(Design.Palette.stone))
        }
    }

    private func tipRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Color(Design.Palette.accent))
                .frame(width: 22, height: 22)
                .background(Color(Design.Palette.accentSoft), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 逻辑实现

    private func setPreview(_ img: UIImage, assetID: String?, fromPasteboard: Bool, badge: String) {
        previewImage = img
        currentAssetID = assetID
        imageFromPasteboard = fromPasteboard
        sourceBadge = badge
        statusBanner = nil
        resultText = ""
    }

    private func handleOnAppear() {
        photoAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        // 若从键盘携带待删除的已上传截屏 ID 跳回，立即触发系统删除确认
        if let pendingID = appState.pendingDeleteScreenshotAssetID, !pendingID.isEmpty {
            appState.pendingDeleteScreenshotAssetID = nil
            currentAssetID = pendingID
            Task {
                await deleteAssetByID(pendingID)
            }
            return
        }

        let autoAnalyze = appState.screenshotAutoAnalyze
        appState.screenshotAutoAnalyze = false
        Task {
            await loadLatestScreenshot(autoRun: autoAnalyze)
        }
    }

    private func requestPhotoPermissionAndLoad() async {
        if photoAuthStatus == .denied || photoAuthStatus == .restricted {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await MainActor.run { UIApplication.shared.open(url) }
            }
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.photoAuthStatus = status
        }
        if status == .authorized || status == .limited {
            await loadLatestScreenshot(autoRun: false)
        } else {
            await MainActor.run {
                self.toast = "没有照片权限，可以在系统设置里打开，或改用「粘贴截屏」"
            }
        }
    }

    private func loadFromPasteboard() {
        // hasImages 只读类型信息，不会触发「允许粘贴」提示；确认有图片后再读取
        if UIPasteboard.general.hasImages, let img = UIPasteboard.general.image {
            setPreview(img, assetID: nil, fromPasteboard: true, badge: "剪贴板截屏")
        } else {
            toast = "剪贴板里没有图片，先截屏或复制一张图片"
        }
    }

    private func loadLatestScreenshot(autoRun: Bool) async {
        await MainActor.run { self.isLoadingImage = true }
        defer { Task { @MainActor in self.isLoadingImage = false } }

        // 1. 优先检查剪贴板最新图片
        if UIPasteboard.general.hasImages, let img = UIPasteboard.general.image {
            await MainActor.run {
                self.setPreview(img, assetID: nil, fromPasteboard: true, badge: "剪贴板截屏")
            }
            if autoRun {
                await MainActor.run { self.startVisionAnalysis() }
            }
            return
        }

        // 2. 自动请求相册读写权限并抓取最新一张系统截屏
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        await MainActor.run { self.photoAuthStatus = status }
        guard status == .authorized || status == .limited else { return }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 3
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        let fetched = PHAsset.fetchAssets(with: .image, options: options)
        guard let latest = fetched.firstObject else {
            await MainActor.run {
                self.sourceBadge = status == .limited ? "只能访问部分照片，未找到截屏" : "相册里没有截屏"
            }
            return
        }

        let loadedImage: UIImage? = await withCheckedContinuation { cont in
            let req = PHImageRequestOptions()
            req.deliveryMode = .highQualityFormat
            req.isNetworkAccessAllowed = true
            req.isSynchronous = false
            // 防止回调被系统多次调用导致 continuation 重复恢复而崩溃
            let once = ResumeOnceFlag()
            PHImageManager.default().requestImage(
                for: latest,
                targetSize: CGSize(width: 1440, height: 1440),
                contentMode: .aspectFit,
                options: req
            ) { img, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded, once.claim() else { return }
                cont.resume(returning: img)
            }
        }

        if let loadedImage {
            let ageSec = Int(max(0, Date().timeIntervalSince(latest.creationDate ?? Date())))
            let ageDesc = ageSec < 60 ? "\(ageSec) 秒前" : (ageSec < 3600 ? "\(ageSec / 60) 分钟前" : "较早")
            await MainActor.run {
                self.setPreview(loadedImage, assetID: latest.localIdentifier, fromPasteboard: false, badge: "最新截屏 · \(ageDesc)")
            }
            if autoRun {
                await MainActor.run { self.startVisionAnalysis() }
            }
        } else {
            await MainActor.run {
                self.toast = "读取截屏失败，可能还在从 iCloud 下载，稍后再试"
            }
        }
    }

    private func startVisionAnalysis() {
        guard let img = previewImage,
              let jpeg = ScreenshotImageHelper.prepareJPEGData(from: img) else {
            toast = "先截屏或选择一张图片"
            return
        }
        let cfg = appState.aiConfig
        let custom = trimmedQuestion
        let isPureExtractText = custom.isEmpty && selectedPreset == .extractText

        streamTask?.cancel()
        isAnalyzing = true
        resultText = ""
        statusIsError = false
        let kb = max(1, jpeg.count / 1024)
        statusBanner = isPureExtractText
            ? "正在本机识别文字…"
            : "正在识别（\(kb) KB · \(cfg.resolvedVisionModel())）…"

        let prompt = custom.isEmpty ? selectedPreset.promptText : custom
        let sys = custom.isEmpty ? selectedPreset.systemInstruction : "你是视觉 AI 助手，请结合截屏内容直接给出清晰实用的纯文本回答。"
        let historyTitle = custom.isEmpty ? "截屏 · \(selectedPreset.appPlainTitle)" : "截屏 · 提问"
        let autoDelete = appState.settings.autoDeleteUploadedScreenshot
        let assetIDToDelete = currentAssetID
        let clearPasteboard = imageFromPasteboard

        streamTask = Task {
            let ocrText = await ScreenshotOCRService.recognizeText(from: img)
            if Task.isCancelled { return }

            // 1. 「提取文字」优先走本机 Apple Vision OCR（无需联网 / 视觉模型）
            if isPureExtractText && !ocrText.isEmpty {
                let finalClean = AITextSanitizer.clean(ocrText, streaming: false)
                await MainActor.run {
                    self.resultText = finalClean
                    self.isAnalyzing = false
                    UIPasteboard.general.string = finalClean
                    _ = ClipboardStore.record(finalClean)
                    AIRecentHistoryStore.record(title: historyTitle, output: finalClean, prompt: prompt)
                    self.statusIsError = false
                    self.statusBanner = autoDelete && clearPasteboard
                        ? "本机识别完成，已复制结果（剪贴板里的原截屏已被替换）"
                        : "本机识别完成，已复制结果"
                }
                return
            }

            guard cfg.isConfigured else {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.statusIsError = true
                    if !ocrText.isEmpty {
                        self.resultText = ocrText
                        self.statusBanner = "已先在本机提取出文字；填写 AI 密钥后可以回复、翻译和总结"
                    } else {
                        self.statusBanner = "还没有填写 AI 密钥，请先到「AI」页填写"
                    }
                }
                return
            }

            var acc = ""
            var lastFlush = CACurrentMediaTime()
            let supportsNativeVision = ScreenshotOCRService.modelLikelySupportsVision(modelID: cfg.resolvedVisionModel(), provider: cfg.provider)
            var needsOCRFallback = !supportsNativeVision

            if supportsNativeVision {
                do {
                    for try await event in aiClient.streamVisionEvents(
                        imageData: jpeg,
                        mimeType: "image/jpeg",
                        prompt: prompt,
                        systemInstruction: sys,
                        config: cfg,
                        featureTag: "screenshot_vision"
                    ) {
                        if Task.isCancelled { return }
                        if case .answer(let delta) = event {
                            acc += delta
                            let now = CACurrentMediaTime()
                            if now - lastFlush >= 0.045 {
                                lastFlush = now
                                let clean = AITextSanitizer.clean(acc, streaming: true)
                                await MainActor.run { self.resultText = clean }
                            }
                        }
                    }
                } catch is CancellationError {
                    await MainActor.run { self.isAnalyzing = false }
                    return
                } catch {
                    if ocrText.isEmpty {
                        await MainActor.run {
                            self.isAnalyzing = false
                            self.statusIsError = true
                            self.statusBanner = "识别失败：\(error.localizedDescription)"
                        }
                        return
                    }
                    acc = ""
                    needsOCRFallback = true
                }
            }

            // 2. 纯文本模型（如 DeepSeek）或视觉接口异常时，自动回退「本机 OCR 文字 → 文本模型」
            if acc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && needsOCRFallback {
                if ocrText.isEmpty {
                    await MainActor.run {
                        self.isAnalyzing = false
                        self.statusIsError = true
                        self.statusBanner = "图里没有识别到文字，而当前模型（\(cfg.activeModelName)）不能直接看图；可以换成 Gemini、GPT-4o 或 Qwen-VL"
                    }
                    return
                }
                await MainActor.run {
                    self.statusBanner = "已在本机提取文字，正在用 \(cfg.activeModelName) 生成回答…"
                }
                let ocrPrompt = "【截屏文字内容（本机 OCR 识别）】\n\(ocrText)\n\n请根据以上内容完成：\(prompt)"
                do {
                    for try await event in aiClient.streamEvents(
                        prompt: ocrPrompt,
                        systemInstruction: sys,
                        config: cfg,
                        featureTag: "screenshot_vision_ocr_fallback",
                        preferFast: true
                    ) {
                        if Task.isCancelled { return }
                        if case .answer(let delta) = event {
                            acc += delta
                            let now = CACurrentMediaTime()
                            if now - lastFlush >= 0.045 {
                                lastFlush = now
                                let clean = AITextSanitizer.clean(acc, streaming: true)
                                await MainActor.run { self.resultText = clean }
                            }
                        }
                    }
                } catch is CancellationError {
                    await MainActor.run { self.isAnalyzing = false }
                    return
                } catch {
                    await MainActor.run {
                        self.isAnalyzing = false
                        self.statusIsError = true
                        self.resultText = ocrText
                        self.statusBanner = "AI 请求失败（\(error.localizedDescription)），先显示本机提取的原文"
                    }
                    return
                }
            }

            if Task.isCancelled { return }
            let finalClean = AITextSanitizer.clean(acc, streaming: false)
            await MainActor.run {
                self.resultText = finalClean
                self.isAnalyzing = false
                if finalClean.isEmpty {
                    self.statusIsError = true
                    self.statusBanner = "模型没有返回内容，请重试，或改用「提取文字」"
                } else {
                    UIPasteboard.general.string = finalClean
                    _ = ClipboardStore.record(finalClean)
                    AIRecentHistoryStore.record(title: historyTitle, output: finalClean, prompt: prompt)
                    self.statusIsError = false
                    self.statusBanner = autoDelete && clearPasteboard
                        ? "识别完成，已复制结果（剪贴板里的原截屏已被替换）"
                        : "识别完成，已复制结果"
                }
            }

            // 仅在真正产出结果且用户开启开关时清理相册原图（系统会弹窗确认）
            if autoDelete && !finalClean.isEmpty && !clearPasteboard,
               let assetID = assetIDToDelete, !assetID.isEmpty {
                await deleteAssetByID(assetID)
            }
        }
    }

    private func deleteCurrentScreenshotNow() async {
        guard let assetID = currentAssetID, !assetID.isEmpty else { return }
        await deleteAssetByID(assetID)
    }

    /// 删除相册图片：iOS 会弹出系统确认框，用户取消时不会删除
    private func deleteAssetByID(_ assetID: String) async {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard assets.count > 0 else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            await MainActor.run {
                if self.currentAssetID == assetID {
                    self.currentAssetID = nil
                }
                self.toast = "原截屏已从相册删除"
            }
        } catch {
            await MainActor.run {
                self.toast = "没有删除原截屏（已取消，或缺少照片权限）"
            }
        }
    }
}
