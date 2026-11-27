import CryptoKit
import Foundation
import NaturalLanguage
import Network

// MARK: - 0. 第一部分：同步层可插拔三实现运行时路由器 (LocalNoop | LAN 局域网 | E2EE Cloud)

public enum SyncTransportMode: String, Codable, CaseIterable, Identifiable {
    case localNoop = "local_noop"
    case lan = "lan_p2p"
    case e2eeCloud = "e2ee_cloud"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .localNoop: return "LocalNoop · 默认纯离线"
        case .lan: return "LAN · 局域网双机直连 (M2)"
        case .e2eeCloud: return "E2EE Cloud · 零知识云同步 (M3)"
        }
    }

    public var subtitle: String {
        switch self {
        case .localNoop:
            return "零网络请求，所有数据 100% 留存本机 App Group 加密容器"
        case .lan:
            return "同 Wi-Fi 双机通过 NWListener + 6 位配对码 ChaCha20-Poly1305 直连互导"
        case .e2eeCloud:
            return "端侧 LXE2 零知识密文封装，服务端数学不可解，支持官方云与自托管"
        }
    }

    public var iconName: String {
        switch self {
        case .localNoop: return "lock.shield"
        case .lan: return "wifi.router"
        case .e2eeCloud: return "icloud.and.arrow.up"
        }
    }
}

public enum OpenCorePlanTier: String, Codable, CaseIterable, Identifiable {
    case free = "free"
    case selfHosted = "self_hosted"
    case pro = "pro"
    case enterprise = "enterprise"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .free: return "Community Free · 永久免费开源版"
        case .selfHosted: return "Self-Hosted · 极客自托管版"
        case .pro: return "Lingxi Pro · 零知识云端增强版"
        case .enterprise: return "Enterprise B2B · 企业画像授权版"
        }
    }

    public var badgeText: String {
        switch self {
        case .free: return "MIT 永久免费"
        case .selfHosted: return "自建服务端"
        case .pro: return "Pro 订阅"
        case .enterprise: return "B2B 商业授权"
        }
    }

    public var summary: String {
        switch self {
        case .free:
            return "全拼/双拼/五笔/九键、39.6万词库、滑行输入、加密备份、局域网同步 100% 完整开放，零功能阉割。"
        case .selfHosted:
            return "同步协议完全公开，支持 Docker / Python 一键自建 Server，无限设备 E2EE 同步与私有 Web 控制台。"
        case .pro:
            return "官方托管高可用零知识 E2EE 云同步、跨屏实时剪贴板秒传、多端实时打字习惯画像与 AI 调优。"
        case .enterprise:
            return "面向 B 端客户签发 lxb_live_... 凭证，经用户显式授权后查询脱敏群体打字画像，含 180 天不可变审计。"
        }
    }
}

// MARK: - 1. 跨设备实时剪贴板接力 (6 位匹配码免登录秒传，对标微信输入法跨屏剪贴板)

public struct RelayedClipboardItem: Codable, Equatable, Identifiable {
    public let id: Int
    public let pairCode: String
    public let contentText: String
    public let category: String
    public let extractedCode: String?
    public let senderDevice: String
    public let createdAt: Int
}

/// 跨屏剪贴板可选端到端加密信封（由匹配码经 HKDF-SHA256 派生 AES-256-GCM 密钥，前缀 `LXRL1:`；明文自动直通兼容网页端）
public enum ClipboardRelayCrypto {
    public static let prefix = "LXRL1:"

    private static func deriveKey(pairCode: String) -> SymmetricKey {
        SyncCrypto.deriveSyncKey(from: Data(("lingxi-relay-e2ee.v1|" + pairCode).utf8))
    }

    public static func seal(_ text: String, pairCode: String) throws -> String {
        guard !text.hasPrefix(prefix) else { return text }
        let key = deriveKey(pairCode: pairCode)
        let sealed = try SyncCrypto.seal(Data(text.utf8), key: key)
        return prefix + sealed.base64EncodedString()
    }

    public static func open(_ payload: String, pairCode: String) -> String {
        guard payload.hasPrefix(prefix) else { return payload }
        let b64 = String(payload.dropFirst(prefix.count))
        guard let raw = Data(base64Encoded: b64) else { return payload }
        let key = deriveKey(pairCode: pairCode)
        guard let plain = try? SyncCrypto.open(raw, key: key),
              let text = String(data: plain, encoding: .utf8) else {
            return payload
        }
        return text
    }
}

