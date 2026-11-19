import Foundation

/// 拼音切分后的单个音节片段（同时支持 26 键拼音与 T9 九宫格数字段）。
struct PinyinToken: Hashable {
    enum Kind: Hashable {
        case complete
        case partial
        case invalid
    }

    let text: String                      // 26键为拼音，T9模式下为数字串
    let raw: String                       // 原始键入字符
    let kind: Kind
    let end: Int                          // 在原始输入字符串中的结束字符偏移（不含）
    let lockedSyllable: String?           // T9 模式下由左侧音节栏锁定的具体音节

    init(
        text: String,
        raw: String,
        kind: Kind,
        end: Int,
        lockedSyllable: String? = nil
    ) {
        self.text = text
        self.raw = raw
        self.kind = kind
        self.end = end
        self.lockedSyllable = lockedSyllable
    }
}

/// 音节切分器：支持全拼 Viterbi（含单音节歧义拆词与含 zh/ch/sh 简拼回退）、T9 九宫格数字切分、7 种主流双拼方案（对齐 WowType shuangpin.rs）。
final class PinyinSegmenter {
    static let maxSyllableLen = 6
    static let maxSegmentations = 6

    // 雾凇拼音主库使用 lve / nve，因此兼容 lue / nue 以及 jv/qv/xv/yv
    private static let syllableAliases: [String: String] = [
        "lue": "lve", "nue": "nve",
        "jv": "ju", "qv": "qu", "xv": "xu", "yv": "yu",
        "jve": "jue", "qve": "que", "xve": "xue", "yve": "yue",
        "jvan": "juan", "qvan": "quan", "xvan": "xuan", "yvan": "yuan",
        "jvn": "jun", "qvn": "qun", "xvn": "xun", "yvn": "yun",
    ]
    private static let consonantSyllables: Set<String> = ["n", "m", "ng", "hm", "hng"]

    private static let costComplete = 1.0
    private static let costPartialEnd = 1.3
    private static let costPartialMid = 1.8
    private static let costInvalid = 5.0

    private enum ZeroMode {
        /// 单韵母双写、双字母韵母照打，或韵母首字母 + 韵母键（自然码、小鹤）
        case natural
        /// `o` + 韵母键，或韵母首字母 + 韵母键（微软、搜狗、拼音加加）
        case oOrFirst
        /// 仅 `o` + 韵母键（智能 ABC、紫光）
        case oOnly
    }

    private struct DoublePinyinLayout {
        let zh: Character
        let ch: Character
        let sh: Character
        let finals: [(String, Character)]
        let zero: ZeroMode
    }

