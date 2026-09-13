/++
Logical serialization of a planned ID3v2.2 tag body.

This module materializes an already validated `Id3v22TagBodyWritePlan`.

The resulting logical body consists of:

1. the already serialized complete frame sequence;
2. the planned number of zero padding bytes.

No new preservation or capacity policy decisions are made here.

The fixed ten-byte ID3 tag header is not part of this output.

ID3v2.2 whole-tag unsynchronisation is deliberately not applied here. The
complete logical body produced by this module is the input to the later outer
unsynchronisation step. Physical source stuffing must therefore never appear in
`frameSequence`.

Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-13
+/
module audiotag.id3v2.v22.tag_body_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v22.tag_body_write_policy :
    Id3v22TagBodyWritePlan;


/++
Serializes one planned logical ID3v2.2 tag body.

The caller supplies the complete logical/native frame-sequence bytes whose
length was used when constructing `plan`.

The function defensively verifies that:

- the plan is writable;
- the supplied frame sequence length matches the plan;
- `logicalBodyLength` equals frame bytes plus padding;
- the resulting logical body remains inside the 28-bit ID3 tag-size domain.

No whole-tag unsynchronisation is applied here.

Params:
    plan = Previously constructed ID3v2.2 body write plan.
    frameSequence = Complete serialized logical/native frame sequence.

Returns:
    Owned logical ID3v2.2 body bytes before whole-tag unsynchronisation, or a
    structured serialization failure.

Safety:
    The returned array owns its bytes and retains no view into
    `frameSequence`.

Complexity:
    O(n) time and O(n) output space.
+/
SerializationResult!(ubyte[])
serializeId3v22TagBody(
    const(Id3v22TagBodyWritePlan) plan,
    const(ubyte)[] frameSequence
)
    @safe
{
    enum ulong maximumTagSize =
        0x0FFF_FFFF;

    if (!plan.writable)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation
                    )
                );
    }

    if (
        frameSequence.length !=
        plan.frameSequenceLength
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        0,
                        frameSequence.length,
                        plan.frameSequenceLength
                    )
                );
    }

    /*
     * Validate externally supplied plan arithmetic in a wider domain before
     * allocating. This also prevents size_t wraparound from turning a forged
     * plan into a smaller allocation.
     */
    const ulong totalLength =
        cast(ulong)
            plan.frameSequenceLength +
        cast(ulong)
            plan.paddingLength;

    if (
        totalLength !=
        cast(ulong)
            plan.logicalBodyLength
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        0,
                        totalLength,
                        plan.logicalBodyLength
                    )
                );
    }

    if (
        totalLength >
        maximumTagSize
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        0,
                        totalLength,
                        maximumTagSize
                    )
                );
    }

    auto output =
        new ubyte[
            cast(size_t)
                totalLength
        ];

    output[
        0 ..
        frameSequence.length
    ] =
        frameSequence;

    /*
     * D dynamic arrays are zero-initialized, so the remaining region already
     * contains exact ID3v2.2 logical padding bytes.
     */
    foreach (
        value;
        output[
            frameSequence.length ..
            $
        ]
    )
    {
        assert(value == 0);
    }

    return
        SerializationResult!(ubyte[])
            .success(output);
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.data_cursor :
        Id3v22DataCursor;

    import audiotag.id3v2.v22.structure :
        Id3v22TagStructure,
        parseId3v22TagStructure;

    import audiotag.id3v2.v22.tag_body_write_policy :
        Id3v22TagBodyWriteStatus,
        planId3v22TagBodyWrite;


    private Id3v22TagStructure
    parseTestTag(
        const(ubyte)[] bytes
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto parsed =
            cursor.parseId3v22TagStructure();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return
            parsed.value;
    }
}


/// Frame growth consumes old padding while retaining logical body capacity.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            // Body size = 11.
            0x00, 0x00, 0x00, 0x0B,

            // Seven-byte source frame.
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55,

            // Four padding bytes.
            0x00, 0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    const ubyte[] frameSequence =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x03,
            0x11, 0x22, 0x33
        ];

    const plan =
        planId3v22TagBodyWrite(
            source,
            frameSequence.length
        );

    assert(plan.writable);
    assert(plan.paddingLength == 2);
    assert(plan.logicalBodyLength == 11);

    auto serialized =
        serializeId3v22TagBody(
            plan,
            frameSequence
        );

    assert(serialized.hasValue);
    assert(serialized.value.length == 11);

    assert(
        serialized.value[
            0 ..
            frameSequence.length
        ] ==
        frameSequence
    );

    assert(
        serialized.value[
            frameSequence.length ..
            $
        ] ==
        [0x00, 0x00]
    );
}


