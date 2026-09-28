---
type: guide
status: active
---

# 오늘 뭐 먹지?

**핸드폰에 말을 걸어** 냉장고를 관리하고, 남은 재료로 오늘의 메뉴를 정하는 가정용 AI 주방
도우미다. Flutter 하이브리드로 Android 와 iOS 에 같은 코드를 쓴다. 3일 해커톤 산출물이며 개발 9/28~9/30, 제출 9/30 18:00, 시연 10/2다.

> “헤이 냉장고, 두부 두 모 넣었어. 소비기한은 10월 3일이야.”

## 여기서 무엇을 먼저 읽는가

| 알고 싶은 것 | 문서 |
|---|---|
| 무엇을 만들고 어디까지 하면 완료인가 | [기능 범위](docs/scope/today-meal.md) |
| 어떤 구조로 만드는가 | [아키텍처](docs/architecture/README.md) |
| 왜 이 스택·모델·저장소를 골랐는가 | [기술 설계](docs/design/0001-mvp-technical-design.md) |
| 테이블과 컬럼이 어떻게 생겼는가 | [데이터 모델 설계](docs/design/0002-database.md) |
| 어떤 순서로 언제까지 만드는가 | [3일 실행 계획](docs/plan/hackathon-3day.md) |
| 설계 동결 뒤 무엇이 왜 바뀌었는가 | [ADR](docs/adr) — 설계가 `draft`인 동안은 비어 있다 |
| 어떻게 띄우고 막히면 어떻게 하는가 | [로컬 개발 런북](docs/runbook/local-development.md) |
| 제품 동작 정책의 상세 | [기획서](docs/product/proposal.md) |

코드를 고치기 전에 **기능 범위**에서 해당 기능의 완료 기준을 읽는다. API·데이터·화면 규칙이
바뀌면 **아키텍처**를 먼저 고친다.

문서의 역할은 셋으로 갈린다 — **설계**는 그때 왜 이렇게 정했는가, **아키텍처**는 지금 어떻게
되어 있는가, **ADR**은 설계가 동결된 뒤로 왜 바뀌었는가다. 설계가 `draft`인 동안 ADR을 쓰지
않는다.

## 구성

```
app/       Flutter 앱 (Dart · MVVM · Android + iOS)
server/    FastAPI (Poetry · Pydantic V2 · SQLAlchemy 2.0)
docs/      engineering-system이 관리하는 문서
scripts/   verify.sh — 양쪽 native 검증 진입점
```

주방 고정 태블릿의 상시 대기는 **후속 방향**이다. 그래서 화면을 핸드폰 세로 기준으로 만들되
태블릿 가로로 확장 가능하게 두고, Flutter 를 골라 프레임워크를 바꾸지 않고 이어갈 수 있게 했다.

API 문서는 서버의 Swagger UI(`/docs`)를 본다. 엔드포인트를 문서에 옮겨 적지 않는다.

## 개발 환경

전제는 Flutter SDK, Android Studio, Python 3.12, Poetry, Docker다. 실기기 확인이 필요하므로
핸드폰 한 대가 있어야 한다. iOS 빌드에는 Xcode 가 따로 필요하다.

**온디바이스 ASR 모델(134MB)은 git 에 없다.** 인코더가 126MB 로 GitHub 의 파일당 100MB
제한을 넘기 때문이다. clone 뒤 `scripts/fetch-model.sh` 로 한 번 받는다.

```sh
# 0) 처음 한 번 — 온디바이스 ASR 모델을 받는다 (134MB, git 에 없다)
sh scripts/fetch-model.sh

# 1) 로컬 스택 한 번에 — DB · 마이그레이션 · 시드 · LAN 주소 설정 · 서버
sh scripts/dev.sh

# 2) 앱
cd app && flutter pub get && flutter run

# 3) 양쪽 검증 (서버 122건 · 앱 27건)
sh scripts/verify.sh
```

Windows 는 **Git Bash** 에서 실행한다. PowerShell 과 CMD 는 sh 스크립트를 돌리지 못한다.

WARNING: 호스트에 이미 PostgreSQL 이 돌면 5432 가 겹친다. 컨테이너는 5433 으로 노출하며
자세한 대응은 [런북](docs/runbook/local-development.md)에 있다.

비밀값은 커밋하지 않는다. 서버는 `server/.env`, 앱의 Porcupine AccessKey와 서버 주소는
`app/.env`로 공급한다. 스테이징 내용은 `.githooks/pre-commit` 이 한 번 더 검사한다.

## 문서와 커밋 규약

문서 관리는 [engineering-system](https://github.com/pis-o-cake/engineering-system)의 계약을
따른다. 이 컴퓨터에서 한 번 활성화해야 검사가 돈다.

```sh
git clone https://github.com/pis-o-cake/engineering-system
cd engineering-system && ./install.sh
cd /path/to/today-meal && engsys setup
```

```sh
engsys docs check --project .    # 문서 구조 검사
engsys check --project .         # 계약 검사
```

커밋 헤더는 `<type>(<scope>): <subject>`이며 subject는 **한글 명사형 50자 이내**다. `commit-msg`
훅이 판정한다. 3일 일정을 고려해 `pre-push` 게이트는 켜지 않았다.
