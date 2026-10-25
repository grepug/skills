#!/usr/bin/env python3
"""Build and package the service in a new work directory; never install or start it."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, required=True)
    args = parser.parse_args()
    skill = Path(__file__).resolve().parent.parent
    work = args.work_dir.resolve()
    if work == skill or skill in work.parents:
        raise ValueError('Choose a work directory outside the installed skill')
    work.mkdir(parents=True, exist_ok=False)
    package = work/'MemobirdServicePackage'
    shutil.copytree(skill/'assets/service/MemobirdServicePackage', package)
    subprocess.run(['xcodebuildmcp', 'swift-package', 'build', '--package-path', str(package), '--configuration', 'release'], check=True)
    candidates = [package/'.build/out/Products/Release', package/'.build/release']
    products = next((p for p in candidates if (p/'MemobirdService').is_file()), None)
    if products is None:
        raise RuntimeError('Cannot locate products; pass actual build product path to package_service.py')
    subprocess.run([sys.executable, str(skill/'scripts/package_service.py'), '--products', str(products), '--output-dir', str(work/'output')], check=True)
