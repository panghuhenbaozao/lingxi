import Foundation

// MARK: - 实时地理位置感知与周边 POI 自学习上下文（100% 本机 App Group，绝不上云）

struct GeoPOIEntry: Codable, Identifiable, Equatable, Hashable {
    var id: String { "\(word)|\(pinyin)" }
    var word: String
    var pinyin: String       // 带单引号分隔的全拼，如 "lin'yi'bei'zhan"
    var abbr: String         // 首字母简拼，如 "lybz"
    var t9Abbr: String       // T9 九宫格数字简拼，如 "5929"
    var category: String     // 城市 / 区县 / 街道 / 商圈 / 交通 / 小区 / 高校 / 地标
    var boostScore: Double   // 候选加权分（越高越靠前）

    init(
        word: String,
        pinyin: String,
        abbr: String,
        t9Abbr: String,
        category: String,
        boostScore: Double
    ) {
        self.word = word
        self.pinyin = pinyin
        self.abbr = abbr
        self.t9Abbr = t9Abbr
        self.category = category
        self.boostScore = boostScore
    }
}

/// 本机实时地理位置与周边高频地标词库快照（由主 App CoreLocation + MapKit 静默采集，键盘零延迟读取）。
struct GeoLocationContext: Codable, Equatable {
    var province: String = ""
    var city: String = ""
    var district: String = ""
    var street: String = ""
    var formattedAddress: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var pois: [GeoPOIEntry] = []
    var updatedAt: Date? = nil
    var sourceMode: String = "gps" // "gps" | "citySearch"

    private static let fileName = "lingxi_geo_context.json"
    private static var cached: GeoLocationContext?
    private static var cachedMTime: Date?
    private static var lastStatCheckTime: CFAbsoluteTime = 0

    init() {}

    var isPopulated: Bool {
        !city.isEmpty || !district.isEmpty || !pois.isEmpty
    }

    /// 去除「市/自治州/地区」后缀的口语简称（如「临沂市」->「临沂」）
    var shortCityName: String {
        Self.stripSuffix(city, suffixes: ["特别行政区", "自治州", "地区", "市", "盟"])
    }

    /// 去除「区/县」后缀的区县简称（如「兰山区」->「兰山」，保留2字县如「费县」）
    var shortDistrictName: String {
        Self.stripSuffix(district, suffixes: ["自治县", "自治旗", "新区", "区", "县", "市", "旗"])
    }

    /// 紧凑地区标签（如「山东省临沂市兰山区」）
    var compactLocationLabel: String {
        var parts: [String] = []
        if !province.isEmpty { parts.append(province) }
        if !city.isEmpty && city != province { parts.append(city) }
        if !district.isEmpty { parts.append(district) }
        return parts.joined()
    }

