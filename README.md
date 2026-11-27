# 灵犀输入法 (Lingxi IME)

> **隐私即产品**：未开启「允许完全访问」、离线输入或开启 **🕶 全局无痕隐私模式** 时**零网络请求、零词库学习、零剪贴板落盘、零打字统计**；开启完全访问后，仅在用户主动触发 AI 写作 / 边打边译 / 截屏识图 / 云同步时直连用户配置的接口（并支持端侧 `AIPrivacyShield` 自动脱敏还原）。
> 云同步采用端侧零知识加密（**`LXE2`：PBKDF2 端侧主密钥 + AES-256-GCM**）——服务器在数学上读不到你的词库；跨屏剪贴板接力采用 **`LXRL1:` 端到端加密**（HKDF-SHA256 + AES-256-GCM，Web 控制台浏览器原生 WebCrypto 互通）；本地保险箱采用 `LXV1` + Keychain 随机密钥静态加密，并以 `ConcealedType` 严防机密外泄进 AI 提示词。
> 分析功能（如启用）默认关闭、与登录解耦、只传会话级聚合指标、永不含输入原文，可一键撤回并物理删除。

> **开源承诺（Open Core，不变更声明）**：输入引擎、键盘 UI、同步协议以 **MIT** 许可**永久开源**（本仓库）。
> 云服务控制台与 B 端分析服务为闭源增值部分。此开源边界与许可**承诺不变更**——本项目不会效仿『先开源后闭源』的路线，社区信任高于一切。

