import AVFoundation
import Speech
import SwiftUI
import UIKit

struct ClipboardPhrasesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var segment = 0 // 0=剪贴板, 1=动态短语, 2=表情符号, 3=效率工具箱
    @State private var showAddPhrase = false
    @State private var newPhraseTitle = ""
    @State private var newPhraseContent = ""
    @State private var newPhraseCategory = "常用"
    @State private var emojiQuery = ""
    @State private var historySearchQuery = ""
    @State private var historyCategoryFilter = 0 // 0=全部, 1=验证码, 2=链接, 3=置顶
    @State private var emojiCategoryFilter = 0
    @State private var copiedSymbolToast: String?
    @State private var toolboxToast: String?

    // 跨屏 6 位匹配码实时剪贴板接力
    @State private var relayConfig: ClipboardRelayConfig = ClipboardRelayConfig.load()
    @State private var relayToast: String?
    @State private var isRelaying: Bool = false
    @State private var relaySSETask: Task<Void, Never>?

    // BigBang 炸词提取 Sheet
    @State private var bigBangSourceText: String?
    @State private var selectedBigBangTokens: [String] = []
    @State private var bigBangCustomCode: String = ""

    // 本地 Face ID 安全保险箱
    @State private var isVaultUnlocked = false
    @State private var showAddVaultItem = false
    @State private var editingVaultItem: SecureVaultItem?

    // 26 键自定义上滑/下滑符号编辑器
    @State private var selectedKeyToEdit: String = "q"
    @State private var customUpDraft: String = ""
    @State private var customDownDraft: String = ""

    // 语音输入与 AI 口语整编工作室
    @State private var showVoiceStudio = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("内容类型", selection: $segment) {
                    Text("剪贴板").tag(0)
                    Text("动态短语").tag(1)
                    Text("表情符号").tag(2)
                    Text("效率工具").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                if segment == 0 {
                    clipboardList
                } else if segment == 1 {
                    phrasesList
                } else if segment == 2 {
                    emojiKaomojiCatalogView
                } else {
                    efficiencyToolboxView
                }
            }
            .navigationTitle("效率中心")
            .onAppear {
                relayConfig = ClipboardRelayConfig.load()
                loadSelectedKeyDrafts()
                if relayConfig.autoRelayEnabled, !relayConfig.pairCode.isEmpty {
                    relaySSETask?.cancel()
                    relaySSETask = ClipboardRelayService.shared.subscribeRealtimeStream(pairCode: relayConfig.pairCode) { items in
                        appState.reloadClipboard()
                        if let first = items.first {
                            UIPasteboard.general.string = first.contentText
                            relayToast = "⚡ 实时跨屏收到：「\(first.contentText.prefix(24))」"
                        }
                    }
                }
            }
            .onDisappear {
                relaySSETask?.cancel()
                relaySSETask = nil
                isVaultUnlocked = false
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if segment == 0 {
                        Menu {
                            Button("从系统剪贴板导入当前内容") {
                                if let text = UIPasteboard.general.string, !text.isEmpty {
                                    appState.addClipboardEntry(text)
                                }
                            }
                            Button("清空未置顶记录", role: .destructive) {
                                appState.clearUnpinnedClipboard()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    } else if segment == 1 {
                        Button {
                            showAddPhrase = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    } else if segment == 3 {
                        Button {
                            showVoiceStudio = true
                        } label: {
                            Image(systemName: "mic.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddPhrase) {
                addPhraseSheet
            }
            .sheet(isPresented: $showAddVaultItem) {
                VaultItemEditorSheet(initial: nil) { created in
                    appState.upsertVaultItem(created)
                    toolboxToast = "✓ 已加密存入本机保险箱（绝不上云）"
                }
            }
            .sheet(item: $editingVaultItem) { item in
                VaultItemEditorSheet(initial: item) { updated in
                    appState.upsertVaultItem(updated)
                    toolboxToast = "✓ 已更新保险箱条目「\(updated.title)」"
                }
            }
            .sheet(isPresented: $showVoiceStudio) {
                VoiceDictationStudioSheet()
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

    // MARK: - 1. 剪贴板历史（分类筛选 + 跨屏接力 + BigBang + 一键排版）

    private var clipboardList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label("跨屏剪贴板接力 (6位码免登录秒传)", systemImage: "laptopcomputer.and.iphone")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(Design.Palette.ink))
                        Spacer()
                        Button {
                            relayConfig.pairCode = ClipboardRelayService.generateSixDigitCode()
                            relayConfig.save()
                        } label: {
                            Label("换码", systemImage: "arrow.clockwise")
                                .font(.caption2.bold())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        TextField("6位匹配码", text: $relayConfig.pairCode)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(width: 96)
                            .background(Color(Design.Palette.surface))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Button {
                            pushClipboardToRelay()
                        } label: {
                            Text("秒传本机")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(Color(Design.Palette.accent))
                                .foregroundStyle(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRelaying)

                        Button {
                            pullClipboardFromRelay()
                        } label: {
                            Text("拉取跨屏")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(Color(Design.Palette.surface))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isRelaying)
                    }

                    if let msg = relayToast {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("在电脑 Web 控制台 (/dashboard) 输入相同 6 位匹配码即可免登录双向秒传；L1 敏感身份证/银行卡/密码自动拦截。")
            }

            if appState.clipboardItems.isEmpty {
                Section("本机剪贴板历史") {
                    Text("暂无剪贴板历史。复制任意内容切出键盘或点右上角导入，就会自动识别验证码、链接与语境 AI 快捷动作。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            } else {
                let q = historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let filtered = appState.clipboardItems.filter { item in
                    switch historyCategoryFilter {
                    case 1: if item.category != .code && item.extractedCode == nil { return false }
                    case 2: if item.category != .url { return false }
                    case 3: if !item.isPinned { return false }
                    default: break
                    }
                    if q.isEmpty { return true }
                    return item.text.lowercased().contains(q) || (item.extractedCode?.contains(q) ?? false)
                }
                Section("本机剪贴板历史 (\(filtered.count))") {
                    TextField("搜索剪贴板历史或验证码…", text: $historySearchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("筛选", selection: $historyCategoryFilter) {
                        Text("全部").tag(0)
                        Text("验证码").tag(1)
                        Text("链接").tag(2)
                        Text("置顶").tag(3)
                    }
                    .pickerStyle(.segmented)

                    ForEach(filtered) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.text)
                                .font(.body)
                                .lineLimit(4)
                            HStack(spacing: 8) {
                                Label(item.category.badgeText, systemImage: item.category.systemIconName)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                if let code = item.extractedCode {
                                    Text("验证码: \(code)")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(Design.Palette.accentSoft))
                                        .foregroundStyle(Color(Design.Palette.accent))
                                        .clipShape(Capsule())
                                }
                                if item.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                Spacer()

                                Button {
                                    selectedBigBangTokens = []
                                    bigBangCustomCode = ""
                                    bigBangSourceText = item.text
                                } label: {
                                    Label("炸词", systemImage: "scissors")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color(Design.Palette.surface))
                                        .foregroundStyle(Color(Design.Palette.ink))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Text(item.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                appState.togglePinClipboard(id: item.id)
                            } label: {
                                Label(item.isPinned ? "取消置顶" : "置顶", systemImage: item.isPinned ? "pin.slash" : "pin")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                appState.deleteClipboard(id: item.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button("复制原文") { UIPasteboard.general.string = item.text }
                            Button("加盘古空格并复制") {
                                UIPasteboard.general.string = TextFormatterToolbox.addPanguSpaces(item.text)
                            }
                            Button("去多余空行并复制") {
                                UIPasteboard.general.string = TextFormatterToolbox.collapseBlankLines(item.text)
                            }
                            Button("整理为编号清单并复制") {
                                UIPasteboard.general.string = TextFormatterToolbox.toNumberedList(item.text)
                            }
                            Button("BigBang 炸词提取") {
                                selectedBigBangTokens = []
                                bigBangCustomCode = ""
                                bigBangSourceText = item.text
                            }
                            Button(item.isPinned ? "取消置顶" : "置顶") { appState.togglePinClipboard(id: item.id) }
                            Button("删除", role: .destructive) { appState.deleteClipboard(id: item.id) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 2. 动态变量快捷短语（支持 {{日期}} / {{时间}} / {{剪贴板}} / {{随机问候}} 实时渲染）

    private var phrasesList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("支持动态变量占位符（实时渲染上屏）", systemImage: "curlybraces")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(Design.Palette.accent))
                    Text("在短语正文中使用 {{日期}}、{{时间}}、{{星期}}、{{剪贴板}}、{{随机问候}}，键盘插入时自动替换为最新实时值。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                Button {
                    newPhraseTitle = "今日汇报头"
                    newPhraseCategory = "动态模板"
                    newPhraseContent = "{{随机问候}}！今日（{{日期}} {{星期}} {{时间}}）进展同步如下："
                    showAddPhrase = true
                } label: {
                    Label("一键新建「动态日期汇报」模板", systemImage: "wand.and.stars")
                        .font(.subheadline.bold())
                }
            }

            Section("我的快捷短语 (\(appState.quickPhrases.count)) · 点按渲染并复制") {
                ForEach(appState.quickPhrases) { phrase in
                    let hasVars = DynamicTemplateEngine.containsVariables(phrase.content)
                    let rendered = hasVars ? DynamicTemplateEngine.render(phrase.content) : phrase.content
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(phrase.title).font(.headline)
                            if hasVars {
                                Text("动态")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(Design.Palette.accentSoft))
                                    .foregroundStyle(Color(Design.Palette.accent))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Text(phrase.category)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        Text(phrase.content)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if hasVars {
                            Text("实时预览：\(rendered)")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.accent))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIPasteboard.general.string = rendered
                        appState.addClipboardEntry(rendered)
                        toolboxToast = "✓ 已复制渲染结果：「\(rendered.prefix(24))」"
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            appState.deleteQuickPhrase(id: phrase.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 3. 表情与颜文字

    private var emojiKaomojiCatalogView: some View {
        let allHits = EmojiCatalog.search(emojiQuery, limit: 80)
        let hits = allHits.filter { entry in
            switch emojiCategoryFilter {
            case 1: return !entry.isSymbol
            case 2: return entry.isSymbol && entry.symbol.count > 1
            case 3: return entry.isSymbol && entry.symbol.count == 1
            default: return true
            }
        }
        return List {
            Section {
                TextField("输入中文或拼音搜索表情/颜文字（如：开心、掀桌、箭头）", text: $emojiQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("分类筛选", selection: $emojiCategoryFilter) {
                    Text("全部").tag(0)
                    Text("表情 Emoji").tag(1)
                    Text("颜文字").tag(2)
                    Text("特殊符号").tag(3)
                }
                .pickerStyle(.segmented)

                if let toast = copiedSymbolToast {
                    Text(toast)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.success))
                }
            }

            let recentSymbols = RecentEmojiStore.load()
            if !recentSymbols.isEmpty {
                Section("最近常用（点按即复制）") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(recentSymbols.prefix(16), id: \.self) { sym in
                                Button {
                                    UIPasteboard.general.string = sym
                                    appState.addClipboardEntry(sym)
                                    copiedSymbolToast = "✓ 已复制「\(sym)」，切出键盘即可一键粘贴"
                                } label: {
                                    Text(sym)
                                        .font(.system(size: 22))
                                        .frame(width: 38, height: 38)
                                        .background(Color(Design.Palette.surface))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("精选表情、颜文字与特殊符号 (\(hits.count))") {
                ForEach(hits, id: \.symbol) { entry in
                    Button {
                        UIPasteboard.general.string = entry.symbol
                        RecentEmojiStore.record(entry.symbol)
                        appState.addClipboardEntry(entry.symbol)
                        copiedSymbolToast = "✓ 已复制「\(entry.symbol)」，切出键盘顶栏一键粘贴"
                    } label: {
                        HStack(spacing: 12) {
                            Text(entry.symbol)
                                .font(.system(size: entry.isSymbol ? 16 : 22))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text(entry.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("点按复制")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 4. 效率工具箱（Face ID 敏感保险箱 + 26键上下滑符号映射 + 语音 AI 整编 + 一键排版）

    private var efficiencyToolboxView: some View {
        List {
            if let toast = toolboxToast {
                Section {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.success))
                }
            }

            // 4A. 语音输入与 AI 口语整编工作室
            Section {
                Button {
                    showVoiceStudio = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(Design.Palette.accentSoft))
                                .frame(width: 40, height: 40)
                            Image(systemName: "waveform.and.mic")
                                .font(.headline)
                                .foregroundStyle(Color(Design.Palette.accent))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("🎙️ 语音输入与 AI 口语整编")
                                .font(.subheadline.bold())
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text("原生语音实时转中文 -> 一键 AI 去口水词加标点 -> 复制即走")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } header: {
                Text("语音直写工作室")
            }

            // 4B. 剪贴板一键排版微整形
            Section {
                HStack(spacing: 8) {
                    formatButton("盘古空格") { TextFormatterToolbox.addPanguSpaces($0) }
                    formatButton("去多余空行") { TextFormatterToolbox.collapseBlankLines($0) }
                    formatButton("1. 编号清单") { TextFormatterToolbox.toNumberedList($0) }
                    formatButton("• 项目符号") { TextFormatterToolbox.toBulletList($0) }
                }
                .padding(.vertical, 4)
            } header: {
                Text("🪄 剪贴板一键排版微整形")
            } footer: {
                Text("直接对当前系统剪贴板文本做无损排版整形并写回剪贴板，切回微信/备忘录即可粘贴。")
            }

            // 4C. Face ID 本地加密敏感信息保险箱（100% 留存本机，永不上云）
            Section {
                if !isVaultUnlocked {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield.fill")
                                .font(.title2)
                                .foregroundStyle(Color(Design.Palette.accent))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("已锁定 · \(appState.secureVaultItems.count) 条敏感凭证")
                                    .font(.subheadline.bold())
                                Text("身份证、税号、银行卡与常用地址仅存本机受保护容器，永不上传任何云端。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            Task { await unlockVaultWithBiometrics() }
                        } label: {
                            Label("用\(BiometricAuthHelper.biometryDisplayName())解锁保险箱", systemImage: "faceid")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Color(Design.Palette.accent))
                                .foregroundStyle(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                } else {
                    HStack {
                        Label("已通过生物验证解锁", systemImage: "lock.open.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color(Design.Palette.success))
                        Spacer()
                        Button("立即上锁") { isVaultUnlocked = false }
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    ForEach(appState.secureVaultItems) { item in
                        HStack {
                            Button {
                                editingVaultItem = item
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.title).font(.subheadline.bold()).foregroundStyle(.primary)
                                        Text(item.category).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Text(item.value)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button("复制") {
                                // 仅写入系统剪贴板供 30 秒内粘贴，绝不写入 Lingxi 剪贴板历史
                                UIPasteboard.general.string = item.value
                                toolboxToast = "✓ 已安全复制「\(item.title)」（未写入剪贴板历史）"
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(Design.Palette.accentSoft))
                            .foregroundStyle(Color(Design.Palette.accent))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { appState.secureVaultItems[$0].id }
                        for id in ids { appState.deleteVaultItem(id: id) }
                    }

                    Button {
                        showAddVaultItem = true
                    } label: {
                        Label("新增敏感安全条目", systemImage: "plus.circle.fill")
                            .font(.subheadline.bold())
                    }
                }
            } header: {
                Text("🔐 本地 Face ID 加密安全保险箱（绝不上云）")
            }

            // 4D. 26 键自定义上滑/下滑符号映射编辑器
            Section {
                let rows: [[String]] = [
                    ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                    ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                    ["z", "x", "c", "v", "b", "n", "m"]
                ]
                VStack(spacing: 6) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(row, id: \.self) { key in
                                let isSel = selectedKeyToEdit == key
                                let upVal = appState.settings.customSwipeUpMap[key]
                                let downVal = appState.settings.customSwipeDownMap[key]
                                let customized = (upVal != nil || downVal != nil)
                                Button {
                                    selectedKeyToEdit = key
                                    loadSelectedKeyDrafts()
                                } label: {
                                    VStack(spacing: 1) {
                                        Text(upVal ?? " ")
                                            .font(.system(size: 8))
                                            .foregroundStyle(isSel ? Color.white.opacity(0.9) : Color(Design.Palette.accent))
                                        Text(key.uppercased())
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(isSel ? Color.white : Color(Design.Palette.ink))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                                    .background(isSel ? Color(Design.Palette.accent) : (customized ? Color(Design.Palette.accentSoft) : Color(Design.Palette.surface)))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("当前编辑按键：「\(selectedKeyToEdit.uppercased())」")
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.accent))

                    HStack(spacing: 8) {
                        Text("上滑输出").font(.caption).frame(width: 56, alignment: .leading)
                        TextField("留空使用默认数字/符号", text: $customUpDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(8)
                            .background(Color(Design.Palette.surface))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    HStack(spacing: 8) {
                        Text("下滑输出").font(.caption).frame(width: 56, alignment: .leading)
                        TextField("如 () / 「」 / 常用词（可选）", text: $customDownDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(8)
                            .background(Color(Design.Palette.surface))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    HStack(spacing: 8) {
                        Button("保存「\(selectedKeyToEdit.uppercased())」映射") {
                            let up = customUpDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            let dn = customDownDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if up.isEmpty { appState.settings.customSwipeUpMap.removeValue(forKey: selectedKeyToEdit) }
                            else { appState.settings.customSwipeUpMap[selectedKeyToEdit] = up }
                            if dn.isEmpty { appState.settings.customSwipeDownMap.removeValue(forKey: selectedKeyToEdit) }
                            else { appState.settings.customSwipeDownMap[selectedKeyToEdit] = dn }
                            toolboxToast = "✓ 已保存按键「\(selectedKeyToEdit.uppercased())」自定义滑行映射"
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color(Design.Palette.accent))
                        .foregroundStyle(Color.white)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)

                        Button("极客编程预设") {
                            appState.settings.customSwipeDownMap["a"] = "@"
                            appState.settings.customSwipeDownMap["s"] = "/"
                            appState.settings.customSwipeDownMap["d"] = "$"
                            appState.settings.customSwipeDownMap["f"] = "()"
                            appState.settings.customSwipeDownMap["g"] = "{}"
                            appState.settings.customSwipeDownMap["h"] = "[]"
                            appState.settings.customSwipeDownMap["k"] = "->"
                            loadSelectedKeyDrafts()
                            toolboxToast = "✓ 已应用极客编程下滑符号预设（已同步至键盘）"
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(Color(Design.Palette.surface))
                        .foregroundStyle(Color(Design.Palette.ink))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)

                        Spacer()

                        if !appState.settings.customSwipeUpMap.isEmpty || !appState.settings.customSwipeDownMap.isEmpty {
                            Button("重置") {
                                appState.settings.customSwipeUpMap = [:]
                                appState.settings.customSwipeDownMap = [:]
                                loadSelectedKeyDrafts()
                                toolboxToast = "已恢复 26 键默认上下滑符号"
                            }
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.error))
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("⌨️ 26 键自定义上滑 / 下滑映射编辑器（实时云同步）")
            } footer: {
                Text("点选任意字母键可自由改写上滑与下滑输出（支持符号、成对括号或常用短词），保存后键盘立即生效并自动随 E2EE 云同步。")
            }
        }
    }

    private func formatButton(_ title: String, transform: @escaping (String) -> String) -> some View {
        Button {
            guard let raw = UIPasteboard.general.string, !raw.isEmpty else {
                toolboxToast = "当前系统剪贴板为空，请先复制一段文字"
                return
            }
            let out = transform(raw)
            UIPasteboard.general.string = out
            appState.addClipboardEntry(out)
            toolboxToast = "✓ 已完成「\(title)」并写回剪贴板"
        } label: {
            Text(title)
                .font(.caption2.bold())
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Color(Design.Palette.surface))
                .foregroundStyle(Color(Design.Palette.ink))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func loadSelectedKeyDrafts() {
        customUpDraft = appState.settings.customSwipeUpMap[selectedKeyToEdit] ?? ""
        customDownDraft = appState.settings.customSwipeDownMap[selectedKeyToEdit] ?? ""
    }

    private func unlockVaultWithBiometrics() async {
        do {
            try await BiometricAuthHelper.verify(reason: "验证身份以查看本机加密敏感信息保险箱")
            isVaultUnlocked = true
        } catch {
            toolboxToast = "解锁失败：\(error.localizedDescription)"
        }
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
                                    .font(.system(size: 13.5, weight: .medium))
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
                .padding()
            }
            .navigationTitle("BigBang 炸词提取")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { bigBangSourceText = nil } }
            }
        }
    }

    // MARK: - 跨屏剪贴板动作

    private func pushClipboardToRelay() {
        let content = UIPasteboard.general.string ?? appState.clipboardItems.first?.text ?? ""
        guard !content.isEmpty else {
            relayToast = "本机剪贴板为空，请先复制一段内容"
            return
        }
        isRelaying = true
        relayConfig.save()
        Task {
            do {
                let item = try await ClipboardRelayService.shared.push(text: content, pairCode: relayConfig.pairCode)
                await MainActor.run {
                    isRelaying = false
                    appState.refreshAll()
                    relayToast = item.extractedCode != nil
                        ? "✓ 已秒传至匹配码 \(item.pairCode)（识别验证码 \(item.extractedCode!)）"
                        : "✓ 已秒传至匹配码 \(item.pairCode)"
                }
            } catch {
                await MainActor.run {
                    isRelaying = false
                    relayToast = error.localizedDescription
                }
            }
        }
    }

    private func pullClipboardFromRelay() {
        isRelaying = true
        relayConfig.save()
        Task {
            do {
                let items = try await ClipboardRelayService.shared.pullLatest(pairCode: relayConfig.pairCode)
                await MainActor.run {
                    isRelaying = false
                    appState.refreshAll()
                    if let first = items.first {
                        UIPasteboard.general.string = first.contentText
                        relayToast = "✓ 已接力：「\(first.contentText.prefix(24))」"
                    } else {
                        relayToast = "匹配码 \(relayConfig.pairCode) 暂无跨屏剪贴板记录"
                    }
                }
            } catch {
                await MainActor.run {
                    isRelaying = false
                    relayToast = error.localizedDescription
                }
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

// MARK: - 保险箱新增 / 编辑 Sheet

private struct VaultItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: SecureVaultItem?
    let onSave: (SecureVaultItem) -> Void

    @State private var title: String
    @State private var category: String
    @State private var value: String

    init(initial: SecureVaultItem?, onSave: @escaping (SecureVaultItem) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _title = State(initialValue: initial?.title ?? "")
        _category = State(initialValue: initial?.category ?? "证件/账务")
        _value = State(initialValue: initial?.value ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称（如：公司开票税号 / 身份证号）", text: $title)
                TextField("分类（如：证件、银行卡、开票、地址）", text: $category)
                TextField("敏感信息正文（仅存本机安全容器，绝不上云）", text: $value, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(size: 14, design: .monospaced))
            }
            .navigationTitle(initial == nil ? "新增敏感凭证" : "编辑敏感凭证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let item = SecureVaultItem(
                            id: initial?.id ?? UUID().uuidString,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "证件/账务" : category,
                            value: value.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSave(item)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - 原生语音识别 + AI 口语整编工作室 (SFSpeechRecognizer)

@MainActor
private final class VoiceDictationController: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var statusText: String = "点击下方麦克风开始中文语音识别"

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    func toggleRecording() {
        if isRecording {
            stop()
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        let authStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
        guard authStatus == .authorized else {
            statusText = "请在系统设置中开启「语音识别」权限"
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            statusText = "当前设备语音识别服务暂不可用"
            return
        }

        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            self.recognitionRequest = req

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            isRecording = true
            statusText = "正在聆听… 说完点击停止，可一键 AI 整理标点"

            recognitionTask = speechRecognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal == true) {
                        self.stop()
                    }
                }
            }
        } catch {
            statusText = "麦克风启动失败：\(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct VoiceDictationStudioSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = VoiceDictationController()
    @State private var polishedOutput = ""
    @State private var isPolishing = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(controller.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Button {
                        controller.toggleRecording()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: controller.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title2)
                            Text(controller.isRecording ? "停止录音" : "开始说话（实时中文转写）")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(controller.isRecording ? Color(Design.Palette.error) : Color(Design.Palette.accent))
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("语音识别原文（可直接修改）")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextEditor(text: $controller.transcript)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await polishTranscriptWithAI() }
                        } label: {
                            HStack {
                                if isPolishing { ProgressView().tint(.white) }
                                Text(isPolishing ? "AI 整编中…" : "✨ AI 去口水词并加标点")
                                    .font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(Color(Design.Palette.accent))
                            .foregroundStyle(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isPolishing || controller.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            let text = polishedOutput.isEmpty ? controller.transcript : polishedOutput
                            guard !text.isEmpty else { return }
                            UIPasteboard.general.string = text
                            appState.addClipboardEntry(text)
                            toast = "✓ 已复制，切回任意聊天软件点键盘顶栏即粘贴"
                        } label: {
                            Text("复制")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 16)
                                .frame(height: 42)
                                .background(Color(.secondarySystemGroupedBackground))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if !polishedOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("✨ AI 书面整编结果")
                                .font(.caption.bold())
                                .foregroundStyle(Color(Design.Palette.accent))
                            Text(polishedOutput)
                                .font(.body)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    if let toast {
                        Text(toast)
                            .font(.caption.bold())
                            .foregroundStyle(Color(Design.Palette.success))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("语音直写与 AI 整编")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        controller.stop()
                        dismiss()
                    }
                }
            }
            .onDisappear { controller.stop() }
        }
    }

    private func polishTranscriptWithAI() async {
        let raw = controller.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isPolishing = true
        polishedOutput = ""
        defer { isPolishing = false }
        let client = AIClient(timeout: 35)
        do {
            for try await chunk in client.streamText(
                prompt: raw,
                systemInstruction: AIPresetAction.organizeVoice.systemPrompt,
                config: appState.aiConfig,
                featureTag: "voice_polish"
            ) {
                polishedOutput += chunk
            }
        } catch {
            // 离线回退：自动盘古空格 + 清理空白
            polishedOutput = TextFormatterToolbox.addPanguSpaces(TextFormatterToolbox.collapseBlankLines(raw))
            toast = "未配置 AI 密钥，已使用端侧规则整编"
        }
    }
}
