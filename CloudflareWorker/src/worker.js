const DASHBOARD_HTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>灵犀输入法 · Cloudflare 云端控制台</title>
<style>
:root{--bg:#F2F3F5;--card:#FFF;--surf:#F7F8FA;--line:#E5E7EB;--ink:#0A0A0A;--mut:#6E6E73;--ok:#17976A;--r:16px}
[data-theme="dark"]{--bg:#000;--card:#1C1C1E;--surf:#2C2C2E;--line:#3A3A3C;--ink:#F2F2F7;--mut:#98989D;--ok:#34C77B}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC",sans-serif;background:var(--bg);color:var(--ink);padding-bottom:48px}
.top{position:sticky;top:0;z-index:20;background:var(--card);border-bottom:1px solid var(--line);padding:14px 20px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px}
.brand{display:flex;align-items:center;gap:10px}.logo{width:34px;height:34px;border-radius:10px;background:var(--ink);color:var(--card);display:grid;place-items:center;font-weight:700}
.acts{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.btn,.pill{font-size:12px;font-weight:600;padding:7px 14px;border-radius:999px;border:1px solid var(--line);background:var(--card);color:var(--ink);cursor:pointer}
.btn-p{background:var(--ink);color:var(--card);border-color:var(--ink)}
.dot{width:7px;height:7px;border-radius:50%;background:var(--ok);display:inline-block;margin-right:5px}
.wrap{max-width:1200px;margin:20px auto 0;padding:0 16px;display:flex;flex-direction:column;gap:18px}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(175px,1fr));gap:12px}
.g2{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:16px}
.card{background:var(--card);border:1px solid var(--line);border-radius:var(--r);padding:18px}
.k-l{font-size:12px;color:var(--mut)}.k-v{font-size:26px;font-weight:700;margin-top:4px;font-variant-numeric:tabular-nums}
.ch{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:12px;flex-wrap:wrap}
.ct{font-size:15px;font-weight:700}.row{display:flex;gap:8px;margin-bottom:10px;flex-wrap:wrap}
.in{flex:1;min-width:140px;padding:8px 12px;border-radius:10px;border:1px solid var(--line);background:var(--surf);color:var(--ink);font-size:13px}
.feed{display:flex;flex-direction:column;gap:8px;max-height:220px;overflow:auto}
.fi{padding:10px 12px;border-radius:10px;background:var(--surf);border:1px solid var(--line);display:flex;justify-content:space-between;gap:10px;align-items:center;font-size:13px}
.bars{display:flex;align-items:flex-end;gap:4px;height:110px;padding:10px 6px 4px;background:var(--surf);border-radius:10px;border:1px solid var(--line)}
.bc{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;height:100%;gap:3px}
.bf{width:100%;background:var(--ink);border-radius:3px 3px 0 0;min-height:3px}.bl{font-size:9px;color:var(--mut)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:8px}
.cell{padding:10px;border-radius:10px;background:var(--surf);border:1px solid var(--line);font-size:12px}
table{width:100%;border-collapse:collapse;font-size:12.5px}th,td{text-align:left;padding:9px 8px;border-bottom:1px solid var(--line)}th{color:var(--mut)}
.tag{display:inline-block;font-size:11px;font-weight:600;padding:2px 8px;border-radius:999px;background:var(--surf);border:1px solid var(--line);margin:2px}
.toast{position:fixed;bottom:20px;right:20px;background:var(--ink);color:var(--card);padding:10px 16px;border-radius:999px;font-size:12px;font-weight:600;opacity:0;transition:opacity .18s}
.toast.show{opacity:1}
</style>
</head>
<body>
<header class="top">
  <div class="brand"><div class="logo">灵</div><div><div style="font-weight:700;font-size:16px">灵犀输入法 · Cloudflare 永久云端控制台</div><div style="font-size:12px;color:var(--mut)">D1 持久化数据库 · E2EE 零知识同步 · 自学习词库 · 跨屏剪贴板</div></div></div>
  <div class="acts">
    <span class="pill"><span class="dot"></span><span id="st">在线 v4.1.0</span></span>
    <button class="btn" id="url-btn" onclick="copyUrl()">📱 复制云端接入地址</button>
    <button class="btn" onclick="seed()">✨ 注入演示样本</button>
    <button class="btn" onclick="load()">↻ 刷新</button>
    <button class="btn" onclick="toggleTheme()">◑ 亮/暗</button>
  </div>
</header>
<main class="wrap">
  <section class="kpis">
    <div class="card"><div class="k-l">注册用户 / 已授权画像</div><div class="k-v" id="k-u">0 / 0</div></div>
    <div class="card"><div class="k-l">E2EE 同步密文块（含自学习词库）</div><div class="k-v" id="k-s">0</div></div>
    <div class="card"><div class="k-l">打字习惯会话样本</div><div class="k-v" id="k-h">0</div></div>
    <div class="card"><div class="k-l">AI / 翻译调用</div><div class="k-v" id="k-a">0</div></div>
  </section>
  <section class="g2">
    <div class="card">
      <div class="ch"><div class="ct">📋 跨设备实时剪贴板秒传（6 位匹配码）</div><span class="pill">全球 HTTPS 实时</span></div>
      <div class="row">
        <input id="code" class="in" style="max-width:130px;font-weight:700" value="886699" placeholder="6位匹配码" />
        <button class="btn" onclick="loadRelay()">拉取记录</button>
        <button class="btn" onclick="sendOTP()">💬 发模拟验证码到手机</button>
      </div>
      <div class="row">
        <input id="rtxt" class="in" placeholder="输入文字或验证码，秒传至 iPhone 键盘顶栏…" />
        <button class="btn btn-p" onclick="pushRelay()">秒传</button>
      </div>
      <div class="feed" id="feed"><div class="fi" style="color:var(--mut)">暂无记录</div></div>
    </div>
    <div class="card">
      <div class="ch"><div class="ct">🕒 24 小时打字节律 & 易混音诊断</div><span class="pill">零原文聚合</span></div>
      <div class="bars" id="bars"></div>
      <div class="grid" id="cm" style="margin-top:12px"></div>
    </div>
  </section>
  <section class="card">
    <div class="ch">
      <div class="ct">👤 已注册用户与打字习惯画像</div>
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <input id="q" class="in" style="min-width:170px" placeholder="搜索昵称 / 邮箱 / 标签…" oninput="renderProf()" />
        <button class="btn" onclick="exportJSON()">📥 导出 JSON</button>
      </div>
    </div>
    <div style="overflow-x:auto">
      <table><thead><tr><th>用户 / 邮箱</th><th>主方案</th><th>平均/峰值 CPM</th><th>平均词长</th><th>退格/滑行</th><th>画像标签</th></tr></thead><tbody id="tb"></tbody></table>
    </div>
  </section>
</main>
<div id="toast" class="toast"></div>
<script>
let ov=null;
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function toast(m){const e=document.getElementById('toast');e.textContent=m;e.classList.add('show');setTimeout(()=>e.classList.remove('show'),2400)}
function toggleTheme(){document.documentElement.setAttribute('data-theme',document.documentElement.getAttribute('data-theme')==='dark'?'light':'dark')}
function copyUrl(){const u=location.origin;navigator.clipboard?.writeText(u);toast('已复制接入地址：'+u)}
async function api(m,p,b){const r=await fetch(p,{method:m,headers:{'Content-Type':'application/json'},body:b?JSON.stringify(b):undefined});return r.json()}
async function load(){
  ov=await api('GET','/api/v1/dashboard/overview');
  document.getElementById('url-btn').textContent='📱 '+location.origin;
  document.getElementById('st').textContent='Cloudflare D1 在线 v'+(ov.version||'4.1.0');
  document.getElementById('k-u').textContent=ov.stats.users+' / '+ov.stats.optedInUsers;
  document.getElementById('k-s').textContent=ov.stats.syncRecords;
  document.getElementById('k-h').textContent=ov.stats.habitEvents;
  document.getElementById('k-a').textContent=ov.stats.aiApiLogs;
  const bars=document.getElementById('bars');bars.innerHTML='';
  const hr=ov.aggregate.hourlyRhythm||{};let mx=1;for(let i=0;i<24;i++)mx=Math.max(mx,hr[i]||0);
  for(let i=0;i<24;i++){const v=hr[i]||0;const h=Math.max(4,Math.round(v/mx*86));bars.innerHTML+='<div class="bc" title="'+i+':00 '+v+'字"><div class="bf" style="height:'+h+'%;opacity:'+(v?1:.2)+'"></div><span class="bl">'+(i%3===0?String(i).padStart(2,'0'):'')+'</span></div>'}
  const cm=ov.aggregate.confusionMatrix||{};const lbs={zh_z:'zh↔z 平翘舌',ch_c:'ch↔c 平翘舌',sh_s:'sh↔s 平翘舌',an_ang:'an↔ang 前后鼻音',en_eng:'en↔eng 前后鼻音',in_ing:'in↔ing 前后鼻音'};
  document.getElementById('cm').innerHTML=Object.entries(lbs).map(([k,t])=>'<div class="cell"><div>'+t+'</div><strong style="font-size:16px">'+(cm[k]||0)+' 次</strong></div>').join('');
  renderProf();loadRelay();
}
function renderProf(){
  const q=(document.getElementById('q').value||'').trim().toLowerCase();
  const list=(ov?.profiles||[]).filter(p=>!q||[p.username,p.email,p.primaryScheme,...(p.habitTags||[])].join(' ').toLowerCase().includes(q));
  document.getElementById('tb').innerHTML=list.length?list.map(p=>'<tr><td><strong>'+esc(p.username)+'</strong><br><span style="color:var(--mut);font-size:11px">'+esc(p.email)+'</span></td><td>'+esc(p.primaryScheme)+'/'+esc(p.primaryLayout)+'</td><td>'+p.avgCPM+' / '+p.peakCPM+'</td><td>'+p.avgWordLength+'</td><td>'+(p.backspaceRate*100).toFixed(1)+'% / '+(p.glideRatio*100).toFixed(1)+'%</td><td>'+(p.habitTags||[]).map(t=>'<span class="tag">'+esc(t)+'</span>').join('')+'</td></tr>').join(''):'<tr><td colspan="6" style="color:var(--mut)">暂无注册用户，在 iPhone 打开灵犀 App 即可直接注册！</td></tr>';
}
async function loadRelay(){
  const c=document.getElementById('code').value.trim();if(!c)return;
  const r=await api('GET','/api/v1/relay/clipboard?code='+encodeURIComponent(c));
  const f=document.getElementById('feed');f.innerHTML='';
  if(!(r.items||[]).length){f.innerHTML='<div class="fi" style="color:var(--mut)">暂无匹配码 '+esc(c)+' 的跨屏记录</div>';return}
  r.items.forEach(it=>{const d=document.createElement('div');d.className='fi';const s=document.createElement('span');s.textContent=(it.extractedCode?'[验证码 '+it.extractedCode+'] ':'')+it.contentText;const b=document.createElement('button');b.className='btn';b.textContent='复制';b.onclick=()=>{navigator.clipboard?.writeText(it.contentText);toast('已复制')};d.append(s,b);f.append(d)})
}
async function pushRelay(){const c=document.getElementById('code').value.trim(),t=document.getElementById('rtxt').value.trim();if(!c||!t)return;await api('POST','/api/v1/relay/clipboard',{pairCode:c,contentText:t,senderDevice:'Cloudflare Web'});document.getElementById('rtxt').value='';toast('已秒传至手机匹配码 '+c);loadRelay()}
async function sendOTP(){const c=document.getElementById('code').value.trim()||'886699',otp=Math.floor(100000+Math.random()*900000);await api('POST','/api/v1/relay/clipboard',{pairCode:c,contentText:'【灵犀云】您的测试验证码为 '+otp+'，5分钟内有效。',senderDevice:'Cloudflare 控制台'});toast('已发送验证码 '+otp);loadRelay()}
async function seed(){await api('POST','/api/v1/dashboard/seed-demo',{});toast('已注入演示样本');load()}
function exportJSON(){if(!ov)return;const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(ov,null,2)],{type:'application/json'}));a.download='lingxi-cf-analytics.json';a.click()}
load();
</script>
</body>
</html>`;

const VERSION = "4.1.0";
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
    description: "涵盖大模型、云原生、微服务、iOS/Swift、Python 研发高频术语与快捷短语",
    tsv: "dm\t大模型\nllm\t大语言模型\nk8s\tKubernetes\nsw\tSwiftUI\ncf\tCloudflare Workers\ngit\tGitHub Actions\napi\tRESTful API\ne2ee\t端到端零知识加密\n"
  },
  {
    id: "business_office",
    name: "职场商务与高情商沟通词包",
    category: "商务职场",
    author: "Lingxi Open Community",
    version: "1.2.0",
    description: "周报、邮件、会议纪要与高频商务礼貌用语",
    tsv: "sd\t收到，马上处理\nxk\t辛苦了，感谢支持\nhy\t会议纪要如下\njz\t进展同步一下\nqr\t麻烦确认一下\n"
  },
  {
    id: "daily_slang",
    name: "日常社交与流行表达词包",
    category: "日常社交",
    author: "Lingxi Open Community",
    version: "1.1.0",
    description: "轻松日常聊天高频词组与温暖回复",
    tsv: "wsm\t为什么呀\nzaima\t在吗方便聊两句吗\nhde\t好的没问题\nxie\t太感谢啦\n"
  }
];

// ============================================================================
// Crypto & Encoding Utilities (Web Crypto API — zero external deps)
// ============================================================================

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function bytesToHex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function hexToBytes(hex) {
  const clean = hex.trim();
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function randomHex(byteLength) {
  const arr = new Uint8Array(byteLength);
  crypto.getRandomValues(arr);
  return bytesToHex(arr);
}

function base64UrlEncode(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(str) {
  const padded = str.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((str.length + 3) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function timingSafeEqual(a, b) {
  const ab = typeof a === "string" ? encoder.encode(a) : a;
  const bb = typeof b === "string" ? encoder.encode(b) : b;
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(text));
  return bytesToHex(new Uint8Array(digest));
}

async function hashPassword(password, saltHex = randomHex(16)) {
  const key = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: hexToBytes(saltHex), iterations: PBKDF2_ITERATIONS, hash: "SHA-256" },
    key,
    256
  );
  return `pbkdf2_sha256$${PBKDF2_ITERATIONS}$${saltHex}$${bytesToHex(new Uint8Array(bits))}`;
}

async function verifyPassword(password, stored) {
  if (!stored || !stored.startsWith("pbkdf2_sha256$")) return false;
  const parts = stored.split("$");
  if (parts.length !== 4) return false;
  const iterations = parseInt(parts[1], 10);
  const saltHex = parts[2];
  const expectedHex = parts[3];
  const key = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: hexToBytes(saltHex), iterations, hash: "SHA-256" },
    key,
    256
  );
  return timingSafeEqual(bytesToHex(new Uint8Array(bits)), expectedHex);
}

async function hmacSign(data, secret) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(data));
  return base64UrlEncode(new Uint8Array(sig));
}

async function signAccessToken(userId, deviceId, secret) {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + ACCESS_TTL_SEC;
  const payload = { sub: userId, dev: deviceId, iat: now, exp };
  const body = base64UrlEncode(encoder.encode(JSON.stringify(payload)));
  const sig = await hmacSign(body, secret);
  return { token: `lxt.${body}.${sig}`, exp };
}

async function verifyAccessToken(token, secret) {
  if (!token || !token.startsWith("lxt.")) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const expectedSig = await hmacSign(parts[1], secret);
  if (!timingSafeEqual(parts[2], expectedSig)) return null;
  try {
    const payload = JSON.parse(decoder.decode(base64UrlDecode(parts[1])));
    const now = Math.floor(Date.now() / 1000);
    if (!payload.sub || (payload.exp && payload.exp < now)) return null;
    return payload;
  } catch {
    return null;
  }
}

function nowSec() {
  return Math.floor(Date.now() / 1000);
}

// ============================================================================
// HTTP Response Helpers & CORS
// ============================================================================

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-API-Key, X-Lingxi-Timestamp, X-Lingxi-Nonce, X-Lingxi-Signature"
};

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS_HEADERS }
  });
}

function errorResponse(status, code, message) {
  return jsonResponse({ error: { code, message } }, status);
}

async function readJsonBody(request) {
  const text = await request.text();
  if (!text.trim()) return {};
  try {
    return JSON.parse(text);
  } catch {
    throw { status: 400, code: "INVALID_JSON", message: "请求体不是有效的 JSON" };
  }
}

function extractOTPCode(text) {
  const trimmed = (text || "").trim();
  if (!trimmed || trimmed.length > 300) return null;
  if (/^\d{4,8}$/.test(trimmed)) return trimmed;
  const cue = /(验证码|校验码|动态码|确认码|取件码|激活码|code|otp|pin|verify)/i;
  if (!cue.test(trimmed)) return null;
  const m1 = trimmed.match(/(?:验证码|校验码|动态码|确认码|取件码|code|otp|pin)[：:\s为是]*([0-9]{4,8})/i);
  if (m1 && m1[1]) return m1[1];
  const m2 = trimmed.match(/\b([0-9]{4,8})\b/);
  if (m2 && m2[1] && !(m2[1].length === 4 && /^(19|20)/.test(m2[1]))) return m2[1];
  return null;
}

// ============================================================================
// Auth Resolution
// ============================================================================

async function resolveAuthUser(request, env) {
  const secret = env.JWT_SECRET || "lingxi-cf-default-signing-secret-v4";
  const authHeader = request.headers.get("Authorization") || "";
  if (authHeader.startsWith("Bearer ")) {
    const token = authHeader.slice(7).trim();
    const payload = await verifyAccessToken(token, secret);
    if (payload?.sub) {
      const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(payload.sub).first();
      if (user) return { user, deviceId: payload.dev || "ios-default" };
    }
  }
  const apiKey = (request.headers.get("X-API-Key") || "").trim();
  if (apiKey) {
    const hash = await sha256Hex(apiKey);
    const user = await env.DB.prepare("SELECT * FROM users WHERE api_key_hash = ?").bind(hash).first();
    if (user) return { user, deviceId: "api-key-client" };
  }
  return null;
}

async function issueSessionPayload(env, user, deviceId, rawApiKey = null) {
  const now = nowSec();
  const secret = env.JWT_SECRET || "lingxi-cf-default-signing-secret-v4";
  const { token: accessToken, exp } = await signAccessToken(user.id, deviceId, secret);
  const refreshToken = `lxr_${randomHex(24)}`;
  const refreshHash = await sha256Hex(refreshToken);
  const tokenId = crypto.randomUUID();

  await env.DB.prepare(
    `INSERT INTO auth_sessions (token_id, user_id, device_id, device_name, refresh_token_hash, expires_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).bind(tokenId, user.id, deviceId, "iOS Device", refreshHash, now + REFRESH_TTL_SEC, now).run();

  await env.DB.prepare(
    `INSERT INTO devices (id, user_id, name, platform, app_ver, last_seen)
     VALUES (?, ?, 'iPhone', 'iOS', ?, ?)
     ON CONFLICT(user_id, id) DO UPDATE SET last_seen = excluded.last_seen, app_ver = excluded.app_ver`
  ).bind(deviceId, user.id, VERSION, now).run();

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
  if (rawApiKey) out.apiKey = rawApiKey;
  return out;
}

