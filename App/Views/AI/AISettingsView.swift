import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// AI 智脑中心 v5（旗舰级个人 AI 写作与沟通全能中枢 · 极简白 / 墨玉设计系统）
/// ① 状态与全路由体检卡 ② 首屏「闪电即用 AI 指令台」（含实时红绿 Diff）
/// ③ 8 大旗舰 AI 创作工具矩阵 ④ 专属进化、隐私护盾与费用账本
/// ⑤ 10 家服务商快切 ⑥ 引擎连接与四路路由/档案/Headers ⑦ 常用 AI 偏好
struct AISettingsView: View {
    private enum StudioDestination: Hashable {
        case autopilotHub
        case obsidianVault
        case toneAndDiff
        case writingStudio
        case translationStudio
        case pipelineStudio
        case offlineLinter
        case multiModelCouncil
        case parameterizedRunner
        case promptsWorkshop
        case styleAndContext
        case privacyShield
        case autoInsight
        case historyAndUsage
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

    // 首屏闪电即用 AI 指令台
    @State private var quickInput = ""
    @State private var quickAction: AIPresetAction = .polish
    @State private var quickResultLabel = ""
    @State private var quickOutput = ""
    @State private var quickShowDiff = true
    @State private var isRunningQuickAI = false
    @State private var quickTask: Task<Void, Never>?

    // 单一集中式弹窗与导航状态（杜绝 iOS 16–18 多 .sheet / NavigationStack(path:) 混用导致的闪退）
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
    /// 历史条数与会话数只在进入页面时读盘一次，避免重绘触发磁盘 IO
    @State private var cachedHistoryCount = 0
    @State private var cachedThreadCount = 0

    private let client = AIClient()

    private var hasFreshModelsForCurrentSource: Bool {
        !appState.aiConfig.fetchedModels.isEmpty
            && (appState.aiConfig.fetchedModelsSourceKey.isEmpty
                || appState.aiConfig.fetchedModelsSourceKey == appState.aiConfig.currentModelsSourceKey)
    }

    private var activeModelDisplaySubtitle: String? {
        let activeID = appState.aiConfig.activeModelName
        guard let matched = appState.aiConfig.fetchedModels.first(where: { $0.id == activeID }),
              !matched.displayName.isEmpty,
              matched.displayName != activeID else {
            return nil
        }
        return matched.displayName
    }

