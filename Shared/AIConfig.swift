import Foundation

/// AI 服务提供方（原生三协议：Google Gemini / OpenAI 兼容 / Anthropic Claude 原生）。
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case gemini
    case openAICompatible
    case anthropic

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .gemini: return "Gemini"
        case .openAICompatible: return "OpenAI 兼容"
        case .anthropic: return "Claude 原生"
        }
    }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openAICompatible: return "OpenAI 兼容 (DeepSeek / Qwen / Ollama / 中转)"
        case .anthropic: return "Anthropic Claude 原生 (/v1/messages)"
        }
    }
}

/// 跨协议思考/深度推理模式（自动适配 Gemini thinking_level / thinking_budget、OpenAI reasoning_effort、DeepSeek/Qwen enable_thinking）。
enum AIThinkingMode: String, Codable, CaseIterable, Identifiable {
    case off
    case auto
    case minimal
    case low
    case medium
    case high
    case customBudget

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "关闭思考"
        case .auto: return "自动适应"
        case .minimal: return "极速浅思考"
        case .low: return "轻度思考"
        case .medium: return "均衡思考"
        case .high: return "深度推理"
        case .customBudget: return "自定义预算"
        }
    }

    var shortBadge: String {
        switch self {
        case .off: return "关"
        case .auto: return "自动"
        case .minimal: return "极速"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "深"
        case .customBudget: return "预算"
        }
    }

    var isEnabled: Bool { self != .off }
}

/// 推荐的内置 Gemini 快捷模型预设（支持一键获取更多或任意手动输入）。
enum GeminiModelOption: String, CaseIterable, Identifiable {
    case flash38 = "gemini-3.8-flash"
    case flashLite35 = "gemini-3.5-flash-lite"
    case argon4 = "gemini-4-argon"
    case flash25 = "gemini-2.5-flash"
    case pro25 = "gemini-2.5-pro"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flash38: return "Gemini 3.8 Flash（默认 · 高效均衡）"
        case .flashLite35: return "Gemini 3.5 Flash-Lite（极速 · 低成本）"
        case .argon4: return "Gemini 4 Argon（旗舰深度推理）"
        case .flash25: return "Gemini 2.5 Flash（经典高速）"
        case .pro25: return "Gemini 2.5 Pro（长上下文推理）"
        }
    }

    var defaultThinkingLevel: String {
        switch self {
        case .flashLite35: return "minimal"
        case .flash38, .argon4: return "low"
        case .flash25, .pro25: return "medium"
        }
    }
}

/// 从远端服务商 API 动态拉取到的模型元数据（完整保留原始 ID、显示名称、所属方与类型标签，绝不截断）。
struct AIModelInfo: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var supportsThinking: Bool = false
    var contextLength: Int? = nil
    var provider: AIProvider = .openAICompatible
    var isChatModel: Bool = true
    var ownedBy: String? = nil

    init(
        id: String,
        displayName: String? = nil,
        supportsThinking: Bool = false,
        contextLength: Int? = nil,
        provider: AIProvider = .openAICompatible,
        isChatModel: Bool = true,
        ownedBy: String? = nil
    ) {
        self.id = id
        let cleanDisplay = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.displayName = cleanDisplay.isEmpty ? id : cleanDisplay
        self.supportsThinking = supportsThinking
        self.contextLength = contextLength
        self.provider = provider
        self.isChatModel = isChatModel
        let cleanOwner = ownedBy?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ownedBy = (cleanOwner?.isEmpty == false) ? cleanOwner : nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.id = decodedID
        let rawDisplay = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        self.displayName = rawDisplay.isEmpty ? decodedID : rawDisplay
        self.supportsThinking = try c.decodeIfPresent(Bool.self, forKey: .supportsThinking) ?? false
        self.contextLength = try c.decodeIfPresent(Int.self, forKey: .contextLength)
        self.provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .openAICompatible
        self.isChatModel = try c.decodeIfPresent(Bool.self, forKey: .isChatModel) ?? true
        self.ownedBy = try c.decodeIfPresent(String.self, forKey: .ownedBy)
    }
}

/// 多服务商配置档案（支持同时保存 Gemini / DeepSeek / Qwen / Ollama / 自定义中转并一键切换）。
struct AIProviderProfile: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var provider: AIProvider
    var baseURL: String
    var apiKey: String
    var model: String
    var fastModel: String = ""
    var deepModel: String = ""
    var visionModel: String = ""
    var sttModel: String = ""
    var thinkingMode: AIThinkingMode = .auto
    var thinkingBudget: Int = 2048
    var fetchedModels: [AIModelInfo] = []
    var customHeaders: [String: String] = [:]

    init(
        id: String = UUID().uuidString,
        name: String,
        provider: AIProvider,
        baseURL: String,
        apiKey: String = "",
        model: String,
        fastModel: String = "",
        deepModel: String = "",
        visionModel: String = "",
        sttModel: String = "",
        thinkingMode: AIThinkingMode = .auto,
        thinkingBudget: Int = 2048,
        fetchedModels: [AIModelInfo] = [],
        customHeaders: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.fastModel = fastModel
        self.deepModel = deepModel
        self.visionModel = visionModel
        self.sttModel = sttModel
        self.thinkingMode = thinkingMode
        self.thinkingBudget = thinkingBudget
        self.fetchedModels = fetchedModels
        self.customHeaders = customHeaders
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "自定义渠道"
        provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .openAICompatible
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.deepseek.com/v1"
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "deepseek-chat"
        fastModel = try c.decodeIfPresent(String.self, forKey: .fastModel) ?? ""
        deepModel = try c.decodeIfPresent(String.self, forKey: .deepModel) ?? ""
        visionModel = try c.decodeIfPresent(String.self, forKey: .visionModel) ?? ""
        sttModel = try c.decodeIfPresent(String.self, forKey: .sttModel) ?? ""
        thinkingMode = try c.decodeIfPresent(AIThinkingMode.self, forKey: .thinkingMode) ?? .auto
        thinkingBudget = try c.decodeIfPresent(Int.self, forKey: .thinkingBudget) ?? 2048
        fetchedModels = try c.decodeIfPresent([AIModelInfo].self, forKey: .fetchedModels) ?? []
        customHeaders = try c.decodeIfPresent([String: String].self, forKey: .customHeaders) ?? [:]
    }
}

/// 聊天对象与关系场景秒切人设（在键盘 AI 栏直接一键切换）。
enum AIScenePersona: String, Codable, CaseIterable, Identifiable {
    case auto
    case bossClient
    case colleague
    case friendPartner
    case socialMedia
    case academic

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .auto: return "自动语境"
        case .bossClient: return "👔 领导/客户"
        case .colleague: return "🤝 同事协作"
        case .friendPartner: return "❤️ 密友/对象"
        case .socialMedia: return "🔥 社交种草"
        case .academic: return "🎓 学术严谨"
        }
    }

    var systemRule: String {
        switch self {
        case .auto:
            return ""
        case .bossClient:
            return "当前对象为领导或客户：结论先行、礼貌克制、有分寸感，句尾稳重得体，避免随意颜文字或网络梗。"
        case .colleague:
            return "当前对象为平级同事：清晰高效、友好协作、直接说重点与时间节点，专业术语可保留英文原词。"
        case .friendPartner:
            return "当前对象为密友或伴侣：松弛温暖、像真人日常聊天，自然亲切，不端着、不官腔，可适度用柔和语气词。"
        case .socialMedia:
            return "当前场景为朋友圈或小红书：生动吸睛、分段透气、有共鸣感，杜绝机械营销套话。"
        case .academic:
            return "当前场景为学术与正式文书：逻辑严密、措辞准确规范，消除口语词和模糊表达。"
        }
    }
}

