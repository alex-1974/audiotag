/++
Physical write planning for one reconstructed ID3v2.2 tag body.

This module bridges the logical body writer and the final physical tag
serializer.

Given one complete logical, uncompressed ID3v2.2 body it derives:

- whether whole-tag unsynchronisation is required;
- the resulting physical stored-body length;
- the output header flags;
- the 28-bit `tagSize`;
- the complete fixed-header value to serialize later.

No bytes are allocated or transformed here.

The plan is intentionally source-independent. Source unsynchronisation is
physical provenance and does not control the output flag. A reconstructed tag
derives unsynchronisation from the resulting logical body itself.

Whole-tag-compressed opaque sources do not enter this planner. Exact opaque
no-op preservation is a separate higher-level path; reconstruction never
silently clears compression and interprets compressed bytes as frames.

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
module audiotag.id3v2.v22.tag_physical_write_plan;

import audiotag.id3v2.v22.header :
    Id3v22Header;

import audiotag.id3v2.v22.unsync_write :
    measureId3v22UnsynchronisedLength,
    requiresId3v22Unsynchronisation;


/++
Primary outcome of ID3v2.2 physical tag planning.
+/
enum Id3v22PhysicalTagWriteStatus : ubyte
{
    /// Physical tag planning succeeded.
    ready,

    /// Reconstructed writable tags require a non-empty logical body.
    emptyLogicalBody,

    /// Logical body length itself exceeds the 28-bit ID3 tag-size domain.
    logicalTagSizeOverflow,

    /++
    Whole-tag unsynchronisation expands the stored body beyond the 28-bit
    ID3 tag-size domain.
    +/
    physicalTagSizeOverflow
}


/++
Complete physical write plan for one reconstructed ID3v2.2 tag body.
+/
struct Id3v22PhysicalTagWritePlan
{
    /// Primary planning outcome.
    Id3v22PhysicalTagWriteStatus status;

    /// Complete logical body length before whole-tag unsynchronisation.
    size_t logicalBodyLength;

    /// Whether the complete logical body must be unsynchronised.
    bool unsynchronisation;

    /// Stored body length after whole-tag unsynchronisation when active.
    size_t physicalBodyLength;

    /++
    Output ID3v2.2 flags.

    Reconstructed tags currently use only bit 7 for whole-tag
    unsynchronisation. Compression is never introduced by this path.
    +/
    ubyte flags;

    /// 28-bit physical body size stored in the fixed ID3 header.
    uint tagSize;

    /++
    Complete output header value.

    `sourceOffset` is always zero because it is provenance only.
    `revision` is always zero because the writer emits ID3v2.2.0 only.
    +/
    Id3v22Header header;


    /++
    Returns whether physical body transformation and header serialization may
    proceed.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            status ==
                Id3v22PhysicalTagWriteStatus.ready;
    }
}


/++
Builds the final bounded physical/header plan from already derived lengths.

This helper is kept separate so boundary behavior can be tested without
allocating bodies hundreds of megabytes in size.

Params:
    logicalBodyLength = Complete logical body size.
    unsynchronisation = Whether whole-tag unsynchronisation is active.
    physicalBodyLength = Resulting stored body size.

Returns:
    Completed plan or an explicit 28-bit size failure.

Complexity:
    O(1) time and space.
+/
private Id3v22PhysicalTagWritePlan
finalizeId3v22PhysicalTagWritePlan(
    size_t logicalBodyLength,
    bool unsynchronisation,
    size_t physicalBodyLength
)
    @safe pure nothrow @nogc
{
    enum size_t maximumTagSize =
        0x0FFF_FFFF;

    auto result =
        Id3v22PhysicalTagWritePlan.init;

    result.logicalBodyLength =
        logicalBodyLength;

    result.unsynchronisation =
        unsynchronisation;

    result.physicalBodyLength =
        physicalBodyLength;

    if (logicalBodyLength == 0)
    {
        result.status =
            Id3v22PhysicalTagWriteStatus
                .emptyLogicalBody;

        return result;
    }

    if (
        logicalBodyLength >
        maximumTagSize
    )
    {
        result.status =
            Id3v22PhysicalTagWriteStatus
                .logicalTagSizeOverflow;

        return result;
    }

    if (
        physicalBodyLength >
        maximumTagSize
    )
    {
        result.status =
            Id3v22PhysicalTagWriteStatus
                .physicalTagSizeOverflow;

        return result;
    }

    result.status =
        Id3v22PhysicalTagWriteStatus.ready;

    result.flags =
        unsynchronisation
        ? cast(ubyte) 0x80
        : cast(ubyte) 0x00;

    result.tagSize =
        cast(uint)
            physicalBodyLength;

    result.header =
        Id3v22Header(
            0,
            0,
            result.flags,
            result.tagSize
        );

    return result;
}


/++
Plans physical storage and the fixed ID3v2.2 header for one complete logical
tag body.

Unsynchronisation is activated only when the resulting logical body contains a
false MPEG synchronisation requiring the ID3v2.2 scheme. When active, length
measurement also accounts for protection of logical `$FF $00` pairs.

The output flag is derived from the resulting body. Source header flags are not
inputs to this function.

Params:
    logicalBody = Complete reconstructed logical frames-plus-padding body.

Returns:
    Allocation-free physical/header plan with explicit failure status.

