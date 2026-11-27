import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 导出 Obsidian 兼容 `.md` 知识库文档
struct ObsidianMarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let str = String(data: data, encoding: .utf8) {
            self.text = str
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// 灵犀 Obsidian 风格「LLM Wiki + 双链图谱」自学习记忆库中枢
/// - 可视化交互知识图谱（点节点高亮 1-Hop 出链/反链）；
/// - 用用户自填 API 将打字记录、聊天历史与原始自述自动拆解为带 `[[双向链接]]` 与 YAML Frontmatter 的常青原子笔记；
/// - 支持点选 `[[双向链接]]` 自由跳转、查看反向链接、手动新建/编辑笔记、查看 `log.md` 演化日志与整库导出 Obsidian `.md`。
struct ObsidianVaultGraphView: View {
    private enum ActiveSheet: Identifiable {
        case inspectNote(String) // slug
        case newNote

        var id: String {
            switch self {
            case .inspectNote(let slug): return "inspect_\(slug)"
            case .newNote: return "newNote"
            }
        }
    }

    @EnvironmentObject private var appState: AppState

    @State private var notes: [ObsidianVaultNote] = []
    @State private var links: [VaultLinkEdge] = []
    @State private var logs: [VaultEvolutionLogEntry] = []
    @State private var selectedFolder: VaultNoteFolder? = nil
    @State private var searchQuery = ""
    @State private var selectedGraphSlug: String? = nil

    @State private var inboxDraft = ""
    @State private var activeSheet: ActiveSheet?
    @State private var exportDoc: ObsidianMarkdownDocument?
    @State private var showExporter = false
    @State private var feedback: String?
    @State private var feedbackIsError = false

    private var filteredNotes: [ObsidianVaultNote] {
        let byFolder = selectedFolder == nil ? notes : notes.filter { $0.folder == selectedFolder }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return byFolder }
        return byFolder.filter {
            $0.title.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
                || $0.bodyMarkdown.lowercased().contains(q)
                || $0.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }

    private var notesBySlug: [String: ObsidianVaultNote] {
        Dictionary(uniqueKeysWithValues: notes.map { ($0.slug, $0) })
    }