// ============================================================================
// Typing Habit Profile Recompute Engine
// ============================================================================

async function recomputeUserHabitProfile(env, userId) {
  const now = nowSec();
  const eventsRes = await env.DB.prepare(
    "SELECT * FROM typing_habit_events WHERE user_id = ? ORDER BY started_at DESC LIMIT 500"
  ).bind(userId).all();
  const events = eventsRes.results || [];

  const aiRes = await env.DB.prepare(
    "SELECT * FROM ai_api_usage_logs WHERE user_id = ? ORDER BY created_at DESC LIMIT 300"
  ).bind(userId).all();
  const aiLogs = aiRes.results || [];

  const existing = await env.DB.prepare(
    "SELECT domain_affinity_json FROM user_typing_profiles WHERE user_id = ?"
  ).bind(userId).first();
  let domainAffinity = {
    primaryDomain: "综合通用",
    domainScores: {},
    analyzedWordCount: 0,
    avgLexiconWordLength: 0,
    preferredTone: "自然流畅",
    topTerms: []
  };
  if (existing?.domain_affinity_json) {
    try {
      domainAffinity = { ...domainAffinity, ...JSON.parse(existing.domain_affinity_json) };
    } catch {}
  }

  let totalChars = 0;
  let totalWords = 0;
  let totalDuration = 0;
  let totalDeletes = 0;
  let totalUndoLearn = 0;
  let totalGlide = 0;
  let totalTypo = 0;
  let peakCPM = 0;
  const schemeBreakdown = {};
  const layoutCounts = {};
  const hourlyRhythm = {};
  const confusionMatrix = {};

  for (const e of events) {
    const dur = Math.max(1, e.duration_seconds || 1);
    const chars = e.committed_chars || 0;
    const words = e.committed_words || 0;
    totalChars += chars;
    totalWords += words;
    totalDuration += dur;
    totalDeletes += e.delete_count || 0;
    totalUndoLearn += e.undo_learn_count || 0;
    totalGlide += e.glide_words || 0;
    totalTypo += e.typo_corrected_count || 0;

    const cpm = (chars * 60) / dur;
    if (cpm > peakCPM && cpm <= 600) peakCPM = cpm;

    const sch = e.scheme_id || "quanpin";
    schemeBreakdown[sch] = (schemeBreakdown[sch] || 0) + chars;
    const lay = e.layout_id || "qwerty26";
    layoutCounts[lay] = (layoutCounts[lay] || 0) + chars;
    const hr = String(e.active_hour ?? 12);
    hourlyRhythm[hr] = (hourlyRhythm[hr] || 0) + chars;

    if (e.confusion_json) {
      try {
        const cm = JSON.parse(e.confusion_json);
        for (const [k, v] of Object.entries(cm)) {
          confusionMatrix[k] = (confusionMatrix[k] || 0) + Number(v || 0);
        }
      } catch {}
    }
  }

  const aiFeatureBreakdown = {};
  for (const l of aiLogs) {
    const f = l.feature || "polish";
    if (!aiFeatureBreakdown[f]) {
      aiFeatureBreakdown[f] = { calls: 0, inputChars: 0, outputChars: 0, totalLat: 0 };
    }
    aiFeatureBreakdown[f].calls += 1;
    aiFeatureBreakdown[f].inputChars += l.input_chars || 0;
    aiFeatureBreakdown[f].outputChars += l.output_chars || 0;
    aiFeatureBreakdown[f].totalLat += l.latency_ms || 0;
  }
  const aiSummary = {};
  for (const [k, v] of Object.entries(aiFeatureBreakdown)) {
    aiSummary[k] = {
      calls: v.calls,
      inputChars: v.inputChars,
      outputChars: v.outputChars,
      avgLatencyMs: Math.round(v.totalLat / Math.max(1, v.calls))
    };
  }

  const avgCPM = totalDuration > 0 ? Number(((totalChars * 60) / totalDuration).toFixed(1)) : 0;
  const avgWordLength = totalWords > 0 ? Number((totalChars / totalWords).toFixed(2)) : 0;
  const backspaceRate = totalChars > 0 ? Number((totalDeletes / totalChars).toFixed(3)) : 0;
  const undoLearnRate = totalWords > 0 ? Number((totalUndoLearn / totalWords).toFixed(3)) : 0;
  const glideRatio = totalWords > 0 ? Number((totalGlide / totalWords).toFixed(3)) : 0;
  const typoCorrectionRate = totalWords > 0 ? Number((totalTypo / totalWords).toFixed(3)) : 0;

  const primaryScheme = Object.entries(schemeBreakdown).sort((a, b) => b[1] - a[1])[0]?.[0] || "quanpin";
  const primaryLayout = Object.entries(layoutCounts).sort((a, b) => b[1] - a[1])[0]?.[0] || "qwerty26";

  const habitTags = [];
  if (avgCPM >= 65) habitTags.push("高速输入达人");
  else if (totalChars > 0) habitTags.push("稳健流畅输入");
  if (glideRatio >= 0.25) habitTags.push("滑行输入爱好者");
  if (backspaceRate >= 0.14) habitTags.push("建议开启智能纠错");
  if (domainAffinity.primaryDomain && domainAffinity.primaryDomain !== "综合通用") {
    habitTags.push(domainAffinity.primaryDomain);
  }
  if (habitTags.length === 0) habitTags.push("灵犀云端同步用户");

  const recommendations = [];
  if ((confusionMatrix.zh_z || 0) >= 2) {
    recommendations.push({ id: "fuzzy_zh_z", title: "开启平翘舌模糊音 (zh↔z)", reason: "检测到高频平翘舌混淆", settingKey: "fuzzy.zhZ" });
  }
  if ((confusionMatrix.an_ang || 0) >= 2) {
    recommendations.push({ id: "fuzzy_an_ang", title: "开启前后鼻音模糊音 (an↔ang)", reason: "检测到高频前后鼻音混淆", settingKey: "fuzzy.anAng" });
  }
  if ((confusionMatrix.in_ing || 0) >= 2) {
    recommendations.push({ id: "fuzzy_in_ing", title: "开启前后鼻音模糊音 (in↔ing)", reason: "检测到高频 in/ing 混淆", settingKey: "fuzzy.inIng" });
  }
  if (backspaceRate >= 0.14) {
    recommendations.push({ id: "typo_boost", title: "保持智能纠错与动态热区开启", reason: "有助于进一步降低退格率", settingKey: "typoCorrectionEnabled" });
  }

  const profile = {
    userID: userId,
    totalChars,
    totalWords,
    totalDurationSeconds: totalDuration,
    totalSessions: events.length,
    avgCPM,
    peakCPM: Number(peakCPM.toFixed(1)),
    avgWordLength,
    backspaceRate,
    undoLearnRate,
    glideRatio,
    typoCorrectionRate,
    primaryScheme,
    primaryLayout,
    schemeBreakdown,
    hourlyRhythm,
    aiFeatureBreakdown: aiSummary,
    confusionMatrix,
    domainAffinity,
    habitTags,
    tuningRecommendations: recommendations,
    updatedAt: now
  };

  await env.DB.prepare(
    `INSERT INTO user_typing_profiles (
       user_id, total_chars, total_words, total_duration_seconds, total_sessions,
       avg_cpm, peak_cpm, avg_word_length, backspace_rate, undo_learn_rate,
       glide_ratio, typo_correction_rate, primary_scheme, primary_layout,
       scheme_breakdown_json, hourly_rhythm_json, ai_feature_breakdown_json,
       confusion_matrix_json, domain_affinity_json, habit_tags_json,
       tuning_recommendations_json, updated_at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
       updated_at = excluded.updated_at`
  ).bind(
    userId, totalChars, totalWords, totalDuration, events.length,
    avgCPM, profile.peakCPM, avgWordLength, backspaceRate, undoLearnRate,
    glideRatio, typoCorrectionRate, primaryScheme, primaryLayout,
    JSON.stringify(schemeBreakdown), JSON.stringify(hourlyRhythm), JSON.stringify(aiSummary),
    JSON.stringify(confusionMatrix), JSON.stringify(domainAffinity), JSON.stringify(habitTags),
    JSON.stringify(recommendations), now
  ).run();

  return profile;
}

