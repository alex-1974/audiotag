/++
Bounded zero-copy byte spans used by audiotag parsers.

A `ByteSpan` represents a fixed view into an existing byte source.
It neither owns nor copies the referenced payload.

Nested parsers can receive subspans so that each parser is confined
to the byte region assigned by its parent parser.

`ByteSpan` has no mutable parsing position. Stateful traversal is
handled separately by `ByteCursor`.

The referenced bytes are exposed as `const(ubyte)[]`: audiotag may
read the bytes but cannot modify them through the span.
+/
module audiotag.core.span;


/++
A fixed, bounded, zero-copy view of a byte sequence.

`sourceOffset` records the absolute position of the first byte in the
original byte source. This allows nested parsers to retain source
locations without depending on files or other I/O mechanisms.

The span does not imply ownership of the referenced storage.
+/
struct ByteSpan
{
    private const(ubyte)[] _data;
    private size_t _sourceOffset;

    /++
    Constructs a byte span.

    Params:
        data = Bytes represented by this span.
        sourceOffset = Absolute offset of `data[0]` in the original
            byte source.
    +/
    this(const(ubyte)[] data, size_t sourceOffset = 0)
        @safe pure nothrow @nogc
    {
        _data = data;
        _sourceOffset = sourceOffset;
    }

    /++
    Returns the bytes referenced by this span.

    No payload bytes are copied.
    +/
    @property
    const(ubyte)[] data() const
        @safe pure nothrow @nogc
    {
        return _data;
    }

    /++
    Returns the number of bytes in this span.
    +/
    @property
    size_t length() const
        @safe pure nothrow @nogc
    {
        return _data.length;
    }

    /++
    Returns whether the span contains no bytes.
    +/
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return _data.length == 0;
    }

    /++
    Returns the absolute source offset of the first byte in this span.
    +/
    @property
    size_t sourceOffset() const
        @safe pure nothrow @nogc
    {
        return _sourceOffset;
    }

    /++
    Creates a bounded subspan without copying payload bytes.

    Params:
        relativeOffset = Offset relative to the beginning of this span.
        count = Number of bytes in the resulting span.

    Returns:
        A span referencing exactly the requested region.

    Preconditions:
        The requested region must be fully contained in this span.

    Note:
        These bounds are an internal program invariant. Lengths obtained
        from untrusted file data must be validated before calling this
        function. Malformed input must not be handled through assertions.
    +/
    ByteSpan subspan(size_t relativeOffset, size_t count) const
        @safe pure nothrow @nogc
    {
        assert(relativeOffset <= _data.length);
        assert(count <= _data.length - relativeOffset);

        return ByteSpan(
            _data[relativeOffset .. relativeOffset + count],
            _sourceOffset + relativeOffset
        );
    }
}


/// Basic construction and properties.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30, 0x40];

    const span = ByteSpan(bytes, 100);

    assert(span.length == 4);
    assert(!span.empty);
    assert(span.sourceOffset == 100);
    assert(span.data == bytes);
}


/// Empty spans are valid and preserve their source position.
unittest
{
    const ubyte[] bytes = [];

    const span = ByteSpan(bytes, 42);

    assert(span.empty);
    assert(span.length == 0);
    assert(span.sourceOffset == 42);
}


/// A subspan preserves its absolute source position.
unittest
{
    const ubyte[] bytes =
        [0x10, 0x20, 0x30, 0x40, 0x50];

    const ubyte[] expected =
        [0x20, 0x30, 0x40];

    const span = ByteSpan(bytes, 100);
    const child = span.subspan(1, 3);

    assert(child.length == 3);
    assert(child.sourceOffset == 101);
    assert(child.data == expected);
}


/// Nested subspans retain correct absolute offsets.
unittest
{
    const ubyte[] bytes =
        [0x10, 0x20, 0x30, 0x40, 0x50];

    const ubyte[] expected = [0x30];

    const root = ByteSpan(bytes, 100);
    const child = root.subspan(1, 3);
    const grandchild = child.subspan(1, 1);

    assert(grandchild.length == 1);
    assert(grandchild.sourceOffset == 102);
    assert(grandchild.data == expected);
}


/// Zero-length subspans are valid, including at the end.
unittest
{
    const ubyte[] bytes = [0x10, 0x20, 0x30];

    const span = ByteSpan(bytes, 100);

    const beginning = span.subspan(0, 0);
    const end = span.subspan(span.length, 0);

    assert(beginning.empty);
    assert(beginning.sourceOffset == 100);

    assert(end.empty);
    assert(end.sourceOffset == 103);
}


/// ByteSpan is a zero-copy read-only view, not an immutable copy.
unittest
{
    ubyte[] bytes = [0x10, 0x20, 0x30];

    const span = ByteSpan(bytes);

    bytes[1] = 0x99;

    assert(span.data[1] == 0x99);
}
