export const DASHBOARD_HTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>灵犀输入法 (Lingxi IME) · Cloudflare 云端全栈控制台 v4.2</title>
<style>
:root{
  --bg:#F2F3F7;--card:#FFFFFF;--surf:#F6F7FA;--line:#E4E7EE;--ink:#0A0A0A;--slate:#3B4252;--mut:#6E7480;
  --accent:#0A0A0A;--accent-fg:#FFFFFF;--blue:#007AFF;--ok:#17976A;--warn:#D97706;--err:#DC2626;
  --r:16px;--rsm:10px;--font:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Microsoft YaHei",sans-serif;
  --mono:"SF Mono","JetBrains Mono",Consolas,monospace;
}
[data-theme="dark"]{
  --bg:#000000;--card:#1C1C1E;--surf:#2C2C2E;--line:#38383A;--ink:#F2F2F7;--slate:#D1D1D6;--mut:#8E8E93;
  --accent:#F2F2F7;--accent-fg:#0A0A0A;--blue:#0A84FF;--ok:#30D158;--warn:#FF9F0A;--err:#FF453A;
}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:var(--font);background:var(--bg);color:var(--ink);line-height:1.5;padding-bottom:60px;transition:background .18s,color .18s}
.topbar{position:sticky;top:0;z-index:30;background:var(--card);border-bottom:1px solid var(--line);padding:12px 22px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px}
.brand{display:flex;align-items:center;gap:12px}
.logo{width:36px;height:36px;border-radius:10px;background:var(--accent);color:var(--accent-fg);display:grid;place-items:center;font-weight:700;font-size:17px}
.b-t{font-size:16px;font-weight:700}.b-s{font-size:11.5px;color:var(--mut)}
.acts{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.btn,.pill{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:600;padding:7px 14px;border-radius:999px;border:1px solid var(--line);background:var(--card);color:var(--ink);cursor:pointer;transition:transform .12s,opacity .15s}
.btn:hover{opacity:.86}.btn:active{transform:scale(.97)}
.btn-p{background:var(--accent);color:var(--accent-fg);border-color:var(--accent)}
.btn-blue{background:var(--blue);color:#fff;border-color:var(--blue)}
.btn-err{color:var(--err);border-color:rgba(220,38,38,.35)}
.dot{width:7px;height:7px;border-radius:50%;background:var(--ok);display:inline-block}
.navwrap{background:var(--card);border-bottom:1px solid var(--line);padding:0 22px;overflow-x:auto}
.tabs{display:flex;gap:4px;max-width:1280px;margin:0 auto;white-space:nowrap}
.tab{border:none;background:transparent;color:var(--mut);font-size:13px;font-weight:600;padding:12px 14px;cursor:pointer;border-bottom:2px solid transparent;transition:color .15s,border-color .15s}
.tab:hover{color:var(--ink)}
.tab.active{color:var(--ink);border-bottom-color:var(--ink)}
.wrap{max-width:1280px;margin:20px auto 0;padding:0 18px}
.pane{display:none;flex-direction:column;gap:18px}.pane.active{display:flex}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(185px,1fr));gap:12px}
.g2{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:16px}
@media(max-width:640px){.g2{grid-template-columns:1fr}}
.card{background:var(--card);border:1px solid var(--line);border-radius:var(--r);padding:18px}
.k-l{font-size:12px;color:var(--mut);font-weight:500}.k-v{font-family:var(--mono);font-size:25px;font-weight:700;margin-top:4px}.k-f{font-size:11px;color:var(--mut);margin-top:3px}
.ch{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:12px;flex-wrap:wrap}
.ct{font-size:15px;font-weight:700}.cd{font-size:12px;color:var(--mut);margin-bottom:12px}
.row{display:flex;gap:8px;margin-bottom:10px;flex-wrap:wrap;align-items:center}
.in,textarea.in{flex:1;min-width:140px;padding:9px 12px;border-radius:var(--rsm);border:1px solid var(--line);background:var(--surf);color:var(--ink);font-size:13px;outline:none;font-family:inherit}
.in:focus,textarea.in:focus{border-color:var(--ink)}
.mono{font-family:var(--mono)}
.bars{display:flex;align-items:flex-end;gap:4px;height:125px;padding:12px 8px 4px;background:var(--surf);border-radius:var(--rsm);border:1px solid var(--line)}
.bc{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;height:100%;gap:4px}
.bf{width:100%;background:var(--accent);border-radius:3px 3px 0 0;min-height:3px;transition:height .25s}.bl{font-family:var(--mono);font-size:9px;color:var(--mut)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(155px,1fr));gap:9px}
.cell{padding:11px;border-radius:var(--rsm);background:var(--surf);border:1px solid var(--line);display:flex;flex-direction:column;gap:4px}
.c-t{font-size:12px;font-weight:600}.c-v{font-family:var(--mono);font-size:16px;font-weight:700}.c-s{font-size:11px;color:var(--mut)}
.pbar{height:5px;background:var(--line);border-radius:99px;overflow:hidden;margin-top:3px}.pfill{height:100%;background:var(--accent);border-radius:99px}
.feed{display:flex;flex-direction:column;gap:8px;max-height:300px;overflow-y:auto}
.fi{padding:11px 13px;border-radius:var(--rsm);background:var(--surf);border:1px solid var(--line);display:flex;justify-content:space-between;gap:10px;align-items:center;font-size:13px}
table{width:100%;border-collapse:collapse;font-size:12.5px}
th,td{text-align:left;padding:10px 8px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--mut);font-size:11.5px;font-weight:600}
.tag{display:inline-flex;align-items:center;gap:4px;font-size:11px;font-weight:600;padding:2px 8px;border-radius:999px;background:var(--surf);border:1px solid var(--line);margin:2px 3px 2px 0}
.pack-card{padding:14px;border-radius:12px;background:var(--surf);border:1px solid var(--line);display:flex;flex-direction:column;gap:8px}
pre.tsv{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px;font-family:var(--mono);font-size:11.5px;max-height:180px;overflow:auto;white-space:pre-wrap;display:none}
.toast{position:fixed;bottom:22px;right:22px;background:var(--accent);color:var(--accent-fg);padding:10px 18px;border-radius:999px;font-size:12.5px;font-weight:600;opacity:0;pointer-events:none;transition:opacity .18s;z-index:100}
.toast.show{opacity:1}
</style>
</head>
<body>
<header class="topbar">
  <div class="brand">
    <div class="logo">灵</div>
    <div>
      <div class="b-t">灵犀输入法 (Lingxi IME) · Cloudflare 云端全栈控制台</div>
      <div class="b-s">Cloudflare Workers + D1 SQLite · 端到端零知识同步 · 自学习词库 · 跨屏剪贴板 · 习惯诊断 · 合规审计</div>
    </div>
  </div>
  <div class="acts">
    <span class="pill"><span class="dot"></span><span id="srv-st">D1 在线 v4.2.0</span></span>
    <button class="btn mono" id="url-btn" onclick="copyOrigin()">📱 复制接入地址</button>
    <button class="btn" onclick="seedDemo()">✨ 注入完整演示数据</button>
    <button class="btn" onclick="refreshAll()">↻ 刷新</button>
    <button class="btn" onclick="toggleTheme()">◑ 亮/暗</button>
  </div>
