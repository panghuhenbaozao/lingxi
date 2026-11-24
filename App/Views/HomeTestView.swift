import SwiftUI
import UIKit

/// 极简首页工作台（v5.2）：一屏看清状态、今日字数统计与纯净试打区，告别重复入口与演示噪音。
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
    @State private var bridgeToast: String?
    @State private var isSyncingBridge = false
    @State private var statsDebounceTask: Task<Void, Never>?
    @FocusState private var isTestingFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    compactStatusCard
                    todayStatsCard
                    cleanSandboxCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 28)
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
            .onAppear {
                appState.reloadSharedThemeAndSettingsIfNeeded()
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

    // MARK: - 1. 顶部精简状态卡（键盘状态 · 云端在线 · 侧载跨进程同步灯）

    private var compactStatusCard: some View {
        let activePreset = appState.theme.activePreset(isSystemDark: colorScheme == .dark)
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(Design.Palette.accent))
                        .frame(width: 40, height: 40)
                    Image(systemName: appState.isKeyboardEnabled ? "checkmark.seal.fill" : "keyboard")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(appState.isKeyboardEnabled ? "灵犀键盘已就绪" : "尚未启用灵犀键盘")
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Circle()
                            .fill(appState.isKeyboardEnabled ? Color(Design.Palette.success) : Color.orange)
                            .frame(width: 7, height: 7)
                    }
                    Text("\(appState.settings.inputScheme.displayName) · \(activePreset.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    if appState.isCloudAuthenticated {
                        navigateToAccount = true
                    } else {
                        showSignInSheet = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.isCloudAuthenticated ? "icloud.fill" : "person.crop.circle")
                            .font(.caption.bold())
                        Text(appState.isCloudAuthenticated ? "云端在线" : "登录云端")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(
                        appState.isCloudAuthenticated
                            ? Color(Design.Palette.success).opacity(0.14)
                            : Color(Design.Palette.accentSoft)
                    )
                    .foregroundStyle(
                        appState.isCloudAuthenticated
                            ? Color(Design.Palette.success)
                            : Color(Design.Palette.accent)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if !appState.isKeyboardEnabled {
                HStack(spacing: 10) {
                    actionPill("开启教程", icon: "book", filled: false) { showGuide = true }
                    actionPill("一键开启权限", icon: "lock.open.fill", filled: true) {
                        appState.showPermissionsCenter = true
                    }
                }
            } else if !appState.isKeyboardFullAccessConfirmed {
                HStack(spacing: 8) {
                    actionPill("一键权限", icon: "checkmark.shield", filled: false) {
                        appState.showPermissionsCenter = true
                    }
                    actionPill(
                        bgVoice.isWarm ? "🟢 后台语音增强在线" : "🎙️ 后台低延迟语音",
                        icon: bgVoice.isWarm ? "waveform.circle.fill" : "mic.fill",
                        filled: false
                    ) {
                        if bgVoice.isWarm {
                            bgVoice.shutdown()
                            appState.voiceEngineBannerMessage = "已关闭后台语音保活"
                        } else {
                            Task {
                                let res = await bgVoice.warmUp()
                                appState.voiceEngineBannerMessage = res.message
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    actionPill("一键权限", icon: "checkmark.shield.fill", filled: false) {
                        appState.showPermissionsCenter = true
                    }
                    actionPill(
                        bgVoice.isWarm ? "🟢 后台语音增强在线" : "🎙️ 后台低延迟语音",
                        icon: bgVoice.isWarm ? "waveform.circle.fill" : "mic.fill",
                        filled: false
                    ) {
                        if bgVoice.isWarm {
                            bgVoice.shutdown()
                            appState.voiceEngineBannerMessage = "已关闭后台语音保活"
                        } else {
                            Task {
                                let res = await bgVoice.warmUp()
                                appState.voiceEngineBannerMessage = res.message
                            }
                        }
                    }
                }
            }

            if let voiceMsg = appState.voiceEngineBannerMessage {
                Text(voiceMsg)
                    .font(.caption2)
                    .foregroundStyle(voiceMsg.hasPrefix("✓") ? Color(Design.Palette.success) : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 仅当检测到免费侧载被系统剥离 App Group 时展示一键同步（含 AI 密钥、外观、设置与字数）
            if !AppGroup.isAvailable {
                Button {
                    Task {
                        isSyncingBridge = true
                        defer { isSyncingBridge = false }
                        let res = await appState.copySideloadBridgeTokenAndSync()
                        bridgeToast = res.message
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSyncingBridge {
                            ProgressView().scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                        Text("免费侧载沙盒隔离 · 点此一键同步 AI 密钥、外观与设置给键盘")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .lineLimit(2)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSyncingBridge)
            }

            if let toast = bridgeToast {
                Text(toast)
                    .font(.caption2)
                    .foregroundStyle(toast.hasPrefix("✓") ? Color(Design.Palette.success) : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 2. 今日打字 3 指标卡（实时联动键盘上屏计数）

    private var todayStatsCard: some View {
        let stats = appState.typingStatsSummary
        let profile = appState.habitProfile
        let todayCount = max(stats.todayChars, 0)
        let avgSpeed = max(stats.averageCharsPerMinute, profile.avgCPM)
        return Button {
            navigateToStats = true
        } label: {
            HStack(spacing: 0) {
                statCell(value: "\(todayCount)", unit: "字", label: "今日打字")
                Divider().frame(height: 30)
                statCell(
                    value: avgSpeed > 0.5 ? String(format: "%.0f", avgSpeed) : "--",
                    unit: avgSpeed > 0.5 ? "字/分" : "",
                    label: "平均速率"
                )
                Divider().frame(height: 30)
                statCell(value: "\(stats.streakDays)", unit: "天", label: "连续打卡")
            }
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statCell(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.ink))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. 纯净试打框（零广告、零演示按钮、专心试打）

    private var cleanSandboxCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("试打区")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))

                Spacer()

                Button {
                    appState.showVoiceTranslator = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.caption2.bold())
                        Text("语音互译")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(Design.Palette.accentSoft))
                    .foregroundStyle(Color(Design.Palette.accent))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if !sandboxText.isEmpty {
                    Text("\(sandboxText.count) 字")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        sandboxText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空试打区")
                }

                if isTestingFocused {
                    Button {
                        isTestingFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
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
                    .padding(12)
                    .frame(minHeight: 196)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    Text("点这里切出「灵犀输入法」试打，上方今日字数会实时更新。")
                        .font(.system(size: 14.5))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 17)
                        .padding(.top, 20)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionPill(_ title: String, icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(filled ? Color.white : Color(Design.Palette.ink))
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(filled ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
