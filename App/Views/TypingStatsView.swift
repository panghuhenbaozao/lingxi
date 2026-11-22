import SwiftUI

// MARK: - 打字统计、26 键触控热力图校准与进化周报
///
/// - 每周输入进化周报卡片（字数、速度、AI 省时、高频自造词、优化建议）
/// - 26 键手型落点偏移自学习热力图 & 一键手型补偿开关/重置
/// - 30 天打字量趋势 + 24 小时昼夜时段节律曲线
/// - 拼音易混音本机诊断矩阵 + 个人词库领域偏好 + 一键智能引擎调优
struct TypingStatsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var statsRefresh = 0
    @State private var appliedToast: String?
    @State private var touchProfile: TouchCalibrationProfile = TouchOffsetCalibrator.shared.currentProfile()

    var body: some View {
        Form {
            if let toast = appliedToast {
                Section {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.success))
                }
            }

            weeklyEvolutionDigestSection
            overviewSection
            touchCalibrationHeatmapSection

            if appState.settings.typingStatsEnabled {
                trendSection
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("开启「每日字数趋势记录」可绘制近 30 天连续打卡曲线。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("记录近 30 天每日打字量趋势", isOn: $appState.settings.typingStatsEnabled)
                } footer: {
                    Text("密码、邮箱、网址输入框自动跳过；统计数据永不记录任何原文。")
                }
            }

            hourlyRhythmSection
            confusionMatrixSection
            lexiconDomainSection
            tuningRecommendationsSection
            trustAndCloudEntrySection
            dangerSection
        }
        .navigationTitle("打字进化与自学习")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            statsRefresh += 1
            touchProfile = TouchOffsetCalibrator.shared.currentProfile()
            appState.refreshAll()
        }
    }

    // MARK: - 0. 每周输入进化周报卡片

    private var weeklyEvolutionDigestSection: some View {
        let _ = statsRefresh
        let digest = AIAutoInsightService.buildWeeklyEvolutionDigest(
            profile: appState.habitProfile,
            stats: TypingStatsStore.shared.summary(),
            userWords: appState.userWords,
            ledger: appState.aiUsageLedger
        )
        return Section("✨ 我的灵犀进化周报") {
            VStack(alignment: .leading, spacing: 10) {
                Text(digest.headline)
                    .font(.headline)
                    .foregroundStyle(Color(Design.Palette.ink))

                HStack(spacing: 10) {
                    digestMetricPill(title: "累计字数", value: "\(digest.totalChars)")
                    digestMetricPill(title: "均速 CPM", value: String(format: "%.0f", digest.avgCPM))
                    digestMetricPill(title: "AI 省时", value: "\(digest.estimatedMinutesSavedByAI) 分")
                }

                if !digest.topLearnedWords.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最常自学习的高频私房词")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(digest.topLearnedWords, id: \.self) { w in
                                    Text(w)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(Color(Design.Palette.accentSoft))
                                        .foregroundStyle(Color(Design.Palette.accent))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                Text("💡 进化建议：\(digest.advice)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private func digestMetricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(Design.Palette.accent))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(Design.Palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 1. 总览指标与习惯标签

    private var overviewSection: some View {
        let _ = statsRefresh
        let summary = TypingStatsStore.shared.summary()
        let profile = appState.habitProfile
        return Section("本机习惯画像总览") {
            Toggle("记录近 30 天每日打字量趋势", isOn: $appState.settings.typingStatsEnabled)
            LabeledContent("今日字数", value: "\(summary.todayChars) 字")
            LabeledContent("累计字数", value: "\(max(summary.totalChars, profile.totalChars)) 字")
            LabeledContent("平均 / 峰值速度", value: String(format: "%.1f / %.0f 字/分", max(summary.averageCharsPerMinute, profile.avgCPM), profile.peakCPM))
            LabeledContent("平均上屏词长", value: String(format: "%.2f 字/词", profile.avgWordLength))
            LabeledContent("活跃时长", value: Self.formatActiveSeconds(summary.totalActiveSeconds))
            LabeledContent("连续打字", value: "\(summary.streakDays) 天（累计 \(summary.dayCount) 天）")

            if !profile.habitTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("自动识别的打字习惯标签")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    // MARK: - 2. 26 键手型落点偏移自学习热力图（越打越准）

    private var touchCalibrationHeatmapSection: some View {
        let rows: [[String]] = [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
            ["z", "x", "c", "v", "b", "n", "m"]
        ]
        let totalSamples = touchProfile.perKey.values.reduce(0) { $0 + $1.count }
        let calibratedKeys = touchProfile.perKey.values.filter { $0.count >= 5 }.count

        return Section {
            Toggle(
                "启用 26 键个人手型落点热区补偿",
                isOn: Binding(
                    get: { touchProfile.calibrationApplied },
                    set: { enabled in
                        TouchOffsetCalibrator.shared.setApplied(enabled)
                        touchProfile = TouchOffsetCalibrator.shared.currentProfile()
                        appliedToast = enabled ? "已开启个人手型热区自动补偿" : "已暂停热区补偿"
                    }
                )
            )

            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { key in
                            let stat = touchProfile.perKey[key]
                            let count = stat?.count ?? 0
                            let dx = stat?.avgDX ?? 0
                            let dy = stat?.avgDY ?? 0
                            let drift = hypot(dx, dy)
                            let intensity = min(1.0, drift / 8.0)
                            let arrow: String = {
                                guard count >= 3, drift >= 1.5 else { return count > 0 ? "•" : "" }
                                if abs(dx) >= abs(dy) { return dx > 0 ? "→" : "←" }
                                return dy > 0 ? "↓" : "↑"
                            }()
                            VStack(spacing: 1) {
                                Text(key.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(count >= 5 ? Color.white : Color(Design.Palette.ink))
                                Text(arrow.isEmpty ? " " : arrow)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(count >= 5 ? Color.white.opacity(0.9) : Color.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                count >= 5
                                    ? Color(Design.Palette.accent).opacity(0.45 + 0.55 * intensity)
                                    : (count > 0 ? Color(Design.Palette.accentSoft) : Color(Design.Palette.surface))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            HStack {
                Text("已采样 \(totalSamples) 次击键 · \(calibratedKeys)/26 键已收敛")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if totalSamples > 0 {
                    Button("重置校准") {
                        TouchOffsetCalibrator.shared.reset()
                        touchProfile = TouchOffsetCalibrator.shared.currentProfile()
                        appliedToast = "已重置 26 键触控手型采样数据"
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.error))
                }
            }
        } header: {
            Text("🎯 26 键手型触控落点自学习热力图")
        } footer: {
            Text("在键盘日常打字时静默记录每个字母按键中心偏移方向（如单手拇指偏右下），单键满 5 次后自动动态微调判定热区，越打越不误触。")
        }
    }

    // MARK: - 3. 近 30 天趋势

    private var trendSection: some View {
        Section("近 30 天打字量趋势") {
            let entries = TypingStatsStore.shared.recentDays(limit: 30)
            if entries.isEmpty {
                Text("暂无按天趋势数据，日常打字上屏后自动在本机积累。")
                    .foregroundStyle(.secondary)
            } else {
                let maxChars = max(entries.map(\.chars).max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(entries) { entry in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color(Design.Palette.accent).opacity(entry.chars >= maxChars ? 1 : 0.45))
                                .frame(height: max(4, CGFloat(entry.chars) / CGFloat(maxChars) * 72))
                            Text(String(Int(entry.day.suffix(2)) ?? 0))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("每日上屏字数，仅显示有记录的日期。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 4. 24 小时打字时段分布曲线

    private var hourlyRhythmSection: some View {
        let rhythm = appState.habitProfile.hourlyRhythm
        let maxVal = max(rhythm.values.max() ?? 1, 1)
        return Section("24 小时打字活跃时段曲线") {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    let count = rhythm[String(hour)] ?? 0
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(Design.Palette.accent).opacity(count > 0 ? 0.85 : 0.16))
                            .frame(height: max(4, CGFloat(count) / CGFloat(maxVal) * 56))
                        if hour % 4 == 0 {
                            Text(String(format: "%02d", hour))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(" ").font(.system(size: 8))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
            Text("00:00–23:00 各时段累计击键分布，帮助了解昼夜创作高峰。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 5. 拼音易混音本机诊断矩阵

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
                    Text(item.label).font(.subheadline)
                    Spacer()
                    Text("\(count) 次纠错")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(count >= 2 ? Color(Design.Palette.accent) : Color.secondary)
                }
            }
        }
    }

    // MARK: - 6. 个人词库领域偏好

    private var lexiconDomainSection: some View {
        let domainAnalysis = TypingHabitTracker.analyzeLexiconDomains(words: appState.userWords.map(\.word))
        let domains = ["科技与研发", "商务与职场", "日常与社交", "学术与创作"]
        return Section("个人词库领域分布（首选：\(domainAnalysis.primaryDomain)）") {
            ForEach(domains, id: \.self) { dom in
                let score = domainAnalysis.domainScores[dom] ?? 0
                HStack {
                    Text(dom).font(.subheadline)
                    Spacer()
                    Text("\(score) 词命中")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 7. 一键智能引擎调优建议

    private var tuningRecommendationsSection: some View {
        let recs = appState.habitProfile.tuningRecommendations
        return Section("基于打字习惯的一键引擎调优") {
            if recs.isEmpty {
                Text("当前击键准确率与上屏节奏表现优异，引擎参数已处于最佳平衡态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recs) { rec in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(rec.title).font(.subheadline.bold())
                            Spacer()
                            Button("一键开启") {
                                appState.applyTuningRecommendation(rec)
                                appliedToast = "✓ 已应用调优建议：\(rec.title)"
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(Color(Design.Palette.accent))
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

    // MARK: - 8. 隐私透明与云同步入口

    private var trustAndCloudEntrySection: some View {
        Section {
            NavigationLink {
                CloudAccountView()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("跨设备加密同步词库与习惯画像")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(Design.Palette.ink))
                    Text("以上自学习能力离线即可 100% 运行；前往「灵犀账号」可开启 Cloudflare E2EE 云同步并查看 10 类透明看板。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("隐私优先 · 透明同步")
        }
    }

    // MARK: - 9. 清除

    private var dangerSection: some View {
        Section {
            Button("清除全部本机统计、热力图与习惯数据", role: .destructive) {
                TypingStatsStore.shared.clearAll()
                TypingHabitTracker.shared.clearAllLocalHabits()
                TouchOffsetCalibrator.shared.reset()
                touchProfile = TouchOffsetCalibrator.shared.currentProfile()
                appState.refreshAll()
                statsRefresh += 1
            }
        } footer: {
            Text("仅在本机记录脱敏数值指标与按键落点偏移，永不记录任何输入原文。")
        }
    }

    private static func formatActiveSeconds(_ seconds: TimeInterval) -> String {
        if seconds >= 3600 { return String(format: "%.1f 小时", seconds / 3600) }
        if seconds >= 60 { return String(format: "%.0f 分钟", seconds / 60) }
        return String(format: "%.0f 秒", seconds)
    }
}
