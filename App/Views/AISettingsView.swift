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
                    Text("模型与密钥")
                } footer: {
                    Text(appState.aiConfig.provider == .gemini
                         ? "直连 Google Gemini Interactions API（v1beta/interactions），默认禁用服务端对话留存 (store=false) 保护输入隐私。"
                         : "支持 DeepSeek (https://api.deepseek.com/v1)、SiliconFlow、OpenAI 或自建反代端点。")
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
                            .foregroundStyle(testSucceeded ? .green : .red)
                    }
                } header: {
                    Text("连通性诊断")
                } footer: {
                    Text("请确保在 iOS 系统设置中为「灵犀输入法」开启了「允许完全访问」，否则键盘扩展在微信等 App 内无法发起网络请求。")
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
