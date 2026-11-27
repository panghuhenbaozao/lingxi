import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// AI 智脑主屏（极简编辑风 4 区块布局）：
/// ① 状态与对话 ② AI 全权托管与 Obsidian 自学习 ③ 模型连接 ④ 核心功能（零冗余噱头，一屏看清）
struct AISettingsView: View {
    private enum StudioDestination: Hashable {
        case autopilotHub
        case obsidianVault
        case promptsWorkshop
        case styleAndContext
        case privacyShield
        case historyAndUsage
        case translationStudio
        case pipelineStudio
        case writingStudio
        case offlineLinter
        case parameterizedRunner
    }

    private enum ActiveSheet: Identifiable {
        case modelPicker(AIModelAssignTarget)
        case workbench(tab: Int, draft: String?)
        case benchmark
        case profileManager
        case customHeaders

        var id: String {
            switch self {
            case .modelPicker(let t): return "modelPicker_\(t.title)"
            case .workbench(let tab, _): return "workbench_\(tab)"
            case .benchmark: return "benchmark"
            case .profileManager: return "profileManager"
            case .customHeaders: return "customHeaders"
            }
        }
    }

    @EnvironmentObject private var appState: AppState

    @State private var revealKey = false
    @State private var isTesting = false
    @State private var toastMessage: String?
    @State private var toastIsError = false
    @State private var lastLatencyMs: Int?
    @State private var showAdvancedParams = false
    @State private var showMoreTools = false

    @State private var activeSheet: ActiveSheet?
    @State private var pushedDestination: StudioDestination?
    @State private var showSaveProfileAlert = false
    @State private var saveProfileAsNew = true
    @State private var newProfileName = ""
    @State private var brainExportDoc: PromptsJSONDocument?
    @State private var showBrainExporter = false
    @State private var showBrainImporter = false
    @State private var isSyncingBridge = false
    @State private var modelFetchError: String?
    @State private var cachedHistoryCount = 0

    private let client = AIClient()

    private var hasFreshModelsForCurrentSource: Bool {
        !appState.aiConfig.fetchedModels.isEmpty
            && (appState.aiConfig.fetchedModelsSourceKey.isEmpty
                || appState.aiConfig.fetchedModelsSourceKey == appState.aiConfig.currentModelsSourceKey)
    }

    private var keyboardNeedsPermission: Bool {
        !appState.isKeyboardEnabled || !appState.isKeyboardFullAccessConfirmed
    }

    private var activeProfileName: String? {
        guard let aid = appState.aiConfig.activeProfileID else { return nil }
        return appState.aiConfig.profiles.first(where: { $0.id == aid })?.name
    }

    private struct ProviderPreset: Identifiable {
        let id: String
        let title: String
        let provider: AIProvider
        let baseURL: String
        let model: String
        var fastModel: String? = nil
        var deepModel: String? = nil
        var visionModel: String? = nil
        var urlKeyword: String? = nil
    }

