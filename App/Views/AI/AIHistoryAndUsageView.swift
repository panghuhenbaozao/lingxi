import SwiftUI
import UIKit

/// 生成历史与 Token / 分模型延迟账本页（支持搜索、单条左滑删除、送回工作台续写、分模型性能排行）
struct AIHistoryAndUsageView: View {
    @EnvironmentObject private var appState: AppState
    let onContinueInWorkbench: (String) -> Void

    @State private var recentHistory: [AIRecentResultItem] = []
    @State private var searchText = ""
    @State private var selectedSkillFilter = "全部"
    @State private var showAllLedger = false
    @State private var expandedIDs: Set<String> = []
    @State private var feedback: String?
    @State private var confirmClearLedger = false
    @State private var confirmClearHistory = false

    private struct ModelPerfSummary: Identifiable {
        let model: String
        let calls: Int
        let avgTTFT: Int
        let totalOutputChars: Int
        let totalTokens: Int
        var id: String { model }
    }

    private var availableHistoryTags: [String] {
        var seen = Set<String>()
        var tags = ["全部"]
        for item in recentHistory where !item.title.isEmpty && seen.insert(item.title).inserted {
            tags.append(item.title)
        }
        return tags
    }

    private var filteredHistory: [AIRecentResultItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return recentHistory.filter { item in
            if selectedSkillFilter != "全部" && item.title != selectedSkillFilter { return false }
            if q.isEmpty { return true }
            return item.title.lowercased().contains(q)
                || item.prompt.lowercased().contains(q)
                || item.output.lowercased().contains(q)
        }
    }

    private func computeModelSummaries(from entries: [AIUsageLedgerEntry]) -> [ModelPerfSummary] {
        var grouped: [String: [AIUsageLedgerEntry]] = [:]
        for e in entries where !e.model.isEmpty {
            grouped[e.model, default: []].append(e)
        }
        return grouped.map { model, list in
            let timed = list.filter { $0.ttftMs > 0 }
            let avg = timed.isEmpty ? 0 : timed.reduce(0) { $0 + $1.ttftMs } / timed.count
            let outChars = list.reduce(0) { $0 + $1.outputChars }
            let tokens = list.reduce(0) { $0 + $1.totalReportedTokens }
            return ModelPerfSummary(model: model, calls: list.count, avgTTFT: avg, totalOutputChars: outChars, totalTokens: tokens)
        }
        .sorted { $0.calls > $1.calls }
    }

    private struct DailyCallBucket: Identifiable {
        let id: String
        let label: String
        let count: Int
        let isToday: Bool
    }

