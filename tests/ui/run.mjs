// Headless UI tests against a mocked backend (see mock-tauri.js).
//
//   npm run test:ui                 run everything
//   SCREENSHOTS=1 npm run test:ui   also save screenshots to tests/ui/screenshots/
//   CHROME=/path/to/chrome ...      browser to use (default: chromium or google-chrome on PATH)
//
// Runs on the host (not in the build container) because it needs a Chromium binary.
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';
import { createServer } from 'vite';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const mock = fs.readFileSync(path.join(here, 'mock-tauri.js'), 'utf8');
const shotsDir = path.join(here, 'screenshots');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function findChrome() {
  if (process.env.CHROME) return process.env.CHROME;
  for (const bin of ['chromium', 'google-chrome', 'google-chrome-stable', 'chromium-browser']) {
    try {
      return execSync(`command -v ${bin}`, { encoding: 'utf8' }).trim();
    } catch {
      /* try the next one */
    }
  }
  throw new Error('No Chromium found; set CHROME=/path/to/chrome');
}

let failures = 0;
function check(cond, msg) {
  console.log(`  ${cond ? 'ok  ' : 'FAIL'} ${msg}`);
  if (!cond) failures++;
}

const server = await createServer({ root, configFile: path.join(root, 'vite.config.ts'), server: { port: 5199, strictPort: true }, logLevel: 'error' });
await server.listen();
const url = 'http://localhost:5199/';
const browser = await puppeteer.launch({ executablePath: findChrome(), headless: true, args: ['--no-sandbox'] });

async function openApp({ trackCount } = {}) {
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 860 });
  page.on('pageerror', (e) => check(false, `page error: ${e.message}`));
  if (trackCount) await page.evaluateOnNewDocument((n) => (window.__MOCK_TRACK_COUNT = n), trackCount);
  await page.evaluateOnNewDocument(mock);
  await page.goto(url);
  await page.waitForSelector('.row');
  return page;
}

const callsOf = (page, name) => page.evaluate((n) => window.__calls.filter(([c]) => c === n).map(([, a]) => a), name);
const playerCalls = (page) => page.evaluate(() => window.__calls.filter(([c]) => c.startsWith('player_')));
const fieldInput = (page, label) =>
  page.evaluateHandle(
    (l) => [...document.querySelectorAll('.field')].find((f) => f.querySelector('.label').textContent.trim() === l).querySelector('input, textarea'),
    label,
  );
async function setField(page, label, value) {
  const input = await fieldInput(page, label);
  await input.focus();
  await input.evaluate((el) => el.select());
  await page.keyboard.press('Backspace');
  if (value) await input.type(value);
}
async function shot(page, name) {
  if (!process.env.SCREENSHOTS) return;
  fs.mkdirSync(shotsDir, { recursive: true });
  await page.screenshot({ path: path.join(shotsDir, `${name}.png`) });
}