</header>

<div class="navwrap">
  <nav class="tabs" id="tab-bar">
    <button class="tab active" data-tab="overview">📊 总览与同步监控</button>
    <button class="tab" data-tab="habits">🧠 自学习与习惯画像</button>
    <button class="tab" data-tab="relay">📋 跨屏剪贴板接力</button>
    <button class="tab" data-tab="community">📦 开源词库社区 (M4)</button>
    <button class="tab" data-tab="account">👤 我的灵犀账号 (实测登录)</button>
    <button class="tab" data-tab="compliance">🛡️ 企业 B 端与合规审计</button>
  </nav>
</div>

<main class="wrap">
  <!-- TAB 1: 总览与同步监控 -->
  <section class="pane active" id="pane-overview">
    <div class="kpis">
      <div class="card"><div class="k-l">注册用户 / 已授权画像</div><div class="k-v" id="k-users">0 / 0</div><div class="k-f">同步与分析通道物理隔离</div></div>
      <div class="card"><div class="k-l">E2EE 同步密文块</div><div class="k-v" id="k-sync">0</div><div class="k-f">词库/皮肤/设置全端加密存储</div></div>
      <div class="card"><div class="k-l">活跃接入设备</div><div class="k-v" id="k-devs">0</div><div class="k-f">iPhone / iPad / Web</div></div>
      <div class="card"><div class="k-l">打字习惯会话样本</div><div class="k-v" id="k-habits">0</div><div class="k-f">结构性零原文 · 实时重算</div></div>
      <div class="card"><div class="k-l">AI 与实时翻译调用</div><div class="k-v" id="k-ai">0</div><div class="k-f" id="k-lat">平均延迟 0 ms</div></div>
      <div class="card"><div class="k-l">社区词包 / B端计费单元</div><div class="k-v" id="k-pack-b2b">3 / 0</div><div class="k-f">M4 词库仓 & 180天审计</div></div>
    </div>

    <div class="g2">
      <div class="card">
        <div class="ch"><div class="ct">🔐 E2EE 零知识同步命名空间分布</div><span class="pill">LXE1 · LWW 冲突决胜</span></div>
        <div class="cd">查看各业务命名空间在 Cloudflare D1 中的密文块数量与最新同步水位（服务端数学上不可读明文）。</div>
        <div class="grid" id="ns-grid"></div>
      </div>
      <div class="card">
        <div class="ch"><div class="ct">📱 已接入设备列表 (devices)</div><span class="pill">自动心跳记录</span></div>
        <div class="cd">iPhone 端注册登录或执行一次同步后，设备将自动登记并记录客户端版本号与最后活跃时间。</div>
        <div style="overflow-x:auto;max-height:240px">
          <table><thead><tr><th>用户</th><th>设备名 / 平台</th><th>版本</th><th>最近活跃</th></tr></thead><tbody id="dev-tb"></tbody></table>
        </div>
      </div>
    </div>

    <div class="g2">
      <div class="card">
        <div class="ch"><div class="ct">🕒 24 小时昼夜打字节律曲线</div><span class="pill">全天 00:00–23:00</span></div>
        <div class="bars" id="hourly-bars"></div>
      </div>
      <div class="card">
        <div class="ch"><div class="ct">⌨️ 输入方案 & AI 技能调用分布</div><span class="pill">多方案实时聚合</span></div>
        <div class="grid" id="scheme-ai-grid"></div>
      </div>
    </div>
  </section>

  <!-- TAB 2: 自学习与习惯画像 -->
  <section class="pane" id="pane-habits">
    <div class="g2">
      <div class="card">
        <div class="ch"><div class="ct">🔥 9 组拼音易混音诊断热力图 (Confusion Matrix)</div><span class="pill">自动反哺模糊音开关</span></div>
        <div class="cd">统计平翘舌、前后鼻音、鼻边音与唇齿音混淆频次，命中阈值后 iPhone 端支持一键应用调优建议。</div>
        <div class="grid" id="cm-grid"></div>
      </div>
      <div class="card">
        <div class="ch"><div class="ct">🧭 个人自学习词库领域亲和力</div><span class="pill">反哺 AI 个人表达风格</span></div>
        <div class="cd">依据用户端侧脱敏上报的词库领域权重（科技研发 / 商务职场 / 日常社交 / 学术创作），自动适配 AI 润色语气。</div>
        <div class="grid" id="domain-grid"></div>
      </div>
    </div>

    <div class="card">
      <div class="ch">
        <div class="ct">✨ AI 自动分析与专属提示词方案（基于云端脱敏习惯画像实时推导）</div>
        <button class="btn btn-p" onclick="copySuggestedPersona()">📋 一键复制专属人设提示词</button>
      </div>
      <div class="cd" id="ai-prompt-summary">依据云端聚合的打字速度、易混音矩阵与词库领域权重，自动为你生成个人 AI 人设 System Prompt 与 4 套高频场景提示词（iPhone 端接入 AI Key 后同样支持大模型深度定制与一键写入键盘 AI 栏）。</div>
      <div class="grid" id="ai-prompt-grid"></div>
    </div>

    <div class="card">
      <div class="ch">
        <div class="ct">👤 用户打字习惯画像与智能引擎调优报表</div>
        <div class="row" style="margin:0">
          <input id="prof-q" class="in" style="min-width:200px" placeholder="搜索昵称、邮箱、方案或标签…" oninput="renderProfiles()" />
          <button class="btn" onclick="exportJSON()">📥 导出 JSON</button>
          <button class="btn" onclick="exportCSV()">📄 导出 CSV</button>
        </div>
      </div>
      <div style="overflow-x:auto">
        <table>
          <thead><tr><th>用户 / 邮箱</th><th>主方案 / 布局</th><th>平均 / 峰值速率</th><th>平均词长</th><th>退格 / 撤学 / 滑行</th><th>画像标签</th><th>引擎调优建议</th></tr></thead>
          <tbody id="prof-tb"></tbody>
        </table>
      </div>
    </div>
  </section>

  <!-- TAB 3: 跨屏剪贴板接力 -->
  <section class="pane" id="pane-relay">
    <div class="card">
      <div class="ch"><div class="ct">📋 跨设备 6 位匹配码实时剪贴板接力</div><span class="pill" id="sse-st">SSE 实时流就绪</span></div>
      <div class="cd">在电脑与 iPhone「灵犀账号 → 跨屏剪贴板」输入相同 6 位匹配码，电脑发送的文字、链接或短信验证码将在手机键盘顶部全宽胶囊实时弹出（默认 10 分钟自动过期销毁）。</div>
      <div class="row">
        <input id="relay-code" class="in mono" style="max-width:150px;font-weight:700;letter-spacing:2px" value="886699" maxlength="8" placeholder="6位匹配码" />
        <button class="btn" onclick="connectSSE()">⚡ 连接实时通道</button>
        <button class="btn" onclick="loadRelay()">↻ 拉取最新</button>
        <button class="btn" onclick="sendDemoOTP()">💬 模拟发短信验证码到手机</button>
      </div>
      <div class="row">
        <input id="relay-txt" class="in" placeholder="输入要秒传到 iPhone 键盘顶栏的长文本、网址或验证码…" />
        <button class="btn btn-p" onclick="pushRelay()">🚀 立即秒传到手机</button>
      </div>
      <div class="feed" id="relay-feed"></div>
    </div>
  </section>

  <!-- TAB 4: 开源词库社区 (M4) -->
  <section class="pane" id="pane-community">
    <div class="card">
      <div class="ch"><div class="ct">📦 发布新的开源词库包（兼容 WowType / 灵犀 TSV）</div><span class="pill">App 端即时可订阅</span></div>
      <div class="cd">每行一条词条，格式为 <code class="mono">简码[Tab]词条文本</code>（如 <code class="mono">fy	法院诉讼</code>），发布后立即存入 Cloudflare D1，iPhone 端词库社区可直接拉取订阅。</div>
      <div class="row">
        <input id="pk-name" class="in" placeholder="词包名称（如：医学高频术语包）" />
        <input id="pk-cat" class="in" style="max-width:160px" value="社区共创" placeholder="分类" />
        <input id="pk-desc" class="in" placeholder="简短介绍（可选）" />
      </div>
      <div class="row">
        <textarea id="pk-tsv" class="in mono" rows="4" placeholder="每行一条：编码+Tab+词条&#10;lx	灵犀输入法&#10;cf	Cloudflare D1 云端"></textarea>
      </div>
      <button class="btn btn-p" onclick="publishPack()">+ 发布词包到 Cloudflare D1 社区仓</button>
    </div>

    <div class="card">
      <div class="ch"><div class="ct">📚 托管中的词库包仓库 (<span id="pk-cnt">0</span> 个)</div><span class="pill">支持预览 TSV 与一键下载</span></div>
      <div class="g2" id="pk-grid"></div>
    </div>
  </section>

  <!-- TAB 5: 我的灵犀账号 (Web 端实测注册/登录/查看自学习同步数据) -->
  <section class="pane" id="pane-account">
    <div class="g2">
      <div class="card">
        <div class="ch"><div class="ct">👤 灵犀云端账号登录 / 注册（与 iPhone 共用同一 D1 数据库）</div><span class="pill" id="me-badge">未登录</span></div>
        <div class="cd">你可以直接在这里注册账号并在 iPhone 登录，或者用 iPhone 刚注册好的邮箱在这里登录，实时查看你的设备、API Key 和端到端加密同步记录。</div>
        <div id="auth-forms">
          <div class="row">
            <input id="au-name" class="in" placeholder="昵称（注册时填写）" />
            <input id="au-email" class="in" type="email" placeholder="邮箱地址（如 me@example.com）" />
          </div>
          <div class="row">
            <input id="au-pw" class="in" type="password" placeholder="密码（至少 6 位）" />
            <button class="btn btn-p" onclick="webLogin()">登录</button>
            <button class="btn btn-blue" onclick="webRegister()">免费注册</button>
          </div>
        </div>
        <div id="me-panel" style="display:none;flex-direction:column;gap:10px">
          <div class="row">
            <input id="me-nick" class="in" placeholder="修改个人昵称" />
            <button class="btn btn-p" onclick="saveMyNickname()">保存昵称</button>
            <button class="btn" onclick="rotateMyKey()">🔄 轮换 API Key</button>
            <button class="btn btn-err" onclick="webLogout()">退出登录</button>
          </div>
          <div class="grid" id="me-meta"></div>
        </div>
      </div>

      <div class="card">
        <div class="ch"><div class="ct">☁️ 我的个人 E2EE 同步记录与自学习词库状态</div><span class="pill">按命名空间统计</span></div>
        <div class="cd">登录后这里展示你当前账号在 Cloudflare D1 中已同步的所有加密记录块（个人自学习词库 <code>lexicon</code>、设置 <code>settings</code>、主题 <code>theme</code>、常用短语等）。</div>
        <div style="overflow-x:auto;max-height:280px">
          <table><thead><tr><th>命名空间</th><th>记录键 (key)</th><th>Lamport 版本</th><th>来源设备</th><th>密文大小</th><th>更新时间</th></tr></thead><tbody id="me-sync-tb"><tr><td colspan="6" style="color:var(--mut)">请先在左侧登录您的灵犀账号。</td></tr></tbody></table>
        </div>
      </div>
    </div>
  </section>

  <!-- TAB 6: 企业 B 端与合规审计 -->
  <section class="pane" id="pane-compliance">
    <div class="g2">
      <div class="card">
        <div class="ch"><div class="ct">🏢 B 端企业 API 客户管理与计费 (<code>api_clients</code>)</div><span class="pill">独立 Service Key + Scope 白名单</span></div>
        <div class="row">
          <input id="b2b-org" class="in" placeholder="输入企业客户名称（如：灵犀企业版 SaaS）" />
          <button class="btn btn-p" onclick="createB2B()">+ 签发企业密钥</button>
        </div>
        <div style="overflow-x:auto">
          <table><thead><tr><th>机构名称</th><th>密钥前缀</th><th>Scope</th><th>调用 / 计费单元</th><th>操作</th></tr></thead><tbody id="b2b-tb"></tbody></table>
        </div>
      </div>

      <div class="card">
        <div class="ch"><div class="ct">🛡️ GDPR / 个保法授权流水 & B 端 180 天审计</div><span class="pill">不可变合规留痕</span></div>
        <div style="overflow-x:auto;max-height:320px">
          <table><thead><tr><th>时间</th><th>类型 / 主体</th><th>Scope / 接口</th><th>状态</th></tr></thead><tbody id="audit-tb"></tbody></table>
        </div>
      </div>
    </div>
  </section>
