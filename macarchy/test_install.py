import contextlib
import io
from pathlib import Path
import tempfile
import tomllib
import unittest
from unittest.mock import patch

import install


class InstallerTest(unittest.TestCase):
    def test_profiles_preserve_native_shortcuts(self):
        for stock in (False, True):
            for leader in (False, True):
                with self.subTest(stock=stock, leader=leader):
                    text = install.profile(stock, leader)
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
                    if stock:
                        self.assertNotIn("scrolling-column-width", data)
                        self.assertEqual(data["default-root-container-layout"], "tiles")
                        self.assertNotIn("macarchy-menu", text, "Stock must not reference the fork-only launcher mode")
                        self.assertNotIn("macarchy-menu", data["mode"])
                    if not stock:
                        self.assertEqual(data["mode"]["macarchy-menu"]["binding"]["alt-space"], "mode main")
                    if leader:
                        self.assertEqual(list(keys), ["f18"])
                        self.assertEqual(data["mode"]["macarchy"]["binding"]["esc"], "mode main")
                        self.assertEqual(data["mode"]["macarchy"]["binding"]["backspace"], ["mode main", "mode system"])
                        if not stock:
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
            with patch.object(Path, "home", return_value=home), contextlib.redirect_stdout(io.StringIO()):
                with patch("sys.argv", ["install.py", "--stock"]):
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


if __name__ == "__main__":
    unittest.main()
