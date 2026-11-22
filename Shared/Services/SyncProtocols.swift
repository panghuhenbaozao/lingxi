import Foundation

// MARK: - 同步协议层（v4.0 架构地基）
///
/// 三条不可动摇的架构铁律（详见 README 与 docs/adr/0001-sync-protocols.md）：
/// 1. 键盘扩展永不发起网络请求——本协议层只允许主 App 目标成员引入；
/// 2. 离线是默认态且永远完整可用——Local Noop 实现即产品默认行为；
/// 3. 云同步端到端加密（E2EE）——服务端只存密文，业务代码只依赖协议，
///    云实现（CloudBase/自建）只替换实现文件，业务零改动。
///
/// 同步冲突策略（ADR 0001）：不用 CRDT。键值语义下用
/// 版本向量 + LWW（lamport 时间戳 + device_id 全序决胜），删除走墓碑。

// MARK: 会话与凭证

/// 登录会话。token 仅存钥匙串（Keychain），禁止写入 UserDefaults/文件。
public struct AuthSession: Equatable, Codable {
    public let userID: String
    public let accessToken: String
    public let refreshToken: String
    /// access token 过期时间（本地时钟），提前 5 分钟视为需要续期
    public let accessExpiry: Date

    public init(userID: String, accessToken: String, refreshToken: String, accessExpiry: Date) {
        self.userID = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiry = accessExpiry
    }

    public var needsRefresh: Bool { Date().addingTimeInterval(300) >= accessExpiry }
}

public enum AuthError: Error, Equatable {
    /// 未登录（Noop 实现的常态）
    case notAuthenticated
    /// 凭证失效且续期失败
    case sessionExpired
    /// 服务端不可达——离线场景下业务应继续走本地
    case networkUnavailable
}

// MARK: 同步数据模型

/// 同步命名空间：settings / phrases / lexicon / theme
public struct SyncNamespace: RawRepresentable, Equatable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let settings = SyncNamespace(rawValue: "settings")
    public static let phrases = SyncNamespace(rawValue: "phrases")
    public static let quickPhrases = SyncNamespace(rawValue: "quick_phrases")
    public static let recentEmojis = SyncNamespace(rawValue: "recent_emojis")
    public static let typingStats = SyncNamespace(rawValue: "typing_stats")
    public static let lexicon = SyncNamespace(rawValue: "lexicon")
    public static let theme = SyncNamespace(rawValue: "theme")
}

/// 单条同步变更。value 由调用方加密（E2EE 层负责），协议层不感知加密细节。
public struct SyncChange: Equatable, Codable {
    public let namespace: SyncNamespace
    public let key: String
    /// 密文（E2EE 后的 base64）；Local Noop 下可为明文占位
    public let ciphertext: Data
    /// 逻辑时钟：Lamport 时间戳，合并时与 deviceID 组成全序
    public let lamportTS: UInt64
    public let deviceID: String
    /// 墓碑标记：true 表示删除
    public let tombstone: Bool
    /// 数据结构版本，端侧按版本链迁移解码
    public let schemaVersion: Int

    public init(namespace: SyncNamespace, key: String, ciphertext: Data,
                lamportTS: UInt64, deviceID: String, tombstone: Bool = false,
                schemaVersion: Int = 1) {
        self.namespace = namespace
        self.key = key
        self.ciphertext = ciphertext
        self.lamportTS = lamportTS
        self.deviceID = deviceID
        self.tombstone = tombstone
        self.schemaVersion = schemaVersion
    }

    /// 全序决胜规则：(lamportTS, deviceID) 字典序，大者胜
    public func wins(over other: SyncChange) -> Bool {
        if lamportTS != other.lamportTS { return lamportTS > other.lamportTS }
        return deviceID > other.deviceID
    }
}

/// 增量拉取结果页
public struct SyncPage: Equatable, Codable {
    public let changes: [SyncChange]
    /// 服务端水位：下次 pull 以此为起点
    public let nextCursor: UInt64
    /// 是否还有更多（分页拉取）
    public let hasMore: Bool

