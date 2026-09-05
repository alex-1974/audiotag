/++
Fixed-width integer decoding primitives for bounded byte cursors.

All functions consume exactly the number of bytes required by their
integer width. Truncated input produces the underlying structured
`ParseError` and leaves the cursor unchanged.

The functions are defined for UFCS use with `ByteCursor`.
+/
module audiotag.core.numeric;

import audiotag.core.cursor : ByteCursor;
import audiotag.core.error : ParseError, ParseErrorCode;
import audiotag.core.result : ParseResult;


/++
Reads an unsigned 16-bit big-endian integer.

On failure the cursor remains unchanged.
+/
ParseResult!ushort readU16BE(ref ByteCursor cursor)
    @safe pure nothrow @nogc
{
    auto bytes = cursor.takeBytes(2);

    if (bytes.hasError)
        return ParseResult!ushort.failure(bytes.error);

    const data = bytes.value.data;

    const value =
        (cast(uint) data[0] << 8) |
        cast(uint) data[1];

    return ParseResult!ushort.success(cast(ushort) value);
}


/++
Reads an unsigned 16-bit little-endian integer.

On failure the cursor remains unchanged.
+/
ParseResult!ushort readU16LE(ref ByteCursor cursor)
    @safe pure nothrow @nogc
{
    auto bytes = cursor.takeBytes(2);

    if (bytes.hasError)
        return ParseResult!ushort.failure(bytes.error);

    const data = bytes.value.data;

    const value =
        cast(uint) data[0] |
        (cast(uint) data[1] << 8);

    return ParseResult!ushort.success(cast(ushort) value);
}


/++
Reads an unsigned 24-bit big-endian integer into a `uint`.

On failure the cursor remains unchanged.
+/
ParseResult!uint readU24BE(ref ByteCursor cursor)
    @safe pure nothrow @nogc
{
    auto bytes = cursor.takeBytes(3);

    if (bytes.hasError)
        return ParseResult!uint.failure(bytes.error);

    const data = bytes.value.data;

    const value =
        (cast(uint) data[0] << 16) |
        (cast(uint) data[1] << 8) |
        cast(uint) data[2];

    return ParseResult!uint.success(value);
}


/++
Reads an unsigned 24-bit little-endian integer into a `uint`.

On failure the cursor remains unchanged.
+/
ParseResult!uint readU24LE(ref ByteCursor cursor)
    @safe pure nothrow @nogc
{
    auto bytes = cursor.takeBytes(3);

    if (bytes.hasError)
        return ParseResult!uint.failure(bytes.error);

    const data = bytes.value.data;

    const value =
        cast(uint) data[0] |
        (cast(uint) data[1] << 8) |
        (cast(uint) data[2] << 16);

    return ParseResult!uint.success(value);
}


/++
Reads an unsigned 32-bit big-endian integer.

On failure the cursor remains unchanged.
+/
ParseResult!uint readU32BE(ref ByteCursor cursor)
    @safe pure nothrow @nogc
{
    auto bytes = cursor.takeBytes(4);

    if (bytes.hasError)
        return ParseResult!uint.failure(bytes.error);

    const data = bytes.value.data;

    const value =
        (cast(uint) data[0] << 24) |
        (cast(uint) data[1] << 16) |
        (cast(uint) data[2] << 8) |
        cast(uint) data[3];

    return ParseResult!uint.success(value);
}


/++
Reads an unsigned 32-bit little-endian integer.

On failure the cursor remains unchanged.
+/
ParseResult!uint readU32LE(ref ByteCursor cursor)
    @safe pure nothrow @nogc
{
    auto bytes = cursor.takeBytes(4);

    if (bytes.hasError)
        return ParseResult!uint.failure(bytes.error);

    const data = bytes.value.data;

    const value =
        cast(uint) data[0] |
        (cast(uint) data[1] << 8) |
        (cast(uint) data[2] << 16) |
        (cast(uint) data[3] << 24);

    return ParseResult!uint.success(value);
}


/++
Reads an unsigned 64-bit big-endian integer.

On failure the cursor remains unchanged.
+/
ParseResult!ulong readU64BE(ref ByteCursor cursor)
    @safe pure nothrow @nogc
{
    auto bytes = cursor.takeBytes(8);

    if (bytes.hasError)
        return ParseResult!ulong.failure(bytes.error);

    const data = bytes.value.data;

    const value =
        (cast(ulong) data[0] << 56) |
        (cast(ulong) data[1] << 48) |
        (cast(ulong) data[2] << 40) |
        (cast(ulong) data[3] << 32) |
        (cast(ulong) data[4] << 24) |
        (cast(ulong) data[5] << 16) |
        (cast(ulong) data[6] << 8) |
        cast(ulong) data[7];

    return ParseResult!ulong.success(value);
}


