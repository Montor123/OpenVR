#!/usr/bin/env python3
"""Validate and unpack one OpenVR Cuttlefish export into an unused directory."""

import hashlib
import posixpath
import re
import shutil
import stat
import sys
import tarfile
import zipfile
from pathlib import Path, PurePosixPath

GUEST = "openvr_cf_x86_64_phone-img.zip"
HOST = "cvd-host_package.tar.gz"
BUILD_INFO = [
    "android-14.0.0_r75",
    "e3b1a5113daede938922ed29c36806e0aac2ecb3",
    "openvr_cf_x86_64_phone-trunk_staging-userdebug",
]
REQUIRED_HOST = {"bin/adb", "bin/launch_cvd", "bin/stop_cvd"}
REQUIRED_GUEST = {"android-info.txt", "boot.img", "bootloader", "super.img"}
RESERVED = {"images", ".openvr-run", "cuttlefish-launch.log", "cuttlefish-stop.log"}
WORKING_SPACE = 4 * 1024**3


def plain_file(directory, name):
    path = directory / name
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Falta un archivo regular del export: {name}")
    return path


def read_manifest(directory, name, value_pattern):
    manifest = plain_file(directory, name)
    if manifest.stat().st_size > 4096:
        raise ValueError(f"Manifiesto demasiado grande: {name}")
    entries = {}
    for line in manifest.read_text(encoding="utf-8").splitlines():
        values = line.split()
        if len(values) != 2:
            raise ValueError(f"Fila inválida en {name}")
        value, filename = values
        if filename not in (HOST, GUEST) or filename in entries:
            raise ValueError(f"Archivo inesperado o repetido en {name}")
        if not re.fullmatch(value_pattern, value):
            raise ValueError(f"Valor inválido en {name} para {filename}")
        entries[filename] = value
    if len(entries) != 2:
        raise ValueError(f"Faltan entradas en {name}")
    return entries


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def bundle_files(directory):
    build_info = plain_file(directory, "BUILD-INFO")
    if build_info.stat().st_size > 4096 or build_info.read_text().splitlines() != BUILD_INFO:
        raise ValueError("BUILD-INFO no corresponde al producto AOSP OpenVR fijado")
    checksums = read_manifest(directory, "SHA256SUMS", "[a-f0-9]{64}")
    sizes = read_manifest(directory, "SIZE-BYTES", "[1-9][0-9]*")
    files = {}
    for name in (HOST, GUEST):
        path = plain_file(directory, name)
        if path.stat().st_size != int(sizes[name]) or sha256(path) != checksums[name]:
            raise ValueError(f"Tamaño o SHA-256 incorrecto para {name}")
        files[name] = path
        print(f"{name}: {sizes[name]} bytes, SHA-256 correcto")
    return files


def member_path(name):
    if not name or "\\" in name or any(ord(char) < 32 for char in name):
        raise ValueError(f"Ruta inválida en el archivo: {name!r}")
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Ruta fuera del destino: {name!r}")
    return path


def inspect_host(archive):
    names = set()
    total = 0
    for member in archive.getmembers():
        path = member_path(member.name)
        if path.parts and path.parts[0] in RESERVED:
            raise ValueError(f"Ruta reservada en el paquete host: {path}")
        if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
            raise ValueError(f"Tipo de entrada no admitido en el paquete host: {path}")
        if member.issym() or member.islnk():
            parent = path.parent if member.issym() else PurePosixPath(".")
            target = member.linkname
            if not target or target.startswith("/") or "\\" in target:
                raise ValueError(f"Enlace inválido en el paquete host: {path}")
            member_path(posixpath.normpath(str(parent / target)))
        total += member.size
        names.add(str(path))
    if not REQUIRED_HOST <= names:
        raise ValueError("El paquete host carece de adb, launch_cvd o stop_cvd")
    return total


def inspect_guest(archive):
    names = set()
    total = 0
    for entry in archive.infolist():
        name = str(member_path(entry.filename))
        mode = (entry.external_attr >> 16) & 0xFFFF
        kind = stat.S_IFMT(mode)
        if kind not in (0, stat.S_IFREG, stat.S_IFDIR):
            raise ValueError(f"Tipo de entrada no admitido en el ZIP: {name}")
        if name in names:
            raise ValueError(f"Entrada ZIP duplicada: {name}")
        names.add(name)
        total += entry.file_size
    if not REQUIRED_GUEST <= names:
        raise ValueError("El ZIP de Cuttlefish carece de metadatos o imágenes de arranque")
    return total


def prepare(bundle, output):
    files = bundle_files(bundle)
    with tarfile.open(files[HOST], "r:gz") as host, zipfile.ZipFile(files[GUEST]) as guest:
        unpacked = inspect_host(host) + inspect_guest(guest)
        print(f"Contenido declarado sin comprimir: {unpacked} bytes")
        if output is None:
            return
        if not hasattr(tarfile, "data_filter"):
            raise ValueError("Python tarfile carece del filtro de extracción data")
        free = shutil.disk_usage(output.parent).free
        if free < unpacked + WORKING_SPACE:
            raise ValueError("Espacio insuficiente para extraer los archivos y reservar 4 GiB de trabajo")
        output.mkdir(mode=0o700)
        host.extractall(output, filter="data")
        images = output / "images"
        images.mkdir()
        guest.extractall(images)
        for binary in REQUIRED_HOST:
            path = output / binary
            if not path.is_file() or not path.stat().st_mode & stat.S_IXUSR:
                raise ValueError(f"No se puede ejecutar {binary} en el directorio de trabajo")
        (output / ".openvr-run").write_text("openvr-cuttlefish-r75\n", encoding="utf-8")


def main():
    if len(sys.argv) not in (2, 3):
        raise ValueError("Uso: prepare-guest.py BUNDLE_DIR [RUN_DIR]")
    prepare(Path(sys.argv[1]), Path(sys.argv[2]) if len(sys.argv) == 3 else None)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, tarfile.TarError, zipfile.BadZipFile) as error:
        sys.exit(f"Error al preparar Cuttlefish: {error}")
