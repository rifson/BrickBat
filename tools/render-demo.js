// Renders the animated demo: the front page -> Secrets -> a search in every environment ->
// filtered to one scope in each -> U to add or update api_key in all of them at once. Built from
// the same fictional screens as render-screenshots.js, so update those when the script's menus
// change. Needs ffmpeg, and gifsicle if it is there to shrink the GIF (losslessly, about ten times).
//
//   cd tools && npm install && npx playwright install chromium
//   node render-demo.js ../docs/screenshots/demo.gif [demo.mp4]
//
// The GIF goes in the README. The optional MP4 (1920x1080) is for posting the demo elsewhere.
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { k, d, h, ok, line, CURSOR, screen, screens, html, width, SEARCH, searchRow } = require('./render-screenshots.js');

const [GIF, MP4] = process.argv.slice(2).map((p) => path.resolve(p));
const COLS = 100;
const ROWS = 30;   // the window's height in lines; longer output scrolls, as in a real console

// ---- screens, as the script prints them --------------------------------------
const lastLine = (lines, last) => [...lines.slice(0, -1), last];
const choose = (key) => line(`   Choose: ${key}`);   // choice echoes the key that was pressed
const typing = (prompt, text, cursor = true) => line(prompt + text, ...(cursor ? [CURSOR] : []));

const front = screens['front-page'];
const menu = screens['secrets-menu'];

// 2: search scope names, in every logged-in environment
const SEARCHING = [
  line('  dev - 5 of 214 scopes match'),
  line('  qa - 2 of 37 scopes match'),
  line('  ', d('prod - skipped, not logged in')),
  line('  azure-sandbox - 1 of 12 scopes match'),
];
const search = (typed, { cursor = true, scope = false, key, found = 0 } = {}) => [
  ...screen('Search scopes by name'),
  line(),
  typing('   Scope name contains (blank = back): ', typed, cursor && !scope),
  ...(scope ? [
    line(),
    line('  ', k('[C]'), ' Only dev     ', k('[A]'), ' All logged-in environments     ', k('[B]'), ' Back'),
    line(),
    key ? line(`   Choose: ${key}`) : line('   Choose: ', CURSOR),
  ] : []),
  ...(found ? [line(), line('  ', d('Searching...')), ...SEARCHING.slice(0, found)] : []),
];

// the whole result, then F to filter it down to one scope in each environment
const MENU = [
  line('  ', k('[O]'), ' Open a scope     ', k('[F]'), ' Filter by name     ', k('[B]'), ' Back'),
  line('  ', k('[V]'), ' Show the keys and access of these 8 scopes'),
  line('  ', k('[U]'), ' Add or update a key in some or all of them'),
  line('  ', k('[G]'), ' Grant or change access in some or all of them'),
  line('  ', k('[K]'), ' Find a key in these 8 scopes'),
  line('  ', k('[P]'), " Check someone's access on these 8 scopes"),
];
const results = [
  ...screen('Scopes matching analytics'),
  line(),
  ...SEARCH.map((_, i) => searchRow(i + 1)),
  line(),
  line('  ', d('8 scopes')),
  line(),
  ...MENU,
  line(),
  line('   Choose: ', CURSOR),
];
const filtering = (typed, cursor = true) => [...lastLine(results, choose('F')), line(),
  typing('   Scope name contains (blank = show the whole list): ', typed, cursor)];
const filtered = screens['scope-filter'];

// U on the filtered list: the key, then the scopes to change
const pick = (key, nums, { keyCursor = true, numCursor = false } = {}) => [
  ...lastLine(filtered, choose('U')),
  line(),
  line('  Adds or updates one key in the scopes you pick, for example the same scope in each environment.'),
  line('  ', d('Key names may use letters, digits, - _ and . only.')),
  typing('   Key (blank = back): ', key, keyCursor),
  ...(nums !== undefined ? [typing('   Scope numbers from the list, separated by spaces (A = all, blank = back): ', nums, numCursor)] : []),
];
const plan = screens['scope-set'];

