import Foundation
import SQLite3

/// SQLite 认知记忆条目（AI 从打字习惯、自学习词库与对话交互中持续沉淀的「懂你」长期记忆）
struct CognitiveMemoryFact: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var category: String
    var memoryKey: String
    var content: String
    var confidence: Double
    var evidenceCount: Int
    var source: String // "local_auto" | "ai_llm" | "user_manual"
    var isPinned: Bool
    var updatedAt: Int

    var sourceDisplayName: String {
        switch source {
        case "ai_llm": return "大模型洞察"
        case "user_manual": return "手动补充"
        default: return "习惯引擎"
        }
    }

    init(
        id: String = UUID().uuidString,
        category: String,
        memoryKey: String,
        content: String,
        confidence: Double = 0.8,
        evidenceCount: Int = 1,
        source: String = "local_auto",
        isPinned: Bool = false,
        updatedAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.category = category
        self.memoryKey = memoryKey
        self.content = content
        self.confidence = min(1.0, max(0.1, confidence))
        self.evidenceCount = max(1, evidenceCount)
        self.source = source
        self.isPinned = isPinned
        self.updatedAt = updatedAt
    }
}

/// AI 自动操控打字功能的单条审计决策记录（支持透明追溯与一键撤回）
struct AutopilotDecisionRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let settingKey: String
    let settingTitle: String
    let oldValue: String
    let newValue: String
    let reason: String
    let evidence: String
    let confidence: Double
    let source: String // "ai_llm" | "local_auto"
    let appliedAt: Int
    var reverted: Bool

    init(
        id: String = UUID().uuidString,
        settingKey: String,
        settingTitle: String,
        oldValue: String,
        newValue: String,
        reason: String,
        evidence: String,
        confidence: Double,
        source: String,
        appliedAt: Int = Int(Date().timeIntervalSince1970),
        reverted: Bool = false
    ) {
        self.id = id
        self.settingKey = settingKey
        self.settingTitle = settingTitle
        self.oldValue = oldValue
        self.newValue = newValue
        self.reason = reason
        self.evidence = evidence
        self.confidence = confidence
        self.source = source
        self.appliedAt = appliedAt
        self.reverted = reverted
    }
}

/// 词汇学习共鸣记录（同步追踪键盘自学习词、领域词频与高频口癖）
struct VocabLearningRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String { word }
    let word: String
    let pinyin: String
    let domain: String
    let learnCount: Int
    let lastUsedAt: Int
}

/// 单次键盘输入习惯采样快照（仅聚合行为指标，不含敏感密码或隐私原文）
struct TypingObservationSample: Sendable {
    var charsCommitted: Int = 0
    var wordsCommitted: Int = 0
    var backspaceCount: Int = 0
    var typoFixHits: Int = 0
    var englishMixWords: Int = 0
    var digitMixCount: Int = 0
    var emojiPickCount: Int = 0
    var bracketPairCount: Int = 0
    var longDraftCount: Int = 0
    var vmodeToolCount: Int = 0
    var glideWordCount: Int = 0
    var traditionalCount: Int = 0
    var fuzzyConfusionKey: String = ""
    var fieldKind: String = "general"

    init(
        charsCommitted: Int = 0,
        wordsCommitted: Int = 0,
        backspaceCount: Int = 0,
        typoFixHits: Int = 0,
        englishMixWords: Int = 0,
        digitMixCount: Int = 0,
        emojiPickCount: Int = 0,
        bracketPairCount: Int = 0,
        longDraftCount: Int = 0,
        vmodeToolCount: Int = 0,
        glideWordCount: Int = 0,
        traditionalCount: Int = 0,
        fuzzyConfusionKey: String = "",
        fieldKind: String = "general"
    ) {
        self.charsCommitted = charsCommitted
        self.wordsCommitted = wordsCommitted
        self.backspaceCount = backspaceCount
        self.typoFixHits = typoFixHits
        self.englishMixWords = englishMixWords
        self.digitMixCount = digitMixCount
        self.emojiPickCount = emojiPickCount
        self.bracketPairCount = bracketPairCount
        self.longDraftCount = longDraftCount
        self.vmodeToolCount = vmodeToolCount
        self.glideWordCount = glideWordCount
        self.traditionalCount = traditionalCount
        self.fuzzyConfusionKey = fuzzyConfusionKey
        self.fieldKind = fieldKind
    }
}

/// Obsidian 风格原子记忆笔记所属目录（对标 Karpathy LLM Wiki / Zettelkasten 5 分区）
enum VaultNoteFolder: String, Codable, CaseIterable, Identifiable, Sendable {
    case index = "index"
    case wiki = "wiki"
    case persona = "persona"
    case habits = "habits"
    case inbox = "inbox"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .index: return "总览索引"
        case .wiki: return "常青知识"
        case .persona: return "人设偏好"
        case .habits: return "打字习惯"
        case .inbox: return "原始收件箱"
        }
    }

    var icon: String {
        switch self {
        case .index: return "map.fill"
        case .wiki: return "doc.text.fill"
        case .persona: return "person.crop.circle.fill"
        case .habits: return "keyboard"
        case .inbox: return "tray.and.arrow.down.fill"
        }
    }
}

/// Obsidian 风格原子记忆笔记（含 YAML Frontmatter 元数据、[[双向链接]] 正文与 Ebbinghaus 记忆强度）
struct ObsidianVaultNote: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let slug: String
    var title: String
    var folder: VaultNoteFolder
    var summary: String
    var bodyMarkdown: String
    var tags: [String]
    var strength: Double
    var recallCount: Int
    var source: String // "ai_llm" | "local_auto" | "user_manual" | "auto_reflect"
    var isPinned: Bool
    let createdAt: Int
    var updatedAt: Int
    var lastRecalledAt: Int

    var sourceDisplayName: String {
        switch source {
        case "ai_llm": return "API 深度提炼"
        case "auto_reflect": return "交互自学习"
        case "user_manual": return "手动笔记"
        default: return "本地习惯引擎"
        }
    }

    init(
        id: String = UUID().uuidString,
        slug: String? = nil,
        title: String,
        folder: VaultNoteFolder = .wiki,
        summary: String,
        bodyMarkdown: String,
        tags: [String] = [],
        strength: Double = 0.72,
        recallCount: Int = 0,
        source: String = "ai_llm",
        isPinned: Bool = false,
        createdAt: Int = Int(Date().timeIntervalSince1970),
        updatedAt: Int = Int(Date().timeIntervalSince1970),
        lastRecalledAt: Int = 0
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.slug = slug ?? AICognitiveMemoryDB.normalizeSlug(cleanTitle)
        self.title = cleanTitle
        self.folder = folder
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bodyMarkdown = bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = tags
        self.strength = min(1.0, max(0.1, strength))
        self.recallCount = max(0, recallCount)
        self.source = source
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRecalledAt = lastRecalledAt
    }
}

