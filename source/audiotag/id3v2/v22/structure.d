/++
Complete strict structural parsing for one ID3v2.2 tag.

This module composes the lower-level ID3v2.2 parsers into one transactional
structural parse:

- tag header and bounded outer envelope;
- optional whole-tag unsynchronisation while traversing the body;
- frame sequence and trailing padding.

ID3v2.2 has no per-frame flags or structural frame-format additions, so a
successfully validated frame sequence is sufficient to establish the complete
uncompressed tag structure.

Whole-tag compression is a valid header state but ID3v2.2 does not standardise
a compression representation. Such a body is therefore preserved exactly as
opaque physical bytes and is not interpreted as frames.

Semantic frame contents are deliberately not decoded here.

Parsing is atomic: any structural failure leaves the caller's cursor unchanged.
+/
module audiotag.id3v2.v22.structure;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    parseId3v22FrameEnvelope;

import audiotag.id3v2.v22.frame_sequence :
    Id3v22FrameSequenceLayout,
    parseId3v22FrameSequenceLayout;

import audiotag.id3v2.v22.tag :
    Id3v22TagEnvelope,
    parseId3v22TagEnvelope;


/++
Identifies whether an ID3v2.2 body was structurally interpreted as frames or
preserved as an opaque compressed representation.
+/
enum Id3v22TagBodyKind : ubyte
{
    /// Validated frame sequence with optional trailing padding.
    framesAndPadding,

    /// Whole-tag-compressed physical body retained without interpretation.
    compressedOpaque
}


/++
Complete validated structural representation of one ID3v2.2 tag.

For `framesAndPadding`, `frames` contains the validated physical frame and
padding partition.

For `compressedOpaque`, `frames` remains its default value and must not be
interpreted. The exact opaque bytes remain available as `envelope.body`.
+/
struct Id3v22TagStructure
{
    /// Validated outer tag envelope.
    Id3v22TagEnvelope envelope;

    /// How the tag body is represented structurally.
    Id3v22TagBodyKind bodyKind;

    /// Validated frame sequence when `bodyKind == framesAndPadding`.
    Id3v22FrameSequenceLayout frames;


    /// Whether this structure contains a validated frame sequence.
    @property
    bool hasFrameSequence() const
        @safe pure nothrow @nogc
    {
        return
            bodyKind ==
            Id3v22TagBodyKind.framesAndPadding;
    }


    /// Whether the exact tag body is retained as opaque compressed bytes.
    @property
    bool compressedOpaque() const
        @safe pure nothrow @nogc
    {
        return
            bodyKind ==
            Id3v22TagBodyKind.compressedOpaque;
    }


    /++
    Number of structurally validated frames.

    Preconditions:
        `hasFrameSequence` must be true.
    +/
    @property
    size_t frameCount() const
        @safe pure nothrow @nogc
    {
        assert(hasFrameSequence);

        return
            frames.frameCount;
    }


    /// Absolute offset immediately following the complete tag.
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return
            envelope.endOffset;
    }


    /++
    Constructs a logical cursor over exactly the validated frame bytes.

    Whole-tag unsynchronisation is applied automatically according to the
    enclosing ID3v2.2 header.

    Preconditions:
        `hasFrameSequence` must be true.
    +/
    Id3v22DataCursor
    frameCursor() const
        @safe pure nothrow @nogc
    {
        assert(hasFrameSequence);

        return
            Id3v22DataCursor(
                frames.frameBytes,
                envelope.header
                    .unsynchronisation
            );
    }
}


/++
Strictly parses one complete ID3v2.2 tag structure.

Uncompressed tag bodies must contain one or more complete frames followed by
optional logical zero padding. Whole-tag unsynchronisation is reversed only
during logical traversal; all returned spans retain exact physical source
bytes.

When the compression flag is set, the exact bounded body is accepted as an
opaque compressed representation. No attempt is made to guess a compression
format or reinterpret those bytes as frame headers.

Params:
    cursor = Cursor positioned at the first byte of an ID3v2.2 tag.

Returns:
    The complete structural tag representation or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v22TagStructure
parseId3v22TagStructure(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    auto envelopeResult =
        probe.parseId3v22TagEnvelope();

    if (envelopeResult.hasError)
    {
        return
            ParseResult!Id3v22TagStructure
                .failure(
                    envelopeResult.error
                );
    }

    const envelope =
        envelopeResult.value;

    if (
        envelope.header.compressed
    )
    {
        const structure =
            Id3v22TagStructure(
                envelope,
                Id3v22TagBodyKind.compressedOpaque,
                Id3v22FrameSequenceLayout.init
            );

        cursor =
            probe;

        return
            ParseResult!Id3v22TagStructure
                .success(structure);
    }

    auto sequenceResult =
        parseId3v22FrameSequenceLayout(
            envelope.body,
            envelope.header
                .unsynchronisation
        );

    if (sequenceResult.hasError)
    {
        return
            ParseResult!Id3v22TagStructure
                .failure(
                    sequenceResult.error
                );
    }

    const structure =
        Id3v22TagStructure(
            envelope,
            Id3v22TagBodyKind.framesAndPadding,
            sequenceResult.value
        );

    cursor =
        probe;

    return
        ParseResult!Id3v22TagStructure
            .success(structure);
}


version (unittest)
{
    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.core.span :
        ByteSpan;
}


