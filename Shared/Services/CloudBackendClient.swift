import CryptoKit
import Foundation
import Security

// MARK: - 云端配置与安全凭证存储

/// 云端服务与 API 接入配置（持久化于 App Group；敏感 Token 与 API Key 走 Keychain + 沙盒保护回退）。
public struct CloudBackendConfig: Codable, Equatable {
    public var serverBaseURL: String = "http://127.0.0.1:8787"
    public var userID: String = ""
    public var email: String = ""
    public var username: String = ""
    public var avatarThemeIndex: Int = 0
    public var apiKeyPrefix: String = ""
    public var e2eeSalt: String = ""
    /// true 表示当前为 iPhone 端侧离线加密账号（无需电脑服务器即可注册、设头像与本地同步，接入服务器后可随时升级云同步）
    public var isLocalOnlyAccount: Bool = false
    /// 第六部分合规铁律：分析功能默认关闭（零收集），由用户显式授权开启并与登录解耦
    public var habitAnalysisEnabled: Bool = false
    public var autoSyncEnabled: Bool = true
    public var lastSyncedAt: Date?
    public var lastSyncSummary: String = ""

    private static let fileName = "lingxi_cloud_config.json"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverBaseURL = try c.decodeIfPresent(String.self, forKey: .serverBaseURL) ?? "http://127.0.0.1:8787"
        userID = try c.decodeIfPresent(String.self, forKey: .userID) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        avatarThemeIndex = try c.decodeIfPresent(Int.self, forKey: .avatarThemeIndex) ?? 0
        apiKeyPrefix = try c.decodeIfPresent(String.self, forKey: .apiKeyPrefix) ?? ""
        e2eeSalt = try c.decodeIfPresent(String.self, forKey: .e2eeSalt) ?? ""
        isLocalOnlyAccount = try c.decodeIfPresent(Bool.self, forKey: .isLocalOnlyAccount) ?? false
        habitAnalysisEnabled = try c.decodeIfPresent(Bool.self, forKey: .habitAnalysisEnabled) ?? false
        autoSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? true
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        lastSyncSummary = try c.decodeIfPresent(String.self, forKey: .lastSyncSummary) ?? ""
    }

    public static func load() -> CloudBackendConfig {
        AppGroup.readJSON(CloudBackendConfig.self, from: fileName) ?? CloudBackendConfig()
    }

    @discardableResult
    public func save() -> Bool {
        AppGroup.writeJSON(self, to: Self.fileName, protected: true)
    }

    public var normalizedBaseURL: String {
        var trimmed = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed.isEmpty ? "http://127.0.0.1:8787" : trimmed
    }
}

/// 钥匙串 + 受保护容器双保险凭证管理器（兼容未签名模拟器测试环境与真机 Keychain）。
public enum CloudCredentialStore {
    private static let serviceName = "com.lingxi.ime.cloud"
    private static let fallbackFileName = "lingxi_cloud_credentials.json"

    private struct FallbackSecrets: Codable {
        var session: AuthSession?
        var apiKey: String?
    }

    public static func saveSession(_ session: AuthSession?) {
        var secrets = loadFallback()
        secrets.session = session
        _ = AppGroup.writeJSON(secrets, to: fallbackFileName, protected: true)
        if let session, let data = try? JSONEncoder().encode(session) {
            writeKeychain(account: "auth_session", data: data)
        } else {
            deleteKeychain(account: "auth_session")
        }
    }

    public static func loadSession() -> AuthSession? {
        if let data = readKeychain(account: "auth_session"),
           let session = try? JSONDecoder().decode(AuthSession.self, from: data) {
            return session
        }
        return loadFallback().session
    }

    public static func saveAPIKey(_ apiKey: String?) {
        let cleaned = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        var secrets = loadFallback()
        secrets.apiKey = (cleaned?.isEmpty == false) ? cleaned : nil
        _ = AppGroup.writeJSON(secrets, to: fallbackFileName, protected: true)
        if let cleaned, !cleaned.isEmpty, let data = cleaned.data(using: .utf8) {
            writeKeychain(account: "customer_api_key", data: data)
        } else {
            deleteKeychain(account: "customer_api_key")
        }
    }

    public static func loadAPIKey() -> String? {
        if let data = readKeychain(account: "customer_api_key"),
           let str = String(data: data, encoding: .utf8),
           !str.isEmpty {
            return str
        }
        return loadFallback().apiKey
    }

    public static func clearAll() {
        deleteKeychain(account: "auth_session")
        deleteKeychain(account: "customer_api_key")
        try? FileManager.default.removeItem(at: AppGroup.fileURL(fallbackFileName))
    }

    private static func loadFallback() -> FallbackSecrets {
        AppGroup.readJSON(FallbackSecrets.self, from: fallbackFileName) ?? FallbackSecrets()
    }

    private static func writeKeychain(account: String, data: Data) {
        deleteKeychain(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 打字习惯画像与 API 实时分析模型 (对齐 Server/lingxi_server.py)

public struct TypingTuningRecommendation: Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let reason: String
    public let settingKey: String

    public init(id: String, title: String, reason: String, settingKey: String) {
        self.id = id
        self.title = title
        self.reason = reason
        self.settingKey = settingKey
    }
}

public struct AIUsageFeatureStat: Codable, Equatable {
    public var calls: Int
    public var inputChars: Int
    public var outputChars: Int
    public var avgLatencyMs: Int

    public init(calls: Int = 0, inputChars: Int = 0, outputChars: Int = 0, avgLatencyMs: Int = 0) {
        self.calls = calls
        self.inputChars = inputChars
        self.outputChars = outputChars
        self.avgLatencyMs = avgLatencyMs
    }
}

public struct LexiconDomainAffinity: Codable, Equatable {
    public var primaryDomain: String = "综合通用"
    public var domainScores: [String: Int] = [:]
    public var analyzedWordCount: Int = 0
    public var avgLexiconWordLength: Double = 0
    public var preferredTone: String = "自然流畅"
    public var topTerms: [String] = []

    public init(
        primaryDomain: String = "综合通用",
        domainScores: [String: Int] = [:],
        analyzedWordCount: Int = 0,
        avgLexiconWordLength: Double = 0,
        preferredTone: String = "自然流畅",
        topTerms: [String] = []
    ) {
        self.primaryDomain = primaryDomain
        self.domainScores = domainScores
        self.analyzedWordCount = analyzedWordCount
        self.avgLexiconWordLength = avgLexiconWordLength
        self.preferredTone = preferredTone
        self.topTerms = topTerms
    }
}

public struct TypingHabitEventPayload: Codable, Equatable {
    public var startedAt: Int
    public var durationSeconds: Int
    public var committedChars: Int
    public var committedWords: Int
    public var deleteCount: Int
    public var undoLearnCount: Int
    public var glideWords: Int
    public var typoCorrectedCount: Int
    public var aiInvocations: Int
    public var translateChars: Int
    public var schemeID: String
    public var layoutID: String
    public var activeHour: Int
    public var deviceID: String
    public var confusionCounts: [String: Int]

    public init(
        startedAt: Int = Int(Date().timeIntervalSince1970),
        durationSeconds: Int,
        committedChars: Int,
        committedWords: Int,
        deleteCount: Int = 0,
        undoLearnCount: Int = 0,
        glideWords: Int = 0,
        typoCorrectedCount: Int = 0,
        aiInvocations: Int = 0,
        translateChars: Int = 0,
        schemeID: String = "quanpin",
        layoutID: String = "qwerty26",
        activeHour: Int = Calendar.current.component(.hour, from: Date()),
        deviceID: String = SyncInfra.deviceIdentity().deviceID,
        confusionCounts: [String: Int] = [:]
    ) {
        self.startedAt = startedAt
        self.durationSeconds = max(1, durationSeconds)
        self.committedChars = max(0, committedChars)
        self.committedWords = max(0, committedWords)
        self.deleteCount = max(0, deleteCount)
        self.undoLearnCount = max(0, undoLearnCount)
        self.glideWords = max(0, glideWords)
        self.typoCorrectedCount = max(0, typoCorrectedCount)
        self.aiInvocations = max(0, aiInvocations)
        self.translateChars = max(0, translateChars)
        self.schemeID = schemeID
        self.layoutID = layoutID
        self.activeHour = ((activeHour % 24) + 24) % 24
        self.deviceID = deviceID
        self.confusionCounts = confusionCounts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try c.decodeIfPresent(Int.self, forKey: .startedAt) ?? Int(Date().timeIntervalSince1970)
        durationSeconds = max(1, try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 1)
        committedChars = max(0, try c.decodeIfPresent(Int.self, forKey: .committedChars) ?? 0)
        committedWords = max(0, try c.decodeIfPresent(Int.self, forKey: .committedWords) ?? 0)
        deleteCount = max(0, try c.decodeIfPresent(Int.self, forKey: .deleteCount) ?? 0)
        undoLearnCount = max(0, try c.decodeIfPresent(Int.self, forKey: .undoLearnCount) ?? 0)
        glideWords = max(0, try c.decodeIfPresent(Int.self, forKey: .glideWords) ?? 0)
        typoCorrectedCount = max(0, try c.decodeIfPresent(Int.self, forKey: .typoCorrectedCount) ?? 0)
        aiInvocations = max(0, try c.decodeIfPresent(Int.self, forKey: .aiInvocations) ?? 0)
        translateChars = max(0, try c.decodeIfPresent(Int.self, forKey: .translateChars) ?? 0)
        schemeID = try c.decodeIfPresent(String.self, forKey: .schemeID) ?? "quanpin"
        layoutID = try c.decodeIfPresent(String.self, forKey: .layoutID) ?? "qwerty26"
        activeHour = try c.decodeIfPresent(Int.self, forKey: .activeHour) ?? 12
        deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID) ?? "ios-default"
        confusionCounts = try c.decodeIfPresent([String: Int].self, forKey: .confusionCounts) ?? [:]
    }
}

public struct AIAPIUsagePayload: Codable, Equatable {
    public var feature: String
    public var provider: String
    public var targetLang: String
    public var formalTone: Bool
    public var inputChars: Int
    public var outputChars: Int
    public var latencyMs: Int
    public var createdAt: Int

