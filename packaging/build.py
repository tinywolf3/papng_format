#!/usr/bin/env python3
"""Assemble complete installers from the existing platform builds. No SDK at runtime."""
import argparse
from dataclasses import dataclass
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent
VERSION = (HERE / 'VERSION').read_text().strip()


@dataclass(frozen=True)
class App:
    slug: str
    name: str
    engine: str
    source: str
    desktop_id: str
    extensions: tuple = ('papng', 'png', 'apng')

    def exe(self, platform):
        if self.slug == 'papng-converter':
            return 'PAPNG-Converter.sh' if platform == 'linux' else 'papng-converter.exe'
        if self.engine == 'unreal':
            return 'PapngViewer/Binaries/Linux/PapngViewer' if platform == 'linux' else 'PapngViewer.exe'
        return self.slug + ('.x86_64' if platform == 'linux' else '.exe')


APPS = [
    App('papng-viewer', 'PAPNG Godot Viewer', 'godot', 'viewer', 'org.tinygames.PapngViewer'),
    App('papng-editor', 'PAPNG Godot Editor', 'godot', 'editor', 'org.tinygames.PapngEditor', ('papng', 'png', 'apng', 'gif')),
    App('papng-unity-viewer', 'PAPNG Unity Viewer', 'unity', 'viewer', 'org.tinygames.PapngUnityViewer'),
    App('papng-unreal-viewer', 'PAPNG Unreal Viewer', 'unreal', 'viewer', 'org.tinygames.PapngUnrealViewer'),
    App('papng-converter', 'PAPNG Converter', 'qt', 'converter', 'org.tinygames.PapngConverter', ('mp4', 'webm', 'gif')),
]
MIMES = {'papng': 'application/x-papng', 'png': 'image/png', 'apng': 'image/apng',
         'gif': 'image/gif', 'mp4': 'video/mp4', 'webm': 'video/webm'}
SKIP_DIRS = {'project', 'cmake', 'native-build', 'Saved', 'Intermediate', 'DerivedDataCache', 'licenses_unused', '__pycache__'}
SKIP_ENDINGS = ('.log', '.zip', '.tar.gz', '.sha256', '.pdb', '.debug', '.sym', '.obj', '.exp', '.lib')


