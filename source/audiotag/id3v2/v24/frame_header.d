/++
ID3v2.4 frame-header parsing.

This module parses only the fixed 10-byte frame header:

- four-byte frame identifier;
- four-byte synchsafe frame size;
- two frame flag bytes.

Frame payload bounding, optional frame-format fields and padding are
handled by later structural parsing stages.

Parsing is atomic: malformed or truncated frame headers leave the
caller's cursor unchanged.
+/
module audiotag.id3v2.v24.frame_header;

import audiotag.core.cursor : ByteCursor;
import audiotag.core.error : ParseError, ParseErrorCode;
import audiotag.core.numeric : readSynchsafe32;
import audiotag.core.result : ParseResult;


/++
Parsed ID3v2.4 frame header.

`size` is the encoded frame-data size and excludes the ten-byte frame
header itself.
+/
struct Id3v24FrameHeader
{
    /// Absolute source offset of the first frame-ID byte.
    size_t sourceOffset;

    /// Four-character ID3v2.4 frame identifier.
    char[4] id;

    /// Encoded frame-data size, excluding this header.
    uint size;

    /// Raw frame status flags.
    ubyte statusFlags;

    /// Raw frame format flags.
    ubyte formatFlags;

    /// Frame should be discarded if the tag is altered.
    @property
    bool discardOnTagAlter() const
        @safe pure nothrow @nogc
    {
        return (statusFlags & 0x40) != 0;
    }

    /// Frame should be discarded if the audio file is altered.
    @property
    bool discardOnFileAlter() const
        @safe pure nothrow @nogc
    {
        return (statusFlags & 0x20) != 0;
    }

    /// Frame contents are marked read-only.
    @property
    bool readOnly() const
        @safe pure nothrow @nogc
    {
        return (statusFlags & 0x10) != 0;
    }

    /// A grouping-identity byte is present in the frame data.
    @property
    bool hasGroupingIdentity() const
        @safe pure nothrow @nogc
    {
        return (formatFlags & 0x40) != 0;
    }

    /// Frame data is compressed.
    @property
    bool compressed() const
        @safe pure nothrow @nogc
    {
        return (formatFlags & 0x08) != 0;
    }

    /// An encryption-method byte is present in the frame data.
    @property
    bool encrypted() const
        @safe pure nothrow @nogc
    {
        return (formatFlags & 0x04) != 0;
    }

    /// Frame-level unsynchronisation is applied.
    @property
    bool unsynchronised() const
        @safe pure nothrow @nogc
    {
        return (formatFlags & 0x02) != 0;
    }

    /// A four-byte data-length indicator is present.
    @property
    bool hasDataLengthIndicator() const
        @safe pure nothrow @nogc
    {
        return (formatFlags & 0x01) != 0;
    }
}


/++
Parses one ID3v2.4 frame header.

Frame identifiers may contain only uppercase ASCII letters `A`-`Z`
and digits `0`-`9`.

The frame size must be non-zero. ID3v2.4 requires every frame to
contain at least one byte of frame data.

Compression requires the data-length-indicator flag.

Params:
    cursor = Cursor positioned at the first byte of a frame header.

Returns:
    The parsed frame header or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v24FrameHeader parseId3v24FrameHeader(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe = cursor;

    auto rawResult = probe.takeBytes(10);

    if (rawResult.hasError)
        return ParseResult!Id3v24FrameHeader.failure(
            rawResult.error
        );

    const raw = rawResult.value;
    const data = raw.data;

    char[4] id;

    foreach (index; 0 .. 4)
    {
        const value = data[index];

        const valid =
            (value >= 'A' && value <= 'Z') ||
            (value >= '0' && value <= '9');

        if (!valid)
        {
            return ParseResult!Id3v24FrameHeader.failure(
                ParseError(
                    ParseErrorCode.invalidSignature,
                    raw.sourceOffset + index
                )
            );
        }

        id[index] = cast(char) value;
    }

    auto sizeCursor =
        ByteCursor(raw.subspan(4, 4));

    auto sizeResult =
        sizeCursor.readSynchsafe32();

    if (sizeResult.hasError)
        return ParseResult!Id3v24FrameHeader.failure(
            sizeResult.error
        );

    if (sizeResult.value == 0)
    {
        return ParseResult!Id3v24FrameHeader.failure(
            ParseError(
                ParseErrorCode.invalidLength,
                raw.sourceOffset + 4
            )
        );
    }

    const statusFlags = data[8];
    const formatFlags = data[9];

    // Status flags are %0abc0000.
    if ((statusFlags & 0x8F) != 0)
    {
        return ParseResult!Id3v24FrameHeader.failure(
            ParseError(
                ParseErrorCode.invalidFlags,
                raw.sourceOffset + 8
            )
        );
    }

    // Format flags are %0h00kmnp.
    if ((formatFlags & 0xB0) != 0)
    {
        return ParseResult!Id3v24FrameHeader.failure(
            ParseError(
                ParseErrorCode.invalidFlags,
                raw.sourceOffset + 9
            )
        );
    }

    // Compression requires a Data Length Indicator in ID3v2.4.
    if (
        (formatFlags & 0x08) != 0 &&
        (formatFlags & 0x01) == 0
    )
    {
        return ParseResult!Id3v24FrameHeader.failure(
            ParseError(
                ParseErrorCode.inconsistentStructure,
                raw.sourceOffset + 9
            )
        );
    }

    const result = Id3v24FrameHeader(
        raw.sourceOffset,
        id,
        sizeResult.value,
        statusFlags,
        formatFlags
    );

    cursor = probe;

    return ParseResult!Id3v24FrameHeader.success(result);
}


