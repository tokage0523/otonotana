(() => {
  'use strict';
  if (!window.chrome?.webview) return;
  let nextID = 0;
  const pending = new Map();
  Object.defineProperty(window, 'otonotanaDesktop', { value: Object.freeze({
    save(content, filename) {
      const id = ++nextID;
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        window.chrome.webview.postMessage({ kind: 'save', id, filename, content });
      });
    }
  }) });
  window.chrome.webview.addEventListener('message', event => {
    const message = event.data;
    if (message?.kind !== 'save-result' || !pending.has(message.id)) return;
    const callback = pending.get(message.id); pending.delete(message.id);
    if (message.error) callback.reject(new Error(message.error));
    else callback.resolve(message.saved);
  });
  document.addEventListener('DOMContentLoaded', () => {
    document.title = '音の棚 · 歌詞エディター';
    for (const element of document.querySelectorAll('.hint')) {
      if (element.textContent.includes('このブラウザに自動保存')) element.textContent = element.textContent.replace('このブラウザに自動保存', 'このアプリに自動保存');
      if (element.textContent.includes('ブラウザで再生できない')) element.textContent = element.textContent.replace('ブラウザで再生できない', 'このアプリで再生できない');
    }
    const note = document.createElement('p'); note.className = 'hint'; note.id = 'desktop-migration';
    note.textContent = 'ブラウザー版の下書きは、そちらで「全下書きを保存」して、このアプリの「保存済みの歌詞を開く」から読み込めます。';
    document.getElementById('projects').closest('section').append(note);
  });
})();

