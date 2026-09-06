/++
Complete strict structural parsing for one ID3v2.3 tag.

This module composes the lower-level ID3v2.3 parsers into one
transactional structural parse:

- tag header and bounded outer envelope;
- optional extended header;
- frame sequence and padding;
- each frame's structural format fields;
- extended-header padding-size consistency.

Semantic frame contents are deliberately not decoded here.

Tag-level unsynchronisation is reversed only while traversing already
bounded physical tag-body regions. Raw physical source representation
and absolute offsets remain available throughout the structure.

Extended-header CRC data is parsed structurally but the CRC checksum
itself is not yet verified against the frame sequence.

Parsing is atomic: any structural failure leaves the caller's cursor
unchanged.
+/
module audiotag.id3v2.v23.structure;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.body :
    Id3v23BodyLayout,
    parseId3v23BodyLayout;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.frame :
    parseId3v23FrameEnvelope;

import audiotag.id3v2.v23.frame_data :
    parseId3v23FrameDataLayout;

import audiotag.id3v2.v23.frame_sequence :
    Id3v23FrameSequenceLayout,
    parseId3v23FrameSequenceLayout;

import audiotag.id3v2.v23.tag :
    Id3v23TagEnvelope,
    parseId3v23TagEnvelope;


/++
Complete validated structural representation of one ID3v2.3 tag.

Individual frames remain represented by the contiguous physical
`frames.frameBytes` span. They can later be iterated without requiring
this structural parser to allocate a dynamic frame collection.

When tag-level unsynchronisation is active, `frameCursor()` traverses
those physical frame bytes through the corresponding logical stream.
+/
struct Id3v23TagStructure
{
    /// Validated outer tag envelope.
    Id3v23TagEnvelope envelope;

    /// Partitioned tag body.
    Id3v23BodyLayout body;

    /// Validated frame sequence and optional padding.
    Id3v23FrameSequenceLayout frames;


    /// Number of structurally validated frames.
    @property
    size_t frameCount() const
        @safe pure nothrow @nogc
    {
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

    The cursor automatically applies the enclosing ID3v2.3 tag-level
    unsynchronisation state.
    +/
    Id3v23DataCursor
    frameCursor() const
        @safe pure nothrow @nogc
    {
        return
            Id3v23DataCursor(
                frames.frameBytes,
                envelope.header
                    .unsynchronisation
            );
    }
}


/++
Strictly parses one complete ID3v2.3 tag structure.

All nested parsing is performed inside regions already bounded by their
parent structures.

Every complete frame is structurally validated twice at different
levels:

1. the frame-sequence parser establishes complete frame boundaries;
2. this parser traverses the validated frame region again and validates
   each frame's optional format additions.

No semantic payload decoding occurs.

When an extended header is present, its declared padding size must
equal the actual validated trailing padding length.

Params:
    cursor = Cursor positioned at the first byte of an ID3v2.3 tag.

Returns:
    The complete structural tag representation or a structured parse
    error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v23TagStructure
parseId3v23TagStructure(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;


    auto envelopeResult =
        probe.parseId3v23TagEnvelope();

    if (envelopeResult.hasError)
    {
        return
            ParseResult!Id3v23TagStructure
                .failure(
                    envelopeResult.error
                );
    }

    const envelope =
        envelopeResult.value;


    auto bodyResult =
        envelope.parseId3v23BodyLayout();

    if (bodyResult.hasError)
    {
        return
            ParseResult!Id3v23TagStructure
                .failure(
                    bodyResult.error
                );
    }

    const body =
        bodyResult.value;


    auto sequenceResult =
        parseId3v23FrameSequenceLayout(
            body.framesAndPadding,
            envelope.header
                .unsynchronisation
        );

    if (sequenceResult.hasError)
    {
        return
            ParseResult!Id3v23TagStructure
                .failure(
                    sequenceResult.error
                );
    }

    const sequence =
        sequenceResult.value;


    /*
     * Validate the structural additions at the beginning of every
     * bounded frame-data region.
     *
     * Reiterate the physical frame region through the same logical
     * unsynchronisation state used by the sequence parser.
     */
    auto frameCursor =
        Id3v23DataCursor(
            sequence.frameBytes,
            envelope.header
                .unsynchronisation
        );

    size_t validatedFrameCount =
        0;

    while (
        !frameCursor.empty
    )
    {
        auto frameResult =
            frameCursor
                .parseId3v23FrameEnvelope();

        if (frameResult.hasError)
        {
            return
                ParseResult!Id3v23TagStructure
                    .failure(
                        frameResult.error
                    );
        }

        auto dataResult =
            frameResult.value
                .parseId3v23FrameDataLayout(
                    envelope.header
                        .unsynchronisation
                );

        if (dataResult.hasError)
        {
            return
                ParseResult!Id3v23TagStructure
                    .failure(
                        dataResult.error
                    );
        }

        ++validatedFrameCount;
    }

    /*
     * The sequence was traversed with the same logical frame-envelope
     * parser inside the same validated physical span. A mismatch here
     * is therefore an internal invariant violation rather than malformed
     * external input.
     */
    assert(
        validatedFrameCount ==
        sequence.frameCount
    );


    /*
     * ID3v2.3 stores the total padding size in the optional extended
     * header.
     *
     * Padding itself contains only zero bytes. Any unsynchronisation
     * stuffing required at the preceding frame/padding boundary has
     * already been consumed as part of the physical frame region.
     * Therefore the validated padding span length is the declared
     * padding length.
     */
    if (
        body.hasExtendedHeader &&
        cast(size_t)
            body.extendedHeader
                .paddingSize !=
            sequence.padding.length
    )
    {
        /*
         * In every valid v2.3 extended header the padding-size field
         * begins six physical bytes after the structure start:
         *
         *   4 size bytes
         *   2 flag bytes
         *
         * Neither valid size nor valid flags can themselves require
         * unsynchronisation stuffing.
         */
        return
            ParseResult!Id3v23TagStructure
                .failure(
                    ParseError(
                        ParseErrorCode
                            .inconsistentStructure,
                        body.extendedHeader
                            .sourceOffset +
                            6
                    )
                );
    }


    const result =
        Id3v23TagStructure(
            envelope,
            body,
            sequence
        );

    cursor =
        probe;

    return
        ParseResult!Id3v23TagStructure
            .success(result);
}


/// A minimal complete tag is parsed as one structural unit.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            /*
             * One eleven-byte frame.
             */
            0x00, 0x00, 0x00, 0x0B,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            /*
             * Outside the tag.
             */
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
        cursor.parseId3v23TagStructure();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(
        tag.envelope.header.sourceOffset ==
        100
    );

