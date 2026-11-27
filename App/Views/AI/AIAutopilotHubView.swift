import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 灵犀 AI 全权托管与本地 SQLite 认知学习数据库中枢
/// - 展示与控制 AI 对 26 项打字/纠错/模糊音/防丢开关的托管策略；
/// - 可视化本地共享 `ai_cognitive_memory.sqlite`（行为观察、长期记忆、决策审计、词汇共鸣）；
/// - 支持手动教给 AI 习惯、置顶/删除记忆、一键撤回 AI 决策、无敏感 JSON 导出与确认清空。
struct AIAutopilotHubView: View {
    @EnvironmentObject private var appState: AppState

    @State private var stats: CognitiveDBStats = .empty
    @State private var memories: [CognitiveMemoryFact] = []
    @State private var decisions: [AutopilotDecisionRecord] = []
    @State private var topVocab: [VocabLearningRecord] = []

    @State private var newMemoryCategory = "表达习惯"
    @State private var newMemoryContent = ""
    @State private var feedback: String?
    @State private var feedbackIsError = false
    @State private var confirmClearDB = false
    @State private var exportDoc: PromptsJSONDocument?
    @State private var showExporter = false
    @State private var showObsidianVault = false

    private static let manualCategories = ["表达习惯", "工作领域", "忌讳偏好", "个人身份"]

    var body: some View {
        List {
            autopilotControlSection
            obsidianVaultEntrySection
            if let outcome = appState.lastAutopilotOutcome, !outcome.suggestedChanges.isEmpty {
                pendingSuggestionsSection(outcome.suggestedChanges)
            }
            databaseOverviewSection
            memoriesSection
            decisionsAuditSection
            vocabResonanceSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI 全权托管与认知库")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showObsidianVault) {
            ObsidianVaultGraphView()
        }
        .onAppear {
            reloadFromSQLite()
        }
        .lxToast($feedback, isError: feedbackIsError)
        .confirmationDialog(
            "确认清空本地 AI 认知学习数据库？",
            isPresented: $confirmClearDB,
            titleVisibility: .visible
        ) {
            Button("确认清空全部学习记录与记忆", role: .destructive) {
                appState.clearCognitiveDatabase()
                reloadFromSQLite()
                showFeedback("已清空本地 SQLite 认知学习数据库")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清空打字观察统计、AI 沉淀的长期记忆、托管决策记录与词汇共鸣，不会删除你的 API Key 与自定义词库。")
        }
    }

    // MARK: - 1. 托管控制与 AI 深度调优

    private var autopilotControlSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    LXIconTile(
                        icon: "brain.head.profile",
                        tint: appState.settings.aiAutopilotMode == .fullAutopilot
                            ? Color(Design.Palette.accent)
                            : Color(Design.Palette.stone),
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("打字功能 AI 托管")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            LXTag(
                                text: appState.settings.aiAutopilotMode.shortBadge,
                                tint: appState.settings.aiAutopilotMode == .fullAutopilot
                                    ? Color(Design.Palette.success)
                                    : Color(Design.Palette.accent),
                                filled: appState.settings.aiAutopilotMode == .fullAutopilot
                            )
                        }
                        Text(appState.settings.aiAutopilotMode.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Picker("托管级别", selection: $appState.settings.aiAutopilotMode) {
                    ForEach(AIAutopilotMode.allCases) { mode in
                        Text(mode.shortBadge).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appState.settings.aiAutopilotMode) { newMode in
                    if newMode == .fullAutopilot {
                        let outcome = appState.runLocalAutopilotIfNeeded(force: true)
                        reloadFromSQLite()
                        if let msg = outcome?.summary {
                            showFeedback(msg)
                        }
                    }
                }

                if !stats.personaDigest.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("AI 眼中的你（自动注入每次回复）", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.accent))
                        Text(stats.personaDigest)
                            .font(.footnote)
                            .foregroundStyle(Color(Design.Palette.ink))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
                    )
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            let res = await appState.runDeepAIAutopilot()
                            reloadFromSQLite()
                            showFeedback(res.summary)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if appState.isRunningAutopilot {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.white)
                                Text("AI 深度读取数据库中…")
                            } else {
                                Image(systemName: "sparkles")
                                Text(appState.aiConfig.isConfigured ? "AI 深度读库并全权调优" : "立即本机习惯体检并开启")
                            }
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(appState.isRunningAutopilot || appState.settings.aiAutopilotMode == .off)

