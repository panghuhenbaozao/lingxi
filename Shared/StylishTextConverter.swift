import Foundation
import Security

/// 花样英文字体样式（纯 Unicode 码位映射，发送给任何 App 都生效）。
enum StylishFontStyle: String, Codable, CaseIterable, Identifiable {
    case normal
    case script
    case boldScript
    case fraktur
    case doubleStruck
    case monospace
    case circled
    case fullwidth
    case smallCaps

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "标准"
        case .script: return "花体"
        case .boldScript: return "粗花体"
        case .fraktur: return "哥特体"
        case .doubleStruck: return "空心体"
        case .monospace: return "打字机"
        case .circled: return "圆圈体"
        case .fullwidth: return "全角宽"
        case .smallCaps: return "小型大写"
        }
    }

    var previewSample: String {
        switch self {
        case .normal: return "Lingxi"
        case .script: return StylishTextConverter.convert("Lingxi", style: .script)
        case .boldScript: return StylishTextConverter.convert("Lingxi", style: .boldScript)
        case .fraktur: return StylishTextConverter.convert("Lingxi", style: .fraktur)
        case .doubleStruck: return StylishTextConverter.convert("Lingxi", style: .doubleStruck)
        case .monospace: return StylishTextConverter.convert("Lingxi", style: .monospace)
        case .circled: return StylishTextConverter.convert("Lingxi", style: .circled)
        case .fullwidth: return StylishTextConverter.convert("Lingxi", style: .fullwidth)
        case .smallCaps: return StylishTextConverter.convert("Lingxi", style: .smallCaps)
        }
    }
}

/// 纯本地轻量文字工具：花样字体、算式直出、日期快捷生成、趣味随机小彩蛋。
enum StylishTextConverter {
    private static let normalChars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    private static let scriptChars = Array("𝒜ℬ𝒞𝒟ℰℱ𝒢ℋℐ𝒥𝒦ℒℳ𝒩𝒪𝒫𝒬ℛ𝒮𝒯𝒰𝒱𝒲𝒳𝒴𝒵𝒶𝒷𝒸𝒹ℯ𝒻ℊ𝒽𝒾𝒿𝓀𝓁𝓂𝓃ℴ𝓅𝓆𝓇𝓈𝓉𝓊𝓋𝓌𝓍𝓎𝓏0123456789")
    private static let boldScriptChars = Array("𝓐𝓑𝓒𝓓𝓔𝓕𝓖𝓗𝓘𝓙𝓚𝓛𝓜𝓝𝓞𝓟𝓠𝓡𝓢𝓣𝓤𝓥𝓦𝓧𝓨𝓩𝓪𝓫𝓬𝓭𝓮𝓯𝓰𝓱𝓲𝓳𝓴𝓵𝓶𝓷𝓸𝓹𝓺𝓻𝓼𝓽𝓾𝓿𝔀𝔁𝔂𝔃0123456789")
    private static let frakturChars = Array("𝔄𝔅ℭ𝔇𝔈𝔉𝔊ℌℑ𝔍𝔎𝔏𝔐𝔑𝔒𝔓𝔔ℜ𝔖𝔗𝔘𝔙𝔚𝔛𝔜ℨ𝔞𝔟𝔠𝔡𝔢𝔣𝔤𝔥𝔦𝔧𝔨𝔩𝔪𝔫𝔬𝔭𝔮𝔯𝔰𝔱𝔲𝔳𝔴𝔵𝔶𝔷0123456789")
    private static let doubleStruckChars = Array("𝔸𝔹ℂ𝔻𝔼𝔽𝔾ℍ𝕀𝕁𝕂𝕃𝕄ℕ𝕆ℙℚℝ𝕊𝕋𝕌𝕍𝕎𝕏𝕐ℤ𝕒𝕓𝕔𝕕𝕖𝕗𝕘𝕙𝕚𝕛𝕜𝕝𝕞𝕟𝕠𝕡𝕢𝕣𝕤𝕥𝕦𝕧𝕨𝕩𝕪𝕫𝟘𝟙𝟚𝟛𝟜𝟝𝟞𝟟𝟠𝟡")
    private static let monospaceChars = Array("𝙰𝙱𝙲𝙳𝙴𝙵𝙶𝙷𝙸𝙹𝙺𝙻𝙼𝙽𝙾𝙿𝚀𝚁𝚂𝚃𝚄𝚅𝚆𝚇𝚈𝚉𝚊𝚋𝚌𝚍𝚎𝚏𝚐𝚑𝚒𝚓𝚔𝚕𝚖𝚗𝚘𝚙𝚚𝚛𝚜𝚝𝚞𝚟𝚠𝚡𝚢𝚣𝟶𝟷𝟸𝟹𝟺𝟻𝟼𝟽𝟾𝟿")
    private static let circledChars = Array("ⒶⒷⒸⒹⒺⒻⒼⒽⒾⒿⓀⓁⓂⓃⓄⓅⓆⓇⓈⓉⓊⓋⓌⓍⓎⓏⓐⓑⓒⓓⓔⓕⓖⓗⓘⓙⓚⓛⓜⓝⓞⓟⓠⓡⓢⓣⓤⓥⓦⓧⓨⓩ⓪①②③④⑤⑥⑦⑧⑨")
    private static let fullwidthChars = Array("ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ０１２３４５６７８９")
    private static let smallCapsChars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘǫʀsᴛᴜᴠᴡxʏᴢ0123456789")

    private static func mapTable(for style: StylishFontStyle) -> [Character: Character] {
        let target: [Character]
        switch style {
        case .normal: return [:]
        case .script: target = scriptChars
        case .boldScript: target = boldScriptChars
        case .fraktur: target = frakturChars
        case .doubleStruck: target = doubleStruckChars
        case .monospace: target = monospaceChars
        case .circled: target = circledChars
        case .fullwidth: target = fullwidthChars
        case .smallCaps: target = smallCapsChars
        }
        guard target.count == normalChars.count else { return [:] }
        var dict: [Character: Character] = [:]
        dict.reserveCapacity(normalChars.count)
        for (k, v) in zip(normalChars, target) {
            dict[k] = v
        }
        return dict
    }

    static func convert(_ text: String, style: StylishFontStyle) -> String {
        guard style != .normal else { return text }
        let table = mapTable(for: style)
        return String(text.map { table[$0] ?? $0 })
    }
}

/// 安全的迷你表达式计算器（支持 + - * / % × ÷ ^ 和括号，对齐 WowType calc.rs，算式结果为金额时自动附带人民币大写）。
enum InlineCalculator {
    static func evaluateIfExpression(_ raw: String) -> (result: String, equation: String)? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
        let hasTrailingEquals = cleaned.hasSuffix("=")
        let expr = hasTrailingEquals ? String(cleaned.dropLast()) : cleaned
        guard !expr.isEmpty else { return nil }
        // 必须包含至少一个运算符，避免普通数字被当成算式
        guard expr.contains(where: { "+-*/%^".contains($0) }) else { return nil }
        guard expr.allSatisfy({ $0.isNumber || "+-*/%^(). ".contains($0) }) else { return nil }

