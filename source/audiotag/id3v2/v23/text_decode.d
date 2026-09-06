/++
ID3v2.3 encoded-text decoding.

This module converts already bounded ID3v2.3 encoded text into UTF-8
D strings.

Supported encodings:

- ISO-8859-1;
- 16-bit Unicode 2.0 / UCS-2 with BOM.

ID3v2.3 tag-level unsynchronisation is reversed before character
decoding.

Unlike ID3v2.4 UTF-16, the ID3v2.3 specification describes `$01` text
as UCS-2. Surrogate code units are therefore rejected rather than
combined into supplementary Unicode code points.

Malformed Unicode is reported with physical source offsets.
+/
module audiotag.id3v2.v23.text_decode;

import std.utf :
    encode;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding;

import audiotag.id3v2.v23.text_segment :
    Id3v23TextSegment;


/++
Decodes one bounded ID3v2.3 text region to UTF-8.

The region does not need to contain or end in a string terminator.
This is useful for text values whose extent is already defined by the
enclosing frame.

For `$01`, an empty region is accepted as an empty string. Every
non-empty region must begin with a valid Unicode BOM.

Params:
    raw = Physical encoded text bytes.
    encoding = ID3v2.3 text encoding.
    unsynchronised = Whether ID3v2.3 tag-level unsynchronisation
        applies to `raw`.

Returns:
    A UTF-8 D string or a structured text-decoding error.

Notes:
    This semantic decoding layer may allocate.
+/
ParseResult!string
decodeId3v23TextSpan(
    ByteSpan raw,
    Id3v23TextEncoding encoding,
    bool unsynchronised = false
)
    @safe
{
    switch (encoding)
    {
        case Id3v23TextEncoding.latin1:
        {
            return
                decodeLatin1(
                    raw,
                    unsynchronised
                );
        }

        case Id3v23TextEncoding.utf16:
        {
            return
                decodeUcs2(
                    raw,
                    unsynchronised
                );
        }

        default:
        {
            return
                ParseResult!string
                    .failure(
                        ParseError(
                            ParseErrorCode
                                .invalidEncodingMarker,
                            raw.sourceOffset
                        )
                    );
        }
    }
}


/++
Decodes one previously bounded ID3v2.3 text segment to UTF-8.

This is a convenience wrapper around `decodeId3v23TextSpan`.
+/
ParseResult!string
decodeId3v23TextSegment(
    Id3v23TextSegment segment,
    bool unsynchronised = false
)
    @safe
{
    return
        decodeId3v23TextSpan(
            segment.raw,
            segment.encoding,
            unsynchronised
        );
}


/++
Decodes ISO-8859-1 code units to UTF-8.
+/
private ParseResult!string
decodeLatin1(
    ByteSpan raw,
    bool unsynchronised
)
    @safe
{
    auto cursor =
        Id3v23DataCursor(
            raw,
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
            cast(dchar)
                result.value.value
        );
    }

    return
        ParseResult!string
            .success(
                output.idup
            );
}


/++
Decodes ID3v2.3 16-bit Unicode / UCS-2 text.

A non-empty string must begin with either:

- `FE FF`: big-endian;
- `FF FE`: little-endian.

