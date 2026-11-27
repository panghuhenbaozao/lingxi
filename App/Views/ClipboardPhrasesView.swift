import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ClipboardPhrasesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var segment = 0 // 0=剪贴板, 1=快捷短语
    @State private var showAddPhrase = false
    @State private var newPhraseTitle = ""
    @State private var newPhraseContent = ""
    @State private var newPhraseCategory = "常用"
    @State private var historySearchQuery = ""
    @State private var historyCategoryFilter = 0 // 0=全部, 1=验证码, 2=链接, 3=置顶
    @State private var toolboxToast: String?
    @State private var showClearConfirm = false
    @State private var relaySSETask: Task<Void, Never>?

    // BigBang 炸词提取 Sheet
    @State private var bigBangSourceText: String?
    @State private var selectedBigBangTokens: [String] = []
    @State private var bigBangCustomCode: String = ""

    // 语音输入与 AI 口语整编工作室
    @State private var showVoiceStudio = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("内容类型", selection: $segment) {
                    Text("剪贴板").tag(0)
                    Text("常用短语").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Design.Spacing.md)
                .padding(.top, 6)
                .padding(.bottom, 10)

                if segment == 0 {
                    clipboardList
                } else {
                    phrasesList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("剪贴板")
            .lxToast($toolboxToast)
            .onAppear {
                let relayConfig = ClipboardRelayConfig.load()
                if relayConfig.autoRelayEnabled, !relayConfig.pairCode.isEmpty {
                    relaySSETask?.cancel()
                    relaySSETask = ClipboardRelayService.shared.subscribeRealtimeStream(pairCode: relayConfig.pairCode) { items in
                        appState.reloadClipboard()
                        if let first = items.first {
                            UIPasteboard.general.string = first.contentText
                            toolboxToast = "跨屏收到：「\(first.contentText.prefix(24))」"
                        }
                    }
                }
            }
            .onDisappear {
                relaySSETask?.cancel()
                relaySSETask = nil
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if segment == 0 {
                        Menu {
                            Button {
                                importSystemClipboard()
                            } label: {
                                Label("导入系统剪贴板当前内容", systemImage: "square.and.arrow.down")
                            }
                            Button(role: .destructive) {
                                showClearConfirm = true
                            } label: {
                                Label("清空未置顶记录", systemImage: "trash")
                            }
                            .disabled(!appState.clipboardItems.contains(where: { !$0.isPinned }))
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("剪贴板操作")
                    } else {
                        Button {
                            newPhraseTitle = ""
                            newPhraseContent = ""
                            newPhraseCategory = "常用"
                            showAddPhrase = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("新建快捷短语")
                    }
                }
            }
            .confirmationDialog("清空未置顶的剪贴板记录？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    appState.clearUnpinnedClipboard()
                    toolboxToast = "已清空未置顶记录"
                }
            } message: {
                Text("置顶的记录会保留，此操作无法撤销。")
            }
            .sheet(isPresented: $showAddPhrase) {
                addPhraseSheet
            }
            .sheet(isPresented: $showVoiceStudio) {
                VoiceLiveTranslatorView()
                    .environmentObject(appState)
            }
            .sheet(
                isPresented: Binding(
                    get: { bigBangSourceText != nil },
                    set: { if !$0 { bigBangSourceText = nil; selectedBigBangTokens = [] } }
                )
            ) {
                bigBangSheet
            }
        }
    }

    private func importSystemClipboard() {
        if let text = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
            appState.addClipboardEntry(text)
            toolboxToast = "已导入当前剪贴板内容"
        } else {
            toolboxToast = ConcealedPasteboard.isConcealed() ? "当前剪贴板为保险箱受保护内容，已拒绝记入明文历史" : "系统剪贴板是空的"
        }
    }

    private func copyToPasteboard(_ text: String, message: String) {
        UIPasteboard.general.string = text
        toolboxToast = message
    }

    private func openBigBang(_ text: String) {
        selectedBigBangTokens = []
        bigBangCustomCode = ""
        bigBangSourceText = text
    }

    // MARK: - 1. 剪贴板历史（L1 主列表）+ 效率工具箱 L2 入口

    private var filteredClipboardItems: [ClipboardItem] {
        let q = historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appState.clipboardItems.filter { item in
            guard matchesFilter(item, historyCategoryFilter) else { return false }
            if q.isEmpty { return true }
            return item.text.lowercased().contains(q) || (item.extractedCode?.contains(q) ?? false)
        }
    }

    private func matchesFilter(_ item: ClipboardItem, _ filter: Int) -> Bool {
        switch filter {
        case 1: return item.category == .code || item.extractedCode != nil
        case 2: return item.category == .url
        case 3: return item.isPinned
        default: return true
        }
    }

    private var clipboardList: some View {
        List {
            if appState.clipboardItems.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        LXEmptyState(
                            icon: "doc.on.clipboard",
                            title: "还没有剪贴板记录",
                            message: "复制任意内容后切到灵犀键盘，或点下面的按钮导入。会自动识别验证码和链接。"
                        )
                        Button {
                            importSystemClipboard()
                        } label: {
                            Label("导入当前剪贴板", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                        .padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                let filtered = filteredClipboardItems
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.subheadline)
                            .foregroundStyle(Color(Design.Palette.muted))
                        TextField("搜索历史或验证码", text: $historySearchQuery)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !historySearchQuery.isEmpty {
                            Button {
                                historySearchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color(Design.Palette.muted))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("清除搜索")
                        }
                    }
                    .frame(minHeight: 36)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip("全部", tag: 0)
                            filterChip("验证码", tag: 1)
                            filterChip("链接", tag: 2)
                            filterChip("置顶", tag: 3)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    if filtered.isEmpty {
                        LXEmptyState(
                            icon: "magnifyingglass",
                            title: "没有匹配的记录",
                            message: "换个关键词，或切回「全部」。"
                        )
                    } else {
                        ForEach(filtered) { item in
                            clipboardRow(item)
                        }
                    }
                } header: {
                    Text("最近记录（\(filtered.count)）")
                }
            }

            toolsSection
        }
        .listStyle(.insetGrouped)
    }

    private func filterChip(_ title: String, tag: Int) -> some View {
        let active = historyCategoryFilter == tag
        let count = appState.clipboardItems.filter { matchesFilter($0, tag) }.count
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { historyCategoryFilter = tag }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .monospacedDigit()
                    .opacity(0.7)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
            .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func clipboardRow(_ item: ClipboardItem) -> some View {
        let parsedInfo = SmartInfoParser.parse(item.text)
        let scamReport = CommunicationGuardEngine.analyzeScam(item.text)
        let linkReport = LinkPrivacyCleaner.clean(item.text)
        return VStack(alignment: .leading, spacing: 8) {
            Text(item.text)
                .font(.subheadline)
                .foregroundStyle(Color(Design.Palette.ink))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let parsedInfo, !parsedInfo.fields.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        LXTag(text: parsedInfo.kind.badgeLabel, tint: Color(Design.Palette.slate))
                        ForEach(parsedInfo.fields) { field in
                            Button {
                                copyToPasteboard(field.value, message: "已复制\(field.label)：\(field.value.prefix(24))")
                            } label: {
                                LXTag(
                                    text: "填\(field.label)",
                                    icon: "doc.on.doc",
                                    tint: Color(Design.Palette.accent),
                                    filled: true
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("仅复制\(field.label)")
                        }
                        Button {
                            if let card = PersonalFillCardStore.buildCardFromRawText(item.text) {
                                PersonalFillCardStore.upsert(card)
                                toolboxToast = "已存入个人速填名片夹「\(card.title)」"
                            }
                        } label: {
                            LXTag(text: "+存名片", icon: "plus.circle", tint: Color(Design.Palette.success), filled: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 6) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(Design.Palette.accent))
                        .accessibilityLabel("已置顶")
                }
                LXTag(text: item.category.badgeText, icon: item.category.systemIconName)
                if scamReport.isRisky {
                    LXTag(
                        text: scamReport.level == .highRisk ? "高危防诈" : "风险提醒",
                        icon: "exclamationmark.shield.fill",
                        tint: scamReport.level == .highRisk ? Color(Design.Palette.error) : Color(Design.Palette.warning),
                        filled: true
                    )
                }
                if linkReport.hasChanges, let cleanTarget = linkReport.extractedCleanURL ?? (linkReport.cleanedText.isEmpty ? nil : linkReport.cleanedText) {
                    Button {
                        copyToPasteboard(cleanTarget, message: linkReport.summaryBadge)
                    } label: {
                        LXTag(
                            text: linkReport.hasIdentityLeakRisk ? "去追踪净链" : "纯净链接",
                            icon: "sparkles",
                            tint: linkReport.hasIdentityLeakRisk ? Color(Design.Palette.warning) : Color(Design.Palette.accent),
                            filled: true
                        )
                    }
                    .buttonStyle(.plain)
                }
                if let code = item.extractedCode {
                    Button {
                        copyToPasteboard(code, message: "已复制验证码 \(code)")
                    } label: {
                        LXTag(text: "验证码 \(code)", icon: "doc.on.doc", tint: Color(Design.Palette.accent), filled: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制验证码 \(code)")
                }
                Spacer(minLength: 4)
                Text(item.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            copyToPasteboard(item.text, message: "已复制「\(item.text.prefix(20))」")
        }
        .swipeActions(edge: .leading) {
            Button {
                appState.togglePinClipboard(id: item.id)
            } label: {
                Label(item.isPinned ? "取消置顶" : "置顶", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            .tint(Color(Design.Palette.accent))
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                appState.deleteClipboard(id: item.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                openBigBang(item.text)
            } label: {
                Label("炸词", systemImage: "scissors")
            }
            .tint(Color(Design.Palette.slate))
        }
        .contextMenu {
            Button {
                copyToPasteboard(item.text, message: "已复制原文")
            } label: {
                Label("复制原文", systemImage: "doc.on.doc")
            }
            Button {
                copyToPasteboard(TextFormatterToolbox.addPanguSpaces(item.text), message: "已加盘古空格并复制")
            } label: {
                Label("加盘古空格并复制", systemImage: "textformat.abc")
            }
            Button {
                copyToPasteboard(TextFormatterToolbox.collapseBlankLines(item.text), message: "已去除多余空行并复制")
            } label: {
                Label("去多余空行并复制", systemImage: "text.justify")
            }
            Button {
                copyToPasteboard(TextFormatterToolbox.toNumberedList(item.text), message: "已整理为编号清单并复制")
            } label: {
                Label("整理为编号清单并复制", systemImage: "list.number")
            }
            Button {
                openBigBang(item.text)
            } label: {
                Label("BigBang 炸词提取", systemImage: "scissors")
            }
            Divider()
            Button {
                appState.togglePinClipboard(id: item.id)
            } label: {
                Label(item.isPinned ? "取消置顶" : "置顶", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                appState.deleteClipboard(id: item.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // 精简核心效率工具（撤除冗余表情库/话术库/6 宫格噪声）
    private var toolsSection: some View {
        Section("效率工具") {
            NavigationLink {
                PersonalFillCardsSubView()
            } label: {
                compactToolRow(icon: "person.text.rectangle", title: "速填名片夹", value: "地址 / 开票")
            }

            NavigationLink {
                DraftRecoverySubView()
            } label: {
                compactToolRow(icon: "clock.arrow.circlepath", title: "草稿防丢", value: "24 小时留底")
            }

            NavigationLink {
                CrossDeviceRelaySubView()
            } label: {
                compactToolRow(icon: "laptopcomputer.and.iphone", title: "跨屏接力", value: "手机 ⇄ 电脑")
            }

            HStack(spacing: 10) {
                formatButton("链接去追踪", icon: "link") {
                    let r = LinkPrivacyCleaner.clean($0)
                    return r.extractedCleanURL ?? r.cleanedText
                }
                formatButton("盘古空格", icon: "textformat.abc") { TextFormatterToolbox.addPanguSpaces($0) }
            }
            .padding(.vertical, 4)
        }
    }

    private func compactToolRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            LXIconTile(icon: icon, size: 30)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(Design.Palette.ink))
            Spacer(minLength: 8)
            Text(value)
                .font(.footnote)
                .foregroundStyle(Color(Design.Palette.stone))
        }
        .padding(.vertical, 3)
    }

    // MARK: - 2. 动态变量快捷短语（支持 {{日期}} / {{时间}} / {{剪贴板}} / {{随机问候}} 实时渲染）

    private var phrasesList: some View {
        List {
            Section {
                Button {
                    newPhraseTitle = "今日汇报头"
                    newPhraseCategory = "动态模板"
                    newPhraseContent = "{{随机问候}}！今日（{{日期}} {{星期}} {{时间}}）进展同步如下："
                    showAddPhrase = true
                } label: {
                    HStack(spacing: 12) {
                        LXIconTile(icon: "wand.and.stars")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("新建动态模板")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text("日期、时间、问候语插入时自动更新")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } footer: {
                Text("可用变量：{{日期}}、{{时间}}、{{星期}}、{{剪贴板}}、{{随机问候}}")
            }

            Section {
                if appState.quickPhrases.isEmpty {
                    LXEmptyState(
                        icon: "text.bubble",
                        title: "还没有快捷短语",
                        message: "点右上角 + 新建，常用的话在键盘里一点就能发。"
                    )
                } else {
                    ForEach(appState.quickPhrases) { phrase in
                        phraseRow(phrase)
                    }
                }
            } header: {
                Text("快捷短语 · \(appState.quickPhrases.count)")
            } footer: {
                if !appState.quickPhrases.isEmpty {
                    Text("点按复制（动态模板会先替换成实时内容）；左滑删除。")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func phraseRow(_ phrase: QuickPhrase) -> some View {
        let hasVars = DynamicTemplateEngine.containsVariables(phrase.content)
        let rendered = hasVars ? DynamicTemplateEngine.render(phrase.content) : phrase.content
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(phrase.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .lineLimit(1)
                if hasVars {
                    LXTag(text: "动态", icon: "wand.and.stars", tint: Color(Design.Palette.accent), filled: true)
                }
                Spacer(minLength: 4)
                if !phrase.category.isEmpty {
                    LXTag(text: phrase.category)
                }
            }
            Text(phrase.content)
                .font(.footnote)
                .foregroundStyle(Color(Design.Palette.stone))
                .lineLimit(3)
            if hasVars {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "eye")
                        .font(.caption2)
                        .foregroundStyle(Color(Design.Palette.accent))
                        .padding(.top, 2)
                    Text(rendered)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.charcoal))
                        .lineLimit(3)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(Design.Palette.accentSoft), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            UIPasteboard.general.string = rendered
            appState.addClipboardEntry(rendered)
            toolboxToast = "已复制「\(rendered.prefix(20))」"
        }
        .swipeActions {
            Button(role: .destructive) {
                appState.deleteQuickPhrase(id: phrase.id)
                toolboxToast = "已删除「\(phrase.title)」"
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = rendered
                appState.addClipboardEntry(rendered)
                toolboxToast = "已复制"
            } label: {
                Label(hasVars ? "复制渲染结果" : "复制", systemImage: "doc.on.doc")
            }
            if hasVars {
                Button {
                    UIPasteboard.general.string = phrase.content
                    toolboxToast = "已复制模板原文"
                } label: {
                    Label("复制模板原文", systemImage: "curlybraces")
                }
            }
            Button(role: .destructive) {
                appState.deleteQuickPhrase(id: phrase.id)
                toolboxToast = "已删除「\(phrase.title)」"
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func formatButton(_ title: String, icon: String, transform: @escaping (String) -> String) -> some View {
        Button {
            guard let raw = ConcealedPasteboard.readNonConcealedStringForUserPaste() else {
                toolboxToast = ConcealedPasteboard.isConcealed()
                    ? "受保护的保险箱机密不参与快捷排版"
                    : "系统剪贴板是空的，先复制一段文字"
                return
            }
            let out = transform(raw)
            UIPasteboard.general.string = out
            appState.addClipboardEntry(out)
            toolboxToast = "已完成「\(title)」并写回剪贴板"
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.accent))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - BigBang 炸词提取 Sheet

    private var bigBangSheet: some View {
        let source = bigBangSourceText ?? ""
        let tokens = BigBangTokenizer.tokenize(source)
        let combined = selectedBigBangTokens.joined()

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("点按下方分词块自由拼接提取，一键复制或存为自定义编码短语：")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 8)], spacing: 8) {
                        ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                            let isChosen = selectedBigBangTokens.contains(token)
                            Button {
                                if let idx = selectedBigBangTokens.firstIndex(of: token) {
                                    selectedBigBangTokens.remove(at: idx)
                                } else {
                                    selectedBigBangTokens.append(token)
                                }
                            } label: {
                                Text(token)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(isChosen ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
                                    .foregroundStyle(isChosen ? Color.white : Color(Design.Palette.ink))
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !combined.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("已拼接内容：\(combined)").font(.subheadline.bold())
                            HStack(spacing: 10) {
                                Button {
                                    UIPasteboard.general.string = combined
                                    appState.addClipboardEntry(combined)
                                    bigBangSourceText = nil
                                } label: {
                                    Label("复制选中词", systemImage: "doc.on.doc")
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(Color(Design.Palette.accent))
                                        .foregroundStyle(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                Button("重选") { selectedBigBangTokens = [] }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 36)
                                    .background(Color(Design.Palette.surface))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .buttonStyle(.plain)
                            }

                            HStack(spacing: 8) {
                                TextField("输入快捷编码 (如 dz)", text: $bigBangCustomCode)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(8)
                                    .background(Color(Design.Palette.surface))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                Button("存入短语") {
                                    let code = bigBangCustomCode.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !code.isEmpty {
                                        appState.addCustomWord(code: code, word: combined)
                                        bigBangSourceText = nil
                                    }
                                }
                                .font(.caption.bold())
                                .disabled(bigBangCustomCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .lxReadableWidth()
                .padding()
            }
            .navigationTitle("BigBang 炸词提取")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { bigBangSourceText = nil } }
            }
        }
    }

    // MARK: - 新增动态快捷短语 Sheet

    private var addPhraseSheet: some View {
        NavigationStack {
            Form {
                TextField("标题（如：收货地址 / 日报头）", text: $newPhraseTitle)
                TextField("分类（如：生活、职场、动态模板）", text: $newPhraseCategory)

                Section("插入动态变量（点按追加到正文）") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(DynamicTemplateEngine.availableTokens, id: \.token) { item in
                                Button("\(item.label)") {
                                    newPhraseContent += item.token
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color(Design.Palette.accentSoft))
                                .foregroundStyle(Color(Design.Palette.accent))
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("短语正文") {
                    TextField("输入正文（可包含 {{日期}} 等变量）", text: $newPhraseContent, axis: .vertical)
                        .lineLimit(3...6)
                    if DynamicTemplateEngine.containsVariables(newPhraseContent) {
                        Text("实时预览：\(DynamicTemplateEngine.render(newPhraseContent))")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                }
            }
            .navigationTitle("新增动态快捷短语")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { showAddPhrase = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let t = newPhraseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let c = newPhraseContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cat = newPhraseCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty && !c.isEmpty {
                            appState.addQuickPhrase(title: t, content: c, category: cat.isEmpty ? "常用" : cat)
                            newPhraseTitle = ""
                            newPhraseContent = ""
                            showAddPhrase = false
                        }
                    }
                    .disabled(newPhraseTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              newPhraseContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - L2 工具子页 1：跨屏剪贴板接力 (6 位码)

struct CrossDeviceRelaySubView: View {
    @EnvironmentObject private var appState: AppState
    @State private var relayConfig: ClipboardRelayConfig = ClipboardRelayConfig()  // 真实配置在 onAppear 读取
    @State private var relayToast: String?
    @State private var isPushing = false
    @State private var isPulling = false
    @FocusState private var codeFocused: Bool

    private var isRelaying: Bool { isPushing || isPulling }

    private var isCodeValid: Bool {
        relayConfig.pairCode.count == 6 && !relayConfig.pairCode.contains(where: { !$0.isNumber })
    }

    private var dashboardURL: String {
        "\(appState.cloudConfig.normalizedBaseURL)/dashboard"
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    LXIconTile(icon: "laptopcomputer.and.iphone", size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("电脑和手机互传文字")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("两边输入同一个 6 位码即可，无需登录。身份证、银行卡、密码会被自动拦截。")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack(spacing: 10) {
                    TextField("000000", text: $relayConfig.pairCode)
                        .keyboardType(.numberPad)
                        .focused($codeFocused)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .kerning(6)
                        .foregroundStyle(isCodeValid ? Color(Design.Palette.ink) : Color(Design.Palette.error))
                        .onChange(of: relayConfig.pairCode) { newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(6))
                            if digits != newValue { relayConfig.pairCode = digits }
                            if digits.count == 6 { relayConfig.save() }
                        }
                        .accessibilityLabel("6 位匹配码")

                    Spacer(minLength: 4)

                    Button {
                        UIPasteboard.general.string = relayConfig.pairCode
                        relayToast = "已复制匹配码"
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                    .disabled(!isCodeValid)
                    .accessibilityLabel("复制匹配码")

                    Button {
                        relayConfig.pairCode = ClipboardRelayService.generateSixDigitCode()
                        relayConfig.save()
                        relayToast = "已换成新的匹配码"
                    } label: {
                        Label("换码", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                }
                .padding(.vertical, 4)
            } header: {
                Text("匹配码")
            } footer: {
                if !isCodeValid {
                    Text("匹配码需要是 6 位数字。")
                        .foregroundStyle(Color(Design.Palette.error))
                }
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        pushClipboardToRelay()
                    } label: {
                        HStack(spacing: 6) {
                            if isPushing {
                                ProgressView().controlSize(.small).tint(Color.white)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                            }
                            Text(isPushing ? "发送中…" : "发送本机剪贴板")
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))

                    Button {
                        pullClipboardFromRelay()
                    } label: {
                        HStack(spacing: 6) {
                            if isPulling {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text(isPulling ? "接收中…" : "接收电脑内容")
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                }
                .disabled(isRelaying || !isCodeValid)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                LXToggleRow(
                    "打开「工具」页时自动接收",
                    subtitle: "电脑推送的内容会直接写入手机剪贴板",
                    isOn: $relayConfig.autoRelayEnabled
                )
                .onChange(of: relayConfig.autoRelayEnabled) { _ in
                    relayConfig.save()
                }
            } header: {
                Text("传输")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    stepRow(1, "在电脑浏览器打开下面的地址")
                    HStack(spacing: 8) {
                        Text(dashboardURL)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color(Design.Palette.charcoal))
                            .lineLimit(2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            UIPasteboard.general.string = dashboardURL
                            relayToast = "已复制控制台地址"
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                        .accessibilityLabel("复制控制台地址")
                    }
                    .padding(10)
                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous))
                    stepRow(2, "输入和手机上相同的 6 位匹配码")
                    stepRow(3, "手机点「发送」，或在电脑上发送后手机点「接收」")
                }
                .padding(.vertical, 4)
            } header: {
                Text("电脑端怎么用")
            }
        }
        .navigationTitle("跨屏剪贴板接力")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($relayToast)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { codeFocused = false }
            }
        }
        .onAppear { relayConfig = ClipboardRelayConfig.load() }
    }

    private func stepRow(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Color(Design.Palette.accent))
                .frame(width: 22, height: 22)
                .background(Color(Design.Palette.accentSoft), in: Circle())
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color(Design.Palette.charcoal))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func pushClipboardToRelay() {
        if ConcealedPasteboard.isConcealed() {
            relayToast = "检测到保险箱受保护剪贴板，已拦截跨屏上传"
            return
        }
        let content = ConcealedPasteboard.readNonConcealedStringForUserPaste() ?? appState.clipboardItems.first?.text ?? ""
        guard !content.isEmpty else {
            relayToast = "本机剪贴板是空的，先复制一段内容"
            return
        }
        isPushing = true
        relayConfig.save()
        Task {
            do {
                let item = try await ClipboardRelayService.shared.push(text: content, pairCode: relayConfig.pairCode)
                await MainActor.run {
                    isPushing = false
                    appState.refreshAll()
                    if let code = item.extractedCode {
                        relayToast = "已发送到匹配码 \(item.pairCode)（识别到验证码 \(code)）"
                    } else {
                        relayToast = "已发送到匹配码 \(item.pairCode)"
                    }
                }
            } catch {
                await MainActor.run {
                    isPushing = false
                    relayToast = "发送失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func pullClipboardFromRelay() {
        isPulling = true
        relayConfig.save()
        Task {
            do {
                let items = try await ClipboardRelayService.shared.pullLatest(pairCode: relayConfig.pairCode)
                await MainActor.run {
                    isPulling = false
                    appState.refreshAll()
                    if let first = items.first {
                        if first.contentText.hasPrefix(ClipboardRelayCrypto.prefix) {
                            relayToast = "收到加密剪贴板但 6 位匹配码不匹配，未能解密"
                        } else {
                            UIPasteboard.general.string = first.contentText
                            relayToast = "已收到并复制：「\(first.contentText.prefix(24))」"
                        }
                    } else {
                        relayToast = "匹配码 \(relayConfig.pairCode) 上还没有内容"
                    }
                }
            } catch {
                await MainActor.run {
                    isPulling = false
                    relayToast = "接收失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - L2 工具子页 2：表情与颜文字库

struct EmojiKaomojiCatalogSubView: View {
    @EnvironmentObject private var appState: AppState
    @State private var emojiQuery = ""
    @State private var emojiCategoryFilter = 0
    @State private var copiedSymbolToast: String?
    @State private var recentSymbols: [String] = []

    private let emojiColumns = [GridItem(.adaptive(minimum: 48, maximum: 64), spacing: 8)]

    var body: some View {
        let allHits = EmojiCatalog.search(emojiQuery, limit: 120)
        let emojis = allHits.filter { !$0.isSymbol }
        let kaomojis = allHits.filter { $0.isSymbol && $0.symbol.count > 1 }
        let symbols = allHits.filter { $0.isSymbol && $0.symbol.count == 1 }
        let showEmoji = emojiCategoryFilter == 0 || emojiCategoryFilter == 1
        let showKaomoji = emojiCategoryFilter == 0 || emojiCategoryFilter == 2
        let showSymbols = emojiCategoryFilter == 0 || emojiCategoryFilter == 3
        let nothing = (showEmoji ? emojis.count : 0) + (showKaomoji ? kaomojis.count : 0) + (showSymbols ? symbols.count : 0) == 0

        return List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryChip("全部", tag: 0)
                        categoryChip("Emoji", tag: 1)
                        categoryChip("颜文字", tag: 2)
                        categoryChip("符号", tag: 3)
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }

            if emojiQuery.isEmpty && !recentSymbols.isEmpty {
                Section("最近常用") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentSymbols.prefix(16), id: \.self) { sym in
                                Button {
                                    copy(sym, record: false)
                                } label: {
                                    Text(sym)
                                        .font(.system(size: 24))
                                        .frame(width: 44, height: 44)
                                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("复制 \(sym)")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if nothing {
                Section {
                    LXEmptyState(
                        icon: "face.dashed",
                        title: "没有找到",
                        message: "换个关键词试试，比如「开心」「掀桌」「箭头」。"
                    )
                }
            }

            if showEmoji && !emojis.isEmpty {
                Section("Emoji · \(emojis.count)") {
                    LazyVGrid(columns: emojiColumns, spacing: 8) {
                        ForEach(emojis, id: \.symbol) { entry in
                            Button {
                                copy(entry.symbol)
                            } label: {
                                Text(entry.symbol)
                                    .font(.system(size: 28))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("复制 \(entry.name)")
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if showKaomoji && !kaomojis.isEmpty {
                Section("颜文字 · \(kaomojis.count)") {
                    ForEach(kaomojis, id: \.symbol) { entry in
                        symbolRow(entry.symbol, name: entry.name, large: false)
                    }
                }
            }

            if showSymbols && !symbols.isEmpty {
                Section("符号 · \(symbols.count)") {
                    LazyVGrid(columns: emojiColumns, spacing: 8) {
                        ForEach(symbols, id: \.symbol) { entry in
                            Button {
                                copy(entry.symbol)
                            } label: {
                                Text(entry.symbol)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("复制 \(entry.name)")
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $emojiQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索：开心、掀桌、箭头…")
        .autocorrectionDisabled()
        .navigationTitle("表情与颜文字")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($copiedSymbolToast)
        .onAppear { recentSymbols = RecentEmojiStore.load() }
    }

    private func categoryChip(_ title: String, tag: Int) -> some View {
        let active = emojiCategoryFilter == tag
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { emojiCategoryFilter = tag }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func symbolRow(_ symbol: String, name: String, large: Bool) -> some View {
        Button {
            copy(symbol)
        } label: {
            HStack(spacing: 12) {
                Text(symbol)
                    .font(.system(size: large ? 22 : 16))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .lineLimit(1)
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.accent))
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("复制 \(name)")
    }

    private func copy(_ symbol: String, record: Bool = true) {
        UIPasteboard.general.string = symbol
        if record {
            RecentEmojiStore.record(symbol)
        }
        appState.addClipboardEntry(symbol)
        recentSymbols = RecentEmojiStore.load()
        copiedSymbolToast = "已复制「\(symbol)」"
    }
}

// MARK: - L2 工具子页 3：Face ID 本地敏感信息保险箱（永不上云）

struct SecureVaultSubView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVaultUnlocked = false
    @State private var isUnlocking = false
    @State private var revealedIDs: Set<String> = []
    @State private var showAddVaultItem = false
    @State private var editingVaultItem: SecureVaultItem?
    @State private var pendingDelete: SecureVaultItem?
    @State private var toast: String?

    var body: some View {
        List {
            if !isVaultUnlocked {
                lockedSection
            } else {
                unlockedSections
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("本地保险箱")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isVaultUnlocked {
                    Button {
                        lock()
                    } label: {
                        Label("上锁", systemImage: "lock.fill")
                    }
                }
            }
        }
        .onDisappear { lock() }
        .onChange(of: scenePhase) { phase in
            // 切到后台或多任务界面时立即上锁，避免内容出现在 App 切换器截图里。
            // Face ID / 密码验证弹框本身也会让 App 暂时变为 inactive，验证进行中不能上锁。
            if phase != .active && !isUnlocking { lock() }
        }
        .confirmationDialog(
            "删除「\(pendingDelete?.title ?? "")」？",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let item = pendingDelete {
                    appState.deleteVaultItem(id: item.id)
                    revealedIDs.remove(item.id)
                    toast = "已删除「\(item.title)」"
                }
                pendingDelete = nil
            }
        } message: {
            Text("保险箱内容不参与备份，删除后无法恢复。")
        }
        .sheet(isPresented: $showAddVaultItem) {
            VaultItemEditorSheet(initial: nil) { created in
                appState.upsertVaultItem(created)
                toast = "已存入保险箱"
            }
        }
        .sheet(item: $editingVaultItem) { item in
            VaultItemEditorSheet(initial: item) { updated in
                appState.upsertVaultItem(updated)
                toast = "已更新「\(updated.title)」"
            }
        }
    }

    private var lockedSection: some View {
        Section {
            VStack(spacing: 16) {
                LXIconTile(icon: "lock.shield.fill", size: 60)
                VStack(spacing: 6) {
                    Text(appState.secureVaultItems.isEmpty ? "本地保险箱" : "已锁定 · \(appState.secureVaultItems.count) 条")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("存放身份证号、银行卡、开票税号等。只保存在这台设备上，不参与云同步，也不进备份。")
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !BiometricAuthHelper.isDeviceSecured {
                    // verify() 在未设锁屏密码时会直接放行：必须如实告诉用户保险箱此时等于没锁
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.warning))
                            .padding(.top, 1)
                        Text("这台设备没有设置锁屏密码，保险箱无法真正上锁，任何拿到手机的人都能打开。建议先在系统设置里设置密码。")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.ink))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(Design.Palette.warning).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    Task { await unlockVaultWithBiometrics() }
                } label: {
                    HStack(spacing: 6) {
                        if isUnlocking {
                            ProgressView().controlSize(.small).tint(Color.white)
                        } else {
                            Image(systemName: BiometricAuthHelper.biometrySymbolName())
                        }
                        Text("用\(BiometricAuthHelper.biometryDisplayName())解锁")
                    }
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                .disabled(isUnlocking)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var unlockedSections: some View {
        Section {
            if appState.secureVaultItems.isEmpty {
                LXEmptyState(
                    icon: "tray",
                    title: "保险箱是空的",
                    message: "点下面的按钮存入第一条，比如开票税号或常用银行卡号。"
                )
            } else {
                ForEach(appState.secureVaultItems) { item in
                    vaultRow(item)
                }
            }
            Button {
                showAddVaultItem = true
            } label: {
                Label("新增条目", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.accent))
                    .frame(minHeight: 36)
            }
        } header: {
            Label("已解锁 · 离开页面或切到后台会自动上锁", systemImage: "lock.open.fill")
                .textCase(nil)
        } footer: {
            Text("复制的内容只留在本机剪贴板（不会通过「通用剪贴板」传到 Mac 或 iPad），\(Int(ConcealedPasteboard.defaultLifetime)) 秒后自动清除，灵犀键盘也不会把它记进剪贴板历史。")
        }
    }

    private func vaultRow(_ item: SecureVaultItem) -> some View {
        let revealed = revealedIDs.contains(item.id)
        return HStack(alignment: .center, spacing: 10) {
            Button {
                editingVaultItem = item
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .lineLimit(1)
                        if !item.category.isEmpty {
                            LXTag(text: item.category)
                        }
                    }
                    Text(revealed ? item.value : item.maskedPreview)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color(Design.Palette.charcoal))
                        .lineLimit(revealed ? 3 : 1)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if revealed {
                    revealedIDs.remove(item.id)
                } else {
                    revealedIDs.insert(item.id)
                }
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.subheadline)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealed ? "隐藏内容" : "显示内容")

            Button {
                ConcealedPasteboard.copy(item.value)
                toast = "已复制「\(item.title)」，\(Int(ConcealedPasteboard.defaultLifetime)) 秒后自动清除"
            } label: {
                Text("复制")
            }
            .buttonStyle(LXCapsuleButtonStyle(prominent: false))
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = item
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func lock() {
        isVaultUnlocked = false
        revealedIDs = []
    }

    private func unlockVaultWithBiometrics() async {
        guard !isUnlocking else { return }
        isUnlocking = true
        do {
            try await BiometricAuthHelper.verify(reason: "验证身份以查看本机保险箱")
            isVaultUnlocked = true
        } catch {
            toast = "解锁失败：\(error.localizedDescription)"
        }
        // 等验证弹框完全收起、App 回到前台后再解除保护，避免收起过程中的 inactive 事件误上锁
        try? await Task.sleep(nanoseconds: 600_000_000)
        isUnlocking = false
    }
}

// MARK: - L2 设置子页：26 键自定义上滑/下滑符号映射编辑器（归口至「设置 → 键盘手感与手势」）

private struct LayoutPackJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct CustomSwipeKeymapEditorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedKeyToEdit: String = "q"
    @State private var customUpDraft: String = ""
    @State private var customDownDraft: String = ""
    @State private var toast: String?
    @State private var confirmPreset = false
    @State private var confirmHamsterPreset = false
    @State private var confirmReset = false
    @State private var commandTargetDirection: Int = 1 // 0=上滑, 1=下划
    @State private var packExportDoc: LayoutPackJSONDocument?
    @State private var showPackExporter = false
    @State private var showPackImporter = false

    private let rows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]

    private static let geekPreset: [String: String] = [
        "a": "@", "s": "/", "d": "$", "f": "()", "g": "{}", "h": "[]", "k": "->"
    ]

    private var savedUp: String { appState.settings.customSwipeUpMap[selectedKeyToEdit] ?? "" }
    private var savedDown: String { appState.settings.customSwipeDownMap[selectedKeyToEdit] ?? "" }

    private var hasUnsavedChanges: Bool {
        customUpDraft.trimmingCharacters(in: .whitespacesAndNewlines) != savedUp
            || customDownDraft.trimmingCharacters(in: .whitespacesAndNewlines) != savedDown
    }

    private var customizedCount: Int {
        Set(appState.settings.customSwipeUpMap.keys).union(appState.settings.customSwipeDownMap.keys).count
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(row, id: \.self) { key in
                                keyCap(key)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("选择按键 · 已自定义 \(customizedCount) 个")
            } footer: {
                Text("蓝底为已自定义的按键。键帽上方是上滑输出，下方是下划输出。")
            }

            Section {
                HStack(spacing: 10) {
                    Label("上滑", systemImage: "arrow.up")
                        .font(.subheadline)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .frame(width: 64, alignment: .leading)
                    TextField("留空使用默认", text: $customUpDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }
                HStack(spacing: 10) {
                    Label("下划", systemImage: "arrow.down")
                        .font(.subheadline)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .frame(width: 64, alignment: .leading)
                    TextField("如 ()、「」或 #paste / #firstChar", text: $customDownDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("绑定仓式快捷动作命令（点按一键填入）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.stone))
                        Spacer()
                        Picker("方向", selection: $commandTargetDirection) {
                            Text("填到上滑").tag(0)
                            Text("填到下划").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 148)
                    }
                    LXFlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(KeyboardSwipeCommand.allCases) { cmd in
                            Button {
                                if commandTargetDirection == 0 {
                                    customUpDraft = cmd.rawValue
                                } else {
                                    customDownDraft = cmd.rawValue
                                }
                            } label: {
                                Text("\(cmd.keycapBadge) · \(cmd.displayTitle)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .padding(.horizontal, 9)
                                    .frame(height: 28)
                                    .background(Color(Design.Palette.surface), in: Capsule())
                                    .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)

                Button {
                    saveCurrent(showToast: true)
                } label: {
                    Label(hasUnsavedChanges ? "保存「\(selectedKeyToEdit.uppercased())」" : "已保存", systemImage: hasUnsavedChanges ? "checkmark" : "checkmark.circle")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: hasUnsavedChanges, wide: true))
                .disabled(!hasUnsavedChanges)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                HStack {
                    Text("按键「\(selectedKeyToEdit.uppercased())」")
                    if hasUnsavedChanges {
                        LXTag(text: "未保存", tint: Color(Design.Palette.warning), filled: true)
                            .textCase(nil)
                    }
                }
            } footer: {
                Text("切换到其他按键时会自动保存当前修改。保存后键盘立即生效。")
            }

            Section {
                ForEach(CustomKeyboardLayoutPack.builtInPacks) { pack in
                    let isActive = appState.settings.activeLayoutPackID == pack.id
                    Button {
                        pack.apply(to: &appState.settings)
                        loadDrafts()
                        toast = "已切换布局包「\(pack.name)」"
                    } label: {
                        HStack(spacing: 12) {
                            LXIconTile(icon: pack.icon, tint: isActive ? Color(Design.Palette.accent) : Color(Design.Palette.slate), size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(pack.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color(Design.Palette.ink))
                                    if isActive {
                                        LXTag(text: "使用中", icon: "checkmark", tint: Color(Design.Palette.accent), filled: true)
                                    }
                                }
                                Text(pack.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Color(Design.Palette.stone))
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 4)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button {
                        let pack = CustomKeyboardLayoutPack.fromCurrentSettings(appState.settings)
                        if let data = pack.exportJSON() {
                            packExportDoc = LayoutPackJSONDocument(data: data)
                            showPackExporter = true
                        }
                    } label: {
                        Label("导出布局包 JSON", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))

                    Button {
                        showPackImporter = true
                    } label: {
                        Label("导入布局包", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                }
                .padding(.vertical, 2)
            } header: {
                Text("场景键盘布局包（支持分享与键盘内 1 键秒切）")
            } footer: {
                Text("对标仓输入法 / CustardKit：一键切换整套划动命令、数字行、标点与盘古空格配置，也可导出为 JSON 分享给朋友。")
            }

            Section {
                Button {
                    confirmHamsterPreset = true
                } label: {
                    LXNavRow(
                        icon: "bolt.circle.fill",
                        title: "仓输入法效率命令预设",
                        subtitle: "上滑 J取首字 K取尾字 · 下划 Z撤 X清 C润色 V贴 B三版 H/L光标 T译 F繁"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    confirmPreset = true
                } label: {
                    LXNavRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "编程符号预设",
                        subtitle: "A@  S/  D$  F()  G{}  H[]  K->"
                    )
                }
                .buttonStyle(.plain)

                if customizedCount > 0 {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Text("全部恢复默认")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                }
            } header: {
                Text("快捷操作")
            }
        }
        .navigationTitle("上下滑映射")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
        .onAppear { loadDrafts() }
        .onDisappear {
            if hasUnsavedChanges { saveCurrent(showToast: false) }
        }
        .confirmationDialog("应用仓输入法效率命令预设？", isPresented: $confirmHamsterPreset, titleVisibility: .visible) {
            Button("应用") {
                for (k, v) in KeyboardSwipeCommand.hamsterEfficiencyUpPreset {
                    appState.settings.customSwipeUpMap[k] = v
                }
                for (k, v) in KeyboardSwipeCommand.hamsterEfficiencyDownPreset {
                    appState.settings.customSwipeDownMap[k] = v
                }
                loadDrafts()
                toast = "已应用仓式动作命令预设（含以词定字与 AI 快捷划动）"
            }
        } message: {
            Text("会在 J/K 上滑绑定以词定字，并在 Z/X/C/V/B/H/L/T/F 下划绑定撤销、清空、AI 润色、粘贴、三版、光标与简繁切换。")
        }
        .confirmationDialog("应用编程符号预设？", isPresented: $confirmPreset, titleVisibility: .visible) {
            Button("应用") {
                for (k, v) in Self.geekPreset {
                    appState.settings.customSwipeDownMap[k] = v
                }
                loadDrafts()
                toast = "已应用编程符号预设"
            }
        } message: {
            Text("会覆盖 A、S、D、F、G、H、K 这 7 个键现有的下划设置。")
        }
        .confirmationDialog("全部恢复默认？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) {
                appState.settings.activeLayoutPackID = "standard"
                appState.settings.customSwipeUpMap = [:]
                appState.settings.customSwipeDownMap = [:]
                loadDrafts()
                toast = "已恢复默认上下滑"
            }
        } message: {
            Text("\(customizedCount) 个按键的自定义映射会被清除。")
        }
        .fileExporter(
            isPresented: $showPackExporter,
            document: packExportDoc,
            contentType: .json,
            defaultFilename: "lingxi-keymap-pack"
        ) { result in
            switch result {
            case .success:
                toast = "已导出灵犀自定义键盘布局包"
            case .failure(let err):
                let ns = err as NSError
                if !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) {
                    toast = "导出失败：\(err.localizedDescription)"
                }
            }
        }
        .fileImporter(isPresented: $showPackImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url),
                      let pack = CustomKeyboardLayoutPack.decodeJSON(data) else {
                    toast = "文件不是有效的灵犀布局包"
                    return
                }
                pack.apply(to: &appState.settings)
                loadDrafts()
                toast = "已导入并启用布局包「\(pack.name)」"
            case .failure(let err):
                let ns = err as NSError
                if !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) {
                    toast = "导入失败：\(err.localizedDescription)"
                }
            }
        }
    }

    private func keyCap(_ key: String) -> some View {
        let isSel = selectedKeyToEdit == key
        let upVal = appState.settings.customSwipeUpMap[key]
        let downVal = appState.settings.customSwipeDownMap[key]
        let customized = (upVal != nil || downVal != nil)
        return Button {
            guard key != selectedKeyToEdit else { return }
            if hasUnsavedChanges { saveCurrent(showToast: false) }
            selectedKeyToEdit = key
            loadDrafts()
        } label: {
            VStack(spacing: 0) {
                Text(upVal.map { KeyboardSwipeCommand.keycapBadge(for: $0) } ?? " ")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(isSel ? Color.white.opacity(0.85) : Color(Design.Palette.accent))
                    .lineLimit(1)
                Text(key.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSel ? Color.white : Color(Design.Palette.ink))
                Text(downVal.map { KeyboardSwipeCommand.keycapBadge(for: $0) } ?? " ")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(isSel ? Color.white.opacity(0.85) : Color(Design.Palette.accent))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                isSel ? Color(Design.Palette.accent) : (customized ? Color(Design.Palette.accentSoft) : Color(Design.Palette.surface)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("按键 \(key.uppercased())\(customized ? "，已自定义" : "")")
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    private func saveCurrent(showToast: Bool) {
        let up = customUpDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let dn = customDownDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if up.isEmpty {
            appState.settings.customSwipeUpMap.removeValue(forKey: selectedKeyToEdit)
        } else {
            appState.settings.customSwipeUpMap[selectedKeyToEdit] = up
        }
        if dn.isEmpty {
            appState.settings.customSwipeDownMap.removeValue(forKey: selectedKeyToEdit)
        } else {
            appState.settings.customSwipeDownMap[selectedKeyToEdit] = dn
        }
        if showToast {
            toast = "已保存「\(selectedKeyToEdit.uppercased())」"
        }
    }

    private func loadDrafts() {
        customUpDraft = savedUp
        customDownDraft = savedDown
    }
}

// MARK: - 保险箱新增 / 编辑 Sheet

private struct VaultItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: SecureVaultItem?
    let onSave: (SecureVaultItem) -> Void

    @State private var title: String
    @State private var category: String
    @State private var value: String

    private static let categoryPresets = ["证件", "银行卡", "开票", "地址", "账号"]

    init(initial: SecureVaultItem?, onSave: @escaping (SecureVaultItem) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _title = State(initialValue: initial?.title ?? "")
        _category = State(initialValue: initial?.category ?? "证件")
        _value = State(initialValue: initial?.value ?? "")
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("如：公司开票税号", text: $title)
                }

                Section {
                    LXFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Self.categoryPresets, id: \.self) { preset in
                            let selected = category == preset
                            Button {
                                category = preset
                            } label: {
                                Text(preset)
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
                    TextField("或输入自定义分类", text: $category)
                } header: {
                    Text("分类")
                }

                Section {
                    TextField("内容", text: $value, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.subheadline.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("内容")
                } footer: {
                    Text("只保存在这台设备上（受 iOS 数据保护加密），不参与云同步和备份。")
                }
            }
            .navigationTitle(initial == nil ? "新增条目" : "编辑条目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
                        let item = SecureVaultItem(
                            id: initial?.id ?? UUID().uuidString,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            category: cleanCategory.isEmpty ? "证件" : cleanCategory,
                            value: value.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSave(item)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}

// MARK: - L2 工具子页 4：个人速填名片夹（家/公司收件地址、企业开票、车牌联系）

struct PersonalFillCardsSubView: View {
    @State private var cards: [PersonalFillCard] = []
    @State private var showCreateSheet = false
    @State private var editingCard: PersonalFillCard?
    @State private var toast: String?

    var body: some View {
        List {
            Section {
                LXFlowLayout(spacing: 8, lineSpacing: 8) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("新建速填名片", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true))

                    Button {
                        importFromClipboard()
                    } label: {
                        Label("从剪贴板智能识别建卡", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                }
                .padding(.vertical, 4)
            } header: {
                Text("快捷操作")
            } footer: {
                Text("保存后可在键盘「剪贴板 → 名片」直接单字段点填，或在任意输入框打 vdz（地址）/ vkp（开票）/ vmp（名片）/ vcp（车牌）毫秒召唤。")
            }

            if cards.isEmpty {
                Section {
                    LXEmptyState(
                        icon: "person.text.rectangle.fill",
                        title: "还没有个人速填名片",
                        message: "复制一段收件地址或开票抬头点上方「智能识别建卡」，或手动新建一张常用名片。"
                    )
                }
            } else {
                Section("已存速填名片 · \(cards.count)") {
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: card.kind.systemIcon)
                                    .foregroundStyle(Color(Design.Palette.accent))
                                Text(card.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                Spacer()
                                LXTag(text: card.kind.displayTitle)
                            }
                            ForEach(card.nonEmptyFields) { field in
                                HStack(spacing: 8) {
                                    Text(field.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color(Design.Palette.stone))
                                        .frame(width: 48, alignment: .leading)
                                    Text(field.value)
                                        .font(.footnote)
                                        .foregroundStyle(Color(Design.Palette.ink))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button("复制") {
                                        UIPasteboard.general.string = field.value
                                        toast = "已复制\(field.label)"
                                    }
                                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                                }
                            }
                            HStack(spacing: 8) {
                                Button {
                                    UIPasteboard.general.string = card.formattedFullText
                                    toast = "已复制整张名片"
                                } label: {
                                    Label("复制整张", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                                Button {
                                    editingCard = card
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                            }
                            .padding(.top, 2)
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                PersonalFillCardStore.delete(id: card.id)
                                cards = PersonalFillCardStore.load()
                                toast = "已删除名片"
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("个人速填名片夹")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
        .onAppear {
            cards = PersonalFillCardStore.load()
        }
        .sheet(isPresented: $showCreateSheet) {
            PersonalFillCardEditorSheet(initial: nil) { saved in
                PersonalFillCardStore.upsert(saved)
                cards = PersonalFillCardStore.load()
                toast = "已保存「\(saved.title)」"
            }
        }
        .sheet(item: $editingCard) { card in
            PersonalFillCardEditorSheet(initial: card) { saved in
                PersonalFillCardStore.upsert(saved)
                cards = PersonalFillCardStore.load()
                toast = "已更新「\(saved.title)」"
            }
        }
    }

    private func importFromClipboard() {
        guard let raw = ConcealedPasteboard.readNonConcealedStringForUserPaste() else {
            toast = ConcealedPasteboard.isConcealed() ? "保险箱受保护机密不可直接导入普通名片夹" : "系统剪贴板为空"
            return
        }
        guard let card = PersonalFillCardStore.buildCardFromRawText(raw) else {
            toast = "未在剪贴板中识别到完整的收件地址或开票信息"
            return
        }
        PersonalFillCardStore.upsert(card)
        cards = PersonalFillCardStore.load()
        toast = "已智能建卡「\(card.title)」（\(card.fields.count) 项）"
    }
}

private struct PersonalFillCardEditorSheet: View {
    let initial: PersonalFillCard?
    let onSave: (PersonalFillCard) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var kind: PersonalCardKind
    @State private var fields: [PersonalCardField]

    init(initial: PersonalFillCard?, onSave: @escaping (PersonalFillCard) -> Void) {
        self.initial = initial
        self.onSave = onSave
        let k = initial?.kind ?? .homeAddress
        _title = State(initialValue: initial?.title ?? k.displayTitle)
        _kind = State(initialValue: k)
        _fields = State(initialValue: initial?.fields ?? k.defaultFieldLabels.map { PersonalCardField(label: $0, value: "") })
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fields.contains(where: { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名片名称（如：家里收件、公司开票）", text: $title)
                    Picker("类型", selection: $kind) {
                        ForEach(PersonalCardKind.allCases) { item in
                            Text("\(item.badgePrefix) \(item.displayTitle)").tag(item)
                        }
                    }
                    .onChange(of: kind) { newKind in
                        if initial == nil {
                            title = newKind.displayTitle
                            fields = newKind.defaultFieldLabels.map { PersonalCardField(label: $0, value: "") }
                        }
                    }
                }

                Section("结构化字段（键盘可逐项单点填入）") {
                    ForEach($fields) { $field in
                        HStack(spacing: 8) {
                            TextField("标签", text: $field.label)
                                .font(.caption.weight(.semibold))
                                .frame(width: 64)
                            TextField("填写内容", text: $field.value)
                                .font(.subheadline)
                        }
                    }
                    .onDelete { offsets in
                        fields.remove(atOffsets: offsets)
                    }
                    Button {
                        fields.append(PersonalCardField(label: "备注", value: ""))
                    } label: {
                        Label("添加字段", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(initial == nil ? "新建速填名片" : "编辑名片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let card = PersonalFillCard(
                            id: initial?.id ?? UUID(),
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            kind: kind,
                            fields: fields.filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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

// MARK: - L2 工具子页 5：草稿防丢黑匣子（24 小时纯本地留底）

struct DraftRecoverySubView: View {
    @State private var drafts: [SavedDraftRecord] = []
    @State private var confirmClearAll = false
    @State private var toast: String?

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Color(Design.Palette.success))
                    Text("仅保存在本机 24 小时后自动销毁、永不上云；密码框、无痕模式、银行卡/身份证与强密码均自动跳过。")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }

            if drafts.isEmpty {
                Section {
                    LXEmptyState(
                        icon: "clock.arrow.circlepath",
                        title: "暂无防丢草稿",
                        message: "当你在任意 App 打出 ≥18 字长内容并换行或切出时，会自动在这里留底，防止页面刷新或闪退丢字。"
                    )
                }
            } else {
                Section("最近 24 小时留底草稿 · \(drafts.count)") {
                    ForEach(drafts) { rec in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(rec.text)
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .lineLimit(5)
                                .textSelection(.enabled)
                            HStack(spacing: 8) {
                                LXTag(text: "\(rec.charCount) 字")
                                Text(rec.updatedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(Color(Design.Palette.stone))
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = rec.text
                                    toast = "已复制完整草稿"
                                } label: {
                                    Label("复制捞回", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                DraftRecoveryStore.delete(id: rec.id)
                                drafts = DraftRecoveryStore.load()
                                toast = "已删除草稿"
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("草稿防丢黑匣子")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
        .toolbar {
            if !drafts.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空", role: .destructive) {
                        confirmClearAll = true
                    }
                }
            }
        }
        .confirmationDialog("清空全部防丢草稿？", isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("全部清空", role: .destructive) {
                DraftRecoveryStore.clearAll()
                drafts = []
                toast = "已清空防丢草稿黑匣子"
            }
        }
        .onAppear {
            drafts = DraftRecoveryStore.load()
        }
    }
}

// MARK: - L2 工具子页 6：高情商离线话术口袋

struct SocialScriptBankSubView: View {
    @State private var query = ""
    @State private var selectedCategory: SocialScriptCategory? = nil
    @State private var selectedTone: SocialScriptTone? = nil
    @State private var toast: String?

    var body: some View {
        let items = SocialScriptBank.filter(category: selectedCategory, tone: selectedTone, query: query)
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color(Design.Palette.muted))
                    TextField("搜索场景（如：借钱、催还钱、迟到、闲鱼、押金…）", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        categoryChip(nil, title: "全部分类")
                        ForEach(SocialScriptCategory.allCases) { cat in
                            categoryChip(cat, title: cat.rawValue)
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        toneChip(nil, title: "全部语气")
                        ForEach(SocialScriptTone.allCases) { tone in
                            toneChip(tone, title: tone.rawValue)
                        }
                    }
                }
            }

            Section("精选离线话术 · \(items.count) 条（无需 API 密钥）") {
                if items.isEmpty {
                    LXEmptyState(icon: "text.bubble", title: "没有匹配的话术", message: "换个关键词或重置筛选条件试试。")
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                LXTag(text: item.scenario, tint: Color(Design.Palette.accent), filled: true)
                                LXTag(text: item.tone.rawValue)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = item.text
                                    toast = "已复制「\(item.scenario)」话术"
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                            }
                            Text(item.text)
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("高情商离线话术口袋")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
    }

    private func categoryChip(_ cat: SocialScriptCategory?, title: String) -> some View {
        let active = (selectedCategory == cat)
        return Button {
            selectedCategory = cat
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(height: 30)
                .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toneChip(_ tone: SocialScriptTone?, title: String) -> some View {
        let active = (selectedTone == tone)
        return Button {
            selectedTone = tone
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .foregroundStyle(active ? Color.white : Color(Design.Palette.stone))
                .background(active ? Color(Design.Palette.slate) : Color(Design.Palette.surface), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
