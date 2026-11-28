import Foundation

/// 免费个人 Apple ID 侧载跨进程配置桥接器：
/// - 当本机 App Group 共享容器正常可用（`AppGroup.isAvailable == true`）时，本模块完全静默休眠（零联网）；
/// - 仅当检测到免费侧载签名剥离了 App Group（`!AppGroup.isAvailable`）且用户已在主 App 登录国内直连云端、
///   并显式开启键盘「允许完全访问」配对后，才通过已加密的 LXE1 云端同步通道在主 App 与键盘之间同步：
///   外观主题 (`theme`)、全局设置 (`settings`)、脱敏打字字数统计 (`typing_stats`) 与快捷短语，绝不上传任何打字原文。
public enum SideloadConfigBridge {
    public static let tokenPrefix = "LXBRIDGE1:"
    private static let stateFileName = "lingxi_sideload_bridge.json"

    public struct PairingPayload: Codable, Equatable {
        public let serverBaseURL: String
        public let userID: String
        public let username: String
        public let email: String
        public let apiKey: String
        public let e2eeSalt: String
        /// 本机剪贴板直传快照（仅在同机主 App → 键盘扩展间一次性中转，不经服务器明文传输）
        public let aiConfigJSON: Data?
        public let themeJSON: Data?
        public let settingsJSON: Data?
        /// 免费侧载无 App Group 时的跨沙盒核心资料快照：个人速填名片、自定义短语与 Obsidian 个人记忆笔记
        public let personalCardsJSON: Data?
        public let customWordsJSON: Data?
        public let vaultNotesJSON: Data?

        public init(
            serverBaseURL: String,
            userID: String,
            username: String,
            email: String,
            apiKey: String,
            e2eeSalt: String,
            aiConfigJSON: Data? = nil,
            themeJSON: Data? = nil,
            settingsJSON: Data? = nil,
            personalCardsJSON: Data? = nil,
            customWordsJSON: Data? = nil,
            vaultNotesJSON: Data? = nil
        ) {
            self.serverBaseURL = serverBaseURL
            self.userID = userID
            self.username = username
            self.email = email
            self.apiKey = apiKey
            self.e2eeSalt = e2eeSalt
            self.aiConfigJSON = aiConfigJSON
            self.themeJSON = themeJSON
            self.settingsJSON = settingsJSON
            self.personalCardsJSON = personalCardsJSON
            self.customWordsJSON = customWordsJSON
            self.vaultNotesJSON = vaultNotesJSON
        }
    }

    public struct BridgeState: Codable, Equatable {
        public var isPaired: Bool = false
        public var lastSyncedAt: Date?
        public var lastSummary: String = ""
    }

    public static func loadState() -> BridgeState {
        AppGroup.readJSON(BridgeState.self, from: stateFileName) ?? BridgeState()
    }

    private static func saveState(_ state: BridgeState) {
        _ = AppGroup.writeJSON(state, to: stateFileName, protected: true)
    }

    public static var isPairedInThisProcess: Bool {
        loadState().isPaired && CloudBackendClient.shared.isRealCloudAuthenticated
    }

    /// 主 App 生成供键盘一键认领的加密云同步 + 本机 AI/外观/设置直传配对串（含云端凭证时同时打通持续云同步）。
    public static func exportPairingTokenFromMainApp() -> String? {
        guard CloudBackendClient.shared.isRealCloudAuthenticated,
              let apiKey = CloudCredentialStore.loadAPIKey(),
              !apiKey.isEmpty else {
            return nil
        }
        let cfg = CloudBackendConfig.load()
        guard !cfg.userID.isEmpty else { return nil }
        return encodePairingToken(
            serverBaseURL: cfg.normalizedBaseURL,
            userID: cfg.userID,
            username: cfg.username,
            email: cfg.email,
            apiKey: apiKey,
            e2eeSalt: cfg.e2eeSalt,
            includeLocalSnapshots: true
        )
    }

    /// 即使未登录云端，也支持将主 App 的 AI 密钥/模型 + 外观 + 设置打包为同机一次性直传口令（供免费侧载键盘零门槛同步 AI）。
    public static func exportLocalConfigHandoffTokenFromMainApp() -> String? {
        if let full = exportPairingTokenFromMainApp() {
            return full
        }
        return encodePairingToken(
            serverBaseURL: "",
            userID: "",
            username: "",
            email: "",
            apiKey: "",
            e2eeSalt: "",
            includeLocalSnapshots: true
        )
    }