一个深度融合开源 **[WowType](https://github.com/Gloridust/WowType)** 核心引擎亮点、**rime-ice 雾凇拼音**、**rime-wubi 五笔 86**、**Hamster 仓输入法**触控交互、**Raycast** 参数化模板、**Cherry Studio** 富文本工作台与 **全民实用离线安全/生活助手** 的原生高性能 iOS 16+ 键盘扩展与 AI 中枢。

---

## 核心特性全景

### 1. WowType 级本地解码引擎 v5（92/92 核心回归 + 66/66 WowType 官方 `regress.tsv` 100% 通过）
- **40 万级现代化离线词库**：集成 **396,225 条雾凇现代中文词条**（融合热词、`tatoeba-freq` 口语词频与脏词过滤）+ **203,060 条二元搭配** + **22,370 条英文词库 (`melt_eng`)** + **93,515 条五笔 86 码表** + **38,460 条部件拆字** + **35,907 条五笔画反查** + **20,000 条滑行输入几何索引桶**；SQLite 采用 `SQLITE_OPEN_FULLMUTEX` + `NSRecursiveLock` 并发安全封装与 8KB APFS 对齐页（约 51 MB），完整支持 `didReceiveMemoryWarning()` 内存自保防 Jetsam 闪退。
- **9 种输入方案 + 5 套高阶布局皮肤包**：26 键全拼 + **全部 7 种主流双拼**（小鹤/自然码/微软/搜狗/智能 ABC/紫光/拼音加加）+ **五笔 86** + **T9 九宫格**（含左侧独立音节锁定栏）+ 可选 **顶部独立数字行**；内置 5 套布局专属快捷条（标准 / 开发者 / 写作 / 财务 / 极简）。
- **26 键中英文滑行输入 + U 模式生僻字拆字/笔画反查**：滑行荧光轨迹解码支持中英双语（按一次 `⌫` 整段撤销）；`u`/`U` 模式支持部件拆字（`ushuishuishui→淼`）与五笔画反查（`uhspn→木`）并实时标注读音。
- **OpenCC 词组级三变体简繁引擎 + 上下文重排**：支持大陆标准 / 台湾惯用词 / 香港繁体精准词组转换（如 `软件→軟體`、`内存→記憶體`），并结合宿主上下文语义重排候选词。

### 2. 全民高频实用效率与离线安全守护（0ms · 零联网 · 0 Token）
- **🛟 草稿防丢黑匣子 (`DraftRecoveryStore`)**：24 小时纯本地自动留底最近 15 段 ≥18 字长输入（续写自动原地覆盖不重复，密码框/无痕模式/强密码/L1 敏感信息零采集、永不上云），切 App 杀后台或网页刷新清空后在键盘「草稿」页 1 秒捞回。
- **🧼 分享链接去追踪 · 防社死净链器 (`LinkPrivacyCleaner`)**：0ms 剥离 B 站/小红书/抖音/淘宝/知乎/YouTube 55+ 追踪与账号暴露参数（如 `appuid`/`vd_source`/`sec_uid`/`spm_id_from`/`utm_*`，精准保护小红书 `xsec_token`），键盘复制横幅 1 点 `🧼 净链` 并支持 `/cleanurl` 离线斜杠宏。
- **🪪 个人速填名片夹 + 万能地址/开票拆解 (`PersonalFillCardWallet` & `SmartInfoParser`)**：既可把刚复制的一整段收件地址、企业开票抬头或会议通知拆出 **`填姓名` `填手机` `填地址` / `填抬头` `填税号` `填开户行` `填账号`** 单字段速填，也能 1 键存入个人名片夹，支持键盘「名片」页点填及 **`vdz`/`vkp`/`vmp`/`vcp`/`vshuihao`** 候选栏秒调。
- **🧊 发前冷静室 · 情绪防冲动温度计 + 🚨 9 类防诈避坑雷达 (`CommunicationGuardEngine`)**：争执上头时键盘顶栏 0ms 柔和弹出 **`🔥 语气偏冲，发前先冷静 3 秒？[🧊 保底线降火]`**；复制百万保障扣费、屏幕共享、套取验证码、刷单等 9 类高危话术时实时标红预警。
- **📢 发帖防限流 / 广告法违禁词雷达 (`OfflineTextLinter` & `/checkpost`)**：0ms 离线检测小红书/抖音/闲鱼极限词与站外导流敏感词，提供红绿 Diff 与一键自然合规平替。
- **🗣️ 0 门槛高情商离线话术口袋 (`SocialScriptBank`)**：覆盖拒绝、催促、道歉、祝福、职场与租房闲鱼 6 大场景 × 4 种语气精选模板，无需 API Key 也能在键盘「话术」页 1 点直发。
- **🧰 `v` / `V` 万能生活与财务速算引擎 v4**：
  - **财务生活速算**：房贷等额本息月供 `vdk100/30/3.5`、月薪换算日/时薪 `vsx15000`、AA 聚餐分摊 `vaa368/4`、购物折扣立省 `v299z85`、BMI 评估 `vbmi175/68`、日期倒计时 `v2027-01-01`、9 币种离线速估 `v100usd`/`v10000jpy`、加密随机强密码 `vpw16` 与财务大写 `v12800rmb`。
  - **单位换算与极客工具**：`v+3d`/`v-7d`/`vmingtian` 相对日期、`v180cm`/`v65kg`/`v38c`/`v10km`/`v100ping`/`v1.5gb` 精准换算、`vts` 时间戳、`vuuid` 随机 UUID。
- **✨ 选区原地包裹与大小写转换 + ⏳ 验证码 15 分钟阅后即焚 + 剪贴板多选拼段上屏 + 👴 长辈大字关怀模式**：选中文字后顶栏 0ms 一键套 `「」`/`《》`/`（）`/`“”`/`**粗**` 或切换 `Aa` 大小写；未置顶验证码超时自动清理，键盘支持多选碎片一键拼段上屏；1 键开启 22pt 超大字长辈关怀与选词轻声语音播报（关闭自动还原原配置）。
- **🎙️ 0ms 离线口述去口水清洗器 (`VoiceTranscriptCleaner`)**：自动折叠口误自纠、清理语境安全填充词并做盘古排版，支持红绿 Diff 对照。
- **🕶 全局无痕隐私模式 & 6 项系统级 Siri / 快捷指令 (`AppIntents`)**：开启后键盘顶栏常驻醒目 **`🕶 无痕`** 徽标（1 点即退），期间零学习、零统计、零草稿留底、零剪贴板留痕、零 AI 历史落盘。

### 3. Hamster 仓式触控交互 + 表情语义快筛 + 16 键专业文本编辑台
- **18 种仓式按键上下划动动作命令 (`#command`)**：支持 `#paste`、`#copy`、`#undo`、`#selectAll`、`#moveLeft/Right`、`#traditional`、`#incognito`、`#ai`、`#ai3v`、`#lint`、`#mask` 等划动动作及 12 组成对括号智能入内/越过/连删 (`PairedBracketHelper`)。
- **16 键专业光标与排版编辑台 (`TextEditingPadView`)**：十字方向键、行首/行尾、向后/向前删、按词删、撤销、隐私安全粘贴、一键离线排版、一键离线脱敏、简繁切换。
- **270+ 词条 Emoji 实时联想 + 语义快筛栏**：全拼/双拼/九键/五笔均支持句尾词 Emoji 联想，键盘表情面板新增 **全部 / 情绪 / 手势 / 职场 / 美食 / 祝福 / 动物** 一键快筛条。

### 4. 三协议流式 AI 写作中枢（AI 全权托管学习库 + 10 大专业工作室 + 原生 PDF 知识卡）
- **🧠 AI 全权托管与专属本地 SQLite 认知学习数据库 (`AICognitiveMemoryDB` & `AIAutopilotController` & `AIAutopilotHubView`)**：主 App 与键盘扩展共享本地加密保护 `ai_cognitive_memory.sqlite`（6 张关系表持续沉淀打字行为观察、高频自学习词领域、长期认知记忆与透明决策审计日志，密码框与无痕模式零采集）；默认开启「AI 全权自动托管」，由 0ms 本机习惯引擎与用户大模型双驱动，在 26 项安全打字开关白名单内按你的习惯自动开启纠错、动态热区、盘古空格、草稿防丢与易混模糊音（每一项变更均可 1 键撤回），并将沉淀的专属认知记忆自动注入每一次 AI 回复，越用越懂你。
- **三协议原生直连 + 自动容灾切换 + 隐私脱敏护盾**：支持 **Google Gemini**（`store=false`）、**OpenAI 兼容接口**（DeepSeek / Qwen / OpenAI / 反代）与 **Anthropic Claude** 原生协议；支持 402/429/5xx 零正文瞬时自动切备用档案，发往外部模型前自动脱敏手机号/身份证/银行卡/密钥并流式无感还原。
- **10 大 AI 专业工作室**：
  - **多话题富文本工作台 (`AIWorkbenchSheet`)**：Cherry Studio 级原生 Markdown 渲染（标题、要点、引用、带一键复制的围栏代码块）+ 策略参谋 + 模型盲测竞技场。
  - **多模型圆桌议会 (`AIMultiModelCouncilView`)**：2–4 席并发流式推理 + 主席融合裁决 + 逐席红绿 Diff。
  - **Raycast 级参数化指令模板 (`AIParameterizedRunnerView`)**：支持 `{{变量|选项1,选项2}}` / `{{变量=默认值}}` 与魔术上下文变量，可固化安装进键盘。
  - **文风 DNA 克隆与 PDF/TXT/MD 知识卡 (`AIStyleAndContextView`)**：原生 `PDFKit` 提取多页 PDF 并智能切片为端侧 RAG-Lite 知识卡，按沟通场景自动检索 Top-4 注入。
  - **发前冷静室与离线质检仪**、**多步 AI 流水线**、**语气微调与红绿 Diff**、**多语种翻译工作室**、**写作拆解工作室**、**Token 账本与成本估算**。
- **键盘内 AI 极速闭环**：支持 `@ai` / `/lint` / `/mask` / `/trad` / `/3v` 内联斜杠宏、多草稿切换 (`‹ 1/3 ›`)、生成后 1 键追问与微调（`更短 / 更礼貌 / 更口语 / 更犀利 / 扩写 / 译英`）、14 语种实时边打边译与截屏识图。

### 5. 双后端部署（Python 自托管 + Cloudflare Worker 边缘计算）与 E2EE 跨屏接力
- **双后端 19/19 全路由严格对齐**：同时提供零依赖 Python 后端 (`Server/lingxi_server.py` + `Server/dashboard.html`) 与无服务器边缘版 (`CloudflareWorker/src/worker.js` + `dashboard.js`)，支持 `ADMIN_TOKEN` 鉴权、滑动窗口限流与自动备份演练。
- **浏览器原生 WebCrypto `LXRL1:` 跨屏接力**：6 位数字匹配码免登录秒传，手机端与电脑浏览器端到端加密互通，中继服务器全程仅见密文。
- **可插拔三同步实现**：离线 Noop / 局域网 `NWListener` + `ChaCha20-Poly1305` 直连 / 云端 `LXE2` 零知识同步。详见 [全栈架构说明书](docs/ARCHITECTURE_AND_BACKEND.md)。

```bash
# 启动本地云端后端服务与可视化 Web 控制台 (访问 http://127.0.0.1:8787/dashboard)
python3 Server/lingxi_server.py --host 127.0.0.1 --port 8787
# 运行后端全规格自检测试与备份恢复演练
python3 Server/lingxi_server.py --self-test
python3 Server/lingxi_server.py --backup-drill
```

---

## 构建与安装（支持免 Mac 云端打包）

### 方式 A：GitHub Actions 云端打包 `.ipa`（Windows + SideStore / AltStore 侧载）

1. 将本 `Lingxi` 目录推送到你的 GitHub 仓库（私有或公开均可）。
2. 打开仓库 **Actions -> Build & Test Lingxi iOS IPA**，点击 **Run workflow**（`push` 也会自动触发）。
3. macOS runner 会先跑完 `Tools/verify_swift_integrity.py`、`Tools/engine_prototype.py`（92/92 + 66/66 WowType 官方回归集）与 Xcode `LingxiTests` 全量单元测试，随后上传 `Lingxi-unsigned-ipa`。
4. 下载并通过 **SideStore / AltStore** 安装到 iPhone；[AppGroup.swift](Shared/AppGroup.swift) 已内置适配侧载生成的 `ALTAppGroups`（全工程严格维持 2 个 App ID，兼容免费 Apple ID 3 App ID 上限）。

### 方式 B：Mac 本地 Xcode 编译

```bash
brew install xcodegen
cd Lingxi
xcodegen generate
open Lingxi.xcodeproj
```

为 `Lingxi` 和 `LingxiKeyboard` 选好 Apple ID **Team** 后连接 iPhone 按 `Cmd + R` 运行。

> 注意：`project.yml` 中 `DEVELOPMENT_TEAM` 默认为空（CI 未签名构建无需设置）。本地真机运行或自行签名打包时，请先将其改为你的 Apple Developer Team ID，或在 Xcode 的 Signing & Capabilities 中直接选择 Team。

## 开源致谢与数据许可

- **Engine Design, Shuangpin / Wubi 86 Logic, Hotwords, Emoji Mapping & Regression Suite**: [Gloridust/WowType](https://github.com/Gloridust/WowType) (MIT / Apache-2.0)
- **Chinese & English Dictionary**: [iDvel/rime-ice](https://github.com/iDvel/rime-ice) (GPL-3.0)
- **Wubi 86 Table**: [rime/rime-wubi](https://github.com/rime/rime-wubi) (LGPL-3.0)
- **Spoken Frequency Blending Data**: [Tatoeba](https://tatoeba.org/) (CC BY 2.0 FR)
