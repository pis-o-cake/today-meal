# 파스텔 원본(theme-src) → 테마 4종(pastel/white/glass/dark)을 고를 수 있는 화면(project)으로 변환
import re, json, colorsys, sys, os

# 경로는 이 파일 기준. 출력 폴더는 --out 으로 바꿀 수 있다(검증용).
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'src') + os.sep
OUT = os.path.normpath(os.path.join(HERE, '..', '..', 'canvas')) + os.sep
if '--out' in sys.argv:
    OUT = os.path.abspath(sys.argv[sys.argv.index('--out') + 1]) + os.sep
    os.makedirs(OUT, exist_ok=True)
THEMES = ['pastel', 'white', 'glass', 'dark']
SCREENS = ['Splash', 'Login', 'SignUp', 'Permission', 'Main', 'Listening', 'Clarify', 'Result',
           'Fridge', 'FridgeItem', 'Menu', 'CookHome', 'Cooking', 'CookDone', 'History', 'MyPage']
COL = re.compile(r"#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{3}\b|rgba?\([^)]*\)")
BLUR = 'backdrop-filter: blur(24px) saturate(180%); -webkit-backdrop-filter: blur(24px) saturate(180%)'
GLASS = {
    'fx': BLUR + '; box-shadow: inset 0 1px 0 rgba(255,255,255,0.95), inset 0 -1px 0 rgba(20,25,45,0.04), 0 0 0 0.5px rgba(20,25,45,0.07), 0 8px 24px rgba(20,25,45,0.08)',
    'fxd': BLUR + '; box-shadow: inset 0 1px 0 rgba(255,255,255,0.24), inset 0 -1px 0 rgba(0,0,0,0.25), 0 10px 24px rgba(15,17,22,0.22)',
    'fxa': 'box-shadow: inset 0 1px 0 rgba(255,255,255,0.4), inset 0 -1px 0 rgba(0,0,0,0.12), 0 10px 22px rgba(20,25,45,0.16)',
    'fxc': 'backdrop-filter: blur(12px) saturate(180%); -webkit-backdrop-filter: blur(12px) saturate(180%); box-shadow: inset 1px 1px 0 rgba(255,255,255,0.95), inset -1px -1px 0 rgba(255,255,255,0.45), inset 0 -10px 18px rgba(255,255,255,0.22), inset 0 8px 14px rgba(255,255,255,0.14), 0 0 0 0.5px rgba(20,25,45,0.13), 0 8px 22px rgba(20,25,45,0.10), 0 1px 3px rgba(20,25,45,0.06)',
}

# ---------- 색 계산 ----------
def parse(lit):
    lit = lit.strip()
    if lit.startswith('#'):
        h = lit[1:]
        if len(h) == 3: h = ''.join(c * 2 for c in h)
        return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 1.0
    nums = [x.strip() for x in lit[lit.index('(') + 1:-1].split(',')]
    r, g, b = [int(float(x)) for x in nums[:3]]
    a = float(nums[3]) if len(nums) > 3 else 1.0
    return r, g, b, a

def norm(lit):
    r, g, b, a = parse(lit)
    return fmt(r, g, b, a)

def fmt(r, g, b, a=1.0):
    r, g, b = [max(0, min(255, int(round(v)))) for v in (r, g, b)]
    if a >= 0.999: return '#%02X%02X%02X' % (r, g, b)
    return 'rgba(%d,%d,%d,%s)' % (r, g, b, ('%.2f' % a).rstrip('0').rstrip('.'))

def hsl(r, g, b):
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    return h * 360, s, l

def fromhsl(h, s, l, a=1.0):
    r, g, b = colorsys.hls_to_rgb((h % 360) / 360, max(0, min(1, l)), max(0, min(1, s)))
    return fmt(r * 255, g * 255, b * 255, a)

def css_hsl(h, s, l, a=1.0):
    return fromhsl(h, s, l, a)

def cat(lit):
    r, g, b, a = parse(lit)
    h, s, l = hsl(r, g, b)
    if min(r, g, b) >= 248: return 'white', h, s, l, a
    if s < 0.15 or (max(r, g, b) - min(r, g, b)) < 18 or (l < 0.32 and s < 0.35): return 'neutral', h, s, l, a
    if l >= 0.8: return 'tint', h, s, l, a
    return 'accent', h, s, l, a

