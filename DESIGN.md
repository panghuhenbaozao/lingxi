# Lingxi v2 Design System — 极简白

本文件是灵犀输入法 iOS 工程的设计系统说明（minimax 风格「极简白」，白底 + 墨色文字 + hairline 细线 + 中性灰系）。
App（SwiftUI）与键盘扩展（UIKit）共用 `Shared/DesignTokens.swift` 中的 `Design` 令牌；`DESIGN.md` 是事实来源。

---

## 1. 风格基调（签名移动）

- **签名移动（signature move）：** 所有主要区块以「纯白底 + 1px hairline 边框」分界，导航不靠色块而靠线条与留白；布局以组件排列的呼吸感（组内 16px 紧凑，组间 24–32px 视距）驱动。
- **密度：** 冷静密度（calm density）——信息保持 80%，视觉安静。
- **颜色纪律：** `ink (#0A0A0A)` 是唯一主色/品牌色；一切背景、线条、次级文字只用基础色板，禁止任何彩色渐变（除必要状态色：success 绿/error 红）。

## 2. 颜色系统

所有 `Design.Palette` 令牌是 `UIColor` 动态色，随系统亮/暗自动切换。亮色是主体验；暗色是同构的第二套（「墨玉」），不是把白卡堆在黑底上。

| 角色 | Token (Design.Palette) | 亮色 | 暗色 |
|---|---|---|---|
| Canvas 基底 | `canvas` | `#FFFFFF` | `#1C1C1E` |
| Canvas 顶部/底部 | `canvasTop` / `canvasBottom` | `#FFFFFF` | `#1C1C1E` |
| 次级色块 | `surface` / `surfaceSoft` | `#F7F8FA` / `#F2F3F5` | `#2C2C2E` / `#242426` |
| 分界线 | `hairline` / `hairlineSoft` | `#E5E7EB` / `#EAECF0` | `#3A3A3C` / `#333335` |
| 主色 | `ink` | `#0A0A0A` | `#F2F2F7` |
| 主色强/纯黑 | `inkStrong` | `#000000` | `#FFFFFF` |
| Charcoal 正文深色 | `charcoal` | `#222222` | `#E5E5EA` |
| Slate 次级 | `slate` | `#45515E` | `#C7C7CC` |
| Steel 第三级 | `steel` | `#5F5F5F` | `#AEAEB2` |
| Stone 弱化 | `stone` | `#6E6E73` | `#98989D` |
| Muted 弱化色 | `muted` | `#A8AAB2` | `#6C6C70` |
| 状态绿 | `success` | `#17976A` | `#34C77B` |
| 状态红 | `error` | `#C94A4A` | `#FF6B6B` |
| 键盘按压态 | `keyPressed` | `#E5E7EB` | `#3A3A3C` |
| 键盘卡面（固定） | `keyboardCanvas` | `#FFFFFF` | `#FFFFFF` |

**实测对比度（WCAG 2.1 相对亮度计算，非估计）：**

| 前景 / 背景 | 亮色 | 暗色 |
|---|---|---|
| `ink` / `canvas` | 19.8:1 | 15.2:1 |
| `slate` / `canvas` | 8.11:1 | 10.1:1 |
| `steel` / `canvas` | 6.38:1 | 7.69:1 |
| `stone` / `canvas` | 4.62:1 | 5.93:1 |
| `success` / `canvas`（图标） | 3.71:1 | 7.78:1 |
| `error` / `canvas`（图标） | 4.60:1 | — |

正文与辅助文字全部 ≥ 4.5:1；状态色用于图标时 ≥ 3:1（WCAG 图形要求），文字标签一律用 `ink`，不靠颜色传信息。

**60/30/10：** 主色 60%（文字、按键）；基底 20%（候选文字在主色料底、边框在 hairline 料底）；次级 10%（轻灰背景、阴影）。


## 3. 字体系统

iOS 原生应用规范使用系统字体（SF / 苹方等），不引入第二字体。