        var parser = Parser(expr.filter { !$0.isWhitespace })
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else {
            return nil
        }
        let formatted = format(value)
        return (formatted, "\(expr)=\(formatted)")
    }

    /// WowType `calc::candidates`：支持纯数字转大写金额+中文数字，或算式求值后自动附带结果的人民币大写。
    static func candidates(forVModeBody body: String) -> [String] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let numCands = ChineseNumberConverter.candidates(forNumericString: trimmed)
        if !numCands.isEmpty {
            return numCands
        }
        if let calc = evaluateIfExpression(trimmed) {
            var out = [calc.result, calc.equation]
            if let rmb = ChineseNumberConverter.candidates(forNumericString: calc.result).first,
               !out.contains(rmb) {
                out.append(rmb)
            }
            return out
        }
        if trimmed.allSatisfy({ $0.isNumber || "+-*/%^().".contains($0) }) {
            return [trimmed]
        }
        return []
    }

    private static func format(_ val: Double) -> String {
        if val == 0.0 { return "0" }
        if val.rounded() == val, abs(val) < 1e14 {
            return String(Int64(val))
        }
        let rounded = (val * 1_000_000_000).rounded() / 1_000_000_000
        var s = String(rounded)
        if s.contains(".") {
            while s.last == "0" { s.removeLast() }
            if s.last == "." { s.removeLast() }
        }
        return s
    }

    private struct Parser {
        private let chars: [Character]
        private var index = 0

        init(_ s: String) { self.chars = Array(s) }
        var isAtEnd: Bool { index >= chars.count }

        mutating func parseExpression() -> Double? {
            guard var left = parseTerm() else { return nil }
            while !isAtEnd, chars[index] == "+" || chars[index] == "-" {
                let op = chars[index]
                index += 1
                guard let right = parseTerm() else { return nil }
                left = (op == "+") ? (left + right) : (left - right)
            }
            return left
        }

        private mutating func parseTerm() -> Double? {
            guard var left = parsePower() else { return nil }
            while !isAtEnd, chars[index] == "*" || chars[index] == "/" || chars[index] == "%" {
                let op = chars[index]
                index += 1
                guard let right = parsePower() else { return nil }
                if op == "/" {
                    guard right != 0 else { return nil }
                    left /= right
                } else if op == "%" {
                    guard right != 0 else { return nil }
                    left = left.truncatingRemainder(dividingBy: right)
                } else {
                    left *= right
                }
            }
            return left
        }

        private mutating func parsePower() -> Double? {
            guard let base = parseFactor() else { return nil }
            if !isAtEnd, chars[index] == "^" {
                index += 1
                guard let exp = parsePower() else { return nil }
                return pow(base, exp)
            }
            return base
        }

        private mutating func parseFactor() -> Double? {
            guard !isAtEnd else { return nil }
            if chars[index] == "-" {
                index += 1
                return parseFactor().map { -$0 }
            }
            if chars[index] == "+" {
                index += 1
                return parseFactor()
            }
            if chars[index] == "(" {
                index += 1
                guard let inner = parseExpression(), !isAtEnd, chars[index] == ")" else { return nil }
                index += 1
                return inner
            }
            let start = index
            var sawDot = false
            while !isAtEnd {
                let c = chars[index]
                if c.isNumber {
                    index += 1
                } else if c == "." && !sawDot {
                    sawDot = true
                    index += 1
                } else {
                    break
                }
            }
            guard index > start else { return nil }
            return Double(String(chars[start..<index]))
        }
    }
}

/// 日期与时间快捷生成（完整对齐 WowType datetime.rs 的 7 种日期、6 种时间与 2 种星期格式）。
enum DateTimeHelper {
    private static let weekdayCharacters = ["日", "一", "二", "三", "四", "五", "六"]

    static func candidates(
        forNormalizedPinyin py: String,
        allowShortTriggers: Bool = true,
        now: Date = Date()
    ) -> [String] {
        let key = py.lowercased().replacingOccurrences(of: "'", with: "")
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)
        let y = comps.year ?? 2026
        let mo = comps.month ?? 1
        let d = comps.day ?? 1
        let h = comps.hour ?? 0
        let mi = comps.minute ?? 0
        let s = comps.second ?? 0
        let wkIdx = max(0, min(6, (comps.weekday ?? 1) - 1))
        let week = weekdayCharacters[wkIdx]

        let isDate = (key == "riqi" || key == "date" || key == "jintian") || (allowShortTriggers && (key == "rq" || key == "jt"))
        let isTime = (key == "shijian" || key == "time" || key == "xianzai") || (allowShortTriggers && key == "sj")
        let isWeek = (key == "xingqi" || key == "zhouji") || (allowShortTriggers && key == "xq")

        if isDate {
            return [
                "\(y)年\(mo)月\(d)日",
                String(format: "%04d-%02d-%02d", y, mo, d),
                String(format: "%04d/%02d/%02d", y, mo, d),
                String(format: "%04d.%02d.%02d", y, mo, d),
                String(format: "%04d%02d%02d", y, mo, d),
                "\(mo)月\(d)日",
                "\(y)年\(mo)月\(d)日 星期\(week)",
            ]
        }
        if isTime {
            return [
                String(format: "%02d:%02d", h, mi),
                String(format: "%02d:%02d:%02d", h, mi, s),
                String(format: "%04d-%02d-%02d %02d:%02d", y, mo, d, h, mi),
                String(format: "%04d-%02d-%02d %02d:%02d:%02d", y, mo, d, h, mi, s),
                "\(h)时\(mi)分",
                String(format: "%04d年%d月%d日 %02d:%02d", y, mo, d, h, mi),
            ]
        }
        if isWeek {
            return ["星期\(week)", "周\(week)"]
        }
        return []
    }
}

/// 键盘 `v`（全拼）/ `V`（双拼、五笔）万能离线工具引擎 v4：
/// - 相对日期：`v+3d` / `v-7d` / `v+2w` / `v+1m` / `vmingtian` / `vhoutian` / `vzuotian`
/// - 日期倒计时：`v2027-01-01` → 距目标日期还有 X 天
/// - 精准单位换算：`v180cm` / `v65kg` / `v38c` / `v98f` / `v10km` / `v100ping` / `v1.5gb`
/// - 全民生活速算：AA 分摊 `vaa368/4`、折扣立省 `v299z85`、BMI 健康评估 `vbmi175/68`
/// - 全民财务与极客 v4：房贷月供 `vdk100/30/3.5`、月薪换算时薪 `vsx15000`、多币种速估 `v100usd`/`v10000jpy`、强密码 `vpw16`
/// - 开发者极客快捷生成：`vts`（时间戳 + ISO8601）/ `vuuid`（RFC-4122 UUID）
enum VModeToolEngine {
    private static let weekdayCharacters = ["日", "一", "二", "三", "四", "五", "六"]
    private static let namedDayOffsets: [String: Int] = [
        "zuotian": -1, "zt": -1,
        "mingtian": 1, "mt": 1,
        "houtian": 2, "ht": 2,
        "dahoutian": 3,
        "xiazhou": 7,
    ]
    private static let knownUnitSuffixes: Set<String> = [
        "km", "mi", "cm", "m", "ft", "in", "inch",
        "kg", "jin", "lb", "g",
        "c", "f",
        "ping", "sqm", "mu",
        "tb", "gb", "mb",
        "usd", "eur", "jpy", "hkd", "gbp", "krw", "sgd", "aud", "cad",
    ]

    /// 离线多币种参考汇率（1 外币 ≈ 人民币，仅作聊天快捷估算参考）
    private static let referenceCNYRates: [String: (name: String, rate: Double)] = [
        "usd": ("美元", 7.25),
        "eur": ("欧元", 7.80),
        "jpy": ("日元", 0.048),
        "hkd": ("港币", 0.93),
        "gbp": ("英镑", 9.15),
        "krw": ("韩元", 0.0052),
        "sgd": ("新币", 5.40),
        "aud": ("澳元", 4.72),
        "cad": ("加元", 5.18),
    ]

