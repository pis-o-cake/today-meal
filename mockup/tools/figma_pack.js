// 화면을 실제로 렌더링한 DOM 을 스크립트 없이 한 장에 가로로 늘어놓은 보드 HTML 을 만든다.
//   node mockup/tools/figma_pack.js              → export/figma/    애니메이션을 한 순간으로 굳힘. Figma 가져오기용
//   node mockup/tools/figma_pack.js --animated   → export/animated/ SVG 애니메이션(SMIL)을 그대로 둠. 보기·공유용
// 둘 다 서버 없이 파일을 더블클릭해 열린다(글꼴은 ../assets). 버튼·화면 이동 같은 동작은 없다.
// 준비(한 번): cd mockup/tools && npm install --no-save playwright && npx playwright install chromium
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const EXPORT = path.resolve(__dirname, '..', 'export');
const ANIMATED = process.argv.includes('--animated');
const OUT = path.join(EXPORT, ANIMATED ? 'animated' : 'figma');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json',
  '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png' };
const DELAY = { Splash: 3200 };

// 확정안만 넣는다. group 은 manifest.json 의 묶음 제목 앞부분.
const PACKS = [
  { file: '01-ios.html', title: 'iOS · 파스텔 (390 × 844)', group: 'iOS' },
  { file: '02-android.html', title: 'Android · 파스텔 (412 × 915)', group: 'Android' },
  { file: '03-white.html', title: '테마 · 화이트', group: '테마 · 화이트' },
  { file: '04-glass.html', title: '테마 · 글래스', group: '테마 · 글래스' },
  { file: '05-dark.html', title: '테마 · 다크', group: '테마 · 다크' },
  { file: '06-assets.html', title: '앱 아이콘 · 탭 아이콘 · 캐릭터 상태', files: ['AppIcon', 'TabIcons', 'Mascot2-states'] },
  { file: '07-added.html', title: '추가 상태 · 앱에서 먼저 만든 화면 (390 × 844)', group: '추가 상태' },
];

