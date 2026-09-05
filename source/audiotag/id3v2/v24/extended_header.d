/++
ID3v2.4 extended-header parsing.

The extended header is parsed as one bounded structure. Its encoded
size includes the four-byte synchsafe size field itself.

Parsing is atomic: malformed or truncated input leaves the caller's
cursor unchanged.
+/
module audiotag.id3v2.v24.extended_header;

import audiotag.core.cursor : ByteCursor;
import audiotag.core.error : ParseError, ParseErrorCode;
import audiotag.core.numeric : readSynchsafe32;
import audiotag.core.result : ParseResult;
import audiotag.core.span : ByteSpan;


/++
Parsed ID3v2.4 extended header.

`crc32` is meaningful only when `hasCrc` is true.
`restrictions` is meaningful only when `hasRestrictions` is true.

`raw` preserves the complete bounded extended-header representation.
+/
struct Id3v24ExtendedHeader
{
    /// Absolute source offset of the extended header.
    size_t sourceOffset;

    /// Total extended-header size, including its four size bytes.
    uint size;

    /// Raw extended-header flags.
    ubyte flags;

    /// Decoded CRC-32 value when present.
    uint crc32;

    /// Raw restrictions byte when present.
    ubyte restrictions;

    /// Complete raw extended-header bytes.
    ByteSpan raw;

    /// Whether this tag is an update of an earlier tag.
    @property
    bool isUpdate() const
        @safe pure nothrow @nogc
    {
        return (flags & 0x40) != 0;
    }

    /// Whether CRC-32 data is present.
    @property
    bool hasCrc() const
        @safe pure nothrow @nogc
    {
        return (flags & 0x20) != 0;
    }

    /// Whether tag restrictions are present.
    @property
    bool hasRestrictions() const
        @safe pure nothrow @nogc
    {
        return (flags & 0x10) != 0;
    }
}


/++
Parses one ID3v2.4 extended header.

Params:
    cursor = Cursor positioned at the first extended-header size byte.

