# Contributing to audiotag

## Principles

`audiotag` parses untrusted binary input. Correctness, bounds discipline, reproducibility and debuggability take priority over clever code.

## D style

Preferred defaults:

- use `const(ubyte)[]` for parser input;
- use `immutable` for truly immutable static data;
- prefer `struct` for parser state and data values;
- keep the parser core `@safe`;
- isolate unavoidable unsafe code in the smallest possible reviewed `@trusted` wrapper;
- use `@nogc nothrow` for byte primitives where this remains natural;
- allow the GC in higher semantic layers unless profiling demonstrates a problem;
- use `auto` for obvious local types;
- keep public API return types explicit;
- use UFCS where it improves readability;
- use CTFE for static registries and generated lookup tables;
- prefer `std.sumtype.SumType` to deep class hierarchies for heterogeneous values;
- avoid `assumeSafeAppend` unless profiling proves a need and safety is encapsulated.

The parser code should read like a description of the binary format.

## Bounds rule

Every nested parser receives a bounded span.

It must never read outside the span assigned by its parent parser.

## External errors versus program bugs

Do not use `assert` or contracts to reject malformed file data.

Use assertions only for internal invariants.

Malformed external input must produce structured parse errors and/or diagnostics.

## Cursor-state rule

Failed atomic operations must not partially consume input.

For example, failed `takeBytes(n)` must leave the cursor unchanged.

## Unknown data

Do not discard unknown but structurally valid data unless an explicit conversion/write policy permits it.

Unknown is not the same as corrupt.

## Documentation

Every public module should have modern Ddoc module documentation.

The module-level Ddoc block belongs immediately before the `module`
declaration and must carry project metadata. Use the following baseline:

```d
/++
<module purpose, scope and important invariants>

Standards:
    <standard/version and authoritative specification URL, when applicable>

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    YYYY-MM-DD
+/
module ...;
```

`Authors`, `Copyright`, `License` and `Date` are required for public modules.
`Standards` is required when a module implements or interprets an external
format specification; omit it only when no external standard applies.

For standard-bound revision modules, identify the exact supported revision
rather than a broader family name. For example, ID3v2.2 modules currently use:

```text
Standards:
    ID3v2.2.0, https://id3.org/id3v2-00
```

The `Date` field records the date on which the module documentation contract
was introduced or materially revised. Do not churn it for unrelated internal
code edits.

When a change introduces a new public module, its complete module Ddoc and
metadata are part of the same change. Phase-closing or broad documentation
audits should verify this mechanically where practical.

Every public type/function should document relevant:

- purpose;
- parameters;
- return value;
- error semantics;
- safety/bounds behavior;
- complexity when non-obvious.

Use documented `unittest` blocks for public examples where practical so examples compile as tests.

## Unit tests

Every new function requires unit tests appropriate to its semantics.

Typical parser primitive coverage includes:

- normal case;
- empty input;
- exact boundary;
- one byte below/above boundary;
- zero-length request;
- offset preservation;
- nested spans;
- failed-operation state preservation.

Pattern search additionally requires:

- match at start/middle/end;
- no match;
- multiple matches;
- overlapping patterns;
- pattern longer than input;
- maximum-search limit;
- aligned searches.

## Parser tests

Parser changes require tests for both valid and malformed structures.

Malformed tests should verify, where relevant:

- error/diagnostic code;
- exact source offset;
- parser synchronization after recovery;
- whether later valid structures remain visible;
- raw-byte preservation;
- confidence/recovery status.

## Regression rule

Every fixed parser bug should receive a permanent regression test before or together with the fix.

## Test files

Do not commit commercial/copyrighted music files merely because they are convenient local samples.

Prefer:

- synthetic byte sequences embedded in tests;
- generated fixtures;
- redistributable/public-domain samples;
- minimal binary fixtures created specifically for the test.

The local `music/` directory is intentionally Git-ignored.

## Build and test

Before committing:

```bash
dub build
dub test
git diff --check
git status
```

When LDC CI is added, changes should also pass the supported LDC compiler.

## Git workflow

Use `main` as the primary branch.

Prefer short-lived topic branches when useful.

Make small, semantically coherent commits.

Recommended commit prefixes include:

```text
core:
id3:
flac:
ogg:
mp4:
ape:
fix:
test:
docs:
build:
refactor:
chore:
```

Examples:

```text
core: implement exact takeBytes
id3: parse v2.4 frame header
fix: preserve cursor on truncated read
test: add malformed UTF-16 terminator regression
docs: document recovery confidence
```

Do not mix unrelated cleanup into a functional parser commit.

## Changelog

Update `CHANGELOG.md` for user-relevant behavior changes.

Minor internal refactors do not need individual changelog entries unless they materially change API or parser behavior.

## Architecture decisions

Significant irreversible or cross-cutting decisions should be recorded under `docs/adr/`.
