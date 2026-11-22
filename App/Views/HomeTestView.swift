import SwiftUI
import UIKit

/// 首页工作台：对标苹果原生 App 清爽层级——顶部云同步状态胶囊、一键快捷开关条、5 场景实时试打台与 2×2 核心入口。
struct HomeTestView: View {
    @EnvironmentObject private var appState: AppState
    var onSelectTab: ((Int) -> Void)? = nil

    @State private var sandboxText: String = ""
    @State private var isSandboxLocked = false
    @State private var isTyping = false
    @State private var showGuide = false
    @State private var showSignInSheet = false
    @State private var navigateToAccount = false
    @State private var navigateToLocation = false
    @State private var tipsExpanded = false
    @ObservedObject private var locationService = LiveLocationLexiconService.shared
    @FocusState private var isTestingFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusHeroBanner
                    quickControlStrip
                    sandboxCard
                    quickBentoGrid
                    tipsCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("灵犀")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if appState.isCloudAuthenticated {
                            navigateToAccount = true
                        } else {
                            showSignInSheet = true
                        }
                    } label: {
                        UserAvatarView(size: 32, showEditBadge: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(appState.isCloudAuthenticated ? "个人账号" : "登录灵犀账号")
                }
            }
            .navigationDestination(isPresented: $navigateToAccount) {
                CloudAccountView()
            }
            .navigationDestination(isPresented: $navigateToLocation) {
                LocationLexiconView()
            }
            .sheet(isPresented: $showGuide) {
                OnboardingGuideView()
            }
            .sheet(isPresented: $showSignInSheet) {
                AppleStyleSignInSheet()
            }
        }
    }

    // MARK: - 1. 顶部状态横幅（含云同步状态胶囊）

    private var statusHeroBanner: some View {
        let health = EngineHealthAndSustainabilityService.shared.diagnose()
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(Design.Palette.accent))
                        .frame(width: 42, height: 42)
                    Image(systemName: appState.isKeyboardEnabled ? "checkmark.seal.fill" : "keyboard")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(appState.isKeyboardEnabled ? "灵犀 5.1 已就绪" : "尚未在系统设置中启用灵犀")
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        if appState.isKeyboardEnabled {
                            Circle()
                                .fill(Color(Design.Palette.success))
                                .frame(width: 7, height: 7)
                        }
                    }
                    Text("\(appState.settings.inputScheme.displayName) · \(appState.theme.appearanceMode.displayName) · 健康 \(health.healthScore) 分")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    if appState.isKeyboardEnabled {
                        isTestingFocused = true
                    } else {
                        showGuide = true
                    }
                } label: {
                    Text(appState.isKeyboardEnabled ? "去试打" : "去启用")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Color(Design.Palette.accent))
                        .foregroundStyle(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }

            // 实时云同步与账号身份胶囊条
            Button {
                if appState.isCloudAuthenticated {
                    navigateToAccount = true
                } else {
                    showSignInSheet = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: appState.isCloudAuthenticated && !appState.cloudConfig.isLocalOnlyAccount ? "icloud.fill" : "apple.logo")
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.accent))
                    if appState.isCloudAuthenticated {
                        let summary = appState.cloudConfig.lastSyncSummary.isEmpty ? "10 类核心数据端到端同步就绪" : appState.cloudConfig.lastSyncSummary
                        Text("\(appState.cloudConfig.username.isEmpty ? "灵犀用户" : appState.cloudConfig.username) · \(summary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("点此通过 Apple 通行密钥 / 面容 ID 登录 Cloudflare 全球云")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(Design.Palette.accent))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(Design.Palette.surface))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            // 实时地理位置与周边地标词库胶囊条
            Button {
                navigateToLocation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: locationService.currentContext.isPopulated ? "location.fill" : "mappin.and.ellipse")
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.accent))
                    if locationService.currentContext.isPopulated {
                        Text("实时位置：\(locationService.currentContext.compactLocationLabel) · 已学会 \(locationService.currentContext.pois.count) 个周边地标")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("开启实时位置词库：自动学习当前城市、路名与 5km 周边商圈")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(Design.Palette.surface))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            if !appState.isKeyboardEnabled {
                HStack(spacing: 10) {
                    pillButton("查看开启教程", icon: "book", filled: false) {
                        showGuide = true
                    }
                    pillButton("打开系统设置", icon: "gear", filled: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 1.5 一键快捷调节栏（方案 / 布局 / 日夜外观 / 思考模式秒切）

    private var quickControlStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickTogglePill(icon: "textformat.abc", label: appState.settings.inputScheme.displayName) {
                    let all = InputScheme.allCases
                    if let idx = all.firstIndex(of: appState.settings.inputScheme) {
                        appState.settings.inputScheme = all[(idx + 1) % all.count]
                    }
                }
                quickTogglePill(icon: "keyboard", label: appState.settings.layoutMode.displayName) {
                    let all = KeyboardLayoutMode.allCases
                    if let idx = all.firstIndex(of: appState.settings.layoutMode) {
                        appState.settings.layoutMode = all[(idx + 1) % all.count]
                    }
                }
                quickTogglePill(icon: "circle.lefthalf.filled", label: appState.theme.appearanceMode.displayName) {
                    let modes = KeyboardAppearanceMode.allCases
                    if let idx = modes.firstIndex(of: appState.theme.appearanceMode) {
                        appState.theme.applyAppearanceMode(modes[(idx + 1) % modes.count])
                    }
                }
                quickTogglePill(icon: "brain", label: "思考: \(appState.aiConfig.thinkingMode.shortBadge)") {
                    let modes: [AIThinkingMode] = [.off, .auto, .low, .medium, .high]
                    if let idx = modes.firstIndex(of: appState.aiConfig.thinkingMode) {
                        appState.aiConfig.thinkingMode = modes[(idx + 1) % modes.count]
                    } else {
                        appState.aiConfig.thinkingMode = .auto
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func quickTogglePill(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.accent))
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.5))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 2. 实时试打体验区（5 大场景一键实测）

    private var sandboxCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("试打体验台")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))

                Spacer()

                Text("\(sandboxText.count) 字")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)

                TypingPulse(isPulsing: isTyping)

                if !sandboxText.isEmpty {
                    Button {
                        UIPasteboard.general.string = sandboxText
                        appState.addClipboardEntry(sandboxText)
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Color(Design.Palette.accent))
                            .frame(width: 30, height: 30)
                            .background(Color(Design.Palette.surface))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                }

                if isTestingFocused {
                    Button {
                        isTestingFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $sandboxText)
                    .allowsHitTesting(!isSandboxLocked)
                    .focused($isTestingFocused)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 15.5))
                    .padding(12)
                    .frame(minHeight: 136)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: sandboxText) { new in
                        guard !new.isEmpty, !isSandboxLocked else {
                            isTyping = false
                            return
                        }
                        isTyping = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isTyping = false }
                    }

                if sandboxText.isEmpty {
                    Text("点这里切出「灵犀输入法」，试打 linyi（临沂）、vwz 发当前位置、@ai 写条朋友圈，或点下方场景芯片体验。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 17)
                        .padding(.top, 20)
                        .allowsHitTesting(false)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    compactChip("模拟验证码", icon: "message.badge.filled.fill") {
                        let sample = "【灵犀测试】您的验证码是 849201，5分钟内有效。"
                        UIPasteboard.general.string = sample
                        appState.addClipboardEntry(sample)
                    }
                    compactChip("测试 @ai 随打指令", icon: "bolt.fill") {
                        sandboxText = "@ai 写一条今天在临沂打卡美食的轻松朋友圈"
                        isTestingFocused = true
                    }
                    compactChip("模拟框选即改", icon: "sparkles") {
                        sandboxText = "明天下午两点我实在赶不过去，能不能往后推一天再碰一下需求？"
                        isTestingFocused = true
                    }
                    compactChip("模拟博弈消息", icon: "chess.knight") {
                        let msg = "这周六临时加个班把方案赶出来吧，周一早上老板要看。"
                        UIPasteboard.general.string = msg
                        appState.addClipboardEntry(msg)
                        isTestingFocused = true
                    }
                    compactChip("测试英文剪贴板", icon: "globe") {
                        let msg = "Could we postpone Friday's architecture sync to Monday morning?"
                        UIPasteboard.general.string = msg
                        appState.addClipboardEntry(msg)
                    }
                    if !sandboxText.isEmpty {
                        compactChip("清空", icon: "trash") {
                            sandboxText = ""
                            isTyping = false
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 3. 2×2 Apple Bento 核心功能入口

    private var quickBentoGrid: some View {
        let todayChars = TypingStatsStore.shared.summary().todayChars
        let health = EngineHealthAndSustainabilityService.shared.diagnose()
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            Button {
                onSelectTab?(1)
            } label: {
                bentoTile(
                    icon: "paintpalette.fill",
                    title: "日夜双套外观",
                    subtitle: "12 套精校主题 · 圆角 \(Int(appState.theme.keyCornerRadius))pt"
                )
            }
            .buttonStyle(PressableStyle())

            Button {
                onSelectTab?(2)
            } label: {
                bentoTile(
                    icon: "brain.head.profile",
                    title: "AI 灵犀智脑",
                    subtitle: "\(appState.aiConfig.activeModelName) · 思考\(appState.aiConfig.thinkingMode.shortBadge)"
                )
            }
            .buttonStyle(PressableStyle())

            NavigationLink {
                TypingStatsView()
            } label: {
                bentoTile(
                    icon: "chart.bar.fill",
                    title: "进化周报与热力图",
                    subtitle: "今日 \(todayChars) 字 · 26 键手型校准"
                )
            }
            .buttonStyle(PressableStyle())

            NavigationLink {
                SustainabilityHubView()
            } label: {
                bentoTile(
                    icon: "leaf.arrow.triangle.circlepath",
                    title: "多模同步与自愈",
                    subtitle: "\(health.activeTransport.title.components(separatedBy: " · ").first ?? "离线") · \(health.healthScore)分"
                )
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func bentoTile(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.accent))
                .frame(width: 34, height: 34)
                .background(Color(Design.Palette.accentSoft))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 4. 高频玩法速查

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("灵犀 5.1 进阶玩法")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Text("\(Self.allTips.count) 条")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            ForEach(Array(visibleTips.indices), id: \.self) { index in
                if index > 0 { Divider() }
                tipRow(visibleTips[index])
            }

            Button {
                tipsExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text(tipsExpanded ? "收起" : "展开全部 \(Self.allTips.count) 条")
                    Image(systemName: tipsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(Design.Palette.accent))
                .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var visibleTips: [PlayTip] {
        tipsExpanded ? Self.allTips : Array(Self.allTips.filter(\.isPopular).prefix(4))
    }

    private func tipRow(_ tip: PlayTip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.icon)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color(Design.Palette.accent))
                .frame(width: 20, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(tip.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(tip.desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    // MARK: - 辅助控件

    private func compactChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.accent))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(Color(Design.Palette.surface))
            .foregroundStyle(Color(Design.Palette.ink))
            .clipShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private func pillButton(_ title: String, icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundStyle(filled ? Color.white : Color(Design.Palette.ink))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(filled ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
            .clipShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private struct TypingPulse: View {
        let isPulsing: Bool
        @State private var phase: CGFloat = 0

        var body: some View {
            Circle()
                .fill(Color(Design.Palette.accent))
                .frame(width: 6, height: 6)
                .scaleEffect(isPulsing ? 0.8 + phase * 0.4 : 0.85)
                .opacity(isPulsing ? 0.75 + phase * 0.25 : 0.18)
                .onChange(of: isPulsing) { new in
                    withAnimation(new ? .easeOut(duration: 0.5).repeatForever(autoreverses: true) : .easeOut(duration: 0.12)) {
                        phase = new ? 1 : 0
                    }
                }
        }
    }
}

private struct PlayTip {
    let icon: String
    let title: String
    let desc: String
    var isPopular: Bool = false
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension HomeTestView {
    static var allTips: [PlayTip] {
        [
            PlayTip(
                icon: "bolt.circle.fill",
                title: "随打 @ai / // 零切屏指令 + 🎲3选1气泡",
                desc: "聊天时直接打「@ai 帮我委婉拒加班」顶栏立刻浮现一键执行；打开 AI 面板点「🎲3选1」一次出 3 种风格，支持版本回退与 ⭐存短语。",
                isPopular: true
            ),
            PlayTip(
                icon: "location.fill",
                title: "全国 6,403 地名库 + 实时 GPS 5km 周边自学习",
                desc: "全国省市区县（如临沂/兰山区/费县/菏泽）开箱首选；开启定位自动学会附近路名、商圈、小区与高铁站，打 vwz / vdz 一键发当前位置。",
                isPopular: true
            ),
            PlayTip(
                icon: "sparkles",
                title: "框选即改 + 顺着续写 + 博弈军师",
                desc: "选中任意段落即浮现「润色 / 更委婉 / 译英」；写到一半点「顺着续写」自然接续；复制棘手消息点「博弈军师」一键出 3 套高情商回复。",
                isPopular: true
            ),
            PlayTip(
                icon: "character.textbox",
                title: "长拼音单字音节回改 & 四声调精准筛字",
                desc: "打长句时点顶栏任意拼音音节可原地换单字不退格；展开候选切「只看单字」后支持按一声/二声/三声/四声秒选生僻字。",
                isPopular: true
            ),
            PlayTip(
                icon: "textformat.123",
                title: "中数英无缝混输（无需切换键盘）",
                desc: "直接连打 mingtian3dianjian 出「明天3点见」，打 fayigepdfgeiwo 出「发一个PDF给我」。"
            ),
            PlayTip(
                icon: "arrow.up.and.down.and.arrow.left.and.right",
                title: "专业文本编辑台 + 26 键自定义滑行映射",
                desc: "从键盘快捷设置打开「📐 编辑台」精准移动光标、一键盘古空格/去空行；在效率中心自由定义任意键上下滑输出。"
            ),
            PlayTip(
                icon: "function",
                title: "v 模式 · 财务大写金额与 AA 均摊",
                desc: "全拼输 v12800rmb 出「壹万贰仟捌佰元整」，输 v1280/4 自动出「人均 ¥320」。"
            ),
            PlayTip(
                icon: "lock.shield.fill",
                title: "Face ID 本地加密安全保险箱",
                desc: "身份证、银行卡与税号经面容 ID 保护存于本机独立容器，绝不上传云端、绝不污染剪贴板历史。"
            )
        ]
    }
}
