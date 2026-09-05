/++
Stateful bounded traversal over a `ByteSpan`.

`ByteCursor` maintains a position inside one fixed span. It does not
own or copy the referenced bytes.

The cursor is always confined to its underlying span. Operations that
consume bytes advance only the cursor position; the `ByteSpan` itself
remains unchanged.

Fallible exact and partial byte operations are added separately.
+/
module audiotag.core.cursor;

import audiotag.core.error : ParseError, ParseErrorCode;
import audiotag.core.result : ParseResult;
import audiotag.core.span : ByteSpan;


/++
A stateful cursor over one bounded byte span.

The cursor position is relative to the beginning of the span.
`absoluteOffset` translates that position back to the original byte
source through `ByteSpan.sourceOffset`.
+/
struct ByteCursor
{
    private ByteSpan _span;
    private size_t _position;

    /++
    Constructs a cursor positioned at the beginning of `span`.

    Params:
        span = Bounded byte region traversed by this cursor.
    +/
    this(ByteSpan span)
        @safe pure nothrow @nogc
    {
        _span = span;
        _position = 0;
    }

    /++
    Returns the current position relative to the beginning of the span.
    +/
    @property
    size_t position() const
        @safe pure nothrow @nogc
    {
        return _position;
    }

    /++
    Returns the absolute source offset of the current cursor position.
    +/
    @property
    size_t absoluteOffset() const
        @safe pure nothrow @nogc
    {
        return _span.sourceOffset + _position;
    }

    /++
    Returns the number of bytes remaining after the current position.
    +/
    @property
    size_t remaining() const
        @safe pure nothrow @nogc
    {
        return _span.length - _position;
    }

    /++
    Returns whether no bytes remain in the cursor.
    +/
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return _position == _span.length;
    }

    /++
    Returns the byte at the current cursor position without consuming it.

    Preconditions:
        The cursor must not be empty.

    Note:
        Calling `front` on an empty cursor is a programmer error.
        Malformed external input is handled by fallible parsing
        operations rather than by this range primitive.
    +/
    @property
    ubyte front() const
        @safe pure nothrow @nogc
    {
        assert(!empty);

        return _span.data[_position];
    }

    /++
    Advances the cursor by one byte.

    Preconditions:
        The cursor must not be empty.

    Note:
        Calling `popFront` on an empty cursor is a programmer error.
        Specification-defined reads from untrusted input use fallible
        bounded operations instead.
    +/
    void popFront()
        @safe pure nothrow @nogc
    {
        assert(!empty);

        ++_position;
    }

    /++
    Returns exactly `count` bytes from the current cursor position
    without consuming them.

    Params:
        count = Number of bytes required.

    Returns:
        A successful result containing exactly `count` bytes, or
        `ParseErrorCode.endOfSpan` when fewer bytes remain.

    Error semantics:
        Failure leaves the cursor unchanged. The error offset is the
        absolute current cursor position.
    +/
    ParseResult!ByteSpan peekBytes(size_t count) const
        @safe pure nothrow @nogc
    {
        if (count > remaining)
        {
            return ParseResult!ByteSpan.failure(
                ParseError(
                    ParseErrorCode.endOfSpan,
                    absoluteOffset,
                    count,
                    remaining
                )
            );
        }

        return ParseResult!ByteSpan.success(
            _span.subspan(_position, count)
        );
    }

    /++
    Consumes and returns exactly `count` bytes.

    Params:
        count = Number of bytes required.

    Returns:
        A successful result containing exactly `count` bytes, or
        `ParseErrorCode.endOfSpan` when fewer bytes remain.

    Error semantics:
        On success the cursor advances by exactly `count` bytes.
        On failure the cursor position is unchanged.
    +/
    ParseResult!ByteSpan takeBytes(size_t count)
        @safe pure nothrow @nogc
    {
        auto result = peekBytes(count);

        if (result.hasError)
            return result;

        _position += count;

        return result;
    }
}


