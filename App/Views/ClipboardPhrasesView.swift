import SwiftUI
import UIKit

struct ClipboardPhrasesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var segment = 0
    @State private var showAddPhrase = false
    @State private var newPhraseTitle = ""
    @State private var newPhraseContent = ""
    @State private var newPhraseCategory = "常用"
    @State private var emojiQuery = ""
    @State private var emojiCategoryFilter = 0 // 0=全部, 1=Emoji, 2=颜文字, 3=特殊符号
    @State private var copiedSymbolToast: String?

    // 跨屏 6 位匹配码实时剪贴板接力
    @State private var relayConfig: ClipboardRelayConfig = ClipboardRelayConfig.load()
    @State private var relayToast: String?
    @State private var isRelaying: Bool = false

    // BigBang 炸词分词提取 Sheet
    @State private var bigBangSourceText: String?
    @State private var selectedBigBangTokens: [String] = []
    @State private var bigBangCustomCode: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("内容类型", selection: $segment) {
                    Text("剪贴板历史").tag(0)
                    Text("快捷短语").tag(1)
                    Text("表情与颜文字").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                if segment == 0 {
                    clipboardList
                } else if segment == 1 {
                    phrasesList
                } else {
                    emojiKaomojiCatalogView
                }
            }
            .navigationTitle("剪贴板与短语")
            .onAppear {
                relayConfig = ClipboardRelayConfig.load()
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
                    }
                }
            }
            .sheet(isPresented: $showAddPhrase) {
                addPhraseSheet
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

    // MARK: - 1. 剪贴板历史（含顶部 6 位码跨屏实时剪贴板接力 + BigBang 炸词提取）

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
                                .background(Color(Design.Palette.ink))
                                .foregroundStyle(Color(Design.Palette.canvas))
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
                            .foregroundStyle(Color(Design.Palette.ink))
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("在电脑 Web 控制台 (/dashboard) 或另一台设备输入相同 6 位匹配码，即可双向秒传剪贴板与短信验证码；L1 敏感身份证/银行卡/密码自动拦截。")
            }

            if appState.clipboardItems.isEmpty {
                Section("本机剪贴板历史") {
                    Text("暂无剪贴板历史。在键盘顶部看到「刚复制」接管胶囊后点击粘贴，或点右上角导入，就会安全保存到本地历史与常用置顶中。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            } else {
                Section("本机剪贴板历史 (\(appState.clipboardItems.count))") {
                    ForEach(appState.clipboardItems) { item in
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
                                        .background(Color(Design.Palette.surfaceSoft))
                                        .foregroundStyle(Color(Design.Palette.ink))
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
                                    Label("炸词提取", systemImage: "scissors")
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
                            Button("复制到剪贴板") {
                                UIPasteboard.general.string = item.text
                            }
                            Button("BigBang 炸词提取") {
                                selectedBigBangTokens = []
                                bigBangCustomCode = ""
                                bigBangSourceText = item.text
                            }
                            Button(item.isPinned ? "取消置顶" : "置顶") {
                                appState.togglePinClipboard(id: item.id)
                            }
                            Button("删除", role: .destructive) {
                                appState.deleteClipboard(id: item.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 2. 快捷短语

    private var phrasesList: some View {
        List {
            ForEach(appState.quickPhrases) { phrase in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(phrase.title).font(.headline)
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
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    UIPasteboard.general.string = phrase.content
                    appState.addClipboardEntry(phrase.content)
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

    // MARK: - 3. 表情与颜文字（从键盘顶栏迁入主 App 统一管理，支持分类筛选）

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
            } footer: {
                Text("表情与颜文字面板已从键盘顶栏移至此处统一管理。点按任意条目即复制到剪贴板，切回键盘时顶栏会自动全栏接管显示为您复制的内容供一键粘贴。")
            }

            Section("精选表情、颜文字与特殊符号 (\(hits.count))") {
                ForEach(hits, id: \.symbol) { entry in
                    Button {
                        UIPasteboard.general.string = entry.symbol
                        appState.addClipboardEntry(entry.symbol)
                        copiedSymbolToast = "✓ 已复制「\(entry.symbol)」，切出键盘即可在顶栏一键粘贴"
                    } label: {
                        HStack(spacing: 12) {
                            Text(entry.symbol)
                                .font(.system(size: entry.isSymbol ? 16 : 22))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text(entry.name)
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.stone))
                            Spacer()
                            Text("点按复制")
                                .font(.caption2)
                                .foregroundStyle(Color(Design.Palette.steel))
                        }
                    }
                }
            }
        }
    }

    // MARK: - BigBang 炸词提取与造词 Sheet

    private var bigBangSheet: some View {
        let source = bigBangSourceText ?? ""
        let tokens = BigBangTokenizer.tokenize(source)
        let combined = selectedBigBangTokens.joined()

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("点按下方分词块即可自由拼接提取，一键复制或直接存为自定义编码短语：")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // 词块流式排布
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
                                    .background(isChosen ? Color(Design.Palette.ink) : Color(Design.Palette.surface))
                                    .foregroundStyle(isChosen ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !combined.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("已拼接内容：\(combined)")
                                .font(.subheadline.bold())

                            HStack(spacing: 10) {
                                Button {
                                    UIPasteboard.general.string = combined
                                    appState.addClipboardEntry(combined)
                                    bigBangSourceText = nil
                                } label: {
                                    Label("复制选中词", systemImage: "doc.on.doc")
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(Color(Design.Palette.ink))
                                        .foregroundStyle(Color(Design.Palette.canvas))
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    selectedBigBangTokens = []
                                } label: {
                                    Text("重选")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 36)
                                        .background(Color(Design.Palette.surface))
                                        .foregroundStyle(Color(Design.Palette.ink))
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 8) {
                                TextField("输入快捷编码 (如 dz)", text: $bigBangCustomCode)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(8)
                                    .background(Color(Design.Palette.surface))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                Button("存入自定义短语") {
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
                        .background(Color(Design.Palette.canvas))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("BigBang 炸词提取")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { bigBangSourceText = nil }
                }
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
                    if let otp = item.extractedCode {
                        relayToast = "✓ 已秒传至匹配码 \(item.pairCode)（识别验证码 \(otp)）"
                    } else {
                        relayToast = "✓ 已秒传至匹配码 \(item.pairCode)"
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
                        relayToast = "✓ 已接力：「\(first.contentText.prefix(24))」，切出键盘顶栏直接粘贴"
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

    private var addPhraseSheet: some View {
        NavigationStack {
            Form {
                TextField("标题（如：收货地址）", text: $newPhraseTitle)
                TextField("分类（如：生活、职场、趣味）", text: $newPhraseCategory)
                TextField("短语正文", text: $newPhraseContent, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("新增快捷短语")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showAddPhrase = false }
                }
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
