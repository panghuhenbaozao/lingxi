import AuthenticationServices
import SwiftUI
import UIKit

/// 云端账号、跨屏剪贴板接力、重要数据 LWW+E2EE 同步、API 实时打字习惯画像与 GDPR/个保法合规中心。
struct CloudAccountView: View {
    @EnvironmentObject private var appState: AppState

    private enum AuthTab: String, CaseIterable, Identifiable {
        case login = "账号登录"
        case register = "注册账号"
        case apiKey = "API Key 接入"
        var id: String { rawValue }
    }

    @State private var authTab: AuthTab = .login
    @State private var emailInput: String = ""
    @State private var usernameInput: String = ""
    @State private var passwordInput: String = ""
    @State private var apiKeyInput: String = ""

    @State private var isWorking: Bool = false
    @State private var statusBanner: String?
    @State private var errorBanner: String?
    @State private var appliedRecIDs: Set<String> = []
    @State private var relayPairCode: String = ClipboardRelayConfig.load().pairCode
    @State private var relayDraftText: String = ""
    @State private var relayedItems: [RelayedClipboardItem] = []
    @State private var relayStreamTask: Task<Void, Never>?
    @State private var newPasswordForRotation: String = ""
    @State private var showDeleteAccountConfirm: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                serverGatewayCard
                crossDeviceRelayCard
                accountAuthCard
                importantDataSyncCard
                typingHabitPortraitCard
                gdprComplianceCard
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.md)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("云端账号与习惯画像")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await appState.refreshHabitProfile()
            relayedItems = (try? await ClipboardRelayService.shared.pullLatest(pairCode: relayPairCode)) ?? []
            startSSEStream()
        }
        .onDisappear {
            relayStreamTask?.cancel()
            relayStreamTask = nil
        }
        .alert("永久注销云端账号？", isPresented: $showDeleteAccountConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认注销并物理删除", role: .destructive) {
                Task { await performCascadeAccountDeletion() }
            }
        } message: {
            Text("此操作将在服务器端级联物理删除您的账号、全部 E2EE 同步密文、设备会话与习惯画像，且无法恢复。您的本机离线词库不受影响。")
        }
    }

    // MARK: - 1. 后端服务器与 Web 控制台网关卡片

    private var serverGatewayCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack {
                Label("后端服务器与 Web 控制台网关", systemImage: "server.rack")
                    .font(Design.Typography.SwiftUIFont.h3)
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Button {
                    Task { await checkHealth() }
                } label: {
                    Text(isWorking ? "检测中…" : "测试连通")
                        .font(Design.Typography.SwiftUIFont.caption)
                        .foregroundStyle(Color(Design.Palette.ink))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(Design.Palette.surface))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 1))
                }
                .disabled(isWorking)
            }

            TextField("后端地址 (如 http://127.0.0.1:8787)", text: $appState.cloudConfig.serverBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .background(Color(Design.Palette.surface))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.input)
                        .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                )

            if let status = statusBanner {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(Design.Palette.success))
                    Text(status)
                        .font(Design.Typography.SwiftUIFont.caption)
                        .foregroundStyle(Color(Design.Palette.ink))
                }
            }
            if let err = errorBanner {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(Design.Palette.error))
                    Text(err)
                        .font(Design.Typography.SwiftUIFont.caption)
                        .foregroundStyle(Color(Design.Palette.error))
                }
            }
        }
        .padding(Design.Spacing.md)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    // MARK: - 1.5 跨设备实时剪贴板接力 (6 位匹配码免登录秒传，对标微信输入法)

    private var crossDeviceRelayCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack {
                Label("跨设备剪贴板接力 (6 位码免登录秒传)", systemImage: "laptopcomputer.and.iphone")
                    .font(Design.Typography.SwiftUIFont.h3)
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Button("换个匹配码") {
                    relayPairCode = ClipboardRelayService.generateSixDigitCode()
                    var cfg = ClipboardRelayConfig.load()
                    cfg.pairCode = relayPairCode
                    cfg.save()
                    startSSEStream()
                }
                .font(Design.Typography.SwiftUIFont.caption)
                .foregroundStyle(Color(Design.Palette.stone))
            }

            Text("在电脑浏览器打开 Web 控制台 (\(appState.cloudConfig.normalizedBaseURL)/dashboard) 输入相同 6 位匹配码，电脑复制的文本或验证码将秒传到手机键盘顶部全宽胶囊。")
                .font(Design.Typography.SwiftUIFont.caption)
                .foregroundStyle(Color(Design.Palette.stone))

            HStack(spacing: 8) {
                TextField("6位匹配码", text: $relayPairCode)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .frame(width: 96)
                    .padding(9)
                    .background(Color(Design.Palette.surface))
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input))

                TextField("输入要跨屏秒传的文字或验证码…", text: $relayDraftText)
                    .font(Design.Typography.SwiftUIFont.body)
                    .padding(9)
                    .background(Color(Design.Palette.surface))
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input))

                Button("秒传") {
                    Task { await pushRelayItem() }
                }
                .font(Design.Typography.SwiftUIFont.label)
                .foregroundStyle(Color(Design.Palette.canvas))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(Design.Palette.ink))
                .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                Button("拉取跨屏剪贴板与验证码") {
                    Task { await pullRelayItems() }
                }
                .font(Design.Typography.SwiftUIFont.caption)
                .foregroundStyle(Color(Design.Palette.ink))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color(Design.Palette.surface))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 1))

                Button("复制 Web 控制台地址") {
                    UIPasteboard.general.string = appState.cloudConfig.normalizedBaseURL + "/dashboard"
                    statusBanner = "已复制 Web 控制台地址：\(appState.cloudConfig.normalizedBaseURL)/dashboard"
                }
                .font(Design.Typography.SwiftUIFont.caption)
                .foregroundStyle(Color(Design.Palette.stone))
            }

            if let latest = relayedItems.first {
                HStack(spacing: 6) {
                    if let otp = latest.extractedCode {
                        Text("验证码 \(otp)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(Design.Palette.canvas))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(Design.Palette.ink))
                            .clipShape(Capsule())
                    }
                    Text("最新跨屏 (\(latest.senderDevice))：\(latest.contentText)")
                        .font(Design.Typography.SwiftUIFont.caption)
                        .foregroundStyle(Color(Design.Palette.ink))
                        .lineLimit(1)
                }
                .padding(8)
                .background(Color(Design.Palette.surface))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input))
            }
        }
        .padding(Design.Spacing.md)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    // MARK: - 2. 账号认证与客户 API Key 卡片

    private var accountAuthCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack {
                Label("账号登录与 API Key 凭证", systemImage: "person.badge.key.fill")
                    .font(Design.Typography.SwiftUIFont.h3)
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Text(appState.isCloudAuthenticated ? "已连接云端" : "离线本地态")
                    .font(Design.Typography.SwiftUIFont.caption)
                    .foregroundStyle(appState.isCloudAuthenticated ? Color(Design.Palette.success) : Color(Design.Palette.stone))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(Design.Palette.surface))
                    .clipShape(Capsule())
            }

            if appState.isCloudAuthenticated {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(appState.cloudConfig.username.isEmpty ? "API Key 接入客户" : appState.cloudConfig.username)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            if !appState.cloudConfig.email.isEmpty {
                                Text(appState.cloudConfig.email)
                                    .font(Design.Typography.SwiftUIFont.caption)
                                    .foregroundStyle(Color(Design.Palette.stone))
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task {
                                await appState.signOutCloudAccount()
                                statusBanner = "已退出云端账号，本地数据完整保留"
                            }
                        } label: {
                            Text("退出登录")
                                .font(Design.Typography.SwiftUIFont.caption)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("客户专属 API Key（含 L3 HMAC-SHA256 5分钟防重放签名）")
                            .font(Design.Typography.SwiftUIFont.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                        HStack(spacing: 8) {
                            Text(appState.activeCustomerAPIKey.isEmpty ? (appState.cloudConfig.apiKeyPrefix.isEmpty ? "lx_live_••••••••" : appState.cloudConfig.apiKeyPrefix) : appState.activeCustomerAPIKey)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .lineLimit(1)
                            Spacer()
                            if !appState.activeCustomerAPIKey.isEmpty {
                                Button("复制") {
                                    UIPasteboard.general.string = appState.activeCustomerAPIKey
                                    statusBanner = "已复制专属 API Key 到剪贴板"
                                }
                                .font(Design.Typography.SwiftUIFont.caption)
                            }
                            Button("轮换密钥") {
                                Task { await rotateAPIKey() }
                            }
                            .font(Design.Typography.SwiftUIFont.caption)
                        }
                        .padding(9)
                        .background(Color(Design.Palette.surface))
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input))
                    }
                }
            } else {
                Picker("认证方式", selection: $authTab) {
                    ForEach(AuthTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if authTab == .apiKey {
                    TextField("输入客户 API Key (lx_live_...)", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                        .padding(10)
                        .background(Color(Design.Palette.surface))
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input))

                    Button {
                        Task { await submitAuth() }
                    } label: {
                        Text("接入 API 并启动实时打字习惯分析")
                            .font(Design.Typography.SwiftUIFont.label)
                            .foregroundStyle(Color(Design.Palette.canvas))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color(Design.Palette.ink))
                            .clipShape(Capsule())
                    }
                    .disabled(isWorking)
                } else {
                    TextField(authTab == .register ? "邮箱地址 (如 user@lingxi.im)" : "邮箱或用户名", text: $emailInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .font(Design.Typography.SwiftUIFont.body)
                        .padding(10)
                        .background(Color(Design.Palette.surface))
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input))

                    if authTab == .register {
                        TextField("昵称 / 用户名", text: $usernameInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(Design.Typography.SwiftUIFont.body)
                            .padding(10)
                            .background(Color(Design.Palette.surface))
                            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input))
                    }

                    SecureField("密码（至少 6 位）", text: $passwordInput)
                        .font(Design.Typography.SwiftUIFont.body)
                        .padding(10)
                        .background(Color(Design.Palette.surface))
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input))

                    Button {
                        Task { await submitAuth() }
                    } label: {
                        Text(authTab == .register ? "注册账号并签发专属 API Key" : "登录并同步重要数据")
                            .font(Design.Typography.SwiftUIFont.label)
                            .foregroundStyle(Color(Design.Palette.canvas))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color(Design.Palette.ink))
                            .clipShape(Capsule())
                    }
                    .disabled(isWorking)

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task { await handleAppleSignIn(result) }
                    }
                    .frame(height: 42)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(Design.Spacing.md)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    // MARK: - 3. 重要数据云端同步中心 (Vaultwarden / Atuin LWW + E2EE)

    private var importantDataSyncCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack {
                Label("重要数据云同步 (LWW + E2EE)", systemImage: "icloud.and.arrow.up.fill")
                    .font(Design.Typography.SwiftUIFont.h3)
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Text("Lamport #\(LamportClock.shared.value)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(Design.Palette.stone))
            }

            Text("参考 Vaultwarden 与 Atuin 架构，通过版本向量 + LWW 全序决胜 + 零知识端到端加密将以下 7 类核心资产自动同步至服务器数据库：")
                .font(Design.Typography.SwiftUIFont.caption)
                .foregroundStyle(Color(Design.Palette.stone))

            Toggle("数据变更与回到前台时自动无感同步", isOn: $appState.cloudConfig.autoSyncEnabled)
                .font(Design.Typography.SwiftUIFont.caption)

            VStack(spacing: 8) {
                vaultItemRow(icon: "book.closed.fill", title: "个人自学习词库 (user_dict)", detail: "\(appState.userWords.count) 条个人词条与置顶")
                vaultItemRow(icon: "text.badge.plus", title: "自定义编码短语 (custom.tsv)", detail: "\(appState.customWords.count) 条快捷编码")
                vaultItemRow(icon: "quote.bubble.fill", title: "常用快捷回复短语", detail: "\(appState.quickPhrases.count) 条常用模板")
                vaultItemRow(icon: "slider.horizontal.3", title: "输入方案与全局设置", detail: "\(appState.settings.inputScheme.displayName) · \(appState.settings.layoutMode.displayName)")
                vaultItemRow(icon: "paintpalette.fill", title: "键盘皮肤与主题配置", detail: "亮色 \(appState.theme.selectedThemeID) / 暗色 \(appState.theme.darkThemeID)")
                vaultItemRow(icon: "chart.bar.fill", title: "400天打字统计与常用表情权重", detail: "累计 \(TypingStatsStore.shared.summary().totalChars) 字")
            }

            if !appState.cloudConfig.lastSyncSummary.isEmpty {
                Text("最近同步：\(appState.cloudConfig.lastSyncSummary)")
                    .font(Design.Typography.SwiftUIFont.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            }

            Button {
                Task { await triggerSyncNow() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(isWorking ? "正在同步服务器数据…" : "立即同步全部重要数据到服务器")
                }
                .font(Design.Typography.SwiftUIFont.label)
                .foregroundStyle(Color(Design.Palette.canvas))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color(Design.Palette.ink))
                .clipShape(Capsule())
            }
            .disabled(isWorking)
        }
        .padding(Design.Spacing.md)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    private func vaultItemRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.ink))
                .frame(width: 26, height: 26)
                .background(Color(Design.Palette.surface))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(Design.Typography.SwiftUIFont.body)
                .foregroundStyle(Color(Design.Palette.ink))
            Spacer()
            Text(detail)
                .font(Design.Typography.SwiftUIFont.caption)
                .foregroundStyle(Color(Design.Palette.stone))
        }
        .padding(.vertical, 4)
    }

    // MARK: - 4. API 实时打字习惯画像与智能调优卡片 (Wakapi 架构)

    private var typingHabitPortraitCard: some View {
        let p = appState.habitProfile
        return VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack {
                Label("打字习惯实时画像与 API 分析", systemImage: "waveform.path.ecg.rectangle")
                    .font(Design.Typography.SwiftUIFont.h3)
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Button("模拟采样并分析") {
                    Task { await simulateAndAnalyzeHabitSample() }
                }
                .font(Design.Typography.SwiftUIFont.caption)
                .foregroundStyle(Color(Design.Palette.ink))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(Design.Palette.surface))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 1))
            }

            Toggle("独立授权：允许分析聚合打字习惯（与同步物理分离，永不含输入原文）", isOn: $appState.cloudConfig.habitAnalysisEnabled)
                .font(Design.Typography.SwiftUIFont.caption)
                .onChange(of: appState.cloudConfig.habitAnalysisEnabled) { granted in
                    _ = ComplianceService.shared.recordConsent(scope: "typing_analytics", granted: granted)
                }

            if !p.habitTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(p.habitTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(Design.Palette.ink).opacity(0.08))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color(Design.Palette.ink).opacity(0.20), lineWidth: 0.5))
                        }
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                habitMetricTile(
                    title: "平均 / 峰值速率",
                    value: String(format: "%.0f / %.0f", p.avgCPM, p.peakCPM),
                    unit: "字/分 (CPM)"
                )
                habitMetricTile(
                    title: "平均上屏词长",
                    value: String(format: "%.2f", p.avgWordLength),
                    unit: "字/词 (\(p.totalWords) 词)"
                )
                habitMetricTile(
                    title: "退格纠错 / 撤学率",
                    value: String(format: "%.1f%% / %.1f%%", p.backspaceRate * 100, p.undoLearnRate * 100),
                    unit: "准确率诊断"
                )
                habitMetricTile(
                    title: "滑行输入占比",
                    value: String(format: "%.1f%%", p.glideRatio * 100),
                    unit: "主方案 \(InputScheme(rawValue: p.primaryScheme)?.shortBadge ?? "全拼")"
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("24 小时打字活跃节律分布")
                    .font(Design.Typography.SwiftUIFont.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                hourlyRhythmBarChart(rhythm: p.hourlyRhythm)
            }
            .padding(10)
            .background(Color(Design.Palette.surface))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.cardSmall))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("拼音易混音热力诊断 & 个人词库领域画像")
                        .font(Design.Typography.SwiftUIFont.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                    Spacer()
                    Text("主领域：\(p.domainAffinity.primaryDomain)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                }

                if !p.confusionMatrix.isEmpty {
                    let confText = p.confusionMatrix
                        .sorted(by: { $0.value > $1.value })
                        .map { "\($0.key.replacingOccurrences(of: "_", with: "↔")): \($0.value)次" }
                        .joined(separator: "  ·  ")
                    Text("易混音热力：\(confText)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Color(Design.Palette.ink))
                } else {
                    Text("易混音热力：暂无明显平翘舌/前后鼻音混淆")
                        .font(Design.Typography.SwiftUIFont.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                }

                if !p.domainAffinity.topTerms.isEmpty {
                    Text("AI 自动记忆高频词：\(p.domainAffinity.topTerms.prefix(6).joined(separator: "、"))")
                        .font(Design.Typography.SwiftUIFont.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(Color(Design.Palette.surface))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.cardSmall))

            if !p.aiFeatureBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI 与实时互译 API 使用习惯")
                        .font(Design.Typography.SwiftUIFont.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                    ForEach(p.aiFeatureBreakdown.keys.sorted(), id: \.self) { key in
                        if let stat = p.aiFeatureBreakdown[key] {
                            HStack {
                                Text(displayNameForAIFeature(key))
                                    .font(Design.Typography.SwiftUIFont.caption)
                                    .foregroundStyle(Color(Design.Palette.ink))
                                Spacer()
                                Text("\(stat.calls) 次 · 吞吐 \(stat.inputChars + stat.outputChars) 字 · 均耗 \(stat.avgLatencyMs)ms")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color(Design.Palette.stone))
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(Design.Palette.surface))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.cardSmall))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("基于您的打字习惯生成的引擎调优建议")
                    .font(Design.Typography.SwiftUIFont.label)
                    .foregroundStyle(Color(Design.Palette.ink))

                ForEach(p.tuningRecommendations) { rec in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rec.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text(rec.reason)
                                .font(Design.Typography.SwiftUIFont.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                        Spacer(minLength: 4)
                        Button {
                            appState.applyTuningRecommendation(rec)
                            appliedRecIDs.insert(rec.id)
                            statusBanner = "已应用调优建议：\(rec.title)"
                        } label: {
                            Text(appliedRecIDs.contains(rec.id) ? "已应用" : "一键优化")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(appliedRecIDs.contains(rec.id) ? Color(Design.Palette.stone) : Color(Design.Palette.canvas))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(appliedRecIDs.contains(rec.id) ? Color(Design.Palette.surface) : Color(Design.Palette.ink))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(10)
                    .background(Color(Design.Palette.surface))
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.cardSmall))
                }
            }

            HStack {
                Button(role: .destructive) {
                    Task {
                        await appState.clearAllHabitAnalytics()
                        statusBanner = "已物理清除云端与本地全部打字习惯画像数据"
                    }
                } label: {
                    Text("一键撤回并物理删除习惯数据")
                        .font(Design.Typography.SwiftUIFont.caption)
                }
                Spacer()
                Text("累计样本 \(p.totalSessions) 会话 / \(p.totalChars) 字")
                    .font(Design.Typography.SwiftUIFont.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            }
        }
        .padding(Design.Spacing.md)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    // MARK: - 5. 个保法 / GDPR 双合规卡片 (数据可携带导出 + 不可变授权流水)

    private var gdprComplianceCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack {
                Label("隐私合规与数据可携带权 (个保法 / GDPR)", systemImage: "checkmark.shield.fill")
                    .font(Design.Typography.SwiftUIFont.h3)
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Text("Policy 2026.11-v1")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(Design.Palette.stone))
            }

            Text("遵循『默认零收集、同步与分析物理分离、授权不可变审计留痕』。您可随时导出全部个人数据（含明文设置/词库 + 云同步密文账本 + 授权流水 + 习惯聚合 JSON）。")
                .font(Design.Typography.SwiftUIFont.caption)
                .foregroundStyle(Color(Design.Palette.stone))

            Button {
                let json = ComplianceService.shared.exportAllPortableDataJSON()
                UIPasteboard.general.string = json
                statusBanner = "已导出完整 GDPR/个保法可携带数据包 (\(json.count) 字节) 到剪贴板"
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("导出我的全部数据 (明文 + 密文双份 JSON)")
                }
                .font(Design.Typography.SwiftUIFont.label)
                .foregroundStyle(Color(Design.Palette.ink))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(Design.Palette.surface))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(Design.Palette.hairline), lineWidth: 1))
            }

            if appState.isCloudAuthenticated {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("L2 密钥学 · 修改密码并全量轮换 E2EE 密钥")
                        .font(Design.Typography.SwiftUIFont.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                    HStack(spacing: 8) {
                        SecureField("输入新密码（至少 8 位）", text: $newPasswordForRotation)
                            .font(Design.Typography.SwiftUIFont.body)
                            .padding(9)
                            .background(Color(Design.Palette.surface))
                            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.input))
                        Button("轮换重加密") {
                            Task { await performPasswordAndKeyRotation() }
                        }
                        .font(Design.Typography.SwiftUIFont.caption)
                        .foregroundStyle(Color(Design.Palette.canvas))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(Design.Palette.ink))
                        .clipShape(Capsule())
                        .disabled(isWorking || newPasswordForRotation.count < 8)
                    }
                }

                Button(role: .destructive) {
                    showDeleteAccountConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                        Text("一键注销云端账号并级联物理删除全部云端数据")
                    }
                    .font(Design.Typography.SwiftUIFont.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(Design.Spacing.md)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    private func habitMetricTile(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Design.Typography.SwiftUIFont.caption)
                .foregroundStyle(Color(Design.Palette.stone))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(Design.Palette.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(unit)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(Design.Palette.stone))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(Design.Palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.cardSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.cardSmall)
                .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
        )
    }

    private func hourlyRhythmBarChart(rhythm: [String: Int]) -> some View {
        let maxVal = max(1, (0..<24).map { rhythm[String($0)] ?? 0 }.max() ?? 1)
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    let val = rhythm[String(hour)] ?? 0
                    let ratio = CGFloat(val) / CGFloat(maxVal)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(val > 0 ? Color(Design.Palette.ink) : Color(Design.Palette.hairline))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, 38 * ratio))
                }
            }
            .frame(height: 40)
            HStack {
                Text("00:00")
                Spacer()
                Text("06:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("18:00")
                Spacer()
                Text("23:00")
            }
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(Color(Design.Palette.stone))
        }
    }

    private func displayNameForAIFeature(_ key: String) -> String {
        switch key {
        case "live_translate": return "译 · 实时边打边译"
        case "ai_ask": return "灵犀 AI · 自由提问"
        case "polish", "ai_polish": return "灵犀 AI · 润色优化"
        case "replyClipboard", "ai_reply": return "灵犀 AI · 高情商回复"
        default: return "AI 助手 (\(key))"
        }
    }

    // MARK: - 交互逻辑

    private func pushRelayItem() async {
        isWorking = true
        errorBanner = nil
        defer { isWorking = false }
        let text = relayDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (UIPasteboard.general.string ?? "")
            : relayDraftText
        do {
            let item = try await ClipboardRelayService.shared.push(text: text, pairCode: relayPairCode, senderDevice: "iPhone")
            relayDraftText = ""
            relayedItems.insert(item, at: 0)
            appState.reloadClipboard()
            statusBanner = "已通过匹配码 \(relayPairCode) 秒传内容至跨屏通道"
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func pullRelayItems() async {
        isWorking = true
        errorBanner = nil
        defer { isWorking = false }
        do {
            let items = try await ClipboardRelayService.shared.pullLatest(pairCode: relayPairCode)
            relayedItems = items
            appState.reloadClipboard()
            if let top = items.first {
                statusBanner = "已拉取跨屏内容（切出键盘即可在顶栏全宽胶囊一键粘贴）：\(top.contentText)"
            } else {
                statusBanner = "当前匹配码 \(relayPairCode) 暂无新跨屏内容"
            }
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func checkHealth() async {
        isWorking = true
        errorBanner = nil
        defer { isWorking = false }
        do {
            let info = try await CloudBackendClient.shared.checkServerHealth()
            let ver = (info["version"] as? String) ?? "4.0"
            let users = (info["users"] as? NSNumber)?.intValue ?? 0
            let records = (info["syncRecords"] as? NSNumber)?.intValue ?? 0
            let events = (info["habitEvents"] as? NSNumber)?.intValue ?? 0
            statusBanner = "后端服务与 Web 控制台在线 (v\(ver)) · 用户 \(users) · 同步库 \(records) 项 · 习惯样本 \(events) 条"
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func submitAuth() async {
        isWorking = true
        errorBanner = nil
        statusBanner = nil
        defer { isWorking = false }
        do {
            switch authTab {
            case .login:
                try await appState.loginCloudAccount(account: emailInput, password: passwordInput)
                statusBanner = "登录成功，已完成重要数据与打字习惯同步"
            case .register:
                try await appState.registerCloudAccount(email: emailInput, username: usernameInput, password: passwordInput)
                statusBanner = "注册成功！已为您自动生成专属 API Key 并开启云同步"
            case .apiKey:
                try await appState.connectCustomerAPIKey(apiKeyInput)
                statusBanner = "API Key 接入成功，实时打字习惯分析已激活"
            }
            passwordInput = ""
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isWorking = true
        errorBanner = nil
        defer { isWorking = false }
        switch result {
        case .success(let auth):
            if let cred = auth.credential as? ASAuthorizationAppleIDCredential {
                let token = cred.identityToken ?? Data(cred.user.utf8)
                do {
                    try await appState.signInWithAppleAccount(identityToken: token, user: cred.user)
                    statusBanner = "Apple 账号登录成功，已开启端到端云同步"
                } catch {
                    errorBanner = error.localizedDescription
                }
            }
        case .failure(let err):
            errorBanner = err.localizedDescription
        }
    }

    private func rotateAPIKey() async {
        isWorking = true
        errorBanner = nil
        defer { isWorking = false }
        do {
            let newKey = try await appState.rotateCloudAPIKey()
            statusBanner = "已生成新 API Key：\(String(newKey.prefix(16)))..."
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func triggerSyncNow() async {
        isWorking = true
        errorBanner = nil
        defer { isWorking = false }
        do {
            let report = try await appState.syncCloudNow()
            statusBanner = "云同步完成：推送 \(report.pushed) 项 · 拉取 \(report.pulled) 项 · 应用 \(report.applied) 项"
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func simulateAndAnalyzeHabitSample() async {
        isWorking = true
        errorBanner = nil
        defer { isWorking = false }
        let sample = TypingHabitEventPayload(
            durationSeconds: 45,
            committedChars: 138,
            committedWords: 52,
            deleteCount: 15,
            undoLearnCount: 3,
            glideWords: 12,
            typoCorrectedCount: 5,
            aiInvocations: 2,
            translateChars: 36,
            schemeID: appState.settings.inputScheme.rawValue,
            layoutID: appState.settings.layoutMode.rawValue,
            confusionCounts: ["zh_z": 3, "an_ang": 2]
        )
        _ = TypingHabitTracker.shared.recordTypingEvent(sample)
        _ = TypingHabitTracker.shared.recordAIUsage(
            AIAPIUsagePayload(
                feature: "live_translate",
                provider: appState.aiConfig.provider.rawValue,
                targetLang: appState.settings.translateTargetLang,
                formalTone: appState.settings.translateFormalTone,
                inputChars: 36,
                outputChars: 72,
                latencyMs: 280
            )
        )
        await appState.refreshHabitProfile()
        statusBanner = appState.isCloudAuthenticated
            ? "已实时上报打字习惯与 API 数据至服务器并更新画像"
            : "已在本地完成打字习惯画像分析（登录或接入 API Key 后自动同步至服务器）"
    }

    private func startSSEStream() {
        relayStreamTask?.cancel()
        let code = relayPairCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        relayStreamTask = ClipboardRelayService.shared.subscribeRealtimeStream(pairCode: code) { items in
            self.relayedItems = items
            self.appState.reloadClipboard()
            if let newest = items.first {
                UIPasteboard.general.string = newest.contentText
                self.statusBanner = "⚡ 实时接力收到 (\(newest.senderDevice))：\(newest.contentText)"
            }
        }
    }

    private func performPasswordAndKeyRotation() async {
        isWorking = true
        errorBanner = nil
        defer { isWorking = false }
        do {
            _ = try await CloudBackendClient.shared.changePasswordAndRotateKey(newPassword: newPasswordForRotation)
            newPasswordForRotation = ""
            appState.refreshAll()
            statusBanner = "✓ 密码已更新，已完成 E2EE 新盐密钥轮换与全量密文重加密同步"
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func performCascadeAccountDeletion() async {
        isWorking = true
        errorBanner = nil
        defer { isWorking = false }
        do {
            try await CloudBackendClient.shared.deleteCloudAccountCascade()
            appState.refreshAll()
            statusBanner = "✓ 云端账号及全部服务端数据已级联物理删除（本机离线词库完好保留）"
        } catch {
            errorBanner = error.localizedDescription
        }
    }
}
