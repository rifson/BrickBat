// Renders the README screenshots of BrickBat as Windows Terminal windows, with fictional data.
// Layout follows brickbat.bat: same prefixes, padding widths and colours (Campbell scheme),
// so update a screen here when its menu changes in the script.
//
//   cd tools && npm install && npx playwright install chromium
//   node render-screenshots.js ../docs/screenshots [screen ...]
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const OUT = process.argv[2];
const FONT = path.join(__dirname, 'node_modules/@fontsource/cascadia-mono/files');
// inlined, because a page made with setContent() may not load file:// fonts
const font = (n) => 'data:font/woff2;base64,' +
  fs.readFileSync(path.join(FONT, `cascadia-mono-${n}-normal.woff2`)).toString('base64');

// ---- segments ---------------------------------------------------------------
const seg = (c) => (t) => ({ c, t });
const k = seg('key'), d = seg('dim'), h = seg('head'), ok = seg('ok'), er = seg('err'),
  wn = seg('warn'), br = seg('brand');
const P = (s, n) => (s.length >= n ? s : s + ' '.repeat(n - s.length));
const L = (s, n) => (s.length >= n ? s : ' '.repeat(n - s.length) + s);
const line = (...parts) => parts.map((p) => (typeof p === 'string' ? { c: '', t: p } : p));
const CURSOR = { c: 'cursor', t: '' };

// ---- fictional environment --------------------------------------------------
const VER = 'v1.1.0', CLI = 'CLI v0.298.0';
const USER = 'jane.doe@example.com';
const PROFILES = [
  { name: 'dev', host: 'https://acme-dev.cloud.databricks.com', ok: true, def: true },
  { name: 'qa', host: 'https://acme-qa.cloud.databricks.com', ok: true },
  { name: 'prod', host: 'https://acme-prod.cloud.databricks.com', ok: false },
  { name: 'azure-sandbox', host: 'https://adb-1234567890123456.7.azuredatabricks.net', ok: true },
];
const ACTIVE = PROFILES[0];

// ---- building blocks copied from the script ---------------------------------
const banner = () => [
  line(),
  line('  ', seg('b1')('██████╗ ██████╗ ██╗ ██████╗██╗  ██╗██████╗  █████╗ ████████╗')),
  line('  ', seg('b2')('██╔══██╗██╔══██╗██║██╔════╝██║ ██╔╝██╔══██╗██╔══██╗╚══██╔══╝')),
  line('  ', seg('b3')('██████╔╝██████╔╝██║██║     █████╔╝ ██████╔╝███████║   ██║')),
  line('  ', seg('b4')('██╔══██╗██╔══██╗██║██║     ██╔═██╗ ██╔══██╗██╔══██║   ██║')),
  line('  ', seg('b5')('██████╔╝██║  ██║██║╚██████╗██║  ██╗██████╔╝██║  ██║   ██║')),
  line('  ', seg('b6')('╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝   ╚═╝')),
  line('  ', d(`a menu for the Databricks CLI  ·  unofficial  ·  ${VER}      ${CLI}`)),
];
const screen = (title, prof = ACTIVE) => [
  line(),
  line('  ', br('█ BRICKBAT'), '  ', d('·'), '  ', h(title)),
  line('  ', d(`profile ${prof.name}   ${prof.host}`)),
  line('  ', d('─'.repeat(78))),
];
const choose = () => [line('   Choose: ', CURSOR)];
const prompt = (text) => [line(text, CURSOR)];
const profileRow = (p, i, num) => {
  const mark = p === ACTIVE ? ['  ', br('►'), ' '] : ['    '];
  const n = num ? [k(L(String(i + 1), 2)), '  '] : [];
  const s = p.ok ? ok('● logged in    ') : er('○ not logged in');
  const x = p.def ? ['  ', d('CLI default')] : [];
  return line(...mark, ...n, P(p.name, 16), ' ', s, '  ', d(p.host), ...x);
};
const listRow = (i, name, type = 'Databricks') =>
  line(' ', k(L(String(i), 4)), '  ', P(name, 48), ' ', d(type));
const secretRow = (i, name, date) => line(' ', k(L(String(i), 4)), '  ', P(name, 44), ' ', d(date));
const aclRow = (i, prin, perm) => {
  const col = perm === 'MANAGE' ? br : perm === 'WRITE' ? wn : ok;
  const guid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(prin);
  return line(' ', k(L(String(i), 4)), '  ', P(prin, 52), ' ', col(P(perm, 6)),
    ...(guid ? ['  ', d('service principal')] : []));
};

