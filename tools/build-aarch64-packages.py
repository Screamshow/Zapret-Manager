#!/usr/bin/env python3
"""Repackage pinned ARMv8 payloads for APK's unified aarch64 architecture.

Requires apk-tools 3 and PyYAML. Does not publish, install or sign packages.
Preserves upstream payloads, licenses, dependencies and lifecycle scripts.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.request
import zipfile

import yaml

SOURCES = [
    ("zapret", "https://github.com/remittor/zapret-openwrt/releases/download/v72.20260307/zapret_v72.20260307_aarch64_generic.zip",
     "db61dc1ecbe27a80bfad1272d9db4526d1cd74070bf85524a14ec0b7e4b48f39"),
    ("zapret2", "https://packages.routerich.ru/25.12/mediatek/filogic/routerich/zapret2-1.0.5.2-r15.apk",
     "7d93fb4e6003e23690dbe3ea59af3720fd77ee8d7d96fc3e3e41b21aa2276545"),
    ("luci-app-zapret2", "https://packages.routerich.ru/25.12/mediatek/filogic/routerich/luci-app-zapret2-1.0.5.2-r15.apk",
     "01854d2f25c1abbce6de33e956aface1d5092206f7062affab8dd29f27c27cf7"),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(apk, path):
    return yaml.safe_load(subprocess.check_output(
        [apk, "adbdump", "--allow-untrusted", str(path)], text=True))


def inventory(root):
    result = {}
    for p in sorted(root.rglob("*")):
        key = str(p.relative_to(root))
        if p.is_symlink():
            result[key] = ["link", str(p.readlink())]
        elif p.is_file():
            result[key] = ["file", p.stat().st_mode & 0o7777, p.stat().st_uid, p.stat().st_gid, sha(p)]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--arch", choices=("aarch64", "aarch64_cortex-a73"), default="aarch64")
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise RuntimeError("Run as root or under unshare -r to preserve package root ownership")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    manifest = {"schema": 1, "profile": "openwrt-" + args.arch, "packages": []}
    with tempfile.TemporaryDirectory(prefix="zms-aarch64-") as temporary:
        work = Path(temporary)
        inputs = []
        for name, url, digest in SOURCES:
            source = work / (name + (".zip" if url.endswith(".zip") else ".apk"))
            urllib.request.urlretrieve(url, source)
            if sha(source) != digest:
                raise RuntimeError(f"Source checksum mismatch: {url}")
            if url.endswith(".zip"):
                with zipfile.ZipFile(source) as archive:
                    for member in archive.namelist():
                        if member.startswith("apk/") and member.endswith(".apk"):
                            target = work / Path(member).name
                            target.write_bytes(archive.read(member))
                            inputs.append((target, url, digest))
            else:
                inputs.append((source, url, digest))
        for source, url, digest in inputs:
            metadata = dump(args.apk, source)
            info = metadata["info"]
            name = info["name"]
            if name not in ("zapret", "zapret2", "luci-app-zapret", "luci-app-zapret2"):
                raise RuntimeError(f"Unexpected package {name}")
            old_arch = info["arch"]
            expected_arch = "noarch" if name.startswith("luci-") else (
                "aarch64_generic" if name == "zapret" else "aarch64_cortex-a53")
            if old_arch != expected_arch:
                raise RuntimeError(f"Unexpected source architecture {name}: {old_arch}")
            root = work / (name + "-root")
            root.mkdir()
            subprocess.run([args.apk, "extract", "--allow-untrusted", "--destination", str(root), str(source)], check=True)
            # apk extract does not restore symlink timestamps. Restore them
            # explicitly so the complete ADB path metadata remains identical.
            for directory in metadata.get("paths", []):
                for entry in directory.get("files", []):
                    if "target" in entry and "mtime" in entry:
                        link = root / directory.get("name", "") / entry["name"]
                        os.utime(link, (entry["mtime"], entry["mtime"]), follow_symlinks=False)
            before = inventory(root)
            # Reject payloads containing non-AArch64 ELF executables/libraries.
            elf = []
            for p in root.rglob("*"):
                if p.is_file() and not p.is_symlink():
                    header = p.read_bytes()[:20]
                    if header[:4] == b"\x7fELF":
                        # Upstream ships an inert Huawei E8372 ARM32 sample
                        # module under files/; it is not an installed core.
                        if str(p.relative_to(root)) == "opt/zapret/files/huawei/E8372/unfuck_nfqueue.ko":
                            continue
                        if header[4:6] != b"\x02\x01" or int.from_bytes(header[18:20], "little") != 183:
                            raise RuntimeError(f"Unexpected ELF ABI: {p}")
                        elf.append(str(p.relative_to(root)))
            if not name.startswith("luci-") and not elf:
                raise RuntimeError(f"Missing ARM64 executable: {name}")
            version = re.sub(r"-r\d+$", "-r100", info["version"])
            arch = "noarch" if name.startswith("luci-") else args.arch
            target = output / f"{name}-{version}.apk"
            command = [args.apk, "mkpkg", "--files", str(root), "--output", str(target)]
            for field in ("name", "description", "license", "origin", "maintainer", "url", "depends", "provides", "replaces", "install-if", "provider-priority", "layer"):
                if field in info:
                    value = info[field]
                    if isinstance(value, list):
                        value = " ".join(value)
                    if isinstance(value, str):
                        # adbdump emits long strings as YAML literal blocks,
                        # whose trailing newline must not enter APK's FDB.
                        value = value.rstrip("\n")
                        if "\n" in value or "\r" in value:
                            raise RuntimeError(f"Multiline package info field: {field}")
                    command += ["-I", f"{field}:{value}"]
            command += ["-I", f"version:{version}", "-I", f"arch:{arch}"]
            for kind, script in metadata.get("scripts", {}).items():
                script_path = work / (name + "-" + kind)
                script_path.write_text(script)
                command += ["-s", f"{kind}:{script_path}"]
            for trigger in metadata.get("triggers", []):
                command += ["-t", trigger]
            subprocess.run(command, check=True)
            after = dump(args.apk, target)
            assert after.get("scripts", {}) == metadata.get("scripts", {})
            # Includes ownership, permissions, symlinks, mtimes and file hashes.
            assert after.get("paths", []) == metadata.get("paths", []), "Payload metadata changed"
            assert after.get("triggers", []) == metadata.get("triggers", [])
            for field in ("depends", "provides", "replaces", "install-if"):
                assert after["info"].get(field) == info.get(field), field
            check = work / (name + "-check")
            check.mkdir()
            subprocess.run([args.apk, "extract", "--allow-untrusted", "--destination", str(check), str(target)], check=True)
            assert inventory(check) == before, "Payload or file permissions changed"
            manifest["packages"].append({"name": name, "version": version, "architecture": arch,
                "file": target.name, "size": target.stat().st_size, "sha256": sha(target),
                "source_url": url, "source_sha256": digest, "source_package_sha256": sha(source),
                "source_architecture": old_arch, "elf_files": elf})
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
