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
    @State private var isSyncingBridge = false
    @State private var modelFetchError: String?

    private let client = AIClient()

    /// 判断当前已拉取模型缓存是否与当前协议 + 接口地址一致
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.showPermissionsCenter = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: appState.isKeyboardFullAccessConfirmed ? "checkmark.shield.fill" : "lock.open.fill")
                                .font(.caption.bold())
                            Text("权限")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(appState.isKeyboardFullAccessConfirmed ? Color(Design.Palette.success) : Color.orange)
                    }
                }
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
                    models: hasFreshModelsForCurrentSource ? appState.aiConfig.fetchedModels : [],
                    currentModel: currentModelFor(target: modelAssignTarget),
                    isFetching: appState.isFetchingAIModels,
                    fetchError: modelFetchError,
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

    // MARK: - 1. 顶部精简状态卡（完整模型名零截断 + 一键权限提示 + 常用服务商快切）

    private var heroStatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(Design.Palette.accent))
                            .frame(width: 40, height: 40)
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.aiConfig.isConfigured ? Color(Design.Palette.success) : Color(Design.Palette.warning))
                                .frame(width: 7, height: 7)
                            Text(appState.aiConfig.isConfigured ? "AI 已就绪" : "待填 API Key")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                        }
                        Text("\(appState.aiConfig.provider == .gemini ? "Gemini" : "OpenAI 兼容") · 思考 \(appState.aiConfig.thinkingMode.shortBadge)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                // 全宽完整模型名展示条（支持长名称自动换行与长按复制，彻底杜绝截断）
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.aiConfig.activeModelName)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color(Design.Palette.surface))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // 键盘 AI 权限 / 免费侧载密钥同步一键引导条
                if !appState.isKeyboardEnabled || !appState.isKeyboardFullAccessConfirmed {
                    Button {
                        appState.showPermissionsCenter = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            Text(!appState.isKeyboardEnabled
                                 ? "尚未启用灵犀键盘 · 点此一键开启权限"
                                 : "键盘 AI 提示无权限？点此一键开启「允许完全访问」")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Text("一键开启")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.11))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if !AppGroup.isAvailable && appState.aiConfig.isConfigured {
                    Button {
                        Task {
                            isSyncingBridge = true
                            defer { isSyncingBridge = false }
                            let res = await appState.copySideloadBridgeTokenAndSync()
                            showStatus(res.message, isError: !res.ok)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isSyncingBridge {
                                ProgressView().scaleEffect(0.75)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(Design.Palette.accent))
                            }
                            Text("免费侧载模式：改完 Key / 模型后点此一键同步给键盘")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Text("同步给键盘")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(Design.Palette.accent))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(Design.Palette.accentSoft))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncingBridge)
                }

                // 常用服务商一键快切（切渠道时同步清理旧渠道模型缓存，防止拉取列表串台）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        providerPill("Gemini", active: appState.aiConfig.provider == .gemini) {
                            applyQuickProviderPreset(provider: .gemini, baseURL: AIConfig.defaultGeminiBaseURL, model: GeminiModelOption.flash25.rawValue)
                        }
                        providerPill("DeepSeek", active: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("deepseek.com")) {
                            applyQuickProviderPreset(provider: .openAICompatible, baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat", deepModel: "deepseek-reasoner")
                        }
                        providerPill("通义千问", active: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("dashscope")) {
                            applyQuickProviderPreset(provider: .openAICompatible, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus")
                        }
                        providerPill("SiliconFlow", active: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("siliconflow")) {
                            applyQuickProviderPreset(provider: .openAICompatible, baseURL: "https://api.siliconflow.cn/v1", model: "deepseek-ai/DeepSeek-V3")
                        }
                        providerPill("OpenRouter", active: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("openrouter")) {
                            applyQuickProviderPreset(provider: .openAICompatible, baseURL: "https://openrouter.ai/api/v1", model: "google/gemini-2.5-flash")
                        }
                        providerPill("Ollama", active: appState.aiConfig.provider == .openAICompatible && appState.aiConfig.openAIBaseURL.contains("11434")) {
                            applyQuickProviderPreset(provider: .openAICompatible, baseURL: "http://127.0.0.1:11434/v1", model: "qwen2.5:7b")
                        }
                    }
                }

                if let msg = statusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color(Design.Palette.error) : Color(Design.Palette.success))
                        .fixedSize(horizontal: false, vertical: true)
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

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("快模型").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if hasFreshModelsForCurrentSource {
                            Button("从列表选") {
                                modelAssignTarget = .fast
                                showModelPicker = true
                            }
                            .font(.caption.bold())
                            .buttonStyle(.plain)
                            .foregroundStyle(Color(Design.Palette.accent))
                        }
                    }
                    TextField("可选（翻译/短回复）", text: $appState.aiConfig.fastModel, axis: .vertical)
                        .lineLimit(1...2)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("深模型").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if hasFreshModelsForCurrentSource {
                            Button("从列表选") {
                                modelAssignTarget = .deep
                                showModelPicker = true
                            }
                            .font(.caption.bold())
                            .buttonStyle(.plain)
                            .foregroundStyle(Color(Design.Palette.accent))
                        }
                    }
                    TextField("可选（军师/分析）", text: $appState.aiConfig.deepModel, axis: .vertical)
                        .lineLimit(1...2)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                }
                .padding(.vertical, 2)

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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("模型")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Button {
                    modelAssignTarget = .primary
                    Task { await triggerFetchModels(openSheetOnSuccess: true) }
                } label: {
                    if appState.isFetchingAIModels {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.7)
                            Text("拉取中…").font(.caption.bold())
                        }
                    } else {
                        Label(hasFreshModelsForCurrentSource ? "刷新列表" : "拉取全部模型", systemImage: "arrow.clockwise")
                            .font(.caption.bold())
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(Design.Palette.accentSoft))
                .foregroundStyle(Color(Design.Palette.accent))
                .clipShape(Capsule())
                .buttonStyle(.plain)
                .disabled(appState.isFetchingAIModels || !appState.aiConfig.isConfigured)

                if hasFreshModelsForCurrentSource {
                    Button {
                        modelAssignTarget = .primary
                        showModelPicker = true
                    } label: {
                        Text("选(\(appState.aiConfig.fetchedModels.count))")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(Design.Palette.accent))
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }

                Button {
                    newProfileName = appState.aiConfig.provider == .gemini ? "Gemini" : "自定义"
                    showSaveProfileAlert = true
                } label: {
                    Image(systemName: "bookmark")
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.accent))
                        .padding(5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保存渠道档案")
            }

            // 独立全宽多行输入框：无论模型名多长（如 Pro/deepseek-ai/DeepSeek-R1-Distill-Qwen-32B）都完整展示零截断
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(Design.Palette.surface))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.vertical, 3)
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

    private func applyQuickProviderPreset(provider: AIProvider, baseURL: String, model: String, deepModel: String? = nil) {
        let oldSourceKey = appState.aiConfig.currentModelsSourceKey
        appState.aiConfig.provider = provider
        if provider == .gemini {
            appState.aiConfig.geminiBaseURL = baseURL
            appState.aiConfig.geminiModel = model
        } else {
            appState.aiConfig.openAIBaseURL = baseURL
            appState.aiConfig.openAIModel = model
            if let deepModel {
                appState.aiConfig.deepModel = deepModel
            }
        }
        if appState.aiConfig.currentModelsSourceKey != oldSourceKey {
            appState.aiConfig.fetchedModels = []
            appState.aiConfig.fetchedModelsSourceKey = ""
            modelFetchError = nil
        }
    }

    private func triggerFetchModels(openSheetOnSuccess: Bool) async {
        modelFetchError = nil
        do {
            let models = try await appState.fetchAvailableAIModels()
            let chatCount = models.filter(\.isChatModel).count
            showStatus("✓ 已拉取全部 \(models.count) 个远端模型（含 \(chatCount) 个对话模型）")
            if openSheetOnSuccess { showModelPicker = true }
        } catch {
            modelFetchError = error.localizedDescription
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

// MARK: - 远端模型搜索选择 Sheet（完整多行展示全部模型 ID 与显示名，绝不截断）

private struct AIModelPickerSheet: View {
    enum CategoryFilter: Int, CaseIterable, Identifiable {
        case all = 0
        case chat = 1
        case thinking = 2
        var id: Int { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    let title: String
    let models: [AIModelInfo]
    let currentModel: String
    let isFetching: Bool
    let fetchError: String?
    let onRefresh: () async -> Void
    let onSelect: (String) -> Void

    @State private var query = ""
    @State private var manualModelID = ""
    @State private var categoryFilter: CategoryFilter = .all

    private var chatCount: Int {
        models.filter(\.isChatModel).count
    }

    private var thinkingCount: Int {
        models.filter(\.supportsThinking).count
    }

    private var filtered: [AIModelInfo] {
        let keywords = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        return models.filter { m in
            switch categoryFilter {
            case .all: break
            case .chat: if !m.isChatModel { return false }
            case .thinking: if !m.supportsThinking { return false }
            }
            guard !keywords.isEmpty else { return true }
            let haystack = "\(m.id) \(m.displayName) \(m.ownedBy ?? "")".lowercased()
            return keywords.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("手动输入任意模型 ID") {
                    HStack(alignment: .center, spacing: 8) {
                        TextField("输入或粘贴完整模型 ID…", text: $manualModelID, axis: .vertical)
                            .lineLimit(1...3)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 13.5, design: .monospaced))
                        Button("使用") {
                            let clean = manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !clean.isEmpty {
                                onSelect(clean)
                                dismiss()
                            }
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(Design.Palette.accentSoft))
                        .foregroundStyle(Color(Design.Palette.accent))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                        .disabled(manualModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("空格分隔多词搜索（如 deepseek r1 / gemini flash）", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Picker("模型分类", selection: $categoryFilter) {
                        Text("全部 (\(models.count))").tag(CategoryFilter.all)
                        Text("对话 (\(chatCount))").tag(CategoryFilter.chat)
                        Text("🧠思考 (\(thinkingCount))").tag(CategoryFilter.thinking)
                    }
                    .pickerStyle(.segmented)
                }

                if let err = fetchError, !err.isEmpty {
                    Section {
                        Text("⚠️ \(err)")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.error))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("远端模型 · 显示 \(filtered.count) / 共 \(models.count) 个") {
                    if isFetching && models.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在分页拉取全部远端模型…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else if filtered.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(models.isEmpty
                                 ? "暂未拉取到远端模型，可点下方按钮或右上角重新拉取。"
                                 : "无匹配模型，可清空搜索词或切回「全部」。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if models.isEmpty {
                                Button("重新拉取全部模型") {
                                    Task { await onRefresh() }
                                }
                                .font(.caption.bold())
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(filtered) { item in
                            Button {
                                onSelect(item.id)
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        // 完整模型 ID：多行自然换行，绝不出现省略号截断
                                        Text(item.id)
                                            .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)

                                        // 如有独立的官方显示名（如 Gemini / OpenRouter 完整名称），另起一行完整展示
                                        if !item.displayName.isEmpty && item.displayName != item.id {
                                            Text(item.displayName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(nil)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }

                                        // 能力与元信息标签行（独立成行，不挤压模型名称宽度）
                                        if item.supportsThinking || !item.isChatModel || (item.contextLength ?? 0) > 0 || (item.ownedBy?.isEmpty == false) {
                                            HStack(spacing: 6) {
                                                if item.supportsThinking {
                                                    Text("🧠 思考")
                                                        .font(.caption2.weight(.semibold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color(Design.Palette.accentSoft))
                                                        .foregroundStyle(Color(Design.Palette.accent))
                                                        .clipShape(Capsule())
                                                }
                                                if !item.isChatModel {
                                                    Text("非对话/专用")
                                                        .font(.caption2.weight(.medium))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.orange.opacity(0.14))
                                                        .foregroundStyle(Color.orange)
                                                        .clipShape(Capsule())
                                                }
                                                if let ctx = item.contextLength, ctx > 0 {
                                                    Text("\(ctx >= 1000 ? "\(ctx / 1000)K" : "\(ctx)") 上下文")
                                                        .font(.caption2.monospacedDigit())
                                                        .foregroundStyle(.secondary)
                                                }
                                                if let owner = item.ownedBy, !owner.isEmpty {
                                                    Text(owner)
                                                        .font(.caption2)
                                                        .foregroundStyle(.tertiary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    if item.id == currentModel {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color(Design.Palette.accent))
                                            .padding(.top, 2)
                                    }
                                }
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .refreshable {
                await onRefresh()
            }
            .task {
                if models.isEmpty && !isFetching {
                    await onRefresh()
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
            HStack(alignment: .top, spacing: 8) {
                Text(appState.aiConfig.activeModelName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
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
            HStack(alignment: .top, spacing: 6) {
                Text(label)
                    .font(.caption.bold())
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
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