Returns:
    The parsed extended header or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v24ExtendedHeader parseId3v24ExtendedHeader(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe = cursor;

    auto sizeResult = probe.readSynchsafe32();

    if (sizeResult.hasError)
        return ParseResult!Id3v24ExtendedHeader.failure(
            sizeResult.error
        );

    const size = sizeResult.value;

    if (size < 6)
    {
        return ParseResult!Id3v24ExtendedHeader.failure(
            ParseError(
                ParseErrorCode.invalidLength,
                cursor.absoluteOffset
            )
        );
    }

    auto rawResult = cursor.peekBytes(size);

    if (rawResult.hasError)
        return ParseResult!Id3v24ExtendedHeader.failure(
            rawResult.error
        );

    const raw = rawResult.value;
    auto inner = ByteCursor(raw);

    auto skippedSize = inner.skipBytes(4);
    assert(skippedSize.succeeded);

    auto flagByteCountResult = inner.takeBytes(1);
    assert(flagByteCountResult.hasValue);

    const flagByteCount =
        flagByteCountResult.value.data[0];

    if (flagByteCount != 1)
    {
        return ParseResult!Id3v24ExtendedHeader.failure(
            ParseError(
                ParseErrorCode.invalidLength,
                raw.sourceOffset + 4
            )
        );
    }

    auto flagsResult = inner.takeBytes(1);
    assert(flagsResult.hasValue);

    const flags = flagsResult.value.data[0];

    // ID3v2.4 defines %0bcd0000.
    if ((flags & 0x8F) != 0)
    {
        return ParseResult!Id3v24ExtendedHeader.failure(
            ParseError(
                ParseErrorCode.invalidFlags,
                raw.sourceOffset + 5
            )
        );
    }

    uint crc32 = 0;
    ubyte restrictions = 0;

    if ((flags & 0x40) != 0)
    {
        auto lengthResult = inner.takeBytes(1);

        if (lengthResult.hasError)
            return ParseResult!Id3v24ExtendedHeader.failure(
                lengthResult.error
            );

        if (lengthResult.value.data[0] != 0)
        {
            return ParseResult!Id3v24ExtendedHeader.failure(
                ParseError(
                    ParseErrorCode.invalidLength,
                    lengthResult.value.sourceOffset
                )
            );
        }
    }

    if ((flags & 0x20) != 0)
    {
        auto lengthResult = inner.takeBytes(1);

        if (lengthResult.hasError)
            return ParseResult!Id3v24ExtendedHeader.failure(
                lengthResult.error
            );

        if (lengthResult.value.data[0] != 5)
        {
            return ParseResult!Id3v24ExtendedHeader.failure(
                ParseError(
                    ParseErrorCode.invalidLength,
                    lengthResult.value.sourceOffset
                )
            );
        }

        auto crcResult = inner.takeBytes(5);

        if (crcResult.hasError)
            return ParseResult!Id3v24ExtendedHeader.failure(
                crcResult.error
            );

        const data = crcResult.value.data;

        foreach (index, value; data)
        {
            if ((value & 0x80) != 0)
            {
                return ParseResult!Id3v24ExtendedHeader.failure(
                    ParseError(
                        ParseErrorCode.invalidSynchsafeInteger,
                        crcResult.value.sourceOffset + index
                    )
                );
            }
        }

        // Five synchsafe bytes carry 35 effective bits, but the stored
        // CRC is only 32 bits. Therefore only the low four bits of the
        // first physical byte may be used.
        if ((data[0] & 0x70) != 0)
        {
            return ParseResult!Id3v24ExtendedHeader.failure(
                ParseError(
                    ParseErrorCode.integerOverflow,
                    crcResult.value.sourceOffset
                )
            );
        }

        crc32 =
            (cast(uint) data[0] << 28) |
            (cast(uint) data[1] << 21) |
            (cast(uint) data[2] << 14) |
            (cast(uint) data[3] << 7) |
            cast(uint) data[4];
    }

    if ((flags & 0x10) != 0)
    {
        auto lengthResult = inner.takeBytes(1);

        if (lengthResult.hasError)
            return ParseResult!Id3v24ExtendedHeader.failure(
                lengthResult.error
            );

        if (lengthResult.value.data[0] != 1)
        {
            return ParseResult!Id3v24ExtendedHeader.failure(
                ParseError(
                    ParseErrorCode.invalidLength,
                    lengthResult.value.sourceOffset
                )
            );
        }

        auto restrictionsResult = inner.takeBytes(1);

        if (restrictionsResult.hasError)
            return ParseResult!Id3v24ExtendedHeader.failure(
                restrictionsResult.error
            );

        restrictions =
            restrictionsResult.value.data[0];
    }

    if (!inner.empty)
    {
        return ParseResult!Id3v24ExtendedHeader.failure(
            ParseError(
                ParseErrorCode.inconsistentStructure,
                inner.absoluteOffset,
                0,
                inner.remaining
            )
        );
    }

    auto remainingStatus =
        probe.skipBytes(size - 4);

    assert(remainingStatus.succeeded);

    const result = Id3v24ExtendedHeader(
        raw.sourceOffset,
        size,
        flags,
        crc32,
        restrictions,
        raw
    );

    cursor = probe;

    return ParseResult!Id3v24ExtendedHeader.success(result);
}


/// The smallest valid extended header contains no optional flag data.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00, 0x06,
         0x01,
         0x00,
         0x99];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasValue);

    const header = result.value;

    assert(header.sourceOffset == 100);
    assert(header.size == 6);
    assert(header.flags == 0);
    assert(!header.isUpdate);
    assert(!header.hasCrc);
    assert(!header.hasRestrictions);
    assert(header.raw.length == 6);

    assert(cursor.absoluteOffset == 106);
    assert(cursor.front == 0x99);
}


