import CryptoKit
import UIKit
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

    // 打字统计（v5.2 默认开启 + 旧版一次性迁移 + 跨进程热重载 + 活跃时长阈值 + 清除）
    func testTypingStatsStoreAndSettings() {
        // 设置开关：v5.2 默认开启；旧版 JSON（无迁移标记）自动迁移开启；显式关闭后保持关闭
        let defaults = LingxiSettings()
        XCTAssertTrue(defaults.typingStatsEnabled)
        let legacyJSON = Data("{}".utf8)
        let decoded = try? JSONDecoder().decode(LingxiSettings.self, from: legacyJSON)
        XCTAssertNotNil(decoded)
        XCTAssertTrue(decoded?.typingStatsEnabled ?? false)
        let optedOutJSON = Data("{\"typingStatsEnabled\":false,\"typingStatsDefaultMigratedV52\":true}".utf8)
        let optedOut = try? JSONDecoder().decode(LingxiSettings.self, from: optedOutJSON)
        XCTAssertFalse(optedOut?.typingStatsEnabled ?? true)

        // 统计逻辑：字数累加、活跃时长仅在间隔 ≤30s 时计入、另一实例可热重载最新落盘数据
        let store = TypingStatsStore()
        let observerStore = TypingStatsStore()
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
        // 触发立即落盘后，验证另一进程/实例无需重建即可热重载磁盘字数
        store.flush()
        XCTAssertEqual(observerStore.summary(now: base.addingTimeInterval(130)).todayChars, 8)
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
        // v5.8 极简默认：AI/译/截屏识图/语音/表情符号/剪贴板/设置/撤销可见，编辑面板/九键切换默认隐藏
        let expectedVisible: Set<ToolbarButtonID> = [.ai, .translate, .screenshot, .voice, .symbols, .clipboard, .settings, .undo]
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

    func testConcealedPasteboardItemCarriesMarkerAndPlainText() {
        // 纯逻辑测试：不读写系统剪贴板（CI 为无宿主单元测试，系统剪贴板不可依赖）
        let item = ConcealedPasteboard.makeItem("91310000MA1FL0000X")
        XCTAssertEqual(item[ConcealedPasteboard.plainTextType] as? String, "91310000MA1FL0000X", "保险箱复制后仍应能正常粘贴文本")
        XCTAssertNotNil(item[ConcealedPasteboard.concealedType], "保险箱复制必须带 Concealed 标记")
        XCTAssertTrue(ConcealedPasteboard.isConcealed(types: Array(item.keys)))
        XCTAssertFalse(ConcealedPasteboard.isConcealed(types: ["public.utf8-plain-text"]), "普通文本不应被识别为保险箱内容")
        XCTAssertFalse(ConcealedPasteboard.isConcealed(types: []))
    }

    func testToastTextStripsLegacyPrefixesAndClassifiesTone() {
        XCTAssertEqual(LXToastText.clean("✓ 已复制"), "已复制")
        XCTAssertEqual(LXToastText.clean("⚠️ 网络超时"), "网络超时")
        XCTAssertEqual(LXToastText.clean("  已保存  "), "已保存")
        XCTAssertEqual(LXToastText.tone(of: "✓ 已复制"), .success)
        XCTAssertEqual(LXToastText.tone(of: "拉取失败：401"), .error)
        XCTAssertEqual(LXToastText.tone(of: "⚠️ 注意"), .error)
        XCTAssertEqual(LXToastText.tone(of: "剪贴板是空的"), .info)
        XCTAssertEqual(LXToastText.tone(of: "所选技能已存在"), .info)
    }

    func testRelayPairCodeIsNeverTheLegacySharedDefault() {
        // 旧版所有人共用 886699，会互相收到剪贴板内容：新配置必须是随机码，旧码与空码需要迁移
        XCTAssertTrue(ClipboardRelayConfig.needsPrivatePairCode(ClipboardRelayConfig.legacySharedPairCode))
        XCTAssertTrue(ClipboardRelayConfig.needsPrivatePairCode("  "))
        XCTAssertFalse(ClipboardRelayConfig.needsPrivatePairCode("204817"))
        let fresh = ClipboardRelayConfig()
        XCTAssertNotEqual(fresh.pairCode, ClipboardRelayConfig.legacySharedPairCode)
        XCTAssertEqual(fresh.pairCode.count, 6)
        XCTAssertTrue(fresh.pairCode.allSatisfy(\.isNumber))
    }

    func testLexiconTSVParserPreviewMatchesImportRules() {
        // 手机上不方便输入 Tab：逗号 / 全角逗号 / 等号都应转换为 Tab
        XCTAssertEqual(LexiconTSVParser.normalize("mail,me@example.com"), "mail\tme@example.com")
        XCTAssertEqual(LexiconTSVParser.normalize("zjtd，字节跳动"), "zjtd\t字节跳动")
        XCTAssertEqual(LexiconTSVParser.normalize("ling xi=灵犀"), "ling xi\t灵犀")
        // 内容里的逗号不应被拆开：编码部分不是纯字母时保持原样
        XCTAssertEqual(LexiconTSVParser.normalize("你好,世界"), "你好,世界")

        let custom = "# 注释\nmail,me@example.com\nzjtd\t字节跳动\n123\t数字编码无效\n\n只有一列"
        XCTAssertEqual(LexiconTSVParser.validCustomCount(custom), 2)

        let user = "ling xi,灵犀\nshu'ru'fa\t输入法\t5\t1\na b c d e f g h i\t太长\n灵犀"
        XCTAssertEqual(LexiconTSVParser.validUserCount(user), 2)

        XCTAssertTrue(LexiconTSVParser.isValidCode("mail"))
        XCTAssertTrue(LexiconTSVParser.isValidCode("zi jie"))
        XCTAssertFalse(LexiconTSVParser.isValidCode("邮件"))
        XCTAssertFalse(LexiconTSVParser.isValidCode("m@il"))
        XCTAssertFalse(LexiconTSVParser.isValidCode("   "))
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

        // 1. 显式允许离线回退时，离线邮箱注册落入本机加密账号库
        let regSession = try await client.register(
            email: uniqueEmail,
            username: "真机测试号",
            password: "password123",
            allowOfflineFallback: true
        )
        XCTAssertTrue(regSession.userID.hasPrefix("local-"))
        XCTAssertTrue(CloudBackendConfig.load().isLocalOnlyAccount)
        XCTAssertFalse(client.isRealCloudAuthenticated, "离线档案不得伪装为真实云端已登录")
        XCTAssertTrue(client.isLocalOfflineSession)
        XCTAssertEqual(CloudBackendConfig.load().username, "真机测试号")

        // 2. 退出后，错误密码应被拒绝，正确密码在允许离线回退时应成功登录
        await client.signOut()
        XCTAssertFalse(client.isAuthenticatedOrHasAPIKey)

        do {
            _ = try await client.login(account: uniqueEmail, password: "wrong_password", allowOfflineFallback: true)
            XCTFail("错误密码不应允许登录")
        } catch {
            // 预期拦截
        }

        let loginSession = try await client.login(account: uniqueEmail, password: "password123", allowOfflineFallback: true)
        XCTAssertEqual(loginSession.userID, regSession.userID)
        XCTAssertTrue(client.isAuthenticatedOrHasAPIKey)
        XCTAssertTrue(client.isLocalOfflineSession)

        // 3. 一键本机账号创建应立即可用
        await client.signOut()
        let quick = client.createQuickLocalAccount(username: "快速体验")
        XCTAssertTrue(quick.userID.hasPrefix("local-"))
        XCTAssertTrue(client.isLocalOfflineSession)
        XCTAssertFalse(client.isRealCloudAuthenticated)
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

    func testV514ThemeSyncIsolationAndChinaDirectTransport() async throws {
        // 1. 日夜自定义调色严格隔离：浅色自定义底板切到深色主题后，绝不串色污染深色主题
        var theme = ThemeCustomization()
        theme.appearanceMode = .alwaysLight
        theme.customCanvasHex = "#FFF8F0"
        theme.customKeyFillHex = "#FFFFFF"
        theme.appearanceMode = .alwaysDark
        theme.selectedThemeID = "deep_ocean"
        let darkPreset = theme.activePreset(isSystemDark: false)
        XCTAssertTrue(darkPreset.isDark, "深色模式下浅色自定义调色绝不能污染成亮色")
        XCTAssertEqual(darkPreset.canvasTop.hex.uppercased(), "#151C26")

        // 2. App 与键盘统一预设锁定语义：日间选深色皮肤立刻锁定为 .alwaysDark，不论系统怎么切明暗都不乱切颜色
        var synced = ThemeCustomization()
        synced.appearanceMode = .followSystem
        let ocean = KeyboardThemePreset.find(id: "deep_ocean")
        synced.applyPresetSelection(ocean, isSystemDark: false)
        XCTAssertEqual(synced.appearanceMode, .alwaysDark)
        XCTAssertEqual(synced.activePreset(isSystemDark: false).id, "deep_ocean")
        XCTAssertEqual(synced.activePreset(isSystemDark: true).id, "deep_ocean")

        // 3. 同秒连续写盘不应命中陈旧缓存（fileStamp 校验）
        let prevTheme = ThemeCustomization.load(force: true)
        defer { _ = prevTheme.save(notify: false) }
        var t1 = ThemeCustomization()
        t1.applyPresetSelection(KeyboardThemePreset.find(id: "lingxi_light"), isSystemDark: false)
        XCTAssertTrue(t1.save(notify: false))
        var t2 = ThemeCustomization()
        t2.applyPresetSelection(KeyboardThemePreset.find(id: "obsidian_gold"), isSystemDark: false)
        XCTAssertTrue(t2.save(notify: false))
        let reloaded = ThemeCustomization.load(force: false)
        XCTAssertEqual(reloaded.selectedThemeID, "obsidian_gold")
        XCTAssertEqual(reloaded.appearanceMode, .alwaysDark)

        // 4. 中国大陆强制 IPv4 HTTP/1.1 解析器：同时支持 Content-Length 与 Transfer-Encoding: chunked
        let plainRaw = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 15\r\n\r\n{\"status\":\"ok\"}".utf8)
        let parsedPlain = try XCTUnwrap(ChinaDirectIPv4Transport.parseHTTPResponse(plainRaw))
        XCTAssertEqual(parsedPlain.statusCode, 200)
        XCTAssertEqual(String(data: parsedPlain.data, encoding: .utf8), "{\"status\":\"ok\"}")

        let chunkedRaw = Data("HTTP/1.1 201 Created\r\nTransfer-Encoding: chunked\r\n\r\n7\r\n{\"ok\":t\r\n5\r\nrue}\n\r\n0\r\n\r\n".utf8)
        let parsedChunked = try XCTUnwrap(ChinaDirectIPv4Transport.parseHTTPResponse(chunkedRaw))
        XCTAssertEqual(parsedChunked.statusCode, 201)
        XCTAssertEqual(String(data: parsedChunked.data, encoding: .utf8), "{\"ok\":true}\n")

        let builtReq = String(
            data: ChinaDirectIPv4Transport.buildHTTP11Request(
                host: "lingxi-ime.pages.dev",
                method: "POST",
                path: "/api/v1/auth/login",
                headers: ["Content-Type": "application/json"],
                body: Data("{\"a\":1}".utf8)
            ),
            encoding: .utf8
        ) ?? ""
        XCTAssertTrue(builtReq.contains("POST /api/v1/auth/login HTTP/1.1\r\n"))
        XCTAssertTrue(builtReq.contains("Host: lingxi-ime.pages.dev\r\n"))
        XCTAssertTrue(builtReq.contains("Connection: close\r\n"))
        XCTAssertTrue(builtReq.contains("Accept-Encoding: identity\r\n"))
        XCTAssertTrue(builtReq.contains("Content-Length: 7\r\n"))

        // 5. 云端登录默认绝不静默降级成离线假账号；且真云端登录自动把旧版 localNoop 升级为 e2eeCloud
        var cfg = CloudBackendConfig.load()
        let prevURL = cfg.serverBaseURL
        let prevRelay = ClipboardRelayConfig.load()
        cfg.serverBaseURL = "http://127.0.0.1:1"
        cfg.save()
        defer {
            var r = CloudBackendConfig.load()
            r.serverBaseURL = prevURL
            r.save()
            _ = prevRelay.save()
            CloudCredentialStore.clearAll()
        }
        let strictClient = CloudBackendClient(timeout: 2)
        await strictClient.signOut()
        do {
            _ = try await strictClient.register(email: "strict@lingxi.test", username: "严检", password: "password123")
            XCTFail("默认云端注册在网络不可达时应明确抛错，绝不得静默伪造离线账号")
        } catch let err as CloudBackendError {
            if case .networkFailure = err {
                // 预期抛出 networkFailure
            } else {
                XCTFail("期望 networkFailure，实际收到：\(err)")
            }
        }
        XCTAssertFalse(strictClient.isLocalOfflineSession)
        XCTAssertFalse(strictClient.isRealCloudAuthenticated)

        var localRelay = ClipboardRelayConfig()
        localRelay.syncTransportMode = .localNoop
        localRelay.save()
        let mockAuthObj: [String: Any] = [
            "userID": "cloud-u-514",
            "email": "china@lingxi.ime",
            "username": "国内直连用户",
            "accessToken": "lxt.v514.token",
            "refreshToken": "lxr_v514_refresh",
            "accessExpiry": Int(Date().addingTimeInterval(3600).timeIntervalSince1970),
            "e2eeSalt": "0123456789abcdef0123456789abcdef"
        ]
        let b64u = try JSONSerialization.data(withJSONObject: mockAuthObj)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let cbURL = try XCTUnwrap(URL(string: "lingxi://auth-callback?payload=\(b64u)"))
        _ = try strictClient.completeApplePasskeyCallback(url: cbURL)
        XCTAssertTrue(strictClient.isRealCloudAuthenticated)
        XCTAssertFalse(strictClient.isLocalOfflineSession)
        XCTAssertEqual(ClipboardRelayConfig.load().syncTransportMode, .e2eeCloud, "云端真登录后必须自动将旧版 localNoop 升级为 e2eeCloud")

        // 6. workers.dev 带路径或末尾斜杠的旧配置也应自动迁移至 lingxi-ime.pages.dev
        let workersWithPath = Data("{\"serverBaseURL\":\"https://lingxi-cloud.1455952.workers.dev/\"}".utf8)
        let migrated = try JSONDecoder().decode(CloudBackendConfig.self, from: workersWithPath)
        XCTAssertEqual(migrated.normalizedBaseURL, "https://lingxi-ime.pages.dev")
    }

    func testV52AppGroupProvisionParserAndSideloadBridge() throws {
        // 1. 解析 embedded.mobileprovision CMS 二进制包中的 com.apple.security.application-groups
        let plistXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Entitlements</key>
            <dict>
                <key>com.apple.security.application-groups</key>
                <array>
                    <string>group.com.other.app</string>
                    <string>group.com.lingxi.ime.TEAM9988</string>
                </array>
            </dict>
        </dict>
        </plist>
        """
        var cmsWrapped = Data([0x30, 0x82, 0x01, 0x00, 0x06, 0x09])
        cmsWrapped.append(Data(plistXML.utf8))
        cmsWrapped.append(Data([0xA0, 0x82, 0x00, 0x10]))
        let parsedGroups = AppGroup.parseAppGroupsFromMobileProvisionData(cmsWrapped)
        XCTAssertEqual(parsedGroups.first, "group.com.lingxi.ime.TEAM9988", "应优先匹配含 lingxi 的 SideStore App Group")
        XCTAssertEqual(parsedGroups.count, 2)

        // 2. 免费侧载云桥接配对串导出/导入往返 & 敏感剪贴板屏蔽
        let prevCfg = CloudBackendConfig.load()
        defer {
            prevCfg.save()
            CloudCredentialStore.clearAll()
        }
        CloudCredentialStore.clearAll()
        var cloudCfg = CloudBackendConfig()
        cloudCfg.userID = "u-bridge-52"
        cloudCfg.username = "侧载桥接测试"
        cloudCfg.email = "bridge@lingxi.ime"
        cloudCfg.e2eeSalt = "abcdef0123456789abcdef0123456789"
        cloudCfg.isLocalOnlyAccount = false
        cloudCfg.save()
        CloudCredentialStore.saveAPIKey("lx_live_bridge_secret_token_520")

        let token = try XCTUnwrap(SideloadConfigBridge.exportPairingTokenFromMainApp())
        XCTAssertTrue(token.hasPrefix(SideloadConfigBridge.tokenPrefix))
        XCTAssertTrue(ClipboardClassifier.isSensitiveContent(token), "桥接配对串必须被 L1 隐私盾拦截，严禁写入剪贴板历史")

        // 清空本地凭证后模拟键盘端导入配对串
        CloudCredentialStore.clearAll()
        var blankCfg = CloudBackendConfig()
        blankCfg.save()
        XCTAssertTrue(SideloadConfigBridge.importPairingToken(token))
        XCTAssertEqual(CloudCredentialStore.loadAPIKey(), "lx_live_bridge_secret_token_520")
        XCTAssertEqual(CloudBackendConfig.load().userID, "u-bridge-52")
        XCTAssertEqual(CloudBackendConfig.load().e2eeSalt, "abcdef0123456789abcdef0123456789")
        XCTAssertTrue(SideloadConfigBridge.isPairedInThisProcess)
    }

    func testV521AIModelDiscoveryAllPagesShapesFullNamesAndSideloadAIHandoff() throws {
        // 1. Gemini 分页解析（保留 nextPageToken + 100% 保留非对话模型并标注 isChatModel，绝不截断完整 ID / displayName）
        let geminiPage1 = Data("""
        {
          "models": [
            {"name": "models/gemini-2.5-pro-preview-06-05", "displayName": "Gemini 2.5 Pro Preview 06-05", "inputTokenLimit": 1048576, "supportedGenerationMethods": ["generateContent"]},
            {"name": "models/text-embedding-004", "displayName": "Text Embedding 004", "supportedGenerationMethods": ["embedContent"]},
            {"name": "models/imagen-3.0-generate-002", "displayName": "Imagen 3.0", "supportedGenerationMethods": ["predict"]}
          ],
          "nextPageToken": "page_tok_2"
        }
        """.utf8)
        let parsedGemini = AIClient.parseGeminiModelsPage(geminiPage1, includeNonChat: true)
        XCTAssertEqual(parsedGemini.models.count, 3)
        XCTAssertEqual(parsedGemini.nextPageToken, "page_tok_2")
        XCTAssertEqual(parsedGemini.models[0].id, "gemini-2.5-pro-preview-06-05")
        XCTAssertEqual(parsedGemini.models[0].displayName, "Gemini 2.5 Pro Preview 06-05")
        XCTAssertTrue(parsedGemini.models[0].isChatModel)
        XCTAssertFalse(parsedGemini.models[1].isChatModel)
        XCTAssertFalse(parsedGemini.models[2].isChatModel)

        // Gemini 中转站返回 OpenAI {"data":[...]} 格式兜底
        let geminiRelayOpenAI = Data("""
        {"data": [{"id": "gemini-2.5-flash", "name": "Google: Gemini 2.5 Flash", "context_length": 1000000}]}
        """.utf8)
        let parsedGeminiRelay = AIClient.parseGeminiModelsPage(geminiRelayOpenAI, includeNonChat: true)
        XCTAssertEqual(parsedGeminiRelay.models.count, 1)
        XCTAssertEqual(parsedGeminiRelay.models.first?.id, "gemini-2.5-flash")
        XCTAssertEqual(parsedGeminiRelay.models.first?.displayName, "Google: Gemini 2.5 Flash")

        // 2. OpenAI 兼容多形态响应（标准分页 + 超长完整模型名 + displayName + ownedBy + 顶层数组 + 嵌套 data.models + 字符串数组）
        let openAIRich = Data("""
        {
          "data": [
            {
              "id": "Pro/deepseek-ai/DeepSeek-R1-Distill-Qwen-32B",
              "name": "DeepSeek R1 Distill Qwen 32B (Pro)",
              "owned_by": "siliconflow",
              "top_provider": {"context_length": 131072},
              "supported_parameters": ["reasoning"]
            },
            {"id": "BAAI/bge-m3", "owned_by": "BAAI"},
            {"id": "whisper-1", "owned_by": "openai"}
          ],
          "has_more": true,
          "last_id": "whisper-1"
        }
        """.utf8)
        let oPage = AIClient.parseOpenAIModelsPage(openAIRich, includeNonChat: true)
        XCTAssertEqual(oPage.models.count, 3, "拉取远端模型时应保留全部 3 个模型，不可静默丢弃")
        XCTAssertTrue(oPage.hasMore)
        XCTAssertEqual(oPage.lastID, "whisper-1")
        XCTAssertEqual(oPage.models[0].id, "Pro/deepseek-ai/DeepSeek-R1-Distill-Qwen-32B")
        XCTAssertEqual(oPage.models[0].displayName, "DeepSeek R1 Distill Qwen 32B (Pro)")
        XCTAssertEqual(oPage.models[0].ownedBy, "siliconflow")
        XCTAssertEqual(oPage.models[0].contextLength, 131072)
        XCTAssertTrue(oPage.models[0].supportsThinking)
        XCTAssertTrue(oPage.models[0].isChatModel)
        XCTAssertFalse(oPage.models[1].isChatModel)
        XCTAssertFalse(oPage.models[2].isChatModel)

        let topLevelArray = Data("""
        [{"id": "meta-llama/Llama-3.3-70B-Instruct-Turbo", "display_name": "Llama 3.3 70B Instruct Turbo"}]
        """.utf8)
        XCTAssertEqual(AIClient.parseOpenAIModelsPage(topLevelArray, includeNonChat: true).models.first?.displayName, "Llama 3.3 70B Instruct Turbo")

        let nestedDataModels = Data("""
        {"data": {"models": [{"model": "qwen3-235b-a22b", "title": "通义千问 Qwen3-235B"}]}}
        """.utf8)
        let nestedParsed = AIClient.parseOpenAIModelsPage(nestedDataModels, includeNonChat: true)
        XCTAssertEqual(nestedParsed.models.first?.id, "qwen3-235b-a22b")
        XCTAssertEqual(nestedParsed.models.first?.displayName, "通义千问 Qwen3-235B")

        let stringArray = Data("""
        ["gpt-4.1", "o4-mini"]
        """.utf8)
        XCTAssertEqual(AIClient.parseOpenAIModelsPage(stringArray, includeNonChat: true).models.count, 2)

        // 3. 大规模 300 模型完整持久化无截断验证
        let prevAI = AIConfig.load()
        defer { _ = prevAI.save() }
        var bulkCfg = AIConfig()
        bulkCfg.fetchedModels = (1...300).map { i in
            AIModelInfo(
                id: "org-\(i)/very-long-model-name-preview-2026-0\(i % 9 + 1)-v\(i)",
                displayName: "Model Full Display Name #\(i)",
                supportsThinking: i % 3 == 0,
                contextLength: 128_000,
                provider: .openAICompatible,
                isChatModel: i % 10 != 0,
                ownedBy: "provider-\(i % 5)"
            )
        }
        XCTAssertTrue(bulkCfg.save())
        let reloadedBulk = AIConfig.load()
        XCTAssertEqual(reloadedBulk.fetchedModels.count, 300)
        XCTAssertEqual(reloadedBulk.fetchedModels.last?.id, "org-300/very-long-model-name-preview-2026-04-v300")
        XCTAssertEqual(reloadedBulk.fetchedModels.last?.displayName, "Model Full Display Name #300")

        // 4. 免费侧载无云登录状态下也可通过本机直传口令把 AI 密钥/模型同步给键盘 + 键盘权限心跳往返
        let prevCloud = CloudBackendConfig.load()
        defer {
            prevCloud.save()
            CloudCredentialStore.clearAll()
        }
        CloudCredentialStore.clearAll()
        var loggedOut = CloudBackendConfig()
        loggedOut.save()

        var srcAI = AIConfig()
        srcAI.provider = .openAICompatible
        srcAI.openAIBaseURL = "https://openrouter.ai/api/v1"
        srcAI.openAIAPIKey = "sk-or-v1-test-handoff-key-999"
        srcAI.openAIModel = "anthropic/claude-sonnet-4"
        _ = srcAI.save()

        let localToken = try XCTUnwrap(SideloadConfigBridge.exportLocalConfigHandoffTokenFromMainApp())
        XCTAssertTrue(ClipboardClassifier.isSensitiveContent(localToken))

        // 清空本地 AI 配置，模拟键盘端导入
        var emptyAI = AIConfig()
        _ = emptyAI.save()
        XCTAssertFalse(AIConfig.load().isConfigured)
        XCTAssertTrue(SideloadConfigBridge.importPairingToken(localToken))
        let importedAI = AIConfig.load()
        XCTAssertTrue(importedAI.isConfigured)
        XCTAssertEqual(importedAI.openAIAPIKey, "sk-or-v1-test-handoff-key-999")
        XCTAssertEqual(importedAI.openAIModel, "anthropic/claude-sonnet-4")

        XCTAssertTrue(KeyboardPermissionHeartbeat.record(hasFullAccess: true, aiConfigured: true))
        let hb = try XCTUnwrap(KeyboardPermissionHeartbeat.load())
        XCTAssertTrue(hb.hasFullAccess)
        XCTAssertTrue(hb.aiConfigured)
    }

    func testV530VoiceTranslateModesAndToolbarVoiceButton() throws {
        // 1. 实时语音双语互译模式校验（说中文→英语 / 说英语→中文 / 中日互译 / 语音转文字）
        XCTAssertEqual(VoiceTranslateMode.zhToEn.sourceLocaleID, "zh-CN")
        XCTAssertEqual(VoiceTranslateMode.zhToEn.outputSpeechLocaleID, "en-US")
        XCTAssertEqual(VoiceTranslateMode.zhToEn.flipped, .enToZh)

        XCTAssertEqual(VoiceTranslateMode.enToZh.sourceLocaleID, "en-US")
        XCTAssertEqual(VoiceTranslateMode.enToZh.outputSpeechLocaleID, "zh-CN")
        XCTAssertEqual(VoiceTranslateMode.enToZh.flipped, .zhToEn)

        XCTAssertEqual(VoiceTranslateMode.zhToJa.sourceLocaleID, "zh-CN")
        XCTAssertEqual(VoiceTranslateMode.zhToJa.outputSpeechLocaleID, "ja-JP")
        XCTAssertEqual(VoiceTranslateMode.zhToJa.flipped, .jaToZh)
        XCTAssertEqual(VoiceTranslateMode.jaToZh.sourceLocaleID, "ja-JP")

        for mode in VoiceTranslateMode.allCases {
            XCTAssertFalse(mode.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertEqual(mode.flipped.flipped, mode, "双击翻转语种必须严格对称还原")
        }
        XCTAssertTrue(VoiceTranslateMode.zhToEn.isTranslationMode)
        XCTAssertTrue(VoiceTranslateMode.enToZh.isTranslationMode)
        XCTAssertFalse(VoiceTranslateMode.zhDictation.isTranslationMode)
        XCTAssertFalse(VoiceTranslateMode.enDictation.isTranslationMode)

        // 2. 键盘顶栏新增语音同传主入口按钮
        XCTAssertTrue(ToolbarButtonID.voice.isPrimaryLeftAction)
        XCTAssertTrue(defaultToolbarLayout.contains(where: { $0.buttonID == .voice && $0.isVisible }))
    }

    func testV540FollowSystemNoPurpleThemeBleedAndAIHistoryPromptPersistence() throws {
        // 1. 曾经预览过赛博极光（紫）后切回纯白并选「跟随系统」：夜间搭档必须自动重置为苹果原生暗（绝不在抖音/暗色 App 里突然变紫）
        var theme = ThemeCustomization()
        theme.applyPresetSelection(KeyboardThemePreset.find(id: "cyber_neon"), isSystemDark: false)
        XCTAssertEqual(theme.darkThemeID, "cyber_neon")

        theme.applyPresetSelection(KeyboardThemePreset.find(id: "lingxi_pure"), isSystemDark: false)
        XCTAssertEqual(theme.lightThemeID, "lingxi_pure")
        XCTAssertEqual(theme.darkThemeID, "midnight_geek", "切回纯白浅色主题后应自动清除遗留赛博紫搭档")

        // 即使旧存档里残留 darkThemeID = cyber_neon，点击「跟随系统」也必须净化回苹果原生暗
        var legacyStale = ThemeCustomization()
        legacyStale.selectedThemeID = "lingxi_pure"
        legacyStale.lightThemeID = "lingxi_pure"
        legacyStale.darkThemeID = "cyber_neon"
        legacyStale.applyAppearanceMode(.followSystem)
        XCTAssertEqual(legacyStale.activePreset(isSystemDark: false).id, "lingxi_pure")
        XCTAssertEqual(legacyStale.activePreset(isSystemDark: true).id, "midnight_geek")

        // 2. AI 历史记录支持保存提问原文与回答正文，支持最多 30 条与单条删除
        let prevHistory = AIRecentHistoryStore.load()
        defer {
            AIRecentHistoryStore.clear()
            for item in prevHistory.reversed() {
                AIRecentHistoryStore.record(title: item.title, output: item.output, prompt: item.prompt)
            }
        }
        AIRecentHistoryStore.clear()
        AIRecentHistoryStore.record(title: "润色", output: "今晚七点老地方见，不见不散！", prompt: "晚上7点老地方见")
        let loaded = AIRecentHistoryStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.prompt, "晚上7点老地方见")
        XCTAssertEqual(loaded.first?.output, "今晚七点老地方见，不见不散！")

        // 旧版 JSON（无 prompt 字段）应向后兼容解码
        let legacyItemJSON = Data("{\"id\":\"old-1\",\"title\":\"译英\",\"output\":\"Hello world\",\"createdAt\":0}".utf8)
        let decodedLegacy = try JSONDecoder().decode(AIRecentResultItem.self, from: legacyItemJSON)
        XCTAssertEqual(decodedLegacy.prompt, "")
        XCTAssertEqual(decodedLegacy.output, "Hello world")
    }

    func testV542AntiSwallowAfterSendAndExternalTextDidChange() {
        // 1. 微信/QQ/抖音点击「发送」后 0.35s–1.4s 宿主异步清空输入框触发 textDidChange，
        //    用户已开始打下一句拼音时绝不可清空 rawComposing（根治点发送后莫名吞字）
        XCTAssertFalse(
            InputStabilityGuard.shouldClearComposingOnTextDidChange(
                hasRawComposing: true,
                hasEnglishComposing: false,
                hasActiveMarkedText: false,
                hostFieldChanged: false,
                secondsSinceLastInternalEdit: 0.35,
                secondsSinceLastKeystroke: 0.12,
                secondsSinceLastReturn: 0.35
            ),
            "点完发送 0.35s 内的宿主异步 textDidChange 绝不可吞掉用户新打的拼音"
        )
        XCTAssertFalse(
            InputStabilityGuard.shouldClearComposingOnTextDidChange(
                hasRawComposing: true,
                hasEnglishComposing: false,
                hasActiveMarkedText: false,
                hostFieldChanged: false,
                secondsSinceLastInternalEdit: 0.90,
                secondsSinceLastKeystroke: 0.25,
                secondsSinceLastReturn: 0.90
            ),
            "连续输入下一句期间（即使距上次 internalEdit 已超 0.45s）绝不可清空本地拼音"
        )
        // 2. 默认关闭内嵌拼音（hasActiveMarkedText == false）时，同一输入框即使静默 5 秒收到新群消息触发 textDidChange，也不应吞掉本地拼音
        XCTAssertFalse(
            InputStabilityGuard.shouldClearComposingOnTextDidChange(
                hasRawComposing: true,
                hasEnglishComposing: false,
                hasActiveMarkedText: false,
                hostFieldChanged: false,
                secondsSinceLastInternalEdit: 5.0,
                secondsSinceLastKeystroke: 5.0,
                secondsSinceLastReturn: 5.0
            ),
            "未写入宿主 markedText 的本地拼音缓冲绝不因同一输入框异步刷新被抹除"
        )
        // 3. 真正切换到另一个不同类型的输入框（如聊天框 -> 搜索框/密码框）时，应当清理旧组合态
        XCTAssertTrue(
            InputStabilityGuard.shouldClearComposingOnTextDidChange(
                hasRawComposing: true,
                hasEnglishComposing: false,
                hasActiveMarkedText: false,
                hostFieldChanged: true,
                secondsSinceLastInternalEdit: 0.1,
                secondsSinceLastKeystroke: 0.1,
                secondsSinceLastReturn: 0.1
            ),
            "切换到不同类型输入框应清理旧拼音缓冲"
        )
        // 4. 开启内嵌拼音（hasActiveMarkedText == true）且完全闲置超过所有保护窗后，允许同步清理失效 markedText
        XCTAssertTrue(
            InputStabilityGuard.shouldClearComposingOnTextDidChange(
                hasRawComposing: true,
                hasEnglishComposing: false,
                hasActiveMarkedText: true,
                hostFieldChanged: false,
                secondsSinceLastInternalEdit: 3.0,
                secondsSinceLastKeystroke: 3.0,
                secondsSinceLastReturn: 3.0
            )
        )
        // 5. 英文候选替换安全退格校验：宿主发送清空后 documentBeforeInput 为空，绝不能执行盲目 deleteBackward
        XCTAssertEqual(
            InputStabilityGuard.safeEnglishReplacementDeleteLength(expectedPrefix: "hel", documentBeforeInput: "Say hel"),
            3
        )
        XCTAssertEqual(
            InputStabilityGuard.safeEnglishReplacementDeleteLength(expectedPrefix: "Hel", documentBeforeInput: "say hel"),
            3
        )
        XCTAssertEqual(
            InputStabilityGuard.safeEnglishReplacementDeleteLength(expectedPrefix: "hel", documentBeforeInput: ""),
            0,
            "宿主已清空输入框时安全退格长度必须为 0，避免吞字"
        )
        XCTAssertEqual(
            InputStabilityGuard.safeEnglishReplacementDeleteLength(expectedPrefix: "hel", documentBeforeInput: "world"),
            0,
            "宿主光标前文本不以预期前缀结尾时绝不误删"
        )
        // 6. 英文直输模式 textDidChange 失同步判定：宿主还以该前缀结尾时保留，宿主已清空且过静默窗后清理
        XCTAssertFalse(
            InputStabilityGuard.shouldClearEnglishComposingOnTextDidChange(
                englishComposing: "hel",
                documentBeforeInput: "hel",
                hostFieldChanged: false,
                secondsSinceLastInternalEdit: 1.0,
                secondsSinceLastKeystroke: 1.0,
                secondsSinceLastReturn: 5.0
            )
        )
        XCTAssertTrue(
            InputStabilityGuard.shouldClearEnglishComposingOnTextDidChange(
                englishComposing: "hel",
                documentBeforeInput: "",
                hostFieldChanged: false,
                secondsSinceLastInternalEdit: 1.0,
                secondsSinceLastKeystroke: 1.0,
                secondsSinceLastReturn: 5.0
            )
        )
    }

    func testV550AITextSanitizerAndScreenshotVisionConfig() throws {
        // 1. 彻底清除 AI 输出中的 * / ** / ### / ``` / --- / > 等 Markdown 符号
        let messyAI = """
        ### 回复建议
        **太好了！**我们今晚 *七点半* 老地方见，别忘带 `身份证`。
        * 方案一：**先吃饭再看电影**
        - 方案二：直接去江边散步
        ---
        > 算式核对：2*3=6，5 * 8 = 40
        """
        let clean = AITextSanitizer.clean(messyAI, streaming: false)
        XCTAssertFalse(clean.contains("**"), "不应残留 ** 粗体符号")
        XCTAssertFalse(clean.contains("###"), "不应残留 ### 标题符号")
        XCTAssertFalse(clean.contains("`"), "不应残留反引号")
        XCTAssertFalse(clean.contains("---"), "不应残留分割线")
        XCTAssertTrue(clean.contains("太好了！我们今晚 七点半 老地方见"))
        XCTAssertTrue(clean.contains("• 方案一：先吃饭再看电影"))
        XCTAssertTrue(clean.contains("• 方案二：直接去江边散步"))
        XCTAssertTrue(clean.contains("2*3=6"), "正常数学乘号 2*3=6 必须保留")
        XCTAssertTrue(clean.contains("5 * 8 = 40"), "正常数学算式 5 * 8 必须保留")

        // 流式尾部未闭合的 ** 或 * 不得泄漏到界面
        let streamPartial = AITextSanitizer.clean("你好，这是**重点内容", streaming: true)
        XCTAssertFalse(streamPartial.contains("*"))
        XCTAssertEqual(streamPartial, "你好，这是重点内容")

        // 2. AIClient.mergeSystem 自动注入禁止 Markdown 的格式约束
        let merged = AIClient.mergeSystem(base: "测试提示词", config: AIConfig())
        XCTAssertTrue(merged.contains("严禁使用任何 Markdown 语法"))

        // 3. 截屏识图顶栏按钮与上传后自动删图设置默认开启 + 向后兼容解码
        XCTAssertTrue(ToolbarButtonID.screenshot.isPrimaryLeftAction)
        XCTAssertTrue(defaultToolbarLayout.contains(where: { $0.buttonID == .screenshot && $0.isVisible }))
        XCTAssertTrue(LingxiSettings().autoDeleteUploadedScreenshot)
        let legacySettings = try JSONDecoder().decode(LingxiSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(legacySettings.autoDeleteUploadedScreenshot)
        XCTAssertGreaterThanOrEqual(ScreenshotVisionPreset.allCases.count, 5)
        for p in ScreenshotVisionPreset.allCases {
            XCTAssertFalse(p.promptText.isEmpty)
            XCTAssertFalse(p.systemInstruction.isEmpty)
        }
    }

    func testV560VoiceIPCBridgeAutoScreenshotAndUModeDisplay() throws {
        // 1. VoiceIPCCommand / VoiceIPCState 编解码与心跳保鲜校验
        let cmd = VoiceIPCCommand(action: .start, modeRaw: VoiceTranslateMode.zhToEn.rawValue)
        let cmdData = try JSONEncoder().encode(cmd)
        let decodedCmd = try JSONDecoder().decode(VoiceIPCCommand.self, from: cmdData)
        XCTAssertEqual(decodedCmd.action, .start)
        XCTAssertEqual(decodedCmd.modeRaw, VoiceTranslateMode.zhToEn.rawValue)

        var st = VoiceIPCState(
            engineWarm: true,
            isRecording: true,
            isTranslating: false,
            modeRaw: VoiceTranslateMode.enToZh.rawValue,
            transcript: "Hello world",
            translatedText: "你好世界",
            audioLevel: 0.42,
            statusText: "录音中",
            updatedAt: Date().timeIntervalSince1970
        )
        XCTAssertTrue(st.isHeartbeatFresh)
        st.updatedAt = Date().timeIntervalSince1970 - 30.0
        XCTAssertFalse(st.isHeartbeatFresh, "超时心跳应判定为后台语音引擎已休眠")

        // 2. 自动直弹截屏开关默认关闭（改为温和顶栏轻提示，绝不劫持日常截屏/乱弹删图框）且旧版 JSON 向后兼容
        XCTAssertFalse(LingxiSettings().autoAnalyzeNewScreenshot)
        let legacy = try JSONDecoder().decode(LingxiSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.autoAnalyzeNewScreenshot)

        // 3. 点按 u 键：queryUMode("u") 必须返回可读 displayBuffer，不丢失字母反馈
        let eng = PinyinEngine()
        let singleU = eng.queryUMode(raw: "u", limit: 12)
        XCTAssertFalse(singleU.displayBuffer.isEmpty, "单敲 u 必须返回清晰提示与字母回显")
        XCTAssertTrue(singleU.displayBuffer.hasPrefix("u"))
    }

    func testV561ScreenshotOCRVisionModelDetection() {
        // 原生视觉多模态模型应返回 true
        XCTAssertTrue(ScreenshotOCRService.modelLikelySupportsVision(modelID: "gemini-2.5-flash", provider: .gemini))
        XCTAssertTrue(ScreenshotOCRService.modelLikelySupportsVision(modelID: "gpt-4o-mini", provider: .openAICompatible))
        XCTAssertTrue(ScreenshotOCRService.modelLikelySupportsVision(modelID: "claude-sonnet-4-20250514", provider: .openAICompatible))
        XCTAssertTrue(ScreenshotOCRService.modelLikelySupportsVision(modelID: "qwen2.5-vl-72b-instruct", provider: .openAICompatible))
        XCTAssertTrue(ScreenshotOCRService.modelLikelySupportsVision(modelID: "glm-4v-flash", provider: .openAICompatible))
        XCTAssertTrue(ScreenshotOCRService.modelLikelySupportsVision(modelID: "doubao-1-5-vision-pro", provider: .openAICompatible))

        // 纯文本模型（如 DeepSeek）应返回 false，自动走端侧 Apple Vision OCR → 文本 LLM 链路
        XCTAssertFalse(ScreenshotOCRService.modelLikelySupportsVision(modelID: "deepseek-chat", provider: .openAICompatible))
        XCTAssertFalse(ScreenshotOCRService.modelLikelySupportsVision(modelID: "deepseek-reasoner", provider: .openAICompatible))
        XCTAssertFalse(ScreenshotOCRService.modelLikelySupportsVision(modelID: "qwen-plus", provider: .openAICompatible))
        XCTAssertFalse(ScreenshotOCRService.modelLikelySupportsVision(modelID: "glm-4-flash", provider: .openAICompatible))
    }

    func testV562VoiceIPCCommandDeduplicationAndLegacyDecode() throws {
        // 1. 新版 VoiceIPCCommand 携带唯一 requestID，VoiceIPCState 回传 lastCommandID 防止双通道重复 start
        let cmd = VoiceIPCCommand(action: .start, modeRaw: VoiceTranslateMode.enToZh.rawValue, requestID: "req-abc-123")
        let encoded = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(VoiceIPCCommand.self, from: encoded)
        XCTAssertEqual(decoded.requestID, "req-abc-123")
        XCTAssertEqual(decoded.action, .start)

        // 2. 向后兼容旧版无 requestID / lastCommandID 的 JSON
        let legacyCmdJSON = Data("{\"action\":\"stop\",\"modeRaw\":\"zhToEn\"}".utf8)
        let legacyCmd = try JSONDecoder().decode(VoiceIPCCommand.self, from: legacyCmdJSON)
        XCTAssertEqual(legacyCmd.action, .stop)
        XCTAssertFalse(legacyCmd.requestID.isEmpty)

        let legacyStateJSON = Data("{\"engineWarm\":true,\"isRecording\":false}".utf8)
        let legacyState = try JSONDecoder().decode(VoiceIPCState.self, from: legacyStateJSON)
        XCTAssertTrue(legacyState.engineWarm)
        XCTAssertEqual(legacyState.lastCommandID, "")
    }

    func testV570AudioWAVEncoderAndPCMConversion() {
        // 构造 4 个 16-bit Little-Endian 采样: 0, 16384 (+0.5), -16384 (-0.5), 32767 (~+1.0)
        var pcm = Data()
        for v: Int16 in [0, 16384, -16384, 32767] {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { pcm.append(contentsOf: $0) }
        }
        let wav = AudioWAVEncoder.encodePCM16MonoToWAV(pcm16Data: pcm, sampleRate: 16_000)
        XCTAssertEqual(wav.count, 44 + pcm.count)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: wav.subdata(in: 36..<40), encoding: .ascii), "data")

        let floats = AudioWAVEncoder.pcm16ToFloat32Samples(pcm)
        XCTAssertEqual(floats.count, 4)
        XCTAssertEqual(floats[0], 0.0, accuracy: 0.0001)
        XCTAssertEqual(floats[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(floats[2], -0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(floats[3], 0.999)
    }

    func testV580FullUnicodeCoverageZeroTruncAndNaturalTypingFeel() throws {
        guard let dbURL = findTestDBURL() else {
            throw XCTSkip("未找到测试词库 pinyin.sqlite")
        }
        let engine = PinyinEngine(databaseURL: dbURL)
        var settings = LingxiSettings()
        settings.userLearningEnabled = false
        settings.geoLocationBoostEnabled = false

        // 1. 全字库无截断检索：高频拥挤音节（yi/xuan/kun/rong/miao/zhe）与 Unicode 扩展生僻字（幵/龘/並/亂）100% 可打
        let yiWords = Set(engine.query(raw: "yi", settings: settings).candidates.map(\.word))
        for expectedYi in ["一", "衣", "祎", "翊", "熠", "懿", "肄", "劓", "壹", "薏"] {
            XCTAssertTrue(yiWords.contains(expectedYi), "单音节 yi 应完整包含汉字 \(expectedYi)，不得被候选上限截断")
        }
        XCTAssertGreaterThanOrEqual(yiWords.filter { $0.count == 1 }.count, 140, "yi 应返回全部规范字与扩展生僻字")

        let rareChecks: [(String, String)] = [
            ("xuan", "煊"),
            ("kun", "堃"),
            ("rong", "镕"),
            ("miao", "淼"),
            ("zhe", "喆"),
            ("jian", "幵"),
            ("da", "龘"),
            ("bing", "並"),
        ]
        for (py, ch) in rareChecks {
            let words = Set(engine.query(raw: py, settings: settings).candidates.map(\.word))
            XCTAssertTrue(words.contains(ch), "全拼 \(py) 必须能打出汉字 \(ch)")
        }

        // 2. 九宫格 T9 无截断校验：此前因 LIMIT 1200 丢失的 W/X/Y/Z 单字（煊/瑄/壹/薏/栀/祉）与扩展字全部恢复
        let t9XuanWords = Set(engine.queryT9(digits: "9826", lockedSyllables: [], settings: settings).candidates.map(\.word))
        XCTAssertTrue(t9XuanWords.contains("煊"), "T9 九宫格 9826(xuan) 必须包含 煊")
        XCTAssertTrue(t9XuanWords.contains("瑄"), "T9 九宫格 9826(xuan) 必须包含 瑄")

        let t9YiWords = Set(engine.queryT9(digits: "94", lockedSyllables: [], settings: settings).candidates.map(\.word))
        for ch in ["壹", "薏", "祎", "翊"] {
            XCTAssertTrue(t9YiWords.contains(ch), "T9 九宫格 94(yi) 必须包含 \(ch)，不得被简拼双字词淹没")
        }
        let t9ZhiWords = Set(engine.queryT9(digits: "944", lockedSyllables: [], settings: settings).candidates.map(\.word))
        for ch in ["栀", "祉", "痔", "栉"] {
            XCTAssertTrue(t9ZhiWords.contains(ch), "T9 九宫格 944(zhi) 必须包含 \(ch)，不得被简拼三字词淹没")
        }
        let t9DaWords = Set(engine.queryT9(digits: "32", lockedSyllables: [], settings: settings).candidates.map(\.word))
        XCTAssertTrue(t9DaWords.contains("龘"), "T9 九宫格 32(da) 必须能打出 龘")

        // 3. 现代口语热词补充词包（全拼、简拼、九宫格同步生效）
        XCTAssertEqual(engine.query(raw: "aduiduidui", settings: settings).candidates.first?.word, "啊对对对")
        XCTAssertTrue(engine.query(raw: "addd", settings: settings).candidates.prefix(3).contains(where: { $0.word == "啊对对对" }))
        XCTAssertEqual(engine.query(raw: "yiduluanhui", settings: settings).candidates.first?.word, "已读乱回")
        XCTAssertEqual(engine.query(raw: "jushenzhineng", settings: settings).candidates.first?.word, "具身智能")

        // 4. 自然打字手感：正常多词短语绝不被邻键纠错劫持，而真实错拼依然精准纠正
        let naturalPhrases: [(String, String)] = [
            ("tashuo", "他说"),
            ("quna", "去哪"),
            ("woxiangquchifan", "我想去吃饭"),
        ]
        for (raw, expected) in naturalPhrases {
            let res = engine.query(raw: raw, settings: settings)
            XCTAssertNil(res.correctedHint, "正常合法短语 \(raw) 不得被误判为错拼")
            XCTAssertEqual(res.candidates.first?.word, expected, "\(raw) 首选应保持 \(expected)")
        }

        XCTAssertEqual(engine.query(raw: "meiyuo", settings: settings).candidates.first?.word, "没有")
        XCTAssertEqual(engine.query(raw: "shengme", settings: settings).candidates.first?.word, "什么")
        XCTAssertEqual(engine.query(raw: "mihao", settings: settings).candidates.first?.word, "你好")
        XCTAssertEqual(engine.query(raw: "zidao", settings: settings).candidates.first?.word, "知道")

        // 5. 简拼动态热区集合：首字母后必须包含全部合法声母，杜绝 nh/wm/zd 简拼漂移到元音键
        let seg = PinyinSegmenter()
        XCTAssertTrue(seg.validNextLetters(for: "n", scheme: .quanpin).contains("h"))
        XCTAssertTrue(seg.validNextLetters(for: "w", scheme: .quanpin).contains("m"))
        XCTAssertTrue(seg.validNextLetters(for: "z", scheme: .quanpin).contains("d"))

        // 6. 顶栏新增表情符号入口及旧版配置向后兼容
        XCTAssertTrue(ToolbarButtonID.allCases.contains(.symbols))
        let legacyDecoded = try JSONDecoder().decode(LingxiSettings.self, from: Data("{\"toolbarLayout\":[{\"buttonID\":\"ai\",\"isVisible\":true,\"order\":0}]}".utf8))
        XCTAssertTrue(legacyDecoded.toolbarLayout.contains(where: { $0.buttonID == .symbols && $0.isVisible }))

        // 7. v5.8.1 关键修复：多音长读音前缀绝不遮蔽短读音精确字（「这」zhe vs zhei、「嗯」en vs eng、「称」chen vs cheng）
        XCTAssertEqual(engine.query(raw: "zhe", settings: settings).candidates.first?.word, "这", "zhe 首选必须是 这，不得被 zhei 前缀遮蔽沉底")
        XCTAssertEqual(engine.queryT9(digits: "943", lockedSyllables: [], settings: settings).candidates.first?.word, "这", "九宫格 943(zhe) 首选必须是 这")
        XCTAssertEqual(engine.query(raw: "en", settings: settings).candidates.first?.word, "嗯", "en 首选必须是 嗯，不得被 eng 遮蔽")
        let chenTop16 = engine.query(raw: "chen", settings: settings).candidates.prefix(16).map(\.word)
        XCTAssertTrue(chenTop16.contains("称"), "chen 前排精确候选必须包含多音字 称（不得被 cheng 挤到生僻字之后）")

        // 8. 单音节平翘舌温和兜底：未开模糊音打 ze 时前 6 位也应给出「这」，打 si 给出「是」
        let zeTop6 = engine.query(raw: "ze", settings: settings).candidates.prefix(6).map(\.word)
        XCTAssertEqual(zeTop6.first, "则")
        XCTAssertTrue(zeTop6.contains("这"), "单音节 ze 应温和兜底提供 这")
        let siTop6 = engine.query(raw: "si", settings: settings).candidates.prefix(6).map(\.word)
        XCTAssertTrue(siTop6.contains("是"), "单音节 si 应温和兜底提供 是")

        // 9. 长句/多字输入下的首屏单字直出与大池单字保底（打很多字也能立刻在前 8 位点到首音节单字，且展开单字池 >= 30 字）
        for (longRaw, expectedFirstSingle) in [
            ("zheli", "这"),
            ("zhelidedongxi", "这"),
            ("woxiangquchifanzuijintianqizhenhao", "我"),
            ("yiqiqukankanba", "一"),
        ] {
            let longRes = engine.query(raw: longRaw, settings: settings)
            let firstScreenSingles = longRes.candidates.prefix(8).filter { $0.word.count == 1 }.map(\.word)
            XCTAssertTrue(firstScreenSingles.contains(expectedFirstSingle), "长输入 \(longRaw) 首屏前 8 项必须直接包含单字 \(expectedFirstSingle)")
        }
        let yiLongSingles = engine.query(raw: "yiqiqukankanba", settings: settings).candidates.filter { $0.word.count == 1 }
        XCTAssertGreaterThanOrEqual(yiLongSingles.count, 80, "长句输入下首音节展开单字池应完整保留 80+ 单字")
    }

    func testV59SecurityHardeningAndAIV4Upgrades() throws {
        // 1. 隐私剪贴板防泄漏策略（纯函数，不触碰 UIPasteboard.general）
        XCTAssertFalse(
            ConcealedPasteboard.shouldAllowPassiveRead(types: [ConcealedPasteboard.concealedType], text: "普通内容"),
            "带 ConcealedType 标记的剪贴板绝不得被被动读取"
        )
        XCTAssertFalse(
            ConcealedPasteboard.shouldAllowPassiveRead(types: ["public.utf8-plain-text"], text: "LXBRIDGE1:abc123"),
            "侧载桥接令牌绝不得被被动读入键盘历史或发给 AI"
        )
        XCTAssertFalse(
            ConcealedPasteboard.shouldAllowPassiveRead(types: ["public.utf8-plain-text"], text: "身份证 11010519900307281X"),
            "含敏感证件号文本应被被动读取拦截"
        )
        XCTAssertTrue(
            ConcealedPasteboard.shouldAllowPassiveRead(types: ["public.utf8-plain-text"], text: "明天下午三点会议室见"),
            "普通聊天文本应允许读取"
        )

        // 2. 本地保险箱 AES-256-GCM 静态加密（LXV1）+ 篡改拦截 + 旧明文迁移兼容
        let vaultKey = SymmetricKey(size: .bits256)
        let wrongKey = SymmetricKey(size: .bits256)
        let sampleItems = [
            SecureVaultItem(title: "开票税号", category: "开票", value: "91310000MA1FL8888X"),
            SecureVaultItem(title: "公司地址", category: "地址", value: "上海市浦东新区张江路 88 号"),
        ]
        let sealedVault = try SecureSnippetVault.sealItems(sampleItems, key: vaultKey)
        XCTAssertTrue(sealedVault.starts(with: Data("LXV1".utf8)), "加密保险箱应带 LXV1 魔数头")
        XCTAssertFalse(String(decoding: sealedVault, as: UTF8.self).contains("91310000MA1FL8888X"), "密文落盘不得泄露明文税号")
        let reopened = try SecureSnippetVault.openItems(sealedVault, key: vaultKey)
        XCTAssertEqual(reopened, sampleItems)
        XCTAssertThrowsError(try SecureSnippetVault.openItems(sealedVault, key: wrongKey), "错误密钥必须解密失败")
        var tampered = sealedVault
        tampered[tampered.count - 1] ^= 0xFF
        XCTAssertThrowsError(try SecureSnippetVault.openItems(tampered, key: vaultKey), "密文被篡改后必须认证失败")
        let legacyPlain = try JSONEncoder().encode(sampleItems)
        let migrated = try SecureSnippetVault.openItems(legacyPlain, key: vaultKey)
        XCTAssertEqual(migrated, sampleItems, "旧版明文保险箱 JSON 应无缝兼容解码")

        // 3. 零知识 E2EE 端侧 PBKDF2 主密钥派生
        let zk1 = try XCTUnwrap(CloudCredentialStore.deriveClientMasterSecret(password: "Passw0rd!2026", salt: "salt-a", rounds: 5_000))
        let zk2 = try XCTUnwrap(CloudCredentialStore.deriveClientMasterSecret(password: "Passw0rd!2026", salt: "salt-a", rounds: 5_000))
        let zkDiffPwd = try XCTUnwrap(CloudCredentialStore.deriveClientMasterSecret(password: "OtherPass!2026", salt: "salt-a", rounds: 5_000))
        let zkDiffSalt = try XCTUnwrap(CloudCredentialStore.deriveClientMasterSecret(password: "Passw0rd!2026", salt: "salt-b", rounds: 5_000))
        XCTAssertEqual(zk1.count, 32)
        XCTAssertEqual(zk1, zk2)
        XCTAssertNotEqual(zk1, zkDiffPwd)
        XCTAssertNotEqual(zk1, zkDiffSalt)

        // 4. AIConfig v4：多渠道档案不覆盖 + 四路模型路由 + 键盘技能排布 + 技能包 JSON 往返
        var cfg = AIConfig()
        XCTAssertEqual(cfg.geminiModel, GeminiModelOption.flash25.rawValue)
        cfg.provider = .openAICompatible
        cfg.openAIBaseURL = "https://api.deepseek.com/v1"
        cfg.openAIModel = "deepseek-chat"
        cfg.fastModel = "deepseek-chat"
        cfg.deepModel = "deepseek-reasoner"
        cfg.visionModel = "gpt-4o"
        cfg.sttModel = "whisper-large-v3"
        cfg.customHeaders = ["HTTP-Referer": "https://lingxi.ime"]
        cfg.saveCurrentAsProfile(name: "DeepSeek 主力", createNew: true)

        cfg.openAIBaseURL = "https://openrouter.ai/api/v1"
        cfg.openAIModel = "google/gemini-2.5-flash"
        cfg.visionModel = "google/gemini-2.5-flash"
        cfg.customHeaders = ["X-Title": "Lingxi"]
        cfg.saveCurrentAsProfile(name: "OpenRouter 备用", createNew: true)
        XCTAssertEqual(cfg.profiles.count, 2, "createNew: true 必须新增档案而非覆盖原档案")
        let openRouterProfile = try XCTUnwrap(cfg.profiles.first(where: { $0.name == "OpenRouter 备用" }))
        let deepSeekProfile = try XCTUnwrap(cfg.profiles.first(where: { $0.name == "DeepSeek 主力" }))
        XCTAssertEqual(cfg.profiles.first?.id, openRouterProfile.id, "最新保存的渠道档案应置顶显示")
        XCTAssertEqual(deepSeekProfile.visionModel, "gpt-4o")
        XCTAssertEqual(deepSeekProfile.customHeaders["HTTP-Referer"], "https://lingxi.ime")

        let applied = cfg.applying(profile: deepSeekProfile)
        XCTAssertEqual(applied.openAIModel, "deepseek-chat")
        XCTAssertEqual(applied.resolvedVisionModel(), "gpt-4o")
        XCTAssertEqual(applied.resolvedSTTModel(baseURL: "https://api.openai.com/v1"), "whisper-large-v3")

        var autoSTTCfg = AIConfig()
        autoSTTCfg.provider = .openAICompatible
        XCTAssertEqual(autoSTTCfg.resolvedSTTModel(baseURL: "https://api.siliconflow.cn/v1"), "FunAudioLLM/SenseVoiceSmall")
        XCTAssertEqual(autoSTTCfg.resolvedSTTModel(baseURL: "https://api.groq.com/openai/v1"), "whisper-large-v3-turbo")
        XCTAssertEqual(autoSTTCfg.resolvedSTTModel(baseURL: "https://api.openai.com/v1"), "whisper-1")

        XCTAssertEqual(cfg.resolvedKeyboardBuiltinActions.count, 8, "默认键盘内置技能应包含 8 项核心推荐能力")
        cfg.enabledBuiltinActions = [AIPresetAction.eqReply.rawValue, AIPresetAction.strategist.rawValue]
        XCTAssertEqual(cfg.resolvedKeyboardBuiltinActions, [.eqReply, .strategist])

        let p1 = CustomAIPromptTemplate(title: "催进度", instruction: "礼貌催促", isPinned: true)
        let p2 = CustomAIPromptTemplate(title: "写周报", instruction: "整理本周工作", isPinned: false)
        cfg.customPrompts = [p1, p2]
        cfg.keyboardShowAllCustomPrompts = true
        XCTAssertEqual(cfg.resolvedKeyboardCustomPrompts.map(\.title), ["催进度", "写周报"])
        cfg.keyboardShowAllCustomPrompts = false
        XCTAssertEqual(cfg.resolvedKeyboardCustomPrompts.map(\.title), ["催进度"])

        let exportedJSON = try XCTUnwrap(cfg.exportCustomPromptsJSON())
        let reimported = try XCTUnwrap(AIConfig.decodeCustomPromptsJSON(exportedJSON))
        XCTAssertEqual(reimported.map(\.title), ["催进度", "写周报"])

        // 5. 场景绑定知识卡过滤 + System Prompt 动态变量渲染
        let bossCard = PersonalContextCard(title: "汇报口径", content: "先说结论", sceneTag: "职场", boundScene: .bossClient, isEnabled: true)
        let friendCard = PersonalContextCard(title: "生活偏好", content: "轻松幽默", sceneTag: "生活", boundScene: .friendPartner, isEnabled: true)
        let globalCard = PersonalContextCard(title: "全局名片", content: "灵犀产品", sceneTag: "通用", boundScene: nil, isEnabled: true)
        cfg.contextCards = [bossCard, friendCard, globalCard]
        cfg.activeScenePersona = .bossClient
        let bossSystem = AIClient.mergeSystem(base: "日期 {{日期}}：请帮我改写。", config: cfg)
        XCTAssertFalse(bossSystem.contains("{{日期}}"), "System Prompt 内动态变量必须实时渲染")
        XCTAssertTrue(bossSystem.contains("[汇报口径]"), "老板场景应注入绑定的汇报口径知识卡")
        XCTAssertTrue(bossSystem.contains("[全局名片]"), "全局知识卡在所有场景均应生效")
        XCTAssertFalse(bossSystem.contains("[生活偏好]"), "绑定朋友场景的知识卡不应串入老板场景")

        // 6. OpenAI 推理模型适配 + 多轮 payload + 真实 Token 解析
        XCTAssertTrue(AIClient.isOpenAIReasoningModel("o3-mini"))
        XCTAssertTrue(AIClient.isOpenAIReasoningModel("openai/gpt-5-mini"))
        XCTAssertFalse(AIClient.isOpenAIReasoningModel("deepseek-chat"))

        let o3Payload = AIClient.buildOpenAIChatPayload(
            prompt: "",
            turns: [
                AIChatTurn(role: "user", content: "第一句"),
                AIChatTurn(role: "assistant", content: "好的"),
                AIChatTurn(role: "user", content: "再精简"),
            ],
            systemInstruction: "系统规则",
            model: "o3-mini",
            extraBody: ["reasoning_effort": "medium"],
            config: cfg
        )
        XCTAssertNotNil(o3Payload["max_completion_tokens"])
        XCTAssertNil(o3Payload["max_tokens"])
        XCTAssertNil(o3Payload["temperature"], "OpenAI 推理模型不得发送 temperature")
        let o3Msgs = try XCTUnwrap(o3Payload["messages"] as? [[String: Any]])
        XCTAssertEqual(o3Msgs.first?["role"] as? String, "developer")
        XCTAssertEqual(o3Msgs.count, 4)

        let stdPayload = AIClient.buildOpenAIChatPayload(
            prompt: "你好",
            systemInstruction: "系统规则",
            model: "deepseek-chat",
            extraBody: [:],
            config: cfg
        )
        XCTAssertNotNil(stdPayload["max_tokens"])
        XCTAssertNotNil(stdPayload["temperature"])
        XCTAssertNotNil(stdPayload["stream_options"])

        let oaiUsage = AIClient.parseOpenAIUsage(from: [
            "usage": [
                "prompt_tokens": 120,
                "completion_tokens": 80,
                "completion_tokens_details": ["reasoning_tokens": 30],
            ]
        ])
        XCTAssertEqual(oaiUsage, AITokenUsage(promptTokens: 120, completionTokens: 80, reasoningTokens: 30))
        let gemUsage = AIClient.parseGeminiUsage(from: [
            "usageMetadata": [
                "promptTokenCount": 200,
                "candidatesTokenCount": 90,
                "thoughtsTokenCount": 40,
            ]
        ])
        XCTAssertEqual(gemUsage, AITokenUsage(promptTokens: 200, completionTokens: 90, reasoningTokens: 40))

        // 7. AI 一键帮写技能解析 + 账本 Token 字段向后兼容
        let authored = AIAutoInsightService.parseGeneratedPromptTemplate(
            "```json\n{\"title\":\"客户跟进邮件\",\"category\":\"职场商务\",\"icon\":\"invalid.icon\",\"instruction\":\"把要点整理成礼貌跟进邮件\",\"useDeepModel\":true}\n```",
            fallbackGoal: "跟进邮件"
        )
        XCTAssertEqual(authored.title, "客户跟进邮件")
        XCTAssertEqual(authored.icon, "sparkles", "非法图标名必须自动回退为安全默认图标")
        XCTAssertTrue(authored.useDeepModel)
        XCTAssertTrue(authored.isAIGenerated)

        let legacyLedger = try JSONDecoder().decode(
            AIUsageLedgerEntry.self,
            from: Data("{\"id\":\"l1\",\"timestamp\":1730000000,\"provider\":\"gemini\",\"model\":\"gemini-2.5-flash\",\"feature\":\"polish\",\"thinkingMode\":\"auto\",\"ttftMs\":300,\"totalMs\":900,\"inputChars\":10,\"outputChars\":20,\"thoughtChars\":0}".utf8)
        )
        XCTAssertEqual(legacyLedger.totalReportedTokens, 0)
        let richLedger = AIUsageLedgerEntry(
            provider: "openai",
            model: "o3-mini",
            feature: "workbench_chat",
            thinkingMode: "medium",
            ttftMs: 420,
            totalMs: 1200,
            inputChars: 30,
            outputChars: 60,
            thoughtChars: 20,
            promptTokens: 100,
            completionTokens: 50,
            reasoningTokens: 25
        )
        XCTAssertEqual(richLedger.totalReportedTokens, 150)
    }

    func testV60FlagshipAIPrivacyDiffCostPipelinesAndRelayCrypto() throws {
        // 1. 端侧 AI 隐私脱敏护盾：6 大内置敏感类型 + 自定义隐私词 + 精确还原 + 跨分片流式还原
        let rawSecretMsg = "张伟手机 13812345678（备用 13812345678），邮箱 wei@lingxi.im，身份证 11010519900307281X，Key sk-abcdef1234567890abcd，内网 192.168.1.25。"
        let shielded = AIPrivacyShield.sanitize(rawSecretMsg, customTerms: ["张伟"])
        XCTAssertTrue(shielded.hasRedactions)
        XCTAssertFalse(shielded.sanitizedText.contains("张伟"))
        XCTAssertFalse(shielded.sanitizedText.contains("13812345678"))
        XCTAssertFalse(shielded.sanitizedText.contains("wei@lingxi.im"))
        XCTAssertFalse(shielded.sanitizedText.contains("11010519900307281X"))
        XCTAssertFalse(shielded.sanitizedText.contains("sk-abcdef1234567890abcd"))
        XCTAssertFalse(shielded.sanitizedText.contains("192.168.1.25"))
        XCTAssertTrue(shielded.sanitizedText.contains("[PRIV_1]"))
        XCTAssertTrue(shielded.sanitizedText.contains("[PHONE_1]"))
        XCTAssertTrue(shielded.sanitizedText.contains("[EMAIL_1]"))
        XCTAssertTrue(shielded.sanitizedText.contains("[ID_1]"))
        XCTAssertTrue(shielded.sanitizedText.contains("[SECRET_1]"))
        XCTAssertTrue(shielded.sanitizedText.contains("[IP_1]"))
        XCTAssertEqual(AIPrivacyShield.restore(shielded.sanitizedText, mapping: shielded.mapping), rawSecretMsg)

        // 跨分片流式还原状态机：占位符在任意位置被切断也不得闪烁泄露
        var restorer = AIPrivacyShield.StreamingRestoreBuffer(mapping: shielded.mapping)
        let chunks = ["收到，已联系 [PR", "IV_1]（电话 [PH", "ONE_1]", "），谢谢！"]
        var streamedOut = ""
        for ch in chunks {
            streamedOut += restorer.push(ch)
        }
        streamedOut += restorer.finish()
        XCTAssertEqual(streamedOut, "收到，已联系 张伟（电话 13812345678），谢谢！")

        // 2. 纯 Swift LCS 逐字红绿 Diff 引擎
        let sameDiff = AITextDiffEngine.diff(original: "今天天气不错", revised: "今天天气不错")
        XCTAssertEqual(sameDiff.deletedChars, 0)
        XCTAssertEqual(sameDiff.insertedChars, 0)
        XCTAssertEqual(sameDiff.unchangedChars, 6)

        let editDiff = AITextDiffEngine.diff(original: "我今天太忙了发不了", revised: "今天较忙明早发送")
        XCTAssertGreaterThan(editDiff.deletedChars, 0)
        XCTAssertGreaterThan(editDiff.insertedChars, 0)
        XCTAssertGreaterThan(editDiff.changeRatio, 0.2)
        // 验证 Diff 片段重拼后严格还原原文与新文
        let reconstructedOld = editDiff.segments.filter { $0.kind != .inserted }.map(\.text).joined()
        let reconstructedNew = editDiff.segments.filter { $0.kind != .deleted }.map(\.text).joined()
        XCTAssertEqual(reconstructedOld, "我今天太忙了发不了")
        XCTAssertEqual(reconstructedNew, "今天较忙明早发送")

        // 3. 主流模型成本估算器（本地 Ollama 免费、云端按 Token 估算）
        let ollamaEntry = AIUsageLedgerEntry(
            provider: "openAICompatible", model: "qwen2.5:7b", feature: "polish",
            thinkingMode: "off", ttftMs: 120, totalMs: 400, inputChars: 100, outputChars: 100, thoughtChars: 0,
            promptTokens: 1000, completionTokens: 1000
        )
        XCTAssertEqual(AICostEstimator.estimateUSD(for: ollamaEntry), 0.0, accuracy: 1e-9)

        let gemEntry = AIUsageLedgerEntry(
            provider: "gemini", model: "gemini-2.5-flash", feature: "workbench_chat",
            thinkingMode: "low", ttftMs: 320, totalMs: 900, inputChars: 500, outputChars: 500, thoughtChars: 0,
            promptTokens: 1_000_000, completionTokens: 1_000_000
        )
        XCTAssertEqual(AICostEstimator.estimateUSD(for: gemEntry), 2.80, accuracy: 0.01)
        XCTAssertTrue(AICostEstimator.formatCNY(2.80).hasPrefix("¥"))

        // 4. 多步 AI 链式流水线编译为键盘技能 + 多话题对话导出 Markdown + 自定义 @ai 前缀识别
        let pipe = try XCTUnwrap(AIPromptPipeline.defaultPipelines.first)
        let compiled = pipe.compiledAsCustomPrompt()
        XCTAssertEqual(compiled.category, "链式流水线")
        XCTAssertTrue(compiled.isPinned)
        XCTAssertTrue(compiled.instruction.contains("第1步"))
        XCTAssertTrue(compiled.instruction.contains("第2步"))

        let thread = AIWorkbenchThread(
            title: "周报润色",
            turns: [
                AIChatTurn(role: "user", content: "帮我润色周报"),
                AIChatTurn(role: "assistant", content: "本周核心产出如下。", model: "gemini-2.5-flash"),
            ]
        )
        let md = thread.exportMarkdown()
        XCTAssertTrue(md.contains("# 周报润色"))
        XCTAssertTrue(md.contains("本周核心产出如下。"))

        let customMatch = InlineAICommandDetector.detect(in: "前面聊了半天 !ai 帮我委婉拒绝加班", customPrefix: "!ai")
        XCTAssertEqual(customMatch?.command, "帮我委婉拒绝加班")
        XCTAssertEqual(customMatch?.triggerPrefix, "!ai")

        // 5. 跨屏剪贴板端到端加密信封（LXRL1: AES-256-GCM 往返 + 错码拒解 + 明文直通兼容）
        let sealedRelay = try ClipboardRelayCrypto.seal("跨屏验证码 654321", pairCode: "294817")
        XCTAssertTrue(sealedRelay.hasPrefix(ClipboardRelayCrypto.prefix))
        XCTAssertFalse(sealedRelay.contains("654321"))
        XCTAssertEqual(ClipboardRelayCrypto.open(sealedRelay, pairCode: "294817"), "跨屏验证码 654321")
        XCTAssertNotEqual(ClipboardRelayCrypto.open(sealedRelay, pairCode: "999999"), "跨屏验证码 654321")
        XCTAssertEqual(ClipboardRelayCrypto.open("网页端明文消息", pairCode: "294817"), "网页端明文消息")
    }

    func testV61AnthropicProtocolFailoverRAGAndBrainBundle() throws {
        // 1. Anthropic Claude 原生协议：模型解析、Messages 连续同角色合并、Extended Thinking 与温度互斥、Token 解析、视觉支持
        let anthropicModelsJSON = Data("""
        {
          "data": [
            {"id": "claude-sonnet-4-20250514", "display_name": "Claude Sonnet 4"},
            {"id": "claude-3-5-haiku-20241022", "display_name": "Claude 3.5 Haiku"}
          ]
        }
        """.utf8)
        let parsedClaudeModels = AIClient.parseAnthropicModelsPayload(anthropicModelsJSON)
        XCTAssertEqual(parsedClaudeModels.count, 2)
        XCTAssertEqual(parsedClaudeModels.first?.provider, .anthropic)
        XCTAssertEqual(parsedClaudeModels.first?.id, "claude-sonnet-4-20250514")
        XCTAssertTrue(ScreenshotOCRService.modelLikelySupportsVision(modelID: "claude-sonnet-4-20250514", provider: .anthropic))

        var claudeCfg = AIConfig()
        claudeCfg.provider = .anthropic
        claudeCfg.anthropicAPIKey = "sk-ant-secret-key-9999"
        claudeCfg.setActiveModel("claude-sonnet-4-20250514")
        claudeCfg.maxOutputTokens = 1024
        claudeCfg.temperature = 0.7

        let thinkingPayload = AIClient.buildAnthropicMessagesPayload(
            prompt: "",
            turns: [
                AIChatTurn(role: "user", content: "第一句背景"),
                AIChatTurn(role: "user", content: "补充细节"),
                AIChatTurn(role: "assistant", content: "收到"),
                AIChatTurn(role: "user", content: "请润色"),
            ],
            systemInstruction: "系统规则",
            model: "claude-sonnet-4-20250514",
            thinkingMode: .medium,
            includeThinking: true,
            config: claudeCfg
        )
        let mergedMsgs = try XCTUnwrap(thinkingPayload["messages"] as? [[String: Any]])
        XCTAssertEqual(mergedMsgs.count, 3, "连续同角色 user 消息必须自动合并，遵守 Anthropic 交替角色协议")
        XCTAssertTrue((mergedMsgs.first?["content"] as? String)?.contains("第一句背景\n\n补充细节") == true)
        let thinkingObj = try XCTUnwrap(thinkingPayload["thinking"] as? [String: Any])
        XCTAssertEqual(thinkingObj["type"] as? String, "enabled")
        XCTAssertEqual(thinkingObj["budget_tokens"] as? Int, 4096)
        XCTAssertGreaterThan((thinkingPayload["max_tokens"] as? Int) ?? 0, 4096, "启用 Extended Thinking 时 max_tokens 必须大于 budget_tokens")
        XCTAssertNil(thinkingPayload["temperature"], "Anthropic Extended Thinking 与自定义 temperature 互斥")

        let plainClaudePayload = AIClient.buildAnthropicMessagesPayload(
            prompt: "你好",
            systemInstruction: "系统规则",
            model: "claude-sonnet-4-20250514",
            thinkingMode: .off,
            includeThinking: false,
            config: claudeCfg
        )
        XCTAssertNil(plainClaudePayload["thinking"])
        XCTAssertNotNil(plainClaudePayload["temperature"])

        let startUsage = AIClient.parseAnthropicUsage(from: ["message": ["usage": ["input_tokens": 320, "output_tokens": 12]]])
        XCTAssertEqual(startUsage, AITokenUsage(promptTokens: 320, completionTokens: 12, reasoningTokens: nil))
        let deltaUsage = AIClient.parseAnthropicUsage(from: ["usage": ["output_tokens": 180]])
        XCTAssertEqual(deltaUsage, AITokenUsage(promptTokens: nil, completionTokens: 180, reasoningTokens: nil))

        // 2. 自动容灾切换判定与备用渠道解析
        XCTAssertTrue(AIClient.shouldTriggerFailover(for: AIClientError.httpError(429, "rate limit")))
        XCTAssertTrue(AIClient.shouldTriggerFailover(for: AIClientError.httpError(503, "overloaded")))
        XCTAssertTrue(AIClient.shouldTriggerFailover(for: AIClientError.httpError(402, "insufficient balance")))
        XCTAssertTrue(AIClient.shouldTriggerFailover(for: URLError(.timedOut)))
        XCTAssertFalse(AIClient.shouldTriggerFailover(for: AIClientError.httpError(400, "bad request")))
        XCTAssertFalse(AIClient.shouldTriggerFailover(for: AIClientError.httpError(401, "unauthorized")))
        XCTAssertFalse(AIClient.shouldTriggerFailover(for: CancellationError()))

        claudeCfg.saveCurrentAsProfile(name: "Claude 主力", createNew: true)
        var backupCfg = claudeCfg
        backupCfg.provider = .gemini
        backupCfg.geminiAPIKey = "AIza-backup-key-8888"
        backupCfg.geminiModel = "gemini-2.5-flash"
        backupCfg.saveCurrentAsProfile(name: "Gemini 备用", createNew: true)
        let geminiProfileID = try XCTUnwrap(backupCfg.profiles.first(where: { $0.name == "Gemini 备用" })?.id)
        let claudeProfile = try XCTUnwrap(backupCfg.profiles.first(where: { $0.name == "Claude 主力" }))
        backupCfg.activateProfile(claudeProfile)
        backupCfg.failoverProfileID = geminiProfileID
        let resolvedBackup = try XCTUnwrap(backupCfg.resolvedFailoverConfig())
        XCTAssertEqual(resolvedBackup.profileName, "Gemini 备用")
        XCTAssertEqual(resolvedBackup.config.provider, .gemini)
        XCTAssertEqual(resolvedBackup.config.activeAPIKey, "AIza-backup-key-8888")

        // 3. 端侧 RAG-Lite Top-K 知识检索 + Markdown 智能切片导入
        let cards: [PersonalContextCard] = [
            PersonalContextCard(title: "美食推荐", content: "喜欢粤菜和火锅", sceneTag: "生活", boundScene: nil, isEnabled: true),
            PersonalContextCard(title: "发版验收清单", content: "Swift iOS 打包前检查 XcodeGen 与签名证书", sceneTag: "研发", boundScene: nil, isEnabled: true),
            PersonalContextCard(title: "老板汇报模板", content: "先给结论再拆风险与排期", sceneTag: "职场", boundScene: .bossClient, isEnabled: true),
            PersonalContextCard(title: "旅游攻略", content: "京都岚山秋日红叶路线", sceneTag: "旅行", boundScene: nil, isEnabled: true),
            PersonalContextCard(title: "健身计划", content: "每周三次核心力量训练", sceneTag: "运动", boundScene: nil, isEnabled: true),
        ]
        let ranked = PersonalContextCard.selectRelevantCards(
            from: cards,
            query: "帮我检查 Swift 打包和 XcodeGen 签名",
            scene: .bossClient,
            limit: 2
        )
        XCTAssertEqual(ranked.count, 2)
        let rankedTitles = Set(ranked.map(\.card.title))
        XCTAssertTrue(rankedTitles.contains("老板汇报模板"), "精确匹配当前场景的知识卡应优先召回")
        XCTAssertTrue(rankedTitles.contains("发版验收清单"), "关键词高度命中的研发知识卡应进入 Top-2")
        XCTAssertFalse(rankedTitles.contains("旅游攻略"))

        let ragSystem = AIClient.mergeSystem(base: "助手", userPrompt: "帮我检查 Swift XcodeGen 签名", config: {
            var c = claudeCfg
            c.activeScenePersona = .bossClient
            c.contextCards = cards
            return c
        }())
        XCTAssertTrue(ragSystem.contains("[发版验收清单]"))
        XCTAssertTrue(ragSystem.contains("[老板汇报模板]"))

        let sampleMarkdown = """
        # 产品定位
        灵犀输入法是一款原生 iOS 高效输入法与 AI 写作助手。

        # 安全原则
        所有 API Key 均仅保存在用户设备本机，导出配置包绝不包含任何密钥。
        """
        let chunks = PersonalContextCard.chunkDocument(title: "灵犀手册", text: sampleMarkdown, sceneTag: "产品文档")
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].title, "产品定位")
        XCTAssertEqual(chunks[1].title, "安全原则")

        // 4. 无密钥 AI 智脑配置包导出与增量合入（严防 API Key 泄漏）
        backupCfg.customPersonaPrompt = "保持克制简洁"
        backupCfg.styleDNA.personalCatchphrases = ["收到啦～"]
        backupCfg.privacyCustomTerms = ["机密代号X"]
        backupCfg.contextCards = chunks
        backupCfg.customPrompts = [CustomAIPromptTemplate(title: "周报提炼", instruction: "提炼核心成果", isPinned: true)]

        let bundleData = try XCTUnwrap(backupCfg.exportBrainBundleJSON())
        let bundleText = String(data: bundleData, encoding: .utf8) ?? ""
        XCTAssertFalse(bundleText.contains("sk-ant-secret-key-9999"), "无密钥智脑包绝不可泄露 Claude API Key")
        XCTAssertFalse(bundleText.contains("AIza-backup-key-8888"), "无密钥智脑包绝不可泄露 Gemini API Key")
        XCTAssertTrue(bundleText.contains("LINGXI-AI-BRAIN-BUNDLE"))

        var targetCfg = AIConfig()
        targetCfg.geminiAPIKey = "LOCAL-OWN-KEY-DO-NOT-TOUCH"
        targetCfg.customPrompts = []
        targetCfg.contextCards = []
        targetCfg.aiPipelines = []
        let importStats = try XCTUnwrap(targetCfg.importBrainBundleJSON(bundleData))
        XCTAssertEqual(importStats.prompts, 1)
        XCTAssertEqual(importStats.cards, 2)
        XCTAssertEqual(targetCfg.geminiAPIKey, "LOCAL-OWN-KEY-DO-NOT-TOUCH", "导入智脑包绝不可覆盖本地已有 API Key")
        XCTAssertTrue(targetCfg.privacyCustomTerms.contains("机密代号X"))
        XCTAssertEqual(targetCfg.customPersonaPrompt, "保持克制简洁")
    }

    func testV62PerformanceFailoverBackupBudgetAndVModeTools() throws {
        // 1. 侧载桥接口令必须保留已绑定的容灾备用渠道（且清空其 fetchedModels 保持口令精简）
        let prevAI = AIConfig.load()
        defer { _ = prevAI.save() }

        var src = AIConfig()
        src.provider = .anthropic
        src.anthropicAPIKey = "sk-ant-main-111"
        src.anthropicModel = "claude-sonnet-4-20250514"
        src.saveCurrentAsProfile(name: "主 Claude", createNew: true)

        let backupProf = AIProviderProfile(
            name: "备用 Gemini",
            provider: .gemini,
            baseURL: AIConfig.defaultGeminiBaseURL,
            apiKey: "AIza-failover-222",
            model: "gemini-2.5-flash",
            fetchedModels: [AIModelInfo(id: "gemini-2.5-flash", displayName: "Flash", supportsThinking: true, contextLength: 1_000_000, provider: .gemini)]
        )
        src.profiles.append(backupProf)
        src.failoverProfileID = backupProf.id
        _ = src.save()

        let token = try XCTUnwrap(SideloadConfigBridge.exportLocalConfigHandoffTokenFromMainApp())
        // 清空本地档案再导入，模拟隔离沙盒键盘端首次接收口令
        var wiped = AIConfig()
        wiped.profiles = []
        wiped.failoverProfileID = nil
        _ = wiped.save()

        XCTAssertTrue(SideloadConfigBridge.importPairingToken(token))
        let imported = AIConfig.load()
        let failover = try XCTUnwrap(imported.resolvedFailoverConfig(), "侧载桥接导入后必须完整保留容灾备用渠道")
        XCTAssertEqual(failover.profileName, "备用 Gemini")
        XCTAssertEqual(failover.config.provider, .gemini)
        XCTAssertEqual(failover.config.activeAPIKey, "AIza-failover-222")
        XCTAssertTrue(imported.profiles.first(where: { $0.id == backupProf.id })?.fetchedModels.isEmpty == true, "桥接口令内的备用档案应剔除冗余模型缓存")

        // 2. 加密备份白名单包含全部 v5/v6 核心 AI 资产文件 + 排除本地保险箱
        let backupSet = Set(LingxiBackup.jsonFileNames)
        XCTAssertTrue(backupSet.contains("lingxi_style_dna.json"))
        XCTAssertTrue(backupSet.contains("lingxi_ai_workbench_threads.json"))
        XCTAssertTrue(backupSet.contains("lingxi_ai_recent_history.json"))
        XCTAssertTrue(backupSet.contains("lingxi_ai_usage_ledger.json"))
        XCTAssertTrue(backupSet.contains("lingxi_touch_calibration.json"))
        XCTAssertFalse(backupSet.contains("lingxi_local_secure_vault.json"), "设备级 Keychain 加密保险箱不应裸字节跨设备拷贝")

        // 3. AI 成本精准分层（Claude Haiku vs Sonnet vs Opus）与自然月预算统计
        let haikuRate = AICostEstimator.pricing(forModel: "claude-3-5-haiku-20241022", provider: "anthropic")
        let sonnetRate = AICostEstimator.pricing(forModel: "claude-sonnet-4-20250514", provider: "anthropic")
        let opusRate = AICostEstimator.pricing(forModel: "claude-opus-4-20250514", provider: "anthropic")
        XCTAssertLessThan(haikuRate.inputPerMillionUSD, sonnetRate.inputPerMillionUSD)
        XCTAssertLessThan(sonnetRate.inputPerMillionUSD, opusRate.inputPerMillionUSD)

        let fixedNow = Date(timeIntervalSince1970: 1_795_700_000) // 2026-11-26
        let lastMonth = Date(timeIntervalSince1970: 1_795_700_000 - 40 * 86400)
        let eThisMonth = AIUsageLedgerEntry(
            timestamp: Int(fixedNow.timeIntervalSince1970),
            provider: "anthropic", model: "claude-sonnet-4-20250514", feature: "kb_three_variants",
            thinkingMode: "off", ttftMs: 400, totalMs: 1200, inputChars: 100, outputChars: 100, thoughtChars: 0,
            promptTokens: 1_000_000, completionTokens: 0
        )
        let eLastMonth = AIUsageLedgerEntry(
            timestamp: Int(lastMonth.timeIntervalSince1970),
            provider: "anthropic", model: "claude-opus-4-20250514", feature: "workbench_chat",
            thinkingMode: "off", ttftMs: 400, totalMs: 1200, inputChars: 100, outputChars: 100, thoughtChars: 0,
            promptTokens: 1_000_000, completionTokens: 0
        )
        XCTAssertEqual(AICostEstimator.currentMonthEstimatedUSD(for: [eThisMonth, eLastMonth], now: fixedNow), 3.0, accuracy: 0.01)

        // 4. 零延迟离线 v 模式工具 v2：相对日期 / 单位换算 / 时间戳与 UUID
        let refCal = Calendar(identifier: .gregorian)
        let refDate = try XCTUnwrap(refCal.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 9, minute: 30)))
        let plus3 = VModeToolEngine.candidates(forBody: "+3d", now: refDate)
        XCTAssertTrue(plus3.contains("2026-11-30"), "v+3d 应准确推算 3 天后的日期")
        XCTAssertTrue(plus3.first?.contains("2026年11月30日") == true)

        let minus7 = VModeToolEngine.candidates(forBody: "-7d", now: refDate)
        XCTAssertTrue(minus7.contains("2026-11-20"))

        let tomorrow = VModeToolEngine.candidates(forBody: "mingtian", now: refDate)
        XCTAssertTrue(tomorrow.contains("2026-11-28"))

        let cmConv = VModeToolEngine.candidates(forBody: "180cm", now: refDate)
        XCTAssertTrue(cmConv.contains("1.8 米"))
        XCTAssertTrue(cmConv.contains("5'11\""))

        let kgConv = VModeToolEngine.candidates(forBody: "65kg", now: refDate)
        XCTAssertTrue(kgConv.contains("130 斤"))

        let tempC = VModeToolEngine.candidates(forBody: "38c", now: refDate)
        XCTAssertTrue(tempC.contains("100.4 °F"))
        let tempNeg = VModeToolEngine.candidates(forBody: "-40c", now: refDate)
        XCTAssertTrue(tempNeg.contains("-40 °F"))

        let gbConv = VModeToolEngine.candidates(forBody: "1.5gb", now: refDate)
        XCTAssertTrue(gbConv.contains("1536 MB"))

        let tsOut = VModeToolEngine.candidates(forBody: "ts", now: refDate)
        XCTAssertEqual(tsOut.first, "\(Int(refDate.timeIntervalSince1970))")
        let uuidOut = VModeToolEngine.candidates(forBody: "uuid", now: refDate)
        XCTAssertEqual(uuidOut.count, 2)
        XCTAssertNotNil(UUID(uuidString: uuidOut[0]))

        XCTAssertTrue(SmartCandidateHelper.isVToolQuery("v+3d", scheme: .quanpin))
        XCTAssertTrue(SmartCandidateHelper.isVToolQuery("v180cm", scheme: .quanpin))
        XCTAssertTrue(SmartCandidateHelper.isVToolQuery("V180cm", scheme: .xiaohe))
        XCTAssertFalse(SmartCandidateHelper.isVToolQuery("v180cm", scheme: .xiaohe), "双拼下小写 v 为声母，严禁抢占为工具模式")

        // 5. InlineAICommandDetector 纯内存检测：无磁盘 I/O，显式支持自定义前缀
        XCTAssertNil(InlineAICommandDetector.detect(in: "你好", customPrefix: "@ai"))
        let customHit = try XCTUnwrap(InlineAICommandDetector.detect(in: "测试前缀 #ai 帮我润色这句话", customPrefix: "#ai"))
        XCTAssertEqual(customHit.command, "帮我润色这句话")
        XCTAssertEqual(customHit.triggerPrefix, "#ai")
    }

    func testV63SwipeCommandsSlashMacrosOfflineLinter() throws {
        // 1. 仓输入法级按键划动命令引擎：解析、大小写容错、普通符号直通、键帽微型角标与预设
        XCTAssertEqual(KeyboardSwipeCommand.parse("#firstChar"), .firstChar)
        XCTAssertEqual(KeyboardSwipeCommand.parse("#LASTCHAR"), .lastChar)
        XCTAssertEqual(KeyboardSwipeCommand.parse("#ai3v"), .aiThreeVariants)
        XCTAssertNil(KeyboardSwipeCommand.parse("@"))
        XCTAssertNil(KeyboardSwipeCommand.parse("()"))
        XCTAssertEqual(KeyboardSwipeCommand.keycapBadge(for: "#paste"), "贴")
        XCTAssertEqual(KeyboardSwipeCommand.keycapBadge(for: "#firstChar"), "首")
        XCTAssertEqual(KeyboardSwipeCommand.keycapBadge(for: "@"), "@")
        for cmd in KeyboardSwipeCommand.allCases {
            XCTAssertLessThanOrEqual(cmd.keycapBadge.count, 2, "键帽角标不得超过 2 字符：\(cmd.rawValue)")
            XCTAssertEqual(KeyboardSwipeCommand.parse(cmd.rawValue), cmd)
        }
        XCTAssertEqual(KeyboardSwipeCommand.hamsterEfficiencyUpPreset["j"], "#firstChar")
        XCTAssertEqual(KeyboardSwipeCommand.hamsterEfficiencyDownPreset["v"], "#paste")

        // 2. 全栈斜杠 AI 宏指令引擎：前缀带参、尾缀作用于前文、/3v、自定义技能与流水线、URL 防误触
        let enPrefix = try XCTUnwrap(InlineAICommandDetector.detect(in: "/en 明天下午三点开会", customPrefix: "@ai"))
        XCTAssertEqual(enPrefix.command, "明天下午三点开会")
        XCTAssertEqual(enPrefix.triggerPrefix, "/en")
        XCTAssertEqual(enPrefix.actionTitle, "⚡ 译为英文")
        XCTAssertNotNil(enPrefix.systemInstruction)

        let fixSuffix = try XCTUnwrap(InlineAICommandDetector.detect(in: "这个方案我明天发给你看看 /fix", customPrefix: "@ai"))
        XCTAssertEqual(fixSuffix.command, "这个方案我明天发给你看看")
        XCTAssertEqual(fixSuffix.triggerPrefix, "/fix")
        XCTAssertEqual(fixSuffix.fullMatchCount, "这个方案我明天发给你看看 /fix".count)

        let threeV = try XCTUnwrap(InlineAICommandDetector.detect(in: "周末临时加班能不能调休 /3v", customPrefix: "@ai"))
        XCTAssertTrue(threeV.isThreeVariants)
        XCTAssertEqual(threeV.command, "周末临时加班能不能调休")

        // URL 路径里的 /en 或 /fix 绝不可误触发斜杠宏
        XCTAssertNil(InlineAICommandDetector.detect(in: "请访问 https://example.com/en", customPrefix: "@ai"))
        XCTAssertNil(InlineAICommandDetector.detect(in: "路径 docs/guide/fix", customPrefix: "@ai"))

        // 动态匹配用户自定义技能与多步链式流水线
        let customTpl = CustomAIPromptTemplate(title: "周报", instruction: "整理为要点式周报", isPinned: true, useDeepModel: true)
        let customMacro = try XCTUnwrap(InlineAICommandDetector.detect(
            in: "/周报 完成了登录模块和支付联调",
            customPrefix: "@ai",
            customPrompts: [customTpl]
        ))
        XCTAssertEqual(customMacro.command, "完成了登录模块和支付联调")
        XCTAssertEqual(customMacro.actionTitle, "⚡ 技能：周报")
        XCTAssertTrue(customMacro.preferDeep)

        let pipe = AIPromptPipeline(
            title: "精修发群",
            summary: "脱敏再润色",
            steps: [
                AIPromptPipelineStep(name: "提炼", instruction: "提炼重点"),
                AIPromptPipelineStep(name: "润色", instruction: "改为自然口语"),
            ]
        )
        let pipeMacro = try XCTUnwrap(InlineAICommandDetector.detect(
            in: "今天联调遇到个小问题已经修好了 /精修发群",
            customPrefix: "@ai",
            pipelines: [pipe]
        ))
        XCTAssertEqual(pipeMacro.actionTitle, "⚡ 流水线：精修发群")
        XCTAssertEqual(pipeMacro.command, "今天联调遇到个小问题已经修好了")

        // 3. 100% 离线中文文案与 AI 腔实时质检仪
        let cleanReport = OfflineTextLinter.analyze("今天下午 3 点我们一起开会同步进度，辛苦啦。")
        XCTAssertEqual(cleanReport.score, 100)
        XCTAssertTrue(cleanReport.findings.isEmpty)
        XCTAssertFalse(cleanReport.hasAutoFixChanges)

        let dirtyText = "各位好,我们在iPhone16上完成了的的闭环赋能!联系方式13812345678"
        let dirtyReport = OfflineTextLinter.analyze(dirtyText, bannedCliches: ["赋能", "闭环"], privacyCustomTerms: [])
        XCTAssertLessThan(dirtyReport.score, 75)
        XCTAssertTrue(dirtyReport.findings.contains(where: { $0.category == .privacy }))
        XCTAssertTrue(dirtyReport.findings.contains(where: { $0.category == .typoDuplicate }))
        XCTAssertTrue(dirtyReport.findings.contains(where: { $0.category == .aiCliche }))
        XCTAssertTrue(dirtyReport.findings.contains(where: { $0.category == .typography }))
        XCTAssertEqual(dirtyReport.privacyHitCount, 1)
        XCTAssertFalse(dirtyReport.privacyRedactedText.contains("13812345678"))
        XCTAssertTrue(dirtyReport.hasAutoFixChanges)
        XCTAssertFalse(dirtyReport.autoFixedText.contains("的的"))
        XCTAssertTrue(dirtyReport.autoFixedText.contains("各位好，我们在 iPhone16 上完成了的闭环赋能！"))
    }

    func testV64OpenCCContextRerankerLayoutPacksAndLintFix() throws {
        // 1. OpenCC 级两岸三地简繁词级双向转换引擎
        let techSample = "软件、内存、鼠标、服务器、默认、打印"
        let twTech = ChineseScriptConverter.toTraditional(techSample, variant: .taiwanPhrase)
        XCTAssertTrue(twTech.contains("軟體"))
        XCTAssertTrue(twTech.contains("記憶體"))
        XCTAssertTrue(twTech.contains("滑鼠"))
        XCTAssertTrue(twTech.contains("伺服器"))
        XCTAssertTrue(twTech.contains("預設"))
        XCTAssertTrue(twTech.contains("列印"))

        let hkTech = ChineseScriptConverter.toTraditional("软件、出租车、公交车", variant: .hongKong)
        XCTAssertTrue(hkTech.contains("軟件"))
        XCTAssertTrue(hkTech.contains("的士"))
        XCTAssertTrue(hkTech.contains("巴士"))

        let stdDisambig = ChineseScriptConverter.toTraditional("皇后以后头发干净干活面条方面一只只有台风舞台里面公里", variant: .standard)
        XCTAssertTrue(stdDisambig.contains("皇后以後"))
        XCTAssertTrue(stdDisambig.contains("頭髮"))
        XCTAssertTrue(stdDisambig.contains("乾淨幹活"))
        XCTAssertTrue(stdDisambig.contains("麵條方面"))
        XCTAssertTrue(stdDisambig.contains("一隻只有"))
        XCTAssertTrue(stdDisambig.contains("颱風舞台"))
        XCTAssertTrue(stdDisambig.contains("裡面公里"))

        let backToSimp = ChineseScriptConverter.toSimplified("這款軟體在伺服器記憶體與滑鼠列印上做了最佳化", normalizeRegionalTerms: true)
        XCTAssertTrue(backToSimp.contains("软件"))
        XCTAssertTrue(backToSimp.contains("服务器"))
        XCTAssertTrue(backToSimp.contains("内存"))
        XCTAssertTrue(backToSimp.contains("鼠标"))
        XCTAssertTrue(backToSimp.contains("打印"))
        XCTAssertTrue(backToSimp.contains("优化"))

        // 2. 端侧零延迟语境同音消歧重排引擎（数字量词 / 星期序数 / 动宾搭配 + 联动 PinyinEngine 实测）
        let after3 = ContextualReranker.bonusMap(forContextBeforeCursor: "明天下午3")
        XCTAssertGreaterThan(after3["点"] ?? 0, 4.0)
        let afterYear = ContextualReranker.bonusMap(forContextBeforeCursor: "2026")
        XCTAssertGreaterThan(afterYear["年"] ?? 0, 5.0)
        let afterDrink = ContextualReranker.bonusMap(forContextBeforeCursor: "多喝")
        XCTAssertGreaterThan(afterDrink["水"] ?? 0, 4.5)
        let afterWeek = ContextualReranker.bonusMap(forContextBeforeCursor: "星期")
        XCTAssertGreaterThan(afterWeek["一"] ?? 0, 4.5)

        if let dbURL = findTestDBURL() {
            let engine = PinyinEngine(databaseURL: dbURL)
            var s = LingxiSettings()
            s.userLearningEnabled = false
            s.bigramPredictionEnabled = true

            let r3Dian = engine.query(raw: "dian", settings: s, contextBeforeCursor: "下午3")
            XCTAssertEqual(r3Dian.candidates.first?.word, "点", "数字 3 后输入 dian 应精准首选「点」")

            let rYear = engine.query(raw: "nian", settings: s, contextBeforeCursor: "2026")
            XCTAssertEqual(rYear.candidates.first?.word, "年", "年份 2026 后输入 nian 应精准首选「年」")

            let rDrink = engine.query(raw: "shui", settings: s, contextBeforeCursor: "我要喝")
            XCTAssertEqual(rDrink.candidates.first?.word, "水", "「喝」后输入 shui 应精准首选「水」而非「睡」")

            let rSleep = engine.query(raw: "shui", settings: s, contextBeforeCursor: "准备去")
            XCTAssertEqual(rSleep.candidates.first?.word, "睡", "「去」后输入 shui 应精准首选「睡」")
        }

        // 3. 声明式可分享自定义键盘布局包（5 套内置 + 应用至设置 + JSON 导出/导入往返 + 畸形拦截）
        XCTAssertEqual(CustomKeyboardLayoutPack.builtInPacks.count, 5)
        let devPack = try XCTUnwrap(CustomKeyboardLayoutPack.find(id: "developer"))
        var testSettings = LingxiSettings()
        devPack.apply(to: &testSettings)
        XCTAssertEqual(testSettings.activeLayoutPackID, "developer")
        XCTAssertTrue(testSettings.showNumberRow)
        XCTAssertEqual(testSettings.punctuationStyle, .halfwidth)
        XCTAssertTrue(testSettings.panguSpaceLetters)
        XCTAssertEqual(testSettings.customSwipeDownMap["c"], KeyboardSwipeCommand.lintFix.rawValue)

        let exportedPack = CustomKeyboardLayoutPack.fromCurrentSettings(testSettings, name: "测试极客包")
        let packJSON = try XCTUnwrap(exportedPack.exportJSON())
        let redecoded = try XCTUnwrap(CustomKeyboardLayoutPack.decodeJSON(packJSON))
        XCTAssertEqual(redecoded.name, "测试极客包")
        XCTAssertEqual(redecoded.swipeDownMap["k"], "->")
        XCTAssertTrue(redecoded.showNumberRow)
        XCTAssertNil(CustomKeyboardLayoutPack.decodeJSON(Data("{\"format\":\"INVALID\",\"name\":\"x\"}".utf8)))

        // 4. 离线排版体检划动命令 #lintFix
        XCTAssertEqual(KeyboardSwipeCommand.parse("#lintFix"), .lintFix)
        XCTAssertEqual(KeyboardSwipeCommand.keycapBadge(for: "#lintFix"), "检")
    }

    func testV65PairedBracketsLayoutPackStripAndEditPad() throws {
        // 1. 统一成对括号引擎（12 组配对、单开补全、预配对自动光标置中、闭括号越过、空对连删）
        XCTAssertEqual(PairedBracketHelper.expandedPair(for: "{"), "{}")
        XCTAssertEqual(PairedBracketHelper.expandedPair(for: "("), "()")
        XCTAssertEqual(PairedBracketHelper.expandedPair(for: "["), "[]")
        XCTAssertEqual(PairedBracketHelper.expandedPair(for: "『"), "『』")
        XCTAssertEqual(PairedBracketHelper.expandedPair(for: "〈"), "〈〉")
        XCTAssertNil(PairedBracketHelper.expandedPair(for: ")"))

        XCTAssertTrue(PairedBracketHelper.shouldSkipCloser("}", nextChar: "}"))
        XCTAssertTrue(PairedBracketHelper.shouldSkipCloser("』", nextChar: "』"))
        XCTAssertTrue(PairedBracketHelper.shouldSkipCloser(">", nextChar: ">"))
        XCTAssertFalse(PairedBracketHelper.shouldSkipCloser("}", nextChar: ")"))
        XCTAssertFalse(PairedBracketHelper.shouldSkipCloser("a", nextChar: "a"))

        for prePaired in ["()", "[]", "{}", "<>", "（）", "「」", "『』", "【】", "《》", "〈〉", "“”", "‘’"] {
            XCTAssertTrue(PairedBracketHelper.shouldAutoPlaceCursorInside(prePaired), "预配对符号 \(prePaired) 应自动将光标置入中央")
        }
        XCTAssertFalse(PairedBracketHelper.shouldAutoPlaceCursorInside("->"))

        XCTAssertTrue(PairedBracketHelper.isMatchingPair(left: "{", right: "}"))
        XCTAssertTrue(PairedBracketHelper.isMatchingPair(left: "<", right: ">"))
        XCTAssertTrue(PairedBracketHelper.isMatchingPair(left: "『", right: "』"))
        XCTAssertTrue(PairedBracketHelper.isMatchingPair(left: "〈", right: "〉"))
        XCTAssertFalse(PairedBracketHelper.isMatchingPair(left: "{", right: "]"))

        // 2. 全部 5 套布局包均携带非空专属快捷符号/命令条，并兼容 #命令 解析
        for pack in CustomKeyboardLayoutPack.builtInPacks {
            XCTAssertFalse(pack.quickStripTokens.isEmpty, "布局包 \(pack.id) 的 quickStripTokens 不应为空")
            for token in pack.quickStripTokens where token.hasPrefix("#") {
                XCTAssertNotNil(KeyboardSwipeCommand.parse(token), "布局包 \(pack.id) 中的命令 \(token) 应合法")
            }
        }

        // 3. 专业编辑台零联网文本工坊核心链路（离线排版 + 隐私脱敏 + 繁简双向互转）
        let rawLine = "各位好,我们在iPhone16上完成了的的联调!手机号13812345678"
        let linted = OfflineTextLinter.autoFix(rawLine)
        XCTAssertFalse(linted.contains("的的"))
        XCTAssertTrue(linted.contains("各位好，我们在 iPhone16 上完成了的联调！"))
        let redacted = AIPrivacyShield.sanitize(linted, customTerms: []).sanitizedText
        XCTAssertFalse(redacted.contains("13812345678"))
        XCTAssertTrue(redacted.contains("[PHONE_1]"))

        let simpLine = "这款软件在服务器内存上做了优化"
        let twLine = ChineseScriptConverter.toTraditional(simpLine, variant: .taiwanPhrase)
        XCTAssertNotEqual(twLine, simpLine)
        XCTAssertTrue(twLine.contains("軟體"))
        XCTAssertEqual(ChineseScriptConverter.toTraditional(twLine, variant: .taiwanPhrase), twLine)
        let roundtripSimp = ChineseScriptConverter.toSimplified(twLine, normalizeRegionalTerms: true)
        XCTAssertEqual(roundtripSimp, simpLine)
    }

    func testV66OfflineSlashMacrosSessionPoolingAndRelayGuard() throws {
        // 1. 0ms 离线斜杠宏（/lint /mask /trad）前缀带参与尾缀双模式检测 + URL 边界隔离
        let lintSuffix = try XCTUnwrap(InlineAICommandDetector.detect(in: "我们在iPhone16上完成了的的联调! /lint"))
        XCTAssertEqual(lintSuffix.triggerPrefix, "/lint")
        XCTAssertEqual(lintSuffix.offlineMacro, .lintFix)
        XCTAssertEqual(lintSuffix.command, "我们在iPhone16上完成了的的联调!")
        XCTAssertEqual(OfflineTextLinter.autoFix(lintSuffix.command), "我们在 iPhone16 上完成了的联调！")

        let maskPrefix = try XCTUnwrap(InlineAICommandDetector.detect(in: "/mask 我的手机13812345678请查收"))
        XCTAssertEqual(maskPrefix.triggerPrefix, "/mask")
        XCTAssertEqual(maskPrefix.offlineMacro, .privacyMask)
        XCTAssertTrue(AIPrivacyShield.sanitize(maskPrefix.command).sanitizedText.contains("[PHONE_1]"))

        let tradSuffix = try XCTUnwrap(InlineAICommandDetector.detect(in: "这款软件默认支持内存优化 /trad"))
        XCTAssertEqual(tradSuffix.triggerPrefix, "/trad")
        XCTAssertEqual(tradSuffix.offlineMacro, .toggleTraditional)
        XCTAssertTrue(ChineseScriptConverter.toTraditional(tradSuffix.command, variant: .taiwanPhrase).contains("軟體"))

        XCTAssertNil(InlineAICommandDetector.detect(in: "https://example.com/lint"))
        XCTAssertNil(InlineAICommandDetector.detect(in: "https://example.com/mask"))

        // 2. AIClient 连接池实例化稳定性（多次高频构造不产生独立 URLSession 泄漏且保持配置有效）
        let c1 = AIClient(timeout: 15)
        let c2 = AIClient(timeout: 45)
        XCTAssertTrue(c1 !== c2)

        // 3. 跨屏接力密文前缀拦截与敏感内容防写入校验
        let sealed = try ClipboardRelayCrypto.seal("验证码 668899", pairCode: "123456")
        XCTAssertTrue(sealed.hasPrefix(ClipboardRelayCrypto.prefix))
        let wrongOpen = ClipboardRelayCrypto.open(sealed, pairCode: "654321")
        XCTAssertTrue(wrongOpen.hasPrefix(ClipboardRelayCrypto.prefix), "错码解不开时保留密文前缀以便客户端拦截不污染剪贴板")
        let rightOpen = ClipboardRelayCrypto.open(sealed, pairCode: "123456")
        XCTAssertEqual(rightOpen, "验证码 668899")
        XCTAssertFalse(rightOpen.hasPrefix(ClipboardRelayCrypto.prefix))
    }

    func testV67EmbeddedStreamErrorParsingAndPinyinThreadSafety() throws {
        // 1. 第三方中转站 HTTP 200 嵌入式 JSON 错误提取与 Auto-Failover 触发校验
        let rateLimitObj: [String: Any] = ["error": ["message": "Rate limit exceeded on upstream", "type": "rate_limit_error"]]
        let parsedRL = try XCTUnwrap(AIClient.extractEmbeddedStreamError(from: rateLimitObj))
        XCTAssertEqual(parsedRL.code, 429)
        XCTAssertTrue(AIClient.shouldTriggerFailover(for: AIClientError.httpError(parsedRL.code, parsedRL.message)))

        let quotaObj: [String: Any] = ["error": ["message": "该渠道余额不足，请充值", "type": "new_api_error"]]
        let parsedQuota = try XCTUnwrap(AIClient.extractEmbeddedStreamError(from: quotaObj))
        XCTAssertEqual(parsedQuota.code, 402)
        XCTAssertTrue(AIClient.shouldTriggerFailover(for: AIClientError.httpError(parsedQuota.code, parsedQuota.message)))

        let authObj: [String: Any] = ["error": ["code": 401, "message": "Invalid API key"]]
        let parsedAuth = try XCTUnwrap(AIClient.extractEmbeddedStreamError(from: authObj))
        XCTAssertEqual(parsedAuth.code, 401)
        XCTAssertFalse(AIClient.shouldTriggerFailover(for: AIClientError.httpError(parsedAuth.code, parsedAuth.message)))

        let geminiErrObj: [String: Any] = ["error": ["code": 503, "message": "The model is overloaded", "status": "UNAVAILABLE"]]
        let parsedGem = try XCTUnwrap(AIClient.extractEmbeddedStreamError(from: geminiErrObj))
        XCTAssertEqual(parsedGem.code, 503)
        XCTAssertTrue(AIClient.shouldTriggerFailover(for: AIClientError.httpError(parsedGem.code, parsedGem.message)))

        XCTAssertNil(AIClient.extractEmbeddedStreamError(from: ["choices": []]))

        // 2. PinyinEngine SQLite FULLMUTEX + NSRecursiveLock 多线程并发查询与内存回收稳定性压力测试
        if let dbURL = findTestDBURL() {
            let engine = PinyinEngine(databaseURL: dbURL)
            var s = LingxiSettings()
            s.userLearningEnabled = false
            let samples = ["nihao", "zhongguo", "shurufa", "weixin", "rengongzhineng", "jintian"]
            let lock = NSLock()
            var okCount = 0
            DispatchQueue.concurrentPerform(iterations: 24) { idx in
                if idx == 12 {
                    engine.releaseMemory()
                } else {
                    let q = samples[idx % samples.count]
                    let res = engine.query(raw: q, settings: s)
                    if !(res.candidates.first?.word ?? "").isEmpty {
                        lock.lock()
                        okCount += 1
                        lock.unlock()
                    }
                }
            }
            XCTAssertEqual(okCount, 23, "并发查询与内存回收交替执行应 100% 稳定无崩溃")
        }
    }

    func testV68PromptVariablesAndVoiceTranscriptCleaner() throws {
        // 1. Raycast 级动态变量提示词引擎（枚举胶囊、默认值、自由变量、内置上下文令牌去重与渲染）
        let tpl = "对象：{{对象|老板,客户,同事}}；语气：{{语气|专业得体,温柔委婉}}；字数：{{字数=80}}；城市：{{当前城市}}；日期：{{当前日期}}；要点：{{核心要点}}；再次引用：{{对象|老板,客户}}"
        let vars = PromptVariableEngine.extractVariables(from: tpl)
        XCTAssertEqual(vars.map(\.name), ["对象", "语气", "字数", "核心要点"])
        XCTAssertTrue(vars[0].isChoice)
        XCTAssertEqual(vars[0].options, ["老板", "客户", "同事"])
        XCTAssertEqual(vars[2].defaultValue, "80")
        XCTAssertFalse(vars[2].isChoice)
        XCTAssertTrue(PromptVariableEngine.hasInteractiveVariables(in: tpl))
        XCTAssertFalse(PromptVariableEngine.hasInteractiveVariables(in: "纯文本 {{当前日期}} {{剪贴板}}"))

        let rendered = PromptVariableEngine.render(
            template: tpl,
            values: ["对象": "客户", "核心要点": "延后两天交付"],
            clipboardText: "剪贴板测试",
            sceneTitle: "领导与客户",
            cityName: "上海"
        )
        XCTAssertTrue(rendered.contains("对象：客户"))
        XCTAssertTrue(rendered.contains("语气：专业得体"))
        XCTAssertTrue(rendered.contains("字数：80"))
        XCTAssertTrue(rendered.contains("城市：上海"))
        XCTAssertTrue(rendered.contains("要点：延后两天交付"))
        XCTAssertTrue(rendered.contains("再次引用：客户"))
        XCTAssertFalse(rendered.contains("{{"))

        XCTAssertEqual(PromptVariableEngine.featuredTemplates.count, 8)
        for ft in PromptVariableEngine.featuredTemplates {
            XCTAssertTrue(PromptVariableEngine.hasInteractiveVariables(in: ft.userPromptTemplate), "模板 \(ft.id) 应含交互变量")
        }

        // 2. 0ms 端侧口述智能清洗引擎（口误回撤、语境安全去口水词、结巴叠词合并、盘古排版）
        let r1 = VoiceTranscriptCleaner.clean("嗯，那个，明天下午三点哦不对四点开会，预算五万说错了八万!")
        XCTAssertGreaterThanOrEqual(r1.selfCorrectionsCount, 2)
        XCTAssertGreaterThanOrEqual(r1.removedFillersCount, 1)
        XCTAssertFalse(r1.cleaned.contains("三点"))
        XCTAssertTrue(r1.cleaned.contains("明天下午四点开会"))
        XCTAssertFalse(r1.cleaned.contains("五万"))
        XCTAssertTrue(r1.cleaned.contains("预算八万！"))

        let r2 = VoiceTranscriptCleaner.clean("我我我觉得就是就是这样，哈哈哈，那个项目在iPhone16上运行很稳")
        XCTAssertGreaterThanOrEqual(r2.stuttersCollapsedCount, 2)
        XCTAssertTrue(r2.cleaned.contains("我觉得就是这样"))
        XCTAssertTrue(r2.cleaned.contains("哈哈哈"), "笑声叠词不应被误删")
        XCTAssertTrue(r2.cleaned.contains("那个项目"), "实义指示代词「那个项目」不应被口水词规则误删")
        XCTAssertTrue(r2.cleaned.contains("在 iPhone16 上"))

        let r3 = VoiceTranscriptCleaner.clean("um, let us meet at 3pm wait no 4pm")
        XCTAssertGreaterThanOrEqual(r3.selfCorrectionsCount, 1)
        XCTAssertGreaterThanOrEqual(r3.removedFillersCount, 1)
        XCTAssertFalse(r3.cleaned.lowercased().hasPrefix("um"))
        XCTAssertFalse(r3.cleaned.contains("3pm"))
        XCTAssertTrue(r3.cleaned.contains("4pm"))
    }

    func testV69MarkdownBlockParserAndIncognitoMode() throws {
        // 1. 纯 Swift 结构化 Markdown & 围栏代码块解析（含流式未闭合代码块、标题、列表、引用、分割线）
        let md = """
        ## 方案结论
        > 优先采用端云 E2EE 零知识架构。

        - 零第三方依赖
        - 支持离线排版

        1. 第一步：派生密钥
        2、第二步：本地加密

        ```swift
        let key = SyncCrypto.deriveSyncKey(from: secret)
        print(key)
        ```

        ---
        普通收尾段落。
        """
        let blocks = MarkdownBlockParser.parse(md)
        XCTAssertTrue(blocks.contains(.heading(level: 2, text: "方案结论")))
        XCTAssertTrue(blocks.contains(.quote(text: "优先采用端云 E2EE 零知识架构。")))
        XCTAssertTrue(blocks.contains(.bullet(text: "零第三方依赖")))
        XCTAssertTrue(blocks.contains(.numbered(prefix: "1.", text: "第一步：派生密钥")))
        XCTAssertTrue(blocks.contains(.numbered(prefix: "2、", text: "第二步：本地加密")))
        XCTAssertTrue(blocks.contains(.divider))
        XCTAssertTrue(blocks.contains(.paragraph(text: "普通收尾段落。")))
        let codeBlock = blocks.first {
            if case .codeBlock = $0 { return true }
            return false
        }
        XCTAssertEqual(codeBlock, .codeBlock(language: "swift", code: "let key = SyncCrypto.deriveSyncKey(from: secret)\nprint(key)", isClosed: true))

        // 流式未闭合代码块绝不崩溃且标记 isClosed == false
        let streamingMD = "看下面代码：\n```python\nprint('hi')"
        let streamBlocks = MarkdownBlockParser.parse(streamingMD)
        XCTAssertEqual(streamBlocks.last, .codeBlock(language: "python", code: "print('hi')", isClosed: false))

        // 2. 系统级隐身无痕模式（Codable 往返、旧 JSON 向后兼容默认值 false、#incognito 划动命令）
        var s = LingxiSettings()
        XCTAssertFalse(s.incognitoModeEnabled)
        s.incognitoModeEnabled = true
        let encoded = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(LingxiSettings.self, from: encoded)
        XCTAssertTrue(decoded.incognitoModeEnabled)

        let legacyDecoded = try JSONDecoder().decode(LingxiSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(legacyDecoded.incognitoModeEnabled)

        XCTAssertEqual(KeyboardSwipeCommand.parse("#incognito"), .toggleIncognito)
        XCTAssertEqual(KeyboardSwipeCommand.keycapBadge(for: "#incognito"), "隐")
    }

    func testV70CommunicationGuardSmartInfoParserAndVModeV3() throws {
        // 1. 情绪防冲动温度计（0ms 离线识别与礼貌减压零误报）
        let calm = CommunicationGuardEngine.analyzeEmotion("不好意思麻烦帮我看一下周报，谢谢！")
        XCTAssertEqual(calm.level, .calm)
        XCTAssertFalse(calm.shouldWarnInKeyboard)

        let heated = CommunicationGuardEngine.analyzeEmotion("我都说了几遍了？！你到底听不懂人话吗？？？真服了你！")
        XCTAssertTrue(heated.level >= .heated)
        XCTAssertTrue(heated.shouldWarnInKeyboard)
        XCTAssertFalse(heated.matchedTriggers.isEmpty)
        XCTAssertFalse(heated.quickCalmSuggestions.isEmpty)

        // 2. 防诈与交易避坑雷达（9 类高频套路命中 + 正常会议通知零误报）
        let normalMeeting = CommunicationGuardEngine.analyzeScam("明天下午3点腾讯会议讨论架构评审，请准时参加")
        XCTAssertEqual(normalMeeting.level, .safe)
        XCTAssertFalse(normalMeeting.isRisky)

        let highScam = CommunicationGuardEngine.analyzeScam(
            "您的微信百万保障今日到期将自动扣费，请立即打开腾讯会议开启屏幕共享，并把短信验证码发我办理关闭。"
        )
        XCTAssertEqual(highScam.level, .highRisk)
        XCTAssertTrue(highScam.isRisky)
        XCTAssertGreaterThanOrEqual(highScam.hits.count, 3)

        let cautionScam = CommunicationGuardEngine.analyzeScam("房子很抢手，请先交押金500元锁定房源")
        XCTAssertEqual(cautionScam.level, .caution)
        XCTAssertTrue(cautionScam.isRisky)

        // 3. 万能收件地址 / 企业开票抬头 / 会议日程分字段拆解
        let addr = SmartInfoParser.parse("张三 138-1234-5678 山东省临沂市兰山区北京路88号科技大厦1201室")
        XCTAssertEqual(addr?.kind, .shippingAddress)
        XCTAssertEqual(addr?.fields.first(where: { $0.id == "name" })?.value, "张三")
        XCTAssertEqual(addr?.fields.first(where: { $0.id == "phone" })?.value, "13812345678")
        XCTAssertTrue(addr?.fields.first(where: { $0.id == "address" })?.value.contains("山东省临沂市") == true)

        let invoice = SmartInfoParser.parse(
            "抬头：灵犀智能科技有限公司\n税号：91371300MA3ABCD12X\n开户行：招商银行北京望京支行\n账号：110928374610901"
        )
        XCTAssertEqual(invoice?.kind, .corporateInvoice)
        XCTAssertEqual(invoice?.fields.first(where: { $0.id == "company" })?.value, "灵犀智能科技有限公司")
        XCTAssertEqual(invoice?.fields.first(where: { $0.id == "taxId" })?.value, "91371300MA3ABCD12X")
        XCTAssertEqual(invoice?.fields.first(where: { $0.id == "bankName" })?.value, "招商银行北京望京支行")
        XCTAssertEqual(invoice?.fields.first(where: { $0.id == "bankAccount" })?.value, "110928374610901")

        let meeting = SmartInfoParser.parse("明天下午14:30 腾讯会议号：888-123-456 入会密码：6688")
        XCTAssertEqual(meeting?.kind, .meetingSchedule)
        XCTAssertEqual(meeting?.fields.first(where: { $0.id == "meetingId" })?.value, "888-123-456")
        XCTAssertEqual(meeting?.fields.first(where: { $0.id == "passcode" })?.value, "6688")

        XCTAssertNil(SmartInfoParser.parse("今晚吃啥"))

        // 4. VModeToolEngine v3 全民生活速算（AA 分摊 / 折扣立省 / BMI / 日期倒计时）
        XCTAssertTrue(VModeToolEngine.isRecognizedQuery("aa368/4"))
        let aa = VModeToolEngine.candidates(forBody: "aa368/4")
        XCTAssertTrue(aa.first?.contains("92") == true)
        XCTAssertTrue(aa.first?.contains("4人") == true)

        XCTAssertTrue(VModeToolEngine.isRecognizedQuery("299z85"))
        let disc = VModeToolEngine.candidates(forBody: "299z85")
        XCTAssertTrue(disc.first?.contains("254.15") == true)
        XCTAssertTrue(disc.first?.contains("44.85") == true)

        XCTAssertTrue(VModeToolEngine.isRecognizedQuery("bmi175/68"))
        let bmi = VModeToolEngine.candidates(forBody: "bmi175/68")
        XCTAssertTrue(bmi.first?.contains("22.2") == true)
        XCTAssertTrue(bmi.first?.contains("正常标准") == true)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let baseDate = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 12)))
        XCTAssertTrue(VModeToolEngine.isRecognizedQuery("2026-12-07"))
        let countdown = VModeToolEngine.candidates(forBody: "2026-12-07", now: baseDate)
        XCTAssertEqual(countdown.first, "距 2026-12-07 还有 10 天")

        // 5. AIClient.mergeSystem 富文本 Markdown 通道与聊天纯文本通道精准分流
        let cfg = AIConfig()
        let plainSys = AIClient.mergeSystem(base: "你是助手", userPrompt: "你好", config: cfg, allowMarkdown: false)
        XCTAssertTrue(plainSys.contains(AITextSanitizer.plainTextOutputRule))
        XCTAssertFalse(plainSys.contains(AITextSanitizer.richMarkdownOutputRule))

        let richSys = AIClient.mergeSystem(base: "你是助手", userPrompt: "写段Swift代码", config: cfg, allowMarkdown: true)
        XCTAssertTrue(richSys.contains(AITextSanitizer.richMarkdownOutputRule))
        XCTAssertFalse(richSys.contains(AITextSanitizer.plainTextOutputRule))

        // 6. 扩容后 EmojiCatalog 高频中文词推荐命中
        XCTAssertFalse(EmojiCatalog.recommendForTopCandidate("辛苦了").isEmpty)
        XCTAssertFalse(EmojiCatalog.recommendForTopCandidate("暴富").isEmpty)
        XCTAssertFalse(EmojiCatalog.recommendForTopCandidate("火锅").isEmpty)
        XCTAssertFalse(EmojiCatalog.recommendForTopCandidate("绝绝子").isEmpty)
    }

    func testV71MassMarketFlagshipFeatures() throws {
        // 1. 分享链接去追踪与账号防暴露净链器（B 站 / 小红书 / 淘宝口令）
        let bili = LinkPrivacyCleaner.clean(
            "【超神技巧】https://www.bilibili.com/video/BV1xx411c7mD/?spm_id_from=333.1007&vd_source=secretuid123&p=2 复制打开哔哩哔哩"
        )
        XCTAssertTrue(bili.hasChanges)
        XCTAssertTrue(bili.hasIdentityLeakRisk)
        XCTAssertTrue(bili.removedIdentityLeakParams.contains("vd_source"))
        XCTAssertTrue(bili.strippedShareNoise)
        XCTAssertEqual(bili.extractedCleanURL, "https://www.bilibili.com/video/BV1xx411c7mD/?p=2")

        let xhs = LinkPrivacyCleaner.clean(
            "https://www.xiaohongshu.com/discovery/item/66abc123?xsec_token=keepMe&appuid=leak999&xhsshare=CopyLink"
        )
        XCTAssertTrue(xhs.hasIdentityLeakRisk)
        XCTAssertTrue(xhs.extractedCleanURL?.contains("xsec_token=keepMe") == true)
        XCTAssertFalse(xhs.extractedCleanURL?.contains("appuid") == true)

        // 2. 草稿防丢黑匣子（隐私边界 + 12 分钟续写原地更新 + 24 小时过期）
        let longDraft = "今天开会同步了三件事，第一是下周上线前把回归用例跑完，第二是整理客户报价单。"
        XCTAssertTrue(DraftRecoveryStore.shouldCapture(longDraft, isSecureField: false, isIncognito: false, enabled: true))
        XCTAssertFalse(DraftRecoveryStore.shouldCapture(longDraft, isSecureField: true, isIncognito: false, enabled: true))
        XCTAssertFalse(DraftRecoveryStore.shouldCapture(longDraft, isSecureField: false, isIncognito: true, enabled: true))
        XCTAssertFalse(DraftRecoveryStore.shouldCapture("好的收到", isSecureField: false, isIncognito: false, enabled: true))

        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let m1 = DraftRecoveryStore.merge(draft: longDraft, into: [], now: t0)
        XCTAssertEqual(m1.count, 1)
        let extendedDraft = longDraft + "第三是周四晚上一起复盘。"
        let m2 = DraftRecoveryStore.merge(draft: extendedDraft, into: m1, now: t0.addingTimeInterval(120))
        XCTAssertEqual(m2.count, 1)
        XCTAssertEqual(m2[0].text, extendedDraft)
        let expired = DraftRecoveryStore.prune(m2, now: t0.addingTimeInterval(25 * 3600))
        XCTAssertTrue(expired.isEmpty)

        // 3. 个人速填名片夹智能建卡 + v 模式秒调（vdz / vkp / vshuihao）
        let card = try XCTUnwrap(PersonalFillCardStore.buildCardFromRawText(
            "抬头：灵犀科技有限公司\n税号：91371300MA3ABCD12X\n开户行：招商银行望京支行\n账号：110928374610901"
        ))
        XCTAssertEqual(card.kind, .invoice)
        let kpCandidates = PersonalFillCardStore.vModeCandidates(forBody: "shuihao", cards: [card])
        XCTAssertEqual(kpCandidates.first, "91371300MA3ABCD12X")

        // 4. 发帖防限流 / 广告法违禁词 0ms 检测与一键合规平替
        let post = "这款面霜全网第一、100%有效还能根治敏感肌，想要直接加微信私聊转账！"
        let report = OfflineTextLinter.analyze(post)
        XCTAssertGreaterThanOrEqual(report.platformRiskCount, 4)
        XCTAssertTrue(report.hasPlatformRisks)
        XCTAssertFalse(report.platformSafeText.contains("全网第一"))
        XCTAssertFalse(report.platformSafeText.contains("加微信"))
        XCTAssertTrue(report.platformSafeText.contains("口碑前列"))
        XCTAssertTrue(report.platformSafeText.contains("站内私信"))

        // 5. 离线高情商话术口袋覆盖全 6 类场景
        XCTAssertGreaterThanOrEqual(SocialScriptBank.all.count, 50)
        for cat in SocialScriptCategory.allCases {
            XCTAssertFalse(SocialScriptBank.filter(category: cat).isEmpty)
        }
        XCTAssertFalse(SocialScriptBank.filter(query: "借钱").isEmpty)

        // 6. 选区原地包裹与大小写轮换
        XCTAssertEqual(SelectionTextTransform.wrapBookTitle.apply(to: "灵犀输入法"), "《灵犀输入法》")
        XCTAssertEqual(SelectionTextTransform.wrapBookTitle.apply(to: "《灵犀输入法》"), "灵犀输入法")
        XCTAssertEqual(SelectionTextTransform.cycleCase.apply(to: "hello world"), "Hello World")
        XCTAssertEqual(SelectionTextTransform.cycleCase.apply(to: "Hello World"), "HELLO WORLD")
        XCTAssertEqual(SelectionTextTransform.cycleCase.apply(to: "HELLO WORLD"), "hello world")

        // 7. VModeToolEngine v4（房贷月供 / 月薪换时薪 / 多币种速估 / 随机强密码）
        XCTAssertTrue(VModeToolEngine.isRecognizedQuery("dk100/30/3.5"))
        let loan = VModeToolEngine.candidates(forBody: "dk100/30/3.5")
        XCTAssertTrue(loan.first?.contains("4490.45") == true)

        XCTAssertTrue(VModeToolEngine.isRecognizedQuery("sx15000"))
        let salary = VModeToolEngine.candidates(forBody: "sx15000")
        XCTAssertTrue(salary.first?.contains("86.2") == true)

        XCTAssertTrue(VModeToolEngine.isRecognizedQuery("100usd"))
        let fx = VModeToolEngine.candidates(forBody: "100usd")
        XCTAssertTrue(fx.first?.contains("725") == true)

        XCTAssertTrue(VModeToolEngine.isPasswordQuery("pw16"))
        let pwds = VModeToolEngine.candidates(forBody: "pw16")
        XCTAssertEqual(pwds.first?.count, 16)

        // 8. 验证码 15 分钟阅后即焚（保留置顶与非验证码，清理超时未置顶验证码）
        let oldOTP = ClipboardItem(text: "您的验证码为 482910", createdAt: t0.addingTimeInterval(-1200), isPinned: false)
        let pinnedOTP = ClipboardItem(text: "您的验证码为 998877", createdAt: t0.addingTimeInterval(-1200), isPinned: true)
        let normalNote = ClipboardItem(text: "周四下午项目复盘", createdAt: t0.addingTimeInterval(-3600), isPinned: false)
        let afterPrune = ClipboardStore.pruneExpiredOTPs([oldOTP, pinnedOTP, normalNote], enabled: true, now: t0)
        XCTAssertEqual(afterPrune.count, 2)
        XCTAssertFalse(afterPrune.contains(where: { $0.id == oldOTP.id }))

        // 9. 长辈大字关怀模式一键切换与原配置无损快照还原 + /cleanurl /checkpost 斜杠宏
        var settings = LingxiSettings()
        settings.candidateFontSize = 16.5
        settings.candidateBarHeight = 50
        settings.setElderCareMode(true)
        XCTAssertTrue(settings.elderCareModeEnabled)
        XCTAssertEqual(settings.candidateFontSize, 22)
        XCTAssertEqual(settings.candidateBarHeight, 60)
        settings.setElderCareMode(false)
        XCTAssertFalse(settings.elderCareModeEnabled)
        XCTAssertEqual(settings.candidateFontSize, 16.5)
        XCTAssertEqual(settings.candidateBarHeight, 50)

        let cleanCmd = InlineAICommandDetector.detect(in: "https://www.bilibili.com/video/BV1xx/?vd_source=123 /cleanurl")
        XCTAssertEqual(cleanCmd?.offlineMacro, .cleanURL)
        let postCmd = InlineAICommandDetector.detect(in: "这款面霜全网第一加微信 /checkpost")
        XCTAssertEqual(postCmd?.offlineMacro, .platformSafe)
    }

    func testV72AICognitiveMemoryDBAndAutopilot() throws {
        // 1. 独立临时 SQLite 认知学习数据库初始化、写入行为观察、模糊音统计、词汇共鸣、长期记忆 CRUD 与防敏感过滤
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("lingxi_cog_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let dbURL = tmpDir.appendingPathComponent("ai_cognitive_memory.sqlite")
        let db = AICognitiveMemoryDB(url: dbURL)

        let nightDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 23, minute: 15)))
        for _ in 0..<4 {
            db.recordTypingObservation(TypingObservationSample(
                charsCommitted: 24,
                wordsCommitted: 10,
                backspaceCount: 4,
                typoFixHits: 2,
                englishMixWords: 3,
                digitMixCount: 2,
                emojiPickCount: 1,
                bracketPairCount: 1,
                longDraftCount: 1,
                fuzzyConfusionKey: "in_ing"
            ), now: nightDate)
        }
        db.recordVocabLearning(word: "接口联调", pinyin: "jie'kou'lian'tiao")
        db.recordVocabLearning(word: "接口联调", pinyin: "jie'kou'lian'tiao")
        db.recordVocabLearning(word: "13812345678", pinyin: "") // 敏感手机号必须被拦截
        db.recordAIInteraction(featureTag: "polish", scene: "bossClient", outcome: "copied")

        let stats = db.loadStats()
        XCTAssertEqual(stats.totalObservations, 4)
        XCTAssertEqual(stats.totalCharsObserved, 96)
        XCTAssertEqual(stats.fuzzyConfusionCounts["in_ing"], 4)
        XCTAssertEqual(stats.vocabCount, 1, "敏感手机号不得写入词汇学习库")
        XCTAssertEqual(stats.interactionCount, 1)
        XCTAssertGreaterThan(stats.nightSessionRatio, 0.9)

        let topVocab = db.fetchTopVocab(limit: 10)
        XCTAssertEqual(topVocab.first?.word, "接口联调")
        XCTAssertEqual(topVocab.first?.domain, "研发技术")
        XCTAssertEqual(topVocab.first?.learnCount, 2)

        // 2. AI 全权托管本地引擎：自动开启核心功能 + 中英混输盘古空格 + 模糊音 in/ing + 写入透明审计日志与记忆
        var settings = LingxiSettings()
        XCTAssertEqual(settings.aiAutopilotMode, .fullAutopilot, "默认应启用 AI 全权自动托管")
        settings.typoCorrectionEnabled = false
        settings.panguSpaceLetters = false
        settings.panguSpaceDigits = false
        settings.draftRecoveryEnabled = false
        settings.fuzzy.inIng = false
        settings.incognitoModeEnabled = false

        let outcome = AIAutopilotController.evaluateAndApplyLocal(
            settings: &settings,
            db: db,
            habitProfile: UserTypingHabitProfile(),
            topUserWords: ["发版回归", "需求评审"]
        )
        XCTAssertGreaterThanOrEqual(outcome.appliedCount, 5)
        XCTAssertTrue(settings.typoCorrectionEnabled)
        XCTAssertTrue(settings.panguSpaceLetters)
        XCTAssertTrue(settings.panguSpaceDigits)
        XCTAssertTrue(settings.draftRecoveryEnabled)
        XCTAssertTrue(settings.fuzzy.inIng, "in/ing 混淆 >= 3 次后 AI 必须自动开启模糊音 in↔ing")
        XCTAssertFalse(settings.incognitoModeEnabled, "AI 严禁触碰隐私红线开关")

        // 3. 决策审计日志与 1 键撤回
        let decisions = db.fetchDecisions(limit: 30)
        let inIngDecision = try XCTUnwrap(decisions.first(where: { $0.settingKey == "fuzzy.inIng" }))
        XCTAssertEqual(inIngDecision.oldValue, "关")
        XCTAssertEqual(inIngDecision.newValue, "开")
        XCTAssertFalse(inIngDecision.reverted)
        XCTAssertTrue(AIAutopilotController.revertDecision(inIngDecision, in: &settings, db: db))
        XCTAssertFalse(settings.fuzzy.inIng, "撤回后必须精确恢复原开关值")
        XCTAssertTrue(db.fetchDecisions(limit: 30).first(where: { $0.id == inIngDecision.id })?.reverted == true)

        // 4. 大模型 JSON 深度托管解析（仅白名单生效，拒绝越权隐私键）+ Prompt 记忆注入 + JSON 导出与清空
        let llmJSON = """
        ```json
        {
          "persona_digest": "偏爱中英混输的研发工程师，注重简洁直给的职场表达。",
          "summary": "已为你开启英文句首大写并沉淀 2 条专属记忆。",
          "memories": [
            {"category": "表达习惯", "key": "llm_direct", "content": "汇报沟通习惯先给结论再列要点", "confidence": 0.92}
          ],
          "setting_changes": [
            {"key": "autoCapitalizeEnglish", "value": false, "reason": "代码与技术缩写场景不强制首字母大写"},
            {"key": "incognitoModeEnabled", "value": true, "reason": "非法越权键应被严格忽略"}
          ]
        }
        ```
        """
        settings.autoCapitalizeEnglish = true
        let llmOutcome = AIAutopilotController.applyParsedLLMJSON(llmJSON, settings: &settings, db: db)
        XCTAssertTrue(llmOutcome.usedLLM)
        XCTAssertFalse(settings.autoCapitalizeEnglish, "白名单内合法决策应自动生效")
        XCTAssertFalse(settings.incognitoModeEnabled, "非白名单隐私键必须被忽略")

        let promptBlock = db.promptContextBlock(limit: 10)
        XCTAssertTrue(promptBlock.contains("偏爱中英混输的研发工程师"))
        XCTAssertTrue(promptBlock.contains("汇报沟通习惯先给结论再列要点"))

        let mems = db.fetchMemories(limit: 20)
        let directMem = try XCTUnwrap(mems.first(where: { $0.memoryKey == "llm_direct" }))
        db.togglePinMemory(id: directMem.id)
        XCTAssertTrue(db.fetchMemories(limit: 20).first(where: { $0.id == directMem.id })?.isPinned == true)
        XCTAssertNotNil(db.exportJSONSummary())

        // 5. LingxiSettings.aiAutopilotMode 旧版 JSON 向后兼容解码
        let legacyDecoded = try JSONDecoder().decode(LingxiSettings.self, from: Data("{\"keySoundEnabled\":false}".utf8))
        XCTAssertEqual(legacyDecoded.aiAutopilotMode, .fullAutopilot)

        db.clearAllData()
        XCTAssertEqual(db.loadStats().memoryCount, 0)
        XCTAssertEqual(db.loadStats().totalObservations, 0)
    }

    func testV73ObsidianSelfLearningMemoryVaultAndGraphRAG() throws {
        // 1. 解析 Obsidian [[双向链接]]（含别名与章节锚点）与 #标签
        let md = """
        # 主标题不应被识别为标签
        平时给老板发汇报时遵循 [[职场汇报原则|结论先行]]，并结合 [[研发工作流#发版阶段]] 输出要点。
        #表达习惯 #职场沟通
        """
        XCTAssertEqual(ObsidianMemoryVaultEngine.parseWikilinks(in: md), ["职场汇报原则", "研发工作流"])
        XCTAssertEqual(ObsidianMemoryVaultEngine.parseHashtags(in: md), ["表达习惯", "职场沟通"])

        // 2. 独立临时 SQLite 图谱双链建库 + 出链/反链 + 2-Hop Graph-RAG 按需召回 + 记忆强化
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("lingxi_obs_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let db = AICognitiveMemoryDB(url: tmpDir.appendingPathComponent("obsidian_vault.sqlite"))

        db.upsertVaultNote(ObsidianVaultNote(
            title: "职场汇报原则",
            folder: .persona,
            summary: "给老板汇报务必先说结论，再列 3 条数据支撑，不用感叹号",
            bodyMarkdown: "汇报遵循结论先行，衔接 [[研发发版节奏]]。 #职场 #汇报",
            tags: ["职场", "汇报"],
            strength: 0.85,
            source: "ai_llm"
        ))
        db.upsertVaultNote(ObsidianVaultNote(
            title: "研发发版节奏",
            folder: .wiki,
            summary: "每周四晚回归测试并整理发版变更清单",
            bodyMarkdown: "核心工作节奏：周四晚回归，关联 [[职场汇报原则]]。 #研发",
            tags: ["研发"],
            strength: 0.78,
            source: "ai_llm"
        ))
        db.upsertVaultNote(ObsidianVaultNote(
            title: "周末露营清单",
            folder: .wiki,
            summary: "帐篷与手冲咖啡器材",
            bodyMarkdown: "户外休闲装备记录 #生活",
            tags: ["生活"],
            strength: 0.60,
            source: "user_manual"
        ))

        let outEdges = db.fetchOutlinks(forSlug: "职场汇报原则")
        let backEdges = db.fetchBacklinks(forSlug: "研发发版节奏")
        XCTAssertTrue(outEdges.contains(where: { $0.toSlug == "研发发版节奏" }))
        XCTAssertTrue(backEdges.contains(where: { $0.fromSlug == "职场汇报原则" }))

        // 查询「给老板写周报」应直接命中 [[职场汇报原则]] 并经 1-Hop 图谱召回 [[研发发版节奏]]，排在无关的 [[周末露营清单]] 前面
        let recalled = ObsidianMemoryVaultEngine.recallGraphNotes(
            query: "帮我给老板写本周工作汇报",
            scene: "老板客户",
            db: db,
            limit: 3,
            reinforce: false
        )
        XCTAssertEqual(recalled.first?.note.title, "职场汇报原则")
        XCTAssertTrue(recalled.prefix(2).contains(where: { $0.note.title == "研发发版节奏" }))
        let ctxBlock = ObsidianMemoryVaultEngine.recallPromptContextBlock(query: "给老板写汇报", scene: "老板客户", db: db, limit: 3)
        XCTAssertTrue(ctxBlock.contains("[[职场汇报原则]]"))

        // 3. 用用户 API 提炼结果 JSON 解析（新增双链原子笔记 + 重复合并重定向反链 + 安全白名单调优 + log.md 留痕 + 隐私脱敏）
        var settings = LingxiSettings()
        settings.aiAutopilotMode = .fullAutopilot
        settings.panguSpaceLetters = false
        settings.incognitoModeEnabled = false

        let apiJSON = """
        ```json
        {
          "persona_digest": "偏重效率与数据化表达的 iOS 研发负责人。",
          "summary": "提炼 1 篇双链笔记、合并 1 组重复节点并开启中英盘古空格。",
          "notes_to_upsert": [
            {
              "title": "极简回复美学",
              "folder": "persona",
              "summary": "杜绝官腔客套，保留关键数字与截止时间，手机 13812345678 应脱敏",
              "body_markdown": "所有回复保持干练，配合 [[职场汇报原则]] 使用。联系 13812345678 必须被脱敏。 #表达习惯",
              "tags": ["表达习惯"],
              "links": [{"to": "职场汇报原则", "relation": "prefers"}]
            }
          ],
          "notes_to_merge": [
            {
              "keep_title": "研发发版节奏",
              "drop_title": "周末露营清单",
              "merged_summary": "周四晚回归与周末复盘安排",
              "merged_body": "统一合并节奏记录，关联 [[职场汇报原则]]。"
            }
          ],
          "setting_changes": [
            {"key": "panguSpaceLetters", "value": true, "reason": "高频技术文档中英混输"},
            {"key": "incognitoModeEnabled", "value": true, "reason": "越权隐私键必须被拦截"}
          ]
        }
        ```
        """
        let outcome = ObsidianMemoryVaultEngine.applyConsolidationJSON(apiJSON, settings: &settings, db: db)
        XCTAssertTrue(outcome.usedLLM)
        XCTAssertEqual(outcome.upsertedNotesCount, 1)
        XCTAssertEqual(outcome.mergedNotesCount, 1)
        XCTAssertEqual(outcome.appliedSettingsCount, 1)
        XCTAssertTrue(settings.panguSpaceLetters)
        XCTAssertFalse(settings.incognitoModeEnabled, "越权隐私开关严禁被 API 修改")

        let aesthetics = try XCTUnwrap(db.fetchVaultNote(slug: "极简回复美学"))
        XCTAssertFalse(aesthetics.bodyMarkdown.contains("13812345678"), "笔记落库前必须经 AIPrivacyShield 脱敏敏感手机号")
        XCTAssertNil(db.fetchVaultNote(slug: "周末露营清单"), "被合并的旧笔记应已移除")
        XCTAssertFalse(db.fetchEvolutionLogs(limit: 20).isEmpty, "log.md 演化日志必须留痕")

        // 4. 真实 Obsidian YAML Frontmatter + 反向链接 + 整库 Markdown 导出校验
        let exportedVault = ObsidianMemoryVaultEngine.exportFullObsidianMarkdownVault(db: db)
        XCTAssertTrue(exportedVault.contains("title: \"极简回复美学\""))
        XCTAssertTrue(exportedVault.contains("## 反向链接 (Backlinks)"))
        XCTAssertTrue(exportedVault.contains("FILE: log.md"))

        // 5. Ebbinghaus 记忆强化与衰减单调性校验
        let now = Date()
        let fresh = ObsidianVaultNote(title: "新记忆", summary: "s", bodyMarkdown: "b", strength: 0.8, recallCount: 0, updatedAt: Int(now.timeIntervalSince1970))
        let stale = ObsidianVaultNote(title: "久远记忆", summary: "s", bodyMarkdown: "b", strength: 0.8, recallCount: 0, updatedAt: Int(now.addingTimeInterval(-60 * 86400).timeIntervalSince1970))
        XCTAssertGreaterThan(ObsidianMemoryVaultEngine.effectiveStrength(for: fresh, now: now), ObsidianMemoryVaultEngine.effectiveStrength(for: stale, now: now))
    }
}
