/++
Logical traversal over bounded ID3v2.3 tag-body data.

ID3v2.3 unsynchronisation is a tag-level transformation. This cursor
therefore preserves the already bounded physical source `ByteSpan`
while optionally exposing logical bytes after removal of inserted
unsynchronisation zero bytes.

No decoded buffer is materialised. Physical source offsets remain
available for diagnostics and provenance.
+/
module audiotag.id3v2.v23.data_cursor;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.unsync :
    Id3v23DecodedByte,
    takeId3v23UnsynchronisedByte;


/++
Cursor over one already bounded physical ID3v2.3 tag-body region.

When `unsynchronised` is true, logical reads remove ID3v2.3 stuffing
bytes while the underlying physical cursor continues to track the
exact source representation.
+/
struct Id3v23DataCursor
{
private:
    ByteSpan _span;
    ByteCursor _cursor;
    size_t _logicalPosition;
    bool _unsynchronised;

public:
    /++
    Constructs a logical ID3v2.3 data cursor.

    Params:
        span = Hard physical boundary for all reads.
        unsynchronised = Whether ID3v2.3 tag-level unsynchronisation
            must be reversed during logical reads.
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


    /// Whether logical reads reverse ID3v2.3 unsynchronisation.
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

    With unsynchronisation an encoded physical `$FF $00` sequence
    produces one logical `$FF` while consuming both physical bytes.

    Returns:
        The logical byte together with the physical source offset of
        the byte that produced it.

    Error semantics:
        Failure leaves this cursor unchanged.
    +/
    ParseResult!Id3v23DecodedByte
    takeByte()
        @safe pure nothrow @nogc
    {
        if (_unsynchronised)
        {
            auto result =
                _cursor
                    .takeId3v23UnsynchronisedByte();

            if (result.hasError)
            {
                return
                    ParseResult!Id3v23DecodedByte
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
                ParseResult!Id3v23DecodedByte
                    .failure(
                        result.error
                    );
        }

        ++_logicalPosition;

        return
            ParseResult!Id3v23DecodedByte
                .success(
                    Id3v23DecodedByte(
                        result.value.data[0],
                        result.value.sourceOffset
                    )
                );
    }


    /++
    Reads one unsigned 32-bit big-endian integer from the logical byte
    stream.

    Four logical bytes are required. This is the integer representation
    used by ID3v2.3 frame sizes and several other version-specific
    structures.

    Unlike an ID3 tag-size field, this value is not synchsafe.

    Returns:
        The decoded unsigned 32-bit value or a structured parse error.

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
    Consumes exactly `count` logical bytes and returns their complete
    physical source region.

    In normal mode the physical and logical lengths are identical.

    With unsynchronisation the returned physical `ByteSpan` may be
    longer than `count` because inserted `$00` stuffing bytes remain
    part of the preserved source representation.

    This operation is intended for structures whose declared length is
    expressed in logical bytes while exact physical provenance must be
    retained.

    Params:
        count = Number of logical bytes to consume.

    Returns:
        The physical source span containing exactly the bytes consumed
        to produce `count` logical bytes.

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

        /*
         * Without unsynchronisation there is a one-to-one mapping.
         * Preserve the core cursor's efficient exact bounded read.
         */
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

        /*
         * In unsynchronised mode physical length cannot be known
         * without traversing the logical stream.
         */
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
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                100
            ),
            false
        );

    auto result =
        cursor.takeByte();

    assert(result.hasValue);

    assert(
        result.value.value ==
        0x11
    );

    assert(
        result.value.sourceOffset ==
        100
    );

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
        Id3v23DataCursor(
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


/// Encoded $FF $00 $00 produces logical $FF $00.
unittest
{
    const ubyte[] bytes =
        [
            0xFF,
            0x00,
            0x00
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                300
            ),
            true
        );

    auto first =
        cursor.takeByte();

    auto second =
        cursor.takeByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 300);

    assert(second.hasValue);
    assert(second.value.value == 0x00);
    assert(second.value.sourceOffset == 302);

    assert(cursor.logicalPosition == 2);
    assert(cursor.physicalPosition == 3);
    assert(cursor.empty);
}