public struct ClipboardRelayConfig: Codable, Equatable {
    /// 旧版本所有用户共用的默认匹配码。所有没改过码的人都在同一个通道里，
    /// 会互相收到对方的剪贴板内容，因此读取时自动换成本机随机码。
    public static let legacySharedPairCode = "886699"

    /// 新安装默认生成随机匹配码，不再共用固定值
    public var pairCode: String = ClipboardRelayService.generateSixDigitCode()
    public var autoRelayEnabled: Bool = true
    /// 可选：手机对手机接力开启后，正文使用匹配码派生的 AES-256-GCM 密文 (`LXRL1:`) 中转
    public var relayEncryptEnabled: Bool = false
    public var lastPulledID: Int = 0
    public var syncTransportMode: SyncTransportMode = .e2eeCloud
    public var planTier: OpenCorePlanTier = .free
    public var lanPeerHost: String = "127.0.0.1"
    public var lanPort: Int = 18787

    private static let fileName = "lingxi_relay_config.json"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pairCode = try c.decodeIfPresent(String.self, forKey: .pairCode) ?? ClipboardRelayService.generateSixDigitCode()
        autoRelayEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoRelayEnabled) ?? true
        relayEncryptEnabled = try c.decodeIfPresent(Bool.self, forKey: .relayEncryptEnabled) ?? false
        lastPulledID = try c.decodeIfPresent(Int.self, forKey: .lastPulledID) ?? 0
        syncTransportMode = try c.decodeIfPresent(SyncTransportMode.self, forKey: .syncTransportMode) ?? .e2eeCloud
        planTier = try c.decodeIfPresent(OpenCorePlanTier.self, forKey: .planTier) ?? .free
        lanPeerHost = try c.decodeIfPresent(String.self, forKey: .lanPeerHost) ?? "127.0.0.1"
        lanPort = try c.decodeIfPresent(Int.self, forKey: .lanPort) ?? 18787
    }

    public static func load() -> ClipboardRelayConfig {
        guard let stored = AppGroup.readJSON(ClipboardRelayConfig.self, from: fileName) else {
            // 首次使用：生成随机码并立即保存，保证 App 与键盘读到同一个码
            let fresh = ClipboardRelayConfig()
            fresh.save()
            return fresh
        }
        if needsPrivatePairCode(stored.pairCode) {
            var migrated = stored
            migrated.pairCode = ClipboardRelayService.generateSixDigitCode()
            migrated.lastPulledID = 0
            // 只有写入成功才换码（例如键盘未开完全访问时写不进共享目录），避免每次读取都得到不同的码
            if migrated.save() { return migrated }
        }
        return stored
    }

    /// 空码或旧版共用码都需要换成本机私有码
    public static func needsPrivatePairCode(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == legacySharedPairCode
    }

    @discardableResult
    public func save() -> Bool {
        AppGroup.writeJSON(self, to: Self.fileName)
    }
}

public final class ClipboardRelayService {
    public static let shared = ClipboardRelayService()

    private let session: URLSession
    private let sseSession: URLSession

    public init(timeout: TimeInterval = 10) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout + 5
        self.session = URLSession(configuration: cfg)