// ============================================================================
// Dashboard Overview Aggregation
// ============================================================================

async function buildStats(env) {
  const [users, opted, syncRecs, habits, aiLogs, b2b] = await Promise.all([
    env.DB.prepare("SELECT COUNT(*) AS c FROM users").first(),
    env.DB.prepare("SELECT COUNT(*) AS c FROM users WHERE analytics_opt_in = 1").first(),
    env.DB.prepare("SELECT COUNT(*) AS c FROM sync_records WHERE tombstone = 0").first(),
    env.DB.prepare("SELECT COUNT(*) AS c FROM typing_habit_events").first(),
    env.DB.prepare("SELECT COUNT(*) AS c, COALESCE(AVG(latency_ms), 0) AS avg_lat FROM ai_api_usage_logs").first(),
    env.DB.prepare("SELECT COUNT(*) AS c, COALESCE(SUM(billable_units), 0) AS units FROM api_clients").first()
  ]);
  return {
    status: "ok",
    service: "lingxi-cloud-backend-cf",
    version: VERSION,
    users: users?.c || 0,
    optedInUsers: opted?.c || 0,
    syncRecords: syncRecs?.c || 0,
    habitEvents: habits?.c || 0,
    aiApiLogs: aiLogs?.c || 0,
    avgAiLatencyMs: Math.round(aiLogs?.avg_lat || 0),
    b2bClients: b2b?.c || 0,
    b2bBillableUnits: b2b?.units || 0,
    timestamp: nowSec()
  };
}