/++
Reads an unsigned 64-bit little-endian integer.

On failure the cursor remains unchanged.
+/
ParseResult!ulong readU64LE(ref ByteCursor cursor)
    @safe pure nothrow @nogc
{
    auto bytes = cursor.takeBytes(8);

    if (bytes.hasError)
        return ParseResult!ulong.failure(bytes.error);

    const data = bytes.value.data;

    const value =
        cast(ulong) data[0] |
        (cast(ulong) data[1] << 8) |
        (cast(ulong) data[2] << 16) |
        (cast(ulong) data[3] << 24) |
        (cast(ulong) data[4] << 32) |
        (cast(ulong) data[5] << 40) |
        (cast(ulong) data[6] << 48) |
        (cast(ulong) data[7] << 56);

    return ParseResult!ulong.success(value);
}


/++
Reads a four-byte synchsafe unsigned integer.

Each input byte contributes seven payload bits. The most significant
bit of every byte must be zero, producing a 28-bit value stored in a
`uint`.

The input is inspected before it is consumed so that both truncated
and semantically invalid values leave the cursor unchanged.

Returns:
    The decoded value, `ParseErrorCode.endOfSpan` when fewer than four
    bytes remain, or `ParseErrorCode.invalidSynchsafeInteger` when an
    input byte has its most significant bit set.

Error semantics:
    Failure leaves the cursor unchanged. For an invalid synchsafe
    integer, the error offset identifies the offending byte.
+/
ParseResult!uint readSynchsafe32(ref ByteCursor cursor)
    @safe pure nothrow @nogc
{
    auto peeked = cursor.peekBytes(4);

    if (peeked.hasError)
        return ParseResult!uint.failure(peeked.error);

    const data = peeked.value.data;

    foreach (index, value; data)
    {
        if ((value & 0x80) != 0)
        {
            return ParseResult!uint.failure(
                ParseError(
                    ParseErrorCode.invalidSynchsafeInteger,
                    peeked.value.sourceOffset + index
                )
            );
        }
    }

    const value =
        (cast(uint) data[0] << 21) |
        (cast(uint) data[1] << 14) |
        (cast(uint) data[2] << 7) |
        cast(uint) data[3];

    auto consumed = cursor.skipBytes(4);

    if (consumed.hasError)
        return ParseResult!uint.failure(consumed.error);

    return ParseResult!uint.success(value);
}


import audiotag.core.span : ByteSpan;


/// 16-bit readers decode both byte orders.
unittest
{
    const ubyte[] bytes = [0x12, 0x34];

    auto be = ByteCursor(ByteSpan(bytes, 100));
    auto beResult = be.readU16BE();

    assert(beResult.hasValue);
    assert(beResult.value == 0x1234);
    assert(be.position == 2);

    auto le = ByteCursor(ByteSpan(bytes, 100));
    auto leResult = le.readU16LE();

    assert(leResult.hasValue);
    assert(leResult.value == 0x3412);
    assert(le.position == 2);
}


/// 24-bit readers decode both byte orders.
unittest
{
    const ubyte[] bytes = [0x12, 0x34, 0x56];

    auto be = ByteCursor(ByteSpan(bytes));
    auto beResult = be.readU24BE();

    assert(beResult.hasValue);
    assert(beResult.value == 0x123456);

    auto le = ByteCursor(ByteSpan(bytes));
    auto leResult = le.readU24LE();

    assert(leResult.hasValue);
    assert(leResult.value == 0x563412);
}


/// 32-bit readers decode both byte orders.
unittest
{
    const ubyte[] bytes = [0x12, 0x34, 0x56, 0x78];

    auto be = ByteCursor(ByteSpan(bytes));
    auto beResult = be.readU32BE();

    assert(beResult.hasValue);
    assert(beResult.value == 0x12345678);

    auto le = ByteCursor(ByteSpan(bytes));
    auto leResult = le.readU32LE();

    assert(leResult.hasValue);
    assert(leResult.value == 0x78563412);
}