    public init(
        feature: String,
        provider: String,
        targetLang: String = "英文",
        formalTone: Bool = false,
        inputChars: Int,
        outputChars: Int,
        latencyMs: Int,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.feature = feature
        self.provider = provider
        self.targetLang = targetLang
        self.formalTone = formalTone
        self.inputChars = max(0, inputChars)
        self.outputChars = max(0, outputChars)
        self.latencyMs = max(0, latencyMs)
        self.createdAt = createdAt
    }
}

/// 用户打字习惯实时画像（端云同构：无网络时端侧实时计算，接入后端/API Key 后与服务器数据库双向同步）。
public struct UserTypingHabitProfile: Codable, Equatable {
    public var userID: String = "local-user"
    public var totalChars: Int = 0
    public var totalWords: Int = 0
    public var totalDurationSeconds: Int = 0
    public var totalSessions: Int = 0
    public var avgCPM: Double = 0
    public var peakCPM: Double = 0
    public var avgWordLength: Double = 0
    public var backspaceRate: Double = 0
    public var undoLearnRate: Double = 0
    public var glideRatio: Double = 0
    public var typoCorrectionRate: Double = 0
    public var primaryScheme: String = "quanpin"
    public var primaryLayout: String = "qwerty26"
    public var schemeBreakdown: [String: Int] = [:]
    public var hourlyRhythm: [String: Int] = [:]
    public var aiFeatureBreakdown: [String: AIUsageFeatureStat] = [:]
    public var confusionMatrix: [String: Int] = [:]
    public var domainAffinity: LexiconDomainAffinity = LexiconDomainAffinity()
    public var habitTags: [String] = []
    public var tuningRecommendations: [TypingTuningRecommendation] = []
    public var updatedAt: Int = Int(Date().timeIntervalSince1970)

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decodeIfPresent(String.self, forKey: .userID) ?? "local-user"
        totalChars = try c.decodeIfPresent(Int.self, forKey: .totalChars) ?? 0
        totalWords = try c.decodeIfPresent(Int.self, forKey: .totalWords) ?? 0
        totalDurationSeconds = try c.decodeIfPresent(Int.self, forKey: .totalDurationSeconds) ?? 0
        totalSessions = try c.decodeIfPresent(Int.self, forKey: .totalSessions) ?? 0
        avgCPM = try c.decodeIfPresent(Double.self, forKey: .avgCPM) ?? 0
        peakCPM = try c.decodeIfPresent(Double.self, forKey: .peakCPM) ?? 0
        avgWordLength = try c.decodeIfPresent(Double.self, forKey: .avgWordLength) ?? 0
        backspaceRate = try c.decodeIfPresent(Double.self, forKey: .backspaceRate) ?? 0
        undoLearnRate = try c.decodeIfPresent(Double.self, forKey: .undoLearnRate) ?? 0
        glideRatio = try c.decodeIfPresent(Double.self, forKey: .glideRatio) ?? 0
        typoCorrectionRate = try c.decodeIfPresent(Double.self, forKey: .typoCorrectionRate) ?? 0
        primaryScheme = try c.decodeIfPresent(String.self, forKey: .primaryScheme) ?? "quanpin"
        primaryLayout = try c.decodeIfPresent(String.self, forKey: .primaryLayout) ?? "qwerty26"
        schemeBreakdown = try c.decodeIfPresent([String: Int].self, forKey: .schemeBreakdown) ?? [:]
        hourlyRhythm = try c.decodeIfPresent([String: Int].self, forKey: .hourlyRhythm) ?? [:]
        aiFeatureBreakdown = try c.decodeIfPresent([String: AIUsageFeatureStat].self, forKey: .aiFeatureBreakdown) ?? [:]
        confusionMatrix = try c.decodeIfPresent([String: Int].self, forKey: .confusionMatrix) ?? [:]
        domainAffinity = try c.decodeIfPresent(LexiconDomainAffinity.self, forKey: .domainAffinity) ?? LexiconDomainAffinity()
        habitTags = try c.decodeIfPresent([String].self, forKey: .habitTags) ?? []
        tuningRecommendations = try c.decodeIfPresent([TypingTuningRecommendation].self, forKey: .tuningRecommendations) ?? []
        updatedAt = try c.decodeIfPresent(Int.self, forKey: .updatedAt) ?? Int(Date().timeIntervalSince1970)
    }
}

// MARK: - 实时打字习惯追踪与画像计算器 (TypingHabitTracker)

public final class TypingHabitTracker {
    public static let shared = TypingHabitTracker()

    private static let allEventsFile = "lingxi_habit_events_all.json"
    private static let pendingEventsFile = "lingxi_habit_events_pending.json"
    private static let allAILogsFile = "lingxi_ai_usage_all.json"
    private static let pendingAILogsFile = "lingxi_ai_usage_pending.json"
    private static let profileFile = "lingxi_habit_profile.json"

    private let queue = DispatchQueue(label: "com.lingxi.habittracker", qos: .utility)

    public init() {}

