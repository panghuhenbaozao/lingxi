import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 文风 DNA 与场景绑定背景知识卡（含克隆前后效果对比试写、Diff 规则管理、PDF/TXT/MD 文档自动切片导入与 RAG-Lite 命中试测）
struct AIStyleAndContextView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showCloner = false
    @State private var showCompareSheet = false
    @State private var showNewCard = false
    @State private var showDocImporter = false
    @State private var ragTestQuery = ""
    @State private var editingCard: PersonalContextCard?
    @State private var newBanned = ""
    @State private var newCatchphrase = ""
    @State private var confirmClearDiffRules = false
    @State private var feedback: String?

    private var dna: PersonalStyleDNA { appState.aiConfig.styleDNA }

    private var hasDNA: Bool {
        !dna.clonedStyleSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var dnaUpdatedText: String {
        Date(timeIntervalSince1970: TimeInterval(dna.updatedAt)).formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        List {
            dnaSection
            bannedSection
            catchphraseSection
            personaSection
            learnedSection
            contextCardsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("文风 DNA 与知识卡")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($feedback)
        .sheet(isPresented: $showCloner) {
            StyleDNAClonerSheet { samples in
                let res = await appState.cloneStyleDNAWithStatus(fromSamples: samples)
                if res.usedLLM {
                    feedback = "已由大模型提取你的专属文风 DNA"
                } else {
                    feedback = res.fallbackReason ?? "已使用本机规则提取基础文风"
                }
            }
        }
        .sheet(isPresented: $showCompareSheet) {
            StyleDNACompareSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showNewCard) {
            ContextCardEditorSheet(initial: nil) { created in
                appState.upsertContextCard(created)
                feedback = "已新增知识卡「\(created.title)」"
            }
        }
        .sheet(item: $editingCard) { card in
            ContextCardEditorSheet(initial: card) { updated in
                appState.upsertContextCard(updated)
                feedback = "已更新知识卡「\(updated.title)」"
            }
        }
        .fileImporter(isPresented: $showDocImporter, allowedContentTypes: [.plainText, .utf8PlainText, .pdf]) { result in
            switch result {
            case .success(let url):
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let baseName = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension.lowercased()
                let extractedText: String
                if ext == "pdf" {
                    guard let pdfDoc = PDFDocument(url: url) else {
                        feedback = "无法打开该 PDF 文档（可能已加密或损坏）"
                        return
                    }
                    let maxPages = min(pdfDoc.pageCount, 80)
                    var pageTexts: [String] = []
                    var totalChars = 0
                    for idx in 0..<maxPages {
                        if let pageStr = pdfDoc.page(at: idx)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !pageStr.isEmpty {
                            pageTexts.append(pageStr)
                            totalChars += pageStr.count
                            if totalChars >= 60_000 { break }
                        }
                    }
                    extractedText = pageTexts.joined(separator: "\n\n")
                    guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        feedback = "该 PDF 未包含可提取文字（纯扫描图片请先截屏识图提取）"
                        return
                    }
                } else {
                    guard let data = try? Data(contentsOf: url),
                          let text = String(data: data, encoding: .utf8),
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        feedback = "无法读取该 UTF-8 文本或 Markdown 文件"
                        return
                    }
                    extractedText = text
                }
                let chunks = PersonalContextCard.chunkDocument(title: baseName, text: extractedText)
                guard !chunks.isEmpty else {
                    feedback = "文件内容为空"
                    return
                }
                for card in chunks.reversed() {
                    appState.upsertContextCard(card)
                }
                let kindTag = (ext == "pdf") ? "PDF 文档" : "文档"
                feedback = "已从 \(kindTag)「\(baseName)」智能切片导入 \(chunks.count) 张知识卡"
            case .failure(let err):
                let ns = err as NSError
                if !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) {
                    feedback = "导入失败：\(err.localizedDescription)"
                }
            }
        }
        .confirmationDialog("清空所有已学到的微调偏好？", isPresented: $confirmClearDiffRules, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                appState.aiConfig.styleDNA.learnedDiffRules = []
                appState.aiConfig.styleDNA.updatedAt = Int(Date().timeIntervalSince1970)
                feedback = "已清空自动学到的偏好规则"
            }
        } message: {
            Text("不会影响已克隆的文风 DNA、口癖或禁用词。")
        }
    }

    private var dnaSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    LXIconTile(
                        icon: "waveform.path.ecg",
                        tint: hasDNA ? Color(Design.Palette.success) : Color(Design.Palette.accent),
                        size: 42
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hasDNA ? "文风 DNA 已提取" : "还没有克隆你的文风")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text(hasDNA ? "更新于 \(dnaUpdatedText)" : "粘贴 3~5 句你真实发过的消息，AI 就会写得更像你")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if hasDNA {
                    Text(dna.clonedStyleSummary)
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.charcoal))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack(spacing: 10) {
                    Button {
                        showCloner = true
                    } label: {
                        HStack(spacing: 6) {
                            if appState.isCloningStyleDNA {
                                ProgressView().controlSize(.small).tint(Color.white)
                            } else {
                                Image(systemName: hasDNA ? "arrow.triangle.2.circlepath" : "sparkles")
                            }
                            Text(appState.isCloningStyleDNA ? "克隆中…" : (hasDNA ? "重新克隆" : "10 秒克隆文风"))
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(appState.isCloningStyleDNA)

                    if hasDNA {
                        Button {
                            showCompareSheet = true
                        } label: {
                            Label("对比效果", systemImage: "square.split.2x1")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                    }
                }
            }
            .padding(.vertical, 6)

            Toggle(isOn: $appState.aiConfig.styleDNA.removeAIClicheEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("自动去除生硬 AI 腔")
                        .font(.subheadline)
                    Text("生成时避开下方的禁用词")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                }
            }
            .tint(Color(Design.Palette.accent))
        } header: {
            Text("文风 DNA")
        }
    }

    private var bannedSection: some View {
        Section {
            if dna.bannedAICliches.isEmpty {
                Text("暂无禁用词")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            } else {
                LXFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(dna.bannedAICliches, id: \.self) { w in
                        LXRemovableChip(text: w, tint: Color(Design.Palette.error)) {
                            appState.aiConfig.styleDNA.bannedAICliches.removeAll { $0 == w }
                        }
                    }
                }
                .padding(.vertical, 6)
                .opacity(dna.removeAIClicheEnabled ? 1 : 0.45)
            }
            LXAddFieldRow(placeholder: "新增禁用词（如：赋能）", text: $newBanned) { w in
                if appState.aiConfig.styleDNA.bannedAICliches.contains(w) {
                    feedback = "「\(w)」已在列表中"
                } else {
                    appState.aiConfig.styleDNA.bannedAICliches.insert(w, at: 0)
                }
            }
        } header: {
            Text("禁用 AI 腔词条 · \(dna.bannedAICliches.count)")
        } footer: {
            Text(dna.removeAIClicheEnabled ? "点按词条即可移除。" : "「自动去除 AI 腔」已关闭，这些词条暂不生效。")
        }
    }

    private var catchphraseSection: some View {
        Section {
            if dna.personalCatchphrases.isEmpty {
                Text("暂无口癖")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            } else {
                LXFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(dna.personalCatchphrases, id: \.self) { phrase in
                        LXRemovableChip(text: phrase, tint: Color(Design.Palette.accent)) {
                            appState.aiConfig.styleDNA.personalCatchphrases.removeAll { $0 == phrase }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            LXAddFieldRow(placeholder: "新增口癖（如：收到啦～）", text: $newCatchphrase) { w in
                if appState.aiConfig.styleDNA.personalCatchphrases.contains(w) {
                    feedback = "「\(w)」已在列表中"
                } else {
                    appState.aiConfig.styleDNA.personalCatchphrases.insert(w, at: 0)
                }
            }
        } header: {
            Text("个人口癖 · \(dna.personalCatchphrases.count)")
        } footer: {
            Text("AI 会在合适的时候自然地用上，不会生搬硬套。")
        }
    }

    private var personaSection: some View {
        Section {
            TextField("例如：我是产品经理，说话简洁，喜欢先说结论", text: $appState.aiConfig.customPersonaPrompt, axis: .vertical)
                .lineLimit(3...6)
                .font(.subheadline)
                .padding(.vertical, 4)
        } header: {
            Text("全局人设补充")
        } footer: {
            Text("可选。每次调用 AI 都会带上这段描述。")
        }
    }

    private var learnedSection: some View {
        Section {
            Toggle(isOn: $appState.aiConfig.autoDiffLearnEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("从手动修改中自动学习偏好")
                        .font(.subheadline)
                    Text("在键盘里手动删改 AI 回复后，自动提炼表达习惯")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                }
            }
            .tint(Color(Design.Palette.accent))

            if dna.learnedDiffRules.isEmpty {
                Text("暂无自动学到的规则，正常使用键盘 AI 并微调发送后会自动沉淀。")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            } else {
                ForEach(dna.learnedDiffRules, id: \.self) { rule in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(Design.Palette.success))
                        Text(rule)
                            .font(.footnote)
                            .foregroundStyle(Color(Design.Palette.charcoal))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            appState.aiConfig.styleDNA.learnedDiffRules.removeAll { $0 == rule }
                            feedback = "已移除该偏好规则"
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                Button("清空已学偏好", role: .destructive) {
                    confirmClearDiffRules = true
                }
            }
        } header: {
            Text("自动学到的偏好 · \(dna.learnedDiffRules.count)")
        } footer: {
            if !dna.learnedDiffRules.isEmpty {
                Text("左滑可移除单条误学规则。")
            }
        }
    }

    private var contextCardsSection: some View {
        let cards = appState.aiConfig.contextCards
        return Section {
            if cards.isEmpty {
                LXEmptyState(
                    icon: "rectangle.stack",
                    title: "还没有知识卡",
                    message: "存入岗位、业务口径或对外介绍，可按「沟通对象」精准挂载，不用每次重复交代背景。"
                )
            } else {
                ForEach(cards) { card in
                    contextCardRow(card)
                }
            }
            Button {
                showNewCard = true
            } label: {
                Label("新增背景知识卡", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.accent))
                    .frame(minHeight: 36)
            }
            Button {
                showDocImporter = true
            } label: {
                Label("从文件导入并切片 (.pdf / .txt / .md)", systemImage: "doc.badge.plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .frame(minHeight: 36)
            }

            if !cards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("RAG 试测：输入一句提问，预览会命中哪几张卡…", text: $ragTestQuery)
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    let trimmedQ = ragTestQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedQ.isEmpty {
                        let hits = PersonalContextCard.selectRelevantCards(
                            from: cards,
                            query: trimmedQ,
                            scene: appState.aiConfig.activeScenePersona,
                            limit: 4
                        )
                        if hits.isEmpty {
                            Text("当前沟通对象下暂无启用的命中卡片。")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                        } else {
                            LXFlowLayout(spacing: 6, lineSpacing: 6) {
                                ForEach(hits) { h in
                                    LXTag(
                                        text: "\(h.card.title) · \(String(format: "%.1f", h.score))",
                                        tint: Color(Design.Palette.accent),
                                        filled: true
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("端侧 RAG 知识卡库 · \(cards.filter(\.isEnabled).count) / \(cards.count) 启用")
        } footer: {
            if !cards.isEmpty {
                Text("请求 AI 时会结合当前沟通对象 + 提问关键词动态检索相关性最高的 Top-4 卡片注入，存 20+ 张卡也不浪费 Token。")
            }
        }
    }

    private func contextCardRow(_ card: PersonalContextCard) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                editingCard = card
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(card.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .lineLimit(1)
                        if let bound = card.boundScene, bound != .auto {
                            LXTag(text: bound.shortTitle, tint: Color(Design.Palette.accent), filled: true)
                        } else if !card.sceneTag.isEmpty {
                            LXTag(text: card.sceneTag)
                        }
                    }
                    Text(card.content)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(card.isEnabled ? 1 : 0.5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { card.isEnabled },
                set: { val in
                    var updated = card
                    updated.isEnabled = val
                    appState.upsertContextCard(updated)
                }
            ))
            .labelsHidden()
            .tint(Color(Design.Palette.accent))
            .accessibilityLabel("启用 \(card.title)")
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                appState.deleteContextCard(id: card.id)
                feedback = "已删除知识卡「\(card.title)」"
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

/// 克隆前后效果对比试写 Sheet：直观展示注入个人文风 DNA 的真实差异
struct StyleDNACompareSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var sampleText = "同事问下午的方案评审能不能顺延半小时，我想答应但提醒别影响今天下班前定稿。"
    @State private var plainOutput = ""
    @State private var styledOutput = ""
    @State private var isRunning = false
    @State private var errorMsg: String?

    private let client = AIClient(timeout: 40)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LXCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("测试场景")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.stone))
                            TextEditor(text: $sampleText)
                                .font(.subheadline)
                                .frame(minHeight: 76)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    Button {
                        runComparison()
                    } label: {
                        HStack(spacing: 6) {
                            if isRunning { ProgressView().controlSize(.small).tint(Color.white) }
                            Text(isRunning ? "对比生成中…" : "同题对比：普通 AI vs 我的文风 DNA")
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(isRunning || !appState.aiConfig.isConfigured || sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let err = errorMsg {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.error))
                    }

                    compareCard(title: "未注入文风（标准 AI）", badge: "基线", tint: Color(Design.Palette.slate), text: plainOutput)
                    compareCard(title: "注入你的文风 DNA + 口癖 + 去 AI 腔", badge: "你的风格", tint: Color(Design.Palette.accent), text: styledOutput)
                }
                .lxReadableWidth()
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("文风 DNA 效果对比")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func compareCard(title: String, badge: String, tint: Color, text: String) -> some View {
        LXCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Spacer()
                    LXTag(text: badge, tint: tint, filled: true)
                }
                Text(text.isEmpty ? (isRunning ? "生成中…" : "点击上方按钮开始对比") : text)
                    .font(.subheadline)
                    .foregroundStyle(text.isEmpty ? Color(Design.Palette.muted) : Color(Design.Palette.ink))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func runComparison() {
        isRunning = true
        errorMsg = nil
        plainOutput = ""
        styledOutput = ""
        let styledCfg = appState.aiConfig
        var plainCfg = appState.aiConfig
        plainCfg.styleDNA = PersonalStyleDNA()
        plainCfg.styleDNA.removeAIClicheEnabled = false
        plainCfg.styleDNA.personalCatchphrases = []
        plainCfg.styleDNA.bannedAICliches = []
        plainCfg.customPersonaPrompt = ""
        let prompt = sampleText
        let sys = AIPresetAction.eqReply.systemPrompt

        Task {
            defer { Task { @MainActor in isRunning = false } }
            async let pTask: Void = {
                var acc = ""
                do {
                    for try await d in client.streamText(prompt: prompt, systemInstruction: sys, config: plainCfg, featureTag: "style_dna_compare") {
                        acc += d
                        let snap = AITextSanitizer.clean(acc, streaming: true)
                        await MainActor.run { plainOutput = snap }
                    }
                    let f = AITextSanitizer.clean(acc, streaming: false)
                    await MainActor.run { plainOutput = f }
                } catch {
                    await MainActor.run { errorMsg = error.localizedDescription }
                }
            }()
            async let sTask: Void = {
                var acc = ""
                do {
                    for try await d in client.streamText(prompt: prompt, systemInstruction: sys, config: styledCfg, featureTag: "style_dna_compare") {
                        acc += d
                        let snap = AITextSanitizer.clean(acc, streaming: true)
                        await MainActor.run { styledOutput = snap }
                    }
                    let f = AITextSanitizer.clean(acc, streaming: false)
                    await MainActor.run { styledOutput = f }
                } catch {
                    await MainActor.run { errorMsg = error.localizedDescription }
                }
            }()
            _ = await (pTask, sTask)
        }
    }
}

/// 10 秒文风 DNA 克隆弹窗
struct StyleDNAClonerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onClone: (String) async -> Void
    @State private var samples = ""
    @State private var isCloning = false

    private static let exampleText = "收到啦，开完会马上看，有进展同步你～\n哈哈不急，明天碰一下就行。\n刚核对完了，整体没问题，两处细节标文档里了。"

    private var sampleCount: Int {
        samples
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    private var countLabel: String {
        if sampleCount == 0 { return "每行一条" }
        return sampleCount < 3 ? "已识别 \(sampleCount) 条 · 建议至少 3 条" : "已识别 \(sampleCount) 条"
    }

    private var canClone: Bool {
        !isCloning && !samples.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        LXIconTile(icon: "waveform.path.ecg", size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("10 秒克隆你的文风")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text("粘贴 3~5 条你平时真实发过的消息，每行一条。AI 会提取语气、句式和常用表达，之后生成的内容会更像你。")
                                .font(.footnote)
                                .foregroundStyle(Color(Design.Palette.stone))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    LXCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("我的消息样本")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.stone))
                                Spacer()
                                Text(countLabel)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(sampleCount >= 3 ? Color(Design.Palette.success) : Color(Design.Palette.stone))
                            }

                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $samples)
                                    .font(.subheadline)
                                    .frame(minHeight: 180)
                                    .scrollContentBackground(.hidden)
                                    .disabled(isCloning)
                                if samples.isEmpty {
                                    Text("例如：\n收到啦，开完会马上看～\n哈哈不急，明天碰一下就行。")
                                        .font(.subheadline)
                                        .foregroundStyle(Color(Design.Palette.muted))
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }
                            .padding(8)
                            .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            HStack(spacing: 8) {
                                Button {
                                    samples = Self.exampleText
                                } label: {
                                    Label("填入示例", systemImage: "text.badge.plus")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                                Button {
                                    if let p = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
                                        samples = samples.isEmpty ? p : samples + "\n" + p
                                    }
                                } label: {
                                    Label("粘贴", systemImage: "doc.on.clipboard")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                                Spacer(minLength: 0)

                                if !samples.isEmpty {
                                    Button {
                                        samples = ""
                                    } label: {
                                        Label("清空", systemImage: "xmark")
                                    }
                                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, tint: Color(Design.Palette.stone)))
                                }
                            }
                            .disabled(isCloning)
                        }
                    }

                    Label("建议先去掉手机号、地址等隐私信息再粘贴。", systemImage: "hand.raised.fill")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                }
                .lxReadableWidth()
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button {
                    isCloning = true
                    Task {
                        await onClone(samples)
                        await MainActor.run {
                            isCloning = false
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isCloning {
                            ProgressView().controlSize(.small).tint(Color.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isCloning ? "正在提取文风…" : "开始克隆")
                    }
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                .disabled(!canClone)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .navigationTitle("文风 DNA 克隆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isCloning)
                }
            }
            .interactiveDismissDisabled(isCloning)
        }
    }
}

