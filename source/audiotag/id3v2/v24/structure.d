/++
Complete strict structural parsing for one ID3v2.4 tag.

This module composes the lower-level ID3v2.4 parsers into one
transactional structural parse:

- tag header and bounded outer envelope;
- optional extended header;
- frame sequence and padding;
- each frame's structural format fields.

Semantic frame contents are deliberately not decoded here.

Extended-header CRC data is parsed structurally but the CRC checksum
itself is not yet verified against the tag contents.

Parsing is atomic: any structural failure leaves the caller's cursor
unchanged.
+/
module audiotag.id3v2.v24.structure;

import audiotag.core.cursor : ByteCursor;
import audiotag.core.error : ParseErrorCode;
import audiotag.core.result : ParseResult;
import audiotag.core.span : ByteSpan;

import audiotag.id3v2.v24.body :
    Id3v24BodyLayout,
    parseId3v24BodyLayout;

import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;

import audiotag.id3v2.v24.frame_data :
    parseId3v24FrameDataLayout;

import audiotag.id3v2.v24.frame_sequence :
    Id3v24FrameSequenceLayout,
    parseId3v24FrameSequenceLayout;

import audiotag.id3v2.v24.tag :
    Id3v24TagEnvelope,
    parseId3v24TagEnvelope;


/++
Complete validated structural representation of one ID3v2.4 tag.

Individual frames remain represented by the contiguous
`frames.frameBytes` span. They can later be iterated without requiring
this structural parser to allocate a dynamic frame collection.
+/
struct Id3v24TagStructure
{
    /// Validated outer tag envelope.
    Id3v24TagEnvelope envelope;

    /// Partitioned tag body.
    Id3v24BodyLayout body;

    /// Validated frame sequence and optional padding.
    Id3v24FrameSequenceLayout frames;

    /// Number of structurally validated frames.
    @property
    size_t frameCount() const
        @safe pure nothrow @nogc
    {
        return frames.frameCount;
    }

    /// Absolute offset immediately following the complete tag.
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return envelope.endOffset;
    }

    /// Constructs a cursor over exactly the validated frame bytes.
    ByteCursor frameCursor() const
        @safe pure nothrow @nogc
    {
        return ByteCursor(frames.frameBytes);
    }
}


/++
Strictly parses one complete ID3v2.4 tag structure.

All nested parsing is performed inside spans already bounded by their
parent structures. Frame format prefixes are validated for every
frame, but semantic payload contents are left untouched.

Params:
    cursor = Cursor positioned at the first byte of an ID3v2.4 tag.

Returns:
    The complete structural tag representation or a structured parse
    error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v24TagStructure parseId3v24TagStructure(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe = cursor;

    auto envelopeResult =
        probe.parseId3v24TagEnvelope();

    if (envelopeResult.hasError)
    {
        return ParseResult!Id3v24TagStructure.failure(
            envelopeResult.error
        );
    }

    const envelope = envelopeResult.value;

    auto bodyResult =
        envelope.parseId3v24BodyLayout();

    if (bodyResult.hasError)
    {
        return ParseResult!Id3v24TagStructure.failure(
            bodyResult.error
        );
    }

    const body = bodyResult.value;

    auto sequenceResult =
        parseId3v24FrameSequenceLayout(
            body.framesAndPadding,
            envelope.header.hasFooter
        );

    if (sequenceResult.hasError)
    {
        return ParseResult!Id3v24TagStructure.failure(
            sequenceResult.error
        );
    }

    const sequence = sequenceResult.value;

    // Validate the structural additions at the beginning of every
    // bounded frame-data region. No semantic payload decoding occurs.
    auto frameCursor =
        ByteCursor(sequence.frameBytes);

    size_t validatedFrameCount = 0;

    while (!frameCursor.empty)
    {
        auto frameResult =
            frameCursor.parseId3v24FrameEnvelope();

        if (frameResult.hasError)
        {
            return ParseResult!Id3v24TagStructure.failure(
                frameResult.error
            );
        }

        auto dataResult =
            frameResult.value
                .parseId3v24FrameDataLayout(
                    envelope.header.unsynchronisation
                );

        if (dataResult.hasError)
        {
            return ParseResult!Id3v24TagStructure.failure(
                dataResult.error
            );
        }

        ++validatedFrameCount;
    }

    // The same validated frame span was traversed by the same bounded
    // frame-envelope parser. A mismatch is therefore a programmer
    // invariant violation, not malformed external input.
    assert(validatedFrameCount == sequence.frameCount);

    const result = Id3v24TagStructure(
        envelope,
        body,
        sequence
    );

    cursor = probe;

    return ParseResult!Id3v24TagStructure.success(result);
}