/// Growth beyond old capacity emits no padding and expands the logical body.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x07,

            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55
        ];

    const source =
        parseTestTag(sourceBytes);

    const ubyte[] frameSequence =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x05,
            0x10, 0x20, 0x30, 0x40, 0x50
        ];

    const plan =
        planId3v22TagBodyWrite(
            source,
            frameSequence.length
        );

    assert(plan.writable);
    assert(plan.paddingLength == 0);
    assert(
        plan.logicalBodyLength ==
        frameSequence.length
    );

    auto serialized =
        serializeId3v22TagBody(
            plan,
            frameSequence
        );

    assert(serialized.hasValue);
    assert(serialized.value == frameSequence);
}


/// An unsynchronised source is still serialized in the logical byte domain.
unittest
{
    /*
     * Source logical payload is 11 FF E1 and is stored physically as
     * 11 FF 00 E1.
     */
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x80,

            // Physical body size = 12.
            0x00, 0x00, 0x00, 0x0C,

            'T', 'T', '2',
            0x00, 0x00, 0x03,

            0x11,
            0xFF, 0x00, 0xE1,

            0x00, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    /*
     * New logical frame data deliberately contains a false-sync sequence.
     * This module must not stuff it; the outer unsync writer does that later.
     */
    const ubyte[] frameSequence =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x03,
            0x22,
            0xFF, 0xE1
        ];

    const plan =
        planId3v22TagBodyWrite(
            source,
            frameSequence.length
        );

    assert(plan.writable);
    assert(plan.paddingLength == 2);
    assert(plan.logicalBodyLength == 11);

    auto serialized =
        serializeId3v22TagBody(
            plan,
            frameSequence
        );

    assert(serialized.hasValue);

    assert(
        serialized.value[
            0 ..
            frameSequence.length
        ] ==
        frameSequence
    );

    /*
     * No physical stuffing zero has been inserted between FF and E1.
     */
    assert(
        serialized.value[
            frameSequence.length - 2
        ] ==
        0xFF
    );

    assert(
        serialized.value[
            frameSequence.length - 1
        ] ==
        0xE1
    );

    assert(
        serialized.value[
            frameSequence.length ..
            $
        ] ==
        [0x00, 0x00]
    );
}


/// The logical body can be traversed directly without unsync decoding.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x09,

            'T', 'A', 'L',
            0x00, 0x00, 0x01,
            0x55,

            0x00, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    const ubyte[] frameSequence =
        [
            'T', 'A', 'L',
            0x00, 0x00, 0x01,
            0x66
        ];

    const plan =
        planId3v22TagBodyWrite(
            source,
            frameSequence.length
        );

    auto serialized =
        serializeId3v22TagBody(
            plan,
            frameSequence
        );

    assert(serialized.hasValue);

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                serialized.value[],
                700
            ),
            false
        );

    foreach (
        expected;
        serialized.value
    )
    {
        auto decoded =
            cursor.takeByte();

        assert(decoded.hasValue);
        assert(decoded.value.value == expected);
    }

    assert(cursor.empty);
}


/// A non-writable plan is rejected without allocation.
unittest
{
    const plan =
        Id3v22TagBodyWritePlan(
            Id3v22TagBodyWriteStatus
                .compressedOpaqueSource,
            7,
            0,
            0
        );

    const ubyte[] frameSequence =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55
        ];

    auto serialized =
        serializeId3v22TagBody(
            plan,
            frameSequence
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// A frame-sequence length mismatch is reported explicitly.
unittest
{
    const plan =
        Id3v22TagBodyWritePlan(
            Id3v22TagBodyWriteStatus.ready,
            8,
            2,
            10
        );

    const ubyte[] frameSequence =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55
        ];

    auto serialized =
        serializeId3v22TagBody(
            plan,
            frameSequence
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );

    assert(serialized.error.index == 0);
    assert(serialized.error.value == 7);
    assert(serialized.error.limit == 8);
}


/// Forged plan arithmetic is rejected before allocation.
unittest
{
    const plan =
        Id3v22TagBodyWritePlan(
            Id3v22TagBodyWriteStatus.ready,
            7,
            3,
            99
        );

    const ubyte[] frameSequence =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55
        ];

    auto serialized =
        serializeId3v22TagBody(
            plan,
            frameSequence
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );

    assert(serialized.error.value == 10);
    assert(serialized.error.limit == 99);
}


/// A forged ready plan beyond the 28-bit domain is rejected before allocation.
unittest
{
    const plan =
        Id3v22TagBodyWritePlan(
            Id3v22TagBodyWriteStatus.ready,
            1,
            0x0FFF_FFFF,
            0x1000_0000
        );

    const ubyte[] frameSequence =
        [0x01];

    auto serialized =
        serializeId3v22TagBody(
            plan,
            frameSequence
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .valueOutOfRange
    );

    assert(serialized.error.index == 0);

    assert(
        serialized.error.value ==
        0x1000_0000
    );

    assert(
        serialized.error.limit ==
        0x0FFF_FFFF
    );
}
