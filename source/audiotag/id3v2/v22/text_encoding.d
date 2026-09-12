/++
ID3v2.2 text-encoding markers.

ID3v2.2 shares its two encoding marker values with ID3v2.3. The common marker
semantics live in `audiotag.id3v2.common.legacy_text_encoding`; this module
provides the revision-specific public surface over `Id3v22DataCursor`.

Character decoding remains revision-specific and is deliberately not supplied
by the shared marker module.


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
module audiotag.id3v2.v22.text_encoding;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.common.legacy_text_encoding :
    Id3v2LegacyTextEncoding,
    id3v2LegacyTerminatorWidth,
    id3v2LegacyUsesUtf16,
    parseId3v2LegacyTextEncoding;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;


/++
Text encodings structurally defined by ID3v2.2.
+/
alias Id3v22TextEncoding =
    Id3v2LegacyTextEncoding;


/++
Returns whether this encoding uses 16-bit code units.
+/
bool
usesUtf16(
    Id3v22TextEncoding encoding
)
    @safe pure nothrow @nogc
{
    return
        id3v2LegacyUsesUtf16(
            encoding
        );
}


/++
Returns the logical terminator width for this encoding.
+/
ubyte
terminatorWidth(
    Id3v22TextEncoding encoding
)
    @safe pure nothrow @nogc
{
    return
        id3v2LegacyTerminatorWidth(
            encoding
        );
}


/++
Parses one ID3v2.2 text-encoding marker from a logical data cursor.

Only $00 and $01 are valid.

Error semantics:
    Failure leaves `cursor` unchanged.
+/
ParseResult!Id3v22TextEncoding
parseId3v22TextEncoding(
    ref Id3v22DataCursor cursor
)
    @safe pure nothrow @nogc
{
    return
        parseId3v2LegacyTextEncoding(
            cursor
        );
}


version (unittest)
{
    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.core.span :
        ByteSpan;
}


/// Both ID3v2.2 marker values are accepted.
unittest
{
    foreach (
        marker;
        0 .. 2
    )
    {
        const ubyte[] bytes =
            [
                cast(ubyte) marker,
                0x55
            ];

        auto cursor =
            Id3v22DataCursor(
                ByteSpan(
                    bytes,
                    100
                ),
                false
            );

        auto result =
            cursor.parseId3v22TextEncoding();

        assert(result.hasValue);

        assert(
            result.value ==
            cast(Id3v22TextEncoding)
                marker
        );

        assert(cursor.logicalPosition == 1);
        assert(cursor.physicalPosition == 1);
        assert(cursor.absoluteOffset == 101);
    }
}


/// Later or undefined marker values are rejected atomically.
unittest
{
    foreach (
        marker;
        [
            0x02,
            0x03,
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
            Id3v22DataCursor(
                ByteSpan(
                    bytes,
                    200
                ),
                false
            );

        auto result =
            cursor.parseId3v22TextEncoding();

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
    }
}


/// Marker parsing preserves physical offsets after unsynchronisation stuffing.
unittest
{
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0x01,
            0x55
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                300
            ),
            true
        );

    auto prefix =
        cursor.takeByte();

    assert(prefix.hasValue);
    assert(prefix.value.value == 0xFF);

    auto result =
        cursor.parseId3v22TextEncoding();

    assert(result.hasValue);

    assert(
        result.value ==
        Id3v22TextEncoding.utf16
    );

    assert(cursor.logicalPosition == 2);
    assert(cursor.physicalPosition == 3);
    assert(cursor.absoluteOffset == 303);
}


/// Structural properties match ID3v2.2 terminator widths.
unittest
{
    assert(
        !Id3v22TextEncoding
            .latin1
            .usesUtf16
    );

    assert(
        Id3v22TextEncoding
            .utf16
            .usesUtf16
    );

    assert(
        Id3v22TextEncoding
            .latin1
            .terminatorWidth ==
        1
    );

    assert(
        Id3v22TextEncoding
            .utf16
            .terminatorWidth ==
        2
    );
}