    /// 记录一次打字会话或实时击键批次，并立即更新打字习惯画像。
    @discardableResult
    public func recordTypingEvent(_ event: TypingHabitEventPayload) -> UserTypingHabitProfile {
        queue.sync {
            var all = AppGroup.readJSON([TypingHabitEventPayload].self, from: Self.allEventsFile) ?? []
            all.append(event)
            if all.count > 500 {
                all = Array(all.suffix(500))
            }
            _ = AppGroup.writeJSON(all, to: Self.allEventsFile)

            var pending = AppGroup.readJSON([TypingHabitEventPayload].self, from: Self.pendingEventsFile) ?? []
            pending.append(event)
            if pending.count > 200 {
                pending = Array(pending.suffix(200))
            }
            _ = AppGroup.writeJSON(pending, to: Self.pendingEventsFile)

            let aiLogs = AppGroup.readJSON([AIAPIUsagePayload].self, from: Self.allAILogsFile) ?? []
            let profile = Self.computeProfile(events: all, aiLogs: aiLogs)
            _ = AppGroup.writeJSON(profile, to: Self.profileFile)
            return profile
        }
    }

    /// 记录一次 AI 写作或实时翻译 API 调用习惯，并立即更新画像。
    @discardableResult
    public func recordAIUsage(_ usage: AIAPIUsagePayload) -> UserTypingHabitProfile {
        queue.sync {
            var allAI = AppGroup.readJSON([AIAPIUsagePayload].self, from: Self.allAILogsFile) ?? []
            allAI.append(usage)
            if allAI.count > 300 {
                allAI = Array(allAI.suffix(300))
            }
            _ = AppGroup.writeJSON(allAI, to: Self.allAILogsFile)

            var pendingAI = AppGroup.readJSON([AIAPIUsagePayload].self, from: Self.pendingAILogsFile) ?? []
            pendingAI.append(usage)
            if pendingAI.count > 150 {
                pendingAI = Array(pendingAI.suffix(150))
            }
            _ = AppGroup.writeJSON(pendingAI, to: Self.pendingAILogsFile)

            let events = AppGroup.readJSON([TypingHabitEventPayload].self, from: Self.allEventsFile) ?? []
            let profile = Self.computeProfile(events: events, aiLogs: allAI)
            _ = AppGroup.writeJSON(profile, to: Self.profileFile)
            return profile
        }
    }

    public func currentProfile() -> UserTypingHabitProfile {
        queue.sync {
            if let saved = AppGroup.readJSON(UserTypingHabitProfile.self, from: Self.profileFile) {
                return saved
            }
            let events = AppGroup.readJSON([TypingHabitEventPayload].self, from: Self.allEventsFile) ?? []
            let aiLogs = AppGroup.readJSON([AIAPIUsagePayload].self, from: Self.allAILogsFile) ?? []
            return Self.computeProfile(events: events, aiLogs: aiLogs)
        }
    }

    public func saveServerProfile(_ profile: UserTypingHabitProfile) {
        queue.sync {
            _ = AppGroup.writeJSON(profile, to: Self.profileFile)
        }
    }

    public func pendingEvents() -> [TypingHabitEventPayload] {
        queue.sync {
            AppGroup.readJSON([TypingHabitEventPayload].self, from: Self.pendingEventsFile) ?? []
        }
    }

    public func clearPendingEvents() {
        queue.sync {
            _ = AppGroup.writeJSON([TypingHabitEventPayload](), to: Self.pendingEventsFile)
        }
    }

    public func pendingAILogs() -> [AIAPIUsagePayload] {
        queue.sync {
            AppGroup.readJSON([AIAPIUsagePayload].self, from: Self.pendingAILogsFile) ?? []
        }
    }

    public func clearPendingAILogs() {
        queue.sync {
            _ = AppGroup.writeJSON([AIAPIUsagePayload](), to: Self.pendingAILogsFile)
        }
    }

    public func clearAllLocalHabits() {
        queue.sync {
            _ = AppGroup.writeJSON([TypingHabitEventPayload](), to: Self.allEventsFile)
            _ = AppGroup.writeJSON([TypingHabitEventPayload](), to: Self.pendingEventsFile)
            _ = AppGroup.writeJSON([AIAPIUsagePayload](), to: Self.allAILogsFile)
            _ = AppGroup.writeJSON([AIAPIUsagePayload](), to: Self.pendingAILogsFile)
            let empty = Self.computeProfile(events: [], aiLogs: [])
            _ = AppGroup.writeJSON(empty, to: Self.profileFile)
        }
    }