    static func isRecognizedQuery(_ rawBody: String) -> Bool {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !body.isEmpty else { return false }
        if namedDayOffsets[body] != nil { return true }
        if body == "ts" || body == "timestamp" || body == "uuid" { return true }
        // 输入中间态保持工具模式（如 vuui / vtim / v+3 / v-7 / v180c / v65k / vaa / vbmi / vdk / vsx / vpw / v299z8 / v2027-）
        if "uuid".hasPrefix(body) && body.count >= 2 { return true }
        if "timestamp".hasPrefix(body) && body.count >= 2 { return true }
        if body == "aa" || body.hasPrefix("aa") && body.dropFirst(2).allSatisfy({ $0.isNumber || $0 == "." || $0 == "/" || $0 == "-" }) {
            return true
        }
        if ("bmi".hasPrefix(body) && body.count >= 2)
            || (body.hasPrefix("bmi") && body.dropFirst(3).allSatisfy({ $0.isNumber || $0 == "." || $0 == "/" || $0 == "-" })) {
            return true
        }
        if body == "dk" || (body.hasPrefix("dk") && body.dropFirst(2).allSatisfy({ $0.isNumber || $0 == "." || $0 == "/" || $0 == "-" })) {
            return true
        }
        if body == "sx" || (body.hasPrefix("sx") && body.dropFirst(2).allSatisfy({ $0.isNumber || $0 == "." })) {
            return true
        }
        if body == "pw" || (body.hasPrefix("pw") && body.dropFirst(2).allSatisfy({ $0.isNumber })) {
            return true
        }
        if isDiscountQueryOrPrefix(body) { return true }
        if isCountdownDateOrPrefix(body) { return true }
        if (body.hasPrefix("+") || body.hasPrefix("-")) && body.count >= 2 {
            let rest = body.dropFirst()
            let digits = rest.prefix(while: { $0.isNumber })
            let tail = rest.dropFirst(digits.count)
            if !digits.isEmpty && (tail.isEmpty || ["d", "w", "m", "y"].contains(String(tail))) {
                return true
            }
        }
        if parseNumericWithUnit(body) != nil { return true }
        // 数字 + 单位字母输入中（如 180c / 65k / 100p / 100us）
        if let split = splitLeadingNumberAndAlpha(body), !split.alpha.isEmpty {
            if knownUnitSuffixes.contains(where: { $0.hasPrefix(split.alpha) }) {
                return true
            }
        }
        return false
    }

    static func candidates(forBody rawBody: String, now: Date = Date()) -> [String] {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !body.isEmpty else { return [] }

        // 0. 全民生活与财务速算 v3/v4：AA 分摊 / 折扣立省 / BMI / 房贷月供 / 时薪换算 / 强密码 / 日期倒计时
        if let aaResult = computeAASplit(body) {
            return aaResult
        }
        if let discountResult = computeDiscount(body) {
            return discountResult
        }
        if let bmiResult = computeBMI(body) {
            return bmiResult
        }
        if let loanResult = computeLoanMonthlyPayment(body) {
            return loanResult
        }
        if let salaryResult = computeSalaryBreakdown(body) {
            return salaryResult
        }
        if let pwdResult = generateSecurePassword(body) {
            return pwdResult
        }
        if let countdownResult = computeDateCountdown(body, now: now) {
            return countdownResult
        }

        // 1. 相对日期（命名快捷词 & ±Nd / ±Nw / ±Nm / ±Ny）
        if let days = namedDayOffsets[body] {
            return formatRelativeDate(byAdding: .day, value: days, from: now)
        }
        if (body.hasPrefix("+") || body.hasPrefix("-")), body.count >= 3 {
            let sign = body.hasPrefix("-") ? -1 : 1
            let unitChar = body.last!
            let numStr = String(body.dropFirst().dropLast())
            if let magnitude = Int(numStr), magnitude > 0, magnitude <= 3650 {
                let signed = sign * magnitude
                switch unitChar {
                case "d": return formatRelativeDate(byAdding: .day, value: signed, from: now)
                case "w": return formatRelativeDate(byAdding: .day, value: signed * 7, from: now)
                case "m": return formatRelativeDate(byAdding: .month, value: signed, from: now)
                case "y": return formatRelativeDate(byAdding: .year, value: signed, from: now)
                default: break
                }
            }
        }

        // 2. 极客工具：时间戳 & UUID
        if body == "ts" || body == "timestamp" {
            let sec = Int(now.timeIntervalSince1970)
            let ms = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
            let iso = ISO8601DateFormatter()
            iso.timeZone = TimeZone.current
            return ["\(sec)", iso.string(from: now), "\(ms)"]
        }
        if body == "uuid" {
            let id = UUID().uuidString
            return [id.lowercased(), id.uppercased()]
        }

        // 3. 精准单位换算
        if let parsed = parseNumericWithUnit(body) {
            return convertUnit(value: parsed.value, unit: parsed.unit)
        }
        return []
    }

    // MARK: - v3 生活速算（AA 分摊 / 折扣立省 / BMI / 日期倒计时）

