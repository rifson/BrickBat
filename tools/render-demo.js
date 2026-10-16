// Renders the animated README demo: front page -> Secrets -> compare one scope across
// environments. Built from the same screens as render-screenshots.js, with fictional data,
// so update those screens when the script's menus change.
//
//   cd tools && npm install && npx playwright install chromium
//   node render-demo.js ../docs/screenshots/demo.gif      (needs ffmpeg on PATH)
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { d, h, line, CURSOR, PROFILES, screen, screens, html, width } = require('./render-screenshots.js');

const OUT = path.resolve(process.argv[2] || 'demo.gif');
const COLS = 96;

// the last line of a menu screen is "   Choose: |"; choice echoes the key that was pressed
const withLast = (lines, last) => [...lines.slice(0, -1), last];
const typed = (prompt, text, cursor = true) => line(prompt + text, ...(cursor ? [CURSOR] : []));

const comparePrompt = (text, cursor = true) => [
  ...screen('Compare a scope across environments'),
  line(),
  line('  Type the scope name as it is in one environment. When the name has an environment'),
  line('  word in it, like the dev in analytics.dev.secrets or analytics_dev, the other'),
  line('  environments are searched with that word swapped - qa, prod and so on.'),
  line(),
  typed('   Scope name (blank = back): ', text, cursor),
];

// the compare screen fills in as each environment answers
const compare = screens['compare'];
const at = (text) => compare.findIndex((l) => l.some((s) => s.t.includes(text)));
const upto = (i) => compare.slice(0, i);
const qaStart = at(PROFILES[1].host);
const prodLine = at('prod - skipped');

const frames = [
  [withLast(screens['front-page'], line('   Choose: ', CURSOR)), 1900],
  [withLast(screens['front-page'], line('   Choose: S')), 350],
  [screens['secrets-menu'], 1600],
  [withLast(screens['secrets-menu'], line('   Choose: 3')), 350],
  [comparePrompt(''), 700],
  ...[...'analytics.dev.secrets'].map((_, i, a) => [comparePrompt(a.slice(0, i + 1).join('')), 55]),
  [comparePrompt('analytics.dev.secrets'), 600],
  [upto(at('Checking logins') + 1), 700],
  [upto(at('analytics.dev.secrets') + 1), 300],
  [upto(qaStart), 450],
  [upto(prodLine), 450],
  [upto(prodLine + 1), 300],
  [compare, 4200],
];

(async () => {
  const rows = Math.max(...frames.map(([l]) => l.length));
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'brickbat-demo-'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 1200, height: 900 } });
  const list = [];
  for (const [i, [lines, ms]] of frames.entries()) {
    if (width(lines) > COLS - 2) throw new Error(`frame ${i} is wider than ${COLS - 2} columns`);
    await page.setContent(html(lines, COLS, { flat: true, rows }));
    await page.evaluate(() => document.fonts.ready);
    const file = path.join(tmp, `f${String(i).padStart(3, '0')}.png`);
    await (await page.$('.win')).screenshot({ path: file, omitBackground: true });
    list.push(`file '${file}'`, `duration ${ms / 1000}`);
  }
  await browser.close();
  // ffmpeg's concat demuxer needs the last file once more for its duration to count
  list.push(list[list.length - 2]);
  fs.writeFileSync(path.join(tmp, 'frames.txt'), list.join('\n') + '\n');
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', path.join(tmp, 'frames.txt'),
    '-filter_complex', // rendered at 2x and scaled down smoothly, so line-drawing characters join up
    'format=rgba,scale=1120:-1:flags=lanczos,split[a][b];[a]palettegen=reserve_transparent=1:stats_mode=full[p];[b][p]paletteuse=dither=none:alpha_threshold=128',
    '-fps_mode', 'vfr', '-loop', '0', OUT]);
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log('wrote', OUT, `${frames.length} frames, ${(fs.statSync(OUT).size / 1024).toFixed(0)} KB`);
})();
