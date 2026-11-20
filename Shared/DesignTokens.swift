import UIKit

extension UIColor {
    /// 解析 `#RRGGBB` 或 `#RRGGBBAA`。
    convenience init(hex: String) {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        switch clean.count {
        case 6:
            self.init(
                red: CGFloat((value >> 16) & 0xFF) / 255.0,
                green: CGFloat((value >> 8) & 0xFF) / 255.0,
                blue: CGFloat(value & 0xFF) / 255.0,
                alpha: 1.0
            )
        case 8:
            self.init(
                red: CGFloat((value >> 24) & 0xFF) / 255.0,
                green: CGFloat((value >> 16) & 0xFF) / 255.0,
                blue: CGFloat((value >> 8) & 0xFF) / 255.0,
                alpha: CGFloat(value & 0xFF) / 255.0
            )
        default:
            self.init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        }
    }
}

/// 灵犀 v2 统一设计系统——minimax 风格「极简白」。
/// `DESIGN.md` 是人读说明。
///
/// 色板全部是动态色：亮色为极简白，暗色为同构的「墨玉」层（深底 + 提亮文字）。
/// 键盘扩展不引用本枚举（只用 `KeyboardTheme`），所以暗色映射不会把键盘卡面变黑。
enum Design {
    enum Palette {
        static let canvas = dynamic(light: "#FFFFFF", dark: "#1C1C1E")
        static let canvasTop = dynamic(light: "#FFFFFF", dark: "#1C1C1E")
        static let canvasBottom = dynamic(light: "#FFFFFF", dark: "#1C1C1E")
        static let surface = dynamic(light: "#F7F8FA", dark: "#2C2C2E")
        static let surfaceSoft = dynamic(light: "#F2F3F5", dark: "#242426")
        static let hairline = dynamic(light: "#E5E7EB", dark: "#3A3A3C")
        static let hairlineSoft = dynamic(light: "#EAECF0", dark: "#333335")
        static let ink = dynamic(light: "#0A0A0A", dark: "#F2F2F7")
        static let inkStrong = dynamic(light: "#000000", dark: "#FFFFFF")
        static let charcoal = dynamic(light: "#222222", dark: "#E5E5EA")
        static let slate = dynamic(light: "#45515E", dark: "#C7C7CC")
        static let steel = dynamic(light: "#5F5F5F", dark: "#AEAEB2")
        static let stone = dynamic(light: "#6E6E73", dark: "#98989D")
        static let muted = dynamic(light: "#A8AAB2", dark: "#6C6C70")
        static let success = dynamic(light: "#17976A", dark: "#34C77B")
        static let error = dynamic(light: "#C94A4A", dark: "#FF6B6B")
        static let keyPressed = dynamic(light: "#E5E7EB", dark: "#3A3A3C")

        /// 键盘卡面固定纯白：暗色系统下也保持白键盘（DESIGN.md §8）。
        static let keyboardCanvas = UIColor(hex: "#FFFFFF")

        private static func dynamic(light: String, dark: String) -> UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
            }
        }
    }

    enum Radius {
        static let card: CGFloat = 16
        static let cardSmall: CGFloat = 12
        static let input: CGFloat = 8
        static let full: CGFloat = 9999
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
}
