import Foundation

/// App Group 共享的最近使用 Emoji 存储（对齐 WowType `recent_emoji.rs`）：
/// - 面板与宿主 App 共享最近使用的 24 个表情；
/// - 当某个中文词关联多个推荐表情（如「哈哈」-> `["😄", "😂"]`）时，优先将用户近期常用的表情排在前面。
enum RecentEmojiStore {
    private static let fileName = "lingxi_recent_emojis.json"
    private static let maxCount = 24

    static func load() -> [String] {
        AppGroup.readJSON([String].self, from: fileName) ?? []
    }

    static func record(_ emoji: String) {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = load()
        list.removeAll { $0 == trimmed }
        list.insert(trimmed, at: 0)
        if list.count > maxCount {
            list = Array(list.prefix(maxCount))
        }
        _ = AppGroup.writeJSON(list, to: fileName)
    }

    /// 按用户最近使用顺序对候选 Emoji 列表重排（最近用过的排最前，未用过的保持原序）。
    static func prioritize(_ emojis: [String]) -> [String] {
        guard emojis.count > 1 else { return emojis }
        let recent = load()
        guard !recent.isEmpty else { return emojis }
        return emojis.sorted { lhs, rhs in
            let lIdx = recent.firstIndex(of: lhs) ?? Int.max
            let rIdx = recent.firstIndex(of: rhs) ?? Int.max
            if lIdx != rIdx { return lIdx < rIdx }
            return (emojis.firstIndex(of: lhs) ?? 0) < (emojis.firstIndex(of: rhs) ?? 0)
        }
    }
}
