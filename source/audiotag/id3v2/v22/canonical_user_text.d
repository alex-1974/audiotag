/++
Canonical mapping for ID3v2.2 user-defined text (`TXX`) frames.

Each decoded `TXX` frame becomes one repeatable canonical `userText` field:

- the native text value becomes `MetadataText`;
- the user-defined description becomes canonical field description;
- exact native frame provenance is retained.

The description is deliberately not promoted to a `MetadataKey`. User-defined
labels belong to field context rather than to the global canonical registry.

ID3v2.2-specific character decoding, including independent UCS-2 byte-order
handling for description and value, is completed by the native codec before
this mapping layer is reached.

ID3v2.2 has no per-frame compression/encryption state, so decoded `TXX`
semantics map directly without a transformation-availability outcome.
+/
module audiotag.id3v2.v22.canonical_user_text;

import std.sumtype :
    match;

import audiotag.id3v2.v22.canonical_mapping :
    Id3v22CanonicalMappingResult,
    Id3v22CanonicalMappingStatus;

import audiotag.id3v2.v22.native_frame :
    Id3v22NativeFrame;

import audiotag.id3v2.v22.user_text :
    Id3v22UserTextFrame;

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
Maps one decoded ID3v2.2 `TXX` frame to canonical `userText`.

Params:
    frame = Decoded user-defined text frame.
    sourceLength = Complete physical frame length when known. Zero represents
        point provenance only.

Returns:
    Canonical user-text mapping result.
+/
Id3v22CanonicalMappingResult
mapId3v22UserTextFrameToCanonical(
    Id3v22UserTextFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    auto field =
        MetadataField(
            MetadataKey(
                "userText"
            ),
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


    assertRegisteredShape(
        field
    );


    return
        Id3v22CanonicalMappingResult
            .success(
                field
            );
}


/++
Maps one unified native ID3v2.2 frame through the `TXX` canonical mapper.

Only decoded `Id3v22UserTextFrame` alternatives are mapped. Other native frame
families remain valid native metadata and return `unsupportedFrame`.

The complete native frame supplies the exact physical frame extent for
canonical provenance.
+/
Id3v22CanonicalMappingResult
mapId3v22NativeUserTextFrameToCanonical(
    Id3v22NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v22UserTextFrame frame) =>
                mapId3v22UserTextFrameToCanonical(
                    frame,
                    native.sourceLength
                ),

            _ =>
                Id3v22CanonicalMappingResult
                    .unsupported()
        );
}


/++
Constructs exact provenance for one mapped `TXX` frame.
+/
private MetadataProvenance
makeProvenance(
    size_t sourceOffset,
    size_t sourceLength
)
    @safe pure nothrow @nogc
{
    return
        MetadataProvenance(
            NativeMetadataIdentifier(
                MetadataSystem.id3v2,
                "TXX"
            ),
            sourceOffset,
            sourceLength,
            MetadataConfidence.exact
        );
}


/++
Checks the mapper/registry contract as a programmer invariant.
+/
private void
assertRegisteredShape(
    MetadataField field
)
    @safe
{
    const definition =
        findMetadataFieldDefinition(
            field.key
        );


    assert(
        definition.found
    );


    assert(
        definition.definition
            .accepts(
                field.value
            )
    );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.frame :
        parseId3v22FrameEnvelope;

    import audiotag.id3v2.v22.native_frame :
        Id3v22NativeFrameContent,
        Id3v22UnknownFrame,
        decodeId3v22NativeFrame;
}


/// TXX preserves scalar value and user-defined description.
unittest
{
    Id3v22UserTextFrame frame;

    frame.sourceOffset =
        123;

    frame.description =
        "MusicBrainz Album Id";

    frame.value =
        "abc-123";


    auto result =
        mapId3v22UserTextFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


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
        "TXX"
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

            _ =>
                false
        );


    assert(matches);
}


/// Empty TXX descriptions remain unspecified canonical description context.
unittest
{
    Id3v22UserTextFrame frame;

    frame.value =
        "value";


    auto result =
        mapId3v22UserTextFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
        !result.field.hasDescription
    );


    const matches =
        result.field.value.match!(
            (MetadataText text) =>
                text.value ==
                "value",

            _ =>
                false
        );


    assert(matches);
}


/// Empty TXX values remain explicit scalar canonical text.
unittest
{
    Id3v22UserTextFrame frame;

    frame.description =
        "kind";


    auto result =
        mapId3v22UserTextFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
        result.field.description ==
        "kind"
    );


    assert(
        result.field.value.match!(
            (MetadataText text) =>
                text.value.length ==
                0,

            _ =>
                false
        )
    );
}


/// Native TXX mapping records the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',

            /*
             * Encoding + "kind" + terminator + "abc".
             */
            0x00, 0x00, 0x09,

            0x00,
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
        cursor.parseId3v22FrameEnvelope();


    assert(
        envelope.hasValue
    );


    assert(
        cursor.empty
    );


    auto native =
        decodeId3v22NativeFrame(
            envelope.value
        );


    assert(
        native.hasValue
    );


    auto mapped =
        mapId3v22NativeUserTextFrameToCanonical(
            native.value
        );


    assert(
        mapped.mapped
    );


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
                text.value ==
                "abc",

            _ =>
                false
        );


    assert(matches);
}


/// Other native frame families remain unsupported by this mapper.
unittest
{
    Id3v22NativeFrameContent content =
        Id3v22UnknownFrame();


    auto native =
        Id3v22NativeFrame(
            typeof(Id3v22NativeFrame.init.envelope).init,
            content
        );


    auto result =
        mapId3v22NativeUserTextFrameToCanonical(
            native
        );


    assert(
        !result.mapped
    );


    assert(
        result.status ==
        Id3v22CanonicalMappingStatus
            .unsupportedFrame
    );
}
