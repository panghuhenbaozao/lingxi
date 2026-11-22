import Foundation

/// AI 自动诊断推荐的快捷短语条目（支持一键导入 QuickPhraseStore）。
struct AISuggestedPhrase: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var content: String
    var category: String = "AI推荐"

    init(id: String = UUID().uuidString, title: String, content: String, category: String = "AI推荐") {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "常用短语"
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "AI推荐"
    }
}

/// AI 自动分析生成的个人打字风格诊断、专属人设与定制提示词方案。
struct AIAutoInsightReport: Codable, Equatable {
    var generatedAt: Date = Date()
    var sourceLabel: String = "端侧智能诊断"
    var isFromLLM: Bool = false
    var personaTitle: String = "高效全能表达者"
    var styleSummary: String = ""
    var efficiencyDiagnosis: String = ""
    var recommendedPersonaPrompt: String = ""
    var suggestedPrompts: [CustomAIPromptTemplate] = []
    var suggestedPhrases: [AISuggestedPhrase] = []
    var suggestedFuzzyKeys: [String] = []
    var actionableTips: [String] = []

    init(
        generatedAt: Date = Date(),
        sourceLabel: String = "端侧智能诊断",
        isFromLLM: Bool = false,
        personaTitle: String = "高效全能表达者",
        styleSummary: String = "",
        efficiencyDiagnosis: String = "",
        recommendedPersonaPrompt: String = "",
        suggestedPrompts: [CustomAIPromptTemplate] = [],
        suggestedPhrases: [AISuggestedPhrase] = [],
        suggestedFuzzyKeys: [String] = [],
        actionableTips: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.sourceLabel = sourceLabel
        self.isFromLLM = isFromLLM
        self.personaTitle = personaTitle
        self.styleSummary = styleSummary
        self.efficiencyDiagnosis = efficiencyDiagnosis
        self.recommendedPersonaPrompt = recommendedPersonaPrompt
        self.suggestedPrompts = suggestedPrompts
        self.suggestedPhrases = suggestedPhrases
        self.suggestedFuzzyKeys = suggestedFuzzyKeys
        self.actionableTips = actionableTips
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        sourceLabel = try c.decodeIfPresent(String.self, forKey: .sourceLabel) ?? "端侧智能诊断"
        isFromLLM = try c.decodeIfPresent(Bool.self, forKey: .isFromLLM) ?? false
        personaTitle = try c.decodeIfPresent(String.self, forKey: .personaTitle) ?? "高效全能表达者"
        styleSummary = try c.decodeIfPresent(String.self, forKey: .styleSummary) ?? ""
        efficiencyDiagnosis = try c.decodeIfPresent(String.self, forKey: .efficiencyDiagnosis) ?? ""
        recommendedPersonaPrompt = try c.decodeIfPresent(String.self, forKey: .recommendedPersonaPrompt) ?? ""
        suggestedPrompts = try c.decodeIfPresent([CustomAIPromptTemplate].self, forKey: .suggestedPrompts) ?? []
        suggestedPhrases = try c.decodeIfPresent([AISuggestedPhrase].self, forKey: .suggestedPhrases) ?? []
        suggestedFuzzyKeys = try c.decodeIfPresent([String].self, forKey: .suggestedFuzzyKeys) ?? []
        actionableTips = try c.decodeIfPresent([String].self, forKey: .actionableTips) ?? []
    }
}

/// 接入 AI 后的自动分析与个性化提示词生成引擎（App 与键盘扩展共享，严格脱敏，不含任何原始聊天内容）。
enum AIAutoInsightService {
    private static let reportFileName = "lingxi_ai_insight_report.json"

    static func loadCachedReport() -> AIAutoInsightReport? {
        AppGroup.readJSON(AIAutoInsightReport.self, from: reportFileName)
    }

    @discardableResult
    static func saveReport(_ report: AIAutoInsightReport) -> Bool {
        AppGroup.writeJSON(report, to: reportFileName, protected: true)
    }

    static func clearReport() {
        try? FileManager.default.removeItem(at: AppGroup.fileURL(reportFileName))
    }