    private static func encodePairingToken(
        serverBaseURL: String,
        userID: String,
        username: String,
        email: String,
        apiKey: String,
        e2eeSalt: String,
        includeLocalSnapshots: Bool
    ) -> String? {
        var aiData: Data?
        var themeData: Data?
        var settingsData: Data?
        var cardsData: Data?
        var customWordsData: Data?
        var vaultNotesData: Data?
        if includeLocalSnapshots {
            let encoder = JSONEncoder()
            var aiSnap = AIConfig.load()
            // 避免把数百条远端模型列表塞入剪贴板口令；同时若已绑定容灾兜底渠道，则保留该条精简备用档案，确保侧载键盘自动容灾可用
            aiSnap.fetchedModels = []
            if let fid = aiSnap.failoverProfileID, !fid.isEmpty,
               var failoverProf = aiSnap.profiles.first(where: { $0.id == fid }) {
                failoverProf.fetchedModels = []
                aiSnap.profiles = [failoverProf]
            } else {
                aiSnap.profiles = []
            }
            aiData = try? encoder.encode(aiSnap)
            themeData = try? encoder.encode(ThemeCustomization.load(force: true))
            settingsData = try? encoder.encode(LingxiSettings.load(force: true))

            let cards = Array(PersonalFillCardStore.load().prefix(24))
            if !cards.isEmpty {
                cardsData = try? encoder.encode(cards)
            }
            let cWords = Array(CustomWordStore.load(force: true).prefix(120))
            if !cWords.isEmpty {
                customWordsData = try? encoder.encode(cWords)
            }
            let vaultNotes = AICognitiveMemoryDB.shared.fetchVaultNotes(limit: 40)
            if !vaultNotes.isEmpty {
                vaultNotesData = try? encoder.encode(vaultNotes)
            }
        }
        let payload = PairingPayload(
            serverBaseURL: serverBaseURL,
            userID: userID,
            username: username,
            email: email,
            apiKey: apiKey,
            e2eeSalt: e2eeSalt,
            aiConfigJSON: aiData,
            themeJSON: themeData,
            settingsJSON: settingsData,
            personalCardsJSON: cardsData,
            customWordsJSON: customWordsData,
            vaultNotesJSON: vaultNotesData
        )
        guard let rawJSON = try? JSONEncoder().encode(payload) else { return nil }
        // 超 2KB 时启用苹果原生零依赖 LZFSE 压缩（带 4 字节 LZFS 魔数），使携带 40 篇 Obsidian 笔记与名片的口令依旧短小轻快
        let wireData: Data
        if rawJSON.count > 2048,
           let compressed = try? (rawJSON as NSData).compressed(using: .lzfse) as Data,
           compressed.count + 4 < rawJSON.count {
            var framed = Data("LZFS".utf8)
            framed.append(compressed)
            wireData = framed
        } else {
            wireData = rawJSON
        }
        let b64u = wireData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return tokenPrefix + b64u
    }

