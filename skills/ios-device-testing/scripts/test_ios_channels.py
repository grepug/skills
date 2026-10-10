#!/usr/bin/env python3
"""Check multi-instance evidence boundaries without a phone, WDA or Appium installation."""

from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import unittest
from unittest.mock import patch

import wda_inventory as inventory


CALL_SCRIPT = Path(__file__).with_name("iphone_use_call.py")


class InventoryTests(unittest.TestCase):
    def test_multiple_listeners_include_ipv6_and_same_port_distinct_processes(self):
        raw = "p101\ncnode\nn127.0.0.1:18100\np102\ncRunner\nn[::1]:18200\nn*:19200\np103\ncnode\nn127.0.0.1:18100\n"
        listeners = inventory.parse_listeners(raw)
        self.assertEqual([(x["pid"], x["port"]) for x in listeners], [(101, 18100), (102, 18200), (102, 19200), (103, 18100)])

    def test_conflicting_configs_are_claims_without_identity_or_ownership(self):
        with tempfile.TemporaryDirectory() as temporary:
            paths = []
            for name, udid in (("a", "PHONE-A"), ("b", "PHONE-B")):
                directory = Path(temporary) / name
                directory.mkdir()
                (directory / "config.json").write_text(json.dumps({"udid": udid, "local_port": 18100, "team_id": "PRIVATE", "password": "PRIVATE"}))
                (directory / "jobs").mkdir()
                (directory / "jobs/job.json").write_text(json.dumps({"id": name, "pid": 99999, "state": "running", "owner_token": "PRIVATE"}))
                paths.append(directory)
            def run(argv):
                if argv[0] == "ps":
                    return "101 1 node wda_usb_forward.js --udid PHONE-B\n500 1 unrelated SECRET\n", None
                return "p101\ncnode\nn127.0.0.1:18100\n", None
            with patch.object(inventory, "run_command", side_effect=run), patch.object(inventory, "probe_endpoint", side_effect=AssertionError("no implicit network probes")):
                report = inventory.collect(paths, [])
            self.assertFalse(report["identity_verified"])
            self.assertFalse(report["ownership_verified"])
            self.assertEqual(len(report["configured_port_conflicts"]), 1)
            self.assertEqual(report["listeners"][0]["pid"], 101)
            self.assertNotIn("PRIVATE", json.dumps(report))
            self.assertNotIn("SECRET", json.dumps(report))
            self.assertTrue(all(runtime["records_are_not_live_proof"] for runtime in report["runtimes"]))

    def test_collection_failure_does_not_become_an_empty_healthy_inventory(self):
        with patch.object(inventory, "run_command", return_value=("", "permission denied")):
            report = inventory.collect([], [])
        self.assertEqual(len(report["collection_errors"]), 2)
        self.assertFalse(report["identity_verified"])

    def test_malformed_runtime_is_reported_and_not_created(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "missing"
            evidence = inventory.read_runtime(directory)
            self.assertTrue(evidence["errors"])
            self.assertFalse(directory.exists())
            directory.mkdir()
            (directory / "config.json").write_text("[]")
            self.assertTrue(inventory.read_runtime(directory)["errors"])

    def test_remote_credentials_query_and_missing_port_are_rejected(self):
        for url in ("http://example.com:8100", "http://127.0.0.1", "http://name:pass@localhost:8100", "http://localhost:8100?next=remote", "file:///tmp/status", "http://localhost:99999"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                inventory.endpoint_url(url)
        self.assertEqual(inventory.endpoint_url("http://[::1]:4723/wd/hub/"), "http://[::1]:4723/wd/hub")

    def test_status_probe_never_creates_session_or_follows_redirects(self):
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                if self.path == "/status":
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b'{"value":{"ready":true}}')
                elif self.path == "/redirect/status":
                    self.send_response(302)
                    self.send_header("Location", "/forbidden")
                    self.end_headers()
                else:
                    self.send_response(500)
                    self.end_headers()
            def log_message(self, *args):
                pass
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}"
            healthy = inventory.probe_endpoint(url)
            redirected = inventory.probe_endpoint(url + "/redirect")
            self.assertTrue(healthy["status"]["value"]["ready"])
            self.assertFalse(healthy["identity_verified"])
            self.assertFalse(healthy["ownership_verified"])
            self.assertIn("error", redirected)
            self.assertEqual(requests, ["/status", "/redirect/status"])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_report_refuses_overwrite_and_uses_private_permissions(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "report.json"
            argv = ["wda_inventory.py", "--output", str(output)]
            with patch.object(sys, "argv", argv), patch.object(inventory, "collect", return_value={"collection_errors": [], "runtimes": [], "endpoints": []}), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(inventory.main(), 0)
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)
                before = output.read_bytes()
                with contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(inventory.main(), 1)
                self.assertEqual(output.read_bytes(), before)

    def test_partial_inventory_is_saved_with_incomplete_exit_code(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "partial.json"
            argv = ["wda_inventory.py", "--state-dir", str(Path(temporary) / "missing"), "--output", str(output)]
            with patch.object(sys, "argv", argv), patch.object(inventory, "run_command", return_value=("", None)), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(inventory.main(), 2)
            report = json.loads(output.read_text())
            self.assertTrue(report["runtimes"][0]["errors"])
            self.assertFalse(report["identity_verified"])


class PuaFileCallTests(unittest.TestCase):
    def make_plugin(self, root):
        server = root / "server"
        server.mkdir()
        # A raw contract fixture; no real plugin or device action is performed.
        (server / "iphone_use.py").write_text('''
import json
from pathlib import Path
SCHEMAS = {"setup": {}, "ready": {}, "tap": {}}
class PUAError(Exception):
    def as_dict(self):
        return {"code": "uncertain_action", "uncertain": True, "action_executed": True}
class Runtime:
    def __init__(self, state_dir, url):
        self.state_dir, self.url = state_dir, url
    def call(self, tool, arguments):
        if tool == "pua_tap":
            raise PUAError()
        if tool == "pua_ready":
            return {"ready": False, "state": "recovering"}
        return {"state_dir": self.state_dir, "url": self.url, "arguments": arguments}
    def close(self):
        pass
''')

    def invoke(self, tool, payload):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_plugin(root)
            argument_file = root / "args.json"
            argument_file.write_text(payload)
            return subprocess.run([sys.executable, str(CALL_SCRIPT), "--plugin-root", str(root), "--state-dir", str(root / "state"), "--url", "http://127.0.0.1:18300", "--arguments-file", str(argument_file), tool], capture_output=True, text=True, check=False)

    def test_file_parameters_preserve_unicode_newlines_and_explicit_runtime(self):
        payload = {"text": "中文\n'\"$()`" * 1000}
        result = self.invoke("pua_setup", json.dumps(payload))
        self.assertEqual(result.returncode, 0, result.stderr)
        response = json.loads(result.stdout)
        self.assertEqual(response["arguments"], payload)
        self.assertEqual(response["url"], "http://127.0.0.1:18300")

    def test_uncertain_action_is_preserved_without_retry(self):
        result = self.invoke("pua_tap", "{}")
        self.assertEqual(result.returncode, 1)
        self.assertTrue(json.loads(result.stdout)["error"]["uncertain"])
        self.assertTrue(json.loads(result.stdout)["error"]["action_executed"])

    def test_recovering_is_not_ready(self):
        result = self.invoke("pua_ready", "{}")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["state"], "recovering")

    def test_bad_json_and_unknown_tool_fail_before_runtime_call(self):
        for tool, payload in (("pua_setup", "[]"), ("pua_setup", "{\"n\":NaN}"), ("pua_setup", "{"), ("pua_missing", "{}")):
            with self.subTest(tool=tool, payload=payload):
                result = self.invoke(tool, payload)
                self.assertEqual(result.returncode, 1)
                self.assertIn("error", json.loads(result.stdout))


if __name__ == "__main__":
    unittest.main()
