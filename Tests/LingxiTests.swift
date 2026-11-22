import XCTest

final class LingxiTests: XCTestCase {
    private func findTestDBURL() -> URL? {
        if let bundled = Bundle(for: PinyinEngine.self).url(forResource: "pinyin", withExtension: "sqlite") {
            return bundled
        }
        let repoRelative = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Keyboard/Resources/pinyin.sqlite")
        return FileManager.default.fileExists(atPath: repoRelative.path) ? repoRelative : nil
    }

    func testQuanpinSegmenterAndAmbiguity() {
        let seg = PinyinSegmenter()
        let xian = seg.segmentations(raw: "xi'an", scheme: .quanpin)
        XCTAssertEqual(xian.first?.map(\.text), ["xi", "an"])

        // 无隔音符单音节歧义补充切分：xian 除 [xian] 外额外生成 [xi, an]
        let xianPlain = seg.segmentations(raw: "xian", scheme: .quanpin)
        let xianVariants = Set(xianPlain.map { $0.map(\.text) })
        XCTAssertTrue(xianVariants.contains(["xian"]))
        XCTAssertTrue(xianVariants.contains(["xi", "an"]))

        // 含 zh/ch/sh 的纯声母简拼补充单字母切分：gzh -> [g, z, h]
        let gzh = seg.segmentations(raw: "gzh", scheme: .quanpin)
        XCTAssertTrue(gzh.map { $0.map(\.text) }.contains(["g", "z", "h"]))

        let fangan = seg.segmentations(raw: "fangan", scheme: .quanpin)
        let variants = Set(fangan.map { $0.map(\.text) })
        XCTAssertTrue(variants.contains(["fang", "an"]))
        XCTAssertTrue(variants.contains(["fan", "gan"]))

        let lue = seg.segmentations(raw: "lue", scheme: .quanpin)
        XCTAssertEqual(lue.first?.map(\.text), ["lve"])
    }

    func testAllSevenDoublePinyinSchemes() {
        let seg = PinyinSegmenter()

        // 小鹤
        XCTAssertEqual(seg.segmentations(raw: "vsgo", scheme: .xiaohe).first?.map(\.text), ["zhong", "guo"])
        XCTAssertEqual(seg.segmentations(raw: "xp", scheme: .xiaohe).first?.map(\.text), ["xie"])
        XCTAssertEqual(seg.segmentations(raw: "vl", scheme: .xiaohe).first?.map(\.text), ["zhuang"])
        let partial = seg.segmentations(raw: "vsg", scheme: .xiaohe)
        XCTAssertEqual(partial.first?.count, 2)
        XCTAssertEqual(partial.first?.last?.kind, .partial)

        // 自然码
        XCTAssertEqual(seg.segmentations(raw: "xmzl", scheme: .ziranma).first?.map(\.text), ["xian", "zai"])
        XCTAssertEqual(seg.segmentations(raw: "nihk", scheme: .ziranma).first?.map(\.text), ["ni", "hao"])

        // 微软双拼（含 ;=ing、y=ü、v/t=üe）
        XCTAssertEqual(seg.segmentations(raw: "m;", scheme: .microsoft).first?.map(\.text), ["ming"])
        XCTAssertEqual(seg.segmentations(raw: "ly", scheme: .microsoft).first?.map(\.text), ["lv"])
        XCTAssertTrue(seg.segmentations(raw: "lv", scheme: .microsoft).map { $0.map(\.text) }.contains(["lve"]))

        // 搜狗双拼（含 ;=ing，üe 仅在 t 不在 v）
        XCTAssertEqual(seg.segmentations(raw: "m;", scheme: .sogou).first?.map(\.text), ["ming"])
        XCTAssertFalse(seg.segmentations(raw: "lv", scheme: .sogou).map { $0.map(\.text) }.contains(["lve"]))

        // 智能 ABC（zh=a, ch=e, sh=v，零声母仅 o+韵母）
        XCTAssertEqual(seg.segmentations(raw: "ah", scheme: .abc).first?.map(\.text), ["zhang"])
        XCTAssertEqual(seg.segmentations(raw: "ol", scheme: .abc).first?.map(\.text), ["ai"])

        // 紫光双拼（zh=u, ch=a, sh=i，;=ing）
        XCTAssertEqual(seg.segmentations(raw: "as", scheme: .ziguang).first?.map(\.text), ["chang"])
        XCTAssertEqual(seg.segmentations(raw: "q;", scheme: .ziguang).first?.map(\.text), ["qing"])

        // 拼音加加（zh=v, ch=u, sh=i）
        XCTAssertEqual(seg.segmentations(raw: "ii", scheme: .pinyinjiajia).first?.map(\.text), ["shi"])
        XCTAssertEqual(seg.segmentations(raw: "uu", scheme: .pinyinjiajia).first?.map(\.text), ["chu"])

        // 全部 7 种双拼都能生成键帽助记表
        for scheme in InputScheme.allCases where scheme.isDoublePinyin {
            let hints = PinyinSegmenter.doublePinyinKeycapHints(for: scheme)
            XCTAssertGreaterThanOrEqual(hints.count, 20, "\(scheme.displayName) 键帽助记表过少")
        }
    }

    func testPinyinEngineQueriesAndTypoCorrection() throws {
        let dbURL = try XCTUnwrap(findTestDBURL(), "找不到 pinyin.sqlite 测试词库")
        let engine = PinyinEngine(databaseURL: dbURL)
        var settings = LingxiSettings()
        settings.userLearningEnabled = false

        let (_, c1, _) = engine.query(raw: "nihao", settings: settings)
        XCTAssertEqual(c1.first?.word, "你好")

        let (_, c2, _) = engine.query(raw: "jintiantianqizhenhao", settings: settings)
        XCTAssertEqual(c2.first?.word, "今天天气真好")

        let (_, c3, _) = engine.query(raw: "fangan", settings: settings)
        XCTAssertEqual(c3.first?.word, "方案")

        // 单音节前缀不被误纠错
        let (_, zhonCands, zhonHint) = engine.query(raw: "zhon", settings: settings)
        XCTAssertNil(zhonHint)
        XCTAssertEqual(zhonCands.first?.word, "中")

        // 错拼换位、重击去重、漏元音与多余误触 4 路容错 + 合法全拼鼻音/换位/邻键容错
        let (_, typo1, hint1) = engine.query(raw: "nihoa", settings: settings)
        XCTAssertEqual(typo1.first?.word, "你好")
        XCTAssertEqual(hint1, "ni'hao")

        XCTAssertEqual(engine.query(raw: "niihao", settings: settings).candidates.first?.word, "你好")
        XCTAssertEqual(engine.query(raw: "zhognguo", settings: settings).candidates.first?.word, "中国")
        XCTAssertEqual(engine.query(raw: "buhap", settings: settings).candidates.first?.word, "不好")
        XCTAssertEqual(engine.query(raw: "zhngguo", settings: settings).candidates.first?.word, "中国")
        XCTAssertEqual(engine.query(raw: "zhkngguo", settings: settings).candidates.first?.word, "中国")
        XCTAssertEqual(engine.query(raw: "shurfa", settings: settings).candidates.first?.word, "输入法")
        XCTAssertEqual(engine.query(raw: "weixni", settings: settings).candidates.first?.word, "微信")
        XCTAssertEqual(engine.query(raw: "meiyuo", settings: settings).candidates.first?.word, "没有")
        XCTAssertEqual(engine.query(raw: "shengme", settings: settings).candidates.first?.word, "什么")
        XCTAssertEqual(engine.query(raw: "penyou", settings: settings).candidates.first?.word, "朋友")
        // 音节首字母邻键容错：mihao -> 你好（m/n 相邻误触），纠错候选显著提升时才前置
        XCTAssertEqual(engine.query(raw: "mihao", settings: settings).candidates.first?.word, "你好")
        // 高频精确词不被邻键纠错抢走（nihao 本身不受影响，仍为你好）
        XCTAssertEqual(engine.query(raw: "nihao", settings: settings).candidates.first?.word, "你好")
        XCTAssertEqual(engine.query(raw: "yingai", settings: settings).candidates.first?.word, "应该")
        XCTAssertEqual(engine.query(raw: "zidao", settings: settings).candidates.first?.word, "知道")
        XCTAssertTrue(engine.query(raw: "tianqu", settings: settings).candidates.prefix(2).map(\.word).contains("天气"))

        // Beam-Search + sys_bigrams 首日长句消歧
        XCTAssertEqual(engine.query(raw: "woquchifan", settings: settings).candidates.first?.word, "我去吃饭")
        XCTAssertEqual(engine.query(raw: "xiabanhouchihuoguo", settings: settings).candidates.first?.word, "下班后吃火锅")
        XCTAssertEqual(engine.query(raw: "bangwokanyixia", settings: settings).candidates.first?.word, "帮我看一下")

        // 首日下一词二元联想
        let preds = engine.predictNext(after: "下班", userLearning: false)
        XCTAssertTrue(preds.contains("后") || preds.contains("了"))

        // 模糊音测试（含新增 huang/wang, un/ong 等 16 组扩展）
        var fuzzySettings = settings
        fuzzySettings.fuzzy.zhZ = true
        XCTAssertTrue(engine.query(raw: "zongguo", settings: fuzzySettings).candidates.prefix(5).map(\.word).contains("中国"))

        fuzzySettings = settings
        fuzzySettings.fuzzy.huangWang = true
        let hwWords = engine.query(raw: "wang", settings: fuzzySettings).candidates.prefix(8).map(\.word)
        XCTAssertTrue(hwWords.contains("黄") || hwWords.contains("王"))

        fuzzySettings = settings
        fuzzySettings.fuzzy.unOng = true
        let uoWords = engine.query(raw: "dun", settings: fuzzySettings).candidates.prefix(8).map(\.word)
        XCTAssertTrue(uoWords.contains("东") || uoWords.contains("懂"))
    }

    func testWowTypeExactProtectionErhuaMixedAndContext() throws {
        let dbURL = try XCTUnwrap(findTestDBURL())
        let engine = PinyinEngine(databaseURL: dbURL)
        var settings = LingxiSettings()
        settings.userLearningEnabled = false

        // 1. 打全精确词保护（不被前缀补全或单字拼凑抢走）
        XCTAssertEqual(engine.query(raw: "zhongdi", settings: settings).candidates.first?.word, "种地")
        XCTAssertEqual(engine.query(raw: "beiji", settings: settings).candidates.first?.word, "北极")
        XCTAssertEqual(engine.query(raw: "ka", settings: settings).candidates.first?.word, "卡")
        XCTAssertEqual(engine.query(raw: "qidongqi", settings: settings).candidates.first?.word, "启动器")
        XCTAssertEqual(engine.query(raw: "qianhouduan", settings: settings).candidates.first?.word, "前后端")
        XCTAssertEqual(engine.query(raw: "houxuanci", settings: settings).candidates.first?.word, "候选词")

        // 2. 单音节歧义保护：xian 首选「先」，「西安」在 Top-5
        let xianWords = engine.query(raw: "xian", settings: settings).candidates.prefix(5).map(\.word)
        XCTAssertEqual(xianWords.first, "先")
        XCTAssertTrue(xianWords.contains("西安"))

        // 3. 儿化音
        XCTAssertEqual(engine.query(raw: "wanr", settings: settings).candidates.first?.word, "玩儿")
        XCTAssertEqual(engine.query(raw: "zher", settings: settings).candidates.first?.word, "这儿")
        XCTAssertEqual(engine.query(raw: "yidianr", settings: settings).candidates.first?.word, "一点儿")
        XCTAssertEqual(engine.query(raw: "haowanr", settings: settings).candidates.first?.word, "好玩儿")

        // 4. 全拼混简拼 + 补全长度惩罚 + 热词
        XCTAssertEqual(engine.query(raw: "kyi", settings: settings).candidates.first?.word, "可以")
        XCTAssertEqual(engine.query(raw: "wanqky", settings: settings).candidates.first?.word, "完全可以")
        XCTAssertEqual(engine.query(raw: "yongzwen", settings: settings).candidates.first?.word, "用中文")
        XCTAssertEqual(engine.query(raw: "zhchi", settings: settings).candidates.first?.word, "支持")
        XCTAssertEqual(engine.query(raw: "weish", settings: settings).candidates.first?.word, "为啥")
        XCTAssertTrue(engine.query(raw: "gzh", settings: settings).candidates.prefix(3).map(\.word).contains("公众号"))
        XCTAssertEqual(engine.query(raw: "heishenhua", settings: settings).candidates.first?.word, "黑神话")

        // 5. 光标上文消歧
        XCTAssertEqual(engine.query(raw: "hui", settings: settings, contextBeforeCursor: "我们").candidates.first?.word, "会")
        XCTAssertEqual(engine.query(raw: "ma", settings: settings, contextBeforeCursor: "你好").candidates.first?.word, "吗")
        XCTAssertEqual(engine.query(raw: "le", settings: settings, contextBeforeCursor: "吃饭").candidates.first?.word, "了")

        // 6. 英文直出精确排位（非全拼排 #1；合法全拼如 like/danger 排第 6 位 index 5）
        XCTAssertEqual(engine.query(raw: "github", settings: settings).candidates.first?.word, "GitHub")
        XCTAssertEqual(engine.query(raw: "wechat", settings: settings).candidates.first?.word, "WeChat")
        XCTAssertEqual(engine.query(raw: "deepseek", settings: settings).candidates.first?.word, "DeepSeek")
        let likeWords = engine.query(raw: "like", settings: settings).candidates.map(\.word)
        XCTAssertGreaterThanOrEqual(likeWords.count, 6)
        XCTAssertEqual(likeWords[5], "like")
        let dangerWords = engine.query(raw: "danger", settings: settings).candidates.map(\.word)
        XCTAssertGreaterThanOrEqual(dangerWords.count, 6)
        XCTAssertEqual(dangerWords[5], "danger")

        // 7. 内存警告释放缓存后仍可稳定解码（Jetsam 防护验证）
        engine.releaseMemory()
        XCTAssertEqual(engine.query(raw: "zhongdi", settings: settings).candidates.first?.word, "种地")
        XCTAssertEqual(engine.query(raw: "nihao", settings: settings).candidates.first?.word, "你好")
    }

