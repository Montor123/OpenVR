#!/usr/bin/env bash
set -euo pipefail

tool_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pwsh="${OPENVR_PWSH:-pwsh}"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$scratch/test transport"
adb="$scratch/test transport/adb"
cat > "$adb" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys

mode = os.environ.get("OPENVR_ADB_FIXTURE", "normal")
args = sys.argv[1:]
serial = "FAKE-QUEST-0001"

with open(os.environ["OPENVR_ADB_COMMANDS"], "a", encoding="utf-8") as log:
    print(json.dumps({"mode": mode, "args": args}), file=log)

if args == ["devices"]:
    print("List of devices attached")
    print(serial + "\t" + ("unauthorized" if mode == "unauthorized" else "device"))
    if mode == "two":
        print("OTHER-TEST-0002\toffline")
    sys.exit()

if args[:3] != ["-s", serial, "shell"]:
    sys.exit(99)

command = args[3:]
if command[:1] == ["getprop"] and len(command) == 2:
    prop = command[1]
    values = {
        "ro.product.model": "Quest 2",
        "ro.product.device": "hollywood",
        "ro.board.platform": "kona",
        "ro.product.cpu.abilist": "arm64-v8a,armeabi-v7a",
        "ro.build.fingerprint": "test/hollywood/hollywood:12/TEST1/1:user/release-keys",
        "ro.build.version.release": "12",
        "ro.build.version.sdk": "31",
        "ro.boot.slot_suffix": "_b",
        "ro.boot.slot": "b",
        "ro.boot.verifiedbootstate": "green",
        "ro.boot.vbmeta.device_state": "locked",
        "ro.boot.flash.locked": "1",
        "ro.boot.hwrev": "EVT2",
        "ro.revision": "03",
        "ro.boot.hardware.sku": "64gb",
    }
    if mode == "fallback":
        values.update({"ro.boot.slot_suffix": "", "ro.boot.slot": "a", "ro.boot.flash.locked": "0"})
    elif mode == "conflict":
        values.update({"ro.boot.slot_suffix": "_a", "ro.boot.slot": "b", "ro.boot.flash.locked": "unknown"})
    elif mode == "denied":
        values.update({"ro.boot.slot_suffix": "_c", "ro.boot.slot": "-", "ro.boot.flash.locked": ""})
    if mode == "other" and prop in ("ro.product.model", "ro.product.device"):
        print("otro-android")
    elif mode == "partial" and prop == "ro.boot.vbmeta.device_state":
        print(f"adb: error reading {serial}", file=sys.stderr)
        sys.exit(7)
    elif mode == "partial" and prop == "ro.build.fingerprint":
        print(serial)
    else:
        print(values.get(prop, ""))
elif command == ["uname", "-r"]:
    print("4.19.999-test")
elif command == ["uname", "-m"]:
    print("aarch64")
elif command == ["wm", "size"]:
    print("Physical size: 1920x1080\nOverride size: 960x540")
elif command == ["wm", "density"]:
    print("Physical density: 320")
elif command in (["cat", "/sys/firmware/devicetree/base/model"], ["cat", "/proc/device-tree/model"]):
    primary = command[1].startswith("/sys/")
    if mode == "denied" or (primary and mode == "fallback"):
        print(f"cat: access to {serial} denied", file=sys.stderr)
        sys.exit(1)
    if primary and mode == "noisy":
        print(f"cannot parse {serial}\nunexpected second line")
    else:
        model = b"Fixture Board" if primary else b"Fixture Board via proc"
        sys.stdout.buffer.write(model + b"\x00")
elif command in (
    ["ls", "-1", "/dev/block/by-name"],
    ["ls", "-1", "/dev/block/bootdevice/by-name"],
    ["ls", "-1", "/dev/block/mapper"],
):
    path = command[2]
    if mode == "denied" or (mode == "fallback" and path == "/dev/block/by-name"):
        print(f"ls: {path} denied for {serial}", file=sys.stderr)
        sys.exit(1)
    if path.endswith("/mapper"):
        if mode != "noisy":
            print("system_b\nvendor_b")
    elif mode == "noisy":
        print(f"boot_b\n{serial}\nls: warning\n../secret\n/dev/block/mmc0\n..\nwith space\nmy:data\nuserdata")
    else:
        print("boot_b\nvbmeta_b\nsuper")
else:
    sys.exit(99)
PY
chmod +x "$adb"
export OPENVR_ADB_COMMANDS="$scratch/commands.jsonl"

run() {
  "$pwsh" -NoLogo -NoProfile -File "$tool_dir/inspect-quest.ps1" -Adb "$adb" "$@"
}

expect_failure() {
  if run "$@" > "$scratch/rejected.txt" 2>&1; then
    echo "Se esperaba un error al crear el inventario." >&2
    return 1
  fi
}

cd "$scratch"
run -Display
default_report="$scratch/results/quest2-inventory.json"
OPENVR_ADB_FIXTURE=two expect_failure -OutputPath "$scratch/rejected.json"
OPENVR_ADB_FIXTURE=unauthorized expect_failure -OutputPath "$scratch/rejected.json"
OPENVR_ADB_FIXTURE=other expect_failure -OutputPath "$scratch/rejected.json"
expect_failure -Serial "NO-EXISTE" -OutputPath "$scratch/rejected.json"
test ! -e "$scratch/rejected.json"