                    Button {
                        if let res = appState.runLocalAutopilotIfNeeded(force: true) {
                            reloadFromSQLite()
                            showFeedback(res.summary)
                        } else {
                            showFeedback("当前为手动或无痕模式，未自动修改", isError: false)
                        }
                    } label: {
                        Text("0ms 速检")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                    .disabled(appState.isRunningAutopilot || appState.settings.aiAutopilotMode == .off)
                }

                if let outcome = appState.lastAutopilotOutcome {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: outcome.usedLLM ? "checkmark.seal.fill" : "cpu")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.success))
                            .padding(.top, 2)
                        Text(outcome.summary)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.ink))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(Design.Palette.success).opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("全权操控策略")
        } footer: {
            Text("AI 仅在 26 项安全打字效率开关白名单内调优（纠错、模糊音、盘古空格、草稿防丢、热区自适应等），绝不触碰无痕模式、隐私脱敏护盾或任何密钥。")
        }
    }

    // MARK: - 1.5 Obsidian 风格双链自学习记忆库入口

    private var obsidianVaultEntrySection: some View {
        Section {
            Button {
                showObsidianVault = true
            } label: {
                HStack(spacing: 12) {
                    LXIconTile(icon: "circle.hexagongrid", tint: Color(Design.Palette.accent), size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Obsidian 风格双链知识图谱")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            LXTag(
                                text: "\(stats.vaultNoteCount) 笔记 · \(stats.vaultLinkCount) 双链",
                                tint: Color(Design.Palette.accent),
                                filled: true
                            )
                        }
                        Text("用你的 API 把打字习惯、对话与自述提炼为 [[双向链接]] 常青笔记，2-Hop 图谱按需召回反哺每次 AI 回复，支持导出 .md。")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
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
                        reloadFromSQLite()
                        showFeedback(res.summary)
                    }
                } label: {
                    HStack(spacing: 5) {
                        if appState.isRunningObsidianLearn {
                            ProgressView().controlSize(.mini).tint(Color.white)
                            Text("API 提炼双链中…")
                        } else {
                            Image(systemName: "wand.and.stars")
                            Text("用我的 API 演化双链记忆库")
                        }
                    }
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                .disabled(appState.isRunningObsidianLearn)

                Button("进图谱") {
                    showObsidianVault = true
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false))
            }
            .padding(.vertical, 2)
        } header: {
            Text("Obsidian LLM Wiki · 自学习个性化知识库")
        }
    }

    // MARK: - 2. 待采纳建议（建议模式）

    private func pendingSuggestionsSection(_ changes: [AutopilotProposedChange]) -> some View {
        Section("AI 建议开启的功能（\(changes.count) 项）") {
            ForEach(changes) { item in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.settingTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            LXTag(text: "\(item.currentValue) → \(item.targetValue)", tint: Color(Design.Palette.accent), filled: true)
                        }
                        Text(item.reason)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.evidence.isEmpty {
                            Text("依据：\(item.evidence)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 6)
                    Button("采纳") {
                        if appState.applyProposedAutopilotChange(item) {
                            reloadFromSQLite()
                            showFeedback("已采纳并开启「\(item.settingTitle)」")
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 3. 本地 SQLite 学习数据库概览（无 LazyVGrid，纯静态 2×2）

    private var databaseOverviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(AICognitiveMemoryDB.shared.databaseFileName, systemImage: "externaldrive.fill")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(Color(Design.Palette.ink))
                    Spacer()
                    LXTag(text: stats.formattedSize, tint: Color(Design.Palette.accent))
                    LXTag(text: "100% 本机", icon: "lock.shield.fill", tint: Color(Design.Palette.success), filled: true)
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        dbStatTile(title: "打字观察", value: "\(stats.totalObservations)", unit: "次 · \(stats.totalCharsObserved)字", icon: "keyboard")
                        dbStatTile(title: "认知记忆", value: "\(stats.memoryCount)", unit: "条长期记忆", icon: "brain.head.profile")
                    }
                    HStack(spacing: 10) {
                        dbStatTile(title: "托管生效", value: "\(stats.activeDecisionCount)", unit: "共 \(stats.decisionCount) 条记录", icon: "slider.horizontal.3")
                        dbStatTile(title: "词汇共鸣", value: "\(stats.vocabCount)", unit: "高频自学习词", icon: "text.book.closed.fill")
                    }
                }

                LXFlowLayout(spacing: 6, lineSpacing: 6) {
                    LXTag(text: "退格率 \(Int(stats.backspaceRate * 100))%")
                    LXTag(text: "中英混输 \(Int(stats.englishMixRatio * 100))%")
                    LXTag(text: "夜间活跃 \(Int(stats.nightSessionRatio * 100))%")
                    if stats.totalTypoFixes > 0 {
                        LXTag(text: "错拼纠偏 \(stats.totalTypoFixes) 次")
                    }
                    if stats.totalLongDrafts > 0 {
                        LXTag(text: "长草稿 \(stats.totalLongDrafts) 段")
                    }
                    ForEach(Array(stats.fuzzyConfusionCounts.sorted(by: { $0.value > $1.value }).prefix(4)), id: \.key) { item in
                        LXTag(text: "易混 \(item.key.replacingOccurrences(of: "_", with: "/")) ×\(item.value)", tint: Color(Design.Palette.warning), filled: true)
                    }
                }
                .padding(.top, 2)

                HStack(spacing: 8) {
                    Button {
                        if let data = AICognitiveMemoryDB.shared.exportJSONSummary() {
                            exportDoc = PromptsJSONDocument(data: data)
                            showExporter = true
                        }
                    } label: {
                        Label("导出学习库 JSON", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                    .background(
                        Color.clear.fileExporter(
                            isPresented: $showExporter,
                            document: exportDoc,
                            contentType: .json,
                            defaultFilename: "lingxi-ai-cognitive-db"
                        ) { result in
                            switch result {
                            case .success:
                                showFeedback("已导出本地 AI 学习数据库快照（不含密码与密钥）")
                            case .failure(let err):
                                let ns = err as NSError
                                if !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) {
                                    showFeedback("导出失败：\(err.localizedDescription)", isError: true)
                                }
                            }
                        }
                    )

                    Button(role: .destructive) {
                        confirmClearDB = true
                    } label: {
                        Label("清空库", systemImage: "trash")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, tint: Color(Design.Palette.error)))
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("AI 专属本地 SQLite 数据库")
        } footer: {
            Text("主 App 与键盘扩展通过 App Group 共享这份加密保护 SQLite 库；密码框、无痕模式与敏感隐私内容严格跳过，永不入库。")
        }
    }

    // MARK: - 4. AI 长期认知记忆（可主动教给 AI + 置顶 + 删除）

    private var memoriesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.manualCategories, id: \.self) { cat in
                            let selected = newMemoryCategory == cat
                            Button {
                                newMemoryCategory = cat
                            } label: {
                                Text(cat)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .foregroundStyle(selected ? Color.white : Color(Design.Palette.ink))
                                    .background(selected ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("主动告诉 AI 一个习惯（如：回复老板先说结论、不用感叹号）", text: $newMemoryContent)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button("教给 AI") {
                        let trimmed = newMemoryContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        appState.addManualCognitiveMemory(category: newMemoryCategory, content: trimmed)
                        newMemoryContent = ""
                        reloadFromSQLite()
                        showFeedback("已写入 SQLite 长期记忆，AI 下次立即生效")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                    .disabled(newMemoryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.vertical, 4)

            if memories.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("记忆库刚开始积累")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("正常用灵犀键盘打字，或点上方「AI 深度读库并全权调优」，AI 就会把你的表达习惯、高频领域与拼音特征沉淀到这里。")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                }
                .padding(.vertical, 4)
            } else {
                ForEach(memories) { mem in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                LXTag(text: mem.category, tint: Color(Design.Palette.accent), filled: mem.isPinned)
                                LXTag(text: mem.sourceDisplayName)
                                Text("\(Int(mem.confidence * 100))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(mem.content)
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Button {
                            AICognitiveMemoryDB.shared.togglePinMemory(id: mem.id)
                            reloadFromSQLite()
                        } label: {
                            Image(systemName: mem.isPinned ? "pin.fill" : "pin")
                                .font(.caption)
                                .foregroundStyle(mem.isPinned ? Color(Design.Palette.accent) : Color(Design.Palette.stone))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(mem.isPinned ? "取消置顶" : "置顶记忆")
                    }
                    .padding(.vertical, 3)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            AICognitiveMemoryDB.shared.deleteMemory(id: mem.id)
                            reloadFromSQLite()
                            showFeedback("已忘记这条记忆")
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("长期认知记忆（每次 AI 调用自动带入）")
        } footer: {
            Text("置顶记忆拥有最高权重，会优先注入你的每一次 AI 润色、回复、翻译与对话提示词中，让 AI 越用越懂你。")
        }
    }

    // MARK: - 5. AI 托管操控审计日志（支持一键撤回）

    private var decisionsAuditSection: some View {
        Section {
            if decisions.isEmpty {
                Text("暂无自动调优记录。点击上方「立即调优」或在日常打字后，AI 的每一项功能开启决定都会完整记录在这里并支持一键撤回。")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(decisions.prefix(20))) { rec in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(rec.settingTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(rec.reverted ? Color(Design.Palette.stone) : Color(Design.Palette.ink))
                                LXTag(
                                    text: "\(rec.oldValue) → \(rec.newValue)",
                                    tint: rec.reverted ? Color(Design.Palette.stone) : Color(Design.Palette.success),
                                    filled: !rec.reverted
                                )
                            }
                            Text(rec.reason)
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                if !rec.evidence.isEmpty {
                                    Text(rec.evidence)
                                }
                                Text(formatTime(rec.appliedAt))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if rec.reverted {
                            Text("已撤回")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.stone))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(Design.Palette.surface), in: Capsule())
                        } else {
                            Button {
                                if appState.revertAutopilotDecision(rec) {
                                    reloadFromSQLite()
                                    showFeedback("已撤回「\(rec.settingTitle)」至「\(rec.oldValue)」")
                                }
                            } label: {
                                Label("撤回", systemImage: "arrow.uturn.backward")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        } header: {
            Text("AI 功能操控审计记录（可 1 键撤回）")
        }
    }

    // MARK: - 6. 词汇学习共鸣

    private var vocabResonanceSection: some View {
        Section {
            if topVocab.isEmpty {
                Text("你在键盘中频繁打出的新词与高频词组，会自动沉淀到这里并归类领域，帮 AI 识别你的专业语境。")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .padding(.vertical, 4)
            } else {
                LXFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Array(topVocab.prefix(18))) { item in
                        LXTag(
                            text: "\(item.word) · \(item.domain) ×\(item.learnCount)",
                            tint: Color(Design.Palette.slate)
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("词汇学习共鸣（Top \(min(18, topVocab.count))）")
        }
    }

    // MARK: - Helpers

    private func dbStatTile(title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.accent))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.stone))
            }
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Color(Design.Palette.ink))
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
        )
    }

    private func reloadFromSQLite() {
        let db = AICognitiveMemoryDB.shared
        stats = db.loadStats()
        memories = db.fetchMemories(limit: 40)
        decisions = db.fetchDecisions(limit: 30)
        topVocab = db.fetchTopVocab(limit: 24)
        appState.cognitiveStats = stats
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
        feedbackIsError = isError
        feedback = message
    }

    private func formatTime(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .abbreviated, time: .shortened)
    }
}