clamp = lambda v, lo, hi: max(lo, min(hi, v))

def vivid(h, s, l, a=1.0):  # 선명한 채움
    return fromhsl(h, max(s, 0.85), clamp(l, 0.45, 0.55), a)

def gray_dark(l):  # 다크 테마 회색 글자
    return fromhsl(220, 0.08, clamp(1.12 - l, 0.5, 0.82))

GL_SURF = 'linear-gradient(180deg, rgba(255,255,255,0.94) 0%, rgba(255,255,255,0.66) 100%)'
GL_DARK = 'linear-gradient(180deg, rgba(58,62,72,0.92) 0%, rgba(18,20,26,0.94) 100%)'
DK_BG, DK_SURF, DK_ELEV, DK_TXT = '#262624', '#30302E', '#3A3A37', '#F5F4EE'
G_BG, G_SURF, G_ELEV, G_T1, G_T2, G_T3, G_T4 = '#202124', '#2D2E31', '#3C4043', '#E8EAED', '#BDC1C6', '#9AA0A6', '#80868B'
G_TONES = [(15, '#F28B82'), (40, '#FCAD70'), (65, '#FDD663'), (165, '#81C995'), (195, '#78D9EC'), (255, '#8AB4F8'), (300, '#C58AF9'), (340, '#FF8BCB'), (361, '#F28B82')]
def gtone(h, s):
    if s < 0.15: return G_T3
    for lim, col in G_TONES:
        if h < lim: return col
    return G_T3
def warm_gray(l):
    return fromhsl(48, 0.06, clamp(1.1 - l, 0.55, 0.8))

