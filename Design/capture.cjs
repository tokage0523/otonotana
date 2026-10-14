const { chromium } = require('playwright');
const { pathToFileURL } = require('node:url');
const path = require('node:path');
const fs = require('node:fs');
(async () => {
  const output = path.join(__dirname, 'output'); fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1340, height: 1100 }, deviceScaleFactor: 1 });
    await page.goto(pathToFileURL(path.join(__dirname, 'directions.html')).href);
    await page.screenshot({ path: path.join(output, 'player-directions.png'), fullPage: true });
    for (const theme of ['artwork','midnight','paper']) {
      await page.locator('#' + theme).screenshot({ path: path.join(output, theme + '.png') });
    }
    await page.locator('#artwork .lyrics-toggle').click();
    await page.locator('#artwork').screenshot({ path: path.join(output, 'lyrics.png') });
    console.log('Three player directions and lyric view exported.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
