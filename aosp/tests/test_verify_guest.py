#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
SERIAL = "127.0.0.1:6520"


class GuestVerifierTest(unittest.TestCase):
    def run_verifier(self, scenario="success", serial=SERIAL, with_apk=True):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        root = Path(work.name)
        apk = root / "demo con espacios.apk"
        apk.write_bytes(b"APK fixture bytes")
        results = root / "results"
        environment = dict(
            os.environ,
            OPENVR_ADB=str(HERE / "fake_adb.py"),
            OPENVR_TEST_STATE=str(root),
            OPENVR_TEST_SCENARIO=scenario,
            OPENVR_RESULTS=str(results),
            AOSP_BOOT_TIMEOUT="1",
            AOSP_UI_TIMEOUT="1",
        )
        command = [str(HERE.parent / "verify-guest.sh"), serial]
        if with_apk:
            command.append(str(apk))
        completed = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=30)
        calls_file = root / "calls.jsonl"
        calls = [json.loads(line) for line in calls_file.read_text().splitlines()] if calls_file.exists() else []
        runs = list(results.glob("guest-*"))
        return completed, calls, runs[0] if runs else None

    def assert_guard_refusal(self, scenario, expected):
        result, calls, run = self.run_verifier(scenario)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(expected, (run / "cuttlefish-guest.log").read_text())
        self.assertTrue(calls)
        for call in calls:
            self.assertTrue(call[:2] == ["shell", "getprop"] or call == ["shell", "am", "get-current-user"], call)
        self.assertFalse((run / "cuttlefish-logcat.txt").exists())

    def assert_failed_flow(self, scenario, expected):
        result, calls, run = self.run_verifier(scenario)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(expected, (run / "cuttlefish-guest.log").read_text())
        self.assertIn("Cuttlefish diagnostic fixture", (run / "cuttlefish-logcat.txt").read_text())
        self.assertTrue((run / "failure.png").read_bytes().startswith(b"\x89PNG"))
        return calls, run

    def test_complete_flow(self):
        result, calls, run = self.run_verifier()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Verificación completada · HOME, Ajustes y APK", result.stdout)
        taps = [call[3:] for call in calls if call[:3] == ["shell", "input", "tap"]]
        self.assertEqual(
            taps,
            [["125", "885"], ["250", "130"], ["375", "885"], ["275", "220"], ["480", "270"], ["480", "330"]],
        )
        self.assertLess(calls.index(["shell", "input", "tap", "250", "130"]),
                        next(index for index, call in enumerate(calls) if call[:2] == ["install", "-r"]))
        self.assertLess(calls.index(["shell", "input", "tap", "480", "330"]),
                        calls.index(["logcat", "-d", "--pid=4359", "-s", "OpenVRDemo:I"]))
        self.assertFalse(any(call[:3] == ["shell", "am", "start"] for call in calls))
        self.assertIn("com.android.settings/.homepage.SettingsHomepageActivity",
                      (run / "android-settings-resumed.txt").read_text())
        self.assertIn("org.openvr.demo/org.openvr.demo.MainActivity", (run / "demo-resumed.txt").read_text())
        self.assertIn("APP_READY", (run / "demo-logcat.txt").read_text())
        self.assertTrue((run / "launcher-demo-result.xml").exists())
        self.assertTrue((run / "android-settings.png").exists())
        self.assertTrue((run / "demo.png").exists())
        self.assertFalse(list(run.glob(".apk-*")))
        self.assertEqual(calls[-1][:3], ["shell", "rm", "-f"])

    def test_home_and_settings_only(self):
        result, calls, run = self.run_verifier(with_apk=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Verificación completada · HOME y Ajustes", result.stdout)
        self.assertTrue((run / "android-settings-resumed.txt").exists())
        self.assertFalse(any(call[0] == "install" for call in calls))

    def test_refuses_usb_serial(self):
        result, calls, run = self.run_verifier(serial="1WMGH123456789")
        self.assertEqual(result.returncode, 2)
        self.assertIn("serial ADB local", result.stderr)
        self.assertFalse(calls)
        self.assertIsNone(run)

    def test_refuses_non_local_tcp(self):
        result, calls, run = self.run_verifier(serial="192.0.2.20:6520")
        self.assertEqual(result.returncode, 2)
        self.assertIn("serial ADB local", result.stderr)
        self.assertFalse(calls)
        self.assertIsNone(run)

    def test_wrong_product(self):
        self.assert_guard_refusal("wrong_product", "ro.product.product.name")

    def test_nonvirtual_device(self):
        self.assert_guard_refusal("physical_flag", "ro.hardware.virtual_device")

    def test_wrong_user(self):
        self.assert_guard_refusal("wrong_user", "usuario principal 0")

    def test_boot_timeout(self):
        self.assert_guard_refusal("boot_timeout", "Tiempo agotado esperando sys.boot_completed=1")

    def test_wrong_home(self):
        calls, run = self.assert_failed_flow("wrong_home", "no es el HOME predeterminado")
        self.assertNotIn(["shell", "input", "keyevent", "KEYCODE_HOME"], calls)
        self.assertIn("com.android.launcher3/.Launcher", (run / "home-resolution.txt").read_text())

    def test_missing_settings_control(self):
        calls, run = self.assert_failed_flow("settings_missing", "settings_android")
        self.assertTrue((run / "launcher-settings.xml").exists())
        self.assertFalse(any(call[0] == "install" for call in calls))

    def test_rejects_stale_ui(self):
        calls, _ = self.assert_failed_flow("stale_ui", "UIAutomator no produjo una captura nueva")
        self.assertNotIn(["shell", "input", "tap", "250", "130"], calls)

    def test_install_failure_reported_even_with_zero_exit(self):
        calls, _ = self.assert_failed_flow("install_failure", "no confirmó la instalación")
        self.assertNotIn(["shell", "am", "force-stop", "--user", "0", "org.openvr.demo"], calls)

    def test_installed_sha_mismatch(self):
        calls, _ = self.assert_failed_flow("apk_mismatch", "difiere del archivo indicado")
        self.assertNotIn(["shell", "input", "tap", "375", "885"], calls)

    def test_wrong_library_component(self):
        calls, run = self.assert_failed_flow("card_wrong", "app_open")
        self.assertIn("unexpected.app/.MainActivity", (run / "launcher-demo-result.xml").read_text())
        self.assertNotIn(["shell", "input", "tap", "480", "330"], calls)

    def test_no_success_for_demo_only_in_task_history(self):
        calls, run = self.assert_failed_flow("demo_not_resumed", "primer plano org.openvr.demo/.MainActivity")
        self.assertIn("Hist #0: ActivityRecord", (run / "demo-resumed.txt").read_text())
        self.assertNotIn(["logcat", "-d", "--pid=4359", "-s", "OpenVRDemo:I"], calls)

    def test_marker_required_for_resumed_activity(self):
        _, run = self.assert_failed_flow("missing_marker", "APP_READY en logcat")
        self.assertIn("topResumedActivity=ActivityRecord", (run / "demo-resumed.txt").read_text())
        self.assertNotIn("APP_READY", (run / "demo-logcat.txt").read_text())


if __name__ == "__main__":
    unittest.main()
