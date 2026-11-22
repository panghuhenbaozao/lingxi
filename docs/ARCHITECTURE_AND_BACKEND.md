# 灵犀输入法 (Lingxi IME) v4.0 全栈架构与开源对标设计说明书

本文档完整对应八部分《产品架构总览与技术规范》，涵盖：**键盘顶部栏重设计（含剪贴板/短信验证码全栏独占接管）**、**跨设备实时剪贴板接力（6 位匹配码免登录秒传 + SSE 实时推流）**、**后端可视化 Web 控制台 / 客户管理看板 (`Server/dashboard.html`)**、**三实现可插拔同步层 (`LocalNoop` / `LAN 局域网` / `E2EE Cloud`)**、**纵深五层安全体系 (L1–L5)**、**11 表生产级数据库 (`Server/schema.sql`)** 以及 **PIPL / GDPR 双合规与 B 端企业画像 API**。

---

## 一、 四条不可动摇的架构铁律与开源对标

1. **键盘扩展永不发起网络请求**：`Keyboard/` 进程零网络权限诉求，所有习惯指标与剪贴板/词库变更均通过 App Group (`group.com.lingxi.keyboard`) 落盘，由主 App 进程统一完成网络通信。
2. **离线是默认态且永远完整可用**：对标 **HeliBoard (`Helium314/HeliBoard`)**，未登录状态下全拼/双拼/九键/笔画、词库、皮肤、加密备份、局域网双机同步、本地统计 100% 完整可用。
3. **同步零知识 (E2EE)**：对标 **Bitwarden / Vaultwarden (`dani-garcia/vaultwarden`)**，端侧采用 `SyncCrypto` (`Argon2id/HKDF-SHA256` + `ChaCha20-Poly1305` / `AES-256-GCM`) 封装 `"LXE1"` 密文信封，服务端仅存取密文 blob，数学上无法解密用户词库或短语。
4. **同步与分析物理分离**：对标 **Atuin (`atuinsh/atuin`)** 与 **Wakapi (`muety/wakapi`)**，同步通道 (`sync_records` + `sync_state`) 与分析通道 (`typing_habit_events` + `user_typing_profiles`) 分表、分接口、分权限，分析通道需显式授权 (`consent_records`) 且永不含任何打字原文。

---

## 二、 键盘顶部栏 (TopToolbarView v3) 与跨屏实时剪贴板接力

