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

// `context` gives the page its own storage (the column layout is kept in localStorage).
async function openApp({ trackCount, width = 1440, height = 860, context = browser } = {}) {
  const page = await context.newPage();
  await page.setViewport({ width, height });
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
const rowTitles = (page) => page.$$eval('.row.selected', (rows) => rows.map((r) => r.children[1].textContent.trim()));
const headerLabels = (page) => page.$$eval('.header .th-cell', (cells) => cells.map((c) => c.textContent.trim()));
async function editTitleThenClickRow(page, rowIndex) {
  await (await page.$$('.row'))[0].click();
  await setField(page, 'Title', 'Edited');
  await (await page.$$('.row'))[rowIndex].click();
  await page.waitForSelector('[role=alertdialog]');
}
const dialogButton = (page, label) =>
  page.evaluate((l) => [...document.querySelectorAll('[role=alertdialog] button')].find((b) => b.textContent.trim() === l).click(), label);

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

  async 'unsaved edits: changing the selection asks first'() {
    const page = await openApp();
    await editTitleThenClickRow(page, 1);
    check((await page.$eval('[role=alertdialog] h2', (h) => h.textContent)) === 'Save changes to “One”?', 'dialog names the file');
    await shot(page, 'unsaved-changes');

    await dialogButton(page, 'Cancel');
    await sleep(100);
    check(!(await page.$('[role=alertdialog]')), 'Cancel closes the dialog');
    check(JSON.stringify(await rowTitles(page)) === '["One"]', 'Cancel keeps the selection');
    check((await (await fieldInput(page, 'Title')).evaluate((el) => el.value)) === 'Edited', 'Cancel keeps the edit');

    await page.keyboard.press('Escape');
    await page.waitForSelector('[role=alertdialog]');
    check(true, 'Esc in the table asks too');
    await page.keyboard.press('Escape');
    await sleep(100);
    check(!(await page.$('[role=alertdialog]')) && (await rowTitles(page)).length === 1, 'Esc in the dialog cancels');

    await (await page.$$('.row'))[1].click();
    await page.waitForSelector('[role=alertdialog]');
    await dialogButton(page, 'Discard changes');
    await sleep(200);
    check(JSON.stringify(await rowTitles(page)) === '["Two"]', 'Discard moves the selection');
    check((await callsOf(page, 'write_tags')).length === 0, 'Discard writes nothing');

    await setField(page, 'Title', 'Also edited');
    await (await page.$$('.row'))[2].click();
    await page.waitForSelector('[role=alertdialog]');
    await dialogButton(page, 'Save');
    await sleep(300);
    const [w] = await callsOf(page, 'write_tags');
    check(JSON.stringify(w) === JSON.stringify({ ids: [2], edits: { title: { op: 'set', value: 'Also edited' } } }), `Save writes the edit: ${JSON.stringify(w)}`);
    check(JSON.stringify(await rowTitles(page)) === '["Three"]', 'Save then moves the selection');

    await (await page.$$('.row'))[2].click();
    await sleep(100);
    check(!(await page.$('[role=alertdialog]')), 'no dialog without unsaved edits');
    await page.close();
  },

  async 'unsaved edits survive a filter that hides the file'() {
    const page = await openApp();
    await (await page.$$('.row'))[0].click();
    await setField(page, 'Title', 'Edited');
    await page.type('.search input', 'Beta');
    await page.waitForFunction(() => document.querySelectorAll('.row').length === 1);
    await sleep(100);
    check((await (await fieldInput(page, 'Title')).evaluate((el) => el.value)) === 'Edited', 'edit still in the editor');
    await page.click('.editor footer button.primary');
    await sleep(300);
    const [w] = await callsOf(page, 'write_tags');
    check(JSON.stringify(w?.ids) === '[1]', `saves to the hidden file: ${JSON.stringify(w)}`);
    await sleep(300);
    check(await page.$eval('.editor', (e) => e.textContent.includes('Select one or more tracks')), 'after saving, the hidden file is deselected');
    await page.close();
  },

  async 'unsaved edits: closing the window asks first'() {
    const page = await openApp();
    const close = () => page.evaluate(() => window.__emit('tauri://close-requested', null));
    await (await page.$$('.row'))[0].click();
    await setField(page, 'Title', 'Edited');
    await close();
    await page.waitForSelector('[role=alertdialog]');
    check((await callsOf(page, 'plugin:window|destroy')).length === 0, 'window stays open while asking');
    await dialogButton(page, 'Discard changes');
    await sleep(100);
    check((await callsOf(page, 'plugin:window|destroy')).length === 1, 'Discard closes the window');
    await page.close();
  },

  async 'save failures: report, marked rows, retry and select'() {
    const page = await openApp();
    await page.evaluate(() => (window.__MOCK_WRITE_FAIL = [2]));
    const rows = await page.$$('.row');
    await rows[0].click();
    await page.keyboard.down('Shift');
    await rows[2].click();
    await page.keyboard.up('Shift');
    await setField(page, 'Genre', 'Rock');
    await page.click('.editor footer button.primary');
    await page.waitForSelector('#failures-title');
    await sleep(200);
    await shot(page, 'save-failures');
    const title = await page.$eval('#failures-title', (h) => h.textContent.trim());
    check(title === '1 file wasn’t saved', `report title: ${title}`);
    check(await page.$eval('#failures-summary', (p) => p.textContent.includes('The other 2 files were saved')), 'report says the rest saved');
    check(await page.$eval('[role=alertdialog] .list', (l) => l.textContent.includes('X/2.mp3') && l.textContent.includes('Permission denied')), 'report lists path and error');
    check(!(await page.$$eval('.toast', (ts) => ts.some((t) => t.textContent.startsWith('Saved')))), 'no success toast');

    await page.keyboard.press('Escape');
    await sleep(100);
    check(!(await page.$('#failures-title')), 'Esc closes the report');
    check(JSON.stringify(await page.$$eval('.row.unsaved', (rs) => rs.map((r) => r.children[1].textContent.trim()))) === '["Two"]', 'failed row is marked');
    check((await page.$eval('.status .not-saved', (b) => b.textContent.trim())) === '1 not saved', 'status bar counts it');

    await page.type('.search input', 'Gamma');
    await page.waitForFunction(() => document.querySelectorAll('.row').length === 1);
    await page.click('.status .not-saved');
    await page.waitForSelector('#failures-title');
    check(!(await page.$eval('#failures-summary', (p) => p.textContent.includes('other'))), 'reopened report has no save summary');
    await page.evaluate(() => [...document.querySelectorAll('[role=alertdialog] button')].find((b) => b.textContent.trim() === 'Select these files').click());
    await sleep(400);
    check((await page.$eval('.search input', (i) => i.value)) === '' && JSON.stringify(await rowTitles(page)) === '["Two"]', 'Select clears the search and selects the file');

    await page.click('.status .not-saved');
    await page.waitForSelector('#failures-title');
    await page.evaluate(() => (window.__MOCK_WRITE_FAIL = []));
    await page.click('[role=alertdialog] .primary');
    await sleep(300);
    const retry = (await callsOf(page, 'write_tags')).at(-1);
    check(JSON.stringify(retry) === JSON.stringify({ ids: [2], edits: { genre: { op: 'set', value: 'Rock' } } }), `Retry resends the edits: ${JSON.stringify(retry)}`);
    check(!(await page.$('#failures-title')) && !(await page.$('.row.unsaved')) && !(await page.$('.status .not-saved')), 'successful retry clears everything');
    await page.close();
  },

  async 'row context menu'() {
    const page = await openApp();
    await page.evaluate(() => {
      window.__copied = [];
      navigator.clipboard.writeText = async (t) => window.__copied.push(t);
    });
    const menuLabels = () => page.$$eval('.menu [role=menuitem]', (bs) => bs.map((b) => b.querySelector('.label').textContent.trim()));
    const choose = (label) =>
      page.evaluate((l) => [...document.querySelectorAll('.menu [role=menuitem]')].find((b) => b.textContent.includes(l)).click(), label);

    await (await page.$$('.row'))[1].click({ button: 'right' });
    await page.waitForSelector('.menu');
    await shot(page, 'row-menu');
    check(JSON.stringify(await rowTitles(page)) === '["Two"]', 'right-click selects the row');
    const labels = await menuLabels();
    check(JSON.stringify(labels) === JSON.stringify(['Play', 'Edit tags', 'Reorganize 1 file…', 'Show in file manager', 'Copy path']), `items: ${labels}`);
    check(await page.evaluate(() => document.activeElement.closest('.menu') !== null), 'menu takes focus');
    await page.keyboard.press('Escape');
    check(!(await page.$('.menu')), 'Esc closes it');

    await (await page.$$('.row'))[1].click({ button: 'right' });
    await page.waitForSelector('.menu');
    await choose('Show in file manager');
    await sleep(100);
    check(JSON.stringify(await callsOf(page, 'show_in_folder')) === '[{"id":2}]', 'Show in file manager asks for the clicked file');

    await (await page.$$('.row'))[1].click({ button: 'right' });
    await page.waitForSelector('.menu');
    await choose('Edit tags');
    await sleep(100);
    check(await page.evaluate(() => document.activeElement === document.querySelector('.editor .fields input')), 'Edit tags focuses the title field');

    const rows = await page.$$('.row');
    await rows[0].click();
    await page.keyboard.down('Shift');
    await rows[2].click();
    await page.keyboard.up('Shift');
    await rows[2].click({ button: 'right' });
    await page.waitForSelector('.menu');
    check(JSON.stringify(await rowTitles(page)) === '["One","Two","Three"]', 'right-click inside the selection keeps it');
    check((await menuLabels()).includes('Reorganize 3 files…'), 'items count the selection');
    await choose('Copy 3 paths');
    await sleep(100);
    const copied = await page.evaluate(() => window.__copied.at(-1));
    check(copied === '/music/X/1.mp3\n/music/X/2.mp3\n/music/Y/3.mp3', `copies full paths: ${JSON.stringify(copied)}`);

    await (await page.$$('.row'))[0].click();
    await page.keyboard.press('ContextMenu');
    await page.waitForSelector('.menu');
    check(true, 'the Menu key opens it for the focused row');
    await page.keyboard.press('ArrowDown');
    await page.keyboard.press('Enter');
    await sleep(100);
    check(await page.evaluate(() => document.activeElement === document.querySelector('.editor .fields input')), 'arrow keys and Enter choose an item');
    await page.close();
  },

  async 'columns shrink to fit, hide and resize'() {
    const context = await browser.createBrowserContext();
    const page = await openApp({ width: 960, height: 760, context });
    const fit = await page.$eval('.scroller', (e) => e.scrollWidth - e.clientWidth);
    check(fit <= 0, `all columns fit a 960px window (overflow ${fit}px)`);
    await shot(page, 'narrow');

    await page.click('.header', { button: 'right' });
    await page.waitForSelector('.menu');
    await shot(page, 'column-menu');
    await page.evaluate(() => [...document.querySelectorAll('.menu button')].find((b) => b.textContent.includes('Path')).click());
    check(!(await headerLabels(page)).includes('Path'), 'Path column hidden from the menu');
    check(await page.$eval('.menu button[disabled]', (b) => b.textContent.includes('Title')), 'Title cannot be hidden');
    await page.keyboard.press('Escape');
    check(!(await page.$('.menu')), 'Esc closes the menu');

    const artist = await page.$$eval('.header .th-cell', (cells) => cells.findIndex((c) => c.textContent.trim() === 'Artist'));
    const cell = (await page.$$('.header .th-cell'))[artist];
    const before = (await cell.boundingBox()).width;
    const handle = await (await cell.$('.resize')).boundingBox();
    await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2);
    await page.mouse.down();
    await page.mouse.move(handle.x + 80, handle.y + handle.height / 2, { steps: 4 });
    await page.mouse.up();
    const after = (await cell.boundingBox()).width;
    check(Math.abs(after - before - 80) < 6, `dragging the edge resizes (${before} → ${after})`);
    check(!(await page.$('.th.sorted')), 'resizing does not sort');

    await page.reload();
    await page.waitForSelector('.row');
    const labels = await headerLabels(page);
    const width = (await (await page.$$('.header .th-cell'))[labels.indexOf('Artist')].boundingBox()).width;
    check(!labels.includes('Path') && Math.abs(width - after) < 2, 'layout is remembered');

    await page.click('.columns-button');
    await page.evaluate(() => [...document.querySelectorAll('.menu button')].find((b) => b.textContent.includes('Reset columns')).click());
    check((await headerLabels(page)).includes('Path'), 'Reset columns shows everything again');
    await context.close();
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
