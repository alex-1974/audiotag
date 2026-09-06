/++
ID3v2.3 text-information frame decoding.

This module decodes ordinary `T***` text-information frames, excluding
the structurally different `TXXX` frame.

Unlike ID3v2.4, an ordinary ID3v2.3 text-information frame contains one
text-information field rather than a null-separated list of values.

If that text field is followed by its encoding-dependent terminator,
all subsequent bytes are ignored semantically but preserved as physical
source provenance.

Compressed or encrypted text frames remain structurally valid but
cannot yet be semantically decoded. Such frames return a successful
outcome describing the required transformation and preserving their
raw semantic payload.
+/
module audiotag.id3v2.v23.text_information;

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
Semantic availability of an ID3v2.3 text-information frame.
+/
enum Id3v23TextInformationAvailability : ubyte
{
    /// Text information was decoded successfully.
    decoded,

    /// Payload must be decompressed before semantic decoding.
    requiresDecompression,

    /// Payload must be decrypted before semantic decoding.
    requiresDecryption,

    /// Payload requires both decryption and decompression.
    requiresDecryptionAndDecompression
}


/++
Decoded ordinary ID3v2.3 text-information frame.

This type represents `T***` frames except `TXXX`.

`value` contains exactly the one ID3v2.3 text-information field.

`rawValue` contains the physical encoded bytes which contributed to
that value. It excludes any terminator but retains tag-level
unsynchronisation stuffing.

When a terminator occurred, `ignoredTrailingData` preserves every
physical source byte after that terminator. When no terminator occurred
it is an empty span positioned immediately after `rawValue`.
+/
struct Id3v23TextInformationFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Native four-character frame identifier.
    char[4] id;

    /// Text encoding declared by the frame.
    Id3v23TextEncoding encoding;

    /// The single decoded ID3v2.3 information value.
    string value;

    /// Physical encoded bytes contributing to `value`.
    ByteSpan rawValue;

    /// Physical bytes ignored after an explicit string terminator.
    ByteSpan ignoredTrailingData;

    /// Whether tag-level unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic ID3v2.3 text-information decoding.

When `availability == decoded`, `text` contains the decoded frame.

Otherwise `rawPayload` preserves the still-transformed semantic payload
after structural frame-format additions have been removed.
+/
struct Id3v23TextInformationOutcome
{
    /// Semantic availability state.
    Id3v23TextInformationAvailability availability;

    /// Decoded text-information frame when available.
    Id3v23TextInformationFrame text;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;


    /// Whether semantic text information is available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v23TextInformationAvailability.decoded;
    }
}


/++
Decodes an ordinary ID3v2.3 text-information frame.

The frame identifier must begin with `T` and must not be `TXXX`.

Compression, encryption and grouping prefixes are handled by the lower
frame-data structural layer.

Compressed or encrypted frames return a successful non-decoded outcome
because those transformations are valid ID3v2.3 features rather than
malformed input.

For an untransformed frame, the payload consists of:

    Text encoding    $xx
    Information      <text string according to encoding>

ID3v2.3 defines one information field. If an encoding-dependent
terminator occurs inside that field, the first terminator ends the
displayed information and every subsequent byte is preserved but
ignored semantically.

No generic slash-separated interpretation is performed here. Frame
specific slash semantics belong to later frame-specific or canonical
mapping logic.

Params:
    frame = Previously validated and bounded ID3v2.3 frame.
    tagUnsynchronised = Whether ID3v2.3 tag-level unsynchronisation
        applies.

Returns:
    A decoded or transformation-pending outcome, or a structured error
    for malformed text information.
