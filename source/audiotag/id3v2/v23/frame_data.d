/++
ID3v2.3 frame-data structural partitioning.

This module separates the already bounded physical frame-data region
into optional ID3v2.3 frame-format fields and the remaining semantic
payload.

When the enclosing tag is unsynchronised, reads operate on the logical
byte stream while the remaining payload stays represented by its raw
physical `ByteSpan`.

ID3v2.3 frame-format additions are consumed in flag order:

- four-byte decompressed size when compression is set;
- one-byte encryption method when encryption is set;
- one-byte grouping identity when grouping is set.

No decryption, decompression or semantic frame decoding is performed
here.
+/
module audiotag.id3v2.v23.frame_data;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.frame :
    Id3v23FrameEnvelope;


/++
Structural layout of one ID3v2.3 frame-data region.

Optional field values are meaningful only when their corresponding
`has...` property is true.

`rawPayload` preserves the physical source representation. When
`effectiveUnsynchronisation` is true, later semantic decoders must
traverse that span through `Id3v23DataCursor` rather than interpreting
the raw bytes directly.
+/
struct Id3v23FrameDataLayout
{
    /// Whether tag-level ID3v2.3 unsynchronisation applies.
    bool effectiveUnsynchronisation;

    /// Whether the four-byte decompressed-size field was present.
    bool hasDecompressedSize;

    /// Declared decompressed size when compression is set.
    uint decompressedSize;

    /// Physical source offset of the first decompressed-size byte.
    size_t decompressedSizeOffset;

    /// Whether an encryption-method byte was present.
    bool hasEncryptionMethod;

    /// Encryption-method value when present.
    ubyte encryptionMethod;

    /// Physical source offset of the encryption-method byte.
    size_t encryptionMethodOffset;

    /// Whether a grouping-identity byte was present.
    bool hasGroupingIdentity;

    /// Grouping-identity value when present.
    ubyte groupingIdentity;

    /// Physical source offset of the grouping byte.
    size_t groupingIdentityOffset;

    /// Remaining physical frame bytes after all format fields.
    ByteSpan rawPayload;


    /++
    Constructs a logical cursor over the remaining semantic payload.

    The cursor applies the same enclosing tag-level unsynchronisation
    state used while parsing the frame-format additions.
    +/
    Id3v23DataCursor
    payloadCursor() const
        @safe pure nothrow @nogc
    {
        return
            Id3v23DataCursor(
                rawPayload,
                effectiveUnsynchronisation
            );
    }
}


/++
Partitions one bounded ID3v2.3 frame-data region.

ID3v2.3 frame-header format flags extend the frame data in the same
order as the flags that declare them:

1. compression adds a four-byte unsigned big-endian decompressed size;
2. encryption adds one encryption-method byte;
3. grouping adds one grouping-identity byte.

All of these additions are included in `frame.header.size`.

When tag-level unsynchronisation is active, these fields are read from
the logical byte stream while their physical source offsets remain
available.

Params:
    frame = Previously validated and logically bounded ID3v2.3 frame.
    tagUnsynchronised = Whether the enclosing ID3v2.3 tag declares
        tag-level unsynchronisation.

Returns:
    The structural frame-data layout or a structured parse error.
