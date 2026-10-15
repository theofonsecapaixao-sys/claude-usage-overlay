// Busca o uso a cada minuto e guarda em chrome.storage. Não precisa de aba do claude.ai aberta:
// o fetch usa a sessão que o Chrome já tem (permissão só para https://claude.ai/*).
const API = 'https://claude.ai/api';

async function getOrg(force) {
  if (!force) {
    const { orgId } = await chrome.storage.local.get('orgId');
    if (orgId) return orgId;
  }
  const res = await fetch(`${API}/organizations`, { credentials: 'include' });
  if (!res.ok) throw new Error('login:' + res.status);
  const orgs = await res.json();
  const pick = orgs.find((o) => (o.capabilities || []).includes('chat')) || orgs[0];
  if (!pick) throw new Error('nenhuma organização encontrada');
  await chrome.storage.local.set({ orgId: pick.uuid });
  return pick.uuid;
}

async function fetchUsage(org) {
  return fetch(`${API}/organizations/${encodeURIComponent(org)}/usage`, { credentials: 'include' });
}

function badge(data) {
  const f = data?.five_hour?.utilization;
  if (typeof f !== 'number') { chrome.action.setBadgeText({ text: '' }); return; }
  const w = data?.seven_day?.utilization;
  const worst = Math.max(f, typeof w === 'number' ? w : 0);
  chrome.action.setBadgeText({ text: String(Math.round(f)) });
  chrome.action.setBadgeBackgroundColor({ color: worst >= 85 ? '#dc2626' : worst >= 60 ? '#d97706' : '#16a34a' });
  chrome.action.setTitle({ title: `Uso do Claude — sessão 5h: ${Math.round(f)}%` + (typeof w === 'number' ? ` · semana: ${Math.round(w)}%` : '') });
}

// Overlay nativo (usage-overlay.ps1) escuta só em 127.0.0.1. Se não estiver aberto, a falha é ignorada.
function pushToOverlay(data) {
  fetch('http://127.0.0.1:47831/usage', {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain' },
    body: JSON.stringify({ usage: data, at: Date.now() }),
  }).catch(() => {});
}

let running = false;
async function refresh() {
  if (running) return;
  running = true;
  try {
    let res = await fetchUsage(await getOrg(false));
    if (res.status === 403 || res.status === 404) res = await fetchUsage(await getOrg(true)); // org mudou
    if (!res.ok) throw new Error(res.status === 401 || res.status === 403 ? 'login:' + res.status : 'HTTP ' + res.status);
    const data = await res.json();
    await chrome.storage.local.set({ usage: data, usageAt: Date.now(), error: null });
    badge(data);
    pushToOverlay(data);
  } catch (e) {
    await chrome.storage.local.set({ error: String(e && e.message || e) });
    chrome.action.setBadgeText({ text: '!' });
    chrome.action.setBadgeBackgroundColor({ color: '#dc2626' });
  } finally {
    running = false;
  }
}

chrome.alarms.get('cuw-refresh', (a) => { if (!a) chrome.alarms.create('cuw-refresh', { periodInMinutes: 1 }); });
chrome.alarms.onAlarm.addListener((a) => { if (a.name === 'cuw-refresh') refresh(); });
chrome.runtime.onInstalled.addListener(() => { chrome.alarms.create('cuw-refresh', { periodInMinutes: 1 }); refresh(); });
chrome.runtime.onStartup.addListener(refresh);
chrome.runtime.onMessage.addListener((m) => { if (m && m.type === 'refresh') refresh(); });