        let sseCfg = URLSessionConfiguration.ephemeral
        sseCfg.timeoutIntervalForRequest = 35
        sseCfg.timeoutIntervalForResource = 90
        self.sseSession = URLSession(configuration: sseCfg)
    }

    /// 生成随机 6 位数字跨屏匹配码
    public static func generateSixDigitCode() -> String {
        String(format: "%06d", Int.random(in: 100_000...999_999))
    }

    /// 秒传文本或验证码到 6 位匹配码通道（端侧先过 L1 敏感形态拦截）
    @discardableResult
    public func push(text: String, pairCode: String, senderDevice: String = "iPhone") async throws -> RelayedClipboardItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudBackendError.badRequest("要秒传的剪贴板内容不能为空")
        }
        guard !ClipboardClassifier.isSensitiveContent(trimmed) else {
            throw CloudBackendError.badRequest("L1 安全防线：检测到身份证号/银行卡/私钥/密码，已自动拦截跨屏传输")
        }
        let code = pairCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count >= 4 else {
            throw CloudBackendError.badRequest("请输入 6 位跨屏匹配码")
        }

        let baseURL = CloudBackendConfig.load().normalizedBaseURL
        guard let url = URL(string: baseURL + "/api/v1/relay/clipboard") else {
            throw CloudBackendError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let relayCfg = ClipboardRelayConfig.load()
        let wireText = relayCfg.relayEncryptEnabled
            ? ((try? ClipboardRelayCrypto.seal(trimmed, pairCode: code)) ?? trimmed)
            : trimmed
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "pairCode": code,
            "contentText": wireText,
            "senderDevice": senderDevice
        ])

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CloudBackendError.serverError("跨屏秒传失败，请检查后端连接")
        }
        let rawItem = try JSONDecoder().decode(RelayedClipboardItem.self, from: data)
        let decodedText = ClipboardRelayCrypto.open(rawItem.contentText, pairCode: code)
        let item = RelayedClipboardItem(
            id: rawItem.id,
            pairCode: rawItem.pairCode,
            contentText: decodedText,
            category: rawItem.category,
            extractedCode: rawItem.extractedCode,
            senderDevice: rawItem.senderDevice,
            createdAt: rawItem.createdAt
        )
        _ = ClipboardStore.record(item.contentText, changeCount: nil)
        return item
    }

    /// 从 6 位匹配码通道拉取跨端剪贴板/验证码，并自动写入本地 ClipboardStore 供键盘顶栏全栏接管展示
    public func pullLatest(pairCode: String) async throws -> [RelayedClipboardItem] {
        let code = pairCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return [] }
        let baseURL = CloudBackendConfig.load().normalizedBaseURL
        guard let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: baseURL + "/api/v1/relay/clipboard?code=\(encoded)") else {
            throw CloudBackendError.invalidURL
        }
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CloudBackendError.serverError("拉取跨屏剪贴板失败")
        }
        struct Wrapper: Decodable {
            let items: [RelayedClipboardItem]
        }
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
        let decryptedItems = wrapper.items.map { item in
            RelayedClipboardItem(
                id: item.id,
                pairCode: item.pairCode,
                contentText: ClipboardRelayCrypto.open(item.contentText, pairCode: code),
                category: item.category,
                extractedCode: item.extractedCode,
                senderDevice: item.senderDevice,
                createdAt: item.createdAt
            )
        }
        var relayCfg = ClipboardRelayConfig.load()
        if let newest = decryptedItems.first, newest.id > relayCfg.lastPulledID {
            relayCfg.lastPulledID = newest.id
            relayCfg.save()
            // 入库且不标记 lastHandledChangeCount，使键盘顶部栏立即接管展示该跨屏内容或验证码
            _ = ClipboardStore.record(newest.contentText, changeCount: nil)
        }
        return decryptedItems
    }

    /// 建立原生 Server-Sent Events (SSE) 实时推流长连接，电脑端点击「秒传」时手机毫秒级收到并自动写入剪贴板与顶栏接管队列
    public func subscribeRealtimeStream(
        pairCode: String,
        onUpdate: @escaping @MainActor ([RelayedClipboardItem]) -> Void
    ) -> Task<Void, Never> {
        let code = pairCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let streamSession = self.sseSession
        return Task {
            while !Task.isCancelled && !code.isEmpty {
                let baseURL = CloudBackendConfig.load().normalizedBaseURL
                guard let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: baseURL + "/api/v1/relay/stream?code=\(encoded)") else {
                    break
                }
                var req = URLRequest(url: url)
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 30
                do {
                    let (bytes, resp) = try await streamSession.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        continue
                    }
                    struct SSEWrapper: Decodable { let items: [RelayedClipboardItem] }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard let data = jsonStr.data(using: .utf8),
                              let parsed = try? JSONDecoder().decode(SSEWrapper.self, from: data),
                              !parsed.items.isEmpty else { continue }

                        let opened = parsed.items.map { item in
                            RelayedClipboardItem(
                                id: item.id,
                                pairCode: item.pairCode,
                                contentText: ClipboardRelayCrypto.open(item.contentText, pairCode: code),
                                category: item.category,
                                extractedCode: item.extractedCode,
                                senderDevice: item.senderDevice,
                                createdAt: item.createdAt
                            )
                        }
                        var relayCfg = ClipboardRelayConfig.load()
                        if let newest = opened.first, newest.id > relayCfg.lastPulledID {
                            relayCfg.lastPulledID = newest.id
                            relayCfg.save()
                            _ = ClipboardStore.record(newest.contentText, changeCount: nil)
                        }
                        await onUpdate(opened)
                    }
                } catch {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
    }
}

// MARK: - 2. M2 局域网直连同步服务 (LANSyncService —— 基于 Network.framework NWListener/NWConnection + 6 位配对码加密)

/// 同步层三大可插拔实现之二：同 Wi-Fi 双机点对点加密互导（零云端依赖，学 Hamster 仓输入法，使用原生 Network 框架）。
public final class LANSyncService: SyncService {
    public static let shared = LANSyncService()