</main>

<div id="toast" class="toast"></div>
<script>
let OV = null;
let SSE = null;
let MY_TOKEN = localStorage.getItem('lx_cf_token') || '';
const NS_NAMES = {
  lexicon: '🧠 个人自学习词库',
  ai_prompts: '✨ AI 专属提示词与人设',
  style_dna: '🧬 个人文风 DNA 与去AI腔',
  keymap: '⌨️ 26键自定义滑行映射',
  settings: '⚙️ 输入法全局设置',
  theme: '🎨 日夜双套外观主题',
  phrases: '📝 自定义编码短语',
  quick_phrases: '⚡ 动态变量快捷短语',
  recent_emojis: '😊 最近常用表情',
  typing_stats: '📈 本机打字统计'
};
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmtTime = ts => ts ? new Date(ts * 1000).toLocaleString() : '--';
function toast(m){ const e = document.getElementById('toast'); e.textContent = m; e.classList.add('show'); setTimeout(() => e.classList.remove('show'), 2800); }
function toggleTheme(){ const r = document.documentElement; r.setAttribute('data-theme', r.getAttribute('data-theme') === 'dark' ? 'light' : 'dark'); }
function copyOrigin(){ navigator.clipboard?.writeText(location.origin); toast('已复制 Cloudflare 接入地址：' + location.origin); }

