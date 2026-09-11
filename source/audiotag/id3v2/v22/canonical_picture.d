/++
Canonical mapping for ID3v2.2 attached-picture (`PIC`) frames.

ID3v2.2 `PIC` supports two canonical picture-source forms:

- embedded image data -> `MetadataBinary`
- linked image URL -> `MetadataUrl`

The fixed three-byte v2.2 image-format field is not itself a MIME type.
The canonical mapper performs only two specification-safe normalizations:

- `JPG` -> `image/jpeg`
- `PNG` -> `image/png`

Other structurally valid three-byte image-format identifiers remain fully
preserved in the native frame. Their canonical embedded binary value uses an
empty optional media type rather than inventing a MIME type or discarding the
artwork.

Whole-tag unsynchronisation stuffing is removed while copying embedded image
bytes into canonical owned storage.

The shared ID3v2 picture type becomes canonical qualifier `pictureRole`.
The native PIC description becomes `MetadataPicture.description`.
+/
module audiotag.id3v2.v22.canonical_picture;

import std.sumtype :
    match;

import audiotag.id3v2.common.picture :
    Id3v2PicturePayloadKind,
    Id3v2PictureType;

import audiotag.id3v2.v22.attached_picture :
    Id3v22AttachedPictureFrame;

import audiotag.id3v2.v22.canonical_mapping :
    Id3v22CanonicalMappingResult,
    Id3v22CanonicalMappingStatus;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.native_frame :
    Id3v22NativeFrame;

import audiotag.id3v2.v22.picture_role :
    findId3v22PictureRole;

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
Maps one decoded ID3v2.2 `PIC` frame to canonical artwork.

Embedded picture bytes become owned canonical binary data after removal of any
whole-tag-unsynchronisation stuffing.

`JPG` and `PNG` receive their standard MIME types. Other valid native format
identifiers retain canonical image bytes with an empty optional media type;
their exact three-byte identifier remains available in the native frame.

Linked `-->` pictures become canonical URLs.

Params:
    frame = Decoded and structurally validated PIC frame.
    sourceLength = Complete physical frame length when known. Zero represents
        point provenance only.

Returns:
    Canonical artwork mapping result.
+/
Id3v22CanonicalMappingResult
mapId3v22AttachedPictureFrameToCanonical(
    Id3v22AttachedPictureFrame frame,
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


    const role =
        findId3v22PictureRole(
            frame.pictureType
        );


    /*
     * The native PIC decoder already rejects picture-type values outside the
     * complete shared ID3v2 range.
     */
    assert(
        role.found
    );


    field.qualifiers =
        [
            MetadataQualifier(
                "pictureRole",
                role.definition.name
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
Maps one unified native ID3v2.2 frame through the PIC canonical mapper.

Only decoded `Id3v22AttachedPictureFrame` alternatives are handled. Other
native frame families remain valid native metadata and return
`unsupportedFrame`.

The complete native frame supplies exact physical frame provenance.
+/
Id3v22CanonicalMappingResult
mapId3v22NativePictureFrameToCanonical(
    Id3v22NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v22AttachedPictureFrame frame) =>
                mapId3v22AttachedPictureFrameToCanonical(
                    frame,
                    native.sourceLength
                ),

            _ =>
                Id3v22CanonicalMappingResult
                    .unsupported()
        );
}


/++
Creates the canonical source of one v2.2 picture.
+/
private MetadataPictureSource
makePictureSource(
    Id3v22AttachedPictureFrame frame
)
    @safe
{
    if (
        frame.payloadKind ==
        Id3v2PicturePayloadKind.linkedUrl
    )
    {
        return
            MetadataPictureSource(
                MetadataUrl(
                    frame.linkedUrl
                )
            );
    }


    return
        MetadataPictureSource(
            makeEmbeddedPictureBinary(
                frame
            )
        );
}


/++
Creates owned canonical binary image data.

`rawPictureData` preserves the physical ID3v2.2 representation. When whole-tag
unsynchronisation was effective, logical bytes are reconstructed through
`Id3v22DataCursor`.

The native three-byte format field is converted to a MIME type only for the
well-defined `JPG` and `PNG` identifiers. Other format identifiers intentionally
produce an empty optional media type.
+/
private MetadataBinary
makeEmbeddedPictureBinary(
    Id3v22AttachedPictureFrame frame
)
    @safe
{
    auto cursor =
        Id3v22DataCursor(
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
            mediaTypeForImageFormat(
                frame.imageFormat
            )
        );
}


/++
Returns the specification-safe canonical MIME type for one v2.2 image format.

No MIME type is invented for other valid native three-byte identifiers.
+/
private string
mediaTypeForImageFormat(
    const ref char[3] imageFormat
)
    @safe pure nothrow @nogc
{
    if (
        imageFormat[] ==
        "JPG"
    )
    {
        return "image/jpeg";
    }


    if (
        imageFormat[] ==
        "PNG"
    )
    {
        return "image/png";
    }


    return "";
}


/++
Constructs exact canonical provenance for one PIC frame.
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
                "PIC"
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

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.frame :
        Id3v22FrameEnvelope,
        parseId3v22FrameEnvelope;

    import audiotag.id3v2.v22.native_frame :
        Id3v22NativeFrameContent,
        Id3v22UnknownFrame,
        decodeId3v22NativeFrame;
}


