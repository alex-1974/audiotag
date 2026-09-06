/++
Canonical mapping for ID3v2.3 private (`PRIV`) frames.

Each decoded PRIV frame becomes one repeatable canonical `privateData`
field.

The opaque private payload is represented as owned `MetadataBinary`.
When ID3v2.3 whole-tag unsynchronisation was effective, physical
stuffing bytes are removed before the canonical value is created.

The PRIV owner identifier is retained as the canonical field qualifier
`owner`.

Transformation-pending native outcomes remain valid metadata and return
`requiresTransformation`.
+/
module audiotag.id3v2.v23.canonical_private;

import std.sumtype :
    match;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.canonical_mapping :
    Id3v23CanonicalMappingResult,
    Id3v23CanonicalMappingStatus;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.native_frame :
    Id3v23NativeFrame;

import audiotag.id3v2.v23.private_frame :
    Id3v23PrivateFrame,
    Id3v23PrivateOutcome;

import audiotag.metadata.field :
    MetadataField,
    MetadataKey,
    MetadataQualifier;

import audiotag.metadata.provenance :
    MetadataConfidence,
    MetadataProvenance,
    MetadataSystem,
    NativeMetadataIdentifier;

import audiotag.metadata.registry :
    findMetadataFieldDefinition;

import audiotag.metadata.value :
    MetadataBinary,
    MetadataValue;


/++
Maps one decoded ID3v2.3 PRIV frame to canonical private data.

Params:
    frame = Decoded PRIV frame.
    sourceLength = Complete physical frame length when known. Zero
        represents point provenance only.

Returns:
    Canonical private-data mapping result.
+/
Id3v23CanonicalMappingResult
mapId3v23PrivateFrameToCanonical(
    Id3v23PrivateFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    auto logical =
        copyPrivateLogicalBytes(
            frame.rawPrivateData,
            frame.effectiveUnsynchronisation
        );


    auto field =
        MetadataField(
            MetadataKey(
                "privateData"
            ),
            MetadataValue(
                MetadataBinary.copyFrom(
                    logical
                )
            ),
            [
                makeProvenance(
                    frame.sourceOffset,
                    sourceLength
                )
            ]
        );


    field.qualifiers =
        [
            MetadataQualifier(
                "owner",
                frame.ownerIdentifier
            )
        ];


    assertRegisteredShape(
        field
    );


    return
        Id3v23CanonicalMappingResult
            .success(
                field
            );
}


/++
Maps one unified native ID3v2.3 frame through the PRIV canonical mapper.

Decoded PRIV outcomes are mapped. Compressed or encrypted PRIV outcomes
remain valid native metadata and return `requiresTransformation`.

Other native frame families remain unsupported by this mapper.

Params:
    native = Unified native ID3v2.3 frame.

Returns:
    Canonical private-data mapping result.
+/
Id3v23CanonicalMappingResult
mapId3v23NativePrivateFrameToCanonical(
    Id3v23NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v23PrivateOutcome outcome) =>
                outcome.decoded
                    ? mapId3v23PrivateFrameToCanonical(
                        outcome.privateFrame,
                        native.sourceLength
                    )
                    : Id3v23CanonicalMappingResult
                        .transformationRequired(),

            _ =>
                Id3v23CanonicalMappingResult
                    .unsupported()
        );
}


/++
Copies the logical private payload into owned temporary storage.

`rawPrivateData` deliberately retains the physical ID3v2.3 source
representation. When whole-tag unsynchronisation was effective,
`Id3v23DataCursor` removes inserted stuffing bytes while traversing the
already bounded span.

A read failure while the cursor reports non-empty would violate the
cursor primitive's internal invariant rather than represent malformed
PRIV input reaching this mapping layer.
+/
private ubyte[] copyPrivateLogicalBytes(
    ByteSpan raw,
    bool unsynchronised
)
    @safe
{
    auto cursor =
        Id3v23DataCursor(
            raw,
            unsynchronised
        );


    ubyte[] logical;


    logical.reserve(
        raw.length
    );


    while (
        !cursor.empty
    )
    {
        auto byteResult =
            cursor.takeByte();


        assert(
            byteResult.hasValue
        );


        logical ~=
            byteResult.value.value;
    }


    return logical;
}


