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

    /// L1 隐私防线：检测剪贴板敏感形态（18位身份证号、16-19位Luhn银行卡号、私钥或显式密码串）。
    /// 命中时自动屏蔽，不进键盘顶栏横幅、不落本地剪贴板历史。
    static func isSensitiveContent(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(SideloadConfigBridge.tokenPrefix) { return true }
        guard !trimmed.isEmpty else { return false }

        // 1. 私钥或 PEM 块
        if trimmed.contains("-----BEGIN ") && trimmed.contains("PRIVATE KEY-----") {
            return true
        }

        // 2. 18 位中国居民身份证号（含出生年月与末位 0-9/X 校验）
        let idPattern = #"(?<![0-9])[1-9][0-9]{5}(?:19|20)[0-9]{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])[0-9]{3}[0-9Xx](?![0-9])"#
        if trimmed.range(of: idPattern, options: .regularExpression) != nil {
            return true
        }

        // 3. 16~19 位银行卡号（纯数字或空格/连字符分隔，且通过 Luhn 模 10 校验）
        let compactDigits = trimmed.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if (16...19).contains(compactDigits.count), compactDigits.allSatisfy(\.isNumber), passesLuhnCheck(compactDigits) {
            return true
        }

        // 4. 显式密码键值对（排除含"验证码"的正常短信）
        let lower = trimmed.lowercased()
        let isOTP = cueKeywords.contains { lower.contains($0) }
        if !isOTP {
            let pwPattern = #"(?:密码|登录密码|支付密码|password|passwd|pwd|secret_key)\s*[：:=is为]\s*\S{6,}"#
            if trimmed.range(of: pwPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }

        return false
    }

    private static func passesLuhnCheck(_ digits: String) -> Bool {
        var sum = 0
        let reversed = digits.reversed().compactMap { Int(String($0)) }
        guard reversed.count == digits.count else { return false }
        for (idx, d) in reversed.enumerated() {
            if idx % 2 == 1 {
                let doubled = d * 2
                sum += doubled > 9 ? (doubled - 9) : doubled
            } else {
                sum += d
            }
        }
        return sum > 0 && sum % 10 == 0
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
        var pendingBannerItemID: UUID? = nil
    }

    private static var storage: Storage {
        get { AppGroup.readJSON(Storage.self, from: fileName) ?? Storage() }
        set { _ = AppGroup.writeJSON(newValue, to: fileName, protected: true) }
    }

    static func items() -> [ClipboardItem] {
        sortItems(storage.items)
    }

    /// 返回尚未在键盘顶栏粘贴或关闭的最新待展示剪贴板/跨屏接力条目
    static func pendingBannerItem() -> ClipboardItem? {
        let st = storage
        guard let pid = st.pendingBannerItemID else { return nil }
        return st.items.first(where: { $0.id == pid })
    }

    static func clearPendingBanner(changeCount: Int? = nil) {
        var st = storage
        st.pendingBannerItemID = nil
        if let count = changeCount, count >= 0 {
            st.lastHandledChangeCount = count
        }
        storage = st
    }

    static func lastHandledChangeCount() -> Int {
        storage.lastHandledChangeCount
    }

    static func markChangeCountHandled(_ count: Int) {
        var st = storage
        st.lastHandledChangeCount = count
        st.pendingBannerItemID = nil
        storage = st
    }

    /// 记录一条新的剪贴板内容（自动去重并保留置顶状态；若命中 L1 敏感证件号/银行卡/密码规则则自动屏蔽）。
    @discardableResult
    static func record(_ rawText: String, changeCount: Int? = nil) -> ClipboardItem? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !ClipboardClassifier.isSensitiveContent(trimmed) else {
            if let count = changeCount {
                markChangeCountHandled(count)
            }
            return nil
        }

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
        // 若未显式标记为已消费，设为待顶栏全栏接管展示条目
        if changeCount == nil {
            st.pendingBannerItemID = item.id
        }
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
        if st.pendingBannerItemID == id {
            st.pendingBannerItemID = nil
        }
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
