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
    @State private var previewDarkOverride: Bool? = nil // nil=跟随当前外观，false=强制预览日间，true=强制预览夜间
    @State private var pressedPreviewKey: String?
    @State private var themeShareStatus: String?

    private var previewIsDark: Bool {
        if let forced = previewDarkOverride { return forced }
        switch appState.theme.appearanceMode {
        case .alwaysLight: return false
        case .alwaysDark: return true
        case .followSystem: return colorScheme == .dark
        }
    }

    private var activePreset: KeyboardThemePreset {
        appState.theme.activePreset(isSystemDark: previewIsDark)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    appearanceModeCard
                    previewControlsBar
                    previewCard
                    groupedPresetGrid
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
        let isDefaultComfortable = (
            appState.theme.lightThemeID == "lingxi_pure" &&
            appState.theme.darkThemeID == "midnight_geek" &&
            !appState.theme.hasCustomColorOverrides
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("外观策略（苹果精校护眼 · 日夜双套独立）", systemImage: "circle.lefthalf.filled")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                if !isDefaultComfortable {
                    Button("恢复原生精校") {
                        appState.theme.lightThemeID = "lingxi_pure"
                        appState.theme.darkThemeID = "midnight_geek"
                        appState.theme.selectedThemeID = "lingxi_pure"
                        appState.theme.appearanceMode = .followSystem
                        appState.theme.adaptiveDarkMode = true
                        appState.theme.clearCustomColors()
                        appState.theme.keyShadowScale = 1.0
                        previewDarkOverride = nil
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(Design.Palette.accent))
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                } else {
                    Text("已启用")
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.success))
                }
            }
            Picker("键盘外观模式", selection: Binding(
                get: { appState.theme.appearanceMode },
                set: { newMode in
                    appState.theme.applyAppearanceMode(newMode)
                    previewDarkOverride = nil
                }
            )) {
                ForEach(KeyboardAppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text("「跟随系统」白天自动展示苹果原生白、夜间自动切为通透高对比石墨暗色，日/夜两套调色板完全独立，互不串色。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var previewControlsBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    previewDarkOverride = false
                } label: {
                    Label("☀️ 日间预览", systemImage: previewIsDark ? "sun.max" : "sun.max.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(!previewIsDark ? Color(Design.Palette.accent) : Color(.secondarySystemGroupedBackground))
                        .foregroundStyle(!previewIsDark ? Color.white : Color(Design.Palette.ink))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    previewDarkOverride = true
                } label: {
                    Label("🌙 夜间预览", systemImage: previewIsDark ? "moon.fill" : "moon")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(previewIsDark ? Color(Design.Palette.accent) : Color(.secondarySystemGroupedBackground))
                        .foregroundStyle(previewIsDark ? Color.white : Color(Design.Palette.ink))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Picker("顶栏预览状态", selection: $previewBarState) {
                Text("常规双簇态").tag(0)
                Text("打字候选态").tag(1)
                Text("验证码全栏接管").tag(2)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - 实时拟真预览（日夜自由切换 + 完整联动顶栏三态）

    private var previewCard: some View {
        let preset = activePreset
        let hasBg = appState.customBgPreview != nil
        let keyAlpha = hasBg ? appState.theme.keyOpacity : 1.0
        let radius = appState.theme.keyCornerRadius

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                if previewBarState == 0 {
                    Text("✨ 灵犀 AI")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color(hexColor: preset.accentFill).opacity(0.18))
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
                    Text("灵犀输入法")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(hexColor: preset.candidateHighlight))
                    Text("苹果精校")
                        .font(.subheadline)
                        .foregroundStyle(Color(hexColor: preset.candidateText))
                    Text("护眼高对比")
                        .font(.subheadline)
                        .foregroundStyle(Color(hexColor: preset.candidateText))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(Color(hexColor: preset.candidateText))
                } else {
                    Text("💬 验证码")
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hexColor: preset.accentFill).opacity(0.18))
                        .foregroundStyle(Color(hexColor: preset.candidateHighlight))
                        .clipShape(Capsule())

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text("849201 · 【灵犀】您的登录验证码是 849201，5分钟内有效")
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
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(preset.isDark ? 0.25 : 0.08), radius: 8, y: 4)
    }

    private func mockKey(_ label: String, fill: Color, text: Color, radius: Double, widthWeight: Double = 1.0) -> some View {
        let isPressed = (pressedPreviewKey == label)
        let activeFill = isPressed ? Color(hexColor: activePreset.keyPressedFill) : fill
        let shadowAlpha = activePreset.keyShadowOpacity * appState.theme.keyShadowScale
        return Button {
            pressedPreviewKey = label
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                if pressedPreviewKey == label { pressedPreviewKey = nil }
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
                        .stroke(Color.black.opacity(activePreset.isDark ? 0.22 : 0.10), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(isPressed ? 0 : shadowAlpha), radius: 0.6, x: 0, y: 1)
                .offset(y: isPressed ? 1 : 0)
        }
        .buttonStyle(.plain)
        .layoutPriority(widthWeight)
    }

    // MARK: - 12 套精校预设主题（浅色护眼 6 套 + 深色舒适 6 套分组呈现）

    private var groupedPresetGrid: some View {
        let lightPresets = KeyboardThemePreset.presets.filter { !$0.isDark }
        let darkPresets = KeyboardThemePreset.presets.filter(\.isDark)
        return VStack(alignment: .leading, spacing: 14) {
            presetSection(title: "☀️ 浅色护眼精选 (\(lightPresets.count))", presets: lightPresets)
            presetSection(title: "🌙 深色舒适精校 (\(darkPresets.count))", presets: darkPresets)
        }
    }

    private func presetSection(title: String, presets: [KeyboardThemePreset]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(presets) { preset in
                    let isSelected: Bool = {
                        if appState.theme.appearanceMode == .followSystem {
                            return preset.isDark
                                ? (appState.theme.darkThemeID == preset.id && !appState.theme.hasDarkCustomOverrides)
                                : (appState.theme.lightThemeID == preset.id && !appState.theme.hasLightCustomOverrides)
                        }
                        return activePreset.id == preset.id && !(preset.isDark ? appState.theme.hasDarkCustomOverrides : appState.theme.hasLightCustomOverrides)
                    }()
                    Button {
                        if appState.theme.appearanceMode == .followSystem {
                            if preset.isDark {
                                appState.theme.darkThemeID = preset.id
                                appState.theme.clearCustomColors(forDark: true)
                                previewDarkOverride = true
                            } else {
                                appState.theme.lightThemeID = preset.id
                                appState.theme.clearCustomColors(forDark: false)
                                previewDarkOverride = false
                            }
                        } else {
                            appState.theme.applyPresetSelection(preset, isSystemDark: colorScheme == .dark)
                            previewDarkOverride = preset.isDark
                        }
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
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color(hexColor: preset.keyFill))
                                            .frame(width: 24, height: 14)
                                            .offset(y: -4)
                                    )
                                Circle()
                                    .fill(Color(hexColor: preset.accentFill))
                                    .frame(width: 10, height: 10)
                                    .offset(x: 8, y: 9)
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
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(Design.Palette.accent))
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? Color(Design.Palette.accent) : Color(Design.Palette.hairline).opacity(0.6), lineWidth: isSelected ? 2 : 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 日夜双套独立自由调色板

    private var customColorPaletteSection: some View {
        let editingDark = previewIsDark
        let hasOverrides = editingDark ? appState.theme.hasDarkCustomOverrides : appState.theme.hasLightCustomOverrides
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(editingDark ? "🌙 夜间独立自由调色板" : "☀️ 日间独立自由调色板", systemImage: "eyedropper.halffull")
                    .font(.headline)
                Spacer()
                if hasOverrides {
                    Button("恢复\(editingDark ? "夜间" : "日间")原色") {
                        appState.theme.clearCustomColors(forDark: editingDark)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.accent))
                }
            }

            ColorPicker(
                "键盘底板颜色",
                selection: hexColorBinding(editingDark ? \.customDarkCanvasHex : \.customCanvasHex, fallback: activePreset.canvasTop),
                supportsOpacity: false
            )
            ColorPicker(
                "字母键帽颜色",
                selection: hexColorBinding(editingDark ? \.customDarkKeyFillHex : \.customKeyFillHex, fallback: activePreset.keyFill),
                supportsOpacity: false
            )
            ColorPicker(
                "按键文字颜色",
                selection: hexColorBinding(editingDark ? \.customDarkKeyTextHex : \.customKeyTextHex, fallback: activePreset.keyText),
                supportsOpacity: false
            )
            ColorPicker(
                "发送键与强调色",
                selection: hexColorBinding(editingDark ? \.customDarkAccentHex : \.customAccentHex, fallback: activePreset.accentFill),
                supportsOpacity: false
            )

            let ratio = activePreset.keyFill.contrastRatio(with: activePreset.keyText)
            HStack(spacing: 8) {
                Image(systemName: ratio >= 4.5 ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ratio >= 4.5 ? Color(Design.Palette.success) : .orange)
                Text(ratio >= 4.5
                     ? "WCAG AA 对比度达标 (\(String(format: "%.1f", ratio)):1 · 舒适清晰)"
                     : "文字与键帽对比度偏低 (\(String(format: "%.1f", ratio)):1)，建议自动优化")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if ratio < 4.5 {
                    Button("自动优化") {
                        let autoText = activePreset.keyFill.isDarkColor ? "#FFFFFF" : "#111113"
                        if editingDark {
                            appState.theme.customDarkKeyTextHex = autoText
                        } else {
                            appState.theme.customKeyTextHex = autoText
                        }
                    }
                    .font(.caption.bold())
                }
            }
            .padding(8)
            .background((ratio >= 4.5 ? Color(Design.Palette.success) : Color.orange).opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .background(Color(Design.Palette.accentSoft))
                .foregroundStyle(Color(Design.Palette.accent))
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

    // MARK: - 按键几何、立体阴影与系统配对

    private var keyAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("键帽圆角、浮雕阴影与深浅配对")
                .font(.headline)
            sliderRow(title: "按键圆角", value: $appState.theme.keyCornerRadius, range: 2...14, format: "%.0f pt")
            sliderRow(title: "按键立体阴影强度", value: $appState.theme.keyShadowScale, range: 0.0...1.6, format: "%.1fx")

            Toggle("键帽加粗字体", isOn: $appState.theme.boldKeyLabel)

            if appState.theme.appearanceMode == .followSystem {
                Picker("日间浅色配对主题", selection: $appState.theme.lightThemeID) {
                    ForEach(KeyboardThemePreset.presets.filter { !$0.isDark }) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                Picker("夜间深色配对主题", selection: $appState.theme.darkThemeID) {
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
            Label("社区皮肤 JSON 分享与导入", systemImage: "square.and.arrow.up.on.square")
                .font(.headline)
            Text("可将当前调好的日夜双套色彩、圆角与阴影配置一键复制为 JSON 分享，或从剪贴板导入。")
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
                        .background(Color(Design.Palette.accent))
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let msg = themeShareStatus {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.accent))
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
