#!/bin/sh
# 로컬 개발 스택을 한 번에 띄운다.
#
# 실기기가 붙어야 하므로 서버를 LAN 주소로 연다. `localhost` 로 열면 폰이 자기 자신을
# 가리켜 닿지 못한다.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)

# LAN 주소를 찾는다. 실기기가 붙어야 하므로 localhost 로는 안 된다.
lan=""
if command -v ipconfig >/dev/null 2>&1 && ipconfig getifaddr en0 >/dev/null 2>&1; then
  lan=$(ipconfig getifaddr en0)                       # macOS
elif command -v ipconfig >/dev/null 2>&1 && ipconfig getifaddr en1 >/dev/null 2>&1; then
  lan=$(ipconfig getifaddr en1)                       # macOS (보조 인터페이스)
elif command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
  lan=$(hostname -I | awk '{print $1}')               # Linux
elif command -v powershell.exe >/dev/null 2>&1; then
  # Windows Git Bash. 사설 대역의 첫 주소를 쓴다.
  lan=$(powershell.exe -NoProfile -Command \
    "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { \$_.IPAddress -like '192.168.*' -or \$_.IPAddress -like '10.*' } | Select-Object -First 1).IPAddress" \
    2>/dev/null | tr -d '\r\n ')
fi

if [ -z "$lan" ]; then
  echo "dev: LAN 주소를 찾지 못했다. 와이파이에 연결돼 있는지 보고, 안 되면" >&2
  echo "     app/.env 의 API_BASE_URL 을 손으로 적는다" >&2
  exit 1
fi

echo "== PostgreSQL =="
( cd "$root/server" && docker compose up -d db )
for i in $(seq 1 30); do
  ( cd "$root/server" && docker compose exec -T db pg_isready -U today_meal >/dev/null 2>&1 ) && break
  sleep 1
done

echo "== 마이그레이션과 시드 =="
( cd "$root/server" && poetry run alembic upgrade head >/dev/null )
( cd "$root/server" && poetry run python -m app.core.seed 2>&1 | grep -E "Seed complete" || true )

echo "== 앱 설정 =="
# 실기기가 붙을 주소로 맞춘다. 매번 손으로 고치면 빠뜨린다.
if [ ! -f "$root/app/.env" ] && [ -f "$root/app/.env.example" ]; then
  cp "$root/app/.env.example" "$root/app/.env"
  echo "  app/.env 를 example 에서 만들었다"
fi
if [ -f "$root/app/.env" ]; then
  tmp=$(mktemp)
  sed "s#^API_BASE_URL=.*#API_BASE_URL=http://$lan:8000/#" "$root/app/.env" > "$tmp"
  mv "$tmp" "$root/app/.env"
  echo "  app/.env → http://$lan:8000/"
fi

echo
echo "서버를 연다. 폰에서 붙을 주소는 http://$lan:8000/ 이다."
echo "  같은 와이파이에 있어야 한다."
echo "  앱 실행:  cd app && flutter run"
echo
# 0.0.0.0 으로 열어야 LAN 에서 닿는다.
cd "$root/server" && exec poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
