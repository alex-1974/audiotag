/++
ID3v2.2 MPEG-location-lookup-table (`MLL`) frame decoding.

The first ten logical payload bytes contain the reference intervals and the
two deviation bit widths. The remaining logical bits contain consecutive
byte- and millisecond-deviation values.

The specification gives both deviation widths as full bytes and does not
impose a 32- or 64-bit ceiling. This decoder therefore uses `BigInt` for the
decoded unsigned values.

Whole-tag unsynchronisation is reversed during logical traversal while
`rawReferenceData` retains the complete physical packed region.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.mpeg_location_lookup;

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

import audiotag.id3v2.common.mpeg_location_lookup :
    Id3v2MpegLocationLookupParameters,
    Id3v2MpegLocationLookupReference;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;


struct Id3v22MpegLocationLookupReference
{
    Id3v2MpegLocationLookupReference reference;
    size_t logicalBitOffset;
}


struct Id3v22MpegLocationLookupFrame
{
    size_t sourceOffset;
    Id3v2MpegLocationLookupParameters parameters;
    ByteSpan rawReferenceData;
    Id3v22MpegLocationLookupReference[] references;
    bool effectiveUnsynchronisation;
}


private struct Id3v22MpegLocationBitCursor
{
private:
    Id3v22DataCursor _data;
    ubyte _currentByte;
    ubyte _bitsRemaining;
    size_t _logicalBitPosition;

public:
    this(
        Id3v22DataCursor data
    )
        @safe pure nothrow @nogc
    {
        _data =
            data;

        _currentByte =
            0;

        _bitsRemaining =
            0;

        _logicalBitPosition =
            0;
    }

    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return
            _bitsRemaining == 0 &&
            _data.empty;
    }

    @property
    size_t logicalBitPosition() const
        @safe pure nothrow @nogc
    {
        return
            _logicalBitPosition;
    }

    ParseStatus
    takeUnsigned(
        size_t bitCount,
        ref BigInt value
    )
        @safe
    {
        auto probe =
            this;

        BigInt decoded =
            BigInt(0);

        foreach (
            index;
            0 .. bitCount
        )
        {
            if (
                probe._bitsRemaining ==
                0
            )
            {
                auto byteResult =
                    probe._data.takeByte();

                if (byteResult.hasError)
                {
                    return
                        ParseStatus.failure(
                            byteResult.error
                        );
                }

                probe._currentByte =
                    byteResult.value.value;

                probe._bitsRemaining =
                    8;
            }

            const shift =
                probe._bitsRemaining -
                1;

            const bit =
                cast(ubyte)
                    (
                        (
                            probe._currentByte >>
                            shift
                        ) &
                        0x01
                    );

            decoded <<=
                1;

            decoded |=
                cast(uint) bit;

            --probe._bitsRemaining;
            ++probe._logicalBitPosition;
        }

        value =
            decoded;

        this =
            probe;

        return
            ParseStatus.success();
    }
}