    private static let layouts: [InputScheme: DoublePinyinLayout] = [
        .ziranma: DoublePinyinLayout(
            zh: "v", ch: "i", sh: "u",
            finals: [
                ("iu", "q"), ("ia", "w"), ("ua", "w"), ("uan", "r"), ("van", "r"),
                ("ue", "t"), ("ve", "t"), ("ing", "y"), ("uai", "y"), ("uo", "o"),
                ("un", "p"), ("vn", "p"), ("ong", "s"), ("iong", "s"), ("iang", "d"),
                ("uang", "d"), ("en", "f"), ("eng", "g"), ("ang", "h"), ("ian", "m"),
                ("an", "j"), ("iao", "c"), ("ao", "k"), ("ai", "l"), ("ei", "z"),
                ("ie", "x"), ("ui", "v"), ("ou", "b"), ("in", "n"),
            ],
            zero: .natural
        ),
        .xiaohe: DoublePinyinLayout(
            zh: "v", ch: "i", sh: "u",
            finals: [
                ("iu", "q"), ("ei", "w"), ("uan", "r"), ("ue", "t"), ("ve", "t"),
                ("un", "y"), ("uo", "o"), ("ie", "p"), ("ong", "s"), ("iong", "s"),
                ("ing", "k"), ("uai", "k"), ("ai", "d"), ("en", "f"), ("eng", "g"),
                ("iang", "l"), ("uang", "l"), ("ang", "h"), ("ian", "m"), ("an", "j"),
                ("ou", "z"), ("ia", "x"), ("ua", "x"), ("iao", "n"), ("ao", "c"),
                ("ui", "v"), ("in", "b"),
            ],
            zero: .natural
        ),
        .microsoft: DoublePinyinLayout(
            zh: "v", ch: "i", sh: "u",
            finals: [
                ("iu", "q"), ("ia", "w"), ("ua", "w"), ("er", "r"), ("uan", "r"), ("van", "r"),
                ("ue", "t"), ("ve", "t"), ("ue", "v"), ("ve", "v"), ("v", "y"), ("uai", "y"),
                ("uo", "o"), ("un", "p"), ("vn", "p"), ("ong", "s"), ("iong", "s"),
                ("iang", "d"), ("uang", "d"), ("en", "f"), ("eng", "g"), ("ang", "h"),
                ("ian", "m"), ("an", "j"), ("iao", "c"), ("ao", "k"), ("ai", "l"),
                ("ei", "z"), ("ie", "x"), ("ui", "v"), ("ou", "b"), ("in", "n"), ("ing", ";"),
            ],
            zero: .oOrFirst
        ),
        .sogou: DoublePinyinLayout(
            zh: "v", ch: "i", sh: "u",
            finals: [
                ("iu", "q"), ("ia", "w"), ("ua", "w"), ("er", "r"), ("uan", "r"), ("van", "r"),
                ("ue", "t"), ("ve", "t"), ("v", "y"), ("uai", "y"), ("uo", "o"),
                ("un", "p"), ("vn", "p"), ("ong", "s"), ("iong", "s"), ("iang", "d"),
                ("uang", "d"), ("en", "f"), ("eng", "g"), ("ang", "h"), ("ian", "m"),
                ("an", "j"), ("iao", "c"), ("ao", "k"), ("ai", "l"), ("ei", "z"),
                ("ie", "x"), ("ui", "v"), ("ou", "b"), ("in", "n"), ("ing", ";"),
            ],
            zero: .oOrFirst
        ),
        .abc: DoublePinyinLayout(
            zh: "a", ch: "e", sh: "v",
            finals: [
                ("ei", "q"), ("ian", "w"), ("er", "r"), ("iu", "r"), ("iang", "t"),
                ("uang", "t"), ("ing", "y"), ("uo", "o"), ("uan", "p"), ("ong", "s"),
                ("iong", "s"), ("ia", "d"), ("ua", "d"), ("en", "f"), ("eng", "g"),
                ("ang", "h"), ("an", "j"), ("iao", "z"), ("ao", "k"), ("in", "c"),
                ("uai", "c"), ("ai", "l"), ("ie", "x"), ("ou", "b"), ("un", "n"),
                ("ue", "m"), ("ve", "m"), ("ui", "m"),
            ],
            zero: .oOnly
        ),
        .ziguang: DoublePinyinLayout(
            zh: "u", ch: "a", sh: "i",
            finals: [
                ("en", "w"), ("eng", "t"), ("in", "y"), ("uai", "y"), ("uo", "o"),
                ("ai", "p"), ("iang", "g"), ("uang", "g"), ("ang", "s"), ("ie", "d"),
                ("ian", "f"), ("ong", "h"), ("iong", "h"), ("er", "j"), ("iu", "j"),
                ("ei", "k"), ("uan", "l"), ("ing", ";"), ("ou", "z"), ("ia", "x"),
                ("ua", "x"), ("iao", "b"), ("ue", "n"), ("ui", "n"), ("ve", "n"),
                ("un", "m"), ("ao", "q"), ("an", "r"),
            ],
            zero: .oOnly
        ),
        .pinyinjiajia: DoublePinyinLayout(
            zh: "v", ch: "u", sh: "i",
            finals: [
                ("iu", "n"), ("ia", "b"), ("ua", "b"), ("er", "q"), ("ing", "q"),
                ("uan", "c"), ("van", "c"), ("ue", "x"), ("ve", "x"), ("uai", "x"),
                ("uo", "o"), ("un", "z"), ("vn", "z"), ("ong", "y"), ("iong", "y"),
                ("iang", "h"), ("uang", "h"), ("en", "r"), ("eng", "t"), ("ang", "g"),
                ("ian", "j"), ("an", "f"), ("iao", "k"), ("ao", "d"), ("ai", "s"),
                ("ei", "w"), ("ie", "m"), ("ui", "v"), ("ou", "p"), ("in", "l"),
            ],
            zero: .oOrFirst
        ),
    ]

