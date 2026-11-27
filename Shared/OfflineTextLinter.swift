import Foundation

/// 100% 纯端侧离线「中文文案、排版与 AI 腔实时质检仪」（对标 textlint / pangu / 中文文案排版指北）：
/// - 0 毫秒网络依赖、0 Token 消耗、100% 留存本机；
/// - 覆盖 5 大维度：手滑重复字词、AI 味/官腔词汇（联动个人文风 DNA）、中文排版规范（盘古之白与中英标点混用）、
///   隐私外泄红灯（联动 AIPrivacyShield）、长难句与口播阅读时长估算；
/// - 内置无损自动排版修复（`autoFix`），可直接对接 `AITextDiffEngine` 展示红绿逐字对比。
enum OfflineTextLinter {
    enum Category: String, Equatable {
        case typoDuplicate = "手滑重复"
        case aiCliche = "AI 味 / 套话"
        case typography = "排版与标点"
        case privacy = "隐私风险"
        case platformRisk = "发帖防限流"
        case readability = "可读性"
    }

    enum Severity: Int, Comparable, Equatable {
        case info = 0
        case warning = 1
        case critical = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Finding: Identifiable, Equatable {
        let id: String
        let category: Category
        let severity: Severity
        let matchedText: String
        let message: String
        let suggestion: String
        let autoFixable: Bool
    }

    struct Report: Equatable {
        let originalText: String
        let autoFixedText: String
        let score: Int
        let totalChars: Int
        let hanChars: Int
        let englishWords: Int
        let sentenceCount: Int
        let estimatedSpeakSeconds: Int
        let findings: [Finding]
        let privacyRedactedText: String
        let privacyHitCount: Int
        let platformSafeText: String
        let platformRiskCount: Int

        var hasAutoFixChanges: Bool {
            autoFixedText != originalText
        }

        var hasPlatformRisks: Bool {
            platformRiskCount > 0 && platformSafeText != originalText
        }

        var scoreLabel: String {
            switch score {
            case 90...100: return "极佳 · 可直接发送"
            case 75..<90: return "良好 · 有小幅可优化项"
            case 55..<75: return "一般 · 建议微调表达或排版"
            default: return "需注意 · 存在隐私或明显表达问题"
            }
        }
    }

    private static let defaultAIClicheSuggestions: [(word: String, tip: String)] = [
        ("赋能", "改用具体动作，如「支持 / 帮到 / 提效」"),
        ("抓手", "直说具体方案或核心方法，少用空洞黑话"),
        ("闭环", "改用「落地 / 跟进到底 / 跑通流程」"),
        ("综上所述", "聊天或短文直接说「总之 / 所以」更自然"),
        ("总而言之", "删去过渡套话，直接给结论更利落"),
        ("不仅如此", "可替换为「而且 / 另外」减少翻译腔"),
        ("值得一提的是", "直接陈述重点即可，无需垫话"),
        ("诚挚", "日常沟通改用「真心 / 非常」更亲切"),
        ("祈请", "日常职场改用「麻烦 / 请」避免过分生硬"),
        ("不胜感激", "日常交流改用「非常感谢 / 辛苦啦」更自然"),
        ("显而易见", "删去或直接给出事实证据"),
        ("至关重要", "改用「很关键 / 最核心」更口语自然"),
    ]

    private static let commonDuplicateTypos: [(pattern: String, fix: String)] = [
        ("的的", "的"),
        ("了了", "了"),
        ("是是", "是"),
        ("在在", "在"),
        ("和和", "和"),
        ("我我", "我"),
        ("你你", "你"),
        ("他他", "他"),
        ("，，", "，"),
        ("。。", "。"),
        ("？？", "？"),
        ("！！", "！"),
        ("、、", "、"),
    ]

    /// 小红书 / 抖音 / 闲鱼 / 广告法高频限流与违规极限词（0ms 离线检测 + 自然合规平替）
    private static let platformComplianceRules: [(word: String, replacement: String, reason: String)] = [
        ("全网最低", "性价比很高", "触碰广告法绝对化价格用语，极易触发平台限流"),
        ("全网第一", "口碑前列", "绝对化排名用语，发帖/评价易被折叠限流"),
        ("销量第一", "人气很高", "绝对化销量宣传，需改用更温和描述"),
        ("世界第一", "行业领先", "绝对化极限词，易触发审核下架"),
        ("国家级", "专业级", "广告法禁止随意使用的绝对化背书词"),
        ("顶级", "高水准", "极限修饰词，小红书/抖音笔记易被限流"),
        ("100%有效", "实测体验很稳", "绝对化功效承诺，易触发内容审核拦截"),
        ("绝对有效", "个人实测好用", "绝对化功效表述，建议改为个人体验"),
        ("永久有效", "长期有效", "绝对化时间承诺，建议温和表达"),
        ("立竿见影", "见效比较快", "夸大功效词，护肤/健康类笔记易限流"),
        ("零副作用", "配方比较温和", "绝对化安全承诺，易触碰医疗合规红线"),
        ("包治", "辅助改善", "涉及医疗疗效承诺，高危违规词"),
        ("根治", "日常舒缓", "涉及医疗疗效承诺，极易被删帖限流"),
        ("抗癌", "日常养护", "医疗违规敏感词，非专业资质严禁使用"),
        ("加我微信", "主页私信我", "站外导流高危词，小红书/闲鱼/抖音易直接封限"),
        ("加微信", "站内私信", "站外导流高危词，易触发平台判违"),
        ("加vx", "站内联系", "站外导流变体词，平台风控重点拦截"),
        ("私聊转账", "走平台担保下单", "脱离平台交易诱导词，闲鱼/电商高危限流"),
        ("微信转账", "平台下单", "站外交易词，易触发账号风控"),
        ("支付宝转账", "走平台保障", "站外交易词，易触发账号风控"),
        ("私下交易", "平台担保交易", "站外交易高危词，建议改走平台流程"),
        ("扫码加群", "站内交流", "外部引流高危词，笔记易被仅自己可见"),
        ("刷单", "真实体验反馈", "违规交易词，极易触发系统风控"),
        ("代购", "好物分享", "部分平台对个人代购词汇会做限流处理"),
    ]

