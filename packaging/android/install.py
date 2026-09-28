#!/usr/bin/env python3
"""Optional USB installation of the two APKs. Normal on-device installation also works."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb', help='Android SDK platform-tools adb executable')
    parser.add_argument('--serial', help='Device serial, required when multiple devices are connected')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / 'manifest.json').read_text())  # Generated strict JSON.
    for item in manifest['apps']:
        path = root / item['apk']
        if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            raise SystemExit(f'Checksum mismatch: {path.name}')
    command = [args.adb] + (['-s', args.serial] if args.serial else [])
    for item in manifest['apps']:
        print('Installing ' + item['name'], flush=True)
        subprocess.run([*command, 'install', '-r', str(root / item['apk'])], check=True)
    print('Installed. Open a .papng file and choose PAPNG Viewer, then Always if offered.')
    print('If a different signing key is reported, do not uninstall until your editor files are backed up.')


if __name__ == '__main__':
    main()
