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
            name: "极简白",
            subtitle: "净洁直白 · 线条静美",
            isDark: false,
            canvasTop: HexColor("#FFFFFF"),
            canvasBottom: HexColor("#FFFFFF"),
            toolbarBackground: HexColor("#FFFFFF"),
            keyFill: HexColor("#FFFFFF"),
            keyPressedFill: HexColor("#D4D7DC"),
            specialKeyFill: HexColor("#EDEDF0"),
            specialKeyPressedFill: HexColor("#D4D7DC"),
            accentFill: HexColor("#0A0A0A"),
            accentPressedFill: HexColor("#222222"),
            keyText: HexColor("#0A0A0A"),
            keyHintText: HexColor("#6E6E73"),
            accentText: HexColor("#FFFFFF"),
            candidateText: HexColor("#0A0A0A"),
            candidateHighlight: HexColor("#0A0A0A"),
            keyShadowHex: HexColor("#E5E7EB"),
            keyShadowOpacity: 0.1
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

/// 用户皮肤自定义配置。
struct ThemeCustomization: Codable, Equatable {
    var selectedThemeID: String = "lingxi_pure"
    var darkThemeID: String = "midnight_geek"
    var adaptiveDarkMode: Bool = true
    var customBackgroundFileName: String? = nil
    var backgroundBlurRadius: Double = 8.0
    var backgroundDimOpacity: Double = 0.25
    var keyOpacity: Double = 0.94
    var keyCornerRadius: Double = 7.0
    var boldKeyLabel: Bool = false

    private static let fileName = "lingxi_theme.json"
    static let customBackgroundImageName = "custom_keyboard_bg.jpg"

    private static var cached: ThemeCustomization?
    private static var cachedMTime: Date?

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
        if adaptiveDarkMode && isSystemDark {
            let chosen = KeyboardThemePreset.find(id: selectedThemeID)
            if chosen.isDark {
                return chosen
            }
            let dark = KeyboardThemePreset.find(id: darkThemeID)
            if dark.isDark {
                return dark
            }
            return KeyboardThemePreset.presets.first(where: { $0.isDark }) ?? dark
        }
        return KeyboardThemePreset.find(id: selectedThemeID)
    }

    var customBackgroundURL: URL? {
        guard let name = customBackgroundFileName, !name.isEmpty else { return nil }
        let url = AppGroup.fileURL(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
