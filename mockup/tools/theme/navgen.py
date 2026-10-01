# 모든 화면이 같은 하단 탭 바를 쓰도록 만드는 도우미
TABS = [
    ('home', '뭐 먹지?', '<path d="M5 6.5a3 4 0 1 0 6 0a3 4 0 1 0 -6 0M8 10.5V21M15 3l.5 18M19 3l-1 18"></path>'),
    ('fridge', '냉장고', '<rect x="5" y="2.5" width="14" height="19" rx="3"></rect><path d="M5 10h14M8.5 6v1.5M8.5 13v3"></path>'),
    ('cook', '조리', '<path d="M5 11h14v6a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3z M3.5 11h17 M10 8.5h4 M3 13.5h2 M19 13.5h2 M9.5 6c0-1.2 1-1.3 1-2.5 M13.5 6c0-1.2 1-1.3 1-2.5"></path>'),
    ('history', '기록', '<circle cx="12" cy="12" r="9"></circle><path d="M12 7v5l3 2"></path>'),
    ('my', '마이페이지', '<circle cx="12" cy="8" r="4"></circle><path d="M4.5 20.5a7.5 7.5 0 0 1 15 0"></path>'),
]
BASE = 'position: absolute; left: 0; right: 0; bottom: 0; height: {{navH}}px; box-sizing: border-box; padding: 0 12px {{bottom}}px; display: flex;'
SOLID = (' border-radius: 28px 28px 0 0; background: rgba(255,255,255,0.72); border-top: 1px solid rgba(255,255,255,0.95);'
         ' box-shadow: 0 -12px 32px rgba(20,25,35,0.07); backdrop-filter: blur(18px); -webkit-backdrop-filter: blur(18px);')
ITEM = 'flex-grow: 1; flex-basis: 0; min-width: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px; text-decoration: none; font-size: 12px; white-space: nowrap;'

def nav_html(active, transparent=False, indent='  '):
    style = BASE + ('' if transparent else SOLID) + ' {{g_nav}}'
    out = [indent + '<nav aria-label="주요 화면" style="%s">' % style]
    for key, label, icon in TABS:
        on = key == active
        st = ITEM + (' color: #15181D; font-weight: 700; {{g_tab}}' if on else ' color: #7C838C; font-weight: 500')
        cur = ' aria-current="page"' if on else ''
        out.append(indent + '  <a href="{{links.%s}}"%s style="%s">' % (key, cur, st))
        out.append(indent + '    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">%s</svg>' % ('2' if on else '1.8', icon))
        out.append(indent + '    ' + label)
        out.append(indent + '  </a>')
    out.append(indent + '</nav>')
    return '\n'.join(out)

GLASS_JS = r"""    // 글래스 테마 전용: 떠 있는 유리 탭 바 (색은 hsl로 적어 테마 변환에서 제외)
    var GLASS_ON = THEME === 'glass';
    var gNav = function (bottomPx) {
      return 'left: 14px; right: 14px; bottom: ' + bottomPx + 'px; height: 62px; padding: 0 6px; border-radius: 31px; border: 1px solid hsla(0,0%,100%,0.75);'
        + ' background: linear-gradient(135deg, hsla(0,0%,100%,0.42) 0%, hsla(0,0%,100%,0.1) 50%, hsla(0,0%,100%,0.26) 100%);'
        + ' backdrop-filter: blur(14px) saturate(190%); -webkit-backdrop-filter: blur(14px) saturate(190%);'
        + ' box-shadow: inset 1px 1px 0 hsla(0,0%,100%,0.95), inset -1px -1px 0 hsla(0,0%,100%,0.45), inset 0 -12px 20px hsla(0,0%,100%,0.2), 0 0 0 0.5px hsla(230,20%,20%,0.15), 0 12px 30px hsla(230,30%,20%,0.13)';
    };
    var gTab = 'margin: 7px 0; border-radius: 24px; background: linear-gradient(135deg, hsla(0,0%,100%,0.72) 0%, hsla(0,0%,100%,0.22) 55%, hsla(0,0%,100%,0.4) 100%);'
      + ' box-shadow: inset 1px 1px 0 hsla(0,0%,100%,1), inset -1px -1px 0 hsla(0,0%,100%,0.5), 0 0 0 0.5px hsla(230,20%,20%,0.12), 0 4px 12px hsla(230,30%,20%,0.10)';
"""
GLASS_RET = "g_nav: GLASS_ON ? gNav(Math.max(g.bottom - 12, 12)) : '', g_tab: GLASS_ON ? gTab : '', navH: 64 + g.bottom,"

def links_js(android_expr='android'):
    return ("home: L('Main'), fridge: L('Fridge'), cook: L('CookHome'), history: L('History'), my: L('MyPage')")
