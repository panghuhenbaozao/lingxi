import SwiftUI
import UIKit

/// AI 智脑中心（Apple 原生精简分层布局：首页 3 组清爽卡片，高阶能力按模块收敛到独立子页，零文字堆砌）。
struct AISettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var revealKey = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showAdvancedParams = false

    @State private var showModelPicker = false
    @State private var modelAssignTarget: ModelAssignTarget = .primary
    @State private var showPlaygroundSheet = false
    @State private var showSaveProfileAlert = false
    @State private var newProfileName = ""

    private let client = AIClient()

    enum ModelAssignTarget: String, Identifiable {
        case primary, fast, deep
        var id: String { rawValue }
        var title: String {
            switch self {
            case .primary: return "选择主模型"
            case .fast: return "选择快模型"
            case .deep: return "选择深度模型"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                heroStatusSection
                connectionSection
                modulesHubSection
                quickPreferencesSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("AI 智脑")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPlaygroundSheet = true
                    } label: {
                        Label("试炼场", systemImage: "play.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .alert("保存渠道档案", isPresented: $showSaveProfileAlert) {
                TextField("档案名（如：公司 Gemini）", text: $newProfileName)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    appState.aiConfig.saveCurrentAsProfile(name: newProfileName)
                    showStatus("已保存档案「\(newProfileName.isEmpty ? appState.aiConfig.activeModelName : newProfileName)」")
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
                        showStatus("已选定 \(chosenID)")
                    }
                )
            }
            .sheet(isPresented: $showPlaygroundSheet) {
                AIPlaygroundAndArenaSheet()
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - 1. 顶部精简状态卡（一眼看清模型、思考模式与快捷操作）

    private var heroStatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(Design.Palette.accent))
                            .frame(width: 42, height: 42)
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.aiConfig.activeModelName)
                            .font(.system(size: 15.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.aiConfig.isConfigured ? Color(Design.Palette.success) : Color(Design.Palette.warning))
                                .frame(width: 7, height: 7)
                            Text(appState.aiConfig.isConfigured ? "已就绪" : "待填 Key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("思考 \(appState.aiConfig.thinkingMode.shortBadge)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 6) {
                        Button {
                            runConnectivityTest()
                        } label: {
                            if isTesting {
                                ProgressView().scaleEffect(0.75)
                                    .frame(width: 48, height: 30)
                            } else {
                                Text("测速")
                                    .font(.caption.bold())
                                    .frame(width: 48, height: 30)
                            }
                        }
                        .background(Color(Design.Palette.surface))
                        .foregroundStyle(Color(Design.Palette.ink))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                        .disabled(isTesting || !appState.aiConfig.isConfigured)

                        Button("试炼场") {
                            showPlaygroundSheet = true
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(Color(Design.Palette.accent))
                        .foregroundStyle(Color.white)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                    }
                }

                // 常用服务商一键快切
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        providerPill("Gemini", active: appState.aiConfig.provider == .gemini) {
                            appState.aiConfig.provider = .gemini
                            appState.aiConfig.geminiBaseURL = AIConfig.defaultGeminiBaseURL
                            appState.aiConfig.geminiModel = GeminiModelOption.flash38.rawValue
                        }
                        providerPill("DeepSeek", active: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("deepseek.com")) {
                            appState.aiConfig.provider = .openAICompatible
                            appState.aiConfig.openAIBaseURL = "https://api.deepseek.com/v1"
                            appState.aiConfig.openAIModel = "deepseek-chat"
                            appState.aiConfig.deepModel = "deepseek-reasoner"
                        }
                        providerPill("通义千问", active: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("dashscope")) {
                            appState.aiConfig.provider = .openAICompatible
                            appState.aiConfig.openAIBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
                            appState.aiConfig.openAIModel = "qwen-plus"
                        }
                        providerPill("SiliconFlow", active: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("siliconflow")) {
                            appState.aiConfig.provider = .openAICompatible
                            appState.aiConfig.openAIBaseURL = "https://api.siliconflow.cn/v1"
                            appState.aiConfig.openAIModel = "deepseek-ai/DeepSeek-V3"
                        }
                        providerPill("OpenRouter", active: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("openrouter")) {
                            appState.aiConfig.provider = .openAICompatible
                            appState.aiConfig.openAIBaseURL = "https://openrouter.ai/api/v1"
                            appState.aiConfig.openAIModel = "google/gemini-2.5-flash"
                        }
                        providerPill("Ollama", active: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("11434")) {
                            appState.aiConfig.provider = .openAICompatible
                            appState.aiConfig.openAIBaseURL = "http://127.0.0.1:11434/v1"
                            appState.aiConfig.openAIModel = "qwen2.5:7b"
                        }
                    }
                }

                if let msg = statusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color(Design.Palette.error) : Color(Design.Palette.success))
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 2. 模型与连接（精简 5 行 + 高级参数默认折叠）

    private var connectionSection: some View {
        Section("模型与连接") {
            Picker("协议", selection: $appState.aiConfig.provider) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }

            if appState.aiConfig.provider == .gemini {
                labeledField("地址", placeholder: AIConfig.defaultGeminiBaseURL, text: $appState.aiConfig.geminiBaseURL, isURL: true)
                apiKeyRow(placeholder: "AIza...", text: $appState.aiConfig.geminiAPIKey)
                modelInputRow(placeholder: "gemini-3.8-flash", text: $appState.aiConfig.geminiModel)
            } else {
                labeledField("地址", placeholder: "https://api.deepseek.com/v1", text: $appState.aiConfig.openAIBaseURL, isURL: true)
                apiKeyRow(placeholder: "sk-...", text: $appState.aiConfig.openAIAPIKey)
                modelInputRow(placeholder: "deepseek-chat", text: $appState.aiConfig.openAIModel)
            }

            Picker("思考模式", selection: $appState.aiConfig.thinkingMode) {
                ForEach(AIThinkingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            if appState.aiConfig.thinkingMode == .customBudget {
                HStack {
                    Text("思考预算")
                    Slider(
                        value: Binding(
                            get: { Double(appState.aiConfig.thinkingBudget) },
                            set: { appState.aiConfig.thinkingBudget = Int($0) }
                        ),
                        in: 256...16384,
                        step: 256
                    )
                    Text("\(appState.aiConfig.thinkingBudget)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            DisclosureGroup("高级参数与渠道档案", isExpanded: $showAdvancedParams) {
                if !appState.aiConfig.profiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(appState.aiConfig.profiles) { prof in
                                let isCurrent = appState.aiConfig.activeProfileID == prof.id
                                HStack(spacing: 4) {
                                    Button(prof.name) {
                                        appState.aiConfig.activateProfile(prof)
                                        showStatus("已切至「\(prof.name)」")
                                    }
                                    .font(.caption.bold())
                                    .buttonStyle(.plain)
                                    Button {
                                        appState.aiConfig.profiles.removeAll { $0.id == prof.id }
                                        if appState.aiConfig.activeProfileID == prof.id {
                                            appState.aiConfig.activeProfileID = nil
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").font(.caption2).opacity(0.6)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(isCurrent ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
                                .foregroundStyle(isCurrent ? Color.white : Color(Design.Palette.ink))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                HStack {
                    Text("快模型").font(.subheadline).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                    TextField("可选（翻译/短回复）", text: $appState.aiConfig.fastModel)
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
                    Text("深模型").font(.subheadline).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                    TextField("可选（军师/分析）", text: $appState.aiConfig.deepModel)
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
            }
            .font(.subheadline)
        }
    }

    // MARK: - 3. 核心能力中心（4 个纯粹 AI 二级页入口；地标词库统一归口至「设置 → 词库与实时地标」）

    private var modulesHubSection: some View {
        let historyCount = AIRecentHistoryStore.load().count
        return Section("能力中心") {
            NavigationLink {
                AIPromptsHubView()
            } label: {
                moduleRow(
                    icon: "wand.and.stars",
                    title: "提示词与指令市场",
                    badge: "\(appState.aiConfig.customPrompts.count) 条 · 市场 \(AIPromptMarketplaceCatalog.allTemplates.count)"
                )
            }

            NavigationLink {
                AIStyleAndContextView()
            } label: {
                let dnaStatus = appState.aiConfig.styleDNA.clonedStyleSummary.isEmpty ? "未克隆" : "已克隆"
                moduleRow(
                    icon: "waveform.path.ecg",
                    title: "文风 DNA 与知识卡",
                    badge: "\(dnaStatus) · \(appState.aiConfig.contextCards.count) 卡"
                )
            }

            NavigationLink {
                AIAutoInsightView()
            } label: {
                moduleRow(
                    icon: "brain.head.profile",
                    title: "智能画像诊断",
                    badge: appState.aiInsightReport?.personaTitle ?? "一键分析"
                )
            }

            NavigationLink {
                AIHistoryAndUsageView()
            } label: {
                moduleRow(
                    icon: "clock.arrow.circlepath",
                    title: "生成历史与账本",
                    badge: "\(historyCount) 历史 · \(appState.aiUsageLedger.count) 次"
                )
            }
        }
    }

    // MARK: - 4. 高频偏好（4 行极简开关）

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
        }
    }

    // MARK: - 精简行组件

    private func moduleRow(icon: String, title: String, badge: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.accent))
                .frame(width: 28, height: 28)
                .background(Color(Design.Palette.accentSoft))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(Design.Palette.ink))
            Spacer(minLength: 6)
            Text(badge)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
    }

    private func labeledField(_ label: String, placeholder: String, text: Binding<String>, isURL: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            TextField(placeholder, text: text)
                .keyboardType(isURL ? .URL : .default)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13.5, design: .monospaced))
        }
    }

    private func apiKeyRow(placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text("Key")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            if revealKey {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13.5, design: .monospaced))
            } else {
                SecureField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13.5, design: .monospaced))
            }
            if text.wrappedValue.isEmpty {
                Button("粘贴") {
                    if let p = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                        text.wrappedValue = p
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func modelInputRow(placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text("模型")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13.5, weight: .medium, design: .monospaced))

            Button {
                modelAssignTarget = .primary
                if appState.aiConfig.fetchedModels.isEmpty {
                    Task { await triggerFetchModels(openSheetOnSuccess: true) }
                } else {
                    showModelPicker = true
                }
            } label: {
                if appState.isFetchingAIModels {
                    ProgressView().scaleEffect(0.75)
                } else {
                    Text(appState.aiConfig.fetchedModels.isEmpty ? "拉取" : "选(\(appState.aiConfig.fetchedModels.count))")
                        .font(.caption.bold())
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color(Design.Palette.accentSoft))
            .foregroundStyle(Color(Design.Palette.accent))
            .clipShape(Capsule())
            .buttonStyle(.plain)
            .disabled(appState.isFetchingAIModels || !appState.aiConfig.isConfigured)

            Button {
                newProfileName = appState.aiConfig.provider == .gemini ? "Gemini" : "自定义"
                showSaveProfileAlert = true
            } label: {
                Image(systemName: "bookmark")
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("保存渠道档案")
        }
    }

    private func compactSliderRow<S: View>(_ title: String, valueText: String, @ViewBuilder slider: () -> S) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            slider()
            Text(valueText).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
        }
    }

    private func providerPill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
            .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
            .clipShape(Capsule())
            .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func showStatus(_ msg: String, isError: Bool = false) {
        withAnimation {
            statusMessage = msg
            statusIsError = isError
        }
    }

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
        case .fast: appState.aiConfig.fastModel = id
        case .deep: appState.aiConfig.deepModel = id
        }
    }

    private func triggerFetchModels(openSheetOnSuccess: Bool) async {
        do {
            let models = try await appState.fetchAvailableAIModels()
            showStatus("✓ 已拉取 \(models.count) 个模型")
            if openSheetOnSuccess { showModelPicker = true }
        } catch {
            showStatus("拉取失败：\(error.localizedDescription)", isError: true)
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
                    showStatus("✓ 连通 (\(ms)ms)：\(reply.prefix(24))")
                    appState.refreshAll()
                }
                if snapshot.autoAnalyzeOnConnect {
                    _ = await appState.runAIAutoAnalysis()
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    showStatus("测试失败：\(error.localizedDescription)", isError: true)
                }
            }
        }
    }
}