Surrogate code units are invalid because ID3v2.3 specifies UCS-2 rather
than ID3v2.4 UTF-16.
+/
private ParseResult!string
decodeUcs2(
    ByteSpan raw,
    bool unsynchronised
)
    @safe
{
    auto cursor =
        Id3v23DataCursor(
            raw,
            unsynchronised
        );

    /*
     * Empty `$01` fields occur in practice and have no byte order to
     * establish. A terminated empty field may have consisted solely of
     * its terminator before structural segmentation.
     */
    if (cursor.empty)
    {
        return
            ParseResult!string
                .success("");
    }

    auto firstResult =
        cursor.takeByte();

    assert(firstResult.hasValue);

    const first =
        firstResult.value;

    if (cursor.empty)
    {
        return
            ParseResult!string
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidByteOrderMark,
                        first.sourceOffset
                    )
                );
    }

    auto secondResult =
        cursor.takeByte();

    assert(secondResult.hasValue);

    const second =
        secondResult.value;

    bool bigEndian;

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
        return
            ParseResult!string
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidByteOrderMark,
                        first.sourceOffset
                    )
                );
    }

    char[] output;

    while (!cursor.empty)
    {
        auto unitResult =
            takeUcs2Unit(
                cursor,
                bigEndian
            );

        if (unitResult.hasError)
        {
            return
                ParseResult!string
                    .failure(
                        unitResult.error
                    );
        }

        const unit =
            unitResult.value;

        /*
         * ID3v2.3 names UCS-2 explicitly. Surrogate code units are not
         * scalar values in UCS-2 and therefore cannot be represented by
         * this strict decoder.
         */
        if (
            unit.value >= 0xD800 &&
            unit.value <= 0xDFFF
        )
        {
            return
                ParseResult!string
                    .failure(
                        ParseError(
                            ParseErrorCode
                                .invalidUnicodeSequence,
                            unit.sourceOffset
                        )
                    );
        }

        encode(
            output,
            cast(dchar)
                unit.value
        );
    }

    return
        ParseResult!string
            .success(
                output.idup
            );
}


/++
One decoded UCS-2 code unit together with its physical source offset.
+/
private struct Ucs2Unit
{
    ushort value;
    size_t sourceOffset;
}


/++
Consumes exactly two logical bytes as one UCS-2 code unit.

The stored physical representation may contain an additional v2.3
unsynchronisation stuffing byte.

Failure is atomic.
+/
private ParseResult!Ucs2Unit
takeUcs2Unit(
    ref Id3v23DataCursor cursor,
    bool bigEndian
)
    @safe
{
    auto probe =
        cursor;

    auto firstResult =
        probe.takeByte();

    if (firstResult.hasError)
    {
        return
            ParseResult!Ucs2Unit
                .failure(
                    firstResult.error
                );
    }

    const first =
        firstResult.value;

    auto secondResult =
        probe.takeByte();

    if (secondResult.hasError)
    {
        /*
         * The logical UCS-2 unit began successfully but its second byte
         * is absent. Report the malformed character at the first byte's
         * physical source location.
         */
        return
            ParseResult!Ucs2Unit
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidUnicodeSequence,
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
            cast(ushort)
            (
                (
                    cast(ushort)
                        first.value
                    << 8
                ) |
                cast(ushort)
                    second.value
            );
    }
    else
    {
        value =
            cast(ushort)
            (
                (
                    cast(ushort)
                        second.value
                    << 8
                ) |
                cast(ushort)
                    first.value
            );
    }

    cursor =
        probe;

    return
        ParseResult!Ucs2Unit
            .success(
                Ucs2Unit(
                    value,
                    first.sourceOffset
                )
            );
}


version (unittest)
{
    import audiotag.id3v2.v23.text_segment :
        takeId3v23TerminatedTextSegment;
}


/// ISO-8859-1 characters are transcoded to UTF-8.
unittest
{
    const ubyte[] bytes =
        [
            'A',
            0xE4
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                100
            ),
            Id3v23TextEncoding.latin1
        );

    assert(result.hasValue);

    assert(
        result.value ==
        "A\u00E4"
    );
}


/// The complete ISO-8859-1 byte range is mapped as Unicode code points.
unittest
{
    const ubyte[] bytes =
        [
            0xC4,
            0xD6,
            0xDC,
            0xFF
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                200
            ),
            Id3v23TextEncoding.latin1
        );

    assert(result.hasValue);

    assert(
        result.value ==
        "\u00C4\u00D6\u00DC\u00FF"
    );
}


