/++
ID3v2.2 text-information frame decoding.

This module decodes ordinary `T**` text-information frames, excluding the
structurally different `TXX` frame.

An ordinary ID3v2.2 text-information frame contains one text-information
field. If that field is followed by its encoding-dependent terminator, every
subsequent byte is ignored semantically but preserved as physical source
provenance.

Whole-tag unsynchronisation is reversed only while traversing and decoding the
payload. Returned spans preserve the original physical source representation.

No frame-specific slash interpretation is performed here. Such semantics
belong to later frame-specific or canonical mapping layers.


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
module audiotag.id3v2.v22.text_information;

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
Decoded ordinary ID3v2.2 text-information frame.

This type represents `T**` frames except `TXX`.

`value` contains exactly the one native text-information field.

`rawValue` contains the physical encoded bytes which contributed to that
value. It excludes an explicit terminator but retains any whole-tag
unsynchronisation stuffing.

When a terminator occurs, `ignoredTrailingData` preserves every physical byte
after that terminator. When no terminator occurs it is an empty span positioned
immediately after `rawValue`.
+/
struct Id3v22TextInformationFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Native three-character ID3v2.2 frame identifier.
    char[3] id;

    /// Text encoding declared by the frame.
    Id3v22TextEncoding encoding;

    /// The single decoded ID3v2.2 information value.
    string value;

    /// Physical encoded bytes contributing to `value`.
    ByteSpan rawValue;

    /// Physical bytes ignored after an explicit string terminator.
    ByteSpan ignoredTrailingData;

    /// Whether whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes an ordinary ID3v2.2 text-information frame.

The frame identifier must begin with `T` and must not be `TXX`.

The payload consists of:

    Text encoding    $xx
    Information      <text string according to encoding>

ID3v2.2 defines one information field. If an encoding-dependent terminator
occurs inside that field, the first terminator ends the displayed information
and every subsequent byte is preserved but ignored semantically.

No generic slash-separated interpretation is performed here.

Params:
    frame = Previously validated and bounded ID3v2.2 frame.
    tagUnsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    The decoded native text-information frame, or a structured error for
    malformed input.
+/
ParseResult!Id3v22TextInformationFrame
decodeId3v22TextInformationFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[0] != 'T' ||
        frame.header.id[] == "TXX"
    )
    {
        return
            ParseResult!Id3v22TextInformationFrame
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
     * Every ordinary text-information frame begins with one encoding marker,
     * even when its information value is empty.
     */
    auto encodingResult =
        payload.parseId3v22TextEncoding();

    if (encodingResult.hasError)
    {
        return
            ParseResult!Id3v22TextInformationFrame
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
         * The encoding marker alone represents one empty information value.
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
            payload.takeId3v22TerminatedTextSegment(
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
             * Everything physically remaining is ignored semantically.
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
             * A terminator is optional for this field. The enclosing frame
             * boundary therefore defines the text extent.
             *
             * The failed segment search was atomic, so `payload` still points
             * at the first information byte.
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
             * In particular, malformed UCS-2 code-unit alignment must not be
             * reclassified as an unterminated but valid value.
             */
            return
                ParseResult!Id3v22TextInformationFrame
                    .failure(
                        segmentResult.error
                    );
        }
    }


    auto decoded =
        decodeId3v22TextSpan(
            rawValue,
            encoding,
            tagUnsynchronised
        );

    if (decoded.hasError)
    {
        return
            ParseResult!Id3v22TextInformationFrame
                .failure(
                    decoded.error
                );
    }


    return
        ParseResult!Id3v22TextInformationFrame
            .success(
                Id3v22TextInformationFrame(
                    frame.header.sourceOffset,
                    frame.header.id,
                    encoding,
                    decoded.value,
                    rawValue,
                    ignoredTrailingData,
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


/// A normal Latin-1 TT2 frame decodes exactly one information value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x06,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22TextInformationFrame();

    assert(result.hasValue);

    const text =
        result.value;

    assert(text.sourceOffset == 100);
    assert(text.id[] == "TT2");

    assert(
        text.encoding ==
        Id3v22TextEncoding.latin1
    );

    assert(text.value == "Title");

    assert(text.rawValue.sourceOffset == 107);
    assert(text.rawValue.length == 5);

    assert(
        text.rawValue.data ==
        ['T', 'i', 't', 'l', 'e']
    );

    assert(text.ignoredTrailingData.empty);
    assert(text.ignoredTrailingData.sourceOffset == 112);
    assert(!text.effectiveUnsynchronisation);
}


/// A terminator ends the native value and preserves ignored trailing bytes.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'A', 'L',
            0x00, 0x00, 0x05,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22TextInformationFrame();

    assert(result.hasValue);

    const text =
        result.value;

    assert(text.value == "A");

    assert(
        text.rawValue.data ==
        ['A']
    );

    assert(text.rawValue.sourceOffset == 207);

    /*
     * Encoding at 206.
     * A at 207.
     * Terminator at 208.
     * Ignored trailing bytes begin at 209.
     */
    assert(text.ignoredTrailingData.sourceOffset == 209);

    assert(
        text.ignoredTrailingData.data ==
        ['X', 'Y']
    );
}


/// A zero byte never creates a second text value in ID3v2.2.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'P', '1',
            0x00, 0x00, 0x04,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.value == "A");

    assert(
        result.value
            .ignoredTrailingData.data ==
        ['B']
    );
}


