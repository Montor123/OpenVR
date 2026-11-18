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
    print(json.dumps(args), file=log)

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
        "ro.boot.verifiedbootstate": "green",
        "ro.boot.vbmeta.device_state": "locked",
        "ro.boot.flash.locked": "1",
    }
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
commands = [json.loads(line) for line in (root / "commands.jsonl").read_text().splitlines()]

assert report["schema_version"] == 1
assert report["properties"]["ro.product.device"] == "hollywood"
assert report["properties"]["ro.build.version.release"] == "12"
assert report["properties"]["ro.boot.slot_suffix"] == "_b"
assert report["properties"]["ro.soc.model"] is None
assert report["kernel"] == {"release": "4.19.999-test", "machine": "aarch64"}
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
for path in [primary, root / "selected.json", root / "partial.json"]:
    assert "FAKE-QUEST-0001" not in path.read_text()
for args in commands:
    if args == ["devices"]:
        continue
    assert args[:3] == ["-s", "FAKE-QUEST-0001", "shell"]
    assert args[3:] in [
        ["uname", "-r"], ["uname", "-m"], ["wm", "size"], ["wm", "density"],
        *[["getprop", prop] for prop in report["properties"]],
    ]

print("OK: comandos de solo lectura, selección, propiedades, pantalla, errores y JSON sin serie.")
PY
