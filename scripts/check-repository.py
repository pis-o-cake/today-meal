#!/usr/bin/env python3
"""Check that runtime sources and Flutter references survive a Git checkout."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


def check(root: Path) -> list[str]:
    tracked = set(
        subprocess.check_output(
            ["git", "ls-files", "-z"], cwd=root
        ).decode().split("\0")
    )
    errors: set[str] = set()

    def require(path: Path) -> None:
        try:
            relative = path.resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            errors.add(f"Reference outside repository: {path}")
            return
        if not path.is_file():
            errors.add(f"Missing file: {relative}")
        elif relative not in tracked:
            errors.add(f"Source or asset is not tracked by Git: {relative}")

    for directory, extension in (("app/lib", "*.dart"), ("server/app", "*.py")):
        for source in (root / directory).rglob(extension):
            require(source)

    # Import/export/part targets also catch omissions in a clean checkout, where
    # the missing source itself is no longer available for the scan above.
    directives = re.compile(
        r"^\s*(?:import|export|part)\s+(?!of\b)([^;]+);", re.MULTILINE
    )
    for source in (root / "app/lib").rglob("*.dart"):
        for directive in directives.findall(source.read_text()):
            for reference in re.findall(r"['\"]([^'\"]+)['\"]", directive):
                if reference.startswith("package:today_meal/"):
                    require(root / "app/lib" / reference.split("/", 1)[1])
                elif not re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", reference):
                    require(source.parent / reference)

    for relative in (
        "app/pubspec.yaml", "app/pubspec.lock", "app/.env.example",
        "server/pyproject.toml", "server/poetry.lock", "server/.env.example",
    ):
        require(root / relative)

    pubspec = root / "app/pubspec.yaml"
    if pubspec.is_file():
        # This project's assets are paths on YAML list lines (including fonts).
        # .env is deliberately generated from .env.example and never tracked.
        paths = re.findall(
            r"^\s*-\s+(?:asset:\s*)?([\w./-]+)\s*(?:#.*)?$",
            pubspec.read_text(), re.MULTILINE,
        )
        for reference in paths:
            if reference == ".env":
                continue
            asset = root / "app" / reference
            if reference.endswith("/") and asset.is_dir():
                for child in asset.rglob("*"):
                    if child.is_file():
                        require(child)
            else:
                require(asset)
    return sorted(errors)


if __name__ == "__main__":
    problems = check(Path(__file__).resolve().parent.parent)
    for problem in problems:
        print(f"repository: {problem}", file=sys.stderr)
    if problems:
        sys.exit(1)
    print("repository: runtime sources, Dart references, locks and assets are tracked")
