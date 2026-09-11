/++
ID3v2.3 attached-picture frame decoding.

An `APIC` frame contains:

- one text-encoding marker;
- one null-terminated ISO-8859-1 MIME type;
- one picture-type byte;
- one terminated description using the selected encoding;
- binary picture data or, for MIME type `"-->"`, a linked URL.

Physical picture bytes are preserved exactly as stored. ID3v2.3
whole-tag unsynchronisation is represented separately so later consumers
can reconstruct the logical byte stream without losing physical source
provenance.

For encoding `$01`, the non-empty Unicode description carries its own
byte-order mark and is decoded using the strict ID3v2.3 UCS-2 rules.

Compressed or encrypted frames remain structurally valid but cannot yet
be semantically decoded.
+/
module audiotag.id3v2.v23.attached_picture;

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

import audiotag.id3v2.v23.frame :
    Id3v23FrameEnvelope;

import audiotag.id3v2.v23.frame_data :
    parseId3v23FrameDataLayout;

import audiotag.id3v2.v23.text_decode :
    decodeId3v23TextSpan;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding,
    parseId3v23TextEncoding;

import audiotag.id3v2.v23.text_segment :
    takeId3v23TerminatedTextSegment;


/++
Backward-compatible ID3v2.3 name for the shared ID3v2 picture type.
+/
alias Id3v23PictureType =
    Id3v2PictureType;


/++
Backward-compatible ID3v2.3 name for the shared picture payload kind.
+/
alias Id3v23PicturePayloadKind =
    Id3v2PicturePayloadKind;


/++
Semantic availability of an ID3v2.3 attached-picture frame.
+/
enum Id3v23AttachedPictureAvailability : ubyte
{
    /// APIC semantic data was decoded.
    decoded,

    /// Payload must be decompressed first.
    requiresDecompression,

    /// Payload must be decrypted first.
    requiresDecryption,

    /// Payload requires both transformations.
    requiresDecryptionAndDecompression
}


/++
Decoded ID3v2.3 `APIC` frame.
+/
struct Id3v23AttachedPictureFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Encoding used by the description.
    Id3v23TextEncoding descriptionEncoding;

    /// MIME type exactly as decoded from its ISO-8859-1 bytes.
    string mimeType;

    /// Physical MIME bytes excluding the null terminator.
    ByteSpan rawMimeType;

    /// Declared picture type.
    Id3v23PictureType pictureType;

    /// Absolute source offset of the logical picture-type byte.
    size_t pictureTypeSourceOffset;

    /// Decoded content description.
    string description;

    /// Physical description bytes excluding its terminator.
    ByteSpan rawDescription;

    /// Whether the final payload is embedded binary data or a URL.
    Id3v23PicturePayloadKind payloadKind;

    /// Physical final payload bytes extending to the frame boundary.
    ByteSpan rawPictureData;

    /// Decoded ISO-8859-1 URL when `payloadKind == linkedUrl`.
    string linkedUrl;

    /// Whether ID3v2.3 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;


    /// Whether this APIC frame refers to an external image.
    @property
    bool linked() const
        @safe pure nothrow @nogc
    {
        return
            payloadKind ==
            Id3v23PicturePayloadKind.linkedUrl;
    }
}


/++
Outcome of attempting semantic APIC decoding.
+/
struct Id3v23AttachedPictureOutcome
{
    /// Semantic availability.
    Id3v23AttachedPictureAvailability availability;

    /// Decoded APIC frame when available.
    Id3v23AttachedPictureFrame picture;

    /// Raw semantic payload after structural frame-format additions.
    ByteSpan rawPayload;


    /// Whether semantic APIC data is available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v23AttachedPictureAvailability.decoded;
    }
}


/++
Decodes an ID3v2.3 attached-picture (`APIC`) frame.

The semantic payload has the form:

    Text encoding   $xx
    MIME type       <ISO-8859-1 text> $00
    Picture type    $xx
    Description     <text according to encoding> $00 (00)
    Picture data    <binary data>

The MIME type and physical final payload are preserved exactly. No
attempt is made here to decode JPEG, PNG or other image formats.

