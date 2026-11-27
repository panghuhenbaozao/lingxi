import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 灵犀账号（v6）：身份 → 云同步 → 打字习惯 → 安全与数据 → 服务器 → 退出 / 注销。
/// 未登录时只显示登录入口和本机可用的功能，不展示用不了的云端选项。
struct CloudAccountView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var showSignInSheet: Bool = false
    @State private var isSyncing: Bool = false
    @State private var isCheckingServer: Bool = false
    @State private var isRotatingKey: Bool = false
    @State private var statusBanner: String?
    @State private var errorBanner: String?
    @State private var appliedRecIDs: Set<String> = []
    @State private var showAllNamespaces: Bool = false

    // 安全与自托管
    @State private var showServerDisclosure: Bool = false
    @State private var showSecuritySheet: Bool = false
    @State private var newPasswordForRotation: String = ""
    @State private var confirmPasswordForRotation: String = ""
    @State private var isRotatingPassword: Bool = false
    @State private var rotationError: String?
    @State private var showDeleteAccountConfirm: Bool = false
    @State private var showClearHabitConfirm: Bool = false
    @State private var showRotateKeyConfirm: Bool = false
    @State private var showSignOutConfirm: Bool = false
    @State private var exportDocument: PortableDataFile?
    @State private var isExportingData: Bool = false

    /// 同步看板汇总：需要打开词库并读取约 10 个文件，只在进入页面与同步完成后计算
    @State private var namespaceSummaries: [CloudBackendClient.NamespaceSyncSummary] = []

    private static let minRotationPasswordLength = 8

    private var isSignedIn: Bool { appState.isCloudAuthenticated }

    var body: some View {
        List {
            identitySection
            if isSignedIn {
                syncSection
                habitSection
            } else {
                offlineInfoSection
            }
            relayLinkSection
            securitySection
            serverSection
            if isSignedIn || appState.isLocalOfflineAccount {
                exitSection
            }
        }
        .listStyle(.insetGrouped)
        .lxToast($statusBanner)
        .lxToast($errorBanner, isError: true)
        .navigationTitle("灵犀账号")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSignInSheet, onDismiss: {
            namespaceSummaries = CloudBackendClient.shared.syncNamespaceDashboardSummary()
        }) {
            AppleStyleSignInSheet()
        }
        .sheet(isPresented: $showSecuritySheet, onDismiss: {
            newPasswordForRotation = ""
            confirmPasswordForRotation = ""
            rotationError = nil
        }) {
            passwordRotationSheet
        }
        .onChange(of: selectedAvatarItem) { newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                let image = data.flatMap { UIImage(data: $0) }
                await MainActor.run {
                    selectedAvatarItem = nil
                    if let image {
                        appState.saveUserAvatarImage(image)
                        statusBanner = "已更新头像"
                    } else {
                        errorBanner = "无法读取这张图片，换一张试试"
                    }
                }
            }
        }
        .task {
            namespaceSummaries = CloudBackendClient.shared.syncNamespaceDashboardSummary()
            await appState.refreshHabitProfile()
        }
        .confirmationDialog("清除全部习惯画像？", isPresented: $showClearHabitConfirm, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                Task {
                    await appState.clearAllHabitAnalytics()
                    statusBanner = "已清除云端与本机的习惯画像数据"
                }
            }
        } message: {
            Text("云端和本机的打字习惯统计都会被删除，无法恢复。词库、短语和设置不受影响。")
        }
        .confirmationDialog(
            appState.isLocalOfflineAccount ? "退出本机离线档案？" : "退出登录？",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("退出", role: .destructive) {
                Task {
                    await appState.signOutCloudAccount()
                    namespaceSummaries = CloudBackendClient.shared.syncNamespaceDashboardSummary()
                    statusBanner = "已退出账号，本机词库完好保留"
                }
            }
        } message: {
            Text("退出后停止云同步，本机的词库、短语和设置都会保留，之后可以随时重新登录。")
        }
        .confirmationDialog("重新签发 API Key？", isPresented: $showRotateKeyConfirm, titleVisibility: .visible) {
            Button("重新签发", role: .destructive) {
                Task { await rotateAPIKey() }
            }
        } message: {
            Text("旧的 API Key 会立即失效，正在使用它的电脑端或脚本需要换成新 Key。")
        }
        .fileExporter(
            isPresented: $isExportingData,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "灵犀数据导出-\(Date().formatted(.iso8601.year().month().day()))"
        ) { result in
            exportDocument = nil
            switch result {
            case .success:
                statusBanner = "数据已导出为文件"
            case .failure(let error):
                let ns = error as NSError
                if !(ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) {
                    errorBanner = "导出失败：\(error.localizedDescription)"
                }
            }
        }
        .alert("永久注销云端账号？", isPresented: $showDeleteAccountConfirm) {
            Button("取消", role: .cancel) {}
            Button("注销并删除", role: .destructive) {
                Task { await performCascadeAccountDeletion() }
            }
        } message: {
            Text("服务器上的账号、登录凭证、全部加密同步数据和习惯画像都会被永久删除，无法恢复。这台设备上的词库不受影响。")
        }
    }

    // MARK: - 1. 身份

    private var identitySection: some View {
        Section {
            VStack(spacing: 12) {
                PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                    UserAvatarView(size: 86, showEditBadge: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更换头像")

                if isSignedIn {
                    signedInIdentity
                } else if appState.isLocalOfflineAccount {
                    offlineIdentity
                } else {
                    signedOutIdentity
                }

                if appState.userAvatarImage != nil {
                    Button("移除自定义头像") {
                        appState.removeUserAvatarImage()
                        statusBanner = "已移除头像"
                    }
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.error))
                    .frame(minHeight: 32)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .listRowBackground(Color.clear)
        }
    }

    private var signedInIdentity: some View {
        VStack(spacing: 8) {
            TextField("输入昵称", text: $appState.cloudConfig.username)
                .multilineTextAlignment(.center)
                .font(.title2.bold())
                .foregroundStyle(Color(Design.Palette.ink))
                .submitLabel(.done)
            Text(appState.cloudConfig.email.isEmpty ? "已通过 API Key 连接" : appState.cloudConfig.email)
                .font(.subheadline)
                .foregroundStyle(Color(Design.Palette.stone))
            LXTag(text: "云端在线 · 端到端加密", icon: "icloud.fill", tint: Color(Design.Palette.success), filled: true)

            if appState.userAvatarImage == nil {
                HStack(spacing: 12) {
                    ForEach(Array(UserAvatarView.avatarGradients.enumerated()), id: \.offset) { idx, item in
                        let selected = appState.cloudConfig.avatarThemeIndex == idx
                        Button {
                            appState.cloudConfig.avatarThemeIndex = idx
                        } label: {
                            Circle()
                                .fill(Color(hexColor: HexColor(item.top)))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(Color(Design.Palette.accent), lineWidth: selected ? 2 : 0)
                                        .padding(-3)
                                )
                                .frame(width: 32, height: 32)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("头像颜色：\(item.name)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var offlineIdentity: some View {
        VStack(spacing: 8) {
            Text(appState.cloudConfig.username.isEmpty ? "本机档案" : appState.cloudConfig.username)
                .font(.title3.bold())
                .foregroundStyle(Color(Design.Palette.ink))
            LXTag(text: "只在本机使用，未连接云端", icon: "iphone", tint: Color(Design.Palette.warning), filled: true)
            Button {
                showSignInSheet = true
            } label: {
                Label("登录云端，在多台设备间同步", systemImage: "icloud.and.arrow.up")
            }
            .buttonStyle(LXCapsuleButtonStyle(prominent: true))
            .padding(.top, 4)
        }
    }

    private var signedOutIdentity: some View {
        VStack(spacing: 8) {
            Text("还没有登录")
                .font(.title3.bold())
                .foregroundStyle(Color(Design.Palette.ink))
            Text("不登录也能使用全部打字功能。登录后可以在多台设备间加密同步词库、外观和设置。")
                .font(.footnote)
                .foregroundStyle(Color(Design.Palette.stone))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showSignInSheet = true
            } label: {
                Label("登录或注册", systemImage: "person.crop.circle.badge.plus")
            }
            .buttonStyle(LXCapsuleButtonStyle(prominent: true))
            .padding(.top, 4)
        }
    }

    // MARK: - 2. 云同步（已登录）

    private var syncSection: some View {
        let summaries = namespaceSummaries
        let syncedCount = summaries.filter(\.isSynced).count
        return Section {
            LXToggleRow(
                "自动同步",
                subtitle: "数据变化后自动加密上传，其他设备会收到更新",
                isOn: $appState.cloudConfig.autoSyncEnabled
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(summaries.isEmpty ? "--" : "\(syncedCount) / \(summaries.count)")
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("类数据已同步")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                    Spacer()
                }
                if !summaries.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(summaries) { item in
                            Capsule()
                                .fill(item.isSynced ? Color(Design.Palette.success) : Color(Design.Palette.hairline))
                                .frame(height: 5)
                        }
                    }
                    .accessibilityHidden(true)
                }
                if let lastAt = appState.cloudConfig.lastSyncedAt {
                    Text("上次同步 \(lastAt.formatted(.relative(presentation: .named)))\(appState.cloudConfig.lastSyncSummary.isEmpty ? "" : " · " + appState.cloudConfig.lastSyncSummary)")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .lineLimit(2)
                } else {
                    Text("还没有同步过，点下面的按钮开始第一次同步。")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                }
            }
            .padding(.vertical, 4)

            Button {
                Task { await triggerSyncNow() }
            } label: {
                HStack(spacing: 6) {
                    if isSyncing {
                        ProgressView().controlSize(.small).tint(Color.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(isSyncing ? "正在同步…" : "立即同步")
                }
            }
            .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
            .disabled(isSyncing)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            DisclosureGroup("查看每一类数据", isExpanded: $showAllNamespaces) {
                ForEach(summaries) { item in
                    HStack(spacing: 12) {
                        LXIconTile(icon: item.icon, tint: item.isSynced ? Color(Design.Palette.success) : Color(Design.Palette.slate))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text(item.localCountLabel)
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                        Spacer(minLength: 6)
                        LXTag(
                            text: item.isSynced ? "已同步" : "待同步",
                            tint: item.isSynced ? Color(Design.Palette.success) : Color(Design.Palette.slate),
                            filled: item.isSynced
                        )
                    }
                    .padding(.vertical, 2)
                }
            }
            .font(.subheadline)
        } header: {
            Text("云同步")
        } footer: {
            Text("同步内容在本机加密后才上传，服务器看不到。AI 的 API 密钥和本地保险箱不参与同步，只留在这台设备上。")
        }
    }

    /// 未登录时：说明本机能做什么，避免展示用不了的云端选项
    private var offlineInfoSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                LXIconTile(icon: "lock.shield")
                VStack(alignment: .leading, spacing: 3) {
                    Text("数据只保存在这台设备上")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("换手机或重装前，记得在「设置 → 云同步与加密备份」里导出一份加密备份。")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)

            NavigationLink {
                BackupSettingsView()
            } label: {
                LXNavRow(icon: "lock.doc", title: "加密备份与恢复", subtitle: "不登录也能把数据带到新手机")
            }
        } header: {
            Text("本机数据")
        }
    }

    // MARK: - 3. 打字习惯（已登录）

    private var habitSection: some View {
        let p = appState.habitProfile
        return Section {
            LXToggleRow(
                "上传打字习惯统计",
                subtitle: "只上传速度、时段等数字，用于多设备合并画像；不包含任何输入内容",
                isOn: $appState.cloudConfig.habitAnalysisEnabled
            )
            .onChange(of: appState.cloudConfig.habitAnalysisEnabled) { granted in
                Task {
                    await CloudBackendClient.shared.syncConsentToServer(scope: "typing_analytics", granted: granted)
                }
            }

            if p.avgCPM > 0.5 {
                LabeledContent("平均 / 最快速度", value: String(format: "%.0f / %.0f 字/分", p.avgCPM, p.peakCPM))
            }
            if !p.domainAffinity.primaryDomain.isEmpty {
                LabeledContent("常用领域", value: p.domainAffinity.primaryDomain)
            }

            ForEach(p.tuningRecommendations) { rec in
                let applied = appliedRecIDs.contains(rec.id)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text(rec.reason)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Button(applied ? "已开启" : "开启") {
                        appState.applyTuningRecommendation(rec)
                        appliedRecIDs.insert(rec.id)
                        statusBanner = "已开启「\(rec.title)」"
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: !applied))
                    .disabled(applied)
                }
                .padding(.vertical, 2)
            }

            Button(role: .destructive) {
                showClearHabitConfirm = true
            } label: {
                Text("清除云端与本机的习惯数据")
                    .frame(minHeight: 32)
            }
        } header: {
            Text("打字习惯")
        } footer: {
            Text("关闭上传后会通知服务器撤回授权。完整的本机统计在「设置 → 打字统计」里。")
        }
    }

    // MARK: - 4. 跨屏接力（入口）

    private var relayLinkSection: some View {
        Section {
            NavigationLink {
                CrossDeviceRelaySubView()
            } label: {
                LXNavRow(
                    icon: "laptopcomputer.and.iphone",
                    title: "跨屏剪贴板接力",
                    subtitle: "电脑和手机输入同一个 6 位码互传文字，无需登录"
                )
            }
        }
    }

    // MARK: - 5. 安全与数据

    private var securitySection: some View {
        Section {
            if isSignedIn {
                HStack(spacing: 12) {
                    LXIconTile(icon: "key.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("API Key")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text(appState.cloudConfig.apiKeyPrefix.isEmpty ? "已绑定" : appState.cloudConfig.apiKeyPrefix)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                    Spacer(minLength: 6)
                    Button("复制") {
                        if appState.activeCustomerAPIKey.isEmpty {
                            errorBanner = "这台设备上没有保存完整的 API Key"
                        } else {
                            // 密钥属于机密：只留本机、限时自动清除、不进剪贴板历史
                            ConcealedPasteboard.copy(appState.activeCustomerAPIKey)
                            statusBanner = "已复制 API Key，\(Int(ConcealedPasteboard.defaultLifetime)) 秒后自动从剪贴板清除"
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                }
                .padding(.vertical, 2)

                Button {
                    showRotateKeyConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        if isRotatingKey {
                            ProgressView().controlSize(.small)
                        }
                        Text("重新签发 API Key")
                    }
                    .frame(minHeight: 32)
                }
                .disabled(isRotatingKey)

                Button {
                    showSecuritySheet = true
                } label: {
                    Text("修改密码")
                        .frame(minHeight: 32)
                }
            }

            Button {
                // 导出包含词库与设置等个人数据：保存为文件，而不是放进会跨设备同步、会被键盘记录的系统剪贴板
                let json = ComplianceService.shared.exportAllPortableDataJSON()
                exportDocument = PortableDataFile(text: json)
                isExportingData = true
            } label: {
                LXNavRow(icon: "square.and.arrow.up", title: "导出我的全部数据", subtitle: "保存为 JSON 文件，可查看或迁移")
            }
            .buttonStyle(.plain)
        } header: {
            Text("安全与数据")
        }
    }

    // MARK: - 6. 服务器

    private var serverSection: some View {
        Section {
            DisclosureGroup("服务器设置（一般不用改）", isExpanded: $showServerDisclosure) {
                TextField("服务器地址", text: $appState.cloudConfig.serverBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote.monospaced())
                    .frame(minHeight: 36)
                HStack(spacing: 8) {
                    Button {
                        Task { await checkHealth() }
                    } label: {
                        HStack(spacing: 6) {
                            if isCheckingServer {
                                ProgressView().controlSize(.small)
                            }
                            Text(isCheckingServer ? "测试中…" : "测试连接")
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                    .disabled(isCheckingServer)

                    Button("复制网页控制台地址") {
                        UIPasteboard.general.string = appState.cloudConfig.normalizedBaseURL + "/dashboard"
                        statusBanner = "已复制网页控制台地址"
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: false))

                    Spacer(minLength: 0)
                }
                if appState.cloudConfig.normalizedBaseURL != CloudBackendConfig.defaultCloudServerURL {
                    Button("恢复默认服务器") {
                        appState.cloudConfig.serverBaseURL = CloudBackendConfig.defaultCloudServerURL
                        statusBanner = "已恢复默认服务器"
                    }
                    .font(.subheadline)
                }
            }
            .font(.subheadline)
        } footer: {
            Text("自己搭建了灵犀服务器时才需要修改。")
        }
    }

    // MARK: - 7. 退出与注销

    private var exitSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Text(appState.isLocalOfflineAccount ? "退出本机档案" : "退出登录")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            if isSignedIn {
                Button(role: .destructive) {
                    showDeleteAccountConfirm = true
                } label: {
                    Text("注销云端账号")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
            }
        } footer: {
            if isSignedIn {
                Text("注销会删除服务器上的账号和全部同步数据；这台设备上的词库和设置会保留。")
            }
        }
    }

    // MARK: - 修改密码

    private var rotationPasswordsMismatch: Bool {
        !confirmPasswordForRotation.isEmpty && confirmPasswordForRotation != newPasswordForRotation
    }

    private var canRotatePassword: Bool {
        newPasswordForRotation.count >= Self.minRotationPasswordLength
            && newPasswordForRotation == confirmPasswordForRotation
            && !isRotatingPassword
    }

    private var passwordRotationSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("新密码（至少 \(Self.minRotationPasswordLength) 位）", text: $newPasswordForRotation)
                        .textContentType(UITextContentType.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("再输入一次", text: $confirmPasswordForRotation)
                        .textContentType(UITextContentType.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit {
                            if canRotatePassword { Task { await performPasswordAndKeyRotation() } }
                        }
                } header: {
                    Text("设置新密码")
                } footer: {
                    if rotationPasswordsMismatch {
                        Text("两次输入的密码不一致。")
                            .foregroundStyle(Color(Design.Palette.error))
                    } else if !newPasswordForRotation.isEmpty && newPasswordForRotation.count < Self.minRotationPasswordLength {
                        Text("密码至少 \(Self.minRotationPasswordLength) 位。")
                            .foregroundStyle(Color(Design.Palette.error))
                    } else {
                        Text("修改后，云端的同步数据会用新密码重新加密。其他设备需要用新密码重新登录。")
                    }
                }

                if let rotationError {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(Design.Palette.error))
                            Text(rotationError)
                                .font(.footnote)
                                .foregroundStyle(Color(Design.Palette.ink))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await performPasswordAndKeyRotation() }
                    } label: {
                        HStack(spacing: 6) {
                            if isRotatingPassword {
                                ProgressView().controlSize(.small).tint(Color.white)
                            }
                            Text(isRotatingPassword ? "正在修改并重新加密…" : "确认修改")
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(!canRotatePassword)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
            }
            .navigationTitle("修改密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showSecuritySheet = false }
                        .disabled(isRotatingPassword)
                }
            }
            .interactiveDismissDisabled(isRotatingPassword)
        }
    }

    // MARK: - Actions

    private func checkHealth() async {
        guard !isCheckingServer else { return }
        isCheckingServer = true
        defer { isCheckingServer = false }
        let t0 = Date()
        do {
            let info = try await CloudBackendClient.shared.checkServerHealth()
            let ms = max(1, Int(Date().timeIntervalSince(t0) * 1000))
            let ver = (info["version"] as? String) ?? "--"
            statusBanner = "服务器连接正常 · \(ms) ms · 版本 \(ver)"
        } catch {
            errorBanner = "连接失败：\(error.localizedDescription)"
        }
    }

    private func rotateAPIKey() async {
        guard !isRotatingKey else { return }
        isRotatingKey = true
        defer { isRotatingKey = false }
        do {
            let newKey = try await appState.rotateCloudAPIKey()
            statusBanner = "已签发新 API Key：\(String(newKey.prefix(16)))…"
        } catch {
            errorBanner = "重新签发失败：\(error.localizedDescription)"
        }
    }

    private func triggerSyncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let report = try await appState.syncCloudNow()
            namespaceSummaries = CloudBackendClient.shared.syncNamespaceDashboardSummary()
            statusBanner = "同步完成：上传 \(report.pushed) 项，下载 \(report.pulled) 项"
        } catch {
            errorBanner = "同步失败：\(error.localizedDescription)"
        }
    }

    /// 失败时保持弹窗打开并在弹窗内显示原因（页面底部的提示会被弹窗挡住）
    private func performPasswordAndKeyRotation() async {
        guard canRotatePassword else { return }
        isRotatingPassword = true
        rotationError = nil
        defer { isRotatingPassword = false }
        do {
            _ = try await CloudBackendClient.shared.changePasswordAndRotateKey(newPassword: newPasswordForRotation)
            appState.refreshAll()
            showSecuritySheet = false
            statusBanner = "密码已修改，同步数据已用新密码重新加密"
        } catch {
            rotationError = "修改失败：\(error.localizedDescription)"
        }
    }

    private func performCascadeAccountDeletion() async {
        do {
            try await CloudBackendClient.shared.deleteCloudAccountCascade()
            appState.refreshAll()
            namespaceSummaries = CloudBackendClient.shared.syncNamespaceDashboardSummary()
            statusBanner = "云端账号和服务器上的数据已全部删除，本机词库保留"
        } catch {
            errorBanner = "注销失败：\(error.localizedDescription)"
        }
    }
}

/// 个人数据导出文件（JSON 文本）
struct PortableDataFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

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
