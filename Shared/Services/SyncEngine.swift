import Foundation

// MARK: - 同步引擎编排层（M3-pre）
///
/// 把 M2 地基（Lamport / LWW / E2EE）串成完整闭环：
/// 采集本地变更 → push →（服务端冲突并入）→ 按命名空间分页 pull → LWW 合并 → 应用回写本地文件。
///
/// 设计约束：
/// - 业务只依赖 SyncService 协议：Local Noop 下 syncNow() 是无害空转（离线默认态完整可用）；
///   M3 换云实现时引擎零改动；
/// - 本地账本（上次推/拉过的全部记录）持久化于 App Group，是 merge 的 local 侧真相；
/// - SnapshotSyncSource 以文件字节为同步单元（settings/theme 整文件一条记录），
///   字节级比对去重——内容没变不重复推送；
/// - 词库/短语条目级同步在 M3 落地时扩展新的 SyncDataSource 实现，引擎不变。

/// 本地同步状态：账本 + 每命名空间拉取游标
/// （public：出现在 public 协议 SyncDataSource 方法签名与 SyncLedgerStore 公开方法中）
public struct SyncLedger: Codable, Equatable {
    /// 全部已见记录（命名空间/键 → 完整记录；含墓碑）
    public var records: [String: SyncChange] = [:]
    /// 每命名空间的拉取游标（服务端 nextCursor）
    public var cursors: [String: UInt64] = [:]

    public init() {}
}

/// 账本持久化（文件名注入：生产 lingxi_sync_ledger.json，测试用独立文件避免污染）
public final class SyncLedgerStore {
    private let fileName: String

    public init(fileName: String = "lingxi_sync_ledger.json") {
        self.fileName = fileName
    }

    public func load() -> SyncLedger {
        AppGroup.readJSON(SyncLedger.self, from: fileName) ?? SyncLedger()
    }

    public func save(_ ledger: SyncLedger) {
        _ = AppGroup.writeJSON(ledger, to: fileName)
    }
}

// MARK: - 数据源抽象

/// 同步数据源：本地采集 + 远端应用的业务桥接点。
/// M3 可扩展条目级实现（词库/短语每条一个 key）。
public protocol SyncDataSource: AnyObject {
    /// 本数据源监视的命名空间（拉取阶段按此集合请求，避免账本为空时漏拉远端数据）
    var watchedNamespaces: [SyncNamespace] { get }
    /// 采集本地变更：文件字节与账本比对，变化处才生成新记录（并登记进账本）
    func collectChanges(deviceID: String, clock: LamportClock, ledger: inout SyncLedger) -> [SyncChange]
    /// 应用远端胜出记录：只处理本源监视的命名空间；返回应用条数
    @discardableResult
    func apply(_ changes: [SyncChange]) -> Int
}

/// 快照数据源：整文件字节作为一条同步记录（适合设置/主题等单文档数据）
public final class SnapshotSyncSource: SyncDataSource {

    public struct Entry {
        public let namespace: SyncNamespace
        public let fileName: String

        public init(namespace: SyncNamespace, fileName: String) {
            self.namespace = namespace
            self.fileName = fileName
        }
    }

    private let entries: [Entry]
    public let watchedNamespaces: [SyncNamespace]

    public init(entries: [Entry]) {
        self.entries = entries
        self.watchedNamespaces = entries.map { $0.namespace }
    }

    public func collectChanges(deviceID: String, clock: LamportClock, ledger: inout SyncLedger) -> [SyncChange] {
        var pending: [SyncChange] = []
        for entry in entries {
            let key = entry.namespace.rawValue + "/main"
            let url = AppGroup.fileURL(entry.fileName)
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }

            if let existing = ledger.records[key], existing.ciphertext == data {
                continue // 内容与账本一致：无本地变更
            }

            let change = SyncChange(
                namespace: entry.namespace,
                key: "main",
                ciphertext: data,
                lamportTS: clock.tick(),
                deviceID: deviceID,
                tombstone: false
            )
            ledger.records[key] = change
            pending.append(change)
        }
        return pending
    }

    public func apply(_ changes: [SyncChange]) -> Int {
        var applied = 0
        for change in changes {
            guard let entry = entries.first(where: { $0.namespace == change.namespace }) else { continue }
            let url = AppGroup.fileURL(entry.fileName)
            if change.tombstone {
                try? FileManager.default.removeItem(at: url)
            } else {
                do {
                    try change.ciphertext.write(to: url, options: [.atomic])
                } catch {
                    continue // 写盘失败不计数（不误报已应用）
                }
            }
            applied += 1
        }
        return applied
    }

}

