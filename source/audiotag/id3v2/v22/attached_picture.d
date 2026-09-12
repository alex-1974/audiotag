/++
ID3v2.2 attached-picture frame decoding.

A `PIC` frame contains:

- one text-encoding marker;
- one fixed three-byte image-format field;
- one picture-type byte;
- one terminated description using the selected encoding;
- binary picture data or, for image format `"-->"`, a linked URL.

The picture-type and final-payload-kind semantics are shared with later ID3v2
revisions through `audiotag.id3v2.common.picture`.

The three-byte image-format representation is specific to ID3v2.2 and is
preserved exactly. `PNG` and `JPG` are preferred by the specification but
other three-byte format identifiers remain structurally valid and are retained
without reinterpretation.

Whole-tag unsynchronisation is reversed only during logical traversal and text
decoding. Raw spans preserve the exact physical source representation.

This module performs no canonical metadata mapping and does not decode image
formats.


Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.attached_picture;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.picture :
    Id3v2PicturePayloadKind,
    Id3v2PictureType,
    isValidId3v2PictureType;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

import audiotag.id3v2.v22.text_decode :
    decodeId3v22TextSpan;

import audiotag.id3v2.v22.text_encoding :
    Id3v22TextEncoding,
    parseId3v22TextEncoding;

import audiotag.id3v2.v22.text_segment :
    takeId3v22TerminatedTextSegment;


/++
Decoded ID3v2.2 `PIC` frame.

`imageFormat` preserves the three logical bytes exactly as stored. No attempt
is made to normalise `JPG`, `PNG` or vendor-specific values.

`rawImageFormat`, `rawDescription` and `rawPictureData` preserve the physical
source representation, including any whole-tag unsynchronisation stuffing.
+/
struct Id3v22AttachedPictureFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Encoding used by the description.
    Id3v22TextEncoding descriptionEncoding;

    /// Native three-byte ID3v2.2 image-format field.
    char[3] imageFormat;

    /// Physical image-format bytes as stored.
    ByteSpan rawImageFormat;

    /// Declared picture type shared across ID3v2 revisions.
    Id3v2PictureType pictureType;

    /// Absolute physical source offset of the logical picture-type byte.
    size_t pictureTypeSourceOffset;

    /// Decoded content description.
    string description;

    /// Physical description bytes excluding its terminator.
    ByteSpan rawDescription;

    /// Whether the final payload is embedded binary data or a URL.
    Id3v2PicturePayloadKind payloadKind;

    /// Physical final payload bytes extending to the frame boundary.
    ByteSpan rawPictureData;

    /// Decoded ISO-8859-1 URL when `payloadKind == linkedUrl`.
    string linkedUrl;

    /// Whether ID3v2.2 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;


    /// Whether this PIC frame refers to an external image.
    @property
    bool linked() const
        @safe pure nothrow @nogc
    {
        return
            payloadKind ==
            Id3v2PicturePayloadKind.linkedUrl;
    }
}


/++
Decodes an ID3v2.2 attached-picture (`PIC`) frame.

The payload has the form:

    Text encoding   $xx
    Image format    $xx xx xx
    Picture type    $xx
    Description     <text according to encoding> $00 (00)
    Picture data    <binary data>

The image-format field is preserved as exactly three logical bytes. Values
other than `PNG`, `JPG` and `-->` are retained rather than rejected because the
ID3v2.2 specification recommends PNG/JPEG for interoperability but does not
make them the only valid formats.

Image format `"-->"` changes the final field from embedded image bytes to an
ISO-8859-1 URL extending to the frame boundary.

Picture-type values outside the shared ID3v2-defined range `$00` through
`$14` are rejected in strict decoding.

Params:
    frame = Previously validated and bounded ID3v2.2 frame.
    tagUnsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    The decoded native picture frame or a structured parse/text error.
