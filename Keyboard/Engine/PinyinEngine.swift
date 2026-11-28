import Foundation
import SQLite3

/// 候选词条（同时承载拼音/双拼/T9/五笔86/英文直出与编码提示）。
struct PinyinCandidate: Hashable {
    enum Source: Hashable {
        case dictionary
        case userLearned
        case smartHelper
        case englishDirect
        case prediction
        case wubi
    }

    let word: String
    let py: String            // 匹配的规范全拼，用于学习词频；智能/英文/五笔辅助词可能为空
    let lp: Double
    let consumed: Int         // 消耗原始输入字符数
    let isExact: Bool
    let source: Source
    let codeHint: String      // 五笔剩余编码后缀（如「您 in」）或 z 临时拼音反查码（如「工 a/aaaa」）

    init(
        word: String,
        py: String,
        lp: Double,
        consumed: Int,
        isExact: Bool,
        source: Source,
        codeHint: String = ""
    ) {
        self.word = word
        self.py = py
        self.lp = lp
        self.consumed = consumed
        self.isExact = isExact
        self.source = source
        self.codeHint = codeHint
    }
}

/// 五笔 86 查询结果（含空码判定、四码唯一自动上屏判定与 `z` 临时拼音反查标志）。
struct WubiQueryResult {
    let candidates: [PinyinCandidate]
    let isEmptyCode: Bool
    let isUnique4: Bool
    let isTempPinyin: Bool
    let displayBuffer: String
}

/// 高性能拼音 / 双拼 / T9 / 五笔86 统一查询与 Beam-Search 语言模型解码引擎 v4（全面对齐 WowType）。
///
/// - 基于雾凇拼音 39.6 万现代词库（融合 WowType 热词/Tatoeba 口语词频/去脏词）+ 20.3 万二元搭配 + 2.2 万英文 + 9.3 万五笔 86
/// - 只读 SQLite 连接（关闭 mmap 并限制 ~1MB 页缓存，严守 iOS 键盘扩展内存红线）
/// - 支持精确保护 (`protectExact`)、补全长度惩罚、儿化音、光标上文消歧、中英直出排位、4 路错拼容错与五笔 86 固定序/顶字/z 反查
final class PinyinEngine {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let invalidLP = -40.0
    private static let wordBoundaryPenalty = 3.2
    private static let contextBigramWeight = 0.65
    private static let mergedPairScore = 1.5
    private static let partialCompletionPenalty = 1.2
    private static let fuzzyPenalty = -0.65
    /// 严控键盘扩展内存红线（48–60MB Jetsam）：既限制缓存桶数，也对总缓存词条数设 12,000 硬上限（~1.2MB）
    private static let maxCacheEntries = 56
    private static let maxTotalCachedRows = 12_000
    private static let maxBigramCacheEntries = 48

    /// 高频英文缩略词补全与常见拼写纠错表（零内存开销，即时生效）
    private static let englishAutoCorrections: [String: String] = [
        "dont": "don't", "cant": "can't", "wont": "won't", "didnt": "didn't",
        "doesnt": "doesn't", "isnt": "isn't", "arent": "aren't", "wasnt": "wasn't",
        "werent": "weren't", "havent": "haven't", "hasnt": "hasn't", "hadnt": "hadn't",
        "wouldnt": "wouldn't", "couldnt": "couldn't", "shouldnt": "shouldn't",
        "im": "I'm", "ive": "I've", "ill": "I'll", "id": "I'd",
        "youre": "you're", "youve": "you've", "youll": "you'll",
        "theyre": "they're", "theyve": "they've", "weve": "we've",
        "thats": "that's", "whats": "what's", "heres": "here's",
        "theres": "there's", "lets": "let's", "whos": "who's",
        "hes": "he's", "shes": "she's",
        "teh": "the", "hte": "the", "taht": "that", "adn": "and",
        "recieve": "receive", "becuase": "because", "definately": "definitely",
        "seperate": "separate", "occured": "occurred", "untill": "until",
        "wich": "which", "wierd": "weird", "thier": "their", "freind": "friend",
        "tommorow": "tomorrow", "goverment": "government", "enviroment": "environment",
        "realy": "really", "accomodate": "accommodate", "acheive": "achieve",
        "arguement": "argument", "calender": "calendar", "commitee": "committee",
        "concious": "conscious", "existance": "existence", "independant": "independent",
        "knowlege": "knowledge", "necesary": "necessary", "occurence": "occurrence",
        "recomend": "recommend", "sucessful": "successful", "truely": "truly",
        "writting": "writing",
    ]

    private static let adjacentKeys: [Character: [Character]] = [
        "q": Array("wa"), "w": Array("qes"), "e": Array("wrd"), "r": Array("etf"), "t": Array("ryg"),
        "y": Array("tuh"), "u": Array("yij"), "i": Array("uok"), "o": Array("ipl"), "p": Array("ol"),
        "a": Array("qwsz"), "s": Array("awedxz"), "d": Array("serfcx"), "f": Array("drtgvc"),
        "g": Array("ftyhbv"), "h": Array("gyujnb"), "j": Array("huikmn"), "k": Array("jiolm"),
        "l": Array("kop"), "z": Array("asx"), "x": Array("zsdc"), "c": Array("xdfv"),
        "v": Array("cfgb"), "b": Array("vghn"), "n": Array("bhjm"), "m": Array("njk"),
    ]

    private var db: OpaquePointer?
    private var dbURL: URL?
    private var abbrStmt: OpaquePointer?
    private var t9Stmt: OpaquePointer?
    private var wordExactStmt: OpaquePointer?
    private var enStmt: OpaquePointer?
    private var enExactStmt: OpaquePointer?
    private var sysBigramStmt: OpaquePointer?
    private var wubiExactStmt: OpaquePointer?
    private var wubiPrefixStmt: OpaquePointer?
    private var wubiReverseStmt: OpaquePointer?
    private var chaiziExactStmt: OpaquePointer?
    private var chaiziPrefixStmt: OpaquePointer?
    private var strokeExactStmt: OpaquePointer?
    private var strokePrefixStmt: OpaquePointer?
    private var glideZhStmt: OpaquePointer?
    private(set) var maxPhraseLen: Int = 8

    let segmenter: PinyinSegmenter
    let userLexicon: UserLexicon

    private struct CacheKey: Hashable {
        let isT9: Bool
        let tokens: [String]
        let kinds: [PinyinToken.Kind]
        let locked: [String?]
        let openEnd: Bool
        let fuzzyMask: Int
        let learnThreshold: Int
    }

    private struct CachedRow {
        let word: String
        let py: String
        let lp: Double
        let exact: Bool
        let isUser: Bool
    }

    private var cache: [CacheKey: [CachedRow]] = [:]
    private var cacheOrder: [CacheKey] = []
    private var totalCachedRows: Int = 0

    private var sysBigramCache: [String: [(next: String, bonus: Double)]] = [:]
    private var sysBigramOrder: [String] = []
    /// 递归并发锁：保护只读 SQLite 复用预处理语句与内存缓存，防止预热/打字/内存警告并发竞态
    private let engineLock = NSRecursiveLock()

    init(databaseURL: URL? = nil, userLexicon: UserLexicon = UserLexicon()) {
        self.userLexicon = userLexicon
        self.segmenter = PinyinSegmenter()

        let resolvedURL = databaseURL ?? Bundle.main.url(forResource: "pinyin", withExtension: "sqlite")
        self.dbURL = resolvedURL
        if let resolvedURL {
            openSystemDict(at: resolvedURL)
        }
        SupplementLexicon.shared.ensureLoaded(nearDatabaseURL: resolvedURL)
    }

    deinit {
        if let abbrStmt { sqlite3_finalize(abbrStmt) }
        if let t9Stmt { sqlite3_finalize(t9Stmt) }
        if let wordExactStmt { sqlite3_finalize(wordExactStmt) }
        if let enStmt { sqlite3_finalize(enStmt) }
        if let enExactStmt { sqlite3_finalize(enExactStmt) }
        if let sysBigramStmt { sqlite3_finalize(sysBigramStmt) }
        if let wubiExactStmt { sqlite3_finalize(wubiExactStmt) }
        if let wubiPrefixStmt { sqlite3_finalize(wubiPrefixStmt) }
        if let wubiReverseStmt { sqlite3_finalize(wubiReverseStmt) }
        if let chaiziExactStmt { sqlite3_finalize(chaiziExactStmt) }
        if let chaiziPrefixStmt { sqlite3_finalize(chaiziPrefixStmt) }
        if let strokeExactStmt { sqlite3_finalize(strokeExactStmt) }
        if let strokePrefixStmt { sqlite3_finalize(strokePrefixStmt) }
        if let glideZhStmt { sqlite3_finalize(glideZhStmt) }
        if let db { sqlite3_close(db) }
    }

    private func openSystemDict(at url: URL) {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return
        }
        self.db = handle
        sqlite3_exec(handle, "PRAGMA mmap_size = 0; PRAGMA cache_size = -1024;", nil, nil, nil)