    static func autoReplacePlatformRisks(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var out = text
        for rule in platformComplianceRules {
            out = out.replacingOccurrences(of: rule.word, with: rule.replacement, options: [.caseInsensitive])
        }
        return out
    }

    static func analyze(
        _ text: String,
        bannedCliches: [String] = PersonalStyleDNA().bannedAICliches,
        privacyCustomTerms: [String] = [],
        checkPlatformCompliance: Bool = true
    ) -> Report {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Report(
                originalText: text,
                autoFixedText: text,
                score: 100,
                totalChars: 0,
                hanChars: 0,
                englishWords: 0,
                sentenceCount: 0,
                estimatedSpeakSeconds: 0,
                findings: [],
                privacyRedactedText: text,
                privacyHitCount: 0,
                platformSafeText: text,
                platformRiskCount: 0
            )
        }

        var findings: [Finding] = []
        var penalty = 0

        // 1. 隐私外泄红灯检测（联动端侧 AIPrivacyShield）
        let shield = AIPrivacyShield.sanitize(text, customTerms: privacyCustomTerms)
        if shield.hasRedactions {
            for item in shield.hits {
                findings.append(Finding(
                    id: "priv_\(item.placeholder)",
                    category: .privacy,
                    severity: .critical,
                    matchedText: item.placeholder,
                    message: "正文含疑似敏感信息（\(item.category)），外发前请确认是否需要脱敏",
                    suggestion: "可点击「复制脱敏版」自动替换为 \(item.placeholder)",
                    autoFixable: false
                ))
            }
            penalty += min(36, shield.hits.count * 15)
        }

        // 2. 手滑重复字词 / 重复标点
        for (dup, fix) in commonDuplicateTypos {
            if text.contains(dup) {
                findings.append(Finding(
                    id: "dup_\(dup)",
                    category: .typoDuplicate,
                    severity: .warning,
                    matchedText: dup,
                    message: "疑似手滑多打了重复字符「\(dup)」",
                    suggestion: "建议合并为「\(fix)」（支持一键自动修复）",
                    autoFixable: true
                ))
                penalty += 8
            }
        }

        // 3. AI 味 / 官腔词汇雷达（合并默认表与用户文风 DNA 禁用词）
        var checkedWords = Set<String>()
        var clichéPairs: [(String, String)] = defaultAIClicheSuggestions
        for custom in bannedCliches {
            let w = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            if !w.isEmpty && !clichéPairs.contains(where: { $0.0 == w }) {
                clichéPairs.append((w, "属于你的文风禁用词，建议换更自然具体的说法"))
            }
        }
        for (word, tip) in clichéPairs where checkedWords.insert(word).inserted {
            if text.contains(word) {
                findings.append(Finding(
                    id: "cliche_\(word)",
                    category: .aiCliche,
                    severity: .warning,
                    matchedText: word,
                    message: "检测到偏 AI 味/官腔用词「\(word)」",
                    suggestion: tip,
                    autoFixable: false
                ))
                penalty += 6
            }
        }

        // 4. 中文文案排版规范（盘古空格 + 中英标点混用 + 多余空行）
        let fixed = autoFix(text)
        let panguOnly = TextFormatterToolbox.addPanguSpaces(text)
        if panguOnly != text {
            findings.append(Finding(
                id: "typo_pangu",
                category: .typography,
                severity: .info,
                matchedText: "中英/数字间距",
                message: "中文与英文/数字之间缺少视觉呼吸空格（盘古之白）",
                suggestion: "开启一键排版自动补齐标准中英间距",
                autoFixable: true
            ))
            penalty += 5
        }
        if hasMixedChineseHalfwidthPunctuation(text) {
            findings.append(Finding(
                id: "typo_punct",
                category: .typography,
                severity: .info,
                matchedText: ", ? ! ;",
                message: "中文语句中混入了英文半角标点",
                suggestion: "建议统一为全角中文标点「，？！；」（支持一键自动修复）",
                autoFixable: true
            ))
            penalty += 6
        }
        if text.contains("\n\n\n") || text.contains("   ") {
            findings.append(Finding(
                id: "typo_blank",
                category: .typography,
                severity: .info,
                matchedText: "多余空白",
                message: "存在连续多余空行或连续空格",
                suggestion: "一键排版自动整理为紧凑段落",
                autoFixable: true
            ))
            penalty += 3
        }

