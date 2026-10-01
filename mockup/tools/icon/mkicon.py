# 앱 아이콘: 문 닫힌 냉장고 캐릭터 + 흰 배경, 입체감
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
# 원본 SVG는 저장소 docs/assets/app-icon/svg 에 쓴다. --out 으로 바꿀 수 있다.
OUT = os.path.normpath(os.path.join(HERE, '..', '..', '..', 'docs', 'assets', 'app-icon', 'svg'))
if '--out' in sys.argv: OUT = os.path.abspath(sys.argv[sys.argv.index('--out') + 1])
INK = '#333A52'

def fridge(u):
    """문 닫힌 냉장고 (200 좌표계). 오른쪽·아래로 두께가 보이고 면마다 빛이 다르게 든다."""
    return f'''
    <ellipse cx="108" cy="191" rx="62" ry="9" fill="url(#{u}-shadow)" filter="url(#{u}-blur)"></ellipse>
    <rect x="72" y="176" width="15" height="13" rx="4.5" fill="{INK}"></rect>
    <rect x="124" y="176" width="15" height="13" rx="4.5" fill="{INK}"></rect>
    <rect x="55" y="29" width="108" height="156" rx="32" fill="url(#{u}-side)" stroke="{INK}" stroke-width="5"></rect>
    <rect x="46" y="24" width="108" height="156" rx="32" fill="url(#{u}-body)" stroke="{INK}" stroke-width="5"></rect>
    <path d="M48.5 76.5 H151.5 V86 H48.5 Z" fill="{INK}" opacity="0.07"></path>
    <path d="M70 30.5 H122 A25.5 25.5 0 0 1 147.5 56" fill="none" stroke="#FFFFFF" stroke-opacity="0.8" stroke-width="3" stroke-linecap="round"></path>
    <ellipse cx="76" cy="52" rx="22" ry="16" fill="#FFFFFF" opacity="0.35"></ellipse>
    <path d="M46 74 H154" fill="none" stroke="{INK}" stroke-width="5"></path>
    <path d="M56 38 Q52 46 52 62" fill="none" stroke="#FFFFFF" stroke-opacity="0.9" stroke-width="5" stroke-linecap="round"></path>
    <path d="M53 92 v16" fill="none" stroke="#FFFFFF" stroke-opacity="0.75" stroke-width="5" stroke-linecap="round"></path>
    <rect x="134.5" y="38" width="8" height="22" rx="4" fill="{INK}"></rect>
    <rect x="134.5" y="88" width="8" height="28" rx="4" fill="{INK}"></rect>
    <path d="M137 41 v8 M137 91 v10" stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="2" stroke-linecap="round"></path>
    <g transform="rotate(-8 80 48)">
      <rect x="66" y="37" width="28" height="24" rx="4" fill="{INK}" opacity="0.15" transform="translate(2 3)"></rect>
      <rect x="66" y="36" width="28" height="24" rx="4" fill="#FFF3B8" stroke="{INK}" stroke-width="3"></rect>
      <circle cx="80" cy="36" r="4" fill="#5A6BEA" stroke="{INK}" stroke-width="2"></circle>
      <path d="M71 46 h16 M71 52 h10" fill="none" stroke="{INK}" stroke-width="2.4" stroke-linecap="round"></path>
    </g>
    <circle cx="72" cy="136" r="7.5" fill="#FF8A98" opacity="0.55"></circle>
    <circle cx="124" cy="136" r="7.5" fill="#FF8A98" opacity="0.55"></circle>
    <path d="M77 122 q7 -9 14 0 M105 122 q7 -9 14 0" fill="none" stroke="{INK}" stroke-width="5" stroke-linecap="round"></path>
    <path d="M89 134 q9 12 18 0 z" fill="{INK}" stroke="{INK}" stroke-width="3" stroke-linejoin="round"></path>
'''

def defs(u, dark=False):
    body = ('<linearGradient id="{u}-body" x1="0" y1="0" x2="0.75" y2="1"><stop offset="0" stop-color="#EEF0FF"></stop>'
            '<stop offset="0.55" stop-color="#C9D0FF"></stop><stop offset="1" stop-color="#AAB5F7"></stop></linearGradient>'
            '<linearGradient id="{u}-side" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8F9BEA"></stop><stop offset="1" stop-color="#6F7DDB"></stop></linearGradient>'
            '<radialGradient id="{u}-shadow"><stop offset="0" stop-color="#333A52" stop-opacity="%s"></stop><stop offset="1" stop-color="#333A52" stop-opacity="0"></stop></radialGradient>'
            '<filter id="{u}-blur" x="-20%%" y="-100%%" width="140%%" height="300%%"><feGaussianBlur stdDeviation="3"></feGaussianBlur></filter>') % ('0.55' if dark else '0.32')
    if dark:
        bg = ('<radialGradient id="{u}-bg" cx="0.5" cy="0.36" r="0.85"><stop offset="0" stop-color="#3A3F5C"></stop>'
              '<stop offset="0.6" stop-color="#23263A"></stop><stop offset="1" stop-color="#171925"></stop></radialGradient>')
    else:
        bg = ('<radialGradient id="{u}-bg" cx="0.5" cy="0.34" r="0.9"><stop offset="0" stop-color="#FFFFFF"></stop>'
              '<stop offset="0.55" stop-color="#F5F6FB"></stop><stop offset="1" stop-color="#E3E6F1"></stop></radialGradient>')
    return (body + bg).replace('{u}', u)

def star(x, y, r, fill):
    k = r * 0.29
    return f'<path d="M{x:.1f} {y-r:.1f} L{x+k:.1f} {y-k:.1f} L{x+r:.1f} {y:.1f} L{x+k:.1f} {y+k:.1f} L{x:.1f} {y+r:.1f} L{x-k:.1f} {y+k:.1f} L{x-r:.1f} {y:.1f} L{x-k:.1f} {y-k:.1f} Z" fill="{fill}"></path>'

def icon_svg(variant='light', size=1024, uid=None, bg=True, fg=True, scale=4.05, cy=528):
    dark = variant == 'dark'
    u = uid or ('ic' + variant)
    s = scale
    tx = 512 - 104 * s
    ty = cy - 106 * s
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="{size}" height="{size}">', '<defs>' + defs(u, dark) + '</defs>']
    if bg:
        out.append(f'<rect width="1024" height="1024" fill="url(#{u}-bg)"></rect>')
    if fg:
        k = s / 4.05
        c1, c2 = ('#FFF3B8', '#C7CFFF') if dark else ('#A99BFF', '#8FA2FF')
        out.append(star(512 - 262 * k, cy - 318 * k, 34 * k, c1))
        out.append(star(512 + 276 * k, cy - 250 * k, 24 * k, c2))
        out.append(f'<g transform="translate({tx:.1f} {ty:.1f}) scale({s})">' + fridge(u) + '</g>')
    out.append('</svg>')
    return ''.join(out)

if __name__ == '__main__':
    files = {
        'app-icon.svg': icon_svg('light'),
        'app-icon-dark.svg': icon_svg('dark'),
        'android-foreground.svg': icon_svg('light', bg=False, scale=3.0, cy=524),
        'android-background.svg': icon_svg('light', fg=False),
    }
    os.makedirs(OUT, exist_ok=True)
    for n, c in files.items():
        open(os.path.join(OUT, n), 'w', encoding='utf-8').write(c)
    print('ok', list(files))