// T: confirm, then the CLI asks for each value - hidden - under the scope it is for
const TARGETS = [['dev', 'analytics.dev.secrets'], ['qa', 'analytics.qa.secrets'], ['azure-sandbox', 'analytics.sandbox.secrets']];
const run = (step, { confirm = true, typed = -1, typedLen = 0, summary = false, cursor = true } = {}) => {
  const out = [...lastLine(plan, choose('T')), line(),
    line('  Add or update ', h('api_key'), ' in these 3 scopes?')];
  out.push(confirm ? line('   Are you sure? [Y/N] Y') : line('   Are you sure? [Y/N] ', CURSOR));
  if (!confirm) return out;
  out.push(line(),
    line('  ', d('The CLI asks for the value now. Paste with right-click or Ctrl+V, then press Enter.')),
    line('  ', d('One line only. For a value with line breaks, use F instead.')),
    line('  ', d('It asks once for each scope, named just above its prompt.')));
  TARGETS.slice(0, step).forEach(([env, scope], i) => {
    out.push(line(), line('  ', h(env), '  ', scope, '  ', d(`${i + 1} of 3`)));
    // promptui's hidden prompt; once Enter is pressed it erases its own line
    if (i === typed) out.push(line({ c: 'pq', t: '?' }, ' ', h('Please enter your secret value:'), ' ' + '*'.repeat(typedLen), ...(cursor ? [CURSOR] : [])));
    else out.push(line('  ', ok('Saved.')));
  });
  if (summary) out.push(line(), line('  ', ok('Saved api_key in all 3 scopes.')),
    line(), line('  ', d('BrickBat emptied the clipboard. If clipboard history is on, delete the value in Win+V too.')),
    line(), line('  ', d(' Press any key to continue...'), CURSOR));
  return out;
};

// ---- storyboard --------------------------------------------------------------
const CAP = {
  front: 'Every profile, and whether you are logged in, at a glance',
  search: 'Search for a scope in every environment at once',
  filter: 'Filter down to the same scope in each environment',
  pick: 'Add or update one key in all of them in one go',
  plan: 'See what changes in each scope before anything is saved',
  typed: 'Each value is typed hidden, with its environment named above it',
  done: 'Saved in every environment. Secret values are never shown.',
  end: 'One file, no install: download brickbat.bat and double-click it',
};
const RHYTHM = [55, 70, 50, 85, 60, 45, 75, 65, 50, 90];   // ms per typed key, for a human feel

const shots = [];
const show = (lines, ms, caption, key) => shots.push({ lines, ms, caption, key });
// a long pause with the cursor blinking, like a real console
const hold = (lines, ms, caption) => {
  if (!lines.flat().includes(CURSOR)) return show(lines, ms, caption);
  const off = lines.map((l) => l.map((s) => (s === CURSOR ? { c: 'cursor off', t: '' } : s)));
  const n = Math.max(1, Math.round(ms / 530));   // equal blinks, no slivers at the end
  for (let i = 0; i < n; i++) show(i % 2 ? off : lines, Math.round(ms / n), caption);
};
// one frame per key typed
const type = (text, frame, caption, speed = 1) =>
  [...text].forEach((_, i) => show(frame(text.slice(0, i + 1)), Math.round(RHYTHM[i % RHYTHM.length] * speed), caption));