/// Latin-1 decoding reverses tag-level unsynchronisation first.
unittest
{
    /*
     * Logical bytes:
     *
     *   FF 42
     *
     * Physical representation:
     *
     *   FF 00 42
     */
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0x42
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                300
            ),
            Id3v23TextEncoding.latin1,
            true
        );

    assert(result.hasValue);

    assert(
        result.value ==
        "\u00FFB"
    );
}


/// Big-endian UCS-2 is selected by FE FF.
unittest
{
    const ubyte[] bytes =
        [
            /*
             * Big-endian BOM.
             */
            0xFE, 0xFF,

            /*
             * U+0041 LATIN CAPITAL LETTER A.
             */
            0x00, 0x41,

            /*
             * U+03A9 GREEK CAPITAL LETTER OMEGA.
             */
            0x03, 0xA9
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                400
            ),
            Id3v23TextEncoding.utf16
        );

    assert(result.hasValue);

    assert(
        result.value ==
        "A\u03A9"
    );
}


/// Little-endian UCS-2 is selected by FF FE.
unittest
{
    const ubyte[] bytes =
        [
            /*
             * Little-endian BOM.
             */
            0xFF, 0xFE,

            /*
             * U+0041.
             */
            0x41, 0x00,

            /*
             * U+03A9.
             */
            0xA9, 0x03
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                500
            ),
            Id3v23TextEncoding.utf16
        );

    assert(result.hasValue);

    assert(
        result.value ==
        "A\u03A9"
    );
}


/// Unsynchronisation inside a little-endian BOM preserves decoding.
unittest
{
    /*
     * Logical bytes:
     *
     *   FF FE 41 00
     *
     * Physical representation:
     *
     *   FF 00 FE 41 00
     */
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0xFE,

            0x41, 0x00
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                600
            ),
            Id3v23TextEncoding.utf16,
            true
        );

    assert(result.hasValue);

    assert(result.value == "A");
}


/// Empty `$01` text decodes to an empty UTF-8 string.
unittest
{
    const ubyte[] bytes = [];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                700
            ),
            Id3v23TextEncoding.utf16
        );

    assert(result.hasValue);
    assert(result.value.length == 0);
}


/// A BOM without following text is a valid empty UCS-2 value.
unittest
{
    const ubyte[] bigEndianBom =
        [
            0xFE, 0xFF
        ];

    const ubyte[] littleEndianBom =
        [
            0xFF, 0xFE
        ];

    foreach (
        bytes;
        [
            bigEndianBom,
            littleEndianBom
        ]
    )
    {
        auto result =
            decodeId3v23TextSpan(
                ByteSpan(
                    bytes,
                    800
                ),
                Id3v23TextEncoding.utf16
            );

        assert(result.hasValue);
        assert(result.value.length == 0);
    }
}


/// Non-empty Unicode text must begin with a BOM.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x41
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                900
            ),
            Id3v23TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidByteOrderMark
    );

    assert(result.error.offset == 900);
}


/// A one-byte Unicode field cannot contain a complete BOM.
unittest
{
    const ubyte[] bytes =
        [
            0xFE
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                1000
            ),
            Id3v23TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidByteOrderMark
    );

    assert(result.error.offset == 1000);
}


/// UCS-2 content must contain complete two-byte logical units.
unittest
{
    const ubyte[] bytes =
        [
            0xFE, 0xFF,

            0x00, 0x41,

            /*
             * Incomplete final code unit.
             */
            0x55
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                1100
            ),
            Id3v23TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidUnicodeSequence
    );

    assert(result.error.offset == 1104);
    assert(result.error.requested == 2);
    assert(result.error.available == 1);
}


