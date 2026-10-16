// Renders the animated demo: front page -> Secrets -> open a favourite -> the scope's keys and
// access -> the same scope in every environment. Built from the same fictional screens as
// render-screenshots.js, so update those when the script's menus change. Needs ffmpeg, and
// gifsicle if it is there to shrink the GIF (losslessly, about ten times).
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
const { k, d, wn, L, line, CURSOR, PROFILES, screen, screens, html, width } = require('./render-screenshots.js');

const [GIF, MP4] = process.argv.slice(2).map((p) => path.resolve(p));
const COLS = 96;
const FAVS = ['analytics.dev.secrets', 'payments.dev.secrets', 'warehouse.dev.secrets'];

// ---- screens, as the script prints them --------------------------------------
const lastLine = (lines, last) => [...lines.slice(0, -1), last];
const choose = (key) => line(`   Choose: ${key}`);   // choice echoes the key that was pressed
const find = (lines, text) => lines.findIndex((l) => l.some((s) => s.t.includes(text)));

const front = screens['front-page'];

const menu = (() => {
  const m = [...screens['secrets-menu']];
  const at = find(m, 'FAVOURITES') + 1;
  m.splice(at, 3, ...FAVS.map((n, i) => line(' ', k(L(String(i + 1), 4)), '  ', n)));
  return m;
})();
const menuPick = (typed, cursor = true) => [...lastLine(menu, choose('F')),
  line('   Favourite number (blank = back): ' + typed, ...(cursor ? [CURSOR] : []))];

const loading = [...screen('Scope analytics.dev.secrets'), line(),
  line('  ', d('Loading secrets and access for analytics.dev.secrets in dev...'))];

// the scope page of a favourite: marked as one, and S removes it
const scope = screens['scope'].map((l) => {
  const t = l.map((s) => s.t).join('');
  if (t.startsWith('  Scope        ')) return [...l, { c: '', t: '  ' }, wn('favourite')];
  if (t.includes('Save as favourite')) return line('  ', k('[S]'), ' Remove from favourites     ', k('[E]'), ' This scope in every environment');
  return l;
});

// the compare screen fills in as each environment answers
const compare = screens['compare'];
const upto = (n) => compare.slice(0, n);
const qa = find(compare, PROFILES[1].host);
const prod = find(compare, 'prod - skipped');

// ---- storyboard --------------------------------------------------------------
const CAP = {
  front: 'Every profile, and whether you are logged in, at a glance',
  menu: 'Your favourite secret scopes, a key press away',
  scope: 'Keys and who has access. Secret values are never shown.',
  compare: 'The same scope in dev, qa and prod, side by side',
  end: 'One file, no install: download brickbat.bat and double-click it',
};

const shots = [];
const show = (lines, ms, caption, key) => shots.push({ lines, ms, caption, key });
// a long pause with the cursor blinking, like a real console
const hold = (lines, ms, caption) => {
  if (!lines.flat().includes(CURSOR)) return show(lines, ms, caption);
  const off = lines.map((l) => l.map((s) => (s === CURSOR ? { c: 'cursor off', t: '' } : s)));
  const n = Math.max(1, Math.round(ms / 530));   // equal blinks, no slivers at the end
  for (let i = 0; i < n; i++) show(i % 2 ? off : lines, Math.round(ms / n), caption);
};

hold(front, 2600, CAP.front);
show(lastLine(front, choose('S')), 450, CAP.front, 'S');
hold(menu, 2100, CAP.menu);
show(menuPick('', false), 450, CAP.menu, 'F');
hold(menuPick(''), 600, CAP.menu);
show(menuPick('1'), 350, CAP.menu, '1');
show(menuPick('1', false), 300, CAP.menu, 'Enter');
show(loading, 500, CAP.scope);
hold(scope, 3200, CAP.scope);
show(lastLine(scope, choose('E')), 450, CAP.scope, 'E');
show(upto(find(compare, 'Checking logins') + 1), 650, CAP.compare);
show(upto(find(compare, 'analytics.dev.secrets') + 1), 300, CAP.compare);
show(upto(qa), 450, CAP.compare);
show(upto(prod), 450, CAP.compare);
show(upto(prod + 1), 300, CAP.compare);
hold(compare, 2600, CAP.compare);
hold(compare, 3200, CAP.end);

// ---- render --------------------------------------------------------------------
(async () => {
  const rows = Math.max(...shots.map((s) => s.lines.length));
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'brickbat-demo-'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 1200, height: 1000 } });
  const list = [];
  const seen = new Map();
  for (const [i, s] of shots.entries()) {
    if (width(s.lines) > COLS - 2) throw new Error(`frame ${i} is wider than ${COLS - 2} columns`);
    const doc = html(s.lines, COLS, { flat: true, rows, caption: s.caption, key: s.key });
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
