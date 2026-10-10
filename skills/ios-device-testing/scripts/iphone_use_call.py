#!/usr/bin/env python3
"""Call an installed iPhone use Runtime with JSON file arguments, preserving its guards."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


def reject_constant(value: str):
    raise ValueError(f"Non-finite JSON value: {value}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin-root", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--arguments-file", type=Path, required=True)
    parser.add_argument("tool", help="Actual pua_* tool name from the installed plugin schema")
    args = parser.parse_args()
    runtime = None
    try:
        document = json.loads(args.arguments_file.read_text(), parse_constant=reject_constant)
        if not isinstance(document, dict):
            raise ValueError("arguments file must contain a JSON object")
        plugin_root = args.plugin_root.expanduser().resolve()
        if not (plugin_root / "server/iphone_use.py").is_file():
            raise ValueError("plugin root has no server/iphone_use.py; inspect the installed version")
        sys.path.insert(0, str(plugin_root / "server"))
        from iphone_use import PUAError, Runtime, SCHEMAS

        if not args.tool.startswith("pua_") or args.tool[4:] not in SCHEMAS:
            raise ValueError("tool is not present in the installed plugin schema")
        try:
            runtime = Runtime(str(args.state_dir.expanduser().resolve()), args.url)
            result = runtime.call(args.tool, document)
        except PUAError as error:
            result = {"error": error.as_dict()}
    except (OSError, ValueError, ImportError) as error:
        result = {"error": {"code": "local_call_failed", "message": str(error)}}
    finally:
        if runtime is not None:
            runtime.close()
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    if "error" in result or result.get("ok") is False:
        return 1
    return 1 if args.tool == "pua_ready" and result.get("ready") is not True else 0


if __name__ == "__main__":
    raise SystemExit(main())