/// 个人背景知识卡片（RAG-Lite：无需每次重复介绍自己或业务背景，支持全局或按沟通场景条件挂载）。
struct PersonalContextCard: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var content: String
    var sceneTag: String = "通用"
    /// 绑定特定沟通场景（nil 或 .auto 表示所有场景均挂载；指定后仅在对应场景生效，节省 Token 且不串味）
    var boundScene: AIScenePersona? = nil
    var isEnabled: Bool = true

    init(
        id: String = UUID().uuidString,
        title: String,
        content: String,
        sceneTag: String = "通用",
        boundScene: AIScenePersona? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.sceneTag = sceneTag
        self.boundScene = boundScene
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "知识卡"
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        sceneTag = try c.decodeIfPresent(String.self, forKey: .sceneTag) ?? "通用"
        boundScene = try c.decodeIfPresent(AIScenePersona.self, forKey: .boundScene)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    /// 判断本卡片在当前沟通对象下是否应当注入系统提示词
    func matches(scene: AIScenePersona) -> Bool {
        guard isEnabled, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let bound = boundScene, bound != .auto else { return true }
        return scene == .auto || scene == bound
    }

    /// 端侧 RAG-Lite 检索命中结果（纯函数，可直接用于 UI 预览与单元测试）
    struct ScoredCard: Identifiable, Equatable {
        let card: PersonalContextCard
        let score: Double
        let exactSceneMatch: Bool
        var id: String { card.id }
    }

    /// 根据当前沟通场景 + 用户提问关键词，从知识卡库中筛选最相关的 Top-K 卡片（既准又省 Token）。
    static func selectRelevantCards(
        from cards: [PersonalContextCard],
        query: String,
        scene: AIScenePersona,
        limit: Int = 4
    ) -> [ScoredCard] {
        let eligible = cards.filter { $0.matches(scene: scene) }
        guard !eligible.isEmpty else { return [] }
        let queryTerms = extractSearchTerms(from: query)

        let scored: [ScoredCard] = eligible.map { card in
            var score = 1.0
            let exactScene = (scene != .auto && card.boundScene == scene)
            if exactScene { score += 6.0 }
            if !queryTerms.isEmpty {
                let titleLower = card.title.lowercased()
                let tagLower = card.sceneTag.lowercased()
                let contentLower = card.content.lowercased()
                var matchedTerms = 0
                for term in queryTerms {
                    if titleLower.contains(term) {
                        score += 3.2
                        matchedTerms += 1
                    } else if tagLower.contains(term) {
                        score += 2.5
                        matchedTerms += 1
                    } else if contentLower.contains(term) {
                        score += 1.2
                        matchedTerms += 1
                    }
                }
                if matchedTerms >= 3 { score += 2.0 }
            }
            return ScoredCard(card: card, score: score, exactSceneMatch: exactScene)
        }
        return Array(scored.sorted { a, b in
            if abs(a.score - b.score) > 0.01 { return a.score > b.score }
            return a.exactSceneMatch && !b.exactSceneMatch
        }.prefix(max(1, limit)))
    }

    /// 提取中英文双轨检索词（英文/数字词 + 中文二元组，零第三方分词依赖）。
    static func extractSearchTerms(from text: String) -> [String] {
        let lower = text.lowercased()
        var seen = Set<String>()
        var terms: [String] = []

        // 1. 英文与数字词
        var asciiBuf = ""
        var hanRun: [Character] = []

        func flushAscii() {
            if asciiBuf.count >= 2 && seen.insert(asciiBuf).inserted {
                terms.append(asciiBuf)
            }
            asciiBuf = ""
        }

        func flushHan() {
            if hanRun.count >= 2 {
                for i in 0..<(hanRun.count - 1) {
                    let bi = String([hanRun[i], hanRun[i + 1]])
                    if seen.insert(bi).inserted {
                        terms.append(bi)
                    }
                }
            }
            hanRun = []
        }

        for ch in lower {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                flushHan()
                asciiBuf.append(ch)
            } else if ch.unicodeScalars.first.map({ (0x4E00...0x9FFF).contains($0.value) }) == true {
                flushAscii()
                hanRun.append(ch)
            } else {
                flushAscii()
                flushHan()
            }
        }
        flushAscii()
        flushHan()
        return Array(terms.prefix(36))
    }

    /// 将导入的 Markdown / TXT 长文档智能切片为多张轻量知识卡（按 `#` 标题或自然段切分）。
    static func chunkDocument(
        title: String,
        text: String,
        sceneTag: String = "导入文档",
        boundScene: AIScenePersona? = nil,
        maxCharsPerCard: Int = 420
    ) -> [PersonalContextCard] {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "知识文档" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var sections: [(heading: String, body: String)] = []
        var curHeading = cleanTitle
        var curLines: [String] = []

        func flushSection() {
            let joined = curLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                sections.append((curHeading, joined))
            }
            curLines = []
        }

        for raw in lines {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") {
                flushSection()
                let heading = t.drop(while: { $0 == "#" || $0 == " " }).trimmingCharacters(in: .whitespaces)
                curHeading = heading.isEmpty ? cleanTitle : String(heading.prefix(24))
            } else {
                curLines.append(raw)
            }
        }
        flushSection()

        let cap = max(120, maxCharsPerCard)
        var cards: [PersonalContextCard] = []
        for sec in sections {
            if sec.body.count <= cap {
                cards.append(PersonalContextCard(title: sec.heading, content: sec.body, sceneTag: sceneTag, boundScene: boundScene, isEnabled: true))
            } else {
                // 按段落二次切分
                let paras = sec.body.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                var chunk = ""
                var partIdx = 1
                for p in paras {
                    if !chunk.isEmpty && chunk.count + p.count + 2 > cap {
                        cards.append(PersonalContextCard(title: "\(sec.heading) (\(partIdx))", content: chunk, sceneTag: sceneTag, boundScene: boundScene, isEnabled: true))
                        partIdx += 1
                        chunk = String(p.prefix(cap))
                    } else {
                        chunk = chunk.isEmpty ? String(p.prefix(cap)) : chunk + "\n\n" + p
                    }
                }
                if !chunk.isEmpty {
                    let finalTitle = partIdx == 1 ? sec.heading : "\(sec.heading) (\(partIdx))"
                    cards.append(PersonalContextCard(title: finalTitle, content: String(chunk.prefix(cap)), sceneTag: sceneTag, boundScene: boundScene, isEnabled: true))
                }
            }
            if cards.count >= 20 { break }
        }
        return cards
    }
}

/// 个人文风 DNA 与「去 AI 腔」规则库（支持粘贴样本克隆、手动改写 Diff 反向自学习与云端同步）。
struct PersonalStyleDNA: Codable, Equatable {
    var bannedAICliches: [String] = ["赋能", "抓手", "闭环", "诚挚", "祈请", "总而言之", "综上所述", "不仅如此"]
    var personalCatchphrases: [String] = ["收到，马上看", "辛苦啦～"]
    var learnedDiffRules: [String] = []
    var clonedStyleSummary: String = ""
    var removeAIClicheEnabled: Bool = true
    var updatedAt: Int = Int(Date().timeIntervalSince1970)

    static let fileName = "lingxi_style_dna.json"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bannedAICliches = try c.decodeIfPresent([String].self, forKey: .bannedAICliches) ?? ["赋能", "抓手", "闭环", "诚挚", "祈请", "总而言之", "综上所述", "不仅如此"]
        personalCatchphrases = try c.decodeIfPresent([String].self, forKey: .personalCatchphrases) ?? ["收到，马上看", "辛苦啦～"]
        learnedDiffRules = try c.decodeIfPresent([String].self, forKey: .learnedDiffRules) ?? []
        clonedStyleSummary = try c.decodeIfPresent(String.self, forKey: .clonedStyleSummary) ?? ""
        removeAIClicheEnabled = try c.decodeIfPresent(Bool.self, forKey: .removeAIClicheEnabled) ?? true
        updatedAt = try c.decodeIfPresent(Int.self, forKey: .updatedAt) ?? Int(Date().timeIntervalSince1970)
    }

    /// 拼装为系统提示词后缀，强制去掉假大空 AI 腔并贴合本人真实表达。
    func promptConstraintBlock() -> String {
        var lines: [String] = []
        if !clonedStyleSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("用户真实文风 DNA：\(clonedStyleSummary)")
        }
        if removeAIClicheEnabled && !bannedAICliches.isEmpty {
            lines.append("严格禁用以下生硬 AI 套话/官腔词：\(bannedAICliches.prefix(16).joined(separator: "、"))。")
        }
        if !personalCatchphrases.isEmpty {
            lines.append("合适时可自然融入用户常用表达习惯（参考但不生搬）：\(personalCatchphrases.prefix(8).joined(separator: " / "))。")
        }
        if !learnedDiffRules.isEmpty {
            lines.append("从历史手动微调学到的偏好：\(learnedDiffRules.prefix(6).joined(separator: "；"))。")
        }
        return lines.joined(separator: "\n")
    }
}

/// AI 单次调用消耗与延迟账本记录（纯数值元数据，不含原文；兼容真实 Token 与字符统计）。
struct AIUsageLedgerEntry: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var timestamp: Int = Int(Date().timeIntervalSince1970)
    var provider: String
    var model: String
    var feature: String
    var thinkingMode: String
    var ttftMs: Int
    var totalMs: Int
    var inputChars: Int
    var outputChars: Int
    var thoughtChars: Int
    var promptTokens: Int? = nil
    var completionTokens: Int? = nil
    var reasoningTokens: Int? = nil

    init(
        id: String = UUID().uuidString,
        timestamp: Int = Int(Date().timeIntervalSince1970),
        provider: String,
        model: String,
        feature: String,
        thinkingMode: String,
        ttftMs: Int,
        totalMs: Int,
        inputChars: Int,
        outputChars: Int,
        thoughtChars: Int,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        reasoningTokens: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.provider = provider
        self.model = model
        self.feature = feature
        self.thinkingMode = thinkingMode
        self.ttftMs = ttftMs
        self.totalMs = totalMs
        self.inputChars = inputChars
        self.outputChars = outputChars
        self.thoughtChars = thoughtChars
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        timestamp = try c.decodeIfPresent(Int.self, forKey: .timestamp) ?? Int(Date().timeIntervalSince1970)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        feature = try c.decodeIfPresent(String.self, forKey: .feature) ?? ""
        thinkingMode = try c.decodeIfPresent(String.self, forKey: .thinkingMode) ?? "auto"
        ttftMs = try c.decodeIfPresent(Int.self, forKey: .ttftMs) ?? 0
        totalMs = try c.decodeIfPresent(Int.self, forKey: .totalMs) ?? 0
        inputChars = try c.decodeIfPresent(Int.self, forKey: .inputChars) ?? 0
        outputChars = try c.decodeIfPresent(Int.self, forKey: .outputChars) ?? 0
        thoughtChars = try c.decodeIfPresent(Int.self, forKey: .thoughtChars) ?? 0
        promptTokens = try c.decodeIfPresent(Int.self, forKey: .promptTokens)
        completionTokens = try c.decodeIfPresent(Int.self, forKey: .completionTokens)
        reasoningTokens = try c.decodeIfPresent(Int.self, forKey: .reasoningTokens)
    }

    var totalReportedTokens: Int {
        (promptTokens ?? 0) + (completionTokens ?? 0)
    }
}

