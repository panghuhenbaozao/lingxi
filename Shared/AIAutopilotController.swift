import Foundation

/// 灵犀 AI 对打字功能与学习数据的托管级别
enum AIAutopilotMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off = "off"
    case suggest = "suggest"
    case fullAutopilot = "full_autopilot"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .off: return "手动控制"
        case .suggest: return "AI 建议（需我确认）"
        case .fullAutopilot: return "AI 全权自动托管"
        }
    }

    var shortBadge: String {
        switch self {
        case .off: return "手动"
        case .suggest: return "建议中"
        case .fullAutopilot: return "全权托管"
        }
    }

    var subtitle: String {
        switch self {
        case .off: return "AI 不自动调整打字设置，仅记录基础统计"
        case .suggest: return "AI 持续分析本地 SQLite 习惯库并给出调优建议，由你一键采纳"
        case .fullAutopilot: return "AI 根据你的打字习惯与学习数据库自动开启最顺手的打字功能，并持续沉淀专属认知记忆"
        }
    }
}

/// 单条 AI 调优建议 / 执行结果
struct AutopilotProposedChange: Identifiable, Equatable, Sendable {
    var id: String { "\(settingKey)->\(targetValue)" }
    let settingKey: String
    let settingTitle: String
    let currentValue: String
    let targetValue: String
    let reason: String
    let evidence: String
    let confidence: Double
}

/// AI 托管一次完整运行的汇报结果
struct AutopilotRunOutcome: Equatable, Sendable {
    let usedLLM: Bool
    let appliedCount: Int
    let suggestedChanges: [AutopilotProposedChange]
    let newMemoriesCount: Int
    let summary: String
}

/// 灵犀 AI 全权操控与自我进化控制器：
/// 1. 白名单安全操控 26 项打字/纠错/模糊音/排版/防丢/智能预测开关（严禁触碰无痕模式、隐私脱敏护盾或密钥安全红线）；
/// 2. 离线本机引擎 0ms 可直接根据 `AICognitiveMemoryDB` 与 `TypingHabitTracker` 自动启用最匹配你习惯的打字功能；
/// 3. 配置了用户大模型 API Key 后，自动融合本地 SQLite 学习记录交由用户自己的 AI 深度洞察：输出结构化调优决策 + 长期认知记忆入库 + 「AI 懂你档案」反哺每一次聊天回复！
enum AIAutopilotController {

    /// 支持 AI 托管调优的全部安全白名单打字功能键
    static let settingTitles: [String: String] = [
        "typoCorrectionEnabled": "智能错拼容错纠错",
        "fuzzyFallbackEnabled": "模糊音智能兜底",
        "dynamicKeyHitBoxEnabled": "动态下一键防误触热区",
        "panguSpaceLetters": "中英文自动盘古空格",
        "panguSpaceDigits": "中文数字自动盘古空格",
        "smartEnglishCandidate": "英文单词智能直出",
        "emojiSuggestionEnabled": "打字 Emoji 实时联想",
        "autoPairPunctuation": "成对括号自动补全居中",
        "smartQuotePairing": "中文弯引号自动交替",
        "bigramPredictionEnabled": "上文二元词智能联想",
        "userLearningEnabled": "个人词库自学习",
        "glideTypingEnabled": "26 键中英文滑行输入",
        "draftRecoveryEnabled": "草稿防丢黑匣子",
        "smartOTPExtraction": "短信验证码智能提取",
        "autoExpireOTPEnabled": "验证码 15 分钟阅后即焚",
        "selectionMagicEnabled": "顶栏框选即改魔法条",
        "doubleSpacePeriod": "双击空格自动出句号",
        "autoCapitalizeEnglish": "英文句首自动大写",
        "fuzzy.zhZ": "模糊音 zh ↔ z",
        "fuzzy.chC": "模糊音 ch ↔ c",
        "fuzzy.shS": "模糊音 sh ↔ s",
        "fuzzy.anAng": "模糊音 an ↔ ang",
        "fuzzy.enEng": "模糊音 en ↔ eng",
        "fuzzy.inIng": "模糊音 in ↔ ing",
        "fuzzy.nl": "模糊音 n ↔ l",
        "fuzzy.fh": "模糊音 f ↔ h",
    ]

