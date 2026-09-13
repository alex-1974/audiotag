# ADR 0008: Preserve-first ID3v2.2 writer with revision-specific framing

## Status

Accepted.

## Context

The ID3v2.2.0 read path is complete and deliberately separates bounded
structural parsing, native/provenance-aware semantic decoding, tag/revision
conformance validation, and canonical projection.

All 63 frame identifiers declared by ID3v2.2.0 have native decoder paths.
Canonical projection is intentionally narrower and covers only semantics for
which the project currently has a stable format-independent representation.

ID3v2.3 and ID3v2.4 already provide same-version writer pipelines with explicit
frame planning, preservation/regeneration decisions, body planning,
unsynchronisation, and tag serialization.

Those revisions expose frame status flags such as discard-on-tag-alter,
discard-on-file-alter, and read-only. The common writer policy uses those
semantic properties.

ID3v2.2 frames are different. Their six-byte frame header contains only a
three-byte frame identifier and a three-byte unsigned big-endian payload size.
ID3v2.2 has no per-frame status flags. Pretending that such flags exist merely
to reuse the v2.3/v2.4 policy would hide a real revision difference and violate
ADR 0006.

ID3v2.2 also defines whole-tag compression and whole-tag unsynchronisation.
The published v2.2.0 specification does not define a compression scheme. A
compressed tag can therefore be preserved as opaque source bytes, but its
frames cannot be safely regenerated.

The specification requires compression, when used, to precede
unsynchronisation. The stored tag-size field describes the complete physical
tag body after unsynchronisation and excludes the fixed ten-byte ID3 header.

## Decision

### 1. Writer scope is same-version ID3v2.2.0

The writer emits ID3v2.2.0 only.

It does not claim support for later ID3v2.2 minor revisions and does not perform
cross-version conversion as part of the same-version writer.

### 2. ID3v2.2 frame planning is revision-specific

ID3v2.2 will have concrete frame write-plan and action types.

The v2.3/v2.4 frame-status policy will not be reused by manufacturing dummy
`readOnly`, `discardOnTagAlter`, or `discardOnFileAlter` properties.

For an uncompressed decoded source tag:

- an unchanged mapped frame preserves its complete original physical frame;
- a modified mapped frame is regenerated when a v2.2 regenerator exists;
- a removed mapped frame is omitted;
- an unchanged native-only/unsupported frame preserves its complete original
  physical frame;
- a canonical modification that would require changing a native-only frame is
  rejected until that semantic write path exists.

Because ID3v2.2 has no frame status flags, changing the enclosing tag or file
does not by itself force an otherwise unknown/native-only frame to be discarded.

### 3. Native decoder coverage and writer regeneration coverage are separate

Native decoding of all 63 official frame identifiers does not imply that all
63 frames must immediately have serializers.

The first semantic writer milestone regenerates only the currently supported
canonical scope, including as applicable:

- ordinary mapped text information;
- user-defined text;
- standard and user-defined URL fields;
- comments;
- unsynchronised lyrics/text;
- attached pictures;
- unique file identifiers;
- track/disc and genre representations already supported canonically;
- compound `TYE`/`TDA`/`TIM` recording-date representation.

Other decoded standard frames remain valid native metadata and are preserved
byte-for-byte when unchanged.

Additional native regenerators may be added independently when a real editing
or conversion requirement exists.

### 4. Whole-tag-compressed sources are preservation-only

A source with the ID3v2.2 compression flag set remains opaque because the
published v2.2.0 specification defines no compression representation.

A no-op/native preservation path may return the exact original complete tag
bytes.

Any operation requiring semantic modification, frame regeneration, padding
replanning, recompression, or reconstruction of a compressed tag is rejected
with an explicit transformation/serialization failure.

The writer must never clear the compression flag and reinterpret opaque
compressed bytes as ordinary frames.

### 5. Writer planning occurs in the logical uncompressed byte domain

For an uncompressed tag, frame serializers produce logical/native frame bytes.

Body planning then operates on:

```text
logical frame sequence
    +
logical zero padding
```

Source unsynchronisation stuffing is physical provenance and is excluded from
logical capacity calculations.

The default padding policy follows the existing preservation-oriented ID3v2
writer behavior:

