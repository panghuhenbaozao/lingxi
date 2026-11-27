import SwiftUI
import UIKit

/// 动态变量参数化指令工坊（对标 Raycast AI `{{变量}}` 表单引擎）：
/// - 内置 8 套高频参数化专业模板 + 自动识别用户自定义技能中带 `{{变量}}` 的指令；
/// - 枚举选项自动渲染胶囊选择器，文本字段自动预填默认值，内置令牌 `{{当前日期}}/{{当前城市}}/{{剪贴板}}` 自动注入；
/// - 支持一键生成、复制、存短语、送入工作台，以及将当前参数组合一键固化装入键盘 AI 栏。
struct AIParameterizedRunnerView: View {
    @EnvironmentObject private var appState: AppState
    var onOpenInWorkbench: ((String) -> Void)? = nil

    @State private var selectedCategory = "全部"
    @State private var activeTemplate: ParameterizedProTemplate? = nil
    @State private var fieldValues: [String: String] = [:]
    @State private var showRenderedPreview = false
    @State private var outputText = ""
    @State private var isRunning = false
    @State private var runTask: Task<Void, Never>?
    @State private var cachedCityName = ""
    @State private var toastMessage: String?
    @State private var toastIsError = false

    private let client = AIClient(timeout: 55)

    private var userVariableTemplates: [ParameterizedProTemplate] {
        appState.aiConfig.customPrompts.compactMap { tpl in
            let combined = tpl.instruction
            guard PromptVariableEngine.hasInteractiveVariables(in: combined) else { return nil }
            return ParameterizedProTemplate(
                id: "custom_\(tpl.id)",
                title: tpl.title,
                category: "我的技能",
                icon: tpl.icon,
                summary: "来自你的自定义技能（含动态 {{变量}}）",
                systemPrompt: "你是灵犀 AI 助手，请严格按下方已填参数的指令直接输出最终可用正文。",
                userPromptTemplate: combined,
                preferDeep: tpl.useDeepModel
            )
        }
    }

    private var allTemplates: [ParameterizedProTemplate] {
        userVariableTemplates + PromptVariableEngine.featuredTemplates
    }

    private var categories: [String] {
        var cats = ["全部"]
        for t in allTemplates where !cats.contains(t.category) {
            cats.append(t.category)
        }
        return cats
    }

