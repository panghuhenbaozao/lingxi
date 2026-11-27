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

/// 剪贴板顶部提醒胶囊状态。
enum ClipboardBannerState: Equatable {
    case hidden
    case detectedNewContent(changeCount: Int, isURL: Bool, isNumber: Bool)
    case readyPreview(item: ClipboardItem)
}

/// 剪贴板变更侦测器，兼顾 iOS 16+ 零弹窗体验、跨屏剪贴板接力与智能验证码提取。
/// 当用户新复制内容、跨设备秒传或收到验证码时，顶栏自动切换为全宽剪贴板/验证码智能胶囊；
/// 用户点击粘贴或关闭后，才标记当前 changeCount 与 pendingBannerItem 已处理并恢复常规顶栏。
final class PasteboardMonitor {
    private(set) var bannerState: ClipboardBannerState = .hidden
    private var dismissedChangeCount: Int = -1
    private var activeChangeCount: Int = -1
    private var lastCheckedAt: CFTimeInterval = 0
    private var lastObservedChangeCount: Int = -1

    func refresh(
        settings: LingxiSettings,
        force: Bool = false,
        allowProactiveStringRead: Bool = false,
        onChange: @escaping (ClipboardBannerState) -> Void
    ) {
        guard settings.clipboardBannerEnabled && !settings.incognitoModeEnabled else {
            if bannerState != .hidden {
                bannerState = .hidden
                onChange(.hidden)
            }
            return
        }

        let now = CACurrentMediaTime()
        if !force, now - lastCheckedAt < 1.2 {
            return
        }
        lastCheckedAt = now

        let pb = UIPasteboard.general
        let currentCount = pb.changeCount

        // 快速通路：changeCount 未变动且已有明确状态时，跳过重复的跨进程 hasStrings 与磁盘 JSON 解码
        if !force && currentCount == lastObservedChangeCount {
            if currentCount == dismissedChangeCount && bannerState == .hidden {
                return
            }
            if currentCount == activeChangeCount && bannerState != .hidden {
                return
            }
        }
        lastObservedChangeCount = currentCount

        // 1. 若系统剪贴板无字符串，检查是否有跨屏剪贴板接力或主 App 刚写入的待展示条目
        guard pb.hasStrings else {
            if let pending = ClipboardStore.pendingBannerItem() {
                bannerState = .readyPreview(item: pending)
                onChange(bannerState)
            } else {
                bannerState = .hidden
                onChange(.hidden)
            }
            return
        }

        // 1.5 保险箱复制的敏感内容带有 Concealed 标记：不入历史、不弹预览（只检查类型，不读取内容）
        if ConcealedPasteboard.isConcealed(pb) {
            dismissedChangeCount = currentCount
            ClipboardStore.markChangeCountHandled(currentCount)
            if bannerState != .hidden {
                bannerState = .hidden
                onChange(.hidden)
            }
            return
        }

        // 2. 若当前系统 changeCount 已消费，仍检查是否有跨设备秒传的新待展示条目
        if currentCount == dismissedChangeCount || currentCount == ClipboardStore.lastHandledChangeCount() {
            if let pending = ClipboardStore.pendingBannerItem() {
                bannerState = .readyPreview(item: pending)
                onChange(bannerState)
                return
            }
            if bannerState != .hidden {
                bannerState = .hidden
                onChange(.hidden)
            }
            return
        }

        // 3. 若当前 changeCount 已经处于预览展示态，保持显示不重复重入
        if currentCount == activeChangeCount, bannerState != .hidden {
            onChange(bannerState)
            return
        }

        // 3.5 若 App Group / 跨屏接力已有待展示条目，直接展示零弹窗预览
        if let pending = ClipboardStore.pendingBannerItem() {
            activeChangeCount = currentCount
            bannerState = .readyPreview(item: pending)
            onChange(bannerState)
            return
        }

        // 4. 仅在明确允许主动读取时才读取 pb.string；键盘冷启动/唤起默认走 Apple 零弹窗 detectPatterns + UIPasteControl，
        // 彻底杜绝 iOS 16+ 每次打开键盘弹出「允许粘贴」系统弹窗阻塞焦点！
        if allowProactiveStringRead && (settings.autoReadClipboardPreview || settings.smartOTPExtraction) {
            if let text = pb.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // L1 安全防线：若剪贴板为身份证号、银行卡号、私钥或显式密码，立即屏蔽并跳过横幅提示
                if ClipboardClassifier.isSensitiveContent(text) {
                    dismissedChangeCount = currentCount
                    ClipboardStore.markChangeCountHandled(currentCount)
                    bannerState = .hidden
                    onChange(.hidden)
                    return
                }
                if let item = ClipboardStore.record(text, changeCount: nil) {
                    activeChangeCount = currentCount
                    bannerState = .readyPreview(item: item)
                    onChange(bannerState)
                    return
                }
            }
        }

        let patterns: Set<UIPasteboard.DetectionPattern> = [.probableWebURL, .number, .probableWebSearch]
        pb.detectPatterns(for: patterns) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      currentCount == self.lastObservedChangeCount,
                      currentCount != self.dismissedChangeCount else { return }
                let matched = (try? result.get()) ?? []
                self.activeChangeCount = currentCount
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
        // 隐身无痕模式或保险箱内容：照常粘贴，但绝不写入剪贴板历史
        if settings.incognitoModeEnabled || ConcealedPasteboard.isConcealed() {
            dismissCurrent()
            return (nil, false)
        }
        let item = ClipboardStore.record(text, changeCount: nil)
        if let item, settings.smartOTPExtraction, let code = item.extractedCode, item.text.count > code.count + 4 {
            activeChangeCount = count
            bannerState = .readyPreview(item: item)
            return (item, true)
        }
        dismissCurrent()
        return (item, false)
    }

    func dismissCurrent() {
        let countToMark: Int
        switch bannerState {
        case .detectedNewContent(let count, _, _):
            countToMark = count
        case .readyPreview:
            countToMark = activeChangeCount >= 0 ? activeChangeCount : UIPasteboard.general.changeCount
        case .hidden:
            countToMark = activeChangeCount
        }
        if countToMark >= 0 {
            dismissedChangeCount = countToMark
            ClipboardStore.markChangeCountHandled(countToMark)
        } else {
            ClipboardStore.clearPendingBanner()
        }
        activeChangeCount = -1
        bannerState = .hidden
    }
}
