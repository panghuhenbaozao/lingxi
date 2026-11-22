import Foundation

/// AI 服务提供方。
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case gemini
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openAICompatible: return "OpenAI 兼容 (DeepSeek / Qwen / Ollama / 中转)"
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

/// 从远端服务商 API 动态拉取到的模型元数据。
struct AIModelInfo: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var supportsThinking: Bool = false
    var contextLength: Int? = nil
    var provider: AIProvider = .openAICompatible

    init(
        id: String,
        displayName: String? = nil,
        supportsThinking: Bool = false,
        contextLength: Int? = nil,
        provider: AIProvider = .openAICompatible
    ) {
        self.id = id
        self.displayName = (displayName?.isEmpty == false) ? displayName! : id
        self.supportsThinking = supportsThinking
        self.contextLength = contextLength
        self.provider = provider
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

/// 个人背景知识卡片（RAG-Lite：无需每次重复介绍自己或业务背景，按需挂载）。
struct PersonalContextCard: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var content: String
    var sceneTag: String = "通用"
    var isEnabled: Bool = true

    init(id: String = UUID().uuidString, title: String, content: String, sceneTag: String = "通用", isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.content = content
        self.sceneTag = sceneTag
        self.isEnabled = isEnabled
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

/// AI 单次调用消耗与延迟账本记录（纯数值元数据，不含原文）。
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

/// 键盘内嵌 AI 快捷指令。
enum AIPresetAction: String, CaseIterable, Identifiable {
    case polish
    case eqReply
    case strategist
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
        case .eqReply: return "高情商回复"
        case .strategist: return "博弈军师"
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
        case .eqReply: return "sparkles"
        case .strategist: return "brain.head.profile"
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

    var systemPrompt: String {
        let commonRule = "只直接输出最终可直接发送的文本，不要解释过程，不要加多余引号或Markdown标题。"
        switch self {
        case .polish:
            return "你是专业中文文字润色助手。保持原意与语气，修正语病与生硬表达，使语句自然流畅得体。\(commonRule)"
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

/// 仅含提示词、人设与知识卡的无密钥同步载荷（绝不把明文 API Key 放入云端同步快照）。
struct AIPromptsSyncPayload: Codable, Equatable {
    var customPersonaPrompt: String = ""
    var customPrompts: [CustomAIPromptTemplate] = []
    var contextCards: [PersonalContextCard] = []
    var temperature: Double = 0.7
    var thinkingMode: AIThinkingMode = .auto
    var smartContextRecommendEnabled: Bool = true
    var updatedAt: Int = Int(Date().timeIntervalSince1970)
}

/// AI 配置与密钥持久化（存于 App Group 受保护文件中，支持多服务商、拉取模型、思考模式与文风 DNA）。
struct AIConfig: Codable, Equatable {
    static let defaultGeminiBaseURL = "https://generativelanguage.googleapis.com"

    var provider: AIProvider = .gemini
    var geminiAPIKey: String = ""
    var geminiBaseURL: String = AIConfig.defaultGeminiBaseURL
    var geminiModel: String = GeminiModelOption.flash38.rawValue
    var openAIBaseURL: String = "https://api.deepseek.com/v1"
    var openAIAPIKey: String = ""
    var openAIModel: String = "deepseek-chat"

    // 双模型路由与动态拉取的模型列表
    var fastModel: String = ""
    var deepModel: String = ""
    var fetchedModels: [AIModelInfo] = []
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

    // 个人人设、场景、提示词库、文风 DNA 与背景知识卡
    var customPersonaPrompt: String = ""
    var activeScenePersona: AIScenePersona = .auto
    var customPrompts: [CustomAIPromptTemplate] = CustomAIPromptTemplate.defaultTemplates
    var styleDNA: PersonalStyleDNA = PersonalStyleDNA()
    var contextCards: [PersonalContextCard] = []
    var autoAnalyzeOnConnect: Bool = true
    var smartContextRecommendEnabled: Bool = true

    private static let fileName = "lingxi_ai_config.json"
    static let promptsSyncFileName = "lingxi_ai_prompts_sync.json"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .gemini
        geminiAPIKey = try c.decodeIfPresent(String.self, forKey: .geminiAPIKey) ?? ""
        let rawGeminiURL = try c.decodeIfPresent(String.self, forKey: .geminiBaseURL) ?? Self.defaultGeminiBaseURL
        geminiBaseURL = rawGeminiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultGeminiBaseURL : rawGeminiURL
        geminiModel = try c.decodeIfPresent(String.self, forKey: .geminiModel) ?? GeminiModelOption.flash38.rawValue
        openAIBaseURL = try c.decodeIfPresent(String.self, forKey: .openAIBaseURL) ?? "https://api.deepseek.com/v1"
        openAIAPIKey = try c.decodeIfPresent(String.self, forKey: .openAIAPIKey) ?? ""
        openAIModel = try c.decodeIfPresent(String.self, forKey: .openAIModel) ?? "deepseek-chat"
        fastModel = try c.decodeIfPresent(String.self, forKey: .fastModel) ?? ""
        deepModel = try c.decodeIfPresent(String.self, forKey: .deepModel) ?? ""
        fetchedModels = try c.decodeIfPresent([AIModelInfo].self, forKey: .fetchedModels) ?? []
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
    }

    static func load() -> AIConfig {
        var cfg = AppGroup.readJSON(AIConfig.self, from: fileName) ?? AIConfig()
        // 云端 E2EE 拉取的无密钥提示词快照自动增量并集合入，绝不覆盖本地新增条目
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
            if cfg.contextCards.isEmpty && !synced.contextCards.isEmpty {
                cfg.contextCards = synced.contextCards
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
            temperature: temperature,
            thinkingMode: thinkingMode,
            smartContextRecommendEnabled: smartContextRecommendEnabled
        )
        _ = AppGroup.writeJSON(syncPayload, to: Self.promptsSyncFileName, protected: true)
        _ = AppGroup.writeJSON(styleDNA, to: PersonalStyleDNA.fileName, protected: true)
        return AppGroup.writeJSON(self, to: Self.fileName, protected: true)
    }

    var activeAPIKey: String {
        switch provider {
        case .gemini: return geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openAICompatible: return openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var activeModelName: String {
        switch provider {
        case .gemini:
            let m = geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? GeminiModelOption.flash38.rawValue : m
        case .openAICompatible:
            let m = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? "deepseek-chat" : m
        }
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

    /// 兼容本地 Ollama 等无需 API Key 的局域网模型端点
    var isLocalNoKeyEndpoint: Bool {
        guard provider == .openAICompatible else { return false }
        let lower = openAIBaseURL.lowercased()
        return lower.contains("127.0.0.1") || lower.contains("localhost") || lower.contains("192.168.") || lower.contains("10.")
    }

    var isConfigured: Bool {
        !activeAPIKey.isEmpty || isLocalNoKeyEndpoint
    }

    /// 将当前活跃配置保存/更新为一个命名渠道档案
    mutating func saveCurrentAsProfile(name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = cleanName.isEmpty ? activeModelName : cleanName
        let currentURL = provider == .gemini ? geminiBaseURL : openAIBaseURL
        if let aid = activeProfileID, let idx = profiles.firstIndex(where: { $0.id == aid }) {
            profiles[idx].name = label
            profiles[idx].provider = provider
            profiles[idx].baseURL = currentURL
            profiles[idx].apiKey = activeAPIKey
            profiles[idx].model = activeModelName
            profiles[idx].fastModel = fastModel
            profiles[idx].deepModel = deepModel
            profiles[idx].thinkingMode = thinkingMode
            profiles[idx].thinkingBudget = thinkingBudget
            profiles[idx].fetchedModels = fetchedModels
        } else {
            let profile = AIProviderProfile(
                name: label,
                provider: provider,
                baseURL: currentURL,
                apiKey: activeAPIKey,
                model: activeModelName,
                fastModel: fastModel,
                deepModel: deepModel,
                thinkingMode: thinkingMode,
                thinkingBudget: thinkingBudget,
                fetchedModels: fetchedModels
            )
            profiles.insert(profile, at: 0)
            activeProfileID = profile.id
        }
    }

    /// 一键切换到已保存的某个服务商档案
    mutating func activateProfile(_ profile: AIProviderProfile) {
        activeProfileID = profile.id
        provider = profile.provider
        if profile.provider == .gemini {
            geminiBaseURL = profile.baseURL.isEmpty ? Self.defaultGeminiBaseURL : profile.baseURL
            geminiAPIKey = profile.apiKey
            geminiModel = profile.model
        } else {
            openAIBaseURL = profile.baseURL
            openAIAPIKey = profile.apiKey
            openAIModel = profile.model
        }
        fastModel = profile.fastModel
        deepModel = profile.deepModel
        thinkingMode = profile.thinkingMode
        thinkingBudget = profile.thinkingBudget
        fetchedModels = profile.fetchedModels
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