    func testWubi86LookupAndReverseQuery() throws {
        let dbURL = try XCTUnwrap(findTestDBURL())
        let engine = PinyinEngine(databaseURL: dbURL)
        var settings = LingxiSettings()
        settings.inputScheme = .wubi86
        settings.userLearningEnabled = false

        // 精确码 + 剩余编码提示
        let wq = engine.queryWubi(raw: "wq", settings: settings)
        XCTAssertFalse(wq.isEmptyCode)
        XCTAssertEqual(wq.candidates.first?.word, "你")
        XCTAssertTrue(wq.candidates.contains { $0.word == "您" && $0.codeHint == "in" })

        // 反查五笔编码
        XCTAssertEqual(engine.wubiReverseHint(for: "工"), "a/aaaa")

        // z 临时拼音与反查码提示
        let zRes = engine.queryWubi(raw: "znihao", settings: settings)
        XCTAssertTrue(zRes.isTempPinyin)
        XCTAssertEqual(zRes.candidates.first?.word, "你好")
        XCTAssertFalse(zRes.candidates.first?.codeHint.isEmpty ?? true)

        // 空码检测
        let emptyRes = engine.queryWubi(raw: "yyyy", settings: settings)
        XCTAssertFalse(emptyRes.isTempPinyin)
        if emptyRes.candidates.isEmpty {
            XCTAssertTrue(emptyRes.isEmptyCode)
        }
    }

    func testUModeChaiziAndStrokeLookup() throws {
        let dbURL = try XCTUnwrap(findTestDBURL())
        let engine = PinyinEngine(databaseURL: dbURL)

        // 部件拆字反查 + 实时注音提示
        let miao = engine.queryUMode(raw: "ushuishuishui")
        XCTAssertEqual(miao.candidates.first?.word, "淼")
        XCTAssertEqual(miao.candidates.first?.codeHint, "miao")

        let ben = engine.queryUMode(raw: "uniuniuniu")
        XCTAssertEqual(ben.candidates.first?.word, "犇")
        XCTAssertEqual(ben.candidates.first?.codeHint, "ben")

        let kun = engine.queryUMode(raw: "ufangfangtu")
        XCTAssertEqual(kun.candidates.first?.word, "堃")
        XCTAssertEqual(kun.candidates.first?.codeHint, "kun")

        let da = engine.queryUMode(raw: "ulonglonglong")
        XCTAssertEqual(da.candidates.first?.word, "龘")
        XCTAssertEqual(da.candidates.first?.codeHint, "da")

        // 五笔画反查（h横 s竖 p撇 n捺 z折）
        let mu = engine.queryUMode(raw: "uhspn")
        XCTAssertEqual(mu.candidates.first?.word, "木")
        XCTAssertEqual(mu.candidates.first?.codeHint, "mu")

        XCTAssertTrue(SmartCandidateHelper.isUToolQuery("ushuishui", scheme: .quanpin))
        XCTAssertFalse(SmartCandidateHelper.isUToolQuery("ushuishui", scheme: .xiaohe))
        XCTAssertTrue(SmartCandidateHelper.isUToolQuery("Ushuishui", scheme: .xiaohe))
    }

    func testGlideTypingDecoderChineseAndEnglish() throws {
        let dbURL = try XCTUnwrap(findTestDBURL())
        let engine = PinyinEngine(databaseURL: dbURL)

        let nihaoPath = GlideTypingDecoder.wordKeyPolyline(for: "nihao")
        let zhHits = GlideTypingDecoder.decodeNormalized(points: nihaoPath, engine: engine, isEnglish: false)
        XCTAssertEqual(zhHits.first?.word, "你好")

        let zgPath = GlideTypingDecoder.wordKeyPolyline(for: "zhongguo")
        let zgHits = GlideTypingDecoder.decodeNormalized(points: zgPath, engine: engine, isEnglish: false)
        XCTAssertEqual(zgHits.first?.word, "中国")

        let helloPath = GlideTypingDecoder.wordKeyPolyline(for: "hello")
        let enHits = GlideTypingDecoder.decodeNormalized(points: helloPath, engine: engine, isEnglish: true)
        XCTAssertEqual(enHits.first?.word, "hello")
    }

    func testT9NineKeyPinyinAndSyllableLock() throws {
        let dbURL = try XCTUnwrap(findTestDBURL())
        let engine = PinyinEngine(databaseURL: dbURL)
        var settings = LingxiSettings()
        settings.userLearningEnabled = false

        let (_, t1, syls1) = engine.queryT9(digits: "64426", lockedSyllables: [], settings: settings)
        XCTAssertTrue(t1.prefix(3).map(\.word).contains("你好"))
        XCTAssertTrue(syls1.contains("ni"))

        let (_, tLocked, _) = engine.queryT9(digits: "64426", lockedSyllables: ["ni"], settings: settings)
        XCTAssertEqual(tLocked.first?.word, "你好")

        let (_, t2, _) = engine.queryT9(digits: "962464", lockedSyllables: [], settings: settings)
        XCTAssertTrue(t2.prefix(3).map(\.word).contains("我爱你"))

        let (_, t3, _) = engine.queryT9(digits: "94664486", lockedSyllables: [], settings: settings)
        XCTAssertEqual(t3.first?.word, "中国")
    }

    func testEnglishAutocomplete() throws {
        let dbURL = try XCTUnwrap(findTestDBURL())
        let engine = PinyinEngine(databaseURL: dbURL)
        let hits = engine.queryEnglish(prefix: "iph")
        XCTAssertTrue(hits.contains("iPhone"))
    }

    func testInlineCalculator() {
        XCTAssertEqual(InlineCalculator.evaluateIfExpression("125*8=")?.result, "1000")
        XCTAssertEqual(InlineCalculator.evaluateIfExpression("(18+24)/7")?.result, "6")
        XCTAssertEqual(InlineCalculator.evaluateIfExpression("2^10=")?.result, "1024")
        XCTAssertEqual(InlineCalculator.evaluateIfExpression("17%5")?.result, "2")
        // 算式结果为金额时自动附带人民币大写（对齐 WowType calc.rs）
        let vCands = InlineCalculator.candidates(forVModeBody: "125*8")
        XCTAssertEqual(vCands.first, "1000")
        XCTAssertTrue(vCands.contains("壹仟元整"))
        XCTAssertNil(InlineCalculator.evaluateIfExpression("2026"))
        XCTAssertNil(InlineCalculator.evaluateIfExpression("10/0="))
    }

    func testSmartPunctuationRules() {
        var openDQ = false
        var openSQ = false

        // 数字后保留半角小数点/冒号/逗号
        XCTAssertEqual(SmartPunctuation.convert(".", style: .fullwidth, beforeCursor: "3", openDoubleQuote: &openDQ, openSingleQuote: &openSQ), ".")
        XCTAssertEqual(SmartPunctuation.convert("。", style: .fullwidth, beforeCursor: "3", openDoubleQuote: &openDQ, openSingleQuote: &openSQ), ".")
        XCTAssertEqual(SmartPunctuation.convert(":", style: .fullwidth, beforeCursor: "20", openDoubleQuote: &openDQ, openSingleQuote: &openSQ), ":")
        XCTAssertEqual(SmartPunctuation.convert(",", style: .fullwidth, beforeCursor: "3", openDoubleQuote: &openDQ, openSingleQuote: &openSQ), ",")

        // 弯引号交替配对
        XCTAssertEqual(SmartPunctuation.convert("\"", style: .fullwidth, beforeCursor: "他说", openDoubleQuote: &openDQ, openSingleQuote: &openSQ), "“")
        XCTAssertEqual(SmartPunctuation.convert("\"", style: .fullwidth, beforeCursor: "你好", openDoubleQuote: &openDQ, openSingleQuote: &openSQ), "”")
        XCTAssertEqual(SmartPunctuation.convert("'", style: .fullwidth, beforeCursor: "中", openDoubleQuote: &openDQ, openSingleQuote: &openSQ), "‘")
        XCTAssertEqual(SmartPunctuation.convert("'", style: .fullwidth, beforeCursor: "文", openDoubleQuote: &openDQ, openSingleQuote: &openSQ), "’")

        // WowType 标点映射与半角切换
        XCTAssertEqual(SmartPunctuation.convert("{", style: .fullwidth, beforeCursor: nil, openDoubleQuote: &openDQ, openSingleQuote: &openSQ), "「")
        XCTAssertEqual(SmartPunctuation.convert("}", style: .fullwidth, beforeCursor: nil, openDoubleQuote: &openDQ, openSingleQuote: &openSQ), "」")
        XCTAssertEqual(SmartPunctuation.convert("^", style: .fullwidth, beforeCursor: nil, openDoubleQuote: &openDQ, openSingleQuote: &openSQ), "……")
        XCTAssertEqual(SmartPunctuation.convert("_", style: .fullwidth, beforeCursor: nil, openDoubleQuote: &openDQ, openSingleQuote: &openSQ), "——")
        XCTAssertEqual(SmartPunctuation.convert(",", style: .halfwidth, beforeCursor: "中文", openDoubleQuote: &openDQ, openSingleQuote: &openSQ), ",")
    }

    func testOTPExtractionAndClassification() {
        let sms = "【灵犀银行】2026年11月提醒：您的登录验证码为 849201，5分钟内有效。"
        let item = ClipboardItem(text: sms)
        XCTAssertEqual(item.category, .code)
        XCTAssertEqual(item.extractedCode, "849201")

        let urlItem = ClipboardItem(text: "https://github.com/lingxi")
        XCTAssertEqual(urlItem.category, .url)
        XCTAssertNil(urlItem.extractedCode)
    }

    func testTraditionalChineseAndPanguSpacing() {
        XCTAssertEqual(ChineseScriptConverter.toTraditional("头发和发财"), "頭髮和發財")
        XCTAssertEqual(ChineseScriptConverter.toTraditional("皇后吃面条"), "皇后吃麵條")
        XCTAssertEqual(ChineseScriptConverter.toTraditional("一只松鼠很干净"), "一隻松鼠很乾淨")

        XCTAssertTrue(PanguSpacer.needsLeadingSpace(beforeCursor: "使用", inserting: "iPhone", spaceLetters: true, spaceDigits: false))
        XCTAssertFalse(PanguSpacer.needsLeadingSpace(beforeCursor: "使用 ", inserting: "iPhone", spaceLetters: true, spaceDigits: false))
        XCTAssertFalse(PanguSpacer.needsLeadingSpace(beforeCursor: "第", inserting: "100", spaceLetters: true, spaceDigits: false))
        XCTAssertTrue(PanguSpacer.needsLeadingSpace(beforeCursor: "第", inserting: "100", spaceLetters: false, spaceDigits: true))
        XCTAssertFalse(PanguSpacer.needsLeadingSpace(beforeCursor: "你好", inserting: "，", spaceLetters: true, spaceDigits: true))
    }

    func testStylishTextConverter() {
        let out = StylishTextConverter.convert("Lingxi 123!", style: .doubleStruck)
        XCTAssertEqual(out, "𝕃𝕚𝕟𝕘𝕩𝕚 𝟙𝟚𝟛!")
    }

