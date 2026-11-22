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

    func toHexRGBString() -> String {
        let ui = UIColor(self)
        if let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let converted = ui.cgColor.converted(to: srgbSpace, intent: .defaultIntent, options: nil),
           let comps = converted.components,
           comps.count >= 3 {
            let r = Int((max(0, min(1, comps[0])) * 255).rounded())
            let g = Int((max(0, min(1, comps[1])) * 255).rounded())
            let b = Int((max(0, min(1, comps[2])) * 255).rounded())
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return String(
                format: "#%02X%02X%02X",
                Int((max(0, min(1, r)) * 255).rounded()),
                Int((max(0, min(1, g)) * 255).rounded()),
                Int((max(0, min(1, b)) * 255).rounded())
            )
        }
        var white: CGFloat = 0
        if ui.getWhite(&white, alpha: &a) {
            let v = Int((max(0, min(1, white)) * 255).rounded())
            return String(format: "#%02X%02X%02X", v, v, v)
        }
        return "#FFFFFF"
    }
}

struct ThemeStudioView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewBarState: Int = 0 // 0=常规双簇态, 1=打字候选态, 2=验证码全栏接管态
    @State private var pressedPreviewKey: String?
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
                    customColorPaletteSection
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
        let isPureWhiteActive = (activePreset.id == "lingxi_pure" && !appState.theme.hasCustomColorOverrides)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("外观模式（纯白为主 · 可跟随系统）", systemImage: "circle.lefthalf.filled")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                if !isPureWhiteActive {
                    Button("一键纯白") {
                        appState.theme.applyPresetSelection(
                            KeyboardThemePreset.find(id: "lingxi_pure"),
                            isSystemDark: colorScheme == .dark
                        )
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(Design.Palette.ink))
                    .foregroundStyle(Color(Design.Palette.canvas))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                } else {
                    Text("纯白已启用")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            Picker("键盘外观模式", selection: Binding(
                get: { appState.theme.appearanceMode },
                set: { newMode in
                    appState.theme.applyAppearanceMode(newMode)
                }
            )) {
                ForEach(KeyboardAppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text("「跟随系统」白天自动展示纯白圆角键帽、夜间切换深色石墨；选择「浅色主题」可全天候固定纯白，也可在下方选「雪域全白」或自由调色。")
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

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text("849201 · 【灵犀】您的登录验证码是 849201，5分钟内有效（可左右滑动查看全文）")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hexColor: preset.candidateHighlight))
                            .fixedSize(horizontal: true, vertical: false)
                    }

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
        let isPressed = (pressedPreviewKey == label)
        let activeFill = isPressed ? Color(hexColor: activePreset.keyPressedFill) : fill
        return Button {
            pressedPreviewKey = label
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                if pressedPreviewKey == label {
                    pressedPreviewKey = nil
                }
            }
        } label: {
            Text(label)
                .font(.system(size: label.count > 2 ? 11 : 14, weight: appState.theme.boldKeyLabel ? .semibold : .regular))
                .foregroundStyle(text)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(activeFill)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.black.opacity(activePreset.isDark ? 0.25 : 0.14), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(isPressed ? 0 : (activePreset.isDark ? 0.35 : 0.18)), radius: 0.6, x: 0, y: 1)
                .offset(y: isPressed ? 1 : 0)
        }
        .buttonStyle(.plain)
        .layoutPriority(widthWeight)
    }

    // MARK: - 预设主题

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("精选预设主题")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(KeyboardThemePreset.presets) { preset in
                    let isSelected = (activePreset.id == preset.id && !appState.theme.hasCustomColorOverrides)
                    Button {
                        appState.theme.applyPresetSelection(preset, isSystemDark: colorScheme == .dark)
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

    // MARK: - 自由调色板（实时联动上方预览与真机键盘）

    private var customColorPaletteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("自由调色板", systemImage: "eyedropper.halffull")
                    .font(.headline)
                Spacer()
                if appState.theme.hasCustomColorOverrides {
                    Button("恢复预设原色") {
                        appState.theme.clearCustomColors()
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.ink))
                }
            }

            ColorPicker("键盘底板颜色", selection: hexColorBinding(\.customCanvasHex, fallback: activePreset.canvasTop), supportsOpacity: false)
            ColorPicker("字母键帽颜色", selection: hexColorBinding(\.customKeyFillHex, fallback: activePreset.keyFill), supportsOpacity: false)
            ColorPicker("按键文字颜色", selection: hexColorBinding(\.customKeyTextHex, fallback: activePreset.keyText), supportsOpacity: false)
            ColorPicker("发送键与强调色", selection: hexColorBinding(\.customAccentHex, fallback: activePreset.accentFill), supportsOpacity: false)

            let ratio = activePreset.keyFill.contrastRatio(with: activePreset.keyText)
            if ratio < 3.5 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("按键文字与键帽对比度偏低 (\(String(format: "%.1f", ratio)):1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("自动优化") {
                        appState.theme.customKeyTextHex = activePreset.keyFill.isDarkColor ? "#F3F4F6" : "#0A0A0A"
                    }
                    .font(.caption.bold())
                }
                .padding(8)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickColorSwatch("苹果纯白", canvas: "#E8EAEF", key: "#FFFFFF", text: "#0A0A0A", accent: "#0A0A0A")
                    quickColorSwatch("晴空蓝", canvas: "#E5EEF8", key: "#FFFFFF", text: "#111827", accent: "#007AFF")
                    quickColorSwatch("樱花粉", canvas: "#F9E6EE", key: "#FFFFFF", text: "#432333", accent: "#E85D93")
                    quickColorSwatch("松烟绿", canvas: "#E3ECE6", key: "#FAFDFB", text: "#1E3129", accent: "#2F7D5A")
                    quickColorSwatch("深邃墨玉", canvas: "#181A20", key: "#2C313D", text: "#F3F4F6", accent: "#4F8BFF")
                }
                .padding(.top, 2)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func hexColorBinding(_ keyPath: WritableKeyPath<ThemeCustomization, String?>, fallback: HexColor) -> Binding<Color> {
        Binding<Color>(
            get: {
                if let hex = appState.theme[keyPath: keyPath] {
                    return Color(hexColor: HexColor(hex))
                }
                return Color(hexColor: fallback)
            },
            set: { newColor in
                appState.theme[keyPath: keyPath] = newColor.toHexRGBString()
            }
        )
    }

    private func quickColorSwatch(_ title: String, canvas: String, key: String, text: String, accent: String) -> some View {
        Button {
            appState.theme.customCanvasHex = canvas
            appState.theme.customKeyFillHex = key
            appState.theme.customKeyTextHex = text
            appState.theme.customAccentHex = accent
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hexColor: HexColor(accent)))
                    .frame(width: 12, height: 12)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.ink))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(Design.Palette.surface))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
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

    // MARK: - 按键几何与深浅色配对

    private var keyAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("键帽圆角与跟随系统配对")
                .font(.headline)
            sliderRow(title: "按键圆角", value: $appState.theme.keyCornerRadius, range: 2...14, format: "%.0f pt")

            Toggle("键帽加粗字体", isOn: $appState.theme.boldKeyLabel)

            if appState.theme.appearanceMode == .followSystem {
                Picker("浅色模式配对主题", selection: $appState.theme.lightThemeID) {
                    ForEach(KeyboardThemePreset.presets.filter { !$0.isDark }) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
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
