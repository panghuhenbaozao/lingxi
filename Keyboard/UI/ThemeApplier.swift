import ImageIO
import UIKit

extension UIColor {
    convenience init(hexColor: HexColor, alphaMultiplier: CGFloat = 1.0) {
        let c = hexColor.rgba
        self.init(
            red: CGFloat(c.r),
            green: CGFloat(c.g),
            blue: CGFloat(c.b),
            alpha: CGFloat(c.a) * alphaMultiplier
        )
    }
}

/// 解析后的 UIKit 渲染主题，避免在每次按键绘制时反复解析 Hex 与解码大图。
struct ResolvedTheme {
    let preset: KeyboardThemePreset
    let customization: ThemeCustomization
    let canvasTop: UIColor
    let canvasBottom: UIColor
    let toolbarBg: UIColor
    let keyFill: UIColor
    let keyPressedFill: UIColor
    let specialKeyFill: UIColor
    let specialKeyPressedFill: UIColor
    let accentFill: UIColor
    let accentPressedFill: UIColor
    let keyText: UIColor
    let keyHintText: UIColor
    let accentText: UIColor
    let candidateText: UIColor
    let candidateHighlight: UIColor
    let keyShadowColor: UIColor
    let keyShadowOpacity: Float
    let keyCornerRadius: CGFloat
    let boldKeyLabel: Bool
    let customBackgroundImage: UIImage?

    /// 顶栏胶囊与分割线细描边色（亮色模式取柔和边框色，暗色模式取微透高亮边框色）
    var keyBorder: UIColor {
        preset.isDark
            ? UIColor.white.withAlphaComponent(0.16)
            : keyShadowColor.withAlphaComponent(0.85)
    }

    static func resolve(
        customization: ThemeCustomization = ThemeCustomization.load(),
        isDarkAppearance: Bool,
        targetSize: CGSize
    ) -> ResolvedTheme {
        let preset = customization.activePreset(isSystemDark: isDarkAppearance)
        let hasCustomBg = customization.customBackgroundURL != nil
        let keyAlpha = CGFloat(hasCustomBg ? min(1.0, max(0.35, customization.keyOpacity)) : 1.0)
        let bgImage = customization.customBackgroundURL.flatMap {
            loadDownsampledImage(at: $0, targetPointSize: targetSize)
        }

        return ResolvedTheme(
            preset: preset,
            customization: customization,
            canvasTop: UIColor(hexColor: preset.canvasTop),
            canvasBottom: UIColor(hexColor: preset.canvasBottom),
            toolbarBg: UIColor(hexColor: preset.toolbarBackground, alphaMultiplier: hasCustomBg ? 0.85 : 1.0),
            keyFill: UIColor(hexColor: preset.keyFill, alphaMultiplier: keyAlpha),
            keyPressedFill: UIColor(hexColor: preset.keyPressedFill, alphaMultiplier: min(1.0, keyAlpha + 0.08)),
            specialKeyFill: UIColor(hexColor: preset.specialKeyFill, alphaMultiplier: keyAlpha),
            specialKeyPressedFill: UIColor(hexColor: preset.specialKeyPressedFill, alphaMultiplier: min(1.0, keyAlpha + 0.08)),
            accentFill: UIColor(hexColor: preset.accentFill),
            accentPressedFill: UIColor(hexColor: preset.accentPressedFill),
            keyText: UIColor(hexColor: preset.keyText),
            keyHintText: UIColor(hexColor: preset.keyHintText),
            accentText: UIColor(hexColor: preset.accentText),
            candidateText: UIColor(hexColor: preset.candidateText),
            candidateHighlight: UIColor(hexColor: preset.candidateHighlight),
            keyShadowColor: UIColor(hexColor: preset.keyShadowHex),
            keyShadowOpacity: Float(preset.keyShadowOpacity),
            keyCornerRadius: CGFloat(customization.keyCornerRadius),
            boldKeyLabel: customization.boldKeyLabel,
            customBackgroundImage: bgImage
        )
    }

    /// 按键盘实际尺寸进行 ImageIO 降采样，将内存控制在 ~1.5MB 以内，防止 Jetsam 杀掉键盘扩展。
    private static func loadDownsampledImage(at url: URL, targetPointSize: CGSize) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }
        let maxDim = max(max(targetPointSize.width, targetPointSize.height) * 2.0, 720.0)
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// 键盘底板背景渲染视图（支持主题双色渐变、自定义图片 + 毛玻璃 + 暗化遮罩）。
final class KeyboardBackdropView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let imageView = UIImageView()
    private let blurView = UIVisualEffectView(effect: nil)
    private let dimView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(gradientLayer)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)

        addSubview(blurView)
        addSubview(dimView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        imageView.frame = bounds
        blurView.frame = bounds
        dimView.frame = bounds
    }

    func apply(theme: ResolvedTheme) {
        gradientLayer.colors = [theme.canvasTop.cgColor, theme.canvasBottom.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)

        if let img = theme.customBackgroundImage {
            imageView.image = img
            imageView.isHidden = false
            let useBlur = theme.customization.backgroundBlurRadius > 1.0
            blurView.isHidden = !useBlur
            if useBlur {
                let style: UIBlurEffect.Style = theme.preset.isDark ? .systemMaterialDark : .systemMaterialLight
                blurView.effect = UIBlurEffect(style: style)
                blurView.alpha = CGFloat(min(1.0, theme.customization.backgroundBlurRadius / 24.0))
            }
            dimView.isHidden = false
            dimView.backgroundColor = (theme.preset.isDark ? UIColor.black : UIColor.white)
                .withAlphaComponent(CGFloat(theme.customization.backgroundDimOpacity))
        } else {
            imageView.image = nil
            imageView.isHidden = true
            blurView.isHidden = true
            dimView.isHidden = true
        }
    }
}
