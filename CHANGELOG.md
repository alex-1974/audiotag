# Changelog

All notable changes to `audiotag` should be documented in this file.

The project intends to follow Semantic Versioning once release versions begin.

## [Unreleased]

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

### Known development issues

- Legacy ID3 code still emits substantial debug output during `dub test`.
- `id3v2_4_frame.d` contains a compiler deprecation caused by assigning `this.delim = delim` instead of the constructor parameter `d`.
- Legacy parsed-frame iteration visibly emits an initial empty frame.
- Legacy UTF-16 and version-specific ID3 behavior is incomplete and is not a basis for the new core.

## Historical baseline

The tag `poc-initial` marks the preserved original proof-of-concept state.
