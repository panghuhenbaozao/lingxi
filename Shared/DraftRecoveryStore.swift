import Foundation

/// 本地防丢草稿记录（仅存本机，24 小时自动销毁，永不上云）
public struct SavedDraftRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public let createdAt: Date
    public var updatedAt: Date

    public var charCount: Int { text.count }

    public var singleLinePreview: String {
        text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 0ms 纯本机「🛟 草稿防丢黑匣子」存储引擎。
/// 专治手机打了一大段字（微信长回复、小红书/知乎评论、网页投诉表单），切 App 被杀后台或网页刷新瞬间清空的痛点。
/// 隐私铁律：
/// 1. 密码框（isSecureField）、无痕模式（incognitoModeEnabled）与关闭开关时绝对不记录；
/// 2. 自动跳过 L1 敏感内容（银行卡、身份证、私钥、验证码等）；
/// 3. 默认仅缓存 ≥ 18 字的长草稿，最多保留 15 条，超过 24 小时自动物理清理，永不参与云同步。
public enum DraftRecoveryStore {
    public static let maxItems = 15
    public static let minCaptureLength = 18
    public static let maxDraftChars = 4000
    public static let retentionInterval: TimeInterval = 24 * 3600
    private static let fileName = "draft_recovery_blackbox.json"
    private static let lock = NSLock()

    /// 纯函数：判断当前输入草稿是否符合防丢黑匣子隐私采集标准
    public static func shouldCapture(
        _ rawText: String,
        isSecureField: Bool,
        isIncognito: Bool,
        enabled: Bool
    ) -> Bool {
        guard enabled, !isSecureField, !isIncognito else { return false }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minCaptureLength else { return false }
        guard !ClipboardClassifier.isSensitiveContent(trimmed) else { return false }
        return true
    }

    /// 纯函数：过滤过期条目与超限条目（便于单元测试）
    public static func prune(
        _ items: [SavedDraftRecord],
        now: Date = Date(),
        ttl: TimeInterval = retentionInterval,
        limit: Int = maxItems
    ) -> [SavedDraftRecord] {
        let cutoff = now.addingTimeInterval(-ttl)
        let valid = items
            .filter { $0.updatedAt >= cutoff && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
        return Array(valid.prefix(limit))
    }

    /// 纯函数：向草稿队列合并记录（同一段正在续写的长草稿在 12 分钟内原地覆盖更新，不产生碎片重复）
    public static func merge(
        draft rawText: String,
        into existing: [SavedDraftRecord],
        now: Date = Date()
    ) -> [SavedDraftRecord] {
        let trimmed = String(rawText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxDraftChars))
        guard trimmed.count >= minCaptureLength else { return prune(existing, now: now) }

        var list = prune(existing, now: now)

        // 如果与最近一条相同，直接更新时间
        if let first = list.first, first.text == trimmed {
            list[0].updatedAt = now
            return list
        }

        // 如果 12 分钟内正在续写同一段（新旧互为前缀或有显著重合前缀 ≥ 12 字），原地更新该草稿
        if let first = list.first, now.timeIntervalSince(first.updatedAt) <= 12 * 60 {
            let sharedPrefixLen = commonPrefixCount(first.text, trimmed)
            if sharedPrefixLen >= 12 || trimmed.contains(first.text) || first.text.contains(trimmed) {
                // 优先保留内容更完整的版本；若用户大幅修改过则更新为新版本
                if trimmed.count >= first.text.count || sharedPrefixLen >= 16 {
                    list[0].text = trimmed
                    list[0].updatedAt = now
                    return list
                }
            }
        }

        // 去重历史完全一致记录
        list.removeAll { $0.text == trimmed }
        list.insert(SavedDraftRecord(text: trimmed, createdAt: now, updatedAt: now), at: 0)
        return Array(list.prefix(maxItems))
    }

    public static func load(now: Date = Date()) -> [SavedDraftRecord] {
        lock.lock()
        defer { lock.unlock() }
        let raw = readRawUnsafe()
        let cleaned = prune(raw, now: now)
        if cleaned.count != raw.count {
            writeRawUnsafe(cleaned)
        }
        return cleaned
    }

    @discardableResult
    public static func record(
        _ rawText: String,
        isSecureField: Bool,
        isIncognito: Bool,
        enabled: Bool,
        now: Date = Date()
    ) -> Bool {
        guard shouldCapture(rawText, isSecureField: isSecureField, isIncognito: isIncognito, enabled: enabled) else {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        let updated = merge(draft: rawText, into: readRawUnsafe(), now: now)
        writeRawUnsafe(updated)
        return true
    }

    public static func delete(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var list = readRawUnsafe()
        list.removeAll { $0.id == id }
        writeRawUnsafe(list)
    }

    public static func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        writeRawUnsafe([])
    }

    // MARK: - Private Storage

    private static func readRawUnsafe() -> [SavedDraftRecord] {
        AppGroup.readJSON([SavedDraftRecord].self, from: fileName) ?? []
    }

    private static func writeRawUnsafe(_ items: [SavedDraftRecord]) {
        _ = AppGroup.writeJSON(items, to: fileName, protected: true)
    }

    private static func commonPrefixCount(_ a: String, _ b: String) -> Int {
        var count = 0
        for (ca, cb) in zip(a, b) {
            if ca == cb { count += 1 } else { break }
        }
        return count
    }
}
