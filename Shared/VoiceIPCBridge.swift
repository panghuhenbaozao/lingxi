import Foundation

/// 主 App 后台语音引擎 ↔ 键盘扩展实时双通道通信协议（v5.6.2 去重 + 诊断 + 零代理劫持版）：
/// - 通道 1（App Group 可用，如正式签名 / 巨魔 / 含组侧载）：共享容器 JSON + Darwin 通知毫秒级直连，并用 `requestID` 防重复执行；
/// - 通道 2（免费侧载无 App Group）：单包 `GET http://127.0.0.1:48921/voice/cmd`（强制 `connectionProxyDictionary = [:]` 绕过代理）；
/// - 诊断信息：明确区分「App Group 在线 / 本机回环在线 / 免费侧载沙盒隔离」，杜绝无提示静默失灵！
struct VoiceIPCCommand: Codable, Equatable {
    enum Action: String, Codable {
        case start
        case stop
        case clear
        case ping
    }

    var action: Action
    var modeRaw: String
    var requestID: String = UUID().uuidString
    var timestamp: TimeInterval = Date().timeIntervalSince1970

    enum CodingKeys: String, CodingKey {
        case action, modeRaw, requestID, timestamp
    }

    init(
        action: Action,
        modeRaw: String,
        requestID: String = UUID().uuidString,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.action = action
        self.modeRaw = modeRaw
        self.requestID = requestID
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decode(Action.self, forKey: .action)
        modeRaw = try c.decode(String.self, forKey: .modeRaw)
        requestID = try c.decodeIfPresent(String.self, forKey: .requestID) ?? UUID().uuidString
        timestamp = try c.decodeIfPresent(TimeInterval.self, forKey: .timestamp) ?? Date().timeIntervalSince1970
    }
}

struct VoiceIPCState: Codable, Equatable {
    var engineWarm: Bool = false
    var isRecording: Bool = false
    var isTranslating: Bool = false
    var modeRaw: String = VoiceTranslateMode.zhToEn.rawValue
    var transcript: String = ""
    var translatedText: String = ""
    var audioLevel: Double = 0
    var statusText: String = ""
    var errorText: String? = nil
    var lastCommandID: String = ""
    var updatedAt: TimeInterval = Date().timeIntervalSince1970

    var isHeartbeatFresh: Bool {
        engineWarm && (Date().timeIntervalSince1970 - updatedAt) < 18.0
    }

    enum CodingKeys: String, CodingKey {
        case engineWarm, isRecording, isTranslating, modeRaw, transcript, translatedText, audioLevel, statusText, errorText, lastCommandID, updatedAt
    }

    init(
        engineWarm: Bool = false,
        isRecording: Bool = false,
        isTranslating: Bool = false,
        modeRaw: String = VoiceTranslateMode.zhToEn.rawValue,
        transcript: String = "",
        translatedText: String = "",
        audioLevel: Double = 0,
        statusText: String = "",
        errorText: String? = nil,
        lastCommandID: String = "",
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.engineWarm = engineWarm
        self.isRecording = isRecording
        self.isTranslating = isTranslating
        self.modeRaw = modeRaw
        self.transcript = transcript
        self.translatedText = translatedText
        self.audioLevel = audioLevel
        self.statusText = statusText
        self.errorText = errorText
        self.lastCommandID = lastCommandID
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engineWarm = try c.decodeIfPresent(Bool.self, forKey: .engineWarm) ?? false
        isRecording = try c.decodeIfPresent(Bool.self, forKey: .isRecording) ?? false
        isTranslating = try c.decodeIfPresent(Bool.self, forKey: .isTranslating) ?? false
        modeRaw = try c.decodeIfPresent(String.self, forKey: .modeRaw) ?? VoiceTranslateMode.zhToEn.rawValue
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        translatedText = try c.decodeIfPresent(String.self, forKey: .translatedText) ?? ""
        audioLevel = try c.decodeIfPresent(Double.self, forKey: .audioLevel) ?? 0
        statusText = try c.decodeIfPresent(String.self, forKey: .statusText) ?? ""
        errorText = try c.decodeIfPresent(String.self, forKey: .errorText)
        lastCommandID = try c.decodeIfPresent(String.self, forKey: .lastCommandID) ?? ""
        updatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? Date().timeIntervalSince1970
    }
}

struct VoiceProbeResult {
    let state: VoiceIPCState?
    let channel: String
    let detail: String