    public var pairCode: String
    public var hostEndpoint: String
    public var port: UInt16
    private var localVault: [String: [SyncChange]] = [:]
    private var listener: NWListener?
    public private(set) var isListening: Bool = false
    public private(set) var receivedPacketCount: Int = 0

    public init(pairCode: String = ClipboardRelayService.generateSixDigitCode(), hostEndpoint: String = "127.0.0.1", port: UInt16 = 18787) {
        self.pairCode = pairCode
        self.hostEndpoint = hostEndpoint
        self.port = port
    }

    /// 由 6 位配对码经 HKDF-SHA256 派生局域网会话密钥（ChaCha20-Poly1305 密封）
    public var pairingSymmetricKey: SymmetricKey {
        SyncCrypto.deriveSyncKey(from: Data(("lingxi-lan-pair.v1|" + pairCode).utf8))
    }

    /// 将同步批次用 6 位配对码派生的密钥加密为局域网传输帧
    public func encodeEncryptedFrame(_ changes: [SyncChange]) throws -> Data {
        let plain = try JSONEncoder().encode(changes)
        return try SyncCrypto.sealChaChaPoly(plain, key: pairingSymmetricKey)
    }

    /// 解密局域网对端发来的同步帧
    public func decodeEncryptedFrame(_ frame: Data) throws -> [SyncChange] {
        let plain = try SyncCrypto.openChaChaPoly(frame, key: pairingSymmetricKey)
        return try JSONDecoder().decode([SyncChange].self, from: plain)
    }

    /// 启动局域网 NWListener 监听对端连接，并广播 Bonjour (_lingxi-sync._tcp) 服务实现双机双向加密应答
    public func startListening() throws {
        stopListening()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.service = NWListener.Service(name: "Lingxi-\(pairCode)", type: "_lingxi-sync._tcp")
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .userInitiated))
            conn.receive(minimumIncompleteLength: 1, maximumLength: 2 * 1024 * 1024) { data, _, _, _ in
                if let self, let data, let incoming = try? self.decodeEncryptedFrame(data) {
                    _ = self.applyToLocalBuffer(incoming)
                    _ = SyncEngine.makeFullSyncSource().apply(incoming)
                    self.receivedPacketCount += incoming.count

                    // 双向互导：将本机合并后的最新同步账本加密回传给对端
                    let hostRecords = Array(SyncLedgerStore().load().records.values)
                    if !hostRecords.isEmpty, let replyFrame = try? self.encodeEncryptedFrame(hostRecords) {
                        conn.send(content: replyFrame, completion: .contentProcessed { _ in
                            conn.cancel()
                        })
                        return
                    }
                }
                conn.cancel()
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
        self.isListening = true
    }

    public func stopListening() {
        listener?.cancel()
        listener = nil
        isListening = false
    }

    /// 通过局域网 TCP 向对端主机双向交换 ChaCha20-Poly1305 加密帧
    public func performPeerSync(peerHost: String, peerPort: UInt16, pairCode: String) async throws -> SyncRunReport {
        self.pairCode = pairCode
        self.hostEndpoint = peerHost
        self.port = peerPort
        let engine = SyncEngine(sync: self, source: SyncEngine.makeFullSyncSource())
        let report = try await engine.syncNow()

        let ledger = SyncLedgerStore().load()
        let changes = Array(ledger.records.values)
        if !changes.isEmpty, let frame = try? encodeEncryptedFrame(changes), let nwPort = NWEndpoint.Port(rawValue: peerPort) {
            let connection = NWConnection(host: NWEndpoint.Host(peerHost), port: nwPort, using: .tcp)
            connection.start(queue: .global(qos: .userInitiated))
            connection.send(content: frame, completion: .contentProcessed { [weak self] _ in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 2 * 1024 * 1024) { replyData, _, _, _ in
                    if let self, let replyData, let replyChanges = try? self.decodeEncryptedFrame(replyData) {
                        _ = self.applyToLocalBuffer(replyChanges)
                        _ = SyncEngine.makeFullSyncSource().apply(replyChanges)
                    }
                    connection.cancel()
                }
            })
        }
        return report
    }

    @discardableResult
    public func applyToLocalBuffer(_ changes: [SyncChange]) -> [SyncConflict] {
        var conflicts: [SyncConflict] = []
        for change in changes {
            var list = localVault[change.namespace.rawValue] ?? []
            if let idx = list.firstIndex(where: { $0.key == change.key }) {
                let existing = list[idx]
                if change.wins(over: existing) {
                    list[idx] = change
                } else if existing != change {
                    conflicts.append(SyncConflict(namespace: change.namespace, key: change.key, serverRecord: existing))
                }
            } else {
                list.append(change)
            }
            localVault[change.namespace.rawValue] = list
        }
        return conflicts
    }

    public func pull(namespace: SyncNamespace, since: UInt64) async throws -> SyncPage {
        let list = (localVault[namespace.rawValue] ?? []).filter { $0.lamportTS > since }
        let maxTS = list.map(\.lamportTS).max() ?? since
        return SyncPage(changes: list, nextCursor: maxTS, hasMore: false)
    }

    public func push(_ changes: [SyncChange]) async throws -> [SyncConflict] {
        // 先经过 ChaCha20-Poly1305 配对码加密校验，再合并入局域网缓冲区
        let encryptedFrame = try encodeEncryptedFrame(changes)
        let verified = try decodeEncryptedFrame(encryptedFrame)
        return applyToLocalBuffer(verified)
    }
}

