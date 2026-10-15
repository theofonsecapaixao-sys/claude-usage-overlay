const body = document.getElementById('body');
async function paint() {
  const { usage, usageAt, error } = await chrome.storage.local.get(['usage', 'usageAt', 'error']);
  CUW.fillBody(document, body, usage, error, usageAt);
}
chrome.storage.onChanged.addListener(paint);
document.getElementById('ref').addEventListener('click', () => chrome.runtime.sendMessage({ type: 'refresh' }));
document.getElementById('win').addEventListener('click', () => {
  chrome.windows.create({ url: chrome.runtime.getURL('float.html'), type: 'popup', width: 270, height: 235 });
  window.close();
});
chrome.runtime.sendMessage({ type: 'refresh' });
paint();