/// Obsidian 双向 [[Wikilink]] 知识图谱连边
struct VaultLinkEdge: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(fromSlug)->\(toSlug)" }
    let fromSlug: String
    let toSlug: String
    let relation: String // "related" | "causes" | "prefers" | "part_of" | "resolves"
    let weight: Double
    let updatedAt: Int
}

/// Obsidian `log.md` 追加式 AI 自学习演化日志
struct VaultEvolutionLogEntry: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let createdAt: Int
    let action: String
    let noteTitle: String
    let detail: String
    let source: String

    var actionDisplayName: String {
        switch action {
        case "distill": return "提炼笔记"
        case "link": return "建立双链"
        case "merge": return "融合去重"
        case "strengthen": return "记忆强化"
        case "autopilot_tune": return "功能调优"
        case "user_teach": return "手动录入"
        default: return "记忆演化"
        }
    }
}

/// 本地 SQLite 认知数据库汇总指标（供 UI 展示与 AI 托管决策使用）
struct CognitiveDBStats: Equatable, Sendable {
    let dbFileSizeBytes: Int64
    let totalObservations: Int
    let totalCharsObserved: Int
    let totalWordsObserved: Int
    let totalBackspaces: Int
    let totalTypoFixes: Int
    let totalEnglishWords: Int
    let totalDigitMix: Int
    let totalEmojiPicks: Int
    let totalBracketPairs: Int
    let totalLongDrafts: Int
    let totalVModeUses: Int
    let totalGlideWords: Int
    let memoryCount: Int
    let decisionCount: Int
    let activeDecisionCount: Int
    let vocabCount: Int
    let interactionCount: Int
    let vaultNoteCount: Int
    let vaultLinkCount: Int
    let vaultEvolutionCount: Int
    let fuzzyConfusionCounts: [String: Int]
    let nightSessionRatio: Double
    let lastAutopilotRunAt: Int
    let personaDigest: String

    var backspaceRate: Double {
        guard totalCharsObserved > 0 else { return 0 }
        return Double(totalBackspaces) / Double(max(1, totalCharsObserved))
    }

    var englishMixRatio: Double {
        guard totalWordsObserved > 0 else { return 0 }
        return Double(totalEnglishWords) / Double(max(1, totalWordsObserved))
    }

    var formattedSize: String {
        if dbFileSizeBytes < 1024 { return "\(dbFileSizeBytes) B" }
        let kb = Double(dbFileSizeBytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.2f MB", kb / 1024.0)
    }

    static let empty = CognitiveDBStats(
        dbFileSizeBytes: 0, totalObservations: 0, totalCharsObserved: 0, totalWordsObserved: 0,
        totalBackspaces: 0, totalTypoFixes: 0, totalEnglishWords: 0, totalDigitMix: 0,
        totalEmojiPicks: 0, totalBracketPairs: 0, totalLongDrafts: 0, totalVModeUses: 0,
        totalGlideWords: 0, memoryCount: 0, decisionCount: 0, activeDecisionCount: 0,
        vocabCount: 0, interactionCount: 0, vaultNoteCount: 0, vaultLinkCount: 0, vaultEvolutionCount: 0,
        fuzzyConfusionCounts: [:], nightSessionRatio: 0,
        lastAutopilotRunAt: 0, personaDigest: ""
    )
}

/// 灵犀 AI 专属本地 SQLite 认知学习数据库（`ai_cognitive_memory.sqlite`）。
/// - 主 App 与键盘扩展通过 AppGroup 共享同一份本地加密保护 SQLite 库（WAL + `SQLITE_OPEN_FULLMUTEX` + `NSRecursiveLock`）；
/// - 5 张结构化关系表：`typing_events` / `learned_memories` / `autopilot_decisions` / `vocab_learning_log` / `ai_interaction_episodes` + `autopilot_meta`；
/// - 严格隐私红线：密码框、无痕模式与 L1 敏感形态（银行卡/身份证/密钥/验证码）绝不入库，100% 留存本机。
final class AICognitiveMemoryDB {
    static let shared = AICognitiveMemoryDB(url: AppGroup.fileURL("ai_cognitive_memory.sqlite"))
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let dbURL: URL
    private let lock = NSRecursiveLock()
    private var db: OpaquePointer?

    // 供 AIClient.mergeSystem 热路径 5 秒内存缓存，杜绝每次调用重复查库
    private var cachedPromptBlock: String = ""
    private var cachedPromptBlockAt: CFAbsoluteTime = 0

    init(url: URL) {
        self.dbURL = url
        openAndMigrateIfNeeded()
    }

    deinit {
        lock.lock()
        if let db { sqlite3_close_v2(db) }
        self.db = nil
        lock.unlock()
    }

    var databaseFileName: String {
        dbURL.lastPathComponent
    }

    private func openAndMigrateIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if db != nil { return }

