/++
Canonical mapping for ID3v2.4 user-defined text (`TXXX`) frames.

Each decoded `TXXX` frame becomes one repeatable canonical `userText`
field:

- the native text value becomes `MetadataText`;
- the user-defined description becomes canonical field description;
- exact native frame provenance is retained.

The description is deliberately not promoted to a `MetadataKey`.
User-defined labels belong to field context rather than to the global
canonical field registry.

Transformation-pending native outcomes remain valid metadata and return
`requiresTransformation`.
+/
module audiotag.id3v2.v24.canonical_user_text;

import std.sumtype :
    match;

import audiotag.id3v2.v24.canonical_mapping :
    Id3v24CanonicalMappingResult,
    Id3v24CanonicalMappingStatus;

import audiotag.id3v2.v24.native_frame :
    Id3v24NativeFrame;

import audiotag.id3v2.v24.user_text :
    Id3v24UserTextFrame,
    Id3v24UserTextOutcome;

import audiotag.metadata.field :
    MetadataField,
    MetadataKey;

import audiotag.metadata.provenance :
    MetadataConfidence,
    MetadataProvenance,
    MetadataSystem,
    NativeMetadataIdentifier;

import audiotag.metadata.registry :
    findMetadataFieldDefinition;

import audiotag.metadata.value :
    MetadataText,
    MetadataValue;


/++
Maps one decoded ID3v2.4 `TXXX` frame to canonical `userText`.

Params:
    frame = Decoded user-defined text frame.
    sourceLength = Complete physical frame length when known. Zero
        represents point provenance only.

Returns:
    Canonical user-text mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24UserTextFrameToCanonical(
    Id3v24UserTextFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    auto field =
        MetadataField(
            MetadataKey("userText"),
            MetadataValue(
                MetadataText(
                    frame.value
                )
            ),
            [
                makeProvenance(
                    frame.sourceOffset,
                    sourceLength
                )
            ]
        );

    field.description =
        frame.description;

    assertRegisteredShape(field);

    return
        Id3v24CanonicalMappingResult.success(
            field
        );
}


/++
Maps one unified native ID3v2.4 frame through the TXXX canonical mapper.

Decoded TXXX outcomes are mapped. Compressed or encrypted outcomes
remain valid native metadata and return `requiresTransformation`.
Other native frame families are unsupported by this mapper.

Params:
    native = Unified native ID3v2.4 frame.

Returns:
    Canonical user-text mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24NativeUserTextFrameToCanonical(
    Id3v24NativeFrame native
)
    @safe
{
    return native.content.match!(
        (Id3v24UserTextOutcome outcome) =>
            outcome.decoded
                ? mapId3v24UserTextFrameToCanonical(
                    outcome.text,
                    native.sourceLength
                )
                : Id3v24CanonicalMappingResult
                    .transformationRequired(),

        _ =>
            Id3v24CanonicalMappingResult
                .unsupported()
    );
}


/++
Constructs exact provenance for one mapped TXXX frame.
+/
private MetadataProvenance makeProvenance(
    size_t sourceOffset,
    size_t sourceLength
)
    @safe pure nothrow @nogc
{
    return MetadataProvenance(
        NativeMetadataIdentifier(
            MetadataSystem.id3v2,
            "TXXX"
        ),
        sourceOffset,
        sourceLength,
        MetadataConfidence.exact
    );
}


/++
Checks the mapper/registry contract as a programmer invariant.
+/
private void assertRegisteredShape(
    MetadataField field
)
    @safe
{
    auto definition =
        findMetadataFieldDefinition(
            field.key
        );

    assert(definition.found);

    assert(
        definition.definition.accepts(
            field.value
        )
    );
}


/// TXXX preserves scalar value and user-defined description.
unittest
{
    Id3v24UserTextFrame frame;

    frame.sourceOffset = 123;
    frame.description =
        "MusicBrainz Album Id";
    frame.value =
        "abc-123";

    auto result =
        mapId3v24UserTextFrameToCanonical(
            frame
        );

    assert(result.mapped);

    assert(
        result.field.key.name ==
        "userText"
    );

    assert(
        result.field.hasDescription
    );

    assert(
        result.field.description ==
        "MusicBrainz Album Id"
    );

    assert(
        result.field.provenance.length ==
        1
    );

    assert(
        result.field.provenance[0]
            .native.identifier ==
        "TXXX"
    );

    assert(
        result.field.provenance[0]
            .sourceOffset ==
        123
    );

    assert(
        result.field.provenance[0]
            .sourceLength ==
        0
    );

    const matches =
        result.field.value.match!(
            (MetadataText text) =>
                text.value ==
                    "abc-123",

            _ => false
        );

    assert(matches);
}


/// Empty TXXX descriptions remain unspecified canonical description context.
unittest
{
    Id3v24UserTextFrame frame;

    frame.value =
        "value";

    auto result =
        mapId3v24UserTextFrameToCanonical(
            frame
        );

    assert(result.mapped);
    assert(!result.field.hasDescription);

    const matches =
        result.field.value.match!(
            (MetadataText text) =>
                text.value == "value",

            _ => false
        );

    assert(matches);
}


/// Native TXXX mapping records the complete physical frame extent.
unittest
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        decodeId3v24NativeFrame;

    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            0x03,
            'k', 'i', 'n', 'd',
            0x00,
            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    auto native =
        decodeId3v24NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v24NativeUserTextFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);

    assert(
        mapped.field.key.name ==
        "userText"
    );

    assert(
        mapped.field.description ==
        "kind"
    );

    assert(
        mapped.field.provenance[0]
            .sourceOffset ==
        700
    );

    assert(
        mapped.field.provenance[0]
            .sourceLength ==
        bytes.length
    );

    const matches =
        mapped.field.value.match!(
            (MetadataText text) =>
                text.value == "abc",

            _ => false
        );

    assert(matches);
}


/// Transformation-pending TXXX remains valid native metadata.
unittest
{
    import audiotag.id3v2.v24.frame :
        Id3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrameContent;

    import audiotag.id3v2.v24.user_text :
        Id3v24UserTextAvailability;

    Id3v24UserTextOutcome outcome;

    outcome.availability =
        Id3v24UserTextAvailability
            .requiresDecompression;

    Id3v24NativeFrameContent content =
        outcome;

    auto native =
        Id3v24NativeFrame(
            Id3v24FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v24NativeUserTextFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .requiresTransformation
    );
}


/// Other native frame families remain unsupported by this mapper.
unittest
{
    import audiotag.id3v2.v24.frame :
        Id3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrameContent,
        Id3v24UnknownFrame;

    Id3v24NativeFrameContent content =
        Id3v24UnknownFrame();

    auto native =
        Id3v24NativeFrame(
            Id3v24FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v24NativeUserTextFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .unsupportedFrame
    );
}
