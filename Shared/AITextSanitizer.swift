import Foundation

/// AI 输出文本纯净清洗器（零第三方依赖，可供主 App / 键盘扩展 / 单元测试共用）：
/// 彻底清除大模型习惯性输出的 `*`、`**`、`###`、`---`、反引号等 Markdown 乱码符号，
/// 同时完整保留正常算式（如 `2*3=6`、`5 * 8`）与自然中文标点，确保内容随时可直接粘贴发微信/聊天。
public enum AITextSanitizer {
    /// 统一注入到系统提示词的强硬纯文本格式规则
    public static let plainTextOutputRule: String = """
    【强制输出格式要求】严禁使用任何 Markdown 语法，绝对不要输出 *、**、***、#、##、###、`、```、~~、>、--- 等符号；只输出干净自然、可直接复制到微信发送的纯文本；需要分点说明时请使用「1.」「2.」或「• 」配合自然换行。
    """

    private static let codeFenceRegex = try? NSRegularExpression(pattern: #"(?m)^\s*```[A-Za-z0-9_+-]*\s*$"#)
    private static let headingRegex = try? NSRegularExpression(pattern: #"(?m)^[ \t]{0,3}#{1,6}[ \t]+"#)
    private static let quoteRegex = try? NSRegularExpression(pattern: #"(?m)^[ \t]*>[ \t]?"#)
    private static let hrRegex = try? NSRegularExpression(pattern: #"(?m)^[ \t]*(\*{3,}|-{3,}|_{3,})[ \t]*$"#)
    private static let bulletRegex = try? NSRegularExpression(pattern: #"(?m)^([ \t]*)[*\-+][ \t]+"#)
    private static let boldAsteriskRegex = try? NSRegularExpression(pattern: #"\*\*([^\n*]+?)\*\*"#)
    private static let boldUnderscoreRegex = try? NSRegularExpression(pattern: #"__([^\n_]+?)__"#)
    private static let strikeRegex = try? NSRegularExpression(pattern: #"~~([^\n~]+?)~~"#)
    private static let italicAsteriskRegex = try? NSRegularExpression(pattern: #"\*([^*\n]+?)\*"#)
    private static let inlineCodeRegex = try? NSRegularExpression(pattern: #"`([^`\n]+)`"#)
    private static let markdownLinkRegex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#)
    private static let strayMultiAsteriskRegex = try? NSRegularExpression(pattern: #"\*{2,}"#)
    private static let multiBlankLinesRegex = try? NSRegularExpression(pattern: #"\n{3,}"#)

    /// 清洗 AI 输出文本中的 Markdown 符号（`streaming == true` 时保留尾部自然空格以免光标跳动，`false` 时做首尾裁剪）。
    public static func clean(_ raw: String, streaming: Bool = false) -> String {
        guard !raw.isEmpty else { return "" }
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")

        // 1. 移除代码块围栏 ```swift / ```
        text = replace(text, regex: codeFenceRegex, with: "")
        // 2. 移除 Markdown 水平分割线 --- / *** / ___
        text = replace(text, regex: hrRegex, with: "")
        // 3. 移除行首标题井号 ### 标题 -> 标题
        text = replace(text, regex: headingRegex, with: "")
        // 4. 移除行首引用符号 > 
        text = replace(text, regex: quoteRegex, with: "")
        // 5. 行首列表项 `* 内容` / `- 内容` -> `• 内容`
        text = replace(text, regex: bulletRegex, with: "$1• ")
        // 6. 链接 [标题](url) -> 标题 (url)
        text = replace(text, regex: markdownLinkRegex, with: "$1 ($2)")
        // 7. 粗体 **text** / __text__ & 删除线 ~~text~~ & 行内代码 `text`（重复两轮兼容嵌套 ***text***）
        for _ in 0..<2 {
            text = replace(text, regex: boldAsteriskRegex, with: "$1")
            text = replace(text, regex: boldUnderscoreRegex, with: "$1")
            text = replace(text, regex: strikeRegex, with: "$1")
            text = replace(text, regex: inlineCodeRegex, with: "$1")
        }
        // 8. 斜体 *text*（保护 `2*3=6`、`5 * 8` 算式中的乘号）
        text = stripItalicAsterisks(text)
        // 9. 清理残余的成串星号（如流式未闭合的 `**` / `***` 或行首/行尾孤立 `**`）
        text = replace(text, regex: strayMultiAsteriskRegex, with: "")
        // 10. 清理单个孤立的非算式星号（例如流式刚输出 `*重点` 还未闭合，但绝不伤及 `2*3`）
        text = stripDanglingMarkdownAsterisks(text)
        // 11. 清理零散孤立反引号
        text = text.replacingOccurrences(of: "`", with: "")
        // 12. 折叠过多连续空行
        text = replace(text, regex: multiBlankLinesRegex, with: "\n\n")

        if streaming {
            // 流式展示时去掉开头多余空行，避免文本跳动
            while text.hasPrefix("\n") {
                text.removeFirst()
            }
            return text
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ input: String, regex: NSRegularExpression?, with template: String) -> String {
        guard let regex else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }

    private static func stripItalicAsterisks(_ input: String) -> String {
        guard let regex = italicAsteriskRegex, input.contains("*") else { return input }
        var current = input
        for _ in 0..<2 {
            let ns = current as NSString
            let matches = regex.matches(in: current, options: [], range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { break }
            let mutable = NSMutableString(string: current)
            var changed = false
            for match in matches.reversed() {
                let fullRange = match.range
                let innerRange = match.range(at: 1)
                guard innerRange.location != NSNotFound else { continue }
                let inner = ns.substring(with: innerRange)
                // CommonMark 规范：斜体 *text* 首尾绝不含空格（保护 `2 * 3 = 6，5 * 8 = 40` 这类带空格算式）
                if inner.hasPrefix(" ") || inner.hasSuffix(" ") {
                    continue
                }
                // 保护无空格数学乘法（如 `2*3=6`、`2*3*4`）
                let leftChar: Character? = fullRange.location > 0
                    ? Character(UnicodeScalar(ns.character(at: fullRange.location - 1)) ?? " ")
                    : nil
                let rightIndex = fullRange.location + fullRange.length
                let rightChar: Character? = rightIndex < ns.length
                    ? Character(UnicodeScalar(ns.character(at: rightIndex)) ?? " ")
                    : nil
                let looksLikeMath = (leftChar?.isNumber == true && inner.first?.isNumber == true)
                    || (rightChar?.isNumber == true && inner.last?.isNumber == true)
                if looksLikeMath {
                    continue
                }
                mutable.replaceCharacters(in: fullRange, with: inner)
                changed = true
            }
            if !changed { break }
            current = mutable as String
        }
        return current
    }

    private static func stripDanglingMarkdownAsterisks(_ input: String) -> String {
        guard input.contains("*") else { return input }
        let chars = Array(input)
        var out: [Character] = []
        out.reserveCapacity(chars.count)
        for i in 0..<chars.count {
            let ch = chars[i]
            guard ch == "*" else {
                out.append(ch)
                continue
            }
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            let next: Character? = (i + 1 < chars.count) ? chars[i + 1] : nil
            // 保留数学乘法（前后紧邻数字，或 `5 * 8` 两侧非空白字符为数字/右括号）
            let prevDigit = prev?.isNumber == true || prev == ")"
            let nextDigit = next?.isNumber == true || next == "("
            if prevDigit && nextDigit {
                out.append(ch)
                continue
            }
            if prev == " " && next == " " {
                var l = i - 2
                while l >= 0 && chars[l] == " " { l -= 1 }
                var r = i + 2
                while r < chars.count && chars[r] == " " { r += 1 }
                if l >= 0 && r < chars.count && (chars[l].isNumber || chars[l] == ")") && (chars[r].isNumber || chars[r] == "(") {
                    out.append(ch)
                    continue
                }
            }
            // 其他孤立星号（常见于未闭合 Markdown 强调符）直接移除
        }
        return String(out)
    }
}