    /// 读取白名单开关当前值（格式化为 `"开"` / `"关"`）
    static func readSettingBool(_ key: String, from s: LingxiSettings) -> Bool? {
        switch key {
        case "typoCorrectionEnabled": return s.typoCorrectionEnabled
        case "fuzzyFallbackEnabled": return s.fuzzyFallbackEnabled
        case "dynamicKeyHitBoxEnabled": return s.dynamicKeyHitBoxEnabled
        case "panguSpaceLetters": return s.panguSpaceLetters
        case "panguSpaceDigits": return s.panguSpaceDigits
        case "smartEnglishCandidate": return s.smartEnglishCandidate
        case "emojiSuggestionEnabled": return s.emojiSuggestionEnabled
        case "autoPairPunctuation": return s.autoPairPunctuation
        case "smartQuotePairing": return s.smartQuotePairing
        case "bigramPredictionEnabled": return s.bigramPredictionEnabled
        case "userLearningEnabled": return s.userLearningEnabled
        case "glideTypingEnabled": return s.glideTypingEnabled
        case "draftRecoveryEnabled": return s.draftRecoveryEnabled
        case "smartOTPExtraction": return s.smartOTPExtraction
        case "autoExpireOTPEnabled": return s.autoExpireOTPEnabled
        case "selectionMagicEnabled": return s.selectionMagicEnabled
        case "doubleSpacePeriod": return s.doubleSpacePeriod
        case "autoCapitalizeEnglish": return s.autoCapitalizeEnglish
        case "fuzzy.zhZ": return s.fuzzy.zhZ
        case "fuzzy.chC": return s.fuzzy.chC
        case "fuzzy.shS": return s.fuzzy.shS
        case "fuzzy.anAng": return s.fuzzy.anAng
        case "fuzzy.enEng": return s.fuzzy.enEng
        case "fuzzy.inIng": return s.fuzzy.inIng
        case "fuzzy.nl": return s.fuzzy.nl
        case "fuzzy.fh": return s.fuzzy.fh
        default: return nil
        }
    }

    /// 写入白名单开关（仅允许操控安全白名单内的打字效率开关）
    @discardableResult
    static func writeSettingBool(_ key: String, value: Bool, into s: inout LingxiSettings) -> Bool {
        switch key {
        case "typoCorrectionEnabled": s.typoCorrectionEnabled = value
        case "fuzzyFallbackEnabled": s.fuzzyFallbackEnabled = value
        case "dynamicKeyHitBoxEnabled": s.dynamicKeyHitBoxEnabled = value
        case "panguSpaceLetters": s.panguSpaceLetters = value
        case "panguSpaceDigits": s.panguSpaceDigits = value
        case "smartEnglishCandidate": s.smartEnglishCandidate = value
        case "emojiSuggestionEnabled": s.emojiSuggestionEnabled = value
        case "autoPairPunctuation": s.autoPairPunctuation = value
        case "smartQuotePairing": s.smartQuotePairing = value
        case "bigramPredictionEnabled": s.bigramPredictionEnabled = value
        case "userLearningEnabled": s.userLearningEnabled = value
        case "glideTypingEnabled": s.glideTypingEnabled = value
        case "draftRecoveryEnabled": s.draftRecoveryEnabled = value
        case "smartOTPExtraction": s.smartOTPExtraction = value
        case "autoExpireOTPEnabled": s.autoExpireOTPEnabled = value
        case "selectionMagicEnabled": s.selectionMagicEnabled = value
        case "doubleSpacePeriod": s.doubleSpacePeriod = value
        case "autoCapitalizeEnglish": s.autoCapitalizeEnglish = value
        case "fuzzy.zhZ": s.fuzzy.zhZ = value
        case "fuzzy.chC": s.fuzzy.chC = value
        case "fuzzy.shS": s.fuzzy.shS = value
        case "fuzzy.anAng": s.fuzzy.anAng = value
        case "fuzzy.enEng": s.fuzzy.enEng = value
        case "fuzzy.inIng": s.fuzzy.inIng = value
        case "fuzzy.nl": s.fuzzy.nl = value
        case "fuzzy.fh": s.fuzzy.fh = value
        default: return false
        }
        return true
    }

