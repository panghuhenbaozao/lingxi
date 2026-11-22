import SwiftUI
import UIKit

/// 首页工作台：对标苹果原生 App（App Store / 健康）清爽层级——右上角圆形头像直达账号/登录，主屏聚焦试打体验与四宫格核心入口。
struct HomeTestView: View {
    @EnvironmentObject private var appState: AppState
    var onSelectTab: ((Int) -> Void)? = nil

    @State private var sandboxText: String = ""
    @State private var isSandboxLocked = false
    @State private var isTyping = false
    @State private var showGuide = false
    @State private var showSignInSheet = false
    @State private var navigateToAccount = false
    @State private var tipsExpanded = false
    @FocusState private var isTestingFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    statusHeroBanner
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
            .sheet(isPresented: $showGuide) {
                OnboardingGuideView()
            }
            .sheet(isPresented: $showSignInSheet) {
                AppleStyleSignInSheet()
            }
        }
    }

    // MARK: - 1. 顶部精简状态横幅（未启用时高对比引导，启用后清爽一行）

    private var statusHeroBanner: some View {
        let health = EngineHealthAndSustainabilityService.shared.diagnose()
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(Design.Palette.ink))
                        .frame(width: 42, height: 42)
                    Image(systemName: appState.isKeyboardEnabled ? "checkmark.seal.fill" : "keyboard")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.canvas))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(appState.isKeyboardEnabled ? "灵犀输入法已就绪" : "尚未在系统设置中启用灵犀")
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        if appState.isKeyboardEnabled {
                            Circle()
                                .fill(Color(Design.Palette.success))
                                .frame(width: 7, height: 7)
                        }
                    }
                    Text("\(appState.settings.inputScheme.displayName) · \(appState.theme.appearanceMode.displayName) · 引擎健康 \(health.healthScore) 分")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if appState.isKeyboardEnabled {
                    Button {
                        isTestingFocused = true
                    } label: {
                        Text("去试打")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Color(Design.Palette.ink))
                            .foregroundStyle(Color(Design.Palette.canvas))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                } else {
                    Button {
                        showGuide = true
                    } label: {
                        Text("去启用")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Color(Design.Palette.ink))
                            .foregroundStyle(Color(Design.Palette.canvas))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }

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

    // MARK: - 2. 实时试打体验区（可直接实测顶栏验证码/新复制内容接管）

    private var sandboxCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("试打体验区")
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
                            .foregroundStyle(Color(Design.Palette.ink))
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
                    Text("点这里切出「灵犀输入法」，试打拼音、双拼、退格删除或点下方按钮测试顶栏验证码秒填。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 17)
                        .padding(.top, 20)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                compactChip("模拟验证码短信", icon: "message.badge.filled.fill") {
                    let sample = "【灵犀测试】您的验证码是 849201，5分钟内有效。"
                    UIPasteboard.general.string = sample
                    appState.addClipboardEntry(sample)
                }
                compactChip("模拟长文本滑动", icon: "doc.on.doc") {
                    let sample = "灵犀输入法 · 纯白圆角按键，支持顶栏复制内容与短信验证码左右滑动查看完整全文并一键填入"
                    UIPasteboard.general.string = sample
                    appState.addClipboardEntry(sample)
                }
                Spacer(minLength: 0)
                if !sandboxText.isEmpty {
                    compactChip("清空", icon: "trash") {
                        sandboxText = ""
                        isTyping = false
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
                    title: "外观与自由调色",
                    subtitle: appState.theme.hasCustomColorOverrides
                        ? "自定义调色中 · 圆角 \(Int(appState.theme.keyCornerRadius))pt"
                        : "\(appState.theme.appearanceMode.displayName) · 圆角 \(Int(appState.theme.keyCornerRadius))pt"
                )
            }
            .buttonStyle(PressableStyle())

            NavigationLink {
                TypingStatsView()
            } label: {
                bentoTile(
                    icon: "chart.bar.fill",
                    title: "打字统计与画像",
                    subtitle: "今日 \(todayChars) 字 · 本机 24h 节律"
                )
            }
            .buttonStyle(PressableStyle())

            Button {
                onSelectTab?(3)
            } label: {
                bentoTile(
                    icon: "laptopcomputer.and.iphone",
                    title: "跨屏剪贴板",
                    subtitle: "6 位码实时 SSE 秒传与炸词"
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
                .foregroundStyle(Color(Design.Palette.ink))
                .frame(width: 34, height: 34)
                .background(Color(Design.Palette.surface))
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
                Text("高频玩法")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Text("\(Self.allTips.count) 条")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            ForEach(Array(visibleTips.indices), id: \.self) { index in
                if index > 0 {
                    Divider()
                }
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
                .foregroundStyle(Color(Design.Palette.ink))
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
        tipsExpanded ? Self.allTips : Array(Self.allTips.filter(\.isPopular).prefix(3))
    }

    private func tipRow(_ tip: PlayTip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.icon)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color(Design.Palette.ink))
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
            .foregroundStyle(filled ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(filled ? Color(Design.Palette.ink) : Color(Design.Palette.surface))
            .clipShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private struct TypingPulse: View {
        let isPulsing: Bool
        @State private var phase: CGFloat = 0

        var body: some View {
            Circle()
                .fill(Color(Design.Palette.stone))
                .frame(width: 6, height: 6)
                .scaleEffect(isPulsing ? 0.8 + phase * 0.4 : 0.85)
                .opacity(isPulsing ? 0.7 + phase * 0.3 : 0.15)
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
                icon: "menubar.rectangle",
                title: "顶栏智能全栏接管（验证码 / 刚复制内容秒填）",
                desc: "复制新内容或收到短信验证码时，自动隐藏 AI/译按钮，整栏切换为一键填入/粘贴胶囊。",
                isPopular: true
            ),
            PlayTip(
                icon: "laptopcomputer.and.iphone",
                title: "6 位匹配码跨屏剪贴板实时秒传",
                desc: "电脑与手机输入相同 6 位码，免登录通过 SSE 毫秒级双向接力文本与短信验证码。",
                isPopular: true
            ),
            PlayTip(
                icon: "scribble.variable",
                title: "26 键中英文滑行输入与空格移光标",
                desc: "手指连续滑过字母成词；在空格键左右滑动即可丝滑移动光标定位。",
                isPopular: true
            ),
            PlayTip(
                icon: "magnifyingglass.circle",
                title: "u 模式 · 拆字与笔画反查",
                desc: "全拼输 u 查生僻字并带读音：ushuishuishui → 淼、uhspn → 木。"
            ),
            PlayTip(
                icon: "function",
                title: "v 模式 · 大写金额 / 算式 / 日期",
                desc: "全拼输 v125*8 同时出 1000 与「壹仟元整」，vrq / vsj 快速插入日期时间。"
            ),
            PlayTip(
                icon: "globe",
                title: "译 · 14 语种实时边打边译",
                desc: "点顶栏「译」照常输中文，一键切口语/正式语气，空格直接上屏译文。"
            )
        ]
    }
}