    func testChineseNumberConverterAndVMode() {
        let money = ChineseNumberConverter.candidates(forNumericString: "12345.67")
        XCTAssertEqual(money.first, "壹万贰仟叁佰肆拾伍元陆角柒分")
        XCTAssertTrue(money.contains("一万二千三百四十五点六七"))

        let settings = LingxiSettings()
        let vCalc = SmartCandidateHelper.extraCandidates(forRawInput: "v1+2*3", settings: settings, consumedLength: 6)
        XCTAssertEqual(vCalc.first?.word, "7")

        let vDate = SmartCandidateHelper.extraCandidates(forRawInput: "vrq", settings: settings, consumedLength: 3)
        XCTAssertFalse(vDate.isEmpty)

        // 双拼/五笔模式下小写 v 不触发工具模式，大写 V 触发工具模式（对齐 WowType）
        var xiaoheSettings = LingxiSettings()
        xiaoheSettings.inputScheme = .xiaohe
        XCTAssertFalse(SmartCandidateHelper.isVToolQuery("vrq", scheme: .xiaohe))
        XCTAssertTrue(SmartCandidateHelper.isVToolQuery("V1+2*3", scheme: .xiaohe))
        XCTAssertTrue(SmartCandidateHelper.isVToolQuery("V12345.67", scheme: .wubi86))
        let upperVCalc = SmartCandidateHelper.extraCandidates(forRawInput: "V1+2*3", settings: xiaoheSettings, consumedLength: 6)
        XCTAssertEqual(upperVCalc.first?.word, "7")

        XCTAssertTrue(SmartCandidateHelper.isVToolQuery("v1+2", scheme: .quanpin))
        XCTAssertFalse(SmartCandidateHelper.isVToolQuery("vip", scheme: .quanpin))
        let xhExtra = SmartCandidateHelper.extraCandidates(forRawInput: "vrq", settings: xiaoheSettings, consumedLength: 3)
        XCTAssertFalse(xhExtra.contains { $0.source == .smartHelper && $0.lp >= 12.0 })
    }

    func testEmailAndURLContextCompletions() {
        let afterAt = SmartCandidateHelper.contextCompletions(
            beforeCursor: "alice@",
            isEmailField: true,
            isURLField: false,
            englishPrefix: ""
        )
        XCTAssertTrue(afterAt.map(\.word).contains("gmail.com"))

        let partialAt = SmartCandidateHelper.contextCompletions(
            beforeCursor: "alice@qq",
            isEmailField: true,
            isURLField: false,
            englishPrefix: "qq"
        )
        XCTAssertEqual(partialAt.first?.word, "qq.com")

        let urlHits = SmartCandidateHelper.contextCompletions(
            beforeCursor: "",
            isEmailField: false,
            isURLField: true,
            englishPrefix: ""
        )
        XCTAssertTrue(urlHits.map(\.word).contains("https://"))
    }

    func testCustomWordStoreTSV() {
        let backup = CustomWordStore.load(force: true)
        defer { CustomWordStore.save(backup) }

        CustomWordStore.save([])
        let imported = CustomWordStore.importTSV("zzyx\t第一行\\n第二行\nad\t灵犀总部\n")
        XCTAssertEqual(imported, 2)

        let hits = CustomWordStore.match(rawInput: "zzyx")
        XCTAssertEqual(hits.first?.expandedWord, "第一行\n第二行")
        XCTAssertTrue(CustomWordStore.exportTSV().contains("zzyx\t第一行\\n第二行"))
    }

    func testEmojiCatalogSearchAndTopWordRecommendations() {
        let arrowHits = EmojiCatalog.search("jiantou")
        XCTAssertTrue(arrowHits.map(\.symbol).contains("→"))

        let kaomojiHits = EmojiCatalog.search("xianzhuo")
        XCTAssertTrue(kaomojiHits.map(\.symbol).contains("(╯°□°）╯︵ ┻━┻"))

        // 首位中文候选词自动附带 Emoji（全拼/双拼/简拼/九宫格/五笔通用）
        let sentenceRec = EmojiCatalog.recommendForTopCandidate("今天好开心")
        XCTAssertEqual(sentenceRec.first?.word, "今天好开心😊")

        let shortRec = EmojiCatalog.recommendForTopCandidate("摸鱼")
        XCTAssertEqual(shortRec.first?.word, "🐟")

        // 结合引擎解析出的中文词条进行表情搜索
        let chiguaSearch = EmojiCatalog.search("cg", resolvedChineseWords: ["吃瓜"])
        XCTAssertTrue(chiguaSearch.map(\.symbol).contains("🍉"))
    }

    func testUserLexiconDecayUndoAndTSV() {
        let now = Date().timeIntervalSince1970
        let fresh = UserLexicon.decayedFrequency(100, lastUsed: now, now: now)
        let afterHalfLife = UserLexicon.decayedFrequency(100, lastUsed: now - 30.0 * 86400.0, now: now)
        XCTAssertEqual(fresh, 100.0, accuracy: 0.01)
        XCTAssertEqual(afterHalfLife, 50.0, accuracy: 0.1)

        let lexicon = UserLexicon()
        let testWord = "测试退格撤学"
        let testPy = "ce'shi'tui'ge'che'xue"
        lexicon.forget(word: testWord, py: testPy)

        let rec = lexicon.learn(word: testWord, py: testPy, prevWord: "开始")
        let lookupHits = lexicon.lookup(abbrList: ["cstgcx"], isT9: false, minFrequency: 1)
        XCTAssertTrue(lookupHits.map(\.word).contains(testWord))

        // 阈值过滤测试（freq=1 在 minFrequency=2 时不生效）
        let gatedHits = lexicon.lookup(abbrList: ["cstgcx"], isT9: false, minFrequency: 2)
        XCTAssertFalse(gatedHits.map(\.word).contains(testWord))

        // 退格撤销学习
        if let rec {
            lexicon.undoLearn(rec)
        }
        let afterUndo = lexicon.lookup(abbrList: ["cstgcx"], isT9: false, minFrequency: 1)
        XCTAssertFalse(afterUndo.map(\.word).contains(testWord))

        // user.tsv 导入/导出 + 过期清理接口
        let imported = lexicon.importTSV("ling xi ceshi\t灵犀词条\t4\t1\n")
        XCTAssertEqual(imported, 1)
        XCTAssertTrue(lexicon.exportTSV().contains("灵犀词条"))
        lexicon.pruneStaleEntries()
        lexicon.forget(word: "灵犀词条", py: "ling'xi'ceshi")

        // 实时互译口语 / 正式双语气系统提示词
        let casualPrompt = TranslateTargetLanguage.systemPrompt(for: "英文", formal: false)
        let formalPrompt = TranslateTargetLanguage.systemPrompt(for: "英文", formal: true)
        XCTAssertTrue(casualPrompt.contains("口语"))
        XCTAssertTrue(formalPrompt.contains("正式"))
    }

    // 打字统计（借鉴 WowType）：开关默认关闭 + 按天计数 + 活跃时长阈值 + 清除
    func testTypingStatsStoreAndSettings() {
        // 设置开关：默认关闭，且旧版 JSON（无该字段）解码后仍为关闭
        let defaults = LingxiSettings()
        XCTAssertFalse(defaults.typingStatsEnabled)
        let legacyJSON = Data("{}".utf8)
        let decoded = try? JSONDecoder().decode(LingxiSettings.self, from: legacyJSON)
        XCTAssertNotNil(decoded)
        XCTAssertFalse(decoded?.typingStatsEnabled ?? true)

        // 统计逻辑：字数累加、活跃时长仅在间隔 ≤30s 时计入
        let store = TypingStatsStore()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        store.clearAll()
        store.recordCommit(text: "你好", at: base)
        store.recordCommit(text: "世界", at: base.addingTimeInterval(10))
        // 间隔 120s > 30s 阈值，不计入活跃时长
        store.recordCommit(text: "长间隔后", at: base.addingTimeInterval(130))
        let summary = store.summary(now: base.addingTimeInterval(130))
        XCTAssertEqual(summary.todayChars, 2 + 2 + 4)
        XCTAssertEqual(summary.totalActiveSeconds, 10, accuracy: 0.001)
        XCTAssertEqual(summary.streakDays, 1)
        // 清除后归零
        store.clearAll()
        let cleared = store.summary(now: base)
        XCTAssertEqual(cleared.totalChars, 0)
        XCTAssertEqual(cleared.todayChars, 0)
        XCTAssertEqual(cleared.streakDays, 0)
    }

    func testToolbarLayoutSettings() throws {
        // 旧版 JSON（无工具栏新字段）解码应回退默认值
        let legacyJSON = "{\"layoutMode\":\"qwerty26\",\"inputScheme\":\"quanpin\"}"
        let legacy = try JSONDecoder().decode(LingxiSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(legacy.toolbarLayout.count, ToolbarButtonID.allCases.count)
        XCTAssertEqual(legacy.toolbarLayout.map({ $0.buttonID }), ToolbarButtonID.allCases)
        // v4 新默认：AI/译/剪贴板/设置/撤销可见，表情/编辑面板/九键切换默认收纳进『⋯』
        let expectedVisible: Set<ToolbarButtonID> = [.ai, .translate, .clipboard, .settings, .undo]
        let visibleByDefault = Set(legacy.toolbarLayout.filter(\.isVisible).map(\.buttonID))
        XCTAssertEqual(visibleByDefault, expectedVisible)
        XCTAssertTrue(legacy.showComposingStrip)
        XCTAssertEqual(legacy.candidateBarHeight, 50, accuracy: 0.001)
        XCTAssertEqual(legacy.candidateFontSize, 16.5, accuracy: 0.001)

        // 归一化：乱序 + 缺项 + 显隐，应补全缺失按钮并按 order 重排
        var custom: [ToolbarItemConfig] = [
            ToolbarItemConfig(buttonID: .layout, isVisible: false, order: 0),
            ToolbarItemConfig(buttonID: .ai, isVisible: true, order: 1),
        ]
        custom = LingxiSettings.normalizedToolbarLayout(custom)
        XCTAssertEqual(custom.count, ToolbarButtonID.allCases.count)
        XCTAssertEqual(custom.first?.buttonID, .layout)
        XCTAssertEqual(custom[1].buttonID, .ai)
        XCTAssertFalse(custom[0].isVisible)
        // 旧版含已废弃 emoji / edit 按钮的 JSON 解码时应自动剥离，不报错且不残留
        let deprecatedButtonsJSON = """
        {"toolbarLayout":[{"buttonID":"emoji","isVisible":true,"order":0},{"buttonID":"edit","isVisible":true,"order":1},{"buttonID":"ai","isVisible":true,"order":2}]}
        """
        let migrated = try JSONDecoder().decode(LingxiSettings.self, from: Data(deprecatedButtonsJSON.utf8))
        XCTAssertEqual(migrated.toolbarLayout.count, ToolbarButtonID.allCases.count)
        XCTAssertEqual(migrated.toolbarLayout.first?.buttonID, .ai)
        // 缺失的按钮应被补全且默认可见
        XCTAssertTrue(custom.contains(where: { $0.buttonID == .undo && $0.isVisible }))
        // order 应被重排为 0..n-1
        XCTAssertEqual(custom.map({ $0.order }), Array(0..<custom.count))
        // 重复项去重：同一按钮出现两次只保留一个
        let dup = LingxiSettings.normalizedToolbarLayout([
            ToolbarItemConfig(buttonID: .ai, isVisible: true, order: 0),
            ToolbarItemConfig(buttonID: .ai, isVisible: false, order: 1),
        ])
        XCTAssertEqual(dup.filter({ $0.buttonID == .ai }).count, 1)

        // 高度/字号越界钳制
        let clampJSON = "{\"candidateBarHeight\":100,\"candidateFontSize\":5}"
        let clamped = try JSONDecoder().decode(LingxiSettings.self, from: Data(clampJSON.utf8))
        XCTAssertEqual(clamped.candidateBarHeight, 64, accuracy: 0.001)
        XCTAssertEqual(clamped.candidateFontSize, 14, accuracy: 0.001)

        // 编码-解码往返保持完整字段
        var full = LingxiSettings()
        full.toolbarLayout = LingxiSettings.normalizedToolbarLayout([
            ToolbarItemConfig(buttonID: .settings, isVisible: true, order: 0),
            ToolbarItemConfig(buttonID: .undo, isVisible: false, order: 1),
        ])
        full.showComposingStrip = false
        full.candidateBarHeight = 58
        full.candidateFontSize = 19.5
        let data = try JSONEncoder().encode(full)
        let roundTrip = try JSONDecoder().decode(LingxiSettings.self, from: data)
        XCTAssertEqual(roundTrip, full)
        XCTAssertFalse(roundTrip.showComposingStrip)
        XCTAssertEqual(roundTrip.candidateBarHeight, 58, accuracy: 0.001)
        XCTAssertEqual(roundTrip.candidateFontSize, 19.5, accuracy: 0.001)
        XCTAssertEqual(roundTrip.toolbarLayout.first?.buttonID, .settings)

        // 另一端钳制：高度下限 44 / 字号上限 22
        let clampLowJSON = "{\"candidateBarHeight\":10,\"candidateFontSize\":99}"
        let clampedLow = try JSONDecoder().decode(LingxiSettings.self, from: Data(clampLowJSON.utf8))
        XCTAssertEqual(clampedLow.candidateBarHeight, 44, accuracy: 0.001)
        XCTAssertEqual(clampedLow.candidateFontSize, 22, accuracy: 0.001)
    }

    // MARK: - M1.5 加密备份

    func testBackupEncryptDecryptRoundtrip() throws {
        let createdAt = Date(timeIntervalSince1970: 1_760_000_000)
        let payload = LingxiBackup.Payload(
            schemaVersion: LingxiBackup.currentSchemaVersion,
            createdAt: createdAt,
            files: [
                "lingxi_settings.json": Data("{\"candidateBarHeight\":50}".utf8),
                "user_dict.sqlite": Data([0x53, 0x51, 0x4C, 0x69, 0x74, 0x65])
            ]
        )
        let data = try LingxiBackup.encrypt(
            password: "correct-horse-8",
            payload: payload,
            appVersion: "2.3.0",
            now: createdAt
        )
        let decoded = try LingxiBackup.decrypt(data: data, password: "correct-horse-8")
        XCTAssertEqual(decoded.files, payload.files)
        XCTAssertEqual(decoded.schemaVersion, payload.schemaVersion)
        XCTAssertEqual(decoded.createdAt, createdAt)
    }

    func testBackupWrongPasswordAndTamperDetection() throws {
        let payload = LingxiBackup.Payload(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            files: ["lingxi_phrases.json": Data("[]".utf8)]
        )
        let data = try LingxiBackup.encrypt(password: "password-123", payload: payload)

        // 错误密码：GCM 认证失败，统一归类为密码错误或损坏
        XCTAssertThrowsError(try LingxiBackup.decrypt(data: data, password: "password-124")) { error in
            XCTAssertEqual(error as? LingxiBackup.BackupError, .wrongPasswordOrCorrupted)
        }

        // 篡改密文尾部字节后必须解密失败（防篡改）
        var tampered = data
        tampered[tampered.count - 3] ^= 0xFF
        XCTAssertThrowsError(try LingxiBackup.decrypt(data: tampered, password: "password-123"))
    }

    func testBackupWeakPasswordAndInvalidFormat() throws {
        let payload = LingxiBackup.Payload(schemaVersion: 1, createdAt: Date(), files: [:])
        XCTAssertThrowsError(
            try LingxiBackup.encrypt(password: "short", payload: payload)
        ) { error in
            XCTAssertEqual(error as? LingxiBackup.BackupError, .weakPassword)
        }
        XCTAssertNil(LingxiBackup.peekMetadata(from: Data("not a backup".utf8)))
    }

    func testBackupPeekMetadataWithoutDecrypting() throws {
        let payload = LingxiBackup.Payload(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1_760_000_123),
            files: [:]
        )
        let data = try LingxiBackup.encrypt(password: "password-123", payload: payload, appVersion: "2.4.0")
        let meta = try XCTUnwrap(LingxiBackup.peekMetadata(from: data))
        XCTAssertEqual(meta.format, "LINGXI-BACKUP")
        XCTAssertEqual(meta.schemaVersion, LingxiBackup.currentSchemaVersion)
        XCTAssertEqual(meta.appVersion, "2.4.0")
        XCTAssertEqual(meta.kdf, "PBKDF2-HMAC-SHA256")
        XCTAssertEqual(meta.kdfRounds, LingxiBackup.kdfRounds)
    }

