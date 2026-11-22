import SwiftUI
import UIKit

/// 设置中心：分类入口首页 + 各分类二级页。
/// 原「词库与设置」单页 40+ 项设置扁平堆叠、词库管理被淹没，
/// 重构为 6 个分类入口，每类一屏，词库管理独立成页。
struct DictionarySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("lastBackupExportAt") private var lastBackupExportAt: Double = 0
    @State private var showAppleSignInSheet = false

    var body: some View {
        NavigationStack {
            List {
                // 对标 Apple iOS「设置」顶部第一栏：圆形头像 + Apple Account 卡片
                Section {
                    if appState.isCloudAuthenticated {
                        NavigationLink {
                            CloudAccountView()
                        } label: {
                            appleAccountHeaderRow(
                                title: appState.cloudConfig.username.isEmpty ? "灵犀账号" : appState.cloudConfig.username,
                                subtitle: appState.cloudConfig.email.isEmpty ? "E2EE 云同步 · 跨屏剪贴板 · 习惯画像" : appState.cloudConfig.email,
                                isSignedIn: true
                            )
                        }
                    } else {
                        Button {
                            showAppleSignInSheet = true
                        } label: {
                            HStack {
                                appleAccountHeaderRow(
                                    title: "登录灵犀账号",
                                    subtitle: "设置端到端同步、跨屏剪贴板与习惯画像",
                                    isSignedIn: false
                                )
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            CloudAccountView()
                        } label: {
                            Label("跨屏剪贴板与自托管服务器设置", systemImage: "laptopcomputer.and.iphone")
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.ink))
                        }
                    }
                }

                Section("输入体验") {
                    settingsLink(icon: "keyboard", tint: Design.Palette.ink, title: "输入方案与布局",
                                 subtitle: appState.settings.inputScheme.displayName + " · " + appState.settings.layoutMode.displayName) {
                        SchemeLayoutSettingsView()
                    }
                    settingsLink(icon: "hand.tap", tint: Design.Palette.ink, title: "键盘手感",
                                 subtitle: "震动 " + appState.settings.hapticStrength.displayName + (appState.settings.keySoundEnabled ? " · 音效开" : " · 音效关")) {
                        KeyboardFeelSettingsView()
                    }
                    settingsLink(icon: "rectangle.3.offgrid", tint: Design.Palette.ink, title: "键盘工具栏",
                                 subtitle: "按钮排序 · 候选栏高度与字号") {
                        ToolbarSettingsView()
                    }
                    settingsLink(icon: "wand.and.stars", tint: Design.Palette.ink, title: "智能输入",
                                 subtitle: "纠错 · 联想 · 剪贴板") {
                        SmartInputSettingsView()
                    }
                    settingsLink(icon: "waveform", tint: Design.Palette.ink, title: "模糊音",
                                 subtitle: "16 组全覆盖") {
                        FuzzyPinyinSettingsView()
                    }
                    settingsLink(icon: "textformat.abc", tint: Design.Palette.ink, title: "趣味字体",
                                 subtitle: stylishFontName) {
                        StylishFontSettingsView()
                    }
                }

                Section("词库、数据与可持续生态") {
                    settingsLink(icon: "book.closed", tint: Design.Palette.ink, title: "词库管理与社区词包",
                                 subtitle: "自定义短语 \(appState.customWords.count) · 个人词库 \(appState.userWords.count)") {
                        LexiconSettingsView()
                    }
                    settingsLink(icon: "chart.bar", tint: Design.Palette.ink, title: "打字统计与本机画像",
                                 subtitle: "今日 \(TypingStatsStore.shared.summary().todayChars) 字 · 近 30 天与 24h 节律") {
                        TypingStatsView()
                    }
                    settingsLink(icon: "externaldrive", tint: Design.Palette.ink, title: "加密备份与恢复",
                                 subtitle: backupSubtitle) {
                        BackupSettingsView()
                    }
                    settingsLink(icon: "leaf.arrow.triangle.circlepath", tint: Design.Palette.ink, title: "可持续发展 · 三模同步 · 引擎自愈",
                                 subtitle: sustainabilitySubtitle) {
                        SustainabilityHubView()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .sheet(isPresented: $showAppleSignInSheet) {
                AppleStyleSignInSheet()
            }
        }
    }

    private func appleAccountHeaderRow(title: String, subtitle: String, isSignedIn: Bool) -> some View {
        HStack(spacing: 14) {
            UserAvatarView(size: 60, showEditBadge: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSignedIn ? Color(Design.Palette.ink) : Color.accentColor)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var stylishFontName: String {
        StylishFontStyle(rawValue: appState.settings.stylishFontID)?.displayName ?? "常规"
    }

    private var cloudAccountSubtitle: String {
        let tags = appState.habitProfile.habitTags
        let tagSummary = tags.first ?? "实时画像就绪"
        if appState.isCloudAuthenticated {
            let user = appState.cloudConfig.username.isEmpty ? "API Key 已连接" : appState.cloudConfig.username
            return "\(user) · \(tagSummary)"
        }
        return "登录 / 接入 API Key · 6位码跨屏剪贴板 · \(tagSummary)"
    }

    private var sustainabilitySubtitle: String {
        let health = EngineHealthAndSustainabilityService.shared.diagnose()
        return "健康度 \(health.healthScore) 分 · \(health.activeTransport.title) · \(health.activePlan.badgeText)"
    }

    private var backupSubtitle: String {
        guard lastBackupExportAt > 0 else { return "加密备份 · 从未导出" }
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return "上次备份 " + fmt.string(from: Date(timeIntervalSince1970: lastBackupExportAt))
    }

    private func settingsLink<Destination: View>(icon: String, tint: UIColor, title: String, subtitle: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(tint))
                    .frame(width: 30, height: 30)
                    .background(Color(Design.Palette.surface))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 输入方案与布局

private struct SchemeLayoutSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("输入方案与布局") {
                Picker("键盘布局", selection: $appState.settings.layoutMode) {
                    ForEach(KeyboardLayoutMode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                Picker("输入方案", selection: $appState.settings.inputScheme) {
                    ForEach(InputScheme.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                Picker("中文标点样式", selection: $appState.settings.punctuationStyle) {
                    ForEach(PunctuationStyle.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                Picker("单手模式", selection: $appState.settings.handedness) {
                    ForEach(HandednessMode.allCases) { h in
                        Text(h.displayName).tag(h)
                    }
                }
                Picker("键盘高度", selection: $appState.settings.heightPreset) {
                    ForEach(KeyboardHeightPreset.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
            }

            Section {
                Toggle("四码唯一自动上屏", isOn: $appState.settings.wubiAutoCommitUnique4)
                Toggle("显示剩余编码与 z 拼音反查码", isOn: $appState.settings.wubiShowCodeHints)
            } header: {
                Text("五笔 86 专属设置")
            } footer: {
                Text("内置 9.3 万标准五笔 86 码表（固定序不调频），支持第 5 码顶字上屏、空码重敲清空，以及按 z 临时拼音并实时反查五笔编码（如 znihao）。")
            }
        }
        .navigationTitle("输入方案与布局")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 键盘手感

private struct KeyboardFeelSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("反馈") {
                Picker("震动反馈", selection: $appState.settings.hapticStrength) {
                    ForEach(HapticStrength.allCases) { h in
                        Text(h.displayName).tag(h)
                    }
                }
                Toggle("按键音效", isOn: $appState.settings.keySoundEnabled)
                Toggle("按键放大气泡", isOn: $appState.settings.keyPopupEnabled)
            }

            Section("键盘外观与布局") {
                Toggle("显示顶部副字符（1-0 / 符号 / 双拼助记）", isOn: $appState.settings.showSecondaryHints)
                Toggle("显示独立顶部数字行 (1-0 五行布局)", isOn: $appState.settings.showNumberRow)
                Toggle("显示底部下划标点提示", isOn: $appState.settings.showDownwardHints)
            }

            Section("手势与滑行") {
                Toggle("26键滑行输入 (Glide Typing 中英轨迹成词)", isOn: $appState.settings.glideTypingEnabled)
                Toggle("动态下一键热区防误触 (Apple 级键缝吸附)", isOn: $appState.settings.dynamicKeyHitBoxEnabled)
                Toggle("上滑直接输入副字符", isOn: $appState.settings.swipeUpForHint)
                Toggle("下划按键快速输入标点", isOn: $appState.settings.swipeDownForPunctuation)
                Toggle("空格键触控板移光标", isOn: $appState.settings.spacebarTrackpadEnabled)
            }

            Section {
                Toggle("宿主输入框内嵌拼音预览", isOn: $appState.settings.inlineComposingEnabled)
            } footer: {
                Text("开启后拼音组合直接显示在宿主 App 输入框内（marked text），关闭则只在键盘候选栏显示。")
            }
        }
        .navigationTitle("键盘手感")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 智能输入

private struct SmartInputSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("纠错与转换") {
                Toggle("输出繁体中文（OpenCC 词组级简繁切换）", isOn: $appState.settings.traditionalChineseEnabled)
                Toggle("智能拼写纠错（4 路容错 + 鼻音/换位）", isOn: $appState.settings.typoCorrectionEnabled)
                Toggle("模糊音未开时智能兜底（yingai→应该 / zidao→知道）", isOn: $appState.settings.fuzzyFallbackEnabled)
                Toggle("中文与英文之间自动加空格", isOn: $appState.settings.panguSpaceLetters)
                Toggle("中文与数字之间自动加空格", isOn: $appState.settings.panguSpaceDigits)
            }

            Section("学习与联想") {
                Toggle("首位候选 Emoji 实时联想（全方案通用）", isOn: $appState.settings.emojiSuggestionEnabled)
                Toggle("自造词学习与词频记忆（30天半衰期）", isOn: $appState.settings.userLearningEnabled)
                if appState.settings.userLearningEnabled {
                    Stepper(
                        "自动学习阈值：\(appState.settings.autoLearnThreshold) 次生效",
                        value: $appState.settings.autoLearnThreshold,
                        in: 1...5
                    )
                }
                Toggle("上下文二元消歧与下一词预测", isOn: $appState.settings.bigramPredictionEnabled)
                Toggle("中英混输与英文词库直出排位", isOn: $appState.settings.smartEnglishCandidate)
            }

            Section("标点与英文") {
                Toggle("自动配对括号", isOn: $appState.settings.autoPairPunctuation)
                Toggle("中文弯引号自动交替配对（“” / ‘’）", isOn: $appState.settings.smartQuotePairing)
                Toggle("双击空格输入句号", isOn: $appState.settings.doubleSpacePeriod)
                Toggle("英文句首自动大写", isOn: $appState.settings.autoCapitalizeEnglish)
            }

            Section("剪贴板") {
                Toggle("顶部剪贴板快速粘贴胶囊", isOn: $appState.settings.clipboardBannerEnabled)
                Toggle("智能提取短信验证码", isOn: $appState.settings.smartOTPExtraction)
                Toggle("自动读取剪贴板预览（需允许系统授权）", isOn: $appState.settings.autoReadClipboardPreview)
            }
            Section {
                NavigationLink {
                    TypingStatsView()
                } label: {
                    HStack {
                        Text("打字统计")
                        Spacer()
                        Text("总览 · 趋势")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }
            } header: {
                Text("打字统计（借鉴 WowType）")
            } footer: {
                Text("仅在本机按天记录字数与活跃打字时长，不记录任何输入内容；密码、邮箱、网址输入框自动跳过统计。")
            }
        }
        .navigationTitle("智能输入")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 模糊音

private struct FuzzyPinyinSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("模糊音设置（16 组全覆盖）") {
                Toggle("zh ↔ z", isOn: $appState.settings.fuzzy.zhZ)
                Toggle("ch ↔ c", isOn: $appState.settings.fuzzy.chC)
                Toggle("sh ↔ s", isOn: $appState.settings.fuzzy.shS)
                Toggle("n ↔ l", isOn: $appState.settings.fuzzy.nl)
                Toggle("r ↔ l", isOn: $appState.settings.fuzzy.rl)
                Toggle("f ↔ h", isOn: $appState.settings.fuzzy.fh)
                Toggle("huang ↔ wang", isOn: $appState.settings.fuzzy.huangWang)
                Toggle("an ↔ ang", isOn: $appState.settings.fuzzy.anAng)
                Toggle("en ↔ eng", isOn: $appState.settings.fuzzy.enEng)
                Toggle("in ↔ ing", isOn: $appState.settings.fuzzy.inIng)
                Toggle("ian ↔ iang", isOn: $appState.settings.fuzzy.ianIang)
                Toggle("uan ↔ uang", isOn: $appState.settings.fuzzy.uanUang)
                Toggle("un ↔ ong", isOn: $appState.settings.fuzzy.unOng)
                Toggle("an ↔ ai", isOn: $appState.settings.fuzzy.anAi)
                Toggle("un ↔ iong", isOn: $appState.settings.fuzzy.unIong)
                Toggle("eng ↔ ong", isOn: $appState.settings.fuzzy.engOng)
            }
        }
        .navigationTitle("模糊音")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 趣味字体

private struct StylishFontSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("趣味英文花样字体") {
                Picker("当前英文字体", selection: $appState.settings.stylishFontID) {
                    ForEach(StylishFontStyle.allCases) { style in
                        Text("\(style.displayName)  \(style.previewSample)").tag(style.rawValue)
                    }
                }
            }
        }
        .navigationTitle("趣味字体")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 词库管理

private struct LexiconSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var showClearConfirm = false
    @State private var newCustomCode = ""
    @State private var newCustomWord = ""
    @State private var showTSVSheet = false
    @State private var tsvDraft = ""
    @State private var customStatusMessage: String?
    @State private var showUserLexiconTSVSheet = false
    @State private var userLexiconDraft = ""
    @State private var userLexiconStatusMessage: String?
    @State private var subscribedPacks: Set<String> = CommunityLexiconService.shared.subscribedPackIDs()

    private var filteredWords: [UserWordEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return appState.userWords }
        return appState.userWords.filter {
            $0.word.lowercased().contains(q) || $0.py.lowercased().contains(q) || $0.abbr.lowercased().contains(q)
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    TextField("编码 (如 mail)", text: $newCustomCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(maxWidth: 110)
                    Divider()
                    TextField("短语内容（可用 \\n 换行）", text: $newCustomWord)
                    Button("添加") {
                        appState.addCustomWord(code: newCustomCode, word: newCustomWord)
                        customStatusMessage = "已添加自定义短语「\(newCustomCode.lowercased())」"
                        newCustomCode = ""
                        newCustomWord = ""
                    }
                    .disabled(newCustomCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              newCustomWord.isEmpty)
                }

                ForEach(appState.customWords) { entry in
                    HStack(spacing: 10) {
                        Text(entry.compactCode)
                            .font(.caption.monospaced().bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(Design.Palette.ink).opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(entry.word)
                            .font(.body)
                            .lineLimit(2)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            appState.deleteCustomWord(id: entry.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }

                HStack {
                    Button("导入 TSV (WowType)") {
                        tsvDraft = appState.exportCustomWordsTSV()
                        showTSVSheet = true
                    }
                    Spacer()
                    Button("复制导出 TSV") {
                        UIPasteboard.general.string = appState.exportCustomWordsTSV()
                        customStatusMessage = "已复制 \(appState.customWords.count) 条 TSV 短语到剪贴板"
                    }
                }
                .font(.subheadline)

                if let status = customStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("自定义短语 / 快捷编码 (\(appState.customWords.count))")
            } footer: {
                Text("兼容 WowType custom.tsv（编码<TAB>词，可用 \\n 换行）。输入对应字母编码时优先级最高，排在候选栏第 1 位。")
            }

            Section {
                ForEach(CommunityLexiconService.shared.allAvailablePacks()) { pack in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(pack.name)
                                    .font(.subheadline.bold())
                                Text(pack.category)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(Design.Palette.surface))
                                    .clipShape(Capsule())
                            }
                            Text(pack.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            let added = CommunityLexiconService.shared.subscribe(pack: pack)
                            subscribedPacks = CommunityLexiconService.shared.subscribedPackIDs()
                            appState.refreshAll()
                            customStatusMessage = "已订阅「\(pack.name)」并导入/更新 \(added) 条专业词条"
                        } label: {
                            Text(subscribedPacks.contains(pack.id) ? "已订阅 · 更新" : "一键订阅")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(subscribedPacks.contains(pack.id) ? Color(Design.Palette.surface) : Color(Design.Palette.ink))
                                .foregroundStyle(subscribedPacks.contains(pack.id) ? Color(Design.Palette.ink) : Color(Design.Palette.canvas))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("开源词库社区订阅 (M4 · 对标 HeliBoard & WowType)")
            } footer: {
                Text("订阅开源社区托管的 TSV 专题词库包，App 内一键导入并随云同步自动分发到各端。")
            }

            Section {
                HStack {
                    Button("导入个人词库 (user.tsv)") {
                        userLexiconDraft = appState.exportUserLexiconTSV()
                        showUserLexiconTSVSheet = true
                    }
                    Spacer()
                    Button("复制导出 user.tsv") {
                        UIPasteboard.general.string = appState.exportUserLexiconTSV()
                        userLexiconStatusMessage = "已复制 \(appState.userWords.count) 条个人词库到剪贴板"
                    }
                }
                .font(.subheadline)

                if let status = userLexiconStatusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if appState.userWords.isEmpty {
                    Text("暂无已学习的个人词条。平时打字选词或分段造词后会自动记忆在这里；若选错词立即按 ⌫ 退格，还会自动撤销误学记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("搜索自造词或拼音…", text: $searchText)
                    ForEach(filteredWords) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    if entry.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                    Text(entry.word).font(.body.bold())
                                }
                                Text(entry.py)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(entry.freq)次")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                appState.togglePinUserWord(entry)
                            } label: {
                                Label(entry.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                appState.forgetUserWord(entry)
                            } label: {
                                Label("遗忘", systemImage: "trash")
                            }
                        }
                    }
                    Button("清空全部个人词库", role: .destructive) {
                        showClearConfirm = true
                    }
                }
            } header: {
                Text("个人自造词与调频词库 (\(appState.userWords.count))")
            }
        }
        .navigationTitle("词库管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTSVSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text("每行一条：编码<TAB>短语（或逗号分隔），支持 \\n 换行")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $tsvDraft)
                        .font(.body.monospaced())
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding()
                .navigationTitle("导入 TSV 短语码表")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showTSVSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入") {
                            let count = appState.importCustomWordsTSV(tsvDraft)
                            customStatusMessage = "成功导入 \(count) 条短语"
                            showTSVSheet = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showUserLexiconTSVSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text("每行一条：拼音<TAB>词条[<TAB>频次[<TAB>置顶]]（拼音可用空格或撇号分隔）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $userLexiconDraft)
                        .font(.body.monospaced())
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding()
                .navigationTitle("导入个人词库 (user.tsv)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showUserLexiconTSVSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入") {
                            let count = appState.importUserLexiconTSV(userLexiconDraft)
                            userLexiconStatusMessage = "成功导入 \(count) 条个人词条"
                            showUserLexiconTSVSheet = false
                        }
                    }
                }
            }
        }
        .alert("确定清空个人词库吗？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                appState.clearUserLexicon()
            }
        } message: {
            Text("这不会影响内置的 39.6 万雾凇现代词库与 9.3 万五笔 86 码表，仅删除您平时积累的自造词和上下文联想记录。")
        }
    }
}
