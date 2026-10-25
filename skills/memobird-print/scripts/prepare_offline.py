#!/usr/bin/env python3
"""Copy a dependency-free core/renderer Swift package to a new explicit work directory."""
import argparse
import shutil
from pathlib import Path

MANIFEST = '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "MemobirdOffline", platforms: [.macOS(.v14)],
    products: [.executable(name: "MemobirdRenderer", targets: ["MemobirdRenderer"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "MemobirdCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "MemobirdRenderer", dependencies: ["MemobirdCore"], resources: [.process("Resources")]),
        .testTarget(name: "MemobirdCoreTests", dependencies: ["MemobirdCore"])
    ])
'''

def prepare(work):
    skill = Path(__file__).resolve().parent.parent
    work = work.resolve()
    if work == skill or skill in work.parents:
        raise ValueError('Choose a work directory outside the installed skill')
    source = skill / 'assets/service/MemobirdServicePackage'
    work.mkdir(parents=True, exist_ok=False)
    for name in ['CSQLite', 'MemobirdCore', 'MemobirdRenderer']:
        shutil.copytree(source / 'Sources' / name, work / 'Sources' / name)
    shutil.copytree(source / 'Tests', work / 'Tests')
    (work / 'Package.swift').write_text(MANIFEST, encoding='utf-8')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.work_dir)
    print(args.work_dir.resolve())