import audiotag.core.span : ByteSpan;


/// A normal ID3v2.4 frame header parses and consumes exactly ten bytes.
unittest
{
    const ubyte[] bytes =
        ['T', 'I', 'T', '2',
         0x00, 0x00, 0x00, 0x03,
         0x00, 0x00,
         0x55];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.parseId3v24FrameHeader();

    assert(result.hasValue);

    const header = result.value;

    assert(header.sourceOffset == 100);
    assert(header.id[] == "TIT2");
    assert(header.size == 3);
    assert(header.statusFlags == 0);
    assert(header.formatFlags == 0);

    assert(!header.discardOnTagAlter);
    assert(!header.discardOnFileAlter);
    assert(!header.readOnly);
    assert(!header.hasGroupingIdentity);
    assert(!header.compressed);
    assert(!header.encrypted);
    assert(!header.unsynchronised);
    assert(!header.hasDataLengthIndicator);

    assert(cursor.position == 10);
    assert(cursor.absoluteOffset == 110);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


/// All defined status and format flags are exposed semantically.
unittest
{
    const ubyte[] bytes =
        ['A', 'B', 'C', '1',
         0x00, 0x00, 0x00, 0x01,
         0x70,
         0x4F];

    auto cursor = ByteCursor(ByteSpan(bytes));
    auto result = cursor.parseId3v24FrameHeader();

    assert(result.hasValue);

    const header = result.value;

    assert(header.id[] == "ABC1");

    assert(header.discardOnTagAlter);
    assert(header.discardOnFileAlter);
    assert(header.readOnly);

    assert(header.hasGroupingIdentity);
    assert(header.compressed);
    assert(header.encrypted);
    assert(header.unsynchronised);
    assert(header.hasDataLengthIndicator);
}


/// Frame headers truncated at any byte fail atomically.
unittest
{
    const ubyte[] complete =
        ['T', 'I', 'T', '2',
         0x00, 0x00, 0x00, 0x01,
         0x00, 0x00];

    foreach (length; 0 .. 10)
    {
        auto cursor =
            ByteCursor(ByteSpan(complete[0 .. length], 200));

        auto result =
            cursor.parseId3v24FrameHeader();

        assert(result.hasError);
        assert(result.error.code == ParseErrorCode.endOfSpan);
        assert(result.error.offset == 200);
        assert(result.error.requested == 10);
        assert(result.error.available == length);

        assert(cursor.position == 0);
        assert(cursor.absoluteOffset == 200);
    }
}


/// Every frame-ID position rejects bytes outside A-Z and 0-9.
unittest
{
    foreach (invalidIndex; 0 .. 4)
    {
        foreach (invalidValue; [0x00, 0x20, 0x61, 0x5F])
        {
            ubyte[] bytes =
                ['T', 'I', 'T', '2',
                 0x00, 0x00, 0x00, 0x01,
                 0x00, 0x00];

            bytes[invalidIndex] =
                cast(ubyte) invalidValue;

            auto cursor =
                ByteCursor(ByteSpan(bytes, 300));

            auto result =
                cursor.parseId3v24FrameHeader();

            assert(result.hasError);
            assert(
                result.error.code ==
                ParseErrorCode.invalidSignature
            );
            assert(
                result.error.offset ==
                300 + invalidIndex
            );

            assert(cursor.position == 0);
        }
    }
}


/// Digits are legal in frame identifiers.
unittest
{
    const ubyte[] bytes =
        ['R', 'V', 'A', '2',
         0x00, 0x00, 0x00, 0x01,
         0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes));
    auto result = cursor.parseId3v24FrameHeader();

    assert(result.hasValue);
    assert(result.value.id[] == "RVA2");
}