+/
ParseResult!Id3v23TextInformationOutcome
decodeId3v23TextInformationFrame(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[0] != 'T' ||
        frame.header.id[] == "TXXX"
    )
    {
        return
            ParseResult!Id3v23TextInformationOutcome
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

    if (layoutResult.hasError)
    {
        return
            ParseResult!Id3v23TextInformationOutcome
                .failure(
                    layoutResult.error
                );
    }

    const layout =
        layoutResult.value;


    /*
     * Compression and encryption transform the semantic payload. The
     * lower structural layer has already removed their prefix fields,
     * so preserve exactly the remaining transformed bytes.
     */
    if (
        frame.header.compressed ||
        frame.header.encrypted
    )
    {
        Id3v23TextInformationAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v23TextInformationAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (
            frame.header.compressed
        )
        {
            availability =
                Id3v23TextInformationAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v23TextInformationAvailability
                    .requiresDecryption;
        }

        return
            ParseResult!Id3v23TextInformationOutcome
                .success(
                    Id3v23TextInformationOutcome(
                        availability,
                        Id3v23TextInformationFrame.init,
                        layout.rawPayload
                    )
                );
    }


    auto payload =
        layout.payloadCursor();


    /*
     * Every ordinary text-information frame begins with one encoding
     * marker, even when its information value is empty.
     */
    auto encodingResult =
        payload.parseId3v23TextEncoding();

    if (encodingResult.hasError)
    {
        return
            ParseResult!Id3v23TextInformationOutcome
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;


    ByteSpan rawValue;
    ByteSpan ignoredTrailingData;


    if (
        payload.empty
    )
    {
        /*
         * The encoding marker alone represents one empty information
         * value.
         */
        rawValue =
            payload.remainingRaw;

        ignoredTrailingData =
            rawValue;
    }
    else
    {
        /*
         * Search transactionally for the first encoding-dependent
         * terminator.
         */
        auto segmentResult =
            payload.takeId3v23TerminatedTextSegment(
                encoding
            );

        if (
            segmentResult.hasValue
        )
        {
            rawValue =
                segmentResult.value.raw;

            /*
             * The segment parser consumed the complete terminator.
             * Everything physically remaining belongs to the
             * specification's ignored trailing information.
             */
            ignoredTrailingData =
                payload.remainingRaw;
        }
        else if (
            segmentResult.error.code ==
            ParseErrorCode.patternNotFound
        )
        {
            /*
             * A terminator is optional for this field. The enclosing
             * frame boundary therefore defines the text extent.
             *
             * The failed segment search was atomic, so `payload` still
             * points at the first information byte.
             */
            rawValue =
                payload.remainingRaw;

            ignoredTrailingData =
                rawValue.subspan(
                    rawValue.length,
                    0
                );
        }
        else
        {
            /*
             * In particular, malformed UTF-16 code-unit alignment must
             * not be reclassified as an unterminated but valid value.
             */
            return
                ParseResult!Id3v23TextInformationOutcome
                    .failure(
                        segmentResult.error
                    );
        }
    }


    auto decoded =
        decodeId3v23TextSpan(
            rawValue,
            encoding,
            layout.effectiveUnsynchronisation
        );

    if (decoded.hasError)
    {
        return
            ParseResult!Id3v23TextInformationOutcome
                .failure(
                    decoded.error
                );
    }


    const text =
        Id3v23TextInformationFrame(
            frame.header.sourceOffset,
            frame.header.id,
            encoding,
            decoded.value,
            rawValue,
            ignoredTrailingData,
            layout.effectiveUnsynchronisation
        );


    return
        ParseResult!Id3v23TextInformationOutcome
            .success(
                Id3v23TextInformationOutcome(
                    Id3v23TextInformationAvailability.decoded,
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


/// A normal Latin-1 TIT2 frame decodes exactly one information value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            /*
             * Encoding + "Title".
             */
            0x00,
            'T', 'i', 't', 'l', 'e'
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const text =
        result.value.text;

    assert(text.sourceOffset == 100);
    assert(text.id[] == "TIT2");

    assert(
        text.encoding ==
        Id3v23TextEncoding.latin1
    );

    assert(text.value == "Title");

    assert(text.rawValue.sourceOffset == 111);
    assert(text.rawValue.length == 5);

    assert(
        text.rawValue.data ==
        ['T', 'i', 't', 'l', 'e']
    );

    assert(text.ignoredTrailingData.empty);

    assert(
        text.ignoredTrailingData.sourceOffset ==
        116
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        110
    );

    assert(
        result.value.rawPayload.length ==
        6
    );
}


/// A terminator ends the single v2.3 value and trailing bytes are ignored.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'A', 'L', 'B',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            0x00,
            'A',
            0x00,
            'X', 'Y'
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const text =
        result.value.text;

    assert(text.value == "A");

    assert(
        text.rawValue.data ==
        ['A']
    );

    assert(text.rawValue.sourceOffset == 211);

    /*
     * Encoding at 210.
     * A at 211.
     * Terminator at 212.
     * Ignored trailing bytes begin at 213.
     */
    assert(
        text.ignoredTrailingData.sourceOffset ==
        213
    );

    assert(
        text.ignoredTrailingData.data ==
        ['X', 'Y']
    );
}


/// NUL does not create a second v2.4-style value in ID3v2.3.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
            'A',
            0x00,
            'B'
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);

    assert(
        result.value.text.value ==
        "A"
    );

    assert(
        result.value.text
            .ignoredTrailingData.data ==
        ['B']
    );
}