    private var providerShortName: String {
        appState.aiConfig.provider.shortName
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

    private static let providerPresets: [ProviderPreset] = [
        ProviderPreset(id: "gemini", title: "Gemini", provider: .gemini, baseURL: AIConfig.defaultGeminiBaseURL, model: GeminiModelOption.flash25.rawValue, deepModel: GeminiModelOption.pro25.rawValue, visionModel: GeminiModelOption.flash25.rawValue),
        ProviderPreset(id: "claude", title: "Claude 原生", provider: .anthropic, baseURL: AIConfig.defaultAnthropicBaseURL, model: AIConfig.defaultAnthropicModel, fastModel: "claude-3-5-haiku-20241022", deepModel: "claude-opus-4-20250514", visionModel: AIConfig.defaultAnthropicModel),
        ProviderPreset(id: "deepseek", title: "DeepSeek", provider: .openAICompatible, baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat", fastModel: "deepseek-chat", deepModel: "deepseek-reasoner", urlKeyword: "deepseek.com"),
        ProviderPreset(id: "openai", title: "OpenAI", provider: .openAICompatible, baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", fastModel: "gpt-4o-mini", deepModel: "o3-mini", visionModel: "gpt-4o", urlKeyword: "api.openai.com"),
        ProviderPreset(id: "qwen", title: "通义千问", provider: .openAICompatible, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", fastModel: "qwen-turbo", deepModel: "qwq-plus", visionModel: "qwen-vl-max", urlKeyword: "dashscope"),
        ProviderPreset(id: "siliconflow", title: "SiliconFlow", provider: .openAICompatible, baseURL: "https://api.siliconflow.cn/v1", model: "deepseek-ai/DeepSeek-V3", deepModel: "deepseek-ai/DeepSeek-R1", visionModel: "Qwen/Qwen2.5-VL-72B-Instruct", urlKeyword: "siliconflow"),
        ProviderPreset(id: "openrouter", title: "OpenRouter", provider: .openAICompatible, baseURL: "https://openrouter.ai/api/v1", model: "google/gemini-2.5-flash", deepModel: "deepseek/deepseek-r1", visionModel: "google/gemini-2.5-flash", urlKeyword: "openrouter"),
        ProviderPreset(id: "zhipu", title: "智谱 GLM", provider: .openAICompatible, baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash", deepModel: "glm-z1-flash", visionModel: "glm-4v-flash", urlKeyword: "bigmodel.cn"),
        ProviderPreset(id: "doubao", title: "火山方舟", provider: .openAICompatible, baseURL: "https://ark.cn-beijing.volces.com/api/v3", model: "doubao-1-5-pro-32k-250115", visionModel: "doubao-1-5-vision-pro-32k-250115", urlKeyword: "volces.com"),
        ProviderPreset(id: "groq", title: "Groq 极速", provider: .openAICompatible, baseURL: "https://api.groq.com/openai/v1", model: "llama-3.3-70b-versatile", fastModel: "llama-3.1-8b-instant", urlKeyword: "groq.com"),
        ProviderPreset(id: "ollama", title: "Ollama 本地", provider: .openAICompatible, baseURL: "http://127.0.0.1:11434/v1", model: "qwen2.5:7b", urlKeyword: "11434"),
    ]

    private static let inlineQuickActions: [AIPresetAction] = [.polish, .eqReply, .translateEn, .summarize]

    var body: some View {
        NavigationStack {
            List {
                heroStatusSection
                autopilotHeroSection
                inlineQuickAISection
                creativeToolsMatrixSection
                evolutionAndSafetySection
                providerSection
                connectionSection
                advancedSection
                quickPreferencesSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("AI 智脑")
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
                cachedThreadCount = AIWorkbenchThreadsStore.load().count
                appState.refreshCognitiveStats()
            }
            .onDisappear {
                quickTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            activeSheet = .benchmark
                        } label: {
                            Image(systemName: "speedometer")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.accent))
                        }
                        .accessibilityLabel("全路由测速体检")

                        Button {
                            appState.showPermissionsCenter = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: appState.isKeyboardFullAccessConfirmed ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                    .font(.caption.bold())
                                Text("权限")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(appState.isKeyboardFullAccessConfirmed ? Color(Design.Palette.success) : Color(Design.Palette.warning))
                        }
                        .accessibilityLabel("权限中心")
                    }
                }
            }
            .lxToast($toastMessage, isError: toastIsError)
            .alert(saveProfileAsNew ? "另存为新渠道档案" : "更新当前渠道档案", isPresented: $showSaveProfileAlert) {
                TextField("档案名（如：公司 Gemini）", text: $newProfileName)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    let chosenName = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.aiConfig.saveCurrentAsProfile(name: chosenName, createNew: saveProfileAsNew)
                    let display = chosenName.isEmpty ? appState.aiConfig.activeModelName : chosenName
                    showToast(saveProfileAsNew ? "已新建档案「\(display)」" : "已更新档案「\(display)」")
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
                    AIProfileManagerSheet { msg in
                        showToast(msg)
                    }
                    .environmentObject(appState)
                case .customHeaders:
                    AICustomHeadersSheet { msg in
                        showToast(msg)
                    }
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
        case .toneAndDiff:
            AIToneAndDiffStudioView { draft in openWorkbench(tab: 0, draft: draft) }
        case .writingStudio:
            AIWritingStudioView { draft in openWorkbench(tab: 0, draft: draft) }
        case .translationStudio:
            AITranslationStudioView()
        case .pipelineStudio:
            AIPipelineStudioView { draft in openWorkbench(tab: 0, draft: draft) }
        case .offlineLinter:
            AIOfflineLinterView { draft in openWorkbench(tab: 0, draft: draft) }
        case .multiModelCouncil:
            AIMultiModelCouncilView { draft in openWorkbench(tab: 0, draft: draft) }
        case .parameterizedRunner:
            AIParameterizedRunnerView { draft in openWorkbench(tab: 0, draft: draft) }
        case .promptsWorkshop:
            AIPromptsWorkshopView()
        case .styleAndContext:
            AIStyleAndContextView()
        case .privacyShield:
            AIPrivacyShieldView()
        case .autoInsight:
            AIAutoInsightView()
        case .historyAndUsage:
            AIHistoryAndUsageView { draft in openWorkbench(tab: 0, draft: draft) }
        case .none:
            EmptyView()
        }
    }

    private func openWorkbench(tab: Int = 0, draft: String? = nil) {
        activeSheet = .workbench(tab: tab, draft: draft)
    }

    // MARK: - 1.5 AI 全权托管与本地学习数据库主入口卡

    private var autopilotHeroSection: some View {
        let mode = appState.settings.aiAutopilotMode
        let stats = appState.cognitiveStats
        return Section {
            Button {
                pushedDestination = .autopilotHub
            } label: {
                HStack(spacing: 12) {
                    LXIconTile(
                        icon: "brain.head.profile",
                        tint: mode == .fullAutopilot ? Color(Design.Palette.accent) : Color(Design.Palette.stone),
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("AI 全权托管与学习数据库")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            LXTag(
                                text: mode.shortBadge,
                                tint: mode == .fullAutopilot ? Color(Design.Palette.success) : Color(Design.Palette.accent),
                                filled: mode == .fullAutopilot
                            )
                        }
                        Text(
                            stats.personaDigest.isEmpty
                                ? "Obsidian 双链记忆库 · \(stats.vaultNoteCount) 笔记 · \(stats.vaultLinkCount) 双链 · \(stats.activeDecisionCount) 项已自动开启"
                                : stats.personaDigest
                        )
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    Task {
                        let res = await appState.runObsidianAPISelfLearning()
                        showToast(res.summary)
                    }
                } label: {
                    HStack(spacing: 5) {
                        if appState.isRunningObsidianLearn || appState.isRunningAutopilot {
                            ProgressView().controlSize(.mini).tint(Color.white)
                            Text("API 自学习演化中…")
                        } else {
                            Image(systemName: "sparkles")
                            Text("API 自学习与托管")
                        }
                    }
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                .disabled(appState.isRunningObsidianLearn || appState.isRunningAutopilot || mode == .off)

                Button {
                    pushedDestination = .obsidianVault
                } label: {
                    Label("双链图谱", systemImage: "circle.hexagongrid")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false))
            }
            .padding(.vertical, 2)
        } header: {
            Text("越打越懂你的专属 AI 管家")
        }
    }

    // MARK: - 1. 顶部状态与全路由主操作卡

    private var heroStatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                        .background(Color(Design.Palette.accent), in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.aiConfig.isConfigured ? Color(Design.Palette.success) : Color(Design.Palette.warning))
                                .frame(width: 8, height: 8)
                            Text(appState.aiConfig.isConfigured ? "AI 智脑已就绪" : "待填写 API Key")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            if let profName = activeProfileName {
                                LXTag(text: profName, tint: Color(Design.Palette.accent), filled: true)
                            }
                            if appState.aiConfig.privacyShieldEnabled {
                                LXTag(text: "护盾", icon: "checkmark.shield.fill", tint: Color(Design.Palette.success), filled: true)
                            }
                            if appState.aiConfig.monthlyBudgetCNY > 0 {
                                let monthCNY = AICostEstimator.currentMonthEstimatedUSD(for: appState.aiUsageLedger) * 7.25
                                let ratio = monthCNY / appState.aiConfig.monthlyBudgetCNY
                                if ratio >= 0.8 {
                                    LXTag(
                                        text: ratio >= 1.0 ? "已超月预算" : "预算 \(Int(ratio * 100))%",
                                        icon: "exclamationmark.triangle.fill",
                                        tint: ratio >= 1.0 ? Color(Design.Palette.error) : Color(Design.Palette.warning),
                                        filled: true
                                    )
                                }
                            }
                        }
                        Text("\(providerShortName) · 思考 \(appState.aiConfig.thinkingMode.shortBadge) · 场景 \(appState.aiConfig.activeScenePersona.shortTitle)")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if let ms = lastLatencyMs {
                        Label("\(ms) ms", systemImage: "bolt.fill")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color(Design.Palette.success))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(Design.Palette.success).opacity(0.12), in: Capsule())
                    }
                }

                activeModelStrip

                HStack(spacing: 8) {
                    heroActionButton(
                        isTesting ? "测速中…" : "闪电测速",
                        icon: "bolt.horizontal.circle",
                        primary: false,
                        loading: isTesting,
                        disabled: isTesting || !appState.aiConfig.isConfigured
                    ) {
                        runConnectivityTest()
                    }
                    heroActionButton("全路由体检", icon: "speedometer", primary: false) {
                        activeSheet = .benchmark
                    }
                    heroActionButton("多模态工作台", icon: "bubble.left.and.text.bubble.right.fill", primary: true) {
                        openWorkbench(tab: 0)
                    }
                }

                setupBanner
            }
            .padding(.vertical, 6)
        }
    }

    private var activeModelStrip: some View {
        let cfg = appState.aiConfig
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("当前主模型")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.stone))
                Spacer(minLength: 4)
                Button {
                    UIPasteboard.general.string = cfg.activeModelName
                    showToast("已复制模型名")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.stone))
                        .frame(width: 30, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制模型名")
            }
            Text(cfg.activeModelName.isEmpty ? "未设置模型" : cfg.activeModelName)
                .font(.footnote.weight(.semibold).monospaced())
                .foregroundStyle(Color(Design.Palette.ink))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let subtitle = activeModelDisplaySubtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !cfg.fastModel.isEmpty || !cfg.deepModel.isEmpty || !cfg.visionModel.isEmpty || !cfg.customHeaders.isEmpty {
                LXFlowLayout(spacing: 6, lineSpacing: 4) {
                    if !cfg.fastModel.isEmpty { LXTag(text: "快: \(cfg.fastModel)") }
                    if !cfg.deepModel.isEmpty { LXTag(text: "深: \(cfg.deepModel)", tint: Color(Design.Palette.accent), filled: true) }
                    if !cfg.visionModel.isEmpty { LXTag(text: "视觉: \(cfg.visionModel)") }
                    if !cfg.customHeaders.isEmpty { LXTag(text: "\(cfg.customHeaders.count) Headers") }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
        )
    }

    // MARK: - 2. 首屏「闪电即用 AI 指令台」（无需跳转直接改写 + 红绿 Diff）

    private var inlineQuickAISection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("贴一句聊天消息或草稿，就地润色 / 回复 / 翻译…", text: $quickInput)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .disabled(isRunningQuickAI)

                    Button {
                        if let clip = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
                            quickInput = clip
                            showToast("已粘贴剪贴板文本")
                        } else {
                            showToast("剪贴板为空或受保险箱隐私保护")
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.accent))
                            .frame(width: 36, height: 36)
                            .background(Color(Design.Palette.accentSoft), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunningQuickAI)
                    .accessibilityLabel("粘贴")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.inlineQuickActions) { act in
                            let selected = quickAction == act && isRunningQuickAI
                            Button {
                                quickAction = act
                                runInlineQuickAI(act)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: act.icon)
                                        .font(.caption2.weight(.semibold))
                                    Text(act.title)
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .foregroundStyle(selected ? Color.white : Color(Design.Palette.ink))
                                .background(selected ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
                                .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: selected ? 0 : 0.6))
                            }
                            .buttonStyle(.plain)
                            .disabled(isRunningQuickAI || !appState.aiConfig.isConfigured || quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if isRunningQuickAI {
                            Button("停止") {
                                quickTask?.cancel()
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false, tint: Color(Design.Palette.error)))
                        } else {
                            let hasText = !quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            Button {
                                runInlineOfflineTool(label: "离线排版", showDiff: true) { OfflineTextLinter.autoFix($0) }
                            } label: {
                                Label("离线排版", systemImage: "text.badge.checkmark")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 11)
                                    .frame(height: 32)
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .background(Color(Design.Palette.surface), in: Capsule())
                                    .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.6))
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasText)

                            Button {
                                runInlineOfflineTool(label: "离线去口水", showDiff: true) { VoiceTranscriptCleaner.clean($0).cleaned }
                            } label: {
                                Label("去口水", systemImage: "waveform")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 11)
                                    .frame(height: 32)
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .background(Color(Design.Palette.surface), in: Capsule())
                                    .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.6))
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasText)

                            Button {
                                runInlineOfflineTool(label: "隐私脱敏", showDiff: true) {
                                    AIPrivacyShield.sanitize($0, customTerms: appState.aiConfig.privacyCustomTerms).sanitizedText
                                }
                            } label: {
                                Label("脱敏", systemImage: "lock.shield")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 11)
                                    .frame(height: 32)
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .background(Color(Design.Palette.surface), in: Capsule())
                                    .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.6))
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasText)
                        }
                    }
                }

                if !quickOutput.isEmpty {
                    let activeLabel = quickResultLabel.isEmpty ? quickAction.title : quickResultLabel
                    let supportsDiff = quickResultLabel.isEmpty ? (quickAction == .polish || quickAction == .summarize) : true
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            LXTag(text: activeLabel, tint: Color(Design.Palette.accent), filled: true)
                            Spacer()
                            if supportsDiff {
                                Button(quickShowDiff ? "看纯净成品" : "看红绿 Diff") {
                                    quickShowDiff.toggle()
                                }
                                .font(.caption2.bold())
                                .foregroundStyle(Color(Design.Palette.accent))
                                .buttonStyle(.plain)
                            }
                        }

                        if quickShowDiff && supportsDiff {
                            let diff = AITextDiffEngine.diff(
                                original: quickInput.trimmingCharacters(in: .whitespacesAndNewlines),
                                revised: quickOutput
                            )
                            LXDiffHighlightText(report: diff)
                        } else {
                            Text(quickOutput)
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }

                        if !isRunningQuickAI {
                            HStack(spacing: 8) {
                                Button {
                                    UIPasteboard.general.string = quickOutput
                                    appState.recordAcceptedAIInteractionAndMaybeLearn(
                                        featureTag: quickResultLabel.isEmpty ? quickAction.rawValue : quickResultLabel,
                                        scene: appState.aiConfig.activeScenePersona.rawValue,
                                        outcome: "copied"
                                    )
                                    showToast("已复制成品")
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                                Button {
                                    appState.addQuickPhrase(title: activeLabel, content: quickOutput, category: "闪电AI")
                                    showToast("已存为快捷短语")
                                } label: {
                                    Label("存短语", systemImage: "text.badge.plus")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                                Button {
                                    openWorkbench(tab: 0, draft: "请帮我基于下面这段继续优化：\n\(quickOutput)")
                                } label: {
                                    Label("进工作台", systemImage: "bubble.left")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                            }
                        }
                    }
                    .padding(11)
                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("闪电即用指令台")
                Spacer()
                Button {
                    pushedDestination = .parameterizedRunner
                } label: {
                    Label("{{变量}} 模板", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.accent))
                }
                .buttonStyle(.plain)
            }
        } footer: {
            Text("不跳页即可就地润色、回复或译英，也支持零联网「离线排版 / 去口水 / 脱敏」实时红绿 Diff；点右上角可打开 Raycast 级动态变量表单模板。")
        }
    }

    private func runInlineOfflineTool(label: String, showDiff: Bool, transform: (String) -> String) {
        let src = quickInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return }
        quickTask?.cancel()
        isRunningQuickAI = false
        quickResultLabel = label
        quickShowDiff = showDiff
        quickOutput = transform(src)
        if quickOutput == src {
            showToast("\(label)：原文已很规范")
        } else {
            showToast("\(label)完成（0ms 本地离线）")
        }
    }

    private func runInlineQuickAI(_ action: AIPresetAction) {
        let src = quickInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return }
        let cfg = appState.aiConfig
        quickResultLabel = ""
        quickOutput = ""
        isRunningQuickAI = true

        quickTask = Task {
            var acc = ""
            defer {
                Task { @MainActor in
                    isRunningQuickAI = false
                    appState.refreshAll()
                }
            }
            do {
                for try await d in client.streamText(
                    prompt: src,
                    systemInstruction: action.systemPrompt,
                    config: cfg,
                    featureTag: "inline_quick_ai",
                    preferFast: !action.prefersDeepModel,
                    preferDeep: action.prefersDeepModel
                ) {
                    if Task.isCancelled { break }
                    acc += d
                    let snap = AITextSanitizer.clean(acc, streaming: true)
                    await MainActor.run { quickOutput = snap }
                }
                let finalOut = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    quickOutput = finalOut
                    if !finalOut.isEmpty {
                        AIRecentHistoryStore.record(title: "闪电 · \(action.title)", output: finalOut, prompt: src)
                        cachedHistoryCount = AIRecentHistoryStore.load().count
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        showToast("执行失败：\(error.localizedDescription)", isError: true)
                    }
                }
            }
        }
    }

    // MARK: - 3. 10 大旗舰 AI 创作工具矩阵（纯静态 2 列 VStack+HStack，杜绝 List 内 LazyVGrid 自适应崩溃）

    private var creativeToolsMatrixSection: some View {
        Section {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        openWorkbench(tab: 0)
                    } label: {
                        studioGridCard(
                            icon: "bubble.left.and.text.bubble.right.fill",
                            title: "多模态工作台",
                            subtitle: "多话题 · 贴图追问 · 朗读",
                            badge: cachedThreadCount > 0 ? "\(cachedThreadCount) 话题" : "对话"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        pushedDestination = .toneAndDiff
                    } label: {
                        studioGridCard(
                            icon: "square.stack.3d.up.fill",
                            title: "三版语气 & Diff",
                            subtitle: "并发 3 版 · 红绿逐字对比",
                            badge: "热门"
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button {
                        pushedDestination = .writingStudio
                    } label: {
                        studioGridCard(
                            icon: "doc.richtext.fill",
                            title: "模板写作 & 拆解",
                            subtitle: "12 套场景表单 · 长文摘要",
                            badge: "12 模板"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        pushedDestination = .translationStudio
                    } label: {
                        studioGridCard(
                            icon: "globe",
                            title: "8 语专业翻译台",
                            subtitle: "双向回译校验 · 语音朗读",
                            badge: "8 语种"
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button {
                        pushedDestination = .pipelineStudio
                    } label: {
                        studioGridCard(
                            icon: "arrow.triangle.branch",
                            title: "AI 链式流水线",
                            subtitle: "多步串联 · 装进键盘",
                            badge: "\(appState.aiConfig.aiPipelines.count) 条"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.showScreenshotVision = true
                    } label: {
                        studioGridCard(
                            icon: "viewfinder.rectangular",
                            title: "截屏 AI 识图",
                            subtitle: "看图回复 · 提字 · 译中",
                            badge: appState.aiConfig.visionModel.isEmpty ? "多模态" : "独立视觉"
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button {
                        appState.showVoiceTranslator = true
                    } label: {
                        studioGridCard(
                            icon: "mic.fill",
                            title: "实时语音同传",
                            subtitle: "中⇄英/日 · 口述整编",
                            badge: "实时"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        openWorkbench(tab: 1)
                    } label: {
                        studioGridCard(
                            icon: "shield.lefthalf.filled",
                            title: "博弈军师 & PK",
                            subtitle: "潜台词 3 策略 · 跨渠道盲测",
                            badge: "进阶"
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button {
                        pushedDestination = .offlineLinter
                    } label: {
                        studioGridCard(
                            icon: "text.badge.checkmark",
                            title: "发前冷静室与质检",
                            subtitle: "情绪降火 · 防诈雷达 · 去 AI 腔 · 排版",
                            badge: "0 Token"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        pushedDestination = .multiModelCouncil
                    } label: {
                        studioGridCard(
                            icon: "person.3.fill",
                            title: "多模型圆桌会诊",
                            subtitle: "2-4 席并发 · 主席融合终版",
                            badge: "MoA"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("AI 创作工具箱（10 大专精工作台）")
        }
    }

    private func studioGridCard(icon: String, title: String, subtitle: String, badge: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LXIconTile(icon: icon, size: 32)
                Spacer(minLength: 4)
                LXTag(text: badge)
            }
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color(Design.Palette.ink))
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Color(Design.Palette.stone))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(Design.Palette.canvas), in: RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
    }

    // MARK: - 4. 专属进化、隐私安全与费用账本

    private var evolutionAndSafetySection: some View {
        let dnaStatus = appState.aiConfig.styleDNA.clonedStyleSummary.isEmpty ? "未克隆" : "已克隆"
        let keyboardBuiltinCount = appState.aiConfig.resolvedKeyboardBuiltinActions.count
        let estCost = AICostEstimator.formatCNY(AICostEstimator.totalEstimatedUSD(for: appState.aiUsageLedger))

        return Section("专属进化、隐私护盾与账本") {
            Button {
                pushedDestination = .promptsWorkshop
            } label: {
                moduleRow(
                    icon: "wand.and.stars",
                    title: "键盘技能工坊与市场",
                    subtitle: "AI 帮写指令 · 键盘栏排布 · \(AIPromptMarketplaceCatalog.allTemplates.count) 条模板 · JSON 分享",
                    badge: "\(keyboardBuiltinCount)+\(appState.aiConfig.customPrompts.count)"
                )
            }
            .buttonStyle(.plain)

            Button {
                pushedDestination = .styleAndContext
            } label: {
                moduleRow(
                    icon: "waveform.path.ecg",
                    title: "文风 DNA 与场景知识卡",
                    subtitle: "克隆文风前后对比 · 知识卡按沟通对象精准挂载",
                    badge: "\(dnaStatus) · \(appState.aiConfig.contextCards.count) 卡"
                )
            }
            .buttonStyle(.plain)

            Button {
                pushedDestination = .privacyShield
            } label: {
                moduleRow(
                    icon: "checkmark.shield.fill",
                    title: "AI 隐私脱敏护盾",
                    subtitle: "发送前本机自动脱敏手机/证件/邮箱/密钥/自定义词",
                    badge: appState.aiConfig.privacyShieldEnabled ? "运行中" : "未开启"
                )
            }
            .buttonStyle(.plain)

            Button {
                pushedDestination = .autoInsight
            } label: {
                moduleRow(
                    icon: "brain.head.profile",
                    title: "智能画像诊断",
                    subtitle: "分析打字习惯，推荐人设、技能与模糊音",
                    badge: appState.aiInsightReport?.personaTitle ?? "未生成"
                )
            }
            .buttonStyle(.plain)

            Button {
                pushedDestination = .historyAndUsage
            } label: {
                moduleRow(
                    icon: "chart.bar.xaxis",
                    title: "历史、趋势与费用账本",
                    subtitle: "最近 \(cachedHistoryCount) 条 · 近 7 天趋势 · 分模型 TTFT 排行",
                    badge: appState.aiUsageLedger.isEmpty ? "0 次" : "\(appState.aiUsageLedger.count) 次 · \(estCost)"
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    LXIconTile(icon: "sparkles.rectangle.stack", size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已接入 iOS 快捷指令、Siri 与专注模式")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("可在系统「快捷指令」中搜「灵犀」，绑定操作按钮/背面轻点执行 AI 处理、离线排版，或随工作专注模式自动切换沟通场景。")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 4)

            HStack(spacing: 10) {
                Button {
                    if let data = appState.aiConfig.exportBrainBundleJSON() {
                        brainExportDoc = PromptsJSONDocument(data: data)
                        showBrainExporter = true
                    }
                } label: {
                    Label("导出智脑包 (无Key)", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                .background(
                    Color.clear.fileExporter(
                        isPresented: $showBrainExporter,
                        document: brainExportDoc,
                        contentType: .json,
                        defaultFilename: "lingxi-ai-brain-nokey"
                    ) { result in
                        switch result {
                        case .success:
                            showToast("已导出无密钥 AI 智脑配置包（不含任何 API Key）")
                        case .failure(let err):
                            let ns = err as NSError
                            if !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) {
                                showToast("导出失败：\(err.localizedDescription)", isError: true)
                            }
                        }
                    }
                )

                Button {
                    showBrainImporter = true
                } label: {
                    Label("导入智脑包", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                .background(
                    Color.clear.fileImporter(isPresented: $showBrainImporter, allowedContentTypes: [.json]) { result in
                        switch result {
                        case .success(let url):
                            let granted = url.startAccessingSecurityScopedResource()
                            defer { if granted { url.stopAccessingSecurityScopedResource() } }
                            guard let data = try? Data(contentsOf: url),
                                  let stats = appState.aiConfig.importBrainBundleJSON(data) else {
                                showToast("文件不是有效的灵犀 AI 智脑配置包", isError: true)
                                return
                            }
                            showToast("已安全合入：\(stats.prompts) 技能 · \(stats.cards) 知识卡 · \(stats.pipelines) 流水线")
                        case .failure(let err):
                            let ns = err as NSError
                            if !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) {
                                showToast("读取失败：\(err.localizedDescription)", isError: true)
                            }
                        }
                    }
                )
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    // MARK: - 5. 常用服务商快切

    private var providerSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.providerPresets) { preset in
                        providerPill(preset)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        } header: {
            Text("常用服务商")
        } footer: {
            Text("一键填好地址与推荐路由模型；切换渠道自动解除旧档案关联并清空旧模型缓存。")
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
            showToast("已切换到 \(preset.title) · \(preset.model)")
        } label: {
            HStack(spacing: 5) {
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(preset.title)
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
            .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.canvas), in: Capsule())
            .overlay(Capsule().stroke(active ? Color.clear : Color(Design.Palette.hairline), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - 6. 模型与连接

    private var connectionSection: some View {
        Section {
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
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            switch appState.aiConfig.provider {
            case .gemini:
                labeledField("地址", placeholder: AIConfig.defaultGeminiBaseURL, text: $appState.aiConfig.geminiBaseURL, isURL: true)
                apiKeyRow(placeholder: "AIza...", text: $appState.aiConfig.geminiAPIKey)
                modelInputRow(placeholder: GeminiModelOption.flash25.rawValue, text: $appState.aiConfig.geminiModel)
            case .openAICompatible:
                labeledField("地址", placeholder: "https://api.deepseek.com/v1", text: $appState.aiConfig.openAIBaseURL, isURL: true)
                apiKeyRow(placeholder: "sk-...", text: $appState.aiConfig.openAIAPIKey)
                modelInputRow(placeholder: "deepseek-chat", text: $appState.aiConfig.openAIModel)
            case .anthropic:
                labeledField("地址", placeholder: AIConfig.defaultAnthropicBaseURL, text: $appState.aiConfig.anthropicBaseURL, isURL: true)
                apiKeyRow(placeholder: "sk-ant-...", text: $appState.aiConfig.anthropicAPIKey)
                modelInputRow(placeholder: AIConfig.defaultAnthropicModel, text: $appState.aiConfig.anthropicModel)
            }

            Picker("思考模式", selection: $appState.aiConfig.thinkingMode) {
                ForEach(AIThinkingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            if appState.aiConfig.thinkingMode == .customBudget {
                compactSliderRow("思考预算", valueText: "\(appState.aiConfig.thinkingBudget)") {
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
        } header: {
            Text("模型与连接")
        } footer: {
            switch appState.aiConfig.provider {
            case .gemini:
                Text("Google Gemini 官方接口（或兼容反代），支持原生多模态看图与音频听写。")
            case .openAICompatible:
                Text("兼容 DeepSeek / OpenAI / 通义千问 / OpenRouter / SiliconFlow / 智谱 / 火山方舟 / Ollama。")
            case .anthropic:
                Text("Anthropic Claude 原生 /v1/messages 接口（支持 Extended Thinking 思考链与原生多模态看图，兼容 Claude 反代）。")
            }
        }
    }

    // MARK: - 7. 高级路由、渠道档案、Headers 与键盘触发设置

    private var advancedSummary: String {
        let c = appState.aiConfig
        return "温度 \(String(format: "%.1f", c.temperature)) · 上限 \(c.maxOutputTokens) · \(c.profiles.count) 档案 · 前缀 \(c.aiTriggerPrefix)"
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAdvancedParams) {
                profilesBlock

                if !appState.aiConfig.profiles.isEmpty {
                    Picker("容灾自动兜底渠道", selection: Binding(
                        get: { appState.aiConfig.failoverProfileID ?? "" },
                        set: { appState.aiConfig.failoverProfileID = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("关闭（不自动切换）").tag("")
                        ForEach(appState.aiConfig.profiles) { prof in
                            Text("\(prof.name) · \(prof.model)").tag(prof.id)
                        }
                    }
                }

                secondaryModelField(title: "快模型", placeholder: "可选（实时翻译 / 简短润色）", text: $appState.aiConfig.fastModel, target: .fast)
                secondaryModelField(title: "深模型", placeholder: "可选（博弈军师 / 深度推理）", text: $appState.aiConfig.deepModel, target: .deep)
                secondaryModelField(title: "视觉模型", placeholder: "可选（截屏识图，如 gpt-4o / qwen-vl-max）", text: $appState.aiConfig.visionModel, target: .vision)
                secondaryModelField(title: "语音转写模型 (STT)", placeholder: "可选（留空自动匹配 whisper-1 / SenseVoice）", text: $appState.aiConfig.sttModel, target: nil)

                Button {
                    activeSheet = .customHeaders
                } label: {
                    HStack {
                        Label("自定义 HTTP Headers", systemImage: "lock.shield")
                            .font(.subheadline)
                            .foregroundStyle(Color(Design.Palette.ink))
                        Spacer()
                        Text(appState.aiConfig.customHeaders.isEmpty ? "未设置" : "\(appState.aiConfig.customHeaders.count) 项")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 36)
                }
                .buttonStyle(.plain)

                labeledField("唤起词", placeholder: "@ai", text: $appState.aiConfig.aiTriggerPrefix)
                compactSliderRow("上下文", valueText: "\(appState.aiConfig.aiContextCharLimit)字") {
                    Slider(
                        value: Binding(
                            get: { Double(appState.aiConfig.aiContextCharLimit) },
                            set: { appState.aiConfig.aiContextCharLimit = Int($0) }
                        ),
                        in: 60...600,
                        step: 30
                    )
                }

                Toggle("展示可折叠思考过程", isOn: $appState.aiConfig.showThinkingProcess)
                Toggle("连通后自动分析画像", isOn: $appState.aiConfig.autoAnalyzeOnConnect)

                compactSliderRow("创造力", valueText: String(format: "%.1f", appState.aiConfig.temperature)) {
                    Slider(value: $appState.aiConfig.temperature, in: 0.0...1.5, step: 0.1)
                }
                compactSliderRow("Top-P", valueText: String(format: "%.2f", appState.aiConfig.topP)) {
                    Slider(value: $appState.aiConfig.topP, in: 0.1...1.0, step: 0.05)
                }
                compactSliderRow("最大字数", valueText: "\(appState.aiConfig.maxOutputTokens)") {
                    Slider(
                        value: Binding(
                            get: { Double(appState.aiConfig.maxOutputTokens) },
                            set: { appState.aiConfig.maxOutputTokens = Int($0) }
                        ),
                        in: 256...8192,
                        step: 256
                    )
                }
            } label: {
                HStack(spacing: 12) {
                    LXIconTile(icon: "slider.horizontal.3")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("高级路由、渠道档案与键盘联动")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text(advancedSummary)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
            }
            .font(.subheadline)
        }
    }

    private var profilesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("渠道档案")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.stone))
                Spacer()
                if activeProfileName != nil {
                    Button("更新档案") {
                        saveProfileAsNew = false
                        newProfileName = activeProfileName ?? appState.aiConfig.activeModelName
                        showSaveProfileAlert = true
                    }
                    .font(.caption.bold())
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(Design.Palette.slate))
                }
                Button {
                    saveProfileAsNew = true
                    newProfileName = "\(appState.aiConfig.provider.shortName) 档案"
                    showSaveProfileAlert = true
                } label: {
                    Label("存为新档案", systemImage: "plus.circle")
                        .font(.caption.bold())
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(Design.Palette.accent))

                if !appState.aiConfig.profiles.isEmpty {
                    Button("管理") {
                        activeSheet = .profileManager
                    }
                    .font(.caption.bold())
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(Design.Palette.stone))
                }
            }

            if appState.aiConfig.profiles.isEmpty {
                Text("把「地址 + Key + 四路模型 + Headers」存为档案，支持一键切换、跨渠道 PK 与并行体检。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.aiConfig.profiles) { prof in
                            let isCurrent = appState.aiConfig.activeProfileID == prof.id
                            Button {
                                appState.aiConfig.activateProfile(prof)
                                lastLatencyMs = nil
                                showToast("已切至「\(prof.name)」")
                            } label: {
                                HStack(spacing: 5) {
                                    if isCurrent {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    Text(prof.name)
                                        .font(.caption.bold())
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(isCurrent ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
                                .foregroundStyle(isCurrent ? Color.white : Color(Design.Palette.ink))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func secondaryModelField(title: String, placeholder: String, text: Binding<String>, target: AIModelAssignTarget?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.stone))
                Spacer()
                if let target, hasFreshModelsForCurrentSource {
                    Button("从列表选") {
                        activeSheet = .modelPicker(target)
                    }
                    .font(.caption.bold())
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(Design.Palette.accent))
                }
            }
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous))
        }
        .padding(.vertical, 2)
    }

    // MARK: - 8. 常用偏好

    private var quickPreferencesSection: some View {
        Section("常用偏好") {
            Picker("沟通对象", selection: $appState.aiConfig.activeScenePersona) {
                ForEach(AIScenePersona.allCases) { scene in
                    Text(scene.shortTitle).tag(scene)
                }
            }
            Picker("默认译文", selection: $appState.settings.translateTargetLang) {
                ForEach(TranslateTargetLanguage.allCases) { lang in
                    Text(lang.rawValue).tag(lang.rawValue)
                }
            }
            Toggle("键盘语境智能推荐", isOn: $appState.aiConfig.smartContextRecommendEnabled)
            Toggle("融合当前城市与时段", isOn: $appState.settings.aiGeoContextEnabled)
            Toggle("截屏识图后自动清理原图", isOn: $appState.settings.autoDeleteUploadedScreenshot)
            Toggle("从手动修改中自动学习文风", isOn: $appState.aiConfig.autoDiffLearnEnabled)
        }
    }

    // MARK: - 共用子视图与动作

    @ViewBuilder
    private var setupBanner: some View {
        if keyboardNeedsPermission {
            Button {
                appState.showPermissionsCenter = true
            } label: {
                bannerContent(
                    icon: "exclamationmark.shield.fill",
                    tint: Color(Design.Palette.warning),
                    text: !appState.isKeyboardEnabled
                        ? "尚未启用灵犀键盘，键盘内暂时用不了 AI"
                        : "键盘未开启「允许完全访问」，AI 无法联网",
                    action: "去开启",
                    loading: false
                )
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
                bannerContent(
                    icon: "arrow.triangle.2.circlepath",
                    tint: Color(Design.Palette.accent),
                    text: "免费侧载模式：改完 Key / 模型后需同步给键盘（仅本机 90 秒有效）",
                    action: "同步",
                    loading: isSyncingBridge
                )
            }
            .buttonStyle(.plain)
            .disabled(isSyncingBridge)
        }
    }

    private func bannerContent(icon: String, tint: Color, text: String, action: String, loading: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 20)

            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(Design.Palette.ink))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Text(action)
                .font(.caption.bold())
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(tint, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func heroActionButton(
        _ title: String,
        icon: String,
        primary: Bool,
        loading: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if loading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(primary ? Color.white : Color(Design.Palette.ink))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .padding(.horizontal, 6)
            .foregroundStyle(primary ? Color.white : Color(Design.Palette.ink))
            .background(primary ? Color(Design.Palette.accent) : Color(Design.Palette.canvas), in: Capsule())
            .overlay(Capsule().stroke(primary ? Color.clear : Color(Design.Palette.hairline), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled && !loading ? 0.45 : 1)
    }

    private func moduleRow(icon: String, title: String, subtitle: String, badge: String?) -> some View {
        HStack(spacing: 12) {
            LXIconTile(icon: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let badge, !badge.isEmpty {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.slate))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(Design.Palette.surface), in: Capsule())
                    .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.5))
                    .frame(maxWidth: 124, alignment: .trailing)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func labeledField(_ label: String, placeholder: String, text: Binding<String>, isURL: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            TextField(placeholder, text: text)
                .keyboardType(isURL ? .URL : .default)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
        }
        .frame(minHeight: 36)
    }

    private func apiKeyRow(placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text("Key")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
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
                Button {
                    if let p = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                        text.wrappedValue = p
                        showToast("已粘贴 API Key")
                    }
                } label: {
                    Text("粘贴")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color(Design.Palette.accentSoft), in: Capsule())
                }
                .foregroundStyle(Color(Design.Palette.accent))
                .buttonStyle(.plain)
            } else {
                Button {
                    ConcealedPasteboard.copy(text.wrappedValue, expiresIn: 60)
                    showToast("已安全复制 Key（仅本机 60 秒自动清除）")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("安全复制 API Key")
            }

            Button {
                revealKey.toggle()
            } label: {
                Image(systemName: revealKey ? "eye.slash" : "eye")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealKey ? "隐藏 Key" : "显示 Key")
        }
        .frame(minHeight: 36)
    }

    private func modelInputRow(placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("模型")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Button {
                    Task { await triggerFetchModels(openSheetOnSuccess: true, target: .primary) }
                } label: {
                    HStack(spacing: 4) {
                        if appState.isFetchingAIModels {
                            ProgressView().controlSize(.mini)
                            Text("拉取中…")
                        } else {
                            Image(systemName: "arrow.clockwise")
                            Text(hasFreshModelsForCurrentSource ? "刷新" : "拉取模型")
                        }
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color(Design.Palette.accentSoft), in: Capsule())
                    .foregroundStyle(Color(Design.Palette.accent))
                }
                .buttonStyle(.plain)
                .disabled(appState.isFetchingAIModels || !appState.aiConfig.isConfigured)
                .opacity(!appState.aiConfig.isConfigured ? 0.45 : 1)

                if hasFreshModelsForCurrentSource {
                    Button {
                        activeSheet = .modelPicker(.primary)
                    } label: {
                        Text("选择 · \(appState.aiConfig.fetchedModels.count)")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Color(Design.Palette.accent), in: Capsule())
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.weight(.medium).monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous))
        }
        .padding(.vertical, 4)
    }

    private func compactSliderRow<S: View>(_ title: String, valueText: String, @ViewBuilder slider: () -> S) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            slider()
                .tint(Color(Design.Palette.accent))
            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color(Design.Palette.ink))
                .frame(width: 48, alignment: .trailing)
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
        case .primary:
            appState.aiConfig.setActiveModel(id)
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
            let chatCount = models.filter(\.isChatModel).count
            showToast("已拉取 \(models.count) 个远端模型（其中 \(chatCount) 个对话模型）")
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
                    showToast("连通成功 · \(ms) ms：\(reply.prefix(24))")
                    appState.refreshAll()
                }
                if snapshot.autoAnalyzeOnConnect {
                    _ = await appState.runAIAutoAnalysis()
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    lastLatencyMs = nil
                    showToast("测试失败：\(error.localizedDescription)", isError: true)
                }
            }
        }
    }
}
