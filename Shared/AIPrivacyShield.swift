import Foundation

// MARK: - 1. 端侧 AI 隐私脱敏护盾（发送外部大模型前本地自动替换敏感信息，流式回传后本地无感还原）

/// 端侧 AI 隐私脱敏与还原引擎（纯逻辑无网络，App 与键盘扩展共享）。
enum AIPrivacyShield {
    struct RedactionHit: Identifiable, Equatable {
        let id: String
        let placeholder: String
        let original: String
        let category: String

        init(placeholder: String, original: String, category: String) {
            self.id = placeholder
            self.placeholder = placeholder
            self.original = original
            self.category = category
        }
    }

    struct RedactionResult: Equatable {
        let sanitizedText: String
        let hits: [RedactionHit]
        let mapping: [String: String]

        var hasRedactions: Bool { !hits.isEmpty }
    }

    /// 对发往大模型的文本进行本地脱敏：自动识别自定义隐私词、密钥、身份证、邮箱、手机号、银行卡与 IPv4。
    static func sanitize(_ text: String, customTerms: [String] = []) -> RedactionResult {
        guard !text.isEmpty else {
            return RedactionResult(sanitizedText: text, hits: [], mapping: [:])
        }
        var working = text
        var originalToPlaceholder: [String: String] = [:]
        var placeholderToOriginal: [String: String] = [:]
        var hits: [RedactionHit] = []
        var counters: [String: Int] = [:]

        func tokenFor(original: String, tag: String, category: String) -> String {
            if let existing = originalToPlaceholder[original] {
                return existing
            }
            let next = (counters[tag] ?? 0) + 1
            counters[tag] = next
            let placeholder = "[\(tag)_\(next)]"
            originalToPlaceholder[original] = placeholder
            placeholderToOriginal[placeholder] = original
            hits.append(RedactionHit(placeholder: placeholder, original: original, category: category))
            return placeholder
        }

        // 1. 用户自定义隐私词（按长度降序，避免短词破坏长词）
        let cleanedTerms = Array(
            Set(customTerms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count >= 2 })
        ).sorted { $0.count > $1.count }
        for term in cleanedTerms {
            if working.contains(term) {
                let ph = tokenFor(original: term, tag: "PRIV", category: "自定义隐私词")
                working = working.replacingOccurrences(of: term, with: ph)
            }
        }

