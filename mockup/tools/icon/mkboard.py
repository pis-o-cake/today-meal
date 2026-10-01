# 캔버스 보드: 앱 아이콘 (닫힌 냉장고 · 흰 배경 입체)
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mkicon import icon_svg

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', '..', 'canvas', 'AppIcon.dc.html'))
if '--out' in sys.argv: OUT = os.path.abspath(sys.argv[sys.argv.index('--out') + 1])
_n = [0]

def uid():
    _n[0] += 1
    return 'ai%d' % _n[0]

def ios(variant, px):
    return icon_svg(variant, size=px, uid=uid())

def android(px, part='both'):
    """적응형 아이콘: 108dp 캔버스 중 가운데 72dp만 보이게 잘라서 미리보기."""
    if part == 'fg':
        s = icon_svg('light', size=px, uid=uid(), bg=False, scale=3.0, cy=524)
    elif part == 'bg':
        s = icon_svg('light', size=px, uid=uid(), fg=False)
    else:
        s = icon_svg('light', size=px, uid=uid(), scale=3.0, cy=524)
    if part == 'both':
        s = s.replace('viewBox="0 0 1024 1024"', 'viewBox="170.67 170.67 682.67 682.67"', 1)
    return s

def tile(svg, px, radius, shadow='0 10px 26px rgba(20,25,35,0.18)'):
    return (f'<div style="width: {px}px; height: {px}px; border-radius: {radius}; overflow: hidden; '
            f'flex-shrink: 0; box-shadow: {shadow}">{svg}</div>')

def cap(text, color='#6B727B', size=12):
    return f'<span style="font-size: {size}px; font-weight: 600; color: {color}; white-space: nowrap">{text}</span>'

def col(inner, gap=6, extra=''):
    return f'<div style="display: flex; flex-direction: column; align-items: center; gap: {gap}px{extra}">{inner}</div>'

def card(label, badge, title, sub, body):
    return f'''
    <section aria-label="{label}" style="flex: 1 1 0; min-width: 0; display: flex; flex-direction: column; gap: 14px; padding: 20px; border-radius: 26px; background: #FFFFFF; box-shadow: 0 10px 28px rgba(20,25,35,0.07)">
      <div style="display: flex; align-items: center; gap: 8px">
        <span style="height: 24px; padding: 0 9px; border-radius: 12px; background: #EEF0FF; color: #3F4FD1; font-size: 12px; font-weight: 800; display: inline-flex; align-items: center">{badge}</span>
        <span style="font-size: 17px; font-weight: 800; letter-spacing: -0.03em">{title}</span>
      </div>
      <span style="font-size: 13px; line-height: 1.5; font-weight: 500; color: #5F6670">{sub}</span>
{body}
    </section>'''

def home_strip(variant, wall, label_color, icon_fn):
    return f'''      <div style="margin-top: auto; display: flex; align-items: flex-start; gap: 18px; padding: 16px 18px 12px; border-radius: 18px; background: {wall}">
        {col(tile(icon_fn(60), 60, '14px', '0 4px 10px rgba(20,25,35,0.22)') + f'<span style="font-size: 11px; font-weight: 600; color: {label_color}; white-space: nowrap; text-shadow: 0 1px 2px rgba(0,0,0,0.25)">오늘 뭐 먹지?</span>', 5, '; width: 64px')}
        {col(tile(icon_fn(40), 40, '9px', '0 3px 8px rgba(20,25,35,0.22)') + f'<span style="font-size: 10px; font-weight: 600; color: {label_color}; text-shadow: 0 1px 2px rgba(0,0,0,0.25)">작게</span>', 5, '; width: 44px; margin-top: 8px')}
        {col(tile(icon_fn(28), 28, '7px', '0 2px 6px rgba(20,25,35,0.22)') + f'<span style="font-size: 10px; font-weight: 600; color: {label_color}; text-shadow: 0 1px 2px rgba(0,0,0,0.25)">설정</span>', 5, '; width: 36px; margin-top: 14px')}
      </div>'''

LIGHT_WALL = 'linear-gradient(135deg, #8E9BF2 0%, #C4A6EC 55%, #F5BFCF 100%)'
DARK_WALL = 'linear-gradient(135deg, #14161F 0%, #262A3F 60%, #3A2F48 100%)'

