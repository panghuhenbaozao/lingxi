import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 设置中心：分类入口首页 + 各分类二级页。
/// 原「词库与设置」单页 40+ 项设置扁平堆叠、词库管理被淹没，
/// 重构为 6 个分类入口，每类一屏，词库管理独立成页。
struct DictionarySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("lastBackupExportAt") private var lastBackupExportAt: Double = 0
    @State private var showAppleSignInSheet = false
    /// 引擎健康分与地域上下文：诊断与位置读取需要访问词库/磁盘，只在进入页面时刷新，避免每次刷新界面都重复读盘
    @State private var cachedHealthScore: Int?
    @State private var cachedGeo = GeoLocationContext()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if appState.isCloudAuthenticated {
                        NavigationLink {
                            CloudAccountView()
                        } label: {
                            appleAccountHeaderRow(
                                title: appState.cloudConfig.username.isEmpty ? "灵犀账号" : appState.cloudConfig.username,
                                subtitle: appState.cloudConfig.email.isEmpty ? "云端同步已连接" : appState.cloudConfig.email,
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
                                    subtitle: "同步个人词库、外观与设置",
                                    isSignedIn: false
                                )
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(Design.Palette.muted))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("输入") {
                    settingsLink(icon: "sparkles", tint: Design.Palette.accent, title: "AI 自动托管",
                                 value: appState.settings.aiAutopilotMode.shortBadge) {
                        AIAutopilotHubView()
                    }
                    settingsLink(icon: "keyboard", tint: Design.Palette.ink, title: "输入方案与布局",
                                 value: "\(appState.settings.inputScheme.shortBadge) · \(appState.settings.layoutMode.displayName)") {
                        SchemeLayoutSettingsView()
                    }
                    settingsLink(icon: "hand.tap", tint: Design.Palette.ink, title: "手感与划动",
                                 value: appState.settings.hapticStrength.displayName) {
                        KeyboardFeelSettingsView()
                    }
                    settingsLink(icon: "rectangle.3.offgrid", tint: Design.Palette.ink, title: "工具栏与候选栏",
                                 value: "\(Int(appState.settings.candidateFontSize))pt") {
                        ToolbarSettingsView()
                    }
                }

                Section("纠错与词库") {
                    settingsLink(icon: "wand.and.stars", tint: Design.Palette.ink, title: "智能纠错与联想",
                                 value: appState.settings.typoCorrectionEnabled ? "已开启" : "已关闭") {
                        SmartInputSettingsView()
                    }
                    settingsLink(icon: "waveform", tint: Design.Palette.ink, title: "模糊音",
                                 value: appState.settings.fuzzy.enabledCount > 0 ? "\(appState.settings.fuzzy.enabledCount) 组" : "关闭") {
                        FuzzyPinyinSettingsView()
                    }
                    settingsLink(icon: "book.closed", tint: Design.Palette.ink, title: "词库与地标",
                                 value: "\(appState.userWords.count) 词") {
                        LexiconAndLocationHubView()
                    }
                }

                Section {
                    settingsLink(icon: "chart.bar", tint: Design.Palette.ink, title: "打字统计",
                                 value: "今日 \(appState.typingStatsSummary.todayChars) 字") {
                        TypingStatsView()
                    }
                    settingsLink(icon: "icloud.and.arrow.up", tint: Design.Palette.ink, title: "同步与备份",
                                 value: appState.isCloudAuthenticated ? "云端" : "本地") {
                        DataSyncAndBackupHubView()
                    }
                    settingsLink(icon: "lock.shield", tint: Design.Palette.ink, title: "本地加密保险箱",
                                 value: appState.secureVaultItems.isEmpty ? "空" : "\(appState.secureVaultItems.count) 条") {
                        SecureVaultSubView()
                    }
                    settingsLink(icon: "stethoscope", tint: Design.Palette.ink, title: "指南与诊断",
                                 value: AppGroup.isAvailable ? "正常" : "侧载") {
                        UsageGuideAndDiagnosticsView()
                    }
                } header: {
                    Text("数据与隐私")
                } footer: {
                    Text("灵犀输入法 \(appVersionText) · 本地优先 · 隐私隔离")
                        .font(.caption2)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .task {
                cachedHealthScore = EngineHealthAndSustainabilityService.shared.diagnose().healthScore
                cachedGeo = GeoLocationContext.load()
            }
            .onAppear {
                cachedGeo = GeoLocationContext.load()
            }
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSignedIn ? Color(Design.Palette.ink) : Color(Design.Palette.accent))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "--"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "v\(version)" : "v\(version) (\(build))"
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

    private var lexiconAndLocationSubtitle: String {
        let geoPart = cachedGeo.isPopulated ? "\(cachedGeo.shortCityName)(\(cachedGeo.pois.count)地标)" : "6,403地名内置"
        return "词库 \(appState.userWords.count) · 短语 \(appState.customWords.count) · \(geoPart)"
    }

    private var syncAndBackupSubtitle: String {
        let mode = appState.isCloudAuthenticated ? "云端在线" : "本地备份"
        let healthPart = cachedHealthScore.map { " · 健康 \($0) 分" } ?? ""
        return "\(mode)\(healthPart) · \(backupSubtitle)"
    }

    private var backupSubtitle: String {
        guard lastBackupExportAt > 0 else { return "从未备份" }
        return "上次备份 " + Date(timeIntervalSince1970: lastBackupExportAt).formatted(.relative(presentation: .named))
    }

    private func settingsLink<Destination: View>(icon: String, tint: UIColor, title: String, value: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                LXIconTile(icon: icon, tint: Color(tint), size: 30)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .lineLimit(1)
            }
            .padding(.vertical, 3)
        }
    }
}

