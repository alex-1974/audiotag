# ADR 0006: Share ID3v2 cross-revision code at semantic boundaries

## Status

Accepted.

## Context

ID3v2.3 and ID3v2.4 differ in native framing, flags and serialization rules, but parts of their writer-planning logic operate on identical semantic concepts.

Initial implementations kept the two revisions separate. This made native differences explicit, but also produced substantial duplicated writer-planning code.

A dedicated refactoring spike compared the v2.3 and v2.4 implementations and tested several D compile-time abstraction mechanisms, including function templates, template structs and traits.

The spike showed that different kinds of duplication require different abstraction boundaries. Treating all similar code as generic would obscure real revision differences, while keeping semantically identical algorithms duplicated would increase maintenance cost and allow the implementations to diverge accidentally.

## Decision

ID3v2 cross-revision code sharing follows the semantic boundary of the abstraction.

Semantically identical concepts that are not revision-specific use ordinary shared types.

Identical algorithms operating on different concrete revision types use function templates.

Larger identical algorithms that require several related revision-specific types and functions may use traits as compile-time bindings. Traits configure the shared algorithm; they should not replace concrete revision-specific result types merely to reduce duplication.

Template structs may be used for structurally identical internal containers when sharing the structure itself provides sufficient benefit and revision-specific concrete type identity is not important.

Native representations, framing models and result types that express real ID3v2 revision differences remain concrete revision-specific types.

Metaprogramming must not hide actual format differences.

String mixins are not the default mechanism for cross-revision code sharing. Ordinary shared types, function templates and typed traits are preferred because they preserve navigation, diagnostics and readability.

The preferred hierarchy is therefore:

```text
shared semantic concept
    -> ordinary shared type

identical algorithm over revision-specific types
    -> function template

larger identical orchestration with related types/functions
    -> traits as compile-time binding

structurally identical internal container
    -> template struct when justified

actual revision-specific semantics or representation
    -> concrete revision-specific type
```

## Consequences

- common ID3v2 semantics have one implementation instead of parallel v2.3 and v2.4 implementations;
- real revision-specific framing and serialization rules remain explicit;
- function templates are preferred for sharing algorithms without changing concrete result-type identity;
- traits are available for compile-time dependency binding when a shared algorithm has several revision-specific collaborators;
- template structs may expose their instantiated type identity in compiler diagnostics and mangled names, so they require stronger justification than function templates;
- string mixins are avoided for ordinary deduplication;
- adding another ID3v2 revision should require explicit native bindings while allowing compatible semantic algorithms to be reused;
- abstraction decisions require semantic justification rather than similarity of source text alone;
- code should remain readable as an implementation of the metadata format rather than as an exercise in metaprogramming.