    private static let primaryPresets: [ProviderPreset] = [
        ProviderPreset(id: "deepseek", title: "DeepSeek", provider: .openAICompatible, baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat", fastModel: "deepseek-chat", deepModel: "deepseek-reasoner", urlKeyword: "deepseek.com"),
        ProviderPreset(id: "gemini", title: "Gemini", provider: .gemini, baseURL: AIConfig.defaultGeminiBaseURL, model: GeminiModelOption.flash25.rawValue, deepModel: GeminiModelOption.pro25.rawValue, visionModel: GeminiModelOption.flash25.rawValue),
        ProviderPreset(id: "openai", title: "OpenAI", provider: .openAICompatible, baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", fastModel: "gpt-4o-mini", deepModel: "o3-mini", visionModel: "gpt-4o", urlKeyword: "api.openai.com"),
        ProviderPreset(id: "claude", title: "Claude", provider: .anthropic, baseURL: AIConfig.defaultAnthropicBaseURL, model: AIConfig.defaultAnthropicModel, fastModel: "claude-3-5-haiku-20241022", deepModel: "claude-opus-4-20250514", visionModel: AIConfig.defaultAnthropicModel),
        ProviderPreset(id: "qwen", title: "千问", provider: .openAICompatible, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", fastModel: "qwen-turbo", deepModel: "qwq-plus", visionModel: "qwen-vl-max", urlKeyword: "dashscope"),
    ]

    private static let extraPresets: [ProviderPreset] = [
        ProviderPreset(id: "siliconflow", title: "SiliconFlow", provider: .openAICompatible, baseURL: "https://api.siliconflow.cn/v1", model: "deepseek-ai/DeepSeek-V3", deepModel: "deepseek-ai/DeepSeek-R1", visionModel: "Qwen/Qwen2.5-VL-72B-Instruct", urlKeyword: "siliconflow"),
        ProviderPreset(id: "openrouter", title: "OpenRouter", provider: .openAICompatible, baseURL: "https://openrouter.ai/api/v1", model: "google/gemini-2.5-flash", deepModel: "deepseek/deepseek-r1", visionModel: "google/gemini-2.5-flash", urlKeyword: "openrouter"),
        ProviderPreset(id: "zhipu", title: "智谱 GLM", provider: .openAICompatible, baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash", deepModel: "glm-z1-flash", visionModel: "glm-4v-flash", urlKeyword: "bigmodel.cn"),
        ProviderPreset(id: "doubao", title: "火山方舟", provider: .openAICompatible, baseURL: "https://ark.cn-beijing.volces.com/api/v3", model: "doubao-1-5-pro-32k-250115", visionModel: "doubao-1-5-vision-pro-32k-250115", urlKeyword: "volces.com"),
        ProviderPreset(id: "groq", title: "Groq", provider: .openAICompatible, baseURL: "https://api.groq.com/openai/v1", model: "llama-3.3-70b-versatile", fastModel: "llama-3.1-8b-instant", urlKeyword: "groq.com"),
        ProviderPreset(id: "ollama", title: "Ollama 本地", provider: .openAICompatible, baseURL: "http://127.0.0.1:11434/v1", model: "qwen2.5:7b", urlKeyword: "11434"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroStatusCard
                    obsidianAutopilotBlock
                    connectionBlock
                    coreCapabilitiesBlock
                    moreToolsBlock
                }
                .lxReadableWidth()
                .padding(.horizontal, Design.Spacing.md)
                .padding(.top, Design.Spacing.xs)
                .padding(.bottom, Design.Spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(
                isPresented: Binding(
                    get: { pushedDestination != nil },
                    set: { if !$0 { pushedDestination = nil } }
                )
            ) {
                destinationView(for: pushedDestination)
            }
            .onAppear {
                cachedHistoryCount = AIRecentHistoryStore.load().count
                appState.refreshCognitiveStats()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            activeSheet = .benchmark
                        } label: {
                            Image(systemName: "speedometer")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(Design.Palette.ink))
                        }
                        .accessibilityLabel("全路由测速")

                        Button {
                            appState.showPermissionsCenter = true
                        } label: {
                            Image(systemName: appState.isKeyboardFullAccessConfirmed ? "checkmark.shield" : "exclamationmark.shield.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(appState.isKeyboardFullAccessConfirmed ? Color(Design.Palette.ink) : Color(Design.Palette.warning))
                        }
                        .accessibilityLabel("权限")
                    }
                }
            }
            .lxToast($toastMessage, isError: toastIsError)
            .alert(saveProfileAsNew ? "存为新档案" : "更新当前档案", isPresented: $showSaveProfileAlert) {
                TextField("档案名称", text: $newProfileName)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    let chosenName = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.aiConfig.saveCurrentAsProfile(name: chosenName, createNew: saveProfileAsNew)
                    showToast("已保存档案")
                    newProfileName = ""
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .modelPicker(let target):
                    AIModelPickerSheet(
                        title: target.title,
                        models: hasFreshModelsForCurrentSource ? appState.aiConfig.fetchedModels : [],
                        currentModel: currentModelFor(target: target),
                        provider: appState.aiConfig.provider,
                        isFetching: appState.isFetchingAIModels,
                        fetchError: modelFetchError,
                        onRefresh: { await triggerFetchModels(openSheetOnSuccess: false, target: target) },
                        onSelect: { chosenID in
                            assignModel(chosenID, to: target)
                            showToast("已选定 \(chosenID)")
                        }
                    )
                case .workbench(let tab, let draft):
                    AIWorkbenchSheet(initialTab: tab, initialDraft: draft)
                        .environmentObject(appState)
                case .benchmark:
                    AIRouteBenchmarkSheet()
                        .environmentObject(appState)
                case .profileManager:
                    AIProfileManagerSheet { msg in showToast(msg) }
                        .environmentObject(appState)
                case .customHeaders:
                    AICustomHeadersSheet { msg in showToast(msg) }
                        .environmentObject(appState)
                }
            }
        }
    }