        // 4.5 小红书 / 抖音 / 闲鱼发帖防限流与广告法极限词检测
        var platformHitCount = 0
        let platformSafe: String
        if checkPlatformCompliance {
            let lowered = text.lowercased()
            for rule in platformComplianceRules {
                if lowered.contains(rule.word.lowercased()) {
                    platformHitCount += 1
                    findings.append(Finding(
                        id: "plat_\(rule.word)",
                        category: .platformRisk,
                        severity: .warning,
                        matchedText: rule.word,
                        message: "「\(rule.word)」：\(rule.reason)",
                        suggestion: "建议平替为「\(rule.replacement)」（支持一键合规替换）",
                        autoFixable: true
                    ))
                    penalty += 8
                }
            }
            platformSafe = platformHitCount > 0 ? autoReplacePlatformRisks(text) : text
        } else {
            platformSafe = text
        }

        // 5. 可读性与长难句分析
        var hanCount = 0
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) {
                hanCount += 1
            }
        }
        let engWords = text.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.filter { !$0.isEmpty }.count
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let longSentences = sentences.filter { $0.count > 48 }
        if let longest = longSentences.max(by: { $0.count < $1.count }) {
            findings.append(Finding(
                id: "read_long_sentence",
                category: .readability,
                severity: .info,
                matchedText: "\(longest.count) 字长句",
                message: "有 \(longSentences.count) 处超过 48 字的长句，手机小屏阅读较费力",
                suggestion: "建议在「，」处拆成两句短句，信息更利落",
                autoFixable: false
            ))
            penalty += min(10, longSentences.count * 4)
        }

        // 约 210 字/分钟口播速度（3.5 字/秒）
        let effectiveUnits = Double(hanCount) + Double(engWords) * 1.4
        let speakSec = max(1, Int((effectiveUnits / 3.5).rounded()))

        let sortedFindings = findings.sorted { $0.severity > $1.severity }
        let finalScore = max(15, min(100, 100 - penalty))

        return Report(
            originalText: text,
            autoFixedText: fixed,
            score: finalScore,
            totalChars: trimmed.count,
            hanChars: hanCount,
            englishWords: engWords,
            sentenceCount: max(1, sentences.count),
            estimatedSpeakSeconds: speakSec,
            findings: sortedFindings,
            privacyRedactedText: shield.sanitizedText,
            privacyHitCount: shield.hits.count,
            platformSafeText: platformSafe,
            platformRiskCount: platformHitCount
        )
    }

    /// 100% 确定性一键离线修复：去手滑重复字符、中文句内半角标点转全角、补盘古之白、清理多余连续空行。
    static func autoFix(_ text: String) -> String {
        var out = text
        // 1. 清理手滑重复字符
        for (dup, fix) in commonDuplicateTypos {
            while out.contains(dup) {
                out = out.replacingOccurrences(of: dup, with: fix)
            }
        }
        // 2. 中文字符紧邻的英文半角标点转中文全角（保留数字小数点、网址与纯英文句）
        out = normalizeChineseHalfwidthPunctuation(out)
        // 3. 盘古之白（中英/中数间距）
        out = TextFormatterToolbox.addPanguSpaces(out)
        // 4. 合并 3 个以上连续换行为双换行，去掉行尾多余空格
        while out.contains("\n\n\n") {
            out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        let lines = out.components(separatedBy: "\n").map { line in
            var s = line
            while s.hasSuffix(" ") || s.hasSuffix("\t") { s.removeLast() }
            return s
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isHan(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v)
    }

    private static func hasMixedChineseHalfwidthPunctuation(_ text: String) -> Bool {
        normalizeChineseHalfwidthPunctuation(text) != text
    }

    private static func normalizeChineseHalfwidthPunctuation(_ text: String) -> String {
        let map: [Character: Character] = [",": "，", "?": "？", "!": "！", ";": "；"]
        let chars = Array(text)
        guard !chars.isEmpty else { return text }
        var out: [Character] = []
        out.reserveCapacity(chars.count)
        for i in 0..<chars.count {
            let ch = chars[i]
            if let full = map[ch] {
                let prevIsHan = (i > 0) && isHan(chars[i - 1])
                let nextIsHan = (i + 1 < chars.count) && isHan(chars[i + 1])
                if prevIsHan || nextIsHan {
                    out.append(full)
                    continue
                }
            }
            out.append(ch)
        }
        return String(out)
    }
}
