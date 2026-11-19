import Foundation

/// AI 服务提供方。
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case gemini
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini (Interactions API)"
        case .openAICompatible: return "OpenAI 兼容接口 (DeepSeek / Qwen / 代理)"
        }
    }
}

/// 推荐的 Gemini 模型选项。
enum GeminiModelOption: String, CaseIterable, Identifiable {
    case flash38 = "gemini-3.8-flash"
    case flashLite35 = "gemini-3.5-flash-lite"
    case argon4 = "gemini-4-argon"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flash38: return "Gemini 3.8 Flash（默认 · 高效均衡）"
        case .flashLite35: return "Gemini 3.5 Flash-Lite（极速 · 低成本）"
        case .argon4: return "Gemini 4 Argon（旗舰推理与写作）"
        }
    }

    var defaultThinkingLevel: String {
        switch self {
        case .flashLite35: return "minimal"
        case .flash38, .argon4: return "low"
        }
    }
}

/// 键盘内嵌 AI 快捷指令。
enum AIPresetAction: String, CaseIterable, Identifiable {
    case polish
    case eqReply
    case organizeVoice
    case translateEn
    case translateZh
    case replyClipboard
    case summarize
    case xiaohongshu
    case classical
    case funny

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polish: return "润色优化"
        case .eqReply: return "高情商回复"
        case .organizeVoice: return "智能整理"
        case .translateEn: return "译为英文"
        case .translateZh: return "译为中文"
        case .replyClipboard: return "回复剪贴板"
        case .summarize: return "精简提炼"
        case .xiaohongshu: return "小红书风"
        case .classical: return "文言文风"
        case .funny: return "幽默玩梗"
        }
    }

    var icon: String {
        switch self {
        case .polish: return "wand.and.stars"
        case .eqReply: return "sparkles"
        case .organizeVoice: return "text.alignleft"
        case .translateEn: return "globe"
        case .translateZh: return "character.book.closed"
        case .replyClipboard: return "doc.on.clipboard.fill"
        case .summarize: return "scissors"
        case .xiaohongshu: return "flame"
        case .classical: return "scroll"
        case .funny: return "face.smiling"
        }
    }

    var needsClipboardFallback: Bool {
        self == .replyClipboard
    }

    var systemPrompt: String {
        let commonRule = "只直接输出最终可直接发送的文本，不要解释过程，不要加多余引号或Markdown标题。"
        switch self {
        case .polish:
            return "你是专业中文文字润色助手。保持原意与语气，修正语病与生硬表达，使语句自然流畅得体。\(commonRule)"
        case .eqReply:
            return "你是高情商沟通专家。把用户的输入或对方消息改写/回复得体、有分寸、温暖且不卑不亢。\(commonRule)"
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
        case .xiaohongshu:
            return "请把内容改写成生动吸睛的小红书风格文案，适当加入自然Emoji，分段舒适有感染力。\(commonRule)"
        case .classical:
            return "请将内容改写为凝练典雅、有古风韵味的文言文或半文白短句，读来朗朗上口。\(commonRule)"
        case .funny:
            return "请用机智幽默、接地气、略带网感但友好的方式重新表达或回复这段话。\(commonRule)"
        }
    }
}

/// AI 配置与密钥持久化（存于 App Group 受保护文件中，兼容侧载签名）。
struct AIConfig: Codable, Equatable {
    var provider: AIProvider = .gemini
    var geminiAPIKey: String = ""
    var geminiModel: String = GeminiModelOption.flash38.rawValue
    var openAIBaseURL: String = "https://api.deepseek.com/v1"
    var openAIAPIKey: String = ""
    var openAIModel: String = "deepseek-chat"
    var customPersonaPrompt: String = ""
    var temperature: Double = 0.7

    private static let fileName = "lingxi_ai_config.json"

    static func load() -> AIConfig {
        AppGroup.readJSON(AIConfig.self, from: fileName) ?? AIConfig()
    }

    @discardableResult
    func save() -> Bool {
        AppGroup.writeJSON(self, to: Self.fileName, protected: true)
    }

    var activeAPIKey: String {
        switch provider {
        case .gemini: return geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openAICompatible: return openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var isConfigured: Bool { !activeAPIKey.isEmpty }
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
