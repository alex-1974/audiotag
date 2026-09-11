/++
Shared canonical-mapping outcome types for all ID3v2 revisions.

Canonical mapping happens after structural parsing and native semantic
decoding. Mapping outcomes are therefore not parse failures:

- mapped native semantics produce a canonical metadata field;
- unsupported native semantics remain preserved natively;
- transformation requirements remain explicit;
- valid native value shapes that cannot be represented losslessly remain
  explicit.

These states are revision-independent. Revision-specific mapping modules retain
their existing public type names as aliases to the types defined here.
+/
module audiotag.id3v2.common.canonical_mapping;

import audiotag.metadata.field :
    MetadataField;


/++
Outcome of attempting to map one native ID3v2 semantic value to one canonical
metadata field.
+/
enum Id3v2CanonicalMappingStatus : ubyte
{
    /// A canonical field was produced.
    mapped,

    /// This native identifier/content has no mapping in the current mapper.
    unsupportedFrame,

    /// Semantic content requires a transformation that is not available.
    requiresTransformation,

    /// The native value is valid but cannot currently be represented
    /// losslessly by the canonical field model.
    unrepresentableValueShape
}


/++
Result of mapping one native ID3v2 semantic value to canonical metadata.

This type deliberately contains no `ParseError`. Malformed external bytes are
rejected by structural or semantic codec layers before canonical mapping is
attempted.
+/
struct Id3v2CanonicalMappingResult
{
    /// Mapping outcome.
    Id3v2CanonicalMappingStatus status;

    /// Canonical field when `status == mapped`.
    MetadataField field;


    /// Whether a canonical field was produced.
    @property
    bool mapped() const
        @safe pure nothrow @nogc
    {
        return
            status ==
            Id3v2CanonicalMappingStatus.mapped;
    }


    /// Constructs a successful mapping result.
    static Id3v2CanonicalMappingResult success(
        MetadataField field
    )
        @safe
    {
        return
            Id3v2CanonicalMappingResult(
                Id3v2CanonicalMappingStatus.mapped,
                field
            );
    }


    /// Constructs an unsupported-native-semantics result.
    static Id3v2CanonicalMappingResult unsupported()
        @safe pure nothrow @nogc
    {
        return
            Id3v2CanonicalMappingResult(
                Id3v2CanonicalMappingStatus.unsupportedFrame,
                MetadataField.init
            );
    }


    /// Constructs an unavailable-transformation result.
    static Id3v2CanonicalMappingResult transformationRequired()
        @safe pure nothrow @nogc
    {
        return
            Id3v2CanonicalMappingResult(
                Id3v2CanonicalMappingStatus.requiresTransformation,
                MetadataField.init
            );
    }


    /// Constructs a lossless-representation-limitation result.
    static Id3v2CanonicalMappingResult unrepresentable()
        @safe pure nothrow @nogc
    {
        return
            Id3v2CanonicalMappingResult(
                Id3v2CanonicalMappingStatus
                    .unrepresentableValueShape,
                MetadataField.init
            );
    }
}


version (unittest)
{
    import std.sumtype :
        match;

    import audiotag.metadata.field :
        MetadataKey;

    import audiotag.metadata.value :
        MetadataText,
        MetadataValue;
}


/// Successful results expose their canonical field.
unittest
{
    MetadataValue value =
        MetadataText(
            "Example"
        );

    auto field =
        MetadataField(
            MetadataKey(
                "title"
            ),
            value
        );

    const result =
        Id3v2CanonicalMappingResult.success(
            field
        );

    assert(result.mapped);

    assert(
        result.status ==
        Id3v2CanonicalMappingStatus.mapped
    );

    assert(
        result.field.key.name ==
        "title"
    );

    const matches =
        result.field.value.match!(
            (MetadataText text) =>
                text.value ==
                "Example",

            _ =>
                false
        );

    assert(matches);
}


/// Unsupported content remains a successful mapping-level outcome.
unittest
{
    const result =
        Id3v2CanonicalMappingResult
            .unsupported();

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v2CanonicalMappingStatus
            .unsupportedFrame
    );
}


/// Transformation requirements remain distinct from unsupported content.
unittest
{
    const result =
        Id3v2CanonicalMappingResult
            .transformationRequired();

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v2CanonicalMappingStatus
            .requiresTransformation
    );
}


/// Lossless-representation limitations remain explicit.
unittest
{
    const result =
        Id3v2CanonicalMappingResult
            .unrepresentable();

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v2CanonicalMappingStatus
            .unrepresentableValueShape
    );
}