    /// 可一键发送的完整位置文案
    var fullDisplayAddress: String {
        if !formattedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return formattedAddress
        }
        return [compactLocationLabel, street].filter { !$0.isEmpty }.joined()
    }

    private static func stripSuffix(_ raw: String, suffixes: [String]) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for suf in suffixes where trimmed.hasSuffix(suf) && trimmed.count - suf.count >= 2 {
            return String(trimmed.dropLast(suf.count))
        }
        return trimmed
    }

    static func load(force: Bool = false) -> GeoLocationContext {
        let now = CFAbsoluteTimeGetCurrent()
        if !force, let cached, now - lastStatCheckTime < 2.5 {
            return cached
        }
        lastStatCheckTime = now
        let mtime = AppGroup.modificationDate(of: fileName)
        if !force, let cached, cachedMTime == mtime {
            return cached
        }
        let loaded = AppGroup.readJSON(GeoLocationContext.self, from: fileName) ?? GeoLocationContext()
        cached = loaded
        cachedMTime = mtime
        return loaded
    }

    @discardableResult
    func save() -> Bool {
        let ok = AppGroup.writeJSON(self, to: Self.fileName, protected: true)
        Self.cached = self
        Self.cachedMTime = AppGroup.modificationDate(of: Self.fileName)
        Self.lastStatCheckTime = CFAbsoluteTimeGetCurrent()
        return ok
    }

    static func clear() {
        try? FileManager.default.removeItem(at: AppGroup.fileURL(fileName))
        cached = GeoLocationContext()
        cachedMTime = nil
        lastStatCheckTime = 0
    }

    /// 在键盘打字热路径中，精准匹配当前城市/区县/街道与周边 POI：
    /// - 全拼模式：优先匹配完整全拼与 4 字以上简拼；2~3 字简拼仅在次选提示；前缀匹配要求至少 5 字符且最多 1 条，绝不抢占常见汉字。
    /// - T9 九宫格模式：仅匹配完整 T9 全拼（>=4位）或 4+ 位 T9 简拼，彻底杜绝短数字前缀劫持日常高频词（如 546/742）。
    func matchCandidates(rawInput: String, isT9: Bool, limit: Int = 4) -> [GeoPOIEntry] {
        guard !pois.isEmpty else { return [] }
        let clean = rawInput.lowercased().replacingOccurrences(of: "'", with: "")
        guard clean.count >= 2 else { return [] }

        var exactHits: [GeoPOIEntry] = []
        var prefixHits: [GeoPOIEntry] = []
        var seen = Set<String>()

        for entry in pois {
            guard !seen.contains(entry.word) else { continue }
            if isT9 {
                guard clean.count >= 4 else { continue }
                let fullT9 = GeoPinyinConverter.toT9(entry.pinyin.replacingOccurrences(of: "'", with: ""))
                if fullT9 == clean || entry.t9Abbr == clean {
                    exactHits.append(entry)
                    seen.insert(entry.word)
                }
            } else {
                let flatPy = entry.pinyin.replacingOccurrences(of: "'", with: "")
                if flatPy == clean || (clean.count >= 2 && entry.abbr == clean) {
                    exactHits.append(entry)
                    seen.insert(entry.word)
                } else if clean.count >= 5 && flatPy.hasPrefix(clean) {
                    prefixHits.append(entry)
                    seen.insert(entry.word)
                }
            }
        }

        let sortedExact = exactHits.sorted { $0.boostScore > $1.boostScore }
        let sortedPrefix = Array(prefixHits.sorted { $0.boostScore > $1.boostScore }.prefix(1))
        return Array((sortedExact + sortedPrefix).prefix(limit))
    }

    /// 为 AI 助手提供脱敏时空上下文（仅包含城市/区县与当前时段，不暴露精确门牌或经纬度）。
    func aiTimeLocationPromptSuffix(now: Date = Date()) -> String {
        guard isPopulated else { return "" }
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日 EEEE"
        let dateStr = fmt.string(from: now)
        let hour = cal.component(.hour, from: now)
        let period: String
        switch hour {
        case 5..<9: period = "清晨"
        case 9..<12: period = "上午"
        case 12..<14: period = "中午"
        case 14..<18: period = "下午"
        case 18..<23: period = "晚上"
        default: period = "深夜"
        }
        let loc = compactLocationLabel.isEmpty ? shortCityName : compactLocationLabel
        let topLandmarks = pois
            .filter { $0.category == "商圈" || $0.category == "交通" || $0.category == "地标" }
            .prefix(5)
            .map(\.word)
            .joined(separator: "、")
        var line = "【实时所在地区与时间】当前位于「\(loc)」，时间：\(dateStr) \(period)。"
        if !topLandmarks.isEmpty {
            line += "附近常见地标：\(topLandmarks)。"
        }
        line += "当用户询问本地推荐、出行路线、打卡文案或约饭安排时，请自然结合该地区特征作答；非地域话题则忽略此上下文。"
        return line
    }
}

// MARK: - 端侧零依赖中文地名拼音与 T9 编码转换器（内置中国地名多音字权威校正表）

