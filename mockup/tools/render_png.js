// mockup/export 의 화면을 PNG 로 찍는다. 외부 네트워크 요청은 막고, 요청이 있었으면 알린다.
//   node mockup/tools/render_png.js                 # manifest 의 모든 보드, 2배율
//   node mockup/tools/render_png.js Main Fridge     # 이름 일부만
//   node mockup/tools/render_png.js --scale 3
// 준비(한 번): cd mockup/tools && npm install --no-save playwright && npx playwright install chromium
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const EXPORT = path.resolve(__dirname, '..', 'export');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json',
  '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png', '.txt': 'text/plain; charset=utf-8' };
// 움직이는 화면은 장면이 다 나온 뒤에 찍는다(ms).
const DELAY = { Splash: 3200 };
// 화면 템플릿의 {{hole}} 을 브라우저가 먼저 읽으며 내는 무해한 경고
const BENIGN = /attribute [\w-]+: (Expected|Invalid value)[^"]*"\{\{/;

const argv = process.argv.slice(2);
const scale = argv.includes('--scale') ? Number(argv[argv.indexOf('--scale') + 1]) : 2;
const only = argv.filter((a, i) => !a.startsWith('--') && argv[i - 1] !== '--scale');

const server = http.createServer((req, res) => {
  const rel = decodeURIComponent(new URL(req.url, 'http://x').pathname).replace(/^\/+/, '');
  const file = path.join(EXPORT, rel || 'index.html');
  if (!file.startsWith(EXPORT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});

(async () => {
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}/`;
  const manifest = JSON.parse(fs.readFileSync(path.join(EXPORT, 'manifest.json'), 'utf8'));
  const boards = manifest.boards.filter(b => b.png && (!only.length || only.some(o => b.file.includes(o))));
  const browser = await chromium.launch();
  const external = new Set();
  const errors = [];
  for (const b of boards) {
    const page = await browser.newPage({ viewport: { width: b.width, height: b.height }, deviceScaleFactor: scale });
    await page.route('**/*', route => {
      const u = new URL(route.request().url());
      if (u.hostname === '127.0.0.1' || u.protocol === 'data:' || u.protocol === 'blob:') return route.continue();
      external.add(u.origin); return route.abort();
    });
    page.on('console', m => { if (m.type() === 'error' && !BENIGN.test(m.text())) errors.push(`${b.file}: ${m.text().slice(0, 160)}`); });
    page.on('pageerror', e => errors.push(`${b.file}: ${e.message.slice(0, 160)}`));
    await page.goto(base + b.file, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    const stem = path.basename(b.file, '.dc.html');
    await page.waitForTimeout(DELAY[stem.replace(/^(Android|White|Glass|Dark|Jua|C2|C3)-/, '')] || 1200);
    fs.mkdirSync(path.join(EXPORT, 'png'), { recursive: true });
    await page.screenshot({ path: path.join(EXPORT, b.png) });
    await page.close();
    process.stdout.write('.');
  }
  await browser.close();
  server.close();
  console.log(`\nPNG ${boards.length}개 → ${path.relative(process.cwd(), path.join(EXPORT, 'png'))} (배율 ${scale})`);
  if (external.size) console.log('외부 요청(차단됨):', [...external].join(', '));
  if (errors.length) { console.log('오류:'); errors.slice(0, 30).forEach(e => console.log('  ' + e)); process.exitCode = 1; }
})();
