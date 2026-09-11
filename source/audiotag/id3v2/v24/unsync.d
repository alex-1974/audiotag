/++
ID3v2.4 compatibility surface for shared streaming unsynchronisation decoding.

The byte-stuffing algorithm itself is revision-independent and lives in
`audiotag.id3v2.common.unsync`. This module preserves the established v2.4
public names while v2.4 structural code continues to decide where
unsynchronisation applies.
+/
module audiotag.id3v2.v24.unsync;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.common.unsync :
    Id3v2DecodedByte,
    takeId3v2UnsynchronisedByte;


/++
Backward-compatible v2.4 name for one decoded unsynchronised byte.
+/
alias Id3v24DecodedByte =
    Id3v2DecodedByte;


/++
Backward-compatible v2.4 entry point for shared ID3v2 unsynchronisation
decoding.

The caller remains responsible for invoking this primitive only where
ID3v2.4 structural rules make unsynchronisation effective.
+/
ParseResult!Id3v24DecodedByte
takeId3v24UnsynchronisedByte(
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


/// The v2.4 compatibility entry point preserves physical source provenance.
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
                300
            )
        );

    auto first =
        cursor.takeId3v24UnsynchronisedByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 300);
    assert(cursor.position == 2);

    auto second =
        cursor.takeId3v24UnsynchronisedByte();

    assert(second.hasValue);
    assert(second.value.value == 0xE1);
    assert(second.value.sourceOffset == 302);
    assert(cursor.empty);
}