/// App 内「AI 写作工作台」多轮对话消息条目（仅存本机，便于随时续聊）。
struct AIChatTurn: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var role: String // "user" | "assistant"
    var content: String
    var thought: String = ""
    var model: String = ""
    var skillTitle: String = ""
    var hasImageAttachment: Bool = false
    var ttftMs: Int? = nil
    var totalMs: Int? = nil
    var createdAt: Date = Date()

    init(
        id: String = UUID().uuidString,
        role: String,
        content: String,
        thought: String = "",
        model: String = "",
        skillTitle: String = "",
        hasImageAttachment: Bool = false,
        ttftMs: Int? = nil,
        totalMs: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thought = thought
        self.model = model
        self.skillTitle = skillTitle
        self.hasImageAttachment = hasImageAttachment
        self.ttftMs = ttftMs
        self.totalMs = totalMs
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "user"
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        thought = try c.decodeIfPresent(String.self, forKey: .thought) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        skillTitle = try c.decodeIfPresent(String.self, forKey: .skillTitle) ?? ""
        hasImageAttachment = try c.decodeIfPresent(Bool.self, forKey: .hasImageAttachment) ?? false
        ttftMs = try c.decodeIfPresent(Int.self, forKey: .ttftMs)
        totalMs = try c.decodeIfPresent(Int.self, forKey: .totalMs)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// 工作台多话题会话（支持新建、置顶、重命名、切换与导出 Markdown）
struct AIWorkbenchThread: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String = "新对话"
    var skillID: String = "free"
    var isPinned: Bool = false
    var turns: [AIChatTurn] = []
    var updatedAt: Date = Date()

    func exportMarkdown() -> String {
        var lines: [String] = ["# \(title)", ""]
        for t in turns {
            let speaker = t.role == "user" ? "我" : "灵犀 AI（\(t.model.isEmpty ? "默认模型" : t.model)）"
            lines.append("### \(speaker)")
            if !t.thought.isEmpty {
                lines.append("> 思考摘要：\(t.thought.replacingOccurrences(of: "\n", with: " "))")
                lines.append("")
            }
            lines.append(t.content)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

enum AIWorkbenchThreadsStore {
    private static let fileName = "lingxi_ai_workbench_threads.json"

    static func load() -> [AIWorkbenchThread] {
        if let existing = AppGroup.readJSON([AIWorkbenchThread].self, from: fileName), !existing.isEmpty {
            return sortThreads(existing)
        }
        // 兼容迁移旧版单会话记录，零丢失
        let legacyTurns = AIWorkbenchSessionStore.load()
        if !legacyTurns.isEmpty {
            let firstTitle = String((legacyTurns.first(where: { $0.role == "user" })?.content ?? "历史对话").prefix(16))
            let migrated = [AIWorkbenchThread(title: firstTitle.isEmpty ? "历史对话" : firstTitle, turns: legacyTurns)]
            save(migrated)
            return migrated
        }
        return []
    }

    static func save(_ threads: [AIWorkbenchThread]) {
        let sorted = sortThreads(threads)
        let capped = Array(sorted.prefix(24)).map { th -> AIWorkbenchThread in
            var copy = th
            if copy.turns.count > 40 { copy.turns = Array(copy.turns.suffix(40)) }
            return copy
        }
        _ = AppGroup.writeJSON(capped, to: fileName, protected: true)
    }

    private static func sortThreads(_ list: [AIWorkbenchThread]) -> [AIWorkbenchThread] {
        list.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.updatedAt > b.updatedAt
        }
    }
}

/// 多步 AI 链式流水线步骤与工作流定义（支持在 App 分步流式运行，也可一键编译为键盘技能）
struct AIPromptPipelineStep: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var instruction: String
    var preferFast: Bool = false
    var preferDeep: Bool = false
}

struct AIPromptPipeline: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var icon: String = "arrow.triangle.branch"
    var summary: String = ""
    var steps: [AIPromptPipelineStep]

    /// 将多步流水线编译为单条可直接放入键盘 AI 面板的自定义技能
    func compiledAsCustomPrompt() -> CustomAIPromptTemplate {
        let numbered = steps.enumerated().map { idx, st in
            "第\(idx + 1)步【\(st.name)】：\(st.instruction)"
        }.joined(separator: "\n")
        let fullInstruction = "请严格按以下多步流水线依次完成处理，仅输出最终一步的成品结果：\n\(numbered)"
        return CustomAIPromptTemplate(
            id: "pipe_\(id)",
            title: String(title.prefix(10)),
            icon: icon,
            instruction: fullInstruction,
            category: "链式流水线",
            isAIGenerated: false,
            isPinned: true,
            useDeepModel: steps.contains(where: \.preferDeep)
        )
    }

    static let defaultPipelines: [AIPromptPipeline] = [
        AIPromptPipeline(
            id: "pipe_voice_to_bilingual_report",
            title: "口述变双语汇报",
            icon: "briefcase.fill",
            summary: "去口水词 → 结论先行职场汇报 → 附地道英文同步",
            steps: [
                AIPromptPipelineStep(name: "整理口水稿", instruction: "去除口语重复词与语气词，理顺逻辑并补齐标点。", preferFast: true),
                AIPromptPipelineStep(name: "提炼领导汇报", instruction: "改写为结论先行、条理清晰的 3 条简洁中文汇报要点。", preferDeep: false),
                AIPromptPipelineStep(name: "生成双语对照", instruction: "保留中文汇报要点，并在下方附上自然地道的英文职场同步版本。", preferDeep: true),
            ]
        ),
        AIPromptPipeline(
            id: "pipe_tactful_counter",
            title: "棘手消息拆解回复",
            icon: "shield.lefthalf.filled",
            summary: "拆解对方真实意图 → 生成温和但有底线的得体回复",
            steps: [
                AIPromptPipelineStep(name: "洞察潜台词", instruction: "冷静分析对方消息背后的真实诉求、压力点和隐含前提，用 2 句话总结。", preferDeep: true),
                AIPromptPipelineStep(name: "拟定高情商回复", instruction: "基于上一步的洞察，写一段可直接发出的高情商回复：先共情缓冲、再亮明底线、最后给出建设性替代方案。", preferDeep: true),
            ]
        ),
        AIPromptPipeline(
            id: "pipe_article_to_social",
            title: "长文转高级朋友圈",
            icon: "camera.filters",
            summary: "提炼核心金句 → 改写为松弛克制的朋友圈分享文案",
            steps: [
                AIPromptPipelineStep(name: "抽取金句观点", instruction: "从长文中提炼出最有洞察力的 1 个核心观点和 2 个细节亮点。", preferFast: true),
                AIPromptPipelineStep(name: "润色社交分享", instruction: "改写为 2~3 句松弛自然、有画面感、绝不鸡汤的朋友圈分享文案。", preferFast: false),
            ]
        ),
        AIPromptPipeline(
            id: "pipe_idea_to_action",
            title: "想法变可执行清单",
            icon: "checklist",
            summary: "结构化拆解目标 → 排优先级与首日落地动作",
            steps: [
                AIPromptPipelineStep(name: "拆解核心模块", instruction: "把零散想法拆解为目标、关键环节与主要风险。", preferDeep: true),
                AIPromptPipelineStep(name: "输出行动清单", instruction: "转化为按优先级排序的 5 条可执行待办（含预计耗时与今天就能做的第 1 步）。", preferFast: false),
            ]
        ),
    ]
}

enum AIWorkbenchSessionStore {
    private static let fileName = "lingxi_ai_workbench_turns.json"

    static func load() -> [AIChatTurn] {
        AppGroup.readJSON([AIChatTurn].self, from: fileName) ?? []
    }

    static func save(_ turns: [AIChatTurn]) {
        let trimmed = Array(turns.suffix(40))
        _ = AppGroup.writeJSON(trimmed, to: fileName, protected: true)
    }

    static func clear() {
        _ = AppGroup.writeJSON([AIChatTurn](), to: fileName, protected: true)
    }
}

enum AIUsageLedgerStore {
    private static let fileName = "lingxi_ai_usage_ledger.json"

    static func load() -> [AIUsageLedgerEntry] {
        AppGroup.readJSON([AIUsageLedgerEntry].self, from: fileName) ?? []
    }

    static func append(_ entry: AIUsageLedgerEntry) {
        var list = load()
        list.insert(entry, at: 0)
        if list.count > 200 { list = Array(list.prefix(200)) }
        _ = AppGroup.writeJSON(list, to: fileName)
    }

    static func clear() {
        _ = AppGroup.writeJSON([AIUsageLedgerEntry](), to: fileName)
    }
}

