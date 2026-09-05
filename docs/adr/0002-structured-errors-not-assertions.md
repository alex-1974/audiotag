# ADR 0002: Structured parse errors instead of assertions for malformed input

## Status

Accepted.

## Context

The library is expected to parse real-world tags that often violate specifications.

Assertions and design-by-contract are appropriate for programmer invariants but not for attacker-controlled or malformed file data.

The byte core should also remain allocation-light and suitable for `@nogc` operation where practical.

## Decision

Malformed external input is represented through structured parse errors and higher-level diagnostics.

Low-level errors contain compact data such as:

```text
code
offset
requested
available
```

Higher parser layers may convert them into human-readable diagnostics.

Assertions/contracts are reserved for internal invariants that indicate a bug in audiotag itself.

## Consequences

- tolerant parsing can be explicit and testable;
- malformed input does not masquerade as a programming error;
- low-level code can remain allocation-free;
- callers can distinguish fatal, recoverable and informational conditions;
- error handling requires deliberate propagation rather than relying on exceptions/assertions.
