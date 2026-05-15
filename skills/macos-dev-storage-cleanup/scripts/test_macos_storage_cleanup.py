#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
SCAN_PATH = SCRIPT_DIR / "scan_macos_storage.py"
APPLY_PATH = SCRIPT_DIR / "apply_macos_storage_cleanup.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


scan = load_module("scan_macos_storage_for_tests", SCAN_PATH)
apply_cleanup = load_module("apply_macos_storage_cleanup_for_tests", APPLY_PATH)


def write_file(path: Path, size: int = 8) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * size)


def run_apply(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(APPLY_PATH), *args], capture_output=True, text=True, check=False)


def test_classifies_project_artifacts() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        write_file(root / "App" / ".build" / "debug" / "object.o")
        write_file(root / "Web" / "node_modules" / "pkg" / "index.js")
        write_file(root / "Web" / "Sources" / "main.swift")

        found = {path.name for path in scan.find_project_artifacts([root])}

    assert ".build" in found
    assert "node_modules" in found
    assert "Sources" not in found


def test_keep_latest_archive_grouping() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        older = root / "Project" / "iOS" / "archives" / "Old.xcarchive"
        newer = root / "Project" / "iOS" / "archives" / "New.xcarchive"
        write_file(older / "Info.plist")
        time.sleep(0.01)
        write_file(newer / "Info.plist")

        archives = scan.find_custom_archives([root])
        latest = scan.latest_archive_by_parent(archives)

    assert newer.resolve() in latest
    assert older.resolve() not in latest


def test_wechat_classification_keeps_databases_report_only() -> None:
    db_category, db_risk, db_eligible, _ = scan.classify_wechat_path(Path("/Users/me/xwechat_files/db_storage/main.db"))
    cache_category, cache_risk, cache_eligible, _ = scan.classify_wechat_path(Path("/Users/me/Library/Caches/com.tencent.xinWeChat/blob"))
    media_category, media_risk, media_eligible, _ = scan.classify_wechat_path(Path("/Users/me/xwechat_files/File/report.pdf"))

    assert (db_category, db_risk, db_eligible) == ("wechat-database", "leave-alone", False)
    assert (cache_category, cache_risk, cache_eligible) == ("wechat-cache", "regenerateable", True)
    assert (media_category, media_risk, media_eligible) == ("wechat-media", "review-required", True)


def test_time_machine_snapshot_parsing() -> None:
    output = """
Snapshots for disk /:
com.apple.TimeMachine.2026-05-15-123456.local
2026-05-16-010203.local
"""
    assert scan.parse_tmutil_snapshots(output) == ["2026-05-15-123456.local", "2026-05-16-010203.local"]


def test_simctl_runtime_parsing() -> None:
    output = json.dumps(
        {
            "runtimes": [
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
                    "name": "iOS 26.0",
                    "version": "26.0",
                    "isAvailable": True,
                    "bundlePath": "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.simruntime",
                }
            ]
        }
    )
    runtimes = scan.parse_simctl_runtimes(output)

    assert runtimes[0]["identifier"] == "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
    assert runtimes[0]["bundlePath"].endswith("iOS 26.simruntime")


def test_json_plan_generation_from_fixture_root() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        write_file(root / ".next" / "cache.bin", 1024)
        args = scan.parse_args([
            "--format",
            "json",
            "--category",
            "developer-artifact",
            "--artifact-root",
            str(root),
            "--min-size-mb",
            "0",
        ])
        report = scan.build_report(args)

    assert report["items"]
    assert report["items"][0]["category"] == "developer-artifact"
    assert report["items"][0]["eligible"] is True


def test_apply_defaults_to_dry_run() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        target = root / "project" / ".build"
        write_file(target / "artifact.o", 16)
        plan = {
            "items": [
                {
                    "id": "developer-artifact:test",
                    "category": "developer-artifact",
                    "risk": "regenerateable",
                    "action": "delete-path",
                    "eligible": True,
                    "reason": "fixture",
                    "size_bytes": 16,
                    "path": str(target),
                    "target": None,
                    "metadata": {"allowed_root": str(target.parent)},
                }
            ]
        }
        plan_path = root / "plan.json"
        log_path = root / "dry-run.log"
        plan_path.write_text(json.dumps(plan), encoding="utf-8")
        result = run_apply(["--plan", str(plan_path), "--category", "developer-artifact", "--log", str(log_path)])

        assert result.returncode == 0, result.stderr
        assert target.exists()
        assert "DRY-RUN" in log_path.read_text(encoding="utf-8")


def test_apply_requires_selection_when_applying() -> None:
    with tempfile.TemporaryDirectory() as raw:
        plan_path = Path(raw) / "plan.json"
        plan_path.write_text(json.dumps({"items": []}), encoding="utf-8")
        result = run_apply(["--plan", str(plan_path), "--apply"])

    assert result.returncode == 2
    assert "requires at least one" in result.stderr


def test_apply_refuses_unallowlisted_path() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        target = root / "outside" / "artifact"
        write_file(target / "file.o", 16)
        plan = {
            "items": [
                {
                    "id": "developer-artifact:outside",
                    "category": "developer-artifact",
                    "risk": "regenerateable",
                    "action": "delete-path",
                    "eligible": True,
                    "reason": "fixture",
                    "size_bytes": 16,
                    "path": str(target),
                    "target": None,
                    "metadata": {"allowed_root": str(root / "different-root")},
                }
            ]
        }
        plan_path = root / "plan.json"
        plan_path.write_text(json.dumps(plan), encoding="utf-8")
        result = run_apply(["--plan", str(plan_path), "--category", "developer-artifact", "--apply", "--log", str(root / "apply.log")])

        assert result.returncode == 3
        assert target.exists()


def test_apply_deletes_with_explicit_allow_path() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        target = root / "project" / ".build"
        write_file(target / "artifact.o", 16)
        plan = {
            "items": [
                {
                    "id": "developer-artifact:allowed",
                    "category": "developer-artifact",
                    "risk": "regenerateable",
                    "action": "delete-path",
                    "eligible": True,
                    "reason": "fixture",
                    "size_bytes": 16,
                    "path": str(target),
                    "target": None,
                    "metadata": {},
                }
            ]
        }
        plan_path = root / "plan.json"
        plan_path.write_text(json.dumps(plan), encoding="utf-8")
        result = run_apply(
            [
                "--plan",
                str(plan_path),
                "--category",
                "developer-artifact",
                "--allow-path",
                str(root),
                "--apply",
                "--log",
                str(root / "apply.log"),
            ]
        )

        assert result.returncode == 0, result.stderr
        assert not target.exists()


def run_tests() -> None:
    tests = [
        test_classifies_project_artifacts,
        test_keep_latest_archive_grouping,
        test_wechat_classification_keeps_databases_report_only,
        test_time_machine_snapshot_parsing,
        test_simctl_runtime_parsing,
        test_json_plan_generation_from_fixture_root,
        test_apply_defaults_to_dry_run,
        test_apply_requires_selection_when_applying,
        test_apply_refuses_unallowlisted_path,
        test_apply_deletes_with_explicit_allow_path,
    ]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")


if __name__ == "__main__":
    run_tests()