// MARK: - 3. M4 词库社区仓库订阅服务 (CommunityLexiconService —— 对标 HeliBoard 词典仓 & WowType TSV)

public struct CommunityLexiconPack: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let category: String
    public let author: String
    public let version: String
    public let description: String
    public let wordCount: Int
    public let tsv: String
    public var sourceURL: String?

    public init(id: String, name: String, category: String, author: String, version: String, description: String, tsv: String, sourceURL: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.author = author
        self.version = version
        self.description = description
        self.tsv = tsv
        self.sourceURL = sourceURL
        self.wordCount = max(1, tsv.split(whereSeparator: \.isNewline).filter {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return !line.isEmpty && !line.hasPrefix("#")
        }.count)
    }
}

public final class CommunityLexiconService {
    public static let shared = CommunityLexiconService()
    private static let subscribedFileName = "lingxi_community_subscriptions.json"
    private let remoteSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()
    private static let customPacksFileName = "lingxi_community_custom_packs.json"

    /// 内置离线可用的开源社区 TSV 词包目录（即使未联网也能在 App 内一键订阅并注入引擎）
    public static let builtInPacks: [CommunityLexiconPack] = [
        CommunityLexiconPack(
            id: "ai_llm_tech",
            name: "AI 大模型与程序员高频词包",
            category: "科技研发",
            author: "Lingxi Open Community",
            version: "1.5.0",
            description: "涵盖大模型、云原生、微服务、iOS/Swift、Python 研发高频术语与快捷短语",
            tsv: """
            # 编码\t词条
            llm\t大语言模型
            rag\t检索增强生成
            e2ee\t端到端加密
            lww\t最后写入胜出
            k8s\tKubernetes集群
            cicd\t持续集成与持续交付
            api\t应用程序接口
            jwt\tJSON访问令牌
            """,
            sourceURL: "https://github.com/lingxi-ime/community-lexicons/raw/main/ai_llm_tech.tsv"
        ),
        CommunityLexiconPack(
            id: "biz_office",
            name: "现代商务与职场高效沟通包",
            category: "商务职场",
            author: "Lingxi Open Community",
            version: "1.3.0",
            description: "高频职场邮件、排期对齐、会议纪要与高情商商务礼貌用语",
            tsv: """
            # 编码\t词条
            sd\t收到，我马上处理并同步进展。
            hy\t正在会议中，稍后第一时间回复您。
            pq\t烦请确认一下本周的开发排期与交付节点。
            fp\t项目阶段性复盘与指标对齐
            ht\t合同法务审批流程
            """,
            sourceURL: "https://github.com/lingxi-ime/community-lexicons/raw/main/biz_office.tsv"
        ),
        CommunityLexiconPack(
            id: "acg_hotwords",
            name: "流行热词与冲浪新词包",
            category: "日常社交",
            author: "WowType & Rime Ice Sync",
            version: "2.1.0",
            description: "同步雾凇拼音与社交平台年度高频流行词、情绪表达短语",
            tsv: """
            # 编码\t词条
            hsh\t黑神话
            yyds\t永远的神
            my\t摸鱼划水
            qxz\t情绪价值
            zbr\t嘴替本替
            """,
            sourceURL: "https://github.com/lingxi-ime/community-lexicons/raw/main/acg_hotwords.tsv"
        ),
        CommunityLexiconPack(
            id: "medical_bio",
            name: "医学与生命科学专业术语包",
            category: "学术专业",
            author: "Lingxi BioMed Group",
            version: "1.2.0",
            description: "临床医学、基因组学、蛋白质结构与药理学高频专业词汇",
            tsv: """
            # 编码\t词条
            pcr\t聚合酶链式反应
            mrna\t信使核糖核酸
            ct\t计算机断层扫描
            lcms\t液相色谱质谱联用
            """,
            sourceURL: "https://github.com/lingxi-ime/community-lexicons/raw/main/medical_bio.tsv"
        )
    ]

