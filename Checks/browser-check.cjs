const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const http = require('node:http');

(async () => {
  const output = path.join(__dirname, 'output');
  fs.mkdirSync(output, { recursive: true });
  // A 12-second PCM fixture; no external music is used.
  const sampleRate = 8000, count = sampleRate * 12;
  const wav = Buffer.alloc(44 + count * 2);
  wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
  wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(sampleRate, 24); wav.writeUInt32LE(sampleRate * 2, 28);
  wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34); wav.write('data', 36); wav.writeUInt32LE(count * 2, 40);
  const fixture = path.join(output, 'fixture.wav'); fs.writeFileSync(fixture, wav);
  const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--autoplay-policy=no-user-gesture-required'] });
  const server = http.createServer((request, response) => {
    const filename = path.basename(request.url.split('?')[0]) || 'index.html';
    const file = path.resolve(__dirname, '../PCEditor', filename);
    if (!fs.existsSync(file)) { response.writeHead(404); response.end(); return; }
    response.setHeader('Content-Type', filename.endsWith('.js') ? 'text/javascript' : 'text/html');
    response.end(fs.readFileSync(file));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const context = await browser.newContext({ viewport: { width: 1200, height: 1000 } });
    const page = await context.newPage(); const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('dialog', dialog => dialog.accept());
    await page.goto(process.env.TEST_FILE_MODE === '1'
      ? pathToFileURL(path.resolve(__dirname, '../PCEditor/index.html')).href
      : `http://127.0.0.1:${server.address().port}/index.html`);
    await page.locator('#paste').fill('歌い出し\nサビ <img src=x onerror=alert(1)>\n最後の一節');
    await page.locator('#append').click();
    assert.equal(await page.locator('.row').count(), 3);
    await page.locator('#export').click();
    assert.match(await page.locator('#status').textContent(), /時刻を設定/);
    await page.locator('#audioFile').setInputFiles(fixture);
    await page.waitForFunction(() => Number.isFinite(document.getElementById('audio').duration));
    await page.evaluate(() => { document.getElementById('audio').currentTime = 2.123; });
    await page.locator('#stamp').click();
    assert.equal(await page.locator('.row').nth(0).locator('input[type=number]').inputValue(), '2.123');
    assert.equal(await page.locator('.row.selected .number').textContent(), '2');
    const values = ['1.25', '4.1', '8.25'];
    for (let i = 0; i < values.length; i++) {
      const field = page.locator('.row').nth(i).locator('input[type=number]');
      await field.fill(values[i]); await field.press('Tab');
    }
    await page.locator('.row').nth(1).getByRole('button', { name: 'ここから再生' }).click();
    const state = await page.evaluate(() => { const a = document.getElementById('audio'); const result = { seconds: a.currentTime, paused: a.paused }; a.pause(); return result; });
    assert.equal(state.paused, false); assert.ok(Math.abs(state.seconds - 4.1) < 0.5);
    const downloadPromise = page.waitForEvent('download'); await page.locator('#export').click();
    const download = await downloadPromise; const lrc = path.join(output, 'fixture.lrc');
    assert.equal(await download.failure(), null);
    await download.saveAs(lrc);
    assert.equal(fs.readFileSync(lrc, 'utf8'), '[00:01.250]歌い出し\n[00:04.100]サビ <img src=x onerror=alert(1)>\n[00:08.250]最後の一節\n');
    await page.reload();
    assert.equal(await page.locator('.row').count(), 3);
    assert.equal(await page.locator('.row').nth(1).locator('input[type=number]').inputValue(), '4.1');
    await page.locator('#lrcFile').setInputFiles(lrc);
    await page.waitForFunction(() => document.getElementById('status').textContent.includes('歌詞を読み込みました'));
    assert.equal(await page.locator('.row').nth(1).locator('input:not([type=number])').inputValue(), 'サビ <img src=x onerror=alert(1)>');
    assert.equal(await page.locator('#rows img').count(), 0);
    await page.locator('#audioFile').setInputFiles(fixture);
    await page.waitForFunction(() => Number.isFinite(document.getElementById('audio').duration));
    await page.locator('.row').nth(1).locator('input:not([type=number])').fill('サビの一節');
    await page.locator('#songName').fill('サンプル曲');
    await page.evaluate(() => { document.getElementById('audioName').textContent = 'サンプル音源.wav'; });
    await page.screenshot({ path: path.join(output, 'editor-preview.png'), fullPage: true });
    assert.deepEqual(errors, []);
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
    console.log('Browser checks passed: marking, manual timing, lyric seek/play, export/import, draft restoration, text safety, narrow layout.');
  } finally { await browser.close(); server.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
