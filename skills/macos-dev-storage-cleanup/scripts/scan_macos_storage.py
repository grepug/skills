#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


ARTIFACT_DIR_NAMES = {
    ".build",
    ".next",
    ".turbo",
    "Pods",
    "build",
    "dist",
    "node_modules",
}

REPORT_ONLY_CATEGORIES = {
    "docker-summary",
    "orbstack-summary",
    "wechat-database",
    "xcode-application",
}


@dataclass
class CleanupItem:
    id: str
    category: str
    risk: str
    action: str
    eligible: bool
    reason: str
    size_bytes: int = 0
    path: str | None = None
    target: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def stable_id(category: str, target: str) -> str:
    digest = hashlib.sha1(f"{category}\0{target}".encode("utf-8")).hexdigest()[:12]
    return f"{category}:{digest}"


def path_size_bytes(path: Path) -> int:
    if not path.exists():
        return 0
    if path.is_symlink() or path.is_file():
        try:
            return path.stat().st_size
        except OSError:
            return 0

    total = 0
    for root, dirs, files in os.walk(path, topdown=True):
        root_path = Path(root)
        kept_dirs: list[str] = []
        for dirname in dirs:
            child = root_path / dirname
            if not child.is_symlink():
                kept_dirs.append(dirname)
        dirs[:] = kept_dirs

        for name in files:
            child = root_path / name
            if child.is_symlink():
                continue
            try:
                total += child.stat().st_size
            except OSError:
                continue
    return total


def human_bytes(size: int) -> str:
    value = float(size)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024 or unit == "TB":
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024
    return f"{size} B"


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def run_command(args: list[str], timeout: int = 20) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(args, capture_output=True, text=True, check=False, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None


def add_path_item(
    items: list[CleanupItem],
    category: str,
    path: Path,
    risk: str,
    action: str = "delete-path",
    eligible: bool = True,
    reason: str = "selected path can be removed when explicitly chosen",
    min_size_bytes: int = 0,
    metadata: dict[str, Any] | None = None,
) -> None:
    if not path.exists():
        return
    size = path_size_bytes(path)
    if size < min_size_bytes:
        return
    resolved = str(path.expanduser().resolve())
    item_metadata = dict(metadata or {})
    item_metadata.setdefault("allowed_root", resolved if path.is_file() else str(path.parent.resolve()))
    if category in REPORT_ONLY_CATEGORIES:
        eligible = False
        action = "report-only"
    items.append(
        CleanupItem(
            id=stable_id(category, resolved),
            category=category,
            path=resolved,
            size_bytes=size,
            risk=risk,
            action=action,
            eligible=eligible,
            reason=reason,
            metadata=item_metadata,
        )
    )


def add_direct_children(
    items: list[CleanupItem],
    root: Path,
    category: str,
    risk: str,
    min_size_bytes: int,
    reason: str,
) -> None:
    if not root.is_dir():
        return
    children = sorted(root.iterdir(), key=lambda path: path.name)
    if not children:
        add_path_item(items, category, root, risk, min_size_bytes=min_size_bytes, reason=reason)
        return
    for child in children:
        add_path_item(items, category, child, risk, min_size_bytes=min_size_bytes, reason=reason)


def read_xcode_version(app_path: Path) -> str | None:
    info_plist = app_path / "Contents" / "Info.plist"
    if not info_plist.is_file():
        return None
    try:
        with info_plist.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException):
        return None
    return str(info.get("CFBundleShortVersionString") or info.get("DTXcode") or "") or None


