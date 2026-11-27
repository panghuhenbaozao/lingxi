import SwiftUI
import UIKit

/// 多模型并发圆桌会诊与主席融合工坊（Mixture-of-Agents / LLM Council）
/// - 支持跨协议、跨渠道（Gemini / Claude / DeepSeek / OpenAI / Qwen 等）并发 2–4 席位实时流式作答；
/// - 单模型用户亦可一键启用「多专家视角圆桌」（务实落地派 / 批判审校派 / 破局创意派），开箱即用；
/// - 全部席位作答后，一键触发「主席综合裁决」汇总共识、标出分歧并融合输出终极一版，支持逐席位红绿 Diff 对比。
struct AIMultiModelCouncilView: View {
    @EnvironmentObject private var appState: AppState
    var onOpenInWorkbench: ((String) -> Void)? = nil

    private enum CouncilMode: String, CaseIterable, Identifiable {
        case crossModel = "跨模型会诊"
        case multiPersona = "多专家视角"
        var id: String { rawValue }
    }

    private struct CouncilSeat: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let providerLabel: String
        let config: AIConfig
        let model: String
        let personaDirective: String
    }

    private struct SeatResultState: Identifiable {
        let seat: CouncilSeat
        var id: String { seat.id }
        var isStreaming: Bool = false
        var thought: String = ""
        var answer: String = ""
        var errorMessage: String? = nil
        var ttftMs: Int? = nil
        var totalMs: Int? = nil
        var showThought: Bool = false
    }

    private struct CouncilScenario: Identifiable {
        let id = UUID()
        let title: String
        let prompt: String
    }

    private static let scenarios: [CouncilScenario] = [
        CouncilScenario(
            title: "高难度沟通博弈",
            prompt: "客户临时要求下周一前加做 3 个大需求但不加预算，既不能丢单也不能让团队通宵。请帮我拟一段高情商、守住底线又能推进合作的微信回复。"
        ),
        CouncilScenario(
            title: "技术架构选型",
            prompt: "我们要为日活 10 万的移动端产品选型端云同步方案：方案 A 是自建 SQLite+FastAPI，方案 B 是 Cloudflare Workers+D1，请从延迟、成本、运维和 E2EE 隐私四维度给出实操结论。"
        ),
        CouncilScenario(
            title: "商业文案打磨",
            prompt: "我们做了一款 100% 端侧隐私保护、支持多模型 AI 润色与离线排版体检的 iOS 输入法，请写出 3 句能在 5 秒内打动效率极客的核心卖点 Slogan。"
        ),
        CouncilScenario(
            title: "复杂决策权衡",
            prompt: "目前手里有两个 Offer：A 是大厂稳定但业务偏边缘、薪资高 15%；B 是 AI 创业团队核心研发、期权多但节奏极快。请给我一套结构化决策框架和最容易被忽略的盲区。"
        ),
    ]

    @State private var mode: CouncilMode = .crossModel
    @State private var promptText = ""
    @State private var availableSeats: [CouncilSeat] = []
    @State private var selectedSeatIDs: Set<String> = []
    @State private var seatStates: [SeatResultState] = []
    @State private var isRunningCouncil = false
    @State private var councilTask: Task<Void, Never>?

    // 主席综合裁决（MoA Synthesizer）
    @State private var chairmanVerdict = ""
    @State private var chairmanThought = ""
    @State private var isRunningChairman = false
    @State private var showChairmanThought = false
    @State private var diffCompareSeatID: String? = nil
    @State private var chairmanTask: Task<Void, Never>?

    @State private var toastMessage: String?
    @State private var toastIsError = false

    private let client = AIClient(timeout: 60)

    private var completedSeatStates: [SeatResultState] {
        seatStates.filter { !$0.isStreaming && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                seatPickerCard
                promptInputCard
                if !seatStates.isEmpty {
                    councilResultsSection
                }
                if completedSeatStates.count >= 2 || !chairmanVerdict.isEmpty || isRunningChairman {
                    chairmanSynthesisCard
                }
            }
            .padding(16)
            .lxReadableWidth()
        }
        .background(Color(Design.Palette.surface).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("多模型圆桌会诊")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toastMessage, isError: toastIsError)
        .onAppear {
            rebuildAvailableSeats()
        }
        .onDisappear {
            councilTask?.cancel()
            chairmanTask?.cancel()
        }
    }

    // MARK: - 1. 顶部说明与模式切换卡

    private var headerCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LXIconTile(icon: "person.3.fill", size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mixture-of-Agents 并发圆桌")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("一次提问并发 2–4 个模型或专家视角实时流式作答，再由主席模型交叉校验、融合出终极一版。")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Picker("圆桌模式", selection: $mode) {
                    ForEach(CouncilMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isRunningCouncil || isRunningChairman)
                .onChange(of: mode) { _ in
                    rebuildAvailableSeats()
                }
            }
        }
    }

    // MARK: - 2. 参会席位选择（2–4 席位）

    private var seatPickerCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(mode == .crossModel ? "选择参会模型席位（已选 \(selectedSeatIDs.count)/4）" : "多专家视角席位（已选 \(selectedSeatIDs.count)/3）")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Spacer()
                    if mode == .crossModel && availableSeats.count < 2 {
                        LXTag(text: "仅 1 个模型，建议切多专家视角", tint: Color(Design.Palette.warning), filled: true)
                    }
                }

                if availableSeats.isEmpty {
                    Text("请先在「AI 智脑」首页配置至少一个模型或保存渠道档案。")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                } else {
                    LXFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(availableSeats) { seat in
                            let selected = selectedSeatIDs.contains(seat.id)
                            Button {
                                toggleSeat(seat)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.caption.weight(.semibold))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(seat.title)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text(seat.subtitle)
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(selected ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
                                .background(
                                    selected ? Color(Design.Palette.ink) : Color(Design.Palette.surface),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(selected ? Color.clear : Color(Design.Palette.hairline), lineWidth: 0.6)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isRunningCouncil)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 3. 提问输入与场景快填卡

    private var promptInputCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("圆桌议题 / 待打磨草稿")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Spacer()
                    Button {
                        if let clip = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
                            promptText = clip
                            showToast("已粘贴剪贴板内容")
                        } else {
                            showToast("剪贴板为空或受保险箱隐私保护")
                        }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunningCouncil)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.scenarios) { sc in
                            Button(sc.title) {
                                promptText = sc.prompt
                            }
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .foregroundStyle(Color(Design.Palette.ink))
                            .background(Color(Design.Palette.surface), in: Capsule())
                            .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.5))
                            .buttonStyle(.plain)
                            .disabled(isRunningCouncil)
                        }
                    }
                }

                TextField("输入你想让多个模型同台竞技的问题、难题或草稿…", text: $promptText, axis: .vertical)
                    .lineLimit(3...7)
                    .font(.subheadline)
                    .padding(10)
                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(Design.Palette.hairline), lineWidth: 0.6)
                    )
                    .disabled(isRunningCouncil)

                HStack(spacing: 10) {
                    if isRunningCouncil {
                        Button {
                            councilTask?.cancel()
                        } label: {
                            Label("停止并发会诊", systemImage: "stop.fill")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
                    } else {
                        Button {
                            startCouncil()
                        } label: {
                            Label("启动 \(selectedSeatIDs.count) 席并发圆桌", systemImage: "play.fill")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                        .disabled(!appState.aiConfig.isConfigured || selectedSeatIDs.isEmpty || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - 4. 各席位并发流式结果区

    private var councilResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("参会席位观点（\(completedSeatStates.count)/\(seatStates.count) 已完稿）")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                if isRunningCouncil {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 2)

            ForEach($seatStates) { $st in
                seatResultCard(state: $st)
            }
        }
    }

    private func seatResultCard(state: Binding<SeatResultState>) -> some View {
        let st = state.wrappedValue
        return LXCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(st.seat.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(Design.Palette.ink))
                        .lineLimit(1)
                    LXTag(text: st.seat.providerLabel)
                    Spacer()
                    if st.isStreaming {
                        ProgressView().controlSize(.mini)
                    } else if let ttft = st.ttftMs, let total = st.totalMs {
                        Text("首字 \(ttft)ms · \(String(format: "%.1fs", Double(total) / 1000.0))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }

                Text(st.seat.subtitle)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Color(Design.Palette.stone))
                    .lineLimit(1)

                if !st.thought.isEmpty {
                    Button {
                        state.showThought.wrappedValue.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.caption2)
                            Text("思考过程（\(st.thought.count) 字）")
                                .font(.caption2.weight(.semibold))
                            Spacer()
                            Image(systemName: st.showThought ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(Color(Design.Palette.stone))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if st.showThought {
                        Text(st.thought)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(Design.Palette.surfaceSoft), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .textSelection(.enabled)
                    }
                }

                if let err = st.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(Design.Palette.error))
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.error))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if st.answer.isEmpty && st.isStreaming {
                    Text("正在思考并流式生成…")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                } else {
                    LXMarkdownMessageView(text: st.answer, font: .subheadline)
                }

                if !st.isStreaming && !st.answer.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = st.answer
                            showToast("已复制「\(st.seat.title)」观点")
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                        if !chairmanVerdict.isEmpty {
                            let isComparing = diffCompareSeatID == st.id
                            Button {
                                diffCompareSeatID = isComparing ? nil : st.id
                            } label: {
                                Label(isComparing ? "收起对比" : "与主席 Diff", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: isComparing))
                        }

                        if let onOpenInWorkbench {
                            Button {
                                onOpenInWorkbench(st.answer)
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

    // MARK: - 5. 主席综合裁决（Mixture-of-Agents 终极融合卡）

    private var chairmanSynthesisCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    LXIconTile(icon: "sparkles", size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("主席综合裁决（MoA 融合终版）")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("交叉核验 \(completedSeatStates.count) 份方案，吸收各自最强论据并消解分歧，合成终极一版。")
                            .font(.caption2)
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    Spacer()
                }

                if isRunningChairman {
                    Button {
                        chairmanTask?.cancel()
                    } label: {
                        Label("停止融合", systemImage: "stop.fill")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
                } else {
                    Button {
                        runChairmanSynthesis()
                    } label: {
                        Label(chairmanVerdict.isEmpty ? "融合众家之长，生成终极一版" : "重新融合裁决", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(completedSeatStates.count < 2)
                }

                if !chairmanThought.isEmpty {
                    Button {
                        showChairmanThought.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain").font(.caption2)
                            Text("主席综合研判过程（\(chairmanThought.count) 字）").font(.caption2.weight(.semibold))
                            Spacer()
                            Image(systemName: showChairmanThought ? "chevron.up" : "chevron.down").font(.caption2)
                        }
                        .foregroundStyle(Color(Design.Palette.stone))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if showChairmanThought {
                        Text(chairmanThought)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(Design.Palette.surfaceSoft), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .textSelection(.enabled)
                    }
                }

                if !chairmanVerdict.isEmpty {
                    if let cmpID = diffCompareSeatID,
                       let seat = seatStates.first(where: { $0.id == cmpID }),
                       !seat.answer.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                LXTag(text: "红绿 Diff：对比「\(seat.seat.title)」→ 主席终版", tint: Color(Design.Palette.accent), filled: true)
                                Spacer()
                                Button("返回纯净终版") { diffCompareSeatID = nil }
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.accent))
                                    .buttonStyle(.plain)
                            }
                            let diff = AITextDiffEngine.diff(original: seat.answer, revised: chairmanVerdict)
                            LXDiffHighlightText(report: diff)
                        }
                        .padding(10)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        LXMarkdownMessageView(text: chairmanVerdict, font: .subheadline)
                            .padding(10)
                            .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if !isRunningChairman {
                        HStack(spacing: 8) {
                            Button {
                                UIPasteboard.general.string = chairmanVerdict
                                showToast("已复制主席终极版")
                            } label: {
                                Label("复制终版", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                            Button {
                                appState.addQuickPhrase(title: "圆桌终版", content: chairmanVerdict, category: "AI圆桌")
                                showToast("已存为快捷短语")
                            } label: {
                                Label("存短语", systemImage: "text.badge.plus")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                            if let onOpenInWorkbench {
                                Button {
                                    onOpenInWorkbench(chairmanVerdict)
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

    // MARK: - Logic

    private func rebuildAvailableSeats() {
        let c = appState.aiConfig
        var seats: [CouncilSeat] = []

        if mode == .multiPersona {
            let baseModel = c.activeModelName
            let hats: [(id: String, title: String, desc: String, directive: String)] = [
                ("hat_pragmatic", "务实执行官", "重落地与可执行步骤", "你是极度务实的执行专家。请聚焦可落地步骤、明确时间节点与最稳妥方案，避免空泛理论。"),
                ("hat_critic", "批判审校官", "找风险、漏洞与盲区", "你是冷静犀利的红队批判者。请直接指出隐含风险、逻辑漏洞、对方可能的反制点，并给出防踩坑对策。"),
                ("hat_creative", "破局创意官", "换维思考与高情商巧思", "你是擅长破局的顶级策略顾问。请跳出常规思路，给出令人眼前一亮、兼顾人情与效果的巧思方案。"),
            ]
            for h in hats {
                seats.append(CouncilSeat(
                    id: h.id,
                    title: h.title,
                    subtitle: "\(h.desc) · \(baseModel)",
                    providerLabel: c.provider.shortName,
                    config: c,
                    model: baseModel,
                    personaDirective: h.directive
                ))
            }
            availableSeats = seats
            selectedSeatIDs = Set(seats.map(\.id))
            return
        }

        // Cross-Model Mode: collect distinct configured models + profiles
        var seenKeys = Set<String>()
        func addSeat(id: String, title: String, cfg: AIConfig, model: String) {
            let clean = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, cfg.isConfigured else { return }
            let dedup = "\(cfg.provider.rawValue)|\(cfg.activeBaseURL)|\(clean)"
            guard seenKeys.insert(dedup).inserted else { return }
            seats.append(CouncilSeat(
                id: id,
                title: title,
                subtitle: clean,
                providerLabel: cfg.provider.shortName,
                config: cfg,
                model: clean,
                personaDirective: "你是圆桌专家成员之一，请独立、直接、清晰地给出你认为质量最高的回答，不要废话与套话。"
            ))
        }

        addSeat(id: "slot_primary", title: "当前主模型", cfg: c, model: c.activeModelName)
        if !c.deepModel.isEmpty {
            addSeat(id: "slot_deep", title: "深度模型", cfg: c, model: c.deepModel)
        }
        if !c.fastModel.isEmpty {
            addSeat(id: "slot_fast", title: "极速模型", cfg: c, model: c.fastModel)
        }
        for prof in c.profiles {
            let pCfg = c.applying(profile: prof)
            addSeat(id: "prof_\(prof.id)", title: prof.name, cfg: pCfg, model: prof.model)
        }

        availableSeats = seats
        if seats.count < 2 && c.isConfigured {
            // 只有一个可用模型时保留可选，但智能切入多专家视角提示用户无需多 Key 也能玩圆桌
            selectedSeatIDs = Set(seats.map(\.id))
        } else {
            selectedSeatIDs = Set(seats.prefix(3).map(\.id))
        }
    }

    private func toggleSeat(_ seat: CouncilSeat) {
        if selectedSeatIDs.contains(seat.id) {
            if selectedSeatIDs.count > 1 {
                selectedSeatIDs.remove(seat.id)
            }
        } else {
            if selectedSeatIDs.count >= 4 {
                showToast("最多同时并发 4 个席位")
                return
            }
            selectedSeatIDs.insert(seat.id)
        }
    }

    private func startCouncil() {
        let q = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let chosen = availableSeats.filter { selectedSeatIDs.contains($0.id) }
        guard !chosen.isEmpty else { return }

        councilTask?.cancel()
        chairmanTask?.cancel()
        chairmanVerdict = ""
        chairmanThought = ""
        diffCompareSeatID = nil
        isRunningCouncil = true
        seatStates = chosen.map { SeatResultState(seat: $0, isStreaming: true) }

        councilTask = Task {
            defer {
                Task { @MainActor in
                    isRunningCouncil = false
                    appState.refreshAll()
                }
            }
            await withTaskGroup(of: Void.self) { group in
                for seat in chosen {
                    group.addTask {
                        let started = Date()
                        var firstAt: Date? = nil
                        var thoughtAcc = ""
                        var answerAcc = ""
                        do {
                            for try await chunk in client.streamEvents(
                                prompt: q,
                                systemInstruction: seat.personaDirective,
                                config: seat.config,
                                featureTag: "ai_council_seat",
                                modelOverride: seat.model,
                                allowMarkdown: true
                            ) {
                                if Task.isCancelled { break }
                                if firstAt == nil { firstAt = Date() }
                                switch chunk {
                                case .thought(let t):
                                    thoughtAcc += t
                                case .answer(let a):
                                    answerAcc += a
                                }
                                let cleanAns = AITextSanitizer.cleanPreservingMarkdown(answerAcc, streaming: true)
                                let curThought = thoughtAcc
                                let curTTFT = firstAt.map { max(1, Int($0.timeIntervalSince(started) * 1000)) }
                                await MainActor.run {
                                    if let idx = seatStates.firstIndex(where: { $0.id == seat.id }) {
                                        seatStates[idx].thought = curThought
                                        seatStates[idx].answer = cleanAns
                                        seatStates[idx].ttftMs = curTTFT
                                    }
                                }
                            }
                            let finalAns = AITextSanitizer.cleanPreservingMarkdown(answerAcc, streaming: false)
                            let totalMs = max(1, Int(Date().timeIntervalSince(started) * 1000))
                            let finalTTFT = firstAt.map { max(1, Int($0.timeIntervalSince(started) * 1000)) } ?? totalMs
                            await MainActor.run {
                                if let idx = seatStates.firstIndex(where: { $0.id == seat.id }) {
                                    seatStates[idx].answer = finalAns
                                    seatStates[idx].ttftMs = finalTTFT
                                    seatStates[idx].totalMs = totalMs
                                    seatStates[idx].isStreaming = false
                                }
                            }
                        } catch {
                            let errDesc = Task.isCancelled ? nil : error.localizedDescription
                            await MainActor.run {
                                if let idx = seatStates.firstIndex(where: { $0.id == seat.id }) {
                                    seatStates[idx].errorMessage = errDesc
                                    seatStates[idx].isStreaming = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func runChairmanSynthesis() {
        let ready = completedSeatStates
        guard ready.count >= 2 else { return }
        let q = promptText.trimmingCharacters(in: .whitespacesAndNewlines)

        chairmanTask?.cancel()
        chairmanVerdict = ""
        chairmanThought = ""
        diffCompareSeatID = nil
        isRunningChairman = true

        var synthesisPrompt = "【原始议题】\n\(q)\n\n"
        for (idx, st) in ready.enumerated() {
            synthesisPrompt += "【席位 \(idx + 1)：\(st.seat.title) (\(st.seat.model))】\n\(st.answer)\n\n"
        }
        synthesisPrompt += "请综合以上 \(ready.count) 位专家的回答，完成最终融合裁决。"

        let chairmanSys = """
        你是圆桌会议主席（Mixture-of-Agents 终极融合器）。请交叉审阅所有参会模型的回答：
        1. 吸收各席位最准确、最有洞察、最可落地的精华部分；
        2. 发现并修正任何明显遗漏、自相矛盾或空洞套话；
        3. 直接输出一份比任意单一模型都更清晰、更完整、可直接使用的最终成品（若各席位存在关键分歧，在末尾用极简 1–2 句「分歧提示」点明即可）。结构清晰，必要时使用标题、要点列表与代码块，避免多余客套。
        """

        let cfg = appState.aiConfig
        chairmanTask = Task {
            var thoughtAcc = ""
            var answerAcc = ""
            defer {
                Task { @MainActor in
                    isRunningChairman = false
                    appState.refreshAll()
                }
            }
            do {
                for try await chunk in client.streamEvents(
                    prompt: synthesisPrompt,
                    systemInstruction: chairmanSys,
                    config: cfg,
                    featureTag: "ai_council_chairman",
                    preferDeep: true,
                    allowMarkdown: true
                ) {
                    if Task.isCancelled { break }
                    switch chunk {
                    case .thought(let t): thoughtAcc += t
                    case .answer(let a): answerAcc += a
                    }
                    let cleanAns = AITextSanitizer.cleanPreservingMarkdown(answerAcc, streaming: true)
                    let curThought = thoughtAcc
                    await MainActor.run {
                        chairmanThought = curThought
                        chairmanVerdict = cleanAns
                    }
                }
                let finalVerdict = AITextSanitizer.cleanPreservingMarkdown(answerAcc, streaming: false)
                await MainActor.run {
                    chairmanVerdict = finalVerdict
                    if !finalVerdict.isEmpty {
                        AIRecentHistoryStore.record(title: "圆桌主席融合", output: finalVerdict, prompt: q)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        showToast("主席融合失败：\(error.localizedDescription)", isError: true)
                    }
                }
            }
        }
    }

    private func showToast(_ msg: String, isError: Bool = false) {
        toastIsError = isError
        toastMessage = msg
    }
}
