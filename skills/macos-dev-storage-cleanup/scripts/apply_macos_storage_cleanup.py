#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPORT_ONLY_CATEGORIES = {
    "docker-summary",
    "orbstack-summary",
    "wechat-database",
    "xcode-application",
}

PATH_ACTIONS = {"delete-path"}
COMMAND_ACTIONS = {
    "simctl-delete-device",
    "simctl-delete-runtime",
    "tmutil-delete-local-snapshot",
}


def load_plan(path: str) -> dict[str, Any]:
    with Path(path).expanduser().open("r", encoding="utf-8") as handle:
        return json.load(handle)


def timestamped_log_path() -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return Path("/tmp") / f"macos-dev-storage-cleanup-{stamp}.log"


def write_log(log_path: Path, message: str) -> None:
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(message.rstrip() + "\n")


def selected_items(items: list[dict[str, Any]], categories: set[str], item_ids: set[str]) -> list[dict[str, Any]]:
    if not categories and not item_ids:
        return []
    selected: list[dict[str, Any]] = []
    for item in items:
        if item.get("category") in categories or item.get("id") in item_ids:
            selected.append(item)
    return selected


def path_is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def dangerous_path(path: Path) -> bool:
    resolved = path.resolve()
    home = Path.home().resolve()
    return resolved in {Path("/"), home, Path("/Users"), Path("/Applications")}


def allowed_roots_for_item(item: dict[str, Any], extra_roots: list[Path]) -> list[Path]:
    roots: list[Path] = []
    metadata = item.get("metadata") or {}
    allowed_root = metadata.get("allowed_root")
    if allowed_root:
        roots.append(Path(allowed_root).expanduser().resolve())

    category = item.get("category")
    home = Path.home().resolve()
    category_roots = {
        "xcode-derived-data": [home / "Library" / "Developer" / "Xcode" / "DerivedData"],
        "xcode-archives": [home / "Library" / "Developer" / "Xcode" / "Archives"],
        "xcode-devicesupport": [home / "Library" / "Developer" / "Xcode" / "iOS DeviceSupport"],
        "xcode-cache": [home / "Library" / "Caches" / "com.apple.dt.Xcode", home / "Library" / "Developer" / "Xcode"],
        "simulator-device": [home / "Library" / "Developer" / "CoreSimulator" / "Devices"],
        "simulator-runtime": [home / "Library" / "Developer" / "CoreSimulator" / "Profiles" / "Runtimes"],
        "coredevice-delta": [home / "Library" / "Developer" / "CoreDevice" / "AppInstallationBinaryDeltas"],
        "vscode-storage": [home / "Library" / "Application Support" / "Code" / "User" / "workspaceStorage"],
        "vscode-cache": [home / "Library" / "Application Support" / "Code"],
        "common-cache": [home / "Library" / "Caches"],
        "wechat-media": [home / "Library" / "Containers" / "com.tencent.xinWeChat"],
        "wechat-cache": [home / "Library" / "Containers" / "com.tencent.xinWeChat"],
    }
    roots.extend(category_roots.get(str(category), []))
    roots.extend(extra_roots)
    return [root for root in roots if str(root)]


def validate_item_path(item: dict[str, Any], extra_roots: list[Path]) -> tuple[bool, str]:
    raw_path = item.get("path")
    if not raw_path:
        return False, "cleanup item has no filesystem path"
    path = Path(raw_path).expanduser()
    if not path.is_absolute():
        return False, f"path is not absolute: {raw_path}"
    if dangerous_path(path):
        return False, f"refusing dangerous top-level path: {path}"
    resolved = path.resolve()
    roots = allowed_roots_for_item(item, extra_roots)
    if not roots:
        return False, f"no allowlist root for {resolved}"
    if any(path_is_relative_to(resolved, root) for root in roots):
        return True, "path is allowlisted"
    return False, f"path is outside allowlisted roots: {resolved}"


def item_is_deletable(item: dict[str, Any], delete_latest_archives: bool) -> tuple[bool, str]:
    category = item.get("category")
    if category in REPORT_ONLY_CATEGORIES:
        return False, "category is report-only"
    if not item.get("eligible"):
        return False, item.get("reason") or "cleanup item is not eligible"
    if item.get("risk") == "leave-alone":
        return False, "risk class is leave-alone"
    if category == "custom-xcode-archive" and (item.get("metadata") or {}).get("keep_latest") and not delete_latest_archives:
        return False, "latest archive in group is preserved"
    return True, "cleanup item is deletable"