def scan_xcode(items: list[CleanupItem], home: Path, min_size_bytes: int, latest_xcode_version: str | None) -> None:
    xcode_root = home / "Library" / "Developer" / "Xcode"
    add_direct_children(
        items,
        xcode_root / "DerivedData",
        "xcode-derived-data",
        "regenerateable",
        min_size_bytes,
        "Xcode can rebuild DerivedData for selected projects",
    )
    add_direct_children(
        items,
        xcode_root / "Archives",
        "xcode-archives",
        "review-required",
        min_size_bytes,
        "archives may be needed for symbolication, release records, or re-export",
    )
    add_direct_children(
        items,
        xcode_root / "iOS DeviceSupport",
        "xcode-devicesupport",
        "review-required",
        min_size_bytes,
        "device support can be redownloaded but may be needed for connected-device debugging",
    )
    for cache_root in (
        home / "Library" / "Caches" / "com.apple.dt.Xcode",
        xcode_root / "Products",
        xcode_root / "DocumentationCache",
    ):
        add_path_item(
            items,
            "xcode-cache",
            cache_root,
            "regenerateable",
            min_size_bytes=min_size_bytes,
            reason="Xcode cache data can be regenerated",
        )

    for app_path in sorted(Path("/Applications").glob("Xcode*.app")):
        metadata = {"xcode_version": read_xcode_version(app_path), "latest_xcode_version": latest_xcode_version}
        add_path_item(
            items,
            "xcode-application",
            app_path,
            "review-required",
            eligible=False,
            action="report-only",
            min_size_bytes=min_size_bytes,
            reason="installed Xcode apps are reported only and require direct user instruction to remove",
            metadata=metadata,
        )

    for downloads in (home / "Downloads", home / "Developer"):
        for pattern in ("Xcode*.xip", "Xcode*.dmg", "Xcode*.zip"):
            for installer in sorted(downloads.glob(pattern)):
                add_path_item(
                    items,
                    "xcode-application",
                    installer,
                    "review-required",
                    eligible=False,
                    action="report-only",
                    min_size_bytes=min_size_bytes,
                    reason="Xcode installers are reported only and require direct user instruction to remove",
                )


def parse_simctl_devices(output: str) -> list[dict[str, Any]]:
    try:
        payload = json.loads(output)
    except json.JSONDecodeError:
        return []
    parsed: list[dict[str, Any]] = []
    for runtime, devices in payload.get("devices", {}).items():
        for device in devices:
            parsed.append(
                {
                    "runtime": runtime,
                    "name": device.get("name"),
                    "udid": device.get("udid"),
                    "state": device.get("state"),
                    "isAvailable": device.get("isAvailable"),
                    "dataPath": device.get("dataPath"),
                }
            )
    return parsed


def parse_simctl_runtimes(output: str) -> list[dict[str, Any]]:
    try:
        payload = json.loads(output)
    except json.JSONDecodeError:
        return []
    parsed: list[dict[str, Any]] = []
    for runtime in payload.get("runtimes", []):
        parsed.append(
            {
                "identifier": runtime.get("identifier"),
                "name": runtime.get("name"),
                "version": runtime.get("version"),
                "isAvailable": runtime.get("isAvailable"),
                "bundlePath": runtime.get("bundlePath"),
            }
        )
    return parsed


def scan_simulators(items: list[CleanupItem], home: Path, min_size_bytes: int, latest_simulator_version: str | None) -> None:
    if command_exists("xcrun"):
        result = run_command(["xcrun", "simctl", "list", "devices", "--json"])
        if result and result.returncode == 0:
            for device in parse_simctl_devices(result.stdout):
                data_path = device.get("dataPath")
                if not data_path:
                    continue
                metadata = dict(device)
                metadata["latest_simulator_version"] = latest_simulator_version
                add_path_item(
                    items,
                    "simulator-device",
                    Path(data_path),
                    "review-required",
                    action="simctl-delete-device",
                    min_size_bytes=min_size_bytes,
                    reason="simulator devices may contain app data and should be explicitly selected",
                    metadata=metadata,
                )

        result = run_command(["xcrun", "simctl", "list", "runtimes", "--json"])
        if result and result.returncode == 0:
            for runtime in parse_simctl_runtimes(result.stdout):
                bundle_path = runtime.get("bundlePath")
                if not bundle_path:
                    continue
                metadata = dict(runtime)
                metadata["latest_simulator_version"] = latest_simulator_version
                add_path_item(
                    items,
                    "simulator-runtime",
                    Path(bundle_path),
                    "review-required",
                    action="simctl-delete-runtime",
                    min_size_bytes=min_size_bytes,
                    reason="simulator runtimes can be large and may need redownload",
                    metadata=metadata,
                )

    devices_root = home / "Library" / "Developer" / "CoreSimulator" / "Devices"
    if not any(item.category == "simulator-device" for item in items):
        add_direct_children(
            items,
            devices_root,
            "simulator-device",
            "review-required",
            min_size_bytes,
            "simulator devices may contain app data and should be explicitly selected",
        )

    runtime_root = home / "Library" / "Developer" / "CoreSimulator" / "Profiles" / "Runtimes"
    if not any(item.category == "simulator-runtime" for item in items):
        for runtime in sorted(runtime_root.glob("*.simruntime")):
            metadata = {"latest_simulator_version": latest_simulator_version}
            add_path_item(
                items,
                "simulator-runtime",
                runtime,
                "review-required",
                action="delete-path",
                min_size_bytes=min_size_bytes,
                reason="simulator runtimes can be large and may need redownload",
                metadata=metadata,
            )


