# audiotag Architecture

## 1. Purpose

`audiotag` is intended to support multiple audio containers and metadata systems while exposing a consistent metadata model.

The architecture must accommodate formats that are structurally very different:

- MP3/MPEG Audio may carry several independent tag blocks such as ID3v2, APEv2, Lyrics3 and ID3v1.
- FLAC contains typed metadata blocks inside the native container.
- Ogg is page-based and requires page parsing, logical-stream reconstruction and packet reconstruction before codec metadata can be decoded.
- MP4/QuickTime is a recursive box/atom tree.
- RIFF/WAVE and AIFF/IFF are chunk hierarchies with padding/alignment rules.
- Matroska uses a recursive EBML structure and scoped metadata.

Therefore the library must not equate a **file format**, **container structure**, and **metadata/tag codec**.

## 2. Architectural layers

```text
I/O / byte source
       ↓
ByteSpan
       ↓
ByteCursor
       ↓
structural/container parser
       ↓
metadata/tag codec
       ↓
native/provenance-aware nodes
       ↓
canonical metadata tree
       ↓
format-specific serializer
       ↓
container writer/update strategy
```

### 2.1 Byte source

Parsers should not depend directly on `std.stdio.File` or a global file position.

Possible source backends may later include:

- in-memory byte arrays;
- buffered files;
- memory-mapped files.

The parser API should operate on bounded byte views rather than on the backing I/O mechanism.

### 2.2 ByteSpan

`ByteSpan` is a fixed, bounded, zero-copy view over `const(ubyte)[]`.

Properties:

- no mutable parser position;
- source-relative absolute offset;
- cheap subspans;
- no payload copying;
- no ownership assumption;
- parser cannot mutate source bytes through the span.

A `ByteSpan` is not itself the stateful parser cursor.

### 2.3 ByteCursor

`ByteCursor` will provide stateful traversal over one `ByteSpan`.

Required properties:

```text
position
absoluteOffset
remaining
empty
```

Initial required operations:

```text
peekBytes(n)
takeBytes(n)
takeAvailable(n)
skipBytes(n)
```

Later:

```text
takeUntilPattern(...)
takeUntilPatternAligned(...)
alignTo(...)
readU16LE/BE
readU24LE/BE
readU32LE/BE
readU64LE/BE
readSynchsafe32()
```

### 2.4 Atomic cursor operations

An important parser invariant is:

> A failed atomic cursor operation does not change the cursor state.

For example:

```text
remaining = 4
takeBytes(10)
```

must return a structured parse error while leaving the position unchanged.

This enables safe look-ahead, alternate parsing paths and recovery.

## 3. Bounded subparsers

The most important safety invariant is:

> Every nested parser operates only on the span assigned by its parent parser.

Examples:

```text
ID3 tag span
└── frame span
    ├── frame-header span
    └── payload span
```

```text
FLAC file span
└── metadata-block span
    └── Vorbis-comment span
        └── field span
```

```text
MP4 box span
└── child-box span
    └── child payload
```

A malformed length may invalidate the current structure, but a subparser must never be able to read arbitrary bytes beyond its parent boundary.

## 4. Exact versus partial consumption

The core API must distinguish semantics explicitly.

### `takeBytes(n)`

Means:

> consume exactly `n` bytes or fail atomically.

It must never silently return fewer bytes.

### `takeAvailable(n)`

Means:

> consume up to `n` bytes.

This is useful for explicit recovery paths but must not be confused with specification-defined exact reads.

## 5. Pattern search

`takeUntilPattern(...)` is part of the generic parsing core because many metadata formats use terminators or signatures.

Its API must eventually define:

- whether the match is included in the returned span;
- whether the delimiter itself is consumed;
- maximum search distance;
- behavior when no match exists;
- overlapping-pattern handling;
- optional alignment.

### Alignment

Alignment is necessary for encodings and binary structures where a matching byte sequence is only valid at specific offsets.

Example: a UTF-16 NUL terminator is `00 00`, but a naive byte search can match across a code-unit boundary.

Therefore an aligned search operation is required rather than embedding UTF-16-specific logic in the generic pattern searcher.

## 6. Parse errors and diagnostics

Malformed external bytes are not programming errors.

The library distinguishes:

### ParseError

Low-level, structured, allocation-light information such as:

```text
endOfSpan
patternNotFound
invalidLength
integerOverflow
invalidEncodingMarker
```

with numeric context such as:

```text
offset
requested
available
```

The byte core should remain allocation-free where practical.

### Diagnostic

Higher-level parser information:

```text
severity
format
code
offset
message
recovery
confidence
```

The higher layer may allocate descriptive text.

### Assertions

`assert` and contracts protect internal invariants only.

They must not be used to reject malformed input originating from an audio file.

## 7. Error tolerance

Future parser modes may include:

```text
strict
tolerant
repair
```

Potential meanings:

- **strict** — stop the affected structure at a specification violation;
- **tolerant** — preserve safely decodable data and record diagnostics;
- **repair** — additionally use explicit heuristics to re-synchronize.

Recovered values must never be silently presented as exact values.

A confidence model may distinguish:

