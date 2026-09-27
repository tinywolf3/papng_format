# Embedded image processing

`gif_decoder.cpp` exposes `PapngGifDecoder.decode(bytes, first_only, cancel)` to
GDScript. giflib handles GIF/LZW parsing; the wrapper composites local/global
palettes, interlaced scanlines, transparency and disposal into full RGBA8 frames.
Frame delays use centiseconds; zero becomes 1 (10 ms). No loop extension means
one play; a NETSCAPE/ANIMEXTS repeat count of zero means infinite playback.

The decoder streams rows instead of using `DGifSlurp`, so dimensions, output
memory and cancellation can be checked before decoding the next frame. It accepts
at most 128 MiB input, 32 megapixels per canvas and 256 MiB of output plus frame
bookkeeping. It checks cancellation and a 60-second deadline during decoding.
Plain-text graphics extensions are rejected because the editor imports raster
frames. Invalid input returns an error without replacing the current document.

## Sources and licenses

- `giflib/`: decoder subset of **giflib 6.1.3**, MIT. Source is unchanged except
  for removing trailing whitespace from one blank line in `gifalloc.c`.
  Source: https://sourceforge.net/projects/giflib/files/giflib-6.x/giflib-6.1.3.tar.gz
  Archive SHA-256: `b65b66b99f0424b93525f987386f22fc5efb9da2bfc92ad4a532249aaffbab0e`.
- **godot-cpp godot-4.4-stable**, MIT: downloaded at build time with its archive
  SHA-256 pinned in `CMakeLists.txt`. Only RefCounted, OS and their required bindings
  are built. The 4.4 extension API is used on the editor's Godot 4.7.2 runtime.
- Both are linked into `papng_gif.so` / `papng_gif.dll`. End users do not install
  giflib, godot-cpp or a compiler to open GIF files.

Build from the repository root with `python3 tools/editor/native.py linux`.
The native build requires CMake 3.22+, Python and a C/C++ compiler. Windows uses
MSVC on Windows or MinGW-w64 when cross-compiling from Linux. Android uses NDK
28.2.13676358 (or `ANDROID_NDK_HOME`) for arm64-v8a and x86_64 with `c++_static`.
All downloads, object files and libraries go to `builds/`. The `.gdextension`
references those outputs for source runs; Godot's exporter bundles the library
beside the desktop executable or inside the APK. Keep the desktop library with
its executable when distributing it.

## Lossless PNG encoding

`png_encoder.cpp` exposes `PapngPngEncoder.encode(rgba, width, height)`. It tests
all five fixed PNG filters and an adaptive per-row signed-residual filter, then
returns the smallest zlib stream. Compression uses Godot's bundled zlib with the
project setting `compression/formats/zlib/compression_level=9`. No additional
library is downloaded or installed. Every RGBA8 byte is preserved, including RGB
under zero alpha. Dimensions and array length are checked before allocation.

The writer reuses identical frame streams in a bounded 16 MiB cache, shares mask
maps and compresses JSON5 iTXt text when smaller. These optimizations preserve
frame identity, timing, rectangle, blend/disposal, masks and metadata source text.
