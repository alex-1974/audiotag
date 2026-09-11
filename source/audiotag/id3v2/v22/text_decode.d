/++
ID3v2.2 encoded-text decoding.

This module converts already bounded ID3v2.2 encoded text into UTF-8 D
strings.

Supported encodings:

- ISO-8859-1;
- 16-bit Unicode 2.0 / UCS-2.

ID3v2.2 tag-level unsynchronisation is reversed before character decoding.

Unlike ID3v2.3, ID3v2.2 does not require a byte-order mark at the beginning
of a Unicode string. For BOM-less UCS-2 this implementation uses big-endian
byte order as the deterministic revision-native default. An explicit FE FF
or FF FE BOM, when present, overrides that default.

ID3v2.2 names UCS-2 rather than later UTF-16. Surrogate code units are
therefore rejected instead of being combined into supplementary Unicode code
points.

Malformed Unicode is reported with physical source offsets.
+/
module audiotag.id3v2.v22.text_decode;

import std.utf :
    encode;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.text_encoding :
    Id3v22TextEncoding;


/++
Decodes one bounded ID3v2.2 text region to UTF-8.

The region does not need to contain or end in a string terminator. This is
suitable for text values whose extent is already defined by the enclosing
frame.

For `$01`, an empty region is accepted as an empty string.

A leading Unicode BOM is accepted:

- `FE FF`: big-endian;
- `FF FE`: little-endian.

When no BOM is present, UCS-2 code units are interpreted as big-endian. The
decoder never guesses little-endian byte order from text contents.

Params:
    raw = Physical encoded text bytes.
    encoding = ID3v2.2 text encoding.
    unsynchronised = Whether ID3v2.2 tag-level unsynchronisation applies to
        `raw`.

Returns:
    A UTF-8 D string or a structured text-decoding error.

Notes:
    This semantic decoding layer may allocate.
+/
ParseResult!string
decodeId3v22TextSpan(
    ByteSpan raw,
    Id3v22TextEncoding encoding,
    bool unsynchronised = false
)
    @safe
{
    switch (encoding)
    {
        case Id3v22TextEncoding.latin1:
        {
            return
                decodeLatin1(
                    raw,
                    unsynchronised
                );
        }

        case Id3v22TextEncoding.utf16:
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
        Id3v22DataCursor(
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
Decodes ID3v2.2 16-bit Unicode / UCS-2 text.

ID3v2.2 itself does not require a BOM. This decoder therefore accepts both:

- BOM-prefixed big- or little-endian UCS-2;
- BOM-less big-endian UCS-2.

No heuristic little-endian detection is performed.

Surrogate code units are invalid because ID3v2.2 specifies UCS-2.
+/
private ParseResult!string
decodeUcs2(
    ByteSpan raw,
    bool unsynchronised
)
    @safe
{
    auto cursor =
        Id3v22DataCursor(
            raw,
            unsynchronised
        );

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
                            .invalidUnicodeSequence,
                        first.sourceOffset,
                        2,
                        1
                    )
                );
    }

    auto secondResult =
        cursor.takeByte();

    assert(secondResult.hasValue);

    const second =
        secondResult.value;

    bool bigEndian =
        true;

    bool consumedBom =
        false;

    if (
        first.value == 0xFE &&
        second.value == 0xFF
    )
    {
        bigEndian =
            true;

        consumedBom =
            true;
    }
    else if (
        first.value == 0xFF &&
        second.value == 0xFE
    )
    {
        bigEndian =
            false;

        consumedBom =
            true;
    }

    char[] output;

    if (!consumedBom)
    {
        auto appendResult =
            appendUcs2Unit(
                output,
                combineUcs2(
                    first.value,
                    second.value,
                    true
                ),
                first.sourceOffset
            );

        if (appendResult.hasError)
        {
            return
                ParseResult!string
                    .failure(
                        appendResult.error
                    );
        }
    }

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

        auto appendResult =
            appendUcs2Unit(
                output,
                unitResult.value.value,
                unitResult.value.sourceOffset
            );

        if (appendResult.hasError)
        {
            return
                ParseResult!string
                    .failure(
                        appendResult.error
                    );
        }
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
Combines two logical bytes into one UCS-2 code unit.
+/
private ushort
combineUcs2(
    ubyte first,
    ubyte second,
    bool bigEndian
)
    @safe pure nothrow @nogc
{
    if (bigEndian)
    {
        return
            cast(ushort)
            (
                (
                    cast(ushort)
                        first
                    << 8
                ) |
                cast(ushort)
                    second
            );
    }

    return
        cast(ushort)
        (
            (
                cast(ushort)
                    second
                << 8
            ) |
            cast(ushort)
                first
        );
}


/++
Consumes exactly two logical bytes as one UCS-2 code unit.

The stored physical representation may contain an additional v2.2
unsynchronisation stuffing byte.

Failure is atomic.
+/
private ParseResult!Ucs2Unit
takeUcs2Unit(
    ref Id3v22DataCursor cursor,
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

    cursor =
        probe;

    return
        ParseResult!Ucs2Unit
            .success(
                Ucs2Unit(
                    combineUcs2(
                        first.value,
                        second.value,
                        bigEndian
                    ),
                    first.sourceOffset
                )
            );
}


/++
Appends one valid UCS-2 scalar to a UTF-8 output buffer.
+/
private ParseResult!bool
appendUcs2Unit(
    ref char[] output,
    ushort unit,
    size_t sourceOffset
)
    @safe
{
    if (
        unit >= 0xD800 &&
        unit <= 0xDFFF
    )
    {
        return
            ParseResult!bool
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidUnicodeSequence,
                        sourceOffset
                    )
                );
    }

    encode(
        output,
        cast(dchar)
            unit
    );

    return
        ParseResult!bool
            .success(true);
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
        decodeId3v22TextSpan(
            ByteSpan(
                bytes,
                100
            ),
            Id3v22TextEncoding.latin1
        );

    assert(result.hasValue);
    assert(result.value == "A\u00E4");
}


