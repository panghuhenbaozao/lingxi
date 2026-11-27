import SwiftUI
import UIKit

/// App 内显示用的同步方式文案（共享层 `title` / `subtitle` 是开发者术语，这里换成用户能看懂的说法）
private extension SyncTransportMode {
    var appTitle: String {
        switch self {
        case .localNoop: return "只在本机"
        case .lan: return "同一 Wi-Fi 下两台设备互传"
        case .e2eeCloud: return "云端加密同步"
        }
    }

    var appSubtitle: String {
        switch self {
        case .localNoop: return "不联网，所有数据只存在这台设备上"
        case .lan: return "不经过服务器，两台设备输入相同的 6 位配对码即可互传"
        case .e2eeCloud: return "登录后在多台设备间自动同步，内容端到端加密，服务器看不到"
        }
    }
}

/// 同步方式与词库维护（v6）：词库健康 → 同步方式 → 局域网互传 → 社区词包 → 开源承诺。
struct SustainabilityHubView: View {
    @EnvironmentObject private var appState: AppState

    // 注意：@State 的初始值表达式在每次创建视图结构体时都会执行；
    // iOS 16 的 NavigationLink 会在上级页面每次重绘时创建目标视图，所以这里只放轻量占位，真实数据在 onAppear 中加载
    @State private var relayConfig: ClipboardRelayConfig = ClipboardRelayConfig()
    @State private var healthReport: EngineHealthReport = EngineHealthReport.placeholder
    @State private var hasLoaded = false
    @State private var toast: String?
    @State private var errorToast: String?

    @State private var showSelfHealConfirm = false
    @State private var showSignIn = false

    // 局域网互传
    @State private var isLANListening: Bool = false
    @State private var isLANSyncing: Bool = false
    @FocusState private var lanFieldFocused: Bool

    // 社区词包（需要读文件，出现时加载）
    @State private var packCount = 0
    @State private var subscribedCount = 0
    @State private var isSyncingPacks = false

    // 自定义词包表单
    @State private var showAddCustomPackSheet = false
    @State private var customPackName = ""
    @State private var customPackCategory = "科技研发"
    @State private var customPackDesc = ""
    @State private var customPackURL = ""
    @State private var customPackTSV = "llm\t大语言模型\nrag\t检索增强生成"

    private var trimmedPeerHost: String {
        relayConfig.lanPeerHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 对方地址必须是另一台设备：127.0.0.1 / localhost 指向本机，互传没有意义
    private var isPeerHostUsable: Bool {
        let h = trimmedPeerHost.lowercased()
        guard !h.isEmpty, h != "127.0.0.1", h != "localhost", !h.contains(" ") else { return false }
        return true
    }

    private var isPairCodeValid: Bool {
        relayConfig.pairCode.count == 6 && !relayConfig.pairCode.contains(where: { !$0.isNumber })
    }

    var body: some View {
        List {
            healthSection
            syncModeSection
            if relayConfig.syncTransportMode == .lan || isLANListening {
                lanSection
            }
            communitySection
            openSourceSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("同步方式与词库维护")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
        .lxToast($errorToast, isError: true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { lanFieldFocused = false }
            }
        }
        .onAppear {
            reload()
        }
        .sheet(isPresented: $showAddCustomPackSheet) {
            addCustomCommunityPackSheet
        }
        .sheet(isPresented: $showSignIn, onDismiss: { reload() }) {
            AppleStyleSignInSheet()
        }
        .confirmationDialog("清理与修复词库？", isPresented: $showSelfHealConfirm, titleVisibility: .visible) {
            Button("开始清理", role: .destructive) {
                let outcome = EngineHealthAndSustainabilityService.shared.performSelfHealing()
                appState.refreshAll()
                healthReport = EngineHealthAndSustainabilityService.shared.diagnose()
                toast = "清理完成：删除 \(outcome.removedNoiseWords) 个偶然词、\(outcome.trimmedClipboardItems) 条旧剪贴板记录，健康分 \(outcome.newHealthScore)"
            }
        } message: {
            Text("会删除只用过一次、4 字以上且未置顶的自学习词，并只保留最近 15 条未置顶的剪贴板记录。置顶内容不受影响，删除后无法恢复，建议先备份。")
        }
    }

    private func reload() {
        relayConfig = ClipboardRelayConfig.load()
        healthReport = EngineHealthAndSustainabilityService.shared.diagnose()
        isLANListening = LANSyncService.shared.isListening
        packCount = CommunityLexiconService.shared.allAvailablePacks().count
        subscribedCount = CommunityLexiconService.shared.subscribedPackIDs().count
        hasLoaded = true
    }

    // MARK: - 1. 词库健康

    private var healthSection: some View {
        let score = healthReport.healthScore
        let tint: Color = score >= 90 ? Color(Design.Palette.success) : (score >= 75 ? Color(Design.Palette.accent) : Color(Design.Palette.warning))
        return Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color(Design.Palette.hairline), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: hasLoaded ? CGFloat(score) / 100 : 0)
                        .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(hasLoaded ? "\(score)" : "--")
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("健康分")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }
                .frame(width: 64, height: 64)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("词库健康分 \(score)")

