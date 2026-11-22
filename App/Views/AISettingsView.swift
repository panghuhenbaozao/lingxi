import SwiftUI
import UIKit

struct AISettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var revealKey = false
    @State private var isTesting = false
    @State private var testStatusMessage: String?
    @State private var testSucceeded = false
    @State private var actionFeedback: String?
    @State private var editingPrompt: CustomAIPromptTemplate?
    @State private var showNewPromptSheet = false

    private let client = AIClient()

    var body: some View {
        NavigationStack {
            Form {
                providerConfigSection
                autoInsightSection
                customPromptsStudioSection
                styleAndHabitSection
                connectivitySection
                builtInSkillsSection
            }
            .navigationTitle("AI 灵犀助手")
            .sheet(isPresented: $showNewPromptSheet) {
                CustomPromptEditorSheet(initial: nil) { created in
                    appState.addOrUpdateCustomPrompt(created)
                    showFeedback("已新建「\(created.title)」并同步至键盘 AI 栏")
                }
            }
            .sheet(item: $editingPrompt) { item in
                CustomPromptEditorSheet(initial: item) { updated in
                    appState.addOrUpdateCustomPrompt(updated)
                    showFeedback("已更新「\(updated.title)」并同步至键盘 AI 栏")
                }
            }
        }
    }

    // MARK: - 1. 模型与密钥配置

    private var providerConfigSection: some View {
        Section {
            Picker("AI 引擎", selection: $appState.aiConfig.provider) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }

            // 一键主流服务商模板预设（自动高亮当前选中模型）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    providerQuickPreset(
                        "Gemini 3.8 Flash",
                        isActive: appState.aiConfig.provider == .gemini && appState.aiConfig.geminiModel == GeminiModelOption.flash38.rawValue
                    ) {
                        appState.aiConfig.provider = .gemini
                        appState.aiConfig.geminiModel = GeminiModelOption.flash38.rawValue
                    }
                    providerQuickPreset(
                        "DeepSeek V3",
                        isActive: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("deepseek.com")
                    ) {
                        appState.aiConfig.provider = .openAICompatible
                        appState.aiConfig.openAIBaseURL = "https://api.deepseek.com/v1"
                        appState.aiConfig.openAIModel = "deepseek-chat"
                    }
                    providerQuickPreset(
                        "通义千问 Qwen",
                        isActive: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("dashscope.aliyuncs.com")
                    ) {
                        appState.aiConfig.provider = .openAICompatible
                        appState.aiConfig.openAIBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
                        appState.aiConfig.openAIModel = "qwen-plus"
                    }
                    providerQuickPreset(
                        "SiliconFlow",
                        isActive: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("siliconflow.cn")
                    ) {
                        appState.aiConfig.provider = .openAICompatible
                        appState.aiConfig.openAIBaseURL = "https://api.siliconflow.cn/v1"
                        appState.aiConfig.openAIModel = "deepseek-ai/DeepSeek-V3"
                    }
                    providerQuickPreset(
                        "本地 Ollama",
                        isActive: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("11434")
                    ) {
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
    }

    // MARK: - 2. 接入 AI 自动分析与专属方案生成

    private var autoInsightSection: some View {
        Section {
            Button {
                triggerAutoAnalysis()
            } label: {
                HStack(spacing: 10) {
                    if appState.isRunningAIInsight {
                        ProgressView()
                    } else {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(Color(Design.Palette.ink))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.isRunningAIInsight
                             ? "正在自动分析你的打字画像并生成专属提示词…"
                             : (appState.aiConfig.isConfigured
                                ? "✨ 立即让 AI 自动分析并生成专属提示词"
                                : "✨ 端侧即时诊断并生成推荐提示词"))
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("仅分析脱敏速度、词库领域与混淆统计，不上传任何聊天原文")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .disabled(appState.isRunningAIInsight)

            if let feedback = actionFeedback {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(Design.Palette.success))
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.success))
                }
            }

            if let report = appState.aiInsightReport {
                // 人设与风格效率诊断卡片
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(report.personaTitle)
                            .font(.headline)
                            .foregroundStyle(Color(Design.Palette.ink))
                        Spacer()
                        Text(report.sourceLabel)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(Design.Palette.surface))
                            .clipShape(Capsule())
                    }

                    Text(report.styleSummary)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !report.efficiencyDiagnosis.isEmpty {
                        Text("效率诊断：\(report.efficiencyDiagnosis)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)

                // 专属 AI 人设提示词 + 一键应用
                if !report.recommendedPersonaPrompt.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("AI 推荐专属人设提示词", systemImage: "person.text.rectangle")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            let isApplied = appState.aiConfig.customPersonaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                                == report.recommendedPersonaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                            Button(isApplied ? "已应用" : "一键应用") {
                                appState.aiConfig.customPersonaPrompt = report.recommendedPersonaPrompt
                                showFeedback("已应用专属人设提示词，键盘 AI 将按此风格输出")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isApplied ? Color(Design.Palette.surface) : Color(Design.Palette.ink))
                            .foregroundStyle(isApplied ? Color.secondary : Color(Design.Palette.canvas))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }

                        Text(report.recommendedPersonaPrompt)
                            .font(.footnote)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(Design.Palette.surface))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(.vertical, 2)
                }

                // AI 自动定制的场景提示词推荐列表
                if !report.suggestedPrompts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("为你定制的键盘提示词 (\(report.suggestedPrompts.count))", systemImage: "wand.and.stars")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("全部加入键盘") {
                                let count = appState.importSuggestedPrompts(report.suggestedPrompts)
                                showFeedback(count > 0 ? "已添加 \(count) 条定制提示词到键盘 AI 栏" : "这些定制提示词均已在你的键盘栏中")
                            }
                            .font(.caption.bold())
                            .foregroundStyle(Color(Design.Palette.ink))
                            .buttonStyle(.plain)
                        }

                        ForEach(report.suggestedPrompts) { tpl in
                            let alreadyAdded = appState.aiConfig.customPrompts.contains(where: { $0.title == tpl.title })
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: tpl.icon)
                                    .font(.subheadline)
                                    .frame(width: 24, height: 24)
                                    .background(Color(Design.Palette.surface))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(tpl.title)
                                            .font(.subheadline.bold())
                                        Text(tpl.category)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(tpl.instruction)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Button(alreadyAdded ? "已加入" : "加入") {
                                    let count = appState.importSuggestedPrompts([tpl])
                                    showFeedback(count > 0 ? "已将「\(tpl.title)」加入键盘 AI 技能栏" : "「\(tpl.title)」已在键盘栏中")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(alreadyAdded ? Color(Design.Palette.surface) : Color(Design.Palette.ink))
                                .foregroundStyle(alreadyAdded ? Color.secondary : Color(Design.Palette.canvas))
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                                .disabled(alreadyAdded)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // AI 推荐高频快捷短语
                if !report.suggestedPhrases.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("AI 推荐高频快捷短语", systemImage: "text.quote")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("一键导入短语库") {
                                let count = appState.importSuggestedPhrases(report.suggestedPhrases)
                                showFeedback(count > 0 ? "已导入 \(count) 条快捷短语，可在剪贴板/短语面板一键发送" : "推荐短语已在你的短语库中")
                            }
                            .font(.caption.bold())
                            .foregroundStyle(Color(Design.Palette.ink))
                            .buttonStyle(.plain)
                        }

                        ForEach(report.suggestedPhrases) { phrase in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(phrase.title)
                                    .font(.caption.bold())
                                Text(phrase.content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // 模糊音一键调优 + 实操建议
                if !report.suggestedFuzzyKeys.isEmpty {
                    Button {
                        let applied = appState.applySuggestedFuzzyKeys(report.suggestedFuzzyKeys)
                        let names = report.suggestedFuzzyKeys.map(AIAutoInsightService.fuzzyDisplayName(for:)).joined(separator: "、")
                        showFeedback(applied > 0 ? "已一键开启模糊音：\(names)" : "推荐模糊音均已处于开启状态")
                    } label: {
                        Label(
                            "一键开启高频混淆模糊音（\(report.suggestedFuzzyKeys.map(AIAutoInsightService.fuzzyDisplayName(for:)).joined(separator: " / "))）",
                            systemImage: "waveform.path.ecg"
                        )
                        .font(.subheadline.bold())
                    }
                }

                if !report.actionableTips.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("输入法进化建议")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(Array(report.actionableTips.enumerated()), id: \.offset) { idx, tip in
                            Text("\(idx + 1). \(tip)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("🧠 AI 自动分析与专属提示词生成")
        } footer: {
            Text("接入 AI 后会自动分析你的打字节奏、词库领域与误拼特征，生成专属人设提示词、键盘自定义技能、快捷短语与模糊音调优方案。")
        }
    }

    // MARK: - 3. 我的键盘自定义提示词库

    private var customPromptsStudioSection: some View {
        Section {
            ForEach(appState.aiConfig.customPrompts) { tpl in
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        editingPrompt = tpl
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: tpl.icon)
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .frame(width: 24, height: 24)
                                .background(Color(Design.Palette.surface))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(tpl.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    if tpl.isAIGenerated {
                                        Text("AI定制")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color(Design.Palette.surface))
                                            .clipShape(Capsule())
                                    }
                                    Text(tpl.category)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(tpl.instruction)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        appState.togglePinCustomPrompt(id: tpl.id)
                    } label: {
                        Image(systemName: tpl.isPinned ? "pin.fill" : "pin")
                            .font(.caption)
                            .foregroundStyle(tpl.isPinned ? Color(Design.Palette.ink) : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { appState.aiConfig.customPrompts[$0].id }
                for id in ids {
                    appState.deleteCustomPrompt(id: id)
                }
            }

            Button {
                showNewPromptSheet = true
            } label: {
                Label("新建专属键盘提示词", systemImage: "plus.circle.fill")
                    .font(.subheadline.bold())
            }
        } header: {
            Text("✨ 我的键盘自定义提示词库（实时同步至键盘 AI 栏）")
        } footer: {
            Text("点按任意条目可编辑指令，点按图钉可置顶到键盘 AI 栏最前方，支持左滑删除，并自动随 E2EE 加密云同步至其他设备。")
        }
    }

    // MARK: - 4. 智能协同与文风偏好

    private var styleAndHabitSection: some View {
        Section {
            Toggle("键盘内自动识别语境并置顶推荐提示词", isOn: $appState.aiConfig.smartContextRecommendEnabled)
            Toggle("测试连通成功后自动分析并生成提示词", isOn: $appState.aiConfig.autoAnalyzeOnConnect)

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

            let habitSuffix = TypingHabitTracker.shared.personalHabitSystemPromptSuffix()
            let profile = appState.habitProfile
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("打字习惯感知引擎已联动", systemImage: "waveform.and.magnifyingglass")
                        .font(.caption.bold())
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
                     ? "日常打字与使用 AI 后，灵犀会自动分析您的句长节奏、词库领域与正式度偏好，并自动微调 AI 输出语气。"
                     : "当前自动注入的个人习惯上下文：\n\(habitSuffix)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        } header: {
            Text("智能协同与文风偏好")
        }
    }

    // MARK: - 5. 连通性诊断

    private var connectivitySection: some View {
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
            Text("普通拼音/双拼/五笔打字 100% 在本地 SQLite 引擎离线完成；仅当您主动点击顶栏「✨ 灵犀 AI」「💬 译」或触发自动分析时才会调用您配置的模型接口。")
        }
    }

    // MARK: - 6. 内置基础技能一览

    private var builtInSkillsSection: some View {
        Section("键盘内置基础 AI 技能") {
            ForEach(AIPresetAction.allCases) { action in
                Label(action.title, systemImage: action.icon)
            }
        }
    }

    // MARK: - Helpers

    private func providerQuickPreset(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isActive ? Color(Design.Palette.ink) : Color(Design.Palette.surface))
                .foregroundStyle(isActive ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isActive ? Color.clear : Color(Design.Palette.hairline), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func apiKeyField(title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            if revealKey {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                SecureField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if text.wrappedValue.isEmpty {
                Button("粘贴") {
                    if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !pasted.isEmpty {
                        text.wrappedValue = pasted
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(Color(Design.Palette.ink))
                .buttonStyle(.plain)
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

    private func showFeedback(_ message: String) {
        withAnimation {
            actionFeedback = message
        }
    }

    private func triggerAutoAnalysis() {
        actionFeedback = nil
        Task {
            let report = await appState.runAIAutoAnalysis()
            await MainActor.run {
                showFeedback(report.isFromLLM
                             ? "AI 深度分析完成！已为你定制 \(report.suggestedPrompts.count) 条提示词与专属人设"
                             : "已完成端侧智能诊断，为你生成 \(report.suggestedPrompts.count) 条推荐提示词")
            }
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
                if snapshot.autoAnalyzeOnConnect {
                    let report = await appState.runAIAutoAnalysis()
                    await MainActor.run {
                        showFeedback("连通后已自动完成分析：为你生成了「\(report.personaTitle)」专属提示词方案")
                    }
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

// MARK: - 自定义提示词新建 / 编辑弹窗

private struct CustomPromptEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: CustomAIPromptTemplate?
    let onSave: (CustomAIPromptTemplate) -> Void

    @State private var title: String
    @State private var category: String
    @State private var icon: String
    @State private var instruction: String
    @State private var isPinned: Bool

    private let categories = ["效率沟通", "职场商务", "日常社交", "学习创作", "AI 自动定制"]
    private let icons = [
        "sparkles", "briefcase.fill", "bolt.fill", "doc.text.fill",
        "bubble.left.and.text.bubble.right.fill", "globe", "checklist",
        "hand.raised.fill", "wand.and.stars", "lightbulb.fill"
    ]

    init(initial: CustomAIPromptTemplate?, onSave: @escaping (CustomAIPromptTemplate) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _title = State(initialValue: initial?.title ?? "")
        _category = State(initialValue: initial?.category ?? "效率沟通")
        _icon = State(initialValue: initial?.icon ?? "sparkles")
        _instruction = State(initialValue: initial?.instruction ?? "")
        _isPinned = State(initialValue: initial?.isPinned ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("键盘按钮名称（建议 2-6 字，如：周报润色）", text: $title)
                    Picker("场景分类", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    Toggle("置顶显示在键盘 AI 栏前排", isOn: $isPinned)
                }

                Section("图标样式") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(icons, id: \.self) { sym in
                            Button {
                                icon = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.headline)
                                    .frame(width: 42, height: 36)
                                    .background(icon == sym ? Color(Design.Palette.ink) : Color(Design.Palette.surface))
                                    .foregroundStyle(icon == sym ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("AI 执行提示词（Prompt）") {
                    TextField(
                        "例如：请把我的零散工作记录整理成包含「本周完成 / 下周计划 / 风险协同」的简洁周报，语气专业不浮夸。",
                        text: $instruction,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                }
            }
            .navigationTitle(initial == nil ? "新建键盘提示词" : "编辑键盘提示词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanInst = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanTitle.isEmpty, !cleanInst.isEmpty else { return }
                        let tpl = CustomAIPromptTemplate(
                            id: initial?.id ?? UUID().uuidString,
                            title: String(cleanTitle.prefix(10)),
                            icon: icon,
                            instruction: cleanInst,
                            category: category,
                            isAIGenerated: initial?.isAIGenerated ?? false,
                            isPinned: isPinned
                        )
                        onSave(tpl)
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}