hold(front, 2200, CAP.front);
show(lastLine(front, choose('S')), 400, CAP.front, 'S');
hold(menu, 1400, CAP.search);
show(lastLine(menu, choose('2')), 400, CAP.search, '2');
hold(search(''), 500, CAP.search);
type('analytics', (t) => search(t), CAP.search);
show(search('analytics', { scope: true }), 900, CAP.search, 'Enter');
show(search('analytics', { scope: true, key: 'A' }), 350, CAP.search, 'A');
for (let n = 0; n <= SEARCHING.length; n++) show(search('analytics', { scope: true, key: 'A', found: n }), n ? 300 : 450, CAP.search);
hold(results, 1600, CAP.filter);
show(filtering('', false), 350, CAP.filter, 'F');
type('secrets', (t) => filtering(t), CAP.filter);
show(filtering('secrets', false), 300, CAP.filter, 'Enter');
hold(filtered, 1800, CAP.filter);
show(pick('', undefined, { keyCursor: false }), 350, CAP.pick, 'U');
type('api_key', (t) => pick(t), CAP.pick);
show(pick('api_key', '', { keyCursor: false, numCursor: true }), 450, CAP.pick, 'Enter');
type('3 6 8', (t) => pick('api_key', t, { keyCursor: false, numCursor: true }), CAP.pick, 1.6);
show(pick('api_key', '3 6 8', { keyCursor: false }), 350, CAP.pick, 'Enter');
hold(plan, 2800, CAP.plan);
show(run(0, { confirm: false }), 700, CAP.plan, 'T');
show(run(0), 450, CAP.typed, 'Y');
TARGETS.forEach((_, i) => {
  const speed = i === 0 ? 0.7 : 0.35;   // the first value is typed out, the rest pasted quickly
  show(run(i + 1, { typed: i, typedLen: 0 }), i === 0 ? 700 : 350, CAP.typed);
  for (let n = 1; n <= 14; n++) show(run(i + 1, { typed: i, typedLen: n }), Math.round(RHYTHM[n % RHYTHM.length] * speed), CAP.typed);
  show(run(i + 1, { typed: i, typedLen: 14, cursor: false }), 250, CAP.typed, 'Enter');
  show(run(i + 1), i === 2 ? 350 : 450, CAP.typed);
});
hold(run(3, { summary: true }), 2600, CAP.done);
hold(run(3, { summary: true }), 3200, CAP.end);

// ---- render --------------------------------------------------------------------
(async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'brickbat-demo-'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 1200, height: 1000 } });
  const list = [];
  const seen = new Map();
  for (const [i, s] of shots.entries()) {
    if (width(s.lines) > COLS - 2) throw new Error(`frame ${i} is wider than ${COLS - 2} columns`);
    const lines = s.lines.slice(-ROWS);   // what fits in the window: the newest lines
    const doc = html(lines, COLS, { flat: true, rows: ROWS, caption: s.caption, key: s.key });
    let file = seen.get(doc);
    if (!file) {
      file = path.join(tmp, `f${String(i).padStart(3, '0')}.png`);
      await page.setContent(doc);
      await page.evaluate(() => document.fonts.ready);
      await (await page.$('.win')).screenshot({ path: file, omitBackground: true });
      seen.set(doc, file);
    }
    list.push(`file '${file}'`, `duration ${s.ms / 1000}`);
  }
  await browser.close();
  // ffmpeg's concat demuxer needs the last file once more for its duration to count
  list.push(list[list.length - 2]);
  const txt = path.join(tmp, 'frames.txt');
  fs.writeFileSync(txt, list.join('\n') + '\n');
  const input = ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', txt];
  if (GIF) {
    // rendered at 2x and scaled down smoothly, so line-drawing characters join up
    execFileSync('ffmpeg', [...input, '-filter_complex',
      'format=rgba,scale=1120:-1:flags=lanczos,split[a][b];[a]palettegen=reserve_transparent=1:stats_mode=full[p];[b][p]paletteuse=dither=none:alpha_threshold=128',
      '-fps_mode', 'vfr', '-loop', '0', GIF]);
    try {
      execFileSync('gifsicle', ['-O3', '--batch', GIF]);
    } catch {
      console.log('gifsicle not found - the GIF is not optimised');
    }
    console.log('wrote', GIF, `${(fs.statSync(GIF).size / 1024).toFixed(0)} KB`);
  }
  if (MP4) {
    execFileSync('ffmpeg', [...input, '-filter_complex',
      'color=c=0x1b1d22:s=1920x1080:r=30[bg];[0:v]format=rgba,scale=-1:960:flags=lanczos[w];[bg][w]overlay=(W-w)/2:(H-h)/2:shortest=1,format=yuv420p',
      '-r', '30', '-c:v', 'libx264', '-crf', '18', '-preset', 'slow', '-movflags', '+faststart', MP4]);
    console.log('wrote', MP4, `${(fs.statSync(MP4).size / 1024).toFixed(0)} KB`);
  }
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`${shots.length} frames, ${(shots.reduce((n, s) => n + s.ms, 0) / 1000).toFixed(1)} s`);
})();