/++
Constructs exact provenance for one mapped PRIV frame.
+/
private MetadataProvenance makeProvenance(
    size_t sourceOffset,
    size_t sourceLength
)
    @safe pure nothrow @nogc
{
    return
        MetadataProvenance(
            NativeMetadataIdentifier(
                MetadataSystem.id3v2,
                "PRIV"
            ),
            sourceOffset,
            sourceLength,
            MetadataConfidence.exact
        );
}


/++
Checks the canonical mapper/registry contract as a programmer invariant.
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

    import audiotag.id3v2.v23.frame :
        Id3v23FrameEnvelope,
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrameContent,
        Id3v23UnknownFrame,
        decodeId3v23NativeFrame;

    import audiotag.id3v2.v23.private_frame :
        Id3v23PrivateAvailability;
}


/// PRIV preserves opaque binary content and owner context.
unittest
{
    const ubyte[] bytes =
        [
            0x11,
            0x22,
            0x33
        ];


    Id3v23PrivateFrame frame;


    frame.sourceOffset =
        123;


    frame.ownerIdentifier =
        "example.invalid";


    frame.rawPrivateData =
        ByteSpan(
            bytes,
            500
        );


    auto result =
        mapId3v23PrivateFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
        result.field.key.name ==
        "privateData"
    );


    assert(
        result.field.qualifiers.length ==
        1
    );


    assert(
        result.field.qualifiers[0].name ==
        "owner"
    );


    assert(
        result.field.qualifiers[0].value ==
        "example.invalid"
    );


    assert(
        result.field.provenance.length ==
        1
    );


    assert(
        result.field.provenance[0]
            .native.identifier ==
        "PRIV"
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
            (MetadataBinary binary) =>
                binary.data ==
                    [
                        0x11,
                        0x22,
                        0x33
                    ],

            _ =>
                false
        );


    assert(
        matches
    );
}


/// Empty owner identifiers remain explicit owner qualifiers.
unittest
{
    const ubyte[] bytes =
        [
            0xAA
        ];


    Id3v23PrivateFrame frame;


    frame.rawPrivateData =
        ByteSpan(
            bytes,
            600
        );


    auto result =
        mapId3v23PrivateFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
        result.field.qualifiers.length ==
        1
    );


    assert(
        result.field.qualifiers[0].name ==
        "owner"
    );


    assert(
        result.field.qualifiers[0].value.length ==
        0
    );
}


/// Physical unsynchronisation bytes never enter canonical PRIV data.
unittest
{
    const ubyte[] physical =
        [
            0x11,

            0xFF,
            0x00,
            0xE1,

            0x22,

            /*
             * Logical FF 00.
             */
            0xFF,
            0x00,
            0x00,

            0x33
        ];


    Id3v23PrivateFrame frame;


    frame.ownerIdentifier =
        "owner";


    frame.rawPrivateData =
        ByteSpan(
            physical,
            700
        );


    frame.effectiveUnsynchronisation =
        true;


    auto result =
        mapId3v23PrivateFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    const matches =
        result.field.value.match!(
            (MetadataBinary binary) =>
                binary.data ==
                    [
                        0x11,
                        0xFF,
                        0xE1,
                        0x22,
                        0xFF,
                        0x00,
                        0x33
                    ],

            _ =>
                false
        );


    assert(
        matches
    );
}