/// A minimal complete tag is parsed as one structural unit.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x0B,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0xAA
        ];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));

    auto result =
        cursor.parseId3v24TagStructure();

    assert(result.hasValue);

    const tag = result.value;

    assert(tag.envelope.header.sourceOffset == 100);
    assert(tag.envelope.header.tagSize == 11);

    assert(!tag.body.hasExtendedHeader);

    assert(tag.frameCount == 1);
    assert(tag.frames.frameBytes.sourceOffset == 110);
    assert(tag.frames.frameBytes.length == 11);

    assert(tag.frames.padding.empty);
    assert(tag.frames.padding.sourceOffset == 121);

    assert(tag.endOffset == 121);

    assert(cursor.absoluteOffset == 121);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0xAA);
}


/// Extended header, frame sequence and padding compose correctly.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,
            0x00, 0x00, 0x00, 0x14,

            // Minimal extended header: six bytes.
            0x00, 0x00, 0x00, 0x06,
            0x01,
            0x00,

            // One eleven-byte frame.
            'T', 'A', 'L', 'B',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            // Three bytes of padding.
            0x00, 0x00, 0x00,

            0xAA
        ];

    auto cursor = ByteCursor(ByteSpan(bytes, 200));

    auto result =
        cursor.parseId3v24TagStructure();

    assert(result.hasValue);

    const tag = result.value;

    assert(tag.body.hasExtendedHeader);
    assert(tag.body.extendedHeader.sourceOffset == 210);
    assert(tag.body.extendedHeader.size == 6);

    assert(tag.body.framesAndPadding.sourceOffset == 216);
    assert(tag.body.framesAndPadding.length == 14);

    assert(tag.frameCount == 1);

    assert(tag.frames.frameBytes.sourceOffset == 216);
    assert(tag.frames.frameBytes.length == 11);

    assert(tag.frames.padding.sourceOffset == 227);
    assert(tag.frames.padding.length == 3);

    assert(tag.endOffset == 230);

    assert(cursor.absoluteOffset == 230);
    assert(cursor.front == 0xAA);
}


/// A footer composes with a frame sequence that has no padding.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x0B,

            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            '3', 'D', 'I',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x0B,

            0xAA
        ];

    auto cursor = ByteCursor(ByteSpan(bytes, 300));

    auto result =
        cursor.parseId3v24TagStructure();

    assert(result.hasValue);

    const tag = result.value;

    assert(tag.envelope.header.hasFooter);
    assert(tag.envelope.footer.sourceOffset == 321);
    assert(tag.envelope.footer.length == 10);

    assert(tag.frameCount == 1);
    assert(tag.frames.padding.empty);

    assert(tag.endOffset == 331);

    assert(cursor.absoluteOffset == 331);
    assert(cursor.front == 0xAA);
}


/// Deep frame-data failures make the complete parse atomic.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x0D,

            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x03,
            0x00,
            0x01,

            // DLI flag requires four logical bytes,
            // but the complete bounded frame has only three.
            0x00, 0x00, 0x00
        ];

    auto cursor = ByteCursor(ByteSpan(bytes, 400));

    auto result =
        cursor.parseId3v24TagStructure();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 423);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 400);
    assert(cursor.remaining == bytes.length);
}


/// Footer and padding are rejected as a cross-layer inconsistency.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            // Padding is forbidden because a footer follows.
            0x00,

            '3', 'D', 'I',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x0C
        ];

    auto cursor = ByteCursor(ByteSpan(bytes, 500));

    auto result =
        cursor.parseId3v24TagStructure();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 521);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 500);
}


/// An extended header without any following frame is not a valid tag.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,
            0x00, 0x00, 0x00, 0x06,

            0x00, 0x00, 0x00, 0x06,
            0x01,
            0x00
        ];

    auto cursor = ByteCursor(ByteSpan(bytes, 600));

    auto result =
        cursor.parseId3v24TagStructure();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 616);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 600);
}


/// The frame cursor is bounded to validated frame bytes only.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x0D,

            'T', 'C', 'O', 'N',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x42,

            0x00, 0x00
        ];

    auto cursor = ByteCursor(ByteSpan(bytes, 700));

    auto result =
        cursor.parseId3v24TagStructure();

    assert(result.hasValue);

    auto frames = result.value.frameCursor();

    assert(frames.absoluteOffset == 710);
    assert(frames.remaining == 11);

    auto frameResult =
        frames.parseId3v24FrameEnvelope();

    assert(frameResult.hasValue);
    assert(frameResult.value.header.id[] == "TCON");

    assert(frames.empty);
}