Safety:
    No input bytes are retained or modified.

Complexity:
    O(n) time and O(1) additional space.
+/
Id3v22PhysicalTagWritePlan
planId3v22PhysicalTagWrite(
    const(ubyte)[] logicalBody
)
    @safe pure nothrow @nogc
{
    const unsynchronisation =
        requiresId3v22Unsynchronisation(
            logicalBody
        );

    size_t physicalBodyLength =
        logicalBody.length;

    if (unsynchronisation)
    {
        auto measured =
            measureId3v22UnsynchronisedLength(
                logicalBody
            );

        /*
         * The logical body is bounded to 28 bits by the body planner. On all D
         * targets `size_t` can therefore represent the logical length and any
         * possible ID3-sized stuffed result. A measurement overflow is still
         * handled defensively as a physical-size failure.
         */
        if (measured.hasError)
        {
            auto failed =
                Id3v22PhysicalTagWritePlan.init;

            failed.status =
                Id3v22PhysicalTagWriteStatus
                    .physicalTagSizeOverflow;

            failed.logicalBodyLength =
                logicalBody.length;

            failed.unsynchronisation =
                true;

            failed.physicalBodyLength =
                size_t.max;

            return failed;
        }

        physicalBodyLength =
            measured.value;
    }

    return
        finalizeId3v22PhysicalTagWritePlan(
            logicalBody.length,
            unsynchronisation,
            physicalBodyLength
        );
}


version (unittest)
{
    import audiotag.id3v2.v22.tag_header_write :
        serializeId3v22Header;

    import audiotag.id3v2.v22.unsync_write :
        serializeId3v22UnsynchronisedBytes;
}


/// Ordinary logical data remains unstuffed with a clear flags byte.
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
    assert(!plan.unsynchronisation);

    assert(
        plan.logicalBodyLength ==
        logicalBody.length
    );

    assert(
        plan.physicalBodyLength ==
        logicalBody.length
    );

    assert(plan.flags == 0x00);
    assert(plan.tagSize == logicalBody.length);

    assert(plan.header.sourceOffset == 0);
    assert(plan.header.revision == 0);
    assert(plan.header.flags == 0x00);
    assert(plan.header.tagSize == logicalBody.length);
}


/// A false MPEG sync activates whole-tag unsynchronisation.
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
    assert(plan.logicalBodyLength == 4);
    assert(plan.physicalBodyLength == 5);
    assert(plan.flags == 0x80);
    assert(plan.tagSize == 5);

    auto encoded =
        serializeId3v22UnsynchronisedBytes(
            logicalBody
        );

    assert(encoded.hasValue);

    assert(
        encoded.value.length ==
        plan.physicalBodyLength
    );
}


/// Once active, the physical length also protects logical FF 00 pairs.
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
    assert(plan.unsynchronisation);
    assert(plan.logicalBodyLength == 5);
    assert(plan.physicalBodyLength == 7);

    auto encoded =
        serializeId3v22UnsynchronisedBytes(
            logicalBody
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            0xFF, 0x00, 0xE0,
            0x11,
            0xFF, 0x00, 0x00
        ]
    );
}


/// FF 00 alone does not cause an output unsynchronisation flag.
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
    assert(plan.physicalBodyLength == 4);
    assert(plan.flags == 0x00);
}


/// The derived header serializes the exact planned physical body size.
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

    assert(plan.writable);

    auto header =
        serializeId3v22Header(
            plan.header
        );

    assert(header.hasValue);

    assert(
        header.value ==
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x80,
            0x00, 0x00, 0x00, 0x05
        ]
    );
}


/// Empty reconstructed bodies are rejected explicitly.
unittest
{
    const ubyte[] logicalBody = [];

    const plan =
        planId3v22PhysicalTagWrite(
            logicalBody
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v22PhysicalTagWriteStatus
            .emptyLogicalBody
    );
}


/// The exact maximum logical and physical size remains writable.
unittest
{
    const plan =
        finalizeId3v22PhysicalTagWritePlan(
            0x0FFF_FFFF,
            false,
            0x0FFF_FFFF
        );

    assert(plan.writable);
    assert(plan.tagSize == 0x0FFF_FFFF);

    assert(
        plan.header.tagSize ==
        0x0FFF_FFFF
    );
}


/// Logical size overflow is distinguishable without huge allocations.
unittest
{
    const plan =
        finalizeId3v22PhysicalTagWritePlan(
            0x1000_0000,
            false,
            0x1000_0000
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v22PhysicalTagWriteStatus
            .logicalTagSizeOverflow
    );
}


/// Unsync expansion beyond 28 bits has its own explicit failure.
unittest
{
    const plan =
        finalizeId3v22PhysicalTagWritePlan(
            0x0FFF_FFFF,
            true,
            0x1000_0000
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v22PhysicalTagWriteStatus
            .physicalTagSizeOverflow
    );

    assert(plan.unsynchronisation);
}


/// Compression is never introduced by reconstructed physical planning.
unittest
{
    const ubyte[] logicalBody =
        [
            0xFF, 0xE0
        ];

    const plan =
        planId3v22PhysicalTagWrite(
            logicalBody
        );

    assert(plan.writable);
    assert((plan.flags & 0x40) == 0);
    assert(!plan.header.compressed);
    assert(plan.header.unsynchronisation);
}
