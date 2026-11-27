import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 技能工坊与指令市场（支持 AI 一键帮写、当场试跑、键盘 AI 栏排布管理、14 内置技能详情与技能包 JSON 导入导出）
struct AIPromptsWorkshopView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showMarketplace = false
    @State private var showNewPrompt = false
    @State private var showKeyboardLayout = false
    @State private var editingPrompt: CustomAIPromptTemplate?
    @State private var inspectingBuiltin: AIPresetAction?
    @State private var showImportPicker = false
    @State private var exportDoc: PromptsJSONDocument?
    @State private var showExporter = false
    @State private var feedback: String?

    private var pinnedPrompts: [CustomAIPromptTemplate] {
        appState.aiConfig.customPrompts.filter(\.isPinned)
    }

    private var otherPrompts: [CustomAIPromptTemplate] {
        appState.aiConfig.customPrompts.filter { !$0.isPinned }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    entryTile(
                        icon: "square.grid.2x2.fill",
                        title: "指令市场",
                        subtitle: "\(AIPromptMarketplaceCatalog.allTemplates.count) 条精选",
                        prominent: true
                    ) {
                        showMarketplace = true
                    }
                    entryTile(
                        icon: "plus",
                        title: "新建技能",
                        subtitle: "支持 AI 帮写",
                        prominent: false
                    ) {
                        showNewPrompt = true
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Button {
                    showKeyboardLayout = true
                } label: {
                    HStack(spacing: 12) {
                        LXIconTile(icon: "keyboard.badge.ellipsis")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("键盘 AI 栏排布管理")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            let builtinN = appState.aiConfig.resolvedKeyboardBuiltinActions.count
                            let customMode = appState.aiConfig.keyboardShowAllCustomPrompts ? "全部自定义" : "仅置顶"
                            Text("当前展示 \(builtinN) 个内置技能 + \(customMode)技能")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if appState.aiConfig.customPrompts.isEmpty {
                Section("我的键盘技能") {
                    LXEmptyState(
                        icon: "wand.and.stars",
                        title: "还没有自定义技能",
                        message: "从指令市场一键装入，或新建一条（支持 AI 自动帮写）。装好的技能会直接出现在键盘 AI 面板里。"
                    )
                }
            } else {
                if !pinnedPrompts.isEmpty {
                    Section {
                        ForEach(pinnedPrompts) { promptRow($0) }
                    } header: {
                        Label("已置顶 · \(pinnedPrompts.count)", systemImage: "pin.fill")
                    }
                }
                if !otherPrompts.isEmpty {
                    Section {
                        ForEach(otherPrompts) { promptRow($0) }
                    } header: {
                        Text(pinnedPrompts.isEmpty ? "我的键盘技能 · \(otherPrompts.count)" : "其他技能 · \(otherPrompts.count)")
                    } footer: {
                        Text(appState.aiConfig.keyboardShowAllCustomPrompts
                             ? "所有已安装技能均会出现在键盘 AI 面板里，置顶项排在最前。点按编辑，左滑置顶或删除。"
                             : "当前设为「键盘仅显示置顶技能」，可在上方「键盘 AI 栏排布管理」调整。")
                    }
                }
            }

            Section {
                LXFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(AIPresetAction.allCases) { act in
                        let enabled = appState.aiConfig.resolvedKeyboardBuiltinActions.contains(act)
                        Button {
                            inspectingBuiltin = act
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: act.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(enabled ? Color(Design.Palette.accent) : Color(Design.Palette.stone))
                                Text(act.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(enabled ? Color(Design.Palette.ink) : Color(Design.Palette.stone))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(enabled ? Color(Design.Palette.accentSoft) : Color(Design.Palette.surface), in: Capsule())
                            .overlay(Capsule().stroke(enabled ? Color.clear : Color(Design.Palette.hairline), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("内置技能 · \(AIPresetAction.allCases.count)（点按可查看、试跑或克隆改写）")
            } footer: {
                Text("高亮芯片表示已启用在键盘 AI 栏中；点任意内置技能可查看指令并试跑。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("键盘技能工坊")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($feedback)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        if let data = appState.aiConfig.exportCustomPromptsJSON() {
                            exportDoc = PromptsJSONDocument(data: data)
                            showExporter = true
                        }
                    } label: {
                        Label("导出我的技能包 (.json)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(appState.aiConfig.customPrompts.isEmpty)

                    Button {
                        showImportPicker = true
                    } label: {
                        Label("导入技能包 (.json)", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("导入导出技能包")
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: .json,
            defaultFilename: "lingxi-ai-skills"
        ) { result in
            switch result {
            case .success:
                feedback = "技能包已导出"
            case .failure(let err):
                if !Self.isUserCancelled(err) {
                    feedback = "导出失败：\(err.localizedDescription)"
                }
            }
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url),
                      let decoded = AIConfig.decodeCustomPromptsJSON(data), !decoded.isEmpty else {
                    feedback = "文件不是有效的灵犀技能包"
                    return
                }
                let added = appState.importSuggestedPrompts(decoded)
                feedback = added > 0 ? "已导入 \(added) 条技能" : "技能包中的条目都已存在"
            case .failure(let err):
                if !Self.isUserCancelled(err) {
                    feedback = "读取文件失败：\(err.localizedDescription)"
                }
            }
        }
        .sheet(isPresented: $showMarketplace) {
            AIPromptMarketplaceSheet(
                existingTitles: Set(appState.aiConfig.customPrompts.map(\.title)),
                onInstall: { templates in
                    let added = appState.importSuggestedPrompts(templates)
                    feedback = added > 0 ? "已装入 \(added) 条技能并同步键盘" : "所选技能已存在"
                }
            )
        }
        .sheet(isPresented: $showNewPrompt) {
            CustomPromptEditorSheet(initial: nil) { created in
                appState.addOrUpdateCustomPrompt(created)
                feedback = "已新建「\(created.title)」"
            }
            .environmentObject(appState)
        }
        .sheet(item: $editingPrompt) { item in
            CustomPromptEditorSheet(initial: item) { updated in
                appState.addOrUpdateCustomPrompt(updated)
                feedback = "已更新「\(updated.title)」"
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showKeyboardLayout) {
            KeyboardAISkillsLayoutSheet()
                .environmentObject(appState)
        }
        .sheet(item: $inspectingBuiltin) { action in
            BuiltinSkillDetailSheet(action: action) { cloned in
                appState.addOrUpdateCustomPrompt(cloned)
                feedback = "已克隆为自定义技能「\(cloned.title)」"
            }
            .environmentObject(appState)
        }
    }

    private func entryTile(icon: String, title: String, subtitle: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(prominent ? Color(Design.Palette.accent) : Color(Design.Palette.ink))
                    .frame(width: 34, height: 34)
                    .background(
                        prominent ? Color.white : Color(Design.Palette.surface),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(prominent ? Color.white : Color(Design.Palette.ink))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                prominent ? Color(Design.Palette.accent) : Color(Design.Palette.canvas),
                in: RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                    .stroke(prominent ? Color.clear : Color(Design.Palette.hairline), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func promptRow(_ tpl: CustomAIPromptTemplate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                editingPrompt = tpl
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    LXIconTile(icon: tpl.icon)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(tpl.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .lineLimit(1)
                            if tpl.useDeepModel {
                                LXTag(text: "深度", icon: "brain", tint: Color(Design.Palette.accent), filled: true)
                            }
                            if tpl.isAIGenerated {
                                LXTag(text: "AI 定制", tint: Color(Design.Palette.success), filled: true)
                            }
                        }
                        Text(tpl.instruction.isEmpty ? "（未填写指令）" : tpl.instruction)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .lineLimit(2)
                        if !tpl.category.isEmpty {
                            LXTag(text: tpl.category)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                togglePin(tpl)
            } label: {
                Image(systemName: tpl.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tpl.isPinned ? Color(Design.Palette.accent) : Color(Design.Palette.muted))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tpl.isPinned ? "取消置顶" : "置顶")
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(tpl)
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                togglePin(tpl)
            } label: {
                Label(tpl.isPinned ? "取消置顶" : "置顶", systemImage: tpl.isPinned ? "pin.slash" : "pin")
            }
            .tint(Color(Design.Palette.accent))
        }
        .contextMenu {
            Button { editingPrompt = tpl } label: { Label("编辑与试跑", systemImage: "pencil") }
            Button { togglePin(tpl) } label: { Label(tpl.isPinned ? "取消置顶" : "置顶", systemImage: tpl.isPinned ? "pin.slash" : "pin") }
            Button {
                UIPasteboard.general.string = tpl.instruction
                feedback = "已复制指令"
            } label: { Label("复制指令", systemImage: "doc.on.doc") }
            Button(role: .destructive) { delete(tpl) } label: { Label("删除", systemImage: "trash") }
        }
    }

    private func togglePin(_ tpl: CustomAIPromptTemplate) {
        appState.togglePinCustomPrompt(id: tpl.id)
        feedback = tpl.isPinned ? "已取消置顶「\(tpl.title)」" : "已置顶「\(tpl.title)」"
    }

    private func delete(_ tpl: CustomAIPromptTemplate) {
        appState.deleteCustomPrompt(id: tpl.id)
        feedback = "已删除「\(tpl.title)」"
    }

    private static func isUserCancelled(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError
    }
}

/// 键盘 AI 面板技能排布管理 Sheet（决定哪些内置技能与自定义技能出现在键盘里）
struct KeyboardAISkillsLayoutSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var activeSet: [AIPresetAction] {
        appState.aiConfig.resolvedKeyboardBuiltinActions
    }

    var body: some View {
        NavigationStack {
            List {
                Section("键盘 AI 栏实时预览") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            LXTag(text: "截屏识图", icon: "camera")
                            LXTag(text: "场景切换", icon: "theatermasks")
                            ForEach(activeSet) { act in
                                LXTag(text: act.title, icon: act.icon, tint: Color(Design.Palette.accent), filled: true)
                            }
                            ForEach(appState.aiConfig.resolvedKeyboardCustomPrompts.prefix(6)) { tpl in
                                LXTag(text: tpl.title, icon: tpl.isPinned ? "star.fill" : "sparkles")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Toggle(isOn: $appState.aiConfig.keyboardShowAllCustomPrompts) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示全部已装入的自定义技能")
                            Text("关闭后，键盘仅展示标记为「置顶」的自定义技能")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                    }
                    .tint(Color(Design.Palette.accent))
                } header: {
                    Text("自定义技能策略")
                }

                Section {
                    ForEach(AIPresetAction.allCases) { act in
                        let isOn = activeSet.contains(act)
                        HStack(spacing: 12) {
                            LXIconTile(icon: act.icon, tint: isOn ? Color(Design.Palette.accent) : Color(Design.Palette.stone))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(act.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color(Design.Palette.ink))
                                    if act.prefersDeepModel {
                                        LXTag(text: "深度", tint: Color(Design.Palette.accent), filled: true)
                                    }
                                    if act.prefersAppendInsert {
                                        LXTag(text: "追加")
                                    }
                                }
                                Text(act.systemPrompt)
                                    .font(.caption)
                                    .foregroundStyle(Color(Design.Palette.stone))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isOn },
                                set: { enable in toggleBuiltin(act, enable: enable) }
                            ))
                            .labelsHidden()
                            .tint(Color(Design.Palette.accent))
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    HStack {
                        Text("内置 14 项技能开关（已选 \(activeSet.count) 项）")
                        Spacer()
                        Button("恢复推荐") {
                            appState.aiConfig.enabledBuiltinActions = []
                        }
                        .font(.caption.bold())
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("键盘 AI 栏排布")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggleBuiltin(_ action: AIPresetAction, enable: Bool) {
        var current = appState.aiConfig.resolvedKeyboardBuiltinActions.map(\.rawValue)
        if enable {
            if !current.contains(action.rawValue) {
                current.append(action.rawValue)
            }
        } else {
            // 至少保留 1 个内置技能
            if current.count > 1 {
                current.removeAll { $0 == action.rawValue }
            }
        }
        appState.aiConfig.enabledBuiltinActions = current
    }
}

/// 内置技能详情与试跑 / 克隆改写弹窗
struct BuiltinSkillDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let action: AIPresetAction
    let onCloneAsCustom: (CustomAIPromptTemplate) -> Void

    @State private var testInput = "今天太忙了，方案晚点发给你，不好意思啊"
    @State private var testOutput = ""
    @State private var isTesting = false
    @State private var testError: String?

    private let client = AIClient(timeout: 35)

    var body: some View {
        NavigationStack {
            Form {
                Section("技能简介") {
                    HStack(spacing: 12) {
                        LXIconTile(icon: action.icon, size: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.title)
                                .font(.headline)
                            LXFlowLayout(spacing: 6, lineSpacing: 4) {
                                LXTag(text: action.prefersDeepModel ? "偏好深度模型" : "偏好极速模型", tint: Color(Design.Palette.accent), filled: true)
                                if action.prefersAppendInsert { LXTag(text: "续写追加插入") }
                                if action.needsClipboardFallback { LXTag(text: "自动读取剪贴板") }
                            }
                        }
                    }
                    Text(action.systemPrompt)
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("当场试跑") {
                    TextField("输入一句测试文本…", text: $testInput, axis: .vertical)
                        .lineLimit(2...5)
                    Button {
                        runQuickTest()
                    } label: {
                        HStack(spacing: 6) {
                            if isTesting { ProgressView().controlSize(.small) }
                            Text(isTesting ? "正在生成…" : "用当前模型试跑")
                        }
                    }
                    .disabled(isTesting || !appState.aiConfig.isConfigured || testInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let err = testError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.error))
                    }
                    if !testOutput.isEmpty {
                        Text(testOutput)
                            .font(.subheadline)
                            .foregroundStyle(Color(Design.Palette.ink))
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Button {
                        let cloned = CustomAIPromptTemplate(
                            title: "\(action.title)Pro",
                            icon: action.icon,
                            instruction: action.systemPrompt,
                            category: "效率沟通",
                            isAIGenerated: false,
                            isPinned: true,
                            useDeepModel: action.prefersDeepModel
                        )
                        onCloneAsCustom(cloned)
                        dismiss()
                    } label: {
                        Label("克隆为自定义技能（可自由修改提示词）", systemImage: "doc.on.doc.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                }
            }
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func runQuickTest() {
        isTesting = true
        testError = nil
        testOutput = ""
        let cfg = appState.aiConfig
        let input = testInput
        Task {
            var acc = ""
            do {
                for try await delta in client.streamText(
                    prompt: input,
                    systemInstruction: action.systemPrompt,
                    config: cfg,
                    featureTag: action.rawValue,
                    preferFast: !action.prefersDeepModel,
                    preferDeep: action.prefersDeepModel
                ) {
                    acc += delta
                    let snap = AITextSanitizer.clean(acc, streaming: true)
                    await MainActor.run { testOutput = snap }
                }
                let finalText = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    testOutput = finalText
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testError = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }
}

/// 自定义提示词新建 / 编辑弹窗（支持 AI 一键帮写、动态变量插入与当场试跑）
struct CustomPromptEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let initial: CustomAIPromptTemplate?
    let onSave: (CustomAIPromptTemplate) -> Void

    @State private var title: String
    @State private var category: String
    @State private var icon: String
    @State private var instruction: String
    @State private var isPinned: Bool
    @State private var useDeepModel: Bool

    // AI 帮写技能
    @State private var aiGoalText = ""
    @State private var isAuthoring = false
    @State private var authoringError: String?

    // 当场试跑
    @State private var showDryRun = false
    @State private var dryRunInput = "下午三点开会同步进度，大家提前看下文档"
    @State private var dryRunOutput = ""
    @State private var isDryRunning = false
    @State private var dryRunError: String?

    private static let titleLimit = 10
    private let categories = ["效率沟通", "职场商务", "链式流水线", "日常社交", "学习创作", "AI 自动定制"]
    private let icons = [
        "sparkles", "briefcase.fill", "bolt.fill", "doc.text.fill",
        "bubble.left.and.text.bubble.right.fill", "globe", "checklist",
        "hand.raised.fill", "arrow.triangle.branch", "lightbulb.fill"
    ]
    private static let quickVars = ["{{剪贴板}}", "{{当前城市}}", "{{日期}}", "{{时间}}"]

    private let client = AIClient(timeout: 35)

    init(initial: CustomAIPromptTemplate?, onSave: @escaping (CustomAIPromptTemplate) -> Void) {
        self.initial = initial; self.onSave = onSave
        _title = State(initialValue: initial?.title ?? "")
        _category = State(initialValue: initial?.category ?? "效率沟通")
        _icon = State(initialValue: initial?.icon ?? "sparkles")
        _instruction = State(initialValue: initial?.instruction ?? "")
        _isPinned = State(initialValue: initial?.isPinned ?? true)
        _useDeepModel = State(initialValue: initial?.useDeepModel ?? false)
    }

    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanInstruction: String { instruction.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                // AI 帮写技能区
                Section {
                    TextField("说一句你想做的事，如：把杂乱口语整理成发给客户的跟进邮件", text: $aiGoalText, axis: .vertical)
                        .lineLimit(2...4)
                    Button {
                        generateSkillWithAI()
                    } label: {
                        HStack(spacing: 6) {
                            if isAuthoring {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text(isAuthoring ? "正在设计提示词…" : "AI 一键帮我写技能")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isAuthoring || !appState.aiConfig.isConfigured || aiGoalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let err = authoringError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.error))
                    }
                } header: {
                    Text("AI 帮写（可选）")
                }

                // 实时预览
                Section("预览") {
                    HStack(spacing: 12) {
                        LXIconTile(icon: icon, size: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(cleanTitle.isEmpty ? "技能名称" : String(cleanTitle.prefix(Self.titleLimit)))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(cleanTitle.isEmpty ? Color(Design.Palette.muted) : Color(Design.Palette.ink))
                            LXFlowLayout(spacing: 6, lineSpacing: 4) {
                                LXTag(text: category)
                                if useDeepModel {
                                    LXTag(text: "深度", icon: "brain", tint: Color(Design.Palette.accent), filled: true)
                                }
                                if isPinned {
                                    LXTag(text: "置顶", icon: "pin.fill", tint: Color(Design.Palette.accent), filled: true)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }

                Section("基本信息") {
                    HStack {
                        TextField("名称（2~6 字最佳）", text: $title)
                        Text("\(cleanTitle.count)/\(Self.titleLimit)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(cleanTitle.count > Self.titleLimit ? Color(Design.Palette.warning) : Color(Design.Palette.stone))
                    }
                    Picker("分类", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("置顶至前排", isOn: $isPinned)
                        .tint(Color(Design.Palette.accent))
                    Toggle(isOn: $useDeepModel) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("使用深度思考模型")
                            Text("更聪明但更慢，适合分析、策略类任务")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                    }
                    .tint(Color(Design.Palette.accent))
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                        ForEach(icons, id: \.self) { sym in
                            let selected = icon == sym
                            Button {
                                icon = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(selected ? Color.white : Color(Design.Palette.ink))
                                    .background(
                                        selected ? Color(Design.Palette.accent) : Color(Design.Palette.surface),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    TextField("描述 AI 要做什么…", text: $instruction, axis: .vertical)
                        .lineLimit(5...10)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Self.quickVars, id: \.self) { token in
                                Button("+ \(token)") {
                                    instruction += (instruction.isEmpty ? "" : " ") + token
                                }
                                .font(.caption.monospaced())
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(Color(Design.Palette.surface), in: Capsule())
                                .foregroundStyle(Color(Design.Palette.accent))
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("提示词指令")
                        Spacer()
                        Text("\(instruction.count) 字")
                            .monospacedDigit()
                    }
                } footer: {
                    Text("支持插入动态变量（如 {{当前城市}} / {{日期}}），调用时自动替换为实时上下文。")
                }

                Section {
                    DisclosureGroup("当场试跑这条技能", isExpanded: $showDryRun) {
                        TextField("输入一句测试文本…", text: $dryRunInput, axis: .vertical)
                            .lineLimit(2...4)
                        Button {
                            runDryTest()
                        } label: {
                            HStack(spacing: 6) {
                                if isDryRunning { ProgressView().controlSize(.small) }
                                Text(isDryRunning ? "正在试跑…" : "运行试跑")
                            }
                        }
                        .disabled(isDryRunning || cleanInstruction.isEmpty || !appState.aiConfig.isConfigured)

                        if let err = dryRunError {
                            Text(err).font(.caption).foregroundStyle(Color(Design.Palette.error))
                        }
                        if !dryRunOutput.isEmpty {
                            Text(dryRunOutput)
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle(initial == nil ? "新建技能" : "编辑技能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard !cleanTitle.isEmpty, !cleanInstruction.isEmpty else { return }
                        let tpl = CustomAIPromptTemplate(
                            id: initial?.id ?? UUID().uuidString,
                            title: String(cleanTitle.prefix(Self.titleLimit)),
                            icon: icon,
                            instruction: cleanInstruction,
                            category: category,
                            isAIGenerated: initial?.isAIGenerated ?? !aiGoalText.isEmpty,
                            isPinned: isPinned,
                            useDeepModel: useDeepModel
                        )
                        onSave(tpl)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(cleanTitle.isEmpty || cleanInstruction.isEmpty)
                }
            }
        }
    }

    private func generateSkillWithAI() {
        isAuthoring = true
        authoringError = nil
        let goal = aiGoalText
        let cfg = appState.aiConfig
        Task {
            do {
                let tpl = try await AIAutoInsightService.generateCustomPromptTemplate(fromGoal: goal, config: cfg, client: client)
                await MainActor.run {
                    title = tpl.title
                    icon = tpl.icon
                    if categories.contains(tpl.category) {
                        category = tpl.category
                    }
                    instruction = tpl.instruction
                    useDeepModel = tpl.useDeepModel
                    isAuthoring = false
                }
            } catch {
                await MainActor.run {
                    authoringError = error.localizedDescription
                    isAuthoring = false
                }
            }
        }
    }

    private func runDryTest() {
        isDryRunning = true
        dryRunError = nil
        dryRunOutput = ""
        let sys = CustomAIPromptTemplate(title: cleanTitle, instruction: cleanInstruction, useDeepModel: useDeepModel).effectiveSystemPrompt
        let input = dryRunInput
        let cfg = appState.aiConfig
        Task {
            var acc = ""
            do {
                for try await delta in client.streamText(prompt: input, systemInstruction: sys, config: cfg, featureTag: "custom_prompt", preferDeep: useDeepModel) {
                    acc += delta
                    let snap = AITextSanitizer.clean(acc, streaming: true)
                    await MainActor.run { dryRunOutput = snap }
                }
                let finalOut = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    dryRunOutput = finalOut
                    isDryRunning = false
                }
            } catch {
                await MainActor.run {
                    dryRunError = error.localizedDescription
                    isDryRunning = false
                }
            }
        }
    }
}

/// AI 场景指令市场 Sheet（精选模板预览与一键装入）
struct AIPromptMarketplaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingTitles: Set<String>
    let onInstall: ([CustomAIPromptTemplate]) -> Void

    @State private var selectedCategory: String = "全部"
    @State private var searchText: String = ""
    @State private var onlyDeepModels = false
    @State private var expandedIDs: Set<String> = []
    @State private var localAddedTitles: Set<String> = []
    @State private var feedback: String?

    private var allCategories: [String] { ["全部"] + AIPromptMarketplaceCatalog.categories }

    private var filteredTemplates: [CustomAIPromptTemplate] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return AIPromptMarketplaceCatalog.allTemplates.filter { tpl in
            if selectedCategory != "全部" && tpl.category != selectedCategory { return false }
            if onlyDeepModels && !tpl.useDeepModel { return false }
            if q.isEmpty { return true }
            return tpl.title.lowercased().contains(q) || tpl.instruction.lowercased().contains(q)
        }
    }

    private func isInstalled(_ tpl: CustomAIPromptTemplate) -> Bool {
        existingTitles.contains(tpl.title) || localAddedTitles.contains(tpl.title)
    }

    var body: some View {
        let templates = filteredTemplates
        let pending = templates.filter { !isInstalled($0) }

        return NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(allCategories, id: \.self) { cat in
                                categoryChip(cat)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                    Toggle("仅看深度思考型模板", isOn: $onlyDeepModels)
                        .font(.subheadline)
                        .tint(Color(Design.Palette.accent))
                }

                if templates.isEmpty {
                    Section {
                        LXEmptyState(
                            icon: "magnifyingglass",
                            title: "没有找到相关技能",
                            message: "换个关键词，或关闭筛选条件试试。"
                        )
                    }
                } else {
                    Section {
                        ForEach(templates) { tpl in
                            templateRow(tpl)
                        }
                    } header: {
                        Text("\(selectedCategory) · \(templates.count) 条（点按展开完整指令）")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索技能（催进度 / 周报 / 朋友圈…）"
            )
            .autocorrectionDisabled()
            .safeAreaInset(edge: .bottom) {
                if pending.count > 1 {
                    Button {
                        onInstall(pending)
                        for item in pending { localAddedTitles.insert(item.title) }
                        feedback = "已装入 \(pending.count) 条技能"
                    } label: {
                        Label("全部装入 · \(pending.count) 条", systemImage: "square.and.arrow.down.on.square")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                }
            }
            .lxToast($feedback)
            .navigationTitle("场景指令市场")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func categoryChip(_ cat: String) -> some View {
        let active = selectedCategory == cat
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selectedCategory = cat }
        } label: {
            Text(cat)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.canvas), in: Capsule())
                .overlay(Capsule().stroke(active ? Color.clear : Color(Design.Palette.hairline), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func templateRow(_ tpl: CustomAIPromptTemplate) -> some View {
        let added = isInstalled(tpl)
        let expanded = expandedIDs.contains(tpl.id)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                if expanded { expandedIDs.remove(tpl.id) } else { expandedIDs.insert(tpl.id) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    LXIconTile(icon: tpl.icon)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(tpl.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .lineLimit(1)
                            if tpl.useDeepModel {
                                LXTag(text: "深度", icon: "brain", tint: Color(Design.Palette.accent), filled: true)
                            }
                        }
                        Text(tpl.instruction)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .lineLimit(expanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        if selectedCategory == "全部" && !tpl.category.isEmpty {
                            LXTag(text: tpl.category)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onInstall([tpl])
                localAddedTitles.insert(tpl.title)
                feedback = "已装入「\(tpl.title)」"
            } label: {
                if added {
                    Label("已装入", systemImage: "checkmark")
                } else {
                    Text("装入")
                }
            }
            .buttonStyle(LXCapsuleButtonStyle(prominent: !added))
            .disabled(added)
        }
        .padding(.vertical, 4)
    }
}

/// FileDocument 封装：导出自定义技能包 JSON
struct PromptsJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
