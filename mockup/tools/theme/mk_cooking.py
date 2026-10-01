import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mkscreens_common import head, POT, MIC

C = round(2 * math.pi * 56, 1)

cooking = '''<div style="position: relative; width: {{w}}px; height: {{h}}px; box-sizing: border-box; padding-top: {{top}}px; padding-bottom: {{bottom}}px; overflow: hidden; display: flex; flex-direction: column; font-family: 'Pretendard', 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif; color: #15181D; letter-spacing: -0.02em; background: radial-gradient(130% 75% at 50% 10%, #FFFFFF 0%, #FFF7F1 45%, #F8E3D6 100%)">

  <div style="display: grid; grid-template-columns: 44px 1fr 44px; align-items: center; padding: 8px 16px 0">
    <a href="{{links.back}}" aria-label="조리 모드 닫기" style="width: 44px; height: 44px; box-sizing: border-box; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #3E454E; background: rgba(255,255,255,0.8); border: 1px solid rgba(255,255,255,0.95); box-shadow: 0 4px 12px rgba(20,25,35,0.06); text-decoration: none">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"></path></svg>
    </a>
    <div style="display: flex; flex-direction: column; align-items: center; gap: 1px">
      <span style="font-size: 16px; font-weight: 800; letter-spacing: -0.03em">두부계란전</span>
      <span style="font-size: 12px; font-weight: 600; color: #8A9199">조리 모드 · 2인분</span>
    </div>
    <button type="button" aria-label="전체 단계 보기" style="width: 44px; height: 44px; box-sizing: border-box; padding: 0; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #3E454E; background: rgba(255,255,255,0.8); border: 1px solid rgba(255,255,255,0.95); box-shadow: 0 4px 12px rgba(20,25,35,0.06); cursor: pointer">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01"></path></svg>
    </button>
  </div>

  <ol aria-label="조리 단계" style="list-style: none; margin: 0; padding: 14px 20px 0; display: flex; gap: 5px">
    <sc-for list="{{bars}}" as="b" hint-placeholder-count="5">
      <li aria-current="{{b.current}}" style="{{b.style}}"></li>
    </sc-for>
  </ol>
  <div style="display: flex; align-items: center; justify-content: space-between; padding: 8px 20px 0">
    <span style="font-size: 14px; font-weight: 800; color: #C2410C">{{stepNo}}단계 <span style="font-weight: 600; color: #8A9199">/ {{total}}</span></span>
    <span style="display: flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 600; color: #6B727B">
      <svg width="22" height="14" viewBox="0 0 22 14" aria-hidden="true">
        <rect x="1" y="4" width="3" height="6" rx="1.5" fill="#C2410C"><animate attributeName="height" values="6;12;4;6" dur="0.9s" repeatCount="indefinite"></animate><animate attributeName="y" values="4;1;5;4" dur="0.9s" repeatCount="indefinite"></animate></rect>
        <rect x="7" y="2" width="3" height="10" rx="1.5" fill="#C2410C"><animate attributeName="height" values="10;4;12;10" dur="1.1s" repeatCount="indefinite"></animate><animate attributeName="y" values="2;5;1;2" dur="1.1s" repeatCount="indefinite"></animate></rect>
        <rect x="13" y="3" width="3" height="8" rx="1.5" fill="#C2410C"><animate attributeName="height" values="8;12;5;8" dur="0.8s" repeatCount="indefinite"></animate><animate attributeName="y" values="3;1;4.5;3" dur="0.8s" repeatCount="indefinite"></animate></rect>
        <rect x="19" y="5" width="2" height="4" rx="1" fill="#C2410C" opacity="0.5"></rect>
      </svg>
      읽어 주는 중
    </span>
  </div>

  <section aria-label="지금 단계" style="margin: 12px 20px 0; padding: 20px 20px 18px; border-radius: 26px; background: rgba(255,255,255,0.9); border: 1px solid rgba(255,255,255,0.95); box-shadow: 0 10px 28px rgba(20,25,35,0.08)">
    <p style="margin: 0; font-size: 25px; line-height: 1.38; font-weight: 800; letter-spacing: -0.04em; word-break: keep-all">{{step.t}}</p>
    <div style="display: flex; flex-wrap: wrap; gap: 6px; margin-top: 14px">
      <sc-for list="{{step.ing}}" as="i" hint-placeholder-count="2">
        <span style="font-size: 13px; font-weight: 600; padding: 6px 11px; border-radius: 999px; background: #F4F1EE; color: #4E5661">{{i}}</span>
      </sc-for>
    </div>
  </section>

  <sc-if value="{{hasTimer}}" hint-placeholder-val="{{ true }}">
    <section aria-label="단계 타이머" style="margin: 12px 20px 0; display: flex; align-items: center; gap: 16px; padding: 16px 18px; border-radius: 26px; background: rgba(255,255,255,0.9); border: 1px solid rgba(255,255,255,0.95); box-shadow: 0 10px 28px rgba(20,25,35,0.08)">
      <div style="position: relative; width: 124px; height: 124px; flex-shrink: 0">
        <svg width="124" height="124" viewBox="0 0 124 124" aria-hidden="true" style="position: absolute; left: 0; top: 0; transform: rotate(-90deg)">
          <circle cx="62" cy="62" r="56" fill="none" stroke="#F1E6DE" stroke-width="9"></circle>
          <circle cx="62" cy="62" r="56" fill="none" stroke="#E0552F" stroke-width="9" stroke-linecap="round" stroke-dasharray="@C@" stroke-dashoffset="{{timerFrom}}">
            <animate attributeName="stroke-dashoffset" values="{{timerFrom}};@C@" dur="{{timerDur}}" repeatCount="indefinite"></animate>
          </circle>
        </svg>
        <div style="position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center">
          <span style="font-size: 28px; font-weight: 800; letter-spacing: -0.03em; font-variant-numeric: tabular-nums">{{step.left}}</span>
          <span style="font-size: 12px; font-weight: 600; color: #8A9199">{{step.timerLabel}}</span>
        </div>
      </div>
      <div style="flex-grow: 1; display: flex; flex-direction: column; gap: 8px">
        <button type="button" style="display: flex; align-items: center; justify-content: center; gap: 6px; height: 44px; border: 0; border-radius: 22px; background: #15181D; color: #FFFFFF; font-family: inherit; font-size: 15px; font-weight: 700; cursor: pointer">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M6 4h4v16H6zM14 4h4v16h-4z"></path></svg>
          잠깐 멈춤
        </button>
        <div style="display: flex; gap: 8px">
          <button type="button" style="flex-grow: 1; height: 40px; border-radius: 20px; background: rgba(255,255,255,0.9); border: 1px solid rgba(21,24,29,0.1); color: #15181D; font-family: inherit; font-size: 14px; font-weight: 700; cursor: pointer">+1분</button>
          <button type="button" style="flex-grow: 1; height: 40px; border-radius: 20px; background: rgba(255,255,255,0.9); border: 1px solid rgba(21,24,29,0.1); color: #15181D; font-family: inherit; font-size: 14px; font-weight: 700; cursor: pointer">처음부터</button>
        </div>
      </div>
    </section>
  </sc-if>
  <sc-if value="{{noTimer}}" hint-placeholder-val="{{ false }}">
    <div style="margin: 12px 20px 0; display: flex; align-items: center; gap: 12px; padding: 16px 18px; border-radius: 22px; border: 1.5px dashed rgba(21,24,29,0.14); color: #5F6670; font-size: 14px; font-weight: 600">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="13" r="8"></circle><path d="M12 9v4l2.5 1.5M9.5 2.5h5"></path></svg>
      시간이 필요하면 “타이머 3분”이라고 말해요
    </div>
  </sc-if>

  <sc-if value="{{notLast}}" hint-placeholder-val="{{ true }}">
    <div style="margin: 12px 20px 0; display: flex; align-items: center; gap: 10px; padding: 12px 16px; border-radius: 18px; background: rgba(255,255,255,0.55); border: 1px solid rgba(255,255,255,0.9)">
      <span style="flex-shrink: 0; font-size: 12px; font-weight: 800; color: #8A9199">다음</span>
      <span style="flex-grow: 1; min-width: 0; font-size: 14px; font-weight: 600; color: #4E5661; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">{{nextText}}</span>
    </div>
  </sc-if>

  <div style="margin-top: auto; display: flex; flex-direction: column; gap: 10px; padding: 12px 20px 8px">
    <div style="display: flex; align-items: center; gap: 8px; flex-wrap: wrap; justify-content: center">
      <span style="display: flex; align-items: center; gap: 5px; font-size: 12px; font-weight: 700; color: #C2410C">
        <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="4" fill="#C2410C" fill-opacity="0.3"><animate attributeName="r" values="4;8;4" dur="1.4s" repeatCount="indefinite"></animate><animate attributeName="fill-opacity" values="0.35;0;0.35" dur="1.4s" repeatCount="indefinite"></animate></circle><circle cx="8" cy="8" r="4" fill="#C2410C"></circle></svg>
        호출어 없이 들어요
      </span>
      <span style="font-size: 13px; font-weight: 600; padding: 5px 10px; border-radius: 999px; background: rgba(255,255,255,0.8); color: #3E454E">“다음”</span>
      <span style="font-size: 13px; font-weight: 600; padding: 5px 10px; border-radius: 999px; background: rgba(255,255,255,0.8); color: #3E454E">“다시 읽어 줘”</span>
      <span style="font-size: 13px; font-weight: 600; padding: 5px 10px; border-radius: 999px; background: rgba(255,255,255,0.8); color: #3E454E">“타이머 3분”</span>
    </div>
    <div style="display: flex; gap: 10px">
      <button type="button" onClick="{{prev}}" aria-disabled="{{firstStep}}" style="{{prevStyle}}">이전</button>
      <sc-if value="{{notLast}}" hint-placeholder-val="{{ true }}">
        <button type="button" onClick="{{next}}" style="flex-grow: 2; flex-basis: 0; display: flex; align-items: center; justify-content: center; gap: 6px; height: 56px; border: 0; border-radius: 28px; background: #15181D; color: #FFFFFF; font-family: inherit; font-size: 17px; font-weight: 700; box-shadow: 0 10px 22px rgba(20,25,35,0.22); cursor: pointer">
          다음 단계
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"></path></svg>
        </button>
      </sc-if>
      <sc-if value="{{isLast}}" hint-placeholder-val="{{ false }}">
        <a href="{{links.done}}" style="flex-grow: 2; flex-basis: 0; display: flex; align-items: center; justify-content: center; height: 56px; border-radius: 28px; background: #1B7F43; color: #FFFFFF; text-decoration: none; font-size: 17px; font-weight: 700; box-shadow: 0 10px 22px rgba(27,127,67,0.25)">다 만들었어요</a>
      </sc-if>
    </div>
  </div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{"platform":{"editor":"enum","options":["ios","android"],"default":"ios"},"$preview":{"width":390,"height":844}}'>
class Component extends DCLogic {
  renderVals() {
    var android = (this.props.platform || 'ios') === 'android';
    var g = android ? { w: 412, h: 915, top: 40, bottom: 24 } : { w: 390, h: 844, top: 59, bottom: 34 };
    var L = function (n) { return (android ? 'Android-' : '') + n + '.dc.html'; };
    var self = this;
    var st = this.state || {};
    var steps = [
      { t: '두부 1모를 1cm 두께로 썰어요', ing: ['두부 1모', '도마 · 칼'] },
      { t: '키친타월에 올려 두부 물기를 빼요', ing: ['두부', '키친타월'], timer: 180, left: '02:48', frac: 0.07, timerLabel: '물기 빼기' },
      { t: '계란 2개에 소금 한 꼬집을 넣고 잘 풀어요', ing: ['계란 2개', '소금 약간'] },
      { t: '두부에 계란물을 입혀 중약불에서 한 면씩 부쳐요', ing: ['식용유 2큰술'], timer: 120, left: '02:00', frac: 0, timerLabel: '한 면 굽기' },
      { t: '앞뒤로 노릇해지면 접시에 담아요', ing: [] }
    ];
    var i = st.step === undefined ? 1 : st.step;
    var step = steps[i];
    var C = @C@;
    var bars = steps.map(function (s, k) {
      return { current: k === i ? 'step' : 'false', style: 'flex: 1 1 0; height: 6px; border-radius: 3px; background: ' + (k < i ? '#F0A58C' : (k === i ? '#E0552F' : 'rgba(21,24,29,0.1)')) };
    });
    var first = i === 0, last = i === steps.length - 1;
    return {
      w: g.w, h: g.h, top: g.top, bottom: g.bottom,
      bars: bars, stepNo: i + 1, total: steps.length, nextText: last ? '' : steps[i + 1].t,
      step: { t: step.t, ing: step.ing, left: step.left || '', timerLabel: step.timerLabel || '' },
      hasTimer: !!step.timer, noTimer: !step.timer,
      timerFrom: step.timer ? Math.round(C * (step.frac || 0) * 10) / 10 : 0,
      timerDur: step.timer ? Math.round(step.timer * (1 - (step.frac || 0))) + 's' : '1s',
      firstStep: first ? 'true' : 'false', notLast: !last, isLast: last,
      prev: function () { if (!first) self.setState({ step: i - 1 }); },
      next: function () { if (!last) self.setState({ step: i + 1 }); },
      prevStyle: 'flex-grow: 1; flex-basis: 0; height: 56px; border-radius: 28px; background: rgba(255,255,255,0.9); border: 1px solid rgba(21,24,29,0.1); color: #15181D; font-family: inherit; font-size: 16px; font-weight: 700; cursor: pointer;' + (first ? ' opacity: 0.4;' : ''),
      links: { back: L('CookHome'), done: L('CookDone') }
    };
  }
}
</script>
</body>
</html>
'''.replace('@C@', str(C))

