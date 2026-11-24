import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 截屏 AI 识图快捷模式（主 App 截屏工作台与键盘内嵌 AI 共用）。
enum ScreenshotVisionPreset: String, CaseIterable, Identifiable {
    case smartReply
    case extractText
    case translateZh
    case summarize
    case explainSolve

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartReply: return "💬 看图回复"
        case .extractText: return "📝 提取文字"
        case .translateZh: return "🌐 截屏译中"
        case .summarize: return "🔍 总结重点"
        case .explainSolve: return "💡 解答分析"
        }
    }

    var promptText: String {
        switch self {
        case .smartReply:
            return "请仔细看这张聊天或社交截图的完整上下文，帮我写一句自然、高情商、像真人聊天的中文回复，直接可发微信。"
        case .extractText:
            return "请准确完整地提取这张截图中的全部文字内容，保持原本逻辑和段落顺序，不要遗漏数字、时间、金额或链接。"
        case .translateZh:
            return "请识别这张截图中的所有外文内容，并准确翻译成自然地道的简体中文。"
        case .summarize:
            return "请快速读取这张截图，用简洁明了的要点总结最核心的信息和需要做的事情。"
        case .explainSolve:
            return "请分析这张截图中的问题、界面提示或内容，给出清晰直接的解答或具体操作建议。"
        }
    }

    var systemInstruction: String {
        switch self {
        case .smartReply:
            return "你是高情商视觉聊天助手。结合截图中对方最后发的话与语境，直接给出最合适的一条回复，不要分析过程。"
        case .extractText:
            return "你是高精度 OCR 文字提取专家。只输出提取并排版干净的文字正文，不要寒暄或多余说明。"
        case .translateZh:
            return "你是精通多语种的视觉翻译专家。只直接输出准确流畅的简体中文译文，不要多余解释。"
        case .summarize:
            return "你是信息提炼专家。用短句和「1.」「2.」提炼截屏核心要点，干净利落，适合直接分享。"
        case .explainSolve:
            return "你是全能视觉顾问。直接针对截图给出明确结论和实用步骤，简洁易懂。"
        }
    }
}

#if canImport(UIKit)
enum ScreenshotImageHelper {
    /// 将截屏等比缩放到 768px 轻量高清晰度并压缩为 JPEG（~60-110KB），
    /// 在键盘扩展 50MB 严格内存红线下彻底杜绝 Jetsam 闪退与大图卡顿。
    static func prepareJPEGData(from image: UIImage, maxDimension: CGFloat = 768, quality: CGFloat = 0.68) -> Data? {
        autoreleasepool {
            let size = image.size
            guard size.width > 1, size.height > 1 else { return nil }
            let longest = max(size.width, size.height)
            let targetImage: UIImage
            if longest > maxDimension {
                let scale = maxDimension / longest
                let newSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = 1.0
                let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
                targetImage = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
            } else {
                targetImage = image
            }
            return targetImage.jpegData(compressionQuality: quality)
        }
    }
}
#endif