    var isWarm: Bool { state?.isHeartbeatFresh == true }
}

enum VoiceIPCBridge {
    static let loopbackPort: UInt16 = 48921
    static let commandFileName = "lingxi_voice_cmd.json"
    static let stateFileName = "lingxi_voice_state.json"

    static func writeCommandToShared(_ cmd: VoiceIPCCommand) {
        guard AppGroup.isAvailable else { return }
        _ = AppGroup.writeJSON(cmd, to: commandFileName)
        AppGroupNotifications.post(AppGroupNotifications.voiceCommand)
    }

    static func readCommandFromShared() -> VoiceIPCCommand? {
        guard AppGroup.isAvailable else { return nil }
        return AppGroup.readJSON(VoiceIPCCommand.self, from: commandFileName)
    }

    static func writeStateToShared(_ state: VoiceIPCState) {
        guard AppGroup.isAvailable else { return }
        _ = AppGroup.writeJSON(state, to: stateFileName)
        AppGroupNotifications.post(AppGroupNotifications.voiceState)
    }

    static func readStateFromShared() -> VoiceIPCState? {
        guard AppGroup.isAvailable else { return nil }
        return AppGroup.readJSON(VoiceIPCState.self, from: stateFileName)
    }

    // MARK: - 键盘侧双通道客户端（强制绕过系统 VPN/代理，零重复命令竞争）

    private static let fastSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 0.75
        cfg.timeoutIntervalForResource = 1.1
        cfg.waitsForConnectivity = false
        cfg.connectionProxyDictionary = [:]
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    static func probeHostEngine() async -> VoiceProbeResult {
        if AppGroup.isAvailable, let shared = readStateFromShared(), shared.isHeartbeatFresh {
            return VoiceProbeResult(state: shared, channel: "AppGroup", detail: "共享容器直连在线")
        }
        guard let url = URL(string: "http://127.0.0.1:\(loopbackPort)/voice/state") else {
            return VoiceProbeResult(state: nil, channel: "none", detail: "回环地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.assumesHTTP3Capable = false
        do {
            let (data, resp) = try await fastSession.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return VoiceProbeResult(state: nil, channel: "none", detail: "后台语音未启动")
            }
            let decoded = try JSONDecoder().decode(VoiceIPCState.self, from: data)
            if decoded.isHeartbeatFresh {
                return VoiceProbeResult(state: decoded, channel: "Loopback", detail: "本机回环在线")
            }
            return VoiceProbeResult(state: decoded, channel: "Loopback", detail: "后台引擎已休眠")
        } catch {
            if AppGroup.isAvailable {
                return VoiceProbeResult(state: nil, channel: "none", detail: "主 App 后台语音未激活")
            }
            return VoiceProbeResult(
                state: nil,
                channel: "isolated",
                detail: "当前签名无 App Group 且系统隔离回环（推荐直接点下方「全屏语音同传」）"
            )
        }
    }

    static func fetchStateFromHost() async -> VoiceIPCState? {
        await probeHostEngine().state
    }

    @discardableResult
    static func sendCommandToHost(_ cmd: VoiceIPCCommand) async -> VoiceIPCState? {
        // 1. App Group 可用时走共享容器 + Darwin 通知，并短暂等待回执（彻底避免再发 HTTP 造成重复 startCapture）
        if AppGroup.isAvailable {
            writeCommandToShared(cmd)
            for _ in 0..<7 {
                try? await Task.sleep(nanoseconds: 30_000_000)
                if let st = readStateFromShared(), st.lastCommandID == cmd.requestID {
                    return st
                }
            }
        }

        // 2. 回退本机回环单包 GET 指令（携带 requestID 去重）
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = "127.0.0.1"
        comps.port = Int(loopbackPort)
        comps.path = "/voice/cmd"
        comps.queryItems = [
            URLQueryItem(name: "action", value: cmd.action.rawValue),
            URLQueryItem(name: "mode", value: cmd.modeRaw),
            URLQueryItem(name: "req", value: cmd.requestID)
        ]
        guard let url = comps.url else {
            return readStateFromShared()
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.assumesHTTP3Capable = false
        do {
            let (data, resp) = try await fastSession.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return readStateFromShared()
            }
            return try JSONDecoder().decode(VoiceIPCState.self, from: data)
        } catch {
            return readStateFromShared()
        }
    }
}