/// 最近在键盘内由 AI 生成的回答历史记录（仅存本机，支持键盘内随时翻阅、一键复制与重新插入）。
struct AIRecentResultItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var prompt: String = ""
    var output: String
    var createdAt: Date = Date()

    init(id: String = UUID().uuidString, title: String, prompt: String = "", output: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.output = output
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "AI 回答"
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        output = try c.decodeIfPresent(String.self, forKey: .output) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

enum AIRecentHistoryStore {
    private static let fileName = "lingxi_ai_recent_history.json"

    static func load() -> [AIRecentResultItem] {
        AppGroup.readJSON([AIRecentResultItem].self, from: fileName) ?? []
    }

    static func record(title: String, output: String, prompt: String = "") {
        let clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return }
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = load()
        list.removeAll { $0.output == clean }
        list.insert(AIRecentResultItem(title: title, prompt: cleanPrompt, output: clean), at: 0)
        if list.count > 30 { list = Array(list.prefix(30)) }
        _ = AppGroup.writeJSON(list, to: fileName, protected: true)
    }

    static func delete(id: String) {
        var list = load()
        list.removeAll { $0.id == id }
        _ = AppGroup.writeJSON(list, to: fileName, protected: true)
    }

    static func clear() {
        _ = AppGroup.writeJSON([AIRecentResultItem](), to: fileName, protected: true)
    }
}

/// 键盘内嵌 AI 快捷指令。
enum AIPresetAction: String, CaseIterable, Identifiable {
    case polish
    case smartContinue
    case eqReply
    case strategist
    case proofread
    case organizeVoice
    case translateEn
    case translateZh
    case replyClipboard
    case summarize
    case structureList
    case xiaohongshu
    case classical
    case funny

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polish: return "润色优化"
        case .smartContinue: return "顺着续写"
        case .eqReply: return "高情商回复"
        case .strategist: return "博弈军师"
        case .proofread: return "纠错查病句"
        case .organizeVoice: return "智能整理"
        case .translateEn: return "译为英文"
        case .translateZh: return "译为中文"
        case .replyClipboard: return "回复剪贴板"
        case .summarize: return "精简提炼"
        case .structureList: return "转日程清单"
        case .xiaohongshu: return "小红书风"
        case .classical: return "文言文风"
        case .funny: return "幽默玩梗"
        }
    }

    var icon: String {
        switch self {
        case .polish: return "wand.and.stars"
        case .smartContinue: return "text.append"
        case .eqReply: return "sparkles"
        case .strategist: return "brain.head.profile"
        case .proofread: return "checkmark.bubble"
        case .organizeVoice: return "text.alignleft"
        case .translateEn: return "globe"
        case .translateZh: return "character.book.closed"
        case .replyClipboard: return "doc.on.clipboard.fill"
        case .summarize: return "scissors"
        case .structureList: return "checklist"
        case .xiaohongshu: return "flame"
        case .classical: return "scroll"
        case .funny: return "face.smiling"
        }
    }

    var needsClipboardFallback: Bool {
        self == .replyClipboard || self == .strategist
    }

    var prefersDeepModel: Bool {
        self == .strategist || self == .structureList || self == .classical
    }

    /// 续写模式下默认以追加方式插入，而非替换原文
    var prefersAppendInsert: Bool {
        self == .smartContinue
    }

    var systemPrompt: String {
        let commonRule = "只直接输出最终可直接发送的文本，不要解释过程，不要加多余引号或Markdown标题。"
        switch self {
        case .polish:
            return "你是专业中文文字润色助手。保持原意与语气，修正语病与生硬表达，使语句自然流畅得体。\(commonRule)"
        case .smartContinue:
            return "你是中文无缝续写助手。紧接着用户已经打出的半句话，自然流畅地顺着原语气与上下文续写完剩下的 1-2 句。不要重复用户已写的开头，只输出紧接在后面的续写内容。\(commonRule)"
        case .proofread:
            return "你是极简中文校对编辑。仅修正文本中的错别字、漏字、病句和错误标点，尽可能完整保留用户原本的用词与口吻，不要过度改写。\(commonRule)"
        case .eqReply:
            return "你是高情商沟通专家。把用户的输入或对方消息改写/回复得体、有分寸、温暖且不卑不亢。\(commonRule)"
        case .strategist:
            return "你是高情商职场与社交沟通军师。分析对方消息的真实诉求，给出最得体稳妥的直接回复。\(commonRule)"
        case .organizeVoice:
            return "你是文字整理专家。把口语化、杂乱无章或缺少标点的语音转写/草稿整理为结构清晰、标点准确、去掉口水词的书面表达。\(commonRule)"
        case .translateEn:
            return "You are a native English translator. Translate the user's text into natural, idiomatic English matching the tone. Output only the translation."
        case .translateZh:
            return "你是精通中英文的母语级译者。将输入译为地道、自然、信达雅的简体中文。\(commonRule)"
        case .replyClipboard:
            return "你正在帮用户快速回复聊天消息。根据对方发来的内容，给出一句自然、高情商、可直接发送的中文回复。\(commonRule)"
        case .summarize:
            return "请把给定内容提炼为最核心的几句话或清晰要点，简洁有力。\(commonRule)"
        case .structureList:
            return "请把给定口语或零散信息整理成清晰整齐的结构化日程/待办清单（每行以 • 开头，突出时间、事项与关键动作）。\(commonRule)"
        case .xiaohongshu:
            return "请把内容改写成生动吸睛的小红书风格文案，适当加入自然Emoji，分段舒适有感染力。\(commonRule)"
        case .classical:
            return "请将内容改写为凝练典雅、有古风韵味的文言文或半文白短句，读来朗朗上口。\(commonRule)"
        case .funny:
            return "请用机智幽默、接地气、略带网感但友好的方式重新表达或回复这段话。\(commonRule)"
        }
    }
}

/// 用户自定义 / AI 自动生成的键盘快捷提示词模板（支持单步指令与多步链式流水线，实时同步至键盘 AI 面板）。
struct CustomAIPromptTemplate: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var icon: String = "sparkles"
    var instruction: String
    var category: String = "效率沟通"
    var isAIGenerated: Bool = false
    var isPinned: Bool = false
    var useDeepModel: Bool = false

    init(
        id: String = UUID().uuidString,
        title: String,
        icon: String = "sparkles",
        instruction: String,
        category: String = "效率沟通",
        isAIGenerated: Bool = false,
        isPinned: Bool = false,
        useDeepModel: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.instruction = instruction
        self.category = category
        self.isAIGenerated = isAIGenerated
        self.isPinned = isPinned
        self.useDeepModel = useDeepModel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "自定义技能"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "sparkles"
        instruction = try c.decodeIfPresent(String.self, forKey: .instruction) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "效率沟通"
        isAIGenerated = try c.decodeIfPresent(Bool.self, forKey: .isAIGenerated) ?? false
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        useDeepModel = try c.decodeIfPresent(Bool.self, forKey: .useDeepModel) ?? false
    }

    var effectiveSystemPrompt: String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = "只直接输出最终可直接发送的文本，不要解释过程，不要加多余引号或Markdown标题。"
        if trimmed.isEmpty {
            return "你是灵犀智能输入法写作助手，请优化用户内容使其自然得体。\(rule)"
        }
        return "\(trimmed)\n\(rule)"
    }

    static let defaultTemplates: [CustomAIPromptTemplate] = [
        CustomAIPromptTemplate(
            id: "preset_work_report",
            title: "职场汇报",
            icon: "briefcase.fill",
            instruction: "请把这段草稿整理为结论先行、条理清晰的职场简洁汇报，适合在微信/企微/钉钉直接发给领导或同事。",
            category: "职场商务",
            isAIGenerated: false,
            isPinned: true
        ),
        CustomAIPromptTemplate(
            id: "preset_polite_decline",
            title: "温柔拒绝",
            icon: "hand.raised.fill",
            instruction: "请用礼貌得体、高情商、不伤和气的语气委婉拒绝对方，同时保留后续合作或沟通的余地。",
            category: "效率沟通",
            isAIGenerated: false,
            isPinned: false
        ),
        CustomAIPromptTemplate(
            id: "preset_extract_todo",
            title: "拆解待办",
            icon: "checklist",
            instruction: "请从内容中提取出清晰可执行的待办清单（用简洁序号列出事项、负责人与时间节点）。",
            category: "效率沟通",
            isAIGenerated: false,
            isPinned: false
        ),
        CustomAIPromptTemplate(
            id: "preset_pipeline_bilingual",
            title: "双语周报链",
            icon: "arrow.triangle.branch",
            instruction: "请按两步流水线执行：第1步去掉口语词并提炼为3条简洁中文进展；第2步在每条下方附上自然地道的英文职场同步表达。",
            category: "链式流水线",
            isAIGenerated: false,
            isPinned: false,
            useDeepModel: true
        ),
    ]
}

