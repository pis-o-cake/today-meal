"""Regression tests for local files silently omitted from a checkout."""

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "repository_check", Path(__file__).with_name("check-repository.py")
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RepositoryCheckTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        for path in (
            "app/pubspec.yaml", "app/pubspec.lock", "app/.env.example",
            "server/pyproject.toml", "server/poetry.lock", "server/.env.example",
        ):
            self.write(path, "")
        self.write("app/lib/main.dart", "import 'data/remote.dart';\n")
        self.write("app/lib/data/remote.dart", "")
        self.stage()

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def stage(self):
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)

    def test_complete_sources_pass_without_private_env(self):
        self.assertEqual(module.check(self.root), [])

    def test_ignored_runtime_source_fails(self):
        self.write(".gitignore", "data/\n")
        self.write("app/lib/data/hidden.dart", "")
        self.assertTrue(any("hidden.dart" in e for e in module.check(self.root)))

    def test_clean_checkout_with_missing_import_fails(self):
        (self.root / "app/lib/data/remote.dart").unlink()
        self.assertTrue(any("Missing file: app/lib/data/remote.dart" == e
                            for e in module.check(self.root)))

    def test_untracked_asset_fails(self):
        self.write("app/pubspec.yaml", "flutter:\n  assets:\n    - assets/icon.svg\n")
        self.write("app/assets/icon.svg", "<svg/>\n")
        self.assertTrue(any("not tracked" in e and "icon.svg" in e
                            for e in module.check(self.root)))

    def test_missing_package_local_export_fails(self):
        self.write("app/lib/main.dart", "export 'package:today_meal/missing.dart';\n")
        self.assertTrue(any("missing.dart" in e for e in module.check(self.root)))

    def test_generated_env_is_exempt_but_font_is_checked(self):
        self.write("app/pubspec.yaml", "flutter:\n  assets:\n    - .env\n"
                   "  fonts:\n    - family: Pretendard\n      fonts:\n"
                   "        - asset: assets/font.ttf\n")
        self.assertEqual(module.check(self.root), ["Missing file: app/assets/font.ttf"])


if __name__ == "__main__":
    unittest.main()