/// 个人背景知识卡编辑弹窗（支持场景条件绑定与快速模板）
struct ContextCardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: PersonalContextCard?
    let onSave: (PersonalContextCard) -> Void

    @State private var title: String
    @State private var sceneTag: String
    @State private var boundScene: AIScenePersona
    @State private var content: String
    @State private var isEnabled: Bool

    private static let tagPresets = ["职场", "销售", "技术", "学习", "生活", "通用"]
    private static let quickTemplates: [(name: String, tag: String, scene: AIScenePersona, body: String)] = [
        ("我的岗位简介", "职场", .bossClient, "我负责产品增长与客户方案推进，汇报时优先给出结论、关键数据与下周节点。"),
        ("业务术语口径", "技术", .colleague, "项目代号统一称「灵犀输入法」，客户端指 iOS 端，同步采用端到端加密。"),
        ("个人沟通边界", "生活", .friendPartner, "工作日晚 8 点后尽量不安排临时电话，周末有固定家庭时间，回复语气保持轻松真诚。"),
        ("邮件/对外签名", "职场", .bossClient, "对外发正式消息时结尾可简短致谢，署名使用中文名，不加多余客套语。")
    ]

    init(initial: PersonalContextCard?, onSave: @escaping (PersonalContextCard) -> Void) {
        self.initial = initial; self.onSave = onSave
        _title = State(initialValue: initial?.title ?? "")
        _sceneTag = State(initialValue: initial?.sceneTag ?? "职场")
        _boundScene = State(initialValue: initial?.boundScene ?? .auto)
        _content = State(initialValue: initial?.content ?? "")
        _isEnabled = State(initialValue: initial?.isEnabled ?? true)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if initial == nil {
                    Section("一键套用常见模板") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.quickTemplates, id: \.name) { tpl in
                                    Button(tpl.name) {
                                        title = tpl.name
                                        sceneTag = tpl.tag
                                        boundScene = tpl.scene
                                        content = tpl.body
                                    }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .frame(height: 30)
                                    .background(Color(Design.Palette.accentSoft), in: Capsule())
                                    .foregroundStyle(Color(Design.Palette.accent))
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("标题") {
                    TextField("如：岗位与汇报口径", text: $title)
                }

                Section {
                    Picker("按沟通对象触发", selection: $boundScene) {
                        Text("全部场景通用").tag(AIScenePersona.auto)
                        ForEach(AIScenePersona.allCases.filter { $0 != .auto }) { sc in
                            Text("仅 \(sc.shortTitle)").tag(sc)
                        }
                    }
                } header: {
                    Text("生效场景")
                } footer: {
                    Text("绑定具体沟通对象后，只有在对应场景下才会注入这张知识卡，既省 Token 又防止商务口径串到日常聊天。")
                }

                Section("分类标签") {
                    LXFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Self.tagPresets, id: \.self) { tag in
                            let selected = sceneTag == tag
                            Button {
                                sceneTag = tag
                            } label: {
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .frame(height: 32)
                                    .foregroundStyle(selected ? Color.white : Color(Design.Palette.ink))
                                    .background(selected ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    TextField("或输入自定义标签", text: $sceneTag)
                }

                Section {
                    TextField("例如：我在某公司做产品经理，负责会员增长；对外统一称「会员中心」……", text: $content, axis: .vertical)
                        .lineLimit(5...10)
                } header: {
                    HStack {
                        Text("背景内容")
                        Spacer()
                        Text("\(content.count) 字")
                            .monospacedDigit()
                    }
                }

                Section {
                    Toggle("启用此卡片", isOn: $isEnabled)
                        .tint(Color(Design.Palette.accent))
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
                            sceneTag: sceneTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "通用" : sceneTag.trimmingCharacters(in: .whitespacesAndNewlines),
                            boundScene: boundScene == .auto ? nil : boundScene,
                            isEnabled: isEnabled
                        )
                        onSave(card)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}
