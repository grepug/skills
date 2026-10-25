#!/usr/bin/env python3
"""Merge printer-native top-first 1-bit BMP stripes without printing or changing pixel rows."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

def validate(blob):
    if len(blob) < 62:
        raise ValueError('BMP shorter than header')
    u32 = lambda off: struct.unpack_from('<I', blob, off)[0]
    u16 = lambda off: struct.unpack_from('<H', blob, off)[0]
    width, height = struct.unpack_from('<ii', blob, 18)
    if not (blob[:2] == b'BM' and u32(2) == len(blob) and u32(10) == 62 and u32(14) == 40
            and width == 576 and 1 <= height <= 4000 and u16(26) == 1 and u16(28) == 1
            and u32(30) == 0 and u32(46) in (0, 2) and blob[54:62] == bytes([255,255,255,0,0,0,0,0])
            and u32(34) == 72 * height and len(blob) == 62 + 72 * height):
        raise ValueError('Expected printer-native 576-dot top-first 1-bit BMP, height 1..4000')
    return height

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('inputs', nargs='+', type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('Output already exists; choose a new output path')
    blobs = [p.read_bytes() for p in args.inputs]
    heights = [validate(b) for b in blobs]
    height = sum(heights)
    if height > 4000:
        raise ValueError('Combined height exceeds software guard 4000; hardware height limit is unverified')
    pixels = b''.join(b[62:] for b in blobs)
    header = bytearray(blobs[0][:62])
    struct.pack_into('<I', header, 2, 62 + len(pixels))
    struct.pack_into('<i', header, 22, height)
    struct.pack_into('<I', header, 34, len(pixels))
    result = bytes(header) + pixels
    validate(result)
    with args.output.open('xb') as target:
        target.write(result)
    print(json.dumps({'output':str(args.output),'width':576,'height':height,'sha256':hashlib.sha256(result).hexdigest(),
                      'rowsPreserved':True,'printed':False,'hardwareLimitVerified':False}, ensure_ascii=False))

if __name__ == '__main__':
    main()
