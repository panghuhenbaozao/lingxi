import CoreFoundation
import Foundation

/// 跨进程 Darwin 通知（主 App 与键盘扩展毫秒级双向实时同步外观与设置，彻底消除不同步）。
enum AppGroupNotifications {
    static let themeChanged = "com.lingxi.ime.themeChanged"
    static let settingsChanged = "com.lingxi.ime.settingsChanged"

    static func post(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    final class Observer {
        fileprivate let onNotify: () -> Void
        private let name: String

        init(name: String, onNotify: @escaping () -> Void) {
            self.name = name
            self.onNotify = onNotify
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(
                center,
                pointer,
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    let box = Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue()
                    DispatchQueue.main.async {
                        box.onNotify()
                    }
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }

        deinit {
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterRemoveObserver(center, pointer, CFNotificationName(name as CFString), nil)
        }
    }
}

/// App Group 解析。
///
/// 正常签名时使用 `LingxiAppGroup`（Info.plist）中配置的标识；
/// 通过 AltStore / SideStore 侧载时，签名工具会把 App Group 改写为带 Team ID 的新标识，
/// 并写入 Info.plist 的 `ALTAppGroups` 键，因此优先读取它。
enum AppGroup {
    static let defaultIdentifier = "group.com.lingxi.ime"

    /// 当前进程实际可用的 App Group 标识。
    static let identifier: String = resolveIdentifier()

    /// 共享容器目录；为 nil 表示 App Group 权限缺失（签名问题）。
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isAvailable: Bool { containerURL != nil }

    /// 数据目录：优先使用共享容器；不可用时退回进程私有目录，并由 UI 明确提示用户。
    static var dataDirectory: URL {
        if let shared = containerURL {
            return shared
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LingxiLocal", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static func fileURL(_ fileName: String) -> URL {
        dataDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    static func modificationDate(of fileName: String) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL(fileName).path)
        return attrs?[.modificationDate] as? Date
    }

    /// 文件内容指纹（修改时间 + 字节大小 + inode），避免 1 秒内连续读写被旧缓存误判未变更。
    static func fileStamp(of fileName: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL(fileName).path) else {
            return nil
        }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        return "\(mtime)-\(size)-\(inode)"
    }

    static func readJSON<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        let url = fileURL(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// L1 安全要求：App Group 文件统一启用 completeUntilFirstUserAuthentication 硬件加密保护级。
    @discardableResult
    static func writeJSON<T: Encodable>(_ value: T, to fileName: String, protected: Bool = true) -> Bool {
        let url = fileURL(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            if protected {
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: url.path
                )
            }
            return true
        } catch {
            return false
        }
    }

    private static func resolveIdentifier() -> String {
        var candidates: [String] = []
        if let altGroups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            // 优先选择与本应用相关的分组（严格弱序比较器，避免 Swift sort 断言）
            candidates += altGroups.sorted { lhs, rhs in
                lhs.contains("lingxi") && !rhs.contains("lingxi")
            }
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: "LingxiAppGroup") as? String, !configured.isEmpty {
            candidates.append(configured)
        }
        candidates.append(defaultIdentifier)

        for candidate in candidates
        where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: candidate) != nil {
            return candidate
        }
        return candidates.first ?? defaultIdentifier
    }
}