    var body: some View {
        List {
            apiSelfLearnSection
            knowledgeGraphSection
            notesListSection
            evolutionLogSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Obsidian 双链记忆库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeSheet = .newNote
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.accent))
                }
                .accessibilityLabel("新建原子笔记")
            }
        }
        .onAppear {
            reloadVault()
            if notes.isEmpty {
                _ = ObsidianMemoryVaultEngine.seedAndRefreshLocalVault(
                    db: .shared,
                    habitProfile: appState.habitProfile,
                    topUserWords: appState.userWords.prefix(20).map(\.word)
                )
                reloadVault()
            }
        }
        .lxToast($feedback, isError: feedbackIsError)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .inspectNote(let slug):
                ObsidianNoteDetailSheet(
                    initialSlug: slug,
                    onChanged: {
                        reloadVault()
                        appState.refreshCognitiveStats()
                    },
                    onToast: { msg in showFeedback(msg) }
                )
            case .newNote:
                ObsidianNewNoteSheet { title, folder, summary, body, tags in
                    appState.saveManualVaultNote(
                        title: title,
                        folder: folder,
                        summary: summary,
                        bodyMarkdown: body,
                        tags: tags,
                        isPinned: true
                    )
                    reloadVault()
                    showFeedback("已新建常青笔记「\(title)」并解析双链")
                }
            }
        }
    }

    // MARK: - 1. 用户 API 驱动自学习与收件箱提炼

    private var apiSelfLearnSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LXIconTile(icon: "sparkles", tint: Color(Design.Palette.accent), size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("API 驱动双链自学习引擎")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            LXTag(
                                text: appState.aiConfig.isConfigured ? "API 已就绪" : "本机模式",
                                tint: appState.aiConfig.isConfigured ? Color(Design.Palette.success) : Color(Design.Palette.warning),
                                filled: true
                            )
                        }
                        Text("\(notes.count) 篇原子笔记 · \(links.count) 条双向链接 · 2-Hop 图谱按需注入每次 AI 回复")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $inboxDraft)
                        .font(.footnote)
                        .frame(height: 68)
                        .padding(6)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if inboxDraft.isEmpty {
                                Text("可选：写两句个人习惯或偏好，让 AI 自动拆解入库…")
                                    .font(.caption)
                                    .foregroundStyle(Color(Design.Palette.muted))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                HStack(spacing: 8) {
                    Button {
                        let raw = inboxDraft
                        Task {
                            let res = await appState.runObsidianAPISelfLearning(rawInboxText: raw.isEmpty ? nil : raw)
                            await MainActor.run {
                                if !raw.isEmpty { inboxDraft = "" }
                                reloadVault()
                                showFeedback(res.summary)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if appState.isRunningObsidianLearn {
                                ProgressView().controlSize(.mini).tint(Color.white)
                                Text("提炼中…")
                            } else {
                                Image(systemName: "wand.and.stars")
                                Text(inboxDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "API 自学习" : "拆解并建双链")
                            }
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(appState.isRunningObsidianLearn)

                    Button {
                        let md = ObsidianMemoryVaultEngine.exportFullObsidianMarkdownVault(db: .shared)
                        exportDoc = ObsidianMarkdownDocument(text: md)
                        showExporter = true
                    } label: {
                        Label("导出 .md", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, tint: Color(Design.Palette.ink)))
                    .background(
                        Color.clear.fileExporter(
                            isPresented: $showExporter,
                            document: exportDoc,
                            contentType: .plainText,
                            defaultFilename: "lingxi-obsidian-vault.md"
                        ) { result in
                            switch result {
                            case .success:
                                showFeedback("已导出 Obsidian .md 双链知识库")
                            case .failure(let err):
                                let ns = err as NSError
                                if !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) {
                                    showFeedback("导出失败：\(err.localizedDescription)", isError: true)
                                }
                            }
                        }
                    )
                }

                if let outcome = appState.lastObsidianOutcome {
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
            .padding(.vertical, 4)
        }
    }

    // MARK: - 2. 可交互知识图谱画布（纯 SwiftUI Canvas + 节点胶囊）

    private var knowledgeGraphSection: some View {
        let graphNotes = Array(notes.filter { $0.folder != .inbox }.prefix(14))
        return Section {
            if graphNotes.isEmpty {
                LXEmptyState(
                    icon: "circle.hexagongrid",
                    title: "图谱等待激活",
                    message: "点上方「用我的 API 全库自学习演化」或新建原子笔记，即可生成你的专属双向知识图谱。"
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ObsidianInteractiveGraphCanvas(
                        notes: graphNotes,
                        links: links,
                        selectedSlug: $selectedGraphSlug
                    )
                    .frame(height: 230)
                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(Design.Palette.hairline), lineWidth: 0.6)
                    )

                    if let slug = selectedGraphSlug, let picked = notesBySlug[slug] {
                        let outCount = links.filter { $0.fromSlug == slug }.count
                        let backCount = links.filter { $0.toSlug == slug }.count
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("[[\(picked.title)]]")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color(Design.Palette.ink))
                                    LXTag(text: "出链 \(outCount) · 反链 \(backCount)", tint: Color(Design.Palette.accent), filled: true)
                                }
                                Text(picked.summary.isEmpty ? picked.bodyMarkdown : picked.summary)
                                    .font(.caption)
                                    .foregroundStyle(Color(Design.Palette.stone))
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            Button("打开") {
                                activeSheet = .inspectNote(picked.slug)
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                        }
                        .padding(10)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Text("轻点图谱中任意节点，高亮它的出链与反向链接关系并查看完整笔记。")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("关系图谱 (Graph View · \(graphNotes.count) 节点)")
        }
    }

    // MARK: - 3. 目录筛选 + 原子笔记浏览

    private var notesListSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        folderPill(title: "全部 (\(notes.count))", active: selectedFolder == nil) {
                            selectedFolder = nil
                        }
                        ForEach(VaultNoteFolder.allCases) { folder in
                            let count = notes.filter { $0.folder == folder }.count
                            folderPill(title: "\(folder.displayTitle) (\(count))", active: selectedFolder == folder) {
                                selectedFolder = folder
                            }
                        }
                    }
                }

                TextField("搜索标题、正文、[[双链]] 或 #标签…", text: $searchQuery)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.vertical, 2)

            if filteredNotes.isEmpty {
                Text("当前筛选条件下暂无原子笔记。")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            } else {
                ForEach(filteredNotes) { note in
                    let outCount = links.filter { $0.fromSlug == note.slug }.count
                    let backCount = links.filter { $0.toSlug == note.slug }.count
                    let effPct = Int(ObsidianMemoryVaultEngine.effectiveStrength(for: note) * 100)
                    Button {
                        activeSheet = .inspectNote(note.slug)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            LXIconTile(
                                icon: note.folder.icon,
                                tint: note.isPinned ? Color(Design.Palette.accent) : Color(Design.Palette.slate),
                                size: 32
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(note.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color(Design.Palette.ink))
                                    if note.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.caption2)
                                            .foregroundStyle(Color(Design.Palette.accent))
                                    }
                                    Spacer()
                                    Text("强度 \(effPct)%")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(Color(Design.Palette.stone))
                                }
                                Text(note.summary.isEmpty ? note.bodyMarkdown : note.summary)
                                    .font(.caption)
                                    .foregroundStyle(Color(Design.Palette.stone))
                                    .lineLimit(2)
                                HStack(spacing: 6) {
                                    LXTag(text: note.folder.displayTitle)
                                    LXTag(text: "→\(outCount) ←\(backCount)", tint: Color(Design.Palette.accent))
                                    if note.recallCount > 0 {
                                        LXTag(text: "召回 \(note.recallCount) 次", tint: Color(Design.Palette.success), filled: true)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            AICognitiveMemoryDB.shared.deleteVaultNote(slug: note.slug)
                            reloadVault()
                            appState.refreshCognitiveStats()
                            showFeedback("已删除笔记「\(note.title)」")
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            AICognitiveMemoryDB.shared.togglePinVaultNote(slug: note.slug)
                            reloadVault()
                        } label: {
                            Label(note.isPinned ? "取消置顶" : "置顶常青", systemImage: note.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(Color(Design.Palette.accent))
                    }
                }
            }
        } header: {
            Text("原子常青笔记（\(filteredNotes.count) 篇）")
        }
    }

    // MARK: - 4. Obsidian `log.md` 演化日志

    private var evolutionLogSection: some View {
        Section {
            if logs.isEmpty {
                Text("暂无演化日志。每次 API 提炼新笔记、建立双链或融合去重都会追加记录在这里。")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            } else {
                ForEach(Array(logs.prefix(15))) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            LXTag(text: entry.actionDisplayName, tint: Color(Design.Palette.accent), filled: true)
                            Text(entry.noteTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .lineLimit(1)
                            Spacer()
                            Text(Date(timeIntervalSince1970: TimeInterval(entry.createdAt)).formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("log.md · 记忆库自学习演化记录")
        }
    }

    private func folderPill(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func reloadVault() {
        let db = AICognitiveMemoryDB.shared
        notes = db.fetchVaultNotes(limit: 160)
        links = db.fetchAllVaultLinks(limit: 400)
        logs = db.fetchEvolutionLogs(limit: 40)
        if let sel = selectedGraphSlug, !notes.contains(where: { $0.slug == sel }) {
            selectedGraphSlug = nil
        }
    }

    private func showFeedback(_ msg: String, isError: Bool = false) {
        feedbackIsError = isError
        feedback = msg
    }
}

// MARK: - 交互式知识图谱视图（Canvas 连边 + 真实可点按节点）

private struct ObsidianInteractiveGraphCanvas: View {
    let notes: [ObsidianVaultNote]
    let links: [VaultLinkEdge]
    @Binding var selectedSlug: String?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let positions = computeNodePositions(for: notes, in: size)
            let activeNeighbors: Set<String> = {
                guard let sel = selectedSlug else { return [] }
                var s: Set<String> = [sel]
                for e in links {
                    if e.fromSlug == sel { s.insert(e.toSlug) }
                    if e.toSlug == sel { s.insert(e.fromSlug) }
                }
                return s
            }()

            ZStack {
                Canvas { ctx, size in
                    // 极简点阵画布背景（致敬 Obsidian / Linear Canvas）
                    let step: CGFloat = 20
                    let dotColor = Color(Design.Palette.hairline).opacity(0.75)
                    var y: CGFloat = step
                    while y < size.height {
                        var x: CGFloat = step
                        while x < size.width {
                            let rect = CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)
                            ctx.fill(Path(ellipseIn: rect), with: .color(dotColor))
                            x += step
                        }
                        y += step
                    }
                    for edge in links {
                        guard let p1 = positions[edge.fromSlug],
                              let p2 = positions[edge.toSlug] else { continue }
                        var path = Path()
                        path.move(to: p1)
                        path.addLine(to: p2)

                        let isHighlighted: Bool
                        let strokeColor: Color
                        if let sel = selectedSlug {
                            if edge.fromSlug == sel {
                                isHighlighted = true
                                strokeColor = Color(Design.Palette.accent)
                            } else if edge.toSlug == sel {
                                isHighlighted = true
                                strokeColor = Color(Design.Palette.success)
                            } else {
                                isHighlighted = false
                                strokeColor = Color(Design.Palette.hairline).opacity(0.45)
                            }
                        } else {
                            isHighlighted = false
                            strokeColor = Color(Design.Palette.slate).opacity(0.32)
                        }
                        ctx.stroke(path, with: .color(strokeColor), lineWidth: isHighlighted ? 2.0 : 1.0)
                    }
                }

                ForEach(notes) { note in
                    if let pt = positions[note.slug] {
                        let isSelected = selectedSlug == note.slug
                        let isDimmed = selectedSlug != nil && !activeNeighbors.contains(note.slug)
                        let isCenter = note.folder == .index
                        Button {
                            selectedSlug = isSelected ? nil : note.slug
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(nodeTint(for: note.folder))
                                    .frame(width: isCenter ? 8 : 6, height: isCenter ? 8 : 6)
                                Text(String(note.title.prefix(8)))
                                    .font(.system(size: 11, weight: isSelected || isCenter ? .bold : .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .foregroundStyle(isSelected ? Color.white : Color(Design.Palette.ink))
                            .background(
                                isSelected ? Color(Design.Palette.accent) : Color(Design.Palette.canvas),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    isSelected ? Color(Design.Palette.accent) : Color(Design.Palette.hairline),
                                    lineWidth: isSelected ? 1.5 : 0.8
                                )
                            )
                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                            .opacity(isDimmed ? 0.32 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .position(pt)
                    }
                }
            }
        }
    }

    private func nodeTint(for folder: VaultNoteFolder) -> Color {
        switch folder {
        case .index: return Color(Design.Palette.accent)
        case .persona: return Color(Design.Palette.success)
        case .habits: return Color(Design.Palette.warning)
        case .wiki: return Color(Design.Palette.slate)
        case .inbox: return Color(Design.Palette.stone)
        }
    }

    private func computeNodePositions(for items: [ObsidianVaultNote], in size: CGSize) -> [String: CGPoint] {
        guard size.width.isFinite, size.height.isFinite, size.width > 40, size.height > 40, !items.isEmpty else {
            return [:]
        }
        let cx = size.width / 2
        let cy = size.height / 2
        var map: [String: CGPoint] = [:]

        let hub = items.first(where: { $0.folder == .index }) ?? items[0]
        map[hub.slug] = CGPoint(x: cx, y: cy)

        let ring = items.filter { $0.slug != hub.slug }
        guard !ring.isEmpty else { return map }

        let rx = max(36, size.width * 0.37)
        let ry = max(34, size.height * 0.37)
        for (idx, note) in ring.enumerated() {
            let angle = (Double(idx) / Double(ring.count)) * 2.0 * .pi - .pi / 2.0
            let radiusScale: CGFloat = (idx % 2 == 0) ? 1.0 : 0.72
            let x = min(size.width - 44, max(44, cx + CGFloat(cos(angle)) * rx * radiusScale))
            let y = min(size.height - 20, max(20, cy + CGFloat(sin(angle)) * ry * radiusScale))
            map[note.slug] = CGPoint(x: x, y: y)
        }
        return map
    }
}

// MARK: - Obsidian 单篇笔记详情 / 双链跳转 / Markdown 编辑弹窗

private struct ObsidianNoteDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentSlug: String
    let onChanged: () -> Void
    let onToast: (String) -> Void

    @State private var note: ObsidianVaultNote?
    @State private var outlinkNotes: [ObsidianVaultNote] = []
    @State private var unresolvedOutlinkTitles: [String] = []
    @State private var backlinkNotes: [ObsidianVaultNote] = []

    @State private var isEditing = false
    @State private var editSummary = ""
    @State private var editBody = ""
    @State private var editFolder: VaultNoteFolder = .wiki

    init(initialSlug: String, onChanged: @escaping () -> Void, onToast: @escaping (String) -> Void) {
        self._currentSlug = State(initialValue: initialSlug)
        self.onChanged = onChanged
        self.onToast = onToast
    }

    var body: some View {
        NavigationStack {
            List {
                if let note {
                    Section("YAML Frontmatter 元数据") {
                        LXFlowLayout(spacing: 6, lineSpacing: 6) {
                            LXTag(text: "/\(note.folder.rawValue)", icon: note.folder.icon, tint: Color(Design.Palette.accent), filled: true)
                            LXTag(text: "强度 \(Int(ObsidianMemoryVaultEngine.effectiveStrength(for: note) * 100))%", tint: Color(Design.Palette.success), filled: true)
                            LXTag(text: "被召回 \(note.recallCount) 次")
                            LXTag(text: note.sourceDisplayName)
                            ForEach(note.tags, id: \.self) { t in
                                LXTag(text: "#\(t)", tint: Color(Design.Palette.slate))
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if isEditing {
                        Section("编辑笔记（支持 [[双向链接]] 与 #标签）") {
                            Picker("目录", selection: $editFolder) {
                                ForEach(VaultNoteFolder.allCases) { f in
                                    Text(f.displayTitle).tag(f)
                                }
                            }
                            TextField("一句话摘要", text: $editSummary)
                                .font(.subheadline)
                            TextEditor(text: $editBody)
                                .font(.footnote.monospaced())
                                .frame(minHeight: 160)
                            Button("保存并同步双向链接") {
                                var updated = note
                                updated.folder = editFolder
                                updated.summary = editSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                                updated.bodyMarkdown = editBody.trimmingCharacters(in: .whitespacesAndNewlines)
                                updated.source = "user_manual"
                                AICognitiveMemoryDB.shared.upsertVaultNote(updated)
                                AICognitiveMemoryDB.shared.appendEvolutionLog(
                                    action: "user_teach",
                                    noteTitle: updated.title,
                                    detail: "手动修订笔记与双链",
                                    source: "user_manual"
                                )
                                isEditing = false
                                loadNote(slug: currentSlug)
                                onChanged()
                                onToast("已保存笔记并更新知识图谱")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                        }
                    } else {
                        Section("笔记正文") {
                            if !note.summary.isEmpty {
                                Text(note.summary)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.ink))
                            }
                            Text(note.bodyMarkdown)
                                .font(.footnote)
                                .foregroundStyle(Color(Design.Palette.charcoal))
                                .lineSpacing(4)
                                .textSelection(.enabled)

                            HStack(spacing: 8) {
                                Button {
                                    let md = ObsidianMemoryVaultEngine.renderObsidianMarkdown(note: note, backlinks: backlinkNotes)
                                    UIPasteboard.general.string = md
                                    onToast("已复制完整 Obsidian .md（含 YAML 与反向链接）")
                                } label: {
                                    Label("复制 .md", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))

                                Button {
                                    AICognitiveMemoryDB.shared.togglePinVaultNote(slug: note.slug)
                                    loadNote(slug: currentSlug)
                                    onChanged()
                                } label: {
                                    Label(note.isPinned ? "取消置顶" : "置顶常青", systemImage: note.isPinned ? "pin.slash" : "pin.fill")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                            }
                        }

                        Section("出链 · 指向的笔记（\(outlinkNotes.count + unresolvedOutlinkTitles.count)）") {
                            if outlinkNotes.isEmpty && unresolvedOutlinkTitles.isEmpty {
                                Text("暂无出链，可在正文中写入 [[其他笔记标题]] 自动建立连接。")
                                    .font(.caption)
                                    .foregroundStyle(Color(Design.Palette.stone))
                            } else {
                                LXFlowLayout(spacing: 8, lineSpacing: 8) {
                                    ForEach(outlinkNotes) { target in
                                        Button {
                                            currentSlug = target.slug
                                            loadNote(slug: target.slug)
                                        } label: {
                                            LXTag(text: "[[\(target.title)]]", icon: "arrow.right", tint: Color(Design.Palette.accent), filled: true)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    ForEach(unresolvedOutlinkTitles, id: \.self) { ghost in
                                        LXTag(text: "[[\(ghost)]] (待建)", tint: Color(Design.Palette.stone))
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        Section("反向链接 · 引用了本篇的笔记（\(backlinkNotes.count)）") {
                            if backlinkNotes.isEmpty {
                                Text("暂无反向链接。")
                                    .font(.caption)
                                    .foregroundStyle(Color(Design.Palette.stone))
                            } else {
                                ForEach(backlinkNotes) { src in
                                    Button {
                                        currentSlug = src.slug
                                        loadNote(slug: src.slug)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("[[\(src.title)]]")
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(Color(Design.Palette.ink))
                                                Text(src.summary)
                                                    .font(.caption)
                                                    .foregroundStyle(Color(Design.Palette.stone))
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(note?.title ?? "原子笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "取消编辑" : "编辑") {
                        if !isEditing, let n = note {
                            editFolder = n.folder
                            editSummary = n.summary
                            editBody = n.bodyMarkdown
                        }
                        isEditing.toggle()
                    }
                }
            }
            .onAppear {
                loadNote(slug: currentSlug)
            }
        }
    }

    private func loadNote(slug: String) {
        let db = AICognitiveMemoryDB.shared
        guard let loaded = db.fetchVaultNote(slug: slug) else {
            note = nil
            return
        }
        note = loaded
        let all = db.fetchVaultNotes(limit: 200)
        let bySlug = Dictionary(uniqueKeysWithValues: all.map { ($0.slug, $0) })

        let outEdges = db.fetchOutlinks(forSlug: slug)
        outlinkNotes = outEdges.compactMap { bySlug[$0.toSlug] }
        let resolvedSlugs = Set(outlinkNotes.map(\.slug))
        let rawInline = ObsidianMemoryVaultEngine.parseWikilinks(in: loaded.bodyMarkdown)
        unresolvedOutlinkTitles = rawInline.filter { !resolvedSlugs.contains(AICognitiveMemoryDB.normalizeSlug($0)) }

        let backEdges = db.fetchBacklinks(forSlug: slug)
        backlinkNotes = backEdges.compactMap { bySlug[$0.fromSlug] }
    }
}

// MARK: - 手动新建 Obsidian 原子笔记弹窗

private struct ObsidianNewNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, VaultNoteFolder, String, String, [String]) -> Void

    @State private var title = ""
    @State private var folder: VaultNoteFolder = .persona
    @State private var summary = ""
    @State private var bodyMarkdown = ""
    @State private var tagsText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("笔记标识") {
                    TextField("原子笔记标题（如：职场汇报原则）", text: $title)
                    Picker("所属分区", selection: $folder) {
                        ForEach(VaultNoteFolder.allCases) { f in
                            Text(f.displayTitle).tag(f)
                        }
                    }
                    TextField("一句话结论（用于 AI 精准召回）", text: $summary)
                    TextField("标签（逗号分隔，如：职场,表达习惯）", text: $tagsText)
                }

                Section("Markdown 正文（写入 [[其他笔记标题]] 自动建立双向链接）") {
                    TextEditor(text: $bodyMarkdown)
                        .font(.footnote.monospaced())
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle("新建原子笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("入库") {
                        let tags = tagsText
                            .replacingOccurrences(of: "，", with: ",")
                            .split(separator: ",")
                            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        onSave(title, folder, summary, bodyMarkdown, tags)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