### 1. 彻底清理低频干扰项并迁入主 App
- 从 [LingxiSettings.swift](file:///D:/Lingxi/Shared/LingxiSettings.swift) 的 `ToolbarButtonID` 与 [TopToolbarView.swift](file:///D:/Lingxi/Keyboard/UI/TopToolbarView.swift) 中彻底移除 **表情 (`emoji`)**、**光标移动 (`edit`)** 以及 **`⋯` 聚合折叠按钮**。
- 在主 App 的 [ClipboardPhrasesView.swift](file:///D:/Lingxi/App/Views/ClipboardPhrasesView.swift) 中新增第三个分段 **「表情与颜文字」**，支持搜索与一键复制常用 Emoji、颜文字及特殊符号。

### 2. 双簇极简常规态（30pt 黄金胶囊高度）
- **左主功能簇 (`leftClusterStack`)**：`[✨ 灵犀 AI]` 与 `[💬 译]`。
- **右轻量工具簇 (`rightClusterStack`)**：通过弹性留白分隔，仅放置 `[剪贴板]` 与 `[快捷设置]`（及可选的 `[九键/26键]`、刚删字时浮现的 `[↩ 撤销]`）。

### 3. 短信验证码 / 新复制内容「全栏独占接管态」（Full-Bar Takeover）
- 当 [PasteboardMonitor.swift](file:///D:/Lingxi/Keyboard/Services/PasteboardMonitor.swift) 检测到系统剪贴板有新复制内容、短信验证码或跨设备接力内容时，`leftClusterStack` 与 `rightClusterStack` 全部隐藏（且在 [KeyboardViewController.swift](file:///D:/Lingxi/Keyboard/KeyboardViewController.swift) 的 `refreshToolbar()` 中主动压制非打字态的 Bigram 联想候选词），由 `bannerContainer` 100% 独占顶栏宽度：
  - **短信验证码到达**：展示 `[💬 验证码]` + 等宽验证码与摘要 + **`[填入 849201]`** + `[全文]` + `[✕]`。
  - **刚复制的内容**：展示 `[📋 刚复制]` / `[🔗 新链接]` + 复制文本全宽预览 + **`[粘贴]`** + `[✨ AI]` + `[✕]`。

### 4. 跨设备实时剪贴板接力（对标微信输入法跨屏剪贴板）
- **端侧实现**：[CrossDeviceSyncAndRelay.swift](file:///D:/Lingxi/Shared/Services/CrossDeviceSyncAndRelay.swift) 中的 `ClipboardRelayService` 支持 **6 位数字匹配码（如 `886699`）免登录跨设备秒传**。
- **服务端实现**：[lingxi_server.py](file:///D:/Lingxi/Server/lingxi_server.py) 提供 `POST /api/v1/relay/clipboard`、`GET /api/v1/relay/clipboard` 以及 **SSE 实时推流端点 `GET /api/v1/relay/stream?pairCode=886699`**，自动提取短信/文本中的 4–8 位验证码并在 Web 控制台与手机端之间毫秒级双向接力。

---

## 三、 后端可视化 Web 控制台 / 客户管理看板 (`Server/dashboard.html`)

启动 `python Server/lingxi_server.py` 后，浏览器访问 **`http://127.0.0.1:8787/dashboard`**（或根路径 `/`）即可打开极简白/墨玉美学设计的可视化管理后台：
1. **全局 KPI 与 API 调用趋势看板**：实时展示注册用户与 API 客户数、E2EE 密文同步库条数、累计分析字数、AI/翻译 API 调用量及平均延迟。
2. **24 小时打字时段活跃热力曲线**：直观呈现全站与单用户的昼夜输入节律与每小时 CPM 峰值。
3. **拼音易混音纠错热力矩阵 (`zh↔z`, `sh↔s`, `ch↔c`, `an↔ang`, `en↔eng`, `in↔ing`, `n↔l`)**：定量展示用户在各组易混音上的触发频次，并联动下发模糊音调优建议。
4. **用户词库领域偏好热力图 (`科技与研发` / `商务与职场` / `日常与社交` / `学术与创作`)**：基于客户端脱敏聚合的个人词库领域分布。
5. **跨设备实时剪贴板接力工作台（6 位匹配码 + SSE 实时流）**：支持在电脑浏览器与手机端之间免登录一键互传文本、链接与短信验证码。
6. **B 端企业 API 客户管理、180 天审计流水与 PIPL/GDPR 合规流水**：支持在线签发 `lxb_live_...` 企业 Key、在线调试 `/api/v1/b2b/cohort-insights` 群体画像接口，并实时查阅 `b2b_audit_logs` 与 `consent_records`。

---

## 四、 可插拔三实现同步层与纵深五层安全体系 (L1–L5)

### 1. 三套 `SyncService` 可插拔实现
- **`LocalNoopSyncService`**（[SyncInfra.swift](file:///D:/Lingxi/Shared/Services/SyncInfra.swift)）：默认纯本地离线实现。
- **`LANSyncService`**（[CrossDeviceSyncAndRelay.swift](file:///D:/Lingxi/Shared/Services/CrossDeviceSyncAndRelay.swift)）：M2 局域网同 Wi-Fi 双机直连同步，基于 Apple 原生 `Network.framework` (`NWListener` / `NWConnection`) + 6 位配对码派生的 `ChaCha20-Poly1305` 加密通道，无需经过任何云端服务器。
- **`CloudBackendClient`**（[CloudBackendClient.swift](file:///D:/Lingxi/Shared/Services/CloudBackendClient.swift)）：M3 零知识 E2EE 云同步，基于 `(lamport_ts, device_id)` 全序 LWW 寄存器合并与 `sync_state` 每设备增量水位线，覆盖 7 大核心命名空间（`settings`, `theme`, `phrases`, `quickPhrases`, `recentEmojis`, `typingStats`, `lexicon`）。

### 2. 纵深五层安全体系 (STRIDE 威胁建模落地)
- **L1 端侧**：
  - `isSecureField` 密码框四项联动：禁学习、禁缓存、禁剪贴板、禁日志；
  - [AppGroup.swift](file:///D:/Lingxi/Shared/AppGroup.swift) 默认启用 `FileProtectionType.completeUntilFirstUserAuthentication`；
  - [ClipboardStore.swift](file:///D:/Lingxi/Shared/ClipboardStore.swift) `ClipboardClassifier.isSensitiveContent` 自动识别并屏蔽 18 位身份证号、Luhn 校验银行卡号、PEM 私钥与显式密码串，不进顶栏横幅、不落历史。
- **L2 密钥学**：
  - `Argon2id/HKDF-SHA256` 派生主密钥，密码永不上传；
  - [SyncCrypto.swift](file:///D:/Lingxi/Shared/Services/SyncCrypto.swift) 同时支持 `ChaCha20-Poly1305` (`sealChaChaPoly` / `openChaChaPoly`) 与 `AES-256-GCM`；
  - 支持 `POST /api/v1/auth/rotate-key` 密钥轮换与全量重加密事务。
- **L3 传输**：
  - `SyncCrypto.signRequest` 生成 `HMAC-SHA256(body‖ts‖nonce)` 请求签名（`X-Lingxi-Timestamp` / `X-Lingxi-Nonce` / `X-Lingxi-Signature`），服务端强制校验 5 分钟防重放窗口。
- **L4 服务端**：
  - `user_id` 一律取自鉴权 Token，跨租户访问直接拦截 (`403 Forbidden`)；
  - 三维滑动窗口限流（`user_id` + `IP` + `api_client`：登录 5 次/分、上报 60 次/时）；
  - B 端企业走独立 `lxb_live_...` Service Key + Scope 白名单，所有画像查询写入 `b2b_audit_logs` 保留 180 天。
- **L5 供应链与自检**：
  - `python Server/lingxi_server.py --self-test` 自动化覆盖全部 8 大架构章节端到端回归测试。

---

## 五、 服务端最终版 11 表数据模型 (`Server/schema.sql`)

| 序号 | 表名 | 职责与核心字段 |
|---|---|---|
| 1 | `users` | 用户主表：`id`, `apple_sub`, `email`, `kdf_salt`, `kdf_params`, `plan`, `analytics_opt_in`, `opt_in_at`, `api_key_hash`, `e2ee_salt` |
| 2 | `devices` | 设备表：`id, user_id, name, platform, app_ver, last_seen` |
| 3 | `auth_sessions` | 多设备会话刷新令牌表：`token_id, user_id, device_id, refresh_token_hash, expires_at` |
| 4 | `sync_records` (`sync_items`) | 零知识 E2EE 同步表：主键 `(user_id, namespace, record_key)`，存 `ciphertext_b64, nonce, lamport_ts, device_id, tombstone` |
| 5 | `sync_state` | 每设备增量同步水位线：主键 `(user_id, device_id)`，存 `last_seen_lamport` |
| 6 | `consent_records` | PIPL/GDPR 不可变授权审计流水：`id, user_id, scope, granted, at, ip, policy_version` |
| 7 | `typing_habit_events` (`typing_sessions`) | 分析通道事件表（与同步表物理隔离，**无任何原文字段**）：存 `committed_chars, delete_count, confusion_json, active_hour` |
| 8 | `ai_api_usage_logs` | AI 与边打边译 API 调用指标表：`feature, provider, target_lang, formal_tone, latency_ms` |
| 9 | `user_typing_profiles` (`typing_profiles`) | 实时物化打字画像表：`avg_cpm, hourly_rhythm_json, confusion_matrix_json, lexicon_domain_json, habit_tags_json, tuning_recommendations_json` |
| 10 | `api_clients` & `b2b_audit_logs` | B 端企业客户凭证 (`lxb_live_...`, `scopes`, `rate_limit`) 与 180 天不可变查询审计日志 |
| 11 | `clipboard_relays` | 跨设备 6 位匹配码实时剪贴板接力表：`pair_code, content, content_kind, extracted_code, expires_at` |
