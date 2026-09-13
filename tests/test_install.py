import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("installer", Path(__file__).resolve().parents[1] / "scripts/install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source, self.target, self.backups = root / "source", root / "live/skill", root / "backups"
        self.source.mkdir()
        (self.source / "SKILL.md").write_text("new skill\n")

    def install(self, apply=True):
        return installer.install_one(self.source, self.target, self.backups, apply)

    def test_dry_run_does_not_create_target(self):
        self.assertEqual(self.install(False)["action"], "install")
        self.assertFalse(self.target.exists())

    def test_backup_and_idempotence(self):
        self.target.mkdir(parents=True)
        (self.target / "local.txt").write_text("preserve my local work")
        result = self.install()
        self.assertEqual((Path(result["backup"]) / "local.txt").read_text(), "preserve my local work")
        self.assertEqual(installer.files(self.source), installer.files(self.target))
        self.assertEqual(self.install()["action"], "unchanged")

    def test_generated_assets_excluded(self):
        (self.source / "node_modules").mkdir()
        (self.source / "node_modules/module.js").write_text("dependency")
        (self.source / "preview.wav").write_bytes(b"audio")
        (self.source / ".env").write_text("LOCAL_SETTING=local-only")
        self.install()
        self.assertEqual(set(installer.files(self.target)), {"SKILL.md"})

    def test_symlink_refused(self):
        (self.source / "external").symlink_to(self.backups)
        with self.assertRaises(ValueError):
            self.install()
        self.assertFalse(self.target.exists())

    def test_reinstall_repairs_executable_mode(self):
        script = self.source / "start.sh"
        script.write_text("#!/bin/sh\nexit 0\n")
        script.chmod(0o755)
        self.install()
        (self.target / "start.sh").chmod(0o644)
        result = self.install()
        self.assertEqual(result["action"], "update")
        self.assertEqual((self.target / "start.sh").stat().st_mode & 0o111, 0o111)
        self.assertEqual((Path(result["backup"]) / "start.sh").stat().st_mode & 0o111, 0)

    def test_restore_after_replace_failure(self):
        self.target.mkdir(parents=True)
        (self.target / "SKILL.md").write_text("old skill\n")
        with patch.object(installer.os, "replace", side_effect=OSError("simulated failure")):
            with self.assertRaises(OSError):
                self.install()
        self.assertEqual((self.target / "SKILL.md").read_text(), "old skill\n")


if __name__ == "__main__":
    unittest.main()
