#!/usr/bin/env python3
"""Call an installed iPhone use Runtime with JSON file arguments, preserving its guards."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time


def reject_constant(value: str):
    raise ValueError(f"Non-finite JSON value: {value}")


def invoke(runtime, tool, arguments, pua_error):
    try:
        return runtime.call(tool, arguments)
    except pua_error as error:
        return {"error": error.as_dict()}
    except Exception as error:
        # Runtime can fail while persisting its session after the device action.
        return {"error": {"code": "local_call_failed", "message": str(error), "uncertain": True}}


def progress_without_token(result):
    progress = {key: value for key, value in result.items() if key not in {"continue_token", "next_step"}}
    progress["next_step"] = "Read the actual field before doing anything else; enter only confirmed missing text with replace=false. Do not resend the original text or use a token from this closed process."
    return progress


def finish_input(runtime, result, pua_error):
    # Continuation plans live only in this Runtime's memory. Consume tokens here,
    # never hand a still-pending token to a later CLI process.
    deadline = time.monotonic() + 600
    continuations = 0
    while result.get("input_complete") is False and "error" not in result:
        previous = result
        token = previous.get("continue_token")
        if not isinstance(token, str) or not token or continuations >= 64 or time.monotonic() >= deadline:
            result = progress_without_token(previous)
            result["error"] = {"code": "input_continuation_stopped", "message": "Input remains incomplete; continuation token is missing or the local continuation budget ended.", "uncertain": True}
            break
        result = invoke(runtime, "pua_type_text", {"continue_token": token}, pua_error)
        continuations += 1
        if "error" in result:
            result["input_progress"] = progress_without_token(previous)
    return result


def call_operation(runtime, tool, arguments, pua_error):
    result = invoke(runtime, tool, arguments, pua_error)
    if tool == "pua_type_text":
        return finish_input(runtime, result, pua_error)
    if tool != "pua_batch" or result.get("stop_reason") != "input_continues" or "error" in result:
        return result
    results = result.get("results", [])
    index = result.get("stopped_at")
    if not results or not isinstance(index, int):
        return {"error": {"code": "invalid_batch_progress", "message": "Cannot locate pending input; read actual device state before continuing.", "uncertain": True}, "batch_progress": result}
    final_input = finish_input(runtime, results[-1], pua_error)
    result["results"] = results[:-1] + [final_input]
    if "error" in final_input:
        result["error"] = final_input["error"]
        result["stop_reason"] = final_input["error"].get("code", "input_failed")
        result["next_step"] = "Read the actual input field and the failed step; do not replay completed steps or the original input."
        return result
    result["completed_steps"] = index + 1
    if final_input.get("submitted") and not final_input.get("submission_verified"):
        result["stop_reason"] = "submission_requires_verification"
        result["next_step"] = "Verify the submission result before continuing; do not submit again."
    elif index + 1 == len(arguments.get("steps", [])):
        result["complete"] = True
        for key in ("stopped_at", "stop_reason", "next_step"):
            result.pop(key, None)
    else:
        result["stop_reason"] = "input_completed"
        result["next_step"] = "Input at stopped_at is complete. Send only the steps after stopped_at; do not repeat completed steps."
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin-root", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--arguments-file", type=Path, required=True)
    parser.add_argument("tool", help="Actual pua_* tool name from the installed plugin schema")
    args = parser.parse_args()
    runtime = None
    result = None
    call_started = False
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
        except PUAError as error:
            result = {"error": error.as_dict()}
        else:
            call_started = True
            result = call_operation(runtime, args.tool, document, PUAError)
    except Exception as error:
        detail = {"code": "local_call_failed", "message": str(error), "uncertain": call_started}
        if not call_started:
            detail["action_executed"] = False
        result = {"error": detail}
    finally:
        if runtime is not None:
            try:
                runtime.close()
            except Exception as error:
                # A cleanup error cannot replace the action's original evidence.
                result["cleanup_error"] = {"message": str(error)}
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    if "error" in result or "cleanup_error" in result or result.get("ok") is False:
        return 1
    return 1 if args.tool == "pua_ready" and result.get("ready") is not True else 0


if __name__ == "__main__":
    raise SystemExit(main())