/// Embedded JPG artwork maps to owned canonical binary image data.
unittest
{
    const ubyte[] data =
        [
            0xFF,
            0xD8,
            0xFF,
            0xD9
        ];


    Id3v22AttachedPictureFrame frame;


    frame.sourceOffset =
        123;


    frame.imageFormat[] =
        "JPG";


    frame.pictureType =
        Id3v2PictureType.frontCover;


    frame.description =
        "Front cover";


    frame.payloadKind =
        Id3v2PicturePayloadKind.binaryData;


    frame.rawPictureData =
        ByteSpan(
            data,
            500
        );


    auto result =
        mapId3v22AttachedPictureFrameToCanonical(
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
        "PIC"
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


    assert(matches);
}


/// PNG receives its standard canonical MIME type.
unittest
{
    const ubyte[] data =
        [
            0x89,
            0x50,
            0x4E,
            0x47
        ];


    Id3v22AttachedPictureFrame frame;


    frame.imageFormat[] =
        "PNG";


    frame.pictureType =
        Id3v2PictureType.other;


    frame.payloadKind =
        Id3v2PicturePayloadKind.binaryData;


    frame.rawPictureData =
        ByteSpan(
            data,
            600
        );


    auto result =
        mapId3v22AttachedPictureFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
        result.field.value.match!(
            (MetadataPicture picture) =>
                picture.source.match!(
                    (MetadataBinary binary) =>
                        binary.mediaType ==
                            "image/png",

                    (MetadataUrl url) =>
                        false
                ),

            _ =>
                false
        )
    );
}


/// Other valid image-format identifiers retain artwork without invented MIME.
unittest
{
    const ubyte[] data =
        [
            'G',
            'I',
            'F'
        ];


    Id3v22AttachedPictureFrame frame;


    frame.imageFormat[] =
        "GIF";


    frame.pictureType =
        Id3v2PictureType.illustration;


    frame.description =
        "Illustration";


    frame.payloadKind =
        Id3v2PicturePayloadKind.binaryData;


    frame.rawPictureData =
        ByteSpan(
            data,
            700
        );


    auto result =
        mapId3v22AttachedPictureFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
        result.field.qualifiers[0].value ==
        "illustration"
    );


    assert(
        result.field.value.match!(
            (MetadataPicture picture) =>
                picture.description ==
                    "Illustration" &&
                picture.source.match!(
                    (MetadataBinary binary) =>
                        binary.data ==
                            ['G', 'I', 'F'] &&
                        binary.mediaType.length ==
                            0,

                    (MetadataUrl url) =>
                        false
                ),

            _ =>
                false
        )
    );
}