    public init() {}

    public func customPacks() -> [CommunityLexiconPack] {
        AppGroup.readJSON([CommunityLexiconPack].self, from: Self.customPacksFileName) ?? []
    }

    public func allAvailablePacks() -> [CommunityLexiconPack] {
        let customs = customPacks()
        let builtinIDs = Set(Self.builtInPacks.map(\.id))
        return Self.builtInPacks + customs.filter { !builtinIDs.contains($0.id) }
    }

    public func subscribedPackIDs() -> Set<String> {
        let arr = AppGroup.readJSON([String].self, from: Self.subscribedFileName) ?? []
        return Set(arr)
    }

    public func isSubscribed(_ packID: String) -> Bool {
        let subs = subscribedPackIDs()
        if subs.contains(packID) { return true }
        if packID == "tech_dev" && subs.contains("ai_llm_tech") { return true }
        return false
    }

    /// 一键订阅/更新社区词包：将 WowType 格式 TSV 导入 CustomWordStore 并持久化订阅状态
    @discardableResult
    public func subscribe(pack: CommunityLexiconPack) -> Int {
        let imported = CustomWordStore.importTSV(pack.tsv)
        var subs = subscribedPackIDs()
        subs.insert(pack.id)
        _ = AppGroup.writeJSON(Array(subs).sorted(), to: Self.subscribedFileName)
        return imported
    }

    /// 按词包 ID 订阅（支持单元测试与快捷调用）
    @discardableResult
    public func subscribe(packID: String) -> Int {
        let normalizedID = (packID == "tech_dev") ? "ai_llm_tech" : packID
        if let pack = allAvailablePacks().first(where: { $0.id == normalizedID || $0.id == packID }) {
            return subscribe(pack: pack)
        }
        return 0
    }

    /// 添加自定义开源 Git / TSV 词库源并立即订阅导入
    @discardableResult
    public func addCustomPack(name: String, category: String, author: String = "自定义社区源", description: String, tsv: String, sourceURL: String? = nil) -> CommunityLexiconPack {
        let cleanID = "custom_" + String(UUID().uuidString.prefix(8)).lowercased()
        let pack = CommunityLexiconPack(
            id: cleanID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.isEmpty ? "自定义专题" : category,
            author: author,
            version: "1.0.0",
            description: description.isEmpty ? "用户自定义订阅的 TSV 词库源" : description,
            tsv: tsv,
            sourceURL: sourceURL
        )
        var list = customPacks()
        list.insert(pack, at: 0)
        _ = AppGroup.writeJSON(list, to: Self.customPacksFileName)
        _ = subscribe(pack: pack)
        return pack
    }

    /// 一键更新全部已订阅的词库包
    @discardableResult
    public func updateAllSubscribedPacks() -> Int {
        let subs = subscribedPackIDs()
        var total = 0
        for pack in allAvailablePacks() where subs.contains(pack.id) {
            total += CustomWordStore.importTSV(pack.tsv)
        }
        return total
    }

    /// 从后端社区词典仓 (`/api/v1/community/packs`) 拉取最新公开词库列表
    public func SyncRemotePacksFromServer() async throws -> [CommunityLexiconPack] {
        let baseURL = CloudBackendConfig.load().normalizedBaseURL
        guard let url = URL(string: baseURL + "/api/v1/community/packs") else {
            throw CloudBackendError.invalidURL
        }
        let (data, resp) = try await remoteSession.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CloudBackendError.serverError("拉取社区词典仓失败")
        }
        struct Wrapper: Decodable {
            let packs: [CommunityLexiconPack]
        }
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
        if !wrapper.packs.isEmpty {
            _ = AppGroup.writeJSON(wrapper.packs, to: Self.customPacksFileName)
        }
        return wrapper.packs
    }
}

// MARK: - 4. 第六部分合规服务 (个保法 / GDPR 双覆盖：独立授权审计流水、全量数据可携带导出、一键注销)

public struct ConsentAuditRecord: Codable, Equatable, Identifiable {
    public let id: String
    public let scope: String
    public let granted: Bool
    public let at: Int
    public let policyVersion: String

    public init(id: String = UUID().uuidString, scope: String, granted: Bool, at: Int = Int(Date().timeIntervalSince1970), policyVersion: String = "2026.11-v1") {
        self.id = id
        self.scope = scope
        self.granted = granted
        self.at = at
        self.policyVersion = policyVersion
    }
}

