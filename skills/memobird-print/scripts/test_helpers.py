#!/usr/bin/env python3
"""Offline BMP invariants: row preservation, invalid headers, height guard and no overwrite."""
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('merge_printer_bmp.py')
spec = importlib.util.spec_from_file_location('merge', SCRIPT)
merge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge)

def bitmap(height, byte=0):
    head = bytearray(62)
    head[:2] = b'BM'
    for offset, value in [(2, 62 + 72 * height), (10, 62), (14, 40), (18, 576), (22, height), (34, 72 * height), (46, 2)]:
        struct.pack_into('<I', head, offset, value)
    struct.pack_into('<HH', head, 26, 1, 1)
    head[54:62] = bytes([255, 255, 255, 0, 0, 0, 0, 0])
    return bytes(head) + bytes([byte]) * (72 * height)

class BitmapTests(unittest.TestCase):
    def test_rows_and_headers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            a, b = bitmap(1600, 0x55), bitmap(230, 0xAA)
            (root/'a.bmp').write_bytes(a)
            (root/'b.bmp').write_bytes(b)
            cmd = [sys.executable, str(SCRIPT), '--output', str(root/'out.bmp'), str(root/'a.bmp'), str(root/'b.bmp')]
            subprocess.run(cmd, check=True, capture_output=True)
            result = (root/'out.bmp').read_bytes()
            self.assertEqual(merge.validate(result), 1830)
            self.assertEqual(result[62:], a[62:]+b[62:])
            self.assertNotEqual(subprocess.run(cmd, capture_output=True).returncode, 0)
            self.assertEqual((root/'out.bmp').read_bytes(), result)

    def test_rejects_invalid_headers(self):
        for offset in [0, 2, 10, 14, 18, 22, 26, 28, 30, 34, 46, 54]:
            value = bytearray(bitmap(1))
            value[offset] ^= 0x80
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                merge.validate(value)
        with self.assertRaises(ValueError):
            merge.validate(b'BM')

    def test_combined_height_guard(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'a.bmp').write_bytes(bitmap(2500))
            result = subprocess.run([sys.executable, str(SCRIPT), '--output', str(root/'out.bmp'), str(root/'a.bmp'), str(root/'a.bmp')], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root/'out.bmp').exists())

if __name__ == '__main__':
    unittest.main()