enum GeoPinyinConverter {
    private static let polyphoneOverrides: [(word: String, py: String)] = [
        ("临沂", "lin'yi"), ("菏泽", "he'ze"), ("郯城", "tan'cheng"), ("临沭", "lin'shu"),
        ("平邑", "ping'yi"), ("莒南", "ju'nan"), ("莒县", "ju'xian"), ("单县", "shan'xian"),
        ("茌平", "chi'ping"), ("临朐", "lin'qu"), ("兖州", "yan'zhou"), ("济宁", "ji'ning"),
        ("重庆", "chong'qing"), ("长沙", "chang'sha"), ("长春", "chang'chun"), ("长治", "chang'zhi"),
        ("长葛", "chang'ge"), ("长乐", "chang'le"), ("长宁", "chang'ning"), ("长清", "chang'qing"),
        ("蚌埠", "beng'bu"), ("六安", "lu'an"), ("六合", "lu'he"), ("亳州", "bo'zhou"),
        ("东莞", "dong'guan"), ("番禺", "pan'yu"), ("厦门", "xia'men"), ("台州", "tai'zhou"),
        ("丽水", "li'shui"), ("衢州", "qu'zhou"), ("歙县", "she'xian"), ("黟县", "yi'xian"),
        ("涡阳", "guo'yang"), ("砀山", "dang'shan"), ("荥阳", "xing'yang"), ("泌阳", "bi'yang"),
        ("浚县", "xun'xian"), ("铅山", "yan'shan"), ("乐亭", "lao'ting"), ("蔚县", "yu'xian"),
        ("洪洞", "hong'tong"), ("繁峙", "fan'shi"), ("郫都", "pi'du"), ("邛崃", "qiong'lai"),
        ("犍为", "qian'wei"), ("阆中", "lang'zhong"), ("涪陵", "fu'ling"), ("綦江", "qi'jiang"),
        ("都匀", "du'yun"), ("百色", "bai'se"), ("那曲", "na'qu"), ("珲春", "hun'chun"),
        ("大城", "dai'cheng"), ("井陉", "jing'xing"), ("藁城", "gao'cheng"), ("栾城", "luan'cheng"),
        ("任丘", "ren'qiu"), ("宝坻", "bao'di"), ("蓟州", "ji'zhou"), ("朝阳", "chao'yang"),
        ("银行", "yin'hang"), ("长途", "chang'tu"), ("广场", "guang'chang"), ("商业", "shang'ye"),
        ("万象", "wan'xiang"), ("启阳", "qi'yang"),
    ]

    /// 清洗 MapKit 返回的冗长商户/分店后缀，提取干净高频的 2~8 字中文地标名。
    static func cleanPOIName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for sep in ["(", "（", "[", "【", "·", "-", " "] {
            if let idx = s.range(of: sep)?.lowerBound {
                let head = String(s[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                if head.count >= 2 { s = head }
            }
        }
        // 只保留常见汉字，过滤纯数字/英文门牌噪音
        let hanOnly = String(s.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) })
        guard hanOnly.count >= 2 && hanOnly.count <= 8 else { return "" }
        return hanOnly
    }

    static func makeEntry(word rawWord: String, category: String, boostScore: Double) -> GeoPOIEntry? {
        let word = cleanPOIName(rawWord)
        guard !word.isEmpty else { return nil }
        let syllables = toPinyinSyllables(word)
        guard syllables.count == word.count else { return nil }
        let py = syllables.joined(separator: "'")
        let abbr = syllables.compactMap(\.first).map(String.init).joined()
        let t9 = toT9(abbr)
        return GeoPOIEntry(
            word: word,
            pinyin: py,
            abbr: abbr,
            t9Abbr: t9,
            category: category,
            boostScore: boostScore
        )
    }

    static func toPinyinSyllables(_ chinese: String) -> [String] {
        var result: [String] = []
        let chars = Array(chinese)
        var i = 0
        while i < chars.count {
            var matchedOverride = false
            for ov in polyphoneOverrides {
                let ovChars = Array(ov.word)
                if i + ovChars.count <= chars.count && Array(chars[i..<(i + ovChars.count)]) == ovChars {
                    result.append(contentsOf: ov.py.split(separator: "'").map(String.init))
                    i += ovChars.count
                    matchedOverride = true
                    break
                }
            }
            if matchedOverride { continue }

            let single = String(chars[i])
            let latin = single.applyingTransform(.toLatin, reverse: false)?
                .applyingTransform(.stripDiacritics, reverse: false)?
                .lowercased()
                .replacingOccurrences(of: "ü", with: "v") ?? ""
            let lettersOnly = String(latin.filter { $0 >= "a" && $0 <= "z" })
            if lettersOnly.isEmpty { return [] }
            result.append(lettersOnly)
            i += 1
        }
        return result
    }

    static func toT9(_ letters: String) -> String {
        var out = ""
        out.reserveCapacity(letters.count)
        for ch in letters.lowercased() {
            switch ch {
            case "a", "b", "c": out.append("2")
            case "d", "e", "f": out.append("3")
            case "g", "h", "i": out.append("4")
            case "j", "k", "l": out.append("5")
            case "m", "n", "o": out.append("6")
            case "p", "q", "r", "s": out.append("7")
            case "t", "u", "v": out.append("8")
            case "w", "x", "y", "z": out.append("9")
            default: break
            }
        }
        return out
    }
}
