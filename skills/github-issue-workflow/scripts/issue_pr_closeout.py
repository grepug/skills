#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent
PR_TEMPLATE_PATH = SKILL_DIR / "assets" / "pull-request-body.md"
CANONICAL_PLAN_MARKER = "**Use this comment for:**"
CHECKLIST_PATTERN = re.compile(r"^[*-]\s*\[( |x|X)\]\s*(.*)$")


@dataclass
class ChecklistItem:
    source: str
    section: str
    text: str
    checked: bool


@dataclass
class AuditResult:
    issue: dict[str, Any]
    plan_comment: dict[str, Any] | None
    issue_items: list[ChecklistItem]
    plan_items: list[ChecklistItem]

    @property
    def open_issue_items(self) -> list[ChecklistItem]:
        return [item for item in self.issue_items if not item.checked and not is_ignorable_item(item)]

    @property
    def open_plan_items(self) -> list[ChecklistItem]:
        return [item for item in self.plan_items if not item.checked and not is_ignorable_item(item)]

    @property
    def blocking_plan_items(self) -> list[ChecklistItem]:
        return [item for item in self.open_plan_items if not is_non_blocking_plan_item(item)]

    @property
    def non_blocking_plan_items(self) -> list[ChecklistItem]:
        return [item for item in self.open_plan_items if is_non_blocking_plan_item(item)]

    @property
    def blockers(self) -> list[str]:
        problems: list[str] = []
        if self.plan_comment is None:
            problems.append("Canonical plan comment not found.")
        if self.open_issue_items:
            problems.append(f"Issue body still has {len(self.open_issue_items)} unchecked checklist item(s).")
        if self.blocking_plan_items:
            problems.append(
                f"Canonical plan comment still has {len(self.blocking_plan_items)} unchecked implementation checklist item(s)."
            )
        return problems


@dataclass
class PullRequestAudit:
    pr: dict[str, Any]
    pr_items: list[ChecklistItem]
    linked_issue: AuditResult
    related_issues: list[AuditResult]

    @property
    def open_pr_items(self) -> list[ChecklistItem]:
        return [item for item in self.pr_items if not item.checked]

    @property
    def blockers(self) -> list[str]:
        problems: list[str] = []
        if self.open_pr_items:
            problems.append(f"PR body still has {len(self.open_pr_items)} unchecked checklist item(s).")
        if not pr_closes_issue(self.pr, self.linked_issue.issue["number"]):
            problems.append(
                f"PR #{self.pr['number']} does not close linked issue #{self.linked_issue.issue['number']}."
            )
        if self.linked_issue.blockers:
            problems.extend(f"Linked issue #{self.linked_issue.issue['number']}: {blocker}" for blocker in self.linked_issue.blockers)
        for related_issue in self.related_issues:
            if related_issue.blockers:
                problems.extend(
                    f"Related issue #{related_issue.issue['number']}: {blocker}" for blocker in related_issue.blockers
                )
        return problems


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Audit GitHub issue checklist state and create or update a PR only after closeout passes.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    for name in ("audit", "pr-body", "open-pr", "merge-pr"):
        subparser = subparsers.add_parser(name)
        add_common_args(subparser)
        if name in {"pr-body", "open-pr"}:
            subparser.add_argument(
                "--summary",
                action="append",
                default=[],
                help="Summary bullet for the PR body. Repeat to add more bullets.",
            )
            subparser.add_argument(
                "--validation",
                action="append",
                default=[],
                help="Validation bullet for the PR body. Repeat to add more bullets.",
            )
            subparser.add_argument(
                "--title",
                help="Explicit PR title. Defaults to the issue title.",
            )
        if name == "open-pr":
            subparser.add_argument("--base", help="Base branch for gh pr create.")
            subparser.add_argument("--head", help="Head branch for gh pr create and gh pr edit.")
            subparser.add_argument("--draft", action="store_true", help="Create the PR as a draft.")
            subparser.add_argument("--dry-run", action="store_true", help="Print the body and planned gh command without creating or editing a PR.")
        if name == "merge-pr":
            subparser.add_argument("--pr", help="PR number, URL, or branch. Defaults to the current branch's PR.")
            subparser.add_argument(
                "--method",
                choices=("merge", "squash", "rebase"),
                default="merge",
                help="Merge strategy to pass to gh pr merge. Defaults to merge.",
            )
            subparser.add_argument(
                "--related-issue",
                action="append",
                default=[],
                help="Extra related issue number or URL to audit before merge. Repeat to add more issues.",
            )
            subparser.add_argument(
                "--delete-branch",
                action="store_true",
                help="Delete the PR branch after a successful merge.",
            )
            subparser.add_argument(
                "--dry-run",
                action="store_true",
                help="Print the merge audit and planned gh command without merging.",
            )

    return parser


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--issue", required=True, help="Issue number or URL.")
    parser.add_argument("--repo", help="Optional owner/repo override for gh commands.")