done = '''<div style="position: relative; width: {{w}}px; height: {{h}}px; box-sizing: border-box; padding-top: {{top}}px; padding-bottom: {{bottom}}px; overflow: hidden; display: flex; flex-direction: column; font-family: 'Pretendard', 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif; color: #15181D; letter-spacing: -0.02em; background: radial-gradient(125% 80% at 50% 22%, #FFFFFF 0%, #F3FBF6 40%, #D3EFDD 100%)">

  <div style="display: flex; justify-content: flex-end; padding: 8px 16px 0">
    <a href="{{links.home}}" aria-label="닫기" style="width: 44px; height: 44px; box-sizing: border-box; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #3E454E; background: rgba(255,255,255,0.74); border: 1px solid rgba(255,255,255,0.95); text-decoration: none">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"></path></svg>
    </a>
  </div>

  <main style="flex-grow: 1; min-height: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 0 24px; text-align: center">
    <dc-import name="Mascot2" mood="done" size="{{mascotSize}}" hint-size="{{mascotHint}}"></dc-import>
    <div style="font-size: 38px; line-height: 1.15; font-family: 'Jua', 'Pretendard', sans-serif; font-weight: 400; letter-spacing: -0.01em; color: #1B7F43; margin-top: 4px">짠, 다 만들었어요!</div>
    <div style="font-size: 15px; font-weight: 500; color: #5F6670; margin-top: 8px">두부계란전 · 2인분 · 17분 걸렸어요</div>
  </main>

  <section aria-label="뺀 재료" style="margin: 0 20px; padding: 6px 0; border-radius: 24px; background: rgba(255,255,255,0.9); border: 1px solid rgba(255,255,255,0.95); box-shadow: 0 10px 28px rgba(20,25,35,0.08)">
    <div style="display: flex; align-items: center; justify-content: space-between; padding: 12px 16px 6px">
      <span style="font-size: 16px; font-weight: 800; letter-spacing: -0.03em">쓴 재료를 냉장고에서 뺐어요</span>
      <span style="font-size: 12px; font-weight: 600; color: #8A9199">자동 차감</span>
    </div>
    <sc-for list="{{rows}}" as="r" hint-placeholder-count="3">
      <div style="{{r.rowStyle}}">
        <span style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px">
          <span style="font-size: 16px; font-weight: 700">{{r.name}}</span>
          <span style="font-size: 13px; font-weight: 500; color: #6B727B">{{r.meta}}</span>
        </span>
        <span style="{{r.chipStyle}}">{{r.chip}}</span>
        <button type="button" aria-label="{{r.editLabel}}" style="width: 36px; height: 36px; padding: 0; border: 0; border-radius: 50%; background: transparent; color: #8A9199; display: flex; align-items: center; justify-content: center; cursor: pointer">
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16z M13.5 6.5l4 4"></path></svg>
        </button>
      </div>
    </sc-for>
  </section>
  <div style="display: flex; align-items: center; justify-content: center; gap: 6px; padding: 10px 24px 0; font-size: 13px; font-weight: 500; color: #4E5661">
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="@MIC@"></path></svg>
    틀렸으면 “계란은 3개 썼어”라고 말해 주세요
  </div>

  <div style="display: flex; gap: 10px; padding: 14px 20px 4px">
    <a href="{{links.cooking}}" style="flex-grow: 1; flex-basis: 0; box-sizing: border-box; display: flex; align-items: center; justify-content: center; gap: 8px; height: 56px; border-radius: 28px; background: rgba(255,255,255,0.86); border: 1px solid rgba(21,24,29,0.12); color: #15181D; text-decoration: none; font-size: 16px; font-weight: 700">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 14L4 9l5-5"></path><path d="M4 9h10a6 6 0 0 1 0 12h-3"></path></svg>
      되돌리기
    </a>
    <a href="{{links.home}}" style="flex-grow: 1; flex-basis: 0; box-sizing: border-box; border: 1px solid #15181D; display: flex; align-items: center; justify-content: center; height: 56px; border-radius: 28px; background: #15181D; color: #FFFFFF; text-decoration: none; font-size: 16px; font-weight: 700; box-shadow: 0 10px 22px rgba(20,25,35,0.22)">확인</a>
  </div>
  <div style="text-align: center; font-size: 13px; font-weight: 500; color: #5F6670; padding: 8px 20px 8px">기록에도 남겼어요</div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{"platform":{"editor":"enum","options":["ios","android"],"default":"ios"},"$preview":{"width":390,"height":844}}'>
class Component extends DCLogic {
  renderVals() {
    var android = (this.props.platform || 'ios') === 'android';
    var g = android ? { w: 412, h: 915, top: 40, bottom: 24, mascot: 170 } : { w: 390, h: 844, top: 59, bottom: 34, mascot: 150 };
    var L = function (n) { return (android ? 'Android-' : '') + n + '.dc.html'; };
    var rows = [
      { name: '두부', meta: '2모 → 1모', chip: '−1모', used: true },
      { name: '계란', meta: '4개 → 2개', chip: '−2개', used: true },
      { name: '대파', meta: '빼지 못했어요', chip: '그대로', used: false }
    ].map(function (r, i) {
      return { name: r.name, meta: r.meta, chip: r.chip, editLabel: r.name + ' 뺀 양 고치기',
        rowStyle: 'display: flex; align-items: center; gap: 10px; min-height: 60px; padding: 4px 8px 4px 16px;' + (i > 0 ? ' border-top: 1px solid rgba(21,24,29,0.06);' : ''),
        chipStyle: 'flex-shrink: 0; font-size: 13px; font-weight: 700; padding: 4px 9px; border-radius: 8px;' + (r.used ? ' background: #FFE4DB; color: #B0341A;' : ' background: #F0F1F4; color: #5F6670;') };
    });
    return {
      w: g.w, h: g.h, top: g.top, bottom: g.bottom,
      mascotSize: g.mascot, mascotHint: g.mascot + 'px,' + g.mascot + 'px',
      rows: rows,
      links: { home: L('Main'), cooking: L('Cooking') }
    };
  }
}
</script>
</body>
</html>
'''.replace('@MIC@', MIC)

P = os.path.join(HERE, 'src') + os.sep
if '--out' in sys.argv: P = os.path.abspath(sys.argv[sys.argv.index('--out') + 1]) + os.sep
open(P + 'Cooking.dc.html', 'w', encoding='utf-8').write(head('조리 중') + cooking)
open(P + 'CookDone.dc.html', 'w', encoding='utf-8').write(head('조리 완료') + done)
print('ok', C)
