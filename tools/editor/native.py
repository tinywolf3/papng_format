#!/usr/bin/env python3
"""Build the embedded giflib extension. Sources and outputs remain under builds/."""
import argparse
import hashlib
import os
from pathlib import Path
import platform as host_platform
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'demos/godot/editor/native'
CPP_URL = 'https://codeload.github.com/godotengine/godot-cpp/tar.gz/refs/tags/godot-4.4-stable'
CPP_SHA = '472c6e7f3f7a9d576f21e2c57d16390b46d238f98e69a47d84730e943f5c5506'


def host():
    return {'Linux': 'linux', 'Windows': 'windows'}.get(host_platform.system(), 'linux')


def cpp_source():
    cache = ROOT / 'builds' / host() / 'editor-native-tools'
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / 'godot-cpp-4.4.tar.gz'
    if not archive.exists():
        print('Downloading pinned godot-cpp 4.4 bindings...', flush=True)
        with urllib.request.urlopen(CPP_URL, timeout=60) as response:
            archive.write_bytes(response.read())
    if hashlib.sha256(archive.read_bytes()).hexdigest() != CPP_SHA:
        raise SystemExit(f'godot-cpp archive checksum mismatch: {archive}')
    source = cache / 'godot-cpp-godot-4.4-stable'
    if not (source / 'CMakeLists.txt').exists():
        with tarfile.open(archive) as bundle:
            for item in bundle.getmembers():
                target = (cache / item.name).resolve()
                if not target.is_relative_to(cache.resolve()) or not (item.isfile() or item.isdir()):
                    raise SystemExit('Unsafe godot-cpp archive entry')
                if item.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(bundle.extractfile(item).read())
    return source


def build(target):
    if not shutil.which('cmake'):
        raise SystemExit('Install CMake 3.22+ and a C/C++ compiler to build the bundled GIF decoder.')
    source = cpp_source()
    variants = ['arm64-v8a', 'x86_64'] if target == 'android' else ['x86_64']
    outputs = []
    for arch in variants:
        out = ROOT / 'builds' / target / 'papng-editor/native'
        if target == 'android': out /= arch
        work = ROOT / 'builds' / target / 'papng-editor/native-build' / arch
        args = ['cmake', '-S', str(SOURCE), '-B', str(work), '-DCMAKE_BUILD_TYPE=Release',
                '-DCMAKE_POLICY_VERSION_MINIMUM=3.5', '-DPAPNG_OUTPUT_DIR=' + str(out),
                '-DFETCHCONTENT_SOURCE_DIR_GODOT_CPP=' + str(source)]
        if target == 'windows' and host() != 'windows':
            if not shutil.which('x86_64-w64-mingw32-g++'):
                raise SystemExit('Windows cross-build requires MinGW-w64 (x86_64-w64-mingw32-g++). Native Windows builds can use Visual Studio C++ tools.')
            args += ['-DCMAKE_SYSTEM_NAME=Windows', '-DCMAKE_SYSTEM_PROCESSOR=x86_64',
                     '-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc', '-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++']
        elif target == 'android':
            sdk = Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Android/Sdk')))
            ndk = Path(os.environ.get('ANDROID_NDK_HOME', str(sdk / 'ndk/28.2.13676358')))
            toolchain = ndk / 'build/cmake/android.toolchain.cmake'
            if not toolchain.exists(): raise SystemExit('Install Android NDK 28.2.13676358 or set ANDROID_NDK_HOME.')
            args += ['-DCMAKE_TOOLCHAIN_FILE=' + str(toolchain), '-DANDROID_ABI=' + arch,
                     '-DANDROID_PLATFORM=android-24', '-DANDROID_STL=c++_static']
        elif target != host():
            raise SystemExit(f'Build {target} on that platform, or supply a supported cross toolchain.')
        work.mkdir(parents=True, exist_ok=True)
        log = work / 'build.log'
        print(f'Building embedded GIF decoder: {target}/{arch} ({log.relative_to(ROOT)})', flush=True)
        with log.open('w') as stream:
            for command in [args, ['cmake', '--build', str(work), '--config', 'Release', '--target', 'papng_gif', '--parallel', str(min(os.cpu_count() or 2, 8))]]:
                result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
                stream.flush()
                if result.returncode:
                    print(log.read_text()[-8000:])
                    raise SystemExit(f'GIF decoder build failed: {log}')
        library = out / ('papng_gif.dll' if target == 'windows' else 'libpapng_gif.so' if target == 'android' else 'papng_gif.so')
        if not library.is_file(): raise SystemExit(f'GIF library missing after build: {library}')
        outputs.append(library)
    return outputs


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('platform', choices=['linux', 'windows', 'android'], nargs='?', default=host())
    for library in build(parser.parse_args().platform): print(f'BUILT: {library}')
