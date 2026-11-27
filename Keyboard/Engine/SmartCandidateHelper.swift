import Foundation

/// 除拼音词库外的智能候选补充：自定义短语、v/V 工具模式（算式/人民币大写/日期）、
/// WowType 同款首位候选 Emoji 推荐（支持全拼/7种双拼/简拼/九宫格/五笔）、英文词表补全。
enum SmartCandidateHelper {
    private static let emojiAndKaomojiTriggers: [String: [String]] = [
        "haha": ["😂", "(≧▽≦)", "🤣"],
        "kaixin": ["😊", "ヽ(✿ﾟ▽ﾟ)ノ", "🥳"],
        "gaoxing": ["😄", "(ﾉ´▽｀)ﾉ♪"],
        "nanguo": ["😭", "(╥﹏╥)", "🥹"],
        "ku": ["😭", "(つД`)ノ"],
        "wuyu": ["🫠", "(ー_ー)!!", "(╯°□°）╯︵ ┻━┻"],
        "jiayou": ["💪", "🔥", "(ง •_•)ง"],
        "aixin": ["❤️", "(づ￣ 3￣)づ", "🫶"],
        "xihuan": ["🥰", "❤️"],
        "xiexie": ["🙏", "🌹", "🥹"],
        "wanan": ["🌙", "😴", "💤"],
        "zaoan": ["☀️", "☕️"],
        "shengri": ["🎂", "🎉", "🥳"],
        "ganbei": ["🍻", "🥂"],
        "meigui": ["🌹", "💐"],
        "huoguo": ["🍲", "🌶️"],
        "naicha": ["🧋"],
        "kafei": ["☕️"],
        "niubi": ["🔥", "👍", "💯"],
        "ok": ["👌", "OK"],
    ]

