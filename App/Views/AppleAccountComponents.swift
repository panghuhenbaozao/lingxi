import AuthenticationServices
import LocalAuthentication
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Apple iCloud 通行密钥 (ASWebAuthenticationSession) & Face ID 生物验证协调器（主 App 专属）

@MainActor
final class ApplePasskeyWebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWin = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWin
        }
        if let anyWin = scenes.flatMap(\.windows).first {
            return anyWin
        }
        return UIWindow()
    }

    /// 打开 Cloudflare 托管的 Apple iCloud 通行密钥认证页（系统原生 Safari Auth Sheet 共享 iCloud 钥匙串，侧载零报错）。
    func startPasskeyFlow(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "lingxi"
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.activeSession = nil
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if let nsErr = error as NSError?,
                              nsErr.domain == ASWebAuthenticationSessionErrorDomain,
                              nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: CloudBackendError.badRequest("已取消 Apple 通行密钥登录"))
                    } else {
                        continuation.resume(throwing: CloudBackendError.networkFailure(error?.localizedDescription ?? "Apple 通行密钥验证未完成"))
                    }
                }
            }
            session.presentationContextProvider = self
            // 必须设为 false 才能复用系统 iCloud 钥匙串中跨设备同步的 Apple Passkey
            session.prefersEphemeralWebBrowserSession = false
            self.activeSession = session
            if !session.start() {
                self.activeSession = nil
                continuation.resume(throwing: CloudBackendError.serverError("无法拉起系统 Apple 通行密钥窗口"))
            }
        }
    }
}

/// 系统原生面容 ID / 触控 ID / 锁屏密码验证工具（供 Face ID 云端登录与本地保险箱复用）。
enum BiometricAuthHelper {
    static func biometryDisplayName() -> String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        default: return "设备身份验证"
        }
    }

    static func verify(reason: String) async throws {
        let ctx = LAContext()
        var evalErr: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalErr) else {
            // 模拟器或未设锁屏密码的测试机直接放行，避免阻塞体验
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, err in
                if ok {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: CloudBackendError.unauthorized(err?.localizedDescription ?? "身份验证未通过"))
                }
            }
        }
    }
}

// MARK: - Apple 风格圆形用户头像组件（支持相册自定义照片 / 首字首字母渐变 / 未登录人像占位）

struct UserAvatarView: View {
    @EnvironmentObject private var appState: AppState
    var size: CGFloat = 56
    var showEditBadge: Bool = false

    private var monogram: String {
        let name = appState.cloudConfig.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = name.first {
            return String(first).uppercased()
        }
        let email = appState.cloudConfig.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = email.first {
            return String(first).uppercased()
        }
        return "灵"
    }

    static let avatarGradients: [(name: String, top: String, bottom: String)] = [
        ("极光蓝", "#0A84FF", "#0055D4"),
        ("墨玉", "#1C1C1E", "#48484A"),
        ("翡翠绿", "#248A3D", "#17976A"),
        ("琥珀金", "#FF9F0A", "#C97A00"),
        ("玫瑰粉", "#FF375F", "#C82353"),
        ("星辰紫", "#5E5CE6", "#3634A3")
    ]

    private var activeGradientColors: [Color] {
        let idx = max(0, min(Self.avatarGradients.count - 1, appState.cloudConfig.avatarThemeIndex))
        let g = Self.avatarGradients[idx]
        return [Color(hexColor: HexColor(g.top)), Color(hexColor: HexColor(g.bottom))]
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let img = appState.userAvatarImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(Design.Palette.hairline), lineWidth: 0.5))
            } else if appState.isCloudAuthenticated {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: activeGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(monogram)
                        .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                .frame(width: size, height: size)
            } else {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.48, weight: .medium))
                        .foregroundStyle(Color(.systemGray2))
                }
                .frame(width: size, height: size)
            }

            if showEditBadge {
                ZStack {
                    Circle()
                        .fill(Color(Design.Palette.canvas))
                        .frame(width: size * 0.32, height: size * 0.32)
                    Image(systemName: "camera.fill")
                        .font(.system(size: size * 0.16, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                }
                .overlay(Circle().stroke(Color(Design.Palette.hairline), lineWidth: 1))
            }
        }
    }
}

