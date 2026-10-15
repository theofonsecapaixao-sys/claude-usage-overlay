const body = document.getElementById('body');
let pipBody = null;
async function paint() {
  const { usage, usageAt, error } = await chrome.storage.local.get(['usage', 'usageAt', 'error']);
  for (const b of [body, pipBody]) if (b) CUW.fillBody(b.ownerDocument, b, usage, error, usageAt);
}
chrome.storage.onChanged.addListener(paint);
setInterval(paint, 30000); // mantém a contagem regressiva em dia
document.getElementById('ref').addEventListener('click', () => chrome.runtime.sendMessage({ type: 'refresh' }));

// "Por cima de tudo": Document Picture-in-Picture (Chrome 116+). Esta janelinha precisa ficar aberta (pode minimizar).
document.getElementById('pin').addEventListener('click', async () => {
  if (!('documentPictureInPicture' in window)) { body.textContent = 'Este Chrome não suporta fixar por cima (precisa do 116+).'; return; }
  if (pipBody) { try { window.documentPictureInPicture.window?.close(); } catch {} return; }
  try {
    const pip = await window.documentPictureInPicture.requestWindow({ width: 250, height: 190 });
    const css = await (await fetch(chrome.runtime.getURL('styles.css'))).text();
    const st = pip.document.createElement('style'); st.textContent = css; pip.document.head.appendChild(st);
    const box = pip.document.createElement('div'); box.className = 'box';
    const head = pip.document.createElement('div'); head.className = 'head';
    const t = pip.document.createElement('b'); t.textContent = 'Uso do Claude'; head.appendChild(t);
    pipBody = pip.document.createElement('div');
    box.append(head, pipBody); pip.document.body.appendChild(box);
    pip.addEventListener('pagehide', () => { pipBody = null; });
    paint();
  } catch (e) { body.textContent = 'Falhou: ' + (e.message || e); }
});

chrome.runtime.sendMessage({ type: 'refresh' });
paint();
