/++
Canonical mapping for ID3v2.4 attached-picture (`APIC`) frames.

APIC supports two canonical picture-source forms:

- embedded image data -> `MetadataBinary`
- linked image URL -> `MetadataUrl`

Embedded image bytes are copied into canonical owned storage. When ID3
unsynchronisation was effective, the physical APIC payload is traversed
through `Id3v24DataCursor` so that stuffing bytes are removed before the
canonical binary value is created.

The native APIC picture type is represented as the canonical field
qualifier `pictureRole`. The qualifier values preserve all ID3v2.4
defined picture roles with stable semantic names.

The APIC description belongs to `MetadataPicture.description`, not to
the surrounding field description.

Transformation-pending APIC outcomes remain valid native metadata and
return `requiresTransformation`.
+/
module audiotag.id3v2.v24.canonical_picture;

import std.sumtype :
    match;

import audiotag.id3v2.v24.attached_picture :
    Id3v24AttachedPictureFrame,
    Id3v24AttachedPictureOutcome,
    Id3v24PicturePayloadKind,
    Id3v24PictureType;

import audiotag.id3v2.v24.canonical_mapping :
    Id3v24CanonicalMappingResult,
    Id3v24CanonicalMappingStatus;

import audiotag.id3v2.v24.data_cursor :
    Id3v24DataCursor;

import audiotag.id3v2.v24.logical_bytes :
    copyId3v24LogicalBytes;

import audiotag.id3v2.v24.native_frame :
    Id3v24NativeFrame;

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
Maps one already decoded ID3v2.4 APIC frame to canonical artwork.

Embedded picture data is copied into canonical owned binary storage.
Physical ID3 unsynchronisation stuffing is removed before copying when
required.

Params:
    frame = Decoded and structurally validated APIC frame.
    sourceLength = Complete physical frame length when known. Zero
        represents point provenance only.

