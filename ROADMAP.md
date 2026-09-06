# audiotag Roadmap

This roadmap describes implementation order, not release promises.

## Phase 0 — Preserve the proof of concept

Status: largely complete.

- initialize Git;
- preserve original source as historical POC;
- ignore local commercial music files and build artefacts;
- move ID3 registry data under `data/id3/`;
- establish repository documentation;
- repair DUB string-import path after the registry move.

## Phase 1 — Binary parsing core

Goal: prove the generic bounded range model before writing more tag parsers.

Status: **complete** for the current parser-core requirements.

### 1.1 ByteSpan

- bounded zero-copy byte view;
- `const(ubyte)[]`;
- absolute source offset;
- subspans;
- `@safe`, `@nogc`, `nothrow` where practical;
- comprehensive unit tests.

Current state: implemented, committed and covered by unit tests.

### 1.2 ByteCursor

Implement:

```text
position
absoluteOffset
remaining
empty
front
popFront
peekBytes(n)
takeBytes(n)
takeAvailable(n)
skipBytes(n)
```

Required invariant:

> failed atomic operations do not change cursor state.

### 1.3 ParseError

Implement allocation-light structured errors:

```text
endOfSpan
invalidLength
overflow
patternNotFound
...
```

### 1.4 Pattern search

Implement and test:

```text
takeUntilPattern(...)
takeUntilPatternAligned(...)
```

including:

- beginning/middle/end match;
- missing pattern;
- overlapping matches;
- maximum search length;
- alignment 1/2/4;
- cursor rollback on failure.

### 1.5 Numeric primitives

Implemented:

```text
U16/U24/U32/U64 LE/BE
synchsafe integer
```

Generic alignment helpers are deferred until a structural format provides
a concrete alignment-origin requirement. Aligned pattern search is already
implemented.

## Phase 2 — ID3v2.4 structural parser

Status: strict structural parsing milestone implemented.

Goal: use the new core against a real, complex tag system.

Implemented:

- ID3 signature, version and header validation;
- bounded tag body derived from the declared tag size;
- extended-header parsing;
- validated optional footer;
- bounded frame sequence;
- synchsafe frame-size and frame-flag parsing;
- exact frame-data bounds;
- tag-level and frame-level unsynchronisation traversal;
- structural parsing of grouping identity, encryption method and Data Length Indicator fields;
- strict padding validation;
- raw frame and payload spans with absolute source offsets;
- end-to-end transactional parsing of a complete ID3v2.4 tag.

The strict structural parser has also been exercised successfully against
a real ID3v2.4 tag during development. The audio sample is not part of
the repository or automated test corpus.

Still pending before this phase is fully complete:

- higher-level structured diagnostics and recovery information;
- explicit native-node representation for unknown frames beyond the raw
  structural spans already preserved;
- CRC verification when an extended-header CRC is present.

Semantic frame codecs are deliberately deferred to Phase 3.

## Phase 3 — Text and common ID3 frame codecs

Status: **initial codec milestone complete**.

Implemented robust text decoding:

- ISO-8859-1;
- UTF-8;
- UTF-16 with BOM;
- UTF-16BE;
- aligned terminators;
- malformed text diagnostics.

Implemented initial frame families:

```text
T***
TXXX
W***
WXXX
COMM
USLT
APIC
PRIV
UFID
```

The codecs preserve native/raw provenance where required. Structurally valid compressed or encrypted payloads that require unsupported transformations are represented as transformation-pending outcomes rather than malformed input.

## Phase 4 — Canonical metadata tree

Status: **initial canonical integration milestone complete**.

Implemented:

- typed canonical values for text, ordered multi-value text, integers,
  URLs, binary data and pictures;
- provenance carrying native metadata identifiers, source extents and
  confidence;
- ordered repeatable canonical fields;
- canonical language, descriptions and ordered qualifiers;
- format-independent canonical field registry;
- ID3v2.4 mappings for the currently implemented semantic frame
  families;