ParseResult!Id3v22MpegLocationLookupFrame
decodeId3v22MpegLocationLookupFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "MLL"
    )
    {
        return
            ParseResult!Id3v22MpegLocationLookupFrame
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

    auto framesResult =
        payload.takeU16BE();

    if (framesResult.hasError)
    {
        return
            ParseResult!Id3v22MpegLocationLookupFrame
                .failure(framesResult.error);
    }

    auto bytesResult =
        payload.takeU24BE();

    if (bytesResult.hasError)
    {
        return
            ParseResult!Id3v22MpegLocationLookupFrame
                .failure(bytesResult.error);
    }

    auto millisecondsResult =
        payload.takeU24BE();

    if (millisecondsResult.hasError)
    {
        return
            ParseResult!Id3v22MpegLocationLookupFrame
                .failure(millisecondsResult.error);
    }

    auto byteBitsResult =
        payload.takeByte();

    if (byteBitsResult.hasError)
    {
        return
            ParseResult!Id3v22MpegLocationLookupFrame
                .failure(byteBitsResult.error);
    }

    auto millisecondBitsResult =
        payload.takeByte();

    if (millisecondBitsResult.hasError)
    {
        return
            ParseResult!Id3v22MpegLocationLookupFrame
                .failure(millisecondBitsResult.error);
    }

    const byteBits =
        byteBitsResult.value.value;

    const millisecondBits =
        millisecondBitsResult.value.value;

    const bitsPerReference =
        cast(size_t) byteBits +
        cast(size_t) millisecondBits;

    if (
        bitsPerReference %
            4 !=
        0
    )
    {
        return
            ParseResult!Id3v22MpegLocationLookupFrame
                .failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        byteBitsResult.value.sourceOffset
                    )
                );
    }

    const parameters =
        Id3v2MpegLocationLookupParameters(
            framesResult.value,
            bytesResult.value,
            millisecondsResult.value,
            byteBits,
            millisecondBits
        );

    const rawReferenceData =
        payload.remainingRaw;

    Id3v22MpegLocationLookupReference[] references;

    if (
        bitsPerReference ==
        0
    )
    {
        if (!payload.empty)
        {
            return
                ParseResult!Id3v22MpegLocationLookupFrame
                    .failure(
                        ParseError(
                            ParseErrorCode.inconsistentStructure,
                            payload.absoluteOffset
                        )
                    );
        }

        return
            ParseResult!Id3v22MpegLocationLookupFrame
                .success(
                    Id3v22MpegLocationLookupFrame(
                        frame.header.sourceOffset,
                        parameters,
                        rawReferenceData,
                        references,
                        tagUnsynchronised
                    )
                );
    }

    auto bits =
        Id3v22MpegLocationBitCursor(
            payload
        );

    while (!bits.empty)
    {
        const logicalBitOffset =
            bits.logicalBitPosition;

        BigInt byteDeviation =
            BigInt(0);

        auto byteDeviationStatus =
            bits.takeUnsigned(
                byteBits,
                byteDeviation
            );

        if (byteDeviationStatus.hasError)
        {
            return
                ParseResult!Id3v22MpegLocationLookupFrame
                    .failure(
                        byteDeviationStatus.error
                    );
        }

        BigInt millisecondDeviation =
            BigInt(0);

        auto millisecondDeviationStatus =
            bits.takeUnsigned(
                millisecondBits,
                millisecondDeviation
            );

        if (millisecondDeviationStatus.hasError)
        {
            return
                ParseResult!Id3v22MpegLocationLookupFrame
                    .failure(
                        millisecondDeviationStatus.error
                    );
        }

        references ~=
            Id3v22MpegLocationLookupReference(
                Id3v2MpegLocationLookupReference(
                    byteDeviation,
                    millisecondDeviation
                ),
                logicalBitOffset
            );
    }

    return
        ParseResult!Id3v22MpegLocationLookupFrame
            .success(
                Id3v22MpegLocationLookupFrame(
                    frame.header.sourceOffset,
                    parameters,
                    rawReferenceData,
                    references,
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


/// Nibble-sized deviations decode consecutive references MSB first.
unittest
{
    const ubyte[] bytes =
        [
            'M', 'L', 'L',
            0x00, 0x00, 0x0C,

            0x00, 0x02,
            0x00, 0x03, 0xE8,
            0x00, 0x00, 0x1A,
            0x04,
            0x04,

            0xAB,
            0x12
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
            .decodeId3v22MpegLocationLookupFrame();

    assert(result.hasValue);

    const lookup =
        result.value;

    assert(lookup.parameters.mpegFramesBetweenReference == 2);
    assert(lookup.parameters.bytesBetweenReference == 1000);
    assert(lookup.parameters.millisecondsBetweenReference == 26);
    assert(lookup.references.length == 2);

    assert(
        lookup.references[0]
            .reference.bytesDeviation ==
        10
    );

    assert(
        lookup.references[0]
            .reference.millisecondsDeviation ==
        11
    );

    assert(lookup.references[0].logicalBitOffset == 0);

    assert(
        lookup.references[1]
            .reference.bytesDeviation ==
        1
    );

    assert(
        lookup.references[1]
            .reference.millisecondsDeviation ==
        2
    );

    assert(lookup.references[1].logicalBitOffset == 8);
    assert(lookup.rawReferenceData.data == [0xAB, 0x12]);
}


/// Wide deviation fields are not truncated to machine integers.
unittest
{
    const ubyte[] bytes =
        [
            'M', 'L', 'L',
            0x00, 0x00, 0x13,

            0x00, 0x01,
            0x00, 0x00, 0x01,
            0x00, 0x00, 0x01,
            68,
            4,

            0xFF, 0xFF, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF, 0xFF,
            0xFA
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
            .decodeId3v22MpegLocationLookupFrame();

    assert(result.hasValue);
    assert(result.value.references.length == 1);

    auto expected =
        (
            BigInt(1) <<
            68
        ) -
        1;

    assert(
        result.value.references[0]
            .reference.bytesDeviation ==
        expected
    );

    assert(
        result.value.references[0]
            .reference.millisecondsDeviation ==
        10
    );
}


/// Combined deviation width must be a multiple of four.
unittest
{
    const ubyte[] bytes =
        [
            'M', 'L', 'L',
            0x00, 0x00, 0x0A,

            0x00, 0x01,
            0x00, 0x00, 0x01,
            0x00, 0x00, 0x01,
            3,
            2
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
            .decodeId3v22MpegLocationLookupFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.inconsistentStructure);
    assert(result.error.offset == 314);
}


/// Header-only zero-width data remains representable as zero references.
unittest
{
    const ubyte[] bytes =
        [
            'M', 'L', 'L',
            0x00, 0x00, 0x0A,

            0x00, 0x01,
            0x00, 0x00, 0x01,
            0x00, 0x00, 0x01,
            0,
            0
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
            .decodeId3v22MpegLocationLookupFrame();

    assert(result.hasValue);
    assert(result.value.references.length == 0);
    assert(result.value.rawReferenceData.empty);
}


/// Zero-width references cannot coexist with packed data.
unittest
{
    const ubyte[] bytes =
        [
            'M', 'L', 'L',
            0x00, 0x00, 0x0B,

            0x00, 0x01,
            0x00, 0x00, 0x01,
            0x00, 0x00, 0x01,
            0,
            0,

            0xAA
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
            .decodeId3v22MpegLocationLookupFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.inconsistentStructure);
    assert(result.error.offset == 516);
}


/// A partial final packed reference is rejected.
unittest
{
    const ubyte[] bytes =
        [
            'M', 'L', 'L',
            0x00, 0x00, 0x0B,

            0x00, 0x01,
            0x00, 0x00, 0x01,
            0x00, 0x00, 0x01,
            8,
            8,

            0xAA
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
            .decodeId3v22MpegLocationLookupFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
}


/// MLL rejects another frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'T', 'C',
            0x00, 0x00, 0x0A,

            0x00, 0x01,
            0x00, 0x00, 0x01,
            0x00, 0x00, 0x01,
            4,
            4
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
            .decodeId3v22MpegLocationLookupFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 700);
}


/// Whole-tag unsynchronisation is removed logically but retained physically.
unittest
{
    const ubyte[] bytes =
        [
            'M', 'L', 'L',
            0x00, 0x00, 0x0C,

            0x00, 0x01,
            0x00, 0x00, 0x01,
            0x00, 0x00, 0x01,
            8,
            8,

            0xFF, 0x00,
            0xE1
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                800
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 12);
    assert(frame.value.data.length == 13);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22MpegLocationLookupFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.effectiveUnsynchronisation);
    assert(result.value.references.length == 1);

    assert(
        result.value.references[0]
            .reference.bytesDeviation ==
        255
    );

    assert(
        result.value.references[0]
            .reference.millisecondsDeviation ==
        225
    );

    assert(
        result.value.rawReferenceData.data ==
        [
            0xFF, 0x00,
            0xE1
        ]
    );
}
