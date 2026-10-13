import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("update_feed", pathlib.Path(__file__).with_name("update-feed.py"))
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)


class UpdateFeedTests(unittest.TestCase):
    def test_release_feed_rejects_wrong_build_download_or_missing_signature(self):
        manifest = {"version": "1.0.0", "build": "2", "artifacts": {
            "diskImage": {"name": "Sofla-1.0.0-arm64.dmg", "bytes": 123}}}
        xml = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:version>2</sparkle:version><sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
        <enclosure url="https://github.com/a-yunes/sofla/releases/download/v1.0.0/Sofla-1.0.0-arm64.dmg"
        length="123" sparkle:edSignature="test-signature" /></item></channel></rss>'''
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "appcast.xml"
            path.write_text(xml)
            self.assertEqual(feed.verify_item(path, manifest), "test-signature")
            for original, altered in [('>2<', '>1<'), ('v1.0.0/', 'v0.9.0/'),
                                      ('edSignature="test-signature"', 'edSignature=""'),
                                      ('length="123"', 'length="122"'), ('26.0', '27.0')]:
                path.write_text(xml.replace(original, altered))
                with self.subTest(altered=altered), self.assertRaises(ValueError):
                    feed.verify_item(path, manifest)