    /// 端云同构的打字习惯画像分析算法（与 Server/lingxi_server.py 严格一致）。
    public static func computeProfile(
        events: [TypingHabitEventPayload],
        aiLogs: [AIAPIUsagePayload],
        userID: String = "local-user"
    ) -> UserTypingHabitProfile {
        var p = UserTypingHabitProfile()
        p.userID = userID
        p.totalSessions = events.count
        p.totalChars = events.reduce(0) { $0 + $1.committedChars }
        p.totalWords = events.reduce(0) { $0 + $1.committedWords }
        p.totalDurationSeconds = events.reduce(0) { $0 + $1.durationSeconds }

        let totalDeletes = events.reduce(0) { $0 + $1.deleteCount }
        let totalUndos = events.reduce(0) { $0 + $1.undoLearnCount }
        let totalGlides = events.reduce(0) { $0 + $1.glideWords }
        let totalTypos = events.reduce(0) { $0 + $1.typoCorrectedCount }

        if p.totalDurationSeconds > 0 {
            p.avgCPM = ((Double(p.totalChars) * 60.0 / Double(p.totalDurationSeconds)) * 10).rounded() / 10
        }
        var maxSessionCPM: Double = 0
        var schemeCounts: [String: Int] = [:]
        var layoutCounts: [String: Int] = [:]
        var hourCounts: [String: Int] = [:]
        var confMatrix: [String: Int] = [:]

        for ev in events {
            if ev.durationSeconds >= 5 {
                let cpm = Double(ev.committedChars) * 60.0 / Double(ev.durationSeconds)
                if cpm > maxSessionCPM { maxSessionCPM = cpm }
            }
            schemeCounts[ev.schemeID, default: 0] += ev.committedChars
            layoutCounts[ev.layoutID, default: 0] += ev.committedChars
            let hKey = String(ev.activeHour)
            hourCounts[hKey, default: 0] += ev.committedChars
            for (k, v) in ev.confusionCounts where v > 0 {
                confMatrix[k, default: 0] += v
            }
        }

        p.peakCPM = (maxSessionCPM * 10).rounded() / 10
        p.avgWordLength = p.totalWords > 0 ? ((Double(p.totalChars) / Double(p.totalWords)) * 100).rounded() / 100 : 0
        p.backspaceRate = p.totalChars > 0 ? ((Double(totalDeletes) / Double(p.totalChars)) * 10000).rounded() / 10000 : 0
        p.undoLearnRate = p.totalWords > 0 ? ((Double(totalUndos) / Double(p.totalWords)) * 10000).rounded() / 10000 : 0
        p.glideRatio = p.totalWords > 0 ? ((Double(totalGlides) / Double(p.totalWords)) * 10000).rounded() / 10000 : 0
        p.typoCorrectionRate = p.totalWords > 0 ? ((Double(totalTypos) / Double(p.totalWords)) * 10000).rounded() / 10000 : 0
        p.confusionMatrix = confMatrix

        let personalWords = UserLexicon().allEntries(limit: 40).map(\.word) + CustomWordStore.load().map(\.word)
        p.domainAffinity = analyzeLexiconDomains(words: personalWords)

        p.schemeBreakdown = schemeCounts
        p.hourlyRhythm = hourCounts
        if let topScheme = schemeCounts.max(by: { $0.value < $1.value })?.key {
            p.primaryScheme = topScheme
        }
        if let topLayout = layoutCounts.max(by: { $0.value < $1.value })?.key {
            p.primaryLayout = topLayout
        }

        var aiStats: [String: (calls: Int, inC: Int, outC: Int, totalLat: Int)] = [:]
        for log in aiLogs {
            var cur = aiStats[log.feature] ?? (0, 0, 0, 0)
            cur.calls += 1
            cur.inC += log.inputChars
            cur.outC += log.outputChars
            cur.totalLat += log.latencyMs
            aiStats[log.feature] = cur
        }
        p.aiFeatureBreakdown = aiStats.mapValues { v in
            AIUsageFeatureStat(
                calls: v.calls,
                inputChars: v.inC,
                outputChars: v.outC,
                avgLatencyMs: v.calls > 0 ? v.totalLat / v.calls : 0
            )
        }

        var tags: [String] = []
        var recs: [TypingTuningRecommendation] = []

        let fuzzyMeta: [String: (label: String, key: String)] = [
            "zh_z": ("zh ↔ z 平翘舌", "fuzzy.zhZ"),
            "ch_c": ("ch ↔ c 平翘舌", "fuzzy.chC"),
            "sh_s": ("sh ↔ s 平翘舌", "fuzzy.shS"),
            "n_l": ("n ↔ l 鼻边音", "fuzzy.nl"),
            "an_ang": ("an ↔ ang 前后鼻音", "fuzzy.anAng"),
            "en_eng": ("en ↔ eng 前后鼻音", "fuzzy.enEng"),
            "in_ing": ("in ↔ ing 前后鼻音", "fuzzy.inIng"),
            "f_h": ("f ↔ h 唇齿音", "fuzzy.fh"),
            "huang_wang": ("huang ↔ wang 介音", "fuzzy.huangWang")
        ]
        for (pairKey, count) in confMatrix.sorted(by: { $0.value > $1.value }) {
            if count >= 2, let meta = fuzzyMeta[pairKey] {
                recs.append(TypingTuningRecommendation(
                    id: "fuzzy_\(pairKey)",
                    title: "建议专属开启『\(meta.label)模糊音』",
                    reason: "实时分析检测到您已累计出现 \(count) 次 \(meta.label) 混淆输入，开启后可直接首选命中。",
                    settingKey: meta.key
                ))
            }
        }

        if p.domainAffinity.primaryDomain != "综合通用" {
            tags.append("\(p.domainAffinity.primaryDomain)词库偏好")
        }

        let schemeDisplay = InputScheme(rawValue: p.primaryScheme)?.displayName ?? "全拼"
        if p.primaryScheme == "wubi86" {
            tags.append("五笔字根极客")
        } else if p.primaryScheme != "quanpin" {
            tags.append("\(schemeDisplay)高阶用户")
        } else {
            tags.append("全拼流式输入")
        }

        if p.avgCPM >= 150 || p.peakCPM >= 200 {
            tags.append("高速击键达人")
        } else if p.totalChars > 0 && p.backspaceRate <= 0.05 {
            tags.append("零误触精准派")
        }

        if p.avgWordLength >= 2.1 {
            tags.append("长句整输习惯")
            recs.append(TypingTuningRecommendation(
                id: "keep_bigram_prediction",
                title: "已适配『长句连打』习惯",
                reason: "您的平均上屏词长达 \(p.avgWordLength) 字/次，二元语法与上下文消歧可显著提升整句首选命中率。",
                settingKey: "bigramPredictionEnabled"
            ))
        } else if p.totalWords >= 5 {
            tags.append("短词快选节奏")
        }

        if p.glideRatio >= 0.15 {
            tags.append("滑行轨迹玩家")
        } else if p.primaryLayout == "qwerty26" && p.totalWords >= 10 {
            recs.append(TypingTuningRecommendation(
                id: "try_glide_typing",
                title: "建议尝试 26 键滑行输入",
                reason: "检测到您习惯 26 键点按输入，单手打字时在字母间连续滑行可提升约 25% 造句速度。",
                settingKey: "glideTypingEnabled"
            ))
        }

        if p.backspaceRate >= 0.10 || p.typoCorrectionRate >= 0.08 {
            tags.append("快节奏纠错依赖")
            let pct = ((p.backspaceRate * 1000).rounded() / 10)
            recs.append(TypingTuningRecommendation(
                id: "enable_dynamic_hitbox_and_fuzzy",
                title: "建议开启『动态热区防误触』与『模糊音兜底』",
                reason: "当前退格修改率为 \(pct)%，开启键缝动态吸附与 4 路错拼容错能减少约 35% 返工。",
                settingKey: "dynamicKeyHitBoxEnabled"
            ))
        }

        if p.undoLearnRate >= 0.05 {
            recs.append(TypingTuningRecommendation(
                id: "raise_auto_learn_threshold",
                title: "建议将『自造词学习阈值』调至 2 次",
                reason: "检测到您频繁使用『退格重选撤学』，将学习阈值设为 2 次可避免偶发误触词进入个人词库。",
                settingKey: "autoLearnThreshold"
            ))
        }

        let nightChars = [22, 23, 0, 1, 2, 3, 4].reduce(0) { $0 + (hourCounts[String($1)] ?? 0) }
        if p.totalChars > 0 && Double(nightChars) / Double(p.totalChars) >= 0.35 {
            tags.append("深夜高产创作者")
        } else if p.totalChars > 0 {
            tags.append("日间高效表达者")
        }

        let totalAICalls = p.aiFeatureBreakdown.values.reduce(0) { $0 + $1.calls }
        if totalAICalls > 0 {
            tags.append("AI 协同写作者")
            if let topFeature = p.aiFeatureBreakdown.max(by: { $0.value.calls < $1.value.calls })?.key {
                recs.append(TypingTuningRecommendation(
                    id: "ai_workflow_habit",
                    title: "高频 AI 技能偏好：\(topFeature)",
                    reason: "已累计分析 \(totalAICalls) 次 AI/翻译 API 交互，云端已记住您的语言与文风习惯。",
                    settingKey: "translateTargetLang"
                ))
            }
        }

        if recs.isEmpty {
            recs.append(TypingTuningRecommendation(
                id: "optimal_state",
                title: "当前输入引擎参数已处于最佳平衡态",
                reason: "您的击键准确率与上屏节奏表现优异，继续保持当前配置即可。",
                settingKey: "userLearningEnabled"
            ))
        }

        p.habitTags = tags
        p.tuningRecommendations = recs
        p.updatedAt = Int(Date().timeIntervalSince1970)
        return p
    }

    /// 分析个人词库与高频短语的领域偏好（与服务端 analyze_lexicon_habits 算法同构）。
    public static func analyzeLexiconDomains(words: [String], preferredTone: String = "自然流畅") -> LexiconDomainAffinity {
        let domainKeywords: [String: [String]] = [
            "科技与研发": ["代码", "接口", "部署", "服务器", "数据库", "算法", "模型", "前端", "后端", "架构", "测试", "编译", "函数", "并发", "灵犀"],
            "商务与职场": ["收到", "会议", "汇报", "方案", "进度", "合作", "排期", "辛苦", "确认", "合同", "客户", "需求", "复盘", "对齐"],
            "日常与社交": ["哈哈", "吃饭", "开心", "下班", "火锅", "奶茶", "周末", "晚安", "摸鱼", "快递", "朋友", "明天", "休息"],
            "学术与创作": ["研究", "分析", "论文", "文献", "逻辑", "结构", "实验", "论证", "摘要", "引用", "叙事", "章节"]
        ]
        let cleaned = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var scores: [String: Int] = [:]
        for w in cleaned {
            for (dom, kws) in domainKeywords where kws.contains(where: { w.contains($0) }) {
                scores[dom, default: 0] += 1
            }
        }
        let primary = scores.max(by: { $0.value < $1.value })?.key ?? "综合通用"
        let avgLen = cleaned.isEmpty ? 0.0 : ((Double(cleaned.reduce(0) { $0 + $1.count }) / Double(cleaned.count)) * 100).rounded() / 100
        return LexiconDomainAffinity(
            primaryDomain: primary,
            domainScores: scores,
            analyzedWordCount: cleaned.count,
            avgLexiconWordLength: avgLen,
            preferredTone: preferredTone,
            topTerms: Array(cleaned.prefix(12))
        )
    }

