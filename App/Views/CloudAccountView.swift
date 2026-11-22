import PhotosUI
import SwiftUI
import UIKit

/// Apple ID 风格「灵犀账号与云服务」管理页（原生 InsetGrouped 清晰分组，头像支持从相册更换）。
struct CloudAccountView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var showSignInSheet: Bool = false
    @State private var isWorking: Bool = false
    @State private var statusBanner: String?
    @State private var errorBanner: String?
    @State private var appliedRecIDs: Set<String> = []

    // 跨屏剪贴板接力 (6位码 + SSE)
    @State private var relayPairCode: String = ClipboardRelayConfig.load().pairCode
    @State private var relayDraftText: String = ""
    @State private var relayedItems: [RelayedClipboardItem] = []
    @State private var relayStreamTask: Task<Void, Never>?

    // 安全与自托管设置
    @State private var showServerDisclosure: Bool = false
    @State private var showSecuritySheet: Bool = false
    @State private var newPasswordForRotation: String = ""
    @State private var showDeleteAccountConfirm: Bool = false

    var body: some View {
        List {
            // 1. Apple Account 顶部居中头像与身份区
            Section {
                VStack(spacing: 12) {
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                        UserAvatarView(size: 86, showEditBadge: true)
                    }
                    .buttonStyle(.plain)

                    if appState.isCloudAuthenticated {
                        VStack(spacing: 6) {
                            TextField("输入个人昵称", text: $appState.cloudConfig.username)
                                .multilineTextAlignment(.center)
                                .font(.title2.bold())
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text(appState.cloudConfig.email.isEmpty ? "API Key 已连接 · 零知识同步就绪" : appState.cloudConfig.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if appState.cloudConfig.isLocalOnlyAccount {
                                Text("本机加密账号 · 无需服务器即可使用，接入自建服务端可随时云同步")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(Design.Palette.surface))
                                    .clipShape(Capsule())
                            }

                            // 6 组苹果风格字母头像色盘快速切换
                            if appState.userAvatarImage == nil {
                                HStack(spacing: 10) {
                                    ForEach(Array(UserAvatarView.avatarGradients.enumerated()), id: \.offset) { idx, item in
                                        Button {
                                            appState.cloudConfig.avatarThemeIndex = idx
                                        } label: {
                                            Circle()
                                                .fill(Color(hexColor: HexColor(item.top)))
                                                .frame(width: 20, height: 20)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color(Design.Palette.ink), lineWidth: appState.cloudConfig.avatarThemeIndex == idx ? 2 : 0)
                                                        .padding(-2)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    } else {
                        VStack(spacing: 6) {
                            Text("未登录灵犀账号")
                                .font(.title3.bold())
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text("登录以开启端到端零知识同步；未登录不影响本地全功能免费使用。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                showSignInSheet = true
                            } label: {
                                Text("登录或创建灵犀账号")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 10)
                                    .background(Color(Design.Palette.ink))
                                    .foregroundStyle(Color(Design.Palette.canvas))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }

                    if appState.userAvatarImage != nil {
                        Button("移除自定义头像", role: .destructive) {
                            appState.removeUserAvatarImage()
                        }
                        .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }

            if let status = statusBanner {
                Section {
                    Label(status, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.success))
                }
            }
            if let err = errorBanner {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.error))
                }
            }

            // 2. 端到端云同步（iCloud 风格清晰列表）
            Section {
                Toggle("变更时自动后台加密同步", isOn: $appState.cloudConfig.autoSyncEnabled)
                LabeledContent("个人自造词库", value: "\(appState.userWords.count) 条")
                LabeledContent("自定义编码短语", value: "\(appState.customWords.count) 条")
                LabeledContent("常用快捷短语", value: "\(appState.quickPhrases.count) 条")
                LabeledContent("输入方案与布局", value: "\(appState.settings.inputScheme.displayName) · \(appState.settings.layoutMode.displayName)")
                LabeledContent("键盘外观主题", value: appState.theme.appearanceMode.displayName)

                Button {
                    Task { await triggerSyncNow() }
                } label: {
                    HStack {
                        Label(isWorking ? "正在同步…" : "立即端到端同步", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if !appState.cloudConfig.lastSyncSummary.isEmpty {
                            Text(appState.cloudConfig.lastSyncSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .disabled(isWorking)
            } header: {
                Text("端到端零知识同步 (E2EE · LXE1)")
            } footer: {
                Text("词库、短语、设置与皮肤在端侧经 ChaCha20-Poly1305 / AES-256-GCM 加密后上传，服务端数学上无法解密您的内容。")
            }

            // 3. 跨设备 6 位匹配码实时剪贴板接力 (SSE)
            Section {
                HStack {
                    Text("6 位跨屏匹配码")
                    Spacer()
                    TextField("886699", text: $relayPairCode)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .frame(width: 90)
                    Button("换码") {
                        relayPairCode = ClipboardRelayService.generateSixDigitCode()
                        var cfg = ClipboardRelayConfig.load()
                        cfg.pairCode = relayPairCode
                        cfg.save()
                        startSSEStream()
                    }
                    .font(.caption.bold())
                }

                HStack(spacing: 8) {
                    TextField("输入要秒传到电脑/另一台设备的文字或验证码…", text: $relayDraftText)
                        .font(.subheadline)
                    Button("秒传") {
                        Task { await pushRelayItem() }
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(Color(Design.Palette.ink))
                }

                Button("立即拉取跨屏剪贴板与验证码") {
                    Task { await pullRelayItems() }
                }

                if let latest = relayedItems.first {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("最新跨屏 (\(latest.senderDevice))")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            if let otp = latest.extractedCode {
                                Text("验证码 \(otp)")
                                    .font(.caption2.bold().monospacedDigit())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(Design.Palette.ink))
                                    .foregroundStyle(Color(Design.Palette.canvas))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(latest.contentText)
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("跨设备实时剪贴板接力 (SSE 毫秒推流)")
            } footer: {
                Text("在电脑浏览器打开 Web 控制台 (\(appState.cloudConfig.normalizedBaseURL)/dashboard) 输入相同 6 位匹配码即可免登录双向秒传。")
            }

            // 4. 实时打字习惯画像与隐私授权（独立开关，默认关闭）
            Section {
                Toggle("开启脱敏打字习惯与 API 实时分析", isOn: $appState.cloudConfig.habitAnalysisEnabled)
                    .onChange(of: appState.cloudConfig.habitAnalysisEnabled) { granted in
                        Task {
                            await CloudBackendClient.shared.syncConsentToServer(scope: "typing_analytics", granted: granted)
                        }
                    }

                let p = appState.habitProfile
                LabeledContent("平均 / 峰值速率", value: String(format: "%.0f / %.0f 字/分", p.avgCPM, p.peakCPM))
                LabeledContent("个人词库主领域", value: p.domainAffinity.primaryDomain)

                if !p.tuningRecommendations.isEmpty {
                    ForEach(p.tuningRecommendations) { rec in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.title).font(.subheadline.weight(.medium))
                                Text(rec.reason).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(appliedRecIDs.contains(rec.id) ? "已应用" : "应用") {
                                appState.applyTuningRecommendation(rec)
                                appliedRecIDs.insert(rec.id)
                                statusBanner = "已应用引擎调优：\(rec.title)"
                            }
                            .font(.caption.bold())
                            .disabled(appliedRecIDs.contains(rec.id))
                        }
                    }
                }

                Button("清除云端与本机全部习惯画像数据", role: .destructive) {
                    Task {
                        await appState.clearAllHabitAnalytics()
                        statusBanner = "已物理清除云端与本地全部习惯画像数据"
                    }
                }
            } header: {
                Text("打字习惯画像分析（默认关闭 · 零原文）")
            }

            // 5. 安全、API Key、自托管与 GDPR 合规
            Section {
                if appState.isCloudAuthenticated {
                    HStack {
                        Label("专属 API Key", systemImage: "key.fill")
                        Spacer()
                        Text(appState.cloudConfig.apiKeyPrefix.isEmpty ? "已绑定" : appState.cloudConfig.apiKeyPrefix)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Button("复制完整 API Key") {
                        if !appState.activeCustomerAPIKey.isEmpty {
                            UIPasteboard.general.string = appState.activeCustomerAPIKey
                            statusBanner = "已复制 API Key 到剪贴板"
                        }
                    }
                    Button("轮换并重新签发 API Key") {
                        Task { await rotateAPIKey() }
                    }
                    Button("修改密码并全量轮换 E2EE 密钥") {
                        showSecuritySheet = true
                    }
                }

                Button("导出我的全部数据 (GDPR / 个保法 JSON)") {
                    let json = ComplianceService.shared.exportAllPortableDataJSON()
                    UIPasteboard.general.string = json
                    statusBanner = "已导出完整可携带数据包 (\(json.count) 字节) 到剪贴板"
                }

                DisclosureGroup("自托管服务器与 Web 控制台", isExpanded: $showServerDisclosure) {
                    TextField("云端地址 (默认 Cloudflare 全球云)", text: $appState.cloudConfig.serverBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(size: 13.5, design: .monospaced))
                    HStack {
                        Button("测试连通性") {
                            Task { await checkHealth() }
                        }
                        Spacer()
                        Button("复制控制台网址") {
                            UIPasteboard.general.string = appState.cloudConfig.normalizedBaseURL + "/dashboard"
                            statusBanner = "已复制：\(appState.cloudConfig.normalizedBaseURL)/dashboard"
                        }
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("安全、合规与自托管网关")
            }

            // 6. 退出与注销（对齐 Apple ID 底部红色退出区）
            if appState.isCloudAuthenticated {
                Section {
                    Button("退出登录", role: .destructive) {
                        Task {
                            await appState.signOutCloudAccount()
                            statusBanner = "已退出云端账号，本机离线词库完好保留"
                        }
                    }
                    Button("永久注销云端账号并删除所有数据", role: .destructive) {
                        showDeleteAccountConfirm = true
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("灵犀账号")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSignInSheet) {
            AppleStyleSignInSheet()
        }
        .sheet(isPresented: $showSecuritySheet) {
            passwordRotationSheet
        }
        .onChange(of: selectedAvatarItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        appState.saveUserAvatarImage(uiImage)
                        statusBanner = "✓ 已更新个人头像"
                    }
                }
            }
        }
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
            Text("将在服务端级联物理删除您的账号、全部 E2EE 密文同步库、会话与习惯画像，无法恢复。本机离线词库不受影响。")
        }
    }

    private var passwordRotationSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("输入新密码（至少 8 位）", text: $newPasswordForRotation)
                } header: {
                    Text("设置新密码")
                } footer: {
                    Text("修改密码后将自动在服务端轮换 E2EE 盐，并在端侧使用新密钥全量重加密您的词库与设置。")
                }
                Section {
                    Button("确认修改并重加密") {
                        Task {
                            await performPasswordAndKeyRotation()
                            showSecuritySheet = false
                        }
                    }
                    .disabled(isWorking || newPasswordForRotation.count < 8)
                }
            }
            .navigationTitle("密码与 E2EE 密钥轮换")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showSecuritySheet = false }
                }
            }
        }
    }

    // MARK: - 交互逻辑

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
                UIPasteboard.general.string = top.contentText
                statusBanner = "已接力跨屏内容（切出键盘即可一键粘贴）：\(top.contentText)"
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
            statusBanner = "后端服务在线 (v\(ver)) · 可随时登录或使用跨屏剪贴板"
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    private func rotateAPIKey() async {
        isWorking = true
        errorBanner = nil
        defer { isWorking = false }
        do {
            let newKey = try await appState.rotateCloudAPIKey()
            statusBanner = "已签发新 API Key：\(String(newKey.prefix(16)))..."
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
            statusBanner = "同步完成：推送 \(report.pushed) 项 · 拉取 \(report.pulled) 项 · 应用 \(report.applied) 项"
        } catch {
            errorBanner = error.localizedDescription
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
            statusBanner = "✓ 密码已更新，已完成 E2EE 新盐密钥轮换与全量重加密同步"
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
            statusBanner = "✓ 云端账号及全部服务端数据已级联物理删除（本机词库完好保留）"
        } catch {
            errorBanner = error.localizedDescription
        }
    }
}
