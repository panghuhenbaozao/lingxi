import Foundation

/// 离线高情商话术场景分类
public enum SocialScriptCategory: String, CaseIterable, Identifiable, Sendable {
    case politeRefuse = "委婉拒绝"
    case gentleNudge = "体面催促"
    case gracefulApology = "救场道歉"
    case warmBlessing = "走心祝福"
    case workplace = "职场沟通"
    case lifeAndDeal = "租房闲鱼"

    public var id: String { rawValue }

    public var shortTabTitle: String {
        switch self {
        case .politeRefuse: return "拒绝"
        case .gentleNudge: return "催促"
        case .gracefulApology: return "道歉"
        case .warmBlessing: return "祝福"
        case .workplace: return "职场"
        case .lifeAndDeal: return "生活"
        }
    }
}

/// 话术语气标签
public enum SocialScriptTone: String, CaseIterable, Identifiable, Sendable {
    case gentle = "温和"
    case crisp = "干脆"
    case humorous = "幽默"
    case formal = "正式"

    public var id: String { rawValue }
}

/// 单条离线救场话术
public struct SocialScriptItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let category: SocialScriptCategory
    public let tone: SocialScriptTone
    public let scenario: String
    public let text: String

    public init(id: String, category: SocialScriptCategory, tone: SocialScriptTone, scenario: String, text: String) {
        self.id = id
        self.category = category
        self.tone = tone
        self.scenario = scenario
        self.text = text
    }
}

