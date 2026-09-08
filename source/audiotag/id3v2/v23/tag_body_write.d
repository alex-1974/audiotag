/++
Physical serialization of a planned ID3v2.3 tag body.

This module materializes an already validated `Id3v23TagBodyWritePlan`.

The resulting body consists of:

1. the optional extended header;
2. the already serialized complete frame sequence;
3. the planned number of zero padding bytes.

For an existing extended header the body policy decides whether the
original bytes remain valid or whether the structure must be regenerated
with a new padding-size value.

No new policy decisions are made here.

The fixed ten-byte ID3 tag header is not part of this output.

ID3v2.3 whole-tag unsynchronisation is likewise not applied here. The
current body policy rejects such output before serialization reaches
this layer.
+/
module audiotag.id3v2.v23.tag_body_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.extended_header_write :
    serializeRegeneratedId3v23ExtendedHeader;

import audiotag.id3v2.v23.structure :
    Id3v23TagStructure;

import audiotag.id3v2.v23.tag_body_write_policy :
    Id3v23ExtendedHeaderWriteAction,
    Id3v23TagBodyWritePlan;


/++
Serializes one planned ID3v2.3 tag body.

The caller supplies the complete frame-sequence bytes whose length was
used when constructing `plan`.

The function verifies that the supplied plan still agrees with the
source structure and frame-sequence length before producing output.

Params:
    source = Strictly validated source ID3v2.3 tag structure.
    plan = Previously constructed body write plan.
    frameSequence = Complete serialized resulting native frame sequence.

Returns:
    Owned ordinary ID3v2.3 tag-body bytes or a structured serialization
    failure.
+/
SerializationResult!(ubyte[])
serializeId3v23TagBody(
    const(Id3v23TagStructure) source,
    const(Id3v23TagBodyWritePlan) plan,
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

    /*
     * Whole-tag-unsynchronised source structures must have been blocked
     * by the body policy.
     */
    if (
        source.envelope.header
            .unsynchronisation
    )
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

    ubyte[] extendedHeaderBytes;

    final switch (plan.extendedHeaderAction)
    {
        case Id3v23ExtendedHeaderWriteAction
            .absent:
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

        case Id3v23ExtendedHeaderWriteAction
            .preserveOriginal:
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

            const raw =
                source.body
                    .extendedHeader
                    .raw
                    .data;

            if (
                raw.length !=
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
                                raw.length,
                                plan.extendedHeaderLength
                            )
                        );
            }

            /*
             * Copy into owned temporary storage so all three actions
             * present the same locally owned representation below.
             */
            extendedHeaderBytes =
                raw.dup;

            break;
        }

        case Id3v23ExtendedHeaderWriteAction
            .regenerate:
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

            /*
             * `plan.tagSize` is bounded to 28 bits, therefore the
             * resulting padding length necessarily fits in uint.
             */
            auto regenerated =
                serializeRegeneratedId3v23ExtendedHeader(
                    source.body.extendedHeader,
                    cast(uint)
                        plan.paddingLength
                );

            if (regenerated.hasError)
            {
                return
                    SerializationResult!(ubyte[])
                        .failure(
                            regenerated.error
                        );
            }

            if (
                regenerated.value.length !=
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
                                regenerated.value.length,
                                plan.extendedHeaderLength
                            )
                        );
            }

            extendedHeaderBytes =
                regenerated.value.dup;

            break;
        }
    }

    /*
     * Validate externally supplied plan arithmetic in a wider domain
     * before allocating.
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

    if (extendedHeaderBytes.length != 0)
    {
        output[
            position ..
            position + extendedHeaderBytes.length
        ] =
            extendedHeaderBytes;

        position +=
            extendedHeaderBytes.length;
    }

    output[
        position ..
        position + frameSequence.length
    ] =
        frameSequence;

    position +=
        frameSequence.length;

    /*
     * Dynamic arrays are zero-initialized. The remaining planned region
     * therefore already contains exact ID3v2.3 padding bytes.
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

    import audiotag.id3v2.v23.data_cursor :
        Id3v23DataCursor;

    import audiotag.id3v2.v23.extended_header :
        parseId3v23ExtendedHeader;

    import audiotag.id3v2.v23.structure :
        parseId3v23TagStructure;

    import audiotag.id3v2.v23.tag_body_write_policy :
        planId3v23TagBodyWrite;


    private Id3v23TagStructure parseTestTag(
        const(ubyte)[] bytes
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto parsed =
            cursor.parseId3v23TagStructure();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }
}


/// Frame growth consumes existing padding while retaining body capacity.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
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
     * Fifteen-byte replacement frame.
     */
    const ubyte[] frameSequence =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            0x00,
            'T', 'e', 's', 't'
        ];

    const plan =
        planId3v23TagBodyWrite(
            source,
            frameSequence.length,
            true
        );

    assert(plan.writable);
    assert(plan.paddingLength == 5);
    assert(plan.tagSize == 20);

    auto serialized =
        serializeId3v23TagBody(
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


/// An unchanged extended header remains the first exact body bytes.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            // 10 extended + 11 frame + 3 padding = 24.
            0x00, 0x00, 0x00, 0x18,

            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,
            0x00, 0x00, 0x00, 0x03,

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
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x66
        ];

    const plan =
        planId3v23TagBodyWrite(
            source,
            frameSequence.length,
            true
        );

    assert(plan.writable);

    assert(
        plan.extendedHeaderAction ==
        Id3v23ExtendedHeaderWriteAction
            .preserveOriginal
    );

    auto serialized =
        serializeId3v23TagBody(
            source,
            plan,
            frameSequence
        );

    assert(serialized.hasValue);

    assert(
        serialized.value[0 .. 10] ==
        source.body
            .extendedHeader
            .raw
            .data
    );

    assert(
        serialized.value[
            10 ..
            10 + frameSequence.length
        ] ==
        frameSequence
    );

    assert(
        serialized.value[$ - 3 .. $] ==
        [0x00, 0x00, 0x00]
    );
}