/// Linked PIC data maps to a canonical picture URL.
unittest
{
    Id3v22AttachedPictureFrame frame;


    frame.sourceOffset =
        200;


    frame.imageFormat[] =
        "-->";


    frame.pictureType =
        Id3v2PictureType.backCover;


    frame.description =
        "Back cover";


    frame.payloadKind =
        Id3v2PicturePayloadKind.linkedUrl;


    frame.linkedUrl =
        "https://example.invalid/back.jpg";


    auto result =
        mapId3v22AttachedPictureFrameToCanonical(
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


    assert(
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
        )
    );
}


/// Every shared ID3v2 picture type has a stable canonical role.
unittest
{
    foreach (
        raw;
        0 .. 0x15
    )
    {
        const role =
            findId3v22PictureRole(
                cast(Id3v2PictureType) raw
            );


        assert(
            role.found
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


    Id3v22AttachedPictureFrame frame;


    frame.imageFormat[] =
        "JPG";


    frame.pictureType =
        Id3v2PictureType.other;


    frame.payloadKind =
        Id3v2PicturePayloadKind.binaryData;


    frame.rawPictureData =
        ByteSpan(
            physical,
            900
        );


    frame.effectiveUnsynchronisation =
        true;


    auto result =
        mapId3v22AttachedPictureFrameToCanonical(
            frame
        );


    assert(
        result.mapped
    );


    assert(
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
        )
    );
}


/// Native PIC mapping preserves the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',

            /*
             * 1 encoding
             * + 3 format
             * + 1 type
             * + 1 empty-description terminator
             * + 4 image bytes
             * = 10.
             */
            0x00, 0x00, 0x0A,

            0x00,
            'J', 'P', 'G',
            0x03,
            0x00,

            0xFF, 0xD8, 0xFF, 0xD9
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1000
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
        mapId3v22NativePictureFrameToCanonical(
            native.value
        );


    assert(
        mapped.mapped
    );


    assert(
        mapped.field.key.name ==
        "artwork"
    );


    assert(
        mapped.field.qualifiers[0].value ==
        "frontCover"
    );


    assert(
        mapped.field.provenance[0]
            .sourceOffset ==
        1000
    );


    assert(
        mapped.field.provenance[0]
            .sourceLength ==
        bytes.length
    );


    assert(
        mapped.field.value.match!(
            (MetadataPicture picture) =>
                picture.source.match!(
                    (MetadataBinary binary) =>
                        binary.mediaType ==
                            "image/jpeg" &&
                        binary.data ==
                            [
                                0xFF,
                                0xD8,
                                0xFF,
                                0xD9
                            ],

                    (MetadataUrl url) =>
                        false
                ),

            _ =>
                false
        )
    );
}


/// Native linked PIC mapping preserves URL semantics and physical provenance.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',

            /*
             * encoding + format + type + empty description + URL "x"
             * = 7 logical/physical data bytes.
             */
            0x00, 0x00, 0x07,

            0x00,
            '-', '-', '>',
            0x04,
            0x00,
            'x'
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1200
            )
        );


    auto envelope =
        cursor.parseId3v22FrameEnvelope();


    assert(
        envelope.hasValue
    );


    auto native =
        decodeId3v22NativeFrame(
            envelope.value
        );


    assert(
        native.hasValue
    );


    auto mapped =
        mapId3v22NativePictureFrameToCanonical(
            native.value
        );


    assert(
        mapped.mapped
    );


    assert(
        mapped.field.qualifiers[0].value ==
        "backCover"
    );


    assert(
        mapped.field.provenance[0]
            .sourceLength ==
        bytes.length
    );


    assert(
        mapped.field.value.match!(
            (MetadataPicture picture) =>
                picture.source.match!(
                    (MetadataUrl url) =>
                        url.value ==
                            "x",

                    (MetadataBinary binary) =>
                        false
                ),

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
        mapId3v22NativePictureFrameToCanonical(
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