    let validSyllables: Set<String>
    private let prefixes: Set<String>
    private let doublePinyinTables: [InputScheme: [String: [String]]]

    let sylToT9: [String: String]
    let t9ToSyllables: [String: [String]]
    private let t9Prefixes: Set<String>

    init(syllables: [String] = PinyinSyllables.all) {
        var set = Set(syllables)
        for alias in Self.syllableAliases.keys {
            set.insert(alias)
        }
        self.validSyllables = set

        var pref = Set<String>()
        pref.reserveCapacity(set.count * 3)
        for syl in set {
            var current = ""
            for ch in syl {
                current.append(ch)
                pref.insert(current)
            }
        }
        self.prefixes = pref

        var s2t9: [String: String] = [:]
        var t9Map: [String: [String]] = [:]
        var t9Pref = Set<String>()
        for syl in syllables.sorted() where !Self.consonantSyllables.contains(syl) {
            let code = Self.t9Code(for: syl)
            s2t9[syl] = code
            t9Map[code, default: []].append(syl)
            var cur = ""
            for ch in code {
                cur.append(ch)
                t9Pref.insert(cur)
            }
        }
        self.sylToT9 = s2t9
        self.t9ToSyllables = t9Map
        self.t9Prefixes = t9Pref

        var tables: [InputScheme: [String: [String]]] = [:]
        for (scheme, layout) in Self.layouts {
            tables[scheme] = Self.buildDoublePinyinTable(syllables: syllables, layout: layout)
        }
        self.doublePinyinTables = tables
    }

    /// 自动生成任意双拼方案的 26 键（含分号）键帽副标签映射，供 `KeyboardCanvasView` 渲染双拼助记提示。
    static func doublePinyinKeycapHints(for scheme: InputScheme) -> [String: String] {
        guard let layout = layouts[scheme] else { return [:] }
        var map: [String: [String]] = [:]
        func add(_ key: Character, _ label: String) {
            let k = String(key)
            var arr = map[k] ?? []
            if !arr.contains(label) {
                arr.append(label)
                map[k] = arr
            }
        }
        add(layout.zh, "zh")
        add(layout.ch, "ch")
        add(layout.sh, "sh")
        for (fin, key) in layout.finals {
            // 过滤与 ue/uan/un 重复的 ve/van/vn 展示，保持键帽紧凑美观
            if fin == "ve" || fin == "van" || fin == "vn" { continue }
            let disp = (fin == "v") ? "ü" : fin
            add(key, disp)
        }
        var out: [String: String] = [:]
        for (k, labels) in map {
            out[k] = labels.prefix(2).joined(separator: "/")
        }
        return out
    }

    static func t9Code(for syllable: String) -> String {
        var out = ""
        out.reserveCapacity(syllable.count)
        for ch in syllable.lowercased() {
            switch ch {
            case "a", "b", "c": out.append("2")
            case "d", "e", "f": out.append("3")
            case "g", "h", "i": out.append("4")
            case "j", "k", "l": out.append("5")
            case "m", "n", "o": out.append("6")
            case "p", "q", "r", "s": out.append("7")
            case "t", "u", "v": out.append("8")
            case "w", "x", "y", "z": out.append("9")
            default: break
            }
        }
        return out
    }

    func segmentations(raw: String, scheme: InputScheme) -> [[PinyinToken]] {
        let lower = raw.lowercased()
        guard !lower.isEmpty else { return [] }
        if scheme.isDoublePinyin, let table = doublePinyinTables[scheme], let layout = Self.layouts[scheme] {
            return segmentDoublePinyin(lower, table: table, layout: layout)
        }
        return segmentQuanpin(lower)
    }