def scan_coredevice(items: list[CleanupItem], home: Path, min_size_bytes: int) -> None:
    add_direct_children(
        items,
        home / "Library" / "Developer" / "CoreDevice" / "AppInstallationBinaryDeltas",
        "coredevice-delta",
        "regenerateable",
        min_size_bytes,
        "CoreDevice app installation binary deltas are rebuildable transfer caches",
    )


def find_project_artifacts(roots: Iterable[Path], max_depth: int = 5) -> list[Path]:
    found: list[Path] = []
    for root in roots:
        root = root.expanduser()
        if not root.is_dir():
            continue
        root = root.resolve()
        for current, dirs, _files in os.walk(root, topdown=True):
            current_path = Path(current)
            try:
                depth = len(current_path.relative_to(root).parts)
            except ValueError:
                continue
            if depth > max_depth:
                dirs[:] = []
                continue

            kept_dirs: list[str] = []
            for dirname in sorted(dirs):
                child = current_path / dirname
                if dirname in ARTIFACT_DIR_NAMES:
                    found.append(child)
                    continue
                if dirname in {".git", ".hg", ".svn"}:
                    continue
                kept_dirs.append(dirname)
            dirs[:] = kept_dirs
    return sorted(set(found))


def scan_project_artifacts(items: list[CleanupItem], roots: list[Path], min_size_bytes: int) -> None:
    for artifact in find_project_artifacts(roots):
        add_path_item(
            items,
            "developer-artifact",
            artifact,
            "regenerateable",
            min_size_bytes=min_size_bytes,
            reason="selected rebuildable project artifact directory can be regenerated",
            metadata={"allowed_root": str(artifact.parent.resolve()), "artifact_name": artifact.name},
        )


def find_custom_archives(roots: Iterable[Path]) -> list[Path]:
    archives: list[Path] = []
    for root in roots:
        root = root.expanduser()
        if not root.is_dir():
            continue
        for current, dirs, _files in os.walk(root, topdown=True):
            current_path = Path(current)
            try:
                depth = len(current_path.relative_to(root).parts)
            except ValueError:
                continue
            if depth > 5:
                dirs[:] = []
                continue
            for dirname in list(dirs):
                if dirname.endswith(".xcarchive"):
                    archives.append(current_path / dirname)
                    dirs.remove(dirname)
    return sorted(set(path.resolve() for path in archives))


def latest_archive_by_parent(archives: Iterable[Path]) -> set[Path]:
    latest: dict[Path, tuple[float, Path]] = {}
    for archive in archives:
        parent = archive.parent
        try:
            mtime = archive.stat().st_mtime
        except OSError:
            mtime = 0
        current = latest.get(parent)
        if current is None or mtime > current[0] or (mtime == current[0] and archive.name > current[1].name):
            latest[parent] = (mtime, archive)
    return {entry[1] for entry in latest.values()}


def scan_custom_archives(items: list[CleanupItem], roots: list[Path], min_size_bytes: int) -> None:
    archives = find_custom_archives(roots)
    latest = latest_archive_by_parent(archives)
    for archive in archives:
        keep_latest = archive in latest
        add_path_item(
            items,
            "custom-xcode-archive",
            archive,
            "review-required",
            eligible=True,
            min_size_bytes=min_size_bytes,
            reason="custom Xcode archives may be needed for release history or symbolication",
            metadata={
                "allowed_root": str(archive.parent.resolve()),
                "keep_latest": keep_latest,
                "archive_group": str(archive.parent.resolve()),
            },
        )


