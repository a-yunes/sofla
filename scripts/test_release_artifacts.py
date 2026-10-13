import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("release_artifacts", pathlib.Path(__file__).with_name("release-artifacts.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseMetadataTests(unittest.TestCase):
    def metadata(self):
        return {"CFBundleIdentifier": "app.sofla.launcher", "CFBundleExecutable": "AppLauncher",
                "CFBundleShortVersionString": "1.0", "LSMinimumSystemVersion": "26.0"}

    def test_rejects_incompatible_binary_even_when_plist_claims_support(self):
        with self.assertRaises(ValueError):
            release.validate_metadata(self.metadata(), ["arm64"], "27.0")
        with self.assertRaises(ValueError):
            release.validate_metadata(self.metadata(), ["x86_64"], "26.0")
        self.assertEqual(release.validate_metadata(self.metadata(), ["arm64"], "26.0"), "1.0")

    def test_rejects_wrong_app_and_unsafe_version(self):
        for key, value in [("CFBundleIdentifier", "another.app"),
                           ("CFBundleExecutable", "Other"),
                           ("CFBundleShortVersionString", "../1.0")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                release.validate_metadata(self.metadata() | {key: value}, ["arm64"], "26.0")

    def test_checksum_records_no_local_paths_and_detects_changed_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "Sofla.dmg"
            path.write_bytes(b"first")
            first = release.file_record(path)
            path.write_bytes(b"second")
            self.assertEqual(first["name"], "Sofla.dmg")
            self.assertEqual(first["bytes"], 5)
            self.assertNotEqual(first["sha256"], release.file_record(path)["sha256"])
