import SwiftUI

/// 模型指派目标（主模型 / 快模型 / 深模型 / 视觉模型）
enum AIModelAssignTarget: String, Identifiable {
    case primary, fast, deep, vision
    var id: String { rawValue }
    var title: String {
        switch self {
        case .primary: return "选择主模型"
        case .fast: return "选择快模型"
        case .deep: return "选择深度模型"
        case .vision: return "选择视觉模型"
        }
    }
}

/// 远端模型搜索选择 Sheet（支持全部 / 对话 / 思考 / 视觉四维筛选，完整多行展示绝不截断）
struct AIModelPickerSheet: View {
    enum CategoryFilter: Int, CaseIterable, Identifiable {
        case all = 0
        case chat = 1
        case thinking = 2
        case vision = 3
        var id: Int { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    let title: String
    let models: [AIModelInfo]
    let currentModel: String
    let provider: AIProvider
    let isFetching: Bool
    let fetchError: String?
    let onRefresh: () async -> Void
    let onSelect: (String) -> Void

    @State private var query = ""
    @State private var manualModelID = ""
    @State private var categoryFilter: CategoryFilter = .all

    private var chatCount: Int { models.filter(\.isChatModel).count }
    private var thinkingCount: Int { models.filter(\.supportsThinking).count }
    private var visionCount: Int {
        models.filter { ScreenshotOCRService.modelLikelySupportsVision(modelID: $0.id, provider: provider) }.count
    }

    private var trimmedManualID: String {
        manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasError: Bool {
        !(fetchError ?? "").isEmpty
    }

    private var manualFirst: Bool {
        models.isEmpty || hasError
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
            case .vision:
                if !ScreenshotOCRService.modelLikelySupportsVision(modelID: m.id, provider: provider) { return false }
            }
            guard !keywords.isEmpty else { return true }
            let haystack = "\(m.id) \(m.displayName) \(m.ownedBy ?? "")".lowercased()
            return keywords.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !currentModel.isEmpty {
                    Section("当前使用") {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(Color(Design.Palette.accent))
                            Text(currentModel)
                                .font(.footnote.weight(.semibold).monospaced())
                                .foregroundStyle(Color(Design.Palette.ink))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if let err = fetchError, !err.isEmpty {
                    errorSection(err)
                }

                if manualFirst {
                    manualSection
                }

                Section {
                    if !models.isEmpty {
                        Picker("模型分类", selection: $categoryFilter) {
                            Text("全部 \(models.count)").tag(CategoryFilter.all)
                            Text("对话 \(chatCount)").tag(CategoryFilter.chat)
                            Text("思考 \(thinkingCount)").tag(CategoryFilter.thinking)
                            Text("视觉 \(visionCount)").tag(CategoryFilter.vision)
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }

                    if isFetching && models.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在拉取全部远端模型…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else if filtered.isEmpty {
                        VStack(spacing: 10) {
                            LXEmptyState(
                                icon: models.isEmpty ? "tray" : "magnifyingglass",
                                title: models.isEmpty ? "还没有模型列表" : "没有匹配的模型",
                                message: models.isEmpty
                                    ? "下拉或点右上角刷新；也可以手动输入模型 ID。"
                                    : "换个关键词试试，或切回「全部」。"
                            )
                            if models.isEmpty && !hasError {
                                Button("重新拉取") {
                                    Task { await onRefresh() }
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                                .disabled(isFetching)
                                .padding(.bottom, 8)
                            }
                        }
                    } else {
                        ForEach(filtered) { item in
                            modelRow(item)
                        }
                    }
                } header: {
                    Text(models.isEmpty ? "远端模型" : "远端模型 · 显示 \(filtered.count) / \(models.count)")
                }

                if !manualFirst {
                    manualSection
                }
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索模型，空格分隔多个关键词"
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
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
                    .accessibilityLabel("刷新模型列表")
                }
            }
        }
    }

    private var manualSection: some View {
        Section {
            HStack(alignment: .center, spacing: 8) {
                TextField("输入或粘贴完整模型 ID…", text: $manualModelID, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                Button("使用") {
                    guard !trimmedManualID.isEmpty else { return }
                    onSelect(trimmedManualID)
                    dismiss()
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                .disabled(trimmedManualID.isEmpty)
            }
            .frame(minHeight: 36)
        } header: {
            Text("手动输入模型 ID")
        } footer: {
            Text("列表里找不到时，直接填写服务商文档里的模型 ID。")
        }
    }

    private func errorSection(_ err: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(Design.Palette.error))
                VStack(alignment: .leading, spacing: 8) {
                    Text("拉取模型失败")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重试") {
                        Task { await onRefresh() }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, tint: Color(Design.Palette.error)))
                    .disabled(isFetching)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func modelRow(_ item: AIModelInfo) -> some View {
        let selected = item.id == currentModel
        let ctx = item.contextLength ?? 0
        let owner = item.ownedBy ?? ""
        let isVision = ScreenshotOCRService.modelLikelySupportsVision(modelID: item.id, provider: provider)
        return Button {
            onSelect(item.id)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.id)
                        .font(.footnote.weight(.semibold).monospaced())
                        .foregroundStyle(Color(Design.Palette.ink))
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    if !item.displayName.isEmpty && item.displayName != item.id {
                        Text(item.displayName)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if item.supportsThinking || isVision || !item.isChatModel || ctx > 0 || !owner.isEmpty {
                        LXFlowLayout(spacing: 6, lineSpacing: 4) {
                            if item.supportsThinking {
                                LXTag(text: "思考", icon: "brain", tint: Color(Design.Palette.accent), filled: true)
                            }
                            if isVision {
                                LXTag(text: "视觉", icon: "eye", tint: Color(Design.Palette.success), filled: true)
                            }
                            if !item.isChatModel {
                                LXTag(text: "非对话 / 专用", tint: Color(Design.Palette.warning), filled: true)
                            }
                            if ctx > 0 {
                                LXTag(text: "\(ctx >= 1000 ? "\(ctx / 1000)K" : "\(ctx)") 上下文")
                            }
                            if !owner.isEmpty {
                                Text(owner)
                                    .font(.caption2)
                                    .foregroundStyle(Color(Design.Palette.stone))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Color(Design.Palette.accent) : Color(Design.Palette.hairline))
                    .padding(.top, 1)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? Color(Design.Palette.accentSoft) : nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 自定义 HTTP Headers 管理弹窗（适配 OpenRouter、自建网关、CF Access 等鉴权与路由 Header）
struct AICustomHeadersSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onMessage: (String) -> Void

    @State private var newKey = ""
    @State private var newValue = ""

    private var sortedKeys: [String] {
        appState.aiConfig.customHeaders.keys.sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("快捷预设") {
                    Button {
                        appState.aiConfig.customHeaders["HTTP-Referer"] = "https://lingxi.ime"
                        appState.aiConfig.customHeaders["X-Title"] = "Lingxi IME"
                        onMessage("已添加 OpenRouter 推荐 Header")
                    } label: {
                        Label("填入 OpenRouter 标识 Header", systemImage: "sparkles")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                }

                Section("新增 Header") {
                    TextField("Header 名称（如 X-Custom-Auth）", text: $newKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    TextField("Header 值", text: $newValue)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    Button("添加") {
                        let k = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !k.isEmpty, !v.isEmpty else { return }
                        appState.aiConfig.customHeaders[k] = v
                        newKey = ""
                        newValue = ""
                        onMessage("已添加 Header：\(k)")
                    }
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("已配置（\(sortedKeys.count)）") {
                    if sortedKeys.isEmpty {
                        LXEmptyState(
                            icon: "network",
                            title: "暂无自定义 Header",
                            message: "大部分官方接口无需设置；使用中转网关、OpenRouter 或私有代理时可按需添加。"
                        )
                    } else {
                        ForEach(sortedKeys, id: \.self) { k in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(k)
                                    .font(.footnote.weight(.semibold).monospaced())
                                    .foregroundStyle(Color(Design.Palette.ink))
                                Text(appState.aiConfig.customHeaders[k] ?? "")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Color(Design.Palette.stone))
                                    .lineLimit(2)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    appState.aiConfig.customHeaders.removeValue(forKey: k)
                                    onMessage("已删除 Header：\(k)")
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("自定义 HTTP Headers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

/// 渠道档案集中管理弹窗（查看四路模型与 Header、切换或二次确认删除）
struct AIProfileManagerSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onMessage: (String) -> Void

    @State private var deletingProfile: AIProviderProfile?

    var body: some View {
        NavigationStack {
            List {
                if appState.aiConfig.profiles.isEmpty {
                    LXEmptyState(
                        icon: "bookmark.slash",
                        title: "暂无渠道档案",
                        message: "在「AI 智脑」展开高级区点击「存为新档案」，即可保存多套服务商配置随时秒切或跨渠道 PK。"
                    )
                } else {
                    ForEach(appState.aiConfig.profiles) { prof in
                        let isCurrent = appState.aiConfig.activeProfileID == prof.id
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(prof.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color(Design.Palette.ink))
                                    if isCurrent {
                                        LXTag(text: "当前", tint: Color(Design.Palette.success), filled: true)
                                    }
                                }
                                Text("\(prof.provider.shortName) · \(prof.model)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Color(Design.Palette.stone))
                                Text(prof.baseURL)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(Color(Design.Palette.stone))
                                    .lineLimit(1)
                                LXFlowLayout(spacing: 6, lineSpacing: 4) {
                                    if !prof.fastModel.isEmpty { LXTag(text: "快: \(prof.fastModel)") }
                                    if !prof.deepModel.isEmpty { LXTag(text: "深: \(prof.deepModel)") }
                                    if !prof.visionModel.isEmpty { LXTag(text: "视觉: \(prof.visionModel)") }
                                    if !prof.customHeaders.isEmpty { LXTag(text: "\(prof.customHeaders.count) Headers") }
                                }
                            }
                            Spacer()
                            if !isCurrent {
                                Button("启用") {
                                    appState.aiConfig.activateProfile(prof)
                                    onMessage("已切至「\(prof.name)」")
                                    dismiss()
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deletingProfile = prof
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("渠道档案管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "删除渠道档案「\(deletingProfile?.name ?? "")」？",
                isPresented: Binding(
                    get: { deletingProfile != nil },
                    set: { if !$0 { deletingProfile = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let p = deletingProfile {
                        appState.aiConfig.profiles.removeAll { $0.id == p.id }
                        if appState.aiConfig.activeProfileID == p.id {
                            appState.aiConfig.activeProfileID = nil
                        }
                        onMessage("已删除档案「\(p.name)」")
                        deletingProfile = nil
                    }
                }
            } message: {
                Text("删除后需重新填写该渠道的 Key 与模型配置。")
            }
        }
    }
}