def gh_command(repo: str | None, *args: str) -> list[str]:
    command = ["gh"]
    if repo:
        command.extend(["--repo", repo])
    command.extend(args)
    return command


def run_command(command: list[str], *, capture_output: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        text=True,
        capture_output=capture_output,
        check=False,
    )


def fetch_issue(issue_ref: str, repo: str | None) -> dict[str, Any]:
    result = run_command(
        gh_command(
            repo,
            "issue",
            "view",
            issue_ref,
            "--json",
            "number,title,body,url,milestone,comments",
        )
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or result.stdout.strip() or "Failed to fetch issue.")
    return json.loads(result.stdout)


def fetch_pr(pr_ref: str, repo: str | None) -> dict[str, Any]:
    result = run_command(
        gh_command(
            repo,
            "pr",
            "view",
            pr_ref,
            "--json",
            "number,title,body,url,isDraft,closingIssuesReferences",
        )
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or result.stdout.strip() or "Failed to fetch PR.")
    return json.loads(result.stdout)


def normalize_comments(raw_comments: Any) -> list[dict[str, Any]]:
    if isinstance(raw_comments, list):
        return [comment for comment in raw_comments if isinstance(comment, dict)]
    if isinstance(raw_comments, dict):
        nodes = raw_comments.get("nodes")
        if isinstance(nodes, list):
            return [comment for comment in nodes if isinstance(comment, dict)]
    return []


def normalize_issue_refs(raw_refs: Any) -> list[dict[str, Any]]:
    if isinstance(raw_refs, list):
        return [issue for issue in raw_refs if isinstance(issue, dict)]
    if isinstance(raw_refs, dict):
        nodes = raw_refs.get("nodes")
        if isinstance(nodes, list):
            return [issue for issue in nodes if isinstance(issue, dict)]
    return []


def find_canonical_plan_comment(issue: dict[str, Any]) -> dict[str, Any] | None:
    for comment in reversed(normalize_comments(issue.get("comments"))):
        body = str(comment.get("body", ""))
        if CANONICAL_PLAN_MARKER in body and "## Checklist" in body:
            return comment
    for comment in reversed(normalize_comments(issue.get("comments"))):
        body = str(comment.get("body", ""))
        if "## Checklist" in body and "## Design" in body:
            return comment
    return None


def parse_checklist(markdown: str, source: str) -> list[ChecklistItem]:
    items: list[ChecklistItem] = []
    section = "Top"
    for raw_line in markdown.splitlines():
        line = raw_line.rstrip()
        if line.startswith("#"):
            heading = line.lstrip("#").strip()
            if heading:
                section = heading
            continue

        stripped = line.strip()
        match = CHECKLIST_PATTERN.match(stripped)
        if match is None:
            continue
        checked = match.group(1).lower() == "x"
        text = match.group(2).strip()
        items.append(ChecklistItem(source=source, section=section, text=text, checked=checked))
    return items


def is_ignorable_item(item: ChecklistItem) -> bool:
    text = item.text.strip().lower()
    if item.section.strip().lower() == "tweaks" and text == "none yet":
        return True
    return False


