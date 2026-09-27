# Third-party components

The converter's source is covered by the repository's MIT license. This does not change the licenses of bundled dependencies.

- **Qt 6** (Core, Gui, Qml, Quick, Quick Controls, Concurrent): dynamically linked. Use the applicable Qt commercial or open-source terms for your Qt build. The selected open-source modules are available under LGPLv3/GPL terms. Preserve the ability to replace the dynamic Qt libraries, include the matching license notices, and supply the corresponding source as required. See https://www.qt.io/licensing/ and https://doc.qt.io/qt-6/licensing.html.
- **FFmpeg and ffprobe**: separate executables launched with explicit argument arrays. Their license and redistribution requirements depend on configuration; for example an `--enable-gpl` build includes GPL components. A subprocess boundary does not remove obligations for the copies you distribute. Choose a known build, include its notices and corresponding source/build instructions, and do not redistribute a build marked `--enable-nonfree`. See https://ffmpeg.org/legal.html.
- **zlib**: PNG compression through Qt; zlib license, https://zlib.net/zlib_license.html. Qt's `qCompress` emits the zlib stream used for PNG data.

`build.py --package` records the exact FFmpeg version/configuration output in `licenses/tool-builds.json`, copies local Debian copyright notices when available, and accepts additional upstream notices through `--ffmpeg-notices`. This is a local packaging helper; it does not publish a release or fetch corresponding source archives. Before distributing binaries, include the full licenses and matching source materials required by the exact Qt, FFmpeg, codec and other shared-library builds you chose. A Windows package requires an explicit FFmpeg notices path.

The normal developer build does not download or install any tools. End-user packages contain Qt and the FFmpeg tool pair so users do not need to install them separately. Linux packages still rely on the target system's glibc, graphics drivers and ordinary desktop services.
