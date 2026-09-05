/++
ID3v2.4 encoded-text decoding.

This module converts an already bounded `Id3v24TextSegment` into a
UTF-8 D string.

Supported encodings:

- ISO-8859-1;
- UTF-8;
- UTF-16 with BOM;
- UTF-16BE without BOM.

Unsynchronisation is reversed before character decoding.

Malformed Unicode is reported with physical source offsets.
+/
module audiotag.id3v2.v24.text_decode;

import std.encoding : validLength;
import std.utf : encode;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v24.data_cursor :
    Id3v24DataCursor;

import audiotag.id3v2.v24.text_encoding :
    Id3v24TextEncoding;

import audiotag.id3v2.v24.text_segment :
    Id3v24TextSegment;


/++
Decodes one ID3v2.4 encoded text segment to UTF-8.

Params:
    segment = Previously bounded encoded text segment.
    unsynchronised = Whether unsynchronisation applies to the physical
        bytes stored in `segment.raw`.

Returns:
    A UTF-8 D string or a structured text-decoding error.

Notes:
    This semantic decoding layer may allocate.
+/
ParseResult!string decodeId3v24TextSegment(
    Id3v24TextSegment segment,
    bool unsynchronised = false
)
    @safe
{
    switch (segment.encoding)
    {
        case Id3v24TextEncoding.latin1:
            return decodeLatin1(
                segment,
                unsynchronised
            );

        case Id3v24TextEncoding.utf8:
            return decodeUtf8(
                segment,
                unsynchronised
            );

        case Id3v24TextEncoding.utf16:
            return decodeUtf16(
                segment,
                unsynchronised,
                true
            );

        case Id3v24TextEncoding.utf16be:
            return decodeUtf16(
                segment,
                unsynchronised,
                false
            );

        default:
            return ParseResult!string.failure(
                ParseError(
                    ParseErrorCode.invalidEncodingMarker,
                    segment.raw.sourceOffset
                )
            );
    }
}


/++
Decodes ISO-8859-1 code units to UTF-8.
+/
private ParseResult!string decodeLatin1(
    Id3v24TextSegment segment,
    bool unsynchronised
)
    @safe
{
    auto cursor =
        segment.textCursor(
            unsynchronised
        );

    char[] output;

    while (!cursor.empty)
    {
        auto result =
            cursor.takeByte();

        assert(result.hasValue);

        encode(
            output,
            cast(dchar) result.value.value
        );
    }

    return ParseResult!string.success(
        output.idup
    );
}


/++
Validates and returns UTF-8 logical bytes.
+/
private ParseResult!string decodeUtf8(
    Id3v24TextSegment segment,
    bool unsynchronised
)
    @safe
{
    auto cursor =
        segment.textCursor(
            unsynchronised
        );

    char[] bytes;
    size_t[] offsets;

    while (!cursor.empty)
    {
        auto result =
            cursor.takeByte();

        assert(result.hasValue);

        bytes ~=
            cast(char) result.value.value;

        offsets ~=
            result.value.sourceOffset;
    }

    const valid =
        validLength(bytes);

    if (valid != bytes.length)
    {
        assert(valid < offsets.length);

        return ParseResult!string.failure(
            ParseError(
                ParseErrorCode.invalidUnicodeSequence,
                offsets[valid]
            )
        );
    }

    return ParseResult!string.success(
        bytes.idup
    );
}


/++
Decodes UTF-16 text.

When `requiresBom` is true, non-empty text must begin with either
`FE FF` or `FF FE`.

