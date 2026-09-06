/++
ID3v2.3 user-defined text-information frame decoding.

The `TXXX` frame consists of:

- one text-encoding marker;
- one terminated description;
- one value extending to the end of the frame.

ID3v2.3 Unicode strings carry their own byte-order marks. Description
and value are therefore decoded independently and may use different
byte orders.

Compressed or encrypted frames remain structurally valid but are not
semantically decoded until the required transformation is available.

Tag-level unsynchronisation is reversed only while traversing the
already bounded physical frame-data representation.
+/
module audiotag.id3v2.v23.user_text;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

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
Semantic availability of an ID3v2.3 user-defined text frame.
+/
enum Id3v23UserTextAvailability : ubyte
{
    /// Description and value were decoded successfully.
    decoded,

    /// Payload must be decompressed before semantic decoding.
    requiresDecompression,

    /// Payload must be decrypted before semantic decoding.
    requiresDecryption,

    /// Payload requires both transformations.
    requiresDecryptionAndDecompression
}


/++
Decoded ID3v2.3 `TXXX` frame.

`rawDescription` excludes the required description terminator while
retaining physical unsynchronisation stuffing.

`rawValue` extends physically to the bounded frame-data end.
+/
struct Id3v23UserTextFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Text encoding declared by the frame.
    Id3v23TextEncoding encoding;

    /// User-defined field description.
    string description;

    /// User-defined field value.
    string value;

    /// Physical description bytes excluding its terminator.
    ByteSpan rawDescription;

    /// Physical value bytes extending to the frame boundary.
    ByteSpan rawValue;

    /// Whether ID3v2.3 tag-level unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic `TXXX` decoding.

When `availability == decoded`, `text` contains the decoded frame.

Otherwise `rawPayload` preserves the still-transformed semantic payload
after structural frame-format additions have been removed.
+/
struct Id3v23UserTextOutcome
{
    /// Semantic availability state.
    Id3v23UserTextAvailability availability;

    /// Decoded frame when available.
    Id3v23UserTextFrame text;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;


    /// Whether semantic user text is available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v23UserTextAvailability.decoded;
    }
}


/++
Decodes an ID3v2.3 user-defined text-information (`TXXX`) frame.

The payload consists of:

    Text encoding    $xx
    Description      <text according to encoding> $00 (00)
    Value            <text according to encoding>

The description terminator is mandatory.

The value occupies the remainder of the bounded semantic payload.

For Unicode encoding `$01`, every non-empty string is decoded according
to its own BOM. ID3v2.3 does not impose the ID3v2.4 same-byte-order
constraint across the two strings.

Compression, encryption and grouping additions are handled by the lower
frame-data structural layer.

Compressed or encrypted frames return a successful transformation-
pending outcome rather than a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.3 frame.
    tagUnsynchronised = Whether ID3v2.3 tag-level unsynchronisation
        applies.

Returns:
    A decoded or transformation-pending outcome, or a structured error.