/// Update, CRC and restrictions data are parsed in flag order.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00, 0x0F,
         0x01,
         0x70,

         0x00,

         0x05,
         0x00, 0x00, 0x00, 0x00, 0x01,

         0x01,
         0xA5];

    auto cursor = ByteCursor(ByteSpan(bytes, 200));
    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasValue);

    const header = result.value;

    assert(header.size == 15);
    assert(header.flags == 0x70);
    assert(header.isUpdate);
    assert(header.hasCrc);
    assert(header.hasRestrictions);
    assert(header.crc32 == 1);
    assert(header.restrictions == 0xA5);

    assert(cursor.position == 15);
    assert(cursor.empty);
}


/// An extended header can never be shorter than six bytes.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00, 0x05,
         0x01, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 300));
    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 300);
    assert(cursor.position == 0);
}


/// A declared extended header must fit completely in its parent span.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00, 0x06,
         0x01];

    auto cursor = ByteCursor(ByteSpan(bytes, 400));
    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 400);
    assert(result.error.requested == 6);
    assert(result.error.available == 5);
    assert(cursor.position == 0);
}


/// ID3v2.4 currently requires exactly one extended-header flag byte.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00, 0x06,
         0x02,
         0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 500));
    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 504);
    assert(cursor.position == 0);
}


/// Undefined extended-header flags are rejected atomically.
unittest
{
    foreach (flags; [0x80, 0x08, 0x04, 0x02, 0x01])
    {
        const ubyte[] bytes =
            [0x00, 0x00, 0x00, 0x06,
             0x01,
             cast(ubyte) flags];

        auto cursor = ByteCursor(ByteSpan(bytes, 600));
        auto result = cursor.parseId3v24ExtendedHeader();

        assert(result.hasError);
        assert(result.error.code == ParseErrorCode.invalidFlags);
        assert(result.error.offset == 605);
        assert(cursor.position == 0);
    }
}


/// Update flag data must have length zero.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00, 0x07,
         0x01,
         0x40,
         0x01];

    auto cursor = ByteCursor(ByteSpan(bytes, 700));
    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 706);
    assert(cursor.position == 0);
}


/// CRC data length must be exactly five bytes.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00, 0x07,
         0x01,
         0x20,
         0x04];

    auto cursor = ByteCursor(ByteSpan(bytes, 800));
    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 806);
    assert(cursor.position == 0);
}


/// Invalid synchsafe CRC bytes retain their absolute source offset.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00, 0x0C,
         0x01,
         0x20,
         0x05,
         0x00, 0x00, 0x80, 0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 900));
    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.invalidSynchsafeInteger
    );
    assert(result.error.offset == 909);
    assert(cursor.position == 0);
}


/// A 35-bit synchsafe value that does not fit CRC-32 is rejected.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00, 0x0C,
         0x01,
         0x20,
         0x05,
         0x10, 0x00, 0x00, 0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 1000));
    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.integerOverflow);
    assert(result.error.offset == 1007);
    assert(cursor.position == 0);
}


/// Restrictions data length must be exactly one byte.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00, 0x07,
         0x01,
         0x10,
         0x02];

    auto cursor = ByteCursor(ByteSpan(bytes, 1100));
    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 1106);
    assert(cursor.position == 0);
}


/// Bytes not described by set flags make the structure inconsistent.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00, 0x07,
         0x01,
         0x00,
         0x99];

    auto cursor = ByteCursor(ByteSpan(bytes, 1200));
    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );
    assert(result.error.offset == 1206);
    assert(result.error.available == 1);
    assert(cursor.position == 0);
}


/// Extended-header parsing preserves parent-relative absolute offsets.
unittest
{
    const ubyte[] bytes =
        [0x99,
         0x00, 0x00, 0x00, 0x06,
         0x01, 0x00,
         0x55];

    auto cursor = ByteCursor(ByteSpan(bytes, 2000));
    cursor.popFront();

    auto result = cursor.parseId3v24ExtendedHeader();

    assert(result.hasValue);
    assert(result.value.sourceOffset == 2001);
    assert(result.value.raw.sourceOffset == 2001);

    assert(cursor.absoluteOffset == 2007);
    assert(cursor.front == 0x55);
}
