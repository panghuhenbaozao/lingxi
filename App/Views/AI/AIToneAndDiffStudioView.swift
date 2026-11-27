import SwiftUI
import UIKit

/// 可复用的红绿逐字 Diff 渲染视图（基于纯 Swift LCS 差分引擎）
struct LXDiffHighlightText: View {
    let report: AITextDiffEngine.DiffReport

    private var attributed: AttributedString {
        var result = AttributedString()
        for seg in report.segments {
            var part = AttributedString(seg.text)
            var container = AttributeContainer()
            switch seg.kind {
            case .equal:
                container.swiftUI.foregroundColor = Color(Design.Palette.ink)
            case .deleted:
                container.swiftUI.foregroundColor = Color(Design.Palette.error)
                container.swiftUI.strikethroughStyle = Text.LineStyle.single
                container.swiftUI.backgroundColor = Color(Design.Palette.error).opacity(0.12)
            case .inserted:
                container.swiftUI.foregroundColor = Color(Design.Palette.success)
                container.swiftUI.backgroundColor = Color(Design.Palette.success).opacity(0.14)
            }
            part.mergeAttributes(container, mergePolicy: .keepNew)
            result.append(part)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                LXTag(text: "删 \(report.deletedChars) 字", tint: Color(Design.Palette.error), filled: true)
                LXTag(text: "增 \(report.insertedChars) 字", tint: Color(Design.Palette.success), filled: true)
                LXTag(text: "改动 \(Int((report.changeRatio * 100).rounded()))%")
            }
            Text(attributed)
                .font(.body)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// 多风格三版并发改写 & 二维语气精调 + 红绿 Diff 对比实验室
struct AIToneAndDiffStudioView: View {
    @EnvironmentObject private var appState: AppState
    let onSendToWorkbench: (String) -> Void

    private struct StyleOption: Identifiable, Equatable {
        let id: String
        let title: String
        let badge: String
        let icon: String
        let instruction: String
    }

    private struct StyleBundle: Identifiable, Equatable {
        let id: String
        let title: String
        let styles: [StyleOption]
    }

    private static let bundles: [StyleBundle] = [
        StyleBundle(
            id: "workplace",
            title: "职场全能",
            styles: [
                StyleOption(id: "pro", title: "专业得体", badge: "稳重", icon: "briefcase.fill", instruction: "改写为专业得体、结论先行、分寸感极佳的职场沟通回复，不卑不亢。"),
                StyleOption(id: "warm", title: "温和亲切", badge: "高情商", icon: "heart.fill", instruction: "改写为温和真诚、令人舒服的高情商回复，化解生硬感同时守住意思。"),
                StyleOption(id: "concise", title: "极简干脆", badge: "省时间", icon: "bolt.fill", instruction: "压缩到最精炼的一两句话，去掉所有废话与客套，直达重点。"),
            ]
        ),
        StyleBundle(
            id: "social",
            title: "社交破冰",
            styles: [
                StyleOption(id: "empathy", title: "走心共情", badge: "有温度", icon: "sparkles", instruction: "改写为真诚走心、有共情力、像真人朋友聊天的自然消息。"),
                StyleOption(id: "humor", title: "机智幽默", badge: "轻松", icon: "face.smiling", instruction: "用机智幽默、略带网感但自然不油腻的方式表达，拉近距离。"),
                StyleOption(id: "boundary", title: "体面有边界", badge: "不委屈", icon: "shield.lefthalf.filled", instruction: "既照顾对方面子、又清晰守住个人边界，不留模糊误解空间。"),
            ]
        ),
        StyleBundle(
            id: "content",
            title: "社媒创作",
            styles: [
                StyleOption(id: "moments", title: "高级朋友圈", badge: "松弛", icon: "camera.filters", instruction: "改写为松弛克制、有画面感、绝不鸡汤的高级朋友圈配文（1-3 句）。"),
                StyleOption(id: "xhs", title: "小红书种草", badge: "吸睛", icon: "flame.fill", instruction: "改写为吸睛透气、有情绪共鸣的小红书风格文案，适当点缀自然 Emoji。"),
                StyleOption(id: "hook", title: "金句提炼", badge: "抓眼球", icon: "quote.opening", instruction: "提炼为 1~2 句极具传播力与记忆点的锐利短句/口播金句。"),
            ]
        ),
        StyleBundle(
            id: "formal",
            title: "正式多面",
            styles: [
                StyleOption(id: "official", title: "书面公文", badge: "严谨", icon: "doc.text.fill", instruction: "改写为逻辑严密、措辞规范、适合邮件或正式通告的书面中文。"),
                StyleOption(id: "english", title: "商务英文", badge: "Native", icon: "globe", instruction: "Rewrite into natural, idiomatic, concise professional English matching the exact intent. Output English only."),
                StyleOption(id: "classical", title: "典雅古风", badge: "凝练", icon: "scroll", instruction: "改写为凝练典雅、朗朗上口的半文白/古风短句。"),
            ]
        ),
    ]

    private static let quickSamples: [(title: String, text: String)] = [
        ("推迟方案", "今天太忙了，方案实在来不及，明早发给你行不行，不好意思哈"),
        ("拒绝加班", "领导我周六家里有聚餐实在来不了，能不能周日晚上远程把活干完"),
        ("催对方反馈", "你到底看没看我昨天发你的报价啊，客户这边一直在催我"),
    ]

    @State private var mode = 0 // 0 = 一键三版, 1 = 二维精调 + 红绿 Diff
    @State private var inputText = "今天太忙了，方案实在来不及，明早发给你行不行，不好意思哈"
    @State private var selectedBundleID = "workplace"

    // 三版并发输出状态
    @State private var outputs: [String: String] = [:]
    @State private var latencies: [String: Int] = [:]
    @State private var errors: [String: String] = [:]
    @State private var isGeneratingVariants = false
    @State private var activeTask: Task<Void, Never>?

    // 二维精调 + 红绿 Diff 状态
    @State private var formalityLevel: Double = 3 // 1...5
    @State private var lengthLevel: Double = 2    // 1...5
    @State private var tunedOutput = ""
    @State private var tunedTTFT: Int?
    @State private var showDiffMode = true
    @State private var isTuning = false
    @State private var tuneError: String?

    @State private var feedback: String?
    private let client = AIClient(timeout: 45)

    private var currentBundle: StyleBundle {
        Self.bundles.first(where: { $0.id == selectedBundleID }) ?? Self.bundles[0]
    }

    private var formalityLabel: String {
        switch Int(formalityLevel.rounded()) {
        case 1: return "极松弛口语"
        case 2: return "亲切自然"
        case 3: return "均衡得体"
        case 4: return "职场专业"
        default: return "庄重书面"
        }
    }

    private var lengthLabel: String {
        switch Int(lengthLevel.rounded()) {
        case 1: return "一句话极简"
        case 2: return "精炼短句"
        case 3: return "标准适中"
        case 4: return "细节充实"
        default: return "完整详尽"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("实验室模式", selection: $mode) {
                    Text("一次生成 3 版").tag(0)
                    Text("语气精调 & Diff").tag(1)
                }
                .pickerStyle(.segmented)
                .disabled(isGeneratingVariants || isTuning)

                inputCard

                if mode == 0 {
                    threeVariantsSection
                } else {
                    toneMatrixAndDiffSection
                }
            }
            .lxReadableWidth()
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("多风格改写与 Diff")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($feedback)
        .onDisappear {
            activeTask?.cancel()
        }
    }

    private var inputCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("输入草稿或对方消息")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.stone))
                    Spacer()
                    Button("粘贴") {
                        if let s = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
                            inputText = s
                            feedback = "已粘贴文本"
                        } else if ConcealedPasteboard.isConcealed() {
                            feedback = "受保护的保险箱机密不可直接粘贴给 AI"
                        }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.accent))
                    .buttonStyle(.plain)
                }

                TextEditor(text: $inputText)
                    .font(.subheadline)
                    .frame(minHeight: 82)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .disabled(isGeneratingVariants || isTuning)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.quickSamples, id: \.title) { sample in
                            Button(sample.title) {
                                inputText = sample.text
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .foregroundStyle(Color(Design.Palette.ink))
                            .background(Color(Design.Palette.surface), in: Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 模式 0：一次三版并发流式对比

    private var threeVariantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.bundles) { b in
                        let active = b.id == selectedBundleID
                        Button {
                            selectedBundleID = b.id
                        } label: {
                            Text(b.title)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                                .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.canvas), in: Capsule())
                                .overlay(Capsule().stroke(active ? Color.clear : Color(Design.Palette.hairline), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isGeneratingVariants)
                    }
                }
            }

            if isGeneratingVariants {
                Button {
                    activeTask?.cancel()
                } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).tint(Color(Design.Palette.error))
                        Text("三路并发生成中… 点击停止")
                    }
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
            } else {
                Button {
                    runThreeVariants()
                } label: {
                    Label("同时生成 3 版「\(currentBundle.title)」方案", systemImage: "square.stack.3d.up.fill")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                .disabled(!appState.aiConfig.isConfigured || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ForEach(currentBundle.styles) { style in
                variantCard(style)
            }
        }
    }

    private func variantCard(_ style: StyleOption) -> some View {
        let text = outputs[style.id] ?? ""
        let err = errors[style.id]
        let ms = latencies[style.id]
        return LXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    LXIconTile(icon: style.icon, size: 30)
                    Text(style.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    LXTag(text: style.badge, tint: Color(Design.Palette.accent), filled: true)
                    Spacer()
                    if let ms {
                        Text("\(ms) ms")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }

                if let err {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.error))
                } else {
                    Text(text.isEmpty ? (isGeneratingVariants ? "正在流式撰写…" : "点击上方按钮同时对比 3 种风格") : text)
                        .font(.body)
                        .foregroundStyle(text.isEmpty ? Color(Design.Palette.muted) : Color(Design.Palette.ink))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if !text.isEmpty && !isGeneratingVariants {
                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = text
                            feedback = "已复制「\(style.title)」版本"
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                        Button {
                            appState.addQuickPhrase(title: style.title, content: text, category: "AI三版")
                            feedback = "已存为快捷短语"
                        } label: {
                            Label("存短语", systemImage: "text.badge.plus")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                        Button {
                            onSendToWorkbench("请帮我把这版「\(style.title)」回复再微调一下：\n\(text)")
                        } label: {
                            Label("去微调", systemImage: "bubble.left")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                    }
                }
            }
        }
    }

    private func runThreeVariants() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let styles = currentBundle.styles
        let cfg = appState.aiConfig
        outputs = [:]
        latencies = [:]
        errors = [:]
        isGeneratingVariants = true

        activeTask = Task {
            defer {
                Task { @MainActor in
                    isGeneratingVariants = false
                    appState.refreshAll()
                }
            }
            await withTaskGroup(of: Void.self) { group in
                for style in styles {
                    group.addTask {
                        let start = Date()
                        var acc = ""
                        let sys = "\(style.instruction) 只直接输出最终可直接发送的正文，不要加标题或解释。"
                        do {
                            for try await delta in client.streamText(
                                prompt: prompt,
                                systemInstruction: sys,
                                config: cfg,
                                featureTag: "ai_three_variants",
                                preferFast: true
                            ) {
                                if Task.isCancelled { break }
                                acc += delta
                                let snap = AITextSanitizer.clean(acc, streaming: true)
                                await MainActor.run { outputs[style.id] = snap }
                            }
                            let finalTxt = AITextSanitizer.clean(acc, streaming: false)
                            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                            await MainActor.run {
                                outputs[style.id] = finalTxt
                                latencies[style.id] = elapsed
                            }
                        } catch {
                            if !Task.isCancelled {
                                await MainActor.run { errors[style.id] = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            await MainActor.run {
                let combined = styles.compactMap { s -> String? in
                    guard let out = outputs[s.id], !out.isEmpty else { return nil }
                    return "【\(s.title)】\(out)"
                }.joined(separator: "\n")
                if !combined.isEmpty {
                    AIRecentHistoryStore.record(title: "三版改写 · \(currentBundle.title)", output: combined, prompt: prompt)
                }
            }
        }
    }

    // MARK: - 模式 1：二维语气精调 + 红绿逐字 Diff

    private var toneMatrixAndDiffSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LXCard {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("正式度")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.stone))
                            Spacer()
                            LXTag(text: formalityLabel, tint: Color(Design.Palette.accent), filled: true)
                        }
                        Slider(value: $formalityLevel, in: 1...5, step: 1)
                            .tint(Color(Design.Palette.accent))
                            .disabled(isTuning)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("篇幅长度")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.stone))
                            Spacer()
                            LXTag(text: lengthLabel, tint: Color(Design.Palette.slate))
                        }
                        Slider(value: $lengthLevel, in: 1...5, step: 1)
                            .tint(Color(Design.Palette.accent))
                            .disabled(isTuning)
                    }
                }
            }

            if isTuning {
                Button {
                    activeTask?.cancel()
                } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).tint(Color(Design.Palette.error))
                        Text("精调改写中… 点击停止")
                    }
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
            } else {
                Button {
                    runToneTune()
                } label: {
                    Label("按「\(formalityLabel) · \(lengthLabel)」改写并标出 Diff", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                .disabled(!appState.aiConfig.isConfigured || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let err = tuneError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.error))
            }

            if !tunedOutput.isEmpty {
                LXCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker("视图", selection: $showDiffMode) {
                                Text("红绿 Diff 对比").tag(true)
                                Text("纯净成品").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 230)
                            Spacer()
                            if let ms = tunedTTFT {
                                Text("首字 \(ms)ms")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Color(Design.Palette.stone))
                            }
                        }

                        if showDiffMode {
                            let diff = AITextDiffEngine.diff(
                                original: inputText.trimmingCharacters(in: .whitespacesAndNewlines),
                                revised: tunedOutput
                            )
                            LXDiffHighlightText(report: diff)
                        } else {
                            Text(tunedOutput)
                                .font(.body)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }

                        if !isTuning {
                            HStack(spacing: 8) {
                                Button {
                                    UIPasteboard.general.string = tunedOutput
                                    feedback = "已复制改写成品"
                                } label: {
                                    Label("复制成品", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                                Button {
                                    inputText = tunedOutput
                                    feedback = "已替换原文，可继续二次精调"
                                } label: {
                                    Label("继续二改", systemImage: "arrow.uturn.up")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                                Button {
                                    onSendToWorkbench("请帮我继续润色这段文字：\n\(tunedOutput)")
                                } label: {
                                    Label("送工作台", systemImage: "bubble.left")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                            }
                        }
                    }
                }
            }
        }
    }

    private func runToneTune() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let fDesc = formalityLabel
        let lDesc = lengthLabel
        let sys = "你是精准的中文语气与篇幅精调编辑。严格按目标语气「\(fDesc)」与目标篇幅「\(lDesc)」改写用户的文字，保留核心事实与意图。只输出最终改写文本，不加任何解释或引号。"
        let cfg = appState.aiConfig
        tuneError = nil
        tunedOutput = ""
        tunedTTFT = nil
        isTuning = true

        activeTask = Task {
            let start = Date()
            var acc = ""
            defer {
                Task { @MainActor in
                    isTuning = false
                    appState.refreshAll()
                }
            }
            do {
                for try await delta in client.streamText(prompt: prompt, systemInstruction: sys, config: cfg, featureTag: "tone_tuner") {
                    if Task.isCancelled { break }
                    if tunedTTFT == nil {
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        await MainActor.run { tunedTTFT = ms }
                    }
                    acc += delta
                    let snap = AITextSanitizer.clean(acc, streaming: true)
                    await MainActor.run { tunedOutput = snap }
                }
                let finalTxt = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    tunedOutput = finalTxt
                    if !finalTxt.isEmpty {
                        AIRecentHistoryStore.record(title: "语气精调 · \(fDesc)", output: finalTxt, prompt: prompt)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { tuneError = error.localizedDescription }
                }
            }
        }
    }
}
