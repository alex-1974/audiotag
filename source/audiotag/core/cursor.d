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