    /// 1 键撤回某条 AI 自动托管决策
    @discardableResult
    static func revertDecision(
        _ record: AutopilotDecisionRecord,
        in settings: inout LingxiSettings,
        db: AICognitiveMemoryDB = .shared
    ) -> Bool {
        let oldBool = (record.oldValue == "开" || record.oldValue.lowercased() == "true")
        guard writeSettingBool(record.settingKey, value: oldBool, into: &settings) else { return false }
        db.markDecisionReverted(id: record.id)
        return true
    }

    /// 0ms 本地习惯分析与全权自动开启引擎（无网、无 API Key 也能持续运作）
    static func evaluateAndApplyLocal(
        settings: inout LingxiSettings,
        db: AICognitiveMemoryDB = .shared,
        habitProfile: UserTypingHabitProfile = TypingHabitTracker.shared.currentProfile(),
        topUserWords: [String] = []
    ) -> AutopilotRunOutcome {
        let mode = settings.aiAutopilotMode
        guard mode != .off else {
            return AutopilotRunOutcome(usedLLM: false, appliedCount: 0, suggestedChanges: [], newMemoriesCount: 0, summary: "AI 托管当前为手动模式。")
        }

        // 先将用户自学习词库高频词同步进 SQLite 认知库，确保 AI 掌握完整词库脉络
        for w in topUserWords.prefix(24) {
            db.recordVocabLearning(word: w)
        }

        let stats = db.loadStats()
        var proposals: [AutopilotProposedChange] = []
        var newMemories = 0

        func proposeIfNeeded(_ key: String, target: Bool, reason: String, evidence: String, confidence: Double) {
            guard let cur = readSettingBool(key, from: settings), cur != target else { return }
            let title = settingTitles[key] ?? key
            proposals.append(AutopilotProposedChange(
                settingKey: key,
                settingTitle: title,
                currentValue: cur ? "开" : "关",
                targetValue: target ? "开" : "关",
                reason: reason,
                evidence: evidence,
                confidence: confidence
            ))
        }

        // A. 基础旗舰核心体验保障（全权托管开启后，自动补齐核心效率能力）
        proposeIfNeeded("userLearningEnabled", target: true, reason: "开启个人词库自学习，让 AI 持续吸收你的高频用词与口癖", evidence: "AI 全权学习底座要求", confidence: 0.96)
        proposeIfNeeded("bigramPredictionEnabled", target: true, reason: "开启上下文二元词联想，减少重复敲键次数", evidence: "核心流畅输入策略", confidence: 0.94)
        proposeIfNeeded("typoCorrectionEnabled", target: true, reason: "开启 4 路错拼智能容错，手滑打反字母也能命中首选", evidence: stats.totalBackspaces > 0 ? "累计退格 \(stats.totalBackspaces) 次" : "高频手滑预防策略", confidence: 0.95)
        proposeIfNeeded("dynamicKeyHitBoxEnabled", target: true, reason: "开启 Apple 级动态下一键防误触热区，显著降低连击误触", evidence: stats.backspaceRate >= 0.12 ? "退格率 \(Int(stats.backspaceRate * 100))%" : "触控防误触基线", confidence: 0.92)
        proposeIfNeeded("draftRecoveryEnabled", target: true, reason: "自动守护长文本输入，防 App 切后台或刷新丢字", evidence: stats.totalLongDrafts > 0 ? "已捕捉 \(stats.totalLongDrafts) 段长草稿" : "防丢基础保障", confidence: 0.95)
        proposeIfNeeded("smartOTPExtraction", target: true, reason: "自动提取短信验证码并在键盘顶栏 1 点填入", evidence: "高频验证场景", confidence: 0.93)
        proposeIfNeeded("autoExpireOTPEnabled", target: true, reason: "15 分钟自动清理过期验证码，保持剪贴板清爽", evidence: "隐私与整洁策略", confidence: 0.91)
        proposeIfNeeded("selectionMagicEnabled", target: true, reason: "选中文字即在顶栏唤出离线包裹与 AI 润色胶囊", evidence: "快捷编辑效率策略", confidence: 0.90)
        proposeIfNeeded("fuzzyFallbackEnabled", target: true, reason: "未显式开模糊音时也在误拼兜底中自动补救", evidence: "模糊音安全网", confidence: 0.90)

        // B. 数据驱动的习惯自适应开启
        if stats.totalEnglishWords >= 3 || stats.englishMixRatio >= 0.08 || habitProfile.totalSessions >= 1 {
            proposeIfNeeded("panguSpaceLetters", target: true, reason: "检测到你常有中英混输，自动开启中英文盘古空格让排版更清爽", evidence: "累计英文词 \(stats.totalEnglishWords) 次", confidence: 0.91)
            proposeIfNeeded("smartEnglishCandidate", target: true, reason: "检测到英文技术/品牌词输入习惯，自动开启英文词直出首位", evidence: "中英混输占比 \(Int(stats.englishMixRatio * 100))%", confidence: 0.90)
        }
        if stats.totalDigitMix >= 3 {
            proposeIfNeeded("panguSpaceDigits", target: true, reason: "检测到你常在中文里混输数字，自动开启中数字视觉空格", evidence: "数字混输 \(stats.totalDigitMix) 次", confidence: 0.88)
        }
        if stats.totalEmojiPicks >= 2 || stats.totalCharsObserved >= 20 {
            proposeIfNeeded("emojiSuggestionEnabled", target: true, reason: "根据聊天表达习惯，自动开启句尾高频 Emoji 实时联想", evidence: "表情使用 \(stats.totalEmojiPicks) 次", confidence: 0.87)
        }
        if stats.totalBracketPairs >= 2 || stats.totalLongDrafts >= 1 {
            proposeIfNeeded("autoPairPunctuation", target: true, reason: "检测到高频括号与长文编辑，自动开启成对括号补全并光标居中", evidence: "括号输入 \(stats.totalBracketPairs) 次", confidence: 0.89)
            proposeIfNeeded("smartQuotePairing", target: true, reason: "自动交替配对中文弯引号，提升长文质感", evidence: "长文与标点习惯", confidence: 0.87)
        }

        // C. 模糊音精准自动探测（合并 SQLite 观察与 TypingHabitTracker 易混音计数）
        var mergedConfusions = stats.fuzzyConfusionCounts
        for (k, v) in habitProfile.confusionMatrix {
            mergedConfusions[k] = max(mergedConfusions[k] ?? 0, v)
        }
        let fuzzyMapping: [(dbKey: String, settingKey: String, label: String)] = [
            ("zh_z", "fuzzy.zhZ", "平翘舌 zh/z"),
            ("ch_c", "fuzzy.chC", "平翘舌 ch/c"),
            ("sh_s", "fuzzy.shS", "平翘舌 sh/s"),
            ("an_ang", "fuzzy.anAng", "前后鼻音 an/ang"),
            ("en_eng", "fuzzy.enEng", "前后鼻音 en/eng"),
            ("in_ing", "fuzzy.inIng", "前后鼻音 in/ing"),
            ("n_l", "fuzzy.nl", "鼻边音 n/l"),
            ("f_h", "fuzzy.fh", "声母 f/h"),
        ]
        for fm in fuzzyMapping {
            let hits = mergedConfusions[fm.dbKey] ?? 0
            if hits >= 3 {
                proposeIfNeeded(
                    fm.settingKey,
                    target: true,
                    reason: "数据库监测到你经常混淆 \(fm.label)，已自动为你开启对应模糊音",
                    evidence: "累计混淆 \(hits) 次",
                    confidence: min(0.98, 0.78 + Double(hits) * 0.03)
                )
            }
        }

        // D. 沉淀本机习惯记忆进入 SQLite `learned_memories`
        if stats.totalCharsObserved >= 10 {
            let mixDesc = stats.englishMixRatio >= 0.12 ? "中英混输频率较高，偏好技术/双语简洁表达" : "以纯中文日常/工作沟通为主，表达偏向自然口语"
            db.upsertMemory(CognitiveMemoryFact(
                category: "打字习惯",
                memoryKey: "local_typing_style",
                content: "累计观察 \(stats.totalCharsObserved) 字，\(mixDesc)。",
                confidence: 0.84,
                evidenceCount: max(1, stats.totalObservations),
                source: "local_auto"
            ))
            newMemories += 1
        }
        if stats.nightSessionRatio >= 0.35 && stats.totalObservations >= 3 {
            db.upsertMemory(CognitiveMemoryFact(
                category: "活跃时段",
                memoryKey: "local_night_owl",
                content: "有约 \(Int(stats.nightSessionRatio * 100))% 的输入发生在 22:00 后，属于偏夜间高效表达人群。",
                confidence: 0.82,
                evidenceCount: stats.totalObservations,
                source: "local_auto"
            ))
            newMemories += 1
        }
        let topVocab = db.fetchTopVocab(limit: 10)
        if !topVocab.isEmpty {
            let domainCounts = Dictionary(grouping: topVocab, by: \.domain).mapValues { $0.reduce(0) { $0 + $1.learnCount } }
            if let topDomain = domainCounts.max(by: { $0.value < $1.value }) {
                let sampleWords = topVocab.prefix(5).map(\.word).joined(separator: "、")
                db.upsertMemory(CognitiveMemoryFact(
                    category: "常用领域",
                    memoryKey: "local_top_domain",
                    content: "高频表达集中在「\(topDomain.key)」领域，常用自学习词包含：\(sampleWords)。",
                    confidence: 0.86,
                    evidenceCount: topVocab.count,
                    source: "local_auto"
                ))
                newMemories += 1
            }
        }
        let activeFuzzyNotes = fuzzyMapping.filter { (mergedConfusions[$0.dbKey] ?? 0) >= 3 }.map(\.label)
        if !activeFuzzyNotes.isEmpty {
            db.upsertMemory(CognitiveMemoryFact(
                category: "拼音特征",
                memoryKey: "local_fuzzy_profile",
                content: "在 \(activeFuzzyNotes.joined(separator: "、")) 上存在高频拼写混淆，已由 AI 针对性补偿。",
                confidence: 0.90,
                evidenceCount: activeFuzzyNotes.count,
                source: "local_auto"
            ))
            newMemories += 1
        }

        // E. 按托管模式执行或返回提案
        var appliedCount = 0
        if mode == .fullAutopilot {
            for prop in proposals {
                let targetBool = (prop.targetValue == "开")
                if writeSettingBool(prop.settingKey, value: targetBool, into: &settings) {
                    appliedCount += 1
                    db.insertDecision(AutopilotDecisionRecord(
                        settingKey: prop.settingKey,
                        settingTitle: prop.settingTitle,
                        oldValue: prop.currentValue,
                        newValue: prop.targetValue,
                        reason: prop.reason,
                        evidence: prop.evidence,
                        confidence: prop.confidence,
                        source: "local_auto"
                    ))
                }
            }
        }

        db.setMeta("last_autopilot_run_at", value: "\(Int(Date().timeIntervalSince1970))")
        let summary: String
        if mode == .fullAutopilot {
            summary = appliedCount > 0
                ? "AI 习惯引擎已基于本机数据库自动开启/优化 \(appliedCount) 项打字功能，并更新 \(newMemories) 条个人记忆。"
                : "本机习惯体检完成：你的全部核心打字功能已处于最佳开启状态，记忆库持续同步中。"
        } else {
            summary = proposals.isEmpty
                ? "当前设置已很契合你的打字习惯，暂无待调整项。"
                : "AI 发现 \(proposals.count) 项值得为你开启的打字功能，可在下方一键采纳。"
        }

        return AutopilotRunOutcome(
            usedLLM: false,
            appliedCount: appliedCount,
            suggestedChanges: mode == .fullAutopilot ? [] : proposals,
            newMemoriesCount: newMemories,
            summary: summary
        )
    }