+/
ParseResult!Id3v23FrameDataLayout
parseId3v23FrameDataLayout(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe pure nothrow @nogc
{
    auto cursor =
        Id3v23DataCursor(
            frame.data,
            tagUnsynchronised
        );

    bool hasDecompressedSize =
        false;

    uint decompressedSize =
        0;

    size_t decompressedSizeOffset =
        0;

    bool hasEncryptionMethod =
        false;

    ubyte encryptionMethod =
        0;

    size_t encryptionMethodOffset =
        0;

    bool hasGroupingIdentity =
        false;

    ubyte groupingIdentity =
        0;

    size_t groupingIdentityOffset =
        0;


    /*
     * Format additions occur in the same order as their format flags:
     *
     *   compression
     *   encryption
     *   grouping
     */
    if (frame.header.compressed)
    {
        decompressedSizeOffset =
            cursor.absoluteOffset;

        auto result =
            cursor.takeU32BE();

        if (result.hasError)
        {
            return
                ParseResult!Id3v23FrameDataLayout
                    .failure(
                        result.error
                    );
        }

        hasDecompressedSize =
            true;

        decompressedSize =
            result.value;
    }


    if (frame.header.encrypted)
    {
        auto result =
            cursor.takeByte();

        if (result.hasError)
        {
            return
                ParseResult!Id3v23FrameDataLayout
                    .failure(
                        result.error
                    );
        }

        hasEncryptionMethod =
            true;

        encryptionMethod =
            result.value.value;

        encryptionMethodOffset =
            result.value.sourceOffset;
    }


    if (frame.header.hasGroupingIdentity)
    {
        auto result =
            cursor.takeByte();

        if (result.hasError)
        {
            return
                ParseResult!Id3v23FrameDataLayout
                    .failure(
                        result.error
                    );
        }

        hasGroupingIdentity =
            true;

        groupingIdentity =
            result.value.value;

        groupingIdentityOffset =
            result.value.sourceOffset;
    }


    const layout =
        Id3v23FrameDataLayout(
            tagUnsynchronised,

            hasDecompressedSize,
            decompressedSize,
            decompressedSizeOffset,

            hasEncryptionMethod,
            encryptionMethod,
            encryptionMethodOffset,

            hasGroupingIdentity,
            groupingIdentity,
            groupingIdentityOffset,

            cursor.remainingRaw
        );

    return
        ParseResult!Id3v23FrameDataLayout
            .success(layout);
}


version (unittest)
{
    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;
}


/// Without format flags, the complete frame data remains payload.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0x11, 0x22, 0x33
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                100
            ),
            false
        );

    auto frameResult =
        cursor.parseId3v23FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v23FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout =
        layoutResult.value;

    assert(
        !layout
            .effectiveUnsynchronisation
    );

    assert(!layout.hasDecompressedSize);
    assert(!layout.hasEncryptionMethod);
    assert(!layout.hasGroupingIdentity);

    assert(layout.rawPayload.sourceOffset == 110);
    assert(layout.rawPayload.length == 3);

    assert(
        layout.rawPayload.data ==
        [0x11, 0x22, 0x33]
    );
}


/// Compression removes its four-byte decompressed size from the payload.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x80,

            /*
             * Decompressed size = 256.
             */
            0x00, 0x00, 0x01, 0x00,

            0xAA, 0xBB
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                200
            ),
            false
        );

    auto frameResult =
        cursor.parseId3v23FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v23FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout =
        layoutResult.value;

    assert(layout.hasDecompressedSize);
    assert(layout.decompressedSize == 256);
    assert(layout.decompressedSizeOffset == 210);

    assert(!layout.hasEncryptionMethod);
    assert(!layout.hasGroupingIdentity);

    assert(layout.rawPayload.sourceOffset == 214);
    assert(layout.rawPayload.data == [0xAA, 0xBB]);
}


/// Encryption removes one method byte from the semantic payload.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x40,

            0x23,

            0xAA, 0xBB
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                300
            ),
            false
        );

    auto frameResult =
        cursor.parseId3v23FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v23FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout =
        layoutResult.value;

    assert(!layout.hasDecompressedSize);

    assert(layout.hasEncryptionMethod);
    assert(layout.encryptionMethod == 0x23);
    assert(layout.encryptionMethodOffset == 310);

    assert(!layout.hasGroupingIdentity);

    assert(layout.rawPayload.sourceOffset == 311);
    assert(layout.rawPayload.data == [0xAA, 0xBB]);
}


/// Grouping removes one group identifier from the semantic payload.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x20,

            0x12,

            0xAA, 0xBB
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                400
            ),
            false
        );

    auto frameResult =
        cursor.parseId3v23FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v23FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout =
        layoutResult.value;

    assert(!layout.hasDecompressedSize);
    assert(!layout.hasEncryptionMethod);

    assert(layout.hasGroupingIdentity);
    assert(layout.groupingIdentity == 0x12);
    assert(layout.groupingIdentityOffset == 410);

    assert(layout.rawPayload.sourceOffset == 411);
    assert(layout.rawPayload.data == [0xAA, 0xBB]);
}


/// All additions occur in compression, encryption, grouping order.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0xE0,

            /*
             * Compression: decompressed size.
             */
            0x00, 0x00, 0x00, 0x10,

            /*
             * Encryption method.
             */
            0x34,

            /*
             * Grouping identity.
             */
            0x12,

            /*
             * Opaque semantic payload.
             */
            0xAA, 0xBB
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                500
            ),
            false
        );

    auto frameResult =
        cursor.parseId3v23FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v23FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout =
        layoutResult.value;

    assert(layout.hasDecompressedSize);
    assert(layout.decompressedSize == 0x10);
    assert(layout.decompressedSizeOffset == 510);

    assert(layout.hasEncryptionMethod);
    assert(layout.encryptionMethod == 0x34);
    assert(layout.encryptionMethodOffset == 514);

    assert(layout.hasGroupingIdentity);
    assert(layout.groupingIdentity == 0x12);
    assert(layout.groupingIdentityOffset == 515);

    assert(layout.rawPayload.sourceOffset == 516);
    assert(layout.rawPayload.data == [0xAA, 0xBB]);
}


