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
    private let session: URLSession

    init(timeout: TimeInterval = 40) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 25
        self.session = URLSession(configuration: config)
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

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.assumesHTTP3Capable = false
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
                        var retryReq = URLRequest(url: retryURL)
                        retryReq.httpMethod = "GET"
                        retryReq.assumesHTTP3Capable = false
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
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.assumesHTTP3Capable = false
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
                var tagReq = URLRequest(url: tagsURL)
                tagReq.assumesHTTP3Capable = false
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

    // MARK: - 统一流式推理（分离思考过程与纯净正文）

    func streamEvents(
        prompt: String,
        systemInstruction: String,
        config: AIConfig = AIConfig.load(),
        featureTag: String = "ai_assistant",
        preferFast: Bool = false,
        preferDeep: Bool = false,
        modelOverride: String? = nil,
        thinkingOverride: AIThinkingMode? = nil
    ) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                var firstTokenAt: Date?
                var answerChars = 0
                var thoughtChars = 0
                let effectiveThinking = thinkingOverride ?? config.thinkingMode
                let chosenModel = (modelOverride?.isEmpty == false)
                    ? modelOverride!
                    : config.resolvedModel(preferFast: preferFast, preferDeep: preferDeep)

                let trackingYield: (AIStreamChunk) -> Void = { chunk in
                    if firstTokenAt == nil { firstTokenAt = Date() }
                    switch chunk {
                    case .thought(let t): thoughtChars += t.count
                    case .answer(let a): answerChars += a.count
                    }
                    continuation.yield(chunk)
                }

                do {
                    guard config.isConfigured else {
                        throw AIClientError.missingAPIKey
                    }
                    let finalSystem = Self.mergeSystem(base: systemInstruction, config: config)

                    switch config.provider {
                    case .gemini:
                        try await self.streamGeminiWithFallback(
                            prompt: prompt,
                            systemInstruction: finalSystem,
                            model: chosenModel,
                            thinkingMode: effectiveThinking,
                            config: config,
                            yield: trackingYield
                        )
                    case .openAICompatible:
                        try await self.streamOpenAICompatible(
                            prompt: prompt,
                            systemInstruction: finalSystem,
                            model: chosenModel,
                            thinkingMode: effectiveThinking,
                            config: config,
                            yield: trackingYield
                        )
                    }

                    let now = Date()
                    let totalMs = max(10, Int(now.timeIntervalSince(startTime) * 1000))
                    let ttftMs = max(10, Int((firstTokenAt ?? now).timeIntervalSince(startTime) * 1000))
                    let settings = LingxiSettings.load()
                    _ = TypingHabitTracker.shared.recordAIUsage(
                        AIAPIUsagePayload(
                            feature: featureTag,
                            provider: config.provider.rawValue,
                            targetLang: settings.translateTargetLang,
                            formalTone: settings.translateFormalTone,
                            inputChars: prompt.count,
                            outputChars: max(1, answerChars),
                            latencyMs: totalMs
                        )
                    )
                    AIUsageLedgerStore.append(
                        AIUsageLedgerEntry(
                            provider: config.provider.rawValue,
                            model: chosenModel,
                            feature: featureTag,
                            thinkingMode: effectiveThinking.rawValue,
                            ttftMs: ttftMs,
                            totalMs: totalMs,
                            inputChars: prompt.count,
                            outputChars: answerChars,
                            thoughtChars: thoughtChars
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
        preferDeep: Bool = false
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
                        preferDeep: preferDeep
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

    static func mergeSystem(base: String, custom: String) -> String {
        var cfg = AIConfig.load()
        cfg.customPersonaPrompt = custom
        return mergeSystem(base: base, config: cfg)
    }

    static func mergeSystem(base: String, config: AIConfig) -> String {
        var result = base
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
        let activeCards = config.contextCards.filter { $0.isEnabled && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !activeCards.isEmpty {
            let cardsText = activeCards.prefix(4).map { "[\($0.title)] \($0.content)" }.joined(separator: "\n")
            result += "\n【用户背景知识卡片（按需参考）】\n\(cardsText)"
        }
        let habitSuffix = TypingHabitTracker.shared.personalHabitSystemPromptSuffix()
        if !habitSuffix.isEmpty {
            result += "\n\(habitSuffix)"
        }
        if LingxiSettings.load().aiGeoContextEnabled {
            let geoSuffix = GeoLocationContext.load().aiTimeLocationPromptSuffix()
            if !geoSuffix.isEmpty {
                result += "\n\(geoSuffix)"
            }
        }
        return result
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

    // MARK: - Google Gemini（优先通用 streamGenerateContent SSE + 自动兼容中转站 ?key= 与降级重试）

    private func streamGeminiWithFallback(
        prompt: String,
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        config: AIConfig,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        var base = config.geminiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = AIConfig.defaultGeminiBaseURL }
        while base.hasSuffix("/") { base.removeLast() }

        do {
            try await streamGeminiGenerateContentSSE(
                base: base,
                prompt: prompt,
                systemInstruction: systemInstruction,
                model: model,
                thinkingMode: thinkingMode,
                includeThinkingConfig: thinkingMode != .auto,
                useQueryKeyAuth: false,
                config: config,
                yield: yield
            )
            return
        } catch AIClientError.httpError(let code, _) where code == 400 && thinkingMode != .auto {
            // 部分非思考模型或中转站不识别 thinkingConfig，自动剥离重试一次
            try await streamGeminiGenerateContentSSE(
                base: base,
                prompt: prompt,
                systemInstruction: systemInstruction,
                model: model,
                thinkingMode: .off,
                includeThinkingConfig: false,
                useQueryKeyAuth: false,
                config: config,
                yield: yield
            )
            return
        } catch AIClientError.httpError(let code, _) where code == 401 || code == 403 {
            // 部分第三方 Gemini 中转站仅接受 ?key= 查询参数鉴权，自动降级重试一次
            try await streamGeminiGenerateContentSSE(
                base: base,
                prompt: prompt,
                systemInstruction: systemInstruction,
                model: model,
                thinkingMode: thinkingMode,
                includeThinkingConfig: thinkingMode != .auto,
                useQueryKeyAuth: true,
                config: config,
                yield: yield
            )
            return
        } catch AIClientError.httpError(let code, _) where (code == 404 || code == 405) && base.contains("generativelanguage.googleapis.com") {
            // 仅当官方端点明确返回 404/405 时兜底尝试 Interactions API
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
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
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
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        includeThinkingConfig: Bool,
        useQueryKeyAuth: Bool,
        config: AIConfig,
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
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
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

        let payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
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
                consumeGeminiCandidateObject(obj)
            } else if !sawSSELine && rawNonSSE.count < 65536 {
                rawNonSSE += line
            }
        }

        // 兜底：部分中转站忽略 alt=sse 直接返回普通 JSON 数组或单对象
        if !sawSSELine && !rawNonSSE.isEmpty, let rawData = rawNonSSE.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: rawData) {
            if let obj = parsed as? [String: Any] {
                consumeGeminiCandidateObject(obj)
            } else if let arr = parsed as? [[String: Any]] {
                for obj in arr { consumeGeminiCandidateObject(obj) }
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
        systemInstruction: String,
        model: String,
        thinkingMode: AIThinkingMode,
        config: AIConfig,
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
                systemInstruction: systemInstruction,
                model: model,
                extraBody: extraThinking,
                config: config,
                yield: yield
            )
            return
        } catch AIClientError.httpError(let code, _) where (code == 400 || code == 422) && !extraThinking.isEmpty {
            // 部分模型或中转站不支持 enable_thinking / reasoning_effort 参数，自动剥离重试
            try await performOpenAIChatStream(
                endpoint: primaryEndpoint,
                prompt: prompt,
                systemInstruction: systemInstruction,
                model: model,
                extraBody: [:],
                config: config,
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
                systemInstruction: systemInstruction,
                model: model,
                extraBody: extraThinking,
                config: config,
                yield: yield
            )
        }
    }

    private func performOpenAIChatStream(
        endpoint: String,
        prompt: String,
        systemInstruction: String,
        model: String,
        extraBody: [String: Any],
        config: AIConfig,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        guard let url = URL(string: endpoint) else { throw AIClientError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        if !config.activeAPIKey.isEmpty {
            request.setValue("Bearer \(config.activeAPIKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in config.customHeaders where !k.isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }

        var payload: [String: Any] = [
            "model": model.isEmpty ? "deepseek-chat" : model,
            "messages": [
                ["role": "system", "content": systemInstruction],
                ["role": "user", "content": prompt],
            ],
            "temperature": config.temperature,
            "top_p": config.topP,
            "max_tokens": config.maxOutputTokens,
            "stream": true,
        ]
        for (k, v) in extraBody {
            payload[k] = v
        }
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
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = obj["choices"] as? [[String: Any]] else { continue }
                if let delta = choices.first?["delta"] as? [String: Any] {
                    emitOpenAIMessage(delta)
                } else if let msg = choices.first?["message"] as? [String: Any] {
                    emitOpenAIMessage(msg)
                }
            } else if !sawSSELine && rawNonSSE.count < 65536 {
                rawNonSSE += line
            }
        }

        // 兜底：部分中转站忽略 stream:true 直接返回非流式 JSON
        if !sawSSELine && !rawNonSSE.isEmpty,
           let data = rawNonSSE.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = obj["choices"] as? [[String: Any]],
           let msg = choices.first?["message"] as? [String: Any] {
            emitOpenAIMessage(msg)
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
