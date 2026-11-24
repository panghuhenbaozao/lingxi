import Foundation
import SQLite3

/// 用户个人词条（自造词、调频与置顶）。
struct UserWordEntry: Identifiable, Equatable {
    var id: String { "\(word)|\(py)" }
    let word: String
    let py: String
    let abbr: String
    let freq: Int
    let lastUsed: TimeInterval
    let isPinned: Bool
}

/// 单次学习凭证，供「选错立即退格（⌫）」精准撤销误学词条与误学二元搭配（对齐 WowType undoLearn）。
struct UserLearnRecord: Equatable {
    let word: String
    let py: String
    let prevWord: String?
}

/// 基于 App Group 共享 SQLite 的用户词库与二元上下文联想存储。
final class UserLexicon {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let dbFileName = "user_dict.sqlite"

    private var db: OpaquePointer?
    private var singleAbbrStmt: OpaquePointer?
    private var singleT9Stmt: OpaquePointer?
    private var predictNextStmt: OpaquePointer?
    private let queue = DispatchQueue(label: "com.lingxi.userlexicon", qos: .userInitiated)

    init() {
        openDatabase()
    }

    deinit {
        if let singleAbbrStmt { sqlite3_finalize(singleAbbrStmt) }
        if let singleT9Stmt { sqlite3_finalize(singleT9Stmt) }
        if let predictNextStmt { sqlite3_finalize(predictNextStmt) }
        if let db {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        let url = AppGroup.fileURL(Self.dbFileName)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return
        }
        sqlite3_busy_timeout(handle, 150)
        self.db = handle

        let schema = """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        CREATE TABLE IF NOT EXISTS user_words (
            word      TEXT    NOT NULL,
            py        TEXT    NOT NULL,
            abbr      TEXT    NOT NULL,
            t9_abbr   TEXT    NOT NULL DEFAULT '',
            len       INTEGER NOT NULL,
            freq      INTEGER NOT NULL DEFAULT 1,
            last_used REAL    NOT NULL,
            pinned    INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (word, py)
        );
        CREATE INDEX IF NOT EXISTS idx_uw_abbr ON user_words (abbr, pinned DESC, freq DESC);
        CREATE INDEX IF NOT EXISTS idx_uw_t9   ON user_words (t9_abbr, pinned DESC, freq DESC);
        CREATE INDEX IF NOT EXISTS idx_uw_py   ON user_words (py, pinned DESC, freq DESC);
        CREATE TABLE IF NOT EXISTS bigrams (
            prev_word TEXT    NOT NULL,
            next_word TEXT    NOT NULL,
            freq      INTEGER NOT NULL DEFAULT 1,
            last_used REAL    NOT NULL,
            PRIMARY KEY (prev_word, next_word)
        );
        CREATE INDEX IF NOT EXISTS idx_bg_prev ON bigrams (prev_word, freq DESC, last_used DESC);
        """
        sqlite3_exec(handle, schema, nil, nil, nil)
        // 兼容旧库迁移
        sqlite3_exec(handle, "ALTER TABLE user_words ADD COLUMN t9_abbr TEXT NOT NULL DEFAULT '';", nil, nil, nil)
        sqlite3_exec(handle, "CREATE INDEX IF NOT EXISTS idx_uw_t9 ON user_words (t9_abbr, pinned DESC, freq DESC);", nil, nil, nil)

        // 预编译高频热路径 SQL 语句，避免每次按键都触发 SQLite 解析与查询规划
        sqlite3_prepare_v2(
            handle,
            "SELECT word, py, freq, last_used, pinned FROM user_words WHERE abbr = ? AND (pinned = 1 OR freq >= ?) ORDER BY pinned DESC, last_used DESC, freq DESC LIMIT ?",
            -1,
            &singleAbbrStmt,
            nil
        )
        sqlite3_prepare_v2(
            handle,
            "SELECT word, py, freq, last_used, pinned FROM user_words WHERE t9_abbr = ? AND (pinned = 1 OR freq >= ?) ORDER BY pinned DESC, last_used DESC, freq DESC LIMIT ?",
            -1,
            &singleT9Stmt,
            nil
        )
        sqlite3_prepare_v2(
            handle,
            "SELECT next_word FROM bigrams WHERE prev_word = ? ORDER BY freq DESC, last_used DESC LIMIT ?",
            -1,
            &predictNextStmt,
            nil
        )
    }

