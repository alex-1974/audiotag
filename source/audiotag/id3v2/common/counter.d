/++
Shared semantic representation of an ID3v2 play counter.

ID3v2.2 `CNT` and ID3v2.3/v2.4 `PCNT`, as well as the optional counter in
`POP`/`POPM`, use the same counter representation:

- unsigned;
- most-significant byte first;
- at least four bytes when present;
- width may grow beyond 32 or 64 bits;
- leading zero bytes are semantically significant to the native
  representation and are preserved.

This type therefore stores the exact logical big-endian counter bytes rather
than narrowing the value to a machine integer.
+/
module audiotag.id3v2.common.counter;


/++
One decoded ID3v2 counter value.

The byte array contains the logical counter bytes after any revision-specific
unsynchronisation/transformation has been removed.

Construction assumes the surrounding frame codec has already validated the
minimum width required by the applicable ID3v2 frame.
+/
struct Id3v2Counter
{
private:
    ubyte[] _bigEndianBytes;

public:
    /++
    Takes ownership-by-convention of already decoded logical counter bytes.

    The array is retained without normalization so leading zero bytes and
    arbitrary widths survive exactly.
    +/
    this(
        ubyte[] bigEndianBytes
    )
        @safe pure nothrow @nogc
    {
        _bigEndianBytes =
            bigEndianBytes;
    }


    /// Exact logical big-endian counter bytes.
    @property
    const(ubyte)[] bigEndianBytes() const
        @safe pure nothrow @nogc
    {
        return
            _bigEndianBytes;
    }


    /// Logical counter width in bytes.
    @property
    size_t byteLength() const
        @safe pure nothrow @nogc
    {
        return
            _bigEndianBytes.length;
    }
}


/// Leading zero bytes are preserved exactly.
unittest
{
    ubyte[] bytes =
        [
            0x00,
            0x00,
            0x00,
            0x01
        ];

    const counter =
        Id3v2Counter(
            bytes
        );

    assert(counter.byteLength == 4);

    assert(
        counter.bigEndianBytes ==
        [
            0x00,
            0x00,
            0x00,
            0x01
        ]
    );
}


/// Counter width is not limited to a machine integer.
unittest
{
    ubyte[] bytes =
        [
            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C
        ];

    const counter =
        Id3v2Counter(
            bytes
        );

    assert(counter.byteLength == 12);
    assert(counter.bigEndianBytes == bytes);
}
