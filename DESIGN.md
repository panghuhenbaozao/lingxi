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

## 12. App 共享组件库（`App/Views/LingxiComponents.swift`）

新页面一律用这些组件，不再手写颜色、圆角和按钮样式。

| 组件 | 用途 | 关键约定 |
|---|---|---|
| `LXCard` | 非 List 页面的白底卡片 | 圆角 16 + 0.5pt hairline，内边距 14 |
| `LXIconTile` | 行首图标块 | 主题色 12% 浅底，`size` 默认 32 |
| `LXTag` | 小标签 / 徽标 | 默认中性描边；`filled: true` 用主题色浅底 |
| `LXCapsuleButtonStyle` | 全部按钮 | `prominent` 实底白字；`wide` 撑满、高 46；视觉 32pt、热区补足 44pt（§9） |
| `LXToggleRow` | 设置开关 | 标题 + 一行白话说明，主题色 |
| `LXNavRow` | 二级页入口 | 图标块 + 标题 + 说明 + 可选徽标 |
| `LXEmptyState` | 空状态 | 图标 + 标题 + 说明，居中 |
| `LXFlowLayout` | 自动换行的标签墙 | iOS 16 `Layout`；超过 2 个标签的一行必须用它，防止 iPhone SE 宽度溢出 |
| `LXRemovableChip` / `LXAddFieldRow` | 可删词条 / 新增输入 | 回车提交 |
| `.lxToast($msg)` | 底部浮动提示 | 成功 / 提示 2.5s、失败 5s 自动消失；按文案判断语气（`Shared/ToastText.swift`，有单元测试）；成功 / 失败带触觉反馈；VoiceOver 播报；尊重「减弱动态效果」 |
| `.lxReadableWidth()` | 滚动页内容宽度 | 上限 680pt 居中，iPad 不被拉满 |

**硬性规则**
1. `@State` 的初始值表达式在每次创建视图结构体时都会执行，iOS 16 的 `NavigationLink` 又会在上级页面每次重绘时创建目标视图——所以 `@State` 初始值只放轻量默认值，真实数据在 `.task` / `.onAppear` 里读取。
2. `body` 里禁止读盘、开数据库或做遍历计算（如 `diagnose()`、`*Store.load()`、`syncNamespaceDashboardSummary()`）：放进 `@State`，在 `.task` / `.onAppear` / 数据变化后刷新。`AppState` 是 `@EnvironmentObject`，任意字段变化都会让所有页面重绘。
3. 删除、清空、退出、重新签发等不可逆操作必须二次确认（`confirmationDialog`）。
4. 机密内容（API Key、保险箱）复制走 `ConcealedPasteboard`；个人数据导出走文件，不进系统剪贴板。
5. 信息类文字用 `stone`（4.62:1），`muted` 只用于占位文字和装饰图标。
6. 白字只能放在 `accent / success / error / warning` 底上；`ink` 底的文字用 `canvas`，深色模式下才会自动反转。
7. 文案里不写 emoji 和 ✓ 前缀；判断 emoji 前缀时注意 Swift 按字形簇比较，`"⚠️"` ≠ `"⚠"`。
8. 涉及生物验证的功能要考虑「设备未设锁屏密码」的情况（`BiometricAuthHelper.isDeviceSecured`），不能让用户误以为数据已上锁。
9. 非「通过 Apple 登录」的按钮不能使用 Apple 标志。

---

> 补充规则 10：正文文字用文本样式（`.subheadline`、`.footnote.weight(.semibold)` 等）跟随系统字号；固定字号只用于图标、固定高度的胶囊和模拟键盘的预览。

## Changelog