/// Changed padding regenerates the v2.3 extended-header padding field.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            // 10 extended + 11 frame + 3 padding = 24.
            0x00, 0x00, 0x00, 0x18,

            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            // Source padding size = 3.
            0x00, 0x00, 0x00, 0x03,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    /*
     * Twelve frame bytes leave two padding bytes in the old
     * frames-plus-padding capacity.
     */
    const ubyte[] frameSequence =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x00,
            'X'
        ];

    const plan =
        planId3v23TagBodyWrite(
            source,
            frameSequence.length,
            true
        );

    assert(plan.writable);

    assert(
        plan.extendedHeaderAction ==
        Id3v23ExtendedHeaderWriteAction
            .regenerate
    );

    assert(plan.paddingLength == 2);
    assert(plan.tagSize == 24);

    auto serialized =
        serializeId3v23TagBody(
            source,
            plan,
            frameSequence
        );

    assert(serialized.hasValue);

    /*
     * Parse the regenerated first ten body bytes independently.
     */
    auto extendedCursor =
        Id3v23DataCursor(
            ByteSpan(
                serialized.value[0 .. 10]
            ),
            false
        );

    auto extended =
        extendedCursor
            .parseId3v23ExtendedHeader();

    assert(extended.hasValue);
    assert(extendedCursor.empty);

    assert(extended.value.size == 6);
    assert(!extended.value.hasCrc);

    assert(
        extended.value.paddingSize ==
        2
    );

    assert(
        serialized.value[
            10 ..
            10 + frameSequence.length
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
            0x03, 0x00,
            0x40,

            // 14 extended + 11 frame + 2 padding = 27.
            0x00, 0x00, 0x00, 0x1B,

            0x00, 0x00, 0x00, 0x0A,
            0x80, 0x00,
            0x00, 0x00, 0x00, 0x02,
            0x12, 0x34, 0x56, 0x78,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    const frameSequence =
        source.frames.frameBytes.data;

    const plan =
        planId3v23TagBodyWrite(
            source,
            frameSequence.length,
            false
        );

    assert(plan.writable);
    assert(!plan.crcBlocksChange);

    auto serialized =
        serializeId3v23TagBody(
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
            0x03, 0x00,
            0x40,

            0x00, 0x00, 0x00, 0x1B,

            0x00, 0x00, 0x00, 0x0A,
            0x80, 0x00,
            0x00, 0x00, 0x00, 0x02,
            0x12, 0x34, 0x56, 0x78,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    const ubyte[] frameSequence =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x00, 'X'
        ];

    const plan =
        planId3v23TagBodyWrite(
            source,
            frameSequence.length,
            true
        );

    assert(!plan.writable);
    assert(plan.crcBlocksChange);

    auto serialized =
        serializeId3v23TagBody(
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


/// A frame sequence that does not match its plan is rejected.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
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
        planId3v23TagBodyWrite(
            source,
            11,
            false
        );

    assert(plan.writable);

    const ubyte[] wrongFrameSequence =
        [0x01, 0x02];

    auto serialized =
        serializeId3v23TagBody(
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