    /// 检测用户输入的原始拼音串与最终上屏词条标准拼音之间的易混音对（zh_z / an_ang / in_ing / n_l 等）。
    public static func detectPinyinConfusions(rawInput: String, resolvedPinyin: String) -> [String: Int] {
        let rawFlat = rawInput.lowercased().replacingOccurrences(of: "'", with: "")
        let targetSyls = resolvedPinyin.lowercased().split(separator: "'").map(String.init)
        let targetFlat = targetSyls.joined()
        guard !rawFlat.isEmpty, !targetFlat.isEmpty, rawFlat != targetFlat else { return [:] }

        var counts: [String: Int] = [:]
        if (targetFlat.contains("zh") && !rawFlat.contains("zh") && rawFlat.contains("z"))
            || (rawFlat.contains("zh") && !targetFlat.contains("zh") && targetFlat.contains("z")) {
            counts["zh_z", default: 0] += 1
        }
        if (targetFlat.contains("ch") && !rawFlat.contains("ch") && rawFlat.contains("c"))
            || (rawFlat.contains("ch") && !targetFlat.contains("ch") && targetFlat.contains("c")) {
            counts["ch_c", default: 0] += 1
        }
        if (targetFlat.contains("sh") && !rawFlat.contains("sh") && rawFlat.contains("s"))
            || (rawFlat.contains("sh") && !targetFlat.contains("sh") && targetFlat.contains("s")) {
            counts["sh_s", default: 0] += 1
        }
        if (targetFlat.contains("ang") && !rawFlat.contains("ang") && rawFlat.contains("an"))
            || (rawFlat.contains("ang") && !targetFlat.contains("ang") && targetFlat.contains("an")) {
            counts["an_ang", default: 0] += 1
        }
        if (targetFlat.contains("eng") && !rawFlat.contains("eng") && rawFlat.contains("en"))
            || (rawFlat.contains("eng") && !targetFlat.contains("eng") && targetFlat.contains("en")) {
            counts["en_eng", default: 0] += 1
        }
        if (targetFlat.contains("ing") && !rawFlat.contains("ing") && rawFlat.contains("in"))
            || (rawFlat.contains("ing") && !targetFlat.contains("ing") && targetFlat.contains("in")) {
            counts["in_ing", default: 0] += 1
        }
        if (targetFlat.hasPrefix("n") && rawFlat.hasPrefix("l"))
            || (targetFlat.hasPrefix("l") && rawFlat.hasPrefix("n")) {
            counts["n_l", default: 0] += 1
        }
        if (targetFlat.hasPrefix("f") && rawFlat.hasPrefix("h"))
            || (targetFlat.hasPrefix("h") && rawFlat.hasPrefix("f")) {
            counts["f_h", default: 0] += 1
        }
        if (targetFlat.contains("huang") && rawFlat.contains("wang"))
            || (targetFlat.contains("wang") && rawFlat.contains("huang")) {
            counts["huang_wang", default: 0] += 1
        }
        return counts
    }

    /// 生成供 AI 写作助手与边打边译自动注入的「用户个人打字与用词习惯画像」上下文。
    public func personalHabitSystemPromptSuffix() -> String {
        let p = currentProfile()
        var parts: [String] = []
        if !p.habitTags.isEmpty {
            parts.append("用户打字画像标签：\(p.habitTags.joined(separator: "、"))")
        }
        if p.domainAffinity.primaryDomain != "综合通用" {
            parts.append("常用词汇领域偏好：\(p.domainAffinity.primaryDomain)")
        }
        if !p.domainAffinity.topTerms.isEmpty {
            parts.append("个人高频习惯词汇：\(p.domainAffinity.topTerms.prefix(6).joined(separator: "、"))")
        }
        if p.avgWordLength >= 2.2 {
            parts.append("句式节奏偏好：习惯连贯长句表达")
        } else if p.totalWords >= 5 {
            parts.append("句式节奏偏好：习惯短促精炼表达")
        }
        guard !parts.isEmpty else { return "" }
        return "【灵犀打字习惯数据库画像】" + parts.joined(separator: "；") + "。请在生成或润色时自然贴合该用户的用词习惯与表达节奏。"
    }
}

// MARK: - 云端 HTTP 客户端与协议层真实实现 (AuthService / SyncService / InsightService)

public enum CloudBackendError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized(String)
    case badRequest(String)
    case serverError(String)
    case networkFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "后端服务地址格式无效"
        case .unauthorized(let msg): return msg
        case .badRequest(let msg): return msg
        case .serverError(let msg): return msg
        case .networkFailure(let msg): return msg
        }
    }
}

/// 端侧离线加密账号库（无自建服务器或侧载安装时，直接在 iPhone 上完成加盐哈希注册与登录，永不因无后端而卡死）。
private enum LocalAccountVault {
    private static let fileName = "lingxi_local_accounts.json"

    struct Record: Codable, Equatable {
        var userID: String
        var email: String
        var username: String
        var passwordSalt: String
        var passwordHash: String
        var e2eeSalt: String
        var createdAt: Date
    }

    static func loadAll() -> [Record] {
        AppGroup.readJSON([Record].self, from: fileName) ?? []
    }

    private static func saveAll(_ list: [Record]) {
        _ = AppGroup.writeJSON(list, to: fileName, protected: true)
    }

