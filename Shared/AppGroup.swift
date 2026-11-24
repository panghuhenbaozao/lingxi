import CoreFoundation
import Foundation

/// 跨进程 Darwin 通知（主 App 与键盘扩展毫秒级双向实时同步外观、设置与字数统计，彻底消除不同步）。
enum AppGroupNotifications {
    static let themeChanged = "com.lingxi.ime.themeChanged"
    static let settingsChanged = "com.lingxi.ime.settingsChanged"
    static let statsChanged = "com.lingxi.ime.statsChanged"
    static let aiConfigChanged = "com.lingxi.ime.aiConfigChanged"
    static let permissionsChanged = "com.lingxi.ime.permissionsChanged"
    static let voiceCommand = "com.lingxi.ime.voiceCommand"
    static let voiceState = "com.lingxi.ime.voiceState"

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

    /// 当前进程实际可用的 App Group 标识与来源诊断。
    private static let resolution: (identifier: String, source: String, candidates: [String]) = resolveIdentifierWithDiagnostics()

    static var identifier: String { resolution.identifier }
    static var resolutionSource: String { resolution.source }
    static var inspectedCandidates: [String] { resolution.candidates }

    /// 共享容器目录；为 nil 表示当前签名未包含可用的 App Group 权限（例如免费个人 Apple ID 侧载）。
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isAvailable: Bool { containerURL != nil }

    static var diagnosticSummary: String {
        if isAvailable {
            return "本机共享容器已打通（\(identifier) · \(resolutionSource)）"
        }
        return "未检测到本机 App Group 共享容器（常见于免费个人 Apple ID 侧载，系统会隔离 App 与键盘沙盒）"
    }

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

    /// 4 级精准探测本机可用 App Group：
    /// 1) 自身 embedded.mobileprovision 的 com.apple.security.application-groups
    /// 2) 键盘扩展自动向上读取父包 Lingxi.app 的 embedded.mobileprovision 与 Info.plist (ALTAppGroups)
    /// 3) 自身 Info.plist (ALTAppGroups / LingxiAppGroup)
    /// 4) 基于 Bundle ID 推导的常见侧载组名 + 默认 group.com.lingxi.ime
    private static func resolveIdentifierWithDiagnostics() -> (identifier: String, source: String, candidates: [String]) {
        var ordered: [(id: String, source: String)] = []
        var seen = Set<String>()

        func appendCandidate(_ raw: String?, source: String) {
            guard let id = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  seen.insert(id).inserted else { return }
            ordered.append((id, source))
        }

        // Level 1: 自身签名描述文件 embedded.mobileprovision
        for g in readMobileProvisionAppGroups(in: Bundle.main.bundleURL) {
            appendCandidate(g, source: "自身描述文件")
        }

        // Level 2: 若当前处于 .appex 键盘扩展，向上读取宿主 Lingxi.app 的描述文件与 Info.plist
        if let hostAppURL = parentAppBundleURL() {
            for g in readMobileProvisionAppGroups(in: hostAppURL) {
                appendCandidate(g, source: "主App描述文件")
            }
            if let hostPlist = readInfoPlist(in: hostAppURL) {
                if let altGroups = hostPlist["ALTAppGroups"] as? [String] {
                    let sorted = altGroups.sorted { lhs, rhs in
                        lhs.contains("lingxi") && !rhs.contains("lingxi")
                    }
                    for g in sorted { appendCandidate(g, source: "主App ALTAppGroups") }
                }
                if let configured = hostPlist["LingxiAppGroup"] as? String {
                    appendCandidate(configured, source: "主App Info.plist")
                }
            }
        }

        // Level 3: 自身 Info.plist
        if let altGroups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            let sorted = altGroups.sorted { lhs, rhs in
                lhs.contains("lingxi") && !rhs.contains("lingxi")
            }
            for g in sorted { appendCandidate(g, source: "ALTAppGroups") }
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: "LingxiAppGroup") as? String {
            appendCandidate(configured, source: "Info.plist")
        }

        // Level 4: 常见侧载推导组名 & 默认组名
        if let bid = Bundle.main.bundleIdentifier, !bid.isEmpty {
            let baseBid = bid.hasSuffix(".keyboard") ? String(bid.dropLast(".keyboard".count)) : bid
            appendCandidate("group.\(baseBid)", source: "BundleID推导")
        }
        appendCandidate(defaultIdentifier, source: "默认标识")

        let allIDs = ordered.map(\.id)
        for item in ordered
        where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: item.id) != nil {
            return (item.id, item.source, allIDs)
        }
        let fallback = ordered.first ?? (defaultIdentifier, "未匹配")
        return (fallback.id, fallback.source, allIDs)
    }

    private static func parentAppBundleURL() -> URL? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension.lowercased() == "appex" else { return nil }
        let candidate = url.deletingLastPathComponent().deletingLastPathComponent()
        return candidate.pathExtension.lowercased() == "app" ? candidate : nil
    }

    private static func readInfoPlist(in bundleURL: URL) -> [String: Any]? {
        let plistURL = bundleURL.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return obj
    }

    /// 从 iOS embedded.mobileprovision 二进制 CMS 包中解析 XML plist 并提取 com.apple.security.application-groups。
    static func parseAppGroupsFromMobileProvisionData(_ data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
            return []
        }
        let xmlData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: xmlData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
            return []
        }
        return groups.sorted { lhs, rhs in
            lhs.contains("lingxi") && !rhs.contains("lingxi")
        }
    }

    private static func readMobileProvisionAppGroups(in bundleURL: URL) -> [String] {
        let provURL = bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: provURL) else { return [] }
        return parseAppGroupsFromMobileProvisionData(data)
    }
}

/// 键盘扩展权限与状态心跳（由于 iOS 禁止主 App 直接探测键盘的 hasFullAccess，由键盘在 viewWillAppear 写入共享容器供主 App 实时感知）。
struct KeyboardPermissionHeartbeat: Codable, Equatable {
    var hasFullAccess: Bool = false
    var appGroupAvailable: Bool = false
    var aiConfigured: Bool = false
    var updatedAt: Date = Date()

    static let fileName = "lingxi_keyboard_heartbeat.json"

    static func load() -> KeyboardPermissionHeartbeat? {
        AppGroup.readJSON(KeyboardPermissionHeartbeat.self, from: fileName)
    }

    @discardableResult
    static func record(hasFullAccess: Bool, aiConfigured: Bool) -> Bool {
        let heartbeat = KeyboardPermissionHeartbeat(
            hasFullAccess: hasFullAccess,
            appGroupAvailable: AppGroup.isAvailable,
            aiConfigured: aiConfigured,
            updatedAt: Date()
        )
        let ok = AppGroup.writeJSON(heartbeat, to: fileName, protected: false)
        if ok {
            AppGroupNotifications.post(AppGroupNotifications.permissionsChanged)
        }
        return ok
    }
}
