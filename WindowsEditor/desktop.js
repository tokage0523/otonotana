(() => {
  'use strict';
  if (!window.chrome?.webview) return;
  let nextID = 0;
  const pending = new Map();
  let state = { position: 0, duration: 0, paused: true, volume: 1, error: null };
  function request(kind, values = {}) {
    const id = ++nextID;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      window.chrome.webview.postMessage({ kind, id, ...values });
    });
  }
  function failed(error) { state.error = error.message; nativeAudio.dispatchEvent(new Event('error')); }
  class WindowsAudio extends EventTarget {
    get duration() { return state.duration || NaN; }
    get currentTime() { return state.position; }
    set currentTime(seconds) {
      state.position = seconds;
      request('seek-audio', { seconds }).then(applyState).catch(failed);
    }
    get paused() { return state.paused; }
    get error() { return state.error ? { message: state.error } : null; }
    get volume() { return state.volume; }
    set volume(volume) { state.volume = volume; request('volume-audio', { volume }).then(applyState).catch(failed); }
    async play() { applyState(await request('play-audio')); }
    pause() { state.paused = true; request('pause-audio').then(applyState).catch(failed); }
    removeAttribute() { /* Native close happens in load(), matching the editor's reset sequence. */ }
    load() { state = { position: 0, duration: 0, paused: true, volume: state.volume, error: null }; request('close-audio').then(applyState).catch(failed); }
  }
  const nativeAudio = new WindowsAudio();
  function applyState(next) {
    if (!next) return;
    const previous = state; state = next;
    if (previous.duration !== state.duration) nativeAudio.dispatchEvent(new Event('loadedmetadata'));
    if (state.error && state.error !== previous.error) nativeAudio.dispatchEvent(new Event('error'));
    nativeAudio.dispatchEvent(new Event('timeupdate'));
  }
  Object.defineProperty(window, 'otonotanaDesktop', { value: Object.freeze({
    save: (content, filename) => request('save', { filename, content }),
    audio: nativeAudio,
    chooseAudio: fixture => request('choose-audio', { fixture }),
    async loadAudio(token) { const value = await request('load-audio', { token }); applyState(value); return value; }
  }) });
  window.chrome.webview.addEventListener('message', event => {
    const message = event.data;
    if (message?.kind === 'audio-state') { applyState(message.value); return; }
    if (!['save-result', 'audio-result'].includes(message?.kind) || !pending.has(message.id)) return;
    const callback = pending.get(message.id); pending.delete(message.id);
    if (message.error) callback.reject(new Error(message.error));
    else callback.resolve(message.kind === 'save-result' ? message.saved : message.value);
  });
  document.addEventListener('DOMContentLoaded', () => {
    document.title = '音の棚 · 歌詞エディター';
    const audioElement = document.getElementById('audio'); audioElement.hidden = true;
    const controls = document.createElement('div'); controls.className = 'native-audio-controls';
    controls.innerHTML = '<label for="native-seek">再生位置</label><input id="native-seek" type="range" min="0" max="0" step="0.01" value="0" disabled><div class="bar"><span id="native-audio-time" class="hint">音楽を選んでください</span><label for="native-volume">音量</label><input id="native-volume" type="range" min="0" max="1" step="0.01" value="1" style="width:120px"></div>';
    controls.style.marginTop = '16px'; audioElement.after(controls);
    const seek = document.getElementById('native-seek'), time = document.getElementById('native-audio-time');
    const format = n => `${Math.floor(n / 60)}:${String(Math.floor(n % 60)).padStart(2, '0')}`;
    let scrubbing = false;
    seek.oninput = () => { scrubbing = true; time.textContent = `${format(Number(seek.value))} / ${format(state.duration)}`; };
    seek.onchange = () => { nativeAudio.currentTime = Number(seek.value); scrubbing = false; };
    seek.onpointercancel = () => { scrubbing = false; };
    document.getElementById('native-volume').oninput = event => { nativeAudio.volume = Number(event.target.value); };
    nativeAudio.addEventListener('timeupdate', () => {
      seek.disabled = !state.duration; seek.max = state.duration || 0;
      if (!scrubbing) { seek.value = state.position; time.textContent = state.duration ? `${format(state.position)} / ${format(state.duration)}` : '音楽を選んでください'; }
      document.getElementById('toggle').textContent = state.paused ? '再生' : '一時停止';
      document.getElementById('native-volume').value = state.volume;
    });
    document.getElementById('audioFile').closest('label').addEventListener('click', event => {
      event.preventDefault(); window.openDesktopAudio();
    });
    for (const element of document.querySelectorAll('.hint')) {
      if (element.textContent.includes('このブラウザに自動保存')) element.textContent = element.textContent.replace('このブラウザに自動保存', 'このアプリに自動保存');
      if (element.textContent.includes('ブラウザで再生できない')) element.textContent = element.textContent.replace('ブラウザで再生できない', 'このアプリで再生できない');
    }
    const note = document.createElement('p'); note.className = 'hint'; note.id = 'desktop-migration';
    note.textContent = 'ブラウザー版の下書きは、そちらで「全下書きを保存」して、このアプリの「保存済みの歌詞を開く」から読み込めます。';
    document.getElementById('projectHelp').append(note);
  });
})();