// ---- screens ----------------------------------------------------------------
const screens = {};

screens['front-page'] = [
  ...banner(),
  line(),
  line('  ', d('Profile    '), h(ACTIVE.name), '   ', d('CLI default')),
  line('  ', d('Workspace  '), ACTIVE.host),
  line('  ', d('Status     '), ok('● Logged in'), ' as ', h(USER)),
  line(),
  line('  ', d('ENVIRONMENTS')),
  ...PROFILES.map((p, i) => profileRow(p, i)),
  line(),
  line('  ', k('[S]'), ' Secrets          ', k('[P]'), ' Switch profile    ', k('[T]'), ' Terminal with this profile'),
  line('  ', k('[L]'), ' Log in again     ', k('[N]'), ' New profile       ', k('[W]'), ' Open workspace in browser'),
  line('  ', k('[O]'), ' Log out          ', k('[I]'), ' Info and update   ', k('[R]'), ' Refresh   ', k('[Q]'), ' Quit'),
  line(),
  ...choose(),
];

screens['switch-profile'] = [
  ...screen('Switch profile'),
  line(),
  ...PROFILES.map((p, i) => profileRow(p, i, true)),
  line(),
  line('  ', d('The profile you pick also becomes the default for plain databricks commands.')),
  ...prompt('   Profile number (blank = back): '),
];

screens['secrets-menu'] = [
  ...screen('Secrets'),
  line(),
  line('  ', d('Secrets live in scopes. Access is granted per scope and covers every secret in it.')),
  line(),
  line('  ', k('[1]'), ' Show all scopes in ', h('dev')),
  line('  ', k('[2]'), ' Search scopes by name'),
  line('  ', k('[3]'), ' Compare one scope across environments'),
  line('  ', k('[4]'), ' Create a new scope in ', h('dev')),
  line('  ', k('[F]'), ' Open a favourite'),
  line('  ', k('[B]'), ' Back'),
  line(),
  line('  ', d('FAVOURITES')),
  ...['payments.dev.secrets', 'warehouse.dev.secrets', 'ingest_dev']
    .map((n, i) => line(' ', k(L(String(i + 1), 4)), '  ', n)),
  line(),
  line('  ', d("Looking inside scopes for a key or someone's access costs one call per scope,")),
  line('  ', d('so it is offered once a list is down to 20 scopes or fewer.')),
  line(),
  ...choose(),
];

const ALL = [
  'analytics-sandbox', 'analytics.dev.legacy', 'analytics.dev.secrets', 'analytics_exports',
  'billing-api', 'crm-sync.dev', 'data-platform-admin', 'finance-reports.dev', 'ingest_dev', 'kafka.ingest.dev', 'marketing.dev.secrets',
  'ml-feature-store', 'payments.dev.secrets', 'search-index.dev', 'warehouse.dev.secrets',
];
// 214 rows scroll past, so the window shows the end of the list, as a real terminal does
const TAIL = [
  'search-index.dev', 'sharepoint-sync', 'slack-alerts', 'snowflake-migration',
  'spark-streaming.dev.secrets', 'support-tools', 'tableau-extracts', 'tax-engine.dev',
  'telemetry.dev.secrets', 'terraform-ci', 'translations-api', 'user-events.dev', 'vault-sync',
  'warehouse.dev.secrets', 'weather-feed', 'web-analytics.dev.secrets',
  'workflows-api', 'zendesk-export',
];
screens['scope-list'] = [
  ...TAIL.map((n, i) => listRow(214 - TAIL.length + 1 + i, n)),
  line(),
  line('  ', d('214 scopes')),
  line(),
  line('  ', k('[O]'), ' Open a scope     ', k('[F]'), ' Filter by name     ', k('[B]'), ' Back'),
  line('  ', d("Filter down to 20 scopes or fewer to look inside them for a key or someone's access.")),
  line(),
  ...choose(),
];

const FILTERED = ['analytics-sandbox', 'analytics.dev.legacy', 'analytics.dev.secrets',
  'analytics_exports', 'web-analytics.dev.secrets'];