// 페이지 안에서 실행: (굳힘 모드) 애니메이션을 지금 모습으로 굳히고, id 를 화면마다 다르게, 그림은 data URI 로.
async function freeze({ prefix, animated }) {
  const PRES = { opacity: 'opacity', 'fill-opacity': 'fillOpacity', 'stroke-opacity': 'strokeOpacity',
    'stroke-dashoffset': 'strokeDashoffset', fill: 'fill', stroke: 'stroke' };
  const host = document.getElementById('dc-root') || document.body;
  if (!animated) {
  document.querySelectorAll('svg').forEach(s => s.pauseAnimations && s.pauseAnimations());
  for (const a of document.getAnimations()) { try { a.pause(); a.commitStyles(); a.cancel(); } catch (e) {} }
  const done = new Set();
  for (const an of [...document.querySelectorAll('animate, animateTransform, animateMotion, set')]) {
    const t = an.parentElement;
    const attr = an.getAttribute('attributeName');
    const key = attr + '|' + (t.__fid || (t.__fid = Math.random()));
    if (!done.has(key)) {
      done.add(key);
      if (an.tagName === 'animateTransform' && t.transform) {
        const list = t.transform.animVal;
        let m = document.createElementNS('http://www.w3.org/2000/svg', 'svg').createSVGMatrix();
        for (let i = 0; i < list.numberOfItems; i++) m = m.multiply(list.getItem(i).matrix);
        t.setAttribute('transform', `matrix(${[m.a, m.b, m.c, m.d, m.e, m.f].map(v => +v.toFixed(4)).join(' ')})`);
      } else if (PRES[attr]) {
        t.setAttribute(attr, getComputedStyle(t)[PRES[attr]]);
      } else if (t[attr] && t[attr].animVal && 'value' in t[attr].animVal) {
        t.setAttribute(attr, +t[attr].animVal.value.toFixed(3));
      }
    }
  }
  document.querySelectorAll('animate, animateTransform, animateMotion, set').forEach(e => e.remove());
  }
  // 화면 소스용 스크립트 블록(<script type="text/x-dc">)은 렌더링에 쓰이지 않는다.
  host.querySelectorAll('script, x-dc').forEach(e => e.remove());
  // SVG 안의 <span>(글자 자리 채움)은 HTML 로 다시 읽을 때 SVG 를 끊어 버린다 → 글자로 바꾼다.
  host.querySelectorAll('svg span').forEach(s => s.replaceWith(document.createTextNode(s.textContent)));

  const ids = new Map();
  host.querySelectorAll('[id]').forEach(el => { const n = prefix + el.id; ids.set(el.id, n); el.id = n; });
  const fix = v => v.replace(/url\(\s*['"]?#([^'")\s]+)['"]?\s*\)/g, (s, id) => ids.has(id) ? `url(#${ids.get(id)})` : s);
  document.querySelectorAll('*').forEach(el => {
    for (const at of [...el.attributes]) {
      if ((at.name === 'href' || at.name === 'xlink:href') && at.value.startsWith('#') && ids.has(at.value.slice(1))) el.setAttribute(at.name, '#' + ids.get(at.value.slice(1)));
      else if (at.value.includes('url(#')) el.setAttribute(at.name, fix(at.value));
    }
  });
  // 링크는 화면 이동용이라 보드에서는 뜻이 없다.
  document.querySelectorAll('a[href]').forEach(a => a.removeAttribute('href'));
  for (const img of [...document.images]) {
    const blob = await (await fetch(img.src)).blob();
    img.src = await new Promise(r => { const f = new FileReader(); f.onload = () => r(f.result); f.readAsDataURL(blob); });
  }
  return {
    styles: [...document.head.querySelectorAll('style')].map(s => s.textContent),
    html: host.innerHTML,
  };
}

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

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
  fs.mkdirSync(OUT, { recursive: true });

  for (const pack of PACKS) {
    const boards = manifest.boards.filter(b => b.png && (pack.files
      ? pack.files.includes(path.basename(b.file, '.dc.html'))
      : b.group.startsWith(pack.group)));
    const styles = new Set();
    const frames = [];
    for (const [i, b] of boards.entries()) {
      const page = await browser.newPage({ viewport: { width: b.width, height: b.height } });
      await page.route('**/*', r => new URL(r.request().url()).hostname === '127.0.0.1' ? r.continue() : r.abort());
      await page.goto(base + b.file, { waitUntil: 'networkidle' });
      await page.evaluate(() => document.fonts.ready);
      const stem = path.basename(b.file, '.dc.html');
      // 움직이는 보드는 애니메이션이 처음부터 다시 돌므로 오래 기다릴 필요가 없다.
      await page.waitForTimeout(ANIMATED ? 600 : (DELAY[stem.replace(/^(Android|White|Glass|Dark)-/, '')] || 1200));
      const snap = await page.evaluate(freeze, { prefix: `s${i}-`, animated: ANIMATED });
      // screens/ 와 figma/ 는 같은 깊이라 ../assets/ 경로가 그대로 맞는다.
      snap.styles.forEach(s => styles.add(s));
      frames.push(`<section class="frame" data-name="${esc(b.title)}">
<h2 class="label">${esc(b.title)}</h2>
<div class="screen" style="width: ${b.width}px; height: ${b.height}px">${snap.html}</div>
</section>`);
      await page.close();
      process.stdout.write('.');
    }
    const html = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>오늘 뭐 먹지? · ${esc(pack.title)}</title>
<!-- ${ANIMATED ? '움직이는 보드: SVG 애니메이션 포함, 스크립트 없음' : 'Figma 가져오기용 정적 보드: 스크립트·애니메이션 없음'}. 글꼴: Pretendard, Jua(배민 주아체) -->
<style>
${[...styles].join('\n')}
html, body { margin: 0; background: #E9EBF0; }
.board { display: flex; align-items: flex-start; gap: 80px; padding: 80px; width: max-content; }
.frame { display: flex; flex-direction: column; gap: 16px; }
.label { margin: 0; font: 600 22px/1.3 'Pretendard', sans-serif; color: #4E5661; letter-spacing: -0.02em; }
.screen { position: relative; overflow: hidden; flex-shrink: 0; background: #FFFFFF; }
</style>
</head>
<body>
<h1 style="margin: 0; padding: 60px 80px 0; font: 400 40px/1.2 'Jua', 'Pretendard', sans-serif; color: #15181D">오늘 뭐 먹지? · ${esc(pack.title)}</h1>
<main class="board">
${frames.join('\n')}
</main>
</body>
</html>
`;
    fs.writeFileSync(path.join(OUT, pack.file), html);
    console.log(` ${pack.file} (${boards.length}화면, ${(html.length / 1024).toFixed(0)}KB)`);
  }
  await browser.close();
  server.close();
})();
