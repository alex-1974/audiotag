/++
Bounded ID3v2.2 tag-envelope parsing.

This module parses the complete outer structure of an ID3v2.2 tag:

- fixed 10-byte tag header;
- exactly the physical body length declared by that header.

The tag body remains an opaque bounded `ByteSpan`. Frame parsing, padding,
whole-tag unsynchronisation and the special opaque handling of whole-tag
compression are handled by later structural stages.

In ID3v2.2 the tag-size field describes the stored tag body after
unsynchronisation, including padding and excluding the 10-byte header.
Therefore this outer parser deliberately bounds physical bytes without
reversing unsynchronisation.

Parsing is atomic: malformed or truncated outer structures leave the caller's
cursor unchanged.
+/
module audiotag.id3v2.v22.tag;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v22.header :
    Id3v22Header,
    parseId3v22Header;


/++
The bounded outer structure of one ID3v2.2 tag.

`body` contains exactly `header.tagSize` physical source bytes.

When whole-tag unsynchronisation is indicated, those physical bytes may
represent fewer logical bytes. That transformation is intentionally deferred
until the bounded body is parsed.

When whole-tag compression is indicated, the same physical body remains
bounded here without attempting to interpret its representation.
+/
struct Id3v22TagEnvelope
{
    /// Parsed ID3v2.2 tag header.
    Id3v22Header header;

    /// Complete bounded physical tag body.
    ByteSpan body;


    /// Absolute offset immediately following the complete ID3v2.2 tag.
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
Parses and bounds one complete ID3v2.2 tag envelope.

The header is parsed first. Exactly `header.tagSize` physical bytes are then
bounded as the tag body.

Neither the unsynchronisation flag nor the compression flag changes this outer
operation. Their interpretation belongs to the later complete structural
parser.

Params:
    cursor = Cursor positioned at the beginning of an ID3v2.2 tag.

Returns:
    A bounded tag envelope or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v22TagEnvelope
parseId3v22TagEnvelope(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    auto headerResult =
        probe.parseId3v22Header();

    if (headerResult.hasError)
    {
        return
            ParseResult!Id3v22TagEnvelope
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
            ParseResult!Id3v22TagEnvelope
                .failure(
                    bodyResult.error
                );
    }

    const envelope =
        Id3v22TagEnvelope(
            header,
            bodyResult.value
        );

    cursor =
        probe;

    return
        ParseResult!Id3v22TagEnvelope
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
            0x02, 0x00,
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
        cursor.parseId3v22TagEnvelope();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.header.sourceOffset == 100);
    assert(tag.header.revision == 0);
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
            0x02, 0x00,
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
        cursor.parseId3v22TagEnvelope();

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


/// Whole-tag unsynchronisation does not change outer physical bounding.
unittest
{
    /*
     * Logical body bytes:
     *
     *   11 FF E1
     *
     * Physical stored body:
     *
     *   11 FF 00 E1
     *
     * The tag-size field describes the four stored physical bytes.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x80,

            0x00, 0x00, 0x00, 0x04,

            0x11,
            0xFF, 0x00,
            0xE1,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto result =
        cursor.parseId3v22TagEnvelope();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.header.unsynchronisation);
    assert(tag.header.tagSize == 4);

    assert(
        tag.body.data ==
        [
            0x11,
            0xFF, 0x00,
            0xE1
        ]
    );

    assert(tag.body.sourceOffset == 310);
    assert(tag.endOffset == 314);

    assert(cursor.absoluteOffset == 314);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


/// Whole-tag compression also leaves outer body bytes opaque.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x01,
            0x40,

            0x00, 0x00, 0x00, 0x04,

            0xDE, 0xAD, 0xBE, 0xEF,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto result =
        cursor.parseId3v22TagEnvelope();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.header.compressed);
    assert(tag.header.revision == 1);

    assert(
        tag.body.data ==
        [0xDE, 0xAD, 0xBE, 0xEF]
    );

    assert(tag.body.sourceOffset == 410);
    assert(tag.endOffset == 414);

    assert(cursor.absoluteOffset == 414);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


/// A body may end exactly at the end of its bounded parent region.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x02,

            0xAA, 0xBB
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto result =
        cursor.parseId3v22TagEnvelope();

    assert(result.hasValue);
    assert(result.value.body.length == 2);
    assert(result.value.endOffset == 512);
    assert(cursor.empty);
}


/// A truncated declared body fails atomically at the body boundary.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x05,

            0x11, 0x22
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto result =
        cursor.parseId3v22TagEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 610);
    assert(result.error.requested == 5);
    assert(result.error.available == 2);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 600);
    assert(cursor.remaining == bytes.length);
}


/// Header failures propagate without consuming the caller cursor.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x01,

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
        cursor.parseId3v22TagEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.unsupportedVersion
    );

    assert(result.error.offset == 703);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 700);
}


/// Envelope offsets remain absolute after prior cursor movement.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x01,

            0x55,

            0x42
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
        cursor.parseId3v22TagEnvelope();

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
    assert(cursor.front == 0x42);
}