An empty `$01` string may omit its BOM.
+/
private ParseResult!string decodeUtf16(
    Id3v24TextSegment segment,
    bool unsynchronised,
    bool requiresBom
)
    @safe
{
    auto cursor =
        segment.textCursor(
            unsynchronised
        );

    bool bigEndian = true;

    if (requiresBom)
    {
        if (cursor.empty)
        {
            return ParseResult!string.success("");
        }

        auto firstResult =
            cursor.takeByte();

        assert(firstResult.hasValue);

        const first =
            firstResult.value;

        if (cursor.empty)
        {
            return ParseResult!string.failure(
                ParseError(
                    ParseErrorCode.invalidByteOrderMark,
                    first.sourceOffset
                )
            );
        }

        auto secondResult =
            cursor.takeByte();

        assert(secondResult.hasValue);

        const second =
            secondResult.value;

        if (
            first.value == 0xFE &&
            second.value == 0xFF
        )
        {
            bigEndian = true;
        }
        else if (
            first.value == 0xFF &&
            second.value == 0xFE
        )
        {
            bigEndian = false;
        }
        else
        {
            return ParseResult!string.failure(
                ParseError(
                    ParseErrorCode.invalidByteOrderMark,
                    first.sourceOffset
                )
            );
        }
    }

    char[] output;

    while (!cursor.empty)
    {
        auto highResult =
            takeUtf16Unit(
                cursor,
                bigEndian
            );

        if (highResult.hasError)
        {
            return ParseResult!string.failure(
                highResult.error
            );
        }

        const high =
            highResult.value;

        if (
            high.value >= 0xD800 &&
            high.value <= 0xDBFF
        )
        {
            if (cursor.empty)
            {
                return ParseResult!string.failure(
                    ParseError(
                        ParseErrorCode.invalidUnicodeSequence,
                        high.sourceOffset
                    )
                );
            }

            auto lowResult =
                takeUtf16Unit(
                    cursor,
                    bigEndian
                );

            if (lowResult.hasError)
            {
                return ParseResult!string.failure(
                    lowResult.error
                );
            }

            const low =
                lowResult.value;

            if (
                low.value < 0xDC00 ||
                low.value > 0xDFFF
            )
            {
                return ParseResult!string.failure(
                    ParseError(
                        ParseErrorCode.invalidUnicodeSequence,
                        low.sourceOffset
                    )
                );
            }

            const codePoint =
                0x10000u +
                (
                    (cast(uint) high.value - 0xD800u)
                    << 10
                ) +
                (
                    cast(uint) low.value -
                    0xDC00u
                );

            encode(
                output,
                cast(dchar) codePoint
            );

            continue;
        }

        if (
            high.value >= 0xDC00 &&
            high.value <= 0xDFFF
        )
        {
            return ParseResult!string.failure(
                ParseError(
                    ParseErrorCode.invalidUnicodeSequence,
                    high.sourceOffset
                )
            );
        }

        encode(
            output,
            cast(dchar) high.value
        );
    }

    return ParseResult!string.success(
        output.idup
    );
}


/++
One decoded UTF-16 code unit together with its physical source offset.
+/
private struct Utf16Unit
{
    ushort value;
    size_t sourceOffset;
}


/++
Consumes exactly two logical bytes as one UTF-16 code unit.

Failure is atomic.
+/
private ParseResult!Utf16Unit takeUtf16Unit(
    ref Id3v24DataCursor cursor,
    bool bigEndian
)
    @safe
{
    auto probe = cursor;

    auto firstResult =
        probe.takeByte();

    if (firstResult.hasError)
    {
        return ParseResult!Utf16Unit.failure(
            firstResult.error
        );
    }

    const first =
        firstResult.value;

    auto secondResult =
        probe.takeByte();

    if (secondResult.hasError)
    {
        return ParseResult!Utf16Unit.failure(
            ParseError(
                ParseErrorCode.invalidUnicodeSequence,
                first.sourceOffset,
                2,
                1
            )
        );
    }

    const second =
        secondResult.value;

    ushort value;

    if (bigEndian)
    {
        value =
            cast(ushort)(
                (cast(ushort) first.value << 8) |
                cast(ushort) second.value
            );
    }
    else
    {
        value =
            cast(ushort)(
                (cast(ushort) second.value << 8) |
                cast(ushort) first.value
            );
    }

    cursor = probe;

    return ParseResult!Utf16Unit.success(
        Utf16Unit(
            value,
            first.sourceOffset
        )
    );
}


import audiotag.core.span : ByteSpan;

import audiotag.id3v2.v24.text_segment :
    takeId3v24TerminatedTextSegment;