    private var filteredTemplates: [ParameterizedProTemplate] {
        if selectedCategory == "全部" { return allTemplates }
        return allTemplates.filter { $0.category == selectedCategory }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                categoryStrip
                templateListSection
                if let active = activeTemplate {
                    interactiveFormCard(for: active)
                }
            }
            .padding(16)
            .lxReadableWidth()
        }
        .background(Color(Design.Palette.surface).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("参数化变量模板")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toastMessage, isError: toastIsError)
        .onAppear {
            cachedCityName = GeoLocationContext.load().shortCityName
            if activeTemplate == nil, let first = allTemplates.first {
                selectTemplate(first)
            }
        }
        .onDisappear {
            runTask?.cancel()
        }
    }

    private var headerCard: some View {
        LXCard {
            HStack(spacing: 10) {
                LXIconTile(icon: "slider.horizontal.3", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Raycast 级 {{变量}} 动态提示词")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("支持 {{名称|选项1,选项2}} 胶囊快选、{{名称=默认值}} 与 {{当前日期}}/{{当前城市}}/{{剪贴板}} 自动注入。")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let sel = selectedCategory == cat
                    Button(cat) {
                        selectedCategory = cat
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .foregroundStyle(sel ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
                    .background(sel ? Color(Design.Palette.ink) : Color(Design.Palette.canvas), in: Capsule())
                    .overlay(Capsule().stroke(sel ? Color.clear : Color(Design.Palette.hairline), lineWidth: 0.6))
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var templateListSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filteredTemplates) { tpl in
                    let isSelected = activeTemplate?.id == tpl.id
                    Button {
                        selectTemplate(tpl)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: tpl.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isSelected ? Color(Design.Palette.canvas) : Color(Design.Palette.accent))
                                Spacer()
                                Text(tpl.category)
                                    .font(.caption2)
                                    .foregroundStyle(isSelected ? Color(Design.Palette.canvas).opacity(0.8) : Color(Design.Palette.stone))
                            }
                            Text(tpl.title)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(isSelected ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
                                .lineLimit(1)
                            Text(tpl.summary)
                                .font(.caption2)
                                .foregroundStyle(isSelected ? Color(Design.Palette.canvas).opacity(0.85) : Color(Design.Palette.stone))
                                .lineLimit(2)
                        }
                        .frame(width: 168, alignment: .leading)
                        .padding(11)
                        .background(
                            isSelected ? Color(Design.Palette.ink) : Color(Design.Palette.canvas),
                            in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                                .stroke(isSelected ? Color.clear : Color(Design.Palette.hairline), lineWidth: 0.6)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)
                }
            }
        }
    }

    private func interactiveFormCard(for tpl: ParameterizedProTemplate) -> some View {
        let specs = PromptVariableEngine.extractVariables(from: tpl.userPromptTemplate)
        return LXCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(tpl.title)
                        .font(.headline)
                        .foregroundStyle(Color(Design.Palette.ink))
                    Spacer()
                    Button {
                        installAsKeyboardSkill(tpl)
                    } label: {
                        Label("装进键盘", systemImage: "keyboard")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                    .buttonStyle(.plain)
                }

                ForEach(specs) { spec in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(spec.name)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Spacer()
                            if !spec.isChoice {
                                Button("粘贴剪贴板") {
                                    if let clip = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
                                        fieldValues[spec.name] = clip
                                    } else {
                                        showToast("剪贴板为空或受保险箱隐私保护")
                                    }
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.accent))
                                .buttonStyle(.plain)
                            }
                        }

                        if spec.isChoice {
                            LXFlowLayout(spacing: 6, lineSpacing: 6) {
                                ForEach(spec.options, id: \.self) { opt in
                                    let chosen = (fieldValues[spec.name] ?? spec.initialValue) == opt
                                    Button(opt) {
                                        fieldValues[spec.name] = opt
                                    }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .foregroundStyle(chosen ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
                                    .background(chosen ? Color(Design.Palette.ink) : Color(Design.Palette.surface), in: Capsule())
                                    .overlay(Capsule().stroke(chosen ? Color.clear : Color(Design.Palette.hairline), lineWidth: 0.5))
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            let binding = Binding<String>(
                                get: { fieldValues[spec.name] ?? spec.initialValue },
                                set: { fieldValues[spec.name] = $0 }
                            )
                            TextField("填写\(spec.name)…", text: binding, axis: .vertical)
                                .lineLimit(2...5)
                                .font(.subheadline)
                                .padding(9)
                                .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
                                )
                        }
                    }
                }

                DisclosureGroup("查看实时渲染后的完整 Prompt", isExpanded: $showRenderedPreview) {
                    Text(renderedPrompt(for: tpl))
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(Design.Palette.stone))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(Design.Palette.surfaceSoft), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(Design.Palette.stone))

                if isRunning {
                    Button {
                        runTask?.cancel()
                    } label: {
                        Label("停止生成", systemImage: "stop.fill")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
                } else {
                    Button {
                        runTemplate(tpl)
                    } label: {
                        Label("一键生成成品", systemImage: "sparkles")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(!appState.aiConfig.isConfigured)
                }

                if !outputText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        LXMarkdownMessageView(text: outputText, font: .subheadline)
                            .padding(10)
                            .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        if !isRunning {
                            HStack(spacing: 8) {
                                Button {
                                    UIPasteboard.general.string = outputText
                                    showToast("已复制成品")
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                                Button {
                                    appState.addQuickPhrase(title: tpl.title, content: outputText, category: "模板AI")
                                    showToast("已存为快捷短语")
                                } label: {
                                    Label("存短语", systemImage: "text.badge.plus")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                                if let onOpenInWorkbench {
                                    Button {
                                        onOpenInWorkbench(outputText)
                                    } label: {
                                        Label("进工作台", systemImage: "bubble.left")
                                    }
                                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func selectTemplate(_ tpl: ParameterizedProTemplate) {
        activeTemplate = tpl
        outputText = ""
        var initVals: [String: String] = [:]
        for spec in PromptVariableEngine.extractVariables(from: tpl.userPromptTemplate) {
            initVals[spec.name] = spec.initialValue
        }
        fieldValues = initVals
    }

    private func renderedPrompt(for tpl: ParameterizedProTemplate) -> String {
        let clip = ConcealedPasteboard.readNonConcealedStringForUserPaste() ?? ""
        return PromptVariableEngine.render(
            template: tpl.userPromptTemplate,
            values: fieldValues,
            clipboardText: clip,
            sceneTitle: appState.aiConfig.activeScenePersona.shortTitle,
            cityName: cachedCityName
        )
    }

    private func runTemplate(_ tpl: ParameterizedProTemplate) {
        let prompt = renderedPrompt(for: tpl).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        runTask?.cancel()
        outputText = ""
        isRunning = true
        let cfg = appState.aiConfig

        runTask = Task {
            var acc = ""
            defer {
                Task { @MainActor in
                    isRunning = false
                    appState.refreshAll()
                }
            }
            do {
                for try await delta in client.streamText(
                    prompt: prompt,
                    systemInstruction: tpl.systemPrompt,
                    config: cfg,
                    featureTag: "ai_param_template",
                    preferFast: !tpl.preferDeep,
                    preferDeep: tpl.preferDeep,
                    allowMarkdown: true
                ) {
                    if Task.isCancelled { break }
                    acc += delta
                    let snap = AITextSanitizer.cleanPreservingMarkdown(acc, streaming: true)
                    await MainActor.run { outputText = snap }
                }
                let finalOut = AITextSanitizer.cleanPreservingMarkdown(acc, streaming: false)
                await MainActor.run {
                    outputText = finalOut
                    if !finalOut.isEmpty {
                        AIRecentHistoryStore.record(title: "模板 · \(tpl.title)", output: finalOut, prompt: prompt)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        showToast("生成失败：\(error.localizedDescription)", isError: true)
                    }
                }
            }
        }
    }

    private func installAsKeyboardSkill(_ tpl: ParameterizedProTemplate) {
        let sys = PromptVariableEngine.staticSystemPrompt(for: tpl, values: fieldValues)
        let newPrompt = CustomAIPromptTemplate(
            title: tpl.title,
            icon: tpl.icon,
            instruction: sys,
            isPinned: true,
            useDeepModel: tpl.preferDeep
        )
        if let idx = appState.aiConfig.customPrompts.firstIndex(where: { $0.title == tpl.title }) {
            appState.aiConfig.customPrompts[idx] = newPrompt
        } else {
            appState.aiConfig.customPrompts.insert(newPrompt, at: 0)
        }
        showToast("已将「\(tpl.title)」固化装入键盘 AI 技能栏")
    }

    private func showToast(_ msg: String, isError: Bool = false) {
        toastIsError = isError
        toastMessage = msg
    }
}