+/
ParseResult!Id3v23UserTextOutcome
decodeId3v23UserTextFrame(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "TXXX"
    )
    {
        return
            ParseResult!Id3v23UserTextOutcome
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
            ParseResult!Id3v23UserTextOutcome
                .failure(
                    layoutResult.error
                );
    }

    const layout =
        layoutResult.value;


    /*
     * Compression and encryption transform the semantic payload.
     * Structural prefixes have already been removed by frame_data.d.
     */
    if (
        frame.header.compressed ||
        frame.header.encrypted
    )
    {
        Id3v23UserTextAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v23UserTextAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (
            frame.header.compressed
        )
        {
            availability =
                Id3v23UserTextAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v23UserTextAvailability
                    .requiresDecryption;
        }

        return
            ParseResult!Id3v23UserTextOutcome
                .success(
                    Id3v23UserTextOutcome(
                        availability,
                        Id3v23UserTextFrame.init,
                        layout.rawPayload
                    )
                );
    }


    auto payload =
        layout.payloadCursor();


    /*
     * TXXX always begins with one text-encoding marker.
     */
    auto encodingResult =
        payload.parseId3v23TextEncoding();

    if (
        encodingResult.hasError
    )
    {
        return
            ParseResult!Id3v23UserTextOutcome
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;


    /*
     * Unlike an ordinary T*** information value, the TXXX description
     * is explicitly required to be terminated.
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
            ParseResult!Id3v23UserTextOutcome
                .failure(
                    descriptionResult.error
                );
    }

    const descriptionSegment =
        descriptionResult.value;


    /*
     * The value is not structurally terminated. Its extent is the
     * enclosing bounded frame payload.
     */
    const rawValue =
        payload.remainingRaw;


    /*
     * Decode both text strings independently.
     *
     * This is intentionally different from the v2.4 codec: v2.3 says
     * each non-empty Unicode string begins with its own BOM and does not
     * require the two strings to share one byte order.
     */
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
            ParseResult!Id3v23UserTextOutcome
                .failure(
                    description.error
                );
    }


    auto value =
        decodeId3v23TextSpan(
            rawValue,
            encoding,
            layout.effectiveUnsynchronisation
        );

    if (
        value.hasError
    )
    {
        return
            ParseResult!Id3v23UserTextOutcome
                .failure(
                    value.error
                );
    }


    const text =
        Id3v23UserTextFrame(
            frame.header.sourceOffset,
            encoding,
            description.value,
            value.value,
            descriptionSegment.raw,
            rawValue,
            layout.effectiveUnsynchronisation
        );


    return
        ParseResult!Id3v23UserTextOutcome
            .success(
                Id3v23UserTextOutcome(
                    Id3v23UserTextAvailability.decoded,
                    text,
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


/// A Latin-1 TXXX frame decodes description and value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Encoding + "key" + terminator + "value".
             */
            0x00, 0x00, 0x00, 0x0A,

            0x00, 0x00,

            0x00,

            'k', 'e', 'y',
            0x00,

            'v', 'a', 'l', 'u', 'e'
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
            .decodeId3v23UserTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const text =
        result.value.text;

    assert(text.sourceOffset == 100);

    assert(
        text.encoding ==
        Id3v23TextEncoding.latin1
    );

    assert(text.description == "key");
    assert(text.value == "value");

    assert(
        text.rawDescription.sourceOffset ==
        111
    );

    assert(
        text.rawDescription.data ==
        ['k', 'e', 'y']
    );

    assert(
        text.rawValue.sourceOffset ==
        115
    );

    assert(
        text.rawValue.data ==
        ['v', 'a', 'l', 'u', 'e']
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        110
    );

    assert(
        result.value.rawPayload.length ==
        10
    );

    assert(!text.effectiveUnsynchronisation);
}


/// Description and value may both be empty.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Encoding + description terminator.
             */
            0x00, 0x00, 0x00, 0x02,

            0x00, 0x00,

            0x00,
            0x00
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
            .decodeId3v23UserTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const text =
        result.value.text;

    assert(text.description.length == 0);
    assert(text.value.length == 0);

    assert(text.rawDescription.empty);
    assert(text.rawDescription.sourceOffset == 211);

    assert(text.rawValue.empty);
    assert(text.rawValue.sourceOffset == 212);
}


/// A missing description terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
            'a', 'b', 'c'
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
            .decodeId3v23UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 311);
    assert(result.error.requested == 1);
    assert(result.error.available == 3);
}


/// The TXXX codec rejects ordinary text-information frames.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x00,
            'A'
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
            .decodeId3v23UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 400);
}


/// ID3v2.4-only text encoding markers remain invalid.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            /*
             * UTF-8 marker is undefined in ID3v2.3.
             */
            0x03,
            0x00
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
            .decodeId3v23UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 510);
}


/// Unicode description and value may both use little-endian UCS-2.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Encoding
             * + description BOM/A/terminator
             * + value BOM/B.
             */
            0x00, 0x00, 0x00, 0x0B,

            0x00, 0x00,

            0x01,

            /*
             * Description "A", little endian.
             */
            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

            /*
             * Value "B", little endian.
             */
            0xFF, 0xFE,
            0x42, 0x00
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
            .decodeId3v23UserTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.text.description ==
        "A"
    );

    assert(
        result.value.text.value ==
        "B"
    );
}