    /// 调用用户自己的大模型执行「深度认知记忆提炼 + 全权智能调优」
    static func runDeepLLMAutopilot(
        settings: inout LingxiSettings,
        aiConfig: AIConfig,
        db: AICognitiveMemoryDB = .shared,
        habitProfile: UserTypingHabitProfile = TypingHabitTracker.shared.currentProfile(),
        topUserWords: [String] = [],
        client: AIClient = AIClient(timeout: 35)
    ) async -> AutopilotRunOutcome {
        // 先跑 0ms 本机基线体检
        let localOutcome = evaluateAndApplyLocal(
            settings: &settings,
            db: db,
            habitProfile: habitProfile,
            topUserWords: topUserWords
        )

        guard aiConfig.isConfigured else {
            return localOutcome
        }

        let stats = db.loadStats()
        let topVocab = db.fetchTopVocab(limit: 20).map { "\($0.word)(\($0.domain)×\($0.learnCount))" }.joined(separator: "、")
        let existingMemories = db.fetchMemories(limit: 12).map { "[\($0.category)] \($0.content)" }.joined(separator: "\n")
        let currentSwitches = settingTitles.keys.sorted().compactMap { key -> String? in
            guard let v = readSettingBool(key, from: settings) else { return nil }
            return "\(key)=\(v ? "true" : "false")"
        }.joined(separator: ", ")

        let sysPrompt = """
        你是「灵犀输入法 AI 智脑托管管家」。请根据用户的本机 SQLite 打字学习统计、高频词汇与当前开关状态，深度理解用户习惯，并只输出一个合法 JSON 对象（严禁 Markdown 围栏或多余说明）：
        {
          "persona_digest": "一句话精准概括这位用户的打字风格、关注领域与沟通偏好（30-70字，用来让后续所有 AI 回复更懂 TA）",
          "summary": "向用户汇报本次分析与调优结果（30-60字，自然亲切）",
          "memories": [
            {"category": "表达习惯", "key": "llm_style_1", "content": "具体可复用的个人习惯洞察（15-45字）", "confidence": 0.9}
          ],
          "setting_changes": [
            {"key": "白名单键名", "value": true, "reason": "为什么要为用户开启或关闭此功能（15-35字）"}
          ]
        }
        要求：
        1. `setting_changes` 中的 `key` 只能从以下白名单挑选，且只返回确实需要变更的项：\(settingTitles.keys.sorted().joined(separator: ", "))；
        2. `memories` 提炼 2–4 条真正有价值、能让 AI 以后写得更像用户的长期认知记忆；
        3. 只输出纯 JSON。
        """

        let userDigest = """
        【本机 SQLite 认知学习数据库摘要】
        - 累计观察会话：\(stats.totalObservations) 次，累计字数：\(stats.totalCharsObserved) 字，词数：\(stats.totalWordsObserved)
        - 退格率：\(String(format: "%.1f%%", stats.backspaceRate * 100))，错拼自动纠正：\(stats.totalTypoFixes) 次
        - 中英混输词：\(stats.totalEnglishWords)（占比 \(String(format: "%.1f%%", stats.englishMixRatio * 100))），数字混输：\(stats.totalDigitMix) 次
        - 表情联想使用：\(stats.totalEmojiPicks) 次，长草稿：\(stats.totalLongDrafts) 段，夜间打字占比：\(Int(stats.nightSessionRatio * 100))%
        - 易混音记录：\(stats.fuzzyConfusionCounts.isEmpty ? "暂无明显混淆" : stats.fuzzyConfusionCounts.map { "\($0.key):\($0.value)" }.joined(separator: ", "))
        - 高频自学习词：\(topVocab.isEmpty ? "暂无" : topVocab)
        - 既有认知记忆：\(existingMemories.isEmpty ? "暂无" : existingMemories)
        - 当前打字功能开关：\(currentSwitches)
        """

        do {
            var raw = ""
            for try await chunk in client.streamText(
                prompt: userDigest,
                systemInstruction: sysPrompt,
                config: aiConfig,
                featureTag: "ai_autopilot_brain",
                preferFast: true
            ) {
                raw += chunk
            }
            return applyParsedLLMJSON(raw, settings: &settings, db: db, localApplied: localOutcome.appliedCount, localMemories: localOutcome.newMemoriesCount)
        } catch {
            return AutopilotRunOutcome(
                usedLLM: false,
                appliedCount: localOutcome.appliedCount,
                suggestedChanges: localOutcome.suggestedChanges,
                newMemoriesCount: localOutcome.newMemoriesCount,
                summary: "\(localOutcome.summary)（大模型深度分析暂未连通：\(error.localizedDescription)）"
            )
        }
    }