/// ISO-8859-1 characters are transcoded to UTF-8.
unittest
{
    const ubyte[] bytes =
        ['A', 0xE4, 0x00];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 100),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.latin1
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasValue);
    assert(decoded.value == "A\u00E4");
}


/// Valid UTF-8 is preserved.
unittest
{
    const ubyte[] bytes =
        [0xC3, 0x84, 0x00];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 200),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf8
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasValue);
    assert(decoded.value == "\u00C4");
}


/// Malformed UTF-8 reports the physical start of the invalid sequence.
unittest
{
    const ubyte[] bytes =
        [0xC3, 0x28, 0x00];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 300),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf8
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasError);
    assert(
        decoded.error.code ==
        ParseErrorCode.invalidUnicodeSequence
    );
    assert(decoded.error.offset == 300);
}


/// UTF-16 with a big-endian BOM is decoded.
unittest
{
    const ubyte[] bytes =
        [
            0xFE, 0xFF,
            0x00, 0x41,
            0x03, 0xA9,
            0x00, 0x00
        ];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 400),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf16
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasValue);
    assert(decoded.value == "A\u03A9");
}


/// UTF-16 with a little-endian BOM is decoded.
unittest
{
    const ubyte[] bytes =
        [
            0xFF, 0xFE,
            0x41, 0x00,
            0xA9, 0x03,
            0x00, 0x00
        ];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 500),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf16
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasValue);
    assert(decoded.value == "A\u03A9");
}


/// UTF-16BE is decoded without a BOM.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x41,
            0x03, 0xA9,
            0x00, 0x00
        ];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 600),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf16be
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasValue);
    assert(decoded.value == "A\u03A9");
}


/// UTF-16 surrogate pairs produce supplementary Unicode code points.
unittest
{
    const ubyte[] bytes =
        [
            0xD8, 0x3D,
            0xDE, 0x00,
            0x00, 0x00
        ];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 700),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf16be
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasValue);
    assert(decoded.value == "\U0001F600");
}


/// A lone high surrogate is malformed Unicode.
unittest
{
    const ubyte[] bytes =
        [
            0xD8, 0x3D,
            0x00, 0x00
        ];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 800),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf16be
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasError);
    assert(
        decoded.error.code ==
        ParseErrorCode.invalidUnicodeSequence
    );
    assert(decoded.error.offset == 800);
}


/// A lone low surrogate is malformed Unicode.
unittest
{
    const ubyte[] bytes =
        [
            0xDC, 0x00,
            0x00, 0x00
        ];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 900),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf16be
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasError);
    assert(
        decoded.error.code ==
        ParseErrorCode.invalidUnicodeSequence
    );
    assert(decoded.error.offset == 900);
}


/// Non-empty UTF-16 text requires a valid BOM.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x41,
            0x00, 0x00
        ];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 1000),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf16
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasError);
    assert(
        decoded.error.code ==
        ParseErrorCode.invalidByteOrderMark
    );
    assert(decoded.error.offset == 1000);
}


/// An empty UTF-16 string may omit its BOM.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 1100),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf16
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasValue);
    assert(decoded.value.length == 0);
}


/// A BOM-only UTF-16 segment decodes as an empty string.
unittest
{
    const ubyte[] bytes =
        [
            0xFE, 0xFF,
            0x00, 0x00
        ];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 1200),
            false
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf16
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment();

    assert(decoded.hasValue);
    assert(decoded.value.length == 0);
}


/// Latin-1 decoding operates on de-unsynchronised logical bytes.
unittest
{
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0x00
        ];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 1300),
            true
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.latin1
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment(
            true
        );

    assert(decoded.hasValue);
    assert(decoded.value == "\u00FF");
}


/// UTF-16 BOM decoding also works after unsynchronisation removal.
unittest
{
    // Logical bytes:
    // FF FE | 41 00 | 00 00
    const ubyte[] bytes =
        [
            0xFF, 0x00, 0xFE,
            0x41, 0x00,
            0x00, 0x00
        ];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 1400),
            true
        );

    auto segment =
        cursor.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.utf16
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value.decodeId3v24TextSegment(
            true
        );

    assert(decoded.hasValue);
    assert(decoded.value == "A");
}