// a search in every logged-in environment, filtered by name
const SEARCH = [
  ['dev', 'analytics-sandbox'], ['dev', 'analytics.dev.legacy'], ['dev', 'analytics.dev.secrets'],
  ['dev', 'analytics_exports'], ['dev', 'web-analytics.dev.secrets'], ['qa', 'analytics.qa.secrets'],
  ['qa', 'analytics_exports'], ['azure-sandbox', 'analytics.sandbox.secrets'],
];
const searchRow = (i) => line(' ', k(L(String(i), 4)), '  ', P(SEARCH[i - 1][0], 14), ' ', P(SEARCH[i - 1][1], 48), ' ', d('Databricks'));
screens['scope-filter'] = [
  ...screen('Scopes matching analytics'),
  line(),
  ...[3, 5, 6, 8].map(searchRow),
  line(),
  line('  ', d('Filter: secrets  -  4 of 8 scopes shown')),
  line(),
  line('  ', k('[O]'), ' Open a scope     ', k('[F]'), ' Filter by name     ', k('[B]'), ' Back'),
  line('  ', k('[V]'), ' Show the keys and access of these 4 scopes'),
  line('  ', k('[U]'), ' Add or update a key in some or all of them'),
  line('  ', k('[G]'), ' Grant or change access in some or all of them'),
  line('  ', k('[K]'), ' Find a key in these 4 scopes'),
  line('  ', k('[P]'), " Check someone's access on these 4 scopes"),
  line(),
  ...choose(),
];

// U on that list, for 3 6 8: what changes in each scope, before anything is saved
const planRow = (i, state) => line(' ', k(L(String(i), 4)), '  ', P(SEARCH[i - 1][0], 14), ' ', P(SEARCH[i - 1][1], 44), ' ', state);
screens['scope-set'] = [
  ...screen('Add or update api_key in 3 scopes'),
  line(),
  line('  ', d('Checking which of them have api_key already - one call per scope.')),
  line(),
  planRow(3, wn('replaces the current value')),
  planRow(6, wn('replaces the current value')),
  planRow(8, ok('new key')),
  line(),
  line('  ', k('[T]'), ' Type or paste a value for each scope - the CLI asks once per scope, hidden'),
  line('  ', k('[F]'), ' The same value for every scope, read from a file'),
  line('  ', k('[B]'), ' Back'),
  line(),
  ...choose(),
];

screens['scope'] = [
  ...screen('Scope analytics.dev.secrets'),
  line(),
  line('  ', d('Scope        '), h('analytics.dev.secrets')),
  line('  ', d('Backend      '), 'Databricks'),
  line('  ', d('Environment  '), 'dev  ', d(ACTIVE.host)),
  line(),
  line('  ', h('SECRETS'), '  ', d('keys only, values are never shown')),
  secretRow(1, 'api_key', '2026-07-28 11:30 UTC'),
  secretRow(2, 'service_account.json', '2026-05-02 08:15 UTC'),
  secretRow(3, 'warehouse_token', '2026-09-20 10:00 UTC'),
  line(),
  line('  ', h('ACCESS'), '  ', d('applies to every secret in this scope')),
  aclRow(1, 'data-platform-admins', 'MANAGE'),
  aclRow(2, 'analytics-engineers', 'WRITE'),
  aclRow(3, 'analytics-readers', 'READ'),
  aclRow(4, '7c1e9a52-3f4b-4d8e-9a61-2b5c8d0e4f17', 'MANAGE'),
  line(),
  line('  ', k('[A]'), ' Add or update a secret     ', k('[D]'), ' Delete a secret'),
  line('  ', k('[G]'), ' Grant or change access     ', k('[X]'), ' Remove access'),
  line('  ', k('[S]'), ' Save as favourite          ', k('[E]'), ' This scope in every environment'),
  line('  ', k('[Z]'), ' Delete this scope          ', k('[R]'), ' Reload        ', k('[B]'), ' Back'),
  line(),
  ...choose(),
];