/// 主 App 内置「AI 场景指令市场」精选 20 条开箱即用高质量键盘技能模板（支持一键装入键盘 AI 栏）。
enum AIPromptMarketplaceCatalog {
    static let allTemplates: [CustomAIPromptTemplate] = [
        // 💬 微信高情商
        CustomAIPromptTemplate(id: "mkt_nudge_progress", title: "礼貌催进度", icon: "clock.badge.checkmark", instruction: "帮我把这段催促改写得既不显得咄咄逼人、又能清晰锁定对方答复时间节点的礼貌微信消息。", category: "微信高情商"),
        CustomAIPromptTemplate(id: "mkt_decline_borrow", title: "委婉拒借钱", icon: "hand.raised.fill", instruction: "用真诚、有边界感又不伤感情的口吻委婉拒绝对方借钱或额外帮忙请求，给出体面理由。", category: "微信高情商"),
        CustomAIPromptTemplate(id: "mkt_warm_comfort", title: "暖心安慰", icon: "heart.fill", instruction: "针对对方遇到烦心事或疲惫倾诉，写一句真诚共情、不讲大道理、让人瞬间松一口气的温暖回复。", category: "微信高情商"),
        CustomAIPromptTemplate(id: "mkt_flirt_banter", title: "拉近距离", icon: "sparkles", instruction: "把回复改得轻松自然、略带一点机智和好感，不油腻不刻意，像聊得很投机的朋友。", category: "微信高情商"),

        // 💼 职场办公
        CustomAIPromptTemplate(id: "mkt_weekly_report", title: "一键周报", icon: "doc.text.fill", instruction: "将零散工作记录整理为「本周核心进展 / 风险与阻塞 / 下周计划」三段简洁周报，突出量化结果。", category: "职场办公", useDeepModel: true),
        CustomAIPromptTemplate(id: "mkt_meeting_minutes", title: "会议纪要", icon: "list.bullet.clipboard", instruction: "把杂乱会议记录提炼为：核心结论、待办事项（负责人+截止时间）、待确认问题，格式清爽。", category: "职场办公", useDeepModel: true),
        CustomAIPromptTemplate(id: "mkt_client_followup", title: "客户报价跟进", icon: "briefcase.fill", instruction: "写一条专业得体、不卑不亢的客户报价/合作跟进消息，自然提醒下一步推进节点。", category: "职场办公"),
        CustomAIPromptTemplate(id: "mkt_blame_shield", title: "专业甩锅防护", icon: "shield.lefthalf.filled", instruction: "在群聊中冷静、客观、基于事实澄清责任边界与时间线，既不情绪化又能保护自己团队利益。", category: "职场办公", useDeepModel: true),

        // 🔥 社交种草
        CustomAIPromptTemplate(id: "mkt_moments_caption", title: "高级朋友圈", icon: "camera.filters", instruction: "把这段随想改写成松弛、有画面感、不矫情的朋友圈配文，1-3句恰到好处，严禁鸡汤。", category: "社交种草"),
        CustomAIPromptTemplate(id: "mkt_food_review", title: "探店美食评", icon: "fork.knife", instruction: "结合当前所在城市风味，把这几句评价扩写为真实走心、有细节感的探店点评（适合大众点评/小红书）。", category: "社交种草"),
        CustomAIPromptTemplate(id: "mkt_short_video_hook", title: "爆款开头钩子", icon: "flame.fill", instruction: "把这段主题改写成 3 秒抓眼球的短视频开场白与核心口播金句，短句有力。", category: "社交种草"),

        // 📍 本地出行与生活
        CustomAIPromptTemplate(id: "mkt_local_invite", title: "本地约饭局", icon: "mappin.and.ellipse", instruction: "结合当前所在地区与时间，把这段话润色成轻松热情、时间地点清晰的约饭/碰面邀请。", category: "本地生活"),
        CustomAIPromptTemplate(id: "mkt_route_guide", title: "清晰指路", icon: "map.fill", instruction: "把零散的地址和路线提示整理为一眼看懂的到达指引（含地标、入口与停车/打车提示）。", category: "本地生活"),
        CustomAIPromptTemplate(id: "mkt_buyer_bargain", title: "闲鱼神砍价", icon: "tag.fill", instruction: "写一句有礼貌、有诚意、让卖家容易松口的闲鱼/二手交易咨询与议价消息。", category: "本地生活"),

        // 🌍 跨境与多语
        CustomAIPromptTemplate(id: "mkt_en_email", title: "地道英文邮件", icon: "envelope.fill", instruction: "将这段中文改写为地道、专业、简洁的商务英文邮件正文（Native English tone，无中式英语）。", category: "跨境多语"),
        CustomAIPromptTemplate(id: "mkt_jp_polite", title: "日语敬语回复", icon: "globe.asia.australia", instruction: "将内容译为自然得体的日语礼貌体（です・ます/敬语），适合商务或日常礼貌交流。", category: "跨境多语"),
        CustomAIPromptTemplate(id: "mkt_en_grammar_fix", title: "英文语法精修", icon: "textformat.abc", instruction: "Fix grammar, word choice, and natural flow of this English text while keeping the original intent. Output only the improved English.", category: "跨境多语"),

        // 💻 极客与效率
        CustomAIPromptTemplate(id: "mkt_bug_report", title: "规范提 Bug", icon: "ladybug.fill", instruction: "将这段问题描述整理为标准研发 Bug 单格式：现象、复现步骤、预期结果与影响范围。", category: "极客效率"),
        CustomAIPromptTemplate(id: "mkt_pr_review", title: "温和代码评审", icon: "chevron.left.forwardslash.chevron.right", instruction: "把这段技术挑刺改写为建设性、尊重同事且直指根因的 Code Review 评审意见。", category: "极客效率"),
        CustomAIPromptTemplate(id: "mkt_prompt_upgrade", title: "口语转专业Prompt", icon: "cpu.fill", instruction: "把用户的简短大白话需求改写为结构清晰、角色明确、约束完整的高质量 AI 提示词。", category: "极客效率", useDeepModel: true),
    ]

    static var categories: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in allTemplates where seen.insert(t.category).inserted {
            out.append(t.category)
        }
        return out
    }
}

/// 仅含提示词、人设、知识卡与流水线的无密钥同步载荷（绝不把明文 API Key 放入云端同步快照）。
struct AIPromptsSyncPayload: Codable, Equatable {
    var customPersonaPrompt: String = ""
    var customPrompts: [CustomAIPromptTemplate] = []
    var contextCards: [PersonalContextCard] = []
    var aiPipelines: [AIPromptPipeline] = []
    var privacyCustomTerms: [String] = []
    var aiTriggerPrefix: String = "@ai"
    var aiContextCharLimit: Int = 240
    var temperature: Double = 0.7
    var thinkingMode: AIThinkingMode = .auto
    var smartContextRecommendEnabled: Bool = true
    var enabledBuiltinActions: [String] = []
    var keyboardShowAllCustomPrompts: Bool = true
    var updatedAt: Int = Int(Date().timeIntervalSince1970)

    init(
        customPersonaPrompt: String = "",
        customPrompts: [CustomAIPromptTemplate] = [],
        contextCards: [PersonalContextCard] = [],
        aiPipelines: [AIPromptPipeline] = [],
        privacyCustomTerms: [String] = [],
        aiTriggerPrefix: String = "@ai",
        aiContextCharLimit: Int = 240,
        temperature: Double = 0.7,
        thinkingMode: AIThinkingMode = .auto,
        smartContextRecommendEnabled: Bool = true,
        enabledBuiltinActions: [String] = [],
        keyboardShowAllCustomPrompts: Bool = true,
        updatedAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.customPersonaPrompt = customPersonaPrompt
        self.customPrompts = customPrompts
        self.contextCards = contextCards
        self.aiPipelines = aiPipelines
        self.privacyCustomTerms = privacyCustomTerms
        self.aiTriggerPrefix = aiTriggerPrefix
        self.aiContextCharLimit = aiContextCharLimit
        self.temperature = temperature
        self.thinkingMode = thinkingMode
        self.smartContextRecommendEnabled = smartContextRecommendEnabled
        self.enabledBuiltinActions = enabledBuiltinActions
        self.keyboardShowAllCustomPrompts = keyboardShowAllCustomPrompts
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customPersonaPrompt = try c.decodeIfPresent(String.self, forKey: .customPersonaPrompt) ?? ""
        customPrompts = try c.decodeIfPresent([CustomAIPromptTemplate].self, forKey: .customPrompts) ?? []
        contextCards = try c.decodeIfPresent([PersonalContextCard].self, forKey: .contextCards) ?? []
        aiPipelines = try c.decodeIfPresent([AIPromptPipeline].self, forKey: .aiPipelines) ?? []
        privacyCustomTerms = try c.decodeIfPresent([String].self, forKey: .privacyCustomTerms) ?? []
        let rawPrefix = (try c.decodeIfPresent(String.self, forKey: .aiTriggerPrefix) ?? "@ai").trimmingCharacters(in: .whitespacesAndNewlines)
        aiTriggerPrefix = rawPrefix.isEmpty ? "@ai" : rawPrefix
        aiContextCharLimit = max(60, min(800, try c.decodeIfPresent(Int.self, forKey: .aiContextCharLimit) ?? 240))
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        thinkingMode = try c.decodeIfPresent(AIThinkingMode.self, forKey: .thinkingMode) ?? .auto
        smartContextRecommendEnabled = try c.decodeIfPresent(Bool.self, forKey: .smartContextRecommendEnabled) ?? true
        enabledBuiltinActions = try c.decodeIfPresent([String].self, forKey: .enabledBuiltinActions) ?? []
        keyboardShowAllCustomPrompts = try c.decodeIfPresent(Bool.self, forKey: .keyboardShowAllCustomPrompts) ?? true
        updatedAt = try c.decodeIfPresent(Int.self, forKey: .updatedAt) ?? Int(Date().timeIntervalSince1970)
    }
}

