import Foundation

/// 输入稳定性守护器（纯逻辑，零 UIKit 依赖，可供主 App / 键盘扩展 / 单元测试直接复用）：
/// 解决微信/QQ/抖音/小红书等宿主 App 在用户点击「发送」后异步清空输入框并回调 `textDidChange`
/// 导致刚敲下的下一句拼音被误清空（莫名吞字），以及英文前缀替换误删已发送内容等问题。
public enum InputStabilityGuard {
    /// 键盘自身调用 `insertText` / `deleteBackward` / `setMarkedText` 后，宿主回声 `textDidChange` 的保护窗（秒）。
    public static let internalEditEchoWindow: TimeInterval = 0.45
    /// 用户正在连续按键输入时的防误清保护窗（秒）。
    public static let activeTypingGraceWindow: TimeInterval = 2.0
    /// 用户点击「发送 / 回车」后，宿主执行发送动画与清空输入框的异步保护窗（秒）。
    public static let postReturnGraceWindow: TimeInterval = 1.5

    /// 判断 `textDidChange(_:)` 回调时是否应当清空当前中文/双拼/九键/五笔组合缓冲（`rawComposing`）。
    ///
    /// 核心原则：
    /// 1. 仅当用户真正切换到**另一个不同类型的输入框**（`hostFieldChanged == true`）时立即清空；
    /// 2. 刚刚发生过内部编辑、刚刚按键、或刚刚点击「发送」后，宿主异步回传的 `textDidChange` **绝对禁止清空**正在输入的新字；
    /// 3. 默认关闭「输入框内嵌拼音」（`hasActiveMarkedText == false`）时，`rawComposing` 仅存在于键盘本地缓冲，
    ///    与宿主输入框文本完全独立——同一输入框内收到新聊天气泡或发送清空回执时，绝不抹除用户键盘里未上屏的拼音！
    public static func shouldClearComposingOnTextDidChange(
        hasRawComposing: Bool,
        hasEnglishComposing: Bool,
        hasActiveMarkedText: Bool,
        hostFieldChanged: Bool,
        secondsSinceLastInternalEdit: TimeInterval,
        secondsSinceLastKeystroke: TimeInterval,
        secondsSinceLastReturn: TimeInterval
    ) -> Bool {
        if hostFieldChanged {
            return hasRawComposing || hasEnglishComposing || hasActiveMarkedText
        }
        if secondsSinceLastInternalEdit < internalEditEchoWindow {
            return false
        }
        if secondsSinceLastKeystroke < activeTypingGraceWindow {
            return false
        }
        if secondsSinceLastReturn < postReturnGraceWindow {
            return false
        }
        // 本地拼音缓冲（未写入宿主 markedText）绝不因同一输入框的异步 textDidChange 被吞掉
        if hasRawComposing && !hasActiveMarkedText {
            return false
        }
        return hasActiveMarkedText || hasEnglishComposing
    }

    /// 独立判断英文直接上屏模式下的 `englishComposing` 是否已与宿主输入框失同步（需要清理，防止后续点候选误删）。
    public static func shouldClearEnglishComposingOnTextDidChange(
        englishComposing: String,
        documentBeforeInput: String?,
        hostFieldChanged: Bool,
        secondsSinceLastInternalEdit: TimeInterval,
        secondsSinceLastKeystroke: TimeInterval,
        secondsSinceLastReturn: TimeInterval
    ) -> Bool {
        guard !englishComposing.isEmpty else { return false }
        if hostFieldChanged { return true }
        if secondsSinceLastInternalEdit < internalEditEchoWindow { return false }
        if secondsSinceLastReturn < postReturnGraceWindow && secondsSinceLastKeystroke < activeTypingGraceWindow {
            return false
        }
        let before = (documentBeforeInput ?? "").lowercased()
        if before.hasSuffix(englishComposing.lowercased()) {
            return false
        }
        return secondsSinceLastKeystroke >= 0.65
    }

    /// 计算英文点选候选词替换前缀时的安全退格次数：
    /// 必须确认宿主光标前文本确实以待替换前缀结尾，否则返回 0，杜绝发送清空后误删其他字符。
    public static func safeEnglishReplacementDeleteLength(
        expectedPrefix: String,
        documentBeforeInput: String?
    ) -> Int {
        guard !expectedPrefix.isEmpty else { return 0 }
        guard let before = documentBeforeInput, !before.isEmpty else { return 0 }
        if before.lowercased().hasSuffix(expectedPrefix.lowercased()) {
            return expectedPrefix.count
        }
        return 0
    }

    /// 判断 `textDidChange(_:)` 回调时是否应当刷新闲置候选联想，避免刚打完/刚发送瞬间闪烁或干扰状态。
    public static func shouldRefreshIdleSuggestionsOnTextDidChange(
        hasRawComposing: Bool,
        hasEnglishComposing: Bool,
        hostFieldChanged: Bool,
        secondsSinceLastInternalEdit: TimeInterval,
        secondsSinceLastKeystroke: TimeInterval,
        secondsSinceLastReturn: TimeInterval
    ) -> Bool {
        guard !hasRawComposing && !hasEnglishComposing else { return false }
        if hostFieldChanged { return true }
        return secondsSinceLastInternalEdit >= internalEditEchoWindow
            && secondsSinceLastKeystroke >= 0.50
            && secondsSinceLastReturn >= 0.80
    }
}