    private static func splitPair(_ rest: String) -> (Double, Double)? {
        let sep: Character? = rest.contains("/") ? "/" : (rest.contains("-") ? "-" : nil)
        guard let sep else { return nil }
        let parts = rest.split(separator: sep, maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let a = Double(parts[0]), let b = Double(parts[1]),
              a.isFinite, b.isFinite else { return nil }
        return (a, b)
    }

    /// AA 聚餐/团建分摊：`vaa368/4` 或 `vaa368-4`
    private static func computeAASplit(_ body: String) -> [String]? {
        guard body.hasPrefix("aa"), let (total, people) = splitPair(String(body.dropFirst(2))) else {
            return nil
        }
        guard total > 0, people >= 2, people <= 999 else { return nil }
        let peopleInt = Int(people.rounded())
        guard Double(peopleInt) == people else { return nil }
        let each = total / Double(peopleInt)
        let eachStr = formatNum(each, decimals: 2)
        let totalStr = formatNum(total, decimals: 2)
        return [
            "人均 ¥\(eachStr)（总计 ¥\(totalStr) ÷ \(peopleInt)人）",
            "¥\(eachStr)",
            eachStr,
        ]
    }

    private static func isDiscountQueryOrPrefix(_ body: String) -> Bool {
        guard let zIdx = body.firstIndex(of: "z"), zIdx > body.startIndex else { return false }
        let pricePart = body[..<zIdx]
        let discPart = body[body.index(after: zIdx)...]
        guard !pricePart.isEmpty,
              pricePart.allSatisfy({ $0.isNumber || $0 == "." }),
              discPart.allSatisfy({ $0.isNumber || $0 == "." }) else { return false }
        return true
    }

    /// 购物折扣立省：`v299z8`（8折）/ `v299z85`（85折）/ `v299z7.5`（7.5折）
    private static func computeDiscount(_ body: String) -> [String]? {
        guard let zIdx = body.firstIndex(of: "z"), zIdx > body.startIndex else { return nil }
        let priceStr = String(body[..<zIdx])
        let discStr = String(body[body.index(after: zIdx)...])
        guard !discStr.isEmpty,
              let price = Double(priceStr), price > 0, price <= 10_000_000,
              let rawDisc = Double(discStr), rawDisc > 0 else { return nil }

        let ratio: Double
        let discLabel: String
        if discStr.contains(".") {
            guard rawDisc < 10 else { return nil }
            ratio = rawDisc / 10.0
            discLabel = "\(discStr)折"
        } else if rawDisc < 10 {
            ratio = rawDisc / 10.0
            discLabel = "\(formatNum(rawDisc, decimals: 0))折"
        } else if rawDisc < 100 {
            ratio = rawDisc / 100.0
            discLabel = "\(formatNum(rawDisc, decimals: 0))折"
        } else {
            return nil
        }

        let finalPrice = price * ratio
        let saved = price - finalPrice
        let finalStr = formatNum(finalPrice, decimals: 2)
        let savedStr = formatNum(saved, decimals: 2)
        return [
            "\(discLabel)折后 ¥\(finalStr)（立省 ¥\(savedStr)）",
            "¥\(finalStr)",
            finalStr,
        ]
    }

    /// BMI 健康评估：`vbmi175/68`（身高 cm / 体重 kg）
    private static func computeBMI(_ body: String) -> [String]? {
        guard body.hasPrefix("bmi"), let (cm, kg) = splitPair(String(body.dropFirst(3))) else {
            return nil
        }
        guard cm >= 80, cm <= 250, kg >= 20, kg <= 300 else { return nil }
        let meters = cm / 100.0
        let bmi = kg / (meters * meters)
        let bmiStr = String(format: "%.1f", bmi)
        let category: String
        if bmi < 18.5 {
            category = "偏瘦"
        } else if bmi < 24.0 {
            category = "正常标准"
        } else if bmi < 28.0 {
            category = "偏胖超重"
        } else {
            category = "肥胖警戒"
        }
        return [
            "BMI \(bmiStr)（\(category)）",
            bmiStr,
        ]
    }

    /// 房贷/分期等额本息速算：`vdk100/30/3.5`（贷款 100 万 / 30 年 / 年利率 3.5%）
    private static func computeLoanMonthlyPayment(_ body: String) -> [String]? {
        guard body.hasPrefix("dk") else { return nil }
        let rest = String(body.dropFirst(2))
        let sep: Character? = rest.contains("/") ? "/" : (rest.contains("-") ? "-" : nil)
        guard let sep else { return nil }
        let parts = rest.split(separator: sep, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let wan = Double(parts[0]), wan > 0, wan <= 10_000,
              let years = Double(parts[1]), years >= 1, years <= 50,
              let annualPct = Double(parts[2]), annualPct >= 0, annualPct <= 36 else {
            return nil
        }
        let principal = wan * 10_000.0
        let months = Int((years * 12.0).rounded())
        guard months >= 1 else { return nil }

        let monthly: Double
        if annualPct == 0 {
            monthly = principal / Double(months)
        } else {
            let r = (annualPct / 100.0) / 12.0
            let factor = pow(1.0 + r, Double(months))
            monthly = principal * r * factor / (factor - 1.0)
        }
        let totalPaid = monthly * Double(months)
        let totalInterestWan = max(0, (totalPaid - principal) / 10_000.0)
        let monthlyStr = formatNum(monthly, decimals: 2)
        let interestStr = formatNum(totalInterestWan, decimals: 2)
        return [
            "月供 ¥\(monthlyStr)（总利息 ¥\(interestStr)万）",
            monthlyStr,
        ]
    }

    /// 月薪换算日薪/时薪：`vsx15000`（按法定 21.75 计薪日、8 小时/天）
    private static func computeSalaryBreakdown(_ body: String) -> [String]? {
        guard body.hasPrefix("sx"), let monthly = Double(String(body.dropFirst(2))),
              monthly >= 100, monthly <= 10_000_000 else {
            return nil
        }
        let daily = monthly / 21.75
        let hourly = daily / 8.0
        let dailyStr = formatNum(daily, decimals: 1)
        let hourlyStr = formatNum(hourly, decimals: 1)
        let annualWan = formatNum(monthly * 12.0 / 10_000.0, decimals: 2)
        return [
            "日薪 ¥\(dailyStr) · 时薪 ¥\(hourlyStr)（年薪约 \(annualWan)万）",
            "时薪 ¥\(hourlyStr)",
            hourlyStr,
        ]
    }

    /// 密码学安全随机强密码生成器：`vpw`（默认 16 位）或 `vpw12` / `vpw20`（8–32 位）
    private static func generateSecurePassword(_ body: String) -> [String]? {
        guard body.hasPrefix("pw") else { return nil }
        let lenStr = String(body.dropFirst(2))
        let length: Int
        if lenStr.isEmpty {
            length = 16
        } else if let n = Int(lenStr), (8...32).contains(n) {
            length = n
        } else {
            return nil
        }
        let upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let lower = Array("abcdefghijkmnopqrstuvwxyz")
        let digits = Array("23456789")
        let symbols = Array("!@#$%^&*-_=+")
        let fullPool = upper + lower + digits + symbols

        func randomIndex(_ bound: Int) -> Int {
            var byte: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            if status == errSecSuccess {
                return Int(byte) % bound
            }
            return Int.random(in: 0..<bound)
        }

        func makeOne(withSymbols: Bool) -> String {
            let pool = withSymbols ? fullPool : (upper + lower + digits)
            var chars: [Character] = [
                upper[randomIndex(upper.count)],
                lower[randomIndex(lower.count)],
                digits[randomIndex(digits.count)],
            ]
            if withSymbols {
                chars.append(symbols[randomIndex(symbols.count)])
            }
            while chars.count < length {
                chars.append(pool[randomIndex(pool.count)])
            }
            // Fisher-Yates shuffle using SecRandomCopyBytes
            for i in stride(from: chars.count - 1, through: 1, by: -1) {
                let j = randomIndex(i + 1)
                if i != j { chars.swapAt(i, j) }
            }
            return String(chars)
        }

        return [makeOne(withSymbols: true), makeOne(withSymbols: false)]
    }

    static func isPasswordQuery(_ rawBody: String) -> Bool {
        let lower = rawBody.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "pw" || (lower.hasPrefix("pw") && lower.dropFirst(2).allSatisfy(\.isNumber))
    }

    private static func isCountdownDateOrPrefix(_ body: String) -> Bool {
        guard body.count >= 5 else { return false }
        let prefix4 = body.prefix(4)
        guard prefix4.allSatisfy({ $0.isNumber }),
              let year = Int(prefix4), year >= 1900, year <= 2200 else { return false }
        let sepIdx = body.index(body.startIndex, offsetBy: 4)
        let sep = body[sepIdx]
        guard sep == "-" || sep == "." else { return false }
        return body[sepIdx...].allSatisfy { $0.isNumber || $0 == sep }
    }

    /// 目标日期倒计时：`v2027-01-01` 或 `v2027.01.01`
    private static func computeDateCountdown(_ body: String, now: Date) -> [String]? {
        let normalized = body.replacingOccurrences(of: ".", with: "-")
        let parts = normalized.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              let y = Int(parts[0]), y >= 1900, y <= 2200,
              let m = Int(parts[1]), (1...12).contains(m),
              let d = Int(parts[2]), (1...31).contains(d) else {
            return nil
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        guard let targetDate = cal.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        let verify = cal.dateComponents([.year, .month, .day], from: targetDate)
        guard verify.year == y, verify.month == m, verify.day == d else { return nil }

        let todayStart = cal.startOfDay(for: now)
        let targetStart = cal.startOfDay(for: targetDate)
        let diffDays = cal.dateComponents([.day], from: todayStart, to: targetStart).day ?? 0
        let formatted = String(format: "%04d-%02d-%02d", y, m, d)
        if diffDays > 0 {
            return ["距 \(formatted) 还有 \(diffDays) 天", "\(diffDays)天"]
        } else if diffDays == 0 {
            return ["\(formatted) 就是今天！", "0天"]
        } else {
            let passed = -diffDays
            return ["\(formatted) 已过去 \(passed) 天", "\(passed)天"]
        }
    }

    private static func formatRelativeDate(byAdding comp: Calendar.Component, value: Int, from now: Date) -> [String] {
        let cal = Calendar(identifier: .gregorian)
        guard let target = cal.date(byAdding: comp, value: value, to: now) else { return [] }
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: target)
        let y = c.year ?? 2026
        let mo = c.month ?? 1
        let d = c.day ?? 1
        let wkIdx = max(0, min(6, (c.weekday ?? 1) - 1))
        let wk = weekdayCharacters[wkIdx]
        return [
            "\(y)年\(mo)月\(d)日（周\(wk)）",
            "\(mo)月\(d)日（周\(wk)）",
            String(format: "%04d-%02d-%02d", y, mo, d),
        ]
    }

    private static func splitLeadingNumberAndAlpha(_ body: String) -> (numberStr: String, alpha: String)? {
        var idx = body.startIndex
        if idx < body.endIndex && body[idx] == "-" {
            idx = body.index(after: idx)
        }
        var sawDigit = false
        var sawDot = false
        while idx < body.endIndex {
            let ch = body[idx]
            if ch.isNumber {
                sawDigit = true
                idx = body.index(after: idx)
            } else if ch == "." && !sawDot {
                sawDot = true
                idx = body.index(after: idx)
            } else {
                break
            }
        }
        guard sawDigit else { return nil }
        let numStr = String(body[..<idx])
        let alpha = String(body[idx...])
        guard alpha.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return (numStr, alpha)
    }

    private static func parseNumericWithUnit(_ body: String) -> (value: Double, unit: String)? {
        guard let split = splitLeadingNumberAndAlpha(body),
              knownUnitSuffixes.contains(split.alpha),
              let val = Double(split.numberStr),
              val.isFinite else {
            return nil
        }
        // 非温度单位不允许负数，避免与算式混淆
        if val < 0 && split.alpha != "c" && split.alpha != "f" {
            return nil
        }
        return (val, split.alpha)
    }

    private static func formatNum(_ v: Double, decimals: Int = 2) -> String {
        let factor = pow(10.0, Double(decimals))
        let rounded = (v * factor).rounded() / factor
        let fmt = String(format: "%.\(decimals)f", rounded)
        if fmt.contains(".") {
            var s = fmt
            while s.last == "0" { s.removeLast() }
            if s.last == "." { s.removeLast() }
            return s == "-0" ? "0" : s
        }
        return fmt
    }

    private static func convertUnit(value v: Double, unit: String) -> [String] {
        switch unit {
        case "km":
            return ["\(formatNum(v * 0.621371)) 英里", "\(formatNum(v * 1000, decimals: 0)) 米"]
        case "usd", "eur", "jpy", "hkd", "gbp", "krw", "sgd", "aud", "cad":
            if let info = referenceCNYRates[unit] {
                let cny = v * info.rate
                let cnyStr = formatNum(cny, decimals: 2)
                return ["≈ ¥\(cnyStr)（\(formatNum(v)) \(info.name)参考价）", "¥\(cnyStr)", cnyStr]
            }
            return []
        case "mi":
            return ["\(formatNum(v * 1.609344)) 公里", "\(formatNum(v * 1609.344, decimals: 0)) 米"]
        case "cm":
            let totalInches = v / 2.54
            let feet = Int(totalInches / 12.0)
            let remInches = Int((totalInches - Double(feet) * 12.0).rounded())
            let adjFeet = remInches == 12 ? feet + 1 : feet
            let adjIn = remInches == 12 ? 0 : remInches
            return ["\(formatNum(v / 100.0)) 米", "\(adjFeet)'\(adjIn)\"", "\(formatNum(totalInches)) 英寸"]
        case "m":
            return ["\(formatNum(v * 100.0, decimals: 0)) 厘米", "\(formatNum(v * 3.28084)) 英尺"]
        case "ft":
            return ["\(formatNum(v * 30.48, decimals: 1)) 厘米", "\(formatNum(v * 0.3048)) 米"]
        case "in", "inch":
            return ["\(formatNum(v * 2.54)) 厘米", "\(formatNum(v * 25.4, decimals: 1)) 毫米"]
        case "kg":
            return ["\(formatNum(v * 2.0)) 斤", "\(formatNum(v * 2.20462, decimals: 1)) 磅"]
        case "jin":
            return ["\(formatNum(v * 0.5)) 公斤", "\(formatNum(v * 500.0, decimals: 0)) 克"]
        case "lb":
            return ["\(formatNum(v * 0.453592)) 公斤", "\(formatNum(v * 0.907185)) 斤"]
        case "g":
            return ["\(formatNum(v / 500.0)) 斤", "\(formatNum(v / 1000.0, decimals: 3)) 公斤"]
        case "c":
            return ["\(formatNum(v * 9.0 / 5.0 + 32.0, decimals: 1)) °F", "\(formatNum(v + 273.15)) K"]
        case "f":
            return ["\(formatNum((v - 32.0) * 5.0 / 9.0, decimals: 1)) °C"]
        case "ping", "sqm":
            return ["\(formatNum(v)) ㎡", "\(formatNum(v * 10.7639, decimals: 1)) 平方英尺"]
        case "mu":
            return ["\(formatNum(v * 666.6667, decimals: 1)) ㎡", "\(formatNum(v * 0.066667, decimals: 3)) 公顷"]
        case "tb":
            return ["\(formatNum(v * 1024.0, decimals: 0)) GB"]
        case "gb":
            return ["\(formatNum(v * 1024.0, decimals: 0)) MB", "\(formatNum(v / 1024.0, decimals: 3)) TB"]
        case "mb":
            return ["\(formatNum(v / 1024.0, decimals: 3)) GB", "\(formatNum(v * 1024.0, decimals: 0)) KB"]
        default:
            return []
        }
    }
}

/// 趣味小工具。
enum FunGenerator {
    private static let foodChoices = [
        "🍜 兰州牛肉面", "🍲 麻辣烫", "🍣 三文鱼寿司", "🍔 汉堡薯条",
        "🥘 番茄牛腩饭", "🧋 烤鸭饭 + 冰美式", "🥟 手工水饺", "🍗 脆皮炸鸡",
        "🌶️ 川味水煮肉片", "🥗 轻食鸡胸肉沙拉"
    ]

    private static let fortuneChoices = [
        "🎋 上上签：今日宜大胆表白、提交代码一次过",
        "✨ 上吉：贵人相助，等的好消息正在路上",
        "☕ 中吉：宜摸鱼喝杯热拿铁，灵感马上到账",
        "🚀 大吉：效率爆棚，今天做事顺风顺水",
    ]

    static func rollDice() -> String {
        let face = Int.random(in: 1...6)
        return "🎲 掷出了 \(face) 点"
    }

    static func flipCoin() -> String {
        Bool.random() ? "🪙 正面（冲！）" : "🪙 反面（稳一手）"
    }

    static func randomMeal() -> String {
        "🍽️ 今天吃：\(foodChoices.randomElement() ?? "🍜 牛肉面")"
    }

    static func randomFortune() -> String {
        fortuneChoices.randomElement() ?? "✨ 今日好运加持"
    }
}

/// 繁体中文输出标准（对标 OpenCC：标准繁体 / 台湾正体含两岸惯用词 / 香港繁体）。
enum TraditionalChineseVariant: String, Codable, CaseIterable, Identifiable {
    case standard
    case taiwanPhrase
    case hongKong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "OpenCC 标准繁体"
        case .taiwanPhrase: return "台湾正体（含惯用词）"
        case .hongKong: return "香港繁体"
        }
    }

