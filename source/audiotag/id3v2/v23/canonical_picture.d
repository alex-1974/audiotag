/++
Canonical mapping for ID3v2.3 attached-picture (`APIC`) frames.

APIC supports two canonical picture-source forms:

- embedded image data -> `MetadataBinary`
- linked image URL -> `MetadataUrl`

Embedded image bytes are copied into canonical owned storage. ID3v2.3
whole-tag unsynchronisation is reversed while copying so physical
stuffing bytes never enter the canonical binary value.

The native APIC picture type is represented as the canonical field
qualifier `pictureRole`.

The APIC description belongs to `MetadataPicture.description`, not to
the surrounding field description.

Transformation-pending APIC outcomes remain valid native metadata and
return `requiresTransformation`.
+/
module audiotag.id3v2.v23.canonical_picture;

import std.sumtype :
    match;

import audiotag.id3v2.v23.attached_picture :
    Id3v23AttachedPictureFrame,
    Id3v23AttachedPictureOutcome,
    Id3v23PicturePayloadKind,
    Id3v23PictureType;

import audiotag.id3v2.v23.canonical_mapping :
    Id3v23CanonicalMappingResult,
    Id3v23CanonicalMappingStatus;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.native_frame :
    Id3v23NativeFrame;

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
    MetadataPicture,
    MetadataPictureSource,
    MetadataUrl,
    MetadataValue;


/++
Maps one already decoded ID3v2.3 APIC frame to canonical artwork.

Embedded picture data is copied into canonical owned binary storage.
Physical ID3v2.3 unsynchronisation stuffing is removed before copying
when required.

Params:
    frame = Decoded and structurally validated APIC frame.
    sourceLength = Complete physical frame length when known. Zero
        represents point provenance only.

Returns:
    Canonical artwork mapping result.
