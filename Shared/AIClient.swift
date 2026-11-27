import Foundation

enum AIClientError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case httpError(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先在「灵犀输入法 App -> AI 智脑」中填写 API Key（本地 Ollama 无需填写）"
        case .invalidEndpoint:
            return "AI 接口地址格式无效"
        case .httpError(let code, let message):
            switch code {
            case 401:
                return "接口鉴权失败 (401)：API Key 无效或未授权，请检查是否粘贴完整。\(message.isEmpty ? "" : " (\(message))")"
            case 403:
                return "接口拒绝访问 (403)：当前 Key 无该模型权限、渠道余额不足或地区受限。\(message.isEmpty ? "" : " (\(message))")"
            case 404:
                return "接口或模型不存在 (404)：请检查接口地址是否含 /v1 或重新拉取模型。\(message.isEmpty ? "" : " (\(message))")"
            case 429:
                return "请求过于频繁或额度已耗尽 (429)：\(message)"
            default:
                return "请求失败 (\(code)): \(message)"
            }
        case .emptyResponse:
            return "模型未返回有效正文内容"
        }
    }
}

/// 流式输出事件：严格分离「思考推理链」与「可直接上屏正文」，绝不把 <think> 草稿混入输入框。
enum AIStreamChunk: Equatable {
    case thought(String)
    case answer(String)
}

/// 跨协议真实 Token 消耗统计（OpenAI `usage` / Gemini `usageMetadata`）。
struct AITokenUsage: Equatable {
    var promptTokens: Int? = nil
    var completionTokens: Int? = nil
    var reasoningTokens: Int? = nil
}

/// 跨分片健壮解析 `<think>...</think>` 标签的状态机，确保任意流式切分都不会泄漏思考草稿。
struct ThinkTagStreamSplitter {
    private var insideThink = false
    private var pending = ""

    mutating func push(_ delta: String) -> [AIStreamChunk] {
        guard !delta.isEmpty else { return [] }
        pending += delta
        var out: [AIStreamChunk] = []

        while !pending.isEmpty {
            if insideThink {
                if let closeRange = pending.range(of: "</think>") {
                    let thoughtPart = String(pending[..<closeRange.lowerBound])
                    if !thoughtPart.isEmpty { out.append(.thought(thoughtPart)) }
                    pending = String(pending[closeRange.upperBound...])
                    insideThink = false
                } else {
                    // 保留末尾可能是不完整的 "</think>" 前缀（最多 7 字符）
                    let keep = min(7, pending.count)
                    let flushCount = pending.count - keep
                    if flushCount > 0 {
                        let idx = pending.index(pending.startIndex, offsetBy: flushCount)
                        out.append(.thought(String(pending[..<idx])))
                        pending = String(pending[idx...])
                    }
                    break
                }
            } else {
                if let openRange = pending.range(of: "<think>") {
                    let answerPart = String(pending[..<openRange.lowerBound])
                    if !answerPart.isEmpty { out.append(.answer(answerPart)) }
                    pending = String(pending[openRange.upperBound...])
                    insideThink = true
                } else {
                    let keep = min(6, pending.count)
                    let flushCount = pending.count - keep
                    if flushCount > 0 {
                        let idx = pending.index(pending.startIndex, offsetBy: flushCount)
                        out.append(.answer(String(pending[..<idx])))
                        pending = String(pending[idx...])
                    }
                    break
                }
            }
        }
        return out
    }

    mutating func finish() -> [AIStreamChunk] {
        guard !pending.isEmpty else { return [] }
        let rem = pending
        pending = ""
        return [insideThink ? .thought(rem) : .answer(rem)]
    }
}

/// 零第三方依赖的全能流式 AI 客户端：
/// - 支持 Google Gemini（Interactions API + 自动降级兼容中转站 generateContent SSE）
/// - 支持 OpenAI 兼容全生态（DeepSeek / Qwen / OpenRouter / SiliconFlow / Ollama / 自定义中转）
/// - 支持动态拉取远端模型列表 (`fetchModels`) 与全协议思考模式 (`AIThinkingMode`)。
final class AIClient {
    /// 进程级共享连接池：彻底消除 SwiftUI 视图重绘与键盘扩展内频繁实例化 `AIClient` 造成的 `URLSession` 内存泄漏，
    /// 并自动复用 HTTP/2 与 TLS 会话以降低连续 AI 请求的首字延迟（TTFT）。
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private let timeout: TimeInterval
    private var session: URLSession { Self.sharedSession }

    init(timeout: TimeInterval = 40) {
        self.timeout = max(5, timeout)
    }

    private func makeRequest(url: URL, method: String = "POST") -> URLRequest {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = method
        req.assumesHTTP3Capable = false
        return req
    }

    // MARK: - 动态拉取可用模型列表（全分页 + 全协议格式 + 100% 保留完整模型 ID 与显示名）

    struct ModelPageResult: Equatable {
        let models: [AIModelInfo]
        let nextPageToken: String?
        let hasMore: Bool
        let lastID: String?
        let nextURL: String?
    }

    func fetchModels(config: AIConfig = AIConfig.load()) async throws -> [AIModelInfo] {
        guard config.isConfigured else {
            throw AIClientError.missingAPIKey
        }
        switch config.provider {
        case .gemini:
            return try await fetchGeminiModels(config: config)
        case .openAICompatible:
            return try await fetchOpenAICompatibleModels(config: config)
        case .anthropic:
            return try await fetchAnthropicModels(config: config)
        }
    }

    private func fetchGeminiModels(config: AIConfig) async throws -> [AIModelInfo] {
        var base = config.geminiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = AIConfig.defaultGeminiBaseURL }
        while base.hasSuffix("/") { base.removeLast() }
        let baseEndpoint: String
        if base.hasSuffix("/models") {
            baseEndpoint = base
        } else if base.hasSuffix("/v1beta") || base.hasSuffix("/v1") {
            baseEndpoint = "\(base)/models"
        } else {
            baseEndpoint = "\(base)/v1beta/models"
        }

        var useQueryKeyAuth = false
        var pageToken: String? = nil
        var seenTokens = Set<String>()
        var seenIDs = Set<String>()
        var collected: [AIModelInfo] = []

        for pageIndex in 0..<15 {
            guard var comps = URLComponents(string: baseEndpoint) else {
                throw AIClientError.invalidEndpoint
            }
            var items = comps.queryItems ?? []
            items.removeAll { $0.name == "pageSize" || $0.name == "pageToken" || $0.name == "key" }
            items.append(URLQueryItem(name: "pageSize", value: "1000"))
            if let token = pageToken, !token.isEmpty {
                items.append(URLQueryItem(name: "pageToken", value: token))
            }
            if useQueryKeyAuth && !config.activeAPIKey.isEmpty {
                items.append(URLQueryItem(name: "key", value: config.activeAPIKey))
            }
            comps.queryItems = items
            guard let url = comps.url else { throw AIClientError.invalidEndpoint }

            var request = makeRequest(url: url, method: "GET")
            request.setValue(config.activeAPIKey, forHTTPHeaderField: "x-goog-api-key")
            if useQueryKeyAuth && !config.activeAPIKey.isEmpty {
                request.setValue("Bearer \(config.activeAPIKey)", forHTTPHeaderField: "Authorization")
            }
            for (k, v) in config.customHeaders where !k.isEmpty {
                request.setValue(v, forHTTPHeaderField: k)
            }

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIClientError.invalidEndpoint
            }
            if !(200..<300).contains(http.statusCode) {
                // 部分第三方 Gemini 中转站仅接受 ?key= 或 Authorization: Bearer 鉴权，首页 401/403 自动降级重试一次
                if pageIndex == 0 && !useQueryKeyAuth && (http.statusCode == 401 || http.statusCode == 403) {
                    useQueryKeyAuth = true
                    var retryComps = comps
                    var retryItems = retryComps.queryItems ?? []
                    retryItems.append(URLQueryItem(name: "key", value: config.activeAPIKey))
                    retryComps.queryItems = retryItems
                    if let retryURL = retryComps.url {
                        var retryReq = makeRequest(url: retryURL, method: "GET")
                        retryReq.setValue(config.activeAPIKey, forHTTPHeaderField: "x-goog-api-key")
                        retryReq.setValue("Bearer \(config.activeAPIKey)", forHTTPHeaderField: "Authorization")
                        for (k, v) in config.customHeaders where !k.isEmpty {
                            retryReq.setValue(v, forHTTPHeaderField: k)
                        }
                        let (retryData, retryResp) = try await session.data(for: retryReq)
                        if let retryHTTP = retryResp as? HTTPURLResponse, (200..<300).contains(retryHTTP.statusCode) {
                            let page = Self.parseGeminiModelsPage(retryData, includeNonChat: true)
                            for m in page.models where seenIDs.insert(m.id).inserted {
                                collected.append(m)
                            }
                            if let next = page.nextPageToken, !next.isEmpty, seenTokens.insert(next).inserted {
                                pageToken = next
                                continue
                            }
                            break
                        }
                    }
                }
                if collected.isEmpty {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw AIClientError.httpError(http.statusCode, Self.extractErrorMessage(body))
                }
                break
            }

