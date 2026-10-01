---
type: guide
status: active
---

# 오늘 뭐 먹지?

장본 것을 말로 넣고, 쓴 것을 말로 빼고, 남은 재료로 오늘 저녁을 정하는 Flutter 앱이다.
유튜브 레시피 링크에서 재료와 조리 단계를 정리해 조리 화면으로 연결하는 기능도 구현했다.
손이 바쁜 조리 중에도 단계 안내와 음성 조작을 사용할 수 있도록 구성했다.

## 핵심 사용 흐름

| 상황 | 앱에서 하는 일 |
|---|---|
| 장본 뒤 | “헤이 키친”으로 불러 재료·수량·보관 정보를 말로 등록 |
| 재료를 쓰거나 잘못 기록했을 때 | 사용량 반영·잔량 보정·직전 변경 취소와 이력 확인 |
| 메뉴를 정할 때 | 현재 재고로 메뉴를 추천받고 인분별 재료·부족량 확인 |
| 레시피를 따라 요리할 때 | 추천 메뉴 또는 유튜브 링크 분석 결과로 조리 시작, 단계·타이머·낭독 이용 |

AI는 발화와 영상에서 의도·재료·조리 순서를 해석한다. 서버는 수량·단위·대상을 검증하고
변경 이력을 저장한다. 모르는 수량을 임의로 채우지 않으며, 반영한 변경은 이력으로 되돌린다.
명확한 항목만 먼저 저장하는 복합 등록의 부분 반영은 아직 구현되지 않은 목표다.

## 제출 상태와 실행

[제출 전 상태·검증 결과](docs/verification/results/2026-09-30-submission-status.md)에서
현재 코드 확인, 과거 실기기 관찰, 이번 자동 검증을 구분한다. Android·iOS를 대상으로 하지만
기존 실기기 기록은 Android 한 대이며 iOS 설치 검증은 남아 있다.
앱을 열어 둔 전경에서 호출을 받으며, 잠금·백그라운드 상시 대기는 후속 범위다.
영상에서 시작한 조리는 완료해도 재고를 자동 차감하지 않는다.

