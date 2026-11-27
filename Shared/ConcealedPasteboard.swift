import Foundation
import UIKit

/// 敏感内容专用剪贴板写入（保险箱复制使用）：
/// - `localOnly`：不经「通用剪贴板」同步到同一 Apple ID 的其他设备；
/// - `expirationDate`：到期后系统自动清空，避免长期滞留；
/// - 附带 `org.nspasteboard.ConcealedType` 标记：灵犀键盘看到该标记后不入剪贴板历史、不弹顶栏预览。
///
/// 只检查类型属于剪贴板「元数据」访问，不会触发 iOS 的粘贴提示。
enum ConcealedPasteboard {
    /// 业界通用的「隐藏内容」剪贴板类型标记（1Password / Bitwarden 等密码管理器同样使用）。
    static let concealedType = "org.nspasteboard.ConcealedType"
    static let plainTextType = "public.utf8-plain-text"
    static let defaultLifetime: TimeInterval = 90

    /// 纯函数：生成要写入剪贴板的条目（便于单元测试，不触碰系统剪贴板）
    static func makeItem(_ text: String) -> [String: Any] {
        [
            plainTextType: text,
            concealedType: Data(),
        ]
    }

    /// 纯函数：给定剪贴板类型列表，判断是否为保险箱内容
    static func isConcealed(types: [String]) -> Bool {
        types.contains(concealedType)
    }

    static func copy(_ text: String, expiresIn lifetime: TimeInterval = defaultLifetime) {
        UIPasteboard.general.setItems(
            [makeItem(text)],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(max(1, lifetime)),
            ]
        )
    }

    /// 只检查类型、不读取内容，不会触发 iOS 的「允许粘贴」提示。
    static func isConcealed(_ pasteboard: UIPasteboard = .general) -> Bool {
        pasteboard.contains(pasteboardTypes: [concealedType])
    }

    /// 纯函数：校验给定的剪贴板类型与文本是否允许被 AI / 语音 / 快捷排版等非手动粘贴模块读取。
    static func shouldAllowPassiveRead(types: [String], text: String) -> Bool {
        guard !isConcealed(types: types) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !ClipboardClassifier.isSensitiveContent(trimmed)
    }

    /// 安全被动读取剪贴板文本（供 AI 面板、语音面板、顶栏 Dock、格式化等调用）：
    /// 若无完全访问、含保险箱 Concealed 标记或命中 L1 敏感形态（银行卡/身份证/私钥/配对串），统一返回 nil。
    static func readNonSensitiveString(hasFullAccess: Bool, pasteboard: UIPasteboard = .general) -> String? {
        guard hasFullAccess else { return nil }
        guard !isConcealed(pasteboard) else { return nil }
        guard let raw = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              !ClipboardClassifier.isSensitiveContent(raw) else {
            return nil
        }
        return raw
    }

    /// 主 App 用户显式点击「粘贴」按钮时的安全读取：
    /// 屏蔽带 `org.nspasteboard.ConcealedType` 标记的保险箱机密内容，防止误贴进 AI 外部提示词、普通历史或跨屏接力；普通文本正常读取。
    static func readNonConcealedStringForUserPaste(_ pasteboard: UIPasteboard = .general) -> String? {
        guard !isConcealed(pasteboard) else { return nil }
        guard let raw = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }
}
