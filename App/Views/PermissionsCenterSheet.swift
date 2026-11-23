import AVFoundation
import CoreLocation
import Speech
import SwiftUI
import UIKit

/// 统一「一键开启权限」中心：集中检测并一键开启 AI 联网所需全部权限（系统键盘、允许完全访问、AI 密钥同步、语音、麦克风、定位）。
struct PermissionsCenterSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var locationService = LiveLocationLexiconService.shared

    @State private var speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    @State private var micPermission: AVAudioSession.RecordPermission = AVAudioSession.sharedInstance().recordPermission
    @State private var isRequestingAll = false
    @State private var isSyncingBridge = false
    @State private var toastMessage: String?
    @State private var toastIsSuccess = true

    private var isLocationGranted: Bool {
        locationService.authorizationStatus == .authorizedWhenInUse || locationService.authorizationStatus == .authorizedAlways
    }

    private var isSpeechGranted: Bool { speechStatus == .authorized }
    private var isMicGranted: Bool { micPermission == .granted }

    private var allCoreAIReady: Bool {
        appState.isKeyboardEnabled && appState.isKeyboardFullAccessConfirmed && appState.aiConfig.isConfigured
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                coreKeyboardAISection
                enhancedPermissionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("一键开启权限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                refreshPermissionStates()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    refreshPermissionStates()
                }
            }
        }
    }

    // MARK: - 顶部总览与一键操作

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(allCoreAIReady ? Color(Design.Palette.success) : Color(Design.Palette.accent))
                            .frame(width: 44, height: 44)
                        Image(systemName: allCoreAIReady ? "checkmark.shield.fill" : "lock.open.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(allCoreAIReady ? "键盘与 AI 核心权限已全部就绪" : "一键补齐 AI 与键盘必需权限")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text(allCoreAIReady
                             ? "现在切出灵犀键盘即可正常联网调用 AI、云翻译与语音输入。"
                             : "iOS 要求为键盘开启「允许完全访问」后，才允许键盘联网使用 AI。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        openAppSystemSettings()
                    } label: {
                        Label("一键前往系统设置", systemImage: "gearshape.fill")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(Design.Palette.accent))

                    Button {
                        Task { await requestAllRuntimePermissions() }
                    } label: {
                        if isRequestingAll {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                        } else {
                            Label("一键授权语音/定位", systemImage: "wand.and.stars")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRequestingAll)
                }

                if let msg = toastMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(toastIsSuccess ? Color(Design.Palette.success) : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 1. 键盘与 AI 必开权限

    private var coreKeyboardAISection: some View {
        Section {
            permissionRow(
                icon: "keyboard",
                title: "启用灵犀系统键盘",
                subtitle: appState.isKeyboardEnabled
                    ? "已在 iOS 键盘列表中启用"
                    : "跳转后点「键盘」→ 打开「灵犀输入法」",
                isGranted: appState.isKeyboardEnabled,
                grantedLabel: "已启用",
                actionTitle: "去开启",
                action: { openAppSystemSettings() }
            )

            permissionRow(
                icon: "network",
                title: "键盘「允许完全访问」",
                subtitle: appState.isKeyboardFullAccessConfirmed
                    ? "键盘已回传确认允许联网调用 AI 与读取配置"
                    : "AI 提示「无权限」的唯一原因！跳转后点「键盘」→ 打开「允许完全访问」，再切出一次灵犀键盘即可自动变绿",
                isGranted: appState.isKeyboardFullAccessConfirmed,
                grantedLabel: "已开启",
                actionTitle: "一键去开",
                action: { openAppSystemSettings() }
            )

            // AI 密钥与免费侧载同步状态
            HStack(alignment: .center, spacing: 12) {
                iconBadge(
                    systemName: "sparkles",
                    color: appState.aiConfig.isConfigured && AppGroup.isAvailable
                        ? Color(Design.Palette.success)
                        : Color.orange
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI 密钥与键盘同步")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text(aiSyncSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if !appState.aiConfig.isConfigured {
                    Button("去填 Key") {
                        appState.requestedTab = 2
                        dismiss()
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(Design.Palette.accentSoft))
                    .foregroundStyle(Color(Design.Palette.accent))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                } else if !AppGroup.isAvailable {
                    Button {
                        Task { await syncSideloadAIConfigNow() }
                    } label: {
                        if isSyncingBridge {
                            ProgressView().scaleEffect(0.75)
                        } else {
                            Text("同步给键盘")
                                .font(.caption.bold())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.16))
                    .foregroundStyle(Color.orange)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .disabled(isSyncingBridge)
                } else {
                    statusPill("已互通", granted: true)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("AI 与键盘核心权限（必开）")
        } footer: {
            Text("路径提示：点击「一键去开」会直达系统「设置 → 灵犀输入法」，点进「键盘」打开「允许完全访问」即可。普通拼音打字 100% 本地离线，仅在主动点 AI / 翻译时联网。")
        }
    }

    // MARK: - 2. 语音与实时地标增强权限

    private var enhancedPermissionsSection: some View {
        Section("语音与地标增强权限（可一键弹窗授权）") {
            permissionRow(
                icon: "waveform",
                title: "语音识别",
                subtitle: isSpeechGranted ? "已授权语音转写与 AI 去口水词" : "支持语音速记与 AI 自动整理润色",
                isGranted: isSpeechGranted,
                grantedLabel: "已授权",
                actionTitle: speechStatus == .denied || speechStatus == .restricted ? "去设置" : "一键授权",
                action: { Task { await requestSpeechPermission() } }
            )

            permissionRow(
                icon: "mic.fill",
                title: "麦克风",
                subtitle: isMicGranted ? "已授权采集语音输入" : "配合语音识别录入语音草稿",
                isGranted: isMicGranted,
                grantedLabel: "已授权",
                actionTitle: micPermission == .denied ? "去设置" : "一键授权",
                action: { Task { await requestMicPermission() } }
            )

            permissionRow(
                icon: "location.fill",
                title: "实时位置与周边地标学习",
                subtitle: isLocationGranted
                    ? "已授权，自动学习所在城市与 5km 商圈/路名热词"
                    : "自动识别当前城市与周边路名商圈（如临沂等本地地标，100% 留存本机）",
                isGranted: isLocationGranted,
                grantedLabel: "已授权",
                actionTitle: (locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted) ? "去设置" : "一键授权",
                action: { Task { await requestLocationPermission() } }
            )
        }
    }

    // MARK: - Helpers

    private var aiSyncSubtitle: String {
        if !appState.aiConfig.isConfigured {
            return "尚未填写 API Key（本地 Ollama 除外）"
        }
        if AppGroup.isAvailable {
            return "已配置「\(appState.aiConfig.activeModelName)」，与键盘共享容器已自动打通"
        }
        return "免费侧载下系统会隔离 App 与键盘沙盒，点右侧按钮复制直传口令后切出键盘即自动同步 AI 密钥与模型"
    }

    private func iconBadge(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusPill(_ title: String, granted: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.caption2.bold())
            Text(title)
                .font(.caption.bold())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background((granted ? Color(Design.Palette.success) : Color.orange).opacity(0.14))
        .foregroundStyle(granted ? Color(Design.Palette.success) : Color.orange)
        .clipShape(Capsule())
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        isGranted: Bool,
        grantedLabel: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            iconBadge(systemName: icon, color: isGranted ? Color(Design.Palette.success) : Color(Design.Palette.accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if isGranted {
                statusPill(grantedLabel, granted: true)
            } else {
                Button(actionTitle, action: action)
                    .font(.caption.bold())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color(Design.Palette.accent))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private func refreshPermissionStates() {
        appState.refreshAll()
        speechStatus = SFSpeechRecognizer.authorizationStatus()
        micPermission = AVAudioSession.sharedInstance().recordPermission
    }

    private func openAppSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func requestSpeechPermission() async {
        if speechStatus == .denied || speechStatus == .restricted {
            openAppSystemSettings()
            return
        }
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { result in
                cont.resume(returning: result)
            }
        }
        speechStatus = status
        showToast(status == .authorized ? "✓ 语音识别权限已开启" : "可在系统设置中开启语音识别权限", success: status == .authorized)
    }

    private func requestMicPermission() async {
        if micPermission == .denied {
            openAppSystemSettings()
            return
        }
        let granted = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
        micPermission = AVAudioSession.sharedInstance().recordPermission
        showToast(granted ? "✓ 麦克风权限已开启" : "可在系统设置中开启麦克风权限", success: granted)
    }

    private func requestLocationPermission() async {
        if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
            openAppSystemSettings()
            return
        }
        await locationService.refreshLiveGPSAndNearbyPOIs()
        showToast(isLocationGranted ? "✓ 定位权限已开启并完成周边地标学习" : locationService.statusMessage, success: isLocationGranted)
    }

    private func requestAllRuntimePermissions() async {
        isRequestingAll = true
        defer { isRequestingAll = false }
        if !isSpeechGranted && speechStatus == .notDetermined {
            await requestSpeechPermission()
        }
        if !isMicGranted && micPermission == .undetermined {
            await requestMicPermission()
        }
        if !isLocationGranted && locationService.authorizationStatus == .notDetermined {
            await requestLocationPermission()
        }
        refreshPermissionStates()
        if !appState.isKeyboardFullAccessConfirmed {
            showToast("系统语音/定位已处理；键盘「允许完全访问」需点左侧「一键前往系统设置」打开。", success: true)
        } else {
            showToast("✓ 全部权限检查完成！", success: true)
        }
    }

    private func syncSideloadAIConfigNow() async {
        isSyncingBridge = true
        defer { isSyncingBridge = false }
        let res = await appState.copySideloadBridgeTokenAndSync()
        showToast(res.message, success: res.ok)
    }

    private func showToast(_ msg: String, success: Bool) {
        withAnimation {
            toastMessage = msg
            toastIsSuccess = success
        }
    }
}
