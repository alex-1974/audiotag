/++
Canonical mapping for ID3v2.4 unique-file-identifier (`UFID`) frames.

Each decoded UFID frame becomes one repeatable canonical
`uniqueFileIdentifier` field.

The opaque identifier is represented as owned `MetadataBinary`.
When ID3 byte unsynchronisation was effective, physical stuffing bytes
are removed before the canonical value is created.

The UFID owner identifier is retained as canonical qualifier `owner`.

The native UFID codec is responsible for validating the specification
limit of at most 64 logical identifier bytes. This mapper consumes the
already-decoded semantic frame and does not reinterpret malformed input.

Transformation-pending native outcomes remain valid metadata and return
`requiresTransformation`.
+/
module audiotag.id3v2.v24.canonical_unique_file_identifier;

import std.sumtype :
    match;

import audiotag.id3v2.v24.canonical_mapping :
    Id3v24CanonicalMappingResult,
    Id3v24CanonicalMappingStatus;

import audiotag.id3v2.v24.logical_bytes :
    copyId3v24LogicalBytes;

import audiotag.id3v2.v24.native_frame :
    Id3v24NativeFrame;

import audiotag.id3v2.v24.unique_file_identifier :
    Id3v24UniqueFileIdentifierFrame,
    Id3v24UniqueFileIdentifierOutcome;

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
Maps one decoded ID3v2.4 UFID frame to canonical metadata.

Params:
    frame = Decoded UFID frame.
    sourceLength = Complete physical frame length when known. Zero
        represents point provenance only.

Returns:
    Canonical unique-file-identifier mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24UniqueFileIdentifierFrameToCanonical(
    Id3v24UniqueFileIdentifierFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    auto logical =
        copyId3v24LogicalBytes(
            frame.rawIdentifier,
            frame.effectiveUnsynchronisation
        );

    auto field =
        MetadataField(
            MetadataKey(
                "uniqueFileIdentifier"
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

    assertRegisteredShape(field);

    return
        Id3v24CanonicalMappingResult.success(
            field
        );
}


/++
Maps one unified native ID3v2.4 frame through the UFID canonical mapper.

Decoded UFID outcomes are mapped. Compressed or encrypted UFID outcomes
remain valid native metadata and return `requiresTransformation`.

Other native frame families remain unsupported by this mapper.

Params:
    native = Unified native ID3v2.4 frame.

Returns:
    Canonical unique-file-identifier mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24NativeUniqueFileIdentifierFrameToCanonical(
    Id3v24NativeFrame native
)
    @safe
{
    return native.content.match!(
        (Id3v24UniqueFileIdentifierOutcome outcome) =>
            outcome.decoded
                ? mapId3v24UniqueFileIdentifierFrameToCanonical(
                    outcome.uniqueFileIdentifier,
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
Constructs exact provenance for one mapped UFID frame.
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
            "UFID"
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


/// UFID preserves opaque identifier bytes and owner context.
unittest
{
    import audiotag.core.span :
        ByteSpan;

    const ubyte[] bytes =
        [0x11, 0x22, 0x33];

    Id3v24UniqueFileIdentifierFrame frame;

    frame.sourceOffset = 123;
    frame.ownerIdentifier =
        "example.invalid";

    frame.rawIdentifier =
        ByteSpan(
            bytes,
            500
        );

    frame.logicalIdentifierLength =
        bytes.length;

    auto result =
        mapId3v24UniqueFileIdentifierFrameToCanonical(
            frame
        );

    assert(result.mapped);

    assert(
        result.field.key.name ==
        "uniqueFileIdentifier"
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
        "UFID"
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


/// Physical unsynchronisation bytes never enter canonical UFID data.
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

    Id3v24UniqueFileIdentifierFrame frame;

    frame.ownerIdentifier =
        "owner";

    frame.rawIdentifier =
        ByteSpan(
            physical,
            700
        );

    frame.logicalIdentifierLength =
        7;

    frame.effectiveUnsynchronisation =
        true;

    auto result =
        mapId3v24UniqueFileIdentifierFrameToCanonical(
            frame
        );

    assert(result.mapped);

    const matches =
        result.field.value.match!(
            (MetadataBinary binary)
            {
                assert(
                    binary.length ==
                    frame.logicalIdentifierLength
                );

                return
                    binary.data ==
                    [
                        0x11,
                        0xFF, 0xE1,
                        0x22,
                        0xFF, 0x00,
                        0x33
                    ];
            },

            _ => false
        );

    assert(matches);
}


/// Native UFID mapping preserves the complete physical frame extent.
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
            'U', 'F', 'I', 'D',
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
        mapId3v24NativeUniqueFileIdentifierFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);

    assert(
        mapped.field.key.name ==
        "uniqueFileIdentifier"
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


/// Empty UFID identifier data remains representable canonically.
unittest
{
    import audiotag.core.span :
        ByteSpan;

    const ubyte[] bytes = [];

    Id3v24UniqueFileIdentifierFrame frame;

    frame.ownerIdentifier =
        "owner";

    frame.rawIdentifier =
        ByteSpan(
            bytes,
            1000
        );

    frame.logicalIdentifierLength =
        0;

    auto result =
        mapId3v24UniqueFileIdentifierFrameToCanonical(
            frame
        );

    assert(result.mapped);

    const matches =
        result.field.value.match!(
            (MetadataBinary binary) =>
                binary.empty,

            _ => false
        );

    assert(matches);
}


/// Transformation-pending UFID remains valid native metadata.
unittest
{
    import audiotag.id3v2.v24.frame :
        Id3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrameContent;

    import audiotag.id3v2.v24.unique_file_identifier :
        Id3v24UniqueFileIdentifierAvailability;

    Id3v24UniqueFileIdentifierOutcome outcome;

    outcome.availability =
        Id3v24UniqueFileIdentifierAvailability
            .requiresDecompression;

    Id3v24NativeFrameContent content =
        outcome;

    auto native =
        Id3v24NativeFrame(
            Id3v24FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v24NativeUniqueFileIdentifierFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .requiresTransformation
    );
}


/// Other native frame families remain unsupported by the UFID mapper.
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
        mapId3v24NativeUniqueFileIdentifierFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .unsupportedFrame
    );
}
