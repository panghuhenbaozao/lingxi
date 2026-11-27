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
    @State private var showResetConfirm = false

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
            return "日间 \(dayName) · 夜间 \(nightName)"
        case .alwaysLight:
            return "锁定浅色 · \(activePreset.name)"
        case .alwaysDark:
            return "锁定深色 · \(activePreset.name)"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.md) {
                    previewCard
                    appearanceModeCard
                    groupedPresetGrid
                    advancedLinksCard
                }
                .lxReadableWidth()
                .padding(.horizontal, Design.Spacing.md)
                .padding(.top, Design.Spacing.xs)
                .padding(.bottom, Design.Spacing.xxl)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("外观")
            .lxToast($bridgeToast)
            .confirmationDialog("恢复默认外观？", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("恢复默认", role: .destructive) {
                    resetToDefault()
                }
            } message: {
                Text("日间「苹果原生白」+ 夜间「苹果原生暗」跟随系统，并清除自定义颜色与键帽阴影调整。壁纸不受影响。")
            }
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

    private var isDefaultComfortable: Bool {
        appState.theme.lightThemeID == "lingxi_pure" &&
            appState.theme.darkThemeID == "midnight_geek" &&
            appState.theme.appearanceMode == .followSystem &&
            !appState.theme.hasCustomColorOverrides
    }

    private func resetToDefault() {
        appState.theme.lightThemeID = "lingxi_pure"
        appState.theme.darkThemeID = "midnight_geek"
        appState.theme.selectedThemeID = "lingxi_pure"
        appState.theme.appearanceMode = .followSystem
        appState.theme.adaptiveDarkMode = true
        appState.theme.clearCustomColors()
        appState.theme.keyShadowScale = 1.0
        previewDarkOverride = nil
        bridgeToast = "已恢复默认外观"
    }

    // MARK: - 1. 外观模式卡 + 跨进程同步状态

    private var appearanceModeCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("外观模式")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Spacer()
                    if isDefaultComfortable {
                        LXTag(
                            text: AppGroup.isAvailable ? "实时同步" : "默认外观",
                            icon: "checkmark",
                            tint: Color(Design.Palette.success),
                            filled: true
                        )
                    } else {
                        Button {
                            showResetConfirm = true
                        } label: {
                            Label("恢复默认", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
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

                HStack(alignment: .center, spacing: 8) {
                    Text(appearanceStatusSummary)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if appState.theme.appearanceMode == .followSystem {
                        Button {
                            previewDarkOverride = !previewIsDark
                        } label: {
                            Label(previewIsDark ? "预览日间" : "预览夜间", systemImage: previewIsDark ? "sun.max" : "moon")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                    }
                }

                if !AppGroup.isAvailable {
                    Button {
                        Task {
                            isSyncingBridge = true
                            defer { isSyncingBridge = false }
                            let res = await appState.copySideloadBridgeTokenAndSync()
                            bridgeToast = res.message.hasPrefix("✓")
                                ? String(res.message.dropFirst()).trimmingCharacters(in: .whitespaces)
                                : res.message
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Group {
                                if isSyncingBridge {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color(Design.Palette.accent))
                                }
                            }
                            .frame(width: 20)
                            Text("免费侧载模式：选好皮肤后需要同步给键盘")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Text("同步")
                                .font(.caption.bold())
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(Design.Palette.accent), in: Capsule())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(Design.Palette.accentSoft), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncingBridge)
                }
            }
        }
    }

    // MARK: - 2. 精简实时键盘预览卡

    private var previewCard: some View {
        let preset = activePreset
        let hasBg = appState.customBgPreview != nil
        let keyAlpha = hasBg ? appState.theme.keyOpacity : 1.0
        let radius = appState.theme.keyCornerRadius

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                    Text("AI")
                        .font(.system(size: 11.5, weight: .semibold))
                }
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

    // MARK: - 3. 精校预设主题

    private var groupedPresetGrid: some View {
        let lightPresets = KeyboardThemePreset.presets.filter { !$0.isDark }
        let darkPresets = KeyboardThemePreset.presets.filter(\.isDark)
        return VStack(alignment: .leading, spacing: Design.Spacing.md) {
            presetSection(title: "浅色护眼", icon: "sun.max", presets: lightPresets)
            presetSection(title: "深色精校", icon: "moon.stars", presets: darkPresets)
        }
    }

    private func presetSection(title: String, icon: String, presets: [KeyboardThemePreset]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.slate))
                Text("\(presets.count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.stone))
            }
            .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(presets) { preset in
                    presetCard(preset)
                }
            }
        }
    }

    private func presetCard(_ preset: KeyboardThemePreset) -> some View {
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

        return Button {
            appState.theme.applyPresetSelection(preset, isSystemDark: colorScheme == .dark)
            previewDarkOverride = nil
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // 迷你键盘缩略图
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 4) {
                        HStack(spacing: 3) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color(hexColor: preset.keyFill))
                                    .frame(height: 11)
                            }
                        }
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color(hexColor: preset.specialKeyFill))
                                .frame(width: 18, height: 11)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color(hexColor: preset.keyFill))
                                .frame(height: 11)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color(hexColor: preset.accentFill))
                                .frame(width: 20, height: 11)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [Color(hexColor: preset.canvasTop), Color(hexColor: preset.canvasBottom)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
                    )

                    if isCurrentlyActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.white, Color(Design.Palette.accent))
                            .padding(4)
                    }
                }

                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .lineLimit(1)
                        Text(preset.subtitle)
                            .font(.caption2)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isPairedStandby {
                        LXTag(text: preset.isDark ? "夜配" : "日配", tint: Color(Design.Palette.accent), filled: true)
                    }
                }
            }
            .padding(10)
            .background(Color(Design.Palette.canvas), in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                    .stroke(
                        isCurrentlyActive ? Color(Design.Palette.accent) : Color(Design.Palette.hairline),
                        lineWidth: isCurrentlyActive ? 2 : 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name)，\(preset.subtitle)")
        .accessibilityAddTraits(isCurrentlyActive ? .isSelected : [])
    }

    // MARK: - 4. L2 进阶外观子页入口（自由调色 / 壁纸几何 / JSON 分享）

    private var advancedLinksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            LXSectionLabel("进阶定制")

            LXGroupCard {
                NavigationLink {
                    ThemeColorPaletteView()
                } label: {
                    LXCleanRow(
                        icon: "eyedropper.halffull",
                        title: "自由调色",
                        value: appState.theme.hasCustomColorOverrides ? "已自定义" : "默认"
                    )
                }
                Divider().padding(.leading, 58)
                NavigationLink {
                    ThemeWallpaperAndKeyDetailView()
                } label: {
                    LXCleanRow(
                        icon: "photo.on.rectangle.angled",
                        title: "壁纸与键帽",
                        value: appState.customBgPreview != nil ? "已设壁纸" : "圆角 \(Int(appState.theme.keyCornerRadius))pt"
                    )
                }
                Divider().padding(.leading, 58)
                NavigationLink {
                    ThemeCommunityShareView()
                } label: {
                    LXCleanRow(
                        icon: "square.and.arrow.up",
                        title: "皮肤导入导出"
                    )
                }
            }
        }
    }
}

