import Foundation

// MARK: - 1. 动态变量快捷短语引擎（借鉴 azooKey：支持 {{日期}} / {{时间}} / {{星期}} / {{剪贴板}} / {{选中文字}}）

enum DynamicTemplateEngine {
    static let availableTokens: [(token: String, label: String)] = [
        ("{{日期}}", "今日日期"),
        ("{{时间}}", "当前时间"),
        ("{{星期}}", "星期几"),
        ("{{年月}}", "当前年月"),
        ("{{当前城市}}", "实时城市"),
        ("{{当前区县}}", "实时区县"),
        ("{{当前位置}}", "实时地址"),
        ("{{剪贴板}}", "最新剪贴板"),
        ("{{选中文字}}", "选中内容"),
        ("{{随机问候}}", "时段问候"),
    ]

    static func containsVariables(_ text: String) -> Bool {
        text.contains("{{") && text.contains("}}")
    }

    static func render(
        _ template: String,
        clipboard: String? = nil,
        selectedText: String? = nil,
        now: Date = Date()
    ) -> String {
        guard containsVariables(template) else { return template }
        let cal = Calendar(identifier: .gregorian)
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "zh_CN")

        dateFmt.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFmt.string(from: now)

        dateFmt.dateFormat = "HH:mm"
        let timeStr = dateFmt.string(from: now)

        dateFmt.dateFormat = "yyyy年MM月"
        let ymStr = dateFmt.string(from: now)

        let weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        let wdIdx = max(0, min(6, cal.component(.weekday, from: now) - 1))
        let weekdayStr = weekdays[wdIdx]

        let hour = cal.component(.hour, from: now)
        let greeting: String
        switch hour {
        case 5..<11: greeting = "早上好"
        case 11..<14: greeting = "中午好"
        case 14..<18: greeting = "下午好"
        case 18..<23: greeting = "晚上好"
        default: greeting = "夜深了注意休息"
        }