/// A new cursor starts at the beginning of its span.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];
    const span = ByteSpan(bytes, 100);

    const cursor = ByteCursor(span);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 100);
    assert(cursor.remaining == 3);
    assert(!cursor.empty);
    assert(cursor.front == 0x10);
}


/// Empty spans produce valid empty cursors.
unittest
{
    const ubyte[] bytes = [];
    const span = ByteSpan(bytes, 42);

    const cursor = ByteCursor(span);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 42);
    assert(cursor.remaining == 0);
    assert(cursor.empty);
}


/// popFront advances relative and absolute cursor state by one byte.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];
    const span = ByteSpan(bytes, 100);

    auto cursor = ByteCursor(span);

    cursor.popFront();

    assert(cursor.position == 1);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.remaining == 2);
    assert(!cursor.empty);
    assert(cursor.front == 0x20);
}


/// Consuming the final byte leaves the cursor exactly at the span end.
unittest
{
    const ubyte[] bytes = [0x10];
    const span = ByteSpan(bytes, 100);

    auto cursor = ByteCursor(span);

    assert(cursor.front == 0x10);
    cursor.popFront();

    assert(cursor.position == 1);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.remaining == 0);
    assert(cursor.empty);
}


/// peekBytes returns an exact span without advancing the cursor.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30, 0x40];
    const ubyte[] expected = [0x20, 0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    const originalPosition = cursor.position;
    auto result = cursor.peekBytes(2);

    assert(result.hasValue);
    assert(result.value.data == expected);
    assert(result.value.sourceOffset == 101);
    assert(cursor.position == originalPosition);
    assert(cursor.absoluteOffset == 101);
}


/// peekBytes accepts an exact-boundary request.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 50));
    auto result = cursor.peekBytes(3);

    assert(result.hasValue);
    assert(result.value.length == 3);
    assert(result.value.sourceOffset == 50);
    assert(cursor.position == 0);
}


/// peekBytes failure reports bounds and preserves cursor state.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    const originalPosition = cursor.position;
    auto result = cursor.peekBytes(3);

    assert(result.hasError);

    const error = result.error;

    assert(error.code == ParseErrorCode.endOfSpan);
    assert(error.offset == 101);
    assert(error.requested == 3);
    assert(error.available == 2);
    assert(cursor.position == originalPosition);
}


/// takeBytes returns an exact span and advances by exactly its length.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30, 0x40];
    const ubyte[] expected = [0x10, 0x20];

    auto cursor = ByteCursor(ByteSpan(bytes, 200));
    auto result = cursor.takeBytes(2);

    assert(result.hasValue);
    assert(result.value.data == expected);
    assert(result.value.sourceOffset == 200);
    assert(cursor.position == 2);
    assert(cursor.absoluteOffset == 202);
    assert(cursor.remaining == 2);
}


/// takeBytes may consume exactly all remaining bytes.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.takeBytes(3);

    assert(result.hasValue);
    assert(result.value.length == 3);
    assert(cursor.position == 3);
    assert(cursor.absoluteOffset == 103);
    assert(cursor.remaining == 0);
    assert(cursor.empty);
}


/// takeBytes failure is atomic and does not partially consume input.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    const originalPosition = cursor.position;
    auto result = cursor.takeBytes(3);

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 101);
    assert(result.error.requested == 3);
    assert(result.error.available == 2);

    assert(cursor.position == originalPosition);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.remaining == 2);
}


/// Zero-length exact operations succeed even at the end of a span.
unittest
{
    const ubyte[] bytes = [0x10];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    auto peeked = cursor.peekBytes(0);

    assert(peeked.hasValue);
    assert(peeked.value.empty);
    assert(peeked.value.sourceOffset == 101);
    assert(cursor.position == 1);

    auto taken = cursor.takeBytes(0);

    assert(taken.hasValue);
    assert(taken.value.empty);
    assert(taken.value.sourceOffset == 101);
    assert(cursor.position == 1);
    assert(cursor.empty);
}