def run(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write(path, content, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8')
    path.chmod(0o755 if executable else 0o644)


def app_source(app, platform, inputs):
    path = inputs / platform / app.slug
    return path / 'package' if app.engine == 'qt' else path


def selected_files(app, source, platform):
    # Explicit top-level selection excludes archives, engine project copies and QA.
    if app.engine == 'godot':
        names = [app.exe(platform), 'icon.svg', 'LICENSE.txt', 'Godot-LICENSE.txt',
                 'Godot-COPYRIGHT.txt', 'giflib-LICENSE.txt', 'godot-cpp-LICENSE.txt', 'README.md']
        if app.source == 'editor':
            names.append('papng_gif.so' if platform == 'linux' else 'papng_gif.dll')
        return [source / name for name in names if (source / name).is_file()]
    result = []
    for path in source.rglob('*'):
        rel = path.relative_to(source)
        if any(part in SKIP_DIRS or 'DontShip' in part for part in rel.parts):
            continue
        if path.name.startswith('Manifest_') or path.name in {'associate.py', 'app.json'}:
            continue
        if path.is_file() and not path.name.endswith(SKIP_ENDINGS):
            result.append(path)
    return sorted(result)


def required_files(app, platform):
    result = [app.exe(platform)]
    if app.slug == 'papng-editor':
        result += ['papng_gif.so' if platform == 'linux' else 'papng_gif.dll']
    elif app.engine == 'unity':
        result += [app.slug + '_Data/globalgamemanagers', 'UnityPlayer.so' if platform == 'linux' else 'UnityPlayer.dll']
        result += [app.slug + '_Data/Plugins/x86_64/' + ('libpapng.so' if platform == 'linux' else 'papng.dll')]
    elif app.engine == 'unreal':
        result += ['PapngViewer/Content/Paks/PapngViewer-' + ('Linux' if platform == 'linux' else 'Windows') + '.pak']
    elif app.engine == 'qt':
        suffix = '.exe' if platform == 'windows' else ''
        result += ['papng-converter' + suffix, 'tools/ffmpeg' + suffix, 'tools/ffprobe' + suffix, 'qt.conf', 'licenses/THIRD_PARTY.md']
    return list(dict.fromkeys(result))


def inventory(platform, inputs):
    missing = []
    for app in APPS:
        source = app_source(app, platform, inputs)
        for name in required_files(app, platform):
            if not (source / name).is_file():
                missing.append(str(source / name))
    if missing:
        raise SystemExit('Complete installer requires all five applications. Missing files:\n  ' + '\n  '.join(missing) + '\nBuild instructions: packaging/README.md')


def stage_apps(stage, platform, inputs):
    inventory(platform, inputs)  # Check before replacing any output.
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    manifest = {'suite_version': VERSION, 'platform': platform, 'architecture': 'x86_64', 'apps': []}
    for app in APPS:
        source = app_source(app, platform, inputs)
        files = selected_files(app, source, platform)
        print(f'Staging {app.name}: {len(files)} files', flush=True)
        for path in files:
            # Never bundle an external symlink target without an explicit source build.
            if not path.resolve().is_relative_to(source.resolve()):
                raise SystemExit(f'External payload symlink: {path}')
            destination = stage / app.slug / path.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
        source_readme = ROOT / 'demos' / app.engine / app.source / 'README.md'
        shutil.copy2(source_readme, stage / app.slug / 'README.md')
        version = (source_readme.parent / 'VERSION').read_text().strip()
        manifest['apps'].append({'id': app.slug, 'name': app.name, 'version': version, 'entry_point': app.exe(platform)})
    shutil.copy2(ROOT / 'LICENSE', stage / 'LICENSE.txt')
    write(stage / 'manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    return manifest


def checksums(output, artifacts):
    write(output / 'SHA256SUMS', ''.join(f'{digest(path)}  {path.name}\n' for path in artifacts))


def linux_dependencies(stage):
    # Collect the distro packages backing unbundled ELF dependencies, including plugins.
    dependencies = {'python3', 'xdg-utils', 'shared-mime-info', 'desktop-file-utils', 'libgl1', 'libegl1', 'libvulkan1'}
    system_paths = set()
    for app in APPS:
        base = stage / app.slug
        elves = []
        for path in base.rglob('*'):
            if path.is_file():
                with path.open('rb') as stream:
                    if stream.read(4) == b'\x7fELF':
                        elves.append(path)
        search = sorted({str(path.parent) for path in elves})
        env = dict(os.environ, LD_LIBRARY_PATH=os.pathsep.join(search))
        for path in elves:
            check = subprocess.run(['ldd', str(path)], env=env, capture_output=True, text=True)
            if 'not found' in check.stdout:
                raise SystemExit(f'Unresolved library in {path}:\n{check.stdout}')
            for found in re.findall(r'=> (/[^\s]+)', check.stdout):
                library = Path(found).resolve()
                if not library.is_relative_to(stage.resolve()):
                    system_paths.add(str(library))
    packages = set()
    for offset in range(0, len(system_paths), 80):
        result = run(['dpkg-query', '-S', *sorted(system_paths)[offset:offset + 80]], capture_output=True, text=True)
        for line in result.stdout.splitlines():
            if ': /' in line:
                packages.add(line.split(': /', 1)[0])
    for package in packages:
        version = run(['dpkg-query', '-W', '-f=${Version}\n', package], capture_output=True, text=True).stdout.strip()
        if '\n' in version:
            raise SystemExit(f'Ambiguous dependency architecture: {package}')
        dependencies.add(f'{package.split(":", 1)[0]} (>= {version})')
    return ', '.join(sorted(dependencies))


def prepare_ubuntu_runtime(payload):
    # The system ELF interpreter and glibc must be upgraded together by Ubuntu.
    # Qt's deployment tool can copy these even though our FFmpeg bundler excludes them.
    libraries = payload / 'papng-converter/lib'
    system = re.compile(r'^(ld-linux.*|lib(c|m|dl|pthread|rt|resolv|util|nss_.*)\.so.*)$')
    for path in libraries.iterdir():
        if path.is_file() and system.fullmatch(path.name):
            path.unlink()
    if not shutil.which('patchelf'):
        raise SystemExit('Install patchelf to normalize bundled Ubuntu library paths.')
    for path in libraries.iterdir():
        if not path.is_file():
            continue
        with path.open('rb') as stream:
            if stream.read(4) != b'\x7fELF':
                continue
        rpath = run(['patchelf', '--print-rpath', path], capture_output=True, text=True).stdout.strip()
        if any(part.startswith('/') for part in rpath.split(':')):
            run(['patchelf', '--set-rpath', '$ORIGIN', path])


def ubuntu(output, inputs):
    release = Path('/etc/os-release').read_text() if Path('/etc/os-release').exists() else ''
    if not re.search(r'^ID=ubuntu$', release, re.M) or os.uname().machine != 'x86_64':
        raise SystemExit('Build the Ubuntu amd64 package on the target Ubuntu x86_64 release.')
    ubuntu_version = re.search(r'^VERSION_ID="?([\d.]+)', release, re.M).group(1)
    root = output / 'stage'
    payload = root / 'opt/papng-suite'
    manifest = stage_apps(output / 'payload', 'linux', inputs)
    if root.exists():
        shutil.rmtree(root)
    payload.parent.mkdir(parents=True)
    shutil.move(output / 'payload', payload)
    prepare_ubuntu_runtime(payload)
    dependencies = linux_dependencies(payload)
    manifest['ubuntu_build_release'] = ubuntu_version
    manifest['depends'] = dependencies
    write(payload / 'manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    for app in APPS:
        installed = f'/opt/papng-suite/{app.slug}'
        if app.engine == 'unreal':
            command = f'exec "{installed}/{app.exe("linux")}" PapngViewer -SaveToUserDir "$@"'
        else:
            command = f'exec "{installed}/{app.exe("linux")}"' + (' --' if app.engine == 'godot' else '') + ' "$@"'
        write(root / 'usr/bin' / app.slug, '#!/bin/sh\n' + command + '\n', True)
        (payload / app.slug / app.exe('linux')).chmod(0o755)
        mime = ';'.join(MIMES[ext] for ext in app.extensions) + ';'
        write(root / 'usr/share/applications' / (app.desktop_id + '.desktop'),
              '[Desktop Entry]\nType=Application\nName=' + app.name + '\n'
              f'Exec={app.slug} %f\nIcon={app.desktop_id}\nTerminal=false\n'
              'Categories=Graphics;' + ('Viewer;' if app.source == 'viewer' else '2DGraphics;') + '\n'
              f'MimeType={mime}\nStartupNotify=true\n')
        icon = root / 'usr/share/icons/hicolor/scalable/apps' / (app.desktop_id + '.svg')
        icon.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'demos/godot' / ('editor' if app.source == 'editor' else 'viewer') / 'icon.svg', icon)
    shutil.copy2(HERE / 'linux/defaults.py', payload / 'defaults.py')
    write(root / 'usr/bin/papng-defaults', '#!/bin/sh\nexec python3 /opt/papng-suite/defaults.py "$@"\n', True)
    write(root / 'usr/share/applications/org.tinygames.PapngDefaults.desktop',
          '[Desktop Entry]\nType=Application\nName=PAPNG Default Viewer\nName[ko]=PAPNG 기본 뷰어 설정\n'
          'Comment=Open PAPNG files with the Godot viewer\nExec=papng-defaults install\n'
          'Icon=org.tinygames.PapngViewer\nTerminal=false\nCategories=Settings;\n')
    mime = root / 'usr/share/mime/packages/papng-suite.xml'
    mime.parent.mkdir(parents=True)
    shutil.copy2(HERE / 'linux/tinygames-PapngViewer.xml', mime)
    copyright = root / 'usr/share/doc/papng-suite/copyright'
    copyright.parent.mkdir(parents=True)
    shutil.copy2(ROOT / 'LICENSE', copyright)
    shutil.copy2(HERE / 'README.md', copyright.parent / 'README.md')
    changelog = f'papng-suite ({VERSION}) unstable; urgency=medium\n\n  * Install the PAPNG desktop applications, menus and MIME handlers.\n\n -- PAPNG contributors <noreply@tinygames.invalid>  Sun, 27 Sep 2026 00:00:00 +0000\n'
    (copyright.parent / 'changelog.gz').write_bytes(gzip.compress(changelog.encode(), mtime=0))
    size = sum(path.stat().st_size for path in root.rglob('*') if path.is_file()) // 1024
    write(root / 'DEBIAN/control', f'Package: papng-suite\nVersion: {VERSION}\nArchitecture: amd64\n'
          'Maintainer: PAPNG contributors <noreply@tinygames.invalid>\nSection: graphics\nPriority: optional\n'
          f'Installed-Size: {size}\nDepends: {dependencies}\n'
          'Homepage: https://github.com/tinywolf3/papng_format\n'
          'Description: PAPNG viewers, pixel editor and video converter\n'
          f' Godot, Unity and Unreal viewers, Godot editor, Qt converter.\n Built on Ubuntu {ubuntu_version}.\n')
    write(root / 'DEBIAN/postinst', '#!/bin/sh\nset -e\nif [ "$1" = configure ]; then\n'
          ' python3 /opt/papng-suite/defaults.py --system install\n'
          ' update-mime-database /usr/share/mime\n update-desktop-database /usr/share/applications\nfi\n', True)
    write(root / 'DEBIAN/prerm', '#!/bin/sh\nset -e\nif [ "$1" = remove ] || [ "$1" = deconfigure ]; then\n'
          ' python3 /opt/papng-suite/defaults.py --system remove\nfi\n', True)
    write(root / 'DEBIAN/postrm', '#!/bin/sh\nset -e\nif [ "$1" = remove ] || [ "$1" = purge ]; then\n'
          ' if command -v update-mime-database >/dev/null; then update-mime-database /usr/share/mime; fi\n'
          ' if command -v update-desktop-database >/dev/null; then update-desktop-database /usr/share/applications; fi\n'
          ' rmdir /var/lib/papng-suite 2>/dev/null || true\nfi\n', True)
    for desktop in (root / 'usr/share/applications').glob('*.desktop'):
        run(['desktop-file-validate', desktop])
    # Normalize copied build modes; no root-owned application ever needs setuid or write access.
    for path in root.rglob('*'):
        path.chmod(0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)
    artifact = output / f'papng-suite_{VERSION}_ubuntu-{ubuntu_version}_amd64.deb'
    run(['dpkg-deb', '--root-owner-group', '-Zzstd', '-z9', '--threads-max=4', '--build', root, artifact])
    shutil.copy2(payload / 'manifest.json', output / 'manifest.json')
    checksums(output, [artifact, output / 'manifest.json'])
    print('Installer:', artifact)


def nsis_literal(value):
    return str(value).replace('$', '$$').replace('"', '$\\"')


def windows(output, inputs, vc_runtime=None, vc_notices=None):
    stage = output / 'payload'
    stage_apps(stage, 'windows', inputs)
    crt_names = ['msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll']
    if vc_runtime:
        if not all((vc_runtime / name).is_file() for name in crt_names) or not vc_notices or not vc_notices.is_file():
            raise SystemExit('Supply the x64 Microsoft.VC143.CRT redistributable directory and its license notice via --vc-runtime-dir and --vc-runtime-notices.')
        destinations = {exe.parent for exe in stage.rglob('*.exe')}
        for destination in destinations:
            for dll in vc_runtime.glob('*.dll'):
                shutil.copy2(dll, destination / dll.name)
        licenses = stage / 'licenses'
        licenses.mkdir(exist_ok=True)
        shutil.copy2(vc_notices, licenses / ('MSVC-Runtime' + vc_notices.suffix))
    # Installed applications must not rely on a development machine's CRT.
    for app in APPS:
        if app.engine in {'qt', 'unreal', 'unity'}:
            directories = {(stage / app.slug / app.exe('windows')).parent}
            if app.engine == 'unreal':
                directories.update(exe.parent for exe in (stage / app.slug / 'PapngViewer/Binaries').rglob('*.exe'))
            for directory in directories:
                if not all((directory / name).is_file() for name in crt_names):
                    raise SystemExit(f'Missing bundled MSVC runtime at {directory}. Supply --vc-runtime-dir and --vc-runtime-notices; do not copy DLLs from System32.')
    artifact = output / f'PAPNG-Suite-{VERSION}-windows-x64-setup.exe'
    define = '\n'.join(f'!define {name} "{nsis_literal(value)}"' for name, value in {
        'OUTPUT': artifact, 'VERSION': VERSION, 'LICENSE_FILE': ROOT / 'LICENSE'}.items()) + '\n'
    install, remove, register, unregister = [], [], [], []
    directories = set()
    for path in sorted(stage.rglob('*')):
        if not path.is_file():
            continue
        rel = path.relative_to(stage)
        parent = str(rel.parent).replace('/', '\\')
        parent = '' if parent == '.' else '\\' + parent
        install += [f'SetOutPath "$INSTDIR{nsis_literal(parent)}"', f'File "{nsis_literal(path)}"']
        relative = str(rel).replace('/', '\\')
        remove += [f'Delete "$INSTDIR\\{nsis_literal(relative)}"']
        for directory in rel.parents:
            if str(directory) != '.':
                directories.add(str(directory).replace('/', '\\'))
    remove += [f'RMDir "$INSTDIR\\{nsis_literal(directory)}"' for directory in sorted(directories, key=lambda s: s.count('\\'), reverse=True)]
    for app in APPS:
        exe = '$INSTDIR\\' + app.slug + '\\' + app.exe('windows').replace('/', '\\')
        base = 'Software\\Classes\\' + app.desktop_id
        capabilities = 'Software\\TinyGames\\PAPNG Suite\\' + app.slug + '\\Capabilities'
        argument = '-- ' if app.engine == 'godot' else '-SaveToUserDir -PapngFile=' if app.engine == 'unreal' else ''
        command = '$\\"' + exe + '$\\" ' + argument + '$\\"%1$\\"'
        menu_args = '-SaveToUserDir' if app.engine == 'unreal' else ''
        register += [
            f'CreateShortcut "$SMPROGRAMS\\PAPNG\\{app.name}.lnk" "{exe}" "{menu_args}"',
            f'WriteRegStr HKCU "{base}" "" "{app.name}"',
            f'WriteRegStr HKCU "{base}\\Application" "ApplicationName" "{app.name}"',
            f'WriteRegStr HKCU "{base}\\DefaultIcon" "" \'$\\"{exe}$\\",0\'',
            f'WriteRegStr HKCU "{base}\\shell\\open\\command" "" \'{command}\'',
            f'WriteRegStr HKCU "{capabilities}" "ApplicationName" "{app.name}"',
            f'WriteRegStr HKCU "{capabilities}" "ApplicationDescription" "{app.name}"',
            f'WriteRegStr HKCU "Software\\RegisteredApplications" "{app.name}" "{capabilities}"']
        unregister += [f'Delete "$SMPROGRAMS\\PAPNG\\{app.name}.lnk"',
                       f'DeleteRegKey HKCU "{base}"',
                       f'DeleteRegValue HKCU "Software\\RegisteredApplications" "{app.name}"']
        for ext in app.extensions:
            register += [f'WriteRegStr HKCU "Software\\Classes\\.{ext}\\OpenWithProgids" "{app.desktop_id}" ""',
                         f'WriteRegStr HKCU "{capabilities}\\FileAssociations" ".{ext}" "{app.desktop_id}"']
            unregister += [f'DeleteRegValue HKCU "Software\\Classes\\.{ext}\\OpenWithProgids" "{app.desktop_id}"']
    for name, lines in [('InstallPayload', install), ('RemovePayload', remove), ('RegisterApps', register), ('UnregisterApps', unregister)]:
        define += f'\n!macro {name}\n' + '\n'.join(lines) + '\n!macroend\n'
    write(output / 'payload.nsh', define)
    shutil.copy2(HERE / 'windows/suite.nsi', output / 'suite.nsi')
    compiler = shutil.which('makensis') or shutil.which('makensis.exe')
    if not compiler:
        raise SystemExit(f'Install NSIS 3 and run makensis "{output / "suite.nsi"}". All five payloads are staged.')
    run([compiler, '-V2' if os.name != 'nt' else '/V2', output / 'suite.nsi'])
    shutil.copy2(stage / 'manifest.json', output / 'manifest.json')
    checksums(output, [artifact, output / 'manifest.json'])
    print('Installer:', artifact)


def android(output, inputs, apk_dir):
    sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Android/Sdk'))
    tools = sorted((sdk / 'build-tools').glob('*'), reverse=True)
    if not tools:
        raise SystemExit('Set ANDROID_HOME to an SDK with build-tools (aapt, apksigner and zipalign).')
    tool = tools[0]
    suffix = '.exe' if os.name == 'nt' else ''
    signer = tool / ('apksigner.bat' if os.name == 'nt' else 'apksigner')
    records = []
    for app in APPS[:2]:
        apk = apk_dir / (app.slug + '.apk') if apk_dir else inputs / 'android' / app.slug / (app.slug + '-debug.apk')
        if not apk.is_file():
            raise SystemExit(f'Missing APK: {apk}')
        signing = run([signer, 'verify', '--verbose', '--print-certs', apk], capture_output=True, text=True).stdout
        run([tool / ('zipalign' + suffix), '-c', '-P', '16', '4', apk], capture_output=True)
        badging = run([tool / ('aapt' + suffix), 'dump', 'badging', apk], capture_output=True, text=True).stdout
        package = 'org.tinygames.papng' + app.source
        if "package: name='" + package + "'" not in badging:
            raise SystemExit(f'Incorrect package ID: {apk}')
        manifest = run([tool / ('aapt' + suffix), 'dump', 'xmltree', apk, 'AndroidManifest.xml'], capture_output=True, text=True).stdout
        # aapt badging omits activity-alias launchers in some SDK releases.
        components = [match.group(0) for match in re.finditer(r'(?ms)^      E: activity(?:-alias)? .*?(?=^      E: |\Z)', manifest)]
        exported = [block for block in components if re.search(r'(?m)^        A: android:exported.*0xffffffff', block)]
        if not any('android.intent.action.MAIN' in block and 'android.intent.category.LAUNCHER' in block for block in exported):
            raise SystemExit(f'Missing exported launcher activity or alias: {apk}')
        for action in ['VIEW', 'SEND']:
            if not any('android.intent.action.' + action in block and 'application/x-papng' in block for block in exported):
                raise SystemExit(f'Missing exported PAPNG {action} handler: {apk}')
        debug = 'application-debuggable' in badging
        version = re.search(r"versionName='([^']+)'", badging).group(1)
        cert = re.search(r'Signer #1 certificate SHA-256 digest: (\w+)', signing).group(1)
        records.append({'id': package, 'name': app.name, 'version': version, 'debuggable': debug,
                        'apk': app.slug + '.apk', 'sha256': digest(apk), 'certificate_sha256': cert, 'source': apk})
    bundle = output / 'package'
    if bundle.exists():
        shutil.rmtree(bundle)
    bundle.mkdir()
    for item in records:
        shutil.copy2(item.pop('source'), bundle / item['apk'])
    for app in APPS[:2]:
        notices = bundle / 'licenses' / app.slug
        notices.mkdir(parents=True)
        shutil.copy2(ROOT / 'LICENSE', notices / 'PAPNG-MIT.txt')
        for name in ['Godot-LICENSE.txt', 'Godot-COPYRIGHT.txt', 'giflib-LICENSE.txt', 'godot-cpp-LICENSE.txt']:
            source = inputs / 'android' / app.slug / name
            if source.exists():
                shutil.copy2(source, notices / name)
    shutil.copy2(HERE / 'android/install.py', bundle / 'install.py')
    shutil.copy2(HERE / 'README.md', bundle / 'README.md')
    write(bundle / 'manifest.json', json.dumps({'suite_version': VERSION, 'platform': 'android', 'apps': records}, indent=2) + '\n')
    label = '-debug' if any(item['debuggable'] for item in records) else ''
    artifact = output / f'PAPNG-Suite-{VERSION}-android{label}.zip'
    with zipfile.ZipFile(artifact, 'w', compression=zipfile.ZIP_STORED) as archive:
        for path in sorted(bundle.rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(bundle))
    checksums(output, [artifact])
    print('Installer bundle:', artifact)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=['ubuntu', 'windows', 'android'])
    parser.add_argument('--inputs', type=Path, default=ROOT / 'builds', help='Existing platform build tree')
    parser.add_argument('--check', action='store_true', help='Check desktop app payloads without building')
    parser.add_argument('--apk-dir', type=Path, help='Signed papng-viewer.apk and papng-editor.apk (default: local debug builds)')
    parser.add_argument('--vc-runtime-dir', type=Path, help='Windows x64 Microsoft.VC143.CRT redistribution directory')
    parser.add_argument('--vc-runtime-notices', type=Path, help='License notice for the selected Microsoft runtime')
    args = parser.parse_args()
    platform = 'linux' if args.platform == 'ubuntu' else args.platform
    if args.check:
        if platform == 'android':
            parser.error('--check applies to desktop payloads; Android assembly verifies signatures and manifests.')
        inventory(platform, args.inputs.resolve())
        print('All five application payloads are present.')
        return
    output = ROOT / 'builds' / platform / 'papng-suite'
    output.mkdir(parents=True, exist_ok=True)
    if args.platform == 'ubuntu':
        ubuntu(output, args.inputs.resolve())
    elif args.platform == 'windows':
        windows(output, args.inputs.resolve(), args.vc_runtime_dir, args.vc_runtime_notices)
    else:
        android(output, args.inputs.resolve(), args.apk_dir.resolve() if args.apk_dir else None)


if __name__ == '__main__':
    main()
