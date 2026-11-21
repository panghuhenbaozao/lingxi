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
            ToolbarItemConfig(buttonID: .emoji, isVisible: false, order: 0),
            ToolbarItemConfig(buttonID: .ai, isVisible: true, order: 1),
        ]
        custom = LingxiSettings.normalizedToolbarLayout(custom)
        XCTAssertEqual(custom.count, ToolbarButtonID.allCases.count)
        XCTAssertEqual(custom.first?.buttonID, .emoji)
        XCTAssertEqual(custom[1].buttonID, .ai)
        XCTAssertFalse(custom[0].isVisible)
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
}
