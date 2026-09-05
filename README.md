# audiotag

`audiotag` is an early-stage D library for reading, normalizing, preserving, converting, and writing metadata in common audio file formats.

> **Project status:** proof of concept / architecture phase.
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

The repository began as an experimental ID3 proof of concept.

The legacy code currently contains:

- basic audio-header detection for ID3, FLAC and Ogg signatures;
- experimental ID3v2 header/frame parsing;
- experimental ID3 text decoding;
- a compile-time ID3 frame registry generated from CSV;
- proof-of-concept D ranges for frames.

The format-independent binary parsing core is now implemented. It includes bounded zero-copy `ByteSpan` views, stateful `ByteCursor` traversal, structured allocation-light parse errors and results, exact and partial byte consumption, bounded and aligned pattern search, endian integer readers, and validated synchsafe integer decoding.

Known legacy issues are intentionally being left isolated rather than fixed opportunistically during the core rewrite.

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

Important primitive operations will include:

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

The project uses DUB and currently builds as a library.

```bash
dub build
dub test
```

The current DUB file uses:

```sdl
targetType "library"
dflags "-Jdata/id3"
```

The `-Jdata/id3` path is required by the legacy CTFE string import of `id3v2-frame-id.csv`.

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
├── data/
│   └── id3/
│       ├── id3v2-frame-id.csv
│       └── id3v2-frame-id.ods
├── docs/
│   └── adr/
├── source/
│   └── audiotag/
│       ├── core/
│       ├── id3.d
│       ├── id3_utils.d
│       ├── id3v2_4_frame.d
│       ├── package.d
│       └── utils.d
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
