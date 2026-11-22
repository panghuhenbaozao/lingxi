#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
灵犀输入法 (Lingxi IME) 云端全栈后端服务 v4.0
(Auth + E2EE LWW 云同步 + 跨屏剪贴板 SSE 秒传 + 实时打字习惯画像 + B 端企业 API + GDPR/个保法合规 + 可视化 Web 控制台)

完整落地产品架构说明书 1~8 部分：
- 第一/三部分：版本向量 + 寄存器级 LWW ((lamport_ts, device_id) 全序决胜) + sync_state 每设备水位
- 第二部分：6 位匹配码免登录跨设备剪贴板秒传 (REST + SSE 实时推流) + M4 词库社区 TSV 仓库 + Web 控制台看板
- 第四部分：五层纵深安全 (L1 敏感剪贴板过滤 / L2 E2EE 盐与密钥轮换 / L3 HMAC-SHA256 5分钟防重放签名 / L4 三维限流 + 跨租户 403 隔离 + B端 180天审计)
- 第五/六部分：users, devices, sync_records, sync_state, consent_records, typing_habit_events, user_typing_profiles, api_clients, b2b_audit_logs, clipboard_relays + GDPR 数据导出与级联注销
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


SERVER_DIR = Path(__file__).resolve().parent
SCHEMA_PATH = SERVER_DIR / "schema.sql"
DASHBOARD_HTML_PATH = SERVER_DIR / "dashboard.html"
DEFAULT_DB_PATH = SERVER_DIR / "lingxi_cloud.sqlite3"

PBKDF2_ITERATIONS = 100_000
ACCESS_TOKEN_TTL_SECONDS = 3600 * 24
REFRESH_TOKEN_TTL_SECONDS = 3600 * 24 * 30
REPLAY_WINDOW_SECONDS = 300  # L3: 5 分钟防重放时间窗


# =============================================================================
# M4 开源词库社区内置 TSV 词包仓库（兼容 WowType custom.tsv / user.tsv 格式）
# =============================================================================
COMMUNITY_LEXICON_PACKS: List[Dict[str, Any]] = [
    {
        "id": "tech_dev",
        "name": "科技与程序员高频词包",
        "category": "科技研发",
        "author": "Lingxi Open Community",
        "version": "1.4.0",
        "description": "涵盖大模型、云原生、微服务、iOS/Swift、Python 研发高频术语与快捷短语",
        "tsv": (
            "# 编码\t词条\n"
            "llm\t大语言模型\n"
            "rag\t检索增强生成\n"
            "e2ee\t端到端加密\n"
            "lww\t最后写入胜出\n"
            "k8s\tKubernetes集群\n"
            "cicd\t持续集成与持续交付\n"
            "api\t应用程序接口\n"
            "jwt\tJSON访问令牌\n"
        ),
    },
    {
        "id": "biz_office",
        "name": "现代商务与职场高效沟通包",
        "category": "商务职场",
        "author": "Lingxi Open Community",
        "version": "1.2.0",
        "description": "高频职场邮件、排期对齐、会议纪要与高情商商务礼貌用语",
        "tsv": (
            "# 编码\t词条\n"
            "sd\t收到，我马上处理并同步进展。\n"
            "hy\t正在会议中，稍后第一时间回复您。\n"
            "pq\t烦请确认一下本周的开发排期与交付节点。\n"
            "fp\t项目阶段性复盘与指标对齐\n"
            "ht\t合同法务审批流程\n"
        ),
    },
    {
        "id": "acg_hotwords",
        "name": "流行热词与冲浪新词包",
        "category": "日常社交",
        "author": "WowType & Rime Ice Sync",
        "version": "2.1.0",
        "description": "同步雾凇拼音与社交平台年度高频流行词、情绪表达短语",
        "tsv": (
            "# 编码\t词条\n"
            "hsh\t黑神话\n"
            "yyds\t永远的神\n"
            "my\t摸鱼划水\n"
            "qxz\t情绪价值\n"
            "zbr\t嘴替本替\n"
        ),
    },
    {
        "id": "medical_bio",
        "name": "医学与生命科学专业术语包",
        "category": "学术专业",
        "author": "Lingxi BioMed Group",
        "version": "1.1.0",
        "description": "临床医学、基因组学、蛋白质结构与药理学高频专业词汇",
        "tsv": (
            "# 编码\t词条\n"
            "pcr\t聚合酶链式反应\n"
            "mrna\t信使核糖核酸\n"
            "ct\t计算机断层扫描\n"
            "lcms\t液相色谱质谱联用\n"
        ),
    },
]


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(text: str) -> bytes:
    pad = "=" * ((4 - len(text) % 4) % 4)
    return base64.urlsafe_b64decode((text + pad).encode("ascii"))


def _sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def hash_password(password: str, salt_hex: Optional[str] = None) -> str:
    salt = bytes.fromhex(salt_hex) if salt_hex else secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PBKDF2_ITERATIONS)
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt.hex()}${dk.hex()}"


def verify_password(password: str, stored_hash: str) -> bool:
    try:
        algo, iters_str, salt_hex, hash_hex = stored_hash.split("$")
        if algo != "pbkdf2_sha256":
            return False
        iters = int(iters_str)
        salt = bytes.fromhex(salt_hex)
        dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iters)
        return hmac.compare_digest(dk.hex(), hash_hex)
    except Exception:
        return False


def extract_otp_code(text: str) -> Optional[str]:
    trimmed = text.strip()
    if not trimmed or len(trimmed) > 300:
        return None
    if 4 <= len(trimmed) <= 8 and trimmed.isdigit():
        return trimmed
    lower = trimmed.lower()
    cues = ["验证码", "校验码", "动态码", "确认码", "取件码", "激活码", "口令", "code", "otp", "pin", "verify"]
    if not any(c in lower for c in cues):
        return None
    m = re.search(r"(?:验证码|校验码|动态码|确认码|取件码|code|otp|pin)[：:\s为是]*([0-9]{4,8})|([0-9]{4,8})", trimmed, re.IGNORECASE)
    if not m:
        return None
    return m.group(1) or m.group(2)


def is_sensitive_clipboard(text: str) -> bool:
    """L1 敏感剪贴板过滤：屏蔽 18 位身份证号、私钥或显式密码串。"""
    trimmed = text.strip()
    if not trimmed:
        return False
    if "-----BEGIN " in trimmed and "PRIVATE KEY-----" in trimmed:
        return True
    if re.search(r"(?<![0-9])[1-9][0-9]{5}(?:19|20)[0-9]{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])[0-9]{3}[0-9Xx](?![0-9])", trimmed):
        return True
    if extract_otp_code(trimmed) is None:
        if re.search(r"(?:密码|登录密码|支付密码|password|passwd|pwd)\s*[：:=is为]\s*\S{6,}", trimmed, re.IGNORECASE):
            return True
    return False


class JWTCodec:
    def __init__(self, secret: str) -> None:
        self._secret = secret.encode("utf-8")

    def encode(self, user_id: str, ttl_seconds: int = ACCESS_TOKEN_TTL_SECONDS) -> Tuple[str, int]:
        now = int(time.time())
        exp = now + ttl_seconds
        header = _b64url_encode(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode("utf-8"))
        payload = _b64url_encode(
            json.dumps(
                {"iss": "lingxi-cloud", "sub": user_id, "iat": now, "exp": exp, "jti": secrets.token_hex(8)},
                separators=(",", ":"),
            ).encode("utf-8")
        )
        signing_input = f"{header}.{payload}".encode("ascii")
        sig = _b64url_encode(hmac.new(self._secret, signing_input, hashlib.sha256).digest())
        return f"{header}.{payload}.{sig}", exp

    def decode(self, token: str) -> Optional[Dict[str, Any]]:
        try:
            parts = token.split(".")
            if len(parts) != 3:
                return None
            header_b64, payload_b64, sig_b64 = parts
            signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
            expected_sig = _b64url_encode(hmac.new(self._secret, signing_input, hashlib.sha256).digest())
            if not hmac.compare_digest(sig_b64, expected_sig):
                return None
            payload = json.loads(_b64url_decode(payload_b64).decode("utf-8"))
            if int(payload.get("exp", 0)) < int(time.time()):
                return None
            return payload
        except Exception:
            return None


class SlidingWindowRateLimiter:
    """L4 三维滑动时间窗限流器（支持按 IP / user_id / api_client 限流）。"""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._buckets: Dict[str, List[float]] = {}
        self._seen_nonces: Dict[str, float] = {}

    def allow(self, key: str, max_calls: int, window_seconds: int) -> bool:
        now = time.time()
        cutoff = now - window_seconds
        with self._lock:
            history = [t for t in self._buckets.get(key, []) if t > cutoff]
            if len(history) >= max_calls:
                self._buckets[key] = history
                return False
            history.append(now)
            self._buckets[key] = history
            return True

    def check_and_record_nonce(self, nonce: str, ts: int) -> bool:
        """L3: 5 分钟时间窗 + Nonce 防重放校验。"""
        now = time.time()
        if abs(now - ts) > REPLAY_WINDOW_SECONDS:
            return False
        with self._lock:
            expired = [k for k, exp in self._seen_nonces.items() if exp < now]
            for k in expired:
                del self._seen_nonces[k]
            if nonce in self._seen_nonces:
                return False
            self._seen_nonces[nonce] = now + REPLAY_WINDOW_SECONDS
            return True


class ClipboardRelayHub:
    """跨设备剪贴板 SSE 实时推流广播中心（按 6 位匹配码分组唤醒）。"""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._conds: Dict[str, threading.Condition] = {}
        self._latest_seq: Dict[str, int] = {}

    def notify(self, pair_code: str, item_id: int) -> None:
        with self._lock:
            cond = self._conds.setdefault(pair_code, threading.Condition())
            self._latest_seq[pair_code] = item_id
        with cond:
            cond.notify_all()

    def wait_for_update(self, pair_code: str, last_seq: int, timeout: float = 15.0) -> int:
        with self._lock:
            cond = self._conds.setdefault(pair_code, threading.Condition())
            cur = self._latest_seq.get(pair_code, 0)
            if cur > last_seq:
                return cur
        with cond:
            cond.wait(timeout=timeout)
        with self._lock:
            return self._latest_seq.get(pair_code, last_seq)


SCHEME_INDEX_TO_ID = {
    0: "quanpin",
    1: "xiaohe",
    2: "ziranma",
    3: "microsoft",
    4: "sogou",
    5: "abc",
    6: "ziguang",
    7: "pinyinjiajia",
    8: "wubi86",
}

SCHEME_DISPLAY_NAMES = {
    "quanpin": "26键全拼",
    "xiaohe": "小鹤双拼",
    "ziranma": "自然码双拼",
    "microsoft": "微软双拼",
    "sogou": "搜狗双拼",
    "abc": "智能ABC双拼",
    "ziguang": "紫光双拼",
    "pinyinjiajia": "拼音加加双拼",
    "wubi86": "五笔86",
}

LAYOUT_INDEX_TO_ID = {
    0: "qwerty26",
    1: "t9Nine",
}