```text
exact
recovered
guessed
```

## 8. Native information and canonical metadata

The canonical metadata model must not destroy information needed for roundtrips.

The public model must be able to retain provenance such as:

```text
source format
native field/frame identifier
source span / offset
native flags
encoding
scope
language / locale
confidence
diagnostics
raw unknown data
```

Unknown data is different from corrupt data.

Unknown but structurally valid fields should normally be preserved.

Corrupt regions should be representable as raw/provenance nodes when safe.

## 9. Canonical tree requirements

A plain `string[string]` model is insufficient.

The model must support:

- multiple values for one semantic key;
- stable ordering where meaningful;
- typed values;
- binary values;
- pictures/artwork;
- URLs;
- nested structures;
- scoped metadata;
- language/locale;
- descriptions/qualifiers;
- provenance;
- unknown native nodes.

The type system should prefer D value types and may use `std.sumtype.SumType` for heterogeneous values.

## 10. Format, container and metadata modules

The architecture distinguishes:

### Container / structural modules

Examples:

```text
MPEG Audio
FLAC
Ogg
MP4 / ISO-BMFF
RIFF
IFF
ASF
Matroska / EBML
DSF
```

### Metadata/tag codecs

Examples:

```text
ID3
Vorbis Comment
APEv2
Lyrics3
RIFF INFO
BWF metadata
Matroska Tags
```

### Format composition

Examples:

```text
MP3
├── MPEG Audio
├── ID3v2
├── APEv2
├── Lyrics3
└── ID3v1
```

```text
FLAC
├── FLAC metadata blocks
├── Vorbis Comment
└── Picture
```

```text
Ogg/Opus
├── Ogg pages
├── logical streams
├── packets
├── Opus
└── OpusTags
```

Metadata codecs should be reusable rather than duplicated inside every container.

## 11. Module loading

The initial implementation should prefer compile-time modularity.

Possible future package structure:

```text
audiotag:core
audiotag:id3
audiotag:mp3
audiotag:vorbiscomment
audiotag:flac
audiotag:ogg
audiotag:mp4
audiotag:ape
audiotag:all
```

This should only be introduced when separate DUB subpackages provide real value.

Applications should eventually be able to construct parser sets such as:

```text
MP3 only
music formats
all supported formats
```

Runtime third-party plugins are a later concern. If introduced, a small versioned `extern(C)` ABI is preferred over exposing unstable D object ABI across independently compiled plugins.

## 12. Writers

Metadata serialization and container updating are separate responsibilities.

A metadata codec answers:

> How is this metadata represented in this tag system?

A container writer answers:

> How are the resulting bytes safely inserted into or updated inside this file?

Examples:

- ID3 may use padding or require shifting MPEG audio.
- FLAC may reuse metadata padding.
- MP4 may use `free`/`skip` space or require box-tree size updates.
- Ogg metadata changes may require packet repagination and CRC regeneration.
- Matroska may use `Void` or rebuild affected structures.

## 13. Conversion policy

Metadata systems are not isomorphic.

Future writers should expose conversion policy such as:

```text
strict
bestEffort
preserveExtension
```

Unrepresentable information must produce diagnostics rather than disappearing silently.

## 14. D language rules

Preferred defaults:

- parser input: `const(ubyte)[]`;
- static lookup data: `immutable`;
- data objects: `struct`;
- parser core: `@safe`;
- unsafe integration: minimal reviewed `@trusted`;
- byte primitives: `@nogc nothrow` where practical;
- no GC prohibition for the canonical tree unless profiling justifies it;
- public API types explicit;
- `auto` freely used for obvious local types;
- UFCS where it improves parser readability;
- CTFE for static registries;
- `std.sumtype` instead of unnecessary class hierarchies;
- no `assumeSafeAppend` without a demonstrated need and a narrowly reviewed wrapper.

The parser code should remain readable as a description of the binary format.

## 15. Testing architecture

Three test levels are required.

### Unit tests

Located close to functions through D `unittest` blocks.

Every public/core function requires direct tests.

### Integration tests

Whole structures and complete parse/write flows.

### Regression and malformed corpus

Every fixed parser bug should gain a permanent regression case.

Malformed-input tests should verify not only success/failure but:

```text
diagnostic code
offset
cursor state
recovery behavior
later synchronization
raw-data preservation
```

## 16. Security limits

All input is untrusted.

Future parser limits should cover:

- maximum metadata size;
- maximum number of nodes/frames;
- maximum string size;
- maximum artwork size;
- maximum recursion depth;
- maximum pattern-search distance;
- maximum decompressed metadata size where compression exists.

No attacker-controlled length should cause unchecked allocation.

## 17. Legacy proof of concept

The current legacy modules are retained temporarily to preserve experiments and real-world observations.

They are not the architecture to extend.

Known legacy behavior includes:

- direct `File` state inside ID3 frame iteration;
- incorrect/unfinished range behavior;
- unfinished UTF-16 handling;
- mixed ID3v2.3/v2.4 assumptions;
- experimental duplicate frame decoder designs;
- debug output inside unittests.

New code should be built in the new core and gradually replace legacy functionality through small commits.