    private static func hashPassword(_ password: String, salt: String) -> String {
        let digest = SHA256.hash(data: Data((salt + "|" + password).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func register(email: String, username: String, password: String) throws -> Record {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanEmail.contains("@"), cleanEmail.count >= 5 else {
            throw CloudBackendError.badRequest("请输入有效的邮箱地址")
        }
        guard password.count >= 6 else {
            throw CloudBackendError.badRequest("密码长度不能少于 6 位")
        }
        var all = loadAll()
        if all.contains(where: { $0.email == cleanEmail }) {
            throw CloudBackendError.badRequest("该邮箱已在本机注册，请直接切换「登录」")
        }
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let e2ee = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let cleanName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = cleanEmail.components(separatedBy: "@").first ?? "灵犀用户"
        let rec = Record(
            userID: "local-" + UUID().uuidString.lowercased(),
            email: cleanEmail,
            username: cleanName.isEmpty ? fallbackName : cleanName,
            passwordSalt: salt,
            passwordHash: hashPassword(password, salt: salt),
            e2eeSalt: e2ee,
            createdAt: Date()
        )
        all.append(rec)
        saveAll(all)
        return rec
    }

    static func mirrorServerAccount(userID: String, email: String, username: String, password: String, e2eeSalt: String) {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanEmail.isEmpty, !password.isEmpty else { return }
        var all = loadAll()
        all.removeAll { $0.email == cleanEmail }
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let rec = Record(
            userID: userID,
            email: cleanEmail,
            username: username,
            passwordSalt: salt,
            passwordHash: hashPassword(password, salt: salt),
            e2eeSalt: e2eeSalt,
            createdAt: Date()
        )
        all.append(rec)
        saveAll(all)
    }

    static func authenticate(account: String, password: String) throws -> Record {
        let clean = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty, !password.isEmpty else {
            throw CloudBackendError.badRequest("请输入邮箱和密码")
        }
        let all = loadAll()
        guard let rec = all.first(where: { $0.email == clean || $0.username.lowercased() == clean }) else {
            throw CloudBackendError.unauthorized("未连接自建云端，且本机尚未注册该账号；请点「免费注册」或「一键创建本机账号」立即登录。")
        }
        guard hashPassword(password, salt: rec.passwordSalt) == rec.passwordHash else {
            throw CloudBackendError.unauthorized("密码不正确，请重新输入")
        }
        return rec
    }

    static func upsertQuick(username: String, email: String) -> Record {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        var all = loadAll()
        if let existing = all.first(where: { $0.email == cleanEmail }) {
            return existing
        }
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let e2ee = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let rec = Record(
            userID: "local-" + UUID().uuidString.lowercased(),
            email: cleanEmail,
            username: cleanName.isEmpty ? "灵犀用户" : cleanName,
            passwordSalt: salt,
            passwordHash: "",
            e2eeSalt: e2ee,
            createdAt: Date()
        )
        all.append(rec)
        saveAll(all)
        return rec
    }
}

/// 灵犀云端全栈客户端：同时实现 `AuthService`、`SyncService` 与 `InsightService`。
public final class CloudBackendClient: AuthService, SyncService, InsightService {
    public static let shared = CloudBackendClient()

    private let urlSession: URLSession

    public init(timeout: TimeInterval = 12) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout * 2
        self.urlSession = URLSession(configuration: cfg)
    }

    // MARK: AuthService

    public var currentSession: AuthSession? {
        CloudCredentialStore.loadSession()
    }

    public var activeAPIKey: String? {
        CloudCredentialStore.loadAPIKey()
    }

    public var isAuthenticatedOrHasAPIKey: Bool {
        if let s = currentSession, !s.accessToken.isEmpty { return true }
        if let k = activeAPIKey, !k.isEmpty { return true }
        return false
    }

    /// 邮箱 + 用户名 + 密码注册（优先连接自建/云端服务器；若未部署服务器或网络不可达，自动在本机创建加盐加密账号）
    @discardableResult
    public func register(email: String, username: String, password: String) async throws -> AuthSession {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEmail.contains("@"), cleanEmail.count >= 5 else {
            throw CloudBackendError.badRequest("请输入有效的邮箱地址")
        }
        guard password.count >= 6 else {
            throw CloudBackendError.badRequest("密码长度不能少于 6 位")
        }

        let payload: [String: Any] = [
            "email": cleanEmail,
            "username": cleanName.isEmpty ? (cleanEmail.components(separatedBy: "@").first ?? "灵犀用户") : cleanName,
            "password": password,
            "deviceID": SyncInfra.deviceIdentity().deviceID
        ]
        do {
            let dict = try await requestJSON(method: "POST", path: "/api/v1/auth/register", body: payload, requireAuth: false)
            let session = try persistAuthResponse(dict, isLocalOnly: false)
            let cfg = CloudBackendConfig.load()
            LocalAccountVault.mirrorServerAccount(
                userID: session.userID,
                email: cfg.email,
                username: cfg.username,
                password: password,
                e2eeSalt: cfg.e2eeSalt
            )
            return session
        } catch CloudBackendError.networkFailure {
            let localRec = try LocalAccountVault.register(email: cleanEmail, username: cleanName, password: password)
            return persistLocalSession(for: localRec)
        }
    }

    /// 邮箱/用户名 + 密码登录（优先连接云端；若未连服务器自动校验本机加密账号库）
    @discardableResult
    public func login(account: String, password: String) async throws -> AuthSession {
        let cleanAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccount.isEmpty, !password.isEmpty else {
            throw CloudBackendError.badRequest("请输入邮箱地址和密码")
        }
        let payload: [String: Any] = [
            "account": cleanAccount,
            "password": password,
            "deviceID": SyncInfra.deviceIdentity().deviceID
        ]
        do {
            let dict = try await requestJSON(method: "POST", path: "/api/v1/auth/login", body: payload, requireAuth: false)
            let session = try persistAuthResponse(dict, isLocalOnly: false)
            let cfg = CloudBackendConfig.load()
            LocalAccountVault.mirrorServerAccount(
                userID: session.userID,
                email: cfg.email,
                username: cfg.username,
                password: password,
                e2eeSalt: cfg.e2eeSalt
            )
            return session
        } catch CloudBackendError.networkFailure {
            let localRec = try LocalAccountVault.authenticate(account: cleanAccount, password: password)
            return persistLocalSession(for: localRec)
        }
    }

    /// 一键创建/登录本机加密账号（无需服务器、无需 Apple 付费签名，iPhone 装完即可用头像与个人档案）
    @discardableResult
    public func createQuickLocalAccount(username: String = "灵犀用户", email: String = "local@lingxi.ime") -> AuthSession {
        let rec = LocalAccountVault.upsertQuick(username: username, email: email)
        return persistLocalSession(for: rec)
    }

    public func signInWithApple(identityToken: Data, user: String) async throws -> AuthSession {
        let payload: [String: Any] = [
            "identityToken": identityToken.base64EncodedString(),
            "user": user,
            "deviceID": SyncInfra.deviceIdentity().deviceID
        ]
        do {
            let dict = try await requestJSON(method: "POST", path: "/api/v1/auth/apple", body: payload, requireAuth: false)
            return try persistAuthResponse(dict, isLocalOnly: false)
        } catch CloudBackendError.networkFailure {
            let suffix = String(user.prefix(6))
            let rec = LocalAccountVault.upsertQuick(username: "灵犀用户", email: "apple-\(suffix)@lingxi.local")
            return persistLocalSession(for: rec)
        }
    }

    private func persistLocalSession(for rec: LocalAccountVault.Record) -> AuthSession {
        let session = AuthSession(
            userID: rec.userID,
            accessToken: "lx_local_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            refreshToken: "lx_local_ref_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            accessExpiry: Date().addingTimeInterval(3600 * 24 * 365)
        )
        CloudCredentialStore.saveSession(session)
        var cfg = CloudBackendConfig.load()
        cfg.userID = rec.userID
        cfg.email = rec.email
        cfg.username = rec.username
        cfg.e2eeSalt = rec.e2eeSalt
        cfg.isLocalOnlyAccount = true
        cfg.save()
        return session
    }

    public func refreshIfNeeded() async throws -> AuthSession? {
        guard let session = currentSession else { return nil }
        guard session.needsRefresh else { return session }
        let payload: [String: Any] = ["refreshToken": session.refreshToken]
        let dict = try await requestJSON(method: "POST", path: "/api/v1/auth/refresh", body: payload, requireAuth: false)
        return try persistAuthResponse(dict)
    }

    /// 生成或轮换客户专属 API Key (lx_live_...)
    public func rotateAPIKey() async throws -> String {
        let dict = try await requestJSON(method: "POST", path: "/api/v1/auth/api-key/rotate", body: [:], requireAuth: true)
        guard let newKey = dict["apiKey"] as? String, !newKey.isEmpty else {
            throw CloudBackendError.serverError("服务端未返回有效 API Key")
        }
        CloudCredentialStore.saveAPIKey(newKey)
        var cfg = CloudBackendConfig.load()
        cfg.apiKeyPrefix = (dict["apiKeyPrefix"] as? String) ?? String(newKey.prefix(16)) + "..."
        cfg.save()
        return newKey
    }

    public func signOut() async {
        CloudCredentialStore.clearAll()
        var cfg = CloudBackendConfig.load()
        cfg.userID = ""
        cfg.email = ""
        cfg.username = ""
        cfg.apiKeyPrefix = ""
        cfg.isLocalOnlyAccount = false
        cfg.save()
    }

    private func persistAuthResponse(_ dict: [String: Any], isLocalOnly: Bool = false) throws -> AuthSession {
        guard let userID = dict["userID"] as? String,
              let accessToken = dict["accessToken"] as? String,
              let refreshToken = dict["refreshToken"] as? String else {
            throw CloudBackendError.serverError("认证响应缺少必要字段")
        }
        let expSeconds = (dict["accessExpiry"] as? NSNumber)?.doubleValue ?? Date().addingTimeInterval(86400).timeIntervalSince1970
        let session = AuthSession(
            userID: userID,
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessExpiry: Date(timeIntervalSince1970: expSeconds)
        )
        CloudCredentialStore.saveSession(session)
        if let rawAPIKey = dict["apiKey"] as? String, !rawAPIKey.isEmpty {
            CloudCredentialStore.saveAPIKey(rawAPIKey)
        }
        var cfg = CloudBackendConfig.load()
        cfg.userID = userID
        cfg.email = (dict["email"] as? String) ?? cfg.email
        cfg.username = (dict["username"] as? String) ?? cfg.username
        cfg.apiKeyPrefix = (dict["apiKeyPrefix"] as? String) ?? cfg.apiKeyPrefix
        cfg.e2eeSalt = (dict["e2eeSalt"] as? String) ?? cfg.e2eeSalt
        cfg.isLocalOnlyAccount = isLocalOnly
        cfg.save()
        return session
    }

    // MARK: SyncService (LWW 重要数据云同步 + SyncCrypto E2EE 端到端加密)

    private static let e2eeMagicHeader = Data("LXE1".utf8)

    /// 从用户专属 e2eeSalt + 身份标识派生 AES-256-GCM 端到端同步密钥
    private func activeE2EESyncKey() -> Data? {
        let cfg = CloudBackendConfig.load()
        let salt = cfg.e2eeSalt.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = cfg.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !salt.isEmpty {
            return Data((salt + "|" + uid).utf8)
        }
        if let apiKey = activeAPIKey, !apiKey.isEmpty {
            return Data(("lingxi-e2ee|" + apiKey).utf8)
        }
        return nil
    }

    private func sealPayloadIfPossible(_ plaintext: Data) -> Data {
        guard !plaintext.isEmpty,
              !plaintext.starts(with: Self.e2eeMagicHeader),
              let material = activeE2EESyncKey() else {
            return plaintext
        }
        let key = SyncCrypto.deriveSyncKey(from: material)
        if let sealed = try? SyncCrypto.seal(plaintext, key: key) {
            return Self.e2eeMagicHeader + sealed
        }
        return plaintext
    }

    private func openPayloadIfNeeded(_ payload: Data) -> Data {
        guard payload.starts(with: Self.e2eeMagicHeader) else {
            return payload
        }
        let body = payload.dropFirst(Self.e2eeMagicHeader.count)
        guard let material = activeE2EESyncKey() else {
            return payload
        }
        let key = SyncCrypto.deriveSyncKey(from: material)
        return (try? SyncCrypto.open(Data(body), key: key)) ?? payload
    }

    public func pull(namespace: SyncNamespace, since: UInt64) async throws -> SyncPage {
        guard isAuthenticatedOrHasAPIKey else {
            return SyncPage(changes: [], nextCursor: since, hasMore: false)
        }
        let path = "/api/v1/sync/pull?namespace=\(namespace.rawValue)&since=\(since)&limit=100"
        let dict = try await requestJSON(method: "GET", path: path, body: nil, requireAuth: true)
        let rawChanges = (dict["changes"] as? [[String: Any]]) ?? []
        let nextCursor = (dict["nextCursor"] as? NSNumber)?.uint64Value ?? since
        let hasMore = (dict["hasMore"] as? Bool) ?? false

        let changes: [SyncChange] = rawChanges.compactMap { item in
            guard let ns = item["namespace"] as? String,
                  let key = item["key"] as? String,
                  let b64 = item["ciphertext"] as? String,
                  let rawData = Data(base64Encoded: b64) else {
                return nil
            }
            let openedData = openPayloadIfNeeded(rawData)
            let ts = (item["lamportTS"] as? NSNumber)?.uint64Value ?? 0
            let dev = (item["deviceID"] as? String) ?? ""
            let tomb = (item["tombstone"] as? Bool) ?? false
            let ver = (item["schemaVersion"] as? NSNumber)?.intValue ?? 1
            return SyncChange(
                namespace: SyncNamespace(rawValue: ns),
                key: key,
                ciphertext: openedData,
                lamportTS: ts,
                deviceID: dev,
                tombstone: tomb,
                schemaVersion: ver
            )
        }
        return SyncPage(changes: changes, nextCursor: nextCursor, hasMore: hasMore)
    }

    public func push(_ changes: [SyncChange]) async throws -> [SyncConflict] {
        guard isAuthenticatedOrHasAPIKey else { return [] }
        let serialized: [[String: Any]] = changes.map { c in
            let encrypted = c.tombstone ? c.ciphertext : sealPayloadIfPossible(c.ciphertext)
            return [
                "namespace": c.namespace.rawValue,
                "key": c.key,
                "ciphertext": encrypted.base64EncodedString(),
                "lamportTS": c.lamportTS,
                "deviceID": c.deviceID,
                "tombstone": c.tombstone,
                "schemaVersion": c.schemaVersion
            ]
        }
        let dict = try await requestJSON(
            method: "POST",
            path: "/api/v1/sync/push",
            body: ["changes": serialized],
            requireAuth: true
        )
        let rawConflicts = (dict["conflicts"] as? [[String: Any]]) ?? []
        return rawConflicts.compactMap { item in
            guard let ns = item["namespace"] as? String,
                  let key = item["key"] as? String,
                  let srv = item["serverRecord"] as? [String: Any],
                  let b64 = srv["ciphertext"] as? String,
                  let rawData = Data(base64Encoded: b64) else {
                return nil
            }
            let openedData = openPayloadIfNeeded(rawData)
            let record = SyncChange(
                namespace: SyncNamespace(rawValue: ns),
                key: key,
                ciphertext: openedData,
                lamportTS: (srv["lamportTS"] as? NSNumber)?.uint64Value ?? 0,
                deviceID: (srv["deviceID"] as? String) ?? "",
                tombstone: (srv["tombstone"] as? Bool) ?? false,
                schemaVersion: (srv["schemaVersion"] as? NSNumber)?.intValue ?? 1
            )
            return SyncConflict(namespace: SyncNamespace(rawValue: ns), key: key, serverRecord: record)
        }
    }

    /// 执行全量重要数据（设置/皮肤/自定义短语/个人词库）云同步 + 打字习惯实时分析同步。
    @discardableResult
    public func syncAllImportantDataAndHabits() async throws -> SyncRunReport {
        let engine = SyncEngine(
            sync: self,
            source: SyncEngine.makeFullSyncSource()
        )
        let report = try await engine.syncNow()
        _ = try? await syncTypingHabitsWithServer()

        var cfg = CloudBackendConfig.load()
        cfg.lastSyncedAt = Date()
        cfg.lastSyncSummary = "推送 \(report.pushed) 项 · 拉取 \(report.pulled) 项 · 应用 \(report.applied) 项"
        cfg.save()
        return report
    }

    // MARK: InsightService & 实时打字习惯 API 分析

    public var isAuthorized: Bool {
        CloudBackendConfig.load().habitAnalysisEnabled && isAuthenticatedOrHasAPIKey
    }

    public func submit(_ digests: [TypingSessionDigest]) async throws {
        guard isAuthorized, !digests.isEmpty else { return }
        let payloads: [TypingHabitEventPayload] = digests.map { d in
            let schemeID = InputScheme.allCases.indices.contains(d.schemeIndex)
                ? InputScheme.allCases[d.schemeIndex].rawValue
                : "quanpin"
            let layoutID = KeyboardLayoutMode.allCases.indices.contains(d.layoutIndex)
                ? KeyboardLayoutMode.allCases[d.layoutIndex].rawValue
                : "qwerty26"
            return TypingHabitEventPayload(
                startedAt: Int(d.startedAt.timeIntervalSince1970),
                durationSeconds: d.durationSeconds,
                committedChars: d.committedChars,
                committedWords: d.committedWords,
                deleteCount: d.deleteCount,
                schemeID: schemeID,
                layoutID: layoutID
            )
        }
        for p in payloads {
            _ = TypingHabitTracker.shared.recordTypingEvent(p)
        }
        _ = try await syncTypingHabitsWithServer()
    }

    /// 将本地待上报的打字习惯事件流与 AI API 调用日志实时推送到后端分析引擎，并拉取服务器最新画像。
    @discardableResult
    public func syncTypingHabitsWithServer() async throws -> UserTypingHabitProfile {
        guard isAuthenticatedOrHasAPIKey else {
            return TypingHabitTracker.shared.currentProfile()
        }

        let pendingEvents = TypingHabitTracker.shared.pendingEvents()
        if !pendingEvents.isEmpty {
            let encoded = try JSONEncoder().encode(pendingEvents)
            let rawList = (try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]]) ?? []
            let res = try await requestJSON(
                method: "POST",
                path: "/api/v1/analytics/typing-events",
                body: ["digests": rawList],
                requireAuth: true
            )
            TypingHabitTracker.shared.clearPendingEvents()
            if let profDict = res["profile"] as? [String: Any],
               let prof = decodeProfile(from: profDict) {
                TypingHabitTracker.shared.saveServerProfile(prof)
            }
        }

        let pendingAI = TypingHabitTracker.shared.pendingAILogs()
        for aiLog in pendingAI {
            let encoded = try JSONEncoder().encode(aiLog)
            if let bodyDict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
                _ = try? await requestJSON(
                    method: "POST",
                    path: "/api/v1/analytics/api-usage",
                    body: bodyDict,
                    requireAuth: true
                )
            }
        }
        if !pendingAI.isEmpty {
            TypingHabitTracker.shared.clearPendingAILogs()
        }

