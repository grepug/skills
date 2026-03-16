#!/usr/bin/env python3

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REQUIRED_FRONTMATTER_KEYS = ("name", "description")
REFERENCE_PATTERN = re.compile(r"(?:^|[^A-Za-z0-9_./-])((?:scripts|assets|references)/[A-Za-z0-9._/-]+)")
FRONTMATTER_PATTERN = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
MAX_SKILL_NAME_LENGTH = 64


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


def validate_skill_dir(skill_dir: Path) -> list[str]:
    errors: list[str] = []

    if not skill_dir.exists():
        return [f"Skill directory does not exist: {skill_dir}"]
    if not skill_dir.is_dir():
        return [f"Skill path is not a directory: {skill_dir}"]

    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        return [f"Missing SKILL.md in {skill_dir.relative_to(ROOT) if skill_dir.is_relative_to(ROOT) else skill_dir}"]

    text = skill_md.read_text(encoding="utf-8")
    frontmatter = parse_frontmatter(text)
    if frontmatter is None:
        return [f"{skill_md} is missing YAML frontmatter"]

    for key in REQUIRED_FRONTMATTER_KEYS:
        value = frontmatter.get(key, "").strip()
        if not value:
            errors.append(f"{skill_md} is missing required frontmatter key: {key}")

    name = frontmatter.get("name", "").strip()
    if name:
        if not re.fullmatch(r"[a-z0-9-]+", name):
            errors.append(
                f"Name '{name}' should be hyphen-case (lowercase letters, digits, and hyphens only)"
            )
        if name.startswith("-") or name.endswith("-") or "--" in name:
            errors.append(
                f"Name '{name}' cannot start/end with hyphen or contain consecutive hyphens"
            )
        if len(name) > MAX_SKILL_NAME_LENGTH:
            errors.append(
                f"Name is too long ({len(name)} characters). Maximum is {MAX_SKILL_NAME_LENGTH} characters."
            )

    description = frontmatter.get("description", "").strip()
    if description:
        if "<" in description or ">" in description:
            errors.append("Description cannot contain angle brackets (< or >)")
        if len(description) > 1024:
            errors.append(
                f"Description is too long ({len(description)} characters). Maximum is 1024 characters."
            )

    seen_references: set[str] = set()
    for match in REFERENCE_PATTERN.finditer(text):
        relative_reference = match.group(1).rstrip("`'\"),.:;]")
        if relative_reference in seen_references:
            continue
        seen_references.add(relative_reference)
        referenced_path = skill_dir / relative_reference
        if not referenced_path.exists():
            errors.append(f"{skill_md} references missing path: {relative_reference}")

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
                errors.append(f"Shell syntax failed for {shell_script}: {detail}")

    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python3 scripts/quick_validate_skill.py <skill_directory>", file=sys.stderr)
        return 1

    input_path = Path(sys.argv[1])
    skill_dir = input_path if input_path.is_absolute() else (ROOT / input_path)
    errors = validate_skill_dir(skill_dir.resolve())

    if errors:
        print("Skill validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("Skill is valid!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
