import Foundation

enum AIClientError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case httpError(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先在「灵犀输入法 App -> AI 助手」中填写 API Key"
        case .invalidEndpoint:
            return "AI 接口地址格式无效"
        case .httpError(let code, let message):
            return "请求失败 (\(code)): \(message)"
        case .emptyResponse:
            return "模型未返回内容"
        }
    }
}

/// 零第三方依赖的流式 AI 客户端，同时支持 Gemini Interactions API 与 OpenAI 兼容接口。
final class AIClient {
    private let session: URLSession

    init(timeout: TimeInterval = 35) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 15
        self.session = URLSession(configuration: config)
    }

    func streamText(
        prompt: String,
        systemInstruction: String,
        config: AIConfig = AIConfig.load(),
        featureTag: String = "ai_assistant"
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                do {
                    guard config.isConfigured else {
                        throw AIClientError.missingAPIKey
                    }
                    let finalSystem = Self.mergeSystem(base: systemInstruction, custom: config.customPersonaPrompt)
                    switch config.provider {
                    case .gemini:
                        try await self.streamGeminiInteractions(
                            prompt: prompt,
                            systemInstruction: finalSystem,
                            config: config,
                            continuation: continuation
                        )
                    case .openAICompatible:
                        try await self.streamOpenAICompatible(
                            prompt: prompt,
                            systemInstruction: finalSystem,
                            config: config,
                            continuation: continuation
                        )
                    }
                    let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                    let settings = LingxiSettings.load()
                    _ = TypingHabitTracker.shared.recordAIUsage(
                        AIAPIUsagePayload(
                            feature: featureTag,
                            provider: config.provider.rawValue,
                            targetLang: settings.translateTargetLang,
                            formalTone: settings.translateFormalTone,
                            inputChars: prompt.count,
                            outputChars: max(1, prompt.count),
                            latencyMs: max(10, latencyMs)
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

    func testConnection(config: AIConfig) async throws -> String {
        var collected = ""
        for try await chunk in streamText(
            prompt: "请回复：灵犀AI连接成功",
            systemInstruction: "简短直接回复，不超过20字。",
            config: config
        ) {
            collected += chunk
        }
        let trimmed = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIClientError.emptyResponse }
        return trimmed
    }

    static func mergeSystem(base: String, custom: String) -> String {
        var result = base
        let extra = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            result += "\n用户附加风格偏好：\(extra)"
        }
        let habitSuffix = TypingHabitTracker.shared.personalHabitSystemPromptSuffix()
        if !habitSuffix.isEmpty {
            result += "\n\(habitSuffix)"
        }
        return result
    }

    // MARK: - Google Gemini Interactions API (v1beta/interactions)

    private func streamGeminiInteractions(
        prompt: String,
        systemInstruction: String,
        config: AIConfig,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions") else {
            throw AIClientError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.activeAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let model = config.geminiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? GeminiModelOption.flash38.rawValue
            : config.geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)

        var genConfig: [String: Any] = [
            "temperature": config.temperature,
            "max_output_tokens": 2048,
        ]
        if let known = GeminiModelOption(rawValue: model) {
            genConfig["thinking_level"] = known.defaultThinkingLevel
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
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.invalidEndpoint
        }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = try await readAllText(bytes)
            throw AIClientError.httpError(http.statusCode, Self.extractErrorMessage(errBody))
        }

        var yielded = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard !jsonStr.isEmpty, jsonStr != "[DONE]",
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let eventType = obj["event_type"] as? String {
                if eventType == "step.delta",
                   let delta = obj["delta"] as? [String: Any],
                   delta["type"] as? String == "text",
                   let text = delta["text"] as? String, !text.isEmpty {
                    yielded = true
                    continuation.yield(text)
                } else if eventType == "error",
                          let err = obj["error"] as? [String: Any],
                          let msg = err["message"] as? String {
                    throw AIClientError.httpError(http.statusCode, msg)
                }
            }
        }
        if !yielded {
            throw AIClientError.emptyResponse
        }
    }

    // MARK: - OpenAI Compatible Chat Completions

    private func streamOpenAICompatible(
        prompt: String,
        systemInstruction: String,
        config: AIConfig,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var base = config.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        let endpoint = base.hasSuffix("/chat/completions") ? base : "\(base)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw AIClientError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.activeAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let model = config.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: Any] = [
            "model": model.isEmpty ? "deepseek-chat" : model,
            "messages": [
                ["role": "system", "content": systemInstruction],
                ["role": "user", "content": prompt],
            ],
            "temperature": config.temperature,
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.invalidEndpoint
        }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = try await readAllText(bytes)
            throw AIClientError.httpError(http.statusCode, Self.extractErrorMessage(errBody))
        }

        var yielded = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if jsonStr == "[DONE]" { break }
            guard let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let text = delta["content"] as? String, !text.isEmpty else {
                continue
            }
            yielded = true
            continuation.yield(text)
        }
        if !yielded {
            throw AIClientError.emptyResponse
        }
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