    /// T9 九宫格数字串切分，支持传入左侧筛选栏锁定的前置音节。
    func t9Segmentations(digits: String, lockedPrefixes: [String] = []) -> [[PinyinToken]] {
        let allowedT9Chars = Set("23456789'")
        let clean = digits.filter { allowedT9Chars.contains($0) }
        guard !clean.isEmpty else { return [] }

        var results: [[PinyinToken]] = [[PinyinToken]()]
        var offset = 0
        var lockIndex = 0
        let parts = clean.split(separator: "'", omittingEmptySequences: false)

        for part in parts {
            let chunk = String(part)
            if !chunk.isEmpty {
                var baseTokens: [PinyinToken] = []
                var posInChunk = 0
                let chars = Array(chunk)

                while lockIndex < lockedPrefixes.count && posInChunk < chars.count {
                    let syl = lockedPrefixes[lockIndex]
                    let code = sylToT9[syl] ?? Self.t9Code(for: syl)
                    let endInChunk = posInChunk + code.count
                    if endInChunk <= chars.count && String(chars[posInChunk..<endInChunk]) == code {
                        baseTokens.append(PinyinToken(
                            text: code,
                            raw: code,
                            kind: .complete,
                            end: offset + endInChunk,
                            lockedSyllable: syl
                        ))
                        posInChunk = endInChunk
                        lockIndex += 1
                    } else {
                        break
                    }
                }

                let rem: String
                if posInChunk < chars.count {
                    rem = String(chars[posInChunk..<chars.count])
                } else {
                    rem = ""
                }

                let tails: [[PinyinToken]]
                if rem.isEmpty {
                    tails = [[PinyinToken]()]
                } else {
                    tails = segmentT9Chunk(rem, baseOffset: offset + posInChunk)
                }

                var next: [[PinyinToken]] = []
                for prefix in results {
                    for tail in tails {
                        var combined = prefix
                        combined.append(contentsOf: baseTokens)
                        combined.append(contentsOf: tail)
                        next.append(combined)
                        if next.count >= Self.maxSegmentations { break }
                    }
                    if next.count >= Self.maxSegmentations { break }
                }
                results = next
            }
            offset += chunk.count + 1
        }
        if let first = results.first, !first.isEmpty {
            return results
        }
        return []
    }

    func candidateSyllablesForT9Prefix(_ digits: String, lockedCount: Int, tokens: [PinyinToken]) -> [String] {
        let offset = tokens.prefix(lockedCount).last?.end ?? 0
        let clean = digits.replacingOccurrences(of: "'", with: "")
        guard offset < clean.count else { return [] }
        let rem = String(clean.dropFirst(offset))
        var out: [String] = []
        var seen = Set<String>()
        for len in stride(from: min(Self.maxSyllableLen, rem.count), through: 1, by: -1) {
            let sub = String(rem.prefix(len))
            for syl in t9ToSyllables[sub] ?? [] where seen.insert(syl).inserted {
                out.append(syl)
            }
        }
        return out
    }

    static func displayPinyin(for tokens: [PinyinToken]) -> String {
        tokens.map { tok in
            if let locked = tok.lockedSyllable { return locked }
            return tok.text
        }.joined(separator: "'")
    }

    /// 预测当前拼音末尾之后可能合法延续的下一个按键集合（供键盘动态热区防误触使用，0.02ms 级）。
    func validNextLetters(for raw: String, scheme: InputScheme) -> Set<Character> {
        let lower = raw.lowercased()
        guard !lower.isEmpty, scheme == .quanpin else { return [] }
        guard let seg = segmentations(raw: lower, scheme: .quanpin).first,
              let last = seg.last else { return [] }

        var valid = Set<Character>()
        if last.kind == .partial {
            let p = last.text
            for pref in prefixes where pref.count == p.count + 1 && pref.hasPrefix(p) {
                if let ch = pref.last { valid.insert(ch) }
            }
        } else if last.kind == .complete {
            let p = last.text
            for pref in prefixes where pref.count == p.count + 1 && pref.hasPrefix(p) {
                if let ch = pref.last { valid.insert(ch) }
            }
            for ch in "bpmfdtnlgkhjqxrzcsywaoe" {
                valid.insert(ch)
            }
        }
        return valid
    }