+/
Id3v23CanonicalMappingResult
mapId3v23AttachedPictureFrameToCanonical(
    Id3v23AttachedPictureFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    auto source =
        makePictureSource(
            frame
        );


    auto picture =
        MetadataPicture(
            frame.description,
            source
        );


    auto field =
        MetadataField(
            MetadataKey(
                "artwork"
            ),
            MetadataValue(
                picture
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
                "pictureRole",
                pictureRoleName(
                    frame.pictureType
                )
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
Maps one unified native ID3v2.3 frame through the APIC canonical mapper.

Only APIC native outcomes are handled here. Decoded APIC data is mapped,
while compressed or encrypted APIC data returns an explicit
transformation requirement.

Params:
    native = Unified native ID3v2.3 frame.

Returns:
    Canonical artwork mapping result.
+/
Id3v23CanonicalMappingResult
mapId3v23NativePictureFrameToCanonical(
    Id3v23NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v23AttachedPictureOutcome outcome) =>
                outcome.decoded
                    ? mapId3v23AttachedPictureFrameToCanonical(
                        outcome.picture,
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
Creates the canonical source of an APIC picture.
+/
private MetadataPictureSource makePictureSource(
    Id3v23AttachedPictureFrame frame
)
    @safe
{
    if (
        frame.payloadKind ==
        Id3v23PicturePayloadKind.linkedUrl
    )
    {
        return
            MetadataPictureSource(
                MetadataUrl(
                    frame.linkedUrl
                )
            );
    }


    auto binary =
        makeEmbeddedPictureBinary(
            frame
        );


    return
        MetadataPictureSource(
            binary
        );
}


/++
Creates owned canonical binary image data.

`rawPictureData` contains physical ID3v2.3 bytes. When whole-tag
unsynchronisation was effective, logical bytes are reconstructed through
`Id3v23DataCursor`.

Because the cursor operates on an already bounded physical span, a
failure while reading until `empty` would indicate an internal cursor
invariant violation rather than malformed APIC input reaching this
mapping layer.
+/
private MetadataBinary makeEmbeddedPictureBinary(
    Id3v23AttachedPictureFrame frame
)
    @safe
{
    auto cursor =
        Id3v23DataCursor(
            frame.rawPictureData,
            frame.effectiveUnsynchronisation
        );


    ubyte[] logical;

    logical.reserve(
        frame.rawPictureData.length
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


    return
        MetadataBinary.copyFrom(
            logical,
            frame.mimeType
        );
}


/++
Returns the stable canonical role name for one validated ID3v2.3
picture type.
+/
private string pictureRoleName(
    Id3v23PictureType pictureType
)
    @safe pure nothrow @nogc
{
    final switch (
        pictureType
    )
    {
        case Id3v23PictureType.other:
            return "other";

        case Id3v23PictureType.fileIcon:
            return "fileIcon";

        case Id3v23PictureType.otherFileIcon:
            return "otherFileIcon";

        case Id3v23PictureType.frontCover:
            return "frontCover";

        case Id3v23PictureType.backCover:
            return "backCover";

        case Id3v23PictureType.leafletPage:
            return "leafletPage";

        case Id3v23PictureType.media:
            return "media";

        case Id3v23PictureType.leadArtist:
            return "leadArtist";

        case Id3v23PictureType.artist:
            return "artist";

        case Id3v23PictureType.conductor:
            return "conductor";

        case Id3v23PictureType.band:
            return "band";

        case Id3v23PictureType.composer:
            return "composer";

        case Id3v23PictureType.lyricist:
            return "lyricist";

        case Id3v23PictureType.recordingLocation:
            return "recordingLocation";

        case Id3v23PictureType.duringRecording:
            return "duringRecording";

        case Id3v23PictureType.duringPerformance:
            return "duringPerformance";

        case Id3v23PictureType.videoCapture:
            return "videoCapture";

        case Id3v23PictureType.brightColouredFish:
            return "brightColouredFish";

        case Id3v23PictureType.illustration:
            return "illustration";

        case Id3v23PictureType.artistLogotype:
            return "artistLogotype";

        case Id3v23PictureType.publisherLogotype:
            return "publisherLogotype";
    }
}


/++
Constructs exact provenance for one APIC frame.
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
                "APIC"
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

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.attached_picture :
        Id3v23AttachedPictureAvailability;

    import audiotag.id3v2.v23.frame :
        Id3v23FrameEnvelope,
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrameContent,
        Id3v23UnknownFrame,
        decodeId3v23NativeFrame;
}


/// Embedded APIC data maps to an owned canonical binary picture.
unittest
{
    const ubyte[] data =
        [
            0x89,
            0x50,
            0x4E,
            0x47
        ];


    Id3v23AttachedPictureFrame frame;


    frame.sourceOffset =
        123;


    frame.mimeType =
        "image/png";


    frame.pictureType =
        Id3v23PictureType.frontCover;


    frame.description =
        "Front cover";


    frame.payloadKind =
        Id3v23PicturePayloadKind.binaryData;


    frame.rawPictureData =
        ByteSpan(
            data,
            500
        );


    auto result =
        mapId3v23AttachedPictureFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
        result.field.key.name ==
        "artwork"
    );


    assert(
        result.field.provenance.length ==
        1
    );


    assert(
        result.field.provenance[0]
            .native.identifier ==
        "APIC"
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
        result.field.qualifiers.length ==
        1
    );


    assert(
        result.field.qualifiers[0].name ==
        "pictureRole"
    );


    assert(
        result.field.qualifiers[0].value ==
        "frontCover"
    );


    const matches =
        result.field.value.match!(
            (MetadataPicture picture) =>
                picture.description ==
                    "Front cover" &&
                picture.source.match!(
                    (MetadataBinary binary) =>
                        binary.data ==
                            [
                                0x89,
                                0x50,
                                0x4E,
                                0x47
                            ] &&
                        binary.mediaType ==
                            "image/png",

                    (MetadataUrl url) =>
                        false
                ),

            _ =>
                false
        );


    assert(
        matches
    );
}


/// Linked APIC data maps to a canonical picture URL.
unittest
{
    Id3v23AttachedPictureFrame frame;


    frame.sourceOffset =
        200;


    frame.mimeType =
        "-->";


    frame.pictureType =
        Id3v23PictureType.backCover;


    frame.description =
        "Back cover";


    frame.payloadKind =
        Id3v23PicturePayloadKind.linkedUrl;


    frame.linkedUrl =
        "https://example.invalid/back.jpg";


    auto result =
        mapId3v23AttachedPictureFrameToCanonical(
            frame,
            42
        );


    assert(
        result.mapped
    );


    assert(
        result.field.qualifiers[0].value ==
        "backCover"
    );


    assert(
        result.field.provenance[0]
            .sourceLength ==
        42
    );


    const matches =
        result.field.value.match!(
            (MetadataPicture picture) =>
                picture.description ==
                    "Back cover" &&
                picture.source.match!(
                    (MetadataUrl url) =>
                        url.value ==
                            "https://example.invalid/back.jpg",

                    (MetadataBinary binary) =>
                        false
                ),

            _ =>
                false
        );


    assert(
        matches
    );
}


/// Every ID3v2.3 picture type has a stable canonical role name.
unittest
{
    struct Case
    {
        Id3v23PictureType type;
        string name;
    }


    const cases =
        [
            Case(Id3v23PictureType.other, "other"),
            Case(Id3v23PictureType.fileIcon, "fileIcon"),
            Case(Id3v23PictureType.otherFileIcon, "otherFileIcon"),
            Case(Id3v23PictureType.frontCover, "frontCover"),
            Case(Id3v23PictureType.backCover, "backCover"),
            Case(Id3v23PictureType.leafletPage, "leafletPage"),
            Case(Id3v23PictureType.media, "media"),
            Case(Id3v23PictureType.leadArtist, "leadArtist"),
            Case(Id3v23PictureType.artist, "artist"),
            Case(Id3v23PictureType.conductor, "conductor"),
            Case(Id3v23PictureType.band, "band"),
            Case(Id3v23PictureType.composer, "composer"),
            Case(Id3v23PictureType.lyricist, "lyricist"),
            Case(
                Id3v23PictureType.recordingLocation,
                "recordingLocation"
            ),
            Case(
                Id3v23PictureType.duringRecording,
                "duringRecording"
            ),
            Case(
                Id3v23PictureType.duringPerformance,
                "duringPerformance"
            ),
            Case(
                Id3v23PictureType.videoCapture,
                "videoCapture"
            ),
            Case(
                Id3v23PictureType.brightColouredFish,
                "brightColouredFish"
            ),
            Case(
                Id3v23PictureType.illustration,
                "illustration"
            ),
            Case(
                Id3v23PictureType.artistLogotype,
                "artistLogotype"
            ),
            Case(
                Id3v23PictureType.publisherLogotype,
                "publisherLogotype"
            )
        ];


    foreach (
        entry;
        cases
    )
    {
        assert(
            pictureRoleName(
                entry.type
            ) ==
            entry.name
        );
    }
}


/// Whole-tag unsynchronisation stuffing never enters canonical image data.
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


    Id3v23AttachedPictureFrame frame;


    frame.mimeType =
        "application/octet-stream";


    frame.pictureType =
        Id3v23PictureType.other;


    frame.payloadKind =
        Id3v23PicturePayloadKind.binaryData;


    frame.rawPictureData =
        ByteSpan(
            physical,
            900
        );


    frame.effectiveUnsynchronisation =
        true;


    auto result =
        mapId3v23AttachedPictureFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    const matches =
        result.field.value.match!(
            (MetadataPicture picture) =>
                picture.source.match!(
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

                    (MetadataUrl url) =>
                        false
                ),

            _ =>
                false
        );


    assert(
        matches
    );
}


/// Native APIC mapping preserves exact physical frame provenance.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',

            /*
             * Encoding
             * + MIME + terminator
             * + picture type
             * + empty description terminator
             * + four image bytes.
             */
            0x00, 0x00, 0x00, 0x12,

            0x00, 0x00,

            0x00,

            'i', 'm', 'a', 'g', 'e',
            '/', 'j', 'p', 'e', 'g',
            0x00,

            0x03,

            0x00,

            0xFF,
            0xD8,
            0xFF,
            0xD9
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
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
        mapId3v23NativePictureFrameToCanonical(
            native.value
        );


    assert(
        mapped.mapped
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


    assert(
        mapped.field.qualifiers[0].value ==
        "frontCover"
    );


    const matches =
        mapped.field.value.match!(
            (MetadataPicture picture) =>
                picture.source.match!(
                    (MetadataBinary binary) =>
                        binary.data ==
                            [
                                0xFF,
                                0xD8,
                                0xFF,
                                0xD9
                            ] &&
                        binary.mediaType ==
                            "image/jpeg",

                    (MetadataUrl url) =>
                        false
                ),

            _ =>
                false
        );


    assert(
        matches
    );
}


/// Transformation-pending APIC remains valid native metadata.
unittest
{
    Id3v23AttachedPictureOutcome outcome;


    outcome.availability =
        Id3v23AttachedPictureAvailability
            .requiresDecompression;


    Id3v23NativeFrameContent content =
        outcome;


    auto native =
        Id3v23NativeFrame(
            Id3v23FrameEnvelope.init,
            content
        );


    auto result =
        mapId3v23NativePictureFrameToCanonical(
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


/// Non-APIC native frames remain unsupported by this mapper.
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
        mapId3v23NativePictureFrameToCanonical(
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