        // 2. 正则规则扫描（先扫描高特征长串，避免被手机号等短规则误切）
        let rules: [(pattern: String, tag: String, category: String, validator: ((String) -> Bool)?)] = [
            (#"(?:sk-[A-Za-z0-9_\-]{16,}|AIza[0-9A-Za-z_\-]{20,}|ghp_[A-Za-z0-9]{20,}|lx_live_[A-Za-z0-9_\-]{12,}|lxb_live_[A-Za-z0-9_\-]{12,})"#, "SECRET", "API 密钥", nil),
            (#"(?<!\d)[1-9]\d{5}(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx](?!\d)"#, "ID", "身份证号", nil),
            (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "EMAIL", "电子邮箱", nil),
            (#"(?<!\d)1[3-9]\d{9}(?!\d)"#, "PHONE", "手机号", nil),
            (#"(?<!\d)(?:\d[ -]?){15,19}(?!\d)"#, "CARD", "银行卡号", { candidate in
                let digits = candidate.filter(\.isNumber)
                guard digits.count >= 15 && digits.count <= 19 else { return false }
                return Self.passesLuhn(digits)
            }),
            (#"(?<!\d)(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?!\d)"#, "IP", "IP 地址", nil),
        ]

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let ns = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            var rebuilt = ""
            var cursor = 0
            for m in matches {
                let r = m.range
                guard r.location >= cursor else { continue }
                let segment = ns.substring(with: r)
                // 避免重复替换已经生成的占位符内部文本
                if segment.hasPrefix("[") && segment.hasSuffix("]") { continue }
                if let validator = rule.validator, !validator(segment) { continue }
                rebuilt += ns.substring(with: NSRange(location: cursor, length: r.location - cursor))
                rebuilt += tokenFor(original: segment, tag: rule.tag, category: rule.category)
                cursor = r.location + r.length
            }
            if cursor > 0 {
                rebuilt += ns.substring(from: cursor)
                working = rebuilt
            }
        }

        return RedactionResult(sanitizedText: working, hits: hits, mapping: placeholderToOriginal)
    }

    /// 批量脱敏多轮对话（保持跨轮次一致的占位符编号，便于上下文连续指代）。
    static func sanitizeTurns(_ turns: [AIChatTurn], customTerms: [String] = []) -> (turns: [AIChatTurn], mapping: [String: String], hits: [RedactionHit]) {
        guard !turns.isEmpty else { return (turns, [:], []) }
        let sentinel = "\u{241E}\u{241F}" // 极低碰撞率多轮合并分隔符
        let combined = turns.map(\.content).joined(separator: sentinel)
        let res = sanitize(combined, customTerms: customTerms)
        guard res.hasRedactions else { return (turns, [:], []) }
        let parts = res.sanitizedText.components(separatedBy: sentinel)
        guard parts.count == turns.count else {
            // 兜底：逐条独立脱敏并合并映射
            var mergedMap: [String: String] = [:]
            var mergedHits: [RedactionHit] = []
            let mappedTurns = turns.map { t -> AIChatTurn in
                var copy = t
                let r = sanitize(t.content, customTerms: customTerms)
                copy.content = r.sanitizedText
                for (k, v) in r.mapping { mergedMap[k] = v }
                mergedHits.append(contentsOf: r.hits)
                return copy
            }
            return (mappedTurns, mergedMap, mergedHits)
        }
        var outTurns: [AIChatTurn] = []
        for (idx, t) in turns.enumerated() {
            var copy = t
            copy.content = parts[idx]
            outTurns.append(copy)
        }
        return (outTurns, res.mapping, res.hits)
    }

    /// 将大模型返回文本中的占位符还原为本地原始敏感值。
    static func restore(_ text: String, mapping: [String: String]) -> String {
        guard !mapping.isEmpty, text.contains("[") else { return text }
        var out = text
        for (placeholder, original) in mapping {
            if out.contains(placeholder) {
                out = out.replacingOccurrences(of: placeholder, with: original)
            }
        }
        return out
    }

    /// 流式输出安全还原缓冲器：当分片在 `[PHONE_1]` 中间截断时暂缓尾部未闭合 `[` 片段，防止占位符闪烁泄露。
    struct StreamingRestoreBuffer {
        private let mapping: [String: String]
        private var pending = ""
        private let maxTokenLen: Int

        init(mapping: [String: String]) {
            self.mapping = mapping
            self.maxTokenLen = max(12, (mapping.keys.map(\.count).max() ?? 12) + 2)
        }

        mutating func push(_ delta: String) -> String {
            guard !mapping.isEmpty else { return delta }
            pending += delta
            // 先替换已经完整闭合的占位符
            pending = AIPrivacyShield.restore(pending, mapping: mapping)

            // 检查末尾是否存在尚未闭合的 `[`（且距离尾部不超过 maxTokenLen）
            if let openIdx = pending.lastIndex(of: "[") {
                let tail = pending[openIdx...]
                if !tail.contains("]") && tail.count < maxTokenLen {
                    let safeOut = String(pending[..<openIdx])
                    pending = String(tail)
                    return safeOut
                }
            }
            let out = pending
            pending = ""
            return out
        }

        mutating func finish() -> String {
            guard !pending.isEmpty else { return "" }
            let out = AIPrivacyShield.restore(pending, mapping: mapping)
            pending = ""
            return out
        }
    }

    private static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        var shouldDouble = false
        for ch in digits.reversed() {
            guard let d = ch.wholeNumberValue else { return false }
            if shouldDouble {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += d
            }
            shouldDouble.toggle()
        }
        return sum % 10 == 0
    }
}

// MARK: - 2. 纯 Swift 逐字红绿 Diff 差分引擎（用于润色对比、语气微调前后可视化）

enum AITextDiffEngine {
    enum Kind: Equatable {
        case equal
        case deleted
        case inserted
    }

    struct Segment: Identifiable, Equatable {
        let id: Int
        let kind: Kind
        let text: String
    }

    struct DiffReport: Equatable {
        let segments: [Segment]
        let deletedChars: Int
        let insertedChars: Int
        let unchangedChars: Int

        var changeRatio: Double {
            let denom = max(1, unchangedChars + deletedChars + insertedChars)
            return Double(deletedChars + insertedChars) / Double(denom)
        }
    }

