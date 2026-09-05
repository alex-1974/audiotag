# ADR 0004: Preserve native and unknown metadata

## Status

Accepted.

## Context

The library must support version conversion and safe roundtrips.

A purely normalized key/value model would lose:

- unknown fields;
- native frame identifiers;
- ordering;
- flags;
- encoding information;
- source offsets;
- proprietary extensions;
- partially recoverable regions.

That would make read/write conversion lossy even when the user did not request data removal.

## Decision

Canonical metadata values retain native provenance.

Unknown but structurally valid metadata should be preserved as bounded opaque/native nodes.

Corrupt regions may be preserved as raw diagnostic nodes where safe.

Writers must use an explicit conversion/preservation policy rather than silently dropping unrepresentable information.

## Consequences

- roundtrips can be significantly more faithful;
- debugging malformed files becomes easier;
- the public tree/model is richer than a simple dictionary;
- writer policy must explicitly handle information not representable in a target format.
