#!/usr/bin/env python3
"""Verify the OpenVR product through its actual Android UI on Cuttlefish."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET


LAUNCHER = "org.openvr.launcher"
HOME = f"{LAUNCHER}/.MainActivity"
SETTINGS = "com.android.settings"
DEMO = "org.openvr.demo"
DEMO_ACTIVITY = f"{DEMO}/.MainActivity"
GUEST_PROPERTIES = {
    "ro.product.product.name": "openvr_cf_x86_64_phone",
    "ro.product.product.model": "OpenVR Lab x86_64",
    "ro.product.product.device": "vsoc_x86_64",
    "ro.product.cpu.abi": "x86_64",
    "ro.hardware.virtual_device": "1",
    "ro.build.version.sdk": "34",
}
SHELL_COMPONENT = re.compile(r"([\w.]+)/(\.?[\w.$]+)")
RESUMED_ACTIVITY = re.compile(r"topResumedActivity=ActivityRecord\{[^}\r\n]*\bu0 ([\w.]+/\.?[\w.$]+)")
BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")
DEMO_APK_PATH = re.compile(r"/data/app/[A-Za-z0-9_.=~+/-]+/base\.apk")


class VerificationError(RuntimeError):
    pass


def expanded_component(component):
    package, activity = component.split("/", 1)
    return f"{package}/{package + activity if activity.startswith('.') else activity}"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


class GuestVerifier:
    def __init__(self, adb, serial, results, boot_timeout, ui_timeout, log):
        self.device = [adb, "-s", serial]
        self.adb_env = dict(os.environ)
        for name in ("ADB_SERVER_SOCKET", "ANDROID_ADB_SERVER_ADDRESS", "ANDROID_ADB_SERVER_PORT"):
            self.adb_env.pop(name, None)
        self.results = results
        self.boot_timeout = boot_timeout
        self.ui_timeout = ui_timeout
        self.log = log
        self.is_openvr = False
        self.remote_xml = f"/data/local/tmp/openvr-{results.name}.xml"
        self.dump_requested = False

    def report(self, message):
        print(message, flush=True)
        print(message, file=self.log, flush=True)

    def adb(self, *args, timeout=10, deadline=None, binary=False):
        command = self.device + list(args)
        if deadline is not None:
            timeout = min(timeout, deadline - time.monotonic())
        if timeout <= 0:
            raise VerificationError("Se agotó el tiempo de espera.")

        print(f"$ {shlex.join(command)}", file=self.log, flush=True)
        try:
            result = subprocess.run(command, capture_output=True, timeout=timeout, env=self.adb_env)
        except subprocess.TimeoutExpired as error:
            raise VerificationError(f"ADB superó el tiempo de espera con {shlex.join(args)}.") from error
        if result.returncode:
            detail = (result.stdout + b"\n" + result.stderr).decode(errors="replace").strip()
            raise VerificationError(f"ADB falló con {shlex.join(args)}. {detail}")
        if result.stderr:
            print(result.stderr.decode(errors="replace").strip(), file=self.log, flush=True)
        if binary:
            return result.stdout
        return result.stdout.decode(errors="replace").strip()

    def wait_for(self, description, probe, seconds):
        deadline = time.monotonic() + seconds
        last_error = None
        while time.monotonic() < deadline:
            try:
                value = probe(deadline)
                if value is not None:
                    return value
            except VerificationError as error:
                last_error = error
            remaining = deadline - time.monotonic()
            if remaining > 0:
                time.sleep(min(0.5, remaining))
        detail = f" Último error: {last_error}" if last_error else ""
        raise VerificationError(f"Tiempo agotado esperando {description}.{detail}")

    def property(self, name, deadline=None):
        return self.adb("shell", "getprop", name, deadline=deadline)

    def confirm_guest(self):
        # Only read guest identity before making UI or package changes.
        self.report(f"Esperando el arranque de {self.device[-1]}.")
        self.wait_for(
            "sys.boot_completed=1",
            lambda deadline: True if self.property("sys.boot_completed", deadline) == "1" else None,
            self.boot_timeout,
        )
        for prop, expected in GUEST_PROPERTIES.items():
            actual = self.property(prop)
            self.report(f"{prop}={actual}")
            if actual != expected:
                raise VerificationError(
                    f"El serial no corresponde al Cuttlefish OpenVR ({prop}, se esperaba {expected})."
                )
        if self.adb("shell", "am", "get-current-user") != "0":
            raise VerificationError("La prueba requiere el usuario principal 0 del invitado.")
        self.is_openvr = True

    def wait_activity(self, expected, evidence):
        def active(deadline):
            activities = self.adb("shell", "dumpsys", "activity", "activities", deadline=deadline)
            (self.results / f"{evidence}.txt").write_text(activities + "\n", encoding="utf-8")
            resumed = set(RESUMED_ACTIVITY.findall(activities))
            if len(resumed) != 1:
                return None
            component = resumed.pop()
            if "/" in expected:
                matches = expanded_component(component) == expanded_component(expected)
            else:
                matches = component.split("/", 1)[0] == expected
            return component if matches else None

        component = self.wait_for(f"la actividad en primer plano {expected}", active, self.ui_timeout)
        self.report(f"Actividad en primer plano: {component}")

    def dump_ui(self, evidence, deadline):
        self.dump_requested = True
        summary = self.adb("shell", "uiautomator", "dump", self.remote_xml,
                           timeout=15, deadline=deadline)
        if not summary.endswith(self.remote_xml):
            raise VerificationError(f"UIAutomator no produjo una captura nueva. {summary}")
        xml = self.adb("exec-out", "cat", self.remote_xml, deadline=deadline, binary=True)
        (self.results / f"{evidence}.xml").write_bytes(xml)
        try:
            return ET.fromstring(xml)
        except ET.ParseError as error:
            raise VerificationError(f"UIAutomator produjo XML inválido. {error}") from error

    def tap_launcher_control(self, control, evidence, component=None):
        resource = f"{LAUNCHER}:id/{control}"

        def locate(deadline):
            nodes = self.dump_ui(evidence, deadline)
            matches = [
                node for node in nodes.iter("node")
                if node.get("package") == LAUNCHER
                and node.get("resource-id") == resource
                and node.get("enabled") == "true"
                and node.get("clickable") == "true"
                and (component is None or node.get("content-desc", "").endswith(f" ({component})"))
            ]
            if len(matches) != 1:
                return None
            bounds = BOUNDS.fullmatch(matches[0].get("bounds", ""))
            if bounds is None:
                return None
            left, top, right, bottom = map(int, bounds.groups())
            if left >= right or top >= bottom:
                return None
            return str((left + right) // 2), str((top + bottom) // 2)

        x, y = self.wait_for(resource, locate, self.ui_timeout)
        self.adb("shell", "input", "tap", x, y)
        self.report(f"Control pulsado: {resource}" + (f" ({component})" if component else ""))

    def open_home(self, evidence):
        self.adb("shell", "input", "keyevent", "KEYCODE_HOME")
        self.wait_activity(HOME, evidence)

    def verify_settings(self):
        home = self.adb("shell", "cmd", "package", "resolve-activity", "--brief", "--user", "0",
                        "-a", "android.intent.action.MAIN", "-c", "android.intent.category.HOME")
        (self.results / "home-resolution.txt").write_text(home + "\n", encoding="utf-8")
        components = [
            line.strip() for line in home.splitlines() if SHELL_COMPONENT.fullmatch(line.strip())
        ]
        if len(components) != 1 or expanded_component(components[0]) != expanded_component(HOME):
            raise VerificationError(f"OpenVR no es el HOME predeterminado. {home}")

        self.report(f"HOME predeterminado: {components[0]}")
        self.adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
        self.adb("shell", "wm", "dismiss-keyguard")
        self.open_home("home-resumed")
        self.tap_launcher_control("tab_settings", "launcher-home")
        self.tap_launcher_control("settings_android", "launcher-settings")
        self.wait_activity(SETTINGS, "android-settings-resumed")
        self.save_screenshot("android-settings")
        self.open_home("home-after-settings")

    def verify_installed_apk(self, apk):
        digest = sha256(apk)
        self.report(f"APK de prueba · SHA-256 {digest}")
        install = self.adb("install", "-r", str(apk.resolve()), timeout=120)
        self.report(install)
        if "Success" not in install.splitlines():
            raise VerificationError("El instalador no confirmó la instalación de la APK.")

        paths = self.adb("shell", "pm", "path", "--user", "0", DEMO).splitlines()
        bases = [
            line.removeprefix("package:") for line in paths
            if line.startswith("package:") and DEMO_APK_PATH.fullmatch(line.removeprefix("package:"))
        ]
        if len(bases) != 1 or any(part == ".." for part in bases[0].split("/")):
            raise VerificationError(f"Falta base.apk instalada de {DEMO} en /data/app.")
        # adbd can read installed APKs via pull. The unprivileged guest shell
        # does not have the same SELinux permissions.
        with tempfile.TemporaryDirectory(prefix=".apk-", dir=self.results) as directory:
            installed = Path(directory) / "installed.apk"
            self.adb("pull", bases[0], str(installed), timeout=60)
            if sha256(installed) != digest:
                raise VerificationError(f"La APK del invitado para {DEMO} difiere del archivo indicado.")

    def verify_demo(self, apk):
        self.verify_installed_apk(apk)
        self.adb("shell", "am", "force-stop", "--user", "0", DEMO)
        self.open_home("home-after-install")
        self.tap_launcher_control("tab_library", "launcher-before-library")
        self.tap_launcher_control("library_apps", "launcher-library")
        self.tap_launcher_control("library_search", "launcher-app-filter")
        self.adb("shell", "input", "keycombination", "KEYCODE_CTRL_LEFT", "KEYCODE_A")
        self.adb("shell", "input", "text", DEMO)
        self.tap_launcher_control("app_open", "launcher-demo-result", component=DEMO_ACTIVITY)
        self.wait_activity(DEMO_ACTIVITY, "demo-resumed")

        def ready(deadline):
            pid = self.adb("shell", "pidof", "-s", DEMO, deadline=deadline)
            if not re.fullmatch(r"[1-9][0-9]*", pid):
                return None
            logcat = self.adb("logcat", "-d", f"--pid={pid}", "-s", "OpenVRDemo:I", deadline=deadline)
            (self.results / "demo-logcat.txt").write_text(logcat + "\n", encoding="utf-8")
            return pid if re.search(r"\bAPP_READY\b", logcat) else None

        pid = self.wait_for("APP_READY en logcat de OpenVRDemo", ready, self.ui_timeout)
        self.report(f"APK abierta desde Biblioteca · APP_READY en PID {pid}")
        self.save_screenshot("demo")

    def save_screenshot(self, name):
        try:
            png = self.adb("exec-out", "screencap", "-p", timeout=15, binary=True)
            if not png.startswith(b"\x89PNG\r\n\x1a\n"):
                raise VerificationError("La captura no contiene un PNG.")
            (self.results / f"{name}.png").write_bytes(png)
        except (VerificationError, OSError) as error:
            self.report(f"Captura {name}: {error}")

    def save_diagnostics(self, successful):
        if not self.is_openvr:
            return
        if not successful:
            self.save_screenshot("failure")
        try:
            output = self.adb("logcat", "-d", "-v", "threadtime", timeout=25)
            (self.results / "cuttlefish-logcat.txt").write_text(output + "\n", encoding="utf-8")
        except (VerificationError, OSError) as error:
            self.report(f"Captura de logcat: {error}")
        if self.dump_requested:
            try:
                self.adb("shell", "rm", "-f", self.remote_xml)
            except VerificationError as error:
                self.report(f"Limpieza del XML temporal: {error}")


def parse_timeout(name, default):
    value = os.environ.get(name, str(default))
    if not re.fullmatch(r"[1-9][0-9]{0,5}", value):
        raise ValueError(f"{name} debe indicar segundos enteros positivos.")
    return int(value)


def main():
    parser = argparse.ArgumentParser(prog="verify-guest.sh", description="Verifica la interfaz de OpenVR en Cuttlefish.")
    parser.add_argument("serial", metavar="SERIAL_CUTTLEFISH")
    parser.add_argument("apk", nargs="?", type=Path, metavar="openvr-demo.apk")
    args = parser.parse_args()
    serial = re.fullmatch(r"(?:127\.0\.0\.1|localhost):([1-9][0-9]{0,4})", args.serial)
    if serial is None or int(serial[1]) > 65535:
        parser.error("Usa el serial ADB local 127.0.0.1:PUERTO del Cuttlefish OpenVR.")

    adb = shutil.which(os.environ.get("OPENVR_ADB", "adb"))
    if adb is None:
        parser.error("No se encontró ADB. Configura OPENVR_ADB.")
    if args.apk is not None and not (args.apk.is_file() and os.access(args.apk, os.R_OK)):
        parser.error(f"No se puede leer {args.apk}.")
    try:
        boot_timeout = parse_timeout("AOSP_BOOT_TIMEOUT", 300)
        ui_timeout = parse_timeout("AOSP_UI_TIMEOUT", 60)
        base = Path(os.environ.get("OPENVR_RESULTS", "./results/cuttlefish")).resolve()
        base.mkdir(parents=True, exist_ok=True)
        results = Path(tempfile.mkdtemp(prefix="guest-", dir=base))
    except (ValueError, OSError) as error:
        parser.error(str(error))

    with (results / "cuttlefish-guest.log").open("w", encoding="utf-8") as log:
        guest = GuestVerifier(adb, args.serial, results, boot_timeout, ui_timeout, log)
        guest.report(f"Resultados: {results}")
        successful = False
        try:
            guest.confirm_guest()
            guest.verify_settings()
            if args.apk is not None:
                guest.verify_demo(args.apk)
            phases = "HOME, Ajustes y APK" if args.apk is not None else "HOME y Ajustes"
            guest.report(f"Verificación completada · {phases}")
            successful = True
        except (VerificationError, OSError) as error:
            guest.report(f"Falló la verificación: {error}")
        finally:
            guest.save_diagnostics(successful)
        return 0 if successful else 1


if __name__ == "__main__":
    raise SystemExit(main())
