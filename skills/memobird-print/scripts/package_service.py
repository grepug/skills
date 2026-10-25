#!/usr/bin/env python3
"""Package explicit SwiftPM outputs with local signing; never install, launch or change TCC."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

def package(products, output):
    skill = Path(__file__).resolve().parent.parent
    if output == skill or skill in output.parents:
        raise ValueError('Choose an output directory outside the installed skill')
    config = skill/'assets/service/Config'
    for name in ['MemobirdService', 'MemobirdRenderer', 'memobird']:
        if not (products/name).is_file():
            raise FileNotFoundError(products/name)
    output.mkdir(parents=True, exist_ok=False)
    app = output/'MemobirdService.app'
    macos, resources = app/'Contents/MacOS', app/'Contents/Resources'
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    identity = os.environ.get('MEMOBIRD_SIGN_IDENTITY', '-')
    for name in ['MemobirdService', 'MemobirdRenderer', 'memobird']:
        shutil.copy2(products/name, macos/('咕咕打印服务' if name == 'MemobirdService' else name))
    for executable in list(macos.iterdir()):
        dependencies = subprocess.check_output(['otool', '-L', str(executable)], text=True)
        commands = subprocess.check_output(['otool', '-l', str(executable)], text=True)
        rpaths = re.findall(r'\bpath ([^\n]+?) \(offset', commands)
        for name in re.findall(r'@rpath/(libswiftCompatibility[^ /]+\.dylib)', dependencies):
            if (macos/name).exists():
                continue
            candidates = [Path(p.replace('@loader_path', str(executable.parent)))/name for p in rpaths]
            source = next((p for p in candidates if p.is_file()), None)
            if source is None:
                raise RuntimeError('Missing Swift compatibility library: '+name)
            shutil.copy2(source, macos/name)
            shutil.copy2(source, output/name)
    for bundle in products.glob('*.bundle'):
        shutil.copytree(bundle, resources/bundle.name)
    shutil.copytree(skill, resources/'skills/memobird-print', ignore=shutil.ignore_patterns('__pycache__', '.DS_Store', '.build', '.swiftpm'))
    shutil.copy2(skill/'references/openapi.yaml', resources/'openapi.yaml')
    info = {'CFBundleIdentifier': 'local.memobird.mac', 'CFBundleExecutable': '咕咕打印服务',
            'CFBundleName': '咕咕打印服务', 'CFBundleDisplayName': '咕咕打印服务', 'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '2', 'LSMinimumSystemVersion': '14.0',
            'LSUIElement': True, 'NSHighResolutionCapable': True,
            'NSBluetoothAlwaysUsageDescription': '通过蓝牙连接您的 MEMOBIRD 打印机并发送您提交的打印任务。'}
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    for name, entitlement in [('MemobirdRenderer', 'MemobirdRenderer.entitlements'), ('咕咕打印服务', 'MemobirdService.entitlements')]:
        subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp=none', '--entitlements', str(config/entitlement), str(macos/name)], check=True)
    subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp=none', str(macos/'memobird')], check=True)
    subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp=none', '--entitlements', str(config/'MemobirdService.entitlements'), str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    shutil.copy2(macos/'memobird', output/'memobird')
    print(app)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--products', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    package(args.products.resolve(), args.output_dir.resolve())
