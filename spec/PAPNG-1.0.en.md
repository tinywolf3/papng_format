# PAPNG 1.0 File Format Specification

- **Format version:** 1.0
- **Document revision:** 1
- **Language:** English — translation
- **Date:** 2026-09-21
- **File extension:** `.papng`

Copyright (c) 2026 TinyWolf. This document is distributed under the repository's [MIT License](../LICENSE).

## Status

This document defines version 1.0 of PAPNG, an APNG-based format for editable pixel-art resources and controlled animation playback. This is the English translation of the [Korean normative specification](PAPNG-1.0.ko.md). If the editions differ in interpretation, the Korean edition takes precedence. Examples and sections explicitly marked *informative* explain the format without adding requirements.

PAPNG is an independent format specification. This document does not claim endorsement by W3C, IETF, or a registration authority. It defines no new Internet media type.

This initial 1.0 definition replaces the repository's earlier unpublished alpha-marker draft; that draft is not an alternative encoding of this specification. The format version remains 1.0 and document revision remains 1.

## Contents

- [1. Scope](#1-scope)
- [2. Conventions](#2-conventions)
- [3. Container and identification](#3-container-and-identification)
- [4. Binary extension layout](#4-binary-extension-layout)
- [5. Display hints](#5-display-hints)
- [6. Original pixels and mask planes](#6-original-pixels-and-mask-planes)
- [7. Distribution palette](#7-distribution-palette)
- [8. Frame controls](#8-frame-controls)
- [9. Playback and reconstruction](#9-playback-and-reconstruction)
- [10. Text metadata](#10-text-metadata)
- [11. Importing ordinary images](#11-importing-ordinary-images)
- [12. Error handling](#12-error-handling)
- [13. Versioning and editing](#13-versioning-and-editing)
- [14. Implementation considerations](#14-implementation-considerations)
- [15. Conformance](#15-conformance)
- [Appendix A. Binary examples](#appendix-a-binary-examples)
- [Appendix B. Behavioral examples](#appendix-b-behavioral-examples)
- [Appendix C. Precision and storage](#appendix-c-precision-and-storage)
- [References](#references)

## 1. Scope

PAPNG preserves original RGBA in APNG and adds shared 16-bit mask planes, reusable random distributions, frame playback controls, and optional presentation metadata.

A conforming PAPNG file MUST satisfy the PNG/APNG container requirements in [PNG3](#references), together with this specification. Standard image compression, filtering, interlacing, chunk integrity, and APNG frame data remain governed by PNG3.

A PAPNG writer MUST use 8-bit samples and PNG color type 6: four bytes per stored pixel, in RGBA order. Every canvas dimension MUST be positive. PAPNG imposes no additional canvas-size or animation-frame-count ceiling beyond the underlying container and the representable fields.

PAPNG MUST NOT store extension data in a synthetic animation frame. All animation frames are content frames, including frames that are composited without being presented.

Ordinary APNG viewers decode the original colors and per-pixel alpha. They need not apply runtime hue offsets or PAPNG timing and controls, so edited appearance and playback can differ. Recognition of the `.papng` filename extension is application-dependent.

## 2. Conventions

Capitalized requirement keywords have the meanings specified by BCP 14, [RFC2119](#references) and [RFC8174](#references). Lowercase uses have their ordinary English meanings.

A **writer** produces PAPNG files. A **reader** parses and reconstructs their image content. A **player** additionally executes the playback model. An **importer** converts ordinary images into PAPNG.

All multibyte integers in `paEX` and `paMD` MUST be stored most significant byte first (big-endian). Fields MUST be serialized consecutively, without alignment padding. Lengths count bytes unless stated otherwise.

| Type | Bytes | Range |
| --- | ---: | --- |
| `uint8` | 1 | 0 to 255 |
| `uint16` | 2 | 0 to 65,535 |
| `uint24` | 3 | 0 to 16,777,215 |
| `uint32` | 4 | 0 to 4,294,967,295 |
| `int24` | 3 | -8,388,608 to 8,388,607 |
| `int32` | 4 | -2,147,483,648 to 2,147,483,647 |

Signed values use two's complement. To decode `int24`, read an unsigned value `u`; the signed result is `u - 0x1000000` when `u >= 0x800000`, and `u` otherwise. Implementations MUST NOT depend on native structure packing or on a native 24-bit integer type.

These extension types do not enlarge the permitted ranges of PNG/APNG's own fields.

All indices are zero-based. Every numerical interval written as `[a, b]` includes both endpoints. Arithmetic used to validate lengths, ranges, weights, and target frames MUST NOT overflow or wrap.

## 3. Container and identification

### 3.1 Required extension chunk

A PAPNG 1.0 file MUST contain exactly one `paEX` chunk. Its type bytes are:

```text
70 61 45 58
 p  a  E  X
```

The name identifies an ancillary, private, reserved-bit-conforming, unsafe-to-copy chunk under PNG's naming conventions. The PNG chunk length and CRC apply normally. The chunk data is not independently compressed.

The chunk MUST follow `IHDR` and precede the first `IDAT`. It need not have a particular order relative to other ancillary chunks, except where PNG3 requires one.

A file MUST contain an APNG animation, including for a single-frame resource. The animation frame count is the APNG content-frame count; no metadata frame is included.

A reader MUST inspect the `paEX` identifier and version rather than infer PAPNG semantics solely from a filename. The identifier is the following eight bytes:

```text
50 41 50 4E 47 00 00 00
 P  A  P  N  G
```

### 3.2 Frame numbering

`frame_index` is the ordinal position of a frame in the APNG animation, beginning at 0. It is not an APNG chunk sequence number. A separate default image that is not part of the animation has no `frame_index`.

Mask bindings apply only to animation frames. A default image outside the animation retains original RGBA and MUST NOT be used as the animation's initial compositing state.

### 3.3 Optional text

At most one `iTXt` chunk with the keyword `PAPNG.Metadata` MAY be included. Its payload is described in Section 10. Other conforming PNG chunks MAY be present.

## 4. Binary extension layout

### 4.1 Top-level order

The `paEX` chunk data MUST have the following order:

```text
Header
uint16 mask_count
uint8 distribution_count
Distribution distributions[distribution_count]
uint32 frame_control_count
FrameControl frame_controls[frame_control_count]
```

`mask_count` declares logical slots without serialized entries. Other counts describe serialized entries; the distribution count excludes built-in distribution index 0.

For version 1.0, all bytes after the header MUST be accounted for by these fields and their declared payloads. Writers MUST NOT append unstructured trailing data.

### 4.2 Header

Offsets are relative to the first byte of the `paEX` chunk data.

| Offset | Field | Type | Version 1.0 meaning |
| ---: | --- | --- | --- |
| 0 | `magic` | `byte[8]` | `50 41 50 4E 47 00 00 00` |
| 8 | `version_major` | `uint16` | 1 |
| 10 | `version_minor` | `uint16` | 0 |
| 12 | `header_size` | `uint32` | 56 |
| 16 | `hint_flags` | `uint32` | Presence flags below |
| 20 | `display_width` | `uint32` | Requested display width |
| 24 | `display_height` | `uint32` | Requested display height |
| 28 | `bbox_x` | `int32` | Bounding-box left coordinate |
| 32 | `bbox_y` | `int32` | Bounding-box top coordinate |
| 36 | `bbox_width` | `uint32` | Bounding-box width |
| 40 | `bbox_height` | `uint32` | Bounding-box height |
| 44 | `pixel_scale` | `uint32` | Suggested integer scale |
| 48 | `pivot_x` | `int32` | Horizontal pivot coordinate |
| 52 | `pivot_y` | `int32` | Vertical pivot coordinate |

`header_size` includes the identifier and every header field. In version 1.0 it MUST equal 56; the first body field begins at that offset.

`hint_flags` assigns the following bits:

| Bit | Mask | Fields present |
| ---: | --- | --- |
| 0 | `0x00000001` | `display_width`, `display_height` |
| 1 | `0x00000002` | All four `bbox_*` fields |
| 2 | `0x00000004` | `pixel_scale` |
| 3 | `0x00000008` | `pivot_x`, `pivot_y` |
| 4–31 | — | Reserved |

Writers MUST clear reserved bits and write zero to fields whose presence flag is clear. Readers MUST use the flags to determine presence; an absent value is not an instruction to use a numerical zero.

### 4.3 Body counts

`mask_count` MUST be in `[0, 32768]`. Zero means no mask slots. The value 32768 is stored literally as `0x8000` and permits indices 0 through 32767. Unused slots are permitted; this count bounds indices across the entire animation.

`distribution_count` MUST be in `[0, 255]`. Its interpretation is defined in Section 7.

`frame_control_count` is the number of serialized frame-control records. A conforming writer MUST associate no more than one record with any one animation frame. Records MAY appear in any order; increasing `frame_index` order is RECOMMENDED.

With no hints, masks, additional distributions, or controls, the `paEX` data is 63 bytes: a 56-byte header and counts of 2, 1, and 4 bytes.

## 5. Display hints

Display hints do not change the encoded canvas or frame coordinates. A reader MAY ignore any or all hints without affecting core PAPNG conformance.

All geometric coordinates refer to the original canvas, whose origin is at the top left; x increases rightward and y increases downward. Scaling MUST NOT be applied to these values before interpreting them.

When present:

- Display width and height MUST both be positive. They describe a suggested size in output pixels.
- The bounding box MUST have positive width and height and lie within the canvas. It denotes the half-open rectangle `[x, x + width) × [y, y + height)`.
- Pixel scale MUST be at least 1.
- The pivot is an integer position in canvas coordinates and MAY lie outside the canvas.

The bounding box is a resource-wide application hint, not a command to crop image data or alter compositing. Applications determine its use; it is not required to equal a computed alpha bound.

An application that applies the hints SHOULD prefer an explicit display size. If that hint is absent, it SHOULD use canvas dimensions multiplied by the pixel scale, or scale 1 when absent. Nearest-neighbor scaling is RECOMMENDED. Applications MAY select a different presentation policy.

An invalid hint MUST be ignored independently of valid hints.

## 6. Original pixels and mask planes

### 6.1 Original RGBA and mask indices

Every stored image sample MUST remain original, unassociated RGBA8. No alpha value is reserved: alpha 1 is an ordinary alpha value. Mask membership MUST NOT be encoded into RGB or alpha channels. Different pixels in one mask MAY have different RGB and alpha values.

`mask_count` declares resource-wide logical mask slots, not serialized palette entries and not the maximum number of distinct masks in a single frame. A valid index satisfies `0 <= mask_index < mask_count`. The same index refers to the same logical mask across frames. No hue, alpha, saturation, value, or hue offset is stored for a slot. An application supplies a finite hue offset in degrees per index; the default for every index is zero.

A mask plane contains one big-endian `uint16` per source-frame pixel, in row-major order from the top left. The highest bit is the membership flag and the lower 15 bits are the index:

```text
active     = (word & 0x8000) != 0
mask_index = word & 0x7FFF

0x0000 = unassigned
0x8000 = assigned to mask 0
0xFFFF = assigned to mask 32767
```

Writers MUST encode every unassigned pixel as `0x0000`. An inactive word with nonzero low bits MUST be treated as unassigned with a warning. An active out-of-range index MUST leave that source pixel's original RGBA unchanged and produce a warning.

### 6.2 Compressed mask pool and frame bindings

At most one `paMD` chunk MAY occur, after `paEX` and before the first `IDAT`. Like `paEX`, its name is ancillary, private, reserved-bit-conforming, and unsafe to copy after image edits. Its PNG CRC covers the chunk type and the full chunk data. Its version is the version of `paEX`; it has no additional header or version fields. All integers are big-endian.

```text
uint32 mask_data_count
MaskData mask_data[mask_data_count]
uint32 frame_mask_count
FrameMask frame_masks[frame_mask_count]

MaskData:
  uint32 width
  uint32 height
  uint32 compressed_size
  byte compressed_data[compressed_size]

FrameMask:
  uint32 frame_index
  uint32 mask_data_index
```

`mask_data_index` is the zero-based position in `mask_data`. Invalid entries retain their positions. Each `MaskData` MUST contain exactly one independently decodable zlib stream as defined by RFC 1950, using DEFLATE and no preset dictionary. Its decompressed size MUST be exactly `2 * width * height` bytes. Width and height MUST be positive and no larger than the APNG canvas dimensions; `compressed_size` MUST be positive. The stream MUST have no trailing data. All chunk bytes MUST be accounted for. There are no PNG scanline filter bytes or Adam7 passes in a mask array, regardless of image interlacing.

Every binding MUST reference an existing animation frame and mask-data entry. Map dimensions MUST equal that frame's `fcTL` width and height. The array uses local coordinates of the source rectangle; its canvas position comes from `fcTL`. The default image outside the animation cannot have a binding and remains original RGBA. An animation frame without a binding is entirely unassigned, even if a preceding frame used a mask. Bindings MUST NOT be inherited across frames.

A writer MUST emit at most one binding per frame. A reader encountering duplicates MUST warn and retain the first binding whose frame, map descriptor, and dimensions are valid; invalid preceding bindings do not block a later valid one. A later decompression failure uses original RGBA and does not select a different duplicate binding.

Multiple frames MAY share one map, including frames at different canvas offsets when their local dimensions match. Writers SHOULD store identical dimensions and uncompressed arrays only once, omit entirely unassigned maps and their bindings, and omit `paMD` when there are no bindings. Readers MUST also accept redundant equal maps and all-zero maps. Map and binding counts are limited only by their field widths and the enclosing PNG chunk size. A `paMD` chunk MAY be absent even when `mask_count` is nonzero.

A bad `paMD` CRC, duplicate chunk, or invalid chunk position MUST disable all mask bindings, preserving original RGBA. An invalid map descriptor, compressed stream, decompressed length, or frame reference MUST disable only affected bindings where safely identifiable. Readers MAY retain fully validated bindings before structural truncation and MUST stop at the first unbounded field. No failure in `paMD` changes frame timing or disables otherwise valid controls.

### 6.3 Hue offsets and color conversion

Hue offsets are runtime rendering parameters, not file fields. Missing offsets default to zero. A non-finite offset MUST produce a warning and be treated as zero. Offsets MUST be normalized modulo 360 degrees. An unassigned pixel or a zero normalized offset MUST preserve its four original bytes exactly, without an HSV round trip. The source alpha byte MUST remain unchanged for every offset, including alpha 0 and 1.

For an assigned pixel with a nonzero offset, use the original encoded RGB samples before color management, alpha premultiplication, resampling, and APNG compositing. RGB is not linearized. Let `r`, `g`, and `b` be the source bytes divided by 255, `m = min(r,g,b)`, `v = max(r,g,b)`, and `d = v-m`.

- If `d = 0`, retain the original RGB; a hue shift cannot color a gray pixel.
- Otherwise set `s = d/v`.
- When `v = r`, set `h = (((g-b)/d) mod 6)/6`.
- Otherwise, when `v = g`, set `h = ((b-r)/d+2)/6`.
- Otherwise set `h = ((r-g)/d+4)/6`.

```text
h_out = (h + hue_offset_degrees / 360) mod 1
s_out = s
v_out = v
alpha_out = original_alpha
```

H, S, and V MUST NOT be quantized into integer storage fields. For HSV-to-RGB conversion, calculate `c = v*s`, `q = 6*h_out`, `x = c*(1-abs((q mod 2)-1))`, and `m = v-c`. Select a triple by `floor(q)`:

```text
0: (c, x, 0)    1: (x, c, 0)    2: (0, c, x)
3: (0, x, c)    4: (x, 0, c)    5: (c, 0, x)
```

Add `m` to each component, multiply by 255, round as `floor(value+0.5)`, and clamp to `[0,255]`. Modulo results MUST be nonnegative. These formulas define the mathematical result; implementations SHOULD use sufficient precision near rounding boundaries. Every change is evaluated from the original source samples, never from a previously recolored image.

### 6.4 Compositing, edits, and caches

Apply each source frame's mask and hue offsets before that frame's normal APNG blend operation, including during reconstruction and hidden visits. Do not blend, interpolate, or apply APNG disposal to mask indices themselves. Ordinary APNG disposal still applies to the resulting image state.

Offsets MUST remain unchanged during playback. Before changing them, an application MUST suspend playback, discard composition state and color-dependent caches, and restart reconstruction from frame 0. A selected clip uses normal prefix reconstruction to its start. Decoded membership maps MAY remain cached because they do not depend on hue offsets.

## 7. Distribution palette

### 7.1 Indices and definition header

Distribution index 0 is always a built-in uniform distribution with no parameters. It MUST NOT be serialized or overridden.

`distribution_count` counts additional definitions. Serialized definition number 0 has distribution index 1; definition number `k` has index `k+1`.

Consequently, count 0 provides one effective distribution, and count 255 provides 256 effective distributions. A valid reference satisfies `distribution_index <= distribution_count`.

Every additional definition has this four-byte header:

```text
uint8  distribution_kind
uint24 parameter_size
byte   parameters[parameter_size]
```

`parameter_size` excludes the header. A parameterless definition occupies exactly four bytes. The index selects a definition; `distribution_kind` selects the algorithm used by that definition.

Unknown or malformed definitions retain their index positions. A reader MUST NOT compact the array after ignoring one.

### 7.2 Range-based distributions

Kinds 0–3 MUST have `parameter_size = 0`. They select an integer from the inclusive range supplied by the referring control.

Let `N = maximum - minimum + 1` and `i = value - minimum`. Candidate probability is its weight divided by the sum of all candidate weights.

| Kind | Name | Candidate weight |
| ---: | --- | --- |
| 0 | `UNIFORM` | `1` |
| 1 | `TRIANGULAR` | `min(i + 1, N - i)` |
| 2 | `FAVOR_LOW` | `N - i` |
| 3 | `FAVOR_HIGH` | `i + 1` |

The built-in index 0 uses kind 0 semantics. Additional kind 0 definitions are permitted.

A reversed interval is invalid. An interval containing one value selects that value with certainty. The definition of `TRIANGULAR` is discrete and also covers even candidate counts; it is not an implementation-selected continuous distribution.

### 7.3 Weighted numeric values

Kind 4, `WEIGHTED_VALUES`, has these parameters:

```text
uint32 item_count
repeat item_count times:
    int24 value
    uint8 probability
```

Each item is four bytes. The following relationship MUST hold exactly:

```text
parameter_size = 4 + 4 * item_count
```

The count MUST be positive. The maximum representable count is 4,194,302; its parameter block is 16,777,212 bytes.

Despite its name, `probability` stores a relative integer weight:

```text
P(item j) = probability[j] / sum(probability)
```

Zero-weight entries MUST never be selected. The total weight MUST be positive. Repeated values are permitted and their probabilities add. Weights need not sum to 100 or 255. The selected result is the stored number, not the item's position.

When a control uses this kind, its `min_*` and `max_*` fields are ignored. Writers MUST write zero to those ignored fields. Its selected value becomes the delay numerator, relative frame delta, or absolute target frame, according to the referring control.

Readers MUST validate all positive-weight values in the context of each reference. A shared definition can be usable by one control but unusable by another. Zero-weight values need no control-specific range validation.

Kind values 5–255 are reserved.

### 7.4 Sampling

A player MUST implement the specified discrete probabilities without introducing systematic selection bias through integer reduction, clamping, filtering, or retrying out-of-range outcomes.

The random generator and its seed are application choices. Version 1.0 does not promise matching random sequences across implementations and does not serialize generator state. Each playback instance SHOULD have independently managed random state.

An invalid distribution reference or invalid selection domain invokes the frame-control recovery rule in Section 12; it MUST NOT silently select a different distribution.

## 8. Frame controls

### 8.1 Record layout

Each frame-control record has a 12-byte header:

```text
uint32 frame_index
uint32 control_type
uint32 payload_size
byte   payload[payload_size]
```

`payload_size` excludes the header. For a recognized version 1.0 control type, it MUST equal the exact size listed below.

| Type | Name | Payload bytes |
| ---: | --- | ---: |
| 0 | `FIXED_DELAY` | 4 |
| 1 | `RANDOM_DELAY` | 7 |
| 2 | `RELATIVE_JUMP` | 4 |
| 3 | `ABSOLUTE_MOVE` | 4 |
| 4 | `RANDOM_RELATIVE_JUMP` | 9 |
| 5 | `RANDOM_ABSOLUTE_MOVE` | 9 |

Types 6 and above are reserved. Version 1.0 permits at most one control per frame and does not combine a delay override with a movement override in one record.

A frame without a control uses its APNG delay and the sequential successor.

Control association MUST NOT repurpose APNG delay fields as indices or sentinels. Adding or changing a PAPNG control leaves the underlying APNG delay fields unchanged, unless the author separately edits that base timing or applies the import normalization in Section 11.

### 8.2 Delay arithmetic

A delay is a rational number of seconds, `numerator / effective_denominator`. A stored denominator of zero is interpreted as 100, both for APNG frame delays and extension delay fields. The source field need not be rewritten during PAPNG loading.

A positive rational duration MUST NOT become a hidden frame because it rounds to zero in an implementation's clock unit. Timing accumulation SHOULD retain fractional precision.

An effective numerator of zero invokes the hidden-frame rules in Section 9.4. It is not an error or an extension-record marker.

### 8.3 Type 0: FIXED_DELAY

```text
uint16 delay_num
uint16 delay_den
```

These values override the effective delay without modifying the underlying APNG fields. After the delay, playback follows the sequential successor.

### 8.4 Type 1: RANDOM_DELAY

```text
uint16 min_delay_num
uint16 max_delay_num
uint16 delay_den
uint8  distribution_index
```

For a range-based distribution, sample an integer numerator from the supplied inclusive interval. For `WEIGHTED_VALUES`, use the selected value directly as the numerator; it MUST be nonnegative. The 16-bit interval fields do not constrain a weighted-value numerator.

Divide the selected numerator by the effective denominator. Sample once for each actual visit to this frame, not on every render update. After the delay, playback follows the sequential successor.

### 8.5 Type 2: RELATIVE_JUMP

```text
int32 frame_delta
```

Use the current frame's underlying APNG delay. Then move to:

```text
target = current_frame + frame_delta
```

A negative delta moves toward lower frame numbers. Zero revisits the current frame.

### 8.6 Type 3: ABSOLUTE_MOVE

```text
uint32 target_frame
```

Use the current frame's underlying APNG delay, then move to the specified frame.

### 8.7 Type 4: RANDOM_RELATIVE_JUMP

```text
int32 min_frame_delta
int32 max_frame_delta
uint8 distribution_index
```

Use the underlying APNG delay. On its completion, sample a delta and add it to the current frame number. A weighted-value distribution supplies the delta directly.

### 8.8 Type 5: RANDOM_ABSOLUTE_MOVE

```text
uint32 min_target_frame
uint32 max_target_frame
uint8  distribution_index
```

Use the underlying APNG delay. On its completion, sample a target frame number. A weighted-value distribution supplies that number directly.

### 8.9 Target validity

Targets MUST lie within the animation and, during selected-clip playback, within the active clip. Frame arithmetic MUST be checked before narrowing to an unsigned index. Targets do not wrap modulo the frame count.

Every candidate in a range-based movement control, and every positive-weight candidate in a weighted movement control, MUST be a valid target in the active playback context. If not, the entire control uses the recovery rule; the player MUST NOT renormalize a subset of candidates.

Changing a file's frame order requires reevaluating absolute references and relative deltas, including those returned by distributions.

## 9. Playback and reconstruction

### 9.1 State model

A player distinguishes:

- The **composition state**, including the canvas and any saved state needed for disposal.
- The **presented image**, which is updated only when a frame with positive effective delay is presented.
- The **current frame** and active playback interval.
- Timing, repetition, and random-generator state.

At the start of a fresh playback, composition state and the presented image are transparent. A loop reset clears composition state; the previously presented image remains visible until a new visible frame replaces it.

A **visit** executes a frame's timing and control. A **reconstruction step** processes a frame solely to obtain image state.

### 9.2 Canonical frame state

The canonical state of frame `j` is the state obtained by starting with a transparent canvas and processing frames 0 through `j` in file order.

Masks are restored before each frame is composited. Between frames, APNG blending and disposal apply as defined by PNG3. At frame `j`, the state is captured after compositing and before disposal of `j`.

Reconstruction steps MUST NOT present images, wait, sample randomness, execute PAPNG frame controls, or increment playback repetition counts. This applies even if an intermediate frame has a zero delay or an unconditional jump.

Disposal is determined by the frame's stored disposal operation, not by a random timing outcome. The target's saved disposal state is part of the reconstruction result.

### 9.3 Moving to a frame

For a move from frame `i` to frame `j`:

1. If `j > i`, apply disposal of `i` once, then reconstruct frames `i+1` through `j` in order. Dispose intermediate frames before their successors.
2. If `j < i`, reset composition state and reconstruct frames 0 through `j`.
3. If `j = i`, keep the current post-composition state and its saved disposal state. Do not dispose or composite the frame again.

Then begin a new visit to `j`. A new visit reevaluates its effective delay and, when required, performs a new random draw.

An implementation MAY reconstruct a forward target from frame 0 or use a cache instead, provided the result and saved disposal state match the canonical state. Image reconstruction MUST NOT rewind or advance the playback random generator.

When starting a clip above frame 0, reconstruct the prefix from 0 without executing that prefix's timing or controls.

### 9.4 Zero-delay frames

For a visit with effective delay zero, the player MUST composite the frame but MUST NOT present it or wait. It MUST immediately execute that frame's successor-selection rule.

Zero-delay composition can prepare image content for later frames. Writers that intend the result to persist SHOULD use APNG disposal `NONE`. The reader MUST NOT replace disposal operations based on whether the sampled or fixed delay is zero.

The next frame's normal compositing may overwrite this content. No persistence beyond the normal compositing rules is implied.

A player MUST keep composition state separate from presentation sufficiently to avoid exposing reconstruction or hidden frames during asynchronous work.

### 9.5 Visible visits and transitions

For a positive effective delay, present the completed composition and retain it for that logical duration. At the end of the duration, select the successor.

Types 0 and 1 change timing only. Types 2–5 change the successor only. An invalid control uses the 10 ms sequential recovery behavior instead of either override.

Random movement is sampled once after the current delay. A hidden frame still executes its own control on an actual visit.

### 9.6 End of an interval and repetition

For full-animation playback, the active interval is all animation frames and the repetition count is APNG's `num_plays`. For selected-clip playback, the interval and count come from the clip.

A **completed play** occurs only when sequential progression passes the final frame of the active interval. An explicit jump, including a jump to the interval's first frame, does not itself complete a play. Therefore a control loop may prevent a finite repetition count from being reached.

If another play is required, clear composition state and reconstruct the interval's first frame canonically. A count of zero requests indefinite repetition. On completion of finite playback, preserve the last presented image; hidden final frames MUST NOT become visible merely because playback ends.

### 9.7 Zero-time cycles and scheduling

A zero-time control cycle is possible. Players MUST bound the work performed in any one uninterrupted scheduling slice and return control to their host when that budget is exhausted.

A player SHOULD report persistent lack of time progress and remain cancelable. Yielding MUST preserve execution state and MUST NOT inject a nonzero logical delay or present a hidden frame. The work budget is an implementation parameter, not a PAPNG frame-count limit.

## 10. Text metadata

### 10.1 Encoding

The optional `iTXt` keyword MUST be exactly `PAPNG.Metadata`. The text is a UTF-8 JSON object conforming to [RFC8259](#references), without a byte-order mark. Standard iTXt compression MAY be used. The language tag and translated keyword SHOULD be empty.

Object member names MUST be unique. Unknown members MUST be ignored by readers. Recognized members MUST have their specified types; booleans are not accepted as numeric values.

The top-level object MUST contain integer `schema_version: 1`. The optional arrays `clips` and `mask_groups` default to empty. This schema version is separate from the binary format version.

### 10.2 Animation clips

Each clip has:

| Member | Type | Meaning |
| --- | --- | --- |
| `id` | Nonempty string | Stable identifier, unique among clips |
| `name` | String, optional | Display name; defaults to `id` |
| `start_frame` | Integer | Inclusive first frame |
| `end_frame` | Integer | Inclusive last frame |
| `play_count` | Integer | Number of completed plays; 0 means indefinite |

Frame bounds MUST satisfy `0 <= start_frame <= end_frame < frame_count`. `play_count` MUST fit `uint32`. IDs are compared exactly and case-sensitively; display-name changes do not change an ID.

Clips describe selectable playback intervals. Their presence does not automatically select a clip or replace full-animation playback. Clip playback follows Section 9, including prefix reconstruction and target bounds.

### 10.3 Mask groups

Each mask group has:

| Member | Type | Meaning |
| --- | --- | --- |
| `id` | Nonempty string | Stable identifier, unique among mask groups |
| `name` | String, optional | Display name; defaults to `id` |
| `palette_indices` | Array of integers | Mask palette indices belonging to the group |

Indices MUST be less than `mask_count` and MUST be unique within one group. Different groups MAY overlap. An empty group is permitted. A group is organizational metadata and does not change pixel decoding by itself.

### 10.4 Example and recovery

The following is informative and assumes at least eight frames and three mask slots:

```json
{
  "schema_version": 1,
  "clips": [
    {
      "id": "idle",
      "name": "Idle",
      "start_frame": 0,
      "end_frame": 7,
      "play_count": 0
    }
  ],
  "mask_groups": [
    {
      "id": "hair",
      "name": "Hair",
      "palette_indices": [0, 1, 2]
    }
  ]
}
```

Malformed JSON, duplicate object members, or an unsupported schema version disables this metadata object with a warning. An invalid individual clip or group SHOULD be ignored without discarding unrelated valid entries. For repeated IDs, the first valid entry wins; later duplicates are ignored with a warning.

Missing or ignored metadata MUST NOT prevent core image decoding or full-animation playback.

## 11. Importing ordinary images

Import normalization applies to conversion from an ordinary image, not to loading an existing PAPNG resource.

An importer MUST convert source samples to unassociated RGBA8. It MUST preserve all resulting RGBA bytes, including alpha 1, when adding mask membership. No channel value is reserved for masks.

For each ordinary APNG frame:

- If `delay_num = 0`, replace both delay fields with `delay_num = 1`, `delay_den = 100`: 10 ms.
- Otherwise, if `delay_den = 0`, replace the denominator with 100 while retaining the numerator.
- Otherwise, retain the original delay fields.

An imported static image SHOULD become a one-frame APNG with one play and a 10 ms delay. No frame controls or additional distributions are required for this conversion.

A PAPNG reader MUST preserve valid zero delays and use explicit mask bindings. Renaming a PAPNG file to `.png` or `.apng` MUST NOT by itself trigger import normalization.

The importer SHOULD report timing adjustments so an editor can make them visible to the user.

## 12. Error handling

### 12.1 Recovery is distinct from validity

Recovery allows playback of otherwise usable image data. It does not make malformed data a conforming file. A diagnostic MAY be delivered through a callback, log, or UI; repeated occurrences SHOULD be coalesced.

Container errors remain subject to PNG3. Recovery is not a promise to reconstruct corrupted compressed image data.

### 12.2 Local errors

| Error | Required recovery |
| --- | --- |
| Active mask index outside `mask_count` | Warn; preserve that pixel's original RGBA |
| Invalid mask data or binding | Warn; preserve original RGBA for affected bindings, as in Section 6.2 |
| Invalid hint | Warn; ignore that hint |
| Unusable distribution referenced by a control | Warn; use control recovery |
| Invalid control payload, range, target, or reserved control type | Warn; use control recovery |
| Control refers to a nonexistent frame | Warn; ignore the record |
| Duplicate controls for an existing frame | Warn; first valid record wins |
| Invalid optional text metadata | Warn; ignore the affected metadata as in Section 10 |

**Control recovery** means presenting the frame for exactly 10 ms and taking its sequential successor. The underlying APNG delay and movement override are not used for that failed control.

For duplicate controls, a later valid record can replace an earlier invalid candidate until the first valid record is found. If no valid record exists for that frame but an invalid record refers to it, control recovery applies. Record validity includes checks in the active clip context.

A distribution whose parameters are invalid still occupies its declared index slot. Merely defining an unused invalid distribution does not change unrelated frames.

### 12.3 Structural errors

Readers MUST verify the chunk boundary, CRC, identifier, counts, and declared lengths before using dependent data.

For a recognizable version 1 extension with an invalid CRC, unusable header, or ambiguous duplicate `paEX` chunks, the extension MUST be disabled rather than interpreted from untrusted offsets. In PAPNG recovery mode, masks are disabled and original RGBA is preserved; absent controls use ordinary PAPNG sequential timing, including its zero-delay rule.

When a valid chunk contains a structurally truncated body, a reader MAY retain fully validated earlier sections. It MUST stop interpreting the body at the first field whose end cannot be located safely. It MUST NOT guess the location of subsequent sections. Unavailable data is handled as above.

A `mask_count` above 32768 is invalid. Readers MUST disable masks and MAY continue with distributions and controls; there are no serialized mask entries to skip.

A file with no recognizable PAPNG extension, or an unsupported major version, is not a supported PAPNG 1.0 resource. An application MAY offer ordinary PNG/APNG decoding as a separately identified fallback. Such fallback MUST NOT be reported as successful PAPNG reconstruction.

## 13. Versioning and editing

Version 1.0 writers MUST emit major 1, minor 0, the 56-byte header, the assigned control and distribution kinds, and zero reserved flags.

Future minor revisions MUST retain the meaning and encoding of existing fields and the top-level body order. Length-delimited unknown definitions can be skipped. A same-major reader MAY process a newer minor revision using known fields, skip extra header bytes using `header_size`, and warn about unsupported features. It MUST NOT interpret unknown fields by guessing. Unknown hint bits MAY be ignored.

A change that alters existing decoding or playback semantics requires a new major version. Future features that cannot be safely skipped MUST NOT rely solely on an older reader ignoring their data.

An editor that changes frame order or removes frames MUST update control keys, absolute targets, relative deltas, distribution values used as targets, clip ranges, and frame-mask bindings. If a shared distribution cannot preserve all of its references after an edit, the editor can create separate definitions within the format's count limit or report that the edit cannot be represented.

An editor that renumbers or removes logical masks MUST update mask-array indices, `mask_count`, and mask-group references. An editor that reorders or removes mask-data entries MUST update every frame binding. Changing one frame's shared map MUST NOT modify unrelated frames: create a separate map when their membership should differ.

Ordinary PNG/APNG editing tools are not required to understand these relationships. The unsafe-to-copy chunk property is not a guarantee of a valid editing round trip, particularly when animation or text metadata is changed. PAPNG-aware tools SHOULD validate all extension references before saving.

## 14. Implementation considerations

This section is informative except for its explicit safety requirements.

Readers MUST check arithmetic and byte availability before allocation, indexing, or decompression. Suggested resource thresholds should result in diagnostics; PAPNG specifies no additional canvas or frame ceiling. An implementation that cannot process a resource within its actual memory or scheduling capacity should report that limitation rather than claim the file violates an invented format limit.

Applications should bound decompressed metadata size, maintain cancellation during reconstruction, and avoid repeated identical warnings. Those are host resource policies, not serialized PAPNG values.

Image data is original RGBA and mask data is a separate integer array. A raw unassociated sample path is required to apply hue offsets before premultiplication or color conversion and to preserve low-alpha RGB values.

Caching canonical frame states can accelerate jumps. A useful cache includes saved disposal state, not only the visible canvas. Hue-offset changes invalidate such color-dependent caches, but not decoded mask arrays.

Writers should preserve original RGBA and mask membership exactly. Compress each map independently and reuse equal maps across frames. Baking recolored preview pixels into RGBA is an export operation; runtime hue offsets are not serialized in v1.

## 15. Conformance

A conforming **writer** emits the container profile, binary layout, valid references, supported values, and metadata constraints defined here.

A conforming **core reader** applies runtime hue offsets through mask bindings and restores canonical frame states and implements the specified parsing and recovery behavior. It MAY ignore display hints and text metadata.

A conforming **player** additionally implements all six control types, all five distribution kinds, rational timing, hidden-frame behavior, reconstruction-only traversal, and repetition rules. An implementation supporting only ordinary APNG playback MUST NOT claim full PAPNG playback support.

A conforming **importer** implements the ordinary-image normalization rules without applying them to existing PAPNG content.

Optional optimizations or host presentation choices MUST NOT change logical frame selection, random probabilities, mask restoration, or zero-delay visibility.

## Appendix A. Binary examples

This appendix is informative. Hexadecimal byte blocks contain only the bytes described by their captions; they do not include an outer PNG chunk unless explicitly stated.

### A.1 Signed 24-bit values

```text
-8388608 = 80 00 00
      -1 = FF FF FF
       0 = 00 00 00
       1 = 00 00 01
 8388607 = 7F FF FF
```

### A.2 A weighted-value definition

This complete distribution definition selects -3 with weight 1 or 5 with weight 3. It occupies 16 bytes, including its four-byte definition header.

<!-- vector: weighted-values -->
```hex
04 00 00 0C
00 00 00 02
FF FF FD 01
00 00 05 03
```

The kind is 4, the parameter size is 12, and the item count is 2. Probabilities are 1/4 and 3/4. If it is the first serialized definition, its distribution index is 1.

### A.3 A random-delay control

This control applies to frame 2. It chooses an integer numerator n uniformly from 100 through 250 and uses n/1000 seconds as the delay: 100 through 250 ms. Distribution index 0 is built in.

<!-- vector: random-delay -->
```hex
00 00 00 02
00 00 00 01
00 00 00 07
00 64 00 FA 03 E8 00
```

The complete record is 19 bytes: a 12-byte header and a seven-byte payload.

### A.4 Minimal extension data

This is a complete 63-byte `paEX` data field with no hints, masks, additional distributions, or controls. It still provides the built-in uniform distribution.

<!-- vector: minimal-extension -->
```hex
50 41 50 4E 47 00 00 00
00 01 00 00 00 00 00 38
00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00
00 00 00 00 00 00 00
```

To place this data in a PNG stream, write a PNG chunk length of 63, chunk type `paEX`, these 63 bytes, and the standard PNG CRC for the type and data.

### A.5 Original alpha and hue offsets

For `mask_count = 32768`, words `80 00` and `FF FF` select masks 0 and 32767 respectively. `00 00` leaves a pixel unassigned. Original pixel `FF 00 00 01` remains exactly unchanged when its offset is zero. At +180 degrees it becomes `00 FF FF 01`; alpha 1 is preserved. Other pixels with the same mask index retain their own original alpha and relative hue differences. Offset edits require the restart in Section 6.4.

### A.6 Shared mask data

The following complete `paMD` data has one 2-by-1 map and two bindings, for frames 0 and 1. Both source frames must be 2-by-1; `mask_count` must be at least 1. The decompressed words are `80 00 00 00`: the first pixel uses mask 0 and the second is unassigned.

<!-- vector: shared-mask-data -->
```hex
00 00 00 01 00 00 00 02
00 00 00 01 00 00 00 0C
78 DA 6B 60 60 60 00 00
02 04 00 81 00 00 00 02
00 00 00 00 00 00 00 00
00 00 00 01 00 00 00 00
```

## Appendix B. Behavioral examples

This appendix is informative.

### B.1 Hidden preparation frame

Use a two-pixel canvas, initially transparent:

1. Frame 0 writes opaque red at x=0, has delay zero, and disposal NONE. It is composited but not presented.
2. Frame 1 writes opaque blue at x=1 and has delay 1/10 second.

The first presented image has two adjacent pixels: [red, blue]. Frame 0 contributes to the result despite never being displayed.

### B.2 Reconstruction does not execute controls

Suppose frame 1 contains a jump to frame 0. A direct move from frame 0 to frame 3 reconstructs frames 1, 2, and 3 in order. The jump attached to frame 1 is not executed during reconstruction. The visit begins at frame 3.

A later backward move from frame 3 to frame 1 reconstructs from transparent through frames 0 and 1. Frame 1 is now actually visited, so its jump executes after its effective delay.

### B.3 Self-targeting does not accumulate opacity

A partially transparent frame with a target equal to its own index keeps its existing composition on each visit. It does not repeatedly blend its source pixels over itself. Its timing and successor selection still execute again.

### B.4 Import normalization

An ordinary APNG delay of 0/1000 imports as 1/100 second, not 1/1000 second. A delay of 7/0 imports as 7/100 second.

A PAPNG delay of 0/1000 remains zero and hides the frame's presentation while retaining its normal compositing behavior.

### B.5 Weighted contextual validation

The definition in A.2 is valid for relative jumps from frame 10 in an animation containing frames 0–20: it selects frame 7 or 15.

The same definition is invalid for a delay numerator because the positive-weight value -3 is negative. A control using it for a delay falls back to 10 ms and sequential progression; the player does not discard -3 and select 5 with certainty.

## Appendix C. Precision and storage

This appendix is informative.

Original RGBA8 is stored without HSV quantization. With zero hue offsets, the mask operation has zero source-byte error, including alpha 0 and 1. APNG compositing, display color management, and the presentation surface are separate operations; this statement does not imply every composited pixel equals an individual source pixel.

For a nonzero offset, the deliberate hue change is evaluated from original RGB at full precision. The final RGB8 rounding error is at most half a channel step relative to the ideal real-valued transformed channel; floating-point implementations should handle rounding boundaries carefully. Alpha is copied exactly. Repeated edits do not accumulate error when each starts from the original pixels.

Before compression, a map costs two bytes per corresponding source pixel: a 50% addition to four-byte RGBA when every source pixel has a stored map. Actual file growth is not bounded by 50%, because image and mask compression ratios differ. Uniform regions, canonical zero words, omitting unused maps, and sharing identical arrays reduce storage. Each shared map can be decompressed independently, without traversing prior animation frames.

## References

- **PNG3:** W3C, *Portable Network Graphics (PNG) Specification (Third Edition)*, Recommendation, 24 June 2025. [Fixed edition](https://www.w3.org/TR/2025/REC-png-3-20250624/).
- **RFC2119:** S. Bradner, *Key words for use in RFCs to Indicate Requirement Levels*, BCP 14, March 1997. [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).
- **RFC8174:** B. Leiba, *Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words*, BCP 14, May 2017. [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).
- **RFC8259:** T. Bray, Ed., *The JavaScript Object Notation (JSON) Data Interchange Format*, December 2017. [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259).

- **RFC1950:** P. Deutsch, J-L. Gailly, *ZLIB Compressed Data Format Specification version 3.3*, May 1996. [RFC 1950](https://www.rfc-editor.org/rfc/rfc1950).