    var shortBadge: String {
        switch self {
        case .standard: return "标"
        case .taiwanPhrase: return "台"
        case .hongKong: return "港"
        }
    }
}

/// OpenCC 级「两岸三地简繁词级双向转换引擎」：
/// - 100+ 高频一简多繁歧义消解词表（皇后/以后、头发/发展、干净/干活、面条/方面、一只/只有、台风/舞台、里面/公里…）；
/// - 台湾正体 70+ 两岸 IT/科技/生活惯用词双向映射（软件↔軟體、内存↔記憶體、鼠标↔滑鼠、服务器↔伺服器、默认↔預設、打印↔列印…）；
/// - 香港繁体惯用词表（软件→軟件、出租车→的士、公交车→巴士、程序→程式…）；
/// - 采用按长度哈希最大正向匹配（Max-Forward Match），比线性扫描提速 10× 以上，保持键盘候选 0.05ms 零感知延迟。
enum ChineseScriptConverter {
    /// 通用一简多繁精确消歧词表（所有繁体标准共享）
    private static let baseDisambiguationDict: [String: String] = [
        // 发 (髮 vs 發)
        "头发": "頭髮", "理发": "理髮", "美发": "美髮", "脱发": "脫髮", "白发": "白髮",
        "卷发": "捲髮", "长发": "長髮", "短发": "短髮", "黑发": "黑髮", "洗发": "洗髮",
        "发展": "發展", "发现": "發現", "出发": "出發", "发财": "發財", "发送": "發送",
        "发布": "發布", "发烧": "發燒", "发挥": "發揮", "发言": "發言", "发明": "發明",
        // 后 (后 vs 後)
        "皇后": "皇后", "太后": "太后", "天后": "天后", "影后": "影后", "王后": "王后",
        "后来": "後來", "以后": "以後", "后面": "後面", "然后": "然後", "最后": "最後",
        "背后": "背後", "后果": "後果", "后台": "後台", "后续": "後續", "后悔": "後悔",
        // 干 (乾 vs 幹 vs 干)
        "干净": "乾淨", "饼干": "餅乾", "干燥": "乾燥", "干杯": "乾杯", "干脆": "乾脆",
        "干洗": "乾洗", "风干": "風乾", "晒干": "曬乾", "烘干": "烘乾", "葡萄干": "葡萄乾",
        "干部": "幹部", "干活": "幹活", "能干": "能幹", "骨干": "骨幹", "树干": "樹幹",
        "干嘛": "幹嘛", "干什么": "幹什麼", "干涉": "干涉", "干扰": "干擾", "若干": "若干",
        // 面 (麵 vs 面)
        "面条": "麵條", "方便面": "方便麵", "泡面": "泡麵", "拉面": "拉麵", "面粉": "麵粉",
        "面包": "麵包", "挂面": "掛麵", "煮面": "煮麵", "炒面": "炒麵", "拌面": "拌麵",
        "面对": "面對", "方面": "方面", "全面": "全面", "画面": "畫面", "界面": "界面",
        // 里 (裡 vs 里)
        "里面": "裡面", "里头": "裡頭", "心里": "心裡", "家里": "家裡", "这里": "這裡",
        "那里": "那裡", "哪里": "哪裡", "公里": "公里", "里程": "里程", "邻里": "鄰里",
        // 只 (隻 vs 只)
        "一只": "一隻", "两只": "兩隻", "三只": "三隻", "几只": "幾隻", "船只": "船隻",
        "只有": "只有", "只是": "只是", "只要": "只要", "只能": "只能", "只好": "只好",
        // 台 (颱 vs 臺/台)
        "台风": "颱風", "强台风": "強颱風", "舞台": "舞台", "平台": "平台", "后台服务": "後台服務",
        // 表 / 松 / 系 / 复 / 历 / 划 / 钟 / 卷 / 征 / 余 / 板
        "手表": "手錶", "怀表": "懷錶", "秒表": "秒錶", "电表": "電錶", "水表": "水錶",
        "表面": "表面", "表达": "表達", "表示": "表示", "表格": "表格",
        "放松": "放鬆", "轻松": "輕鬆", "松手": "鬆手", "松弛": "鬆弛", "松散": "鬆散",
        "松树": "松樹", "松鼠": "松鼠", "松果": "松果",
        "联系": "聯繫", "关系": "關係", "系统": "系統", "系列": "系列",
        "复杂": "複雜", "复制": "複製", "复习": "複習", "回复": "回復", "恢复": "恢復", "反复": "反覆",
        "日历": "日曆", "农历": "農曆", "公历": "公曆", "历史": "歷史", "经历": "經歷", "简历": "簡歷",
        "计划": "計劃", "规划": "規劃", "策划": "策劃", "划算": "划算", "划船": "划船", "画画": "畫畫",
        "时钟": "時鐘", "闹钟": "鬧鐘", "分钟": "分鐘", "钟爱": "鍾愛", "钟情": "鍾情",
        "试卷": "試卷", "答卷": "答卷", "画卷": "畫卷", "卷起": "捲起", "胶卷": "膠捲",
        "云端": "雲端", "乌云": "烏雲", "云彩": "雲彩", "电脑": "電腦", "游览": "遊覽", "游泳": "游泳",
        "老板": "老闆", "板凳": "板凳", "占领": "佔領", "占据": "佔據", "占有": "佔有", "占卜": "占卜",
        "征求": "徵求", "征集": "徵集", "特征": "特徵", "长征": "長征", "远征": "遠征",
        "余下": "餘下", "其余": "其餘", "剩余": "剩餘", "多余": "多餘", "业余": "業餘",
    ]

