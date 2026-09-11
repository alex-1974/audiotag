/++
ID3v2.2 recommended-buffer-size (`BUF`) frame decoding.

The logical payload is either four or eight bytes:

- recommended buffer size: unsigned 24-bit big-endian;
- embedded-info flag: `%0000000x`;
- optional offset to the next tag: unsigned 32-bit big-endian.

The upper seven bits of the flag byte are reserved and must be zero.

Whole-tag unsynchronisation is reversed during logical traversal. Raw spans
retain the exact physical source representation, including stuffing bytes.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.recommended_buffer;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.recommended_buffer :
    Id3v2RecommendedBuffer;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;


/++
Decoded native ID3v2.2 `BUF` frame.
+/
struct Id3v22RecommendedBufferFrame
{
    size_t sourceOffset;
    Id3v2RecommendedBuffer value;
    ByteSpan rawBufferSize;
    size_t embeddedInfoFlagSourceOffset;
    ByteSpan rawNextTagOffset;
    bool effectiveUnsynchronisation;
}


/++
Decodes one ID3v2.2 recommended-buffer-size (`BUF`) frame.

The logical payload length must be exactly four bytes when the next-tag offset
is absent or exactly eight bytes when it is present.

The single-BUF-per-tag rule belongs to tag-level validation rather than this
single-frame decoder.
+/
ParseResult!Id3v22RecommendedBufferFrame
decodeId3v22RecommendedBufferFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "BUF"
    )
    {
        return
            ParseResult!Id3v22RecommendedBufferFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }

    if (
        frame.header.size != 4 &&
        frame.header.size != 8
    )
    {
        return
            ParseResult!Id3v22RecommendedBufferFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        frame.data.sourceOffset
                    )
                );
    }

    auto payload =
        Id3v22DataCursor(
            frame.data,
            tagUnsynchronised
        );

    const bufferStart =
        payload.remainingRaw;

    auto bufferSizeResult =
        payload.takeU24BE();

    if (bufferSizeResult.hasError)
    {
        return
            ParseResult!Id3v22RecommendedBufferFrame
                .failure(
                    bufferSizeResult.error
                );
    }

    const rawBufferSize =
        bufferStart.subspan(
            0,
            bufferStart.length -
                payload.remainingRaw.length
        );

    auto flagResult =
        payload.takeByte();

    if (flagResult.hasError)
    {
        return
            ParseResult!Id3v22RecommendedBufferFrame
                .failure(
                    flagResult.error
                );
    }

    const flagByte =
        flagResult.value;

    if (
        (
            flagByte.value &
            0xFE
        ) !=
        0
    )
    {
        return
            ParseResult!Id3v22RecommendedBufferFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidFlags,
                        flagByte.sourceOffset
                    )
                );
    }

    const hasNextTagOffset =
        frame.header.size ==
        8;

    uint nextTagOffset =
        0;

    ByteSpan rawNextTagOffset =
        payload.remainingRaw.subspan(
            0,
            0
        );

    if (hasNextTagOffset)
    {
        const offsetStart =
            payload.remainingRaw;

        auto offsetResult =
            payload.takeU32BE();

        if (offsetResult.hasError)
        {
            return
                ParseResult!Id3v22RecommendedBufferFrame
                    .failure(
                        offsetResult.error
                    );
        }

        nextTagOffset =
            offsetResult.value;

        rawNextTagOffset =
            offsetStart.subspan(
                0,
                offsetStart.length -
                    payload.remainingRaw.length
            );
    }

    if (!payload.empty)
    {
        return
            ParseResult!Id3v22RecommendedBufferFrame
                .failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        payload.absoluteOffset
                    )
                );
    }

    return
        ParseResult!Id3v22RecommendedBufferFrame
            .success(
                Id3v22RecommendedBufferFrame(
                    frame.header.sourceOffset,
                    Id3v2RecommendedBuffer(
                        bufferSizeResult.value,
                        (
                            flagByte.value &
                            0x01
                        ) !=
                            0,
                        hasNextTagOffset,
                        nextTagOffset
                    ),
                    rawBufferSize,
                    flagByte.sourceOffset,
                    rawNextTagOffset,
                    tagUnsynchronised
                )
            );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.id3v2.v22.frame :
        parseId3v22FrameEnvelope;
}


/// Minimal four-byte BUF payload decodes without a next-tag offset.
unittest
{
    const ubyte[] bytes =
        [
            'B', 'U', 'F',
            0x00, 0x00, 0x04,

            0x00, 0x10, 0x00,
            0x01
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22RecommendedBufferFrame();

    assert(result.hasValue);

    const buffer =
        result.value;

    assert(buffer.sourceOffset == 100);
    assert(buffer.value.bufferSize == 4096);
    assert(buffer.value.embeddedInfo);
    assert(!buffer.value.hasNextTagOffset);
    assert(buffer.value.nextTagOffset == 0);
    assert(buffer.rawBufferSize.sourceOffset == 106);
    assert(buffer.rawBufferSize.data == [0x00, 0x10, 0x00]);
    assert(buffer.embeddedInfoFlagSourceOffset == 109);
    assert(buffer.rawNextTagOffset.empty);
    assert(!buffer.effectiveUnsynchronisation);
}


/// Eight-byte BUF payload decodes the optional next-tag offset.
unittest
{
    const ubyte[] bytes =
        [
            'B', 'U', 'F',
            0x00, 0x00, 0x08,

            0x01, 0x02, 0x03,
            0x00,
            0x11, 0x22, 0x33, 0x44
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                200
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22RecommendedBufferFrame();

    assert(result.hasValue);
    assert(result.value.value.bufferSize == 0x01_02_03);
    assert(!result.value.value.embeddedInfo);
    assert(result.value.value.hasNextTagOffset);
    assert(result.value.value.nextTagOffset == 0x11_22_33_44);
    assert(result.value.rawNextTagOffset.sourceOffset == 210);
}


/// Reserved flag bits are rejected.
unittest
{
    const ubyte[] bytes =
        [
            'B', 'U', 'F',
            0x00, 0x00, 0x04,

            0x00, 0x10, 0x00,
            0x80
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22RecommendedBufferFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidFlags);
    assert(result.error.offset == 309);
}


/// Logical lengths other than four or eight bytes are rejected.
unittest
{
    const ubyte[] bytes =
        [
            'B', 'U', 'F',
            0x00, 0x00, 0x05,

            0x00, 0x10, 0x00,
            0x00,
            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22RecommendedBufferFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
}


/// Whole-tag unsynchronisation preserves physical spans.
unittest
{
    const ubyte[] bytes =
        [
            'B', 'U', 'F',
            0x00, 0x00, 0x04,

            0x00,
            0xFF, 0x00,
            0xE1,
            0x01
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                500
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 4);
    assert(frame.value.data.length == 5);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22RecommendedBufferFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.effectiveUnsynchronisation);
    assert(result.value.value.bufferSize == 0x00_FF_E1);
    assert(result.value.value.embeddedInfo);

    assert(
        result.value.rawBufferSize.data ==
        [
            0x00,
            0xFF, 0x00,
            0xE1
        ]
    );
}


/// BUF rejects another native frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'R', 'E', 'V',
            0x00, 0x00, 0x04,
            0x00, 0x10, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22RecommendedBufferFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 600);
}