    // MARK: - M1.5 打字统计趋势窗口

    func testTypingStatsRecentDaysWindow() {
        // 测试使用独立实例（不与 shared 单例串状态）；先清空再构造确定性数据
        let store = TypingStatsStore()
        store.clearAll()
        let now = Date()
        let day: TimeInterval = 86400
        store.recordCommit(text: "三天前写的", at: now.addingTimeInterval(-3 * day))
        store.recordCommit(text: "四十天前写的", at: now.addingTimeInterval(-40 * day))
        store.recordCommit(text: "今天写的", at: now)

        let entries = store.recentDays(limit: 30, now: now)
        XCTAssertEqual(entries.count, 2, "40 天前的记录不应出现在 30 天窗口内")
        XCTAssertEqual(entries.first?.chars, 5)
        XCTAssertEqual(entries.last?.chars, 4)
        XCTAssertLessThan(entries[0].day, entries[1].day, "趋势数据必须按日期升序")

        store.clearAll()
    }

    // MARK: - M2 同步地基（Lamport / LWW / E2EE）

    private func makeChange(ns: String, key: String, ts: UInt64, device: String, tombstone: Bool = false) -> SyncChange {
        SyncChange(
            namespace: SyncNamespace(rawValue: ns),
            key: key,
            ciphertext: Data("v-\(ts)-\(device)".utf8),
            lamportTS: ts,
            deviceID: device,
            tombstone: tombstone
        )
    }

    func testLamportClockTickAndObserve() {
        var persisted: [UInt64] = []
        let clock = LamportClock(initial: 5, persist: { persisted.append($0) })
        XCTAssertEqual(clock.value, 5)
        XCTAssertEqual(clock.tick(), 6)
        XCTAssertEqual(clock.observe(remote: 10), 11)
        XCTAssertEqual(clock.observe(remote: 3), 12, "远端时钟落后时本地仍递增（ADR 0001：max(local, remote) + 1）")
        XCTAssertEqual(clock.value, 12)
        XCTAssertEqual(persisted, [6, 11, 12], "每次变化都必须落盘，崩溃后恢复值只增不减")
    }

    func testLamportClockRestoreFromPersistedValue() {
        let clock = LamportClock(initial: 42)
        XCTAssertEqual(clock.tick(), 43, "崩溃重启后从持久化值恢复，时钟绝不回退")
    }

    func testLWWMergeEngineRemoteWinsByLamport() {
        let local = [makeChange(ns: "settings", key: "haptic", ts: 10, device: "A")]
        let remote = [makeChange(ns: "settings", key: "haptic", ts: 12, device: "B")]
        let outcome = LWWMergeEngine.merge(local: local, remote: remote)
        XCTAssertEqual(outcome.merged.count, 1)
        XCTAssertEqual(outcome.merged.first?.deviceID, "B")
        XCTAssertEqual(outcome.toApply.count, 1)
        XCTAssertEqual(outcome.watermark, 12)
    }

    func testLWWMergeEngineTieBrokenByDeviceID() {
        let local = [makeChange(ns: "settings", key: "haptic", ts: 10, device: "B")]
        let remote = [makeChange(ns: "settings", key: "haptic", ts: 10, device: "C")]
        let outcome = LWWMergeEngine.merge(local: local, remote: remote)
        XCTAssertEqual(outcome.merged.first?.deviceID, "C", "lamport 相同时 deviceID 字典序大者胜")
        XCTAssertEqual(outcome.toApply.first?.deviceID, "C")
    }

    func testLWWMergeEngineTombstoneWins() {
        let local = [makeChange(ns: "phrases", key: "p1", ts: 10, device: "A")]
        let remote = [makeChange(ns: "phrases", key: "p1", ts: 11, device: "B", tombstone: true)]
        let outcome = LWWMergeEngine.merge(local: local, remote: remote)
        XCTAssertEqual(outcome.merged.first?.tombstone, true, "删除也是一次写入：墓碑参与决胜")
        XCTAssertEqual(outcome.toApply.first?.tombstone, true)
    }

    func testLWWMergeEngineLocalWinsKeepsState() {
        let local = [makeChange(ns: "settings", key: "k", ts: 20, device: "A")]
        let remote = [makeChange(ns: "settings", key: "k", ts: 5, device: "B")]
        let outcome = LWWMergeEngine.merge(local: local, remote: remote)
        XCTAssertEqual(outcome.merged.first?.deviceID, "A")
        XCTAssertTrue(outcome.toApply.isEmpty, "本地胜出时远端旧记录不应落本地")
        XCTAssertEqual(outcome.watermark, 20)
    }

    func testLWWMergeEngineBatchSameKeyOnlyFinalWinnerApplied() {
        let remote = [
            makeChange(ns: "lexicon", key: "w1", ts: 8, device: "B"),
            makeChange(ns: "lexicon", key: "w1", ts: 15, device: "B"),
            makeChange(ns: "lexicon", key: "w1", ts: 12, device: "C")
        ]
        let outcome = LWWMergeEngine.merge(local: [], remote: remote)
        XCTAssertEqual(outcome.merged.count, 1)
        XCTAssertEqual(outcome.merged.first?.lamportTS, 15)
        XCTAssertEqual(outcome.toApply.count, 1, "批内同键多版本只应用最终胜者")
        XCTAssertEqual(outcome.toApply.first?.lamportTS, 15)
        XCTAssertEqual(outcome.watermark, 15)
    }

    func testLWWMergeEngineNamespacesIsolated() {
        let local = [makeChange(ns: "settings", key: "same", ts: 30, device: "A")]
        let remote = [makeChange(ns: "theme", key: "same", ts: 10, device: "B")]
        let outcome = LWWMergeEngine.merge(local: local, remote: remote)
        XCTAssertEqual(outcome.merged.count, 2, "不同命名空间的同名 key 互不冲突")
        XCTAssertEqual(outcome.toApply.count, 1)
        XCTAssertEqual(outcome.watermark, 30)
    }

    func testSyncCryptoSealOpenRoundtripAndTamper() throws {
        let master = Data("master-secret-material-0123456789ab".utf8)
        let key = SyncCrypto.deriveSyncKey(from: master)
        let value = Data("{\"candidateBarHeight\":50}".utf8)

        let sealed = try SyncCrypto.seal(value, key: key)
        XCTAssertNotEqual(sealed, value, "密文不得等于明文")
        XCTAssertEqual(try SyncCrypto.open(sealed, key: key), value)

        // nonce 每次随机：同明文两次加密密文不同
        let sealed2 = try SyncCrypto.seal(value, key: key)
        XCTAssertNotEqual(sealed, sealed2)

        // 篡改密文必须解密失败（GCM 认证标签）
        var tampered = sealed
        tampered[tampered.count - 1] ^= 0x01
        XCTAssertThrowsError(try SyncCrypto.open(tampered, key: key))

        // 错误密钥材料必须解密失败
        let wrongKey = SyncCrypto.deriveSyncKey(from: Data("another-master-material-9876543210".utf8))
        XCTAssertThrowsError(try SyncCrypto.open(sealed, key: wrongKey))

        // 同一材料派生确定性一致（多设备同凭据可恢复同钥）
        let keyAgain = SyncCrypto.deriveSyncKey(from: master)
        XCTAssertEqual(try SyncCrypto.open(sealed, key: keyAgain), value)
    }

    func testDeviceIdentityStableAcrossCalls() {
        let first = SyncInfra.deviceIdentity()
        XCTAssertFalse(first.deviceID.isEmpty)
        let second = SyncInfra.deviceIdentity()
        XCTAssertEqual(first, second, "设备身份必须稳定（LWW 决胜第二排序键的前提）")
    }

    // MARK: - M3-pre 同步引擎（SyncEngine / SnapshotSyncSource）

    /// 测试用同步服务桩：记录推送批次与拉取调用，按需返回拉取页与冲突
    private final class MockSyncService: SyncService {
        var pushedBatches: [[SyncChange]] = []
        var pullCalls: [SyncNamespace] = []
        var pullResult: SyncPage
        var conflicts: [SyncConflict]

        init(pullResult: SyncPage = SyncPage(changes: [], nextCursor: 0, hasMore: false),
             conflicts: [SyncConflict] = []) {
            self.pullResult = pullResult
            self.conflicts = conflicts
        }

        func pull(namespace: SyncNamespace, since: UInt64) async throws -> SyncPage {
            pullCalls.append(namespace)
            return pullResult
        }

        func push(_ changes: [SyncChange]) async throws -> [SyncConflict] {
            pushedBatches.append(changes)
            return conflicts
        }
    }

    /// 引擎测试夹具：测试专用文件名 + 注入时钟 + 独立账本文件，绝不触碰真实用户数据
    private func makeEngineFixture(_ mock: SyncService, testFile: String, ledgerFile: String) -> (SyncEngine, URL) {
        let engine = SyncEngine(
            sync: mock,
            source: SnapshotSyncSource(entries: [.init(namespace: .settings, fileName: testFile)]),
            clock: LamportClock(),
            deviceID: "test-device",
            ledgerStore: SyncLedgerStore(fileName: ledgerFile)
        )
        return (engine, AppGroup.fileURL(testFile))
    }

