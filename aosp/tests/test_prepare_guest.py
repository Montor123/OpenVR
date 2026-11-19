"""Exercise the bundle importer with small synthetic Cuttlefish archives."""

import hashlib
import importlib.util
import io
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

SPEC = importlib.util.spec_from_file_location(
    "prepare_guest", Path(__file__).resolve().parent.parent / "prepare-guest.py"
)
guest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guest)


class GuestBundleTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bundle = self.root / "bundle"
        self.bundle.mkdir()
        self.output = self.root / "run"
        self.write_host()
        self.write_guest()
        (self.bundle / "BUILD-INFO").write_text("\n".join(guest.BUILD_INFO) + "\n", encoding="utf-8")
        self.write_manifests()

    def write_host(self):
        with tarfile.open(self.bundle / guest.HOST, "w:gz") as archive:
            for binary in sorted(guest.REQUIRED_HOST):
                content = b"#!/bin/sh\nexit 0\n"
                member = tarfile.TarInfo(binary)
                member.mode = 0o755
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
            alias = tarfile.TarInfo("bin/launcher")
            alias.type = tarfile.SYMTYPE
            alias.linkname = "launch_cvd"
            archive.addfile(alias)

    def write_guest(self, members=None):
        with zipfile.ZipFile(self.bundle / guest.GUEST, "w") as archive:
            images = sorted(guest.REQUIRED_GUEST) if members is None else members
            for image in images:
                archive.writestr(image, b"synthetic image")

    def write_manifests(self):
        sums = []
        sizes = []
        for name in (guest.HOST, guest.GUEST):
            content = (self.bundle / name).read_bytes()
            sums.append(f"{hashlib.sha256(content).hexdigest()}  {name}")
            sizes.append(f"{len(content)} {name}")
        (self.bundle / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="utf-8")
        (self.bundle / "SIZE-BYTES").write_text("\n".join(sizes) + "\n", encoding="utf-8")

    def test_dry_run_validates_without_extracting(self):
        guest.prepare(self.bundle, None)
        self.assertFalse(self.output.exists())

    @unittest.skipUnless(hasattr(tarfile, "data_filter"), "tarfile data filter unavailable")
    def test_valid_bundle_preserves_tools_and_separates_images(self):
        with mock.patch.object(guest, "WORKING_SPACE", 0):
            guest.prepare(self.bundle, self.output)
        self.assertTrue((self.output / "bin/launch_cvd").stat().st_mode & 0o100)
        self.assertEqual((self.output / "bin/launcher").readlink(), Path("launch_cvd"))
        self.assertEqual((self.output / "images/boot.img").read_bytes(), b"synthetic image")
        self.assertEqual((self.output / ".openvr-run").read_text().strip(), "openvr-cuttlefish-r75")

    def test_corrupted_file_stops_before_extraction(self):
        image = self.bundle / guest.GUEST
        content = bytearray(image.read_bytes())
        content[-1] ^= 1
        image.write_bytes(content)
        with self.assertRaisesRegex(ValueError, "SHA-256 incorrecto"):
            guest.prepare(self.bundle, self.output)
        self.assertFalse(self.output.exists())

    def test_missing_boot_image_stops_before_extraction(self):
        self.write_guest(sorted(guest.REQUIRED_GUEST - {"boot.img"}))
        self.write_manifests()
        with self.assertRaisesRegex(ValueError, "carece de metadatos o imágenes"):
            guest.prepare(self.bundle, self.output)
        self.assertFalse(self.output.exists())

    def test_archive_entry_outside_output_is_rejected(self):
        self.write_guest([*sorted(guest.REQUIRED_GUEST), "../outside"])
        self.write_manifests()
        with self.assertRaisesRegex(ValueError, "Ruta fuera del destino"):
            guest.prepare(self.bundle, self.output)
        self.assertFalse(self.output.exists())
        self.assertFalse((self.root / "outside").exists())


if __name__ == "__main__":
    unittest.main()
