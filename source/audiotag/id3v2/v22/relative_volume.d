/++
ID3v2.2 relative-volume-adjustment (`RVA`) frame decoding.

The frame stores separate right/left increment flags, one non-zero bit width,
mandatory unsigned right/left adjustment magnitudes and an optional complete
right/left peak pair.

Numeric descriptions occupy whole bytes. If the declared bit width is not a
multiple of eight, unused most-significant padding bits must be zero.

Whole-tag unsynchronisation is reversed during logical traversal. Raw value
spans preserve exact physical source representation.

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
module audiotag.id3v2.v22.relative_volume;

import std.bigint :
    BigInt;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult,
    ParseStatus;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.relative_volume :
    Id3v2LegacyVolumeChannelAdjustment;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

enum Id3v22RelativeVolumeChannel : ubyte
{
    right,
    left
}

struct Id3v22RelativeVolumeChannelAdjustment
{
    Id3v22RelativeVolumeChannel channel;
    Id3v2LegacyVolumeChannelAdjustment adjustment;
    ByteSpan rawChangeMagnitude;
    ByteSpan rawPeak;
}

struct Id3v22RelativeVolumeFrame
{
    size_t sourceOffset;
    size_t incrementDecrementSourceOffset;
    ubyte bitsUsed;
    size_t bitsUsedSourceOffset;
    Id3v22RelativeVolumeChannelAdjustment[] channels;
    bool effectiveUnsynchronisation;
}

private ParseStatus
takeId3v22VolumeValue(
    ref Id3v22DataCursor cursor,
    ubyte bitsUsed,
    ref BigInt value,
    ref ByteSpan raw
)
    @safe
{
    assert(bitsUsed != 0);

    const byteCount =
        (cast(size_t) bitsUsed + 7) /
        8;

    const paddingBits =
        byteCount * 8 -
        cast(size_t) bitsUsed;

    auto probe =
        cursor;

    const start =
        probe.remainingRaw;

    BigInt decoded =
        BigInt(0);

    foreach (
        index;
        0 .. byteCount
    )
    {
        auto byteResult =
            probe.takeByte();

        if (byteResult.hasError)
        {
            return
                ParseStatus.failure(
                    byteResult.error
                );
        }

        const byteValue =
            byteResult.value.value;

        if (
            index == 0 &&
            paddingBits != 0
        )
        {
            const highPaddingMask =
                cast(ubyte)
                    (
                        0xFF <<
                        (8 - paddingBits)
                    );

            if (
                (
                    byteValue &
                    highPaddingMask
                ) !=
                0
            )
            {
                return
                    ParseStatus.failure(
                        ParseError(
                            ParseErrorCode.inconsistentStructure,
                            byteResult.value.sourceOffset
                        )
                    );
            }
        }

        decoded <<=
            8;

        decoded |=
            cast(uint)
                byteValue;
    }

    const physicalLength =
        start.length -
        probe.remainingRaw.length;

    value =
        decoded;

    raw =
        start.subspan(
            0,
            physicalLength
        );

    cursor =
        probe;

    return
        ParseStatus.success();
}