// MARK: - L2 子页 1：日夜双套独立自由调色板

struct ThemeColorPaletteView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingDark: Bool = false
    @State private var confirmReset = false
    @State private var toast: String?

    private var activePreset: KeyboardThemePreset {
        appState.theme.activePreset(isSystemDark: editingDark)
    }

    private var isFollowSystem: Bool {
        appState.theme.appearanceMode == .followSystem
    }

    private var hasOverrides: Bool {
        editingDark ? appState.theme.hasDarkCustomOverrides : appState.theme.hasLightCustomOverrides
    }

    private var channelName: String { editingDark ? "夜间" : "日间" }

    var body: some View {
        let preset = activePreset
        let ratio = preset.keyFill.contrastRatio(with: preset.keyText)
        let passes = ratio >= 4.5

        return Form {
            Section {
                if isFollowSystem {
                    Picker("编辑哪一套", selection: $editingDark) {
                        Text("日间配色").tag(false)
                        Text("夜间配色").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
                palettePreview(preset)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } footer: {
                Text(isFollowSystem
                     ? "日间、夜间两套颜色互不影响，系统切换深浅色时自动换用。"
                     : "当前外观锁定为「\(editingDark ? "始终深色" : "始终浅色")」，只需要调这一套。")
            }

            Section {
                ColorPicker(
                    "键盘底板",
                    selection: hexColorBinding(editingDark ? \.customDarkCanvasHex : \.customCanvasHex, fallback: preset.canvasTop),
                    supportsOpacity: false
                )
                ColorPicker(
                    "字母键帽",
                    selection: hexColorBinding(editingDark ? \.customDarkKeyFillHex : \.customKeyFillHex, fallback: preset.keyFill),
                    supportsOpacity: false
                )
                ColorPicker(
                    "按键文字",
                    selection: hexColorBinding(editingDark ? \.customDarkKeyTextHex : \.customKeyTextHex, fallback: preset.keyText),
                    supportsOpacity: false
                )
                ColorPicker(
                    "发送键与强调色",
                    selection: hexColorBinding(editingDark ? \.customDarkAccentHex : \.customAccentHex, fallback: preset.accentFill),
                    supportsOpacity: false
                )
            } header: {
                Text("\(channelName)颜色")
            }

            Section {
                HStack(spacing: 12) {
                    LXIconTile(
                        icon: passes ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                        tint: passes ? Color(Design.Palette.success) : Color(Design.Palette.warning)
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", ratio))
                                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text(": 1")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                        Text(passes ? "文字清晰，符合 WCAG AA 标准" : "文字偏淡，低于 4.5 : 1 时不易看清")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    Spacer(minLength: 6)
                    if !passes {
                        Button("自动修正") {
                            let autoText = preset.keyFill.isDarkColor ? "#FFFFFF" : "#111113"
                            if editingDark {
                                appState.theme.customDarkKeyTextHex = autoText
                            } else {
                                appState.theme.customKeyTextHex = autoText
                            }
                            toast = "已把按键文字调整为高对比色"
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("按键文字对比度")
            }

            if hasOverrides {
                Section {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Text("恢复\(channelName)原色")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                }
            }
        }
        .navigationTitle("自由调色板")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
        .confirmationDialog("恢复\(channelName)原色？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("恢复原色", role: .destructive) {
                appState.theme.clearCustomColors(forDark: editingDark)
                toast = "已恢复\(channelName)原色"
            }
        } message: {
            Text("\(channelName)的 4 项自定义颜色会被清除，回到「\(KeyboardThemePreset.find(id: editingDark ? appState.theme.darkThemeID : appState.theme.lightThemeID).name)」的配色。")
        }
        .onAppear {
            switch appState.theme.appearanceMode {
            case .alwaysDark: editingDark = true
            case .alwaysLight: editingDark = false
            case .followSystem: editingDark = (colorScheme == .dark)
            }
        }
    }

    /// 迷你键盘实时预览：调色时立即看到效果
    private func palettePreview(_ preset: KeyboardThemePreset) -> some View {
        let radius = appState.theme.keyCornerRadius
        return VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(["Q", "W", "E", "R", "T", "Y"], id: \.self) { ch in
                    previewKey(ch, fill: Color(hexColor: preset.keyFill), text: Color(hexColor: preset.keyText), radius: radius)
                }
            }
            HStack(spacing: 5) {
                previewKey("123", fill: Color(hexColor: preset.specialKeyFill), text: Color(hexColor: preset.keyText), radius: radius)
                    .frame(width: 44)
                previewKey("灵犀", fill: Color(hexColor: preset.keyFill), text: Color(hexColor: preset.keyHintText), radius: radius)
                previewKey("发送", fill: Color(hexColor: preset.accentFill), text: Color(hexColor: preset.accentText), radius: radius)
                    .frame(width: 56)
            }
        }
        .padding(8)
        .background(
            LinearGradient(
                colors: [Color(hexColor: preset.canvasTop), Color(hexColor: preset.canvasBottom)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(channelName)键盘配色预览")
    }

    private func previewKey(_ label: String, fill: Color, text: Color, radius: Double) -> some View {
        Text(label)
            .font(.system(size: label.count > 1 ? 11.5 : 14, weight: appState.theme.boldKeyLabel ? .semibold : .regular))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
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
    @State private var isLoadingPhoto = false
    @State private var confirmRemove = false
    @State private var toast: String?

    var body: some View {
        Form {
            Section {
                if let img = appState.customBgPreview {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .blur(radius: appState.theme.backgroundBlurRadius * 0.6)
                        .overlay(Color.black.opacity(appState.theme.backgroundDimOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .accessibilityLabel("当前键盘壁纸预览")
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 10) {
                        if isLoadingPhoto {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                                .foregroundStyle(Color(Design.Palette.accent))
                        }
                        Text(isLoadingPhoto ? "正在处理图片…" : (appState.customBgPreview == nil ? "从相册选择壁纸" : "更换壁纸"))
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                    .frame(minHeight: 36)
                }
                .disabled(isLoadingPhoto)

                if appState.customBgPreview != nil {
                    sliderRow(title: "模糊", value: $appState.theme.backgroundBlurRadius, range: 0...24, format: "%.0f", defaultValue: nil)
                    sliderRow(title: "暗化遮罩", value: $appState.theme.backgroundDimOpacity, range: 0...0.75, format: "%.2f", defaultValue: nil)
                    sliderRow(title: "按键不透明度", value: $appState.theme.keyOpacity, range: 0.4...1.0, format: "%.2f", defaultValue: nil)
                    Button(role: .destructive) {
                        confirmRemove = true
                    } label: {
                        Text("移除壁纸")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                }
            } header: {
                Text("键盘壁纸")
            } footer: {
                Text(appState.customBgPreview == nil
                     ? "选一张喜欢的照片作为键盘背景，之后可以调整模糊和暗化，让文字保持清晰。"
                     : "壁纸越花，越建议调高模糊和暗化，按键文字会更清楚。")
            }

            Section {
                sliderRow(title: "按键圆角", value: $appState.theme.keyCornerRadius, range: 2...14, format: "%.0f pt", defaultValue: nil)
                sliderRow(title: "立体阴影", value: $appState.theme.keyShadowScale, range: 0.0...1.6, format: "%.1f×", defaultValue: 1.0)
                LXToggleRow("键帽文字加粗", isOn: $appState.theme.boldKeyLabel)
            } header: {
                Text("键帽细节")
            }

            if appState.theme.appearanceMode == .followSystem {
                Section {
                    Picker("日间主题", selection: Binding(
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
                    Picker("夜间主题", selection: Binding(
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
                } header: {
                    Text("跟随系统时的日夜配对")
                } footer: {
                    Text("更换主题会清除该时段的自定义颜色。")
                }
            }
        }
        .navigationTitle("壁纸与键帽细节")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
        .confirmationDialog("移除键盘壁纸？", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                appState.removeCustomBackgroundImage()
                toast = "已移除壁纸"
            }
        }
        .onChange(of: selectedPhotoItem) { newItem in
            guard let newItem else { return }
            isLoadingPhoto = true
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                let image = data.flatMap { UIImage(data: $0) }
                await MainActor.run {
                    if let image {
                        appState.saveCustomBackgroundImage(image)
                        toast = "已设置为键盘壁纸"
                    } else {
                        toast = "无法读取这张图片，换一张试试"
                    }
                    isLoadingPhoto = false
                    selectedPhotoItem = nil
                }
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String, defaultValue: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                if let defaultValue, abs(value.wrappedValue - defaultValue) > 0.001 {
                    Button("默认") {
                        value.wrappedValue = defaultValue
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.accent))
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                }
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.stone))
            }
            Slider(value: value, in: range)
                .tint(Color(Design.Palette.accent))
                .accessibilityLabel(title)
                .accessibilityValue(String(format: format, value.wrappedValue))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - L2 子页 3：社区皮肤 JSON 分享与导入

struct ThemeCommunityShareView: View {
    @EnvironmentObject private var appState: AppState
    @State private var toast: String?
    @State private var pendingImport: ThemeCustomization?

    private var exportJSON: String? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(appState.theme) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    LXIconTile(icon: "square.and.arrow.up.on.square", size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("把你的皮肤分享给朋友")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("导出的是一段文字配置：日夜两套配色、圆角和阴影。壁纸图片不包含在内。")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("导出") {
                if let json = exportJSON {
                    ShareLink(item: json) {
                        Label("分享皮肤配置", systemImage: "square.and.arrow.up")
                            .frame(minHeight: 36)
                    }
                    Button {
                        UIPasteboard.general.string = json
                        toast = "已复制皮肤配置"
                    } label: {
                        Label("复制到剪贴板", systemImage: "doc.on.doc")
                            .frame(minHeight: 36)
                    }
                }
            }

            Section {
                Button {
                    importFromClipboard()
                } label: {
                    Label("从剪贴板导入", systemImage: "arrow.down.doc")
                        .frame(minHeight: 36)
                }
            } header: {
                Text("导入")
            } footer: {
                Text("先复制朋友发来的皮肤配置文字，再点上面的按钮。导入前会先确认。")
            }
        }
        .navigationTitle("皮肤分享与导入")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
        .confirmationDialog(
            "应用这个皮肤？",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            titleVisibility: .visible
        ) {
            Button("应用") {
                if let imported = pendingImport {
                    appState.theme = imported
                    toast = "已应用导入的皮肤"
                }
                pendingImport = nil
            }
        } message: {
            Text("当前的外观设置会被替换。如需保留，可以先导出备份一份。")
        }
    }

    private func importFromClipboard() {
        guard let raw = ConcealedPasteboard.readNonConcealedStringForUserPaste() else {
            toast = ConcealedPasteboard.isConcealed()
                ? "受保护的保险箱内容不能作为皮肤配置导入"
                : "剪贴板是空的，先复制皮肤配置"
            return
        }
        guard let data = raw.data(using: .utf8),
              let imported = try? JSONDecoder().decode(ThemeCustomization.self, from: data) else {
            toast = "无法识别：剪贴板里不是有效的皮肤配置"
            return
        }
        pendingImport = imported
    }
}
