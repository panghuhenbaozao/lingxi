import SwiftUI

/// 智能画像诊断页（修复推荐模糊音开启完成态联动）
struct AIAutoInsightView: View {
    @EnvironmentObject private var appState: AppState
    @State private var feedback: String?

    var body: some View {
        List {
            if let report = appState.aiInsightReport {
                reportHeroSection(report)
                quickApplySection(report)
                if !report.actionableTips.isEmpty {
                    tipsSection(report)
                }
                if !report.suggestedPrompts.isEmpty {
                    promptsSection(report)
                }
                if !report.suggestedPhrases.isEmpty {
                    phrasesSection(report)
                }
            } else {
                emptySection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("智能画像诊断")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($feedback)
    }

    private func runAnalysis() {
        Task {
            let report = await appState.runAIAutoAnalysis()
            await MainActor.run {
                feedback = "已生成画像「\(report.personaTitle)」"
            }
        }
    }

    private func allSuggestedFuzzyEnabled(_ keys: [String]) -> Bool {
        let f = appState.settings.fuzzy
        for key in keys {
            switch key {
            case "zh_z": if !f.zhZ { return false }
            case "ch_c": if !f.chC { return false }
            case "sh_s": if !f.shS { return false }
            case "n_l": if !f.nl { return false }
            case "r_l": if !f.rl { return false }
            case "f_h": if !f.fh { return false }
            case "an_ang": if !f.anAng { return false }
            case "en_eng": if !f.enEng { return false }
            case "in_ing": if !f.inIng { return false }
            default: break
            }
        }
        return !keys.isEmpty
    }

    private func analyzeButton(title: String, prominent: Bool) -> some View {
        Button {
            runAnalysis()
        } label: {
            HStack(spacing: 6) {
                if appState.isRunningAIInsight {
                    ProgressView()
                        .controlSize(.small)
                        .tint(prominent ? Color.white : Color(Design.Palette.accent))
                } else {
                    Image(systemName: prominent ? "sparkles" : "arrow.clockwise")
                }
                Text(appState.isRunningAIInsight ? "分析中…" : title)
            }
        }
        .buttonStyle(LXCapsuleButtonStyle(prominent: prominent, wide: true))
        .disabled(appState.isRunningAIInsight)
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 16) {
                LXIconTile(icon: "brain.head.profile", size: 60)
                VStack(spacing: 6) {
                    Text("生成你的专属打字画像")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("根据打字统计和 AI 使用习惯分析你的表达风格，并推荐人设、键盘技能、常用短语和模糊音。")
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                analyzeButton(title: "立即分析", prominent: true)
                Text(appState.aiConfig.isConfigured ? "已配置 AI，将由大模型深度分析" : "未配置 AI 时使用端侧诊断，数据不离开设备")
                    .font(.caption2)
                    .foregroundStyle(Color(Design.Palette.stone))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 4)
        }
    }

    private func reportHeroSection(_ report: AIAutoInsightReport) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    LXIconTile(icon: "brain.head.profile", size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("你的打字画像")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.stone))
                        Text(report.personaTitle)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    LXTag(
                        text: report.sourceLabel,
                        icon: report.isFromLLM ? "sparkles" : "iphone",
                        tint: report.isFromLLM ? Color(Design.Palette.accent) : Color(Design.Palette.slate),
                        filled: report.isFromLLM
                    )
                    Text(report.generatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(Color(Design.Palette.stone))
                }

                if !report.styleSummary.isEmpty {
                    insightBlock(title: "表达风格", icon: "text.quote", text: report.styleSummary)
                }
                if !report.efficiencyDiagnosis.isEmpty {
                    insightBlock(title: "效率诊断", icon: "speedometer", text: report.efficiencyDiagnosis)
                }

