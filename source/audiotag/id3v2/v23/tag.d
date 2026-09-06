/++
Bounded ID3v2.3 tag-envelope parsing.

This module parses the complete outer structure of an ID3v2.3 tag:

- fixed 10-byte tag header;
- exactly the physical body length declared by that header.

The tag body remains an opaque bounded `ByteSpan`. Extended headers,
frames, padding and tag-level unsynchronisation are handled by later
structural stages.

In ID3v2.3 the tag-size field describes the stored tag body after
unsynchronisation. Therefore this outer parser deliberately bounds
physical bytes without reversing unsynchronisation.

Parsing is atomic: malformed or truncated outer structures leave the
caller's cursor unchanged.
+/
module audiotag.id3v2.v23.tag;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.header :
    Id3v23Header,
    parseId3v23Header;


/++
The bounded outer structure of one ID3v2.3 tag.

`body` contains exactly `header.tagSize` physical source bytes.

When tag-level unsynchronisation is indicated, those physical bytes may
represent fewer logical bytes. That transformation is intentionally
deferred until the bounded body is parsed.
+/
struct Id3v23TagEnvelope
{
    /// Parsed ID3v2.3 tag header.
    Id3v23Header header;

    /// Complete bounded physical tag body.
    ByteSpan body;


    /// Absolute offset immediately following the complete ID3v2.3 tag.
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return
            body.sourceOffset +
            body.length;
    }
}


/++
Parses and bounds one complete ID3v2.3 tag envelope.

The header is parsed first. Exactly `header.tagSize` physical bytes are
then bounded as the tag body.

The unsynchronisation flag does not change this operation. The v2.3
tag-size field already describes the stored representation after
unsynchronisation.

Params:
    cursor = Cursor positioned at the beginning of an ID3v2.3 tag.

Returns:
    A bounded tag envelope or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v23TagEnvelope
parseId3v23TagEnvelope(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    auto headerResult =
        probe.parseId3v23Header();

    if (headerResult.hasError)
    {
        return
            ParseResult!Id3v23TagEnvelope
                .failure(
                    headerResult.error
                );
    }

    const header =
        headerResult.value;

    auto bodyResult =
        probe.takeBytes(
            header.tagSize
        );

    if (bodyResult.hasError)
    {
        return
            ParseResult!Id3v23TagEnvelope
                .failure(
                    bodyResult.error
                );
    }

    const envelope =
        Id3v23TagEnvelope(
            header,
            bodyResult.value
        );

    cursor =
        probe;

    return
        ParseResult!Id3v23TagEnvelope
            .success(envelope);
}


version (unittest)
{
    import audiotag.core.error :
        ParseErrorCode;
}


/// A normal tag exposes exactly its declared physical body.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            /*
             * tagSize = 3.
             */
            0x00, 0x00, 0x00, 0x03,

            0x11, 0x22, 0x33,

            0x99
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto result =
        cursor.parseId3v23TagEnvelope();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.header.sourceOffset == 100);
    assert(tag.header.tagSize == 3);

    assert(tag.body.sourceOffset == 110);
    assert(tag.body.length == 3);

    assert(
        tag.body.data ==
        [0x11, 0x22, 0x33]
    );

    assert(tag.endOffset == 113);

    assert(cursor.position == 13);
    assert(cursor.absoluteOffset == 113);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x99);
}


/// A zero-length body is valid at the outer-envelope layer.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x00,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                200
            )
        );

    auto result =
        cursor.parseId3v23TagEnvelope();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.header.tagSize == 0);

    assert(tag.body.empty);
    assert(tag.body.sourceOffset == 210);
    assert(tag.endOffset == 210);

    assert(cursor.absoluteOffset == 210);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


/// The body may end exactly at the end of its bounded parent region.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x02,

            0xAA, 0xBB
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto result =
        cursor.parseId3v23TagEnvelope();

    assert(result.hasValue);

    assert(result.value.body.length == 2);
    assert(result.value.endOffset == 312);

    assert(cursor.absoluteOffset == 312);
    assert(cursor.empty);
}


/// A truncated declared body leaves the original cursor unchanged.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            /*
             * Five physical body bytes declared.
             */
            0x00, 0x00, 0x00, 0x05,

            /*
             * Only two available.
             */
            0x11, 0x22
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto result =
        cursor.parseId3v23TagEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    /*
     * The header was parsed only on the probe cursor.
     */
    assert(result.error.offset == 410);
    assert(result.error.requested == 5);
    assert(result.error.available == 2);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 400);
    assert(cursor.remaining == bytes.length);
}


/// Header failures propagate without consuming the caller's cursor.
unittest
{
    const ubyte[] bytes =
        [
            'X', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto result =
        cursor.parseId3v23TagEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 500);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 500);
}


/// Unsynchronisation does not change outer physical body bounding.
unittest
{
    /*
     * The physical body contains:
     *
     *   FF 00 E1
     *
     * which represents two logical bytes after v2.3 unsynchronisation
     * reversal. The tag header nevertheless declares and bounds all
     * three stored physical bytes.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            /*
             * Unsynchronisation flag.
             */
            0x80,

            /*
             * Physical stored body size = 3.
             */
            0x00, 0x00, 0x00, 0x03,

            0xFF, 0x00, 0xE1,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto result =
        cursor.parseId3v23TagEnvelope();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.header.unsynchronisation);
    assert(tag.header.tagSize == 3);

    assert(tag.body.sourceOffset == 610);
    assert(tag.body.length == 3);

    assert(
        tag.body.data ==
        [0xFF, 0x00, 0xE1]
    );

    assert(tag.endOffset == 613);

    assert(cursor.absoluteOffset == 613);
    assert(cursor.front == 0x55);
}


/// The maximum synchsafe tag size remains bounded by the parent span.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            /*
             * Maximum 28-bit synchsafe value:
             * 0x0FFF_FFFF.
             */
            0x7F, 0x7F, 0x7F, 0x7F,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto result =
        cursor.parseId3v23TagEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 710);

    assert(
        result.error.requested ==
        0x0FFF_FFFF
    );

    assert(result.error.available == 1);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 700);
}


/// Tag-envelope offsets remain absolute after earlier parent consumption.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x01,

            0xAA,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1000
            )
        );

    cursor.popFront();

    auto result =
        cursor.parseId3v23TagEnvelope();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.header.sourceOffset == 1001);
    assert(tag.body.sourceOffset == 1011);
    assert(tag.body.length == 1);
    assert(tag.endOffset == 1012);

    assert(cursor.position == 12);
    assert(cursor.absoluteOffset == 1012);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}
