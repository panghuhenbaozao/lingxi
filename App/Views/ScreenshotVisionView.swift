import Photos
import PhotosUI
import SwiftUI
import UIKit

/// 旗舰「📷 截屏 AI 识图 & 上传后自动删图」工作台：
/// - 打开即自动抓取剪贴板截屏或相册最新系统截屏（也支持手动选图）；
/// - 调用多模态 AI 流式识别（高情商看图回复 / 提取文字 / 截屏译中 / 总结重点 / 解答分析 / 自定义提问）；
/// - 开启「上传后自动删除原截屏」后，发送给 AI 即自动触发系统清理原截屏，结果同步复制回剪贴板，切回聊天顶栏一键上屏！
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

    @State private var resultText: String = ""
    @State private var isAnalyzing: Bool = false
    @State private var statusBanner: String?
    @State private var statusIsError: Bool = false
    @State private var deletedOriginalNotice: String?
    @State private var photoAuthStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var streamTask: Task<Void, Never>?

    private let aiClient = AIClient(timeout: 45)

    private var hasPhotoReadWrite: Bool {
        photoAuthStatus == .authorized || photoAuthStatus == .limited
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    autoDeleteToggleCard
                    screenshotPreviewCard
                    presetActionCard
                    resultCard
                    quickTipCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("截屏 AI 识图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        streamTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("权限") {
                        appState.showPermissionsCenter = true
                    }
                    .font(.subheadline)
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
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            self.previewImage = img
                            self.currentAssetID = newItem.itemIdentifier
                            self.imageFromPasteboard = false
                            self.sourceBadge = "已选相册图片"
                            self.deletedOriginalNotice = nil
                            self.statusBanner = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - 1. 自动删图开关卡

    private var autoDeleteToggleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $appState.settings.autoDeleteUploadedScreenshot) {
                HStack(spacing: 10) {
                    Image(systemName: "trash.slash.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(Design.Palette.accent))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("上传 AI 后自动删除原截屏")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("发给 AI 识别完成后自动清理原截屏，相册零垃圾残留")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(Color(Design.Palette.accent))

            if !hasPhotoReadWrite {
                Button {
                    Task { await requestPhotoPermissionAndLoad() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.checkmark")
                        Text("一键开启相册读写权限（自动抓取并删除最新截屏）")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(Design.Palette.accent))
            }

            if let deletedOriginalNotice {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(Design.Palette.success))
                    Text(deletedOriginalNotice)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(Design.Palette.success))
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 2. 截屏预览与来源抓取卡

    private var screenshotPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(sourceBadge, systemImage: "camera.viewfinder")
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.accent))
                Spacer()
                Button {
                    Task { await loadLatestScreenshot(autoRun: false) }
                } label: {
                    Label("刷新最新截屏", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(Design.Palette.accent))
            }

            if let img = previewImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
                    )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("尚未检测到最新截屏")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("在微信/抖音截一张屏再回来，或点下方粘贴/选图")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 8) {
                PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                    Label("相册选图", systemImage: "photo.stack")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Button {
                    loadFromPasteboard()
                } label: {
                    Label("粘贴截屏", systemImage: "doc.on.clipboard")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                if currentAssetID != nil {
                    Button(role: .destructive) {
                        Task { await deleteCurrentScreenshotNow() }
                    } label: {
                        Label("删原图", systemImage: "trash")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 3. 识图指令与自定义提问卡

    private var presetActionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ScreenshotVisionPreset.allCases) { preset in
                        let active = selectedPreset == preset && customQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Button(preset.title) {
                            selectedPreset = preset
                            customQuestion = ""
                            if previewImage != nil {
                                startVisionAnalysis()
                            }
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(active ? Color(Design.Palette.accent) : Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("也可以直接输入想问图片的问题…", text: $customQuestion)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .submitLabel(.send)
                    .onSubmit { startVisionAnalysis() }

                Button {
                    if isAnalyzing {
                        streamTask?.cancel()
                        isAnalyzing = false
                    } else {
                        startVisionAnalysis()
                    }
                } label: {
                    Text(isAnalyzing ? "停止" : "识图")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .tint(isAnalyzing ? .orange : Color(Design.Palette.accent))
                .disabled(previewImage == nil && !isAnalyzing)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 4. 纯净无 `*` AI 识别结果卡

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI 识图结果（纯净纯文本）", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.accent))
                Spacer()
                if isAnalyzing {
                    ProgressView().scaleEffect(0.75)
                }
            }

            if let statusBanner {
                Text(statusBanner)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Color.orange : Color(Design.Palette.success))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if resultText.isEmpty {
                Text("选择上方「看图回复 / 提取文字 / 截屏译中 / 总结重点」或直接点「识图」，结果将自动净化掉 * 等符号并同步复制到剪贴板。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                Text(resultText)
                    .font(.body)
                    .foregroundStyle(Color(Design.Palette.ink))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = resultText
                        _ = ClipboardStore.record(resultText)
                        statusIsError = false
                        statusBanner = "✓ 已复制纯净正文！切回聊天 App 点键盘顶栏即可一键发送"
                    } label: {
                        Label("复制结果回键盘", systemImage: "doc.on.doc.fill")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(Design.Palette.accent))

                    Button {
                        startVisionAnalysis()
                    } label: {
                        Label("重新识别", systemImage: "arrow.clockwise")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 5. 一键截屏快捷技巧提示卡

    private var quickTipCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("⚡ 键盘内真·一键自动截屏识图（零相册残留）", systemImage: "bolt.fill")
                .font(.caption.bold())
                .foregroundStyle(Color(Design.Palette.accent))
            Text("方案 1（系统监听 · 零配置）：授予相册读写权限后，在微信/抖音按「电源+音量上」或「轻点背面两下」截屏，键盘 1 秒内自动弹起识图面板并上传分析；\n方案 2（键盘内点「⚡截屏」零相册残留）：打开苹果「快捷指令」新建名为「灵犀截屏识图」的 2 步指令（① 截屏 ② 拷贝至剪贴板），以后在键盘内点「⚡截屏」即自动截屏识图并在传完后秒清剪贴板！")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 逻辑实现

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
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.photoAuthStatus = status
        }
        if status == .authorized || status == .limited {
            await loadLatestScreenshot(autoRun: false)
        } else {
            await MainActor.run {
                self.statusIsError = true
                self.statusBanner = "请在「系统设置 → 灵犀输入法 → 照片」中允许访问照片，以支持自动抓取与上传后删除截屏。"
            }
        }
    }

    private func loadFromPasteboard() {
        if UIPasteboard.general.hasImages, let img = UIPasteboard.general.image {
            previewImage = img
            currentAssetID = nil
            imageFromPasteboard = true
            sourceBadge = "剪贴板截屏"
            deletedOriginalNotice = nil
            statusBanner = nil
        } else {
            statusIsError = true
            statusBanner = "剪贴板里当前没有图片，请先截屏或复制一张图片。"
        }
    }

    private func loadLatestScreenshot(autoRun: Bool) async {
        // 1. 优先检查剪贴板最新图片
        if UIPasteboard.general.hasImages, let img = UIPasteboard.general.image {
            await MainActor.run {
                self.previewImage = img
                self.currentAssetID = nil
                self.imageFromPasteboard = true
                self.sourceBadge = "剪贴板最新截屏"
                self.deletedOriginalNotice = nil
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
                self.sourceBadge = "相册暂无截屏"
            }
            return
        }

        let loadedImage: UIImage? = await withCheckedContinuation { cont in
            let req = PHImageRequestOptions()
            req.deliveryMode = .highQualityFormat
            req.isNetworkAccessAllowed = true
            req.isSynchronous = false
            PHImageManager.default().requestImage(
                for: latest,
                targetSize: CGSize(width: 1440, height: 1440),
                contentMode: .aspectFit,
                options: req
            ) { img, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    cont.resume(returning: img)
                }
            }
        }

        if let loadedImage {
            let ageSec = Int(max(0, Date().timeIntervalSince(latest.creationDate ?? Date())))
            let ageDesc = ageSec < 60 ? "\(ageSec)秒前" : (ageSec < 3600 ? "\(ageSec / 60)分钟前" : "最近")
            await MainActor.run {
                self.previewImage = loadedImage
                self.currentAssetID = latest.localIdentifier
                self.imageFromPasteboard = false
                self.sourceBadge = "相册最新截屏 · \(ageDesc)"
                self.deletedOriginalNotice = nil
            }
            if autoRun {
                await MainActor.run { self.startVisionAnalysis() }
            }
        }
    }

    private func startVisionAnalysis() {
        guard let img = previewImage,
              let jpeg = ScreenshotImageHelper.prepareJPEGData(from: img) else {
            statusIsError = true
            statusBanner = "请先截取或选择一张图片。"
            return
        }
        let cfg = appState.aiConfig
        guard cfg.isConfigured else {
            statusIsError = true
            statusBanner = "尚未配置 AI API Key，请先在「AI」页填写 Key（推荐 Gemini / GPT-4o / Qwen-VL 等视觉模型）。"
            return
        }

        streamTask?.cancel()
        isAnalyzing = true
        resultText = ""
        statusIsError = false
        let kb = max(1, jpeg.count / 1024)
        statusBanner = "正在上传截屏（\(kb) KB）并调用 \(cfg.activeModelName) 识图…"

        let custom = customQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = custom.isEmpty ? selectedPreset.promptText : custom
        let sys = custom.isEmpty ? selectedPreset.systemInstruction : "你是视觉 AI 助手，请结合截屏内容直接给出清晰实用的纯文本回答。"
        let autoDelete = appState.settings.autoDeleteUploadedScreenshot
        let assetIDToDelete = currentAssetID
        let clearPasteboard = imageFromPasteboard

        streamTask = Task {
            var acc = ""
            var lastFlush = CACurrentMediaTime()
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
                if Task.isCancelled { return }
                let finalClean = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    self.resultText = finalClean
                    self.isAnalyzing = false
                    if finalClean.isEmpty {
                        self.statusIsError = true
                        self.statusBanner = "模型未返回有效文本，请确认当前模型支持图片识别。"
                    } else {
                        UIPasteboard.general.string = finalClean
                        _ = ClipboardStore.record(finalClean)
                        AIRecentHistoryStore.record(title: "📷 截屏识图", output: finalClean, prompt: prompt)
                        self.statusIsError = false
                        self.statusBanner = "✓ 识别完成并已自动复制纯净结果！切回聊天 App 点键盘顶栏即可发送"
                    }
                }

                // 上传识别完成后自动清理原截屏
                if autoDelete {
                    if clearPasteboard {
                        await MainActor.run {
                            self.deletedOriginalNotice = "✓ 剪贴板中的原截屏已替换清理，零残留"
                        }
                    }
                    if let assetID = assetIDToDelete, !assetID.isEmpty {
                        await deleteAssetByID(assetID)
                    }
                }
            } catch is CancellationError {
                await MainActor.run { self.isAnalyzing = false }
            } catch {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.statusIsError = true
                    self.statusBanner = "识图失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteCurrentScreenshotNow() async {
        guard let assetID = currentAssetID, !assetID.isEmpty else { return }
        await deleteAssetByID(assetID)
    }

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
                self.deletedOriginalNotice = "✓ 上传的原截屏已从相册彻底删除，不占空间"
            }
        } catch {
            await MainActor.run {
                self.deletedOriginalNotice = "⚠️ 未删除原截屏（已取消确认或缺少相册权限）"
            }
        }
    }
}