document.getElementById('tab-bar').addEventListener('click', e => {
  const btn = e.target.closest('.tab'); if (!btn) return;
  document.querySelectorAll('.tab').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.pane').forEach(p => p.classList.remove('active'));
  btn.classList.add('active');
  document.getElementById('pane-' + btn.dataset.tab).classList.add('active');
  if (btn.dataset.tab === 'account' && MY_TOKEN) loadMe();
});

async function api(method, path, body = null, token = null) {
  const hdrs = { 'Content-Type': 'application/json' };
  if (token) hdrs['Authorization'] = 'Bearer ' + token;
  const res = await fetch(path, { method, headers: hdrs, body: body ? JSON.stringify(body) : undefined });
  const data = await res.json();
  if (!res.ok) throw new Error(data?.error?.message || ('HTTP ' + res.status));
  return data;
}

async function refreshAll() {
  try {
    OV = await api('GET', '/api/v1/dashboard/overview');
    document.getElementById('url-btn').textContent = '📱 ' + location.origin;
    document.getElementById('srv-st').textContent = 'Cloudflare D1 在线 v' + (OV.version || '4.2.0');
    const st = OV.stats || {};
    document.getElementById('k-users').textContent = (st.users || 0) + ' / ' + (st.optedInUsers || 0);
    document.getElementById('k-sync').textContent = st.syncRecords || 0;
    document.getElementById('k-devs').textContent = st.activeDevices || 0;
    document.getElementById('k-habits').textContent = st.habitEvents || 0;
    document.getElementById('k-ai').textContent = st.aiApiLogs || 0;
    document.getElementById('k-lat').textContent = '平均响应延迟 ' + (st.avgAiLatencyMs || 0) + ' ms';
    document.getElementById('k-pack-b2b').textContent = (OV.communityPacks?.length || 0) + ' / ' + (st.b2bBillableUnits || 0);

    renderNamespaces(OV.syncNamespaces || []);
    renderDevices(OV.devices || []);
    renderHourly(OV.aggregate?.hourlyRhythm || {});
    renderSchemeAI(OV.aggregate?.schemeBreakdown || {}, OV.aggregate?.aiBreakdown || {});
    renderCM(OV.aggregate?.confusionMatrix || {});
    renderDomains(OV.aggregate?.domainScores || {});
    renderAIInsights(OV.aggregate?.domainScores || {}, OV.aggregate?.confusionMatrix || {}, OV.profiles || []);
    renderProfiles();
    renderPacks(OV.communityPacks || []);
    renderB2B(OV.b2bClients || []);
    renderAudits(OV.consentLogs || [], OV.b2bAuditLogs || []);
    loadRelay();
    if (MY_TOKEN) loadMe();
  } catch (e) {
    toast('加载失败：' + e.message);
  }
}

