import SwiftUI
import UIKit

/// 多步 AI 链式流水线工坊（支持分步流式串联执行、自定义编排，以及一键编译为键盘技能）
struct AIPipelineStudioView: View {
    @EnvironmentObject private var appState: AppState
    let onSendToWorkbench: (String) -> Void

    @State private var runningPipeline: AIPromptPipeline?
    @State private var editingPipeline: AIPromptPipeline?
    @State private var showNewEditor = false
    @State private var confirmResetDefaults = false
    @State private var feedback: String?

    var body: some View {
        List {
            Section {
                Button {
                    showNewEditor = true
                } label: {
                    HStack(spacing: 12) {
                        LXIconTile(icon: "plus.circle.fill", size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("新建多步 AI 流水线")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text("串联 2~4 个步骤，上一步输出自动作为下一步输入")
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

            Section {
                ForEach(appState.aiConfig.aiPipelines) { pipeline in
                    pipelineRow(pipeline)
                }
            } header: {
                Text("我的 AI 流水线 · \(appState.aiConfig.aiPipelines.count)")
            } footer: {
                Text("点击「运行」可观看每一步实时串联生成；点「装进键盘」可一键编译为键盘技能随时呼出。")
            }

            Section {
                Button("恢复默认 4 条推荐流水线", role: .destructive) {
                    confirmResetDefaults = true
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI 链式流水线")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($feedback)
        .sheet(item: $runningPipeline) { pipe in
            PipelineRunnerSheet(pipeline: pipe) { draft in
                runningPipeline = nil
                onSendToWorkbench(draft)
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showNewEditor) {
            PipelineEditorSheet(initial: nil) { created in
                appState.aiConfig.aiPipelines.insert(created, at: 0)
                feedback = "已新建流水线「\(created.title)」"
            }
        }
        .sheet(item: $editingPipeline) { pipe in
            PipelineEditorSheet(initial: pipe) { updated in
                if let idx = appState.aiConfig.aiPipelines.firstIndex(where: { $0.id == updated.id }) {
                    appState.aiConfig.aiPipelines[idx] = updated
                    feedback = "已更新「\(updated.title)」"
                }
            }
        }
        .confirmationDialog("恢复默认流水线？", isPresented: $confirmResetDefaults, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) {
                appState.aiConfig.aiPipelines = AIPromptPipeline.defaultPipelines
                feedback = "已恢复默认 4 条推荐流水线"
            }
        } message: {
            Text("自定义编排的流水线会被重置为出厂推荐组合。")
        }
    }

    private func pipelineRow(_ pipe: AIPromptPipeline) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                LXIconTile(icon: pipe.icon, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pipe.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    if !pipe.summary.isEmpty {
                        Text(pipe.summary)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button("运行") {
                    runningPipeline = pipe
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true))
            }

            // 步骤链路可视化胶囊
            LXFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(pipe.steps.enumerated()), id: \.element.id) { idx, st in
                    LXTag(
                        text: "\(idx + 1). \(st.name)",
                        tint: st.preferDeep ? Color(Design.Palette.accent) : Color(Design.Palette.slate),
                        filled: st.preferDeep
                    )
                }
            }

            HStack(spacing: 12) {
                Button {
                    let compiled = pipe.compiledAsCustomPrompt()
                    appState.addOrUpdateCustomPrompt(compiled)
                    feedback = "已将「\(pipe.title)」装入键盘 AI 栏"
                } label: {
                    Label("装进键盘", systemImage: "keyboard.badge.ellipsis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.accent))
                }
                .buttonStyle(.plain)

                Button {
                    editingPipeline = pipe
                } label: {
                    Label("编辑步骤", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.stone))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                appState.aiConfig.aiPipelines.removeAll { $0.id == pipe.id }
                feedback = "已删除流水线「\(pipe.title)」"
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

/// 多步流水线实时执行器 Sheet
struct PipelineRunnerSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let pipeline: AIPromptPipeline
    let onSendToWorkbench: (String) -> Void

    @State private var inputText = "呃那个王总刚才说下周二之前得把新版本演示做完，但咱们后端接口还差两个没联调，我想问问他能不能先演示核心流程，剩下那俩周五补齐。"
    @State private var stepOutputs: [String: String] = [:]
    @State private var stepLatencies: [String: Int] = [:]
    @State private var currentStepIndex: Int? = nil
    @State private var expandedStepIDs: Set<String> = []
    @State private var isRunning = false
    @State private var errorMsg: String?
    @State private var activeTask: Task<Void, Never>?
    @State private var feedback: String?

    private let client = AIClient(timeout: 55)

    private var finalOutput: String {
        guard let last = pipeline.steps.last else { return "" }
        return stepOutputs[last.id] ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LXCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("流水线输入原文")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.stone))
                                Spacer()
                                Button("粘贴") {
                                    if let s = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
                                        inputText = s
                                    }
                                }
                                .font(.caption.bold())
                                .foregroundStyle(Color(Design.Palette.accent))
                                .buttonStyle(.plain)
                            }
                            TextEditor(text: $inputText)
                                .font(.subheadline)
                                .frame(minHeight: 84)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .disabled(isRunning)
                        }
                    }

                    if isRunning {
                        Button {
                            activeTask?.cancel()
                        } label: {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small).tint(Color(Design.Palette.error))
                                Text("正在执行第 \((currentStepIndex ?? 0) + 1) / \(pipeline.steps.count) 步… 停止")
                            }
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
                    } else {
                        Button {
                            runPipeline()
                        } label: {
                            Label("按序运行 \(pipeline.steps.count) 步流水线", systemImage: "play.fill")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                        .disabled(!appState.aiConfig.isConfigured || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let err = errorMsg {
                        Text(err).font(.caption).foregroundStyle(Color(Design.Palette.error))
                    }

                    ForEach(Array(pipeline.steps.enumerated()), id: \.element.id) { idx, step in
                        stepCard(index: idx, step: step, isFinal: idx == pipeline.steps.count - 1)
                    }
                }
                .lxReadableWidth()
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(pipeline.title)
            .navigationBarTitleDisplayMode(.inline)
            .lxToast($feedback)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        activeTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                activeTask?.cancel()
            }
        }
    }

