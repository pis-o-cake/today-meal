#!/bin/sh
# 프로젝트 native 검증. server / android 중 존재하는 것만 실행한다.
#
# engsys 가 `commands.verify` 로 부르는 진입점이다. 실패하면 0 이 아닌 코드로 끝난다.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)

if [ -f "$root/server/pyproject.toml" ]; then
  echo "== server =="
  # 통합 테스트는 PostgreSQL 이 없으면 스스로 건너뛴다. 나머지는 DB 없이 돈다.
  ( cd "$root/server" && poetry run pytest -q && poetry run ruff check . )
fi

if [ -f "$root/android/gradlew" ]; then
  echo "== android =="
  # JAVA_HOME 이 없으면 Android Studio 의 JBR 을 쓴다. 별도 JDK 설치를 요구하지 않는다.
  if [ -z "$JAVA_HOME" ]; then
    for candidate in \
      "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
      "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    do
      if [ -x "$candidate/bin/java" ]; then
        JAVA_HOME="$candidate"
        export JAVA_HOME
        echo "using bundled JBR: $JAVA_HOME"
        break
      fi
    done
  fi
  if [ -z "$JAVA_HOME" ]; then
    echo "verify: JAVA_HOME is not set and no Android Studio JBR was found" >&2
    exit 1
  fi
  if [ -z "$ANDROID_HOME" ] && [ -d "$HOME/Library/Android/sdk" ]; then
    ANDROID_HOME="$HOME/Library/Android/sdk"
    export ANDROID_HOME
  fi
  ( cd "$root/android" && ./gradlew testDebugUnitTest --console=plain --quiet )
fi

echo "verify: done"