/// Slash characters remain part of the native single information value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
            'A', '/', 'B'
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);

    assert(
        result.value.text.value ==
        "A/B"
    );

    assert(
        result.value.text.rawValue.data ==
        ['A', '/', 'B']
    );

    assert(
        result.value.text
            .ignoredTrailingData.empty
    );
}


/// An encoding marker without information represents one empty value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'C', 'O', 'N',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

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
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.text.value.length ==
        0
    );

    assert(result.value.text.rawValue.empty);

    assert(
        result.value.text.rawValue.sourceOffset ==
        511
    );
}


/// Unterminated big-endian Unicode uses the frame boundary as its extent.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            0x01,

            /*
             * Big-endian BOM + A.
             */
            0xFE, 0xFF,
            0x00, 0x41
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);

    assert(
        result.value.text.encoding ==
        Id3v23TextEncoding.utf16
    );

    assert(
        result.value.text.value ==
        "A"
    );

    assert(
        result.value.text.rawValue.data ==
        [
            0xFE, 0xFF,
            0x00, 0x41
        ]
    );

    assert(
        result.value.text
            .ignoredTrailingData.empty
    );
}


/// A Unicode terminator ends the value and preserves later physical bytes.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

            0x01,

            /*
             * Big-endian BOM + A.
             */
            0xFE, 0xFF,
            0x00, 0x41,

            /*
             * Aligned Unicode terminator.
             */
            0x00, 0x00,

            /*
             * Ignored extension byte.
             */
            0x55
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);

    const text =
        result.value.text;

    assert(text.value == "A");

    assert(
        text.rawValue.data ==
        [
            0xFE, 0xFF,
            0x00, 0x41
        ]
    );

    assert(
        text.ignoredTrailingData.data ==
        [0x55]
    );

    assert(
        text.ignoredTrailingData.sourceOffset ==
        717
    );
}


/// Malformed ignored trailing bytes do not affect the displayed value.
unittest
{
    /*
     * Once the Latin-1 information terminator has occurred, the
     * specification says all following information is ignored.
     */
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            0x00,
            'A',
            0x00,

            /*
             * Deliberately arbitrary ignored bytes.
             */
            0xFF, 0x7F
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.text.value == "A");

    assert(
        result.value.text
            .ignoredTrailingData.data ==
        [0xFF, 0x7F]
    );
}


/// ID3v2.4-only encoding markers remain invalid in v2.3 text frames.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            /*
             * UTF-8 marker is not defined in v2.3.
             */
            0x03,
            'A'
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidEncodingMarker
    );

    assert(result.error.offset == 910);
}


/// TXXX is deliberately excluded from the generic T*** decoder.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            0x00
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 1000);
}


/// Non-text frames are rejected by this semantic codec.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            0x55
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 1100);
}