/// 全套无密钥「灵犀 AI 智脑配置包」（用于个人备份、跨设备迁移或分享给朋友，绝对不含任何 API Key）
struct AIBrainExportBundle: Codable, Equatable {
    var format: String = "LINGXI-AI-BRAIN-BUNDLE-V1"
    var exportedAt: Int = Int(Date().timeIntervalSince1970)
    var customPersonaPrompt: String = ""
    var styleDNA: PersonalStyleDNA = PersonalStyleDNA()
    var customPrompts: [CustomAIPromptTemplate] = []
    var contextCards: [PersonalContextCard] = []
    var aiPipelines: [AIPromptPipeline] = []
    var privacyCustomTerms: [String] = []
    var enabledBuiltinActions: [String] = []
}

/// AI 配置与密钥持久化（存于 App Group 受保护文件中，支持三协议、拉取模型、自动容灾、思考模式与文风 DNA）。
struct AIConfig: Codable, Equatable {
    static let defaultGeminiBaseURL = "https://generativelanguage.googleapis.com"
    static let defaultAnthropicBaseURL = "https://api.anthropic.com"
    static let defaultAnthropicModel = "claude-sonnet-4-20250514"
    static let defaultKeyboardBuiltinActions: [AIPresetAction] = [
        .polish, .eqReply, .smartContinue, .strategist, .translateEn, .translateZh, .proofread, .summarize
    ]

    var provider: AIProvider = .gemini
    var geminiAPIKey: String = ""
    var geminiBaseURL: String = AIConfig.defaultGeminiBaseURL
    var geminiModel: String = GeminiModelOption.flash25.rawValue
    var openAIBaseURL: String = "https://api.deepseek.com/v1"
    var openAIAPIKey: String = ""
    var openAIModel: String = "deepseek-chat"
    var anthropicBaseURL: String = AIConfig.defaultAnthropicBaseURL
    var anthropicAPIKey: String = ""
    var anthropicModel: String = AIConfig.defaultAnthropicModel

    // 多场景路由模型、自动容灾备份渠道与动态拉取的模型列表
    var fastModel: String = ""
    var deepModel: String = ""
    var visionModel: String = ""
    var sttModel: String = ""
    var failoverProfileID: String? = nil
    var fetchedModels: [AIModelInfo] = []
    var fetchedModelsSourceKey: String = ""
    var customHeaders: [String: String] = [:]

    // 思考模式与高级生成参数
    var thinkingMode: AIThinkingMode = .auto
    var thinkingBudget: Int = 2048
    var showThinkingProcess: Bool = true
    var temperature: Double = 0.7
    var topP: Double = 0.95
    var maxOutputTokens: Int = 2048

    // 多服务商档案
    var profiles: [AIProviderProfile] = []
    var activeProfileID: String? = nil

    // 个人人设、场景、提示词库、文风 DNA、背景知识卡与键盘 AI 栏排布
    var customPersonaPrompt: String = ""
    var activeScenePersona: AIScenePersona = .auto
    var customPrompts: [CustomAIPromptTemplate] = CustomAIPromptTemplate.defaultTemplates
    var styleDNA: PersonalStyleDNA = PersonalStyleDNA()
    var contextCards: [PersonalContextCard] = []
    var autoAnalyzeOnConnect: Bool = true
    var smartContextRecommendEnabled: Bool = true
    var enabledBuiltinActions: [String] = []
    var keyboardShowAllCustomPrompts: Bool = true
    var autoDiffLearnEnabled: Bool = true
    // 端侧 AI 隐私脱敏护盾 + 多步流水线 + 键盘 @ai 交互偏好
    var privacyShieldEnabled: Bool = false
    var privacyAutoRestore: Bool = true
    var privacyCustomTerms: [String] = []
    var aiPipelines: [AIPromptPipeline] = AIPromptPipeline.defaultPipelines
    var aiTriggerPrefix: String = "@ai"
    var aiContextCharLimit: Int = 240
    /// 可选月度费用预算提醒阈值（人民币，0 表示不限）
    var monthlyBudgetCNY: Double = 0

