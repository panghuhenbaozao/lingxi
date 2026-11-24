import Foundation

/// 自定义短语 / 快捷编码词条（兼容 WowType `custom.tsv` 编码<TAB>词 格式）。
struct CustomWordEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var code: String        // 纯字母编码或带空格音节，如 `mail`、`zjtd`、`zi jie tiao dong`
    var word: String        // 目标上屏文本，支持 `\n` 转真换行

    init(id: UUID = UUID(), code: String, word: String) {
        self.id = id
        self.code = code.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.word = word
    }

    var compactCode: String {
        code.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")
    }

    var expandedWord: String {
        word
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }
}

/// 自定义编码词表存储（支持直接作为常用语列表展示与 TSV 导入导出）。
final class CustomWordStore {
    private static let fileName = "lingxi_custom_words.json"
    private static var cached: [CustomWordEntry]?
    private static var cachedMTime: Date?
    private static var lastStatCheckTime: CFAbsoluteTime = 0

    static let defaults: [CustomWordEntry] = [
        CustomWordEntry(code: "mail", word: "hello@example.com"),
        CustomWordEntry(code: "lx", word: "灵犀输入法"),
        CustomWordEntry(code: "dz", word: "请在「词库与设置 -> 自定义编码词」修改为你的收货地址"),
    ]

    static func load(force: Bool = false) -> [CustomWordEntry] {
        let now = CFAbsoluteTimeGetCurrent()
        // 打字热路径 10 秒内纯内存直返，彻底杜绝逐键磁盘 stat 开销
        if !force, let cached, now - lastStatCheckTime < 10.0 {
            return cached
        }
        lastStatCheckTime = now
        let mtime = AppGroup.modificationDate(of: fileName)
        if !force, let cached, cachedMTime == mtime {
            return cached
        }
        let loaded = AppGroup.readJSON([CustomWordEntry].self, from: fileName) ?? defaults
        cached = loaded
        cachedMTime = mtime
        return loaded
    }

    @discardableResult
    static func save(_ entries: [CustomWordEntry]) -> Bool {
        let ok = AppGroup.writeJSON(entries, to: fileName)
        cached = entries
        cachedMTime = AppGroup.modificationDate(of: fileName)
        lastStatCheckTime = CFAbsoluteTimeGetCurrent()
        return ok
    }

    static func add(code: String, word: String) {
        var list = load(force: true)
        let entry = CustomWordEntry(code: code, word: word)
        guard !entry.compactCode.isEmpty, !entry.word.isEmpty else { return }
        list.removeAll { $0.compactCode == entry.compactCode && $0.word == entry.word }
        list.insert(entry, at: 0)
        save(list)
    }

    static func delete(id: UUID) {
        var list = load(force: true)
        list.removeAll { $0.id == id }
        save(list)
    }

    /// 按键入的紧凑字母编码匹配自定义词（精确匹配排最前）。
    static func match(rawInput: String) -> [CustomWordEntry] {
        let q = rawInput.lowercased().replacingOccurrences(of: "'", with: "")
        guard !q.isEmpty else { return [] }
        let all = load()
        var exact: [CustomWordEntry] = []
        var prefix: [CustomWordEntry] = []
        for item in all {
            let c = item.compactCode
            if c == q {
                exact.append(item)
            } else if q.count >= 2 && c.hasPrefix(q) {
                prefix.append(item)
            }
        }
        return exact + prefix
    }

    /// 导入 WowType 风格的 `编码<TAB>词` TSV 文本。
    static func importTSV(_ text: String) -> Int {
        var list = load(force: true)
        var added = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let raw = line.trimmingCharacters(in: .whitespaces)
            if raw.isEmpty || raw.hasPrefix("#") { continue }
            let cols = raw.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 2 else { continue }
            let code = String(cols[0]).lowercased().trimmingCharacters(in: .whitespaces)
            let word = String(cols[1])
            let compact = code.replacingOccurrences(of: " ", with: "")
            guard !compact.isEmpty, compact.allSatisfy({ $0.isASCII && $0.isLetter }), !word.isEmpty else {
                continue
            }
            list.removeAll { $0.compactCode == compact && $0.word == word }
            list.append(CustomWordEntry(code: code, word: word))
            added += 1
        }
        if added > 0 { save(list) }
        return added
    }

    static func exportTSV() -> String {
        let header = "# 编码<TAB>词（可用 \\n 表示换行）\n"
        let body = load(force: true).map { "\($0.code)\t\($0.word)" }.joined(separator: "\n")
        return header + body
    }
}