def scan_docker_or_orbstack(items: list[CleanupItem]) -> None:
    if command_exists("docker"):
        result = run_command(["docker", "system", "df"], timeout=10)
        output = (result.stdout if result else "").strip()
        items.append(
            CleanupItem(
                id=stable_id("docker-summary", "docker system df"),
                category="docker-summary",
                risk="review-required",
                action="report-only",
                eligible=False,
                reason="Docker cleanup should use a separate user-approved prune command",
                target="docker system df",
                metadata={"summary": output, "returncode": result.returncode if result else None},
            )
        )
    if command_exists("orb"):
        result = run_command(["orb", "disk", "usage"], timeout=10)
        output = (result.stdout if result else "").strip()
        items.append(
            CleanupItem(
                id=stable_id("orbstack-summary", "orb disk usage"),
                category="orbstack-summary",
                risk="review-required",
                action="report-only",
                eligible=False,
                reason="OrbStack cleanup should use a separate user-approved command",
                target="orb disk usage",
                metadata={"summary": output, "returncode": result.returncode if result else None},
            )
        )


def scan_vscode(items: list[CleanupItem], home: Path, min_size_bytes: int) -> None:
    code_root = home / "Library" / "Application Support" / "Code"
    add_direct_children(
        items,
        code_root / "User" / "workspaceStorage",
        "vscode-storage",
        "review-required",
        min_size_bytes,
        "VS Code workspace storage may contain extension state and should be explicitly selected",
    )
    for cache_name in ("Cache", "CachedData", "GPUCache", "logs"):
        add_path_item(
            items,
            "vscode-cache",
            code_root / cache_name,
            "regenerateable",
            min_size_bytes=min_size_bytes,
            reason="VS Code cache data can be regenerated",
        )


def classify_wechat_path(path: Path) -> tuple[str, str, bool, str]:
    lowered_parts = [part.lower() for part in path.parts]
    path_text = str(path).lower()
    if "db_storage" in lowered_parts or "database" in path_text or "message.db" in path_text:
        return ("wechat-database", "leave-alone", False, "WeChat message and account databases are report-only")
    if "caches" in lowered_parts or "cache" in path_text:
        return ("wechat-cache", "regenerateable", True, "WeChat cache data can be regenerated")
    return ("wechat-media", "review-required", True, "WeChat media may be user-owned and should be explicitly selected")


def scan_wechat(items: list[CleanupItem], home: Path, min_size_bytes: int) -> None:
    candidates = [
        home / "Library" / "Containers" / "com.tencent.xinWeChat" / "Data" / "Library" / "Caches",
        home / "Library" / "Containers" / "com.tencent.xinWeChat" / "Data" / "Documents" / "xwechat_files",
        home
        / "Library"
        / "Containers"
        / "com.tencent.xinWeChat"
        / "Data"
        / "Library"
        / "Application Support"
        / "com.tencent.xinWeChat"
        / "db_storage",
    ]
    for candidate in candidates:
        category, risk, eligible, reason = classify_wechat_path(candidate)
        add_path_item(
            items,
            category,
            candidate,
            risk,
            eligible=eligible,
            min_size_bytes=min_size_bytes,
            reason=reason,
        )


def scan_common_caches(items: list[CleanupItem], home: Path, min_size_bytes: int) -> None:
    for cache_path in (
        home / "Library" / "Caches" / "org.swift.swiftpm",
        home / "Library" / "Caches" / "pip",
        home / "Library" / "Caches" / "CocoaPods",
    ):
        add_path_item(
            items,
            "common-cache",
            cache_path,
            "regenerateable",
            min_size_bytes=min_size_bytes,
            reason="developer cache data can be regenerated",
        )


def parse_tmutil_snapshots(output: str) -> list[str]:
    snapshots: list[str] = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("com.apple.TimeMachine."):
            snapshots.append(line.removeprefix("com.apple.TimeMachine."))
        elif line[0].isdigit():
            snapshots.append(line)
    return snapshots


def scan_time_machine(items: list[CleanupItem]) -> None:
    if not command_exists("tmutil"):
        return
    result = run_command(["tmutil", "listlocalsnapshots", "/"], timeout=15)
    if not result or result.returncode != 0:
        return
    for snapshot in parse_tmutil_snapshots(result.stdout):
        items.append(
            CleanupItem(
                id=stable_id("time-machine-snapshot", snapshot),
                category="time-machine-snapshot",
                risk="review-required",
                action="tmutil-delete-local-snapshot",
                eligible=True,
                reason="local snapshots can retain deleted blocks and should be removed only after explicit selection",
                target=snapshot,
            )
        )


