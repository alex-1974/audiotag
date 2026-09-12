/++
ID3v2.2 synchronised-tempo-code (`STC`) frame decoding.

The frame contains one timestamp-format discriminator followed by one or more
tempo entries. Each entry contains one tempo descriptor and one absolute
unsigned 32-bit big-endian timestamp.

`$00` denotes a beat-free period. `$01` denotes one single beat followed by a
beat-free period. `$02` through `$FE` directly encode BPM. `$FF` requires one
additional byte; the BPM value is 255 plus that byte, giving a maximum of 510.

Whole-tag unsynchronisation is reversed during logical traversal. Raw tempo and
timestamp spans retain the exact physical source representation.

This module performs no canonical metadata mapping.


Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.synchronised_tempo;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.tempo :
    Id3v2Tempo,
    Id3v2TempoKind;

import audiotag.id3v2.common.timestamp :
    Id3v2TimestampFormat,
    isValidId3v2TimestampFormat;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

struct Id3v22SynchronisedTempoEntry
{
    Id3v2Tempo tempo;
    uint timestamp;
    ByteSpan rawTempo;
    ByteSpan rawTimestamp;
}

struct Id3v22SynchronisedTempoFrame
{
    size_t sourceOffset;
    Id3v2TimestampFormat timestampFormat;
    size_t timestampFormatSourceOffset;
    Id3v22SynchronisedTempoEntry[] entries;
    bool effectiveUnsynchronisation;
}