/// Latin-1 decoding reverses tag-level unsynchronisation first.
unittest
{
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0x42
        ];

    auto result =
        decodeId3v22TextSpan(
            ByteSpan(
                bytes,
                200
            ),
            Id3v22TextEncoding.latin1,
            true
        );

    assert(result.hasValue);
    assert(result.value == "\u00FFB");
}


/// BOM-less ID3v2.2 UCS-2 uses deterministic big-endian byte order.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x41,
            0x00, 0xE4
        ];

    auto result =
        decodeId3v22TextSpan(
            ByteSpan(
                bytes,
                300
            ),
            Id3v22TextEncoding.utf16
        );

    assert(result.hasValue);
    assert(result.value == "A\u00E4");
}


/// A big-endian BOM is accepted and removed from semantic text.
unittest
{
    const ubyte[] bytes =
        [
            0xFE, 0xFF,
            0x00, 0x41,
            0x00, 0xE4
        ];

    auto result =
        decodeId3v22TextSpan(
            ByteSpan(
                bytes,
                400
            ),
            Id3v22TextEncoding.utf16
        );

    assert(result.hasValue);
    assert(result.value == "A\u00E4");
}


/// A little-endian BOM is accepted and establishes little-endian decoding.
unittest
{
    const ubyte[] bytes =
        [
            0xFF, 0xFE,
            0x41, 0x00,
            0xE4, 0x00
        ];

    auto result =
        decodeId3v22TextSpan(
            ByteSpan(
                bytes,
                500
            ),
            Id3v22TextEncoding.utf16
        );

    assert(result.hasValue);
    assert(result.value == "A\u00E4");
}


/// An explicit little-endian BOM survives whole-tag unsynchronisation.
unittest
{
    /*
     * Logical bytes:
     *
     *   FF FE 41 00
     *
     * Physical bytes:
     *
     *   FF 00 FE 41 00
     */
    const ubyte[] bytes =
        [
            0xFF, 0x00, 0xFE,
            0x41, 0x00
        ];

    auto result =
        decodeId3v22TextSpan(
            ByteSpan(
                bytes,
                600
            ),
            Id3v22TextEncoding.utf16,
            true
        );

    assert(result.hasValue);
    assert(result.value == "A");
}


/// A BOM by itself represents an empty semantic string.
unittest
{
    foreach (
        bytes;
        [
            cast(const(ubyte)[])
                [0xFE, 0xFF],
            cast(const(ubyte)[])
                [0xFF, 0xFE]
        ]
    )
    {
        auto result =
            decodeId3v22TextSpan(
                ByteSpan(
                    bytes,
                    700
                ),
                Id3v22TextEncoding.utf16
            );

        assert(result.hasValue);
        assert(result.value.length == 0);
    }
}


/// An empty UCS-2 region is accepted as an empty string.
unittest
{
    const ubyte[] bytes = [];

    auto result =
        decodeId3v22TextSpan(
            ByteSpan(
                bytes,
                800
            ),
            Id3v22TextEncoding.utf16
        );

    assert(result.hasValue);
    assert(result.value.length == 0);
}


/// An odd UCS-2 byte count is rejected at the first incomplete code unit.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x41,
            0x00
        ];

    auto result =
        decodeId3v22TextSpan(
            ByteSpan(
                bytes,
                900
            ),
            Id3v22TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidUnicodeSequence
    );

    assert(result.error.offset == 902);
    assert(result.error.requested == 2);
    assert(result.error.available == 1);
}


/// A single logical byte cannot form one UCS-2 code unit.
unittest
{
    const ubyte[] bytes =
        [
            0x41
        ];

    auto result =
        decodeId3v22TextSpan(
            ByteSpan(
                bytes,
                1000
            ),
            Id3v22TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidUnicodeSequence
    );

    assert(result.error.offset == 1000);
    assert(result.error.requested == 2);
    assert(result.error.available == 1);
}


/// UCS-2 surrogate code units are rejected.
unittest
{
    const ubyte[] bytes =
        [
            0xD8, 0x00
        ];

    auto result =
        decodeId3v22TextSpan(
            ByteSpan(
                bytes,
                1100
            ),
            Id3v22TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidUnicodeSequence
    );

    assert(result.error.offset == 1100);
}


/// Invalid encoding enum values remain structured errors.
unittest
{
    const ubyte[] bytes =
        [
            0x41
        ];

    auto result =
        decodeId3v22TextSpan(
            ByteSpan(
                bytes,
                1200
            ),
            cast(Id3v22TextEncoding)
                0x7F
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode
            .invalidEncodingMarker
    );

    assert(result.error.offset == 1200);
}