    // MARK: - 全拼切分

    private func classify(_ fragment: String, atEnd: Bool) -> (Double, PinyinToken.Kind)? {
        if validSyllables.contains(fragment) && !Self.consonantSyllables.contains(fragment) {
            return (Self.costComplete, .complete)
        }
        if prefixes.contains(fragment) {
            return (atEnd ? Self.costPartialEnd : Self.costPartialMid, .partial)
        }
        return nil
    }

    private func segmentQuanpin(_ raw: String) -> [[PinyinToken]] {
        var results: [[PinyinToken]] = [[PinyinToken]()]
        var offset = 0
        for part in raw.split(separator: "'", omittingEmptySequences: false) {
            let chunk = String(part)
            if !chunk.isEmpty {
                let alts = segmentChunk(chunk, baseOffset: offset)
                var next: [[PinyinToken]] = []
                for prefix in results {
                    for alt in alts {
                        next.append(prefix + alt)
                        if next.count >= Self.maxSegmentations { break }
                    }
                    if next.count >= Self.maxSegmentations { break }
                }
                results = next
            }
            offset += chunk.count + 1
        }
        return results.first?.isEmpty == false ? results : []
    }

    private func segmentChunk(_ chunk: String, baseOffset: Int) -> [[PinyinToken]] {
        let chars = Array(chunk)
        let n = chars.count
        var cost = Array(repeating: Double.infinity, count: n + 1)
        var preds: [[(Int, PinyinToken.Kind)]] = Array(repeating: [], count: n + 1)
        cost[0] = 0.0

        for i in 0..<n {
            guard cost[i].isFinite else { continue }
            let upper = min(n, i + Self.maxSyllableLen)
            for j in (i + 1)...upper {
                let sub = String(chars[i..<j])
                guard let (stepCost, kind) = classify(sub, atEnd: j == n) else { continue }
                let nextCost = cost[i] + stepCost
                if nextCost < cost[j] - 1e-9 {
                    cost[j] = nextCost
                    preds[j] = [(i, kind)]
                } else if abs(nextCost - cost[j]) <= 1e-9 {
                    preds[j].append((i, kind))
                }
            }
            let invalidCost = cost[i] + Self.costInvalid
            if invalidCost < cost[i + 1] - 1e-9 {
                cost[i + 1] = invalidCost
                preds[i + 1] = [(i, .invalid)]
            }
        }

        var out: [[PinyinToken]] = []
        func walk(_ j: Int, _ tail: [PinyinToken]) {
            if out.count >= Self.maxSegmentations { return }
            if j == 0 {
                out.append(tail.reversed())
                return
            }
            for (i, kind) in preds[j].sorted(by: { $0.0 < $1.0 }) {
                let rawPiece = String(chars[i..<j])
                let norm = Self.syllableAliases[rawPiece] ?? rawPiece
                let token = PinyinToken(text: norm, raw: rawPiece, kind: kind, end: baseOffset + j)
                walk(i, tail + [token])
            }
        }
        walk(n, [])

        // 单音节歧义补充切分：如 xian -> [xian] 外额外补充 [xi, an]，让「西安」无需手动加隔音符即可进 Top-5
        if out.count < Self.maxSegmentations,
           let first = out.first,
           first.count == 1,
           first[0].kind == .complete,
           n >= 3 {
            for k in 1..<n {
                let left = String(chars[0..<k])
                let right = String(chars[k..<n])
                if validSyllables.contains(left) && !Self.consonantSyllables.contains(left),
                   validSyllables.contains(right) && !Self.consonantSyllables.contains(right) {
                    let alt = [
                        PinyinToken(text: Self.syllableAliases[left] ?? left, raw: left, kind: .complete, end: baseOffset + k),
                        PinyinToken(text: Self.syllableAliases[right] ?? right, raw: right, kind: .complete, end: baseOffset + n),
                    ]
                    if !out.contains(alt) {
                        out.append(alt)
                        if out.count >= Self.maxSegmentations { break }
                    }
                }
            }
        }

        // 含 zh/ch/sh 的简拼补充纯单字母切分：如 gzh -> [g, zh] 外补充 [g, z, h]，让「公众号」自然命中
        if out.count < Self.maxSegmentations,
           (2...8).contains(n),
           (chunk.contains("zh") || chunk.contains("ch") || chunk.contains("sh")),
           !(out.first?.allSatisfy { $0.kind == .complete } ?? false),
           chars.allSatisfy({ prefixes.contains(String($0)) }) {
            let singleInitials = chars.enumerated().map { idx, ch in
                PinyinToken(text: String(ch), raw: String(ch), kind: .partial, end: baseOffset + idx + 1)
            }
            if !out.contains(singleInitials) {
                out.append(singleInitials)
            }
        }

        return out
    }