                VStack(alignment: .leading, spacing: 4) {
                    Text(score >= 90 ? "词库状态很好" : (score >= 75 ? "词库状态良好" : "建议清理一下"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("用得越久，偶然打出的词会越积越多，偶尔清理能让常用词排得更准。")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)

            HStack(spacing: 8) {
                metricBox(label: "自学习词", value: healthReport.userWordCount)
                metricBox(label: "偶然词", value: healthReport.lowFreqNoiseCount, highlight: healthReport.lowFreqNoiseCount > 15)
                metricBox(label: "剪贴板", value: healthReport.clipboardItemCount, highlight: healthReport.clipboardItemCount > 35)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            Button {
                showSelfHealConfirm = true
            } label: {
                Label("清理与修复", systemImage: "wand.and.stars")
            }
            .buttonStyle(LXCapsuleButtonStyle(prominent: healthReport.healthScore < 90, wide: true))
            .disabled(!hasLoaded)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        } header: {
            Text("词库健康")
        } footer: {
            Text("置顶的词和置顶的剪贴板记录永远不会被清理。")
        }
    }

    private func metricBox(label: String, value: Int, highlight: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(hasLoaded ? value.formatted() : "--")
                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(highlight ? Color(Design.Palette.warning) : Color(Design.Palette.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color(Design.Palette.stone))
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 2. 同步方式

    private var syncModeSection: some View {
        Section {
            ForEach(SyncTransportMode.allCases) { mode in
                syncModeRow(mode)
            }
            if relayConfig.syncTransportMode == .e2eeCloud && !appState.isCloudAuthenticated {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(Color(Design.Palette.warning))
                    Text("还没有登录，云端同步暂时不会进行")
                        .font(.footnote)
                        .foregroundStyle(Color(Design.Palette.ink))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button("去登录") { showSignIn = true }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("同步方式")
        } footer: {
            Text(appState.cloudConfig.autoSyncEnabled
                 ? "数据变化后会按这里选择的方式自动同步。"
                 : "自动同步已关闭，可以在「灵犀账号」里打开。")
        }
    }

    private func syncModeRow(_ mode: SyncTransportMode) -> some View {
        let selected = relayConfig.syncTransportMode == mode
        return Button {
            selectMode(mode)
        } label: {
            HStack(spacing: 12) {
                LXIconTile(icon: mode.iconName, tint: selected ? Color(Design.Palette.accent) : Color(Design.Palette.slate))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.appTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text(mode.appSubtitle)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? Color(Design.Palette.accent) : Color(Design.Palette.hairline))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectMode(_ mode: SyncTransportMode) {
        guard relayConfig.syncTransportMode != mode else { return }
        relayConfig.syncTransportMode = mode
        relayConfig.save()
        switch mode {
        case .localNoop:
            toast = "已改为只在本机，不再自动同步"
        case .lan:
            toast = isPeerHostUsable ? "已改为局域网互传" : "已改为局域网互传，请在下方填写另一台设备的地址"
        case .e2eeCloud:
            toast = appState.isCloudAuthenticated ? "已改为云端加密同步" : "已改为云端加密同步，登录后开始同步"
        }
    }

    // MARK: - 3. 局域网互传

    private var lanSection: some View {
        Section {
            HStack(spacing: 10) {
                Text("对方地址")
                    .font(.subheadline)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .frame(width: 72, alignment: .leading)
                TextField("如 192.168.1.23", text: $relayConfig.lanPeerHost)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($lanFieldFocused)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { relayConfig.save() }
            }
            .frame(minHeight: 36)

            HStack(spacing: 10) {
                Text("配对码")
                    .font(.subheadline)
                    .foregroundStyle(Color(Design.Palette.stone))
                    .frame(width: 72, alignment: .leading)
                TextField("6 位数字", text: $relayConfig.pairCode)
                    .keyboardType(.numberPad)
                    .focused($lanFieldFocused)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(isPairCodeValid ? Color(Design.Palette.ink) : Color(Design.Palette.error))
                    .onChange(of: relayConfig.pairCode) { newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(6))
                        if digits != newValue { relayConfig.pairCode = digits }
                        if digits.count == 6 { relayConfig.save() }
                    }
            }
            .frame(minHeight: 36)

            HStack(spacing: 10) {
                Button {
                    toggleListening()
                } label: {
                    Label(isLANListening ? "停止接收" : "允许对方连接", systemImage: isLANListening ? "stop.circle" : "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: isLANListening ? Color(Design.Palette.error) : Color(Design.Palette.accent)))
                .disabled(!isPairCodeValid)

                Button {
                    runPeerSync()
                } label: {
                    HStack(spacing: 6) {
                        if isLANSyncing {
                            ProgressView().controlSize(.small).tint(Color.white)
                        } else {
                            Image(systemName: "arrow.left.arrow.right")
                        }
                        Text(isLANSyncing ? "互传中…" : "立即互传")
                    }
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                .disabled(isLANSyncing || !isPeerHostUsable || !isPairCodeValid)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            if isLANListening {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(Design.Palette.success))
                        .frame(width: 8, height: 8)
                    Text("正在等待对方连接（端口 \(relayConfig.lanPort)）")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                }
            }
        } header: {
            Text("局域网互传")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("一台设备点「允许对方连接」，另一台填好它的地址后点「立即互传」。两台设备要连在同一个 Wi-Fi 上，第一次使用时 iOS 会询问是否允许访问本地网络。")
                if !trimmedPeerHost.isEmpty && !isPeerHostUsable {
                    Text("这里要填另一台设备的地址，不能填本机（127.0.0.1）。")
                        .foregroundStyle(Color(Design.Palette.error))
                }
                Text("配对码与「跨屏剪贴板接力」共用，改这里两边都会变。")
            }
        }
    }

    private func toggleListening() {
        lanFieldFocused = false
        if isLANListening {
            LANSyncService.shared.stopListening()
            isLANListening = false
            toast = "已停止接收"
            return
        }
        do {
            LANSyncService.shared.pairCode = relayConfig.pairCode
            LANSyncService.shared.port = UInt16(clamping: relayConfig.lanPort)
            try LANSyncService.shared.startListening()
            isLANListening = true
            relayConfig.save()
            toast = "正在等待对方连接，配对码 \(relayConfig.pairCode)"
        } catch {
            errorToast = "无法开始接收：\(error.localizedDescription)"
        }
    }

    private func runPeerSync() {
        guard !isLANSyncing else { return }
        lanFieldFocused = false
        isLANSyncing = true
        relayConfig.lanPeerHost = trimmedPeerHost
        relayConfig.save()
        let host = relayConfig.lanPeerHost
        let port = UInt16(clamping: relayConfig.lanPort)
        let code = relayConfig.pairCode
        Task {
            do {
                let report = try await LANSyncService.shared.performPeerSync(peerHost: host, peerPort: port, pairCode: code)
                await MainActor.run {
                    isLANSyncing = false
                    appState.refreshAll()
                    toast = "互传完成：发送 \(report.pushed) 项，合并 \(report.applied) 项"
                }
            } catch {
                await MainActor.run {
                    isLANSyncing = false
                    errorToast = "互传失败：\(error.localizedDescription)。请确认两台设备在同一 Wi-Fi，且对方已点「允许对方连接」"
                }
            }
        }
    }

    // MARK: - 4. 社区词包

    private var communitySection: some View {
        Section {
            HStack(spacing: 12) {
                LXIconTile(icon: "books.vertical")
                VStack(alignment: .leading, spacing: 2) {
                    Text("已订阅 \(subscribedCount) 个 · 共 \(packCount) 个可用")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("专业领域的词包，订阅后键盘里直接能打出来")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                }
            }
            .padding(.vertical, 4)

            HStack(spacing: 10) {
                Button {
                    let count = CommunityLexiconService.shared.updateAllSubscribedPacks()
                    appState.refreshAll()
                    subscribedCount = CommunityLexiconService.shared.subscribedPackIDs().count
                    toast = subscribedCount == 0 ? "还没有订阅任何词包" : "已更新 \(subscribedCount) 个词包，共 \(count) 个词"
                } label: {
                    Label("更新已订阅", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                .disabled(subscribedCount == 0)

                Button {
                    syncRemotePacks()
                } label: {
                    HStack(spacing: 6) {
                        if isSyncingPacks {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "icloud.and.arrow.down")
                        }
                        Text(isSyncingPacks ? "获取中…" : "获取更多")
                    }
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true))
                .disabled(isSyncingPacks)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            Button {
                showAddCustomPackSheet = true
            } label: {
                Label("添加自己的词包", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.accent))
                    .frame(minHeight: 36)
            }
        } header: {
            Text("社区词包")
        } footer: {
            Text("在「设置 → 词库与实时地标 → 词库管理」里可以浏览和订阅每一个词包。")
        }
    }

    private func syncRemotePacks() {
        guard !isSyncingPacks else { return }
        isSyncingPacks = true
        Task {
            do {
                let remote = try await CommunityLexiconService.shared.SyncRemotePacksFromServer()
                await MainActor.run {
                    isSyncingPacks = false
                    packCount = CommunityLexiconService.shared.allAvailablePacks().count
                    toast = "已获取 \(remote.count) 个云端词包"
                }
            } catch {
                await MainActor.run {
                    isSyncingPacks = false
                    // 离线时仍可使用内置词包，属于提示而非错误
                    toast = "暂时连不上服务器，没有新的词包，可以继续使用内置的 \(packCount) 个"
                }
            }
        }
    }

    // MARK: - 5. 开源承诺（只读）

    private var openSourceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                promiseRow(icon: "keyboard", text: "键盘本身永不联网，平时打字只在本机运行")
                promiseRow(icon: "checkmark.seal", text: "不登录也能使用全部打字功能，没有功能阉割")
                promiseRow(icon: "lock", text: "云同步端到端加密，服务器看不到你的词库")
                promiseRow(icon: "chevron.left.forwardslash.chevron.right", text: "输入引擎、键盘和同步协议以 MIT 协议永久开源")
            }
            .padding(.vertical, 6)
        } header: {
            Text("我们的承诺")
        }
    }

    private func promiseRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.accent))
                .frame(width: 20)
                .padding(.top, 1)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color(Design.Palette.charcoal))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 自定义词包表单

