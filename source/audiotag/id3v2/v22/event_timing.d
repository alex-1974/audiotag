/++
ID3v2.2 event-timing-code (`ETC`) frame decoding.

The frame contains one timestamp-format discriminator followed by zero or more
event entries. Each event consists of an extensible event type followed by a
four-byte absolute big-endian timestamp.

Event type `$FF` is a continuation marker: another event-type byte follows,
and any further `$FF` bytes have the same continuation meaning. The final
non-`$FF` byte is retained as the terminal event type.

ID3v2.2 defines named events only through `$0D`; later revisions assign names
to additional previously-reserved values. Event-type semantics therefore
remain revision-specific in this module.

Whole-tag unsynchronisation is reversed during logical traversal. Raw event
type and timestamp spans preserve the exact physical source representation.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.event_timing;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.timestamp :
    Id3v2TimestampFormat,
    isValidId3v2TimestampFormat;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;


/++
One provenance-preserving native ID3v2.2 event-timing entry.

`continuationCount` is the number of leading `$FF` continuation markers before
the terminal non-`$FF` event-type byte.

Reserved terminal event values are valid native data and are not rejected.
+/
struct Id3v22EventTimingEntry
{
    size_t continuationCount;
    ubyte eventType;
    uint timestamp;
    ByteSpan rawEventType;
    ByteSpan rawTimestamp;
}


/++
Decoded native ID3v2.2 `ETC` frame.

Entry ordering is preserved exactly. ID3v2.2 says events should be sorted
chronologically, so this native decoder does not reject or reorder an
out-of-order source sequence.
+/
struct Id3v22EventTimingFrame
{
    size_t sourceOffset;
    Id3v2TimestampFormat timestampFormat;
    size_t timestampFormatSourceOffset;
    Id3v22EventTimingEntry[] events;
    bool effectiveUnsynchronisation;
}


/++
Decodes one ID3v2.2 event-timing-code (`ETC`) frame.

Timestamp-format values other than `$01` and `$02` are structurally invalid.

Every event must contain a terminal non-`$FF` event-type byte followed by
exactly four logical timestamp bytes. `$FF` bytes extend the event-type code
and may repeat until a non-`$FF` terminal byte occurs.

Reserved terminal event values remain valid native data. The specification's
single-ETC-per-tag rule belongs to tag-level validation, not this frame codec.
+/
ParseResult!Id3v22EventTimingFrame
decodeId3v22EventTimingFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "ETC"
    )
    {
        return
            ParseResult!Id3v22EventTimingFrame
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

    auto formatResult =
        payload.takeByte();

    if (formatResult.hasError)
    {
        return
            ParseResult!Id3v22EventTimingFrame
                .failure(
                    formatResult.error
                );
    }

    const formatByte =
        formatResult.value;

    if (
        !isValidId3v2TimestampFormat(
            formatByte.value
        )
    )
    {
        return
            ParseResult!Id3v22EventTimingFrame
                .failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        formatByte.sourceOffset
                    )
                );
    }

    const timestampFormat =
        cast(Id3v2TimestampFormat)
            formatByte.value;

    Id3v22EventTimingEntry[] events;

    while (!payload.empty)
    {
        const eventTypeStart =
            payload.remainingRaw;

        size_t continuationCount =
            0;

        ubyte eventType;

        for (;;)
        {
            auto typeResult =
                payload.takeByte();

            if (typeResult.hasError)
            {
                return
                    ParseResult!Id3v22EventTimingFrame
                        .failure(
                            typeResult.error
                        );
            }

            const typeByte =
                typeResult.value.value;

            if (typeByte == 0xFF)
            {
                ++continuationCount;
                continue;
            }

            eventType =
                typeByte;
            break;
        }

        const eventTypePhysicalLength =
            eventTypeStart.length -
            payload.remainingRaw.length;

        const rawEventType =
            eventTypeStart.subspan(
                0,
                eventTypePhysicalLength
            );

        const timestampStart =
            payload.remainingRaw;

        auto timestampResult =
            payload.takeU32BE();

        if (timestampResult.hasError)
        {
            return
                ParseResult!Id3v22EventTimingFrame
                    .failure(
                        timestampResult.error
                    );
        }

        const timestampPhysicalLength =
            timestampStart.length -
            payload.remainingRaw.length;

        const rawTimestamp =
            timestampStart.subspan(
                0,
                timestampPhysicalLength
            );

        events ~=
            Id3v22EventTimingEntry(
                continuationCount,
                eventType,
                timestampResult.value,
                rawEventType,
                rawTimestamp
            );
    }

    return
        ParseResult!Id3v22EventTimingFrame
            .success(
                Id3v22EventTimingFrame(
                    frame.header.sourceOffset,
                    timestampFormat,
                    formatByte.sourceOffset,
                    events,
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


/// Millisecond events decode as ordered absolute 32-bit timestamps.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'T', 'C',
            0x00, 0x00, 0x0B,

            0x02,

            0x02,
            0x00, 0x00, 0x03, 0xE8,

            0x0D,
            0x00, 0x00, 0x07, 0xD0
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
            .decodeId3v22EventTimingFrame();

    assert(result.hasValue);

    const timing =
        result.value;

    assert(timing.sourceOffset == 100);
    assert(
        timing.timestampFormat ==
        Id3v2TimestampFormat.milliseconds
    );
    assert(timing.timestampFormatSourceOffset == 106);
    assert(timing.events.length == 2);

    assert(timing.events[0].continuationCount == 0);
    assert(timing.events[0].eventType == 0x02);
    assert(timing.events[0].timestamp == 1000);

    assert(timing.events[1].continuationCount == 0);
    assert(timing.events[1].eventType == 0x0D);
    assert(timing.events[1].timestamp == 2000);

    assert(!timing.effectiveUnsynchronisation);
}


/// MPEG-frame timestamps use the same unsigned 32-bit representation.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'T', 'C',
            0x00, 0x00, 0x06,

            0x01,
            0x03,
            0x12, 0x34, 0x56, 0x78
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
            .decodeId3v22EventTimingFrame();

    assert(result.hasValue);
    assert(
        result.value.timestampFormat ==
        Id3v2TimestampFormat.mpegFrames
    );
    assert(result.value.events.length == 1);
    assert(result.value.events[0].eventType == 0x03);
    assert(result.value.events[0].timestamp == 0x12_34_56_78);
}


