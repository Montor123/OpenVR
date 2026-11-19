#!/usr/bin/env python3
"""Stateful ADB fixture. A command outside the expected guest flow fails."""

from contextlib import redirect_stdout
import base64
import io
import json
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


LAUNCHER = "org.openvr.launcher"
DEMO = "org.openvr.demo"
APK_PATH = "/data/app/~~test==/org.openvr.demo-bookmarked==/base.apk"
PROPERTIES = {
    "sys.boot_completed": "1",
    "ro.product.product.name": "openvr_cf_x86_64_phone",
    "ro.product.product.model": "OpenVR Lab x86_64",
    "ro.product.product.device": "vsoc_x86_64",
    "ro.product.cpu.abi": "x86_64",
    "ro.hardware.virtual_device": "1",
    "ro.build.version.sdk": "34",
}
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6txlR0AAAAASUVORK5CYII="
)
UI = {
    "tab_settings": (0, 850, 250, 920),
    "settings_android": (100, 100, 400, 160),
    "tab_library": (250, 850, 500, 920),
    "library_apps": (80, 195, 470, 245),
    "library_search": (80, 250, 880, 290),
    "app_open": (80, 305, 880, 355),
}


def ui_hierarchy(state, scenario):
    root = ET.Element("hierarchy", rotation="0")
    screen = state["screen"]
    if screen in ("home", "launcher_settings", "library"):
        add_control(root, "tab_settings")
        add_control(root, "tab_library")
    if screen == "launcher_settings" and scenario != "settings_missing":
        add_control(root, "settings_android")
    if screen == "library":
        add_control(root, "library_apps")
        add_control(root, "library_search")
        if state.get("query") == DEMO and state.get("installed") and state.get("apps_filter"):
            component = "unexpected.app/.MainActivity" if scenario == "card_wrong" else f"{DEMO}/.MainActivity"
            add_control(root, "app_open", f"OpenVR Demo ({component})")
    if scenario == "stale_ui" and screen == "home":
        # An old file can claim to show a control not present after the next dump fails.
        add_control(root, "settings_android")
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def add_control(parent, control, description=""):
    x1, y1, x2, y2 = UI[control]
    ET.SubElement(parent, "node", {
        "resource-id": f"{LAUNCHER}:id/{control}",
        "package": LAUNCHER,
        "enabled": "true",
        "clickable": "true",
        "bounds": f"[{x1},{y1}][{x2},{y2}]",
        "content-desc": description,
    })


def active_component(screen):
    if screen == "settings":
        return "com.android.settings/.homepage.SettingsHomepageActivity"
    if screen == "demo":
        return f"{DEMO}/{DEMO}.MainActivity"
    return f"{LAUNCHER}/.MainActivity"