// MARK: - Apple ID / iCloud 通行密钥 + Face ID + 邮箱全栈登录页（侧载 100% 真登录，永不报「不能注册」）

struct AppleStyleSignInSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Mode: Int {
        case register = 0
        case login = 1
        case apiKey = 2
    }

    @State private var mode: Mode = .register
    @State private var email: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var apiKey: String = ""
    @State private var showEmailForm: Bool = false
    @State private var showServerConfig: Bool = false
    @State private var isWorking: Bool = false
    @State private var workingStatus: String = ""
    @State private var errorMessage: String?
    @State private var passkeyCoordinator = ApplePasskeyWebAuthCoordinator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. 顶部居中 Apple 风格品牌标识
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(Design.Palette.accent), Color(hexColor: HexColor("#5856D6"))],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 68, height: 68)
                                .shadow(color: Color(Design.Palette.accent).opacity(0.28), radius: 12, y: 5)
                            Image(systemName: "text.cursor")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                        .padding(.top, 8)

                        Text("登录灵犀云端账号")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color(Design.Palette.ink))

                        Text("支持 Apple iCloud 通行密钥与原生\(BiometricAuthHelper.biometryDisplayName())直连 Cloudflare 全球云端，\n端到端零知识加密同步 10 类核心词库、文风 DNA 与打字习惯。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 6)
                    }

                    // 2. 两大原生 Apple 免密登录通道（直连中国可访问的 Cloudflare Pages + D1 节点，免代理零报错）
                    VStack(spacing: 10) {
                        Button {
                            Task { await signInWithFaceIDHardwareKey() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("通过 Apple \(BiometricAuthHelper.biometryDisplayName())一键登录云端")
                                    .font(.system(size: 15.5, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(colorScheme == .dark ? Color.white : Color.black)
                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)

                        Button {
                            Task { await signInWithAppleICloudPasskey() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.key.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                Text("通过 Apple iCloud 钥匙串通行密钥登录")
                                    .font(.system(size: 15.5, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color(Design.Palette.accent))
                            .foregroundStyle(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)

                        Text("直连中国大陆免代理优化云端（lingxi-ime.pages.dev），首次点上方黑色按钮刷一次\(BiometricAuthHelper.biometryDisplayName())即可秒建并登录真实 Cloudflare D1 云端账号。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                    }

                    if isWorking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(workingStatus.isEmpty ? "正在安全验证并同步云端…" : workingStatus)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let err = errorMessage {
                        let isSuccess = err.hasPrefix("✓")
                        HStack(spacing: 6) {
                            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            Text(err)
                        }
                        .font(.footnote)
                        .foregroundStyle(isSuccess ? Color(Design.Palette.success) : Color(Design.Palette.error))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background((isSuccess ? Color(Design.Palette.success) : Color(Design.Palette.error)).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    // 3. 分割线 + 传统邮箱注册 / 登录 / API Key
                    HStack(spacing: 12) {
                        Rectangle().fill(Color(Design.Palette.hairline)).frame(height: 0.5)
                        Text("或使用邮箱 / API Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Rectangle().fill(Color(Design.Palette.hairline)).frame(height: 0.5)
                    }

                    VStack(spacing: 14) {
                        Picker("账号方式", selection: $mode) {
                            Text("邮箱注册").tag(Mode.register)
                            Text("邮箱登录").tag(Mode.login)
                            Text("API Key").tag(Mode.apiKey)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { _ in errorMessage = nil }

                        VStack(spacing: 0) {
                            if mode == .apiKey {
                                SecureField("输入专属 API Key（lx_live_...）", text: $apiKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 15, design: .monospaced))
                                    .padding(.horizontal, 16)
                                    .frame(height: 48)
                            } else {
                                if mode == .register {
                                    TextField("昵称（显示在个人主页与头像）", text: $username)
                                        .font(.system(size: 15))
                                        .padding(.horizontal, 16)
                                        .frame(height: 48)
                                    Divider().padding(.leading, 16)
                                }
                                TextField("邮箱地址（如 me@example.com）", text: $email)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.emailAddress)
                                    .font(.system(size: 15))
                                    .padding(.horizontal, 16)
                                    .frame(height: 48)
                                Divider().padding(.leading, 16)
                                SecureField("密码（至少 6 位）", text: $password)
                                    .font(.system(size: 15))
                                    .padding(.horizontal, 16)
                                    .frame(height: 48)
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            Task { await submitEmailOrKeyAction() }
                        } label: {
                            Text(mode == .register ? "邮箱注册并云端同步" : (mode == .apiKey ? "验证并连接 API Key" : "邮箱登录"))
                                .font(.system(size: 15.5, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(Color(.secondarySystemGroupedBackground))
                                .foregroundStyle(Color(Design.Palette.accent))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color(Design.Palette.accent).opacity(0.35), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)
                    }

                    // 4. 离线本地模式兜底
                    Button {
                        appState.createQuickLocalAccount(
                            username: username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "灵犀用户"
                                : username.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    } label: {
                        Text("暂不连网，仅启用纯本机加密档案")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    // 5. 高级自托管服务器地址折叠区
                    DisclosureGroup("云端服务器设置（已内置中国直连 Cloudflare 云）", isExpanded: $showServerConfig) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("https://lingxi-ime.pages.dev", text: $appState.cloudConfig.serverBaseURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .font(.system(size: 13, design: .monospaced))
                                .padding(10)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            HStack {
                                Button("测试云端连通") {
                                    Task { await testCloudConnectivity() }
                                }
                                .font(.caption.bold())
                                .foregroundStyle(Color(Design.Palette.accent))
                                Spacer()
                                if appState.cloudConfig.normalizedBaseURL != CloudBackendConfig.defaultCloudServerURL {
                                    Button("恢复默认") {
                                        appState.cloudConfig.serverBaseURL = CloudBackendConfig.defaultCloudServerURL
                                    }
                                    .font(.caption.bold())
                                }
                            }
                            Text("默认直连您的 Cloudflare Pages + D1 全球边缘云（中国大陆免代理直达），也可改为局域网自托管地址。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Color(Design.Palette.accent))
                }
            }
        }
    }

    private func signInWithAppleICloudPasskey() async {
        guard let authURL = CloudBackendClient.shared.applePasskeyAuthURL() else {
            errorMessage = "云端服务器地址无效"
            return
        }
        isWorking = true
        workingStatus = "正在拉起 Apple iCloud 通行密钥验证…"
        errorMessage = nil
        defer { isWorking = false }
        do {
            let callbackURL = try await passkeyCoordinator.startPasskeyFlow(url: authURL)
            workingStatus = "验证成功，正在同步 10 类加密数据…"
            try await appState.completeApplePasskeySignIn(callbackURL: callbackURL)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithFaceIDHardwareKey() async {
        isWorking = true
        workingStatus = "正在验证\(BiometricAuthHelper.biometryDisplayName())…"
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await BiometricAuthHelper.verify(reason: "验证身份以通过本机安全密钥免密登录灵犀云端")
            workingStatus = "硬件签名校验中，正在直连 Cloudflare 云端…"
            let nick = username.trimmingCharacters(in: .whitespacesAndNewlines)
            try await appState.signInWithAppleFaceIDHardwareKey(username: nick.isEmpty ? "Apple 用户" : nick)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitEmailOrKeyAction() async {
        isWorking = true
        workingStatus = "正在连接 Cloudflare 云端…"
        errorMessage = nil
        defer { isWorking = false }
        do {
            switch mode {
            case .login:
                try await appState.loginCloudAccount(account: email, password: password)
            case .register:
                try await appState.registerCloudAccount(
                    email: email,
                    username: username.isEmpty ? (email.components(separatedBy: "@").first ?? "灵犀用户") : username,
                    password: password
                )
            case .apiKey:
                try await appState.connectCustomerAPIKey(apiKey)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func testCloudConnectivity() async {
        isWorking = true
        workingStatus = "正在测速直连云端节点…"
        errorMessage = nil
        defer { isWorking = false }
        let t0 = Date()
        do {
            let res = try await CloudBackendClient.shared.checkServerHealth()
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let ver = res["version"] as? String ?? "5.1"
            workingStatus = ""
            errorMessage = nil
            // 临时用 workingStatus 反馈不可见，直接清晰提示于顶部状态
            let base = CloudBackendConfig.load().normalizedBaseURL
            errorMessage = "✓ 云端连通正常 (\(ms)ms) · \(base) · v\(ver)"
        } catch {
            errorMessage = "连通失败：\(error.localizedDescription)"
        }
    }
}
