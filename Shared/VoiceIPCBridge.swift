import Foundation

/// 主 App 后台语音引擎 ↔ 键盘扩展实时双通道通信协议：
/// - 正式签名（App Group 可用）：共享容器 JSON + Darwin 通知毫秒级直连；
/// - 免费侧载（App Group 被系统隔离）：自动走本机回环 `http://127.0.0.1:48921`（强制绕过 VPN/代理，零外网流量、单包 GET 命令零拆包风险），
///   让键盘在微信/抖音内无需跳出 App 即可直接录音并实时双语转换（对齐 讯飞/豆包/Wispr Flow 方案）。
struct VoiceIPCCommand: Codable, Equatable {
    enum Action: String, Codable {
        case start
        case stop
        case clear
        case ping
    }

    var action: Action
    var modeRaw: String
    var timestamp: TimeInterval = Date().timeIntervalSince1970
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
    var updatedAt: TimeInterval = Date().timeIntervalSince1970

    var isHeartbeatFresh: Bool {
        engineWarm && (Date().timeIntervalSince1970 - updatedAt) < 18.0
    }
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

    // MARK: - 键盘侧双通道客户端（同时兼容 App Group 与免费侧载 127.0.0.1 回环，强制绕过系统 VPN/代理）

    private static let fastSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 0.85
        cfg.timeoutIntervalForResource = 1.25
        cfg.waitsForConnectivity = false
        // 关键修复：显式清空代理字典，防止 Shadowrocket / Clash / 代理工具劫持 127.0.0.1 本机回环连接！
        cfg.connectionProxyDictionary = [:]
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    static func fetchStateFromHost() async -> VoiceIPCState? {
        if AppGroup.isAvailable, let shared = readStateFromShared(), shared.isHeartbeatFresh {
            return shared
        }
        guard let url = URL(string: "http://127.0.0.1:\(loopbackPort)/voice/state") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.assumesHTTP3Capable = false
        do {
            let (data, resp) = try await fastSession.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try JSONDecoder().decode(VoiceIPCState.self, from: data)
        } catch {
            return readStateFromShared()
        }
    }

    @discardableResult
    static func sendCommandToHost(_ cmd: VoiceIPCCommand) async -> VoiceIPCState? {
        if AppGroup.isAvailable {
            writeCommandToShared(cmd)
        }
        // 关键修复：使用单包 GET /voice/cmd?action=...&mode=... 传递指令，
        // 彻底避免 URLSession POST 头/体分两个 TCP 包发送导致微服务器漏读 JSON Body 的问题！
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = "127.0.0.1"
        comps.port = Int(loopbackPort)
        comps.path = "/voice/cmd"
        comps.queryItems = [
            URLQueryItem(name: "action", value: cmd.action.rawValue),
            URLQueryItem(name: "mode", value: cmd.modeRaw)
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