ParseResult!Id3v22RelativeVolumeFrame
decodeId3v22RelativeVolumeFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (frame.header.id[] != "RVA")
    {
        return
            ParseResult!Id3v22RelativeVolumeFrame
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

    auto directionResult =
        payload.takeByte();

    if (directionResult.hasError)
    {
        return
            ParseResult!Id3v22RelativeVolumeFrame
                .failure(
                    directionResult.error
                );
    }

    const directionByte =
        directionResult.value;

    if (
        (
            directionByte.value &
            0xFC
        ) !=
        0
    )
    {
        return
            ParseResult!Id3v22RelativeVolumeFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidFlags,
                        directionByte.sourceOffset
                    )
                );
    }

    auto bitsUsedResult =
        payload.takeByte();

    if (bitsUsedResult.hasError)
    {
        return
            ParseResult!Id3v22RelativeVolumeFrame
                .failure(
                    bitsUsedResult.error
                );
    }

    const bitsUsedByte =
        bitsUsedResult.value;

    if (bitsUsedByte.value == 0)
    {
        return
            ParseResult!Id3v22RelativeVolumeFrame
                .failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        bitsUsedByte.sourceOffset
                    )
                );
    }

    const bitsUsed =
        bitsUsedByte.value;

    BigInt rightChange =
        BigInt(0);

    ByteSpan rawRightChange =
        payload.remainingRaw.subspan(0, 0);

    auto rightChangeStatus =
        takeId3v22VolumeValue(
            payload,
            bitsUsed,
            rightChange,
            rawRightChange
        );

    if (rightChangeStatus.hasError)
    {
        return
            ParseResult!Id3v22RelativeVolumeFrame
                .failure(
                    rightChangeStatus.error
                );
    }

    BigInt leftChange =
        BigInt(0);

    ByteSpan rawLeftChange =
        payload.remainingRaw.subspan(0, 0);

    auto leftChangeStatus =
        takeId3v22VolumeValue(
            payload,
            bitsUsed,
            leftChange,
            rawLeftChange
        );

    if (leftChangeStatus.hasError)
    {
        return
            ParseResult!Id3v22RelativeVolumeFrame
                .failure(
                    leftChangeStatus.error
                );
    }

    bool hasPeaks =
        false;

    BigInt rightPeak =
        BigInt(0);

    BigInt leftPeak =
        BigInt(0);

    ByteSpan rawRightPeak =
        payload.remainingRaw.subspan(0, 0);

    ByteSpan rawLeftPeak =
        rawRightPeak;

    if (!payload.empty)
    {
        hasPeaks =
            true;

        auto rightPeakStatus =
            takeId3v22VolumeValue(
                payload,
                bitsUsed,
                rightPeak,
                rawRightPeak
            );

        if (rightPeakStatus.hasError)
        {
            return
                ParseResult!Id3v22RelativeVolumeFrame
                    .failure(
                        rightPeakStatus.error
                    );
        }

        auto leftPeakStatus =
            takeId3v22VolumeValue(
                payload,
                bitsUsed,
                leftPeak,
                rawLeftPeak
            );

        if (leftPeakStatus.hasError)
        {
            return
                ParseResult!Id3v22RelativeVolumeFrame
                    .failure(
                        leftPeakStatus.error
                    );
        }

        if (!payload.empty)
        {
            return
                ParseResult!Id3v22RelativeVolumeFrame
                    .failure(
                        ParseError(
                            ParseErrorCode.inconsistentStructure,
                            payload.absoluteOffset
                        )
                    );
        }
    }

    Id3v22RelativeVolumeChannelAdjustment[] channels;

    channels ~=
        Id3v22RelativeVolumeChannelAdjustment(
            Id3v22RelativeVolumeChannel.right,
            Id3v2LegacyVolumeChannelAdjustment(
                (
                    directionByte.value &
                    0x01
                ) !=
                    0,
                rightChange,
                hasPeaks,
                rightPeak
            ),
            rawRightChange,
            rawRightPeak
        );

    channels ~=
        Id3v22RelativeVolumeChannelAdjustment(
            Id3v22RelativeVolumeChannel.left,
            Id3v2LegacyVolumeChannelAdjustment(
                (
                    directionByte.value &
                    0x02
                ) !=
                    0,
                leftChange,
                hasPeaks,
                leftPeak
            ),
            rawLeftChange,
            rawLeftPeak
        );

    return
        ParseResult!Id3v22RelativeVolumeFrame
            .success(
                Id3v22RelativeVolumeFrame(
                    frame.header.sourceOffset,
                    directionByte.sourceOffset,
                    bitsUsed,
                    bitsUsedByte.sourceOffset,
                    channels,
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
            'R', 'V', 'A',
            0x00, 0x00, 0x06,

            0x01,
            16,

            0x01, 0x00,
            0x00, 0x20
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
            .decodeId3v22RelativeVolumeFrame();

    assert(result.hasValue);

    const volume =
        result.value;

    assert(volume.channels.length == 2);
    assert(volume.channels[0].channel == Id3v22RelativeVolumeChannel.right);
    assert(volume.channels[0].adjustment.increment);
    assert(volume.channels[0].adjustment.changeMagnitude == 256);
    assert(!volume.channels[0].adjustment.hasPeak);

    assert(volume.channels[1].channel == Id3v22RelativeVolumeChannel.left);
    assert(!volume.channels[1].adjustment.increment);
    assert(volume.channels[1].adjustment.changeMagnitude == 32);
    assert(!volume.channels[1].adjustment.hasPeak);
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'V', 'A',
            0x00, 0x00, 0x0A,

            0x02,
            16,

            0x00, 0x10,
            0x00, 0x20,

            0x12, 0x34,
            0x56, 0x78
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
            .decodeId3v22RelativeVolumeFrame();

    assert(result.hasValue);

    const volume =
        result.value;

    assert(!volume.channels[0].adjustment.increment);
    assert(volume.channels[1].adjustment.increment);
    assert(volume.channels[0].adjustment.hasPeak);
    assert(volume.channels[0].adjustment.peak == 0x12_34);
    assert(volume.channels[1].adjustment.hasPeak);
    assert(volume.channels[1].adjustment.peak == 0x56_78);
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'V', 'A',
            0x00, 0x00, 0x06,

            0x03,
            10,

            0x03, 0xFF,
            0x00, 0x01
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
            .decodeId3v22RelativeVolumeFrame();

    assert(result.hasValue);
    assert(result.value.channels[0].adjustment.changeMagnitude == 1023);
    assert(result.value.channels[1].adjustment.changeMagnitude == 1);
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'V', 'A',
            0x00, 0x00, 0x06,

            0x00,
            10,

            0x04, 0x00,
            0x00, 0x01
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
            .decodeId3v22RelativeVolumeFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.inconsistentStructure);
    assert(result.error.offset == 408);
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'V', 'A',
            0x00, 0x00, 0x02,
            0x00,
            0x00
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
            .decodeId3v22RelativeVolumeFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.inconsistentStructure);
    assert(result.error.offset == 507);
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'V', 'A',
            0x00, 0x00, 0x02,
            0x04,
            0x08
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
            .decodeId3v22RelativeVolumeFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidFlags);
    assert(result.error.offset == 606);
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'V', 'A',
            0x00, 0x00, 0x05,

            0x00,
            0x08,

            0x10,
            0x20,
            0x30
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
            .decodeId3v22RelativeVolumeFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'V', 'A',
            0x00, 0x00, 0x07,

            0x00,
            0x08,

            0x10,
            0x20,
            0x30,
            0x40,
            0x50
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
            .decodeId3v22RelativeVolumeFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.inconsistentStructure);
    assert(result.error.offset == 812);
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'V', 'A',
            0x00, 0x00, 0x14,

            0x03,
            65,

            0x01,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,

            0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x01
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
            .decodeId3v22RelativeVolumeFrame();

    assert(result.hasValue);

    auto expected =
        BigInt(1) <<
        64;

    assert(
        result.value.channels[0]
            .adjustment.changeMagnitude ==
        expected
    );

    assert(
        result.value.channels[1]
            .adjustment.changeMagnitude ==
        1
    );
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'V', 'A',
            0x00, 0x00, 0x06,

            0x03,
            16,

            0xFF, 0x00,
            0xE1,

            0x00, 0x02
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
    assert(frame.value.header.size == 6);
    assert(frame.value.data.length == 7);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22RelativeVolumeFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.effectiveUnsynchronisation);

    assert(
        result.value.channels[0]
            .adjustment.changeMagnitude ==
        0xFF_E1
    );

    assert(
        result.value.channels[0]
            .rawChangeMagnitude.data ==
        [
            0xFF, 0x00,
            0xE1
        ]
    );
}

unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x02,
            0x00,
            0x08
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1100
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22RelativeVolumeFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 1100);
}
