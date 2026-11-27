import AVFoundation
import CoreLocation
import Photos
import Speech
import SwiftUI
import UIKit

/// 权限中心（v6）：
/// - 顶部进度：核心 3 项（启用键盘 / 完全访问 / AI 密钥）+ 可选 4 项分开计数；
/// - 下一步永远只有一个主按钮（按当前缺什么自动切换）；
/// - 可选权限标明「用在哪个功能」，一键授权后如实汇报结果（几项开启、几项被拒绝需去设置）。
struct PermissionsCenterSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var locationService = LiveLocationLexiconService.shared

    @State private var speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    @State private var micPermission: AVAudioSession.RecordPermission = AVAudioSession.sharedInstance().recordPermission
    @State private var photoStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var isRequestingAll = false
    @State private var isSyncingBridge = false
    @State private var toast: String?

    private var isLocationGranted: Bool {
        locationService.authorizationStatus == .authorizedWhenInUse || locationService.authorizationStatus == .authorizedAlways
    }

    private var isLocationDenied: Bool {
        locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted
    }

    private var isSpeechGranted: Bool { speechStatus == .authorized }
    private var isSpeechDenied: Bool { speechStatus == .denied || speechStatus == .restricted }
    private var isMicGranted: Bool { micPermission == .granted }
    private var isMicDenied: Bool { micPermission == .denied }
    private var isPhotosGranted: Bool { photoStatus == .authorized || photoStatus == .limited }
    private var isPhotosDenied: Bool { photoStatus == .denied || photoStatus == .restricted }

    private var aiReady: Bool { appState.aiConfig.isConfigured && AppGroup.isAvailable }

    private var coreReadyCount: Int {
        [appState.isKeyboardEnabled, appState.isKeyboardFullAccessConfirmed, aiReady].filter { $0 }.count
    }

    private var optionalReadyCount: Int {
        [isPhotosGranted, isSpeechGranted, isMicGranted, isLocationGranted].filter { $0 }.count
    }

    /// 还没问过系统的可选权限数（一键授权只对这些弹窗）
    private var undeterminedOptionalCount: Int {
        [
            photoStatus == .notDetermined,
            speechStatus == .notDetermined,
            micPermission == .undetermined,
            locationService.authorizationStatus == .notDetermined,
        ].filter { $0 }.count
    }

    private var deniedOptionalCount: Int {
        [isPhotosDenied, isSpeechDenied, isMicDenied, isLocationDenied].filter { $0 }.count
    }

    private enum NextStep {
        case enableKeyboard, fullAccess, fillKey, syncKey, optional, done
    }

    private var nextStep: NextStep {
        if !appState.isKeyboardEnabled { return .enableKeyboard }
        if !appState.isKeyboardFullAccessConfirmed { return .fullAccess }
        if !appState.aiConfig.isConfigured { return .fillKey }
        if !AppGroup.isAvailable { return .syncKey }
        if undeterminedOptionalCount > 0 { return .optional }
        return .done
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                coreSection
                optionalSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("权限中心")
            .navigationBarTitleDisplayMode(.inline)
            .lxToast($toast)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                refreshPermissionStates()
            }
            .onChange(of: scenePhase) { phase in
                // 从系统设置返回时自动刷新状态
                if phase == .active {
                    refreshPermissionStates()
                }
            }
        }
    }

    // MARK: - 顶部总览：进度 + 唯一主操作

    private var summarySection: some View {
        let coreDone = coreReadyCount == 3
        return Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    LXIconTile(
                        icon: coreDone ? "checkmark.shield.fill" : "shield.lefthalf.filled",
                        tint: coreDone ? Color(Design.Palette.success) : Color(Design.Palette.accent),
                        size: 44
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(coreDone ? "核心功能已就绪" : "还差 \(3 - coreReadyCount) 步就能用 AI")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text(coreDone
                             ? "可选权限已开 \(optionalReadyCount)/4，按需开启即可"
                             : "按下方按钮一步步来，从系统设置返回后会自动刷新")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                progressBar(done: coreReadyCount, total: 3)

                nextStepButton
            }
            .padding(.vertical, 6)
        }
    }

    private func progressBar(done: Int, total: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { idx in
                Capsule()
                    .fill(idx < done ? Color(Design.Palette.success) : Color(Design.Palette.hairline))
                    .frame(height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("核心权限已完成 \(done) 项，共 \(total) 项")
    }

    @ViewBuilder
    private var nextStepButton: some View {
        switch nextStep {
        case .enableKeyboard:
            primaryButton("去系统设置添加键盘", icon: "gearshape.fill") { openAppSystemSettings() }
        case .fullAccess:
            primaryButton("去开启「允许完全访问」", icon: "gearshape.fill") { openAppSystemSettings() }
        case .fillKey:
            primaryButton("去填写 AI 密钥", icon: "key.fill") { goToAITab() }
        case .syncKey:
            primaryButton(isSyncingBridge ? "正在同步…" : "把 AI 设置同步给键盘", icon: "arrow.triangle.2.circlepath", loading: isSyncingBridge) {
                Task { await syncSideloadAIConfigNow() }
            }
        case .optional:
            primaryButton(isRequestingAll ? "正在请求…" : "一次开启其余 \(undeterminedOptionalCount) 项可选权限", icon: "checkmark.circle", loading: isRequestingAll) {
                Task { await requestAllRuntimePermissions() }
            }
        case .done:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(Design.Palette.success))
                Text(deniedOptionalCount > 0
                     ? "有 \(deniedOptionalCount) 项可选权限被关闭，需要时可在下方去设置打开"
                     : "全部设置完成")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func primaryButton(_ title: String, icon: String, loading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView().controlSize(.small).tint(Color.white)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
            }
        }
        .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
        .disabled(loading)
    }

    // MARK: - 核心：键盘 + 完全访问 + AI 密钥

    private var coreSection: some View {
        Section {
            permissionRow(
                step: 1,
                icon: "keyboard",
                title: "添加灵犀键盘",
                subtitle: appState.isKeyboardEnabled
                    ? "已添加到系统键盘列表"
                    : "设置 → 灵犀输入法 → 键盘 → 打开「灵犀输入法」",
                state: appState.isKeyboardEnabled ? .granted : .pending,
                actionTitle: "去设置",
                action: { openAppSystemSettings() }
            )

            permissionRow(
                step: 2,
                icon: "network",
                title: "允许完全访问",
                subtitle: appState.isKeyboardFullAccessConfirmed
                    ? "键盘可以使用 AI、剪贴板和语音"
                    : "同一页面打开「允许完全访问」，然后切到灵犀键盘一次，这里就会变绿",
                state: appState.isKeyboardFullAccessConfirmed ? .granted : .pending,
                actionTitle: "去设置",
                action: { openAppSystemSettings() }
            )

            permissionRow(
                step: 3,
                icon: "sparkles",
                title: "AI 密钥",
                subtitle: aiSyncSubtitle,
                state: aiReady ? .granted : .pending,
                actionTitle: appState.aiConfig.isConfigured ? (isSyncingBridge ? "同步中" : "同步") : "去填写",
                action: {
                    if appState.aiConfig.isConfigured {
                        Task { await syncSideloadAIConfigNow() }
                    } else {
                        goToAITab()
                    }
                }
            )
        } header: {
            Text("核心 · \(coreReadyCount)/3")
        } footer: {
            Text("「完全访问」是 iOS 对所有第三方键盘的统一提示。灵犀平时打字完全在本机离线运行，只有你主动使用 AI、翻译或跨屏接力时才会联网。")
        }
    }

    // MARK: - 可选：按功能说明用途

    private var optionalSection: some View {
        Section {
            permissionRow(
                icon: "photo.on.rectangle",
                title: "照片",
                subtitle: "截屏识图：读取最新截屏发给 AI，识别后可自动删除这张截屏",
                state: isPhotosGranted ? .granted : (isPhotosDenied ? .denied : .pending),
                actionTitle: isPhotosDenied ? "去设置" : "允许",
                action: { Task { await requestPhotosPermission() } }
            )

            permissionRow(
                icon: "waveform",
                title: "语音识别",
                subtitle: "语音输入：把说的话转成文字，并去掉「嗯」「那个」等口头语",
                state: isSpeechGranted ? .granted : (isSpeechDenied ? .denied : .pending),
                actionTitle: isSpeechDenied ? "去设置" : "允许",
                action: { Task { await requestSpeechPermission() } }
            )

            permissionRow(
                icon: "mic.fill",
                title: "麦克风",
                subtitle: "语音输入和语音同传时录音",
                state: isMicGranted ? .granted : (isMicDenied ? .denied : .pending),
                actionTitle: isMicDenied ? "去设置" : "允许",
                action: { Task { await requestMicPermission() } }
            )

            permissionRow(
                icon: "location.fill",
                title: "位置",
                subtitle: "周边地名：自动学习附近的路名、商圈、车站，打字更快。位置只存在本机",
                state: isLocationGranted ? .granted : (isLocationDenied ? .denied : .pending),
                actionTitle: isLocationDenied ? "去设置" : "允许",
                action: { Task { await requestLocationPermission() } }
            )
        } header: {
            Text("可选 · \(optionalReadyCount)/4")
        } footer: {
            Text("不开也能正常打字，只是对应功能用不了。被拒绝过的权限，iOS 不允许再次弹窗，需要到系统设置里打开。")
        }
    }

    // MARK: - Helpers

    private var aiSyncSubtitle: String {
        if !appState.aiConfig.isConfigured {
            return "还没填写 API Key（使用本机 Ollama 时可不填）"
        }
        if AppGroup.isAvailable {
            return "正在使用「\(appState.aiConfig.activeModelName)」，已自动同步给键盘"
        }
        return "免费侧载模式下 App 和键盘互相隔离，需要手动同步一次"
    }

    private enum PermissionState { case granted, pending, denied }

    private func permissionRow(
        step: Int? = nil,
        icon: String,
        title: String,
        subtitle: String,
        state: PermissionState,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        let tint: Color = {
            switch state {
            case .granted: return Color(Design.Palette.success)
            case .pending: return Color(Design.Palette.accent)
            case .denied: return Color(Design.Palette.warning)
            }
        }()
        return HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                LXIconTile(icon: icon, tint: tint)
                if let step, state != .granted {
                    Text("\(step)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.white)
                        .frame(width: 15, height: 15)
                        .background(Color(Design.Palette.accent), in: Circle())
                        .overlay(Circle().stroke(Color(Design.Palette.canvas), lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    if state == .denied {
                        LXTag(text: "已拒绝", tint: Color(Design.Palette.warning), filled: true)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if state == .granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(Design.Palette.success))
                    .accessibilityLabel("已开启")
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(LXCapsuleButtonStyle(prominent: state == .pending, tint: tint))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func refreshPermissionStates() {
        appState.refreshAll()
        speechStatus = SFSpeechRecognizer.authorizationStatus()
        micPermission = AVAudioSession.sharedInstance().recordPermission
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private func openAppSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func goToAITab() {
        appState.requestedTab = 2
        dismiss()
    }

    /// 单项请求；`announce` 为 false 时不弹提示（批量请求时由汇总提示统一说明）
    private func requestSpeechPermission(announce: Bool = true) async {
        if isSpeechDenied {
            openAppSystemSettings()
            return
        }
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { result in
                cont.resume(returning: result)
            }
        }
        await MainActor.run { speechStatus = status }
        if announce {
            toast = status == .authorized ? "已开启语音识别" : "语音识别未开启，可在系统设置里打开"
        }
    }

    private func requestMicPermission(announce: Bool = true) async {
        if isMicDenied {
            openAppSystemSettings()
            return
        }
        let granted = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
        await MainActor.run { micPermission = AVAudioSession.sharedInstance().recordPermission }
        if announce {
            toast = granted ? "已开启麦克风" : "麦克风未开启，可在系统设置里打开"
        }
    }

    private func requestPhotosPermission(announce: Bool = true) async {
        if isPhotosDenied {
            openAppSystemSettings()
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run { photoStatus = status }
        if announce {
            switch status {
            case .authorized: toast = "已开启照片访问"
            case .limited: toast = "已允许访问部分照片；截屏识图需要能看到最新截屏"
            default: toast = "照片访问未开启，可在系统设置里打开"
            }
        }
    }

    private func requestLocationPermission(announce: Bool = true) async {
        if isLocationDenied {
            openAppSystemSettings()
            return
        }
        await locationService.refreshLiveGPSAndNearbyPOIs()
        if announce {
            if isLocationGranted {
                toast = "已开启位置，正在学习周边地名"
            } else if !locationService.statusMessage.isEmpty {
                toast = locationService.statusMessage
            } else {
                toast = "位置未开启，可在系统设置里打开"
            }
        }
    }

    /// 只对「还没问过」的权限依次弹窗，结束后如实汇报结果
    private func requestAllRuntimePermissions() async {
        isRequestingAll = true
        defer { isRequestingAll = false }
        let before = optionalReadyCount
        if photoStatus == .notDetermined { await requestPhotosPermission(announce: false) }
        if speechStatus == .notDetermined { await requestSpeechPermission(announce: false) }
        if micPermission == .undetermined { await requestMicPermission(announce: false) }
        if locationService.authorizationStatus == .notDetermined { await requestLocationPermission(announce: false) }
        refreshPermissionStates()
        let gained = optionalReadyCount - before
        if deniedOptionalCount > 0 {
            toast = "新开启 \(max(gained, 0)) 项，\(deniedOptionalCount) 项未允许（需要时可在系统设置里打开）"
        } else {
            toast = "可选权限已全部开启"
        }
    }

    private func syncSideloadAIConfigNow() async {
        isSyncingBridge = true
        defer { isSyncingBridge = false }
        let res = await appState.copySideloadBridgeTokenAndSync()
        toast = res.ok ? LXToastText.clean(res.message) : "同步失败：\(LXToastText.clean(res.message))"
    }
}