    /// 台湾正体两岸惯用词映射（Simp -> TW Phrase）
    private static let taiwanRegionalDict: [String: String] = [
        "软件": "軟體", "硬件": "硬體", "固件": "韌體", "内存": "記憶體", "硬盘": "硬碟",
        "固态硬盘": "固態硬碟", "移动硬盘": "行動硬碟", "U盘": "隨身碟", "u盘": "隨身碟",
        "鼠标": "滑鼠", "服务器": "伺服器", "默认": "預設", "打印": "列印", "打印机": "印表機",
        "屏幕": "螢幕", "截图": "截圖", "截屏": "截圖", "录屏": "錄影", "网络": "網路",
        "互联网": "網際網路", "宽带": "寬頻", "蓝牙": "藍牙", "人工智能": "人工智慧",
        "算法": "演算法", "数据库": "資料庫", "程序": "程式", "程序员": "程式設計師",
        "代码": "程式碼", "源代码": "原始碼", "操作系统": "作業系統", "文件夹": "資料夾",
        "主板": "主機板", "显卡": "顯示卡", "芯片": "晶片", "像素": "畫素", "分辨率": "解析度",
        "视频": "影片", "音频": "音訊", "信息": "資訊", "消息": "訊息", "链接": "連結",
        "点击": "點擊", "双击": "雙擊", "兼容": "相容", "优化": "最佳化", "崩溃": "當機",
        "死机": "當機", "重启": "重新開機", "博客": "部落格", "公众号": "公眾號", "小程序": "小程式",
        "高清": "高畫質", "移动电源": "行動電源", "充电宝": "行動電源", "激光": "雷射",
        "出租车": "計程車", "地铁": "捷運", "公交车": "公車", "高铁": "高鐵", "快递": "快遞",
        "外卖": "外送", "空调": "冷氣", "方便面": "泡麵", "酸奶": "優格", "土豆": "馬鈴薯",
        "菠萝": "鳳梨", "猕猴桃": "奇異果", "幼儿园": "幼兒園", "卫生间": "洗手間",
        "数据": "資料", "接口": "介面", "界面": "介面", "交互": "互動", "缓存": "快取",
        "日志": "日誌", "账号": "帳號", "登录": "登入", "注销": "登出", "刷新": "重新整理",
        "粘贴": "貼上", "剪切": "剪下", "搜索": "搜尋", "设置": "設定", "同步": "同步",
    ]

    /// 香港繁体惯用词映射（Simp -> HK Phrase）
    private static let hongKongRegionalDict: [String: String] = [
        "软件": "軟件", "硬件": "硬件", "程序": "程式", "打印": "列印", "默认": "預設",
        "出租车": "的士", "公交车": "巴士", "地铁": "地鐵", "方便面": "即食麵",
        "激光": "鐳射", "土豆": "薯仔", "菠萝": "菠蘿", "猕猴桃": "奇異果",
        "鼠标": "滑鼠", "服务器": "伺服器", "内存": "記憶體", "屏幕": "螢幕",
        "粘贴": "貼上", "登录": "登入", "账号": "帳號", "搜索": "搜尋", "设置": "設定",
    ]

