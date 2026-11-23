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

    /// 主 App 生成供键盘一键认领的加密云同步配对串（含国内直连地址、API Key 与端侧 E2EE 盐）。
    public static func exportPairingTokenFromMainApp() -> String? {
        guard CloudBackendClient.shared.isRealCloudAuthenticated,
              let apiKey = CloudCredentialStore.loadAPIKey(),
              !apiKey.isEmpty else {
            return nil
        }
        let cfg = CloudBackendConfig.load()
        guard !cfg.userID.isEmpty else { return nil }
        let payload = PairingPayload(
            serverBaseURL: cfg.normalizedBaseURL,
            userID: cfg.userID,
            username: cfg.username,
            email: cfg.email,
            apiKey: apiKey,
            e2eeSalt: cfg.e2eeSalt
        )
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        let b64u = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return tokenPrefix + b64u
    }

    /// 键盘端解析并落地主 App 复制过来的 `LXBRIDGE1:...` 配对串（纯字符串，供单元测试与剪贴板识别复用）。
    @discardableResult
    public static func importPairingToken(_ rawText: String) -> Bool {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(tokenPrefix) else { return false }
        var b64 = String(trimmed.dropFirst(tokenPrefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
        guard let data = Data(base64Encoded: b64),
              let payload = try? JSONDecoder().decode(PairingPayload.self, from: data),
              !payload.apiKey.isEmpty,
              !payload.userID.isEmpty else {
            return false
        }

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

        var st = loadState()
        st.isPaired = true
        st.lastSummary = "已绑定云桥接账号（\(payload.username.isEmpty ? "灵犀用户" : payload.username)）"
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
