'use strict';
const $ = id => document.getElementById(id);
const audio = globalThis.otonotanaDesktop?.audio || $('audio');
let rows = [], selected = 0, audioURL = null;
const storageKey = 'otonotana-projects-v2';
const newID = () => globalThis.crypto?.randomUUID?.() || String(Date.now()) + Math.random().toString(16).slice(2);
let activeID = newID(), projects = [], history = new EditorState.History(), expectedAudio = '';
function snapshot() { return { version: 1, name: $('songName').value, rows, selected, audioFilename: expectedAudio }; }
function historyControls() { $('undo').disabled = !history.past.length; $('redo').disabled = !history.future.length; }
function checkpoint() { history.push(snapshot()); historyControls(); }
function projectOptions() {
  $('projects').replaceChildren(...projects.map(draft => { const option = document.createElement('option'); option.value = draft.id; option.textContent = draft.name || '名前未設定の曲'; return option; }));
  $('projects').value = activeID;
}
function status(text, error = false) { $('status').textContent = text; $('status').classList.toggle('error', error); }
function persist() {
  try {
    const draft = { ...snapshot(), id: activeID };
    const index = projects.findIndex(d => d.id === activeID);
    if (index < 0) projects.push(draft); else projects[index] = draft;
    localStorage.setItem(storageKey, JSON.stringify({ version: 2, activeID, drafts: projects }));
    projectOptions(); historyControls();
  }
  catch { status('自動保存が使えません。「下書きを保存」で編集内容を保存してください。', true); }
}
function activeIndex() {
  let index = -1, latest = -1;
  rows.forEach((row, i) => { if (row.seconds !== null && row.seconds <= audio.currentTime && row.seconds >= latest) { latest = row.seconds; index = i; } });
  return index;
}
function highlight() {
  const active = activeIndex();
  [...$('rows').children].forEach((el, i) => { el.classList.toggle('selected', i === selected); el.classList.toggle('active', i === active && Boolean(audioURL)); });
  $('clock').textContent = LyricsCore.timestamp(audio.currentTime || 0);
  $('toggle').textContent = audio.paused ? '再生' : '一時停止';
}
function action(label, handler) { const b = document.createElement('button'); b.textContent = label; b.type = 'button'; b.onclick = handler; return b; }
function render() {
  const area = $('rows'); area.replaceChildren();
  $('count').textContent = `${rows.filter(r => r.seconds !== null).length} / ${rows.length}行 設定済み`;
  $('stamp').disabled = !rows.length;
  if (!rows.length) { const empty = document.createElement('div'); empty.className = 'empty'; empty.textContent = '左側から歌詞を追加してください。'; area.append(empty); return; }
  rows.forEach((row, index) => {
    const el = document.createElement('div'); el.className = 'row';
    const number = document.createElement('span'); number.className = 'number'; number.textContent = index + 1;
    const seconds = document.createElement('input'); seconds.type = 'number'; seconds.min = '0'; seconds.step = '0.001'; seconds.placeholder = '秒数'; seconds.value = row.seconds ?? ''; seconds.setAttribute('aria-label', `${index + 1}行目の開始秒数`);
    seconds.onchange = () => {
      const value = seconds.value === '' ? null : Number(seconds.value);
      if (value !== null && (!Number.isFinite(value) || value < 0)) { seconds.value = row.seconds ?? ''; status('0以上の秒数を入力してください。', true); return; }
      checkpoint(); row.seconds = value; persist(); $('count').textContent = `${rows.filter(r => r.seconds !== null).length} / ${rows.length}行 設定済み`; highlight();
    };
    const text = document.createElement('input'); text.value = row.text; text.placeholder = '（間奏）'; text.setAttribute('aria-label', `${index + 1}行目の歌詞`);
    let beforeTextEdit, committedTextEdit = false;
    text.onfocus = () => { beforeTextEdit = snapshot(); committedTextEdit = false; };
    text.oninput = () => {
      if (!committedTextEdit) { history.push(beforeTextEdit || snapshot()); committedTextEdit = true; }
      row.text = text.value; persist();
    };
    const adjustments = document.createElement('div'); adjustments.className = 'timing-controls';
    for (const step of [0.1, 0.01, 0.001]) {
      const pair = document.createElement('span'); pair.className = 'timing-step';
      const earlier = action('−', () => adjust(index, -step)), later = action('＋', () => adjust(index, step));
      earlier.dataset.adjust = `-${step}`; later.dataset.adjust = String(step);
      earlier.setAttribute('aria-label', `${index + 1}行目を${step}秒早める`); later.setAttribute('aria-label', `${index + 1}行目を${step}秒遅らせる`);
      earlier.title = `${step}秒早める`; later.title = `${step}秒遅らせる`;
      const unit = document.createElement('span'); unit.className = 'unit'; unit.textContent = `${step}秒`;
      pair.append(earlier, unit, later); adjustments.append(pair);
    }
    const buttons = document.createElement('div'); buttons.className = 'actions';
    const selection = document.createElement('div'); selection.className = 'row-selection';
    const choose = action('選択', () => { selected = index; highlight(); }); choose.className = 'select-row';
    selection.append(choose, action('今の時刻', () => { selected = index; stamp(false); }));
    const playback = document.createElement('div'); playback.className = 'row-playback';
    const play = action('ここから再生', () => preview(index)); play.className = 'preview-row';
    const stop = action('停止', () => { audio.pause(); highlight(); }); stop.className = 'stop-row';
    playback.append(play, stop);
    const remove = action('削除', () => { if (!row.text || confirm('この歌詞の行を削除しますか？')) { checkpoint(); rows.splice(index, 1); selected = Math.min(selected, Math.max(0, rows.length - 1)); persist(); render(); } });
    remove.className = 'delete-row'; buttons.append(selection, playback, remove);
    el.append(number, seconds, text, adjustments, buttons); area.append(el);
  }); highlight(); historyControls();
}
function adjust(index, delta) {
  if (rows[index].seconds === null) { status('先にこの行の時刻を設定してください。', true); return; }
  checkpoint(); rows[index].seconds = Math.max(0, Math.round(rows[index].seconds * 1000) + Math.round(delta * 1000)) / 1000;
  persist(); render();
}
function stamp(advance = true) {
  if (!audioURL || !Number.isFinite(audio.duration)) { status('先に再生できる音楽ファイルを開いてください。時刻の手入力もできます。', true); return; }
  if (!rows[selected]) return;
  checkpoint(); rows[selected].seconds = Math.round(audio.currentTime * 1000) / 1000;
  if (advance) selected = Math.min(selected + 1, rows.length - 1);
  persist(); render();
  $('rows').children[selected]?.scrollIntoView({ block: 'nearest' });
}
async function preview(index) {
  if (!audioURL || !Number.isFinite(audio.duration)) { status('先に音楽ファイルを開いてください。', true); return; }
  const seconds = rows[index].seconds;
  if (seconds === null || seconds >= audio.duration) { status('この行に曲の長さより短い時刻を設定してください。', true); return; }
  audio.currentTime = seconds; selected = index; highlight();
  try { await audio.play(); } catch (error) { status(globalThis.otonotanaDesktop ? error.message : 'この音源をブラウザで再生できません。秒数は手入力できます。', true); }
}
async function download(content, extension, type) {
  const filename = ($('songName').value.trim() || 'lyrics').replace(/[<>:"/\\|?*]/g, '_') + extension;
  if (globalThis.otonotanaDesktop) return await globalThis.otonotanaDesktop.save(content, filename);
  const blob = new Blob([content], { type }); const url = URL.createObjectURL(blob); const link = document.createElement('a');
  link.href = url; link.download = filename;
  document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 60000);
  return true;
}
$('audioFile').onchange = event => {
  const file = event.target.files[0]; if (!file) return;
  if (expectedAudio && expectedAudio !== file.name && rows.length && !confirm('前に選んだ音楽と名前が違います。この下書きに使いますか？ 新しい曲は「新しい曲」から始められます。')) { event.target.value = ''; return; }
  expectedAudio = file.name;
  if (audioURL) URL.revokeObjectURL(audioURL);
  audioURL = URL.createObjectURL(file); audio.src = audioURL;
  $('audioName').textContent = file.name;
  if (!$('songName').value) $('songName').value = file.name.replace(/\.[^.]+$/, '');
  persist(); status('音楽を開きました。');
};
let choosingDesktopAudio = false;
async function openDesktopAudio(fixture) {
  if (choosingDesktopAudio) return false;
  choosingDesktopAudio = true;
  try {
    const chosen = await globalThis.otonotanaDesktop.chooseAudio(fixture);
    if (!chosen) return false;
    if (expectedAudio && expectedAudio !== chosen.filename && rows.length && !confirm('前に選んだ音楽と名前が違います。この下書きに使いますか？')) return false;
    await globalThis.otonotanaDesktop.loadAudio(chosen.token);
    if (audioURL) URL.revokeObjectURL(audioURL);
    audioURL = 'native:' + chosen.token; expectedAudio = chosen.filename;
    $('audioName').textContent = chosen.filename;
    if (!$('songName').value) $('songName').value = chosen.filename.replace(/\.[^.]+$/, '');
    persist(); status('音楽を開きました。'); return true;
  } catch (error) { status(error.message, true); return false; }
  finally { choosingDesktopAudio = false; }
}
audio.addEventListener('timeupdate', highlight);
audio.addEventListener('error', () => status(audio.error?.message || 'この音源をブラウザで再生できません。秒数は手入力できます。', true));
$('toggle').onclick = async () => { try { if (audio.paused) await audio.play(); else audio.pause(); } catch (error) { status(globalThis.otonotanaDesktop ? error.message : '音源を選び、再生できるか確認してください。', true); } };
$('back').onclick = () => { audio.currentTime = Math.max(0, audio.currentTime - 3); };
$('append').onclick = () => {
  if (!$('paste').value.trim()) { status('歌詞を貼り付けてください。', true); return; }
  checkpoint(); const first = rows.length; rows.push(...$('paste').value.trim().split(/\r?\n/).map(text => ({ seconds: null, text })));
  $('paste').value = ''; selected = first; persist(); render();
};
$('blank').onclick = () => {
  checkpoint();
  const index = rows.length ? Math.min(selected + 1, rows.length) : 0;
  rows.splice(index, 0, { seconds: null, text: '' }); selected = index;
  persist(); render();
  const inserted = $('rows').children[index];
  inserted?.scrollIntoView({ block: 'nearest' });
  inserted?.querySelector('input[placeholder="（間奏）"]')?.focus({ preventScroll: true });
};
$('stamp').onclick = () => stamp();
let beforeNameEdit, committedNameEdit = false;
$('songName').onfocus = () => { beforeNameEdit = snapshot(); committedNameEdit = false; };
$('songName').oninput = () => {
  if (!committedNameEdit) { history.push(beforeNameEdit || snapshot()); committedNameEdit = true; }
  persist();
};
$('export').onclick = async () => {
  try { const content = LyricsCore.serialize(rows, audioURL ? audio.duration : undefined); const saved = await download(content, '.lrc', 'text/plain;charset=utf-8'); status(saved ? 'LRCを保存しました。音楽ファイルと一緒にiPhoneへ渡してください。' : '保存をキャンセルしました。'); }
  catch (error) { status(error.message, true); }
};
$('draft').onclick = async () => {
  try { const saved = await download(JSON.stringify({ version: 1, name: $('songName').value, rows }, null, 2), '.json', 'application/json'); status(saved ? '編集用の下書きを保存しました。' : '保存をキャンセルしました。'); }
  catch (error) { status(error.message, true); }
};
function validateDraft(data) {
  return EditorState.validateDraft(data);
}
$('lrcFile').onchange = async event => {
  const file = event.target.files[0]; if (!file) return;
  try {
    const content = await file.text();
    let name = file.name.replace(/\.[^.]+$/, ''), imported;
    if (file.name.toLowerCase().endsWith('.json')) {
      const raw = JSON.parse(content);
      if (raw.version === 2) {
        const book = EditorState.readBook(raw, newID); persist();
        for (const draft of book.drafts) projects.push({ ...draft, id: newID() });
        activeID = projects.at(-book.drafts.length).id;
        loadProject(activeID); status('下書き一覧を追加しました。'); return;
      }
      const data = validateDraft(raw); imported = data.rows; name = data.name;
    }
    else { imported = LyricsCore.parse(content); if (!imported.length) throw new Error('時刻付きの歌詞が見つかりません。'); }
    if (rows.length && !confirm('現在の編集内容を読み込んだ歌詞に置き換えますか？ 必要なら先に下書きを保存してください。')) return;
    checkpoint(); rows = imported; $('songName').value = name; selected = 0; persist(); render(); status('歌詞を読み込みました。対応する音楽ファイルを選んで確認してください。');
  } catch (error) { status(error.message, true); }
  finally { event.target.value = ''; }
};
function closeAudio() {
  audio.pause(); audio.removeAttribute('src'); audio.load();
  if (audioURL) URL.revokeObjectURL(audioURL); audioURL = null; $('audioFile').value = ''; $('audioName').textContent = 'ファイル未選択'; persist(); render(); highlight(); status('新しい曲の編集を始められます。');
}
function loadProject(id) {
  const draft = projects.find(d => d.id === id); if (!draft) return;
  activeID = id; rows = JSON.parse(JSON.stringify(draft.rows)); selected = Math.min(draft.selected || 0, Math.max(0, rows.length - 1));
  expectedAudio = draft.audioFilename || ''; $('songName').value = draft.name; $('paste').value = '';
  history = new EditorState.History(); closeAudio(); persist(); render();
}
function newProject() { persist(); activeID = newID(); projects.push({ version: 1, id: activeID, name: '', rows: [] }); loadProject(activeID); }
$('reset').onclick = newProject; $('newProject').onclick = newProject;
$('projects').onchange = event => { const id = event.target.value; persist(); loadProject(id); status('下書きを切り替えました。対応する音楽を選んでください。'); };
$('deleteProject').onclick = () => {
  if (!confirm('この下書きを削除しますか？ この操作は元に戻せません。音楽ファイルは削除しません。')) return;
  projects = projects.filter(d => d.id !== activeID);
  if (!projects.length) projects.push({ version: 1, id: newID(), name: '', rows: [] });
  loadProject(projects[0].id);
};
$('exportProjects').onclick = async () => {
  try { persist(); const saved = await download(JSON.stringify({ version: 2, activeID, drafts: projects }, null, 2), '.json', 'application/json'); status(saved ? '全下書きを保存しました。' : '保存をキャンセルしました。'); }
  catch (error) { status(error.message, true); }
};
function restoreState(state) { if (!state) return; rows = state.rows; selected = state.selected || 0; $('songName').value = state.name; expectedAudio = state.audioFilename || ''; persist(); render(); }
$('undo').onclick = () => restoreState(history.undo(snapshot()));
$('redo').onclick = () => restoreState(history.redo(snapshot()));
$('shift').onclick = () => {
  try {
    const delta = Number($('shiftSeconds').value);
    if (!$('shiftSeconds').value || !rows.length) throw new Error('歌詞とずらす秒数を確認してください。');
    const shifted = LyricsCore.shift(rows, delta, $('shiftTarget').value === 'selected' ? selected : 0);
    checkpoint(); rows = shifted; persist(); render(); status('時刻をまとめて調整しました。元に戻すこともできます。');
  } catch (error) { status(error.message, true); }
};
document.addEventListener('keydown', event => {
  if (event.ctrlKey && event.key === 'Enter') { event.preventDefault(); stamp(); }
  if (event.ctrlKey && !event.target.matches('input,textarea') && ['z', 'y'].includes(event.key.toLowerCase())) {
    event.preventDefault(); (event.key.toLowerCase() === 'y' || event.shiftKey ? $('redo') : $('undo')).click();
  }
});
try {
  const saved = localStorage.getItem(storageKey) || localStorage.getItem('otonotana-lyrics-v1');
  if (saved) { const book = EditorState.readBook(JSON.parse(saved), newID); projects = book.drafts; loadProject(book.activeID); status('前回の下書きを復元しました。音楽ファイルをもう一度選んでください。'); }
  else { projects = [{ version: 1, id: activeID, name: '', rows: [] }]; persist(); }
}
catch { status('下書きを復元できません。保存した下書きファイルから読み込めます。', true); }
render();
