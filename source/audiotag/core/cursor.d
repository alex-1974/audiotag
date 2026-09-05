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


    /++
    Consumes bytes through the first occurrence of `pattern`.

    The returned span contains the bytes before the matched pattern.
    The pattern itself is consumed but is not included in the returned
    span.

    Searching is limited to at most `maxSearch` bytes beginning at the
    current cursor position. A pattern whose final byte lies exactly at
    the search boundary is considered a valid match.

    Params:
        pattern = Non-empty byte sequence to search for.
        maxSearch = Maximum number of bytes in which the complete
            pattern may occur.

    Returns:
        A successful result containing the bytes before the first
        matching pattern, `ParseErrorCode.patternNotFound` when no
        complete match exists inside the search region, or
        `ParseErrorCode.invalidLength` when `pattern` is empty.

    Error semantics:
        Failure leaves the cursor unchanged.

    Complexity:
        O(n * m), where `n` is the bounded search length and `m` is the
        pattern length.
    +/
    ParseResult!ByteSpan takeUntilPattern(
        const(ubyte)[] pattern,
        size_t maxSearch
    )
        @safe pure nothrow @nogc
    {
        if (pattern.length == 0)
        {
            return ParseResult!ByteSpan.failure(
                ParseError(
                    ParseErrorCode.invalidLength,
                    absoluteOffset,
                    0,
                    remaining
                )
            );
        }

        const searchLength =
            maxSearch < remaining
                ? maxSearch
                : remaining;

        if (pattern.length <= searchLength)
        {
            const lastStart = searchLength - pattern.length;

            for (size_t relativeOffset = 0;
                 relativeOffset <= lastStart;
                 ++relativeOffset)
            {
                bool matches = true;

                for (size_t patternOffset = 0;
                     patternOffset < pattern.length;
                     ++patternOffset)
                {
                    if (_span.data[
                            _position +
                            relativeOffset +
                            patternOffset
                        ] != pattern[patternOffset])
                    {
                        matches = false;
                        break;
                    }
                }

                if (matches)
                {
                    const result =
                        _span.subspan(_position, relativeOffset);

                    _position += relativeOffset + pattern.length;

                    return ParseResult!ByteSpan.success(result);
                }
            }
        }

        return ParseResult!ByteSpan.failure(
            ParseError(
                ParseErrorCode.patternNotFound,
                absoluteOffset,
                pattern.length,
                searchLength
            )
        );
    }


    /++
    Consumes bytes through the first aligned occurrence of `pattern`.

    Candidate matches are considered only at offsets that are multiples
    of `alignment` relative to the current cursor position.

    The returned span contains the bytes before the matched pattern.
    The pattern itself is consumed but is not included in the returned
    span.

    Searching is limited to at most `maxSearch` bytes beginning at the
    current cursor position. A pattern whose final byte lies exactly at
    the search boundary is considered a valid match.

    Params:
        pattern = Non-empty byte sequence to search for.
        maxSearch = Maximum number of bytes in which the complete
            pattern may occur.
        alignment = Required alignment of candidate match offsets
            relative to the current cursor position.

    Returns:
        A successful result containing the bytes before the first
        aligned match, `ParseErrorCode.patternNotFound` when no aligned
        complete match exists inside the search region, or
        `ParseErrorCode.invalidLength` when `pattern` is empty.

    Preconditions:
        `alignment` must be greater than zero.

    Error semantics:
        Failure leaves the cursor unchanged.

    Complexity:
        O((n / alignment) * m), where `n` is the bounded search length
        and `m` is the pattern length.
    +/
    ParseResult!ByteSpan takeUntilPatternAligned(
        const(ubyte)[] pattern,
        size_t maxSearch,
        size_t alignment
    )
        @safe pure nothrow @nogc
    {
        assert(alignment > 0);

        if (pattern.length == 0)
        {
            return ParseResult!ByteSpan.failure(
                ParseError(
                    ParseErrorCode.invalidLength,
                    absoluteOffset,
                    0,
                    remaining
                )
            );
        }

        const searchLength =
            maxSearch < remaining
                ? maxSearch
                : remaining;

        if (pattern.length <= searchLength)
        {
            const lastStart = searchLength - pattern.length;

            for (size_t relativeOffset = 0;
                 relativeOffset <= lastStart;
                 relativeOffset += alignment)
            {
                bool matches = true;

                for (size_t patternOffset = 0;
                     patternOffset < pattern.length;
                     ++patternOffset)
                {
                    if (_span.data[
                            _position +
                            relativeOffset +
                            patternOffset
                        ] != pattern[patternOffset])
                    {
                        matches = false;
                        break;
                    }
                }

                if (matches)
                {
                    const result =
                        _span.subspan(_position, relativeOffset);

                    _position += relativeOffset + pattern.length;

                    return ParseResult!ByteSpan.success(result);
                }
            }
        }

        return ParseResult!ByteSpan.failure(
            ParseError(
                ParseErrorCode.patternNotFound,
                absoluteOffset,
                pattern.length,
                searchLength
            )
        );
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


/// takeUntilPattern matches a pattern at the current position.
unittest
{
    const ubyte[] bytes = [0x00, 0x10, 0x20];
    const ubyte[] pattern = [0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.takeUntilPattern(pattern, 3);

    assert(result.hasValue);
    assert(result.value.empty);
    assert(result.value.sourceOffset == 100);

    assert(cursor.position == 1);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.remaining == 2);
}


/// takeUntilPattern returns data before a middle match and consumes it.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30, 0x40];
    const ubyte[] pattern = [0x20, 0x30];
    const ubyte[] expected = [0x10];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.takeUntilPattern(pattern, 4);

    assert(result.hasValue);
    assert(result.value.data == expected);
    assert(result.value.sourceOffset == 100);

    assert(cursor.position == 3);
    assert(cursor.absoluteOffset == 103);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x40);
}