CLEAR_FILL = 'linear-gradient(135deg, rgba(255,255,255,0.52) 0%, rgba(255,255,255,0.14) 48%, rgba(255,255,255,0.3) 100%)'
def tx(theme, kind, lit):
    if theme == 'pastel' or kind == 'svgstop': return norm(lit)
    if kind == 'btnbg':
        if theme == 'glass' and cat(lit)[0] == 'white': return CLEAR_FILL
        kind = 'bg'
    if kind == 'btnborder':
        if theme == 'glass' and cat(lit)[0] == 'white': return 'rgba(255,255,255,0.7)'
        kind = 'border'
    c, h, s, l, a = cat(lit)
    r, g, b, _ = parse(lit)
    if theme == 'white':
        if kind == 'bg':
            if c == 'white': return '#FFFFFF' if a >= 0.5 else fmt(255, 255, 255, a)
            if c == 'tint': return fromhsl(h, min(1, s * 0.9 + 0.15), max(l - 0.02, 0.88), a)
            if c == 'accent': return vivid(h, s, l, a)
            return norm(lit)
        if kind == 'text':
            if c == 'accent': return fromhsl(h, max(s, 0.85), min(l, 0.42), a)
            return norm(lit)
        if kind == 'border':
            if c == 'white' and a >= 0.5: return 'rgba(17,20,26,0.07)'
            if c == 'accent': return vivid(h, s, l, a)
            if c == 'tint': return fromhsl(h, min(1, s * 0.9 + 0.15), max(l - 0.02, 0.88), a)
            return norm(lit)
        if kind == 'shadow':
            if c == 'accent': return vivid(h, s, l, a)
            return norm(lit)
        if kind in ('svgfill', 'svgstroke'):
            if c == 'accent':
                if l > 0.62: return fromhsl(h, min(s, 0.8), l - 0.03, a)
                return fromhsl(h, clamp(s, 0.65, 0.85), clamp(l, 0.45, 0.55), a)
            if c == 'tint': return fromhsl(h, min(s, 0.8), l - 0.04, a)
            return norm(lit)
        if kind == 'mbody':
            return norm(lit) if c in ('neutral', 'white') else fromhsl(h, clamp(s, 0.5, 0.72), clamp(l - 0.05, 0.72, 0.82))
        if kind == 'mdeep':
            return norm(lit) if c == 'neutral' else fromhsl(h, clamp(s, 0.55, 0.75), min(l, 0.5))
    if theme == 'glass':
        # 배경은 깨끗하게, 표면·버튼만 유리처럼
        flat = kind == 'bgstop'
        if kind in ('bg', 'bgstop'):
            if c == 'white':
                return fmt(255, 255, 255, a) if flat else GL_SURF
            if c == 'neutral':
                if a < 0.999 and l < 0.3: return norm(lit)
                if l >= 0.93: return 'rgba(120,128,150,0.10)'
                if l >= 0.7: return fmt(120, 128, 150, round(clamp((1 - l) * 1.5, 0.12, 0.3), 2))
                if l < 0.25: return fmt(20, 22, 28, 0.9) if flat else GL_DARK
                return norm(lit)
            if c == 'tint': return fromhsl(h, max(s, 0.7), 0.55, 0.13)
            if a < 0.999 or flat: return fromhsl(h, max(s, 0.75), clamp(l, 0.45, 0.55), a)
            return 'linear-gradient(180deg, %s 0%%, %s 100%%)' % (
                fromhsl(h, max(s, 0.75), clamp(l, 0.45, 0.55) + 0.1, 0.94), fromhsl(h, max(s, 0.75), clamp(l, 0.45, 0.55), 0.94))
        if kind == 'text':
            if c == 'accent': return fromhsl(h, max(s, 0.75), min(l, 0.45), a)
            return norm(lit)
        if kind == 'border':
            if c == 'white': return 'rgba(255,255,255,0.92)'
            if c == 'neutral':
                if l < 0.25 and a >= 0.999: return 'rgba(255,255,255,0.16)'
                return norm(lit)
            if c == 'tint': return fromhsl(h, max(s, 0.7), 0.55, 0.25)
            return fromhsl(h, max(s, 0.75), clamp(l, 0.45, 0.55), a)
        if kind == 'shadow':
            if c == 'accent': return fromhsl(h, max(s, 0.75), 0.5, a)
            return fmt(20, 25, 45, min(0.2, a))
        if kind in ('svgfill', 'svgstroke'):
            if c == 'accent': return fromhsl(h, max(s, 0.8), 0.5, a)
            return norm(lit)
        if kind == 'mbody':
            return norm(lit) if c in ('neutral', 'white') else fromhsl(h, clamp(s, 0.5, 0.7), 0.78)
        if kind == 'mdeep':
            return norm(lit) if c == 'neutral' else fromhsl(h, 0.55, 0.42)
    if theme == 'dark':
        # Google Nest Hub 다크처럼: #202124 바탕, #2D2E31 카드, Google 200 톤 강조색
        tone = gtone(h, s)
        tr, tg, tb, _ = parse(tone)
        if kind in ('bg', 'bgstop'):
            if c == 'white': return G_ELEV if a >= 0.999 else fmt(45, 46, 49, max(a, 0.96))
            if c == 'neutral':
                if a < 0.999 and l < 0.3: return fmt(232, 234, 237, round(min(0.12, a * 1.5), 2))
                if l >= 0.93: return G_ELEV
                if l >= 0.72: return '#5F6368'
                if l < 0.25: return G_T1
                return G_T4
            if c == 'tint': return fmt(tr, tg, tb, 0.16)
            return tone if a >= 0.999 else fmt(tr, tg, tb, round(min(0.9, a * 1.2), 2))
        if kind == 'text':
            if c == 'white': return G_BG if a >= 0.999 else fmt(32, 33, 36, a)
            if c == 'neutral':
                if a < 0.999: return fmt(232, 234, 237, a)
                if l < 0.2: return G_T1
                if l < 0.45: return G_T2
                if l < 0.6: return G_T3
                return G_T4
            return tone if a >= 0.999 else fmt(tr, tg, tb, a)
        if kind == 'border':
            if c == 'white': return 'rgba(232,234,237,0.08)' if a < 0.999 else G_SURF
            if c == 'neutral':
                if a < 0.999 and l < 0.3: return fmt(232, 234, 237, round(min(0.14, a * 1.6), 2))
                if l < 0.25: return G_T1
                return '#5F6368'
            if c == 'tint': return fmt(tr, tg, tb, 0.28)
            return tone if a >= 0.999 else fmt(tr, tg, tb, round(min(0.9, a * 1.3), 2))
        if kind == 'shadow':
            if c == 'accent': return fmt(tr, tg, tb, round(a * 0.6, 2))
            return fmt(0, 0, 0, round(min(0.3, a * 1.8), 2))
        if kind in ('svgfill', 'svgstroke'):
            if c in ('white', 'tint'): return norm(lit)
            if c == 'neutral':
                if l < 0.32: return norm(lit)
                return G_T3
            return tone
        if kind in ('mbody', 'mdeep'): return norm(lit)
    return norm(lit)