- shared canonical mapping outcomes:
  `mapped`, `unsupportedFrame`, `requiresTransformation` and
  `unrepresentableValueShape`;
- central native-frame → canonical dispatcher;
- provenance-preserving frame projection retaining every native frame
  in original order;
- complete native-plus-canonical ID3v2.4 whole-tag view.

The canonical tree is deliberately a semantic view rather than a
replacement for native metadata. Native frames remain available for
roundtrip-aware writing even when they map successfully.

Still pending:

- broader canonical coverage as further native frame codecs are added;
- higher-level structured diagnostics and recovery information;
- stable public API design.

## Phase 5 — ID3 writer

Status: complete for the currently targeted ID3v2.4 codec scope.

Implemented:

- ID3v2.4 serialization;
- stable roundtrip;
- unknown-frame preservation policy;
- padding strategy;
- parse → write → parse tests;
- canonical writer support for T***, W***, TXXX, WXXX, COMM, USLT,
  APIC, PRIV and UFID.

Deliberately deferred beyond this phase:

- whole-tag unsynchronisation writing;
- extended-header CRC regeneration;
- changed-tag restriction handling beyond conservative rejection;
- compression regeneration;
- encryption regeneration;
- MPEG/MP3 container update strategy.

## Phase 6 — ID3 version family

Add:

- ID3v2.3 framing and encoding rules;
- ID3v2.2 frame IDs/framing;
- ID3v1;
- version conversion through the canonical model.

The common semantic codecs should be reused; version-specific framing must remain separate.

## Phase 7 — Vorbis Comments and native FLAC

Implement Vorbis Comments as an independent metadata codec:

- vendor string;
- repeated keys;
- case-insensitive keys;
- ordered values;
- UTF-8;
- pictures where appropriate to the enclosing format.

Implement FLAC:

- metadata-block range;
- STREAMINFO;
- PADDING;
- APPLICATION/unknown preservation;
- VORBIS_COMMENT;
- PICTURE;
- writer with padding reuse.

## Phase 8 — Ogg

Implement:

- Ogg pages;
- lacing table;
- CRC validation;
- logical stream tracking;
- packet reconstruction;
- Vorbis metadata;
- OpusTags;
- recovery scanning as an explicitly heuristic path.

## Phase 9 — APEv2 and MPEG tag set

Implement APEv2 as a reusable metadata codec.

Build a full MPEG Audio format module that can expose multiple simultaneous tag systems:

```text
ID3v2
MPEG audio
APEv2
Lyrics3
ID3v1
```

Define deterministic canonical precedence while preserving every native tag.

## Phase 10 — MP4 / ISO-BMFF

Implement recursive box parser and music metadata:

- size / extended size;
- bounded child boxes;
- unknown box preservation;
- `meta`;
- `keys`;
- `ilst`;
- common iTunes-style fields;
- free-space-aware writer.

## Phase 11 — Additional containers

Candidates:

- RIFF/WAVE;
- BWF/RF64/BW64;
- AIFF/AIFC;
- ASF/WMA;
- Matroska/WebM;
- DSF/DSDIFF;
- WavPack;
- Musepack;
- Monkey's Audio;
- TrueAudio.

Priority should follow real use cases and test-file availability.

## Phase 12 — Package modularity

When format implementations justify it, introduce DUB subpackages such as:

```text
audiotag:core
audiotag:mp3
audiotag:flac
audiotag:ogg
audiotag:mp4
audiotag:all
```

Do not add packaging complexity before it provides a real benefit.

## Phase 13 — Hardening

- fuzzing;
- corpus testing;
- coverage analysis;
- DMD + LDC CI;
- Linux/Windows/macOS CI;
- resource limits;
- hostile-input testing;
- performance benchmarks;
- memory-mapped source backend where useful.

## v1.0 criteria

Do not call the API stable before:

- core parser invariants are stable;
- canonical tree is stable;
- reader/writer roundtrips are tested;
- at least the major music metadata families are supported;
- malformed input has deterministic error semantics;
- public API is documented;
- supported D/compiler versions are documented;
- license is finalized.
