import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var revealKey = false
    @State private var isTesting = false
    @State private var testStatusMessage: String?
    @State private var testSucceeded = false

    private let client = AIClient()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("AI 引擎", selection: $appState.aiConfig.provider) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }

                    // 一键主流服务商模板预设
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            providerQuickPreset("Gemini 3.8 Flash") {
                                appState.aiConfig.provider = .gemini
                                appState.aiConfig.geminiModel = GeminiModelOption.flash38.rawValue
                            }
                            providerQuickPreset("DeepSeek V3") {
                                appState.aiConfig.provider = .openAICompatible
                                appState.aiConfig.openAIBaseURL = "https://api.deepseek.com/v1"
                                appState.aiConfig.openAIModel = "deepseek-chat"
                            }
                            providerQuickPreset("通义千问 Qwen") {
                                appState.aiConfig.provider = .openAICompatible
                                appState.aiConfig.openAIBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
                                appState.aiConfig.openAIModel = "qwen-plus"
                            }
                            providerQuickPreset("SiliconFlow") {
                                appState.aiConfig.provider = .openAICompatible
                                appState.aiConfig.openAIBaseURL = "https://api.siliconflow.cn/v1"
                                appState.aiConfig.openAIModel = "deepseek-ai/DeepSeek-V3"
                            }
                            providerQuickPreset("本地 Ollama") {
                                appState.aiConfig.provider = .openAICompatible
                                appState.aiConfig.openAIBaseURL = "http://127.0.0.1:11434/v1"
                                appState.aiConfig.openAIModel = "qwen2.5:7b"
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if appState.aiConfig.provider == .gemini {
                        Picker("Gemini 模型", selection: $appState.aiConfig.geminiModel) {
                            ForEach(GeminiModelOption.allCases) { opt in
                                Text(opt.displayName).tag(opt.rawValue)
                            }
                        }

                        apiKeyField(
                            title: "Gemini API Key",
                            placeholder: "AIza...",
                            text: $appState.aiConfig.geminiAPIKey
                        )
                    } else {
                        TextField("接口 Base URL", text: $appState.aiConfig.openAIBaseURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("模型名称", text: $appState.aiConfig.openAIModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        apiKeyField(
                            title: "API Key",
                            placeholder: "sk-...",
                            text: $appState.aiConfig.openAIAPIKey
                        )
                    }
                } header: {
                    Text("模型与密钥（支持主流 API 与本地私有模型一键预设）")
                } footer: {
                    Text(appState.aiConfig.provider == .gemini
                         ? "直连 Google Gemini Interactions API（v1beta/interactions），默认禁用服务端对话留存 (store=false) 保护输入隐私。"
                         : "支持 DeepSeek、通义千问、SiliconFlow、OpenAI 或自建 Ollama 本地离线推理端点。")
                }

                // 实时打字习惯感知 → AI 动态人设闭环
                Section {
                    let habitSuffix = TypingHabitTracker.shared.personalHabitSystemPromptSuffix()
                    let profile = appState.habitProfile
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("打字习惯感知引擎已联动", systemImage: "brain.head.profile")
                                .font(.subheadline.bold())
                                .foregroundStyle(Color(Design.Palette.ink))
                            Spacer()
                            Text(profile.domainAffinity.primaryDomain)
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color(Design.Palette.surface))
                                .clipShape(Capsule())
                        }
                        Text(habitSuffix.isEmpty
                             ? "日常打字与使用 AI 后，灵犀会自动分析您的句长节奏、常用词库领域（科技/商务/日常/学术）与正式度偏好，并自动微调 AI 润色和翻译语气。"
                             : "当前自动注入的个人习惯上下文：\n\(habitSuffix)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("个人打字习惯 → AI 动态文风自适应")
                }

                Section("文风偏好与创意度") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Temperature（创造力）")
                            Spacer()
                            Text(String(format: "%.1f", appState.aiConfig.temperature))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $appState.aiConfig.temperature, in: 0.0...1.2, step: 0.1)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("个人常用人设补充（可选）")
                            .font(.subheadline)
                        TextField("例如：口吻简洁友好，偏科技从业者风格，少用感叹号", text: $appState.aiConfig.customPersonaPrompt, axis: .vertical)
                            .lineLimit(2...4)
                    }

                    Picker("译 · 默认翻译目标语种", selection: $appState.settings.translateTargetLang) {
                        ForEach(TranslateTargetLanguage.allCases) { lang in
                            Text(lang.rawValue).tag(lang.rawValue)
                        }
                    }
                }

                Section {
                    Button {
                        runConnectivityTest()
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView().padding(.trailing, 6)
                            } else {
                                Image(systemName: "bolt.horizontal.circle.fill")
                            }
                            Text(isTesting ? "正在测试连接…" : "测试 AI 连通性")
                            Spacer()
                        }
                    }
                    .disabled(isTesting || !appState.aiConfig.isConfigured)

                    if let msg = testStatusMessage {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(
                                testSucceeded
                                    ? Color(Design.Palette.success)
                                    : Color(Design.Palette.error)
                            )
                    }
                } header: {
                    Text("连通性诊断")
                } footer: {
                    Text("普通拼音/双拼/五笔打字 100% 在本地 SQLite 引擎离线完成；仅当您主动点击顶栏「✨ 灵犀 AI」或「💬 译」时才会调用您配置的模型接口。")
                }

                Section("键盘内支持的 AI 技能") {
                    ForEach(AIPresetAction.allCases) { action in
                        Label(action.title, systemImage: action.icon)
                    }
                }
            }
            .navigationTitle("AI 灵犀助手")
        }
    }

    private func providerQuickPreset(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(Design.Palette.surface))
                .foregroundStyle(Color(Design.Palette.ink))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func apiKeyField(title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            if revealKey {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                SecureField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Button {
                revealKey.toggle()
            } label: {
                Image(systemName: revealKey ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func runConnectivityTest() {
        isTesting = true
        testStatusMessage = nil
        let snapshot = appState.aiConfig
        Task {
            do {
                let reply = try await client.testConnection(config: snapshot)
                await MainActor.run {
                    isTesting = false
                    testSucceeded = true
                    testStatusMessage = "连接成功：\(reply)"
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testSucceeded = false
                    testStatusMessage = "测试失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