/// 0ms 纯离线「高情商生活救场话术口袋」（无需 API Key、无网地铁也能秒发）。
/// 精选零油腻、贴近真实微信日常的现代高频表达，覆盖拒绝、催促、道歉、祝福、职场与租房闲鱼维权 6 大场景。
public enum SocialScriptBank {
    public static let all: [SocialScriptItem] = [
        // MARK: - 1. 委婉拒绝
        SocialScriptItem(id: "ref_1", category: .politeRefuse, tone: .gentle, scenario: "拒绝借钱", text: "真不好意思，我这边钱都放了定期和房贷备用金，手头确实周转不开，帮不上忙多包涵。"),
        SocialScriptItem(id: "ref_2", category: .politeRefuse, tone: .crisp, scenario: "拒绝借钱（立规矩）", text: "家里之前定过规矩，亲友之间不互相借钱以免伤感情，实在不好意思，祝你早点周转过去。"),
        SocialScriptItem(id: "ref_3", category: .politeRefuse, tone: .gentle, scenario: "拒绝不想去的饭局", text: "谢谢惦记！我这周状态不太好想在家好好歇两天，这次就不凑热闹了，祝你们吃得开心～"),
        SocialScriptItem(id: "ref_4", category: .politeRefuse, tone: .humorous, scenario: "拒绝临时邀约", text: "我的社交电量今天已经红灯报警啦，先回家充个电，改天满血复活再约！"),
        SocialScriptItem(id: "ref_5", category: .politeRefuse, tone: .crisp, scenario: "拒绝砍一刀/助力", text: "不好意思哈，那个软件我手机里没装也没注册，这次真帮不上忙啦。"),
        SocialScriptItem(id: "ref_6", category: .politeRefuse, tone: .gentle, scenario: "拒绝免费帮忙干私活", text: "这事要做好挺耗精力的，我最近手头项目排得特别满，实在抽不出完整时间，怕耽误你进度，建议找更稳妥的渠道哈。"),
        SocialScriptItem(id: "ref_7", category: .politeRefuse, tone: .formal, scenario: "拒绝临时加塞需求", text: "这个需求我评估了一下，会直接影响当前主线排期。如果优先级更高，麻烦同步一下需要顺延哪一项，我立刻配合调整。"),
        SocialScriptItem(id: "ref_8", category: .politeRefuse, tone: .gentle, scenario: "拒绝相亲/介绍对象", text: "谢谢阿姨/朋友费心想着我，我现阶段精力主要放在工作和自己节奏上，暂时还没打算安排见面，心意我领啦！"),
        SocialScriptItem(id: "ref_9", category: .politeRefuse, tone: .crisp, scenario: "拒绝帮带大件代购", text: "这次行李箱已经塞满超重边缘了，实在带不下，不好意思哈！"),
        SocialScriptItem(id: "ref_10", category: .politeRefuse, tone: .gentle, scenario: "拒绝周末临时加班", text: "周末我这边已经提前安排好家里的事了，电脑不在身边；周一上午一到工位我第一时间优先把这块搞定。"),
        SocialScriptItem(id: "ref_11", category: .politeRefuse, tone: .humorous, scenario: "拒绝喝酒劝酒", text: "今天真是滴酒不沾的养生局，我以茶代酒先干为敬，咱感情全在茶里！"),
        SocialScriptItem(id: "ref_12", category: .politeRefuse, tone: .crisp, scenario: "拒绝当担保人/借账号", text: "涉及实名和信用担保的事我一贯不外借，原则问题，实在抱歉帮不了这个忙。"),

        // MARK: - 2. 体面催促
        SocialScriptItem(id: "nud_1", category: .gentleNudge, tone: .gentle, scenario: "礼貌催同事给资料", text: "打扰一下～之前对齐的那份资料大概什么时候方便发我？我这边排一下后面的衔接时间。"),
        SocialScriptItem(id: "nud_2", category: .gentleNudge, tone: .formal, scenario: "催领导审批流程", text: "老师您好，之前提交的审批单目前卡在这一步，下游节点在等确认，方便的话麻烦您抽空看一眼，辛苦了。"),
        SocialScriptItem(id: "nud_3", category: .gentleNudge, tone: .gentle, scenario: "体面提醒朋友还钱", text: "最近忙吗？我下周这边刚好有笔大额支出，之前那笔周转款你看看这两天方便转一下不？"),
        SocialScriptItem(id: "nud_4", category: .gentleNudge, tone: .crisp, scenario: "二次明确催还款", text: "之前约好这个月结清的那笔钱，我这边已经在安排账单了，麻烦今天内先处理一下哈。"),
        SocialScriptItem(id: "nud_5", category: .gentleNudge, tone: .gentle, scenario: "催客户确认方案", text: "您好，上次发的方案不知道您这边看完有没有需要微调的地方？确认后我们就可以安排往下推进啦。"),
        SocialScriptItem(id: "nud_6", category: .gentleNudge, tone: .humorous, scenario: "轻松催熟人回消息", text: "轻轻敲一下门，人还在地球服务区吗？等你拍板我就开干啦！"),
        SocialScriptItem(id: "nud_7", category: .gentleNudge, tone: .formal, scenario: "催对方付款/结算", text: "您好，该项目已于此前验收完成，按约定周期本次结算款项已到期，烦请协助推进财务打款并告知预计到账时间，谢谢。"),
        SocialScriptItem(id: "nud_8", category: .gentleNudge, tone: .crisp, scenario: "催物业/维修上门", text: "您好，之前报修的问题目前还没解决，比较影响正常生活，麻烦确认一下师傅具体几点能上门？"),
        SocialScriptItem(id: "nud_9", category: .gentleNudge, tone: .gentle, scenario: "催朋友确认聚会人数", text: "我一会儿准备订位置啦，你这边大概几点能到？方便的话给个准信我好留座～"),
        SocialScriptItem(id: "nud_10", category: .gentleNudge, tone: .formal, scenario: "催外部合作方交付", text: "您好，距离约定交付时间还有 1 天，麻烦同步一下目前完成进度以及是否存在延期风险，方便我们提前预案。"),

        // MARK: - 3. 救场道歉
        SocialScriptItem(id: "apo_1", category: .gracefulApology, tone: .gentle, scenario: "忘记回消息救场", text: "实在不好意思！刚翻聊天记录才发现之前看过竟然忘了回，让你久等了，我现在马上处理。"),
        SocialScriptItem(id: "apo_2", category: .gracefulApology, tone: .humorous, scenario: "给熟人补回消息", text: "救命，我脑子里明明已经回复过你了，结果手指根本没发出去！罚自己下次请喝奶茶。"),
        SocialScriptItem(id: "apo_3", category: .gracefulApology, tone: .gentle, scenario: "赴约路上要迟到", text: "真抱歉，路上比预计堵一点，大概晚到 10 分钟左右，你到了先点单别等我，到了立刻找你！"),
        SocialScriptItem(id: "apo_4", category: .gracefulApology, tone: .formal, scenario: "工作出小差错担责", text: "非常抱歉，这个疏漏确实是我这边核对不够细致。我已经把修正版重新整理好了，后续会加上双人复核避免再发生。"),
        SocialScriptItem(id: "apo_5", category: .gracefulApology, tone: .gentle, scenario: "不小心说错话降温", text: "刚才我语气太急，话没说到位，其实本意不是针对你。别往心里去，咱们心平气和把事聊清楚。"),
        SocialScriptItem(id: "apo_6", category: .gracefulApology, tone: .gentle, scenario: "临时放鸽子改约", text: "真的非常对不起，这边突发急事实在走不开，临时改约太耽误你安排了。你看下周哪天有空，这顿我请客赔罪！"),
        SocialScriptItem(id: "apo_7", category: .gracefulApology, tone: .formal, scenario: "回复邮件/工单延迟", text: "抱歉回复稍晚。您反馈的问题我已经完整核查完毕，以下是详细说明与下一步处理方案："),
        SocialScriptItem(id: "apo_8", category: .gracefulApology, tone: .crisp, scenario: "发错群撤回救场", text: "不好意思发错群了，打扰各位，请忽略刚才那条消息。"),

        // MARK: - 4. 走心祝福
        SocialScriptItem(id: "bls_1", category: .warmBlessing, tone: .gentle, scenario: "朋友生日（走心不土）", text: "生日快乐！祝你新的一岁身体稳稳的、钱包鼓鼓的，遇到的都是顺心人和好消息，自由又松弛。"),
        SocialScriptItem(id: "bls_2", category: .warmBlessing, tone: .humorous, scenario: "铁哥们/闺蜜生日", text: "生日快乐！祝你暴富、暴美、不掉发，吃啥都不胖，烦心事统统绕道走！"),
        SocialScriptItem(id: "bls_3", category: .warmBlessing, tone: .formal, scenario: "领导/长辈生日", text: "祝您生日快乐！愿您身体健康、松弛顺遂，新的一岁事业蒸蒸日上，阖家平安喜乐。"),
        SocialScriptItem(id: "bls_4", category: .warmBlessing, tone: .gentle, scenario: "新年通用（去群发味）", text: "新年好！过去一年多谢关照，祝新的一年顺风顺水、平安喜乐，日子越过越有奔头！"),
        SocialScriptItem(id: "bls_5", category: .warmBlessing, tone: .formal, scenario: "客户/合作方节日问候", text: "值此佳节，诚挚感谢您一直以来的信任与支持。祝您节日愉快、生意兴隆，期待新的一年继续携手共赢！"),
        SocialScriptItem(id: "bls_6", category: .warmBlessing, tone: .gentle, scenario: "新婚祝福", text: "新婚快乐！祝你们往后余生三餐四季都温柔，有说不完的话，也有一起扛事的底气，长长久久！"),
        SocialScriptItem(id: "bls_7", category: .warmBlessing, tone: .gentle, scenario: "生娃/满月祝福", text: "恭喜喜得小宝贝！祝宝宝健康平安长大，也祝新手爸妈少熬夜、多开心，一家人幸福满满！"),
        SocialScriptItem(id: "bls_8", category: .warmBlessing, tone: .gentle, scenario: "乔迁新居", text: "恭喜乔迁新居！祝新家阳光满屋、烟火可亲，越住越顺心，日子红红火火！"),
        SocialScriptItem(id: "bls_9", category: .warmBlessing, tone: .gentle, scenario: "考试/面试加油", text: "放平心态正常发挥就够棒了，你前期准备已经很扎实啦，祝顺顺利利一次上岸，等你捷报！"),
        SocialScriptItem(id: "bls_10", category: .warmBlessing, tone: .gentle, scenario: "离职/入职新起点", text: "恭喜开启新旅程！这段时间一起并肩合作非常愉快，祝你在新平台大展身手，江湖有缘常聚！"),

        // MARK: - 5. 职场沟通
        SocialScriptItem(id: "wrk_1", category: .workplace, tone: .formal, scenario: "收到任务并明确交付时间", text: "收到，目标和范围我都清楚了。我先拆解一下细节，预计今天下班前同步初版，有卡点会提前反馈。"),
        SocialScriptItem(id: "wrk_2", category: .workplace, tone: .crisp, scenario: "请假申请（专业利落）", text: "老师您好，因个人事务需请假一天（具体日期），期间手头重点事项已提前做好交接，紧急情况微信/电话随时可联系，望批准。"),
        SocialScriptItem(id: "wrk_3", category: .workplace, tone: .formal, scenario: "不同意方案但保留体面", text: "这个方向很有启发，我补充一个执行层面的顾虑：在当前资源下风险偏高。建议我们先用小范围灰度验证，您看这样稳妥吗？"),
        SocialScriptItem(id: "wrk_4", category: .workplace, tone: .gentle, scenario: "感谢同事帮忙", text: "太感谢了！多亏你及时补位帮大忙了，省了我好多时间，改天一定请你喝咖啡～"),
        SocialScriptItem(id: "wrk_5", category: .workplace, tone: .formal, scenario: "会议纪要简洁收尾", text: "本次讨论核心结论与分工如下，如有遗漏或理解偏差请今天内补充，未异议将按此节奏推进。"),
        SocialScriptItem(id: "wrk_6", category: .workplace, tone: .crisp, scenario: "明确边界拒绝甩锅", text: "这块背景我同步一下客观记录：此前约定的上游输入截至目前尚未到达，需要先把前置依赖补齐，我这边才能按计划验收。"),
        SocialScriptItem(id: "wrk_7", category: .workplace, tone: .gentle, scenario: "下班后礼貌延迟回复", text: "消息收到啦，我现在在外面没带电脑，明天早上九点半一到公司就优先处理并给您答复。"),
        SocialScriptItem(id: "wrk_8", category: .workplace, tone: .formal, scenario: "向上汇报卡点求助", text: "目前进度整体可控，但在这一环节遇到跨团队资源协调卡点，已尝试 A/B 两种方式。希望能借您支持帮忙拍板或拉通一下。"),

        // MARK: - 6. 租房 / 闲鱼 / 维权
        SocialScriptItem(id: "lif_1", category: .lifeAndDeal, tone: .gentle, scenario: "闲鱼礼貌小刀", text: "东西成色看着挺好的，真心想要自用～如果能小刀到 XX 包邮的话，我直接拍下确认收货不墨迹，您看行吗？"),
        SocialScriptItem(id: "lif_2", category: .lifeAndDeal, tone: .crisp, scenario: "闲鱼拒绝屠龙刀", text: "谢谢关注，这个价已经很实在了，大刀就不出啦，诚心要可以包邮，祝您淘到心仪的～"),
        SocialScriptItem(id: "lif_3", category: .lifeAndDeal, tone: .crisp, scenario: "租房看房核心核对", text: "您好，请问这套房子还在吗？水电是民水民电还是商水商电？有没有额外物业费/网费，什么时候方便看房？"),
        SocialScriptItem(id: "lif_4", category: .lifeAndDeal, tone: .formal, scenario: "退租要押金（留痕）", text: "房东您好，房屋已按合同清扫交接完毕、水电燃气均已结清且无设施损坏，按约定请协助退还押金，收款方式发您，谢谢。"),
        SocialScriptItem(id: "lif_5", category: .lifeAndDeal, tone: .formal, scenario: "电商/快递理智维权", text: "您好，该订单商品存在明显质量/破损问题（已拍照留证），诉求是按平台规则直接退款/补发，请不要用模板敷衍，麻烦转专员尽快处理。"),
        SocialScriptItem(id: "lif_6", category: .lifeAndDeal, tone: .gentle, scenario: "提醒邻居降噪（礼貌先声）", text: "邻居您好，实在打扰啦～这边晚上声音传下来有点明显，家里人睡得比较浅，麻烦方便的话稍微轻一点点，非常感谢理解！"),
        SocialScriptItem(id: "lif_7", category: .lifeAndDeal, tone: .crisp, scenario: "快递放驿站要求送货上门", text: "您好，这个包裹没有提前征得我同意就直接放驿站了，件比较重我不太方便自取，麻烦安排按地址送货上门，谢谢配合。"),
        SocialScriptItem(id: "lif_8", category: .lifeAndDeal, tone: .gentle, scenario: "挪车礼貌提醒", text: "车主您好，不好意思打扰，您的车稍微挡住出口了，我这边着急出门，麻烦方便的话下来挪一下车，谢谢啦！"),
    ]

    public static func filter(
        category: SocialScriptCategory? = nil,
        tone: SocialScriptTone? = nil,
        query: String = ""
    ) -> [SocialScriptItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.filter { item in
            if let category, item.category != category { return false }
            if let tone, item.tone != tone { return false }
            if q.isEmpty { return true }
            return item.scenario.lowercased().contains(q)
                || item.text.lowercased().contains(q)
                || item.category.rawValue.contains(q)
                || item.tone.rawValue.contains(q)
        }
    }
}
