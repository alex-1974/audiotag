/++
Logical traversal over bounded ID3v2.2 tag-body data.

ID3v2.2 unsynchronisation is a tag-level transformation. This cursor preserves
the already bounded physical source `ByteSpan` while optionally exposing
logical bytes after removal of inserted unsynchronisation zero bytes.

No decoded buffer is materialised. Physical source offsets remain available
for diagnostics and provenance.


Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.data_cursor;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.unsync :
    Id3v2DecodedByte,
    takeId3v2UnsynchronisedByte;


/++
Cursor over one already bounded physical ID3v2.2 tag-body region.

When `unsynchronised` is true, logical reads remove ID3v2 stuffing bytes while
the underlying physical cursor continues to track the exact source
representation.
+/
struct Id3v22DataCursor
{
private:
    ByteSpan _span;
    ByteCursor _cursor;
    size_t _logicalPosition;
    bool _unsynchronised;

public:
    /++
    Constructs a logical ID3v2.2 data cursor.

    Params:
        span = Hard physical boundary for all reads.
        unsynchronised = Whether ID3v2.2 tag-level unsynchronisation must be
            reversed during logical reads.
    +/
    this(
        ByteSpan span,
        bool unsynchronised
    )
        @safe pure nothrow @nogc
    {
        _span =
            span;

        _cursor =
            ByteCursor(span);

        _logicalPosition =
            0;

        _unsynchronised =
            unsynchronised;
    }


    /// Physical position relative to the beginning of the source span.
    @property
    size_t physicalPosition() const
        @safe pure nothrow @nogc
    {
        return
            _cursor.position;
    }


    /// Number of logical bytes consumed after unsynchronisation decoding.
    @property
    size_t logicalPosition() const
        @safe pure nothrow @nogc
    {
        return
            _logicalPosition;
    }


    /// Absolute physical source offset of the next unread byte.
    @property
    size_t absoluteOffset() const
        @safe pure nothrow @nogc
    {
        return
            _cursor.absoluteOffset;
    }


    /// Number of unread physical source bytes.
    @property
    size_t remainingPhysical() const
        @safe pure nothrow @nogc
    {
        return
            _cursor.remaining;
    }