/// Physical stuffing does not affect UCS-2 code-unit alignment.
unittest
{
    /*
     * Logical bytes:
     *
     *   FE FF
     *   00 FF
     *
     * Whole-tag unsynchronisation must stuff both FF occurrences:
     *
     *   FE FF 00
     *   00 FF 00
     *
     * The first stuffing byte belongs to the BOM boundary because the
     * logical byte following the BOM's final FF is 00.
     */
    const ubyte[] bytes =
        [
            0xFE,
            0xFF, 0x00,

            0x00,
            0xFF, 0x00
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                1200
            ),
            Id3v23TextEncoding.utf16,
            true
        );

    assert(result.hasValue);

    assert(
        result.value ==
        "\u00FF"
    );
}


/// High-surrogate code units are invalid in strict ID3v2.3 UCS-2.
unittest
{
    const ubyte[] bytes =
        [
            0xFE, 0xFF,

            /*
             * D800.
             */
            0xD8, 0x00
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                1300
            ),
            Id3v23TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidUnicodeSequence
    );

    assert(result.error.offset == 1302);
}


/// Low-surrogate code units are also invalid in ID3v2.3 UCS-2.
unittest
{
    const ubyte[] bytes =
        [
            0xFF, 0xFE,

            /*
             * DC00 in little-endian order.
             */
            0x00, 0xDC
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                1400
            ),
            Id3v23TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidUnicodeSequence
    );

    assert(result.error.offset == 1402);
}


/// Surrogate pairs are not silently upgraded from UCS-2 to UTF-16.
unittest
{
    /*
     * D83D DE00 would encode U+1F600 in UTF-16, but ID3v2.3 specifies
     * UCS-2 and therefore cannot represent this value.
     */
    const ubyte[] bytes =
        [
            0xFE, 0xFF,

            0xD8, 0x3D,
            0xDE, 0x00
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                1500
            ),
            Id3v23TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidUnicodeSequence
    );

    assert(result.error.offset == 1502);
}


/// Physical source offsets survive stuffing before an invalid surrogate.
unittest
{
    /*
     * Logical:
     *
     *   FF FE       BOM
     *   41 00       A
     *   00 D8       D800 little-endian
     *
     * Physical:
     *
     *   FF 00 FE
     *   41 00
     *   00 D8
     */
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0xFE,

            0x41, 0x00,

            0x00, 0xD8
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                1600
            ),
            Id3v23TextEncoding.utf16,
            true
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidUnicodeSequence
    );

    /*
     * The malformed logical unit begins at physical offset 1605.
     */
    assert(result.error.offset == 1605);
}


/// A previously segmented Latin-1 string decodes through the wrapper.
unittest
{
    const ubyte[] bytes =
        [
            'A',
            0xE4,
            0x00
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1700
            ),
            false
        );

    auto segment =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    assert(segment.hasValue);

    auto decoded =
        segment.value
            .decodeId3v23TextSegment();

    assert(decoded.hasValue);

    assert(
        decoded.value ==
        "A\u00E4"
    );
}


/// A segmented Unicode string excludes its terminator before decoding.
unittest
{
    const ubyte[] bytes =
        [
            0xFE, 0xFF,
            0x00, 0x41,

            /*
             * UTF-16 terminator.
             */
            0x00, 0x00,

            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1800
            ),
            false
        );

    auto segment =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.utf16
        );

    assert(segment.hasValue);

    assert(
        segment.value.raw.data ==
        [
            0xFE, 0xFF,
            0x00, 0x41
        ]
    );

    auto decoded =
        segment.value
            .decodeId3v23TextSegment();

    assert(decoded.hasValue);
    assert(decoded.value == "A");

    assert(cursor.absoluteOffset == 1806);
    assert(cursor.remainingRaw.data == [0x55]);
}


/// An invalid enum value remains a structured external-data error.
unittest
{
    const ubyte[] bytes =
        [
            0x41
        ];

    auto result =
        decodeId3v23TextSpan(
            ByteSpan(
                bytes,
                1900
            ),
            cast(Id3v23TextEncoding)
                0x7F
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidEncodingMarker
    );

    assert(result.error.offset == 1900);
}