    private func stepCard(index: Int, step: AIPromptPipelineStep, isFinal: Bool) -> some View {
        let out = stepOutputs[step.id] ?? ""
        let isActive = isRunning && currentStepIndex == index
        let isDone = !out.isEmpty && !isActive
        let isExpanded = isFinal || isActive || expandedStepIDs.contains(step.id)

        return LXCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(isDone || isActive ? Color.white : Color(Design.Palette.stone))
                        .frame(width: 22, height: 22)
                        .background(
                            isDone ? Color(Design.Palette.success) : (isActive ? Color(Design.Palette.accent) : Color(Design.Palette.surface)),
                            in: Circle()
                        )
                    Text(step.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    if isFinal {
                        LXTag(text: "最终成品", tint: Color(Design.Palette.accent), filled: true)
                    }
                    Spacer()
                    if isActive {
                        ProgressView().controlSize(.small)
                    } else if let ms = stepLatencies[step.id] {
                        Text("\(ms) ms")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    if !isFinal && !out.isEmpty {
                        Button(isExpanded ? "收起" : "展开") {
                            if expandedStepIDs.contains(step.id) {
                                expandedStepIDs.remove(step.id)
                            } else {
                                expandedStepIDs.insert(step.id)
                            }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.accent))
                        .buttonStyle(.plain)
                    }
                }

                if isExpanded && !out.isEmpty {
                    Text(out)
                        .font(isFinal ? .body : .footnote)
                        .foregroundStyle(isFinal ? Color(Design.Palette.ink) : Color(Design.Palette.charcoal))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else if out.isEmpty {
                    Text(step.instruction)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(2)
                }

                if isFinal && !finalOutput.isEmpty && !isRunning {
                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = finalOutput
                            feedback = "已复制流水线成品"
                        } label: {
                            Label("复制成品", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                        Button {
                            appState.addQuickPhrase(title: String(pipeline.title.prefix(8)), content: finalOutput, category: "流水线")
                            feedback = "已存为快捷短语"
                        } label: {
                            Label("存短语", systemImage: "text.badge.plus")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                        Button {
                            onSendToWorkbench("请帮我微调下面这份「\(pipeline.title)」流水线成果：\n\(finalOutput)")
                        } label: {
                            Label("去微调", systemImage: "bubble.left")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                    }
                }
            }
        }
    }

    private func runPipeline() {
        let seed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !seed.isEmpty, !pipeline.steps.isEmpty else { return }
        let cfg = appState.aiConfig
        stepOutputs = [:]
        stepLatencies = [:]
        errorMsg = nil
        isRunning = true

        activeTask = Task {
            var currentPayload = seed
            defer {
                Task { @MainActor in
                    isRunning = false
                    currentStepIndex = nil
                    appState.refreshAll()
                }
            }
            for (idx, step) in pipeline.steps.enumerated() {
                if Task.isCancelled { break }
                await MainActor.run { currentStepIndex = idx }
                let stepStart = Date()
                var acc = ""
                let stepPrompt = idx == 0
                    ? currentPayload
                    : "【原始需求】\n\(seed)\n\n【上一步输出】\n\(currentPayload)\n\n请基于以上内容执行本步骤。"
                do {
                    for try await d in client.streamText(
                        prompt: stepPrompt,
                        systemInstruction: step.instruction + " 只输出本步结果，不加额外废话。",
                        config: cfg,
                        featureTag: "ai_pipeline",
                        preferFast: step.preferFast,
                        preferDeep: step.preferDeep
                    ) {
                        if Task.isCancelled { break }
                        acc += d
                        let snap = AITextSanitizer.clean(acc, streaming: true)
                        await MainActor.run { stepOutputs[step.id] = snap }
                    }
                    let finalStepOut = AITextSanitizer.clean(acc, streaming: false)
                    let ms = Int(Date().timeIntervalSince(stepStart) * 1000)
                    await MainActor.run {
                        stepOutputs[step.id] = finalStepOut
                        stepLatencies[step.id] = ms
                    }
                    currentPayload = finalStepOut
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run { errorMsg = "第 \(idx + 1) 步「\(step.name)」失败：\(error.localizedDescription)" }
                    }
                    return
                }
            }
            let lastOut = currentPayload
            await MainActor.run {
                if !lastOut.isEmpty {
                    AIRecentHistoryStore.record(title: "流水线 · \(pipeline.title)", output: lastOut, prompt: String(seed.prefix(60)))
                }
            }
        }
    }
}