    static func extraCandidates(
        forRawInput raw: String,
        settings: LingxiSettings,
        consumedLength: Int,
        englishWords: [String] = [],
        topChineseWord: String? = nil
    ) -> [PinyinCandidate] {
        var result: [PinyinCandidate] = []
        var seenWords = Set<String>()
        let lower = raw.lowercased()

        func appendCandidate(_ word: String, lp: Double, isExact: Bool, source: PinyinCandidate.Source) {
            guard !word.isEmpty, seenWords.insert(word).inserted else { return }
            result.append(PinyinCandidate(
                word: word,
                py: "",
                lp: lp,
                consumed: consumedLength,
                isExact: isExact,
                source: source
            ))
        }

        // 0. 用户自定义短语 / custom.tsv（最高优先级置顶，支持 {{日期}}/{{时间}}/{{剪贴板}} 动态变量实时展开）
        let customMatches = CustomWordStore.match(rawInput: raw)
        for (idx, entry) in customMatches.enumerated() {
            let expanded = DynamicTemplateEngine.render(entry.expandedWord)
            appendCandidate(expanded, lp: 15.0 - Double(idx) * 0.1, isExact: true, source: .smartHelper)
        }

        // 0.5 v/V 万能工具模式（WowType 同款：全拼用小写 `v`，双拼与五笔用大写 `V`，绝不与声母 v=zh 或五笔 v 键冲突）
        let isVModePrefix = (settings.inputScheme == .quanpin && lower.hasPrefix("v"))
            || (settings.inputScheme != .quanpin && raw.hasPrefix("V"))
        if isVModePrefix && raw.count >= 2 {
            let body = String(raw.dropFirst())
            let lowerBody = body.lowercased()

            // 支持 v12800rmb -> 壹万贰仟捌佰元整 财务大写直出
            if lowerBody.hasSuffix("rmb"), let amt = Double(String(lowerBody.dropLast(3))) {
                let cap = TextFormatterToolbox.amountToChineseCapital(amt)
                if !cap.isEmpty {
                    appendCandidate(cap, lp: 14.5, isExact: true, source: .smartHelper)
                }
            }

            // 支持 v1280/4 -> 320 & 人均 ¥320.00 AA 制算账直出
            if let slashIdx = body.firstIndex(of: "/"),
               let total = Double(String(body[..<slashIdx])),
               let people = Double(String(body[body.index(after: slashIdx)...])),
               people > 0 {
                let avg = total / people
                let avgStr = String(format: "%.2f", avg).replacingOccurrences(of: ".00", with: "")
                appendCandidate("人均 ¥\(avgStr)", lp: 13.8, isExact: false, source: .smartHelper)
            }

            for (idx, calcOrNum) in InlineCalculator.candidates(forVModeBody: body).enumerated() {
                appendCandidate(calcOrNum, lp: 14.0 - Double(idx) * 0.15, isExact: idx == 0, source: .smartHelper)
            }

            // 支持 vdz / vkp / vmp / vcp / vshuihao 秒调个人常用速填名片夹（地址/开票/车牌单字段与整卡）
            for (idx, cardVal) in PersonalFillCardStore.vModeCandidates(forBody: lowerBody).enumerated() {
                appendCandidate(cardVal, lp: 14.9 - Double(idx) * 0.08, isExact: idx == 0, source: .smartHelper)
            }

            // 支持 vwz / vdz / vweizhi / vdizhi 快速插入当前实时定位地址
            if settings.geoLocationBoostEnabled && ["wz", "dz", "weizhi", "dizhi", "cs", "chengshi"].contains(lowerBody) {
                let geo = GeoLocationContext.load()
                if geo.isPopulated {
                    if !geo.fullDisplayAddress.isEmpty {
                        appendCandidate(geo.fullDisplayAddress, lp: 14.8, isExact: true, source: .smartHelper)
                    }
                    if !geo.compactLocationLabel.isEmpty && geo.compactLocationLabel != geo.fullDisplayAddress {
                        appendCandidate(geo.compactLocationLabel, lp: 14.4, isExact: true, source: .smartHelper)
                    }
                    if !geo.shortCityName.isEmpty {
                        appendCandidate(geo.shortCityName, lp: 14.0, isExact: false, source: .smartHelper)
                    }
                }
            }

            for (idx, dtWord) in DateTimeHelper.candidates(forNormalizedPinyin: lowerBody, allowShortTriggers: true).enumerated() {
                appendCandidate(dtWord, lp: 13.0 - Double(idx) * 0.1, isExact: idx == 0, source: .smartHelper)
            }

            // 支持相对日期(v+3d/vmingtian)、生活与工程单位换算(v180cm/v65kg/v38c/v10km/v1.5gb)、时间戳(vts)与 UUID(vuuid)
            for (idx, toolVal) in VModeToolEngine.candidates(forBody: body).enumerated() {
                appendCandidate(toolVal, lp: 14.3 - Double(idx) * 0.12, isExact: idx == 0, source: .smartHelper)
            }
        }

        // 1. 常规日期 / 时间 / 星期快捷候选（仅完整拼音 riqi/date/shijian/time/xingqi 触发，不拦截 rq/sj 简拼）
        for (idx, dateStr) in DateTimeHelper.candidates(forNormalizedPinyin: lower, allowShortTriggers: false).enumerated() {
            appendCandidate(dateStr, lp: -2.0 - Double(idx) * 0.05, isExact: false, source: .smartHelper)
        }

        // 1.5 输入 weizhi / dizhi / dangqianweizhi 时补充当前实时定位地址
        if settings.geoLocationBoostEnabled && ["weizhi", "dizhi", "dangqianweizhi", "wodeweizhi"].contains(lower) {
            let geo = GeoLocationContext.load()
            if geo.isPopulated {
                if !geo.fullDisplayAddress.isEmpty {
                    appendCandidate(geo.fullDisplayAddress, lp: -1.5, isExact: false, source: .smartHelper)
                }
                if !geo.compactLocationLabel.isEmpty {
                    appendCandidate(geo.compactLocationLabel, lp: -1.8, isExact: false, source: .smartHelper)
                }
            }
        }

        // 2. 常规算式直出（如 `125*8=`）
        if let calc = InlineCalculator.evaluateIfExpression(raw) {
            appendCandidate(calc.result, lp: 10.0, isExact: true, source: .smartHelper)
            appendCandidate(calc.equation, lp: 9.0, isExact: false, source: .smartHelper)
        }

        // 3. WowType 同款首位候选中文词 Emoji 推荐（支持全拼/7种双拼/简拼/九宫格/五笔，如「今天好开心」->「今天好开心😊」）
        if settings.emojiSuggestionEnabled {
            var suggested: [String] = []
            if let topWord = topChineseWord {
                for rec in EmojiCatalog.recommendForTopCandidate(topWord) where !suggested.contains(rec.word) {
                    suggested.append(rec.word)
                }
            }
            if settings.inputScheme == .quanpin {
                for face in (emojiAndKaomojiTriggers[lower] ?? []) where !suggested.contains(face) {
                    suggested.append(face)
                }
                for sym in EmojiCatalog.suggestionsForExactPinyin(lower) where !suggested.contains(sym) {
                    suggested.append(sym)
                }
            }
            for (idx, face) in suggested.prefix(3).enumerated() {
                appendCandidate(face, lp: -4.0 - Double(idx) * 0.1, isExact: false, source: .smartHelper)
            }
        }

        // 4. 英文词表补全与中英混输直出（五笔模式下不插入英文直出，以免干扰纯码表）
        if settings.smartEnglishCandidate && !settings.inputScheme.isWubi {
            for w in englishWords.prefix(4) {
                appendCandidate(w, lp: -22.0, isExact: false, source: .englishDirect)
            }
            if raw.count >= 2, raw.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "'") }) {
                let clean = raw.replacingOccurrences(of: "'", with: "")
                if !clean.isEmpty {
                    appendCandidate(clean, lp: -25.0, isExact: false, source: .englishDirect)
                }
            }
        }

        return result
    }

    /// 判断当前输入是否属于 `v`（全拼）或大写 `V`（双拼/五笔）万能工具串。
    static func isVToolQuery(_ raw: String, scheme: InputScheme) -> Bool {
        let isPrefix: Bool
        if scheme == .quanpin {
            isPrefix = raw.lowercased().hasPrefix("v")
        } else {
            isPrefix = raw.hasPrefix("V")
        }
        guard isPrefix else { return false }
        if raw.count == 1 { return true }
        let body = String(raw.dropFirst())
        let lowerBody = body.lowercased()
        if !ChineseNumberConverter.candidates(forNumericString: body).isEmpty { return true }
        if InlineCalculator.evaluateIfExpression(body) != nil { return true }
        if !DateTimeHelper.candidates(forNormalizedPinyin: lowerBody).isEmpty { return true }
        if lowerBody.hasSuffix("rmb"), Double(String(lowerBody.dropLast(3))) != nil { return true }
        if ["wz", "dz", "weizhi", "dizhi", "cs", "chengshi"].contains(lowerBody) { return true }
        if PersonalFillCardStore.vModeTriggers.contains(lowerBody) { return true }
        if VModeToolEngine.isRecognizedQuery(body) { return true }
        // 输入计算式中间态（如 `v1+` 或 `V12*` 或 `v10%3`）同样保持工具模式
        if body.allSatisfy({ $0.isNumber || "+-*/%^().".contains($0) }) { return true }
        return false
    }

    /// 判断当前输入是否属于 `u`（全拼）或大写 `U`（双拼/五笔）拆字与笔画反查模式（如 `ushuishuishui`->淼、`uhspn`->木）。
    static func isUToolQuery(_ raw: String, scheme: InputScheme) -> Bool {
        let isPrefix: Bool
        if scheme == .quanpin {
            isPrefix = raw.lowercased().hasPrefix("u")
        } else {
            isPrefix = raw.hasPrefix("U")
        }
        guard isPrefix else { return false }
        if raw.count == 1 { return true }
        let body = raw.dropFirst()
        return body.allSatisfy { ($0.isASCII && $0.isLetter) || $0 == "'" }
    }

    private static let emailDomains = ["gmail.com", "qq.com", "163.com", "icloud.com", "outlook.com", "foxmail.com", "126.com"]
    private static let urlQuickTokens = ["https://", "www.", ".com", ".cn", ".org", ".io", ".net"]

    /// 根据光标前上下文与宿主输入框类型提供邮箱域名（`@` 后）或 URL 后缀快捷补全。
    static func contextCompletions(
        beforeCursor: String?,
        isEmailField: Bool,
        isURLField: Bool,
        englishPrefix: String
    ) -> [PinyinCandidate] {
        var out: [PinyinCandidate] = []
        let before = beforeCursor ?? ""

        if let atIdx = before.lastIndex(of: "@") {
            let afterAt = String(before[before.index(after: atIdx)...])
            if !afterAt.contains(where: { $0.isWhitespace || $0 == "/" }), afterAt.count <= 16 {
                let targetPrefix = afterAt.lowercased()
                let matches = emailDomains.filter { targetPrefix.isEmpty || $0.hasPrefix(targetPrefix) }
                for (idx, domain) in matches.enumerated() where domain != targetPrefix {
                    out.append(PinyinCandidate(
                        word: domain,
                        py: "",
                        lp: 8.0 - Double(idx) * 0.2,
                        consumed: englishPrefix.count,
                        isExact: true,
                        source: .englishDirect
                    ))
                }
                if !out.isEmpty { return out }
            }
        } else if isEmailField && !before.isEmpty && !before.last!.isWhitespace && !before.contains("@") && englishPrefix.isEmpty {
            for (idx, domain) in emailDomains.prefix(5).enumerated() {
                out.append(PinyinCandidate(
                    word: "@\(domain)",
                    py: "",
                    lp: 6.0 - Double(idx) * 0.2,
                    consumed: 0,
                    isExact: false,
                    source: .englishDirect
                ))
            }
            return out
        }

        if isURLField && englishPrefix.isEmpty {
            let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = trimmed.isEmpty ? ["https://", "www."] : urlQuickTokens
            for (idx, tok) in tokens.enumerated() {
                out.append(PinyinCandidate(
                    word: tok,
                    py: "",
                    lp: 5.0 - Double(idx) * 0.2,
                    consumed: 0,
                    isExact: false,
                    source: .englishDirect
                ))
            }
        }
        return out
    }

    /// 当用户刚刚上屏中文词语后，在空闲联想栏顺手推荐匹配 Emoji（覆盖全部 157 条 WowType 聊天热词）。
    static func emojiPredictions(forCommittedWord word: String) -> [String] {
        if let direct = EmojiCatalog.wordRecommendations[word], word.count >= 2 {
            return Array(direct.prefix(2))
        }
        let chars = Array(word)
        let n = chars.count
        if n >= 3 {
            for len in stride(from: min(4, n - 1), through: 2, by: -1) {
                let tail = String(chars[(n - len)..<n])
                if let list = EmojiCatalog.wordRecommendations[tail] {
                    return Array(list.prefix(2))
                }
            }
        }
        return []
    }
}
