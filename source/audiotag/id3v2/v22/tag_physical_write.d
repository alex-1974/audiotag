/++
Physical serialization of one reconstructed ID3v2.2 tag.

This module composes the already separated lower writer layers:

1. validate that the supplied physical plan still describes the logical body;
2. apply whole-tag unsynchronisation when the plan requires it;
3. validate the resulting stored body length;
4. serialize the fixed ID3v2.2 header from the planned physical size;
5. concatenate header and physical body.

No semantic/canonical frame planning is performed here. The input is already a
complete logical frames-plus-padding body.

Whole-tag-compressed opaque tags do not enter this reconstruction path. Exact
opaque no-op preservation remains a separate higher-level operation.

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
module audiotag.id3v2.v22.tag_physical_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v22.tag_header_write :
    serializeId3v22Header;

import audiotag.id3v2.v22.tag_physical_write_plan :
    Id3v22PhysicalTagWritePlan,
    planId3v22PhysicalTagWrite;

import audiotag.id3v2.v22.unsync_write :
    serializeId3v22UnsynchronisedBytes;


/++
Serializes one complete reconstructed ID3v2.2 tag from a physical write plan.

`logicalBody` must be the same complete logical frames-plus-padding body used
to construct `plan`.

The function recalculates the physical plan from `logicalBody` and requires all
externally relevant plan fields to agree before any final tag bytes are
returned. This prevents stale or forged plans from:

- suppressing required unsynchronisation;
- setting an unnecessary unsynchronisation flag;
- claiming the wrong physical body length;
- serializing inconsistent flags or `tagSize` values.

Params:
    plan = Previously constructed physical/header plan.
    logicalBody = Complete logical ID3v2.2 body before whole-tag
        unsynchronisation.

Returns:
    Complete owned ID3v2.2 tag bytes, including the ten-byte header, or a
    structured serialization failure.

Safety:
    The returned buffer owns its bytes and retains no view into `logicalBody`.

Complexity:
    O(n) time and O(n) output space.
+/
SerializationResult!(ubyte[])
serializeId3v22PhysicalTag(
    const(Id3v22PhysicalTagWritePlan) plan,
    const(ubyte)[] logicalBody
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
        logicalBody.length !=
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
                        logicalBody.length,
                        plan.logicalBodyLength
                    )
                );
    }

    const actualPlan =
        planId3v22PhysicalTagWrite(
            logicalBody
        );

    if (!actualPlan.writable)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        0,
                        actualPlan.physicalBodyLength,
                        plan.physicalBodyLength
                    )
                );
    }

    /*
     * Unsynchronisation is a property of the complete resulting logical body.
     * A caller-supplied plan must not be able to force or suppress it.
     */
    if (
        actualPlan.unsynchronisation !=
        plan.unsynchronisation
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        5,
                        actualPlan.flags,
                        plan.flags
                    )
                );
    }

    if (
        actualPlan.physicalBodyLength !=
        plan.physicalBodyLength
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        6,
                        actualPlan.physicalBodyLength,
                        plan.physicalBodyLength
                    )
                );
    }

    if (
        actualPlan.flags != plan.flags ||
        actualPlan.tagSize != plan.tagSize ||
        actualPlan.header.revision !=
            plan.header.revision ||
        actualPlan.header.flags !=
            plan.header.flags ||
        actualPlan.header.tagSize !=
            plan.header.tagSize
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

    const(ubyte)[] physicalBody;

    if (plan.unsynchronisation)
    {
        auto unsynchronised =
            serializeId3v22UnsynchronisedBytes(
                logicalBody
            );

        if (unsynchronised.hasError)
        {
            return
                SerializationResult!(ubyte[])
                    .failure(
                        unsynchronised.error
                    );
        }

        physicalBody =
            unsynchronised.value;
    }
    else
    {
        physicalBody =
            logicalBody;
    }

    if (
        physicalBody.length !=
        plan.physicalBodyLength
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        6,
                        physicalBody.length,
                        plan.physicalBodyLength
                    )
                );
    }

    /*
     * sourceOffset is provenance only. The low-level header writer ignores it,
     * but the physical planner constructs a canonical zero offset and the
     * complete physical writer requires that exact plan.
     */
    if (plan.header.sourceOffset != 0)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        0,
                        plan.header.sourceOffset,
                        0
                    )
                );
    }

    auto header =
        serializeId3v22Header(
            plan.header
        );

    if (header.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    header.error
                );
    }

    auto output =
        new ubyte[
            header.value.length +
            physicalBody.length
        ];

    size_t position;

    output[
        position ..
        position + header.value.length
    ] =
        header.value[];

    position +=
        header.value.length;

    output[
        position ..
        position + physicalBody.length
    ] =
        physicalBody;

    position +=
        physicalBody.length;

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

    import audiotag.id3v2.v22.header :
        parseId3v22Header;

    import audiotag.id3v2.v22.tag_physical_write_plan :
        Id3v22PhysicalTagWriteStatus;
}


/// An ordinary logical body becomes header plus unchanged physical body.
unittest
{
    const ubyte[] logicalBody =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55,
            0x00, 0x00
        ];

    const plan =
        planId3v22PhysicalTagWrite(
            logicalBody
        );

    assert(plan.writable);

    auto serialized =
        serializeId3v22PhysicalTag(
            plan,
            logicalBody
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x09,

            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55,
            0x00, 0x00
        ]
    );
}


