import SwiftUI
import UIKit

/// 端侧 AI 隐私脱敏护盾管理页（全链路生效于 App 与键盘扩展 + 交互式实时脱敏试测沙盒）
struct AIPrivacyShieldView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newTerm = ""
    @State private var sandboxInput = "王总您好，我叫张伟，手机号 13812345678，邮箱 zhangwei@example.com，身份证 11010519900307281X，请查收。"
    @State private var feedback: String?

    private static let builtinDetectors: [(icon: String, name: String, tag: String)] = [
        ("phone.fill", "中国大陆 11 位手机号", "[PHONE_n]"),
        ("person.text.rectangle", "18 位身份证号", "[ID_n]"),
        ("envelope.fill", "电子邮箱地址", "[EMAIL_n]"),
        ("creditcard.fill", "Luhn 校验银行卡号", "[CARD_n]"),
        ("key.fill", "API Key / 访问密钥", "[SECRET_n]"),
        ("network", "IPv4 网络地址", "[IP_n]"),
    ]

    var body: some View {
        let preview = AIPrivacyShield.sanitize(sandboxInput, customTerms: appState.aiConfig.privacyCustomTerms)
        let restored = AIPrivacyShield.restore(preview.sanitizedText, mapping: preview.mapping)

        return List {
            Section {
                HStack(spacing: 12) {
                    LXIconTile(
                        icon: appState.aiConfig.privacyShieldEnabled ? "checkmark.shield.fill" : "shield.lefthalf.filled",
                        tint: appState.aiConfig.privacyShieldEnabled ? Color(Design.Palette.success) : Color(Design.Palette.accent),
                        size: 42
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.aiConfig.privacyShieldEnabled ? "隐私脱敏护盾运行中" : "端侧 AI 隐私脱敏护盾")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("发往任何外部 AI 接口前在本机自动替换为占位符，敏感原文绝不离开设备。")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)

                Toggle(isOn: $appState.aiConfig.privacyShieldEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开启 AI 发送前自动脱敏")
                        Text("同时保护 App 工作台与键盘扩展内的全部 AI 请求")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }
                .tint(Color(Design.Palette.accent))

                Toggle(isOn: $appState.aiConfig.privacyAutoRestore) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("收到 AI 回复后在本地自动还原")
                        Text("关闭后结果中将继续保留 [PHONE_1] 等脱敏占位符")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                    }
                }
                .tint(Color(Design.Palette.accent))
                .disabled(!appState.aiConfig.privacyShieldEnabled)
            }

            Section {
                if appState.aiConfig.privacyCustomTerms.isEmpty {
                    Text("可添加你的真实姓名、公司名、项目代号或家庭住址（至少 2 字）。")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                } else {
                    LXFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(appState.aiConfig.privacyCustomTerms, id: \.self) { term in
                            LXRemovableChip(text: term, tint: Color(Design.Palette.accent)) {
                                appState.aiConfig.privacyCustomTerms.removeAll { $0 == term }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                LXAddFieldRow(placeholder: "新增私密词（如：张伟 / 星海科技）", text: $newTerm) { w in
                    if w.count < 2 {
                        feedback = "私密词至少需要 2 个字"
                    } else if appState.aiConfig.privacyCustomTerms.contains(w) {
                        feedback = "「\(w)」已在保护列表"
                    } else {
                        appState.aiConfig.privacyCustomTerms.insert(w, at: 0)
                        feedback = "已加入隐私保护词"
                    }
                }
            } header: {
                Text("自定义私密词库 · \(appState.aiConfig.privacyCustomTerms.count)")
            }

            Section("内置自动识别类型（6 大类）") {
                ForEach(Self.builtinDetectors, id: \.tag) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.subheadline)
                            .foregroundStyle(Color(Design.Palette.accent))
                            .frame(width: 22)
                        Text(item.name)
                            .font(.subheadline)
                            .foregroundStyle(Color(Design.Palette.ink))
                        Spacer()
                        LXTag(text: item.tag)
                    }
                }
            }

            Section {
                TextField("输入含手机号/邮箱/身份证/自定义词的句子测试…", text: $sandboxInput, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.subheadline)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("发出给大模型的脱敏稿", systemImage: "arrow.up.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.accent))
                        Spacer()
                        LXTag(text: "拦截 \(preview.hits.count) 处", tint: preview.hasRedactions ? Color(Design.Palette.success) : Color(Design.Palette.stone), filled: preview.hasRedactions)
                    }
                    Text(preview.sanitizedText)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color(Design.Palette.ink))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.vertical, 2)

                if preview.hasRedactions {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("本地还原预览", systemImage: "arrow.down.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.success))
                        Text(restored)
                            .font(.footnote)
                            .foregroundStyle(Color(Design.Palette.charcoal))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("实时脱敏试测沙盒（纯本机零联网）")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI 隐私脱敏护盾")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($feedback)
    }
}