    public init(changes: [SyncChange], nextCursor: UInt64, hasMore: Bool) {
        self.changes = changes
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

/// 推送冲突（服务端已有更新的记录时返回）
public struct SyncConflict: Equatable, Codable {
    public let namespace: SyncNamespace
    public let key: String
    /// 服务端胜出的记录（LWW 规则）
    public let serverRecord: SyncChange

    public init(namespace: SyncNamespace, key: String, serverRecord: SyncChange) {
        self.namespace = namespace
        self.key = key
        self.serverRecord = serverRecord
    }
}

// MARK: - 协议定义

/// 账号服务。唯一允许持有 token 与发起认证请求的抽象。
public protocol AuthService: AnyObject {
    /// 当前会话；未登录返回 nil（不是错误态——未登录是产品默认态）
    var currentSession: AuthSession? { get }

    /// Sign in with Apple 流程完成后的会话建立
    func signInWithApple(identityToken: Data, user: String) async throws -> AuthSession

    /// 需要时自动续期；返回 nil 表示未登录
    func refreshIfNeeded() async throws -> AuthSession?

    /// 登出：清除钥匙串凭证与本地缓存
    func signOut() async
}

/// 零知识同步服务。实现方只能拿到密文——明文永不出协议层。
public protocol SyncService: AnyObject {
    /// 增量拉取：since 为本设备已见最大 lamport 水位
    func pull(namespace: SyncNamespace, since: UInt64) async throws -> SyncPage

    /// 批量推送；返回被服务端 LWW 胜出的冲突列表（调用方按需合并重推）
    func push(_ changes: [SyncChange]) async throws -> [SyncConflict]
}

/// 会话摘要：分析通道的最小上报单元。
/// **铁律：结构中不允许出现任何输入原文、词条、按键序列。**
/// 编译器层面约束：所有字段均为数值，无 String 内容字段。
public struct TypingSessionDigest: Equatable, Codable {
    /// 会话开始（本地时间，上报时转为 UTC 日粒度）
    public let startedAt: Date
    /// 会话时长（秒）
    public let durationSeconds: Int
    /// 上屏字符数
    public let committedChars: Int
    /// 上屏词数
    public let committedWords: Int
    /// 删除次数（含退格与撤销）
    public let deleteCount: Int
    /// 输入方案标识（枚举索引，非自由文本）
    public let schemeIndex: Int
    /// 布局标识（枚举索引）
    public let layoutIndex: Int

    public init(startedAt: Date, durationSeconds: Int, committedChars: Int,
                committedWords: Int, deleteCount: Int, schemeIndex: Int, layoutIndex: Int) {
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.committedChars = committedChars
        self.committedWords = committedWords
        self.deleteCount = deleteCount
        self.schemeIndex = schemeIndex
        self.layoutIndex = layoutIndex
    }
}

/// 分析上报服务。**默认实现必须是 Noop**；真实实现必须先检查
/// 独立授权状态（与登录解耦），未授权直接丢弃。
public protocol InsightService: AnyObject {
    /// 是否已获用户显式授权（独立于登录）
    var isAuthorized: Bool { get }

    /// 批量提交会话摘要；未授权时实现必须静默丢弃（不缓存不报错）
    func submit(_ digests: [TypingSessionDigest]) async throws
}

// MARK: - Local Noop 实现（默认态：纯离线，永不难用）

/// 默认账号服务：永远未登录、零联网。
/// 业务代码依赖 AuthService 时，未登录态下一切功能照常。
public final class LocalNoopAuthService: AuthService {
    public private(set) var currentSession: AuthSession?

    public init() {}

    public func signInWithApple(identityToken: Data, user: String) async throws -> AuthSession {
        // M3 之前无云实现：明确报错而非假装成功，调用方据此展示『云服务未开放』
        throw AuthError.networkUnavailable
    }

    public func refreshIfNeeded() async throws -> AuthSession? {
        nil
    }

    public func signOut() async {
        currentSession = nil
    }
}

/// 默认同步服务：所有数据留在本地，零联网。
/// push 返回空冲突、pull 返回空页——语义上『无云端数据』，业务无感降级。
public final class LocalNoopSyncService: SyncService {
    public init() {}

    public func pull(namespace: SyncNamespace, since: UInt64) async throws -> SyncPage {
        SyncPage(changes: [], nextCursor: since, hasMore: false)
    }

    public func push(_ changes: [SyncChange]) async throws -> [SyncConflict] {
        []
    }
}

/// 默认分析服务：未授权常量，静默丢弃一切上报。
public final class LocalNoopInsightService: InsightService {
    /// Noop 实现永远未授权（M5 前分析通道整体关闭）
    public let isAuthorized = false

    public init() {}

    public func submit(_ digests: [TypingSessionDigest]) async throws {
        // 静默丢弃：不缓存、不报错、不联网
    }
}

// MARK: - 服务工厂（唯一组装点）

/// 业务代码从这里取服务实例；未登录/未配置 API Key 时自动退化为本地离线零请求态。
public enum LingxiServices {
    public static var auth: AuthService { CloudBackendClient.shared }
    public static var sync: SyncService { CloudBackendClient.shared }
    public static var insight: InsightService { CloudBackendClient.shared }
}
