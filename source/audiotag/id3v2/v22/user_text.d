/++
ID3v2.2 user-defined text-information frame decoding.

The `TXX` frame consists of:

- one text-encoding marker;
- one terminated description;
- one value extending to the end of the frame.

Whole-tag unsynchronisation is reversed only while traversing and decoding the
already bounded physical frame-data representation. Returned byte spans retain
the exact stored physical source bytes.

For ID3v2.2 UCS-2, description and value are decoded independently. Each may
therefore carry its own byte-order mark, while BOM-less strings use the
revision-specific deterministic big-endian default implemented by
`text_decode.d`.

This module preserves native v2.2 semantics and performs no canonical mapping.
+/
module audiotag.id3v2.v22.user_text;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

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
Decoded ID3v2.2 `TXX` frame.

`rawDescription` excludes the required description terminator while retaining
physical whole-tag-unsynchronisation stuffing.

`rawValue` extends physically to the bounded frame-data end.
+/
struct Id3v22UserTextFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Text encoding declared by the frame.
    Id3v22TextEncoding encoding;

    /// User-defined field description.
    string description;

    /// User-defined field value.
    string value;

    /// Physical description bytes excluding its terminator.
    ByteSpan rawDescription;

    /// Physical value bytes extending to the frame boundary.
    ByteSpan rawValue;

    /// Whether ID3v2.2 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes an ID3v2.2 user-defined text-information (`TXX`) frame.

The payload consists of:

    Text encoding    $xx
    Description      <text according to encoding> $00 (00)
    Value            <text according to encoding>

The description terminator is mandatory.

The value occupies the remainder of the bounded frame payload and is not
required to end in a terminator.

For UCS-2, description and value are decoded independently so an explicit BOM
on either string controls that string only. BOM-less strings use the v2.2
decoder's big-endian default.

Params:
    frame = Previously validated and bounded ID3v2.2 frame.
    tagUnsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    The decoded native `TXX` frame or a structured parse error.
+/
ParseResult!Id3v22UserTextFrame
decodeId3v22UserTextFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "TXX"
    )
    {
        return
            ParseResult!Id3v22UserTextFrame
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
     * TXX always begins with one text-encoding marker.
     */
    auto encodingResult =
        payload.parseId3v22TextEncoding();

    if (
        encodingResult.hasError
    )
    {
        return
            ParseResult!Id3v22UserTextFrame
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;


    /*
     * The description terminator is mandatory.
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
            ParseResult!Id3v22UserTextFrame
                .failure(
                    descriptionResult.error
                );
    }

    const descriptionSegment =
        descriptionResult.value;


    /*
     * The value is not structurally terminated. Its extent is the bounded
     * frame-data end.
     */
    const rawValue =
        payload.remainingRaw;


    /*
     * Decode both native strings independently.
     */
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
            ParseResult!Id3v22UserTextFrame
                .failure(
                    description.error
                );
    }


    auto value =
        decodeId3v22TextSpan(
            rawValue,
            encoding,
            tagUnsynchronised
        );

    if (
        value.hasError
    )
    {
        return
            ParseResult!Id3v22UserTextFrame
                .failure(
                    value.error
                );
    }


    return
        ParseResult!Id3v22UserTextFrame
            .success(
                Id3v22UserTextFrame(
                    frame.header.sourceOffset,
                    encoding,
                    description.value,
                    value.value,
                    descriptionSegment.raw,
                    rawValue,
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


/// A Latin-1 TXX frame decodes description and value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',

            /*
             * Encoding + "key" + terminator + "value".
             */
            0x00, 0x00, 0x0A,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserTextFrame();

    assert(result.hasValue);

    const text =
        result.value;

    assert(text.sourceOffset == 100);

    assert(
        text.encoding ==
        Id3v22TextEncoding.latin1
    );

    assert(text.description == "key");
    assert(text.value == "value");

    assert(
        text.rawDescription.sourceOffset ==
        107
    );

    assert(
        text.rawDescription.data ==
        ['k', 'e', 'y']
    );

    assert(
        text.rawValue.sourceOffset ==
        111
    );

    assert(
        text.rawValue.data ==
        ['v', 'a', 'l', 'u', 'e']
    );

    assert(!text.effectiveUnsynchronisation);
}


/// Description and value may both be empty.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',

            /*
             * Encoding + description terminator.
             */
            0x00, 0x00, 0x02,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserTextFrame();

    assert(result.hasValue);

    const text =
        result.value;

    assert(text.description.length == 0);
    assert(text.value.length == 0);

    assert(text.rawDescription.empty);
    assert(text.rawDescription.sourceOffset == 207);

    assert(text.rawValue.empty);
    assert(text.rawValue.sourceOffset == 208);
}


/// A missing description terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',
            0x00, 0x00, 0x04,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 307);
    assert(result.error.requested == 1);
    assert(result.error.available == 3);
}