        // 同步分析个人词库与高频短语的领域偏好 (科技/商务/日常/学术)
        let lexiconWords = UserLexicon().allEntries(limit: 40).map(\.word) + CustomWordStore.load().map(\.word)
        if !lexiconWords.isEmpty {
            let tone = LingxiSettings.load().translateFormalTone ? "正式专业" : "自然口语"
            _ = try? await requestJSON(
                method: "POST",
                path: "/api/v1/analytics/lexicon-habits",
                body: ["words": lexiconWords, "preferredTone": tone],
                requireAuth: true
            )
        }

        let dict = try await requestJSON(method: "GET", path: "/api/v1/analytics/habits", body: nil, requireAuth: true)
        if let profile = decodeProfile(from: dict) {
            TypingHabitTracker.shared.saveServerProfile(profile)
            return profile
        }
        return TypingHabitTracker.shared.currentProfile()
    }

    public func deleteServerHabits() async throws -> UserTypingHabitProfile {
        TypingHabitTracker.shared.clearAllLocalHabits()
        guard isAuthenticatedOrHasAPIKey else {
            return TypingHabitTracker.shared.currentProfile()
        }
        let dict = try await requestJSON(method: "DELETE", path: "/api/v1/analytics/habits", body: nil, requireAuth: true)
        if let profDict = dict["profile"] as? [String: Any], let prof = decodeProfile(from: profDict) {
            TypingHabitTracker.shared.saveServerProfile(prof)
            return prof
        }
        return TypingHabitTracker.shared.currentProfile()
    }

    public func checkServerHealth() async throws -> [String: Any] {
        try await requestJSON(method: "GET", path: "/api/v1/health", body: nil, requireAuth: false)
    }

    /// L2 密钥学：修改账号密码并轮换服务端 E2EE 派生盐，随后触发全量密文重加密同步
    public func changePasswordAndRotateKey(newPassword: String) async throws -> String {
        guard newPassword.count >= 8 else {
            throw CloudBackendError.badRequest("新密码长度不能少于 8 位")
        }
        let dict = try await requestJSON(
            method: "POST",
            path: "/api/v1/auth/password/change",
            body: ["newPassword": newPassword],
            requireAuth: true
        )
        let newSalt = dict["newE2eeSalt"] as? String ?? ""
        if !newSalt.isEmpty {
            var cfg = CloudBackendConfig.load()
            cfg.e2eeSalt = newSalt
            cfg.save()
            // 清空同步账本游标，触发用新盐派生的密钥全量重加密推送
            SyncLedgerStore().save(SyncLedger())
            _ = try? await syncAllImportantDataAndHabits()
        }
        return newSalt
    }

    /// 第六部分 PIPL/GDPR：向服务端写入不可变授权审计流水 (`consent_records`)
    public func syncConsentToServer(scope: String, granted: Bool, policyVersion: String = "2026.11-v1") async {
        ComplianceService.shared.recordConsent(scope: scope, granted: granted, policyVersion: policyVersion)
        guard isAuthenticatedOrHasAPIKey else { return }
        _ = try? await requestJSON(
            method: "POST",
            path: "/api/v1/compliance/consent",
            body: ["scope": scope, "granted": granted, "policyVersion": policyVersion],
            requireAuth: true
        )
    }

    /// 第六部分 PIPL/GDPR：一键注销云端账号并级联物理删除所有同步密文、会话与画像数据
    public func deleteCloudAccountCascade() async throws {
        if isAuthenticatedOrHasAPIKey {
            _ = try await requestJSON(method: "DELETE", path: "/api/v1/compliance/account", body: nil, requireAuth: true)
        }
        TypingHabitTracker.shared.clearAllLocalHabits()
        await signOut()
    }

    private func decodeProfile(from dict: [String: Any]) -> UserTypingHabitProfile? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(UserTypingHabitProfile.self, from: data)
    }

    // MARK: 底层 HTTP 请求

    private func requestJSON(
        method: String,
        path: String,
        body: [String: Any]?,
        requireAuth: Bool,
        allowRetryOn401: Bool = true
    ) async throws -> [String: Any] {
        if requireAuth, path != "/api/v1/auth/refresh", let session = currentSession, session.needsRefresh {
            _ = try? await refreshIfNeeded()
        }

        let baseURL = CloudBackendConfig.load().normalizedBaseURL
        guard let url = URL(string: baseURL + path) else {
            throw CloudBackendError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var rawBodyData = Data()
        if let body {
            rawBodyData = try JSONSerialization.data(withJSONObject: body)
            req.httpBody = rawBodyData
        }

        if requireAuth {
            if let apiKey = activeAPIKey, !apiKey.isEmpty {
                req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
                let ts = Int(Date().timeIntervalSince1970)
                let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                let sig = SyncCrypto.signRequest(body: rawBodyData, timestamp: ts, nonce: nonce, secret: apiKey)
                req.setValue(String(ts), forHTTPHeaderField: "X-Lingxi-Timestamp")
                req.setValue(nonce, forHTTPHeaderField: "X-Lingxi-Nonce")
                req.setValue(sig, forHTTPHeaderField: "X-Lingxi-Signature")
            }
            if let session = currentSession, !session.accessToken.isEmpty {
                req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            }
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: req)
        } catch {
            throw CloudBackendError.networkFailure("无法连接后端服务器 (\(baseURL))：\(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw CloudBackendError.networkFailure("无效的服务器响应")
        }

        let jsonObj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (200...299).contains(http.statusCode) {
            return jsonObj
        }

        if http.statusCode == 401, requireAuth, allowRetryOn401, let session = currentSession, !session.refreshToken.isEmpty {
            let payload: [String: Any] = ["refreshToken": session.refreshToken]
            if let refreshedDict = try? await requestJSON(method: "POST", path: "/api/v1/auth/refresh", body: payload, requireAuth: false, allowRetryOn401: false),
               (try? persistAuthResponse(refreshedDict)) != nil {
                return try await requestJSON(method: method, path: path, body: body, requireAuth: requireAuth, allowRetryOn401: false)
            }
        }

        let errMsg = ((jsonObj["error"] as? [String: Any])?["message"] as? String)
            ?? "HTTP \(http.statusCode)"
        if http.statusCode == 401 {
            throw CloudBackendError.unauthorized(errMsg)
        } else if http.statusCode == 400 {
            throw CloudBackendError.badRequest(errMsg)
        } else {
            throw CloudBackendError.serverError(errMsg)
        }
    }
}