/// 个人自学习词库同步数据源：将 UserLexicon (user_dict.sqlite) 导出为确定性 TSV 快照参与 LWW 云同步，
/// 远端胜出时自动合并导入本地词库。
public final class UserLexiconSyncSource: SyncDataSource {
    public let watchedNamespaces: [SyncNamespace] = [.lexicon]

    public init() {}

    public func collectChanges(deviceID: String, clock: LamportClock, ledger: inout SyncLedger) -> [SyncChange] {
        let lexicon = UserLexicon()
        let tsv = lexicon.exportTSV()
        guard let data = tsv.data(using: .utf8), !data.isEmpty else { return [] }
        // 若仅包含表头注释而无实际词条且账本为空，跳过空推送
        let nonHeaderLines = tsv.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let recordKey = SyncNamespace.lexicon.rawValue + "/main"
        if nonHeaderLines.isEmpty && ledger.records[recordKey] == nil {
            return []
        }
        if let existing = ledger.records[recordKey], existing.ciphertext == data {
            return []
        }
        let change = SyncChange(
            namespace: .lexicon,
            key: "main",
            ciphertext: data,
            lamportTS: clock.tick(),
            deviceID: deviceID,
            tombstone: false
        )
        ledger.records[recordKey] = change
        return [change]
    }

    @discardableResult
    public func apply(_ changes: [SyncChange]) -> Int {
        var applied = 0
        let lexicon = UserLexicon()
        for change in changes where change.namespace == .lexicon && change.key == "main" {
            if change.tombstone {
                lexicon.clearAll()
                applied += 1
            } else if let text = String(data: change.ciphertext, encoding: .utf8) {
                _ = lexicon.importTSV(text)
                applied += 1
            }
        }
        return applied
    }
}

/// 组合数据源：将设置、主题、自定义短语文件快照与个人 SQLite 词库统一纳入单次 LWW 同步事务。
public final class CompositeSyncSource: SyncDataSource {
    private let sources: [SyncDataSource]

    public var watchedNamespaces: [SyncNamespace] {
        var seen = Set<SyncNamespace>()
        var result: [SyncNamespace] = []
        for src in sources {
            for ns in src.watchedNamespaces where seen.insert(ns).inserted {
                result.append(ns)
            }
        }
        return result
    }

    public init(sources: [SyncDataSource]) {
        self.sources = sources
    }

    public func collectChanges(deviceID: String, clock: LamportClock, ledger: inout SyncLedger) -> [SyncChange] {
        var all: [SyncChange] = []
        for src in sources {
            all.append(contentsOf: src.collectChanges(deviceID: deviceID, clock: clock, ledger: &ledger))
        }
        return all
    }

    @discardableResult
    public func apply(_ changes: [SyncChange]) -> Int {
        var total = 0
        for src in sources {
            total += src.apply(changes)
        }
        return total
    }
}

// MARK: - 引擎

/// 一次同步的执行报告
public struct SyncRunReport: Equatable {
    public let pushed: Int
    public let pulled: Int
    public let applied: Int
    public let conflicts: Int
}

/// 同步编排器：依赖全部来自 M1/M2 的协议与地基，M3 只替换 SyncService 实现。
public final class SyncEngine {

    private let sync: SyncService
    private let source: SyncDataSource
    private let clock: LamportClock
    private let deviceID: String
    private let ledgerStore: SyncLedgerStore