        let dir = dbURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbURL.path, &handle, flags, nil) == SQLITE_OK, let opened = handle else {
            if let handle { sqlite3_close_v2(handle) }
            return
        }
        db = opened
        sqlite3_busy_timeout(opened, 2000)

        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: dbURL.path
        )
        #endif

        execUnsafe("PRAGMA journal_mode=WAL;")
        execUnsafe("PRAGMA synchronous=NORMAL;")

        execUnsafe("""
        CREATE TABLE IF NOT EXISTS typing_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at INTEGER NOT NULL,
            hour_of_day INTEGER NOT NULL,
            chars_committed INTEGER NOT NULL DEFAULT 0,
            words_committed INTEGER NOT NULL DEFAULT 0,
            backspace_count INTEGER NOT NULL DEFAULT 0,
            typo_fix_hits INTEGER NOT NULL DEFAULT 0,
            english_mix_words INTEGER NOT NULL DEFAULT 0,
            digit_mix_count INTEGER NOT NULL DEFAULT 0,
            emoji_pick_count INTEGER NOT NULL DEFAULT 0,
            bracket_pair_count INTEGER NOT NULL DEFAULT 0,
            long_draft_count INTEGER NOT NULL DEFAULT 0,
            vmode_tool_count INTEGER NOT NULL DEFAULT 0,
            glide_word_count INTEGER NOT NULL DEFAULT 0,
            traditional_count INTEGER NOT NULL DEFAULT 0,
            fuzzy_confusion_key TEXT NOT NULL DEFAULT '',
            field_kind TEXT NOT NULL DEFAULT 'general'
        );
        """)
        execUnsafe("CREATE INDEX IF NOT EXISTS idx_typing_events_time ON typing_events(created_at DESC);")

        execUnsafe("""
        CREATE TABLE IF NOT EXISTS learned_memories (
            id TEXT PRIMARY KEY,
            category TEXT NOT NULL,
            memory_key TEXT NOT NULL UNIQUE,
            content TEXT NOT NULL,
            confidence REAL NOT NULL DEFAULT 0.8,
            evidence_count INTEGER NOT NULL DEFAULT 1,
            source TEXT NOT NULL DEFAULT 'local_auto',
            is_pinned INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
        );
        """)

        execUnsafe("""
        CREATE TABLE IF NOT EXISTS autopilot_decisions (
            id TEXT PRIMARY KEY,
            setting_key TEXT NOT NULL,
            setting_title TEXT NOT NULL,
            old_value TEXT NOT NULL,
            new_value TEXT NOT NULL,
            reason TEXT NOT NULL,
            evidence TEXT NOT NULL DEFAULT '',
            confidence REAL NOT NULL DEFAULT 0.85,
            source TEXT NOT NULL DEFAULT 'local_auto',
            applied_at INTEGER NOT NULL,
            reverted INTEGER NOT NULL DEFAULT 0
        );
        """)
        execUnsafe("CREATE INDEX IF NOT EXISTS idx_autopilot_decisions_time ON autopilot_decisions(applied_at DESC);")

        execUnsafe("""
        CREATE TABLE IF NOT EXISTS vocab_learning_log (
            word TEXT PRIMARY KEY,
            pinyin TEXT NOT NULL DEFAULT '',
            domain TEXT NOT NULL DEFAULT '通用',
            learn_count INTEGER NOT NULL DEFAULT 1,
            last_used_at INTEGER NOT NULL
        );
        """)

        execUnsafe("""
        CREATE TABLE IF NOT EXISTS ai_interaction_episodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at INTEGER NOT NULL,
            feature_tag TEXT NOT NULL,
            scene TEXT NOT NULL DEFAULT 'auto',
            user_outcome TEXT NOT NULL DEFAULT 'accepted',
            delta_note TEXT NOT NULL DEFAULT ''
        );
        """)

        execUnsafe("""
        CREATE TABLE IF NOT EXISTS autopilot_meta (
            meta_key TEXT PRIMARY KEY,
            meta_value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        );
        """)

        // Obsidian 风格自学习双链记忆库三表（原子笔记 + 双向 [[Wikilink]] 边 + log.md 演化日志）
        execUnsafe("""
        CREATE TABLE IF NOT EXISTS vault_notes (
            id TEXT PRIMARY KEY,
            slug TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            folder TEXT NOT NULL DEFAULT 'wiki',
            summary TEXT NOT NULL DEFAULT '',
            body_markdown TEXT NOT NULL DEFAULT '',
            tags_csv TEXT NOT NULL DEFAULT '',
            strength REAL NOT NULL DEFAULT 0.72,
            recall_count INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'ai_llm',
            is_pinned INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            last_recalled_at INTEGER NOT NULL DEFAULT 0
        );
        """)
        execUnsafe("CREATE INDEX IF NOT EXISTS idx_vault_notes_folder ON vault_notes(folder, is_pinned DESC, strength DESC);")

        execUnsafe("""
        CREATE TABLE IF NOT EXISTS vault_links (
            from_slug TEXT NOT NULL,
            to_slug TEXT NOT NULL,
            relation TEXT NOT NULL DEFAULT 'related',
            weight REAL NOT NULL DEFAULT 1.0,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (from_slug, to_slug)
        );
        """)
        execUnsafe("CREATE INDEX IF NOT EXISTS idx_vault_links_to ON vault_links(to_slug);")

        execUnsafe("""
        CREATE TABLE IF NOT EXISTS vault_evolution_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at INTEGER NOT NULL,
            action TEXT NOT NULL,
            note_title TEXT NOT NULL,
            detail TEXT NOT NULL,
            source TEXT NOT NULL DEFAULT 'ai_llm'
        );
        """)
    }

    static func normalizeSlug(_ raw: String) -> String {
        let stripped = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let collapsed = stripped.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.lowercased()
    }

    private func execUnsafe(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func invalidatePromptCacheUnsafe() {
        cachedPromptBlockAt = 0
    }

    // MARK: - 1. 写入打字行为观察（隐私安全聚合指标）

    func recordTypingObservation(_ sample: TypingObservationSample, now: Date = Date()) {
        guard sample.charsCommitted > 0 || sample.backspaceCount > 0 || !sample.fuzzyConfusionKey.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }

        let ts = Int(now.timeIntervalSince1970)
        let hour = Calendar.current.component(.hour, from: now)
        let sql = """
        INSERT INTO typing_events (
            created_at, hour_of_day, chars_committed, words_committed, backspace_count,
            typo_fix_hits, english_mix_words, digit_mix_count, emoji_pick_count,
            bracket_pair_count, long_draft_count, vmode_tool_count, glide_word_count,
            traditional_count, fuzzy_confusion_key, field_kind
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(ts))
            sqlite3_bind_int(stmt, 2, Int32(hour))
            sqlite3_bind_int(stmt, 3, Int32(sample.charsCommitted))
            sqlite3_bind_int(stmt, 4, Int32(sample.wordsCommitted))
            sqlite3_bind_int(stmt, 5, Int32(sample.backspaceCount))
            sqlite3_bind_int(stmt, 6, Int32(sample.typoFixHits))
            sqlite3_bind_int(stmt, 7, Int32(sample.englishMixWords))
            sqlite3_bind_int(stmt, 8, Int32(sample.digitMixCount))
            sqlite3_bind_int(stmt, 9, Int32(sample.emojiPickCount))
            sqlite3_bind_int(stmt, 10, Int32(sample.bracketPairCount))
            sqlite3_bind_int(stmt, 11, Int32(sample.longDraftCount))
            sqlite3_bind_int(stmt, 12, Int32(sample.vmodeToolCount))
            sqlite3_bind_int(stmt, 13, Int32(sample.glideWordCount))
            sqlite3_bind_int(stmt, 14, Int32(sample.traditionalCount))
            sqlite3_bind_text(stmt, 15, sample.fuzzyConfusionKey, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 16, sample.fieldKind, -1, Self.sqliteTransient)
            sqlite3_step(stmt)
        }

        // 保留最近 2000 条行为采样，防数据库膨胀
        execUnsafe("DELETE FROM typing_events WHERE id NOT IN (SELECT id FROM typing_events ORDER BY id DESC LIMIT 2000);")
    }

    // MARK: - 2. 写入自学习词汇共鸣与 AI 交互反馈

    func recordVocabLearning(word: String, pinyin: String = "", now: Date = Date()) {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2,
              clean.count <= 16,
              !ClipboardClassifier.isSensitiveContent(clean),
              !AIPrivacyShield.sanitize(clean).hasRedactions,
              clean.contains(where: { !$0.isNumber && !$0.isPunctuation && !$0.isWhitespace }) else { return }
        let domain = inferDomain(for: clean)
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }

        let ts = Int(now.timeIntervalSince1970)
        let sql = """
        INSERT INTO vocab_learning_log (word, pinyin, domain, learn_count, last_used_at)
        VALUES (?, ?, ?, 1, ?)
        ON CONFLICT(word) DO UPDATE SET
            pinyin = CASE WHEN excluded.pinyin != '' THEN excluded.pinyin ELSE vocab_learning_log.pinyin END,
            learn_count = vocab_learning_log.learn_count + 1,
            last_used_at = excluded.last_used_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, clean, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, pinyin, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 3, domain, -1, Self.sqliteTransient)
            sqlite3_bind_int64(stmt, 4, Int64(ts))
            sqlite3_step(stmt)
        }
        invalidatePromptCacheUnsafe()
    }

    func recordAIInteraction(featureTag: String, scene: String, outcome: String, deltaNote: String = "", now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }
        let ts = Int(now.timeIntervalSince1970)
        let sql = "INSERT INTO ai_interaction_episodes (created_at, feature_tag, scene, user_outcome, delta_note) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(ts))
            sqlite3_bind_text(stmt, 2, featureTag, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 3, scene, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 4, outcome, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 5, String(deltaNote.prefix(160)), -1, Self.sqliteTransient)
            sqlite3_step(stmt)
        }
        execUnsafe("DELETE FROM ai_interaction_episodes WHERE id NOT IN (SELECT id FROM ai_interaction_episodes ORDER BY id DESC LIMIT 300);")
    }

    // MARK: - 3. 长期认知记忆 CRUD（learned_memories）

    func upsertMemory(_ fact: CognitiveMemoryFact) {
        let cleanContent = fact.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = fact.memoryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty, !cleanKey.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }

        let sql = """
        INSERT INTO learned_memories (id, category, memory_key, content, confidence, evidence_count, source, is_pinned, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(memory_key) DO UPDATE SET
            category = excluded.category,
            content = excluded.content,
            confidence = MAX(learned_memories.confidence, excluded.confidence),
            evidence_count = learned_memories.evidence_count + excluded.evidence_count,
            source = CASE WHEN learned_memories.source = 'user_manual' THEN 'user_manual' ELSE excluded.source END,
            is_pinned = MAX(learned_memories.is_pinned, excluded.is_pinned),
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, fact.id, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, fact.category, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 3, cleanKey, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 4, cleanContent, -1, Self.sqliteTransient)
            sqlite3_bind_double(stmt, 5, fact.confidence)
            sqlite3_bind_int(stmt, 6, Int32(fact.evidenceCount))
            sqlite3_bind_text(stmt, 7, fact.source, -1, Self.sqliteTransient)
            sqlite3_bind_int(stmt, 8, fact.isPinned ? 1 : 0)
            sqlite3_bind_int64(stmt, 9, Int64(fact.updatedAt))
            sqlite3_step(stmt)
        }
        invalidatePromptCacheUnsafe()
    }

    func fetchMemories(limit: Int = 60) -> [CognitiveMemoryFact] {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return [] }

        let sql = """
        SELECT id, category, memory_key, content, confidence, evidence_count, source, is_pinned, updated_at
        FROM learned_memories
        ORDER BY is_pinned DESC, confidence DESC, updated_at DESC
        LIMIT ?;
        """
        var result: [CognitiveMemoryFact] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(CognitiveMemoryFact(
                    id: colString(stmt, 0),
                    category: colString(stmt, 1),
                    memoryKey: colString(stmt, 2),
                    content: colString(stmt, 3),
                    confidence: sqlite3_column_double(stmt, 4),
                    evidenceCount: Int(sqlite3_column_int(stmt, 5)),
                    source: colString(stmt, 6),
                    isPinned: sqlite3_column_int(stmt, 7) != 0,
                    updatedAt: Int(sqlite3_column_int64(stmt, 8))
                ))
            }
        }
        return result
    }

    func togglePinMemory(id: String) {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE learned_memories SET is_pinned = CASE WHEN is_pinned = 1 THEN 0 ELSE 1 END WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, Self.sqliteTransient)
            sqlite3_step(stmt)
        }
        invalidatePromptCacheUnsafe()
    }

    func deleteMemory(id: String) {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM learned_memories WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, Self.sqliteTransient)
            sqlite3_step(stmt)
        }
        invalidatePromptCacheUnsafe()
    }

    // MARK: - 4. AI 托管决策审计日志 CRUD（autopilot_decisions）

    func insertDecision(_ rec: AutopilotDecisionRecord) {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }
        let sql = """
        INSERT OR REPLACE INTO autopilot_decisions
        (id, setting_key, setting_title, old_value, new_value, reason, evidence, confidence, source, applied_at, reverted)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, rec.id, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, rec.settingKey, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 3, rec.settingTitle, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 4, rec.oldValue, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 5, rec.newValue, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 6, rec.reason, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 7, rec.evidence, -1, Self.sqliteTransient)
            sqlite3_bind_double(stmt, 8, rec.confidence)
            sqlite3_bind_text(stmt, 9, rec.source, -1, Self.sqliteTransient)
            sqlite3_bind_int64(stmt, 10, Int64(rec.appliedAt))
            sqlite3_bind_int(stmt, 11, rec.reverted ? 1 : 0)
            sqlite3_step(stmt)
        }
        execUnsafe("DELETE FROM autopilot_decisions WHERE id NOT IN (SELECT id FROM autopilot_decisions ORDER BY applied_at DESC LIMIT 120);")
    }

    func fetchDecisions(limit: Int = 50) -> [AutopilotDecisionRecord] {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return [] }
        let sql = """
        SELECT id, setting_key, setting_title, old_value, new_value, reason, evidence, confidence, source, applied_at, reverted
        FROM autopilot_decisions
        ORDER BY applied_at DESC
        LIMIT ?;
        """
        var list: [AutopilotDecisionRecord] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                list.append(AutopilotDecisionRecord(
                    id: colString(stmt, 0),
                    settingKey: colString(stmt, 1),
                    settingTitle: colString(stmt, 2),
                    oldValue: colString(stmt, 3),
                    newValue: colString(stmt, 4),
                    reason: colString(stmt, 5),
                    evidence: colString(stmt, 6),
                    confidence: sqlite3_column_double(stmt, 7),
                    source: colString(stmt, 8),
                    appliedAt: Int(sqlite3_column_int64(stmt, 9)),
                    reverted: sqlite3_column_int(stmt, 10) != 0
                ))
            }
        }
        return list
    }

    func markDecisionReverted(id: String) {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE autopilot_decisions SET reverted = 1 WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, Self.sqliteTransient)
            sqlite3_step(stmt)
        }
    }

    func fetchTopVocab(limit: Int = 30) -> [VocabLearningRecord] {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return [] }
        let sql = "SELECT word, pinyin, domain, learn_count, last_used_at FROM vocab_learning_log ORDER BY learn_count DESC, last_used_at DESC LIMIT ?;"
        var out: [VocabLearningRecord] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(VocabLearningRecord(
                    word: colString(stmt, 0),
                    pinyin: colString(stmt, 1),
                    domain: colString(stmt, 2),
                    learnCount: Int(sqlite3_column_int(stmt, 3)),
                    lastUsedAt: Int(sqlite3_column_int64(stmt, 4))
                ))
            }
        }
        return out
    }

    // MARK: - 5. Meta & 统计与 Prompt 上下文注入

    func setMeta(_ key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }
        let sql = "INSERT OR REPLACE INTO autopilot_meta (meta_key, meta_value, updated_at) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, key, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, value, -1, Self.sqliteTransient)
            sqlite3_bind_int64(stmt, 3, Int64(Date().timeIntervalSince1970))
            sqlite3_step(stmt)
        }
        if key == "persona_digest" {
            invalidatePromptCacheUnsafe()
        }
    }

    func getMeta(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return nil }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT meta_value FROM autopilot_meta WHERE meta_key = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, key, -1, Self.sqliteTransient)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return colString(stmt, 0)
            }
        }
        return nil
    }

    func loadStats() -> CognitiveDBStats {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return .empty }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: dbURL.path)[.size] as? NSNumber)?.int64Value ?? 0

        var obsCount = 0, chars = 0, words = 0, backs = 0, typos = 0, eng = 0, digs = 0
        var emojis = 0, pairs = 0, drafts = 0, vmodes = 0, glides = 0, nightObs = 0
        let aggSQL = """
        SELECT COUNT(*), COALESCE(SUM(chars_committed),0), COALESCE(SUM(words_committed),0),
               COALESCE(SUM(backspace_count),0), COALESCE(SUM(typo_fix_hits),0),
               COALESCE(SUM(english_mix_words),0), COALESCE(SUM(digit_mix_count),0),
               COALESCE(SUM(emoji_pick_count),0), COALESCE(SUM(bracket_pair_count),0),
               COALESCE(SUM(long_draft_count),0), COALESCE(SUM(vmode_tool_count),0),
               COALESCE(SUM(glide_word_count),0),
               COALESCE(SUM(CASE WHEN hour_of_day >= 22 OR hour_of_day <= 5 THEN 1 ELSE 0 END), 0)
        FROM typing_events;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, aggSQL, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                obsCount = Int(sqlite3_column_int(stmt, 0))
                chars = Int(sqlite3_column_int(stmt, 1))
                words = Int(sqlite3_column_int(stmt, 2))
                backs = Int(sqlite3_column_int(stmt, 3))
                typos = Int(sqlite3_column_int(stmt, 4))
                eng = Int(sqlite3_column_int(stmt, 5))
                digs = Int(sqlite3_column_int(stmt, 6))
                emojis = Int(sqlite3_column_int(stmt, 7))
                pairs = Int(sqlite3_column_int(stmt, 8))
                drafts = Int(sqlite3_column_int(stmt, 9))
                vmodes = Int(sqlite3_column_int(stmt, 10))
                glides = Int(sqlite3_column_int(stmt, 11))
                nightObs = Int(sqlite3_column_int(stmt, 12))
            }
        }

        var confMap: [String: Int] = [:]
        var cStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT fuzzy_confusion_key, COUNT(*) FROM typing_events WHERE fuzzy_confusion_key != '' GROUP BY fuzzy_confusion_key;", -1, &cStmt, nil) == SQLITE_OK, let cStmt {
            defer { sqlite3_finalize(cStmt) }
            while sqlite3_step(cStmt) == SQLITE_ROW {
                let k = colString(cStmt, 0)
                if !k.isEmpty { confMap[k] = Int(sqlite3_column_int(cStmt, 1)) }
            }
        }

        let memCount = scalarCountUnsafe("SELECT COUNT(*) FROM learned_memories;")
        let decCount = scalarCountUnsafe("SELECT COUNT(*) FROM autopilot_decisions;")
        let activeDecCount = scalarCountUnsafe("SELECT COUNT(*) FROM autopilot_decisions WHERE reverted = 0;")
        let vocCount = scalarCountUnsafe("SELECT COUNT(*) FROM vocab_learning_log;")
        let interCount = scalarCountUnsafe("SELECT COUNT(*) FROM ai_interaction_episodes;")
        let noteCount = scalarCountUnsafe("SELECT COUNT(*) FROM vault_notes;")
        let linkCount = scalarCountUnsafe("SELECT COUNT(*) FROM vault_links;")
        let evoCount = scalarCountUnsafe("SELECT COUNT(*) FROM vault_evolution_log;")
        let lastRun = Int(getMeta("last_autopilot_run_at") ?? "0") ?? 0
        let digest = getMeta("persona_digest") ?? ""
        let nightRatio = obsCount > 0 ? Double(nightObs) / Double(obsCount) : 0

        return CognitiveDBStats(
            dbFileSizeBytes: fileSize,
            totalObservations: obsCount,
            totalCharsObserved: chars,
            totalWordsObserved: words,
            totalBackspaces: backs,
            totalTypoFixes: typos,
            totalEnglishWords: eng,
            totalDigitMix: digs,
            totalEmojiPicks: emojis,
            totalBracketPairs: pairs,
            totalLongDrafts: drafts,
            totalVModeUses: vmodes,
            totalGlideWords: glides,
            memoryCount: memCount,
            decisionCount: decCount,
            activeDecisionCount: activeDecCount,
            vocabCount: vocCount,
            interactionCount: interCount,
            vaultNoteCount: noteCount,
            vaultLinkCount: linkCount,
            vaultEvolutionCount: evoCount,
            fuzzyConfusionCounts: confMap,
            nightSessionRatio: nightRatio,
            lastAutopilotRunAt: lastRun,
            personaDigest: digest
        )
    }

    /// 供 `AIClient.mergeSystem` 零阻塞注入的长期认知记忆块（5 秒热缓存）
    func promptContextBlock(limit: Int = 8) -> String {
        lock.lock()
        defer { lock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        if now - cachedPromptBlockAt < 5.0 {
            return cachedPromptBlock
        }
        let digest = (getMeta("persona_digest") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let memories = fetchMemories(limit: limit)
        let topVocab = fetchTopVocab(limit: 8).map(\.word)

        var lines: [String] = []
        if !digest.isEmpty {
            lines.append("用户核心画像：\(digest)")
        }
        for mem in memories {
            lines.append("- [\(mem.category)] \(mem.content)")
        }
        if !topVocab.isEmpty {
            lines.append("用户高频自用词汇：\(topVocab.joined(separator: "、"))")
        }
        let block = lines.isEmpty ? "" : lines.joined(separator: "\n")
        cachedPromptBlock = block
        cachedPromptBlockAt = now
        return block
    }

    /// 导出完整认知数据库与 Obsidian 双链记忆库为可读 JSON（不含任何敏感密码/密钥）
    func exportJSONSummary() -> Data? {
        struct ExportSnapshot: Codable {
            let exportedAt: Int
            let personaDigest: String
            let memories: [CognitiveMemoryFact]
            let decisions: [AutopilotDecisionRecord]
            let topVocab: [VocabLearningRecord]
            let vaultNotes: [ObsidianVaultNote]
            let vaultLinks: [VaultLinkEdge]
            let evolutionLogs: [VaultEvolutionLogEntry]
        }
        let stats = loadStats()
        let snap = ExportSnapshot(
            exportedAt: Int(Date().timeIntervalSince1970),
            personaDigest: stats.personaDigest,
            memories: fetchMemories(limit: 120),
            decisions: fetchDecisions(limit: 100),
            topVocab: fetchTopVocab(limit: 80),
            vaultNotes: fetchVaultNotes(limit: 160),
            vaultLinks: fetchAllVaultLinks(limit: 400),
            evolutionLogs: fetchEvolutionLogs(limit: 80)
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(snap)
    }

    // MARK: - 6. Obsidian 双链知识图谱记忆库 CRUD（vault_notes / vault_links / vault_evolution_log）

    func upsertVaultNote(_ note: ObsidianVaultNote, extraLinks: [(toTitle: String, relation: String)] = []) {
        let cleanTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSlug = Self.normalizeSlug(note.slug.isEmpty ? cleanTitle : note.slug)
        guard !cleanTitle.isEmpty, !cleanSlug.isEmpty else { return }

        // 自动融合正文中的 #标签 与显式 tags
        let inlineTags = ObsidianMemoryVaultEngine.parseHashtags(in: note.bodyMarkdown)
        var mergedTags: [String] = []
        var seenTags = Set<String>()
        for t in (note.tags + inlineTags) {
            let cleaned = t.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
            if !cleaned.isEmpty, seenTags.insert(cleaned).inserted {
                mergedTags.append(cleaned)
            }
        }
        let tagsCSV = mergedTags.prefix(10).joined(separator: ",")
        let nowTs = Int(Date().timeIntervalSince1970)

        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }

        let sql = """
        INSERT INTO vault_notes (
            id, slug, title, folder, summary, body_markdown, tags_csv,
            strength, recall_count, source, is_pinned, created_at, updated_at, last_recalled_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(slug) DO UPDATE SET
            title = excluded.title,
            folder = excluded.folder,
            summary = CASE WHEN excluded.summary != '' THEN excluded.summary ELSE vault_notes.summary END,
            body_markdown = excluded.body_markdown,
            tags_csv = excluded.tags_csv,
            strength = MIN(1.0, MAX(vault_notes.strength, excluded.strength) + 0.04),
            source = CASE WHEN vault_notes.source = 'user_manual' AND excluded.source != 'user_manual' THEN 'user_manual' ELSE excluded.source END,
            is_pinned = MAX(vault_notes.is_pinned, excluded.is_pinned),
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, note.id, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, cleanSlug, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 3, cleanTitle, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 4, note.folder.rawValue, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 5, note.summary, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 6, note.bodyMarkdown, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 7, tagsCSV, -1, Self.sqliteTransient)
            sqlite3_bind_double(stmt, 8, note.strength)
            sqlite3_bind_int(stmt, 9, Int32(note.recallCount))
            sqlite3_bind_text(stmt, 10, note.source, -1, Self.sqliteTransient)
            sqlite3_bind_int(stmt, 11, note.isPinned ? 1 : 0)
            sqlite3_bind_int64(stmt, 12, Int64(note.createdAt))
            sqlite3_bind_int64(stmt, 13, Int64(nowTs))
            sqlite3_bind_int64(stmt, 14, Int64(note.lastRecalledAt))
            sqlite3_step(stmt)
        }

        // 重建此笔记的出链边（自动解析正文中的 [[wikilink]] + 显式关联边）
        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM vault_links WHERE from_slug = ?;", -1, &delStmt, nil) == SQLITE_OK, let delStmt {
            defer { sqlite3_finalize(delStmt) }
            sqlite3_bind_text(delStmt, 1, cleanSlug, -1, Self.sqliteTransient)
            sqlite3_step(delStmt)
        }

        var edgeMap: [String: (relation: String, weight: Double)] = [:]
        for rawTarget in ObsidianMemoryVaultEngine.parseWikilinks(in: note.bodyMarkdown) {
            let tSlug = Self.normalizeSlug(rawTarget)
            if !tSlug.isEmpty && tSlug != cleanSlug {
                edgeMap[tSlug] = ("related", 1.0)
            }
        }
        for extra in extraLinks {
            let tSlug = Self.normalizeSlug(extra.toTitle)
            if !tSlug.isEmpty && tSlug != cleanSlug {
                let rel = extra.relation.trimmingCharacters(in: .whitespacesAndNewlines)
                edgeMap[tSlug] = (rel.isEmpty ? "related" : rel, 1.15)
            }
        }
        let linkSQL = "INSERT OR REPLACE INTO vault_links (from_slug, to_slug, relation, weight, updated_at) VALUES (?, ?, ?, ?, ?);"
        for (toSlug, info) in edgeMap {
            var lStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, linkSQL, -1, &lStmt, nil) == SQLITE_OK, let lStmt {
                defer { sqlite3_finalize(lStmt) }
                sqlite3_bind_text(lStmt, 1, cleanSlug, -1, Self.sqliteTransient)
                sqlite3_bind_text(lStmt, 2, toSlug, -1, Self.sqliteTransient)
                sqlite3_bind_text(lStmt, 3, info.relation, -1, Self.sqliteTransient)
                sqlite3_bind_double(lStmt, 4, info.weight)
                sqlite3_bind_int64(lStmt, 5, Int64(nowTs))
                sqlite3_step(lStmt)
            }
        }
        invalidatePromptCacheUnsafe()
    }

    func fetchVaultNotes(folder: VaultNoteFolder? = nil, query: String = "", limit: Int = 120) -> [ObsidianVaultNote] {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return [] }

        let sql: String
        if folder != nil {
            sql = """
            SELECT id, slug, title, folder, summary, body_markdown, tags_csv, strength, recall_count, source, is_pinned, created_at, updated_at, last_recalled_at
            FROM vault_notes
            WHERE folder = ?
            ORDER BY is_pinned DESC, strength DESC, updated_at DESC
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT id, slug, title, folder, summary, body_markdown, tags_csv, strength, recall_count, source, is_pinned, created_at, updated_at, last_recalled_at
            FROM vault_notes
            ORDER BY is_pinned DESC, strength DESC, updated_at DESC
            LIMIT ?;
            """
        }

        var notes: [ObsidianVaultNote] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            if let folder {
                sqlite3_bind_text(stmt, 1, folder.rawValue, -1, Self.sqliteTransient)
                sqlite3_bind_int(stmt, 2, Int32(limit))
            } else {
                sqlite3_bind_int(stmt, 1, Int32(limit))
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                notes.append(readVaultNoteRow(stmt))
            }
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return notes }
        return notes.filter { n in
            n.title.lowercased().contains(q)
                || n.summary.lowercased().contains(q)
                || n.bodyMarkdown.lowercased().contains(q)
                || n.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }

    func fetchVaultNote(slug: String) -> ObsidianVaultNote? {
        let key = Self.normalizeSlug(slug)
        guard !key.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return nil }
        let sql = """
        SELECT id, slug, title, folder, summary, body_markdown, tags_csv, strength, recall_count, source, is_pinned, created_at, updated_at, last_recalled_at
        FROM vault_notes WHERE slug = ? LIMIT 1;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, key, -1, Self.sqliteTransient)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return readVaultNoteRow(stmt)
            }
        }
        return nil
    }

    func fetchAllVaultLinks(limit: Int = 400) -> [VaultLinkEdge] {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return [] }
        var out: [VaultLinkEdge] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT from_slug, to_slug, relation, weight, updated_at FROM vault_links ORDER BY weight DESC, updated_at DESC LIMIT ?;", -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(VaultLinkEdge(
                    fromSlug: colString(stmt, 0),
                    toSlug: colString(stmt, 1),
                    relation: colString(stmt, 2),
                    weight: sqlite3_column_double(stmt, 3),
                    updatedAt: Int(sqlite3_column_int64(stmt, 4))
                ))
            }
        }
        return out
    }

    func fetchOutlinks(forSlug slug: String) -> [VaultLinkEdge] {
        let key = Self.normalizeSlug(slug)
        return fetchAllVaultLinks(limit: 400).filter { $0.fromSlug == key }
    }

    func fetchBacklinks(forSlug slug: String) -> [VaultLinkEdge] {
        let key = Self.normalizeSlug(slug)
        return fetchAllVaultLinks(limit: 400).filter { $0.toSlug == key }
    }

    /// A-MEM / Ebbinghaus 记忆强化：每次被 Graph-RAG 召回命中后提升回忆次数与稳定度
    func reinforceVaultNotes(slugs: [String], boost: Double = 0.03) {
        guard !slugs.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }
        let nowTs = Int(Date().timeIntervalSince1970)
        let sql = "UPDATE vault_notes SET recall_count = recall_count + 1, strength = MIN(1.0, strength + ?), last_recalled_at = ? WHERE slug = ?;"
        for raw in slugs {
            let key = Self.normalizeSlug(raw)
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_double(stmt, 1, boost)
                sqlite3_bind_int64(stmt, 2, Int64(nowTs))
                sqlite3_bind_text(stmt, 3, key, -1, Self.sqliteTransient)
                sqlite3_step(stmt)
            }
        }
    }

    func togglePinVaultNote(slug: String) {
        let key = Self.normalizeSlug(slug)
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE vault_notes SET is_pinned = CASE WHEN is_pinned = 1 THEN 0 ELSE 1 END WHERE slug = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, key, -1, Self.sqliteTransient)
            sqlite3_step(stmt)
        }
        invalidatePromptCacheUnsafe()
    }

    func deleteVaultNote(slug: String) {
        let key = Self.normalizeSlug(slug)
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }
        for sql in [
            "DELETE FROM vault_notes WHERE slug = ?;",
            "DELETE FROM vault_links WHERE from_slug = ? OR to_slug = ?;"
        ] {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, key, -1, Self.sqliteTransient)
                if sql.contains("OR") {
                    sqlite3_bind_text(stmt, 2, key, -1, Self.sqliteTransient)
                }
                sqlite3_step(stmt)
            }
        }
        invalidatePromptCacheUnsafe()
    }

    /// 合并两条重复原子笔记并无损重定向全部反向链接
    @discardableResult
    func mergeVaultNotes(keepSlug: String, dropSlug: String, mergedBody: String, mergedSummary: String? = nil) -> Bool {
        let keepKey = Self.normalizeSlug(keepSlug)
        let dropKey = Self.normalizeSlug(dropSlug)
        guard !keepKey.isEmpty, !dropKey.isEmpty, keepKey != dropKey,
              var keepNote = fetchVaultNote(slug: keepKey) else { return false }
        keepNote.bodyMarkdown = mergedBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = mergedSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            keepNote.summary = s
        }
        keepNote.strength = min(1.0, keepNote.strength + 0.08)
        upsertVaultNote(keepNote)

        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        if let db {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE OR IGNORE vault_links SET to_slug = ? WHERE to_slug = ? AND from_slug != ?;", -1, &stmt, nil) == SQLITE_OK, let stmt {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, keepKey, -1, Self.sqliteTransient)
                sqlite3_bind_text(stmt, 2, dropKey, -1, Self.sqliteTransient)
                sqlite3_bind_text(stmt, 3, keepKey, -1, Self.sqliteTransient)
                sqlite3_step(stmt)
            }
        }
        deleteVaultNote(slug: dropKey)
        return true
    }

    func appendEvolutionLog(action: String, noteTitle: String, detail: String, source: String = "ai_llm") {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return }
        let nowTs = Int(Date().timeIntervalSince1970)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "INSERT INTO vault_evolution_log (created_at, action, note_title, detail, source) VALUES (?, ?, ?, ?, ?);", -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(nowTs))
            sqlite3_bind_text(stmt, 2, action, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 3, String(noteTitle.prefix(60)), -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 4, String(detail.prefix(220)), -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 5, source, -1, Self.sqliteTransient)
            sqlite3_step(stmt)
        }
        execUnsafe("DELETE FROM vault_evolution_log WHERE id NOT IN (SELECT id FROM vault_evolution_log ORDER BY id DESC LIMIT 150);")
    }

    func fetchEvolutionLogs(limit: Int = 50) -> [VaultEvolutionLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return [] }
        var out: [VaultEvolutionLogEntry] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id, created_at, action, note_title, detail, source FROM vault_evolution_log ORDER BY id DESC LIMIT ?;", -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(VaultEvolutionLogEntry(
                    id: Int(sqlite3_column_int(stmt, 0)),
                    createdAt: Int(sqlite3_column_int64(stmt, 1)),
                    action: colString(stmt, 2),
                    noteTitle: colString(stmt, 3),
                    detail: colString(stmt, 4),
                    source: colString(stmt, 5)
                ))
            }
        }
        return out
    }

    func fetchRecentInteractions(limit: Int = 20) -> [(createdAt: Int, featureTag: String, scene: String, outcome: String, deltaNote: String)] {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        guard let db else { return [] }
        var out: [(Int, String, String, String, String)] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT created_at, feature_tag, scene, user_outcome, delta_note FROM ai_interaction_episodes ORDER BY id DESC LIMIT ?;", -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append((
                    Int(sqlite3_column_int64(stmt, 0)),
                    colString(stmt, 1),
                    colString(stmt, 2),
                    colString(stmt, 3),
                    colString(stmt, 4)
                ))
            }
        }
        return out
    }

    private func readVaultNoteRow(_ stmt: OpaquePointer) -> ObsidianVaultNote {
        let folderRaw = colString(stmt, 3)
        let tagsCSV = colString(stmt, 6)
        let tags = tagsCSV.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return ObsidianVaultNote(
            id: colString(stmt, 0),
            slug: colString(stmt, 1),
            title: colString(stmt, 2),
            folder: VaultNoteFolder(rawValue: folderRaw) ?? .wiki,
            summary: colString(stmt, 4),
            bodyMarkdown: colString(stmt, 5),
            tags: tags,
            strength: sqlite3_column_double(stmt, 7),
            recallCount: Int(sqlite3_column_int(stmt, 8)),
            source: colString(stmt, 9),
            isPinned: sqlite3_column_int(stmt, 10) != 0,
            createdAt: Int(sqlite3_column_int64(stmt, 11)),
            updatedAt: Int(sqlite3_column_int64(stmt, 12)),
            lastRecalledAt: Int(sqlite3_column_int64(stmt, 13))
        )
    }

    func clearAllData() {
        lock.lock()
        defer { lock.unlock() }
        openAndMigrateIfNeeded()
        execUnsafe("DELETE FROM typing_events;")
        execUnsafe("DELETE FROM learned_memories;")
        execUnsafe("DELETE FROM autopilot_decisions;")
        execUnsafe("DELETE FROM vocab_learning_log;")
        execUnsafe("DELETE FROM ai_interaction_episodes;")
        execUnsafe("DELETE FROM autopilot_meta;")
        execUnsafe("DELETE FROM vault_notes;")
        execUnsafe("DELETE FROM vault_links;")
        execUnsafe("DELETE FROM vault_evolution_log;")
        execUnsafe("PRAGMA wal_checkpoint(TRUNCATE);")
        invalidatePromptCacheUnsafe()
    }

    // MARK: - Private Helpers

    private func scalarCountUnsafe(_ sql: String) -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
        }
        return 0
    }

    private func colString(_ stmt: OpaquePointer, _ idx: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: cstr)
    }

    private func inferDomain(for word: String) -> String {
        let lower = word.lowercased()
        let techKeys = ["代码", "接口", "上线", "发版", "测试", "数据库", "算法", "模型", "框架", "api", "swift", "python", "git", "bug", "sql", "ai"]
        if techKeys.contains(where: { lower.contains($0) }) { return "研发技术" }
        let bizKeys = ["需求", "排期", "复盘", "周报", "汇报", "审批", "合同", "报价", "开票", "客户", "预算", "方案"]
        if bizKeys.contains(where: { lower.contains($0) }) { return "职场商务" }
        let lifeKeys = ["快递", "外卖", "火锅", "奶茶", "租房", "押金", "医院", "体检", "旅游", "机票", "高铁", "生日"]
        if lifeKeys.contains(where: { lower.contains($0) }) { return "日常生活" }
        return "通用表达"
    }
}
