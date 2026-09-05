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
import audiotag.core.result : ParseResult, ParseStatus;
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


    /++
    Consumes and returns up to `count` bytes.

    Unlike `takeBytes`, this operation is explicitly partial and cannot
    fail because fewer than `count` bytes remain. It consumes all
    remaining bytes when `count` exceeds the available length.

    Params:
        count = Maximum number of bytes to consume.

    Returns:
        A span containing between zero and `count` bytes.

    Note:
        A zero-length request succeeds without changing the cursor.
    +/
    ByteSpan takeAvailable(size_t count)
        @safe pure nothrow @nogc
    {
        const actual =
            count < remaining
                ? count
                : remaining;

        const result = _span.subspan(_position, actual);

        _position += actual;

        return result;
    }


    /++
    Advances the cursor by exactly `count` bytes.

    Params:
        count = Number of bytes to skip.

    Returns:
        A successful status when exactly `count` bytes can be skipped,
        or `ParseErrorCode.endOfSpan` when fewer bytes remain.

    Error semantics:
        On success the cursor advances by exactly `count` bytes.
        On failure the cursor position is unchanged.
    +/
    ParseStatus skipBytes(size_t count)
        @safe pure nothrow @nogc
    {
        if (count > remaining)
        {
            return ParseStatus.failure(
                ParseError(
                    ParseErrorCode.endOfSpan,
                    absoluteOffset,
                    count,
                    remaining
                )
            );
        }

        _position += count;

        return ParseStatus.success();
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


/// takeAvailable consumes at most the requested number of bytes.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30, 0x40];
    const ubyte[] expected = [0x10, 0x20];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    const result = cursor.takeAvailable(2);

    assert(result.data == expected);
    assert(result.sourceOffset == 100);
    assert(cursor.position == 2);
    assert(cursor.absoluteOffset == 102);
    assert(cursor.remaining == 2);
}


/// takeAvailable consumes all remaining bytes when the request is larger.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    const result = cursor.takeAvailable(10);

    assert(result.length == 2);
    assert(result.sourceOffset == 101);
    assert(result.data == bytes[1 .. $]);

    assert(cursor.position == 3);
    assert(cursor.absoluteOffset == 103);
    assert(cursor.remaining == 0);
    assert(cursor.empty);
}


/// takeAvailable accepts a zero-length request without advancing.
unittest
{
    const ubyte[] bytes = [0x10, 0x20];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    const result = cursor.takeAvailable(0);

    assert(result.empty);
    assert(result.sourceOffset == 101);
    assert(cursor.position == 1);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.remaining == 1);
}


/// takeAvailable on an empty cursor returns an empty end-position span.
unittest
{
    const ubyte[] bytes = [0x10];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    const result = cursor.takeAvailable(5);

    assert(result.empty);
    assert(result.sourceOffset == 101);
    assert(cursor.position == 1);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.empty);
}


/// skipBytes advances by exactly the requested number of bytes.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30, 0x40];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto status = cursor.skipBytes(2);

    assert(status.succeeded);
    assert(!status.hasError);
    assert(cursor.position == 2);
    assert(cursor.absoluteOffset == 102);
    assert(cursor.remaining == 2);
    assert(cursor.front == 0x30);
}


/// skipBytes may advance exactly to the end of the span.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 50));
    auto status = cursor.skipBytes(3);

    assert(status.succeeded);
    assert(cursor.position == 3);
    assert(cursor.absoluteOffset == 53);
    assert(cursor.remaining == 0);
    assert(cursor.empty);
}


/// skipBytes failure reports bounds and leaves the cursor unchanged.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    const originalPosition = cursor.position;
    auto status = cursor.skipBytes(3);

    assert(status.hasError);
    assert(!status.succeeded);

    const error = status.error;

    assert(error.code == ParseErrorCode.endOfSpan);
    assert(error.offset == 101);
    assert(error.requested == 3);
    assert(error.available == 2);

    assert(cursor.position == originalPosition);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.remaining == 2);
}


/// skipBytes accepts a zero-length request without advancing.
unittest
{
    const ubyte[] bytes = [0x10];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    auto status = cursor.skipBytes(0);

    assert(status.succeeded);
    assert(cursor.position == 1);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.empty);
}


/// skipBytes on an empty cursor fails only for a nonzero request.
unittest
{
    const ubyte[] bytes = [];

    auto cursor = ByteCursor(ByteSpan(bytes, 42));

    auto zero = cursor.skipBytes(0);

    assert(zero.succeeded);
    assert(cursor.position == 0);

    auto one = cursor.skipBytes(1);

    assert(one.hasError);
    assert(one.error.code == ParseErrorCode.endOfSpan);
    assert(one.error.offset == 42);
    assert(one.error.requested == 1);
    assert(one.error.available == 0);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 42);
}
