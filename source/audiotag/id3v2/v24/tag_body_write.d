/++
Physical serialization of a planned ID3v2.4 tag body.

This module materializes an already validated `Id3v24TagBodyWritePlan`.

The resulting body consists of:

1. the optional original extended-header bytes;
2. the already serialized complete frame sequence;
3. the planned number of zero padding bytes.

No new policy decisions are made here.

The fixed ten-byte ID3 header and optional ten-byte footer are not part
of this output.
+/
module audiotag.id3v2.v24.tag_body_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v24.structure :
    Id3v24TagStructure;

import audiotag.id3v2.v24.tag_body_write_policy :
    Id3v24ExtendedHeaderWriteAction,
    Id3v24TagBodyWritePlan;


/++
Serializes one planned ID3v2.4 tag body.

The caller supplies the frame sequence bytes whose length was used while
constructing `plan`.

The function verifies that the supplied plan still matches the source
structure and frame-sequence length before producing output.

Params:
    source = Strictly validated source tag structure.
    plan = Previously constructed body write plan.
    frameSequence = Complete serialized resulting native frame sequence.

Returns:
    Owned tag-body bytes or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeId3v24TagBody(
    const(Id3v24TagStructure) source,
    const(Id3v24TagBodyWritePlan) plan,
    const(ubyte)[] frameSequence
)
    @safe
{
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

    if (
        plan.footerPresent !=
        source.envelope.header.hasFooter
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        0,
                        plan.footerPresent ? 1 : 0,
                        source.envelope.header.hasFooter
                            ? 1
                            : 0
                    )
                );
    }

    final switch (plan.extendedHeaderAction)
    {
        case Id3v24ExtendedHeaderWriteAction.absent:
        {
            if (
                source.body.hasExtendedHeader ||
                plan.extendedHeaderLength != 0
            )
            {
                return
                    SerializationResult!(ubyte[])
                        .failure(
                            SerializationError(
                                SerializationErrorCode
                                    .inconsistentStructure,
                                0,
                                plan.extendedHeaderLength
                            )
                        );
            }

            break;
        }

        case Id3v24ExtendedHeaderWriteAction.preserveOriginal:
        {
            if (!source.body.hasExtendedHeader)
            {
                return
                    SerializationResult!(ubyte[])
                        .failure(
                            SerializationError(
                                SerializationErrorCode
                                    .inconsistentStructure
                            )
                        );
            }

            if (
                source.body.extendedHeader.raw.length !=
                plan.extendedHeaderLength
            )
            {
                return
                    SerializationResult!(ubyte[])
                        .failure(
                            SerializationError(
                                SerializationErrorCode
                                    .inconsistentStructure,
                                0,
                                source.body
                                    .extendedHeader
                                    .raw
                                    .length,
                                plan.extendedHeaderLength
                            )
                        );
            }

            break;
        }
    }

    /*
     * Use a wider arithmetic domain while validating externally supplied
     * plan values.
     */
    const ulong totalLength =
        cast(ulong) plan.extendedHeaderLength +
        cast(ulong) plan.frameSequenceLength +
        cast(ulong) plan.paddingLength;

    if (
        totalLength !=
        cast(ulong) plan.tagSize
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
                        plan.tagSize
                    )
                );
    }

    auto output =
        new ubyte[
            cast(size_t)
                totalLength
        ];

    size_t position;

    if (
        plan.extendedHeaderAction ==
        Id3v24ExtendedHeaderWriteAction
            .preserveOriginal
    )
    {
        const raw =
            source.body
                .extendedHeader
                .raw
                .data;

        output[
            position ..
            position + raw.length
        ] =
            raw;

        position +=
            raw.length;
    }

    output[
        position ..
        position + frameSequence.length
    ] =
        frameSequence;

    position +=
        frameSequence.length;

    /*
     * Newly allocated dynamic arrays are zero-initialized. The remaining
     * planned region therefore already contains exact ID3 padding bytes.
     */
    position +=
        plan.paddingLength;

    assert(position == output.length);

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

    import audiotag.id3v2.v24.structure :
        parseId3v24TagStructure;

    import audiotag.id3v2.v24.tag_body_write_policy :
        planId3v24TagBodyWrite;


    private Id3v24TagStructure parseTestTag(
        const(ubyte)[] bytes
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto parsed =
            cursor.parseId3v24TagStructure();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }
}


