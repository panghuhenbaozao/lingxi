import { DASHBOARD_HTML } from "./dashboard.js";

const VERSION = "5.1.2";
const ACCESS_TTL_SEC = 86400;
const REFRESH_TTL_SEC = 86400 * 30;
const PBKDF2_ITERATIONS = 100000;

const BUILTIN_PACKS = [
  {
    id: "tech_dev",
    name: "科技与程序员高频词包",
    category: "科技研发",
    author: "Lingxi Open Community",
    version: "1.4.0",
    description: "大模型、云原生、iOS/Swift、Cloudflare Workers 高频术语与快捷短语",
    tsv: "dm\t大模型\nllm\t大语言模型\nk8s\tKubernetes\nsw\tSwiftUI\ncf\tCloudflare Workers\ngit\tGitHub Actions\napi\tRESTful API\ne2ee\t端到端零知识加密\nsql\tSQLite D1\n"
  },
  {
    id: "business_office",
    name: "职场商务与高情商沟通词包",
    category: "商务职场",
    author: "Lingxi Open Community",
    version: "1.2.0",
    description: "周报、邮件、会议纪要与高频商务礼貌用语",
    tsv: "sd\t收到，马上处理\nxk\t辛苦了，感谢支持\nhy\t会议纪要如下\njz\t进展同步一下\nqr\t麻烦确认一下\ngx\t感谢您的耐心配合\n"
  },
  {
    id: "daily_slang",
    name: "日常社交与流行表达词包",
    category: "日常社交",
    author: "Lingxi Open Community",
    version: "1.1.0",
    description: "轻松日常聊天高频词组与温暖回复",
    tsv: "wsm\t为什么呀\nzaima\t在吗方便聊两句吗\nhde\t好的没问题\nxie\t太感谢啦\nwanan\t晚安好梦\n"
  }
];

const enc = new TextEncoder();
const dec = new TextDecoder();
const toHex = (b) => Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
const fromHex = (h) => {
  const o = new Uint8Array(h.length / 2);
  for (let i = 0; i < o.length; i++) o[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16);
  return o;
};
const randHex = (n) => {
  const a = new Uint8Array(n);
  crypto.getRandomValues(a);
  return toHex(a);
};
const b64uEnc = (b) => {
  let s = "";
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};
const b64uDec = (s) => {
  const p = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  const bin = atob(p);
  const o = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) o[i] = bin.charCodeAt(i);
  return o;
};
const eqSafe = (a, b) => {
  const ab = enc.encode(String(a));
  const bb = enc.encode(String(b));
  if (ab.length !== bb.length) return false;
  let d = 0;
  for (let i = 0; i < ab.length; i++) d |= ab[i] ^ bb[i];
  return d === 0;
};
const sha256 = async (t) => toHex(new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(t))));
const nowSec = () => Math.floor(Date.now() / 1000);

function derToP1363(der) {
  if (der.length === 64) return der;
  let offset = 0;
  if (der[offset++] !== 0x30) throw new Error("Invalid DER sequence");
  let seqLen = der[offset++];
  if (seqLen & 0x80) offset += (seqLen & 0x7f);
  if (der[offset++] !== 0x02) throw new Error("Invalid DER R");
  const rLen = der[offset++];
  const rBytes = der.slice(offset, offset + rLen);
  offset += rLen;
  if (der[offset++] !== 0x02) throw new Error("Invalid DER S");
  const sLen = der[offset++];
  const sBytes = der.slice(offset, offset + sLen);
  const out = new Uint8Array(64);
  const rTrim = rBytes.length > 32 ? rBytes.slice(rBytes.length - 32) : rBytes;
  const sTrim = sBytes.length > 32 ? sBytes.slice(sBytes.length - 32) : sBytes;
  out.set(rTrim, 32 - rTrim.length);
  out.set(sTrim, 64 - sTrim.length);
  return out;
}

async function ensurePasskeyTables(env) {
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS passkey_credentials (cred_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, public_key_spki_b64 TEXT NOT NULL, label TEXT DEFAULT '', created_at INTEGER NOT NULL)"
  ).run();
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS passkey_challenges (id TEXT PRIMARY KEY, challenge TEXT NOT NULL, expires_at INTEGER NOT NULL)"
  ).run();
}

function renderApplePasskeyHTML(rpId, defaultDevId) {
  return `<!DOCTYPE html><html lang="zh-Hans"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>通过 Apple 通行密钥登录灵犀</title>
<style>
:root{color-scheme:light dark;--bg:#F2F2F7;--card:#FFFFFF;--ink:#000;--mut:#6E6E73;--blue:#007AFF;--btn:#000;--btnt:#FFF;--bd:#E5E5EA}
@media(prefers-color-scheme:dark){:root{--bg:#000;--card:#1C1C1E;--ink:#FFF;--mut:#98989D;--blue:#0A84FF;--btn:#FFF;--btnt:#000;--bd:#38383A}}
*{box-sizing:border-box}body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px;background:var(--bg);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","PingFang SC",sans-serif}
.card{width:100%;max-width:400px;background:var(--card);border:1px solid var(--bd);border-radius:22px;padding:26px 22px;box-shadow:0 12px 32px rgba(0,0,0,.12)}
.logo{font-size:38px;text-align:center;margin-bottom:8px}h1{margin:0 0 8px;font-size:22px;text-align:center}
p{margin:0 0 18px;font-size:13.5px;color:var(--mut);text-align:center;line-height:1.5}
.in{width:100%;padding:12px 14px;border-radius:12px;border:1px solid var(--bd);background:var(--bg);color:var(--ink);font-size:15px;margin-bottom:12px}
.btn{width:100%;padding:14px;border:none;border-radius:13px;font-size:16px;font-weight:600;cursor:pointer;margin-bottom:10px;display:flex;align-items:center;justify-content:center;gap:8px}
.btn-apple{background:var(--btn);color:var(--btnt)}.btn-sub{background:var(--blue);color:#FFF}
.msg{margin-top:8px;font-size:13px;text-align:center;min-height:20px;color:var(--mut)}.err{color:#FF453A}.ok{color:#30D158}
</style></head><body><div class="card">
<div class="logo"></div>
<h1>Apple iCloud 通行密钥登录</h1>
<p>凭证通过 iOS 系统面容 ID 加密保存于您的 Apple ID iCloud 钥匙串，跨 iPhone / iPad / Mac 自动同步，并直连灵犀 Cloudflare 云端词库。</p>
<input id="nick" class="in" placeholder="昵称（首次创建时可选填，如：我的 iPhone）" maxlength="24"/>
<button class="btn btn-apple" onclick="doRegister()"> 首次使用：用 Apple ID 创建通行密钥并登录</button>
<button class="btn btn-sub" onclick="doLogin()">🔑 已有通行密钥：刷面容 ID 直接登录</button>
<div id="st" class="msg">首次登录请点上方黑色按钮，老用户点蓝色按钮</div>
</div><script>
const RP_ID = ${JSON.stringify(rpId)};
const DEV_ID = ${JSON.stringify(defaultDevId)};
const st = (m, cls='') => { const e=document.getElementById('st'); e.textContent=m; e.className='msg '+cls; };
const b64uToBuf = s => Uint8Array.from(atob(s.replace(/-/g,'+').replace(/_/g,'/')+'==='.slice((s.length+3)%4)), c=>c.charCodeAt(0));
const bufToB64u = b => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\\+/g,'-').replace(/\\//g,'_').replace(/=+$/,'');

async function doRegister() {
  try {
    st('正在拉起系统面容 ID 与 iCloud 钥匙串…');
    const nick = (document.getElementById('nick').value || '').trim() || 'Apple 用户';
    const chRes = await fetch('/api/v1/auth/passkey/challenge', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ mode:'register', username:nick }) });
    const ch = await chRes.json();
    if (!chRes.ok) throw new Error(ch?.error?.message || '获取挑战失败');
    const cred = await navigator.credentials.create({
      publicKey: {
        rp: { name: '灵犀输入法 (Lingxi Cloud)', id: RP_ID },
        user: { id: b64uToBuf(ch.userHandle), name: nick + ' (Apple iCloud)', displayName: nick },
        challenge: b64uToBuf(ch.challenge),
        pubKeyCredParams: [{ type:'public-key', alg:-7 }],
        authenticatorSelection: { authenticatorAttachment:'platform', residentKey:'required', userVerification:'required' },
        timeout: 60000, attestation: 'none'
      }
    });
    const spki = cred.response.getPublicKey ? cred.response.getPublicKey() : null;
    if (!spki) throw new Error('当前浏览器不支持导出通行密钥公钥');
    const regRes = await fetch('/api/v1/auth/passkey/register', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({
        challengeID: ch.challengeID,
        credentialID: cred.id,
        publicKeySPKI: bufToB64u(spki),
        username: nick,
        deviceID: DEV_ID
      })
    });
    const out = await regRes.json();
    if (!regRes.ok) throw new Error(out?.error?.message || '注册失败');
    st('✓ 通行密钥已绑定 iCloud，正在返回灵犀 App…', 'ok');
    location.href = 'lingxi://auth-callback?payload=' + encodeURIComponent(out.callbackPayload);
  } catch (e) { st('提示：' + (e.message || e), 'err'); }
}

async function doLogin() {
  try {
    st('正在拉起系统面容 ID 验证通行密钥…');
    const chRes = await fetch('/api/v1/auth/passkey/challenge', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ mode:'login' }) });
    const ch = await chRes.json();
    if (!chRes.ok) throw new Error(ch?.error?.message || '获取挑战失败');
    const assertion = await navigator.credentials.get({
      publicKey: { rpId: RP_ID, challenge: b64uToBuf(ch.challenge), userVerification:'required', timeout: 60000 }
    });
    const verRes = await fetch('/api/v1/auth/passkey/verify', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({
        challengeID: ch.challengeID,
        credentialID: assertion.id,
        clientDataJSON: bufToB64u(assertion.response.clientDataJSON),
        authenticatorData: bufToB64u(assertion.response.authenticatorData),
        signature: bufToB64u(assertion.response.signature),
        deviceID: DEV_ID
      })
    });
    const out = await verRes.json();
    if (!verRes.ok) throw new Error(out?.error?.message || '验签失败');
    st('✓ 面容 ID 验证通过，正在返回灵犀 App…', 'ok');
    location.href = 'lingxi://auth-callback?payload=' + encodeURIComponent(out.callbackPayload);
  } catch (e) { st('提示：' + (e.message || e), 'err'); }
}
</script></body></html>`;
}

