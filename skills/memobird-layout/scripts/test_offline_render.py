#!/usr/bin/env python3
"""Check local-only resource validation before a renderer can run."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('offline', Path(__file__).with_name('offline_render.py'))
offline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(offline)

class ResourceTests(unittest.TestCase):
    def test_network_references_rejected(self):
        for text in ['![x](https://example.invalid/a.png)', '<img src="//example.invalid/a.png">',
                     'a{background:url(//example.invalid/a.png)}', '@import "//example.invalid/a.css"']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                offline.local_text(text)

    def test_local_markup_accepted(self):
        self.assertEqual(offline.local_text('<img src="images/a.png">'), '<img src="images/a.png">')

    def test_symlink_and_remote_css_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'a.css').write_text('@import "https://example.invalid/a.css";')
            with self.assertRaises(ValueError):
                offline.resource(root/'a.css', 'a.css')
            (root/'b.css').symlink_to(root/'a.css')
            with self.assertRaises(ValueError):
                offline.resource(root/'b.css', 'b.css')

if __name__ == '__main__':
    unittest.main()
