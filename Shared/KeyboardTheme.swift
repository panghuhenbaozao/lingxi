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

/// 一套完整的键盘配色与外观规范（对标 Apple iOS 原生视觉层次与 WCAG 高对比标准）。
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
        // MARK: - 浅色护眼系列（6 套）
        KeyboardThemePreset(
            id: "lingxi_pure",
            name: "苹果原生白",
            subtitle: "iOS 原生层次 · 纯白立体键帽",
            isDark: false,
            canvasTop: HexColor("#D2D5DB"),
            canvasBottom: HexColor("#CCD0D7"),
            toolbarBackground: HexColor("#E5E7EC"),
            keyFill: HexColor("#FFFFFF"),
            keyPressedFill: HexColor("#E3E6EC"),
            specialKeyFill: HexColor("#AEB4C0"),
            specialKeyPressedFill: HexColor("#99A0AE"),
            accentFill: HexColor("#007AFF"),
            accentPressedFill: HexColor("#0062CC"),
            keyText: HexColor("#000000"),
            keyHintText: HexColor("#5C6068"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#111214"),
            candidateHighlight: HexColor("#007AFF"),
            keyShadowHex: HexColor("#898A8D"),
            keyShadowOpacity: 0.42
        ),
        KeyboardThemePreset(
            id: "cloud_snow",
            name: "雪域轻白",
            subtitle: "通透轻盈 · 柔和浅灰底板",
            isDark: false,
            canvasTop: HexColor("#E9ECEF"),
            canvasBottom: HexColor("#E1E5EA"),
            toolbarBackground: HexColor("#F5F6F8"),
            keyFill: HexColor("#FFFFFF"),
            keyPressedFill: HexColor("#DDE2E9"),
            specialKeyFill: HexColor("#D3D8E0"),
            specialKeyPressedFill: HexColor("#BFC6D1"),
            accentFill: HexColor("#007AFF"),
            accentPressedFill: HexColor("#005EC4"),
            keyText: HexColor("#111318"),
            keyHintText: HexColor("#636872"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#111318"),
            candidateHighlight: HexColor("#007AFF"),
            keyShadowHex: HexColor("#8D95A2"),
            keyShadowOpacity: 0.30
        ),
        KeyboardThemePreset(
            id: "warm_paper",
            name: "暖纸护眼",
            subtitle: "墨水屏柔和米白 · 久打不累眼",
            isDark: false,
            canvasTop: HexColor("#E6E1D8"),
            canvasBottom: HexColor("#DDD7CC"),
            toolbarBackground: HexColor("#F2EFE9"),
            keyFill: HexColor("#FBF9F5"),
            keyPressedFill: HexColor("#EAE3D7"),
            specialKeyFill: HexColor("#D5CEC2"),
            specialKeyPressedFill: HexColor("#C3BAB0"),
            accentFill: HexColor("#B86B2B"),
            accentPressedFill: HexColor("#995721"),
            keyText: HexColor("#231F1B"),
            keyHintText: HexColor("#746B61"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#231F1B"),
            candidateHighlight: HexColor("#A85E22"),
            keyShadowHex: HexColor("#8F8679"),
            keyShadowOpacity: 0.32
        ),
        KeyboardThemePreset(
            id: "lingxi_light",
            name: "冰川雾蓝",
            subtitle: "清澈蓝灰 · 精致商务风",
            isDark: false,
            canvasTop: HexColor("#DCE4EE"),
            canvasBottom: HexColor("#D1DCE8"),
            toolbarBackground: HexColor("#EDF2F8"),
            keyFill: HexColor("#FFFFFF"),
            keyPressedFill: HexColor("#D4E1F2"),
            specialKeyFill: HexColor("#B8C7DA"),
            specialKeyPressedFill: HexColor("#A2B4CC"),
            accentFill: HexColor("#2563EB"),
            accentPressedFill: HexColor("#1D4ED8"),
            keyText: HexColor("#0F172A"),
            keyHintText: HexColor("#5B6B82"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#0F172A"),
            candidateHighlight: HexColor("#2563EB"),
            keyShadowHex: HexColor("#7A8FA8"),
            keyShadowOpacity: 0.32
        ),
        KeyboardThemePreset(
            id: "morandi_sage",
            name: "抹茶松烟",
            subtitle: "低饱和青翠 · 清新宁静",
            isDark: false,
            canvasTop: HexColor("#DCE6DF"),
            canvasBottom: HexColor("#D0DDD4"),
            toolbarBackground: HexColor("#ECF2EE"),
            keyFill: HexColor("#FAFDFB"),
            keyPressedFill: HexColor("#CBE0D2"),
            specialKeyFill: HexColor("#B5C9BC"),
            specialKeyPressedFill: HexColor("#9FB8A8"),
            accentFill: HexColor("#2E7D5B"),
            accentPressedFill: HexColor("#226146"),
            keyText: HexColor("#182B22"),
            keyHintText: HexColor("#5B7467"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#182B22"),
            candidateHighlight: HexColor("#246C4D"),
            keyShadowHex: HexColor("#6F8779"),
            keyShadowOpacity: 0.28
        ),
        KeyboardThemePreset(
            id: "sakura_mist",
            name: "柔粉樱云",
            subtitle: "浅粉柔和 · 温润轻甜",
            isDark: false,
            canvasTop: HexColor("#F2DFE7"),
            canvasBottom: HexColor("#EAD2DC"),
            toolbarBackground: HexColor("#FAF0F4"),
            keyFill: HexColor("#FFFFFF"),
            keyPressedFill: HexColor("#F5D0DF"),
            specialKeyFill: HexColor("#DFBDCB"),
            specialKeyPressedFill: HexColor("#CFA3B5"),
            accentFill: HexColor("#D94E86"),
            accentPressedFill: HexColor("#BA3A6E"),
            keyText: HexColor("#3A1D2B"),
            keyHintText: HexColor("#8A6275"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#3A1D2B"),
            candidateHighlight: HexColor("#C73E76"),
            keyShadowHex: HexColor("#9A6B7F"),
            keyShadowOpacity: 0.26
        ),

        // MARK: - 深色舒适系列（6 套 · 高对比度键帽，拒绝一团黑）
        KeyboardThemePreset(
            id: "midnight_geek",
            name: "苹果原生暗",
            subtitle: "iOS 暗黑精校 · 通透清晰不刺眼",
            isDark: true,
            canvasTop: HexColor("#1C1C1E"),
            canvasBottom: HexColor("#171719"),
            toolbarBackground: HexColor("#242426"),
            keyFill: HexColor("#56565A"),
            keyPressedFill: HexColor("#707075"),
            specialKeyFill: HexColor("#3A3A3E"),
            specialKeyPressedFill: HexColor("#505056"),
            accentFill: HexColor("#0A84FF"),
            accentPressedFill: HexColor("#006BE0"),
            keyText: HexColor("#FFFFFF"),
            keyHintText: HexColor("#C2C2C8"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#F2F2F7"),
            candidateHighlight: HexColor("#4DA3FF"),
            keyShadowHex: HexColor("#000000"),
            keyShadowOpacity: 0.48
        ),
        KeyboardThemePreset(
            id: "true_oled",
            name: "午夜 OLED 黑",
            subtitle: "纯黑省电 · 浮雕灰键清晰利落",
            isDark: true,
            canvasTop: HexColor("#09090B"),
            canvasBottom: HexColor("#000000"),
            toolbarBackground: HexColor("#121215"),
            keyFill: HexColor("#343439"),
            keyPressedFill: HexColor("#4D4D54"),
            specialKeyFill: HexColor("#222226"),
            specialKeyPressedFill: HexColor("#38383F"),
            accentFill: HexColor("#0A84FF"),
            accentPressedFill: HexColor("#0068D6"),
            keyText: HexColor("#FFFFFF"),
            keyHintText: HexColor("#AEAEB5"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#F5F5F7"),
            candidateHighlight: HexColor("#52A6FF"),
            keyShadowHex: HexColor("#000000"),
            keyShadowOpacity: 0.60
        ),
        KeyboardThemePreset(
            id: "deep_ocean",
            name: "深海青黛",
            subtitle: "沉静靛蓝 · 夜间护眼专注",
            isDark: true,
            canvasTop: HexColor("#151C26"),
            canvasBottom: HexColor("#10161F"),
            toolbarBackground: HexColor("#1B2430"),
            keyFill: HexColor("#354459"),
            keyPressedFill: HexColor("#4A5D78"),
            specialKeyFill: HexColor("#243040"),
            specialKeyPressedFill: HexColor("#344459"),
            accentFill: HexColor("#38BDF8"),
            accentPressedFill: HexColor("#0EA5E9"),
            keyText: HexColor("#F8FAFC"),
            keyHintText: HexColor("#AFC0D6"),
            accentText: HexColor("#081B29"),
            candidateText: HexColor("#F1F5F9"),
            candidateHighlight: HexColor("#5CCBFF"),
            keyShadowHex: HexColor("#060A10"),
            keyShadowOpacity: 0.50
        ),
        KeyboardThemePreset(
            id: "obsidian_gold",
            name: "石墨曜金",
            subtitle: "暖灰炭石 · 鎏金高级质感",
            isDark: true,
            canvasTop: HexColor("#1B1917"),
            canvasBottom: HexColor("#141210"),
            toolbarBackground: HexColor("#24211E"),
            keyFill: HexColor("#47423B"),
            keyPressedFill: HexColor("#5F574D"),
            specialKeyFill: HexColor("#312D28"),
            specialKeyPressedFill: HexColor("#464039"),
            accentFill: HexColor("#E0B24F"),
            accentPressedFill: HexColor("#C49635"),
            keyText: HexColor("#FAF5EC"),
            keyHintText: HexColor("#C7BCA9"),
            accentText: HexColor("#1A1408"),
            candidateText: HexColor("#F7F0E4"),
            candidateHighlight: HexColor("#F0C565"),
            keyShadowHex: HexColor("#000000"),
            keyShadowOpacity: 0.50
        ),
        KeyboardThemePreset(
            id: "cyber_neon",
            name: "赛博极光",
            subtitle: "靛紫电光 · 高对比霓虹键帽",
            isDark: true,
            canvasTop: HexColor("#121526"),
            canvasBottom: HexColor("#191430"),
            toolbarBackground: HexColor("#1B1E36"),
            keyFill: HexColor("#353A63"),
            keyPressedFill: HexColor("#4D528A"),
            specialKeyFill: HexColor("#242847"),
            specialKeyPressedFill: HexColor("#373B66"),
            accentFill: HexColor("#00D9B8"),
            accentPressedFill: HexColor("#00B398"),
            keyText: HexColor("#F2FEFF"),
            keyHintText: HexColor("#AEB8E8"),
            accentText: HexColor("#061E1B"),
            candidateText: HexColor("#ECFEFF"),
            candidateHighlight: HexColor("#34F2C4"),
            keyShadowHex: HexColor("#050610"),
            keyShadowOpacity: 0.52
        ),
        KeyboardThemePreset(
            id: "forest_night",
            name: "暗夜松林",
            subtitle: "深苔墨绿 · 温和不刺眼",
            isDark: true,
            canvasTop: HexColor("#141E19"),
            canvasBottom: HexColor("#0F1713"),
            toolbarBackground: HexColor("#1B2821"),
            keyFill: HexColor("#344A3E"),
            keyPressedFill: HexColor("#496656"),
            specialKeyFill: HexColor("#23342B"),
            specialKeyPressedFill: HexColor("#334B3E"),
            accentFill: HexColor("#34D399"),
            accentPressedFill: HexColor("#10B981"),
            keyText: HexColor("#F0FDF6"),
            keyHintText: HexColor("#A8C9B7"),
            accentText: HexColor("#062116"),
            candidateText: HexColor("#ECFDF5"),
            candidateHighlight: HexColor("#4EE3AB"),
            keyShadowHex: HexColor("#050A07"),
            keyShadowOpacity: 0.50
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

/// 用户皮肤自定义配置（支持预设切换、跟随系统自动配对，以及浅色/深色独立自由调色板）。
struct ThemeCustomization: Codable, Equatable {
    var selectedThemeID: String = "lingxi_pure"
    var lightThemeID: String = "lingxi_pure"
    var darkThemeID: String = "midnight_geek"
    var adaptiveDarkMode: Bool = true
    var appearanceMode: KeyboardAppearanceMode = .followSystem

    // 浅色（或传统统一）自定义调色
    var customCanvasHex: String? = nil
    var customKeyFillHex: String? = nil
    var customKeyTextHex: String? = nil
    var customAccentHex: String? = nil

    // 深色独立自由调色（跟随系统或深色模式下互不干扰）
    var customDarkCanvasHex: String? = nil
    var customDarkKeyFillHex: String? = nil
    var customDarkKeyTextHex: String? = nil
    var customDarkAccentHex: String? = nil

    var customBackgroundFileName: String? = nil
    var backgroundBlurRadius: Double = 8.0
    var backgroundDimOpacity: Double = 0.25
    var keyOpacity: Double = 0.96
    var keyCornerRadius: Double = 7.0
    var keyShadowScale: Double = 1.0
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
        customDarkCanvasHex = try c.decodeIfPresent(String.self, forKey: .customDarkCanvasHex)
        customDarkKeyFillHex = try c.decodeIfPresent(String.self, forKey: .customDarkKeyFillHex)
        customDarkKeyTextHex = try c.decodeIfPresent(String.self, forKey: .customDarkKeyTextHex)
        customDarkAccentHex = try c.decodeIfPresent(String.self, forKey: .customDarkAccentHex)
        customBackgroundFileName = try c.decodeIfPresent(String.self, forKey: .customBackgroundFileName)
        backgroundBlurRadius = try c.decodeIfPresent(Double.self, forKey: .backgroundBlurRadius) ?? 8.0
        backgroundDimOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundDimOpacity) ?? 0.25
        keyOpacity = try c.decodeIfPresent(Double.self, forKey: .keyOpacity) ?? 0.96
        keyCornerRadius = try c.decodeIfPresent(Double.self, forKey: .keyCornerRadius) ?? 7.0
        keyShadowScale = try c.decodeIfPresent(Double.self, forKey: .keyShadowScale) ?? 1.0
        boldKeyLabel = try c.decodeIfPresent(Bool.self, forKey: .boldKeyLabel) ?? false
    }

    var hasLightCustomOverrides: Bool {
        customCanvasHex != nil || customKeyFillHex != nil || customKeyTextHex != nil || customAccentHex != nil
    }

    var hasDarkCustomOverrides: Bool {
        customDarkCanvasHex != nil || customDarkKeyFillHex != nil || customDarkKeyTextHex != nil || customDarkAccentHex != nil
    }

    var hasCustomColorOverrides: Bool {
        hasLightCustomOverrides || hasDarkCustomOverrides
    }

    mutating func clearCustomColors() {
        customCanvasHex = nil
        customKeyFillHex = nil
        customKeyTextHex = nil
        customAccentHex = nil
        customDarkCanvasHex = nil
        customDarkKeyFillHex = nil
        customDarkKeyTextHex = nil
        customDarkAccentHex = nil
    }

    mutating func clearCustomColors(forDark isDark: Bool) {
        if isDark {
            customDarkCanvasHex = nil
            customDarkKeyFillHex = nil
            customDarkKeyTextHex = nil
            customDarkAccentHex = nil
        } else {
            customCanvasHex = nil
            customKeyFillHex = nil
            customKeyTextHex = nil
            customAccentHex = nil
        }
    }

    /// 统一的外观模式切换逻辑：切回跟随系统或切换深/浅模式时，自动清理冲突的自定义色覆盖，确保切换 100% 立即生效。
    mutating func applyAppearanceMode(_ mode: KeyboardAppearanceMode) {
        appearanceMode = mode
        adaptiveDarkMode = (mode == .followSystem)
        switch mode {
        case .followSystem:
            if hasLightCustomOverrides, let c = customCanvasHex, HexColor(c).isDarkColor {
                clearCustomColors(forDark: false)
            }
        case .alwaysLight:
            if let canvasHex = customCanvasHex, HexColor(canvasHex).isDarkColor {
                clearCustomColors(forDark: false)
            }
            if KeyboardThemePreset.find(id: selectedThemeID).isDark {
                selectedThemeID = lightThemeID
            }
        case .alwaysDark:
            if let canvasHex = customCanvasHex, !HexColor(canvasHex).isDarkColor {
                clearCustomColors(forDark: false)
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

        let cCanvas: String?
        let cKey: String?
        let cText: String?
        let cAccent: String?
        if appearanceMode == .followSystem {
            if base.isDark {
                cCanvas = customDarkCanvasHex
                cKey = customDarkKeyFillHex
                cText = customDarkKeyTextHex
                cAccent = customDarkAccentHex
            } else {
                cCanvas = customCanvasHex
                cKey = customKeyFillHex
                cText = customKeyTextHex
                cAccent = customAccentHex
            }
        } else if base.isDark && hasDarkCustomOverrides {
            cCanvas = customDarkCanvasHex
            cKey = customDarkKeyFillHex
            cText = customDarkKeyTextHex
            cAccent = customDarkAccentHex
        } else {
            cCanvas = customCanvasHex
            cKey = customKeyFillHex
            cText = customKeyTextHex
            cAccent = customAccentHex
        }

        let hasActiveCustom = (cCanvas != nil || cKey != nil || cText != nil || cAccent != nil)
        guard hasActiveCustom else {
            if abs(keyShadowScale - 1.0) < 0.01 { return base }
            return KeyboardThemePreset(
                id: base.id, name: base.name, subtitle: base.subtitle, isDark: base.isDark,
                canvasTop: base.canvasTop, canvasBottom: base.canvasBottom, toolbarBackground: base.toolbarBackground,
                keyFill: base.keyFill, keyPressedFill: base.keyPressedFill,
                specialKeyFill: base.specialKeyFill, specialKeyPressedFill: base.specialKeyPressedFill,
                accentFill: base.accentFill, accentPressedFill: base.accentPressedFill,
                keyText: base.keyText, keyHintText: base.keyHintText, accentText: base.accentText,
                candidateText: base.candidateText, candidateHighlight: base.candidateHighlight,
                keyShadowHex: base.keyShadowHex,
                keyShadowOpacity: min(0.85, max(0.0, base.keyShadowOpacity * keyShadowScale))
            )
        }

        let canvasTop = cCanvas.map { HexColor($0) } ?? base.canvasTop
        let effectiveDark = cCanvas != nil ? canvasTop.isDarkColor : base.isDark
        let canvasBottom = cCanvas != nil
            ? canvasTop.adjustedBrightness(by: effectiveDark ? -0.04 : -0.03)
            : base.canvasBottom
        let toolbarBg = cCanvas != nil
            ? canvasTop.adjustedBrightness(by: effectiveDark ? 0.05 : 0.05)
            : base.toolbarBackground

        let keyFill = cKey.map { HexColor($0) } ?? base.keyFill
        let keyPressed = cKey != nil
            ? keyFill.adjustedBrightness(by: keyFill.isDarkColor ? 0.12 : -0.11)
            : base.keyPressedFill
        let specialKey = cCanvas != nil
            ? canvasTop.adjustedBrightness(by: effectiveDark ? 0.10 : -0.10)
            : base.specialKeyFill
        let specialPressed = cCanvas != nil
            ? specialKey.adjustedBrightness(by: effectiveDark ? 0.10 : -0.09)
            : base.specialKeyPressedFill

        let keyText = cText.map { HexColor($0) } ?? base.keyText
        let keyHint = cText != nil
            ? keyText.adjustedBrightness(by: keyText.isDarkColor ? 0.32 : -0.24)
            : base.keyHintText

        let accent = cAccent.map { HexColor($0) } ?? base.accentFill
        let accentPressed = cAccent != nil
            ? accent.adjustedBrightness(by: accent.isDarkColor ? 0.12 : -0.12)
            : base.accentPressedFill
        let accentText = cAccent != nil
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
            keyShadowOpacity: min(0.85, max(0.0, (effectiveDark ? 0.45 : 0.36) * keyShadowScale))
        )
    }

    var customBackgroundURL: URL? {
        guard let name = customBackgroundFileName, !name.isEmpty else { return nil }
        let url = AppGroup.fileURL(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