    @ViewBuilder
    private func destinationView(for dest: StudioDestination?) -> some View {
        switch dest {
        case .autopilotHub:
            AIAutopilotHubView()
        case .obsidianVault:
            ObsidianVaultGraphView()
        case .promptsWorkshop:
            AIPromptsWorkshopView()
        case .styleAndContext:
            AIStyleAndContextView()
        case .privacyShield:
            AIPrivacyShieldView()
        case .historyAndUsage:
            AIHistoryAndUsageView { draft in activeSheet = .workbench(tab: 0, draft: draft) }
        case .translationStudio:
            AITranslationStudioView()
        case .pipelineStudio:
            AIPipelineStudioView { draft in activeSheet = .workbench(tab: 0, draft: draft) }
        case .writingStudio:
            AIWritingStudioView { draft in activeSheet = .workbench(tab: 0, draft: draft) }
        case .offlineLinter:
            AIOfflineLinterView { draft in activeSheet = .workbench(tab: 0, draft: draft) }
        case .parameterizedRunner:
            AIParameterizedRunnerView { draft in activeSheet = .workbench(tab: 0, draft: draft) }
        case .none:
            EmptyView()
        }
    }

    // MARK: - 1. 顶部状态卡（极简、清晰、双按钮）

    private var heroStatusCard: some View {
        let cfg = appState.aiConfig
        let ready = cfg.isConfigured
        return LXCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Circle()
                        .fill(ready ? Color(Design.Palette.success) : Color(Design.Palette.warning))
                        .frame(width: 9, height: 9)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ready ? (cfg.activeModelName.isEmpty ? "未设模型" : cfg.activeModelName) : "待配置 API Key")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .lineLimit(1)
                        Text(heroMetaLine)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if let ms = lastLatencyMs {
                        Text("\(ms) ms")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color(Design.Palette.success))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color(Design.Palette.success).opacity(0.11), in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        runConnectivityTest()
                    } label: {
                        HStack(spacing: 5) {
                            if isTesting {
                                ProgressView().controlSize(.small)
                                Text("测速中")
                            } else {
                                Image(systemName: "bolt.horizontal")
                                Text("测速")
                            }
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.ink)))
                    .disabled(isTesting || !ready)

                    Button {
                        activeSheet = .workbench(tab: 0, draft: nil)
                    } label: {
                        Label("AI 对话", systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true, tint: Color(Design.Palette.accent)))
                }

                setupBanner
            }
        }
    }

    private var heroMetaLine: String {
        var parts = [appState.aiConfig.provider.shortName]
        if let p = activeProfileName { parts.append(p) }
        if appState.aiConfig.privacyShieldEnabled { parts.append("隐私脱敏开") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 2. Obsidian 自学习与 AI 全权托管主卡

    private var obsidianAutopilotBlock: some View {
        let stats = appState.cognitiveStats
        let mode = appState.settings.aiAutopilotMode
        let busy = appState.isRunningObsidianLearn || appState.isRunningAutopilot

        return VStack(alignment: .leading, spacing: 8) {
            LXSectionLabel("自学习与托管")

            LXGroupCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text("打字托管")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Spacer()
                        Picker("托管模式", selection: $appState.settings.aiAutopilotMode) {
                            ForEach(AIAutopilotMode.allCases) { m in
                                Text(m.shortBadge).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 186)
                    }

                    // 极简 3 数指标条
                    HStack(spacing: 0) {
                        miniMetric(value: "\(stats.vaultNoteCount)", label: "记忆笔记")
                        metricDivider
                        miniMetric(value: "\(stats.vaultLinkCount)", label: "双链关联")
                        metricDivider
                        miniMetric(value: "\(stats.activeDecisionCount)", label: "托管生效")
                    }
                    .padding(.vertical, 10)
                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))

                    if !stats.personaDigest.isEmpty {
                        Text(stats.personaDigest)
                            .font(.footnote)
                            .foregroundStyle(Color(Design.Palette.slate))
                            .lineLimit(2)
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                let res = await appState.runObsidianAPISelfLearning()
                                showToast(res.summary)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if busy {
                                    ProgressView().controlSize(.small).tint(Color.white)
                                    Text("学习中…")
                                } else {
                                    Image(systemName: "sparkles")
                                    Text("API 自学习")
                                }
                            }
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true, tint: Color(Design.Palette.accent)))
                        .disabled(busy || mode == .off)

                        Button {
                            pushedDestination = .obsidianVault
                        } label: {
                            Label("双链图谱", systemImage: "circle.hexagongrid")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.ink)))
                    }
                }
                .padding(16)

                Divider().padding(.leading, 16)

                Button {
                    pushedDestination = .autopilotHub
                } label: {
                    LXCleanRow(
                        icon: "externaldrive",
                        title: "数据库与托管记录",
                        value: stats.formattedSize
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func miniMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(Design.Palette.ink))
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color(Design.Palette.stone))
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color(Design.Palette.hairline))
            .frame(width: 0.5, height: 24)
    }

    // MARK: - 3. 模型连接（清爽不拥挤）

    private var connectionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            LXSectionLabel("模型连接")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.primaryPresets) { preset in
                        providerPill(preset)
                    }
                    Menu {
                        ForEach(Self.extraPresets) { preset in
                            Button(preset.title) {
                                applyQuickProviderPreset(preset)
                                showToast("已切至 \(preset.title)")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("更多")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .foregroundStyle(Color(Design.Palette.slate))
                        .background(Color(Design.Palette.canvas), in: Capsule())
                        .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.6))
                    }
                }
                .padding(.vertical, 2)
            }

            LXGroupCard {
                VStack(spacing: 0) {
                    Picker("协议", selection: Binding(
                        get: { appState.aiConfig.provider },
                        set: { newProvider in
                            if appState.aiConfig.provider != newProvider {
                                appState.aiConfig.provider = newProvider
                                appState.aiConfig.activeProfileID = nil
                                lastLatencyMs = nil
                            }
                        }
                    )) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.shortName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(14)

                    Divider().padding(.leading, 16)

                    switch appState.aiConfig.provider {
                    case .gemini:
                        cleanFieldRow("地址", placeholder: AIConfig.defaultGeminiBaseURL, text: $appState.aiConfig.geminiBaseURL, isURL: true)
                        Divider().padding(.leading, 72)
                        apiKeyRow(placeholder: "AIza...", text: $appState.aiConfig.geminiAPIKey)
                        Divider().padding(.leading, 72)
                        modelRow(placeholder: GeminiModelOption.flash25.rawValue, text: $appState.aiConfig.geminiModel)
                    case .openAICompatible:
                        cleanFieldRow("地址", placeholder: "https://api.deepseek.com/v1", text: $appState.aiConfig.openAIBaseURL, isURL: true)
                        Divider().padding(.leading, 72)
                        apiKeyRow(placeholder: "sk-...", text: $appState.aiConfig.openAIAPIKey)
                        Divider().padding(.leading, 72)
                        modelRow(placeholder: "deepseek-chat", text: $appState.aiConfig.openAIModel)
                    case .anthropic:
                        cleanFieldRow("地址", placeholder: AIConfig.defaultAnthropicBaseURL, text: $appState.aiConfig.anthropicBaseURL, isURL: true)
                        Divider().padding(.leading, 72)
                        apiKeyRow(placeholder: "sk-ant-...", text: $appState.aiConfig.anthropicAPIKey)
                        Divider().padding(.leading, 72)
                        modelRow(placeholder: AIConfig.defaultAnthropicModel, text: $appState.aiConfig.anthropicModel)
                    }

                    Divider().padding(.leading, 16)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAdvancedParams.toggle() }
                    } label: {
                        HStack {
                            Text("高级路由与档案")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color(Design.Palette.slate))
                            Spacer()
                            Text(appState.aiConfig.profiles.isEmpty ? "展开" : "\(appState.aiConfig.profiles.count) 档案")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                            Image(systemName: showAdvancedParams ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(Design.Palette.muted))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showAdvancedParams {
                        Divider().padding(.leading, 16)
                        advancedExpandedPanel
                    }
                }
            }
        }
    }

    private var advancedExpandedPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 渠道档案
            HStack {
                Text("渠道档案")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.stone))
                Spacer()
                Button("存为新档案") {
                    saveProfileAsNew = true
                    newProfileName = "\(appState.aiConfig.provider.shortName) 档案"
                    showSaveProfileAlert = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(Design.Palette.accent))
                .buttonStyle(.plain)

                if !appState.aiConfig.profiles.isEmpty {
                    Button("管理") { activeSheet = .profileManager }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.stone))
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                }
            }

            if !appState.aiConfig.profiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(appState.aiConfig.profiles) { prof in
                            let current = appState.aiConfig.activeProfileID == prof.id
                            Button {
                                appState.aiConfig.activateProfile(prof)
                                lastLatencyMs = nil
                                showToast("已切至「\(prof.name)」")
                            } label: {
                                Text(prof.name)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 11)
                                    .frame(height: 28)
                                    .foregroundStyle(current ? Color.white : Color(Design.Palette.ink))
                                    .background(current ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Text("思考模式")
                    .font(.footnote)
                    .foregroundStyle(Color(Design.Palette.slate))
                Spacer()
                Picker("思考模式", selection: $appState.aiConfig.thinkingMode) {
                    ForEach(AIThinkingMode.allCases) { m in
                        Text(m.shortBadge).tag(m)
                    }
                }
                .labelsHidden()
            }

            compactInlineField("快模型", placeholder: "可选", text: $appState.aiConfig.fastModel, target: .fast)
            compactInlineField("深模型", placeholder: "可选", text: $appState.aiConfig.deepModel, target: .deep)
            compactInlineField("视觉模型", placeholder: "可选", text: $appState.aiConfig.visionModel, target: .vision)
            compactInlineField("唤起词", placeholder: "@ai", text: $appState.aiConfig.aiTriggerPrefix, target: nil)

            HStack {
                Text("温度 \(String(format: "%.1f", appState.aiConfig.temperature))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.stone))
                    .frame(width: 64, alignment: .leading)
                Slider(value: $appState.aiConfig.temperature, in: 0.0...1.5, step: 0.1)
                    .tint(Color(Design.Palette.accent))
            }

            Button {
                activeSheet = .customHeaders
            } label: {
                HStack {
                    Text("自定义 HTTP Headers")
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.ink))
                    Spacer()
                    Text(appState.aiConfig.customHeaders.isEmpty ? "无" : "\(appState.aiConfig.customHeaders.count) 项")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.muted))
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - 4. 核心功能（仅 4 行干净单行入口，零冗余噱头）

    private var coreCapabilitiesBlock: some View {
        let skillCount = appState.aiConfig.resolvedKeyboardBuiltinActions.count + appState.aiConfig.customPrompts.count
        return VStack(alignment: .leading, spacing: 8) {
            LXSectionLabel("核心功能")

            LXGroupCard {
                Button {
                    pushedDestination = .obsidianVault
                } label: {
                    LXCleanRow(
                        icon: "circle.hexagongrid",
                        title: "Obsidian 双链记忆库",
                        value: "\(appState.cognitiveStats.vaultNoteCount) 篇",
                        tint: Color(Design.Palette.accent)
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 58)

                Button {
                    pushedDestination = .privacyShield
                } label: {
                    LXCleanRow(
                        icon: "checkmark.shield",
                        title: "隐私脱敏护盾",
                        value: appState.aiConfig.privacyShieldEnabled ? "已开启" : "已关闭",
                        tint: appState.aiConfig.privacyShieldEnabled ? Color(Design.Palette.success) : Color(Design.Palette.ink)
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 58)

                Button {
                    pushedDestination = .promptsWorkshop
                } label: {
                    LXCleanRow(
                        icon: "wand.and.stars",
                        title: "键盘技能与指令",
                        value: "\(skillCount) 项"
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 58)

                Button {
                    pushedDestination = .styleAndContext
                } label: {
                    LXCleanRow(
                        icon: "doc.text",
                        title: "文风与知识卡",
                        value: "\(appState.aiConfig.contextCards.count) 卡"
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 58)

                Button {
                    pushedDestination = .historyAndUsage
                } label: {
                    LXCleanRow(
                        icon: "chart.bar",
                        title: "用量与历史",
                        value: "\(cachedHistoryCount) 条"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 5. 静默折叠扩展区（不打扰主屏）

    private var moreToolsBlock: some View {
        LXGroupCard {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showMoreTools.toggle() }
            } label: {
                HStack {
                    Text("更多工具与配置包")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color(Design.Palette.stone))
                    Spacer()
                    Image(systemName: showMoreTools ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.muted))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showMoreTools {
                Divider().padding(.leading, 16)
                Button { pushedDestination = .translationStudio } label: {
                    LXCleanRow(icon: "globe", title: "多语专业翻译", value: appState.settings.translateTargetLang)
                }.buttonStyle(.plain)
                Divider().padding(.leading, 58)
                Button { appState.showScreenshotVision = true } label: {
                    LXCleanRow(icon: "viewfinder.rectangular", title: "截屏 AI 识图")
                }.buttonStyle(.plain)
                Divider().padding(.leading, 58)
                Button { appState.showVoiceTranslator = true } label: {
                    LXCleanRow(icon: "mic", title: "实时语音同传")
                }.buttonStyle(.plain)
                Divider().padding(.leading, 58)
                Button { pushedDestination = .pipelineStudio } label: {
                    LXCleanRow(icon: "arrow.triangle.branch", title: "链式流水线", value: "\(appState.aiConfig.aiPipelines.count) 条")
                }.buttonStyle(.plain)
                Divider().padding(.leading, 58)
                HStack(spacing: 10) {
                    Button {
                        if let data = appState.aiConfig.exportBrainBundleJSON() {
                            brainExportDoc = PromptsJSONDocument(data: data)
                            showBrainExporter = true
                        }
                    } label: {
                        Label("导出无密钥包", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.ink)))
                    .background(
                        Color.clear.fileExporter(
                            isPresented: $showBrainExporter,
                            document: brainExportDoc,
                            contentType: .json,
                            defaultFilename: "lingxi-ai-brain-nokey"
                        ) { result in
                            if case .success = result { showToast("已导出无密钥配置包") }
                        }
                    )

                    Button {
                        showBrainImporter = true
                    } label: {
                        Label("导入配置包", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.ink)))
                    .background(
                        Color.clear.fileImporter(isPresented: $showBrainImporter, allowedContentTypes: [.json]) { result in
                            if case .success(let url) = result {
                                let granted = url.startAccessingSecurityScopedResource()
                                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                                if let data = try? Data(contentsOf: url),
                                   let stats = appState.aiConfig.importBrainBundleJSON(data) {
                                    showToast("已导入 \(stats.prompts) 技能 · \(stats.cards) 知识卡")
                                } else {
                                    showToast("配置包无效", isError: true)
                                }
                            }
                        }
                    )
                }
                .padding(14)
            }
        }
    }

    // MARK: - Compact Field & Row Helpers

    @ViewBuilder
    private var setupBanner: some View {
        if keyboardNeedsPermission {
            Button {
                appState.showPermissionsCenter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.warning))
                    Text(!appState.isKeyboardEnabled ? "未启用灵犀键盘" : "需开启「允许完全访问」")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Spacer()
                    Text("去开启")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.warning))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(Design.Palette.warning).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        } else if !AppGroup.isAvailable && appState.aiConfig.isConfigured {
            Button {
                Task {
                    isSyncingBridge = true
                    defer { isSyncingBridge = false }
                    let res = await appState.copySideloadBridgeTokenAndSync()
                    showToast(res.message, isError: !res.ok)
                }
            } label: {
                HStack(spacing: 8) {
                    if isSyncingBridge {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                    Text("侧载模式：将配置同步至键盘")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Spacer()
                    Text("同步")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.accent))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(Design.Palette.accentSoft), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSyncingBridge)
        }
    }

    private func isPresetActive(_ preset: ProviderPreset) -> Bool {
        guard appState.aiConfig.provider == preset.provider else { return false }
        guard let keyword = preset.urlKeyword else { return true }
        return appState.aiConfig.openAIBaseURL.lowercased().contains(keyword)
    }

    private func providerPill(_ preset: ProviderPreset) -> some View {
        let active = isPresetActive(preset)
        return Button {
            applyQuickProviderPreset(preset)
            showToast("已切换 \(preset.title)")
        } label: {
            Text(preset.title)
                .font(.footnote.weight(active ? .semibold : .medium))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                .background(active ? Color(Design.Palette.ink) : Color(Design.Palette.canvas), in: Capsule())
                .overlay(Capsule().stroke(active ? Color.clear : Color(Design.Palette.hairline), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func cleanFieldRow(_ label: String, placeholder: String, text: Binding<String>, isURL: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(Design.Palette.stone))
                .frame(width: 44, alignment: .leading)
            TextField(placeholder, text: text)
                .keyboardType(isURL ? .URL : .default)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
                .foregroundStyle(Color(Design.Palette.ink))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 46)
    }

    private func apiKeyRow(placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text("Key")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(Design.Palette.stone))
                .frame(width: 44, alignment: .leading)
            Group {
                if revealKey {
                    TextField(placeholder, text: text)
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.footnote.monospaced())

            if text.wrappedValue.isEmpty {
                Button("粘贴") {
                    if let p = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                        text.wrappedValue = p
                        showToast("已粘贴 API Key")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(Design.Palette.accent))
                .buttonStyle(.plain)
            } else {
                Button {
                    ConcealedPasteboard.copy(text.wrappedValue, expiresIn: 60)
                    showToast("已安全复制 Key")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制 Key")
            }

            Button {
                revealKey.toggle()
            } label: {
                Image(systemName: revealKey ? "eye.slash" : "eye")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealKey ? "隐藏 Key" : "显示 Key")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 46)
    }

    private func modelRow(placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text("模型")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(Design.Palette.stone))
                .frame(width: 44, alignment: .leading)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
                .foregroundStyle(Color(Design.Palette.ink))

            Button {
                Task { await triggerFetchModels(openSheetOnSuccess: true, target: .primary) }
            } label: {
                if appState.isFetchingAIModels {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(hasFreshModelsForCurrentSource ? "选择" : "拉取")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .foregroundStyle(Color(Design.Palette.accent))
                        .background(Color(Design.Palette.accentSoft), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .disabled(appState.isFetchingAIModels || !appState.aiConfig.isConfigured)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 46)
    }

    private func compactInlineField(_ title: String, placeholder: String, text: Binding<String>, target: AIModelAssignTarget?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(Design.Palette.stone))
                .frame(width: 54, alignment: .leading)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if let target, hasFreshModelsForCurrentSource {
                Button("选") { activeSheet = .modelPicker(target) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.accent))
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func showToast(_ msg: String, isError: Bool = false) {
        toastIsError = isError
        toastMessage = msg
    }

    private func currentModelFor(target: AIModelAssignTarget) -> String {
        switch target {
        case .primary: return appState.aiConfig.activeModelName
        case .fast: return appState.aiConfig.fastModel
        case .deep: return appState.aiConfig.deepModel
        case .vision: return appState.aiConfig.visionModel
        }
    }

    private func assignModel(_ id: String, to target: AIModelAssignTarget) {
        switch target {
        case .primary: appState.aiConfig.setActiveModel(id)
        case .fast: appState.aiConfig.fastModel = id
        case .deep: appState.aiConfig.deepModel = id
        case .vision: appState.aiConfig.visionModel = id
        }
    }

    private func applyQuickProviderPreset(_ preset: ProviderPreset) {
        let oldSourceKey = appState.aiConfig.currentModelsSourceKey
        appState.aiConfig.activeProfileID = nil
        appState.aiConfig.provider = preset.provider
        switch preset.provider {
        case .gemini:
            appState.aiConfig.geminiBaseURL = preset.baseURL
            appState.aiConfig.geminiModel = preset.model
        case .openAICompatible:
            appState.aiConfig.openAIBaseURL = preset.baseURL
            appState.aiConfig.openAIModel = preset.model
        case .anthropic:
            appState.aiConfig.anthropicBaseURL = preset.baseURL
            appState.aiConfig.anthropicModel = preset.model
        }
        if let fm = preset.fastModel { appState.aiConfig.fastModel = fm }
        if let dm = preset.deepModel { appState.aiConfig.deepModel = dm }
        if let vm = preset.visionModel { appState.aiConfig.visionModel = vm }
        if appState.aiConfig.currentModelsSourceKey != oldSourceKey {
            appState.aiConfig.fetchedModels = []
            appState.aiConfig.fetchedModelsSourceKey = ""
            modelFetchError = nil
        }
        lastLatencyMs = nil
    }

    private func triggerFetchModels(openSheetOnSuccess: Bool, target: AIModelAssignTarget = .primary) async {
        modelFetchError = nil
        do {
            let models = try await appState.fetchAvailableAIModels()
            showToast("已拉取 \(models.count) 个模型")
            if openSheetOnSuccess { activeSheet = .modelPicker(target) }
        } catch {
            modelFetchError = error.localizedDescription
            showToast("拉取失败：\(error.localizedDescription)", isError: true)
        }
    }

    private func runConnectivityTest() {
        isTesting = true
        let snapshot = appState.aiConfig
        Task {
            do {
                let start = Date()
                let reply = try await client.testConnection(config: snapshot)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                await MainActor.run {
                    isTesting = false
                    lastLatencyMs = ms
                    showToast("连通成功 · \(ms) ms：\(reply.prefix(20))")
                    appState.refreshAll()
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    lastLatencyMs = nil
                    showToast("测速失败：\(error.localizedDescription)", isError: true)
                }
            }
        }
    }
}
