import PhotosUI
import SwiftUI
import UIKit

/// Apple ID 风格「灵犀账号与云服务」管理页（原生 InsetGrouped 清晰分组，10 类数据透明上云看板 + Apple Passkey/Face ID）。
struct CloudAccountView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var showSignInSheet: Bool = false
    @State private var isWorking: Bool = false
    @State private var statusBanner: String?
    @State private var errorBanner: String?
    @State private var appliedRecIDs: Set<String> = []
    @State private var showAllNamespaces: Bool = true

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

                            HStack(spacing: 6) {
                                Image(systemName: "icloud.fill")
                                    .font(.caption2)
                                Text("国内直连云端在线 · E2EE 端到端加密")
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(Color(Design.Palette.success))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(Design.Palette.success).opacity(0.12))
                            .clipShape(Capsule())

                            Text(CloudBackendClient.shared.lastActiveRouteDescription)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

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
                                                        .stroke(Color(Design.Palette.accent), lineWidth: appState.cloudConfig.avatarThemeIndex == idx ? 2 : 0)
                                                        .padding(-2)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    } else if appState.isLocalOfflineAccount {
                        VStack(spacing: 8) {
                            Text(appState.cloudConfig.username.isEmpty ? "本机离线档案" : appState.cloudConfig.username)
                                .font(.title3.bold())
                                .foregroundStyle(Color(Design.Palette.ink))
                            HStack(spacing: 6) {
                                Image(systemName: "iphone")
                                    .font(.caption2)
                                Text("当前为旧版/纯本机离线档案，尚未连接云端")
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())

                            Button {
                                showSignInSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "icloud.and.arrow.up.fill")
                                    Text("立即免代理登录国内云端")
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color(Design.Palette.accent))
                                .foregroundStyle(Color.white)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Text("未登录灵犀云端账号")
                                .font(.title3.bold())
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text("国内免代理直连云端（支持面容 ID 免密、Apple 通行密钥与邮箱），端到端加密同步 10 类核心数据。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                showSignInSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "apple.logo")
                                    Text("免代理登录国内云端")
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color(Design.Palette.accent))
                                .foregroundStyle(Color.white)
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

            // 2. 10 类核心数据云端同步透明看板
            Section {
                Toggle("数据变化时自动加密传回云端", isOn: $appState.cloudConfig.autoSyncEnabled)

                let summaries = CloudBackendClient.shared.syncNamespaceDashboardSummary()
                let syncedCount = summaries.filter(\.isSynced).count

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已加密上云进度：\(syncedCount) / \(summaries.count) 类核心数据")
                            .font(.subheadline.bold())
                        if let lastAt = appState.cloudConfig.lastSyncedAt {
                            Text("最近同步：\(lastAt, style: .relative)前 · \(appState.cloudConfig.lastSyncSummary)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("登录后点下方按钮即可将 10 类关键数据全量 E2EE 备份至 Cloudflare D1")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 2)

                Button {
                    if appState.isCloudAuthenticated {
                        Task { await triggerSyncNow() }
                    } else {
                        showSignInSheet = true
                    }
                } label: {
                    HStack {
                        if isWorking {
                            ProgressView().padding(.trailing, 4)
                        } else {
                            Image(systemName: appState.isCloudAuthenticated ? "icloud.and.arrow.up.fill" : "person.crop.circle.badge.plus")
                        }
                        Text(isWorking
                             ? "正在加密同步 10 类数据与习惯…"
                             : (appState.isCloudAuthenticated ? "立即全量端到端同步" : "先登录国内云端后再同步"))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(Color(Design.Palette.accent))
                }
                .disabled(isWorking)

                DisclosureGroup("展开 10 类同步数据透明明细", isExpanded: $showAllNamespaces) {
                    ForEach(summaries) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.subheadline)
                                .foregroundStyle(Color(Design.Palette.accent))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                Text(item.localCountLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.isSynced ? "已上云 ✓" : "待同步")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(item.isSynced ? Color(Design.Palette.success).opacity(0.14) : Color(Design.Palette.surface))
                                .foregroundStyle(item.isSynced ? Color(Design.Palette.success) : Color.secondary)
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("端到端零知识同步透明看板 (E2EE · LXE1)")
            } footer: {
                Text("10 类关键资产（词库/提示词/文风DNA/按键映射/设置/主题/短语/表情/统计）端侧加密后传回 Cloudflare D1；AI API 密钥与 Face ID 本地敏感保险箱永远留存本机，绝不上云。")
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
                    .tint(Color(Design.Palette.accent))
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
                                    .background(Color(Design.Palette.accent))
                                    .foregroundStyle(Color.white)
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

            // 4. 实时打字习惯画像与隐私授权（独立开关）
            Section {
                Toggle("同步脱敏打字习惯画像至云端自学习引擎", isOn: $appState.cloudConfig.habitAnalysisEnabled)
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
                Text("云端打字习惯自学习（仅统计数值 · 零打字原文）")
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

            // 6. 退出与注销
            if appState.isCloudAuthenticated || appState.isLocalOfflineAccount {
                Section {
                    Button(appState.isLocalOfflineAccount ? "退出本机离线档案" : "退出登录", role: .destructive) {
                        Task {
                            await appState.signOutCloudAccount()
                            statusBanner = "已退出账号，本机词库完好保留"
                        }
                    }
                    if appState.isCloudAuthenticated {
                        Button("永久注销云端账号并删除所有数据", role: .destructive) {
                            showDeleteAccountConfirm = true
                        }
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
            Text("将在服务端级联物理删除您的账号、通行密钥凭证、全部 E2EE 密文同步库、会话与习惯画像，无法恢复。本机离线词库不受影响。")
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
            let ver = (info["version"] as? String) ?? "5.0.0"
            statusBanner = "后端服务在线 (v\(ver)) · Apple Passkey 与 10 类云同步均已就绪"
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