# ---------- 배경 ----------
def root_hue(value):
    best = None
    for lit in COL.findall(value):
        c, h, s, l, a = cat(lit)
        if c in ('tint', 'accent') and (best is None or s > best[1]): best = (h, s)
    return best[0] if best else None

def root_for(theme, value, hue=None, from_value=True):
    h = root_hue(value) if from_value else hue
    if theme == 'pastel': return value
    if theme == 'white':
        if h is None: return '#F4F5F7'
        return 'radial-gradient(120%% 45%% at 50%% 0%%, %s 0%%, rgba(255,255,255,0) 70%%), #F6F7F9' % fromhsl(h, 0.9, 0.6, 0.08)
    if theme == 'glass':
        return 'linear-gradient(180deg, #FFFFFF 0%, #EEF0F4 100%)'
    if theme == 'dark':
        return G_BG

# ---------- 파일별 예외 ----------
OVERRIDES = {
    'Login': {
        ('bg', '#FFFFFF'): {'white': '#FFFFFF', 'glass': '#FFFFFF', 'dark': '#131314'},   # Google 버튼
        ('border', '#747775'): {'dark': '#8E918F'},
        ('text', '#1F1F1F'): {'dark': '#E3E3E3'},
        ('bg', '#000000'): {'white': '#000000', 'glass': '#000000', 'dark': '#FFFFFF'},   # Apple: 다크 배경엔 흰 버튼
        ('bg', '#FEE500'): {'white': '#FEE500', 'glass': '#FEE500', 'dark': '#FEE500'},
        ('text', 'rgba(0,0,0,0.85)'): {'white': 'rgba(0,0,0,0.85)', 'glass': 'rgba(0,0,0,0.85)', 'dark': 'rgba(0,0,0,0.85)'},
    },
    'Menu': {('bgstop', 'rgba(248,227,217,0)'): {'white': 'rgba(246,247,249,0)', 'glass': 'rgba(238,240,244,0)', 'dark': 'rgba(32,33,36,0)'},
             ('bgstop', 'rgba(248,227,217,0.96)'): {'white': 'rgba(246,247,249,0.97)', 'glass': 'rgba(238,240,244,0.95)', 'dark': 'rgba(32,33,36,0.96)'}},
    'Splash': {('svgstop', '#FFFFFF'): {'dark': '#202124'},
               ('svgfill', '#C7CFFF'): {'glass': 'url(#sp-glass-b)'},
               ('svgstroke', '#333A52'): {'glass': 'rgba(64,76,150,0.85)'},
               ('svgfill', '#333A52'): {'glass': 'rgba(64,76,150,0.85)'}},
    'Listening': {('svgfill', '#FFFFFF'): {'dark': 'rgba(232,234,237,0.05)'}},
    'MyPage': {('bg', '#FFFFFF'): {'white': '#FFFFFF', 'glass': '#FFFFFF', 'dark': '#FFFFFF'}},   # 토글 손잡이
    'SignUp': {('bg', '#CDD2F2'): {'dark': '#3C4043', 'glass': 'rgba(120,128,150,0.16)'},
               ('text', 'rgba(255,255,255,0.95)'): {'dark': 'rgba(232,234,237,0.38)', 'glass': 'rgba(21,24,29,0.32)'}},
}

PROP_KIND = {'background': 'bg', 'background-color': 'bg', 'color': 'text', 'caret-color': 'text',
             'box-shadow': 'shadow', 'text-shadow': 'shadow', 'fill': 'svgfill', 'stroke': 'svgstroke'}