    private static let fileName = "lingxi_ai_config.json"
    static let promptsSyncFileName = "lingxi_ai_prompts_sync.json"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .gemini
        geminiAPIKey = try c.decodeIfPresent(String.self, forKey: .geminiAPIKey) ?? ""
        let rawGeminiURL = try c.decodeIfPresent(String.self, forKey: .geminiBaseURL) ?? Self.defaultGeminiBaseURL
        geminiBaseURL = rawGeminiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultGeminiBaseURL : rawGeminiURL
        geminiModel = try c.decodeIfPresent(String.self, forKey: .geminiModel) ?? GeminiModelOption.flash25.rawValue
        openAIBaseURL = try c.decodeIfPresent(String.self, forKey: .openAIBaseURL) ?? "https://api.deepseek.com/v1"
        openAIAPIKey = try c.decodeIfPresent(String.self, forKey: .openAIAPIKey) ?? ""
        openAIModel = try c.decodeIfPresent(String.self, forKey: .openAIModel) ?? "deepseek-chat"
        let rawAnthropicURL = try c.decodeIfPresent(String.self, forKey: .anthropicBaseURL) ?? Self.defaultAnthropicBaseURL
        anthropicBaseURL = rawAnthropicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultAnthropicBaseURL : rawAnthropicURL
        anthropicAPIKey = try c.decodeIfPresent(String.self, forKey: .anthropicAPIKey) ?? ""
        let rawAnthropicModel = try c.decodeIfPresent(String.self, forKey: .anthropicModel) ?? Self.defaultAnthropicModel
        anthropicModel = rawAnthropicModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultAnthropicModel : rawAnthropicModel
        fastModel = try c.decodeIfPresent(String.self, forKey: .fastModel) ?? ""
        deepModel = try c.decodeIfPresent(String.self, forKey: .deepModel) ?? ""
        visionModel = try c.decodeIfPresent(String.self, forKey: .visionModel) ?? ""
        sttModel = try c.decodeIfPresent(String.self, forKey: .sttModel) ?? ""
        failoverProfileID = try c.decodeIfPresent(String.self, forKey: .failoverProfileID)
        fetchedModels = try c.decodeIfPresent([AIModelInfo].self, forKey: .fetchedModels) ?? []
        fetchedModelsSourceKey = try c.decodeIfPresent(String.self, forKey: .fetchedModelsSourceKey) ?? ""
        customHeaders = try c.decodeIfPresent([String: String].self, forKey: .customHeaders) ?? [:]
        thinkingMode = try c.decodeIfPresent(AIThinkingMode.self, forKey: .thinkingMode) ?? .auto
        thinkingBudget = max(0, min(32768, try c.decodeIfPresent(Int.self, forKey: .thinkingBudget) ?? 2048))
        showThinkingProcess = try c.decodeIfPresent(Bool.self, forKey: .showThinkingProcess) ?? true
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        topP = try c.decodeIfPresent(Double.self, forKey: .topP) ?? 0.95
        maxOutputTokens = max(256, min(16384, try c.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? 2048))
        profiles = try c.decodeIfPresent([AIProviderProfile].self, forKey: .profiles) ?? []
        activeProfileID = try c.decodeIfPresent(String.self, forKey: .activeProfileID)
        customPersonaPrompt = try c.decodeIfPresent(String.self, forKey: .customPersonaPrompt) ?? ""
        activeScenePersona = try c.decodeIfPresent(AIScenePersona.self, forKey: .activeScenePersona) ?? .auto
        customPrompts = try c.decodeIfPresent([CustomAIPromptTemplate].self, forKey: .customPrompts) ?? CustomAIPromptTemplate.defaultTemplates
        styleDNA = try c.decodeIfPresent(PersonalStyleDNA.self, forKey: .styleDNA) ?? PersonalStyleDNA()
        contextCards = try c.decodeIfPresent([PersonalContextCard].self, forKey: .contextCards) ?? []
        autoAnalyzeOnConnect = try c.decodeIfPresent(Bool.self, forKey: .autoAnalyzeOnConnect) ?? true
        smartContextRecommendEnabled = try c.decodeIfPresent(Bool.self, forKey: .smartContextRecommendEnabled) ?? true
        enabledBuiltinActions = try c.decodeIfPresent([String].self, forKey: .enabledBuiltinActions) ?? []
        keyboardShowAllCustomPrompts = try c.decodeIfPresent(Bool.self, forKey: .keyboardShowAllCustomPrompts) ?? true
        autoDiffLearnEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoDiffLearnEnabled) ?? true
        privacyShieldEnabled = try c.decodeIfPresent(Bool.self, forKey: .privacyShieldEnabled) ?? false
        privacyAutoRestore = try c.decodeIfPresent(Bool.self, forKey: .privacyAutoRestore) ?? true
        privacyCustomTerms = try c.decodeIfPresent([String].self, forKey: .privacyCustomTerms) ?? []
        aiPipelines = try c.decodeIfPresent([AIPromptPipeline].self, forKey: .aiPipelines) ?? AIPromptPipeline.defaultPipelines
        let rawPrefix = (try c.decodeIfPresent(String.self, forKey: .aiTriggerPrefix) ?? "@ai").trimmingCharacters(in: .whitespacesAndNewlines)
        aiTriggerPrefix = rawPrefix.isEmpty ? "@ai" : rawPrefix
        aiContextCharLimit = max(60, min(800, try c.decodeIfPresent(Int.self, forKey: .aiContextCharLimit) ?? 240))
        monthlyBudgetCNY = max(0, min(10_000, try c.decodeIfPresent(Double.self, forKey: .monthlyBudgetCNY) ?? 0))
    }

    static func load() -> AIConfig {
        var cfg = AppGroup.readJSON(AIConfig.self, from: fileName) ?? AIConfig()
        // 云端 E2EE 拉取的无密钥智脑快照自动增量并集合入，绝不覆盖本地新增条目或 API Key
        if let synced = AppGroup.readJSON(AIPromptsSyncPayload.self, from: promptsSyncFileName) {
            if !synced.customPrompts.isEmpty {
                var existingIDs = Set(cfg.customPrompts.map(\.id))
                var existingTitles = Set(cfg.customPrompts.map(\.title))
                for p in synced.customPrompts where !existingIDs.contains(p.id) && !existingTitles.contains(p.title) {
                    cfg.customPrompts.append(p)
                    existingIDs.insert(p.id)
                    existingTitles.insert(p.title)
                }
            }
            if cfg.customPersonaPrompt.isEmpty && !synced.customPersonaPrompt.isEmpty {
                cfg.customPersonaPrompt = synced.customPersonaPrompt
            }
            if !synced.contextCards.isEmpty {
                var existingCardIDs = Set(cfg.contextCards.map(\.id))
                var existingCardTitles = Set(cfg.contextCards.map(\.title))
                for card in synced.contextCards where !existingCardIDs.contains(card.id) && !existingCardTitles.contains(card.title) {
                    cfg.contextCards.append(card)
                    existingCardIDs.insert(card.id)
                    existingCardTitles.insert(card.title)
                }
            }
            if !synced.aiPipelines.isEmpty {
                var existingPipeIDs = Set(cfg.aiPipelines.map(\.id))
                var existingPipeTitles = Set(cfg.aiPipelines.map(\.title))
                for pipe in synced.aiPipelines where !existingPipeIDs.contains(pipe.id) && !existingPipeTitles.contains(pipe.title) {
                    cfg.aiPipelines.append(pipe)
                    existingPipeIDs.insert(pipe.id)
                    existingPipeTitles.insert(pipe.title)
                }
            }
            for term in synced.privacyCustomTerms where !cfg.privacyCustomTerms.contains(term) {
                cfg.privacyCustomTerms.append(term)
            }
        }
        if let syncedDNA = AppGroup.readJSON(PersonalStyleDNA.self, from: PersonalStyleDNA.fileName),
           syncedDNA.updatedAt > cfg.styleDNA.updatedAt {
            cfg.styleDNA = syncedDNA
        }
        return cfg
    }

    @discardableResult
    func save() -> Bool {
        let syncPayload = AIPromptsSyncPayload(
            customPersonaPrompt: customPersonaPrompt,
            customPrompts: customPrompts,
            contextCards: contextCards,
            aiPipelines: aiPipelines,
            privacyCustomTerms: privacyCustomTerms,
            aiTriggerPrefix: aiTriggerPrefix,
            aiContextCharLimit: aiContextCharLimit,
            temperature: temperature,
            thinkingMode: thinkingMode,
            smartContextRecommendEnabled: smartContextRecommendEnabled,
            enabledBuiltinActions: enabledBuiltinActions,
            keyboardShowAllCustomPrompts: keyboardShowAllCustomPrompts
        )
        _ = AppGroup.writeJSON(syncPayload, to: Self.promptsSyncFileName, protected: true)
        _ = AppGroup.writeJSON(styleDNA, to: PersonalStyleDNA.fileName, protected: true)
        let ok = AppGroup.writeJSON(self, to: Self.fileName, protected: true)
        if ok {
            AppGroupNotifications.post(AppGroupNotifications.aiConfigChanged)
        }
        return ok
    }

    var activeBaseURL: String {
        switch provider {
        case .gemini:
            let u = geminiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return u.isEmpty ? Self.defaultGeminiBaseURL : u
        case .openAICompatible:
            return openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        case .anthropic:
            let u = anthropicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return u.isEmpty ? Self.defaultAnthropicBaseURL : u
        }
    }

    /// 标识当前渠道 + 接口地址的稳定指纹，避免切渠道后误把旧渠道的模型缓存当成新渠道模型列表。
    var currentModelsSourceKey: String {
        "\(provider.rawValue)|\(activeBaseURL.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    var activeAPIKey: String {
        switch provider {
        case .gemini: return geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openAICompatible: return openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .anthropic: return anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var activeModelName: String {
        switch provider {
        case .gemini:
            let m = geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? GeminiModelOption.flash25.rawValue : m
        case .openAICompatible:
            let m = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? "deepseek-chat" : m
        case .anthropic:
            let m = anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? Self.defaultAnthropicModel : m
        }
    }

    mutating func setActiveModel(_ modelID: String) {
        switch provider {
        case .gemini: geminiModel = modelID
        case .openAICompatible: openAIModel = modelID
        case .anthropic: anthropicModel = modelID
        }
    }

    /// 解析当前已配置的容灾自动兜底渠道（排除与当前渠道完全相同或无 Key 的无效档案）
    func resolvedFailoverConfig() -> (profileName: String, config: AIConfig)? {
        guard let fid = failoverProfileID, !fid.isEmpty, fid != activeProfileID,
              let prof = profiles.first(where: { $0.id == fid }) else {
            return nil
        }
        let backup = applying(profile: prof)
        guard backup.isConfigured else { return nil }
        return (prof.name, backup)
    }

    /// 导出无密钥全量 AI 智脑配置包 JSON（绝不导出任何 API Key）
    func exportBrainBundleJSON() -> Data? {
        let bundle = AIBrainExportBundle(
            customPersonaPrompt: customPersonaPrompt,
            styleDNA: styleDNA,
            customPrompts: customPrompts,
            contextCards: contextCards,
            aiPipelines: aiPipelines,
            privacyCustomTerms: privacyCustomTerms,
            enabledBuiltinActions: enabledBuiltinActions
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(bundle)
    }

    /// 安全合入外部无密钥 AI 智脑配置包（返回新增条数统计，绝不覆盖本地 API Key）
    @discardableResult
    mutating func importBrainBundleJSON(_ data: Data) -> (prompts: Int, cards: Int, pipelines: Int)? {
        guard let bundle = try? JSONDecoder().decode(AIBrainExportBundle.self, from: data),
              bundle.format.hasPrefix("LINGXI-AI-BRAIN-BUNDLE") else {
            return nil
        }
        if customPersonaPrompt.isEmpty && !bundle.customPersonaPrompt.isEmpty {
            customPersonaPrompt = bundle.customPersonaPrompt
        }
        if styleDNA.clonedStyleSummary.isEmpty && !bundle.styleDNA.clonedStyleSummary.isEmpty {
            styleDNA.clonedStyleSummary = bundle.styleDNA.clonedStyleSummary
        }
        for w in bundle.styleDNA.personalCatchphrases where !styleDNA.personalCatchphrases.contains(w) {
            styleDNA.personalCatchphrases.append(w)
        }
        for w in bundle.styleDNA.bannedAICliches where !styleDNA.bannedAICliches.contains(w) {
            styleDNA.bannedAICliches.append(w)
        }
        for term in bundle.privacyCustomTerms where !privacyCustomTerms.contains(term) {
            privacyCustomTerms.append(term)
        }
        if enabledBuiltinActions.isEmpty && !bundle.enabledBuiltinActions.isEmpty {
            enabledBuiltinActions = bundle.enabledBuiltinActions
        }
        var addedP = 0
        var existingPTitles = Set(customPrompts.map(\.title))
        for p in bundle.customPrompts where existingPTitles.insert(p.title).inserted {
            customPrompts.insert(p, at: 0)
            addedP += 1
        }
        var addedC = 0
        var existingCTitles = Set(contextCards.map(\.title))
        for c in bundle.contextCards where existingCTitles.insert(c.title).inserted {
            contextCards.insert(c, at: 0)
            addedC += 1
        }
        var addedPipe = 0
        var existingPipeTitles = Set(aiPipelines.map(\.title))
        for pipe in bundle.aiPipelines where existingPipeTitles.insert(pipe.title).inserted {
            aiPipelines.insert(pipe, at: 0)
            addedPipe += 1
        }
        return (addedP, addedC, addedPipe)
    }

    func resolvedModel(preferFast: Bool = false, preferDeep: Bool = false) -> String {
        if preferFast {
            let fm = fastModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fm.isEmpty { return fm }
        }
        if preferDeep {
            let dm = deepModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !dm.isEmpty { return dm }
        }
        return activeModelName
    }

    func resolvedVisionModel() -> String {
        let vm = visionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return vm.isEmpty ? activeModelName : vm
    }

    func resolvedSTTModel(baseURL: String) -> String {
        let sm = sttModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sm.isEmpty { return sm }
        let lower = baseURL.lowercased()
        if lower.contains("siliconflow") { return "FunAudioLLM/SenseVoiceSmall" }
        if lower.contains("groq.com") { return "whisper-large-v3-turbo" }
        return "whisper-1"
    }

    /// 键盘 AI 面板实际展示的内置技能（按用户勾选顺序；未配置时使用推荐 8 项核心技能）
    var resolvedKeyboardBuiltinActions: [AIPresetAction] {
        let parsed = enabledBuiltinActions.compactMap { AIPresetAction(rawValue: $0) }
        return parsed.isEmpty ? Self.defaultKeyboardBuiltinActions : parsed
    }

    /// 键盘 AI 面板实际展示的自定义技能（置顶优先；开启「显示全部」后市场装入的技能立即可见）
    var resolvedKeyboardCustomPrompts: [CustomAIPromptTemplate] {
        let pinned = customPrompts.filter(\.isPinned)
        if !keyboardShowAllCustomPrompts {
            return pinned
        }
        let others = customPrompts.filter { !$0.isPinned }
        return pinned + others
    }

    /// 导出自定义技能为格式化 JSON 字节（便于文件分享与备份）
    func exportCustomPromptsJSON() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(customPrompts)
    }

    static func decodeCustomPromptsJSON(_ data: Data) -> [CustomAIPromptTemplate]? {
        if let arr = try? JSONDecoder().decode([CustomAIPromptTemplate].self, from: data) {
            return arr
        }
        if let single = try? JSONDecoder().decode(CustomAIPromptTemplate.self, from: data) {
            return [single]
        }
        return nil
    }

    /// 兼容本地 Ollama 等无需 API Key 的局域网模型端点
    var isLocalNoKeyEndpoint: Bool {
        guard provider == .openAICompatible else { return false }
        let lower = openAIBaseURL.lowercased()
        return lower.contains("127.0.0.1") || lower.contains("localhost") || lower.contains("192.168.") || lower.contains("10.")
    }

    var isConfigured: Bool {
        !activeAPIKey.isEmpty || isLocalNoKeyEndpoint
    }

    /// 将当前活跃配置保存/更新为一个命名渠道档案（createNew == true 时强制新建，绝不覆写旧档案）
    mutating func saveCurrentAsProfile(name: String, createNew: Bool = false) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = cleanName.isEmpty ? activeModelName : cleanName
        let currentURL = activeBaseURL
        if !createNew, let aid = activeProfileID, let idx = profiles.firstIndex(where: { $0.id == aid }) {
            profiles[idx].name = label
            profiles[idx].provider = provider
            profiles[idx].baseURL = currentURL
            profiles[idx].apiKey = activeAPIKey
            profiles[idx].model = activeModelName
            profiles[idx].fastModel = fastModel
            profiles[idx].deepModel = deepModel
            profiles[idx].visionModel = visionModel
            profiles[idx].sttModel = sttModel
            profiles[idx].thinkingMode = thinkingMode
            profiles[idx].thinkingBudget = thinkingBudget
            profiles[idx].fetchedModels = fetchedModels
            profiles[idx].customHeaders = customHeaders
        } else {
            let profile = AIProviderProfile(
                name: label,
                provider: provider,
                baseURL: currentURL,
                apiKey: activeAPIKey,
                model: activeModelName,
                fastModel: fastModel,
                deepModel: deepModel,
                visionModel: visionModel,
                sttModel: sttModel,
                thinkingMode: thinkingMode,
                thinkingBudget: thinkingBudget,
                fetchedModels: fetchedModels,
                customHeaders: customHeaders
            )
            profiles.insert(profile, at: 0)
            activeProfileID = profile.id
        }
    }

    /// 依据某个渠道档案构造独立 AIConfig 快照（供跨渠道双模型 PK 并排对比使用）
    func applying(profile: AIProviderProfile) -> AIConfig {
        var copy = self
        copy.activateProfile(profile)
        return copy
    }

    /// 一键切换到已保存的某个服务商档案
    mutating func activateProfile(_ profile: AIProviderProfile) {
        activeProfileID = profile.id
        provider = profile.provider
        switch profile.provider {
        case .gemini:
            geminiBaseURL = profile.baseURL.isEmpty ? Self.defaultGeminiBaseURL : profile.baseURL
            geminiAPIKey = profile.apiKey
            geminiModel = profile.model
        case .openAICompatible:
            openAIBaseURL = profile.baseURL
            openAIAPIKey = profile.apiKey
            openAIModel = profile.model
        case .anthropic:
            anthropicBaseURL = profile.baseURL.isEmpty ? Self.defaultAnthropicBaseURL : profile.baseURL
            anthropicAPIKey = profile.apiKey
            anthropicModel = profile.model
        }
        fastModel = profile.fastModel
        deepModel = profile.deepModel
        visionModel = profile.visionModel
        sttModel = profile.sttModel
        thinkingMode = profile.thinkingMode
        thinkingBudget = profile.thinkingBudget
        fetchedModels = profile.fetchedModels
        fetchedModelsSourceKey = profile.fetchedModels.isEmpty ? "" : currentModelsSourceKey
        customHeaders = profile.customHeaders
    }
}

