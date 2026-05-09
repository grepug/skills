#!/usr/bin/env python3
"""
Smoke tests for the inline documentation audit helper.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


SCRIPT = Path(__file__).with_name("audit_inline_docs.py")


def main() -> int:
    tests = [
        test_directives_do_not_count_as_docs,
        test_fix_does_not_generate_placeholder_docs,
        test_generated_files_are_skipped,
        test_automatically_generated_banner_is_skipped,
        test_swift_inline_attributes_are_audited,
        test_export_declare_enum_is_audited,
        test_skipped_directories_are_pruned,
        test_fix_moves_docs_above_decorators,
    ]

    for test in tests:
        test()

    print(f"{len(tests)} inline-doc audit smoke test(s) passed")
    return 0


def test_directives_do_not_count_as_docs() -> None:
    with tempfile.TemporaryDirectory(prefix="inline-doc-directive.") as raw_tmp:
        tmp = Path(raw_tmp)
        source = tmp / "sample.ts"
        source.write_text(
            "\n".join(
                [
                    "/* eslint-disable no-console */",
                    "",
                    "// eslint-disable-next-line @typescript-eslint/no-empty-interface",
                    "export interface AuditInput {",
                    "  id: string;",
                    "}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

        result = run_audit(tmp)
        assert result.returncode == 1
        assert "missing-file-header" in result.stdout
        assert "missing-type-doc" in result.stdout


def test_fix_does_not_generate_placeholder_docs() -> None:
    with tempfile.TemporaryDirectory(prefix="inline-doc-fix.") as raw_tmp:
        tmp = Path(raw_tmp)
        source = tmp / "sample.ts"
        source.write_text(
            "\n".join(
                [
                    "export interface AuditInput {",
                    "  id: string;",
                    "}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

        result = run_audit(tmp, "--fix")
        assert result.returncode == 1
        assert "auto-fixed 0 file(s)" in result.stdout
        assert source.read_text(encoding="utf-8").startswith("export interface")


def test_generated_files_are_skipped() -> None:
    with tempfile.TemporaryDirectory(prefix="inline-doc-generated.") as raw_tmp:
        tmp = Path(raw_tmp)
        source = tmp / "model.ts"
        source.write_text(
            "\n".join(
                [
                    "// Generated file",
                    "export interface GeneratedThing {",
                    "  id: string;",
                    "}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

        result = run_audit(tmp, "--type-doc-policy", "all")
        assert result.returncode == 0
        assert "scanned 0 file(s)" in result.stdout


def test_automatically_generated_banner_is_skipped() -> None:
    with tempfile.TemporaryDirectory(prefix="inline-doc-generated-banner.") as raw_tmp:
        tmp = Path(raw_tmp)
        source = tmp / "model.ts"
        source.write_text(
            "\n".join(
                [
                    "// This file was automatically generated.",
                    "export interface GeneratedThing {",
                    "  id: string;",
                    "}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

        result = run_audit(tmp, "--type-doc-policy", "all")
        assert result.returncode == 0
        assert "scanned 0 file(s)" in result.stdout


def test_swift_inline_attributes_are_audited() -> None:
    with tempfile.TemporaryDirectory(prefix="inline-doc-swift-attribute.") as raw_tmp:
        tmp = Path(raw_tmp)
        source = tmp / "Coordinator.swift"
        source.write_text(
            "\n".join(
                [
                    "// Coordinator.swift",
                    "//",
                    "// Coordinates app startup for this module.",
                    "",
                    "@MainActor public final class AppCoordinator {",
                    "}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

        result = run_audit(tmp)
        assert result.returncode == 1
        assert "missing-type-doc" in result.stdout
        assert "AppCoordinator" in result.stdout


def test_export_declare_enum_is_audited() -> None:
    with tempfile.TemporaryDirectory(prefix="inline-doc-declare-enum.") as raw_tmp:
        tmp = Path(raw_tmp)
        source = tmp / "states.ts"
        source.write_text(
            "\n".join(
                [
                    "/**",
                    " * Defines externally visible state constants for this module.",
                    " */",
                    "",
                    "export declare enum ExternalState {",
                    "  Ready = 'ready',",
                    "}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

        result = run_audit(tmp)
        assert result.returncode == 1
        assert "missing-type-doc" in result.stdout
        assert "ExternalState" in result.stdout


def test_skipped_directories_are_pruned() -> None:
    with tempfile.TemporaryDirectory(prefix="inline-doc-prune.") as raw_tmp:
        tmp = Path(raw_tmp)
        ignored = tmp / "node_modules" / "pkg"
        ignored.mkdir(parents=True)
        (ignored / "ignored.ts").write_text(
            "\n".join(
                [
                    "export interface Ignored {",
                    "  id: string;",
                    "}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

        src = tmp / "src"
        src.mkdir()
        (src / "queue.ts").write_text(
            "\n".join(
                [
                    "/**",
                    " * Owns queue configuration for this module.",
                    " */",
                    "",
                    "/** Stable queue options exposed to callers. */",
                    "export interface QueueOptions {",
                    "  id: string;",
                    "}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

        result = run_audit(tmp)
        assert result.returncode == 0
        assert "scanned 1 file(s)" in result.stdout


def test_fix_moves_docs_above_decorators() -> None:
    with tempfile.TemporaryDirectory(prefix="inline-doc-decorator.") as raw_tmp:
        tmp = Path(raw_tmp)
        source = tmp / "service.ts"
        source.write_text(
            "\n".join(
                [
                    "/**",
                    " * Owns queue coordination for this module.",
                    " */",
                    "",
                    "@Injectable()",
                    "/** Coordinates queue work for callers. */",
                    "export class QueueService {",
                    "}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

        result = run_audit(tmp, "--fix")
        assert result.returncode == 0
        text = source.read_text(encoding="utf-8")
        assert "/** Coordinates queue work for callers. */\n@Injectable()" in text


def run_audit(path: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args, str(path)],
        capture_output=True,
        text=True,
        check=False,
    )


if __name__ == "__main__":
    raise SystemExit(main())
