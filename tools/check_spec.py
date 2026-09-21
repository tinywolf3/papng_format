#!/usr/bin/env python3
"""Check both Markdown editions and their examples; not a PAPNG player."""
from __future__ import annotations

from fractions import Fraction
from pathlib import Path
import json
import re
import struct
import subprocess
from urllib.parse import unquote, urlsplit
import zlib

ROOT = Path(__file__).resolve().parents[1]
SOURCES = (ROOT / "spec/PAPNG-1.0.ko.md", ROOT / "spec/PAPNG-1.0.en.md")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def vector(text: str, name: str) -> bytes:
    pattern = r"<!-- vector: " + re.escape(name) + r" -->\s*\x60{3}hex\s*([\s\S]*?)\x60{3}"
    matches = re.findall(pattern, text)
    require(len(matches) == 1, "Missing or duplicate vector: " + name)
    return bytes.fromhex(matches[0])


def signed24(data: bytes) -> int:
    require(len(data) == 3, "int24 must contain three bytes")
    raw = int.from_bytes(data, "big")
    return raw - (1 << 24) if raw >= (1 << 23) else raw


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def header_fields(text: str) -> list[tuple[str, str, str]]:
    block = re.search(r"^### 4\.2 [^\n]+\n([\s\S]*?)(?=^### 4\.3 )", text, re.M)
    require(block is not None, "Missing header section")
    table = next((part for part in block[1].split("\n\n") if part.startswith("|")), "")
    return re.findall(r"^\| (\d+) \| \x60([^\x60]+)\x60 \| \x60([^\x60]+)\x60 \|", table, re.M)


def check_layout(text: str) -> None:
    sizes = {"byte[8]": 8, "uint8": 1, "uint16": 2, "uint24": 3, "uint32": 4, "int24": 3, "int32": 4}
    fields = header_fields(text)
    require(len(fields) == 14, "Header field count changed")
    position = 0
    for offset, name, typ in fields:
        require(int(offset) == position, "Bad offset for " + name)
        position += sizes[typ]
    require(position == 56, "Header must total 56 bytes")
    require(56 + 2 + 1 + 4 == 63, "Minimal extension size")

    cases = {
        -8388608: "800000", -1: "ffffff", 0: "000000",
        1: "000001", 8388607: "7fffff",
    }
    for expected, encoded in cases.items():
        raw = bytes.fromhex(encoded)
        require(signed24(raw) == expected, "int24 decode boundary")
        require((expected & 0xFFFFFF).to_bytes(3, "big") == raw, "int24 encode boundary")
    maximum = ((1 << 24) - 1 - 4) // 4
    require(maximum == 4194302, "Weighted item limit")
    require(4 + 4 * maximum == 16777212, "Largest weighted parameter block")
    require(4 + 4 * (maximum + 1) > 0xFFFFFF, "Overflowing weighted parameter block")
    print("PASS: 56-byte header offsets, int24 boundaries, weighted-array limits.")