| 级别 | 语义 | UIKit | SwiftUI |
|---|---|---|---|
| h1 | 页面标题 | 16.5 bold | `.system(size: 16.5, weight: .bold)` |
| h2 | 表单分区 | 14 bold | `.system(size: 14, weight: .bold)` |
| h3 | 卡片主标题 | 15 semibold | `.system(size: 15, weight: .semibold)` |
| label | 按钮/表单标签 | 12.5 medium | `.system(size: 12.5, weight: .medium)` |
| body | 正文/简介 | 13 regular | `.system(size: 13, weight: .regular)` |
| caption | 说明/小字 | 11 regular | `.system(size: 11, weight: .regular)` |

**正文行距：** SwiftUI 正文默认；keyboard canvas 用适应键盘高度。

## 4. 圆角系统

| 用途 | Token | 值 |
|---|---|---|
| 页面/卡片 | `Radius.card` | 16px |
| 小型卡片 | `Radius.cardSmall` | 12px |
| 输入框/表单 | `Radius.input` | 8px |
| 按钮/胶囊 | `Radius.full` | 9999px |

**规则：** 独立卡片 16px；胶囊按钮 9999px（切边与正方向对齐）；表单字段 8px。

## 5. 间距系统

| Token | 值 | 用途 |
|---|---|---|
| `Spacing.xxs` | 4px | 极紧组间 |
| `Spacing.xs` | 8px | 组内紧凑 |
| `Spacing.sm` | 12px | 卡片内部边距基准 |
| `Spacing.md` | 16px | 组间、按钮间距 |
| `Spacing.lg` | 20px | 卡片内边距 |
| `Spacing.xl` | 24px | 页面内容顶部边距、模块间距 |
| `Spacing.xxl` | 32px | 组件与组件之间 |

**节奏：** 组内紧凑（8/12px），组间放松（16/20/24/32px）。禁止用不相关的大留白拆一个板块。

## 6. 组件与状态

- **Card（卡片）** — 白底 + 1px hairline 边框，圆角 16；悬浮状态用 0.5pt 实色 hairline 边 + 微阴影。
- **Button（按钮）**
  - 主按钮：`background = ink`，白字，胶囊形；按下变 `#222222`。
  - 次按钮：白底 + ink 边框，等距前景。
  - 第三按钮：白底，细灰边。
- **Form Fields** — 白底，hairline 边，radius 8；焦点变 2px hairline 深灰边；空字段用到的 + success 绿。
- **Search Bar** — 白底 + hairline + 圆角 8，文字 #5F5F5F。
- **Badge** — 球形 + 极小字 + hairline 边（成功用浅绿底）。
- **Keyboard（键盘界面）** — 键盘卡面全白（#FFFFFF），键目 ink，键体 pressed #E5E7EB，键帽 secondary/hint 用 stone；工具栏白底，candidate 文字 #0A0A0A；键盘相对 host 区完全透明（极简白 = 无色叠）。
- **Avatar（可选）** — 方形占位，圆角 8，填 surface。

## 7. 运动与时长

- 默认 ease-out，150–200ms（hover/focus 反馈）；关键动作（上屏/切换）无过渡。
- 禁止 layout 动画（top/left/size 变化）。
- 尊重 prefers-reduced-motion（UIKit 部分用 UIView.animate 时加 animationEnabled 守卫）。

## 8. 暗模式策略

**亮色是主体验，暗色是同构的第二套，不是把白卡堆在黑底上。**

- 所有语义色是 `UIColor` 动态色（`UIColor { traits in ... }`），系统切换时无需重启、无需重绘。
- 层级靠背景差 + hairline 双层承担：页面 `.systemGroupedBackground`（亮 `#F2F3F5` / 暗 `#000000`），卡片 `canvas`（亮白 / 暗 `#1C1C1E`），形成 iOS 分组语义的两级浮起。
- 阴影只做 0.08 的辅助，不承担分界；分界永远是 1px hairline。这样亮色下不会发灰，暗色下不会出现"白卡发光"。
- 键盘扩展不引用 `Design.Palette`（只用 `KeyboardTheme`），暗色系统上仍渲染白色卡面（`keyboardCanvas`），与 Apple 键盘惯例一致，避免"变暗了变难用"。
- 禁止在暗色下用纯黑 `#000` 作卡片底：会和页面背景粘连，失去层级。


## 9. 输入与无障碍

