/++
ID3v2.4 tag-header parsing.

This module parses only the fixed 10-byte ID3v2.4 tag header.
Extended headers, frames, padding and footers are handled by later
structural parsing stages.

Parsing is atomic: a malformed or unsupported header leaves the input
cursor unchanged.
+/
module audiotag.id3v2.v24.header;

import audiotag.core.cursor : ByteCursor;
import audiotag.core.error : ParseError, ParseErrorCode;
import audiotag.core.numeric : readSynchsafe32;
import audiotag.core.result : ParseResult;


/++
Parsed ID3v2.4 tag header.

`tagSize` is the size stored in the ID3 header. It describes the bytes
following the header that belong to the tag, excluding an optional
footer.
+/
struct Id3v24Header
{
    /// Absolute source offset of the first `I` in the ID3 identifier.
    size_t sourceOffset;

    /// ID3v2.4 revision byte.
    ubyte revision;

    /// Raw ID3v2.4 header flags.
    ubyte flags;

    /// Decoded 28-bit synchsafe tag size.
    uint tagSize;

    /// Whether tag-level unsynchronisation is indicated.
    @property
    bool unsynchronisation() const
        @safe pure nothrow @nogc
    {
        return (flags & 0x80) != 0;
    }

    /// Whether an extended header follows the tag header.
    @property
    bool hasExtendedHeader() const
        @safe pure nothrow @nogc
    {
        return (flags & 0x40) != 0;
    }

    /// Whether the experimental indicator is set.
    @property
    bool experimentalIndicator() const
        @safe pure nothrow @nogc
    {
        return (flags & 0x20) != 0;
    }

    /// Whether a footer is present at the end of the tag.
    @property
    bool hasFooter() const
        @safe pure nothrow @nogc
    {
        return (flags & 0x10) != 0;
    }
}


/++
Parses one ID3v2.4 tag header.

The parser accepts ID3 major version 4. Revision values are retained
for provenance; revision `0xFF` is rejected because ID3 version and
revision bytes may not use that value.

Params:
    cursor = Cursor positioned at the beginning of an ID3v2 tag.

Returns:
    The parsed ID3v2.4 header, or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v24Header parseId3v24Header(ref ByteCursor cursor)
    @safe pure nothrow @nogc
{
    // Parse transactionally. Only commit the copied cursor state after
    // the complete header has been validated.
    auto probe = cursor;

    auto rawResult = probe.takeBytes(10);

    if (rawResult.hasError)
        return ParseResult!Id3v24Header.failure(rawResult.error);

    const raw = rawResult.value;
    const data = raw.data;

    immutable ubyte[3] identifier = ['I', 'D', '3'];

    foreach (index; 0 .. identifier.length)
    {
        if (data[index] != identifier[index])
        {
            return ParseResult!Id3v24Header.failure(
                ParseError(
                    ParseErrorCode.invalidSignature,
                    raw.sourceOffset + index
                )
            );
        }
    }

    const major = data[3];
    const revision = data[4];

    if (major != 4 || revision == 0xFF)
    {
        return ParseResult!Id3v24Header.failure(
            ParseError(
                ParseErrorCode.unsupportedVersion,
                raw.sourceOffset + (major != 4 ? 3 : 4)
            )
        );
    }

    const flags = data[5];

    if ((flags & 0x0F) != 0)
    {
        return ParseResult!Id3v24Header.failure(
            ParseError(
                ParseErrorCode.invalidFlags,
                raw.sourceOffset + 5
            )
        );
    }

    auto sizeCursor =
        ByteCursor(raw.subspan(6, 4));

    auto sizeResult =
        sizeCursor.readSynchsafe32();

    if (sizeResult.hasError)
        return ParseResult!Id3v24Header.failure(sizeResult.error);

    const header = Id3v24Header(
        raw.sourceOffset,
        revision,
        flags,
        sizeResult.value
    );

    cursor = probe;

    return ParseResult!Id3v24Header.success(header);
}


import audiotag.core.span : ByteSpan;


/// A minimal ID3v2.4.0 header parses and consumes exactly ten bytes.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x00,
         0x00, 0x00, 0x00, 0x00,
         0x55];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.parseId3v24Header();

    assert(result.hasValue);

    const header = result.value;

    assert(header.sourceOffset == 100);
    assert(header.revision == 0);
    assert(header.flags == 0);
    assert(header.tagSize == 0);

    assert(!header.unsynchronisation);
    assert(!header.hasExtendedHeader);
    assert(!header.experimentalIndicator);
    assert(!header.hasFooter);

    assert(cursor.position == 10);
    assert(cursor.absoluteOffset == 110);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