    /// 纯函数：解析大模型返回的托管 JSON 并按当前模式写入 SQLite 与设置（便于单元测试）
    static func applyParsedLLMJSON(
        _ rawText: String,
        settings: inout LingxiSettings,
        db: AICognitiveMemoryDB,
        localApplied: Int = 0,
        localMemories: Int = 0
    ) -> AutopilotRunOutcome {
        let cleaned = extractJSONObject(from: rawText)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AutopilotRunOutcome(
                usedLLM: false,
                appliedCount: localApplied,
                suggestedChanges: [],
                newMemoriesCount: localMemories,
                summary: "已完成本机学习数据库分析（大模型返回格式非 JSON，已保留本机调优结果）。"
            )
        }

        if let digest = (obj["persona_digest"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !digest.isEmpty {
            db.setMeta("persona_digest", value: String(digest.prefix(200)))
        }

        var memAdded = localMemories
        if let memories = obj["memories"] as? [[String: Any]] {
            for (idx, item) in memories.prefix(6).enumerated() {
                guard let content = (item["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !content.isEmpty else { continue }
                let cat = (item["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "大模型洞察"
                let key = (item["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "llm_mem_\(idx)"
                let conf = (item["confidence"] as? Double) ?? 0.88
                db.upsertMemory(CognitiveMemoryFact(
                    category: cat.isEmpty ? "大模型洞察" : cat,
                    memoryKey: key.isEmpty ? "llm_mem_\(idx)" : key,
                    content: content,
                    confidence: conf,
                    evidenceCount: 1,
                    source: "ai_llm"
                ))
                memAdded += 1
            }
        }

        var applied = localApplied
        var suggested: [AutopilotProposedChange] = []
        if let changes = obj["setting_changes"] as? [[String: Any]] {
            for ch in changes.prefix(12) {
                guard let key = ch["key"] as? String,
                      let targetBool = ch["value"] as? Bool,
                      let curBool = readSettingBool(key, from: settings),
                      curBool != targetBool else { continue }
                let title = settingTitles[key] ?? key
                let reason = (ch["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "AI 根据你的打字习惯建议优化"
                if settings.aiAutopilotMode == .fullAutopilot {
                    if writeSettingBool(key, value: targetBool, into: &settings) {
                        applied += 1
                        db.insertDecision(AutopilotDecisionRecord(
                            settingKey: key,
                            settingTitle: title,
                            oldValue: curBool ? "开" : "关",
                            newValue: targetBool ? "开" : "关",
                            reason: reason,
                            evidence: "用户大模型深度习惯分析",
                            confidence: 0.92,
                            source: "ai_llm"
                        ))
                    }
                } else if settings.aiAutopilotMode == .suggest {
                    suggested.append(AutopilotProposedChange(
                        settingKey: key,
                        settingTitle: title,
                        currentValue: curBool ? "开" : "关",
                        targetValue: targetBool ? "开" : "关",
                        reason: reason,
                        evidence: "用户大模型深度习惯分析",
                        confidence: 0.92
                    ))
                }
            }
        }

        db.setMeta("last_autopilot_run_at", value: "\(Int(Date().timeIntervalSince1970))")
        let aiSummary = (obj["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSummary = (aiSummary?.isEmpty == false)
            ? aiSummary!
            : "AI 已深度读取你的学习数据库：沉淀 \(memAdded) 条个人认知记忆，自动调优 \(applied) 项打字功能。"

        return AutopilotRunOutcome(
            usedLLM: true,
            appliedCount: applied,
            suggestedChanges: suggested,
            newMemoriesCount: memAdded,
            summary: finalSummary
        )
    }

    private static func extractJSONObject(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") ,
              start <= end else {
            return trimmed
        }
        return String(trimmed[start...end])
    }
}