    assert(
        tag.envelope.header.tagSize ==
        11
    );

    assert(!tag.body.hasExtendedHeader);

    assert(tag.frameCount == 1);

    assert(
        tag.frames.frameBytes.sourceOffset ==
        110
    );

    assert(
        tag.frames.frameBytes.length ==
        11
    );

    assert(tag.frames.padding.empty);

    assert(
        tag.frames.padding.sourceOffset ==
        121
    );

    assert(tag.endOffset == 121);

    assert(cursor.absoluteOffset == 121);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0xAA);
}


/// Extended header, frame and matching padding compose correctly.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            /*
             * Extended header.
             */
            0x40,

            /*
             * Body:
             *
             *   10-byte extended header
             *   11-byte frame
             *    3-byte padding
             *
             * Total = 24.
             */
            0x00, 0x00, 0x00, 0x18,

            /*
             * Extended-header size = 6.
             */
            0x00, 0x00, 0x00, 0x06,

            /*
             * No CRC.
             */
            0x00, 0x00,

            /*
             * Padding size = 3.
             */
            0x00, 0x00, 0x00, 0x03,

            /*
             * One frame.
             */
            'T', 'A', 'L', 'B',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            /*
             * Padding.
             */
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
        cursor.parseId3v23TagStructure();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.body.hasExtendedHeader);

    assert(
        tag.body.extendedHeader
            .sourceOffset ==
        210
    );

    assert(
        tag.body.extendedHeader
            .paddingSize ==
        3
    );

    assert(
        tag.body.framesAndPadding
            .sourceOffset ==
        220
    );

    assert(
        tag.body.framesAndPadding
            .length ==
        14
    );

    assert(tag.frameCount == 1);

    assert(
        tag.frames.frameBytes
            .sourceOffset ==
        220
    );

    assert(
        tag.frames.frameBytes.length ==
        11
    );

    assert(
        tag.frames.padding.sourceOffset ==
        231
    );

    assert(
        tag.frames.padding.length ==
        3
    );

    assert(tag.endOffset == 234);

    assert(cursor.absoluteOffset == 234);
    assert(cursor.front == 0xAA);
}


/// Extended-header padding size must match the actual padding.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            0x00, 0x00, 0x00, 0x18,

            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            /*
             * Declares four padding bytes.
             */
            0x00, 0x00, 0x00, 0x04,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            /*
             * Only three actually exist.
             */
            0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto result =
        cursor.parseId3v23TagStructure();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    /*
     * Extended header begins at 410.
     * Padding-size field begins at 416.
     */
    assert(result.error.offset == 416);

    /*
     * Complete structural parsing is transactional.
     */
    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 400);
}


