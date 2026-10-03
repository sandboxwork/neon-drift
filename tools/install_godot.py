#!/usr/bin/env python3
"""Install the pinned Godot editor and selected templates into .cache/godot.

python3 tools/install_godot.py --templates ios web
Downloads official GitHub release archives and verifies SHA-256 before extraction.
Uses only Python's standard library. Does not change system installations.
"""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import platform
import shutil
import urllib.request
import zipfile

VERSION = "4.6.3-stable"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}/"
ARTIFACTS = {
    "Darwin": (f"Godot_v{VERSION}_macos.universal.zip", "30630f3e9b11e10b35c1f90ba8814185dcec43fae1a48345159be7552c64bfe8", "Godot.app/Contents/MacOS/Godot"),
    "Linux": (f"Godot_v{VERSION}_linux.x86_64.zip", "d0bc2113065e481c9c2c2b2c37daa4e8be3fe9e27f0ab9ab0b6096e9a37907f3", f"Godot_v{VERSION}_linux.x86_64"),
    "Linux-arm64": (f"Godot_v{VERSION}_linux.arm64.zip", "90c70382eee1542904bf507b9bdc6e62a230ac73fd214bf3887a9e0a4d85aeed", f"Godot_v{VERSION}_linux.arm64"),
}
TEMPLATES_HASH = "3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8"


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def download(directory: Path, name: str, expected: str) -> Path:
    path = directory / name
    if path.is_file() and digest(path) == expected:
        return path
    partial = path.with_suffix(path.suffix + ".partial")
    print(f"Downloading {name} (export templates are approximately 1.26 GB)", flush=True)
    with urllib.request.urlopen(BASE + name, timeout=120) as response, partial.open("wb") as output:
        shutil.copyfileobj(response, output)
    if digest(partial) != expected:
        raise RuntimeError(f"SHA-256 mismatch: {name}")
    partial.replace(path)
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parent.parent / ".cache/godot")
    parser.add_argument("--templates", nargs="+", choices=["ios", "web"], default=["ios"])
    args = parser.parse_args()
    system = platform.system()
    if system == "Linux" and platform.machine() in {"aarch64", "arm64"}:
        system = "Linux-arm64"
    elif system == "Linux" and platform.machine() not in {"x86_64", "amd64"}:
        parser.error("Unsupported Linux architecture; supply an official Godot 4.6.3 binary manually.")
    if system not in ARTIFACTS:
        parser.error("Installer supports macOS and Linux. Install Godot 4.6.3 manually on other hosts.")
    directory = args.directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    name, checksum, member = ARTIFACTS[system]
    with zipfile.ZipFile(download(directory, name, checksum)) as archive:
        (directory / "godot").write_bytes(archive.read(member))
    (directory / "godot").chmod(0o755)
    templates = directory / "templates"
    templates.mkdir(exist_ok=True)
    with zipfile.ZipFile(download(directory, f"Godot_v{VERSION}_export_templates.tpz", TEMPLATES_HASH)) as archive:
        names = (["ios.zip"] if "ios" in args.templates else [])
        if "web" in args.templates:
            names += ["web_nothreads_debug.zip", "web_nothreads_release.zip"]
        for name in names:
            (templates / name).write_bytes(archive.read("templates/" + name))
    print(f"Godot: {directory / 'godot'}\nTemplates: {templates}")


if __name__ == "__main__":
    main()