def check_examples(text: str) -> None:
    weighted = vector(text, "weighted-values")
    require(weighted[0] == 4 and len(weighted) == 16, "Weighted header/size")
    param_size = int.from_bytes(weighted[1:4], "big")
    count = int.from_bytes(weighted[4:8], "big")
    require(param_size == len(weighted) - 4 == 4 + 4 * count == 12, "Weighted parameter accounting")
    items = [(signed24(weighted[i:i+3]), weighted[i+3]) for i in range(8, len(weighted), 4)]
    require(items == [(-3, 1), (5, 3)], "Weighted values")
    total = sum(w for _, w in items)
    require([Fraction(w, total) for _, w in items] == [Fraction(1,4), Fraction(3,4)], "Weighted probabilities")

    control = vector(text, "random-delay")
    frame, kind, size = struct.unpack(">III", control[:12])
    lower, upper, denominator, index = struct.unpack(">HHHB", control[12:])
    require((frame, kind, size) == (2, 1, 7), "Control header")
    require(len(control) == 12 + size == 19, "Control size")
    require((lower, upper, denominator, index) == (100,250,1000,0), "Control payload")

    extension = vector(text, "minimal-extension")
    require(len(extension) == 63, "Minimal vector length")
    require(extension[:8] == bytes.fromhex("5041504e47000000"), "Identifier")
    require(struct.unpack(">HHI", extension[8:16]) == (1,0,56), "Version/header size")
    require(extension[16:] == bytes(47), "Minimal hint/count values")

    masks = vector(text, "shared-mask-data")
    data_count, width, height, compressed_size = struct.unpack(">IIII", masks[:16])
    require((data_count, width, height) == (1,2,1), "Shared mask descriptor")
    raw = zlib.decompress(masks[16:16+compressed_size])
    require(raw == bytes.fromhex("80000000") and len(raw) == 2*width*height, "16-bit row-major words")
    require(struct.unpack(">IIIII", masks[16+compressed_size:]) == (2,0,0,1,0), "Shared frame bindings")
    require((0x8000 & 0x7FFF) == 0 and (0xFFFF & 0x7FFF) == 32767, "Mask index bounds")
    require(struct.pack(">H",32768) == bytes.fromhex("8000"), "Maximum mask count")

    # Form a complete APNG around the published data, then verify chunk
    # framing, CRCs, sequence metadata, and the decompressed scanline.
    rgba_scanline = bytes([0, 255, 0, 0, 255])
    parts = [
        (b"IHDR", struct.pack(">IIBBBBB", 1,1,8,6,0,0,0)),
        (b"acTL", struct.pack(">II", 1,1)),
        (b"paEX", extension),
        (b"fcTL", struct.pack(">IIIIIHHBB", 0,1,1,0,0,1,100,0,0)),
        (b"IDAT", zlib.compress(rgba_scanline)),
        (b"IEND", b""),
    ]
    container = bytes.fromhex("89504e470d0a1a0a") + b"".join(chunk(t,d) for t,d in parts)
    offset = 8
    parsed = []
    while offset < len(container):
        size = int.from_bytes(container[offset:offset+4], "big")
        kind = container[offset+4:offset+8]
        data = container[offset+8:offset+8+size]
        crc = int.from_bytes(container[offset+8+size:offset+12+size], "big")
        require(len(data) == size and zlib.crc32(kind + data) == crc, "PNG chunk CRC/framing")
        parsed.append((kind,data))
        offset += size + 12
    require(offset == len(container) and parsed == parts, "PNG complete parse")
    require(zlib.decompress(dict(parsed)[b"IDAT"]) == rgba_scanline, "PNG scanline")
    print(f"PASS: 4 published byte vectors; {len(container)}-byte APNG assembly and CRCs.")


def check_semantics(text: str) -> None:
    # Normative discrete weights for five candidates, plus the even center case.
    n = 5
    weights = [
        [1 for i in range(n)], [min(i+1,n-i) for i in range(n)],
        [n-i for i in range(n)], [i+1 for i in range(n)],
    ]
    require(weights == [[1,1,1,1,1],[1,2,3,2,1],[5,4,3,2,1],[1,2,3,4,5]], "Distribution weights")
    require([min(i+1,4-i) for i in range(4)] == [1,2,2,1], "Even triangular weights")
    def normalize(num, den):
        return (1,100) if num == 0 else (num,100 if den == 0 else den)
    require(normalize(0,1000) == (1,100), "Zero import")
    require(normalize(7,0) == (7,100), "Zero denominator import")
    require(normalize(0,0) == (1,100), "Both zero import")
    require(normalize(1,65535) == (1,65535), "Positive sub-millisecond delay")
    require(Fraction(1,65535) > 0, "Small positive time is not hidden")
    # Runtime hue offsets do not quantize H/S/V or change the alpha byte.
    for offset, expected in [(0, (255,0,0)), (180, (0,255,255)), (-120, (0,0,255))]:
        q = (Fraction(offset,60) % 6)
        x = 1 - abs(q % 2 - 1)
        triples = [(1,x,0),(x,1,0),(0,1,x),(0,x,1),(x,0,1),(1,0,x)]
        actual = tuple(int(Fraction(c) * 255 + Fraction(1,2)) for c in triples[int(q)])
        require(actual == expected, "Hue offset example")
    require("uint16 mask_count" in text and "uint32 mask_data_count" in text, "Mask layout")
    require("h_out = (h + hue_offset_degrees / 360) mod 1" in text, "Hue offset rule")
    require("**Document revision:** 1" in text or "**문서 개정:** 1" in text, "Document revision must remain 1")
    json_blocks = re.findall(r"\x60{3}json5\s*([\s\S]*?)\x60{3}", text)
    require(len(json_blocks) == 1, "One JSON5 metadata example expected")
    # Use the same bounded, duplicate-aware parser as the TypeScript reader.
    parsed = subprocess.run([
        "node", "--import", "tsx", "--input-type=module", "--eval",
        "import { readFileSync } from 'node:fs'; "
        "import { uniqueJson5 } from './packages/papng/src/json5.ts'; "
        "process.stdout.write(JSON.stringify(uniqueJson5(readFileSync(0, 'utf8'))));",
    ], input=json_blocks[0], text=True, capture_output=True, cwd=ROOT, check=True)
    metadata = json.loads(parsed.stdout)
    require(metadata["schema_version"] == 1, "Metadata schema")
    require(metadata["clips"][0]["start_frame"] == 0 and metadata["clips"][0]["end_frame"] == 7, "Clip example")
    require(metadata["mask_groups"][0]["palette_indices"] == [0,1,2], "Group example")
    sockets = metadata["sockets"]
    require([d["name"] for d in sockets["definitions"]] == ["right_hand", "head"], "Socket definitions")
    require([f["frame_index"] for f in sockets["frames"]] == [0, 3, 6], "Sparse socket records")
    require(sockets["frames"][1]["positions"] == [[13,14,30],[8,2]], "Socket rotation example")
    require(sockets["frames"][2]["positions"][0] == [12,15], "Default rotation resets")
    require("uint32 control_type" in text, "Control type field")
    require("uint24 parameter_size" in text, "Distribution parameter size")
    print("PASS: discrete weights, timing/import cases, mask examples, metadata, terminology.")


