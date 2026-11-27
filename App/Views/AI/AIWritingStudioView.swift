import AVFoundation
import SwiftUI
import UIKit

/// 轻量复用的原生语音朗读器（App 内 AI 回答、翻译译文与模板成品一键播报，支持多语种 BCP-47 语音）
@MainActor
final class AISpeechSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    @Published var activeID: String?

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func toggleSpeak(_ text: String, localeID: String = "zh-CN", id: String = "default") {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if isSpeaking && activeID == id {
            stop()
            return
        }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = AVSpeechSynthesisVoice(language: localeID) ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        activeID = id
        isSpeaking = true
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        activeID = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.activeID = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.activeID = nil
        }
    }
}

/// 结构化场景模板写作工坊（12 套高频表单模板）+ 长文/群聊一键结构化拆解器
struct AIWritingStudioView: View {
    @EnvironmentObject private var appState: AppState
    let onSendToWorkbench: (String) -> Void

    struct FieldSpec: Identifiable {
        let id: String
        let label: String
        let placeholder: String
        var multiline: Bool = false
    }

    struct WritingTemplate: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let category: String
        let icon: String
        let preferDeep: Bool
        let fields: [FieldSpec]
        let systemPrompt: String
    }

    private static let templates: [WritingTemplate] = [
        // 职场汇报
        WritingTemplate(
            id: "tpl_weekly",
            title: "高分周报生成",
            subtitle: "核心产出 + 风险推进 + 下周计划",
            category: "职场汇报",
            icon: "doc.text.fill",
            preferDeep: true,
            fields: [
                FieldSpec(id: "done", label: "本周做了什么（可贴碎碎念）", placeholder: "如：修完支付偶发超时、跟客户过了二期需求、上线了新首页", multiline: true),
                FieldSpec(id: "metrics", label: "关键数据 / 成果（可选）", placeholder: "如：接口延迟降了 40%，转化提升 3%"),
                FieldSpec(id: "next", label: "下周重点或需要协调的事", placeholder: "如：需要设计周三前给图，周五灰发布"),
            ],
            systemPrompt: "你是资深职场周报顾问。把用户填写的要点整理成结构清晰、结果导向、量化突出的高质量中文周报（分为「本周核心进展」「风险与待协调」「下周计划」三块），直接可粘贴发群或邮件。"
        ),
        WritingTemplate(
            id: "tpl_meeting",
            title: "会议纪要整编",
            subtitle: "结论、待办、责任人一目了然",
            category: "职场汇报",
            icon: "list.bullet.clipboard",
            preferDeep: true,
            fields: [
                FieldSpec(id: "topic", label: "会议主题与参会方", placeholder: "如：Q2 增长评审会（产品/研发/运营）"),
                FieldSpec(id: "notes", label: "杂乱记录或口述草稿", placeholder: "粘贴原始笔记或语音转文字内容…", multiline: true),
            ],
            systemPrompt: "你是高效 PMO 助理。把杂乱会议记录提炼为标准清爽的会议纪要：会议结论、行动待办（每项写明动作+责任人+时间节点）、待决事项。"
        ),
        WritingTemplate(
            id: "tpl_ask_boss",
            title: "向上请示 / 汇报",
            subtitle: "结论先行 + 备选方案 + 请求拍板",
            category: "职场汇报",
            icon: "arrow.up.right.square.fill",
            preferDeep: false,
            fields: [
                FieldSpec(id: "issue", label: "遇到的问题或需拍板的事", placeholder: "如：第三方接口下周涨价，需要决定切方案 A 还是自建", multiline: true),
                FieldSpec(id: "options", label: "你准备的方案与倾向", placeholder: "如：建议先切备用方案成本降 30%，两周内平滑切换"),
            ],
            systemPrompt: "你是擅长向上管理的职场顾问。按「一句话结论/请示点 → 简要背景 → 推荐方案与利弊 → 请领导确认项」写出简洁稳重、方便老板一眼拍板的微信/钉钉消息。"
        ),
        WritingTemplate(
            id: "tpl_biz_email",
            title: "商务跟进邮件 / 消息",
            subtitle: "报价推进、合作对接、专业得体",
            category: "职场汇报",
            icon: "envelope.fill",
            preferDeep: false,
            fields: [
                FieldSpec(id: "recipient", label: "对方称呼与关系", placeholder: "如：王总（潜在企业客户）"),
                FieldSpec(id: "goal", label: "核心目的与下一步节点", placeholder: "如：跟进上周发送的方案报价，约本周四下午 20 分钟演示", multiline: true),
            ],
            systemPrompt: "你是资深商务沟通专家。写出专业真诚、不卑不亢、有清晰下一步行动指引（CTA）的跟进消息或邮件正文（含建议邮件主题行）。"
        ),
        // 高情商社交
        WritingTemplate(
            id: "tpl_decline",
            title: "高情商委婉拒绝",
            subtitle: "守住底线又不伤和气",
            category: "高情商社交",
            icon: "hand.raised.fill",
            preferDeep: false,
            fields: [
                FieldSpec(id: "who", label: "对方是谁", placeholder: "如：不太熟的老同学 / 跨部门同事 / 亲戚"),
                FieldSpec(id: "req", label: "对方提了什么要求", placeholder: "如：想借两万块周转 / 让我免费帮忙做一个 PPT", multiline: true),
                FieldSpec(id: "reason", label: "可使用的现实理由（可选）", placeholder: "如：最近买了定期理财 / 本周项目封版"),
            ],
            systemPrompt: "你是高情商沟通专家。写一段真诚有分寸、既明确拒绝又保留体面的中文回复，绝不模棱两可给对方留错误期待。"
        ),
        WritingTemplate(
            id: "tpl_nudge",
            title: "礼貌催进度 / 催款",
            subtitle: "不显得急躁又能锁定时间",
            category: "高情商社交",
            icon: "clock.badge.checkmark",
            preferDeep: false,
            fields: [
                FieldSpec(id: "who", label: "催谁", placeholder: "如：客户财务 / 合作方开发 / 同事"),
                FieldSpec(id: "matter", label: "催什么事 & 期望时间", placeholder: "如：上个月的尾款发票已开，希望本周五前打款", multiline: true),
            ],
            systemPrompt: "你是高情商协作沟通专家。写一段礼貌自然、既不咄咄逼人又能推动对方给出明确时间节点的微信消息。"
        ),
        WritingTemplate(
            id: "tpl_apology",
            title: "真诚道歉与挽回",
            subtitle: "担责不找借口 + 补救动作",
            category: "高情商社交",
            icon: "heart.text.square.fill",
            preferDeep: false,
            fields: [
                FieldSpec(id: "who", label: "对象（伴侣 / 朋友 / 客户 / 领导）", placeholder: "如：女朋友 / 重要客户"),
                FieldSpec(id: "mistake", label: "发生了什么 & 准备怎么补救", placeholder: "如：忘了纪念日 / 发错合同版本号，已立刻重发正确版", multiline: true),
            ],
            systemPrompt: "你是真诚沟通顾问。写一段诚恳承担责任、共情对方感受、给出明确补救措施、不推卸不敷衍的道歉回复。"
        ),
        WritingTemplate(
            id: "tpl_comfort",
            title: "暖心共情安慰",
            subtitle: "不讲大道理，真正接住情绪",
            category: "高情商社交",
            icon: "sun.max.fill",
            preferDeep: false,
            fields: [
                FieldSpec(id: "context", label: "对方遇到了什么烦心事", placeholder: "如：面试没过很沮丧 / 连续加班崩溃了", multiline: true),
            ],
            systemPrompt: "你是温暖细腻的朋友。写出真诚共情、接住对方情绪、不说教不灌鸡汤、让人看完心里一暖的聊天回复。"
        ),
        // 社媒创作
        WritingTemplate(
            id: "tpl_moments",
            title: "松弛高级朋友圈",
            subtitle: "有画面感、绝不矫情鸡汤",
            category: "社媒创作",
            icon: "camera.filters",
            preferDeep: false,
            fields: [
                FieldSpec(id: "scene", label: "拍了什么 / 发生了什么", placeholder: "如：雨后在街头喝到一杯好喝的手冲咖啡，顺手拍了晚霞", multiline: true),
                FieldSpec(id: "vibe", label: "想要的感觉", placeholder: "如：松弛幽默 / 极简留白 / 温柔记录"),
            ],
            systemPrompt: "你是朋友圈文案高手。给出 3 条风格各异、松弛有质感、1~3 句克制高级的朋友圈配文，严禁土味鸡汤。"
        ),
        WritingTemplate(
            id: "tpl_xhs",
            title: "小红书爆款图文",
            subtitle: "吸睛标题 + 干货分段 + 标签",
            category: "社媒创作",
            icon: "flame.fill",
            preferDeep: false,
            fields: [
                FieldSpec(id: "topic", label: "分享主题与亮点", placeholder: "如：分享一个零广告的 iOS 自签开源输入法，自带 AI 和九宫格", multiline: true),
                FieldSpec(id: "audience", label: "目标读者", placeholder: "如：iPhone 效率党 / 打工人"),
            ],
            systemPrompt: "你是小红书爆款内容策划。生成 3 个高点击率备选标题 + 节奏透气、真诚干货、有互动结尾的正文 + 5 个精准话题标签（不使用 Markdown 星号）。"
        ),
        WritingTemplate(
            id: "tpl_hook",
            title: "短视频 3 秒开场脚本",
            subtitle: "黄金开头 + 反转观点 + 结尾引导",
            category: "社媒创作",
            icon: "video.fill",
            preferDeep: false,
            fields: [
                FieldSpec(id: "topic", label: "视频核心主题", placeholder: "如：为什么 90% 的人用 AI 回复微信一眼就被识破", multiline: true),
            ],
            systemPrompt: "你是短视频编导。写出一份 30 秒口播脚本：3 秒抓人钩子开场、核心干货展开、金句收尾与评论互动问题，口语自然上嘴。"
        ),
        WritingTemplate(
            id: "tpl_bio",
            title: "个人简介 / 自我介绍",
            subtitle: "入群破冰 / 面试开场 / 个人主页",
            category: "社媒创作",
            icon: "person.text.rectangle.fill",
            preferDeep: false,
            fields: [
                FieldSpec(id: "scene", label: "使用场合", placeholder: "如：新部门入群自我介绍 / 行业交流会"),
                FieldSpec(id: "facts", label: "你的身份、擅长领域与小特点", placeholder: "如：iOS 工程师，爱折腾效率工具和咖啡", multiline: true),
            ],
            systemPrompt: "你是个人品牌顾问。写出真诚自然、让人一眼记住、不端着也不尬的自我介绍（提供 1 个简短版和 1 个完整版）。"
        ),
    ]

    private static let digestModes: [(id: String, title: String, instruction: String)] = [
        ("full", "全维拆解", "对这段长文/聊天记录做全维拆解，按以下 4 块清晰输出（纯文本无 Markdown 星号）：\n1. 一句话结论 (TL;DR)\n2. 核心要点（3~5 条）\n3. 行动待办与时间节点\n4. 关键数据 / 潜在风险提醒"),
        ("todo", "只抽待办", "从内容中精准提取所有需要跟进的行动项，按「序号. 事项｜负责人（若提及）｜截止时间（若提及）」输出清晰清单。"),
        ("quotes", "提炼金句", "提炼出最精华的 3~5 条核心观点与可直接引用的短金句。"),
        ("exec", "一页老板摘要", "改写为 150 字以内的高管一页摘要：先给结论与影响，再列 3 条关键支撑事实。"),
    ]

    @State private var mode = 0 // 0 = 模板工坊, 1 = 长文拆解
    @State private var selectedCategory = "全部"
    @State private var activeTemplate: WritingTemplate?

    // 长文拆解状态
    @State private var digestInput = ""
    @State private var digestModeID = "full"
    @State private var digestOutput = ""
    @State private var isDigesting = false
    @State private var digestError: String?
    @State private var digestTask: Task<Void, Never>?

    @StateObject private var speaker = AISpeechSpeaker()
    @State private var feedback: String?
    private let client = AIClient(timeout: 55)

    private let categories = ["全部", "职场汇报", "高情商社交", "社媒创作"]

    private var filteredTemplates: [WritingTemplate] {
        selectedCategory == "全部" ? Self.templates : Self.templates.filter { $0.category == selectedCategory }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("模式", selection: $mode) {
                    Text("12 套场景模板").tag(0)
                    Text("长文 / 群聊拆解").tag(1)
                }
                .pickerStyle(.segmented)

                if mode == 0 {
                    templatesGridBody
                } else {
                    longTextDigestBody
                }
            }
            .lxReadableWidth()
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("模板写作与长文拆解")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($feedback)
        .sheet(item: $activeTemplate) { tpl in
            WritingTemplateRunnerSheet(template: tpl, onSendToWorkbench: { draft in
                activeTemplate = nil
                onSendToWorkbench(draft)
            })
            .environmentObject(appState)
        }
        .onDisappear {
            digestTask?.cancel()
            speaker.stop()
        }
    }

    private var templatesGridBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        let active = selectedCategory == cat
                        Button(cat) {
                            selectedCategory = cat
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                        .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.canvas), in: Capsule())
                        .overlay(Capsule().stroke(active ? Color.clear : Color(Design.Palette.hairline), lineWidth: 1))
                        .buttonStyle(.plain)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(filteredTemplates) { tpl in
                    Button {
                        activeTemplate = tpl
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                LXIconTile(icon: tpl.icon, size: 34)
                                Spacer()
                                if tpl.preferDeep {
                                    LXTag(text: "深度", tint: Color(Design.Palette.accent), filled: true)
                                }
                            }
                            Text(tpl.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .lineLimit(1)
                            Text(tpl.subtitle)
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(Color(Design.Palette.canvas), in: RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                                .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var longTextDigestBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            LXCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("粘贴长文章、文档或群聊记录（\(digestInput.count) 字）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.stone))
                        Spacer()
                        Button("粘贴") {
                            if let s = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
                                digestInput = s
                                feedback = "已粘贴 \(s.count) 字"
                            } else if ConcealedPasteboard.isConcealed() {
                                feedback = "受保护的保险箱机密不可直接粘贴给 AI"
                            }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.accent))
                        .buttonStyle(.plain)
                        if !digestInput.isEmpty {
                            Button("清空") { digestInput = "" }
                                .font(.caption.bold())
                                .foregroundStyle(Color(Design.Palette.stone))
                                .buttonStyle(.plain)
                        }
                    }

                    TextEditor(text: $digestInput)
                        .font(.subheadline)
                        .frame(minHeight: 130)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .disabled(isDigesting)

                    LXFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Self.digestModes, id: \.id) { m in
                            let active = digestModeID == m.id
                            Button(m.title) {
                                digestModeID = m.id
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                            .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
                            .buttonStyle(.plain)
                            .disabled(isDigesting)
                        }
                    }
                }
            }

            if isDigesting {
                Button {
                    digestTask?.cancel()
                } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).tint(Color(Design.Palette.error))
                        Text("正在拆解核心要点… 点击停止")
                    }
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
            } else {
                Button {
                    runDigest()
                } label: {
                    Label("一键结构化拆解", systemImage: "text.magnifyingglass")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                .disabled(!appState.aiConfig.isConfigured || digestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let err = digestError {
                Text(err).font(.caption).foregroundStyle(Color(Design.Palette.error))
            }

            if !digestOutput.isEmpty {
                LXCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(digestOutput)
                            .font(.body)
                            .foregroundStyle(Color(Design.Palette.ink))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        if !isDigesting {
                            HStack(spacing: 8) {
                                Button {
                                    UIPasteboard.general.string = digestOutput
                                    feedback = "已复制拆解结果"
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                                Button {
                                    speaker.toggleSpeak(digestOutput, localeID: "zh-CN", id: "digest")
                                } label: {
                                    Label(speaker.isSpeaking && speaker.activeID == "digest" ? "停止" : "朗读", systemImage: "speaker.wave.2")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                                Button {
                                    onSendToWorkbench("基于下面这份拆解摘要，帮我继续深入分析或写成汇报：\n\(digestOutput)")
                                } label: {
                                    Label("去工作台", systemImage: "bubble.left")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                            }
                        }
                    }
                }
            }
        }
    }

    private func runDigest() {
        let src = digestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return }
        let selected = Self.digestModes.first(where: { $0.id == digestModeID }) ?? Self.digestModes[0]
        let cfg = appState.aiConfig
        digestError = nil
        digestOutput = ""
        isDigesting = true

        digestTask = Task {
            var acc = ""
            defer {
                Task { @MainActor in
                    isDigesting = false
                    appState.refreshAll()
                }
            }
            do {
                for try await d in client.streamText(
                    prompt: src,
                    systemInstruction: selected.instruction,
                    config: cfg,
                    featureTag: "long_text_digest",
                    preferDeep: true
                ) {
                    if Task.isCancelled { break }
                    acc += d
                    let snap = AITextSanitizer.clean(acc, streaming: true)
                    await MainActor.run { digestOutput = snap }
                }
                let finalTxt = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    digestOutput = finalTxt
                    if !finalTxt.isEmpty {
                        AIRecentHistoryStore.record(title: "长文拆解 · \(selected.title)", output: finalTxt, prompt: String(src.prefix(60)))
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { digestError = error.localizedDescription }
                }
            }
        }
    }
}