async function hashPw(pw, salt = randHex(16)) {
  const k = await crypto.subtle.importKey("raw", enc.encode(pw), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: fromHex(salt), iterations: PBKDF2_ITERATIONS, hash: "SHA-256" },
    k,
    256
  );
  return `pbkdf2_sha256$${PBKDF2_ITERATIONS}$${salt}$${toHex(new Uint8Array(bits))}`;
}

async function verifyPw(pw, stored) {
  if (!stored || !stored.startsWith("pbkdf2_sha256$")) return false;
  const parts = stored.split("$");
  if (parts.length !== 4) return false;
  const k = await crypto.subtle.importKey("raw", enc.encode(pw), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: fromHex(parts[2]), iterations: parseInt(parts[1], 10), hash: "SHA-256" },
    k,
    256
  );
  return eqSafe(toHex(new Uint8Array(bits)), parts[3]);
}

async function hmacSign(data, secret) {
  const k = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return b64uEnc(new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(data))));
}

async function signToken(uid, dev, secret) {
  const iat = nowSec();
  const exp = iat + ACCESS_TTL_SEC;
  const body = b64uEnc(enc.encode(JSON.stringify({ sub: uid, dev, iat, exp })));
  return { token: `lxt.${body}.${await hmacSign(body, secret)}`, exp };
}

async function verifyToken(token, secret) {
  if (!token || !token.startsWith("lxt.")) return null;
  const p = token.split(".");
  if (p.length !== 3) return null;
  if (!eqSafe(p[2], await hmacSign(p[1], secret))) return null;
  try {
    const o = JSON.parse(dec.decode(b64uDec(p[1])));
    return o.sub && (!o.exp || o.exp >= nowSec()) ? o : null;
  } catch {
    return null;
  }
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-API-Key, X-Lingxi-Timestamp, X-Lingxi-Nonce, X-Lingxi-Signature"
};
const jres = (d, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { "Content-Type": "application/json; charset=utf-8", ...CORS } });
const eres = (s, c, m) => jres({ error: { code: c, message: m } }, s);

async function rjson(req) {
  const t = await req.text();
  if (!t.trim()) return {};
  try {
    return JSON.parse(t);
  } catch {
    throw { status: 400, code: "INVALID_JSON", message: "请求体不是有效的 JSON" };
  }
}

function extractOTP(text) {
  const t = (text || "").trim();
  if (!t || t.length > 300) return null;
  if (/^\d{4,8}$/.test(t)) return t;
  if (!/(验证码|校验码|动态码|确认码|取件码|激活码|code|otp|pin|verify)/i.test(t)) return null;
  const m1 = t.match(/(?:验证码|校验码|动态码|确认码|取件码|code|otp|pin)[：:\s为是]*([0-9]{4,8})/i);
  if (m1 && m1[1]) return m1[1];
  const m2 = t.match(/\b([0-9]{4,8})\b/);
  return m2 && m2[1] && !(m2[1].length === 4 && /^(19|20)/.test(m2[1])) ? m2[1] : null;
}

async function resolveAuth(req, env) {
  const sec = env.JWT_SECRET || "lingxi-cf-signing-key";
  const ah = req.headers.get("Authorization") || "";
  if (ah.startsWith("Bearer ")) {
    const p = await verifyToken(ah.slice(7).trim(), sec);
    if (p && p.sub) {
      const u = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(p.sub).first();
      if (u) return { user: u, deviceId: p.dev || "ios-default" };
    }
  }
  const ak = (req.headers.get("X-API-Key") || "").trim();
  if (ak) {
    const u = await env.DB.prepare("SELECT * FROM users WHERE api_key_hash = ?").bind(await sha256(ak)).first();
    if (u) return { user: u, deviceId: "api-key-client" };
  }
  return null;
}

async function issueSession(env, user, devId, rawKey = null) {
  const now = nowSec();
  const sec = env.JWT_SECRET || "lingxi-cf-signing-key";
  const { token: accessToken, exp } = await signToken(user.id, devId, sec);
  const refreshToken = `lxr_${randHex(24)}`;
  const devName = devId === "web-console" ? "Web 控制台" : "iPhone";
  const platform = devId === "web-console" ? "Web" : "iOS";

  await env.DB.prepare(
    "INSERT INTO auth_sessions (token_id, user_id, device_id, device_name, refresh_token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
  ).bind(crypto.randomUUID(), user.id, devId, devName, await sha256(refreshToken), now + REFRESH_TTL_SEC, now).run();

  await env.DB.prepare(
    "INSERT INTO devices (id, user_id, name, platform, app_ver, last_seen) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, id) DO UPDATE SET last_seen=excluded.last_seen, app_ver=excluded.app_ver, name=excluded.name"
  ).bind(devId, user.id, devName, platform, VERSION, now).run();

  const out = {
    userID: user.id,
    email: user.email || "",
    username: user.username || "灵犀用户",
    accessToken,
    refreshToken,
    accessExpiry: exp,
    apiKeyPrefix: user.api_key_prefix || "",
    e2eeSalt: user.e2ee_salt
  };
  if (rawKey) out.apiKey = rawKey;
  return out;
}

