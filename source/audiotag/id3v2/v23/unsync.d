/++
Streaming ID3v2.3 unsynchronisation decoding.

ID3v2.3 tag-level unsynchronisation inserts a zero byte after certain
$FF bytes. During decoding, an encountered physical `$FF $00` sequence
therefore yields one logical `$FF` byte while consuming both physical
bytes.

This primitive deliberately does not decide where unsynchronisation
applies. ID3v2.3 applies it at tag-body level; that policy belongs to
the higher structural parser.

No decoded buffer is materialised. The raw source representation and
absolute physical offsets remain available.
+/
module audiotag.id3v2.v23.unsync;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;


/++
One logically decoded byte together with the absolute source offset of
the physical byte that produced it.
+/
struct Id3v23DecodedByte
{
    /// Logical byte value after unsynchronisation decoding.
    ubyte value;

    /// Absolute source offset of the corresponding physical byte.
    size_t sourceOffset;
}


/++
Consumes one logical byte from an ID3v2.3 unsynchronised byte region.

If the physical input begins with `$FF $00`, both bytes are consumed
and one logical `$FF` is returned. Otherwise exactly one physical byte
is consumed.

The caller is responsible for invoking this primitive only inside a
region for which ID3v2.3 tag-level unsynchronisation is effective.

Params:
    cursor = Cursor over an already bounded physical source region.

Returns:
    The next logical byte and its physical source offset, or a
    structured end-of-span error.

Error semantics:
    Failure leaves `cursor` unchanged.
+/
ParseResult!Id3v23DecodedByte
takeId3v23UnsynchronisedByte(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    auto firstResult =
        probe.takeBytes(1);

    if (firstResult.hasError)
    {
        return
            ParseResult!Id3v23DecodedByte
                .failure(
                    firstResult.error
                );
    }

    const first =
        firstResult.value;

    const value =
        first.data[0];

    if (
        value == 0xFF &&
        !probe.empty
    )
    {
        auto nextResult =
            probe.peekBytes(1);

        /*
         * probe.empty was checked immediately above, so one physical
         * byte is guaranteed to be available.
         */
        assert(nextResult.hasValue);

        if (
            nextResult.value.data[0] ==
            0x00
        )
        {
            auto skipped =
                probe.skipBytes(1);

            /*
             * The byte was just observed through peekBytes(1).
             */
            assert(skipped.succeeded);
        }
    }

    const decoded =
        Id3v23DecodedByte(
            value,
            first.sourceOffset
        );

    cursor =
        probe;

    return
        ParseResult!Id3v23DecodedByte
            .success(decoded);
}


version (unittest)
{
    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.core.span :
        ByteSpan;
}


/// Ordinary bytes consume exactly one physical byte.
unittest
{
    const ubyte[] bytes =
        [
            0x11,
            0x22
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto result =
        cursor.takeId3v23UnsynchronisedByte();

    assert(result.hasValue);
    assert(result.value.value == 0x11);
    assert(result.value.sourceOffset == 100);

    assert(cursor.position == 1);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x22);
}


/// An inserted zero after $FF is removed from the logical stream.
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
    assert(cursor.absoluteOffset == 202);

    auto second =
        cursor.takeId3v23UnsynchronisedByte();

    assert(second.hasValue);
    assert(second.value.value == 0xE1);
    assert(second.value.sourceOffset == 202);

    assert(cursor.empty);
}


/// An original $FF $00 round-trips from encoded $FF $00 $00.
unittest
{
    const ubyte[] bytes =
        [
            0xFF,
            0x00,
            0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto first =
        cursor.takeId3v23UnsynchronisedByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 300);

    auto second =
        cursor.takeId3v23UnsynchronisedByte();

    assert(second.hasValue);
    assert(second.value.value == 0x00);
    assert(second.value.sourceOffset == 302);

    assert(cursor.empty);
}


/// A trailing $FF remains one valid logical byte.
unittest
{
    const ubyte[] bytes =
        [
            0xFF
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto result =
        cursor.takeId3v23UnsynchronisedByte();

    assert(result.hasValue);
    assert(result.value.value == 0xFF);
    assert(result.value.sourceOffset == 400);

    assert(cursor.empty);
}


/// A zero not preceded by $FF is ordinary data.
unittest
{
    const ubyte[] bytes =
        [
            0x00,
            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto result =
        cursor.takeId3v23UnsynchronisedByte();

    assert(result.hasValue);
    assert(result.value.value == 0x00);
    assert(result.value.sourceOffset == 500);

    assert(cursor.position == 1);
    assert(cursor.absoluteOffset == 501);
    assert(cursor.front == 0x55);
}


/// Empty input fails atomically at the current absolute offset.
unittest
{
    const ubyte[] bytes = [];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto result =
        cursor.takeId3v23UnsynchronisedByte();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 600);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 600);
}


/// Source offsets remain physical after skipped stuffing bytes.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            0xFF,
            0x00,
            0x42
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1000
            )
        );

    cursor.popFront();

    auto first =
        cursor.takeId3v23UnsynchronisedByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 1001);

    auto second =
        cursor.takeId3v23UnsynchronisedByte();

    assert(second.hasValue);
    assert(second.value.value == 0x42);
    assert(second.value.sourceOffset == 1003);

    assert(cursor.empty);
}
