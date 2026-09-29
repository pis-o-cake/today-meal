---
type: prototype-record
status: active
prototype-version: mobile-2026-09-29-r2
---

# 모바일 목업 구현 인계

선택한 화면·캐릭터·인터랙션과 구현에 필요한 보완 계약을 안내한다. 목업은 기능 완료 증거가 아니다.

## 대상과 version

현재 `canvas/`의 화면 HTML을 앱 시각 기준으로 사용한다. 판본은 `mobile-2026-09-29-r2`다.
9/29 최신 작업 트리의 계정 화면·4개 탭·캐릭터 대화·헤이 키친 변경을 포함한다.
검증 시 실제 파일 해시 또는 커밋을 남긴다.
이는 화면 기준의 선택이며 앱 구현 완료나 실기기 검증을 뜻하지 않는다.

[UI 계약](../docs/ui/mobile.md)은 목업을 사용자 흐름·데이터·실패 처리로 연결한다.
목업의 날짜·재료·수량은 시연 예시이며 서버 실데이터를 대체하지 않는다.

## 화면과 상태

| 화면 ID | iOS 기준 | Android 기준 | 핵심 표현 |
|---|---|---|---|
| UI-00 | [Splash](canvas/Splash.dc.html) | [Android-Splash](canvas/Android-Splash.dc.html) | 냉장고 착지·문 열림·미소·제목 등장 |
| UI-01 | [Permission](canvas/Permission.dc.html) | [Android-Permission](canvas/Android-Permission.dc.html) | 권한 설명·권한 요청·마이크 없이 둘러보기 |
| UI-02 | [Main](canvas/Main.dc.html) | [Android-Main](canvas/Android-Main.dc.html) | 캐릭터·밴드 스와이프·메뉴 진입·뭐 먹지?/냉장고/기록/마이페이지 |
| UI-03 | [Listening](canvas/Listening.dc.html) | [Android-Listening](canvas/Android-Listening.dc.html) | 보라 캐릭터·단계 막대·들은 말·20초·취소 |
| UI-04 | [Clarify](canvas/Clarify.dc.html) | [Android-Clarify](canvas/Android-Clarify.dc.html) | 반영된 항목·질문·선택지·8초 응답 창 |
| UI-05 | [Result](canvas/Result.dc.html) | [Android-Result](canvas/Android-Result.dc.html) | 반영 결과·항목별 상세·되돌리기·확인·4초 복귀 |
| UI-06 | [Fridge](canvas/Fridge.dc.html) | [Android-Fridge](canvas/Android-Fridge.dc.html) | 검색·보관 필터·2열 재료 타일 |
| UI-07 | [Menu](canvas/Menu.dc.html) | [Android-Menu](canvas/Android-Menu.dc.html) | 인분·재료 상태·순서·조리 모드 시작 |
| UI-08 | [History](canvas/History.dc.html) | [Android-History](canvas/Android-History.dc.html) | 사용자 발화와 응답 카드·최근 변경 되돌리기 |
| UI-09 | [Login](canvas/Login.dc.html) | [Android-Login](canvas/Android-Login.dc.html) | 이메일·비밀번호·간편 로그인·둘러보기 |
| UI-10 | [SignUp](canvas/SignUp.dc.html) | [Android-SignUp](canvas/Android-SignUp.dc.html) | 닉네임·이메일·비밀번호·필수/선택 약관 |
| UI-11 | [MyPage](canvas/MyPage.dc.html) | [Android-MyPage](canvas/Android-MyPage.dc.html) | 음성·식사·알림 설정·로그아웃 |

캐릭터는 [Mascot2](canvas/Mascot2.dc.html)·[상태 모음](canvas/Mascot2-states.dc.html)의
냉장고 친구를 쓴다. `C2-*`는 같은 캐릭터를 명시한 비교용 래퍼다. `Mascot`·`Mascot3`·`C3-*`는
선택되지 않은 시안이다. [Neuron](canvas/Neuron.dc.html)은 이전 듣기 시안이며 더 이상 UI-03의 기준이 아니다.
[TabIcons](canvas/TabIcons.dc.html)의 A 수저(숟가락+젓가락)가 뭐 먹지? 탭 아이콘이다.
[index.html](index.html)은 이전 단독 인터랙션 실험이며 화면별 구현 기준으로 쓰지 않는다.