    /// 繁转简两岸惯用词逆向归并表（TW/HK -> 大陆简体常用词）
    private static let reverseRegionalToSimpDict: [String: String] = [
        "軟體": "软件", "硬體": "硬件", "韌體": "固件", "記憶體": "内存", "硬碟": "硬盘",
        "固態硬碟": "固态硬盘", "行動硬碟": "移动硬盘", "隨身碟": "U盘",
        "滑鼠": "鼠标", "伺服器": "服务器", "預設": "默认", "列印": "打印", "印表機": "打印机",
        "螢幕": "屏幕", "網路": "网络", "網際網路": "互联网", "寬頻": "宽带",
        "人工智慧": "人工智能", "演算法": "算法", "資料庫": "数据库", "程式碼": "代码",
        "原始碼": "源代码", "作業系統": "操作系统", "資料夾": "文件夹", "主機板": "主板",
        "顯示卡": "显卡", "畫素": "像素", "解析度": "分辨率", "音訊": "音频",
        "資訊": "信息", "最佳化": "优化", "當機": "崩溃", "部落格": "博客",
        "高畫質": "高清", "行動電源": "充电宝", "雷射": "激光", "計程車": "出租车",
        "捷運": "地铁", "泡麵": "方便面", "即食麵": "方便面", "優格": "酸奶",
        "馬鈴薯": "土豆", "鳳梨": "菠萝", "奇異果": "猕猴桃", "快取": "缓存",
        "登入": "登录", "登出": "注销", "貼上": "粘贴", "搜尋": "搜索", "設定": "设置",
        "的士": "出租车", "薯仔": "土豆",
    ]

    private static let mergedStandardDict: [String: String] = baseDisambiguationDict
    private static let mergedTaiwanDict: [String: String] = baseDisambiguationDict.merging(taiwanRegionalDict) { _, tw in tw }
    private static let mergedHongKongDict: [String: String] = baseDisambiguationDict.merging(hongKongRegionalDict) { _, hk in hk }

    private static func maxForwardReplace(_ text: String, dict: [String: String], maxKeyLen: Int = 4, fallbackTransform: (String) -> String) -> String {
        guard !text.isEmpty else { return text }
        let chars = Array(text)
        let n = chars.count
        var out = ""
        out.reserveCapacity(n)
        var pending = ""
        var i = 0

        func flushPending() {
            guard !pending.isEmpty else { return }
            out.append(fallbackTransform(pending))
            pending.removeAll(keepingCapacity: true)
        }

        while i < n {
            var matchedLen = 0
            var matchedVal = ""
            let upper = min(maxKeyLen, n - i)
            if upper >= 2 {
                for len in stride(from: upper, through: 2, by: -1) {
                    let sub = String(chars[i..<(i + len)])
                    if let val = dict[sub] {
                        matchedLen = len
                        matchedVal = val
                        break
                    }
                }
            }
            if matchedLen > 0 {
                flushPending()
                out.append(matchedVal)
                i += matchedLen
            } else {
                pending.append(chars[i])
                i += 1
            }
        }
        flushPending()
        return out
    }

    static func toTraditional(_ text: String, variant: TraditionalChineseVariant = .taiwanPhrase) -> String {
        let dict: [String: String]
        switch variant {
        case .standard: dict = mergedStandardDict
        case .taiwanPhrase: dict = mergedTaiwanDict
        case .hongKong: dict = mergedHongKongDict
        }
        return maxForwardReplace(text, dict: dict, maxKeyLen: 4) { segment in
            let mutable = NSMutableString(string: segment)
            CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, true)
            return mutable as String
        }
    }

    static func toSimplified(_ text: String, normalizeRegionalTerms: Bool = true) -> String {
        let dict = normalizeRegionalTerms ? reverseRegionalToSimpDict : [:]
        return maxForwardReplace(text, dict: dict, maxKeyLen: 4) { segment in
            let mutable = NSMutableString(string: segment)
            CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
            return mutable as String
        }
    }
}

/// 成对括号与引号统一智能引擎（支持 12 组中英文括号/书名号/引号）：
/// - 单开括号自动补全闭括号并将光标置入中间（含 `{}`、`『』`、`〈〉`）
/// - 快捷划动/符号面板直接插入成对串（如 `()`、`{}`、`「」`、`《》`）时同样自动将光标置入中间 `(|)`
/// - 光标紧邻右侧闭括号时再次输入闭括号直接越过不重复
/// - 光标位于空括号中间按 ⌫ 一次连删整对
enum PairedBracketHelper {
    static let openToPair: [String: String] = [
        "(": "()",
        "[": "[]",
        "{": "{}",
        "（": "（）",
        "「": "「」",
        "『": "『』",
        "【": "【】",
        "《": "《》",
        "〈": "〈〉",
    ]

    static let closers: Set<String> = [")", "]", "}", ">", "）", "」", "』", "】", "》", "〉"]

    static let prePairedTokens: Set<String> = [
        "()", "[]", "{}", "<>", "（）", "「」", "『』", "【】", "《》", "〈〉", "“”", "‘’",
    ]

    static func expandedPair(for opening: String) -> String? {
        openToPair[opening]
    }

    static func shouldSkipCloser(_ text: String, nextChar: Character?) -> Bool {
        guard closers.contains(text), let nextChar else { return false }
        return String(nextChar) == text
    }

    static func shouldAutoPlaceCursorInside(_ text: String) -> Bool {
        prePairedTokens.contains(text)
    }

    static func isMatchingPair(left: Character, right: Character) -> Bool {
        switch (left, right) {
        case ("(", ")"), ("[", "]"), ("{", "}"), ("<", ">"),
             ("（", "）"), ("「", "」"), ("『", "』"), ("【", "】"),
             ("《", "》"), ("〈", "〉"), ("“", "”"), ("‘", "’"):
            return true
        default:
            return false
        }
    }
}

/// 0ms 纯本地「选区原地包裹与大小写转换」引擎（无需联网、不耗 AI Token）：
/// 选中文字后 1 点套上 `「」` / `《》` / `（）` / `“”` / `**加粗**` / 行内代码或轮换英文大小写。
public enum SelectionTextTransform: String, CaseIterable, Sendable {
    case wrapCornerQuote
    case wrapBookTitle
    case wrapParen
    case wrapDoubleQuote
    case wrapMarkdownBold
    case cycleCase

    public var pillTitle: String {
        switch self {
        case .wrapCornerQuote: return "「」"
        case .wrapBookTitle: return "《》"
        case .wrapParen: return "（）"
        case .wrapDoubleQuote: return "“”"
        case .wrapMarkdownBold: return "**粗**"
        case .cycleCase: return "Aa"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .wrapCornerQuote: return "用直角引号包裹选中文字"
        case .wrapBookTitle: return "用书名号包裹选中文字"
        case .wrapParen: return "用中文括号包裹选中文字"
        case .wrapDoubleQuote: return "用中文双引号包裹选中文字"
        case .wrapMarkdownBold: return "用 Markdown 加粗包裹选中文字"
        case .cycleCase: return "切换选中英文的大小写"
        }
    }

    public func apply(to text: String) -> String {
        guard !text.isEmpty else { return text }
        switch self {
        case .wrapCornerQuote:
            return toggleWrap(text, open: "「", close: "」")
        case .wrapBookTitle:
            return toggleWrap(text, open: "《", close: "》")
        case .wrapParen:
            return toggleWrap(text, open: "（", close: "）")
        case .wrapDoubleQuote:
            return toggleWrap(text, open: "“", close: "”")
        case .wrapMarkdownBold:
            return toggleWrap(text, open: "**", close: "**")
        case .cycleCase:
            if text == text.uppercased() && text != text.lowercased() {
                return text.lowercased()
            } else if text == text.lowercased() {
                return text.capitalized
            } else {
                return text.uppercased()
            }
        }
    }

    private func toggleWrap(_ text: String, open: String, close: String) -> String {
        if text.hasPrefix(open) && text.hasSuffix(close) && text.count >= open.count + close.count {
            return String(text.dropFirst(open.count).dropLast(close.count))
        }
        return open + text + close
    }
}