/// A minimal complete uncompressed tag is parsed as one structural unit.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            /*
             * One seven-byte frame.
             */
            0x00, 0x00, 0x00, 0x07,

            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55,

            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto result =
        cursor.parseId3v22TagStructure();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.hasFrameSequence);
    assert(!tag.compressedOpaque);

    assert(tag.envelope.header.sourceOffset == 100);
    assert(tag.envelope.header.tagSize == 7);

    assert(tag.frameCount == 1);

    assert(tag.frames.frameBytes.sourceOffset == 110);
    assert(tag.frames.frameBytes.length == 7);

    assert(tag.frames.padding.empty);
    assert(tag.frames.padding.sourceOffset == 117);

    assert(tag.endOffset == 117);

    assert(cursor.absoluteOffset == 117);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0xAA);
}


/// Multiple frames and trailing padding compose correctly.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            /*
             * Body:
             *
             *   TT2 frame = 7
             *   TP1 frame = 8
             *   padding   = 3
             *
             * Total = 18.
             */
            0x00, 0x00, 0x00, 0x12,

            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x11,

            'T', 'P', '1',
            0x00, 0x00, 0x02,
            0x22, 0x33,

            0x00, 0x00, 0x00,

            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                200
            )
        );

    auto result =
        cursor.parseId3v22TagStructure();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.frameCount == 2);
    assert(tag.frames.frameBytes.sourceOffset == 210);
    assert(tag.frames.frameBytes.length == 15);
    assert(tag.frames.padding.sourceOffset == 225);
    assert(tag.frames.padding.length == 3);

    assert(tag.endOffset == 228);
    assert(cursor.absoluteOffset == 228);
    assert(cursor.front == 0xAA);
}


/// Whole-tag unsynchronisation is applied during frame traversal only.
unittest
{
    /*
     * Logical body:
     *
     *   TT2 size=3
     *   payload 11 FF E1
     *   padding 00 00
     *
     * Physical body:
     *
     *   TT2 size=3
     *   payload 11 FF 00 E1
     *   padding 00 00
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x80,

            /*
             * Physical body size = 12.
             */
            0x00, 0x00, 0x00, 0x0C,

            'T', 'T', '2',
            0x00, 0x00, 0x03,

            0x11,
            0xFF, 0x00,
            0xE1,

            0x00, 0x00,

            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto result =
        cursor.parseId3v22TagStructure();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.hasFrameSequence);
    assert(tag.envelope.header.unsynchronisation);
    assert(tag.frameCount == 1);

    /*
     * Six physical header bytes plus four physical payload bytes.
     */
    assert(tag.frames.frameBytes.length == 10);
    assert(tag.frames.padding.sourceOffset == 320);
    assert(tag.frames.padding.length == 2);

    assert(tag.endOffset == 322);
    assert(cursor.absoluteOffset == 322);
    assert(cursor.front == 0xAA);
}


/// The frame cursor reproduces the validated logical frame stream.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x80,

            /*
             * Physical body = one frame.
             *
             * Logical payload is FF E1, stored as FF 00 E1.
             */
            0x00, 0x00, 0x00, 0x09,

            'T', 'T', '2',
            0x00, 0x00, 0x02,
            0xFF, 0x00, 0xE1
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto result =
        cursor.parseId3v22TagStructure();

    assert(result.hasValue);

    auto frameCursor =
        result.value.frameCursor();

    auto frameResult =
        frameCursor.parseId3v22FrameEnvelope();

    assert(frameResult.hasValue);
    assert(frameResult.value.header.id[] == "TT2");
    assert(frameResult.value.header.size == 2);

    assert(
        frameResult.value.data.data ==
        [0xFF, 0x00, 0xE1]
    );

    assert(frameCursor.empty);
}


/// Whole-tag compression is preserved as a valid opaque representation.
unittest
{
    /*
     * The body is deliberately not a valid frame sequence.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x40,

            0x00, 0x00, 0x00, 0x04,

            0xDE, 0xAD, 0xBE, 0xEF,

            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto result =
        cursor.parseId3v22TagStructure();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(!tag.hasFrameSequence);
    assert(tag.compressedOpaque);

    assert(tag.envelope.header.compressed);
    assert(tag.envelope.header.revision == 0);

    assert(
        tag.envelope.body.data ==
        [0xDE, 0xAD, 0xBE, 0xEF]
    );

    assert(
        tag.frames ==
        Id3v22FrameSequenceLayout.init
    );

    assert(tag.endOffset == 514);
    assert(cursor.absoluteOffset == 514);
    assert(cursor.front == 0xAA);
}


/// Compression and unsynchronisation flags preserve the opaque physical body.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0xC0,

            0x00, 0x00, 0x00, 0x03,

            0xFF, 0x00, 0xE1
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto result =
        cursor.parseId3v22TagStructure();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.compressedOpaque);
    assert(tag.envelope.header.unsynchronisation);
    assert(tag.envelope.header.compressed);

    /*
     * An opaque compressed body is never unsynchronised speculatively.
     */
    assert(
        tag.envelope.body.data ==
        [0xFF, 0x00, 0xE1]
    );

    assert(cursor.empty);
}


/// A malformed uncompressed frame sequence fails transactionally.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x07,

            /*
             * Invalid lowercase frame identifier.
             */
            't', 'T', '2',
            0x00, 0x00, 0x01,
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
        cursor.parseId3v22TagStructure();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 710);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 700);
}


/// A zero-sized uncompressed body fails because v2.2 requires a frame.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x00,

            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                800
            )
        );

    auto result =
        cursor.parseId3v22TagStructure();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 810);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 800);
}


/// A compressed zero-sized body remains opaque because its format is unknown.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x40,

            0x00, 0x00, 0x00, 0x00,

            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto result =
        cursor.parseId3v22TagStructure();

    assert(result.hasValue);
    assert(result.value.compressedOpaque);
    assert(result.value.envelope.body.empty);

    assert(result.value.endOffset == 910);
    assert(cursor.absoluteOffset == 910);
    assert(cursor.front == 0xAA);
}
