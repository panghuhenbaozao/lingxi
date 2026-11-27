import SwiftUI

// MARK: - 打字统计、26 键触控热力图校准与进化周报
///
/// 结构（从「一眼看懂」到「深入了解」）：
/// 1. 总览：今日 / 累计 / 速度 / 连续天数 + 一句话周报与建议
/// 2. 近 30 天趋势（按日历补齐空白天，不再跳过没打字的日子）
/// 3. 24 小时活跃时段（标出高峰时段）
/// 4. 习惯标签 + 引擎调优建议（一键应用）
/// 5. 易混音统计（达到阈值可直接开启对应模糊音）
/// 6. 26 键触控热力图（带图例）
/// 7. 词库领域分布
/// 8. 隐私说明 + 清除数据（二次确认）
struct TypingStatsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var toast: String?
    @State private var touchProfile: TouchCalibrationProfile = TouchCalibrationProfile()  // 真实数据在 onAppear 读取
    @State private var confirmClearAll = false
    @State private var confirmResetCalibration = false
    /// 以下统计需要读盘和遍历词库：只在进入页面 / 数据变化后计算，避免每次刷新界面（如弹出提示）都重算
    @State private var digest: WeeklyEvolutionDigest?
    @State private var dayBars: [DayBar] = []
    @State private var domainAnalysis: LexiconDomainAffinity?

    var body: some View {
        Form {
            overviewSection
            trendSection
            hourlyRhythmSection
            habitAndTuningSection
            confusionMatrixSection
            touchCalibrationHeatmapSection
            lexiconDomainSection
            privacySection
        }
        .navigationTitle("打字统计")
        .navigationBarTitleDisplayMode(.inline)
        .lxToast($toast)
        .onAppear {
            appState.refreshAll()
            reloadDerivedStats()
        }
        .onChange(of: appState.settings.typingStatsEnabled) { _ in
            reloadDerivedStats()
        }
        .confirmationDialog("清除全部打字数据？", isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                TypingStatsStore.shared.clearAll()
                TypingHabitTracker.shared.clearAllLocalHabits()
                TouchOffsetCalibrator.shared.reset()
                appState.refreshAll()
                reloadDerivedStats()
                toast = "已清除全部打字数据"
            }
        } message: {
            Text("字数统计、每日趋势、时段分布、习惯画像和按键校准都会被清空，无法恢复。")
        }
        .confirmationDialog("重置按键校准？", isPresented: $confirmResetCalibration, titleVisibility: .visible) {
            Button("重置", role: .destructive) {
                TouchOffsetCalibrator.shared.reset()
                touchProfile = TouchOffsetCalibrator.shared.currentProfile()
                toast = "已重置按键校准"
            }
        } message: {
            Text("键盘会重新学习你的按键落点，前几天的防误触效果会暂时回到默认。")
        }
    }

    // MARK: - 1. 总览

    private var overviewSection: some View {
        let summary = appState.typingStatsSummary
        let profile = appState.habitProfile
        let avgSpeed = max(summary.averageCharsPerMinute, profile.avgCPM)
        let total = max(summary.totalChars, profile.totalChars)

        return Section {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    statTile("今日上屏", value: summary.todayChars.formatted(), unit: "字", icon: "keyboard")
                    statTile("累计上屏", value: total.formatted(), unit: "字", icon: "text.alignleft")
                }
                HStack(spacing: 10) {
                    statTile(
                        "平均速度",
                        value: avgSpeed > 0.5 ? String(format: "%.0f", avgSpeed) : "--",
                        unit: avgSpeed > 0.5 ? "字/分" : "",
                        icon: "speedometer",
                        detail: profile.peakCPM > 0.5 ? String(format: "最快 %.0f 字/分", profile.peakCPM) : nil
                    )
                    statTile(
                        "连续打字",
                        value: "\(summary.streakDays)",
                        unit: "天",
                        icon: "flame",
                        detail: summary.dayCount > 0 ? "共 \(summary.dayCount) 天有记录" : nil
                    )
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if let digest {
            VStack(alignment: .leading, spacing: 10) {
                Text(digest.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.ink))
                    .fixedSize(horizontal: false, vertical: true)
                LXFlowLayout(spacing: 6, lineSpacing: 6) {
                    LXTag(text: "活跃 \(Self.formatActiveSeconds(summary.totalActiveSeconds))", icon: "clock")
                    if digest.estimatedMinutesSavedByAI > 0 {
                        LXTag(text: "AI 省时约 \(digest.estimatedMinutesSavedByAI) 分钟", icon: "sparkles", tint: Color(Design.Palette.accent), filled: true)
                    }
                    if profile.avgWordLength > 0 {
                        LXTag(text: String(format: "平均每词 %.1f 字", profile.avgWordLength))
                    }
                }
                if !digest.advice.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.accent))
                            .padding(.top, 1)
                        Text(digest.advice)
                            .font(.footnote)
                            .foregroundStyle(Color(Design.Palette.charcoal))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(Design.Palette.accentSoft), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if !digest.topLearnedWords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("最近学会的常用词")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(Design.Palette.stone))
                        LXFlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(digest.topLearnedWords, id: \.self) { w in
                                LXTag(text: w, tint: Color(Design.Palette.accent), filled: true)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            }
        } header: {
            Text("总览")
        }
    }

    private func statTile(_ title: String, value: String, unit: String, icon: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(Design.Palette.accent))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(Color(Design.Palette.stone))
                }
            }
            Text(detail ?? " ")
                .font(.caption2)
                .foregroundStyle(Color(Design.Palette.stone))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(Design.Palette.canvas), in: RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.cardSmall, style: .continuous)
                .stroke(Color(Design.Palette.hairline), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - 2. 近 30 天趋势（按日历补齐 30 天）

    private static let dayFormatter: DateFormatter = {
        // 与 TypingStatsStore 的日期键格式保持一致
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    private struct DayBar: Identifiable {
        let key: String
        let date: Date
        let chars: Int
        var id: String { key }
    }

    private func last30Days() -> [DayBar] {
        let recorded = Dictionary(
            TypingStatsStore.shared.recentDays(limit: 30).map { ($0.day, $0.chars) },
            uniquingKeysWith: { a, _ in a }
        )
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        return (0..<30).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = Self.dayFormatter.string(from: date)
            return DayBar(key: key, date: date, chars: recorded[key] ?? 0)
        }
    }

    @ViewBuilder
    private var trendSection: some View {
        if appState.settings.typingStatsEnabled {
            let bars = dayBars
            let maxChars = max(bars.map(\.chars).max() ?? 0, 1)
            let activeDays = bars.filter { $0.chars > 0 }.count
            let total30 = bars.reduce(0) { $0 + $1.chars }
            let todayKey = bars.last?.key
            Section {
                if activeDays == 0 {
                    LXEmptyState(
                        icon: "chart.bar",
                        title: "还没有趋势数据",
                        message: "用灵犀键盘打字后，每天的上屏字数会自动记录在这里。"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(total30.formatted())
                                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text("字 · \(activeDays) 天有打字")
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                            Spacer()
                            Text("日均 \((total30 / max(activeDays, 1)).formatted())")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(bars) { bar in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(barColor(chars: bar.chars, isToday: bar.key == todayKey))
                                    .frame(height: bar.chars > 0 ? max(4, CGFloat(bar.chars) / CGFloat(maxChars) * 80) : 2)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 80, alignment: .bottom)
                        HStack {
                            Text(bars.first.map { $0.date.formatted(.dateTime.month(.defaultDigits).day()) } ?? "")
                            Spacer()
                            Text("今天")
                        }
                        .font(.caption2)
                        .foregroundStyle(Color(Design.Palette.stone))
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("近 30 天共上屏 \(total30) 字，其中 \(activeDays) 天有打字")
                }
            } header: {
                Text("近 30 天")
            }
        } else {
            Section {
                LXToggleRow(
                    "记录每日打字量",
                    subtitle: "开启后可以查看近 30 天趋势和连续打字天数",
                    isOn: $appState.settings.typingStatsEnabled
                )
            } header: {
                Text("近 30 天")
            } footer: {
                Text("只记录字数和时长，不记录任何输入内容；密码、邮箱、网址输入框自动跳过。")
            }
        }
    }

    private func barColor(chars: Int, isToday: Bool) -> Color {
        if chars == 0 { return Color(Design.Palette.hairline) }
        return Color(Design.Palette.accent).opacity(isToday ? 1 : 0.55)
    }

    // MARK: - 3. 24 小时活跃时段

    private var hourlyRhythmSection: some View {
        let rhythm = appState.habitProfile.hourlyRhythm
        let counts = (0..<24).map { rhythm[String($0)] ?? 0 }
        let maxVal = max(counts.max() ?? 0, 1)
        let hasData = counts.contains { $0 > 0 }
        let peakHour = counts.firstIndex(of: counts.max() ?? 0) ?? 0

        return Section {
            if !hasData {
                LXEmptyState(
                    icon: "clock",
                    title: "还没有时段数据",
                    message: "多打几天字，就能看出你一天里什么时候打字最多。"
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("高峰时段")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                        Text(String(format: "%02d:00 – %02d:00", peakHour, (peakHour + 1) % 24))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color(Design.Palette.ink))
                    }
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<24, id: \.self) { hour in
                            let count = counts[hour]
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(count == 0
                                      ? Color(Design.Palette.hairline)
                                      : Color(Design.Palette.accent).opacity(hour == peakHour ? 1 : 0.55))
                                .frame(height: count > 0 ? max(4, CGFloat(count) / CGFloat(maxVal) * 60) : 2)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 60, alignment: .bottom)
                    HStack(spacing: 0) {
                        ForEach([0, 6, 12, 18], id: \.self) { h in
                            Text(String(format: "%02d", h))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("24")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(Design.Palette.stone))
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(format: "打字高峰在 %d 点到 %d 点", peakHour, (peakHour + 1) % 24))
            }
        } header: {
            Text("一天中的打字时段")
        }
    }

    // MARK: - 4. 习惯标签与调优建议

    @ViewBuilder
    private var habitAndTuningSection: some View {
        let profile = appState.habitProfile
        let recs = profile.tuningRecommendations
        if !profile.habitTags.isEmpty || !recs.isEmpty {
            Section {
                if !profile.habitTags.isEmpty {
                    LXFlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(profile.habitTags, id: \.self) { tag in
                            LXTag(text: tag)
                        }
                    }
                    .padding(.vertical, 6)
                }
                ForEach(recs) { rec in
                    HStack(alignment: .center, spacing: 12) {
                        LXIconTile(icon: "wand.and.stars")
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
                        Button("开启") {
                            appState.applyTuningRecommendation(rec)
                            toast = "已开启「\(rec.title)」"
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("你的打字习惯")
            } footer: {
                if !recs.isEmpty {
                    Text("根据你的打字节奏和纠错情况自动给出，开启后可在「设置」里随时关闭。")
                }
            }
        }
    }

    // MARK: - 5. 易混音统计（可直接开启对应模糊音）

    private struct ConfusionPair: Identifiable {
        let key: String
        let pair: String
        let kind: String
        let fuzzyKeyPath: WritableKeyPath<FuzzyPinyinOptions, Bool>
        var id: String { key }
    }

    private let confusionPairs: [ConfusionPair] = [
        ConfusionPair(key: "zh_z", pair: "zh ↔ z", kind: "平翘舌", fuzzyKeyPath: \.zhZ),
        ConfusionPair(key: "ch_c", pair: "ch ↔ c", kind: "平翘舌", fuzzyKeyPath: \.chC),
        ConfusionPair(key: "sh_s", pair: "sh ↔ s", kind: "平翘舌", fuzzyKeyPath: \.shS),
        ConfusionPair(key: "n_l", pair: "n ↔ l", kind: "鼻边音", fuzzyKeyPath: \.nl),
        ConfusionPair(key: "an_ang", pair: "an ↔ ang", kind: "前后鼻音", fuzzyKeyPath: \.anAng),
        ConfusionPair(key: "en_eng", pair: "en ↔ eng", kind: "前后鼻音", fuzzyKeyPath: \.enEng),
        ConfusionPair(key: "in_ing", pair: "in ↔ ing", kind: "前后鼻音", fuzzyKeyPath: \.inIng),
    ]

    private var confusionMatrixSection: some View {
        let matrix = appState.habitProfile.confusionMatrix
        let maxCount = max(confusionPairs.map { matrix[$0.key] ?? 0 }.max() ?? 0, 1)
        let anyData = confusionPairs.contains { (matrix[$0.key] ?? 0) > 0 }

        return Section {
            if !anyData {
                LXEmptyState(
                    icon: "checkmark.seal",
                    title: "暂时没发现易混音",
                    message: "如果你常把 zh 打成 z、in 打成 ing，这里会统计出来并建议开启对应模糊音。"
                )
            } else {
                ForEach(confusionPairs) { item in
                    let count = matrix[item.key] ?? 0
                    let enabled = appState.settings.fuzzy[keyPath: item.fuzzyKeyPath]
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(item.pair)
                                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text(item.kind)
                                .font(.caption)
                                .foregroundStyle(Color(Design.Palette.stone))
                            Spacer(minLength: 6)
                            Text("\(count) 次")
                                .font(.caption.monospacedDigit().weight(count >= 2 ? .semibold : .regular))
                                .foregroundStyle(count >= 2 ? Color(Design.Palette.ink) : Color(Design.Palette.stone))
                            if enabled {
                                LXTag(text: "已开模糊音", icon: "checkmark", tint: Color(Design.Palette.success), filled: true)
                            } else if count >= 2 {
                                Button("开启模糊音") {
                                    appState.settings.fuzzy[keyPath: item.fuzzyKeyPath] = true
                                    toast = "已开启 \(item.pair) 模糊音"
                                }
                                .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(Design.Palette.surface))
                                Capsule()
                                    .fill(count >= 2 ? Color(Design.Palette.accent) : Color(Design.Palette.hairline))
                                    .frame(width: count > 0 ? max(6, geo.size.width * CGFloat(count) / CGFloat(maxCount)) : 0)
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("易混音纠错")
        } footer: {
            if anyData {
                Text("统计的是键盘帮你自动纠正的次数。同一组超过 2 次，建议开启对应模糊音。")
            }
        }
    }

    // MARK: - 6. 26 键触控热力图

    private var touchCalibrationHeatmapSection: some View {
        let rows: [[String]] = [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
            ["z", "x", "c", "v", "b", "n", "m"]
        ]
        let totalSamples = touchProfile.perKey.values.reduce(0) { $0 + $1.count }
        let calibratedKeys = touchProfile.perKey.values.filter { $0.count >= 5 }.count

        return Section {
            LXToggleRow(
                "按我的手型校准按键",
                subtitle: "根据你习惯按偏的方向，自动微调每个键的判定范围",
                isOn: Binding(
                    get: { touchProfile.calibrationApplied },
                    set: { enabled in
                        TouchOffsetCalibrator.shared.setApplied(enabled)
                        touchProfile = TouchOffsetCalibrator.shared.currentProfile()
                        toast = enabled ? "已开启按键校准" : "已暂停按键校准"
                    }
                )
            )

            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { key in
                            heatKey(key)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .opacity(touchProfile.calibrationApplied ? 1 : 0.5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("已校准 \(calibratedKeys) 个按键，共采样 \(totalSamples) 次")

            HStack(spacing: 12) {
                legendItem(color: Color(Design.Palette.surface), text: "未采样")
                legendItem(color: Color(Design.Palette.accentSoft), text: "学习中")
                legendItem(color: Color(Design.Palette.accent), text: "已校准")
                Spacer(minLength: 0)
                Text("箭头 = 习惯按偏的方向")
                    .font(.caption2)
                    .foregroundStyle(Color(Design.Palette.stone))
            }

            HStack {
                Text("\(calibratedKeys)/26 键已校准 · 采样 \(totalSamples.formatted()) 次")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
                Spacer()
                if totalSamples > 0 {
                    Button("重置") {
                        confirmResetCalibration = true
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color(Design.Palette.error))
                    .buttonStyle(.plain)
                    .frame(minHeight: 32)
                }
            }
        } header: {
            Text("按键落点校准")
        } footer: {
            Text("日常打字时静默学习，每个键按满 5 次后开始校准，越用越不容易按错。只记录偏移方向，不记录按了什么。")
        }
    }

    private func heatKey(_ key: String) -> some View {
        let stat = touchProfile.perKey[key]
        let count = stat?.count ?? 0
        let dx = stat?.avgDX ?? 0
        let dy = stat?.avgDY ?? 0
        let drift = hypot(dx, dy)
        let intensity = min(1.0, drift / 8.0)
        let calibrated = count >= 5
        let arrow: String = {
            guard count >= 3, drift >= 1.5 else { return " " }
            if abs(dx) >= abs(dy) { return dx > 0 ? "→" : "←" }
            return dy > 0 ? "↓" : "↑"
        }()
        return VStack(spacing: 1) {
            Text(key.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(calibrated ? Color.white : Color(Design.Palette.ink))
            Text(arrow)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(calibrated ? Color.white.opacity(0.9) : Color(Design.Palette.stone))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(
            calibrated
                ? Color(Design.Palette.accent).opacity(0.55 + 0.45 * intensity)
                : (count > 0 ? Color(Design.Palette.accentSoft) : Color(Design.Palette.surface)),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Color(Design.Palette.hairline), lineWidth: 0.5))
                .frame(width: 12, height: 12)
            Text(text)
                .font(.caption2)
                .foregroundStyle(Color(Design.Palette.stone))
        }
    }

    // MARK: - 7. 词库领域分布

    @ViewBuilder
    private var lexiconDomainSection: some View {
        let analysis = domainAnalysis ?? LexiconDomainAffinity()
        let domains = ["科技与研发", "商务与职场", "日常与社交", "学术与创作"]
        let scores = domains.map { analysis.domainScores[$0] ?? 0 }
        let maxScore = max(scores.max() ?? 0, 1)
        if scores.contains(where: { $0 > 0 }) {
            Section {
                ForEach(Array(domains.enumerated()), id: \.offset) { idx, dom in
                    let score = scores[idx]
                    let isPrimary = dom == analysis.primaryDomain
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(dom)
                                .font(.subheadline.weight(isPrimary ? .semibold : .regular))
                                .foregroundStyle(Color(Design.Palette.ink))
                            if isPrimary {
                                LXTag(text: "最常用", tint: Color(Design.Palette.accent), filled: true)
                            }
                            Spacer()
                            Text("\(score) 个词")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color(Design.Palette.stone))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(Design.Palette.surface))
                                Capsule()
                                    .fill(Color(Design.Palette.accent).opacity(isPrimary ? 1 : 0.5))
                                    .frame(width: score > 0 ? max(6, geo.size.width * CGFloat(score) / CGFloat(maxScore)) : 0)
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("词库领域")
            } footer: {
                Text("根据键盘学会的 \(appState.userWords.count) 个词自动归类，AI 生成内容时会参考你的常用领域。")
            }
        }
    }

    // MARK: - 8. 隐私与清除

    private var privacySection: some View {
        Section {
            NavigationLink {
                CloudAccountView()
            } label: {
                LXNavRow(
                    icon: "lock.icloud",
                    title: "在多台设备间同步",
                    subtitle: "以上统计离线可用；登录后可端到端加密同步"
                )
            }
            Button(role: .destructive) {
                confirmClearAll = true
            } label: {
                Text("清除全部打字数据")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
        } header: {
            Text("数据与隐私")
        } footer: {
            Text("这里所有数据只在本机记录字数、时长和按键偏移等数字，永不记录任何输入内容。")
        }
    }

    /// 重新计算周报、30 天柱状图和词库领域（读盘 + 遍历词库，只在需要时调用）
    private func reloadDerivedStats() {
        touchProfile = TouchOffsetCalibrator.shared.currentProfile()
        digest = AIAutoInsightService.buildWeeklyEvolutionDigest(
            profile: appState.habitProfile,
            stats: appState.typingStatsSummary,
            userWords: appState.userWords,
            ledger: appState.aiUsageLedger
        )
        dayBars = appState.settings.typingStatsEnabled ? last30Days() : []
        domainAnalysis = TypingHabitTracker.analyzeLexiconDomains(words: appState.userWords.map(\.word))
    }

    private static func formatActiveSeconds(_ seconds: TimeInterval) -> String {
        if seconds >= 3600 { return String(format: "%.1f 小时", seconds / 3600) }
        if seconds >= 60 { return String(format: "%.0f 分钟", seconds / 60) }
        return String(format: "%.0f 秒", seconds)
    }
}
