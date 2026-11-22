import SwiftUI

// MARK: - 打字统计与本机习惯画像（M1.5 · 先建信任再谈上传）
///
/// 独立本机统计与习惯诊断页：
/// - 30 天打字量趋势 + 24 小时昼夜时段节律曲线
/// - 拼音易混音本机诊断矩阵 (zh↔z / an↔ang / in↔ing / n↔l)
/// - 个人词库四大领域分布 (科技研发 / 商务职场 / 日常社交 / 学术创作)
/// - 智能引擎调优建议一键应用
/// 数据 100% 来自本机 App Group（TypingStatsStore + TypingHabitTracker），不依赖登录，永不记录任何打字原文。
struct TypingStatsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var statsRefresh = 0
    @State private var appliedToast: String?

    var body: some View {
        Form {
            if let toast = appliedToast {
                Section {
                    Text(toast)
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.success))
                }
            }

            if appState.settings.typingStatsEnabled {
                overviewSection
                trendSection
                hourlyRhythmSection
                confusionMatrixSection
                lexiconDomainSection
                tuningRecommendationsSection
                trustAndCloudEntrySection
                dangerSection
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("零原文 · 纯本机打字习惯诊断", systemImage: "lock.shield.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(Design.Palette.ink))
                        Text("开启后仅在本机 App Group 统计每日字数趋势、24 小时昼夜节律与 16 组拼音易混音（如 zh/z、an/ang），自动反哺引擎调优建议。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(["30天趋势", "24h 节律", "易混音诊断"], id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(Design.Palette.surface))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    Toggle("开启本机打字统计与画像", isOn: $appState.settings.typingStatsEnabled)
                } footer: {
                    Text("密码、邮箱、网址输入框自动跳过；统计数据永不记录任何原文，可随时一键清空。")
                }
            }
        }
        .navigationTitle("打字统计与本机画像")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            statsRefresh += 1
            appState.refreshAll()
        }
    }

    // MARK: - 1. 总览指标与习惯标签

    private var overviewSection: some View {
        let _ = statsRefresh
        let summary = TypingStatsStore.shared.summary()
        let profile = appState.habitProfile
        return Section("本机总览与习惯标签") {
            Toggle("记录本机打字统计", isOn: $appState.settings.typingStatsEnabled)
            LabeledContent("今日字数", value: "\(summary.todayChars) 字")
            LabeledContent("累计字数", value: "\(max(summary.totalChars, profile.totalChars)) 字")
            LabeledContent("平均 / 峰值速度", value: String(format: "%.1f / %.0f 字/分", max(summary.averageCharsPerMinute, profile.avgCPM), profile.peakCPM))
            LabeledContent("平均上屏词长", value: String(format: "%.2f 字/词", profile.avgWordLength))
            LabeledContent("活跃时长", value: Self.formatActiveSeconds(summary.totalActiveSeconds))
            LabeledContent("连续打字", value: "\(summary.streakDays) 天（累计 \(summary.dayCount) 天）")

            if !profile.habitTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本机识别的打字习惯标签")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(profile.habitTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(Design.Palette.surface))
                                    .foregroundStyle(Color(Design.Palette.ink))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 2. 近 30 天趋势

    private var trendSection: some View {
        Section("近 30 天打字量趋势") {
            let entries = TypingStatsStore.shared.recentDays(limit: 30)
            if entries.isEmpty {
                Text("暂无按天趋势数据，日常打字上屏后自动在本机积累。")
                    .foregroundStyle(Color(Design.Palette.stone))
            } else {
                let maxChars = max(entries.map(\.chars).max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(entries) { entry in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color(Design.Palette.ink).opacity(entry.chars >= maxChars ? 1 : 0.35))
                                .frame(height: max(4, CGFloat(entry.chars) / CGFloat(maxChars) * 72))
                            Text(String(Int(entry.day.suffix(2)) ?? 0))
                                .font(.system(size: 8))
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("每日上屏字数，仅显示有记录的日期。")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            }
        }
    }

    // MARK: - 3. 24 小时打字时段分布曲线

    private var hourlyRhythmSection: some View {
        let rhythm = appState.habitProfile.hourlyRhythm
        let maxVal = max(rhythm.values.max() ?? 1, 1)
        return Section("24 小时打字活跃时段曲线") {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    let count = rhythm[String(hour)] ?? 0
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color(Design.Palette.ink).opacity(count > 0 ? 0.85 : 0.15))
                            .frame(height: max(4, CGFloat(count) / CGFloat(maxVal) * 56))
                        if hour % 4 == 0 {
                            Text(String(format: "%02d", hour))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(Color(Design.Palette.stone))
                        } else {
                            Text(" ")
                                .font(.system(size: 8))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
            Text("00:00–23:00 各时段累计击键分布，帮助了解昼夜创作高峰。")
                .font(.caption)
                .foregroundStyle(Color(Design.Palette.stone))
        }
    }

    // MARK: - 4. 拼音易混音本机诊断矩阵

    private var confusionMatrixSection: some View {
        let matrix = appState.habitProfile.confusionMatrix
        let pairs: [(key: String, label: String)] = [
            ("zh_z", "zh ↔ z 平翘舌"),
            ("ch_c", "ch ↔ c 平翘舌"),
            ("sh_s", "sh ↔ s 平翘舌"),
            ("n_l", "n ↔ l 鼻边音"),
            ("an_ang", "an ↔ ang 前后鼻音"),
            ("en_eng", "en ↔ eng 前后鼻音"),
            ("in_ing", "in ↔ ing 前后鼻音")
        ]
        return Section("拼音易混音本机纠错统计") {
            ForEach(pairs, id: \.key) { item in
                let count = matrix[item.key] ?? 0
                HStack {
                    Text(item.label)
                        .font(.subheadline)
                    Spacer()
                    Text("\(count) 次纠错")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(count >= 2 ? Color(Design.Palette.ink) : Color(Design.Palette.stone))
                }
            }
        }
    }

    // MARK: - 5. 个人词库领域偏好

    private var lexiconDomainSection: some View {
        let domainAnalysis = TypingHabitTracker.analyzeLexiconDomains(words: appState.userWords.map(\.word))
        let domains = ["科技与研发", "商务与职场", "日常与社交", "学术与创作"]
        return Section("个人词库领域分布（首选：\(domainAnalysis.primaryDomain)）") {
            ForEach(domains, id: \.self) { dom in
                let score = domainAnalysis.domainScores[dom] ?? 0
                HStack {
                    Text(dom)
                        .font(.subheadline)
                    Spacer()
                    Text("\(score) 词命中")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color(Design.Palette.stone))
                }
            }
        }
    }

    // MARK: - 6. 一键智能引擎调优建议

    private var tuningRecommendationsSection: some View {
        let recs = appState.habitProfile.tuningRecommendations
        return Section("基于打字习惯的一键引擎调优") {
            if recs.isEmpty {
                Text("当前击键准确率与上屏节奏表现优异，引擎参数已处于最佳平衡态。")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            } else {
                ForEach(recs) { rec in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(rec.title)
                                .font(.subheadline.bold())
                            Spacer()
                            Button("一键开启") {
                                appState.applyTuningRecommendation(rec)
                                appliedToast = "✓ 已应用调优建议：\(rec.title)"
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(Color(Design.Palette.ink))
                        }
                        Text(rec.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 7. 先建信任再谈上传

    private var trustAndCloudEntrySection: some View {
        Section {
            NavigationLink {
                CloudAccountView()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("需要将词库与习惯画像跨设备同步吗？")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("以上统计默认 100% 纯本机运行；若您希望多设备同步词库或在 Web 控制台查看报表，可按需开启 E2EE 云同步与脱敏分析授权。")
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.steel))
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("隐私优先 · 先建信任再谈上传")
        }
    }

    // MARK: - 8. 清除

    private var dangerSection: some View {
        Section {
            Button("清除全部本机统计与习惯数据", role: .destructive) {
                TypingStatsStore.shared.clearAll()
                TypingHabitTracker.shared.clearAllLocalHabits()
                appState.refreshAll()
                statsRefresh += 1
            }
        } footer: {
            Text("仅在本机按天记录字数、活跃时长与脱敏易混音计数，永不记录任何输入原文。")
        }
    }

    private static func formatActiveSeconds(_ seconds: TimeInterval) -> String {
        if seconds >= 3600 { return String(format: "%.1f 小时", seconds / 3600) }
        if seconds >= 60 { return String(format: "%.0f 分钟", seconds / 60) }
        return String(format: "%.0f 秒", seconds)
    }
}
