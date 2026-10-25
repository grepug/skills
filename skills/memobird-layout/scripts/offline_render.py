#!/usr/bin/env python3
"""Render local documents with MemobirdRenderer; never contact the printing service."""
import argparse
import base64
import json
import mimetypes
from pathlib import Path
import re
import subprocess

EXTENSIONS = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg', '.css', '.ttf', '.otf', '.ttc', '.woff', '.woff2'}

def local_text(text):
    # Reject network references in supported markup/CSS. This is input hygiene,
    # not an OS network sandbox; use trusted local resources for offline previews.
    if re.search(r'(?:https?|ftp)\s*:|(?:src\s*=\s*[\"\']?|url\(\s*[\"\']?|@import\s*[\"\'])//', text, re.I):
        raise ValueError('Offline preview requires local resources; remove network URLs')
    return text

def resource(path, name):
    if path.is_symlink():
        raise ValueError('Symlink resources are not supported')
    data = path.read_bytes()
    if len(data) > 25_000_000:
        raise ValueError('Resource exceeds 25 MB')
    if path.suffix.lower() in {'.css', '.svg'}:
        local_text(data.decode('utf-8'))
    return {'path': name, 'data': base64.b64encode(data).decode('ascii'), 'mimeType': mimetypes.guess_type(name)[0]}

def render(args):
    renderer = args.renderer.expanduser().resolve(strict=True)
    source = args.input.resolve(strict=True)
    assets = []
    if args.kind == 'image':
        assets.append(resource(source, source.name))
        content = ''
    else:
        content = local_text(source.read_text(encoding='utf-8'))
    css = local_text(args.css.read_text(encoding='utf-8')) if args.css else ''
    if args.assets_dir:
        root = args.assets_dir.resolve(strict=True)
        for path in sorted(root.rglob('*')):
            relative = path.relative_to(root)
            if any(part.startswith('.') for part in relative.parts):
                continue
            if path.is_symlink():
                raise ValueError('Symlink resources are not supported')
            if path.is_file() and path.suffix.lower() in EXTENSIONS and path.resolve() != source:
                assets.append(resource(path, relative.as_posix()))
    if len(assets) > 256 or sum(len(base64.b64decode(a['data'])) for a in assets) > 45_000_000:
        raise ValueError('Resources exceed 256 items / 45 MB')
    if len({a['path'] for a in assets}) != len(assets):
        raise ValueError('Duplicate resource path')
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    fonts = output / 'fonts'
    fonts.mkdir()
    worker = output / 'worker-input.json'
    document = {'kind': args.kind, 'content': content, 'assets': assets, 'css': css,
                'font': args.font, 'fontSize': args.font_size, 'printerBitmap': args.printer_bitmap}
    worker.write_text(json.dumps({'directory': str(output), 'fontsDirectory': str(fonts), 'document': document}), encoding='utf-8')
    try:
        with (output/'renderer.log').open('wb') as diagnostics:
            completed = subprocess.run([str(renderer), str(worker)], stdout=subprocess.PIPE, stderr=diagnostics, timeout=65)
        result = json.loads(completed.stdout)
        (output/'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        if completed.returncode or result.get('error') or not result.get('artifacts'):
            raise RuntimeError('Renderer failed; inspect result.json and renderer.log')
        print(json.dumps({'output': str(output), 'printed': False, **result}, ensure_ascii=False))
    finally:
        worker.unlink(missing_ok=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--renderer', type=Path, required=True)
    parser.add_argument('--kind', choices=['html', 'markdown', 'image'], required=True)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--css', type=Path)
    parser.add_argument('--assets-dir', type=Path)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--font', default='PingFang SC')
    parser.add_argument('--font-size', type=float, default=26)
    parser.add_argument('--printer-bitmap', action='store_true')
    args = parser.parse_args()
    if args.printer_bitmap and args.kind != 'image':
        parser.error('--printer-bitmap requires --kind image')
    render(args)
