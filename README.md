# 灵犀输入法 (Lingxi IME)

> **隐私即产品**：键盘扩展**永不发起网络请求**；未登录、未授权时**没有任何数据离开你的设备**。
> 未来若提供云同步，将是**端到端加密**的——服务器在数学上读不到你的词库（Bitwarden 模式）。
> 分析功能（如启用）默认关闭、与登录解耦、只传会话级聚合指标、永不含输入原文，可一键撤回并物理删除。

> **开源承诺（Open Core，不变更声明）**：输入引擎、键盘 UI、同步协议以 **MIT** 许可**永久开源**（本仓库）。
> 云服务控制台与 B 端分析服务为闭源增值部分。此开源边界与许可**承诺不变更**——本项目不会效仿『先开源后闭源』的路线，社区信任高于一切。

一个深度移植开源 **[WowType](https://github.com/Gloridust/WowType)** 核心引擎亮点、**rime-ice 雾凇拼音**、**rime-wubi 五笔 86**、**Hamster 仓输入法**触控交互与现代流式 AI 写作体验的原生高性能 iOS 键盘扩展。

## 核心特性

1. **WowType 级本地解码引擎 v5（92/92 核心回归 + 66/66 WowType 官方 `regress.tsv` 100% 通过）**
   - 集成 **396,225 条雾凇现代中文词条**（融合 WowType `hotwords.tsv` 热词、`tatoeba-freq.tsv` 口语词频、`rime-ice-freq.tsv` 词频修正、`blocklist.tsv` 去脏词）+ **203,060 条二元搭配 (`sys_bigrams`)** + **22,370 条英文词库 (`melt_eng`)** + **93,515 条五笔 86 码表 (`rime-wubi`)** + **38,460 条部件拆字 (`rime-radical-pinyin`)** + **35,907 条五笔画反查 (`rime-stroke`)** + **20,000 条滑行输入几何索引桶 (`glide_dict`)**。
   - **9 种输入方案 + 双布局 + 独立数字行**：26 键全拼 + **全部 7 种主流双拼**（小鹤、自然码、微软、搜狗、智能 ABC、紫光、拼音加加；自动渲染对应双拼键帽助记，微软/搜狗/紫光提供分号 `;=ing` 一键直达）+ **五笔 86** + **T9 九宫格**（含左侧独立音节锁定栏）+ 可选 **顶部独立数字行 (`1-0` 五行键盘)**。
   - **26 键中英文滑行输入 (`GlideTypingDecoder` + 荧光轨迹渲染)**：基于 Shark2 / Gboard 几何等距重采样与语言模型联合打分，手指在 26 键上连续滑行即可精准识别中文词句（`nihao→你好`、`zhongguo→中国`、`woaini→我爱你`、`shurufa→输入法`）与英文单词（`hello`、`GitHub`、`iPhone`），按一次 `⌫` 即可整段撤销滑行词。
   - **U 模式：部件拆字 + 五笔画生僻字反查（自带读音注音）**：全拼下按 `u`（双拼/五笔下长按 `u` 输入大写 `U`）即可用部件拼音或五笔画（`h`横 `s`竖 `p`撇 `n`/`d`捺点 `z`折）查生僻字并实时显示正确读音（如 `ushuishuishui→淼 miao`、`uniuniuniu→犇 ben`、`ufangfangtu→堃 kun`、`ulonglonglong→龘 da`、`uhspn→木 mu`）。
   - **精确保护与自然排位**：
     - 完整拼音匹配真实词条保护 #1（`zhongdi`→种地、`beiji`→北极、`ka`→卡、`qidongqi`→启动器、`qianhouduan`→前后端、`houxuanci`→候选词），单音节歧义词 `xian` 首选「先」、「西安」自动进 Top-5；
     - 儿化音（`wanr`→玩儿、`zher`→这儿、`yidianr`→一点儿、`haowanr`→好玩儿）；
     - 全拼混简拼与补全长度惩罚（`kyi`→可以、`wanqky`→完全可以、`yongzwen`→用中文、`zhchi`→支持、`weish`→为啥、`gzh`→公众号）；
     - 光标上文消歧 + **`MERGED_PAIR_SCORE` 合成词保底加分**（`我们`+`hui`→会、`你好`+`ma`→吗、`吃饭`+`le`→了、`我`+`yao`→要）；
     - 英文精准排位（`github`→GitHub、`wechat`→WeChat、`deepseek`→DeepSeek 直接 #1；同时为合法拼音的 `like`/`danger` 精确放第 6 位）；
     - 4 路错拼容错 + **WowType `fuzzy_fallback` 模糊音未开时智能兜底**（`yingai`→应该、`zidao`→知道、`meiyuo`→没有、`shengme`→什么、`penyou`→朋友、`tianqu`→天气）+ 16 组全模糊音 + **Apple 级动态下一键热区防误触**。
   - **五笔 86 完整支持**：严格码表原序不动态调频、未满 4 码显示剩余编码提示（`wq`→`您 in`、`低 a`、`你的 rq`）、四码唯一自动上屏（可关）、第 5 码顶字上屏、空码自动提示并重敲清空、`z` 键临时拼音与实时五笔编码反查（`工 a/aaaa`、`znihao`、`zriqi`）。

2. **WowType & Hamster 级高效率交互与文本编辑精控**
   - **✥ 独立文本编辑与光标精控面板 (`TextEditingPanelView`)**：工具栏一键呼出十字方向键（`↑` `↓` `←` `→` 支持跨行跳转与长按连发）、`⇤ 行首` / `行尾 ⇥`、`⌫ 向后删` / `向前删 ⌦ (Forward Delete)`、复制全文/选区、粘贴、清空当前行（带撤销）与换行。
   - **首位候选 Emoji 实时联想 + 最近使用记忆 (`RecentEmojiStore`)**：移植 WowType `zh-extra.tsv` 161 条精选聊天词库，按首位候选词整词或句尾 2–4 字推荐（如「今天好开心」→候选 #3 `今天好开心😊`），并根据用户最近使用的 Emoji 动态调优推荐优先级。
   - **智能标点与成对括号精控**：支持中文全角 / 英文半角一键切换；数字后自动保留半角小数点、冒号与逗号（`3.14`、`20:22`、`3,000`）；中文弯引号 `“`/`”` 与 `‘`/`’` 自动交替配对；`{`→`「`、`}`→`」`、`^`→`……`、`_`→`——`；空括号内按一次 `⌫` 成对清除（`()`/`（）`/`「」`/`【】`/`《》`），右括号处再敲闭合符号自动越过不重复。
   - **`v` / `V` 万能工具模式（算式结果自动附人民币大写 + 15 种日期时间格式）**：支持 `+ - * / % ^` 与括号求值（如 `v125*8` 同时给出 `1000`、`125*8=1000` 与 `壹仟元整`）、`v12345.67` 大写金额，以及 `riqi`/`date`/`shijian`/`time`/`xingqi` 的 7 种日期、6 种时间与 2 种星期格式。
   - **退格重选 + 撤回误学 (`undoLearn`) + 学习阈值**：选错候选后紧接按 `⌫` 不仅撤销文本并恢复原拼音，还自动回退刚刚写入 `UserLexicon` 的词频与二元搭配；支持 30 天半衰期衰减、1–5 次自动学习阈值及 `user.tsv` / `custom.tsv` 导入导出。
   - **OpenCC 词组级简繁切换**、**以词定字**（长按候选选首/尾字）、**盘古之白**（支持 CJK 扩展 A–G 汉字检测，密码框/邮箱/网址框自动避让）。
   - **译 · 14 语种实时边打边译（支持口语 / 正式语气切换）**：工具栏开启「译」模式，可一键切换「口语 / 正式」译文风格，边打中文边流式译为目标语种，空格/回车一键上屏译文或切 `[原]` 提交中文。
   - **生产级 iOS 扩展可靠性**：SQLite 采用 8KB APFS 对齐页与精简索引压缩至 **49.87 MB**（低于 GitHub 50 MB 阈值，推送零警告）；完整实现 `didReceiveMemoryWarning()` 内存警告自动释放 SQLite 页面缓存与查询 LRU（防 Jetsam 闪退）；基于 `traitCollection` 自适应 iPhone 竖屏 / 横屏紧凑高度与 iPad 宽屏旋转布局。

3. **iOS 16+ 零弹窗剪贴板 & BigBang「炸词提取」**
   - 借助 `UIPasteboard.detectPatterns` 与原生 `UIPasteControl`（配 `hasFullAccess` 兜底）智能提取 4–8 位短信验证码。
   - 内置 **BigBang 炸词**（`NLTokenizer`）与趣味花样英文字体。

4. **内嵌流式 AI 写作助手**
   - 支持 **Google Gemini Interactions API**（`store=false` 隐私不留存）与 **OpenAI 兼容接口**（DeepSeek / Qwen / OpenAI / 反代），支持自由提问、整理口述草稿、润色、高情商回复、翻译与神回复剪贴板。

5. **极简双簇顶栏 + 短信验证码/新复制内容全栏独占接管 + 跨设备实时剪贴板接力 + Web 控制台与云端画像 (`v4.0`)**
   - **极简顶栏与全栏智能接管 (`TopToolbarView`)**：移除顶栏低频表情、光标移动与折叠菜单（表情/颜文字检索迁入主 App「剪贴板与短语」页）；空闲时左置 `[✨ 灵犀 AI]` `[💬 译]`、右置 `[剪贴板]` `[设置]`。当收到短信验证码或新复制内容时，**自动隐藏工具栏按钮，整栏切换为「验证码一键填入 / 刚复制内容预览与粘贴」智能胶囊**，粘贴或关闭后立即恢复。
   - **跨设备实时剪贴板接力 (`ClipboardRelayService` + SSE 推流)**：对标微信输入法跨屏剪贴板，支持 **6 位数字匹配码免登录秒传**（REST `POST/GET /api/v1/relay/clipboard` + SSE 实时推流 `GET /api/v1/relay/stream`），电脑与手机之间一键接力文本、链接与短信验证码。
   - **后端可视化 Web 控制台 / 客户管理看板 (`Server/dashboard.html`)**：启动后端后访问 `http://127.0.0.1:8787/dashboard`，即可可视化查看 API 调用趋势、24 小时打字时段热力曲线、拼音易混音纠错矩阵 (`zh↔z` / `an↔ang` / `in↔ing` / `n↔l`)、用户词库领域偏好热力图、B 端企业客户管理与 180 天审计日志、PIPL/GDPR 授权流水及在线跨屏剪贴板接力工作台。
   - **可插拔三同步实现 + 纵深五层安全 (L1–L5) + 11 表数据库 (`Server/schema.sql` & `Server/lingxi_server.py`)**：完整提供 `LocalNoopSyncService`（离线）、`LANSyncService`（M2 局域网 `NWListener` + 6 位码 `ChaCha20-Poly1305` 双机直连）、`CloudBackendClient`（M3 零知识 E2EE 云同步），以及 M4 词库社区订阅 (`CommunityLexiconService`) 与 PIPL/GDPR 全量可携权导出 (`ComplianceService`)。详见 [全栈架构说明书](docs/ARCHITECTURE_AND_BACKEND.md)。

   ```bash
   # 启动本地云端后端服务与可视化 Web 控制台 (访问 http://127.0.0.1:8787/dashboard)
   python3 Server/lingxi_server.py --host 127.0.0.1 --port 8787
   # 运行后端 v4.0 全规格自检测试 (8/8 架构章节全覆盖)
   python3 Server/lingxi_server.py --self-test
   ```

---

## 构建与安装（支持免 Mac 云端打包）

### 方式 A：GitHub Actions 云端打包 `.ipa`（Windows + SideStore / AltStore 侧载）

1. 将本 `Lingxi` 目录推送到你的 GitHub 仓库（私有或公开均可）。
2. 打开仓库 **Actions -> Build & Test Lingxi iOS IPA**，点击 **Run workflow**（`push` 也会自动触发）。
3. macOS runner 会先跑完 `Tools/engine_prototype.py`（含 WowType `regress.tsv` 回归集）与 Xcode `LingxiTests` 单元测试，随后上传 `Lingxi-unsigned-ipa`。
4. 下载并通过 **SideStore / AltStore** 安装到 iPhone；[AppGroup.swift](Shared/AppGroup.swift) 已内置适配侧载生成的 `ALTAppGroups`。

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