/// 实时互译模式（「译」）支持的目标语言列表（参照 WowType 14 语种设计）。
enum TranslateTargetLanguage: String, CaseIterable, Identifiable {
    case english = "英文"
    case japanese = "日文"
    case korean = "韩文"
    case french = "法文"
    case german = "德文"
    case spanish = "西班牙文"
    case russian = "俄文"
    case italian = "意大利文"
    case portuguese = "葡萄牙文"
    case thai = "泰文"
    case vietnamese = "越南文"
    case arabic = "阿拉伯文"
    case cantonese = "粤语"
    case classicalChinese = "文言文"

    var id: String { rawValue }

    static func systemPrompt(for targetName: String, formal: Bool = false) -> String {
        let toneRule = formal
            ? "请使用礼貌、严谨、得体的正式书面/商务语气。"
            : "请使用自然、地道、贴近日常聊天的口语化表达。"
        return """
        你是实时输入法互译引擎。
        规则：
        - 如果输入主要是中文，请将其准确、地道地翻译成「\(targetName)」。
        - 如果输入主要是外文，请将其准确、自然地翻译成简体中文。
        - \(toneRule)
        - 保留数字、符号、专有名词的准确含义。
        - 只输出最终译文本身，绝对不要加任何解释、引号或前缀。
        """
    }
}

/// 实时语音同传转换模式（支持中英日实时双语互译及纯语音转文字，动态切换 Apple SpeechRecognizer 源语言）。
enum VoiceTranslateMode: String, Codable, CaseIterable, Identifiable {
    case zhToEn
    case enToZh
    case zhToJa
    case jaToZh
    case zhDictation
    case enDictation

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .zhToEn: return "说中文 → 英语"
        case .enToZh: return "说英语 → 中文"
        case .zhToJa: return "说中文 → 日语"
        case .jaToZh: return "说日语 → 中文"
        case .zhDictation: return "中文转文字"
        case .enDictation: return "英语转文字"
        }
    }

    var pillTitle: String {
        switch self {
        case .zhToEn: return "中 → 英"
        case .enToZh: return "英 → 中"
        case .zhToJa: return "中 → 日"
        case .jaToZh: return "日 → 中"
        case .zhDictation: return "中文转字"
        case .enDictation: return "英语转字"
        }
    }

    var sourceLocaleID: String {
        switch self {
        case .zhToEn, .zhToJa, .zhDictation: return "zh-CN"
        case .enToZh, .enDictation: return "en-US"
        case .jaToZh: return "ja-JP"
        }
    }

    var outputSpeechLocaleID: String {
        switch self {
        case .zhToEn, .enDictation: return "en-US"
        case .enToZh, .jaToZh, .zhDictation: return "zh-CN"
        case .zhToJa: return "ja-JP"
        }
    }

    var sourceLanguageLabel: String {
        switch self {
        case .zhToEn, .zhToJa, .zhDictation: return "中文语音"
        case .enToZh, .enDictation: return "English Speech"
        case .jaToZh: return "日本語音声"
        }
    }

    var targetLanguageLabel: String {
        switch self {
        case .zhToEn: return "实时英文译文"
        case .enToZh, .jaToZh: return "实时中文译文"
        case .zhToJa: return "实时日文译文"
        case .zhDictation: return "AI 标点整编中文"
        case .enDictation: return "AI 精修英文"
        }
    }

    var isTranslationMode: Bool {
        self != .zhDictation && self != .enDictation
    }

    var flipped: VoiceTranslateMode {
        switch self {
        case .zhToEn: return .enToZh
        case .enToZh: return .zhToEn
        case .zhToJa: return .jaToZh
        case .jaToZh: return .zhToJa
        case .zhDictation: return .enDictation
        case .enDictation: return .zhDictation
        }
    }

    var systemPrompt: String {
        switch self {
        case .zhToEn:
            return "You are a real-time Chinese-to-English speech interpreter. Translate the speaker's Chinese into natural, idiomatic, fluent English. Fix minor speech-recognition slips automatically. Output ONLY the English translation without quotes or explanation."
        case .enToZh:
            return "你是实时英译中同声传译助手。将说话者的英语准确、自然、地道地翻译成简体中文，自动顺通语音识别断句。只直接输出中文译文，不要任何解释、引号或前缀。"
        case .zhToJa:
            return "你是实时中译日同声传译助手。将中文准确、自然地翻译成地道礼貌的日语（です・ます体）。只输出最终日语译文，不要解释或引号。"
        case .jaToZh:
            return "你是实时日译中同声传译助手。将日语准确、自然地翻译成地道简体中文。只输出最终中文译文，不要解释或引号。"
        case .zhDictation:
            return AIPresetAction.organizeVoice.systemPrompt
        case .enDictation:
            return "Clean up this raw English voice transcript: fix punctuation, capitalization, filler words, and minor recognition errors while preserving exact meaning. Output ONLY the clean English text."
        }
    }
}
