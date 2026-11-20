import SwiftUI
import UIKit

struct HomeTestView: View {
    @EnvironmentObject private var appState: AppState
    var onSelectTab: ((Int) -> Void)? = nil

    @State private var sandboxText: String = ""
    @State private var isSandboxLocked = false
    @State private var isTyping = false
    @State private var showGuide = false
    @State private var tipsExpanded = false
    @FocusState private var isTestingFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.xl) {
                    heroCard
                    statusSection
                    sandboxCard
                    tipsCard
                }
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("体验")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showGuide) {
                OnboardingGuideView()
            }
        }
    }

    // MARK: - 品牌条

    private var heroCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(Design.Palette.ink))
                    Image(systemName: "text.cursor")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.canvas))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text("灵犀输入法")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.ink))

                    Text("39.6 万词库 · 全拼/双拼/九宫格 · 流式 AI")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(Design.Palette.steel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    statusDot
                }

                Spacer(minLength: 0)
            }

            keyboardEntryCard
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
        .shadow(color: Color(Design.Palette.stone).opacity(0.08), radius: 1, x: 0, y: 1)
    }

    // MARK: - 键盘入口
    private var keyboardEntryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.ink))

            VStack(alignment: .leading, spacing: 4) {
                Text("开始打字")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(appState.isKeyboardEnabled ? "现在就能切出键盘打字" : "把灵犀加入系统键盘列表")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(Design.Palette.steel))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if appState.isKeyboardEnabled {
                Text("已在")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(Design.Palette.slate))
            } else {
                Button {
                    appState.refreshAll()
                } label: {
                    Text("加入")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .frame(width: 56, height: 36)
                .background(Color(Design.Palette.ink))
                .clipShape(Capsule())
                .foregroundStyle(Color(Design.Palette.canvas))
                .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(Design.Palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    private var statusDot: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(appState.isKeyboardEnabled ? Color(Design.Palette.success) : Color(Design.Palette.error))
                .frame(width: 6, height: 6)
            Text(appState.isKeyboardEnabled ? "运行中" : "未启用")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(Design.Palette.steel))
        }
    }

    // MARK: - 运行状态

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                "运行状态",
                trailing: pendingCount == 0 ? "全部就绪" : "\(pendingCount) 项待处理"
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                statusCard(
                    title: "系统键盘",
                    value: appState.isKeyboardEnabled ? "已添加启用" : "未添加到系统",
                    icon: appState.isKeyboardEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: appState.isKeyboardEnabled ? Color(Design.Palette.success) : Color(Design.Palette.error)
                ) {
                    if !appState.isKeyboardEnabled { showGuide = true }
                }

                statusCard(
                    title: "AI 引擎",
                    value: appState.aiConfig.isConfigured ? "密钥已就绪" : "待填写密钥",
                    icon: appState.aiConfig.isConfigured ? "sparkles" : "key.fill",
                    tint: appState.aiConfig.isConfigured ? Color(Design.Palette.ink) : Color(Design.Palette.stone)
                ) {
                    onSelectTab?(2)
                }
            }

            Rectangle()
                .fill(Color(Design.Palette.hairlineSoft))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                statusCard(
                    title: "App Group",
                    value: AppGroup.isAvailable ? "互通正常" : "容器受限",
                    icon: AppGroup.isAvailable ? "link.circle.fill" : "xmark.octagon.fill",
                    tint: AppGroup.isAvailable ? Color(Design.Palette.success) : Color(Design.Palette.error)
                )

                statusCard(
                    title: "输入方案",
                    value: appState.settings.inputScheme.displayName,
                    icon: "character.textbox",
                    tint: Color(Design.Palette.ink)
                ) {
                    onSelectTab?(4)
                }
            }

            if !appState.isKeyboardEnabled {
                HStack(spacing: 12) {
                    pillButton("开启教程", icon: "book", filled: false) {
                        showGuide = true
                    }
                    pillButton("去设置", icon: "gear", filled: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func statusCard(
        title: String,
        value: String,
        icon: String,
        tint: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(height: 18)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(Design.Palette.steel))
                    .padding(.top, 14)

                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(16)
            .background(Color(Design.Palette.canvas))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                    .stroke(Color(Design.Palette.hairline), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.ink))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(Design.Palette.stone))
            }
        }
    }

    private var pendingCount: Int {
        var count = 0
        if !appState.isKeyboardEnabled { count += 1 }
        if !appState.aiConfig.isConfigured { count += 1 }
        if !AppGroup.isAvailable { count += 1 }
        return count
    }

    // MARK: - 试打区

    private var sandboxCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题行：字数 / 复制所有文字 / 禁用输入 / 收软键盘
            HStack(spacing: 8) {
                Text("试打区")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))

                Spacer()

                Text("\(sandboxText.count) 字")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.stone))

                // 打字脉冲点：有可见的“正在输入”反馈，避免打字时空白
                TypingPulse(isPulsing: isTyping)

                if !sandboxText.isEmpty {
                    pillButton("复制所有文字", icon: "doc.on.clipboard", filled: false, compact: true) {
                        UIPasteboard.general.string = sandboxText
                    }
                }

                pillButton(
                    isSandboxLocked ? "解锁输入" : "禁用输入",
                    icon: isSandboxLocked ? "lock.open" : "lock",
                    filled: false,
                    compact: true
                ) {
                    isSandboxLocked.toggle()
                    if isSandboxLocked {
                        isTyping = false
                    }
                }

                if isTestingFocused {
                    Button {
                        isTestingFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(Design.Palette.steel))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $sandboxText)
                    .allowsHitTesting(!isSandboxLocked)
                    .focused($isTestingFocused)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 15))
                    .padding(12)
                    .frame(minHeight: 160)
                    .background(Color(Design.Palette.canvas))
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous)
                            .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                    )
                    .onChange(of: sandboxText) { new in
                        // 每次改动重新触发脉冲；停手 0.5 秒后淡出，仍能看到“正在输入”的反馈
                        guard !new.isEmpty, !isSandboxLocked else {
                            isTyping = false
                            return
                        }
                        isTyping = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isTyping = false }
                    }

                if sandboxText.isEmpty {
                    Text("点这里切出「灵犀输入法」，试打拼音、双拼、算式（125*8=）或调工具栏 AI。")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 17)
                        .padding(.top, 20)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 12) {
                pillButton("模拟验证码短信", icon: "doc.on.doc", filled: false, compact: true) {
                    let sample = "【灵犀测试】您的验证码是 849201，5分钟内有效。"
                    UIPasteboard.general.string = sample
                    appState.addClipboardEntry(sample)
                }

                Spacer(minLength: 0)

                if !sandboxText.isEmpty {
                    pillButton("清空", icon: "trash", filled: false, compact: true) {
                        sandboxText = ""
                        isTyping = false
                    }
                }
            }
        }
        .padding(16)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    // MARK: - 打字脉冲指示
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
                .animation(isPulsing ? .easeOut(duration: 0.5).repeatForever(autoreverses: true) : .easeOut(duration: 0.12), value: phase)
        }
    }

    // MARK: - 玩法速查

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("高频玩法")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Text("\(Self.allTips.count) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(Design.Palette.stone))
            }
            .padding(.bottom, 4)

            ForEach(Array(visibleTips.indices), id: \.self) { index in
                if index > 0 {
                    Rectangle()
                        .fill(Color(Design.Palette.hairlineSoft))
                        .frame(height: 1)
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
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color(Design.Palette.ink))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    private var visibleTips: [PlayTip] {
        tipsExpanded ? Self.allTips : Array(Self.allTips.filter(\.isPopular).prefix(4))
    }

    private func tipRow(_ tip: PlayTip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(Design.Palette.ink))
                .frame(width: 20, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(tip.desc)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(Design.Palette.slate))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    // MARK: - 按钮

    private func pillButton(
        _ title: String,
        icon: String,
        filled: Bool,
        compact: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(filled ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
            .padding(.horizontal, compact ? 12 : 16)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: 44)
            .background(filled ? Color(Design.Palette.ink) : Color(Design.Palette.canvas))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(filled ? Color.clear : Color(Design.Palette.hairline), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - 玩法条目

private struct PlayTip {
    let icon: String
    let title: String
    let desc: String
    /// 默认只折叠卡里展示的“必要项”；其余藏在“展开全部 N 条”里。
    let isPopular: Bool = false
}

/// 统一按压反馈：极简白不靠色块变化，只降透明度。
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.62 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension HomeTestView {
    static var allTips: [PlayTip] {
        [
            PlayTip(
                icon: "scribble.variable",
                title: "26 键中英文滑行输入",
                desc: "手指在字母上连续滑过即可成词（nihao → 你好、hello），按一次 ⌫ 整词撤销。",
                isPopular: true
            ),
            PlayTip(
                icon: "magnifyingglass.circle",
                title: "u 模式 · 拆字与笔画反查",
                desc: "全拼输 u（双拼/五笔长按 u 选 U）查生僻字并带读音：ushuishuishui → 淼、uhspn → 木。",
                isPopular: true
            ),
            PlayTip(
                icon: "keyboard.badge.ellipsis",
                title: "全拼 + 7 双拼 + 五笔 86 + 九宫格",
                desc: "内置 39.6 万雾凇词库与 9.3 万五笔码表；五笔按 z 临时转拼音并实时反查编码。"
            ),
            PlayTip(
                icon: "arrow.up.and.down.and.arrow.left.and.right",
                title: "✥ 光标精控面板",
                desc: "点工具栏十字图标开启四向方向键、行首行尾跳转、向前删 ⌦、复制粘贴与清空本行。"
            ),
            PlayTip(
                icon: "globe",
                title: "译 · 14 语种边打边译",
                desc: "点工具栏「译」照常输中文，一键切口语/正式语气，空格上屏译文。"
            ),
            PlayTip(
                icon: "function",
                title: "v 模式 · 大写金额 / 算式 / 日期",
                desc: "全拼输 v、双拼与五笔上划 V：v125*8 同时出 1000 与「壹仟元整」，vrq / vsj 查日期。",
                isPopular: true
            ),
            PlayTip(
                icon: "character.textbox",
                title: "以词定字 & 退格撤学",
                desc: "长按候选可单取首/尾字；上屏选错词立刻按 ⌫，恢复原拼音并撤销误学词频。"
            ),
            PlayTip(
                icon: "face.smiling",
                title: "句尾表情推荐 & 拼音搜表情",
                desc: "全方案自动推荐句尾表情（今天好开心😊），也支持拼音直搜表情、箭头与颜文字。",
                isPopular: true
            ),
            PlayTip(
                icon: "sparkles",
                title: "AI 自由问 & 剪贴板炸词",
                desc: "支持拼音自由问 AI、神回复剪贴板、长短信 BigBang 炸词，custom.tsv / user.tsv 可导入导出。"
            )
        ]
    }
}