    public init(sync: SyncService,
                source: SyncDataSource,
                clock: LamportClock = .shared,
                deviceID: String = SyncInfra.deviceIdentity().deviceID,
                ledgerStore: SyncLedgerStore = SyncLedgerStore()) {
        self.sync = sync
        self.source = source
        self.clock = clock
        self.deviceID = deviceID
        self.ledgerStore = ledgerStore
    }

    /// 生产全量重要数据源：覆盖全部 7 类核心用户数据（设置、主题、自定义编码短语、快捷回复短语、常用表情权重、打字统计与个人 SQLite 词库）
    public static func makeFullSyncSource() -> SyncDataSource {
        CompositeSyncSource(sources: [
            SnapshotSyncSource(entries: [
                .init(namespace: .settings, fileName: "lingxi_settings.json"),
                .init(namespace: .theme, fileName: "lingxi_theme.json"),
                .init(namespace: .phrases, fileName: "lingxi_custom_words.json"),
                .init(namespace: .quickPhrases, fileName: "lingxi_phrases.json"),
                .init(namespace: .recentEmojis, fileName: "lingxi_recent_emojis.json"),
                .init(namespace: .typingStats, fileName: "typing_stats.json"),
                .init(namespace: .aiPrompts, fileName: "lingxi_ai_prompts_sync.json"),
                .init(namespace: .keymap, fileName: "lingxi_custom_keymap.json"),
                .init(namespace: .styleDNA, fileName: "lingxi_style_dna.json")
            ]),
            UserLexiconSyncSource()
        ])
    }

    /// 生产共享实例：Local Noop 同步服务（离线默认态）+ 全量重要数据源
    public static let shared = SyncEngine(
        sync: LingxiServices.sync,
        source: makeFullSyncSource()
    )

    /// 完整一轮同步。网络不可达时向上抛出（调用方静默处理，离线是默认态不是错误态）。
    @discardableResult
    public func syncNow() async throws -> SyncRunReport {
        var ledger = ledgerStore.load()

        // 1. 采集本地变更（字节级比对去重后逐条 tick）
        let localChanges = source.collectChanges(deviceID: deviceID, clock: clock, ledger: &ledger)

        // 2. 推送；服务端 LWW 胜出的冲突记录视为远端最新，并入本轮拉取结果
        var pulled: [SyncChange] = []
        var conflictCount = 0
        if !localChanges.isEmpty {
            let conflicts = try await sync.push(localChanges)
            conflictCount = conflicts.count
            pulled.append(contentsOf: conflicts.map { $0.serverRecord })
        }

        // 3. 按命名空间分页拉取（游标持久化，中断续传）：
        // 命名空间集合 = 数据源监视集合 ∪ 账本已见集合（全新设备账本为空也能拉到全部远端数据）
        var namespaces = Set(source.watchedNamespaces.map { $0.rawValue })
        namespaces.formUnion(ledger.records.keys.map { String($0.split(separator: "/")[0]) })
        for entry in namespaces {
            let ns = SyncNamespace(rawValue: entry)
            var cursor = ledger.cursors[entry] ?? 0
            while true {
                let page = try await sync.pull(namespace: ns, since: cursor)
                pulled.append(contentsOf: page.changes)
                cursor = page.nextCursor
                if !page.hasMore { break }
            }
            ledger.cursors[entry] = cursor
        }

        // 4. LWW 合并：账本 vs 拉取结果（含冲突服务端记录）
        let outcome = LWWMergeEngine.merge(local: Array(ledger.records.values), remote: pulled)

        // 5. 远端胜出者回写本地文件（数据源按命名空间过滤），并推进本地时钟（ADR 0001：max(local, remote) + 1）
        for change in outcome.toApply {
            clock.observe(remote: change.lamportTS)
        }
        let applied = source.apply(outcome.toApply)

        // 6. 账本收敛为合并结果并持久化
        var newLedger = SyncLedger()
        newLedger.cursors = ledger.cursors
        for change in outcome.merged {
            newLedger.records[change.namespace.rawValue + "/" + change.key] = change
        }
        ledgerStore.save(newLedger)

        return SyncRunReport(
            pushed: localChanges.count,
            pulled: pulled.count,
            applied: applied,
            conflicts: conflictCount
        )
    }
}