/// 模板表单填写与流式成稿 Sheet
struct WritingTemplateRunnerSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let template: AIWritingStudioView.WritingTemplate
    let onSendToWorkbench: (String) -> Void

    @State private var values: [String: String] = [:]
    @State private var extraTone = ""
    @State private var output = ""
    @State private var isRunning = false
    @State private var errorMsg: String?
    @State private var activeTask: Task<Void, Never>?
    @State private var feedback: String?
    @StateObject private var speaker = AISpeechSpeaker()

    private let client = AIClient(timeout: 55)

    private var hasAnyInput: Bool {
        values.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        LXIconTile(icon: template.icon, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(.headline)
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text(template.subtitle)
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                    }

                    LXCard {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(template.fields) { field in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(field.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color(Design.Palette.stone))
                                    TextField(
                                        field.placeholder,
                                        text: Binding(
                                            get: { values[field.id] ?? "" },
                                            set: { values[field.id] = $0 }
                                        ),
                                        axis: field.multiline ? .vertical : .horizontal
                                    )
                                    .lineLimit(field.multiline ? 3...6 : 1...2)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .disabled(isRunning)
                                }
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text("额外风格要求（可选）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.stone))
                                TextField("如：控制在 120 字内 / 结尾带一句轻松问候", text: $extraTone)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .disabled(isRunning)
                            }
                        }
                    }

                    if isRunning {
                        Button {
                            activeTask?.cancel()
                        } label: {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small).tint(Color(Design.Palette.error))
                                Text("正在撰稿… 点击停止")
                            }
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
                    } else {
                        Button {
                            generate()
                        } label: {
                            Label("结合我的文风 DNA 生成", systemImage: "sparkles")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                        .disabled(!appState.aiConfig.isConfigured || !hasAnyInput)
                    }

                    if let err = errorMsg {
                        Text(err).font(.caption).foregroundStyle(Color(Design.Palette.error))
                    }

                    if !output.isEmpty {
                        LXCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(output)
                                    .font(.body)
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)

                                if !isRunning {
                                    HStack(spacing: 8) {
                                        Button {
                                            UIPasteboard.general.string = output
                                            feedback = "已复制成品"
                                        } label: {
                                            Label("复制", systemImage: "doc.on.doc")
                                        }
                                        .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                                        Button {
                                            speaker.toggleSpeak(output, localeID: "zh-CN", id: "tpl")
                                        } label: {
                                            Label(speaker.isSpeaking ? "停止" : "朗读", systemImage: "speaker.wave.2")
                                        }
                                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                                        Button {
                                            appState.addQuickPhrase(title: String(template.title.prefix(8)), content: output, category: "模板成稿")
                                            feedback = "已存为快捷短语"
                                        } label: {
                                            Label("存短语", systemImage: "text.badge.plus")
                                        }
                                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                                        Button {
                                            onSendToWorkbench("请帮我基于下面这篇「\(template.title)」继续修改：\n\(output)")
                                        } label: {
                                            Label("微调", systemImage: "bubble.left")
                                        }
                                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                                    }
                                }
                            }
                        }
                    }
                }
                .lxReadableWidth()
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(template.title)
            .navigationBarTitleDisplayMode(.inline)
            .lxToast($feedback)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        activeTask?.cancel()
                        speaker.stop()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                activeTask?.cancel()
                speaker.stop()
            }
        }
    }

    private func generate() {
        var parts: [String] = []
        for field in template.fields {
            let v = (values[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty {
                parts.append("【\(field.label)】\n\(v)")
            }
        }
        let tone = extraTone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tone.isEmpty {
            parts.append("【额外风格要求】\(tone)")
        }
        let prompt = parts.joined(separator: "\n\n")
        guard !prompt.isEmpty else { return }

        let cfg = appState.aiConfig
        output = ""
        errorMsg = nil
        isRunning = true

        activeTask = Task {
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
                    systemInstruction: template.systemPrompt,
                    config: cfg,
                    featureTag: "writing_template",
                    preferDeep: template.preferDeep
                ) {
                    if Task.isCancelled { break }
                    acc += delta
                    let snap = AITextSanitizer.clean(acc, streaming: true)
                    await MainActor.run { output = snap }
                }
                let finalTxt = AITextSanitizer.clean(acc, streaming: false)
                await MainActor.run {
                    output = finalTxt
                    if !finalTxt.isEmpty {
                        AIRecentHistoryStore.record(title: template.title, output: finalTxt, prompt: String(prompt.prefix(60)))
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { errorMsg = error.localizedDescription }
                }
            }
        }
    }
}