MIME type `"-->"` changes the final field from embedded binary image
bytes to an ISO-8859-1 URL extending to the frame boundary.

Picture-type values outside the ID3v2.3-defined range `$00` through
`$14` are rejected in strict decoding.

Compression, encryption and grouping additions are handled by the lower
frame-data structural layer.

Compressed or encrypted frames return a successful transformation-
pending outcome rather than a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.3 frame.
    tagUnsynchronised = Whether ID3v2.3 whole-tag unsynchronisation
        applies.

Returns:
    Decoded or transformation-pending APIC outcome, or a structured
    parsing/text error.
+/
ParseResult!Id3v23AttachedPictureOutcome
decodeId3v23AttachedPictureFrame(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "APIC"
    )
    {
        return
            ParseResult!Id3v23AttachedPictureOutcome
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }


    auto layoutResult =
        frame.parseId3v23FrameDataLayout(
            tagUnsynchronised
        );

    if (
        layoutResult.hasError
    )
    {
        return
            ParseResult!Id3v23AttachedPictureOutcome
                .failure(
                    layoutResult.error
                );
    }

    const layout =
        layoutResult.value;


    /*
     * Compression and encryption transform the semantic APIC payload.
     * frame_data.d has already consumed the corresponding structural
     * prefixes.
     */
    if (
        frame.header.compressed ||
        frame.header.encrypted
    )
    {
        Id3v23AttachedPictureAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v23AttachedPictureAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (
            frame.header.compressed
        )
        {
            availability =
                Id3v23AttachedPictureAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v23AttachedPictureAvailability
                    .requiresDecryption;
        }

        return
            ParseResult!Id3v23AttachedPictureOutcome
                .success(
                    Id3v23AttachedPictureOutcome(
                        availability,
                        Id3v23AttachedPictureFrame.init,
                        layout.rawPayload
                    )
                );
    }


    auto payload =
        layout.payloadCursor();


    /*
     * The encoding marker controls the description only.
     */
    auto encodingResult =
        payload.parseId3v23TextEncoding();

    if (
        encodingResult.hasError
    )
    {
        return
            ParseResult!Id3v23AttachedPictureOutcome
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;


    /*
     * MIME type is always an ISO-8859-1 terminated string.
     */
    auto mimeResult =
        payload.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    if (
        mimeResult.hasError
    )
    {
        return
            ParseResult!Id3v23AttachedPictureOutcome
                .failure(
                    mimeResult.error
                );
    }

    const mimeSegment =
        mimeResult.value;


    auto mime =
        decodeId3v23TextSpan(
            mimeSegment.raw,
            Id3v23TextEncoding.latin1,
            layout.effectiveUnsynchronisation
        );

    if (
        mime.hasError
    )
    {
        return
            ParseResult!Id3v23AttachedPictureOutcome
                .failure(
                    mime.error
                );
    }


    /*
     * Picture type is one logical byte. Its source offset is retained
     * from the logical cursor primitive.
     */
    auto typeResult =
        payload.takeByte();

    if (
        typeResult.hasError
    )
    {
        return
            ParseResult!Id3v23AttachedPictureOutcome
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
            ParseResult!Id3v23AttachedPictureOutcome
                .failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        typeByte.sourceOffset
                    )
                );
    }

    const pictureType =
        cast(Id3v23PictureType)
            typeByte.value;


    /*
     * Description is mandatory as a field, but may be empty.
     * Its terminator is encoding-dependent.
     */
    auto descriptionResult =
        payload.takeId3v23TerminatedTextSegment(
            encoding
        );

    if (
        descriptionResult.hasError
    )
    {
        return
            ParseResult!Id3v23AttachedPictureOutcome
                .failure(
                    descriptionResult.error
                );
    }

    const descriptionSegment =
        descriptionResult.value;


    auto description =
        decodeId3v23TextSpan(
            descriptionSegment.raw,
            encoding,
            layout.effectiveUnsynchronisation
        );

    if (
        description.hasError
    )
    {
        return
            ParseResult!Id3v23AttachedPictureOutcome
                .failure(
                    description.error
                );
    }


    /*
     * The final field consumes the remainder of the bounded semantic
     * payload. For embedded pictures these bytes remain opaque here.
     */
    const rawPictureData =
        payload.remainingRaw;

    Id3v23PicturePayloadKind payloadKind =
        Id3v23PicturePayloadKind.binaryData;

    string linkedUrl;


    /*
     * ID3v2.3 reserves MIME type "-->" for an external image URL.
     *
     * URLs are always ISO-8859-1 in ID3v2.3 and extend to the payload
     * boundary without an additional APIC-specific terminator.
     */
    if (
        mime.value ==
        "-->"
    )
    {
        payloadKind =
            Id3v23PicturePayloadKind.linkedUrl;

        auto url =
            decodeId3v23TextSpan(
                rawPictureData,
                Id3v23TextEncoding.latin1,
                layout.effectiveUnsynchronisation
            );

        if (
            url.hasError
        )
        {
            return
                ParseResult!Id3v23AttachedPictureOutcome
                    .failure(
                        url.error
                    );
        }

        linkedUrl =
            url.value;
    }


    const picture =
        Id3v23AttachedPictureFrame(
            frame.header.sourceOffset,
            encoding,
            mime.value,
            mimeSegment.raw,
            pictureType,
            typeByte.sourceOffset,
            description.value,
            descriptionSegment.raw,
            payloadKind,
            rawPictureData,
            linkedUrl,
            layout.effectiveUnsynchronisation
        );


    return
        ParseResult!Id3v23AttachedPictureOutcome
            .success(
                Id3v23AttachedPictureOutcome(
                    Id3v23AttachedPictureAvailability.decoded,
                    picture,
                    layout.rawPayload
                )
            );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.id3v2.v23.data_cursor :
        Id3v23DataCursor;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;
}


