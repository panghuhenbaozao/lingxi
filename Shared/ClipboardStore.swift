import Foundation

/// 剪贴板条目分类。
enum ClipboardCategory: String, Codable {
    case text
    case url
    case code
    case phone

    var badgeText: String {
        switch self {
        case .text: return "文本"
        case .url: return "链接"
        case .code: return "验证码"
        case .phone: return "号码"
        }
    }

    var systemIconName: String {
        switch self {
        case .text: return "doc.on.clipboard"
        case .url: return "link"
        case .code: return "number.square"
        case .phone: return "phone"
        }
    }
}

/// 单条剪贴板历史记录。
struct ClipboardItem: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var createdAt: Date
    var isPinned: Bool
    var category: ClipboardCategory
    var extractedCode: String?

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        category: ClipboardCategory? = nil,
        extractedCode: String? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.isPinned = isPinned
        let detectedCode = extractedCode ?? ClipboardClassifier.extractVerificationCode(from: text)
        self.extractedCode = detectedCode
        self.category = category ?? ClipboardClassifier.classify(text, code: detectedCode)
    }
}

/// 剪贴板内容分类与验证码提取工具。
enum ClipboardClassifier {
    private static let cueKeywords = [
        "验证码", "校验码", "动态码", "确认码", "取件码", "激活码", "口令",
        "code", "otp", "pin", "verify", "verification", "passcode"
    ]

    static func classify(_ text: String, code: String? = nil) -> ClipboardCategory {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if code != nil {
            return .code
        }
        if isProbableURL(trimmed) {
            return .url
        }
        if isPhoneOrPureNumber(trimmed) {
            return .phone
        }
        return .text
    }

    static func isProbableURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return true
        }
        if !text.contains(" "), let url = URL(string: text), url.scheme != nil, url.host != nil {
            return true
        }
        return false
    }

    private static func isPhoneOrPureNumber(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        guard compact.count >= 7, compact.count <= 18 else { return false }
        return compact.allSatisfy { $0.isNumber || $0 == "+" }
    }

    /// 从短信/通知中提取 4~8 位数字验证码，避免误匹配年份或价格。
    static func extractVerificationCode(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 300 else { return nil }

        // 纯 4~8 位数字且无小数点
        if (4...8).contains(trimmed.count), trimmed.allSatisfy({ $0.isNumber }) {
            return trimmed
        }

        let lower = trimmed.lowercased()
        guard cueKeywords.contains(where: { lower.contains($0) }) else {
            return nil
        }

        // 优先提取紧邻关键词后的 4~8 位数字或字母数字混合码
        let pattern = #"(?:验证码|校验码|动态码|确认码|取件码|code|otp|pin)[：:\s为是]*([0-9]{4,8})|([0-9]{4,8})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let matches = regex.matches(in: trimmed, range: range)
        for match in matches {
            for groupIndex in 1..<match.numberOfRanges {
                let r = match.range(at: groupIndex)
                if r.location != NSNotFound, let swiftRange = Range(r, in: trimmed) {
                    let candidate = String(trimmed[swiftRange])
                    // 排除明显的年份与过短串
                    if candidate.count == 4, (candidate.hasPrefix("19") || candidate.hasPrefix("20")), groupIndex == 2 {
                        continue
                    }
                    return candidate
                }
            }
        }
        return nil
    }
}

/// App 与 Keyboard 共享的剪贴板历史存储。
final class ClipboardStore {
    private static let fileName = "lingxi_clipboard.json"
    private static let maxUnpinnedCount = 80

    private struct Storage: Codable {
        var items: [ClipboardItem] = []
        var lastHandledChangeCount: Int = -1
    }

    private static var storage: Storage {
        get { AppGroup.readJSON(Storage.self, from: fileName) ?? Storage() }
        set { _ = AppGroup.writeJSON(newValue, to: fileName, protected: true) }
    }

    static func items() -> [ClipboardItem] {
        sortItems(storage.items)
    }

    static func lastHandledChangeCount() -> Int {
        storage.lastHandledChangeCount
    }

    static func markChangeCountHandled(_ count: Int) {
        var st = storage
        st.lastHandledChangeCount = count
        storage = st
    }

    /// 记录一条新的剪贴板内容（自动去重并保留置顶状态）。
    @discardableResult
    static func record(_ rawText: String, changeCount: Int? = nil) -> ClipboardItem? {
        let trimmed = rawText.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return nil }

        var st = storage
        if let count = changeCount {
            st.lastHandledChangeCount = count
        }
        var wasPinned = false
        st.items.removeAll { item in
            if item.text == trimmed {
                wasPinned = wasPinned || item.isPinned
                return true
            }
            return false
        }
        let item = ClipboardItem(text: trimmed, createdAt: Date(), isPinned: wasPinned)
        st.items.insert(item, at: 0)
        st.items = trimUnpinned(sortItems(st.items))
        storage = st
        return item
    }

    static func togglePin(id: UUID) {
        var st = storage
        guard let idx = st.items.firstIndex(where: { $0.id == id }) else { return }
        st.items[idx].isPinned.toggle()
        st.items = sortItems(st.items)
        storage = st
    }

    static func delete(id: UUID) {
        var st = storage
        st.items.removeAll { $0.id == id }
        storage = st
    }

    static func clearUnpinned() {
        var st = storage
        st.items.removeAll { !$0.isPinned }
        storage = st
    }

    private static func sortItems(_ list: [ClipboardItem]) -> [ClipboardItem] {
        list.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func trimUnpinned(_ list: [ClipboardItem]) -> [ClipboardItem] {
        let pinned = list.filter { $0.isPinned }
        let unpinned = Array(list.filter { !$0.isPinned }.prefix(maxUnpinnedCount))
        return pinned + unpinned
    }
}