/// 自定义流水线步骤编排编辑器
struct PipelineEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: AIPromptPipeline?
    let onSave: (AIPromptPipeline) -> Void

    @State private var title: String
    @State private var summary: String
    @State private var icon: String
    @State private var steps: [AIPromptPipelineStep]

    private let icons = ["arrow.triangle.branch", "briefcase.fill", "shield.lefthalf.filled", "sparkles", "doc.text.fill", "checklist", "globe", "camera.filters"]

    init(initial: AIPromptPipeline?, onSave: @escaping (AIPromptPipeline) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _title = State(initialValue: initial?.title ?? "")
        _summary = State(initialValue: initial?.summary ?? "")
        _icon = State(initialValue: initial?.icon ?? "arrow.triangle.branch")
        _steps = State(initialValue: initial?.steps ?? [
            AIPromptPipelineStep(name: "整理提炼", instruction: "提取输入里的核心事实与目标要点。", preferFast: true),
            AIPromptPipelineStep(name: "润色成稿", instruction: "整理为自然得体、可直接发送的成品文案。", preferDeep: false),
        ])
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && steps.count >= 2
            && steps.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("流水线信息") {
                    TextField("名称（如：口述转邮件）", text: $title)
                    TextField("一句话简介（可选）", text: $summary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(icons, id: \.self) { sym in
                                let sel = icon == sym
                                Button {
                                    icon = sym
                                } label: {
                                    Image(systemName: sym)
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 38, height: 38)
                                        .foregroundStyle(sel ? Color.white : Color(Design.Palette.ink))
                                        .background(sel ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                    Section("第 \(idx + 1) 步") {
                        TextField("步骤名（如：去口水词）", text: Binding(
                            get: { steps[idx].name },
                            set: { steps[idx].name = $0 }
                        ))
                        TextField("本步执行指令…", text: Binding(
                            get: { steps[idx].instruction },
                            set: { steps[idx].instruction = $0 }
                        ), axis: .vertical)
                        .lineLimit(2...5)
                        Toggle("本步使用深度模型", isOn: Binding(
                            get: { steps[idx].preferDeep },
                            set: {
                                steps[idx].preferDeep = $0
                                if $0 { steps[idx].preferFast = false }
                            }
                        ))
                        .tint(Color(Design.Palette.accent))
                        if steps.count > 2 {
                            Button("删除此步骤", role: .destructive) {
                                steps.remove(at: idx)
                            }
                        }
                    }
                }

                if steps.count < 4 {
                    Section {
                        Button {
                            steps.append(AIPromptPipelineStep(name: "第 \(steps.count + 1) 步", instruction: ""))
                        } label: {
                            Label("增加一个串联步骤（最多 4 步）", systemImage: "plus.circle.fill")
                                .foregroundStyle(Color(Design.Palette.accent))
                        }
                    }
                }
            }
            .navigationTitle(initial == nil ? "新建流水线" : "编辑流水线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let pipe = AIPromptPipeline(
                            id: initial?.id ?? UUID().uuidString,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            icon: icon,
                            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                            steps: steps
                        )
                        onSave(pipe)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}
