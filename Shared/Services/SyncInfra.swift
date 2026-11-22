import Foundation

// MARK: - 同步客户端地基（M2，对齐 ADR 0001）
///
/// 为 M3 云同步准备的全部离线可验证组件：
/// - 设备身份：稳定 device_id（LWW 全序决胜的第二排序键）；
/// - Lamport 逻辑时钟：本地写入 tick()、收到远端 observe(remote:)，崩溃后只增不减；
/// - LWW 合并引擎：纯函数、可完整单元测试，云实现（M3）只负责搬运 SyncChange。

/// 稳定设备身份：首次运行生成 UUID 并持久化于 App Group。
/// deviceID 变化（如容器损坏重建）不影响数据完整性，仅影响同刻决胜排序。
public struct DeviceIdentity: Equatable, Codable {
    public let deviceID: String
    public let createdAt: Date
}

public enum SyncInfra {

    static let deviceFileName = "lingxi_device.json"
    static let lamportFileName = "lingxi_lamport.json"

    /// 读取或创建设备身份（App Group 不可用时退回进程私有目录，语义一致）
    public static func deviceIdentity() -> DeviceIdentity {
        if let existing = AppGroup.readJSON(DeviceIdentity.self, from: deviceFileName) {
            return existing
        }
        let fresh = DeviceIdentity(deviceID: UUID().uuidString, createdAt: Date())
        _ = AppGroup.writeJSON(fresh, to: deviceFileName, protected: true)
        return fresh
    }

    struct LamportState: Codable { var counter: UInt64 }

    /// 从 App Group 恢复 Lamport 计数器；文件缺失或损坏从 0 起步
    public static func restoreLamportCounter() -> UInt64 {
        AppGroup.readJSON(LamportState.self, from: lamportFileName)?.counter ?? 0
    }

    /// 计数器变化后落盘（时钟只增不减的前提）
    public static func persistLamportCounter(_ value: UInt64) {
        _ = AppGroup.writeJSON(LamportState(counter: value), to: lamportFileName)
    }
}

/// 单进程 Lamport 逻辑时钟（ADR 0001）。
/// persist 注入化：生产走 SyncInfra（App Group JSON），测试注入内存闭包。
public final class LamportClock {

    private let queue = DispatchQueue(label: "com.lingxi.lamport")
    private var current: UInt64
    private let persist: ((UInt64) -> Void)?

    /// - Parameters:
    ///   - initial: 恢复的计数器初值
    ///   - persist: 每次变化后的落盘回调
    public init(initial: UInt64 = 0, persist: ((UInt64) -> Void)? = nil) {
        self.current = initial
        self.persist = persist
    }

    /// 生产共享实例（App Group 持久化；时钟值跨启动只增不减）
    public static let shared = LamportClock(
        initial: SyncInfra.restoreLamportCounter(),
        persist: SyncInfra.persistLamportCounter
    )

    /// 本地写入前调用：counter += 1，返回本次写入携带的 lamport 时间戳
    @discardableResult
    public func tick() -> UInt64 {
        queue.sync {
            current += 1
            persist?(current)
            return current
        }
    }

    /// 收到远端记录时调用：counter = max(local, remote) + 1
    @discardableResult
    public func observe(remote: UInt64) -> UInt64 {
        queue.sync {
            current = max(current, remote) + 1
            persist?(current)
            return current
        }
    }

    /// 当前时钟值（只读，不递增）
    public var value: UInt64 { queue.sync { current } }
}

// MARK: - LWW 合并引擎

/// 一次合并的完整产出
public struct LWWMergeOutcome: Equatable {
    /// 合并后的完整状态（含墓碑；按 (lamportTS, deviceID) 降序）
    public let merged: [SyncChange]
    /// 远端胜出、需要应用到本地存储的变更（墓碑 → 本地执行删除）
    public let toApply: [SyncChange]
    /// 已见最大 lamport 水位（下次增量拉取的 since 起点）
    public let watermark: UInt64
}

/// 键值语义 LWW 合并（ADR 0001）：全序规则 (lamportTS, deviceID) 字典序大者胜。
/// 纯函数、无副作用，本地存储的最终写入由调用方执行。
public enum LWWMergeEngine {

    /// - Parameters:
    ///   - local: 本地当前状态（含墓碑；必须包含本地已见过的全部记录）
    ///   - remote: 本次增量拉取的远端变更
    public static func merge(local: [SyncChange], remote: [SyncChange]) -> LWWMergeOutcome {
        var byKey: [String: SyncChange] = [:]
        for change in local {
            byKey[fullKey(of: change)] = change
        }

        // 远端批内先按全序升序逐条 upsert：批内重复 key 时时间戳高者最终胜出
        let sortedRemote = remote.sorted {
            ($0.lamportTS, $0.deviceID) < ($1.lamportTS, $1.deviceID)
        }
        var remoteByKey: [String: SyncChange] = [:]
        for change in sortedRemote {
            let key = fullKey(of: change)
            // 升序遍历：同键时后写入的（更新）版本覆盖前者，字典最终只留批内最新
            remoteByKey[key] = change
            if let existing = byKey[key] {
                if change.wins(over: existing) {
                    byKey[key] = change
                }
            } else {
                byKey[key] = change
            }
        }

        let merged = byKey.values.sorted {
            ($0.lamportTS, $0.deviceID) > ($1.lamportTS, $1.deviceID)
        }
        // 仅『最终胜出者就是远端记录』的键需要落本地：
        // 批内同键多版本只应用最终胜者；与本地一致的远端记录重放为无害 no-op
        let applied = merged.compactMap { entry -> SyncChange? in
            guard let remote = remoteByKey[fullKey(entry)], remote == entry else { return nil }
            return remote
        }
        let watermark = merged.map { $0.lamportTS }.max() ?? 0
        return LWWMergeOutcome(merged: merged, toApply: applied, watermark: watermark)
    }

    /// 命名空间 + 键构成全局唯一标识（不同命名空间下的同名 key 互不冲突）
    private static func fullKey(of change: SyncChange) -> String {
        change.namespace.rawValue + "/" + change.key
    }
}
