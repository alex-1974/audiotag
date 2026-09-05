/++
Streaming ID3v2.4 unsynchronisation decoding.

ID3v2.4 unsynchronisation inserts a zero byte after certain $FF
bytes. During decoding, an encountered $FF $00 sequence therefore
yields one logical $FF byte while consuming both physical bytes.

This module deliberately does not materialise a decoded buffer.
It preserves the raw source representation and absolute offsets.
+/
module audiotag.id3v2.v24.unsync;

import audiotag.core.cursor : ByteCursor;
import audiotag.core.result : ParseResult;


/++
One logically decoded byte together with the absolute source offset
of the physical byte that produced it.
+/
struct Id3v24DecodedByte
{
    /// Logical byte value after unsynchronisation decoding.
    ubyte value;

    /// Absolute source offset of the corresponding physical byte.
    size_t sourceOffset;
}


/++
Consumes one logical byte from an ID3v2.4 unsynchronised byte region.

If the physical input begins with `$FF $00`, both bytes are consumed
and one logical `$FF` is returned. Otherwise exactly one physical byte
is consumed.

The operation is atomic on failure.

Params:
    cursor = Cursor over an already bounded unsynchronised region.

Returns:
    The next logical byte and its physical source offset, or a
    structured end-of-span error.
+/
ParseResult!Id3v24DecodedByte takeId3v24UnsynchronisedByte(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe = cursor;

    auto firstResult = probe.takeBytes(1);

    if (firstResult.hasError)
    {
        return ParseResult!Id3v24DecodedByte.failure(
            firstResult.error
        );
    }

    const first = firstResult.value;
    const value = first.data[0];

    if (value == 0xFF && !probe.empty)
    {
        auto nextResult = probe.peekBytes(1);
        assert(nextResult.hasValue);

        if (nextResult.value.data[0] == 0x00)
        {
            auto skipped = probe.skipBytes(1);
            assert(skipped.succeeded);
        }
    }

    const decoded = Id3v24DecodedByte(
        value,
        first.sourceOffset
    );

    cursor = probe;

    return ParseResult!Id3v24DecodedByte.success(decoded);
}


import audiotag.core.error : ParseErrorCode;
import audiotag.core.span : ByteSpan;


/// Ordinary bytes consume exactly one physical byte.
unittest
{
    const ubyte[] bytes =
        [0x11, 0x22];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));

    auto result =
        cursor.takeId3v24UnsynchronisedByte();

    assert(result.hasValue);
    assert(result.value.value == 0x11);
    assert(result.value.sourceOffset == 100);

    assert(cursor.absoluteOffset == 101);
    assert(cursor.front == 0x22);
}


/// An inserted zero after $FF is removed from the logical stream.
unittest
{
    const ubyte[] bytes =
        [0xFF, 0x00, 0xE1];

    auto cursor = ByteCursor(ByteSpan(bytes, 200));

    auto first =
        cursor.takeId3v24UnsynchronisedByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 200);

    assert(cursor.position == 2);
    assert(cursor.absoluteOffset == 202);

    auto second =
        cursor.takeId3v24UnsynchronisedByte();

    assert(second.hasValue);
    assert(second.value.value == 0xE1);
    assert(second.value.sourceOffset == 202);

    assert(cursor.empty);
}


/// An original $FF $00 round-trips from encoded $FF $00 $00.
unittest
{
    const ubyte[] bytes =
        [0xFF, 0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 300));

    auto first =
        cursor.takeId3v24UnsynchronisedByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 300);

    auto second =
        cursor.takeId3v24UnsynchronisedByte();

    assert(second.hasValue);
    assert(second.value.value == 0x00);
    assert(second.value.sourceOffset == 302);

    assert(cursor.empty);
}


/// A trailing $FF remains a valid logical byte.
unittest
{
    const ubyte[] bytes =
        [0xFF];

    auto cursor = ByteCursor(ByteSpan(bytes, 400));

    auto result =
        cursor.takeId3v24UnsynchronisedByte();

    assert(result.hasValue);
    assert(result.value.value == 0xFF);
    assert(result.value.sourceOffset == 400);
    assert(cursor.empty);
}


/// A zero not preceded by $FF is ordinary data.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x55];

    auto cursor = ByteCursor(ByteSpan(bytes, 500));

    auto result =
        cursor.takeId3v24UnsynchronisedByte();

    assert(result.hasValue);
    assert(result.value.value == 0x00);

    assert(cursor.position == 1);
    assert(cursor.front == 0x55);
}


/// Empty input fails atomically with the original absolute offset.
unittest
{
    const ubyte[] bytes = [];

    auto cursor = ByteCursor(ByteSpan(bytes, 600));

    auto result =
        cursor.takeId3v24UnsynchronisedByte();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 600);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 600);
}


/// Source offsets remain physical offsets after skipped stuffing bytes.
unittest
{
    const ubyte[] bytes =
        [0x99,
         0xFF, 0x00,
         0x42];

    auto cursor = ByteCursor(ByteSpan(bytes, 1000));
    cursor.popFront();

    auto first =
        cursor.takeId3v24UnsynchronisedByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 1001);

    auto second =
        cursor.takeId3v24UnsynchronisedByte();

    assert(second.hasValue);
    assert(second.value.value == 0x42);
    assert(second.value.sourceOffset == 1003);

    assert(cursor.empty);
}