/// A frame size of zero is structurally invalid.
unittest
{
    const ubyte[] bytes =
        ['T', 'I', 'T', '2',
         0x00, 0x00, 0x00, 0x00,
         0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 400));
    auto result = cursor.parseId3v24FrameHeader();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 404);

    assert(cursor.position == 0);
}


/// Invalid synchsafe frame-size bytes retain exact source offsets.
unittest
{
    foreach (invalidIndex; 0 .. 4)
    {
        ubyte[] bytes =
            ['T', 'I', 'T', '2',
             0x01, 0x02, 0x03, 0x04,
             0x00, 0x00];

        bytes[4 + invalidIndex] |= 0x80;

        auto cursor =
            ByteCursor(ByteSpan(bytes, 500));

        auto result =
            cursor.parseId3v24FrameHeader();

        assert(result.hasError);
        assert(
            result.error.code ==
            ParseErrorCode.invalidSynchsafeInteger
        );
        assert(
            result.error.offset ==
            504 + invalidIndex
        );

        assert(cursor.position == 0);
    }
}


/// Undefined status flag bits are rejected.
unittest
{
    foreach (flags; [0x80, 0x08, 0x04, 0x02, 0x01])
    {
        const ubyte[] bytes =
            ['T', 'I', 'T', '2',
             0x00, 0x00, 0x00, 0x01,
             cast(ubyte) flags,
             0x00];

        auto cursor =
            ByteCursor(ByteSpan(bytes, 600));

        auto result =
            cursor.parseId3v24FrameHeader();

        assert(result.hasError);
        assert(result.error.code == ParseErrorCode.invalidFlags);
        assert(result.error.offset == 608);
        assert(cursor.position == 0);
    }
}


/// Undefined format flag bits are rejected.
unittest
{
    foreach (flags; [0x80, 0x20, 0x10])
    {
        const ubyte[] bytes =
            ['T', 'I', 'T', '2',
             0x00, 0x00, 0x00, 0x01,
             0x00,
             cast(ubyte) flags];

        auto cursor =
            ByteCursor(ByteSpan(bytes, 700));

        auto result =
            cursor.parseId3v24FrameHeader();

        assert(result.hasError);
        assert(result.error.code == ParseErrorCode.invalidFlags);
        assert(result.error.offset == 709);
        assert(cursor.position == 0);
    }
}


/// Compression without a Data Length Indicator is inconsistent.
unittest
{
    const ubyte[] bytes =
        ['T', 'I', 'T', '2',
         0x00, 0x00, 0x00, 0x01,
         0x00,
         0x08];

    auto cursor = ByteCursor(ByteSpan(bytes, 800));
    auto result = cursor.parseId3v24FrameHeader();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );
    assert(result.error.offset == 809);

    assert(cursor.position == 0);
}


/// Compression with a Data Length Indicator is structurally valid.
unittest
{
    const ubyte[] bytes =
        ['T', 'I', 'T', '2',
         0x00, 0x00, 0x00, 0x05,
         0x00,
         0x09];

    auto cursor = ByteCursor(ByteSpan(bytes));
    auto result = cursor.parseId3v24FrameHeader();

    assert(result.hasValue);
    assert(result.value.compressed);
    assert(result.value.hasDataLengthIndicator);
}


/// Frame-header offsets remain absolute inside a parent region.
unittest
{
    const ubyte[] bytes =
        [0x99,
         'T', 'I', 'T', '2',
         0x00, 0x00, 0x00, 0x01,
         0x00, 0x00,
         0x55];

    auto cursor = ByteCursor(ByteSpan(bytes, 1000));
    cursor.popFront();

    auto result = cursor.parseId3v24FrameHeader();

    assert(result.hasValue);
    assert(result.value.sourceOffset == 1001);
    assert(result.value.id[] == "TIT2");

    assert(cursor.absoluteOffset == 1011);
    assert(cursor.front == 0x55);
}