def is_non_blocking_plan_item(item: ChecklistItem) -> bool:
    return item.source == "plan" and item.section.strip().lower() == "external setup dependencies"


def audit_issue(issue_ref: str, repo: str | None) -> AuditResult:
    issue = fetch_issue(issue_ref, repo)
    plan_comment = find_canonical_plan_comment(issue)
    issue_items = parse_checklist(str(issue.get("body", "")), source="issue")
    plan_items = parse_checklist(str(plan_comment.get("body", "")) if plan_comment else "", source="plan")
    return AuditResult(
        issue=issue,
        plan_comment=plan_comment,
        issue_items=issue_items,
        plan_items=plan_items,
    )


def parse_issue_number(issue_ref: str) -> int | None:
    ref = issue_ref.strip()
    if ref.isdigit():
        return int(ref)
    match = re.search(r"/issues/(\d+)$", ref)
    if match:
        return int(match.group(1))
    return None


def pr_closes_issue(pr: dict[str, Any], issue_number: int) -> bool:
    for issue in normalize_issue_refs(pr.get("closingIssuesReferences")):
        if issue.get("number") == issue_number:
            return True
    return False


def resolve_pr_reference(pr_ref: str | None, repo: str | None) -> str:
    if pr_ref:
        return pr_ref

    branch = current_branch()
    existing_pr = find_existing_pr(branch, repo)
    if existing_pr is None:
        raise SystemExit(f"No PR found for current branch '{branch}'.")
    return str(existing_pr["number"])


def collect_related_issue_refs(
    pr: dict[str, Any],
    primary_issue_number: int,
    extra_issue_refs: list[str],
) -> list[str]:
    seen: set[int] = {primary_issue_number}
    refs: list[str] = []

    for issue in normalize_issue_refs(pr.get("closingIssuesReferences")):
        number = issue.get("number")
        if isinstance(number, int) and number not in seen:
            seen.add(number)
            refs.append(str(number))

    for issue_ref in extra_issue_refs:
        number = parse_issue_number(issue_ref)
        if number is None:
            refs.append(issue_ref)
            continue
        if number in seen:
            continue
        seen.add(number)
        refs.append(str(number))

    return refs


def audit_pr_merge(
    issue_ref: str,
    repo: str | None,
    pr_ref: str | None,
    extra_related_issue_refs: list[str],
) -> PullRequestAudit:
    linked_issue = audit_issue(issue_ref, repo)
    pr = fetch_pr(resolve_pr_reference(pr_ref, repo), repo)
    pr_items = parse_checklist(str(pr.get("body", "")), source="pr")

    primary_issue_number = int(linked_issue.issue["number"])
    related_issue_refs = collect_related_issue_refs(pr, primary_issue_number, extra_related_issue_refs)
    related_issues = [audit_issue(related_issue_ref, repo) for related_issue_ref in related_issue_refs]

    return PullRequestAudit(
        pr=pr,
        pr_items=pr_items,
        linked_issue=linked_issue,
        related_issues=related_issues,
    )


def format_items(items: list[ChecklistItem]) -> str:
    lines = [f"- [{item.section}] {item.text}" for item in items]
    return "\n".join(lines)


def render_lines(values: list[str], fallback: str) -> str:
    if values:
        return "\n".join(f"- {value}" for value in values)
    return f"- {fallback}"


def plan_comment_link(issue: dict[str, Any], plan_comment: dict[str, Any] | None) -> str:
    if plan_comment is None:
        return "Missing canonical plan comment"
    if plan_comment.get("url"):
        return str(plan_comment["url"])
    comment_id = plan_comment.get("id")
    if comment_id:
        return f"{issue['url']}#issuecomment-{comment_id}"
    return issue["url"]