/// ID3v2.3 does not require TXXX strings to share byte order.
unittest
{
    /*
     * The description is little endian and the value is big endian.
     *
     * Each non-empty Unicode string has its own valid BOM, which is the
     * requirement imposed by ID3v2.3.
     */
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0B,
            0x00, 0x00,

            0x01,

            /*
             * Description "A", little endian.
             */
            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

            /*
             * Value "B", big endian.
             */
            0xFE, 0xFF,
            0x00, 0x42
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
            .decodeId3v23UserTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.text.description ==
        "A"
    );

    assert(
        result.value.text.value ==
        "B"
    );

    assert(
        result.value.text.rawDescription.data ==
        [
            0xFF, 0xFE,
            0x41, 0x00
        ]
    );

    assert(
        result.value.text.rawValue.data ==
        [
            0xFE, 0xFF,
            0x00, 0x42
        ]
    );
}


/// A non-empty Unicode description requires its own BOM.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Encoding + description unit + terminator + empty value.
             */
            0x00, 0x00, 0x00, 0x05,

            0x00, 0x00,

            0x01,

            /*
             * "A" without BOM.
             */
            0x00, 0x41,

            0x00, 0x00
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
            .decodeId3v23UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidByteOrderMark
    );

    assert(result.error.offset == 811);
}


/// A non-empty Unicode value also requires its own BOM.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Encoding
             * + empty description terminator
             * + value without BOM.
             */
            0x00, 0x00, 0x00, 0x05,

            0x00, 0x00,

            0x01,

            /*
             * Empty Unicode description.
             */
            0x00, 0x00,

            /*
             * "A" without BOM.
             */
            0x00, 0x41
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
            .decodeId3v23UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidByteOrderMark
    );

    assert(result.error.offset == 913);
}


/// An empty Unicode description and empty value are representable.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Encoding + empty Unicode description terminator.
             */
            0x00, 0x00, 0x00, 0x03,

            0x00, 0x00,

            0x01,
            0x00, 0x00
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
            .decodeId3v23UserTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.text.description.length ==
        0
    );

    assert(
        result.value.text.value.length ==
        0
    );
}


/// A BOM-prefixed empty Unicode description is also accepted.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Encoding + BOM + Unicode NULL.
             */
            0x00, 0x00, 0x00, 0x05,

            0x00, 0x00,

            0x01,

            /*
             * Little-endian BOM followed by the description terminator.
             */
            0xFF, 0xFE,
            0x00, 0x00
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
            .decodeId3v23UserTextFrame();

    assert(result.hasValue);

    assert(
        result.value.text.description.length ==
        0
    );

    assert(
        result.value.text.value.length ==
        0
    );

    assert(
        result.value.text.rawDescription.data ==
        [0xFF, 0xFE]
    );
}


/// Incomplete Unicode description code units fail structurally.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Encoding + three logical description bytes.
             */
            0x00, 0x00, 0x00, 0x04,

            0x00, 0x00,

            0x01,

            /*
             * One complete pair followed by one incomplete byte.
             */
            0xFE, 0xFF,
            0x41
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
            .decodeId3v23UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 1213);
    assert(result.error.requested == 2);
    assert(result.error.available == 1);
}


/// Compressed TXXX data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Four-byte decompressed-size prefix + opaque payload.
             */
            0x00, 0x00, 0x00, 0x05,

            /*
             * Compression.
             */
            0x00, 0x80,

            /*
             * Decompressed size = 1.
             */
            0x00, 0x00, 0x00, 0x01,

            /*
             * Opaque compressed semantic payload.
             */
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
            .decodeId3v23UserTextFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UserTextAvailability
            .requiresDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1314
    );
}


/// Encrypted TXXX data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Encryption method + opaque payload.
             */
            0x00, 0x00, 0x00, 0x02,

            /*
             * Encryption.
             */
            0x00, 0x40,

            /*
             * Method.
             */
            0x23,

            /*
             * Opaque ciphertext.
             */
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
            .decodeId3v23UserTextFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UserTextAvailability
            .requiresDecryption
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1411
    );
}