const cmpEnv = (p, scope, keys, acls) => [
  line('  ', h(p.name), '  ', d(p.host)),
  line('  ', d('  Scope  '), h(scope)),
  line('  ', d('  Keys')),
  ...keys.map(([n, t], i) => secretRow(i + 1, n, t)),
  line('  ', d('  Access')),
  ...acls.map(([n, r], i) => aclRow(i + 1, n, r)),
  line(),
];
screens['compare'] = [
  ...screen('analytics.*.secrets in every environment'),
  line(),
  line('  ', d('* is one of: dev test tst qa uat stg stage staging preprod prod prd')),
  line('  ', d('Checking logins...')),
  line(),
  ...cmpEnv(PROFILES[0], 'analytics.dev.secrets',
    [['api_key', '2026-07-28 11:30 UTC'], ['service_account.json', '2026-05-02 08:15 UTC'],
      ['warehouse_token', '2026-09-20 10:00 UTC']],
    [['data-platform-admins', 'MANAGE'], ['analytics-engineers', 'WRITE'], ['analytics-readers', 'READ'],
      ['7c1e9a52-3f4b-4d8e-9a61-2b5c8d0e4f17', 'MANAGE']]),
  ...cmpEnv(PROFILES[1], 'analytics.qa.secrets',
    [['api_key', '2026-08-04 09:12 UTC']],
    [['data-platform-admins', 'MANAGE'], ['analytics-readers', 'READ']]),
  line('  ', d('prod - skipped, not logged in')),
  line('  ', h('azure-sandbox'), '  ', d(PROFILES[3].host)),
  line('  ', d('  No matching scope here.')),
  line(),
  line(),
  line('  ', d(' Press any key to continue...'), CURSOR),
];

screens['new-profile'] = [
  ...screen('New profile'),
  line(),
  line('  Connect a Databricks workspace. You sign in with your own account in the browser.'),
  line('  ', d('The CLI cannot create Databricks users - your admins add those - so this adds a profile.')),
  line(),
  line('  Paste the workspace URL. Straight from the browser address bar is fine.'),
  line('  ', d('For example  https://dbc-a1b2c3d4-e5f6.cloud.databricks.com        AWS')),
  line('  ', d('             https://adb-1234567890123456.7.azuredatabricks.net    Azure')),
  line('  ', d('             https://1234567890123456.7.gcp.databricks.com         Google Cloud')),
  line(),
  line('   Workspace URL (blank = back): https://acme-staging.cloud.databricks.com'),
  line('  ', d('Using https://acme-staging.cloud.databricks.com')),
  line(),
  line('  Give the profile a short name you will recognise, for example dev, test or prod.'),
  ...prompt('   Profile name (blank = back): staging'),
];

const PS = (cmd) => line(br('[BrickBat:dev]'), ' C:\\Users\\jane>', cmd);
screens['terminal'] = [
  line(),
  line('  ', br('█ BRICKBAT'), '  ', d('·'), '  ', h('Terminal for dev')),
  line(),
  line('  Every databricks command in here uses profile ', h('dev'), '  ', d(ACTIVE.host)),
  line('  Type ', h('exit'), ' to go back to BrickBat.'),
  line(),
  line('  ', d('Try:  databricks current-user me     databricks clusters list     databricks secrets list-scopes')),
  line(),
  // piped, so the CLI prints no colours; the column fits the longest scope name in the workspace
  PS('databricks secrets list-scopes | findstr analytics'),
  ...FILTERED.map((n) => line(P(n, 29), 'DATABRICKS')),
  line(),
  [...PS(''), CURSOR],
];

// ---- page -------------------------------------------------------------------
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
// For the animated demo: flat drops the padding and shadow, rows fixes the height so frames
// line up, caption adds a strip under the terminal, key shows the key just pressed in it
const inter = (w) => 'data:font/woff2;base64,' + fs.readFileSync(
  path.join(__dirname, `node_modules/@fontsource/inter/files/inter-latin-${w}-normal.woff2`)).toString('base64');
const captionCss = () => `@font-face{font-family:Inter;src:url(${inter(400)});font-weight:400}
@font-face{font-family:Inter;src:url(${inter(600)});font-weight:600}
.cap{height:48px;display:flex;align-items:center;gap:12px;padding:0 20px;background:#151515;
  border-top:1px solid #272727;font:400 16px Inter,sans-serif;color:#e9e9e9;letter-spacing:.1px}
.cap .mark{width:4px;height:20px;background:#ff3621;border-radius:2px;flex:none}
.cap kbd{margin-left:auto;min-width:16px;padding:3px 10px 2px;border:1px solid #4d4d4d;border-bottom-width:3px;
  border-radius:6px;background:#242424;font:600 14px Inter,sans-serif;color:#fff;text-align:center}`;