def render_pr_body(audit: AuditResult, summaries: list[str], validations: list[str]) -> str:
    template = PR_TEMPLATE_PATH.read_text(encoding="utf-8")
    summary_lines = render_lines(
        summaries,
        f"Implements the scope captured in #{audit.issue['number']}: {audit.issue['title']}",
    )
    validation_lines = render_lines(
        validations,
        "Validation details not recorded yet.",
    )
    replacements = {
        "{{SUMMARY_LINES}}": summary_lines,
        "{{CLOSES_LINE}}": f"Closes #{audit.issue['number']}",
        "{{ISSUE_OPEN_COUNT}}": str(len(audit.open_issue_items)),
        "{{PLAN_BLOCKING_OPEN_COUNT}}": str(len(audit.blocking_plan_items)),
        "{{PLAN_NON_BLOCKING_OPEN_COUNT}}": str(len(audit.non_blocking_plan_items)),
        "{{PLAN_COMMENT_LINK}}": plan_comment_link(audit.issue, audit.plan_comment),
        "{{VALIDATION_LINES}}": validation_lines,
    }

    body = template
    for placeholder, value in replacements.items():
        body = body.replace(placeholder, value)
    return body


def current_branch() -> str:
    result = run_command(["git", "rev-parse", "--abbrev-ref", "HEAD"])
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or result.stdout.strip() or "Failed to determine current git branch.")
    return result.stdout.strip()


def ensure_branch_has_upstream(branch: str) -> None:
    result = run_command(
        ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]
    )
    if result.returncode != 0:
        raise SystemExit(
            f"Current branch '{branch}' is not tracking a remote branch. Push it before running open-pr."
        )


def find_existing_pr(branch: str, repo: str | None) -> dict[str, Any] | None:
    result = run_command(
        gh_command(
            repo,
            "pr",
            "view",
            branch,
            "--json",
            "number,url,title",
        )
    )
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def print_audit(audit: AuditResult) -> None:
    print(f"Issue #{audit.issue['number']}: {audit.issue['title']}")
    if audit.plan_comment is None:
        print("Canonical plan comment: missing")
    else:
        print(f"Canonical plan comment: {plan_comment_link(audit.issue, audit.plan_comment)}")
    print(f"Issue body checklist items: {len(audit.issue_items)} total, {len(audit.open_issue_items)} open")
    print(
        "Plan comment checklist items: "
        f"{len(audit.plan_items)} total, "
        f"{len(audit.open_plan_items)} open, "
        f"{len(audit.blocking_plan_items)} blocking"
    )

    if audit.open_issue_items:
        print("\nOpen issue checklist items:")
        print(format_items(audit.open_issue_items))
    if audit.blocking_plan_items:
        print("\nOpen blocking plan checklist items:")
        print(format_items(audit.blocking_plan_items))
    if audit.non_blocking_plan_items:
        print("\nOpen non-blocking plan checklist items:")
        print(format_items(audit.non_blocking_plan_items))

    if audit.blockers:
        print("\nCloseout blockers:")
        for blocker in audit.blockers:
            print(f"- {blocker}")


def print_merge_audit(audit: PullRequestAudit) -> None:
    linked_issue = audit.linked_issue
    print(f"PR #{audit.pr['number']}: {audit.pr['title']}")
    print(f"PR URL: {audit.pr['url']}")
    print(f"Linked issue #{linked_issue.issue['number']}: {linked_issue.issue['title']}")
    print(f"PR checklist items: {len(audit.pr_items)} total, {len(audit.open_pr_items)} open")

    if audit.open_pr_items:
        print("\nOpen PR checklist items:")
        print(format_items(audit.open_pr_items))

    print("\nLinked issue audit:")
    print_audit(linked_issue)

    for related_issue in audit.related_issues:
        print(f"\nRelated issue audit: #{related_issue.issue['number']} {related_issue.issue['title']}")
        print_audit(related_issue)

    if audit.blockers:
        print("\nMerge blockers:")
        for blocker in audit.blockers:
            print(f"- {blocker}")
        print("\nNext steps:")
        print("- Finish the work behind each unchecked item, or rewrite/remove stale checklist items before retrying merge.")
        print("- Re-run merge-pr after the PR, linked issue, and related issue state all agree.")