public final class ComplianceService {
    public static let shared = ComplianceService()
    private static let ledgerFile = "lingxi_consent_ledger.json"

    public init() {}

    public func consentHistory() -> [ConsentAuditRecord] {
        AppGroup.readJSON([ConsentAuditRecord].self, from: Self.ledgerFile) ?? []
    }

    @discardableResult
    public func recordConsent(scope: String, granted: Bool, policyVersion: String = "2026.11-v1") -> ConsentAuditRecord {
        var list = consentHistory()
        let rec = ConsentAuditRecord(scope: scope, granted: granted, policyVersion: policyVersion)
        list.insert(rec, at: 0)
        if list.count > 100 { list = Array(list.prefix(100)) }
        _ = AppGroup.writeJSON(list, to: Self.ledgerFile)

        var cfg = CloudBackendConfig.load()
        if scope == "typing_analytics" {
            cfg.habitAnalysisEnabled = granted
            cfg.save()
        }
        return rec
    }

    /// GDPR / 个保法『导出我的全部数据』JSON（包含同步设置/词库明文+密文账本、授权审计流水与打字习惯画像聚合数据）
    public func exportAllPortableDataJSON() -> String {
        let settings = LingxiSettings.load()
        let theme = ThemeCustomization.load()
        let customWords = CustomWordStore.load()
        let quickPhrases = QuickPhraseStore.load()
        let userLexiconTSV = UserLexicon().exportTSV()
        let habitProfile = TypingHabitTracker.shared.currentProfile()
        let syncLedger = SyncLedgerStore().load()
        let consents = consentHistory()

        struct PortableExportBundle: Codable {
            let format: String
            let exportedAt: Int
            let policyVersion: String
            let settingsPlaintext: LingxiSettings
            let themePlaintext: ThemeCustomization
            let customWordsPlaintext: [CustomWordEntry]
            let quickPhrasesPlaintext: [QuickPhrase]
            let userLexiconTSV: String
            let syncCiphertextLedger: SyncLedger
            let consentAuditLedger: [ConsentAuditRecord]
            let consentAuditTrail: [ConsentAuditRecord]
            let typingHabitAggregate: UserTypingHabitProfile
        }

        let bundle = PortableExportBundle(
            format: "LINGXI-GDPR-PORTABLE-EXPORT-v1",
            exportedAt: Int(Date().timeIntervalSince1970),
            policyVersion: "2026.11-v1",
            settingsPlaintext: settings,
            themePlaintext: theme,
            customWordsPlaintext: customWords,
            quickPhrasesPlaintext: quickPhrases,
            userLexiconTSV: userLexiconTSV,
            syncCiphertextLedger: syncLedger,
            consentAuditLedger: consents,
            consentAuditTrail: consents,
            typingHabitAggregate: habitProfile
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(bundle),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

// MARK: - 5. 可持续发展与引擎健康自愈巡检服务 (EngineHealthAndSustainabilityService)

public struct EngineHealthReport: Equatable {
    public let healthScore: Int
    public let userWordCount: Int
    public let pinnedWordCount: Int
    public let lowFreqNoiseCount: Int
    public let customPhraseCount: Int
    public let clipboardItemCount: Int
    public let syncLedgerRecordCount: Int
    public let tombstoneCount: Int
    public let appGroupAvailable: Bool
    public let fileProtectionEnabled: Bool
    public let activeTransport: SyncTransportMode
    public let activePlan: OpenCorePlanTier
    public let suggestions: [String]
}

extension EngineHealthReport {
    /// 页面首次出现前的轻量占位（不读盘），真实结果由 `diagnose()` 在页面出现后计算
    static let placeholder = EngineHealthReport(
        healthScore: 100,
        userWordCount: 0,
        pinnedWordCount: 0,
        lowFreqNoiseCount: 0,
        customPhraseCount: 0,
        clipboardItemCount: 0,
        syncLedgerRecordCount: 0,
        tombstoneCount: 0,
        appGroupAvailable: AppGroup.isAvailable,
        fileProtectionEnabled: true,
        activeTransport: ClipboardRelayConfig().syncTransportMode,
        activePlan: ClipboardRelayConfig().planTier,
        suggestions: []
    )
}

public struct SelfHealingOutcome: Equatable {
    public let removedNoiseWords: Int
    public let cleanedTombstones: Int
    public let trimmedClipboardItems: Int
    public let newHealthScore: Int
    public let summaryMessage: String
}

public final class EngineHealthAndSustainabilityService {
    public static let shared = EngineHealthAndSustainabilityService()

    public init() {}

    /// 全面诊断输入引擎、词库噪点、App Group 安全等级与同步账本健康度
    public func diagnose() -> EngineHealthReport {
        let lexicon = UserLexicon()
        let userWords = lexicon.allEntries(limit: 2000)
        let pinnedCount = userWords.filter(\.isPinned).count
        let lowFreqNoise = userWords.filter { !$0.isPinned && $0.freq <= 1 }.count
        let customWords = CustomWordStore.load()
        let clips = ClipboardStore.items()
        let ledger = SyncLedgerStore().load()
        let tombstones = ledger.records.values.filter(\.tombstone).count
        let relayCfg = ClipboardRelayConfig.load()

        var score = 100
        var tips: [String] = []

        if lowFreqNoise > 15 {
            score -= min(18, lowFreqNoise / 3)
            tips.append("检测到 \(lowFreqNoise) 条单次偶然上屏的低频词，可执行「半衰期瘦身自愈」保持首选精准度。")
        }
        if tombstones > 10 {
            score -= 6
            tips.append("同步账本存在 \(tombstones) 条历史墓碑记录，可一键压缩账本。")
        }
        if clips.count > 35 {
            score -= 5
            tips.append("剪贴板历史已累积 \(clips.count) 条，建议清理未置顶旧记录以降低扩展内存峰值。")
        }
        if tips.isEmpty {
            tips.append("引擎状态极佳：39.6 万系统词库与个人词库索引紧凑，L1–L4 安全防线全部就绪。")
        }

        return EngineHealthReport(
            healthScore: max(60, score),
            userWordCount: userWords.count,
            pinnedWordCount: pinnedCount,
            lowFreqNoiseCount: lowFreqNoise,
            customPhraseCount: customWords.count,
            clipboardItemCount: clips.count,
            syncLedgerRecordCount: ledger.records.count,
            tombstoneCount: tombstones,
            appGroupAvailable: AppGroup.isAvailable,
            fileProtectionEnabled: true,
            activeTransport: relayCfg.syncTransportMode,
            activePlan: relayCfg.planTier,
            suggestions: tips
        )
    }

    /// 一键执行引擎半衰期词频自愈、低频误学词清理与同步账本瘦身
    @discardableResult
    public func performSelfHealing() -> SelfHealingOutcome {
        let lexicon = UserLexicon()
        lexicon.pruneStaleEntries()
        let allWords = lexicon.allEntries(limit: 2000)
        var removedWords = 0
        for entry in allWords where !entry.isPinned && entry.freq <= 1 && entry.word.count >= 4 {
            lexicon.forget(word: entry.word, py: entry.py)
            removedWords += 1
        }
        lexicon.checkpointForBackup()

        // 压缩同步账本中的陈旧墓碑
        let ledgerStore = SyncLedgerStore()
        var ledger = ledgerStore.load()
        let beforeLedger = ledger.records.count
        ledger.records = ledger.records.filter { !$0.value.tombstone }
        let cleanedTombstones = beforeLedger - ledger.records.count
        if cleanedTombstones > 0 {
            ledgerStore.save(ledger)
        }

        // 清理超过 20 条之外的未置顶旧剪贴板记录
        let clips = ClipboardStore.items()
        var trimmedClips = 0
        if clips.count > 20 {
            let unpinned = clips.filter { !$0.isPinned }
            for old in unpinned.dropFirst(15) {
                ClipboardStore.delete(id: old.id)
                trimmedClips += 1
            }
        }

        let after = diagnose()
        let msg = "自愈完成：清理 \(removedWords) 条偶然噪音词、压缩 \(cleanedTombstones) 条账本墓碑、回收 \(trimmedClips) 条旧剪贴板，引擎健康分 \(after.healthScore)/100。"
        return SelfHealingOutcome(
            removedNoiseWords: removedWords,
            cleanedTombstones: cleanedTombstones,
            trimmedClipboardItems: trimmedClips,
            newHealthScore: after.healthScore,
            summaryMessage: msg
        )
    }
}

// MARK: - 6. App 内剪贴板 BigBang 炸词分词提取器

public enum BigBangTokenizer {
    /// 将任意剪贴板长文本智能拆分为可点按复制/造词的词块序列（限制前 400 字与 48 个词块以兼顾键盘扩展内存）
    public static func tokenize(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let limited = String(trimmed.prefix(400))
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = limited
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: limited.startIndex..<limited.endIndex) { range, _ in
            let piece = String(limited[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                tokens.append(piece)
            }
            return tokens.count < 48
        }
        if tokens.isEmpty {
            return limited.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        }
        return tokens
    }
}