/// 全路由模型与多渠道并行基准测速体检 Sheet
struct AIRouteBenchmarkSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var results: [AIModelBenchmarkResult] = []
    @State private var isRunning = false
    @State private var activeTask: Task<Void, Never>?

    private let client = AIClient(timeout: 30)

    private struct BenchmarkTarget {
        let slotLabel: String
        let profileName: String
        let config: AIConfig
        let model: String
    }

    private func buildTargets() -> [BenchmarkTarget] {
        var list: [BenchmarkTarget] = []
        var seen = Set<String>()
        let c = appState.aiConfig

        func appendIfUnique(slot: String, profile: String, cfg: AIConfig, model: String) {
            let clean = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            let key = "\(cfg.provider.rawValue)|\(cfg.activeBaseURL)|\(clean)"
            guard seen.insert(key).inserted else { return }
            list.append(BenchmarkTarget(slotLabel: slot, profileName: profile, config: cfg, model: clean))
        }

        appendIfUnique(slot: "当前主模型", profile: "活跃渠道", cfg: c, model: c.activeModelName)
        if !c.fastModel.isEmpty {
            appendIfUnique(slot: "快模型路由", profile: "活跃渠道", cfg: c, model: c.fastModel)
        }
        if !c.deepModel.isEmpty {
            appendIfUnique(slot: "深模型路由", profile: "活跃渠道", cfg: c, model: c.deepModel)
        }
        if !c.visionModel.isEmpty {
            appendIfUnique(slot: "视觉模型路由", profile: "活跃渠道", cfg: c, model: c.visionModel)
        }
        for prof in c.profiles {
            let pCfg = c.applying(profile: prof)
            appendIfUnique(slot: "已存档案", profile: prof.name, cfg: pCfg, model: prof.model)
        }
        return list
    }

    private var fastestTTFT: Int {
        results.filter(\.ok).map(\.ttftMs).min() ?? 0
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("一键并行实测当前配置的「主 / 快 / 深 / 视觉」路由与全部已存渠道档案，对比首字延迟（TTFT）和吞吐速率（字/秒）。")
                            .font(.footnote)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)

                        if isRunning {
                            Button {
                                activeTask?.cancel()
                            } label: {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small).tint(Color(Design.Palette.error))
                                    Text("并行测速体检中… 点击停止")
                                }
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: false, wide: true, tint: Color(Design.Palette.error)))
                        } else {
                            Button {
                                runBenchmark()
                            } label: {
                                Label(results.isEmpty ? "开始全路由并发体检" : "重新并发体检", systemImage: "speedometer")
                            }
                            .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                            .disabled(!appState.aiConfig.isConfigured && appState.aiConfig.profiles.isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if results.isEmpty && !isRunning {
                    Section {
                        LXEmptyState(
                            icon: "speedometer",
                            title: "等待开始体检",
                            message: "将对 \(buildTargets().count) 个模型/渠道节点同时发起轻量探测请求。"
                        )
                    }
                } else {
                    Section("实测结果 · \(results.filter(\.ok).count) / \(results.count) 可用") {
                        ForEach(results) { r in
                            benchmarkRow(r)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("全路由模型体检")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        activeTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                activeTask?.cancel()
            }
        }
    }

    private func benchmarkRow(_ r: AIModelBenchmarkResult) -> some View {
        let isFastest = r.ok && fastestTTFT > 0 && r.ttftMs == fastestTTFT && results.filter(\.ok).count > 1
        let maxTTFT = max(1, results.filter(\.ok).map(\.ttftMs).max() ?? 1)
        let ratio = r.ok ? min(1.0, max(0.08, Double(r.ttftMs) / Double(maxTTFT))) : 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(r.ok ? Color(Design.Palette.success) : Color(Design.Palette.error))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(r.model)
                            .font(.footnote.weight(.semibold).monospaced())
                            .foregroundStyle(Color(Design.Palette.ink))
                            .lineLimit(1)
                        if isFastest {
                            LXTag(text: "最快", icon: "bolt.fill", tint: Color(Design.Palette.success), filled: true)
                        }
                    }
                    Text("\(r.slotLabel) · \(r.profileName)")
                        .font(.caption2)
                        .foregroundStyle(Color(Design.Palette.stone))
                }
                Spacer()
                if r.ok {
                    Text("\(r.ttftMs) ms")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(r.ttftMs < 1500 ? Color(Design.Palette.success) : Color(Design.Palette.ink))
                }
            }

            if r.ok {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(r.ttftMs < 1500 ? Color(Design.Palette.success) : Color(Design.Palette.accent))
                        .frame(width: max(12, geo.size.width * ratio), height: 6)
                }
                .frame(height: 6)

                LXFlowLayout(spacing: 6, lineSpacing: 4) {
                    LXTag(text: "首字 \(r.ttftMs)ms")
                    LXTag(text: "总计 \(r.totalMs)ms")
                    LXTag(text: String(format: "%.1f 字/秒", r.charsPerSecond))
                }
            } else if let err = r.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.error))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func runBenchmark() {
        let targets = buildTargets()
        guard !targets.isEmpty else { return }
        results = []
        isRunning = true

        activeTask = Task {
            defer {
                Task { @MainActor in
                    isRunning = false
                    appState.refreshAll()
                }
            }
            await withTaskGroup(of: AIModelBenchmarkResult.self) { group in
                for t in targets {
                    group.addTask {
                        await client.benchmarkModel(
                            config: t.config,
                            slotLabel: t.slotLabel,
                            profileName: t.profileName,
                            modelOverride: t.model
                        )
                    }
                }
                for await res in group {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        results.append(res)
                        results.sort { a, b in
                            if a.ok != b.ok { return a.ok }
                            return a.ttftMs < b.ttftMs
                        }
                    }
                }
            }
        }
    }
}
