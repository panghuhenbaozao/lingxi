import Foundation

/// 单次 Obsidian 自学习知识库提炼与图谱演化汇报
struct ObsidianLearningOutcome: Equatable, Sendable {
    let usedLLM: Bool
    let upsertedNotesCount: Int
    let mergedNotesCount: Int
    let createdLinksCount: Int
    let appliedSettingsCount: Int
    let summary: String
}

/// 灵犀 Obsidian 风格「LLM Wiki + Zettelkasten + A-MEM」自学习双链记忆库引擎
/// 1. 双向 `[[Wikilinks]]` 与 `#标签` 解析、真实 YAML Frontmatter `.md` 渲染与整库 Obsidian Markdown 导出；
/// 2. Ebbinghaus 记忆强化与时间衰减模型 + 2-Hop 知识图谱 Graph-RAG 按需召回（精准反哺每一次 AI 润色/回复/翻译）；
/// 3. 调用用户自填大模型 API 执行「原始笔记/聊天习惯/打字数据库 → 原子常青笔记 + 双向链接 + 冲突合并 + 功能托管」持续自学习闭环。
enum ObsidianMemoryVaultEngine {

    // MARK: - 1. Obsidian [[Wikilink]] & #Tag 解析器

    /// 从 Markdown 正文中提取所有 `[[目标笔记]]` 或 `[[目标笔记|别名]]` 的真实目标标题（保序去重）
    static func parseWikilinks(in markdown: String) -> [String] {
        guard markdown.contains("[[") else { return [] }
        let ns = markdown as NSString
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\[\]\|#]+?)(?:#[^\[\]\|]*)?(?:\|[^\[\]]*)?\]\]"#) else {
            return []
        }
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        var seen = Set<String>()
        var out: [String] = []
        for m in matches where m.numberOfRanges >= 2 {
            let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let norm = AICognitiveMemoryDB.normalizeSlug(raw)
            if !raw.isEmpty, !norm.isEmpty, seen.insert(norm).inserted {
                out.append(raw)
            }
        }
        return out
    }

    /// 提取正文中的 `#标签`（忽略 Markdown 标题 `# 标题` 与 URL 锚点）
    static func parseHashtags(in markdown: String) -> [String] {
        guard markdown.contains("#") else { return [] }
        let ns = markdown as NSString
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|[\s，。；、])#([\u4e00-\u9fffA-Za-z0-9_\-]{1,18})"#) else {
            return []
        }
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        var seen = Set<String>()
        var out: [String] = []
        for m in matches where m.numberOfRanges >= 2 {
            let tag = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tag.isEmpty, seen.insert(tag).inserted {
                out.append(tag)
            }
        }
        return out
    }

    // MARK: - 2. 真实 Obsidian YAML Frontmatter `.md` 渲染与整库导出

    static func renderObsidianMarkdown(note: ObsidianVaultNote, backlinks: [ObsidianVaultNote] = []) -> String {
        let iso = ISO8601DateFormatter()
        let updatedStr = iso.string(from: Date(timeIntervalSince1970: TimeInterval(note.updatedAt)))
        let escapedTags = note.tags.map { tag -> String in
            let clean = tag.replacingOccurrences(of: "\"", with: "")
            return "\"\(clean)\""
        }.joined(separator: ", ")
        let tagsYAML = note.tags.isEmpty ? "[]" : "[\(escapedTags)]"
        let escapedTitle = note.title.replacingOccurrences(of: "\"", with: "")
        let strengthStr = String(format: "%.2f", note.strength)
        let pinnedStr = note.isPinned ? "true" : "false"

        var lines: [String] = [
            "---",
            "title: \"\(escapedTitle)\"",
            "folder: \(note.folder.rawValue)",
            "tags: \(tagsYAML)",
            "strength: \(strengthStr)",
            "recall_count: \(note.recallCount)",
            "source: \(note.source)",
            "pinned: \(pinnedStr)",
            "updated: \(updatedStr)",
            "---",
            "",
            "# \(note.title)",
            "",
        ]
        if !note.summary.isEmpty {
            lines.append("> \(note.summary)")
            lines.append("")
        }
        lines.append(note.bodyMarkdown)

        if !backlinks.isEmpty {
            lines.append("")
            lines.append("## 反向链接 (Backlinks)")
            for b in backlinks {
                lines.append("- [[\(b.title)]] — \(b.summary.isEmpty ? b.folder.displayTitle : b.summary)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 导出完整 Obsidian 兼容 Markdown 知识库汇总包（含 `index.md` MOC、全部双链笔记与 `log.md` 演化轨迹）
    static func exportFullObsidianMarkdownVault(db: AICognitiveMemoryDB = .shared) -> String {
        let notes = db.fetchVaultNotes(limit: 200)
        let links = db.fetchAllVaultLinks(limit: 500)
        let logs = db.fetchEvolutionLogs(limit: 80)
        let bySlug = Dictionary(uniqueKeysWithValues: notes.map { ($0.slug, $0) })

        var out: [String] = [
            "# 灵犀 Obsidian 风格个人自学习记忆库 (Lingxi LLM Wiki)",
            "",
            "> 导出时间：\(ISO8601DateFormatter().string(from: Date())) · 共 \(notes.count) 篇原子笔记 · \(links.count) 条双向链接",
            "",
            "## index.md · 知识图谱总目录 (MOC)",
        ]
        for folder in VaultNoteFolder.allCases {
            let group = notes.filter { $0.folder == folder }
            if !group.isEmpty {
                out.append("### \(folder.displayTitle) (`/\(folder.rawValue)`)")
                for n in group {
                    out.append("- [[\(n.title)]] (\(Int(n.strength * 100))% 强度 · 召回 \(n.recallCount) 次) — \(n.summary)")
                }
            }
        }

        for note in notes {
            let backSlugs = links.filter { $0.toSlug == note.slug }.map(\.fromSlug)
            let backNotes = backSlugs.compactMap { bySlug[$0] }
            out.append("")
            out.append("================================================================")
            out.append("FILE: \(note.folder.rawValue)/\(note.title).md")
            out.append("================================================================")
            out.append(renderObsidianMarkdown(note: note, backlinks: backNotes))
        }

        if !logs.isEmpty {
            out.append("")
            out.append("================================================================")
            out.append("FILE: log.md")
            out.append("================================================================")
            for entry in logs {
                let d = Date(timeIntervalSince1970: TimeInterval(entry.createdAt)).formatted(date: .abbreviated, time: .shortened)
                out.append("- [\(d)] **\(entry.actionDisplayName)** `\(entry.noteTitle)`：\(entry.detail) (`\(entry.source)`)")
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - 3. Ebbinghaus 记忆稳定度与 2-Hop Obsidian Graph-RAG 召回

    /// 结合记忆强度、召回频次与时间间隔计算当前有效活跃度（置顶常青笔记免疫衰减）
    static func effectiveStrength(for note: ObsidianVaultNote, now: Date = Date()) -> Double {
        if note.isPinned { return max(0.92, note.strength) }
        let lastActive = max(note.updatedAt, note.lastRecalledAt)
        let days = max(0.0, (now.timeIntervalSince1970 - TimeInterval(lastActive)) / 86400.0)
        // 回忆次数越多，半衰期越长（模拟间隔重复记忆固化）
        let halfLifeDays = 30.0 + Double(min(note.recallCount, 20)) * 6.0
        let decay = exp(-days / halfLifeDays)
        return min(1.0, max(0.15, note.strength * decay))
    }

    struct RecalledVaultNote: Equatable, Sendable {
        let note: ObsidianVaultNote
        let score: Double
        let viaHopTitle: String?
    }

    /// 2-Hop 双向知识图谱召回：先按语义/场景/标签/活跃度选出种子笔记，再沿 `[[出链]]` 与 `[[反链]]` 扩散 1 跳补齐深层关联背景
    static func recallGraphNotes(
        query: String,
        scene: String = "",
        db: AICognitiveMemoryDB = .shared,
        limit: Int = 6,
        reinforce: Bool = false,
        now: Date = Date()
    ) -> [RecalledVaultNote] {
        let allNotes = db.fetchVaultNotes(limit: 160).filter { $0.folder != .inbox }
        guard !allNotes.isEmpty else { return [] }
        let allLinks = db.fetchAllVaultLinks(limit: 500)
        let bySlug = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.slug, $0) })

        let queryTokens = extractSemanticTokens("\(query) \(scene)")
        var directScores: [String: Double] = [:]

        for note in allNotes {
            var score = effectiveStrength(for: note, now: now) * 2.0
            if note.isPinned { score += 3.2 }
            if note.folder == .persona { score += 0.6 }
            if note.folder == .index { score += 0.3 }
            score += min(1.5, log(Double(note.recallCount + 1)) * 0.45)

            if !queryTokens.isEmpty {
                let haystackTokens = extractSemanticTokens("\(note.title) \(note.summary) \(note.tags.joined(separator: " ")) \(note.bodyMarkdown)")
                let overlap = queryTokens.intersection(haystackTokens).count
                if overlap > 0 {
                    score += Double(overlap) * 1.45
                }
                let qLower = query.lowercased()
                if !qLower.isEmpty {
                    if qLower.contains(note.title.lowercased()) { score += 4.0 }
                    for tag in note.tags where !tag.isEmpty && qLower.contains(tag.lowercased()) {
                        score += 2.2
                    }
                }
            }
            directScores[note.slug] = score
        }

        // 选取 Top-3 种子笔记进行 1 跳双向图扩散（出链 + 反链）
        let seeds = allNotes
            .sorted { (directScores[$0.slug] ?? 0) > (directScores[$1.slug] ?? 0) }
            .prefix(3)

        var graphBonus: [String: (bonus: Double, via: String)] = [:]
        for seed in seeds {
            let seedScore = directScores[seed.slug] ?? 0
            for edge in allLinks where edge.fromSlug == seed.slug || edge.toSlug == seed.slug {
                let neighborSlug = (edge.fromSlug == seed.slug) ? edge.toSlug : edge.fromSlug
                guard neighborSlug != seed.slug, bySlug[neighborSlug] != nil else { continue }
                let propagated = min(3.0, seedScore * 0.32 * edge.weight)
                if propagated > (graphBonus[neighborSlug]?.bonus ?? 0) {
                    graphBonus[neighborSlug] = (propagated, seed.title)
                }
            }
        }

        let ranked: [RecalledVaultNote] = allNotes.map { note in
            let base = directScores[note.slug] ?? 0
            let hop = graphBonus[note.slug]
            return RecalledVaultNote(
                note: note,
                score: base + (hop?.bonus ?? 0),
                viaHopTitle: hop?.via
            )
        }
        .sorted {
            if abs($0.score - $1.score) > 0.01 { return $0.score > $1.score }
            return $0.note.updatedAt > $1.note.updatedAt
        }

        let picked = Array(ranked.prefix(max(1, limit)))
        if reinforce && !picked.isEmpty {
            let slugs = picked.map(\.note.slug)
            DispatchQueue.global(qos: .utility).async {
                db.reinforceVaultNotes(slugs: slugs, boost: 0.025)
            }
        }
        return picked
    }

    /// 供 `AIClient.mergeSystem` 调用的查询感知 Obsidian 图谱记忆上下文块
    static func recallPromptContextBlock(
        query: String,
        scene: String = "",
        db: AICognitiveMemoryDB = .shared,
        limit: Int = 6
    ) -> String {
        let recalled = recallGraphNotes(query: query, scene: scene, db: db, limit: limit, reinforce: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        guard !recalled.isEmpty else { return "" }

        var lines: [String] = []
        for item in recalled {
            let n = item.note
            let pct = Int(effectiveStrength(for: n) * 100)
            let hopLabel = item.viaHopTitle.map { " · 双链关联:[[\($0)]]" } ?? ""
            let brief = n.summary.isEmpty ? String(n.bodyMarkdown.prefix(90)) : n.summary
            lines.append("- [[\(n.title)]] (\(n.folder.displayTitle) · 记忆度\(pct)%\(hopLabel)): \(brief)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 4. 0ms 本地双链图谱冷启动与自动同步

    @discardableResult
    static func seedAndRefreshLocalVault(
        db: AICognitiveMemoryDB = .shared,
        habitProfile: UserTypingHabitProfile = TypingHabitTracker.shared.currentProfile(),
        topUserWords: [String] = []
    ) -> Int {
        let stats = db.loadStats()
        let topVocab = db.fetchTopVocab(limit: 12)
        let legacyMems = db.fetchMemories(limit: 12)
        var created = 0

        // 1. 总览索引 MOC 笔记（index.md）
        let digest = stats.personaDigest.isEmpty
            ? "持续根据你的打字行为、高频自学习词与 AI 互动演化专属个性化档案。"
            : stats.personaDigest
        let mocBody = """
        本节点为灵犀 Obsidian 风格记忆库总导航（MOC），自动汇总你的核心习惯与偏好：
        - 核心画像：\(digest)
        - 输入习惯脉络：[[打字风格画像]] · [[常用词汇领域]] · [[拼音纠偏策略]]
        - 互动节奏与进化：[[活跃作息节律]]
        #MOC #总览 #灵犀AI
        """
        db.upsertVaultNote(ObsidianVaultNote(
            title: "AI 个人记忆总览",
            folder: .index,
            summary: digest,
            bodyMarkdown: mocBody,
            tags: ["MOC", "总览", "常青"],
            strength: 0.90,
            source: "local_auto",
            isPinned: false
        ))
        created += 1

        // 2. 打字风格画像
        if stats.totalCharsObserved > 0 || habitProfile.totalSessions > 0 {
            let mixStyle = stats.englishMixRatio >= 0.10 ? "偏中英混输（适合自动盘古空格与英文词直出）" : "以中文流畅表达为主"
            let body = """
            累计观察 \(stats.totalObservations) 次会话、\(stats.totalCharsObserved) 字（退格率 \(Int(stats.backspaceRate * 100))%）。
            表达特征：\(mixStyle)。
            相关节点：[[AI 个人记忆总览]] · [[常用词汇领域]] · [[拼音纠偏策略]]
            #打字习惯 #输入节奏
            """
            db.upsertVaultNote(ObsidianVaultNote(
                title: "打字风格画像",
                folder: .habits,
                summary: "累计观察 \(stats.totalCharsObserved) 字，\(mixStyle)",
                bodyMarkdown: body,
                tags: ["打字习惯", "输入节奏"],
                strength: 0.80,
                source: "local_auto"
            ))
            created += 1
        }

        // 3. 常用词汇领域
        let wordsList = topVocab.isEmpty ? topUserWords.prefix(8).map { $0 } : topVocab.prefix(8).map(\.word)
        if !wordsList.isEmpty {
            let domains = Dictionary(grouping: topVocab, by: \.domain).mapValues { $0.reduce(0) { $0 + $1.learnCount } }
            let primaryDomain = domains.max(by: { $0.value < $1.value })?.key ?? "日常高频"
            let body = """
            当前最活跃的专业/生活词域为「\(primaryDomain)」，高频自学习词包括：\(wordsList.joined(separator: "、"))。
            AI 在润色、续写和生成回复时，应优先贴合该领域术语与语感。
            相关节点：[[打字风格画像]] · [[AI 个人记忆总览]]
            #常用领域 #\(primaryDomain)
            """
            db.upsertVaultNote(ObsidianVaultNote(
                title: "常用词汇领域",
                folder: .wiki,
                summary: "核心词域「\(primaryDomain)」，高频词：\(wordsList.prefix(5).joined(separator: "、"))",
                bodyMarkdown: body,
                tags: ["常用领域", primaryDomain],
                strength: 0.82,
                source: "local_auto"
            ))
            created += 1
        }

        // 4. 拼音纠偏策略
        var mergedConf = stats.fuzzyConfusionCounts
        for (k, v) in habitProfile.confusionMatrix {
            mergedConf[k] = max(mergedConf[k] ?? 0, v)
        }
        let topConf = mergedConf.filter { $0.value >= 2 }.sorted { $0.value > $1.value }
        if !topConf.isEmpty {
            let desc = topConf.prefix(5).map { "\($0.key.replacingOccurrences(of: "_", with: "/")) (×\($0.value))" }.joined(separator: "、")
            let body = """
            系统通过本地 SQLite 持续监测到以下高频拼音混淆对：\(desc)。
            全权托管开启后，超过 3 次的混淆对将自动激活对应模糊音补偿。
            相关节点：[[打字风格画像]] · [[AI 个人记忆总览]]
            #模糊音 #纠错策略
            """
            db.upsertVaultNote(ObsidianVaultNote(
                title: "拼音纠偏策略",
                folder: .habits,
                summary: "高频混淆音：\(desc)",
                bodyMarkdown: body,
                tags: ["模糊音", "纠错策略"],
                strength: 0.85,
                source: "local_auto"
            ))
            created += 1
        }

        // 5. 活跃作息节律
        if stats.totalObservations >= 3 {
            let nightPct = Int(stats.nightSessionRatio * 100)
            let rhythmDesc = nightPct >= 35 ? "偏夜间高频输入（22:00 后占比 \(nightPct)%）" : "以日间沟通工作为主（夜间占比 \(nightPct)%）"
            let body = """
            当前活跃节律：\(rhythmDesc)。
            相关节点：[[AI 个人记忆总览]] · [[打字风格画像]]
            #作息节律
            """
            db.upsertVaultNote(ObsidianVaultNote(
                title: "活跃作息节律",
                folder: .persona,
                summary: rhythmDesc,
                bodyMarkdown: body,
                tags: ["作息节律"],
                strength: 0.74,
                source: "local_auto"
            ))
            created += 1
        }

        // 6. 将用户手动补充的旧记忆同步沉淀为置顶原子笔记
        for mem in legacyMems where mem.source == "user_manual" {
            let title = String(mem.content.prefix(12)).replacingOccurrences(of: "\n", with: " ")
            let body = """
            \(mem.content)

            相关节点：[[AI 个人记忆总览]]
            #\(mem.category) #手动录入
            """
            db.upsertVaultNote(ObsidianVaultNote(
                title: title.isEmpty ? mem.category : title,
                folder: .persona,
                summary: mem.content,
                bodyMarkdown: body,
                tags: [mem.category, "手动录入"],
                strength: 0.96,
                source: "user_manual",
                isPinned: true
            ))
        }

        return created
    }

    // MARK: - 5. 用用户填写的 API 执行 Obsidian 自学习提炼、双链构建与个性化调优

    static func consolidateWithUserAPI(
        rawInboxText: String? = nil,
        settings: inout LingxiSettings,
        aiConfig: AIConfig,
        db: AICognitiveMemoryDB = .shared,
        habitProfile: UserTypingHabitProfile = TypingHabitTracker.shared.currentProfile(),
        topUserWords: [String] = [],
        recentHistory: [AIRecentResultItem] = AIRecentHistoryStore.load(),
        client: AIClient = AIClient(timeout: 45)
    ) async -> ObsidianLearningOutcome {
        // 先跑 0ms 本机托管与本地双链种子，保证无网也有完整体验
        let localAutopilot = AIAutopilotController.evaluateAndApplyLocal(
            settings: &settings,
            db: db,
            habitProfile: habitProfile,
            topUserWords: topUserWords
        )
        let localSeedCount = seedAndRefreshLocalVault(db: db, habitProfile: habitProfile, topUserWords: topUserWords)

        // 若用户输入了原始收件箱文本，脱敏后暂存进 inbox 节点留痕
        let cleanInbox = rawInboxText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanInbox.isEmpty && !ClipboardClassifier.isSensitiveContent(cleanInbox) {
            let safeInbox = AIPrivacyShield.sanitize(cleanInbox, customTerms: aiConfig.privacyCustomTerms).sanitizedText
            db.upsertVaultNote(ObsidianVaultNote(
                title: "收件箱-\(Int(Date().timeIntervalSince1970) % 10000)",
                folder: .inbox,
                summary: String(safeInbox.prefix(48)),
                bodyMarkdown: safeInbox,
                tags: ["收件箱", "待提炼"],
                strength: 0.60,
                source: "user_manual"
            ))
        }

        guard aiConfig.isConfigured else {
            return ObsidianLearningOutcome(
                usedLLM: false,
                upsertedNotesCount: localSeedCount,
                mergedNotesCount: 0,
                createdLinksCount: db.fetchAllVaultLinks(limit: 200).count,
                appliedSettingsCount: localAutopilot.appliedCount,
                summary: "已完成本机双链图谱构建（\(localSeedCount) 篇基础笔记）。填写 API Key 后即可解锁 Obsidian 级大模型深度自学习与自动建链。"
            )
        }

        let stats = db.loadStats()
        let existingNotes = db.fetchVaultNotes(limit: 30)
        let existingCatalog = existingNotes.map { note in
            "- [[\(note.title)]] (\(note.folder.rawValue), 强度\(Int(note.strength * 100))%): \(note.summary)"
        }.joined(separator: "\n")

        let vocabLine = db.fetchTopVocab(limit: 24).map { "\($0.word)(\($0.domain)×\($0.learnCount))" }.joined(separator: "、")
        let recentAI = recentHistory.prefix(6).map { item in
            let safePrompt = AIPrivacyShield.sanitize(String(item.prompt.prefix(60)), customTerms: aiConfig.privacyCustomTerms).sanitizedText
            let safeOut = AIPrivacyShield.sanitize(String(item.output.prefix(80)), customTerms: aiConfig.privacyCustomTerms).sanitizedText
            return "- [\(item.title)] 问: \(safePrompt) -> 选定答复: \(safeOut)"
        }.joined(separator: "\n")
        let styleBlock = aiConfig.styleDNA.promptConstraintBlock()
        let currentSwitches = AIAutopilotController.settingTitles.keys.sorted().compactMap { key -> String? in
            guard let v = AIAutopilotController.readSettingBool(key, from: settings) else { return nil }
            return "\(key)=\(v ? "true" : "false")"
        }.joined(separator: ", ")

        let systemPrompt = """
        你是「灵犀 Obsidian 风格个人自学习记忆库（LLM Wiki + Zettelkasten）」的首席知识建筑师兼打字管家。
        请综合用户的打字统计、高频词汇、近期 AI 交互、已有双链笔记目录与新收件箱内容，执行「原子知识提炼 + [[双向链接]] 构建 + 重复合并 + 打字功能个性化调优」。
        你必须只输出一个合法 JSON 对象（禁止 Markdown 围栏与任何多余说明）：
        {
          "persona_digest": "一句话精准概括这位用户的核心身份、表达审美与沟通偏好（30-75字）",
          "summary": "向用户亲切汇报本次提炼了几篇原子笔记、建立了哪些双链与调优（30-70字）",
          "notes_to_upsert": [
            {
              "title": "简短原子标题（4-14字，作为 [[双链目标]]）",
              "folder": "wiki | persona | habits",
              "summary": "一句话核心结论（15-45字，供后续 Prompt 精准召回）",
              "body_markdown": "结构化 Markdown 笔记正文（50-180字），务必自然嵌入 1-3 个 [[已有或新建的关联笔记标题]] 双向链接与 #标签",
              "tags": ["标签1", "标签2"],
              "links": [{"to": "关联笔记标题", "relation": "related | prefers | causes | part_of"}]
            }
          ],
          "notes_to_merge": [
            {"keep_title": "保留的主标题", "drop_title": "被吸收的重复标题", "merged_summary": "合并摘要", "merged_body": "合并后的正文含 [[双链]]"}
          ],
          "setting_changes": [
            {"key": "白名单键名", "value": true, "reason": "开启或关闭理由（15-35字）"}
          ]
        }
        规则：
        1. 严守 Zettelkasten 原子原则：每篇笔记聚焦 1 个清晰长期可用的个性化知识/习惯/沟通原则，优先更新或链接「已有笔记目录」，不要制造重复碎片；
        2. 每次产出 2–5 篇高价值 `notes_to_upsert`，确保笔记之间用 `[[标题]]` 形成有机的知识网络；
        3. `setting_changes` 仅允许从安全白名单挑选确有必要变更的项：\(AIAutopilotController.settingTitles.keys.sorted().joined(separator: ", "))；
        4. 严禁在笔记中保留任何隐私手机号、身份证号、密钥或银行卡号；只输出纯 JSON。
        """

        let safeInboxSection = cleanInbox.isEmpty
            ? "（无新增手动收件箱内容）"
            : AIPrivacyShield.sanitize(String(cleanInbox.prefix(1200)), customTerms: aiConfig.privacyCustomTerms).sanitizedText

        let userPayload = """
        【1. 现有 Obsidian 双链记忆库目录（共 \(existingNotes.count) 篇，优先复用标题或建立 [[双链]]）】
        \(existingCatalog.isEmpty ? "（首次冷启动）" : existingCatalog)

        【2. 用户主动投入的新笔记 / 自述（高优先级提炼为原子笔记与双链）】
        \(safeInboxSection)

        【3. 本地 SQLite 打字习惯与词汇库】
        - 观察会话：\(stats.totalObservations) 次，累计 \(stats.totalCharsObserved) 字，退格率 \(String(format: "%.1f%%", stats.backspaceRate * 100))
        - 中英混输占比：\(String(format: "%.1f%%", stats.englishMixRatio * 100))，夜间活跃占比：\(Int(stats.nightSessionRatio * 100))%
        - 易混音计数：\(stats.fuzzyConfusionCounts.isEmpty ? "暂无" : stats.fuzzyConfusionCounts.map { "\($0.key):\($0.value)" }.joined(separator: ", "))
        - 高频自学习词：\(vocabLine.isEmpty ? "暂无" : vocabLine)

        【4. 近期 AI 交互偏好与文风 DNA（已脱敏）】
        \(recentAI.isEmpty ? "（暂无近期交互）" : recentAI)
        \(styleBlock.isEmpty ? "" : "\n文风 DNA：\n\(styleBlock)")

        【5. 当前打字功能开关状态】
        \(currentSwitches)
        """

        do {
            var raw = ""
            for try await chunk in client.streamText(
                prompt: userPayload,
                systemInstruction: systemPrompt,
                config: aiConfig,
                featureTag: "obsidian_vault_learn",
                preferFast: true
            ) {
                raw += chunk
            }
            var parsed = applyConsolidationJSON(raw, settings: &settings, db: db)
            parsed = ObsidianLearningOutcome(
                usedLLM: parsed.usedLLM,
                upsertedNotesCount: parsed.upsertedNotesCount,
                mergedNotesCount: parsed.mergedNotesCount,
                createdLinksCount: parsed.createdLinksCount,
                appliedSettingsCount: parsed.appliedSettingsCount + localAutopilot.appliedCount,
                summary: parsed.summary
            )
            return parsed
        } catch {
            return ObsidianLearningOutcome(
                usedLLM: false,
                upsertedNotesCount: localSeedCount,
                mergedNotesCount: 0,
                createdLinksCount: db.fetchAllVaultLinks(limit: 200).count,
                appliedSettingsCount: localAutopilot.appliedCount,
                summary: "已更新本地双链基础库（API 深度自学习暂未连通：\(error.localizedDescription)）。"
            )
        }
    }

    /// 纯函数：解析大模型返回的 Obsidian 双链演化 JSON 并落库（100% 可单元测试）
    static func applyConsolidationJSON(
        _ rawText: String,
        settings: inout LingxiSettings,
        db: AICognitiveMemoryDB
    ) -> ObsidianLearningOutcome {
        let cleaned = extractJSONObject(from: rawText)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ObsidianLearningOutcome(
                usedLLM: false,
                upsertedNotesCount: 0,
                mergedNotesCount: 0,
                createdLinksCount: 0,
                appliedSettingsCount: 0,
                summary: "大模型返回格式非标准 JSON，已安全保留现有双链记忆库。"
            )
        }

        if let digest = (obj["persona_digest"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !digest.isEmpty {
            db.setMeta("persona_digest", value: String(digest.prefix(220)))
        }

        var upsertedCount = 0
        var linkCount = 0
        if let rawNotes = obj["notes_to_upsert"] as? [[String: Any]] {
            for item in rawNotes.prefix(8) {
                guard let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty,
                      let body = (item["body_markdown"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !body.isEmpty else { continue }
                let folderStr = (item["folder"] as? String)?.lowercased() ?? "wiki"
                let folder = VaultNoteFolder(rawValue: folderStr) ?? .wiki
                let summary = (item["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? String(body.prefix(48))
                let tags = (item["tags"] as? [String]) ?? []
                var extraLinks: [(String, String)] = []
                if let rawLinks = item["links"] as? [[String: Any]] {
                    for l in rawLinks.prefix(8) {
                        if let to = (l["to"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !to.isEmpty {
                            let rel = (l["relation"] as? String) ?? "related"
                            extraLinks.append((to, rel))
                        }
                    }
                }
                let inlineLinks = parseWikilinks(in: body)
                let safeBody = AIPrivacyShield.sanitize(body).sanitizedText
                let safeSummary = AIPrivacyShield.sanitize(summary).sanitizedText

                let note = ObsidianVaultNote(
                    title: title,
                    folder: folder == .inbox ? .wiki : folder,
                    summary: safeSummary,
                    bodyMarkdown: safeBody,
                    tags: tags,
                    strength: 0.84,
                    source: "ai_llm"
                )
                db.upsertVaultNote(note, extraLinks: extraLinks)
                upsertedCount += 1
                linkCount += Set(inlineLinks.map { AICognitiveMemoryDB.normalizeSlug($0) } + extraLinks.map { AICognitiveMemoryDB.normalizeSlug($0.0) }).count

                // 同步摘要到 learned_memories，兼容旧记忆视图
                db.upsertMemory(CognitiveMemoryFact(
                    category: folder.displayTitle,
                    memoryKey: "vault_\(note.slug)",
                    content: "[\(title)] \(safeSummary)",
                    confidence: 0.90,
                    evidenceCount: 1,
                    source: "ai_llm"
                ))
                db.appendEvolutionLog(
                    action: "distill",
                    noteTitle: title,
                    detail: safeSummary,
                    source: "ai_llm"
                )
            }
        }

        var mergedCount = 0
        if let merges = obj["notes_to_merge"] as? [[String: Any]] {
            for m in merges.prefix(4) {
                guard let keep = (m["keep_title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let drop = (m["drop_title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let body = (m["merged_body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !keep.isEmpty, !drop.isEmpty, !body.isEmpty else { continue }
                let sum = m["merged_summary"] as? String
                if db.mergeVaultNotes(keepSlug: keep, dropSlug: drop, mergedBody: AIPrivacyShield.sanitize(body).sanitizedText, mergedSummary: sum) {
                    mergedCount += 1
                    db.appendEvolutionLog(
                        action: "merge",
                        noteTitle: keep,
                        detail: "吸收合并重复节点 [[\(drop)]] 并重定向反向链接",
                        source: "ai_llm"
                    )
                }
            }
        }

        // 应用安全白名单打字功能变更（完全复用 AIAutopilotController 边界与审计日志）
        var appliedSettings = 0
        if let changes = obj["setting_changes"] as? [[String: Any]] {
            for ch in changes.prefix(12) {
                guard let key = ch["key"] as? String,
                      let targetBool = ch["value"] as? Bool,
                      let curBool = AIAutopilotController.readSettingBool(key, from: settings),
                      curBool != targetBool else { continue }
                let title = AIAutopilotController.settingTitles[key] ?? key
                let reason = (ch["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Obsidian 记忆库自学习建议调优"
                if settings.aiAutopilotMode == .fullAutopilot {
                    if AIAutopilotController.writeSettingBool(key, value: targetBool, into: &settings) {
                        appliedSettings += 1
                        db.insertDecision(AutopilotDecisionRecord(
                            settingKey: key,
                            settingTitle: title,
                            oldValue: curBool ? "开" : "关",
                            newValue: targetBool ? "开" : "关",
                            reason: reason,
                            evidence: "Obsidian API 深度自学习",
                            confidence: 0.93,
                            source: "ai_llm"
                        ))
                        db.appendEvolutionLog(
                            action: "autopilot_tune",
                            noteTitle: title,
                            detail: "\(curBool ? "开" : "关") → \(targetBool ? "开" : "关")：\(reason)",
                            source: "ai_llm"
                        )
                    }
                }
            }
        }

        let nowTs = Int(Date().timeIntervalSince1970)
        db.setMeta("last_obsidian_api_learn_at", value: "\(nowTs)")
        db.setMeta("last_autopilot_run_at", value: "\(nowTs)")

        let rawSummary = (obj["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalSummary = !rawSummary.isEmpty
            ? rawSummary
            : "API 自学习完成：提炼 \(upsertedCount) 篇双链原子笔记、建立 \(linkCount) 条图谱关联、自动调优 \(appliedSettings) 项功能。"

        return ObsidianLearningOutcome(
            usedLLM: true,
            upsertedNotesCount: upsertedCount,
            mergedNotesCount: mergedCount,
            createdLinksCount: linkCount,
            appliedSettingsCount: appliedSettings,
            summary: finalSummary
        )
    }

    /// 被动后台自学习触发器：累计达到 ≥6 次新 AI 采纳交互且距上次 API 提炼 ≥30 分钟时，静默用快模型更新双链记忆库
    static func maybeRunPassiveAPISelfLearning(
        settings: LingxiSettings,
        aiConfig: AIConfig,
        db: AICognitiveMemoryDB = .shared
    ) {
        guard settings.aiAutopilotMode != .off,
              !settings.incognitoModeEnabled,
              aiConfig.isConfigured else { return }

        let nowTs = Int(Date().timeIntervalSince1970)
        let lastLearn = Int(db.getMeta("last_obsidian_api_learn_at") ?? "0") ?? 0
        guard nowTs - lastLearn >= 1800 else { return }

        let totalInter = db.loadStats().interactionCount
        let lastInterAtLearn = Int(db.getMeta("last_obsidian_interaction_count") ?? "0") ?? 0
        guard totalInter - lastInterAtLearn >= 6 else { return }

        db.setMeta("last_obsidian_interaction_count", value: "\(totalInter)")
        Task.detached(priority: .utility) {
            var mutableSettings = settings
            let outcome = await consolidateWithUserAPI(
                settings: &mutableSettings,
                aiConfig: aiConfig,
                db: db
            )
            if outcome.appliedSettingsCount > 0 {
                _ = mutableSettings.save()
            }
        }
    }

    /// 记忆库 ↔ 词库正向回流：将认知学习数据库中高频确认的专属词条同步至本地 `UserLexicon`，
    /// 让用户常打的项目名、专业术语和人名在 26 键/九宫格候选前排自然涌现（严格跳过隐私敏感词）。
    @discardableResult
    static func syncLearnedVocabToUserLexicon(
        _ userLexicon: UserLexicon,
        db: AICognitiveMemoryDB = .shared,
        minLearnCount: Int = 2,
        limit: Int = 40
    ) -> Int {
        let records = db.fetchTopVocab(limit: limit)
        var synced = 0
        for rec in records {
            guard rec.learnCount >= minLearnCount else { continue }
            let cleanWord = rec.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanPy = rec.pinyin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard cleanWord.count >= 2, cleanWord.count <= 8, !cleanPy.isEmpty else { continue }
            guard !ClipboardClassifier.isSensitiveContent(cleanWord),
                  !AIPrivacyShield.sanitize(cleanWord).hasRedactions else { continue }
            if userLexicon.learn(word: cleanWord, py: cleanPy, prevWord: nil) != nil {
                synced += 1
            }
        }
        return synced
    }

    // MARK: - Helpers

    private static func extractSemanticTokens(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        var tokens = Set<String>()
        // ASCII 词（≥2 字符）
        var current = ""
        for scalar in lower.unicodeScalars {
            if (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57) {
                current.append(Character(scalar))
            } else {
                if current.count >= 2 { tokens.insert(current) }
                current = ""
            }
        }
        if current.count >= 2 { tokens.insert(current) }

        // 中文二元组（2-gram），零分词依赖即可实现精准语义匹配
        let cjk = lower.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.map { Character($0) }
        if cjk.count >= 2 {
            for i in 0..<(cjk.count - 1) {
                tokens.insert(String([cjk[i], cjk[i + 1]]))
            }
        }
        return tokens
    }

    private static func extractJSONObject(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else {
            return trimmed
        }
        return String(trimmed[start...end])
    }
}
