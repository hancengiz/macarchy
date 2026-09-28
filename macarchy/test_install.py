import contextlib
import os
import io
from pathlib import Path
import tempfile
import tomllib
import unittest

from install import parse_identities, pick_identity


class InstallerTest(unittest.TestCase):
    def test_profiles_preserve_native_shortcuts(self):
        for leader in (False, True):
            with self.subTest(leader=leader):
                text = install.profile(leader)
                data = tomllib.loads(text)
                keys = data["mode"]["main"]["binding"]
                self.assertTrue(all(key == "f18" or key.startswith("alt-") for key in keys))
                for mode in data["mode"].values():
                    self.assertTrue(all("cmd" not in key.split("-") for key in mode["binding"]))
                self.assertNotIn("cmd-t", keys)
                self.assertNotIn("cmd-l", keys)
                self.assertNotIn("alt-esc", keys)
                self.assertEqual(data["mode"]["system"]["binding"]["alt-shift-esc"], "mode main")
                if not leader:
                    self.assertEqual(keys["alt-shift-esc"], "mode system")
                self.assertEqual(data["mode"]["macarchy-menu"]["binding"]["alt-space"], "mode main")
                self.assertEqual(data["default-root-container-layout"], "scrolling")
                if leader:
                    self.assertEqual(list(keys), ["f18"])
                    self.assertEqual(data["mode"]["macarchy"]["binding"]["esc"], "mode main")
                    self.assertEqual(data["mode"]["macarchy"]["binding"]["backspace"], ["mode main", "mode system"])
                    self.assertEqual(data["mode"]["macarchy"]["binding"]["space"], ["mode main", "mode macarchy-menu"],
                                     "Leader profile must still open the launcher")
                    self.assertIn("macarchy-menu", data["mode"])
                    self.assertIn("passthrough", data["mode"], "Leader transformation must keep the passthrough section")

    def test_install_and_restore_preserve_previous_files(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / ".macarchy.toml"
            config.write_text("# previous config\n")
            helper = home / ".config/macarchy"
            helper.mkdir(parents=True)
            (helper / "action").write_text("# previous helper\n")
            # --profile-only requires an already-installed fork marker
            installed = home / "Applications/macarchy.app/Contents/Helpers"
            installed.mkdir(parents=True)
            (installed / "macarchy").write_text("# cli\n")
            with patch.object(Path, "home", return_value=home), contextlib.redirect_stdout(io.StringIO()):
                with patch("sys.argv", ["install.py", "--profile-only"]):
                    install.main()
                self.assertIn("alt-t", config.read_text())
                backup = next((home / ".config/macarchy/backups").iterdir())
                with patch("sys.argv", ["install.py", "--restore", str(backup), "--dry-run"]):
                    install.main()
                self.assertIn("alt-t", config.read_text())
                with patch("sys.argv", ["install.py", "--restore", str(backup)]):
                    install.main()
                self.assertEqual(config.read_text(), "# previous config\n")
                self.assertEqual((helper / "action").read_text(), "# previous helper\n")
class ParseIdentitiesTest(unittest.TestCase):
    def test_parses_named_identities_and_ignores_summary(self):
        text = (
            '  1) 2F4E08830C57875E0D91064A8E4E812842C6777F "KiwiDesk Local Signing"\n'
            '  2) ABCDEF "Developer ID Application: Acme Inc (TEAM123)"\n'
            '     2 valid identities found.\n'
        )
        self.assertEqual(
            parse_identities(text),
            ["KiwiDesk Local Signing", "Developer ID Application: Acme Inc (TEAM123)"],
        )

    def test_empty_output(self):
        self.assertEqual(parse_identities(""), [])
        self.assertEqual(parse_identities("     0 valid identities found.\n"), [])


class PickIdentityTest(unittest.TestCase):
    def test_prefers_documented_convention_name(self):
        names = ["KiwiDesk Local Signing", "aerospace-codesign-certificate"]
        self.assertEqual(pick_identity(names), ("aerospace-codesign-certificate", "preferred"))

    def test_developer_id_over_arbitrary(self):
        names = ["KiwiDesk Local Signing", "Developer ID Application: Acme Inc (T)"]
        self.assertEqual(
            pick_identity(names),
            ("Developer ID Application: Acme Inc (T)", "developer-id"),
        )

    def test_first_named_fallback(self):
        self.assertEqual(pick_identity(["KiwiDesk Local Signing"]), ("KiwiDesk Local Signing", "named"))

    def test_adhoc_fallback(self):
        self.assertEqual(pick_identity([]), ("-", "adhoc"))

    def test_upgrade_preserves_custom_config_and_replaces_bundle_cleanly(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / ".macarchy.toml"
            original = '# custom\nscrolling-column-width = 0.72\n'
            config.write_text(original)
            helper = home / ".config/macarchy"
            helper.mkdir(parents=True)
            (helper / "HOTKEYS.txt").write_text("custom shortcuts")
            (helper / "menu.jsonc").write_text("custom menu")
            installed = home / "Applications/macarchy.app"
            installed.mkdir(parents=True)
            (installed / "obsolete-resource").write_text("old")
            built = home / "built/macarchy.app"
            built.mkdir(parents=True)
            (built / "new-resource").write_text("new")
            with patch.object(Path, "home", return_value=home), patch.object(install, "build_app", return_value=built), \
                    patch.object(install, "run"), patch.object(install, "supports_safe_restart", return_value=False), \
                    patch.dict(os.environ, {"XDG_CONFIG_HOME": str(home / ".config")}), \
                    patch("sys.argv", ["install.py", "--build"]), contextlib.redirect_stdout(io.StringIO()):
                install.main()
            self.assertEqual(config.read_text(), original)
            self.assertEqual((helper / "HOTKEYS.txt").read_text(), "custom shortcuts")
            self.assertEqual((helper / "menu.jsonc").read_text(), "custom menu")
            self.assertEqual((installed / "new-resource").read_text(), "new")
            self.assertFalse((installed / "obsolete-resource").exists())
            backup = next((helper / "backups").iterdir())
            self.assertEqual((backup / "macarchy.app/obsolete-resource").read_text(), "old")

    def test_failed_app_swap_restores_original_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            installed = root / "Applications/macarchy.app"
            installed.mkdir(parents=True)
            (installed / "executable").write_text("original")
            built = root / "built/macarchy.app"
            built.mkdir(parents=True)
            (built / "executable").write_text("replacement")
            backup = root / "backup"
            backup.mkdir()
            replace = os.replace

            def fail_replacement(source, destination):
                if Path(source).name == "macarchy.app" and Path(destination) == installed:
                    raise OSError("simulated replacement failure")
                return replace(source, destination)

            with patch.object(install, "run"), patch.object(install.os, "replace", side_effect=fail_replacement):
                with self.assertRaises(OSError):
                    install.install_app(built, installed, backup)
            self.assertEqual((installed / "executable").read_text(), "original")

    def test_failed_verification_leaves_original_bundle_in_place(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            installed = root / "Applications/macarchy.app"
            installed.mkdir(parents=True)
            (installed / "executable").write_text("original")
            built = root / "built/macarchy.app"
            built.mkdir(parents=True)
            backup = root / "backup"
            backup.mkdir()
            with patch.object(install, "run", side_effect=OSError("invalid signature")):
                with self.assertRaises(OSError):
                    install.install_app(built, installed, backup)
            self.assertEqual((installed / "executable").read_text(), "original")

    def test_upgrade_preserves_xdg_config_without_creating_ambiguous_dotfile(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            xdg = home / "custom-config"
            config = xdg / "macarchy/macarchy.toml"
            config.parent.mkdir(parents=True)
            config.write_text("# existing XDG configuration\n")
            (home / ".aerospace.toml").write_text("# legacy configuration\n")
            installed = home / "Applications/macarchy.app"
            installed.mkdir(parents=True)
            built = home / "built/macarchy.app"
            built.mkdir(parents=True)
            with patch.object(Path, "home", return_value=home), patch.object(install, "build_app", return_value=built), \
                    patch.object(install, "run"), patch.object(install, "supports_safe_restart", return_value=False), \
                    patch.dict(os.environ, {"XDG_CONFIG_HOME": str(xdg)}), \
                    patch("sys.argv", ["install.py", "--build"]), contextlib.redirect_stdout(io.StringIO()):
                install.main()
            self.assertEqual(config.read_text(), "# existing XDG configuration\n")
            self.assertFalse((home / ".macarchy.toml").exists())


if __name__ == "__main__":
    unittest.main()
