import Foundation

/// 沟通情绪热力等级（0ms 纯本地离线评估，绝不上传原文）
public enum EmotionHeatLevel: Int, Comparable, Sendable, CaseIterable {
    case calm = 0
    case tense = 1
    case heated = 2
    case explosive = 3

    public static func < (lhs: EmotionHeatLevel, rhs: EmotionHeatLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .calm: return "语气平和"
        case .tense: return "略带情绪"
        case .heated: return "语气偏冲"
        case .explosive: return "高危冲动"
        }
    }

    public var shortBadge: String {
        switch self {
        case .calm: return "平和"
        case .tense: return "略冲"
        case .heated: return "偏冲·降火"
        case .explosive: return "冲动预警·降火"
        }
    }
}

/// 情绪冲动检测报告
public struct EmotionGuardReport: Equatable, Sendable {
    public let level: EmotionHeatLevel
    public let score: Int
    public let matchedTriggers: [String]
    public let advice: String
    public let coolingSystemPrompt: String
    public let quickCalmSuggestions: [String]

    public var shouldWarnInKeyboard: Bool {
        level >= .heated
    }

    public init(
        level: EmotionHeatLevel,
        score: Int,
        matchedTriggers: [String],
        advice: String,
        coolingSystemPrompt: String,
        quickCalmSuggestions: [String]
    ) {
        self.level = level
        self.score = score
        self.matchedTriggers = matchedTriggers
        self.advice = advice
        self.coolingSystemPrompt = coolingSystemPrompt
        self.quickCalmSuggestions = quickCalmSuggestions
    }
}

/// 防诈与交易避坑风险等级
public enum ScamRiskLevel: Int, Comparable, Sendable {
    case safe = 0
    case caution = 1
    case highRisk = 2

    public static func < (lhs: ScamRiskLevel, rhs: ScamRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .safe: return "未见诈骗特征"
        case .caution: return "交易风险提醒"
        case .highRisk: return "高危诈骗预警"
        }
    }
}

/// 单条防诈命中记录
public struct ScamAlertHit: Identifiable, Equatable, Sendable {
    public let id: String
    public let category: String
    public let matchedKeyword: String
    public let warning: String
    public let isHighRisk: Bool

    public init(
        id: String,
        category: String,
        matchedKeyword: String,
        warning: String,
        isHighRisk: Bool
    ) {
        self.id = id
        self.category = category
        self.matchedKeyword = matchedKeyword
        self.warning = warning
        self.isHighRisk = isHighRisk
    }
}

/// 防诈与避坑雷达报告
public struct ScamGuardReport: Equatable, Sendable {
    public let level: ScamRiskLevel
    public let hits: [ScamAlertHit]
    public let summaryBanner: String

    public var isRisky: Bool {
        level != .safe
    }

    public init(level: ScamRiskLevel, hits: [ScamAlertHit], summaryBanner: String) {
        self.level = level
        self.hits = hits
        self.summaryBanner = summaryBanner
    }
}

/// 0ms 纯本地「情绪防冲动温度计 + 防诈/避坑雷达」双核引擎。
/// 面向大众日常高频痛点：
/// 1. 职场/伴侣/家人争执时，在发送前识别上头冲动语气，给出「保底线、不卑微」的冷静降火改写；
/// 2. 收到可疑短信、客服话术、转账催促或求职租房要求时，0ms 离线拦截高危诈骗与常见交易坑。
public enum CommunicationGuardEngine {

    /// 一键送往 AI 降火改写的专用系统指令
    public static let coolingSystemPrompt: String = """
    你是高情商情绪降火沟通顾问。用户刚刚写了一段带气或容易引发冲突的话，请在「守住核心底线与真实诉求、不卑微不讨好」的前提下，把它改写成冷静、克制、就事论事且更容易推进解决问题的表达：
    1. 保留用户的核心诉求、边界与客观事实；
    2. 去掉人身攻击、反问指责、情绪宣泄与过度感叹号/问号；
    3. 语气自然像真人发微信，不要官腔套话，字数与原文接近；
    4. 仅输出改写后的纯文本，不要解释。
    """

