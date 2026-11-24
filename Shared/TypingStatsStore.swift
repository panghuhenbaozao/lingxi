import Foundation

/// 打字统计（借鉴 WowType stats 模块）：仅在本机按天计数，不记录任何输入内容。
/// - 性能优化 v5.5：静态复用 `DateFormatter`，`recordCommit` 改为零阻塞异步入队 + `1.2s` 合并防抖写盘，
///   彻底消除每次上屏同步磁盘 `fsync` 与跨进程通知造成的打字掉帧卡顿。
struct TypingDailyStat: Codable, Equatable {
    /// 当天累计上屏字数（按 Unicode 字符计，含标点）
    var chars: Int = 0
    /// 活跃打字时长（秒）：两次上屏间隔 ≤30 秒才计入，防止挂后台虚增
    var activeSeconds: TimeInterval = 0
}

/// 趋势图单日数据点（仅含实际有记录的天）。
struct TypingDailyEntry: Identifiable {
    let day: String
    let chars: Int
    var id: String { day }
}

final class TypingStatsStore {
    static let shared = TypingStatsStore()
    private static let fileName = "typing_stats.json"
    /// 两次上屏间隔超过该阈值视为不活跃，不计入打字时长
    private static let activeGapThreshold: TimeInterval = 30
    /// 仅保留最近 N 天数据，避免 JSON 无限增长（连续天数统计不受清理影响）
    private static let retainedDays = 400
    /// 连续打字写盘防抖间隔（秒）：合并高频按键写入，避免每敲一字就写盘卡顿
    private static let persistDebounceInterval: TimeInterval = 1.2

    private static let sharedDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    private var days: [String: TypingDailyStat] = [:]
    private var lastCommitAt: Date?
    private var lastFileStamp: String?
    private var lastStampCheckTime: CFAbsoluteTime = 0
    private var dirty = false
    private var pendingPersistWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.lingxi.typingstats", qos: .utility)

    /// 仅测试代码直接实例化（避免共享单例在测试间串状态）；业务代码一律使用 `shared`
    init() {
        load()
    }

    /// 仅在 `queue` 内调用，复用静态 `DateFormatter` 避免高频分配
    private static func dayKeyLocked(for date: Date = Date()) -> String {
        sharedDayFormatter.string(from: date)
    }

    private func load() {
        queue.sync {
            reloadIfChangedLocked(force: true)
        }
    }

    /// 跨进程热重载：键盘扩展写入新字数后，主 App 无需杀进程重启即可实时读取最新统计。
    func reloadFromDisk() {
        queue.sync {
            reloadIfChangedLocked(force: true)
        }
    }

    /// 键盘退场前强制立即落盘（零丢失）
    func flush() {
        queue.sync {
            pendingPersistWork?.cancel()
            pendingPersistWork = nil
            persistLocked()
        }
    }

    private func reloadIfChangedLocked(force: Bool = false, allowThrottle: Bool = false) {
        let nowMono = CFAbsoluteTimeGetCurrent()
        // 有未落盘脏数据时优先以内存最新值为准，避免被磁盘旧值覆盖；仅热路径 recordCommit 允许 1.0s stat 节流
        if !force {
            if dirty { return }
            if allowThrottle && nowMono - lastStampCheckTime < 1.0 { return }
        }
        lastStampCheckTime = nowMono
        let stamp = AppGroup.fileStamp(of: Self.fileName)
        if !force, stamp == lastFileStamp {
            return
        }
        days = AppGroup.readJSON([String: TypingDailyStat].self, from: Self.fileName) ?? [:]
        lastFileStamp = stamp
    }

    /// 记录一次上屏（字数按 text 的字符数计）。调用方需已确认开关开启且非隐私输入框。
    /// 零主线程阻塞：异步更新内存计数并防抖合并写盘，单次调用耗时 < 0.01ms。
    func recordCommit(text: String, at now: Date = Date()) {
        let count = text.count
        guard count > 0 else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.reloadIfChangedLocked(allowThrottle: true)
            let key = Self.dayKeyLocked(for: now)
            var stat = self.days[key] ?? TypingDailyStat()
            stat.chars += count
            if let last = self.lastCommitAt {
                let gap = now.timeIntervalSince(last)
                if gap > 0, gap <= Self.activeGapThreshold {
                    stat.activeSeconds += gap
                }
            }
            self.lastCommitAt = now
            self.days[key] = stat
            self.dirty = true
            self.pruneLocked()
            self.schedulePersistLocked()
        }
    }

    private func schedulePersistLocked() {
        pendingPersistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingPersistWork = nil
            self?.persistLocked()
        }
        pendingPersistWork = work
        queue.asyncAfter(deadline: .now() + Self.persistDebounceInterval, execute: work)
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

    func summary(now: Date = Date()) -> Summary {
        queue.sync {
            reloadIfChangedLocked()
            return summarizeLocked(now: now)
        }
    }

    private func summarizeLocked(now: Date) -> Summary {
        let totalChars = days.values.reduce(0) { $0 + $1.chars }
        let totalSeconds = days.values.reduce(0.0) { $0 + $1.activeSeconds }
        let minutes = totalSeconds / 60
        let cpm = minutes > 0.5 ? Double(totalChars) / minutes : 0
        let todayKey = Self.dayKeyLocked(for: now)
        let todayChars = days[todayKey]?.chars ?? 0
        // 连续天数：从今天（若今天无记录则从昨天）向前倒推连续有记录的天数
        var streak = 0
        var cursor = now
        if days[todayKey] == nil {
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while days[Self.dayKeyLocked(for: cursor)] != nil {
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

    /// 最近 N 天窗口内有记录的数据点（按日期升序），供趋势图展示。
    func recentDays(limit: Int, now: Date = Date()) -> [TypingDailyEntry] {
        queue.sync {
            reloadIfChangedLocked()
            let cutoffDay = Self.dayKeyLocked(
                for: Calendar.current.date(byAdding: .day, value: -(limit - 1), to: now) ?? now
            )
            return days
                .filter { $0.key >= cutoffDay }
                .sorted { $0.key < $1.key }
                .prefix(limit)
                .map { TypingDailyEntry(day: $0.key, chars: $0.value.chars) }
        }
    }

    /// 清除全部统计数据（设置页「清除统计」按钮调用）。
    func clearAll() {
        queue.sync {
            pendingPersistWork?.cancel()
            pendingPersistWork = nil
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
            lastFileStamp = AppGroup.fileStamp(of: Self.fileName)
            lastStampCheckTime = CFAbsoluteTimeGetCurrent()
            AppGroupNotifications.post(AppGroupNotifications.statsChanged)
        }
    }
}