/// takeUntilPattern accepts a match ending exactly at the search boundary.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30, 0x40];
    const ubyte[] pattern = [0x30, 0x40];
    const ubyte[] expected = [0x10, 0x20];

    auto cursor = ByteCursor(ByteSpan(bytes, 50));
    auto result = cursor.takeUntilPattern(pattern, 4);

    assert(result.hasValue);
    assert(result.value.data == expected);
    assert(result.value.sourceOffset == 50);

    assert(cursor.position == 4);
    assert(cursor.absoluteOffset == 54);
    assert(cursor.empty);
}


/// takeUntilPattern chooses the first of multiple matches.
unittest
{
    const ubyte[] bytes = [0x10, 0x00, 0x20, 0x00];
    const ubyte[] pattern = [0x00];
    const ubyte[] expected = [0x10];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.takeUntilPattern(pattern, 4);

    assert(result.hasValue);
    assert(result.value.data == expected);

    assert(cursor.position == 2);
    assert(cursor.front == 0x20);
}


/// takeUntilPattern correctly examines overlapping candidate positions.
unittest
{
    const ubyte[] bytes = [0x01, 0x01, 0x02];
    const ubyte[] pattern = [0x01, 0x02];
    const ubyte[] expected = [0x01];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.takeUntilPattern(pattern, 3);

    assert(result.hasValue);
    assert(result.value.data == expected);

    assert(cursor.position == 3);
    assert(cursor.empty);
}


/// A missing pattern reports the bounded search and preserves state.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    const originalPosition = cursor.position;
    auto result = cursor.takeUntilPattern([0x99], 2);

    assert(result.hasError);

    const error = result.error;

    assert(error.code == ParseErrorCode.patternNotFound);
    assert(error.offset == 101);
    assert(error.requested == 1);
    assert(error.available == 2);

    assert(cursor.position == originalPosition);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.remaining == 2);
}


/// A pattern longer than the available input cannot match.
unittest
{
    const ubyte[] bytes = [0x10, 0x20];
    const ubyte[] pattern = [0x10, 0x20, 0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.takeUntilPattern(pattern, 10);

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
    assert(result.error.requested == 3);
    assert(result.error.available == 2);

    assert(cursor.position == 0);
}


/// maxSearch prevents a match beyond the permitted search region.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30, 0x40];
    const ubyte[] pattern = [0x30];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.takeUntilPattern(pattern, 2);

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
    assert(result.error.requested == 1);
    assert(result.error.available == 2);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 100);
}


/// An empty pattern is invalid and never changes cursor state.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];
    const ubyte[] pattern = [];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    const originalPosition = cursor.position;
    auto result = cursor.takeUntilPattern(pattern, 2);

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 101);
    assert(result.error.requested == 0);
    assert(result.error.available == 2);

    assert(cursor.position == originalPosition);
    assert(cursor.absoluteOffset == 101);
}


/// A zero-byte search cannot find a non-empty pattern.
unittest
{
    const ubyte[] bytes = [0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 42));
    auto result = cursor.takeUntilPattern([0x00], 0);

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 42);
}


