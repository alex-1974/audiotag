/++
Canonical mapping for ID3v2.2 unique-file-identifier (`UFI`) frames.

Each decoded `UFI` frame becomes one repeatable canonical
`uniqueFileIdentifier` field.

The opaque identifier is represented as owned `MetadataBinary`.

When ID3v2.2 whole-tag unsynchronisation was effective, physical stuffing
bytes are removed before the canonical value is created.

The native owner identifier is retained as canonical qualifier `owner`.

The native codec has already validated the non-empty owner identifier and the
maximum of 64 logical identifier bytes. This mapper consumes the decoded
semantic frame and performs no structural reparsing.
+/
module audiotag.id3v2.v22.canonical_unique_file_identifier;

import std.sumtype :
    match;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v22.canonical_mapping :
    Id3v22CanonicalMappingResult,
    Id3v22CanonicalMappingStatus;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.native_frame :
    Id3v22NativeFrame;

import audiotag.id3v2.v22.unique_file_identifier :
    Id3v22UniqueFileIdentifierFrame;

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
Maps one decoded ID3v2.2 `UFI` frame to canonical metadata.

Params:
    frame = Decoded unique-file-identifier frame.
    sourceLength = Complete physical frame length when known. Zero represents
        point provenance only.

Returns:
    Canonical unique-file-identifier mapping result.
+/
Id3v22CanonicalMappingResult
mapId3v22UniqueFileIdentifierFrameToCanonical(
    Id3v22UniqueFileIdentifierFrame frame,
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
     * The native decoder has already counted and validated the logical
     * identifier length. A disagreement here is an internal representation
     * bug, not a new external-input condition.
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
        Id3v22CanonicalMappingResult
            .success(
                field
            );
}


/++
Maps one unified native ID3v2.2 frame through the UFI canonical mapper.

Only decoded `Id3v22UniqueFileIdentifierFrame` alternatives are handled.
Other native frame families remain valid native metadata and return
`unsupportedFrame`.

The complete native frame supplies exact physical frame provenance.
+/
Id3v22CanonicalMappingResult
mapId3v22NativeUniqueFileIdentifierFrameToCanonical(
    Id3v22NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v22UniqueFileIdentifierFrame frame) =>
                mapId3v22UniqueFileIdentifierFrameToCanonical(
                    frame,
                    native.sourceLength
                ),

            _ =>
                Id3v22CanonicalMappingResult
                    .unsupported()
        );
}


/++
Copies logical UFI identifier bytes into owned storage.

`raw` contains the physical ID3v2.2 representation. When whole-tag
unsynchronisation was active, `Id3v22DataCursor` removes stuffing bytes while
traversing the already bounded identifier span.
+/
private ubyte[]
copyIdentifierLogicalBytes(
    ByteSpan raw,
    bool unsynchronised
)
    @safe
{
    auto cursor =
        Id3v22DataCursor(
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
Constructs exact canonical provenance for one UFI frame.
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
                "UFI"
            ),
            sourceOffset,
            sourceLength,
            MetadataConfidence.exact
        );
}


/++
Checks the canonical mapper/registry contract as a programmer invariant.
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

    import audiotag.id3v2.v22.frame :
        Id3v22FrameEnvelope,
        parseId3v22FrameEnvelope;

    import audiotag.id3v2.v22.native_frame :
        Id3v22NativeFrameContent,
        Id3v22UnknownFrame,
        decodeId3v22NativeFrame;
}


/// UFI preserves opaque identifier bytes and owner context.
unittest
{
    const ubyte[] bytes =
        [
            0x11,
            0x22,
            0x33
        ];


    Id3v22UniqueFileIdentifierFrame frame;


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
        mapId3v22UniqueFileIdentifierFrameToCanonical(
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
        "UFI"
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


/// Physical unsynchronisation bytes never enter canonical UFI data.
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


    Id3v22UniqueFileIdentifierFrame frame;


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
        mapId3v22UniqueFileIdentifierFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
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
        )
    );
}


/// Exactly 64 logical identifier bytes remain representable canonically.
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


    Id3v22UniqueFileIdentifierFrame frame;


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
        mapId3v22UniqueFileIdentifierFrameToCanonical(
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


/// Native UFI mapping preserves the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I',

            /*
             * owner "owner" + NUL + 3 identifier bytes.
             */
            0x00, 0x00, 0x09,

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
        mapId3v22NativeUniqueFileIdentifierFrameToCanonical(
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


/// Whole-tag-unsynchronised native UFI keeps physical provenance and logical bytes.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I',

            /*
             * Five logical frame-data bytes:
             *
             * owner: x 00
             * id:    FF E0 FF
             *
             * Physical representation contains one stuffing zero.
             */
            0x00, 0x00, 0x05,

            'x',
            0x00,

            0xFF,
            0x00,
            0xE0,
            0xFF
        ];


    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1100
            ),
            true
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
        mapId3v22NativeUniqueFileIdentifierFrameToCanonical(
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


/// Empty UFI identifier data remains representable canonically.
unittest
{
    const ubyte[] bytes = [];


    Id3v22UniqueFileIdentifierFrame frame;


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
        mapId3v22UniqueFileIdentifierFrameToCanonical(
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


/// Other native frame families remain unsupported.
unittest
{
    Id3v22NativeFrameContent content =
        Id3v22UnknownFrame();


    auto native =
        Id3v22NativeFrame(
            Id3v22FrameEnvelope.init,
            content
        );


    auto result =
        mapId3v22NativeUniqueFileIdentifierFrameToCanonical(
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
