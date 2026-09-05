/++
Logical traversal over bounded ID3v2.4 frame data.

ID3v2.4 frame data may be physically unsynchronised. This cursor
preserves the original bounded raw `ByteSpan` while exposing logical
bytes after unsynchronisation decoding.

No decoded buffer is materialised and physical source offsets remain
available for diagnostics and provenance.
+/
module audiotag.id3v2.v24.data_cursor;

import audiotag.core.cursor : ByteCursor;
import audiotag.core.error : ParseError, ParseErrorCode;
import audiotag.core.result : ParseResult;
import audiotag.core.span : ByteSpan;
import audiotag.id3v2.v24.unsync :
    Id3v24DecodedByte,
    takeId3v24UnsynchronisedByte;


/++
Cursor over one already bounded ID3v2.4 data region.

Logical reads optionally reverse ID3v2.4 unsynchronisation while the
physical cursor continues to track the exact encoded source bytes.
+/
struct Id3v24DataCursor
{
private:
    ByteSpan _span;
    ByteCursor _cursor;
    bool _unsynchronised;

public:
    /++
    Constructs a logical data cursor.

    Params:
        span = Hard physical boundary for all reads.
        unsynchronised = Whether ID3v2.4 unsynchronisation must be
            reversed during logical reads.
    +/
    this(ByteSpan span, bool unsynchronised)
        @safe pure nothrow @nogc
    {
        _span = span;
        _cursor = ByteCursor(span);
        _unsynchronised = unsynchronised;
    }

    /// Physical byte position relative to the beginning of the span.
    @property
    size_t physicalPosition() const
        @safe pure nothrow @nogc
    {
        return _cursor.position;
    }

    /// Absolute physical source offset of the next unread byte.
    @property
    size_t absoluteOffset() const
        @safe pure nothrow @nogc
    {
        return _cursor.absoluteOffset;
    }

    /// Number of unread physical source bytes.
    @property
    size_t remainingPhysical() const
        @safe pure nothrow @nogc
    {
        return _cursor.remaining;
    }

    /// Whether no physical source bytes remain.
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return _cursor.empty;
    }

    /// Whether logical reads reverse unsynchronisation.
    @property
    bool unsynchronised() const
        @safe pure nothrow @nogc
    {
        return _unsynchronised;
    }

    /// Raw physical bytes that have not yet been consumed.
    @property
    ByteSpan remainingRaw() const
        @safe pure nothrow @nogc
    {
        return _span.subspan(
            _cursor.position,
            _cursor.remaining
        );
    }

    /++
    Consumes one logical byte.

    In normal mode exactly one physical byte is consumed.

    In unsynchronised mode a physical `$FF $00` sequence produces one
    logical `$FF` and consumes both physical bytes.

    Returns:
        The logical byte together with the physical source offset of
        the byte that produced it.

    Error semantics:
        Failure is atomic.
    +/
    ParseResult!Id3v24DecodedByte takeByte()
        @safe pure nothrow @nogc
    {
        if (_unsynchronised)
        {
            return _cursor
                .takeId3v24UnsynchronisedByte();
        }

        auto result = _cursor.takeBytes(1);

        if (result.hasError)
        {
            return ParseResult!Id3v24DecodedByte.failure(
                result.error
            );
        }

        return ParseResult!Id3v24DecodedByte.success(
            Id3v24DecodedByte(
                result.value.data[0],
                result.value.sourceOffset
            )
        );
    }

    /++
    Reads one 32-bit synchsafe integer from the logical byte stream.

    Four logical bytes are required. Every byte must have its most
    significant bit cleared.

    Returns:
        The decoded 28-bit value or a structured parse error.

    Error semantics:
        Failure leaves this cursor unchanged.
    +/
    ParseResult!uint takeSynchsafe32()
        @safe pure nothrow @nogc
    {
        auto probe = this;

        uint value = 0;

        foreach (index; 0 .. 4)
        {
            auto byteResult = probe.takeByte();

            if (byteResult.hasError)
            {
                return ParseResult!uint.failure(
                    byteResult.error
                );
            }

            const decoded = byteResult.value;

            if ((decoded.value & 0x80) != 0)
            {
                return ParseResult!uint.failure(
                    ParseError(
                        ParseErrorCode.invalidSynchsafeInteger,
                        decoded.sourceOffset
                    )
                );
            }

            value =
                (value << 7) |
                cast(uint) decoded.value;
        }

        this = probe;

        return ParseResult!uint.success(value);
    }
}


