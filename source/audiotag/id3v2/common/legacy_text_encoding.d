/++
Shared ID3v2.2/ID3v2.3 text-encoding marker semantics.

Both revisions use the same selectable text-encoding marker domain:

- $00: ISO-8859-1;
- $01: 16-bit Unicode.

This module intentionally stops at the structural marker semantics.
The precise character-decoding contract is revision-specific:

- ID3v2.2's original Unicode wording does not establish the same strict BOM
  contract used by the later ID3v2.3 implementation;
- ID3v2.3 decoding in this library remains strict UCS-2 with BOM.

Keeping only the genuinely shared marker layer here avoids making v2.2 depend
on v2.3 while preserving revision-specific text interpretation.
+/
module audiotag.id3v2.common.legacy_text_encoding;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;


/++
Text-encoding markers shared by ID3v2.2 and ID3v2.3.
+/
enum Id3v2LegacyTextEncoding : ubyte
{
    /// ISO-8859-1, marker $00.
    latin1 = 0x00,

    /// Legacy 16-bit Unicode marker $01.
    utf16 = 0x01
}


/++
Returns whether the encoding uses 16-bit code units.

This is a structural property used for terminator alignment. It does not
decide the revision-specific Unicode decoding policy.
+/
bool
id3v2LegacyUsesUtf16(
    Id3v2LegacyTextEncoding encoding
)
    @safe pure nothrow @nogc
{
    return
        encoding ==
        Id3v2LegacyTextEncoding.utf16;
}


/++
Returns the number of logical zero bytes in the encoding's string terminator.

Latin-1 uses one zero byte; the 16-bit encoding uses two.
+/
ubyte
id3v2LegacyTerminatorWidth(
    Id3v2LegacyTextEncoding encoding
)
    @safe pure nothrow @nogc
{
    return
        id3v2LegacyUsesUtf16(encoding)
        ? 2
        : 1;
}


/++
Parses one legacy ID3v2 text-encoding marker from a logical data cursor.

`Cursor` is expected to provide the common logical-cursor operation
`takeByte()`. This is satisfied by both `Id3v22DataCursor` and
`Id3v23DataCursor`.

Params:
    cursor = Logical cursor positioned at the encoding marker.

Returns:
    The parsed legacy encoding or `invalidEncodingMarker`.

Error semantics:
    Failure leaves `cursor` unchanged.
+/
ParseResult!Id3v2LegacyTextEncoding
parseId3v2LegacyTextEncoding(Cursor)(
    ref Cursor cursor
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
            ParseResult!Id3v2LegacyTextEncoding
                .failure(
                    byteResult.error
                );
    }

    const decoded =
        byteResult.value;

    Id3v2LegacyTextEncoding encoding;

    switch (decoded.value)
    {
        case 0x00:
        {
            encoding =
                Id3v2LegacyTextEncoding.latin1;
            break;
        }

        case 0x01:
        {
            encoding =
                Id3v2LegacyTextEncoding.utf16;
            break;
        }

        default:
        {
            return
                ParseResult!Id3v2LegacyTextEncoding
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
        ParseResult!Id3v2LegacyTextEncoding
            .success(encoding);
}


/// Structural properties are stable across both legacy revisions.
unittest
{
    assert(
        !id3v2LegacyUsesUtf16(
            Id3v2LegacyTextEncoding.latin1
        )
    );

    assert(
        id3v2LegacyUsesUtf16(
            Id3v2LegacyTextEncoding.utf16
        )
    );

    assert(
        id3v2LegacyTerminatorWidth(
            Id3v2LegacyTextEncoding.latin1
        ) ==
        1
    );

    assert(
        id3v2LegacyTerminatorWidth(
            Id3v2LegacyTextEncoding.utf16
        ) ==
        2
    );
}