/// 智能中英文标点转换（移植自 WowType symbols.rs）：
/// - 支持中文全角 / 英文半角一键切换；
/// - 数字后自动保留半角 `.` `:` `,`（如 `3.14`、`20:22`、`3,000`）；
/// - `"` / `'` 自动交替配对中文弯引号 `“`/`”` 与 `‘`/`’`；
/// - `{`→`「` `}`→`」` `\`→`、` `^`→`……` `_`→`——` `$`→`￥` `` ` ``→`·`；`@ # % & *` 恒定半角。
enum SmartPunctuation {
    private static let fullwidthMap: [String: String] = [
        ",": "，",
        ".": "。",
        "?": "？",
        "!": "！",
        ";": "；",
        ":": "：",
        "(": "（",
        ")": "）",
        "[": "【",
        "]": "】",
        "{": "「",
        "}": "」",
        "<": "《",
        ">": "》",
        "\\": "、",
        "^": "……",
        "_": "——",
        "$": "￥",
        "`": "·",
        "~": "～",
    ]

    private static let digitKeepHalfwidth: Set<String> = [".", ":", ","]

    static func convert(
        _ input: String,
        style: PunctuationStyle,
        beforeCursor: String?,
        smartQuotePairing: Bool = true,
        openDoubleQuote: inout Bool,
        openSingleQuote: inout Bool
    ) -> String {
        guard style == .fullwidth else { return input }

        // 数字后的小数点、冒号、千分位逗号自动保留半角（3.14 / 20:22 / 3,000）
        if let prev = beforeCursor?.last, prev.isASCII && prev.isNumber {
            if digitKeepHalfwidth.contains(input) {
                return input
            }
            if input == "。" { return "." }
            if input == "，" { return "," }
            if input == "：" { return ":" }
        }

        if input == "\"" || input == "“" || input == "”" {
            if smartQuotePairing {
                let out = openDoubleQuote ? "”" : "“"
                openDoubleQuote.toggle()
                return out
            }
            return "“"
        }
        if input == "'" || input == "‘" || input == "’" {
            if smartQuotePairing {
                let out = openSingleQuote ? "’" : "‘"
                openSingleQuote.toggle()
                return out
            }
            return "‘"
        }

        return fullwidthMap[input] ?? input
    }
}

/// 中英文混排自动空格（盘古之白）：支持汉字与字母、汉字与数字分别独立开关。
enum PanguSpacer {
    static func needsLeadingSpace(
        beforeCursor: String?,
        inserting: String,
        spaceLetters: Bool,
        spaceDigits: Bool
    ) -> Bool {
        guard spaceLetters || spaceDigits,
              let before = beforeCursor,
              let prev = before.last,
              let next = inserting.first else {
            return false
        }
        if prev.isWhitespace || next.isWhitespace { return false }

        if isHan(prev) {
            return (spaceLetters && isAsciiLetter(next)) || (spaceDigits && next.isNumber && next.isASCII)
        }
        if isHan(next) {
            return (spaceLetters && isAsciiLetter(prev)) || (spaceDigits && prev.isNumber && prev.isASCII)
        }
        return false
    }

    private static func isHan(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0xF900...0xFAFF).contains(v)
            || (0x20000...0x3134F).contains(v)
    }

    private static func isAsciiLetter(_ ch: Character) -> Bool {
        ch.isASCII && ch.isLetter
    }
}

/// 人民币大写金额与中文数字读法转换（WowType `v12345.67` 同款）。
enum ChineseNumberConverter {
    private static let upperDigits = ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"]
    private static let lowerDigits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
    private static let upperSmallUnits = ["", "拾", "佰", "仟"]
    private static let lowerSmallUnits = ["", "十", "百", "千"]
    private static let bigUnits = ["", "万", "亿", "兆"]

    /// 转换为财务报销专用大写人民币金额与标准中文数字。
    static func candidates(forNumericString raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let number = Double(trimmed),
              number >= 0,
              number < 1_000_000_000_000.0 else {
            return []
        }

        let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return [] }
        let intStr = String(parts[0])
        let fracStr = parts.count == 2 ? String(parts[1]) : ""
        guard !intStr.isEmpty, intStr.allSatisfy(\.isNumber), fracStr.allSatisfy(\.isNumber) else {
            return []
        }
        guard let intVal = UInt64(intStr) else { return [] }

        var results: [String] = []
        let rmb = formatRMB(intVal: intVal, fracStr: fracStr)
        if !rmb.isEmpty { results.append(rmb) }

        let lower = formatChineseNumber(intVal: intVal, fracStr: fracStr, uppercase: false)
        if !lower.isEmpty && !results.contains(lower) { results.append(lower) }

        let upper = formatChineseNumber(intVal: intVal, fracStr: fracStr, uppercase: true)
        if !upper.isEmpty && !results.contains(upper) { results.append(upper) }

        return results
    }

    private static func formatRMB(intVal: UInt64, fracStr: String) -> String {
        let paddedFrac = (fracStr + "00").prefix(2)
        let jiao = Int(String(paddedFrac.prefix(1))) ?? 0
        let fen = Int(String(paddedFrac.suffix(1))) ?? 0

        if intVal == 0 && jiao == 0 && fen == 0 {
            return "零元整"
        }

        var out = ""
        if intVal > 0 {
            out += formatInteger(intVal, uppercase: true) + "元"
        }
        if jiao == 0 && fen == 0 {
            out += "整"
        } else {
            if intVal > 0 && jiao == 0 {
                out += "零"
            }
            if jiao > 0 {
                out += upperDigits[jiao] + "角"
            }
            if fen > 0 {
                out += upperDigits[fen] + "分"
            }
        }
        return out
    }

    private static func formatChineseNumber(intVal: UInt64, fracStr: String, uppercase: Bool) -> String {
        let digits = uppercase ? upperDigits : lowerDigits
        var out = formatInteger(intVal, uppercase: uppercase)
        if !fracStr.isEmpty {
            out += "点"
            for ch in fracStr {
                if let d = Int(String(ch)), d >= 0 && d <= 9 {
                    out += digits[d]
                }
            }
        }
        return out
    }

    private static func formatInteger(_ value: UInt64, uppercase: Bool) -> String {
        let digits = uppercase ? upperDigits : lowerDigits
        let smallUnits = uppercase ? upperSmallUnits : lowerSmallUnits
        if value == 0 { return digits[0] }

        var sections: [Int] = []
        var rem = value
        while rem > 0 {
            sections.append(Int(rem % 10000))
            rem /= 10000
        }

        var parts: [String] = []
        var needZeroBridge = false
        for secIdx in stride(from: sections.count - 1, through: 0, by: -1) {
            let sec = sections[secIdx]
            if sec == 0 {
                needZeroBridge = !parts.isEmpty
                continue
            }
            var secStr = ""
            if needZeroBridge || (!parts.isEmpty && sec < 1000) {
                secStr += digits[0]
            }
            secStr += formatSection(sec, digits: digits, smallUnits: smallUnits, trimLeadingOneTen: !uppercase && parts.isEmpty)
            if secIdx > 0 && secIdx < bigUnits.count {
                secStr += bigUnits[secIdx]
            }
            parts.append(secStr)
            needZeroBridge = false
        }
        return parts.joined()
    }

    private static func formatSection(_ sec: Int, digits: [String], smallUnits: [String], trimLeadingOneTen: Bool) -> String {
        var result = ""
        var zeroPending = false
        let divisors = [1000, 100, 10, 1]
        for (pos, div) in divisors.enumerated() {
            let d = (sec / div) % 10
            let unitIdx = 3 - pos
            if d == 0 {
                if !result.isEmpty { zeroPending = true }
            } else {
                if zeroPending {
                    result += digits[0]
                    zeroPending = false
                }
                if !(trimLeadingOneTen && result.isEmpty && unitIdx == 1 && d == 1) {
                    result += digits[d]
                }
                result += smallUnits[unitIdx]
            }
        }
        return result
    }
}