/// Frame-format additions are validated for every bounded frame.
unittest
{
    /*
     * Compression requires four decompressed-size bytes at the
     * beginning of frame data. This frame declares only one byte.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x0B,

            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x01,

            /*
             * Compression flag.
             */
            0x00, 0x80,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto result =
        cursor.parseId3v23TagStructure();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    /*
     * Frame data begins at 520. One byte can be consumed as the first
     * decompressed-size byte; the next required logical byte is beyond
     * the bounded frame.
     */
    assert(result.error.offset == 521);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 500);
}


/// A zero-sized tag body fails because ID3v2.3 requires a frame.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto result =
        cursor.parseId3v23TagStructure();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 610);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 600);
}


/// Whole-tag unsynchronisation composes through frame and padding parsing.
unittest
{
    /*
     * Logical frame payload:
     *
     *   FF
     *
     * followed by two logical padding bytes.
     *
     * At the frame/padding boundary whole-tag unsynchronisation inserts
     * a stuffing zero after FF.
     *
     * Physical frames/padding region:
     *
     *   frame header
     *   FF 00
     *   00 00
     *
     * Frame physical length = 12.
     * Padding physical length = 2.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            /*
             * Tag-level unsynchronisation.
             */
            0x80,

            /*
             * Physical body size = 14.
             */
            0x00, 0x00, 0x00, 0x0E,

            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            /*
             * Logical payload FF plus stuffing.
             */
            0xFF, 0x00,

            /*
             * Actual padding.
             */
            0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto result =
        cursor.parseId3v23TagStructure();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(
        tag.envelope.header
            .unsynchronisation
    );

    assert(tag.frameCount == 1);

    assert(
        tag.frames.frameBytes.length ==
        12
    );

    assert(
        tag.frames.padding.length ==
        2
    );

    assert(
        tag.frames.padding.sourceOffset ==
        722
    );

    /*
     * The structure-provided frame cursor must expose the same logical
     * frame despite retaining its physical unsynchronised bytes.
     */
    auto frames =
        tag.frameCursor();

    auto frameResult =
        frames.parseId3v23FrameEnvelope();

    assert(frameResult.hasValue);

    assert(
        frameResult.value.header.size ==
        1
    );

    assert(
        frameResult.value.data.length ==
        2
    );

    assert(frames.empty);
}


/// Unsynchronisation inside an extended-header CRC composes correctly.
unittest
{
    /*
     * Extended header:
     *
     * logical length = 14
     * physical length = 15 because CRC contains FF E1
     *
     * Frame = 11 physical bytes.
     * Padding = 2 bytes.
     *
     * Physical body = 28 bytes.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            /*
             * Unsynchronisation + extended header.
             */
            0xC0,

            0x00, 0x00, 0x00, 0x1C,

            /*
             * Extended-header size = 10.
             */
            0x00, 0x00, 0x00, 0x0A,

            /*
             * CRC present.
             */
            0x80, 0x00,

            /*
             * Padding size = 2.
             */
            0x00, 0x00, 0x00, 0x02,

            /*
             * Logical CRC = 12 FF E1 34.
             * Physical unsynchronised CRC = 12 FF 00 E1 34.
             */
            0x12,
            0xFF, 0x00,
            0xE1,
            0x34,

            /*
             * One ordinary frame.
             */
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            /*
             * Two padding bytes.
             */
            0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                800
            )
        );

    auto result =
        cursor.parseId3v23TagStructure();

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.body.hasExtendedHeader);

    assert(
        tag.body.extendedHeader.hasCrc
    );

    assert(
        tag.body.extendedHeader.crc32 ==
        0x12FF_E134
    );

    assert(
        tag.body.extendedHeader.raw.length ==
        15
    );

    assert(
        tag.body.extendedHeader
            .paddingSize ==
        2
    );

    assert(tag.frameCount == 1);
    assert(tag.frames.padding.length == 2);

    assert(tag.endOffset == 838);
    assert(cursor.absoluteOffset == 838);
}


/// Structural failures after outer-envelope parsing remain transactional.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            /*
             * One malformed eleven-byte frame.
             */
            0x00, 0x00, 0x00, 0x0B,

            /*
             * Lowercase frame IDs are invalid.
             */
            'a', 'B', 'C', '1',

            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

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
        cursor.parseId3v23TagStructure();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 910);

    /*
     * Even though the complete outer envelope fit, the caller is not
     * advanced because the nested structure failed.
     */
    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 900);
    assert(cursor.remaining == bytes.length);
}