async function listAllCommunityPacks(env) {
  const custom = await env.DB.prepare("SELECT * FROM community_lexicons ORDER BY created_at DESC LIMIT 50").all();
  const rows = [...BUILTIN_PACKS, ...(custom.results || [])];
  return rows.map((p) => ({
    id: p.id,
    name: p.name,
    category: p.category,
    author: p.author,
    version: p.version,
    description: p.description || "",
    tsv: p.tsv,
    wordCount: (p.tsv || "").split(/\r?\n/).filter((ln) => ln.trim() && !ln.startsWith("#")).length
  }));
}

async function buildDashboardOverview(env, originUrl) {
  const stats = await buildStats(env);
  const profRows = await env.DB.prepare(
    `SELECT u.id AS user_id, u.username, u.email, p.*
     FROM users u
     LEFT JOIN user_typing_profiles p ON p.user_id = u.id
     ORDER BY u.last_login_at DESC LIMIT 50`
  ).all();

  const hourlyRhythm = {};
  const schemeBreakdown = {};
  const confusionMatrix = {};
  const domainScores = {};
  const aiBreakdown = {};
  const profiles = [];

  for (const r of profRows.results || []) {
    const parse = (s, fb) => { try { return s ? JSON.parse(s) : fb; } catch { return fb; } };
    const hr = parse(r.hourly_rhythm_json, {});
    const sb = parse(r.scheme_breakdown_json, {});
    const cm = parse(r.confusion_matrix_json, {});
    const da = parse(r.domain_affinity_json, {});
    const ai = parse(r.ai_feature_breakdown_json, {});

    for (const [k, v] of Object.entries(hr)) hourlyRhythm[k] = (hourlyRhythm[k] || 0) + Number(v || 0);
    for (const [k, v] of Object.entries(sb)) schemeBreakdown[k] = (schemeBreakdown[k] || 0) + Number(v || 0);
    for (const [k, v] of Object.entries(cm)) confusionMatrix[k] = (confusionMatrix[k] || 0) + Number(v || 0);
    for (const [k, v] of Object.entries(da.domainScores || {})) domainScores[k] = (domainScores[k] || 0) + Number(v || 0);
    for (const [k, v] of Object.entries(ai)) {
      if (!aiBreakdown[k]) aiBreakdown[k] = { calls: 0, avgLatencyMs: 0 };
      aiBreakdown[k].calls += v.calls || 0;
      aiBreakdown[k].avgLatencyMs = v.avgLatencyMs || 0;
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
      habitTags: parse(r.habit_tags_json, ["灵犀云端用户"]),
      tuningRecommendations: parse(r.tuning_recommendations_json, [])
    });
  }

  const [b2bClients, consentLogs, b2bAuditLogs, communityPacks] = await Promise.all([
    env.DB.prepare("SELECT id, org, key_prefix AS keyPrefix, scopes, call_count AS callCount, billable_units AS billableUnits FROM api_clients ORDER BY created_at DESC LIMIT 30").all(),
    env.DB.prepare("SELECT id, user_id AS userID, scope, granted, at, policy_version AS policyVersion FROM consent_records ORDER BY at DESC LIMIT 20").all(),
    env.DB.prepare("SELECT id, org, endpoint, scope_used AS scopeUsed, status_code AS statusCode, created_at AS createdAt FROM b2b_audit_logs ORDER BY created_at DESC LIMIT 20").all(),
    listAllCommunityPacks(env)
  ]);

  return {
    version: VERSION,
    lanURL: originUrl,
    dashboardURL: `${originUrl}/dashboard`,
    stats,
    aggregate: { hourlyRhythm, schemeBreakdown, confusionMatrix, domainScores, aiBreakdown },
    profiles,
    b2bClients: b2bClients.results || [],
    consentLogs: (consentLogs.results || []).map((c) => ({ ...c, granted: Boolean(c.granted) })),
    b2bAuditLogs: b2bAuditLogs.results || [],
    communityPacks
  };
}

