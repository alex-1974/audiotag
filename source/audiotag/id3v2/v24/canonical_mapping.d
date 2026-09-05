/++
Common result types for mapping native ID3v2.4 metadata to the
format-independent canonical metadata model.

Individual frame-family mappers retain their own semantic logic but
share these mapping outcome states.

A mapping result is distinct from a parse result:

- malformed native input is handled earlier by the parser/codec layer;
- transformation-pending native content remains valid native metadata;
- unsupported or currently unrepresentable native semantics are not
  parser failures.
+/
module audiotag.id3v2.v24.canonical_mapping;

import audiotag.metadata.field :
    MetadataField;


/++
Outcome of attempting to map one native ID3v2.4 semantic value to one
canonical metadata field.
+/
enum Id3v24CanonicalMappingStatus : ubyte
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
Result of mapping one native ID3v2.4 semantic value to canonical
metadata.

This result deliberately does not contain `ParseError`. Malformed
external bytes are rejected by the structural or semantic codec layer
before canonical mapping is attempted.
+/
struct Id3v24CanonicalMappingResult
{
    /// Mapping outcome.
    Id3v24CanonicalMappingStatus status;

    /// Canonical field when `status == mapped`.
    MetadataField field;

    /++
    Returns whether a canonical field was produced.
    +/
    @property
    bool mapped() const
        @safe pure nothrow @nogc
    {
        return
            status ==
            Id3v24CanonicalMappingStatus.mapped;
    }

    /++
    Constructs a successful mapping result.
    +/
    static Id3v24CanonicalMappingResult success(
        MetadataField field
    )
        @safe
    {
        return Id3v24CanonicalMappingResult(
            Id3v24CanonicalMappingStatus.mapped,
            field
        );
    }

    /++
    Constructs a result for native content unsupported by the current
    mapper.
    +/
    static Id3v24CanonicalMappingResult unsupported()
        @safe pure nothrow @nogc
    {
        return Id3v24CanonicalMappingResult(
            Id3v24CanonicalMappingStatus.unsupportedFrame,
            MetadataField.init
        );
    }

    /++
    Constructs a result for native content whose semantic decoding
    requires an unavailable transformation.
    +/
    static Id3v24CanonicalMappingResult transformationRequired()
        @safe pure nothrow @nogc
    {
        return Id3v24CanonicalMappingResult(
            Id3v24CanonicalMappingStatus.requiresTransformation,
            MetadataField.init
        );
    }

    /++
    Constructs a result for valid native semantics that cannot yet be
    represented losslessly by the canonical model.
    +/
    static Id3v24CanonicalMappingResult unrepresentable()
        @safe pure nothrow @nogc
    {
        return Id3v24CanonicalMappingResult(
            Id3v24CanonicalMappingStatus.unrepresentableValueShape,
            MetadataField.init
        );
    }
}


/// Successful mapping results expose their canonical field.
unittest
{
    import audiotag.metadata.field :
        MetadataKey;

    import audiotag.metadata.value :
        MetadataText,
        MetadataValue;

    MetadataValue value =
        MetadataText("Example");

    auto field =
        MetadataField(
            MetadataKey("title"),
            value
        );

    const result =
        Id3v24CanonicalMappingResult.success(
            field
        );

    assert(result.mapped);
    assert(
        result.status ==
        Id3v24CanonicalMappingStatus.mapped
    );
    assert(result.field.key.name == "title");
}


/// Unsupported native content remains a successful mapping-level outcome.
unittest
{
    const result =
        Id3v24CanonicalMappingResult.unsupported();

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus.unsupportedFrame
    );
}


/// Transformation requirements are distinct from unsupported content.
unittest
{
    const result =
        Id3v24CanonicalMappingResult
            .transformationRequired();

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .requiresTransformation
    );
}


/// Lossless-representation limitations remain explicit.
unittest
{
    const result =
        Id3v24CanonicalMappingResult.unrepresentable();

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .unrepresentableValueShape
    );
}