+/
ParseResult!Id3v22AttachedPictureFrame
decodeId3v22AttachedPictureFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "PIC"
    )
    {
        return
            ParseResult!Id3v22AttachedPictureFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }


    auto payload =
        Id3v22DataCursor(
            frame.data,
            tagUnsynchronised
        );


    /*
     * The first logical byte selects the description encoding.
     */
    auto encodingResult =
        payload.parseId3v22TextEncoding();

    if (
        encodingResult.hasError
    )
    {
        return
            ParseResult!Id3v22AttachedPictureFrame
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;


    /*
     * ID3v2.2 uses exactly three logical bytes for its image-format field.
     * Preserve both the logical characters and the physical source span.
     */
    const imageFormatStart =
        payload.remainingRaw;

    char[3] imageFormat;

    foreach (
        i;
        0 .. 3
    )
    {
        auto byteResult =
            payload.takeByte();

        if (
            byteResult.hasError
        )
        {
            return
                ParseResult!Id3v22AttachedPictureFrame
                    .failure(
                        byteResult.error
                    );
        }

        imageFormat[i] =
            cast(char)
                byteResult.value.value;
    }

    const imageFormatPhysicalLength =
        imageFormatStart.length -
        payload.remainingRaw.length;

    const rawImageFormat =
        imageFormatStart.subspan(
            0,
            imageFormatPhysicalLength
        );


    /*
     * Picture type is one logical byte.
     */
    auto typeResult =
        payload.takeByte();

    if (
        typeResult.hasError
    )
    {
        return
            ParseResult!Id3v22AttachedPictureFrame
                .failure(
                    typeResult.error
                );
    }

    const typeByte =
        typeResult.value;

    if (
        !isValidId3v2PictureType(
            typeByte.value
        )
    )
    {
        return
            ParseResult!Id3v22AttachedPictureFrame
                .failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        typeByte.sourceOffset
                    )
                );
    }

    const pictureType =
        cast(Id3v2PictureType)
            typeByte.value;


    /*
     * The description field is mandatory but may be empty.
     */
    auto descriptionResult =
        payload.takeId3v22TerminatedTextSegment(
            encoding
        );

    if (
        descriptionResult.hasError
    )
    {
        return
            ParseResult!Id3v22AttachedPictureFrame
                .failure(
                    descriptionResult.error
                );
    }

    const descriptionSegment =
        descriptionResult.value;


    auto description =
        decodeId3v22TextSpan(
            descriptionSegment.raw,
            encoding,
            tagUnsynchronised
        );

    if (
        description.hasError
    )
    {
        return
            ParseResult!Id3v22AttachedPictureFrame
                .failure(
                    description.error
                );
    }


    /*
     * The final field consumes the remainder of the bounded frame payload.
     * Embedded image bytes remain opaque and physical.
     */
    const rawPictureData =
        payload.remainingRaw;

    Id3v2PicturePayloadKind payloadKind =
        Id3v2PicturePayloadKind.binaryData;

    string linkedUrl;


    if (
        imageFormat[] ==
        "-->"
    )
    {
        payloadKind =
            Id3v2PicturePayloadKind.linkedUrl;

        auto url =
            decodeId3v22TextSpan(
                rawPictureData,
                Id3v22TextEncoding.latin1,
                tagUnsynchronised
            );

        if (
            url.hasError
        )
        {
            return
                ParseResult!Id3v22AttachedPictureFrame
                    .failure(
                        url.error
                    );
        }

        linkedUrl =
            url.value;
    }


    return
        ParseResult!Id3v22AttachedPictureFrame
            .success(
                Id3v22AttachedPictureFrame(
                    frame.header.sourceOffset,
                    encoding,
                    imageFormat,
                    rawImageFormat,
                    pictureType,
                    typeByte.sourceOffset,
                    description.value,
                    descriptionSegment.raw,
                    payloadKind,
                    rawPictureData,
                    linkedUrl,
                    tagUnsynchronised
                )
            );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.id3v2.v22.frame :
        parseId3v22FrameEnvelope;
}


/// A normal JPG front-cover PIC frame is decoded.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',

            /*
             * 1 encoding
             * + 3 format
             * + 1 type
             * + 5 description
             * + 1 terminator
             * + 4 picture bytes
             * = 15.
             */
            0x00, 0x00, 0x0F,

            0x00,

            'J', 'P', 'G',

            0x03,

            'F', 'r', 'o', 'n', 't',
            0x00,

            0xFF, 0xD8, 0xFF, 0xD9
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22AttachedPictureFrame();

    assert(result.hasValue);

    const picture =
        result.value;

    assert(picture.sourceOffset == 100);

    assert(
        picture.descriptionEncoding ==
        Id3v22TextEncoding.latin1
    );

    assert(picture.imageFormat[] == "JPG");

    assert(
        picture.rawImageFormat.data ==
        ['J', 'P', 'G']
    );

    assert(
        picture.pictureType ==
        Id3v2PictureType.frontCover
    );

    assert(picture.pictureTypeSourceOffset == 110);
    assert(picture.description == "Front");

    assert(
        picture.payloadKind ==
        Id3v2PicturePayloadKind.binaryData
    );

    assert(!picture.linked);
    assert(picture.linkedUrl.length == 0);

    assert(
        picture.rawPictureData.data ==
        [0xFF, 0xD8, 0xFF, 0xD9]
    );
}