    /// 将脱敏数值画像与配置汇总成发给 AI 的结构化分析上下文（绝不包含具体聊天原文）。
    static func buildPrivacySafeAnalysisContext(
        profile: UserTypingHabitProfile,
        stats: TypingStatsStore.Summary,
        settings: LingxiSettings
    ) -> String {
        let peakHour = profile.hourlyRhythm.max(by: { $0.value < $1.value })?.key ?? "未形成明显高峰"
        let topConfusions = profile.confusionMatrix
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(4)
            .map { "\(fuzzyDisplayName(for: $0.key))(\($0.value)次)" }
            .joined(separator: "、")
        let topAIFeatures = profile.aiFeatureBreakdown
            .sorted { $0.value.calls > $1.value.calls }
            .prefix(4)
            .map { "\($0.key)(\($0.value.calls)次)" }
            .joined(separator: "、")
        let tags = profile.habitTags.isEmpty ? "新上手用户" : profile.habitTags.joined(separator: "、")

        return """
        【用户脱敏打字画像（无任何输入原文）】
        - 输入方案与布局：\(settings.inputScheme.displayName) / \(settings.layoutMode.displayName)
        - 已记录会话数：\(profile.totalSessions) 次，总字数：\(max(profile.totalChars, stats.totalChars)) 字，连续活跃：\(stats.streakDays) 天
        - 平均速度：\(String(format: "%.1f", profile.avgCPM)) 字/分（峰值 \(String(format: "%.1f", profile.peakCPM)) 字/分）
        - 平均词长：\(String(format: "%.2f", profile.avgWordLength)) 字/词
        - 退格率：\(String(format: "%.1f%%", profile.backspaceRate * 100))，纠错触发率：\(String(format: "%.1f%%", profile.typoCorrectionRate * 100))，滑行占比：\(String(format: "%.1f%%", profile.glideRatio * 100))
        - 词库领域偏好：\(profile.domainAffinity.primaryDomain)（语气倾向：\(profile.domainAffinity.preferredTone)）
        - 活跃高峰时段：\(peakHour) 点
        - 行为特征标签：\(tags)
        - 声韵母高频混淆：\(topConfusions.isEmpty ? "暂无明显混淆" : topConfusions)
        - 历史常用 AI 技能：\(topAIFeatures.isEmpty ? "刚接入 AI" : topAIFeatures)
        - 当前已开启模糊音组数：\(settings.fuzzy.enabledCount) 组，翻译默认目标语种：\(settings.translateTargetLang)
        """
    }