스플래시는 앱에서 약 1.8초 동안 한 번만 재생하고 준비 완료 후 첫 진입 화면으로 페이드한다.
목업의 4.2초 반복은 관찰용이다. 유효한 세션이나 이미 선택한 게스트 상태가 있으면 UI-02, 첫 방문이면 UI-09로 연결한다.
로그인·가입·둘러보기 뒤 음성 권한 안내가 필요하면 UI-01을 거쳐 UI-02로 이동한다.
초기화 실패를 애니메이션 반복으로 숨기지 않으며 모션 감소 설정에서는 정지 이미지로 대체한다.

## 구현 인계 사항

판단 순서는 화면 HTML → 이 문서의 충돌 해석 → UI 계약의 보완 상태다.
`canvas.json`은 보드 배치·메모를 보존한다. 메모와 화면이 다른 아래 사항은 화면 HTML을 따른다.

| 차이 | 구현 기준 |
|---|---|
| 이전 듣기 화면은 어두운 그래프 | 최신 Listening과 메모가 모두 Mascot2·파동·들은 말 카드를 사용 |
| 예전 개발 계획은 시각 디자인을 미확정으로 취급 | 이 판본의 정보 배치·캐릭터·탭·타일·기록 형태를 구현 기준으로 고정 |
| 코드의 기본 호출어는 자비스·내장 반복 청취 | 목표는 Hey Kitchen(헤이 키친)·Porcupine 영어 커스텀 호출어. 키·OS별 모델·인식 품질 검증 전 완료 아님 |
| 이전 범위는 로그인 추가·보안 제외 | 최신 로그인·가입·마이페이지를 목표 범위에 편입. 기존 식별 헤더를 실제 인증으로 사용하지 않음 |
| 서버는 질문 시 전체 보류 | UI-04의 부분 반영을 지원하도록 명령 그룹·미완료 항목·후속 답변 계약을 구현해야 함 |
| 코드의 재질문 창은 10초 | 질문 낭독 후 8초. 응답 중에는 카운트다운이 입력을 끊지 않음. 2026-09-29 앱에 반영 |
| 기존 코드에 해먹었어요 차감 버튼 | UI-07은 조리 모드와 명시적 사용 발화. 레시피 일괄 차감은 이 판본에서 노출하지 않음. 2026-09-29 앱에서 내림 |
| 화면 HTML의 테마 4종이 계약에 없었음 | 파스텔·화이트·글래스·다크를 구현 범위에 편입하고 마이페이지에서 고른다 |

상태 이름은 기한 지났어요·얼마 안 남았어요·며칠 남았어요·넉넉해요·날짜 몰라요다.
화면 날짜는 연도를 포함하고 음성은 “2026년 10월 3일”처럼 읽는다. 스플래시·로그인·권한은
보라 배경과 hello 캐릭터를 사용한다. 상세 규칙은 UI 계약을 따른다.

iOS 390×844·Android 412×915는 비교용 뷰포트이며 SafeArea 수치를 실기기에 고정하지 않는다.
목업의 `overflow: hidden`을 그대로 복사해 목록이나 큰 글자를 자르지 않는다. 실제 앱은 스크롤과
접근성을 보장한다. 재고 막대의 예시 퍼센트는 신선도 측정값이 아니다. 의미는 UI 계약을 따른다.

### 열람과 재현

`*.dc.html`은 Design Canvas 런타임의 `dc-import`·`sc-for`·`DCLogic`에 의존한다.
`support.js`와 `/_blob/...`는 편집기 제공 자원이며 저장소에 들어 있지 않다. 일반 브라우저에서
파일을 열었다고 목업이 정상 렌더링된 것으로 기록하지 않는다. `canvas.json`과 화면 소스를
해당 편집기에 가져와 열거나, 편집기에서 독립 HTML/이미지를 내보내 비교 증거로 사용한다.
앱은 저장소의 [Pretendard](../app/assets/fonts/PretendardVariable.ttf)를 번들한다.

소스 기반 화면 계약은 이 저장소만으로 읽을 수 있다. 편집기 없는 환경의 시각 검증에는 내보낸
스크린샷이 필요하며 현재 별도 내보내기 산출물은 없다. 이 제약은 작업표의 R-08에서 추적한다.
검증 시 목업 판본·기기·화면 크기·앱 커밋·비교 이미지 경로를 함께 기록한다.
