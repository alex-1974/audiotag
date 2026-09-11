/++
ID3v2.2 equalisation (`EQU`) frame decoding.

An `EQU` frame begins with one non-zero `adjustment bits` byte. The remainder
contains zero or more equalisation bands. Each band stores one 16-bit
big-endian frequency word and one unsigned adjustment magnitude.

The frequency word uses its MSB as the increment/decrement flag; the lower
15 bits are the frequency in whole hertz. Adjustment values occupy whole
bytes and are padded at the most-significant end when needed.

The specification says bands should be ordered by increasing frequency and a
frequency should occur only once. This native decoder preserves source order
and duplicates rather than enforcing recommendation-level constraints.

Whole-tag unsynchronisation is reversed during logical traversal. Raw frequency
and adjustment spans retain exact physical source representation.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.equalisation;

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

import audiotag.id3v2.common.equalisation :
    Id3v2LegacyEqualisationBand;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

struct Id3v22EqualisationBand
{
    Id3v2LegacyEqualisationBand band;
    ByteSpan rawFrequencyWord;
    ByteSpan rawAdjustment;
}

struct Id3v22EqualisationFrame
{
    size_t sourceOffset;
    ubyte adjustmentBits;
    size_t adjustmentBitsSourceOffset;
    Id3v22EqualisationBand[] bands;
    bool effectiveUnsynchronisation;
}

private ParseStatus
takeId3v22EqualisationAdjustment(
    ref Id3v22DataCursor cursor,
    ubyte bitsUsed,
    ref BigInt value,
    ref ByteSpan raw
)
    @safe
{
    assert(bitsUsed != 0);

    const byteCount =
        (
            cast(size_t) bitsUsed +
            7
        ) /
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
                        (
                            8 -
                            paddingBits
                        )
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

ParseResult!Id3v22EqualisationFrame
decodeId3v22EqualisationFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "EQU"
    )
    {
        return
            ParseResult!Id3v22EqualisationFrame
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

    auto adjustmentBitsResult =
        payload.takeByte();

    if (adjustmentBitsResult.hasError)
    {
        return
            ParseResult!Id3v22EqualisationFrame
                .failure(
                    adjustmentBitsResult.error
                );
    }

    const adjustmentBitsByte =
        adjustmentBitsResult.value;

    if (
        adjustmentBitsByte.value ==
        0
    )
    {
        return
            ParseResult!Id3v22EqualisationFrame
                .failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        adjustmentBitsByte.sourceOffset
                    )
                );
    }

    const adjustmentBits =
        adjustmentBitsByte.value;

    Id3v22EqualisationBand[] bands;

    while (!payload.empty)
    {
        const frequencyStart =
            payload.remainingRaw;

        auto frequencyResult =
            payload.takeU16BE();

        if (frequencyResult.hasError)
        {
            return
                ParseResult!Id3v22EqualisationFrame
                    .failure(
                        frequencyResult.error
                    );
        }

        const frequencyPhysicalLength =
            frequencyStart.length -
            payload.remainingRaw.length;

        const rawFrequencyWord =
            frequencyStart.subspan(
                0,
                frequencyPhysicalLength
            );

        const frequencyWord =
            frequencyResult.value;

        const increment =
            (
                frequencyWord &
                0x8000
            ) !=
            0;

        const frequencyHz =
            cast(ushort)
                (
                    frequencyWord &
                    0x7FFF
                );

        BigInt adjustmentMagnitude =
            BigInt(0);

        ByteSpan rawAdjustment =
            payload.remainingRaw.subspan(
                0,
                0
            );

        auto adjustmentStatus =
            takeId3v22EqualisationAdjustment(
                payload,
                adjustmentBits,
                adjustmentMagnitude,
                rawAdjustment
            );

        if (adjustmentStatus.hasError)
        {
            return
                ParseResult!Id3v22EqualisationFrame
                    .failure(
                        adjustmentStatus.error
                    );
        }

        bands ~=
            Id3v22EqualisationBand(
                Id3v2LegacyEqualisationBand(
                    increment,
                    frequencyHz,
                    adjustmentMagnitude
                ),
                rawFrequencyWord,
                rawAdjustment
            );
    }

    return
        ParseResult!Id3v22EqualisationFrame
            .success(
                Id3v22EqualisationFrame(
                    frame.header.sourceOffset,
                    adjustmentBits,
                    adjustmentBitsByte.sourceOffset,
                    bands,
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
            'E', 'Q', 'U',
            0x00, 0x00, 0x09,

            16,

            0x83, 0xE8,
            0x01, 0x00,

            0x07, 0xD0,
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
            .decodeId3v22EqualisationFrame();

    assert(result.hasValue);

    const equalisation =
        result.value;

    assert(equalisation.adjustmentBits == 16);
    assert(equalisation.bands.length == 2);

    assert(equalisation.bands[0].band.increment);
    assert(equalisation.bands[0].band.frequencyHz == 1000);
    assert(equalisation.bands[0].band.adjustmentMagnitude == 256);

    assert(!equalisation.bands[1].band.increment);
    assert(equalisation.bands[1].band.frequencyHz == 2000);
    assert(equalisation.bands[1].band.adjustmentMagnitude == 32);
}

unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x07,

            8,

            0x07, 0xD0,
            0x10,

            0x03, 0xE8,
            0x20
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
            .decodeId3v22EqualisationFrame();

    assert(result.hasValue);
    assert(result.value.bands[0].band.frequencyHz == 2000);
    assert(result.value.bands[1].band.frequencyHz == 1000);
}

unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x05,

            10,

            0x81, 0xF4,
            0x03, 0xFF
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
            .decodeId3v22EqualisationFrame();

    assert(result.hasValue);
    assert(result.value.bands[0].band.increment);
    assert(result.value.bands[0].band.frequencyHz == 500);
    assert(result.value.bands[0].band.adjustmentMagnitude == 1023);
}

unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x05,

            10,

            0x01, 0xF4,
            0x04, 0x00
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
            .decodeId3v22EqualisationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.inconsistentStructure);
    assert(result.error.offset == 409);
}

unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x01,
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
            .decodeId3v22EqualisationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.inconsistentStructure);
    assert(result.error.offset == 506);
}

unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x01,
            16
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
            .decodeId3v22EqualisationFrame();

    assert(result.hasValue);
    assert(result.value.bands.length == 0);
}

unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x02,
            8,
            0x12
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
            .decodeId3v22EqualisationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
}

unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x04,
            16,
            0x03, 0xE8,
            0x12
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
            .decodeId3v22EqualisationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
}

unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x0C,

            65,
            0x03, 0xE8,

            0x01,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00
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
            .decodeId3v22EqualisationFrame();

    assert(result.hasValue);

    auto expected =
        BigInt(1) <<
        64;

    assert(
        result.value.bands[0]
            .band.adjustmentMagnitude ==
        expected
    );
}

unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x05,

            16,

            0xFF, 0x00,
            0xE1,

            0xFF, 0x00,
            0xE2
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
    assert(frame.value.header.size == 5);
    assert(frame.value.data.length == 7);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22EqualisationFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.effectiveUnsynchronisation);
    assert(result.value.bands.length == 1);

    const band =
        result.value.bands[0];

    assert(band.band.increment);
    assert(band.band.frequencyHz == 0x7FE1);
    assert(band.band.adjustmentMagnitude == 0xFF_E2);

    assert(
        band.rawFrequencyWord.data ==
        [
            0xFF, 0x00,
            0xE1
        ]
    );

    assert(
        band.rawAdjustment.data ==
        [
            0xFF, 0x00,
            0xE2
        ]
    );
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'V', 'A',
            0x00, 0x00, 0x01,
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
            .decodeId3v22EqualisationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 1100);
}