    // MARK: - T9 九宫格数字串切分

    private func segmentT9Chunk(_ chunk: String, baseOffset: Int) -> [[PinyinToken]] {
        let chars = Array(chunk)
        let n = chars.count
        var paths: [[(cost: Double, tokens: [PinyinToken])]] = Array(repeating: [], count: n + 1)
        paths[0] = [(0.0, [])]

        for i in 0..<n {
            guard !paths[i].isEmpty else { continue }
            let upper = min(n, i + Self.maxSyllableLen)
            for j in (i + 1)...upper {
                let sub = String(chars[i..<j])
                let stepCost: Double
                let kind: PinyinToken.Kind
                if t9ToSyllables[sub] != nil {
                    stepCost = 1.0
                    kind = .complete
                } else if t9Prefixes.contains(sub) {
                    stepCost = (j == n) ? 1.35 : 1.85
                    kind = .partial
                } else {
                    continue
                }
                let tok = PinyinToken(text: sub, raw: sub, kind: kind, end: baseOffset + j)
                for (prevC, prevToks) in paths[i] {
                    paths[j].append((prevC + stepCost, prevToks + [tok]))
                }
            }
            if paths[i + 1].isEmpty {
                let ch = String(chars[i])
                let tok = PinyinToken(text: ch, raw: ch, kind: .invalid, end: baseOffset + i + 1)
                for (prevC, prevToks) in paths[i] {
                    paths[i + 1].append((prevC + 5.0, prevToks + [tok]))
                }
            }
            for target in (i + 1)...upper where paths[target].count > 6 {
                paths[target].sort { lhs, rhs in
                    if abs(lhs.cost - rhs.cost) > 1e-6 {
                        return lhs.cost < rhs.cost
                    }
                    return lhs.tokens.count < rhs.tokens.count
                }
                paths[target] = Array(paths[target].prefix(4))
            }
        }

        paths[n].sort { lhs, rhs in
            if abs(lhs.cost - rhs.cost) > 1e-6 {
                return lhs.cost < rhs.cost
            }
            return lhs.tokens.count < rhs.tokens.count
        }
        return Array(paths[n].prefix(Self.maxSegmentations).map(\.tokens))
    }

    // MARK: - 7 种双拼方案统一展开

    private func segmentDoublePinyin(_ raw: String, table: [String: [String]], layout: DoublePinyinLayout) -> [[PinyinToken]] {
        var results: [[PinyinToken]] = [[PinyinToken]()]
        var offset = 0
        for part in raw.split(separator: "'", omittingEmptySequences: false) {
            let chunk = String(part)
            if !chunk.isEmpty {
                let alts = segmentDoubleChunk(chunk, baseOffset: offset, table: table, layout: layout)
                var next: [[PinyinToken]] = []
                for prefix in results {
                    for alt in alts {
                        next.append(prefix + alt)
                        if next.count >= Self.maxSegmentations { break }
                    }
                    if next.count >= Self.maxSegmentations { break }
                }
                results = next
            }
            offset += chunk.count + 1
        }
        return results.first?.isEmpty == false ? results : []
    }