    /// Whether no physical source bytes remain.
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return
            _cursor.empty;
    }


    /// Whether logical reads reverse ID3v2.2 tag-level unsynchronisation.
    @property
    bool unsynchronised() const
        @safe pure nothrow @nogc
    {
        return
            _unsynchronised;
    }


    /// Raw physical bytes that have not yet been consumed.
    @property
    ByteSpan remainingRaw() const
        @safe pure nothrow @nogc
    {
        return
            _span.subspan(
                _cursor.position,
                _cursor.remaining
            );
    }


    /++
    Consumes one logical byte.

    Without unsynchronisation exactly one physical byte is consumed.

    With unsynchronisation an encoded physical `$FF $00` sequence produces one
    logical `$FF` while consuming both physical bytes.

    Returns:
        The logical byte together with the physical source offset of the byte
        that produced it.

    Error semantics:
        Failure leaves this cursor unchanged.
    +/
    ParseResult!Id3v2DecodedByte
    takeByte()
        @safe pure nothrow @nogc
    {
        if (_unsynchronised)
        {
            auto result =
                _cursor
                    .takeId3v2UnsynchronisedByte();

            if (result.hasError)
            {
                return
                    ParseResult!Id3v2DecodedByte
                        .failure(
                            result.error
                        );
            }

            ++_logicalPosition;

            return result;
        }

        auto result =
            _cursor.takeBytes(1);

        if (result.hasError)
        {
            return
                ParseResult!Id3v2DecodedByte
                    .failure(
                        result.error
                    );
        }

        ++_logicalPosition;

        return
            ParseResult!Id3v2DecodedByte
                .success(
                    Id3v2DecodedByte(
                        result.value.data[0],
                        result.value.sourceOffset
                    )
                );
    }


    /++
    Reads one unsigned 16-bit big-endian integer from the logical byte stream.

    Two logical bytes are required.

    Error semantics:
        Failure leaves this cursor unchanged.
    +/
    ParseResult!ushort
    takeU16BE()
        @safe pure nothrow @nogc
    {
        auto probe =
            this;

        ushort value =
            0;

        foreach (
            index;
            0 .. 2
        )
        {
            auto byteResult =
                probe.takeByte();

            if (byteResult.hasError)
            {
                return
                    ParseResult!ushort
                        .failure(
                            byteResult.error
                        );
            }

            value =
                cast(ushort)
                    (
                        (
                            cast(uint) value <<
                            8
                        ) |
                        cast(uint)
                            byteResult.value.value
                    );
        }

        this =
            probe;

        return
            ParseResult!ushort
                .success(value);
    }


    /++
    Reads one unsigned 24-bit big-endian integer from the logical byte stream.

    Three logical bytes are required. This is the integer representation used
    by ID3v2.2 frame sizes.

    Unlike the four-byte ID3 tag-size field, this value is not synchsafe.

    Returns:
        The decoded unsigned 24-bit value in a `uint`, or a structured parse
        error.

    Error semantics:
        Failure leaves this cursor unchanged.
    +/
    ParseResult!uint
    takeU24BE()
        @safe pure nothrow @nogc
    {
        auto probe =
            this;

        uint value =
            0;

        foreach (
            index;
            0 .. 3
        )
        {
            auto byteResult =
                probe.takeByte();

            if (byteResult.hasError)
            {
                return
                    ParseResult!uint
                        .failure(
                            byteResult.error
                        );
            }

            value =
                (
                    value << 8
                ) |
                cast(uint)
                    byteResult.value.value;
        }

        this =
            probe;

        return
            ParseResult!uint
                .success(value);
    }


    /++
    Reads one unsigned 32-bit big-endian integer from the logical byte stream.

    Four logical bytes are required. This is the integer representation used
    by ID3v2 synchronisation timestamps.

    Returns:
        The decoded unsigned 32-bit value, or a structured parse error.

    Error semantics:
        Failure leaves this cursor unchanged.
    +/
    ParseResult!uint
    takeU32BE()
        @safe pure nothrow @nogc
    {
        auto probe =
            this;

        uint value =
            0;

        foreach (
            index;
            0 .. 4
        )
        {
            auto byteResult =
                probe.takeByte();

            if (byteResult.hasError)
            {
                return
                    ParseResult!uint
                        .failure(
                            byteResult.error
                        );
            }

            value =
                (
                    value << 8
                ) |
                cast(uint)
                    byteResult.value.value;
        }

        this =
            probe;

        return
            ParseResult!uint
                .success(value);
    }


    /++
    Consumes exactly `count` logical bytes and returns their complete physical
    source region.

    In normal mode the physical and logical lengths are identical.

    With unsynchronisation the returned physical `ByteSpan` may be longer than
    `count` because inserted `$00` stuffing bytes remain part of the preserved
    source representation.

    Params:
        count = Number of logical bytes to consume.

    Returns:
        The physical source span containing exactly the bytes consumed to
        produce `count` logical bytes.

    Error semantics:
        Failure leaves this cursor unchanged.
    +/
    ParseResult!ByteSpan
    takeLogicalRegion(
        size_t count
    )
        @safe pure nothrow @nogc
    {
        auto probe =
            this;

        const startPhysical =
            probe.physicalPosition;

        if (!probe._unsynchronised)
        {
            auto result =
                probe._cursor
                    .takeBytes(count);

            if (result.hasError)
            {
                return
                    ParseResult!ByteSpan
                        .failure(
                            result.error
                        );
            }

            probe._logicalPosition +=
                count;

            this =
                probe;

            return result;
        }

        foreach (
            index;
            0 .. count
        )
        {
            auto byteResult =
                probe.takeByte();

            if (byteResult.hasError)
            {
                return
                    ParseResult!ByteSpan
                        .failure(
                            byteResult.error
                        );
            }
        }

        const consumedPhysical =
            probe.physicalPosition -
            startPhysical;

        auto physical =
            _span.subspan(
                startPhysical,
                consumedPhysical
            );

        this =
            probe;

        return
            ParseResult!ByteSpan
                .success(physical);
    }
}


