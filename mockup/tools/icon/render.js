// 앱 아이콘 SVG → PNG. 인자 없이 실행하면 docs/assets/app-icon 의 표준 파일을 모두 다시 만든다.
//   node mockup/tools/icon/render.js
//   node mockup/tools/icon/render.js '[{"svg":"a.svg","out":"a.png","size":1024,"transparent":false}]'
// 필요: npm i playwright && npx playwright install chromium
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const ICON = path.resolve(__dirname, '..', '..', '..', 'docs', 'assets', 'app-icon');
const DEFAULT_JOBS = [
  { svg: 'svg/app-icon.svg', out: 'ios/AppIcon-1024.png', size: 1024 },
  { svg: 'svg/app-icon-dark.svg', out: 'ios/AppIcon-Dark-1024.png', size: 1024 },
  { svg: 'svg/android-foreground.svg', out: 'android/ic_launcher_foreground.png', size: 432, transparent: true },
  { svg: 'svg/android-background.svg', out: 'android/ic_launcher_background.png', size: 432 },
  { svg: 'svg/app-icon.svg', out: 'android/playstore-512.png', size: 512 },
].map(j => ({ ...j, svg: path.join(ICON, j.svg), out: path.join(ICON, j.out) }));

(async () => {
  const jobs = process.argv[2] ? JSON.parse(process.argv[2]) : DEFAULT_JOBS;
  const b = await chromium.launch();
  for (const j of jobs) {
    fs.mkdirSync(path.dirname(j.out), { recursive: true });
    const p = await b.newPage({ viewport: { width: j.size, height: j.size } });
    const svg = fs.readFileSync(j.svg, 'utf8').replace(/width="\d+" height="\d+"/, `width="${j.size}" height="${j.size}"`);
    await p.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
    await p.screenshot({ path: j.out, omitBackground: !!j.transparent, clip: { x: 0, y: 0, width: j.size, height: j.size } });
    await p.close();
    console.log('png', path.relative(process.cwd(), j.out));
  }
  await b.close();
})();