- 按钮/可点击目标 ≥ 44×44pt。
- 焦点环（iOS）可见；键盘 pressed 态颜色区分度 ≥ 4.5:1。
- 非决定性信息只用 color-independent 符号 + 文字（OK 状态）。

## 10. 签名参考

参考资料：minimax 官方设计系统（design-catalog，4421 个 token 级别的体系以亮色为主）；全部 token 在 `Shared/DesignTokens.swift`。

---

## 11. App 里面的规划设计（v2.2）

### 11.1 App 页面规划（TabView 清单，职责细则）

| Tab | 页面 | 职责 |
|---|---|---|
| 0 体验 | `HomeTestView` | 品牌条（键盘入口）+ 运行状态（两组分隔，可跳转）+ 试打区 v4 + 高频玩法卡 |
| 1 皮肤 | `ThemeStudioView` | 主题预览与自定义（含切换暗色映射 `darkThemeID`） |
| 2 AI 助手 | `AISettingsView` | AI 引擎/密钥、文风偏好、连通性诊断、AI 技能清单 |
| 3 剪贴板 | `ClipboardPhrasesView` | 系统剪贴板预览 + 快捷短语管理 |
| 4 设置 | `DictionarySettingsView` | 分类化设置中心：方案与布局 / 键盘手感 / 智能输入 / 模糊音 / 趣味字体 / 词库管理 六个分类入口，各自独立二级页；词库管理（自定义短语 + 个人词库 + TSV 导入导出）归入「词库管理」分类页 |
| 入口 | `OnboardingGuideView` | 3 步启用灵犀输入法 |

**状态卡约定：** 4×2 以上所有可点击元素 ≥ 44×44pt（`statusCard` minHeight 48 + padding 16）；文字与图标互不依赖。

### 11.2 试打区 v4（`HomeTestView.sandboxCard`）规划

- 标题行：`试打区` + `N 字`（monospacedDigit）+ 打字脉冲点（`TypingPulse`：灰色球 6pt，0.85 基准 → 0.8 + phase·0.4，opacity 0.15 → 0.7 + phase·0.3，0.5s 脉冲）+ 复制所有文字（有文本时可见）+ 禁用输入（锁定开关，锁定后编辑器 `allowsHitTesting(false)`，标签切换「解锁输入」）+ 收软键盘。
- 输入区：`TextEditor` minHeight 160，留白 12，可滚动；输入中脉冲持续 0.5s 后淡出。
- 底部动作行：模拟验证码短信 + 清空（≥ 44pt）。
- **打字可见性：** 输入中脉冲点保证每次改动有可见反馈；占位文案仅在空状态；键盘组合口端（英文联想）已在 `refreshToolbar` 中可见（`composingDisplay = englishComposing`）。

### 11.3 键盘优化方案（v2.2）

**Hit testing（`KeyboardCanvasView.nearestKey`）：**
- 核心区内圈 inset 1.5（原 3.5）；边缘/键缝扩边：`insetBy(dx: -3, dy: -5)`（原 -8）；空格键 `insetBy(dx: -2, dy: -4)`（原 dx -4, dy -10）。目的：按键中心热区保持，缝隙变小时不再抢占邻键。
- 动态热区偏置保持（dist × 0.74）。

**长按延迟（`scheduleLongPress`）：** backspace 0.30 / 带备选的 character 0.32 / punctuation 0.30 / space 0.22（原 0.34/0.38/0.35/0.25）。

**空格跟踪器（`touchesMoved`）：** 激活阈值 dx ≥ 10（原 14）；每步（10pt）发 `cursorMove` + `KeyboardVibrator.shared.spaceTick()`（动态敲击）。

**音效（`FeedbackManager`/`KeyboardVibrator`）：**
- 静态音（gated `keySoundEnabled`，走 controller 事件）：字母 press/commit、删除、功能键（letter/delete/modifier，依字段类型分层）。
- 动态音（新增）：`triggerCursorSound()` — 触发点：`cursorMove`（Space 跟踪器每步 + TextEditingPanel 方向键）、`glideCompleted`、`selectCandidate`、`handleLongPressCandidate`、候选栏点击（`KeyboardVibrator.shared.candidateTick()`）。