    /// 当用户已配置 AI Key 时，自动调用模型进行深度结构化分析；网络异常或解析失败时无缝回落到端侧智能诊断。
    static func runAutoAnalysis(
        config: AIConfig = AIConfig.load(),
        profile: UserTypingHabitProfile = TypingHabitTracker.shared.currentProfile(),
        stats: TypingStatsStore.Summary = TypingStatsStore.shared.summary(),
        settings: LingxiSettings = LingxiSettings.load(),
        client: AIClient = AIClient(timeout: 45)
    ) async -> AIAutoInsightReport {
        let fallback = generateLocalReport(profile: profile, stats: stats, settings: settings)
        guard config.isConfigured else {
            saveReport(fallback)
            return fallback
        }

        let contextText = buildPrivacySafeAnalysisContext(profile: profile, stats: stats, settings: settings)
        let systemPrompt = """
        你是「灵犀输入法」的 AI 个人效率顾问与提示词架构师。
        根据用户提供的脱敏打字统计画像，输出一个严格合法的 JSON 对象（不要任何多余说明或 Markdown 以外的文字），结构如下：
        {
          "personaTitle": "4-8字个性化称号，如：极速科技实干派",
          "styleSummary": "60-100字中文，精准总结用户的输入节奏、表达习惯与领域特征",
          "efficiencyDiagnosis": "60-100字中文，分析速度、退格率、纠错/模糊音痛点及提升方向",
          "recommendedPersonaPrompt": "40-90字中文系统人设提示词，可直接作为灵犀 AI 的个人语气偏好",
          "suggestedPrompts": [
            {
              "title": "4字以内键盘按钮名",
              "icon": "SF Symbol名如 sparkles/briefcase.fill/bolt.fill/doc.text/bubble.left.and.text.bubble.right/globe",
              "category": "效率沟通 或 职场商务 或 日常社交 或 学习创作",
              "instruction": "30-70字清晰具体的指令提示词"
            }
          ],
          "suggestedPhrases": [
            {
              "title": "4-6字短语标题",
              "content": "一条高频实用、可直接发送的中文短语",
              "category": "AI推荐"
            }
          ],
          "actionableTips": ["3-4条具体可落地的输入法调优与效率建议，每条25-45字"]
        }
        要求：
        1. suggestedPrompts 提供 4 条高度实用、与用户领域匹配的提示词。
        2. suggestedPhrases 提供 3 条日常/工作高频短语。
        3. 全部使用简体中文，语言真诚专业、避免空泛套话。
        """

        do {
            var collected = ""
            for try await delta in client.streamText(
                prompt: contextText,
                systemInstruction: systemPrompt,
                config: config,
                featureTag: "ai_auto_analysis"
            ) {
                collected += delta
            }
            let modelTag = config.provider == .gemini ? config.geminiModel : config.openAIModel
            let parsed = parseLLMResponse(
                collected,
                fallback: fallback,
                sourceLabel: "AI 深度分析 · \(modelTag.isEmpty ? config.provider.rawValue : modelTag)"
            )
            saveReport(parsed)
            return parsed
        } catch {
            saveReport(fallback)
            return fallback
        }
    }

