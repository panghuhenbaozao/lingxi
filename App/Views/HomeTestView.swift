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
    @State private var toolbarPreviewMode: Int = 0 // 0=常规双簇态, 1=验证码全栏接管态, 2=新复制内容全栏接管态
    @FocusState private var isTestingFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.xl) {
                    heroCard
                    statusSection
                    hubEntriesSection
                    toolbarLiveSimulatorCard
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
                    HStack(spacing: 6) {
                        Text("灵犀输入法")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("v4.0 Open-Core")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(Design.Palette.surface))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .clipShape(Capsule())
                    }

                    Text("39.6 万词库 · 顶栏智能接管 · 跨屏剪贴板 · 零知识同步")
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
                Text(appState.isKeyboardEnabled ? "现在就能唤起灵犀键盘体验极速输入" : "将灵犀加入系统键盘列表，开启完整体验")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(Design.Palette.steel))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if appState.isKeyboardEnabled {
                Button {
                    isTestingFocused = true
                } label: {
                    Text("去试打")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
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
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color(Design.Palette.ink))
                        .foregroundStyle(Color(Design.Palette.canvas))
                        .clipShape(Capsule())
                }
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
        let report = EngineHealthAndSustainabilityService.shared.diagnose()
        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(appState.isKeyboardEnabled ? Color(Design.Palette.success) : Color(Design.Palette.error))
                    .frame(width: 6, height: 6)
                Text(appState.isKeyboardEnabled ? "运行中" : "未启用")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(Design.Palette.steel))
            }
            Text("· 引擎健康 \(report.healthScore) 分 · \(report.activeTransport.title)")
                .font(.system(size: 11))
                .foregroundStyle(Color(Design.Palette.stone))
                .lineLimit(1)
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

                statusCard(
                    title: "App Group 安全容器",
                    value: AppGroup.isAvailable ? "L1 加密互通正常" : "容器受限",
                    icon: AppGroup.isAvailable ? "lock.shield.fill" : "xmark.octagon.fill",
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

    // MARK: - 核心中枢双卡片（云端画像/跨屏剪贴板 + 可持续发展/多模同步/引擎自愈）

    private var hubEntriesSection: some View {
        VStack(spacing: 10) {
            NavigationLink {
                CloudAccountView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                        .frame(width: 36, height: 36)
                        .background(Color(Design.Palette.surface))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("云端同步 · 6位码跨屏剪贴板 · 打字习惯画像")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            if appState.isCloudAuthenticated {
                                Text("已连接")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Color(Design.Palette.success))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(Design.Palette.surface))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(appState.habitProfile.habitTags.isEmpty
                             ? "6位码免登录跨屏传剪贴板 · E2EE 零知识同步 · 实时打字习惯分析"
                             : "画像标签：" + appState.habitProfile.habitTags.joined(separator: " · "))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(Design.Palette.steel))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.stone))
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(Design.Palette.canvas))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                        .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                SustainabilityHubView()
            } label: {
                let health = EngineHealthAndSustainabilityService.shared.diagnose()
                HStack(spacing: 12) {
                    Image(systemName: "leaf.arrow.triangle.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                        .frame(width: 36, height: 36)
                        .background(Color(Design.Palette.surface))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("可持续发展 · 三模同步切换 · 局域网互导 · 引擎自愈")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text("\(health.healthScore)分")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(Design.Palette.surface))
                                .clipShape(Capsule())
                        }
                        Text("\(health.activePlan.displayName) · \(health.activeTransport.title) · M4 开源词库仓")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(Design.Palette.steel))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.stone))
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(Design.Palette.canvas))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                        .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 键盘顶栏 v3 三态与全栏独占接管交互仿真器

    private var toolbarLiveSimulatorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("键盘顶栏 v3 · 全栏独占接管实时交互预览", systemImage: "menubar.rectangle")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Text(toolbarPreviewMode == 0 ? "常规双簇态" : (toolbarPreviewMode == 1 ? "验证码独占态" : "新复制独占态"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(Design.Palette.stone))
            }

            Picker("顶栏状态仿真", selection: $toolbarPreviewMode) {
                Text("常规双簇 (AI/译)").tag(0)
                Text("验证码到达接管").tag(1)
                Text("刚复制内容接管").tag(2)
            }
            .pickerStyle(.segmented)

            // 拟真 50pt 键盘顶栏
            HStack(spacing: 8) {
                if toolbarPreviewMode == 0 {
                    // 左主功能簇
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("灵犀 AI")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(Color(Design.Palette.ink).opacity(0.10))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .clipShape(Capsule())

                    HStack(spacing: 4) {
                        Image(systemName: "character.bubble")
                            .font(.system(size: 11, weight: .semibold))
                        Text("译")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color(Design.Palette.canvas))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.5))

                    Spacer()

                    // 右轻量工具簇（无表情/无光标移动/无⋯折叠）
                    ForEach(["doc.on.clipboard", "slider.horizontal.3"], id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .frame(width: 30, height: 30)
                            .background(Color(Design.Palette.canvas))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 0.5))
                    }
                } else if toolbarPreviewMode == 1 {
                    // 场景 A：短信验证码全栏独占接管（隐藏 AI/译）
                    HStack(spacing: 4) {
                        Image(systemName: "message.badge.filled.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("验证码")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(Design.Palette.ink).opacity(0.10))
                    .clipShape(Capsule())

                    Text("849201 · 【灵犀】5分钟内有效")
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(Design.Palette.ink))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Button {
                        sandboxText += "849201"
                        toolbarPreviewMode = 0
                    } label: {
                        Text("填入 849201")
                            .font(.system(size: 11.5, weight: .bold))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Color(Design.Palette.ink))
                            .foregroundStyle(Color(Design.Palette.canvas))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        toolbarPreviewMode = 0
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                } else {
                    // 场景 B：刚复制的内容全栏独占接管（隐藏 AI/译）
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("刚复制")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(Design.Palette.ink).opacity(0.10))
                    .clipShape(Capsule())

                    Text(UIPasteboard.general.string ?? "灵犀输入法跨屏剪贴板秒传测试")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(Design.Palette.ink))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Button {
                        let text = UIPasteboard.general.string ?? "灵犀输入法跨屏剪贴板秒传测试"
                        sandboxText += text
                        toolbarPreviewMode = 0
                    } label: {
                        Text("粘贴")
                            .font(.system(size: 11.5, weight: .bold))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Color(Design.Palette.ink))
                            .foregroundStyle(Color(Design.Palette.canvas))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        toolbarPreviewMode = 0
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Color(Design.Palette.surface))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(Design.Palette.hairline), lineWidth: 1)
            )
        }
        .padding(16)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
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
            HStack(spacing: 8) {
                Text("试打区")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))

                Spacer()

                Text("\(sandboxText.count) 字")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.stone))

                TypingPulse(isPulsing: isTyping)

                if !sandboxText.isEmpty {
                    pillButton("复制所有文字", icon: "doc.on.clipboard", filled: false, compact: true) {
                        UIPasteboard.general.string = sandboxText
                        appState.addClipboardEntry(sandboxText)
                        toolbarPreviewMode = 2
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
                        guard !new.isEmpty, !isSandboxLocked else {
                            isTyping = false
                            return
                        }
                        isTyping = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isTyping = false }
                    }

                if sandboxText.isEmpty {
                    Text("点这里切出「灵犀输入法」，试打拼音、双拼、算式（v125*8）或点下方「模拟验证码短信」查看顶栏全栏接管。")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 17)
                        .padding(.top, 20)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 10) {
                pillButton("模拟验证码短信", icon: "message.badge.filled.fill", filled: false, compact: true) {
                    let sample = "【灵犀测试】您的验证码是 849201，5分钟内有效。"
                    UIPasteboard.general.string = sample
                    appState.addClipboardEntry(sample)
                    toolbarPreviewMode = 1
                }

                pillButton("模拟复制内容", icon: "doc.on.clipboard", filled: false, compact: true) {
                    let sample = "https://lingxi.app/open-core-sync"
                    UIPasteboard.general.string = sample
                    appState.addClipboardEntry(sample)
                    toolbarPreviewMode = 2
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
    var isPopular: Bool = false
}

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
                icon: "menubar.rectangle",
                title: "顶栏智能全栏接管（验证码 / 初次复制秒填）",
                desc: "收到短信验证码或复制新内容时，自动隐藏 AI/译按钮，整栏切换为一键填入/粘贴胶囊；敏感身份证/密码自动屏蔽。",
                isPopular: true
            ),
            PlayTip(
                icon: "laptopcomputer.and.iphone",
                title: "6 位匹配码跨屏剪贴板实时接力",
                desc: "对标微信输入法跨屏剪贴板：免登录输入相同 6 位码，电脑与手机之间通过 SSE 毫秒级互传剪贴板与验证码。",
                isPopular: true
            ),
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
                icon: "space",
                title: "空格键无感触控板移光标",
                desc: "在空格键上左右滑动即可丝滑移动光标定位，无需在顶栏放置低频方向键。"
            ),
            PlayTip(
                icon: "globe",
                title: "译 · 14 语种边打边译",
                desc: "点工具栏「译」照常输中文，一键切口语/正式语气，空格上屏译文。"
            ),
            PlayTip(
                icon: "function",
                title: "v 模式 · 大写金额 / 算式 / 日期",
                desc: "全拼输 v、双拼与五笔上划 V：v125*8 同时出 1000 与「壹仟元整」，vrq / vsj 查日期。"
            ),
            PlayTip(
                icon: "character.textbox",
                title: "以词定字 & 退格撤学",
                desc: "长按候选可单取首/尾字；上屏选错词立刻按 ⌫，恢复原拼音并撤销误学词频。"
            )
        ]
    }
}