    private struct EmotionTrigger {
        let keyword: String
        let weight: Int
        let displayLabel: String
    }

    private static let strongEmotionTriggers: [EmotionTrigger] = [
        EmotionTrigger(keyword: "有病", weight: 40, displayLabel: "攻击性措辞"),
        EmotionTrigger(keyword: "神经病", weight: 45, displayLabel: "人身攻击"),
        EmotionTrigger(keyword: "傻逼", weight: 55, displayLabel: "强侮辱词"),
        EmotionTrigger(keyword: "蠢货", weight: 45, displayLabel: "强侮辱词"),
        EmotionTrigger(keyword: "智障", weight: 50, displayLabel: "强侮辱词"),
        EmotionTrigger(keyword: "废物", weight: 45, displayLabel: "人身贬低"),
        EmotionTrigger(keyword: "垃圾", weight: 36, displayLabel: "情绪化贬损"),
        EmotionTrigger(keyword: "脑子进水", weight: 45, displayLabel: "人身攻击"),
        EmotionTrigger(keyword: "脑子有泡", weight: 45, displayLabel: "人身攻击"),
        EmotionTrigger(keyword: "给我滚", weight: 50, displayLabel: "激烈驱逐"),
        EmotionTrigger(keyword: "滚蛋", weight: 45, displayLabel: "激烈驱逐"),
        EmotionTrigger(keyword: "闭嘴", weight: 38, displayLabel: "强硬压制"),
        EmotionTrigger(keyword: "去死", weight: 60, displayLabel: "极端攻击"),
        EmotionTrigger(keyword: "真服了你", weight: 34, displayLabel: "强烈不满"),
        EmotionTrigger(keyword: "爱干干", weight: 38, displayLabel: "摆烂对抗"),
        EmotionTrigger(keyword: "爱买不买", weight: 38, displayLabel: "对抗性表态"),
        EmotionTrigger(keyword: "爱咋咋", weight: 36, displayLabel: "决裂语气"),
        EmotionTrigger(keyword: "别烦我", weight: 36, displayLabel: "情绪拒绝"),
        EmotionTrigger(keyword: "听不懂人话", weight: 48, displayLabel: "严重嘲讽"),
        EmotionTrigger(keyword: "恶心死了", weight: 38, displayLabel: "强烈厌恶"),
        EmotionTrigger(keyword: "shut up", weight: 42, displayLabel: "强硬压制"),
        EmotionTrigger(keyword: "idiot", weight: 45, displayLabel: "人身攻击"),
        EmotionTrigger(keyword: "stupid", weight: 38, displayLabel: "人身攻击"),
        EmotionTrigger(keyword: "wtf", weight: 36, displayLabel: "强烈宣泄")
    ]

    private static let mediumEmotionTriggers: [EmotionTrigger] = [
        EmotionTrigger(keyword: "你到底", weight: 22, displayLabel: "质问语气"),
        EmotionTrigger(keyword: "我都说了几遍", weight: 28, displayLabel: "不耐烦指责"),
        EmotionTrigger(keyword: "说了多少遍", weight: 28, displayLabel: "不耐烦指责"),
        EmotionTrigger(keyword: "无语死了", weight: 24, displayLabel: "强烈吐槽"),
        EmotionTrigger(keyword: "随便你", weight: 22, displayLabel: "冷战推开"),
        EmotionTrigger(keyword: "懒得理你", weight: 30, displayLabel: "拒绝沟通"),
        EmotionTrigger(keyword: "懒得跟你说", weight: 28, displayLabel: "拒绝沟通"),
        EmotionTrigger(keyword: "凭什么", weight: 22, displayLabel: "对抗质问"),
        EmotionTrigger(keyword: "长点心", weight: 22, displayLabel: "居高临下指责"),
        EmotionTrigger(keyword: "你什么意思", weight: 24, displayLabel: "防御质问"),
        EmotionTrigger(keyword: "有没有搞错", weight: 24, displayLabel: "指责失误"),
        EmotionTrigger(keyword: "搞什么鬼", weight: 26, displayLabel: "恼火质问"),
        EmotionTrigger(keyword: "能不能长脑子", weight: 38, displayLabel: "挖苦指责"),
        EmotionTrigger(keyword: "受够了", weight: 32, displayLabel: "情绪临界"),
        EmotionTrigger(keyword: "烦死了", weight: 24, displayLabel: "明显烦躁"),
        EmotionTrigger(keyword: "少废话", weight: 34, displayLabel: "打断冲突"),
        EmotionTrigger(keyword: "别废话", weight: 34, displayLabel: "打断冲突"),
        EmotionTrigger(keyword: "什么玩意", weight: 32, displayLabel: "轻蔑贬损"),
        EmotionTrigger(keyword: "真无语", weight: 18, displayLabel: "无奈抱怨"),
        EmotionTrigger(keyword: "拉倒吧", weight: 20, displayLabel: "消极放弃"),
        EmotionTrigger(keyword: "你自己看着办", weight: 22, displayLabel: "甩手施压"),
        EmotionTrigger(keyword: "爱谁谁", weight: 24, displayLabel: "消极对抗"),
        EmotionTrigger(keyword: "呵呵", weight: 18, displayLabel: "阴阳怪气"),
        EmotionTrigger(keyword: "行吧行吧", weight: 16, displayLabel: "敷衍情绪"),
        EmotionTrigger(keyword: "别找我", weight: 28, displayLabel: "切断沟通")
    ]