/// A normal JPEG front-cover APIC frame is decoded.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x17,
            0x00, 0x00,

            /*
             * Latin-1 description encoding.
             */
            0x00,

            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g',
            0x00,

            /*
             * Front cover.
             */
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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const picture =
        result.value.picture;

    assert(picture.sourceOffset == 100);

    assert(
        picture.descriptionEncoding ==
        Id3v23TextEncoding.latin1
    );

    assert(
        picture.mimeType ==
        "image/jpeg"
    );

    assert(
        picture.rawMimeType.sourceOffset ==
        111
    );

    assert(
        picture.rawMimeType.data ==
        [
            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g'
        ]
    );

    assert(
        picture.pictureType ==
        Id3v23PictureType.frontCover
    );

    assert(
        picture.pictureTypeSourceOffset ==
        122
    );

    assert(
        picture.description ==
        "Front"
    );

    assert(
        picture.rawDescription.sourceOffset ==
        123
    );

    assert(
        picture.rawDescription.data ==
        ['F', 'r', 'o', 'n', 't']
    );

    assert(
        picture.payloadKind ==
        Id3v23PicturePayloadKind.binaryData
    );

    assert(!picture.linked);

    assert(
        picture.rawPictureData.sourceOffset ==
        129
    );

    assert(
        picture.rawPictureData.data ==
        [
            0xFF, 0xD8,
            0xFF, 0xD9
        ]
    );

    assert(
        picture.linkedUrl.length ==
        0
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        110
    );

    assert(
        result.value.rawPayload.length ==
        23
    );

    assert(
        !picture.effectiveUnsynchronisation
    );
}


/// An empty description is valid.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x0F,
            0x00, 0x00,

            0x00,

            'i', 'm', 'a', 'g', 'e', '/',
            'p', 'n', 'g',
            0x00,

            0x03,

            /*
             * Empty Latin-1 description.
             */
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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.picture.description.length ==
        0
    );

    assert(
        result.value.picture.mimeType ==
        "image/png"
    );

    assert(
        result.value.picture.rawPictureData.data ==
        [0x89, 0x50]
    );
}


