# ADR 0003: Separate container, metadata-codec and canonical layers

## Status

Accepted.

## Context

Common music files do not share one metadata architecture.

Examples:

- MP3 may carry multiple independent tags.
- FLAC contains typed metadata blocks.
- Ogg requires page and packet reconstruction before codec metadata is available.
- MP4 is a recursive box tree.

A single flat "TagParser" abstraction would hide necessary structure and encourage duplication.

## Decision

The project separates:

1. structural/container parsing;
2. metadata/tag codecs;
3. format composition;
4. canonical metadata normalization;
5. format-specific serialization and container writing.

Reusable tag codecs such as ID3, Vorbis Comments and APEv2 are not owned by only one container implementation.

## Consequences

- the same metadata codec can be reused in multiple file formats;
- container-specific rewrite logic remains separate from metadata encoding;
- architecture is more complex than a single parser interface;
- module boundaries reflect actual file-format structure.