def prop_kind(p):
    p = p.strip().lower()
    if p in PROP_KIND: return PROP_KIND[p]
    if p.startswith('border') or p.startswith('outline'): return 'border'
    return 'text'

KEY_KIND = {'acc': 'text', 'accSoft': 'bg', 'bg1': 'mainstop1', 'bg2': 'mainstop2', 'bg': 'bg', 'fg': 'text',
            'bar': 'bg', 'color': 'text', 'labelColor': 'text', 'subColor': 'text', 'body': 'mbody', 'deep': 'mdeep', 'check': 'svgstroke', 'allCheck': 'svgstroke'}

def mainstop(theme, n, lit):
    if theme == 'pastel': return norm(lit)
    c, h, s, l, a = cat(lit)
    neutral = c in ('neutral', 'white')
    if theme == 'white': return '#FFFFFF' if n == 1 else '#EEF0F3'
    if theme == 'glass': return '#FFFFFF' if n == 1 else '#EEF0F4'
    if theme == 'dark': return G_BG

class Reg:
    def __init__(self, name):
        self.name, self.items, self.idx = name, [], {}
    def key(self, kind, lit):
        k = (kind, norm(lit))
        if k not in self.idx:
            self.idx[k] = 'c%d' % len(self.items)
            self.items.append(k)
        return self.idx[k]
    def table(self, theme):
        ov = OVERRIDES.get(self.name, {})
        out = {}
        for (kind, lit) in self.items:
            k = self.idx[(kind, lit)]
            if (kind, lit) in ov and theme in ov[(kind, lit)]:
                out[k] = ov[(kind, lit)][theme]
            elif kind == 'mainstop1': out[k] = mainstop(theme, 1, lit)
            elif kind == 'mainstop2': out[k] = mainstop(theme, 2, lit)
            else: out[k] = tx(theme, kind, lit)
        return out

BRAND = ('#FEE500', '#000000', '#747775')
def buttonish(style):
    m = re.search(r'(?:^|;)\s*(?:min-)?height:\s*(\d+)px', style)
    if m and int(m.group(1)) >= 36: return True
    m = re.search(r'(?:^|;)\s*padding:\s*([^;]*)', style)
    nums = [int(x) for x in re.findall(r'(\d+)px', m.group(1))] if m else []
    return bool(nums and max(nums) >= 8 and 'border-radius' in style)

def pill_control(style):
    m = re.search(r'(?:^|;)\s*height:\s*(\d+)px', style)
    return bool(m and 36 <= int(m.group(1)) <= 64 and re.search(r'border-radius:\s*(999px|50%|[2-9]\d px)'.replace(' ', ''), style))

def style_sub(style, reg, is_root, extra, btn=False):
    decls = style.split(';')
    fx = None
    for i, d in enumerate(decls):
        if ':' not in d or not COL.search(d): continue
        p, v = d.split(':', 1)
        kind = prop_kind(p)
        if is_root and kind == 'bg' and p.strip() == 'background':
            extra['root'] = v.strip()
            decls[i] = p + ': {{K.root}}'
            continue
        if kind == 'bg':
            if 'gradient(' in v:
                kind = 'bgstop'
            else:
                for lit in COL.findall(v):
                    c, h, sat, l, a = cat(lit)
                    if c == 'white': fx = fx or ('fxc' if btn and buttonish(style) else 'fx')
                    elif c == 'neutral' and l < 0.25 and a >= 0.999 and buttonish(style): fx = fx or 'fxd'
                    elif c == 'accent' and a >= 0.999 and buttonish(style): fx = fx or 'fxa'
        k2 = kind
        if btn and buttonish(style) and kind in ('bg', 'border'):
            k2 = 'btnbg' if kind == 'bg' else 'btnborder'
        decls[i] = p + ':' + COL.sub(lambda m, k2=k2: '{{K.%s}}' % reg.key(k2, m.group(0)), v)
    out = ';'.join(decls)
    if fx and not is_root and '{{g_' not in style and not any(b.lower() in style.lower() for b in BRAND):
        out = out.rstrip().rstrip(';') + '; {{K.%s}}' % fx
    return out