                analyzeButton(title: "重新分析", prominent: false)
            }
            .padding(.vertical, 6)
        }
    }

    private func insightBlock(title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(Design.Palette.slate))
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color(Design.Palette.charcoal))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func quickApplySection(_ report: AIAutoInsightReport) -> some View {
        let hasPersona = !report.recommendedPersonaPrompt.isEmpty
        let hasFuzzy = !report.suggestedFuzzyKeys.isEmpty
        if hasPersona || hasFuzzy {
            Section("一键优化") {
                if hasPersona {
                    let applied = appState.aiConfig.customPersonaPrompt == report.recommendedPersonaPrompt
                    applyRow(
                        icon: "person.text.rectangle",
                        title: "应用推荐人设",
                        detail: report.recommendedPersonaPrompt,
                        actionTitle: applied ? "已应用" : "应用",
                        done: applied
                    ) {
                        appState.aiConfig.customPersonaPrompt = report.recommendedPersonaPrompt
                        feedback = "已应用推荐人设"
                    }
                }
                if hasFuzzy {
                    let fuzzyDone = allSuggestedFuzzyEnabled(report.suggestedFuzzyKeys)
                    let names = report.suggestedFuzzyKeys
                        .map(AIAutoInsightService.fuzzyDisplayName(for:))
                        .joined(separator: "、")
                    applyRow(
                        icon: "ear",
                        title: "开启推荐模糊音",
                        detail: names,
                        actionTitle: fuzzyDone ? "已开启" : "开启",
                        done: fuzzyDone
                    ) {
                        let n = appState.applySuggestedFuzzyKeys(report.suggestedFuzzyKeys)
                        feedback = n > 0 ? "已开启 \(n) 项模糊音" : "推荐的模糊音都已开启"
                    }
                }
            }
        }
    }

    private func applyRow(icon: String, title: String, detail: String, actionTitle: String, done: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            LXIconTile(icon: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Button(actionTitle, action: action)
                .buttonStyle(LXCapsuleButtonStyle(prominent: !done))
                .disabled(done)
        }
        .padding(.vertical, 4)
    }

    private func tipsSection(_ report: AIAutoInsightReport) -> some View {
        Section("改进建议") {
            ForEach(Array(report.actionableTips.enumerated()), id: \.offset) { idx, tip in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(idx + 1)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(Color(Design.Palette.accent))
                        .frame(width: 22, height: 22)
                        .background(Color(Design.Palette.accentSoft), in: Circle())
                    Text(tip)
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.charcoal))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func promptsSection(_ report: AIAutoInsightReport) -> some View {
        let existing = Set(appState.aiConfig.customPrompts.map(\.title))
        let pendingCount = report.suggestedPrompts.filter { !existing.contains($0.title) }.count
        return Section {
            ForEach(report.suggestedPrompts) { tpl in
                let added = existing.contains(tpl.title)
                HStack(alignment: .center, spacing: 12) {
                    LXIconTile(icon: tpl.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tpl.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text(tpl.instruction)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    Button(added ? "已装入" : "装入") {
                        _ = appState.importSuggestedPrompts([tpl])
                        feedback = "已装入「\(tpl.title)」"
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: !added))
                    .disabled(added)
                }
                .padding(.vertical, 4)
            }
            if pendingCount > 1 {
                Button {
                    let n = appState.importSuggestedPrompts(report.suggestedPrompts)
                    feedback = n > 0 ? "已装入 \(n) 条技能" : "都已在键盘里了"
                } label: {
                    Label("全部装入键盘（\(pendingCount) 条）", systemImage: "square.and.arrow.down.on.square")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.accent))
                        .frame(minHeight: 36)
                }
            }
        } header: {
            Text("为你定制的技能 · \(report.suggestedPrompts.count)")
        }
    }

    private func phrasesSection(_ report: AIAutoInsightReport) -> some View {
        Section {
            ForEach(report.suggestedPhrases) { p in
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.slate))
                    Text(p.content)
                        .font(.subheadline)
                        .foregroundStyle(Color(Design.Palette.ink))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
            Button {
                let n = appState.importSuggestedPhrases(report.suggestedPhrases)
                feedback = n > 0 ? "已导入 \(n) 条短语" : "这些短语都已存在"
            } label: {
                Label("全部导入快捷短语", systemImage: "text.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.accent))
                    .frame(minHeight: 36)
            }
        } header: {
            Text("推荐短语 · \(report.suggestedPhrases.count)")
        }
    }
}
