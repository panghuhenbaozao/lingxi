import AuthenticationServices
import PhotosUI
import SwiftUI
import UIKit

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
        ("墨玉", "#1C1C1E", "#48484A"),
        ("极光蓝", "#0A84FF", "#0055D4"),
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

// MARK: - Apple ID 风格极简模态登录页（干净、克制、居中聚焦、折叠高级服务器地址）

struct AppleStyleSignInSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Mode: Int {
        case login = 0
        case register = 1
        case apiKey = 2
    }

    @State private var mode: Mode = .login
    @State private var email: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var apiKey: String = ""
    @State private var showServerConfig: Bool = false
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 1. 顶部居中品牌图标与大标题（严格对标 Apple Account 登录页）
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(Design.Palette.ink))
                                .frame(width: 68, height: 68)
                                .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
                            Image(systemName: "text.cursor")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(Color(Design.Palette.canvas))
                        }
                        .padding(.top, 12)

                        Text(mode == .register ? "创建灵犀账号" : (mode == .apiKey ? "接入客户 API Key" : "登录灵犀账号"))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color(Design.Palette.ink))

                        Text("端到端加密同步个人词库、皮肤与跨屏剪贴板。\n未登录也可永久免费使用全部本地输入功能。")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 12)
                    }

                    // 2. 官方 Sign in with Apple 主按钮（置顶最醒目）
                    if mode != .apiKey {
                        SignInWithAppleButton(.continue) { req in
                            req.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            Task { await handleAppleAuth(result) }
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        HStack(spacing: 12) {
                            Rectangle().fill(Color(Design.Palette.hairline)).frame(height: 0.5)
                            Text("或使用邮箱账号")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Rectangle().fill(Color(Design.Palette.hairline)).frame(height: 0.5)
                        }
                    }

                    // 3. 苹果 InsetGrouped 风格极简表单卡片
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
                                TextField("昵称（显示在个人主页）", text: $username)
                                    .font(.system(size: 15))
                                    .padding(.horizontal, 16)
                                    .frame(height: 48)
                                Divider().padding(.leading, 16)
                            }
                            TextField("邮箱地址", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .font(.system(size: 15))
                                .padding(.horizontal, 16)
                                .frame(height: 48)
                            Divider().padding(.leading, 16)
                            SecureField("密码（至少 8 位）", text: $password)
                                .font(.system(size: 15))
                                .padding(.horizontal, 16)
                                .frame(height: 48)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let err = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(err)
                        }
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.error))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 4. 单一高对比度主操作按钮
                    Button {
                        Task { await submitPrimaryAction() }
                    } label: {
                        HStack {
                            if isWorking {
                                ProgressView().tint(Color(Design.Palette.canvas))
                            } else {
                                Text(mode == .register ? "创建账号并开启同步" : (mode == .apiKey ? "验证并连接 API Key" : "继续"))
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(Design.Palette.ink))
                        .foregroundStyle(Color(Design.Palette.canvas))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    // 5. 底部轻量模式切换链接
                    HStack(spacing: 20) {
                        if mode == .login {
                            Button("没有账号？免费注册") {
                                errorMessage = nil
                                mode = .register
                            }
                            Button("API Key 接入") {
                                errorMessage = nil
                                mode = .apiKey
                            }
                        } else {
                            Button("返回邮箱登录") {
                                errorMessage = nil
                                mode = .login
                            }
                            if mode == .register {
                                Button("API Key 接入") {
                                    errorMessage = nil
                                    mode = .apiKey
                                }
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    // 6. 高级自托管服务器地址默认折叠，保持登录屏极度纯净
                    DisclosureGroup("自托管服务器设置（高级）", isExpanded: $showServerConfig) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("如 http://192.168.1.10:8787", text: $appState.cloudConfig.serverBaseURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .font(.system(size: 13.5, design: .monospaced))
                                .padding(10)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text("支持 Vaultwarden 模式自建私有服务器；手机连电脑自建服务时请填写电脑局域网 IP。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color(Design.Palette.ink))
                }
            }
        }
    }

    private func submitPrimaryAction() async {
        isWorking = true
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

    private func handleAppleAuth(_ result: Result<ASAuthorization, Error>) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        switch result {
        case .success(let auth):
            if let cred = auth.credential as? ASAuthorizationAppleIDCredential {
                let token = cred.identityToken ?? Data(cred.user.utf8)
                do {
                    try await appState.signInWithAppleAccount(identityToken: token, user: cred.user)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let err):
            errorMessage = err.localizedDescription
        }
    }
}