/// Header flags are preserved and exposed through semantic properties.
unittest
{
    // 00 02 02 74 decodes to 33140.
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0xF0,
         0x00, 0x02, 0x02, 0x74];

    auto cursor = ByteCursor(ByteSpan(bytes));
    auto result = cursor.parseId3v24Header();

    assert(result.hasValue);

    const header = result.value;

    assert(header.flags == 0xF0);
    assert(header.tagSize == 33140);
    assert(header.unsynchronisation);
    assert(header.hasExtendedHeader);
    assert(header.experimentalIndicator);
    assert(header.hasFooter);
}


/// Truncated ID3 headers fail atomically at every possible length.
unittest
{
    const ubyte[] complete =
        ['I', 'D', '3',
         0x04, 0x00,
         0x00,
         0x00, 0x00, 0x00, 0x00];

    foreach (length; 0 .. 10)
    {
        auto cursor =
            ByteCursor(ByteSpan(complete[0 .. length], 200));

        auto result =
            cursor.parseId3v24Header();

        assert(result.hasError);
        assert(result.error.code == ParseErrorCode.endOfSpan);
        assert(result.error.offset == 200);
        assert(result.error.requested == 10);
        assert(result.error.available == length);

        assert(cursor.position == 0);
        assert(cursor.absoluteOffset == 200);
    }
}


/// Invalid identifier bytes report their exact absolute source offset.
unittest
{
    foreach (invalidIndex; 0 .. 3)
    {
        ubyte[] bytes =
            ['I', 'D', '3',
             0x04, 0x00,
             0x00,
             0x00, 0x00, 0x00, 0x00];

        bytes[invalidIndex] = 0x00;

        auto cursor = ByteCursor(ByteSpan(bytes, 300));
        auto result = cursor.parseId3v24Header();

        assert(result.hasError);
        assert(result.error.code == ParseErrorCode.invalidSignature);
        assert(result.error.offset == 300 + invalidIndex);
        assert(cursor.position == 0);
    }
}


/// A different ID3 major version is not consumed by the v2.4 parser.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x03, 0x00,
         0x00,
         0x00, 0x00, 0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.parseId3v24Header();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.unsupportedVersion);
    assert(result.error.offset == 103);
    assert(cursor.position == 0);
}


/// Revision 0xFF is rejected without consuming the header.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0xFF,
         0x00,
         0x00, 0x00, 0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.parseId3v24Header();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.unsupportedVersion);
    assert(result.error.offset == 104);
    assert(cursor.position == 0);
}


/// Undefined low flag bits are rejected atomically.
unittest
{
    foreach (bit; 0 .. 4)
    {
        ubyte[] bytes =
            ['I', 'D', '3',
             0x04, 0x00,
             cast(ubyte)(1 << bit),
             0x00, 0x00, 0x00, 0x00];

        auto cursor = ByteCursor(ByteSpan(bytes, 400));
        auto result = cursor.parseId3v24Header();

        assert(result.hasError);
        assert(result.error.code == ParseErrorCode.invalidFlags);
        assert(result.error.offset == 405);
        assert(cursor.position == 0);
    }
}


/// Invalid synchsafe size bytes retain their exact absolute error offset.
unittest
{
    foreach (invalidIndex; 0 .. 4)
    {
        ubyte[] bytes =
            ['I', 'D', '3',
             0x04, 0x00,
             0x00,
             0x01, 0x02, 0x03, 0x04];

        bytes[6 + invalidIndex] |= 0x80;

        auto cursor = ByteCursor(ByteSpan(bytes, 500));
        auto result = cursor.parseId3v24Header();

        assert(result.hasError);
        assert(
            result.error.code ==
            ParseErrorCode.invalidSynchsafeInteger
        );
        assert(result.error.offset == 506 + invalidIndex);

        assert(cursor.position == 0);
        assert(cursor.absoluteOffset == 500);
    }
}


/// Header offsets remain absolute when parsing begins inside a parent span.
unittest
{
    const ubyte[] bytes =
        [0x99,
         'I', 'D', '3',
         0x04, 0x01,
         0x00,
         0x00, 0x00, 0x00, 0x01,
         0x55];

    auto cursor = ByteCursor(ByteSpan(bytes, 1000));
    cursor.popFront();

    auto result = cursor.parseId3v24Header();

    assert(result.hasValue);
    assert(result.value.sourceOffset == 1001);
    assert(result.value.revision == 1);
    assert(result.value.tagSize == 1);

    assert(cursor.position == 11);
    assert(cursor.absoluteOffset == 1011);
    assert(cursor.front == 0x55);
}
