---
type: guide
status: active
---

# 오늘 뭐 먹지?

핸드폰에 말로 식재료를 등록·사용·정정하고 남은 재료로 메뉴를 정하는 Flutter 앱이다.
Android·iOS가 대상이며 주방 고정 태블릿의 백그라운드 상시 대기는 후속 범위다.
개발 9/28~9/30, 제출 9/30 18:00, 시연 10/2를 목표로 한다.

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
최신 목업의 목표는 “Hey Kitchen(헤이 키친)”과 Porcupine 영어 커스텀 호출어다. 현재 코드는
내장 반복 청취와 “자비스”를 사용하므로 R-02에서 교체·검증한다. Porcupine 키와 모델은 아직
현재 코드의 설치 요건이 아니며 목표 엔진을 연결할 때 설정·OS별 자산·런북을 함께 추가한다.

화면 범위는 스플래시·로그인·회원가입·권한·홈·듣기·질문·결과·냉장고·메뉴·기록·마이페이지다.
뭐 먹지?·냉장고·기록·마이페이지 네 탭을 사용한다. 계정 목표는 기존 식별 전용 서버와 구분한다.

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
동결 후 결정을 뒤집을 때 ADR을 작성한다. 없는 ADR 디렉터리를 현행 근거로 링크하지 않는다.

비밀값은 `.env`에만 둔다. `app/lib/data/`는 앱 소스이므로 반드시 커밋 대상에 포함한다.
`python3 scripts/check-repository.py`가 누락·무시된 소스와 깨진 상대 참조를 검사한다.
커밋 헤더는 `<type>(<scope>): <한글 명사형 subject>`이며 subject는 50자 이내다.