    /// 计算两段文本的红绿差分（短中文本精确到字，超长文本自动降级到行/句级别防止 O(N*M) 卡顿）。
    static func diff(original: String, revised: String) -> DiffReport {
        if original == revised {
            let segs = original.isEmpty ? [] : [Segment(id: 0, kind: .equal, text: original)]
            return DiffReport(segments: segs, deletedChars: 0, insertedChars: 0, unchangedChars: original.count)
        }
        let a = Array(original)
        let b = Array(revised)

        // 超长文本（> 450 字）改为按分句/换行粒度做 LCS，保证 iOS 端毫秒级响应
        if a.count * b.count > 180_000 {
            let aChunks = splitIntoSentenceChunks(original)
            let bChunks = splitIntoSentenceChunks(revised)
            return buildReport(from: lcsDiff(aChunks, bChunks))
        }

        let rawOps = lcsDiff(a.map(String.init), b.map(String.init))
        return buildReport(from: rawOps)
    }

    private static func splitIntoSentenceChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var cur = ""
        let breaks: Set<Character> = ["\n", "。", "！", "？", "；", ".", "!", "?", ";"]
        for ch in text {
            cur.append(ch)
            if breaks.contains(ch) {
                chunks.append(cur)
                cur = ""
            }
        }
        if !cur.isEmpty { chunks.append(cur) }
        return chunks
    }

    private static func lcsDiff(_ a: [String], _ b: [String]) -> [(Kind, String)] {
        let n = a.count
        let m = b.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    if a[i] == b[j] {
                        dp[i][j] = dp[i + 1][j + 1] + 1
                    } else {
                        dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                    }
                }
            }
        }
        var ops: [(Kind, String)] = []
        var i = 0
        var j = 0
        while i < n || j < m {
            if i < n && j < m && a[i] == b[j] {
                ops.append((.equal, a[i]))
                i += 1
                j += 1
            } else if j < m && (i == n || dp[i][j + 1] >= dp[i + 1][j]) {
                ops.append((.inserted, b[j]))
                j += 1
            } else {
                ops.append((.deleted, a[i]))
                i += 1
            }
        }
        return ops
    }

    private static func buildReport(from ops: [(Kind, String)]) -> DiffReport {
        var merged: [Segment] = []
        var deleted = 0
        var inserted = 0
        var unchanged = 0

        for (kind, txt) in ops where !txt.isEmpty {
            switch kind {
            case .equal: unchanged += txt.count
            case .deleted: deleted += txt.count
            case .inserted: inserted += txt.count
            }
            if let last = merged.last, last.kind == kind {
                merged[merged.count - 1] = Segment(id: last.id, kind: kind, text: last.text + txt)
            } else {
                merged.append(Segment(id: merged.count, kind: kind, text: txt))
            }
        }
        return DiffReport(segments: merged, deletedChars: deleted, insertedChars: inserted, unchangedChars: unchanged)
    }
}

// MARK: - 3. 主流大模型参考单价与 Token 成本估算器

enum AICostEstimator {
    struct Pricing: Equatable {
        let inputPerMillionUSD: Double
        let outputPerMillionUSD: Double
        let isLocalFree: Bool
    }