    /// 端侧即时智能诊断（零网络即可给出精准的风格分析、人设提示词、领域定制提示词与模糊音建议）。
    static func generateLocalReport(
        profile: UserTypingHabitProfile,
        stats: TypingStatsStore.Summary,
        settings: LingxiSettings
    ) -> AIAutoInsightReport {
        let domain = profile.domainAffinity.primaryDomain
        let cpm = max(profile.avgCPM, stats.averageCharsPerMinute)
        let totalChars = max(profile.totalChars, stats.totalChars)
        let suggestedFuzzy = recommendedFuzzyKeys(from: profile.confusionMatrix, current: settings.fuzzy)

        let personaTitle: String
        let recommendedPersona: String
        let domainPrompts: [CustomAIPromptTemplate]
        let domainPhrases: [AISuggestedPhrase]

        if domain.contains("科技") || domain.contains("开发") {
            personaTitle = cpm >= 55 ? "极速科技实干派" : "清晰逻辑技术派"
            recommendedPersona = "保持逻辑清晰、结论先行的科技从业者口吻，技术术语保留英文原词，少用冗长客套，句式精炼干脆。"
            domainPrompts = [
                CustomAIPromptTemplate(
                    id: "ai_tech_review",
                    title: "技术同步",
                    icon: "chevron.left.forwardslash.chevron.right",
                    instruction: "把这段内容改写成简洁专业的研发进度/问题同步消息，明确现状、原因和下一步动作。",
                    category: "职场商务",
                    isAIGenerated: true,
                    isPinned: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_tech_bug",
                    title: "问题复盘",
                    icon: "ant.fill",
                    instruction: "把内容整理为结构化排查记录：现象、根因分析、修复方案与验证结论，条理清晰。",
                    category: "效率沟通",
                    isAIGenerated: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_tech_doc",
                    title: "中英精译",
                    icon: "globe",
                    instruction: "在保留专业技术术语的前提下进行地道中英互译，适合技术文档、Issue 或 PR 沟通。",
                    category: "学习创作",
                    isAIGenerated: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_tech_eq",
                    title: "温和催促",
                    icon: "sparkles",
                    instruction: "用友好合作、不显急躁的语气跟进对方进度，并顺带给出清晰的期望截止时间。",
                    category: "效率沟通",
                    isAIGenerated: true
                ),
            ]
            domainPhrases = [
                AISuggestedPhrase(title: "收到排查", content: "收到，我马上复现定位一下，有进展第一时间同步你。", category: "AI推荐"),
                AISuggestedPhrase(title: "方案确认", content: "这个方案我这边 OK，按这个排期推进就行，辛苦啦！", category: "AI推荐"),
                AISuggestedPhrase(title: "已发版验证", content: "刚已经合入并完成验证，方便的时候可以再回归确认一下。", category: "AI推荐"),
            ]
        } else if domain.contains("商务") || domain.contains("职场") {
            personaTitle = "高效商务沟通官"
            recommendedPersona = "表达礼貌得体、重点突出、有分寸感，既体现专业度又保持亲和力，适合客户沟通与团队协作。"
            domainPrompts = [
                CustomAIPromptTemplate(
                    id: "ai_biz_minutes",
                    title: "会议纪要",
                    icon: "doc.text.fill",
                    instruction: "将这段口语或零散记录提炼为标准会议纪要：核心结论、待办事项、责任人与节点。",
                    category: "职场商务",
                    isAIGenerated: true,
                    isPinned: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_biz_client",
                    title: "客户回复",
                    icon: "person.2.fill",
                    instruction: "用专业、真诚且让人放心的商务口吻回复客户，回应关切并明确下一步安排。",
                    category: "职场商务",
                    isAIGenerated: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_biz_email",
                    title: "邮件润色",
                    icon: "envelope.fill",
                    instruction: "把这段草稿润色成结构完整、措辞得体的正式商务消息或邮件正文。",
                    category: "职场商务",
                    isAIGenerated: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_biz_decline",
                    title: "体面婉拒",
                    icon: "hand.raised.fill",
                    instruction: "高情商委婉拒绝不合理需求或时间冲突，给出替代建议，保持良好合作关系。",
                    category: "效率沟通",
                    isAIGenerated: true
                ),
            ]
            domainPhrases = [
                AISuggestedPhrase(title: "辛苦对接", content: "辛苦跟进，细节我这边确认无误，麻烦按计划推进～", category: "AI推荐"),
                AISuggestedPhrase(title: "稍后回电", content: "我现在正在开会，大约半小时后结束，结束第一时间联系您。", category: "AI推荐"),
                AISuggestedPhrase(title: "资料已发", content: "相关材料刚刚已经整理发您了，有任何需要调整的地方随时告诉我。", category: "AI推荐"),
            ]
        } else if domain.contains("学术") || domain.contains("学习") {
            personaTitle = "深度思考学习者"
            recommendedPersona = "表达严谨准确、逻辑连贯、用词精炼，兼顾可读性与学术规范，避免口语化赘述。"
            domainPrompts = [
                CustomAIPromptTemplate(
                    id: "ai_edu_polish",
                    title: "学术润色",
                    icon: "book.fill",
                    instruction: "将这段内容润色为严谨流畅、逻辑严密的书面/学术表达，消除口语词。",
                    category: "学习创作",
                    isAIGenerated: true,
                    isPinned: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_edu_outline",
                    title: "提炼要点",
                    icon: "list.bullet.rectangle",
                    instruction: "把这段文字拆解为 3-5 个清晰核心观点，方便记忆与复盘。",
                    category: "学习创作",
                    isAIGenerated: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_edu_en",
                    title: "英文润色",
                    icon: "globe",
                    instruction: "将内容译为地道自然的英文学术或正式表达，修正语法与搭配。",
                    category: "学习创作",
                    isAIGenerated: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_edu_explain",
                    title: "通俗改写",
                    icon: "lightbulb.fill",
                    instruction: "把专业复杂的概念改写成通俗易懂、一读就明白的大白话。",
                    category: "效率沟通",
                    isAIGenerated: true
                ),
            ]
            domainPhrases = [
                AISuggestedPhrase(title: "请教问题", content: "打扰啦，想向您请教一个小问题，方便的时候麻烦指点一下～", category: "AI推荐"),
                AISuggestedPhrase(title: "感谢分享", content: "非常感谢分享，这份整理很有启发，我先收藏仔细看看！", category: "AI推荐"),
                AISuggestedPhrase(title: "已核对完毕", content: "这部分内容我已经逐条核对完毕，没有问题了。", category: "AI推荐"),
            ]
        } else {
            personaTitle = cpm >= 50 ? "灵动高频表达者" : "自然流畅沟通派"
            recommendedPersona = "口吻自然真诚、温暖有礼、贴近日常聊天节奏，表达清楚不绕弯，适度保留亲切感。"
            domainPrompts = [
                CustomAIPromptTemplate(
                    id: "ai_daily_reply",
                    title: "高情商答",
                    icon: "sparkles",
                    instruction: "把这段消息回复得自然真诚、高情商且有温度，像关系很好的朋友或得体同事在说话。",
                    category: "日常社交",
                    isAIGenerated: true,
                    isPinned: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_daily_polish",
                    title: "顺句去冗",
                    icon: "wand.and.stars",
                    instruction: "保留原意，把话说得更顺口利落、去掉重复口水词，直接可发送。",
                    category: "效率沟通",
                    isAIGenerated: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_daily_social",
                    title: "朋友圈风",
                    icon: "camera.filters",
                    instruction: "把这段记录改写成轻松有质感、不油腻的朋友圈或小红书分享文案。",
                    category: "日常社交",
                    isAIGenerated: true
                ),
                CustomAIPromptTemplate(
                    id: "ai_daily_short",
                    title: "一句话说清",
                    icon: "bolt.fill",
                    instruction: "把这段较长的内容浓缩为一两句重点明确、礼貌好懂的短消息。",
                    category: "效率沟通",
                    isAIGenerated: true
                ),
            ]
            domainPhrases = [
                AISuggestedPhrase(title: "马上到", content: "已经在路上了，大概十分钟左右到，稍微等我一下～", category: "AI推荐"),
                AISuggestedPhrase(title: "收到谢谢", content: "收到啦，非常感谢！辛苦你专门发过来～", category: "AI推荐"),
                AISuggestedPhrase(title: "稍后回复", content: "刚看到消息，手头正忙着一件事，忙完马上仔细回你！", category: "AI推荐"),
            ]
        }

        let styleSummary: String
        if totalChars < 30 {
            styleSummary = "您刚开启灵犀 AI 诊断，当前以「\(settings.inputScheme.displayName) · \(settings.layoutMode.displayName)」为主，领域倾向偏向「\(domain)」。日常继续使用后，灵犀会自动结合您的句长节奏与词频特征持续进化专属提示词。"
        } else {
            let wordLenDesc = profile.avgWordLength >= 2.8 ? "偏爱整句连打" : "以短词精准点选为主"
            styleSummary = "累计记录 \(totalChars) 字，平均速度 \(String(format: "%.0f", cpm)) 字/分，\(wordLenDesc)，核心表达偏向「\(domain)」风格（语气：\(profile.domainAffinity.preferredTone)）。"
        }

        var diagParts: [String] = []
        if profile.backspaceRate >= 0.16 {
            diagParts.append("退格率偏高（\(String(format: "%.1f%%", profile.backspaceRate * 100))），建议保持智能纠错与长句单字保护开启，减少返工。")
        } else {
            diagParts.append("输入准确率整体表现良好，节奏稳定。")
        }
        if !suggestedFuzzy.isEmpty {
            let names = suggestedFuzzy.map(fuzzyDisplayName(for:)).joined(separator: "、")
            diagParts.append("检测到高频声韵母混淆：\(names)，可一键开启对应模糊音提速。")
        } else if settings.inputScheme == .quanpin && cpm >= 45 {
            diagParts.append("当前全拼速度较快，可尝试「小鹤双拼」或「滑行输入」进一步降低击键次数。")
        } else {
            diagParts.append("打开键盘「✨ 灵犀 AI」时已支持自动识别语境并置顶推荐最匹配提示词。")
        }

        var tips: [String] = [
            "点击下方「一键应用人设」后，键盘内所有润色、回复和翻译都会自动贴合您的个人语气。",
            "将 AI 定制提示词加入键盘栏后，聊天时点一下「✨ 灵犀 AI」即可一键调用，无需重复打指令。",
        ]
        if !suggestedFuzzy.isEmpty {
            tips.append("点击「一键开启推荐模糊音」，可立刻消除 \(suggestedFuzzy.map(fuzzyDisplayName(for:)).joined(separator: "/")) 误拼卡顿。")
        } else {
            tips.append("长拼音输入时既支持整句首位上屏，也已保留高频单字与展开「只看单字」，纠错更顺手。")
        }
        if !settings.typingStatsEnabled {
            tips.append("在「效率与统计」中开启本机打字统计，可让后续 AI 诊断更精准感知您的速度与高峰时段。")
        }

        return AIAutoInsightReport(
            generatedAt: Date(),
            sourceLabel: "端侧智能诊断",
            isFromLLM: false,
            personaTitle: personaTitle,
            styleSummary: styleSummary,
            efficiencyDiagnosis: diagParts.joined(separator: " "),
            recommendedPersonaPrompt: recommendedPersona,
            suggestedPrompts: domainPrompts,
            suggestedPhrases: domainPhrases,
            suggestedFuzzyKeys: suggestedFuzzy,
            actionableTips: tips
        )
    }

