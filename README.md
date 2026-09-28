---
type: guide
status: active
---

# 오늘 뭐 먹지?

주방에 고정한 안드로이드 태블릿에 말을 걸어 냉장고를 관리하고, 남은 재료로 오늘의 메뉴를 정하는
가정용 AI 주방 도우미다. 3일 해커톤 산출물이며 개발 9/28~9/30, 제출 9/30 18:00, 시연 10/2다.

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
android/   Android 앱 (Kotlin · Compose · MVVM · Hilt)
server/    FastAPI (Poetry · Pydantic V2 · SQLAlchemy 2.0)
docs/      engineering-system이 관리하는 문서
scripts/   verify.sh — 양쪽 native 검증 진입점
```

API 문서는 서버의 Swagger UI(`/docs`)를 본다. 엔드포인트를 문서에 옮겨 적지 않는다.

## 개발 환경

전제는 Android Studio, JDK 17, Python 3.12, Poetry, Docker다. 실기기 확인이 필요하므로 안드로이드
태블릿 한 대가 있어야 한다.

```sh
# 서버 — 전체 절차는 런북 참조
cd server && poetry install && docker compose up -d db
poetry run alembic upgrade head && poetry run python -m app.core.seed
poetry run uvicorn app.main:app --reload --port 8000

# 앱
cd android && ./gradlew :app:assembleDebug

# 양쪽 검증 (서버 59건 · 앱 5건)
sh scripts/verify.sh
```

WARNING: 호스트에 이미 PostgreSQL 이 돌면 5432 가 겹친다. 컨테이너는 5433 으로 노출하며
자세한 대응은 [런북](docs/runbook/local-development.md)에 있다.

비밀값은 커밋하지 않는다. 서버는 `server/.env`, 앱의 Porcupine AccessKey는
`android/local.properties`로 공급한다.

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

커밋 헤더는 `<type>(<scope>): <subject>`이며 subject는 영문 명령형 50자 이내다. `commit-msg`
훅이 판정한다. 3일 일정을 고려해 `pre-push` 게이트는 켜지 않았다.
