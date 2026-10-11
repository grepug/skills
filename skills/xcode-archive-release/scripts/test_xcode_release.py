#!/usr/bin/env python3
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("xcode-release.sh")


class XcodeReleaseScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.stubs = self.root / "stubs"
        self.stubs.mkdir()
        self.asc_log = self.root / "asc.log"
        self.ipa_server_log = self.root / "ipa-server.log"
        self.ipa_server_helper = self.root / "ipa_server.py"
        self.app_dir = self.root / "app"
        self.app_dir.mkdir()
        self.project = self.app_dir / "Demo.xcodeproj"
        self.project.mkdir()
        self.info_plist = self.app_dir / "Info.plist"
        self._write_project()
        self._write_stubs()
        self._init_git_repo()
        (self.app_dir / ".env").write_text("IPA_SERVER_URL=https://ipa.from.env\n")

    def tearDown(self):
        self.tmp.cleanup()

    def _write_project(self):
        (self.project / "project.pbxproj").write_text(
            textwrap.dedent(
                """
                    MARKETING_VERSION = 0.1.0;
                    CURRENT_PROJECT_VERSION = 1;
                    INFOPLIST_FILE = Info.plist;
                """
            ).strip()
            + "\n"
        )
        with self.info_plist.open("wb") as handle:
            plistlib.dump(
                {
                    "CFBundleIdentifier": "com.example.demo",
                    "CFBundleShortVersionString": "0.1.0",
                    "CFBundleVersion": "1",
                },
                handle,
            )

    def _write_stubs(self):
        self._write_executable(
            "asc",
            r"""#!/usr/bin/env bash
set -euo pipefail
echo "ASC $*" >> "$ASC_STUB_LOG"

if [[ "${1:-}" == "version" ]]; then
  echo "0.45.3-test"
  exit 0
fi

if [[ "${1:-}" == "signing" && "${2:-}" == "fetch" ]]; then
  output="./signing"
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--output" ]]; then
      output="$2"
      shift 2
    else
      shift
    fi
  done
  mkdir -p "$output"
  printf 'profile' > "$output/profile.mobileprovision"
  printf 'cert' > "$output/cert.cer"
  exit 0
fi

if [[ "${1:-}" == "xcode" && "${2:-}" == "archive" ]]; then
  archive=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--archive-path" ]]; then
      archive="$2"
      shift 2
    else
      shift
    fi
  done
  mkdir -p "$archive"
  exit 0
fi

if [[ "${1:-}" == "xcode" && "${2:-}" == "export" ]]; then
  ipa=""
  export_options=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ipa-path) ipa="$2"; shift 2 ;;
      --export-options) export_options="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -n "$ipa" ]] && ! grep -q '<string>upload</string>' "$export_options"; then
    mkdir -p "$(dirname "$ipa")"
    printf 'ipa' > "$ipa"
  fi
  exit 0
fi

if [[ "${1:-}" == "publish" && "${2:-}" == "appstore" ]]; then
  exit 0
fi

exit 0
""",
        )
        self._write_executable(
            "xcodebuildmcp",
            """#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "xcodebuildmcp-test"
  exit 0
fi
if [[ "${1:-}" == "project-discovery" && "${2:-}" == "list-schemes" ]]; then
  echo "Schemes:"
  echo "  Demo"
  exit 0
fi
if [[ "${1:-}" == "device" && "${2:-}" == "build" ]]; then
  json=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--json" ]]; then
      json="$2"
      shift 2
    else
      shift
    fi
  done
  derived="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["derivedDataPath"])' "$json")"
  app="$derived/Build/Products/Debug-iphoneos/Demo.app"
  mkdir -p "$app"
  printf 'binary' > "$app/Demo"
  printf 'profile' > "$app/embedded.mobileprovision"
  python3 - "$app/Info.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as handle:
    plistlib.dump(
        {
            "CFBundleIdentifier": "com.example.demo",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "50",
        },
        handle,
    )
PY
  echo '{"data":{"summary":{"status":"SUCCEEDED"},"artifacts":{"buildLogPath":"device.log"}}}'
  exit 0
fi
if [[ "${1:-}" == "device" && "${2:-}" == "get-app-path" ]]; then
  derived=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--derived-data-path" ]]; then
      derived="$2"
      shift 2
    else
      shift
    fi
  done
  printf '{"data":{"artifacts":{"appPath":"%s/Build/Products/Debug-iphoneos/Demo.app"}}}\n' "$derived"
  exit 0
fi
exit 0
""",
        )
        self._write_executable(
            "security",
            """#!/usr/bin/env bash
if [[ "${1:-}" == "find-identity" ]]; then
  if [[ "${SIGNING_IDENTITY:-1}" == "0" ]]; then
    echo "  0 valid identities found"
  else
    echo '  1) ABCDEF1234567890ABCDEF1234567890ABCDEF12 "Apple Distribution: Example"'
  fi
  exit 0
fi
if [[ "${1:-}" == "import" ]]; then
  echo "security import $*" >> "$ASC_STUB_LOG"
  exit 0
fi
exit 0
""",
        )
        self.ipa_server_helper.write_text(
            """#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["IPA_SERVER_STUB_LOG"], "a", encoding="utf-8") as handle:
    handle.write("IPA_SERVER " + " ".join(args) + "\\n")

if "list" in args:
    print("[]")
    raise SystemExit(0)

if "upload" in args:
    ipa = args[args.index("--ipa") + 1]
    project = args[args.index("--project") + 1]
    version = args[args.index("--version") + 1]
    build = args[args.index("--build-number") + 1]
    bundle = args[args.index("--bundle-id") + 1]
    if not os.path.isfile(ipa):
        raise SystemExit(f"IPA does not exist: {ipa}")
    print(json.dumps({
        "id": "stub-build",
        "project": project,
        "version": version,
        "buildNumber": build,
        "bundleId": bundle,
        "createdAt": "2026-06-07T00:00:00.000Z",
        "installUrl": "itms-services://stub",
        "downloadUrl": "https://ipa.test/downloads/stub-build.ipa",
    }))
    raise SystemExit(0)

raise SystemExit("unsupported ipa server command")
"""
        )
        self.ipa_server_helper.chmod(0o755)

    def _write_executable(self, name, content):
        path = self.stubs / name
        path.write_text(content)
        path.chmod(0o755)

    def _init_git_repo(self):
        remote = self.root / "remote.git"
        subprocess.run(["git", "init", "--bare", str(remote)], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["git", "init"], cwd=self.app_dir, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=self.app_dir, check=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=self.app_dir, check=True)
        subprocess.run(["git", "add", "."], cwd=self.app_dir, check=True)
        subprocess.run(["git", "commit", "-m", "initial"], cwd=self.app_dir, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["git", "remote", "add", "origin", str(remote)], cwd=self.app_dir, check=True)

    def env(self, **overrides):
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.stubs}:{env['PATH']}",
                "HOME": str(self.home),
                "ASC_STUB_LOG": str(self.asc_log),
                "IPA_SERVER_STUB_LOG": str(self.ipa_server_log),
            }
        )
        env.update(overrides)
        return env

    def run_release(self, *args, env=None):
        command = [
            "bash",
            str(SCRIPT),
            "--project",
            str(self.project),
            "--scheme",
            "Demo",
            "--app",
            "123456789",
            "--bundle-id",
            "com.example.demo",
            *args,
        ]
        return subprocess.run(
            command,
            cwd=self.app_dir,
            env=env or self.env(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

    def asc_commands(self):
        if not self.asc_log.exists():
            return ""
        return self.asc_log.read_text()

    def ipa_server_commands(self):
        if not self.ipa_server_log.exists():
            return ""
        return self.ipa_server_log.read_text()

    def test_direct_upload_refreshes_signing_archives_exports_and_tags(self):
        result = self.run_release("--version", "1.2.3", "--build", "42")

        self.assertEqual(result.returncode, 0, result.stdout)
        commands = self.asc_commands()
        self.assertIn("ASC signing fetch", commands)
        self.assertIn("--profile-type IOS_APP_STORE", commands)
        self.assertIn("ASC xcode archive", commands)
        self.assertIn("--xcodebuild-flag=-allowProvisioningUpdates", commands)
        self.assertIn("ASC xcode export", commands)
        self.assertIn("--wait", commands)
        installed_profile = self.home / "Library/MobileDevice/Provisioning Profiles/profile.mobileprovision"
        self.assertTrue(installed_profile.exists())
        tag = subprocess.run(
            ["git", "ls-remote", "--tags", "origin", "refs/tags/v1.2.3-42"],
            cwd=self.app_dir,
            text=True,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
        self.assertIn("refs/tags/v1.2.3-42", tag)

    def test_publish_path_exports_local_ipa_and_does_not_submit(self):
        result = self.run_release("--version", "1.2.3", "--build", "43", "--release-path", "publish")

        self.assertEqual(result.returncode, 0, result.stdout)
        commands = self.asc_commands()
        self.assertIn("ASC xcode export", commands)
        self.assertIn("ExportOptions-AppStore-Local.plist", commands)
        self.assertIn("ASC publish appstore", commands)
        self.assertIn("--platform IOS", commands)
        self.assertNotIn("--submit", commands)

    def test_missing_bundle_id_fails_when_signing_refresh_enabled(self):
        command = [
            "bash",
            str(SCRIPT),
            "--project",
            str(self.project),
            "--scheme",
            "Demo",
            "--app",
            "123456789",
            "--version",
            "1.2.3",
            "--build",
            "44",
        ]
        result = subprocess.run(
            command,
            cwd=self.app_dir,
            env=self.env(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--bundle-id is required", result.stdout)

    def test_no_signing_identity_fails_before_archive(self):
        result = self.run_release(
            "--version",
            "1.2.3",
            "--build",
            "45",
            env=self.env(SIGNING_IDENTITY="0"),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No usable code signing identity found", result.stdout)
        self.assertNotIn("ASC xcode archive", self.asc_commands())

    def test_duplicate_local_tag_fails_after_upload_without_moving_tag(self):
        subprocess.run(
            ["git", "tag", "-a", "v1.2.3-46", "-m", "existing"],
            cwd=self.app_dir,
            check=True,
        )

        result = self.run_release("--version", "1.2.3", "--build", "46")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Release tag already exists locally", result.stdout)
        self.assertIn("ASC xcode export", self.asc_commands())

    def test_completion_marker_skips_completed_platform_on_retry(self):
        first = self.run_release("--version", "1.2.3", "--build", "47")
        self.assertEqual(first.returncode, 0, first.stdout)
        self.asc_log.write_text("")

        second = self.run_release("--version", "1.2.3", "--build", "47")

        self.assertEqual(second.returncode, 0, second.stdout)
        self.assertIn("already completed", second.stdout)
        self.assertEqual(self.asc_commands(), "")

    def test_force_rebuild_passes_overwrite(self):
        first = self.run_release("--version", "1.2.3", "--build", "48")
        self.assertEqual(first.returncode, 0, first.stdout)
        self.asc_log.write_text("")

        second = self.run_release("--version", "1.2.3", "--build", "48", "--force")

        self.assertNotEqual(second.returncode, 0)
        self.assertIn("Release tag already exists", second.stdout)
        self.assertIn("--overwrite", self.asc_commands())

    def test_mac_catalyst_platform_mapping(self):
        result = self.run_release("--version", "1.2.3", "--build", "49", "--platform", "mac_catalyst")

        self.assertEqual(result.returncode, 0, result.stdout)
        commands = self.asc_commands()
        self.assertIn("--profile-type MAC_CATALYST_APP_STORE", commands)
        self.assertIn("--xcodebuild-flag=generic/platform=iOS", commands)
        self.assertIn("--xcodebuild-flag=SUPPORTS_MACCATALYST=YES", commands)

    def test_ipa_server_path_builds_packages_uploads_without_appstore_tag(self):
        result = self.run_release(
            "--version",
            "1.2.3",
            "--build",
            "50",
            "--release-path",
            "ipa_server",
            "--ipa-server-url",
            "https://ipa.test",
            "--ipa-server-helper",
            str(self.ipa_server_helper),
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Skipping release tag creation for ipa_server path", result.stdout)
        self.assertNotIn("ASC xcode archive", self.asc_commands())
        self.assertNotIn("ASC xcode export", self.asc_commands())
        commands = self.ipa_server_commands()
        self.assertIn("IPA_SERVER --server https://ipa.test upload", commands)
        self.assertIn("--project Demo", commands)
        self.assertIn("--bundle-id com.example.demo", commands)
        ipa = self.home / ".xcode-archive/Demo/1.2.3-50/export-ios/Demo-ios.ipa"
        self.assertTrue(ipa.exists())
        listing = subprocess.run(
            ["unzip", "-l", str(ipa)],
            text=True,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
        self.assertIn("Payload/Demo.app/embedded.mobileprovision", listing)
        tag = subprocess.run(
            ["git", "ls-remote", "--tags", "origin", "refs/tags/v1.2.3-50"],
            cwd=self.app_dir,
            text=True,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
        self.assertEqual(tag, "")

    def test_ipa_server_requires_server_url(self):
        (self.app_dir / ".env").unlink()
        result = self.run_release(
            "--version",
            "1.2.3",
            "--build",
            "51",
            "--release-path",
            "ipa_server",
            "--ipa-server-helper",
            str(self.ipa_server_helper),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--ipa-server-url is required", result.stdout)

    def test_ipa_server_reads_server_url_from_project_env(self):
        result = self.run_release(
            "--version",
            "1.2.3",
            "--build",
            "52",
            "--release-path",
            "ipa_server",
            "--ipa-server-helper",
            str(self.ipa_server_helper),
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("IPA_SERVER --server https://ipa.from.env upload", self.ipa_server_commands())

    def test_script_has_no_direct_raw_xcodebuild_invocation(self):
        text = SCRIPT.read_text()
        self.assertNotRegex(text, re.compile(r"(?m)^\\s*xcodebuild(\\s|$)"))
        self.assertNotRegex(text, re.compile(r"command -v xcodebuild(\\s|$)"))


if __name__ == "__main__":
    unittest.main()