version (unittest)
{
    import audiotag.core.error :
        ParseErrorCode;
}


/// Normal mode consumes one physical byte per logical byte.
unittest
{
    const ubyte[] bytes =
        [
            0x11,
            0x22
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                100
            ),
            false
        );

    auto result =
        cursor.takeByte();

    assert(result.hasValue);
    assert(result.value.value == 0x11);
    assert(result.value.sourceOffset == 100);

    assert(cursor.logicalPosition == 1);
    assert(cursor.physicalPosition == 1);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.remainingPhysical == 1);

    assert(
        cursor.remainingRaw.data ==
        [0x22]
    );
}


/// Unsynchronised mode removes one physical stuffing zero.
unittest
{
    const ubyte[] bytes =
        [
            0xFF,
            0x00,
            0xE1
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                200
            ),
            true
        );

    auto first =
        cursor.takeByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 200);

    assert(cursor.logicalPosition == 1);
    assert(cursor.physicalPosition == 2);
    assert(cursor.absoluteOffset == 202);

    auto second =
        cursor.takeByte();

    assert(second.hasValue);
    assert(second.value.value == 0xE1);
    assert(second.value.sourceOffset == 202);

    assert(cursor.logicalPosition == 2);
    assert(cursor.physicalPosition == 3);
    assert(cursor.empty);
}


/// U24BE reads use the logical byte stream.
unittest
{
    const ubyte[] bytes =
        [
            0x12,
            0x34,
            0x56,

            0x55
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                300
            ),
            false
        );

    auto result =
        cursor.takeU24BE();

    assert(result.hasValue);
    assert(result.value == 0x12_34_56);

    assert(cursor.logicalPosition == 3);
    assert(cursor.physicalPosition == 3);
    assert(cursor.absoluteOffset == 303);
    assert(cursor.remainingPhysical == 1);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// U24BE reads work across physical unsynchronisation stuffing.
unittest
{
    /*
     * Logical bytes:
     *
     *   12 FF 34
     *
     * Physical bytes:
     *
     *   12 FF 00 34
     */
    const ubyte[] bytes =
        [
            0x12,
            0xFF,
            0x00,
            0x34,

            0x55
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                400
            ),
            true
        );

    auto result =
        cursor.takeU24BE();

    assert(result.hasValue);
    assert(result.value == 0x12_FF_34);

    assert(cursor.logicalPosition == 3);
    assert(cursor.physicalPosition == 4);
    assert(cursor.absoluteOffset == 404);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// Truncated U24BE reads fail atomically.
unittest
{
    /*
     * Two logical bytes are encoded in three physical bytes.
     */
    const ubyte[] bytes =
        [
            0x12,
            0xFF,
            0x00
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                500
            ),
            true
        );

    auto result =
        cursor.takeU24BE();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 503);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 500);
    assert(cursor.remainingPhysical == bytes.length);
}


/// Normal logical regions preserve the one-to-one physical span.
unittest
{
    const ubyte[] bytes =
        [
            0x11,
            0x22,
            0x33,

            0x55
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                600
            ),
            false
        );

    auto result =
        cursor.takeLogicalRegion(3);

    assert(result.hasValue);
    assert(result.value.sourceOffset == 600);
    assert(result.value.length == 3);

    assert(
        result.value.data ==
        [0x11, 0x22, 0x33]
    );

    assert(cursor.logicalPosition == 3);
    assert(cursor.physicalPosition == 3);
    assert(cursor.absoluteOffset == 603);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// Unsynchronised logical regions retain their larger physical span.
