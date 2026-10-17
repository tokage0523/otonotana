import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';

const root = resolve(import.meta.dirname, '..');
const output = resolve(root, 'Design/V04Verified');
const profile = resolve(root, 'Checks/BrowserProfile');
await mkdir(output, { recursive: true });
const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', '--disable-gpu', '--remote-debugging-port=0', '--no-first-run',
  '--disable-background-networking', `--user-data-dir=${profile}`, 'about:blank'
], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
let socket;
try {
  const endpoint = await new Promise((done, fail) => {
    const timer = setTimeout(() => fail(new Error('Browser startup timed out')), 15000);
    chrome.stderr.on('data', chunk => {
      const match = chunk.toString().match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (match) { clearTimeout(timer); done(match[1]); }
    });
    chrome.on('error', fail);
  });
  socket = new WebSocket(endpoint);
  await new Promise((done, fail) => { socket.addEventListener('open', done); socket.addEventListener('error', fail); });
  let sequence = 0, session;
  const pending = new Map();
  function call(method, params = {}, sessionId) {
    const id = ++sequence;
    return new Promise((done, fail) => {
      const timer = setTimeout(() => { pending.delete(id); fail(new Error(method + ' timed out')); }, 15000);
      pending.set(id, { done: value => { clearTimeout(timer); done(value); }, fail: error => { clearTimeout(timer); fail(error); } });
      socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    });
  }
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const item = pending.get(message.id); pending.delete(message.id);
      if (message.error) item.fail(new Error(JSON.stringify(message.error))); else item.done(message.result);
    }
    if (message.method === 'Page.javascriptDialogOpening') call('Page.handleJavaScriptDialog', { accept: true }, session).catch(() => {});
  });
  const target = await call('Target.createTarget', { url: pathToFileURL(resolve(root, 'PCEditor/index.html')).href });
  session = (await call('Target.attachToTarget', { targetId: target.targetId, flatten: true })).sessionId;
  const page = (method, params) => call(method, params, session);
  await page('Page.enable');
  await page('Emulation.setDeviceMetricsOverride', { width: 1180, height: 1000, deviceScaleFactor: 1, mobile: false });
  async function evaluate(expression) {
    const result = await page('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true, userGesture: true });
    if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
    return result.result.value;
  }
  async function waitFor(expression) {
    for (let attempt = 0; attempt < 100; attempt++) {
      if (await evaluate(expression)) return;
      await new Promise(done => setTimeout(done, 100));
    }
    throw new Error('Condition timed out: ' + expression);
  }
  await waitFor('document.readyState === "complete" && !!document.getElementById("projects")');
  await evaluate(`localStorage.clear();localStorage.setItem('otonotana-lyrics-v1',JSON.stringify({version:1,name:'確認用の曲',rows:[{seconds:0,text:'最初の歌詞'},{seconds:2,text:'次の歌詞'}]}));`);
  await page('Page.reload');
  await waitFor('document.getElementById("songName")?.value === "確認用の曲"');
  assert.equal(await evaluate('document.querySelectorAll("#rows .row").length'), 2);
  const clickRow = (index, label) => evaluate(`[...document.querySelectorAll('#rows .row')[${index}].querySelectorAll('button')].find(b=>b.textContent===${JSON.stringify(label)}).click()`);
  for (const [label, expected] of [['＋0.1秒','0.1'],['＋0.01秒','0.11'],['＋0.001秒','0.111'],['−0.1秒','0.011'],['−0.01秒','0.001'],['−0.001秒','0']]) {
    await clickRow(0, label);
    assert.equal(await evaluate('document.querySelector("#rows input").value'), expected);
  }
  await clickRow(0, '−0.001秒');
  assert.equal(await evaluate('document.querySelector("#rows input").value'), '0');
  await clickRow(0, '選択');
  await evaluate("document.getElementById('blank').click()");
  assert.deepEqual(await evaluate("rows.map(r=>r.text)"), ['最初の歌詞', '', '次の歌詞']);
  assert.equal(await evaluate("selected"), 1);
  assert.equal(await evaluate("document.activeElement.getAttribute('aria-label')"), '2行目の歌詞');
  await evaluate("document.getElementById('undo').click()");
  assert.deepEqual(await evaluate("rows.map(r=>r.text)"), ['最初の歌詞', '次の歌詞']);
  await evaluate("document.getElementById('redo').click()");
  assert.deepEqual(await evaluate("rows.map(r=>r.text)"), ['最初の歌詞', '', '次の歌詞']);
  await evaluate("document.getElementById('undo').click()");
  await evaluate(`document.getElementById('shiftSeconds').value='0.5';document.getElementById('shift').click();`);
  assert.equal(await evaluate('document.querySelector("#rows input").value'), '0.5');
  await evaluate(`document.getElementById('undo').click()`);
  assert.equal(await evaluate('document.querySelector("#rows input").value'), '0');
  await evaluate(`document.getElementById('redo').click()`);
  assert.equal(await evaluate('document.querySelector("#rows input").value'), '0.5');
  await evaluate("document.getElementById('newProject').click();document.getElementById('blank').click()");
  assert.equal(await evaluate('document.querySelectorAll("#rows .row").length'), 1);
  await evaluate("document.getElementById('undo').click()");
  assert.equal(await evaluate('document.querySelectorAll("#rows .row").length'), 0);
  await evaluate(`document.getElementById('songName').value='二曲目';document.getElementById('songName').dispatchEvent(new Event('input'));document.getElementById('paste').value='別の歌詞';document.getElementById('append').click();`);
  assert.equal(await evaluate('document.getElementById("projects").options.length'), 2);
  await evaluate(`const selector=document.getElementById('projects');selector.value=selector.options[0].value;selector.dispatchEvent(new Event('change'));`);
  assert.equal(await evaluate('document.getElementById("songName").value'), '確認用の曲');
  assert.equal(await evaluate('document.querySelector("#rows input").value'), '0.5');
  // Real audio metadata and stamping, rather than just the pure time functions.
  const wav = Buffer.alloc(44 + 8000 * 2 * 3);
  wav.write('RIFF', 0); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
  wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(8000, 24); wav.writeUInt32LE(16000, 28); wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
  wav.write('data', 36); wav.writeUInt32LE(wav.length - 44, 40);
  const audioPath = resolve(root, 'Checks/BrowserProfile/sample.wav');
  await writeFile(audioPath, wav);
  const doc = await page('DOM.getDocument');
  const input = await page('DOM.querySelector', { nodeId: doc.root.nodeId, selector: '#audioFile' });
  await page('DOM.setFileInputFiles', { nodeId: input.nodeId, files: [audioPath] });
  await waitFor('Number.isFinite(document.getElementById("audio").duration)');
  await evaluate(`document.getElementById('audio').currentTime=0.25;document.getElementById('stamp').click();`);
  assert.equal(await evaluate('document.querySelector("#rows input").value'), '0.25');
  await evaluate(`document.getElementById('undo').click()`);
  assert.equal(await evaluate('document.querySelector("#rows input").value'), '0.5');
  await evaluate('preview(0)');
  await waitFor('!audio.paused');
  await clickRow(0, '停止');
  const stoppedAt = await evaluate('audio.currentTime');
  await new Promise(done => setTimeout(done, 200));
  assert.equal(await evaluate('audio.paused'), true);
  assert.ok(stoppedAt >= 0.5 && Math.abs(await evaluate('audio.currentTime') - stoppedAt) < 0.02);
  await page('Page.reload');
  await waitFor('document.getElementById("songName")?.value === "確認用の曲"');
  assert.equal(await evaluate('document.getElementById("projects").options.length'), 2);
  assert.equal(await evaluate('document.querySelector("#rows input").value'), '0.5');
  const image = await page('Page.captureScreenshot', { format: 'png' });
  await writeFile(resolve(output, 'pc-editor.png'), Buffer.from(image.data, 'base64'));
  console.log('Browser checks passed: millisecond buttons, insert-after-selection and undo/redo, row playback stop without reset, draft migration, stamping and persistence.');
  await call('Browser.close');
} finally {
  socket?.close(); chrome.kill();
}