            let page = Self.parseGeminiModelsPage(data, includeNonChat: true)
            for m in page.models where seenIDs.insert(m.id).inserted {
                collected.append(m)
            }
            if let next = page.nextPageToken, !next.isEmpty, seenTokens.insert(next).inserted {
                pageToken = next
            } else {
                break
            }
        }

        return Self.sortFetchedModels(collected, preferDescendingID: true)
    }

    private func fetchOpenAICompatibleModels(config: AIConfig) async throws -> [AIModelInfo] {
        var base = config.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
        }
        let primaryEndpoint = base.hasSuffix("/models") ? base : "\(base)/models"
        var candidateEndpoints = [primaryEndpoint]
        let lowerBase = base.lowercased()
        let hasVersionSegment = lowerBase.contains("/v1") || lowerBase.contains("/v2") || lowerBase.contains("/v3") || lowerBase.contains("/v4") || lowerBase.hasSuffix("/models")
        if !hasVersionSegment {
            candidateEndpoints.append("\(base)/v1/models")
        }

        var lastHTTPCode = 0
        var lastErrorBody = ""

        for endpoint in candidateEndpoints {
            var seenIDs = Set<String>()
            var seenCursors = Set<String>()
            var collected: [AIModelInfo] = []
            var nextRequestURL = URL(string: endpoint)
            var endpointSucceeded = false

            for _ in 0..<15 {
                guard let url = nextRequestURL else { break }
                var request = makeRequest(url: url, method: "GET")
                if !config.activeAPIKey.isEmpty {
                    request.setValue("Bearer \(config.activeAPIKey)", forHTTPHeaderField: "Authorization")
                }
                for (k, v) in config.customHeaders where !k.isEmpty {
                    request.setValue(v, forHTTPHeaderField: k)
                }

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AIClientError.invalidEndpoint
                }
                lastHTTPCode = http.statusCode
                guard (200..<300).contains(http.statusCode) else {
                    lastErrorBody = String(data: data, encoding: .utf8) ?? ""
                    break
                }

                let page = Self.parseOpenAIModelsPage(data, includeNonChat: true)
                endpointSucceeded = true
                var addedOnThisPage = 0
                for m in page.models where seenIDs.insert(m.id).inserted {
                    collected.append(m)
                    addedOnThisPage += 1
                }

                // 自动翻页（兼容 next_page_token / nextPageToken / next_cursor / has_more+last_id / next URL）
                if let explicitNext = page.nextURL, !explicitNext.isEmpty, seenCursors.insert(explicitNext).inserted {
                    if let resolved = URL(string: explicitNext, relativeTo: url)?.absoluteURL {
                        nextRequestURL = resolved
                        continue
                    }
                }
                if let token = page.nextPageToken, !token.isEmpty, seenCursors.insert("tok:\(token)").inserted {
                    if var comps = URLComponents(string: endpoint) {
                        var q = comps.queryItems ?? []
                        q.removeAll { $0.name == "page_token" || $0.name == "pageToken" || $0.name == "cursor" }
                        q.append(URLQueryItem(name: "page_token", value: token))
                        comps.queryItems = q
                        nextRequestURL = comps.url
                        continue
                    }
                }
                if page.hasMore, addedOnThisPage > 0, let afterID = page.lastID ?? page.models.last?.id, !afterID.isEmpty,
                   seenCursors.insert("after:\(afterID)").inserted {
                    if var comps = URLComponents(string: endpoint) {
                        var q = comps.queryItems ?? []
                        q.removeAll { $0.name == "after" }
                        q.append(URLQueryItem(name: "after", value: afterID))
                        comps.queryItems = q
                        nextRequestURL = comps.url
                        continue
                    }
                }
                break
            }

            if !collected.isEmpty {
                return Self.sortFetchedModels(collected, preferDescendingID: false)
            }
            if endpointSucceeded && candidateEndpoints.count == 1 {
                break
            }
        }

        // Ollama 兼容兜底：尝试 /api/tags
        if base.contains("11434") || config.isLocalNoKeyEndpoint {
            let root = base.replacingOccurrences(of: "/v1", with: "")
            if let tagsURL = URL(string: "\(root)/api/tags") {
                let tagReq = makeRequest(url: tagsURL, method: "GET")
                let (tagData, tagResp) = try await session.data(for: tagReq)
                if let th = tagResp as? HTTPURLResponse, (200..<300).contains(th.statusCode) {
                    let parsed = Self.parseOllamaTagsPayload(tagData)
                    if !parsed.isEmpty { return parsed }
                }
            }
        }

        if lastHTTPCode == 0 {
            throw AIClientError.invalidEndpoint
        }
        throw AIClientError.httpError(lastHTTPCode, Self.extractErrorMessage(lastErrorBody))
    }

    private func fetchAnthropicModels(config: AIConfig) async throws -> [AIModelInfo] {
        var base = config.anthropicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = AIConfig.defaultAnthropicBaseURL }
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/messages") {
            base = String(base.dropLast("/messages".count))
        }
        let endpoint = base.hasSuffix("/v1") ? "\(base)/models?limit=100" : "\(base)/v1/models?limit=100"
        guard let url = URL(string: endpoint) else { throw AIClientError.invalidEndpoint }

        var request = makeRequest(url: url, method: "GET")
        request.setValue(config.activeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        for (k, v) in config.customHeaders where !k.isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.invalidEndpoint
        }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw AIClientError.httpError(http.statusCode, Self.extractErrorMessage(errBody))
        }
        let parsed = Self.parseAnthropicModelsPayload(data)
        return Self.sortFetchedModels(parsed, preferDescendingID: true)
    }

    /// 纯函数：解析 Anthropic `GET /v1/models` 响应体。
    static func parseAnthropicModelsPayload(_ data: Data) -> [AIModelInfo] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else {
            return []
        }
        var seen = Set<String>()
        var out: [AIModelInfo] = []
        for item in list {
            let id = ((item["id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            let display = ((item["display_name"] as? String) ?? id).trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(AIModelInfo(
                id: id,
                displayName: display.isEmpty ? id : display,
                supportsThinking: Self.modelLikelySupportsThinking(id),
                contextLength: 200_000,
                provider: .anthropic,
                isChatModel: true,
                ownedBy: "Anthropic"
            ))
        }
        return out
    }

    static func sortFetchedModels(_ models: [AIModelInfo], preferDescendingID: Bool) -> [AIModelInfo] {
        models.sorted { a, b in
            if a.isChatModel != b.isChatModel { return a.isChatModel }
            if a.supportsThinking != b.supportsThinking { return a.supportsThinking }
            return preferDescendingID
                ? a.id.localizedStandardCompare(b.id) == .orderedDescending
                : a.id.localizedStandardCompare(b.id) == .orderedAscending
        }
    }

    static func isLikelyNonChatModel(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        let nonChatMarkers = [
            "embedding", "embed-", "-embed", "bge-", "gte-", "e5-", "rerank",
            "whisper", "transcribe", "dall-e", "flux", "stable-diffusion", "sdxl", "kolors",
            "moderation", "aqa", "imagen", "veo", "sora", "midjourney",
            "tts-", "-tts", "cosyvoice", "fish-speech", "sensevoice", "funasr"
        ]
        if lower == "tts-1" || lower == "tts-1-hd" { return true }
        return nonChatMarkers.contains { lower.contains($0) }
    }

    static func parseGeminiModelsPage(_ data: Data, includeNonChat: Bool = true) -> ModelPageResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return ModelPageResult(models: [], nextPageToken: nil, hasMore: false, lastID: nil, nextURL: nil)
        }
        guard let obj = root as? [String: Any] else {
            // 某些代理直接返回顶层数组
            return parseOpenAIModelsPage(data, includeNonChat: includeNonChat)
        }
        guard let list = obj["models"] as? [[String: Any]] else {
            // 兼容部分 Gemini 中转站返回 OpenAI 风格的 {"data": [...]} 结构
            if obj["data"] != nil {
                let openAIPage = parseOpenAIModelsPage(data, includeNonChat: includeNonChat)
                let remapped = openAIPage.models.map { m in
                    AIModelInfo(
                        id: m.id,
                        displayName: m.displayName,
                        supportsThinking: m.supportsThinking,
                        contextLength: m.contextLength,
                        provider: .gemini,
                        isChatModel: m.isChatModel,
                        ownedBy: m.ownedBy
                    )
                }
                return ModelPageResult(
                    models: remapped,
                    nextPageToken: openAIPage.nextPageToken,
                    hasMore: openAIPage.hasMore,
                    lastID: openAIPage.lastID,
                    nextURL: openAIPage.nextURL
                )
            }
            return ModelPageResult(models: [], nextPageToken: nil, hasMore: false, lastID: nil, nextURL: nil)
        }

        var seen = Set<String>()
        var results: [AIModelInfo] = []
        for item in list {
            let rawName = (item["name"] as? String) ?? (item["id"] as? String) ?? ""
            let trimmedRaw = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRaw.isEmpty else { continue }
            let cleanID = trimmedRaw.hasPrefix("models/") ? String(trimmedRaw.dropFirst("models/".count)) : trimmedRaw
            guard !cleanID.isEmpty, seen.insert(cleanID).inserted else { continue }

            var isChat = !Self.isLikelyNonChatModel(cleanID)
            if let methods = item["supportedGenerationMethods"] as? [String], !methods.isEmpty {
                let supportsGen = methods.contains("generateContent") || methods.contains("bidiGenerateContent")
                if !supportsGen { isChat = false }
            }
            if !includeNonChat && !isChat { continue }

            let display = (item["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let inputLimit = (item["inputTokenLimit"] as? Int) ?? (item["context_length"] as? Int)
            let supportsThinking = Self.modelLikelySupportsThinking(cleanID) || (item["thinking"] as? Bool == true)
            results.append(AIModelInfo(
                id: cleanID,
                displayName: (display?.isEmpty == false) ? display! : cleanID,
                supportsThinking: supportsThinking,
                contextLength: inputLimit,
                provider: .gemini,
                isChatModel: isChat,
                ownedBy: "Google"
            ))
        }

        let nextToken = (obj["nextPageToken"] as? String) ?? (obj["next_page_token"] as? String)
        return ModelPageResult(
            models: results,
            nextPageToken: (nextToken?.isEmpty == false) ? nextToken : nil,
            hasMore: (nextToken?.isEmpty == false),
            lastID: results.last?.id,
            nextURL: nil
        )
    }

    static func parseGeminiModelsPayload(_ data: Data, includeNonChat: Bool = false) -> [AIModelInfo] {
        let page = parseGeminiModelsPage(data, includeNonChat: includeNonChat)
        return sortFetchedModels(page.models, preferDescendingID: true)
    }

    static func parseOpenAIModelsPage(_ data: Data, includeNonChat: Bool = true) -> ModelPageResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return ModelPageResult(models: [], nextPageToken: nil, hasMore: false, lastID: nil, nextURL: nil)
        }

        var rawItems: [Any] = []
        var obj: [String: Any] = [:]

        if let dict = root as? [String: Any] {
            obj = dict
            if let arr = dict["data"] as? [Any] {
                rawItems = arr
            } else if let nested = dict["data"] as? [String: Any] {
                rawItems = (nested["models"] as? [Any])
                    ?? (nested["list"] as? [Any])
                    ?? (nested["items"] as? [Any])
                    ?? (nested["data"] as? [Any])
                    ?? []
            } else if let arr = dict["models"] as? [Any] {
                rawItems = arr
            } else if let arr = dict["items"] as? [Any] {
                rawItems = arr
            } else if let arr = dict["list"] as? [Any] {
                rawItems = arr
            } else if let arr = dict["result"] as? [Any] {
                rawItems = arr
            } else if let arr = dict["results"] as? [Any] {
                rawItems = arr
            }
        } else if let arr = root as? [Any] {
            rawItems = arr
        }

        var seen = Set<String>()
        var results: [AIModelInfo] = []
        for entry in rawItems {
            if let strID = entry as? String {
                let id = strID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, seen.insert(id).inserted else { continue }
                let isChat = !Self.isLikelyNonChatModel(id)
                if !includeNonChat && !isChat { continue }
                results.append(AIModelInfo(
                    id: id,
                    displayName: id,
                    supportsThinking: Self.modelLikelySupportsThinking(id),
                    contextLength: nil,
                    provider: .openAICompatible,
                    isChatModel: isChat,
                    ownedBy: nil
                ))
                continue
            }

            guard let item = entry as? [String: Any] else { continue }
            let rawID = (item["id"] as? String)
                ?? (item["model"] as? String)
                ?? (item["name"] as? String)
                ?? ""
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }

            let isChat = !Self.isLikelyNonChatModel(id)
            if !includeNonChat && !isChat { continue }

            let rawDisplay = (item["name"] as? String)
                ?? (item["display_name"] as? String)
                ?? (item["displayName"] as? String)
                ?? (item["title"] as? String)
            let display = (rawDisplay?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? rawDisplay!.trimmingCharacters(in: .whitespacesAndNewlines)
                : id

            let ownedBy = (item["owned_by"] as? String)
                ?? (item["provider"] as? String)
                ?? (item["organization"] as? String)

            let topProvider = item["top_provider"] as? [String: Any]
            let ctx = (item["context_length"] as? Int)
                ?? (item["max_model_len"] as? Int)
                ?? (item["context_window"] as? Int)
                ?? (item["max_context_length"] as? Int)
                ?? (item["input_token_limit"] as? Int)
                ?? (topProvider?["context_length"] as? Int)

            let supportedParams = (item["supported_parameters"] as? [String]) ?? []
            let paramThinking = supportedParams.contains("reasoning") || supportedParams.contains("include_reasoning")
            let supportsThinking = Self.modelLikelySupportsThinking(id)
                || Self.modelLikelySupportsThinking(display)
                || (item["reasoning"] as? Bool == true)
                || paramThinking

            results.append(AIModelInfo(
                id: id,
                displayName: display,
                supportsThinking: supportsThinking,
                contextLength: ctx,
                provider: .openAICompatible,
                isChatModel: isChat,
                ownedBy: ownedBy
            ))
        }

        let nextToken = (obj["next_page_token"] as? String)
            ?? (obj["nextPageToken"] as? String)
            ?? (obj["next_cursor"] as? String)
            ?? (obj["nextCursor"] as? String)
        let hasMore = (obj["has_more"] as? Bool) ?? (obj["hasMore"] as? Bool) ?? false
        let lastID = (obj["last_id"] as? String) ?? (obj["lastId"] as? String) ?? results.last?.id
        let nextURL = obj["next"] as? String
        return ModelPageResult(
            models: results,
            nextPageToken: (nextToken?.isEmpty == false) ? nextToken : nil,
            hasMore: hasMore,
            lastID: lastID,
            nextURL: (nextURL?.isEmpty == false) ? nextURL : nil
        )
    }

    static func parseOpenAIModelsPayload(_ data: Data, includeNonChat: Bool = false) -> [AIModelInfo] {
        let page = parseOpenAIModelsPage(data, includeNonChat: includeNonChat)
        return page.models.sorted { $0.id < $1.id }
    }

    static func parseOllamaTagsPayload(_ data: Data) -> [AIModelInfo] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["models"] as? [[String: Any]] else {
            return []
        }
        return list.compactMap { item in
            let name = ((item["name"] as? String) ?? (item["model"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let isChat = !Self.isLikelyNonChatModel(name)
            return AIModelInfo(
                id: name,
                displayName: name,
                supportsThinking: Self.modelLikelySupportsThinking(name),
                contextLength: nil,
                provider: .openAICompatible,
                isChatModel: isChat,
                ownedBy: "Ollama"
            )
        }
    }

    static func modelLikelySupportsThinking(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        let hints = ["reasoner", "-r1", "qwq", "thinking", "qwen3", "gemini-2.5", "gemini-3", "gemini-4", "o1", "o3", "o4", "gpt-5", "claude-3-7", "claude-sonnet-4", "claude-opus-4", "claude-4", "glm-z1", "hunyuan-t1", "kimi-k2-thinking", "doubao-seed-1-6-thinking"]
        return hints.contains { lower.contains($0) }
    }

    // MARK: - 统一流式推理（分离思考过程与纯净正文，支持单轮与多轮对话）

    func streamEvents(
        prompt: String,
        systemInstruction: String,
        config: AIConfig = AIConfig.load(),
        featureTag: String = "ai_assistant",
        preferFast: Bool = false,
        preferDeep: Bool = false,
        modelOverride: String? = nil,
        thinkingOverride: AIThinkingMode? = nil,
        allowMarkdown: Bool = false
    ) -> AsyncThrowingStream<AIStreamChunk, Error> {
        streamConversationEvents(
            turns: [AIChatTurn(role: "user", content: prompt)],
            systemInstruction: systemInstruction,
            config: config,
            featureTag: featureTag,
            preferFast: preferFast,
            preferDeep: preferDeep,
            modelOverride: modelOverride,
            thinkingOverride: thinkingOverride,
            allowMarkdown: allowMarkdown
        )
    }

    /// 多轮流式推理（App 写作工作台与单轮技能共用底座，自动采集真实 Token 账本）。
    func streamConversationEvents(
        turns: [AIChatTurn],
        systemInstruction: String,
        config: AIConfig = AIConfig.load(),
        featureTag: String = "ai_assistant",
        preferFast: Bool = false,
        preferDeep: Bool = false,
        modelOverride: String? = nil,
        thinkingOverride: AIThinkingMode? = nil,
        allowMarkdown: Bool = false
    ) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                var firstTokenAt: Date?
                var answerChars = 0
                var thoughtChars = 0
                var reportedUsage = AITokenUsage()
                let effectiveThinking = thinkingOverride ?? config.thinkingMode
                let chosenModel = (modelOverride?.isEmpty == false)
                    ? modelOverride!
                    : config.resolvedModel(preferFast: preferFast, preferDeep: preferDeep)
                let cleanedTurns = turns.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let totalInputChars = cleanedTurns.reduce(0) { $0 + $1.content.count }

                // 端侧 AI 隐私脱敏护盾：开启后发往外部模型前自动脱敏，收到流式回传后在本地无感还原
                let shieldedTurns: [AIChatTurn]
                let shieldMapping: [String: String]
                if config.privacyShieldEnabled {
                    let shielded = AIPrivacyShield.sanitizeTurns(cleanedTurns, customTerms: config.privacyCustomTerms)
                    shieldedTurns = shielded.turns
                    shieldMapping = shielded.mapping
                } else {
                    shieldedTurns = cleanedTurns
                    shieldMapping = [:]
                }
                let fallbackPrompt = shieldedTurns.last?.content ?? ""
                let shouldRestore = config.privacyShieldEnabled && config.privacyAutoRestore && !shieldMapping.isEmpty
                var answerRestorer = AIPrivacyShield.StreamingRestoreBuffer(mapping: shouldRestore ? shieldMapping : [:])
                var thoughtRestorer = AIPrivacyShield.StreamingRestoreBuffer(mapping: shouldRestore ? shieldMapping : [:])

                let trackingYield: (AIStreamChunk) -> Void = { chunk in
                    if firstTokenAt == nil { firstTokenAt = Date() }
                    switch chunk {
                    case .thought(let t):
                        let restored = shouldRestore ? thoughtRestorer.push(t) : t
                        guard !restored.isEmpty else { return }
                        thoughtChars += restored.count
                        continuation.yield(.thought(restored))
                    case .answer(let a):
                        let restored = shouldRestore ? answerRestorer.push(a) : a
                        guard !restored.isEmpty else { return }
                        answerChars += restored.count
                        continuation.yield(.answer(restored))
                    }
                }

                let usageCollector: (AITokenUsage) -> Void = { u in
                    if let p = u.promptTokens { reportedUsage.promptTokens = p }
                    if let c = u.completionTokens { reportedUsage.completionTokens = c }
                    if let r = u.reasoningTokens { reportedUsage.reasoningTokens = r }
                }

                var activeProviderRaw = config.provider.rawValue
                var activeModelUsed = chosenModel

                func dispatchProvider(cfg: AIConfig, model: String, sysPrompt: String) async throws {
                    switch cfg.provider {
                    case .gemini:
                        try await self.streamGeminiWithFallback(
                            prompt: fallbackPrompt,
                            turns: shieldedTurns,
                            systemInstruction: sysPrompt,
                            model: model,
                            thinkingMode: effectiveThinking,
                            config: cfg,
                            onUsage: usageCollector,
                            yield: trackingYield
                        )
                    case .openAICompatible:
                        try await self.streamOpenAICompatible(
                            prompt: fallbackPrompt,
                            turns: shieldedTurns,
                            systemInstruction: sysPrompt,
                            model: model,
                            thinkingMode: effectiveThinking,
                            config: cfg,
                            onUsage: usageCollector,
                            yield: trackingYield
                        )
                    case .anthropic:
                        try await self.streamAnthropicWithFallback(
                            prompt: fallbackPrompt,
                            turns: shieldedTurns,
                            systemInstruction: sysPrompt,
                            model: model,
                            thinkingMode: effectiveThinking,
                            config: cfg,
                            onUsage: usageCollector,
                            yield: trackingYield
                        )
                    }
                }

                do {
                    guard config.isConfigured else {
                        throw AIClientError.missingAPIKey
                    }
                    guard !shieldedTurns.isEmpty else {
                        throw AIClientError.emptyResponse
                    }
                    var finalSystem = Self.mergeSystem(
                        base: systemInstruction,
                        userPrompt: fallbackPrompt,
                        config: config,
                        allowMarkdown: allowMarkdown
                    )
                    if !shieldMapping.isEmpty {
                        finalSystem += "\n【隐私占位符约束】输入文本中的 [PHONE_n]、[ID_n]、[EMAIL_n]、[CARD_n]、[SECRET_n]、[IP_n]、[PRIV_n] 为受保护占位符，请在输出中按原样保留这些占位符，不要篡改或省略方括号。"
                    }

                    do {
                        try await dispatchProvider(cfg: config, model: chosenModel, sysPrompt: finalSystem)
                    } catch {
                        // 生产级自动容灾切换：仅在尚未输出正文且遇到 402/429/5xx/网络超时时无缝切备用渠道档案
                        if answerChars == 0,
                           Self.shouldTriggerFailover(for: error),
                           let backup = config.resolvedFailoverConfig() {
                            if shouldRestore {
                                answerRestorer = AIPrivacyShield.StreamingRestoreBuffer(mapping: shieldMapping)
                                thoughtRestorer = AIPrivacyShield.StreamingRestoreBuffer(mapping: shieldMapping)
                            }
                            let backupModel = backup.config.resolvedModel(preferFast: preferFast, preferDeep: preferDeep)
                            activeProviderRaw = backup.config.provider.rawValue
                            activeModelUsed = backupModel
                            try await dispatchProvider(cfg: backup.config, model: backupModel, sysPrompt: finalSystem)
                        } else {
                            throw error
                        }
                    }

                    if shouldRestore {
                        let tailThought = thoughtRestorer.finish()
                        if !tailThought.isEmpty {
                            thoughtChars += tailThought.count
                            continuation.yield(.thought(tailThought))
                        }
                        let tailAnswer = answerRestorer.finish()
                        if !tailAnswer.isEmpty {
                            answerChars += tailAnswer.count
                            continuation.yield(.answer(tailAnswer))
                        }
                    }

                    let now = Date()
                    let totalMs = max(10, Int(now.timeIntervalSince(startTime) * 1000))
                    let ttftMs = max(10, Int((firstTokenAt ?? now).timeIntervalSince(startTime) * 1000))
                    let settings = LingxiSettings.load()
                    _ = TypingHabitTracker.shared.recordAIUsage(
                        AIAPIUsagePayload(
                            feature: featureTag,
                            provider: activeProviderRaw,
                            targetLang: settings.translateTargetLang,
                            formalTone: settings.translateFormalTone,
                            inputChars: totalInputChars,
                            outputChars: max(1, answerChars),
                            latencyMs: totalMs
                        )
                    )
                    AIUsageLedgerStore.append(
                        AIUsageLedgerEntry(
                            provider: activeProviderRaw,
                            model: activeModelUsed,
                            feature: featureTag,
                            thinkingMode: effectiveThinking.rawValue,
                            ttftMs: ttftMs,
                            totalMs: totalMs,
                            inputChars: totalInputChars,
                            outputChars: answerChars,
                            thoughtChars: thoughtChars,
                            promptTokens: reportedUsage.promptTokens,
                            completionTokens: reportedUsage.completionTokens,
                            reasoningTokens: reportedUsage.reasoningTokens
                        )
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 向后兼容纯正文流（自动剥离思考过程与 `<think>` 标签，严防思考草稿被直接插入宿主输入框）。
    func streamText(
        prompt: String,
        systemInstruction: String,
        config: AIConfig = AIConfig.load(),
        featureTag: String = "ai_assistant",
        preferFast: Bool = false,
        preferDeep: Bool = false,
        allowMarkdown: Bool = false
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in self.streamEvents(
                        prompt: prompt,
                        systemInstruction: systemInstruction,
                        config: config,
                        featureTag: featureTag,
                        preferFast: preferFast,
                        preferDeep: preferDeep,
                        allowMarkdown: allowMarkdown
                    ) {
                        if case .answer(let text) = event, !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func testConnection(config: AIConfig) async throws -> String {
        var collected = ""
        for try await chunk in streamText(
            prompt: "请回复：灵犀AI连接成功",
            systemInstruction: "简短直接回复，不超过20字。",
            config: config,
            featureTag: "connectivity_test"
        ) {
            collected += chunk
        }
        let trimmed = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIClientError.emptyResponse }
        return trimmed
    }

    /// 对单个路由槽位或已存渠道档案执行连通性与首字/吞吐基准测速。
    func benchmarkModel(
        config: AIConfig,
        slotLabel: String,
        profileName: String,
        modelOverride: String? = nil
    ) async -> AIModelBenchmarkResult {
        let chosen = (modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? modelOverride!.trimmingCharacters(in: .whitespacesAndNewlines)
            : config.activeModelName
        let id = "\(slotLabel)|\(profileName)|\(chosen)"
        guard config.isConfigured else {
            return AIModelBenchmarkResult(
                id: id, slotLabel: slotLabel, profileName: profileName, model: chosen,
                provider: config.provider, ok: false, ttftMs: 0, totalMs: 0, outputChars: 0,
                errorMessage: "未配置 API Key"
            )
        }
        let start = Date()
        var firstMs: Int?
        var acc = ""
        do {
            for try await ev in streamEvents(
                prompt: "请用一句话介绍输入法效率提升的要点（约35字）。",
                systemInstruction: "简明扼要，直接输出正文。",
                config: config,
                featureTag: "connectivity_test",
                modelOverride: chosen,
                thinkingOverride: .off
            ) {
                if case .answer(let a) = ev, !a.isEmpty {
                    if firstMs == nil { firstMs = Int(Date().timeIntervalSince(start) * 1000) }
                    acc += a
                }
            }
            let total = max(10, Int(Date().timeIntervalSince(start) * 1000))
            let clean = AITextSanitizer.clean(acc, streaming: false)
            guard !clean.isEmpty else {
                return AIModelBenchmarkResult(
                    id: id, slotLabel: slotLabel, profileName: profileName, model: chosen,
                    provider: config.provider, ok: false, ttftMs: firstMs ?? total, totalMs: total, outputChars: 0,
                    errorMessage: "返回空内容"
                )
            }
            return AIModelBenchmarkResult(
                id: id, slotLabel: slotLabel, profileName: profileName, model: chosen,
                provider: config.provider, ok: true, ttftMs: firstMs ?? total, totalMs: total,
                outputChars: clean.count, errorMessage: nil
            )
        } catch {
            let total = max(10, Int(Date().timeIntervalSince(start) * 1000))
            return AIModelBenchmarkResult(
                id: id, slotLabel: slotLabel, profileName: profileName, model: chosen,
                provider: config.provider, ok: false, ttftMs: firstMs ?? 0, totalMs: total,
                outputChars: acc.count, errorMessage: error.localizedDescription
            )
        }
    }

    /// 纯函数：判断主渠道异常是否属于可容灾切备用的瞬时故障（402/429/5xx/网络超时）。
    static func shouldTriggerFailover(for error: Error) -> Bool {
        if error is CancellationError { return false }
        if case let AIClientError.httpError(code, _) = error {
            return code == 402 || code == 429 || (500...599).contains(code)
        }
        if error is URLError { return true }
        return false
    }

    static func mergeSystem(base: String, custom: String, allowMarkdown: Bool = false) -> String {
        var cfg = AIConfig.load()
        cfg.customPersonaPrompt = custom
        return mergeSystem(base: base, userPrompt: "", config: cfg, allowMarkdown: allowMarkdown)
    }

    static func mergeSystem(base: String, config: AIConfig, allowMarkdown: Bool = false) -> String {
        mergeSystem(base: base, userPrompt: "", config: config, allowMarkdown: allowMarkdown)
    }

    static func mergeSystem(
        base: String,
        userPrompt: String,
        config: AIConfig,
        allowMarkdown: Bool = false
    ) -> String {
        var result = DynamicTemplateEngine.containsVariables(base) ? DynamicTemplateEngine.render(base) : base
        let sceneRule = config.activeScenePersona.systemRule
        if !sceneRule.isEmpty {
            result += "\n【当前沟通对象与场景】\(sceneRule)"
        }
        let extra = config.customPersonaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            result += "\n【用户附加人设偏好】\(extra)"
        }
        let dnaBlock = config.styleDNA.promptConstraintBlock()
        if !dnaBlock.isEmpty {
            result += "\n【个人文风 DNA 约束】\n\(dnaBlock)"
        }
        // 端侧 RAG-Lite：结合当前沟通场景与用户提问关键词相关性动态筛选 Top-4 知识卡，既精准又省 Token
        let matchedCards = PersonalContextCard.selectRelevantCards(
            from: config.contextCards,
            query: userPrompt,
            scene: config.activeScenePersona,
            limit: 4
        )
        if !matchedCards.isEmpty {
            let cardsText = matchedCards.map { "[\($0.card.title)] \($0.card.content)" }.joined(separator: "\n")
            result += "\n【用户背景知识卡片（按相关性动态检索）】\n\(cardsText)"
        }
        let habitSuffix = TypingHabitTracker.shared.personalHabitSystemPromptSuffix()
        if !habitSuffix.isEmpty {
            result += "\n\(habitSuffix)"
        }
        let cognitiveBlock = AICognitiveMemoryDB.shared.promptContextBlock(limit: 6)
        if !cognitiveBlock.isEmpty {
            result += "\n【灵犀 AI 本地 SQLite 长期认知记忆库（懂你档案）】\n\(cognitiveBlock)"
        }
        let obsidianGraphBlock = ObsidianMemoryVaultEngine.recallPromptContextBlock(
            query: userPrompt,
            scene: config.activeScenePersona.shortTitle,
            db: .shared,
            limit: 6
        )
        if !obsidianGraphBlock.isEmpty {
            result += "\n【Obsidian 双链知识图谱按需召回记忆（2-Hop Graph-RAG）】\n\(obsidianGraphBlock)"
        }
        if LingxiSettings.load().aiGeoContextEnabled {
            let geoSuffix = GeoLocationContext.load().aiTimeLocationPromptSuffix()
            if !geoSuffix.isEmpty {
                result += "\n\(geoSuffix)"
            }
        }
        // 按场景区分输出格式规则：键盘聊天直发强制纯文本，App 富文本工作台则放行标题/代码块等 Markdown 结构
        if allowMarkdown {
            result += "\n\(AITextSanitizer.richMarkdownOutputRule)"
        } else {
            result += "\n\(AITextSanitizer.plainTextOutputRule)"
        }
        return result
    }

    // MARK: - 多模态截屏识图流式推理（同时兼容 Gemini inlineData 与 OpenAI Vision image_url）

    func streamVisionEvents(
        imageData: Data,
        mimeType: String = "image/jpeg",
        prompt: String,
        systemInstruction: String,
        config: AIConfig = AIConfig.load(),
        featureTag: String = "screenshot_vision",
        thinkingOverride: AIThinkingMode? = .off
    ) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                var firstTokenAt: Date?
                var answerChars = 0
                var thoughtChars = 0
                var reportedUsage = AITokenUsage()
                let effectiveThinking = thinkingOverride ?? config.thinkingMode
                let chosenModel = config.resolvedVisionModel()
                let base64 = imageData.base64EncodedString()

                // 端侧隐私脱敏护盾：多模态看图提问词同样在出网前脱敏、回流时无闪烁还原
                var shieldMapping: [String: String] = [:]
                let shieldedPrompt: String
                if config.privacyShieldEnabled {
                    let res = AIPrivacyShield.sanitize(prompt, customTerms: config.privacyCustomTerms)
                    shieldedPrompt = res.sanitizedText
                    shieldMapping = res.mapping
                } else {
                    shieldedPrompt = prompt
                }
                let shouldRestore = config.privacyShieldEnabled && config.privacyAutoRestore && !shieldMapping.isEmpty
                var thoughtRestorer = AIPrivacyShield.StreamingRestoreBuffer(mapping: shieldMapping)
                var answerRestorer = AIPrivacyShield.StreamingRestoreBuffer(mapping: shieldMapping)

                let trackingYield: (AIStreamChunk) -> Void = { chunk in
                    if firstTokenAt == nil { firstTokenAt = Date() }
                    switch chunk {
                    case .thought(let t):
                        let restored = shouldRestore ? thoughtRestorer.push(t) : t
                        guard !restored.isEmpty else { return }
                        thoughtChars += restored.count
                        continuation.yield(.thought(restored))
                    case .answer(let a):
                        let restored = shouldRestore ? answerRestorer.push(a) : a
                        guard !restored.isEmpty else { return }
                        answerChars += restored.count
                        continuation.yield(.answer(restored))
                    }
                }

                let usageCollector: (AITokenUsage) -> Void = { u in
                    if let p = u.promptTokens { reportedUsage.promptTokens = p }
                    if let c = u.completionTokens { reportedUsage.completionTokens = c }
                    if let r = u.reasoningTokens { reportedUsage.reasoningTokens = r }
                }

                var activeProviderRaw = config.provider.rawValue
                var activeModelUsed = chosenModel

                func dispatchVision(cfg: AIConfig, model: String, sysPrompt: String) async throws {
                    switch cfg.provider {
                    case .gemini:
                        try await self.streamGeminiVisionWithFallback(
                            base64Image: base64,
                            mimeType: mimeType,
                            prompt: shieldedPrompt,
                            systemInstruction: sysPrompt,
                            model: model,
                            thinkingMode: effectiveThinking,
                            config: cfg,
                            onUsage: usageCollector,
                            yield: trackingYield
                        )
                    case .openAICompatible:
                        try await self.streamOpenAIVisionCompatible(
                            base64Image: base64,
                            mimeType: mimeType,
                            prompt: shieldedPrompt,
                            systemInstruction: sysPrompt,
                            model: model,
                            thinkingMode: effectiveThinking,
                            config: cfg,
                            onUsage: usageCollector,
                            yield: trackingYield
                        )
                    case .anthropic:
                        try await self.streamAnthropicVision(
                            base64Image: base64,
                            mimeType: mimeType,
                            prompt: shieldedPrompt,
                            systemInstruction: sysPrompt,
                            model: model,
                            config: cfg,
                            onUsage: usageCollector,
                            yield: trackingYield
                        )
                    }
                }

                do {
                    guard config.isConfigured else {
                        throw AIClientError.missingAPIKey
                    }
                    var finalSystem = Self.mergeSystem(base: systemInstruction, userPrompt: shieldedPrompt, config: config)
                    if !shieldMapping.isEmpty {
                        finalSystem += "\n【隐私占位符约束】输入文本中的 [PHONE_n]、[ID_n]、[EMAIL_n]、[CARD_n]、[SECRET_n]、[IP_n]、[PRIV_n] 为受保护占位符，请在输出中按原样保留这些占位符，不要篡改或省略方括号。"
                    }

                    do {
                        try await dispatchVision(cfg: config, model: chosenModel, sysPrompt: finalSystem)
                    } catch {
                        // 多模态识图同样支持瞬时故障自动容灾切换（仅在备用通道支持视觉时切入）
                        if answerChars == 0,
                           Self.shouldTriggerFailover(for: error),
                           let backup = config.resolvedFailoverConfig() {
                            let backupModel = backup.config.resolvedVisionModel()
                            if ScreenshotOCRService.modelLikelySupportsVision(modelID: backupModel, provider: backup.config.provider) {
                                activeProviderRaw = backup.config.provider.rawValue
                                activeModelUsed = backupModel
                                try await dispatchVision(cfg: backup.config, model: backupModel, sysPrompt: finalSystem)
                            } else {
                                throw error
                            }
                        } else {
                            throw error
                        }
                    }

                    if shouldRestore {
                        let tailThought = thoughtRestorer.finish()
                        if !tailThought.isEmpty {
                            thoughtChars += tailThought.count
                            continuation.yield(.thought(tailThought))
                        }
                        let tailAnswer = answerRestorer.finish()
                        if !tailAnswer.isEmpty {
                            answerChars += tailAnswer.count
                            continuation.yield(.answer(tailAnswer))
                        }
                    }

                    let now = Date()
                    let totalMs = max(10, Int(now.timeIntervalSince(startTime) * 1000))
                    let ttftMs = max(10, Int((firstTokenAt ?? now).timeIntervalSince(startTime) * 1000))
                    let settings = LingxiSettings.load()
                    _ = TypingHabitTracker.shared.recordAIUsage(
                        AIAPIUsagePayload(
                            feature: featureTag,
                            provider: activeProviderRaw,
                            targetLang: settings.translateTargetLang,
                            formalTone: settings.translateFormalTone,
                            inputChars: prompt.count,
                            outputChars: max(1, answerChars),
                            latencyMs: totalMs
                        )
                    )
                    AIUsageLedgerStore.append(
                        AIUsageLedgerEntry(
                            provider: activeProviderRaw,
                            model: activeModelUsed,
                            feature: featureTag,
                            thinkingMode: effectiveThinking.rawValue,
                            ttftMs: ttftMs,
                            totalMs: totalMs,
                            inputChars: prompt.count,
                            outputChars: answerChars,
                            thoughtChars: thoughtChars,
                            promptTokens: reportedUsage.promptTokens,
                            completionTokens: reportedUsage.completionTokens,
                            reasoningTokens: reportedUsage.reasoningTokens
                        )
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func streamGeminiVisionWithFallback(
        base64Image: String,
        mimeType: String,
        prompt: String,
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        config: AIConfig,
        onUsage: ((AITokenUsage) -> Void)? = nil,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        var base = config.geminiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = AIConfig.defaultGeminiBaseURL }
        while base.hasSuffix("/") { base.removeLast() }

        let parts: [[String: Any]] = [
            ["inlineData": ["mimeType": mimeType, "data": base64Image]],
            ["text": prompt],
        ]

        do {
            try await streamGeminiGenerateContentSSE(
                base: base,
                prompt: prompt,
                userPartsOverride: parts,
                systemInstruction: systemInstruction,
                model: model,
                thinkingMode: thinkingMode,
                includeThinkingConfig: false,
                useQueryKeyAuth: false,
                config: config,
                onUsage: onUsage,
                yield: yield
            )
            return
        } catch AIClientError.httpError(let code, _) where code == 401 || code == 403 {
            try await streamGeminiGenerateContentSSE(
                base: base,
                prompt: prompt,
                userPartsOverride: parts,
                systemInstruction: systemInstruction,
                model: model,
                thinkingMode: thinkingMode,
                includeThinkingConfig: false,
                useQueryKeyAuth: true,
                config: config,
                onUsage: onUsage,
                yield: yield
            )
        }
    }

    private func streamOpenAIVisionCompatible(
        base64Image: String,
        mimeType: String,
        prompt: String,
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        config: AIConfig,
        onUsage: ((AITokenUsage) -> Void)? = nil,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        var base = config.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        let primaryEndpoint = base.hasSuffix("/chat/completions") ? base : "\(base)/chat/completions"
        let userContent: [[String: Any]] = [
            ["type": "text", "text": prompt],
            ["type": "image_url", "image_url": ["url": "data:\(mimeType);base64,\(base64Image)"]],
        ]

        do {
            try await performOpenAIChatStream(
                endpoint: primaryEndpoint,
                prompt: prompt,
                userContentOverride: userContent,
                systemInstruction: systemInstruction,
                model: model,
                extraBody: [:],
                config: config,
                onUsage: onUsage,
                yield: yield
            )
        } catch AIClientError.httpError(let code, _) where code == 404 {
            let lowerBase = base.lowercased()
            let hasVersion = lowerBase.contains("/v1") || lowerBase.contains("/v2") || lowerBase.contains("/v3") || lowerBase.contains("/v4") || lowerBase.hasSuffix("/chat/completions")
            guard !hasVersion else { throw AIClientError.httpError(code, "接口路径或当前模型不支持视觉识图") }
            try await performOpenAIChatStream(
                endpoint: "\(base)/v1/chat/completions",
                prompt: prompt,
                userContentOverride: userContent,
                systemInstruction: systemInstruction,
                model: model,
                extraBody: [:],
                config: config,
                onUsage: onUsage,
                yield: yield
            )
        }
    }

    // MARK: - 音频直接识别与双语转换（供键盘内 WKWebView 录音在离线语音权限未开时云端无缝兜底）

    /// 将键盘内录制好的 16kHz WAV 音频直接发给支持音频的模型（Gemini 原生音频理解 / OpenAI 兼容 `/audio/transcriptions`）完成转写与目标语种转换。
    func transcribeAndTranslateAudio(
        wavData: Data,
        mode: VoiceTranslateMode,
        config: AIConfig = AIConfig.load()
    ) async throws -> (transcript: String, translated: String) {
        guard config.isConfigured else {
            throw AIClientError.missingAPIKey
        }
        let audioStart = Date()
        switch config.provider {
        case .gemini:
            var base = config.geminiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if base.isEmpty { base = AIConfig.defaultGeminiBaseURL }
            while base.hasSuffix("/") { base.removeLast() }
            let model = config.sttModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? config.resolvedModel(preferFast: true, preferDeep: false)
                : config.sttModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let base64Audio = wavData.base64EncodedString()
            let prompt = """
            请听取这段语音，完成两件事并严格按下面两行格式输出（不要任何 Markdown、星号、引号或多余解释）：
            原文：<逐字听写用户说出的\(mode.sourceLanguageLabel)内容>
            结果：<按要求输出最终的\(mode.targetLanguageLabel)文本：\(mode.systemPrompt)>
            """
            let parts: [[String: Any]] = [
                ["inlineData": ["mimeType": "audio/wav", "data": base64Audio]],
                ["text": prompt],
            ]
            var acc = ""
            var reportedUsage = AITokenUsage()
            let yieldHandler: (AIStreamChunk) -> Void = { chunk in
                if case .answer(let delta) = chunk { acc += delta }
            }
            let usageHandler: (AITokenUsage) -> Void = { u in
                if let p = u.promptTokens { reportedUsage.promptTokens = p }
                if let c = u.completionTokens { reportedUsage.completionTokens = c }
                if let r = u.reasoningTokens { reportedUsage.reasoningTokens = r }
            }
            do {
                try await streamGeminiGenerateContentSSE(
                    base: base,
                    prompt: prompt,
                    userPartsOverride: parts,
                    systemInstruction: Self.mergeSystem(base: "你是精准的实时语音听写与双语翻译引擎。", config: config),
                    model: model,
                    thinkingMode: .off,
                    includeThinkingConfig: false,
                    useQueryKeyAuth: false,
                    config: config,
                    onUsage: usageHandler,
                    yield: yieldHandler
                )
            } catch AIClientError.httpError(let code, _) where code == 401 || code == 403 {
                acc = ""
                try await streamGeminiGenerateContentSSE(
                    base: base,
                    prompt: prompt,
                    userPartsOverride: parts,
                    systemInstruction: Self.mergeSystem(base: "你是精准的实时语音听写与双语翻译引擎。", config: config),
                    model: model,
                    thinkingMode: .off,
                    includeThinkingConfig: false,
                    useQueryKeyAuth: true,
                    config: config,
                    onUsage: usageHandler,
                    yield: yieldHandler
                )
            }
            let cleaned = AITextSanitizer.clean(acc, streaming: false)
            var src = ""
            var dst = ""
            for line in cleaned.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("原文：") || t.hasPrefix("原文:") {
                    src = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else if t.hasPrefix("结果：") || t.hasPrefix("结果:") {
                    dst = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
            }
            if dst.isEmpty { dst = cleaned }
            if src.isEmpty { src = dst }
            let elapsedMs = max(10, Int(Date().timeIntervalSince(audioStart) * 1000))
            let settings = LingxiSettings.load()
            _ = TypingHabitTracker.shared.recordAIUsage(
                AIAPIUsagePayload(
                    feature: "voice_audio_translate",
                    provider: config.provider.rawValue,
                    targetLang: settings.translateTargetLang,
                    formalTone: settings.translateFormalTone,
                    inputChars: src.count,
                    outputChars: max(1, dst.count),
                    latencyMs: elapsedMs
                )
            )
            AIUsageLedgerStore.append(
                AIUsageLedgerEntry(
                    provider: config.provider.rawValue,
                    model: model,
                    feature: "voice_audio_translate",
                    thinkingMode: AIThinkingMode.off.rawValue,
                    ttftMs: elapsedMs,
                    totalMs: elapsedMs,
                    inputChars: src.count,
                    outputChars: dst.count,
                    thoughtChars: 0,
                    promptTokens: reportedUsage.promptTokens,
                    completionTokens: reportedUsage.completionTokens,
                    reasoningTokens: reportedUsage.reasoningTokens
                )
            )
            return (src, dst)

        case .anthropic:
            throw AIClientError.httpError(400, "Claude 原生接口暂不提供音频转写端点，建议在键盘内开启后台低延迟语音，或切换 Gemini / OpenAI 渠道进行云端听写。")

        case .openAICompatible:
            // 先调用 OpenAI 兼容 /audio/transcriptions（支持 OpenAI / SiliconFlow / Groq / OneAPI 等中转站）
            var base = config.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            while base.hasSuffix("/") { base.removeLast() }
            if base.hasSuffix("/chat/completions") {
                base = String(base.dropLast("/chat/completions".count))
            }
            let endpoint = "\(base)/audio/transcriptions"
            guard let url = URL(string: endpoint) else { throw AIClientError.invalidEndpoint }

            let boundary = "LingxiAudio-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            var body = Data()
            func appendField(_ name: String, _ value: String) {
                body.append(Data("--\(boundary)\r\n".utf8))
                body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
                body.append(Data("\(value)\r\n".utf8))
            }
            let whisperModel = config.resolvedSTTModel(baseURL: base)
            let langCode = mode.sourceLocaleID.hasPrefix("en") ? "en" : (mode.sourceLocaleID.hasPrefix("ja") ? "ja" : "zh")
            appendField("model", whisperModel)
            appendField("language", langCode)
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"voice.wav\"\r\n".utf8))
            body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
            body.append(wavData)
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))

            var req = makeRequest(url: url, method: "POST")
            if !config.activeAPIKey.isEmpty {
                req.setValue("Bearer \(config.activeAPIKey)", forHTTPHeaderField: "Authorization")
            }
            for (k, v) in config.customHeaders where !k.isEmpty {
                req.setValue(v, forHTTPHeaderField: k)
            }
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.httpBody = body

            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw AIClientError.invalidEndpoint }
            guard (200..<300).contains(http.statusCode) else {
                let errTxt = String(data: data, encoding: .utf8) ?? ""
                throw AIClientError.httpError(http.statusCode, Self.extractErrorMessage(errTxt))
            }
            let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let transcript = (obj["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { throw AIClientError.emptyResponse }

            if !mode.isTranslationMode {
                return (transcript, AITextSanitizer.clean(transcript, streaming: false))
            }
            var translatedAcc = ""
            for try await chunk in streamText(
                prompt: transcript,
                systemInstruction: mode.systemPrompt,
                config: config,
                featureTag: "in_keyboard_voice_audio_translate",
                preferFast: true
            ) {
                translatedAcc += chunk
            }
            return (transcript, AITextSanitizer.clean(translatedAcc, streaming: false))
        }
    }

    // MARK: - 跨协议思考参数组装器（纯函数，可直接单元测试）

    static func geminiThinkingPayload(model: String, mode: AIThinkingMode, budget: Int) -> [String: Any] {
        let lower = model.lowercased()
        let isLegacy25 = lower.contains("gemini-2.5") || lower.contains("2.0-flash-thinking")
        if isLegacy25 {
            switch mode {
            case .off: return ["thinking_budget": 0]
            case .auto: return ["thinking_budget": -1]
            case .minimal: return ["thinking_budget": 512]
            case .low: return ["thinking_budget": 1024]
            case .medium: return ["thinking_budget": 4096]
            case .high: return ["thinking_budget": 8192]
            case .customBudget: return ["thinking_budget": max(0, min(24576, budget))]
            }
        } else {
            switch mode {
            case .off: return ["thinking_level": "minimal"]
            case .auto:
                if let known = GeminiModelOption(rawValue: model) {
                    return ["thinking_level": known.defaultThinkingLevel]
                }
                return [:]
            case .minimal: return ["thinking_level": "minimal"]
            case .low: return ["thinking_level": "low"]
            case .medium: return ["thinking_level": "medium"]
            case .high: return ["thinking_level": "high"]
            case .customBudget:
                let mapped = budget <= 1024 ? "low" : (budget <= 4096 ? "medium" : "high")
                return ["thinking_level": mapped]
            }
        }
    }

    static func openAIThinkingExtraBody(model: String, baseURL: String, mode: AIThinkingMode, budget: Int) -> [String: Any] {
        guard mode != .auto else { return [:] }
        let lowerModel = model.lowercased()
        let lowerURL = baseURL.lowercased()

        // OpenAI o1 / o3 / o4 / gpt-5 或 Gemini OpenAI 兼容层
        if lowerModel.hasPrefix("o1") || lowerModel.hasPrefix("o3") || lowerModel.hasPrefix("o4") || lowerModel.contains("gpt-5") || lowerURL.contains("googleapis.com") {
            switch mode {
            case .off, .minimal: return ["reasoning_effort": "low"]
            case .low: return ["reasoning_effort": "low"]
            case .medium: return ["reasoning_effort": "medium"]
            case .high, .customBudget: return ["reasoning_effort": "high"]
            case .auto: return [:]
            }
        }

        // Qwen / DashScope / SiliconFlow / 本地 Ollama
        if lowerModel.contains("qwen") || lowerModel.contains("qwq") || lowerURL.contains("dashscope") || lowerURL.contains("siliconflow") {
            if mode == .off {
                return ["enable_thinking": false]
            }
            var extra: [String: Any] = ["enable_thinking": true]
            if mode == .customBudget {
                extra["thinking_budget"] = max(256, min(32768, budget))
            }
            return extra
        }

        return [:]
    }

    /// 判断是否为 OpenAI o1/o3/o4/gpt-5 等推理模型（要求使用 `max_completion_tokens` 且可能拒绝 `temperature`/`top_p`）。
    static func isOpenAIReasoningModel(_ model: String) -> Bool {
        let lower = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = lower.split(separator: "/").last.map(String.init) ?? lower
        return tail.hasPrefix("o1") || tail.hasPrefix("o3") || tail.hasPrefix("o4") || tail.hasPrefix("gpt-5")
    }

    /// 纯函数：解析 OpenAI 响应体中的真实 Token 统计（供账本与单测使用）。
    static func parseOpenAIUsage(from obj: [String: Any]) -> AITokenUsage? {
        guard let usage = obj["usage"] as? [String: Any] else { return nil }
        let p = usage["prompt_tokens"] as? Int
        let c = usage["completion_tokens"] as? Int
        let details = usage["completion_tokens_details"] as? [String: Any]
        let r = details?["reasoning_tokens"] as? Int
        if p == nil && c == nil && r == nil { return nil }
        return AITokenUsage(promptTokens: p, completionTokens: c, reasoningTokens: r)
    }

    /// 纯函数：解析 Gemini `usageMetadata` 中的真实 Token 统计（供账本与单测使用）。
    static func parseGeminiUsage(from obj: [String: Any]) -> AITokenUsage? {
        guard let meta = obj["usageMetadata"] as? [String: Any] else { return nil }
        let p = meta["promptTokenCount"] as? Int
        let c = meta["candidatesTokenCount"] as? Int
        let r = meta["thoughtsTokenCount"] as? Int
        if p == nil && c == nil && r == nil { return nil }
        return AITokenUsage(promptTokens: p, completionTokens: c, reasoningTokens: r)
    }

    /// 纯函数：构建 OpenAI Chat Completions 请求载荷，自动适配 o1/o3/o4/gpt-5 推理模型与多轮对话。
    static func buildOpenAIChatPayload(
        prompt: String,
        turns: [AIChatTurn] = [],
        userContentOverride: Any? = nil,
        systemInstruction: String,
        model: String,
        extraBody: [String: Any],
        config: AIConfig,
        stripSamplingParams: Bool = false,
        includeStreamUsage: Bool = true
    ) -> [String: Any] {
        let resolvedModel = model.isEmpty ? "deepseek-chat" : model
        let reasoningModel = isOpenAIReasoningModel(resolvedModel)
        var messages: [[String: Any]] = [
            ["role": reasoningModel ? "developer" : "system", "content": systemInstruction]
        ]
        if let override = userContentOverride {
            messages.append(["role": "user", "content": override])
        } else if !turns.isEmpty {
            for t in turns {
                let role = (t.role == "assistant") ? "assistant" : "user"
                messages.append(["role": role, "content": t.content])
            }
        } else {
            messages.append(["role": "user", "content": prompt])
        }

        var payload: [String: Any] = [
            "model": resolvedModel,
            "messages": messages,
            "stream": true,
        ]
        if includeStreamUsage {
            payload["stream_options"] = ["include_usage": true]
        }
        if reasoningModel {
            payload["max_completion_tokens"] = config.maxOutputTokens
        } else {
            payload["max_tokens"] = config.maxOutputTokens
            if !stripSamplingParams {
                payload["temperature"] = config.temperature
                payload["top_p"] = config.topP
            }
        }
        for (k, v) in extraBody {
            payload[k] = v
        }
        return payload
    }

    // MARK: - Google Gemini（优先通用 streamGenerateContent SSE + 自动兼容中转站 ?key= 与降级重试）

    private func streamGeminiWithFallback(
        prompt: String,
        turns: [AIChatTurn] = [],
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        config: AIConfig,
        onUsage: ((AITokenUsage) -> Void)? = nil,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        var base = config.geminiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = AIConfig.defaultGeminiBaseURL }
        while base.hasSuffix("/") { base.removeLast() }

        do {
            try await streamGeminiGenerateContentSSE(
                base: base,
                prompt: prompt,
                turns: turns,
                systemInstruction: systemInstruction,
                model: model,
                thinkingMode: thinkingMode,
                includeThinkingConfig: thinkingMode != .auto,
                useQueryKeyAuth: false,
                config: config,
                onUsage: onUsage,
                yield: yield
            )
            return
        } catch AIClientError.httpError(let code, _) where code == 400 && thinkingMode != .auto {
            // 部分非思考模型或中转站不识别 thinkingConfig，自动剥离重试一次
            try await streamGeminiGenerateContentSSE(
                base: base,
                prompt: prompt,
                turns: turns,
                systemInstruction: systemInstruction,
                model: model,
                thinkingMode: .off,
                includeThinkingConfig: false,
                useQueryKeyAuth: false,
                config: config,
                onUsage: onUsage,
                yield: yield
            )
            return
        } catch AIClientError.httpError(let code, _) where code == 401 || code == 403 {
            // 部分第三方 Gemini 中转站仅接受 ?key= 查询参数鉴权，自动降级重试一次
            try await streamGeminiGenerateContentSSE(
                base: base,
                prompt: prompt,
                turns: turns,
                systemInstruction: systemInstruction,
                model: model,
                thinkingMode: thinkingMode,
                includeThinkingConfig: thinkingMode != .auto,
                useQueryKeyAuth: true,
                config: config,
                onUsage: onUsage,
                yield: yield
            )
            return
        } catch AIClientError.httpError(let code, _) where (code == 404 || code == 405) && base.contains("generativelanguage.googleapis.com") && turns.count <= 1 {
            // 仅当官方端点明确返回 404/405 且单轮时兜底尝试 Interactions API
            try await streamGeminiInteractions(
                base: base,
                prompt: prompt,
                systemInstruction: systemInstruction,
                model: model,
                thinkingMode: thinkingMode,
                config: config,
                yield: yield
            )
        }
    }

    private func streamGeminiInteractions(
        base: String,
        prompt: String,
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        config: AIConfig,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        let endpoint = (base.hasSuffix("/v1beta") || base.hasSuffix("/v1")) ? "\(base)/interactions" : "\(base)/v1beta/interactions"
        guard let url = URL(string: endpoint) else { throw AIClientError.invalidEndpoint }
        var request = makeRequest(url: url, method: "POST")
        request.setValue(config.activeAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in config.customHeaders where !k.isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }

        var genConfig: [String: Any] = [
            "temperature": config.temperature,
            "top_p": config.topP,
            "max_output_tokens": config.maxOutputTokens,
        ]
        for (k, v) in Self.geminiThinkingPayload(model: model, mode: thinkingMode, budget: config.thinkingBudget) {
            genConfig[k] = v
        }

        let payload: [String: Any] = [
            "model": model,
            "input": prompt,
            "system_instruction": systemInstruction,
            "generation_config": genConfig,
            "store": false,
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidEndpoint }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = try await readAllText(bytes)
            throw AIClientError.httpError(http.statusCode, Self.extractErrorMessage(errBody))
        }

        var yieldedAnswer = false
        var splitter = ThinkTagStreamSplitter()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard !jsonStr.isEmpty, jsonStr != "[DONE]",
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let eventType = obj["event_type"] as? String {
                if eventType == "step.delta", let delta = obj["delta"] as? [String: Any] {
                    let dtype = delta["type"] as? String ?? ""
                    if dtype == "thought", let txt = (delta["thought"] as? String) ?? (delta["text"] as? String), !txt.isEmpty {
                        yield(.thought(txt))
                    } else if dtype == "text", let txt = delta["text"] as? String, !txt.isEmpty {
                        for item in splitter.push(txt) {
                            if case .answer = item { yieldedAnswer = true }
                            yield(item)
                        }
                    }
                } else if eventType == "error",
                          let err = obj["error"] as? [String: Any],
                          let msg = err["message"] as? String {
                    throw AIClientError.httpError(http.statusCode, msg)
                }
            }
        }
        for item in splitter.finish() {
            if case .answer = item { yieldedAnswer = true }
            yield(item)
        }
        if !yieldedAnswer { throw AIClientError.emptyResponse }
    }

    private func streamGeminiGenerateContentSSE(
        base: String,
        prompt: String,
        turns: [AIChatTurn] = [],
        userPartsOverride: [[String: Any]]? = nil,
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        includeThinkingConfig: Bool,
        useQueryKeyAuth: Bool,
        config: AIConfig,
        onUsage: ((AITokenUsage) -> Void)? = nil,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        let prefix = (base.hasSuffix("/v1beta") || base.hasSuffix("/v1")) ? base : "\(base)/v1beta"
        let cleanModel = model.hasPrefix("models/") ? String(model.dropFirst("models/".count)) : model
        let encodedModel = cleanModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanModel
        guard var comps = URLComponents(string: "\(prefix)/models/\(encodedModel):streamGenerateContent") else {
            throw AIClientError.invalidEndpoint
        }
        var qItems = [URLQueryItem(name: "alt", value: "sse")]
        if useQueryKeyAuth && !config.activeAPIKey.isEmpty {
            qItems.append(URLQueryItem(name: "key", value: config.activeAPIKey))
        }
        comps.queryItems = qItems
        guard let url = comps.url else {
            throw AIClientError.invalidEndpoint
        }
        var request = makeRequest(url: url, method: "POST")
        request.setValue(config.activeAPIKey, forHTTPHeaderField: "x-goog-api-key")
        if useQueryKeyAuth && !config.activeAPIKey.isEmpty {
            request.setValue("Bearer \(config.activeAPIKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in config.customHeaders where !k.isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }

        var genConfig: [String: Any] = [
            "temperature": config.temperature,
            "topP": config.topP,
            "maxOutputTokens": config.maxOutputTokens,
        ]
        if includeThinkingConfig && thinkingMode != .auto {
            var tc: [String: Any] = ["includeThoughts": config.showThinkingProcess]
            let mapped = Self.geminiThinkingPayload(model: cleanModel, mode: thinkingMode, budget: config.thinkingBudget)
            if let lvl = mapped["thinking_level"] { tc["thinkingLevel"] = lvl }
            if let bdg = mapped["thinking_budget"] { tc["thinkingBudget"] = bdg }
            genConfig["thinkingConfig"] = tc
        }

        let contentsPayload: [[String: Any]]
        if let overrideParts = userPartsOverride {
            contentsPayload = [["role": "user", "parts": overrideParts]]
        } else if !turns.isEmpty {
            contentsPayload = turns.map { t in
                ["role": t.role == "assistant" ? "model" : "user", "parts": [["text": t.content]]]
            }
        } else {
            contentsPayload = [["role": "user", "parts": [["text": prompt]]]]
        }
        let payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "contents": contentsPayload,
            "generationConfig": genConfig,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidEndpoint }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = try await readAllText(bytes)
            throw AIClientError.httpError(http.statusCode, Self.extractErrorMessage(errBody))
        }

        var yieldedAnswer = false
        var sawSSELine = false
        var rawNonSSE = ""
        var splitter = ThinkTagStreamSplitter()

        func consumeGeminiCandidateObject(_ obj: [String: Any]) {
            if let usage = Self.parseGeminiUsage(from: obj) {
                onUsage?(usage)
            }
            guard let cands = obj["candidates"] as? [[String: Any]],
                  let content = cands.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return }
            for part in parts {
                guard let txt = part["text"] as? String, !txt.isEmpty else { continue }
                if part["thought"] as? Bool == true {
                    yield(.thought(txt))
                } else {
                    for item in splitter.push(txt) {
                        if case .answer = item { yieldedAnswer = true }
                        yield(item)
                    }
                }
            }
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.hasPrefix("data:") {
                sawSSELine = true
                let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                guard !jsonStr.isEmpty, jsonStr != "[DONE]",
                      let data = jsonStr.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if let embedded = Self.extractEmbeddedStreamError(from: obj) {
                    throw AIClientError.httpError(embedded.code, embedded.message)
                }
                consumeGeminiCandidateObject(obj)
            } else if !sawSSELine && rawNonSSE.count < 65536 {
                rawNonSSE += line
            }
        }

        // 兜底：部分中转站忽略 alt=sse 直接返回普通 JSON 数组或单对象（含 HTTP 200 嵌入式 error）
        if !sawSSELine && !rawNonSSE.isEmpty, let rawData = rawNonSSE.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: rawData) {
            if let obj = parsed as? [String: Any] {
                if let embedded = Self.extractEmbeddedStreamError(from: obj) {
                    throw AIClientError.httpError(embedded.code, embedded.message)
                }
                consumeGeminiCandidateObject(obj)
            } else if let arr = parsed as? [[String: Any]] {
                for obj in arr {
                    if let embedded = Self.extractEmbeddedStreamError(from: obj) {
                        throw AIClientError.httpError(embedded.code, embedded.message)
                    }
                    consumeGeminiCandidateObject(obj)
                }
            }
        }

        for item in splitter.finish() {
            if case .answer = item { yieldedAnswer = true }
            yield(item)
        }
        if !yieldedAnswer { throw AIClientError.emptyResponse }
    }

    // MARK: - OpenAI Compatible Chat Completions (DeepSeek / Qwen / OpenAI / SiliconFlow / OpenRouter / Ollama)

    private func streamOpenAICompatible(
        prompt: String,
        turns: [AIChatTurn] = [],
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        config: AIConfig,
        onUsage: ((AITokenUsage) -> Void)? = nil,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        var base = config.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        let primaryEndpoint = base.hasSuffix("/chat/completions") ? base : "\(base)/chat/completions"
        let extraThinking = Self.openAIThinkingExtraBody(model: model, baseURL: base, mode: thinkingMode, budget: config.thinkingBudget)

        do {
            try await performOpenAIChatStream(
                endpoint: primaryEndpoint,
                prompt: prompt,
                turns: turns,
                systemInstruction: systemInstruction,
                model: model,
                extraBody: extraThinking,
                config: config,
                stripSamplingParams: false,
                includeStreamUsage: true,
                onUsage: onUsage,
                yield: yield
            )
            return
        } catch AIClientError.httpError(let code, _) where code == 400 || code == 422 {
            // 部分中转站或推理模型不支持 enable_thinking / stream_options / temperature，自动降级为最简参数重试一次
            try await performOpenAIChatStream(
                endpoint: primaryEndpoint,
                prompt: prompt,
                turns: turns,
                systemInstruction: systemInstruction,
                model: model,
                extraBody: [:],
                config: config,
                stripSamplingParams: true,
                includeStreamUsage: false,
                onUsage: onUsage,
                yield: yield
            )
            return
        } catch AIClientError.httpError(let code, _) where code == 404 {
            let lowerBase = base.lowercased()
            let hasVersion = lowerBase.contains("/v1") || lowerBase.contains("/v2") || lowerBase.contains("/v3") || lowerBase.contains("/v4") || lowerBase.hasSuffix("/chat/completions")
            guard !hasVersion else { throw AIClientError.httpError(code, "接口路径或模型不存在") }
            try await performOpenAIChatStream(
                endpoint: "\(base)/v1/chat/completions",
                prompt: prompt,
                turns: turns,
                systemInstruction: systemInstruction,
                model: model,
                extraBody: extraThinking,
                config: config,
                stripSamplingParams: false,
                includeStreamUsage: true,
                onUsage: onUsage,
                yield: yield
            )
        }
    }

    private func performOpenAIChatStream(
        endpoint: String,
        prompt: String,
        turns: [AIChatTurn] = [],
        userContentOverride: Any? = nil,
        systemInstruction: String,
        model: String,
        extraBody: [String: Any],
        config: AIConfig,
        stripSamplingParams: Bool = false,
        includeStreamUsage: Bool = true,
        onUsage: ((AITokenUsage) -> Void)? = nil,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        guard let url = URL(string: endpoint) else { throw AIClientError.invalidEndpoint }

        var request = makeRequest(url: url, method: "POST")
        if !config.activeAPIKey.isEmpty {
            request.setValue("Bearer \(config.activeAPIKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in config.customHeaders where !k.isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let payload = Self.buildOpenAIChatPayload(
            prompt: prompt,
            turns: turns,
            userContentOverride: userContentOverride,
            systemInstruction: systemInstruction,
            model: model,
            extraBody: extraBody,
            config: config,
            stripSamplingParams: stripSamplingParams,
            includeStreamUsage: includeStreamUsage
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidEndpoint }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = try await readAllText(bytes)
            throw AIClientError.httpError(http.statusCode, Self.extractErrorMessage(errBody))
        }

        var yieldedAnswer = false
        var sawSSELine = false
        var rawNonSSE = ""
        var splitter = ThinkTagStreamSplitter()

        func emitOpenAIMessage(_ dict: [String: Any]) {
            if let reason = (dict["reasoning_content"] as? String) ?? (dict["reasoning"] as? String), !reason.isEmpty {
                yield(.thought(reason))
            }
            if let text = dict["content"] as? String, !text.isEmpty {
                for item in splitter.push(text) {
                    if case .answer = item { yieldedAnswer = true }
                    yield(item)
                }
            }
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.hasPrefix("data:") {
                sawSSELine = true
                let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if jsonStr == "[DONE]" { break }
                guard let data = jsonStr.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if let embedded = Self.extractEmbeddedStreamError(from: obj) {
                    throw AIClientError.httpError(embedded.code, embedded.message)
                }
                if let usage = Self.parseOpenAIUsage(from: obj) {
                    onUsage?(usage)
                }
                guard let choices = obj["choices"] as? [[String: Any]] else { continue }
                if let delta = choices.first?["delta"] as? [String: Any] {
                    emitOpenAIMessage(delta)
                } else if let msg = choices.first?["message"] as? [String: Any] {
                    emitOpenAIMessage(msg)
                }
            } else if !sawSSELine && rawNonSSE.count < 65536 {
                rawNonSSE += line
            }
        }

        // 兜底：部分中转站忽略 stream:true 直接返回非流式 JSON（含 HTTP 200 嵌入式 error）
        if !sawSSELine && !rawNonSSE.isEmpty,
           let data = rawNonSSE.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let embedded = Self.extractEmbeddedStreamError(from: obj) {
                throw AIClientError.httpError(embedded.code, embedded.message)
            }
            if let usage = Self.parseOpenAIUsage(from: obj) {
                onUsage?(usage)
            }
            if let choices = obj["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any] {
                emitOpenAIMessage(msg)
            }
        }

        for item in splitter.finish() {
            if case .answer = item { yieldedAnswer = true }
            yield(item)
        }
        if !yieldedAnswer { throw AIClientError.emptyResponse }
    }

    /// 纯函数：识别第三方中转站（OneAPI/NewAPI/OpenRouter/Gemini Relay）在 HTTP 200 响应体或 SSE 帧内嵌的 `{"error": ...}`，
    /// 映射出准确状态码以透出真实错误并正确触发 Auto-Failover 备用渠道切换。
    static func extractEmbeddedStreamError(from obj: [String: Any]) -> (code: Int, message: String)? {
        guard let err = obj["error"] as? [String: Any] else { return nil }
        let msg = ((err["message"] as? String) ?? (err["msg"] as? String) ?? (err["type"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty || err["code"] != nil else { return nil }
        if let intCode = err["code"] as? Int, (400...599).contains(intCode) {
            return (intCode, msg.isEmpty ? "上游返回错误 (\(intCode))" : msg)
        }
        if let strCode = err["code"] as? String, let intCode = Int(strCode), (400...599).contains(intCode) {
            return (intCode, msg.isEmpty ? "上游返回错误 (\(intCode))" : msg)
        }
        let lower = (msg + " " + ((err["type"] as? String) ?? "") + " " + ((err["status"] as? String) ?? "")).lowercased()
        let inferredCode: Int
        if lower.contains("rate_limit") || lower.contains("rate limit") || lower.contains("resource_exhausted") || lower.contains("too many") || lower.contains("限流") {
            inferredCode = 429
        } else if lower.contains("insufficient") || lower.contains("quota") || lower.contains("balance") || lower.contains("billing") || lower.contains("余额不足") || lower.contains("额度") {
            inferredCode = 402
        } else if lower.contains("overloaded") || lower.contains("unavailable") || lower.contains("service_unavailable") || lower.contains("过载") {
            inferredCode = 503
        } else if lower.contains("bad_gateway") || lower.contains("upstream") || lower.contains("timeout") || lower.contains("超时") {
            inferredCode = 502
        } else if lower.contains("unauthorized") || lower.contains("invalid_api_key") || lower.contains("authentication") {
            inferredCode = 401
        } else {
            inferredCode = 500
        }
        return (inferredCode, msg.isEmpty ? "上游通道异常" : msg)
    }

    // MARK: - Anthropic Claude 原生 Messages API（/v1/messages + Extended Thinking + 原生 Vision）

    /// 纯函数：解析 Anthropic SSE (`message_start` / `message_delta`) 的 Token 消耗。
    static func parseAnthropicUsage(from obj: [String: Any]) -> AITokenUsage? {
        if let msg = obj["message"] as? [String: Any],
           let usage = msg["usage"] as? [String: Any] {
            let input = usage["input_tokens"] as? Int
            let output = usage["output_tokens"] as? Int
            if input != nil || output != nil {
                return AITokenUsage(promptTokens: input, completionTokens: output, reasoningTokens: nil)
            }
        }
        if let usage = obj["usage"] as? [String: Any] {
            let input = usage["input_tokens"] as? Int
            let output = usage["output_tokens"] as? Int
            if input != nil || output != nil {
                return AITokenUsage(promptTokens: input, completionTokens: output, reasoningTokens: nil)
            }
        }
        return nil
    }

    /// 纯函数：构造 Anthropic `/v1/messages` 请求体（严格遵守连续同角色合并、Extended Thinking 预算与温度互斥规则）。
    static func buildAnthropicMessagesPayload(
        prompt: String,
        turns: [AIChatTurn] = [],
        userContentBlocksOverride: [[String: Any]]? = nil,
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        includeThinking: Bool,
        config: AIConfig
    ) -> [String: Any] {
        let resolvedModel = model.isEmpty ? AIConfig.defaultAnthropicModel : model
        var messages: [[String: Any]] = []

        if let blocks = userContentBlocksOverride {
            messages.append(["role": "user", "content": blocks])
        } else if !turns.isEmpty {
            for t in turns {
                let role = (t.role == "assistant") ? "assistant" : "user"
                if let last = messages.last,
                   (last["role"] as? String) == role,
                   let prevText = last["content"] as? String {
                    messages[messages.count - 1]["content"] = prevText + "\n\n" + t.content
                } else {
                    messages.append(["role": role, "content": t.content])
                }
            }
            if (messages.first?["role"] as? String) != "user" {
                messages.insert(["role": "user", "content": prompt.isEmpty ? "请继续" : prompt], at: 0)
            }
        } else {
            messages.append(["role": "user", "content": prompt])
        }

        let budget: Int? = {
            guard includeThinking else { return nil }
            switch thinkingMode {
            case .off, .auto: return nil
            case .minimal: return 1024
            case .low: return 1536
            case .medium: return 4096
            case .high: return 8192
            case .customBudget: return max(1024, min(24576, config.thinkingBudget))
            }
        }()

        var maxTok = max(256, config.maxOutputTokens)
        var payload: [String: Any] = [
            "model": resolvedModel,
            "system": systemInstruction,
            "messages": messages,
            "stream": true,
        ]
        if let budget {
            maxTok = max(maxTok, budget + 1024)
            payload["thinking"] = ["type": "enabled", "budget_tokens": budget]
            // Anthropic API 规范：启用 Extended Thinking 时不可同时传自定义 temperature / top_p
        } else {
            payload["temperature"] = min(1.0, max(0.0, config.temperature))
        }
        payload["max_tokens"] = maxTok
        return payload
    }

    private func streamAnthropicWithFallback(
        prompt: String,
        turns: [AIChatTurn] = [],
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        config: AIConfig,
        onUsage: ((AITokenUsage) -> Void)? = nil,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        let wantThinking = thinkingMode != .off && thinkingMode != .auto
        do {
            try await performAnthropicMessagesStream(
                prompt: prompt,
                turns: turns,
                userContentBlocksOverride: nil,
                systemInstruction: systemInstruction,
                model: model,
                thinkingMode: thinkingMode,
                includeThinking: wantThinking,
                config: config,
                onUsage: onUsage,
                yield: yield
            )
        } catch AIClientError.httpError(let code, _) where code == 400 && wantThinking {
            // 部分旧 Claude 模型不支持 Extended Thinking，自动剥离 thinking 字段重试
            try await performAnthropicMessagesStream(
                prompt: prompt,
                turns: turns,
                userContentBlocksOverride: nil,
                systemInstruction: systemInstruction,
                model: model,
                thinkingMode: .off,
                includeThinking: false,
                config: config,
                onUsage: onUsage,
                yield: yield
            )
        }
    }

    private func streamAnthropicVision(
        base64Image: String,
        mimeType: String,
        prompt: String,
        systemInstruction: String,
        model: String,
        config: AIConfig,
        onUsage: ((AITokenUsage) -> Void)? = nil,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        let blocks: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mimeType,
                    "data": base64Image,
                ],
            ],
            ["type": "text", "text": prompt],
        ]
        try await performAnthropicMessagesStream(
            prompt: prompt,
            turns: [],
            userContentBlocksOverride: blocks,
            systemInstruction: systemInstruction,
            model: model,
            thinkingMode: .off,
            includeThinking: false,
            config: config,
            onUsage: onUsage,
            yield: yield
        )
    }

    private func performAnthropicMessagesStream(
        prompt: String,
        turns: [AIChatTurn],
        userContentBlocksOverride: [[String: Any]]?,
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        includeThinking: Bool,
        config: AIConfig,
        onUsage: ((AITokenUsage) -> Void)?,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        var base = config.anthropicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = AIConfig.defaultAnthropicBaseURL }
        while base.hasSuffix("/") { base.removeLast() }
        let endpoint: String
        if base.hasSuffix("/messages") {
            endpoint = base
        } else if base.hasSuffix("/v1") {
            endpoint = "\(base)/messages"
        } else {
            endpoint = "\(base)/v1/messages"
        }
        guard let url = URL(string: endpoint) else { throw AIClientError.invalidEndpoint }

        var request = makeRequest(url: url, method: "POST")
        request.setValue(config.activeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in config.customHeaders where !k.isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let payload = Self.buildAnthropicMessagesPayload(
            prompt: prompt,
            turns: turns,
            userContentBlocksOverride: userContentBlocksOverride,
            systemInstruction: systemInstruction,
            model: model,
            thinkingMode: thinkingMode,
            includeThinking: includeThinking,
            config: config
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidEndpoint }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = try await readAllText(bytes)
            throw AIClientError.httpError(http.statusCode, Self.extractErrorMessage(errBody))
        }

        var yieldedAnswer = false
        var sawSSE = false
        var rawNonSSE = ""
        var splitter = ThinkTagStreamSplitter()

        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.hasPrefix("data:") {
                sawSSE = true
                let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                guard !jsonStr.isEmpty, jsonStr != "[DONE]",
                      let data = jsonStr.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if let usage = Self.parseAnthropicUsage(from: obj) {
                    onUsage?(usage)
                }
                let evType = (obj["type"] as? String) ?? ""
                if evType == "content_block_delta", let delta = obj["delta"] as? [String: Any] {
                    let dtype = (delta["type"] as? String) ?? ""
                    if dtype == "thinking_delta", let th = delta["thinking"] as? String, !th.isEmpty {
                        yield(.thought(th))
                    } else if dtype == "text_delta", let txt = delta["text"] as? String, !txt.isEmpty {
                        for item in splitter.push(txt) {
                            if case .answer = item { yieldedAnswer = true }
                            yield(item)
                        }
                    }
                } else if evType == "error",
                          let err = obj["error"] as? [String: Any],
                          let msg = err["message"] as? String {
                    throw AIClientError.httpError(http.statusCode, msg)
                }
            } else if !sawSSE && rawNonSSE.count < 65536 {
                rawNonSSE += line
            }
        }

        // 兜底：部分代理忽略 stream:true 直接返回非流式 Messages JSON
        if !sawSSE && !rawNonSSE.isEmpty,
           let data = rawNonSSE.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let usage = Self.parseAnthropicUsage(from: obj) {
                onUsage?(usage)
            }
            if let blocks = obj["content"] as? [[String: Any]] {
                for b in blocks {
                    let btype = (b["type"] as? String) ?? ""
                    if btype == "thinking", let th = b["thinking"] as? String, !th.isEmpty {
                        yield(.thought(th))
                    } else if btype == "text", let txt = b["text"] as? String, !txt.isEmpty {
                        for item in splitter.push(txt) {
                            if case .answer = item { yieldedAnswer = true }
                            yield(item)
                        }
                    }
                }
            }
        }

        for item in splitter.finish() {
            if case .answer = item { yieldedAnswer = true }
            yield(item)
        }
        if !yieldedAnswer { throw AIClientError.emptyResponse }
    }

    private func readAllText(_ bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > 4096 { break }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func extractErrorMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return body.isEmpty ? "未知错误" : String(body.prefix(160))
        }
        if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
            return msg
        }
        if let msg = obj["message"] as? String {
            return msg
        }
        return body.isEmpty ? "未知错误" : String(body.prefix(160))
    }
}
