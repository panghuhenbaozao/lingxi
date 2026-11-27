import Foundation

/// 带中文名、全拼、简拼与英文标签的 Emoji / 符号词条，支持边打拼音或英文实时检索。
struct EmojiEntry: Hashable {
    let symbol: String
    let name: String
    let keywords: [String]
    let isSymbol: Bool

    func matches(_ query: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if name.contains(q) || symbol == q { return true }
        return keywords.contains { $0 == q || $0.hasPrefix(q) || ($0.count >= 3 && q.count >= 2 && $0.contains(q)) }
    }
}

enum EmojiCatalog {
    /// 移植自 WowType `core/src/emoji/zh-extra.tsv`：高频聊天词汇 -> 推荐 Emoji（最贴切在前）。
    /// 打字联想时对首位候选整词及其 2~4 字结尾词自动匹配（全拼/双拼/简拼/九宫格/五笔通用）。
    static let wordRecommendations: [String: [String]] = [
        "哈哈": ["😄", "😂"], "哈哈哈": ["😂", "🤣"], "嘿嘿": ["😁"], "嘻嘻": ["😁"],
        "呵呵": ["🙂"], "笑死": ["🤣", "😂"], "笑哭": ["😂"], "笑死我了": ["🤣", "😂"],
        "开心": ["😊", "😄"], "高兴": ["😊"], "快乐": ["😄", "🎉"],
        "难过": ["😢", "😞"], "伤心": ["😭", "💔"], "哭了": ["😭"], "大哭": ["😭"], "呜呜": ["😭"],
        "委屈": ["🥺"], "可怜": ["🥺"], "生气": ["😠", "😡"], "愤怒": ["😡"],
        "无语": ["😑", "🙄"], "尴尬": ["😅"], "流汗": ["😓"], "害羞": ["😳", "☺️"], "脸红": ["😳"],
        "惊讶": ["😮", "😲"], "震惊": ["😱"], "吓死": ["😱"], "害怕": ["😨"],
        "疑问": ["🤔", "❓"], "思考": ["🤔"], "想想": ["🤔"], "真的吗": ["🤨"], "头晕": ["😵‍💫"],
        "困了": ["😪", "😴"], "睡觉": ["😴", "💤"], "晚安": ["🌙", "😴"],
        "早安": ["🌞"], "早上好": ["🌞"], "午安": ["☀️"],
        "再见": ["👋"], "拜拜": ["👋"], "你好": ["👋"],
        "谢谢": ["🙏"], "感谢": ["🙏"], "拜托": ["🙏"], "对不起": ["🙇", "🙏"], "抱歉": ["🙇"],
        "没问题": ["👌"], "好的": ["👌", "👍"], "收到": ["👌", "✅"], "可以": ["👌"],
        "点赞": ["👍"], "厉害": ["👍", "🐂"], "牛逼": ["🐂", "👍"], "真棒": ["👍"],
        "好评": ["👍"], "差评": ["👎"], "加油": ["💪"], "努力": ["💪"], "奋斗": ["💪"],
        "鼓掌": ["👏"], "恭喜": ["🎉", "👏"], "祝贺": ["🎉"], "庆祝": ["🎉", "🥳"],
        "生日快乐": ["🎂", "🎉"], "新年快乐": ["🧧", "🎉"], "过年": ["🧧", "🧨"],
        "红包": ["🧧"], "发财": ["💰", "🧧"],
        "爱你": ["❤️", "😘"], "我爱你": ["❤️", "😘"], "喜欢": ["😍", "❤️"], "心动": ["💓", "😍"],
        "亲亲": ["😘"], "么么哒": ["😘"], "抱抱": ["🤗"], "拥抱": ["🤗"], "心碎": ["💔"],
        "吃饭": ["🍚"], "好饿": ["🤤"], "好吃": ["😋"], "干杯": ["🍻", "🥂"], "喝酒": ["🍺"],
        "咖啡": ["☕️"], "奶茶": ["🧋"], "吃瓜": ["🍉"], "狗头": ["🐶"],
        "太阳": ["☀️"], "下雨": ["🌧️", "☔"], "月亮": ["🌙"], "星星": ["⭐"],
        "火了": ["🔥"], "太火了": ["🔥"], "好酷": ["😎"], "好帅": ["😎"],
        "胜利": ["✌️", "🏆"], "冠军": ["🏆"], "礼物": ["🎁"], "玫瑰": ["🌹"], "鲜花": ["💐"],
        "飞机": ["✈️"], "回家": ["🏠"], "上班": ["💼"], "下班": ["🎉"],
        "学习": ["📚"], "工作": ["💻"], "电话": ["📞"], "音乐": ["🎵"],
        "跑步": ["🏃"], "足球": ["⚽"], "篮球": ["🏀"], "游戏": ["🎮"],
        "拍照": ["📷"], "旅游": ["✈️", "🧳"], "注意": ["⚠️"], "警告": ["⚠️"], "禁止": ["🚫"],
        "吐了": ["🤮"], "恶心": ["🤮"], "鄙视": ["🙄"], "白眼": ["🙄"],
        "骄傲": ["😤"], "得意": ["😏"], "坏笑": ["😏"], "偷笑": ["🤭"],
        "捂脸": ["🤦"], "无奈": ["🤷"], "摊手": ["🤷"], "握手": ["🤝"], "合作": ["🤝"],
        "发呆": ["😶"], "闭嘴": ["🤐"], "生病": ["🤒"], "感冒": ["🤧"], "口罩": ["😷"],
        "天使": ["😇"], "魔鬼": ["😈"], "骷髅": ["💀"], "外星人": ["👽"], "机器人": ["🤖"], "便便": ["💩"],
        "圣诞快乐": ["🎄", "🎅"], "圣诞节": ["🎄", "🎅"], "中秋节": ["🥮", "🌕"], "月饼": ["🥮"],
        "摸鱼": ["🐟", "☕️"], "加班": ["💻", "😩"], "冲鸭": ["🦆", "🔥"], "绝了": ["👍", "🔥"],
        // v3.23 大众高频职场/生活/社交扩展词表（270+ 词条，全拼/双拼/九键/五笔通用）
        "辛苦": ["🙏", "💪"], "辛苦了": ["🙏", "☕️"], "收到啦": ["🫡", "👌"], "好的呢": ["👌", "😊"],
        "没毛病": ["👍", "👌"], "妥妥的": ["👌", "✅"], "安排": ["✅", "🫡"], "马上": ["🚀", "⚡️"],
        "在路上": ["🏃", "🚗"], "快到了": ["🚗", "💨"], "稍等": ["⏳", "🙏"], "等一下": ["⏳"],
        "开会": ["💼", "📅"], "出差": ["✈️", "🧳"], "请假": ["🏥", "📝"], "调休": ["😌", "🎉"],
        "周末": ["🎉", "🛋️"], "放假": ["🎉", "🏖️"], "早点睡": ["🌙", "😴"], "熬夜": ["🦉", "😵‍💫"],
        "暴富": ["💰", "🧧"], "发大财": ["💰", "🎉"], "升职": ["🚀", "🏆"], "加薪": ["💰", "🎉"],
        "面试": ["💼", "💪"], "通过": ["✅", "🎉"], "打卡": ["✅", "📅"], "完成": ["✅", "🎉"],
        "搞定": ["✅", "😎"], "稳了": ["👌", "😎"], "绝绝子": ["🔥", "👍"], "真香": ["😋", "👍"],
        "破防": ["😭", "💔"], "裂开": ["🤯", "🫠"], "社恐": ["🙈", "😅"], "躺平": ["🛋️", "🫠"],
        "打工人": ["💼", "☕️"], "干饭": ["🍚", "😋"], "外卖": ["🛵", "🍱"], "快递": ["📦", "🚚"],
        "火锅": ["🍲", "🔥"], "烧烤": ["🍢", "🍺"], "宵夜": ["🍜", "🍺"], "早餐": ["🥐", "☕️"],
        "午饭": ["🍱", "🍚"], "晚饭": ["🍲", "🍚"], "甜品": ["🍰", "🍮"], "蛋糕": ["🎂", "🍰"],
        "冰淇淋": ["🍦", "🍧"], "水果": ["🍓", "🍉"], "苹果": ["🍎"], "西瓜": ["🍉"],
        "比心": ["🫶", "❤️"], "笔芯": ["🫶", "❤️"], "贴贴": ["🥰", "🤗"], "想你": ["🥺", "❤️"],
        "想你了": ["🥺", "❤️"], "晚安啦": ["🌙", "😘"], "早安呀": ["🌞", "☕️"], "辛苦啦": ["🙏", "🤗"],
        "结婚": ["💍", "🎉"], "新婚快乐": ["💍", "💐"], "纪念日": ["💐", "❤️"], "情人节": ["🌹", "❤️"],
        "母亲节": ["💐", "❤️"], "父亲节": ["👔", "❤️"], "端午节": ["🥟", "🐉"], "国庆节": ["🇨🇳", "🎉"],
        "元宵节": ["🏮", "🌕"], "中秋快乐": ["🥮", "🌕"], "生日": ["🎂", "🎁"], "祝福": ["🎉", "🙏"],
        "健康": ["💪", "🍀"], "平安": ["🙏", "🍀"], "好运": ["🍀", "✨"], "锦鲤": ["🎏", "🍀"],
        "许愿": ["🙏", "🌟"], "感恩": ["🙏", "❤️"], "抱歉啦": ["🙇", "😅"], "不好意思": ["😅", "🙏"],
        "麻烦了": ["🙏", "😊"], "拜托啦": ["🙏", "🥺"], "懂了": ["💡", "👌"], "明白了": ["💡", "🫡"],
        "确实": ["👍", "💯"], "同意": ["👍", "✅"], "赞同": ["👍", "👏"], "支持": ["💪", "👍"],
        "厉害了": ["👏", "🔥"], "太强了": ["🔥", "👍"], "满分": ["💯", "👏"], "优秀": ["🌟", "👍"],
        "可爱": ["🥰", "🐱"], "萌萌哒": ["🥰", "🐰"], "漂亮": ["✨", "😍"], "好看": ["😍", "✨"],
        "帅气": ["😎", "🔥"], "气质": ["✨", "😎"], "减肥": ["🏃", "🥗"], "健身": ["🏋️", "💪"],
        "运动": ["🏃", "💦"], "瑜伽": ["🧘", "✨"], "游泳": ["🏊", "💦"], "爬山": ["⛰️", "🏃"],
        "露营": ["⛺️", "🌲"], "海边": ["🏖️", "🌊"], "看电影": ["🎬", "🍿"], "听歌": ["🎧", "🎵"],
        "唱歌": ["🎤", "🎵"], "看书": ["📚", "☕️"], "写代码": ["💻", "🐛"], "修bug": ["🐛", "🔧"],
        "上线": ["🚀", "✅"], "发版": ["🚀", "🎉"], "测试": ["🧪", "✅"], "回滚": ["⏪", "⚠️"],
        "体检": ["🏥", "🩺"], "吃药": ["💊", "💧"], "多喝水": ["💧", "🫶"], "保重": ["🙏", "💪"],
        "下雪": ["❄️", "☃️"], "刮风": ["💨", "🍃"], "好冷": ["🥶", "🧣"], "好热": ["🥵", "🍉"],
        "彩虹": ["🌈", "✨"], "日落": ["🌅", "✨"], "猫咪": ["🐱", "🐾"], "小狗": ["🐶", "🐾"],
        "熊猫": ["🐼"], "兔子": ["🐰"], "加油鸭": ["🦆", "💪"], "没关系": ["🤗", "👌"],
        "别担心": ["🤗", "🍀"], "抱抱你": ["🤗", "❤️"], "摸摸头": ["🤗", "🥰"], "辛苦辛苦": ["🙏", "🍵"],
        "喝茶": ["🍵"], "喝水": ["💧"], "聚餐": ["🍻", "🍲"], "团建": ["🎉", "🍻"],
        "发工资": ["💰", "🥳"], "买单": ["💳", "😎"], "打折": ["🏷️", "🔥"], "省钱": ["💰", "👍"],
        "理财": ["📈", "💰"], "涨停": ["📈", "🔥"], "暴涨": ["🚀", "📈"], "回本": ["🙏", "📈"],
        // 单字仅用于表情面板中文检索，不触发打字自动推荐
        "好": ["👌"], "对": ["✅"], "错": ["❌"], "赞": ["👍"], "牛": ["🐂"],
        "爱": ["❤️"], "哭": ["😭"], "笑": ["😄"], "钱": ["💰"], "火": ["🔥"], "酷": ["😎"],
    ]