- preserve the source logical frames-plus-padding capacity while the new frame
  sequence fits;
- consume padding before growing the tag;
- when the new frame sequence exceeds the old logical capacity, drop padding
  to zero and grow the body.

ID3v2.2 has no extended header, so no extended-header planning is required.

A writable ID3v2.2 tag must still contain at least one frame.

### 6. Whole-tag unsynchronisation is an outer body transformation

For newly constructed or changed uncompressed tags, the writer pipeline is:

```text
canonical/native write plan
    ↓
logical frame serialization
    ↓
logical frame sequence
    ↓
logical padding
    ↓
complete logical tag body
    ↓
whole-tag unsynchronisation when required
    ↓
physical stored tag body
    ↓
ID3v2.2 tag header using physical body length
```

Unsynchronisation is never applied independently to already preserved physical
frame slices and then applied again to the complete body.

When unsynchronisation is active, logical `$FF $00` sequences are protected in
addition to false MPEG synchronisation patterns.

For a changed/reconstructed tag, the unsynchronisation flag is derived from the
resulting body rather than copied blindly from the source header.

The common byte-transformation algorithm may be shared with another ID3v2
revision only if its byte semantics are proven identical. Revision-specific
activation and boundary policy remain explicit.

### 7. Physical framing remains concrete ID3v2.2 code

ID3v2.2 frame serialization emits:

```text
3-byte frame identifier
3-byte ordinary unsigned big-endian payload size
payload
```

The payload size must be in the inclusive range `1 .. 0xFF_FF_FF`.

ID3v2.2 tag-header serialization emits:

```text
"ID3"
$02 $00
header flags
28-bit synchsafe physical tag-body size
```

The tag-size field excludes the fixed ten-byte header and is computed only
after all outer body transformations that affect physical length.

These representations are revision-specific and are not hidden behind v2.3 or
v2.4 framing types.

### 8. Text writing uses only v2.2-defined encodings

ID3v2.2 text fields use the existing legacy encoding marker semantics:

- `$00` for ISO-8859-1;
- `$01` for Unicode/UCS-2 representation.

No v2.3/v2.4-only text-encoding marker is emitted.

Encoding selection and representability checks may reuse shared legacy-text
algorithms where their semantics are genuinely identical, while v2.2 frame
layout remains revision-specific.

### 9. Native order and provenance are preserved

Existing native frames retain source order.

A preserved frame reuses its complete original physical representation when
that representation can safely participate in the output domain.

Regenerated frames replace their source position rather than causing unrelated
native frames to move.

New canonical fields use a deterministic insertion policy; they must not
silently reorder unrelated native metadata.

The exact insertion rule may reuse an existing cross-revision planning
algorithm if its semantics are revision-independent under ADR 0006.

### 10. Conformance validation remains separate from parsing and planning

An unchanged source tag may be preserved even when the read-side conformance
report contains semantic violations; preservation is not repair.

A changed/reconstructed tag must not silently introduce or claim strict
conformance in the presence of definite locally checkable ID3v2.2 violations.

The resulting planned/written tag is validated against the existing ID3v2.2
tag-level rules before it is exposed as a successful changed serialization.

Constraints that remain locally indeterminate, especially some `LNK`
relationships, stay explicitly indeterminate rather than being guessed or
dereferenced by the writer.

## Consequences

- ID3v2.2 writer behavior reflects the actual v2.2.0 format instead of
  pretending it has v2.3/v2.4 frame flags.
- Unknown, experimental, and currently non-editable standard frames can survive
  ordinary edits without information loss.
- 63/63 native read coverage can remain complete while writer regeneration
  grows incrementally.
- Opaque compressed tags remain lossless for exact preservation but cannot be
  semantically edited until a concrete compression representation is known.
- Whole-tag unsynchronisation and padding are planned in explicit logical and
  physical byte domains, preventing double stuffing and incorrect tag sizes.
- Frame and tag header encoders remain small, testable revision-specific
  primitives.
- Shared writer code is introduced only at semantic boundaries justified by
  ADR 0006.
- The natural implementation order is structural writer primitives first,
  preservation/planning second, canonical regenerators third, and complete
  tag/API integration last.
