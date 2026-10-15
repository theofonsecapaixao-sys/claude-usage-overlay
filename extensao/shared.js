// Desenho do painel, usado pelo popup e pela janelinha.
(() => {
  const LABELS = { five_hour: 'Sessão (5h)', seven_day: 'Semana', seven_day_opus: 'Semana · Opus', seven_day_sonnet: 'Semana · Sonnet' };
  const WINDOW_MS = { five_hour: 5 * 3600e3, seven_day: 7 * 24 * 3600e3 };
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
    if (elapsed < w * 0.05) return null;
    return Math.round(util / (elapsed / w));
  }
  function fillBody(doc, body, data, errMsg, at) {
    body.textContent = '';
    const el = (tag, cls) => { const n = doc.createElement(tag); if (cls) n.className = cls; return n; };
    if (errMsg) {
      const d = el('div', 'err');
      d.textContent = errMsg.startsWith('login:') ? 'Não consegui ler seu uso. Entre no claude.ai neste Chrome e tente de novo.' : 'Erro ao ler uso: ' + errMsg;
      body.appendChild(d);
      if (!data) return;
    }
    if (!data) { const d = el('div', 'sub'); d.style.marginTop = '6px'; d.textContent = 'Carregando…'; body.appendChild(d); return; }
    const keys = Object.keys(data).filter((k) => data[k] && typeof data[k] === 'object' && typeof data[k].utilization === 'number');
    keys.sort((a, b) => (a === 'five_hour' ? -1 : b === 'five_hour' ? 1 : a === 'seven_day' ? -1 : b === 'seven_day' ? 1 : a.localeCompare(b)));
    for (const k of keys) {
      const { utilization: u, resets_at } = data[k];
      const row = el('div', 'row');
      const top = el('div', 'top');
      const l = el('span'); l.textContent = LABELS[k] || k.replace(/_/g, ' ');
      const r = el('b'); r.textContent = `${Math.round(u)}%`; r.style.color = color(u);
      top.append(l, r);
      const bar = el('div', 'bar');
      const fill = el('div', 'fill'); fill.style.width = Math.max(0, Math.min(100, u)) + '%'; fill.style.background = color(u);
      bar.appendChild(fill);
      const sub = el('div', 'sub');
      const proj = projection(k, u, resets_at);
      sub.textContent = [resets_at ? fmtReset(resets_at) : '', proj !== null && proj > 100 ? `⚠ ritmo atual: ~${proj}%` : ''].filter(Boolean).join(' · ');
      row.append(top, bar, sub);
      body.appendChild(row);
    }
    if (!keys.length) { const d = el('div', 'sub'); d.textContent = 'Sem dados de uso para este plano.'; body.appendChild(d); }
    if (at) { const t = el('div', 'sub'); t.style.marginTop = '6px'; t.textContent = 'atualizado ' + new Date(at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }); body.appendChild(t); }
  }
  window.CUW = { fillBody };
})();