/// Slash characters remain part of the native information value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'P', '1',
            0x00, 0x00, 0x04,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.value == "A/B");

    assert(
        result.value.rawValue.data ==
        ['A', '/', 'B']
    );

    assert(result.value.ignoredTrailingData.empty);
}


/// An encoding marker without text represents one empty information value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'C', 'O',
            0x00, 0x00, 0x01,

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
            .decodeId3v22TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.value.length == 0);

    assert(result.value.rawValue.empty);
    assert(result.value.rawValue.sourceOffset == 507);

    assert(result.value.ignoredTrailingData.empty);
    assert(result.value.ignoredTrailingData.sourceOffset == 507);
}


/// BOM-less UCS-2 text uses the established ID3v2.2 decoder semantics.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x05,

            0x01,
            0x00, 0x41,
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
            .decodeId3v22TextInformationFrame();

    assert(result.hasValue);

    assert(
        result.value.encoding ==
        Id3v22TextEncoding.utf16
    );

    assert(result.value.value == "A\u00E4");
    assert(result.value.rawValue.sourceOffset == 607);
    assert(result.value.rawValue.length == 4);
}


/// UCS-2 termination is aligned and trailing data remains physically exact.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x08,

            0x01,

            0x00, 0x41,
            0x00, 0x00,

            0x12, 0x34, 0x56
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
            .decodeId3v22TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.value == "A");

    assert(
        result.value.rawValue.data ==
        [0x00, 0x41]
    );

    assert(result.value.rawValue.sourceOffset == 707);

    assert(
        result.value.ignoredTrailingData.data ==
        [0x12, 0x34, 0x56]
    );

    assert(
        result.value
            .ignoredTrailingData.sourceOffset ==
        711
    );
}


/// Whole-tag unsynchronisation preserves physical stuffing in provenance.
unittest
{
    /*
     * Logical frame:
     *
     *   TT2 size = 2
     *   encoding = 00
     *   value    = FF
     *
     * Stored physical payload is 00 FF 00 because FF is unsynchronised.
     */
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x02,

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

    assert(frame.value.header.size == 2);
    assert(frame.value.data.sourceOffset == 806);
    assert(frame.value.data.length == 3);

    auto result =
        frame.value
            .decodeId3v22TextInformationFrame(
                true
            );

    assert(result.hasValue);

    const text =
        result.value;

    assert(text.effectiveUnsynchronisation);
    assert(text.value == "\u00FF");

    assert(
        text.rawValue.data ==
        [0xFF, 0x00]
    );

    assert(text.rawValue.sourceOffset == 807);
    assert(text.rawValue.length == 2);
    assert(text.ignoredTrailingData.empty);
}


/// TXX is structurally different and is rejected by the ordinary codec.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',
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
            .decodeId3v22TextInformationFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 900);
}


/// Non-text frame identifiers are rejected at the frame header offset.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'A', 'R',
            0x00, 0x00, 0x01,
            'x'
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
            .decodeId3v22TextInformationFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 1000);
}


/// Undefined text-encoding markers are propagated as structured errors.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x02,

            0x02,
            'A'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1100
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22TextInformationFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 1106);
}


/// Malformed odd-length UCS-2 text is not accepted as merely unterminated.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x04,

            0x01,
            0x00, 0x41,
            0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1200
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22TextInformationFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 1209);
    assert(result.error.requested == 2);
    assert(result.error.available == 1);
}