        let clip = (clipboard ?? ClipboardStore.items().first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sel = (selectedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let geo = GeoLocationContext.load()

        return template
            .replacingOccurrences(of: "{{日期}}", with: dateStr)
            .replacingOccurrences(of: "{{时间}}", with: timeStr)
            .replacingOccurrences(of: "{{星期}}", with: weekdayStr)
            .replacingOccurrences(of: "{{年月}}", with: ymStr)
            .replacingOccurrences(of: "{{当前城市}}", with: geo.shortCityName)
            .replacingOccurrences(of: "{{当前区县}}", with: geo.district.isEmpty ? geo.shortCityName : geo.district)
            .replacingOccurrences(of: "{{当前街道}}", with: geo.street)
            .replacingOccurrences(of: "{{当前位置}}", with: geo.fullDisplayAddress)
            .replacingOccurrences(of: "{{剪贴板}}", with: clip)
            .replacingOccurrences(of: "{{选中文字}}", with: sel)
            .replacingOccurrences(of: "{{随机问候}}", with: greeting)
    }
}

// MARK: - 2. 一键排版微整形工具箱（盘古空格 / 去多余空行 / 编号清单 / 财务大写金额）

enum TextFormatterToolbox {
    /// 中文与英文/数字之间自动插入标准盘古空格。
    static func addPanguSpaces(_ text: String) -> String {
        var out = text
        let patterns: [(String, String)] = [
            ("([\\p{Han}])([A-Za-z0-9@#\\$%\\^&\\*\\(])", "$1 $2"),
            ("([A-Za-z0-9!\\)\\?%])([\\p{Han}])", "$1 $2"),
        ]
        for (pat, rep) in patterns {
            if let regex = try? NSRegularExpression(pattern: pat) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: rep)
            }
        }
        return out
    }

    /// 清除复制网页/PDF 带来的碎片空行与多余首尾空白。
    static func collapseBlankLines(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    /// 将多行文本一键整理为「1. 2. 3.」有序编号清单。
    static func toNumberedList(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    /// 将多行文本一键整理为「• 」项目符号清单。
    static func toBulletList(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.map { $0.hasPrefix("•") ? $0 : "• \($0)" }.joined(separator: "\n")
    }

    /// 将阿拉伯金额转换为中文财务大写（如 12800 -> 壹万贰仟捌佰元整）。
    static func amountToChineseCapital(_ rawAmount: Double) -> String {
        guard rawAmount >= 0, rawAmount < 1_000_000_000_000 else { return "" }
        let digits = ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"]
        let smallUnits = ["", "拾", "佰", "仟"]
        let bigUnits = ["", "万", "亿"]

        let totalFen = Int64((rawAmount * 100.0).rounded())
        let yuan = totalFen / 100
        let jiao = Int((totalFen % 100) / 10)
        let fen = Int(totalFen % 10)

        var intPart = ""
        if yuan == 0 {
            intPart = "零"
        } else {
            var remaining = yuan
            var groupIndex = 0
            var needZero = false
            while remaining > 0 {
                let section = Int(remaining % 10000)
                if section > 0 {
                    var secStr = ""
                    var secZero = false
                    var s = section
                    for pos in 0..<4 {
                        let d = s % 10
                        if d == 0 {
                            if !secStr.isEmpty { secZero = true }
                        } else {
                            if secZero {
                                secStr = digits[0] + secStr
                                secZero = false
                            }
                            secStr = digits[d] + smallUnits[pos] + secStr
                        }
                        s /= 10
                        if s == 0 { break }
                    }
                    if needZero && !intPart.hasPrefix("零") {
                        intPart = "零" + intPart
                    }
                    intPart = secStr + bigUnits[groupIndex] + intPart
                    needZero = section < 1000
                } else {
                    if !intPart.isEmpty { needZero = true }
                }
                remaining /= 10000
                groupIndex += 1
            }
        }

        if jiao == 0 && fen == 0 {
            return "\(intPart)元整"
        }
        var decPart = ""
        if jiao > 0 { decPart += "\(digits[jiao])角" }
        else if yuan > 0 { decPart += "零" }
        if fen > 0 { decPart += "\(digits[fen])分" }
        return "\(intPart)元\(decPart)"
    }
}

// MARK: - 3. 本地 Face ID 敏感信息安全保险箱（100% 留存本机受保护容器，绝不上云、绝不污染剪贴板）

struct SecureVaultItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var category: String
    var value: String
    var updatedAt: Int = Int(Date().timeIntervalSince1970)

    init(id: String = UUID().uuidString, title: String, category: String = "证件/账务", value: String) {
        self.id = id
        self.title = title
        self.category = category
        self.value = value
        self.updatedAt = Int(Date().timeIntervalSince1970)
    }

    /// 列表预览脱敏展示（仅露首尾 2~3 字符）
    var maskedPreview: String {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 4 { return String(repeating: "•", count: max(2, t.count)) }
        let head = t.prefix(2)
        let tail = t.suffix(2)
        return "\(head)••••\(tail)"
    }
}

enum SecureSnippetVault {
    private static let fileName = "lingxi_local_secure_vault.json"

    static func loadAll() -> [SecureVaultItem] {
        AppGroup.readJSON([SecureVaultItem].self, from: fileName) ?? []
    }

    @discardableResult
    static func saveAll(_ items: [SecureVaultItem]) -> Bool {
        AppGroup.writeJSON(items, to: fileName, protected: true)
    }

    static func upsert(_ item: SecureVaultItem) {
        var list = loadAll()
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            list[idx] = item
        } else {
            list.insert(item, at: 0)
        }
        _ = saveAll(list)
    }

    static func delete(id: String) {
        var list = loadAll()
        list.removeAll { $0.id == id }
        _ = saveAll(list)
    }
}

// MARK: - 4. 26 键手型触控落点偏移自学习校准器（Touch Heatmap & Auto-Hitbox Calibration）

struct KeyTouchOffsetStat: Codable, Equatable {
    var count: Int = 0
    var avgDX: Double = 0
    var avgDY: Double = 0
}

struct TouchCalibrationProfile: Codable, Equatable {
    var perKey: [String: KeyTouchOffsetStat] = [:]
    var calibrationApplied: Bool = true
    var updatedAt: Int = Int(Date().timeIntervalSince1970)
}

final class TouchOffsetCalibrator {
    static let shared = TouchOffsetCalibrator()
    private static let fileName = "lingxi_touch_calibration.json"
    private let queue = DispatchQueue(label: "com.lingxi.touchcalib", qos: .utility)
    private var profile: TouchCalibrationProfile
    private var pendingWrites = 0

