import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
SRC = os.path.join(HERE, 'src')
if '--out' in sys.argv: SRC = os.path.abspath(sys.argv[sys.argv.index('--out') + 1])
from navgen import nav_html, GLASS_JS, GLASS_RET
from mkscreens_common import head, POT, MIC

body = '''<div style="position: relative; width: {{w}}px; height: {{h}}px; box-sizing: border-box; padding-top: {{top}}px; overflow: hidden; display: flex; flex-direction: column; font-family: 'Pretendard', 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif; color: #15181D; letter-spacing: -0.02em; background: radial-gradient(130% 70% at 50% 0%, #FFFFFF 0%, #FBF7F4 45%, #F2E9E2 100%)">

  <header style="display: flex; align-items: center; gap: 10px; padding: 10px 20px 0">
    <div style="flex-grow: 1; display: flex; flex-direction: column; gap: 2px">
      <h1 style="margin: 0; font-size: 30px; line-height: 1.2; font-family: 'Jua', 'Pretendard', sans-serif; font-weight: 400; letter-spacing: -0.01em">조리</h1>
      <span style="font-size: 14px; font-weight: 500; color: #5F6670">단계별로 읽어 주고 타이머도 맞춰요</span>
    </div>
    <dc-import name="Mascot2" mood="hello" size="56" hint-size="56px,56px"></dc-import>
  </header>

  <div style="flex-grow: 1; min-height: 0; overflow: hidden; display: flex; flex-direction: column; gap: 14px; padding: 16px 20px 0">
    <section aria-label="냉장고 재료로 요리하기" style="display: flex; flex-direction: column; padding: 16px 16px 6px; border-radius: 24px; background: rgba(255,255,255,0.9); border: 1px solid rgba(255,255,255,0.95); box-shadow: 0 8px 24px rgba(20,25,35,0.06)">
      <div style="display: flex; align-items: center; gap: 8px">
        <span style="display: inline-flex; align-items: center; height: 22px; padding: 0 8px; border-radius: 11px; background: #EEF0FF; color: #3F4FD1; font-size: 12px; font-weight: 800">AI 추천</span>
        <span style="font-size: 17px; font-weight: 800; letter-spacing: -0.03em">냉장고 재료로 요리하기</span>
        <button type="button" aria-label="추천 새로 받기" style="margin-left: auto; width: 36px; height: 36px; padding: 0; border: 0; border-radius: 50%; background: transparent; color: #8A9199; display: flex; align-items: center; justify-content: center; cursor: pointer; opacity: {{refreshOp}}">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 12a8 8 0 1 1-2.4-5.7M20 4v4.5h-4.5"></path></svg>
        </button>
      </div>
      <sc-if value="{{thinking}}" hint-placeholder-val="{{ false }}">
        <div role="status" aria-label="추천을 고르는 중" style="display: flex; flex-direction: column; align-items: center; padding: 14px 0 18px">
          <dc-import name="Mascot2" mood="asking" size="84" hint-size="84px,84px"></dc-import>
          <span style="margin-top: 10px; font-size: 16px; font-weight: 700">냉장고를 뒤져보는 중</span>
          <svg width="300" height="20" viewBox="0 0 300 20" aria-hidden="true" style="margin-top: 6px; overflow: visible"><text x="150" y="15" text-anchor="middle" font-size="13" font-weight="500" fill="#6B727B" font-family="Pretendard, sans-serif" opacity="0">냉장고 문을 열어보는 중…<animate attributeName="opacity" values="0;1;1;0;0" keyTimes="0;0.027;0.173;0.2;1" dur="12s" begin="0.0s" repeatCount="indefinite"></animate></text><text x="150" y="15" text-anchor="middle" font-size="13" font-weight="500" fill="#6B727B" font-family="Pretendard, sans-serif" opacity="0">기한 코앞인 재료부터 챙기는 중…<animate attributeName="opacity" values="0;1;1;0;0" keyTimes="0;0.027;0.173;0.2;1" dur="12s" begin="2.4s" repeatCount="indefinite"></animate></text><text x="150" y="15" text-anchor="middle" font-size="13" font-weight="500" fill="#6B727B" font-family="Pretendard, sans-serif" opacity="0">뭐랑 뭐가 어울릴지 짝지어 보는 중…<animate attributeName="opacity" values="0;1;1;0;0" keyTimes="0;0.027;0.173;0.2;1" dur="12s" begin="4.8s" repeatCount="indefinite"></animate></text><text x="150" y="15" text-anchor="middle" font-size="13" font-weight="500" fill="#6B727B" font-family="Pretendard, sans-serif" opacity="0">오늘 몇 분이나 걸릴지 어림잡는 중…<animate attributeName="opacity" values="0;1;1;0;0" keyTimes="0;0.027;0.173;0.2;1" dur="12s" begin="7.2s" repeatCount="indefinite"></animate></text><text x="150" y="15" text-anchor="middle" font-size="13" font-weight="500" fill="#6B727B" font-family="Pretendard, sans-serif" opacity="0">이거 맛있으려나 혼자 고민하는 중…<animate attributeName="opacity" values="0;1;1;0;0" keyTimes="0;0.027;0.173;0.2;1" dur="12s" begin="9.6s" repeatCount="indefinite"></animate></text></svg>
          <svg width="40" height="20" viewBox="0 0 40 20" aria-hidden="true" style="margin-top: 12px"><circle cx="4" cy="13" r="4" fill="#E08E00" opacity="0.85"><animate attributeName="cy" values="13;6;13;13" keyTimes="0;0.2;0.4;1" dur="1.4s" begin="0.00s" repeatCount="indefinite"></animate></circle><circle cx="20" cy="13" r="4" fill="#E08E00" opacity="0.65"><animate attributeName="cy" values="13;6;13;13" keyTimes="0;0.2;0.4;1" dur="1.4s" begin="0.15s" repeatCount="indefinite"></animate></circle><circle cx="36" cy="13" r="4" fill="#E08E00" opacity="0.45"><animate attributeName="cy" values="13;6;13;13" keyTimes="0;0.2;0.4;1" dur="1.4s" begin="0.30s" repeatCount="indefinite"></animate></circle></svg>
        </div>
      </sc-if>
      <sc-if value="{{showPicks}}" hint-placeholder-val="{{ true }}">
      <span style="font-size: 13px; font-weight: 500; color: #6B727B; margin-top: 2px">기한 코앞인 두부부터 쓰도록 골랐어요</span>
      <div style="display: flex; flex-direction: column; margin-top: 6px">
        <sc-for list="{{picks}}" as="r" hint-placeholder-count="2">
          <a href="{{r.href}}" style="{{r.rowStyle}}">
            <span style="{{r.iconStyle}}">
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="@POT@"></path></svg>
            </span>
            <span style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px">
              <span style="font-size: 16px; font-weight: 700">{{r.name}}</span>
              <span style="font-size: 13px; font-weight: 500; color: #6B727B">{{r.meta}}</span>
            </span>
            <span style="display: flex; align-items: center; gap: 4px; height: 34px; padding: 0 12px; border-radius: 17px; background: #15181D; color: #FFFFFF; font-size: 13px; font-weight: 700">
              <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l12-7.5z"></path></svg>
              시작
            </span>
          </a>
        </sc-for>
      </div>
      </sc-if>
    </section>

    <section aria-label="영상 레시피로 요리하기" style="display: flex; flex-direction: column; gap: 10px; padding: 16px; border-radius: 24px; background: rgba(255,255,255,0.9); border: 1px solid rgba(255,255,255,0.95); box-shadow: 0 8px 24px rgba(20,25,35,0.06)">
      <div style="display: flex; flex-direction: column; gap: 4px">
        <span style="font-size: 17px; font-weight: 800; letter-spacing: -0.03em">영상 레시피로 요리하기</span>
        <span style="font-size: 13px; font-weight: 500; color: #6B727B">유튜브 링크를 넣으면 단계별로 정리해 드려요</span>
      </div>
      <div style="display: flex; gap: 8px">
        <label style="flex-grow: 1; min-width: 0; display: flex; align-items: center; gap: 8px; height: 48px; box-sizing: border-box; padding: 0 12px; border-radius: 14px; background: #F4F5F8; border: 1px solid rgba(21,24,29,0.06)">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#8A9199" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1 M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1"></path></svg>
          <input type="url" inputmode="url" aria-label="유튜브 링크" placeholder="링크 붙여넣기" style="flex-grow: 1; min-width: 0; height: 100%; padding: 0; border: 0; background: transparent; font-family: inherit; font-size: 15px; color: #15181D; outline: none">
        </label>
        <button type="button" onClick="{{summarize}}" style="flex-shrink: 0; height: 48px; padding: 0 16px; border: 0; border-radius: 14px; background: #15181D; color: #FFFFFF; font-family: inherit; font-size: 15px; font-weight: 700; cursor: pointer">정리하기</button>
      </div>
      <div style="display: flex; gap: 12px; padding: 12px; border-radius: 18px; background: #F8F9FB; border: 1px solid rgba(21,24,29,0.05)">
        <div aria-hidden="true" style="position: relative; width: 92px; height: 64px; flex-shrink: 0; border-radius: 12px; background: linear-gradient(135deg, #3A3F4B 0%, #6B7280 100%); display: flex; align-items: center; justify-content: center">
          <span style="width: 30px; height: 30px; border-radius: 50%; background: rgba(255,255,255,0.9); display: flex; align-items: center; justify-content: center; color: #15181D">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M7 4.5v15l12-7.5z"></path></svg>
          </span>
        </div>
        <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; gap: 3px">
          <span style="font-size: 15px; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">초간단 두부조림</span>
          <span style="font-size: 12px; font-weight: 500; color: #6B727B">5단계 · 약 20분 · 재료 6개 중 5개</span>
          <span style="align-self: flex-start; font-size: 12px; font-weight: 700; padding: 2px 7px; border-radius: 7px; background: #FFEFD2; color: #8F5A08">대파만 없어요</span>
        </div>
      </div>
      <a href="{{links.cooking}}" style="display: flex; align-items: center; justify-content: center; gap: 6px; height: 48px; border-radius: 24px; background: rgba(255,255,255,0.9); border: 1px solid rgba(21,24,29,0.1); color: #15181D; text-decoration: none; font-size: 15px; font-weight: 700">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="@POT@"></path></svg>
        이 레시피로 조리 시작
      </a>
    </section>

    <div style="display: flex; align-items: center; justify-content: center; gap: 6px; font-size: 13px; font-weight: 500; color: #6B727B">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="@MIC@"></path></svg>
      “헤이 키친, 두부로 뭐 해 먹지?”
    </div>
  </div>

@NAV@
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{"platform":{"editor":"enum","options":["ios","android"],"default":"ios"},"picks":{"editor":"enum","options":["list","thinking"],"default":"list"},"$preview":{"width":390,"height":844}}'>
class Component extends DCLogic {
  renderVals() {
    var android = (this.props.platform || 'ios') === 'android';
    var g = android ? { w: 412, h: 915, top: 40, bottom: 24 } : { w: 390, h: 844, top: 59, bottom: 34 };
    var L = function (n) { return (android ? 'Android-' : '') + n + '.dc.html'; };
    // 추천은 세 개까지. 아이콘 칸 색과 끝말이 재료 상태를 말한다(지금 가능 · 확인 필요 · 재료 준비 후).
    var AV = { ready: 'background: #DDF3E4; color: #17703C', check: 'background: #FFEFD2; color: #8F5A08', buy: 'background: #FFE4DB; color: #B0341A' };
    var thinking = this.props.picks === 'thinking';
    var picks = [
      { name: '두부계란전', meta: '2인분 · 약 15분 · 재료 다 있어요', av: 'ready' },
      { name: '두부조림', meta: '2인분 · 약 20분 · 재료 다 있어요', av: 'ready' },
      { name: '마파두부', meta: '2인분 · 약 25분 · 재료 준비 후', av: 'buy' }
    ].map(function (r, i) {
      return { name: r.name, meta: r.meta, href: L('Cooking'),
        iconStyle: 'width: 44px; height: 44px; flex-shrink: 0; border-radius: 14px; display: flex; align-items: center; justify-content: center; ' + AV[r.av],
        rowStyle: 'display: flex; align-items: center; gap: 12px; min-height: 64px; color: #15181D; text-decoration: none;' + (i > 0 ? ' border-top: 1px solid rgba(21,24,29,0.06);' : '') };
    });
@GLASS_JS@
    return { @GLASS_RET@
      w: g.w, h: g.h, top: g.top, bottom: g.bottom,
      picks: picks, summarize: function () {}, thinking: thinking, showPicks: !thinking, refreshOp: thinking ? 0.4 : 1,
      links: { home: L('Main'), fridge: L('Fridge'), cook: L('CookHome'), history: L('History'), my: L('MyPage'), cooking: L('Cooking') }
    };
  }
}
</script>
</body>
</html>
'''
out = head('조리') + body.replace('@POT@', POT).replace('@MIC@', MIC).replace('@NAV@', nav_html('cook')).replace('@GLASS_JS@', GLASS_JS.rstrip('\n')).replace('@GLASS_RET@', GLASS_RET)
open(os.path.join(SRC, 'CookHome.dc.html'), 'w', encoding='utf-8').write(out)
print('ok')
