import SwiftUI

// MARK: - 打字统计（M1.5）
///
/// 独立统计页：总览指标 + 近 30 天趋势。
/// 数据全部来自本机 TypingStatsStore（App Group JSON），不记录任何输入内容；
/// 密码、邮箱、网址输入框由键盘侧跳过埋点，数据可随时一键清除。
struct TypingStatsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var statsRefresh = 0

    var body: some View {
        Form {
            if appState.settings.typingStatsEnabled {
                overviewSection
                trendSection
                dangerSection
            } else {
                Section {
                    Toggle("打字统计（仅本机按天计数）", isOn: $appState.settings.typingStatsEnabled)
                } footer: {
                    Text("开启后，键盘在本机按天记录字数与活跃打字时长；密码、邮箱、网址输入框自动跳过，数据可随时一键清除。")
                }
            }
        }
        .navigationTitle("打字统计")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { statsRefresh += 1 }
    }

    // MARK: 总览

    private var overviewSection: some View {
        let _ = statsRefresh
        let summary = TypingStatsStore.shared.summary()
        return Section("总览") {
            Toggle("记录打字数据", isOn: $appState.settings.typingStatsEnabled)
            LabeledContent("今日字数", value: "\(summary.todayChars)")
            LabeledContent("累计字数", value: "\(summary.totalChars)")
            LabeledContent("平均速度", value: String(format: "%.1f 字/分", summary.averageCharsPerMinute))
            LabeledContent("活跃时长", value: Self.formatActiveSeconds(summary.totalActiveSeconds))
            LabeledContent("连续打字", value: "\(summary.streakDays) 天")
            LabeledContent("记录天数", value: "\(summary.dayCount) 天")
        }
    }

    // MARK: 近 30 天趋势（轻量条形图，不依赖 Charts 框架）

    private var trendSection: some View {
        Section("近 30 天趋势") {
            let entries = TypingStatsStore.shared.recentDays(limit: 30)
            if entries.isEmpty {
                Text("暂无数据，打字后自动积累。")
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
                Text("每日上屏字数，仅显示有记录的日子。")
                    .font(.caption)
                    .foregroundStyle(Color(Design.Palette.stone))
            }
        }
    }

    // MARK: 清除

    private var dangerSection: some View {
        Section {
            Button("清除全部统计数据", role: .destructive) {
                TypingStatsStore.shared.clearAll()
                statsRefresh += 1
            }
        } footer: {
            Text("仅在本机按天记录字数与活跃打字时长，不记录任何输入内容。")
        }
    }

    private static func formatActiveSeconds(_ seconds: TimeInterval) -> String {
        if seconds >= 3600 { return String(format: "%.1f 小时", seconds / 3600) }
        if seconds >= 60 { return String(format: "%.0f 分钟", seconds / 60) }
        return String(format: "%.0f 秒", seconds)
    }
}
