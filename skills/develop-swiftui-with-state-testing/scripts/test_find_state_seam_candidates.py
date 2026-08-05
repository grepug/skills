#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("find-state-seam-candidates.sh")


@unittest.skipUnless(shutil.which("rg"), "rg is required by the candidate scanner")
class CandidateScannerTests(unittest.TestCase):
    def run_scanner(self, root: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SCRIPT), str(root)],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_reports_containers_and_separate_application_models(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "CheckoutView.swift").write_text(
                textwrap.dedent(
                    """
                    import SwiftUI

                    struct CheckoutView: View {
                        @Environment(AppModel.self) private var app

                        var body: some View {
                            Button("Checkout") { app.checkoutTapped() }
                        }
                    }
                    """
                ),
                encoding="utf-8",
            )
            (root / "AppModel.swift").write_text(
                textwrap.dedent(
                    """
                    import Observation

                    @MainActor
                    @Observable
                    final class AppModel {
                        private(set) var routes: [Route] = []
                        private(set) var rootState: RootState = .launching

                        func deepLinkReceived(_ url: URL) async {}
                    }
                    """
                ),
                encoding="utf-8",
            )
            (root / "EditorModel.swift").write_text(
                textwrap.dedent(
                    """
                    import Observation

                    @Observable
                    final class EditorModel {
                        var draft = ""
                        private(set) var phase = Phase.editing
                    }
                    """
                ),
                encoding="utf-8",
            )

            result = self.run_scanner(root)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("container candidate:", result.stdout)
            self.assertIn("CheckoutView.swift", result.stdout)
            self.assertIn("application-model candidate:", result.stdout)
            self.assertIn("AppModel.swift", result.stdout)
            self.assertNotIn("EditorModel.swift", result.stdout)

    def test_excludes_tests_and_generated_directories(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for child in (root / "Tests", root / "Generated"):
                child.mkdir()
                (child / "AppModel.swift").write_text(
                    "@Observable final class AppModel { var routes: [Route] = [] }",
                    encoding="utf-8",
                )

            result = self.run_scanner(root)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "No State Seam review candidates found.")

    def test_rejects_a_missing_input_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "Missing"

            result = self.run_scanner(missing)

            self.assertEqual(result.returncode, 2)
            self.assertIn("path does not exist", result.stderr)


if __name__ == "__main__":
    unittest.main()