/// Decompressed-size reads operate after tag-level unsynchronisation.
unittest
{
    /*
     * Logical decompressed-size bytes:
     *
     *   00 FF 00 02
     *
     * Physical representation:
     *
     *   00 FF 00 00 02
     *
     * The inserted zero after $FF is not part of the uint value.
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x80,

            0x00,
            0xFF, 0x00,
            0x00,
            0x02,

            0xAA, 0xBB
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                600
            ),
            true
        );

    auto frameResult =
        cursor.parseId3v23FrameEnvelope();

    assert(frameResult.hasValue);

    /*
     * Six logical data bytes occupy seven physical bytes.
     */
    assert(frameResult.value.header.size == 6);
    assert(frameResult.value.data.length == 7);

    auto layoutResult =
        frameResult.value
            .parseId3v23FrameDataLayout(
                true
            );

    assert(layoutResult.hasValue);

    const layout =
        layoutResult.value;

    assert(layout.effectiveUnsynchronisation);

    assert(layout.hasDecompressedSize);

    assert(
        layout.decompressedSize ==
        0x00FF_0002
    );

    assert(layout.decompressedSizeOffset == 610);

    /*
     * Four logical prefix bytes consumed five physical bytes.
     */
    assert(layout.rawPayload.sourceOffset == 615);
    assert(layout.rawPayload.data == [0xAA, 0xBB]);
}


/// Encryption methods are also read from the logical byte stream.
unittest
{
    /*
     * Logical frame data:
     *
     *   FF E1
     *
     * Physical representation:
     *
     *   FF 00 E1
     *
     * The first logical byte is the encryption method.
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x40,

            0xFF, 0x00,
            0xE1
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                700
            ),
            true
        );

    auto frameResult =
        cursor.parseId3v23FrameEnvelope();

    assert(frameResult.hasValue);
    assert(frameResult.value.data.length == 3);

    auto layoutResult =
        frameResult.value
            .parseId3v23FrameDataLayout(
                true
            );

    assert(layoutResult.hasValue);

    const layout =
        layoutResult.value;

    assert(layout.hasEncryptionMethod);
    assert(layout.encryptionMethod == 0xFF);
    assert(layout.encryptionMethodOffset == 710);

    assert(layout.rawPayload.sourceOffset == 712);
    assert(layout.rawPayload.data == [0xE1]);
}


/// Truncated decompressed-size fields fail at the frame boundary.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x80,

            /*
             * Only three decompressed-size bytes are present.
             */
            0x00, 0x00, 0x00
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                800
            ),
            false
        );

    auto frameResult =
        cursor.parseId3v23FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v23FrameDataLayout();

    assert(layoutResult.hasError);

    assert(
        layoutResult.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(layoutResult.error.offset == 813);
    assert(layoutResult.error.requested == 1);
    assert(layoutResult.error.available == 0);
}


/// Format additions may consume all logical frame data.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0xE0,

            0x00, 0x00, 0x00, 0x10,
            0x23,
            0x12
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                900
            ),
            false
        );

    auto frameResult =
        cursor.parseId3v23FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v23FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout =
        layoutResult.value;

    assert(layout.hasDecompressedSize);
    assert(layout.hasEncryptionMethod);
    assert(layout.hasGroupingIdentity);

    assert(layout.rawPayload.empty);
    assert(layout.rawPayload.sourceOffset == 916);
}


/// The payload cursor retains tag-level unsynchronisation semantics.
unittest
{
    /*
     * Logical payload:
     *
     *   FF E1
     *
     * Physical payload:
     *
     *   FF 00 E1
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0xFF, 0x00,
            0xE1
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1000
            ),
            true
        );

    auto frameResult =
        cursor.parseId3v23FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v23FrameDataLayout(
                true
            );

    assert(layoutResult.hasValue);

    auto payload =
        layoutResult.value
            .payloadCursor();

    auto first =
        payload.takeByte();

    auto second =
        payload.takeByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 1010);

    assert(second.hasValue);
    assert(second.value.value == 0xE1);
    assert(second.value.sourceOffset == 1012);

    assert(payload.empty);
}
