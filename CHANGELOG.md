# Changelog

All notable changes to `audiotag` should be documented in this file.

The project intends to follow Semantic Versioning once release versions begin.

## [Unreleased]

### Added

- Initial read-only `audiotag.mp3` prefix API for locating and bounding prepended ID3v2.3 and ID3v2.4 tags.
- I/O-free planning for insertion, replacement or removal of a prepended ID3v2 tag while preserving the remaining source bytes unchanged.
- I/O-free materialization of a leading-ID3v2 write plan into a new owned byte buffer with checked output-length arithmetic.
- High-level in-memory `audiotag.mp3` API composing prefix location, write planning and materialization into one leading-ID3v2 update operation.
- High-level same-version ID3v2.3 serialization API.
- Curated public `audiotag.id3v2.v23` package API.
- High-level same-version ID3v2.4 serialization API.
- Curated public `audiotag.id3v2.v24` package API.
- Curated public `audiotag.metadata` canonical metadata API.
- Serialization result/error types through `audiotag.core`.
- Structured file-update result/error types with explicit pre-commit, commit and post-commit stages through `audiotag.core`.
- Backend-injected file-replacement orchestration through `audiotag.io`, with commit-boundary and failure-injection coverage and no platform I/O dependency.
- Initial POSIX whole-file replacement backend using same-directory `mkstemp`, complete raw writes, access-mode preservation and atomic `rename` commit semantics.
- Public POSIX `replaceFile(path, bytes)` convenience API composing the safe replacement backend and portable orchestrator.
- Structured cross-platform `readFileBytes(path)` API for whole-file byte reads with pre-commit I/O error reporting.
- POSIX path-based MP3 leading-ID3v2 update API composing structured reads, in-memory container rewriting and atomic whole-file replacement.
- Initial bounded `audiotag.id3v1` parser for exact ID3v1.0/ID3v1.1 tag blocks with zero-copy raw field preservation.
- Strict ISO-8859-1 decoding for NUL-padded ID3v1 string fields while retaining raw source bytes.
- Provenance-preserving ID3v1 canonical projection for title, artist, album, comment, ID3v1.1 track number and recognized numeric genres.
- Canonical position value and stable `track`/`disc` registry keys with independently optional number and total components.
- ID3v2.3 and ID3v2.4 `TRCK`/`TPOS` canonical projection through shared strict numeric-position parsing.
- Canonical `genre` registry key using an ordered text list so multiple free-form genres remain representable across tag systems.
- Shared ID3 numeric genre registry covering codes 0-191 with explicit unknown-code handling and legacy reverse-lookup aliases.
- ID3v2.3 and ID3v2.4 `TCON` canonical genre projection with revision-specific legacy numeric syntax, free-text preservation and `RX`/`CR` handling.
- Precision-preserving canonical date/time value foundation and stable `recordingDate` registry key for cross-format temporal metadata.
- Strict ID3v2.4 timestamp parsing and `TDRC` recording-time projection to ordered canonical UTC date/time values.
- Stable canonical `releaseDate` key, distinct from `recordingDate`, using the shared precision-preserving date/time-list value family.
- ID3v1 four-digit year projection to canonical year-only `releaseDate` values with exact native provenance.
- Zero-copy MP3 suffix locator for fixed trailing ID3v1 `TAG` blocks.
- Combined zero-copy MP3 edge layout for leading ID3v2, opaque middle bytes and trailing ID3v1.

### Changed

- DUB package description now explicitly describes `audiotag` as a library.
- Root `audiotag` package no longer re-exports the historical utility/POC API.
- Public package structure now supports feature-oriented imports without
  requiring unrelated tag versions, containers or conversion layers.

### Removed

- Historical ID3 proof-of-concept modules from the active source tree.
- Legacy CTFE ID3 frame-registry CSV/ODS assets.
- Legacy `-Jdata/id3` DUB string-import path.

## [0.1.0] - 2026-09-08

### Added

- Git-based version history.
- Initial project documentation structure.
- Architecture decision record directory.
- Planned test and regression-corpus structure.
- Bounded zero-copy `ByteSpan` implementation in the new parser core.
- Unit tests for `ByteSpan` construction, empty spans, subspans, nested offsets, zero-length subspans and zero-copy behavior.
- Stateful bounded `ByteCursor`, numeric helpers and structured parse errors.
- Strict bounded ID3v2.4 structural parsing including extended headers, frames, padding and footer handling.
- Semantic ID3v2.4 readers and canonical mappings for T***, W***, TXXX, WXXX, COMM, USLT, APIC, PRIV and UFID.
- Provenance-aware canonical metadata tree and edit overlay.
- ID3v2.4 writer planning with preservation, regeneration, discard and reject actions.
- Complete ID3v2.4 tag serialization with source-order preservation and padding policy.
- Deterministic ID3v2.4 writers and complete tag roundtrip coverage for T***, W***, TXXX, WXXX, COMM, USLT, APIC, PRIV and UFID.
- Strict bounded ID3v2.3 structural parsing with extended headers, frame-format additions, padding and whole-tag unsynchronisation.
- Provenance-aware ID3v2.3 canonical readers and writers for T***, W***, TXXX, WXXX, COMM, USLT, APIC, PRIV and UFID.
- Complete ID3v2.3 tag serialization with preservation, regeneration, discard/reject, logical padding and whole-tag unsynchronisation policies.
- ID3v2.3 extended-header CRC validation and CRC regeneration after logical frame changes.
- ID3v2.3 parse → write → parse coverage for ordinary, unsynchronised and CRC-bearing tags.

### Changed

- ID3 frame-registry data moved from the repository root to `data/id3/`.
- DUB string-import path changed from `-J.` to `-Jdata/id3`.
- Development direction changed from an ID3-specific proof of concept to a modular, format-independent parser architecture.

### Known issues in 0.1.0

- Legacy ID3 code still emits substantial debug output during `dub test`.
- `id3v2_4_frame.d` contains a compiler deprecation caused by assigning `this.delim = delim` instead of the constructor parameter `d`.
- Legacy parsed-frame iteration visibly emits an initial empty frame.
- Legacy UTF-16 and version-specific ID3 behavior is incomplete and is not a basis for the new core.

## Historical baseline

The tag `poc-initial` marks the preserved original proof-of-concept state.