// MARK: - 子页 1：提示词与指令市场

private struct AIPromptsHubView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showMarketplace = false
    @State private var showNewPrompt = false
    @State private var editingPrompt: CustomAIPromptTemplate?
    @State private var feedback: String?

    var body: some View {
        List {
            Section {
                Button {
                    showMarketplace = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundStyle(Color.white)
                            .frame(width: 30, height: 30)
                            .background(Color(Design.Palette.accent))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI 场景指令市场")
                                .font(.subheadline.bold())
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text("\(AIPromptMarketplaceCatalog.allTemplates.count) 条精选 · 一键装入键盘")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showNewPrompt = true
                } label: {
                    Label("新建自定义技能", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold())
                }
            }

            if let fb = feedback {
                Section {
                    Text(fb).font(.caption).foregroundStyle(Color(Design.Palette.success))
                }
            }

            Section("我的键盘技能 (\(appState.aiConfig.customPrompts.count))") {
                ForEach(appState.aiConfig.customPrompts) { tpl in
                    HStack(spacing: 10) {
                        Button {
                            editingPrompt = tpl
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tpl.icon)
                                    .font(.subheadline)
                                    .foregroundStyle(Color(Design.Palette.accent))
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(tpl.title).font(.subheadline.bold()).foregroundStyle(.primary)
                                        if tpl.useDeepModel {
                                            Text("深度").font(.caption2.bold())
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color(Design.Palette.accentSoft))
                                                .foregroundStyle(Color(Design.Palette.accent))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(tpl.instruction).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
            }

            Section("内置技能") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(AIPresetAction.allCases) { act in
                            Label(act.title, systemImage: act.icon)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(Design.Palette.surface))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("提示词与指令市场")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMarketplace) {
            AIPromptMarketplaceSheet(
                existingTitles: Set(appState.aiConfig.customPrompts.map(\.title)),
                onInstall: { templates in
                    let added = appState.importSuggestedPrompts(templates)
                    feedback = added > 0 ? "✓ 已装入 \(added) 条技能" : "所选技能已存在"
                }
            )
        }
        .sheet(isPresented: $showNewPrompt) {
            CustomPromptEditorSheet(initial: nil) { created in
                appState.addOrUpdateCustomPrompt(created)
                feedback = "✓ 已新建「\(created.title)」"
            }
        }
        .sheet(item: $editingPrompt) { item in
            CustomPromptEditorSheet(initial: item) { updated in
                appState.addOrUpdateCustomPrompt(updated)
                feedback = "✓ 已更新「\(updated.title)」"
            }
        }
    }
}

// MARK: - 子页 2：文风 DNA 与个人背景知识卡

private struct AIStyleAndContextView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showCloner = false
    @State private var showNewCard = false
    @State private var editingCard: PersonalContextCard?
    @State private var newBanned = ""
    @State private var newCatchphrase = ""
    @State private var feedback: String?

    var body: some View {
        List {
            Section("文风 DNA") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.aiConfig.styleDNA.clonedStyleSummary.isEmpty ? "尚未克隆个人文风" : "已提取文风 DNA")
                            .font(.subheadline.bold())
                        Text(appState.aiConfig.styleDNA.clonedStyleSummary.isEmpty
                             ? "粘贴 3~5 句真实消息，让 AI 更像你"
                             : appState.aiConfig.styleDNA.clonedStyleSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    Spacer()
                    Button(appState.aiConfig.styleDNA.clonedStyleSummary.isEmpty ? "克隆" : "重克") {
                        showCloner = true
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color(Design.Palette.accent))
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }

                Toggle("自动去除生硬 AI 腔", isOn: $appState.aiConfig.styleDNA.removeAIClicheEnabled)

                if let fb = feedback {
                    Text(fb).font(.caption).foregroundStyle(Color(Design.Palette.success))
                }
            }

            Section("禁用 AI 腔词条") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(appState.aiConfig.styleDNA.bannedAICliches, id: \.self) { w in
                            Button {
                                appState.aiConfig.styleDNA.bannedAICliches.removeAll { $0 == w }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(w)
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .font(.caption2.bold())
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color(Design.Palette.error).opacity(0.12))
                                .foregroundStyle(Color(Design.Palette.error))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("新增禁用词（如：赋能）", text: $newBanned).font(.subheadline)
                    Button("添加") {
                        let w = newBanned.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !w.isEmpty && !appState.aiConfig.styleDNA.bannedAICliches.contains(w) {
                            appState.aiConfig.styleDNA.bannedAICliches.insert(w, at: 0)
                            newBanned = ""
                        }
                    }
                    .font(.caption.bold())
                    .disabled(newBanned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("个人口癖与人设") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(appState.aiConfig.styleDNA.personalCatchphrases, id: \.self) { phrase in
                            Button {
                                appState.aiConfig.styleDNA.personalCatchphrases.removeAll { $0 == phrase }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(phrase)
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .font(.caption2.bold())
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color(Design.Palette.accentSoft))
                                .foregroundStyle(Color(Design.Palette.accent))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("新增口癖（如：收到啦～）", text: $newCatchphrase).font(.subheadline)
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
                TextField("全局人设补充（可选）", text: $appState.aiConfig.customPersonaPrompt, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.subheadline)

                if !appState.aiConfig.styleDNA.learnedDiffRules.isEmpty {
                    ForEach(appState.aiConfig.styleDNA.learnedDiffRules, id: \.self) { rule in
                        Text("✓ \(rule)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if appState.aiConfig.contextCards.isEmpty {
                    Text("可存入岗位、业务口径，调用 AI 时自动挂载")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.aiConfig.contextCards) { card in
                        HStack {
                            Button {
                                editingCard = card
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.title).font(.subheadline.bold()).foregroundStyle(.primary)
                                    Text(card.content).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                Button {
                    showNewCard = true
                } label: {
                    Label("新增背景知识卡", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold())
                }
            } header: {
                Text("背景知识卡 (\(appState.aiConfig.contextCards.filter(\.isEnabled).count) 启用)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("文风 DNA 与知识卡")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCloner) {
            StyleDNAClonerSheet { samples in
                _ = await appState.cloneStyleDNA(fromSamples: samples)
                feedback = "✓ 文风 DNA 已更新"
            }
        }
        .sheet(isPresented: $showNewCard) {
            ContextCardEditorSheet(initial: nil) { created in
                appState.upsertContextCard(created)
            }
        }
        .sheet(item: $editingCard) { card in
            ContextCardEditorSheet(initial: card) { updated in
                appState.upsertContextCard(updated)
            }
        }
    }
}

// MARK: - 子页 3：智能画像诊断

private struct AIAutoInsightView: View {
    @EnvironmentObject private var appState: AppState
    @State private var feedback: String?

    var body: some View {
        List {
            Section {
                Button {
                    Task {
                        let report = await appState.runAIAutoAnalysis()
                        await MainActor.run {
                            feedback = "✓ 已生成「\(report.personaTitle)」"
                        }
                    }
                } label: {
                    HStack {
                        if appState.isRunningAIInsight {
                            ProgressView().padding(.trailing, 4)
                        } else {
                            Image(systemName: "sparkles").foregroundStyle(Color(Design.Palette.accent))
                        }
                        Text(appState.isRunningAIInsight ? "分析中…" : "立即生成专属打字画像")
                            .font(.subheadline.bold())
                    }
                }
                .disabled(appState.isRunningAIInsight)

                if let fb = feedback {
                    Text(fb).font(.caption).foregroundStyle(Color(Design.Palette.success))
                }
            }

            if let report = appState.aiInsightReport {
                Section("诊断摘要") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(report.personaTitle).font(.headline)
                            Spacer()
                            Text(report.sourceLabel).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(report.styleSummary).font(.caption).foregroundStyle(.primary)
                        if !report.efficiencyDiagnosis.isEmpty {
                            Text(report.efficiencyDiagnosis).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !report.recommendedPersonaPrompt.isEmpty {
                        Button("一键应用推荐人设") {
                            appState.aiConfig.customPersonaPrompt = report.recommendedPersonaPrompt
                            feedback = "✓ 已应用人设"
                        }
                        .font(.subheadline.bold())
                    }
                    if !report.suggestedFuzzyKeys.isEmpty {
                        Button("一键开启推荐模糊音（\(report.suggestedFuzzyKeys.map(AIAutoInsightService.fuzzyDisplayName(for:)).joined(separator: "/"))）") {
                            let n = appState.applySuggestedFuzzyKeys(report.suggestedFuzzyKeys)
                            feedback = n > 0 ? "✓ 已开启 \(n) 项模糊音" : "推荐模糊音已全部开启"
                        }
                        .font(.subheadline.bold())
                    }
                }

                if !report.suggestedPrompts.isEmpty {
                    Section {
                        ForEach(report.suggestedPrompts) { tpl in
                            let added = appState.aiConfig.customPrompts.contains(where: { $0.title == tpl.title })
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tpl.title).font(.subheadline.bold())
                                    Text(tpl.instruction).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button(added ? "已装" : "装入") {
                                    _ = appState.importSuggestedPrompts([tpl])
                                    feedback = "✓ 已装入「\(tpl.title)」"
                                }
                                .font(.caption.bold())
                                .disabled(added)
                            }
                        }
                    } header: {
                        HStack {
                            Text("定制技能 (\(report.suggestedPrompts.count))")
                            Spacer()
                            Button("全部装入") {
                                let n = appState.importSuggestedPrompts(report.suggestedPrompts)
                                feedback = n > 0 ? "✓ 已装入 \(n) 条" : "均已在键盘栏中"
                            }
                            .font(.caption.bold())
                        }
                    }
                }

                if !report.suggestedPhrases.isEmpty {
                    Section {
                        ForEach(report.suggestedPhrases) { p in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.caption.bold())
                                Text(p.content).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        HStack {
                            Text("推荐短语")
                            Spacer()
                            Button("一键导入") {
                                let n = appState.importSuggestedPhrases(report.suggestedPhrases)
                                feedback = n > 0 ? "✓ 已导入 \(n) 条短语" : "短语均已存在"
                            }
                            .font(.caption.bold())
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("智能画像诊断")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 子页 4：生成历史与用量账本

private struct AIHistoryAndUsageView: View {
    @EnvironmentObject private var appState: AppState
    @State private var recentHistory: [AIRecentResultItem] = []
    @State private var feedback: String?

    var body: some View {
        let entries = appState.aiUsageLedger
        let avgTTFT = entries.isEmpty ? 0 : entries.reduce(0) { $0 + $1.ttftMs } / entries.count
        let totalOut = entries.reduce(0) { $0 + $1.outputChars }

        List {
            Section("用量概览") {
                LabeledContent("累计调用", value: "\(entries.count) 次")
                LabeledContent("平均首字延迟", value: avgTTFT > 0 ? "\(avgTTFT) ms" : "--")
                LabeledContent("累计生成", value: "\(totalOut) 字（省 \(max(0, totalOut / 38)) 分钟）")
                if !entries.isEmpty {
                    Button("清空账本", role: .destructive) {
                        appState.clearAIUsageLedger()
                    }
                }
            }

            if let fb = feedback {
                Section {
                    Text(fb).font(.caption).foregroundStyle(Color(Design.Palette.success))
                }
            }

            Section("最近键盘生成 (\(recentHistory.count))") {
                if recentHistory.isEmpty {
                    Text("在键盘使用 AI 或 @ai 指令后，最近 12 条结果会自动留存在此。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentHistory) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.title)
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(Design.Palette.accent))
                                Spacer()
                                Text(item.createdAt, style: .time)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.output)
                                .font(.subheadline)
                                .lineLimit(3)
                            HStack(spacing: 14) {
                                Button("复制") {
                                    UIPasteboard.general.string = item.output
                                    feedback = "✓ 已复制"
                                }
                                Button("存短语") {
                                    appState.addQuickPhrase(title: String(item.title.prefix(8)), content: item.output, category: "AI收藏")
                                    feedback = "✓ 已存为短语"
                                }
                            }
                            .font(.caption.bold())
                            .foregroundStyle(Color(Design.Palette.accent))
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                    Button("清空历史", role: .destructive) {
                        AIRecentHistoryStore.clear()
                        recentHistory = []
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("历史与用量")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            recentHistory = AIRecentHistoryStore.load()
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
                Section("手动输入模型 ID") {
                    HStack {
                        TextField("输入任意模型 ID…", text: $manualModelID)
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
                    TextField("搜索模型…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("仅看思考模型 (🧠)", isOn: $thinkingOnly)
                }

                Section("远端模型 (\(filtered.count))") {
                    if filtered.isEmpty {
                        Text("无匹配模型，可点右上角刷新或在上方手动输入。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { item in
                            Button {
                                onSelect(item.id)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(item.id)
                                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.primary)
                                            if item.supportsThinking {
                                                Text("🧠")
                                                    .font(.caption2)
                                            }
                                        }
                                        if let ctx = item.contextLength, ctx > 0 {
                                            Text("\(ctx >= 1000 ? "\(ctx / 1000)K" : "\(ctx)") 上下文")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
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
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await onRefresh() } } label: {
                        if isFetching { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(isFetching)
                }
            }
        }
    }
}

// MARK: - Live AI 试炼场 & 双模型 Arena PK Sheet

private struct AIPlaygroundAndArenaSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var tab = 0
    @State private var inputText = "领导说周六临时加班，但我家里约好了聚餐，帮我委婉回复。"
    @State private var thoughtText = ""
    @State private var answerText = ""
    @State private var showThought = false
    @State private var isRunning = false
    @State private var statusMetrics = ""

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
                    Picker("模式", selection: $tab) {
                        Text("流式试炼").tag(0)
                        Text("双模型 PK").tag(1)
                    }
                    .pickerStyle(.segmented)

                    TextEditor(text: $inputText)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if tab == 0 {
                        singlePlaygroundBody
                    } else {
                        arenaPKBody
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI 试炼场")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
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
                Text(appState.aiConfig.activeModelName).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Text("思考 \(appState.aiConfig.thinkingMode.shortBadge)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(Design.Palette.accentSoft))
                    .foregroundStyle(Color(Design.Palette.accent))
                    .clipShape(Capsule())
            }

            Button {
                Task { await runSingleTest() }
            } label: {
                HStack {
                    if isRunning { ProgressView().tint(.white) }
                    Text(isRunning ? "推理中…" : "运行测试").font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Color(Design.Palette.accent))
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRunning || !appState.aiConfig.isConfigured)

            if !statusMetrics.isEmpty {
                Text(statusMetrics).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            if !thoughtText.isEmpty {
                DisclosureGroup("💭 思考 (\(thoughtText.count)字)", isExpanded: $showThought) {
                    Text(thoughtText).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !answerText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("正文").font(.caption.bold()).foregroundStyle(Color(Design.Palette.accent))
                        Spacer()
                        Button("复制") { UIPasteboard.general.string = answerText }.font(.caption.bold())
                    }
                    Text(answerText).font(.body).frame(maxWidth: .infinity, alignment: .leading)
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
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("VS").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("模型 B", text: $modelB)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
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
                    Text(isRunning ? "PK 中…" : "🔥 并排对比").font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Color(Design.Palette.accent))
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRunning || !appState.aiConfig.isConfigured)

            arenaResultCard(label: modelA, metrics: metricsA, output: outA) {
                if appState.aiConfig.provider == .gemini { appState.aiConfig.geminiModel = modelA }
                else { appState.aiConfig.openAIModel = modelA }
            }
            arenaResultCard(label: modelB, metrics: metricsB, output: outB) {
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
                if !metrics.isEmpty { Text(metrics).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                if !output.isEmpty {
                    Button("选用", action: onChoose)
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
        isRunning = true; thoughtText = ""; answerText = ""; statusMetrics = "连接中…"
        let start = Date(); var firstTokenMs: Int?
        defer { isRunning = false }
        do {
            for try await chunk in client.streamEvents(
                prompt: inputText, systemInstruction: AIPresetAction.eqReply.systemPrompt,
                config: appState.aiConfig, featureTag: "playground"
            ) {
                if firstTokenMs == nil { firstTokenMs = Int(Date().timeIntervalSince(start) * 1000) }
                switch chunk {
                case .thought(let t): thoughtText += t
                case .answer(let a): answerText += a
                }
            }
            let totalMs = Int(Date().timeIntervalSince(start) * 1000)
            statusMetrics = "✓ 首字 \(firstTokenMs ?? totalMs)ms · 总 \(totalMs)ms · \(answerText.count)字"
            appState.refreshAll()
        } catch {
            statusMetrics = "失败：\(error.localizedDescription)"
        }
    }

    private func runArenaPK() async {
        isRunning = true; outA = ""; outB = ""; metricsA = "…"; metricsB = "…"
        defer { isRunning = false }
        let baseCfg = appState.aiConfig
        var cfgA = baseCfg; var cfgB = baseCfg
        if baseCfg.provider == .gemini { cfgA.geminiModel = modelA; cfgB.geminiModel = modelB }
        else { cfgA.openAIModel = modelA; cfgB.openAIModel = modelB }
        async let taskA: Void = {
            let s = Date()
            do {
                var acc = ""
                for try await c in client.streamText(prompt: inputText, systemInstruction: AIPresetAction.eqReply.systemPrompt, config: cfgA, featureTag: "arena_a") {
                    acc += c; let snap = acc; await MainActor.run { outA = snap }
                }
                let ms = Int(Date().timeIntervalSince(s) * 1000)
                await MainActor.run { metricsA = "\(ms)ms" }
            } catch {
                await MainActor.run { metricsA = "失败"; outA = error.localizedDescription }
            }
        }()
        async let taskB: Void = {
            let s = Date()
            do {
                var acc = ""
                for try await c in client.streamText(prompt: inputText, systemInstruction: AIPresetAction.eqReply.systemPrompt, config: cfgB, featureTag: "arena_b") {
                    acc += c; let snap = acc; await MainActor.run { outB = snap }
                }
                let ms = Int(Date().timeIntervalSince(s) * 1000)
                await MainActor.run { metricsB = "\(ms)ms" }
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
                Section("粘贴 3~5 条你平时发的真实消息") {
                    TextEditor(text: $samples).frame(minHeight: 150)
                    Button("填入示例") {
                        samples = "收到啦，开完会马上看，有进展同步你～\n哈哈不急，明天碰一下就行。\n刚核对完了，整体没问题，两处细节标文档里了。"
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
                            Text(isCloning ? "提取中…" : "✨ 克隆我的文风").font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(isCloning || samples.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("文风 DNA 克隆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
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
        self.initial = initial; self.onSave = onSave
        _title = State(initialValue: initial?.title ?? "")
        _sceneTag = State(initialValue: initial?.sceneTag ?? "职场")
        _content = State(initialValue: initial?.content ?? "")
        _isEnabled = State(initialValue: initial?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题（如：岗位与汇报口径）", text: $title)
                TextField("标签（职场 / 销售）", text: $sceneTag)
                Toggle("自动挂载", isOn: $isEnabled)
                Section("内容") {
                    TextField("输入背景信息…", text: $content, axis: .vertical).lineLimit(4...8)
                }
            }
            .navigationTitle(initial == nil ? "新增知识卡" : "编辑知识卡")
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
        self.initial = initial; self.onSave = onSave
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
                    TextField("名称（2~6 字）", text: $title)
                    Picker("分类", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("置顶至前排", isOn: $isPinned)
                    Toggle("走深度思考模型", isOn: $useDeepModel)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(icons, id: \.self) { sym in
                            Button { icon = sym } label: {
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

                Section("提示词指令") {
                    TextField("描述 AI 要做什么…", text: $instruction, axis: .vertical).lineLimit(4...8)
                }
            }
            .navigationTitle(initial == nil ? "新建技能" : "编辑技能")
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
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - AI 场景指令市场 Sheet（20 条精选一键装入）

private struct AIPromptMarketplaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingTitles: Set<String>
    let onInstall: ([CustomAIPromptTemplate]) -> Void

    @State private var selectedCategory: String = "全部"
    @State private var searchText: String = ""
    @State private var localAddedTitles: Set<String> = []

    private var allCategories: [String] { ["全部"] + AIPromptMarketplaceCatalog.categories }

    private var filteredTemplates: [CustomAIPromptTemplate] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return AIPromptMarketplaceCatalog.allTemplates.filter { tpl in
            if selectedCategory != "全部" && tpl.category != selectedCategory { return false }
            if q.isEmpty { return true }
            return tpl.title.lowercased().contains(q) || tpl.instruction.lowercased().contains(q)
        }
    }

    private func isInstalled(_ tpl: CustomAIPromptTemplate) -> Bool {
        existingTitles.contains(tpl.title) || localAddedTitles.contains(tpl.title)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("搜索技能（催进度 / 周报 / 朋友圈…）", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(allCategories, id: \.self) { cat in
                                let active = selectedCategory == cat
                                Button(cat) { selectedCategory = cat }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
                                    .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    ForEach(filteredTemplates) { tpl in
                        let added = isInstalled(tpl)
                        HStack(spacing: 10) {
                            Image(systemName: tpl.icon)
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.accent))
                                .frame(width: 26, height: 26)
                                .background(Color(Design.Palette.accentSoft))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(tpl.title).font(.subheadline.bold())
                                    if tpl.useDeepModel {
                                        Text("深度").font(.caption2.bold())
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color(Design.Palette.accentSoft))
                                            .foregroundStyle(Color(Design.Palette.accent))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(tpl.instruction).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 6)
                            Button(added ? "已装" : "装入") {
                                onInstall([tpl])
                                localAddedTitles.insert(tpl.title)
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(added ? Color(Design.Palette.surface) : Color(Design.Palette.accent))
                            .foregroundStyle(added ? Color.secondary : Color.white)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                            .disabled(added)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(selectedCategory) (\(filteredTemplates.count))")
                        Spacer()
                        let pending = filteredTemplates.filter { !isInstalled($0) }
                        if !pending.isEmpty {
                            Button("全部装入 (\(pending.count))") {
                                onInstall(pending)
                                for item in pending { localAddedTitles.insert(item.title) }
                            }
                            .font(.caption.bold())
                            .foregroundStyle(Color(Design.Palette.accent))
                        }
                    }
                }
            }
            .navigationTitle("场景指令市场")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
    }
}