def js_sub(js, reg, name):
    lines = js.split('\n')
    for li, line in enumerate(lines):
        if not COL.search(line): continue
        # History: ['#bg', '#fg']
        line = re.sub(r"\[\s*'(#[0-9A-Fa-f]{6})'\s*,\s*'(#[0-9A-Fa-f]{6})'\s*\]",
                      lambda m: '[K.%s, K.%s]' % (reg.key('bg', m.group(1)), reg.key('text', m.group(2))), line)
        out, pos = [], 0
        for m in re.finditer(r"'((?:[^'\\]|\\.)*)'", line):
            sval = m.group(1)
            out.append(line[pos:m.start()])
            pos = m.end()
            if not COL.search(sval):
                out.append(m.group(0)); continue
            before = ''.join(out)
            if COL.fullmatch(sval.strip()):
                km = re.search(r"(\w+)\s*:\s*(?:[^,{'?]*\?\s*(?:K\.\w+\s*:\s*)?)?$", before)
                cm = re.findall(r"\b(background|color|border[a-z-]*|box-shadow|outline[a-z-]*|fill|stroke)\s*:\s", before)
                if km and km.group(1) in KEY_KIND: kind = KEY_KIND[km.group(1)]
                elif cm: kind = prop_kind(cm[-1])
                elif 'mk(' in before: kind = 'text'
                else:
                    print('  [warn]', name, 'unknown kind:', line.strip()[:120]); kind = 'text'
                out.append('K.' + reg.key(kind, sval.strip()))
                continue
            if ':' in sval:   # CSS 선언 문자열 안의 색
                parts = sval.split(';')
                for i, d in enumerate(parts):
                    if ':' in d and COL.search(d):
                        p, v = d.split(':', 1)
                        kind = prop_kind(p)
                        parts[i] = p + ':' + COL.sub(lambda mm: "' + K.%s + '" % reg.key(kind, mm.group(0)), v)
                out.append("'" + ';'.join(parts) + "'")
            else:              # 값만 있는 문자열 (그림자 등)
                cm = re.findall(r"\b(background|color|border[a-z-]*|box-shadow|outline[a-z-]*)\s*:\s", before)
                kind = prop_kind(cm[-1]) if cm else 'shadow'
                out.append("'" + COL.sub(lambda mm: "' + K.%s + '" % reg.key(kind, mm.group(0)), sval) + "'")
        out.append(line[pos:])
        lines[li] = ''.join(out)
    return '\n'.join(lines)

def add_theme_prop(s, name):
    m = re.search(r"data-props='([^']*)'", s)
    d = json.loads(m.group(1))
    newd = {}
    for k, v in d.items():
        if k == '$preview': continue
        newd[k] = v
    newd['theme'] = {'editor': 'enum', 'options': THEMES, 'default': 'pastel'}
    if name != 'Mascot2': newd['font'] = {'editor': 'enum', 'options': ['mixed', 'jua'], 'default': 'mixed'}
    if '$preview' in d: newd['$preview'] = d['$preview']
    return s[:m.start(1)] + json.dumps(newd, ensure_ascii=False, separators=(',', ':')) + s[m.end(1):]