def handle(args, state, work, scenario):
    if args[:2] == ["shell", "getprop"] and len(args) == 3:
        prop = args[2]
        values = dict(PROPERTIES)
        if scenario == "boot_timeout":
            values["sys.boot_completed"] = "0"
        if scenario == "wrong_product":
            values["ro.product.product.name"] = "hollywood"
        if scenario == "physical_flag":
            values["ro.hardware.virtual_device"] = "0"
        print(values[prop])
    elif args == ["shell", "am", "get-current-user"]:
        print("10" if scenario == "wrong_user" else "0")
    elif args[:4] == ["shell", "cmd", "package", "resolve-activity"]:
        print("priority=0 preferredOrder=0 match=0x108000 isDefault=true")
        if scenario == "wrong_home":
            print("com.android.launcher3/.Launcher")
        else:
            print(f"{LAUNCHER}/{LAUNCHER}.MainActivity")
    elif args in (["shell", "input", "keyevent", "KEYCODE_WAKEUP"],
                  ["shell", "wm", "dismiss-keyguard"]):
        pass
    elif args == ["shell", "input", "keyevent", "KEYCODE_HOME"]:
        state["screen"] = "home"
    elif args == ["shell", "dumpsys", "activity", "activities"]:
        print("ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)")
        print(f"  topResumedActivity=ActivityRecord{{f841ef u0 {active_component(state['screen'])} t17}}")
        print(f"  * Hist #0: ActivityRecord{{ab42a u0 {DEMO}/.MainActivity t16}}")
    elif args[:3] == ["shell", "uiautomator", "dump"] and len(args) == 4:
        if scenario == "stale_ui" and state["screen"] == "launcher_settings":
            print("ERROR: could not get idle state.")
        else:
            (work / "remote.xml").write_bytes(ui_hierarchy(state, scenario))
            print(f"UI hierchary dumped to: {args[-1]}")
    elif args[:2] == ["exec-out", "cat"]:
        return (work / "remote.xml").read_bytes()
    elif args[:3] == ["shell", "input", "tap"]:
        x, y = map(int, args[3:])
        control = next(
            name for name, (left, top, right, bottom) in UI.items()
            if left < x < right and top < y < bottom
        )
        if control == "tab_settings":
            state["screen"] = "launcher_settings"
        elif control == "settings_android":
            assert state["screen"] == "launcher_settings"
            state["screen"] = "settings"
        elif control == "tab_library":
            state["screen"] = "library"
        elif control == "library_apps":
            assert state["screen"] == "library"
            state["apps_filter"] = True
        elif control == "library_search":
            assert state["screen"] == "library"
            state["search_focused"] = True
        else:
            assert state["installed"] and state["query"] == DEMO and state["force_stopped"]
            if scenario != "demo_not_resumed":
                state["screen"] = "demo"
    elif args == ["exec-out", "screencap", "-p"]:
        return PNG
    elif args[:2] == ["install", "-r"] and len(args) == 3:
        if scenario == "install_failure":
            print("Failure [INSTALL_FAILED_INVALID_APK]")
        else:
            state["installed"] = True
            state["apk_file"] = args[2]
            print("Performing Streamed Install\nSuccess")
    elif args == ["shell", "pm", "path", "--user", "0", DEMO]:
        assert state["installed"]
        print(f"package:{APK_PATH}")
    elif args[:2] == ["pull", APK_PATH] and len(args) == 3:
        apk = b"wrong APK" if scenario == "apk_mismatch" else Path(state["apk_file"]).read_bytes()
        Path(args[2]).write_bytes(apk)
        print("1 file pulled")
    elif args == ["shell", "am", "force-stop", "--user", "0", DEMO]:
        state["force_stopped"] = True
    elif args == ["shell", "input", "keycombination", "KEYCODE_CTRL_LEFT", "KEYCODE_A"]:
        assert state["search_focused"]
        state["query"] = ""
    elif args == ["shell", "input", "text", DEMO]:
        assert state["search_focused"]
        state["query"] = DEMO
    elif args == ["shell", "pidof", "-s", DEMO]:
        assert state["screen"] == "demo"
        print("4359")
    elif args == ["logcat", "-d", "--pid=4359", "-s", "OpenVRDemo:I"]:
        print("11-18 16:00:01.000  4359  4359 I OpenVRDemo: Process started")
        if scenario != "missing_marker":
            print("11-18 16:00:01.001  4359  4359 I OpenVRDemo: APP_READY Android 14 · API 34 · x86_64")
    elif args == ["logcat", "-d", "-v", "threadtime"]:
        print("Cuttlefish diagnostic fixture")
    elif args[:3] == ["shell", "rm", "-f"] and len(args) == 4:
        (work / "remote.xml").unlink(missing_ok=True)
    else:
        raise ValueError(f"unexpected ADB command {args}")


def main():
    assert sys.argv[1:3] == ["-s", "127.0.0.1:6520"], sys.argv
    args = sys.argv[3:]
    work = Path(os.environ["OPENVR_TEST_STATE"])
    scenario = os.environ["OPENVR_TEST_SCENARIO"]
    state_path = work / "state.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {"screen": "home"}
    with (work / "calls.jsonl").open("a", encoding="utf-8") as calls:
        calls.write(json.dumps(args) + "\n")
    output = io.StringIO()
    with redirect_stdout(output):
        binary = handle(args, state, work, scenario)
    state_path.write_text(json.dumps(state), encoding="utf-8")
    if binary is None:
        print(output.getvalue(), end="")
    else:
        sys.stdout.buffer.write(binary)


if __name__ == "__main__":
    main()