**震动映射（`KeyboardVibrator`）：**
- `lightTap`（touchBegan 所有键）+ `prepare()`；`softTap`（空格跟踪器开始/每步）；`spaceTick`（空格跟踪器动态敲击，选择级 + 预热）；`mediumTap`（上屏/语言切换）；`heavyTap`（退格重选删）；`candidateTick`（候选高亮移动/选中）。

**AI 顶工具栏（`TopToolbarView`）：**
- 功能按钮 44pt（`buttonsStack` height 44，垂直居中），触摸目标符合 44×44 最低要求。
- composing 预览升级：semibold 13.5 + `candidateHighlight`（原 11.5 mono）——输入中可见性提升。
- AI 按钮聚焦态（`aiPanelActive`）保留，为默认高亮。

**候选栏（`CandidateBarView`）：**
- 首选：ink 实底 + 白字；其余：文字 + hairline 0.5 边（层次与对比提升）。
- 动态交互：点选触发 `candidateTick`；长按 pin/forget（置顶/遗忘）已有，controller 侧补动态音。

### 11.4 目标
键盘按键命中更准（误触减少），输入有节奏感（音+震），输入中文字可见（英文联想 + 小试打区脉冲），老用户零配置即可感知提升。

---

## Changelog

- v2.8（2026-11-22）：M3-pre 同步引擎编排层——①新增 `Shared/Services/SyncEngine.swift`：SyncLedger 本地账本（记录+per-namespace 拉取游标，App Group 持久化）+ SnapshotSyncSource 快照数据源（整文件字节为同步单元、内容不变去重、墓碑删文件/字节原子写回）+ SyncEngine.syncNow() 编排闭环（采集→push→服务端 LWW 冲突并入→分页 pull→LWW merge→远端胜出回写并推进本地时钟→账本收敛持久化）；②拉取集合 = 数据源监视命名空间 ∪ 账本已见命名空间，修复全新设备账本为空时漏拉远端数据的缺陷；③Local Noop 下 syncNow() 为无害空转（离线默认态完整可用），M3 云实现只替换 SyncService 实现、引擎与业务零改动；④新增 6 项引擎测试（Noop 空转/推送去重/远端胜出落盘/墓碑删除/本地胜出保护/冲突胜出应用，全部用测试专用文件与注入时钟账本隔离）。
- v2.7（2026-11-22）：M2 同步客户端地基（为 M3 云同步准备的离线可验证组件，全部落 ADR 0001 决策）——①新增 `Shared/Services/SyncInfra.swift`：DeviceIdentity 稳定设备身份（UUID 持久化 App Group，LWW 第二排序键）+ LamportClock 逻辑时钟（tick/observe = max+1、persist 注入化、崩溃后只增不减）+ LWWMergeEngine 纯函数合并引擎（命名空间+键复合主键、(lamportTS, deviceID) 全序决胜、墓碑参与决胜、批内同键只应用最终胜者、产出 merged/toApply/watermark）；②新增 `Shared/Services/SyncCrypto.swift` E2EE 编解码层：HKDF-SHA256 域分离派生同步密钥 + AES-256-GCM 加解密 SyncChange.ciphertext（nonce 随机、认证防篡改），落实 SyncProtocols『value 由调用方加密』约定；③新增 10 项单元测试（时钟语义/LWW 全序与平局/墓碑/批内胜者/命名空间隔离/E2EE 往返与防篡改/设备身份稳定性）。
- v2.6（2026-11-22）：M1.5 加密备份与本地统计完善——①新增 `Shared/Services/BackupService.swift` 本地加密备份：密码经 PBKDF2-HMAC-SHA256（10 万轮 + 32 字节随机盐）派生 AES-256-GCM 密钥，打包全部用户数据（设置/主题/AI 配置/剪贴板/自定义短语/快捷短语/常用表情/打字统计 8 个 JSON + 个人词库 user_dict.sqlite）为单个 .lingxibak 文件；明文头部仅含格式/版本/时间元数据，payload 全密文，GCM 认证标签防篡改；SQLite 备份前 WAL checkpoint（TRUNCATE）合并日志，恢复时清 WAL/SHM 残留并重连词库；纯本地文件导出导入，零云端依赖，与『键盘永不联网』铁律一致。②新增备份与恢复设置页：密码导出 / fileImporter 导入，恢复前完整解密校验密码，覆盖确认弹窗，恢复后 refreshAll 重载内存态防 didSet 回写覆盖。③打字统计升级为独立页：总览六项指标（今日/累计/均速/活跃时长/连续天数/记录天数）+ 近 30 天趋势条形图（SwiftUI 原生实现，不依赖 Charts 框架），设置中心与智能输入页双入口。④新增配套测试：备份加解密往返、错误密码/篡改检测、弱密码拒绝、元数据读取、统计趋势窗口。
- v2.5（2026-11-22）：M1 工具栏三态重设计（产品化 v4.0 起点）——①默认布局极简化：AI/译/剪贴板/设置/撤销上栏，表情/编辑面板/九键切换默认收纳（存量用户配置不受影响，设置页『默认』预设仍为全可见）；②键盘新增『⋯』聚合面板：收纳被隐藏按钮为横排胶囊浮层，离开空闲态自动收起，主题联动重建，含 VoiceOver 标签；③新增 `Shared/Services/SyncProtocols.swift` 协议层地基（AuthService/SyncService/InsightService + Local Noop 实现 + LingxiServices 工厂）：业务只依赖协议，云实现只换文件；同步冲突策略为版本向量 + LWW（ADR 0001），TypingSessionDigest 结构性禁含原文；④README 落地隐私立场（键盘永不联网/默认零上传/同步 E2EE）与 Open Core 开源承诺（MIT 边界不变更声明）。
- v2.4（2026-11-21）：候选栏可调完善——修复候选栏高度滑杆热加载不生效（toolbarView 高度约束此前为一次性常量，新增 `toolbarHeightConstraint` 在 `reloadConfigurationIfNeeded` 中同步）；设置页『候选栏外观』新增实时预览条（高度/字号随滑杆即时变化，首选淡底 + 次选 hairline 描边，对齐键盘观感）与『恢复默认（50 pt / 16.5）』按钮（偏离默认时出现）；钳制测试补齐高度下限 44 / 字号上限 22 断言。补充修复：单行候选条字号按可用高度自动收敛（`appliedFontSize`，下限 12，栏高变化随 `layoutSubviews` 重算）——此前栏高 44 + 字号 22 + 拼音预览条开启时，候选条仅剩 28pt 而按钮约 36pt，文字溢出到拼音条区域；展开网格区域高度充足，不受影响。
- v2.3（2026-11-20）：App 页面分类重构——原「词库与设置」单页 40+ 项设置扁平堆叠、词库管理被淹没，重构为分类化设置中心：首页 6 个分类入口（hairline 描边图标 + 标题 + 实时摘要副标题），每类一屏二级页；词库管理独立成页。Tab 4 更名为「设置」（gearshape 图标）。体验页状态卡跳转语义不变（AI 引擎 → Tab 2、输入方案 → Tab 4）。

