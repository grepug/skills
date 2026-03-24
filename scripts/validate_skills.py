#!/usr/bin/env python3

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SKILLS_DIR = ROOT / "skills"
REQUIRED_ROOT_FILES = ("README.md", "CONTRIBUTING.md", "LICENSE")
REQUIRED_FRONTMATTER_KEYS = ("name", "description")
REFERENCE_PATTERN = re.compile(r"(?:^|[^A-Za-z0-9_./-])((?:scripts|assets|references)/[A-Za-z0-9._/-]+)")
FRONTMATTER_PATTERN = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
MAX_SKILL_NAME_LENGTH = 64
MIRRORED_ISSUE_TEMPLATE_SKILL_DIR = ROOT / "skills" / "github-issue-workflow" / "assets" / "issue-templates"
MIRRORED_ISSUE_TEMPLATE_ROOT_DIR = ROOT / ".github" / "ISSUE_TEMPLATE"


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def parse_frontmatter(text: str) -> dict[str, str] | None:
    match = FRONTMATTER_PATTERN.match(text)
    if not match:
        return None

    values: dict[str, str] = {}
    for raw_line in match.group(1).splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip().strip("'\"")
    return values


def validate_root_files(errors: list[str]) -> None:
    for relative_path in REQUIRED_ROOT_FILES:
        if not (ROOT / relative_path).is_file():
            fail(errors, f"Missing required root file: {relative_path}")


def validate_mirrored_issue_templates(errors: list[str]) -> None:
    if not MIRRORED_ISSUE_TEMPLATE_SKILL_DIR.is_dir() or not MIRRORED_ISSUE_TEMPLATE_ROOT_DIR.is_dir():
        return

    skill_files = sorted(path.relative_to(MIRRORED_ISSUE_TEMPLATE_SKILL_DIR) for path in MIRRORED_ISSUE_TEMPLATE_SKILL_DIR.rglob("*") if path.is_file())
    root_files = sorted(path.relative_to(MIRRORED_ISSUE_TEMPLATE_ROOT_DIR) for path in MIRRORED_ISSUE_TEMPLATE_ROOT_DIR.rglob("*") if path.is_file())

    if skill_files != root_files:
        fail(
            errors,
            "Mirrored issue template file sets differ between "
            f"{MIRRORED_ISSUE_TEMPLATE_SKILL_DIR.relative_to(ROOT)} and "
            f"{MIRRORED_ISSUE_TEMPLATE_ROOT_DIR.relative_to(ROOT)}",
        )
        return

    for relative_path in skill_files:
        skill_text = (MIRRORED_ISSUE_TEMPLATE_SKILL_DIR / relative_path).read_text(encoding="utf-8")
        root_text = (MIRRORED_ISSUE_TEMPLATE_ROOT_DIR / relative_path).read_text(encoding="utf-8")
        if skill_text != root_text:
            fail(
                errors,
                "Mirrored issue template content differs for "
                f"{relative_path} between {MIRRORED_ISSUE_TEMPLATE_SKILL_DIR.relative_to(ROOT)} "
                f"and {MIRRORED_ISSUE_TEMPLATE_ROOT_DIR.relative_to(ROOT)}",
            )


def validate_readme_index(skill_dirs: list[Path], errors: list[str]) -> None:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    for skill_dir in skill_dirs:
        if skill_dir.name not in readme:
            fail(errors, f"README.md catalog is missing skill entry: {skill_dir.name}")


def validate_skill(skill_dir: Path, errors: list[str]) -> None:
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        fail(errors, f"Missing SKILL.md in {skill_dir.relative_to(ROOT)}")
        return

    text = skill_md.read_text(encoding="utf-8")
    frontmatter = parse_frontmatter(text)
    if frontmatter is None:
        fail(errors, f"{skill_md.relative_to(ROOT)} is missing YAML frontmatter")
        return

    for key in REQUIRED_FRONTMATTER_KEYS:
        value = frontmatter.get(key, "").strip()
        if not value:
            fail(errors, f"{skill_md.relative_to(ROOT)} is missing required frontmatter key: {key}")

    name = frontmatter.get("name", "").strip()
    if name:
        if not re.fullmatch(r"[a-z0-9-]+", name):
            fail(
                errors,
                f"{skill_md.relative_to(ROOT)} has invalid name '{name}': use hyphen-case with lowercase letters, digits, and hyphens only",
            )
        if name.startswith("-") or name.endswith("-") or "--" in name:
            fail(
                errors,
                f"{skill_md.relative_to(ROOT)} has invalid name '{name}': names cannot start/end with hyphen or contain consecutive hyphens",
            )
        if len(name) > MAX_SKILL_NAME_LENGTH:
            fail(
                errors,
                f"{skill_md.relative_to(ROOT)} has name that is too long ({len(name)} characters); maximum is {MAX_SKILL_NAME_LENGTH}",
            )

    description = frontmatter.get("description", "").strip()
    if description:
        if "<" in description or ">" in description:
            fail(
                errors,
                f"{skill_md.relative_to(ROOT)} description cannot contain angle brackets (< or >)",
            )
        if len(description) > 1024:
            fail(
                errors,
                f"{skill_md.relative_to(ROOT)} description is too long ({len(description)} characters); maximum is 1024",
            )

    seen_references: set[str] = set()
    for match in REFERENCE_PATTERN.finditer(text):
        relative_reference = match.group(1).rstrip("`'\"),.:;]")
        if relative_reference in seen_references:
            continue
        seen_references.add(relative_reference)
        referenced_path = skill_dir / relative_reference
        if not referenced_path.exists():
            fail(
                errors,
                f"{skill_md.relative_to(ROOT)} references missing path: {relative_reference}",
            )

    scripts_dir = skill_dir / "scripts"
    if scripts_dir.is_dir():
        for shell_script in sorted(scripts_dir.rglob("*.sh")):
            result = subprocess.run(
                ["bash", "-n", str(shell_script)],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                detail = result.stderr.strip() or result.stdout.strip() or "unknown syntax error"
                fail(errors, f"Shell syntax failed for {shell_script.relative_to(ROOT)}: {detail}")


def main() -> int:
    errors: list[str] = []

    validate_root_files(errors)
    validate_mirrored_issue_templates(errors)

    if not SKILLS_DIR.is_dir():
        fail(errors, "Missing skills directory")
    else:
        skill_dirs = sorted(path for path in SKILLS_DIR.iterdir() if path.is_dir())
        if not skill_dirs:
            fail(errors, "No skill directories found under skills/")
        else:
            for skill_dir in skill_dirs:
                validate_skill(skill_dir, errors)
            if (ROOT / "README.md").is_file():
                validate_readme_index(skill_dirs, errors)

    if errors:
        print("Skill repository validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("Skill repository validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