    private func computeLast7Days(from entries: [AIUsageLedgerEntry]) -> [DailyCallBucket] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        var countsByDay: [Date: Int] = [:]
        for e in entries {
            let d = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(e.timestamp)))
            countsByDay[d, default: 0] += 1
        }
        return (0..<7).reversed().compactMap { offset -> DailyCallBucket? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyCallBucket(
                id: fmt.string(from: day),
                label: offset == 0 ? "今天" : fmt.string(from: day),
                count: countsByDay[day] ?? 0,
                isToday: offset == 0
            )
        }
    }

    var body: some View {
        let entries = appState.aiUsageLedger
        let timed = entries.filter { $0.ttftMs > 0 }
        let avgTTFT = timed.isEmpty ? 0 : timed.reduce(0) { $0 + $1.ttftMs } / timed.count
        let totalOut = entries.reduce(0) { $0 + $1.outputChars }
        let totalTokens = entries.reduce(0) { $0 + $1.totalReportedTokens }
        let totalReasoningTokens = entries.reduce(0) { $0 + ($1.reasoningTokens ?? 0) }
        let estUSD = AICostEstimator.totalEstimatedUSD(for: entries)
        let monthUSD = AICostEstimator.currentMonthEstimatedUSD(for: entries)
        let monthCNY = monthUSD * 7.25
        let budgetCNY = appState.aiConfig.monthlyBudgetCNY
        let dailyBuckets = computeLast7Days(from: entries)
        let sortedCalls = entries.sorted { $0.timestamp > $1.timestamp }
        let displayedCalls = showAllLedger ? sortedCalls : Array(sortedCalls.prefix(10))
        let modelSummaries = computeModelSummaries(from: entries)
        let shownHistory = filteredHistory

        return List {
            Section {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    statTile(title: "累计调用", value: "\(entries.count)", unit: "次", icon: "bolt.fill")
                    statTile(title: "平均首字", value: avgTTFT > 0 ? "\(avgTTFT)" : "--", unit: "ms", icon: "timer")
                    if totalTokens > 0 {
                        statTile(title: "实测 Token", value: formatCompactNumber(totalTokens), unit: "tok", icon: "cpu")
                    } else {
                        statTile(title: "累计生成", value: totalOut.formatted(), unit: "字", icon: "text.alignleft")
                    }
                    statTile(title: "参考估算费用", value: AICostEstimator.formatCNY(estUSD), unit: "≈省\(max(0, totalOut / 38))分", icon: "yensign.circle")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if totalTokens > 0 || totalOut > 0 {
                    LXFlowLayout(spacing: 8, lineSpacing: 6) {
                        LXTag(text: "生成 \(totalOut.formatted()) 字")
                        if totalReasoningTokens > 0 {
                            LXTag(text: "思考 \(formatCompactNumber(totalReasoningTokens)) tok", tint: Color(Design.Palette.accent), filled: true)
                        }
                        if estUSD > 0 {
                            LXTag(text: String(format: "约 $%.4f", estUSD))
                        }
                        LXTag(text: "本月估算 \(AICostEstimator.formatCNY(monthUSD))")
                    }
                    .padding(.vertical, 2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("本月费用预算提醒")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Spacer()
                        Text(budgetCNY > 0 ? "\(AICostEstimator.formatCNY(monthUSD)) / ¥\(Int(budgetCNY))" : "不限")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(
                                budgetCNY > 0 && monthCNY >= budgetCNY
                                    ? Color(Design.Palette.error)
                                    : (budgetCNY > 0 && monthCNY >= budgetCNY * 0.8 ? Color(Design.Palette.warning) : Color(Design.Palette.stone))
                            )
                    }
                    if budgetCNY > 0 {
                        let ratio = min(1.0, monthCNY / budgetCNY)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(Design.Palette.surface))
                                Capsule()
                                    .fill(monthCNY >= budgetCNY ? Color(Design.Palette.error) : (monthCNY >= budgetCNY * 0.8 ? Color(Design.Palette.warning) : Color(Design.Palette.accent)))
                                    .frame(width: max(4, geo.size.width * ratio))
                            }
                        }
                        .frame(height: 6)
                    }
                    LXFlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach([0.0, 15.0, 30.0, 50.0, 100.0], id: \.self) { cap in
                            let selected = abs(budgetCNY - cap) < 0.5
                            Button(cap == 0 ? "不限" : "¥\(Int(cap))") {
                                appState.aiConfig.monthlyBudgetCNY = cap
                                feedback = cap == 0 ? "已关闭月度预算提醒" : "已设本月预算提醒 ¥\(Int(cap))"
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .foregroundStyle(selected ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
                            .background(selected ? Color(Design.Palette.ink) : Color(Design.Palette.surface), in: Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("用量与成本概览")
            } footer: {
                Text("参考费用按各主流模型公开单价估算，Ollama 本地模型计 ¥0；节省时间按手打每分钟约 38 字估算。")
            }

            if entries.count > 0 {
                Section("近 7 天 AI 活跃趋势") {
                    let maxCount = max(1, dailyBuckets.map(\.count).max() ?? 1)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(dailyBuckets) { b in
                            VStack(spacing: 4) {
                                Text(b.count > 0 ? "\(b.count)" : "")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(b.isToday ? Color(Design.Palette.accent) : Color(Design.Palette.stone))
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(b.isToday ? Color(Design.Palette.accent) : Color(Design.Palette.accent).opacity(0.35))
                                    .frame(height: max(4, CGFloat(b.count) / CGFloat(maxCount) * 76))
                                Text(b.label)
                                    .font(.caption2)
                                    .foregroundStyle(b.isToday ? Color(Design.Palette.ink) : Color(Design.Palette.stone))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 112, alignment: .bottom)
                    .padding(.vertical, 6)
                }
            }

            if !modelSummaries.isEmpty {
                Section("分模型性能对比") {
                    ForEach(modelSummaries.prefix(6)) { summary in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.model)
                                    .font(.footnote.weight(.semibold).monospaced())
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .lineLimit(1)
                                Text("\(summary.calls) 次调用 · \(summary.totalOutputChars.formatted()) 字\(summary.totalTokens > 0 ? " · \(formatCompactNumber(summary.totalTokens)) tok" : "")")
                                    .font(.caption2)
                                    .foregroundStyle(Color(Design.Palette.stone))
                            }
                            Spacer()
                            Text(summary.avgTTFT > 0 ? "\(summary.avgTTFT) ms" : "--")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(ttftColor(summary.avgTTFT))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !sortedCalls.isEmpty {
                Section {
                    ForEach(displayedCalls) { entry in
                        ledgerRow(entry)
                    }
                    if sortedCalls.count > 10 {
                        Button(showAllLedger ? "收起至最近 10 条" : "展开全部 \(sortedCalls.count) 条调用记录") {
                            withAnimation(.easeOut(duration: 0.18)) {
                                showAllLedger.toggle()
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.accent))
                    }
                    Button("清空用量账本", role: .destructive) {
                        confirmClearLedger = true
                    }
                } header: {
                    Text("最近调用 · \(sortedCalls.count)")
                }
            }

            Section {
                if availableHistoryTags.count > 2 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(availableHistoryTags, id: \.self) { tag in
                                let active = selectedSkillFilter == tag
                                Button(tag) {
                                    selectedSkillFilter = tag
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 11)
                                .frame(height: 28)
                                .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                                .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if shownHistory.isEmpty {
                    LXEmptyState(
                        icon: recentHistory.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass",
                        title: recentHistory.isEmpty ? "暂无生成记录" : "没有匹配的记录",
                        message: recentHistory.isEmpty
                            ? "在键盘或写作工作台使用 AI 后，最近 30 条结果会保存在本机。"
                            : "换个关键词或切回「全部」试试。"
                    )
                } else {
                    ForEach(shownHistory) { item in
                        historyRow(item)
                    }
                    Button("清空生成历史", role: .destructive) {
                        confirmClearHistory = true
                    }
                }
            } header: {
                Text("生成历史 · \(shownHistory.count) / \(recentHistory.count)（最多保存 30 条）")
            } footer: {
                if !shownHistory.isEmpty {
                    Text("左滑可删除单条历史；点「去微调」可将结果送回写作工作台继续改写。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "搜索历史回答或提问原文")
        .navigationTitle("历史与 Token 账本")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($feedback)
        .refreshable {
            recentHistory = AIRecentHistoryStore.load()
            appState.refreshAll()
        }
        .onAppear {
            recentHistory = AIRecentHistoryStore.load()
        }
        .confirmationDialog("清空用量账本？", isPresented: $confirmClearLedger, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                appState.clearAIUsageLedger()
                feedback = "已清空用量账本"
            }
        } message: {
            Text("调用次数、首字延迟与 Token 统计会被清零，无法恢复。")
        }
        .confirmationDialog("清空生成历史？", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                AIRecentHistoryStore.clear()
                recentHistory = []
                expandedIDs = []
                feedback = "已清空生成历史"
            }
        } message: {
            Text("最近保存的生成结果会被删除，无法恢复。")
        }
    }

    private func formatCompactNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000.0) }
        if n >= 10_000 { return String(format: "%.1fK", Double(n) / 1000.0) }
        return n.formatted()
    }

    private func statTile(title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.accent))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(Design.Palette.canvas), in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
        )
    }

    private func ttftColor(_ ms: Int) -> Color {
        if ms <= 0 { return Color(Design.Palette.muted) }
        if ms < 1500 { return Color(Design.Palette.success) }
        if ms < 4000 { return Color(Design.Palette.ink) }
        return Color(Design.Palette.warning)
    }

    private func featureDisplayName(_ tag: String) -> String {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "AI 调用" }
        if let preset = AIPresetAction(rawValue: t) { return preset.title }
        switch t {
        case "ai_ask": return "键盘自由提问"
        case "ai_direct": return "@ai 指令"
        case "ai_retry": return "重新生成"
        case "ai_strategist": return "博弈军师"
        case "ai_three_variants": return "一次生成 3 版"
        case "kb_three_variants": return "键盘一键三版"
        case "live_translate": return "键盘边打边译"
        case "app_intent_ai": return "系统快捷指令 AI"
        case "ai_auto_analysis": return "智能画像诊断"
        case "custom_prompt": return "自定义技能"
        case "style_dna_clone": return "文风 DNA 克隆"
        case "style_dna_compare": return "文风对比试写"
        case "prompt_authoring": return "AI 帮写技能"
        case "workbench_chat": return "写作工作台对话"
        case "workbench_vision": return "工作台带图对话"
        case "inline_quick_ai": return "首页闪电指令"
        case "tone_tuner": return "语气精调"
        case "writing_template": return "模板写作"
        case "long_text_digest": return "长文拆解"
        case "studio_translate": return "专业多语翻译"
        case "back_translate": return "双向回译核验"
        case "idiom_notes": return "地道表达精讲"
        case "ai_pipeline": return "链式流水线"
        case "ai_council_seat": return "圆桌会诊席位"
        case "ai_council_chairman": return "圆桌主席融合"
        case "ai_param_template": return "参数化变量模板"
        case "ai_followup": return "键盘多轮追问"
        case "ai_quick_refine": return "键盘一键精调"
        case "connectivity_test": return "测速连通"
        case "playground": return "试炼场"
        case "arena_a", "arena_b": return "跨渠道 PK"
        default: break
        }
        if t.contains("screenshot") { return "截屏 AI 识图" }
        if t.contains("voice") || t.contains("translate") { return "语音同传 / 边打边译" }
        return t
    }

    private func ledgerRow(_ entry: AIUsageLedgerEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(featureDisplayName(entry.feature))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.model)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(1)
                    if entry.totalReportedTokens > 0 {
                        Text("· \(entry.totalReportedTokens) tok")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.ttftMs > 0 ? "\(entry.ttftMs) ms" : "--")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ttftColor(entry.ttftMs))
                Text(Date(timeIntervalSince1970: TimeInterval(entry.timestamp)).formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(Color(Design.Palette.stone))
            }
        }
        .padding(.vertical, 2)
    }

    private func historyRow(_ item: AIRecentResultItem) -> some View {
        let expanded = expandedIDs.contains(item.id)
        let isLong = item.output.count > 80
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                LXTag(text: item.title, tint: Color(Design.Palette.accent), filled: true)
                Spacer(minLength: 4)
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.stone))
            }
            if !item.prompt.isEmpty {
                Text("原文：\(item.prompt)")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .lineLimit(1)
            }
            Text(item.output)
                .font(.subheadline)
                .foregroundStyle(Color(Design.Palette.ink))
                .lineSpacing(2)
                .lineLimit(expanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = item.output
                    feedback = "已复制"
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                Button {
                    appState.addQuickPhrase(title: String(item.title.prefix(8)), content: item.output, category: "AI收藏")
                    feedback = "已存为快捷短语"
                } label: {
                    Label("存短语", systemImage: "text.badge.plus")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                Button {
                    onContinueInWorkbench("请帮我基于下面这段内容继续优化：\n\(item.output)")
                } label: {
                    Label("去微调", systemImage: "bubble.left")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                Spacer(minLength: 0)

                if isLong {
                    Button(expanded ? "收起" : "展开") {
                        withAnimation(.easeOut(duration: 0.18)) {
                            if expanded { expandedIDs.remove(item.id) } else { expandedIDs.insert(item.id) }
                        }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.stone))
                    .buttonStyle(.plain)
                    .frame(minHeight: 32)
                }
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                AIRecentHistoryStore.delete(id: item.id)
                recentHistory.removeAll { $0.id == item.id }
                feedback = "已删除该条历史"
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
