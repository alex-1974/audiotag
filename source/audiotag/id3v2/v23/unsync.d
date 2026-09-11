/++
ID3v2.3 compatibility surface for shared streaming unsynchronisation decoding.

The byte-stuffing algorithm itself is revision-independent and lives in
`audiotag.id3v2.common.unsync`. This module preserves the established v2.3
public names while the v2.3 structural layers continue to decide where
tag-level unsynchronisation applies.
+/
module audiotag.id3v2.v23.unsync;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.common.unsync :
    Id3v2DecodedByte,
    takeId3v2UnsynchronisedByte;


/++
Backward-compatible v2.3 name for one decoded unsynchronised byte.
+/
alias Id3v23DecodedByte =
    Id3v2DecodedByte;


/++
Backward-compatible v2.3 entry point for shared ID3v2 unsynchronisation
decoding.

The caller remains responsible for invoking this primitive only where
ID3v2.3 tag-level unsynchronisation is effective.
+/
ParseResult!Id3v23DecodedByte
takeId3v23UnsynchronisedByte(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    return
        cursor.takeId3v2UnsynchronisedByte();
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;
}


/// The v2.3 compatibility entry point preserves physical source provenance.
unittest
{
    const ubyte[] bytes =
        [
            0xFF,
            0x00,
            0xE1
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                200
            )
        );

    auto first =
        cursor.takeId3v23UnsynchronisedByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 200);
    assert(cursor.position == 2);

    auto second =
        cursor.takeId3v23UnsynchronisedByte();

    assert(second.hasValue);
    assert(second.value.value == 0xE1);
    assert(second.value.sourceOffset == 202);
    assert(cursor.empty);
}