ParseResult!Id3v22SynchronisedTempoFrame
decodeId3v22SynchronisedTempoFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (frame.header.id[] != "STC")
    {
        return
            ParseResult!Id3v22SynchronisedTempoFrame
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
            ParseResult!Id3v22SynchronisedTempoFrame
                .failure(
                    formatResult.error
                );
    }

    const formatByte =
        formatResult.value;

    if (!isValidId3v2TimestampFormat(formatByte.value))
    {
        return
            ParseResult!Id3v22SynchronisedTempoFrame
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

    if (payload.empty)
    {
        return
            ParseResult!Id3v22SynchronisedTempoFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        payload.absoluteOffset,
                        1,
                        0
                    )
                );
    }

    Id3v22SynchronisedTempoEntry[] entries;

    while (!payload.empty)
    {
        const tempoStart =
            payload.remainingRaw;

        auto firstResult =
            payload.takeByte();

        if (firstResult.hasError)
        {
            return
                ParseResult!Id3v22SynchronisedTempoFrame
                    .failure(
                        firstResult.error
                    );
        }

        const first =
            firstResult.value.value;

        Id3v2Tempo tempo;

        if (first == 0x00)
        {
            tempo =
                Id3v2Tempo(
                    Id3v2TempoKind.beatFree,
                    0
                );
        }
        else if (first == 0x01)
        {
            tempo =
                Id3v2Tempo(
                    Id3v2TempoKind.singleBeat,
                    0
                );
        }
        else if (first == 0xFF)
        {
            auto extensionResult =
                payload.takeByte();

            if (extensionResult.hasError)
            {
                return
                    ParseResult!Id3v22SynchronisedTempoFrame
                        .failure(
                            extensionResult.error
                        );
            }

            tempo =
                Id3v2Tempo(
                    Id3v2TempoKind.beatsPerMinute,
                    cast(ushort)
                        (
                            255 +
                            cast(uint)
                                extensionResult.value.value
                        )
                );
        }
        else
        {
            tempo =
                Id3v2Tempo(
                    Id3v2TempoKind.beatsPerMinute,
                    cast(ushort) first
                );
        }

        const tempoPhysicalLength =
            tempoStart.length -
            payload.remainingRaw.length;

        const rawTempo =
            tempoStart.subspan(
                0,
                tempoPhysicalLength
            );

        const timestampStart =
            payload.remainingRaw;

        auto timestampResult =
            payload.takeU32BE();

        if (timestampResult.hasError)
        {
            return
                ParseResult!Id3v22SynchronisedTempoFrame
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

        entries ~=
            Id3v22SynchronisedTempoEntry(
                tempo,
                timestampResult.value,
                rawTempo,
                rawTimestamp
            );
    }

    return
        ParseResult!Id3v22SynchronisedTempoFrame
            .success(
                Id3v22SynchronisedTempoFrame(
                    frame.header.sourceOffset,
                    timestampFormat,
                    formatByte.sourceOffset,
                    entries,
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

unittest
{
    const ubyte[] bytes =
        [
            'S', 'T', 'C',
            0x00, 0x00, 0x0B,

            0x02,

            120,
            0x00, 0x00, 0x03, 0xE8,

            90,
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
            .decodeId3v22SynchronisedTempoFrame();

    assert(result.hasValue);

    const timing =
        result.value;

    assert(timing.sourceOffset == 100);
    assert(
        timing.timestampFormat ==
        Id3v2TimestampFormat.milliseconds
    );
    assert(timing.timestampFormatSourceOffset == 106);
    assert(timing.entries.length == 2);
    assert(timing.entries[0].tempo.beatsPerMinute == 120);
    assert(timing.entries[0].timestamp == 1000);
    assert(timing.entries[1].tempo.beatsPerMinute == 90);
    assert(timing.entries[1].timestamp == 2000);
}

unittest
{
    const ubyte[] bytes =
        [
            'S', 'T', 'C',
            0x00, 0x00, 0x0B,

            0x01,

            0x00,
            0x00, 0x00, 0x00, 0x10,

            0x01,
            0x00, 0x00, 0x00, 0x20
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
            .decodeId3v22SynchronisedTempoFrame();

    assert(result.hasValue);
    assert(
        result.value.entries[0].tempo.kind ==
        Id3v2TempoKind.beatFree
    );
    assert(
        result.value.entries[1].tempo.kind ==
        Id3v2TempoKind.singleBeat
    );
}

unittest
{
    const ubyte[] bytes =
        [
            'S', 'T', 'C',
            0x00, 0x00, 0x07,

            0x02,

            0xFF, 0xFF,
            0x12, 0x34, 0x56, 0x78
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
            .decodeId3v22SynchronisedTempoFrame();

    assert(result.hasValue);

    const entry =
        result.value.entries[0];

    assert(entry.tempo.kind == Id3v2TempoKind.beatsPerMinute);
    assert(entry.tempo.beatsPerMinute == 510);
    assert(entry.timestamp == 0x12_34_56_78);
    assert(entry.rawTempo.data == [0xFF, 0xFF]);
}

unittest
{
    const ubyte[] bytes =
        [
            'S', 'T', 'C',
            0x00, 0x00, 0x01,

            0x03
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
            .decodeId3v22SynchronisedTempoFrame();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );
    assert(result.error.offset == 406);
}

unittest
{
    const ubyte[] bytes =
        [
            'S', 'T', 'C',
            0x00, 0x00, 0x01,

            0x02
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
            .decodeId3v22SynchronisedTempoFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 507);
}

unittest
{
    const ubyte[] bytes =
        [
            'S', 'T', 'C',
            0x00, 0x00, 0x02,

            0x02,
            0xFF
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
            .decodeId3v22SynchronisedTempoFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
}

unittest
{
    const ubyte[] bytes =
        [
            'S', 'T', 'C',
            0x00, 0x00, 0x05,

            0x02,
            120,
            0x00, 0x00, 0x01
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
            .decodeId3v22SynchronisedTempoFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
}

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
                800
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22SynchronisedTempoFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 800);
}

unittest
{
    const ubyte[] bytes =
        [
            'S', 'T', 'C',
            0x00, 0x00, 0x07,

            0x02,

            0xFF, 0x00,
            0x2D,

            0x00,
            0xFF, 0x00,
            0xE1,
            0x02
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                900
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
            .decodeId3v22SynchronisedTempoFrame(
                true
            );

    assert(result.hasValue);

    const entry =
        result.value.entries[0];

    assert(entry.tempo.kind == Id3v2TempoKind.beatsPerMinute);
    assert(entry.tempo.beatsPerMinute == 300);
    assert(entry.timestamp == 0x00_FF_E1_02);

    assert(
        entry.rawTempo.data ==
        [
            0xFF, 0x00,
            0x2D
        ]
    );

    assert(
        entry.rawTimestamp.data ==
        [
            0x00,
            0xFF, 0x00,
            0xE1,
            0x02
        ]
    );
}
