---
type: guide
status: active
---

# 개발 작업 기준

현재 목업을 기준으로 기능을 구현한다. 화면을 새로 설계하거나 기존 기능을 임의로 축소하지 않는다.

작업 전 아래 순서로 읽는다.

1. [기능 범위](docs/scope/today-meal.md): 해당 F-ID와 완료 기준.
2. [제품 정책](docs/product/proposal.md): 저장·질문·취소의 의미.
3. [목업 인계](mockup/README.md)와 [UI 계약](docs/ui/mobile.md): 해당 화면과 상태.
4. [아키텍처](docs/architecture/README.md): 구현 경계와 현재 API.
5. [작업표](docs/plan/hackathon-3day.md): 구현 차이와 다음 작업.

[기능 개발 절차](docs/runbook/feature-development.md)를 따른다. 구현 전에 F-ID, 사용자 흐름,
화면 ID, 필요한 API 데이터, 실패·복구 경로, 검증 항목을 연결한다. 문서와 코드가 다르면 코드를
정답으로 간주해 요구를 바꾸지 말고 작업표의 차이를 해소한다.

시각 기준은 `mockup/canvas/`의 화면 HTML이다. 캐릭터는 `Mascot2`이며 듣기·확인·반영 모두 냉장고 캐릭터와 단계 막대를 사용한다.
`Neuron`, `mockup/index.html`, 캐릭터 시안 1·3은 이전 비교 자료다.
캔버스 메모가 화면 HTML과 다르면 [목업 인계](mockup/README.md)의 해석을 따른다.

목업의 예시 날짜·재고·퍼센트를 실데이터로 하드코딩하지 않는다. 목업에 없는 상태는 UI 계약의
보완 규칙을 적용한다. 새 제품 정책이나 화면 재설계가 필요할 때만 사용자 판단을 요청한다.
현재 요청으로 허용된 수정이나 일반 구현 선택에 승인을 반복해서 묻지 않는다.
새 시안의 5개 탭·16화면·계정 화면·헤이 키친을 이전 탭 구성이나 식별 전용 정책으로 되돌리지 않는다.
화면 ID는 [기능 범위](docs/scope/today-meal.md)의 UI-01~16이 정본이며 폐기된 UI-00~11 번호를 쓰지 않는다.
현재 구현과 목표의 차이는 작업표에 남기며 미연동 로그인이나 호출 감지를 성공으로 표시하지 않는다.

다른 작업자의 미커밋 변경을 보존한다. `git diff`로 작업 시작 상태를 확인하고 맡은 파일만 수정한다.
앱 소스·자산이 Git에서 빠지지 않도록 `python3 scripts/check-repository.py`를 실행한다.
완료 검증의 진입점은 `sh scripts/verify.sh`다. 실기기 검증 전에는 기능 완료로 기록하지 않는다.
문서 변경에는 engineering-system의 문서 작성·개별 편집 검토 규칙을 적용한다.
