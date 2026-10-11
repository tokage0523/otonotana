'use strict';
const $ = id => document.getElementById(id);
const audio = $('audio');
let rows = [], selected = 0, audioURL = null;
const storageKey = 'otonotana-lyrics-v1';
function status(text, error = false) { $('status').textContent = text; $('status').classList.toggle('error', error); }
function persist() {
  try { localStorage.setItem(storageKey, JSON.stringify({ version: 1, name: $('songName').value, rows })); }
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
      row.seconds = value; persist(); $('count').textContent = `${rows.filter(r => r.seconds !== null).length} / ${rows.length}行 設定済み`; highlight();
    };
    const text = document.createElement('input'); text.value = row.text; text.placeholder = '（間奏）'; text.setAttribute('aria-label', `${index + 1}行目の歌詞`); text.oninput = () => { row.text = text.value; persist(); };
    const buttons = document.createElement('div'); buttons.className = 'actions';
    buttons.append(action('選択', () => { selected = index; highlight(); }),
      action('今の時刻', () => { selected = index; stamp(false); }),
      action('−0.1秒', () => adjust(index, -0.1)), action('＋0.1秒', () => adjust(index, 0.1)),
      action('ここから再生', () => preview(index)),
      action('削除', () => { if (!row.text || confirm('この歌詞の行を削除しますか？')) { rows.splice(index, 1); selected = Math.min(selected, Math.max(0, rows.length - 1)); persist(); render(); } }));
    el.append(number, seconds, text, buttons); area.append(el);
  }); highlight();
}
function adjust(index, delta) {
  if (rows[index].seconds === null) { status('先にこの行の時刻を設定してください。', true); return; }
  rows[index].seconds = Math.round(Math.max(0, rows[index].seconds + delta) * 1000) / 1000;
  persist(); render();
}
function stamp(advance = true) {
  if (!audioURL || !Number.isFinite(audio.duration)) { status('先に再生できる音楽ファイルを開いてください。時刻の手入力もできます。', true); return; }
  if (!rows[selected]) return;
  rows[selected].seconds = Math.round(audio.currentTime * 1000) / 1000;
  if (advance) selected = Math.min(selected + 1, rows.length - 1);
  persist(); render();
  $('rows').children[selected]?.scrollIntoView({ block: 'nearest' });
}
async function preview(index) {
  if (!audioURL || !Number.isFinite(audio.duration)) { status('先に音楽ファイルを開いてください。', true); return; }
  const seconds = rows[index].seconds;
  if (seconds === null || seconds >= audio.duration) { status('この行に曲の長さより短い時刻を設定してください。', true); return; }
  audio.currentTime = seconds; selected = index; highlight();
  try { await audio.play(); } catch { status('この音源をブラウザで再生できません。秒数は手入力できます。', true); }
}
function download(content, extension, type) {
  const blob = new Blob([content], { type }); const url = URL.createObjectURL(blob); const link = document.createElement('a');
  link.href = url; link.download = ($('songName').value.trim() || 'lyrics').replace(/[<>:"/\\|?*]/g, '_') + extension;
  document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 60000);
}
$('audioFile').onchange = event => {
  const file = event.target.files[0]; if (!file) return;
  if (audioURL) URL.revokeObjectURL(audioURL);
  audioURL = URL.createObjectURL(file); audio.src = audioURL;
  $('audioName').textContent = file.name;
  if (!$('songName').value) $('songName').value = file.name.replace(/\.[^.]+$/, '');
  persist(); status('音楽を開きました。');
};
audio.addEventListener('timeupdate', highlight);
audio.addEventListener('error', () => status('この音源をブラウザで再生できません。秒数は手入力できます。', true));
$('toggle').onclick = async () => { try { if (audio.paused) await audio.play(); else audio.pause(); } catch { status('音源を選び、再生できるか確認してください。', true); } };
$('back').onclick = () => { audio.currentTime = Math.max(0, audio.currentTime - 3); };
$('append').onclick = () => {
  if (!$('paste').value.trim()) { status('歌詞を貼り付けてください。', true); return; }
  const first = rows.length; rows.push(...$('paste').value.trim().split(/\r?\n/).map(text => ({ seconds: null, text })));
  $('paste').value = ''; selected = first; persist(); render();
};
$('blank').onclick = () => { rows.push({ seconds: null, text: '' }); selected = rows.length - 1; persist(); render(); };
$('stamp').onclick = () => stamp();
$('songName').oninput = persist;
$('export').onclick = () => {
  try { const content = LyricsCore.serialize(rows, audioURL ? audio.duration : undefined); download(content, '.lrc', 'text/plain;charset=utf-8'); status('LRCを保存しました。音楽ファイルと一緒にiPhoneへ渡してください。'); }
  catch (error) { status(error.message, true); }
};
$('draft').onclick = () => { download(JSON.stringify({ version: 1, name: $('songName').value, rows }, null, 2), '.json', 'application/json'); status('編集用の下書きを保存しました。'); };
function validateDraft(data) {
  if (data.version !== 1 || !Array.isArray(data.rows) || typeof data.name !== 'string') throw new Error('下書きの形式が違います。');
  if (!data.rows.every(r => r && typeof r.text === 'string' && !/[\r\n]/.test(r.text) && (r.seconds === null || (Number.isFinite(r.seconds) && r.seconds >= 0)))) throw new Error('下書きの歌詞・時刻を読み込めません。');
  return data;
}
$('lrcFile').onchange = async event => {
  const file = event.target.files[0]; if (!file) return;
  try {
    const content = await file.text();
    let name = file.name.replace(/\.[^.]+$/, ''), imported;
    if (file.name.toLowerCase().endsWith('.json')) { const data = validateDraft(JSON.parse(content)); imported = data.rows; name = data.name; }
    else { imported = LyricsCore.parse(content); if (!imported.length) throw new Error('時刻付きの歌詞が見つかりません。'); }
    if (rows.length && !confirm('現在の編集内容を読み込んだ歌詞に置き換えますか？ 必要なら先に下書きを保存してください。')) return;
    rows = imported; $('songName').value = name; selected = 0; persist(); render(); status('歌詞を読み込みました。対応する音楽ファイルを選んで確認してください。');
  } catch (error) { status(error.message, true); }
  finally { event.target.value = ''; }
};
$('reset').onclick = () => {
  if (rows.length && !confirm('新しい曲の編集を始めますか？ 必要なら先にLRCまたは下書きを保存してください。')) return;
  rows = []; selected = 0; $('songName').value = ''; $('paste').value = ''; audio.pause(); audio.removeAttribute('src'); audio.load();
  if (audioURL) URL.revokeObjectURL(audioURL); audioURL = null; $('audioFile').value = ''; $('audioName').textContent = 'ファイル未選択'; persist(); render(); highlight(); status('新しい曲の編集を始められます。');
};
document.addEventListener('keydown', event => { if (event.ctrlKey && event.key === 'Enter') { event.preventDefault(); stamp(); } });
try { const saved = localStorage.getItem(storageKey); if (saved) { const data = validateDraft(JSON.parse(saved)); rows = data.rows; $('songName').value = data.name; status('前回の下書きを復元しました。音楽ファイルをもう一度選んでください。'); } }
catch { status('下書きを復元できません。保存した下書きファイルから読み込めます。', true); }
render();
