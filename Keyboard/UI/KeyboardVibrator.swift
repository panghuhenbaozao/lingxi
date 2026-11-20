import UIKit

/// 键盘动态震动：触摸反馈、上屏、删除、方向、空格跟踪器滑动动态敲击。
/// 尊重用户「按键震动」设置（hapticStrength），关闭时全部静默；系统级振动开关由 iOS 兜底。
final class KeyboardVibrator {
    static let shared = KeyboardVibrator()

    private lazy var selectionGenerator = UISelectionFeedbackGenerator()
    private lazy var notificationGenerator = UINotificationFeedbackGenerator()
    private lazy var heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)

    /// 用户「按键震动」开关缓存：LingxiSettings.load() 内部按文件 mtime 缓存，
    /// 这里再做 0.4s 节流，避免每次按键都触发文件 stat。
    /// 修复此前完全绕过设置、用户关闭震动后按键仍会震动的缺陷。
    private var cachedHapticsEnabled = true
    private var lastSettingsCheck: CFTimeInterval = 0

    private var hapticsEnabled: Bool {
        let now = CACurrentMediaTime()
        if now - lastSettingsCheck > 0.4 {
            lastSettingsCheck = now
            cachedHapticsEnabled = LingxiSettings.load().hapticStrength != .off
        }
        return cachedHapticsEnabled
    }

    /// 普通按压：普通选择级
    func lightTap() {
        guard hapticsEnabled else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// 上屏 / 语言切换 / 方向：中等通知级
    func mediumTap() {
        guard hapticsEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    /// 退格：重删级
    func heavyTap() {
        guard hapticsEnabled else { return }
        heavyGenerator.impactOccurred()
        heavyGenerator.prepare()
    }

    /// 空格触控板滑动：轻选择级
    func softTap() {
        guard hapticsEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    /// 空格跟踪器动态敲击：每一步滑动都有快速感知（选择级 + 预热）
    func spaceTick() {
        guard hapticsEnabled else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// 候选词高亮移动/选中：轻选择级
    func candidateTick() {
        guard hapticsEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    private init() {}
}