    private func segmentDoubleChunk(
        _ chunk: String,
        baseOffset: Int,
        table: [String: [String]],
        layout: DoublePinyinLayout
    ) -> [[PinyinToken]] {
        let chars = Array(chunk)
        let n = chars.count
        var paths: [[PinyinToken]] = [[PinyinToken]()]
        var i = 0

        while i + 1 < n {
            let pair = String(chars[i...(i + 1)])
            let endOffset = baseOffset + i + 2
            if let matches = table[pair], !matches.isEmpty {
                var expanded: [[PinyinToken]] = []
                for path in paths {
                    for syl in matches {
                        expanded.append(path + [PinyinToken(text: syl, raw: pair, kind: .complete, end: endOffset)])
                        if expanded.count >= Self.maxSegmentations { break }
                    }
                    if expanded.count >= Self.maxSegmentations { break }
                }
                paths = expanded
            } else {
                paths = paths.map { $0 + [PinyinToken(text: pair, raw: pair, kind: .invalid, end: endOffset)] }
            }
            i += 2
        }

        if i < n {
            let ch = chars[i]
            let expandedInitial: String
            if ch == layout.zh {
                expandedInitial = "zh"
            } else if ch == layout.ch {
                expandedInitial = "ch"
            } else if ch == layout.sh {
                expandedInitial = "sh"
            } else {
                expandedInitial = String(ch)
            }
            paths = paths.map { $0 + [PinyinToken(text: expandedInitial, raw: String(ch), kind: .partial, end: baseOffset + n)] }
        }
        return paths
    }

    private static func finalKeys(layout: DoublePinyinLayout, finalPart: String) -> [Character] {
        let explicit = layout.finals.filter { $0.0 == finalPart }.map(\.1)
        if !explicit.isEmpty { return explicit }
        if finalPart.count == 1, let ch = finalPart.first, "aoeiuv".contains(ch) {
            return [ch]
        }
        return []
    }

    private static func splitSyllable(_ syl: String) -> (initial: String, finalPart: String)? {
        guard !syl.isEmpty else { return nil }
        for dg in ["zh", "ch", "sh"] where syl.hasPrefix(dg) {
            return (dg, String(syl.dropFirst(2)))
        }
        if let first = syl.first, "aoe".contains(first) {
            return ("", syl)
        }
        if let first = syl.first, "bpmfdtnlgkhjqxrzcsyw".contains(first) {
            return (String(first), String(syl.dropFirst(1)))
        }
        return nil
    }

    private static func buildDoublePinyinTable(syllables: [String], layout: DoublePinyinLayout) -> [String: [String]] {
        var map: [String: [String]] = [:]
        func append(_ code: String, _ syl: String) {
            var list = map[code] ?? []
            if !list.contains(syl) {
                list.append(syl)
                map[code] = list
            }
        }

        for syl in syllables.sorted() where !Self.consonantSyllables.contains(syl) {
            guard let (ini, fin) = splitSyllable(syl) else { continue }
            let keys = finalKeys(layout: layout, finalPart: fin)

            if ini.isEmpty {
                guard let f0 = fin.first, "aoe".contains(f0) else { continue }
                if layout.zero == .natural && fin.count <= 2 {
                    if fin.count == 1 {
                        append(String([f0, f0]), syl)
                    } else if let f1 = fin.last {
                        append(String([f0, f1]), syl)
                    }
                }
                if layout.zero == .oOrFirst && fin == "ou" {
                    append("ou", syl)
                }
                let oChar: Character = "o"
                for k in keys {
                    if layout.zero != .oOnly {
                        append(String([f0, k]), syl)
                    }
                    if layout.zero != .natural {
                        append(String([oChar, k]), syl)
                    }
                }
            } else {
                let iniKey: Character
                switch ini {
                case "zh": iniKey = layout.zh
                case "ch": iniKey = layout.ch
                case "sh": iniKey = layout.sh
                default:
                    guard let c = ini.first else { continue }
                    iniKey = c
                }
                for k in keys {
                    append(String([iniKey, k]), syl)
                }
            }
        }
        return map
    }
}
