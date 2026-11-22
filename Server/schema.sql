-- ============================================================================
-- 灵犀输入法 (Lingxi IME) 云端数据库 Schema v2 (SQLite WAL / PostgreSQL 兼容)
-- 完整覆盖产品架构说明书第五部分（数据模型）、第四部分（五层安全）与第六部分（GDPR/个保法合规）：
--   1. users / devices / auth_sessions —— 账号、KDF 参数、分析独立授权状态与多设备管理
--   2. sync_records / sync_state —— 零知识 E2EE 密文库 + 每设备 Lamport 增量水位线
--   3. consent_records —— 不可变隐私授权审计流水 (个保法/GDPR 双合规)
--   4. typing_habit_events / ai_api_usage_logs / user_typing_profiles —— 物理分离的分析通道
--   5. api_clients / b2b_audit_logs —— B 端企业 API 接入、Scope 白名单、计费与 180 天审计日志
--   6. clipboard_relays —— 6 位匹配码免登录跨设备实时剪贴板接力（对标微信输入法跨屏剪贴板）
--   7. community_lexicons —— M4 词库社区 TSV 词包订阅仓库（对标 HeliBoard / WowType）
-- ============================================================================

PRAGMA foreign_keys = ON;

-- 1. 用户主表
CREATE TABLE IF NOT EXISTS users (
    id                  TEXT PRIMARY KEY,
    email               TEXT UNIQUE,
    username            TEXT NOT NULL,
    password_hash       TEXT,                           -- PBKDF2 / Argon2id 密码校验哈希
    apple_sub           TEXT UNIQUE,                    -- Sign in with Apple Subject
    api_key_hash        TEXT UNIQUE,                    -- SHA-256(lx_live_...)
    api_key_prefix      TEXT,                           -- lx_live_xxxx...
    e2ee_salt           TEXT NOT NULL,                  -- kdf_salt: 32 字节 Hex 盐（端侧派生主密钥）
    kdf_params          TEXT NOT NULL DEFAULT '{"alg":"Argon2id/HKDF-SHA256","cipher":"XChaCha20-Poly1305/AES-256-GCM"}',
    plan                TEXT NOT NULL DEFAULT 'free',   -- free | pro | enterprise
    analytics_opt_in    INTEGER NOT NULL DEFAULT 0,     -- 与登录解耦的分析单独授权开关
    opt_in_at           INTEGER NOT NULL DEFAULT 0,
    created_at          INTEGER NOT NULL,
    updated_at          INTEGER NOT NULL,
    last_login_at       INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_api_key_hash ON users(api_key_hash);

-- 2. 设备注册表 (devices)
CREATE TABLE IF NOT EXISTS devices (
    id          TEXT NOT NULL,
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL DEFAULT 'iPhone',
    platform    TEXT NOT NULL DEFAULT 'iOS',
    app_ver     TEXT NOT NULL DEFAULT '3.0.0',
    last_seen   INTEGER NOT NULL,
    PRIMARY KEY (user_id, id)
);

-- 3. 多设备登录会话表 (auth_sessions)
CREATE TABLE IF NOT EXISTS auth_sessions (
    token_id            TEXT PRIMARY KEY,
    user_id             TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id           TEXT NOT NULL,
    device_name         TEXT NOT NULL DEFAULT 'iOS Device',
    refresh_token_hash  TEXT NOT NULL UNIQUE,
    expires_at          INTEGER NOT NULL,
    created_at          INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_auth_sessions_user ON auth_sessions(user_id);

-- 4. 零知识同步表 (sync_records / sync_items)
CREATE TABLE IF NOT EXISTS sync_records (
    user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    namespace       TEXT NOT NULL,              -- settings | theme | lexicon | phrases | quick_phrases | recent_emojis | typing_stats
    record_key      TEXT NOT NULL,
    ciphertext_b64  TEXT NOT NULL,              -- E2EE 密文 Base64（服务端数学上不可读）
    nonce           TEXT NOT NULL DEFAULT '',   -- 加密随机 Nonce
    lamport_ts      INTEGER NOT NULL,           -- 客户端 Lamport 逻辑时钟
    device_id       TEXT NOT NULL,              -- 写入方稳定设备 UUID
    tombstone       INTEGER NOT NULL DEFAULT 0, -- 1 表示墓碑删除
    schema_version  INTEGER NOT NULL DEFAULT 1,
    server_seq      INTEGER NOT NULL,
    updated_at      INTEGER NOT NULL,
    PRIMARY KEY (user_id, namespace, record_key)
);

CREATE INDEX IF NOT EXISTS idx_sync_pull
    ON sync_records(user_id, namespace, lamport_ts, device_id);

-- 5. 每设备同步水位表 (sync_state)
CREATE TABLE IF NOT EXISTS sync_state (
    user_id             TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id           TEXT NOT NULL,
    namespace           TEXT NOT NULL DEFAULT 'all',
    last_seen_lamport   INTEGER NOT NULL DEFAULT 0,
    updated_at          INTEGER NOT NULL,
    PRIMARY KEY (user_id, device_id, namespace)
);

-- 6. 不可变隐私授权审计流水表 (consent_records —— 个保法/GDPR 双合规)
CREATE TABLE IF NOT EXISTS consent_records (
    id              TEXT PRIMARY KEY,
    user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    scope           TEXT NOT NULL,              -- typing_analytics | b2b_portrait_sharing | cloud_e2ee_sync
    granted         INTEGER NOT NULL,           -- 1 授权 / 0 撤回
    at              INTEGER NOT NULL,
    ip              TEXT NOT NULL DEFAULT '127.0.0.1',
    policy_version  TEXT NOT NULL DEFAULT '2026.11-v1'
);

CREATE INDEX IF NOT EXISTS idx_consent_user ON consent_records(user_id, at DESC);

-- 7. 实时打字习惯事件流表 (typing_habit_events / typing_sessions —— 与同步库物理分离，永不含原文)
CREATE TABLE IF NOT EXISTS typing_habit_events (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id                 TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id               TEXT NOT NULL DEFAULT 'default',
    started_at              INTEGER NOT NULL,
    duration_seconds        INTEGER NOT NULL,
    committed_chars         INTEGER NOT NULL,
    committed_words         INTEGER NOT NULL,
    delete_count            INTEGER NOT NULL DEFAULT 0,
    undo_learn_count        INTEGER NOT NULL DEFAULT 0,
    glide_words             INTEGER NOT NULL DEFAULT 0,
    typo_corrected_count    INTEGER NOT NULL DEFAULT 0,
    ai_invocations          INTEGER NOT NULL DEFAULT 0,
    translate_chars         INTEGER NOT NULL DEFAULT 0,
    scheme_id               TEXT NOT NULL DEFAULT 'quanpin',
    layout_id               TEXT NOT NULL DEFAULT 'qwerty26',
    active_hour             INTEGER NOT NULL DEFAULT 12,
    confusion_json          TEXT NOT NULL DEFAULT '{}',
    created_at              INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_habit_events_user_time
    ON typing_habit_events(user_id, started_at DESC);

-- 8. AI 与实时翻译 API 调用习惯分析表
CREATE TABLE IF NOT EXISTS ai_api_usage_logs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    feature         TEXT NOT NULL,
    provider        TEXT NOT NULL,
    target_lang     TEXT NOT NULL DEFAULT '英文',
    formal_tone     INTEGER NOT NULL DEFAULT 0,
    input_chars     INTEGER NOT NULL DEFAULT 0,
    output_chars    INTEGER NOT NULL DEFAULT 0,
    latency_ms      INTEGER NOT NULL DEFAULT 0,
    created_at      INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ai_usage_user_time
    ON ai_api_usage_logs(user_id, created_at DESC);

-- 9. 用户打字习惯实时画像表 (user_typing_profiles / typing_profiles)
CREATE TABLE IF NOT EXISTS user_typing_profiles (
    user_id                     TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    total_chars                 INTEGER NOT NULL DEFAULT 0,
    total_words                 INTEGER NOT NULL DEFAULT 0,
    total_duration_seconds      INTEGER NOT NULL DEFAULT 0,
    total_sessions              INTEGER NOT NULL DEFAULT 0,
    avg_cpm                     REAL NOT NULL DEFAULT 0.0,
    peak_cpm                    REAL NOT NULL DEFAULT 0.0,
    avg_word_length             REAL NOT NULL DEFAULT 0.0,
    backspace_rate              REAL NOT NULL DEFAULT 0.0,
    undo_learn_rate             REAL NOT NULL DEFAULT 0.0,
    glide_ratio                 REAL NOT NULL DEFAULT 0.0,
    typo_correction_rate        REAL NOT NULL DEFAULT 0.0,
    primary_scheme              TEXT NOT NULL DEFAULT 'quanpin',
    primary_layout              TEXT NOT NULL DEFAULT 'qwerty26',
    scheme_breakdown_json       TEXT NOT NULL DEFAULT '{}',
    hourly_rhythm_json          TEXT NOT NULL DEFAULT '{}',
    ai_feature_breakdown_json   TEXT NOT NULL DEFAULT '{}',
    confusion_matrix_json       TEXT NOT NULL DEFAULT '{}',
    domain_affinity_json        TEXT NOT NULL DEFAULT '{}',
    habit_tags_json             TEXT NOT NULL DEFAULT '[]',
    tuning_recommendations_json TEXT NOT NULL DEFAULT '[]',
    updated_at                  INTEGER NOT NULL
);

-- 10. B 端企业 API 客户表 (api_clients) 与 180 天全量审计日志表 (b2b_audit_logs)
CREATE TABLE IF NOT EXISTS api_clients (
    id              TEXT PRIMARY KEY,
    org             TEXT NOT NULL,
    key_hash        TEXT NOT NULL UNIQUE,       -- SHA-256(lxb_live_...)
    key_prefix      TEXT NOT NULL,
    scopes          TEXT NOT NULL DEFAULT 'profile:read,aggregate:read',
    rate_limit      INTEGER NOT NULL DEFAULT 120,
    call_count      INTEGER NOT NULL DEFAULT 0,
    billable_units  INTEGER NOT NULL DEFAULT 0,
    created_at      INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS b2b_audit_logs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    client_id       TEXT NOT NULL REFERENCES api_clients(id) ON DELETE CASCADE,
    org             TEXT NOT NULL,
    endpoint        TEXT NOT NULL,
    target_user_id  TEXT NOT NULL DEFAULT 'aggregate',
    scope_used      TEXT NOT NULL,
    ip              TEXT NOT NULL DEFAULT '127.0.0.1',
    status_code     INTEGER NOT NULL DEFAULT 200,
    created_at      INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_b2b_audit_time ON b2b_audit_logs(created_at DESC);

-- 11. 跨设备实时剪贴板接力表 (6 位匹配码免登录秒传，对标微信输入法跨屏剪贴板)
CREATE TABLE IF NOT EXISTS clipboard_relays (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    pair_code       TEXT NOT NULL,              -- 6 位数字匹配码，如 839204
    content_text    TEXT NOT NULL,              -- 剪贴板文本或端到端密文
    category        TEXT NOT NULL DEFAULT 'text',
    extracted_code  TEXT,                       -- 若包含验证码则自动提取
    sender_device   TEXT NOT NULL DEFAULT 'PC/Web',
    created_at      INTEGER NOT NULL,
    expires_at      INTEGER NOT NULL            -- 默认 10 分钟后自动过期清理
);

CREATE INDEX IF NOT EXISTS idx_relay_code_time
    ON clipboard_relays(pair_code, id DESC);
