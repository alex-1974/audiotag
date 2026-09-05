# Changelog

All notable changes to `audiotag` should be documented in this file.

The project intends to follow Semantic Versioning once release versions begin.

## [Unreleased]

### Added

- Git-based version history.
- Initial project documentation structure.
- Architecture decision record directory.
- Planned test and regression-corpus structure.
- Bounded zero-copy `ByteSpan` implementation in the new parser core.
- Unit tests for `ByteSpan` construction, empty spans, subspans, nested offsets, zero-length subspans and zero-copy behavior.

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
