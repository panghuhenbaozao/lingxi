import SwiftUI
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
        static let canvas = dynamic(light: "#FFFFFF", dark: "#161618")
        static let canvasTop = dynamic(light: "#FFFFFF", dark: "#161618")
        static let canvasBottom = dynamic(light: "#FFFFFF", dark: "#161618")
        static let surface = dynamic(light: "#F4F5F7", dark: "#222226")
        static let surfaceSoft = dynamic(light: "#ECEEF2", dark: "#1D1D21")
        static let hairline = dynamic(light: "#E8EAEE", dark: "#2C2C31")
        static let hairlineSoft = dynamic(light: "#F0F1F4", dark: "#252529")
        static let ink = dynamic(light: "#111214", dark: "#F5F5F7")
        static let inkStrong = dynamic(light: "#000000", dark: "#FFFFFF")
        static let charcoal = dynamic(light: "#1F2328", dark: "#E5E5EA")
        static let slate = dynamic(light: "#4B5563", dark: "#C7C7CC")
        static let steel = dynamic(light: "#5F6672", dark: "#AEAEB2")
        static let stone = dynamic(light: "#6B7280", dark: "#9A9AA3")
        static let muted = dynamic(light: "#9CA3AF", dark: "#63636B")
        static let success = dynamic(light: "#15803D", dark: "#34D399")
        static let error = dynamic(light: "#DC2626", dark: "#F87171")
        static let warning = dynamic(light: "#D97706", dark: "#FBBF24")
        static let accent = dynamic(light: "#2F5BFF", dark: "#5B82FF")
        static let accentSoft = dynamic(light: "#EEF2FF", dark: "#1A2444")
        static let accentText = UIColor(hex: "#FFFFFF")
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
        static let card: CGFloat = 18
        static let cardSmall: CGFloat = 12
        static let input: CGFloat = 10
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

    enum Typography {
        enum SwiftUIFont {
            static let h3 = Font.system(size: 15, weight: .semibold)
            static let body = Font.system(size: 13.5, weight: .regular)
            static let label = Font.system(size: 12.5, weight: .semibold)
            static let caption = Font.system(size: 11.5, weight: .regular)
        }
    }
}
