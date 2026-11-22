import PhotosUI
import SwiftUI
import UIKit

extension Color {
    init(hexColor: HexColor, opacityScale: Double = 1.0) {
        let c = hexColor.rgba
        self.init(
            .sRGB,
            red: c.r,
            green: c.g,
            blue: c.b,
            opacity: c.a * opacityScale
        )
    }
}

struct ThemeStudioView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewBarState: Int = 0 // 0=常规双簇态, 1=打字候选态, 2=验证码全栏接管态
    @State private var themeShareStatus: String?

    private var activePreset: KeyboardThemePreset {
        appState.theme.activePreset(isSystemDark: colorScheme == .dark)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    appearanceModeCard
                    previewStateSelector
                    previewCard
                    presetGrid
                    customBackgroundSection
                    keyAppearanceSection
                    communityThemeShareSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("键盘外观")
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            appState.saveCustomBackgroundImage(uiImage)
                        }
                    }
                }
            }
        }
    }

    private var appearanceModeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("外观模式（纯白为主 · 可跟随系统）", systemImage: "circle.lefthalf.filled")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Text(appState.theme.appearanceMode.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("键盘外观模式", selection: $appState.theme.appearanceMode) {
                ForEach(KeyboardAppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appState.theme.appearanceMode) { newMode in
                appState.theme.adaptiveDarkMode = (newMode == .followSystem)
                if newMode == .alwaysLight {
                    appState.theme.selectedThemeID = "lingxi_pure"
                }
            }
            Text("「跟随系统」在浅色模式下展示苹果质感纯白圆角键帽，夜间自动切换为暗夜石墨；也可手动锁定「始终纯白」或「始终深色」。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var previewStateSelector: some View {
        Picker("顶栏预览状态", selection: $previewBarState) {
            Text("常规双簇态").tag(0)
            Text("打字候选态").tag(1)
            Text("验证码全栏接管").tag(2)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 实时拟真预览（完整联动顶栏 v3 三态）

    private var previewCard: some View {
        let preset = activePreset
        let hasBg = appState.customBgPreview != nil
        let keyAlpha = hasBg ? appState.theme.keyOpacity : 1.0
        let radius = appState.theme.keyCornerRadius

        return VStack(spacing: 0) {
            // 顶部栏 v3 三态联动预览
            HStack(spacing: 8) {
                if previewBarState == 0 {
                    // 常规双簇态：左 [✨ 灵犀 AI] [💬 译] · 右 [剪贴板] [设置]
                    Text("✨ 灵犀 AI")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color(hexColor: preset.accentFill).opacity(0.16))
                        .foregroundStyle(Color(hexColor: preset.candidateHighlight))
                        .clipShape(Capsule())

                    Text("💬 译")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(Color(hexColor: preset.keyFill, opacityScale: keyAlpha))
                        .foregroundStyle(Color(hexColor: preset.keyText))
                        .clipShape(Capsule())

                    Spacer()

                    ForEach(["doc.on.clipboard", "slider.horizontal.3"], id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hexColor: preset.keyText))
                            .frame(width: 28, height: 28)
                            .background(Color(hexColor: preset.keyFill, opacityScale: keyAlpha))
                            .clipShape(Capsule())
                    }
                } else if previewBarState == 1 {
                    // 打字候选态
                    Text("灵犀输入法")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(hexColor: preset.candidateHighlight))
                    Text("极简白")
                        .font(.subheadline)
                        .foregroundStyle(Color(hexColor: preset.candidateText))
                    Text("墨玉黑")
                        .font(.subheadline)
                        .foregroundStyle(Color(hexColor: preset.candidateText))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(Color(hexColor: preset.candidateText))
                } else {
                    // 验证码/新复制内容全栏独占接管态（隐藏 AI/译）
                    Text("💬 验证码")
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hexColor: preset.accentFill).opacity(0.16))
                        .foregroundStyle(Color(hexColor: preset.candidateHighlight))
                        .clipShape(Capsule())

                    Text("849201 · 【灵犀】5分钟有效")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hexColor: preset.candidateHighlight))
                        .lineLimit(1)

                    Spacer()

                    Text("填入 849201")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(Color(hexColor: preset.accentFill))
                        .foregroundStyle(Color(hexColor: preset.accentText))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(Color(hexColor: preset.toolbarBackground).opacity(hasBg ? 0.85 : 1.0))

            // 模拟按键区
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    ForEach(["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"], id: \.self) { ch in
                        mockKey(ch, fill: Color(hexColor: preset.keyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyText), radius: radius)
                    }
                }
                HStack(spacing: 5) {
                    ForEach(["A", "S", "D", "F", "G", "H", "J", "K", "L"], id: \.self) { ch in
                        mockKey(ch, fill: Color(hexColor: preset.keyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyText), radius: radius)
                    }
                }
                .padding(.horizontal, 12)
                HStack(spacing: 5) {
                    mockKey("123", fill: Color(hexColor: preset.specialKeyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyText), radius: radius, widthWeight: 1.4)
                    mockKey("中/英", fill: Color(hexColor: preset.specialKeyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyText), radius: radius, widthWeight: 1.4)
                    mockKey("灵犀 · \(appState.settings.inputScheme.shortBadge)", fill: Color(hexColor: preset.keyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyHintText), radius: radius, widthWeight: 3.4)
                    mockKey("，", fill: Color(hexColor: preset.keyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyText), radius: radius, widthWeight: 1.2)
                    mockKey("发送", fill: Color(hexColor: preset.accentFill), text: Color(hexColor: preset.accentText), radius: radius, widthWeight: 1.7)
                }
            }
            .padding(8)
        }
        .background {
            ZStack {
                LinearGradient(
                    colors: [Color(hexColor: preset.canvasTop), Color(hexColor: preset.canvasBottom)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if let bg = appState.customBgPreview {
                    Image(uiImage: bg)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: appState.theme.backgroundBlurRadius * 0.6)
                    (preset.isDark ? Color.black : Color.white)
                        .opacity(appState.theme.backgroundDimOpacity)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(Design.Palette.stone).opacity(0.12), radius: 8, y: 4)
    }

    private func mockKey(_ label: String, fill: Color, text: Color, radius: Double, widthWeight: Double = 1.0) -> some View {
        Text(label)
            .font(.system(size: label.count > 2 ? 11 : 14, weight: appState.theme.boldKeyLabel ? .semibold : .regular))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.black.opacity(activePreset.isDark ? 0.25 : 0.12), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(activePreset.isDark ? 0.35 : 0.16), radius: 0.6, x: 0, y: 1)
            .layoutPriority(widthWeight)
    }

    // MARK: - 预设主题

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("精选预设主题")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(KeyboardThemePreset.presets) { preset in
                    let isSelected = (appState.theme.selectedThemeID == preset.id)
                    Button {
                        appState.theme.selectedThemeID = preset.id
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hexColor: preset.canvasTop), Color(hexColor: preset.canvasBottom)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                Circle()
                                    .fill(Color(hexColor: preset.accentFill))
                                    .frame(width: 14, height: 14)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text(preset.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(Design.Palette.ink))
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? Color(Design.Palette.ink) : .clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 相册自定义背景

    private var customBackgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("自定义相册壁纸", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                Spacer()
                if appState.customBgPreview != nil {
                    Button("移除壁纸", role: .destructive) {
                        appState.removeCustomBackgroundImage()
                    }
                    .font(.caption.bold())
                }
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text(appState.customBgPreview == nil ? "从相册挑选一张照片作为键盘背景" : "更换背景图片（已自动压缩适配扩展内存）")
                        .font(.subheadline.bold())
                    Spacer()
                }
                .padding(12)
                .background(Color(Design.Palette.ink).opacity(0.12))
                .foregroundStyle(Color(Design.Palette.ink))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if appState.customBgPreview != nil {
                sliderRow(title: "背景模糊度", value: $appState.theme.backgroundBlurRadius, range: 0...24, format: "%.0f")
                sliderRow(title: "暗化/柔光遮罩", value: $appState.theme.backgroundDimOpacity, range: 0...0.75, format: "%.2f")
                sliderRow(title: "按键不透明度", value: $appState.theme.keyOpacity, range: 0.4...1.0, format: "%.2f")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 按键几何与深色模式联动

    private var keyAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("细节精调")
                .font(.headline)
            sliderRow(title: "按键圆角", value: $appState.theme.keyCornerRadius, range: 2...14, format: "%.0f pt")

            Toggle("键帽加粗字体", isOn: $appState.theme.boldKeyLabel)
            Toggle("跟随系统深色模式自动切换暗色主题", isOn: $appState.theme.adaptiveDarkMode)

            if appState.theme.adaptiveDarkMode {
                Picker("深色模式配对主题", selection: $appState.theme.darkThemeID) {
                    ForEach(KeyboardThemePreset.presets.filter(\.isDark)) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 开源社区皮肤 JSON 导出分享与导入

    private var communityThemeShareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("开源社区皮肤 JSON 分享与导入", systemImage: "square.and.arrow.up.on.square")
                .font(.headline)
            Text("可将当前调好的圆角、透明度与深浅配对配置一键复制为 JSON 分享给社区，或从剪贴板导入他人分享的皮肤配置。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    let enc = JSONEncoder()
                    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    if let data = try? enc.encode(appState.theme),
                       let json = String(data: data, encoding: .utf8) {
                        UIPasteboard.general.string = json
                        themeShareStatus = "✓ 已复制当前皮肤配置 JSON 到剪贴板"
                    }
                } label: {
                    Label("复制皮肤 JSON", systemImage: "doc.on.doc")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color(Design.Palette.surface))
                        .foregroundStyle(Color(Design.Palette.ink))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    guard let raw = UIPasteboard.general.string,
                          let data = raw.data(using: .utf8),
                          let imported = try? JSONDecoder().decode(ThemeCustomization.self, from: data) else {
                        themeShareStatus = "剪贴板中未检测到有效的皮肤 JSON 配置"
                        return
                    }
                    appState.theme = imported
                    themeShareStatus = "✓ 已成功从剪贴板导入并应用社区皮肤配置"
                } label: {
                    Label("从剪贴板导入", systemImage: "arrow.down.doc.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color(Design.Palette.ink))
                        .foregroundStyle(Color(Design.Palette.canvas))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let msg = themeShareStatus {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.ink))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