    private static func toT9Digits(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.lowercased() {
            switch ch {
            case "a", "b", "c": out.append("2")
            case "d", "e", "f": out.append("3")
            case "g", "h", "i": out.append("4")
            case "j", "k", "l": out.append("5")
            case "m", "n", "o": out.append("6")
            case "p", "q", "r", "s": out.append("7")
            case "t", "u", "v": out.append("8")
            case "w", "x", "y", "z": out.append("9")
            default: break
            }
        }
        return out
    }

    /// 30 天半衰期时间衰减：长期不用的词权重自然回落，贴合近期表达习惯。
    static func decayedFrequency(_ freq: Int, lastUsed: TimeInterval, now: TimeInterval) -> Double {
        let ageDays = max(0.0, (now - lastUsed) / 86400.0)
        return max(0.15, Double(max(1, freq)) * exp(-ageDays * log(2.0) / 30.0))
    }

    /// 按首字母缩写查询用户词库（同步高速读取，单缩写复用预编译 stmt 零解析开销）。
    func lookup(abbrList: [String], isT9: Bool = false, minFrequency: Int = 1, limit: Int = 200) -> [(word: String, py: String, boost: Double)] {
        guard !abbrList.isEmpty else { return [] }
        let now = Date().timeIntervalSince1970
        let threshold = max(1, minFrequency)
        return queue.sync {
            guard let db else { return [] }
            if abbrList.count == 1, let cachedStmt = (isT9 ? singleT9Stmt : singleAbbrStmt) {
                sqlite3_reset(cachedStmt)
                sqlite3_clear_bindings(cachedStmt)
                sqlite3_bind_text(cachedStmt, 1, abbrList[0], -1, Self.sqliteTransient)
                sqlite3_bind_int(cachedStmt, 2, Int32(threshold))
                sqlite3_bind_int(cachedStmt, 3, Int32(limit))

                var out: [(String, String, Double)] = []
                while sqlite3_step(cachedStmt) == SQLITE_ROW {
                    guard let wPtr = sqlite3_column_text(cachedStmt, 0),
                          let pPtr = sqlite3_column_text(cachedStmt, 1) else { continue }
                    let word = String(cString: wPtr)
                    let py = String(cString: pPtr)
                    let freq = Int(sqlite3_column_int(cachedStmt, 2))
                    let lastUsed = sqlite3_column_double(cachedStmt, 3)
                    let pinned = sqlite3_column_int(cachedStmt, 4) != 0
                    let eff = Self.decayedFrequency(freq, lastUsed: lastUsed, now: now)
                    let boost = (pinned ? 24.0 : 0.0) + min(7.0, 1.8 + log(max(1.0, eff)) * 1.15)
                    out.append((word, py, boost))
                }
                sqlite3_reset(cachedStmt)
                return out
            }

            let col = isT9 ? "t9_abbr" : "abbr"
            let placeholders = Array(repeating: "?", count: abbrList.count).joined(separator: ",")
            let sql = """
            SELECT word, py, freq, last_used, pinned
            FROM user_words
            WHERE \(col) IN (\(placeholders)) AND (pinned = 1 OR freq >= ?)
            ORDER BY pinned DESC, last_used DESC, freq DESC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                return []
            }
            defer { sqlite3_finalize(stmt) }

            for (idx, abbr) in abbrList.enumerated() {
                sqlite3_bind_text(stmt, Int32(idx + 1), abbr, -1, Self.sqliteTransient)
            }
            sqlite3_bind_int(stmt, Int32(abbrList.count + 1), Int32(threshold))
            sqlite3_bind_int(stmt, Int32(abbrList.count + 2), Int32(limit))

            var out: [(String, String, Double)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let wPtr = sqlite3_column_text(stmt, 0),
                      let pPtr = sqlite3_column_text(stmt, 1) else { continue }
                let word = String(cString: wPtr)
                let py = String(cString: pPtr)
                let freq = Int(sqlite3_column_int(stmt, 2))
                let lastUsed = sqlite3_column_double(stmt, 3)
                let pinned = sqlite3_column_int(stmt, 4) != 0
                let eff = Self.decayedFrequency(freq, lastUsed: lastUsed, now: now)
                let boost = (pinned ? 24.0 : 0.0) + min(7.0, 1.8 + log(max(1.0, eff)) * 1.15)
                out.append((word, py, boost))
            }
            return out
        }
    }

    /// 学习一次上屏选择（包含自造词合并），返回可供退格重选撤回的凭证。
    @discardableResult
    func learn(word: String, py: String, prevWord: String? = nil) -> UserLearnRecord? {
        let syllables = py.split(separator: "'").map(String.init)
        guard !word.isEmpty, !syllables.isEmpty, syllables.count <= 8 else { return nil }
        let abbr = syllables.compactMap { $0.first }.map(String.init).joined()
        guard abbr.count == syllables.count else { return nil }
        let t9Abbr = Self.toT9Digits(abbr)
        let now = Date().timeIntervalSince1970

        queue.async { [weak self] in
            guard let db = self?.db else { return }
            let sql = """
            INSERT INTO user_words (word, py, abbr, t9_abbr, len, freq, last_used, pinned)
            VALUES (?, ?, ?, ?, ?, 1, ?, 0)
            ON CONFLICT(word, py) DO UPDATE SET
                freq = freq + 1,
                t9_abbr = excluded.t9_abbr,
                last_used = excluded.last_used
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, word, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, py, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 3, abbr, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 4, t9Abbr, -1, Self.sqliteTransient)
            sqlite3_bind_int(stmt, 5, Int32(syllables.count))
            sqlite3_bind_double(stmt, 6, now)
            sqlite3_step(stmt)
        }
        return UserLearnRecord(word: word, py: py, prevWord: prevWord)
    }

    /// 撤销刚刚触发的一次选词学习（含关联二元搭配），防止按错候选永久污染词频。
    func undoLearn(_ record: UserLearnRecord) {
        queue.sync {
            guard let db else { return }
            // 1. 词频减 1，若减至 0 且未置顶则删除
            var decStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE user_words SET freq = freq - 1 WHERE word = ? AND py = ?", -1, &decStmt, nil) == SQLITE_OK, let decStmt {
                sqlite3_bind_text(decStmt, 1, record.word, -1, Self.sqliteTransient)
                sqlite3_bind_text(decStmt, 2, record.py, -1, Self.sqliteTransient)
                sqlite3_step(decStmt)
                sqlite3_finalize(decStmt)
            }
            var delStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM user_words WHERE word = ? AND py = ? AND freq <= 0 AND pinned = 0", -1, &delStmt, nil) == SQLITE_OK, let delStmt {
                sqlite3_bind_text(delStmt, 1, record.word, -1, Self.sqliteTransient)
                sqlite3_bind_text(delStmt, 2, record.py, -1, Self.sqliteTransient)
                sqlite3_step(delStmt)
                sqlite3_finalize(delStmt)
            }
            // 2. 若有关联二元搭配，同样回退计数
            if let prev = record.prevWord, !prev.isEmpty {
                var bgDec: OpaquePointer?
                if sqlite3_prepare_v2(db, "UPDATE bigrams SET freq = freq - 1 WHERE prev_word = ? AND next_word = ?", -1, &bgDec, nil) == SQLITE_OK, let bgDec {
                    sqlite3_bind_text(bgDec, 1, prev, -1, Self.sqliteTransient)
                    sqlite3_bind_text(bgDec, 2, record.word, -1, Self.sqliteTransient)
                    sqlite3_step(bgDec)
                    sqlite3_finalize(bgDec)
                }
                var bgDel: OpaquePointer?
                if sqlite3_prepare_v2(db, "DELETE FROM bigrams WHERE prev_word = ? AND next_word = ? AND freq <= 0", -1, &bgDel, nil) == SQLITE_OK, let bgDel {
                    sqlite3_bind_text(bgDel, 1, prev, -1, Self.sqliteTransient)
                    sqlite3_bind_text(bgDel, 2, record.word, -1, Self.sqliteTransient)
                    sqlite3_step(bgDel)
                    sqlite3_finalize(bgDel)
                }
            }
        }
    }

    /// 记录二元上下文词对。
    func learnBigram(prev: String, next: String) {
        guard !prev.isEmpty, !next.isEmpty, prev.count <= 8, next.count <= 8 else { return }
        let now = Date().timeIntervalSince1970
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            let sql = """
            INSERT INTO bigrams (prev_word, next_word, freq, last_used)
            VALUES (?, ?, 1, ?)
            ON CONFLICT(prev_word, next_word) DO UPDATE SET
                freq = freq + 1,
                last_used = excluded.last_used
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, prev, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, next, -1, Self.sqliteTransient)
            sqlite3_bind_double(stmt, 3, now)
            sqlite3_step(stmt)
        }
    }

    /// 查询二元上下文下一词联想（复用预编译 stmt 零 SQL 解析开销）。
    func predictNext(after prevWord: String, limit: Int = 10) -> [String] {
        guard !prevWord.isEmpty else { return [] }
        return queue.sync {
            guard let stmt = predictNextStmt else { return [] }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, prevWord, -1, Self.sqliteTransient)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var out: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    out.append(String(cString: ptr))
                }
            }
            sqlite3_reset(stmt)
            return out
        }
    }

    /// 返回用户历史记录的二元搭配加权（含 30 天时间衰减），供 Beam-Search Viterbi 解码器使用。
    func bigramBonuses(after prevWord: String, limit: Int = 24) -> [String: Double] {
        guard !prevWord.isEmpty else { return [:] }
        let now = Date().timeIntervalSince1970
        return queue.sync {
            guard let db else { return [:] }
            let sql = """
            SELECT next_word, freq, last_used
            FROM bigrams
            WHERE prev_word = ?
            ORDER BY last_used DESC, freq DESC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                return [:]
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, prevWord, -1, Self.sqliteTransient)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var map: [String: Double] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let ptr = sqlite3_column_text(stmt, 0) else { continue }
                let freq = Int(sqlite3_column_int(stmt, 1))
                let lastUsed = sqlite3_column_double(stmt, 2)
                let eff = Self.decayedFrequency(freq, lastUsed: lastUsed, now: now)
                map[String(cString: ptr)] = min(3.5, 0.8 + log(max(1.0, eff)) * 0.9)
            }
            return map
        }
    }

    func togglePin(word: String, py: String? = nil) {
        queue.sync {
            guard let db else { return }
            let sql = py == nil
                ? "UPDATE user_words SET pinned = CASE WHEN pinned = 1 THEN 0 ELSE 1 END WHERE word = ?"
                : "UPDATE user_words SET pinned = CASE WHEN pinned = 1 THEN 0 ELSE 1 END WHERE word = ? AND py = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, word, -1, Self.sqliteTransient)
            if let py {
                sqlite3_bind_text(stmt, 2, py, -1, Self.sqliteTransient)
            }
            sqlite3_step(stmt)
        }
    }

    func forget(word: String, py: String? = nil) {
        queue.sync {
            guard let db else { return }
            let sql = py == nil
                ? "DELETE FROM user_words WHERE word = ?"
                : "DELETE FROM user_words WHERE word = ? AND py = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, word, -1, Self.sqliteTransient)
            if let py {
                sqlite3_bind_text(stmt, 2, py, -1, Self.sqliteTransient)
            }
            sqlite3_step(stmt)
            // 同时清理相关二元联想中的孤立项（无论该词是 prev 还是 next）
            var bgStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM bigrams WHERE next_word = ? OR prev_word = ?", -1, &bgStmt, nil) == SQLITE_OK, let bgStmt {
                sqlite3_bind_text(bgStmt, 1, word, -1, Self.sqliteTransient)
                sqlite3_bind_text(bgStmt, 2, word, -1, Self.sqliteTransient)
                sqlite3_step(bgStmt)
                sqlite3_finalize(bgStmt)
            }
        }
    }

    func allEntries(limit: Int = 300) -> [UserWordEntry] {
        queue.sync {
            guard let db else { return [] }
            let sql = """
            SELECT word, py, abbr, freq, last_used, pinned
            FROM user_words
            ORDER BY pinned DESC, freq DESC, last_used DESC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                return []
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))

            var list: [UserWordEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let wPtr = sqlite3_column_text(stmt, 0),
                      let pPtr = sqlite3_column_text(stmt, 1),
                      let aPtr = sqlite3_column_text(stmt, 2) else { continue }
                list.append(UserWordEntry(
                    word: String(cString: wPtr),
                    py: String(cString: pPtr),
                    abbr: String(cString: aPtr),
                    freq: Int(sqlite3_column_int(stmt, 3)),
                    lastUsed: sqlite3_column_double(stmt, 4),
                    isPinned: sqlite3_column_int(stmt, 5) != 0
                ))
            }
            return list
        }
    }

    /// 导出用户词库为纯文本 TSV（格式：`拼音<TAB>词条<TAB>频次<TAB>置顶`，对齐 WowType user.tsv）。
    func exportTSV() -> String {
        let entries = allEntries(limit: 5000)
        var lines = ["# 灵犀输入法用户词库 (拼音<TAB>词条<TAB>频次<TAB>置顶)"]
        for e in entries {
            let pySpaced = e.py.replacingOccurrences(of: "'", with: " ")
            lines.append("\(pySpaced)\t\(e.word)\t\(e.freq)\t\(e.isPinned ? 1 : 0)")
        }
        return lines.joined(separator: "\n")
    }

    /// 导入 TSV 用户词库（兼容空格或撇号分隔的拼音）。
    @discardableResult
    func importTSV(_ text: String) -> Int {
        var count = 0
        let now = Date().timeIntervalSince1970
        queue.sync {
            guard let db else { return }
            let sql = """
            INSERT INTO user_words (word, py, abbr, t9_abbr, len, freq, last_used, pinned)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(word, py) DO UPDATE SET
                freq = MAX(user_words.freq, excluded.freq),
                pinned = MAX(user_words.pinned, excluded.pinned),
                last_used = excluded.last_used
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
            defer { sqlite3_finalize(stmt) }

            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty || line.hasPrefix("#") { continue }
                let cols = line.split(separator: "\t").map { String($0).trimmingCharacters(in: .whitespaces) }
                guard cols.count >= 2 else { continue }
                let pyNorm = cols[0].lowercased()
                    .replacingOccurrences(of: "ü", with: "v")
                    .split(whereSeparator: { $0 == " " || $0 == "'" })
                    .map(String.init)
                let word = cols[1]
                guard !word.isEmpty, !pyNorm.isEmpty, pyNorm.count <= 8 else { continue }
                let pyJoined = pyNorm.joined(separator: "'")
                let abbr = pyNorm.compactMap { $0.first }.map(String.init).joined()
                guard abbr.count == pyNorm.count else { continue }
                let t9 = Self.toT9Digits(abbr)
                let freq = (cols.count >= 3 ? Int(cols[2]) : nil) ?? 3
                let pinned = (cols.count >= 4 ? Int(cols[3]) : nil) ?? 0

                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_text(stmt, 1, word, -1, Self.sqliteTransient)
                sqlite3_bind_text(stmt, 2, pyJoined, -1, Self.sqliteTransient)
                sqlite3_bind_text(stmt, 3, abbr, -1, Self.sqliteTransient)
                sqlite3_bind_text(stmt, 4, t9, -1, Self.sqliteTransient)
                sqlite3_bind_int(stmt, 5, Int32(pyNorm.count))
                sqlite3_bind_int(stmt, 6, Int32(max(1, freq)))
                sqlite3_bind_double(stmt, 7, now)
                sqlite3_bind_int(stmt, 8, Int32(pinned != 0 ? 1 : 0))
                if sqlite3_step(stmt) == SQLITE_DONE {
                    count += 1
                }
            }
        }
        return count
    }

    func clearAll() {
        queue.sync {
            guard let db else { return }
            sqlite3_exec(db, "DELETE FROM user_words; DELETE FROM bigrams;", nil, nil, nil)
        }
    }

    /// 定期清理过期低频孤立记录并限制表容量上限（对齐 WowType `learn.rs`: 150 天单次淘汰 + 2万词/4万搭配封顶）。
    func pruneStaleEntries(now: TimeInterval = Date().timeIntervalSince1970) {
        let cutoff = now - 150.0 * 86400.0
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            var stmt1: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM user_words WHERE pinned = 0 AND freq <= 1 AND last_used < ?", -1, &stmt1, nil) == SQLITE_OK, let stmt1 {
                sqlite3_bind_double(stmt1, 1, cutoff)
                sqlite3_step(stmt1)
                sqlite3_finalize(stmt1)
            }
            var stmt2: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM bigrams WHERE freq <= 1 AND last_used < ?", -1, &stmt2, nil) == SQLITE_OK, let stmt2 {
                sqlite3_bind_double(stmt2, 1, cutoff)
                sqlite3_step(stmt2)
                sqlite3_finalize(stmt2)
            }
            // 超出容量上限时仅淘汰最冷的非置顶记录
            sqlite3_exec(
                db,
                """
                DELETE FROM user_words WHERE pinned = 0 AND rowid IN (
                    SELECT rowid FROM user_words WHERE pinned = 0 ORDER BY last_used DESC, freq DESC LIMIT -1 OFFSET 20000
                );
                DELETE FROM bigrams WHERE rowid IN (
                    SELECT rowid FROM bigrams ORDER BY last_used DESC, freq DESC LIMIT -1 OFFSET 40000
                );
                """,
                nil, nil, nil
            )
        }
    }

    // MARK: - 备份与恢复（M1.5）

    /// 备份前将 WAL 日志合并进主库文件，确保随后读取 user_dict.sqlite 拿到完整最新状态。
    func checkpointForBackup() {
        queue.sync {
            guard let db else { return }
            sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        }
    }

    /// 用备份中的 SQLite 数据整体替换当前词库：关旧连接 → 清理 WAL/SHM 残留 → 原子写盘 → 重开连接。
    /// 注意：键盘扩展等其他进程的旧连接仍指向被替换前的文件，恢复后需重启键盘才读到新词库。
    /// - Parameter data: 备份内的 user_dict.sqlite 字节
    /// - Throws: 写盘失败或重开数据库失败时抛出（调用方据此提示恢复失败）
    func restore(data: Data) throws {
        try queue.sync {
            if let db {
                sqlite3_close(db)
                self.db = nil
            }
            let url = AppGroup.fileURL(Self.dbFileName)
            // WAL/SHM 残留会在重开后覆盖恢复的数据，必须先清除
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
            try data.write(to: url, options: [.atomic])
            openDatabase()
            guard db != nil else {
                throw NSError(
                    domain: "com.lingxi.userlexicon",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "恢复词库后无法重新打开数据库"]
                )
            }
        }
    }
}