def check_editions(korean: str, english: str) -> None:
    # Compare machine-readable declarations and examples, not translated prose.
    blocks = r"^\x60{3}(\w+)\n([\s\S]*?)^\x60{3}$"
    ko_blocks = re.findall(blocks, korean, re.M)
    en_blocks = re.findall(blocks, english, re.M)
    require(ko_blocks == en_blocks, "Code blocks differ between editions")
    require(header_fields(korean) == header_fields(english), "Header layouts differ between editions")
    controls = r"^\| (\d+) \| \x60([A-Z_]+)\x60 \| (\d+) \|$"
    require(re.findall(controls, korean, re.M) == re.findall(controls, english, re.M),
            "Control names or payload sizes differ between editions")
    sections = r"^(#{2,3}) (?:Appendix |부록 )?([0-9A-C]+(?:\.\d+)*)(?:\.|:| )"
    require(re.findall(sections, korean, re.M) == re.findall(sections, english, re.M),
            "Numbered section structure differs between editions")
    require(re.search(r"[\uac00-\ud7a3]", korean) is not None, "Missing Korean translation")
    require(re.search(r"[\uac00-\ud7a3]", english) is None, "English edition contains Korean text")
    print(f"PASS: bilingual section structure, header/control layouts, {len(ko_blocks)} matching code blocks.")


def prose(text: str) -> str:
    """Exclude fenced code from heading and inline-link checks."""
    return re.sub(r"^\x60{3}[^\n]*\n[\s\S]*?^\x60{3}\s*$", "", text, flags=re.M)


def anchors(text: str) -> set[str]:
    """GitHub-style anchors for the plain ATX headings used in this repo."""
    used: set[str] = set()
    for title in re.findall(r"^#{1,6} (.+)$", prose(text), re.M):
        title = title.rstrip("#").strip().replace("`", "").replace("*", "")
        slug = re.sub(r"[^\w\- ]", "", title.lower()).replace(" ", "-")
        candidate = slug
        suffix = 0
        while candidate in used:
            suffix += 1
            candidate = f"{slug}-{suffix}"
        used.add(candidate)
    return used


def check_links(documents: dict[Path, str]) -> None:
    count = 0
    for source, text in documents.items():
        for href in re.findall(r"\[[^\]\n]+\]\(([^\s)]+)\)", prose(text)):
            target = urlsplit(href)
            if target.scheme or target.netloc:
                continue
            path = (source.parent / unquote(target.path)).resolve() if target.path else source
            require(path.is_relative_to(ROOT), f"Link outside repository: {source.name}: {href}")
            require(path.is_file(), f"Missing link target: {source.name}: {href}")
            if target.fragment:
                body = documents.get(path)
                if body is None:
                    body = path.read_text(encoding="utf-8")
                require(unquote(target.fragment) in anchors(body), f"Missing anchor: {source.name}: {href}")
            count += 1
    print(f"PASS: {count} local Markdown links and anchors.")


if __name__ == "__main__":
    documents = {source: source.read_text(encoding="utf-8") for source in SOURCES}
    for source, text in documents.items():
        print(f"Checking {source.relative_to(ROOT)}")
        check_layout(text)
        check_examples(text)
        check_semantics(text)
    check_editions(*(documents[source] for source in SOURCES))
    documents[ROOT / "README.md"] = (ROOT / "README.md").read_text(encoding="utf-8")
    for path in (ROOT / "samples/README.md", ROOT / "demos/web/viewer/README.md"):
        documents[path] = path.read_text(encoding="utf-8")
    check_links(documents)
