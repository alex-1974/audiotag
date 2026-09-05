/++
Canonical mapping for ID3v2.4 private (`PRIV`) frames.

Each decoded PRIV frame becomes one repeatable canonical `privateData`
field.

The opaque private payload is represented as owned `MetadataBinary`.
When ID3 byte unsynchronisation was effective, physical stuffing bytes
are removed before the canonical value is created.

The PRIV owner identifier is retained as the canonical field qualifier
`owner`.

Transformation-pending native outcomes remain valid metadata and return
`requiresTransformation`.
+/
module audiotag.id3v2.v24.canonical_private;

import std.sumtype :
    match;

import audiotag.id3v2.v24.canonical_mapping :
    Id3v24CanonicalMappingResult,
    Id3v24CanonicalMappingStatus;

import audiotag.id3v2.v24.logical_bytes :
    copyId3v24LogicalBytes;

import audiotag.id3v2.v24.native_frame :
    Id3v24NativeFrame;

import audiotag.id3v2.v24.private_frame :
    Id3v24PrivateFrame,
    Id3v24PrivateOutcome;

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
Maps one decoded ID3v2.4 PRIV frame to canonical private data.

Params:
    frame = Decoded PRIV frame.
    sourceLength = Complete physical frame length when known. Zero
        represents point provenance only.

Returns:
    Canonical private-data mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24PrivateFrameToCanonical(
    Id3v24PrivateFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    auto logical =
        copyId3v24LogicalBytes(
            frame.rawPrivateData,
            frame.effectiveUnsynchronisation
        );

    auto field =
        MetadataField(
            MetadataKey("privateData"),
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

    assertRegisteredShape(field);

    return
        Id3v24CanonicalMappingResult.success(
            field
        );
}


/++
Maps one unified native ID3v2.4 frame through the PRIV canonical mapper.

Decoded PRIV outcomes are mapped. Compressed or encrypted PRIV outcomes
remain valid native metadata and return `requiresTransformation`.

Other native frame families remain unsupported by this mapper.

Params:
    native = Unified native ID3v2.4 frame.

Returns:
    Canonical private-data mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24NativePrivateFrameToCanonical(
    Id3v24NativeFrame native
)
    @safe
{
    return native.content.match!(
        (Id3v24PrivateOutcome outcome) =>
            outcome.decoded
                ? mapId3v24PrivateFrameToCanonical(
                    outcome.privateFrame,
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
Constructs exact provenance for one mapped PRIV frame.
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
            "PRIV"
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


/// PRIV preserves opaque binary content and owner context.
unittest
{
    import audiotag.core.span :
        ByteSpan;

    const ubyte[] bytes =
        [0x11, 0x22, 0x33];

    Id3v24PrivateFrame frame;

    frame.sourceOffset = 123;
    frame.ownerIdentifier =
        "example.invalid";
    frame.rawPrivateData =
        ByteSpan(
            bytes,
            500
        );

    auto result =
        mapId3v24PrivateFrameToCanonical(
            frame
        );

    assert(result.mapped);

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
                    [0x11, 0x22, 0x33],

            _ => false
        );

    assert(matches);
}


/// Physical unsynchronisation bytes never enter canonical PRIV data.
unittest
{
    import audiotag.core.span :
        ByteSpan;

    const ubyte[] physical =
        [
            0x11,
            0xFF, 0x00, 0xE1,
            0x22,
            0xFF, 0x00, 0x00,
            0x33
        ];

    Id3v24PrivateFrame frame;

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
        mapId3v24PrivateFrameToCanonical(
            frame
        );

    assert(result.mapped);

    const matches =
        result.field.value.match!(
            (MetadataBinary binary) =>
                binary.data ==
                    [
                        0x11,
                        0xFF, 0xE1,
                        0x22,
                        0xFF, 0x00,
                        0x33
                    ],

            _ => false
        );

    assert(matches);
}


/// Native PRIV mapping preserves the complete physical frame extent.
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
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            'o', 'w', 'n', 'e', 'r',
            0x00,
            0x11, 0x22, 0x33
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
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
        mapId3v24NativePrivateFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);

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
                    [0x11, 0x22, 0x33],

            _ => false
        );

    assert(matches);
}


/// Empty private data remains a valid empty canonical binary value.
unittest
{
    import audiotag.core.span :
        ByteSpan;

    const ubyte[] bytes = [];

    Id3v24PrivateFrame frame;

    frame.ownerIdentifier =
        "owner";

    frame.rawPrivateData =
        ByteSpan(
            bytes,
            1000
        );

    auto result =
        mapId3v24PrivateFrameToCanonical(
            frame
        );

    assert(result.mapped);

    const matches =
        result.field.value.match!(
            (MetadataBinary binary) =>
                binary.data.length == 0,

            _ => false
        );

    assert(matches);
}


/// Transformation-pending PRIV remains valid native metadata.
unittest
{
    import audiotag.id3v2.v24.frame :
        Id3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrameContent;

    import audiotag.id3v2.v24.private_frame :
        Id3v24PrivateAvailability;

    Id3v24PrivateOutcome outcome;

    outcome.availability =
        Id3v24PrivateAvailability
            .requiresDecompression;

    Id3v24NativeFrameContent content =
        outcome;

    auto native =
        Id3v24NativeFrame(
            Id3v24FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v24NativePrivateFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .requiresTransformation
    );
}


/// Other native frame families remain unsupported by the PRIV mapper.
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
        mapId3v24NativePrivateFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .unsupportedFrame
    );
}