        var metaStmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, "SELECT value FROM meta WHERE key = 'max_len'", -1, &metaStmt, nil) == SQLITE_OK,
           let metaStmt {
            if sqlite3_step(metaStmt) == SQLITE_ROW, let ptr = sqlite3_column_text(metaStmt, 0) {
                maxPhraseLen = max(4, min(8, Int(String(cString: ptr)) ?? 8))
            }
            sqlite3_finalize(metaStmt)
        }

        // 完整覆盖所有首字母缩写桶（abbr 最大桶 915 条，t9_abbr 最大桶 '99' 为 7,689 条），
        // 彻底根治九宫格与单音节生僻字因 SQL LIMIT 过小导致的漏字/缺词问题！
        sqlite3_prepare_v2(handle, "SELECT word, py, lp FROM dict WHERE abbr = ? ORDER BY lp DESC LIMIT 3000", -1, &abbrStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT word, py, lp FROM dict WHERE t9_abbr = ? ORDER BY lp DESC LIMIT 8000", -1, &t9Stmt, nil)
        sqlite3_prepare_v2(handle, "SELECT lp FROM glide_dict WHERE word = ? ORDER BY lp DESC LIMIT 1", -1, &wordExactStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT word FROM en_dict WHERE lower >= ? AND lower < ? ORDER BY rank DESC LIMIT ?", -1, &enStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT word FROM en_dict WHERE lower = ? LIMIT 1", -1, &enExactStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT next, bonus FROM sys_bigrams WHERE prev = ? ORDER BY bonus DESC LIMIT 128", -1, &sysBigramStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT word FROM wubi WHERE code = ? ORDER BY weight DESC, ord ASC LIMIT ?", -1, &wubiExactStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT word, code FROM wubi WHERE code > ? AND code < ? ORDER BY weight DESC, ord ASC LIMIT ?", -1, &wubiPrefixStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT code FROM wubi WHERE word = ? ORDER BY length(code) ASC, ord ASC LIMIT 6", -1, &wubiReverseStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT word, py FROM chaizi WHERE code = ? ORDER BY weight DESC LIMIT ?", -1, &chaiziExactStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT word, py FROM chaizi WHERE code > ? AND code < ? ORDER BY length(code) ASC, weight DESC LIMIT ?", -1, &chaiziPrefixStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT word, py FROM strokes WHERE code = ? ORDER BY weight DESC LIMIT ?", -1, &strokeExactStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT word, py FROM strokes WHERE code > ? AND code < ? ORDER BY length(code) ASC, weight DESC LIMIT ?", -1, &strokePrefixStmt, nil)
        sqlite3_prepare_v2(handle, "SELECT py_flat, py, word, lp FROM glide_dict WHERE first_c = ? AND last_c = ? ORDER BY lp DESC LIMIT 56", -1, &glideZhStmt, nil)
    }

    func invalidateCache() {
        engineLock.lock()
        defer { engineLock.unlock() }
        cache.removeAll(keepingCapacity: true)
        cacheOrder.removeAll(keepingCapacity: true)
        totalCachedRows = 0
    }

    /// 响应 iOS `didReceiveMemoryWarning()`，主动清空查询与二元缓存并释放 SQLite 页缓存，严防 Jetsam 杀掉键盘扩展。
    func releaseMemory() {
        engineLock.lock()
        defer { engineLock.unlock() }
        cache.removeAll(keepingCapacity: false)
        cacheOrder.removeAll(keepingCapacity: false)
        totalCachedRows = 0
        sysBigramCache.removeAll(keepingCapacity: false)
        sysBigramOrder.removeAll(keepingCapacity: false)
        userLexicon.releaseMemory()
        SupplementLexicon.shared.releaseMemory()
        if let db {
            sqlite3_db_release_memory(db)
        }
    }

    // MARK: - 26键查询（全拼 + 7种双拼 + 儿化音 + 光标上文消歧 + 中英排位 + 4路纠错）

    func query(
        raw: String,
        settings: LingxiSettings,
        contextBeforeCursor: String? = nil,
        limit: Int = 128
    ) -> (tokens: [PinyinToken], candidates: [PinyinCandidate], correctedHint: String?) {
        engineLock.lock()
        defer { engineLock.unlock() }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], [], nil) }
        let lower = trimmed.lowercased()

        // 0. 中英数混输直出（含内嵌数字如 mingtian3dianjian -> 明天3点见，或含非法拼音段的常见英文缩写如 fayigepdfgeiwo -> 发一个PDF给我）
        let effectiveScheme: InputScheme = settings.inputScheme.isWubi ? .quanpin : settings.inputScheme
        if effectiveScheme == .quanpin && !lower.hasPrefix("v") && lower.count >= 3 && lower.contains(where: \.isNumber),
           let mixed = attemptMixedChineseDigitEnglishDecode(raw: trimmed, settings: settings, contextBeforeCursor: contextBeforeCursor) {
            return (mixed.tokens, mixed.candidates, nil)
        }

        let ctxMap = settings.bigramPredictionEnabled
            ? contextBonusMap(from: contextBeforeCursor, userLearning: settings.userLearningEnabled)
            : [:]
        let segs = segmenter.segmentations(raw: trimmed, scheme: effectiveScheme)
        // 单音节放宽至 420（100% 覆盖规范字+生僻字），多音节长输入放宽至 260（确保打很多字时首音节单字仍完整保留 140+ 字不截断！）
        let isSingleSyllableQuery = segs.contains { $0.count == 1 }
        let effectiveLimit: Int
        if limit >= 64 {
            effectiveLimit = isSingleSyllableQuery ? max(limit, 420) : max(limit, 260)
        } else {
            effectiveLimit = limit
        }
        var (bestSeg, out) = evaluateSegmentations(
            segs,
            isT9: false,
            settings: settings,
            contextMap: ctxMap,
            rawContext: contextBeforeCursor,
            limit: effectiveLimit
        )

        let hasInvalid = bestSeg.contains { $0.kind == .invalid }
        let hasNonCompleteCluster: Bool = {
            var run = 0
            for t in bestSeg {
                if t.kind != .complete {
                    run += 1
                    if run >= 2 { return true }
                } else {
                    run = 0
                }
            }
            return false
        }()
        let allInitials = !bestSeg.isEmpty && bestSeg.allSatisfy { $0.raw.count == 1 }
        let allComplete = !bestSeg.isEmpty && bestSeg.allSatisfy { $0.kind == .complete }
        let hasAwkwardPartial = bestSeg.count >= 2 && !allInitials && bestSeg.contains { $0.kind == .partial }

        // 1. 儿化音：wanr -> wan'er(玩儿), zher -> zhe'er(这儿), yidianr -> 一点儿, haowanr -> 好玩儿
        if effectiveScheme == .quanpin,
           lower.count >= 3,
           lower.hasSuffix("r"),
           !allComplete,
           !lower.contains("'") {
            let erRaw = String(lower.dropLast()) + "'er"
            let erSegs = segmenter.segmentations(raw: erRaw, scheme: .quanpin)
                .filter { $0.allSatisfy { $0.kind == .complete } }
            if !erSegs.isEmpty {
                let (_, erOut) = evaluateSegmentations(erSegs, isT9: false, settings: settings, contextMap: ctxMap, limit: 8)
                let erHits = erOut.filter { $0.word.hasSuffix("儿") }.map {
                    PinyinCandidate(word: $0.word, py: $0.py, lp: $0.lp, consumed: trimmed.count, isExact: true, source: $0.source)
                }
                if !erHits.isEmpty {
                    let erSet = Set(erHits.map(\.word))
                    out = erHits + out.filter { !erSet.contains($0.word) }
                }
            }
        }

        // 2. 英文精确词直出排位（WowType 规则）：
        //    - 非合法全拼（github/wechat/deepseek/iphone）直接排第 1 位，跳过无谓拼音纠错；
        //    - 同时是合法全拼的英文词（like/danger）留前 5 位给中文，精确放第 6 位（index 5）。
        let exactEn = (settings.smartEnglishCandidate && effectiveScheme == .quanpin) ? exactEnglish(for: lower) : nil
        if let exactEn, !allComplete {
            let strongInitialHit = allInitials && (out.first.map { $0.isExact && $0.lp > -11.5 } ?? false)
            if !strongInitialHit {
                let enCand = PinyinCandidate(word: exactEn, py: "", lp: 5.0, consumed: trimmed.count, isExact: true, source: .englishDirect)
                out = [enCand] + out.filter { $0.word != exactEn }
                return (bestSeg, Array(out.prefix(effectiveLimit)), nil)
            }
        }

        // 3. 智能 4 路容错 + 合法全拼换位/鼻音/末位邻键容错（严格保护正常成句不被邻键误劫持，仅对 <=4 音节执行高速查表）
        var correctedHint: String?
        if settings.typoCorrectionEnabled && effectiveScheme == .quanpin && !trimmed.contains("'"),
           !lower.hasPrefix("v"),
           (3...16).contains(trimmed.count) {
            if hasInvalid || hasAwkwardPartial {
                if let fix = attemptTypoFix(raw: lower, rawSeg: bestSeg, settings: settings, contextMap: ctxMap) {
                    let rawTopLP = out.first?.lp ?? -Double.infinity
                    // 仅含合法混简拼（无 invalid）时，需命中高频词 (> -11.5) 才覆盖，避免「拥吻」抢走「用中文」
                    let allowPromote = hasInvalid || (fix.topLP > -11.5 && fix.topLP - 3.8 > rawTopLP)
                    if allowPromote {
                        correctedHint = PinyinSegmenter.displayPinyin(for: fix.seg)
                        let promoted = fix.cands.prefix(3).map {
                            PinyinCandidate(word: $0.word, py: $0.py, lp: $0.lp, consumed: trimmed.count, isExact: false, source: $0.source)
                        }
                        let promotedSet = Set(promoted.map(\.word))
                        out = promoted + out.filter { !promotedSet.contains($0.word) }
                    }
                }
            } else if allComplete && (2...4).contains(bestSeg.count) && trimmed.count <= 14 {
                let rawIsExact = out.first?.isExact ?? false
                let rawTopLP = out.first?.lp ?? -25.0
                let hasStrongExact = rawIsExact && rawTopLP > -12.5
                if !hasStrongExact {
                    // 3a. 换位（meiyuo -> 没有）+ 前后鼻音单 g 误敲（shengme -> 什么, penyou -> 朋友）+ 平翘舌模糊兜底
                    if let strongFix = attemptCompleteSwapOrNasalFix(
                        raw: lower,
                        bestSeg: bestSeg,
                        rawIsExact: rawIsExact,
                        rawTopLP: rawTopLP,
                        settings: settings,
                        contextMap: ctxMap
                    ) {
                        let cand = PinyinCandidate(
                            word: strongFix.cand.word,
                            py: strongFix.cand.py,
                            lp: strongFix.cand.lp,
                            consumed: trimmed.count,
                            isExact: false,
                            source: strongFix.cand.source
                        )
                        if strongFix.promoteToFirst {
                            correctedHint = PinyinSegmenter.displayPinyin(for: strongFix.seg)
                            out = [cand] + out.filter { $0.word != cand.word }
                        } else if !out.prefix(2).contains(where: { $0.word == cand.word }) {
                            out = out.filter { $0.word != cand.word }
                            out.insert(cand, at: min(1, out.count))
                        }
                    } else if bestSeg.count == 2 {
                        // 3b. 末位邻键高频词放第 2 位（tianqu -> [天区, 天气]，保护精确首词）
                        if let adjCand = attemptTailAdjacentFix(raw: lower, rawTopLP: rawTopLP, settings: settings, contextMap: ctxMap),
                           !out.prefix(2).contains(where: { $0.word == adjCand.word }) {
                            out.insert(adjCand, at: min(1, out.count))
                        }
                    }
                }
            }
        }

        // 3.5 单音节平翘舌/前后鼻音温和兜底（如未开模糊音时打 ze 也能在第 4~5 位看到「这」，打 si 能看到「是」，打 zi 能看到「只/知」）
        if settings.fuzzyFallbackEnabled && effectiveScheme == .quanpin && allComplete && bestSeg.count == 1 {
            let syl = bestSeg[0].text
            var fuzzyAlts: [String] = []
            for (dg, sg) in [("zh", "z"), ("ch", "c"), ("sh", "s")] {
                if syl.hasPrefix(dg) {
                    fuzzyAlts.append(sg + String(syl.dropFirst(2)))
                } else if syl.hasPrefix(sg) {
                    fuzzyAlts.append(dg + String(syl.dropFirst(1)))
                }
            }
            for (finA, finB) in [("ang", "an"), ("eng", "en"), ("ing", "in")] {
                if syl.hasSuffix(finA) {
                    fuzzyAlts.append(String(syl.dropLast(3)) + finB)
                } else if syl.hasSuffix(finB) {
                    fuzzyAlts.append(String(syl.dropLast(2)) + finA)
                }
            }
            var insertPos = min(3, out.count)
            var existingWords = Set(out.map(\.word))
            for alt in fuzzyAlts where segmenter.validSyllables.contains(alt) {
                let altTok = PinyinToken(text: alt, raw: trimmed, kind: .complete, end: trimmed.count)
                let hits = lookup(tokens: [altTok], start: 0, end: 1, openEnd: false, isT9: false, settings: settings)
                for h in hits.prefix(2) where h.word.count == 1 && h.lp > -8.6 && existingWords.insert(h.word).inserted {
                    let fallbackCand = PinyinCandidate(
                        word: h.word,
                        py: h.py,
                        lp: h.lp - 1.5,
                        consumed: trimmed.count,
                        isExact: false,
                        source: .dictionary
                    )
                    out.insert(fallbackCand, at: min(insertPos, out.count))
                    insertPos += 1
                }
            }
        }

        // 4. 合法全拼同时又是英文词（like / danger）排第 6 位（index 5）
        if let exactEn, allComplete {
            let enCand = PinyinCandidate(word: exactEn, py: "", lp: -20.0, consumed: trimmed.count, isExact: false, source: .englishDirect)
            out = out.filter { $0.word != exactEn }
            out.insert(enCand, at: min(5, out.count))
        }

        // 4.5 中英内嵌缩写混输（如 fayigepdfgeiwo -> 发一个PDF给我）：放在常规纠错之后，不劫持正常中文错拼纠错
        if effectiveScheme == .quanpin && (hasInvalid || hasNonCompleteCluster) && lower.count >= 5 && correctedHint == nil,
           let mixed = attemptMixedChineseDigitEnglishDecode(raw: trimmed, settings: settings, contextBeforeCursor: contextBeforeCursor) {
            let mixedWords = Set(mixed.candidates.map(\.word))
            out = mixed.candidates + out.filter { !mixedWords.contains($0.word) }
        }

        // 5. 实时地理位置与周边 POI 动态提权（当前所在城市/区县/街道/商圈/车站精准命中，不劫持日常短词）
        if settings.geoLocationBoostEnabled && effectiveScheme == .quanpin && !lower.hasPrefix("v") {
            let geoHits = GeoLocationContext.load().matchCandidates(rawInput: lower, isT9: false, limit: 3)
            if !geoHits.isEmpty {
                let cleanLower = lower.replacingOccurrences(of: "'", with: "")
                var promotedTop: [PinyinCandidate] = []
                var promotedSecondary: [PinyinCandidate] = []
                for entry in geoHits {
                    let flatPy = entry.pinyin.replacingOccurrences(of: "'", with: "")
                    let isFullExact = (flatPy == cleanLower)
                    let isLongAbbrExact = (entry.abbr == cleanLower && cleanLower.count >= 4)
                    let cand = PinyinCandidate(
                        word: entry.word,
                        py: entry.pinyin,
                        lp: entry.boostScore,
                        consumed: trimmed.count,
                        isExact: isFullExact,
                        source: .userLearned
                    )
                    if isFullExact || isLongAbbrExact {
                        promotedTop.append(cand)
                    } else {
                        promotedSecondary.append(cand)
                    }
                }
                let injectedSet = Set((promotedTop + promotedSecondary).map(\.word))
                out = out.filter { !injectedSet.contains($0.word) }
                if !promotedTop.isEmpty {
                    out = promotedTop + out
                }
                if !promotedSecondary.isEmpty {
                    let insertIdx = min(max(2, promotedTop.count + 1), out.count)
                    out.insert(contentsOf: promotedSecondary, at: insertIdx)
                }
            }
        }

        return (bestSeg, Array(out.prefix(effectiveLimit)), correctedHint)
    }

    // MARK: - 引擎 3.0：中英数混输直出 & 点击任意音节局部单字反查

    // 仅收录 3 字母以上无歧义英文缩写，彻底避免 2 字母词（ai/ui/ok/hr/pm/pr）误切正常中文拼音
    private static let embeddedEnglishTokens: [(lower: String, display: String)] = [
        ("iphone", "iPhone"), ("github", "GitHub"), ("wechat", "WeChat"), ("deepseek", "DeepSeek"),
        ("chatgpt", "ChatGPT"), ("gemini", "Gemini"), ("swift", "Swift"), ("python", "Python"),
        ("docker", "Docker"), ("macos", "macOS"), ("xcode", "Xcode"), ("wifi", "Wi-Fi"),
        ("pdf", "PDF"), ("ppt", "PPT"), ("vip", "VIP"), ("api", "API"), ("app", "App"),
        ("bug", "Bug"), ("ios", "iOS"), ("mac", "Mac"), ("sql", "SQL"), ("llm", "LLM"),
        ("ipa", "IPA"), ("url", "URL"), ("ceo", "CEO"), ("kpi", "KPI"), ("okr", "OKR"),
    ]

    /// 当拼音串中包含阿拉伯数字（如 `mingtian3dianjian`）或嵌入高频英文缩写（如 `fayigepdfgeiwo`）时，
    /// 自动分段解码中文并无缝拼合英文/数字，免切换键盘直接输出整句。
    private func attemptMixedChineseDigitEnglishDecode(
        raw: String,
        settings: LingxiSettings,
        contextBeforeCursor: String?
    ) -> (tokens: [PinyinToken], candidates: [PinyinCandidate])? {
        let lower = raw.lowercased()
        enum Piece { case py(String), literal(String) }
        var pieces: [Piece] = []
        var idx = lower.startIndex

        // 1. 先按数字块切分
        var buf = ""
        while idx < lower.endIndex {
            let ch = lower[idx]
            if ch.isNumber {
                if !buf.isEmpty { pieces.append(.py(buf)); buf = "" }
                var numStr = ""
                while idx < lower.endIndex && (lower[idx].isNumber || lower[idx] == ".") {
                    numStr.append(lower[idx])
                    idx = lower.index(after: idx)
                }
                pieces.append(.literal(numStr))
                continue
            }
            buf.append(ch)
            idx = lower.index(after: idx)
        }
        if !buf.isEmpty { pieces.append(.py(buf)) }

        // 2. 在无法全部切分为完整全拼音节的字母片段中，尝试识别常见内嵌英文词（如 pdf/ppt/bug/api/app/ios）
        var refined: [Piece] = []
        var foundMixedLiteral = pieces.contains { if case .literal = $0 { return true }; return false }
        for piece in pieces {
            guard case .py(let segText) = piece, segText.count >= 3 else {
                refined.append(piece)
                continue
            }
            let rawSegs = segmenter.segmentations(raw: segText, scheme: .quanpin)
            let isCleanCompletePinyin = rawSegs.first?.allSatisfy({ $0.kind == .complete }) ?? false
            if isCleanCompletePinyin {
                refined.append(piece)
                continue
            }
            var splitDone = false
            for entry in Self.embeddedEnglishTokens where segText.contains(entry.lower) {
                if let range = segText.range(of: entry.lower) {
                    let left = String(segText[..<range.lowerBound])
                    let right = String(segText[range.upperBound...])
                    let leftSeg = left.isEmpty ? [] : (segmenter.segmentations(raw: left, scheme: .quanpin).first ?? [])
                    let rightSeg = right.isEmpty ? [] : (segmenter.segmentations(raw: right, scheme: .quanpin).first ?? [])
                    let leftOK = left.isEmpty || (!leftSeg.isEmpty && leftSeg.allSatisfy({ $0.kind == .complete }))
                    let rightOK = right.isEmpty || (!rightSeg.isEmpty && rightSeg.allSatisfy({ $0.kind == .complete }))
                    if leftOK && rightOK && (!left.isEmpty || !right.isEmpty) {
                        if !left.isEmpty { refined.append(.py(left)) }
                        refined.append(.literal(entry.display))
                        if !right.isEmpty { refined.append(.py(right)) }
                        foundMixedLiteral = true
                        splitDone = true
                        break
                    }
                }
            }
            if !splitDone { refined.append(piece) }
        }

        guard foundMixedLiteral else { return nil }

        var pieceOptions: [[String]] = []
        var assembledTokens: [PinyinToken] = []
        var cursorOffset = 0
        for p in refined {
            switch p {
            case .literal(let lit):
                pieceOptions.append([lit])
                assembledTokens.append(PinyinToken(text: lit, raw: lit, kind: .complete, end: cursorOffset + lit.count))
                cursorOffset += lit.count
            case .py(let pyPart):
                let segs = segmenter.segmentations(raw: pyPart, scheme: .quanpin)
                let (subSeg, subCands) = evaluateSegmentations(segs, isT9: false, settings: settings, contextMap: [:], limit: 5)
                guard !subCands.isEmpty else { return nil }
                pieceOptions.append(Array(subCands.prefix(4).map(\.word)))
                for t in subSeg {
                    assembledTokens.append(PinyinToken(text: t.text, raw: t.raw, kind: t.kind, end: cursorOffset + t.end))
                }
                cursorOffset += pyPart.count
            }
        }
        let primaryJoined = pieceOptions.compactMap(\.first).joined()
        guard !primaryJoined.isEmpty else { return nil }
        var outCands: [PinyinCandidate] = [
            PinyinCandidate(
                word: primaryJoined,
                py: "",
                lp: 12.0,
                consumed: raw.count,
                isExact: true,
                source: .dictionary
            )
        ]
        var seen = Set<String>([primaryJoined])
        // 为主中文分片补充次选组合，避免中数混输时候选栏只剩唯一孤词
        if let varyIdx = pieceOptions.lastIndex(where: { $0.count > 1 }) {
            for alt in pieceOptions[varyIdx].dropFirst() {
                var parts = pieceOptions.compactMap(\.first)
                parts[varyIdx] = alt
                let word = parts.joined()
                if seen.insert(word).inserted {
                    outCands.append(PinyinCandidate(
                        word: word,
                        py: "",
                        lp: 11.0 - Double(outCands.count) * 0.2,
                        consumed: raw.count,
                        isExact: false,
                        source: .dictionary
                    ))
                }
            }
        }
        return (assembledTokens, outCands)
    }

    /// 针对长句中用户点选的任意单个音节，快速返回其全部同音单字（含规范字与扩展生僻字），用于「免退格回溯改字」。
    func candidatesForSingleToken(
        _ token: PinyinToken,
        isT9: Bool,
        settings: LingxiSettings,
        limit: Int = 360
    ) -> [PinyinCandidate] {
        engineLock.lock()
        defer { engineLock.unlock() }
        let single = lookup(tokens: [token], start: 0, end: 1, openEnd: false, isT9: isT9, settings: settings)
            .filter { $0.word.count == 1 }
        return Array(single.prefix(limit))
    }

    // MARK: - 五笔 86（固定表序、剩余码提示、四码唯一自动上屏、z 临时拼音与五笔编码反查）

    func queryWubi(
        raw: String,
        settings: LingxiSettings,
        contextBeforeCursor: String? = nil,
        limit: Int = 36
    ) -> WubiQueryResult {
        engineLock.lock()
        defer { engineLock.unlock() }
        let lower = raw.lowercased()
        guard !lower.isEmpty else {
            return WubiQueryResult(candidates: [], isEmptyCode: false, isUnique4: false, isTempPinyin: false, displayBuffer: "")
        }

        // 1. z 键引导临时拼音 + 反查每个词条的最短/完整五笔编码（如 `znihao` -> `你好 wqvb`、`zriqi` -> 日期）
        if lower.hasPrefix("z") {
            let body = String(lower.dropFirst())
            if body.isEmpty {
                return WubiQueryResult(
                    candidates: [],
                    isEmptyCode: false,
                    isUnique4: false,
                    isTempPinyin: true,
                    displayBuffer: "z·临时拼音"
                )
            }
            var pySettings = settings
            pySettings.inputScheme = .quanpin
            let (tokens, pyCands, _) = query(raw: body, settings: pySettings, contextBeforeCursor: contextBeforeCursor, limit: limit)
            var out: [PinyinCandidate] = []
            // 支持 zriqi / zshijian / zxingqi 快捷日期时间
            for dt in DateTimeHelper.candidates(forNormalizedPinyin: body) {
                out.append(PinyinCandidate(word: dt, py: "", lp: 10.0, consumed: lower.count, isExact: true, source: .smartHelper))
            }
            for c in pyCands {
                let rev = settings.wubiShowCodeHints ? wubiReverseHint(for: c.word) : ""
                out.append(PinyinCandidate(
                    word: c.word,
                    py: c.py,
                    lp: c.lp,
                    consumed: lower.count,
                    isExact: c.isExact,
                    source: c.source,
                    codeHint: rev
                ))
            }
            let disp = "z·" + (tokens.isEmpty ? body : PinyinSegmenter.displayPinyin(for: tokens))
            return WubiQueryResult(
                candidates: Array(out.prefix(limit)),
                isEmptyCode: out.isEmpty,
                isUnique4: false,
                isTempPinyin: true,
                displayBuffer: disp
            )
        }

        // 2. 标准五笔 86 查表（仅 a-y，1~4 码，严格按码表原序不动态调频）
        guard lower.count <= 4,
              lower.allSatisfy({ $0 >= "a" && $0 <= "y" }),
              let exactStmt = wubiExactStmt else {
            return WubiQueryResult(candidates: [], isEmptyCode: true, isUnique4: false, isTempPinyin: false, displayBuffer: lower)
        }

        var exactWords: [PinyinCandidate] = []
        var seen = Set<String>()
        sqlite3_reset(exactStmt)
        sqlite3_clear_bindings(exactStmt)
        lower.withCString { sqlite3_bind_text(exactStmt, 1, $0, -1, Self.sqliteTransient) }
        sqlite3_bind_int(exactStmt, 2, Int32(limit))
        while sqlite3_step(exactStmt) == SQLITE_ROW {
            guard let ptr = sqlite3_column_text(exactStmt, 0) else { continue }
            let word = String(cString: ptr)
            if seen.insert(word).inserted {
                exactWords.append(PinyinCandidate(
                    word: word,
                    py: "",
                    lp: 0.0,
                    consumed: lower.count,
                    isExact: true,
                    source: .wubi,
                    codeHint: ""
                ))
            }
        }

        let isUnique4 = (lower.count == 4 && exactWords.count == 1)
        var out = exactWords

        // 未满 4 码时补充前缀联想并附带剩余编码提示（如 `wq` -> `您 in`, `低 a`, `你的 rq`）
        if lower.count < 4, out.count < limit, let prefixStmt = wubiPrefixStmt,
           let lastScalar = lower.unicodeScalars.last,
           let nextScalar = UnicodeScalar(lastScalar.value + 1) {
            let upper = String(lower.dropLast()) + String(nextScalar)
            sqlite3_reset(prefixStmt)
            sqlite3_clear_bindings(prefixStmt)
            lower.withCString { sqlite3_bind_text(prefixStmt, 1, $0, -1, Self.sqliteTransient) }
            upper.withCString { sqlite3_bind_text(prefixStmt, 2, $0, -1, Self.sqliteTransient) }
            sqlite3_bind_int(prefixStmt, 3, Int32(limit * 2))
            while sqlite3_step(prefixStmt) == SQLITE_ROW {
                guard let wPtr = sqlite3_column_text(prefixStmt, 0),
                      let cPtr = sqlite3_column_text(prefixStmt, 1) else { continue }
                let word = String(cString: wPtr)
                let fullCode = String(cString: cPtr)
                if seen.insert(word).inserted {
                    let suffix = settings.wubiShowCodeHints ? String(fullCode.dropFirst(lower.count)) : ""
                    out.append(PinyinCandidate(
                        word: word,
                        py: "",
                        lp: -1.0,
                        consumed: lower.count,
                        isExact: false,
                        source: .wubi,
                        codeHint: suffix
                    ))
                    if out.count >= limit { break }
                }
            }
        }

        return WubiQueryResult(
            candidates: out,
            isEmptyCode: out.isEmpty,
            isUnique4: isUnique4,
            isTempPinyin: false,
            displayBuffer: out.isEmpty ? "\(lower) · 空码" : lower
        )
    }

    /// 反查汉字/词条的五笔 86 编码（如「工」-> `a/aaaa`，「你好」-> `wqvb`）。
    func wubiReverseHint(for word: String) -> String {
        engineLock.lock()
        defer { engineLock.unlock() }
        guard !word.isEmpty, let stmt = wubiReverseStmt else { return "" }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        word.withCString { sqlite3_bind_text(stmt, 1, $0, -1, Self.sqliteTransient) }
        var codes: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let ptr = sqlite3_column_text(stmt, 0) {
                let code = String(cString: ptr)
                if !codes.contains(code) { codes.append(code) }
            }
        }
        guard let first = codes.first else { return "" }
        if let last = codes.last, last != first {
            return "\(first)/\(last)"
        }
        return first
    }

    // MARK: - U 模式：部件拆字反查 (`radical_pinyin`) + 五笔画反查 (`stroke`)

    /// Rime / 仓输入法同款 `u` 拆字与五笔画反查（如 `ushuishuishui` -> `淼 miao`、`ufangfangtu` -> `堃 kun`、`uhspn` -> `木 mu`）。
    func queryUMode(
        raw: String,
        limit: Int = 36
    ) -> (candidates: [PinyinCandidate], displayBuffer: String) {
        engineLock.lock()
        defer { engineLock.unlock() }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], "") }
        let body = String(trimmed.dropFirst()).lowercased().replacingOccurrences(of: "'", with: "")
        if body.isEmpty {
            return ([], "u·拆字/笔画 (如 shui·淼 / hspn·木)")
        }
        guard body.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return ([], "u·\(body)")
        }

        var out: [PinyinCandidate] = []
        var seen = Set<String>()
        let consumedLen = trimmed.count

        func appendHit(word: String, py: String, lp: Double, exact: Bool) {
            guard seen.insert(word).inserted else { return }
            out.append(PinyinCandidate(
                word: word,
                py: py,
                lp: lp,
                consumed: consumedLen,
                isExact: exact,
                source: .dictionary,
                codeHint: py
            ))
        }

        // 1. 部件拆字精确匹配
        if let exactStmt = chaiziExactStmt {
            sqlite3_reset(exactStmt)
            sqlite3_clear_bindings(exactStmt)
            body.withCString { sqlite3_bind_text(exactStmt, 1, $0, -1, Self.sqliteTransient) }
            sqlite3_bind_int(exactStmt, 2, Int32(limit))
            while sqlite3_step(exactStmt) == SQLITE_ROW {
                guard let wPtr = sqlite3_column_text(exactStmt, 0),
                      let pPtr = sqlite3_column_text(exactStmt, 1) else { continue }
                appendHit(word: String(cString: wPtr), py: String(cString: pPtr), lp: 0.0, exact: true)
            }
        }

        // 2. 五笔画精确匹配（h横 s竖 p撇 n/d捺点 z折）
        let strokeQuery = body.replacingOccurrences(of: "d", with: "n")
        let isValidStrokeSeq = strokeQuery.allSatisfy { "hspnz".contains($0) }
        if isValidStrokeSeq, let sExact = strokeExactStmt {
            sqlite3_reset(sExact)
            sqlite3_clear_bindings(sExact)
            strokeQuery.withCString { sqlite3_bind_text(sExact, 1, $0, -1, Self.sqliteTransient) }
            sqlite3_bind_int(sExact, 2, Int32(limit))
            while sqlite3_step(sExact) == SQLITE_ROW {
                guard let wPtr = sqlite3_column_text(sExact, 0),
                      let pPtr = sqlite3_column_text(sExact, 1) else { continue }
                appendHit(word: String(cString: wPtr), py: String(cString: pPtr), lp: -0.2, exact: true)
            }
        }

        // 3. 部件拆字前缀联想
        if out.count < limit, let prefStmt = chaiziPrefixStmt,
           let lastScalar = body.unicodeScalars.last,
           let nextScalar = UnicodeScalar(lastScalar.value + 1) {
            let upper = String(body.dropLast()) + String(nextScalar)
            sqlite3_reset(prefStmt)
            sqlite3_clear_bindings(prefStmt)
            body.withCString { sqlite3_bind_text(prefStmt, 1, $0, -1, Self.sqliteTransient) }
            upper.withCString { sqlite3_bind_text(prefStmt, 2, $0, -1, Self.sqliteTransient) }
            sqlite3_bind_int(prefStmt, 3, Int32(limit * 2))
            while sqlite3_step(prefStmt) == SQLITE_ROW {
                guard let wPtr = sqlite3_column_text(prefStmt, 0),
                      let pPtr = sqlite3_column_text(prefStmt, 1) else { continue }
                appendHit(word: String(cString: wPtr), py: String(cString: pPtr), lp: -1.0, exact: false)
                if out.count >= limit { break }
            }
        }

        // 4. 五笔画前缀联想
        if isValidStrokeSeq, out.count < limit, let sPref = strokePrefixStmt,
           let lastScalar = strokeQuery.unicodeScalars.last,
           let nextScalar = UnicodeScalar(lastScalar.value + 1) {
            let upper = String(strokeQuery.dropLast()) + String(nextScalar)
            sqlite3_reset(sPref)
            sqlite3_clear_bindings(sPref)
            strokeQuery.withCString { sqlite3_bind_text(sPref, 1, $0, -1, Self.sqliteTransient) }
            upper.withCString { sqlite3_bind_text(sPref, 2, $0, -1, Self.sqliteTransient) }
            sqlite3_bind_int(sPref, 3, Int32(limit * 2))
            while sqlite3_step(sPref) == SQLITE_ROW {
                guard let wPtr = sqlite3_column_text(sPref, 0),
                      let pPtr = sqlite3_column_text(sPref, 1) else { continue }
                appendHit(word: String(cString: wPtr), py: String(cString: pPtr), lp: -1.5, exact: false)
                if out.count >= limit { break }
            }
        }

        let modeTag = isValidStrokeSeq ? "笔画/拆字" : "拆字"
        return (Array(out.prefix(limit)), "u·\(modeTag): \(body)")
    }

    // MARK: - 滑行输入词候选桶检索 (供 GlideTypingDecoder 调用)

    func fetchGlidePool(
        startKeys: [Character],
        endKeys: [Character],
        isEnglish: Bool
    ) -> [(pyFlat: String, py: String, word: String, lp: Double)] {
        engineLock.lock()
        defer { engineLock.unlock() }
        guard !startKeys.isEmpty, !endKeys.isEmpty else { return [] }
        var out: [(String, String, String, Double)] = []

        if isEnglish {
            guard let stmt = enStmt else { return [] }
            let endSet = Set(endKeys)
            for sKey in startKeys {
                let lower = String(sKey)
                guard let scalar = lower.unicodeScalars.first,
                      let nextScalar = UnicodeScalar(scalar.value + 1) else { continue }
                let upper = String(nextScalar)
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                lower.withCString { sqlite3_bind_text(stmt, 1, $0, -1, Self.sqliteTransient) }
                upper.withCString { sqlite3_bind_text(stmt, 2, $0, -1, Self.sqliteTransient) }
                sqlite3_bind_int(stmt, 3, 220)
                var rankIdx = 0
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let ptr = sqlite3_column_text(stmt, 0) else { continue }
                    let word = String(cString: ptr)
                    let lw = word.lowercased()
                    rankIdx += 1
                    if lw.count >= 2, let lastC = lw.last, endSet.contains(lastC) {
                        let pseudoLP = -8.0 - Double(rankIdx) * 0.03
                        out.append((lw, "", word, pseudoLP))
                    }
                }
            }
        } else {
            guard let stmt = glideZhStmt else { return [] }
            for sKey in startKeys {
                let sStr = String(sKey)
                for eKey in endKeys {
                    let eStr = String(eKey)
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                    sStr.withCString { sqlite3_bind_text(stmt, 1, $0, -1, Self.sqliteTransient) }
                    eStr.withCString { sqlite3_bind_text(stmt, 2, $0, -1, Self.sqliteTransient) }
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        guard let pfPtr = sqlite3_column_text(stmt, 0),
                              let pPtr = sqlite3_column_text(stmt, 1),
                              let wPtr = sqlite3_column_text(stmt, 2) else { continue }
                        let lp = sqlite3_column_double(stmt, 3)
                        out.append((String(cString: pfPtr), String(cString: pPtr), String(cString: wPtr), lp))
                    }
                }
            }
        }
        return out
    }

    // MARK: - T9 九宫格查询

    func queryT9(
        digits: String,
        lockedSyllables: [String],
        settings: LingxiSettings,
        contextBeforeCursor: String? = nil,
        limit: Int = 128
    ) -> (tokens: [PinyinToken], candidates: [PinyinCandidate], leftSyllables: [String]) {
        engineLock.lock()
        defer { engineLock.unlock() }
        let ctxMap = settings.bigramPredictionEnabled
            ? contextBonusMap(from: contextBeforeCursor, userLearning: settings.userLearningEnabled)
            : [:]
        let segs = segmenter.t9Segmentations(digits: digits, lockedPrefixes: lockedSyllables)
        let isSingleSyllableT9 = segs.contains { $0.count == 1 }
        let effectiveLimit: Int
        if limit >= 64 {
            effectiveLimit = isSingleSyllableT9 ? max(limit, 420) : max(limit, 260)
        } else {
            effectiveLimit = limit
        }
        let (bestSeg, rawOut) = evaluateSegmentations(
            segs,
            isT9: true,
            settings: settings,
            contextMap: ctxMap,
            rawContext: contextBeforeCursor,
            limit: effectiveLimit
        )
        var out = rawOut
        if settings.geoLocationBoostEnabled && digits.count >= 4 {
            let geoHits = GeoLocationContext.load().matchCandidates(rawInput: digits, isT9: true, limit: 2)
            if !geoHits.isEmpty {
                let geoCands = geoHits.map { entry in
                    PinyinCandidate(
                        word: entry.word,
                        py: entry.pinyin,
                        lp: entry.boostScore,
                        consumed: digits.count,
                        isExact: true,
                        source: .userLearned
                    )
                }
                let set = Set(geoCands.map(\.word))
                out = geoCands + out.filter { !set.contains($0.word) }
            }
        }
        let leftSyls = segmenter.candidateSyllablesForT9Prefix(digits, lockedCount: lockedSyllables.count, tokens: bestSeg)
        return (bestSeg, Array(out.prefix(effectiveLimit)), leftSyls)
    }

    // MARK: - 英文词表精确与前缀联想 (melt_eng)

    func exactEnglish(for raw: String) -> String? {
        engineLock.lock()
        defer { engineLock.unlock() }
        let lower = raw.lowercased()
        guard lower.count >= 2, lower.allSatisfy({ $0.isASCII && $0.isLetter }), let stmt = enExactStmt else {
            return nil
        }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        lower.withCString { sqlite3_bind_text(stmt, 1, $0, -1, Self.sqliteTransient) }
        if sqlite3_step(stmt) == SQLITE_ROW, let ptr = sqlite3_column_text(stmt, 0) {
            return String(cString: ptr)
        }
        return nil
    }

    func queryEnglish(prefix: String, limit: Int = 8) -> [String] {
        engineLock.lock()
        defer { engineLock.unlock() }
        let lower = prefix.lowercased()
        guard !lower.isEmpty, lower.allSatisfy({ $0.isASCII && $0.isLetter }), let stmt = enStmt else {
            return []
        }
        guard let lastScalar = lower.unicodeScalars.last,
              let nextScalar = UnicodeScalar(lastScalar.value + 1) else {
            return []
        }

        let startsUpper = prefix.first?.isUppercase == true
        var words: [String] = []
        var seen = Set<String>()

        func pushCandidate(_ rawWord: String) {
            var word = rawWord
            if startsUpper, let first = word.first, first.isLowercase {
                word = first.uppercased() + String(word.dropFirst())
            }
            if word != prefix && seen.insert(word.lowercased()).inserted {
                words.append(word)
            }
        }

        // 1. 高频缩略词补全与常见拼写纠错（dont->don't / teh->the / recieve->receive）
        if let corrected = Self.englishAutoCorrections[lower] {
            pushCandidate(corrected)
        }

        // 2. 标准词典前缀补全
        let upperBound = String(lower.dropLast()) + String(nextScalar)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        lower.withCString { sqlite3_bind_text(stmt, 1, $0, -1, Self.sqliteTransient) }
        upperBound.withCString { sqlite3_bind_text(stmt, 2, $0, -1, Self.sqliteTransient) }
        sqlite3_bind_int(stmt, 3, Int32(limit))

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let ptr = sqlite3_column_text(stmt, 0) else { continue }
            pushCandidate(String(cString: ptr))
            if words.count >= limit { break }
        }

        // 3. 无前缀命中时的 1-Edit 极速拼写容错（相邻颠倒 emial->email / 误重按 helllo->hello / 误多按 appple->apple）
        if words.isEmpty && lower.count >= 3 && lower.count <= 16, let exactStmt = enExactStmt {
            let chars = Array(lower)
            var probes: [String] = []
            probes.reserveCapacity(chars.count * 2 + 2)

            // 3a. 相邻字母颠倒（如 wrod -> word, iphnoe -> iphone）
            for i in 0..<(chars.count - 1) where chars[i] != chars[i + 1] {
                var swapped = chars
                swapped.swapAt(i, i + 1)
                probes.append(String(swapped))
            }
            // 3b. 连按重复字母折叠（如 helllo -> hello, goood -> good）
            var collapsed: [Character] = []
            var hadRun = false
            for ch in chars {
                if collapsed.count >= 2 && collapsed[collapsed.count - 1] == ch && collapsed[collapsed.count - 2] == ch {
                    hadRun = true
                    continue
                }
                collapsed.append(ch)
            }
            if hadRun {
                probes.append(String(collapsed))
            }
            // 3c. 单字误多按删除（如 keybaord / thiss）
            for i in 0..<chars.count {
                var trimmed = chars
                trimmed.remove(at: i)
                probes.append(String(trimmed))
            }

            var tried = Set<String>()
            for probe in probes where tried.insert(probe).inserted {
                sqlite3_reset(exactStmt)
                sqlite3_clear_bindings(exactStmt)
                probe.withCString { sqlite3_bind_text(exactStmt, 1, $0, -1, Self.sqliteTransient) }
                if sqlite3_step(exactStmt) == SQLITE_ROW, let ptr = sqlite3_column_text(exactStmt, 0) {
                    pushCandidate(String(cString: ptr))
                    if words.count >= min(3, limit) { break }
                }
            }
        }

        return Array(words.prefix(limit))
    }

    // MARK: - 二元上下文下一词预测 & 光标上文消歧图

    func predictNext(after prevWord: String, userLearning: Bool, limit: Int = 10) -> [String] {
        engineLock.lock()
        defer { engineLock.unlock() }
        guard !prevWord.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [String] = []

        if userLearning {
            for w in userLexicon.predictNext(after: prevWord, limit: limit) where seen.insert(w).inserted {
                out.append(w)
            }
        }
        for (w, _) in sysBigrams(after: prevWord) where seen.insert(w).inserted {
            out.append(w)
            if out.count >= limit { break }
        }
        return Array(out.prefix(limit))
    }

    private func contextBonusMap(from context: String?, userLearning: Bool) -> [String: Double] {
        guard let context, !context.isEmpty else { return [:] }
        // 1. 端侧零延迟结构化语境消歧（支持末尾数字+量词、星期/序数、高频动宾搭配）
        var merged = ContextualReranker.bonusMap(forContextBeforeCursor: context)

        // 2. 系统 Bigram + 个人习惯 Bigram
        let hanChars = context.suffix(8).filter { ch in
            guard let s = ch.unicodeScalars.first?.value else { return false }
            return (0x4E00...0x9FFF).contains(s)
        }
        guard !hanChars.isEmpty else { return merged }
        let arr = Array(hanChars)
        for len in stride(from: min(4, arr.count), through: 1, by: -1) {
            let sub = String(arr[(arr.count - len)..<arr.count])
            let scale = 1.0 + 0.15 * Double(len - 1)
            for (nextW, bonus) in combinedBigramMap(after: sub, userLearning: userLearning) {
                let weighted = bonus * scale
                if weighted > (merged[nextW] ?? 0.0) {
                    merged[nextW] = weighted
                }
            }
        }
        return merged
    }

    /// WowType `MERGED_PAIR_SCORE`：上文末尾 1~2 字与候选连起来本身是常用词（如 我+要=我要, 不+会=不会）时保底给 1.5 分。
    private func mergedPairBonus(context: String?, word: String) -> Double {
        guard let context, !context.isEmpty, !word.isEmpty, word.count <= 3, let stmt = wordExactStmt else {
            return 0.0
        }
        let hanChars = context.suffix(4).filter { ch in
            guard let s = ch.unicodeScalars.first?.value else { return false }
            return (0x4E00...0x9FFF).contains(s)
        }
        guard !hanChars.isEmpty else { return 0.0 }
        let arr = Array(hanChars)
        for len in stride(from: min(2, arr.count), through: 1, by: -1) {
            let combined = String(arr[(arr.count - len)..<arr.count]) + word
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            combined.withCString { sqlite3_bind_text(stmt, 1, $0, -1, Self.sqliteTransient) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                let lp = sqlite3_column_double(stmt, 0)
                if lp > -13.0 {
                    return Self.mergedPairScore
                }
            }
        }
        return 0.0
    }

    private func sysBigrams(after prevWord: String) -> [(next: String, bonus: Double)] {
        if let hit = sysBigramCache[prevWord] {
            return hit
        }
        guard let stmt = sysBigramStmt else { return [] }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        prevWord.withCString { sqlite3_bind_text(stmt, 1, $0, -1, Self.sqliteTransient) }

        var rows: [(String, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let ptr = sqlite3_column_text(stmt, 0) else { continue }
            let bonus = sqlite3_column_double(stmt, 1)
            rows.append((String(cString: ptr), bonus))
        }
        if sysBigramCache.count >= Self.maxBigramCacheEntries, let oldest = sysBigramOrder.first {
            sysBigramOrder.removeFirst()
            sysBigramCache.removeValue(forKey: oldest)
        }
        sysBigramCache[prevWord] = rows
        sysBigramOrder.append(prevWord)
        return rows
    }

    private func combinedBigramMap(after prevWord: String, userLearning: Bool) -> [String: Double] {
        guard !prevWord.isEmpty else { return [:] }
        var map: [String: Double] = [:]
        for (nextW, bonus) in sysBigrams(after: prevWord) {
            map[nextW] = bonus
        }
        if userLearning {
            for (nextW, bonus) in userLexicon.bigramBonuses(after: prevWord) {
                map[nextW] = max(map[nextW] ?? 0.0, bonus)
            }
        }
        return map
    }

    // MARK: - 纠错与候选评估

    private func evaluateTypoVariants(
        _ variants: [String],
        settings: LingxiSettings,
        contextMap: [String: Double]
    ) -> (seg: [PinyinToken], cands: [PinyinCandidate], topLP: Double)? {
        var bestFix: (seg: [PinyinToken], cands: [PinyinCandidate], topLP: Double)?
        for variant in variants {
            let segs = segmenter.segmentations(raw: variant, scheme: .quanpin)
            let completeSegs = segs.filter { $0.allSatisfy { $0.kind == .complete } }
            guard !completeSegs.isEmpty else { continue }
            let (seg, cands) = evaluateSegmentations(completeSegs, isT9: false, settings: settings, contextMap: contextMap, limit: 6)
            guard let top = cands.first, top.word.count >= 2 else { continue }
            if bestFix == nil || top.lp > bestFix!.topLP {
                bestFix = (seg, cands, top.lp)
            }
        }
        return bestFix
    }

    private func attemptTypoFix(
        raw: String,
        rawSeg: [PinyinToken],
        settings: LingxiSettings,
        contextMap: [String: Double]
    ) -> (seg: [PinyinToken], cands: [PinyinCandidate], topLP: Double)? {
        let chars = Array(raw)
        guard chars.count >= 3 else { return nil }
        var variants: [String] = []
        var seenVars = Set<String>()
        func addVariant(_ v: String, into list: inout [String]) {
            if seenVars.insert(v).inserted {
                list.append(v)
            }
        }

        // 1. 相邻字母换位（nihoa -> nihao）或误重击去重（niihao -> nihao）
        for idx in 0..<(chars.count - 1) {
            if chars[idx] != chars[idx + 1] {
                var sw = chars
                sw.swapAt(idx, idx + 1)
                addVariant(String(sw), into: &variants)
            } else {
                var dedup = chars
                dedup.remove(at: idx)
                addVariant(String(dedup), into: &variants)
            }
        }

        // 2. 单字符多余误触删除（zhkngguo 等多按了一键的情况）
        if chars.count >= 4 {
            for idx in 0..<chars.count {
                var del = chars
                del.remove(at: idx)
                addVariant(String(del), into: &variants)
            }
        }

        // 3. 疑似打错字符位置上的 QWERTY 邻键替换（zhkngguo k->o 等）
        var suspectIndices = Set<Int>()
        for tok in rawSeg where tok.kind == .invalid || (tok.kind == .partial && tok.raw.count == 1) {
            let p = max(0, min(chars.count - 1, tok.end - 1))
            suspectIndices.insert(max(0, p - 1))
            suspectIndices.insert(p)
            suspectIndices.insert(min(chars.count - 1, p + 1))
        }
        for pos in suspectIndices.sorted() {
            for rep in Self.adjacentKeys[chars[pos]] ?? [] {
                var sub = chars
                sub[pos] = rep
                addVariant(String(sub), into: &variants)
            }
        }

        if let hit = evaluateTypoVariants(variants, settings: settings, contextMap: contextMap) {
            return hit
        }

        // 4. 漏敲元音兜底插入（zhngguo -> zhongguo, shurfa -> shurufa）
        var insertPositions: [Int] = []
        var seenPos = Set<Int>()
        for pos in suspectIndices.sorted() {
            for idx in [pos, min(chars.count, pos + 1)] where seenPos.insert(idx).inserted {
                insertPositions.append(idx)
            }
        }
        var vowelVariants: [String] = []
        for pos in insertPositions {
            for vowel in "aeiou" {
                var ins = chars
                ins.insert(vowel, at: pos)
                addVariant(String(ins), into: &vowelVariants)
            }
        }
        return evaluateTypoVariants(vowelVariants, settings: settings, contextMap: contextMap)
    }

    private func attemptCompleteSwapOrNasalFix(
        raw: String,
        bestSeg: [PinyinToken],
        rawIsExact: Bool,
        rawTopLP: Double,
        settings: LingxiSettings,
        contextMap: [String: Double]
    ) -> (cand: PinyinCandidate, seg: [PinyinToken], promoteToFirst: Bool)? {
        let chars = Array(raw)
        enum VariantKind {
            case swapOrNasalOrFuzzy
            case adjacentInitial
        }
        var vars: [(text: String, kind: VariantKind)] = []
        var seen = Set<String>([raw])
        func add(_ v: String, kind: VariantKind) {
            if seen.insert(v).inserted {
                vars.append((v, kind))
            }
        }

        // 1. 相邻字母换位（meiyuo -> meiyou）
        for idx in 0..<(chars.count - 1) where chars[idx] != chars[idx + 1] {
            var sw = chars
            sw.swapAt(idx, idx + 1)
            add(String(sw), kind: .swapOrNasalOrFuzzy)
        }
        // 2. 前后鼻音单 g 误敲（shengme -> shenme, penyou -> pengyou）
        for idx in 0..<(chars.count - 1) where "aei".contains(chars[idx]) && chars[idx + 1] == "n" {
            if idx + 2 < chars.count && chars[idx + 2] == "g" {
                var dropG = chars
                dropG.remove(at: idx + 2)
                add(String(dropG), kind: .swapOrNasalOrFuzzy)
            } else {
                var addG = chars
                addG.insert("g", at: idx + 2)
                add(String(addG), kind: .swapOrNasalOrFuzzy)
            }
        }
        // 3. WowType fuzzy_fallback：模糊音未开时，对硬拼输入尝试平翘舌/前后鼻音音节替换（如 yingai->应该, zidao->知道）
        if settings.fuzzyFallbackEnabled {
            let sylTexts = bestSeg.map(\.text)
            for (sIdx, st) in sylTexts.enumerated() {
                var alts: [String] = []
                for (dg, sg) in [("zh", "z"), ("ch", "c"), ("sh", "s")] {
                    if st.hasPrefix(dg) {
                        alts.append(sg + String(st.dropFirst(2)))
                    } else if st.hasPrefix(sg) {
                        alts.append(dg + String(st.dropFirst(1)))
                    }
                }
                for (finA, finB) in [("ang", "an"), ("eng", "en"), ("ing", "in")] {
                    if st.hasSuffix(finA) {
                        alts.append(String(st.dropLast(3)) + finB)
                    } else if st.hasSuffix(finB) {
                        alts.append(String(st.dropLast(2)) + finA)
                    }
                }
                for alt in alts {
                    var rep = sylTexts
                    rep[sIdx] = alt
                    add(rep.joined(), kind: .swapOrNasalOrFuzzy)
                }
            }
        }
        // 4. 音节首字母邻键替换（mihao -> nihao）：仅在 <=3 音节时尝试，并严格校验原句得分，绝不劫持正常双词短语（如 tashuo/quna）！
        if bestSeg.count <= 3 {
            var sylOffset = 0
            for st in bestSeg.map(\.text) {
                if let first = st.first, let reps = Self.adjacentKeys[first], !reps.isEmpty {
                    for rep in reps {
                        var sub = chars
                        sub[sylOffset] = rep
                        add(String(sub), kind: .adjacentInitial)
                    }
                }
                sylOffset += st.count
            }
        }

        // 零 Beam-Search 直接整词查表（提速 ~30x，消除多音节输入每键跑几十次动态规划的卡顿！）
        let sylCount = Double(max(2, bestSeg.count))
        let avgPerSylLP = rawTopLP / sylCount
        var best: (cand: PinyinCandidate, seg: [PinyinToken], promoteToFirst: Bool, score: Double)?

        for item in vars {
            let vSegs = segmenter.segmentations(raw: item.text, scheme: .quanpin).filter { $0.allSatisfy { $0.kind == .complete } }
            guard !vSegs.isEmpty else { continue }
            for vSeg in vSegs where vSeg.count <= maxPhraseLen {
                let exactHits = lookup(tokens: vSeg, start: 0, end: vSeg.count, openEnd: false, isT9: false, settings: settings)
                guard let rawTop = exactHits.first, rawTop.isExact, rawTop.word.count >= 2 else { continue }
                let ctxBonus = (contextMap[rawTop.word] ?? 0.0) * Self.contextBigramWeight
                let effLP = rawTop.lp + ctxBonus
                guard effLP > -11.0 else { continue }

                let adjusted = PinyinCandidate(
                    word: rawTop.word,
                    py: rawTop.py,
                    lp: effLP,
                    consumed: raw.count,
                    isExact: false,
                    source: rawTop.source
                )

                switch item.kind {
                case .swapOrNasalOrFuzzy:
                    // 原输入若已拼成自然高分短语（如「他说」「去哪」avgPerSylLP > -9.3），不强抢首位，仅对真正错拼（美哟/生么/自到）置顶
                    let shouldPromote = (!rawIsExact && avgPerSylLP < -9.3) || (effLP > rawTopLP + 4.2)
                    let acceptSecondary = !rawIsExact && effLP > -9.2 && avgPerSylLP < -8.4
                    if shouldPromote || acceptSecondary {
                        let rankScore = effLP + (shouldPromote ? 2.0 : 0.0)
                        if best == nil || rankScore > best!.score {
                            best = (adjusted, vSeg, shouldPromote, rankScore)
                        }
                    }
                case .adjacentInitial:
                    // 邻键首字母替换（如 mihao -> 你好）门槛更严：原句必须是低分生硬单字拼接（avgPerSylLP < -10.1）且目标为超高频词才置顶；
                    // 否则仅温和放入第 2 候选位，彻底杜绝正常聊天短语被邻键词覆盖！
                    let shouldPromote = !rawIsExact && avgPerSylLP < -10.1 && effLP > -9.5
                    let acceptSecondary = !rawIsExact && avgPerSylLP < -9.4 && effLP > -8.8
                    if shouldPromote || acceptSecondary {
                        let rankScore = effLP + (shouldPromote ? 1.5 : -0.5)
                        if best == nil || rankScore > best!.score {
                            best = (adjusted, vSeg, shouldPromote, rankScore)
                        }
                    }
                }
            }
        }
        return best.map { ($0.cand, $0.seg, $0.promoteToFirst) }
    }

    private func attemptTailAdjacentFix(
        raw: String,
        rawTopLP: Double,
        settings: LingxiSettings,
        contextMap: [String: Double]
    ) -> PinyinCandidate? {
        let chars = Array(raw)
        guard chars.count >= 3 else { return nil }
        var best: PinyinCandidate?
        for pos in [chars.count - 1, chars.count - 2] {
            for rep in Self.adjacentKeys[chars[pos]] ?? [] {
                var sub = chars
                sub[pos] = rep
                let vSegs = segmenter.segmentations(raw: String(sub), scheme: .quanpin)
                    .filter { $0.allSatisfy { $0.kind == .complete } }
                for vSeg in vSegs where vSeg.count <= maxPhraseLen {
                    let hits = lookup(tokens: vSeg, start: 0, end: vSeg.count, openEnd: false, isT9: false, settings: settings)
                    if let top = hits.first, top.isExact, top.word.count >= 2 {
                        let effLP = top.lp + (contextMap[top.word] ?? 0.0) * Self.contextBigramWeight
                        if effLP > rawTopLP + 2.8 && effLP > -10.8 {
                            if best == nil || effLP > best!.lp {
                                best = PinyinCandidate(word: top.word, py: top.py, lp: effLP, consumed: raw.count, isExact: false, source: top.source)
                            }
                        }
                    }
                }
            }
        }
        return best
    }

    private func evaluateSegmentations(
        _ segs: [[PinyinToken]],
        isT9: Bool,
        settings: LingxiSettings,
        contextMap: [String: Double],
        rawContext: String? = nil,
        limit: Int
    ) -> (bestSeg: [PinyinToken], candidates: [PinyinCandidate]) {
        guard !segs.isEmpty else { return ([], []) }

        var sentences: [PinyinCandidate] = []
        var exactFull: [PinyinCandidate] = []
        var extendedFull: [PinyinCandidate] = []
        var bestSeg = segs[0]
        var bestScore = -Double.infinity
        let hasSingleSyllableSeg = segs.contains { $0.count == 1 && $0[0].kind != .invalid }

        for tokens in segs {
            let n = tokens.count
            var full = (n <= maxPhraseLen)
                ? lookup(tokens: tokens, start: 0, end: n, openEnd: true, isT9: isT9, settings: settings)
                : []
            // 关键防淹没机制：当输入本身是一个合法单音节（如 T9 `94`=yi/xi、`944`=zhi、`9826`=xuan）时，
            // 纯单键简拼切分（如 `[9,4]`、`[9,4,4]`）仅保留前 20 个超高频常用短语（如「一个」「这个」「喜欢」），
            // 严禁数千条低频简拼双字/三字词涌入 exactFull 把单音节常用字/生僻字（如 壹/薏/栀/祉/痔/煊）挤出候选池！
            if hasSingleSyllableSeg && n >= 2 && tokens.allSatisfy({ $0.kind == .partial && $0.raw.count == 1 }) {
                full = Array(full.filter { $0.isExact && $0.lp > -11.8 }.prefix(20))
            }
            let sents = (n > 1)
                ? decodeSentenceBeam(tokens: tokens, isT9: isT9, settings: settings, contextMap: contextMap, maxAlts: 2)
                : []
            sentences.append(contentsOf: sents)

            var fullBestExact = -Double.infinity
            for cand in full {
                var ctxBonus = (contextMap[cand.word] ?? 0.0) * Self.contextBigramWeight
                if settings.bigramPredictionEnabled && ctxBonus < Self.mergedPairScore && cand.isExact {
                    ctxBonus = max(ctxBonus, mergedPairBonus(context: rawContext, word: cand.word) * Self.contextBigramWeight)
                }
                let adjusted = ctxBonus > 0
                    ? PinyinCandidate(word: cand.word, py: cand.py, lp: cand.lp + ctxBonus, consumed: cand.consumed, isExact: cand.isExact, source: cand.source)
                    : cand
                if adjusted.isExact {
                    exactFull.append(adjusted)
                    if adjusted.lp > fullBestExact { fullBestExact = adjusted.lp }
                } else {
                    extendedFull.append(adjusted)
                }
            }

            let topScore = max(fullBestExact - Self.wordBoundaryPenalty, sents.first?.lp ?? -Double.infinity)
            if topScore > bestScore {
                bestScore = topScore
                bestSeg = tokens
            }
        }

        sentences.sort { $0.lp > $1.lp }
        exactFull.sort { $0.lp > $1.lp }
        extendedFull.sort { $0.lp > $1.lp }

        var uniqueSentences: [PinyinCandidate] = []
        var seenSentWords = Set<String>()
        for s in sentences where seenSentWords.insert(s.word).inserted {
            uniqueSentences.append(s)
        }
        var keptSentences: [PinyinCandidate] = []
        if let firstSent = uniqueSentences.first {
            keptSentences.append(firstSent)
            if uniqueSentences.count > 1, uniqueSentences[1].lp >= firstSent.lp - 1.5 {
                keptSentences.append(uniqueSentences[1])
            }
        }

        var output: [PinyinCandidate] = []
        var seenWords = Set<String>()
        func appendUnique(_ cand: PinyinCandidate) {
            if seenWords.insert(cand.word).inserted {
                output.append(cand)
            }
        }

        // WowType protect_exact_input：整输入正好是一个实在的精确词时，保护它排在第 1 位（不被单字拼凑或前缀补全抢走）
        let allComplete = bestSeg.allSatisfy { $0.kind == .complete }
        let protectExact = (exactFull.first.map { $0.lp > -17.0 } ?? false) && (allComplete || bestSeg.count == 1)

        if protectExact {
            for c in exactFull { appendUnique(c) }
            for c in keptSentences { appendUnique(c) }
        } else {
            if let topSent = keptSentences.first,
               exactFull.first.map({ topSent.lp > $0.lp - Self.wordBoundaryPenalty + 1e-9 }) ?? true {
                appendUnique(topSent)
            }
            for c in exactFull { appendUnique(c) }
            for c in keptSentences { appendUnique(c) }
        }

        // 单音节歧义词保护（如 xian -> 先/现/显/西安）：把双音节高权重精确词放入 Top-4
        if bestSeg.count == 1 && segs.count > 1,
           let multi = exactFull.first(where: { $0.word.count >= 2 && $0.lp > -13.5 }),
           !output.prefix(4).contains(where: { $0.word == multi.word }) {
            output.removeAll { $0.word == multi.word }
            output.insert(multi, at: min(3, output.count))
        }

        let prefixUpper = min(bestSeg.count - 1, maxPhraseLen)
        if bestSeg.count >= 2 && limit >= 12 {
            // 对齐微信/搜狗长句分字选词黄金排位：
            //   1) 整句与完整词 (exactFull / keptSentences) 居首；
            //   2) 紧跟最核心的 2~4 个前段词组（如「这里的」「这里」），方便分步组词；
            //   3) 立刻在首屏第 4~6 位放上首音节最高频单字（如「这」「我」），无需向右狂翻几十个词就能一键选单字！
            //   4) 随后展开完整首音节单字池（保底最高 140 字）与其余中间词组、前缀补全词。
            let singleChars = lookup(tokens: bestSeg, start: 0, end: 1, openEnd: false, isT9: isT9, settings: settings)
                .filter { $0.word.count == 1 }
            let guaranteedSingleQuota = min(singleChars.count, max(36, min(160, (limit * 3) / 5)))

            var primaryPrefixes: [PinyinCandidate] = []
            var secondaryPrefixes: [PinyinCandidate] = []
            if prefixUpper >= 2 {
                for k in stride(from: prefixUpper, through: 2, by: -1) {
                    let prefixCands = lookup(tokens: bestSeg, start: 0, end: k, openEnd: false, isT9: isT9, settings: settings)
                    // 最长前段与双字前段各提取 1~2 个精品词放在首屏单字之前，其余后置避免淹没单字
                    let frontCap = (k == 2) ? 2 : (k == prefixUpper ? 1 : 0)
                    let tierCap = (k >= 4) ? 3 : (k == 3 ? 4 : 6)
                    for (idx, c) in prefixCands.prefix(tierCap).enumerated() {
                        if idx < frontCap && primaryPrefixes.count < 3 {
                            primaryPrefixes.append(c)
                        } else {
                            secondaryPrefixes.append(c)
                        }
                    }
                    if prefixCands.count > tierCap {
                        secondaryPrefixes.append(contentsOf: prefixCands.dropFirst(tierCap).prefix(10))
                    }
                }
            }

            // 先放至多 3 个最常用前段词组（确保整句+常用词后紧邻首屏单字！）
            for c in primaryPrefixes {
                if output.count >= 4 { break }
                appendUnique(c)
            }

            // 首屏直出首音节前 4 个核心单字（如打 zhelidedongxi 首屏直接可见「这」「着」，实现丝滑逐字/分步上屏！）
            let firstScreenSingleCount = min(4, guaranteedSingleQuota)
            for c in singleChars.prefix(firstScreenSingleCount) { appendUnique(c) }

            // 紧随其后放次级前段词组与少量高分前缀补全
            for c in primaryPrefixes { appendUnique(c) }
            for c in secondaryPrefixes.prefix(8) {
                if output.count < max(8, limit - guaranteedSingleQuota) {
                    appendUnique(c)
                }
            }
            for c in extendedFull.prefix(8) {
                if output.count < max(8, limit - guaranteedSingleQuota) {
                    appendUnique(c)
                }
            }

            // 追加全部保底单字（最高 160 字），保证展开面板「只看单字」即使在 10 音节长句下也能找到所有常用字与次常用字！
            if guaranteedSingleQuota > firstScreenSingleCount {
                for c in singleChars[firstScreenSingleCount..<guaranteedSingleQuota] {
                    appendUnique(c)
                }
            }

            // 用剩余配额回填其余词组、扩展补全与生僻单字
            for c in secondaryPrefixes.dropFirst(8) {
                if output.count >= limit { break }
                appendUnique(c)
            }
            for c in extendedFull.dropFirst(8) {
                if output.count >= limit { break }
                appendUnique(c)
            }
            if singleChars.count > guaranteedSingleQuota {
                for c in singleChars.dropFirst(guaranteedSingleQuota) {
                    if output.count >= limit { break }
                    appendUnique(c)
                }
            }
        } else {
            for c in extendedFull { appendUnique(c) }
            if prefixUpper >= 1 {
                for k in stride(from: prefixUpper, through: 1, by: -1) {
                    let prefixCands = lookup(tokens: bestSeg, start: 0, end: k, openEnd: false, isT9: isT9, settings: settings)
                    for c in prefixCands { appendUnique(c) }
                    if output.count >= limit { break }
                }
            }
        }

        return (bestSeg, Array(output.prefix(limit)))
    }

    // MARK: - Beam-Search 二元语言模型整句解码

    private func decodeSentenceBeam(
        tokens: [PinyinToken],
        isT9: Bool,
        settings: LingxiSettings,
        contextMap: [String: Double],
        maxAlts: Int = 2
    ) -> [PinyinCandidate] {
        let n = tokens.count
        let beamWidth = 3
        let spanTopK = 4
        // 仅当末尾音节未打完（partial）时允许开放前缀补全，避免 zhongdi 被「重点」压过「种地」
        let allowTailExt = tokens.last?.kind == .partial

        struct BeamState {
            let score: Double
            let words: [String]
            let pys: [String]
        }

        var states: [[BeamState]] = Array(repeating: [], count: n + 1)
        states[0] = [BeamState(score: 0.0, words: [], pys: [])]

        for j in 1...n {
            var pool: [BeamState] = []
            let lower = max(0, j - maxPhraseLen)

            for i in lower..<j {
                guard !states[i].isEmpty else { continue }
                let spanCands = lookup(tokens: tokens, start: i, end: j, openEnd: (j == n && allowTailExt), isT9: isT9, settings: settings)
                let choices: [(word: String, py: String, baseScore: Double)]
                if !spanCands.isEmpty {
                    choices = spanCands.prefix(spanTopK).map { ($0.word, $0.py, $0.lp - Self.wordBoundaryPenalty) }
                } else if j - i == 1 && tokens[i].kind == .invalid {
                    choices = [(tokens[i].raw, "", Self.invalidLP)]
                } else {
                    continue
                }

                for prevState in states[i] {
                    let prevWord = prevState.words.last ?? ""
                    let bgMap = (settings.bigramPredictionEnabled && !prevWord.isEmpty)
                        ? combinedBigramMap(after: prevWord, userLearning: settings.userLearningEnabled)
                        : [:]

                    for choice in choices {
                        let bgBonus = bgMap[choice.word] ?? 0.0
                        let ctxBonus = (i == 0) ? ((contextMap[choice.word] ?? 0.0) * Self.contextBigramWeight) : 0.0
                        let nextScore = prevState.score + choice.baseScore + bgBonus + ctxBonus
                        var nextWords = prevState.words
                        nextWords.append(choice.word)
                        var nextPys = prevState.pys
                        if !choice.py.isEmpty { nextPys.append(choice.py) }
                        pool.append(BeamState(score: nextScore, words: nextWords, pys: nextPys))
                    }
                }
            }

            pool.sort { $0.score > $1.score }
            var kept: [BeamState] = []
            var seenLast = Set<String>()
            for st in pool {
                if let last = st.words.last, seenLast.insert(last).inserted {
                    kept.append(st)
                    if kept.count >= beamWidth { break }
                }
            }
            states[j] = kept
        }

        let consumed = tokens.last?.end ?? 0
        return states[n].prefix(maxAlts).map { st in
            PinyinCandidate(
                word: st.words.joined(),
                py: st.pys.joined(separator: "'"),
                lp: st.score,
                consumed: consumed,
                isExact: false,
                source: .dictionary
            )
        }
    }

    // MARK: - 片段查询

    private func lookup(
        tokens: [PinyinToken],
        start: Int,
        end: Int,
        openEnd: Bool,
        isT9: Bool,
        settings: LingxiSettings
    ) -> [PinyinCandidate] {
        let span = Array(tokens[start..<end])
        if span.contains(where: { $0.kind == .invalid }) {
            return []
        }

        let fuzzyMask = isT9 ? 0 : fuzzyBitmask(settings.fuzzy)
        let learnThreshold = settings.userLearningEnabled ? max(1, settings.autoLearnThreshold) : 0
        let key = CacheKey(
            isT9: isT9,
            tokens: span.map(\.text),
            kinds: span.map(\.kind),
            locked: span.map(\.lockedSyllable),
            openEnd: openEnd,
            fuzzyMask: fuzzyMask,
            learnThreshold: learnThreshold
        )

        let cachedRows: [CachedRow]
        if let hit = cache[key] {
            cachedRows = hit
        } else {
            cachedRows = fetchRows(span: span, openEnd: openEnd, isT9: isT9, settings: settings)
            storeInCache(key: key, rows: cachedRows)
        }

        let consumed = span.last?.end ?? 0
        return cachedRows.map {
            PinyinCandidate(
                word: $0.word,
                py: $0.py,
                lp: $0.lp,
                consumed: consumed,
                isExact: $0.exact,
                source: $0.isUser ? .userLearned : .dictionary
            )
        }
    }

    private func storeInCache(key: CacheKey, rows: [CachedRow]) {
        // 单次极端超大桶直接跳过缓存，防止单个九宫格桶瞬间占满内存预算
        guard rows.count <= Self.maxTotalCachedRows / 2 else { return }
        if let existing = cache.removeValue(forKey: key) {
            totalCachedRows = max(0, totalCachedRows - existing.count)
            cacheOrder.removeAll { $0 == key }
        }
        while (cache.count >= Self.maxCacheEntries || totalCachedRows + rows.count > Self.maxTotalCachedRows),
              let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            if let removed = cache.removeValue(forKey: oldest) {
                totalCachedRows = max(0, totalCachedRows - removed.count)
            }
        }
        cache[key] = rows
        cacheOrder.append(key)
        totalCachedRows += rows.count
    }

    private func fetchRows(
        span: [PinyinToken],
        openEnd: Bool,
        isT9: Bool,
        settings: LingxiSettings
    ) -> [CachedRow] {
        let abbrs: [String]
        if isT9 {
            let t9Abbr = span.compactMap { tok -> Character? in
                if let locked = tok.lockedSyllable, let first = locked.first {
                    return PinyinSegmenter.t9Code(for: String(first)).first
                }
                return tok.text.first
            }
            abbrs = t9Abbr.count == span.count ? [String(t9Abbr)] : []
        } else {
            abbrs = expandedAbbrs(for: span, fuzzy: settings.fuzzy)
        }
        guard !abbrs.isEmpty else { return [] }

        var exactRows: [CachedRow] = []
        var extendedRows: [CachedRow] = []
        var bestByWord: [String: CachedRow] = [:]

        func consider(word: String, py: String, baseLP: Double, isUser: Bool) {
            let syls = py.split(separator: "'").map(String.init)
            guard syls.count == span.count else { return }
            var allExact = true
            var usedFuzzy = false
            var compPenalty = 0.0
            for idx in 0..<span.count {
                let tok = span[idx]
                let syl = syls[idx]
                let allowPrefix = openEnd && idx == span.count - 1
                let match = isT9
                    ? matchT9Token(tok, syllable: syl, allowPrefix: allowPrefix)
                    : match26Token(tok, syllable: syl, allowPrefix: allowPrefix, fuzzy: settings.fuzzy)
                guard match.matched else { return }
                allExact = allExact && match.exact
                usedFuzzy = usedFuzzy || match.usedFuzzy
                // WowType 补全长度惩罚：多字母残缺音节（如 weish 中的 sh）按缺失字母数扣分，让「为啥」胜过「卫生」
                if !isT9 && tok.kind == .partial && tok.text.count >= 2 && syl.count > tok.text.count {
                    compPenalty += Self.partialCompletionPenalty * Double(syl.count - tok.text.count)
                }
            }
            let finalLP = baseLP + (usedFuzzy ? Self.fuzzyPenalty : 0.0) - compPenalty
            let row = CachedRow(word: word, py: py, lp: finalLP, exact: allExact, isUser: isUser)
            if let existing = bestByWord[word] {
                // 致命缺陷修复：精确音节匹配 (exact == true) 必须永远优先于开放前缀补全 (exact == false)！
                // 此前仅比较 existing.lp >= row.lp，导致「这」(zhei -6.064) 在 openEnd=true 时先把「这」锁死为 exact=false，
                // 随后真正的精确匹配「这」(zhe -6.064) 因 lp 相等被直接丢弃，致使打 zhe 时「这」沉到 90+ 生僻字之后彻底打不出来！
                // 同理修复「嗯」(eng 遮蔽 en)、「称」(cheng 遮蔽 chen)、「得」(dei 遮蔽 de) 等全部 23 组多音前缀遮蔽问题！
                if existing.exact && !row.exact {
                    return
                }
                if existing.exact == row.exact && existing.lp >= row.lp {
                    return
                }
            }
            bestByWord[word] = row
        }

        var userBoostByKey: [String: Double] = [:]
        if settings.userLearningEnabled {
            for u in userLexicon.lookup(abbrList: abbrs, isT9: isT9, minFrequency: settings.autoLearnThreshold) {
                userBoostByKey["\(u.word)|\(u.py)"] = u.boost
                consider(word: u.word, py: u.py, baseLP: -10.5 + u.boost, isUser: true)
            }
        }

        let stmt = isT9 ? t9Stmt : abbrStmt
        if let stmt {
            for abbr in abbrs {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                abbr.withCString { sqlite3_bind_text(stmt, 1, $0, -1, Self.sqliteTransient) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let wPtr = sqlite3_column_text(stmt, 0),
                          let pPtr = sqlite3_column_text(stmt, 1) else { continue }
                    let word = String(cString: wPtr)
                    let py = String(cString: pPtr)
                    let lp = sqlite3_column_double(stmt, 2)
                    let boost = userBoostByKey["\(word)|\(py)"] ?? 0.0
                    consider(word: word, py: py, baseLP: lp + boost, isUser: boost > 0)
                }
            }
        }

        // 合并轻量补充词包：现代口语热词 + 四字成语 + Unicode BMP 全量扩展生僻单字（如 幵/龘/人名古籍字）
        for abbr in abbrs {
            for item in SupplementLexicon.shared.phrases(forAbbr: abbr, isT9: isT9, nearDatabaseURL: dbURL) {
                let boost = userBoostByKey["\(item.word)|\(item.py)"] ?? 0.0
                consider(word: item.word, py: item.py, baseLP: item.lp + boost, isUser: boost > 0)
            }
        }
        if span.count == 1 {
            let tok = span[0]
            for syl in PinyinSyllables.all {
                let match = isT9
                    ? matchT9Token(tok, syllable: syl, allowPrefix: false)
                    : match26Token(tok, syllable: syl, allowPrefix: false, fuzzy: settings.fuzzy)
                guard match.matched && match.exact else { continue }
                // 纯单声母简拼（如仅敲下 'y' 或 T9 '9' 且并非完整音节）不展开上千生僻单字；敲定完整音节（如 yi / jian / da / 94 / 5426）时 100% 完整返回！
                if tok.kind == .partial && tok.lockedSyllable == nil && syl != tok.text {
                    if isT9 && (segmenter.sylToT9[syl] ?? PinyinSegmenter.t9Code(for: syl)) != tok.text {
                        continue
                    } else if !isT9 {
                        continue
                    }
                }
                let rareStr = SupplementLexicon.shared.rareCharacters(forSyllable: syl, nearDatabaseURL: dbURL)
                guard !rareStr.isEmpty else { continue }
                var idx = 0
                for ch in rareStr {
                    let w = String(ch)
                    let boost = userBoostByKey["\(w)|\(syl)"] ?? 0.0
                    let baseLP = (boost > 0) ? (-10.5 + boost) : (-22.0 - Double(idx) * 0.008)
                    consider(word: w, py: syl, baseLP: baseLP, isUser: boost > 0)
                    idx += 1
                }
            }
        }

        for row in bestByWord.values {
            if row.exact { exactRows.append(row) }
            else { extendedRows.append(row) }
        }
        exactRows.sort { $0.lp > $1.lp }
        extendedRows.sort { $0.lp > $1.lp }
        return exactRows + extendedRows
    }

    // MARK: - 音节匹配

    private func matchT9Token(_ token: PinyinToken, syllable: String, allowPrefix: Bool) -> (matched: Bool, exact: Bool, usedFuzzy: Bool) {
        if token.kind == .invalid { return (false, false, false) }
        if let locked = token.lockedSyllable {
            let ok = (syllable == locked)
            return (ok, ok, false)
        }
        let code = segmenter.sylToT9[syllable] ?? PinyinSegmenter.t9Code(for: syllable)
        if code == token.text { return (true, true, false) }
        if (token.kind == .partial || allowPrefix) && code.hasPrefix(token.text) {
            return (true, token.kind == .partial, false)
        }
        return (false, false, false)
    }

    private func match26Token(
        _ token: PinyinToken,
        syllable: String,
        allowPrefix: Bool,
        fuzzy: FuzzyPinyinOptions
    ) -> (matched: Bool, exact: Bool, usedFuzzy: Bool) {
        if token.kind == .invalid { return (false, false, false) }
        if syllable == token.text { return (true, true, false) }
        if (token.kind == .partial || allowPrefix) && syllable.hasPrefix(token.text) {
            return (true, token.kind == .partial, false)
        }
        guard fuzzy.isAnyEnabled else { return (false, false, false) }

        let normToken = normalizeFuzzy(token.text, options: fuzzy)
        let normSyl = normalizeFuzzy(syllable, options: fuzzy)
        if normSyl == normToken { return (true, true, true) }
        if (token.kind == .partial || allowPrefix) && normSyl.hasPrefix(normToken) {
            return (true, token.kind == .partial, true)
        }
        return (false, false, false)
    }

    private func normalizeFuzzy(_ s: String, options: FuzzyPinyinOptions) -> String {
        var r = s
        if options.zhZ && r.hasPrefix("zh") { r = "z" + String(r.dropFirst(2)) }
        else if options.chC && r.hasPrefix("ch") { r = "c" + String(r.dropFirst(2)) }
        else if options.shS && r.hasPrefix("sh") { r = "s" + String(r.dropFirst(2)) }
        else if options.nl && r.hasPrefix("n") { r = "l" + String(r.dropFirst(1)) }
        else if options.rl && r.hasPrefix("r") { r = "l" + String(r.dropFirst(1)) }
        else if options.huangWang && r == "huang" { r = "wang" }
        else if options.fh && r.hasPrefix("f") { r = "h" + String(r.dropFirst(1)) }

        if options.ianIang && r.hasSuffix("iang") { r = String(r.dropLast(1)) }
        else if options.uanUang && r.hasSuffix("uang") { r = String(r.dropLast(1)) }
        else if options.anAng && r.hasSuffix("ang") { r = String(r.dropLast(1)) }
        else if options.anAi && r.hasSuffix("ai") { r = String(r.dropLast(1)) + "n" }
        else if options.unIong && r.hasSuffix("iong") { r = String(r.dropLast(4)) + "un" }
        else if options.unIong && r == "yong" { r = "yun" }
        else if options.unOng && r.hasSuffix("un") &&
                    !r.hasPrefix("j") && !r.hasPrefix("q") && !r.hasPrefix("x") && !r.hasPrefix("y") {
            r = String(r.dropLast(2)) + "ong"
        }

        if options.engOng && !r.hasSuffix("iong") && r != "yong" && r.hasSuffix("ong") {
            r = String(r.dropLast(3)) + "eng"
        }
        if options.enEng && r.hasSuffix("eng") { r = String(r.dropLast(1)) }
        if options.inIng && r.hasSuffix("ing") { r = String(r.dropLast(1)) }
        return r
    }

    private func expandedAbbrs(for span: [PinyinToken], fuzzy: FuzzyPinyinOptions) -> [String] {
        var abbrs = [""]
        for token in span {
            guard let ch = token.text.first else { return [] }
            var choices: [Character] = [ch]
            if fuzzy.nl {
                if ch == "n" { choices.append("l") }
                else if ch == "l" { choices.append("n") }
            }
            if fuzzy.rl {
                if ch == "r" { choices.append("l") }
                else if ch == "l" && !choices.contains("r") { choices.append("r") }
            }
            if fuzzy.fh {
                if ch == "f" { choices.append("h") }
                else if ch == "h" { choices.append("f") }
            }
            if fuzzy.huangWang {
                if "huang".hasPrefix(token.text) && !choices.contains("w") {
                    choices.append("w")
                } else if "wang".hasPrefix(token.text) && !choices.contains("h") {
                    choices.append("h")
                }
            }
            var next: [String] = []
            for prefix in abbrs {
                for c in choices {
                    next.append(prefix + String(c))
                    if next.count >= 12 { break }
                }
                if next.count >= 12 { break }
            }
            abbrs = next
        }
        return abbrs
    }

    private func fuzzyBitmask(_ f: FuzzyPinyinOptions) -> Int {
        var m = 0
        if f.zhZ { m |= 1 << 0 }
        if f.chC { m |= 1 << 1 }
        if f.shS { m |= 1 << 2 }
        if f.nl { m |= 1 << 3 }
        if f.rl { m |= 1 << 4 }
        if f.fh { m |= 1 << 5 }
        if f.anAng { m |= 1 << 6 }
        if f.enEng { m |= 1 << 7 }
        if f.inIng { m |= 1 << 8 }
        if f.ianIang { m |= 1 << 9 }
        if f.uanUang { m |= 1 << 10 }
        if f.unOng { m |= 1 << 11 }
        if f.anAi { m |= 1 << 12 }
        if f.huangWang { m |= 1 << 13 }
        if f.unIong { m |= 1 << 14 }
        if f.engOng { m |= 1 << 15 }
        return m
    }
}
