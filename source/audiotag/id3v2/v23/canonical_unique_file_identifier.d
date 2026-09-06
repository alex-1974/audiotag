/++
Canonical mapping for ID3v2.3 unique-file-identifier (`UFID`) frames.

Each decoded UFID frame becomes one repeatable canonical
`uniqueFileIdentifier` field.

The opaque identifier is represented as owned `MetadataBinary`.
When ID3v2.3 whole-tag unsynchronisation was effective, physical
stuffing bytes are removed before the canonical value is created.

The UFID owner identifier is retained as canonical qualifier `owner`.

The native UFID codec is responsible for validating the specification
limit of at most 64 logical identifier bytes. This mapper consumes the
already-decoded semantic frame and does not reinterpret malformed input.

Transformation-pending native outcomes remain valid metadata and return
`requiresTransformation`.
+/
module audiotag.id3v2.v23.canonical_unique_file_identifier;

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

import audiotag.id3v2.v23.unique_file_identifier :
    Id3v23UniqueFileIdentifierFrame,
    Id3v23UniqueFileIdentifierOutcome;

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
Maps one decoded ID3v2.3 UFID frame to canonical metadata.

The native decoder has already validated the non-empty owner identifier
and the maximum logical identifier length.

Params:
    frame = Decoded UFID frame.
    sourceLength = Complete physical frame length when known. Zero
        represents point provenance only.

Returns:
    Canonical unique-file-identifier mapping result.
+/
Id3v23CanonicalMappingResult
mapId3v23UniqueFileIdentifierFrameToCanonical(
    Id3v23UniqueFileIdentifierFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    auto logical =
        copyIdentifierLogicalBytes(
            frame.rawIdentifier,
            frame.effectiveUnsynchronisation
        );


    /*
     * A decoded UFID frame already carries the logical length validated
     * by the native codec. A disagreement here would indicate an internal
     * representation bug rather than malformed external input.
     */
    assert(
        logical.length ==
        frame.logicalIdentifierLength
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
Maps one unified native ID3v2.3 frame through the UFID canonical mapper.

Decoded UFID outcomes are mapped. Compressed or encrypted UFID outcomes
remain valid native metadata and return `requiresTransformation`.

Other native frame families remain unsupported by this mapper.

Params:
    native = Unified native ID3v2.3 frame.

Returns:
    Canonical unique-file-identifier mapping result.
+/
Id3v23CanonicalMappingResult
mapId3v23NativeUniqueFileIdentifierFrameToCanonical(
    Id3v23NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v23UniqueFileIdentifierOutcome outcome) =>
                outcome.decoded
                    ? mapId3v23UniqueFileIdentifierFrameToCanonical(
                        outcome.uniqueFileIdentifier,
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
Copies the logical UFID identifier bytes into owned temporary storage.

`rawIdentifier` preserves the physical ID3v2.3 representation. When
whole-tag unsynchronisation was effective, `Id3v23DataCursor` removes
the inserted stuffing bytes while traversing the already bounded span.

A read failure while the cursor reports non-empty would violate an
internal cursor invariant rather than represent a new UFID parsing
condition at this layer.
+/
private ubyte[] copyIdentifierLogicalBytes(
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
Constructs exact provenance for one mapped UFID frame.
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
                "UFID"
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

    import audiotag.id3v2.v23.unique_file_identifier :
        Id3v23UniqueFileIdentifierAvailability;
}


/// UFID preserves opaque identifier bytes and owner context.
unittest
{
    const ubyte[] bytes =
        [
            0x11,
            0x22,
            0x33
        ];


    Id3v23UniqueFileIdentifierFrame frame;


    frame.sourceOffset =
        123;


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
        mapId3v23UniqueFileIdentifierFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


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


    assert(
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
        )
    );
}


/// Physical unsynchronisation bytes never enter canonical UFID data.
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


    Id3v23UniqueFileIdentifierFrame frame;


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
        mapId3v23UniqueFileIdentifierFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
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
                        0xFF,
                        0xE1,
                        0x22,
                        0xFF,
                        0x00,
                        0x33
                    ];
            },

            _ =>
                false
        )
    );
}


/// Exactly 64 logical UFID bytes remain representable canonically.
unittest
{
    ubyte[] physical =
        [
            0xFF,
            0x00
        ];


    foreach (
        _;
        0 .. 63
    )
    {
        physical ~=
            0x11;
    }


    Id3v23UniqueFileIdentifierFrame frame;


    frame.ownerIdentifier =
        "owner";


    frame.rawIdentifier =
        ByteSpan(
            physical,
            800
        );


    frame.logicalIdentifierLength =
        64;


    frame.effectiveUnsynchronisation =
        true;


    auto result =
        mapId3v23UniqueFileIdentifierFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
        result.field.value.match!(
            (MetadataBinary binary) =>
                binary.length ==
                64,

            _ =>
                false
        )
    );
}


/// Native UFID mapping preserves the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
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
        mapId3v23NativeUniqueFileIdentifierFrameToCanonical(
            native.value
        );


    assert(
        mapped.mapped
    );


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


    assert(
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
        )
    );
}


/// Whole-tag-unsynchronised native UFID keeps physical provenance and logical identifier bytes.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',

            /*
             * Five logical frame-data bytes:
             *
             * owner: x 00
             * id:    FF E0 FF
             *
             * Physical representation contains one stuffing zero.
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
        mapId3v23NativeUniqueFileIdentifierFrameToCanonical(
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


/// Empty UFID identifier data remains representable canonically.
unittest
{
    const ubyte[] bytes = [];


    Id3v23UniqueFileIdentifierFrame frame;


    frame.ownerIdentifier =
        "owner";


    frame.rawIdentifier =
        ByteSpan(
            bytes,
            1200
        );


    frame.logicalIdentifierLength =
        0;


    auto result =
        mapId3v23UniqueFileIdentifierFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
        result.field.value.match!(
            (MetadataBinary binary) =>
                binary.length ==
                0,

            _ =>
                false
        )
    );
}


/// Transformation-pending UFID remains valid native metadata.
unittest
{
    Id3v23UniqueFileIdentifierOutcome outcome;


    outcome.availability =
        Id3v23UniqueFileIdentifierAvailability
            .requiresDecompression;


    Id3v23NativeFrameContent content =
        outcome;


    auto native =
        Id3v23NativeFrame(
            Id3v23FrameEnvelope.init,
            content
        );


    auto result =
        mapId3v23NativeUniqueFileIdentifierFrameToCanonical(
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


/// Other native frame families remain unsupported by the UFID mapper.
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
        mapId3v23NativeUniqueFileIdentifierFrameToCanonical(
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
