import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("audit", pathlib.Path(__file__).with_name("audit-source.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class SourceExportTests(unittest.TestCase):
    def test_upstream_license_exception_requires_the_exact_reviewed_file(self):
        source = pathlib.Path(__file__).resolve().parent.parent / "LICENSE.sparkle"
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            path = root / "LICENSE.sparkle"
            path.write_bytes(source.read_bytes())
            self.assertEqual(audit.audit([path], root), [])
            path.write_bytes(source.read_bytes() + b"\nprivate" + b"@example.test")
            self.assertTrue(any("email address" in failure for failure in audit.audit([path], root)))

    def test_approved_creator_credit_does_not_allow_private_identifiers(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            path = root / "README.md"
            email = "private" + "@" + "example.test"
            authors = ("Aleksei Iunes\nPrivate Author\n" + email).encode()
            with patch.object(audit.subprocess, "check_output", return_value=authors):
                path.write_text("Created by Aleksei Iunes.\n")
                self.assertEqual(audit.audit([path], root), [])
                path.write_text("Private Author\n" + email)
                findings = audit.audit([path], root)
                self.assertTrue(any("local author identifier" in finding for finding in findings))
                self.assertTrue(any("email address" in finding for finding in findings))

    def test_export_excludes_history_build_output_and_local_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / "README.md").write_text("# Sofla\n")
            (root / "design.md").write_text("# Native design\n")
            for name in (".git", "build", "sofla-website"):
                (root / name).mkdir()
                (root / name / "private.txt").write_text("private")
            files = list(audit.source_files(root))
            self.assertEqual(files, [root / "README.md", root / "design.md"])
            output = root / "source.zip"
            audit.export(files, output, root)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.namelist(), ["sofla/README.md", "sofla/design.md"])
                self.assertEqual(archive.read("sofla/README.md"), b"# Sofla\n")
                self.assertEqual(archive.read("sofla/design.md"), b"# Native design\n")

    def test_rejects_home_paths_credentials_and_em_dashes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            path = root / "README.md"
            path.write_text("/" + "Users/fixture/project " + "ghp_" + "x" * 30 + "\u2014")
            self.assertEqual(len(audit.audit([path], root)), 3)

    def test_export_rejects_symlinks_and_unreviewed_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / "Sources").mkdir()
            path = root / "Sources" / "private.txt"
            path.write_text("private")
            with self.assertRaises(ValueError):
                list(audit.source_files(root))
            path.unlink()
            path.symlink_to(root / "missing")
            with self.assertRaises(ValueError):
                list(audit.source_files(root))