/// Normal mode consumes one physical byte per logical byte.
unittest
{
    const ubyte[] bytes =
        [0x11, 0x22];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 100),
            false
        );

    auto result = cursor.takeByte();

    assert(result.hasValue);
    assert(result.value.value == 0x11);
    assert(result.value.sourceOffset == 100);

    assert(cursor.physicalPosition == 1);
    assert(cursor.absoluteOffset == 101);
    assert(cursor.remainingPhysical == 1);
    assert(cursor.remainingRaw.data == [0x22]);
}


/// Unsynchronised mode removes a physical stuffing zero.
unittest
{
    const ubyte[] bytes =
        [0xFF, 0x00, 0xE1];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 200),
            true
        );

    auto first = cursor.takeByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 200);

    assert(cursor.physicalPosition == 2);
    assert(cursor.absoluteOffset == 202);

    auto second = cursor.takeByte();

    assert(second.hasValue);
    assert(second.value.value == 0xE1);
    assert(second.value.sourceOffset == 202);
    assert(cursor.empty);
}


/// The unread raw span always reflects physical source bytes.
unittest
{
    const ubyte[] bytes =
        [0xFF, 0x00, 0x11, 0x22];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 300),
            true
        );

    auto first = cursor.takeByte();
    assert(first.hasValue);

    assert(cursor.remainingRaw.sourceOffset == 302);
    assert(cursor.remainingRaw.length == 2);
    assert(cursor.remainingRaw.data == [0x11, 0x22]);
}


/// Logical synchsafe integers decode identically in normal mode.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x02, 0x02, 0x74,
         0x55];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 400),
            false
        );

    auto result = cursor.takeSynchsafe32();

    assert(result.hasValue);
    assert(result.value == 33140);

    assert(cursor.physicalPosition == 4);
    assert(cursor.absoluteOffset == 404);
    assert(cursor.remainingRaw.data == [0x55]);
}


/// Synchsafe reads operate after earlier unsynchronised bytes.
unittest
{
    const ubyte[] bytes =
        [0xFF, 0x00,
         0x00, 0x00, 0x00, 0x01];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 500),
            true
        );

    auto prefix = cursor.takeByte();

    assert(prefix.hasValue);
    assert(prefix.value.value == 0xFF);
    assert(prefix.value.sourceOffset == 500);

    assert(cursor.physicalPosition == 2);

    auto value = cursor.takeSynchsafe32();

    assert(value.hasValue);
    assert(value.value == 1);
    assert(cursor.empty);
}


/// Invalid logical synchsafe bytes report physical source offsets.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x01, 0x82, 0x03,
         0x55];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 600),
            false
        );

    auto result = cursor.takeSynchsafe32();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.invalidSynchsafeInteger
    );
    assert(result.error.offset == 602);

    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 600);
    assert(cursor.remainingPhysical == bytes.length);
}


/// Truncated logical synchsafe reads fail atomically.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x01, 0x02];

    auto cursor =
        Id3v24DataCursor(
            ByteSpan(bytes, 700),
            false
        );

    auto result = cursor.takeSynchsafe32();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 703);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);

    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 700);
}


/// Unsynchronised source offsets remain physical after stuffing removal.
unittest
{
    const ubyte[] bytes =
        [0x99,
         0xFF, 0x00,
         0x42];

    const span =
        ByteSpan(bytes, 1000)
            .subspan(1, 3);

    auto cursor =
        Id3v24DataCursor(span, true);

    auto first = cursor.takeByte();
    auto second = cursor.takeByte();

    assert(first.hasValue);
    assert(first.value.sourceOffset == 1001);

    assert(second.hasValue);
    assert(second.value.value == 0x42);
    assert(second.value.sourceOffset == 1003);

    assert(cursor.empty);
}
