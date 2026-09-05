/++
Materialisation of logical ID3v2.4 bytes from bounded physical spans.

Some ID3v2.4 frame payloads retain their exact physical source bytes in
the native representation. When byte unsynchronisation was effective,
a physical `$FF $00` pair represents one logical `$FF`.

This module provides the allocating semantic-layer counterpart to the
zero-copy `Id3v24DataCursor`: it copies a bounded physical `ByteSpan`
into owned logical bytes without using assertions or exceptions for
source data.

The returned array is independent of the parser input buffer.
+/
module audiotag.id3v2.v24.logical_bytes;

import audiotag.core.span :
    ByteSpan;


/++
Copies one bounded ID3v2.4 byte span into logical byte representation.

When `unsynchronised` is false, all bytes are copied unchanged.

When `unsynchronised` is true, every physical `$FF $00` pair becomes
one logical `$FF`. Other bytes are copied unchanged. A final `$FF`
requires no look-ahead beyond the bounded span and remains `$FF`.

Params:
    span = Bounded physical source bytes.
    unsynchronised = Whether ID3 byte unsynchronisation is effective.

Returns:
    Independent logical byte array.

Safety:
    The function reads only inside `span`. No malformed-input condition
    is represented through an assertion.
+/
ubyte[] copyId3v24LogicalBytes(
    ByteSpan span,
    bool unsynchronised
)
    @safe
{
    if (!unsynchronised)
    {
        return span.data.dup;
    }

    auto logical =
        new ubyte[span.length];

    size_t physicalPosition = 0;
    size_t logicalLength = 0;

    while (physicalPosition < span.length)
    {
        const value =
            span.data[physicalPosition];

        ++physicalPosition;

        logical[logicalLength] =
            value;

        ++logicalLength;

        if (
            value == 0xFF &&
            physicalPosition < span.length &&
            span.data[physicalPosition] == 0x00
        )
        {
            ++physicalPosition;
        }
    }

    return logical[0 .. logicalLength];
}


/// Normal physical bytes are copied unchanged.
unittest
{
    const ubyte[] bytes =
        [0x11, 0x22, 0x33];

    auto logical =
        copyId3v24LogicalBytes(
            ByteSpan(bytes, 100),
            false
        );

    assert(
        logical ==
        [0x11, 0x22, 0x33]
    );

    assert(logical.ptr != bytes.ptr);
}


/// Physical unsynchronisation stuffing is removed.
unittest
{
    const ubyte[] bytes =
        [
            0x11,
            0xFF, 0x00, 0xE1,
            0x22,
            0xFF, 0x00, 0x00,
            0x33
        ];

    auto logical =
        copyId3v24LogicalBytes(
            ByteSpan(bytes, 200),
            true
        );

    assert(
        logical ==
        [
            0x11,
            0xFF, 0xE1,
            0x22,
            0xFF, 0x00,
            0x33
        ]
    );
}


/// A final FF byte remains valid and never requires out-of-bounds look-ahead.
unittest
{
    const ubyte[] bytes =
        [0x11, 0xFF];

    auto logical =
        copyId3v24LogicalBytes(
            ByteSpan(bytes, 300),
            true
        );

    assert(
        logical ==
        [0x11, 0xFF]
    );
}


/// Empty spans remain empty in both modes.
unittest
{
    const ubyte[] bytes = [];

    assert(
        copyId3v24LogicalBytes(
            ByteSpan(bytes, 400),
            false
        ).length == 0
    );

    assert(
        copyId3v24LogicalBytes(
            ByteSpan(bytes, 400),
            true
        ).length == 0
    );
}