function renderNamespaces(list) {
  const map = {}; list.forEach(x => { map[x.namespace] = x; });
  const keys = Object.keys(NS_NAMES);
  document.getElementById('ns-grid').innerHTML = keys.map(k => {
    const it = map[k] || { count: 0, maxLamport: 0, lastUpdated: 0 };
    return '<div class="cell"><div class="c-t">' + NS_NAMES[k] + '</div><div class="c-v">' + it.count + ' 块</div><div class="c-s">水位 L=' + (it.maxLamport || 0) + ' · ' + (it.lastUpdated ? new Date(it.lastUpdated * 1000).toLocaleTimeString() : '待同步') + '</div></div>';
  }).join('');
}

function renderDevices(devs) {
  const tb = document.getElementById('dev-tb');
  if (!devs.length) { tb.innerHTML = '<tr><td colspan="4" style="color:var(--mut)">暂无接入设备，iPhone 登录灵犀后自动登记。</td></tr>'; return; }
  tb.innerHTML = devs.map(d => '<tr><td><strong>' + esc(d.username) + '</strong></td><td>' + esc(d.name) + ' <span class="tag">' + esc(d.platform) + '</span></td><td class="mono">v' + esc(d.appVer) + '</td><td class="mono" style="font-size:11px">' + fmtTime(d.lastSeen) + '</td></tr>').join('');
}

function renderHourly(rhythm) {
  const w = document.getElementById('hourly-bars'); w.innerHTML = '';
  let mx = 1; for (let h = 0; h < 24; h++) mx = Math.max(mx, rhythm[h] || 0);
  for (let h = 0; h < 24; h++) {
    const v = rhythm[h] || 0, pct = Math.max(4, Math.round(v / mx * 88));
    w.innerHTML += '<div class="bc" title="' + String(h).padStart(2,'0') + ':00 — ' + v + ' 字"><div class="bf" style="height:' + pct + '%;opacity:' + (v ? 1 : .2) + '"></div><span class="bl">' + (h % 3 === 0 ? String(h).padStart(2,'0') : '') + '</span></div>';
  }
}

function renderSchemeAI(sch, ai) {
  const g = document.getElementById('scheme-ai-grid');
  const items = [];
  for (const [k, v] of Object.entries(sch)) items.push({ t: '方案 · ' + k, v: v + ' 字', s: '端侧打字统计' });
  for (const [k, v] of Object.entries(ai)) items.push({ t: 'AI · ' + k, v: v.calls + ' 次', s: '均耗时 ' + (v.avgLatencyMs || 0) + ' ms' });
  g.innerHTML = items.length ? items.map(i => '<div class="cell"><div class="c-t">' + esc(i.t) + '</div><div class="c-v">' + esc(i.v) + '</div><div class="c-s">' + esc(i.s) + '</div></div>').join('') : '<div class="cell"><div class="c-t">等待打字样本</div><div class="c-v">--</div><div class="c-s">可点右上角「注入完整演示数据」体验</div></div>';
}

function renderCM(cm) {
  const lbs = { zh_z:'zh ↔ z 平翘舌', ch_c:'ch ↔ c 平翘舌', sh_s:'sh ↔ s 平翘舌', n_l:'n ↔ l 鼻边音', an_ang:'an ↔ ang 前后鼻音', en_eng:'en ↔ eng 前后鼻音', in_ing:'in ↔ ing 前后鼻音', f_h:'f ↔ h 唇齿音', huang_wang:'huang ↔ wang 介音' };
  const mx = Math.max(1, ...Object.values(cm));
  document.getElementById('cm-grid').innerHTML = Object.entries(lbs).map(([k, t]) => {
    const n = cm[k] || 0, p = Math.min(100, Math.round(n / mx * 100));
    return '<div class="cell"><div class="c-t">' + t + '</div><div class="c-v">' + n + ' 次</div><div class="pbar"><div class="pfill" style="width:' + p + '%"></div></div></div>';
  }).join('');
}

function renderDomains(ds) {
  const all = ['科技与研发', '商务与职场', '日常与社交', '学术与创作'];
  const mx = Math.max(1, ...Object.values(ds));
  document.getElementById('domain-grid').innerHTML = all.map(d => {
    const n = ds[d] || 0, p = Math.min(100, Math.round(n / mx * 100));
    return '<div class="cell"><div class="c-t">' + d + '</div><div class="c-v">' + n + ' 词命中</div><div class="pbar"><div class="pfill" style="width:' + p + '%"></div></div></div>';
  }).join('');
}

