#!/usr/bin/env python3
"""스테이징된 내용에서 비밀값을 찾는다.

`.gitignore` 는 "추적하지 않는다"만 보장한다. `git add -f`, 새 경로의 비밀 파일, 소스에
붙여넣은 키 문자열은 막지 못한다. 이 스캐너는 **실제로 커밋될 내용**을 본다.

판정을 둘로 나눈다. 제공자 접두사가 붙은 것은 확실하므로 바로 막는다. `key = value` 형태는
변수 참조와 구분할 수 없어, 값이 코드에서 값을 읽어오는 표현이면 통과시킨다 —
오탐이 나면 사람들이 `--no-verify` 를 쓰게 되고 그게 더 나쁘다.
"""

from __future__ import annotations

import re
import subprocess
import sys

# 파일 경로만으로 막는 것들.
SECRET_PATHS = (
    re.compile(r"(^|/)\.env(\.[^.]+)?$"),
    re.compile(r"(^|/)local\.properties$"),
    re.compile(r"\.(keystore|jks|p12|pem|key)$"),
    re.compile(r"(^|/)id_rsa"),
    re.compile(r"serviceAccount.*\.json$"),
)
ALLOWED_PATHS = (
    re.compile(r"\.(example|sample|template)$"),
    re.compile(r"(^|/)\.env\.example$"),
)

# 내용 검사에서 제외할 확장자. 바이너리와 사람이 읽는 문서.
SKIP_CONTENT = re.compile(
    r"\.(lock|jar|apk|aab|png|jpe?g|gif|webp|svg|ico|ttf|otf|woff2?|zip|md)$"
)
SKIP_EXACT = {".githooks/secret-scan.py", ".githooks/pre-commit"}

# 제공자 접두사. 이건 변수 참조일 수 없다.
CERTAIN = re.compile(
    r"AIza[0-9A-Za-z_-]{30,}"
    r"|\bAQ\.[A-Za-z0-9_-]{30,}"
    r"|\bsk-[A-Za-z0-9]{20,}"
    r"|\bghp_[A-Za-z0-9]{30,}"
    r"|\bxox[abpr]-[A-Za-z0-9-]{10,}"
    r"|-----BEGIN [A-Z ]*PRIVATE KEY-----"
)

# `이름 = 값` 형태. 값이 인용부호로 감싼 리터럴일 때만 본다.
ASSIGN = re.compile(
    r"""(?ix)
    \b(api[_-]?key|access[_-]?key|access[_-]?token|refresh[_-]?token
      |client[_-]?secret|secret[_-]?key|secret|password|passwd|passphrase)
    \s*[:=]\s*
    (?P<quote>['"])(?P<value>[^'"\n]{12,})(?P=quote)
    """
)

# 자리표시자와 예시. 실제 비밀값이 아니다.
#
# WARNING: 여기에 `\s*` 처럼 빈 문자열에 맞는 대안을 넣으면 모든 값이 자리표시자가 된다.
# 각 대안은 최소 한 글자를 요구해야 한다.
PLACEHOLDER = re.compile(
    r"(?i)^(x+$|\.+|change-?me|your[-_ ]|<|\$\{?[a-z_]|example|dummy|sample"
    r"|placeholder|redacted|\*+|todo|none|null)"
)


def is_placeholder(value: str) -> bool:
    """실제 비밀값이 아닌 자리표시자인지."""
    stripped = value.strip()
    if not stripped:
        return True
    return PLACEHOLDER.match(stripped) is not None


def staged_files() -> list[str]:
    out = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
        capture_output=True,
        text=True,
        check=True,
    )
    return [line for line in out.stdout.splitlines() if line]


def staged_content(path: str) -> str | None:
    out = subprocess.run(
        ["git", "show", f":{path}"], capture_output=True, text=True, check=False
    )
    return out.stdout if out.returncode == 0 else None


def findings(paths: list[str]) -> list[str]:
    problems: list[str] = []
    for path in paths:
        if any(allow.search(path) for allow in ALLOWED_PATHS):
            continue
        if any(bad.search(path) for bad in SECRET_PATHS):
            problems.append(f"비밀 파일이 스테이징됨: {path}")
            continue
        if path in SKIP_EXACT or SKIP_CONTENT.search(path):
            continue

        content = staged_content(path)
        if content is None:
            continue

        for number, line in enumerate(content.splitlines(), 1):
            if len(line) > 4000:
                continue
            if CERTAIN.search(line):
                problems.append(f"비밀값이 확실한 문자열: {path}:{number}")
                break
            match = ASSIGN.search(line)
            if match and not is_placeholder(match.group("value")):
                problems.append(f"비밀값으로 보이는 대입: {path}:{number}")
                break
    return problems


def main() -> int:
    paths = staged_files()
    if not paths:
        return 0
    problems = findings(paths)
    if not problems:
        return 0

    print("", file=sys.stderr)
    for problem in problems:
        print(f"pre-commit: {problem}", file=sys.stderr)
    print(
        "\n커밋을 중단했다. 비밀값은 커밋하지 않는다.\n"
        "\n  스테이징에서 빼기 : git restore --staged <경로>"
        "\n  무시 대상에 넣기  : .gitignore 에 추가"
        "\n  값을 파일로 옮기기: server/.env 또는 android/local.properties"
        "\n"
        "\n정말 비밀값이 아니면 그 줄을 고치거나 --no-verify 로 우회한다."
        "\n우회는 기록에 남지 않으므로 이유를 커밋 본문에 적는다.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