/// MIME media-type prefixes are preserved exactly as stored.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

            0x00,

            /*
             * ID3v2.3 permits the media-type name to be omitted;
             * "image/" is then implied semantically.
             *
             * The native decoder preserves exactly what was stored.
             */
            'p', 'n', 'g',
            0x00,

            0x03,

            0x00,

            0x89
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasValue);

    assert(
        result.value.picture.mimeType ==
        "png"
    );
}


/// MIME type "-->" represents a linked image URL.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x14,
            0x00, 0x00,

            0x00,

            '-', '-', '>',
            0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const picture =
        result.value.picture;

    assert(picture.linked);

    assert(
        picture.payloadKind ==
        Id3v23PicturePayloadKind.linkedUrl
    );

    assert(
        picture.mimeType ==
        "-->"
    );

    assert(
        picture.description ==
        "cover"
    );

    assert(
        picture.linkedUrl ==
        "http://x"
    );

    assert(
        picture.rawPictureData.data ==
        [
            'h', 't', 't', 'p', ':', '/',
            '/', 'x'
        ]
    );
}


/// Linked-image URLs remain ISO-8859-1 regardless of description encoding.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',

            /*
             * Encoding
             * + "-->" + NUL
             * + type
             * + empty Unicode description terminator
             * + two ISO-8859-1 URL bytes.
             */
            0x00, 0x00, 0x00, 0x0A,

            0x00, 0x00,

            0x01,

            '-', '-', '>',
            0x00,

            0x03,

            /*
             * Empty Unicode description.
             */
            0x00, 0x00,

            'x',
            0xE9
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasValue);

    assert(
        result.value.picture.descriptionEncoding ==
        Id3v23TextEncoding.utf16
    );

    assert(
        result.value.picture.description.length ==
        0
    );

    assert(
        result.value.picture.linkedUrl ==
        "x\u00E9"
    );
}


/// Undefined picture-type values are rejected.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x00,

            'x',
            0x00,

            /*
             * First undefined picture-type value.
             */
            0x15,

            0x00,
            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(
        result.error.offset ==
        613
    );
}


/// A missing MIME terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,

            'j', 'p', 'g'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(
        result.error.offset ==
        711
    );
}


/// A missing description terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x07,
            0x00, 0x00,

            0x00,

            'x',
            0x00,

            0x03,

            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                800
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(
        result.error.offset ==
        814
    );
}


/// A non-empty Unicode description requires its own BOM.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',

            /*
             * Encoding + MIME + type + description + terminator.
             */
            0x00, 0x00, 0x00, 0x08,

            0x00, 0x00,

            0x01,

            'x',
            0x00,

            0x03,

            /*
             * "A" without a BOM.
             */
            0x00, 0x41,

            0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidByteOrderMark
    );

    assert(
        result.error.offset ==
        914
    );
}


/// ID3v2.4-only description encoding markers remain invalid.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            /*
             * UTF-8 is undefined as an ID3v2.3 text-encoding marker.
             */
            0x03
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1000
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(
        result.error.offset ==
        1010
    );
}


/// The APIC codec rejects a different frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1100
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(
        result.error.offset ==
        1100
    );
}


/// Compressed APIC data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',

            /*
             * Four-byte decompressed-size prefix + opaque payload.
             */
            0x00, 0x00, 0x00, 0x05,

            0x00, 0x80,

            0x00, 0x00, 0x00, 0x01,
            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1200
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23AttachedPictureAvailability
            .requiresDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1214
    );
}


/// Encrypted APIC data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x02,

            0x00, 0x40,

            0x23,
            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1300
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23AttachedPictureAvailability
            .requiresDecryption
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1311
    );
}


/// Combined APIC transformations remain explicit.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x06,

            0x00, 0xC0,

            0x00, 0x00, 0x00, 0x01,
            0x23,
            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1400
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23AttachedPictureAvailability
            .requiresDecryptionAndDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1415
    );
}