let LAST_SUGGESTED_PERSONA = '';
function renderAIInsights(ds, cm, profiles) {
  const topDomain = Object.entries(ds).sort((a, b) => b[1] - a[1])[0]?.[0] || '综合日常';
  const topConf = Object.entries(cm).filter(([, v]) => v > 0).sort((a, b) => b[1] - a[1]).slice(0, 2).map(([k]) => k.replace('_', '/'));
  const avgCpm = profiles.length ? (profiles.reduce((s, p) => s + (p.avgCPM || 0), 0) / profiles.length).toFixed(1) : '0.0';
  let persona = '口吻自然真诚、表达清晰利落，少用冗长客套，直接输出可发送文本。';
  let prompts = [
    { t: '✦ 高情商答', c: '日常社交', p: '用自然真诚、高情商且有分寸感的口吻回复这段消息，直接可发送。' },
    { t: '✦ 顺句去冗', c: '效率沟通', p: '保留原意，去掉口水词与生硬语病，使语句流畅简洁。' },
    { t: '✦ 职场汇报', c: '职场商务', p: '把零散要点整理为结论先行、条理清晰的工作同步消息。' },
    { t: '✦ 一句话说清', c: '效率沟通', p: '将较长内容浓缩为重点明确、礼貌易懂的简短表达。' }
  ];
  if (topDomain.includes('科技')) {
    persona = '保持逻辑清晰、结论先行的科技从业者口吻，技术专有名词保留英文原词，句式精炼干脆。';
    prompts = [
      { t: '✦ 技术同步', c: '科技研发', p: '改写为简洁专业的研发进度/问题同步消息，明确现状、根因与下一步动作。' },
      { t: '✦ 问题复盘', c: '效率沟通', p: '整理为结构化排查记录：现象、根因、修复方案与验证结果。' },
      { t: '✦ 中英精译', c: '学习创作', p: '保留技术术语前提下进行地道中英互译，适合文档与 Issue 沟通。' },
      { t: '✦ 温和催促', c: '职场商务', p: '用友好合作不急躁的语气跟进同事进度，并给出清晰时间节点。' }
    ];
  } else if (topDomain.includes('商务')) {
    persona = '表达礼貌得体、重点突出、有分寸感，既体现专业度又保持亲和力，适合客户与团队协作。';
    prompts = [
      { t: '✦ 会议纪要', c: '商务职场', p: '将记录提炼为标准会议纪要：核心结论、待办事项、责任人与节点。' },
      { t: '✦ 客户回复', c: '商务职场', p: '用专业真诚的商务口吻回复客户，回应关切并明确后续安排。' },
      { t: '✦ 邮件润色', c: '商务职场', p: '润色成结构完整、措辞得体的正式商务消息或邮件正文。' },
      { t: '✦ 体面婉拒', c: '效率沟通', p: '高情商委婉拒绝时间或需求冲突，提供替代方案并保持好关系。' }
    ];
  }
  LAST_SUGGESTED_PERSONA = persona;
  const confTip = topConf.length ? (' · 建议开启模糊音：' + topConf.join('、')) : '';
  document.getElementById('ai-prompt-summary').textContent = '主领域：' + topDomain + ' · 均值速度：' + avgCpm + ' CPM' + confTip + ' ｜ 推荐人设：「' + persona + '」';
  document.getElementById('ai-prompt-grid').innerHTML = prompts.map((item, idx) =>
    '<div class="cell" style="cursor:pointer" data-p="' + esc(item.p) + '" onclick="copyPromptCell(this)"><div class="c-t">' + esc(item.t) + ' · ' + esc(item.c) + '</div><div style="font-size:12px;color:var(--ink);margin-top:4px;line-height:1.45">' + esc(item.p) + '</div><div class="c-s">点击复制该提示词</div></div>'
  ).join('');
}
function copySuggestedPersona() {
  if (!LAST_SUGGESTED_PERSONA) return;
  navigator.clipboard?.writeText(LAST_SUGGESTED_PERSONA);
  toast('已复制专属人设提示词，可粘贴到 iPhone 灵犀 AI 人设');
}
function copyPromptCell(el) {
  const txt = el.getAttribute('data-p') || '';
  if (!txt) return;
  navigator.clipboard?.writeText(txt);
  toast('已复制提示词模板');
}

function renderProfiles() {
  const q = (document.getElementById('prof-q').value || '').trim().toLowerCase();
  const list = (OV?.profiles || []).filter(p => !q || [p.username, p.email, p.primaryScheme, p.primaryLayout, ...(p.habitTags || [])].join(' ').toLowerCase().includes(q));
  const tb = document.getElementById('prof-tb');
  if (!list.length) { tb.innerHTML = '<tr><td colspan="7" style="color:var(--mut)">暂无匹配用户画像，可在 iPhone 注册登录或点右上角「注入完整演示数据」。</td></tr>'; return; }
  tb.innerHTML = list.map(p => '<tr><td><strong>' + esc(p.username) + '</strong><br><span class="mono" style="font-size:11px;color:var(--mut)">' + esc(p.email || p.userID.slice(0,8)) + '</span></td><td class="mono">' + esc(p.primaryScheme) + ' / ' + esc(p.primaryLayout) + '</td><td class="mono"><strong>' + p.avgCPM + '</strong> / ' + p.peakCPM + ' CPM</td><td class="mono">' + p.avgWordLength + ' 字/词</td><td class="mono">' + (p.backspaceRate*100).toFixed(1) + '% / ' + (p.undoLearnRate*100).toFixed(1) + '% / ' + (p.glideRatio*100).toFixed(1) + '%</td><td>' + (p.habitTags||[]).map(t => '<span class="tag">' + esc(t) + '</span>').join('') + '</td><td style="font-size:11.5px;color:var(--slate)">' + ((p.tuningRecommendations||[]).map(r => '• ' + esc(r.title)).join('<br>') || '当前参数已最优') + '</td></tr>').join('');
}

function renderPacks(packs) {
  document.getElementById('pk-cnt').textContent = packs.length;
  const g = document.getElementById('pk-grid'); g.innerHTML = '';
  packs.forEach(p => {
    const card = document.createElement('div'); card.className = 'pack-card';
    card.innerHTML = '<div style="display:flex;justify-content:space-between;align-items:center;gap:8px"><strong>📦 ' + esc(p.name) + '</strong><span class="tag">' + esc(p.category) + ' · ' + p.wordCount + ' 词</span></div>'
      + '<div style="font-size:12px;color:var(--mut)">' + esc(p.description || 'WowType / 灵犀标准 TSV 词包') + ' · v' + esc(p.version) + '</div>';
    const act = document.createElement('div'); act.className = 'row'; act.style.margin = '0';
    const bView = document.createElement('button'); bView.className = 'btn'; bView.textContent = '👀 预览 TSV 词条';
    const bDl = document.createElement('button'); bDl.className = 'btn'; bDl.textContent = '⬇️ 下载 .tsv';
    const pre = document.createElement('pre'); pre.className = 'tsv'; pre.textContent = p.tsv || '';
    bView.onclick = () => { pre.style.display = pre.style.display === 'block' ? 'none' : 'block'; };
    bDl.onclick = () => { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([p.tsv||''], {type:'text/tab-separated-values;charset=utf-8'})); a.download = p.id + '.tsv'; a.click(); };
    act.append(bView, bDl);
    if (p.isCustom) {
      const bDel = document.createElement('button'); bDel.className = 'btn btn-err'; bDel.textContent = '删除';
      bDel.onclick = async () => { await api('DELETE', '/api/v1/community/packs/' + encodeURIComponent(p.id)); toast('已删除词包'); refreshAll(); };
      act.append(bDel);
    }
    card.append(act, pre); g.append(card);
  });
}