// ============================================================================
// Main Worker Entrypoint
// ============================================================================

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;
    const clientIp = request.headers.get("CF-Connecting-IP") || "0.0.0.0";

    try {
      // 1. Web Dashboard & Health
      if (method === "GET" && (path === "/" || path === "/dashboard")) {
        return new Response(DASHBOARD_HTML, {
          status: 200,
          headers: { "Content-Type": "text/html; charset=utf-8", ...CORS_HEADERS }
        });
      }

      if (method === "GET" && path === "/api/v1/health") {
        return jsonResponse(await buildStats(env));
      }

      if (method === "GET" && path === "/api/v1/dashboard/overview") {
        return jsonResponse(await buildDashboardOverview(env, url.origin));
      }

      if (method === "GET" && (path === "/api/v1/community/packs" || path === "/api/v1/community/lexicons")) {
        return jsonResponse({ packs: await listAllCommunityPacks(env) });
      }

      if (method === "POST" && path === "/api/v1/community/packs") {
        const body = await readJsonBody(request);
        const name = (body.name || "").trim();
        const tsv = (body.tsv || "").trim();
        if (!name || !tsv) return errorResponse(400, "BAD_REQUEST", "词包名称与 TSV 内容不能为空");
        const id = "pack_" + randomHex(6);
        await env.DB.prepare(
          `INSERT INTO community_lexicons (id, name, category, author, version, description, tsv, created_at)
           VALUES (?, ?, ?, ?, '1.0.0', ?, ?, ?)`
        ).bind(id, name, body.category || "社区共创", body.author || "Community", body.description || "", tsv, nowSec()).run();
        return jsonResponse({ ok: true, id }, 201);
      }

      // 2. Auth Endpoints
      if (method === "POST" && path === "/api/v1/auth/register") {
        const body = await readJsonBody(request);
        const email = (body.email || "").trim().toLowerCase();
        const username = (body.username || "").trim() || (email.includes("@") ? email.split("@")[0] : "灵犀用户");
        const password = String(body.password || "");
        const deviceId = (body.deviceID || "ios-default").trim();

        if (!email || !email.includes("@")) return errorResponse(400, "INVALID_EMAIL", "请输入有效的邮箱地址");
        if (password.length < 6) return errorResponse(400, "WEAK_PASSWORD", "密码长度不能少于 6 位");

        const existing = await env.DB.prepare("SELECT id FROM users WHERE email = ?").bind(email).first();
        if (existing) return errorResponse(400, "EMAIL_EXISTS", "该邮箱已注册，请直接切换「邮箱登录」");

        const now = nowSec();
        const userId = crypto.randomUUID();
        const pwHash = await hashPassword(password);
        const rawApiKey = `lx_live_${randomHex(20)}`;
        const apiKeyHash = await sha256Hex(rawApiKey);
        const apiKeyPrefix = `${rawApiKey.slice(0, 14)}...`;
        const e2eeSalt = randomHex(32);

        await env.DB.prepare(
          `INSERT INTO users (id, email, username, password_hash, api_key_hash, api_key_prefix, e2ee_salt, created_at, updated_at, last_login_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
        ).bind(userId, email, username, pwHash, apiKeyHash, apiKeyPrefix, e2eeSalt, now, now, now).run();

        const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userId).first();
        return jsonResponse(await issueSessionPayload(env, user, deviceId, rawApiKey), 201);
      }

      if (method === "POST" && path === "/api/v1/auth/login") {
        const body = await readJsonBody(request);
        const account = (body.account || body.email || "").trim().toLowerCase();
        const password = String(body.password || "");
        const deviceId = (body.deviceID || "ios-default").trim();
        if (!account || !password) return errorResponse(400, "BAD_REQUEST", "请输入邮箱和密码");

        const user = await env.DB.prepare(
          "SELECT * FROM users WHERE lower(email) = ? OR lower(username) = ? LIMIT 1"
        ).bind(account, account).first();
        if (!user || !(await verifyPassword(password, user.password_hash))) {
          return errorResponse(401, "INVALID_CREDENTIALS", "账号或密码不正确");
        }

        await env.DB.prepare("UPDATE users SET last_login_at = ? WHERE id = ?").bind(nowSec(), user.id).run();
        return jsonResponse(await issueSessionPayload(env, user, deviceId));
      }

      if (method === "POST" && path === "/api/v1/auth/apple") {
        const body = await readJsonBody(request);
        const appleSub = String(body.user || "").trim();
        const deviceId = (body.deviceID || "ios-default").trim();
        if (!appleSub) return errorResponse(400, "BAD_REQUEST", "缺少 Apple 用户标识");

        let user = await env.DB.prepare("SELECT * FROM users WHERE apple_sub = ?").bind(appleSub).first();
        let rawApiKey = null;
        const now = nowSec();
        if (!user) {
          const userId = crypto.randomUUID();
          rawApiKey = `lx_live_${randomHex(20)}`;
          const apiKeyHash = await sha256Hex(rawApiKey);
          const e2eeSalt = randomHex(32);
          await env.DB.prepare(
            `INSERT INTO users (id, email, username, apple_sub, api_key_hash, api_key_prefix, e2ee_salt, created_at, updated_at, last_login_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
          ).bind(
            userId,
            `apple_${appleSub.slice(0, 8)}@privaterelay.lingxi.ime`,
            "灵犀用户",
            appleSub,
            apiKeyHash,
            `${rawApiKey.slice(0, 14)}...`,
            e2eeSalt,
            now,
            now,
            now
          ).run();
          user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userId).first();
        } else {
          await env.DB.prepare("UPDATE users SET last_login_at = ? WHERE id = ?").bind(now, user.id).run();
        }
        return jsonResponse(await issueSessionPayload(env, user, deviceId, rawApiKey));
      }

      if (method === "POST" && path === "/api/v1/auth/refresh") {
        const body = await readJsonBody(request);
        const rt = String(body.refreshToken || "").trim();
        if (!rt) return errorResponse(401, "INVALID_REFRESH", "缺少刷新令牌");
        const rtHash = await sha256Hex(rt);
        const sess = await env.DB.prepare(
          "SELECT * FROM auth_sessions WHERE refresh_token_hash = ? AND expires_at > ?"
        ).bind(rtHash, nowSec()).first();
        if (!sess) return errorResponse(401, "INVALID_REFRESH", "会话已过期，请重新登录");
        const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(sess.user_id).first();
        if (!user) return errorResponse(401, "USER_NOT_FOUND", "用户不存在");
        await env.DB.prepare("DELETE FROM auth_sessions WHERE token_id = ?").bind(sess.token_id).run();
        return jsonResponse(await issueSessionPayload(env, user, sess.device_id));
      }

      if (method === "POST" && path === "/api/v1/auth/api-key/rotate") {
        const auth = await resolveAuthUser(request, env);
        if (!auth) return errorResponse(401, "UNAUTHORIZED", "请先登录灵犀账号");
        const rawKey = `lx_live_${randomHex(20)}`;
        const keyHash = await sha256Hex(rawKey);
        const prefix = `${rawKey.slice(0, 14)}...`;
        await env.DB.prepare(
          "UPDATE users SET api_key_hash = ?, api_key_prefix = ?, updated_at = ? WHERE id = ?"
        ).bind(keyHash, prefix, nowSec(), auth.user.id).run();
        return jsonResponse({ apiKey: rawKey, apiKeyPrefix: prefix });
      }

      if (method === "POST" && path === "/api/v1/auth/password/change") {
        const auth = await resolveAuthUser(request, env);
        if (!auth) return errorResponse(401, "UNAUTHORIZED", "请先登录灵犀账号");
        const body = await readJsonBody(request);
        const newPassword = String(body.newPassword || "");
        if (newPassword.length < 6) return errorResponse(400, "WEAK_PASSWORD", "新密码至少 6 位");
        const newHash = await hashPassword(newPassword);
        const rotateSalt = Boolean(body.rotateE2EESalt);
        const newSalt = rotateSalt ? randomHex(32) : auth.user.e2ee_salt;
        await env.DB.prepare(
          "UPDATE users SET password_hash = ?, e2ee_salt = ?, updated_at = ? WHERE id = ?"
        ).bind(newHash, newSalt, nowSec(), auth.user.id).run();
        return jsonResponse({ ok: true, e2eeSalt: newSalt });
      }

      // 3. Zero-Knowledge E2EE LWW Sync (Settings / Theme / Self-Learning User Lexicon / Phrases)
      if (method === "GET" && path === "/api/v1/sync/pull") {
        const auth = await resolveAuthUser(request, env);
        if (!auth) return errorResponse(401, "UNAUTHORIZED", "请先登录或接入 API Key");
        const ns = (url.searchParams.get("namespace") || "settings").trim();
        const since = parseInt(url.searchParams.get("since") || "0", 10) || 0;
        const limit = Math.min(200, Math.max(1, parseInt(url.searchParams.get("limit") || "100", 10) || 100));

        const rowsRes = await env.DB.prepare(
          `SELECT namespace, record_key, ciphertext_b64, lamport_ts, device_id, tombstone, schema_version, server_seq
           FROM sync_records
           WHERE user_id = ? AND namespace = ? AND server_seq > ?
           ORDER BY server_seq ASC LIMIT ?`
        ).bind(auth.user.id, ns, since, limit + 1).all();
        const rows = rowsRes.results || [];
        const hasMore = rows.length > limit;
        const page = hasMore ? rows.slice(0, limit) : rows;
        const nextCursor = page.length > 0 ? page[page.length - 1].server_seq : since;

        return jsonResponse({
          changes: page.map((r) => ({
            namespace: r.namespace,
            key: r.record_key,
            ciphertext: r.ciphertext_b64,
            lamportTS: r.lamport_ts,
            deviceID: r.device_id,
            tombstone: Boolean(r.tombstone),
            schemaVersion: r.schema_version
          })),
          nextCursor,
          hasMore
        });
      }

      if (method === "POST" && path === "/api/v1/sync/push") {
        const auth = await resolveAuthUser(request, env);
        if (!auth) return errorResponse(401, "UNAUTHORIZED", "请先登录或接入 API Key");
        const body = await readJsonBody(request);
        const changes = Array.isArray(body.changes) ? body.changes : [];
        const now = nowSec();
        const conflicts = [];

        const seqRow = await env.DB.prepare(
          "SELECT COALESCE(MAX(server_seq), 0) AS m FROM sync_records WHERE user_id = ?"
        ).bind(auth.user.id).first();
        let nextSeq = (seqRow?.m || 0) + 1;

        for (const c of changes) {
          const ns = String(c.namespace || "settings");
          const key = String(c.key || "");
          if (!key) continue;
          const lamport = Number(c.lamportTS || 0);
          const devId = String(c.deviceID || auth.deviceId);
          const cipher = String(c.ciphertext || "");
          const tomb = c.tombstone ? 1 : 0;
          const schemaVer = Number(c.schemaVersion || 1);

          const cur = await env.DB.prepare(
            "SELECT * FROM sync_records WHERE user_id = ? AND namespace = ? AND record_key = ?"
          ).bind(auth.user.id, ns, key).first();

          if (cur && (cur.lamport_ts > lamport || (cur.lamport_ts === lamport && cur.device_id > devId))) {
            conflicts.push({
              namespace: ns,
              key,
              serverRecord: {
                namespace: cur.namespace,
                key: cur.record_key,
                ciphertext: cur.ciphertext_b64,
                lamportTS: cur.lamport_ts,
                deviceID: cur.device_id,
                tombstone: Boolean(cur.tombstone),
                schemaVersion: cur.schema_version
              }
            });
            continue;
          }

          await env.DB.prepare(
            `INSERT INTO sync_records (user_id, namespace, record_key, ciphertext_b64, lamport_ts, device_id, tombstone, schema_version, server_seq, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(user_id, namespace, record_key) DO UPDATE SET
               ciphertext_b64 = excluded.ciphertext_b64,
               lamport_ts = excluded.lamport_ts,
               device_id = excluded.device_id,
               tombstone = excluded.tombstone,
               schema_version = excluded.schema_version,
               server_seq = excluded.server_seq,
               updated_at = excluded.updated_at`
          ).bind(auth.user.id, ns, key, cipher, lamport, devId, tomb, schemaVer, nextSeq++, now).run();

          await env.DB.prepare(
            `INSERT INTO sync_state (user_id, device_id, namespace, last_seen_lamport, updated_at)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(user_id, device_id, namespace) DO UPDATE SET
               last_seen_lamport = MAX(sync_state.last_seen_lamport, excluded.last_seen_lamport),
               updated_at = excluded.updated_at`
          ).bind(auth.user.id, devId, ns, lamport, now).run();
        }

        return jsonResponse({ accepted: changes.length - conflicts.length, conflicts });
      }

      // 4. Typing Habit Analytics & Self-Learning Profile
      if (method === "POST" && path === "/api/v1/analytics/typing-events") {
        const auth = await resolveAuthUser(request, env);
        if (!auth) return errorResponse(401, "UNAUTHORIZED", "请先登录");
        const body = await readJsonBody(request);
        const events = Array.isArray(body.events) ? body.events : [];
        const now = nowSec();
        for (const e of events) {
          await env.DB.prepare(
            `INSERT INTO typing_habit_events (
               user_id, device_id, started_at, duration_seconds, committed_chars, committed_words,
               delete_count, undo_learn_count, glide_words, typo_corrected_count,
               ai_invocations, translate_chars, scheme_id, layout_id, active_hour, confusion_json, created_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
          ).bind(
            auth.user.id,
            String(e.deviceID || auth.deviceId),
            Number(e.startedAt || now),
            Math.max(1, Number(e.durationSeconds || 1)),
            Number(e.committedChars || 0),
            Number(e.committedWords || 0),
            Number(e.deleteCount || 0),
            Number(e.undoLearnCount || 0),
            Number(e.glideWords || 0),
            Number(e.typoCorrectedCount || 0),
            Number(e.aiInvocations || 0),
            Number(e.translateChars || 0),
            String(e.schemeID || "quanpin"),
            String(e.layoutID || "qwerty26"),
            Number(e.activeHour ?? 12),
            JSON.stringify(e.confusionCounts || {}),
            now
          ).run();
        }
        const profile = await recomputeUserHabitProfile(env, auth.user.id);
        return jsonResponse({ ok: true, ingested: events.length, profile });
      }

      if (method === "POST" && path === "/api/v1/analytics/api-usage") {
        const auth = await resolveAuthUser(request, env);
        if (!auth) return errorResponse(401, "UNAUTHORIZED", "请先登录");
        const body = await readJsonBody(request);
        const logs = Array.isArray(body.logs) ? body.logs : [body];
        const now = nowSec();
        for (const l of logs) {
          if (!l || !l.feature) continue;
          await env.DB.prepare(
            `INSERT INTO ai_api_usage_logs (user_id, feature, provider, target_lang, formal_tone, input_chars, output_chars, latency_ms, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
          ).bind(
            auth.user.id,
            String(l.feature),
            String(l.provider || "gemini"),
            String(l.targetLang || "英文"),
            l.formalTone ? 1 : 0,
            Number(l.inputChars || 0),
            Number(l.outputChars || 0),
            Number(l.latencyMs || 0),
            Number(l.createdAt || now)
          ).run();
        }
        const profile = await recomputeUserHabitProfile(env, auth.user.id);
        return jsonResponse({ ok: true, profile });
      }

      if (method === "POST" && path === "/api/v1/analytics/lexicon-habits") {
        const auth = await resolveAuthUser(request, env);
        if (!auth) return errorResponse(401, "UNAUTHORIZED", "请先登录");
        const body = await readJsonBody(request);
        const now = nowSec();
        await recomputeUserHabitProfile(env, auth.user.id);
        await env.DB.prepare(
          "UPDATE user_typing_profiles SET domain_affinity_json = ?, updated_at = ? WHERE user_id = ?"
        ).bind(JSON.stringify(body), now, auth.user.id).run();
        const profile = await recomputeUserHabitProfile(env, auth.user.id);
        return jsonResponse({ ok: true, profile });
      }

      if (method === "GET" && path === "/api/v1/analytics/habits") {
        const auth = await resolveAuthUser(request, env);
        if (!auth) return errorResponse(401, "UNAUTHORIZED", "请先登录");
        const profile = await recomputeUserHabitProfile(env, auth.user.id);
        return jsonResponse({ profile });
      }

      if (method === "DELETE" && path === "/api/v1/analytics/habits") {
        const auth = await resolveAuthUser(request, env);
        if (!auth) return errorResponse(401, "UNAUTHORIZED", "请先登录");
        await env.DB.prepare("DELETE FROM typing_habit_events WHERE user_id = ?").bind(auth.user.id).run();
        await env.DB.prepare("DELETE FROM ai_api_usage_logs WHERE user_id = ?").bind(auth.user.id).run();
        await env.DB.prepare("DELETE FROM user_typing_profiles WHERE user_id = ?").bind(auth.user.id).run();
        const profile = await recomputeUserHabitProfile(env, auth.user.id);
        return jsonResponse({ ok: true, profile });
      }

      // 5. Cross-Device 6-Digit Clipboard Relay (REST + SSE)
      if (method === "POST" && path === "/api/v1/relay/clipboard") {
        const body = await readJsonBody(request);
        const pairCode = String(body.pairCode || "").trim();
        const contentText = String(body.contentText || "").trim();
        if (!pairCode || !contentText) return errorResponse(400, "BAD_REQUEST", "匹配码和内容不能为空");
        const now = nowSec();
        const extracted = extractOTPCode(contentText);
        const category = extracted ? "code" : (/^https?:\/\//i.test(contentText) ? "url" : "text");
        const senderDevice = String(body.senderDevice || "Web/iPhone");

        await env.DB.prepare("DELETE FROM clipboard_relays WHERE expires_at < ?").bind(now).run();
        const ins = await env.DB.prepare(
          `INSERT INTO clipboard_relays (pair_code, content_text, category, extracted_code, sender_device, created_at, expires_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)`
        ).bind(pairCode, contentText, category, extracted, senderDevice, now, now + 600).run();

        return jsonResponse({
          ok: true,
          id: ins.meta?.last_row_id || 0,
          pairCode,
          category,
          extractedCode: extracted
        }, 201);
      }

      if (method === "GET" && path === "/api/v1/relay/clipboard") {
        const code = (url.searchParams.get("code") || "").trim();
        if (!code) return jsonResponse({ items: [] });
        const now = nowSec();
        const res = await env.DB.prepare(
          `SELECT id, pair_code AS pairCode, content_text AS contentText, category,
                  extracted_code AS extractedCode, sender_device AS senderDevice, created_at AS createdAt
           FROM clipboard_relays
           WHERE pair_code = ? AND expires_at >= ?
           ORDER BY id DESC LIMIT 15`
        ).bind(code, now).all();
        return jsonResponse({ items: res.results || [] });
      }

      if (method === "GET" && path === "/api/v1/relay/stream") {
        const code = (url.searchParams.get("code") || "").trim();
        const now = nowSec();
        const res = code
          ? await env.DB.prepare(
              `SELECT id, pair_code AS pairCode, content_text AS contentText, category,
                      extracted_code AS extractedCode, sender_device AS senderDevice, created_at AS createdAt
               FROM clipboard_relays
               WHERE pair_code = ? AND expires_at >= ?
               ORDER BY id DESC LIMIT 5`
            ).bind(code, now).all()
          : { results: [] };
        const payload = `retry: 3000\ndata: ${JSON.stringify({ items: res.results || [] })}\n\n`;
        return new Response(payload, {
          status: 200,
          headers: {
            "Content-Type": "text/event-stream; charset=utf-8",
            "Cache-Control": "no-cache",
            ...CORS_HEADERS
          }
        });
      }

      // 6. GDPR / PIPL Compliance
      if (method === "POST" && path === "/api/v1/compliance/consent") {
        const auth = await resolveAuthUser(request, env);
        if (!auth) return errorResponse(401, "UNAUTHORIZED", "请先登录");
        const body = await readJsonBody(request);
        const scope = String(body.scope || "typing_analytics");
        const granted = body.granted ? 1 : 0;
        const now = nowSec();
        await env.DB.prepare(
          `INSERT INTO consent_records (id, user_id, scope, granted, at, ip, policy_version)
           VALUES (?, ?, ?, ?, ?, ?, ?)`
        ).bind(crypto.randomUUID(), auth.user.id, scope, granted, now, clientIp, String(body.policyVersion || "2026.11-v1")).run();
        if (scope === "typing_analytics") {
          await env.DB.prepare("UPDATE users SET analytics_opt_in = ?, opt_in_at = ? WHERE id = ?")
            .bind(granted, granted ? now : 0, auth.user.id).run();
        }
        return jsonResponse({ ok: true, scope, granted: Boolean(granted) });
      }

      if (method === "DELETE" && path === "/api/v1/compliance/account") {
        const auth = await resolveAuthUser(request, env);
        if (!auth) return errorResponse(401, "UNAUTHORIZED", "请先登录");
        const uid = auth.user.id;
        await env.DB.prepare("DELETE FROM auth_sessions WHERE user_id = ?").bind(uid).run();
        await env.DB.prepare("DELETE FROM sync_records WHERE user_id = ?").bind(uid).run();
        await env.DB.prepare("DELETE FROM sync_state WHERE user_id = ?").bind(uid).run();
        await env.DB.prepare("DELETE FROM typing_habit_events WHERE user_id = ?").bind(uid).run();
        await env.DB.prepare("DELETE FROM ai_api_usage_logs WHERE user_id = ?").bind(uid).run();
        await env.DB.prepare("DELETE FROM user_typing_profiles WHERE user_id = ?").bind(uid).run();
        await env.DB.prepare("DELETE FROM consent_records WHERE user_id = ?").bind(uid).run();
        await env.DB.prepare("DELETE FROM devices WHERE user_id = ?").bind(uid).run();
        await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(uid).run();
        return jsonResponse({ ok: true, deletedUserID: uid });
      }

      // 7. B2B & Dashboard Demo Seed
      if (method === "POST" && path === "/api/v1/b2b/clients") {
        const body = await readJsonBody(request);
        const org = String(body.org || "灵犀企业客户").trim();
        const scopes = String(body.scopes || "profile:read,aggregate:read");
        const serviceKey = `lxb_live_${randomHex(18)}`;
        const keyHash = await sha256Hex(serviceKey);
        const keyPrefix = `${serviceKey.slice(0, 14)}...`;
        const id = crypto.randomUUID();
        await env.DB.prepare(
          `INSERT INTO api_clients (id, org, key_hash, key_prefix, scopes, created_at)
           VALUES (?, ?, ?, ?, ?, ?)`
        ).bind(id, org, keyHash, keyPrefix, scopes, nowSec()).run();
        return jsonResponse({ id, org, serviceKey, keyPrefix, scopes }, 201);
      }

      if (method === "POST" && path === "/api/v1/b2b/simulate-query") {
        const body = await readJsonBody(request);
        const cid = String(body.clientID || "");
        const client = await env.DB.prepare("SELECT * FROM api_clients WHERE id = ?").bind(cid).first();
        if (!client) return errorResponse(404, "NOT_FOUND", "企业客户不存在");
        await env.DB.prepare("UPDATE api_clients SET call_count = call_count + 1, billable_units = billable_units + 1 WHERE id = ?").bind(cid).run();
        await env.DB.prepare(
          `INSERT INTO b2b_audit_logs (client_id, org, endpoint, target_user_id, scope_used, ip, status_code, created_at)
           VALUES (?, ?, '/api/v1/b2b/aggregate', 'aggregate', 'aggregate:read', ?, 200, ?)`
        ).bind(cid, client.org, clientIp, nowSec()).run();
        return jsonResponse({ ok: true });
      }

      if (method === "POST" && path === "/api/v1/dashboard/seed-demo") {
        const now = nowSec();
        const demoEmail = "demo@lingxi.ime";
        let demo = await env.DB.prepare("SELECT * FROM users WHERE email = ?").bind(demoEmail).first();
        if (!demo) {
          const uid = crypto.randomUUID();
          const pwHash = await hashPassword("lingxi2026");
          const rawKey = `lx_live_${randomHex(16)}`;
          await env.DB.prepare(
            `INSERT INTO users (id, email, username, password_hash, api_key_hash, api_key_prefix, e2ee_salt, analytics_opt_in, opt_in_at, created_at, updated_at, last_login_at)
             VALUES (?, ?, '灵犀体验官', ?, ?, ?, ?, 1, ?, ?, ?, ?)`
          ).bind(uid, demoEmail, pwHash, await sha256Hex(rawKey), `${rawKey.slice(0, 14)}...`, randomHex(32), now, now, now, now).run();
          demo = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(uid).first();
        }
        await env.DB.prepare(
          `INSERT INTO typing_habit_events (user_id, device_id, started_at, duration_seconds, committed_chars, committed_words, delete_count, glide_words, scheme_id, layout_id, active_hour, confusion_json, created_at)
           VALUES (?, 'iphone-16', ?, 45, 62, 24, 3, 6, 'quanpin', 'qwerty26', 21, '{"zh_z":2,"an_ang":3,"in_ing":1}', ?)`
        ).bind(demo.id, now - 60, now).run();
        await recomputeUserHabitProfile(env, demo.id);
        return jsonResponse({ ok: true });
      }

      return errorResponse(404, "NOT_FOUND", `未找到接口：${method} ${path}`);
    } catch (err) {
      if (err && typeof err === "object" && "status" in err && "code" in err) {
        return errorResponse(err.status, err.code, err.message);
      }
      return errorResponse(500, "INTERNAL_ERROR", err?.message || "服务端内部错误");
    }
  }
};