async function recomputeProfile(env, uid) {
  const now = nowSec();
  const evs = (await env.DB.prepare("SELECT * FROM typing_habit_events WHERE user_id = ? ORDER BY started_at DESC LIMIT 500").bind(uid).all()).results || [];
  const ais = (await env.DB.prepare("SELECT * FROM ai_api_usage_logs WHERE user_id = ? ORDER BY created_at DESC LIMIT 300").bind(uid).all()).results || [];
  const ex = await env.DB.prepare("SELECT domain_affinity_json FROM user_typing_profiles WHERE user_id = ?").bind(uid).first();
  let da = { primaryDomain: "综合通用", domainScores: {}, analyzedWordCount: 0, avgLexiconWordLength: 0, preferredTone: "自然流畅", topTerms: [] };
  if (ex && ex.domain_affinity_json) {
    try { da = { ...da, ...JSON.parse(ex.domain_affinity_json) }; } catch {}
  }

  let tc = 0, tw = 0, td = 0, tdel = 0, tul = 0, tgl = 0, ttp = 0, peak = 0;
  const sb = {}, lc = {}, hr = {}, cm = {};
  for (const e of evs) {
    const dur = Math.max(1, e.duration_seconds || 1);
    const ch = e.committed_chars || 0;
    const wd = e.committed_words || 0;
    tc += ch; tw += wd; td += dur;
    tdel += e.delete_count || 0;
    tul += e.undo_learn_count || 0;
    tgl += e.glide_words || 0;
    ttp += e.typo_corrected_count || 0;
    const cpm = (ch * 60) / dur;
    if (cpm > peak && cpm <= 600) peak = cpm;
    sb[e.scheme_id || "quanpin"] = (sb[e.scheme_id || "quanpin"] || 0) + ch;
    lc[e.layout_id || "qwerty26"] = (lc[e.layout_id || "qwerty26"] || 0) + ch;
    hr[String(e.active_hour ?? 12)] = (hr[String(e.active_hour ?? 12)] || 0) + ch;
    if (e.confusion_json) {
      try {
        for (const [k, v] of Object.entries(JSON.parse(e.confusion_json))) {
          cm[k] = (cm[k] || 0) + Number(v || 0);
        }
      } catch {}
    }
  }

  const aiMap = {};
  for (const l of ais) {
    const f = l.feature || "polish";
    if (!aiMap[f]) aiMap[f] = { calls: 0, inputChars: 0, outputChars: 0, lat: 0 };
    aiMap[f].calls++;
    aiMap[f].inputChars += l.input_chars || 0;
    aiMap[f].outputChars += l.output_chars || 0;
    aiMap[f].lat += l.latency_ms || 0;
  }
  const aiSum = {};
  for (const [k, v] of Object.entries(aiMap)) {
    aiSum[k] = { calls: v.calls, inputChars: v.inputChars, outputChars: v.outputChars, avgLatencyMs: Math.round(v.lat / Math.max(1, v.calls)) };
  }

  const avgCPM = td > 0 ? Number(((tc * 60) / td).toFixed(1)) : 0;
  const avgWL = tw > 0 ? Number((tc / tw).toFixed(2)) : 0;
  const br = tc > 0 ? Number((tdel / tc).toFixed(3)) : 0;
  const ur = tw > 0 ? Number((tul / tw).toFixed(3)) : 0;
  const gr = tw > 0 ? Number((tgl / tw).toFixed(3)) : 0;
  const tr = tw > 0 ? Number((ttp / tw).toFixed(3)) : 0;
  const ps = Object.entries(sb).sort((a, b) => b[1] - a[1])[0]?.[0] || "quanpin";
  const pl = Object.entries(lc).sort((a, b) => b[1] - a[1])[0]?.[0] || "qwerty26";

  const tags = [];
  if (avgCPM >= 65) tags.push("高速输入达人");
  else if (tc > 0) tags.push("稳健流畅输入");
  if (gr >= 0.25) tags.push("滑行输入爱好者");
  if (da.primaryDomain && da.primaryDomain !== "综合通用") tags.push(da.primaryDomain);
  if (!tags.length) tags.push("灵犀云端同步用户");

  const recs = [];
  if ((cm.zh_z || 0) >= 2) recs.push({ id: "fuzzy_zh_z", title: "开启平翘舌模糊音 (zh↔z)", reason: "检测到高频平翘舌混淆", settingKey: "fuzzy.zhZ" });
  if ((cm.an_ang || 0) >= 2) recs.push({ id: "fuzzy_an_ang", title: "开启前后鼻音模糊音 (an↔ang)", reason: "检测到高频前后鼻音混淆", settingKey: "fuzzy.anAng" });
  if ((cm.in_ing || 0) >= 2) recs.push({ id: "fuzzy_in_ing", title: "开启前后鼻音模糊音 (in↔ing)", reason: "检测到高频 in/ing 混淆", settingKey: "fuzzy.inIng" });
  if (br >= 0.14) recs.push({ id: "typo_boost", title: "保持智能纠错与动态热区开启", reason: "有助于进一步降低退格率", settingKey: "typoCorrectionEnabled" });

  const prof = {
    userID: uid, totalChars: tc, totalWords: tw, totalDurationSeconds: td, totalSessions: evs.length,
    avgCPM, peakCPM: Number(peak.toFixed(1)), avgWordLength: avgWL, backspaceRate: br, undoLearnRate: ur,
    glideRatio: gr, typoCorrectionRate: tr, primaryScheme: ps, primaryLayout: pl,
    schemeBreakdown: sb, hourlyRhythm: hr, aiFeatureBreakdown: aiSum, confusionMatrix: cm,
    domainAffinity: da, habitTags: tags, tuningRecommendations: recs, updatedAt: now
  };

  await env.DB.prepare(
    `INSERT INTO user_typing_profiles (
       user_id,total_chars,total_words,total_duration_seconds,total_sessions,avg_cpm,peak_cpm,avg_word_length,
       backspace_rate,undo_learn_rate,glide_ratio,typo_correction_rate,primary_scheme,primary_layout,
       scheme_breakdown_json,hourly_rhythm_json,ai_feature_breakdown_json,confusion_matrix_json,
       domain_affinity_json,habit_tags_json,tuning_recommendations_json,updated_at
     ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
     ON CONFLICT(user_id) DO UPDATE SET
       total_chars=excluded.total_chars,total_words=excluded.total_words,total_duration_seconds=excluded.total_duration_seconds,
       total_sessions=excluded.total_sessions,avg_cpm=excluded.avg_cpm,peak_cpm=excluded.peak_cpm,avg_word_length=excluded.avg_word_length,
       backspace_rate=excluded.backspace_rate,undo_learn_rate=excluded.undo_learn_rate,glide_ratio=excluded.glide_ratio,
       typo_correction_rate=excluded.typo_correction_rate,primary_scheme=excluded.primary_scheme,primary_layout=excluded.primary_layout,
       scheme_breakdown_json=excluded.scheme_breakdown_json,hourly_rhythm_json=excluded.hourly_rhythm_json,
       ai_feature_breakdown_json=excluded.ai_feature_breakdown_json,confusion_matrix_json=excluded.confusion_matrix_json,
       domain_affinity_json=excluded.domain_affinity_json,habit_tags_json=excluded.habit_tags_json,
       tuning_recommendations_json=excluded.tuning_recommendations_json,updated_at=excluded.updated_at`
  ).bind(
    uid, tc, tw, td, evs.length, avgCPM, prof.peakCPM, avgWL, br, ur, gr, tr, ps, pl,
    JSON.stringify(sb), JSON.stringify(hr), JSON.stringify(aiSum), JSON.stringify(cm),
    JSON.stringify(da), JSON.stringify(tags), JSON.stringify(recs), now
  ).run();
  return prof;
}

async function getStats(env) {
  const [u, o, s, h, a, b, d] = await Promise.all([
    env.DB.prepare("SELECT COUNT(*) AS c FROM users").first(),
    env.DB.prepare("SELECT COUNT(*) AS c FROM users WHERE analytics_opt_in=1").first(),
    env.DB.prepare("SELECT COUNT(*) AS c FROM sync_records WHERE tombstone=0").first(),
    env.DB.prepare("SELECT COUNT(*) AS c FROM typing_habit_events").first(),
    env.DB.prepare("SELECT COUNT(*) AS c, COALESCE(AVG(latency_ms),0) AS lat FROM ai_api_usage_logs").first(),
    env.DB.prepare("SELECT COUNT(*) AS c, COALESCE(SUM(billable_units),0) AS u FROM api_clients").first(),
    env.DB.prepare("SELECT COUNT(*) AS c FROM devices").first()
  ]);
  return {
    status: "ok",
    service: "lingxi-cloud-backend-cf",
    version: VERSION,
    users: u?.c || 0,
    optedInUsers: o?.c || 0,
    syncRecords: s?.c || 0,
    activeDevices: d?.c || 0,
    habitEvents: h?.c || 0,
    aiApiLogs: a?.c || 0,
    avgAiLatencyMs: Math.round(a?.lat || 0),
    b2bClients: b?.c || 0,
    b2bBillableUnits: b?.u || 0,
    timestamp: nowSec()
  };
}

