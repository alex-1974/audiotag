# audiotag

`audiotag` is an early-stage D library for reading, normalizing, preserving, converting, and writing metadata in common audio file formats.

> **Project status:** active parser implementation / architecture phase.
> The public API and internal module structure are not stable yet.

## Goals

The library is intended to:

- read the common metadata systems used by audio files, including ID3, Vorbis Comments, FLAC metadata blocks, APEv2, MP4 metadata and others;
- expose metadata through a version-independent canonical tree;
- preserve native, unknown and partially malformed metadata where practical;
- write metadata back to all supported target formats and versions;
- support conversion between metadata systems without silently discarding information;
- parse binary structures as bounded D ranges/subranges rather than through global file-position state;
- tolerate common real-world tag errors and return structured diagnostics instead of failing on every specification violation;
- use modern, idiomatic D: `struct`, ranges, UFCS, `const`, `@safe`, CTFE, `std.sumtype` where useful, and allocation-free core primitives where practical;
- allow format support to be modular so an application can build only the parsers it needs.

## Non-goals for the current phase

The current phase is **not** trying to:

- provide a stable public API;
- claim full compliance with any audio metadata specification;
- provide production-ready repair heuristics;
- optimize before the byte-range core and parser invariants are proven;
- implement all formats at once.

## Current state

The repository began as an experimental ID3 proof of concept. The
original proof-of-concept modules have now been removed from `main`
after their relevant functionality was replaced by the bounded parser
architecture. Their history remains available through Git and the
`poc-initial` tag.

The active implementation now includes:

- bounded zero-copy `ByteSpan` and stateful `ByteCursor` primitives;
- structured parse and serialization errors;
- strict bounded ID3v2.4 tag and frame parsing;
- native/provenance-aware ID3v2.4 semantic frame decoding;
- strict bounded ID3v2.3 tag, extended-header, frame and padding parsing;
- provenance-preserving ID3v2.3 whole-tag unsynchronisation traversal;
- an order-preserving canonical metadata tree and edit overlay;
- deterministic canonical-to-ID3v2.4 and canonical-to-ID3v2.3 planning;
- complete ID3v2.4 and ID3v2.3 tag serialization for the currently
  targeted frame families;
- canonical reader/writer support for T***, W***, TXXX, WXXX, COMM,
  USLT, APIC, PRIV and UFID;
- ID3v2.3 whole-tag unsynchronisation writing;
- ID3v2.3 extended-header CRC validation and regeneration;
- parse → write → parse coverage for ordinary, unsynchronised and
  CRC-bearing ID3v2.3 tags;
- preservation, regeneration, discard/reject and padding policies;
- structured whole-file reads and POSIX whole-file replacement with
  explicit pre-commit, commit and post-commit error stages;
- MP3 leading-ID3v2.3/v2.4 insertion, replacement and removal while
  preserving the remaining file bytes unchanged;
- POSIX path-based MP3 leading-ID3v2 updates composing read, in-memory
  container rewrite and atomic pathname replacement;
- end-to-end ID3v2.3 and ID3v2.4 canonical edit → serialization →
  physical MP3 file update → reread/reparse coverage;
- bounded ID3v1.0/ID3v1.1 parsing with strict ISO-8859-1 text decoding
  and UTF-8-to-ISO-8859-1 encoding;
- canonical ID3v1 projection/writeback for title, single artist, album,
  comment, year-only `releaseDate`, ID3v1.1 track and recognized genre;
- deterministic 128-byte ID3v1 serialization with native-only byte
  preservation and explicit v1.0/v1.1 transition safety;
- MP3 trailing-ID3v1 location, insertion, replacement and removal in
  memory and through the POSIX whole-file update path.

The current MP3 layer handles the two implemented edge metadata regions:
leading ID3v2.3/ID3v2.4 and final ID3v1. Bytes between them remain opaque.
It does not yet validate MPEG audio frames or coordinate additional
trailing systems such as APEv2 and Lyrics3. Deterministic precedence and
preservation across the complete MPEG Audio tag set remain a later
roadmap phase.

## Core design

The intended parsing stack is:

```text
Byte source
    ↓
ByteSpan
    ↓
ByteCursor / bounded subranges
    ↓
container / structural parser
    ↓
tag / metadata codec
    ↓
native/provenance-aware representation
    ↓
canonical metadata tree
    ↓
target-format writer
```

Every nested parser receives a bounded byte region and must not read outside it.

Implemented core operations include:

```text
takeBytes(n)                  exact, atomic consumption
takeAvailable(n)              explicitly partial consumption
peekBytes(n)
skipBytes(n)
subspan(...)
takeUntilPattern(...)
takeUntilPatternAligned(...)
alignTo(...)
readU16/U24/U32/U64 LE/BE
readSynchsafe32()
```

A failed atomic operation must not change the cursor position.

See [ARCHITECTURE.md](ARCHITECTURE.md).

## Build

The project uses DUB and deliberately builds as a library.

```bash
dub build
dub test
```

The DUB package uses:

```sdl
targetType "library"
```

No legacy string-import path or generated ID3 frame-registry asset is
required by the active implementation.

## Tests

Testing is part of the definition of done.

Every new public/core function should include:

- Ddoc documentation;
- direct `unittest` coverage;
- boundary tests;
- failure tests where applicable.

Parser changes additionally require malformed-input and regression tests.

Real commercial music files under the local `music/` directory are intentionally ignored by Git. Reproducible tests should use synthetic, generated, freely licensed or otherwise redistributable fixtures.

## Repository layout

```text
.
├── README.md
├── CHANGELOG.md
├── ROADMAP.md
├── ARCHITECTURE.md
├── CONTRIBUTING.md
├── FORMAT_SUPPORT.md
├── SECURITY.md
├── dub.sdl
├── docs/
│   └── adr/
├── source/
│   └── audiotag/
│       ├── core/
│       ├── metadata/
│       ├── id3/
│       ├── id3v1/
│       ├── id3v2/
│       │   ├── common/
│       │   ├── v23/
│       │   └── v24/
│       ├── io/
│       ├── mp3/
│       └── package.d
├── testdata/
│   ├── malformed/
│   └── synthetic/
└── tests/
    ├── integration/
    └── regression/
```

Some directories may remain absent from Git until they contain tracked files.

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — parser, tree and writer architecture
- [ROADMAP.md](ROADMAP.md) — implementation sequence
- [FORMAT_SUPPORT.md](FORMAT_SUPPORT.md) — format coverage and priorities
- [CONTRIBUTING.md](CONTRIBUTING.md) — coding, testing and Git rules
- [SECURITY.md](SECURITY.md) — untrusted-input and parser-security rules
- [CHANGELOG.md](CHANGELOG.md) — user-relevant changes
- `docs/adr/` — architecture decision records

## License

`dub.sdl` currently declares `CC-BY-SA-4.0`.

Before the first public library release, the suitability of that license for source-code distribution should be reviewed and a repository-level `LICENSE` file should be added.
