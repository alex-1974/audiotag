/++
ID3v2.2 play-counter (`CNT`) frame decoding.

The frame contains one unsigned big-endian counter.

The counter is at least four logical bytes wide and may grow by prepending
additional bytes. It is therefore not narrowed to `uint` or `ulong`.

The decoded semantic counter stores exact logical bytes. `rawCounter` retains
the complete physical frame-data bytes, including any whole-tag
unsynchronisation stuffing.
+/
module audiotag.id3v2.v22.play_counter;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.counter :
    Id3v2Counter;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;


/++
Decoded native ID3v2.2 `CNT` frame.
+/
struct Id3v22PlayCounterFrame
{
    size_t sourceOffset;
    Id3v2Counter counter;
    ByteSpan rawCounter;
    bool effectiveUnsynchronisation;
}


/++
Decodes one ID3v2.2 play-counter frame.

The counter must contain at least four logical bytes. No upper width is
imposed.
+/
ParseResult!Id3v22PlayCounterFrame
decodeId3v22PlayCounterFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (frame.header.id[] != "CNT")
    {
        return
            ParseResult!Id3v22PlayCounterFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }

    auto payload =
        Id3v22DataCursor(
            frame.data,
            tagUnsynchronised
        );

    const rawCounter =
        payload.remainingRaw;

    ubyte[] logicalCounter;

    logicalCounter.reserve(
        frame.header.size
    );

    while (!payload.empty)
    {
        auto byteResult =
            payload.takeByte();

        if (byteResult.hasError)
        {
            return
                ParseResult!Id3v22PlayCounterFrame
                    .failure(
                        byteResult.error
                    );
        }

        logicalCounter ~=
            byteResult.value.value;
    }

    if (logicalCounter.length < 4)
    {
        return
            ParseResult!Id3v22PlayCounterFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        frame.data.sourceOffset,
                        4,
                        logicalCounter.length
                    )
                );
    }

    return
        ParseResult!Id3v22PlayCounterFrame
            .success(
                Id3v22PlayCounterFrame(
                    frame.header.sourceOffset,
                    Id3v2Counter(
                        logicalCounter
                    ),
                    rawCounter,
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


/// A four-byte counter decodes without narrowing or normalization.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'N', 'T',
            0x00, 0x00, 0x04,

            0x00, 0x00, 0x00, 0x2A
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
            .decodeId3v22PlayCounterFrame();

    assert(result.hasValue);

    const counter =
        result.value;

    assert(counter.sourceOffset == 100);
    assert(counter.counter.byteLength == 4);

    assert(
        counter.counter.bigEndianBytes ==
        [
            0x00, 0x00, 0x00, 0x2A
        ]
    );

    assert(counter.rawCounter.sourceOffset == 106);

    assert(
        counter.rawCounter.data ==
        [
            0x00, 0x00, 0x00, 0x2A
        ]
    );

    assert(!counter.effectiveUnsynchronisation);
}


/// Counter widths greater than 64 bits remain valid.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'N', 'T',
            0x00, 0x00, 0x0C,

            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C
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
            .decodeId3v22PlayCounterFrame();

    assert(result.hasValue);
    assert(result.value.counter.byteLength == 12);

    assert(
        result.value.counter.bigEndianBytes ==
        [
            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C
        ]
    );
}


/// Counters shorter than the required 32 bits are rejected.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'N', 'T',
            0x00, 0x00, 0x03,

            0x00, 0x00, 0x01
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
            .decodeId3v22PlayCounterFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 306);
    assert(result.error.requested == 4);
    assert(result.error.available == 3);
}


/// The CNT codec rejects a different native frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x04,

            0x00, 0x00, 0x00, 0x00
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
            .decodeId3v22PlayCounterFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 400);
}


/// Whole-tag unsynchronisation preserves raw bytes and logical counter value.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'N', 'T',
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

    auto result =
        frame.value
            .decodeId3v22PlayCounterFrame(
                true
            );

    assert(result.hasValue);

    const counter =
        result.value;

    assert(counter.effectiveUnsynchronisation);

    assert(
        counter.counter.bigEndianBytes ==
        [
            0x00,
            0xFF,
            0xE1,
            0x01
        ]
    );

    assert(
        counter.rawCounter.data ==
        [
            0x00,
            0xFF, 0x00,
            0xE1,
            0x01
        ]
    );

    assert(counter.rawCounter.sourceOffset == 506);
}
