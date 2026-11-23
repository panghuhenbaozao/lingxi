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

/// 键盘外观 L1 主屏（v5.2 分级重构）：主屏聚焦「模式切换 + 实时预览 + 12 套精校主题」，
/// 自由调色板、壁纸与键帽细节、皮肤 JSON 分享各收口到 L2 独立子页，清爽高效。
struct ThemeStudioView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var previewDarkOverride: Bool? = nil
    @State private var pressedPreviewKey: String?
    @State private var bridgeToast: String?
    @State private var isSyncingBridge = false

    private var previewIsDark: Bool {
        switch appState.theme.appearanceMode {
        case .alwaysLight:
            return false
        case .alwaysDark:
            return true
        case .followSystem:
            return previewDarkOverride ?? (colorScheme == .dark)
        }
    }

    private var activePreset: KeyboardThemePreset {
        appState.theme.activePreset(isSystemDark: previewIsDark)
    }

    private var appearanceStatusSummary: String {
        switch appState.theme.appearanceMode {
        case .followSystem:
            let dayName = KeyboardThemePreset.find(id: appState.theme.lightThemeID).name
            let nightName = KeyboardThemePreset.find(id: appState.theme.darkThemeID).name
            return "跟随系统：日间「\(dayName)」· 夜间「\(nightName)」"
        case .alwaysLight:
            return "已锁定浅色「\(activePreset.name)」，切换任意 App 不变色"
        case .alwaysDark:
            return "已锁定深色「\(activePreset.name)」，切换任意 App 不变色"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    appearanceModeCard
                    previewCard
                    groupedPresetGrid
                    advancedLinksCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("外观")
            .onAppear {
                appState.reloadSharedThemeAndSettingsIfNeeded()
                if appState.theme.appearanceMode != .followSystem {
                    previewDarkOverride = nil
                }
            }
            .onChange(of: appState.theme.appearanceMode) { newMode in
                if newMode != .followSystem {
                    previewDarkOverride = nil
                }
            }
        }
    }

    // MARK: - 1. 外观模式卡 + 跨进程同步状态

    private var appearanceModeCard: some View {
        let isDefaultComfortable = (
            appState.theme.lightThemeID == "lingxi_pure" &&
            appState.theme.darkThemeID == "midnight_geek" &&
            appState.theme.appearanceMode == .followSystem &&
            !appState.theme.hasCustomColorOverrides
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("外观模式")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                if !isDefaultComfortable {
                    Button("恢复默认") {
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
                    .foregroundStyle(Color(Design.Palette.accent))
                } else {
                    Label(AppGroup.isAvailable ? "实时同步" : "原生精校", systemImage: "checkmark.circle.fill")
                        .font(.caption2.bold())
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

            HStack(spacing: 6) {
                Text(appearanceStatusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if appState.theme.appearanceMode == .followSystem {
                    Button {
                        previewDarkOverride = !previewIsDark
                    } label: {
                        Label(previewIsDark ? "看日间" : "看夜间", systemImage: previewIsDark ? "sun.max" : "moon")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(Design.Palette.accentSoft))
                            .foregroundStyle(Color(Design.Palette.accent))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !AppGroup.isAvailable {
                Button {
                    Task {
                        isSyncingBridge = true
                        defer { isSyncingBridge = false }
                        let res = await appState.copySideloadBridgeTokenAndSync()
                        bridgeToast = res.message
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSyncingBridge {
                            ProgressView().scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption.bold())
                        }
                        Text("免费侧载沙盒隔离 · 选好皮肤后点此同步给键盘")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.12))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSyncingBridge)
            }

            if let toast = bridgeToast {
                Text(toast)
                    .font(.caption2)
                    .foregroundStyle(toast.hasPrefix("✓") ? Color(Design.Palette.success) : .orange)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 2. 精简实时键盘预览卡

    private var previewCard: some View {
        let preset = activePreset
        let hasBg = appState.customBgPreview != nil
        let keyAlpha = hasBg ? appState.theme.keyOpacity : 1.0
        let radius = appState.theme.keyCornerRadius

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("✨ AI")
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Color(hexColor: preset.accentFill).opacity(0.18))
                    .foregroundStyle(Color(hexColor: preset.candidateHighlight))
                    .clipShape(Capsule())

                Text("灵犀输入法")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color(hexColor: preset.candidateHighlight))
                Text("丝滑流畅")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color(hexColor: preset.candidateText))
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hexColor: preset.keyText))
                    .frame(width: 26, height: 26)
                    .background(Color(hexColor: preset.keyFill, opacityScale: keyAlpha))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(Color(hexColor: preset.toolbarBackground).opacity(hasBg ? 0.85 : 1.0))

            VStack(spacing: 6) {
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
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(preset.isDark ? 0.24 : 0.08), radius: 8, y: 3)
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
                .font(.system(size: label.count > 2 ? 11 : 13.5, weight: appState.theme.boldKeyLabel ? .semibold : .regular))
                .foregroundStyle(text)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
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

    // MARK: - 3. 12 套精校预设主题

    private var groupedPresetGrid: some View {
        let lightPresets = KeyboardThemePreset.presets.filter { !$0.isDark }
        let darkPresets = KeyboardThemePreset.presets.filter(\.isDark)
        return VStack(alignment: .leading, spacing: 14) {
            presetSection(title: "浅色护眼", presets: lightPresets)
            presetSection(title: "深色精校", presets: darkPresets)
        }
    }

    private func presetSection(title: String, presets: [KeyboardThemePreset]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(presets) { preset in
                    let hasCustomForPresetSide = preset.isDark
                        ? appState.theme.hasDarkCustomOverrides
                        : appState.theme.hasLightCustomOverrides
                    let isCurrentlyActive = (activePreset.id == preset.id && !hasCustomForPresetSide)
                    let isPairedStandby: Bool = {
                        guard appState.theme.appearanceMode == .followSystem, !isCurrentlyActive, !hasCustomForPresetSide else {
                            return false
                        }
                        return preset.isDark
                            ? (appState.theme.darkThemeID == preset.id)
                            : (appState.theme.lightThemeID == preset.id)
                    }()
                    Button {
                        appState.theme.applyPresetSelection(preset, isSystemDark: colorScheme == .dark)
                        previewDarkOverride = nil
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hexColor: preset.canvasTop), Color(hexColor: preset.canvasBottom)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(Color(hexColor: preset.keyFill))
                                            .frame(width: 22, height: 12)
                                            .offset(y: -4)
                                    )
                                Circle()
                                    .fill(Color(hexColor: preset.accentFill))
                                    .frame(width: 9, height: 9)
                                    .offset(x: 7, y: 8)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(preset.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if isCurrentlyActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(Design.Palette.accent))
                            } else if isPairedStandby {
                                Text(preset.isDark ? "夜配" : "日配")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(Design.Palette.accentSoft))
                                    .foregroundStyle(Color(Design.Palette.accent))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(isCurrentlyActive ? Color(Design.Palette.accent) : Color(Design.Palette.hairline).opacity(0.5), lineWidth: isCurrentlyActive ? 2 : 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 4. L2 进阶外观子页入口（自由调色 / 壁纸几何 / JSON 分享）

    private var advancedLinksCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                ThemeColorPaletteView()
            } label: {
                subpageRow(
                    icon: "eyedropper.halffull",
                    title: "自由调色板",
                    badge: appState.theme.hasCustomColorOverrides ? "已自定义" : "日夜双套"
                )
            }
            Divider().padding(.leading, 44)
            NavigationLink {
                ThemeWallpaperAndKeyDetailView()
            } label: {
                subpageRow(
                    icon: "photo.on.rectangle.angled",
                    title: "壁纸与键帽细节",
                    badge: appState.customBgPreview != nil ? "已设壁纸" : "圆角 \(Int(appState.theme.keyCornerRadius))pt"
                )
            }
            Divider().padding(.leading, 44)
            NavigationLink {
                ThemeCommunityShareView()
            } label: {
                subpageRow(
                    icon: "square.and.arrow.up.on.square",
                    title: "皮肤分享与导入",
                    badge: "JSON"
                )
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func subpageRow(icon: String, title: String, badge: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.accent))
                .frame(width: 24)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(Design.Palette.ink))
            Spacer()
            Text(badge)
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

// MARK: - L2 子页 1：日夜双套独立自由调色板

struct ThemeColorPaletteView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingDark: Bool = false

    private var activePreset: KeyboardThemePreset {
        appState.theme.activePreset(isSystemDark: editingDark)
    }

    var body: some View {
        Form {
            Section {
                Picker("编辑通道", selection: $editingDark) {
                    Text("☀️ 日间浅色").tag(false)
                    Text("🌙 夜间深色").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section {
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
            } header: {
                Text(editingDark ? "夜间独立调色（不影响日间）" : "日间独立调色（不影响夜间）")
            }

            Section("对比度校验 (WCAG AA)") {
                let ratio = activePreset.keyFill.contrastRatio(with: activePreset.keyText)
                HStack(spacing: 8) {
                    Image(systemName: ratio >= 4.5 ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(ratio >= 4.5 ? Color(Design.Palette.success) : .orange)
                    Text(ratio >= 4.5
                         ? "对比度达标 (\(String(format: "%.1f", ratio)):1 · 清晰护眼)"
                         : "对比度偏低 (\(String(format: "%.1f", ratio)):1)")
                        .font(.subheadline)
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

                let hasOverrides = editingDark ? appState.theme.hasDarkCustomOverrides : appState.theme.hasLightCustomOverrides
                if hasOverrides {
                    Button("恢复\(editingDark ? "夜间" : "日间")默认原色", role: .destructive) {
                        appState.theme.clearCustomColors(forDark: editingDark)
                    }
                }
            }
        }
        .navigationTitle("自由调色板")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            switch appState.theme.appearanceMode {
            case .alwaysDark: editingDark = true
            case .alwaysLight: editingDark = false
            case .followSystem: editingDark = (colorScheme == .dark)
            }
        }
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
}

// MARK: - L2 子页 2：相册壁纸、键帽几何与日夜配对

struct ThemeWallpaperAndKeyDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section("相册背景壁纸") {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(appState.customBgPreview == nil ? "从相册选择键盘背景图" : "更换键盘背景图", systemImage: "photo.badge.plus")
                }

                if let img = appState.customBgPreview {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    sliderRow(title: "背景模糊度", value: $appState.theme.backgroundBlurRadius, range: 0...24, format: "%.0f")
                    sliderRow(title: "遮罩暗化", value: $appState.theme.backgroundDimOpacity, range: 0...0.75, format: "%.2f")
                    sliderRow(title: "按键不透明度", value: $appState.theme.keyOpacity, range: 0.4...1.0, format: "%.2f")
                    Button("移除背景壁纸", role: .destructive) {
                        appState.removeCustomBackgroundImage()
                    }
                }
            }

            Section("键帽细节") {
                sliderRow(title: "按键圆角", value: $appState.theme.keyCornerRadius, range: 2...14, format: "%.0f pt")
                sliderRow(title: "立体阴影强度", value: $appState.theme.keyShadowScale, range: 0.0...1.6, format: "%.1fx")
                Toggle("键帽加粗字体", isOn: $appState.theme.boldKeyLabel)
            }

            if appState.theme.appearanceMode == .followSystem {
                Section("跟随系统日夜配对") {
                    Picker("日间浅色主题", selection: Binding(
                        get: { appState.theme.lightThemeID },
                        set: { newID in
                            appState.theme.lightThemeID = newID
                            appState.theme.clearCustomColors(forDark: false)
                        }
                    )) {
                        ForEach(KeyboardThemePreset.presets.filter { !$0.isDark }) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    Picker("夜间深色主题", selection: Binding(
                        get: { appState.theme.darkThemeID },
                        set: { newID in
                            appState.theme.darkThemeID = newID
                            appState.theme.clearCustomColors(forDark: true)
                        }
                    )) {
                        ForEach(KeyboardThemePreset.presets.filter(\.isDark)) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("壁纸与键帽细节")
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - L2 子页 3：社区皮肤 JSON 分享与导入

struct ThemeCommunityShareView: View {
    @EnvironmentObject private var appState: AppState
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                Button {
                    let enc = JSONEncoder()
                    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    if let data = try? enc.encode(appState.theme),
                       let json = String(data: data, encoding: .utf8) {
                        UIPasteboard.general.string = json
                        statusMessage = "✓ 已复制当前皮肤配置 JSON 到剪贴板"
                    }
                } label: {
                    Label("复制当前皮肤 JSON", systemImage: "doc.on.doc")
                }

                Button {
                    guard let raw = UIPasteboard.general.string,
                          let data = raw.data(using: .utf8),
                          let imported = try? JSONDecoder().decode(ThemeCustomization.self, from: data) else {
                        statusMessage = "剪贴板中未检测到有效的皮肤 JSON 配置"
                        return
                    }
                    appState.theme = imported
                    statusMessage = "✓ 已导入并立即应用皮肤配置"
                } label: {
                    Label("从剪贴板导入皮肤 JSON", systemImage: "arrow.down.doc.fill")
                }
            } footer: {
                Text("导出内容包含日夜双套配色、圆角与阴影参数，便于与好友分享或跨设备复用。")
            }

            if let msg = statusMessage {
                Section {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(msg.hasPrefix("✓") ? Color(Design.Palette.success) : .orange)
                }
            }
        }
        .navigationTitle("皮肤分享与导入")
        .navigationBarTitleDisplayMode(.inline)
    }
}