    /// 有效词条行数：跳过空行与 # 注释，要求「编码<Tab>词条」
    private var validTSVLineCount: Int {
        customPackTSV
            .split(whereSeparator: \.isNewline)
            .filter { line in
                let s = line.trimmingCharacters(in: .whitespaces)
                guard !s.isEmpty, !s.hasPrefix("#") else { return false }
                let parts = s.split(separator: "\t", omittingEmptySubsequences: true)
                return parts.count >= 2
            }
            .count
    }

    private var canSaveCustomPack: Bool {
        !customPackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validTSVLineCount > 0
    }

    private var addCustomCommunityPackSheet: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("词包名称，如：法律文书常用词", text: $customPackName)
                    TextField("分类，如：法律、金融、编程", text: $customPackCategory)
                    TextField("简介（可选）", text: $customPackDesc)
                }
                Section {
                    TextEditor(text: $customPackTSV)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 160)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    HStack {
                        Text("词条")
                        Spacer()
                        Text("有效 \(validTSVLineCount) 条")
                            .monospacedDigit()
                            .foregroundStyle(validTSVLineCount > 0 ? Color(Design.Palette.stone) : Color(Design.Palette.error))
                            .textCase(nil)
                    }
                } footer: {
                    Text("每行一条：编码 + Tab + 词条，例如「llm<Tab>大语言模型」。以 # 开头的行会被忽略。")
                }
                Section {
                    TextField("在线词库地址（可选）", text: $customPackURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("填写后可以随时从这个地址更新词条。")
                }
            }
            .navigationTitle("添加词包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddCustomPackSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并订阅") {
                        let name = customPackName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let url = customPackURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        let pack = CommunityLexiconService.shared.addCustomPack(
                            name: name,
                            category: customPackCategory.trimmingCharacters(in: .whitespacesAndNewlines),
                            description: customPackDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                            tsv: customPackTSV,
                            sourceURL: url.isEmpty ? nil : url
                        )
                        appState.refreshAll()
                        showAddCustomPackSheet = false
                        packCount = CommunityLexiconService.shared.allAvailablePacks().count
                        subscribedCount = CommunityLexiconService.shared.subscribedPackIDs().count
                        toast = "已添加并订阅「\(pack.name)」，共 \(pack.wordCount) 个词"
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSaveCustomPack)
                }
            }
        }
    }
}