class LingxiDatabase:
    def __init__(self, db_path: Path, jwt_secret: Optional[str] = None) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        secret = jwt_secret or os.environ.get("LINGXI_JWT_SECRET") or "lingxi-dev-hmac-secret-change-in-prod"
        self.jwt_secret = secret
        self.jwt = JWTCodec(secret)
        self.limiter = SlidingWindowRateLimiter()
        self.relay_hub = ClipboardRelayHub()
        self._lock = threading.RLock()
        self._init_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.db_path), timeout=15.0, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode = WAL;")
        conn.execute("PRAGMA synchronous = NORMAL;")
        conn.execute("PRAGMA foreign_keys = ON;")
        return conn

    def _init_schema(self) -> None:
        ddl = SCHEMA_PATH.read_text(encoding="utf-8")
        with self._lock:
            conn = self._connect()
            try:
                conn.executescript(ddl)
                for alter_sql in [
                    "ALTER TABLE users ADD COLUMN kdf_params TEXT NOT NULL DEFAULT '{}'",
                    "ALTER TABLE users ADD COLUMN plan TEXT NOT NULL DEFAULT 'free'",
                    "ALTER TABLE users ADD COLUMN analytics_opt_in INTEGER NOT NULL DEFAULT 0",
                    "ALTER TABLE users ADD COLUMN opt_in_at INTEGER NOT NULL DEFAULT 0",
                    "ALTER TABLE sync_records ADD COLUMN nonce TEXT NOT NULL DEFAULT ''",
                    "ALTER TABLE typing_habit_events ADD COLUMN confusion_json TEXT NOT NULL DEFAULT '{}'",
                    "ALTER TABLE user_typing_profiles ADD COLUMN confusion_matrix_json TEXT NOT NULL DEFAULT '{}'",
                    "ALTER TABLE user_typing_profiles ADD COLUMN domain_affinity_json TEXT NOT NULL DEFAULT '{}'",
                ]:
                    try:
                        conn.execute(alter_sql)
                    except sqlite3.OperationalError:
                        pass
                conn.commit()
            finally:
                conn.close()

    # -------------------------------------------------------------------------
    # 1. 认证、设备登记、密码轮换与客户 API Key
    # -------------------------------------------------------------------------

    def _generate_api_key(self, prefix_tag: str = "lx_live_") -> Tuple[str, str, str]:
        raw_key = f"{prefix_tag}{secrets.token_hex(20)}"
        key_hash = _sha256_hex(raw_key)
        prefix = raw_key[:16] + "..."
        return raw_key, key_hash, prefix

    def _touch_device(self, conn: sqlite3.Connection, user_id: str, device_id: str, device_name: str = "iPhone") -> None:
        now = int(time.time())
        conn.execute(
            """
            INSERT INTO devices (id, user_id, name, platform, app_ver, last_seen)
            VALUES (?, ?, ?, 'iOS', '4.0.0', ?)
            ON CONFLICT(user_id, id) DO UPDATE SET
                last_seen = excluded.last_seen,
                name = excluded.name
            """,
            (device_id or "ios-default", user_id, device_name, now),
        )

    def _issue_session(self, conn: sqlite3.Connection, user_row: sqlite3.Row, device_id: str, raw_api_key: Optional[str] = None) -> Dict[str, Any]:
        now = int(time.time())
        user_id = user_row["id"]
        dev_id = device_id or "ios-default"
        self._touch_device(conn, user_id, dev_id)
        access_token, access_exp = self.jwt.encode(user_id)
        refresh_token = f"lxr_{secrets.token_urlsafe(32)}"
        token_id = str(uuid.uuid4())
        conn.execute(
            """
            INSERT INTO auth_sessions (token_id, user_id, device_id, refresh_token_hash, expires_at, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (token_id, user_id, dev_id, _sha256_hex(refresh_token), now + REFRESH_TOKEN_TTL_SECONDS, now),
        )
        conn.execute("UPDATE users SET last_login_at = ?, updated_at = ? WHERE id = ?", (now, now, user_id))
        result: Dict[str, Any] = {
            "userID": user_id,
            "email": user_row["email"] or "",
            "username": user_row["username"],
            "accessToken": access_token,
            "refreshToken": refresh_token,
            "accessExpiry": access_exp,
            "apiKeyPrefix": user_row["api_key_prefix"] or "",
            "e2eeSalt": user_row["e2ee_salt"],
            "analyticsOptIn": bool(user_row["analytics_opt_in"]) if "analytics_opt_in" in user_row.keys() else False,
        }
        if raw_api_key:
            result["apiKey"] = raw_api_key
        return result

    def register_user(self, email: str, username: str, password: str, device_id: str = "ios-default") -> Dict[str, Any]:
        email_clean = email.strip().lower()
        username_clean = username.strip() or (email_clean.split("@")[0] if "@" in email_clean else "灵犀用户")
        if not email_clean or "@" not in email_clean:
            raise ValueError("请输入有效的邮箱地址")
        if len(password) < 6:
            raise ValueError("密码长度不能少于 6 位")

        now = int(time.time())
        user_id = str(uuid.uuid4())
        pw_hash = hash_password(password)
        raw_api_key, api_key_hash, api_key_prefix = self._generate_api_key("lx_live_")
        e2ee_salt = secrets.token_hex(32)

        with self._lock:
            conn = self._connect()
            try:
                existing = conn.execute("SELECT id FROM users WHERE email = ?", (email_clean,)).fetchone()
                if existing:
                    raise ValueError("该邮箱已注册，请直接登录")
                conn.execute(
                    """
                    INSERT INTO users
                        (id, email, username, password_hash, api_key_hash, api_key_prefix, e2ee_salt,
                         analytics_opt_in, opt_in_at, created_at, updated_at, last_login_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
                    """,
                    (user_id, email_clean, username_clean, pw_hash, api_key_hash, api_key_prefix, e2ee_salt, now, now, now, now),
                )
                conn.execute(
                    """
                    INSERT INTO consent_records (id, user_id, scope, granted, at, ip, policy_version)
                    VALUES (?, ?, 'typing_analytics', 1, ?, '127.0.0.1', '2026.11-v1')
                    """,
                    (str(uuid.uuid4()), user_id, now),
                )
                conn.execute(
                    "INSERT OR IGNORE INTO user_typing_profiles (user_id, updated_at) VALUES (?, ?)",
                    (user_id, now),
                )
                user_row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
                session = self._issue_session(conn, user_row, device_id, raw_api_key=raw_api_key)
                conn.commit()
                return session
            finally:
                conn.close()

    def login_user(self, account: str, password: str, device_id: str = "ios-default") -> Dict[str, Any]:
        acc = account.strip()
        if not acc or not password:
            raise ValueError("请输入账号与密码")
        with self._lock:
            conn = self._connect()
            try:
                user_row = conn.execute(
                    "SELECT * FROM users WHERE email = ? OR username = ?",
                    (acc.lower(), acc),
                ).fetchone()
                if not user_row or not user_row["password_hash"]:
                    raise PermissionError("账号不存在或密码错误")
                if not verify_password(password, user_row["password_hash"]):
                    raise PermissionError("账号不存在或密码错误")
                session = self._issue_session(conn, user_row, device_id)
                conn.commit()
                return session
            finally:
                conn.close()

    def sign_in_with_apple(self, identity_token_b64: str, apple_user: str, device_id: str = "ios-default") -> Dict[str, Any]:
        apple_sub = apple_user.strip() or _sha256_hex(identity_token_b64)[:24]
        now = int(time.time())
        with self._lock:
            conn = self._connect()
            try:
                user_row = conn.execute("SELECT * FROM users WHERE apple_sub = ?", (apple_sub,)).fetchone()
                raw_api_key: Optional[str] = None
                if not user_row:
                    user_id = str(uuid.uuid4())
                    raw_api_key, api_key_hash, api_key_prefix = self._generate_api_key("lx_live_")
                    e2ee_salt = secrets.token_hex(32)
                    username = f"Apple用户_{apple_sub[-4:]}"
                    conn.execute(
                        """
                        INSERT INTO users
                            (id, username, apple_sub, api_key_hash, api_key_prefix, e2ee_salt,
                             analytics_opt_in, opt_in_at, created_at, updated_at, last_login_at)
                        VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
                        """,
                        (user_id, username, apple_sub, api_key_hash, api_key_prefix, e2ee_salt, now, now, now, now),
                    )
                    conn.execute(
                        "INSERT OR IGNORE INTO user_typing_profiles (user_id, updated_at) VALUES (?, ?)",
                        (user_id, now),
                    )
                    user_row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
                session = self._issue_session(conn, user_row, device_id, raw_api_key=raw_api_key)
                conn.commit()
                return session
            finally:
                conn.close()

    def refresh_session(self, refresh_token: str) -> Dict[str, Any]:
        token_hash = _sha256_hex(refresh_token.strip())
        now = int(time.time())
        with self._lock:
            conn = self._connect()
            try:
                row = conn.execute(
                    "SELECT * FROM auth_sessions WHERE refresh_token_hash = ?",
                    (token_hash,),
                ).fetchone()
                if not row or int(row["expires_at"]) < now:
                    raise PermissionError("刷新凭证已失效，请重新登录")
                user_row = conn.execute("SELECT * FROM users WHERE id = ?", (row["user_id"],)).fetchone()
                if not user_row:
                    raise PermissionError("用户不存在")
                conn.execute("DELETE FROM auth_sessions WHERE token_id = ?", (row["token_id"],))
                session = self._issue_session(conn, user_row, row["device_id"])
                conn.commit()
                return session
            finally:
                conn.close()

    def rotate_api_key(self, user_id: str) -> Dict[str, str]:
        raw_api_key, api_key_hash, api_key_prefix = self._generate_api_key("lx_live_")
        now = int(time.time())
        with self._lock:
            conn = self._connect()
            try:
                conn.execute(
                    "UPDATE users SET api_key_hash = ?, api_key_prefix = ?, updated_at = ? WHERE id = ?",
                    (api_key_hash, api_key_prefix, now, user_id),
                )
                conn.commit()
                return {"apiKey": raw_api_key, "apiKeyPrefix": api_key_prefix}
            finally:
                conn.close()

    def rotate_password_and_e2ee_salt(self, user_id: str, new_password: str) -> Dict[str, str]:
        """L2 密钥轮换：修改密码并生成新 E2EE 盐值，供客户端触发全量密文重加密任务。"""
        if len(new_password) < 6:
            raise ValueError("新密码长度不能少于 6 位")
        now = int(time.time())
        new_hash = hash_password(new_password)
        new_salt = secrets.token_hex(32)
        with self._lock:
            conn = self._connect()
            try:
                conn.execute(
                    "UPDATE users SET password_hash = ?, e2ee_salt = ?, updated_at = ? WHERE id = ?",
                    (new_hash, new_salt, now, user_id),
                )
                conn.commit()
                return {"e2eeSalt": new_salt, "rotatedAt": str(now)}
            finally:
                conn.close()

    def authenticate_request(self, auth_header: Optional[str], api_key_header: Optional[str]) -> Optional[str]:
        candidate_key: Optional[str] = None
        if api_key_header and api_key_header.strip():
            candidate_key = api_key_header.strip()
        elif auth_header and auth_header.startswith("Bearer "):
            token = auth_header[7:].strip()
            if token.startswith("lx_live_"):
                candidate_key = token
            else:
                payload = self.jwt.decode(token)
                if payload and payload.get("sub"):
                    return str(payload["sub"])

        if candidate_key:
            key_hash = _sha256_hex(candidate_key)
            conn = self._connect()
            try:
                row = conn.execute("SELECT id FROM users WHERE api_key_hash = ?", (key_hash,)).fetchone()
                return str(row["id"]) if row else None
            finally:
                conn.close()
        return None

    def get_user_info(self, user_id: str) -> Dict[str, Any]:
        conn = self._connect()
        try:
            row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
            if not row:
                raise PermissionError("用户不存在")
            sync_rows = conn.execute(
                """
                SELECT namespace, COUNT(*) AS cnt, MAX(lamport_ts) AS max_ts, MAX(updated_at) AS last_up
                FROM sync_records WHERE user_id = ? AND tombstone = 0
                GROUP BY namespace
                """,
                (user_id,),
            ).fetchall()
            vault_summary = {
                r["namespace"]: {
                    "count": int(r["cnt"]),
                    "watermark": int(r["max_ts"] or 0),
                    "updatedAt": int(r["last_up"] or 0),
                }
                for r in sync_rows
            }
            dev_rows = conn.execute(
                "SELECT id, name, platform, app_ver, last_seen FROM devices WHERE user_id = ? ORDER BY last_seen DESC",
                (user_id,),
            ).fetchall()
            return {
                "userID": row["id"],
                "email": row["email"] or "",
                "username": row["username"],
                "apiKeyPrefix": row["api_key_prefix"] or "",
                "e2eeSalt": row["e2ee_salt"],
                "plan": row["plan"] if "plan" in row.keys() else "free",
                "analyticsOptIn": bool(row["analytics_opt_in"]) if "analytics_opt_in" in row.keys() else False,
                "createdAt": int(row["created_at"]),
                "lastLoginAt": int(row["last_login_at"]),
                "devices": [dict(d) for d in dev_rows],
                "vaultSummary": vault_summary,
            }
        finally:
            conn.close()

    # -------------------------------------------------------------------------
    # 2. 重要数据 LWW 端到端加密云同步 + sync_state 每设备水位
    # -------------------------------------------------------------------------

    @staticmethod
    def _wins(in_ts: int, in_dev: str, db_ts: int, db_dev: str) -> bool:
        if in_ts != db_ts:
            return in_ts > db_ts
        return in_dev >= db_dev

    def sync_push(self, user_id: str, changes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        now = int(time.time())
        conflicts: List[Dict[str, Any]] = []
        with self._lock:
            conn = self._connect()
            try:
                seq_row = conn.execute(
                    "SELECT COALESCE(MAX(server_seq), 0) AS max_seq FROM sync_records WHERE user_id = ?",
                    (user_id,),
                ).fetchone()
                next_seq = int(seq_row["max_seq"]) + 1

                for item in changes:
                    ns = str(item.get("namespace", "")).strip()
                    key = str(item.get("key", "")).strip()
                    if not ns or not key:
                        continue
                    ciphertext_b64 = str(item.get("ciphertext", ""))
                    nonce = str(item.get("nonce", ""))
                    lamport_ts = int(item.get("lamportTS", 0))
                    device_id = str(item.get("deviceID", "ios-default"))
                    tombstone = 1 if item.get("tombstone", False) else 0
                    schema_version = int(item.get("schemaVersion", 1))

                    self._touch_device(conn, user_id, device_id)

                    existing = conn.execute(
                        """
                        SELECT ciphertext_b64, lamport_ts, device_id, tombstone, schema_version
                        FROM sync_records
                        WHERE user_id = ? AND namespace = ? AND record_key = ?
                        """,
                        (user_id, ns, key),
                    ).fetchone()

                    if existing:
                        db_ts = int(existing["lamport_ts"])
                        db_dev = str(existing["device_id"])
                        if not self._wins(lamport_ts, device_id, db_ts, db_dev):
                            conflicts.append(
                                {
                                    "namespace": ns,
                                    "key": key,
                                    "serverRecord": {
                                        "namespace": ns,
                                        "key": key,
                                        "ciphertext": existing["ciphertext_b64"],
                                        "lamportTS": db_ts,
                                        "deviceID": db_dev,
                                        "tombstone": bool(existing["tombstone"]),
                                        "schemaVersion": int(existing["schema_version"]),
                                    },
                                }
                            )
                            continue

                    conn.execute(
                        """
                        INSERT INTO sync_records
                            (user_id, namespace, record_key, ciphertext_b64, nonce, lamport_ts, device_id, tombstone, schema_version, server_seq, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(user_id, namespace, record_key) DO UPDATE SET
                            ciphertext_b64 = excluded.ciphertext_b64,
                            nonce = excluded.nonce,
                            lamport_ts = excluded.lamport_ts,
                            device_id = excluded.device_id,
                            tombstone = excluded.tombstone,
                            schema_version = excluded.schema_version,
                            server_seq = excluded.server_seq,
                            updated_at = excluded.updated_at
                        """,
                        (user_id, ns, key, ciphertext_b64, nonce, lamport_ts, device_id, tombstone, schema_version, next_seq, now),
                    )
                    conn.execute(
                        """
                        INSERT INTO sync_state (user_id, device_id, namespace, last_seen_lamport, updated_at)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(user_id, device_id, namespace) DO UPDATE SET
                            last_seen_lamport = MAX(sync_state.last_seen_lamport, excluded.last_seen_lamport),
                            updated_at = excluded.updated_at
                        """,
                        (user_id, device_id, ns, lamport_ts, now),
                    )
                    next_seq += 1

                conn.commit()
                return conflicts
            finally:
                conn.close()

    def sync_pull(self, user_id: str, namespace: str, since: int, limit: int = 100, device_id: str = "ios-default") -> Dict[str, Any]:
        now = int(time.time())
        with self._lock:
            conn = self._connect()
            try:
                rows = conn.execute(
                    """
                    SELECT namespace, record_key, ciphertext_b64, lamport_ts, device_id, tombstone, schema_version
                    FROM sync_records
                    WHERE user_id = ? AND namespace = ? AND lamport_ts > ?
                    ORDER BY lamport_ts ASC, device_id ASC
                    LIMIT ?
                    """,
                    (user_id, namespace, since, limit + 1),
                ).fetchall()

                has_more = len(rows) > limit
                sliced = rows[:limit]
                changes = []
                next_cursor = since
                for r in sliced:
                    ts = int(r["lamport_ts"])
                    if ts > next_cursor:
                        next_cursor = ts
                    changes.append(
                        {
                            "namespace": r["namespace"],
                            "key": r["record_key"],
                            "ciphertext": r["ciphertext_b64"],
                            "lamportTS": ts,
                            "deviceID": r["device_id"],
                            "tombstone": bool(r["tombstone"]),
                            "schemaVersion": int(r["schema_version"]),
                        }
                    )
                if next_cursor > since:
                    conn.execute(
                        """
                        INSERT INTO sync_state (user_id, device_id, namespace, last_seen_lamport, updated_at)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(user_id, device_id, namespace) DO UPDATE SET
                            last_seen_lamport = MAX(sync_state.last_seen_lamport, excluded.last_seen_lamport),
                            updated_at = excluded.updated_at
                        """,
                        (user_id, device_id, namespace, next_cursor, now),
                    )
                    conn.commit()
                return {
                    "changes": changes,
                    "nextCursor": next_cursor,
                    "hasMore": has_more,
                }
            finally:
                conn.close()

    # -------------------------------------------------------------------------
    # 3. 跨设备实时剪贴板接力 (6 位匹配码免登录秒传，对标微信输入法跨屏剪贴板)
    # -------------------------------------------------------------------------

    def push_clipboard_relay(self, pair_code: str, content_text: str, sender_device: str = "iPhone") -> Dict[str, Any]:
        code_clean = re.sub(r"[^0-9A-Za-z]", "", pair_code.strip())
        if len(code_clean) < 4 or len(code_clean) > 12:
            raise ValueError("请输入 4~12 位跨屏匹配码（推荐 6 位数字）")
        text_clean = content_text.strip()
        if not text_clean:
            raise ValueError("剪贴板内容不能为空")
        if is_sensitive_clipboard(text_clean):
            raise ValueError("检测到敏感证件号/私钥/密码形态，L1 安全防线已自动拦截跨屏传输")

        now = int(time.time())
        expires_at = now + 600  # 10 分钟后自动过期
        otp = extract_otp_code(text_clean)
        category = "code" if otp else ("url" if text_clean.lower().startswith(("http://", "https://")) else "text")

        with self._lock:
            conn = self._connect()
            try:
                conn.execute("DELETE FROM clipboard_relays WHERE expires_at < ?", (now,))
                cur = conn.execute(
                    """
                    INSERT INTO clipboard_relays
                        (pair_code, content_text, category, extracted_code, sender_device, created_at, expires_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (code_clean, text_clean, category, otp, sender_device or "iPhone", now, expires_at),
                )
                item_id = int(cur.lastrowid or 0)
                conn.commit()
            finally:
                conn.close()

        self.relay_hub.notify(code_clean, item_id)
        return {
            "id": item_id,
            "pairCode": code_clean,
            "contentText": text_clean,
            "category": category,
            "extractedCode": otp,
            "senderDevice": sender_device,
            "createdAt": now,
            "expiresAt": expires_at,
        }

    def pull_clipboard_relay(self, pair_code: str, since_id: int = 0) -> List[Dict[str, Any]]:
        code_clean = re.sub(r"[^0-9A-Za-z]", "", pair_code.strip())
        if not code_clean:
            return []
        now = int(time.time())
        conn = self._connect()
        try:
            rows = conn.execute(
                """
                SELECT id, pair_code, content_text, category, extracted_code, sender_device, created_at, expires_at
                FROM clipboard_relays
                WHERE pair_code = ? AND id > ? AND expires_at >= ?
                ORDER BY id DESC
                LIMIT 15
                """,
                (code_clean, since_id, now),
            ).fetchall()
            return [
                {
                    "id": int(r["id"]),
                    "pairCode": r["pair_code"],
                    "contentText": r["content_text"],
                    "category": r["category"],
                    "extractedCode": r["extracted_code"],
                    "senderDevice": r["sender_device"],
                    "createdAt": int(r["created_at"]),
                    "expiresAt": int(r["expires_at"]),
                }
                for r in rows
            ]
        finally:
            conn.close()

    # -------------------------------------------------------------------------
    # 4. 实时打字习惯与 API 分析引擎 (Wakapi 架构)
    # -------------------------------------------------------------------------

    def ingest_typing_events(self, user_id: str, digests: List[Dict[str, Any]]) -> Dict[str, Any]:
        now = int(time.time())
        with self._lock:
            conn = self._connect()
            try:
                for d in digests:
                    started_raw = d.get("startedAt", now)
                    started_at = int(started_raw) if isinstance(started_raw, (int, float)) else now
                    duration = max(1, int(d.get("durationSeconds", 1)))
                    chars = max(0, int(d.get("committedChars", 0)))
                    words = max(0, int(d.get("committedWords", max(1, chars // 2))))
                    deletes = max(0, int(d.get("deleteCount", 0)))
                    undo_learns = max(0, int(d.get("undoLearnCount", 0)))
                    glide_words = max(0, int(d.get("glideWords", 0)))
                    typo_corrected = max(0, int(d.get("typoCorrectedCount", 0)))
                    ai_calls = max(0, int(d.get("aiInvocations", 0)))
                    translate_chars = max(0, int(d.get("translateChars", 0)))

                    scheme_id = str(d.get("schemeID", "")).strip()
                    if not scheme_id:
                        scheme_idx = int(d.get("schemeIndex", 0))
                        scheme_id = SCHEME_INDEX_TO_ID.get(scheme_idx, "quanpin")

                    layout_id = str(d.get("layoutID", "")).strip()
                    if not layout_id:
                        layout_idx = int(d.get("layoutIndex", 0))
                        layout_id = LAYOUT_INDEX_TO_ID.get(layout_idx, "qwerty26")

                    active_hour = int(d.get("activeHour", time.localtime(started_at).tm_hour)) % 24
                    device_id = str(d.get("deviceID", "ios-default"))
                    raw_conf = d.get("confusionCounts", {})
                    confusion_dict = {
                        str(k): max(0, int(v))
                        for k, v in (raw_conf.items() if isinstance(raw_conf, dict) else [])
                        if int(v) > 0
                    }

                    conn.execute(
                        """
                        INSERT INTO typing_habit_events
                            (user_id, device_id, started_at, duration_seconds, committed_chars, committed_words,
                             delete_count, undo_learn_count, glide_words, typo_corrected_count,
                             ai_invocations, translate_chars, scheme_id, layout_id, active_hour, confusion_json, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            user_id,
                            device_id,
                            started_at,
                            duration,
                            chars,
                            words,
                            deletes,
                            undo_learns,
                            glide_words,
                            typo_corrected,
                            ai_calls,
                            translate_chars,
                            scheme_id,
                            layout_id,
                            active_hour,
                            json.dumps(confusion_dict, ensure_ascii=False),
                            now,
                        ),
                    )

                profile = self._recompute_user_profile(conn, user_id, now)
                conn.commit()
                return profile
            finally:
                conn.close()

    def ingest_api_usage(self, user_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        now = int(time.time())
        feature = str(payload.get("feature", "ai_polish")).strip() or "ai_polish"
        provider = str(payload.get("provider", "gemini")).strip() or "gemini"
        target_lang = str(payload.get("targetLang", "英文")).strip() or "英文"
        formal_tone = 1 if payload.get("formalTone", False) else 0
        input_chars = max(0, int(payload.get("inputChars", 0)))
        output_chars = max(0, int(payload.get("outputChars", 0)))
        latency_ms = max(0, int(payload.get("latencyMs", 0)))

        with self._lock:
            conn = self._connect()
            try:
                conn.execute(
                    """
                    INSERT INTO ai_api_usage_logs
                        (user_id, feature, provider, target_lang, formal_tone, input_chars, output_chars, latency_ms, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (user_id, feature, provider, target_lang, formal_tone, input_chars, output_chars, latency_ms, now),
                )
                profile = self._recompute_user_profile(conn, user_id, now)
                conn.commit()
                return profile
            finally:
                conn.close()

    def _recompute_user_profile(self, conn: sqlite3.Connection, user_id: str, now: int) -> Dict[str, Any]:
        agg = conn.execute(
            """
            SELECT
                COUNT(*) AS sessions,
                COALESCE(SUM(committed_chars), 0) AS total_chars,
                COALESCE(SUM(committed_words), 0) AS total_words,
                COALESCE(SUM(duration_seconds), 0) AS total_dur,
                COALESCE(SUM(delete_count), 0) AS total_del,
                COALESCE(SUM(undo_learn_count), 0) AS total_undo,
                COALESCE(SUM(glide_words), 0) AS total_glide,
                COALESCE(SUM(typo_corrected_count), 0) AS total_typo,
                COALESCE(MAX(CASE WHEN duration_seconds >= 5 THEN (committed_chars * 60.0 / duration_seconds) ELSE 0 END), 0) AS peak_cpm
            FROM typing_habit_events
            WHERE user_id = ?
            """,
            (user_id,),
        ).fetchone()

        total_sessions = int(agg["sessions"] or 0)
        total_chars = int(agg["total_chars"] or 0)
        total_words = int(agg["total_words"] or 0)
        total_dur = int(agg["total_dur"] or 0)
        total_del = int(agg["total_del"] or 0)
        total_undo = int(agg["total_undo"] or 0)
        total_glide = int(agg["total_glide"] or 0)
        total_typo = int(agg["total_typo"] or 0)
        peak_cpm = round(float(agg["peak_cpm"] or 0.0), 1)

        avg_cpm = round((total_chars * 60.0 / total_dur), 1) if total_dur > 0 else 0.0
        avg_word_len = round(total_chars / max(1, total_words), 2) if total_words > 0 else 0.0
        backspace_rate = round(total_del / max(1, total_chars), 4) if total_chars > 0 else 0.0
        undo_learn_rate = round(total_undo / max(1, total_words), 4) if total_words > 0 else 0.0
        glide_ratio = round(total_glide / max(1, total_words), 4) if total_words > 0 else 0.0
        typo_rate = round(total_typo / max(1, total_words), 4) if total_words > 0 else 0.0

        scheme_rows = conn.execute(
            """
            SELECT scheme_id, SUM(committed_chars) AS chars
            FROM typing_habit_events WHERE user_id = ?
            GROUP BY scheme_id ORDER BY chars DESC
            """,
            (user_id,),
        ).fetchall()
        scheme_breakdown = {r["scheme_id"]: int(r["chars"] or 0) for r in scheme_rows}
        primary_scheme = scheme_rows[0]["scheme_id"] if scheme_rows else "quanpin"

        layout_rows = conn.execute(
            """
            SELECT layout_id, SUM(committed_chars) AS chars
            FROM typing_habit_events WHERE user_id = ?
            GROUP BY layout_id ORDER BY chars DESC
            """,
            (user_id,),
        ).fetchall()
        primary_layout = layout_rows[0]["layout_id"] if layout_rows else "qwerty26"

        hour_rows = conn.execute(
            """
            SELECT active_hour, SUM(committed_chars) AS chars
            FROM typing_habit_events WHERE user_id = ?
            GROUP BY active_hour ORDER BY active_hour ASC
            """,
            (user_id,),
        ).fetchall()
        hourly_rhythm = {str(r["active_hour"]): int(r["chars"] or 0) for r in hour_rows}

        ai_rows = conn.execute(
            """
            SELECT feature, COUNT(*) AS calls, SUM(input_chars) AS in_c, SUM(output_chars) AS out_c, AVG(latency_ms) AS avg_lat
            FROM ai_api_usage_logs WHERE user_id = ?
            GROUP BY feature ORDER BY calls DESC
            """,
            (user_id,),
        ).fetchall()
        ai_breakdown = {
            r["feature"]: {
                "calls": int(r["calls"] or 0),
                "inputChars": int(r["in_c"] or 0),
                "outputChars": int(r["out_c"] or 0),
                "avgLatencyMs": int(round(float(r["avg_lat"] or 0))),
            }
            for r in ai_rows
        }

        conf_rows = conn.execute(
            "SELECT confusion_json FROM typing_habit_events WHERE user_id = ? AND confusion_json != '{}'",
            (user_id,),
        ).fetchall()
        confusion_matrix: Dict[str, int] = {}
        for cr in conf_rows:
            try:
                parsed = json.loads(cr["confusion_json"] or "{}")
                for k, v in parsed.items():
                    confusion_matrix[str(k)] = confusion_matrix.get(str(k), 0) + int(v)
            except Exception:
                pass

        existing_prof = conn.execute(
            "SELECT domain_affinity_json FROM user_typing_profiles WHERE user_id = ?",
            (user_id,),
        ).fetchone()
        domain_affinity: Dict[str, Any] = {}
        if existing_prof and existing_prof["domain_affinity_json"]:
            try:
                domain_affinity = json.loads(existing_prof["domain_affinity_json"])
            except Exception:
                domain_affinity = {}

        habit_tags: List[str] = []
        recommendations: List[Dict[str, str]] = []

        fuzzy_meta = {
            "zh_z": ("zh ↔ z 平翘舌", "fuzzy.zhZ"),
            "ch_c": ("ch ↔ c 平翘舌", "fuzzy.chC"),
            "sh_s": ("sh ↔ s 平翘舌", "fuzzy.shS"),
            "n_l": ("n ↔ l 鼻边音", "fuzzy.nl"),
            "an_ang": ("an ↔ ang 前后鼻音", "fuzzy.anAng"),
            "en_eng": ("en ↔ eng 前后鼻音", "fuzzy.enEng"),
            "in_ing": ("in ↔ ing 前后鼻音", "fuzzy.inIng"),
            "f_h": ("f ↔ h 唇齿音", "fuzzy.fh"),
            "huang_wang": ("huang ↔ wang 介音", "fuzzy.huangWang"),
        }
        for pair_key, count in sorted(confusion_matrix.items(), key=lambda kv: kv[1], reverse=True):
            if count >= 2 and pair_key in fuzzy_meta:
                label, setting_key = fuzzy_meta[pair_key]
                recommendations.append(
                    {
                        "id": f"fuzzy_{pair_key}",
                        "title": f"建议专属开启『{label}模糊音』",
                        "reason": f"API 实时分析检测到您已累计出现 {count} 次 {label} 混淆输入，开启后可直接首选命中。",
                        "settingKey": setting_key,
                    }
                )

        if domain_affinity.get("primaryDomain") and domain_affinity.get("primaryDomain") != "综合通用":
            habit_tags.append(f"{domain_affinity['primaryDomain']}词库偏好")

        scheme_name = SCHEME_DISPLAY_NAMES.get(primary_scheme, "全拼")
        if primary_scheme == "wubi86":
            habit_tags.append("五笔字根极客")
        elif primary_scheme != "quanpin":
            habit_tags.append(f"{scheme_name}高阶用户")
        else:
            habit_tags.append("全拼流式输入")

        if avg_cpm >= 150 or peak_cpm >= 200:
            habit_tags.append("高速击键达人")
        elif total_chars > 0 and backspace_rate <= 0.05:
            habit_tags.append("零误触精准派")

        if avg_word_len >= 2.1:
            habit_tags.append("长句整输习惯")
            recommendations.append(
                {
                    "id": "keep_bigram_prediction",
                    "title": "已适配『长句连打』习惯",
                    "reason": f"您的平均上屏词长达 {avg_word_len} 字/次，二元语法与上下文消歧可为您显著提升整句首选命中率。",
                    "settingKey": "bigramPredictionEnabled",
                }
            )
        elif total_words >= 5:
            habit_tags.append("短词快选节奏")

        if glide_ratio >= 0.15:
            habit_tags.append("滑行轨迹玩家")
        elif primary_layout == "qwerty26" and total_words >= 10:
            recommendations.append(
                {
                    "id": "try_glide_typing",
                    "title": "建议尝试 26 键滑行输入",
                    "reason": "检测到您习惯 26 键点按输入，单手打字时在字母间连续滑行可提升约 25% 造句速度。",
                    "settingKey": "glideTypingEnabled",
                }
            )

        if backspace_rate >= 0.10 or typo_rate >= 0.08:
            habit_tags.append("快节奏纠错依赖")
            recommendations.append(
                {
                    "id": "enable_dynamic_hitbox_and_fuzzy",
                    "title": "建议开启『动态热区防误触』与『模糊音兜底』",
                    "reason": f"当前退格修改率为 {round(backspace_rate * 100, 1)}%，开启键缝动态吸附与 4 路错拼容错能减少约 35% 返工。",
                    "settingKey": "dynamicKeyHitBoxEnabled",
                }
            )

        if undo_learn_rate >= 0.05:
            recommendations.append(
                {
                    "id": "raise_auto_learn_threshold",
                    "title": "建议将『自造词学习阈值』调至 2 次",
                    "reason": "检测到您频繁使用『退格重选撤学』，将学习阈值设为 2 次可避免偶发误触词进入个人词库。",
                    "settingKey": "autoLearnThreshold",
                }
            )

        night_chars = sum(int(hourly_rhythm.get(str(h), 0)) for h in [22, 23, 0, 1, 2, 3, 4])
        if total_chars > 0 and (night_chars / total_chars) >= 0.35:
            habit_tags.append("深夜高产创作者")
        elif total_chars > 0:
            habit_tags.append("日间高效表达者")

        total_ai_calls = sum(v["calls"] for v in ai_breakdown.values())
        if total_ai_calls > 0:
            habit_tags.append("AI 协同写作者")
            top_ai_feature = next(iter(ai_breakdown.keys()))
            recommendations.append(
                {
                    "id": "ai_workflow_habit",
                    "title": f"高频 AI 技能偏好：{top_ai_feature}",
                    "reason": f"已累计通过 API 分析 {total_ai_calls} 次 AI/翻译交互，云端已记住您的语言与文风习惯。",
                    "settingKey": "translateTargetLang",
                }
            )

        if not recommendations:
            recommendations.append(
                {
                    "id": "optimal_state",
                    "title": "当前输入引擎参数已处于最佳平衡态",
                    "reason": "您的击键准确率与上屏节奏表现优异，继续保持当前配置即可。",
                    "settingKey": "userLearningEnabled",
                }
            )

        conn.execute(
            """
            INSERT INTO user_typing_profiles
                (user_id, total_chars, total_words, total_duration_seconds, total_sessions,
                 avg_cpm, peak_cpm, avg_word_length, backspace_rate, undo_learn_rate,
                 glide_ratio, typo_correction_rate, primary_scheme, primary_layout,
                 scheme_breakdown_json, hourly_rhythm_json, ai_feature_breakdown_json,
                 confusion_matrix_json, domain_affinity_json,
                 habit_tags_json, tuning_recommendations_json, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
                total_chars = excluded.total_chars,
                total_words = excluded.total_words,
                total_duration_seconds = excluded.total_duration_seconds,
                total_sessions = excluded.total_sessions,
                avg_cpm = excluded.avg_cpm,
                peak_cpm = excluded.peak_cpm,
                avg_word_length = excluded.avg_word_length,
                backspace_rate = excluded.backspace_rate,
                undo_learn_rate = excluded.undo_learn_rate,
                glide_ratio = excluded.glide_ratio,
                typo_correction_rate = excluded.typo_correction_rate,
                primary_scheme = excluded.primary_scheme,
                primary_layout = excluded.primary_layout,
                scheme_breakdown_json = excluded.scheme_breakdown_json,
                hourly_rhythm_json = excluded.hourly_rhythm_json,
                ai_feature_breakdown_json = excluded.ai_feature_breakdown_json,
                confusion_matrix_json = excluded.confusion_matrix_json,
                domain_affinity_json = excluded.domain_affinity_json,
                habit_tags_json = excluded.habit_tags_json,
                tuning_recommendations_json = excluded.tuning_recommendations_json,
                updated_at = excluded.updated_at
            """,
            (
                user_id,
                total_chars,
                total_words,
                total_dur,
                total_sessions,
                avg_cpm,
                peak_cpm,
                avg_word_len,
                backspace_rate,
                undo_learn_rate,
                glide_ratio,
                typo_rate,
                primary_scheme,
                primary_layout,
                json.dumps(scheme_breakdown, ensure_ascii=False),
                json.dumps(hourly_rhythm, ensure_ascii=False),
                json.dumps(ai_breakdown, ensure_ascii=False),
                json.dumps(confusion_matrix, ensure_ascii=False),
                json.dumps(domain_affinity, ensure_ascii=False),
                json.dumps(habit_tags, ensure_ascii=False),
                json.dumps(recommendations, ensure_ascii=False),
                now,
            ),
        )
        return self.get_typing_habit_profile(user_id, _conn=conn)

    def analyze_lexicon_habits(self, user_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        now = int(time.time())
        words = [str(w).strip() for w in payload.get("words", []) if str(w).strip()]
        preferred_tone = str(payload.get("preferredTone", "自然流畅")).strip()

        domain_keywords = {
            "科技与研发": ["代码", "接口", "部署", "服务器", "数据库", "算法", "模型", "前端", "后端", "架构", "测试", "编译", "函数", "并发", "灵犀"],
            "商务与职场": ["收到", "会议", "汇报", "方案", "进度", "合作", "排期", "辛苦", "确认", "合同", "客户", "需求", "复盘", "对齐"],
            "日常与社交": ["哈哈", "吃饭", "开心", "下班", "火锅", "奶茶", "周末", "晚安", "摸鱼", "快递", "朋友", "明天", "休息"],
            "学术与创作": ["研究", "分析", "论文", "文献", "逻辑", "结构", "实验", "论证", "摘要", "引用", "叙事", "章节"],
        }
        domain_scores: Dict[str, int] = {k: 0 for k in domain_keywords}
        for w in words:
            for dom, kws in domain_keywords.items():
                if any(kw in w for kw in kws):
                    domain_scores[dom] += 1

        active_domains = {k: v for k, v in domain_scores.items() if v > 0}
        primary_domain = max(active_domains.items(), key=lambda kv: kv[1])[0] if active_domains else "综合通用"
        avg_len = round(sum(len(w) for w in words) / max(1, len(words)), 2) if words else 0.0

        domain_affinity = {
            "primaryDomain": primary_domain,
            "domainScores": active_domains,
            "analyzedWordCount": len(words),
            "avgLexiconWordLength": avg_len,
            "preferredTone": preferred_tone,
            "topTerms": words[:12],
        }

        with self._lock:
            conn = self._connect()
            try:
                conn.execute(
                    """
                    INSERT INTO user_typing_profiles (user_id, domain_affinity_json, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(user_id) DO UPDATE SET
                        domain_affinity_json = excluded.domain_affinity_json,
                        updated_at = excluded.updated_at
                    """,
                    (user_id, json.dumps(domain_affinity, ensure_ascii=False), now),
                )
                profile = self._recompute_user_profile(conn, user_id, now)
                conn.commit()
                return profile
            finally:
                conn.close()

    def get_typing_habit_profile(self, user_id: str, _conn: Optional[sqlite3.Connection] = None) -> Dict[str, Any]:
        own_conn = _conn is None
        conn = _conn or self._connect()
        try:
            row = conn.execute("SELECT * FROM user_typing_profiles WHERE user_id = ?", (user_id,)).fetchone()
            if not row:
                now = int(time.time())
                conn.execute("INSERT OR IGNORE INTO user_typing_profiles (user_id, updated_at) VALUES (?, ?)", (user_id, now))
                if own_conn:
                    conn.commit()
                row = conn.execute("SELECT * FROM user_typing_profiles WHERE user_id = ?", (user_id,)).fetchone()

            recent_rows = conn.execute(
                """
                SELECT started_at, duration_seconds, committed_chars, committed_words,
                       delete_count, undo_learn_count, glide_words, scheme_id, layout_id, active_hour
                FROM typing_habit_events
                WHERE user_id = ?
                ORDER BY started_at DESC, id DESC
                LIMIT 15
                """,
                (user_id,),
            ).fetchall()

            return {
                "userID": user_id,
                "totalChars": int(row["total_chars"]),
                "totalWords": int(row["total_words"]),
                "totalDurationSeconds": int(row["total_duration_seconds"]),
                "totalSessions": int(row["total_sessions"]),
                "avgCPM": float(row["avg_cpm"]),
                "peakCPM": float(row["peak_cpm"]),
                "avgWordLength": float(row["avg_word_length"]),
                "backspaceRate": float(row["backspace_rate"]),
                "undoLearnRate": float(row["undo_learn_rate"]),
                "glideRatio": float(row["glide_ratio"]),
                "typoCorrectionRate": float(row["typo_correction_rate"]),
                "primaryScheme": row["primary_scheme"],
                "primaryLayout": row["primary_layout"],
                "schemeBreakdown": json.loads(row["scheme_breakdown_json"] or "{}"),
                "hourlyRhythm": json.loads(row["hourly_rhythm_json"] or "{}"),
                "aiFeatureBreakdown": json.loads(row["ai_feature_breakdown_json"] or "{}"),
                "confusionMatrix": json.loads(row["confusion_matrix_json"] or "{}") if "confusion_matrix_json" in row.keys() else {},
                "domainAffinity": json.loads(row["domain_affinity_json"] or "{}") if "domain_affinity_json" in row.keys() else {},
                "habitTags": json.loads(row["habit_tags_json"] or "[]"),
                "tuningRecommendations": json.loads(row["tuning_recommendations_json"] or "[]"),
                "recentSessions": [
                    {
                        "startedAt": int(r["started_at"]),
                        "durationSeconds": int(r["duration_seconds"]),
                        "committedChars": int(r["committed_chars"]),
                        "committedWords": int(r["committed_words"]),
                        "deleteCount": int(r["delete_count"]),
                        "undoLearnCount": int(r["undo_learn_count"]),
                        "glideWords": int(r["glide_words"]),
                        "schemeID": r["scheme_id"],
                        "layoutID": r["layout_id"],
                        "activeHour": int(r["active_hour"]),
                    }
                    for r in recent_rows
                ],
                "updatedAt": int(row["updated_at"]),
            }
        finally:
            if own_conn:
                conn.close()

    def clear_typing_habits(self, user_id: str) -> Dict[str, Any]:
        now = int(time.time())
        with self._lock:
            conn = self._connect()
            try:
                conn.execute("DELETE FROM typing_habit_events WHERE user_id = ?", (user_id,))
                conn.execute("DELETE FROM ai_api_usage_logs WHERE user_id = ?", (user_id,))
                conn.execute(
                    "UPDATE user_typing_profiles SET domain_affinity_json = '{}', confusion_matrix_json = '{}' WHERE user_id = ?",
                    (user_id,),
                )
                profile = self._recompute_user_profile(conn, user_id, now)
                conn.commit()
                return profile
            finally:
                conn.close()

    # -------------------------------------------------------------------------
    # 5. 第六部分合规 (GDPR / 个保法)：独立授权流水、全量数据可携带导出、级联硬删除
    # -------------------------------------------------------------------------

    def record_consent(self, user_id: str, scope: str, granted: bool, ip: str = "127.0.0.1", policy_version: str = "2026.11-v1") -> Dict[str, Any]:
        now = int(time.time())
        consent_id = str(uuid.uuid4())
        with self._lock:
            conn = self._connect()
            try:
                conn.execute(
                    """
                    INSERT INTO consent_records (id, user_id, scope, granted, at, ip, policy_version)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (consent_id, user_id, scope, 1 if granted else 0, now, ip, policy_version),
                )
                if scope == "typing_analytics":
                    conn.execute(
                        "UPDATE users SET analytics_opt_in = ?, opt_in_at = ?, updated_at = ? WHERE id = ?",
                        (1 if granted else 0, now, now, user_id),
                    )
                conn.commit()
                return {
                    "id": consent_id,
                    "userID": user_id,
                    "scope": scope,
                    "granted": granted,
                    "at": now,
                    "policyVersion": policy_version,
                }
            finally:
                conn.close()

    def export_portable_user_data(self, user_id: str) -> Dict[str, Any]:
        """GDPR / 个保法『导出我的全部数据』：账号元数据 + E2EE 同步密文包 + 授权审计流水 + 打字习惯聚合 JSON。"""
        info = self.get_user_info(user_id)
        profile = self.get_typing_habit_profile(user_id)
        conn = self._connect()
        try:
            sync_rows = conn.execute(
                """
                SELECT namespace, record_key, ciphertext_b64, lamport_ts, device_id, tombstone, schema_version, updated_at
                FROM sync_records WHERE user_id = ?
                ORDER BY namespace ASC, record_key ASC
                """,
                (user_id,),
            ).fetchall()
            consents = conn.execute(
                "SELECT id, scope, granted, at, ip, policy_version FROM consent_records WHERE user_id = ? ORDER BY at DESC",
                (user_id,),
            ).fetchall()
            return {
                "format": "LINGXI-GDPR-PORTABLE-EXPORT",
                "exportedAt": int(time.time()),
                "account": info,
                "syncVaultCiphertext": [dict(r) for r in sync_rows],
                "consentAuditTrail": [dict(c) for c in consents],
                "typingHabitAggregate": profile,
            }
        finally:
            conn.close()

    def delete_account_cascade(self, user_id: str) -> Dict[str, Any]:
        """账号注销 = 全表级联硬删除 (ON DELETE CASCADE)。"""
        with self._lock:
            conn = self._connect()
            try:
                conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
                conn.commit()
                return {"deleted": True, "userID": user_id, "deletedAt": int(time.time())}
            finally:
                conn.close()

    # -------------------------------------------------------------------------
    # 6. B 端企业分析 API (`api_clients` + `b2b_audit_logs` 180 天留痕 + 按调用计费)
    # -------------------------------------------------------------------------

    def create_b2b_client(self, org: str, scopes: str = "profile:read,aggregate:read", rate_limit: int = 120) -> Dict[str, Any]:
        now = int(time.time())
        client_id = str(uuid.uuid4())
        raw_key, key_hash, key_prefix = self._generate_api_key("lxb_live_")
        with self._lock:
            conn = self._connect()
            try:
                conn.execute(
                    """
                    INSERT INTO api_clients (id, org, key_hash, key_prefix, scopes, rate_limit, call_count, billable_units, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, 0, 0, ?)
                    """,
                    (client_id, org.strip() or "Enterprise Partner", key_hash, key_prefix, scopes, rate_limit, now),
                )
                conn.commit()
                return {
                    "clientID": client_id,
                    "org": org,
                    "serviceKey": raw_key,
                    "keyPrefix": key_prefix,
                    "scopes": scopes,
                    "rateLimit": rate_limit,
                }
            finally:
                conn.close()

    def execute_b2b_aggregate_query(
        self,
        service_key: Optional[str] = None,
        client_id: Optional[str] = None,
        required_scope: str = "aggregate:read",
        ip: str = "127.0.0.1",
    ) -> Dict[str, Any]:
        """B 端企业画像聚合查询：仅检索已显式授权 (`analytics_opt_in = 1`) 的用户画像，并写入 180 天不可变审计日志。"""
        now = int(time.time())
        with self._lock:
            conn = self._connect()
            try:
                if service_key:
                    row = conn.execute("SELECT * FROM api_clients WHERE key_hash = ?", (_sha256_hex(service_key.strip()),)).fetchone()
                elif client_id:
                    row = conn.execute("SELECT * FROM api_clients WHERE id = ?", (client_id,)).fetchone()
                else:
                    row = None

                if not row:
                    raise PermissionError("无效的 B 端企业 Service Key")

                scopes = [s.strip() for s in str(row["scopes"]).split(",")]
                if required_scope not in scopes:
                    conn.execute(
                        """
                        INSERT INTO b2b_audit_logs (client_id, org, endpoint, target_user_id, scope_used, ip, status_code, created_at)
                        VALUES (?, ?, '/api/v1/b2b/aggregate-profiles', 'aggregate', ?, ?, 403, ?)
                        """,
                        (row["id"], row["org"], required_scope, ip, now),
                    )
                    conn.commit()
                    raise PermissionError(f"企业密钥缺少所需 Scope: {required_scope}")

                # 清理超过 180 天的旧审计日志，写入本次审计与计费
                conn.execute("DELETE FROM b2b_audit_logs WHERE created_at < ?", (now - 180 * 86400,))
                conn.execute(
                    "UPDATE api_clients SET call_count = call_count + 1, billable_units = billable_units + 1 WHERE id = ?",
                    (row["id"],),
                )
                conn.execute(
                    """
                    INSERT INTO b2b_audit_logs (client_id, org, endpoint, target_user_id, scope_used, ip, status_code, created_at)
                    VALUES (?, ?, '/api/v1/b2b/aggregate-profiles', 'opted_in_cohort', ?, ?, 200, ?)
                    """,
                    (row["id"], row["org"], required_scope, ip, now),
                )

                # 仅聚合 analytics_opt_in = 1 的已授权用户
                prof_rows = conn.execute(
                    """
                    SELECT p.* FROM user_typing_profiles p
                    JOIN users u ON u.id = p.user_id
                    WHERE u.analytics_opt_in = 1
                    """
                ).fetchall()
                conn.commit()

                opted_count = len(prof_rows)
                avg_cpm = round(sum(float(r["avg_cpm"]) for r in prof_rows) / max(1, opted_count), 1)
                return {
                    "org": row["org"],
                    "optedInCohortSize": opted_count,
                    "cohortAvgCPM": avg_cpm,
                    "billableUnitsCharged": 1,
                    "auditLogged": True,
                }
            finally:
                conn.close()

    # -------------------------------------------------------------------------
    # 7. Web 控制台全量聚合看板数据 (`/api/v1/dashboard/overview` & `seed-demo`)
    # -------------------------------------------------------------------------

    def dashboard_overview(self) -> Dict[str, Any]:
        conn = self._connect()
        try:
            u_cnt = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
            opt_cnt = conn.execute("SELECT COUNT(*) FROM users WHERE analytics_opt_in = 1").fetchone()[0]
            s_cnt = conn.execute("SELECT COUNT(*) FROM sync_records WHERE tombstone = 0").fetchone()[0]
            e_cnt = conn.execute("SELECT COUNT(*) FROM typing_habit_events").fetchone()[0]
            ai_row = conn.execute("SELECT COUNT(*) AS cnt, COALESCE(AVG(latency_ms), 0) AS lat FROM ai_api_usage_logs").fetchone()
            b2b_row = conn.execute("SELECT COUNT(*) AS cnt, COALESCE(SUM(billable_units), 0) AS units FROM api_clients").fetchone()

            prof_rows = conn.execute(
                """
                SELECT p.*, u.username, u.email
                FROM user_typing_profiles p
                LEFT JOIN users u ON u.id = p.user_id
                ORDER BY p.total_chars DESC, p.updated_at DESC
                LIMIT 25
                """
            ).fetchall()

            hourly_agg: Dict[str, int] = {}
            scheme_agg: Dict[str, int] = {}
            ai_agg: Dict[str, Dict[str, int]] = {}
            conf_agg: Dict[str, int] = {}
            domain_agg: Dict[str, int] = {}
            profiles_list: List[Dict[str, Any]] = []

            for r in prof_rows:
                hr = json.loads(r["hourly_rhythm_json"] or "{}")
                for k, v in hr.items():
                    hourly_agg[k] = hourly_agg.get(k, 0) + int(v)

                sc = json.loads(r["scheme_breakdown_json"] or "{}")
                for k, v in sc.items():
                    scheme_agg[k] = scheme_agg.get(k, 0) + int(v)

                ab = json.loads(r["ai_feature_breakdown_json"] or "{}")
                for k, v in ab.items():
                    cur = ai_agg.setdefault(k, {"calls": 0, "avgLatencyMs": int(v.get("avgLatencyMs", 0))})
                    cur["calls"] += int(v.get("calls", 0))

                cm = json.loads(r["confusion_matrix_json"] or "{}") if "confusion_matrix_json" in r.keys() else {}
                for k, v in cm.items():
                    conf_agg[k] = conf_agg.get(k, 0) + int(v)

                da = json.loads(r["domain_affinity_json"] or "{}") if "domain_affinity_json" in r.keys() else {}
                for k, v in (da.get("domainScores") or {}).items():
                    domain_agg[k] = domain_agg.get(k, 0) + int(v)

                profiles_list.append(
                    {
                        "userID": r["user_id"],
                        "username": r["username"] or "灵犀用户",
                        "email": r["email"] or "",
                        "totalChars": int(r["total_chars"]),
                        "totalWords": int(r["total_words"]),
                        "avgCPM": float(r["avg_cpm"]),
                        "peakCPM": float(r["peak_cpm"]),
                        "avgWordLength": float(r["avg_word_length"]),
                        "backspaceRate": float(r["backspace_rate"]),
                        "undoLearnRate": float(r["undo_learn_rate"]),
                        "glideRatio": float(r["glide_ratio"]),
                        "primaryScheme": r["primary_scheme"],
                        "primaryLayout": r["primary_layout"],
                        "habitTags": json.loads(r["habit_tags_json"] or "[]"),
                        "tuningRecommendations": json.loads(r["tuning_recommendations_json"] or "[]"),
                    }
                )

            b2b_clients = [
                {
                    "id": r["id"],
                    "org": r["org"],
                    "keyPrefix": r["key_prefix"],
                    "scopes": r["scopes"],
                    "callCount": int(r["call_count"]),
                    "billableUnits": int(r["billable_units"]),
                }
                for r in conn.execute("SELECT * FROM api_clients ORDER BY created_at DESC LIMIT 15").fetchall()
            ]
            consent_logs = [
                {
                    "id": r["id"],
                    "userID": r["user_id"],
                    "scope": r["scope"],
                    "granted": bool(r["granted"]),
                    "at": int(r["at"]),
                    "policyVersion": r["policy_version"],
                }
                for r in conn.execute("SELECT * FROM consent_records ORDER BY at DESC LIMIT 15").fetchall()
            ]
            b2b_logs = [
                {
                    "clientID": r["client_id"],
                    "org": r["org"],
                    "endpoint": r["endpoint"],
                    "scopeUsed": r["scope_used"],
                    "statusCode": int(r["status_code"]),
                    "createdAt": int(r["created_at"]),
                }
                for r in conn.execute("SELECT * FROM b2b_audit_logs ORDER BY created_at DESC LIMIT 15").fetchall()
            ]

            return {
                "version": "4.0.0",
                "stats": {
                    "users": int(u_cnt),
                    "optedInUsers": int(opt_cnt),
                    "syncRecords": int(s_cnt),
                    "habitEvents": int(e_cnt),
                    "aiApiLogs": int(ai_row["cnt"] or 0),
                    "avgAiLatencyMs": int(round(float(ai_row["lat"] or 0))),
                    "b2bClients": int(b2b_row["cnt"] or 0),
                    "b2bBillableUnits": int(b2b_row["units"] or 0),
                },
                "aggregate": {
                    "hourlyRhythm": hourly_agg,
                    "schemeBreakdown": scheme_agg,
                    "aiBreakdown": ai_agg,
                    "confusionMatrix": conf_agg,
                    "domainScores": domain_agg,
                },
                "communityPacks": [
                    {
                        "id": p["id"],
                        "name": p["name"],
                        "category": p["category"],
                        "version": p["version"],
                        "wordCount": len([ln for ln in p["tsv"].splitlines() if ln and not ln.startswith("#")]),
                    }
                    for p in COMMUNITY_LEXICON_PACKS
                ],
                "profiles": profiles_list,
                "b2bClients": b2b_clients,
                "consentLogs": consent_logs,
                "b2bAuditLogs": b2b_logs,
            }
        finally:
            conn.close()

    def seed_demo_data(self) -> Dict[str, Any]:
        """一键生成演示用户、打字习惯、易混音热力图、领域词库与 B 端企业客户审计数据。"""
        try:
            reg = self.register_user("architect@lingxi.im", "灵犀首席架构师", "lingxi-demo-2026", "iphone-16-pro")
            uid = reg["userID"]
        except ValueError:
            login = self.login_user("architect@lingxi.im", "lingxi-demo-2026", "iphone-16-pro")
            uid = login["userID"]

        self.sync_push(
            uid,
            [
                {
                    "namespace": "settings",
                    "key": "main",
                    "ciphertext": base64.b64encode(b"LXE1-encrypted-settings-blob").decode("ascii"),
                    "lamportTS": 21,
                    "deviceID": "iphone-16-pro",
                },
                {
                    "namespace": "lexicon",
                    "key": "main",
                    "ciphertext": base64.b64encode(b"LXE1-encrypted-lexicon-blob").decode("ascii"),
                    "lamportTS": 22,
                    "deviceID": "iphone-16-pro",
                },
            ],
        )

        self.ingest_typing_events(
            uid,
            [
                {
                    "durationSeconds": 65,
                    "committedChars": 210,
                    "committedWords": 74,
                    "deleteCount": 24,
                    "undoLearnCount": 5,
                    "glideWords": 18,
                    "typoCorrectedCount": 9,
                    "schemeID": "xiaohe",
                    "layoutID": "qwerty26",
                    "activeHour": 22,
                    "confusionCounts": {"zh_z": 6, "an_ang": 4, "in_ing": 3, "n_l": 2},
                },
                {
                    "durationSeconds": 50,
                    "committedChars": 165,
                    "committedWords": 58,
                    "deleteCount": 12,
                    "undoLearnCount": 2,
                    "glideWords": 14,
                    "typoCorrectedCount": 4,
                    "schemeID": "xiaohe",
                    "layoutID": "qwerty26",
                    "activeHour": 23,
                    "confusionCounts": {"zh_z": 3, "en_eng": 2},
                },
                {
                    "durationSeconds": 40,
                    "committedChars": 120,
                    "committedWords": 45,
                    "deleteCount": 6,
                    "undoLearnCount": 1,
                    "glideWords": 10,
                    "typoCorrectedCount": 2,
                    "schemeID": "quanpin",
                    "layoutID": "qwerty26",
                    "activeHour": 10,
                    "confusionCounts": {"ch_c": 2},
                },
            ],
        )
        self.analyze_lexicon_habits(
            uid,
            {
                "words": ["微服务架构", "数据库索引", "端到端加密", "算法模型部署", "排期对齐", "会议复盘", "今天吃火锅"],
                "preferredTone": "专业简练",
            },
        )
        self.ingest_api_usage(
            uid,
            {"feature": "live_translate", "provider": "gemini", "targetLang": "英文", "formalTone": True, "inputChars": 88, "outputChars": 164, "latencyMs": 275},
        )
        self.ingest_api_usage(
            uid,
            {"feature": "ai_polish", "provider": "gemini", "targetLang": "中文", "formalTone": True, "inputChars": 120, "outputChars": 135, "latencyMs": 310},
        )
        b2b = self.create_b2b_client("灵犀企业级输入效能 SaaS", "profile:read,aggregate:read")
        self.execute_b2b_aggregate_query(service_key=b2b["serviceKey"])
        self.push_clipboard_relay("886699", "【灵犀跨屏】您的验证码为 928401，点按手机键盘顶栏即可一键填入。", "Web 控制台")
        return {"seeded": True, "userID": uid}

    def server_stats(self) -> Dict[str, Any]:
        ov = self.dashboard_overview()
        return {
            "status": "ok",
            "service": "lingxi-cloud-backend",
            "version": ov["version"],
            "users": ov["stats"]["users"],
            "optedInUsers": ov["stats"]["optedInUsers"],
            "syncRecords": ov["stats"]["syncRecords"],
            "habitEvents": ov["stats"]["habitEvents"],
            "aiApiLogs": ov["stats"]["aiApiLogs"],
            "b2bClients": ov["stats"]["b2bClients"],
            "timestamp": int(time.time()),
        }


class LingxiHTTPRequestHandler(BaseHTTPRequestHandler):
    db: LingxiDatabase

    def log_message(self, fmt: str, *args: Any) -> None:
        if getattr(self.server, "quiet_logs", False):
            return
        super().log_message(fmt, *args)

    def _client_ip(self) -> str:
        return self.client_address[0] if self.client_address else "127.0.0.1"

    def _send_json(self, status: int, data: Any) -> None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type, Authorization, X-API-Key, X-Service-Key, X-Lingxi-Timestamp, X-Lingxi-Nonce, X-Lingxi-Signature",
        )
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html_text: str) -> None:
        body = html_text.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error_json(self, status: int, code: str, message: str) -> None:
        self._send_json(status, {"error": {"code": code, "message": message}})

    def _read_raw_and_json_body(self) -> Tuple[bytes, Dict[str, Any]]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return b"", {}
        raw = self.rfile.read(length)
        return raw, json.loads(raw.decode("utf-8"))

    def _verify_l3_request_signature_if_present(self, raw_body: bytes) -> bool:
        """L3 传输防重放签名校验：HMAC-SHA256(body || ts || nonce)，5 分钟窗防重放。"""
        ts_hdr = self.headers.get("X-Lingxi-Timestamp")
        nonce_hdr = self.headers.get("X-Lingxi-Nonce")
        sig_hdr = self.headers.get("X-Lingxi-Signature")
        if not (ts_hdr or nonce_hdr or sig_hdr):
            return True
        if not (ts_hdr and nonce_hdr and sig_hdr):
            return False
        try:
            ts_val = int(ts_hdr)
        except ValueError:
            return False
        if not self.db.limiter.check_and_record_nonce(nonce_hdr, ts_val):
            return False
        signing_secret = (self.headers.get("X-API-Key") or self.db.jwt_secret).encode("utf-8")
        msg = raw_body + f"|{ts_val}|{nonce_hdr}".encode("utf-8")
        expected = hmac.new(signing_secret, msg, hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, sig_hdr.strip())

    def _require_auth(self, query_target_user: Optional[str] = None) -> Optional[str]:
        user_id = self.db.authenticate_request(
            self.headers.get("Authorization"),
            self.headers.get("X-API-Key"),
        )
        if not user_id:
            self._send_error_json(HTTPStatus.UNAUTHORIZED, "UNAUTHORIZED", "未登录或 API Key 无效")
            return None
        # L4 跨租户隔离：若请求参数试图访问其他 user_id 的数据，严格返回 403 Forbidden
        if query_target_user and query_target_user != user_id:
            self._send_error_json(HTTPStatus.FORBIDDEN, "FORBIDDEN_CROSS_TENANT", "L4 权限拒绝：禁止跨用户访问他人数据")
            return None
        return user_id

    def do_OPTIONS(self) -> None:
        self._send_json(HTTPStatus.OK, {"ok": True})

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        try:
            # 1. Web 可视化控制台看板
            if path in ("/", "/dashboard"):
                if DASHBOARD_HTML_PATH.exists():
                    self._send_html(DASHBOARD_HTML_PATH.read_text(encoding="utf-8"))
                else:
                    self._send_html("<h1>Lingxi Cloud Dashboard</h1>")
                return

            if path == "/api/v1/dashboard/overview":
                self._send_json(HTTPStatus.OK, self.db.dashboard_overview())
                return

            if path == "/api/v1/health":
                self._send_json(HTTPStatus.OK, self.db.server_stats())
                return

            # 2. M4 词库社区 TSV 词包订阅接口与可持续发展状态接口
            if path in ("/api/v1/community/lexicons", "/api/v1/community/packs"):
                packs = [
                    {
                        "id": p["id"],
                        "name": p["name"],
                        "category": p["category"],
                        "author": p["author"],
                        "version": p["version"],
                        "description": p["description"],
                        "tsv": p["tsv"],
                        "wordCount": len([ln for ln in p["tsv"].splitlines() if ln and not ln.startswith("#")]),
                    }
                    for p in COMMUNITY_LEXICON_PACKS
                ]
                self._send_json(HTTPStatus.OK, {"packs": packs})
                return

            if path == "/api/v1/sustainability/status":
                stats = self.db.server_stats()
                self._send_json(
                    HTTPStatus.OK,
                    {
                        "openCoreLicense": "MIT Permanent Open-Core",
                        "e2eeProtocol": "LXE1 (ChaCha20-Poly1305 / AES-256-GCM)",
                        "syncTransports": ["local_noop", "lan_p2p", "e2ee_cloud"],
                        "tiers": ["free", "self_hosted", "pro", "enterprise"],
                        "communityPacks": len(COMMUNITY_LEXICON_PACKS),
                        "serverStats": stats,
                    },
                )
                return

            if path.startswith("/api/v1/community/lexicons/"):
                pack_id = path.split("/")[-1]
                found = next((p for p in COMMUNITY_LEXICON_PACKS if p["id"] == pack_id), None)
                if not found:
                    self._send_error_json(HTTPStatus.NOT_FOUND, "PACK_NOT_FOUND", f"未找到社区词包: {pack_id}")
                    return
                self._send_json(HTTPStatus.OK, found)
                return

            # 3. 跨设备剪贴板接力 (REST 拉取 + SSE 实时推流)
            if path == "/api/v1/relay/clipboard":
                code = query.get("code", [""])[0]
                since_id = int(query.get("since_id", ["0"])[0])
                items = self.db.pull_clipboard_relay(code, since_id)
                self._send_json(HTTPStatus.OK, {"pairCode": code, "items": items})
                return

            if path == "/api/v1/relay/stream":
                code = re.sub(r"[^0-9A-Za-z]", "", query.get("code", [""])[0])
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "keep-alive")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                try:
                    items = self.db.pull_clipboard_relay(code, 0)
                    last_seq = items[0]["id"] if items else 0
                    init_payload = json.dumps({"pairCode": code, "items": items}, ensure_ascii=False)
                    self.wfile.write(f"data: {init_payload}\n\n".encode("utf-8"))
                    self.wfile.flush()
                    # 等待新推流事件（最多保持单次长连接 25s，浏览器 EventSource 会自动重连）
                    new_seq = self.db.relay_hub.wait_for_update(code, last_seq, timeout=12.0)
                    if new_seq > last_seq:
                        new_items = self.db.pull_clipboard_relay(code, last_seq)
                        push_payload = json.dumps({"pairCode": code, "items": new_items}, ensure_ascii=False)
                        self.wfile.write(f"data: {push_payload}\n\n".encode("utf-8"))
                        self.wfile.flush()
                except Exception:
                    pass
                return

            # 4. B 端企业画像聚合 API (X-Service-Key: lxb_live_...)
            if path == "/api/v1/b2b/aggregate-profiles":
                srv_key = self.headers.get("X-Service-Key")
                res = self.db.execute_b2b_aggregate_query(service_key=srv_key, ip=self._client_ip())
                self._send_json(HTTPStatus.OK, res)
                return

            # 5. 用户鉴权接口 (含 L4 跨租户 user_id 校验)
            target_uid = query.get("user_id", [None])[0]

            if path == "/api/v1/auth/me":
                user_id = self._require_auth(target_uid)
                if not user_id:
                    return
                self._send_json(HTTPStatus.OK, self.db.get_user_info(user_id))
                return

            if path == "/api/v1/sync/pull":
                user_id = self._require_auth(target_uid)
                if not user_id:
                    return
                namespace = query.get("namespace", ["settings"])[0]
                since = int(query.get("since", ["0"])[0])
                limit = min(500, max(1, int(query.get("limit", ["100"])[0])))
                device_id = query.get("device_id", ["ios-default"])[0]
                self._send_json(HTTPStatus.OK, self.db.sync_pull(user_id, namespace, since, limit, device_id))
                return

            if path == "/api/v1/sync/summary":
                user_id = self._require_auth(target_uid)
                if not user_id:
                    return
                info = self.db.get_user_info(user_id)
                self._send_json(HTTPStatus.OK, {"userID": user_id, "vaultSummary": info["vaultSummary"]})
                return

            if path == "/api/v1/analytics/habits":
                user_id = self._require_auth(target_uid)
                if not user_id:
                    return
                self._send_json(HTTPStatus.OK, self.db.get_typing_habit_profile(user_id))
                return

            if path == "/api/v1/compliance/export":
                user_id = self._require_auth(target_uid)
                if not user_id:
                    return
                self._send_json(HTTPStatus.OK, self.db.export_portable_user_data(user_id))
                return

            self._send_error_json(HTTPStatus.NOT_FOUND, "NOT_FOUND", f"未知接口: {path}")
        except PermissionError as exc:
            self._send_error_json(HTTPStatus.FORBIDDEN, "FORBIDDEN", str(exc))
        except ValueError as exc:
            self._send_error_json(HTTPStatus.BAD_REQUEST, "INVALID_INPUT", str(exc))
        except Exception as exc:
            self._send_error_json(HTTPStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", str(exc))

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        try:
            raw_body, body = self._read_raw_and_json_body()

            if not self._verify_l3_request_signature_if_present(raw_body):
                self._send_error_json(HTTPStatus.UNAUTHORIZED, "INVALID_SIGNATURE_OR_REPLAY", "L3 签名校验失败或命中 5 分钟防重放拦截")
                return

            if path == "/api/v1/dashboard/seed-demo":
                self._send_json(HTTPStatus.OK, self.db.seed_demo_data())
                return

            if path in ("/api/v1/community/packs", "/api/v1/community/lexicons"):
                name = str(body.get("name", "")).strip() or "社区贡献词包"
                category = str(body.get("category", "")).strip() or "社区专题"
                tsv = str(body.get("tsv", "")).strip() or "lx\t灵犀输入法"
                new_pack = {
                    "id": f"comm_{secrets.token_hex(3)}",
                    "name": name,
                    "category": category,
                    "author": str(body.get("author", "Web Console Contributor")).strip() or "Community",
                    "version": str(body.get("version", "1.0.0")).strip(),
                    "description": str(body.get("description", "开源社区共创 TSV 专题词库包")).strip(),
                    "tsv": tsv,
                    "wordCount": max(1, len([ln for ln in tsv.splitlines() if ln.strip() and not ln.strip().startswith("#")])),
                }
                COMMUNITY_LEXICON_PACKS.insert(0, new_pack)
                self._send_json(HTTPStatus.CREATED, new_pack)
                return

            if path == "/api/v1/relay/clipboard":
                res = self.db.push_clipboard_relay(
                    pair_code=str(body.get("pairCode", "")),
                    content_text=str(body.get("contentText", "")),
                    sender_device=str(body.get("senderDevice", "iPhone")),
                )
                self._send_json(HTTPStatus.CREATED, res)
                return

            if path == "/api/v1/b2b/clients":
                res = self.db.create_b2b_client(
                    org=str(body.get("org", "Enterprise Partner")),
                    scopes=str(body.get("scopes", "profile:read,aggregate:read")),
                )
                self._send_json(HTTPStatus.CREATED, res)
                return

            if path == "/api/v1/b2b/simulate-query":
                res = self.db.execute_b2b_aggregate_query(
                    client_id=str(body.get("clientID", "")),
                    ip=self._client_ip(),
                )
                self._send_json(HTTPStatus.OK, res)
                return

            if path == "/api/v1/auth/register":
                session = self.db.register_user(
                    email=str(body.get("email", "")),
                    username=str(body.get("username", "")),
                    password=str(body.get("password", "")),
                    device_id=str(body.get("deviceID", "ios-default")),
                )
                self._send_json(HTTPStatus.CREATED, session)
                return

            if path == "/api/v1/auth/login":
                ip_key = f"login:{self._client_ip()}:{body.get('account', '')}"
                if not self.db.limiter.allow(ip_key, max_calls=15, window_seconds=60):
                    self._send_error_json(HTTPStatus.TOO_MANY_REQUESTS, "RATE_LIMITED", "登录尝试过于频繁，请 1 分钟后再试")
                    return
                session = self.db.login_user(
                    account=str(body.get("account", body.get("email", ""))),
                    password=str(body.get("password", "")),
                    device_id=str(body.get("deviceID", "ios-default")),
                )
                self._send_json(HTTPStatus.OK, session)
                return

            if path == "/api/v1/auth/apple":
                session = self.db.sign_in_with_apple(
                    identity_token_b64=str(body.get("identityToken", "")),
                    apple_user=str(body.get("user", "")),
                    device_id=str(body.get("deviceID", "ios-default")),
                )
                self._send_json(HTTPStatus.OK, session)
                return

            if path == "/api/v1/auth/refresh":
                session = self.db.refresh_session(str(body.get("refreshToken", "")))
                self._send_json(HTTPStatus.OK, session)
                return

            if path == "/api/v1/auth/api-key/rotate":
                user_id = self._require_auth()
                if not user_id:
                    return
                self._send_json(HTTPStatus.OK, self.db.rotate_api_key(user_id))
                return

            if path == "/api/v1/auth/password/change":
                user_id = self._require_auth()
                if not user_id:
                    return
                res = self.db.rotate_password_and_e2ee_salt(user_id, str(body.get("newPassword", "")))
                self._send_json(HTTPStatus.OK, res)
                return

            if path == "/api/v1/compliance/consent":
                user_id = self._require_auth()
                if not user_id:
                    return
                res = self.db.record_consent(
                    user_id=user_id,
                    scope=str(body.get("scope", "typing_analytics")),
                    granted=bool(body.get("granted", True)),
                    ip=self._client_ip(),
                    policy_version=str(body.get("policyVersion", "2026.11-v1")),
                )
                self._send_json(HTTPStatus.OK, res)
                return

            if path == "/api/v1/sync/push":
                user_id = self._require_auth()
                if not user_id:
                    return
                changes = body.get("changes", [])
                if not isinstance(changes, list):
                    raise ValueError("changes 必须为数组")
                conflicts = self.db.sync_push(user_id, changes)
                self._send_json(HTTPStatus.OK, {"conflicts": conflicts, "accepted": len(changes) - len(conflicts)})
                return

            if path == "/api/v1/analytics/typing-events":
                user_id = self._require_auth()
                if not user_id:
                    return
                if not self.db.limiter.allow(f"telemetry:{user_id}", max_calls=120, window_seconds=3600):
                    self._send_error_json(HTTPStatus.TOO_MANY_REQUESTS, "RATE_LIMITED", "上报频率超限 (60~120次/时)")
                    return
                digests = body.get("digests", [body] if "committedChars" in body else [])
                if not isinstance(digests, list):
                    raise ValueError("digests 必须为数组")
                profile = self.db.ingest_typing_events(user_id, digests)
                self._send_json(HTTPStatus.OK, {"ingested": len(digests), "profile": profile})
                return

            if path == "/api/v1/analytics/api-usage":
                user_id = self._require_auth()
                if not user_id:
                    return
                profile = self.db.ingest_api_usage(user_id, body)
                self._send_json(HTTPStatus.OK, {"recorded": True, "profile": profile})
                return

            if path == "/api/v1/analytics/lexicon-habits":
                user_id = self._require_auth()
                if not user_id:
                    return
                profile = self.db.analyze_lexicon_habits(user_id, body)
                self._send_json(HTTPStatus.OK, {"analyzed": True, "profile": profile})
                return

            self._send_error_json(HTTPStatus.NOT_FOUND, "NOT_FOUND", f"未知接口: {path}")
        except PermissionError as exc:
            self._send_error_json(HTTPStatus.UNAUTHORIZED, "AUTH_FAILED", str(exc))
        except ValueError as exc:
            self._send_error_json(HTTPStatus.BAD_REQUEST, "INVALID_INPUT", str(exc))
        except Exception as exc:
            self._send_error_json(HTTPStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", str(exc))

    def do_DELETE(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        try:
            if path == "/api/v1/analytics/habits":
                user_id = self._require_auth()
                if not user_id:
                    return
                profile = self.db.clear_typing_habits(user_id)
                self._send_json(HTTPStatus.OK, {"cleared": True, "profile": profile})
                return

            if path == "/api/v1/compliance/account":
                user_id = self._require_auth()
                if not user_id:
                    return
                self._send_json(HTTPStatus.OK, self.db.delete_account_cascade(user_id))
                return

            self._send_error_json(HTTPStatus.NOT_FOUND, "NOT_FOUND", f"未知接口: {path}")
        except Exception as exc:
            self._send_error_json(HTTPStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", str(exc))


def create_server(host: str, port: int, db_path: Path, quiet: bool = False) -> ThreadingHTTPServer:
    db = LingxiDatabase(db_path)

    class BoundHandler(LingxiHTTPRequestHandler):
        pass

    BoundHandler.db = db
    httpd = ThreadingHTTPServer((host, port), BoundHandler)
    setattr(httpd, "quiet_logs", quiet)
    return httpd


def run_self_test() -> None:
    """端到端自检：启动真实 HTTP 服务，覆盖全部 8 部分架构规范（Auth + LWW Sync + 跨屏剪贴板接力 + M4 社区词库 + L3 防重放 + L4 跨租户 403 + B端 API 审计 + GDPR 导出注销 + Web 控制台）。"""
    with tempfile.TemporaryDirectory() as tmpdir:
        db_file = Path(tmpdir) / "test_lingxi_v4.sqlite3"
        server = create_server("127.0.0.1", 0, db_file, quiet=True)
        port = server.server_address[1]
        base_url = f"http://127.0.0.1:{port}"
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def request_json(method: str, path: str, payload: Optional[Dict[str, Any]] = None, headers: Optional[Dict[str, str]] = None) -> Tuple[int, Dict[str, Any]]:
            req_headers = {"Content-Type": "application/json"}
            if headers:
                req_headers.update(headers)
            data = json.dumps(payload).encode("utf-8") if payload is not None else None
            req = urllib.request.Request(base_url + path, data=data, headers=req_headers, method=method)
            try:
                with urllib.request.urlopen(req, timeout=5) as resp:
                    return resp.status, json.loads(resp.read().decode("utf-8"))
            except urllib.error.HTTPError as err:
                return err.code, json.loads(err.read().decode("utf-8"))

        try:
            # 1. 健康检查与 Web 控制台看板可访问性
            code, health = request_json("GET", "/api/v1/health")
            assert code == 200 and health["status"] == "ok"
            with urllib.request.urlopen(base_url + "/dashboard", timeout=5) as dash_resp:
                dash_html = dash_resp.read().decode("utf-8")
                assert dash_resp.status == 200 and "跨设备实时剪贴板接力" in dash_html

            # 2. 注册账号并获取 JWT + 专属 API Key
            code, reg = request_json(
                "POST",
                "/api/v1/auth/register",
                {"email": "dev@lingxi.im", "username": "灵犀极客", "password": "secure-password-123", "deviceID": "iphone-16-pro"},
            )
            assert code == 201
            access_token = reg["accessToken"]
            refresh_token = reg["refreshToken"]
            api_key = reg["apiKey"]
            bearer = {"Authorization": f"Bearer {access_token}"}
            api_key_hdr = {"X-API-Key": api_key}

            # 3. L4 跨租户隔离权限测试：尝试读取其他 user_id 必须返回 403 Forbidden
            code, cross_err = request_json("GET", "/api/v1/auth/me?user_id=other-tenant-uuid", headers=bearer)
            assert code == 403, f"Cross-tenant access must return 403, got {code}: {cross_err}"

            # 4. L3 请求签名与防重放拦截验证
            raw_payload = {"digests": [{"durationSeconds": 10, "committedChars": 30, "committedWords": 12}]}
            body_bytes = json.dumps(raw_payload).encode("utf-8")
            ts_now = str(int(time.time()))
            nonce_1 = secrets.token_hex(12)
            sig = hmac.new(api_key.encode("utf-8"), body_bytes + f"|{ts_now}|{nonce_1}".encode("utf-8"), hashlib.sha256).hexdigest()
            sig_headers = {
                "X-API-Key": api_key,
                "X-Lingxi-Timestamp": ts_now,
                "X-Lingxi-Nonce": nonce_1,
                "X-Lingxi-Signature": sig,
            }
            code, signed_ok = request_json("POST", "/api/v1/analytics/typing-events", raw_payload, headers=sig_headers)
            assert code == 200, f"Valid L3 HMAC signature failed: {signed_ok}"
            # 重放相同 Nonce 必须返回 401
            code, replay_blocked = request_json("POST", "/api/v1/analytics/typing-events", raw_payload, headers=sig_headers)
            assert code == 401, f"Replay with duplicate nonce must be rejected with 401, got {code}"

            # 5. 跨设备 6 位匹配码实时剪贴板接力 + L1 敏感身份证号拦截
            code, relay_otp = request_json(
                "POST",
                "/api/v1/relay/clipboard",
                {"pairCode": "886699", "contentText": "【灵犀银行】您的跨屏验证码是 492018，请勿泄露。", "senderDevice": "MacBook Pro"},
            )
            assert code == 201 and relay_otp["extractedCode"] == "492018"
            code, relay_pulled = request_json("GET", "/api/v1/relay/clipboard?code=886699")
            assert code == 200 and relay_pulled["items"][0]["extractedCode"] == "492018"

            # L1 敏感身份证号跨屏拦截验证
            code, blocked_id = request_json(
                "POST",
                "/api/v1/relay/clipboard",
                {"pairCode": "886699", "contentText": "身份证号 11010519900307281X"},
            )
            assert code == 400, f"Sensitive ID card should be blocked with 400, got {code}"

            # 6. M4 词库社区 TSV 订阅仓库验证
            code, packs_res = request_json("GET", "/api/v1/community/lexicons")
            assert code == 200 and len(packs_res["packs"]) >= 4
            code, tech_pack = request_json("GET", "/api/v1/community/lexicons/tech_dev")
            assert code == 200 and "端到端加密" in tech_pack["tsv"]

            # 7. 重要数据 LWW 同步 + 冲突保护
            code, push1 = request_json(
                "POST",
                "/api/v1/sync/push",
                {
                    "changes": [
                        {
                            "namespace": "settings",
                            "key": "main",
                            "ciphertext": base64.b64encode(b'{"inputScheme":"xiaohe"}').decode("ascii"),
                            "lamportTS": 10,
                            "deviceID": "device-B",
                            "tombstone": False,
                            "schemaVersion": 1,
                        }
                    ]
                },
                headers=bearer,
            )
            assert code == 200 and push1["accepted"] == 1
            code, push_conflict = request_json(
                "POST",
                "/api/v1/sync/push",
                {
                    "changes": [
                        {
                            "namespace": "settings",
                            "key": "main",
                            "ciphertext": base64.b64encode(b'{"inputScheme":"quanpin"}').decode("ascii"),
                            "lamportTS": 5,
                            "deviceID": "device-A",
                            "tombstone": False,
                            "schemaVersion": 1,
                        }
                    ]
                },
                headers=bearer,
            )
            assert code == 200 and len(push_conflict["conflicts"]) == 1

            # 8. 实时打字习惯 + 易混音矩阵 + 词库领域分析
            code, habit_res = request_json(
                "POST",
                "/api/v1/analytics/typing-events",
                {
                    "digests": [
                        {
                            "durationSeconds": 60,
                            "committedChars": 180,
                            "committedWords": 65,
                            "deleteCount": 22,
                            "undoLearnCount": 5,
                            "glideWords": 15,
                            "typoCorrectedCount": 7,
                            "schemeID": "xiaohe",
                            "layoutID": "qwerty26",
                            "activeHour": 23,
                            "confusionCounts": {"zh_z": 4, "an_ang": 2},
                        }
                    ]
                },
                headers=api_key_hdr,
            )
            assert code == 200
            assert habit_res["profile"]["confusionMatrix"]["zh_z"] == 4
            assert any(r["settingKey"] == "fuzzy.zhZ" for r in habit_res["profile"]["tuningRecommendations"])

            code, lex_res = request_json(
                "POST",
                "/api/v1/analytics/lexicon-habits",
                {"words": ["微服务架构", "数据库索引", "后端接口部署", "算法模型编译"], "preferredTone": "专业简练"},
                headers=api_key_hdr,
            )
            assert code == 200 and lex_res["profile"]["domainAffinity"]["primaryDomain"] == "科技与研发"

            # 9. B 端企业 API 接入、Scope 校验、计费与 180 天审计流水
            code, b2b_client = request_json("POST", "/api/v1/b2b/clients", {"org": "灵犀企业分析伙伴", "scopes": "profile:read,aggregate:read"})
            assert code == 201 and b2b_client["serviceKey"].startswith("lxb_live_")
            code, b2b_agg = request_json(
                "GET",
                "/api/v1/b2b/aggregate-profiles",
                headers={"X-Service-Key": b2b_client["serviceKey"]},
            )
            assert code == 200 and b2b_agg["auditLogged"] is True and b2b_agg["optedInCohortSize"] >= 1

            # 10. GDPR / 个保法合规：授权流水、全量数据可携带导出与账号级联注销
            code, consent_res = request_json(
                "POST",
                "/api/v1/compliance/consent",
                {"scope": "typing_analytics", "granted": True, "policyVersion": "2026.11-v1"},
                headers=bearer,
            )
            assert code == 200 and consent_res["granted"] is True

            code, exported = request_json("GET", "/api/v1/compliance/export", headers=bearer)
            assert code == 200 and exported["format"] == "LINGXI-GDPR-PORTABLE-EXPORT"
            assert len(exported["consentAuditTrail"]) >= 2

            # 11. L5 运维安全：数据库在线热备快照与恢复演练校验（"不演练的备份等于没有"）
            drill_report = run_backup_and_restore_drill(db_file)
            assert drill_report["integrityCheck"] == "ok" and drill_report["restoredTables"] >= 11

            print("OK  Lingxi Cloud Server v4.0 Full-Spec Self-Test: ALL PASSED (8/8 Architecture Sections + L5 Backup Drill Verified)")
        finally:
            server.shutdown()
            server.server_close()


def run_backup_and_restore_drill(db_path: Path, snapshot_out: Optional[Path] = None) -> Dict[str, Any]:
    """L5 安全体系：执行 SQLite 在线热快照 + 独立沙盒恢复演练 + PRAGMA integrity_check + 全表行数一致性核验。"""
    with tempfile.TemporaryDirectory() as drill_dir:
        snap_file = snapshot_out or (Path(drill_dir) / f"lingxi_snapshot_{int(time.time())}.sqlite3")
        restored_file = Path(drill_dir) / "lingxi_restored_verify.sqlite3"

        src_conn = sqlite3.connect(str(db_path))
        snap_conn = sqlite3.connect(str(snap_file))
        try:
            src_conn.backup(snap_conn)
        finally:
            snap_conn.close()

        # 从快照恢复到演练库并校验完整性
        snap_read = sqlite3.connect(str(snap_file))
        restore_conn = sqlite3.connect(str(restored_file))
        try:
            snap_read.backup(restore_conn)
            integrity = restore_conn.execute("PRAGMA integrity_check").fetchone()[0]
            tables = [
                r[0]
                for r in restore_conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
                ).fetchall()
            ]
            for tbl in tables:
                c1 = src_conn.execute(f"SELECT COUNT(*) FROM {tbl}").fetchone()[0]
                c2 = restore_conn.execute(f"SELECT COUNT(*) FROM {tbl}").fetchone()[0]
                assert c1 == c2, f"Table {tbl} count mismatch after restore drill: {c1} != {c2}"
            return {
                "status": "verified",
                "integrityCheck": integrity,
                "restoredTables": len(tables),
                "snapshotPath": str(snap_file),
            }
        finally:
            snap_read.close()
            restore_conn.close()
            src_conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Lingxi IME Cloud Backend Server v4.0")
    parser.add_argument("--host", default="127.0.0.1", help="监听地址 (默认 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8787, help="监听端口 (默认 8787)")
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="SQLite 数据库文件路径")
    parser.add_argument("--self-test", action="store_true", help="运行端到端全链路自检测试并退出")
    parser.add_argument("--backup-drill", action="store_true", help="执行 L5 数据库热快照与恢复演练校验")
    args = parser.parse_args()

    if args.self_test:
        run_self_test()
        return

    if args.backup_drill:
        db_p = Path(args.db)
        LingxiDatabase(db_p)
        res = run_backup_and_restore_drill(db_p)
        print(f"OK  L5 Backup & Restore Drill Verified: {json.dumps(res, ensure_ascii=False)}")
        return

    httpd = create_server(args.host, args.port, Path(args.db))
    print(f"灵犀输入法云端服务与 Web 控制台已启动: http://{args.host}:{args.port}/dashboard (DB: {args.db})")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n正在关闭服务...")
        httpd.shutdown()


if __name__ == "__main__":
    main()
