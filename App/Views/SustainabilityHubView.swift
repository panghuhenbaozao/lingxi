import SwiftUI
import UIKit

/// 可持续发展、三模可插拔同步、M2 局域网双机直连、引擎自愈巡检与 Open-Core 开源生态中心
struct SustainabilityHubView: View {
    @EnvironmentObject private var appState: AppState

    @State private var relayConfig: ClipboardRelayConfig = ClipboardRelayConfig.load()
    @State private var healthReport: EngineHealthReport = EngineHealthAndSustainabilityService.shared.diagnose()
    @State private var statusBanner: String?
    @State private var isErrorBanner: Bool = false

    // M2 局域网双机直连状态
    @State private var isLANListening: Bool = LANSyncService.shared.isListening
    @State private var isLANSyncing: Bool = false

    // M4 自定义社区词包表单
    @State private var showAddCustomPackSheet = false
    @State private var customPackName = ""
    @State private var customPackCategory = "科技研发"
    @State private var customPackDesc = ""
    @State private var customPackURL = ""
    @State private var customPackTSV = "llm\t大语言模型\nrag\t检索增强生成"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let banner = statusBanner {
                    feedbackBanner(banner, isError: isErrorBanner)
                }

                ironLawsAndHealthCard
                pluggableSyncRouterCard
                lanPeerToPeerSyncCard
                openCoreSustainabilityTierCard
                communityEcosystemCard
            }
            .padding(18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("可持续发展与多模同步")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            relayConfig = ClipboardRelayConfig.load()
            healthReport = EngineHealthAndSustainabilityService.shared.diagnose()
            isLANListening = LANSyncService.shared.isListening
        }
        .sheet(isPresented: $showAddCustomPackSheet) {
            addCustomCommunityPackSheet
        }
    }

    // MARK: - 1. 四条架构铁律 + 引擎健康自愈巡检卡

    private var ironLawsAndHealthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color(Design.Palette.hairline), lineWidth: 3)
                        .frame(width: 58, height: 58)
                    VStack(spacing: 0) {
                        Text("\(healthReport.healthScore)")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("健康分")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("引擎生命周期与架构铁律巡检")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("MIT Open-Core")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(Design.Palette.surface))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .clipShape(Capsule())
                    }
                    Text("30 天半衰期词频自动衰减 · App Group 硬件级文件保护 · 零原文字段")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(Design.Palette.steel))
                }
                Spacer(minLength: 0)
            }

            // 四条不可动摇的架构铁律徽章矩阵
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ironLawPill(icon: "airplane.circle.fill", title: "铁律 1 · 键盘零联网", detail: "扩展进程永不发网络请求")
                ironLawPill(icon: "checkmark.shield.fill", title: "铁律 2 · 离线全功能", detail: "未登录 0 功能阉割")
                ironLawPill(icon: "key.radiowaves.forward.fill", title: "铁律 3 · 同步零知识", detail: "LXE1 端侧密文封装")
                ironLawPill(icon: "arrow.triangle.branch", title: "铁律 4 · 双通道物理隔离", detail: "同步与脱敏分析分表分权")
            }

            Divider()

            // 实时词库与账本健康指标
            HStack(spacing: 10) {
                metricBox(label: "个人词条", value: "\(healthReport.userWordCount)")
                metricBox(label: "置顶词条", value: "\(healthReport.pinnedWordCount)")
                metricBox(label: "偶然低频词", value: "\(healthReport.lowFreqNoiseCount)")
                metricBox(label: "同步账本", value: "\(healthReport.syncLedgerRecordCount)")
            }

            ForEach(healthReport.suggestions, id: \.self) { tip in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                        .padding(.top, 2)
                    Text(tip)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(Design.Palette.slate))
                }
            }

            Button {
                let outcome = EngineHealthAndSustainabilityService.shared.performSelfHealing()
                appState.refreshAll()
                healthReport = EngineHealthAndSustainabilityService.shared.diagnose()
                showFeedback(outcome.summaryMessage, isError: false)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars.inverse")
                    Text("一键执行半衰期词频自愈与账本瘦身")
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color(Design.Palette.ink))
                .foregroundStyle(Color(Design.Palette.canvas))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    // MARK: - 2. 第一部分：同步层可插拔三实现切换器 (LocalNoop | LAN | E2EE Cloud)

    private var pluggableSyncRouterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("同步层可插拔三实现 (架构第一部分)", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Text(relayConfig.syncTransportMode.rawValue)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(Design.Palette.stone))
            }

            ForEach(SyncTransportMode.allCases) { mode in
                let selected = (relayConfig.syncTransportMode == mode)
                Button {
                    relayConfig.syncTransportMode = mode
                    relayConfig.save()
                    healthReport = EngineHealthAndSustainabilityService.shared.diagnose()
                    showFeedback("已切换同步层实现为：\(mode.title)", isError: false)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(selected ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
                            .frame(width: 34, height: 34)
                            .background(selected ? Color(Design.Palette.ink) : Color(Design.Palette.surface))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(mode.title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text(mode.subtitle)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color(Design.Palette.steel))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Color(Design.Palette.ink) : Color(Design.Palette.stone))
                    }
                    .padding(12)
                    .background(selected ? Color(Design.Palette.surface) : Color(Design.Palette.canvas))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selected ? Color(Design.Palette.ink) : Color(Design.Palette.hairline), lineWidth: selected ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    // MARK: - 3. M2 局域网双机同步控制台 (NWListener + 6位配对码 ChaCha20-Poly1305)

    private var lanPeerToPeerSyncCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("M2 局域网同 Wi-Fi 双机互导 (NWListener)", systemImage: "wifi.router.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Text(isLANListening ? "监听中 :\(relayConfig.lanPort)" : "待机")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(Design.Palette.surface))
                    .foregroundStyle(isLANListening ? Color(Design.Palette.success) : Color(Design.Palette.stone))
                    .clipShape(Capsule())
            }

            Text("无需登录任何云端账号：在同 Wi-Fi 下输入相同 6 位配对码，即以 HKDF-SHA256 派生会话密钥并通过 ChaCha20-Poly1305 点对点同步 7 大核心词库与设置。")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(Design.Palette.steel))

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("对端局域网 IP")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(Design.Palette.stone))
                    TextField("192.168.1.x 或 127.0.0.1", text: $relayConfig.lanPeerHost)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(9)
                        .background(Color(Design.Palette.surface))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("6 位加密配对码")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(Design.Palette.stone))
                    TextField("886699", text: $relayConfig.pairCode)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .padding(9)
                        .frame(width: 100)
                        .background(Color(Design.Palette.surface))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            HStack(spacing: 10) {
                Button {
                    if isLANListening {
                        LANSyncService.shared.stopListening()
                        isLANListening = false
                        showFeedback("已关闭本机局域网同步监听", isError: false)
                    } else {
                        do {
                            LANSyncService.shared.pairCode = relayConfig.pairCode
                            LANSyncService.shared.port = UInt16(relayConfig.lanPort)
                            try LANSyncService.shared.startListening()
                            isLANListening = true
                            relayConfig.save()
                            showFeedback("本机已启动 NWListener 监听端口 \(relayConfig.lanPort)，配对码 \(relayConfig.pairCode)", isError: false)
                        } catch {
                            showFeedback("启动局域网监听失败：\(error.localizedDescription)", isError: true)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isLANListening ? "stop.circle.fill" : "antenna.radiowaves.left.and.right")
                        Text(isLANListening ? "停止本机监听" : "开启本机接收监听")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(Color(Design.Palette.surface))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    isLANSyncing = true
                    relayConfig.save()
                    Task {
                        do {
                            let report = try await LANSyncService.shared.performPeerSync(
                                peerHost: relayConfig.lanPeerHost,
                                peerPort: UInt16(relayConfig.lanPort),
                                pairCode: relayConfig.pairCode
                            )
                            await MainActor.run {
                                isLANSyncing = false
                                appState.refreshAll()
                                showFeedback("局域网加密同步完成：推送 \(report.pushed) 项 · 合并 \(report.applied) 项（ChaCha20-Poly1305 验证通过）", isError: false)
                            }
                        } catch {
                            await MainActor.run {
                                isLANSyncing = false
                                showFeedback("局域网同步失败：\(error.localizedDescription)", isError: true)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isLANSyncing {
                            ProgressView().tint(Color(Design.Palette.canvas))
                        } else {
                            Image(systemName: "arrow.left.arrow.right.circle.fill")
                        }
                        Text("立即双机加密互导")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(Color(Design.Palette.ink))
                    .foregroundStyle(Color(Design.Palette.canvas))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLANSyncing)
            }
        }
        .padding(16)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    // MARK: - 4. Open-Core 可持续发展商业分层与自托管自由

    private var openCoreSustainabilityTierCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Open-Core 可持续发展模式", systemImage: "leaf.arrow.triangle.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Text(relayConfig.planTier.badgeText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(Design.Palette.surface))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .clipShape(Capsule())
            }

            Text("开源承诺不变更：输入引擎、键盘 UI、同步协议以 MIT 永久开源；通过官方托管 E2EE 云服务与 B 端企业显式授权画像 API 实现长期自我造血。")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(Design.Palette.steel))

            ForEach(OpenCorePlanTier.allCases) { tier in
                let isCurrent = (relayConfig.planTier == tier)
                Button {
                    relayConfig.planTier = tier
                    if tier == .free {
                        relayConfig.syncTransportMode = .localNoop
                    } else if tier == .selfHosted || tier == .pro || tier == .enterprise {
                        relayConfig.syncTransportMode = .e2eeCloud
                    }
                    relayConfig.save()
                    showFeedback("已切换当前服务层级为：\(tier.displayName)", isError: false)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tier.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Spacer()
                            Text(tier.badgeText)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isCurrent ? Color(Design.Palette.ink) : Color(Design.Palette.surface))
                                .foregroundStyle(isCurrent ? Color(Design.Palette.canvas) : Color(Design.Palette.ink))
                                .clipShape(Capsule())
                        }
                        Text(tier.summary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(Design.Palette.slate))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(11)
                    .background(isCurrent ? Color(Design.Palette.surface) : Color(Design.Palette.canvas))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(isCurrent ? Color(Design.Palette.ink) : Color(Design.Palette.hairline), lineWidth: isCurrent ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    // MARK: - 5. M4 开源社区共创词库生态

    private var communityEcosystemCard: some View {
        let packs = CommunityLexiconService.shared.allAvailablePacks()
        let subscribed = CommunityLexiconService.shared.subscribedPackIDs()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("M4 开源词库社区生态 (\(packs.count) 个词包)", systemImage: "books.vertical.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Spacer()
                Button {
                    showAddCustomPackSheet = true
                } label: {
                    Label("新增词库源", systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(Design.Palette.ink))
                }
            }

            Text("对标 HeliBoard 词典仓与 WowType TSV 规范：支持一键更新已订阅词包、从自建/官方服务端拉取社区词包，或接入任意 Git Raw TSV 词库源。")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(Design.Palette.steel))

            HStack(spacing: 10) {
                Button {
                    let count = CommunityLexiconService.shared.updateAllSubscribedPacks()
                    appState.refreshAll()
                    showFeedback("已全量更新 \(subscribed.count) 个已订阅词库包，共刷新 \(count) 条专业词条", isError: false)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("一键更新已订阅 (\(subscribed.count))")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Color(Design.Palette.surface))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color(Design.Palette.hairline), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        do {
                            let remote = try await CommunityLexiconService.shared.SyncRemotePacksFromServer()
                            await MainActor.run {
                                showFeedback("已从服务端社区词典仓同步 \(remote.count) 个共享词库包", isError: false)
                            }
                        } catch {
                            await MainActor.run {
                                showFeedback("当前处于离线或服务端未启动，已使用内置离线社区词典仓 (\(packs.count) 个词包)", isError: false)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "icloud.and.arrow.down")
                        Text("同步云端词典仓")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Color(Design.Palette.ink))
                    .foregroundStyle(Color(Design.Palette.canvas))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    private var addCustomCommunityPackSheet: some View {
        NavigationStack {
            Form {
                Section("词库包元信息") {
                    TextField("词包名称（如：法律文书高频词包）", text: $customPackName)
                    TextField("分类（如：法律、金融、编程）", text: $customPackCategory)
                    TextField("简介描述", text: $customPackDesc)
                    TextField("Git Raw TSV 地址（可选）", text: $customPackURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("WowType TSV 词条内容（每行：编码<TAB>词条）") {
                    TextEditor(text: $customPackTSV)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle("新增开源 TSV 词库源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddCustomPackSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并订阅") {
                        let pack = CommunityLexiconService.shared.addCustomPack(
                            name: customPackName.isEmpty ? "自定义专题词包" : customPackName,
                            category: customPackCategory,
                            description: customPackDesc,
                            tsv: customPackTSV,
                            sourceURL: customPackURL.isEmpty ? nil : customPackURL
                        )
                        appState.refreshAll()
                        showAddCustomPackSheet = false
                        showFeedback("已新增并订阅「\(pack.name)」(\(pack.wordCount) 条词条)", isError: false)
                    }
                }
            }
        }
    }

    // MARK: - 辅助组件

    private func ironLawPill(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(Design.Palette.ink))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(Design.Palette.stone))
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Color(Design.Palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func metricBox(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(Design.Palette.ink))
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(Design.Palette.stone))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(Design.Palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func feedbackBanner(_ text: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .foregroundStyle(isError ? Color(Design.Palette.error) : Color(Design.Palette.success))
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color(Design.Palette.ink))
            Spacer()
            Button {
                statusBanner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(Design.Palette.stone))
            }
        }
        .padding(12)
        .background(Color(Design.Palette.canvas))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isError ? Color(Design.Palette.error) : Color(Design.Palette.hairline), lineWidth: 1)
        )
    }

    private func showFeedback(_ message: String, isError: Bool) {
        statusBanner = message
        isErrorBanner = isError
    }
}