    static func pricing(forModel model: String, provider: String = "") -> Pricing {
        let m = model.lowercased()
        let p = provider.lowercased()
        if p.contains("ollama") || m.contains(":7b") || m.contains(":8b") || m.contains(":14b") || m.contains(":32b") || m.contains("local") {
            return Pricing(inputPerMillionUSD: 0, outputPerMillionUSD: 0, isLocalFree: true)
        }
        if m.contains("gemini-2.5-flash-lite") || m.contains("flash-lite") {
            return Pricing(inputPerMillionUSD: 0.10, outputPerMillionUSD: 0.40, isLocalFree: false)
        }
        if m.contains("gemini-2.5-pro") || m.contains("gemini-4") {
            return Pricing(inputPerMillionUSD: 1.25, outputPerMillionUSD: 10.0, isLocalFree: false)
        }
        if m.contains("gemini") {
            return Pricing(inputPerMillionUSD: 0.30, outputPerMillionUSD: 2.50, isLocalFree: false)
        }
        if m.contains("deepseek-reasoner") || m.contains("deepseek-r1") {
            return Pricing(inputPerMillionUSD: 0.55, outputPerMillionUSD: 2.19, isLocalFree: false)
        }
        if m.contains("deepseek") {
            return Pricing(inputPerMillionUSD: 0.27, outputPerMillionUSD: 1.10, isLocalFree: false)
        }
        if m.contains("gpt-4o-mini") || m.contains("gpt-5-mini") || m.contains("gpt-4.1-mini") {
            return Pricing(inputPerMillionUSD: 0.15, outputPerMillionUSD: 0.60, isLocalFree: false)
        }
        if m.contains("o3-mini") || m.contains("o4-mini") {
            return Pricing(inputPerMillionUSD: 1.10, outputPerMillionUSD: 4.40, isLocalFree: false)
        }
        if m.contains("o1") || m.contains("o3") {
            return Pricing(inputPerMillionUSD: 10.0, outputPerMillionUSD: 40.0, isLocalFree: false)
        }
        if m.contains("gpt-4o") || m.contains("gpt-5") || m.contains("gpt-4.1") {
            return Pricing(inputPerMillionUSD: 2.50, outputPerMillionUSD: 10.0, isLocalFree: false)
        }
        if m.contains("claude") && m.contains("opus") {
            return Pricing(inputPerMillionUSD: 15.0, outputPerMillionUSD: 75.0, isLocalFree: false)
        }
        if m.contains("claude") && m.contains("haiku") {
            return Pricing(inputPerMillionUSD: 0.80, outputPerMillionUSD: 4.00, isLocalFree: false)
        }
        if m.contains("claude") {
            return Pricing(inputPerMillionUSD: 3.0, outputPerMillionUSD: 15.0, isLocalFree: false)
        }
        if m.contains("grok") {
            return Pricing(inputPerMillionUSD: 2.0, outputPerMillionUSD: 10.0, isLocalFree: false)
        }
        if m.contains("kimi") || m.contains("moonshot") {
            return Pricing(inputPerMillionUSD: 0.60, outputPerMillionUSD: 2.50, isLocalFree: false)
        }
        if m.contains("qwen-turbo") || m.contains("glm-4-flash") || m.contains("llama-3.1-8b") {
            return Pricing(inputPerMillionUSD: 0.08, outputPerMillionUSD: 0.20, isLocalFree: false)
        }
        if m.contains("qwen") || m.contains("qwq") || m.contains("doubao") || m.contains("glm") || m.contains("minimax") {
            return Pricing(inputPerMillionUSD: 0.40, outputPerMillionUSD: 1.20, isLocalFree: false)
        }
        // 通用 OpenAI 兼容中转默认估算单价
        return Pricing(inputPerMillionUSD: 0.50, outputPerMillionUSD: 1.50, isLocalFree: false)
    }

    /// 计算单条账本记录的估算美元费用（有真实 Token 优先用真实值，无真实 Token 时按中文混合字符经验折算）。
    static func estimateUSD(for entry: AIUsageLedgerEntry) -> Double {
        let rate = pricing(forModel: entry.model, provider: entry.provider)
        if rate.isLocalFree { return 0 }
        let inTok = Double(entry.promptTokens ?? max(1, Int(Double(entry.inputChars) * 0.75)))
        let outTok = Double(entry.completionTokens ?? max(1, Int(Double(entry.outputChars + entry.thoughtChars) * 0.75)))
        return (inTok / 1_000_000.0) * rate.inputPerMillionUSD + (outTok / 1_000_000.0) * rate.outputPerMillionUSD
    }

    static func totalEstimatedUSD(for entries: [AIUsageLedgerEntry]) -> Double {
        entries.reduce(0.0) { $0 + estimateUSD(for: $1) }
    }

    /// 统计当前自然月（本地日历）内的预估美元费用，供月度预算进度与预警使用。
    static func currentMonthEstimatedUSD(for entries: [AIUsageLedgerEntry], now: Date = Date()) -> Double {
        let cal = Calendar.current
        let nowComps = cal.dateComponents([.year, .month], from: now)
        return entries.reduce(0.0) { acc, entry in
            let d = Date(timeIntervalSince1970: TimeInterval(entry.timestamp))
            let comps = cal.dateComponents([.year, .month], from: d)
            guard comps.year == nowComps.year && comps.month == nowComps.month else { return acc }
            return acc + estimateUSD(for: entry)
        }
    }

    static func formatCNY(_ usd: Double, fxRate: Double = 7.25) -> String {
        let cny = usd * fxRate
        if cny < 0.005 { return "¥0.00" }
        if cny < 0.1 { return String(format: "¥%.3f", cny) }
        return String(format: "¥%.2f", cny)
    }
}

// MARK: - 4. 全路由模型基准测速结果

struct AIModelBenchmarkResult: Identifiable, Equatable {
    let id: String
    let slotLabel: String
    let profileName: String
    let model: String
    let provider: AIProvider
    let ok: Bool
    let ttftMs: Int
    let totalMs: Int
    let outputChars: Int
    let errorMessage: String?

    var charsPerSecond: Double {
        guard ok, totalMs > 0 else { return 0 }
        return Double(outputChars) / (Double(totalMs) / 1000.0)
    }
}
