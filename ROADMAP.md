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

Implement:

```text
U16/U24/U32/U64 LE/BE
synchsafe integer
alignment helpers
```

## Phase 2 — ID3v2.4 structural parser

Goal: use the new core against a real, complex tag system.

Implement:

- ID3 signature and header;
- tag-size bounds;
- extended header;
- frame range;
- frame-size/flag parsing;
- padding;
- footer;
- unknown frame preservation;
- raw payload spans;
- structured diagnostics.

Do not yet attempt every semantic frame codec.

## Phase 3 — Text and common ID3 frame codecs

Implement robust text decoding:

- ISO-8859-1;
- UTF-8;
- UTF-16 with BOM;
- UTF-16BE;
- aligned terminators;
- malformed text diagnostics.

Initial frame families:

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

## Phase 4 — Canonical metadata tree

Define typed, provenance-aware metadata representation supporting:

- text;
- multi-value text;
- integer/count structures;
- URLs;
- pictures;
- binary values;
- nested values;
- scope;
- language;
- native identifiers;
- unknown nodes;
- raw provenance.

Create canonical field registry independent of tag versions.

## Phase 5 — ID3 writer

Implement:

- ID3v2.4 serialization;
- stable roundtrip;
- unknown-frame preservation policy;
- padding strategy;
- parse → write → parse tests.

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
