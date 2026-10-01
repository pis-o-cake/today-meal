// Figma 처럼 보는 단일 HTML 뷰어를 만든다 → export/today-meal-mockup.html
// 무한 캔버스(이동·확대), 레이어·속성 패널, 프레젠테이션(버튼·탭을 눌러 화면 이동), SVG 애니메이션을 담는다.
// 글꼴은 쓰인 글자만 잘라 파일 안에 넣으므로 이 파일 하나만 보내도 열린다(서버 불필요).
//   node mockup/tools/viewer.js
// 준비(한 번): cd mockup/tools && npm install --no-save playwright && npx playwright install chromium
//            글꼴 자르기에 fonttools 가 있으면 파일이 작아진다(pip install fonttools brotli). 없으면 글꼴 전체를 넣는다.
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const EXPORT = path.resolve(__dirname, '..', 'export');
const OUT = path.join(EXPORT, 'today-meal-mockup.html');
const TEMPLATE = path.join(__dirname, 'viewer.template.html');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json',
  '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png' };

// 확정안만. group 은 manifest.json 의 묶음 제목 앞부분.
const SECTIONS = [
  { id: 'ios', title: 'iOS · 파스텔 (기본)', group: 'iOS' },
  { id: 'android', title: 'Android · 파스텔', group: 'Android' },
  { id: 'white', title: '테마 · 화이트', group: '테마 · 화이트' },
  { id: 'glass', title: '테마 · 글래스', group: '테마 · 글래스' },
  { id: 'dark', title: '테마 · 다크', group: '테마 · 다크' },
  { id: 'added', title: '추가 상태 · 앱에서 먼저 만든 화면', group: '추가 상태' },
  { id: 'assets', title: '앱 아이콘 · 탭 아이콘 · 캐릭터', files: ['AppIcon', 'TabIcons', 'Mascot2-states'] },
];
const GAP = 60, PAD_X = 60, PAD_TOP = 64, PAD_BOTTOM = 60, SECTION_GAP = 150;

// 페이지 안에서 실행: 스크립트를 걷어 내고, 화면 이동 링크는 data-go 로, id 는 화면마다 다르게, 그림은 data URI 로.
async function snapshot(prefix) {
  const host = document.getElementById('dc-root') || document.body;
  host.querySelectorAll('script, x-dc').forEach(e => e.remove());
  // SVG 안의 <span>(글자 자리 채움)은 HTML 로 다시 읽을 때 SVG 를 끊어 버린다 → 글자로 바꾼다.
  host.querySelectorAll('svg span').forEach(s => s.replaceWith(document.createTextNode(s.textContent)));
  const links = new Set();
  host.querySelectorAll('a[href]').forEach(a => {
    const m = a.getAttribute('href').match(/([^/]+)\.dc\.html$/);
    if (m) { a.setAttribute('data-go', m[1]); links.add(m[1]); }
    a.removeAttribute('href');
  });
  const ids = new Map();
  host.querySelectorAll('[id]').forEach(el => { const n = prefix + el.id; ids.set(el.id, n); el.id = n; });
  const fix = v => v.replace(/url\(\s*['"]?#([^'")\s]+)['"]?\s*\)/g, (s, id) => ids.has(id) ? `url(#${ids.get(id)})` : s);
  host.querySelectorAll('*').forEach(el => {
    for (const at of [...el.attributes]) {
      if ((at.name === 'href' || at.name === 'xlink:href') && at.value.startsWith('#') && ids.has(at.value.slice(1))) el.setAttribute(at.name, '#' + ids.get(at.value.slice(1)));
      else if (at.value.includes('url(#')) el.setAttribute(at.name, fix(at.value));
    }
  });
  for (const img of [...host.querySelectorAll('img')]) {
    const blob = await (await fetch(img.src)).blob();
    img.src = await new Promise(r => { const f = new FileReader(); f.onload = () => r(f.result); f.readAsDataURL(blob); });
  }
  return { html: host.innerHTML, links: [...links] };
}

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');

function fontFace(family, file, weight, text) {
  const src = path.join(EXPORT, 'assets', 'fonts', file);
  let data = fs.readFileSync(src);
  try {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'viewer-font-'));
    const txt = path.join(dir, 'chars.txt'), out = path.join(dir, 'out.woff2');
    fs.writeFileSync(txt, text);
    execFileSync('pyftsubset', [src, `--text-file=${txt}`, '--flavor=woff2', `--output-file=${out}`,
      '--layout-features=*', '--unicodes=U+0020-007E,U+00A0-00FF,U+2000-206F,U+2190-21FF,U+2212,U+2715,U+00B7'], { stdio: 'ignore' });
    data = fs.readFileSync(out);
    fs.rmSync(dir, { recursive: true, force: true });
  } catch (e) {
    console.log(`  (${family}: 글꼴 자르기 없이 전체를 넣음 — fonttools 가 없거나 실패)`);
  }
  return `@font-face{font-family:'${family}';src:url(data:font/woff2;base64,${data.toString('base64')}) format('woff2');font-weight:${weight};font-style:normal;font-display:block}`;
}