/// The TXX codec rejects ordinary text-information frames.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x02,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 400);
}


/// Undefined text-encoding markers remain invalid.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',
            0x00, 0x00, 0x02,

            0x02,
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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 506);
}


/// BOM-less UCS-2 description and value use big-endian decoding independently.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',

            /*
             * Encoding
             * + description "A"
             * + terminator
             * + value "B".
             */
            0x00, 0x00, 0x09,

            0x01,

            0x00, 0x41,
            0x00, 0x00,

            0x00, 0x42,

            /*
             * One more UCS-2 value code unit: ä.
             */
            0x00, 0xE4
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
            .decodeId3v22UserTextFrame();

    assert(result.hasValue);

    const text =
        result.value;

    assert(
        text.encoding ==
        Id3v22TextEncoding.utf16
    );

    assert(text.description == "A");
    assert(text.value == "B\u00E4");

    assert(
        text.rawDescription.data ==
        [0x00, 0x41]
    );

    assert(
        text.rawValue.data ==
        [
            0x00, 0x42,
            0x00, 0xE4
        ]
    );
}


/// Description and value may explicitly use different byte orders.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',

            /*
             * Encoding
             * + description LE BOM/A
             * + aligned terminator
             * + value BE BOM/B.
             *
             * 1 + 4 + 2 + 4 = 11 logical frame-data bytes.
             */
            0x00, 0x00, 0x0B,

            0x01,

            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserTextFrame();

    assert(result.hasValue);

    assert(result.value.description == "A");
    assert(result.value.value == "B");
}


/// Whole-tag unsynchronisation preserves physical bytes in both fields.
unittest
{
    /*
     * Logical payload:
     *
     *   00
     *   FF
     *   00
     *   FF
     *
     * Physical payload:
     *
     *   00
     *   FF 00
     *   00
     *   FF 00
     */
    const ubyte[] bytes =
        [
            'T', 'X', 'X',

            /*
             * Logical frame-data length = 4.
             */
            0x00, 0x00, 0x04,

            0x00,

            0xFF, 0x00,
            0x00,

            0xFF, 0x00
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                800
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 4);

    /*
     * Four logical payload bytes occupy six physical bytes.
     */
    assert(frame.value.data.length == 6);

    auto result =
        frame.value
            .decodeId3v22UserTextFrame(
                true
            );

    assert(result.hasValue);

    const text =
        result.value;

    assert(text.effectiveUnsynchronisation);

    assert(text.description == "\u00FF");
    assert(text.value == "\u00FF");

    assert(
        text.rawDescription.data ==
        [0xFF, 0x00]
    );

    assert(
        text.rawValue.data ==
        [0xFF, 0x00]
    );
}


/// An incomplete UCS-2 description code unit is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',
            0x00, 0x00, 0x02,

            0x01,
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
            .decodeId3v22UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 907);
    assert(result.error.requested == 2);
    assert(result.error.available == 1);
}


/// An odd-length UCS-2 value is rejected by semantic decoding.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',
            0x00, 0x00, 0x04,

            0x01,

            /*
             * Empty description terminator.
             */
            0x00, 0x00,

            /*
             * Incomplete value.
             */
            0x41
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1000
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidUnicodeSequence
    );

    assert(result.error.offset == 1009);
    assert(result.error.requested == 2);
    assert(result.error.available == 1);
}