// MARK: - 输入方案与布局

private struct SchemeLayoutSettingsView: View {
    @EnvironmentObject private var appState: AppState

    private var isWubi: Bool {
        appState.settings.inputScheme == .wubi86
    }

    var body: some View {
        Form {
            Section {
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
            } header: {
                Text("方案")
            } footer: {
                Text("支持全拼、7 种双拼、五笔 86；双拼会在键帽上显示对应助记。")
            }

            Section("布局") {
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
                LXToggleRow("四码唯一自动上屏", subtitle: "打满 4 码且只有一个候选时直接上屏", isOn: $appState.settings.wubiAutoCommitUnique4)
                LXToggleRow("显示剩余编码提示", subtitle: "候选旁显示还差的编码，按 z 可临时用拼音反查", isOn: $appState.settings.wubiShowCodeHints)
            } header: {
                Text("五笔 86")
            } footer: {
                Text(isWubi
                     ? "内置 9.3 万条标准五笔 86 码表，固定词序不调频；第 5 码顶字上屏，空码重敲自动清空。"
                     : "把输入方案切换为「五笔86」后可调整。")
            }
            .disabled(!isWubi)
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
                LXToggleRow("按键音效", isOn: $appState.settings.keySoundEnabled)
                LXToggleRow("按键放大气泡", subtitle: "按下时在手指上方显示放大的字母", isOn: $appState.settings.keyPopupEnabled)
            }

            Section("键帽显示") {
                LXToggleRow("顶部副字符", subtitle: "键帽角标显示数字、符号或双拼助记", isOn: $appState.settings.showSecondaryHints)
                LXToggleRow("独立数字行", subtitle: "键盘最上方多一行 1–0", isOn: $appState.settings.showNumberRow)
                LXToggleRow("底部标点提示", subtitle: "键帽下方显示下划可输入的标点", isOn: $appState.settings.showDownwardHints)
            }

            Section {
                LXToggleRow("滑行输入", subtitle: "手指在 26 键上连续滑过即可打出中英文词", isOn: $appState.settings.glideTypingEnabled)
                LXToggleRow("智能防误触", subtitle: "根据下一个可能的字母动态放大按键热区", isOn: $appState.settings.dynamicKeyHitBoxEnabled)
                LXToggleRow("上滑输入副字符", isOn: $appState.settings.swipeUpForHint)
                LXToggleRow("下划输入标点", isOn: $appState.settings.swipeDownForPunctuation)
                LXToggleRow("空格键移动光标", subtitle: "按住空格左右拖动，像触控板一样移光标", isOn: $appState.settings.spacebarTrackpadEnabled)
                NavigationLink {
                    CustomSwipeKeymapEditorView()
                } label: {
                    let cnt = appState.settings.customSwipeUpMap.count + appState.settings.customSwipeDownMap.count
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自定义上下滑映射")
                            Text("给任意按键设置上滑、下划时输出的内容")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                        Spacer(minLength: 6)
                        LXTag(
                            text: cnt > 0 ? "已改 \(cnt) 键" : "默认",
                            tint: cnt > 0 ? Color(Design.Palette.accent) : Color(Design.Palette.slate),
                            filled: cnt > 0
                        )
                    }
                }
            } header: {
                Text("手势与滑行")
            }

            Section {
                LXToggleRow("在输入框内显示拼音", isOn: $appState.settings.inlineComposingEnabled)
            } footer: {
                Text("开启后，打字中的拼音直接显示在当前 App 的输入框里；关闭则只在键盘候选栏显示。")
            }
        }
        .navigationTitle("键盘手感与手势")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - L2 合并子页：词库与实时地标（零重复入口）

private struct LexiconAndLocationHubView: View {
    @EnvironmentObject private var appState: AppState
    @State private var cachedGeo = GeoLocationContext()