    /// 宽松且健壮地解析大模型返回的 JSON 诊断报告（容忍 Markdown 代码块与部分缺失字段）。
    static func parseLLMResponse(
        _ raw: String,
        fallback: AIAutoInsightReport,
        sourceLabel: String
    ) -> AIAutoInsightReport {
        let cleaned = extractJSONObjectString(from: raw)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // 若模型未严格按 JSON 返回，但给出了有意义的中文分析文本，则将其保留到风格摘要中
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            var merged = fallback
            merged.generatedAt = Date()
            merged.sourceLabel = sourceLabel
            merged.isFromLLM = !trimmed.isEmpty
            if trimmed.count >= 20 {
                merged.styleSummary = String(trimmed.prefix(240))
            }
            return merged
        }

        func nonEmptyString(_ key: String, default fallbackVal: String) -> String {
            if let s = obj[key] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
            return fallbackVal
        }

        var parsedPrompts: [CustomAIPromptTemplate] = []
        if let arr = obj["suggestedPrompts"] as? [[String: Any]] {
            for (idx, item) in arr.prefix(6).enumerated() {
                let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let instruction = (item["instruction"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !title.isEmpty, !instruction.isEmpty else { continue }
                let icon = (item["icon"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "sparkles"
                let category = (item["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "AI 自动定制"
                parsedPrompts.append(
                    CustomAIPromptTemplate(
                        id: "ai_gen_\(idx)_\(abs(title.hashValue % 10000))",
                        title: String(title.prefix(8)),
                        icon: icon.isEmpty ? "sparkles" : icon,
                        instruction: instruction,
                        category: category.isEmpty ? "AI 自动定制" : category,
                        isAIGenerated: true,
                        isPinned: idx == 0
                    )
                )
            }
        }

        var parsedPhrases: [AISuggestedPhrase] = []
        if let arr = obj["suggestedPhrases"] as? [[String: Any]] {
            for item in arr.prefix(5) {
                let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let content = (item["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !content.isEmpty else { continue }
                let category = (item["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "AI推荐"
                parsedPhrases.append(
                    AISuggestedPhrase(
                        title: title.isEmpty ? String(content.prefix(6)) : String(title.prefix(10)),
                        content: content,
                        category: category.isEmpty ? "AI推荐" : category
                    )
                )
            }
        }

        var parsedTips: [String] = []
        if let arr = obj["actionableTips"] as? [String] {
            parsedTips = arr
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return AIAutoInsightReport(
            generatedAt: Date(),
            sourceLabel: sourceLabel,
            isFromLLM: true,
            personaTitle: nonEmptyString("personaTitle", default: fallback.personaTitle),
            styleSummary: nonEmptyString("styleSummary", default: fallback.styleSummary),
            efficiencyDiagnosis: nonEmptyString("efficiencyDiagnosis", default: fallback.efficiencyDiagnosis),
            recommendedPersonaPrompt: nonEmptyString("recommendedPersonaPrompt", default: fallback.recommendedPersonaPrompt),
            suggestedPrompts: parsedPrompts.isEmpty ? fallback.suggestedPrompts : parsedPrompts,
            suggestedPhrases: parsedPhrases.isEmpty ? fallback.suggestedPhrases : parsedPhrases,
            suggestedFuzzyKeys: fallback.suggestedFuzzyKeys,
            actionableTips: parsedTips.isEmpty ? fallback.actionableTips : parsedTips
        )
    }

    private static func extractJSONObjectString(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fenceRange = text.range(of: "```json"), let endFence = text.range(of: "```", range: fenceRange.upperBound..<text.endIndex) {
            text = String(text[fenceRange.upperBound..<endFence.lowerBound])
        } else if let fenceRange = text.range(of: "```"), let endFence = text.range(of: "```", range: fenceRange.upperBound..<text.endIndex) {
            text = String(text[fenceRange.upperBound..<endFence.lowerBound])
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") , start <= end {
            return String(text[start...end])
        }
        return text
    }

    /// 从 9 组声韵母混淆矩阵中筛出值得开启但尚未开启的模糊音 key。
    static func recommendedFuzzyKeys(from matrix: [String: Int], current: FuzzyPinyinOptions) -> [String] {
        let sorted = matrix.filter { $0.value >= 2 }.sorted { $0.value > $1.value }.map(\.key)
        return sorted.filter { key in
            switch key {
            case "zh_z": return !current.zhZ
            case "ch_c": return !current.chC
            case "sh_s": return !current.shS
            case "n_l": return !current.nl
            case "r_l": return !current.rl
            case "f_h": return !current.fh
            case "an_ang": return !current.anAng
            case "en_eng": return !current.enEng
            case "in_ing": return !current.inIng
            default: return false
            }
        }
    }

    @discardableResult
    static func applyFuzzyKeys(_ keys: [String], to settings: inout LingxiSettings) -> Int {
        var changed = 0
        for key in keys {
            switch key {
            case "zh_z": if !settings.fuzzy.zhZ { settings.fuzzy.zhZ = true; changed += 1 }
            case "ch_c": if !settings.fuzzy.chC { settings.fuzzy.chC = true; changed += 1 }
            case "sh_s": if !settings.fuzzy.shS { settings.fuzzy.shS = true; changed += 1 }
            case "n_l": if !settings.fuzzy.nl { settings.fuzzy.nl = true; changed += 1 }
            case "r_l": if !settings.fuzzy.rl { settings.fuzzy.rl = true; changed += 1 }
            case "f_h": if !settings.fuzzy.fh { settings.fuzzy.fh = true; changed += 1 }
            case "an_ang": if !settings.fuzzy.anAng { settings.fuzzy.anAng = true; changed += 1 }
            case "en_eng": if !settings.fuzzy.enEng { settings.fuzzy.enEng = true; changed += 1 }
            case "in_ing": if !settings.fuzzy.inIng { settings.fuzzy.inIng = true; changed += 1 }
            default: break
            }
        }
        return changed
    }

    static func fuzzyDisplayName(for key: String) -> String {
        switch key {
        case "zh_z": return "zh/z 平翘舌"
        case "ch_c": return "ch/c 平翘舌"
        case "sh_s": return "sh/s 平翘舌"
        case "n_l": return "n/l 鼻边音"
        case "r_l": return "r/l 混淆"
        case "f_h": return "f/h 唇齿音"
        case "an_ang": return "an/ang 前后鼻音"
        case "en_eng": return "en/eng 前后鼻音"
        case "in_ing": return "in/ing 前后鼻音"
        default: return key
        }
    }
}

// MARK: - 键盘内零延迟智能语境感知与提示词自动推荐器

struct SmartContextRecommendation: Equatable {
    let badgeTitle: String
    let recommendedPresets: [AIPresetAction]
    let recommendedCustomIDs: [String]
}

enum SmartContextPromptDetector {
    /// 零网络、亚毫秒级语境识别：打开键盘「✨ 灵犀 AI」时自动判断当前上下文并置顶最匹配的提示词技能。
    static func analyze(
        text: String,
        isClipboard: Bool,
        customPrompts: [CustomAIPromptTemplate]
    ) -> SmartContextRecommendation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let pinned = customPrompts.filter(\.isPinned).map(\.id)
            return SmartContextRecommendation(
                badgeTitle: "✨ 智能技能已就绪",
                recommendedPresets: [.polish, .eqReply, .translateEn],
                recommendedCustomIDs: pinned
            )
        }

        let asciiLetters = trimmed.unicodeScalars.filter { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }.count
        let nonSpaceCount = max(1, trimmed.unicodeScalars.filter { !$0.properties.isWhitespace }.count)
        let asciiRatio = Double(asciiLetters) / Double(nonSpaceCount)

        // 1. 英文/外文文本优先推荐中英翻译与润色
        if asciiRatio >= 0.55 && asciiLetters >= 6 {
            let matchingCustom = customPrompts.filter {
                $0.title.contains("译") || $0.title.contains("英") || $0.instruction.contains("英文")
            }.map(\.id)
            return SmartContextRecommendation(
                badgeTitle: "🌐 检测到英文 · 推荐地道翻译",
                recommendedPresets: [.translateZh, .polish, .summarize],
                recommendedCustomIDs: matchingCustom
            )
        }

        // 2. 职场/商务关键词优先推荐汇报、会议纪要、商务回复
        let bizKeywords = ["汇报", "进度", "方案", "会议", "排期", "需求", "上线", "合同", "客户", "麻烦", "辛苦", "评审", "复盘", "项目"]
        if bizKeywords.contains(where: { trimmed.contains($0) }) {
            let bizCustom = customPrompts.filter {
                $0.category.contains("职场") || $0.category.contains("商务") || $0.title.contains("汇报") || $0.title.contains("会议") || $0.title.contains("同步")
            }.map(\.id)
            return SmartContextRecommendation(
                badgeTitle: "💼 检测到职场语境 · 推荐商务提示词",
                recommendedPresets: isClipboard ? [.replyClipboard, .eqReply, .polish] : [.polish, .summarize, .eqReply],
                recommendedCustomIDs: bizCustom
            )
        }

        // 3. 剪贴板消息或明显提问语境优先推荐高情商回复
        let questionHints = ["?", "？", "吗", "呢", "在吗", "方便", "请问", "什么时候", "怎么", "能不能", "可以吗"]
        if isClipboard || questionHints.contains(where: { trimmed.contains($0) }) {
            let replyCustom = customPrompts.filter {
                $0.title.contains("回复") || $0.title.contains("拒绝") || $0.title.contains("答") || $0.isPinned
            }.map(\.id)
            return SmartContextRecommendation(
                badgeTitle: "💬 检测到对话/提问 · 推荐高情商回复",
                recommendedPresets: isClipboard ? [.replyClipboard, .eqReply, .funny] : [.eqReply, .polish, .funny],
                recommendedCustomIDs: replyCustom
            )
        }

        // 4. 较长段落或口语草稿优先推荐智能整理与精简提炼
        if trimmed.count >= 42 || trimmed.contains("\n") {
            let organizeCustom = customPrompts.filter {
                $0.title.contains("待办") || $0.title.contains("要点") || $0.title.contains("纪要") || $0.title.contains("精简")
            }.map(\.id)
            return SmartContextRecommendation(
                badgeTitle: "📝 检测到长文本 · 推荐整理与提炼",
                recommendedPresets: [.organizeVoice, .summarize, .polish],
                recommendedCustomIDs: organizeCustom
            )
        }

        // 5. 默认通用润色与多风格表达
        let pinned = customPrompts.filter(\.isPinned).map(\.id)
        return SmartContextRecommendation(
            badgeTitle: "✨ 已为你匹配常用润色技能",
            recommendedPresets: [.polish, .eqReply, .translateEn],
            recommendedCustomIDs: pinned
        )
    }
}
