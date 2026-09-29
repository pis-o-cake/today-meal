---
type: runbook
status: active
last-reviewed: 2026-09-29
---

# 로컬 개발과 새 checkout 재현

새 checkout에서 앱·서버를 설치하고 실행·검증하는 절차와 실패 복구 방법을 정한다.

## 적용 상황

새 환경에서 서버·앱을 설치하거나 기동 실패를 복구할 때 사용한다. 저장소에 포함된 소스와
lock 파일로 실행하는 절차다. 배포 완료는 [V-12](../verification/mvp.md)의 별도 실기기 판정이다.

## 실행 전 확인

| 도구·조건 | 확인 |
|---|---|
| Python 3.12·Poetry | `python3.12 --version`, `poetry --version` |
| Docker | `docker info`. 로컬 PostgreSQL 16 사용 |
| Flutter·Dart | `flutter --version`, `flutter doctor`. pubspec의 SDK 제약 확인 |
| Android SDK·기기 | `flutter devices`, 한국어 인식·TTS·마이크 권한 |
| iOS | Xcode·서명·실기기. Android 검증으로 대신하지 않음 |
| Windows | sh 명령은 Git Bash에서 실행 |
| 실기기 통신 | 개발 머신과 같은 LAN, 방화벽·8000 포트 확인 |

Flutter가 PATH에 없으면 설치 위치의 `bin`을 PATH에 추가한다. 예를 들어 이 개발 머신의
SDK 위치는 `$HOME/dev/flutter/bin`일 수 있으나 팀 공통 설치 경로로 강제하지 않는다.
Porcupine AccessKey와 sherpa-onnx 모델은 필요하지 않다.

## 절차

### 1. 설정과 의존성

저장소 루트에서 시작한다. 기존 `.env`가 있으면 덮어쓰지 않는다.

```sh
cp server/.env.example server/.env
cp app/.env.example app/.env
cd server
poetry env use python3.12
poetry install
cd ../app
flutter pub get
cd ..
```

서버 `.env`의 DB 비밀번호를 설정한다. 실제 모델 시험에는 Gemini 키와 계정에서 접근 가능한
모델명을 설정한다. 키가 비어 있으면 Fake 경로가 선택되므로 실제 AI 평가로 기록하지 않는다.
의존성 변경 목적이 아니면 `poetry.lock`·`pubspec.lock`을 재생성하거나 업그레이드하지 않는다.

앱 `.env`에는 `API_BASE_URL`과 `WAKE_WORD_ENABLED`가 있다. URL 끝의 `/`를 유지한다.
`WAKE_WORD_ENABLED=false`면 호출 감지가 꺼지며 호출어 기능 완료 시험에 사용할 수 없다.
`.env`는 앱 자산으로 묶이므로 앱에 서버 비밀키를 넣지 않는다.

### 2. 개발 스택

```sh
sh scripts/dev.sh
```

이 명령은 DB 기동·준비 확인·마이그레이션·시드·앱 LAN 주소 설정 후 서버를 `0.0.0.0:8000`에 연다.
서버의 `.env`와 의존성을 먼저 준비해야 한다. LAN 자동 탐지가 잘못되면 수동 경로를 사용한다.

```sh
cd server
docker compose up -d db
poetry run alembic upgrade head
poetry run python -m app.core.seed
poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

기본 노출 DB 포트는 5433이며 컨테이너 내부는 5432다. 호스트의 기존 PostgreSQL을 종료하지 않는다.
시드는 기본 가구·재료 사전·기본 양념을 준비하며 사용자 재고 등록을 대신하지 않는다.

### 3. 앱

| 위치 | API_BASE_URL 예시 |
|---|---|
| Android 에뮬레이터 | `http://10.0.2.2:8000/` |
| iOS 시뮬레이터 | `http://localhost:8000/` |
| 실기기 | 개발 머신의 실제 LAN 주소 `http://<LAN-IP>:8000/` |

