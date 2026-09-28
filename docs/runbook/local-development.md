---
type: runbook
status: active
last-reviewed: 2026-09-28
---

# 로컬 개발 환경 기동

서버와 앱을 이 컴퓨터에서 처음 돌릴 때까지의 절차다. 3일 일정이라 **막히는 지점을 미리 적어
두는 것**이 이 문서의 목적이다. 구조는 [아키텍처](../architecture/README.md), 기술 선택 근거는
[기술 설계](../design/0001-mvp-technical-design.md)가 갖는다.

## 적용 상황

새 컴퓨터에서 개발을 시작할 때, 또는 기동이 실패해 원인을 찾을 때 쓴다. 개발서버 배포와 APK
배포는 이 문서 범위가 아니다 — S-10 에서 따로 적는다.

전제는 다음 넷이다.

| 도구 | 확인 |
|---|---|
| Python 3.12 | `python3.12 --version`. Homebrew 라면 `/opt/homebrew/opt/python@3.12/bin/python3.12` |
| Poetry 2.x | `poetry --version`. `poetry export` 는 없으므로 쓰지 않는다 |
| Docker | `docker info`. PostgreSQL 컨테이너에 필요하다 |
| Flutter SDK | `flutter --version`. `flutter doctor` 로 Android toolchain 을 확인한다 |
| Git Bash (Windows) | sh 스크립트가 Git Bash 에서만 돈다. PowerShell·CMD 는 실행하지 못한다 |
| Android Studio | Android SDK 와 번들 JBR 을 제공한다 |
| Xcode | **iOS 빌드에만 필요하다.** 없으면 Android 만 낸다 |

## 실행 전 확인

**호스트의 5432 포트를 이미 쓰고 있는지 본다.** 이것이 가장 흔한 실패 원인이다.

```sh
lsof -nP -iTCP:5432 -sTCP:LISTEN
brew services list | grep postgres
```

Homebrew PostgreSQL 이 돌고 있으면 `localhost:5432` 는 그쪽으로 붙는다. 컨테이너는 기본
**5433** 으로 노출하며 `.env` 의 `TODAY_MEAL_DB_PORT` 도 5433 이다. 컨테이너끼리는 항상
`db:5432` 를 쓴다. 이미 돌던 PostgreSQL 을 끄지 않아도 된다.

## 절차

### 1. 서버

```sh
cd server
cp .env.example .env          # TODAY_MEAL_DB_PASSWORD 를 채운다
poetry env use /opt/homebrew/opt/python@3.12/bin/python3.12
poetry install

docker compose up -d db
poetry run alembic upgrade head
poetry run python -m app.core.seed
poetry run uvicorn app.main:app --reload --port 8000
```

`seed` 는 멱등이다. 기본 가구 하나와 재료 사전 32건, 기본 양념 10건을 넣는다. 재고는 넣지
않는다 — 재고는 음성으로 등록하는 것이 제품이다.

### 2. 앱

```sh
cd app
cp .env.example .env            # PORCUPINE_ACCESS_KEY 와 API_BASE_URL 을 채운다
flutter pub get
flutter devices                 # 붙은 기기 확인
flutter run                     # 디버그 실행
```

`.env` 의 `API_BASE_URL` 이 앱이 붙을 서버다. **끝에 슬래시를 붙인다.**

| 실행 위치 | 주소 |
|---|---|
| Android 에뮬레이터 | `http://10.0.2.2:8000/` |
| iOS 시뮬레이터 | `http://localhost:8000/` |
| 실기기 | 개발 머신의 LAN 주소. 같은 와이파이에 있어야 한다 |

릴리스 빌드는 이렇게 만든다.

```sh
flutter build apk --release      # Android
flutter build ios --release      # iOS. Xcode 가 있어야 한다
```

### 2-1. 실기기에 붙이기

폰이 붙으려면 서버가 **LAN 주소**로 열려야 한다. `localhost` 로 열면 폰이 자기 자신을
가리켜 닿지 못한다. 아래 한 줄이 DB·마이그레이션·시드·주소 설정까지 한다.

```sh
sh scripts/dev.sh
```

이 스크립트는 LAN 주소를 찾아 `app/.env` 의 `API_BASE_URL` 을 고치고 서버를 `0.0.0.0`
으로 연다. 폰과 개발 머신이 **같은 와이파이**에 있어야 한다.

### 3. 양쪽 검증