OPENVR_ADB_FIXTURE=two run -Serial FAKE-QUEST-0001 -OutputPath "$scratch/selected.json"
OPENVR_ADB_FIXTURE=partial run -OutputPath "$scratch/partial.json"
for mode in fallback denied noisy conflict; do
  OPENVR_ADB_FIXTURE="$mode" run -OutputPath "$scratch/$mode.json"
done
expect_failure -OutputPath "$default_report"

python3 - "$scratch" <<'PY'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
primary = root / "results/quest2-inventory.json"
report = json.loads(primary.read_text())
selected = json.loads((root / "selected.json").read_text())
partial = json.loads((root / "partial.json").read_text())
fallback = json.loads((root / "fallback.json").read_text())
denied = json.loads((root / "denied.json").read_text())
noisy = json.loads((root / "noisy.json").read_text())
conflict = json.loads((root / "conflict.json").read_text())
calls = [json.loads(line) for line in (root / "commands.jsonl").read_text().splitlines()]

assert report["schema_version"] == 1
assert report["properties"]["ro.product.device"] == "hollywood"
assert report["properties"]["ro.build.version.release"] == "12"
assert report["properties"]["ro.boot.slot_suffix"] == "_b"
assert report["properties"]["ro.soc.model"] is None
assert report["kernel"] == {"release": "4.19.999-test", "machine": "aarch64"}
assert report["boot"] == {
    "active_slot": "b", "slot_conflict": False, "verified_boot_state": "green",
    "flash_locked": True, "vbmeta_device_state": "locked",
}
assert report["boot"]["flash_locked"] is True
assert report["board"] == {
    "model": "Fixture Board", "boot_hardware_revision": "EVT2",
    "hardware_revision": "03", "boot_hardware_sku": "64gb",
}


def assert_names(report, group, source, expected):
    entry = report["partitions"][group]
    assert entry["source"] == source, entry
    assert isinstance(entry["names"], list), entry
    assert sorted(entry["names"]) == sorted(expected), entry


assert_names(report, "by_name", "/dev/block/by-name", ["boot_b", "vbmeta_b", "super"])
assert_names(report, "mapper", "/dev/block/mapper", ["system_b", "vendor_b"])
assert fallback["board"]["model"] == "Fixture Board via proc"
assert fallback["boot"]["active_slot"] == "a"
assert fallback["boot"]["slot_conflict"] is False
assert fallback["boot"]["flash_locked"] is False
assert fallback["read_errors"] == []
assert_names(fallback, "by_name", "/dev/block/bootdevice/by-name", ["boot_b", "vbmeta_b", "super"])
assert noisy["board"]["model"] == "Fixture Board via proc"
assert_names(noisy, "by_name", "/dev/block/by-name", ["boot_b", "userdata"])
assert_names(noisy, "mapper", "/dev/block/mapper", [])
assert noisy["read_errors"] == []
assert denied["board"]["model"] is None
assert denied["partitions"] == {
    "by_name": {"source": None, "names": None},
    "mapper": {"source": None, "names": None},
}
assert sorted(denied["read_errors"]) == ["board.model", "partitions.by_name", "partitions.mapper"]
assert denied["boot"]["active_slot"] is None
assert denied["boot"]["slot_conflict"] is False
assert denied["boot"]["flash_locked"] is None
assert conflict["boot"]["active_slot"] is None
assert conflict["boot"]["slot_conflict"] is True
assert conflict["boot"]["flash_locked"] is None
assert report["display_android_wm"] == {
    "physical_size": {"width": 1920, "height": 1080},
    "physical_density_dpi": 320,
    "override_size": {"width": 960, "height": 540},
    "override_density_dpi": None,
}
assert report["read_errors"] == []
assert selected["properties"] == report["properties"]
assert "display_android_wm" not in selected
assert partial["read_errors"] == ["ro.boot.vbmeta.device_state"]
assert partial["properties"]["ro.boot.vbmeta.device_state"] is None
assert partial["properties"]["ro.build.fingerprint"] is None
for path in [primary, *root.glob("*.json")]:
    report_text = path.read_text()
    assert "FAKE-QUEST-0001" not in report_text
    assert "OTHER-TEST-0002" not in report_text
    assert "../secret" not in report_text
for call in calls:
    args = call["args"]
    if args == ["devices"]:
        continue
    assert args[:3] == ["-s", "FAKE-QUEST-0001", "shell"]
    assert args[3:] in [
        ["uname", "-r"], ["uname", "-m"], ["wm", "size"], ["wm", "density"],
        ["cat", "/sys/firmware/devicetree/base/model"], ["cat", "/proc/device-tree/model"],
        ["ls", "-1", "/dev/block/by-name"], ["ls", "-1", "/dev/block/bootdevice/by-name"],
        ["ls", "-1", "/dev/block/mapper"],
        *[["getprop", prop] for prop in report["properties"]],
    ], args

assert ["cat", "/proc/device-tree/model"] not in [call["args"][3:] for call in calls if call["mode"] == "normal"]
assert ["ls", "-1", "/dev/block/bootdevice/by-name"] not in [
    call["args"][3:] for call in calls if call["mode"] == "normal"
]

print("OK: ADB de solo lectura, arranque, placa, nombres de partición, rutas alternativas y errores sin serie.")
PY