/// Aligned pattern search accepts a match at offset zero.
unittest
{
    const ubyte[] bytes = [0x00, 0x00, 0x41, 0x00];
    const ubyte[] pattern = [0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result =
        cursor.takeUntilPatternAligned(pattern, 4, 2);

    assert(result.hasValue);
    assert(result.value.empty);
    assert(result.value.sourceOffset == 100);

    assert(cursor.position == 2);
    assert(cursor.absoluteOffset == 102);
}


/// Aligned pattern search accepts a match on a valid code-unit boundary.
unittest
{
    const ubyte[] bytes =
        [0x41, 0x00, 0x42, 0x00, 0x00, 0x00, 0x43, 0x00];

    const ubyte[] pattern = [0x00, 0x00];
    const ubyte[] expected = [0x41, 0x00, 0x42, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 200));
    auto result =
        cursor.takeUntilPatternAligned(pattern, 8, 2);

    assert(result.hasValue);
    assert(result.value.data == expected);
    assert(result.value.sourceOffset == 200);

    assert(cursor.position == 6);
    assert(cursor.absoluteOffset == 206);
    assert(cursor.remaining == 2);
}


/// Aligned search ignores an identical byte pattern at an invalid offset.
unittest
{
    const ubyte[] bytes =
        [0x41, 0x00, 0x00, 0x42, 0x00, 0x00, 0x43];

    const ubyte[] pattern = [0x00, 0x00];
    const ubyte[] expected =
        [0x41, 0x00, 0x00, 0x42];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result =
        cursor.takeUntilPatternAligned(pattern, 7, 2);

    assert(result.hasValue);
    assert(result.value.data == expected);

    // The candidate at relative offset 1 is ignored.
    // The valid aligned match begins at relative offset 4.
    assert(cursor.position == 6);
    assert(cursor.front == 0x43);
}


/// Alignment is relative to the cursor start, not the absolute file offset.
unittest
{
    const ubyte[] bytes =
        [0x99, 0x41, 0x00, 0x00, 0x42];

    const ubyte[] pattern = [0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    cursor.popFront();

    auto result =
        cursor.takeUntilPatternAligned(pattern, 4, 2);

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);

    // Relative offset 1 contains the pattern but is not aligned
    // relative to the cursor position at absolute offset 101.
    assert(cursor.position == 1);
    assert(cursor.absoluteOffset == 101);
}


/// Alignment 1 has the same matching behavior as unaligned search.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30, 0x40];
    const ubyte[] pattern = [0x20, 0x30];
    const ubyte[] expected = [0x10];

    auto cursor = ByteCursor(ByteSpan(bytes, 50));
    auto result =
        cursor.takeUntilPatternAligned(pattern, 4, 1);

    assert(result.hasValue);
    assert(result.value.data == expected);
    assert(cursor.position == 3);
}


/// Alignment 4 examines only offsets divisible by four.
unittest
{
    const ubyte[] bytes =
        [0x10, 0x99, 0x20, 0x99,
         0x30, 0x40, 0x50, 0x60];

    const ubyte[] pattern = [0x30, 0x40];
    const ubyte[] expected = [0x10, 0x99, 0x20, 0x99];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result =
        cursor.takeUntilPatternAligned(pattern, 8, 4);

    assert(result.hasValue);
    assert(result.value.data == expected);
    assert(cursor.position == 6);
}


/// Aligned search accepts a match ending exactly at maxSearch.
unittest
{
    const ubyte[] bytes =
        [0x10, 0x20, 0x30, 0x40];

    const ubyte[] pattern = [0x30, 0x40];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result =
        cursor.takeUntilPatternAligned(pattern, 4, 2);

    assert(result.hasValue);
    assert(result.value.length == 2);
    assert(cursor.position == 4);
    assert(cursor.empty);
}


/// Aligned search failure preserves the complete cursor state.
unittest
{
    const ubyte[] bytes =
        [0x10, 0x00, 0x00, 0x20];

    const ubyte[] pattern = [0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));

    const originalPosition = cursor.position;
    auto result =
        cursor.takeUntilPatternAligned(pattern, 4, 2);

    assert(result.hasError);

    const error = result.error;

    assert(error.code == ParseErrorCode.patternNotFound);
    assert(error.offset == 100);
    assert(error.requested == 2);
    assert(error.available == 4);

    assert(cursor.position == originalPosition);
    assert(cursor.absoluteOffset == 100);
    assert(cursor.remaining == 4);
}


/// Empty patterns remain invalid for aligned searches.
unittest
{
    const ubyte[] bytes = [0x10, 0x20];
    const ubyte[] pattern = [];

    auto cursor = ByteCursor(ByteSpan(bytes, 42));

    auto result =
        cursor.takeUntilPatternAligned(pattern, 2, 2);

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 42);

    assert(cursor.position == 0);
}