- v3.26（2026-11-27）：**Obsidian 风格「LLM Wiki + 双链图谱」API 自学习个性化记忆库（v6.1.0）**——在 v3.25 根除 AI 页面闪退与 `ai_cognitive_memory.sqlite` 底座之上，深度借鉴 **Obsidian + Zettelkasten + A-MEM** 架构落地全链路自学习系统：①**Obsidian 图谱三表升级（`Shared/AICognitiveMemoryDB.swift`）**：无损新增 `vault_notes`（5 分区 `index/wiki/persona/habits/inbox` + YAML 元数据 + 记忆强度 + 召回频次）、`vault_links`（自动解析 `[[双向链接]]` 构建出链/反向链接图谱边）与 `vault_evolution_log`（`log.md` 追加式演化审计）；②**双链自学习引擎与 2-Hop Graph-RAG 召回（`Shared/ObsidianMemoryVaultEngine.swift` + `Shared/AIClient.swift` + `AppState`）**：纯 Swift 解析 `[[Wikilinks]]` / `#标签`、渲染标准 YAML Frontmatter `.md` 并支持整库导出为可直接导入 Obsidian 的 `.md` 包；`AIClient.mergeSystem` 每次调用实时执行 **2-Hop 双向知识图谱 Graph-RAG 召回**（结合查询语义、场景、置顶与 Ebbinghaus 衰减/强化曲线），命中后自动强化记忆稳定度；使用用户自填大模型 API 执行「打字库 + 词汇 + 历史对话 + 手动收件箱 → 原子常青笔记 + 自动建 `[[双链]]` + 重复合并重定向反链 + 安全白名单打字功能调优」，且日常采纳 6 次 AI 输出后自动触发低成本后台静默进化；③**交互式知识图谱与双链浏览中枢（`App/Views/AI/ObsidianVaultGraphView.swift` + `AIAutopilotHubView.swift` + `AISettingsView.swift`）**：纯 SwiftUI `Canvas` + 节点胶囊交互图谱（轻点节点高亮 1-Hop 出链/反链）、支持点选 `[[双向链接]]` 自由跳转、在线编辑 Markdown 与导出 `.md`、新增第 86 项 XCTest `testV73ObsidianSelfLearningMemoryVaultAndGraphRAG`。
- v3.25（2026-11-27）：**修复「AI 智脑」Tab 真机闪退 + 专属本地 SQLite 认知学习数据库 + AI 全权托管打字功能闭环（v6.0.1）**——①**P0 根因级修复 AI 页面闪退（`App/Views/AI/AISettingsView.swift` + `LingxiComponents.swift` + `ClipboardPhrasesView.swift` + `AIHistoryAndUsageView.swift`）**：彻底根除 5 项 iOS 16–18/26 SwiftUI 致命隐患——移除 `NavigationStack(path:)` 与 5 个旧式 `NavigationLink { }` 混用（统一改为单模式纯 `NavigationStack` + `.navigationDestination(isPresented:)` 零急切初始化）；将 `List` 内全部 `LazyVGrid` 替换为纯静态 2 列 `VStack + HStack` 消除 `UICollectionViewListCell` 自适应崩溃；将 `List` 上叠加的 5 个 `.sheet` 收敛为单一 `.sheet(item: $activeSheet)` 并将 `.fileExporter`/`.fileImporter` 迁移到独立按钮背景宿主；移除 `List` 内 `TextField(..., axis: .vertical)` 并将 `.topBarTrailing` 统一为 `.navigationBarTrailing`；为 `LXFlowLayout` 补齐 `isFinite` 防 `CALayerInvalidGeometry` 保护；新增永久 CI 防回归门禁；②**AI 专属共享本地 SQLite 认知学习数据库（`Shared/AICognitiveMemoryDB.swift`）**：AppGroup 共享 `ai_cognitive_memory.sqlite`（`SQLITE_OPEN_FULLMUTEX` + `NSRecursiveLock` + WAL + iOS 锁屏加密保护），结构化沉淀 6 张关系表（`typing_events` 打字行为观察、`learned_memories` 长期认知记忆、`autopilot_decisions` 托管操控审计日志、`vocab_learning_log` 词汇学习共鸣、`ai_interaction_episodes` AI 交互反馈、`autopilot_meta` 画像摘要），严守密码框/无痕模式/L1 敏感内容零入库红线；③**AI 全权托管引擎与「越打越懂你」双向闭环（`Shared/AIAutopilotController.swift` + `Shared/LingxiSettings.swift` + `Shared/AIClient.swift` + `AppState` + `KeyboardViewController` + `App/Views/AI/AIAutopilotHubView.swift`）**：默认开启 `.fullAutopilot` 模式，0ms 本机习惯引擎 + 用户大模型深度读库双重驱动，在 26 项安全白名单打字功能内自动为你开启/调优纠错、动态热区、盘古空格、草稿防丢、验证码阅后即焚、成对括号与 8 组易混模糊音（≥3 次自动开启，绝不触碰隐私/密钥红线），全部决定记入 SQLite 并支持 1 键撤回；沉淀的长期认知记忆与核心画像经 5 秒内存热缓存自动注入 `AIClient.mergeSystem(...)` 反哺每一次 AI 回复；新增专属「AI 全权托管与认知库」中枢页（支持手动教给 AI 习惯、记忆置顶/遗忘、JSON 导出、确认清空）与第 85 项单元测试 `testV72AICognitiveMemoryDBAndAutopilot`。
- v3.24（2026-11-27）：全民生活旗舰版（9 大市面稀缺大众高频刚需全量落地，0 第三方依赖、纯本地 0ms 离线可用）——①**🛟 草稿防丢黑匣子（`Shared/DraftRecoveryStore.swift` + `KeyboardViewController` + `ClipboardPanelView` + `DraftRecoverySubView`）**：24 小时纯本地滚动留底最近 15 段 ≥18 字长输入（12 分钟内续写原地更新，严守密码框/无痕模式/强密码/L1 敏感信息零采集、永不上云），专治切 App 杀后台或网页刷新丢字痛点，键盘「草稿」页 1 键原地捞回；②**🧼 分享链接去追踪 · 防账号暴露净链器（`Shared/LinkPrivacyCleaner.swift` + `TopToolbarView` + `ClipboardPanelView` + `ClipboardPhrasesView`）**：0ms 剥离 B 站/小红书/抖音/淘宝/知乎/YouTube 55+ 追踪与账号暴露参数（`appuid`/`vd_source`/`sec_uid`/`u_code`/`spm_id_from`/`utm_*`，精准保护小红书 `xsec_token` 与 B 站分 P `p`），顶栏复制横幅直接弹出 `🧼 净链` 与 `🛡 含追踪` 警示，并支持 `/cleanurl` 离线斜杠宏；③**🪪 个人速填名片夹（`Shared/PersonalFillCardWallet.swift` + `PersonalFillCardsSubView` + `SmartCandidateHelper`）**：结构化常驻保存家庭/公司收件、企业开票与车牌联系，支持从剪贴板 1 键智能建卡、键盘「名片」页单字段点填及 `vdz`/`vkp`/`vmp`/`vcp`/`vshuihao` 候选栏秒调；④**📢 发帖防限流 / 广告法违禁词 0ms 雷达（`OfflineTextLinter` + `AIOfflineLinterView` + `/checkpost`）**：覆盖小红书/抖音/闲鱼 24 组高频极限词与导流敏感词，支持红绿 Diff 与一键自然合规平替；⑤**🗣️ 0 门槛高情商离线话术口袋（`Shared/SocialScriptBank.swift` + `ClipboardPanelView` + `SocialScriptBankSubView`）**：6 大真实生活场景 × 4 种语气精选 56 条零油腻模板，无 API Key / 地铁无网也能在键盘「话术」页 1 点直发；⑥**✨ 选区原地包裹与大小写转换（`SelectionTextTransform` + `TopToolbarView` + `KeyboardViewController`）**：选中文字后顶栏 0ms 本地一键套/脱 `「」`/`《》`/`（）`/`“”`/`**粗**` 及英文 `Aa` 大小写轮换；⑦**💰 `v` 模式全民生活财务工具 v4**：新增房贷等额本息月供 `vdk100/30/3.5`、月薪换算日/时薪 `vsx15000`、9 币种离线速估 `v100usd`/`v10000jpy` 与 `SecRandomCopyBytes` 加密强密码 `vpw16`；⑧**⏳ 验证码 15 分钟自动阅后即焚 + 剪贴板多选拼段上屏（`ClipboardStore` + `ClipboardPanelView`）**：未置顶验证码超时自动清理，键盘支持多选 2–8 条碎片记录一键合并上屏；⑨**👴 长辈 / 护眼大字关怀一键模式 + 选词轻声播报（`LingxiSettings.setElderCareMode` + `QuickSettingsSheetView` + `DictionarySettingsView`）**：1 键拉大至 22pt 候选/60pt 顶栏/强震动并自动快照无损还原，懒加载 `AVSpeechSynthesizer` 轻声读词核对；新增第 84 项单元测试 `testV71MassMarketFlagshipFeatures`。
- v3.23（2026-11-27）：全民实用旗舰版（大众高频痛点闭环 + P0/P1 全仓精修）——①**0ms 离线情绪防冲动温度计 & 9 类防诈避坑雷达（`Shared/CommunicationGuardEngine.swift` + `TopToolbarView` + `ClipboardPanelView` + `AIOfflineLinterView`）**：争执上头即将发送冲动话术时键盘顶栏柔和弹出「🔥 语气偏冲，发前先冷静 3 秒？[🧊 保底线降火]」（联网直达保底线高情商降火改写，离线一键切冷静表达并带撤销缓冲）；复制可疑「百万保障扣费/屏幕共享/会议指导/验证码套取/安全账户/刷单/杀猪盘/熟人急转/提前交押金」文本时顶栏、剪贴板抽屉与 App 列表即时标红防诈预警（对正常腾讯会议通知零误报）；「离线文案质检仪」全面升级为「发前冷静室与质检」；②**0ms 万能收件地址 / 企业开票抬头 / 会议日程分字段速填（`Shared/SmartInfoParser.swift` + `ClipboardPanelView` + `ClipboardPhrasesView`）**：自动拆解一整段快递地址、开票信息与会议通知，直接在键盘剪贴板与 App 历史卡片生成 `填姓名`/`填手机`/`填地址`/`填抬头`/`填税号`/`填开户行`/`填账号`/`填时间`/`填会议号` 单字段一键速填胶囊；③**键盘顶栏常驻 `🕶 无痕` 徽标（1 点退出） + `AIClient` 富文本 Markdown 通道修复**：`mergeSystem`/`streamEvents`/`streamConversationEvents`/`streamText` 新增 `allowMarkdown: Bool = false`，彻底解开写作工作台、多模型圆桌与参数化模板的代码块/标题封印；封堵全仓 10 处剩余 AI/工具粘贴按钮误读 `ConcealedPasteboard` 保险箱机密漏洞；④**知识卡原生 `PDFKit` 导入 + 语音去口水红绿 Diff + 表情语义快筛 + 270+ Emoji 联想 + `VModeToolEngine` v3 生活速算**：知识卡支持直接导入最多 80 页 PDF 智能切片；语音同传「离线去口水」新增可切换 `LXDiffHighlightText` 红绿对照；键盘表情面板新增「全部/情绪/手势/职场/美食/祝福/动物」26pt 快筛栏；`v` 模式新增 `vaa368/4` AA 分摊、`v299z85` 折扣立省、`vbmi175/68` BMI 评估与 `v2027-01-01` 目标日期倒计时；⑤同步焕新 `README.md` 旗舰能力全景并新增 `testV70CommunicationGuardSmartInfoParserAndVModeV3`（第 83 项 XCTest）。
- v3.22（2026-11-27）：全仓 32 个 App 页面 + 16 个键盘面板逐页体检修复 + GitHub 顶流开源标杆双 flagship 能力落地——①**系统级「🕶 隐身无痕模式」（对标 HeliBoard / FlorisBoard）**：新增 `LingxiSettings.incognitoModeEnabled`、第 18 条仓式划动命令 `#incognito`（角标 `隐`）、键盘快捷设置 1 键开关、App「智能输入」开关、首页状态卡 `无痕中` 提醒徽标（点按即退）以及第 6 个原生系统捷径 `LingxiToggleIncognitoIntent`；开启后全面暂停词库自学习与二元词频记录、屏蔽 `PasteboardMonitor` 剪贴板捕获、暂停打字统计与习惯上报、禁止键盘 AI 回答写入历史；②**Cherry Studio 级纯 SwiftUI 富文本 Markdown + 代码块一键复制渲染（`Shared/MarkdownBlockParser.swift` + `App/Views/AI/LXMarkdownMessageView.swift`）**：纯 Foundation 解析标题/无序有序列表/引用/分割线/围栏代码块（原生兼容流式未闭合代码块），独立等宽代码块卡片自带语言徽标、横向滚动与 1 键「复制代码」，已接入多模态写作工作台、多模型圆桌会诊与参数化模板工坊；③**全页面深度体检缺陷清零**：新增 `ConcealedPasteboard.readNonConcealedStringForUserPaste()` 封堵剪贴板导入、跨屏接力上传、闪电指令台、圆桌会诊与变量模板误读保险箱受保护内容，修复跨屏接收错码 `LXRL1:` 密文误写系统剪贴板；修复 `HomeTestView` `statsDebounceTask` 离开未取消、多处垂直 `ScrollView` 缺 `.scrollDismissesKeyboard(.interactively)` 及 `AIWorkbenchSheet` / `AIAssistantPanelView` / `ScreenshotVisionPanelView` 3 处纯图标按钮 VoiceOver 缺失；新增 `testV69MarkdownBlockParserAndIncognitoMode` 单元测试。
- v3.21（2026-11-27）：旗舰级 AI 智脑跨代跃升（多模型圆桌会诊 MoA + 动态变量提示词表单 + 键盘多轮追问微调 + 端侧口述智能清洗）——①**多模型并发圆桌会诊与主席融合工坊（`App/Views/AI/AIMultiModelCouncilView.swift`，第 10 大工作台使首页 5×2 对称矩阵完备）**：对标 Cherry Studio / Mixture-of-Agents，支持跨协议跨渠道（Gemini / Claude / DeepSeek / OpenAI / Qwen）并发 2–4 席位实时流式同台竞技（带首字延迟/耗时/折叠思考链），单模型用户亦可一键切入「多专家视角圆桌」（务实执行官 / 批判审校官 / 破局创意官）；完稿后一键触发「主席综合裁决」汇总共识、指出分歧并融合输出终极一版，支持与任意席位逐字红绿 Diff 对比；②**Raycast 级动态 `{{变量}}` 参数化指令引擎（`Shared/PromptVariableEngine.swift` + `App/Views/AI/AIParameterizedRunnerView.swift`）**：支持 `{{名称|选项1,选项2}}` 胶囊快选、`{{名称=默认值}}` 与 `{{当前日期}}/{{当前城市}}/{{当前场景}}/{{剪贴板}}` 自动注入，内置 8 套高频专业参数化模板并自动纳管用户带变量的自定义技能，支持实时预览与一键固化装进键盘；③**键盘 AI 面板一键精调与多轮追问（`Keyboard/UI/AIAssistantPanelView.swift`）**：完稿后底部自动浮出紧凑精调条（`💬 追问` / `更短` / `更礼貌` / `更口语` / `更犀利` / `扩写` / `译英`），支持基于上一版回答连续迭代并无损压入 `sessionDrafts` 多版本切换栈；同时新增零联网 `🛡 离线脱敏` 与 `繁⇄简` 胶囊；④**豆包 / Wispr Flow 级 0ms 端侧口述智能清洗引擎（`Shared/VoiceTranscriptCleaner.swift`）**：100% 本地零延迟实现中英文口误回撤自动修正（「三点哦不对四点开会」→「四点开会」、「预算五万说错了八万」→「预算八万」）、语境安全去口水词（保护「那个项目」等实义短语）、结巴叠词合并（保护「哈哈哈」）与盘古排版，已贯通至 App 语音同传、键盘语音面板与 AI 首页闪电指令台（补齐离线排版/去口水/脱敏实时 Diff）；新增 `testV68PromptVariablesAndVoiceTranscriptCleaner` 全量单元测试。
- v3.20（2026-11-27）：引擎并发安全、中转站流式错误容灾与双 Web 控制台端到端加密互通——①**`PinyinEngine` SQLite 并发安全加固（`Keyboard/Engine/PinyinEngine.swift`）**：将只读词库打开标志由 `SQLITE_OPEN_NOMUTEX` 升级为 `SQLITE_OPEN_FULLMUTEX`，新增 `NSRecursiveLock` 保护全部 12 个查询/缓存/内存回收入口，彻底消除后台预热、主线程击键与 `didReceiveMemoryWarning()` 并发访问预处理语句与内存缓存的潜在竞态崩溃；②**修复中转站 HTTP 200 嵌入式 JSON 错误吞噬（`Shared/AIClient.swift`）**：新增 `AIClient.extractEmbeddedStreamError(from:)` 并接入 OpenAI / Gemini 流式 SSE 与非流式兜底路径，精准识别 OneAPI / NewAPI / OpenRouter 等代理在 HTTP 200 体内返回的限流/余额不足/过载错误，透出真实报错并正确触发 Auto-Failover 备用渠道切换（切换前自动清空残留隐私还原缓冲）；③**修复 `Server/dashboard.html` 存储型 XSS**：为 `renderB2BClients` 与 `renderAuditLogs` 全部动态字段补齐 `escHTML` 转义，移除内联字符串拼接的 `onclick` 参数；④**双 Web 控制台打通与 iOS 字节级兼容的 `LXRL1:` 端到端加密接力（`Server/dashboard.html` + `CloudflareWorker/src/dashboard.js`）**：基于浏览器原生 `Web Crypto API`（HKDF-SHA256 `salt="com.lingxi.sync"` / `info="lingxi-e2ee-sync.v1"` + AES-256-GCM 12B IV + Tag）实现与 iOS `SyncCrypto` / `ClipboardRelayCrypto` 100% 互通，电脑网页端自动解密手机端加密剪贴板（显示「🔒 E2EE 已解密」）并支持加密回传手机，云端与边缘节点全程零明文；新增 `testV67EmbeddedStreamErrorParsingAndPinyinThreadSafety` 单元测试。
- v3.19（2026-11-27）：全仓深度自检与底层稳定性/兼容性加固——①**消除 `URLSession` 原生内存泄漏（`Shared/AIClient.swift` + `CrossDeviceSyncAndRelay.swift`）**：修复此前 13 个 SwiftUI 视图重绘与键盘扩展内高频实例化 `AIClient()` 持续创建且永不 `invalidate` 独立 `URLSession` 的隐蔽内存泄漏（以及 `CommunityLexiconService.SyncRemotePacksFromServer()` 临时会话泄漏），升级为进程级共享 `.ephemeral` 连接池并透传请求级 `timeoutInterval`，同时获得 HTTP/2 与 TLS Keep-Alive 复用降延迟红利；②**Xcode 16 `AppShortcutsProvider` 合规修复 + 专注模式布局包捷径（`App/Intents/LingxiAppIntents.swift` + `App/LingxiApp.swift`）**：补齐 `@AppShortcutsBuilder` 与 `shortcutTileColor = .navy`、修正 `IntentDialog` 字符串插值、在 App 启动时调用 `LingxiAppShortcuts.updateAppShortcutParameters()` 主动注册系统捷径，并新增第 5 个原生捷径 `LingxiSwitchLayoutPackIntent`（专注模式一键切换 5 套键盘布局包）；同时为跨屏接力前台自动写入系统剪贴板补齐未解密 `LXRL1:` 密文与 L1 敏感内容防护；③**全仓 iOS 16.0 视觉与性能零缺陷修复**：替换全仓 8 处 iOS 17+ SF Symbols 5 图标（`gauge.with.dots.needle.67percent`/`book.pages`/`network.badge.shield.half.filled`/`photo.badge.plus`/`photo.badge.checkmark`）为 iOS 16 原生图标杜绝空白按钮；修复 `LexiconAndLocationHubView.body` 同步读盘违规（`GeoLocationContext.load()` 迁入 `@State` + `.onAppear`）；④**0ms 零联网斜杠宏指令（`/lint` `/mask` `/trad`）**：在任意宿主输入框输入 `/lint`（离线排版）、`/mask`（隐私脱敏）、`/trad`（繁⇄简互转）即可不需 API Key、0ms 原地一键生效并带撤销缓冲；⑤**永久化 CI 防回归门禁（`Tools/verify_swift_integrity.py`）**：新增 iOS 16.1+/17+ 禁用 API、SF Symbols 5 图标与 `AppShortcutsProvider` 规范自动拦截，新增 `testV66OfflineSlashMacrosSessionPoolingAndRelayGuard` 单元测试。
- v3.18（2026-11-27）：输入手感细节、专业编辑台与布局包全链路打通——①**统一成对括号智能引擎（`PairedBracketHelper` + `KeyboardViewController`）**：扩展至 12 组中英文成对符号（新增 `{}`、`『』`、`〈〉`、`<>`），支持单开自动补全居中、下划/符号面板直接点出成对符号（如 `()` `{}` `[]` `「」` `《》`）自动把光标置入括号中央（`(|)`）、紧邻闭括号直跳不重复以及空对内按 ⌫ 一次连删整对；②**4 行 16 键桌面级专业编辑台（`TextEditingPadView` + `KeyboardViewController`）**：修复编辑台 `.paste` 绕过 `ConcealedPasteboard` 的隐私盲区，新增「撤销」「按词删（英文整词/中文短词/连续标点智能断词）」以及第 4 行「离线排版 / 隐私脱敏 / 繁⇄简互转 / 去乱空行」零联网文本工坊行（全带撤销缓冲与触觉反馈）；③**布局包专属快捷符号条全链路生效（`NumberPadView` + `EmojiSymbolPanelView` + `KeyboardViewController`）**：将 5 套布局包的 `quickStripTokens` 真实贯通至数字盘左侧快捷符号轨与表情符号面板新增的「⚡ 布局专属」分类，且支持 `#命令` 直接执行；④**首页试打体验沙盒升级（`HomeTestView`）**：状态卡实时展示当前激活布局包，试打沙盒新增「离线体检样例 / 一键离线排版 / 一键转繁体 / 模拟验证码短信」互动演练条；新增 `testV65PairedBracketsLayoutPackStripAndEditPad` 全量单元测试。
- v3.17（2026-11-27）：输入法核心品质与生态再破界（OpenCC 两岸三地词级简繁 + 端侧语境同音重排 + 声明式布局包 + 键盘离线排版体检）——①**OpenCC 级两岸三地简繁词级双向引擎（`Shared/StylishTextConverter.swift`）**：`TraditionalChineseVariant` 支持「OpenCC 标准繁体 / 台湾正体（含两岸惯用词）/ 香港繁体」三标准，采用按长度哈希最大正向匹配（100+ 一简多繁消歧词组 + 90+ 两岸 IT/生活惯用词双向映射），`toSimplified` 自动归并「軟體/記憶體/滑鼠/伺服器/列印/的士」等地区词；App「智能输入」与键盘快捷设置抽屉实时可切；②**端侧零延迟语境同音消歧重排引擎（`Keyboard/Engine/ContextualReranker.swift` + `PinyinEngine`）**：0 MB 包体膨胀、0.02 ms 内存运算，打通末尾数字+量词/时刻/年份（`3+dian→点`、`2026+nian→年`）、星期/序数（`星期+yi→一`）及高频动宾搭配（`喝+shui→水` vs `去+shui→睡`、`写+daima→代码`、`发+weixin→微信`）；③**声明式可分享自定义键盘布局包（`Shared/CustomKeyboardPack.swift`）**：对标 Hamster / CustardKit 内置 5 套开箱即用专业布局包（标准平衡 / 仓式效率 / 程序员极客 / 写作创作者 / 商务办公），支持在键盘「快捷设置」1 键秒切与在 App「上下滑映射」中导出/导入 `.json` 布局包分享；④**键盘端零联网离线排版与脱敏闭环**：`KeyboardSwipeCommand` 新增第 17 种动作 `#lintFix`（`检`，0ms 离线原地修正重复字/标点/盘古空格并支持撤销），键盘 AI 面板新增无需 API Key 的「✓ 离线排版」胶囊（带体检报告与脱敏双版本草稿），剪贴板工具栏升级内置「排版」与「脱敏」一键上屏；新增 `testV64OpenCCContextRerankerLayoutPacksAndLintFix` 全量单元测试。
- v3.16（2026-11-27）：对标顶流开源项目（Hamster 仓输入法 / Rime-Ice 雾凇拼音 / Raycast & ProseKey / textlint & pangu / Apple AppIntents）的 4 大跨代旗舰模块——①**仓输入法级按键划动命令引擎（`Shared/KeyboardSwipeCommand.swift`）**：任意 26 键上滑/下划除字符外全面支持 16 种 `#命令` 原生动作（Rime 经典「以词定字」`#firstChar`/`#lastChar`、隐私粘贴 `#paste`、撤销 `#undo`、清空 `#clear`、光标左右 `#cursorLeft`/`#cursorRight`、中英 `#toggleLang`、简繁 `#toggleTrad`、AI 面板/润色/三版 `#aiPanel`/`#aiPolish`/`#ai3v`、边打边译 `#translate`、日期时间 `#date`/`#time`、`#newline`），键帽自动渲染 1–2 字微型高亮角标，`CustomSwipeKeymapEditorView` 新增可视化命令胶囊与「仓输入法效率命令预设」；②**全栈斜杠 AI 宏指令引擎（`Shared/AIAutoInsightService.swift` + `TopToolbarView` + `KeyboardViewController`）**：任意宿主输入框支持 10 大内置斜杠宏（`/fix`/`/en`/`/zh`/`/eq`/`/sum`/`/list`/`/xhs`/`/boss`/`/3v`/`/tr`）及用户自定义技能/流水线动态斜杠宏（如 `/周报`），同时支持「前缀带参」与「尾缀直接作用于前文」（并带严格 URL 边界防护防误触），全程内存缓存 0 磁盘 I/O；③**100% 离线中文文案与 AI 腔实时质检仪（`Shared/OfflineTextLinter.swift` + `App/Views/AI/AIOfflineLinterView.swift`）**：0ms 零联网扫描手滑重复字、联动个人文风 DNA 的 AI 腔/官腔词、盘古之白与中英标点混用、联动 `AIPrivacyShield` 的隐私外泄红灯及长难句/口播计时，支持一键自动修复与红绿逐字 Diff 对比（接入 AI 创作工具箱第 9 工坊）；④**原生 iOS 16 `AppIntents` + Siri 捷径 + 专注模式联动（`App/Intents/LingxiAppIntents.swift`）**：内置 4 大系统级捷径动作（AI 处理文本 / 离线文案体检排版 / 切换沟通场景适配专注模式自动化 / 随手存快捷短语）及 `AppShortcutsProvider`；新增 `testV63SwipeCommandsSlashMacrosOfflineLinter` 全量单元测试。
- v3.15（2026-11-27）：全链路性能优化、容灾与备份补盲、月预算守护与 `v` 工具引擎 v2——①**键盘热路径零磁盘 I/O 修复**：消除 `KeyboardViewController.refreshToolbar()` 每键经 `InlineAICommandDetector.detect(in:)` 隐式触发 `AIConfig.load()` 三文件同步读盘解码的性能隐患，改为内存缓存 `cachedAITriggerPrefix` / `cachedAIContextCharLimit`（仅在生命周期与配置变更通知刷新），并让用户自定义触发前缀（如 `!ai`/`#ai`）在键盘端真实生效；②**侧载容灾与多模态识图双补盲**：`SideloadConfigBridge` 打包桥接口令时保留已绑定的容灾备用渠道档案（剔除冗余模型缓存），确保免费侧载键盘同样支持自动容灾；`AIClient.streamVisionEvents` 补齐 `AIPrivacyShield` 提问词出网脱敏 + 流式还原，以及瞬时故障自动切换至支持视觉的备用渠道；③**备份与云同步零遗漏**：`.lingxibak` 加密备份纳入文风 DNA、多话题 AI 对话、生成历史、用量账本与触控校准 5 份核心 JSON；`AIPromptsSyncPayload` 扩展同步链式流水线与自定义隐私词，并将知识卡与流水线合入策略升级为按标题/ID 增量并集；④**成本精细化与月度预算守护**：`AICostEstimator` 精准区分 Claude Haiku/Sonnet/Opus 与 O1/O3/Grok/Kimi/MiniMax 单价，新增 `currentMonthEstimatedUSD` 自然月统计；用量账本页新增本月预算提醒档位（不限/¥15/¥30/¥50/¥100）与进度条，超 80%/100% 时在 AI 智脑状态卡柔和提示，并补全 `kb_three_variants`、`live_translate` 中文标签；⑤**键盘 `v` 模式离线生产力工具 v2（`VModeToolEngine`）**：零延迟离线新增相对日期（`v+3d`/`v-7d`/`v+2w`/`v+1m`/`vmingtian`）、精准单位换算（`v180cm`/`v65kg`/`v38c`/`v98f`/`v10km`/`v100ping`/`v1.5gb`）及极客生成（`vts`/`vuuid`）；新增 `testV62PerformanceFailoverBackupBudgetAndVModeTools` 全量单元测试。
- v3.14（2026-11-26）：AI 智脑 v6 协议与端侧体验深度进化——①**Anthropic Claude 原生第三协议**：`AIProvider` 扩展为三协议（Gemini / OpenAI 兼容 / Claude 原生），`AIClient` 原生实现 `/v1/messages` 流式 SSE、`/v1/models` 动态拉取、连续同角色消息自动合并、Extended Thinking（`thinking.budget_tokens` 与 `temperature` 互斥保护 + 旧模型 400 自动降级）、原生 base64 多模态识图及 `input_tokens`/`output_tokens` 真实统计；②**生产级自动容灾切换（Auto-Failover）**：`AIConfig` 支持为当前渠道绑定备用档案（`failoverProfileID`），当主渠道尚未输出正文且遭遇 `402/429/5xx/URLError` 瞬时故障时，`AIClient` 自动无缝切换至备用通道并真实记账，绝不对 `CancellationError` 或客户端 400/401 误切；③**端侧零依赖 RAG-Lite 与文档切片**：`PersonalContextCard` 新增中英双轨（ASCII 词 + 中文二元组）相关性打分检索（`selectRelevantCards`，自动按场景与提问召回 Top-4 知识卡省 Token）及 Markdown/TXT 智能切片导入（`chunkDocument`），知识卡页面支持 `.fileImporter` 导入与「RAG 命中试测」沙盒；④**键盘 AI 面板非破坏性多版本草稿与一键三版**：`AIAssistantPanelView` 新增顶部紧凑 `‹ 上一版 | 第 1/3 版 | 下一版 ›` 切换条，「重试」追加新版不再覆盖旧稿，新增「✨ 三版」一键并发生成职场得体/温和亲切/极简干脆三版，同时升级「博弈军师」将潜台词收入折叠区、三套话术直进草稿切换条支持任意版本一键插入；⑤**无密钥 AI 智脑配置包与编译器/真机加固**：新增 `AIBrainExportBundle` 导出/增量导入（含人设、文风 DNA、技能、知识卡、流水线、隐私词，严格零 API Key 泄漏）；`LXDiffHighlightText` 升级为官方 iOS 16 `AttributeContainer` + `container.swiftUI.*` 显式作用域消除 UIKit 混编歧义；`AISpeechSpeaker` 补齐 `AVAudioSession(.playback, mode: .spokenAudio, options: [.duckOthers])` 真机外放会话；新增 `testV61AnthropicProtocolFailoverRAGAndBrainBundle` 单元测试。
- v3.13（2026-11-26）：全仓安全隐私深度加固 + App「AI 智脑」v5 旗舰重构——①**安全与隐私闭环**：本地保险箱 `SecureSnippetVault` 升级 `LXV1` + AES-256-GCM 静态加密（Keychain 256 位密钥，兼容旧明文无缝迁移）；云端凭据 `CloudCredentialStore` 仅在 Keychain 失败时落盘回退，新增端侧 PBKDF2 零知识主密钥与 `LXE2` 密文信封（加密失败拒传明文）；侧载桥接口令改走 `ConcealedPasteboard`（仅本机 90 秒过期）；键盘全路径剪贴板读取接入 `ConcealedPasteboard.readNonSensitiveString`；跨屏接力新增 `LXRL1:` 可选 AES-256-GCM 端到端加密信封、消除 `URLSession.shared`、双后端接入 `ADMIN_TOKEN` 鉴权与按 IP 滑动窗口防爆破限流、补齐双后端全部路由差异（`/api/v1/sync/summary`、`/api/v1/compliance/export`、`/api/v1/sustainability/status`、`/api/v1/auth/apple-device`）；②**端侧 AI 三大新底座**：新增 `Shared/AIPrivacyShield.swift`（端侧 AI 隐私脱敏护盾：6 大内置敏感类型 + 自定义私密词 + 流式无闪烁还原缓冲，全链路保护 App 与键盘）、纯 Swift LCS 逐字红绿 Diff 引擎（`AITextDiffEngine`）及主流模型 Token 费用估算器（`AICostEstimator`）；`AIClient` 新增多轮流式对话、OpenAI `o1/o3/o4/gpt-5` 推理载荷适配、真实 Token 解析、视觉/语音独立路由与全路由并行基准测速；③**App「AI 智脑」v5 旗舰矩阵（`App/Views/AI/` 12 文件模块化架构）**：首页首屏嵌入「闪电即用指令台（含实时红绿 Diff）」+「8 大专精创作工具箱」——多话题多模态写作工作台（话题抽屉、相册/剪贴板带图追问 + 纯文本模型自动 OCR 兜底、TTS 语音朗读、多轮调教提炼为键盘技能、System Prompt 透视镜）、多风格三版并发改写 & 二维语气精调 Diff 实验室、12 套结构化场景模板写作与长文拆解器、8 语专业翻译台（双向回译校验 + 地道精讲 + 双语朗读）、多步 AI 链式流水线工坊（串联流式执行 + 一键编译装进键盘）、AI 隐私脱敏护盾与试测沙盒、全路由并发测速体检、近 7 天趋势图与估算费用账本；④**键盘联动与门禁**：键盘 AI 面板完整同步自定义内置技能排布、全部自定义技能、语境智能推荐、场景人设秒切、博弈军师、自定义 `@ai` 触发前缀、上下文读取字数与隐私脱敏护盾；`verify_swift_integrity.py` 增加括号配对与 iOS 16 兼容门禁，新增 `testV59SecurityHardeningAndAIV4Upgrades` 与 `testV60FlagshipAIPrivacyDiffCostPipelinesAndRelayCrypto` 全量单元测试。
- v3.12（2026-11-26）：隐私与无障碍——①**跨屏接力共用通道**：`ClipboardRelayConfig.pairCode` 默认是所有人相同的 `886699`，且自动接收默认开启——没改过码的用户全在一个通道里，会互相收到对方的剪贴板内容（包括验证码）。新安装改为随机 6 位码；读取时发现旧共用码或空码自动换成本机随机码（只有写入共享目录成功才换，避免键盘未开完全访问时每次读到不同的码）；两个网页控制台去掉默认码，未输入时提示「请先输入手机上显示的 6 位匹配码」。新增测试 `testRelayPairCodeIsNeverTheLegacySharedDefault`；②**登录回调静默失败**：从浏览器回到 App 完成通行密钥登录时，错误被 `try?` 吞掉，用户不知道登没登上——改为成功 / 失败都在首页底部提示（`AppState.globalToastMessage / globalErrorMessage`）；③**跟随系统字号**：49 处正文 `.font(.system(size:))` 改为对应文本样式（13→footnote、15→subheadline、17→body 等，默认字号下视觉几乎不变）；图标、固定高度胶囊、键盘预览（外观页、工具栏页）、键位网格保持固定字号；根视图上限 `accessibility3`；④语音唤醒文案去 emoji、改成人话。
- v3.11（2026-11-26）：「词库管理」页重做——①**搜索漏词**：个人词库原先只显示 / 搜索最近 250 条（AppState 缓存上限），老词搜不到；本页改为自行读取最多 2000 条，拼音搜索忽略空格与撇号；②**导入在手机上几乎不可用**：TSV 要求 Tab，iOS 键盘打不出 Tab——新增 `Shared/LexiconTSVParser`，「编码,内容」「编码，内容」「编码=内容」自动转换（编码不是纯字母时保持原样，避免拆坏内容里的逗号）；导入弹窗实时显示「可导入 N 条」，规则与存储层一致，0 条时禁用导入；支持粘贴和从「文件」选择；原导入框会预填导出内容，用户不清空就再导入一遍，已改为空白 + 示例占位；③**导出走剪贴板**：整个词库复制到会跨设备同步、会被其他键盘读到的通用剪贴板，改为导出 .tsv 文件；④编码实时校验（只能英文字母）；长按短语可复制 / 编辑 / 删除，编辑在保存时才替换旧条目，中途离开不丢；添加以「条目确实写入」为准提示成功；空状态、加载态；社区词包显示词数与已订阅标记，订阅后刷新列表；清空确认显示条数并建议先导出；置顶 / 遗忘 / 删除均有提示。新增单元测试 `testLexiconTSVParserPreviewMatchesImportRules`。
- v3.10（2026-11-26）：「灵犀账号」页重做 + 两处编译风险修复——①**编译错误修复**：v3.7 在账号页写的 `[NamespaceSyncSummary]` 是 `CloudBackendClient` 的嵌套类型，未加前缀会报「找不到类型」，已改为 `CloudBackendClient.NamespaceSyncSummary`（新增嵌套类型扫描，全 App 仅此一处）；两处 `.transition(条件 ? .opacity : .move…)` 改为显式 `AnyTransition`，避免 iOS 17+ SDK 下 `.opacity` 同名类型推断歧义；②**修改密码只输一次**：E2EE 数据用新密码重新加密，输错一个字就再也解不开——新增「再输入一次」并实时提示不一致 / 过短；失败时弹窗保持打开并在弹窗内显示原因（此前弹窗先关、错误提示被挡）；修改中禁止下滑关闭；③**静默覆盖剪贴板**：账号页打开时会订阅跨屏接力推流，收到内容就直接写入系统剪贴板，无视「自动接收」开关——账号页移除重复的接力区块与推流订阅，改为跳转「跨屏剪贴板接力」专页（该页按开关行为）；顺带去掉「草稿为空且剪贴板为空时仍推送空内容」的问题；④未登录时只显示登录入口与本机备份入口，不再展示 0/10 同步进度、云端习惯开关等用不了的内容；登录按钮去掉 Apple 标志；同步、测试连接、重新签发各自独立加载态并防重复点击；头像颜色热区补足；文案去「E2EE · LXE1」「Cloudflare D1」「级联物理删除」等术语。
- v3.9（2026-11-26）：「同步方式与词库维护」页重做（原「可持续发展与多模同步」）——①**修复**：原页面的「Open-Core 服务层级」可以随手点选，点「免费版」会把同步方式静默改成 `localNoop`，已登录用户的云端自动同步就此停止且无任何提示；点「Pro / 企业版」则是没有付费流程的假升级——该选择器已移除，开源承诺改为只读说明，`planTier` 字段保留不动；②同步方式改为白话三选一（只在本机 / 同一 Wi-Fi 互传 / 云端加密同步），选云端但未登录时就地给出「去登录」，选局域网时提示填对方地址；③局域网互传：只在选了局域网或正在接收时显示；对方地址拦截 127.0.0.1 / localhost（指向本机，互传无意义），配对码限 6 位数字并注明与跨屏接力共用；失败时提示排查方向；首次使用会弹本地网络权限的说明；④词库健康：环形健康分 + 3 项指标（偶然词、剪贴板过多时警示色），去掉「架构铁律」「LXE1」「NWListener」「ChaCha20」等开发者术语；⑤社区词包：词包数量改为出现时读取（此前每次重绘都读文件）；「更新已订阅」在未订阅时置灰；离线获取失败改为普通提示而非成功；自定义词包表单实时统计有效词条，名称为空或无有效词条时不能保存；⑥登录弹窗密码字段的 `textContentType` 三目表达式写明 `UITextContentType` 类型，避免类型推断歧义。
- v3.8（2026-11-25）：登录与数据安全细节——①CI 防护：`verify_swift_integrity.py` 新增脱敏占位符（`[REDACTED_*]`）与合并冲突标记检查，这类内容只有编译时才会暴露，现在在 CI 第一步就拦截；②登录弹窗：「一键登录」按钮去掉苹果 Logo（该按钮并非「通过 Apple 登录」，按苹果人机界面规范不能使用 Apple 标志），图标随设备显示面容 ID / 触控 ID；去掉渐变紫色品牌块（§1 禁止彩色渐变）；按钮改用 ink / canvas 令牌，删除深色模式下不成立的「点上方黑色按钮」；邮箱表单加本地校验（邮箱格式、注册密码 ≥ 6 位，未填好时按钮置灰）并去除首尾空格；接入系统密码自动填充（`username` / `password` / `newPassword`），密码框回车直接提交；三个登录入口加防重复提交；「暂不登录」热区补足 44pt；文案去技术腔；③保险箱：`BiometricAuthHelper.verify` 在设备未设锁屏密码时会直接放行，此前页面仍显示「Face ID 保护」——新增 `isDeviceSecured` 并在锁定页如实警告；解锁图标随设备显示面容 ID / 触控 ID；④同步与自愈：「一键清理与修复」会删除只用过一次的自学习词并裁剪剪贴板，此前一点即执行，现加确认并写明删什么、不删什么；`isLANListening` 等 `@State` 初始值不再触发服务调用。
- v3.7（2026-11-25）：性能、深色模式、iPad 与隐私细节——①性能：「设置」主页、云同步页每次重绘都调用 `diagnose()`（新开词库连接 + 读 2000 词 + 4 个文件），账号页每次重绘都调用 `syncNamespaceDashboardSummary()`（开词库 + 读约 10 个文件，且实时接力推送会持续触发重绘），AI 页输入 API Key 时每敲一字重读历史文件，打字统计页弹提示也重算周报 / 30 天 / 词库领域——全部改为进入页面或数据变化时计算一次；②深色模式：PK 页「B」徽标白字落在深色模式变浅的 ink 底上看不见，改为 canvas 字；③小屏：总览、模型列表、技能预览里一行 3 个标签在 iPhone SE 宽度会溢出，改为 `LXFlowLayout`；④iPad：新增 `.lxReadableWidth()`，9 个滚动页内容限宽 680pt；⑤隐私：账号页「复制 API Key」改走 `ConcealedPasteboard`；「导出全部数据」由写入系统剪贴板（会经通用剪贴板同步到其他设备、会被键盘记进历史）改为保存 JSON 文件；「重新签发 API Key」加确认（旧 Key 立即失效）；账号页常驻顶部的状态 / 错误横条改为底部浮动提示；⑥工具栏设置：预览此前固定画 5 个按钮，与真实排列不符（漏掉截屏、语音、表情，忽略顺序），改为与键盘 `TopToolbarView` 相同的左右分簇与顺序；⑦提示条：成功 / 失败加触觉反馈；文案判断逻辑移到 `Shared/ToastText.swift` 并补单元测试，测试过程中发现 `"⚠️".hasPrefix("⚠")` 在 Swift 中为 false 导致警告被显示为成功，已修复；⑧`@State` 初始值读盘：同步页 `healthReport = diagnose()`、账号页 / 跨屏接力 / 可持续页读取接力配置、打字统计读取校准数据、词库页读取订阅——它们都是 NavigationLink 目标，上级页面每次重绘都会被重新创建并执行初始值，改为轻量占位 + 出现时加载（新增 `EngineHealthReport.placeholder`）；⑨新增 §12 组件库与硬性规则。
- v3.6（2026-11-25）：自签稳定性审查 + 语音同传 / 截屏识图 / 备份恢复 / 地名词库重做——①CI 门禁：单元测试为无宿主（TEST_HOST 为空）模式，改为不触碰系统剪贴板的纯逻辑测试，避免测试失败阻断 IPA 打包；`ConcealedPasteboard` 拆出 `makeItem` / `isConcealed(types:)` 纯函数；②并发与崩溃防护：方法引用改为闭包（避免 Xcode 16.4 / Swift 6.1 编译器下的 MainActor 隔离告警升级）；相册取图 continuation 加只恢复一次保护；`LXFlowLayout` 处理无限宽提议；保险箱验证 Face ID 期间不因 inactive 误上锁；全仓强制解包逐一复核均有前置保护；③语音同传：底部固定大号麦克风，录音中禁止编辑原文（此前会被识别结果覆盖），麦克风启动失败时恢复后台语音引擎，防连点重复启动，清空加确认，去 emoji；④截屏识图：预览置顶，识别方式改为带说明的 2×2 卡片，App 内标题去 emoji（键盘侧保持不变），清理原图开关下沉并写清剪贴板 / 相册两种行为，技巧默认折叠；⑤备份恢复：显示上次备份时间，密码强度与不一致实时提示，取消保存不再报错，导入允许选择任意文件（由文件头校验），写明备份包含 / 不包含的内容；`project.yml` 新增 `.lingxibak` 类型声明（此前未声明，文件面板可能无法识别）；⑥地名词库：去 emoji，权限被拒时直接引导设置，城市快捷选择改为流式布局，分类只显示有内容的。
- v3.5（2026-11-25）：打字统计 / 权限中心 / 启用引导重做 + 不可逆操作补确认——①打字统计：修复「记录每日打字量」开关关闭时重复出现两次；近 30 天趋势改为按日历补齐 30 天（此前直接跳过没打字的日子，柱状图会误导），标出今天与 30 天合计 / 日均；24 小时时段标出高峰；易混音统计达 2 次可直接一键开启对应模糊音；热力图加图例；词库领域无数据时隐藏；「清除全部数据」「重置校准」加二次确认（此前一点即删）；去掉标题 emoji 与 CPM 等术语；②权限中心：核心 3 项（添加键盘 / 完全访问 / AI 密钥）与可选 4 项分开计数，顶部只保留一个随进度切换的主按钮，取代「点右侧再点左侧」的方位指引；可选权限逐项写明用在哪个功能；区分「未请求 / 已拒绝」，已拒绝的直接引导去设置；一键授权只对未问过的权限弹窗，结束后如实汇报「新开启几项、几项未允许」（此前不论结果都提示「已全部申请」）；补充「完全访问」的用途说明；③启用引导：原「第一步」里含步骤 1、2 的混乱编号改为 3 步，每步实时打勾，当前步骤高亮，主按钮在「打开系统设置 / 去首页试打」间切换，从系统设置返回自动刷新；④账号页「清除云端与本机习惯画像」「退出登录」、位置词库「清除缓存」补二次确认。
- v3.4（2026-11-25）：细节审校与隐私修正——①保险箱：复制改为 `ConcealedPasteboard`（`localOnly` 不经通用剪贴板、90 秒自动过期、带 `org.nspasteboard.ConcealedType` 标记），键盘 `PasteboardMonitor` / 剪贴板面板识别标记后不入历史、不弹预览（此前税号、地址等不匹配敏感规则的内容会被键盘记进历史，与页面文案不符）；列表默认脱敏显示（原有 `maskedPreview` 此前未使用），逐条可显示；切到后台自动上锁；删除二次确认；新增单元测试；②对比度：信息类文字从 `muted`（约 2.3:1）改为 `stone`（4.62:1），`muted` 只留给占位文字和装饰图标，符合 §2「辅助文字 ≥ 4.5:1」；③点按热区：`LXCapsuleButtonStyle` 视觉 32pt、热区补足 44pt（§9）；④提示条：按文案自动区分成功 / 提示 / 失败图标，去掉上游消息自带的 ✓ 前缀避免重复，支持「减弱动态效果」与 VoiceOver 播报；⑤用量账本把内部功能标签（ai_direct、arena_a…）翻译成中文；删除指南里指向不存在入口的「3 选 1」描述；⑥跨屏接力：匹配码限 6 位数字并实时校验、发送 / 接收分别显示进度、电脑端三步说明与地址一键复制；表情库 Emoji 与符号改为网格；滑行映射切换按键自动保存、未保存标记、预设与重置二次确认；⑦外观子页：调色板加实时迷你键盘预览，锁定深浅色时隐藏无效的日夜切换；壁纸选择显示进度与失败提示，移除前确认，阴影可一键回默认；皮肤分享支持系统分享面板，导入前确认。
- v3.3（2026-11-25）：设置中心 7 个二级页统一——新增 `LXToggleRow`（标题 + 一行白话说明）与 `LXNavRow`（图标块入口行）；开关文案去技术腔（如「26键滑行输入 (Glide Typing 中英轨迹成词)」→「滑行输入 · 手指在 26 键上连续滑过即可打出中英文词」）；五笔设置在非五笔方案下置灰并提示；模糊音按声母 / 韵母分组，每组可一键全开 / 全关，并附例字（知道 / 自道）；趣味字体由下拉改为带实时预览的单选列表；词库、云同步页改为图标入口行，备份显示上次时间、未备份时警示色；共享诊断页把 App Group 技术字段收进「技术详情」折叠区，进阶玩法去 emoji。所有设置键与跳转目标逐项比对，零遗漏。
- v3.2（2026-11-25）：App 全 Tab 统一视觉——①新增 `App/Views/LingxiComponents.swift` 共享组件库（LXCard / LXIconTile / LXTag / LXCapsuleButtonStyle / LXFlowLayout / LXEmptyState / LXRemovableChip / LXAddFieldRow / `.lxToast` 底部浮动提示条），AI 智脑页改为引用共享组件；②首页：三态状态卡（未启用 / 差完全访问 / 已就绪，每态只有一个主操作）+ 今日打字卡（带「详细统计」入口）+ 新增「常用功能」四宫格（语音互译 / 截屏识图 / AI 智脑 / 换皮肤）+ 试打区（聚焦描边、复制 / 清空）；③外观：键盘预览置顶为主视觉，恢复默认加二次确认，预设主题改为迷你键盘缩略图卡片，进阶定制入口带说明；④工具：剪贴板筛选改为带计数的胶囊，点按记录即复制、验证码标签单独一键复制，右滑置顶 / 左滑删除或炸词，清空加确认；快捷短语加空状态与渲染预览块；修复快捷短语页操作提示不显示的问题；⑤设置：入口图标统一为 LXIconTile，底部显示版本号与隐私承诺；⑥全 App 移除硬编码 `.orange`，统一为 `Design.Palette.warning`。
- v3.1（2026-11-25）：App「AI 智脑」全页面 UI 重排（`App/Views/AISettingsView.swift`，逻辑与数据接口零改动）——①首页：状态卡（就绪状态 + 测速延迟徽标 + 完整模型名一键复制 + 「测速连通 / 打开试炼场」44pt 双主按钮 + 权限/侧载同步提示条），常用服务商独立分组（选中打勾），协议改分段控件，高级参数折叠且带摘要，能力中心改为「图标 + 标题 + 说明 + 徽标」行；②5 个子页：提示词市场（双入口卡 + 置顶分组 + 左滑/长按操作 + 内置技能流式标签墙）、文风 DNA（主卡 + 流式可删词条 + 回车添加 + 知识卡左滑删除）、智能画像（空状态引导 + 画像主卡 + 一键优化 + 改进建议编号列表）、历史与账本（2×2 数据格 + 最近调用延迟着色 + 展开收起 + 清空二次确认）、模型选择（系统搜索栏 + 当前模型 + 错误重试卡）；③弹窗：试炼场（示例快填 + 运行中可停止 + 首字/总耗时/字数指标 + PK 交换 A/B + 从列表选模型 + 更快徽标 + 设为主模型）、文风克隆（样本计数 + 占位示例 + 底部固定主按钮）、知识卡/技能编辑（预设标签、实时预览、字数计数）、指令市场（系统搜索 + 底部「全部装入」）；④统一组件：AIIconTile / AITag / AICapsuleButtonStyle / AIFlowLayout / AIEmptyState / AICard / 底部浮动提示条（成功 2.5s、失败 5s 自动消失），移除硬编码橙色与 emoji 标签，全部走 `Design.Palette`。
- v3.0（2026-11-22）：键盘顶栏重设计 + 剪贴板/验证码全栏独占接管 + 云端后端与实时打字习惯画像系统——①键盘顶栏（`TopToolbarView.swift` / `PasteboardMonitor.swift` / `LingxiSettings.swift`）：彻底移除顶栏低频『表情』、『光标移动』与『⋯』折叠菜单；常规态重构为 30pt 黄金高度双簇布局（左置『✨ 灵犀 AI』『💬 译』胶囊，右置弹性分隔的『剪贴板』『设置』）；当用户第一次复制内容或收到短信验证码时，自动隐藏常规工具按钮，整栏切换为「全宽验证码一键填入 / 刚复制内容预览与粘贴」智能胶囊，粘贴或关闭后立即恢复；②后端数据库与服务（`Server/schema.sql` + `Server/lingxi_server.py`）：对标 Vaultwarden、Atuin 与 Wakapi，构建 SQLite WAL / PostgreSQL 兼容的 6 表架构（`users`, `auth_sessions`, `sync_records`, `typing_habit_events`, `ai_api_usage_logs`, `user_typing_profiles`），支持邮箱密码、Sign in with Apple 与客户专属 API Key（`lx_live_...`）双通道鉴权；③重要数据全量 LWW 云同步（`CompositeSyncSource` + `UserLexiconSyncSource`）：将个人自学习词库（`user_dict.sqlite`）、自定义短语（`custom.tsv`）、全局设置与皮肤主题全部纳入 `(lamport_ts, device_id)` 全序 LWW 同步；④实时打字习惯与 API 分析引擎（`TypingHabitTracker` + `CloudBackendClient` + `CloudAccountView`）：客户接入 API 后实时分析击键速率（CPM）、词长习惯、退格/撤学率、滑行占比、24 小时昼夜节律及 AI/翻译调用偏好，生成习惯画像标签与可一键应用的引擎调优建议。
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
