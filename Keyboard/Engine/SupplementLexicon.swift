import Foundation

/// 轻量全字库与现代热词补充包加载器（读取 `supplement_lexicon.tsv`，体积仅 ~137KB）：
/// - 补齐 Unicode BMP (`U+4E00..U+9FFF`) 全部 20,900+ 汉字（含生僻人名、姓氏、古籍、方言、港台异体字与多音字读音）
/// - 补齐日常高频口语热词与四字成语，支持全拼、7 种双拼、简拼与 T9 九宫格无死角检索
final class SupplementLexicon {
    struct PhraseItem {
        let word: String
        let py: String
        let lp: Double
    }

    static let shared = SupplementLexicon()

    private let lock = NSLock()
    private var isLoaded = false
    private var loadedFromURL: URL?

    /// 拼音音节 -> 按常用度排序的扩展单字紧凑字符串（如 `"jian" -> "幵戋..."`, `"da" -> "龘..."`）
    private var rareCharsMap: [String: String] = [:]
    /// 首字母简拼 (`abbr`) -> 补充词条
    private var phrasesByAbbr: [String: [PhraseItem]] = [:]
    /// T9 数字简拼 (`t9_abbr`) -> 补充词条
    private var phrasesByT9: [String: [PhraseItem]] = [:]

    private init() {}

    func ensureLoaded(nearDatabaseURL dbURL: URL? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if isLoaded { return }
        isLoaded = true

        guard let url = Self.resolveResourceURL(nearDatabaseURL: dbURL),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        loadedFromURL = url

        var rare: [String: String] = [:]
        rare.reserveCapacity(420)
        var byAbbr: [String: [PhraseItem]] = [:]
        var byT9: [String: [PhraseItem]] = [:]

        content.enumerateLines { line, _ in
            guard !line.isEmpty else { return }
            if line.hasPrefix("#S\t") {
                let rest = line.dropFirst(3)
                guard let tab = rest.firstIndex(of: "\t") else { return }
                let py = String(rest[..<tab])
                let chars = String(rest[rest.index(after: tab)...])
                if !py.isEmpty && !chars.isEmpty {
                    rare[py] = chars
                }
            } else if line.hasPrefix("#P\t") {
                let parts = line.dropFirst(3).split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 3 else { return }
                let word = String(parts[0])
                let py = String(parts[1])
                let lp = Double(parts[2]) ?? -13.0
                let syls = py.split(separator: "'")
                guard !word.isEmpty, !syls.isEmpty else { return }
                let abbr = syls.compactMap(\.first).map(String.init).joined()
                guard abbr.count == syls.count else { return }
                let t9 = PinyinSegmenter.t9Code(for: abbr)
                let item = PhraseItem(word: word, py: py, lp: lp)
                byAbbr[abbr, default: []].append(item)
                byT9[t9, default: []].append(item)
            }
        }

        self.rareCharsMap = rare
        self.phrasesByAbbr = byAbbr
        self.phrasesByT9 = byT9
    }

    func releaseMemory() {
        lock.lock()
        defer { lock.unlock() }
        rareCharsMap.removeAll(keepingCapacity: false)
        phrasesByAbbr.removeAll(keepingCapacity: false)
        phrasesByT9.removeAll(keepingCapacity: false)
        isLoaded = false
    }

    func phrases(forAbbr abbr: String, isT9: Bool, nearDatabaseURL dbURL: URL? = nil) -> [PhraseItem] {
        ensureLoaded(nearDatabaseURL: dbURL)
        lock.lock()
        defer { lock.unlock() }
        return isT9 ? (phrasesByT9[abbr] ?? []) : (phrasesByAbbr[abbr] ?? [])
    }

    func rareCharacters(forSyllable py: String, nearDatabaseURL dbURL: URL? = nil) -> String {
        ensureLoaded(nearDatabaseURL: dbURL)
        lock.lock()
        defer { lock.unlock() }
        return rareCharsMap[py] ?? ""
    }

    var allRareSyllables: [String] {
        ensureLoaded()
        lock.lock()
        defer { lock.unlock() }
        return Array(rareCharsMap.keys)
    }

    private static func resolveResourceURL(nearDatabaseURL dbURL: URL?) -> URL? {
        if let sibling = dbURL?.deletingLastPathComponent().appendingPathComponent("supplement_lexicon.tsv"),
           FileManager.default.fileExists(atPath: sibling.path) {
            return sibling
        }
        if let mainURL = Bundle.main.url(forResource: "supplement_lexicon", withExtension: "tsv") {
            return mainURL
        }
        let engineBundle = Bundle(for: SupplementLexicon.self)
        if let bundleURL = engineBundle.url(forResource: "supplement_lexicon", withExtension: "tsv") {
            return bundleURL
        }
        // 单元测试本地源码树兜底路径
        let srcCandidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/supplement_lexicon.tsv")
        if FileManager.default.fileExists(atPath: srcCandidate.path) {
            return srcCandidate
        }
        return nil
    }
}