/// PNG pictures may have an empty description.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',
            0x00, 0x00, 0x08,

            0x00,
            'P', 'N', 'G',
            0x03,
            0x00,

            0x89, 0x50
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                200
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22AttachedPictureFrame();

    assert(result.hasValue);

    const picture =
        result.value;

    assert(picture.imageFormat[] == "PNG");
    assert(picture.description.length == 0);
    assert(picture.rawDescription.empty);

    assert(
        picture.rawPictureData.data ==
        [0x89, 0x50]
    );
}


/// Non-preferred three-byte image formats are preserved natively.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',
            0x00, 0x00, 0x07,

            0x00,
            'G', 'I', 'F',
            0x00,
            0x00,

            0x47
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22AttachedPictureFrame();

    assert(result.hasValue);

    assert(
        result.value.imageFormat[] ==
        "GIF"
    );

    assert(
        result.value.payloadKind ==
        Id3v2PicturePayloadKind.binaryData
    );

    assert(
        result.value.rawPictureData.data ==
        [0x47]
    );
}


/// Image format "-->" represents a linked picture URL.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',

            /*
             * 1 encoding
             * + 3 format
             * + 1 type
             * + 5 description
             * + 1 terminator
             * + 8 URL bytes
             * = 19.
             */
            0x00, 0x00, 0x13,

            0x00,
            '-', '-', '>',
            0x03,

            'c', 'o', 'v', 'e', 'r',
            0x00,

            'h', 't', 't', 'p', ':', '/',
            '/', 'x'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22AttachedPictureFrame();

    assert(result.hasValue);

    const picture =
        result.value;

    assert(picture.imageFormat[] == "-->");
    assert(picture.linked);

    assert(
        picture.payloadKind ==
        Id3v2PicturePayloadKind.linkedUrl
    );

    assert(picture.linkedUrl == "http://x");

    assert(
        picture.rawPictureData.data ==
        [
            'h', 't', 't', 'p', ':', '/',
            '/', 'x'
        ]
    );
}


/// BOM-less UCS-2 descriptions use the v2.2 big-endian default.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',

            /*
             * 1 encoding
             * + 3 format
             * + 1 type
             * + 2 description
             * + 2 terminator
             * + 1 picture byte
             * = 10.
             */
            0x00, 0x00, 0x0A,

            0x01,
            'P', 'N', 'G',
            0x03,

            0x00, 0x41,
            0x00, 0x00,

            0x89
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22AttachedPictureFrame();

    assert(result.hasValue);

    assert(
        result.value.descriptionEncoding ==
        Id3v22TextEncoding.utf16
    );

    assert(result.value.description == "A");
}


/// Picture-type values outside the defined ID3v2 range are rejected.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',
            0x00, 0x00, 0x06,

            0x00,
            'P', 'N', 'G',
            0x15,
            0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 610);
}


/// A truncated image-format field propagates the lower cursor error.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',
            0x00, 0x00, 0x03,

            0x00,
            'P', 'N'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 709);
}


/// A missing description terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',
            0x00, 0x00, 0x07,

            0x00,
            'P', 'N', 'G',
            0x03,
            'A', 'B'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                800
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 811);
}


/// The PIC codec rejects a different frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 900);
}


/// Whole-tag unsynchronisation preserves physical picture bytes.
unittest
{
    /*
     * Logical frame data:
     *
     *   00
     *   JPG
     *   03
     *   00
     *   FF E1
     *
     * Physical frame data:
     *
     *   00
     *   JPG
     *   03
     *   00
     *   FF 00 E1
     */
    const ubyte[] bytes =
        [
            'P', 'I', 'C',

            /*
             * Eight logical frame-data bytes.
             */
            0x00, 0x00, 0x08,

            0x00,
            'J', 'P', 'G',
            0x03,
            0x00,

            0xFF, 0x00, 0xE1
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1000
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 8);

    auto result =
        frame.value
            .decodeId3v22AttachedPictureFrame(
                true
            );

    assert(result.hasValue);

    const picture =
        result.value;

    assert(picture.effectiveUnsynchronisation);

    assert(
        picture.rawPictureData.data ==
        [0xFF, 0x00, 0xE1]
    );
}


/// Linked URLs are decoded through logical unsynchronisation.
unittest
{
    /*
     * Logical final URL byte FF is stored physically as FF 00.
     */
    const ubyte[] bytes =
        [
            'P', 'I', 'C',

            /*
             * Logical frame data:
             * encoding 1
             * format   3
             * type     1
             * desc NUL 1
             * URL      1
             * = 7.
             */
            0x00, 0x00, 0x07,

            0x00,
            '-', '-', '>',
            0x03,
            0x00,
            0xFF, 0x00
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1100
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22AttachedPictureFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.linked);

    assert(
        result.value.linkedUrl ==
        "\u00FF"
    );

    assert(
        result.value.rawPictureData.data ==
        [0xFF, 0x00]
    );
}