/// 64-bit readers decode both byte orders.
unittest
{
    const ubyte[] bytes =
        [0x01, 0x23, 0x45, 0x67,
         0x89, 0xAB, 0xCD, 0xEF];

    auto be = ByteCursor(ByteSpan(bytes));
    auto beResult = be.readU64BE();

    assert(beResult.hasValue);
    assert(beResult.value == 0x0123456789ABCDEFUL);

    auto le = ByteCursor(ByteSpan(bytes));
    auto leResult = le.readU64LE();

    assert(leResult.hasValue);
    assert(leResult.value == 0xEFCDAB8967452301UL);
}


/// Numeric reads compose while preserving cursor position.
unittest
{
    const ubyte[] bytes =
        [0x12, 0x34, 0x56, 0x78, 0x9A];

    auto cursor = ByteCursor(ByteSpan(bytes, 200));

    auto first = cursor.readU16BE();
    auto second = cursor.readU24BE();

    assert(first.hasValue);
    assert(first.value == 0x1234);

    assert(second.hasValue);
    assert(second.value == 0x56789A);

    assert(cursor.position == 5);
    assert(cursor.absoluteOffset == 205);
    assert(cursor.empty);
}


/// Truncated numeric reads propagate endOfSpan atomically.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    const originalPosition = cursor.position;

    auto result = cursor.readU32BE();

    assert(result.hasError);

    const error = result.error;

    assert(error.code == ParseErrorCode.endOfSpan);
    assert(error.offset == 101);
    assert(error.requested == 4);
    assert(error.available == 2);

    assert(cursor.position == originalPosition);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.remaining == 2);
}


/// Synchsafe integers decode four seven-bit bytes into a 28-bit value.
unittest
{
    // 00 02 02 74 is the synchsafe representation of 33140.
    const ubyte[] bytes = [0x00, 0x02, 0x02, 0x74];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.readSynchsafe32();

    assert(result.hasValue);
    assert(result.value == 33140);
    assert(cursor.position == 4);
    assert(cursor.absoluteOffset == 104);
    assert(cursor.empty);
}


/// Synchsafe decoding handles the minimum and maximum values.
unittest
{
    {
        const ubyte[] bytes = [0x00, 0x00, 0x00, 0x00];

        auto cursor = ByteCursor(ByteSpan(bytes));
        auto result = cursor.readSynchsafe32();

        assert(result.hasValue);
        assert(result.value == 0);
    }

    {
        const ubyte[] bytes = [0x7F, 0x7F, 0x7F, 0x7F];

        auto cursor = ByteCursor(ByteSpan(bytes));
        auto result = cursor.readSynchsafe32();

        assert(result.hasValue);
        assert(result.value == 0x0FFF_FFFF);
    }
}


/// A truncated synchsafe integer fails atomically.
unittest
{
    const ubyte[] bytes = [0x00, 0x02, 0x02];

    auto cursor = ByteCursor(ByteSpan(bytes, 200));
    auto result = cursor.readSynchsafe32();

    assert(result.hasError);

    const error = result.error;

    assert(error.code == ParseErrorCode.endOfSpan);
    assert(error.offset == 200);
    assert(error.requested == 4);
    assert(error.available == 3);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 200);
    assert(cursor.remaining == 3);
}


/// Every byte of a synchsafe integer must have its high bit clear.
unittest
{
    foreach (invalidIndex; 0 .. 4)
    {
        ubyte[] bytes = [0x01, 0x02, 0x03, 0x04];
        bytes[invalidIndex] |= 0x80;

        auto cursor = ByteCursor(ByteSpan(bytes, 100));
        auto result = cursor.readSynchsafe32();

        assert(result.hasError);

        const error = result.error;

        assert(
            error.code ==
            ParseErrorCode.invalidSynchsafeInteger
        );
        assert(error.offset == 100 + invalidIndex);
        assert(error.requested == 0);
        assert(error.available == 0);

        assert(cursor.position == 0);
        assert(cursor.absoluteOffset == 100);
        assert(cursor.remaining == 4);
    }
}


/// Synchsafe reads respect an already advanced cursor.
unittest
{
    const ubyte[] bytes =
        [0x99, 0x00, 0x02, 0x02, 0x74, 0x55];

    auto cursor = ByteCursor(ByteSpan(bytes, 500));
    cursor.popFront();

    auto result = cursor.readSynchsafe32();

    assert(result.hasValue);
    assert(result.value == 33140);

    assert(cursor.position == 5);
    assert(cursor.absoluteOffset == 505);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}