    var body: some View {
        List {
            Section {
                NavigationLink {
                    LexiconSettingsView()
                } label: {
                    LXNavRow(
                        icon: "book.closed",
                        title: "词库管理与社区词包",
                        subtitle: "自学习词 \(appState.userWords.count) 个 · 自定义短语 \(appState.customWords.count) 条"
                    )
                }
            } header: {
                Text("词库")
            } footer: {
                Text("搜索、删除自学习的词，导入导出 TSV，订阅社区词包。")
            }

            Section {
                NavigationLink {
                    LocationLexiconView()
                } label: {
                    LXNavRow(
                        icon: "location.fill",
                        title: "实时城市与周边地标",
                        subtitle: cachedGeo.isPopulated
                            ? "\(cachedGeo.compactLocationLabel) · 已学会 \(cachedGeo.pois.count) 个周边地名"
                            : "已内置全国 6,403 个省市区县",
                        badge: cachedGeo.isPopulated ? "已定位" : nil
                    )
                }
            } header: {
                Text("地名")
            } footer: {
                Text("开启定位后自动学习附近 5 公里的路名、商圈和车站，位置数据只保存在本机。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("词库与实时地标")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            cachedGeo = GeoLocationContext.load()
        }
    }
}

// MARK: - L2 合并子页：云同步、局域网与加密备份

private struct DataSyncAndBackupHubView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("lastBackupExportAt") private var lastBackupExportAt: Double = 0

    private var backupBadge: String {
        guard lastBackupExportAt > 0 else { return "从未备份" }
        return Date(timeIntervalSince1970: lastBackupExportAt).formatted(.relative(presentation: .named))
    }

    @State private var healthScore: Int?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    CloudAccountView()
                } label: {
                    LXNavRow(
                        icon: appState.isCloudAuthenticated ? "icloud.fill" : "icloud",
                        title: "灵犀云端账号",
                        subtitle: appState.isCloudAuthenticated ? "已登录 · 端到端加密同步" : "未登录 · 国内直连，无需代理",
                        badge: appState.isCloudAuthenticated ? "在线" : nil,
                        tint: appState.isCloudAuthenticated ? Color(Design.Palette.success) : Color(Design.Palette.accent)
                    )
                }

                NavigationLink {
                    SustainabilityHubView()
                } label: {
                    LXNavRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "同步方式与词库维护",
                        subtitle: "本机 / 局域网 / 云端三种方式 · 词库清理",
                        badge: healthScore.map { "健康 \($0)" }
                    )
                }
            } header: {
                Text("云端与跨设备")
            }

            Section {
                NavigationLink {
                    BackupSettingsView()
                } label: {
                    LXNavRow(
                        icon: "lock.doc",
                        title: "加密备份与恢复",
                        subtitle: "用密码把词库、短语、主题打包成一个文件",
                        badge: backupBadge,
                        tint: lastBackupExportAt > 0 ? Color(Design.Palette.accent) : Color(Design.Palette.warning)
                    )
                }
            } header: {
                Text("本地备份")
            } footer: {
                Text("备份文件经 AES-GCM 加密，只存在你选择的位置，不经过任何服务器。")
            }
        }
        .listStyle(.insetGrouped)
        .task {
            healthScore = EngineHealthAndSustainabilityService.shared.diagnose().healthScore
        }
        .navigationTitle("云同步与加密备份")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - L2 子页：使用指南与 App↔键盘共享诊断（收纳原首页 8 条进阶玩法 + 侧载诊断）

