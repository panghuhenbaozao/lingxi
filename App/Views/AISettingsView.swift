import SwiftUI
import UIKit

struct AISettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var revealKey = false
    @State private var isTesting = false
    @State private var testStatusMessage: String?
    @State private var testSucceeded = false
    @State private var fetchModelStatus: String?
    @State private var actionFeedback: String?

    @State private var showModelPicker = false
    @State private var modelAssignTarget: ModelAssignTarget = .primary
    @State private var showPlaygroundSheet = false
    @State private var showStyleClonerSheet = false
    @State private var showSaveProfileAlert = false
    @State private var newProfileName = ""

    @State private var editingPrompt: CustomAIPromptTemplate?
    @State private var showNewPromptSheet = false
    @State private var editingContextCard: PersonalContextCard?
    @State private var showNewContextCardSheet = false
    @State private var newBannedCliche = ""
    @State private var newCatchphrase = ""
    @State private var showDualModelDisclosure = false

    private let client = AIClient()

    enum ModelAssignTarget: String, Identifiable {
        case primary, fast, deep
        var id: String { rawValue }
        var title: String {
            switch self {
            case .primary: return "选择主模型"
            case .fast: return "选择极速快模型（翻译/短回复）"
            case .deep: return "选择深度思考模型（军师/分析）"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                providerAndModelSection
                thinkingAndParamsSection
                playgroundAndConnectivitySection
                styleDNAAndContextCardsSection
                autoInsightSection
                customPromptsStudioSection
                usageLedgerSection
                builtInSkillsSection
            }
            .navigationTitle("AI 灵犀智脑")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPlaygroundSheet = true
                    } label: {
                        Label("实战试炼场", systemImage: "play.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .alert("保存当前配置为渠道档案", isPresented: $showSaveProfileAlert) {
                TextField("档案名称（如：公司 Gemini 中转）", text: $newProfileName)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    appState.aiConfig.saveCurrentAsProfile(name: newProfileName)
                    showFeedback("已保存渠道档案「\(newProfileName.isEmpty ? appState.aiConfig.activeModelName : newProfileName)」")
                    newProfileName = ""
                }
            }
            .sheet(isPresented: $showModelPicker) {
                AIModelPickerSheet(
                    title: modelAssignTarget.title,
                    models: appState.aiConfig.fetchedModels,
                    currentModel: currentModelFor(target: modelAssignTarget),
                    isFetching: appState.isFetchingAIModels,
                    onRefresh: { await triggerFetchModels(openSheetOnSuccess: false) },
                    onSelect: { chosenID in
                        assignModel(chosenID, to: modelAssignTarget)
                        showFeedback("已设定模型：\(chosenID)")
                    }
                )
            }
            .sheet(isPresented: $showPlaygroundSheet) {
                AIPlaygroundAndArenaSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showStyleClonerSheet) {
                StyleDNAClonerSheet { samples in
                    let dna = await appState.cloneStyleDNA(fromSamples: samples)
                    showFeedback("✓ 文风 DNA 克隆完成：\(dna.clonedStyleSummary.prefix(24))…")
                }
            }
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
            .sheet(isPresented: $showNewContextCardSheet) {
                ContextCardEditorSheet(initial: nil) { created in
                    appState.upsertContextCard(created)
                    showFeedback("已添加背景知识卡「\(created.title)」")
                }
            }
            .sheet(item: $editingContextCard) { card in
                ContextCardEditorSheet(initial: card) { updated in
                    appState.upsertContextCard(updated)
                    showFeedback("已更新背景知识卡「\(updated.title)」")
                }
            }
        }
    }

    // MARK: - 1. 多渠道模型配置（支持一键拉取远端模型 + 自由手填任意模型 ID + 双模型路由）

    private var providerAndModelSection: some View {
        Section {
            if !appState.aiConfig.profiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.aiConfig.profiles) { prof in
                            let isCurrent = appState.aiConfig.activeProfileID == prof.id
                            HStack(spacing: 5) {
                                Button {
                                    appState.aiConfig.activateProfile(prof)
                                    showFeedback("已切换至渠道档案「\(prof.name)」")
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: prof.provider == .gemini ? "sparkles" : "server.rack")
                                            .font(.caption2)
                                        Text(prof.name)
                                            .font(.caption.bold())
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    appState.aiConfig.profiles.removeAll { $0.id == prof.id }
                                    if appState.aiConfig.activeProfileID == prof.id {
                                        appState.aiConfig.activeProfileID = nil
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .opacity(0.65)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isCurrent ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
                            .foregroundStyle(isCurrent ? Color.white : Color(Design.Palette.ink))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Picker("AI 协议类型", selection: $appState.aiConfig.provider) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    providerQuickPreset(
                        "Gemini 3.8 Flash",
                        isActive: appState.aiConfig.provider == .gemini && appState.aiConfig.geminiModel == GeminiModelOption.flash38.rawValue
                    ) {
                        appState.aiConfig.provider = .gemini
                        appState.aiConfig.geminiBaseURL = AIConfig.defaultGeminiBaseURL
                        appState.aiConfig.geminiModel = GeminiModelOption.flash38.rawValue
                    }
                    providerQuickPreset(
                        "Gemini 2.5 Pro",
                        isActive: appState.aiConfig.provider == .gemini && appState.aiConfig.geminiModel == GeminiModelOption.pro25.rawValue
                    ) {
                        appState.aiConfig.provider = .gemini
                        appState.aiConfig.geminiModel = GeminiModelOption.pro25.rawValue
                    }
                    providerQuickPreset(
                        "DeepSeek V3/R1",
                        isActive: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("deepseek.com")
                    ) {
                        appState.aiConfig.provider = .openAICompatible
                        appState.aiConfig.openAIBaseURL = "https://api.deepseek.com/v1"
                        appState.aiConfig.openAIModel = "deepseek-chat"
                        appState.aiConfig.deepModel = "deepseek-reasoner"
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
                        "OpenRouter",
                        isActive: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("openrouter.ai")
                    ) {
                        appState.aiConfig.provider = .openAICompatible
                        appState.aiConfig.openAIBaseURL = "https://openrouter.ai/api/v1"
                        appState.aiConfig.openAIModel = "google/gemini-2.5-flash"
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gemini 接口 Base URL（支持官方直连或自建反代）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(AIConfig.defaultGeminiBaseURL, text: $appState.aiConfig.geminiBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13.5, design: .monospaced))
                }

                apiKeyField(title: "Gemini API Key", placeholder: "AIza...", text: $appState.aiConfig.geminiAPIKey)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("主模型 ID（可手填或下方一键获取）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Menu("快捷选择") {
                            ForEach(GeminiModelOption.allCases) { opt in
                                Button(opt.displayName) {
                                    appState.aiConfig.geminiModel = opt.rawValue
                                }
                            }
                        }
                        .font(.caption.bold())
                    }
                    TextField("如 gemini-3.8-flash / gemini-2.5-pro", text: $appState.aiConfig.geminiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI 兼容接口 Base URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://api.deepseek.com/v1", text: $appState.aiConfig.openAIBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13.5, design: .monospaced))
                }

                apiKeyField(title: "API Key", placeholder: "sk-...（本地 Ollama 可留空）", text: $appState.aiConfig.openAIAPIKey)

                VStack(alignment: .leading, spacing: 4) {
                    Text("主模型 ID（支持任意手动输入或一键拉取）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("如 deepseek-chat / deepseek-reasoner / qwen3-235b", text: $appState.aiConfig.openAIModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                }
            }

            // 核心能力：一键获取远端可用模型列表 + 从已拉取列表挑选 + 保存为多渠道档案
            HStack(spacing: 10) {
                Button {
                    modelAssignTarget = .primary
                    Task { await triggerFetchModels(openSheetOnSuccess: true) }
                } label: {
                    HStack(spacing: 6) {
                        if appState.isFetchingAIModels {
                            ProgressView().scaleEffect(0.85)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        }
                        Text(appState.isFetchingAIModels ? "正在拉取模型…" : "获取可用模型")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(Color(Design.Palette.accent))
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(appState.isFetchingAIModels || !appState.aiConfig.isConfigured)

                if !appState.aiConfig.fetchedModels.isEmpty {
                    Button {
                        modelAssignTarget = .primary
                        showModelPicker = true
                    } label: {
                        Text("已拉取 \(appState.aiConfig.fetchedModels.count) 个")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(Color(Design.Palette.surface))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    newProfileName = appState.aiConfig.provider == .gemini ? "Gemini 通道" : "自定义通道"
                    showSaveProfileAlert = true
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.subheadline)
                        .frame(width: 38, height: 38)
                        .background(Color(Design.Palette.surface))
                        .foregroundStyle(Color(Design.Palette.accent))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保存为多渠道档案")
            }

            if let msg = fetchModelStatus {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(msg.hasPrefix("✓") ? Color(Design.Palette.success) : Color(Design.Palette.error))
            }

            // 快/深双模型路由配置（可折叠）
            DisclosureGroup("双模型智能路由（极速快模型 / 深度思考模型）", isExpanded: $showDualModelDisclosure) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("极速快模型（如 flash-lite，留空用主模型）", text: $appState.aiConfig.fastModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 13, design: .monospaced))
                        if !appState.aiConfig.fetchedModels.isEmpty {
                            Button("选") {
                                modelAssignTarget = .fast
                                showModelPicker = true
                            }
                            .font(.caption.bold())
                        }
                    }
                    HStack {
                        TextField("深度思考模型（如 deepseek-reasoner / pro）", text: $appState.aiConfig.deepModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 13, design: .monospaced))
                        if !appState.aiConfig.fetchedModels.isEmpty {
                            Button("选") {
                                modelAssignTarget = .deep
                                showModelPicker = true
                            }
                            .font(.caption.bold())
                        }
                    }
                    Text("实时边打边译自动走「极速快模型」降延迟；博弈军师、自动诊断与链式流水线自动走「深度思考模型」提质量。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .font(.subheadline)
        } header: {
            Text("模型渠道与动态拉取（支持多档案秒切与手动填模型）")
        } footer: {
            Text("支持从 Gemini /v1beta/models、OpenAI /models、Ollama /api/tags 动态拉取完整模型列表，也支持直接手填任意新发布或中转站私有模型 ID。")
        }
    }

    // MARK: - 2. 思考模式与推理参数（全协议自动适配）

    private var thinkingAndParamsSection: some View {
        Section {
            Picker("🧠 思考模式（深度推理档位）", selection: $appState.aiConfig.thinkingMode) {
                ForEach(AIThinkingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            if appState.aiConfig.thinkingMode == .customBudget {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("思考 Token 预算 (thinking_budget)")
                            .font(.subheadline)
                        Spacer()
                        Text("\(appState.aiConfig.thinkingBudget) tokens")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(appState.aiConfig.thinkingBudget) },
                            set: { appState.aiConfig.thinkingBudget = Int($0) }
                        ),
                        in: 256...16384,
                        step: 256
                    )
                }
            }

            Toggle("在面板中展示可折叠「思考过程」", isOn: $appState.aiConfig.showThinkingProcess)

            Picker("默认沟通关系场景", selection: $appState.aiConfig.activeScenePersona) {
                ForEach(AIScenePersona.allCases) { scene in
                    Text(scene.shortTitle).tag(scene)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Temperature（创造力）")
                    Spacer()
                    Text(String(format: "%.1f", appState.aiConfig.temperature))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $appState.aiConfig.temperature, in: 0.0...1.5, step: 0.1)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Top-P（核采样多样性）")
                    Spacer()
                    Text(String(format: "%.2f", appState.aiConfig.topP))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $appState.aiConfig.topP, in: 0.1...1.0, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("最大输出长度 (Max Tokens)")
                    Spacer()
                    Text("\(appState.aiConfig.maxOutputTokens)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(appState.aiConfig.maxOutputTokens) },
                        set: { appState.aiConfig.maxOutputTokens = Int($0) }
                    ),
                    in: 256...8192,
                    step: 256
                )
            }

            Picker("译 · 默认翻译目标语种", selection: $appState.settings.translateTargetLang) {
                ForEach(TranslateTargetLanguage.allCases) { lang in
                    Text(lang.rawValue).tag(lang.rawValue)
                }
            }

            Toggle("键盘内自动识别语境并置顶推荐提示词", isOn: $appState.aiConfig.smartContextRecommendEnabled)
            Toggle("测试连通成功后自动分析并生成提示词", isOn: $appState.aiConfig.autoAnalyzeOnConnect)
        } header: {
            Text("🧠 思考模式与推理参数（Gemini / DeepSeek-R1 / Qwen3 / OpenAI 全适配）")
        } footer: {
            Text("系统自动分离 <think> 思考链与正文输出：点击上屏时绝不会把思考过程误插入聊天框。")
        }
    }

    // MARK: - 3. 连通性诊断与 AI 实战试炼场 / 双模型 Arena PK

    private var playgroundAndConnectivitySection: some View {
        Section {
            HStack(spacing: 10) {
                Button {
                    runConnectivityTest()
                } label: {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView().scaleEffect(0.85)
                        } else {
                            Image(systemName: "bolt.horizontal.circle.fill")
                        }
                        Text(isTesting ? "正在测试…" : "一键测速连通")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color(Design.Palette.surface))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isTesting || !appState.aiConfig.isConfigured)

                Button {
                    showPlaygroundSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                        Text("试炼场 / 模型 PK")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color(Design.Palette.accent))
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let msg = testStatusMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(testSucceeded ? Color(Design.Palette.success) : Color(Design.Palette.error))
            }
        } header: {
            Text("连通测试与双模型对比试炼场")
        } footer: {
            Text("在「试炼场 / 模型 PK」中可直接实测思考过程折叠流式输出、首字延迟 TTFT，以及两个模型同题并排 PK。")
        }
    }

    // MARK: - 4. 个人文风 DNA 克隆、去 AI 腔黑名单 & 个人背景知识卡 (RAG-Lite)

    private var styleDNAAndContextCardsSection: some View {
        Section {
            // 10 秒文风 DNA 克隆
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("个人文风 DNA 指纹", systemImage: "waveform.path.ecg")
                        .font(.subheadline.bold())
                    Spacer()
                    Button {
                        showStyleClonerSheet = true
                    } label: {
                        Text(appState.aiConfig.styleDNA.clonedStyleSummary.isEmpty ? "10秒克隆文风" : "重新克隆")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(Design.Palette.accent))
                            .foregroundStyle(Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if appState.aiConfig.styleDNA.clonedStyleSummary.isEmpty {
                    Text("粘贴 3~5 句你平时发的真实微信或工作消息，灵犀会提取你的语气温度、标点习惯与句长节奏，让 AI 写出来的字像你本人。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(appState.aiConfig.styleDNA.clonedStyleSummary)
                        .font(.caption)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(Design.Palette.surface))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.vertical, 2)

            // 去 AI 腔黑名单
            Toggle("自动去除生硬「AI 腔」套话词", isOn: $appState.aiConfig.styleDNA.removeAIClicheEnabled)

            VStack(alignment: .leading, spacing: 8) {
                Text("禁用 AI 腔词条（点按删除，可新增）")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(appState.aiConfig.styleDNA.bannedAICliches, id: \.self) { word in
                            Button {
                                appState.aiConfig.styleDNA.bannedAICliches.removeAll { $0 == word }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(word)
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(Design.Palette.error).opacity(0.12))
                                .foregroundStyle(Color(Design.Palette.error))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("添加禁用词（如：综上所述 / 旨在）", text: $newBannedCliche)
                        .font(.caption)
                    Button("添加") {
                        let w = newBannedCliche.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !w.isEmpty && !appState.aiConfig.styleDNA.bannedAICliches.contains(w) {
                            appState.aiConfig.styleDNA.bannedAICliches.insert(w, at: 0)
                            newBannedCliche = ""
                        }
                    }
                    .font(.caption.bold())
                    .disabled(newBannedCliche.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            // 个人常用口癖/高频收尾
            VStack(alignment: .leading, spacing: 8) {
                Text("个人自然口癖（让回复更有本人味道）")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(appState.aiConfig.styleDNA.personalCatchphrases, id: \.self) { phrase in
                            Button {
                                appState.aiConfig.styleDNA.personalCatchphrases.removeAll { $0 == phrase }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(phrase)
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(Design.Palette.accentSoft))
                                .foregroundStyle(Color(Design.Palette.accent))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("添加口癖（如：收到啦～ / 没问题）", text: $newCatchphrase)
                        .font(.caption)
                    Button("添加") {
                        let w = newCatchphrase.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !w.isEmpty && !appState.aiConfig.styleDNA.personalCatchphrases.contains(w) {
                            appState.aiConfig.styleDNA.personalCatchphrases.insert(w, at: 0)
                            newCatchphrase = ""
                        }
                    }
                    .font(.caption.bold())
                    .disabled(newCatchphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if !appState.aiConfig.styleDNA.learnedDiffRules.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动从你的手动改写中学到的规则：")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(appState.aiConfig.styleDNA.learnedDiffRules, id: \.self) { rule in
                        Text("• \(rule)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("全局人设补充（可选）")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("例如：偏科技从业者，结论先行，不用感叹号", text: $appState.aiConfig.customPersonaPrompt, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.subheadline)
            }

            // 个人背景知识卡片 (RAG-Lite)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("个人背景知识卡 (\(appState.aiConfig.contextCards.filter(\.isEnabled).count) 启用)", systemImage: "rectangle.stack.person.crop")
                        .font(.subheadline.bold())
                    Spacer()
                    Button {
                        showNewContextCardSheet = true
                    } label: {
                        Label("新增卡片", systemImage: "plus.circle.fill")
                            .font(.caption.bold())
                    }
                }

                if appState.aiConfig.contextCards.isEmpty {
                    Text("可存入你的职业身份、公司业务、常见回复口径，键盘 AI 调用时自动挂载，不用每次重复交代背景。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.aiConfig.contextCards) { card in
                        HStack(spacing: 8) {
                            Button {
                                editingContextCard = card
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(card.title).font(.subheadline.bold()).foregroundStyle(.primary)
                                        Text(card.sceneTag).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Text(card.content).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { card.isEnabled },
                                set: { val in
                                    var updated = card
                                    updated.isEnabled = val
                                    appState.upsertContextCard(updated)
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            }
        } header: {
            Text("🧬 个人文风 DNA · 去 AI 腔 · 知识背景卡（端到端云同步）")
        }
    }

    // MARK: - 5. 接入 AI 自动分析与专属方案生成

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
                            .foregroundStyle(Color(Design.Palette.accent))
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
                            .background(isApplied ? Color(Design.Palette.surface) : Color(Design.Palette.accent))
                            .foregroundStyle(isApplied ? Color.secondary : Color.white)
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
                }

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
                            .foregroundStyle(Color(Design.Palette.accent))
                            .buttonStyle(.plain)
                        }

                        ForEach(report.suggestedPrompts) { tpl in
                            let alreadyAdded = appState.aiConfig.customPrompts.contains(where: { $0.title == tpl.title })
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: tpl.icon)
                                    .font(.subheadline)
                                    .foregroundStyle(Color(Design.Palette.accent))
                                    .frame(width: 24, height: 24)
                                    .background(Color(Design.Palette.surface))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(tpl.title).font(.subheadline.bold())
                                        Text(tpl.category).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Text(tpl.instruction).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Button(alreadyAdded ? "已加入" : "加入") {
                                    let count = appState.importSuggestedPrompts([tpl])
                                    showFeedback(count > 0 ? "已将「\(tpl.title)」加入键盘 AI 技能栏" : "「\(tpl.title)」已在键盘栏中")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(alreadyAdded ? Color(Design.Palette.surface) : Color(Design.Palette.accent))
                                .foregroundStyle(alreadyAdded ? Color.secondary : Color.white)
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                                .disabled(alreadyAdded)
                            }
                        }
                    }
                }

                if !report.suggestedPhrases.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("AI 推荐高频快捷短语", systemImage: "text.quote")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("一键导入短语库") {
                                let count = appState.importSuggestedPhrases(report.suggestedPhrases)
                                showFeedback(count > 0 ? "已导入 \(count) 条快捷短语" : "推荐短语已在你的短语库中")
                            }
                            .font(.caption.bold())
                            .foregroundStyle(Color(Design.Palette.accent))
                            .buttonStyle(.plain)
                        }

                        ForEach(report.suggestedPhrases) { phrase in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(phrase.title).font(.caption.bold())
                                Text(phrase.content).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !report.suggestedFuzzyKeys.isEmpty {
                    Button {
                        let applied = appState.applySuggestedFuzzyKeys(report.suggestedFuzzyKeys)
                        let names = report.suggestedFuzzyKeys.map(AIAutoInsightService.fuzzyDisplayName(for:)).joined(separator: "、")
                        showFeedback(applied > 0 ? "已一键开启模糊音：\(names)" : "推荐模糊音均已开启")
                    } label: {
                        Label(
                            "一键开启高频混淆模糊音（\(report.suggestedFuzzyKeys.map(AIAutoInsightService.fuzzyDisplayName(for:)).joined(separator: " / "))）",
                            systemImage: "waveform.path.ecg"
                        )
                        .font(.subheadline.bold())
                    }
                }
            }
        } header: {
            Text("🧠 AI 自动分析与专属提示词生成")
        }
    }

    // MARK: - 6. 我的键盘自定义提示词库（含链式流水线）

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
                                .foregroundStyle(Color(Design.Palette.accent))
                                .frame(width: 24, height: 24)
                                .background(Color(Design.Palette.surface))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(tpl.title).font(.subheadline.bold()).foregroundStyle(.primary)
                                    if tpl.useDeepModel {
                                        Text("深度").font(.caption2.bold())
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color(Design.Palette.accentSoft))
                                            .foregroundStyle(Color(Design.Palette.accent))
                                            .clipShape(Capsule())
                                    }
                                    if tpl.isAIGenerated {
                                        Text("AI定制").font(.caption2.bold())
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color(Design.Palette.surface))
                                            .clipShape(Capsule())
                                    }
                                    Text(tpl.category).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(tpl.instruction).font(.caption).foregroundStyle(.secondary).lineLimit(2)
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
                            .foregroundStyle(tpl.isPinned ? Color(Design.Palette.accent) : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { appState.aiConfig.customPrompts[$0].id }
                for id in ids { appState.deleteCustomPrompt(id: id) }
            }

            Button {
                showNewPromptSheet = true
            } label: {
                Label("新建专属键盘提示词 / 链式流水线", systemImage: "plus.circle.fill")
                    .font(.subheadline.bold())
            }
        } header: {
            Text("✨ 我的键盘自定义提示词库（实时同步至键盘 AI 栏）")
        }
    }

    // MARK: - 7. AI 调用耗时与用量账本

    private var usageLedgerSection: some View {
        let entries = appState.aiUsageLedger
        let avgTTFT = entries.isEmpty ? 0 : entries.reduce(0) { $0 + $1.ttftMs } / entries.count
        let totalOut = entries.reduce(0) { $0 + $1.outputChars }
        return Section {
            LabeledContent("累计 AI 调用", value: "\(entries.count) 次")
            LabeledContent("平均首字响应 (TTFT)", value: avgTTFT > 0 ? "\(avgTTFT) ms" : "--")
            LabeledContent("累计生成字数", value: "\(totalOut) 字（约省 \(max(0, totalOut / 38)) 分钟）")
            if let latest = entries.first {
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近调用：\(latest.model) · 思考「\(latest.thinkingMode)」")
                        .font(.caption.bold())
                    Text("首字 \(latest.ttftMs)ms · 总计 \(latest.totalMs)ms · 输出 \(latest.outputChars) 字（思考 \(latest.thoughtChars) 字）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if !entries.isEmpty {
                Button("清空本地用量账本", role: .destructive) {
                    appState.clearAIUsageLedger()
                }
            }
        } header: {
            Text("📊 AI 速度与消耗账本（仅记录数值元数据）")
        }
    }

    // MARK: - 8. 键盘内置技能一览

    private var builtInSkillsSection: some View {
        Section("键盘内置基础 AI 技能（含博弈军师 & 框选即改）") {
            ForEach(AIPresetAction.allCases) { action in
                Label(action.title, systemImage: action.icon)
            }
        }
    }

    // MARK: - Helpers

    private func currentModelFor(target: ModelAssignTarget) -> String {
        switch target {
        case .primary: return appState.aiConfig.activeModelName
        case .fast: return appState.aiConfig.fastModel
        case .deep: return appState.aiConfig.deepModel
        }
    }

    private func assignModel(_ id: String, to target: ModelAssignTarget) {
        switch target {
        case .primary:
            if appState.aiConfig.provider == .gemini {
                appState.aiConfig.geminiModel = id
            } else {
                appState.aiConfig.openAIModel = id
            }
        case .fast:
            appState.aiConfig.fastModel = id
        case .deep:
            appState.aiConfig.deepModel = id
        }
    }

    private func providerQuickPreset(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isActive ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
                .foregroundStyle(isActive ? Color.white : Color(Design.Palette.ink))
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
                .foregroundStyle(Color(Design.Palette.accent))
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
        withAnimation { actionFeedback = message }
    }

    private func triggerFetchModels(openSheetOnSuccess: Bool) async {
        fetchModelStatus = nil
        do {
            let models = try await appState.fetchAvailableAIModels()
            fetchModelStatus = "✓ 已拉取 \(models.count) 个远端可用模型，可点按挑选或继续手动输入"
            if openSheetOnSuccess {
                showModelPicker = true
            }
        } catch {
            fetchModelStatus = "拉取失败：\(error.localizedDescription)（您仍可直接手动输入模型 ID）"
        }
    }

    private func triggerAutoAnalysis() {
        actionFeedback = nil
        Task {
            let report = await appState.runAIAutoAnalysis()
            await MainActor.run {
                showFeedback(report.isFromLLM
                             ? "AI 深度分析完成！已为你定制 \(report.suggestedPrompts.count) 条提示词"
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
                let start = Date()
                let reply = try await client.testConnection(config: snapshot)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                await MainActor.run {
                    isTesting = false
                    testSucceeded = true
                    testStatusMessage = "✓ 连接成功 (\(ms)ms)：\(reply)"
                    appState.refreshAll()
                }
                if snapshot.autoAnalyzeOnConnect {
                    let report = await appState.runAIAutoAnalysis()
                    await MainActor.run {
                        showFeedback("连通后已自动分析：生成「\(report.personaTitle)」方案")
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

// MARK: - 远端模型搜索选择 Sheet

private struct AIModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let models: [AIModelInfo]
    let currentModel: String
    let isFetching: Bool
    let onRefresh: () async -> Void
    let onSelect: (String) -> Void

    @State private var query = ""
    @State private var manualModelID = ""
    @State private var thinkingOnly = false

    private var filtered: [AIModelInfo] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return models.filter { m in
            if thinkingOnly && !m.supportsThinking { return false }
            if q.isEmpty { return true }
            return m.id.lowercased().contains(q) || m.displayName.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("直接手动输入任意模型 ID") {
                    HStack {
                        TextField("输入自定义模型名称…", text: $manualModelID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 14, design: .monospaced))
                        Button("使用") {
                            let clean = manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !clean.isEmpty {
                                onSelect(clean)
                                dismiss()
                            }
                        }
                        .font(.caption.bold())
                        .disabled(manualModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    TextField("搜索模型 ID 或名称…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("仅显示支持深度思考 (🧠) 的推理模型", isOn: $thinkingOnly)
                }

                Section("远端可用模型 (\(filtered.count))") {
                    if filtered.isEmpty {
                        Text("未匹配到模型，可点右上角刷新或在上方直接手动输入。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { item in
                            Button {
                                onSelect(item.id)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(item.id)
                                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.primary)
                                            if item.supportsThinking {
                                                Text("🧠 思考")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color(Design.Palette.accentSoft))
                                                    .foregroundStyle(Color(Design.Palette.accent))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        HStack(spacing: 8) {
                                            if item.displayName != item.id {
                                                Text(item.displayName).font(.caption2).foregroundStyle(.secondary)
                                            }
                                            if let ctx = item.contextLength, ctx > 0 {
                                                Text("上下文 \(ctx >= 1000 ? "\(ctx / 1000)K" : "\(ctx)")")
                                                    .font(.caption2.monospacedDigit())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    Spacer()
                                    if item.id == currentModel {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color(Design.Palette.accent))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await onRefresh() }
                    } label: {
                        if isFetching {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isFetching)
                }
            }
        }
    }
}

// MARK: - Live AI 试炼场 & 双模型同题 Arena PK Sheet

private struct AIPlaygroundAndArenaSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var tab = 0 // 0=单模型思考试炼场, 1=双模型 Arena PK
    @State private var inputText = "领导刚发消息说这周六临时加班赶一下方案，但我家里已经约好聚餐了，帮我高情商回复一下。"
    @State private var thoughtText = ""
    @State private var answerText = ""
    @State private var showThought = false
    @State private var isRunning = false
    @State private var statusMetrics = ""

    // Arena PK
    @State private var modelA = ""
    @State private var modelB = ""
    @State private var outA = ""
    @State private var outB = ""
    @State private var metricsA = ""
    @State private var metricsB = ""

    private let client = AIClient(timeout: 45)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("试炼模式", selection: $tab) {
                        Text("思考模式试炼场").tag(0)
                        Text("双模型 Arena PK").tag(1)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("测试输入内容")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextEditor(text: $inputText)
                            .frame(minHeight: 88)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if tab == 0 {
                        singlePlaygroundBody
                    } else {
                        arenaPKBody
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI 试炼场与模型 PK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                modelA = appState.aiConfig.activeModelName
                modelB = appState.aiConfig.deepModel.isEmpty
                    ? (appState.aiConfig.fetchedModels.first(where: { $0.id != modelA })?.id ?? modelA)
                    : appState.aiConfig.deepModel
            }
        }
    }

    private var singlePlaygroundBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("当前模型：\(appState.aiConfig.activeModelName)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("思考：\(appState.aiConfig.thinkingMode.displayName)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(Design.Palette.accentSoft))
                    .foregroundStyle(Color(Design.Palette.accent))
                    .clipShape(Capsule())
            }

            Button {
                Task { await runSingleTest() }
            } label: {
                HStack {
                    if isRunning { ProgressView().tint(.white) }
                    Text(isRunning ? "流式推理中…" : "立即运行测试（实时查看思考链与延迟）")
                        .font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(Design.Palette.accent))
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRunning || !appState.aiConfig.isConfigured)

            if !statusMetrics.isEmpty {
                Text(statusMetrics)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !thoughtText.isEmpty {
                DisclosureGroup("💭 思考推理过程（\(thoughtText.count) 字 · 上屏时自动剥离）", isExpanded: $showThought) {
                    Text(thoughtText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !answerText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("✨ 最终可上屏正文")
                            .font(.caption.bold())
                            .foregroundStyle(Color(Design.Palette.accent))
                        Spacer()
                        Button("复制") {
                            UIPasteboard.general.string = answerText
                        }
                        .font(.caption.bold())
                    }
                    Text(answerText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var arenaPKBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("模型 A", text: $modelA)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("VS").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("模型 B", text: $modelB)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                Task { await runArenaPK() }
            } label: {
                HStack {
                    if isRunning { ProgressView().tint(.white) }
                    Text(isRunning ? "双模型并行 PK 中…" : "🔥 同题并排 PK 对比")
                        .font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(Design.Palette.accent))
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRunning || !appState.aiConfig.isConfigured)

            arenaResultCard(label: "模型 A：\(modelA)", metrics: metricsA, output: outA) {
                if appState.aiConfig.provider == .gemini { appState.aiConfig.geminiModel = modelA }
                else { appState.aiConfig.openAIModel = modelA }
            }
            arenaResultCard(label: "模型 B：\(modelB)", metrics: metricsB, output: outB) {
                if appState.aiConfig.provider == .gemini { appState.aiConfig.geminiModel = modelB }
                else { appState.aiConfig.openAIModel = modelB }
            }
        }
    }

    private func arenaResultCard(label: String, metrics: String, output: String, onChoose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.caption.bold())
                Spacer()
                if !metrics.isEmpty {
                    Text(metrics).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                if !output.isEmpty {
                    Button("选用为主模型", action: onChoose)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(Design.Palette.accentSoft))
                        .foregroundStyle(Color(Design.Palette.accent))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                }
            }
            Text(output.isEmpty ? "等待运行…" : output)
                .font(.subheadline)
                .foregroundStyle(output.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func runSingleTest() async {
        isRunning = true
        thoughtText = ""
        answerText = ""
        statusMetrics = "正在连接模型…"
        let start = Date()
        var firstTokenMs: Int?
        defer { isRunning = false }
        do {
            for try await chunk in client.streamEvents(
                prompt: inputText,
                systemInstruction: AIPresetAction.eqReply.systemPrompt,
                config: appState.aiConfig,
                featureTag: "playground"
            ) {
                if firstTokenMs == nil {
                    firstTokenMs = Int(Date().timeIntervalSince(start) * 1000)
                }
                switch chunk {
                case .thought(let t): thoughtText += t
                case .answer(let a): answerText += a
                }
            }
            let totalMs = Int(Date().timeIntervalSince(start) * 1000)
            statusMetrics = "✓ 完成 · 首字延迟 \(firstTokenMs ?? totalMs)ms · 总耗时 \(totalMs)ms · 正文 \(answerText.count) 字"
            appState.refreshAll()
        } catch {
            statusMetrics = "失败：\(error.localizedDescription)"
        }
    }

    private func runArenaPK() async {
        isRunning = true
        outA = ""; outB = ""; metricsA = "推理中…"; metricsB = "推理中…"
        defer { isRunning = false }
        let baseCfg = appState.aiConfig
        var cfgA = baseCfg
        var cfgB = baseCfg
        if baseCfg.provider == .gemini {
            cfgA.geminiModel = modelA; cfgB.geminiModel = modelB
        } else {
            cfgA.openAIModel = modelA; cfgB.openAIModel = modelB
        }
        async let taskA: Void = {
            let s = Date()
            do {
                var acc = ""
                for try await c in client.streamText(prompt: inputText, systemInstruction: AIPresetAction.eqReply.systemPrompt, config: cfgA, featureTag: "arena_a") {
                    acc += c
                    let snap = acc
                    await MainActor.run { outA = snap }
                }
                let ms = Int(Date().timeIntervalSince(s) * 1000)
                await MainActor.run { metricsA = "\(ms)ms · \(acc.count)字" }
            } catch {
                await MainActor.run { metricsA = "失败"; outA = error.localizedDescription }
            }
        }()
        async let taskB: Void = {
            let s = Date()
            do {
                var acc = ""
                for try await c in client.streamText(prompt: inputText, systemInstruction: AIPresetAction.eqReply.systemPrompt, config: cfgB, featureTag: "arena_b") {
                    acc += c
                    let snap = acc
                    await MainActor.run { outB = snap }
                }
                let ms = Int(Date().timeIntervalSince(s) * 1000)
                await MainActor.run { metricsB = "\(ms)ms · \(acc.count)字" }
            } catch {
                await MainActor.run { metricsB = "失败"; outB = error.localizedDescription }
            }
        }()
        _ = await (taskA, taskB)
        appState.refreshAll()
    }
}

// MARK: - 10 秒文风 DNA 克隆弹窗

private struct StyleDNAClonerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onClone: (String) async -> Void

    @State private var samples = ""
    @State private var isCloning = false

    var body: some View {
        NavigationStack {
            Form {
                Section("粘贴 3~5 条你平时发的真实聊天或工作消息") {
                    TextEditor(text: $samples)
                        .frame(minHeight: 160)
                    Button("填入示例看看效果") {
                        samples = "收到啦，我下午开完会马上看一下，有进展第一时间同步你～\n哈哈这事不急，你先忙手头的，咱们明天碰一下就行。\n刚核对完了，整体没啥大问题，有两处小细节我标在文档里了。"
                    }
                    .font(.caption.bold())
                }
                Section {
                    Button {
                        isCloning = true
                        Task {
                            await onClone(samples)
                            isCloning = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isCloning { ProgressView().padding(.trailing, 6) }
                            Text(isCloning ? "正在提取你的语言基因…" : "✨ 立即克隆我的文风 DNA")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(isCloning || samples.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("10 秒文风 DNA 克隆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 个人背景知识卡编辑弹窗

private struct ContextCardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: PersonalContextCard?
    let onSave: (PersonalContextCard) -> Void

    @State private var title: String
    @State private var sceneTag: String
    @State private var content: String
    @State private var isEnabled: Bool

    init(initial: PersonalContextCard?, onSave: @escaping (PersonalContextCard) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _title = State(initialValue: initial?.title ?? "")
        _sceneTag = State(initialValue: initial?.sceneTag ?? "职场")
        _content = State(initialValue: initial?.content ?? "")
        _isEnabled = State(initialValue: initial?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("卡片标题（如：我的岗位与汇报口径）", text: $title)
                TextField("场景标签（如：职场 / 销售 / 个人介绍）", text: $sceneTag)
                Toggle("调用 AI 时自动挂载此背景", isOn: $isEnabled)
                Section("背景知识正文") {
                    TextField("例如：我是一名 iOS 架构师，负责灵犀输入法项目，向研发总监汇报时偏好用「进展/风险/下一步」三段式。", text: $content, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle(initial == nil ? "新增背景知识卡" : "编辑背景知识卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let card = PersonalContextCard(
                            id: initial?.id ?? UUID().uuidString,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                            sceneTag: sceneTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "通用" : sceneTag,
                            isEnabled: isEnabled
                        )
                        onSave(card)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    @State private var useDeepModel: Bool

    private let categories = ["效率沟通", "职场商务", "链式流水线", "日常社交", "学习创作", "AI 自动定制"]
    private let icons = [
        "sparkles", "briefcase.fill", "bolt.fill", "doc.text.fill",
        "bubble.left.and.text.bubble.right.fill", "globe", "checklist",
        "hand.raised.fill", "arrow.triangle.branch", "lightbulb.fill"
    ]

    init(initial: CustomAIPromptTemplate?, onSave: @escaping (CustomAIPromptTemplate) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _title = State(initialValue: initial?.title ?? "")
        _category = State(initialValue: initial?.category ?? "效率沟通")
        _icon = State(initialValue: initial?.icon ?? "sparkles")
        _instruction = State(initialValue: initial?.instruction ?? "")
        _isPinned = State(initialValue: initial?.isPinned ?? true)
        _useDeepModel = State(initialValue: initial?.useDeepModel ?? false)
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
                    Toggle("优先路由至「深度思考模型」执行", isOn: $useDeepModel)
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
                                    .background(icon == sym ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
                                    .foregroundStyle(icon == sym ? Color.white : Color(Design.Palette.ink))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("AI 执行提示词（支持多步链式指令）") {
                    TextField(
                        "例如：第1步去掉口语词并提炼为3条进展；第2步附上英文同步版本。",
                        text: $instruction,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                }
            }
            .navigationTitle(initial == nil ? "新建键盘提示词" : "编辑键盘提示词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
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
                            isPinned: isPinned,
                            useDeepModel: useDeepModel
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
