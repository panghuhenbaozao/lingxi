import Foundation

/// 跨平台十六进制颜色表示，供 App (SwiftUI) 与 Keyboard (UIKit) 共用。
struct HexColor: Codable, Equatable, Hashable {
    var hex: String

    init(_ hex: String) {
        self.hex = hex
    }

    /// 解析 `#RRGGBB` 或 `#RRGGBBAA` 为 (r, g, b, a) 0...1。
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        switch clean.count {
        case 6:
            return (
                Double((value >> 16) & 0xFF) / 255.0,
                Double((value >> 8) & 0xFF) / 255.0,
                Double(value & 0xFF) / 255.0,
                1.0
            )
        case 8:
            return (
                Double((value >> 24) & 0xFF) / 255.0,
                Double((value >> 16) & 0xFF) / 255.0,
                Double((value >> 8) & 0xFF) / 255.0,
                Double(value & 0xFF) / 255.0
            )
        default:
            return (0.5, 0.5, 0.5, 1.0)
        }
    }

    /// 感知亮度 (0.0 黑 ~ 1.0 白)
    var luminance: Double {
        let c = rgba
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    }

    var isDarkColor: Bool {
        luminance < 0.48
    }

    /// 按比例调亮/调暗生成按压态、功能键或次级辅助色
    func adjustedBrightness(by delta: Double) -> HexColor {
        let c = rgba
        let nr = max(0.0, min(1.0, c.r + delta))
        let ng = max(0.0, min(1.0, c.g + delta))
        let nb = max(0.0, min(1.0, c.b + delta))
        return HexColor(
            String(
                format: "#%02X%02X%02X",
                Int((nr * 255.0).rounded()),
                Int((ng * 255.0).rounded()),
                Int((nb * 255.0).rounded())
            )
        )
    }

    /// 简化 WCAG 相对对比度（用于自由调色板自动提示可读性）
    func contrastRatio(with other: HexColor) -> Double {
        let l1 = max(luminance, other.luminance)
        let l2 = min(luminance, other.luminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }
}

