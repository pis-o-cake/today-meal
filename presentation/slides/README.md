# 발표 슬라이드

9장 웹 슬라이드. 서버·CDN·네트워크 없이 `index.html`을 더블클릭해서 연다. 내용 기준은 [발표 스토리보드](../storyboard.md).

## 구성

| 파일 | 내용 |
|---|---|
| `index.html` | 청중 화면. CSS·JS·교체 값을 모두 포함 |
| `presenter.html` | 발표자 창(대본·노트·시간). 청중 화면에서 `P`로 연다 |
| `assets/fonts/` | Pretendard |
| `assets/img/home-*.png` | 3장 실제 앱 홈 화면(10/1 실기기 녹화에서 추출) |
| `assets/img/rec-*.png`, `menu-list.png`, `cook-timer.png` | 4·5장 실제 앱 화면 |
| `assets/video/demo.mp4` | 6장 시연 영상 = `demo/final/voiceover/today-meal-90s-v4-ai-voice-leda.mp4` 복사본 |

시연 영상은 6장에서 Space로 무대 가득 재생한다. 재생이 막히면 같은 파일을 플레이어로 전체 화면 재생한다.

## 발표 순서

1. `index.html` 더블클릭 → `F` 전체 화면.
2. 필요하면 `P`로 발표자 창을 열어 다른 화면에 둔다.
3. 6장 "실제 앱 시연"에서 한 문장 말한 뒤 Space로 영상을 재생한다. 끝나면 `→`로 7장.
4. 누를 키와 시점은 발표자 창 대본의 녹색 키 줄을 따른다.

## 키

| 키 | 동작 |
|---|---|
| → / ← | 다음·이전 장 (← 는 그 장의 마지막 단계로) |
| Space | 다음 단계, 마지막 단계면 다음 장 |
| Shift+Space | 이전 단계 |
| PageDown·↓ / PageUp·↑ | Space / 이전 단계 (리모컨) |
| 1~9, Home, End | 직접 이동 |

주소의 `#3.1`은 3장 1단계로 이동한다. 새로고침하면 항상 1장부터 시작한다.

## 웹 배포

`python3 build_deck.py` 로 `server/app/deck/` 을 만든다(이미지·폰트 인라인). 서버가 `/deck` 으로 싣고,
Cloudflare 공유는 `cloudflare/` 에서 `npx wrangler deploy`.

문구를 바꾸면 `python3 ../subset_font.py .` 로 글꼴 서브셋을 다시 만든다(fonttools 필요).
