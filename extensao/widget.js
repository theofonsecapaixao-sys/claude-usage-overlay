// Widget flutuante de uso do Claude. Sem permissões além de claude.ai.
// Faz fetch same-origin (usa sua sessão já logada), não envia nada para fora.
(() => {
  if (window.top !== window || document.getElementById('cuw-host')) return;

  const REFRESH_MS = 60 * 1000;
  const LABELS = {
    five_hour: 'Sessão (5h)',
    seven_day: 'Semana',
    seven_day_opus: 'Semana · Opus',
    seven_day_sonnet: 'Semana · Sonnet',
  };
  const WINDOW_MS = { five_hour: 5 * 3600e3, seven_day: 7 * 24 * 3600e3 };

  const store = {
    get(k, d) { try { const v = localStorage.getItem('cuw:' + k); return v === null ? d : JSON.parse(v); } catch { return d; } },
    set(k, v) { try { localStorage.setItem('cuw:' + k, JSON.stringify(v)); } catch {} },
  };

  // ---------- UI (shadow DOM pra não brigar com o CSS do claude.ai) ----------
  const host = document.createElement('div');
  host.id = 'cuw-host';
  host.style.cssText = 'position:fixed;z-index:2147483646;';
  const pos = store.get('pos', { right: 16, bottom: 16 });
  host.style.right = pos.right + 'px';
  host.style.bottom = pos.bottom + 'px';
  const root = host.attachShadow({ mode: 'closed' });
  const CSS = `
      :host{all:initial}
      .box{font:12px/1.4 system-ui,-apple-system,sans-serif;color:#f3f4f6;background:rgba(24,24,27,.45);transition:background .2s;
        border:1px solid rgba(255,255,255,.1);border-radius:10px;padding:8px 10px;min-width:190px;
        box-shadow:0 4px 14px rgba(0,0,0,.4);backdrop-filter:blur(6px);user-select:none}
      .box:hover{background:rgba(24,24,27,.92)}
      .head{display:flex;justify-content:space-between;align-items:center;gap:8px;cursor:grab;color:#a1a1aa;font-size:11px}
      .head b{color:#f3f4f6;font-weight:600}
      .btns button{all:unset;cursor:pointer;padding:0 4px;color:#a1a1aa}
      .btns button:hover{color:#fff}
      .row{margin-top:7px}
      .top{display:flex;justify-content:space-between;gap:10px}
      .bar{height:6px;border-radius:3px;background:rgba(255,255,255,.12);margin-top:3px;overflow:hidden}
      .fill{height:100%;border-radius:3px;transition:width .4s}
      .sub{color:#a1a1aa;font-size:11px}
      .err{color:#fca5a5;margin-top:6px}
      .mini .body{display:none}
`;
  root.innerHTML = `<style>${CSS}</style>
    <div class="box" id="box">
      <div class="head" id="drag">
        <span><b id="title">Uso do Claude</b></span>
        <span class="btns"><button id="pop" title="Janela flutuante sempre visível">⧉</button><button id="ref" title="Atualizar">↻</button><button id="min" title="Minimizar">—</button></span>
      </div>
      <div class="body" id="body"><div class="sub" style="margin-top:6px">Carregando…</div></div>
    </div>`;
  document.documentElement.appendChild(host);

  const $ = (id) => root.getElementById(id);
  const box = $('box');
  let minimized = store.get('min', false);
  const applyMin = () => box.classList.toggle('mini', minimized);
  applyMin();
  $('min').addEventListener('click', () => { minimized = !minimized; store.set('min', minimized); applyMin(); renderTitle(); });
  $('ref').addEventListener('click', () => refresh());

  // arrastar
  $('drag').addEventListener('mousedown', (e) => {
    if (e.target.closest('button')) return;
    const r = host.getBoundingClientRect();
    const dx = e.clientX - r.left, dy = e.clientY - r.top;
    const move = (ev) => {
      const w = host.offsetWidth, h = host.offsetHeight;
      const left = Math.min(Math.max(0, ev.clientX - dx), innerWidth - w);
      const top = Math.min(Math.max(0, ev.clientY - dy), innerHeight - h);
      host.style.right = (innerWidth - left - w) + 'px';
      host.style.bottom = (innerHeight - top - h) + 'px';
    };
    const up = () => {
      removeEventListener('mousemove', move); removeEventListener('mouseup', up);
      store.set('pos', { right: parseFloat(host.style.right), bottom: parseFloat(host.style.bottom) });
    };
    addEventListener('mousemove', move); addEventListener('mouseup', up);
    e.preventDefault();
  });

  // ---------- helpers ----------
  const color = (p) => (p >= 85 ? '#ef4444' : p >= 60 ? '#f59e0b' : '#22c55e');
  function fmtReset(iso) {
    const ms = new Date(iso).getTime() - Date.now();
    if (!isFinite(ms)) return '';
    if (ms <= 0) return 'resetando…';
    const m = Math.round(ms / 60000);
    if (m < 60) return `reseta em ${m}min`;
    const h = Math.floor(m / 60);
    if (h < 24) return `reseta em ${h}h${String(m % 60).padStart(2, '0')}`;
    return 'reseta ' + new Date(iso).toLocaleDateString('pt-BR', { weekday: 'short', hour: '2-digit', minute: '2-digit' });
  }
  function projection(key, util, iso) {
    const w = WINDOW_MS[key];
    if (!w || !iso) return null;
    const elapsed = Date.now() - (new Date(iso).getTime() - w);
    if (elapsed < w * 0.05) return null; // cedo demais pra projetar
    return Math.round(util / (elapsed / w));
  }

  let last = null;
  function renderTitle() {
    const f = last?.five_hour?.utilization;
    $('title').textContent = minimized && typeof f === 'number' ? `Claude · ${Math.round(f)}%` : 'Uso do Claude';
  }

  let pipBody = null;
  let lastErr = null;

  function fillBody(doc, body, data, errMsg) {
    body.textContent = '';
    const el = (tag, cls) => { const n = doc.createElement(tag); if (cls) n.className = cls; return n; };
    if (errMsg) { const d = el('div', 'err'); d.textContent = errMsg; body.appendChild(d); return; }
    if (!data) { const d = el('div', 'sub'); d.style.marginTop = '6px'; d.textContent = 'Carregando…'; body.appendChild(d); return; }
    const keys = Object.keys(data).filter((k) => data[k] && typeof data[k] === 'object' && typeof data[k].utilization === 'number');
    keys.sort((a, b) => (a === 'five_hour' ? -1 : b === 'five_hour' ? 1 : a === 'seven_day' ? -1 : b === 'seven_day' ? 1 : a.localeCompare(b)));
    for (const k of keys) {
      const { utilization: u, resets_at } = data[k];
      const pct = Math.max(0, Math.min(100, u));
      const row = el('div', 'row');
      const top = el('div', 'top');
      const l = el('span'); l.textContent = LABELS[k] || k.replace(/_/g, ' ');
      const r = el('b'); r.textContent = `${Math.round(u)}%`; r.style.color = color(u);
      top.append(l, r);
      const bar = el('div', 'bar');
      const fill = el('div', 'fill');
      fill.style.width = pct + '%'; fill.style.background = color(u);
      bar.appendChild(fill);
      const sub = el('div', 'sub');
      const proj = projection(k, u, resets_at);
      sub.textContent = [resets_at ? fmtReset(resets_at) : '', proj !== null && proj > 100 ? `⚠ ritmo atual: ~${proj}%` : ''].filter(Boolean).join(' · ');
      row.append(top, bar, sub);
      body.appendChild(row);
    }
    if (!keys.length) { const d = el('div', 'sub'); d.textContent = 'Sem dados de uso para este plano.'; body.appendChild(d); }
    const t = el('div', 'sub'); t.style.marginTop = '6px';
    t.textContent = 'atualizado ' + new Date().toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    body.appendChild(t);
  }

  function paint() {
    for (const b of [$('body'), pipBody]) if (b) fillBody(b.ownerDocument, b, last, lastErr);
    renderTitle();
  }
  function render(data) { last = data; lastErr = null; paint(); }
  function renderError(msg) { lastErr = msg; paint(); }

  // Janela flutuante: fica por cima de TODOS os apps (Document Picture-in-Picture, Chrome 116+).
  $('pop').addEventListener('click', async () => {
    if (!('documentPictureInPicture' in window)) { renderError('Este Chrome não suporta janela flutuante (precisa do 116 ou mais novo).'); return; }
    if (pipBody) { try { window.documentPictureInPicture.window?.close(); } catch {} return; }
    try {
      const pip = await window.documentPictureInPicture.requestWindow({ width: 240, height: 175 });
      const st = pip.document.createElement('style');
      st.textContent = CSS + 'html,body{margin:0;background:#18181b}.box{border:0;border-radius:0;min-height:100vh;box-sizing:border-box;box-shadow:none}';
      pip.document.head.appendChild(st);
      const b = pip.document.createElement('div'); b.className = 'box';
      const head = pip.document.createElement('div'); head.className = 'head';
      const t = pip.document.createElement('b'); t.textContent = 'Uso do Claude'; head.appendChild(t);
      pipBody = pip.document.createElement('div'); pipBody.className = 'body';
      b.append(head, pipBody); pip.document.body.appendChild(b);
      pip.addEventListener('pagehide', () => { pipBody = null; });
      paint();
    } catch (e) { renderError('Janela flutuante falhou: ' + (e.message || e)); }
  });

  // ---------- dados ----------
  async function getOrgId() {
    const m = document.cookie.match(/(?:^|;\s*)lastActiveOrg=([^;]+)/);
    if (m) return decodeURIComponent(m[1]);
    const res = await fetch('/api/organizations', { credentials: 'include' });
    if (!res.ok) throw new Error('organizations ' + res.status);
    const orgs = await res.json();
    const pick = orgs.find((o) => (o.capabilities || []).includes('chat')) || orgs[0];
    if (!pick) throw new Error('nenhuma organização');
    return pick.uuid;
  }

  let busy = false;
  async function refresh() {
    if (busy) return; busy = true;
    try {
      const org = await getOrgId();
      const res = await fetch(`/api/organizations/${encodeURIComponent(org)}/usage`, { credentials: 'include' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      render(await res.json());
    } catch (e) {
      renderError('Erro ao ler uso: ' + (e.message || e));
    } finally { busy = false; }
  }

  refresh();
  setInterval(() => { if (!document.hidden || pipBody) refresh(); }, REFRESH_MS);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
})();
