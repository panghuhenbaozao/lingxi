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
            return "请求失败 (\(code)): \(message)"
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

    // MARK: - 动态拉取可用模型列表（支持 Gemini /v1beta/models、OpenAI /models 与 Ollama /api/tags）

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
        let endpoint = base.hasSuffix("/v1beta") ? "\(base)/models?pageSize=100" : "\(base)/v1beta/models?pageSize=100"
        guard let url = URL(string: endpoint) else {
            throw AIClientError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.activeAPIKey, forHTTPHeaderField: "x-goog-api-key")
        for (k, v) in config.customHeaders where !k.isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.invalidEndpoint
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIClientError.httpError(http.statusCode, Self.extractErrorMessage(body))
        }
        return Self.parseGeminiModelsPayload(data)
    }

    private func fetchOpenAICompatibleModels(config: AIConfig) async throws -> [AIModelInfo] {
        var base = config.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
        }
        let endpoint = base.hasSuffix("/models") ? base : "\(base)/models"
        guard let url = URL(string: endpoint) else {
            throw AIClientError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
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
        if (200..<300).contains(http.statusCode) {
            let parsed = Self.parseOpenAIModelsPayload(data)
            if !parsed.isEmpty { return parsed }
        }

        // Ollama 兼容兜底：尝试 /api/tags
        if base.contains("11434") || config.isLocalNoKeyEndpoint {
            let root = base.replacingOccurrences(of: "/v1", with: "")
            if let tagsURL = URL(string: "\(root)/api/tags") {
                let (tagData, tagResp) = try await session.data(from: tagsURL)
                if let th = tagResp as? HTTPURLResponse, (200..<300).contains(th.statusCode) {
                    let parsed = Self.parseOllamaTagsPayload(tagData)
                    if !parsed.isEmpty { return parsed }
                }
            }
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        throw AIClientError.httpError(http.statusCode, Self.extractErrorMessage(body))
    }

    static func parseGeminiModelsPayload(_ data: Data) -> [AIModelInfo] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["models"] as? [[String: Any]] else {
            return []
        }
        var results: [AIModelInfo] = []
        for item in list {
            guard let rawName = item["name"] as? String else { continue }
            let cleanID = rawName.hasPrefix("models/") ? String(rawName.dropFirst("models/".count)) : rawName
            let lower = cleanID.lowercased()
            // 过滤纯 embedding / aqa / imagen 不可用于对话的模型
            if lower.contains("embedding") || lower.contains("aqa") || lower.contains("imagen") || lower.contains("veo") {
                continue
            }
            if let methods = item["supportedGenerationMethods"] as? [String],
               !methods.contains("generateContent") && !methods.contains("bidiGenerateContent") {
                continue
            }
            let display = (item["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let inputLimit = item["inputTokenLimit"] as? Int
            let supportsThinking = Self.modelLikelySupportsThinking(cleanID) || (item["thinking"] as? Bool == true)
            results.append(AIModelInfo(
                id: cleanID,
                displayName: (display?.isEmpty == false) ? display! : cleanID,
                supportsThinking: supportsThinking,
                contextLength: inputLimit,
                provider: .gemini
            ))
        }
        return results.sorted { a, b in
            if a.supportsThinking != b.supportsThinking { return a.supportsThinking }
            return a.id > b.id
        }
    }

    static func parseOpenAIModelsPayload(_ data: Data) -> [AIModelInfo] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else {
            return []
        }
        var seen = Set<String>()
        var results: [AIModelInfo] = []
        for item in list {
            guard let id = item["id"] as? String, !id.isEmpty, seen.insert(id).inserted else { continue }
            let lower = id.lowercased()
            if lower.contains("embedding") || lower.contains("whisper") || lower.contains("tts") || lower.contains("dall-e") || lower.contains("moderation") {
                continue
            }
            let ctx = (item["context_length"] as? Int) ?? (item["max_model_len"] as? Int)
            results.append(AIModelInfo(
                id: id,
                displayName: id,
                supportsThinking: Self.modelLikelySupportsThinking(id),
                contextLength: ctx,
                provider: .openAICompatible
            ))
        }
        return results.sorted { $0.id < $1.id }
    }

    static func parseOllamaTagsPayload(_ data: Data) -> [AIModelInfo] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["models"] as? [[String: Any]] else {
            return []
        }
        return list.compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            return AIModelInfo(
                id: name,
                displayName: name,
                supportsThinking: Self.modelLikelySupportsThinking(name),
                contextLength: nil,
                provider: .openAICompatible
            )
        }
    }

    static func modelLikelySupportsThinking(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        let hints = ["reasoner", "-r1", "qwq", "thinking", "qwen3", "gemini-2.5", "gemini-3", "gemini-4", "o1", "o3", "o4", "gpt-5", "claude-3-7", "claude-sonnet-4", "claude-opus-4"]
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

    // MARK: - Google Gemini（优先 Interactions API，中转站不支持时无缝降级至 streamGenerateContent）

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

        let isOfficial = base.contains("generativelanguage.googleapis.com")
        if isOfficial {
            do {
                try await streamGeminiInteractions(
                    base: base,
                    prompt: prompt,
                    systemInstruction: systemInstruction,
                    model: model,
                    thinkingMode: thinkingMode,
                    config: config,
                    yield: yield
                )
                return
            } catch AIClientError.httpError(let code, _) where code == 400 || code == 404 || code == 405 {
                // 部分旧版 2.5 模型或区域端点走标准 generateContent SSE
            }
        }
        try await streamGeminiGenerateContentSSE(
            base: base,
            prompt: prompt,
            systemInstruction: systemInstruction,
            model: model,
            thinkingMode: thinkingMode,
            config: config,
            yield: yield
        )
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
        let endpoint = base.hasSuffix("/v1beta") ? "\(base)/interactions" : "\(base)/v1beta/interactions"
        guard let url = URL(string: endpoint) else { throw AIClientError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
        config: AIConfig,
        yield: @escaping (AIStreamChunk) -> Void
    ) async throws {
        let prefix = base.hasSuffix("/v1beta") ? base : "\(base)/v1beta"
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        guard let url = URL(string: "\(prefix)/models/\(encodedModel):streamGenerateContent?alt=sse") else {
            throw AIClientError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.activeAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in config.customHeaders where !k.isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }

        var genConfig: [String: Any] = [
            "temperature": config.temperature,
            "topP": config.topP,
            "maxOutputTokens": config.maxOutputTokens,
        ]
        if thinkingMode != .auto {
            var tc: [String: Any] = ["includeThoughts": config.showThinkingProcess]
            let mapped = Self.geminiThinkingPayload(model: model, mode: thinkingMode, budget: config.thinkingBudget)
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
        var splitter = ThinkTagStreamSplitter()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard !jsonStr.isEmpty, jsonStr != "[DONE]",
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cands = obj["candidates"] as? [[String: Any]],
                  let content = cands.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }

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
        for item in splitter.finish() {
            if case .answer = item { yieldedAnswer = true }
            yield(item)
        }
        if !yieldedAnswer { throw AIClientError.emptyResponse }
    }

    // MARK: - OpenAI Compatible Chat Completions (DeepSeek / Qwen / OpenAI / SiliconFlow / Ollama)

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
        let endpoint = base.hasSuffix("/chat/completions") ? base : "\(base)/chat/completions"
        guard let url = URL(string: endpoint) else { throw AIClientError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
        for (k, v) in Self.openAIThinkingExtraBody(model: model, baseURL: base, mode: thinkingMode, budget: config.thinkingBudget) {
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
        var splitter = ThinkTagStreamSplitter()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if jsonStr == "[DONE]" { break }
            guard let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { continue }

            // 1. DeepSeek R1 / SiliconFlow / OpenRouter 独立思考字段 reasoning_content / reasoning
            if let reason = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String), !reason.isEmpty {
                yield(.thought(reason))
            }
            // 2. 常规正文字段（同时过滤流式内联 <think>...</think> 标签）
            if let text = delta["content"] as? String, !text.isEmpty {
                for item in splitter.push(text) {
                    if case .answer = item { yieldedAnswer = true }
                    yield(item)
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
