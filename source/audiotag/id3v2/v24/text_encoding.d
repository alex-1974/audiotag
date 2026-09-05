/++
ID3v2.4 text-encoding markers.

Frames that support selectable text encodings begin their encoded text
region with one byte identifying ISO-8859-1, UTF-16 with BOM,
UTF-16BE without BOM, or UTF-8.

This module parses only that marker and exposes structural properties
needed by later text-string parsing.
+/
module audiotag.id3v2.v24.text_encoding;

import audiotag.core.error : ParseError, ParseErrorCode;
import audiotag.core.result : ParseResult;
import audiotag.id3v2.v24.data_cursor : Id3v24DataCursor;


/++
Text encodings defined by ID3v2.4.
+/
enum Id3v24TextEncoding : ubyte
{
    /// ISO-8859-1, encoding marker $00.
    latin1 = 0x00,

    /// UTF-16 with BOM, encoding marker $01.
    utf16 = 0x01,

    /// UTF-16 big-endian without BOM, encoding marker $02.
    utf16be = 0x02,

    /// UTF-8, encoding marker $03.
    utf8 = 0x03
}


/++
Returns whether this encoding uses 16-bit code units.

This affects terminator alignment during structural string parsing.
+/
bool usesUtf16(Id3v24TextEncoding encoding)
    @safe pure nothrow @nogc
{
    return
        encoding == Id3v24TextEncoding.utf16 ||
        encoding == Id3v24TextEncoding.utf16be;
}


/++
Returns the number of logical zero bytes in this encoding's string
terminator.

ISO-8859-1 and UTF-8 use `$00`.
UTF-16 encodings use `$00 $00`.
+/
ubyte terminatorWidth(Id3v24TextEncoding encoding)
    @safe pure nothrow @nogc
{
    return encoding.usesUtf16 ? 2 : 1;
}


/++
Parses one ID3v2.4 text-encoding marker from a logical data cursor.

Params:
    cursor = Cursor positioned at the encoding byte.

Returns:
    The parsed encoding or `invalidEncodingMarker`.

Error semantics:
    Failure leaves `cursor` unchanged.
+/
ParseResult!Id3v24TextEncoding parseId3v24TextEncoding(
    ref Id3v24DataCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe = cursor;

    auto byteResult = probe.takeByte();

    if (byteResult.hasError)
    {
        return ParseResult!Id3v24TextEncoding.failure(
            byteResult.error
        );
    }

    const decoded = byteResult.value;

    Id3v24TextEncoding encoding;

    switch (decoded.value)
    {
        case 0x00:
            encoding = Id3v24TextEncoding.latin1;
            break;

        case 0x01:
            encoding = Id3v24TextEncoding.utf16;
            break;

        case 0x02:
            encoding = Id3v24TextEncoding.utf16be;
            break;

        case 0x03:
            encoding = Id3v24TextEncoding.utf8;
            break;

        default:
            return ParseResult!Id3v24TextEncoding.failure(
                ParseError(
                    ParseErrorCode.invalidEncodingMarker,
                    decoded.sourceOffset
                )
            );
    }

    cursor = probe;

    return ParseResult!Id3v24TextEncoding.success(
        encoding
    );
}


import audiotag.core.span : ByteSpan;


/// All four ID3v2.4 text-encoding markers are accepted.
unittest
{
    foreach (marker; 0 .. 4)
    {
        const expected =
            cast(Id3v24TextEncoding) marker;

        const ubyte[] bytes =
            [cast(ubyte) marker, 0x55];

        auto cursor =
            Id3v24DataCursor(
                ByteSpan(bytes, 100),
                false
            );

        auto result =
            cursor.parseId3v24TextEncoding();

        assert(result.hasValue);
        assert(result.value == expected);

        assert(cursor.logicalPosition == 1);
        assert(cursor.physicalPosition == 1);
        assert(cursor.absoluteOffset == 101);
    }
}


/// Undefined encoding markers are rejected atomically.
unittest
{
    foreach (marker; [0x04, 0x7F, 0xFF])
    {
        const ubyte[] bytes =
            [cast(ubyte) marker, 0x55];

        auto cursor =
            Id3v24DataCursor(
                ByteSpan(bytes, 200),
                false
            );

        auto result =
            cursor.parseId3v24TextEncoding();

        assert(result.hasError);
        assert(
            result.error.code ==
            ParseErrorCode.invalidEncodingMarker
        );
        assert(result.error.offset == 200);

        assert(cursor.logicalPosition == 0);
        assert(cursor.physicalPosition == 0);
        assert(cursor.absoluteOffset == 200);
    }
}


/// Missing encoding markers propagate end-of-span atomically.
unittest
{
    const ubyte[] bytes = [];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 300),
            false
        );

    auto result =
        cursor.parseId3v24TextEncoding();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 300);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
}


/// Structural encoding properties match ID3v2.4 termination rules.
unittest
{
    assert(!Id3v24TextEncoding.latin1.usesUtf16);
    assert(Id3v24TextEncoding.utf16.usesUtf16);
    assert(Id3v24TextEncoding.utf16be.usesUtf16);
    assert(!Id3v24TextEncoding.utf8.usesUtf16);

    assert(Id3v24TextEncoding.latin1.terminatorWidth == 1);
    assert(Id3v24TextEncoding.utf16.terminatorWidth == 2);
    assert(Id3v24TextEncoding.utf16be.terminatorWidth == 2);
    assert(Id3v24TextEncoding.utf8.terminatorWidth == 1);
}


/// Encoding-marker offsets remain physical under unsynchronisation.
unittest
{
    const ubyte[] bytes =
        [0x99, 0x03, 0x55];

    const span =
        ByteSpan(bytes, 1000)
            .subspan(1, 2);

    auto cursor =
        Id3v24DataCursor(
            span,
            true
        );

    auto result =
        cursor.parseId3v24TextEncoding();

    assert(result.hasValue);
    assert(result.value == Id3v24TextEncoding.utf8);

    assert(cursor.logicalPosition == 1);
    assert(cursor.absoluteOffset == 1002);
}