    /// 键盘端解析并落地主 App 复制过来的 `LXBRIDGE1:...` 配对串（纯字符串，兼容明文 JSON 与 LZFSE 压缩帧）。
    @discardableResult
    public static func importPairingToken(_ rawText: String) -> Bool {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(tokenPrefix) else { return false }
        var b64 = String(trimmed.dropFirst(tokenPrefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
        guard let rawWire = Data(base64Encoded: b64) else { return false }

        let jsonData: Data
        let lzfsMagic = Data("LZFS".utf8)
        if rawWire.count > 4 && rawWire.prefix(4) == lzfsMagic {
            guard let decompressed = try? (Data(rawWire.dropFirst(4)) as NSData).decompressed(using: .lzfse) as Data else {
                return false
            }
            jsonData = decompressed
        } else {
            jsonData = rawWire
        }
        guard let payload = try? JSONDecoder().decode(PairingPayload.self, from: jsonData) else {
            return false
        }

        let hasCloudCreds = !payload.apiKey.isEmpty && !payload.userID.isEmpty
        var importedParts: [String] = []

        if hasCloudCreds {
            CloudCredentialStore.saveAPIKey(payload.apiKey)
            var cfg = CloudBackendConfig.load()
            cfg.serverBaseURL = payload.serverBaseURL
            cfg.userID = payload.userID
            cfg.username = payload.username
            cfg.email = payload.email
            cfg.e2eeSalt = payload.e2eeSalt
            cfg.apiKeyPrefix = String(payload.apiKey.prefix(14)) + "..."
            cfg.isLocalOnlyAccount = false
            cfg.save()

            var relay = ClipboardRelayConfig.load()
            relay.syncTransportMode = .e2eeCloud
            relay.save()
            importedParts.append("云端桥接")
        }

        let decoder = JSONDecoder()
        if let aiData = payload.aiConfigJSON,
           var incomingAI = try? decoder.decode(AIConfig.self, from: aiData) {
            let existing = AIConfig.load()
            if incomingAI.fetchedModels.isEmpty {
                incomingAI.fetchedModels = existing.fetchedModels
            }
            if incomingAI.profiles.isEmpty {
                incomingAI.profiles = existing.profiles
            } else if !existing.profiles.isEmpty {
                var merged = incomingAI.profiles
                let incomingIDs = Set(merged.map(\.id))
                for p in existing.profiles where !incomingIDs.contains(p.id) {
                    merged.append(p)
                }
                incomingAI.profiles = merged
            }
            _ = incomingAI.save()
            importedParts.append("AI配置")
        }
        if let themeData = payload.themeJSON,
           let incomingTheme = try? decoder.decode(ThemeCustomization.self, from: themeData) {
            _ = incomingTheme.save()
            importedParts.append("外观")
        }
        if let settingsData = payload.settingsJSON,
           let incomingSettings = try? decoder.decode(LingxiSettings.self, from: settingsData) {
            _ = incomingSettings.save()
            importedParts.append("设置")
        }
        if let cardsData = payload.personalCardsJSON,
           let incomingCards = try? decoder.decode([PersonalFillCard].self, from: cardsData),
           !incomingCards.isEmpty {
            var merged = PersonalFillCardStore.load()
            for card in incomingCards {
                if let idx = merged.firstIndex(where: { $0.id == card.id }) {
                    merged[idx] = card
                } else {
                    merged.insert(card, at: 0)
                }
            }
            PersonalFillCardStore.save(merged)
            importedParts.append("名片(\(incomingCards.count))")
        }
        if let cwData = payload.customWordsJSON,
           let incomingWords = try? decoder.decode([CustomWordEntry].self, from: cwData),
           !incomingWords.isEmpty {
            var merged = CustomWordStore.load(force: true)
            var seen = Set(merged.map { "\($0.code)|\($0.word)" })
            for item in incomingWords where seen.insert("\(item.code)|\(item.word)").inserted {
                merged.append(item)
            }
            _ = CustomWordStore.save(merged)
            importedParts.append("短语(\(incomingWords.count))")
        }
        if let vnData = payload.vaultNotesJSON,
           let incomingNotes = try? decoder.decode([ObsidianVaultNote].self, from: vnData),
           !incomingNotes.isEmpty {
            let db = AICognitiveMemoryDB.shared
            for note in incomingNotes {
                db.upsertVaultNote(note)
            }
            db.appendEvolutionLog(
                action: "strengthen",
                noteTitle: "侧载桥接同步",
                detail: "从主 App 同步 \(incomingNotes.count) 篇 Obsidian 记忆笔记至键盘端",
                source: "sideload_bridge"
            )
            importedParts.append("记忆库(\(incomingNotes.count))")
        }

        guard !importedParts.isEmpty else { return false }

        var st = loadState()
        if hasCloudCreds { st.isPaired = true }
        st.lastSyncedAt = Date()
        st.lastSummary = "已导入 \(importedParts.joined(separator: "、"))"
        saveState(st)
        return true
    }

    /// 供键盘扩展在 `!AppGroup.isAvailable && isPairedInThisProcess` 时执行的轻量双向配置/字数同步
    /// （仅同步主题/设置/脱敏字数统计/自定义短语，绝不包含输入原文）。
    private static let syncQueue = DispatchQueue(label: "com.lingxi.sideload.bridge")
    private static var lastSyncTimestamp: TimeInterval = 0
    private static var isSyncInFlight = false

    public static func makeBridgeSyncSource() -> SyncDataSource {
        SnapshotSyncSource(entries: [
            .init(namespace: .theme, fileName: "lingxi_theme.json"),
            .init(namespace: .settings, fileName: "lingxi_settings.json"),
            .init(namespace: .typingStats, fileName: "typing_stats.json"),
            .init(namespace: .phrases, fileName: "lingxi_custom_words.json"),
            .init(namespace: .quickPhrases, fileName: "lingxi_phrases.json")
        ])
    }

    @discardableResult
    public static func syncIfNeeded(force: Bool = false, minInterval: TimeInterval = 6.0) async -> SyncRunReport? {
        guard !AppGroup.isAvailable, isPairedInThisProcess else { return nil }
        let now = Date().timeIntervalSince1970
        let shouldProceed: Bool = syncQueue.sync {
            if isSyncInFlight { return false }
            if !force && (now - lastSyncTimestamp) < minInterval { return false }
            isSyncInFlight = true
            return true
        }
        guard shouldProceed else { return nil }
        defer {
            syncQueue.sync {
                isSyncInFlight = false
                lastSyncTimestamp = Date().timeIntervalSince1970
            }
        }

        let engine = SyncEngine(
            sync: CloudBackendClient.shared,
            source: makeBridgeSyncSource(),
            ledgerStore: SyncLedgerStore(fileName: "lingxi_bridge_ledger.json")
        )
        guard let report = try? await engine.syncNow() else { return nil }
        var st = loadState()
        st.lastSyncedAt = Date()
        st.lastSummary = "推 \(report.pushed) · 拉 \(report.pulled) · 应用 \(report.applied)"
        saveState(st)
        return report
    }
}
