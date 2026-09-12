# audiotag Roadmap

This roadmap describes implementation order, not release promises.

## Phase 0 — Preserve and retire the proof of concept

Status: **complete**.

- initialize Git;
- preserve the original implementation through Git history and the
  `poc-initial` tag;
- ignore local commercial music files and build artefacts;
- establish repository documentation;
- develop the replacement architecture independently of the POC;
- remove the obsolete POC modules from the active source tree after
  their relevant functionality has been replaced;
- remove the legacy CTFE ID3 registry assets and string-import build
  path once they are no longer required.

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

MP3/container integration now also includes:

- leading ID3v2.3/v2.4 prefix location and exact bounding;
- insertion, replacement and removal of the complete leading ID3v2
  envelope while preserving the remainder byte-for-byte;
- structured whole-file reads;
- same-directory POSIX temporary-file replacement with atomic `rename`
  commit semantics;
- a path-based leading-ID3v2 MP3 update API;
- end-to-end canonical edit → ID3 serialization → physical MP3 update →
  reread/reparse coverage for both ID3v2.3 and ID3v2.4.

Deliberately deferred beyond this phase:

- whole-tag unsynchronisation writing;
- extended-header CRC regeneration;
- changed-tag restriction handling beyond conservative rejection;
- compression regeneration;
- encryption regeneration.

The Phase 5 MP3 writer milestone was deliberately limited to the leading
ID3v2 region. Phase 6 has since added trailing ID3v1 container updates.
MPEG audio-frame validation and simultaneous APEv2/Lyrics3/ID3v1
coordination remain part of the later full MPEG Audio format module.

## Phase 6 — ID3 version family

Status: in progress. The ID3v2.3 parser/writer milestone, the
ID3v2.2 read milestone, and the ID3v1 codec plus MP3 trailing-tag update
milestone are complete for the currently targeted canonical scope.

Implemented for ID3v2.3:

- strict bounded tag, extended-header, frame-sequence and padding parsing;
- provenance-preserving logical traversal of whole-tag
  unsynchronisation;
- canonical reader/writer support for T***, W***, TXXX, WXXX, COMM,
  USLT, APIC, PRIV and UFID;
- canonical track/disc positions and recognized genre handling;
- compound `TYER`/`TDAT`/`TIME` projection and lossless writeback for
  canonical `recordingDate`;
- deterministic preservation, regeneration, discard/reject and padding
  policies;
- complete tag serialization with physical tag-size derivation;
- whole-tag unsynchronisation writing, including terminal-FF handling;
- extended-header CRC validation;
- CRC regeneration after logical frame changes;
- parse → write → parse coverage for ordinary, unsynchronised and
  CRC-bearing tags.

Implemented for ID3v2.2:

- explicit support policy for ID3v2.2.0; later v2.2 revisions are rejected
  as unsupported rather than guessed from the v2.2.0 grammar;
- strict bounded tag parsing with three-character frame identifiers and
  24-bit big-endian frame sizes;
- provenance-preserving logical traversal of whole-tag
  unsynchronisation;
- valid whole-tag compression retained exactly as opaque native data
  without guessing a compression representation;
- native semantic decoding for all 63 official ID3v2.2 frame identifiers;
- provenance-preserving retention of structurally valid unknown or
  experimental frame identifiers;
- tag-wide conformance validation after native decoding, including
  singleton/duplicate rules, identity-key uniqueness, special PIC
  cardinality, MCI/TRK dependency and locally decidable LNK constraints;
- explicit `indeterminate` diagnostics where linked-frame information is
  insufficient to prove a tag-level rule without dereferencing external
  content;
- canonical mappings for the intentionally supported common semantic scope:
  title, artist, album, track/disc, genre, user-defined text,
  standard/user URLs, comments, lyrics, artwork and unique file
  identifiers;
- compound `TYE`/`TDA`/`TIM` projection to precision-preserving canonical
  `recordingDate`;
- complete structure -> native -> conformance-validation -> canonical
  whole-tag read path, including explicit validation/projection
  unavailability for opaque compressed tags;
- curated public read-only `audiotag.id3v2.v22` package API;
- regression coverage proving every official v2.2 frame identifier reaches
  a known native codec path rather than the unknown-frame fallback.

The current ID3v2.2 milestone is read-only. Native decoding is complete for
the 63 frame identifiers declared by ID3v2.2.0; canonical projection remains
an intentionally narrower semantic view rather than a claim that every native
frame has a canonical equivalent.

Implemented for the wider ID3 family:

- shared numeric ID3 genre registry used by ID3v1 and ID3v2 mappings;
- canonical track/disc position values and precision-preserving
  `recordingDate` / `releaseDate` values;
- ID3v2.4 `TRCK`/`TPOS`, `TCON` and `TDRC` canonical projection;
- strict bounded ID3v1.0/ID3v1.1 parsing;
- strict ISO-8859-1 ID3v1 text decoding and lossless UTF-8-to-Latin-1
  fixed-width encoding;
- canonical ID3v1 projection/writeback for title, single artist, album,
  comment, year-only `releaseDate`, nonzero ID3v1.1 track and recognized
  genre;
- deterministic native 128-byte ID3v1 serialization with preservation of
  native-only bytes;
- canonical ID3v1 edit planning with fixed-slot conflict detection and
  explicit v1.0/v1.1 transition safety;
- MP3 trailing-ID3v1 location, insertion, replacement and removal through
  both owned in-memory buffers and the POSIX atomic whole-file update path;
- end-to-end canonical ID3v1 edit → serialization → physical MP3 update
  coverage.

Still pending in the ID3 version family:

- ID3v2.2 serialization and canonical writeback;
- broader ID3v2.2 canonical projection only where a stable,
  format-independent semantic mapping is justified;
- broader ID3v2.3 canonical coverage as further native frame codecs are
  added;
- compression and encryption transformation support;
- explicit native insertion-point control for newly introduced frames;
- broader cross-version canonical mapping where semantics differ;
- version conversion through the canonical model.

The common semantic codecs should be reused; version-specific framing
must remain separate.

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