```sh
sh scripts/verify.sh
```

## 성공 확인

서버가 떴으면 다음 셋이 응답해야 한다.

```sh
curl -s localhost:8000/health
curl -s localhost:8000/api/household/me
curl -s "localhost:8000/api/ingredient?q=파"
```

기대값은 이렇다.

| 확인 | 기대 |
|---|---|
| `/health` | `{"status":"ok", ...}`. DB 없이도 응답한다 |
| `/api/household/me` | `household_id` 가 **1**. 헤더 없이 기본 가구로 처리된다 |
| `/api/ingredient?q=파` | `대파`(별칭 매칭)와 `양파`(이름 매칭) |
| 테이블 수 | 14개. `alembic_version` 은 별도 |
| 미구현 엔드포인트 | 501 과 담당 슬라이스 ID. 빈 성공 응답이 아니다 |

테이블 수는 이렇게 센다.

```sh
docker compose exec -T db psql -U today_meal -d today_meal -tAc \
  "select count(*) from pg_tables where schemaname='public' and tablename<>'alembic_version'"
```

`scripts/verify.sh` 는 서버 109건과 앱 테스트를 통과해야 한다. PostgreSQL 이 없으면 서버의 통합
테스트 10건이 **건너뛰어진다** — 통과가 아니라 건너뛴 것이므로 출력의 `skipped` 수를 본다.

## 실패와 복구

| 증상 | 원인 | 조치 |
|---|---|---|
| `role "today_meal" does not exist` | 호스트의 다른 PostgreSQL 에 붙었다 | `.env` 의 `TODAY_MEAL_DB_PORT` 를 5433 으로 두고 컨테이너 포트를 확인 |
| `greenlet library is required` | SQLAlchemy async 의 전이 의존이 빠졌다 | `poetry install` 재실행. `greenlet` 은 명시 의존이다 |
| 통합 테스트가 조용히 전부 skip | 환경변수가 `.env` 를 덮었다 | 셸의 `TODAY_MEAL_DB_*` 를 지운다. 환경변수가 `.env` 보다 우선한다 |
| `alembic` 이 모델을 못 찾음 | 도메인이 `models.py` 를 갖지 않는다 | `app/domain/<name>/models.py` 를 만든다. `env.py` 는 고치지 않는다 |
| `flutter: command not found` | Flutter 가 PATH 에 없다 | `brew install --cask flutter` 후 새 터미널을 연다 |
| `flutter doctor` 가 Android toolchain 실패 | SDK 라이선스 미동의 | `flutter doctor --android-licenses` 를 실행한다 |
| iOS 빌드가 시작조차 안 됨 | **Xcode 가 없거나 첫 실행 구성요소가 빠졌다** | `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` · `sudo xcodebuild -license accept` · `sudo xcodebuild -runFirstLaunch` 를 차례로 실행한다 |
| Windows 에서 sh 스크립트가 안 돎 | PowerShell·CMD 로 실행했다 | **Git Bash** 를 연다. 경로는 `D:\work` 가 아니라 `/d/work` 형식을 쓴다 |
| Windows 에서 `invalid profile name` 류 오류 | CRLF 로 체크아웃됐다 | `.gitattributes` 가 LF 로 고정한다. 기존 checkout 이면 다시 clone 하거나 해당 파일을 LF 로 저장한다 |
| 앱이 `Connection refused` | 실기기가 `localhost` 를 자기 자신으로 본다 | `.env` 의 `API_BASE_URL` 을 개발 머신의 LAN 주소로 바꾼다 |
| `porcupine.accessKey is missing` | AccessKey 가 없다 | `local.properties` 에 채운다. 커밋하지 않는다 |
| 앱이 서버에 못 붙음 (`CLEARTEXT`) | 릴리스 빌드로 http 에 붙었다 | 디버그 빌드를 쓴다. 평문 허용은 디버그 매니페스트에만 있다 |
| 마이그레이션이 절반만 적용 | DDL 트랜잭션 중단 | `alembic downgrade base` 후 `upgrade head`. 개발 DB 라 데이터 손실을 허용한다 |

컨테이너를 완전히 지우고 다시 시작하려면 다음을 쓴다. **볼륨이 지워지므로 개발 DB 의 데이터가
사라진다.**

```sh
cd server && docker compose down -v && docker compose up -d db
poetry run alembic upgrade head && poetry run python -m app.core.seed
```