unittest
{
    /*
     * Three logical bytes:
     *
     *   11 FF E1
     *
     * occupy four physical bytes:
     *
     *   11 FF 00 E1
     */
    const ubyte[] bytes =
        [
            0x11,
            0xFF,
            0x00,
            0xE1,

            0x55
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                700
            ),
            true
        );

    auto result =
        cursor.takeLogicalRegion(3);

    assert(result.hasValue);
    assert(result.value.sourceOffset == 700);
    assert(result.value.length == 4);

    assert(
        result.value.data ==
        [
            0x11,
            0xFF,
            0x00,
            0xE1
        ]
    );

    assert(cursor.logicalPosition == 3);
    assert(cursor.physicalPosition == 4);
    assert(cursor.absoluteOffset == 704);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// Truncated logical regions fail atomically in unsynchronised mode.
unittest
{
    const ubyte[] bytes =
        [
            0x11,
            0xFF,
            0x00
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                800
            ),
            true
        );

    auto result =
        cursor.takeLogicalRegion(3);

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 803);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 800);
}


/// Zero-length logical regions succeed without consuming bytes.
unittest
{
    const ubyte[] bytes =
        [
            0x11
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                900
            ),
            true
        );

    auto result =
        cursor.takeLogicalRegion(0);

    assert(result.hasValue);
    assert(result.value.empty);
    assert(result.value.sourceOffset == 900);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 900);
    assert(cursor.remainingPhysical == 1);
}

/// U32BE reads four logical bytes in network byte order.
unittest
{
    const ubyte[] bytes =
        [
            0x12, 0x34, 0x56, 0x78,
            0xAA
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1000
            ),
            false
        );

    auto result =
        cursor.takeU32BE();

    assert(result.hasValue);
    assert(result.value == 0x12_34_56_78);
    assert(cursor.logicalPosition == 4);
    assert(cursor.physicalPosition == 4);
    assert(cursor.absoluteOffset == 1004);
    assert(cursor.remainingRaw.data == [0xAA]);
}


/// U32BE remains logical across whole-tag unsynchronisation stuffing.
unittest
{
    const ubyte[] bytes =
        [
            0x12,
            0xFF, 0x00,
            0xE1,
            0x34,
            0xAA
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1100
            ),
            true
        );

    auto result =
        cursor.takeU32BE();

    assert(result.hasValue);
    assert(result.value == 0x12_FF_E1_34);
    assert(cursor.logicalPosition == 4);
    assert(cursor.physicalPosition == 5);
    assert(cursor.absoluteOffset == 1105);
    assert(cursor.remainingRaw.data == [0xAA]);
}


/// Failed U32BE reads leave the logical cursor unchanged.
unittest
{
    const ubyte[] bytes =
        [
            0x12, 0x34, 0x56
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1200
            ),
            false
        );

    auto result =
        cursor.takeU32BE();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 1200);
}

/// U16BE reads two logical bytes in network byte order.
unittest
{
    const ubyte[] bytes =
        [
            0x12, 0x34,
            0xAA
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1300
            ),
            false
        );

    auto result =
        cursor.takeU16BE();

    assert(result.hasValue);
    assert(result.value == 0x12_34);
    assert(cursor.logicalPosition == 2);
    assert(cursor.physicalPosition == 2);
    assert(cursor.absoluteOffset == 1302);
    assert(cursor.remainingRaw.data == [0xAA]);
}


/// U16BE remains logical across whole-tag unsynchronisation stuffing.
unittest
{
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0xE1,
            0xAA
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1400
            ),
            true
        );

    auto result =
        cursor.takeU16BE();

    assert(result.hasValue);
    assert(result.value == 0xFF_E1);
    assert(cursor.logicalPosition == 2);
    assert(cursor.physicalPosition == 3);
    assert(cursor.absoluteOffset == 1403);
    assert(cursor.remainingRaw.data == [0xAA]);
}


/// Failed U16BE reads leave the logical cursor unchanged.
unittest
{
    const ubyte[] bytes =
        [
            0x12
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1500
            ),
            false
        );

    auto result =
        cursor.takeU16BE();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 1500);
}