def category_allowed(category_filter: set[str], category: str) -> bool:
    return not category_filter or category in category_filter


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    home = Path(args.home).expanduser().resolve()
    min_size_bytes = int(args.min_size_mb * 1024 * 1024)
    category_filter = set(args.category or [])
    artifact_roots = [Path(path).expanduser().resolve() for path in (args.artifact_root or [Path.cwd()])]
    archive_roots = [Path(path).expanduser().resolve() for path in (args.archive_root or [home / "Developer" / "xcode-build"])]

    items: list[CleanupItem] = []
    if any(category_allowed(category_filter, category) for category in ("xcode-derived-data", "xcode-archives", "xcode-devicesupport", "xcode-cache", "xcode-application")):
        scan_xcode(items, home, min_size_bytes, args.latest_xcode_version)
    if any(category_allowed(category_filter, category) for category in ("simulator-device", "simulator-runtime")):
        scan_simulators(items, home, min_size_bytes, args.latest_simulator_version)
    if category_allowed(category_filter, "coredevice-delta"):
        scan_coredevice(items, home, min_size_bytes)
    if category_allowed(category_filter, "developer-artifact"):
        scan_project_artifacts(items, artifact_roots, min_size_bytes)
    if category_allowed(category_filter, "custom-xcode-archive"):
        scan_custom_archives(items, archive_roots, min_size_bytes)
    if any(category_allowed(category_filter, category) for category in ("docker-summary", "orbstack-summary")):
        scan_docker_or_orbstack(items)
    if any(category_allowed(category_filter, category) for category in ("vscode-storage", "vscode-cache")):
        scan_vscode(items, home, min_size_bytes)
    if any(category_allowed(category_filter, category) for category in ("wechat-media", "wechat-cache", "wechat-database")):
        scan_wechat(items, home, min_size_bytes)
    if category_allowed(category_filter, "common-cache"):
        scan_common_caches(items, home, min_size_bytes)
    if category_allowed(category_filter, "time-machine-snapshot"):
        scan_time_machine(items)

    filtered = [item for item in items if category_allowed(category_filter, item.category)]
    filtered.sort(key=lambda item: (item.size_bytes, item.category, item.path or item.target or ""), reverse=True)

    summary: dict[str, dict[str, int]] = {}
    for item in filtered:
        entry = summary.setdefault(item.category, {"count": 0, "bytes": 0})
        entry["count"] += 1
        entry["bytes"] += item.size_bytes

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "home": str(home),
        "artifact_roots": [str(path) for path in artifact_roots],
        "archive_roots": [str(path) for path in archive_roots],
        "min_size_bytes": min_size_bytes,
        "items": [item.to_dict() for item in filtered],
        "summary": summary,
    }


def print_human(report: dict[str, Any]) -> None:
    items = report["items"]
    print(f"macOS developer storage scan: {len(items)} cleanup item(s)")
    print(f"Generated: {report['generated_at']}")
    print()
    if not items:
        print("No cleanup items matched the selected categories and minimum size.")
        return
    for item in items:
        location = item.get("path") or item.get("target") or "(unknown target)"
        marker = "eligible" if item["eligible"] else "report-only"
        print(
            f"{human_bytes(item['size_bytes']):>10}  {item['category']:<24} "
            f"{item['risk']:<15} {marker:<11} {item['id']}"
        )
        print(f"            {location}")
        print(f"            {item['reason']}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Read-only macOS developer storage scanner.")
    parser.add_argument("--format", choices=("human", "json"), default="human", help="Output format.")
    parser.add_argument("--category", action="append", help="Category to scan. May be repeated.")
    parser.add_argument("--min-size-mb", type=float, default=1.0, help="Minimum path size to report.")
    parser.add_argument("--home", default=str(Path.home()), help="Home directory root.")
    parser.add_argument("--artifact-root", action="append", help="Project root to scan for rebuildable artifacts.")
    parser.add_argument("--archive-root", action="append", help="Custom Xcode archive root to scan.")
    parser.add_argument("--latest-xcode-version", help="Current Xcode version hint for review.")
    parser.add_argument("--latest-simulator-version", help="Current simulator runtime version hint for review.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    report = build_report(args)
    if args.format == "json":
        json.dump(report, sys.stdout, indent=2, sort_keys=True)
        print()
    else:
        print_human(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