Returns:
    Canonical artwork mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24AttachedPictureFrameToCanonical(
    Id3v24AttachedPictureFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    auto source =
        makePictureSource(frame);

    auto picture =
        MetadataPicture(
            frame.description,
            source
        );

    auto field =
        MetadataField(
            MetadataKey("artwork"),
            MetadataValue(picture),
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

    assertRegisteredShape(field);

    return
        Id3v24CanonicalMappingResult.success(
            field
        );
}


/++
Maps one unified native ID3v2.4 frame through the APIC canonical mapper.

Only APIC native outcomes are handled here. Decoded APIC data is mapped,
while compressed or encrypted APIC data returns an explicit
transformation requirement.

Params:
    native = Unified native ID3v2.4 frame.

Returns:
    Canonical artwork mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24NativePictureFrameToCanonical(
    Id3v24NativeFrame native
)
    @safe
{
    return native.content.match!(
        (Id3v24AttachedPictureOutcome outcome) =>
            outcome.decoded
                ? mapId3v24AttachedPictureFrameToCanonical(
                    outcome.picture,
                    native.sourceLength
                )
                : Id3v24CanonicalMappingResult
                    .transformationRequired(),

        _ =>
            Id3v24CanonicalMappingResult.unsupported()
    );
}


/++
Creates the canonical source of an APIC picture.
+/
private MetadataPictureSource makePictureSource(
    Id3v24AttachedPictureFrame frame
)
    @safe
{
    if (
        frame.payloadKind ==
        Id3v24PicturePayloadKind.linkedUrl
    )
    {
        return MetadataPictureSource(
            MetadataUrl(
                frame.linkedUrl
            )
        );
    }

    auto binary =
        makeEmbeddedPictureBinary(frame);

    return MetadataPictureSource(binary);
}


/++
Creates owned canonical binary image data.

`rawPictureData` contains physical ID3 bytes. With effective
unsynchronisation, logical bytes are reconstructed through the same
bounded data cursor used by the semantic codec layer.

The cursor is only read while non-empty. Failure in that state would
violate the cursor primitive's internal consumption invariant rather
than represent a new APIC mapping condition.
+/
private MetadataBinary makeEmbeddedPictureBinary(
    Id3v24AttachedPictureFrame frame
)
    @safe
{
    auto logical =
        copyId3v24LogicalBytes(
            frame.rawPictureData,
            frame.effectiveUnsynchronisation
        );

    return MetadataBinary.copyFrom(
        logical,
        frame.mimeType
    );
}


/++
Returns the canonical qualifier name of an ID3v2.4 picture role.

All values defined by ID3v2.4 are represented explicitly.
+/
private string pictureRoleName(
    Id3v24PictureType pictureType
)
    @safe pure nothrow @nogc
{
    final switch (pictureType)
    {
        case Id3v24PictureType.other:
            return "other";

        case Id3v24PictureType.fileIcon:
            return "fileIcon";

        case Id3v24PictureType.otherFileIcon:
            return "otherFileIcon";

        case Id3v24PictureType.frontCover:
            return "frontCover";

        case Id3v24PictureType.backCover:
            return "backCover";

        case Id3v24PictureType.leafletPage:
            return "leafletPage";

        case Id3v24PictureType.media:
            return "media";

        case Id3v24PictureType.leadArtist:
            return "leadArtist";

        case Id3v24PictureType.artist:
            return "artist";

        case Id3v24PictureType.conductor:
            return "conductor";

        case Id3v24PictureType.band:
            return "band";

        case Id3v24PictureType.composer:
            return "composer";

        case Id3v24PictureType.lyricist:
            return "lyricist";

        case Id3v24PictureType.recordingLocation:
            return "recordingLocation";

        case Id3v24PictureType.duringRecording:
            return "duringRecording";

        case Id3v24PictureType.duringPerformance:
            return "duringPerformance";

        case Id3v24PictureType.videoCapture:
            return "videoCapture";

        case Id3v24PictureType.brightColouredFish:
            return "brightColouredFish";

        case Id3v24PictureType.illustration:
            return "illustration";

        case Id3v24PictureType.artistLogotype:
            return "artistLogotype";

        case Id3v24PictureType.publisherLogotype:
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
    return MetadataProvenance(
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


/// Embedded APIC data maps to an owned canonical binary picture.
unittest
{
    import audiotag.core.span :
        ByteSpan;

    const ubyte[] data =
        [
            0x89, 0x50, 0x4E, 0x47
        ];

    Id3v24AttachedPictureFrame frame;

    frame.sourceOffset = 123;
    frame.mimeType = "image/png";
    frame.pictureType =
        Id3v24PictureType.frontCover;
    frame.description = "Front cover";
    frame.payloadKind =
        Id3v24PicturePayloadKind.binaryData;
    frame.rawPictureData =
        ByteSpan(data, 500);

    auto result =
        mapId3v24AttachedPictureFrameToCanonical(
            frame
        );

    assert(result.mapped);
    assert(result.field.key.name == "artwork");

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

            _ => false
        );

    assert(matches);
}


/// Linked APIC data maps to a canonical picture URL.
unittest
{
    Id3v24AttachedPictureFrame frame;

    frame.sourceOffset = 200;
    frame.mimeType = "-->";
    frame.pictureType =
        Id3v24PictureType.backCover;
    frame.description = "Back cover";
    frame.payloadKind =
        Id3v24PicturePayloadKind.linkedUrl;
    frame.linkedUrl =
        "https://example.invalid/back.jpg";

    auto result =
        mapId3v24AttachedPictureFrameToCanonical(
            frame,
            42
        );

    assert(result.mapped);

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

            _ => false
        );

    assert(matches);
}


/// Native APIC mapping preserves exact physical frame provenance.
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
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x12,
            0x00, 0x02,

            0x03,

            'i', 'm', 'a', 'g', 'e',
            '/', 'j', 'p', 'e', 'g',
            0x00,

            0x03,

            0x00,

            0xFF, 0x00, 0xE1, 0x55
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
        mapId3v24NativePictureFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);

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
                                0xE1,
                                0x55
                            ] &&
                        binary.mediaType ==
                            "image/jpeg",

                    (MetadataUrl url) =>
                        false
                ),

            _ => false
        );

    assert(matches);
}


/// APIC unsynchronisation stuffing never enters canonical image data.
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

    Id3v24AttachedPictureFrame frame;

    frame.mimeType =
        "application/octet-stream";

    frame.pictureType =
        Id3v24PictureType.other;

    frame.payloadKind =
        Id3v24PicturePayloadKind.binaryData;

    frame.rawPictureData =
        ByteSpan(
            physical,
            900
        );

    frame.effectiveUnsynchronisation =
        true;

    auto result =
        mapId3v24AttachedPictureFrameToCanonical(
            frame
        );

    assert(result.mapped);

    const matches =
        result.field.value.match!(
            (MetadataPicture picture) =>
                picture.source.match!(
                    (MetadataBinary binary) =>
                        binary.data ==
                            [
                                0x11,
                                0xFF, 0xE1,
                                0x22,
                                0xFF, 0x00,
                                0x33
                            ],

                    (MetadataUrl url) =>
                        false
                ),

            _ => false
        );

    assert(matches);
}


/// Transformation-pending APIC remains valid native metadata.
unittest
{
    import audiotag.id3v2.v24.attached_picture :
        Id3v24AttachedPictureAvailability;

    import audiotag.id3v2.v24.frame :
        Id3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrameContent;

    Id3v24AttachedPictureOutcome outcome;

    outcome.availability =
        Id3v24AttachedPictureAvailability
            .requiresDecompression;

    Id3v24NativeFrameContent content =
        outcome;

    auto native =
        Id3v24NativeFrame(
            Id3v24FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v24NativePictureFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .requiresTransformation
    );
}


/// Non-APIC native frames remain unsupported by this mapper.
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
        mapId3v24NativePictureFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .unsupportedFrame
    );
}