(async () => {
  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(new URL(req.url, 'http://x').pathname).replace(/^\/+/, '');
    const file = path.join(EXPORT, rel);
    if (!file.startsWith(EXPORT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}/`;
  const manifest = JSON.parse(fs.readFileSync(path.join(EXPORT, 'manifest.json'), 'utf8'));
  const browser = await chromium.launch();

  const sections = [];
  const parts = [];
  let y = 0, n = 0, maxW = 0;
  for (const sec of SECTIONS) {
    const boards = manifest.boards.filter(b => b.png && (sec.files
      ? sec.files.includes(path.basename(b.file, '.dc.html'))
      : b.group.startsWith(sec.group)));
    const s = { id: sec.id, title: sec.title, x: 0, y, frames: [] };
    let x = PAD_X, rowH = 0;
    const frameHtml = [];
    for (const b of boards) {
      const id = path.basename(b.file, '.dc.html');
      const page = await browser.newPage({ viewport: { width: b.width, height: b.height } });
      await page.route('**/*', r => new URL(r.request().url()).hostname === '127.0.0.1' ? r.continue() : r.abort());
      await page.goto(base + b.file, { waitUntil: 'networkidle' });
      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(500);
      const snap = await page.evaluate(snapshot, `f${n++}-`);
      await page.close();
      const m = id.match(/^(Android|White|Glass|Dark)-/);
      const f = { id, name: b.title, x, y: y + PAD_TOP, w: b.width, h: b.height, links: snap.links.filter(l => l !== id),
        platform: sec.id === 'assets' ? '' : (m && m[1] === 'Android' ? 'Android 412 × 915' : 'iOS 390 × 844'),
        theme: sec.id === 'assets' ? '' : ({ White: '화이트', Glass: '글래스', Dark: '다크' }[m && m[1]] || '파스텔') };
      s.frames.push(f);
      frameHtml.push(`<div class="frame" id="F-${esc(id)}" data-id="${esc(id)}" style="left:${f.x}px;top:${f.y}px;width:${f.w}px;height:${f.h}px;--fw:${f.w}">`
        + `<div class="label">${esc(f.name)}</div>`
        + `<div class="screen" style="width:${f.w}px;height:${f.h}px">${snap.html}</div>`
        + `<div class="hit"></div><i class="h a"></i><i class="h b"></i><i class="h c"></i><i class="h d"></i>`
        + `<div class="size">${f.w} × ${f.h}</div></div>`);
      x += b.width + GAP; rowH = Math.max(rowH, b.height);
      process.stdout.write('.');
    }
    s.w = x - GAP + PAD_X; s.h = PAD_TOP + rowH + PAD_BOTTOM;
    maxW = Math.max(maxW, s.w);
    parts.push(`<section class="section" style="left:0;top:${y}px;width:${s.w}px;height:${s.h}px"><div class="chip" data-sec="${s.id}">${esc(s.title)}</div></section>`);
    parts.push(...frameHtml);
    sections.push(s);
    y += s.h + SECTION_GAP;
    console.log(` ${sec.title} ${boards.length}`);
  }
  await browser.close();
  server.close();

  const data = { title: '오늘 뭐 먹지? · 앱 목업', file: '앱 목업', sections, bounds: { x: 0, y: -40, w: maxW, h: y - SECTION_GAP + 40 } };
  const template = fs.readFileSync(TEMPLATE, 'utf8');
  const framesHtml = parts.join('\n');
  // 글꼴은 이 파일에 실제로 쓰인 글자만 남긴다.
  const text = [...new Set(framesHtml.replace(/<[^>]+>/g, ' ') + template + JSON.stringify(data)
    + [...framesHtml.matchAll(/(?:placeholder|aria-label|value)="([^"]*)"/g)].map(m => m[1]).join(''))].join('');
  const fonts = fontFace('Pretendard', 'PretendardVariable.woff2', '45 920', text) + '\n' + fontFace('Jua', 'Jua-Regular.woff2', '400', text);
  const html = template
    .replace('@TITLE@', esc(data.title))
    .replace('@PROJECT@', '오늘 뭐 먹지?').replace('@FILE@', esc(data.file))
    .replace('@FONTS@', () => fonts)
    .replace('@FRAMES@', () => framesHtml)
    .replace('@DATA@', () => JSON.stringify(data).replace(/</g, '\\u003c'));
  fs.writeFileSync(OUT, html);
  console.log(`→ ${path.relative(process.cwd(), OUT)} (${(html.length / 1024 / 1024).toFixed(2)}MB, 화면 ${n}개)`);
})();