private struct UsageGuideAndDiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var bridgeStatus: String?
    @State private var isSyncingBridge = false
    @State private var showOnboarding = false
    @State private var showDetails = false

    private struct Tip: Identifiable {
        let icon: String
        let title: String
        let desc: String
        var id: String { title }
    }

    private let tips: [Tip] = [
        Tip(icon: "bolt.circle.fill", title: "随打随问 AI", desc: "直接输入「@ai 帮我委婉拒绝加班」，顶栏出现一键直达，不用切出键盘。"),
        Tip(icon: "location.fill", title: "全国地名 + 周边地标", desc: "全国省市区县开箱即用，开启定位自动学习附近路名商圈；打 vwz / vdz 一键发当前位置。"),
        Tip(icon: "sparkles", title: "选中即改 · 续写 · 军师", desc: "选中一段文字自动浮现润色和翻译；复制棘手消息点「博弈军师」出 3 套高情商回复。"),
        Tip(icon: "character.textbox", title: "长句回改与声调筛字", desc: "打长句时点顶栏任意音节原地换字；展开候选切「只看单字」可按声调找生僻字。"),
        Tip(icon: "textformat.123", title: "中数英混输", desc: "连打 mingtian3dianjian 出「明天3点见」，fayigepdfgeiwo 出「发一个PDF给我」。"),
        Tip(icon: "arrow.up.and.down.and.arrow.left.and.right", title: "编辑台与自定义滑行", desc: "键盘快捷设置里打开「编辑台」可精准移光标；「键盘手感与手势」里可自定义任意键的上下滑。"),
        Tip(icon: "function", title: "v 模式：大写金额与 AA", desc: "输入 v12800rmb 出「壹万贰仟捌佰元整」，输入 v1280/4 自动出「人均 ¥320」。"),
        Tip(icon: "lock.shield.fill", title: "Face ID 本地保险箱", desc: "身份证、银行卡、税号只存在本机受保护容器，不上云，也不进剪贴板历史。"),
    ]

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    LXIconTile(
                        icon: AppGroup.isAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        tint: AppGroup.isAvailable ? Color(Design.Palette.success) : Color(Design.Palette.warning),
                        size: 42
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppGroup.isAvailable ? "App 与键盘已打通" : "App 与键盘处于隔离状态")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text(AppGroup.isAvailable
                             ? "设置、外观和词库会自动同步给键盘"
                             : "免费侧载时系统会禁用共享目录，需要手动同步")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)

                LabeledContent("键盘启用状态") {
                    LXTag(
                        text: appState.isKeyboardEnabled ? "已启用" : "未启用",
                        tint: appState.isKeyboardEnabled ? Color(Design.Palette.success) : Color(Design.Palette.warning),
                        filled: true
                    )
                }

                if !AppGroup.isAvailable {
                    Button {
                        Task {
                            isSyncingBridge = true
                            defer { isSyncingBridge = false }
                            let res = await appState.copySideloadBridgeTokenAndSync()
                            bridgeStatus = res.message.hasPrefix("✓")
                                ? String(res.message.dropFirst()).trimmingCharacters(in: .whitespaces)
                                : res.message
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isSyncingBridge {
                                ProgressView().controlSize(.small).tint(Color.white)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(isSyncingBridge ? "正在同步…" : "复制云桥接凭证给键盘")
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(isSyncingBridge)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                DisclosureGroup("技术详情", isExpanded: $showDetails) {
                    LabeledContent("App Group", value: AppGroup.isAvailable ? "已打通" : "沙盒隔离")
                    LabeledContent("解析标识") {
                        Text(AppGroup.identifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color(Design.Palette.stone))
                            .textSelection(.enabled)
                    }
                    LabeledContent("匹配来源", value: AppGroup.resolutionSource)
                }
                .font(.subheadline)

                Button {
                    showOnboarding = true
                } label: {
                    Label("查看启用与完全访问教程", systemImage: "book")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.accent))
                        .frame(minHeight: 36)
                }
            } header: {
                Text("共享状态诊断")
            } footer: {
                if !AppGroup.isAvailable {
                    Text("复制凭证后切到灵犀键盘（需开启「允许完全访问」）即可自动认领，之后外观和打字统计会通过你的国内云端双向同步。")
                }
            }

            Section {
                ForEach(tips) { tip in
                    HStack(alignment: .top, spacing: 12) {
                        LXIconTile(icon: tip.icon)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tip.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text(tip.desc)
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("进阶玩法 · \(tips.count) 条")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("指南与共享诊断")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($bridgeStatus)
        .sheet(isPresented: $showOnboarding) {
            OnboardingGuideView()
        }
    }
}

// MARK: - 智能输入

private struct SmartInputSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("纠错与转换") {
                LXToggleRow("智能拼写纠错", subtitle: "打错、漏打、前后颠倒也能出正确的词", isOn: $appState.settings.typoCorrectionEnabled)
                LXToggleRow("模糊音智能兜底", subtitle: "没开模糊音时也能认出 yingai→应该、zidao→知道", isOn: $appState.settings.fuzzyFallbackEnabled)
                LXToggleRow("输出繁体中文", subtitle: "OpenCC 词级转换，自动区分一简多繁与两岸惯用词", isOn: $appState.settings.traditionalChineseEnabled)
                if appState.settings.traditionalChineseEnabled {
                    Picker("繁体标准", selection: $appState.settings.traditionalVariant) {
                        ForEach(TraditionalChineseVariant.allCases) { v in
                            Text(v.displayName).tag(v)
                        }
                    }
                    .font(.subheadline)
                    let sample = ChineseScriptConverter.toTraditional("软件、内存、鼠标、服务器、以后、头发", variant: appState.settings.traditionalVariant)
                    Text("示例：\(sample)")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                }
            }

            Section {
                LXToggleRow("中文与英文间加空格", isOn: $appState.settings.panguSpaceLetters)
                LXToggleRow("中文与数字间加空格", isOn: $appState.settings.panguSpaceDigits)
            } header: {
                Text("排版")
            } footer: {
                Text("例如「用 iPhone 拍了 3 张」。密码、邮箱、网址输入框会自动跳过。")
            }

            Section("学习与联想") {
                LXToggleRow("隐身无痕模式", subtitle: "开启后暂停词库自学习、剪贴板历史、打字统计与 AI 历史留痕", isOn: $appState.settings.incognitoModeEnabled)
                LXToggleRow("草稿防丢黑匣子", subtitle: "纯本机 24 小时滚动保存 ≥18 字长草稿，防 App 刷新闪退清空（永不上云）", isOn: $appState.settings.draftRecoveryEnabled)
                LXToggleRow("验证码 15 分钟阅后即焚", subtitle: "自动清理超 15 分钟的未置顶验证码，保持剪贴板历史清爽", isOn: $appState.settings.autoExpireOTPEnabled)
                LXToggleRow("学习我的用词", subtitle: "常用的词自动排到前面，久不用会慢慢回落", isOn: $appState.settings.userLearningEnabled)
                if appState.settings.userLearningEnabled {
                    Stepper(value: $appState.settings.autoLearnThreshold, in: 1...5) {
                        HStack {
                            Text("选几次后记住")
                            Spacer()
                            Text("\(appState.settings.autoLearnThreshold) 次")
                                .monospacedDigit()
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                    }
                }
                LXToggleRow("根据上文联想下一个词", isOn: $appState.settings.bigramPredictionEnabled)
                LXToggleRow("英文单词直出", subtitle: "github→GitHub、wechat→WeChat 直接排第一", isOn: $appState.settings.smartEnglishCandidate)
                LXToggleRow("Emoji 联想", subtitle: "打「开心」时候选里出现 😊", isOn: $appState.settings.emojiSuggestionEnabled)
            }

            Section {
                LXToggleRow(
                    "长辈 / 护眼大字关怀模式",
                    subtitle: "一键放大候选字号至 22pt、增高键盘与顶栏并加强震动，关闭时自动还原原设置",
                    isOn: Binding(
                        get: { appState.settings.elderCareModeEnabled },
                        set: { appState.settings.setElderCareMode($0) }
                    )
                )
                LXToggleRow(
                    "选词轻声语音播报",
                    subtitle: "点选候选词时轻声朗读核对，帮长辈防打错同音字",
                    isOn: $appState.settings.speakSelectedCandidateEnabled
                )
            } header: {
                Text("长辈关怀与无障碍")
            }

            Section("标点与英文") {
                LXToggleRow("自动配对括号", isOn: $appState.settings.autoPairPunctuation)
                LXToggleRow("中文引号自动配对", subtitle: "“” 与 ‘’ 自动交替", isOn: $appState.settings.smartQuotePairing)
                LXToggleRow("双击空格输入句号", isOn: $appState.settings.doubleSpacePeriod)
                LXToggleRow("英文句首自动大写", isOn: $appState.settings.autoCapitalizeEnglish)
            }

            Section {
                LXToggleRow("顶栏剪贴板快捷粘贴", subtitle: "复制内容后键盘顶栏出现一键粘贴", isOn: $appState.settings.clipboardBannerEnabled)
                LXToggleRow("自动识别短信验证码", isOn: $appState.settings.smartOTPExtraction)
                LXToggleRow("自动读取剪贴板预览", subtitle: "需要在系统弹窗里允许粘贴", isOn: $appState.settings.autoReadClipboardPreview)
            } header: {
                Text("剪贴板")
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
            } footer: {
                Text("只在本机按天记录字数和打字时长，不记录任何输入内容；密码、邮箱、网址输入框自动跳过。")
            }
        }
        .navigationTitle("智能输入")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 模糊音

private struct FuzzyPinyinSettingsView: View {
    @EnvironmentObject private var appState: AppState

    private struct FuzzyItem: Identifiable {
        let pair: String
        let example: String
        let keyPath: WritableKeyPath<FuzzyPinyinOptions, Bool>
        var id: String { pair }
    }

    private let initials: [FuzzyItem] = [
        FuzzyItem(pair: "zh ↔ z", example: "知道 / 自道", keyPath: \.zhZ),
        FuzzyItem(pair: "ch ↔ c", example: "吃饭 / 词饭", keyPath: \.chC),
        FuzzyItem(pair: "sh ↔ s", example: "是 / 四", keyPath: \.shS),
        FuzzyItem(pair: "n ↔ l", example: "奶奶 / 来来", keyPath: \.nl),
        FuzzyItem(pair: "r ↔ l", example: "热 / 乐", keyPath: \.rl),
        FuzzyItem(pair: "f ↔ h", example: "福 / 胡", keyPath: \.fh),
        FuzzyItem(pair: "huang ↔ wang", example: "黄 / 王", keyPath: \.huangWang),
    ]

    private let finals: [FuzzyItem] = [
        FuzzyItem(pair: "an ↔ ang", example: "安 / 昂", keyPath: \.anAng),
        FuzzyItem(pair: "en ↔ eng", example: "根 / 耕", keyPath: \.enEng),
        FuzzyItem(pair: "in ↔ ing", example: "因 / 英", keyPath: \.inIng),
        FuzzyItem(pair: "ian ↔ iang", example: "先 / 香", keyPath: \.ianIang),
        FuzzyItem(pair: "uan ↔ uang", example: "关 / 光", keyPath: \.uanUang),
        FuzzyItem(pair: "un ↔ ong", example: "吨 / 东", keyPath: \.unOng),
        FuzzyItem(pair: "an ↔ ai", example: "看 / 开", keyPath: \.anAi),
        FuzzyItem(pair: "un ↔ iong", example: "军 / 窘", keyPath: \.unIong),
        FuzzyItem(pair: "eng ↔ ong", example: "等 / 懂", keyPath: \.engOng),
    ]

    private func enabledCount(_ items: [FuzzyItem]) -> Int {
        items.filter { appState.settings.fuzzy[keyPath: $0.keyPath] }.count
    }

    private func setAll(_ items: [FuzzyItem], to value: Bool) {
        for item in items {
            appState.settings.fuzzy[keyPath: item.keyPath] = value
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    LXIconTile(icon: "waveform", size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.settings.fuzzy.enabledCount > 0
                             ? "已开启 \(appState.settings.fuzzy.enabledCount) / 16 组"
                             : "未开启模糊音")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("平翘舌、前后鼻音分不清时打开对应项，开得越多候选越杂。")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("不确定开哪些？在「AI 智脑 → 智能画像诊断」里可以根据你的打字习惯一键推荐。")
            }

            fuzzySection(title: "声母", items: initials)
            fuzzySection(title: "韵母", items: finals)
        }
        .navigationTitle("模糊音")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fuzzySection(title: String, items: [FuzzyItem]) -> some View {
        let count = enabledCount(items)
        return Section {
            ForEach(items) { item in
                Toggle(isOn: Binding(
                    get: { appState.settings.fuzzy[keyPath: item.keyPath] },
                    set: { appState.settings.fuzzy[keyPath: item.keyPath] = $0 }
                )) {
                    HStack(spacing: 10) {
                        Text(item.pair)
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text(item.example)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }
                .tint(Color(Design.Palette.accent))
            }
        } header: {
            HStack {
                Text("\(title) · \(count)/\(items.count)")
                Spacer()
                Button(count == items.count ? "全部关闭" : "全部开启") {
                    setAll(items, to: count != items.count)
                }
                .font(.caption.bold())
                .textCase(nil)
            }
        }
    }
}

// MARK: - 趣味字体

private struct StylishFontSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                ForEach(StylishFontStyle.allCases) { style in
                    let selected = appState.settings.stylishFontID == style.rawValue
                    Button {
                        appState.settings.stylishFontID = style.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(style.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                Text(style.previewSample)
                                    .font(.body)
                                    .foregroundStyle(Color(Design.Palette.charcoal))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(selected ? Color(Design.Palette.accent) : Color(Design.Palette.hairline))
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            } header: {
                Text("英文花样字体")
            } footer: {
                Text("选好后，键盘里打出的英文字母会自动转换成对应字体，适合昵称、签名和朋友圈。")
            }
        }
        .navigationTitle("趣味字体")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 词库管理

/// 导入 / 导出用的纯文本文件（TSV）
private struct LexiconTextFile: FileDocument {
    static var readableContentTypes: [UTType] { [.tabSeparatedText, .plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct LexiconSettingsView: View {
    @EnvironmentObject private var appState: AppState

    private enum ImportTarget: String, Identifiable {
        case custom, user
        var id: String { rawValue }
        var title: String { self == .custom ? "导入自定义短语" : "导入个人词库" }
        var formatHint: String {
            self == .custom
                ? "每行一条：编码 + Tab + 短语，例如「mail<Tab>me@example.com」。也可以用逗号代替 Tab。短语里写 \\n 表示换行。"
                : "每行一条：拼音 + Tab + 词条，可选第 3 列频次、第 4 列置顶（1）。拼音用空格或撇号分隔，例如「ling xi<Tab>灵犀」。也可以用逗号代替 Tab。"
        }
        var example: String {
            self == .custom ? "mail,me@example.com\nzjtd,字节跳动" : "ling xi,灵犀\nshu ru fa,输入法"
        }
    }

    // 自定义短语
    @State private var newCustomCode = ""
    @State private var newCustomWord = ""
    /// 正在编辑的短语：保存时才替换旧条目，中途离开不会丢失
    @State private var editingEntryID: UUID?
    @FocusState private var focusedField: Field?
    private enum Field { case code, word }

    // 个人词库（本页自行读取更多条目：AppState 只缓存最近 250 条，搜索需要覆盖更多）
    @State private var words: [UserWordEntry] = []
    @State private var wordsLoaded = false
    @State private var searchText = ""
    @State private var showClearConfirm = false
    private static let wordLoadLimit = 2000

    // 社区词包（读文件：出现时加载）
    @State private var packs: [CommunityLexiconPack] = []
    @State private var subscribedPacks: Set<String> = []

    // 导入 / 导出
    @State private var importTarget: ImportTarget?
    @State private var importDraft = ""
    @State private var showFileImporter = false
    @State private var fileImportTarget: ImportTarget = .custom
    @State private var exportDocument: LexiconTextFile?
    @State private var exportFilename = ""
    @State private var showFileExporter = false

    @State private var toast: String?
    @State private var errorToast: String?

    private var filteredWords: [UserWordEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return words }
        let qCompact = q.replacingOccurrences(of: " ", with: "")
        return words.filter {
            $0.word.lowercased().contains(q)
                || $0.py.replacingOccurrences(of: "'", with: "").contains(qCompact)
                || $0.abbr.lowercased().contains(qCompact)
        }
    }

    private var wordCountLabel: String {
        words.count >= Self.wordLoadLimit ? "\(Self.wordLoadLimit)+" : "\(words.count)"
    }

    private var trimmedCode: String { newCustomCode.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedWord: String { newCustomWord.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var codeHint: String? {
        guard !trimmedCode.isEmpty, !LexiconTSVParser.isValidCode(trimmedCode) else { return nil }
        return "编码只能用英文字母，键盘里打这串字母时就会出现这条短语"
    }

    private var canAddCustom: Bool {
        LexiconTSVParser.isValidCode(trimmedCode) && !trimmedWord.isEmpty
    }

    var body: some View {
        Form {
            customPhraseSection
            personalLexiconSection
            communitySection
        }
        .navigationTitle("词库管理")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
        .lxToast($errorToast, isError: true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
        }
        .task {
            reloadWords()
            packs = CommunityLexiconService.shared.allAvailablePacks()
            subscribedPacks = CommunityLexiconService.shared.subscribedPackIDs()
        }
        .sheet(item: $importTarget) { target in
            importSheet(target)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.tabSeparatedText, .commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: exportDocument,
            contentType: .tabSeparatedText,
            defaultFilename: exportFilename
        ) { result in
            exportDocument = nil
            switch result {
            case .success:
                toast = "已导出为文件"
            case .failure(let error):
                let ns = error as NSError
                if !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) {
                    errorToast = "导出失败：\(error.localizedDescription)"
                }
            }
        }
        .alert("清空个人词库？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                appState.clearUserLexicon()
                reloadWords()
                toast = "已清空个人词库"
            }
        } message: {
            Text("会删除你平时积累的 \(wordCountLabel) 个自学习词和上下文联想记录，无法恢复，建议先导出。内置的 39.6 万词库和五笔码表不受影响。")
        }
    }

    // MARK: 自定义短语

    private var customPhraseSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                TextField("编码，如 mail", text: $newCustomCode)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .code)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .word }
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 40)
                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous))
                TextField("打出编码时要出现的内容", text: $newCustomWord, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .word)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous))
                if let codeHint {
                    Text(codeHint)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.error))
                }
                HStack(spacing: 8) {
                    Button {
                        addCustomPhrase()
                    } label: {
                        Label(editingEntryID == nil ? "添加" : "保存修改", systemImage: editingEntryID == nil ? "plus" : "checkmark")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(!canAddCustom)

                    if editingEntryID != nil {
                        Button("取消编辑") {
                            editingEntryID = nil
                            newCustomCode = ""
                            newCustomWord = ""
                            focusedField = nil
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                    }
                }
            }
            .padding(.vertical, 6)

            if appState.customWords.isEmpty {
                LXEmptyState(icon: "text.badge.plus", title: "还没有自定义短语", message: "比如把「mail」设成你的邮箱，键盘里打 mail 就能一键上屏。")
            } else {
                ForEach(appState.customWords) { entry in
                    customRow(entry)
                }
            }

            HStack(spacing: 8) {
                Button {
                    openImport(.custom)
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))

                Button {
                    startExport(text: appState.exportCustomWordsTSV(), name: "灵犀自定义短语")
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                .disabled(appState.customWords.isEmpty)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        } header: {
            Text("自定义短语 · \(appState.customWords.count)")
        } footer: {
            Text("在键盘里打出编码时，这条短语会排在候选第一位。兼容 WowType 的 custom.tsv。左滑删除，长按可编辑。")
        }
    }

    private func customRow(_ entry: CustomWordEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.compactCode)
                .font(.caption.monospaced().bold())
                .foregroundStyle(Color(Design.Palette.accent))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(Design.Palette.accentSoft), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(entry.word.replacingOccurrences(of: "\\n", with: " ↵ "))
                .font(.subheadline)
                .foregroundStyle(Color(Design.Palette.ink))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                appState.deleteCustomWord(id: entry.id)
                toast = "已删除「\(entry.compactCode)」"
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.expandedWord
                toast = "已复制短语"
            } label: {
                Label("复制短语", systemImage: "doc.on.doc")
            }
            Button {
                newCustomCode = entry.code
                newCustomWord = entry.word
                editingEntryID = entry.id
                focusedField = .word
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                if editingEntryID == entry.id { editingEntryID = nil }
                appState.deleteCustomWord(id: entry.id)
                toast = "已删除「\(entry.compactCode)」"
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func addCustomPhrase() {
        guard canAddCustom else { return }
        let code = trimmedCode
        let word = newCustomWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = code.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")
        let editing = editingEntryID
        let existed = editing == nil && appState.customWords.contains { $0.compactCode == compact && $0.word == word }
        if let editing {
            appState.deleteCustomWord(id: editing)
        }
        appState.addCustomWord(code: code, word: word)
        // 以「新条目确实存在」为准判断成功，而不是假定一定成功
        guard appState.customWords.contains(where: { $0.compactCode == compact && $0.word == word }) else {
            errorToast = "保存失败，请检查编码和内容"
            return
        }
        if editing != nil {
            toast = "已更新「\(compact)」"
        } else if existed {
            toast = "「\(compact)」已存在，已移到最前"
        } else {
            toast = "已添加「\(compact)」"
        }
        editingEntryID = nil
        newCustomCode = ""
        newCustomWord = ""
        focusedField = .code
    }

    // MARK: 个人词库

    private var personalLexiconSection: some View {
        Section {
            if !wordsLoaded {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if words.isEmpty {
                LXEmptyState(
                    icon: "book.closed",
                    title: "还没有学到新词",
                    message: "平时打字选词、组词后会自动记在这里；选错后马上按删除键，会自动撤销这次学习。"
                )
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color(Design.Palette.stone))
                    TextField("搜索词、拼音或首字母", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
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

                let results = filteredWords
                if results.isEmpty {
                    Text("没有找到「\(searchText)」")
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.stone))
                } else {
                    ForEach(results) { entry in
                        wordRow(entry)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    openImport(.user)
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))

                Button {
                    startExport(text: appState.exportUserLexiconTSV(), name: "灵犀个人词库")
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                .disabled(words.isEmpty)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            if !words.isEmpty {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Text("清空个人词库")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
            }
        } header: {
            Text("个人词库 · \(wordCountLabel)")
        } footer: {
            Text("右滑置顶（总排在候选最前），左滑遗忘。导出为 user.tsv 格式，可在其他设备导入。")
        }
    }

    private func wordRow(_ entry: UserWordEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color(Design.Palette.accent))
                            .accessibilityLabel("已置顶")
                    }
                    Text(entry.word)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                }
                Text(entry.py.replacingOccurrences(of: "'", with: " "))
                    .font(.caption.monospaced())
                    .foregroundStyle(Color(Design.Palette.stone))
            }
            Spacer(minLength: 6)
            Text("\(entry.freq) 次")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color(Design.Palette.stone))
        }
        .swipeActions(edge: .leading) {
            Button {
                appState.togglePinUserWord(entry)
                reloadWords()
                toast = entry.isPinned ? "已取消置顶「\(entry.word)」" : "已置顶「\(entry.word)」"
            } label: {
                Label(entry.isPinned ? "取消置顶" : "置顶", systemImage: entry.isPinned ? "pin.slash" : "pin")
            }
            .tint(Color(Design.Palette.accent))
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                appState.forgetUserWord(entry)
                reloadWords()
                toast = "已遗忘「\(entry.word)」"
            } label: {
                Label("遗忘", systemImage: "trash")
            }
        }
    }

    private func reloadWords() {
        words = appState.lexicon.allEntries(limit: Self.wordLoadLimit)
        wordsLoaded = true
    }

    // MARK: 社区词包

    private var communitySection: some View {
        Section {
            if packs.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                ForEach(packs) { pack in
                    let subscribed = subscribedPacks.contains(pack.id)
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(pack.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .lineLimit(1)
                                if subscribed {
                                    LXTag(text: "已订阅", icon: "checkmark", tint: Color(Design.Palette.success), filled: true)
                                }
                            }
                            Text(pack.description)
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                                .lineLimit(2)
                            LXFlowLayout(spacing: 6, lineSpacing: 4) {
                                LXTag(text: pack.category)
                                LXTag(text: "\(pack.wordCount) 个词")
                            }
                        }
                        Spacer(minLength: 6)
                        Button(subscribed ? "更新" : "订阅") {
                            let added = CommunityLexiconService.shared.subscribe(pack: pack)
                            subscribedPacks = CommunityLexiconService.shared.subscribedPackIDs()
                            appState.refreshAll()
                            reloadWords()
                            toast = subscribed ? "已更新「\(pack.name)」，\(added) 个词" : "已订阅「\(pack.name)」，导入 \(added) 个词"
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: !subscribed))
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("社区词包 · 已订阅 \(subscribedPacks.count)")
        } footer: {
            Text("开源社区整理的专业领域词包，订阅后词条会加入个人词库，并随云同步到其他设备。")
        }
    }

    // MARK: 导入 / 导出

    private func openImport(_ target: ImportTarget) {
        importDraft = ""
        importTarget = target
    }

    private func startExport(text: String, name: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        exportFilename = "\(name)-\(fmt.string(from: Date()))"
        exportDocument = LexiconTextFile(text: text)
        showFileExporter = true
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                errorToast = "无法读取这个文件"
                return
            }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            // 先放进预览框，确认后再导入
            importDraft = text
            importTarget = fileImportTarget
        case .failure(let error):
            let ns = error as NSError
            if !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) {
                errorToast = "无法打开文件：\(error.localizedDescription)"
            }
        }
    }

    private func importSheet(_ target: ImportTarget) -> some View {
        let validCount = target == .custom
            ? LexiconTSVParser.validCustomCount(importDraft)
            : LexiconTSVParser.validUserCount(importDraft)
        return NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $importDraft)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 200)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if importDraft.isEmpty {
                            Text(target.example)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Color(Design.Palette.muted))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    HStack(spacing: 8) {
                        Button {
                            // 页面提示会被弹窗挡住，剪贴板为空或为保险箱机密时不做任何事
                            if let p = ConcealedPasteboard.readNonConcealedStringForUserPaste() {
                                importDraft = importDraft.isEmpty ? p : importDraft + "\n" + p
                            }
                        } label: {
                            Label("粘贴", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                        .disabled(!UIPasteboard.general.hasStrings)

                        Button {
                            fileImportTarget = target
                            importTarget = nil
                            // 等导入弹窗收起后再打开文件选择器
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                showFileImporter = true
                            }
                        } label: {
                            Label("从文件选择", systemImage: "folder")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                        Spacer(minLength: 0)

                        if !importDraft.isEmpty {
                            Button("清空") { importDraft = "" }
                                .font(.caption.bold())
                                .foregroundStyle(Color(Design.Palette.stone))
                                .buttonStyle(.plain)
                                .frame(minHeight: 32)
                        }
                    }
                } header: {
                    HStack {
                        Text("内容")
                        Spacer()
                        Text(importDraft.isEmpty ? "" : "可导入 \(validCount) 条")
                            .monospacedDigit()
                            .foregroundStyle(validCount > 0 ? Color(Design.Palette.success) : Color(Design.Palette.error))
                            .textCase(nil)
                    }
                } footer: {
                    Text(target.formatHint + " 已有的条目不会被删除，相同的会合并。")
                }
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { importTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        let normalized = LexiconTSVParser.normalize(importDraft)
                        let count: Int
                        if target == .custom {
                            count = appState.importCustomWordsTSV(normalized)
                        } else {
                            count = appState.importUserLexiconTSV(normalized)
                            reloadWords()
                        }
                        importTarget = nil
                        importDraft = ""
                        if count > 0 {
                            toast = "已导入 \(count) 条"
                        } else {
                            errorToast = "没有导入任何内容，请检查格式"
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(validCount == 0)
                }
            }
        }
    }
}
