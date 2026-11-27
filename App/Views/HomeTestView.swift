import SwiftUI
import UIKit

/// 极简首页工作台（v6）：状态卡（键盘就绪 / 权限 / 云端 / 侧载同步）→ 今日打字 → 常用入口 → 试打区。
/// 一屏看清状态，下一步该做什么永远只有一个主按钮。
struct HomeTestView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var bgVoice = BackgroundVoiceEngine.shared
    @Environment(\.colorScheme) private var colorScheme
    var onSelectTab: ((Int) -> Void)? = nil

    @State private var sandboxText: String = ""
    @State private var showGuide = false
    @State private var showSignInSheet = false
    @State private var navigateToAccount = false
    @State private var navigateToStats = false
    @State private var toast: String?
    @State private var isSyncingBridge = false
    @State private var isTogglingVoice = false
    @State private var statsDebounceTask: Task<Void, Never>?
    @FocusState private var isTestingFocused: Bool

    private enum KeyboardSetupState {
        case notEnabled, noFullAccess, ready
    }

    private var setupState: KeyboardSetupState {
        if !appState.isKeyboardEnabled { return .notEnabled }
        if !appState.isKeyboardFullAccessConfirmed { return .noFullAccess }
        return .ready
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.md) {
                    statusCard
                    todayStatsCard
                    quickEntriesCard
                    sandboxCard
                }
                .lxReadableWidth()
                .padding(.horizontal, Design.Spacing.md)
                .padding(.top, Design.Spacing.xs)
                .padding(.bottom, Design.Spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("灵犀")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        openAccount()
                    } label: {
                        UserAvatarView(size: 32, showEditBadge: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(appState.isCloudAuthenticated ? "个人账号" : "登录灵犀账号")
                }
            }
            .lxToast($toast)
            .onAppear {
                appState.reloadSharedThemeAndSettingsIfNeeded()
            }
            .onDisappear {
                statsDebounceTask?.cancel()
            }
            .navigationDestination(isPresented: $navigateToAccount) {
                CloudAccountView()
            }
            .navigationDestination(isPresented: $navigateToStats) {
                TypingStatsView()
            }
            .sheet(isPresented: $showGuide) {
                OnboardingGuideView()
            }
            .sheet(isPresented: $showSignInSheet) {
                AppleStyleSignInSheet()
            }
        }
    }

    // MARK: - 1. 状态卡

    private var statusCard: some View {
        let activePreset = appState.theme.activePreset(isSystemDark: colorScheme == .dark)
        let ready = setupState == .ready
        return LXCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: ready ? "checkmark.seal.fill" : "keyboard")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                        .background(
                            ready ? Color(Design.Palette.success) : Color(Design.Palette.accent),
                            in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(ready ? Color(Design.Palette.success) : Color(Design.Palette.warning))
                                .frame(width: 8, height: 8)
                            Text(statusTitle)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            if appState.settings.incognitoModeEnabled {
                                Button {
                                    appState.settings.incognitoModeEnabled = false
                                    toast = "已关闭无痕模式，恢复正常学习与记录"
                                } label: {
                                    LXTag(text: "无痕中", icon: "eye.slash.fill", tint: Color(Design.Palette.warning), filled: true)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("无痕模式已开启，点按退出")
                            }
                        }
                        let packName = CustomKeyboardLayoutPack.find(id: appState.settings.activeLayoutPackID)?.name ?? "自定义布局"
                        Text("\(appState.settings.inputScheme.displayName) · \(packName) · \(activePreset.name)")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    cloudPill
                }

                setupActions

                if let voiceMsg = appState.voiceEngineBannerMessage {
                    inlineStatus(voiceMsg)
                }

                if !AppGroup.isAvailable {
                    sideloadBanner
                }
            }
        }
    }

    private var statusTitle: String {
        switch setupState {
        case .notEnabled: return "尚未启用灵犀键盘"
        case .noFullAccess: return "键盘已启用 · 差一步"
        case .ready: return "灵犀键盘已就绪"
        }
    }

    private var cloudPill: some View {
        let online = appState.isCloudAuthenticated
        let tint = online ? Color(Design.Palette.success) : Color(Design.Palette.accent)
        return Button {
            openAccount()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: online ? "icloud.fill" : "person.crop.circle")
                Text(online ? "云端在线" : "登录")
            }
            .font(.caption.bold())
            .padding(.horizontal, 11)
            .frame(height: 32)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(online ? "云端账号在线" : "登录云端账号")
    }

    @ViewBuilder
    private var setupActions: some View {
        switch setupState {
        case .notEnabled:
            VStack(alignment: .leading, spacing: 10) {
                Text("在系统设置里添加「灵犀输入法」并允许完全访问，就能在任何 App 里使用。")
                    .font(.footnote)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        showGuide = true
                    } label: {
                        Label("查看教程", systemImage: "book")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))

                    Button {
                        appState.showPermissionsCenter = true
                    } label: {
                        Label("一键开启", systemImage: "lock.open.fill")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                }
            }

        case .noFullAccess:
            VStack(spacing: 10) {
                Button {
                    appState.showPermissionsCenter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(Design.Palette.warning))
                        Text("开启「允许完全访问」后才能用 AI、剪贴板和语音")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text("去开启")
                            .font(.caption.bold())
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(Design.Palette.warning), in: Capsule())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(Design.Palette.warning).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                voiceToggleRow
            }

        case .ready:
            HStack(spacing: 10) {
                Button {
                    appState.showPermissionsCenter = true
                } label: {
                    Label("权限中心", systemImage: "checkmark.shield")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.ink)))

                voiceToggleButton
            }
        }
    }

    /// 后台低延迟语音：一行说明 + 开关按钮（用于权限未全开时）
    private var voiceToggleRow: some View {
        HStack(spacing: 12) {
            LXIconTile(
                icon: bgVoice.isWarm ? "waveform" : "mic.fill",
                tint: bgVoice.isWarm ? Color(Design.Palette.success) : Color(Design.Palette.accent)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("后台低延迟语音")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(bgVoice.isWarm ? "已在后台保持，键盘里说话立即识别" : "保持后台待命，键盘语音免跳转")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button(bgVoice.isWarm ? "关闭" : "开启") {
                toggleBackgroundVoice()
            }
            .buttonStyle(LXCapsuleButtonStyle(prominent: !bgVoice.isWarm))
            .disabled(isTogglingVoice)
        }
    }

    private var voiceToggleButton: some View {
        Button {
            toggleBackgroundVoice()
        } label: {
            HStack(spacing: 6) {
                if isTogglingVoice {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: bgVoice.isWarm ? "waveform" : "mic.fill")
                }
                Text(bgVoice.isWarm ? "语音增强在线" : "开启后台语音")
            }
        }
        .buttonStyle(LXCapsuleButtonStyle(
            prominent: false,
            wide: true,
            tint: bgVoice.isWarm ? Color(Design.Palette.success) : Color(Design.Palette.accent)
        ))
        .disabled(isTogglingVoice)
        .accessibilityHint(bgVoice.isWarm ? "点按关闭后台语音保活" : "点按开启后台低延迟语音")
    }

    private func inlineStatus(_ message: String) -> some View {
        let ok = message.hasPrefix("✓") || message.hasPrefix("已")
        let clean = message.hasPrefix("✓")
            ? String(message.dropFirst()).trimmingCharacters(in: .whitespaces)
            : message
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.caption)
                .foregroundStyle(ok ? Color(Design.Palette.success) : Color(Design.Palette.warning))
            Text(clean)
                .font(.caption)
                .foregroundStyle(Color(Design.Palette.stone))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// 仅当检测到免费侧载被系统剥离 App Group 时展示一键同步（含 AI 密钥、外观、设置与字数）
    private var sideloadBanner: some View {
        Button {
            Task {
                isSyncingBridge = true
                defer { isSyncingBridge = false }
                let res = await appState.copySideloadBridgeTokenAndSync()
                toast = res.message.hasPrefix("✓")
                    ? String(res.message.dropFirst()).trimmingCharacters(in: .whitespaces)
                    : res.message
            }
        } label: {
            HStack(spacing: 10) {
                Group {
                    if isSyncingBridge {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(Design.Palette.accent))
                    }
                }
                .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("免费侧载模式")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("改完 AI 密钥、外观或设置后，需要手动同步给键盘")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Text("同步")
                    .font(.caption.bold())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(Design.Palette.accent), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(Design.Palette.accentSoft), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSyncingBridge)
    }

    // MARK: - 2. 今日打字（实时联动键盘上屏计数）

    private var todayStatsCard: some View {
        let stats = appState.typingStatsSummary
        let profile = appState.habitProfile
        let todayCount = max(stats.todayChars, 0)
        let avgSpeed = max(stats.averageCharsPerMinute, profile.avgCPM)
        return Button {
            navigateToStats = true
        } label: {
            LXCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("今日打字")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Spacer()
                        HStack(spacing: 2) {
                            Text("详细统计")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.stone))
                    }
                    HStack(spacing: 0) {
                        statCell(value: todayCount.formatted(), unit: "字", label: "今日上屏")
                        statDivider
                        statCell(
                            value: avgSpeed > 0.5 ? String(format: "%.0f", avgSpeed) : "--",
                            unit: avgSpeed > 0.5 ? "字/分" : "",
                            label: "平均速率"
                        )
                        statDivider
                        statCell(value: "\(appState.cognitiveStats.vaultNoteCount)", unit: "篇", label: "AI 记忆")
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看详细打字统计")
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color(Design.Palette.hairline))
            .frame(width: 0.5, height: 32)
    }

    private func statCell(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(Design.Palette.stone))
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color(Design.Palette.stone))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. 快捷入口（2×2 呼吸感卡片，一屏直达核心能力）

    private var quickEntriesCard: some View {
        let activePreset = appState.theme.activePreset(isSystemDark: colorScheme == .dark)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                quickTile(
                    icon: "sparkles",
                    title: "AI 与记忆库",
                    detail: appState.settings.aiAutopilotMode.shortBadge,
                    tint: Color(Design.Palette.accent)
                ) {
                    selectTab(2)
                }
                quickTile(
                    icon: "paintbrush",
                    title: "键盘外观",
                    detail: activePreset.name
                ) {
                    selectTab(1)
                }
            }
            HStack(spacing: 10) {
                quickTile(
                    icon: "doc.on.clipboard",
                    title: "剪贴板",
                    detail: "\(appState.clipboardItems.count) 条"
                ) {
                    selectTab(3)
                }
                quickTile(
                    icon: "slider.horizontal.3",
                    title: "输入设置",
                    detail: appState.settings.inputScheme.shortBadge
                ) {
                    selectTab(4)
                }
            }
        }
    }

    private func quickTile(icon: String, title: String, detail: String, tint: Color = Color(Design.Palette.ink), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LXIconTile(icon: icon, tint: tint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(Design.Palette.canvas), in: RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                    .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. 极简试打区

    private var sandboxCard: some View {
        LXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("试打")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    if !sandboxText.isEmpty {
                        Text("\(sandboxText.count) 字")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    Spacer()
                    if !sandboxText.isEmpty {
                        Button("清空") {
                            sandboxText = ""
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(Design.Palette.stone))
                        .buttonStyle(.plain)
                    }
                    if isTestingFocused {
                        Button {
                            isTestingFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(Design.Palette.stone))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("收起键盘")
                    }
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $sandboxText)
                        .focused($isTestingFocused)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 16))
                        .padding(10)
                        .frame(minHeight: 130)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                                .stroke(isTestingFocused ? Color(Design.Palette.accent).opacity(0.55) : Color.clear, lineWidth: 1)
                        )
                        .onChange(of: sandboxText) { _ in
                            statsDebounceTask?.cancel()
                            statsDebounceTask = Task {
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    appState.reloadTypingStatsSummary()
                                }
                            }
                        }

                    if sandboxText.isEmpty {
                        Text("点此切到「灵犀输入法」试打…")
                            .font(.subheadline)
                            .foregroundStyle(Color(Design.Palette.muted))
                            .padding(.leading, 15)
                            .padding(.top, 18)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func openAccount() {
        if appState.isCloudAuthenticated {
            navigateToAccount = true
        } else {
            showSignInSheet = true
        }
    }

    private func selectTab(_ index: Int) {
        if let onSelectTab {
            onSelectTab(index)
        } else {
            appState.requestedTab = index
        }
    }

    @MainActor
    private func toggleBackgroundVoice() {
        if bgVoice.isWarm {
            bgVoice.shutdown()
            appState.voiceEngineBannerMessage = "已关闭后台语音保活"
        } else {
            isTogglingVoice = true
            Task {
                let res = await bgVoice.warmUp()
                await MainActor.run {
                    appState.voiceEngineBannerMessage = res.message
                    isTogglingVoice = false
                }
            }
        }
    }
}