실행은 아래 [개발 환경](#개발-환경)과 [로컬 개발 런북](docs/runbook/local-development.md)을,
시연 순서는 [발표 구성안](docs/product/presentation-plan.md)을 따른다.
실제 앱 캡처·시연 영상의 제출 링크는 아직 확정하지 않았다.
[목업](mockup/README.md)은 화면 설계 자료이며 실제 앱 동작 증거와 구분한다.
계획 일정은 9/28~9/30, 실제 개발 기간은 개발자 설명 기준 이틀이다. 제출 목표는 9/30 18:00,
시연은 10/2다.

## 작업을 시작할 때

[개발 작업 기준](AGENTS.md)을 먼저 읽는다. **현재 목업의 화면과 동작을 구현 기준으로 쓴다.**
문서에 요구가 적혀 있다는 것과 코드·실기기에서 동작한다는 것을 구분한다.

| 질문 | 기준 문서 |
|---|---|
| 무엇을 어디까지 만드는가 | [기능 범위](docs/scope/today-meal.md) |
| 등록·확인·정정·취소는 어떻게 동작하는가 | [제품 정책](docs/product/proposal.md) |
| 어떤 목업을 구현하는가 | [목업 인계](mockup/README.md) |
| 화면·상태·버튼·오류는 어떻게 연결되는가 | [UI 계약](docs/ui/mobile.md) |
| 작업을 어떤 순서로 진행하는가 | [기능 개발 절차](docs/runbook/feature-development.md) |
| 현재 구조와 구현 차이는 무엇인가 | [아키텍처](docs/architecture/README.md) · [작업표](docs/plan/hackathon-3day.md) |
| 기술·데이터 선택의 이유는 무엇인가 | [기술 설계](docs/design/0001-mvp-technical-design.md) · [DB 설계](docs/design/0002-database.md) |
| 무엇을 확인해야 완료인가 | [검증 기준](docs/verification/mvp.md) |
| 어떻게 새 환경에서 실행하는가 | [로컬 개발 런북](docs/runbook/local-development.md) |

제품 범위는 기능 범위가, 동작 의미는 제품 정책이, 시각은 선택된 목업이 기준이다.
UI 계약은 이 셋을 화면별 동작으로 연결한다. 충돌을 임의로 선택하지 않고 관련 문서를 함께 고친다.

## 구성

```text
app/       Flutter 앱: UI·음성 입출력·API 연결
server/    FastAPI·SQLAlchemy·PostgreSQL: 해석 검증·재고 계산·저장
mockup/    화면 기준과 인계 문서
docs/      범위·정책·UI 계약·설계·작업·검증·운영
scripts/   로컬 기동·저장소 재현성 검사·통합 검증
```

현재 음성 구현은 기기 음성 인식 서비스를 반복 실행해 호출어를 찾는다. 대기 중 LLM 호출은
없지만 음성 인식 서비스의 외부 통신은 있을 수 있다. 앱이 전경에서 동작할 때만 감지한다.
제품과 코드의 기본 호출어는 “Hey Kitchen(헤이 키친)”이며 유사한 전사 결과도 호출로 받는다.
“자비스”·“헤이 냉장고”는 이전 호출어 별칭이다. Porcupine은 제외한 선택으로 설치에 필요하지
않으며 도입 목표로 두지 않는다. 선택 배경과 인식 보정의 한계는
[기술 설계](docs/design/0001-mvp-technical-design.md)에 기록했다.

화면은 16개다 — 스플래시·로그인·회원가입·권한·홈·메뉴 상세·냉장고·재료 상세·조리 홈·조리
진행·조리 완료·기록·마이페이지와 듣기·확인 질문·반영 결과. 뭐 먹지?·냉장고·조리·기록·
마이페이지 다섯 탭을 사용한다. 화면 ID의 정본은 [기능 범위](docs/scope/today-meal.md)다.
계정은 검증하는 서버 세션이며([ADR-0001](docs/adr/0001-verified-sessions.md)) 이전 식별 전용
설명은 폐기했다.

## 개발 환경

Python 3.12·Poetry·Docker·Flutter SDK·Android SDK가 필요하다. iOS 빌드·실기기 설치에는
Xcode와 서명 환경도 필요하다. Flutter·Dart 호환 범위는 `app/pubspec.yaml`과 lock 파일을 따른다.

```sh
# 최초 1회: example을 복사하고 서버 DB 비밀번호·Gemini 키를 설정
cp server/.env.example server/.env
cp app/.env.example app/.env
cd server
poetry install
cd ../app
flutter pub get
cd ..

# 터미널 1: DB·마이그레이션·시드·LAN 주소 설정·서버
sh scripts/dev.sh

# 터미널 2: 앱
cd app
flutter run

# 저장소 루트에서 검증
sh scripts/verify.sh
```

서버 키가 없으면 가짜 LLM이 선택될 수 있다. 이를 실제 모델 검증으로 기록하지 않는다.
Windows는 Git Bash에서 실행한다. 상세 성공 조건·오류 복구·재현 절차는 런북을 따른다.

## 문서와 저장소 관리

`.engsys/project.yaml`이 경로별 문서 유형과 검증 명령을 선언한다. 문서 변경 후
`engsys docs check --project .`와 개별 편집 검토를 수행한다. 기술 설계는 아직 `draft`이며
동결 후 결정을 뒤집을 때 ADR을 작성한다. 동결된 ADR은 당시 기록이므로 고치지 않는다.

비밀값은 `.env`에만 둔다. `app/lib/data/`는 앱 소스이므로 반드시 커밋 대상에 포함한다.
`python3 scripts/check-repository.py`가 누락·무시된 소스와 깨진 상대 참조를 검사한다.
커밋 헤더는 `<type>(<scope>): <한글 명사형 subject>`이며 subject는 50자 이내다.