def build(name):
    s = open(SRC + name + '.dc.html', encoding='utf-8').read()
    reg = Reg(name)
    head, rest = s.split('</helmet>', 1)
    tpl, script = rest.split('<script type="text/x-dc"', 1)
    extra = {}
    mascot = name == 'Mascot2'
    if not mascot:
        first = [True]
        def tag(m):
            name, attrs = m.group(1).lower(), m.group(2)
            if 'style="' not in attrs: return m.group(0)
            st = re.search(r'style="([^"]*)"', attrs).group(1)
            btn = name in ('a', 'button') or 'onClick=' in attrs or 'role="button"' in attrs or pill_control(st)
            def one(mm):
                is_root = first[0]; first[0] = False
                return 'style="' + style_sub(mm.group(1), reg, is_root, extra, btn) + '"'
            return '<' + m.group(1) + re.sub(r'style="([^"]*)"', one, attrs, count=1) + '>'
        tpl = re.sub(r'<([a-zA-Z][\w-]*)((?:[^>"]|"[^"]*")*)>', tag, tpl)
        tpl = re.sub(r'<text\b[^>]*>', lambda m: re.sub(r'\sfill="(#[0-9A-Fa-f]{3,6}|rgba?\([^)]*\))"',
                     lambda mm: ' fill="{{K.%s}}"' % reg.key('text', mm.group(1)), m.group(0)), tpl)
        tpl = re.sub(r'\s(fill|stroke|stop-color)="(#[0-9A-Fa-f]{3,6}|rgba?\([^)]*\))"',
                     lambda m: ' %s="{{K.%s}}"' % (m.group(1), reg.key({'fill': 'svgfill', 'stroke': 'svgstroke', 'stop-color': 'svgstop'}[m.group(1)], m.group(2))), tpl)
        tpl = tpl.replace('<dc-import name="Mascot2"', '<dc-import name="Mascot2" theme="{{themeName}}"')
        assert tpl.count("font-family: 'Pretendard', 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif") == 1, name
        tpl = tpl.replace("font-family: 'Pretendard', 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif", 'font-family: {{FNT.root}}; font-synthesis: {{FNT.syn}}')
    # 스크립트
    attrs, body = script.split('>', 1)
    js, tail = body.split('</script>', 1)
    js = js_sub(js, reg, name)
    js = js.replace("(android ? 'Android-' : '')", "(android ? 'Android-' : ({white: 'White-', glass: 'Glass-', dark: 'Dark-'})[THEME] || '')")
    tables = {t: reg.table(t) for t in THEMES}
    main_roots = {}
    if name == 'Main':
        # 밴드별 배경
        src_js = open(SRC + 'Main.dc.html', encoding='utf-8').read()
        bands = re.findall(r"key: '(\w+)'.*?bg1: '(#\w+)', bg2: '(#\w+)'", src_js, re.S)
        for t in THEMES:
            for key, b1, b2 in bands:
                if t == 'pastel':
                    v = 'radial-gradient(125%% 80%% at 50%% 20%%, #FFFFFF 0%%, %s 42%%, %s 100%%)' % (b1, b2)
                else:
                    hue = root_hue(b1 + ' ' + b2)
                    v = root_for(t, '', hue, from_value=False)
                tables[t]['root_' + key] = v
        tpl = tpl.replace('{{K.root}}', '{{rootBg}}')
    elif 'root' in extra:
        for t in THEMES: tables[t]['root'] = root_for(t, extra['root'])
    for t in THEMES:
        for k in ('fx', 'fxd', 'fxa', 'fxc'): tables[t][k] = GLASS[k] if t == 'glass' else ''
    theme_expr = "(this.state && this.state.themePick) || this.props.theme || 'pastel'" if name == 'MyPage' else "this.props.theme || 'pastel'"
    font_decl = ("\n    var FNT = (this.props.font === 'jua') ? { root: \"'Jua', 'Pretendard', sans-serif\", syn: 'none' }"
                 " : { root: \"'Pretendard', 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif\", syn: 'weight style' };") if not mascot else ''
    decl = ('\n    var THEME = ' + theme_expr + ';\n    var K = (' +
            json.dumps(tables, ensure_ascii=False, separators=(',', ':')) + ')[THEME] || {};' + font_decl)
    i = js.index('renderVals() {') + len('renderVals() {')
    js = js[:i] + decl + js[i:]
    rets = [m for m in re.finditer(r'\n {4}return \{', js)]
    r = rets[-1].end()
    inject = ' K: K, themeName: THEME,'
    if not mascot: inject += ' FNT: FNT,'
    if name == 'Main': inject += " rootBg: K['root_' + band.key],"
    js = js[:r] + inject + js[r:]
    out = head + '</helmet>' + tpl + '<script type="text/x-dc"' + attrs + '>' + js + '</script>' + tail
    out = add_theme_prop(out, name)
    left = COL.findall(out.split('</helmet>', 1)[1].split('<script type="text/x-dc"')[0]) if not mascot else []
    if left: print('  [warn]', name, 'literals left in template:', left[:5])
    open(OUT + name + '.dc.html', 'w', encoding='utf-8').write(out)
    print('%-11s keys %3d' % (name, len(reg.items)))

for n in SCREENS + ['Mascot2']:
    build(n)