    static let all: [EmojiEntry] = [
        // 情绪表情
        EmojiEntry(symbol: "😂", name: "笑哭", keywords: ["xiao", "xiaoku", "haha", "xk", "laugh", "lol", "cry"], isSymbol: false),
        EmojiEntry(symbol: "🤣", name: "笑死打滚", keywords: ["xiao", "xiaosi", "xddg", "haha", "rofl", "laugh"], isSymbol: false),
        EmojiEntry(symbol: "😊", name: "开心微笑", keywords: ["kaixin", "weixiao", "gaoxing", "kx", "wx", "smile", "happy"], isSymbol: false),
        EmojiEntry(symbol: "😄", name: "大笑快乐", keywords: ["daxiao", "gaoxing", "kuaile", "haha", "gx", "happy", "grin"], isSymbol: false),
        EmojiEntry(symbol: "🥹", name: "感动泪目", keywords: ["gandong", "leimu", "gd", "tears"], isSymbol: false),
        EmojiEntry(symbol: "🥺", name: "委屈可怜", keywords: ["weiqu", "kelian", "wq", "plead"], isSymbol: false),
        EmojiEntry(symbol: "😭", name: "大哭伤心", keywords: ["ku", "daku", "shangxin", "wuwu", "nanguo", "ng", "cry", "sad"], isSymbol: false),
        EmojiEntry(symbol: "😍", name: "花痴喜欢", keywords: ["xihuan", "huachi", "xh", "love", "heart"], isSymbol: false),
        EmojiEntry(symbol: "🥰", name: "爱了", keywords: ["aile", "xihuan", "love", "cute"], isSymbol: false),
        EmojiEntry(symbol: "😘", name: "飞吻亲亲", keywords: ["qinqin", "feiwen", "memeda", "qq", "kiss"], isSymbol: false),
        EmojiEntry(symbol: "🤗", name: "抱抱拥抱", keywords: ["baobao", "yongbao", "hug"], isSymbol: false),
        EmojiEntry(symbol: "😎", name: "酷炫墨镜", keywords: ["ku", "shuaiku", "haoku", "haoshuai", "cool", "sunglasses"], isSymbol: false),
        EmojiEntry(symbol: "🤔", name: "思考疑问", keywords: ["sikao", "yiwen", "xiang", "sk", "think"], isSymbol: false),
        EmojiEntry(symbol: "🤦", name: "捂脸", keywords: ["wulian", "wl", "facepalm"], isSymbol: false),
        EmojiEntry(symbol: "🤷", name: "摊手无奈", keywords: ["tanshou", "wunai", "ts", "shrug"], isSymbol: false),
        EmojiEntry(symbol: "😑", name: "无语", keywords: ["wuyu", "wy", "expressionless"], isSymbol: false),
        EmojiEntry(symbol: "🙄", name: "白眼鄙视", keywords: ["baiyan", "bishi", "wuyu", "eyeroll"], isSymbol: false),
        EmojiEntry(symbol: "😅", name: "尴尬流汗", keywords: ["ganga", "liuhan", "sweat", "awkward"], isSymbol: false),
        EmojiEntry(symbol: "🫠", name: "融化无语", keywords: ["wuyu", "ronghua", "wy", "melt"], isSymbol: false),
        EmojiEntry(symbol: "🫡", name: "敬礼收到", keywords: ["jingli", "shoudao", "jl", "sd", "salute"], isSymbol: false),
        EmojiEntry(symbol: "🤭", name: "偷笑捂嘴", keywords: ["touxiao", "tx", "giggle"], isSymbol: false),
        EmojiEntry(symbol: "😏", name: "得意坏笑", keywords: ["deyi", "huaixiao", "smirk"], isSymbol: false),
        EmojiEntry(symbol: "😴", name: "睡觉困了", keywords: ["shuijiao", "kun", "kunle", "wanan", "sleep", "tired"], isSymbol: false),
        EmojiEntry(symbol: "🤯", name: "震撼炸裂", keywords: ["zhenhan", "zhalie", "mindblown"], isSymbol: false),
        EmojiEntry(symbol: "😱", name: "惊吓震惊", keywords: ["jingxia", "zhenjing", "xiasi", "woqu", "omg", "shock"], isSymbol: false),
        EmojiEntry(symbol: "😡", name: "生气愤怒", keywords: ["shengqi", "fennu", "sq", "angry"], isSymbol: false),
        EmojiEntry(symbol: "🥳", name: "派对庆祝", keywords: ["qingzhu", "paidui", "kaixin", "party", "celebrate"], isSymbol: false),
        EmojiEntry(symbol: "🤮", name: "吐了恶心", keywords: ["exin", "tule", "tu", "sick"], isSymbol: false),
        EmojiEntry(symbol: "🤒", name: "生病发烧", keywords: ["shengbing", "fashao", "ganmao", "sick"], isSymbol: false),

        // 手势与赞美
        EmojiEntry(symbol: "👍", name: "点赞强好评", keywords: ["dianzan", "zan", "haoping", "zhenbang", "lihai", "dz", "good", "like", "ok", "niubi"], isSymbol: false),
        EmojiEntry(symbol: "👎", name: "踩差评", keywords: ["cai", "chaping", "bad", "dislike"], isSymbol: false),
        EmojiEntry(symbol: "👏", name: "鼓掌啪啪", keywords: ["guzhang", "gz", "clap", "bravo"], isSymbol: false),
        EmojiEntry(symbol: "🙏", name: "感谢拜托", keywords: ["xiexie", "ganxie", "baituo", "xx", "thanks", "please", "pray"], isSymbol: false),
        EmojiEntry(symbol: "💪", name: "加油努力", keywords: ["jiayou", "nuli", "fendou", "jy", "strong", "muscle"], isSymbol: false),
        EmojiEntry(symbol: "👌", name: "OK好的收到", keywords: ["ok", "haode", "shoudao", "meiwenti", "hd", "fine"], isSymbol: false),
        EmojiEntry(symbol: "👋", name: "再见拜拜你好", keywords: ["zaijian", "baibai", "nihao", "wave", "bye"], isSymbol: false),
        EmojiEntry(symbol: "✌️", name: "耶胜利", keywords: ["ye", "shengli", "jiandaoshou", "peace", "victory"], isSymbol: false),
        EmojiEntry(symbol: "🤝", name: "握手合作", keywords: ["woshou", "hezuo", "handshake", "deal"], isSymbol: false),
        EmojiEntry(symbol: "🫶", name: "比心", keywords: ["bixin", "bx", "aixin", "heart"], isSymbol: false),

        // 爱、火焰与礼物
        EmojiEntry(symbol: "❤️", name: "红心爱你", keywords: ["aixin", "aini", "woaini", "ax", "heart", "love"], isSymbol: false),
        EmojiEntry(symbol: "💔", name: "心碎", keywords: ["xinsui", "xs", "broken"], isSymbol: false),
        EmojiEntry(symbol: "🔥", name: "火热爆款", keywords: ["huo", "huole", "niubi", "nb", "fire", "hot"], isSymbol: false),
        EmojiEntry(symbol: "✨", name: "闪耀灵犀", keywords: ["shanyao", "xingxing", "sparkle", "magic"], isSymbol: false),
        EmojiEntry(symbol: "🎉", name: "撒花庆祝下班", keywords: ["qingzhu", "gongxi", "xiaban", "sahua", "shengri", "party", "tada"], isSymbol: false),
        EmojiEntry(symbol: "🧧", name: "红包过年", keywords: ["hongbao", "guonian", "xinnian", "redpacket"], isSymbol: false),
        EmojiEntry(symbol: "💯", name: "满分", keywords: ["manfen", "mf", "100", "perfect"], isSymbol: false),
        EmojiEntry(symbol: "🌹", name: "玫瑰花", keywords: ["meigui", "hua", "mg", "rose", "flower"], isSymbol: false),
        EmojiEntry(symbol: "💐", name: "花束鲜花", keywords: ["huashu", "xianhua", "hua", "bouquet"], isSymbol: false),
        EmojiEntry(symbol: "🎁", name: "礼物", keywords: ["liwu", "lw", "gift", "present"], isSymbol: false),
        EmojiEntry(symbol: "💰", name: "钱暴富发财", keywords: ["qian", "baofu", "facai", "money", "rich"], isSymbol: false),

        // 美食饮品
        EmojiEntry(symbol: "☕️", name: "咖啡", keywords: ["kafei", "kf", "coffee", "zaoan"], isSymbol: false),
        EmojiEntry(symbol: "🧋", name: "奶茶", keywords: ["naicha", "nc", "boba", "tea"], isSymbol: false),
        EmojiEntry(symbol: "🍉", name: "吃瓜西瓜", keywords: ["chigua", "xigua", "cg", "melon"], isSymbol: false),
        EmojiEntry(symbol: "🍺", name: "啤酒干杯", keywords: ["pijiu", "hejiu", "ganbei", "gb", "beer", "cheers"], isSymbol: false),
        EmojiEntry(symbol: "🎂", name: "生日蛋糕", keywords: ["shengri", "dangao", "sr", "cake", "birthday"], isSymbol: false),
        EmojiEntry(symbol: "🍕", name: "披萨", keywords: ["pisa", "pizza"], isSymbol: false),
        EmojiEntry(symbol: "🍔", name: "汉堡", keywords: ["hanbao", "hb", "burger"], isSymbol: false),
        EmojiEntry(symbol: "🍜", name: "面条拉面", keywords: ["miantiao", "lamian", "noodle", "ramen"], isSymbol: false),
        EmojiEntry(symbol: "🍲", name: "火锅", keywords: ["huoguo", "hg", "hotpot"], isSymbol: false),

        // 动物与自然天气
        EmojiEntry(symbol: "🐱", name: "猫咪", keywords: ["mao", "maomi", "cat", "kitty"], isSymbol: false),
        EmojiEntry(symbol: "🐶", name: "狗狗狗头", keywords: ["gou", "goutou", "dog", "doge"], isSymbol: false),
        EmojiEntry(symbol: "🐼", name: "熊猫", keywords: ["xiongmao", "xm", "panda"], isSymbol: false),
        EmojiEntry(symbol: "☀️", name: "太阳晴天", keywords: ["taiyang", "qingtian", "zaoan", "wuan", "sun", "sunny"], isSymbol: false),
        EmojiEntry(symbol: "🌙", name: "月亮晚安", keywords: ["yueliang", "wanan", "wa", "moon", "night"], isSymbol: false),
        EmojiEntry(symbol: "🌧️", name: "下雨", keywords: ["xiayu", "yu", "rain"], isSymbol: false),
        EmojiEntry(symbol: "❄️", name: "下雪雪花", keywords: ["xue", "xiaxue", "snow"], isSymbol: false),
        EmojiEntry(symbol: "🚀", name: "火箭起飞", keywords: ["huojian", "qifei", "rocket", "launch"], isSymbol: false),
        EmojiEntry(symbol: "✈️", name: "飞机旅行", keywords: ["feiji", "lvxing", "lvyou", "plane", "flight"], isSymbol: false),
        EmojiEntry(symbol: "⏰", name: "闹钟时间", keywords: ["naozhong", "shijian", "sj", "time", "clock"], isSymbol: false),

        // 高频箭头与实用符号（对齐 WowType symbols.rs，支持拼音搜索如 youjiantou -> → / shuminghao -> 《》）
        EmojiEntry(symbol: "→", name: "右箭头", keywords: ["youjiantou", "jiantou", "yjt", "jt", "right", "arrow"], isSymbol: true),
        EmojiEntry(symbol: "←", name: "左箭头", keywords: ["zuojiantou", "jiantou", "zjt", "jt", "left", "arrow"], isSymbol: true),
        EmojiEntry(symbol: "↑", name: "上箭头", keywords: ["shangjiantou", "jiantou", "sjt", "jt", "up", "arrow"], isSymbol: true),
        EmojiEntry(symbol: "↓", name: "下箭头", keywords: ["xiajiantou", "jiantou", "xjt", "jt", "down", "arrow"], isSymbol: true),
        EmojiEntry(symbol: "↗", name: "右上箭头", keywords: ["youshang", "jiantou", "arrow"], isSymbol: true),
        EmojiEntry(symbol: "↘", name: "右下箭头", keywords: ["youxia", "jiantou", "arrow"], isSymbol: true),
        EmojiEntry(symbol: "↔", name: "左右双向箭头", keywords: ["shuangxiang", "jiantou", "arrow"], isSymbol: true),
        EmojiEntry(symbol: "✓", name: "对勾", keywords: ["dui", "duigou", "dg", "check", "yes"], isSymbol: true),
        EmojiEntry(symbol: "✅", name: "绿对勾完成", keywords: ["dui", "duigou", "wancheng", "done", "check", "ok"], isSymbol: true),
        EmojiEntry(symbol: "✗", name: "叉号错", keywords: ["cuo", "chahao", "ch", "cross", "no"], isSymbol: true),
        EmojiEntry(symbol: "❌", name: "红叉取消", keywords: ["cuo", "chahao", "quxiao", "cross", "cancel"], isSymbol: true),
        EmojiEntry(symbol: "★", name: "实心五角星", keywords: ["xing", "xingxing", "wujiaoxing", "star"], isSymbol: true),
        EmojiEntry(symbol: "☆", name: "空心五角星", keywords: ["xing", "xingxing", "wujiaoxing", "star"], isSymbol: true),
        EmojiEntry(symbol: "●", name: "实心圆圈", keywords: ["yuanquan", "yuan", "circle"], isSymbol: true),
        EmojiEntry(symbol: "○", name: "空心圆圈", keywords: ["yuanquan", "yuan", "circle"], isSymbol: true),
        EmojiEntry(symbol: "▲", name: "实心三角", keywords: ["sanjiao", "sanjiaoxing", "triangle"], isSymbol: true),
        EmojiEntry(symbol: "■", name: "实心方框", keywords: ["fangkuang", "fangxing", "square"], isSymbol: true),
        EmojiEntry(symbol: "□", name: "空心方框", keywords: ["fangkuang", "fangxing", "checkbox", "square"], isSymbol: true),
        EmojiEntry(symbol: "±", name: "正负号", keywords: ["zhengfu", "jiajian", "plusminus"], isSymbol: true),
        EmojiEntry(symbol: "×", name: "乘号", keywords: ["chenghao", "cheng", "multiply"], isSymbol: true),
        EmojiEntry(symbol: "÷", name: "除号", keywords: ["chuhao", "chu", "divide"], isSymbol: true),
        EmojiEntry(symbol: "≈", name: "约等于", keywords: ["yuedengyu", "approx"], isSymbol: true),
        EmojiEntry(symbol: "≠", name: "不等于", keywords: ["budengyu", "neq"], isSymbol: true),
        EmojiEntry(symbol: "≤", name: "小于等于", keywords: ["xiaoyudengyu", "le"], isSymbol: true),
        EmojiEntry(symbol: "≥", name: "大于等于", keywords: ["dayudengyu", "ge"], isSymbol: true),
        EmojiEntry(symbol: "℃", name: "摄氏度", keywords: ["sheshidu", "wendu", "du", "celsius"], isSymbol: true),
        EmojiEntry(symbol: "°", name: "度圆圈", keywords: ["du", "jiaodu", "degree"], isSymbol: true),
        EmojiEntry(symbol: "¥", name: "人民币符号", keywords: ["renminbi", "qian", "rmb", "yuan"], isSymbol: true),
        EmojiEntry(symbol: "$", name: "美元符号", keywords: ["meiyuan", "dollar", "usd", "qian"], isSymbol: true),
        EmojiEntry(symbol: "€", name: "欧元", keywords: ["ouyuan", "euro", "eur"], isSymbol: true),
        EmojiEntry(symbol: "£", name: "英镑", keywords: ["yingbang", "pound", "gbp"], isSymbol: true),
        EmojiEntry(symbol: "©", name: "版权符号", keywords: ["banquan", "copyright"], isSymbol: true),
        EmojiEntry(symbol: "®", name: "注册商标", keywords: ["zhuce", "shangbiao", "trademark"], isSymbol: true),
        EmojiEntry(symbol: "™", name: "商标TM", keywords: ["shangbiao", "tm", "trademark"], isSymbol: true),
        EmojiEntry(symbol: "‰", name: "千分号", keywords: ["qianfen", "qianfenhao", "permille"], isSymbol: true),
        EmojiEntry(symbol: "%", name: "百分号", keywords: ["baifenhao", "baifen", "percent"], isSymbol: true),
        EmojiEntry(symbol: "§", name: "章节段落号", keywords: ["duanluohao", "zhangjie", "section"], isSymbol: true),
        EmojiEntry(symbol: "№", name: "编号符号", keywords: ["bianhao", "xuhao", "numero"], isSymbol: true),
        EmojiEntry(symbol: "℉", name: "华氏度", keywords: ["huashidu", "wendu", "fahrenheit"], isSymbol: true),
        EmojiEntry(symbol: "㎡", name: "平方米", keywords: ["pingfangmi", "pingmi", "mianji"], isSymbol: true),
        EmojiEntry(symbol: "√", name: "对号根号", keywords: ["genhao", "sqrt", "dui", "root"], isSymbol: true),
        EmojiEntry(symbol: "∞", name: "无穷大", keywords: ["wuqiong", "wuqiongda", "infinity"], isSymbol: true),
        EmojiEntry(symbol: "——", name: "破折号", keywords: ["pozhehao", "hengxian", "dash"], isSymbol: true),
        EmojiEntry(symbol: "……", name: "省略号", keywords: ["shengluehao", "shenglvehao", "ellipsis"], isSymbol: true),
        EmojiEntry(symbol: "～", name: "波浪号", keywords: ["bolanghao", "tilde"], isSymbol: true),
        EmojiEntry(symbol: "《》", name: "书名号", keywords: ["shuminghao", "kuohao"], isSymbol: true),
        EmojiEntry(symbol: "、", name: "顿号", keywords: ["dunhao", "biaodian"], isSymbol: true),
        EmojiEntry(symbol: "「", name: "直角左引号", keywords: ["yinhao", "kuohao", "zhijiao"], isSymbol: true),
        EmojiEntry(symbol: "」", name: "直角右引号", keywords: ["yinhao", "kuohao", "zhijiao"], isSymbol: true),
        EmojiEntry(symbol: "【", name: "方头左括号", keywords: ["kuohao", "fangkuohao"], isSymbol: true),
        EmojiEntry(symbol: "】", name: "方头右括号", keywords: ["kuohao", "fangkuohao"], isSymbol: true),
        EmojiEntry(symbol: "•", name: "项目圆点", keywords: ["yuandian", "dian", "bullet"], isSymbol: true),
        EmojiEntry(symbol: "①", name: "圈一", keywords: ["yi", "xuhao", "quan", "1"], isSymbol: true),
        EmojiEntry(symbol: "②", name: "圈二", keywords: ["er", "xuhao", "quan", "2"], isSymbol: true),
        EmojiEntry(symbol: "③", name: "圈三", keywords: ["san", "xuhao", "quan", "3"], isSymbol: true),
        EmojiEntry(symbol: "④", name: "圈四", keywords: ["si", "xuhao", "quan", "4"], isSymbol: true),
        EmojiEntry(symbol: "⑤", name: "圈五", keywords: ["wu", "xuhao", "quan", "5"], isSymbol: true),
        EmojiEntry(symbol: "⑥", name: "圈六", keywords: ["liu", "xuhao", "quan", "6"], isSymbol: true),
        EmojiEntry(symbol: "⑦", name: "圈七", keywords: ["qi", "xuhao", "quan", "7"], isSymbol: true),
        EmojiEntry(symbol: "⑧", name: "圈八", keywords: ["ba", "xuhao", "quan", "8"], isSymbol: true),
        EmojiEntry(symbol: "⑨", name: "圈九", keywords: ["jiu", "xuhao", "quan", "9"], isSymbol: true),
        EmojiEntry(symbol: "⑩", name: "圈十", keywords: ["shi", "xuhao", "quan", "10"], isSymbol: true),
        EmojiEntry(symbol: "♂", name: "男性符号", keywords: ["nan", "nanxing", "male"], isSymbol: true),
        EmojiEntry(symbol: "♀", name: "女性符号", keywords: ["nv", "nvxing", "female"], isSymbol: true),

        // 效率研发/职场高频表情
        EmojiEntry(symbol: "🐛", name: "Bug虫子", keywords: ["bug", "chongzi", "tiaoshi", "debug"], isSymbol: false),
        EmojiEntry(symbol: "💡", name: "灵感灯泡", keywords: ["linggan", "zhuyi", "dengpao", "idea", "tip"], isSymbol: false),
        EmojiEntry(symbol: "🎯", name: "目标命中", keywords: ["mubiao", "baba", "target", "goal"], isSymbol: false),
        EmojiEntry(symbol: "📝", name: "记录备忘", keywords: ["jilu", "biji", "note", "memo"], isSymbol: false),
        EmojiEntry(symbol: "⚠️", name: "警告注意", keywords: ["jinggao", "zhuyi", "warning", "alert"], isSymbol: false),
        EmojiEntry(symbol: "🔒", name: "锁隐私", keywords: ["suo", "yinsi", "mima", "lock", "security"], isSymbol: false),

        // 可搜索颜文字
        EmojiEntry(symbol: "(≧▽≦)", name: "颜文字开心", keywords: ["kaixin", "yanwenzi", "haha", "kaomoji"], isSymbol: true),
        EmojiEntry(symbol: "(╥﹏╥)", name: "颜文字大哭", keywords: ["ku", "nanguo", "yanwenzi", "kaomoji"], isSymbol: true),
        EmojiEntry(symbol: "(ー_ー)!!", name: "颜文字无语", keywords: ["wuyu", "yanwenzi", "kaomoji"], isSymbol: true),
        EmojiEntry(symbol: "(╯°□°）╯︵ ┻━┻", name: "颜文字掀桌", keywords: ["xianzhuo", "zhuokuang", "fanzhuo", "wuyu", "kaomoji"], isSymbol: true),
        EmojiEntry(symbol: "(ง •_•)ง", name: "颜文字加油", keywords: ["jiayou", "yanwenzi", "kaomoji"], isSymbol: true),
        EmojiEntry(symbol: "ʕ•ᴥ•ʔ", name: "颜文字小熊", keywords: ["xiong", "keai", "yanwenzi", "bear"], isSymbol: true),
    ]

