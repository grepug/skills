#!/usr/bin/env python3
"""Read-only WDA evidence collection; never claims target identity or ownership."""

from __future__ import annotations

import argparse
import datetime as dt
import http.client
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


MAX_BYTES = 1024 * 1024
RELATED = re.compile(r"appium|webdriveragent|wda[_/-]|iphone[_-]use|iproxy|xcodebuild|phone\.py", re.I)
CONFIG_KEYS = ("udid", "local_port", "device_port", "source_dir", "bundle_id")
JOB_KEYS = ("id", "action", "state", "pid", "created_at", "worker_entrypoint", "base_url", "recovery_phase")


def redact(value: str) -> str:
    value = re.sub(r"(?i)((?:--)?(?:password|passwd|token|secret|authorization|api[_-]?key)[=\s:]+)\S+", r"\1[redacted]", value)
    value = re.sub(r"https?://[^/\s@]+@", "http://[redacted]@", value)
    return re.sub(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", "[redacted email]", value)


def run_command(argv: list[str]) -> tuple[str, str | None]:
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=8, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        return "", redact(str(error))
    # lsof uses 1 with empty stdout/stderr when there are no matching sockets.
    empty_lsof = argv[0] == "lsof" and result.returncode == 1 and not result.stdout and not result.stderr
    if result.returncode and not empty_lsof:
        return result.stdout, redact(result.stderr.strip() or f"exit {result.returncode}")
    return result.stdout, None


def parse_processes(raw: str) -> list[dict]:
    processes = []
    for line in raw.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
            processes.append({"pid": int(parts[0]), "ppid": int(parts[1]), "command": redact(parts[2])})
    return processes


def parse_listeners(raw: str) -> list[dict]:
    listeners = []
    pid, command = None, ""
    for line in raw.splitlines():
        if line.startswith("p") and line[1:].isdigit():
            pid, command = int(line[1:]), ""
        elif line.startswith("c"):
            command = line[1:]
        elif line.startswith("n") and pid is not None:
            match = re.search(r":(\d+)$", line[1:])
            if match:
                listeners.append({"pid": pid, "command": command, "address": line[1:], "port": int(match[1])})
    return listeners


def read_json(path: Path) -> dict:
    with path.open("rb") as stream:
        raw = stream.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError("JSON exceeds 1 MiB")
    document = json.loads(raw)
    if not isinstance(document, dict):
        raise ValueError("expected JSON object")
    return document


def read_runtime(directory: Path) -> dict:
    evidence = {"directory": str(directory), "config": {}, "jobs": [], "errors": []}
    try:
        config = read_json(directory / "config.json")
        evidence["config"] = {key: config[key] for key in CONFIG_KEYS if key in config}
    except (OSError, ValueError) as error:
        evidence["errors"].append(redact(f"config: {error}"))
    try:
        jobs = sorted((directory / "jobs").glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
        evidence["jobs_truncated"] = len(jobs) > 50
        for path in jobs[:50]:
            try:
                job = read_json(path)
                selected = {key: job[key] for key in JOB_KEYS if key in job}
                selected["file"] = str(path)
                selected["config"] = {key: job["config"][key] for key in CONFIG_KEYS if key in job.get("config", {})} if isinstance(job.get("config"), dict) else {}
                evidence["jobs"].append(selected)
            except (OSError, ValueError) as error:
                evidence["errors"].append(redact(f"job {path.name}: {error}"))
    except OSError as error:
        evidence["errors"].append(redact(f"jobs: {error}"))
    evidence["records_are_not_live_proof"] = True
    return evidence


def endpoint_url(value: str) -> str:
    parsed = urllib.parse.urlsplit(value)
    if (parsed.scheme != "http" or parsed.hostname not in {"localhost", "127.0.0.1", "::1"}
            or parsed.username or parsed.password or parsed.query or parsed.fragment):
        raise ValueError("endpoint must be an HTTP loopback URL without credentials, query or fragment")
    if parsed.port is None or not 1 <= parsed.port <= 65535:
        raise ValueError("endpoint requires an explicit port in 1..65535")
    return value.rstrip("/")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def probe_endpoint(url: str) -> dict:
    url = endpoint_url(url)
    result = {"url": url, "identity_verified": False, "ownership_verified": False}
    # Ignore ambient proxy configuration and refuse redirects away from loopback.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(url + "/status", timeout=2) as response:
            raw = response.read(MAX_BYTES + 1)
            result["http_status"] = response.status
        if len(raw) > MAX_BYTES:
            raise ValueError("status exceeds 1 MiB")
        document = json.loads(raw)
        if not isinstance(document, dict):
            raise ValueError("status is not a JSON object")
        result["status"] = document
    except (OSError, ValueError, urllib.error.URLError, http.client.HTTPException) as error:
        result["error"] = redact(str(error))
    return result


def configured_conflicts(runtimes: list[dict]) -> list[dict]:
    by_port: dict[int, list[dict]] = {}
    for runtime in runtimes:
        config = runtime["config"]
        port = config.get("local_port")
        if isinstance(port, int) and not isinstance(port, bool):
            by_port.setdefault(port, []).append({"directory": runtime["directory"], "udid": config.get("udid")})
    return [{"port": port, "claims": claims} for port, claims in sorted(by_port.items()) if len(claims) > 1]


def collect(state_dirs: list[Path], endpoints: list[str]) -> dict:
    errors = []
    raw_processes, error = run_command(["ps", "-ax", "-o", "pid=,ppid=,command="])
    if error:
        errors.append({"source": "ps", "error": error})
    all_processes = parse_processes(raw_processes)
    runtimes = [read_runtime(path) for path in state_dirs]
    ports = {urllib.parse.urlsplit(url).port for url in endpoints}
    ports.update(runtime["config"].get("local_port") for runtime in runtimes if isinstance(runtime["config"].get("local_port"), int))
    related_pids = {process["pid"] for process in all_processes if RELATED.search(process["command"])}
    raw_listeners, error = run_command(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"])
    if error:
        errors.append({"source": "lsof", "error": error})
    listeners = [item for item in parse_listeners(raw_listeners) if item["pid"] in related_pids or item["port"] in ports or RELATED.search(item["command"])]
    selected_pids = related_pids | {item["pid"] for item in listeners}
    selected_pids.update(process["ppid"] for process in all_processes if process["pid"] in selected_pids)
    processes = [process for process in all_processes if process["pid"] in selected_pids]
    probes = [probe_endpoint(url) for url in endpoints]
    return {
        "schema_version": 1,
        "observed_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "read_only": True,
        "identity_verified": False,
        "ownership_verified": False,
        "processes": processes,
        "listeners": listeners,
        "runtimes": runtimes,
        "configured_port_conflicts": configured_conflicts(runtimes),
        "endpoints": probes,
        "collection_errors": errors,
        "limitations": "Snapshot only; persisted claims and healthy endpoints do not prove UDID binding or task ownership. Listener visibility depends on permissions. No sessions created.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", action="append", default=[], help="Existing runtime directory; repeat to inspect multiple")
    parser.add_argument("--endpoint", action="append", default=[], help="Explicit loopback base URL to GET /status; maximum 8")
    parser.add_argument("--output", type=Path, help="New JSON report file, created with mode 600; refuses overwrite")
    args = parser.parse_args()
    try:
        endpoints = list(dict.fromkeys(endpoint_url(url) for url in args.endpoint))
        if len(endpoints) > 8:
            raise ValueError("at most 8 endpoints may be probed")
    except ValueError as error:
        parser.error(str(error))
    if args.state_dir:
        state_dirs = [Path(path).expanduser().resolve() for path in args.state_dir]
    else:
        candidates = [Path.home() / ".local/share/iphone-use", Path.home() / ".local/share/iphone-use-wda"]
        state_dirs = [path for path in candidates if path.exists()]
    report = collect(list(dict.fromkeys(state_dirs)), endpoints)
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        try:
            fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as stream:
                stream.write(encoded)
        except OSError as error:
            print(redact(str(error)), file=sys.stderr)
            return 1
        print(str(args.output.resolve()))
    else:
        print(encoded, end="")
    incomplete = report["collection_errors"] or any(item["errors"] for item in report["runtimes"]) or any("error" in item for item in report["endpoints"])
    return 2 if incomplete else 0


if __name__ == "__main__":
    raise SystemExit(main())