/// Grouping identity is removed before APIC semantic decoding.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',

            /*
             * Group symbol plus six-byte semantic APIC payload.
             */
            0x00, 0x00, 0x00, 0x07,

            0x00, 0x20,

            /*
             * Group symbol.
             */
            0x7A,

            0x00,

            'x',
            0x00,

            0x03,

            0x00,

            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1500
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const picture =
        result.value.picture;

    assert(
        picture.mimeType ==
        "x"
    );

    assert(
        picture.pictureType ==
        Id3v23PictureType.frontCover
    );

    assert(
        picture.description.length ==
        0
    );

    assert(
        picture.rawPictureData.data ==
        [0xAA]
    );

    assert(
        picture.rawPictureData.sourceOffset ==
        1516
    );
}


/// Whole-tag unsynchronisation preserves physical picture provenance.
unittest
{
    /*
     * Logical semantic APIC payload:
     *
     *   00
     *   x 00
     *   03
     *   d FF 00
     *   FF E1 FF
     *
     * Physical representation:
     *
     *   00
     *   x 00
     *   03
     *   d FF 00 00
     *   FF 00 E1 FF
     *
     * In the description the first zero after FF is stuffing and the
     * second is the actual terminator.
     */
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',

            /*
             * Ten logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x0A,

            0x00, 0x00,

            0x00,

            'x',
            0x00,

            0x03,

            'd',
            0xFF, 0x00,
            0x00,

            /*
             * Logical binary picture bytes FF E1 FF.
             */
            0xFF, 0x00,
            0xE1,
            0xFF
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1600
            ),
            true
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const picture =
        result.value.picture;

    assert(
        picture.description ==
        "d\u00FF"
    );

    assert(
        picture.effectiveUnsynchronisation
    );

    assert(
        picture.rawDescription.sourceOffset ==
        1614
    );

    assert(
        picture.rawDescription.data ==
        [
            'd',
            0xFF, 0x00
        ]
    );

    /*
     * Binary data remains physical provenance; it is not eagerly
     * de-unsynchronised or interpreted as an image format here.
     */
    assert(
        picture.rawPictureData.sourceOffset ==
        1618
    );

    assert(
        picture.rawPictureData.data ==
        [
            0xFF, 0x00,
            0xE1,
            0xFF
        ]
    );
}


/// Whole-tag unsynchronisation is reversed when APIC carries a linked URL.
unittest
{
    /*
     * Logical URL:
     *
     *   x FF E1
     *
     * Physical URL:
     *
     *   x FF 00 E1
     */
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',

            /*
             * Ten logical bytes:
             * encoding + "-->" + NUL + type + desc NUL + URL.
             *
             * The physical unsynchronisation stuffing byte is not part
             * of the logical ID3v2.3 frame size.
             */
            0x00, 0x00, 0x00, 0x0A,

            0x00, 0x00,

            0x00,

            '-', '-', '>',
            0x00,

            0x03,

            0x00,

            'x',
            0xFF, 0x00,
            0xE1
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1700
            ),
            true
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const picture =
        result.value.picture;

    assert(picture.linked);

    assert(
        picture.linkedUrl ==
        "x\u00FF\u00E1"
    );

    assert(
        picture.rawPictureData.data ==
        [
            'x',
            0xFF, 0x00,
            0xE1
        ]
    );

    assert(
        picture.effectiveUnsynchronisation
    );
}


/// Unsynchronisation inside a Unicode description BOM is handled logically.
unittest
{
    /*
     * Logical semantic APIC payload:
     *
     *   01
     *   x 00
     *   03
     *   FF FE 41 00
     *   00 00
     *   AA
     *
     * The little-endian BOM is stored physically as FF 00 FE.
     */
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',

            /*
             * Eleven logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x0B,

            0x00, 0x00,

            0x01,

            'x',
            0x00,

            0x03,

            0xFF, 0x00,
            0xFE,

            0x41, 0x00,

            0x00, 0x00,

            0xAA
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1800
            ),
            true
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v23AttachedPictureFrame(
                true
            );

    assert(result.hasValue);

    const picture =
        result.value.picture;

    assert(
        picture.description ==
        "A"
    );

    assert(
        picture.rawDescription.data ==
        [
            0xFF, 0x00,
            0xFE,
            0x41, 0x00
        ]
    );

    assert(
        picture.rawPictureData.data ==
        [0xAA]
    );
}