function renderB2B(clients) {
  const tb = document.getElementById('b2b-tb');
  if (!clients.length) { tb.innerHTML = '<tr><td colspan="5" style="color:var(--mut)">暂无 B 端企业客户，输入机构名即可签发密钥。</td></tr>'; return; }
  tb.innerHTML = clients.map(c => '<tr><td><strong>' + esc(c.org) + '</strong></td><td class="mono">' + esc(c.keyPrefix) + '</td><td class="mono" style="font-size:11px">' + esc(c.scopes) + '</td><td class="mono">' + c.callCount + ' 次 / ' + c.billableUnits + ' 单元</td><td><button class="btn" style="padding:4px 10px" onclick="simB2B(\'' + esc(c.id) + '\')">模拟计费查询</button></td></tr>').join('');
}

function renderAudits(consents, audits) {
  const rows = [];
  consents.forEach(c => rows.push({ ts: c.at, who: '用户授权 (' + esc(String(c.userID).slice(0,6)) + ')', sc: esc(c.scope), st: c.granted ? '✓ 已授权 (' + esc(c.policyVersion) + ')' : '✕ 已撤回' }));
  audits.forEach(a => rows.push({ ts: a.createdAt, who: 'B端 (' + esc(a.org) + ')', sc: esc(a.endpoint) + ' [' + esc(a.scopeUsed) + ']', st: 'HTTP ' + a.statusCode + ' · 计费+1' }));
  rows.sort((a,b) => b.ts - a.ts);
  const tb = document.getElementById('audit-tb');
  tb.innerHTML = rows.length ? rows.slice(0, 25).map(r => '<tr><td class="mono" style="font-size:11px">' + fmtTime(r.ts) + '</td><td>' + r.who + '</td><td class="mono" style="font-size:11px">' + r.sc + '</td><td>' + r.st + '</td></tr>').join('') : '<tr><td colspan="4" style="color:var(--mut)">暂无审计流水</td></tr>';
}

async function loadRelay() {
  const code = document.getElementById('relay-code').value.trim(); if (!code) return;
  const r = await api('GET', '/api/v1/relay/clipboard?code=' + encodeURIComponent(code));
  const f = document.getElementById('relay-feed'); f.innerHTML = '';
  if (!(r.items||[]).length) { f.innerHTML = '<div class="fi" style="color:var(--mut)">匹配码 ' + esc(code) + ' 暂无记录，可点击上方「模拟发短信验证码」或直接输入发送。</div>'; return; }
  r.items.forEach(it => {
    const d = document.createElement('div'); d.className = 'fi';
    const left = document.createElement('div');
    const tag = document.createElement('span'); tag.className = 'tag';
    tag.textContent = it.extractedCode ? ('💬 验证码 ' + it.extractedCode) : (it.senderDevice || '跨屏');
    left.append(tag, document.createTextNode(' ' + (it.contentText || '')));
    const btn = document.createElement('button'); btn.className = 'btn'; btn.textContent = '复制';
    btn.onclick = () => { navigator.clipboard?.writeText(it.contentText || ''); toast('已复制到剪贴板'); };
    d.append(left, btn); f.append(d);
  });
}

function connectSSE() {
  const code = document.getElementById('relay-code').value.trim(); if (!code) return;
  if (SSE) SSE.close();
  SSE = new EventSource('/api/v1/relay/stream?code=' + encodeURIComponent(code));
  document.getElementById('sse-st').textContent = 'SSE 已连接 (' + code + ')';
  SSE.onmessage = () => loadRelay();
  loadRelay(); toast('已连接 6 位跨屏通道：' + code);
}

async function pushRelay() {
  const c = document.getElementById('relay-code').value.trim(), t = document.getElementById('relay-txt').value.trim();
  if (!c || !t) return toast('请输入匹配码和内容');
  await api('POST', '/api/v1/relay/clipboard', { pairCode: c, contentText: t, senderDevice: 'Cloudflare Web' });
  document.getElementById('relay-txt').value = ''; toast('已秒传至手机匹配码 ' + c); loadRelay();
}

async function sendDemoOTP() {
  const c = document.getElementById('relay-code').value.trim() || '886699', otp = Math.floor(100000 + Math.random() * 900000);
  await api('POST', '/api/v1/relay/clipboard', { pairCode: c, contentText: '【灵犀云安全】您的跨设备登录验证码为 ' + otp + '，5分钟内有效。', senderDevice: 'Cloudflare 控制台' });
  toast('已发送验证码 ' + otp + ' 到通道 ' + c); loadRelay();
}

async function publishPack() {
  const name = document.getElementById('pk-name').value.trim(), cat = document.getElementById('pk-cat').value.trim(), desc = document.getElementById('pk-desc').value.trim(), tsv = document.getElementById('pk-tsv').value.trim();
  if (!name || !tsv) return toast('请填写词包名称和 TSV 词条');
  await api('POST', '/api/v1/community/packs', { name, category: cat, description: desc, tsv });
  document.getElementById('pk-name').value = ''; document.getElementById('pk-desc').value = ''; document.getElementById('pk-tsv').value = '';
  toast('已发布词包到 Cloudflare D1 社区仓！'); refreshAll();
}

