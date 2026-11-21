import Foundation
/// 打字统计（借鉴 WowType stats 模块）：仅在本机按天计数，不记录任何输入内容。
/// - 统计维度：总字数、活跃打字时长（秒）、平均速度（字/分）、连续打字天数；
/// - 隐私策略：密码框/邮箱/网址框由键盘侧跳过埋点；数据仅存 App Group JSON，可随时一键清除；
/// - 默认关闭，需在设置中手动开启 `typingStatsEnabled`。
struct TypingDailyStat: Codable, Equatable {
    /// 当天累计上屏字数（按 Unicode 字符计，含标点）
    var chars: Int = 0
    /// 活跃打字时长（秒）：两次上屏间隔 ≤30 秒才计入，防止挂后台虚增
    var activeSeconds: TimeInterval = 0
}
final class TypingStatsStore {
    static let shared = TypingStatsStore()
    private static let fileName = "typing_stats.json"
    /// 两次上屏间隔超过该阈值视为不活跃，不计入打字时长
    private static let activeGapThreshold: TimeInterval = 30
    /// 仅保留最近 N 天数据，避免 JSON 无限增长（连续天数统计不受清理影响）
    private static let retainedDays = 400
    private var days: [String: TypingDailyStat] = [:]
    private var lastCommitAt: Date?
    private var dirty = false
    private let queue = DispatchQueue(label: "com.lingxi.typingstats", qos: .utility)
    /// 仅测试代码直接实例化（避免共享单例在测试间串状态）；业务代码一律使用 `shared`
    init() {
        load()
    }
    private static func dayKey(for date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
    private func load() {
        queue.sync {
            days = AppGroup.readJSON([String: TypingDailyStat].self, from: Self.fileName) ?? [:]
        }
    }
    /// 记录一次上屏（字数按 text 的字符数计）。调用方需已确认开关开启且非隐私输入框。
    func recordCommit(text: String, at now: Date = Date()) {
        let count = text.count
        guard count > 0 else { return }
        queue.sync {
            let key = Self.dayKey(for: now)
            var stat = days[key] ?? TypingDailyStat()
            stat.chars += count
            if let last = lastCommitAt {
                let gap = now.timeIntervalSince(last)
                if gap > 0, gap <= Self.activeGapThreshold {
                    stat.activeSeconds += gap
                }
            }
            lastCommitAt = now
            days[key] = stat
            dirty = true
            pruneLocked()
            persistLocked()
        }
    }
    /// 汇总数据：总字数、总活跃时长、平均速度（字/分）、连续天数、今日字数。
    struct Summary: Equatable {
        let totalChars: Int
        let totalActiveSeconds: TimeInterval
        let averageCharsPerMinute: Double
        let streakDays: Int
        let todayChars: Int
        let dayCount: Int
    }
    func summary() -> Summary {
        queue.sync {
            summarizeLocked()
        }
    }
    private func summarizeLocked() -> Summary {
        let totalChars = days.values.reduce(0) { $0 + $1.chars }
        let totalSeconds = days.values.reduce(0.0) { $0 + $1.activeSeconds }
        let minutes = totalSeconds / 60
        let cpm = minutes > 0.5 ? Double(totalChars) / minutes : 0
        let todayKey = Self.dayKey()
        let todayChars = days[todayKey]?.chars ?? 0
        // 连续天数：从今天（若今天无记录则从昨天）向前倒推连续有记录的天数
        var streak = 0
        var cursor = Date()
        if days[todayKey] == nil {
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while days[Self.dayKey(for: cursor)] != nil {
            streak += 1
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return Summary(
            totalChars: totalChars,
            totalActiveSeconds: totalSeconds,
            averageCharsPerMinute: cpm,
            streakDays: streak,
            todayChars: todayChars,
            dayCount: days.count
        )
    }
    /// 清除全部统计数据（设置页「清除统计」按钮调用）。
    func clearAll() {
        queue.sync {
            days = [:]
            lastCommitAt = nil
            dirty = true
            persistLocked()
        }
    }
    private func pruneLocked() {
        guard days.count > Self.retainedDays else { return }
        let sortedKeys = days.keys.sorted()
        let dropCount = days.count - Self.retainedDays
        for key in sortedKeys.prefix(dropCount) {
            days.removeValue(forKey: key)
        }
    }
    private func persistLocked() {
        guard dirty else { return }
        if AppGroup.writeJSON(days, to: Self.fileName) {
            dirty = false
        }
    }
}