/// Reserved v2.2 event codes remain valid native values.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'T', 'C',
            0x00, 0x00, 0x06,

            0x02,
            0x15,
            0x00, 0x00, 0x00, 0x2A
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
            .decodeId3v22EventTimingFrame();

    assert(result.hasValue);
    assert(result.value.events.length == 1);
    assert(result.value.events[0].eventType == 0x15);
    assert(result.value.events[0].timestamp == 42);
}


/// Event-type continuation markers are retained before the timestamp.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'T', 'C',
            0x00, 0x00, 0x08,

            0x02,

            0xFF, 0xFF, 0xE0,
            0x00, 0x00, 0x00, 0x2A
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
            .decodeId3v22EventTimingFrame();

    assert(result.hasValue);
    assert(result.value.events.length == 1);

    const event =
        result.value.events[0];

    assert(event.continuationCount == 2);
    assert(event.eventType == 0xE0);
    assert(event.timestamp == 42);
    assert(event.rawEventType.data == [0xFF, 0xFF, 0xE0]);
    assert(event.rawTimestamp.data == [0x00, 0x00, 0x00, 0x2A]);
}


/// Invalid timestamp-format discriminators are rejected.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'T', 'C',
            0x00, 0x00, 0x01,

            0x03
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22EventTimingFrame();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );
    assert(result.error.offset == 506);
}


/// The format byte may be followed by an empty event list.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'T', 'C',
            0x00, 0x00, 0x01,

            0x02
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
            .decodeId3v22EventTimingFrame();

    assert(result.hasValue);
    assert(result.value.events.length == 0);
}


/// A continuation chain without a terminal event-type byte is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'T', 'C',
            0x00, 0x00, 0x02,

            0x02,
            0xFF
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22EventTimingFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
}


/// A complete event type without four timestamp bytes is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'T', 'C',
            0x00, 0x00, 0x05,

            0x02,
            0x03,
            0x00, 0x00, 0x01
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                800
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22EventTimingFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
}


/// ETC rejects a different native frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',
            0x00, 0x00, 0x01,

            0x02
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22EventTimingFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 900);
}


/// Whole-tag unsynchronisation preserves physical event and timestamp spans.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'T', 'C',
            0x00, 0x00, 0x07,

            0x02,

            0xFF, 0x00,
            0xE0,

            0x00,
            0xFF, 0x00,
            0xE1,
            0x02
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1000
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 7);
    assert(frame.value.data.length == 9);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22EventTimingFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.effectiveUnsynchronisation);
    assert(result.value.events.length == 1);

    const event =
        result.value.events[0];

    assert(event.continuationCount == 1);
    assert(event.eventType == 0xE0);
    assert(event.timestamp == 0x00_FF_E1_02);

    assert(
        event.rawEventType.data ==
        [
            0xFF, 0x00,
            0xE0
        ]
    );

    assert(
        event.rawTimestamp.data ==
        [
            0x00,
            0xFF, 0x00,
            0xE1,
            0x02
        ]
    );
}