async function webRegister() {
  try {
    const res = await api('POST', '/api/v1/auth/register', { username: document.getElementById('au-name').value, email: document.getElementById('au-email').value, password: document.getElementById('au-pw').value, deviceID: 'web-console' });
    MY_TOKEN = res.accessToken; localStorage.setItem('lx_cf_token', MY_TOKEN);
    toast('注册成功！同一邮箱和密码可直接在 iPhone 登录'); loadMe(); refreshAll();
  } catch (e) { toast('注册失败：' + e.message); }
}

async function webLogin() {
  try {
    const res = await api('POST', '/api/v1/auth/login', { account: document.getElementById('au-email').value, password: document.getElementById('au-pw').value, deviceID: 'web-console' });
    MY_TOKEN = res.accessToken; localStorage.setItem('lx_cf_token', MY_TOKEN);
    toast('登录成功！已同步加载你的个人 D1 档案'); loadMe();
  } catch (e) { toast('登录失败：' + e.message); }
}

function webLogout() {
  MY_TOKEN = ''; localStorage.removeItem('lx_cf_token');
  document.getElementById('auth-forms').style.display = 'block';
  document.getElementById('me-panel').style.display = 'none';
  document.getElementById('me-badge').textContent = '未登录';
  document.getElementById('me-sync-tb').innerHTML = '<tr><td colspan="6" style="color:var(--mut)">已退出登录。</td></tr>';
  toast('已退出 Web 控制台账号');
}

async function loadMe() {
  if (!MY_TOKEN) return;
  try {
    const me = await api('GET', '/api/v1/me', null, MY_TOKEN);
    document.getElementById('auth-forms').style.display = 'none';
    document.getElementById('me-panel').style.display = 'flex';
    document.getElementById('me-badge').textContent = '已登录 · ' + (me.user.username || '灵犀用户');
    document.getElementById('me-nick').value = me.user.username || '';
    document.getElementById('me-meta').innerHTML = [
      { t: '绑定邮箱', v: me.user.email || '--' },
      { t: '专属 API Key 前缀', v: me.user.apiKeyPrefix || '--' },
      { t: 'E2EE 加密盐 (前12位)', v: (me.user.e2eeSalt || '').slice(0, 12) + '…' },
      { t: '已同步加密块数', v: (me.syncRecords?.length || 0) + ' 块' }
    ].map(x => '<div class="cell"><div class="c-t">' + x.t + '</div><div class="mono" style="font-size:12.5px;font-weight:700;word-break:break-all">' + esc(x.v) + '</div></div>').join('');
    const tb = document.getElementById('me-sync-tb');
    const recs = me.syncRecords || [];
    tb.innerHTML = recs.length ? recs.map(r => '<tr><td>' + esc(NS_NAMES[r.namespace] || r.namespace) + '</td><td class="mono">' + esc(r.key) + '</td><td class="mono">L=' + r.lamportTS + '</td><td class="mono">' + esc(r.deviceID) + '</td><td class="mono">' + r.byteSize + ' B</td><td class="mono" style="font-size:11px">' + fmtTime(r.updatedAt) + '</td></tr>').join('') : '<tr><td colspan="6" style="color:var(--mut)">当前账号尚无同步块，请在 iPhone 登录并点击「立即端到端同步」。</td></tr>';
  } catch (e) {
    webLogout();
  }
}

async function saveMyNickname() {
  const username = document.getElementById('me-nick').value.trim(); if (!username) return;
  await api('PATCH', '/api/v1/me', { username }, MY_TOKEN);
  toast('昵称已更新并写入 Cloudflare D1'); loadMe(); refreshAll();
}

async function rotateMyKey() {
  const res = await api('POST', '/api/v1/auth/api-key/rotate', {}, MY_TOKEN);
  navigator.clipboard?.writeText(res.apiKey);
  toast('已签发并复制新 API Key：' + res.apiKeyPrefix); loadMe();
}

async function createB2B() {
  const org = document.getElementById('b2b-org').value.trim() || '灵犀企业分析客户';
  const r = await api('POST', '/api/v1/b2b/clients', { org, scopes: 'profile:read,aggregate:read' });
  document.getElementById('b2b-org').value = '';
  navigator.clipboard?.writeText(r.serviceKey);
  toast('已签发并复制企业密钥：' + r.keyPrefix); refreshAll();
}

async function simB2B(id) {
  await api('POST', '/api/v1/b2b/simulate-query', { clientID: id });
  toast('已执行 B 端企业聚合查询并记录 180 天审计流水'); refreshAll();
}

async function seedDemo() {
  await api('POST', '/api/v1/dashboard/seed-demo', {});
  toast('✨ 已注入完整演示用户、E2EE 同步块、设备、易混音与 B 端审计样本'); refreshAll();
}

function exportJSON() {
  if (!OV) return;
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([JSON.stringify(OV, null, 2)], { type: 'application/json;charset=utf-8' }));
  a.download = 'lingxi-cloudflare-analytics-' + new Date().toISOString().slice(0,10) + '.json';
  a.click();
}

function exportCSV() {
  const rows = [['username','email','scheme','layout','avgCPM','peakCPM','avgWordLength','backspaceRate','glideRatio','tags']];
  (OV?.profiles || []).forEach(p => rows.push([p.username, p.email, p.primaryScheme, p.primaryLayout, p.avgCPM, p.peakCPM, p.avgWordLength, p.backspaceRate, p.glideRatio, (p.habitTags||[]).join('|')]));
  const csv = '\\uFEFF' + rows.map(r => r.map(x => '"' + String(x ?? '').replace(/"/g, '""') + '"').join(',')).join('\\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  a.download = 'lingxi-profiles-' + new Date().toISOString().slice(0,10) + '.csv';
  a.click();
}

refreshAll();
connectSSE();
</script>
</body>
</html>`;
