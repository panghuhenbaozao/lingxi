import PhotosUI
import SwiftUI
import UIKit

/// 灵犀 AI 写作工作台 v5（3 模式：多话题多模态写作对话 / 博弈军师 / 跨渠道 PK）
/// 支持：多话题会话抽屉（新建/置顶/重命名/删除/导出 Markdown）、相册与剪贴板带图追问（纯文本模型自动 OCR 兜底）、
/// TTS 朗读、把多轮调教提炼为键盘自定义技能、System Prompt 透视镜与隐私脱敏护盾联动。
struct AIWorkbenchSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let initialTab: Int
    let initialDraft: String?

    @State private var tab = 0
    @State private var feedback: String?

    // MARK: Tab 0 - 多话题多模态写作对话
    @State private var threads: [AIWorkbenchThread] = []
    @State private var activeThreadID: String = ""
    @State private var showThreadsSheet = false
    @State private var draftInput = ""
    @State private var attachedPhotoItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    @State private var selectedSkillID: String = "free" // "free" | "builtin:<raw>" | "custom:<id>"
    @State private var overrideScene: AIScenePersona = .auto
    @State private var overrideThinking: AIThinkingMode = .auto
    @State private var streamingAnswer = ""
    @State private var streamingThought = ""
    @State private var expandedThoughtIDs: Set<String> = []
    @State private var showPromptInspector = false
    @State private var confirmClearChat = false
    @State private var isDistillingSkill = false
    @State private var chatError: String?
    @State private var isRunning = false
    @State private var activeTask: Task<Void, Never>?
    @StateObject private var speaker = AISpeechSpeaker()

    // MARK: Tab 1 - 博弈军师
    @State private var strategistInput = "领导说周六临时加班，但我家里约好了聚餐，帮我委婉回复。"
    @State private var strategistResult: NegotiationStrategistResult?
    @State private var strategistError: String?

    // MARK: Tab 2 - 跨渠道 PK
    @State private var pkInput = "领导说周六临时加班，但我家里约好了聚餐，帮我委婉回复。"
    @State private var pkSkill: AIPresetAction = .eqReply
    @State private var profileAID: String = "" // "" = 当前渠道
    @State private var profileBID: String = ""
    @State private var modelA = ""
    @State private var modelB = ""
    @State private var outA = ""
    @State private var outB = ""
    @State private var thoughtA = ""
    @State private var thoughtB = ""
    @State private var showThoughtA = false
    @State private var showThoughtB = false
    @State private var ttftA: Int?
    @State private var ttftB: Int?
    @State private var msA: Int?
    @State private var msB: Int?
    @State private var failedA = false
    @State private var failedB = false

    private let client = AIClient(timeout: 55)

    private struct QuickExample: Identifiable {
        let title: String
        let text: String
        var id: String { title }
    }

    private static let strategistSamples: [QuickExample] = [
        QuickExample(title: "周末加班", text: "领导说周六临时加班，但我家里约好了聚餐，帮我委婉回复。"),
        QuickExample(title: "临时加需求", text: "产品经理周五下午五点说下周一上线前临时再加两个新页面，怎么高情商守住底线？"),
        QuickExample(title: "朋友借钱", text: "不太熟的老同学突然发微信问能不能借两万周转一个月，怎么体面拒绝？"),
        QuickExample(title: "同事甩锅", text: "项目延期了，同事在群里暗示是开发这边提测晚，怎么客观体面澄清？"),
    ]

    private static let quickFollowUps: [String] = [
        "再委婉自然一点", "精简到一半字数", "换成正式商务口吻", "译成地道英文", "多给 2 个备选说法"
    ]

    init(initialTab: Int = 0, initialDraft: String? = nil) {
        self.initialTab = initialTab
        self.initialDraft = initialDraft
        _tab = State(initialValue: initialTab)
    }

    private var activeThreadIndex: Int? {
        threads.firstIndex(where: { $0.id == activeThreadID })
    }

    private var activeThreadTitle: String {
        guard let idx = activeThreadIndex else { return "新对话" }
        return threads[idx].title
    }

    private var turns: [AIChatTurn] {
        guard let idx = activeThreadIndex else { return [] }
        return threads[idx].turns
    }

    private var activeSkillDescriptor: (title: String, systemPrompt: String, preferDeep: Bool) {
        if selectedSkillID.hasPrefix("builtin:") {
            let raw = String(selectedSkillID.dropFirst("builtin:".count))
            if let act = AIPresetAction(rawValue: raw) {
                return (act.title, act.systemPrompt, act.prefersDeepModel)
            }
        } else if selectedSkillID.hasPrefix("custom:") {
            let cid = String(selectedSkillID.dropFirst("custom:".count))
            if let tpl = appState.aiConfig.customPrompts.first(where: { $0.id == cid }) {
                return (tpl.title, tpl.effectiveSystemPrompt, tpl.useDeepModel)
            }
        }
        return (
            "自由写作对话",
            "你是「灵犀输入法」内置的个人中文写作与沟通助手。根据用户意图直接给出自然、得体、可发送的高质量结果，支持多轮按用户追问不断精修。",
            false
        )
    }

    private var effectiveChatConfig: AIConfig {
        var cfg = appState.aiConfig
        cfg.activeScenePersona = overrideScene
        cfg.thinkingMode = overrideThinking
        return cfg
    }

    private var freshCurrentChannelModels: [String] {
        let c = appState.aiConfig
        guard !c.fetchedModels.isEmpty,
              c.fetchedModelsSourceKey.isEmpty || c.fetchedModelsSourceKey == c.currentModelsSourceKey else {
            return []
        }
        return Array(c.fetchedModels.filter(\.isChatModel).map(\.id).prefix(40))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("工作台模式", selection: $tab) {
                    Text("写作对话").tag(0)
                    Text("博弈军师").tag(1)
                    Text("跨渠道 PK").tag(2)
                }
                .pickerStyle(.segmented)
                .disabled(isRunning)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGroupedBackground))

                if tab == 0 {
                    chatWorkbenchBody
                } else if tab == 1 {
                    strategistBody
                } else {
                    arenaPKBody
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("灵犀 AI 工作台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        activeTask?.cancel()
                        speaker.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if tab == 0 {
                        Menu {
                            Button {
                                startNewThread()
                            } label: {
                                Label("新建话题对话", systemImage: "square.and.pencil")
                            }
                            Button {
                                showThreadsSheet = true
                            } label: {
                                Label("管理全部话题（\(threads.count)）", systemImage: "list.bullet.rectangle")
                            }
                            Button {
                                if let img = UIPasteboard.general.image {
                                    attachedImage = img
                                    feedback = "已附带剪贴板截图"
                                } else {
                                    feedback = "剪贴板里没有图片"
                                }
                            } label: {
                                Label("附带剪贴板截图", systemImage: "doc.on.clipboard")
                            }
                            Divider()
                            Button {
                                showPromptInspector = true
                            } label: {
                                Label("透视完整 System Prompt", systemImage: "doc.text.magnifyingglass")
                            }
                            if !turns.isEmpty {
                                Button {
                                    distillConversationIntoSkill()
                                } label: {
                                    Label(isDistillingSkill ? "正在提炼…" : "把本次调教提炼为键盘技能", systemImage: "wand.and.stars")
                                }
                                .disabled(isDistillingSkill || !appState.aiConfig.isConfigured)

                                Button {
                                    if let idx = activeThreadIndex {
                                        UIPasteboard.general.string = threads[idx].exportMarkdown()
                                        feedback = "已复制整段对话为 Markdown"
                                    }
                                } label: {
                                    Label("复制对话 (Markdown)", systemImage: "doc.on.doc")
                                }

                                Button(role: .destructive) {
                                    confirmClearChat = true
                                } label: {
                                    Label("清空当前话题消息", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("更多操作")
                    }
                }
            }
            .lxToast($feedback)
            .confirmationDialog("清空当前话题的所有消息？", isPresented: $confirmClearChat, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    if let idx = activeThreadIndex {
                        threads[idx].turns = []
                        threads[idx].updatedAt = Date()
                        AIWorkbenchThreadsStore.save(threads)
                    }
                    streamingAnswer = ""
                    streamingThought = ""
                    chatError = nil
                    feedback = "已清空当前话题消息"
                }
            } message: {
                Text("清空后可在当前话题重新开始提问，不会影响其他历史话题。")
            }
            .sheet(isPresented: $showPromptInspector) {
                SystemPromptInspectorSheet(
                    skillTitle: activeSkillDescriptor.title,
                    mergedPrompt: AIClient.mergeSystem(base: activeSkillDescriptor.systemPrompt, config: effectiveChatConfig),
                    config: effectiveChatConfig
                )
            }
            .sheet(isPresented: $showThreadsSheet) {
                AIWorkbenchThreadsSheet(
                    threads: $threads,
                    activeThreadID: $activeThreadID,
                    onNewThread: { startNewThread() },
                    onNotify: { feedback = $0 }
                )
            }
            .onChange(of: attachedPhotoItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            attachedImage = img
                            feedback = "已附带图片，输入问题后即可带图提问"
                        }
                    }
                }
            }
            .onAppear {
                loadThreadsIfNeeded()
                overrideScene = appState.aiConfig.activeScenePersona
                overrideThinking = appState.aiConfig.thinkingMode
                if let d = initialDraft, !d.isEmpty {
                    draftInput = d
                }
                modelA = appState.aiConfig.activeModelName
                modelB = appState.aiConfig.deepModel.isEmpty
                    ? (freshCurrentChannelModels.first(where: { $0 != modelA }) ?? modelA)
                    : appState.aiConfig.deepModel
            }
            .onDisappear {
                activeTask?.cancel()
                speaker.stop()
            }
        }
    }

    private func loadThreadsIfNeeded() {
        if threads.isEmpty {
            let loaded = AIWorkbenchThreadsStore.load()
            if loaded.isEmpty {
                let first = AIWorkbenchThread(title: "新对话")
                threads = [first]
                activeThreadID = first.id
            } else {
                threads = loaded
                activeThreadID = loaded[0].id
            }
        }
    }

    private func startNewThread() {
        let fresh = AIWorkbenchThread(title: "新对话", skillID: selectedSkillID)
        threads.insert(fresh, at: 0)
        activeThreadID = fresh.id
        streamingAnswer = ""
        streamingThought = ""
        chatError = nil
        attachedImage = nil
        AIWorkbenchThreadsStore.save(threads)
        feedback = "已开启新话题对话"
    }

    // MARK: - Tab 0：多话题多模态写作对话

    private var chatWorkbenchBody: some View {
        VStack(spacing: 0) {
            // 顶部话题切换栏
            HStack(spacing: 8) {
                Button {
                    showThreadsSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tray.2.fill")
                            .font(.caption2)
                        Text(activeThreadTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("(\(threads.count))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .foregroundStyle(Color(Design.Palette.ink))
                    .background(Color(Design.Palette.canvas), in: Capsule())
                    .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .disabled(isRunning)

                Button {
                    startNewThread()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.accent))
                        .frame(width: 28, height: 28)
                        .background(Color(Design.Palette.accentSoft), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .accessibilityLabel("新建话题")

                Spacer()

                if appState.aiConfig.privacyShieldEnabled {
                    LXTag(text: "脱敏护盾", icon: "checkmark.shield.fill", tint: Color(Design.Palette.success), filled: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            // 技能条
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    skillChip(id: "free", title: "自由对话")
                    ForEach(appState.aiConfig.resolvedKeyboardBuiltinActions.filter { $0 != .strategist }) { act in
                        skillChip(id: "builtin:\(act.rawValue)", title: act.title)
                    }
                    ForEach(appState.aiConfig.customPrompts.prefix(8)) { tpl in
                        skillChip(id: "custom:\(tpl.id)", title: tpl.title)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(AIScenePersona.allCases) { sc in
                        Button {
                            overrideScene = sc
                        } label: {
                            if overrideScene == sc {
                                Label(sc.shortTitle, systemImage: "checkmark")
                            } else {
                                Text(sc.shortTitle)
                            }
                        }
                    }
                } label: {
                    LXTag(text: "对象: \(overrideScene.shortTitle)", icon: "person.2", tint: Color(Design.Palette.accent), filled: overrideScene != .auto)
                }

                Menu {
                    ForEach(AIThinkingMode.allCases) { mode in
                        Button {
                            overrideThinking = mode
                        } label: {
                            if overrideThinking == mode {
                                Label(mode.displayName, systemImage: "checkmark")
                            } else {
                                Text(mode.displayName)
                            }
                        }
                    }
                } label: {
                    LXTag(text: "思考: \(overrideThinking.shortBadge)", icon: "brain", tint: Color(Design.Palette.slate))
                }

                Spacer()

                Button {
                    showPromptInspector = true
                } label: {
                    Label("透视 Prompt", systemImage: "eye")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.stone))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !appState.aiConfig.isConfigured {
                            notConfiguredCard
                        }

                        if turns.isEmpty && streamingAnswer.isEmpty && streamingThought.isEmpty {
                            emptyChatGuidance
                        }

                        ForEach(turns) { turn in
                            chatBubble(turn)
                                .id(turn.id)
                        }

                        if isRunning || !streamingAnswer.isEmpty || !streamingThought.isEmpty {
                            streamingBubble
                                .id("streaming-bubble")
                        }

                        if let err = chatError {
                            workbenchErrorCard(err)
                        }
                    }
                    .lxReadableWidth()
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: turns.count) { _ in
                    if let lastID = turns.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            // 已有回复时提供一键追问芯片
            if !turns.isEmpty && !isRunning {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.quickFollowUps, id: \.self) { hint in
                            Button {
                                sendChatMessage(hint)
                            } label: {
                                Text(hint)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .padding(.horizontal, 11)
                                    .frame(height: 30)
                                    .background(Color(Design.Palette.canvas), in: Capsule())
                                    .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }

            // 底部输入条（支持附带相册图片或粘贴剪贴板截图多模态提问）
            VStack(spacing: 0) {
                Divider()
                if let img = attachedImage {
                    HStack(spacing: 10) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("已附带 1 张图片")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            let visionCapable = ScreenshotOCRService.modelLikelySupportsVision(
                                modelID: appState.aiConfig.resolvedVisionModel(),
                                provider: appState.aiConfig.provider
                            )
                            Text(visionCapable ? "将直连视觉模型识别" : "当前模型为纯文本，将自动本机 OCR 提取文字后再提问")
                                .font(.caption2)
                                .foregroundStyle(Color(Design.Palette.stone))
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            attachedImage = nil
                            attachedPhotoItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除图片")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    PhotosPicker(selection: $attachedPhotoItem, matching: .images) {
                        Image(systemName: attachedImage == nil ? "photo.on.rectangle.angled" : "photo.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(attachedImage == nil ? Color(Design.Palette.stone) : Color(Design.Palette.accent))
                            .frame(width: 36, height: 40)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)
                    .accessibilityLabel("从相册添加图片")

                    TextField(attachedImage == nil ? "输入需求或粘贴草稿，支持多轮追问…" : "问问这张图（如：帮我高情商回复）…", text: $draftInput, axis: .vertical)
                        .lineLimit(1...5)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .disabled(isRunning)

                    if isRunning {
                        Button {
                            activeTask?.cancel()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 40, height: 40)
                                .background(Color(Design.Palette.error), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("停止生成")
                    } else {
                        let canSend = appState.aiConfig.isConfigured && (!draftInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImage != nil)
                        Button {
                            let raw = draftInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            let msg = raw.isEmpty ? "请识别图片内容并给出高情商回复或要点总结。" : raw
                            draftInput = ""
                            sendChatMessage(msg)
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 40, height: 40)
                                .background(canSend ? Color(Design.Palette.accent) : Color(Design.Palette.muted), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .accessibilityLabel("发送")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
    }

    private func skillChip(id: String, title: String) -> some View {
        let active = selectedSkillID == id
        return Button {
            selectedSkillID = id
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.canvas), in: Capsule())
                .overlay(Capsule().stroke(active ? Color.clear : Color(Design.Palette.hairline), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
    }

    private var emptyChatGuidance: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LXIconTile(icon: "sparkles", size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("多话题 · 多模态个人写作工作台")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("已注入文风 DNA 与匹配知识卡 · 支持贴图提问与语音朗读")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }
                LXFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Self.strategistSamples) { sample in
                        Button {
                            draftInput = sample.text
                        } label: {
                            Text("试写：\(sample.title)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color(Design.Palette.accent))
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(Color(Design.Palette.accentSoft), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func chatBubble(_ turn: AIChatTurn) -> some View {
        let isUser = turn.role == "user"
        let isThoughtOpen = expandedThoughtIDs.contains(turn.id)
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if isUser {
                VStack(alignment: .trailing, spacing: 4) {
                    if turn.hasImageAttachment {
                        LXTag(text: "含图片附件", icon: "photo", tint: Color(Design.Palette.accent), filled: true)
                    }
                    Text(turn.content)
                        .font(.subheadline)
                        .foregroundStyle(Color(Design.Palette.canvas))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(Color(Design.Palette.ink), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                LXCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            LXTag(text: turn.skillTitle.isEmpty ? "AI" : turn.skillTitle, tint: Color(Design.Palette.accent), filled: true)
                            if !turn.model.isEmpty {
                                Text(turn.model)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(Color(Design.Palette.stone))
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let ttft = turn.ttftMs {
                                Text("首字 \(ttft)ms")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Color(Design.Palette.stone))
                            }
                        }

                        if !turn.thought.isEmpty {
                            Button {
                                if isThoughtOpen {
                                    expandedThoughtIDs.remove(turn.id)
                                } else {
                                    expandedThoughtIDs.insert(turn.id)
                                }
                            } label: {
                                Label(isThoughtOpen ? "收起思考过程（\(turn.thought.count) 字）" : "展开思考过程（\(turn.thought.count) 字）", systemImage: "brain")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.slate))
                            }
                            .buttonStyle(.plain)

                            if isThoughtOpen {
                                Text(turn.thought)
                                    .font(.caption)
                                    .foregroundStyle(Color(Design.Palette.stone))
                                    .lineSpacing(3)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .textSelection(.enabled)
                            }
                        }

                        LXMarkdownMessageView(text: turn.content, font: .body)

                        HStack(spacing: 8) {
                            Button {
                                UIPasteboard.general.string = turn.content
                                feedback = "已复制回答"
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                            Button {
                                speaker.toggleSpeak(turn.content, localeID: "zh-CN", id: turn.id)
                            } label: {
                                Label(speaker.isSpeaking && speaker.activeID == turn.id ? "停止" : "朗读", systemImage: "speaker.wave.2")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                            Button {
                                appState.addQuickPhrase(
                                    title: String((turn.skillTitle.isEmpty ? "AI回复" : turn.skillTitle).prefix(8)),
                                    content: turn.content,
                                    category: "AI收藏"
                                )
                                feedback = "已存为快捷短语"
                            } label: {
                                Label("存短语", systemImage: "text.badge.plus")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var streamingBubble: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(streamingAnswer.isEmpty && !streamingThought.isEmpty ? "深度思考中（\(streamingThought.count) 字）…" : "生成中…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.accent))
                }
                if !streamingThought.isEmpty {
                    Text(streamingThought)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(4)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                if !streamingAnswer.isEmpty {
                    Text(streamingAnswer)
                        .font(.body)
                        .foregroundStyle(Color(Design.Palette.ink))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func appendTurnToActiveThread(_ turn: AIChatTurn) {
        loadThreadsIfNeeded()
        guard let idx = activeThreadIndex else { return }
        if threads[idx].turns.isEmpty && turn.role == "user" {
            let autoTitle = String(turn.content.replacingOccurrences(of: "\n", with: " ").prefix(16))
            if !autoTitle.isEmpty {
                threads[idx].title = autoTitle
            }
        }
        threads[idx].turns.append(turn)
        threads[idx].updatedAt = Date()
        AIWorkbenchThreadsStore.save(threads)
    }

    private func sendChatMessage(_ text: String) {
        chatError = nil
        let skill = activeSkillDescriptor
        let pendingImage = attachedImage
        attachedImage = nil
        attachedPhotoItem = nil

        let userTurn = AIChatTurn(role: "user", content: text, skillTitle: skill.title, hasImageAttachment: pendingImage != nil)
        appendTurnToActiveThread(userTurn)

        let historySnapshot = Array(turns.suffix(12))
        let cfg = effectiveChatConfig
        isRunning = true
        streamingAnswer = ""
        streamingThought = ""

        activeTask = Task {
            let start = Date()
            var firstMs: Int?
            var accAns = ""
            var accThought = ""
            var usedModelName = cfg.resolvedModel(preferDeep: skill.preferDeep)
            defer {
                Task { @MainActor in
                    self.isRunning = false
                }
            }
            do {
                if let img = pendingImage,
                   let jpeg = img.jpegData(compressionQuality: 0.78) {
                    let visionModel = cfg.resolvedVisionModel()
                    if ScreenshotOCRService.modelLikelySupportsVision(modelID: visionModel, provider: cfg.provider) {
                        usedModelName = visionModel
                        for try await ev in client.streamVisionEvents(
                            imageData: jpeg,
                            mimeType: "image/jpeg",
                            prompt: text,
                            systemInstruction: skill.systemPrompt,
                            config: cfg,
                            featureTag: "workbench_vision",
                            thinkingOverride: cfg.thinkingMode
                        ) {
                            if Task.isCancelled { break }
                            if firstMs == nil { firstMs = Int(Date().timeIntervalSince(start) * 1000) }
                            switch ev {
                            case .thought(let t):
                                accThought += t
                                let snap = AITextSanitizer.clean(accThought, streaming: true)
                                await MainActor.run { self.streamingThought = snap }
                            case .answer(let a):
                                accAns += a
                                let snap = AITextSanitizer.cleanPreservingMarkdown(accAns, streaming: true)
                                await MainActor.run { self.streamingAnswer = snap }
                            }
                        }
                    } else {
                        // 纯文本模型自动本机 Vision OCR 兜底，绝不报 400
                        let ocrText = await ScreenshotOCRService.recognizeText(from: img)
                        var enrichedTurns = historySnapshot
                        if !enrichedTurns.isEmpty {
                            let extra = ocrText.isEmpty ? "（图片中未识别到清晰文字）" : "\n【图片本机 OCR 文字】\n\(ocrText)"
                            enrichedTurns[enrichedTurns.count - 1].content += extra
                        }
                        for try await ev in client.streamConversationEvents(
                            turns: enrichedTurns,
                            systemInstruction: skill.systemPrompt,
                            config: cfg,
                            featureTag: "workbench_vision",
                            preferDeep: skill.preferDeep,
                            allowMarkdown: true
                        ) {
                            if Task.isCancelled { break }
                            if firstMs == nil { firstMs = Int(Date().timeIntervalSince(start) * 1000) }
                            switch ev {
                            case .thought(let t):
                                accThought += t
                                let snap = AITextSanitizer.clean(accThought, streaming: true)
                                await MainActor.run { self.streamingThought = snap }
                            case .answer(let a):
                                accAns += a
                                let snap = AITextSanitizer.cleanPreservingMarkdown(accAns, streaming: true)
                                await MainActor.run { self.streamingAnswer = snap }
                            }
                        }
                    }
                } else {
                    for try await ev in client.streamConversationEvents(
                        turns: historySnapshot,
                        systemInstruction: skill.systemPrompt,
                        config: cfg,
                        featureTag: "workbench_chat",
                        preferDeep: skill.preferDeep,
                        allowMarkdown: true
                    ) {
                        if Task.isCancelled { break }
                        if firstMs == nil {
                            firstMs = Int(Date().timeIntervalSince(start) * 1000)
                        }
                        switch ev {
                        case .thought(let t):
                            accThought += t
                            let snap = AITextSanitizer.clean(accThought, streaming: true)
                            await MainActor.run { self.streamingThought = snap }
                        case .answer(let a):
                            accAns += a
                            let snap = AITextSanitizer.cleanPreservingMarkdown(accAns, streaming: true)
                            await MainActor.run { self.streamingAnswer = snap }
                        }
                    }
                }

                let finalAns = AITextSanitizer.cleanPreservingMarkdown(accAns, streaming: false)
                let finalThought = AITextSanitizer.clean(accThought, streaming: false)
                let total = Int(Date().timeIntervalSince(start) * 1000)
                let chosenModel = usedModelName
                await MainActor.run {
                    if !finalAns.isEmpty {
                        let assistantTurn = AIChatTurn(
                            role: "assistant",
                            content: finalAns,
                            thought: finalThought,
                            model: chosenModel,
                            skillTitle: pendingImage != nil ? "带图对话" : skill.title,
                            ttftMs: firstMs ?? total,
                            totalMs: total
                        )
                        self.appendTurnToActiveThread(assistantTurn)
                        AIRecentHistoryStore.record(title: skill.title, output: finalAns, prompt: text)
                    }
                    self.streamingAnswer = ""
                    self.streamingThought = ""
                    self.appState.refreshAll()
                }
            } catch {
                await MainActor.run {
                    self.streamingAnswer = ""
                    self.streamingThought = ""
                    if !Task.isCancelled {
                        self.chatError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func distillConversationIntoSkill() {
        let userMsgs = turns.filter { $0.role == "user" }.map(\.content).joined(separator: "；")
        guard !userMsgs.isEmpty else { return }
        isDistillingSkill = true
        let cfg = appState.aiConfig
        Task {
            defer { Task { @MainActor in isDistillingSkill = false } }
            do {
                let goal = "根据以下多轮调教需求，提炼成一个以后在键盘里一键就能复用的写作技能：\(String(userMsgs.prefix(260)))"
                let tpl = try await AIAutoInsightService.generateCustomPromptTemplate(fromGoal: goal, config: cfg, client: client)
                await MainActor.run {
                    appState.addOrUpdateCustomPrompt(tpl)
                    feedback = "已提炼为键盘技能「\(tpl.title)」"
                }
            } catch {
                await MainActor.run {
                    feedback = "提炼失败：\(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Tab 1：博弈军师

    private var strategistBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !appState.aiConfig.isConfigured {
                    notConfiguredCard
                }

                LXCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("粘贴对方发来的棘手消息")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.stone))
                            Spacer()
                            Button("粘贴") {
                                if let s = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
                                    strategistInput = s
                                    feedback = "已粘贴对方消息"
                                } else {
                                    feedback = ConcealedPasteboard.isConcealed() ? "保险箱受保护内容不可直接粘贴给 AI" : "剪贴板是空的"
                                }
                            }
                            .font(.caption.bold())
                            .foregroundStyle(Color(Design.Palette.accent))
                            .buttonStyle(.plain)
                        }

                        TextEditor(text: $strategistInput)
                            .font(.subheadline)
                            .frame(minHeight: 96)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .disabled(isRunning)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.strategistSamples) { sample in
                                    Button {
                                        strategistInput = sample.text
                                    } label: {
                                        Text(sample.title)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .frame(height: 30)
                                            .foregroundStyle(Color(Design.Palette.ink))
                                            .background(Color(Design.Palette.canvas), in: Capsule())
                                            .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isRunning)
                                }
                            }
                        }
                    }
                }

                if isRunning {
                    Button {
                        activeTask?.cancel()
                    } label: {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).tint(Color(Design.Palette.error))
                            Text("正在拆解潜台词… 点击停止")
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
                } else {
                    Button {
                        runStrategist()
                    } label: {
                        Label("拆解潜台词并生成 3 套回复策略", systemImage: "shield.lefthalf.filled")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(!appState.aiConfig.isConfigured || strategistInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let err = strategistError {
                    workbenchErrorCard(err)
                }

                if let result = strategistResult {
                    if !result.subtext.isEmpty {
                        LXCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("对方真实诉求 / 潜台词", systemImage: "eye.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.accent))
                                Text(result.subtext)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    ForEach(result.options) { opt in
                        LXCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(opt.tag)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color(Design.Palette.ink))
                                    Spacer()
                                    LXTag(text: opt.toneLabel)
                                }
                                Text(opt.reply)
                                    .font(.body)
                                    .foregroundStyle(Color(Design.Palette.charcoal))
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                HStack(spacing: 8) {
                                    Button {
                                        UIPasteboard.general.string = opt.reply
                                        feedback = "已复制「\(opt.tag)」回复"
                                    } label: {
                                        Label("复制", systemImage: "doc.on.doc")
                                    }
                                    .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                                    Button {
                                        appState.addQuickPhrase(title: String(opt.tag.prefix(8)), content: opt.reply, category: "博弈军师")
                                        feedback = "已存为快捷短语"
                                    } label: {
                                        Label("存短语", systemImage: "text.badge.plus")
                                    }
                                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                                    Button {
                                        draftInput = "请帮我把下面这条回复再微调一下：\n\(opt.reply)"
                                        tab = 0
                                    } label: {
                                        Label("去微调", systemImage: "bubble.left")
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
    }

    private func runStrategist() {
        let msg = strategistInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }
        strategistError = nil
        isRunning = true
        let cfg = appState.aiConfig
        activeTask = Task {
            defer { Task { @MainActor in self.isRunning = false } }
            do {
                let res = try await AIAutoInsightService.runNegotiationStrategist(message: msg, config: cfg, client: client)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.strategistResult = res
                    let summaryText = res.options.map { "\($0.tag)：\($0.reply)" }.joined(separator: "\n")
                    AIRecentHistoryStore.record(title: "博弈军师", output: summaryText, prompt: msg)
                    self.appState.refreshAll()
                }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        self.strategistError = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - Tab 2：跨渠道双模型 PK

    private var arenaPKBody: some View {
        let bothTimed = !failedA && !failedB && msA != nil && msB != nil
        let fasterA = bothTimed && (msA ?? 0) < (msB ?? 0)
        let fasterB = bothTimed && (msB ?? 0) < (msA ?? 0)
        let modelsMissing = modelA.trimmingCharacters(in: .whitespaces).isEmpty || modelB.trimmingCharacters(in: .whitespaces).isEmpty

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !appState.aiConfig.isConfigured && appState.aiConfig.profiles.isEmpty {
                    notConfiguredCard
                }

                LXCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("评测题目")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.stone))
                            Spacer()
                            Menu {
                                ForEach([AIPresetAction.eqReply, .polish, .translateEn, .summarize, .xiaohongshu, .funny], id: \.self) { act in
                                    Button(act.title) { pkSkill = act }
                                }
                            } label: {
                                LXTag(text: "技能: \(pkSkill.title)", icon: "wand.and.stars", tint: Color(Design.Palette.accent), filled: true)
                            }
                        }

                        TextEditor(text: $pkInput)
                            .font(.subheadline)
                            .frame(minHeight: 78)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .disabled(isRunning)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Self.strategistSamples.prefix(3)) { s in
                                    Button(s.title) { pkInput = s.text }
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .frame(height: 26)
                                        .foregroundStyle(Color(Design.Palette.ink))
                                        .background(Color(Design.Palette.surface), in: Capsule())
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                LXCard {
                    VStack(spacing: 8) {
                        pkSidePicker(badge: "A", profileID: $profileAID, modelText: $modelA)
                        HStack(spacing: 10) {
                            Rectangle().fill(Color(Design.Palette.hairline)).frame(height: 0.5)
                            Button {
                                let tmpProfile = profileAID
                                profileAID = profileBID
                                profileBID = tmpProfile
                                let tmpModel = modelA
                                modelA = modelB
                                modelB = tmpModel
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color(Design.Palette.stone))
                                    .frame(width: 32, height: 32)
                                    .background(Color(Design.Palette.surface), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isRunning)
                            .accessibilityLabel("交换 A 和 B")
                            Rectangle().fill(Color(Design.Palette.hairline)).frame(height: 0.5)
                        }
                        pkSidePicker(badge: "B", profileID: $profileBID, modelText: $modelB)
                    }
                }

                if isRunning {
                    Button {
                        activeTask?.cancel()
                    } label: {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).tint(Color(Design.Palette.error))
                            Text("停止对比")
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
                } else {
                    Button {
                        activeTask = Task { await runArenaPK() }
                    } label: {
                        Label("开始并排盲测对比", systemImage: "square.split.2x1")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(pkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || modelsMissing)
                }

                pkResultCard(
                    badge: "A",
                    profileName: profileDisplayName(profileAID),
                    model: modelA,
                    ttft: ttftA,
                    totalMs: msA,
                    thought: thoughtA,
                    showThought: $showThoughtA,
                    output: outA,
                    failed: failedA,
                    faster: fasterA
                )
                pkResultCard(
                    badge: "B",
                    profileName: profileDisplayName(profileBID),
                    model: modelB,
                    ttft: ttftB,
                    totalMs: msB,
                    thought: thoughtB,
                    showThought: $showThoughtB,
                    output: outB,
                    failed: failedB,
                    faster: fasterB
                )
            }
            .lxReadableWidth()
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func profileDisplayName(_ id: String) -> String {
        if id.isEmpty { return "当前渠道" }
        return appState.aiConfig.profiles.first(where: { $0.id == id })?.name ?? "当前渠道"
    }

    private func modelsForSide(profileID: String) -> [String] {
        if let prof = appState.aiConfig.profiles.first(where: { $0.id == profileID }) {
            let list = prof.fetchedModels.filter(\.isChatModel).map(\.id)
            return list.isEmpty ? [prof.model] : Array(list.prefix(40))
        }
        return freshCurrentChannelModels
    }

    private func pkSidePicker(badge: String, profileID: Binding<String>, modelText: Binding<String>) -> some View {
        let choices = modelsForSide(profileID: profileID.wrappedValue)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                badgeCircle(badge)
                if !appState.aiConfig.profiles.isEmpty {
                    Menu {
                        Button("当前活跃渠道") {
                            profileID.wrappedValue = ""
                            modelText.wrappedValue = appState.aiConfig.activeModelName
                        }
                        ForEach(appState.aiConfig.profiles) { p in
                            Button("\(p.name) · \(p.model)") {
                                profileID.wrappedValue = p.id
                                modelText.wrappedValue = p.model
                            }
                        }
                    } label: {
                        LXTag(text: profileDisplayName(profileID.wrappedValue), icon: "arrow.triangle.swap", tint: Color(Design.Palette.slate))
                    }
                    .disabled(isRunning)
                }
                TextField("模型 \(badge) ID", text: modelText, axis: .vertical)
                    .lineLimit(1...2)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.weight(.medium).monospaced())
                    .disabled(isRunning)
                if !choices.isEmpty {
                    Menu {
                        ForEach(choices, id: \.self) { id in
                            Button(id) { modelText.wrappedValue = id }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(Design.Palette.accent))
                            .frame(width: 30, height: 30)
                            .background(Color(Design.Palette.accentSoft), in: Circle())
                    }
                    .disabled(isRunning)
                }
            }
        }
    }

    private func pkResultCard(
        badge: String,
        profileName: String,
        model: String,
        ttft: Int?,
        totalMs: Int?,
        thought: String,
        showThought: Binding<Bool>,
        output: String,
        failed: Bool,
        faster: Bool
    ) -> some View {
        let placeholder = isRunning ? "生成中…" : "等待运行"
        let speed: Double? = {
            guard !failed, let m = totalMs, m > 0, !output.isEmpty else { return nil }
            return Double(output.count) / (Double(m) / 1000.0)
        }()
        return LXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    badgeCircle(badge)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.isEmpty ? "未填写模型" : model)
                            .font(.footnote.weight(.semibold).monospaced())
                            .foregroundStyle(Color(Design.Palette.ink))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(profileName)
                            .font(.caption2)
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    Spacer(minLength: 4)
                    if faster {
                        LXTag(text: "更快", icon: "bolt.fill", tint: Color(Design.Palette.success), filled: true)
                    }
                }

                if ttft != nil || totalMs != nil || !output.isEmpty {
                    LXFlowLayout(spacing: 6, lineSpacing: 4) {
                        if let t = ttft { LXTag(text: "首字 \(t)ms") }
                        if let m = totalMs { LXTag(text: "总计 \(m)ms") }
                        if let s = speed { LXTag(text: String(format: "%.1f 字/秒", s)) }
                        if !output.isEmpty && !failed { LXTag(text: "\(output.count) 字") }
                        if !thought.isEmpty { LXTag(text: "思考 \(thought.count) 字", tint: Color(Design.Palette.accent), filled: true) }
                    }
                }

                if !thought.isEmpty {
                    DisclosureGroup(isExpanded: showThought) {
                        Text(thought)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .padding(.top, 6)
                    } label: {
                        Label("思考过程", systemImage: "brain")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.slate))
                    }
                }

                Text(output.isEmpty ? placeholder : output)
                    .font(.subheadline)
                    .foregroundStyle(output.isEmpty ? Color(Design.Palette.muted) : (failed ? Color(Design.Palette.error) : Color(Design.Palette.ink)))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if !output.isEmpty && !failed && !isRunning {
                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = output
                            feedback = "已复制模型 \(badge) 的回答"
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                        Menu {
                            Button("设为主模型") {
                                applyWinningModel(model, profileID: badge == "A" ? profileAID : profileBID, slot: .primary)
                            }
                            Button("设为快模型") {
                                applyWinningModel(model, profileID: badge == "A" ? profileAID : profileBID, slot: .fast)
                            }
                            Button("设为深模型") {
                                applyWinningModel(model, profileID: badge == "A" ? profileAID : profileBID, slot: .deep)
                            }
                        } label: {
                            Label("采用此模型", systemImage: "star")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                        Spacer()
                    }
                }
            }
        }
    }

    private func applyWinningModel(_ model: String, profileID: String, slot: AIModelAssignTarget) {
        if let prof = appState.aiConfig.profiles.first(where: { $0.id == profileID }) {
            appState.aiConfig.activateProfile(prof)
        }
        switch slot {
        case .primary:
            appState.aiConfig.setActiveModel(model)
            feedback = "已将 \(model) 设为主模型"
        case .fast:
            appState.aiConfig.fastModel = model
            feedback = "已将 \(model) 设为快模型"
        case .deep:
            appState.aiConfig.deepModel = model
            feedback = "已将 \(model) 设为深模型"
        case .vision:
            appState.aiConfig.visionModel = model
            feedback = "已将 \(model) 设为视觉模型"
        }
    }

    private func buildPKConfig(profileID: String, model: String) -> AIConfig {
        var cfg: AIConfig
        if let prof = appState.aiConfig.profiles.first(where: { $0.id == profileID }) {
            cfg = appState.aiConfig.applying(profile: prof)
        } else {
            cfg = appState.aiConfig
        }
        cfg.setActiveModel(model)
        return cfg
    }

    @MainActor
    private func runArenaPK() async {
        isRunning = true
        outA = ""; outB = ""
        thoughtA = ""; thoughtB = ""
        ttftA = nil; ttftB = nil
        msA = nil; msB = nil
        failedA = false; failedB = false
        defer { isRunning = false }

        let cfgA = buildPKConfig(profileID: profileAID, model: modelA)
        let cfgB = buildPKConfig(profileID: profileBID, model: modelB)
        let promptText = pkInput
        let sys = pkSkill.systemPrompt

        async let taskA: Void = {
            let s = Date()
            var first: Int?
            var ansAcc = ""
            var thAcc = ""
            do {
                for try await ev in client.streamEvents(prompt: promptText, systemInstruction: sys, config: cfgA, featureTag: "arena_a") {
                    if Task.isCancelled { break }
                    if first == nil {
                        let f = Int(Date().timeIntervalSince(s) * 1000)
                        first = f
                        await MainActor.run { ttftA = f }
                    }
                    switch ev {
                    case .thought(let t):
                        thAcc += t
                        let snap = AITextSanitizer.clean(thAcc, streaming: true)
                        await MainActor.run { thoughtA = snap }
                    case .answer(let a):
                        ansAcc += a
                        let snap = AITextSanitizer.clean(ansAcc, streaming: true)
                        await MainActor.run { outA = snap }
                    }
                }
                let total = Int(Date().timeIntervalSince(s) * 1000)
                let cleanFinal = AITextSanitizer.clean(ansAcc, streaming: false)
                let stopped = Task.isCancelled
                await MainActor.run {
                    if !stopped {
                        outA = cleanFinal
                        msA = total
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        failedA = true
                        outA = error.localizedDescription
                    }
                }
            }
        }()

        async let taskB: Void = {
            let s = Date()
            var first: Int?
            var ansAcc = ""
            var thAcc = ""
            do {
                for try await ev in client.streamEvents(prompt: promptText, systemInstruction: sys, config: cfgB, featureTag: "arena_b") {
                    if Task.isCancelled { break }
                    if first == nil {
                        let f = Int(Date().timeIntervalSince(s) * 1000)
                        first = f
                        await MainActor.run { ttftB = f }
                    }
                    switch ev {
                    case .thought(let t):
                        thAcc += t
                        let snap = AITextSanitizer.clean(thAcc, streaming: true)
                        await MainActor.run { thoughtB = snap }
                    case .answer(let a):
                        ansAcc += a
                        let snap = AITextSanitizer.clean(ansAcc, streaming: true)
                        await MainActor.run { outB = snap }
                    }
                }
                let total = Int(Date().timeIntervalSince(s) * 1000)
                let cleanFinal = AITextSanitizer.clean(ansAcc, streaming: false)
                let stopped = Task.isCancelled
                await MainActor.run {
                    if !stopped {
                        outB = cleanFinal
                        msB = total
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        failedB = true
                        outB = error.localizedDescription
                    }
                }
            }
        }()

        _ = await (taskA, taskB)
        appState.refreshAll()
    }

    // MARK: - 通用辅助卡片

    private func badgeCircle(_ badge: String) -> some View {
        Text(badge)
            .font(.caption.bold())
            .foregroundStyle(badge == "A" ? Color.white : Color(Design.Palette.canvas))
            .frame(width: 24, height: 24)
            .background(badge == "A" ? Color(Design.Palette.accent) : Color(Design.Palette.ink), in: Circle())
    }

    private var notConfiguredCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.warning))
            Text("还没有填写 API Key。回到「AI 智脑」配置好模型后即可开始使用。")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(Design.Palette.ink))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(Design.Palette.warning).opacity(0.10), in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
    }

    private func workbenchErrorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.error))
            VStack(alignment: .leading, spacing: 3) {
                Text("请求失败")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(Design.Palette.error).opacity(0.08), in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
    }
}

/// 工作台多话题会话管理 Sheet（切换、新建、置顶、删除、导出 Markdown）
struct AIWorkbenchThreadsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var threads: [AIWorkbenchThread]
    @Binding var activeThreadID: String
    let onNewThread: () -> Void
    let onNotify: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onNewThread()
                        dismiss()
                    } label: {
                        Label("开启新话题对话", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                }

                Section("全部话题 · \(threads.count)") {
                    ForEach(threads) { th in
                        let isCurrent = th.id == activeThreadID
                        Button {
                            activeThreadID = th.id
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: th.isPinned ? "pin.fill" : "bubble.left.and.bubble.right")
                                    .font(.subheadline)
                                    .foregroundStyle(isCurrent ? Color(Design.Palette.accent) : Color(Design.Palette.stone))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(th.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color(Design.Palette.ink))
                                            .lineLimit(1)
                                        if isCurrent {
                                            LXTag(text: "当前", tint: Color(Design.Palette.accent), filled: true)
                                        }
                                    }
                                    Text("\(th.turns.count) 条消息 · \(th.updatedAt.formatted(.relative(presentation: .named)))")
                                        .font(.caption2)
                                        .foregroundStyle(Color(Design.Palette.stone))
                                }
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if threads.count > 1 {
                                Button(role: .destructive) {
                                    threads.removeAll { $0.id == th.id }
                                    if activeThreadID == th.id, let first = threads.first {
                                        activeThreadID = first.id
                                    }
                                    AIWorkbenchThreadsStore.save(threads)
                                    onNotify("已删除话题")
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            Button {
                                if let idx = threads.firstIndex(where: { $0.id == th.id }) {
                                    threads[idx].isPinned.toggle()
                                    AIWorkbenchThreadsStore.save(threads)
                                }
                            } label: {
                                Label(th.isPinned ? "取消置顶" : "置顶", systemImage: th.isPinned ? "pin.slash" : "pin")
                            }
                            .tint(Color(Design.Palette.accent))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("对话话题列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

/// System Prompt 透视镜：透明展示当前请求发给大模型的完整系统提示词与隐私护盾状态
struct SystemPromptInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let skillTitle: String
    let mergedPrompt: String
    let config: AIConfig
    @State private var toast: String?

    private var activeCardsCount: Int {
        config.contextCards.filter { $0.matches(scene: config.activeScenePersona) }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LXFlowLayout(spacing: 8, lineSpacing: 6) {
                        LXTag(text: "技能: \(skillTitle)", tint: Color(Design.Palette.accent), filled: true)
                        LXTag(text: "对象: \(config.activeScenePersona.shortTitle)")
                        LXTag(text: "命中知识卡: \(activeCardsCount) 张")
                        LXTag(text: config.privacyShieldEnabled ? "隐私脱敏: 已开启" : "隐私脱敏: 未开", tint: config.privacyShieldEnabled ? Color(Design.Palette.success) : Color(Design.Palette.slate), filled: config.privacyShieldEnabled)
                        LXTag(text: "共 \(mergedPrompt.count) 字")
                    }

                    LXCard {
                        Text(mergedPrompt)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color(Design.Palette.ink))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .lxReadableWidth()
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("System Prompt 透视镜")
            .navigationBarTitleDisplayMode(.inline)
            .lxToast($toast)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("复制") {
                        UIPasteboard.general.string = mergedPrompt
                        toast = "已复制完整 System Prompt"
                    }
                }
            }
        }
    }
}
