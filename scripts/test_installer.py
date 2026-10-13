import copy
import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("installer", pathlib.Path(__file__).with_name("verify-installer.py"))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerLayoutTests(unittest.TestCase):
    def test_rejects_the_previous_unstyled_installer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / ".background.png").write_bytes(b"image")
            (root / "Applications").symlink_to("/Applications")
            (root / "Sofla.app/Contents").mkdir(parents=True)
            (root / "Sofla.app/Contents/Info.plist").write_bytes(b"plist")
            with self.assertRaisesRegex(ValueError, "Finder layout was not saved"):
                installer.require_contents(root)
            (root / ".DS_Store").write_bytes(b"\0\0\0\1Bud1" + bytes(32))
            installer.require_contents(root)
            (root / "Applications").unlink()
            (root / "Applications").symlink_to("/tmp")
            with self.assertRaisesRegex(ValueError, "Applications link"):
                installer.require_contents(root)

    def test_rejects_lost_background_and_rearranged_icons(self):
        records = {".": {
            "icvp": {"backgroundType": 2, "backgroundImageAlias": b".background.png",
                     "iconSize": 88, "textSize": 14, "arrangeBy": "none"},
            "bwsp": {"WindowBounds": "{{120, 120}, {660, 440}}"}},
            "Sofla.app": {"Iloc": (180, 220)}, "Applications": {"Iloc": (480, 220)}}
        installer.verify_layout(records)
        for group, key, value in [("icvp", "backgroundType", 0), ("icvp", "iconSize", 48),
                                  ("bwsp", "WindowBounds", "{{0, 0}, {920, 440}}")]:
            changed = copy.deepcopy(records)
            changed["."][group][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                installer.verify_layout(changed)
        records["Sofla.app"]["Iloc"] = (480, 220)
        with self.assertRaisesRegex(ValueError, "icon positions"):
            installer.verify_layout(records)