    func testSyncEngineLocalPushThenDedup() async throws {
        let mock = MockSyncService()
        let (engine, url) = makeEngineFixture(mock, testFile: "test_sync_a.json", ledgerFile: "test_ledger_a.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try "v1".write(to: url, atomically: true, encoding: .utf8)
        let r1 = try await engine.syncNow()
        XCTAssertEqual(r1.pushed, 1)
        XCTAssertEqual(mock.pushedBatches.count, 1)
        XCTAssertEqual(r1.applied, 0)

        let r2 = try await engine.syncNow()
        XCTAssertEqual(r2.pushed, 0, "内容未变不得重复推送（账本字节级去重）")
        XCTAssertEqual(mock.pushedBatches.count, 1)

        try "v2".write(to: url, atomically: true, encoding: .utf8)
        let r3 = try await engine.syncNow()
        XCTAssertEqual(r3.pushed, 1, "内容变化后再次推送新版本")
    }

    func testSyncEngineRemoteWinOverwritesLocalFile() async throws {
        let remoteChange = SyncChange(
            namespace: .settings, key: "main",
            ciphertext: Data("remote-v9".utf8),
            lamportTS: 99, deviceID: "device-b"
        )
        let mock = MockSyncService(pullResult: SyncPage(changes: [remoteChange], nextCursor: 99, hasMore: false))
        let (engine, url) = makeEngineFixture(mock, testFile: "test_sync_b.json", ledgerFile: "test_ledger_b.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try "local-v1".write(to: url, atomically: true, encoding: .utf8)
        let report = try await engine.syncNow()

        XCTAssertEqual(report.applied, 1, "远端更高时间戳胜出并落盘")
        XCTAssertEqual(try Data(contentsOf: url), Data("remote-v9".utf8))
        XCTAssertEqual(mock.pullCalls, [.settings])
        XCTAssertEqual(report.pushed, 1)
    }

    func testSyncEngineTombstoneDeletesLocalFile() async throws {
        let tombstone = SyncChange(
            namespace: .settings, key: "main",
            ciphertext: Data(), lamportTS: 50, deviceID: "device-b", tombstone: true
        )
        let mock = MockSyncService(pullResult: SyncPage(changes: [tombstone], nextCursor: 50, hasMore: false))
        let (engine, url) = makeEngineFixture(mock, testFile: "test_sync_c.json", ledgerFile: "test_ledger_c.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try "to-be-deleted".write(to: url, atomically: true, encoding: .utf8)
        let report = try await engine.syncNow()
        XCTAssertEqual(report.applied, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "墓碑胜出后本地文件应被删除")
    }

    func testSyncEngineLocalWinKeepsLocalFile() async throws {
        let staleRemote = SyncChange(
            namespace: .settings, key: "main",
            ciphertext: Data("stale".utf8),
            lamportTS: 0, deviceID: "device-old"
        )
        let mock = MockSyncService(pullResult: SyncPage(changes: [staleRemote], nextCursor: 0, hasMore: false))
        let (engine, url) = makeEngineFixture(mock, testFile: "test_sync_d.json", ledgerFile: "test_ledger_d.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try "local-current".write(to: url, atomically: true, encoding: .utf8)
        let report = try await engine.syncNow()
        XCTAssertEqual(report.applied, 0, "本地时间戳更高时远端旧记录不落盘")
        XCTAssertEqual(try Data(contentsOf: url), Data("local-current".utf8))
    }

    func testSyncEngineWithLocalNoopIsHarmless() async throws {
        let engine = SyncEngine(
            sync: LocalNoopSyncService(),
            source: SnapshotSyncSource(entries: [.init(namespace: .theme, fileName: "test_sync_e.json")]),
            clock: LamportClock(),
            deviceID: "test-device",
            ledgerStore: SyncLedgerStore(fileName: "test_ledger_e.json")
        )
        let url = AppGroup.fileURL("test_sync_e.json")
        defer { try? FileManager.default.removeItem(at: url) }
        try "noop".write(to: url, atomically: true, encoding: .utf8)

        let report = try await engine.syncNow()
        XCTAssertEqual(report.pushed, 1, "Noop push 语义：无云端数据、无冲突")
        XCTAssertEqual(report.pulled, 0)
        XCTAssertEqual(report.applied, 0)
        XCTAssertEqual(report.conflicts, 0)
    }

    func testSyncEngineServerConflictWinApplied() async throws {
        let serverWin = SyncChange(
            namespace: .settings, key: "main",
            ciphertext: Data("server-wins".utf8),
            lamportTS: 100, deviceID: "device-b"
        )
        let mock = MockSyncService(
            pullResult: SyncPage(changes: [], nextCursor: 0, hasMore: false),
            conflicts: [SyncConflict(namespace: .settings, key: "main", serverRecord: serverWin)]
        )
        let (engine, url) = makeEngineFixture(mock, testFile: "test_sync_f.json", ledgerFile: "test_ledger_f.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try "local-old".write(to: url, atomically: true, encoding: .utf8)
        let report = try await engine.syncNow()

        XCTAssertEqual(report.conflicts, 1)
        XCTAssertEqual(report.applied, 1, "服务端 LWW 胜出记录视为远端最新并落盘")
        XCTAssertEqual(try Data(contentsOf: url), Data("server-wins".utf8))
    }

    func testTypingHabitTrackerAndRealTimeProfileAnalysis() {
        let events = [
            TypingHabitEventPayload(
                startedAt: 1_760_000_000,
                durationSeconds: 60,
                committedChars: 180,
                committedWords: 60,
                deleteCount: 24,
                undoLearnCount: 4,
                glideWords: 12,
                typoCorrectedCount: 6,
                aiInvocations: 2,
                translateChars: 40,
                schemeID: "xiaohe",
                layoutID: "qwerty26",
                activeHour: 23,
                deviceID: "test-dev",
                confusionCounts: ["zh_z": 4, "an_ang": 2]
            )
        ]
        let aiLogs = [
            AIAPIUsagePayload(
                feature: "live_translate",
                provider: "gemini",
                targetLang: "英文",
                formalTone: true,
                inputChars: 40,
                outputChars: 85,
                latencyMs: 310
            )
        ]
        let profile = TypingHabitTracker.computeProfile(events: events, aiLogs: aiLogs, userID: "u-test")
        XCTAssertEqual(profile.totalChars, 180)
        XCTAssertEqual(profile.totalWords, 60)
        XCTAssertEqual(profile.avgCPM, 180.0, accuracy: 0.1)
        XCTAssertEqual(profile.avgWordLength, 3.0, accuracy: 0.01)
        XCTAssertEqual(profile.primaryScheme, "xiaohe")
        XCTAssertEqual(profile.confusionMatrix["zh_z"], 4)
        XCTAssertTrue(profile.habitTags.contains("小鹤双拼高阶用户"))
        XCTAssertTrue(profile.habitTags.contains("高速击键达人"))
        XCTAssertTrue(profile.habitTags.contains("长句整输习惯"))
        XCTAssertTrue(profile.habitTags.contains("滑行轨迹玩家"))
        XCTAssertTrue(profile.habitTags.contains("深夜高产创作者"))
        XCTAssertTrue(profile.habitTags.contains("AI 协同写作者"))
        XCTAssertTrue(profile.tuningRecommendations.contains { $0.settingKey == "fuzzy.zhZ" })
        XCTAssertTrue(profile.tuningRecommendations.contains { $0.settingKey == "dynamicKeyHitBoxEnabled" })
        XCTAssertTrue(profile.tuningRecommendations.contains { $0.settingKey == "autoLearnThreshold" })
        XCTAssertEqual(profile.aiFeatureBreakdown["live_translate"]?.calls, 1)

        // 拼音易混音自动检测测试
        let conf1 = TypingHabitTracker.detectPinyinConfusions(rawInput: "zongguo", resolvedPinyin: "zhong'guo")
        XCTAssertEqual(conf1["zh_z"], 1)
        let conf2 = TypingHabitTracker.detectPinyinConfusions(rawInput: "fanan", resolvedPinyin: "fang'an")
        XCTAssertEqual(conf2["an_ang"], 1)
        let conf3 = TypingHabitTracker.detectPinyinConfusions(rawInput: "lihao", resolvedPinyin: "ni'hao")
        XCTAssertEqual(conf3["n_l"], 1)

        // 个人词库领域偏好分析测试
        let dom = TypingHabitTracker.analyzeLexiconDomains(words: ["微服务架构", "数据库索引", "后端接口部署"])
        XCTAssertEqual(dom.primaryDomain, "科技与研发")
    }

    func testCompositeAndLexiconSyncSource() async throws {
        let lexicon = UserLexicon()
        _ = lexicon.importTSV("ling xi yun\t灵犀云同步测试词\t5\t1\n")
        defer { lexicon.forget(word: "灵犀云同步测试词", py: "ling'xi'yun") }

        let mock = MockSyncService()
        let composite = CompositeSyncSource(sources: [
            SnapshotSyncSource(entries: [.init(namespace: .settings, fileName: "test_comp_settings.json")]),
            UserLexiconSyncSource()
        ])
        let settingsURL = AppGroup.fileURL("test_comp_settings.json")
        defer { try? FileManager.default.removeItem(at: settingsURL) }
        try "{\"inputScheme\":\"xiaohe\"}".write(to: settingsURL, atomically: true, encoding: .utf8)

        let engine = SyncEngine(
            sync: mock,
            source: composite,
            clock: LamportClock(),
            deviceID: "test-dev",
            ledgerStore: SyncLedgerStore(fileName: "test_ledger_composite.json")
        )
        let report = try await engine.syncNow()
        XCTAssertEqual(report.pushed, 2, "设置快照与个人词库应在同一轮事务中一并推送")
        let pushedNamespaces = Set(mock.pushedBatches.flatMap { $0.map(\.namespace) })
        XCTAssertTrue(pushedNamespaces.contains(.settings))
        XCTAssertTrue(pushedNamespaces.contains(.lexicon))
    }

    func testL1SensitiveClipboardShieldingAndL2L3CryptoAndM2M4Compliance() throws {
        // L1 端侧敏感形态（身份证号 / 密码 / 私钥）自动屏蔽测试
        XCTAssertTrue(ClipboardClassifier.isSensitiveContent("11010519900307281X"), "18位身份证号必须自动屏蔽")
        XCTAssertTrue(ClipboardClassifier.isSensitiveContent("登录密码：MySuperSecret99"), "显式密码串必须自动屏蔽")
        XCTAssertTrue(ClipboardClassifier.isSensitiveContent("-----BEGIN PRIVATE KEY----- MIIEvgIBADANBg"), "私钥串必须自动屏蔽")
        XCTAssertFalse(ClipboardClassifier.isSensitiveContent("【灵犀】您的验证码是 849201，5分钟内有效"), "正常短信验证码不得误屏蔽")
        XCTAssertFalse(ClipboardClassifier.isSensitiveContent("https://lingxi.app/docs"), "普通链接不得误屏蔽")

        // L2 ChaCha20-Poly1305 AEAD 与 L3 HMAC-SHA256 请求防重放签名测试
        let master = Data("lingxi-l2-chacha-key-material-2026".utf8)
        let key = SyncCrypto.deriveSyncKey(from: master)
        let plain = Data("{\"lexicon\":\"零知识密文同步\"}".utf8)
        let chachaCipher = try SyncCrypto.sealChaChaPoly(plain, key: key)
        XCTAssertNotEqual(chachaCipher, plain)
        let chachaOpened = try SyncCrypto.openChaChaPoly(chachaCipher, key: key)
        XCTAssertEqual(chachaOpened, plain)

        let sig1 = SyncCrypto.signRequest(body: plain, timestamp: 1_760_000_000, nonce: "n-1001", secret: "sk_test")
        let sig2 = SyncCrypto.signRequest(body: plain, timestamp: 1_760_000_000, nonce: "n-1001", secret: "sk_test")
        let sigDiff = SyncCrypto.signRequest(body: plain, timestamp: 1_760_000_301, nonce: "n-1001", secret: "sk_test")
        XCTAssertEqual(sig1, sig2, "相同 body+ts+nonce 的 HMAC-SHA256 签名必须确定性一致")
        XCTAssertNotEqual(sig1, sigDiff, "时间戳变动后签名必须不同")

        // M4 词库社区订阅服务（复用 WowType TSV 格式）测试
        let packCount = CommunityLexiconService.shared.subscribe(packID: "ai_llm_tech")
        XCTAssertGreaterThan(packCount, 0, "订阅社区词库包应成功导入词条")
        XCTAssertTrue(CommunityLexiconService.shared.isSubscribed("ai_llm_tech"))

        // 第六部分 PIPL / GDPR 不可变授权流水与全量数据可携权导出测试
        ComplianceService.shared.recordConsent(scope: "typing_analytics", granted: true)
        let exportedJSON = ComplianceService.shared.exportAllPortableDataJSON()
        XCTAssertTrue(exportedJSON.contains("LINGXI-GDPR-PORTABLE-EXPORT-v1"), "可携权导出必须包含完整 JSON 导出信封")
        XCTAssertTrue(exportedJSON.contains("consentAuditLedger"), "可携权导出必须包含不可变授权流水")

        // 可持续发展引擎健康自愈巡检与 BigBang 炸词提取测试
        let healthBefore = EngineHealthAndSustainabilityService.shared.diagnose()
        XCTAssertGreaterThanOrEqual(healthBefore.healthScore, 60)
        let healOutcome = EngineHealthAndSustainabilityService.shared.performSelfHealing()
        XCTAssertGreaterThanOrEqual(healOutcome.newHealthScore, 60)

        let tokens = BigBangTokenizer.tokenize("灵犀输入法支持跨设备实时剪贴板接力与零知识同步")
        XCTAssertFalse(tokens.isEmpty, "BigBang 炸词分词结果不得为空")
    }

    func testThemeCustomizationColorPaletteAndPresetSwitching() throws {
        // 1. HexColor 亮度与 WCAG 对比度算法校验
        let pureWhite = HexColor("#FFFFFF")
        let pureBlack = HexColor("#000000")
        XCTAssertFalse(pureWhite.isDarkColor)
        XCTAssertTrue(pureBlack.isDarkColor)
        XCTAssertEqual(pureWhite.contrastRatio(with: pureBlack), 21.0, accuracy: 0.05)
        XCTAssertEqual(pureWhite.contrastRatio(with: pureWhite), 1.0, accuracy: 0.01)

        // 2. 默认纯白圆角按键与跟随系统模式
        var theme = ThemeCustomization()
        let lightDefault = theme.activePreset(isSystemDark: false)
        XCTAssertEqual(lightDefault.id, "lingxi_pure")
        XCTAssertEqual(lightDefault.keyFill.hex.uppercased(), "#FFFFFF")
        XCTAssertFalse(lightDefault.isDark)
        let darkDefault = theme.activePreset(isSystemDark: true)
        XCTAssertTrue(darkDefault.isDark)

        // 3. 预设切换：在浅色系统下点深色预设必须立即切换生效并清除自定义色覆盖
        theme.customKeyFillHex = "#FFE4E1"
        XCTAssertTrue(theme.hasCustomColorOverrides)
        let cyber = KeyboardThemePreset.find(id: "cyber_neon")
        theme.applyPresetSelection(cyber, isSystemDark: false)
        XCTAssertFalse(theme.hasCustomColorOverrides)
        XCTAssertEqual(theme.appearanceMode, .alwaysDark)
        XCTAssertEqual(theme.activePreset(isSystemDark: false).id, "cyber_neon")

        // 4. 自由调色板：自定义深色画布 + 亮色强调色应自动推导 isDark / accentText / 按下态色值
        theme.customCanvasHex = "#121826"
        theme.customKeyFillHex = "#1E293B"
        theme.customKeyTextHex = "#F8FAFC"
        theme.customAccentHex = "#FACC15"
        let customActive = theme.activePreset(isSystemDark: false)
        XCTAssertTrue(customActive.isDark, "深色自定义底色应自动推导为深色模式")
        XCTAssertEqual(customActive.keyFill.hex.uppercased(), "#1E293B")
        XCTAssertEqual(customActive.keyText.hex.uppercased(), "#F8FAFC")
        XCTAssertEqual(customActive.accentText.hex.uppercased(), "#0A0A0A", "亮黄色强调色应自动配深色文字")
        XCTAssertNotEqual(customActive.keyPressedFill, customActive.keyFill, "按键按下态色值应自动推导且与默认态有区分")

        // 4b. 从深色自定义调色一键切回浅色模式，应自动清除冲突暗色并恢复纯白键帽
        theme.applyAppearanceMode(.alwaysLight)
        XCTAssertFalse(theme.hasCustomColorOverrides)
        XCTAssertEqual(theme.activePreset(isSystemDark: true).keyFill.hex.uppercased(), "#FFFFFF")
        XCTAssertFalse(theme.activePreset(isSystemDark: true).isDark)

        // 5. 旧版 JSON 兼容解码
        let legacyJSON = Data("{\"selectedThemeID\":\"sakura_mist\",\"adaptiveDarkMode\":false}".utf8)
        let decoded = try JSONDecoder().decode(ThemeCustomization.self, from: legacyJSON)
        XCTAssertEqual(decoded.lightThemeID, "sakura_mist")
        XCTAssertEqual(decoded.appearanceMode, .alwaysLight)
    }

    func testClipboardPendingBannerLifecycleAndAccountConfigDecode() throws {
        // 剪贴板顶栏接管条目生命周期：record -> pendingBannerItem -> delete/clear
        ClipboardStore.clearPendingBanner()
        let recorded = ClipboardStore.record("【灵犀】验证码 609321，支持左右滑动预览测试")
        XCTAssertNotNil(recorded)
        XCTAssertEqual(recorded?.extractedCode, "609321")
        XCTAssertEqual(ClipboardStore.pendingBannerItem()?.id, recorded?.id)

        if let id = recorded?.id {
            ClipboardStore.delete(id: id)
        }
        XCTAssertNil(ClipboardStore.pendingBannerItem(), "删除待展示条目后应自动清空 pendingBannerItem")

        // CloudBackendConfig 向后兼容解码（缺少 avatarThemeIndex 时默认为 0，旧版 127.0.0.1:8787 与 workers.dev 自动迁移至中国直连 Cloudflare Pages 节点）
        let legacyCloudJSON = Data("{\"serverBaseURL\":\"http://127.0.0.1:8787\",\"username\":\"测试用户\"}".utf8)
        let cfg = try JSONDecoder().decode(CloudBackendConfig.self, from: legacyCloudJSON)
        XCTAssertEqual(cfg.username, "测试用户")
        XCTAssertEqual(cfg.avatarThemeIndex, 0)
        XCTAssertFalse(cfg.isLocalOnlyAccount)
        XCTAssertEqual(cfg.normalizedBaseURL, CloudBackendConfig.defaultCloudServerURL)
        XCTAssertEqual(CloudBackendConfig.defaultCloudServerURL, "https://lingxi-ime.pages.dev")

        let legacyWorkersJSON = Data("{\"serverBaseURL\":\"https://lingxi-cloud.1455952.workers.dev\",\"username\":\"旧版用户\"}".utf8)
        let migratedCfg = try JSONDecoder().decode(CloudBackendConfig.self, from: legacyWorkersJSON)
        XCTAssertEqual(migratedCfg.normalizedBaseURL, "https://lingxi-ime.pages.dev")
    }

    func testOfflineLocalAccountRegisterLoginAndQuickSignIn() async throws {
        // 指向不可达端口，模拟纯 iPhone 离线/无自建服务器环境
        var cfg = CloudBackendConfig.load()
        let prevURL = cfg.serverBaseURL
        cfg.serverBaseURL = "http://127.0.0.1:1"
        cfg.save()
        defer {
            var restore = CloudBackendConfig.load()
            restore.serverBaseURL = prevURL
            restore.save()
        }

        let uniqueEmail = "ios_\(UUID().uuidString.prefix(8).lowercased())@lingxi.test"
        let client = CloudBackendClient(timeout: 2)

        // 1. 离线邮箱注册应自动落入本机加密账号库，不再因无服务器报错
        let regSession = try await client.register(email: uniqueEmail, username: "真机测试号", password: "password123")
        XCTAssertTrue(regSession.userID.hasPrefix("local-"))
        XCTAssertTrue(CloudBackendConfig.load().isLocalOnlyAccount)
        XCTAssertEqual(CloudBackendConfig.load().username, "真机测试号")

        // 2. 退出后，错误密码应被拒绝，正确密码应成功登录
        await client.signOut()
        XCTAssertFalse(client.isAuthenticatedOrHasAPIKey)

        do {
            _ = try await client.login(account: uniqueEmail, password: "wrong_password")
            XCTFail("错误密码不应允许登录")
        } catch {
            // 预期拦截
        }

        let loginSession = try await client.login(account: uniqueEmail, password: "password123")
        XCTAssertEqual(loginSession.userID, regSession.userID)
        XCTAssertTrue(client.isAuthenticatedOrHasAPIKey)

        // 3. 一键本机账号创建应立即可用
        await client.signOut()
        let quick = client.createQuickLocalAccount(username: "快速体验")
        XCTAssertTrue(quick.userID.hasPrefix("local-"))
        XCTAssertTrue(client.isAuthenticatedOrHasAPIKey)
        await client.signOut()
    }

    func testLongPinyinPreservesSingleCharacters() throws {
        guard let dbURL = findTestDBURL() else {
            throw XCTSkip("未找到测试词库 pinyin.sqlite")
        }
        let engine = PinyinEngine(databaseURL: dbURL)
        var settings = LingxiSettings()
        settings.userLearningEnabled = false

        // 1. 6 音节与 10 音节长全拼：整句仍居首位，且单字既出现在前 36 位候选栏，也完整保留在展开面板「只看单字」中
        let longQueries = [
            ("jintiantianqizhenhao", "今天天气真好", "今"),
            ("woxiangquchifanzuijintianqizhenhao", "我想去吃饭最近天气真好", "我"),
            ("zhhrmghg", "中华人民共和国", "这"),
        ]
        for (raw, expectedTop, expectedSingle) in longQueries {
            let res = engine.query(raw: raw, settings: settings)
            XCTAssertEqual(res.candidates.first?.word, expectedTop, "\(raw) 首选应保持整句准确")
            let barSingles = res.candidates.prefix(36).filter { $0.word.count == 1 }.map(\.word)
            let allSingles = res.candidates.filter { $0.word.count == 1 }.map(\.word)
            XCTAssertGreaterThanOrEqual(barSingles.count, 5, "\(raw) 顶部横向候选栏前 36 项应包含高频单字")
            XCTAssertTrue(allSingles.contains(expectedSingle), "\(raw) 单字列表中应包含首音节核心单字 \(expectedSingle)")
            XCTAssertGreaterThanOrEqual(allSingles.count, 12, "\(raw) 展开单字池应保留至少 12 个单字")
        }

        // 2. T9 九宫格长句同样保底返回首音节单字
        let t9Res = engine.queryT9(digits: "54684268426749436426", lockedSyllables: [], settings: settings)
        let t9Singles = t9Res.candidates.filter { $0.word.count == 1 }
        XCTAssertGreaterThanOrEqual(t9Singles.count, 10, "T9 长输入也必须保底返回单字")
    }

    func testAIAutoInsightAndSmartContextDetector() throws {
        // 1. 旧版 AIConfig JSON 向后兼容解码（无 customPrompts 字段时自动补齐默认模板并保留原 API Key）
        let legacyAIJSON = Data("{\"provider\":\"gemini\",\"geminiAPIKey\":\"AIza_test_key\",\"temperature\":0.6}".utf8)
        let decodedAI = try JSONDecoder().decode(AIConfig.self, from: legacyAIJSON)
        XCTAssertEqual(decodedAI.geminiAPIKey, "AIza_test_key")
        XCTAssertEqual(decodedAI.temperature, 0.6, accuracy: 0.001)
        XCTAssertFalse(decodedAI.customPrompts.isEmpty)
        XCTAssertTrue(decodedAI.smartContextRecommendEnabled)

        // 2. 端侧自动诊断报告：结合混淆矩阵与领域生成专属人设、定制提示词、短语与模糊音建议
        var profile = UserTypingHabitProfile()
        profile.totalChars = 2600
        profile.totalWords = 900
        profile.avgCPM = 68
        profile.backspaceRate = 0.19
        profile.confusionMatrix = ["zh_z": 6, "en_eng": 4]
        profile.domainAffinity = LexiconDomainAffinity(primaryDomain: "科技开发", preferredTone: "简洁高效")
        let stats = TypingStatsStore.Summary(
            totalChars: 2600,
            totalActiveSeconds: 2200,
            averageCharsPerMinute: 68,
            streakDays: 7,
            todayChars: 320,
            dayCount: 10
        )
        var settings = LingxiSettings()
        let localReport = AIAutoInsightService.generateLocalReport(profile: profile, stats: stats, settings: settings)
        XCTAssertFalse(localReport.personaTitle.isEmpty)
        XCTAssertFalse(localReport.recommendedPersonaPrompt.isEmpty)
        XCTAssertGreaterThanOrEqual(localReport.suggestedPrompts.count, 4)
        XCTAssertGreaterThanOrEqual(localReport.suggestedPhrases.count, 3)
        XCTAssertEqual(Set(localReport.suggestedFuzzyKeys), Set(["zh_z", "en_eng"]))

        let appliedFuzzy = AIAutoInsightService.applyFuzzyKeys(localReport.suggestedFuzzyKeys, to: &settings)
        XCTAssertEqual(appliedFuzzy, 2)
        XCTAssertTrue(settings.fuzzy.zhZ)
        XCTAssertTrue(settings.fuzzy.enEng)

        // 3. 大模型 Markdown JSON 响应健壮解析
        let mockLLM = """
        ```json
        {
          "personaTitle": "极客效率建筑师",
          "styleSummary": "节奏极快且表达直接。",
          "efficiencyDiagnosis": "平翘舌与前后鼻音偶有误拼。",
          "recommendedPersonaPrompt": "保持极简专业的工程师口吻。",
          "suggestedPrompts": [
            {"title": "代码评审", "icon": "sparkles", "category": "职场商务", "instruction": "整理成温和专业的代码评审意见"}
          ],
          "suggestedPhrases": [
            {"title": "已修复", "content": "已修复并验证通过，请查收", "category": "AI推荐"}
          ],
          "actionableTips": ["开启模糊音 zh/z 提速"]
        }
        ```
        """
        let parsed = AIAutoInsightService.parseLLMResponse(mockLLM, fallback: localReport, sourceLabel: "AI 深度分析 · gemini-3.8-flash")
        XCTAssertTrue(parsed.isFromLLM)
        XCTAssertEqual(parsed.personaTitle, "极客效率建筑师")
        XCTAssertEqual(parsed.suggestedPrompts.first?.title, "代码评审")
        XCTAssertEqual(parsed.suggestedPhrases.first?.title, "已修复")

        // 4. 键盘内零延迟语境感知器
        let enRec = SmartContextPromptDetector.analyze(text: "Could you please share the updated API spec before Friday?", isClipboard: false, customPrompts: CustomAIPromptTemplate.defaultTemplates)
        XCTAssertEqual(enRec.recommendedPresets.first, .translateZh)

        let bizRec = SmartContextPromptDetector.analyze(text: "下午项目评审的排期和汇报方案麻烦同步一下", isClipboard: false, customPrompts: CustomAIPromptTemplate.defaultTemplates)
        XCTAssertTrue(bizRec.recommendedCustomIDs.contains("preset_work_report"))

        let askRec = SmartContextPromptDetector.analyze(text: "今晚有空一起吃饭吗？", isClipboard: true, customPrompts: CustomAIPromptTemplate.defaultTemplates)
        XCTAssertEqual(askRec.recommendedPresets.first, .replyClipboard)
    }

    func testV5AIThinkingModelDiscoveryAndStyleDNA() throws {
        // 1. 跨分片 <think> 状态机：绝不向正文泄漏思考草稿
        var splitter = ThinkTagStreamSplitter()
        let parts = ["<thi", "nk>先分析语气与", "重点</th", "ink>收到啦，下午三点同步给你～"]
        var thoughts = ""
        var answers = ""
        for p in parts {
            for ev in splitter.push(p) {
                switch ev {
                case .thought(let t): thoughts += t
                case .answer(let a): answers += a
                }
            }
        }
        for ev in splitter.finish() {
            switch ev {
            case .thought(let t): thoughts += t
            case .answer(let a): answers += a
            }
        }
        XCTAssertEqual(thoughts, "先分析语气与重点")
        XCTAssertEqual(answers, "收到啦，下午三点同步给你～")

        // 2. 远端模型列表动态解析 (Gemini / OpenAI / Ollama)
        let geminiPayload = Data("""
        {
          "models": [
            {"name": "models/gemini-3.8-flash", "displayName": "Gemini 3.8 Flash", "inputTokenLimit": 1048576, "supportedGenerationMethods": ["generateContent"]},
            {"name": "models/text-embedding-004", "displayName": "Embedding", "supportedGenerationMethods": ["embedContent"]}
          ]
        }
        """.utf8)
        let gModels = AIClient.parseGeminiModelsPayload(geminiPayload)
        XCTAssertEqual(gModels.count, 1)
        XCTAssertEqual(gModels.first?.id, "gemini-3.8-flash")
        XCTAssertEqual(gModels.first?.supportsThinking, true)

        let openAIPayload = Data("""
        {"data": [{"id": "deepseek-reasoner", "context_length": 65536}, {"id": "whisper-1"}]}
        """.utf8)
        let oModels = AIClient.parseOpenAIModelsPayload(openAIPayload)
        XCTAssertEqual(oModels.count, 1)
        XCTAssertEqual(oModels.first?.id, "deepseek-reasoner")
        XCTAssertEqual(oModels.first?.supportsThinking, true)

        let ollamaPayload = Data("{\"models\": [{\"name\": \"qwen3:8b\"}]}".utf8)
        let olModels = AIClient.parseOllamaTagsPayload(ollamaPayload)
        XCTAssertEqual(olModels.first?.id, "qwen3:8b")
        XCTAssertEqual(olModels.first?.supportsThinking, true)

        // 3. 跨协议思考模式参数构造
        let g38High = AIClient.geminiThinkingPayload(model: "gemini-3.8-flash", mode: .high, budget: 2048)
        XCTAssertEqual(g38High["thinking_level"] as? String, "high")
        let g25Custom = AIClient.geminiThinkingPayload(model: "gemini-2.5-pro", mode: .customBudget, budget: 4096)
        XCTAssertEqual(g25Custom["thinking_budget"] as? Int, 4096)
        let qwenOff = AIClient.openAIThinkingExtraBody(model: "qwen3-235b", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", mode: .off, budget: 1024)
        XCTAssertEqual(qwenOff["enable_thinking"] as? Bool, false)
        let o3Med = AIClient.openAIThinkingExtraBody(model: "o3-mini", baseURL: "https://api.openai.com/v1", mode: .medium, budget: 1024)
        XCTAssertEqual(o3Med["reasoning_effort"] as? String, "medium")

        // 4. 多渠道档案保存与秒切 + 文风 DNA Diff 自学习 + 博弈军师解析
        var aiCfg = AIConfig()
        aiCfg.provider = .openAICompatible
        aiCfg.openAIBaseURL = "https://api.deepseek.com/v1"
        aiCfg.openAIModel = "deepseek-chat"
        aiCfg.deepModel = "deepseek-reasoner"
        aiCfg.saveCurrentAsProfile(name: "DeepSeek 通道")
        XCTAssertEqual(aiCfg.profiles.count, 1)
        XCTAssertEqual(aiCfg.resolvedModel(preferDeep: true), "deepseek-reasoner")

        var dna = PersonalStyleDNA()
        AIAutoInsightService.learnFromUserEditDiff(
            aiOriginal: "您好，感谢您的耐心等待，我这边已经完整审阅了您的全部方案并准备好了详细反馈。",
            userFinal: "收到，我看完了～",
            into: &dna
        )
        XCTAssertTrue(dna.learnedDiffRules.contains(where: { $0.contains("简短") }))
        XCTAssertTrue(dna.learnedDiffRules.contains(where: { $0.contains("您好") }))
        XCTAssertTrue(dna.learnedDiffRules.contains(where: { $0.contains("波浪号") }))

        let stratJSON = """
        {"subtext": "对方想临时加需求但不好直说", "options": [{"tag": "🛡️ 温和太极", "toneLabel": "先缓冲", "reply": "收到啦，我先核对下排期～"}]}
        """
        let strat = AIAutoInsightService.parseStrategistResult(stratJSON, fallbackMessage: "周末加个班吧")
        XCTAssertEqual(strat.options.first?.tag, "🛡️ 温和太极")
    }

    func testV5MixedInputToneFilterTemplatesAndFormatting() throws {
        // 1. 动态变量短语渲染
        let fixedDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00 UTC
        let rendered = DynamicTemplateEngine.render("汇报日期 {{日期}} | 引用: {{剪贴板}}", clipboard: "测试进度", now: fixedDate)
        XCTAssertTrue(rendered.contains("引用: 测试进度"))
        XCTAssertFalse(rendered.contains("{{日期}}"))

        // 2. 排版微整形工具箱（盘古空格 / 去空行 / 编号 / 财务大写金额）
        XCTAssertEqual(TextFormatterToolbox.addPanguSpaces("我在iPhone16上用Swift写代码"), "我在 iPhone16 上用 Swift 写代码")
        XCTAssertEqual(TextFormatterToolbox.collapseBlankLines("第一行\n\n  \n第二行\n"), "第一行\n第二行")
        XCTAssertEqual(TextFormatterToolbox.toNumberedList("准备数据\n发布版本"), "1. 准备数据\n2. 发布版本")
        XCTAssertEqual(TextFormatterToolbox.amountToChineseCapital(12800), "壹万贰仟捌佰元整")

        // 3. v 模式财务大写与 AA 均摊
        let vSettings = LingxiSettings()
        let vRmb = SmartCandidateHelper.extraCandidates(forRawInput: "v12800rmb", settings: vSettings, consumedLength: 9)
        XCTAssertTrue(vRmb.contains(where: { $0.word == "壹万贰仟捌佰元整" }))
        let vAA = SmartCandidateHelper.extraCandidates(forRawInput: "v1280/4", settings: vSettings, consumedLength: 7)
        XCTAssertTrue(vAA.contains(where: { $0.word == "人均 ¥320" }))

        // 4. 汉字四声调识别器（妈/麻/马/骂）
        XCTAssertEqual(PinyinToneClassifier.tone(for: "妈"), 1)
        XCTAssertEqual(PinyinToneClassifier.tone(for: "麻"), 2)
        XCTAssertEqual(PinyinToneClassifier.tone(for: "马"), 3)
        XCTAssertEqual(PinyinToneClassifier.tone(for: "骂"), 4)

        // 5. 本地安全保险箱脱敏展示
        let vaultItem = SecureVaultItem(title: "税号", category: "开票", value: "91310000MA1FL8888X")
        XCTAssertTrue(vaultItem.maskedPreview.hasPrefix("91"))
        XCTAssertTrue(vaultItem.maskedPreview.hasSuffix("8X"))
        XCTAssertTrue(vaultItem.maskedPreview.contains("••••"))

        // 6. 中数英无缝混输 + 点击音节单字反查
        guard let dbURL = findTestDBURL() else {
            throw XCTSkip("未找到测试词库 pinyin.sqlite")
        }
        let engine = PinyinEngine(databaseURL: dbURL)
        var settings = LingxiSettings()
        settings.userLearningEnabled = false

        let mixedNum = engine.query(raw: "mingtian3dianjian", settings: settings)
        XCTAssertTrue(mixedNum.candidates.contains(where: { $0.word.contains("3") && $0.word.contains("明天") }), "中数混输应直出含数字的中文短语")

        let mixedEng = engine.query(raw: "fayigepdfgeiwo", settings: settings)
        XCTAssertTrue(mixedEng.candidates.contains(where: { $0.word.contains("PDF") }), "中英混输应识别内嵌英文词 PDF")

        let singleTok = PinyinToken(text: "ni", raw: "ni", kind: .complete, end: 2)
        let singleChars = engine.candidatesForSingleToken(singleTok, isT9: false, settings: settings, limit: 20)
        XCTAssertTrue(singleChars.contains(where: { $0.word == "你" }), "点击单个音节应返回对应高频单字")
    }

    func testV5DualThemeContrastAndApplePasskeyCallback() throws {
        // 1. 全部 12 套精校主题必须满足 WCAG AA 键帽文字可读对比度 (>= 4.5:1)
        XCTAssertEqual(KeyboardThemePreset.presets.count, 12)
        for preset in KeyboardThemePreset.presets {
            let ratio = preset.keyFill.contrastRatio(with: preset.keyText)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "主题 \(preset.name) 键帽对比度不足: \(ratio)")
            let accentRatio = preset.accentFill.contrastRatio(with: preset.accentText)
            XCTAssertGreaterThanOrEqual(accentRatio, 3.0, "主题 \(preset.name) 强调按钮对比度不足: \(accentRatio)")
        }

        // 2. 日夜双套独立自由调色在「跟随系统」模式下互不串色
        var theme = ThemeCustomization()
        theme.appearanceMode = .followSystem
        theme.customCanvasHex = "#E5EEF8"
        theme.customKeyFillHex = "#FFFFFF"
        theme.customKeyTextHex = "#111827"
        let dayPreset = theme.activePreset(isSystemDark: false)
        let nightPreset = theme.activePreset(isSystemDark: true)
        XCTAssertEqual(dayPreset.canvasTop.hex.uppercased(), "#E5EEF8")
        XCTAssertTrue(nightPreset.isDark, "浅色自定义调色绝不能污染深色模式")
        XCTAssertNotEqual(nightPreset.canvasTop.hex.uppercased(), "#E5EEF8")

        // 3. Apple iCloud Passkey 回调 URL 解析校验
        let mockAuthObj: [String: Any] = [
            "userID": "apple-passkey-u1",
            "email": "apple_test@icloud.lingxi.ime",
            "username": "Apple 体验官",
            "accessToken": "lxt.mock.token",
            "refreshToken": "lxr_mock_refresh",
            "accessExpiry": Int(Date().addingTimeInterval(3600).timeIntervalSince1970),
            "e2eeSalt": "0123456789abcdef0123456789abcdef"
        ]
        let rawJSON = try JSONSerialization.data(withJSONObject: mockAuthObj)
        let b64u = rawJSON.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let url = URL(string: "lingxi://auth-callback?payload=\(b64u)")!
        let session = try CloudBackendClient.shared.completeApplePasskeyCallback(url: url)
        XCTAssertEqual(session.userID, "apple-passkey-u1")
        XCTAssertFalse(CloudBackendConfig.load().isLocalOnlyAccount)
        // 清理测试会话避免污染后续测试
        CloudCredentialStore.clearAll()
    }

    func testV51GeoLocationLexiconAndAICoPilotUpgrades() throws {
        // 1. 地名多音字清洗与拼音转换器
        XCTAssertEqual(GeoPinyinConverter.cleanPOIName("临沂万象汇(兰山店)"), "临沂万象汇")
        let mallEntry = try XCTUnwrap(GeoPinyinConverter.makeEntry(word: "临沂万象汇(兰山店)", category: "商圈", boostScore: 12.0))
        XCTAssertEqual(mallEntry.pinyin, "lin'yi'wan'xiang'hui")
        XCTAssertEqual(mallEntry.abbr, "lywxh")
        let cqEntry = try XCTUnwrap(GeoPinyinConverter.makeEntry(word: "重庆北站", category: "交通", boostScore: 12.0))
        XCTAssertEqual(cqEntry.pinyin, "chong'qing'bei'zhan")

        // 2. 实时 GPS / 周边 POI 上下文、vwz/vdz 快捷地址、动态模板与 AI 地域上下文
        let prevGeo = GeoLocationContext.load(force: true)
        defer {
            if prevGeo.isPopulated {
                prevGeo.save()
            } else {
                GeoLocationContext.clear()
            }
        }
        var geo = GeoLocationContext()
        geo.province = "山东省"
        geo.city = "临沂市"
        geo.district = "兰山区"
        geo.street = "北京路"
        geo.formattedAddress = "山东省临沂市兰山区北京路"
        geo.updatedAt = Date()
        geo.pois = [
            GeoPinyinConverter.makeEntry(word: "临沂", category: "城市", boostScore: 15.0),
            GeoPinyinConverter.makeEntry(word: "兰山", category: "区县", boostScore: 13.8),
            GeoPinyinConverter.makeEntry(word: "泰盛广场", category: "商圈", boostScore: 11.5),
            GeoPinyinConverter.makeEntry(word: "临沂北站", category: "交通", boostScore: 11.8),
        ].compactMap { $0 }
        geo.save()

        let settings = LingxiSettings()
        XCTAssertTrue(SmartCandidateHelper.isVToolQuery("vwz", scheme: .quanpin))
        XCTAssertTrue(SmartCandidateHelper.isVToolQuery("vdz", scheme: .quanpin))
        let vwzHits = SmartCandidateHelper.extraCandidates(forRawInput: "vwz", settings: settings, consumedLength: 3)
        XCTAssertTrue(vwzHits.contains(where: { $0.word == "山东省临沂市兰山区北京路" }))
        XCTAssertTrue(vwzHits.contains(where: { $0.word == "山东省临沂市兰山区" }))
        XCTAssertTrue(vwzHits.contains(where: { $0.word == "临沂" }))

        let renderedGeoTpl = DynamicTemplateEngine.render("我现在在{{当前城市}}{{当前区县}}：{{当前位置}}")
        XCTAssertEqual(renderedGeoTpl, "我现在在临沂兰山区：山东省临沂市兰山区北京路")

        let aiGeoPrompt = geo.aiTimeLocationPromptSuffix()
        XCTAssertTrue(aiGeoPrompt.contains("山东省临沂市兰山区"))
        XCTAssertTrue(aiGeoPrompt.contains("泰盛广场"))

        // 3. 全国 6,403 地名内置词库 + 实时周边地标动态提权
        if let dbURL = findTestDBURL() {
            let engine = PinyinEngine(databaseURL: dbURL)
            var testSettings = LingxiSettings()
            testSettings.userLearningEnabled = false
            testSettings.geoLocationBoostEnabled = false

            // 即使关闭 GPS 实时提权，全国重点省市区县也必须直接首选出词
            let builtinChecks: [(String, String)] = [
                ("linyi", "临沂"),
                ("heze", "菏泽"),
                ("feixian", "费县"),
                ("linshu", "临沭"),
                ("chongqing", "重庆"),
                ("bengbu", "蚌埠"),
                ("lu'an", "六安"),
                ("panyu", "番禺"),
                ("xiamen", "厦门"),
            ]
            for (py, expected) in builtinChecks {
                let res = engine.query(raw: py, settings: testSettings)
                XCTAssertEqual(res.candidates.first?.word, expected, "内置地名库 \(py) 应首选 \(expected)")
            }
            // 同音区县（临沂兰山区 vs 日照岚山区）离线双候选均在前两位；开启实时定位至临沂兰山后立刻置顶
            let lanshanOffline = engine.query(raw: "lanshanqu", settings: testSettings).candidates.prefix(2).map(\.word)
            XCTAssertTrue(lanshanOffline.contains("兰山区"), "离线词库 lanshanqu 前两位应包含 兰山区")

            // 开启实时 GPS 位置提权后，当前城市周边特有商圈/缩写应立刻跃升首位
            testSettings.geoLocationBoostEnabled = true
            let localMall = engine.query(raw: "taishengguangchang", settings: testSettings)
            XCTAssertEqual(localMall.candidates.first?.word, "泰盛广场")
            let localMallAbbr = engine.query(raw: "tsgc", settings: testSettings)
            XCTAssertEqual(localMallAbbr.candidates.first?.word, "泰盛广场")
            let localDistrict = engine.query(raw: "lanshan", settings: testSettings)
            XCTAssertEqual(localDistrict.candidates.first?.word, "兰山")
        }

        // 4. @ai / /ai / // 随打随唤内联指令检测器
        let inlineInput = "@ai 帮我委婉拒绝周末加班"
        let inlineMatch = try XCTUnwrap(InlineAICommandDetector.detect(in: inlineInput))
        XCTAssertEqual(inlineMatch.command, "帮我委婉拒绝周末加班")
        XCTAssertEqual(inlineMatch.fullMatchCount, inlineInput.count)

        let slashMatch = try XCTUnwrap(InlineAICommandDetector.detect(in: "前一段话\n// 写一条临沂美食朋友圈"))
        XCTAssertEqual(slashMatch.command, "写一条临沂美食朋友圈")
        XCTAssertNil(InlineAICommandDetector.detect(in: "普通日常聊天内容不包含命令"))

        // 5. AI 最近生成历史缓存 + 20 条场景指令市场 + 顺着续写/纠错技能
        let prevHistory = AIRecentHistoryStore.load()
        defer {
            AIRecentHistoryStore.clear()
            for item in prevHistory.reversed() {
                AIRecentHistoryStore.record(title: item.title, output: item.output)
            }
        }
        AIRecentHistoryStore.clear()
        AIRecentHistoryStore.record(title: "润色", output: "第一条测试输出")
        AIRecentHistoryStore.record(title: "续写", output: "第二条测试输出")
        AIRecentHistoryStore.record(title: "润色重用", output: "第一条测试输出")
        let loadedHistory = AIRecentHistoryStore.load()
        XCTAssertEqual(loadedHistory.count, 2)
        XCTAssertEqual(loadedHistory.first?.output, "第一条测试输出")

        XCTAssertGreaterThanOrEqual(AIPromptMarketplaceCatalog.allTemplates.count, 20)
        XCTAssertGreaterThanOrEqual(AIPromptMarketplaceCatalog.categories.count, 5)
        XCTAssertTrue(AIPresetAction.smartContinue.prefersAppendInsert)
        XCTAssertFalse(AIPresetAction.polish.prefersAppendInsert)
        XCTAssertTrue(AIPresetAction.allCases.contains(.proofread))
    }

    func testV511PinyinStabilityLayoutAndNoHijack() throws {
        // 1. 拼音音节条确定性紧凑排版：2/3/6/10 音节必须严格从 x=0 连续紧贴，绝不横向拉宽乱跑
        let sampleWidths: [Double] = [14, 4, 24, 4, 18, 4, 28, 4, 16]
        let layout = ComposingSyllableLayout.computeHorizontalFrames(itemWidths: sampleWidths, spacing: 0.5)
        XCTAssertEqual(layout.rects.count, sampleWidths.count)
        XCTAssertEqual(layout.rects.first?.x ?? -1, 0.0, accuracy: 0.001)
        for i in 0..<(layout.rects.count - 1) {
            let curEnd = layout.rects[i].x + layout.rects[i].width
            let nextStart = layout.rects[i + 1].x
            XCTAssertGreaterThanOrEqual(nextStart, curEnd, "音节芯片不得重叠")
            XCTAssertEqual(nextStart - curEnd, 0.5, accuracy: 0.001, "音节间距必须恒定 0.5pt，严禁随容器拉伸")
        }
        XCTAssertLessThan(layout.totalWidth, 160.0, "5 音节总宽应保持紧凑自然宽度，绝不拉伸到整屏 366pt")

        // 2. 激活本地位置上下文（临沂/兰山/山东/泰盛广场），验证全拼与 T9 绝不劫持日常短词与前缀
        let prevGeo = GeoLocationContext.load(force: true)
        defer {
            if prevGeo.isPopulated {
                prevGeo.save()
            } else {
                GeoLocationContext.clear()
            }
        }
        var geo = GeoLocationContext()
        geo.province = "山东省"
        geo.city = "临沂市"
        geo.district = "兰山区"
        geo.pois = [
            GeoPinyinConverter.makeEntry(word: "临沂", category: "城市", boostScore: 15.0),
            GeoPinyinConverter.makeEntry(word: "山东", category: "省份", boostScore: 12.2),
            GeoPinyinConverter.makeEntry(word: "兰山", category: "区县", boostScore: 13.8),
            GeoPinyinConverter.makeEntry(word: "泰盛广场", category: "商圈", boostScore: 11.5),
            GeoPinyinConverter.makeEntry(word: "临沂北站", category: "交通", boostScore: 11.8),
        ].compactMap { $0 }
        geo.save()

        guard let dbURL = findTestDBURL() else {
            throw XCTSkip("未找到测试词库 pinyin.sqlite")
        }
        let engine = PinyinEngine(databaseURL: dbURL)
        var settings = LingxiSettings()
        settings.userLearningEnabled = false
        settings.geoLocationBoostEnabled = true

        // 2a. 全拼逐字连打：2字/3字/6字中间态与完整态均稳定输出中文，绝不被 2 字母英文(ok/ai/ui)或地名前缀劫持
        let stepInputs = ["w", "wo", "wox", "woxi", "woxia", "woxian", "woxiang", "woxiangq", "woxiangqu"]
        for s in stepInputs {
            let r = engine.query(raw: s, settings: settings)
            XCTAssertFalse(r.candidates.isEmpty, "中间输入 \(s) 不得为空")
            XCTAssertFalse(r.candidates.first?.word.contains("OK") ?? false)
            XCTAssertFalse(r.candidates.first?.word.contains("AI") ?? false)
        }
        XCTAssertEqual(engine.query(raw: "woxiangqu", settings: settings).candidates.first?.word, "我想去")
        XCTAssertEqual(engine.query(raw: "haokan", settings: settings).candidates.first?.word, "好看")
        XCTAssertFalse(engine.query(raw: "haokxi", settings: settings).candidates.first?.word.contains("OK") ?? false)
        XCTAssertFalse(engine.query(raw: "woshuijiao", settings: settings).candidates.first?.word.contains("UI") ?? false)
        XCTAssertEqual(engine.query(raw: "woshuijiao", settings: settings).candidates.first?.word, "我睡觉")

        // 2b. 3字母拼音 lin 不得被 临沂/临沂北站 抢占首位；完整 linyi 与 4字简拼 tsgc 精准首选
        let linTop = engine.query(raw: "lin", settings: settings).candidates.first?.word ?? ""
        XCTAssertEqual(linTop.count, 1, "单音节 lin 首选应为单字（林/临），不得被临沂前缀劫持")
        XCTAssertEqual(engine.query(raw: "linyi", settings: settings).candidates.first?.word, "临沂")
        XCTAssertEqual(engine.query(raw: "tsgc", settings: settings).candidates.first?.word, "泰盛广场")

        // 2c. 中英数混输依然精准可用且保持多候选
        let pdfRes = engine.query(raw: "fayigepdfgeiwo", settings: settings)
        XCTAssertTrue(pdfRes.candidates.contains(where: { $0.word.contains("PDF") }))
        let numRes = engine.query(raw: "mingtian3dianjian", settings: settings)
        XCTAssertTrue(numRes.candidates.contains(where: { $0.word == "明天3点见" }), "中数混输多候选应包含 明天3点见")
        XCTAssertGreaterThanOrEqual(numRes.candidates.count, 2, "中数混输应保留多个次选避免孤词")

        // 2d. T9 九宫格短数字前缀（546 / 742）绝不被 临沂(54694) / 山东(74263664) 劫持；完整 T9 54694 仍精准出 临沂
        let t9_546 = engine.queryT9(digits: "546", lockedSyllables: [], settings: settings)
        XCTAssertNotEqual(t9_546.candidates.first?.word, "临沂", "T9 三位前缀 546 不得被 临沂 劫持")
        let t9_742 = engine.queryT9(digits: "742", lockedSyllables: [], settings: settings)
        XCTAssertNotEqual(t9_742.candidates.first?.word, "山东", "T9 三位前缀 742 不得被 山东 劫持")
        let t9_linyi = engine.queryT9(digits: "54694", lockedSyllables: [], settings: settings)
        XCTAssertEqual(t9_linyi.candidates.first?.word, "临沂", "T9 完整编码 54694 应精准命中 临沂")
    }
}
