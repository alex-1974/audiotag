# ADR 0001: Bounded byte spans

## Status

Accepted.

## Context

Audio metadata frequently contains malformed, inconsistent or malicious length fields. The original proof of concept read ID3 frames directly from a `File` and compared global file positions with tag-relative sizes. This couples format parsing to I/O state and makes boundary errors easier.

The project must also support very different nested formats such as ID3, FLAC, Ogg and MP4.

## Decision

All nested binary parsing is based on bounded byte regions.

`ByteSpan` represents a fixed zero-copy view over `const(ubyte)[]` and carries an absolute source offset.

Parent parsers explicitly create bounded subspans for child parsers.

A child parser must not read outside the span assigned by its parent.

Stateful traversal is provided separately by `ByteCursor`.

## Consequences

Advantages:

- boundary rules are explicit;
- parser code is independent of `File.tell()`;
- nested formats map naturally to nested subspans;
- malformed child structures cannot silently consume unrelated following data;
- testing with synthetic byte arrays becomes simple;
- zero-copy parsing is natural.

Costs:

- parent parsers must validate sizes before creating subspans;
- source ownership/lifetime must remain valid while spans are used;
- streaming backends may need an adapter rather than exposing arbitrary slices directly.
