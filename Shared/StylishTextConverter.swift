import Foundation

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

/// 基于系统 ICU 引擎 + 常见一简多繁词组修正（OpenCC 思路，解决 头发/干净/皇后/面条/一只/台风 等歧义）。
enum ChineseScriptConverter {
    private static let phraseOverrides: [(String, String)] = [
        ("头发", "頭髮"), ("干净", "乾淨"), ("皇后", "皇后"), ("面条", "麵條"),
        ("一只", "一隻"), ("台风", "颱風"), ("放松", "放鬆"), ("松鼠", "松鼠"),
        ("后来", "後來"), ("以后", "以後"), ("手表", "手錶"), ("饼干", "餅乾"),
        ("干部", "幹部"), ("干活", "幹活"), ("里面", "裡面"), ("后面", "後面"),
        ("联系", "聯繫"), ("关系", "關係"), ("发展", "發展"), ("发现", "發現"),
        ("出发", "出發"), ("发财", "發財"), ("计划", "計劃"), ("画画", "畫畫"),
        ("系统", "系統"), ("云端", "雲端"), ("电脑", "電腦"), ("软件", "軟體"),
    ]

    static func toTraditional(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var remaining = text
        var tokens: [(String, Bool)] = []
        while !remaining.isEmpty {
            var matched: (String, String)?
            for pair in phraseOverrides where remaining.hasPrefix(pair.0) {
                matched = pair
                break
            }
            if let (simp, trad) = matched {
                tokens.append((trad, true))
                remaining.removeFirst(simp.count)
            } else {
                let first = String(remaining.removeFirst())
                if let last = tokens.last, !last.1 {
                    tokens[tokens.count - 1].0.append(first)
                } else {
                    tokens.append((first, false))
                }
            }
        }
        return tokens.map { segment, isFixed in
            if isFixed { return segment }
            let mutable = NSMutableString(string: segment)
            CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, true)
            return mutable as String
        }.joined()
    }

    static func toSimplified(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
        return mutable as String
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