def remove_path(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()


def run_command(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True, check=False)


def apply_command_item(item: dict[str, Any]) -> tuple[bool, str]:
    action = item.get("action")
    metadata = item.get("metadata") or {}
    if action == "simctl-delete-device":
        udid = metadata.get("udid") or item.get("target")
        if not udid:
            return False, "simulator device cleanup item has no UDID"
        result = run_command(["xcrun", "simctl", "delete", str(udid)])
    elif action == "simctl-delete-runtime":
        identifier = metadata.get("identifier") or item.get("target") or item.get("path")
        if not identifier:
            return False, "simulator runtime cleanup item has no identifier"
        result = run_command(["xcrun", "simctl", "runtime", "delete", str(identifier)])
    elif action == "tmutil-delete-local-snapshot":
        snapshot = item.get("target")
        if not snapshot:
            return False, "Time Machine cleanup item has no snapshot target"
        result = run_command(["tmutil", "deletelocalsnapshots", str(snapshot)])
    else:
        return False, f"unsupported command action: {action}"

    output = (result.stdout or result.stderr or "").strip()
    if result.returncode != 0:
        return False, output or f"command failed with exit code {result.returncode}"
    return True, output or "command completed"


def process_item(item: dict[str, Any], args: argparse.Namespace, log_path: Path) -> tuple[str, int]:
    deletable, reason = item_is_deletable(item, args.delete_latest_archives)
    label = item.get("path") or item.get("target") or item.get("id")
    if not deletable:
        write_log(log_path, f"SKIP {item.get('id')}: {reason} [{label}]")
        return ("skipped", 0)

    action = item.get("action")
    if action in PATH_ACTIONS:
        valid, validation_reason = validate_item_path(item, [Path(path).expanduser().resolve() for path in args.allow_path])
        if not valid:
            write_log(log_path, f"REFUSE {item.get('id')}: {validation_reason} [{label}]")
            return ("refused", 0)
        path = Path(str(item["path"])).expanduser()
        if not path.exists():
            write_log(log_path, f"SKIP {item.get('id')}: path no longer exists [{path}]")
            return ("skipped", 0)
        size = int(item.get("size_bytes") or 0)
        if args.apply:
            remove_path(path)
            write_log(log_path, f"DELETE {item.get('id')}: {path} ({size} bytes)")
            return ("deleted", size)
        write_log(log_path, f"DRY-RUN {item.get('id')}: would delete {path} ({size} bytes)")
        return ("dry-run", size)

    if action in COMMAND_ACTIONS:
        if args.apply:
            ok, detail = apply_command_item(item)
            status = "DELETE" if ok else "FAILED"
            write_log(log_path, f"{status} {item.get('id')}: {detail} [{label}]")
            return ("deleted" if ok else "failed", int(item.get("size_bytes") or 0) if ok else 0)
        write_log(log_path, f"DRY-RUN {item.get('id')}: would run {action} for {label}")
        return ("dry-run", int(item.get("size_bytes") or 0))

    write_log(log_path, f"SKIP {item.get('id')}: unsupported action {action} [{label}]")
    return ("skipped", 0)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply a selected macOS developer storage cleanup plan.")
    parser.add_argument("--plan", required=True, help="JSON plan emitted by scan_macos_storage.py.")
    parser.add_argument("--category", action="append", default=[], help="Category to apply. May be repeated.")
    parser.add_argument("--item", action="append", default=[], help="Cleanup item ID to apply. May be repeated.")
    parser.add_argument("--allow-path", action="append", default=[], help="Additional user-approved filesystem root.")
    parser.add_argument("--apply", action="store_true", help="Actually delete selected cleanup items.")
    parser.add_argument("--delete-latest-archives", action="store_true", help="Allow deletion of latest custom archives.")
    parser.add_argument("--log", default=str(timestamped_log_path()), help="Execution log path.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.apply and not args.category and not args.item:
        print("--apply requires at least one --category or --item selection", file=sys.stderr)
        return 2

    plan = load_plan(args.plan)
    items = selected_items(plan.get("items", []), set(args.category), set(args.item))
    log_path = Path(args.log).expanduser()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    write_log(log_path, f"macOS developer storage cleanup started apply={args.apply}")

    totals = {"deleted": 0, "dry-run": 0, "skipped": 0, "refused": 0, "failed": 0}
    bytes_selected = 0
    for item in items:
        status, size = process_item(item, args, log_path)
        totals[status] = totals.get(status, 0) + 1
        bytes_selected += size

    print(f"Selected cleanup item(s): {len(items)}")
    print(f"Apply mode: {'yes' if args.apply else 'no, dry-run only'}")
    print(f"Bytes selected: {bytes_selected}")
    print(f"Results: {json.dumps(totals, sort_keys=True)}")
    print(f"Log: {log_path}")

    if args.apply and totals.get("refused", 0):
        return 3
    if args.apply and totals.get("failed", 0):
        return 4
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
