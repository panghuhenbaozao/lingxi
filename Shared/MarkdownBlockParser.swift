import Foundation

/// 结构化 Markdown 文档块（供 App 内 AI 工作台、多模型圆桌与参数化模板渲染富文本与独立代码块）
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case codeBlock(language: String, code: String, isClosed: Bool)
    case bullet(text: String)
    case numbered(prefix: String, text: String)
    case quote(text: String)
    case divider
    case paragraph(text: String)
}

/// 纯 Swift 零依赖结构化 Markdown 块解析器：
/// - 完整支持围栏代码块（` ```swift ... ``` `），且兼容流式生成中尚未闭合的代码块不闪烁错位；
/// - 识别标题（`#`–`###`）、引用（`> `）、无序/有序列表（`- ` / `• ` / `1. ` / `1、`）与分割线（`---`）。
enum MarkdownBlockParser {
    static func parse(_ raw: String) -> [MarkdownBlock] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paraBuffer: [String] = []

        var inCode = false
        var codeLang = ""
        var codeLines: [String] = []

        func flushParagraph() {
            guard !paraBuffer.isEmpty else { return }
            let joined = paraBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(text: joined))
            }
            paraBuffer.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 1. 围栏代码块起止（```）
            if trimmed.hasPrefix("```") {
                if !inCode {
                    flushParagraph()
                    inCode = true
                    codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLines.removeAll(keepingCapacity: true)
                } else {
                    blocks.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n"), isClosed: true))
                    inCode = false
                    codeLang = ""
                    codeLines.removeAll(keepingCapacity: true)
                }
                continue
            }

            if inCode {
                codeLines.append(line)
                continue
            }

            // 2. 空行分段
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // 3. 分割线
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            // 4. ATX 标题（# / ## / ###）
            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            // 5. 引用块（> ）
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    blocks.append(.quote(text: content))
                }
                continue
            }

            // 6. 无序列表（- / * / •）
            if let bullet = parseBullet(trimmed) {
                flushParagraph()
                blocks.append(.bullet(text: bullet))
                continue
            }

            // 7. 有序列表（1. / 2. / 1、）
            if let num = parseNumbered(trimmed) {
                flushParagraph()
                blocks.append(.numbered(prefix: num.prefix, text: num.text))
                continue
            }

            // 8. 普通段落行
            paraBuffer.append(line)
        }

        if inCode {
            blocks.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n"), isClosed: false))
        } else {
            flushParagraph()
        }

        return blocks
    }

    private static func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard (1...4).contains(level) else { return nil }
        let rest = String(trimmed.dropFirst(level))
        guard rest.hasPrefix(" ") else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (min(level, 3), title)
    }

    private static func parseBullet(_ trimmed: String) -> String? {
        for prefix in ["- ", "* ", "• ", "· "] {
            if trimmed.hasPrefix(prefix) {
                let body = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty { return body }
            }
        }
        return nil
    }

    private static func parseNumbered(_ trimmed: String) -> (prefix: String, text: String)? {
        var digitCount = 0
        for ch in trimmed {
            if ch.isASCII && ch.isNumber { digitCount += 1 } else { break }
        }
        guard (1...3).contains(digitCount) else { return nil }
        let afterDigits = trimmed.dropFirst(digitCount)
        let sep: String
        let rest: Substring
        if afterDigits.hasPrefix(". ") {
            sep = "."
            rest = afterDigits.dropFirst(2)
        } else if afterDigits.hasPrefix("、") {
            sep = "、"
            rest = afterDigits.dropFirst(1)
        } else if afterDigits.hasPrefix(") ") {
            sep = ")"
            rest = afterDigits.dropFirst(2)
        } else {
            return nil
        }
        let body = rest.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        return (String(trimmed.prefix(digitCount)) + sep, body)
    }
}