    /// 面板内实时搜索：同时支持直接拼音/英文关键词 + 引擎解析出的中文词条（WowType `emoji_search` 同款）。
    static func search(_ query: String, resolvedChineseWords: [String] = [], limit: Int = 30) -> [EmojiEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(all.prefix(limit)) }

        var results: [EmojiEntry] = []
        var seenSymbols = Set<String>()

        func appendEntry(_ entry: EmojiEntry) {
            guard seenSymbols.insert(entry.symbol).inserted else { return }
            results.append(entry)
        }

        // 1. 先按引擎解析出的中文词条精准命中 zh-extra 词表（支持任意拼音输入查表情）
        for word in resolvedChineseWords.prefix(8) {
            if let emojis = wordRecommendations[word] {
                for sym in emojis {
                    appendEntry(EmojiEntry(symbol: sym, name: word, keywords: [], isSymbol: false))
                }
            }
            for entry in all where entry.name.contains(word) {
                appendEntry(entry)
            }
        }

        // 2. 再按本地关键词精确/前缀匹配
        for entry in all where entry.keywords.contains(q) || entry.name == q {
            appendEntry(entry)
        }
        for entry in all where entry.matches(q) {
            appendEntry(entry)
        }
        return Array(results.prefix(limit))
    }

    /// WowType 首位候选中文词实时 Emoji 推荐（全拼 / 7种双拼 / 简拼 / 九宫格 / 五笔全通用）：
    /// - 整句如「今天好开心」结尾命中「开心」→ 返回 `("今天好开心😊", "😊")`；
    /// - 词汇如「开心」直接命中 → 返回 `("😊", "😊")` 与 `("开心😊", "😊")`。
    static func recommendForTopCandidate(_ topWord: String) -> [(word: String, emoji: String)] {
        guard topWord.count >= 2 else { return [] }
        let chars = Array(topWord)
        let n = chars.count

        // 先查整词，再依次查结尾 4 / 3 / 2 字（单字不触发打字自动推荐）
        var matchedWord: String?
        var matchedEmojis: [String]?
        for len in stride(from: min(4, n), through: 2, by: -1) {
            let tail = String(chars[(n - len)..<n])
            if let list = wordRecommendations[tail], !list.isEmpty {
                matchedWord = tail
                matchedEmojis = list
                break
            }
        }
        guard let matched = matchedWord, let rawEmojis = matchedEmojis else {
            return []
        }
        let emojis = RecentEmojiStore.prioritize(rawEmojis)
        guard let firstEmoji = emojis.first else {
            return []
        }

        if n > matched.count {
            // 句尾附带表情：如「今天好开心」→「今天好开心😊」
            return [(topWord + firstEmoji, firstEmoji)]
        } else {
            // 精确短词命中：优先出「开心😊」或独立表情
            var out: [(String, String)] = [(firstEmoji, firstEmoji)]
            if emojis.count > 1 {
                out.append((emojis[1], emojis[1]))
            }
            return out
        }
    }

    static func suggestionsForExactPinyin(_ pinyin: String) -> [String] {
        let q = pinyin.lowercased()
        guard q.count >= 3 else { return [] }
        return all.filter { $0.keywords.contains(q) }.prefix(3).map(\.symbol)
    }
}
