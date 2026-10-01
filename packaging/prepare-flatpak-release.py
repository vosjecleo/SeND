#!/usr/bin/env python3
"""Pin the Flatpak wrapper to the published, checksum-verified current build."""
import hashlib
from datetime import date
import os
from pathlib import Path
import re
import urllib.request
import xml.etree.ElementTree as ET


def main():
    release = re.search(r"^version: (\d+\.\d+\.\d+\+\d+)$", Path("pubspec.yaml").read_text(), re.M)[1]
    tag = "v" + release.replace("+", "-b")
    asset = f"SeND-{release}-linux-debian-amd64.deb"
    base = f"https://github.com/VosjeCleo/SeND/releases/download/{tag}/"
    with urllib.request.urlopen(base + "SHA256SUMS", timeout=60) as response:
        checksums = response.read().decode()
    expected = dict((line.split()[1].removeprefix("*"), line.split()[0]) for line in checksums.splitlines())[asset]
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("Invalid package checksum")
    digest = hashlib.sha256()
    with urllib.request.urlopen(base + asset, timeout=120) as response:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise ValueError("Published Debian checksum mismatch")
    manifest = Path("packaging/flatpak/net.deltie.deltiecord.yml")
    text, count = re.subn(r"url: https://github.com/VosjeCleo/SeND/releases/download/[^\n]+\n        sha256: [0-9a-f]+\n        dest-filename: send.deb", f"url: {base}{asset}\n        sha256: {expected}\n        dest-filename: send.deb", manifest.read_text())
    if count != 1:
        raise ValueError("Expected exactly one application source")
    manifest.write_text(text)
    metadata = Path('packaging/flatpak/net.deltie.deltiecord.metainfo.xml')
    tree = ET.parse(metadata)
    releases = tree.getroot().find('releases')
    if not any(item.get('version') == release for item in releases):
        entry = ET.Element('release', version=release, date=date.today().isoformat(), type='development')
        ET.SubElement(ET.SubElement(entry, 'description'), 'p').text = f'Flatpak packaging of SeND {release}. See the release changelog for application changes.'
        releases.insert(0, entry)
        tree.write(metadata, encoding='utf-8', xml_declaration=True)
    if env := os.environ.get("GITHUB_ENV"):
        with open(env, "a") as output:
            output.write(f"SEND_RELEASE={release}\n")
    print(f"Flatpak pinned to verified {release}")


if __name__ == "__main__":
    main()