- v2.2（2026-11-20）：键盘优化：hit testing 内圈 1.5pt / 边缩 -3/-5（空格 -2/-4）；长按延迟 0.22–0.32s；space 跟踪器激活阈值降至 dx≥10、每步 spaceTick 动态敲击；动态音效（cursor/glide/candidate/选词动作）+ 震动映射更新；AI 顶工具栏按钮 44pt、composing 预览可见（13.5 semibold）；候选栏首选/次选视觉层次升级 + 动态震动；试打区 v4（字数/复制所有文字/禁用输入/收软键盘 + 打字脉冲点）；英文输入中预览修复（composing 可见）。
- v2.1（2026-11-20）：色板改为动态色，补齐「墨玉」暗色一套（卡片 `#1C1C1E`、hairline `#3A3A3C`、ink 反转 `#F2F2F7`）；`stone` 由 `#8E8E93` 调深至 `#6E6E73` 以满足 4.5:1；体验页重构为品牌条 + 2×2 状态网格（可点跳转）+ 试打区 + 折叠玩法；新增实测对比度表。
- v2（2026-11-19）：统一极简白（minimax 风格）设计系统；新增 `Design` 令牌；键盘主题新增「极简白」；体验页完整重设计；基于 hairline 线条的节奏感布局。
- v1（历史）：灵犀白昼/暗夜极客/樱花微醺/莫兰迪青/赛博霓虹/黑金殿堂 六色体系。