```sh
cd app
flutter run
```

실기기에서 `localhost`는 폰 자신이다. HTTP 개발 통신은 플랫폼 정책에 따라 차단될 수 있으므로
실제 응답으로 확인한다. 현재 debug 매니페스트의 INTERNET 권한만 보고 평문 허용이 있다고
가정하지 않는다. release 연결은 HTTPS 주소와 별도 설치 시험으로 확인한다.

### 4. 검증과 빌드

저장소 루트에서 실행한다.

```sh
python3 scripts/check-repository.py
sh scripts/verify.sh
engsys docs check --project .
```

새 소스가 아직 untracked면 재현성 검사는 실패한다. 해당 소스만 확인해 Git에 추가한 뒤 다시
검사한다. 모든 untracked 파일이나 `.env`를 일괄 추가하지 않는다.

```sh
cd app
flutter build apk --release
flutter build ios --release
```

iOS에는 Xcode·서명이 필요하다. 빌드 성공과 다른 기기 설치 성공을 분리해 기록한다.

## 성공 확인

`/health`, `/api/household/me`, `/api/ingredient?q=파`가 응답하는지 확인한다.
health만으로 DB·실제 모델·음성 왕복이 동작한다고 판정하지 않는다. 기기에서 등록·조회 후
DB와 화면 수량이 일치해야 한다. API 정본은 서버 개발 환경의 `/docs`다.

서버 테스트의 통과·실패·skip 수와 Flutter analyze/test 결과를 기록한다. 수량 테스트가
DB 부재로 skip되면 PostgreSQL을 준비해 재실행한다. 테스트 수를 문서에 고정된 합격 숫자로 두지 않는다.

새 checkout 검증에서는 커밋된 소스·lock·자산만으로 위 절차를 수행한다. `.env.example`에서
설정을 만들고 캐시·숨겨진 로컬 소스에 기대지 않는지 확인한다. 저장소 검사는 Dart 상대 import와
앱·서버 소스의 추적 여부를 먼저 확인하지만 실제 의존성 설치·빌드 시험을 대신하지 않는다.

## 실패와 복구

| 증상 | 확인과 복구 |
|---|---|
| DB role 없음/연결 실패 | 다른 PostgreSQL의 5432에 붙지 않았는지 `.env`의 포트·사용자·비밀번호 확인 |
| DB 준비 시간 초과 | `docker compose logs db` 확인. 준비 안 된 DB에 마이그레이션을 계속 실행하지 않음 |
| 통합 테스트 skip | DB 실행·접속값·환경변수 우선순위 확인. 비밀값을 로그에 출력하지 않음 |
| 앱 data import 없음 | `.gitignore`의 data 범위와 `git ls-files app/lib/data` 확인 |
| Flutter 없음/SDK 불일치 | 설치 경로·PATH·pubspec SDK 제약 확인. lock 무조건 삭제 금지 |
| .env asset 없음 | 앱 디렉터리에 example을 복사. 실제 값 커밋 금지 |
| 음성 불가 | 권한·한국어 인식/TTS·네트워크·전경 상태 확인. 코드의 Unavailable를 사용자 문구로 안내 |
| iOS 환경 불완전 | `flutter doctor`와 Xcode 첫 실행·서명 확인. 자동 완료로 기록하지 않음 |
| 실기기 서버 연결 거부 | LAN 주소·같은 네트워크·방화벽·바인딩 주소 확인 |
| 마이그레이션 오류 | 현재 revision·로그·DB 백업 확인 후 복구. 데이터 삭제를 기본 해법으로 사용하지 않음 |

개발 DB를 지우려면 대상이 폐기 가능한 테스트 DB인지 먼저 확인한다. 이 런북은 기존 DB 볼륨을
자동 삭제하지 않는다. 목업 열람의 Canvas 런타임 의존성은 [목업 인계](../../mockup/README.md)를 따른다.