const tests = {
  async 'single edit: changed field is set, blanked field is cleared'() {
    const page = await openApp();
    await (await page.$$('.row'))[0].click();
    await setField(page, 'Title', 'New Title');
    await setField(page, 'Artist', '');
    await page.click('.editor footer button.primary');
    await sleep(300);
    const [w] = await callsOf(page, 'write_tags');
    check(JSON.stringify(w) === JSON.stringify({ ids: [1], edits: { title: { op: 'set', value: 'New Title' }, artist: { op: 'clear' } } }), JSON.stringify(w));
    await page.close();
  },

  async 'bulk edit: blank is skipped, × clears, typed value is set'() {
    const page = await openApp();
    const rows = await page.$$('.row');
    await rows[0].click();
    await page.keyboard.down('Shift');
    await rows[2].click();
    await page.keyboard.up('Shift');
    await page.waitForFunction(() => document.querySelector('.editor h2')?.textContent.includes('3 files'));
    const placeholder = await (await fieldInput(page, 'Artist')).evaluate((el) => el.placeholder);
    check(placeholder.includes('multiple'), `differing values show placeholder: ${placeholder}`);
    await setField(page, 'Album', '');
    await setField(page, 'Genre', 'Rock');
    await page.evaluate(() =>
      [...document.querySelectorAll('.field')].find((f) => f.querySelector('.label').textContent.trim() === 'Composer').querySelector('button.clear').click(),
    );
    await shot(page, 'bulk-edit');
    await page.click('.editor footer button.primary');
    await sleep(300);
    const [w] = await callsOf(page, 'write_tags');
    check(JSON.stringify(w) === JSON.stringify({ ids: [1, 2, 3], edits: { genre: { op: 'set', value: 'Rock' }, composer: { op: 'clear' } } }), JSON.stringify(w));
    await page.close();
  },

  async 'filters are sent with the query'() {
    const page = await openApp();
    await page.click('.bar button');
    await page.type('.filter .value', 'Alp');
    await sleep(400);
    const q = (await callsOf(page, 'query_tracks')).at(-1).query;
    check(q.filters[0].field === 'artist' && q.filters[0].op === 'contains' && q.filters[0].value === 'Alp', JSON.stringify(q));
    await page.close();
  },

  async 'reorganize dialog previews moves and conflicts'() {
    const page = await openApp();
    await (await page.$$('.row'))[0].click();
    await page.keyboard.down('Control');
    await page.keyboard.press('a');
    await page.keyboard.up('Control');
    await page.click('.top button.primary');
    await page.waitForSelector('.dialog .item');
    await sleep(400);
    await shot(page, 'reorganize');
    check((await page.$$('.dialog .item.conflict')).length === 1, 'one conflict row');
    const label = await page.$eval('.dialog footer button.primary', (b) => b.textContent.trim());
    check(label === 'Move 2 files', `move button: ${label}`);
    await page.close();
  },

  async 'player: double-click, Space, player bar and seek'() {
    const page = await openApp();
    check(!(await page.$('.player')), 'no player bar before anything plays');
    await (await page.$$('.row'))[1].click({ count: 2 });
    await sleep(100);
    check((await callsOf(page, 'player_play')).some((a) => a.id === 2), 'double-click plays the row');

    await page.evaluate(() => window.__emit('player', { track_id: 2, playing: true, position_ms: 65000, duration_ms: 200000, error: null }));
    await page.waitForSelector('.player');
    await sleep(100);
    check((await page.$eval('.player .title', (e) => e.textContent)) === 'Two', 'player bar shows the title');
    check((await page.$eval('.row.playing .now-playing', (e) => e.textContent)) === '▶', 'playing row is marked');
    check((await page.$eval('.editor .listen', (e) => e.textContent.trim())) === '❚❚ Pause', 'editor button offers Pause');

    await page.keyboard.press('Space');
    await page.keyboard.press('ArrowDown');
    await page.keyboard.press('Space');
    await sleep(100);
    const recent = (await playerCalls(page)).slice(-2).map(([c, a]) => [c, a.id ?? null]);
    check(JSON.stringify(recent) === JSON.stringify([['player_toggle', null], ['player_play', 3]]), `Space toggles current, plays other: ${JSON.stringify(recent)}`);

    const box = await (await page.$('.player .seek')).boundingBox();
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    await sleep(100);
    const seek = (await callsOf(page, 'player_seek')).at(-1);
    check(seek && Math.abs(seek.positionMs - 100000) < 5000, `seek to middle: ${JSON.stringify(seek)}`);
    await shot(page, 'player');
    await page.close();
  },

  async 'large library stays responsive (6000 rows)'() {
    const start = Date.now();
    const page = await openApp({ trackCount: 6000 });
    const rendered = Date.now() - start;
    const domRows = (await page.$$('.row')).length;
    check(domRows < 100, `table is virtualized (${domRows} rows in DOM, first render ${rendered} ms)`);
    await (await page.$$('.row'))[0].click();
    const t = Date.now();
    await page.keyboard.down('Control');
    await page.keyboard.press('a');
    await page.keyboard.up('Control');
    await page.waitForFunction(() => document.querySelector('.editor h2')?.textContent.includes('6000'));
    const selectMs = Date.now() - t;
    check(selectMs < 1000, `select all + editor in ${selectMs} ms`);
    await page.close();
  },
};

try {
  const only = process.argv[2];
  for (const [name, fn] of Object.entries(tests)) {
    if (only && !name.includes(only)) continue;
    console.log(name);
    try {
      await fn();
    } catch (e) {
      check(false, `threw: ${e.stack ?? e}`);
    }
  }
} finally {
  await browser.close();
  await server.close();
}
console.log(failures ? `\n${failures} check(s) failed` : '\nall UI checks passed');
process.exit(failures ? 1 : 0);