async function listPacks(env) {
  const custom = (await env.DB.prepare("SELECT * FROM community_lexicons ORDER BY created_at DESC LIMIT 50").all()).results || [];
  const all = [
    ...BUILTIN_PACKS.map((p) => ({ ...p, isCustom: false })),
    ...custom.map((p) => ({ ...p, isCustom: true }))
  ];
  return all.map((p) => ({
    id: p.id,
    name: p.name,
    category: p.category,
    author: p.author,
    version: p.version,
    description: p.description || "",
    tsv: p.tsv,
    isCustom: p.isCustom,
    wordCount: (p.tsv || "").split(/\r?\n/).filter((l) => l.trim() && !l.startsWith("#")).length
  }));
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    const url = new URL(request.url);
    const path = url.pathname;
    const m = request.method;
    const ip = request.headers.get("CF-Connecting-IP") || "0.0.0.0";

    try {
      // 1. Dashboard & Health
      if (m === "GET" && (path === "/" || path === "/dashboard")) {
        return new Response(DASHBOARD_HTML, { status: 200, headers: { "Content-Type": "text/html; charset=utf-8", ...CORS } });
      }
      if (m === "GET" && path === "/api/v1/health") return jres(await getStats(env));

      if (m === "GET" && path === "/api/v1/dashboard/overview") {
        const [stats, profRes, nsRes, devRes, b2bRes, conRes, audRes, packs] = await Promise.all([
          getStats(env),
          env.DB.prepare("SELECT u.id AS user_id,u.username,u.email,p.* FROM users u LEFT JOIN user_typing_profiles p ON p.user_id=u.id ORDER BY u.last_login_at DESC LIMIT 50").all(),
          env.DB.prepare("SELECT namespace, COUNT(*) AS count, MAX(lamport_ts) AS maxLamport, MAX(updated_at) AS lastUpdated FROM sync_records WHERE tombstone=0 GROUP BY namespace").all(),
          env.DB.prepare("SELECT d.id, d.name, d.platform, d.app_ver AS appVer, d.last_seen AS lastSeen, u.username FROM devices d JOIN users u ON u.id=d.user_id ORDER BY d.last_seen DESC LIMIT 30").all(),
          env.DB.prepare("SELECT id, org, key_prefix AS keyPrefix, scopes, call_count AS callCount, billable_units AS billableUnits FROM api_clients ORDER BY created_at DESC LIMIT 30").all(),
          env.DB.prepare("SELECT id, user_id AS userID, scope, granted, at, policy_version AS policyVersion FROM consent_records ORDER BY at DESC LIMIT 25").all(),
          env.DB.prepare("SELECT id, org, endpoint, scope_used AS scopeUsed, status_code AS statusCode, created_at AS createdAt FROM b2b_audit_logs ORDER BY created_at DESC LIMIT 25").all(),
          listPacks(env)
        ]);

        const hr = {}, sb = {}, cm = {}, ds = {}, ab = {}, profiles = [];
        const pj = (s, f) => { try { return s ? JSON.parse(s) : f; } catch { return f; } };
        for (const r of profRes.results || []) {
          for (const [k, v] of Object.entries(pj(r.hourly_rhythm_json, {}))) hr[k] = (hr[k] || 0) + Number(v || 0);
          for (const [k, v] of Object.entries(pj(r.scheme_breakdown_json, {}))) sb[k] = (sb[k] || 0) + Number(v || 0);
          for (const [k, v] of Object.entries(pj(r.confusion_matrix_json, {}))) cm[k] = (cm[k] || 0) + Number(v || 0);
          for (const [k, v] of Object.entries(pj(r.domain_affinity_json, {}).domainScores || {})) ds[k] = (ds[k] || 0) + Number(v || 0);
          for (const [k, v] of Object.entries(pj(r.ai_feature_breakdown_json, {}))) {
            if (!ab[k]) ab[k] = { calls: 0, avgLatencyMs: 0 };
            ab[k].calls += v.calls || 0;
            ab[k].avgLatencyMs = v.avgLatencyMs || 0;
          }
          profiles.push({
            userID: r.user_id,
            username: r.username || "灵犀用户",
            email: r.email || "",
            primaryScheme: r.primary_scheme || "quanpin",
            primaryLayout: r.primary_layout || "qwerty26",
            avgCPM: r.avg_cpm || 0,
            peakCPM: r.peak_cpm || 0,
            avgWordLength: r.avg_word_length || 0,
            backspaceRate: r.backspace_rate || 0,
            undoLearnRate: r.undo_learn_rate || 0,
            glideRatio: r.glide_ratio || 0,
            habitTags: pj(r.habit_tags_json, ["灵犀云端用户"]),
            tuningRecommendations: pj(r.tuning_recommendations_json, [])
          });
        }

        return jres({
          version: VERSION,
          lanURL: url.origin,
          dashboardURL: url.origin + "/dashboard",
          stats,
          syncNamespaces: nsRes.results || [],
          devices: devRes.results || [],
          aggregate: { hourlyRhythm: hr, schemeBreakdown: sb, confusionMatrix: cm, domainScores: ds, aiBreakdown: ab },
          profiles,
          communityPacks: packs,
          b2bClients: b2bRes.results || [],
          consentLogs: (conRes.results || []).map((c) => ({ ...c, granted: Boolean(c.granted) })),
          b2bAuditLogs: audRes.results || []
        });
      }

      // 2. Personal Account Portal (Web + App Shared Profile)
      if (m === "GET" && path === "/api/v1/me") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录灵犀账号");
        const syncRes = await env.DB.prepare(
          "SELECT namespace, record_key AS key, lamport_ts AS lamportTS, device_id AS deviceID, LENGTH(ciphertext_b64) AS byteSize, updated_at AS updatedAt FROM sync_records WHERE user_id=? AND tombstone=0 ORDER BY updated_at DESC LIMIT 50"
        ).bind(a.user.id).all();
        const devRes = await env.DB.prepare(
          "SELECT id, name, platform, app_ver AS appVer, last_seen AS lastSeen FROM devices WHERE user_id=? ORDER BY last_seen DESC"
        ).bind(a.user.id).all();
        return jres({
          user: {
            userID: a.user.id,
            email: a.user.email || "",
            username: a.user.username || "灵犀用户",
            apiKeyPrefix: a.user.api_key_prefix || "",
            e2eeSalt: a.user.e2ee_salt || "",
            analyticsOptIn: Boolean(a.user.analytics_opt_in)
          },
          syncRecords: syncRes.results || [],
          devices: devRes.results || []
        });
      }

      if (m === "PATCH" && path === "/api/v1/me") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        const b = await rjson(request);
        const uname = String(b.username || "").trim();
        if (!uname) return eres(400, "BAD_REQUEST", "昵称不能为空");
        await env.DB.prepare("UPDATE users SET username=?, updated_at=? WHERE id=?").bind(uname, nowSec(), a.user.id).run();
        return jres({ ok: true, username: uname });
      }

      // 3. Community Lexicon Packs (M4)
      if (m === "GET" && (path === "/api/v1/community/packs" || path === "/api/v1/community/lexicons")) {
        return jres({ packs: await listPacks(env) });
      }
      if (m === "POST" && path === "/api/v1/community/packs") {
        const b = await rjson(request);
        if (!b.name?.trim() || !b.tsv?.trim()) return eres(400, "BAD_REQUEST", "词包名称与 TSV 不能为空");
        const id = "pack_" + randHex(6);
        await env.DB.prepare(
          "INSERT INTO community_lexicons (id,name,category,author,version,description,tsv,created_at) VALUES (?,?,?,?,'1.0.0',?,?,?)"
        ).bind(id, b.name.trim(), b.category || "社区共创", b.author || "Community", b.description || "", b.tsv.trim(), nowSec()).run();
        return jres({ ok: true, id }, 201);
      }
      if (m === "DELETE" && path.startsWith("/api/v1/community/packs/")) {
        const packId = decodeURIComponent(path.slice("/api/v1/community/packs/".length));
        await env.DB.prepare("DELETE FROM community_lexicons WHERE id=?").bind(packId).run();
        return jres({ ok: true, deleted: packId });
      }

      // 4. Auth Endpoints (含真 Apple iCloud 通行密钥 WebAuthn Passkey + 原生 Face ID 硬件公钥签名登录)
      if (m === "GET" && path === "/auth/apple-passkey") {
        const devId = (url.searchParams.get("deviceID") || "ios-passkey").slice(0, 64);
        return new Response(renderApplePasskeyHTML(url.hostname, devId), {
          status: 200,
          headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" }
        });
      }

      if (m === "POST" && path === "/api/v1/auth/passkey/challenge") {
        await ensurePasskeyTables(env);
        const now = nowSec();
        await env.DB.prepare("DELETE FROM passkey_challenges WHERE expires_at < ?").bind(now).run();
        const cid = crypto.randomUUID();
        const chBytes = new Uint8Array(32);
        crypto.getRandomValues(chBytes);
        const challenge = b64uEnc(chBytes);
        const uhBytes = new Uint8Array(16);
        crypto.getRandomValues(uhBytes);
        await env.DB.prepare("INSERT INTO passkey_challenges (id, challenge, expires_at) VALUES (?, ?, ?)").bind(cid, challenge, now + 300).run();
        return jres({ challengeID: cid, challenge, userHandle: b64uEnc(uhBytes) });
      }

      if (m === "POST" && path === "/api/v1/auth/passkey/register") {
        await ensurePasskeyTables(env);
        const b = await rjson(request);
        const chRow = await env.DB.prepare("SELECT * FROM passkey_challenges WHERE id = ? AND expires_at >= ?").bind(String(b.challengeID || ""), nowSec()).first();
        if (!chRow) return eres(400, "EXPIRED_CHALLENGE", "认证已过期，请重试");
        await env.DB.prepare("DELETE FROM passkey_challenges WHERE id = ?").bind(chRow.id).run();
        const credId = String(b.credentialID || "").trim();
        const pubSpki = String(b.publicKeySPKI || "").trim();
        if (!credId || !pubSpki) return eres(400, "BAD_REQUEST", "缺少通行密钥公钥凭证");

        const now = nowSec(), uid = crypto.randomUUID(), rawKey = `lx_live_${randHex(20)}`, salt = randHex(32);
        const uname = String(b.username || "Apple 用户").trim() || "Apple 用户";
        const pseudoEmail = `apple_${randHex(5)}@icloud.lingxi.ime`;
        await env.DB.prepare(
          "INSERT INTO users (id,email,username,password_hash,api_key_hash,api_key_prefix,e2ee_salt,analytics_opt_in,opt_in_at,created_at,updated_at,last_login_at) VALUES (?,?,?,?,?,?,?,1,?,?,?,?)"
        ).bind(uid, pseudoEmail, uname, await hashPw(randHex(16)), await sha256(rawKey), rawKey.slice(0, 14) + "...", salt, now, now, now, now).run();
        await env.DB.prepare(
          "INSERT OR REPLACE INTO passkey_credentials (cred_id, user_id, public_key_spki_b64, label, created_at) VALUES (?, ?, ?, ?, ?)"
        ).bind(credId, uid, pubSpki, "Apple iCloud Passkey", now).run();

        const u = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(uid).first();
        const sessionObj = await issueSession(env, u, String(b.deviceID || "ios-passkey"), rawKey);
        const callbackPayload = b64uEnc(enc.encode(JSON.stringify(sessionObj)));
        return jres({ ...sessionObj, callbackPayload }, 201);
      }

      if (m === "POST" && path === "/api/v1/auth/passkey/verify") {
        await ensurePasskeyTables(env);
        const b = await rjson(request);
        const chRow = await env.DB.prepare("SELECT * FROM passkey_challenges WHERE id = ? AND expires_at >= ?").bind(String(b.challengeID || ""), nowSec()).first();
        if (!chRow) return eres(400, "EXPIRED_CHALLENGE", "认证挑战已过期，请重新刷面容 ID");
        await env.DB.prepare("DELETE FROM passkey_challenges WHERE id = ?").bind(chRow.id).run();

        const credRow = await env.DB.prepare("SELECT * FROM passkey_credentials WHERE cred_id = ?").bind(String(b.credentialID || "")).first();
        if (!credRow) return eres(404, "PASSKEY_NOT_FOUND", "云端未找到该通行密钥，请先点下方「首次使用创建通行密钥」");

        const clientDataBytes = b64uDec(String(b.clientDataJSON || ""));
        const clientData = JSON.parse(dec.decode(clientDataBytes));
        if (clientData.challenge !== chRow.challenge) return eres(401, "CHALLENGE_MISMATCH", "挑战校验失败");

        const authData = b64uDec(String(b.authenticatorData || ""));
        const sigRaw = derToP1363(b64uDec(String(b.signature || "")));
        const clientHash = new Uint8Array(await crypto.subtle.digest("SHA-256", clientDataBytes));
        const signed = new Uint8Array(authData.length + clientHash.length);
        signed.set(authData, 0);
        signed.set(clientHash, authData.length);

        const pubKey = await crypto.subtle.importKey(
          "spki",
          b64uDec(credRow.public_key_spki_b64),
          { name: "ECDSA", namedCurve: "P-256" },
          false,
          ["verify"]
        );
        const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pubKey, sigRaw, signed);
        if (!valid) return eres(401, "INVALID_SIGNATURE", "Apple 通行密钥验签失败");

        const u = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(credRow.user_id).first();
        if (!u) return eres(404, "USER_NOT_FOUND", "对应账号不存在");
        await env.DB.prepare("UPDATE users SET last_login_at = ? WHERE id = ?").bind(nowSec(), u.id).run();
        const sessionObj = await issueSession(env, u, String(b.deviceID || "ios-passkey"));
        const callbackPayload = b64uEnc(enc.encode(JSON.stringify(sessionObj)));
        return jres({ ...sessionObj, callbackPayload });
      }

      if (m === "POST" && path === "/api/v1/auth/apple-device") {
        await ensurePasskeyTables(env);
        const b = await rjson(request);
        const hwId = String(b.hardwareID || "").trim();
        const pubB64 = String(b.publicKeyRawB64 || "").trim();
        const sigB64 = String(b.signatureB64 || "").trim();
        const ts = Number(b.timestamp || 0);
        if (!hwId || !pubB64 || !sigB64 || Math.abs(nowSec() - ts) > 3600) {
          return eres(400, "BAD_REQUEST", "Apple Face ID 硬件凭证无效或已过期");
        }
        const pubBytes = b64uDec(pubB64);
        const sigBytes = derToP1363(b64uDec(sigB64));
        const msgBytes = enc.encode(`${hwId}|${ts}`);
        const keyFmt = pubBytes.length === 65 ? "raw" : "spki";
        const pubKey = await crypto.subtle.importKey(keyFmt, pubBytes, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
        const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pubKey, sigBytes, msgBytes);
        if (!ok) return eres(401, "INVALID_SIGNATURE", "Face ID 安全隔区硬件签名校验失败");

        const credKey = `apple_hw_${hwId}`;
        const existingCred = await env.DB.prepare("SELECT * FROM passkey_credentials WHERE cred_id = ?").bind(credKey).first();
        let u = existingCred ? await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(existingCred.user_id).first() : null;
        let rawKey = null;
        if (!u) {
          const now = nowSec(), uid = crypto.randomUUID(), salt = randHex(32);
          rawKey = `lx_live_${randHex(20)}`;
          const uname = String(b.username || "Apple 用户").trim() || "Apple 用户";
          const email = String(b.email || "").trim().toLowerCase() || `apple_${hwId.slice(0, 8)}@icloud.lingxi.ime`;
          await env.DB.prepare(
            "INSERT INTO users (id,email,username,password_hash,api_key_hash,api_key_prefix,e2ee_salt,analytics_opt_in,opt_in_at,created_at,updated_at,last_login_at) VALUES (?,?,?,?,?,?,?,1,?,?,?,?)"
          ).bind(uid, email, uname, await hashPw(randHex(16)), await sha256(rawKey), rawKey.slice(0, 14) + "...", salt, now, now, now, now).run();
          await env.DB.prepare(
            "INSERT OR REPLACE INTO passkey_credentials (cred_id, user_id, public_key_spki_b64, label, created_at) VALUES (?, ?, ?, ?, ?)"
          ).bind(credKey, uid, pubB64, "Apple Face ID Hardware Key", now).run();
          u = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(uid).first();
        } else {
          await env.DB.prepare("UPDATE users SET last_login_at = ? WHERE id = ?").bind(nowSec(), u.id).run();
        }
        return jres(await issueSession(env, u, String(b.deviceID || "ios-faceid"), rawKey));
      }

      if (m === "POST" && path === "/api/v1/auth/register") {
        const b = await rjson(request);
        const email = (b.email || "").trim().toLowerCase();
        const pw = String(b.password || "");
        const dev = (b.deviceID || "ios-default").trim();
        const uname = (b.username || "").trim() || (email.includes("@") ? email.split("@")[0] : "灵犀用户");
        if (!email || !email.includes("@")) return eres(400, "INVALID_EMAIL", "请输入有效的邮箱地址");
        if (pw.length < 6) return eres(400, "WEAK_PASSWORD", "密码长度不能少于 6 位");
        if (await env.DB.prepare("SELECT id FROM users WHERE email = ?").bind(email).first()) {
          return eres(400, "EMAIL_EXISTS", "该邮箱已注册，请直接登录");
        }
        const now = nowSec(), uid = crypto.randomUUID(), rawKey = `lx_live_${randHex(20)}`, salt = randHex(32);
        await env.DB.prepare(
          "INSERT INTO users (id,email,username,password_hash,api_key_hash,api_key_prefix,e2ee_salt,created_at,updated_at,last_login_at) VALUES (?,?,?,?,?,?,?,?,?,?)"
        ).bind(uid, email, uname, await hashPw(pw), await sha256(rawKey), rawKey.slice(0, 14) + "...", salt, now, now, now).run();
        const u = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(uid).first();
        return jres(await issueSession(env, u, dev, rawKey), 201);
      }

      if (m === "POST" && path === "/api/v1/auth/login") {
        const b = await rjson(request);
        const acc = (b.account || b.email || "").trim().toLowerCase();
        const pw = String(b.password || "");
        const dev = (b.deviceID || "ios-default").trim();
        if (!acc || !pw) return eres(400, "BAD_REQUEST", "请输入邮箱和密码");
        const u = await env.DB.prepare("SELECT * FROM users WHERE lower(email)=? OR lower(username)=? LIMIT 1").bind(acc, acc).first();
        if (!u || !(await verifyPw(pw, u.password_hash))) return eres(401, "INVALID_CREDENTIALS", "账号或密码不正确");
        await env.DB.prepare("UPDATE users SET last_login_at=? WHERE id=?").bind(nowSec(), u.id).run();
        return jres(await issueSession(env, u, dev));
      }

      if (m === "POST" && path === "/api/v1/auth/apple") {
        const b = await rjson(request), sub = String(b.user || "").trim(), dev = (b.deviceID || "ios-default").trim();
        if (!sub) return eres(400, "BAD_REQUEST", "缺少 Apple 标识");
        let u = await env.DB.prepare("SELECT * FROM users WHERE apple_sub=?").bind(sub).first();
        let rawKey = null;
        const now = nowSec();
        if (!u) {
          const uid = crypto.randomUUID();
          rawKey = `lx_live_${randHex(20)}`;
          await env.DB.prepare(
            "INSERT INTO users (id,email,username,apple_sub,api_key_hash,api_key_prefix,e2ee_salt,created_at,updated_at,last_login_at) VALUES (?,?,'灵犀用户',?,?,?,?,?,?,?)"
          ).bind(uid, `apple_${sub.slice(0, 8)}@privaterelay.lingxi.ime`, sub, await sha256(rawKey), rawKey.slice(0, 14) + "...", randHex(32), now, now, now).run();
          u = await env.DB.prepare("SELECT * FROM users WHERE id=?").bind(uid).first();
        }
        return jres(await issueSession(env, u, dev, rawKey));
      }

      if (m === "POST" && path === "/api/v1/auth/refresh") {
        const b = await rjson(request), rt = String(b.refreshToken || "").trim();
        const s = rt ? await env.DB.prepare("SELECT * FROM auth_sessions WHERE refresh_token_hash=? AND expires_at>?").bind(await sha256(rt), nowSec()).first() : null;
        if (!s) return eres(401, "INVALID_REFRESH", "会话已过期，请重新登录");
        const u = await env.DB.prepare("SELECT * FROM users WHERE id=?").bind(s.user_id).first();
        await env.DB.prepare("DELETE FROM auth_sessions WHERE token_id=?").bind(s.token_id).run();
        return jres(await issueSession(env, u, s.device_id));
      }

      if (m === "POST" && path === "/api/v1/auth/api-key/rotate") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        const rawKey = `lx_live_${randHex(20)}`, pre = rawKey.slice(0, 14) + "...";
        await env.DB.prepare("UPDATE users SET api_key_hash=?, api_key_prefix=?, updated_at=? WHERE id=?").bind(await sha256(rawKey), pre, nowSec(), a.user.id).run();
        return jres({ apiKey: rawKey, apiKeyPrefix: pre });
      }

      if (m === "POST" && path === "/api/v1/auth/password/change") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        const b = await rjson(request), np = String(b.newPassword || "");
        if (np.length < 6) return eres(400, "WEAK_PASSWORD", "新密码至少 6 位");
        const ns = b.rotateE2EESalt ? randHex(32) : a.user.e2ee_salt;
        await env.DB.prepare("UPDATE users SET password_hash=?, e2ee_salt=?, updated_at=? WHERE id=?").bind(await hashPw(np), ns, nowSec(), a.user.id).run();
        return jres({ ok: true, e2eeSalt: ns });
      }

      // 5. E2EE Sync
      if (m === "GET" && path === "/api/v1/sync/pull") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        const ns = (url.searchParams.get("namespace") || "settings").trim();
        const since = parseInt(url.searchParams.get("since") || "0", 10) || 0;
        const lim = Math.min(200, Math.max(1, parseInt(url.searchParams.get("limit") || "100", 10) || 100));
        const rows = (await env.DB.prepare("SELECT namespace,record_key,ciphertext_b64,lamport_ts,device_id,tombstone,schema_version,server_seq FROM sync_records WHERE user_id=? AND namespace=? AND server_seq>? ORDER BY server_seq ASC LIMIT ?").bind(a.user.id, ns, since, lim + 1).all()).results || [];
        const hasMore = rows.length > lim, page = hasMore ? rows.slice(0, lim) : rows;
        return jres({
          changes: page.map((r) => ({ namespace: r.namespace, key: r.record_key, ciphertext: r.ciphertext_b64, lamportTS: r.lamport_ts, deviceID: r.device_id, tombstone: Boolean(r.tombstone), schemaVersion: r.schema_version })),
          nextCursor: page.length ? page[page.length - 1].server_seq : since,
          hasMore
        });
      }

      if (m === "POST" && path === "/api/v1/sync/push") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        const b = await rjson(request), changes = Array.isArray(b.changes) ? b.changes : [], now = nowSec(), conflicts = [];
        let seq = ((await env.DB.prepare("SELECT COALESCE(MAX(server_seq),0) AS m FROM sync_records WHERE user_id=?").bind(a.user.id).first())?.m || 0) + 1;
        for (const c of changes) {
          const ns = String(c.namespace || "settings"), k = String(c.key || "");
          if (!k) continue;
          const lt = Number(c.lamportTS || 0), dev = String(c.deviceID || a.deviceId), ct = String(c.ciphertext || ""), tb = c.tombstone ? 1 : 0, sv = Number(c.schemaVersion || 1);
          const cur = await env.DB.prepare("SELECT * FROM sync_records WHERE user_id=? AND namespace=? AND record_key=?").bind(a.user.id, ns, k).first();
          if (cur && (cur.lamport_ts > lt || (cur.lamport_ts === lt && cur.device_id > dev))) {
            conflicts.push({ namespace: ns, key: k, serverRecord: { namespace: cur.namespace, key: cur.record_key, ciphertext: cur.ciphertext_b64, lamportTS: cur.lamport_ts, deviceID: cur.device_id, tombstone: Boolean(cur.tombstone), schemaVersion: cur.schema_version } });
            continue;
          }
          await env.DB.prepare("INSERT INTO sync_records (user_id,namespace,record_key,ciphertext_b64,lamport_ts,device_id,tombstone,schema_version,server_seq,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(user_id,namespace,record_key) DO UPDATE SET ciphertext_b64=excluded.ciphertext_b64,lamport_ts=excluded.lamport_ts,device_id=excluded.device_id,tombstone=excluded.tombstone,schema_version=excluded.schema_version,server_seq=excluded.server_seq,updated_at=excluded.updated_at")
            .bind(a.user.id, ns, k, ct, lt, dev, tb, sv, seq++, now).run();
        }
        return jres({ accepted: changes.length - conflicts.length, conflicts });
      }

      // 6. Analytics & Self-Learning
      if (m === "POST" && path === "/api/v1/analytics/typing-events") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        const b = await rjson(request);
        const evs = Array.isArray(b.events) ? b.events : (Array.isArray(b.digests) ? b.digests : []);
        const now = nowSec();
        for (const e of evs) {
          await env.DB.prepare("INSERT INTO typing_habit_events (user_id,device_id,started_at,duration_seconds,committed_chars,committed_words,delete_count,undo_learn_count,glide_words,typo_corrected_count,ai_invocations,translate_chars,scheme_id,layout_id,active_hour,confusion_json,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
            .bind(a.user.id, String(e.deviceID || a.deviceId), Number(e.startedAt || now), Math.max(1, Number(e.durationSeconds || 1)), Number(e.committedChars || 0), Number(e.committedWords || 0), Number(e.deleteCount || 0), Number(e.undoLearnCount || 0), Number(e.glideWords || 0), Number(e.typoCorrectedCount || 0), Number(e.aiInvocations || 0), Number(e.translateChars || 0), String(e.schemeID || "quanpin"), String(e.layoutID || "qwerty26"), Number(e.activeHour ?? 12), JSON.stringify(e.confusionCounts || {}), now).run();
        }
        return jres({ ok: true, ingested: evs.length, profile: await recomputeProfile(env, a.user.id) });
      }

      if (m === "POST" && path === "/api/v1/analytics/api-usage") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        const b = await rjson(request), logs = Array.isArray(b.logs) ? b.logs : [b], now = nowSec();
        for (const l of logs) {
          if (!l || !l.feature) continue;
          await env.DB.prepare("INSERT INTO ai_api_usage_logs (user_id,feature,provider,target_lang,formal_tone,input_chars,output_chars,latency_ms,created_at) VALUES (?,?,?,?,?,?,?,?,?)")
            .bind(a.user.id, String(l.feature), String(l.provider || "gemini"), String(l.targetLang || "英文"), l.formalTone ? 1 : 0, Number(l.inputChars || 0), Number(l.outputChars || 0), Number(l.latencyMs || 0), Number(l.createdAt || now)).run();
        }
        return jres({ ok: true, profile: await recomputeProfile(env, a.user.id) });
      }

      if (m === "POST" && path === "/api/v1/analytics/lexicon-habits") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        const b = await rjson(request);
        let daObj = b;
        if (Array.isArray(b.words)) {
          const domKeywords = {
            "科技与研发": ["代码", "接口", "部署", "服务器", "数据库", "算法", "模型", "前端", "后端", "架构", "测试", "编译", "函数", "并发", "灵犀"],
            "商务与职场": ["收到", "会议", "汇报", "方案", "进度", "合作", "排期", "辛苦", "确认", "合同", "客户", "需求", "复盘", "对齐"],
            "日常与社交": ["哈哈", "吃饭", "开心", "下班", "火锅", "奶茶", "周末", "晚安", "摸鱼", "快递", "朋友", "明天", "休息"],
            "学术与创作": ["研究", "分析", "论文", "文献", "逻辑", "结构", "实验", "论证", "摘要", "引用", "叙事", "章节"]
          };
          const cleaned = b.words.map((w) => String(w || "").trim()).filter(Boolean);
          const scores = {};
          for (const w of cleaned) {
            for (const [dom, kws] of Object.entries(domKeywords)) {
              if (kws.some((k) => w.includes(k))) scores[dom] = (scores[dom] || 0) + 1;
            }
          }
          const primary = Object.entries(scores).sort((x, y) => y[1] - x[1])[0]?.[0] || "综合通用";
          const avgLen = cleaned.length ? Number((cleaned.reduce((s, w) => s + w.length, 0) / cleaned.length).toFixed(2)) : 0;
          daObj = {
            primaryDomain: primary,
            domainScores: scores,
            analyzedWordCount: cleaned.length,
            avgLexiconWordLength: avgLen,
            preferredTone: String(b.preferredTone || "自然流畅"),
            topTerms: cleaned.slice(0, 12)
          };
        }
        await recomputeProfile(env, a.user.id);
        await env.DB.prepare("UPDATE user_typing_profiles SET domain_affinity_json=?, updated_at=? WHERE user_id=?").bind(JSON.stringify(daObj), nowSec(), a.user.id).run();
        return jres({ ok: true, profile: await recomputeProfile(env, a.user.id) });
      }

      if (m === "GET" && path === "/api/v1/analytics/habits") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        const prof = await recomputeProfile(env, a.user.id);
        return jres({ ...prof, profile: prof });
      }

      if (m === "DELETE" && path === "/api/v1/analytics/habits") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        await env.DB.prepare("DELETE FROM typing_habit_events WHERE user_id=?").bind(a.user.id).run();
        await env.DB.prepare("DELETE FROM ai_api_usage_logs WHERE user_id=?").bind(a.user.id).run();
        await env.DB.prepare("DELETE FROM user_typing_profiles WHERE user_id=?").bind(a.user.id).run();
        return jres({ ok: true, profile: await recomputeProfile(env, a.user.id) });
      }

      // 7. Cross-Device Clipboard Relay
      if (m === "POST" && path === "/api/v1/relay/clipboard") {
        const b = await rjson(request), pc = String(b.pairCode || "").trim(), txt = String(b.contentText || "").trim();
        if (!pc || !txt) return eres(400, "BAD_REQUEST", "匹配码和内容不能为空");
        const now = nowSec(), otp = extractOTP(txt), cat = otp ? "code" : (/^https?:\/\//i.test(txt) ? "url" : "text");
        await env.DB.prepare("DELETE FROM clipboard_relays WHERE expires_at < ?").bind(now).run();
        const ins = await env.DB.prepare("INSERT INTO clipboard_relays (pair_code,content_text,category,extracted_code,sender_device,created_at,expires_at) VALUES (?,?,?,?,?,?,?)")
          .bind(pc, txt, cat, otp, String(b.senderDevice || "Web/iPhone"), now, now + 600).run();
        return jres({ ok: true, id: ins.meta?.last_row_id || 0, pairCode: pc, category: cat, extractedCode: otp }, 201);
      }

      if (m === "GET" && path === "/api/v1/relay/clipboard") {
        const c = (url.searchParams.get("code") || "").trim();
        if (!c) return jres({ items: [] });
        const rows = (await env.DB.prepare("SELECT id,pair_code AS pairCode,content_text AS contentText,category,extracted_code AS extractedCode,sender_device AS senderDevice,created_at AS createdAt FROM clipboard_relays WHERE pair_code=? AND expires_at>=? ORDER BY id DESC LIMIT 15").bind(c, nowSec()).all()).results || [];
        return jres({ items: rows });
      }

      if (m === "GET" && path === "/api/v1/relay/stream") {
        const c = (url.searchParams.get("code") || "").trim();
        const rows = c ? ((await env.DB.prepare("SELECT id,pair_code AS pairCode,content_text AS contentText,category,extracted_code AS extractedCode,sender_device AS senderDevice,created_at AS createdAt FROM clipboard_relays WHERE pair_code=? AND expires_at>=? ORDER BY id DESC LIMIT 5").bind(c, nowSec()).all()).results || []) : [];
        return new Response(`retry: 3000\ndata: ${JSON.stringify({ items: rows })}\n\n`, {
          status: 200,
          headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-cache", ...CORS }
        });
      }

      // 8. Compliance & B2B
      if (m === "POST" && path === "/api/v1/compliance/consent") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        const b = await rjson(request), sc = String(b.scope || "typing_analytics"), gr = b.granted ? 1 : 0, now = nowSec();
        await env.DB.prepare("INSERT INTO consent_records (id,user_id,scope,granted,at,ip,policy_version) VALUES (?,?,?,?,?,?,?)").bind(crypto.randomUUID(), a.user.id, sc, gr, now, ip, String(b.policyVersion || "2026.11-v1")).run();
        if (sc === "typing_analytics") await env.DB.prepare("UPDATE users SET analytics_opt_in=?, opt_in_at=? WHERE id=?").bind(gr, gr ? now : 0, a.user.id).run();
        return jres({ ok: true, scope: sc, granted: Boolean(gr) });
      }

      if (m === "DELETE" && path === "/api/v1/compliance/account") {
        const a = await resolveAuth(request, env);
        if (!a) return eres(401, "UNAUTHORIZED", "请先登录");
        const u = a.user.id;
        await ensurePasskeyTables(env);
        for (const t of ["auth_sessions", "passkey_credentials", "sync_records", "sync_state", "typing_habit_events", "ai_api_usage_logs", "user_typing_profiles", "consent_records", "devices"]) {
          await env.DB.prepare("DELETE FROM " + t + " WHERE user_id=?").bind(u).run();
        }
        await env.DB.prepare("DELETE FROM users WHERE id=?").bind(u).run();
        return jres({ ok: true, deletedUserID: u });
      }

      if (m === "POST" && path === "/api/v1/b2b/clients") {
        const b = await rjson(request), org = String(b.org || "灵犀企业客户").trim(), scopes = String(b.scopes || "profile:read,aggregate:read");
        const sk = `lxb_live_${randHex(18)}`, pre = sk.slice(0, 14) + "...", id = crypto.randomUUID();
        await env.DB.prepare("INSERT INTO api_clients (id,org,key_hash,key_prefix,scopes,created_at) VALUES (?,?,?,?,?,?)").bind(id, org, await sha256(sk), pre, scopes, nowSec()).run();
        return jres({ id, org, serviceKey: sk, keyPrefix: pre, scopes }, 201);
      }

      if (m === "POST" && path === "/api/v1/b2b/simulate-query") {
        const b = await rjson(request), cid = String(b.clientID || "");
        const cli = await env.DB.prepare("SELECT * FROM api_clients WHERE id=?").bind(cid).first();
        if (!cli) return eres(404, "NOT_FOUND", "企业客户不存在");
        await env.DB.prepare("UPDATE api_clients SET call_count=call_count+1, billable_units=billable_units+1 WHERE id=?").bind(cid).run();
        await env.DB.prepare("INSERT INTO b2b_audit_logs (client_id,org,endpoint,target_user_id,scope_used,ip,status_code,created_at) VALUES (?,?,'/api/v1/b2b/aggregate','aggregate','aggregate:read',?,200,?)").bind(cid, cli.org, ip, nowSec()).run();
        return jres({ ok: true });
      }

      if (m === "POST" && path === "/api/v1/dashboard/seed-demo") {
        const now = nowSec();
        let d = await env.DB.prepare("SELECT * FROM users WHERE email='demo@lingxi.ime'").first();
        if (!d) {
          const uid = crypto.randomUUID(), rk = `lx_live_${randHex(16)}`;
          await env.DB.prepare("INSERT INTO users (id,email,username,password_hash,api_key_hash,api_key_prefix,e2ee_salt,analytics_opt_in,opt_in_at,created_at,updated_at,last_login_at) VALUES (?,'demo@lingxi.ime','灵犀体验官',?,?,?,?,1,?,?,?,?)")
            .bind(uid, await hashPw("lingxi2026"), await sha256(rk), rk.slice(0, 14) + "...", randHex(32), now, now, now, now).run();
          d = await env.DB.prepare("SELECT * FROM users WHERE id=?").bind(uid).first();
        }
        await env.DB.prepare("INSERT INTO devices (id,user_id,name,platform,app_ver,last_seen) VALUES ('iphone-16-pro',?,'iPhone 16 Pro','iOS',?,?) ON CONFLICT(user_id,id) DO UPDATE SET last_seen=excluded.last_seen").bind(d.id, VERSION, now).run();
        const nsSeed = [["lexicon", "user_lexicon", 12], ["settings", "lingxi_settings.json", 8], ["theme", "lingxi_theme.json", 5], ["phrases", "custom_words.json", 4]];
        for (let i = 0; i < nsSeed.length; i++) {
          const [ns, k, lt] = nsSeed[i];
          await env.DB.prepare("INSERT INTO sync_records (user_id,namespace,record_key,ciphertext_b64,lamport_ts,device_id,tombstone,schema_version,server_seq,updated_at) VALUES (?,?,?,'TFhFMV9ERU1PX0NJUEhFUg==',?,'iphone-16-pro',0,1,?,?) ON CONFLICT(user_id,namespace,record_key) DO UPDATE SET lamport_ts=excluded.lamport_ts,updated_at=excluded.updated_at")
            .bind(d.id, ns, k, lt, i + 1, now).run();
        }
        const hours = [9, 11, 14, 16, 20, 22];
        for (const h of hours) {
          await env.DB.prepare("INSERT INTO typing_habit_events (user_id,device_id,started_at,duration_seconds,committed_chars,committed_words,delete_count,glide_words,scheme_id,layout_id,active_hour,confusion_json,created_at) VALUES (?,'iphone-16-pro',?,42,68,26,3,7,'quanpin','qwerty26',?,?,?)")
            .bind(d.id, now - h * 60, h, JSON.stringify({ zh_z: 2, an_ang: 3, in_ing: 2, n_l: 1 }), now).run();
        }
        await env.DB.prepare("INSERT INTO ai_api_usage_logs (user_id,feature,provider,target_lang,formal_tone,input_chars,output_chars,latency_ms,created_at) VALUES (?,'polish','gemini','英文',0,42,64,420,?)").bind(d.id, now).run();
        await env.DB.prepare("INSERT INTO ai_api_usage_logs (user_id,feature,provider,target_lang,formal_tone,input_chars,output_chars,latency_ms,created_at) VALUES (?,'live_translate','gemini','英文',1,28,51,380,?)").bind(d.id, now).run();
        await env.DB.prepare("INSERT INTO consent_records (id,user_id,scope,granted,at,ip,policy_version) VALUES (?,?,'typing_analytics',1,?,?,?)").bind(crypto.randomUUID(), d.id, now, ip, "2026.11-v1").run();
        await recomputeProfile(env, d.id);
        await env.DB.prepare("UPDATE user_typing_profiles SET domain_affinity_json=? WHERE user_id=?").bind(JSON.stringify({ primaryDomain: "科技与研发", domainScores: { "科技与研发": 42, "商务与职场": 26, "日常与社交": 18, "学术与创作": 9 }, analyzedWordCount: 95, avgLexiconWordLength: 2.8, preferredTone: "清晰干练", topTerms: ["大模型", "Cloudflare", "SwiftUI", "端到端加密"] }), d.id).run();
        await recomputeProfile(env, d.id);
        return jres({ ok: true });
      }

      return eres(404, "NOT_FOUND", `未找到接口: ${m} ${path}`);
    } catch (err) {
      if (err && err.status && err.code) return eres(err.status, err.code, err.message);
      return eres(500, "INTERNAL_ERROR", (err && err.message) || "服务端内部错误");
    }
  }
};