/// Frame growth consumes existing padding while preserving body capacity.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            // Body size = 20.
            0x00, 0x00, 0x00, 0x14,

            // Existing eleven-byte frame.
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            // Nine bytes padding.
            0x00, 0x00, 0x00,
            0x00, 0x00, 0x00,
            0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    /*
     * Fifteen-byte regenerated/new frame:
     * header 10 + data 5.
     */
    const ubyte[] frameSequence =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            0x03,
            'T', 'e', 's', 't'
        ];

    const plan =
        planId3v24TagBodyWrite(
            source,
            frameSequence.length,
            true
        );

    assert(plan.writable);
    assert(plan.paddingLength == 5);
    assert(plan.tagSize == 20);

    auto serialized =
        serializeId3v24TagBody(
            source,
            plan,
            frameSequence
        );

    assert(serialized.hasValue);
    assert(serialized.value.length == 20);

    assert(
        serialized.value[
            0 ..
            frameSequence.length
        ] ==
        frameSequence
    );

    foreach (
        value;
        serialized.value[
            frameSequence.length ..
            $
        ]
    )
    {
        assert(value == 0);
    }
}


/// A preserved extended header remains the first exact body bytes.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,

            // 6 extended + 11 frame + 3 padding = 20.
            0x00, 0x00, 0x00, 0x14,

            0x00, 0x00, 0x00, 0x06,
            0x01,
            0x00,

            'T', 'A', 'L', 'B',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    const ubyte[] frameSequence =
        [
            'T', 'A', 'L', 'B',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x03, 'X'
        ];

    const plan =
        planId3v24TagBodyWrite(
            source,
            frameSequence.length,
            true
        );

    assert(plan.writable);

    assert(plan.extendedHeaderLength == 6);
    assert(plan.paddingLength == 2);
    assert(plan.tagSize == 20);

    auto serialized =
        serializeId3v24TagBody(
            source,
            plan,
            frameSequence
        );

    assert(serialized.hasValue);

    assert(
        serialized.value[0 .. 6] ==
        source.body
            .extendedHeader
            .raw
            .data
    );

    assert(
        serialized.value[
            6 ..
            6 + frameSequence.length
        ] ==
        frameSequence
    );

    assert(
        serialized.value[$ - 2 .. $] ==
        [0x00, 0x00]
    );
}


/// An unchanged CRC-bearing body can be reproduced byte-for-byte.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,

            // Extended header 12 + frame 11 = 23.
            0x00, 0x00, 0x00, 0x17,

            0x00, 0x00, 0x00, 0x0C,
            0x01,
            0x20,
            0x05,
            0x00, 0x00, 0x00, 0x00, 0x01,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const source =
        parseTestTag(sourceBytes);

    const frameSequence =
        source.frames.frameBytes.data;

    const plan =
        planId3v24TagBodyWrite(
            source,
            frameSequence.length,
            false
        );

    assert(plan.writable);

    auto serialized =
        serializeId3v24TagBody(
            source,
            plan,
            frameSequence
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        source.envelope.body.data
    );
}


/// A stale CRC plan never reaches physical body output.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,

            0x00, 0x00, 0x00, 0x17,

            0x00, 0x00, 0x00, 0x0C,
            0x01,
            0x20,
            0x05,
            0x00, 0x00, 0x00, 0x00, 0x01,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const source =
        parseTestTag(sourceBytes);

    const ubyte[] frameSequence =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x03, 'X'
        ];

    const plan =
        planId3v24TagBodyWrite(
            source,
            frameSequence.length,
            true
        );

    assert(!plan.writable);
    assert(plan.crcBlocksChange);

    auto serialized =
        serializeId3v24TagBody(
            source,
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


/// Footer-bearing tags produce no body padding.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x10,

            0x00, 0x00, 0x00, 0x0B,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            '3', 'D', 'I',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x0B
        ];

    const source =
        parseTestTag(sourceBytes);

    const ubyte[] frameSequence =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,
            0x03, 'N', 'e', 'w'
        ];

    const plan =
        planId3v24TagBodyWrite(
            source,
            frameSequence.length,
            true
        );

    assert(plan.writable);
    assert(plan.footerPresent);
    assert(plan.paddingLength == 0);
    assert(plan.tagSize == frameSequence.length);

    auto serialized =
        serializeId3v24TagBody(
            source,
            plan,
            frameSequence
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        frameSequence
    );
}


/// A frame sequence that does not match its plan is rejected.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x0B,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const source =
        parseTestTag(sourceBytes);

    const plan =
        planId3v24TagBodyWrite(
            source,
            11,
            false
        );

    assert(plan.writable);

    const ubyte[] wrongFrameSequence =
        [0x01, 0x02];

    auto serialized =
        serializeId3v24TagBody(
            source,
            plan,
            wrongFrameSequence
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );
}