    private static let politeDeescalators: [String] = [
        "麻烦", "不好意思", "感谢", "谢谢", "请帮忙", "辛苦", "方便的话", "我们一起"
    ]

    private static let intensePunctRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"([?!？！]{3,}|[！!]{2,}[？?]+|[？?]+[！!]{2,})"#,
        options: []
    )

    private static let doublePunctRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"([?!？！]{2})"#,
        options: []
    )

    private static let shoutingCapsRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\b[A-Z]{4,}\b"#,
        options: []
    )

    /// 0ms 纯离线情绪温度计分析
    public static func analyzeEmotion(_ text: String) -> EmotionGuardReport {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return EmotionGuardReport(
                level: .calm,
                score: 0,
                matchedTriggers: [],
                advice: "表达自然平和，可直接发送。",
                coolingSystemPrompt: coolingSystemPrompt,
                quickCalmSuggestions: []
            )
        }

        let lowered = trimmed.lowercased()
        var score = 0
        var matched: [String] = []
        var hasStrongTrigger = false

        for trigger in strongEmotionTriggers {
            if lowered.contains(trigger.keyword) {
                score += trigger.weight
                hasStrongTrigger = true
                if !matched.contains(trigger.keyword) {
                    matched.append(trigger.keyword)
                }
            }
        }

        for trigger in mediumEmotionTriggers {
            if lowered.contains(trigger.keyword) {
                score += trigger.weight
                if !matched.contains(trigger.keyword) {
                    matched.append(trigger.keyword)
                }
            }
        }

        let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if let regex = intensePunctRegex, regex.firstMatch(in: trimmed, range: nsRange) != nil {
            score += 20
            matched.append("连续感叹/反问标点")
        } else if let regex = doublePunctRegex, regex.numberOfMatches(in: trimmed, range: nsRange) >= 1 {
            score += 10
            if score >= 16 {
                matched.append("叠加反问标点")
            }
        }

        if let capsRegex = shoutingCapsRegex {
            let capsCount = capsRegex.numberOfMatches(in: trimmed, range: nsRange)
            if capsCount >= 2 {
                score += 16
                matched.append("全大写强调")
            }
        }

        if !hasStrongTrigger {
            let politeHits = politeDeescalators.filter { trimmed.contains($0) }.count
            if politeHits > 0 {
                score = max(0, score - 14 * politeHits)
            }
        }

        let clampedScore = min(100, max(0, score))
        let level: EmotionHeatLevel
        if clampedScore >= 55 {
            level = .explosive
        } else if clampedScore >= 32 {
            level = .heated
        } else if clampedScore >= 16 {
            level = .tense
        } else {
            level = .calm
        }

        let advice: String
        switch level {
        case .calm:
            advice = "语气平稳清晰，未发现明显冲动或激化表达。"
        case .tense:
            advice = "略带质问或不耐烦情绪；若对方关系敏感，建议把「追责」改为「对齐下一步动作」。"
        case .heated:
            advice = "当前措辞偏冲，发出后易引发情绪对抗。建议先深呼吸 3 秒，保底线但去掉反问与指责。"
        case .explosive:
            advice = "检测到高危冲动/攻击表达！强烈建议先冷静降火再发，避免事后后悔或截屏留患。"
        }

        let quickCalm = buildOfflineCalmSuggestions(for: trimmed, level: level)
        return EmotionGuardReport(
            level: level,
            score: clampedScore,
            matchedTriggers: Array(matched.prefix(5)),
            advice: advice,
            coolingSystemPrompt: coolingSystemPrompt,
            quickCalmSuggestions: quickCalm
        )
    }

    private static func buildOfflineCalmSuggestions(for text: String, level: EmotionHeatLevel) -> [String] {
        guard level >= .tense else { return [] }
        if text.contains("几遍") || text.contains("多少遍") || text.contains("到底") {
            return [
                "这件事我再把关键点确认一遍，麻烦按这个口径同步一下进度。",
                "刚才可能没对齐清楚，我的核心诉求如下，我们先把结论敲定。",
                "目前卡点在这块，咱们先聚焦怎么解决，避免反复沟通。"
            ]
        }
        if text.contains("随便") || text.contains("懒得") || text.contains("算了") || text.contains("别找我") {
            return [
                "我现在情绪有点上头，先各自冷静一下，晚点心平气和再聊。",
                "这个方案我确实不太认可，我先把我的顾虑列出来，方便你参考。",
                "目前我这边精力有限，这件事先按原约定来，有变化再同步。"
            ]
        }
        return [
            "这个问题对我来说挺重要的，希望我们能就事论事把方案定下来。",
            "我对目前的处理方式不太满意，麻烦给一个明确的时间节点和改进方案。",
            "先不争论对错了，我们确认一下接下来具体怎么推进。"
        ]
    }

    // MARK: - 防诈与交易避坑雷达

    private struct ScamRule {
        let id: String
        let category: String
        let keywords: [String]
        let requiredContextKeywords: [String]
        let warning: String
        let isHighRisk: Bool
    }

    private static let scamRules: [ScamRule] = [
        ScamRule(
            id: "screen_share",
            category: "诱导屏幕共享/远程控制",
            keywords: ["屏幕共享", "共享屏幕", "开启共享", "远程控制", "远程协助下载", "同屏协助"],
            requiredContextKeywords: [],
            warning: "切勿与陌生人或「客服」开启屏幕共享/远程控制，对方可实时窃取银行卡密码与验证码！",
            isHighRisk: true
        ),
        ScamRule(
            id: "meeting_scam",
            category: "假借会议软件指导操作",
            keywords: ["会议号", "腾讯会议", "云视讯", "zoom会议", "下载会议"],
            requiredContextKeywords: ["客服", "扣费", "退款", "保障", "注销", "征信", "理赔", "关闭"],
            warning: "官方客服绝不会要求通过视频会议软件指导关闭扣费或理赔，请立即挂断并自行在官方 App 核实！",
            isHighRisk: true
        ),
        ScamRule(
            id: "million_insurance",
            category: "冒充客服/百万保障扣费",
            keywords: [
                "百万保障", "微信保障", "百万医疗到期", "自动扣费", "每月扣款",
                "不关闭将扣费", "影响征信", "消除征信", "注销校园贷", "关闭免密扣费", "理赔通道"
            ],
            requiredContextKeywords: [],
            warning: "微信/支付宝「百万保障」完全免费且不会到期自动扣费，凡提「不关闭扣费/影响征信」均为诈骗！",
            isHighRisk: true
        ),
        ScamRule(
            id: "otp_theft",
            category: "套取短信验证码/密码",
            keywords: [
                "发一下验证码", "告诉我验证码", "验证码发我", "把验证码",
                "支付密码发", "银行卡密码", "动态口令发", "取款密码"
            ],
            requiredContextKeywords: [],
            warning: "短信验证码与支付密码等同于银行卡现金，任何客服、平台或公检法都无权索要！",
            isHighRisk: true
        ),
        ScamRule(
            id: "safe_account",
            category: "冒充公检法/安全账户",
            keywords: ["安全账户", "资金清查", "涉案资金", "冻结名下账户", "通缉令", "验资账户", "配合警方转账"],
            requiredContextKeywords: [],
            warning: "公检法机关绝对不存在「安全账户」或线上资金清查，遇此话术请立即拨打 96110 核实！",
            isHighRisk: true
        ),
        ScamRule(
            id: "brushing_rebate",
            category: "刷单返利/垫资兼职",
            keywords: ["刷单", "垫资返佣", "做任务返现", "点赞返现", "充值解冻", "连单任务", "导师带单", "内部漏洞稳赚"],
            requiredContextKeywords: [],
            warning: "凡是需要先垫资、做连单或充值才能提现的兼职/返利，100% 为刷单诈骗！",
            isHighRisk: true
        ),
        ScamRule(
            id: "pig_butchering",
            category: "高息保本/虚假投资",
            keywords: ["稳赚不赔", "保本高息", "内幕消息带", "虚拟币搬砖", "usdt充值", "提现需交税", "解冻保证金"],
            requiredContextKeywords: [],
            warning: "承诺稳赚高息或提现要求先交税/保证金均是虚假投资平台典型套路，请勿继续转入资金！",
            isHighRisk: true
        ),
        ScamRule(
            id: "impersonate_transfer",
            category: "熟人/领导紧急转账",
            keywords: ["先帮我转", "急用转一下", "我换新号了", "领导让转", "私下打款", "先垫付一下"],
            requiredContextKeywords: [],
            warning: "遇亲友或领导在聊天中要求紧急转账、代付，务必通过原手机号语音/视频亲口核实身份！",
            isHighRisk: false
        ),
        ScamRule(
            id: "deposit_phishing",
            category: "提前交押金/钓鱼诱导链接",
            keywords: ["先交押金", "提前交定金", "体检费先转", "培训贷", "建档费", "点击链接领取", "账户异常请登录", "补贴申领入口"],
            requiredContextKeywords: [],
            warning: "求职/租房要求提前转账交押金、培训费或点击陌生链接填写银行卡信息均存在高风险，请谨慎核验！",
            isHighRisk: false
        )
    ]

    /// 0ms 纯离线防诈与避坑雷达扫描
    public static func analyzeScam(_ text: String) -> ScamGuardReport {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else {
            return ScamGuardReport(level: .safe, hits: [], summaryBanner: "未检出明显诈骗或交易陷阱特征。")
        }

        let lowered = trimmed.lowercased()
        var hits: [ScamAlertHit] = []

        for rule in scamRules {
            guard let matchedKw = rule.keywords.first(where: { lowered.contains($0) }) else {
                continue
            }
            if !rule.requiredContextKeywords.isEmpty {
                let hasContext = rule.requiredContextKeywords.contains { lowered.contains($0) }
                guard hasContext else { continue }
            }
            hits.append(ScamAlertHit(
                id: rule.id,
                category: rule.category,
                matchedKeyword: matchedKw,
                warning: rule.warning,
                isHighRisk: rule.isHighRisk
            ))
        }

        guard !hits.isEmpty else {
            return ScamGuardReport(level: .safe, hits: [], summaryBanner: "未检出明显诈骗或交易陷阱特征。")
        }

        let highRiskCount = hits.filter { $0.isHighRisk }.count
        let level: ScamRiskLevel = (highRiskCount >= 1 || hits.count >= 2) ? .highRisk : .caution
        let categoriesText = hits.prefix(2).map { "「\($0.category)」" }.joined()
        let banner: String
        if level == .highRisk {
            banner = "高危预警：疑似涉及\(categoriesText)，切勿转账、共享屏幕或泄露验证码（反诈专线 96110）"
        } else {
            banner = "风险提醒：检测到\(categoriesText)特征，涉及钱款或陌生链接请先多方核实"
        }
        return ScamGuardReport(level: level, hits: hits, summaryBanner: banner)
    }
}
