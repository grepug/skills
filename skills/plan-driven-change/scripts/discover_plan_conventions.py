#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
from dataclasses import asdict, dataclass
from pathlib import Path


PLAN_DIR_CANDIDATES = (
    "docs/plans",
    "docs/superpowers/plans",
    "planning",
    "docs/rfcs",
    "docs/decisions",
    "docs",
    ".github",
)

PLAN_DIR_BASENAMES = ("plans", "rfcs", "decisions")

IGNORED_DIR_NAMES = {
    ".git",
    ".hg",
    ".svn",
    ".venv",
    "venv",
    "node_modules",
    "__pycache__",
    ".mypy_cache",
    ".pytest_cache",
    ".tox",
    ".nox",
    ".next",
    ".turbo",
    "build",
    "dist",
    "target",
    "vendor",
}

TASK_LEDGER_CANDIDATES = (
    "tasks/todo.md",
    "tasks/TODO.md",
    "todo.md",
    "TODO.md",
    "docs/todo.md",
    "docs/TODO.md",
    "planning/todo.md",
    "planning/TODO.md",
)


@dataclass
class ConventionReport:
    repo_root: str
    active_plan_dir: str
    active_plan_dir_source: str
    archive_index: str | None
    retention_mode: str
    separate_task_ledger: str | None
    notes: list[str]
    recovery_examples: list[str]


def list_markdown_files(directory: Path) -> list[Path]:
    return sorted(
        path for path in directory.glob("*.md") if path.is_file() and path.name.lower() != "readme.md"
    )


def walk_repo_directories(repo_root: Path):
    for root, dirnames, filenames in os.walk(repo_root, topdown=True):
        dirnames[:] = sorted(name for name in dirnames if name not in IGNORED_DIR_NAMES)
        yield Path(root), dirnames, filenames


def discover_nested_plan_dirs(repo_root: Path) -> list[Path]:
    matches: list[Path] = []
    for root, _, _ in walk_repo_directories(repo_root):
        if root == repo_root:
            continue
        if root.name.lower() not in PLAN_DIR_BASENAMES:
            continue
        if list_markdown_files(root):
            matches.append(root)
    return sorted(matches)


def discover_active_plan_dir(repo_root: Path) -> tuple[Path, str]:
    for relative in PLAN_DIR_CANDIDATES:
        candidate = repo_root / relative
        if candidate.is_dir() and list_markdown_files(candidate):
            return candidate, "existing_markdown_dir"
    nested_matches = discover_nested_plan_dirs(repo_root)
    if nested_matches:
        return nested_matches[0], "nested_markdown_dir"
    for relative in PLAN_DIR_CANDIDATES:
        candidate = repo_root / relative
        if candidate.is_dir():
            return candidate, "existing_dir"
    return repo_root / "docs/plans", "default"


def discover_archive_index(repo_root: Path, active_plan_dir: Path) -> Path | None:
    preferred = active_plan_dir / "ARCHIVED.md"
    if preferred.is_file():
        return preferred

    matches: list[Path] = []
    for root, _, filenames in walk_repo_directories(repo_root):
        if "ARCHIVED.md" not in filenames:
            continue
        matches.append(root / "ARCHIVED.md")
    return sorted(matches)[0] if matches else None


def discover_task_ledger(repo_root: Path) -> Path | None:
    for relative in TASK_LEDGER_CANDIDATES:
        candidate = repo_root / relative
        if candidate.is_file():
            return candidate
    return None


def infer_retention_mode(active_plan_dir: Path, archive_index: Path | None) -> str:
    if archive_index:
        return "live_working_set_plus_archive_index"
    if active_plan_dir.exists():
        return "historical_plans_kept_in_place"
    return "unknown"


def build_notes(
    active_plan_dir: Path,
    active_plan_dir_source: str,
    archive_index: Path | None,
    task_ledger: Path | None,
    retention_mode: str,
    repo_root: Path,
) -> list[str]:
    notes: list[str] = []

    if active_plan_dir_source == "default":
        notes.append("No plan directory convention was detected; default to docs/plans unless the repo says otherwise.")
    else:
        notes.append(f"Use {active_plan_dir.relative_to(repo_root)} as the live plan location.")

    if archive_index:
        notes.append(
            f"Archive index detected at {archive_index.relative_to(repo_root)}; treat it as metadata, not as a copy of archived plans."
        )
    elif retention_mode == "historical_plans_kept_in_place":
        notes.append(
            "No archive index detected; assume plans stay in place unless project docs say otherwise. "
            "If you need to introduce archival policy, default to a metadata-only ARCHIVED.md index plus git recovery commands."
        )
    else:
        notes.append("Archive policy is unclear; confirm before moving or deleting historical plans.")

    if task_ledger:
        notes.append(f"Separate task ledger detected at {task_ledger.relative_to(repo_root)}.")
    else:
        notes.append("No separate task ledger detected; use the active plan file as the default execution tracker.")

    return notes


def recovery_examples(repo_root: Path, active_plan_dir: Path) -> list[str]:
    sample_path = active_plan_dir.relative_to(repo_root) / "<filename>.md"
    sample = sample_path.as_posix()
    return [
        f"git log --follow -- {sample}",
        f"git show <commit>:{sample}",
    ]


def discover(repo_root: Path) -> ConventionReport:
    active_plan_dir, active_plan_dir_source = discover_active_plan_dir(repo_root)
    archive_index = discover_archive_index(repo_root, active_plan_dir)
    task_ledger = discover_task_ledger(repo_root)
    retention_mode = infer_retention_mode(active_plan_dir, archive_index)

    return ConventionReport(
        repo_root=str(repo_root),
        active_plan_dir=str(active_plan_dir.relative_to(repo_root)),
        active_plan_dir_source=active_plan_dir_source,
        archive_index=str(archive_index.relative_to(repo_root)) if archive_index else None,
        retention_mode=retention_mode,
        separate_task_ledger=str(task_ledger.relative_to(repo_root)) if task_ledger else None,
        notes=build_notes(
            active_plan_dir,
            active_plan_dir_source,
            archive_index,
            task_ledger,
            retention_mode,
            repo_root,
        ),
        recovery_examples=recovery_examples(repo_root, active_plan_dir),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Inspect a repository for plan storage, archival, and task-tracking conventions."
    )
    parser.add_argument(
        "repo_root",
        nargs="?",
        default=".",
        help="Repository root to inspect. Defaults to the current working directory.",
    )
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format.",
    )
    return parser.parse_args()


def print_text(report: ConventionReport) -> None:
    print(f"Repo root: {report.repo_root}")
    print(f"Active plan dir: {report.active_plan_dir} ({report.active_plan_dir_source})")
    print(f"Archive index: {report.archive_index or 'none detected'}")
    print(f"Retention mode: {report.retention_mode}")
    print(f"Separate task ledger: {report.separate_task_ledger or 'none detected'}")
    print("")
    print("Notes:")
    for note in report.notes:
        print(f"- {note}")
    print("")
    print("Recovery examples:")
    for command in report.recovery_examples:
        print(f"- {command}")


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    report = discover(repo_root)

    if args.format == "json":
        print(json.dumps(asdict(report), indent=2))
    else:
        print_text(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