/// 一套完整的键盘配色与外观规范。
struct KeyboardThemePreset: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let isDark: Bool
    let canvasTop: HexColor
    let canvasBottom: HexColor
    let toolbarBackground: HexColor
    let keyFill: HexColor
    let keyPressedFill: HexColor
    let specialKeyFill: HexColor
    let specialKeyPressedFill: HexColor
    let accentFill: HexColor
    let accentPressedFill: HexColor
    let keyText: HexColor
    let keyHintText: HexColor
    let accentText: HexColor
    let candidateText: HexColor
    let candidateHighlight: HexColor
    let keyShadowHex: HexColor
    let keyShadowOpacity: Double

    static let presets: [KeyboardThemePreset] = [
        KeyboardThemePreset(
            id: "lingxi_pure",
            name: "极简纯白",
            subtitle: "苹果质感 · 纯白圆角键帽",
            isDark: false,
            canvasTop: HexColor("#EAECEF"),
            canvasBottom: HexColor("#E2E5EA"),
            toolbarBackground: HexColor("#F7F8FA"),
            keyFill: HexColor("#FFFFFF"),
            keyPressedFill: HexColor("#DCE0E8"),
            specialKeyFill: HexColor("#D6DBE3"),
            specialKeyPressedFill: HexColor("#C1C8D3"),
            accentFill: HexColor("#0A0A0A"),
            accentPressedFill: HexColor("#222222"),
            keyText: HexColor("#0A0A0A"),
            keyHintText: HexColor("#6E6E73"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#0A0A0A"),
            candidateHighlight: HexColor("#0A0A0A"),
            keyShadowHex: HexColor("#8C929C"),
            keyShadowOpacity: 0.30
        ),
        KeyboardThemePreset(
            id: "cloud_snow",
            name: "雪域全白",
            subtitle: "通体雪白 · 苹果蓝点缀",
            isDark: false,
            canvasTop: HexColor("#F4F5F7"),
            canvasBottom: HexColor("#ECEEF2"),
            toolbarBackground: HexColor("#FFFFFF"),
            keyFill: HexColor("#FFFFFF"),
            keyPressedFill: HexColor("#E6EAF0"),
            specialKeyFill: HexColor("#E5E8EE"),
            specialKeyPressedFill: HexColor("#D3D8E2"),
            accentFill: HexColor("#007AFF"),
            accentPressedFill: HexColor("#0062CC"),
            keyText: HexColor("#111111"),
            keyHintText: HexColor("#787C84"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#111111"),
            candidateHighlight: HexColor("#007AFF"),
            keyShadowHex: HexColor("#949BA6"),
            keyShadowOpacity: 0.26
        ),
        KeyboardThemePreset(
            id: "lingxi_light",
            name: "灵犀白昼",
            subtitle: "通透磨砂 · 清晰护眼",
            isDark: false,
            canvasTop: HexColor("#EEF2F7"),
            canvasBottom: HexColor("#E2E7EF"),
            toolbarBackground: HexColor("#F7F9FC"),
            keyFill: HexColor("#FFFFFF"),
            keyPressedFill: HexColor("#DCE4F0"),
            specialKeyFill: HexColor("#CED6E3"),
            specialKeyPressedFill: HexColor("#B6C2D4"),
            accentFill: HexColor("#2F6FED"),
            accentPressedFill: HexColor("#1E57C8"),
            keyText: HexColor("#111827"),
            keyHintText: HexColor("#7A869A"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#1F2937"),
            candidateHighlight: HexColor("#2F6FED"),
            keyShadowHex: HexColor("#1E293B"),
            keyShadowOpacity: 0.16
        ),
        KeyboardThemePreset(
            id: "midnight_geek",
            name: "暗夜极客",
            subtitle: "深邃石墨 · 夜间首选",
            isDark: true,
            canvasTop: HexColor("#181A20"),
            canvasBottom: HexColor("#111318"),
            toolbarBackground: HexColor("#1E2129"),
            keyFill: HexColor("#2B303C"),
            keyPressedFill: HexColor("#3F4759"),
            specialKeyFill: HexColor("#20242E"),
            specialKeyPressedFill: HexColor("#323846"),
            accentFill: HexColor("#4F8BFF"),
            accentPressedFill: HexColor("#3872E0"),
            keyText: HexColor("#F3F4F6"),
            keyHintText: HexColor("#8E98AB"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#E5E7EB"),
            candidateHighlight: HexColor("#6EA1FF"),
            keyShadowHex: HexColor("#000000"),
            keyShadowOpacity: 0.42
        ),
        KeyboardThemePreset(
            id: "sakura_mist",
            name: "樱花微醺",
            subtitle: "柔粉渐变 · 轻甜质感",
            isDark: false,
            canvasTop: HexColor("#FDF2F6"),
            canvasBottom: HexColor("#F8E1EC"),
            toolbarBackground: HexColor("#FFF7FA"),
            keyFill: HexColor("#FFFFFF"),
            keyPressedFill: HexColor("#FAD7E5"),
            specialKeyFill: HexColor("#F2CEDD"),
            specialKeyPressedFill: HexColor("#E7B4CA"),
            accentFill: HexColor("#E85D93"),
            accentPressedFill: HexColor("#CC447A"),
            keyText: HexColor("#432333"),
            keyHintText: HexColor("#A4798E"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#4A2537"),
            candidateHighlight: HexColor("#D94680"),
            keyShadowHex: HexColor("#832B52"),
            keyShadowOpacity: 0.14
        ),
        KeyboardThemePreset(
            id: "morandi_sage",
            name: "莫兰迪青",
            subtitle: "静谧松烟 · 低饱和高级感",
            isDark: false,
            canvasTop: HexColor("#E8EFEA"),
            canvasBottom: HexColor("#D9E4DC"),
            toolbarBackground: HexColor("#F2F6F3"),
            keyFill: HexColor("#FAFDFB"),
            keyPressedFill: HexColor("#CFE0D5"),
            specialKeyFill: HexColor("#C3D2C8"),
            specialKeyPressedFill: HexColor("#ACBFB3"),
            accentFill: HexColor("#3A7D62"),
            accentPressedFill: HexColor("#2B624C"),
            keyText: HexColor("#1E3129"),
            keyHintText: HexColor("#6F877B"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#1E3129"),
            candidateHighlight: HexColor("#2E6F54"),
            keyShadowHex: HexColor("#1C3429"),
            keyShadowOpacity: 0.15
        ),
        KeyboardThemePreset(
            id: "cyber_neon",
            name: "赛博霓虹",
            subtitle: "电光青紫 · 赛博未来",
            isDark: true,
            canvasTop: HexColor("#0D0F1D"),
            canvasBottom: HexColor("#16112B"),
            toolbarBackground: HexColor("#14162B"),
            keyFill: HexColor("#202442"),
            keyPressedFill: HexColor("#352C68"),
            specialKeyFill: HexColor("#171A33"),
            specialKeyPressedFill: HexColor("#292552"),
            accentFill: HexColor("#00D1B2"),
            accentPressedFill: HexColor("#00A88F"),
            keyText: HexColor("#ECFEFF"),
            keyHintText: HexColor("#7A88C2"),
            accentText: HexColor("#081C1B"),
            candidateText: HexColor("#E0F7FA"),
            candidateHighlight: HexColor("#2CEAA3"),
            keyShadowHex: HexColor("#04050E"),
            keyShadowOpacity: 0.52
        ),
        KeyboardThemePreset(
            id: "obsidian_gold",
            name: "黑金殿堂",
            subtitle: "曜石哑光 · 鎏金点缀",
            isDark: true,
            canvasTop: HexColor("#161412"),
            canvasBottom: HexColor("#0E0D0B"),
            toolbarBackground: HexColor("#1C1A17"),
            keyFill: HexColor("#282520"),
            keyPressedFill: HexColor("#3F382D"),
            specialKeyFill: HexColor("#1E1C18"),
            specialKeyPressedFill: HexColor("#322D25"),
            accentFill: HexColor("#D4A74A"),
            accentPressedFill: HexColor("#B68A32"),
            keyText: HexColor("#F5EFE4"),
            keyHintText: HexColor("#9C907D"),
            accentText: HexColor("#1A1408"),
            candidateText: HexColor("#F3EBDC"),
            candidateHighlight: HexColor("#E5BA5C"),
            keyShadowHex: HexColor("#000000"),
            keyShadowOpacity: 0.48
        ),
    ]

    static func find(id: String) -> KeyboardThemePreset {
        presets.first { $0.id == id } ?? presets[0]
    }
}

/// 键盘外观明暗策略（支持跟随系统自动切换，或手动锁定浅色/深色）。
enum KeyboardAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case followSystem = "follow_system"
    case alwaysLight = "always_light"
    case alwaysDark = "always_dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .followSystem: return "跟随系统"
        case .alwaysLight: return "浅色主题"
        case .alwaysDark: return "深色主题"
        }
    }
}

/// 用户皮肤自定义配置（支持预设切换、跟随系统自动配对，以及自由调色板自定义色值）。
struct ThemeCustomization: Codable, Equatable {
    var selectedThemeID: String = "lingxi_pure"
    var lightThemeID: String = "lingxi_pure"
    var darkThemeID: String = "midnight_geek"
    var adaptiveDarkMode: Bool = true
    var appearanceMode: KeyboardAppearanceMode = .followSystem
    var customCanvasHex: String? = nil
    var customKeyFillHex: String? = nil
    var customKeyTextHex: String? = nil
    var customAccentHex: String? = nil
    var customBackgroundFileName: String? = nil
    var backgroundBlurRadius: Double = 8.0
    var backgroundDimOpacity: Double = 0.25
    var keyOpacity: Double = 0.96
    var keyCornerRadius: Double = 8.0
    var boldKeyLabel: Bool = false

    private static let fileName = "lingxi_theme.json"
    static let customBackgroundImageName = "custom_keyboard_bg.jpg"

    private static var cached: ThemeCustomization?
    private static var cachedMTime: Date?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedThemeID = try c.decodeIfPresent(String.self, forKey: .selectedThemeID) ?? "lingxi_pure"
        let decodedLight = try c.decodeIfPresent(String.self, forKey: .lightThemeID)
        if let decodedLight {
            lightThemeID = decodedLight
        } else {
            let sel = KeyboardThemePreset.find(id: selectedThemeID)
            lightThemeID = sel.isDark ? "lingxi_pure" : sel.id
        }
        darkThemeID = try c.decodeIfPresent(String.self, forKey: .darkThemeID) ?? "midnight_geek"
        adaptiveDarkMode = try c.decodeIfPresent(Bool.self, forKey: .adaptiveDarkMode) ?? true
        appearanceMode = try c.decodeIfPresent(KeyboardAppearanceMode.self, forKey: .appearanceMode)
            ?? (adaptiveDarkMode ? .followSystem : .alwaysLight)
        customCanvasHex = try c.decodeIfPresent(String.self, forKey: .customCanvasHex)
        customKeyFillHex = try c.decodeIfPresent(String.self, forKey: .customKeyFillHex)
        customKeyTextHex = try c.decodeIfPresent(String.self, forKey: .customKeyTextHex)
        customAccentHex = try c.decodeIfPresent(String.self, forKey: .customAccentHex)
        customBackgroundFileName = try c.decodeIfPresent(String.self, forKey: .customBackgroundFileName)
        backgroundBlurRadius = try c.decodeIfPresent(Double.self, forKey: .backgroundBlurRadius) ?? 8.0
        backgroundDimOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundDimOpacity) ?? 0.25
        keyOpacity = try c.decodeIfPresent(Double.self, forKey: .keyOpacity) ?? 0.96
        keyCornerRadius = try c.decodeIfPresent(Double.self, forKey: .keyCornerRadius) ?? 8.0
        boldKeyLabel = try c.decodeIfPresent(Bool.self, forKey: .boldKeyLabel) ?? false
    }

    var hasCustomColorOverrides: Bool {
        customCanvasHex != nil || customKeyFillHex != nil || customKeyTextHex != nil || customAccentHex != nil
    }

    mutating func clearCustomColors() {
        customCanvasHex = nil
        customKeyFillHex = nil
        customKeyTextHex = nil
        customAccentHex = nil
    }

    /// 统一的外观模式切换逻辑：切回跟随系统或切换深/浅模式时，自动清理冲突的自定义色覆盖，确保切换 100% 立即生效。
    mutating func applyAppearanceMode(_ mode: KeyboardAppearanceMode) {
        appearanceMode = mode
        adaptiveDarkMode = (mode == .followSystem)
        switch mode {
        case .followSystem:
            if hasCustomColorOverrides {
                clearCustomColors()
            }
        case .alwaysLight:
            if let canvasHex = customCanvasHex, HexColor(canvasHex).isDarkColor {
                clearCustomColors()
            }
            if KeyboardThemePreset.find(id: selectedThemeID).isDark {
                selectedThemeID = lightThemeID
            }
        case .alwaysDark:
            if let canvasHex = customCanvasHex, !HexColor(canvasHex).isDarkColor {
                clearCustomColors()
            }
            if !KeyboardThemePreset.find(id: selectedThemeID).isDark {
                selectedThemeID = darkThemeID
            }
        }
    }

    /// 统一的预设选择逻辑（App 外观页与键盘内快捷设置共用，保证点任意预设 100% 立即生效）
    mutating func applyPresetSelection(_ preset: KeyboardThemePreset, isSystemDark: Bool) {
        selectedThemeID = preset.id
        clearCustomColors()
        if preset.isDark {
            darkThemeID = preset.id
            if appearanceMode == .alwaysLight || (appearanceMode == .followSystem && !isSystemDark) {
                appearanceMode = .alwaysDark
                adaptiveDarkMode = false
            }
        } else {
            lightThemeID = preset.id
            if appearanceMode == .alwaysDark || (appearanceMode == .followSystem && isSystemDark) {
                appearanceMode = .alwaysLight
                adaptiveDarkMode = false
            }
        }
    }

    static func load(force: Bool = false) -> ThemeCustomization {
        let mtime = AppGroup.modificationDate(of: fileName)
        if !force, let cached, cachedMTime == mtime {
            return cached
        }
        let loaded = AppGroup.readJSON(ThemeCustomization.self, from: fileName) ?? ThemeCustomization()
        cached = loaded
        cachedMTime = mtime
        return loaded
    }

    @discardableResult
    func save() -> Bool {
        let ok = AppGroup.writeJSON(self, to: Self.fileName)
        Self.cached = self
        Self.cachedMTime = AppGroup.modificationDate(of: Self.fileName)
        return ok
    }

    func activePreset(isSystemDark: Bool) -> KeyboardThemePreset {
        let base: KeyboardThemePreset
        switch appearanceMode {
        case .followSystem:
            if isSystemDark {
                let d = KeyboardThemePreset.find(id: darkThemeID)
                base = d.isDark ? d : KeyboardThemePreset.find(id: "midnight_geek")
            } else {
                let l = KeyboardThemePreset.find(id: lightThemeID)
                base = !l.isDark ? l : KeyboardThemePreset.find(id: "lingxi_pure")
            }
        case .alwaysLight:
            let sel = KeyboardThemePreset.find(id: selectedThemeID)
            base = !sel.isDark ? sel : KeyboardThemePreset.find(id: lightThemeID)
        case .alwaysDark:
            let sel = KeyboardThemePreset.find(id: selectedThemeID)
            base = sel.isDark ? sel : KeyboardThemePreset.find(id: darkThemeID)
        }

        guard hasCustomColorOverrides else { return base }
        let canvasTop = customCanvasHex.map { HexColor($0) } ?? base.canvasTop
        let effectiveDark = customCanvasHex != nil ? canvasTop.isDarkColor : base.isDark
        let canvasBottom = customCanvasHex != nil
            ? canvasTop.adjustedBrightness(by: effectiveDark ? -0.04 : -0.03)
            : base.canvasBottom
        let toolbarBg = customCanvasHex != nil
            ? canvasTop.adjustedBrightness(by: effectiveDark ? 0.04 : 0.04)
            : base.toolbarBackground

        let keyFill = customKeyFillHex.map { HexColor($0) } ?? base.keyFill
        let keyPressed = customKeyFillHex != nil
            ? keyFill.adjustedBrightness(by: keyFill.isDarkColor ? 0.12 : -0.11)
            : base.keyPressedFill
        let specialKey = customCanvasHex != nil
            ? canvasTop.adjustedBrightness(by: effectiveDark ? 0.06 : -0.08)
            : base.specialKeyFill
        let specialPressed = customCanvasHex != nil
            ? specialKey.adjustedBrightness(by: effectiveDark ? 0.10 : -0.09)
            : base.specialKeyPressedFill

        let keyText = customKeyTextHex.map { HexColor($0) } ?? base.keyText
        let keyHint = customKeyTextHex != nil
            ? keyText.adjustedBrightness(by: keyText.isDarkColor ? 0.32 : -0.28)
            : base.keyHintText

        let accent = customAccentHex.map { HexColor($0) } ?? base.accentFill
        let accentPressed = customAccentHex != nil
            ? accent.adjustedBrightness(by: accent.isDarkColor ? 0.12 : -0.12)
            : base.accentPressedFill
        let accentText = customAccentHex != nil
            ? (accent.isDarkColor ? HexColor("#FFFFFF") : HexColor("#0A0A0A"))
            : base.accentText

        return KeyboardThemePreset(
            id: base.id,
            name: base.name,
            subtitle: base.subtitle,
            isDark: effectiveDark,
            canvasTop: canvasTop,
            canvasBottom: canvasBottom,
            toolbarBackground: toolbarBg,
            keyFill: keyFill,
            keyPressedFill: keyPressed,
            specialKeyFill: specialKey,
            specialKeyPressedFill: specialPressed,
            accentFill: accent,
            accentPressedFill: accentPressed,
            keyText: keyText,
            keyHintText: keyHint,
            accentText: accentText,
            candidateText: keyText,
            candidateHighlight: accent,
            keyShadowHex: effectiveDark ? HexColor("#000000") : HexColor("#898A8D"),
            keyShadowOpacity: effectiveDark ? 0.42 : 0.32
        )
    }

    var customBackgroundURL: URL? {
        guard let name = customBackgroundFileName, !name.isEmpty else { return nil }
        let url = AppGroup.fileURL(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