/// Native PRIV mapping preserves the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            'o', 'w', 'n', 'e', 'r',
            0x00,

            0x11,
            0x22,
            0x33
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );


    auto envelope =
        cursor.parseId3v23FrameEnvelope();


    assert(
        envelope.hasValue
    );


    assert(
        cursor.empty
    );


    auto native =
        decodeId3v23NativeFrame(
            envelope.value
        );


    assert(
        native.hasValue
    );


    auto mapped =
        mapId3v23NativePrivateFrameToCanonical(
            native.value
        );


    assert(
        mapped.mapped
    );


    assert(
        mapped.field.key.name ==
        "privateData"
    );


    assert(
        mapped.field.qualifiers[0].name ==
        "owner"
    );


    assert(
        mapped.field.qualifiers[0].value ==
        "owner"
    );


    assert(
        mapped.field.provenance[0]
            .sourceOffset ==
        900
    );


    assert(
        mapped.field.provenance[0]
            .sourceLength ==
        bytes.length
    );


    const matches =
        mapped.field.value.match!(
            (MetadataBinary binary) =>
                binary.data ==
                    [
                        0x11,
                        0x22,
                        0x33
                    ],

            _ =>
                false
        );


    assert(
        matches
    );
}


/// Whole-tag-unsynchronised native PRIV keeps physical provenance but canonical logical bytes.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',

            /*
             * Five logical frame-data bytes:
             *
             * owner: x 00
             * data:  FF E0 FF
             *
             * Physical data contains one stuffing zero.
             */
            0x00, 0x00, 0x00, 0x05,

            0x00, 0x00,

            'x',
            0x00,

            0xFF,
            0x00,
            0xE0,
            0xFF
        ];


    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1100
            ),
            true
        );


    auto envelope =
        cursor.parseId3v23FrameEnvelope();


    assert(
        envelope.hasValue
    );


    assert(
        cursor.empty
    );


    auto native =
        decodeId3v23NativeFrame(
            envelope.value,
            true
        );


    assert(
        native.hasValue
    );


    assert(
        native.value.sourceLength ==
        bytes.length
    );


    auto mapped =
        mapId3v23NativePrivateFrameToCanonical(
            native.value
        );


    assert(
        mapped.mapped
    );


    assert(
        mapped.field.provenance[0]
            .sourceLength ==
        bytes.length
    );


    assert(
        mapped.field.value.match!(
            (MetadataBinary binary) =>
                binary.data ==
                    [
                        0xFF,
                        0xE0,
                        0xFF
                    ],

            _ =>
                false
        )
    );
}


/// Empty private data remains a valid empty canonical binary value.
unittest
{
    const ubyte[] bytes = [];


    Id3v23PrivateFrame frame;


    frame.ownerIdentifier =
        "owner";


    frame.rawPrivateData =
        ByteSpan(
            bytes,
            1200
        );


    auto result =
        mapId3v23PrivateFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
        result.field.value.match!(
            (MetadataBinary binary) =>
                binary.data.length ==
                0,

            _ =>
                false
        )
    );
}


/// Transformation-pending PRIV remains valid native metadata.
unittest
{
    Id3v23PrivateOutcome outcome;


    outcome.availability =
        Id3v23PrivateAvailability
            .requiresDecompression;


    Id3v23NativeFrameContent content =
        outcome;


    auto native =
        Id3v23NativeFrame(
            Id3v23FrameEnvelope.init,
            content
        );


    auto result =
        mapId3v23NativePrivateFrameToCanonical(
            native
        );


    assert(
        !result.mapped
    );


    assert(
        result.status ==
        Id3v23CanonicalMappingStatus
            .requiresTransformation
    );
}


/// Other native frame families remain unsupported by the PRIV mapper.
unittest
{
    Id3v23NativeFrameContent content =
        Id3v23UnknownFrame();


    auto native =
        Id3v23NativeFrame(
            Id3v23FrameEnvelope.init,
            content
        );


    auto result =
        mapId3v23NativePrivateFrameToCanonical(
            native
        );


    assert(
        !result.mapped
    );


    assert(
        result.status ==
        Id3v23CanonicalMappingStatus
            .unsupportedFrame
    );
}