def open_or_update_pr(
    audit: AuditResult,
    repo: str | None,
    title: str | None,
    summaries: list[str],
    validations: list[str],
    base: str | None,
    head: str | None,
    draft: bool,
    dry_run: bool,
) -> None:
    if audit.blockers:
        print_audit(audit)
        raise SystemExit(1)

    pr_title = title or str(audit.issue["title"])
    pr_body = render_pr_body(audit, summaries, validations)
    head_branch = head or current_branch()
    existing_pr = find_existing_pr(head_branch, repo)
    milestone = audit.issue.get("milestone") or {}
    milestone_title = milestone.get("title")
    create_command = gh_command(
        repo,
        "pr",
        "create",
        "--title",
        pr_title,
        "--body-file",
        "<tempfile>",
        "--head",
        head_branch,
    )
    if base:
        create_command.extend(["--base", base])
    if draft:
        create_command.append("--draft")
    if milestone_title:
        create_command.extend(["--milestone", str(milestone_title)])

    if dry_run:
        if existing_pr:
            print(f"Would update PR #{existing_pr['number']} for branch {head_branch}")
        else:
            print(f"Would create PR for branch {head_branch}")
        print(f"Title: {pr_title}")
        if not existing_pr:
            print(f"Command: {' '.join(create_command)}")
        print("\nBody:\n")
        print(pr_body)
        return

    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as handle:
        handle.write(pr_body)
        body_path = Path(handle.name)

    try:
        if existing_pr:
            command = gh_command(
                repo,
                "pr",
                "edit",
                str(existing_pr["number"]),
                "--title",
                pr_title,
                "--body-file",
                str(body_path),
            )
            if milestone_title:
                command.extend(["--milestone", str(milestone_title)])
            result = run_command(command)
            if result.returncode != 0:
                raise SystemExit(result.stderr.strip() or result.stdout.strip() or "Failed to update PR.")
            print(result.stdout.strip() or f"Updated PR #{existing_pr['number']}")
            return

        if head is None:
            ensure_branch_has_upstream(head_branch)
        command = create_command.copy()
        command[command.index("<tempfile>")] = str(body_path)
        result = run_command(command)
        if result.returncode != 0:
            raise SystemExit(result.stderr.strip() or result.stdout.strip() or "Failed to create PR.")
        print(result.stdout.strip())
    finally:
        body_path.unlink(missing_ok=True)


def merge_pull_request(
    audit: PullRequestAudit,
    repo: str | None,
    method: str,
    delete_branch: bool,
    dry_run: bool,
) -> None:
    merge_command = gh_command(
        repo,
        "pr",
        "merge",
        str(audit.pr["number"]),
        f"--{method}",
    )
    if delete_branch:
        merge_command.append("--delete-branch")

    if dry_run:
        print_merge_audit(audit)
        print("\nWould run:")
        print(" ".join(merge_command))
        return

    result = run_command(merge_command)
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or result.stdout.strip() or "Failed to merge PR.")
    print(result.stdout.strip())


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "merge-pr":
        merge_audit = audit_pr_merge(args.issue, args.repo, args.pr, args.related_issue)
        if merge_audit.blockers:
            print_merge_audit(merge_audit)
            return 1
        merge_pull_request(
            audit=merge_audit,
            repo=args.repo,
            method=args.method,
            delete_branch=args.delete_branch,
            dry_run=args.dry_run,
        )
        return 0

    audit = audit_issue(args.issue, args.repo)

    if args.command == "audit":
        print_audit(audit)
        return 0 if not audit.blockers else 1

    if audit.blockers:
        print_audit(audit)
        return 1

    if args.command == "pr-body":
        print(render_pr_body(audit, args.summary, args.validation))
        return 0

    open_or_update_pr(
        audit=audit,
        repo=args.repo,
        title=args.title,
        summaries=args.summary,
        validations=args.validation,
        base=args.base,
        head=args.head,
        draft=args.draft,
        dry_run=args.dry_run,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