# 1. 기본 아이콘
c1 = card('기본 아이콘', '기본', '흰 배경 · 입체 냉장고',
          '옆면 두께·윗면 빛·바닥 그림자로 도톰하게 보여요.',
          f'''      <div style="display: flex; align-items: flex-end; gap: 20px">
        {col(tile(ios('light', 168), 168, '38px') + cap('iOS'))}
        {col(tile(android(104), 104, '50%', '0 6px 16px rgba(20,25,35,0.16)') + cap('Android'))}
      </div>
''' + home_strip('light', LIGHT_WALL, '#FFFFFF', lambda px: ios('light', px)))

# 2. 다크 모드
c2 = card('다크 모드 아이콘', '다크', 'iOS 다크 모드',
          'iOS 18 이상 다크 모드에서 자동으로 바뀌어요.',
          f'''      <div style="display: flex; align-items: flex-end; gap: 20px">
        {col(tile(ios('dark', 168), 168, '38px', '0 10px 26px rgba(20,25,35,0.28)') + cap('iOS 다크'))}
      </div>
''' + home_strip('dark', DARK_WALL, '#E8EAED', lambda px: ios('dark', px)))

# 3. Android 적응형
CHECK = 'repeating-conic-gradient(#E4E7EF 0% 25%, #FFFFFF 0% 50%) 0 0 / 12px 12px'
safe = ('<div aria-hidden="true" style="position: absolute; left: 50%; top: 50%; width: 61%; height: 61%; '
        'transform: translate(-50%, -50%); border-radius: 50%; border: 1.5px dashed #F0535E"></div>')
layers = f'''      <div style="display: flex; align-items: flex-start; gap: 10px; margin-top: auto; padding: 14px; border-radius: 18px; background: #F6F7FA">
        {col(tile(android(84, 'bg'), 84, '12px', 'none') + cap('뒤 레이어', size=11), 5)}
        <span style="align-self: center; margin-top: -18px; font-size: 18px; font-weight: 700; color: #9AA0A6">+</span>
        {col(f'<div style="position: relative; width: 84px; height: 84px; border-radius: 12px; overflow: hidden; background: {CHECK}">{android(84, "fg")}{safe}</div>' + cap('앞 레이어', size=11), 5)}
        <span style="align-self: center; margin-top: -18px; font-size: 18px; font-weight: 700; color: #9AA0A6">=</span>
        {col(tile(android(84), 84, '50%', '0 4px 12px rgba(20,25,35,0.14)') + cap('합성', size=11), 5)}
      </div>'''
c3 = card('Android 적응형 아이콘', 'Android', '기기마다 다른 모양',
          '어떤 모양으로 잘려도 안전 영역(점선) 안에 들어가요.',
          f'''      <div style="display: flex; align-items: flex-end; justify-content: space-between">
        {col(tile(android(92), 92, '50%', '0 6px 16px rgba(20,25,35,0.14)') + cap('원형'))}
        {col(tile(android(92), 92, '22px', '0 6px 16px rgba(20,25,35,0.14)') + cap('둥근 사각'))}
        {col(tile(android(92), 92, '38%', '0 6px 16px rgba(20,25,35,0.14)') + cap('스퀘어클'))}
      </div>
''' + layers)

HELMET = ("@font-face{font-family:'Pretendard';src:url(/_blob/1b43482c59fb171bdbae3b012829170f) format('woff2');font-weight:45 920;font-style:normal;font-display:swap}"
          "@font-face{font-family:'Jua';src:url(/_blob/b80c3f239a19ae2ac0629973c9271ec7) format('woff2');font-weight:400;font-style:normal;font-display:swap}body{margin:0}")

html = f'''<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>앱 아이콘</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>{HELMET}</style>
</helmet>
<div style="width: 1380px; height: 540px; box-sizing: border-box; padding: 28px; display: flex; flex-direction: column; gap: 20px; font-family: 'Pretendard', 'Apple SD Gothic Neo', sans-serif; color: #15181D; letter-spacing: -0.02em; background: #F1F2F6">
  <div style="display: flex; align-items: baseline; gap: 12px">
    <span style="font-family: 'Jua', 'Pretendard', sans-serif; font-size: 30px; font-weight: 400">앱 아이콘</span>
    <span style="font-size: 15px; font-weight: 500; color: #5F6670">문 닫힌 냉장고 캐릭터 · 흰 배경에 입체감 · 파일은 docs/assets/app-icon</span>
  </div>
  <div style="flex-grow: 1; display: flex; gap: 20px">
{c1}
{c2}
{c3}
  </div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1380,"height":540}}}}'>
class Component extends DCLogic {{
  renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
'''
open(OUT, 'w', encoding='utf-8').write(html)
print('ok', len(html), _n[0])