/// Required whole-tag unsynchronisation is applied before final sizing.
unittest
{
    const ubyte[] logicalBody =
        [
            0x11,
            0xFF, 0xE1,
            0x22
        ];

    const plan =
        planId3v22PhysicalTagWrite(
            logicalBody
        );

    assert(plan.writable);
    assert(plan.unsynchronisation);
    assert(plan.physicalBodyLength == 5);

    auto serialized =
        serializeId3v22PhysicalTag(
            plan,
            logicalBody
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x80,
            0x00, 0x00, 0x00, 0x05,

            0x11,
            0xFF, 0x00, 0xE1,
            0x22
        ]
    );
}


/// Active unsynchronisation also protects logical FF 00 pairs.
unittest
{
    const ubyte[] logicalBody =
        [
            0xFF, 0xE0,
            0x11,
            0xFF, 0x00
        ];

    const plan =
        planId3v22PhysicalTagWrite(
            logicalBody
        );

    assert(plan.writable);
    assert(plan.physicalBodyLength == 7);

    auto serialized =
        serializeId3v22PhysicalTag(
            plan,
            logicalBody
        );

    assert(serialized.hasValue);

    assert(
        serialized.value[10 .. $] ==
        [
            0xFF, 0x00, 0xE0,
            0x11,
            0xFF, 0x00, 0x00
        ]
    );

    assert(serialized.value[5] == 0x80);

    assert(
        serialized.value[6 .. 10] ==
        [0x00, 0x00, 0x00, 0x07]
    );
}


/// FF 00 alone remains unstuffed because it does not activate the scheme.
unittest
{
    const ubyte[] logicalBody =
        [
            0x11,
            0xFF, 0x00,
            0x22
        ];

    const plan =
        planId3v22PhysicalTagWrite(
            logicalBody
        );

    assert(plan.writable);
    assert(!plan.unsynchronisation);

    auto serialized =
        serializeId3v22PhysicalTag(
            plan,
            logicalBody
        );

    assert(serialized.hasValue);
    assert(serialized.value[5] == 0x00);
    assert(serialized.value[10 .. $] == logicalBody);
}


/// The serialized fixed header round-trips with the exact stored body size.
unittest
{
    const ubyte[] logicalBody =
        [
            0x11,
            0xFF, 0xE0,
            0x22
        ];

    const plan =
        planId3v22PhysicalTagWrite(
            logicalBody
        );

    auto serialized =
        serializeId3v22PhysicalTag(
            plan,
            logicalBody
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[]
            )
        );

    auto header =
        cursor.parseId3v22Header();

    assert(header.hasValue);

    assert(header.value.revision == 0);
    assert(header.value.unsynchronisation);
    assert(!header.value.compressed);

    assert(
        header.value.tagSize ==
        serialized.value.length - 10
    );
}


/// A non-writable physical plan is rejected before serialization.
unittest
{
    const plan =
        Id3v22PhysicalTagWritePlan(
            Id3v22PhysicalTagWriteStatus
                .emptyLogicalBody
        );

    const ubyte[] logicalBody = [];

    auto serialized =
        serializeId3v22PhysicalTag(
            plan,
            logicalBody
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// A stale plan for a different logical body length is rejected.
unittest
{
    const ubyte[] original =
        [0x11, 0x22, 0x33];

    const plan =
        planId3v22PhysicalTagWrite(
            original
        );

    const ubyte[] changed =
        [0x11, 0x22, 0x33, 0x44];

    auto serialized =
        serializeId3v22PhysicalTag(
            plan,
            changed
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );

    assert(serialized.error.index == 0);
    assert(serialized.error.value == 4);
    assert(serialized.error.limit == 3);
}


/// A forged plan cannot suppress required unsynchronisation.
unittest
{
    const ubyte[] logicalBody =
        [
            0x11,
            0xFF, 0xE1,
            0x22
        ];

    auto plan =
        planId3v22PhysicalTagWrite(
            logicalBody
        );

    assert(plan.writable);
    assert(plan.unsynchronisation);

    plan.unsynchronisation = false;
    plan.flags = 0x00;
    plan.physicalBodyLength =
        logicalBody.length;
    plan.tagSize =
        cast(uint)
            logicalBody.length;
    plan.header.flags = 0x00;
    plan.header.tagSize =
        cast(uint)
            logicalBody.length;

    auto serialized =
        serializeId3v22PhysicalTag(
            plan,
            logicalBody
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );

    assert(serialized.error.index == 5);
}


/// A forged physical body size is rejected even when other fields look valid.
unittest
{
    const ubyte[] logicalBody =
        [
            0x11,
            0x22,
            0x33
        ];

    auto plan =
        planId3v22PhysicalTagWrite(
            logicalBody
        );

    assert(plan.writable);

    ++plan.physicalBodyLength;

    auto serialized =
        serializeId3v22PhysicalTag(
            plan,
            logicalBody
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );

    assert(serialized.error.index == 6);
}


/// Reconstructed output never introduces the v2.2 compression flag.
unittest
{
    const ubyte[] logicalBody =
        [
            0x11,
            0x22
        ];

    const plan =
        planId3v22PhysicalTagWrite(
            logicalBody
        );

    auto serialized =
        serializeId3v22PhysicalTag(
            plan,
            logicalBody
        );

    assert(serialized.hasValue);
    assert((serialized.value[5] & 0x40) == 0);
}
