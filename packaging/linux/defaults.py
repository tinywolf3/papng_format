#!/usr/bin/env python3
"""Manage only PAPNG's MIME default, preserving other settings and later choices."""
import argparse
import configparser
import os
from pathlib import Path
import tempfile

MIME = 'application/x-papng'
DESKTOP = 'org.tinygames.PapngViewer.desktop'
SECTION = 'Default Applications'


def read(path):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    if path.exists():
        parser.read_string(path.read_text())
    return parser


def replace_entry(text, value):
    # Edit one key without rewriting comments, ordering or unrelated sections.
    lines = text.splitlines(keepends=True)
    result, inside, found_section, written = [], False, False, False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith('[') and stripped.endswith(']'):
            if inside and not written and value is not None:
                result.append(f'{MIME}={value}\n')
                written = True
            inside = stripped == f'[{SECTION}]'
            found_section |= inside
        if inside and stripped.split('=', 1)[0].strip() == MIME:
            if not written and value is not None:
                result.append(f'{MIME}={value}\n')
            written = True
            continue
        result.append(line if line.endswith('\n') else line + '\n')
    if value is not None and not written:
        if not found_section:
            result.append(f'\n[{SECTION}]\n')
        result.append(f'{MIME}={value}\n')
    return ''.join(result)


def atomic_write(path, content, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.papng-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(content)
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def update(config, backup, remove=False, explicit=False):
    current = read(config).get(SECTION, MIME, fallback=None)
    if remove:
        if not backup.exists():
            return
        saved = read(backup)
        # Respect a choice made after installation, including an explicit removal.
        if current == DESKTOP + ';':
            previous = saved.get('backup', 'previous', fallback=None)
            content = replace_entry(config.read_text(), previous)
            atomic_write(config, content, config.stat().st_mode & 0o777)
        backup.unlink()
    else:
        first_install = not backup.exists()
        if first_install:
            atomic_write(backup, '[backup]\n' + (f'previous={current}\n' if current is not None else ''), 0o600)
        if first_install or explicit:
            content = config.read_text() if config.exists() else ''
            atomic_write(config, replace_entry(content, DESKTOP + ';'), config.stat().st_mode & 0o777 if config.exists() else 0o644)
        # Upgrades do not reclaim a default that the user subsequently changed.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['install', 'remove'])
    parser.add_argument('--system', action='store_true')
    args = parser.parse_args()
    if args.system:
        config = Path('/etc/xdg/mimeapps.list')
        backup = Path('/var/lib/papng-suite/default-backup.ini')
    else:
        desktop = os.environ.get('XDG_CURRENT_DESKTOP', '').split(':')[0].lower()
        filename = (desktop + '-' if desktop and desktop.replace('-', '').isalnum() else '') + 'mimeapps.list'
        config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / filename
        backup = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'papng-suite' / (filename + '.backup')
    update(config, backup, args.action == 'remove', explicit=not args.system)
    if not args.system and args.action == 'install':
        print('PAPNG files now open in the Godot viewer.')


if __name__ == '__main__':
    main()
