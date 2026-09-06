/++
ID3v2.3 text-encoding markers.

Frames that support selectable text encodings begin their encoded text
region with one byte identifying either:

- ISO-8859-1;
- 16-bit Unicode with BOM.

ID3v2.3 does not define the later ID3v2.4 UTF-16BE-without-BOM or UTF-8
encoding markers.

This module parses only the encoding marker and exposes structural
properties needed by later text-string parsing.
+/
module audiotag.id3v2.v23.text_encoding;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;


/++
Text encodings defined by ID3v2.3.
+/
enum Id3v23TextEncoding : ubyte
{
    /// ISO-8859-1, encoding marker $00.
    latin1 = 0x00,

    /// 16-bit Unicode with BOM, encoding marker $01.
    utf16 = 0x01
}


/++
Returns whether this encoding uses 16-bit code units.

This affects terminator alignment during structural string parsing.
+/
bool usesUtf16(
    Id3v23TextEncoding encoding
)
    @safe pure nothrow @nogc
{
    return
        encoding ==
        Id3v23TextEncoding.utf16;
}


/++
Returns the number of logical zero bytes in this encoding's string
terminator.

ISO-8859-1 uses `$00`.
UTF-16 uses `$00 $00`.
+/
ubyte terminatorWidth(
    Id3v23TextEncoding encoding
)
    @safe pure nothrow @nogc
{
    return
        encoding.usesUtf16
        ? 2
        : 1;
}


/++
Parses one ID3v2.3 text-encoding marker from a logical data cursor.

Params:
    cursor = Cursor positioned at the encoding byte.

Returns:
    The parsed encoding or `invalidEncodingMarker`.

Error semantics:
    Failure leaves `cursor` unchanged.
+/
ParseResult!Id3v23TextEncoding
parseId3v23TextEncoding(
    ref Id3v23DataCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    auto byteResult =
        probe.takeByte();

    if (byteResult.hasError)
    {
        return
            ParseResult!Id3v23TextEncoding
                .failure(
                    byteResult.error
                );
    }

    const decoded =
        byteResult.value;

    Id3v23TextEncoding encoding;

    switch (
        decoded.value
    )
    {
        case 0x00:
        {
            encoding =
                Id3v23TextEncoding.latin1;

            break;
        }

        case 0x01:
        {
            encoding =
                Id3v23TextEncoding.utf16;

            break;
        }

        default:
        {
            return
                ParseResult!Id3v23TextEncoding
                    .failure(
                        ParseError(
                            ParseErrorCode
                                .invalidEncodingMarker,
                            decoded.sourceOffset
                        )
                    );
        }
    }

    cursor =
        probe;

    return
        ParseResult!Id3v23TextEncoding
            .success(
                encoding
            );
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;
}


/// Both ID3v2.3 text-encoding markers are accepted.
unittest
{
    foreach (
        marker;
        0 .. 2
    )
    {
        const expected =
            cast(Id3v23TextEncoding)
                marker;

        const ubyte[] bytes =
            [
                cast(ubyte) marker,
                0x55
            ];

        auto cursor =
            Id3v23DataCursor(
                ByteSpan(
                    bytes,
                    100
                ),
                false
            );

        auto result =
            cursor.parseId3v23TextEncoding();

        assert(result.hasValue);

        assert(
            result.value ==
            expected
        );

        assert(cursor.logicalPosition == 1);
        assert(cursor.physicalPosition == 1);
        assert(cursor.absoluteOffset == 101);

        assert(
            cursor.remainingRaw.data ==
            [0x55]
        );
    }
}


/// ID3v2.4-only and otherwise undefined markers are rejected.
unittest
{
    foreach (
        marker;
        [
            0x02,
            0x03,
            0x04,
            0x7F,
            0xFF
        ]
    )
    {
        const ubyte[] bytes =
            [
                cast(ubyte) marker,
                0x55
            ];

        auto cursor =
            Id3v23DataCursor(
                ByteSpan(
                    bytes,
                    200
                ),
                false
            );

        auto result =
            cursor.parseId3v23TextEncoding();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode
                .invalidEncodingMarker
        );

        assert(result.error.offset == 200);

        assert(cursor.logicalPosition == 0);
        assert(cursor.physicalPosition == 0);
        assert(cursor.absoluteOffset == 200);

        assert(
            cursor.remainingRaw.data ==
            bytes
        );
    }
}


/// Missing encoding markers propagate end-of-span atomically.
unittest
{
    const ubyte[] bytes = [];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                300
            ),
            false
        );

    auto result =
        cursor.parseId3v23TextEncoding();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 300);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 300);
}


/// Structural encoding properties match ID3v2.3 termination rules.
unittest
{
    assert(
        !Id3v23TextEncoding
            .latin1
            .usesUtf16
    );

    assert(
        Id3v23TextEncoding
            .utf16
            .usesUtf16
    );

    assert(
        Id3v23TextEncoding
            .latin1
            .terminatorWidth ==
        1
    );

    assert(
        Id3v23TextEncoding
            .utf16
            .terminatorWidth ==
        2
    );
}


/// Marker parsing retains physical position after earlier unsynchronisation.
unittest
{
    /*
     * Logical stream:
     *
     *   FF 01 55
     *
     * Physical representation:
     *
     *   FF 00 01 55
     *
     * The valid UTF-16 marker therefore begins at physical offset 402
     * even though it is only logical byte number two.
     */
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0x01,
            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                400
            ),
            true
        );

    auto prefix =
        cursor.takeByte();

    assert(prefix.hasValue);
    assert(prefix.value.value == 0xFF);
    assert(prefix.value.sourceOffset == 400);

    assert(cursor.logicalPosition == 1);
    assert(cursor.physicalPosition == 2);
    assert(cursor.absoluteOffset == 402);

    auto result =
        cursor.parseId3v23TextEncoding();

    assert(result.hasValue);

    assert(
        result.value ==
        Id3v23TextEncoding.utf16
    );

    assert(cursor.logicalPosition == 2);
    assert(cursor.physicalPosition == 3);
    assert(cursor.absoluteOffset == 403);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// Invalid marker offsets remain physical after earlier stuffing.
unittest
{
    /*
     * Logical stream:
     *
     *   FF 03
     *
     * The invalid v2.4 UTF-8 marker originates at physical offset 502.
     */
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0x03,
            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                500
            ),
            true
        );

    auto prefix =
        cursor.takeByte();

    assert(prefix.hasValue);

    assert(cursor.logicalPosition == 1);
    assert(cursor.physicalPosition == 2);

    auto result =
        cursor.parseId3v23TextEncoding();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidEncodingMarker
    );

    assert(result.error.offset == 502);

    /*
     * Only the earlier successful prefix read remains committed.
     * The failed marker parse itself is atomic.
     */
    assert(cursor.logicalPosition == 1);
    assert(cursor.physicalPosition == 2);
    assert(cursor.absoluteOffset == 502);

    assert(
        cursor.remainingRaw.data ==
        [0x03, 0x55]
    );
}


/// An invalid logical $FF marker does not consume its stuffing byte.
unittest
{
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                600
            ),
            true
        );

    auto result =
        cursor.parseId3v23TextEncoding();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidEncodingMarker
    );

    assert(result.error.offset == 600);

    /*
     * The parser's probe consumed physical FF 00, but failure must not
     * commit either physical byte to the caller.
     */
    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 600);

    assert(
        cursor.remainingRaw.data ==
        bytes
    );
}