/// Big-endian integer reads use the logical byte stream.
unittest
{
    const ubyte[] bytes =
        [
            0x12,
            0x34,
            0x56,
            0x78,

            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                400
            ),
            false
        );

    auto result =
        cursor.takeU32BE();

    assert(result.hasValue);

    assert(
        result.value ==
        0x1234_5678
    );

    assert(cursor.logicalPosition == 4);
    assert(cursor.physicalPosition == 4);
    assert(cursor.absoluteOffset == 404);
    assert(cursor.remainingPhysical == 1);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// Big-endian reads work across physical unsynchronisation stuffing.
unittest
{
    /*
     * Logical bytes:
     *
     *   12 FF 34 56
     *
     * Physical bytes:
     *
     *   12 FF 00 34 56
     */
    const ubyte[] bytes =
        [
            0x12,
            0xFF,
            0x00,
            0x34,
            0x56,

            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                500
            ),
            true
        );

    auto result =
        cursor.takeU32BE();

    assert(result.hasValue);

    assert(
        result.value ==
        0x12FF_3456
    );

    assert(cursor.logicalPosition == 4);
    assert(cursor.physicalPosition == 5);
    assert(cursor.absoluteOffset == 505);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// Truncated big-endian reads fail atomically.
unittest
{
    /*
     * Three logical bytes are encoded in four physical bytes.
     */
    const ubyte[] bytes =
        [
            0x12,
            0xFF,
            0x00,
            0x34
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                600
            ),
            true
        );

    auto result =
        cursor.takeU32BE();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 604);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 600);
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
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                700
            ),
            false
        );

    auto result =
        cursor.takeLogicalRegion(3);

    assert(result.hasValue);

    assert(result.value.sourceOffset == 700);
    assert(result.value.length == 3);

    assert(
        result.value.data ==
        [0x11, 0x22, 0x33]
    );

    assert(cursor.logicalPosition == 3);
    assert(cursor.physicalPosition == 3);
    assert(cursor.absoluteOffset == 703);

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
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                800
            ),
            true
        );

    auto result =
        cursor.takeLogicalRegion(3);

    assert(result.hasValue);

    assert(result.value.sourceOffset == 800);
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
    assert(cursor.absoluteOffset == 804);

    assert(cursor.remainingPhysical == 1);
    assert(cursor.remainingRaw.data == [0x55]);
}


/// Failed logical-region reads leave both positions unchanged.
unittest
{
    /*
     * Only two logical bytes:
     *
     *   FF 42
     */
    const ubyte[] bytes =
        [
            0xFF,
            0x00,
            0x42
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                900
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

    assert(result.error.offset == 903);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 900);
    assert(cursor.remainingPhysical == bytes.length);
}


/// Zero-length logical regions succeed without advancing.
unittest
{
    const ubyte[] bytes =
        [
            0xFF,
            0x00,
            0x42
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1000
            ),
            true
        );

    auto result =
        cursor.takeLogicalRegion(0);

    assert(result.hasValue);
    assert(result.value.empty);
    assert(result.value.sourceOffset == 1000);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 1000);
}


/// Physical offsets remain absolute after using a bounded subspan.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            0xFF,
            0x00,
            0x42,

            0x55
        ];

    const span =
        ByteSpan(
            bytes,
            2000
        )
            .subspan(
                1,
                3
            );

    auto cursor =
        Id3v23DataCursor(
            span,
            true
        );

    auto first =
        cursor.takeByte();

    auto second =
        cursor.takeByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 2001);

    assert(second.hasValue);
    assert(second.value.value == 0x42);
    assert(second.value.sourceOffset == 2003);

    assert(cursor.logicalPosition == 2);
    assert(cursor.physicalPosition == 3);
    assert(cursor.absoluteOffset == 2004);
    assert(cursor.empty);
}
