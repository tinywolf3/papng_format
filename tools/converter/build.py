#!/usr/bin/env python3
"""Build on the target OS; optionally deploy Qt and an explicitly chosen FFmpeg pair."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "demos/qt/converter"


def run(args, **kwargs):
    print("+", subprocess.list2cmdline([str(a) for a in args]), flush=True)
    subprocess.run([str(a) for a in args], check=True, **kwargs)


def tools_path(directory, name):
    suffix = ".exe" if sys.platform == "win32" else ""
    path = Path(directory) / (name + suffix) if directory else Path(shutil.which(name + suffix) or "__missing__")
    if not path.is_file():
        raise SystemExit(f"Missing {name}. Supply --ffmpeg-dir with both ffmpeg and ffprobe.")
    return path.resolve()


def bundle_linux_dependencies(executables, target):
    # ldd is used only on the local, user-selected tools, never an input video.
    system = re.compile(r"^(ld-linux.*|lib(c|m|dl|pthread|rt|resolv|util|nss_.*)\.so.*)$")
    libraries = {}
    for executable in executables:
        output = subprocess.run(["ldd", str(executable)], text=True, capture_output=True)
        if output.returncode:
            if "not a dynamic executable" in output.stderr or "statically linked" in output.stdout:
                continue
            raise SystemExit(output.stderr)
        if "not found" in output.stdout:
            raise SystemExit(f"Unresolved dependency in {executable}:\n{output.stdout}")
        for line in output.stdout.splitlines():
            match = re.search(r"=> (/\S+) \(", line)
            if match:
                path = Path(match[1])
                if not system.match(path.name):
                    libraries[path.name] = path
    target.mkdir(parents=True, exist_ok=True)
    for name, path in libraries.items():
        dest = target / name
        # Qt deployment can already have installed a symlink with this name.
        if not dest.exists():
            shutil.copy2(path.resolve(), dest)
    return libraries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", action="store_true", help="Create a runnable folder with Qt and FFmpeg")
    parser.add_argument("--ffmpeg-dir", help="Folder containing trusted FFmpeg/ffprobe binaries")
    parser.add_argument("--ffmpeg-notices", type=Path, help="License notices supplied with this FFmpeg build (required for Windows packaging)")
    parser.add_argument("--qt-prefix", help="Qt SDK prefix, e.g. C:/Qt/6.10.2/msvc2022_64")
    parser.add_argument("--generator", help="CMake generator; defaults to Ninja when available")
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 2))
    args = parser.parse_args()
    platform = "windows" if sys.platform == "win32" else "linux" if sys.platform.startswith("linux") else None
    if not platform:
        raise SystemExit("Linux and Windows are supported.")
    output = ROOT / "builds" / platform / "papng-converter"
    build = output / "cmake"
    if args.package and platform == "linux" and not shutil.which("patchelf"):
        raise SystemExit("Linux packaging requires patchelf (sudo apt install patchelf).")
    configure = ["cmake", "-S", SOURCE, "-B", build, "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_RUNTIME_OUTPUT_DIRECTORY={output}"]
    generator = args.generator or ("Ninja" if shutil.which("ninja") else None)
    if platform == "linux" and shutil.which("patchelf"):
        configure += ["-DQT_DEPLOY_USE_PATCHELF=ON"]
    if generator:
        configure += ["-G", generator]
    if args.qt_prefix:
        configure += [f"-DCMAKE_PREFIX_PATH={args.qt_prefix}"]
    run(configure)
    run(["cmake", "--build", build, "--config", "Release", "--parallel", str(max(1, args.jobs))])
    if args.package:
        ffmpeg = tools_path(args.ffmpeg_dir, "ffmpeg")
        ffprobe = tools_path(args.ffmpeg_dir, "ffprobe")
        if platform == "windows" and not args.ffmpeg_notices:
            raise SystemExit("Supply --ffmpeg-notices from your chosen Windows FFmpeg distribution.")
        package = output / "package"
        # Only replace this app's disposable packaging directory.
        if package.exists():
            shutil.rmtree(package)
        run(["cmake", "--install", build, "--config", "Release", "--prefix", package])
        (package / "tools").mkdir(exist_ok=True)
        notices = package / "licenses"
        notices.mkdir(exist_ok=True)
        shutil.copy2(ROOT / "LICENSE", notices / "PAPNG-MIT.txt")
        shutil.copy2(SOURCE / "THIRD_PARTY.md", notices)
        for tool in [ffmpeg, ffprobe]:
            shutil.copy2(tool, package / "tools" / tool.name)
        libraries = {}
        if platform == "linux":
            libraries = bundle_linux_dependencies([ffmpeg, ffprobe], package / "lib")
            # A relocatable launcher supplies the transitive shared-library path.
            launcher = package / "PAPNG-Converter.sh"
            launcher.write_text('#!/bin/sh\napp_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\nexport LD_LIBRARY_PATH="$app_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexec "$app_dir/papng-converter" "$@"\n')
            launcher.chmod(0o755)
            # Include installed distro copyright notices for bundled libraries.
            if shutil.which("dpkg-query"):
                files = [ffmpeg, ffprobe, *libraries.values(), *list((package / "lib").glob("*.so*"))]
                packages = set()
                queries = sorted({str(path if str(path).startswith("/usr/") else Path("/usr/lib/x86_64-linux-gnu") / path.name) for path in files})
                for offset in range(0, len(queries), 100):
                    found = subprocess.run(["dpkg-query", "-S", *queries[offset:offset+100]], text=True, capture_output=True)
                    for line in found.stdout.splitlines():
                        if ": /" in line:
                            packages.add(line.split(": /", 1)[0].split(":", 1)[0])
                for name in packages:
                    copyright_file = Path("/usr/share/doc") / name / "copyright"
                    if copyright_file.is_file():
                        shutil.copy2(copyright_file, notices / f"{name}.copyright")
        else:
            # Shared FFmpeg distributions carry sibling DLLs; static distributions have none.
            for dll in ffmpeg.parent.glob("*.dll"):
                shutil.copy2(dll, package / "tools" / dll.name)
        if args.ffmpeg_notices:
            if args.ffmpeg_notices.is_dir():
                shutil.copytree(args.ffmpeg_notices, notices / "ffmpeg", dirs_exist_ok=True)
            else:
                shutil.copy2(args.ffmpeg_notices, notices / args.ffmpeg_notices.name)
        versions = {}
        for tool in [ffmpeg, ffprobe]:
            versions[tool.name] = subprocess.check_output([str(tool), "-version"], text=True, errors="replace")
        (notices / "tool-builds.json").write_text(json.dumps(versions, indent=2), encoding="utf-8")
        print(f"Runnable folder: {package}")
    print(f"Build output: {output}")


if __name__ == "__main__":
    main()