const html = (lines, cols, { flat = false, rows = 0, caption, key } = {}) => `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:Cascadia;src:url(${font('latin-400')});font-weight:400;unicode-range:U+0000-00FF,U+2000-206F}
@font-face{font-family:Cascadia;src:url(${font('latin-700')});font-weight:700;unicode-range:U+0000-00FF,U+2000-206F}
@font-face{font-family:Cascadia;src:url(${font('symbols2-400')});font-weight:400 700;unicode-range:U+2500-259F}
html,body{margin:0;background:transparent}
.pad{display:inline-block;padding:${flat ? 0 : '28px 34px 40px'}}
.win{display:inline-block;background:#0c0c0c;border-radius:8px;overflow:hidden;
  box-shadow:${flat ? 'none' : '0 14px 34px rgba(0,0,0,.38),0 0 0 1px rgba(255,255,255,.07)'}}
.bar{height:40px;background:#202020;display:flex;align-items:flex-end;font:12px "Segoe UI",system-ui,sans-serif;color:#fff}
.tab{height:32px;margin-left:8px;padding:0 10px 0 12px;background:#0c0c0c;border-radius:6px 6px 0 0;
  display:flex;align-items:center;gap:10px;min-width:200px}
.tab .ic{width:14px;height:11px;border:1px solid #9a9a9a;border-radius:2px;font:7px/11px monospace;color:#ddd;text-indent:1px;box-sizing:border-box;overflow:hidden}
.tab .x{margin-left:auto;color:#ccc;font-size:13px}
.plus{height:32px;display:flex;align-items:center;gap:16px;padding:0 14px;color:#ccc;font-size:16px}
.plus span:last-child{font-size:10px;padding-left:12px;border-left:1px solid #444;line-height:14px}
.ctl{margin-left:auto;align-self:stretch;display:flex}
.ctl span{width:46px;display:flex;align-items:center;justify-content:center}
.ctl svg{stroke:#ddd;stroke-width:1;fill:none}
pre{margin:0;padding:10px 14px 18px;font:15px/18px Cascadia,"DejaVu Sans Mono",monospace;color:#cccccc;
  width:${cols}ch;${rows ? `height:${rows * 18}px;` : ''}white-space:pre;-webkit-font-smoothing:antialiased}
.key{color:#61d6d6}.dim{color:#767676}.head{color:#f2f2f2;font-weight:700}.ok{color:#16c60c}
.err{color:#e74856}.warn{color:#f9f1a5}.brand{color:#ff3621}.pq{color:#3b78ff;font-weight:700}
.b1{color:#ff8058}.b2{color:#ff6844}.b3{color:#ff5032}.b4{color:#ff3621}.b5{color:#de2c1c}.b6{color:#962418}
.cursor{display:inline-block;width:2px;height:16px;background:#cccccc;vertical-align:-3px}
.cursor.off{visibility:hidden}
${caption === undefined ? '' : captionCss()}
</style></head><body><div class="pad"><div class="win">
<div class="bar"><div class="tab"><div class="ic">C:\\</div>BrickBat<span class="x">✕</span></div>
<div class="plus"><span>+</span><span>⌄</span></div>
<div class="ctl"><span><svg width="10" height="10"><path d="M0 5.5h10"/></svg></span>
<span><svg width="10" height="10"><rect x=".5" y=".5" width="9" height="9"/></svg></span>
<span><svg width="10" height="10"><path d="M0 0l10 10M10 0L0 10"/></svg></span></div></div>
<pre>
${lines.map((l) => l.map((s) => s.c ? `<span class="${s.c}">${esc(s.t)}</span>` : esc(s.t)).join('')).join('\n')}</pre>
${caption === undefined ? '' : `<div class="cap"><span class="mark"></span><span>${esc(caption)}</span>${key ? `<kbd>${esc(key)}</kbd>` : ''}</div>`}
</div></div></body></html>`;

const width = (lines) => Math.max(...lines.map((l) => l.reduce((n, s) => n + [...s.t].length, 0)));
module.exports = { k, d, h, ok, er, wn, br, P, L, line, CURSOR, PROFILES, ACTIVE, banner, screen, screens, html, width,
  SEARCH, searchRow };

if (require.main === module) (async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 1400, height: 900 } });
  const only = process.argv.slice(3);
  for (const [name, lines] of Object.entries(screens)) {
    if (only.length && !only.includes(name)) continue;
    await page.setContent(html(lines, Math.max(width(lines) + 2, 96)));
    await page.evaluate(() => document.fonts.ready);
    const el = await page.$('.pad');
    await el.screenshot({ path: path.join(OUT, `${name}.png`), omitBackground: true });
    console.log('wrote', name);
  }
  await browser.close();
})();