/// Compressed text remains structurally valid but is not decoded yet.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',

            /*
             * Four-byte decompressed-size prefix + opaque payload.
             */
            0x00, 0x00, 0x00, 0x05,

            /*
             * Compression flag.
             */
            0x00, 0x80,

            /*
             * Decompressed size = 1.
             */
            0x00, 0x00, 0x00, 0x01,

            /*
             * Opaque compressed payload.
             */
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23TextInformationAvailability
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


/// Encrypted text remains structurally valid but is not decoded yet.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',

            /*
             * Method byte + opaque ciphertext.
             */
            0x00, 0x00, 0x00, 0x02,

            /*
             * Encryption flag.
             */
            0x00, 0x40,

            /*
             * Encryption method.
             */
            0x23,

            /*
             * Opaque encrypted payload.
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23TextInformationAvailability
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


/// Combined compression and encryption remain explicitly pending.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',

            /*
             * Decompressed size + method + opaque payload.
             */
            0x00, 0x00, 0x00, 0x06,

            /*
             * Compression + encryption.
             */
            0x00, 0xC0,

            /*
             * Decompressed size = 1.
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
                1400
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23TextInformationAvailability
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


/// Grouping identity is removed structurally before ordinary decoding.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',

            /*
             * Group byte + encoding + A.
             */
            0x00, 0x00, 0x00, 0x03,

            /*
             * Grouping identity flag.
             */
            0x00, 0x20,

            /*
             * Group symbol.
             */
            0x7A,

            /*
             * Latin-1 "A".
             */
            0x00,
            'A'
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.text.value ==
        "A"
    );

    assert(
        result.value.text.rawValue.sourceOffset ==
        1512
    );
}


/// Whole-tag unsynchronisation is reversed before Latin-1 decoding.
unittest
{
    /*
     * Logical frame data:
     *
     *   00 FF E1
     *
     * Physical frame data:
     *
     *   00 FF 00 E1
     */
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',

            /*
             * Three logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x03,

            0x00, 0x00,

            0x00,
            0xFF, 0x00,
            0xE1
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
            .decodeId3v23TextInformationFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const text =
        result.value.text;

    assert(
        text.value ==
        "\u00FF\u00E1"
    );

    assert(text.effectiveUnsynchronisation);

    /*
     * The physical stuffing zero is preserved inside rawValue.
     */
    assert(
        text.rawValue.data ==
        [
            0xFF, 0x00,
            0xE1
        ]
    );

    assert(
        text.rawValue.sourceOffset ==
        1611
    );
}


/// Stuffing before the information terminator remains part of rawValue.
unittest
{
    /*
     * Logical frame data:
     *
     *   encoding = 00
     *   value    = FF
     *   terminator = 00
     *
     * Whole-tag unsynchronisation stores:
     *
     *   00 FF 00 00
     *
     * The first zero after FF is stuffing; the second is the actual
     * string terminator.
     */
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',

            /*
             * Three logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x03,

            0x00, 0x00,

            0x00,
            0xFF, 0x00,
            0x00
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
            .decodeId3v23TextInformationFrame(
                true
            );

    assert(result.hasValue);

    const text =
        result.value.text;

    assert(
        text.value ==
        "\u00FF"
    );

    assert(
        text.rawValue.data ==
        [0xFF, 0x00]
    );

    assert(
        text.rawValue.length ==
        2
    );

    assert(
        text.ignoredTrailingData.empty
    );

    assert(
        text.ignoredTrailingData.sourceOffset ==
        1714
    );
}


/// Missing encoding markers remain structured frame-data errors.
unittest
{
    /*
     * A structurally valid frame has one byte of data, but grouping
     * consumes that byte and leaves no semantic text payload.
     */
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x20,

            0x7A
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1800
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23TextInformationFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 1811);
}


/// Incomplete Unicode information does not become a valid unterminated value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',

            /*
             * Encoding + BOM + one incomplete logical code-unit byte.
             */
            0x00, 0x00, 0x00, 0x04,

            0x00, 0x00,

            0x01,
            0xFE, 0xFF,
            0x41
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
            .decodeId3v23TextInformationFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 1913);
    assert(result.error.requested == 2);
    assert(result.error.available == 1);
}