    init() {
        self.profile = AppGroup.readJSON(TouchCalibrationProfile.self, from: Self.fileName) ?? TouchCalibrationProfile()
    }

    func currentProfile() -> TouchCalibrationProfile {
        queue.sync { profile }
    }

    /// 记录用户点击某字母键中心点的 (dx, dy) 偏差（单位：pt），指数滑动平均收敛手型偏移。
    func recordTouch(key: String, dx: Double, dy: Double) {
        let k = key.lowercased()
        guard k.count == 1, abs(dx) <= 22, abs(dy) <= 22 else { return }
        queue.async {
            var stat = self.profile.perKey[k] ?? KeyTouchOffsetStat()
            let alpha = stat.count < 12 ? (1.0 / Double(stat.count + 1)) : 0.08
            stat.count += 1
            stat.avgDX = ((stat.avgDX * (1.0 - alpha) + dx * alpha) * 100).rounded() / 100
            stat.avgDY = ((stat.avgDY * (1.0 - alpha) + dy * alpha) * 100).rounded() / 100
            self.profile.perKey[k] = stat
            self.profile.updatedAt = Int(Date().timeIntervalSince1970)
            self.pendingWrites += 1
            if self.pendingWrites >= 16 {
                self.pendingWrites = 0
                _ = AppGroup.writeJSON(self.profile, to: Self.fileName)
            }
        }
    }

    func flush() {
        queue.sync {
            pendingWrites = 0
            _ = AppGroup.writeJSON(profile, to: Self.fileName)
        }
    }

    func reset() {
        queue.sync {
            profile = TouchCalibrationProfile()
            pendingWrites = 0
            _ = AppGroup.writeJSON(profile, to: Self.fileName)
        }
    }

    func setApplied(_ enabled: Bool) {
        queue.sync {
            profile.calibrationApplied = enabled
            _ = AppGroup.writeJSON(profile, to: Self.fileName)
        }
    }

    /// 返回某键的微调偏移量（限制在 ±6pt 防止过度偏移）。
    func offset(for key: String) -> (dx: Double, dy: Double) {
        queue.sync {
            guard profile.calibrationApplied, let s = profile.perKey[key.lowercased()], s.count >= 5 else {
                return (0, 0)
            }
            return (max(-6, min(6, s.avgDX)), max(-6, min(6, s.avgDY)))
        }
    }
}

// MARK: - 5. 零体积汉字四声调识别器（基于系统原生 CoreFoundation 转写，覆盖全部 20,000+ 汉字）

enum MandarinTone: Int, CaseIterable, Identifiable {
    case all = 0
    case first = 1
    case second = 2
    case third = 3
    case fourth = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .all: return "全部"
        case .first: return "一声 ¯"
        case .second: return "二声 ´"
        case .third: return "三声 ˇ"
        case .fourth: return "四声 ˋ"
        }
    }
}

enum PinyinToneClassifier {
    private static var cache: [Character: Int] = [:]

    /// 返回汉字的主读音声调（1=阴平, 2=阳平, 3=上声, 4=去声, 0=轻声/非汉字）。
    static func tone(for word: String) -> Int {
        guard word.count == 1, let ch = word.first else { return 0 }
        if let hit = cache[ch] { return hit }
        let latin = String(ch).applyingTransform(.toLatin, reverse: false) ?? ""
        let detected = detectToneFromMarkedPinyin(latin)
        if cache.count < 4096 { cache[ch] = detected }
        return detected
    }

    static func detectToneFromMarkedPinyin(_ marked: String) -> Int {
        let firstSet = CharacterSet(charactersIn: "āēīōūǖ")
        let secondSet = CharacterSet(charactersIn: "áéíóúǘ")
        let thirdSet = CharacterSet(charactersIn: "ǎěǐǒǔǚ")
        let fourthSet = CharacterSet(charactersIn: "àèìòùǜ")
        for scalar in marked.unicodeScalars {
            if firstSet.contains(scalar) { return 1 }
            if secondSet.contains(scalar) { return 2 }
            if thirdSet.contains(scalar) { return 3 }
            if fourthSet.contains(scalar) { return 4 }
        }
        return 0
    }
}