/// Combined transformation requirements remain explicit.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Decompressed size + method + opaque payload.
             */
            0x00, 0x00, 0x00, 0x06,

            /*
             * Compression + encryption.
             */
            0x00, 0xC0,

            /*
             * Decompressed size.
             */
            0x00, 0x00, 0x00, 0x01,

            /*
             * Encryption method.
             */
            0x23,

            /*
             * Opaque transformed payload.
             */
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
            .decodeId3v23UserTextFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UserTextAvailability
            .requiresDecryptionAndDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1515
    );
}


/// Grouping identity is removed before semantic TXXX decoding.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Group symbol + encoding + description terminator + value.
             */
            0x00, 0x00, 0x00, 0x04,

            /*
             * Grouping identity.
             */
            0x00, 0x20,

            /*
             * Group symbol.
             */
            0x7A,

            /*
             * Latin-1 empty description and value "A".
             */
            0x00,
            0x00,
            'A'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1600
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23UserTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.text.description.length ==
        0
    );

    assert(
        result.value.text.value ==
        "A"
    );

    assert(
        result.value.text.rawValue.sourceOffset ==
        1613
    );
}


/// Whole-tag unsynchronisation is reversed for TXXX description and value.
unittest
{
    /*
     * Logical frame data:
     *
     *   00
     *   FF 00
     *   FF E1
     *
     * Meaning:
     *
     *   encoding = Latin-1
     *   description = FF
     *   description terminator
     *   value = FF E1
     *
     * Physical representation:
     *
     *   00
     *   FF 00 00
     *   FF 00 E1
     *
     * Each FF needing protection gains its own stuffing zero.
     */
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Five logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x05,

            0x00, 0x00,

            0x00,

            /*
             * Description logical FF followed by logical terminator 00.
             */
            0xFF, 0x00,
            0x00,

            /*
             * Value logical FF E1.
             */
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
            .decodeId3v23UserTextFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const text =
        result.value.text;

    assert(
        text.description ==
        "\u00FF"
    );

    assert(
        text.value ==
        "\u00FF\u00E1"
    );

    assert(text.effectiveUnsynchronisation);

    /*
     * Both returned provenance spans retain their physical stuffing.
     */
    assert(
        text.rawDescription.data ==
        [
            0xFF, 0x00
        ]
    );

    assert(
        text.rawValue.data ==
        [
            0xFF, 0x00,
            0xE1
        ]
    );

    assert(
        text.rawDescription.sourceOffset ==
        1711
    );

    assert(
        text.rawValue.sourceOffset ==
        1714
    );
}


/// Unsynchronisation inside a Unicode BOM is handled logically.
unittest
{
    /*
     * Logical frame data:
     *
     *   01
     *   FF FE 41 00
     *   00 00
     *
     * Empty value.
     *
     * Because description BOM begins FF FE, whole-tag
     * unsynchronisation stores FF 00 FE.
     */
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',

            /*
             * Seven logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x07,

            0x00, 0x00,

            0x01,

            /*
             * Little-endian BOM with stuffing.
             */
            0xFF, 0x00,
            0xFE,

            /*
             * "A".
             */
            0x41, 0x00,

            /*
             * Description terminator.
             */
            0x00, 0x00
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
            .decodeId3v23UserTextFrame(
                true
            );

    assert(result.hasValue);

    assert(
        result.value.text.description ==
        "A"
    );

    assert(
        result.value.text.value.length ==
        0
    );

    assert(
        result.value.text.rawDescription.data ==
        [
            0xFF, 0x00,
            0xFE,
            0x41, 0x00
        ]
    );

    assert(
        result.value.text.rawValue.empty
    );

    assert(
        result.value.text.rawValue.sourceOffset ==
        1818
    );
}


/// Missing semantic payload after grouping reports the missing marker.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x01,

            /*
             * Grouping identity.
             */
            0x00, 0x20,

            /*
             * The only frame-data byte is consumed as the group symbol.
             */
            0x7A
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1900
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 1911);
}
