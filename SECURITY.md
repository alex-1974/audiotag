# Security

## Threat model

`audiotag` treats every input audio file as untrusted binary data.

A file may contain:

- truncated structures;
- inconsistent sizes;
- integer-overflow attempts;
- deliberately huge counts or lengths;
- malformed text encodings;
- recursive structures intended to exhaust resources;
- oversized embedded artwork;
- corrupt compressed metadata;
- false signatures intended to trigger recovery scanners.

## Core safety requirements

### Bounded parsing

Every nested parser must operate inside a bounded parent span.

No parser may read beyond the region assigned by its parent structure.

### Validate before allocation

Lengths/counts derived from input must be validated against:

- remaining parent span;
- integer overflow;
- configured resource limits;

before allocation.

### Atomic cursor operations

A failed exact read must not partially advance parser state.

### Assertions

Do not use `assert` or contracts to reject malformed external bytes.

Assertions are reserved for programmer invariants.

### `@safe`

The parser core should remain `@safe`.

Any required `@trusted` code must:

- be minimal;
- document why it is safe;
- expose a safe abstraction to the rest of the library.

## Resource limits

The public parser should eventually expose configurable limits for at least:

- total metadata bytes;
- number of frames/nodes;
- string length;
- binary-value size;
- embedded artwork size;
- recursion depth;
- pattern-search distance;
- decompressed metadata size;
- number of Ogg streams/pages examined during recovery.

Reasonable defaults should prevent accidental or malicious resource exhaustion.

## Recovery scanners

Searching for a structural signature is not proof that the structure is valid.

Recovery candidates must be validated using the format's structural checks before they are accepted.

Recovered data should carry an explicit confidence/recovery status.

## Unknown data

Unknown metadata is not automatically malicious and should normally be preserved as opaque bounded data.

Malformed data must not be reinterpreted outside its validated bounds.

## Fuzzing

Fuzzing is a planned hardening requirement once the new parser core and first structural parsers are stable.

Every crash or state-corruption bug discovered by fuzzing should gain a permanent regression case.

## Security reports

A public vulnerability-reporting channel has not yet been established because the project is not yet released publicly.

Before the first public release, add:

- supported release policy;
- private reporting contact;
- disclosure process.
