import NaturalLanguage
import UIKit
import UniformTypeIdentifiers

/// 隐藏于工具栏胶囊内的 `UIPasteControl` 接收目标，可绕过 iOS 16+「允许粘贴」系统弹窗直接拿到剪贴板文本。
final class PasteTargetView: UIView {
    var onPasteText: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        isUserInteractionEnabled = true
        alpha = 0.02
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
        itemProviders.contains {
            $0.canLoadObject(ofClass: NSString.self) ||
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.text.identifier)
        }
    }

    override func paste(itemProviders: [NSItemProvider]) {
        if let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) {
            provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                if let text = (object as? NSString) as String? {
                    DispatchQueue.main.async { self?.onPasteText?(text) }
                }
            }
            return
        }
        guard let provider = itemProviders.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) else {
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] item, _ in
            let text: String?
            if let s = item as? String {
                text = s
            } else if let data = item as? Data {
                text = String(data: data, encoding: .utf8)
            } else {
                text = nil
            }
            if let text {
                DispatchQueue.main.async { self?.onPasteText?(text) }
            }
        }
    }
}

/// 剪贴板「炸词提取 (BigBang)」分词器：基于系统 `NaturalLanguage` 框架，零外部依赖。
enum BigBangTokenizer {
    static func tokenize(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let limited = String(trimmed.prefix(400))

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = limited

        var tokens: [String] = []
        tokenizer.enumerateTokens(in: limited.startIndex..<limited.endIndex) { range, _ in
            let piece = String(limited[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                tokens.append(piece)
            }
            return tokens.count < 48
        }

        if tokens.isEmpty {
            return limited.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        }
        return tokens
    }
}

/// 剪贴板顶部提醒胶囊状态。
enum ClipboardBannerState: Equatable {
    case hidden
    case detectedNewContent(changeCount: Int, isURL: Bool, isNumber: Bool)
    case readyPreview(item: ClipboardItem)
}

/// 剪贴板变更侦测器，兼顾 iOS 16+ 零弹窗体验与智能验证码提取。
final class PasteboardMonitor {
    private(set) var bannerState: ClipboardBannerState = .hidden
    private var dismissedChangeCount: Int = -1

    func refresh(settings: LingxiSettings, onChange: @escaping (ClipboardBannerState) -> Void) {
        guard settings.clipboardBannerEnabled else {
            bannerState = .hidden
            onChange(.hidden)
            return
        }

        let pb = UIPasteboard.general
        let currentCount = pb.changeCount
        guard pb.hasStrings else {
            bannerState = .hidden
            onChange(.hidden)
            return
        }

        if currentCount == dismissedChangeCount || currentCount == ClipboardStore.lastHandledChangeCount() {
            return
        }

        if settings.autoReadClipboardPreview {
            if let text = pb.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let item = ClipboardStore.record(text, changeCount: currentCount) {
                    bannerState = .readyPreview(item: item)
                    onChange(bannerState)
                    return
                }
            }
        }

        let patterns: Set<UIPasteboard.DetectionPattern> = [.probableWebURL, .number, .probableWebSearch]
        pb.detectPatterns(for: patterns) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let matched = (try? result.get()) ?? []
                let state = ClipboardBannerState.detectedNewContent(
                    changeCount: currentCount,
                    isURL: matched.contains(.probableWebURL),
                    isNumber: matched.contains(.number)
                )
                self.bannerState = state
                onChange(state)
            }
        }
    }

    func handleCapturedPaste(_ text: String, settings: LingxiSettings) -> (item: ClipboardItem?, shouldOfferOTPChoice: Bool) {
        let count = UIPasteboard.general.changeCount
        let item = ClipboardStore.record(text, changeCount: count)
        if let item, settings.smartOTPExtraction, let code = item.extractedCode, item.text.count > code.count + 4 {
            bannerState = .readyPreview(item: item)
            return (item, true)
        }
        dismissedChangeCount = count
        bannerState = .hidden
        return (item, false)
    }

    func dismissCurrent() {
        switch bannerState {
        case .detectedNewContent(let count, _, _):
            dismissedChangeCount = count
            ClipboardStore.markChangeCountHandled(count)
        case .readyPreview:
            dismissedChangeCount = UIPasteboard.general.changeCount
            ClipboardStore.markChangeCountHandled(dismissedChangeCount)
        case .hidden:
            break
        }
        bannerState = .hidden
    }
}
