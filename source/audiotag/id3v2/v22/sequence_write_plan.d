/++
Write planning for an existing ID3v2.2 native frame sequence.

The revision-independent sequence container, source-order retention and action
counters live in `audiotag.id3v2.common.sequence_write_plan`.

ID3v2.2 has no per-frame preservation/status flags and therefore needs no
writer context or preservation policy. This module binds the simple two-input
frame planner to the shared sequence machinery.

No bytes are emitted here.

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
module audiotag.id3v2.v22.sequence_write_plan;

import audiotag.id3v2.common.sequence_write_plan :
    Id3v2FrameSequenceWriteEntry,
    Id3v2FrameSequenceWritePlan,
    planId3v2ExistingFrameSequenceWriteSimple;

import audiotag.id3v2.v22.canonical_projection :
    Id3v22CanonicalFrameRecord;

import audiotag.id3v2.v22.frame_write_plan :
    Id3v22CanonicalFrameMutation,
    Id3v22FrameWriteAction,
    Id3v22FrameWritePlan,
    planId3v22CanonicalFrameWrite;


/++
Compile-time bindings required by the shared ID3v2 sequence planner.

This type contains no runtime state.
+/
struct Id3v22FrameSequenceWriteTraits
{
    alias CanonicalFrameRecord =
        Id3v22CanonicalFrameRecord;

    alias CanonicalFrameMutation =
        Id3v22CanonicalFrameMutation;

    alias FrameWriteAction =
        Id3v22FrameWriteAction;

    alias FrameWritePlan =
        Id3v22FrameWritePlan;

    alias planCanonicalFrameWrite =
        planId3v22CanonicalFrameWrite;
}


/++
One frame-level plan together with its original ID3v2.2 source-frame index.
+/
alias Id3v22FrameSequenceWriteEntry =
    Id3v2FrameSequenceWriteEntry!(
        Id3v22FrameSequenceWriteTraits
    );


/++
Complete ordered write plan for all existing native frames in one ID3v2.2 tag.
+/
alias Id3v22FrameSequenceWritePlan =
    Id3v2FrameSequenceWritePlan!(
        Id3v22FrameSequenceWriteTraits
    );


/++
Plans all existing ID3v2.2 native frames in original source order.

The record and mutation arrays must correspond one-for-one. Their equal length
is an internal caller invariant, matching the established shared sequence
planner contract.

Params:
    records = Existing provenance-preserved native frame records.
    mutations = Canonical mutation state corresponding one-for-one to
        `records`.

Returns:
    Complete ordered plan for every existing frame.

Complexity:
    O(n) time and O(n) plan storage.
+/
Id3v22FrameSequenceWritePlan
planId3v22ExistingFrameSequenceWrite(
    const(Id3v22CanonicalFrameRecord)[] records,
    const(Id3v22CanonicalFrameMutation)[] mutations
)
    @safe
{
    return
        planId3v2ExistingFrameSequenceWriteSimple!(
            Id3v22FrameSequenceWriteTraits
        )(
            records,
            mutations
        );
}


version (unittest)
{
    import audiotag.id3v2.v22.canonical_mapping :
        Id3v22CanonicalMappingStatus;


    private Id3v22CanonicalFrameRecord
    testRecord(
        Id3v22CanonicalMappingStatus status,
        size_t canonicalStart = 0,
        size_t canonicalCount = 0
    )
        @safe pure nothrow @nogc
    {
        auto record =
            Id3v22CanonicalFrameRecord.init;

        record.status =
            status;

        record.canonicalStart =
            canonicalStart;

        record.canonicalCount =
            canonicalCount;

        return record;
    }
}


/// Empty existing-frame input produces an empty writable sequence plan.
unittest
{
    const Id3v22CanonicalFrameRecord[] records = [];
    const Id3v22CanonicalFrameMutation[] mutations = [];

    const plan =
        planId3v22ExistingFrameSequenceWrite(
            records,
            mutations
        );

    assert(plan.empty);
    assert(plan.length == 0);
    assert(plan.writable);

    assert(plan.preserveCount == 0);
    assert(plan.regenerateCount == 0);
    assert(plan.discardCount == 0);
    assert(plan.rejectCount == 0);
}


/// Existing source order and every frame action remain explicit.
unittest
{
    const records =
        [
            testRecord(
                Id3v22CanonicalMappingStatus.mapped,
                0,
                1
            ),

            testRecord(
                Id3v22CanonicalMappingStatus
                    .unsupportedFrame
            ),

            testRecord(
                Id3v22CanonicalMappingStatus.mapped,
                1,
                1
            ),

            testRecord(
                Id3v22CanonicalMappingStatus.mapped,
                2,
                1
            )
        ];

    const mutations =
        [
            Id3v22CanonicalFrameMutation.unchanged,
            Id3v22CanonicalFrameMutation.unchanged,
            Id3v22CanonicalFrameMutation.modified,
            Id3v22CanonicalFrameMutation.removed
        ];

    const plan =
        planId3v22ExistingFrameSequenceWrite(
            records,
            mutations
        );

    assert(plan.length == 4);
    assert(plan.writable);

    foreach (index, const entry; plan.entries)
    {
        assert(entry.sourceFrameIndex == index);
    }

    assert(
        plan.entries[0].plan.action ==
        Id3v22FrameWriteAction.preserveOriginal
    );
    assert(
        plan.entries[1].plan.action ==
        Id3v22FrameWriteAction.preserveOriginal
    );
    assert(
        plan.entries[2].plan.action ==
        Id3v22FrameWriteAction.regenerate
    );
    assert(
        plan.entries[3].plan.action ==
        Id3v22FrameWriteAction.discard
    );

    assert(plan.preserveCount == 2);
    assert(plan.regenerateCount == 1);
    assert(plan.discardCount == 1);
    assert(plan.rejectCount == 0);
}


/// One non-representable mutation makes the complete sequence non-writable.
unittest
{
    const records =
        [
            testRecord(
                Id3v22CanonicalMappingStatus.mapped,
                0,
                1
            ),

            testRecord(
                Id3v22CanonicalMappingStatus
                    .unsupportedFrame
            ),

            testRecord(
                Id3v22CanonicalMappingStatus.mapped,
                1,
                1
            )
        ];

    const mutations =
        [
            Id3v22CanonicalFrameMutation.unchanged,
            Id3v22CanonicalFrameMutation.modified,
            Id3v22CanonicalFrameMutation.modified
        ];

    const plan =
        planId3v22ExistingFrameSequenceWrite(
            records,
            mutations
        );

    assert(plan.length == 3);
    assert(!plan.writable);

    assert(plan.preserveCount == 1);
    assert(plan.regenerateCount == 1);
    assert(plan.discardCount == 0);
    assert(plan.rejectCount == 1);

    assert(
        plan.entries[1].plan.action ==
        Id3v22FrameWriteAction.rejectWrite
    );
}


/// Canonical ranges survive sequence planning unchanged.
unittest
{
    const records =
        [
            testRecord(
                Id3v22CanonicalMappingStatus.mapped,
                5,
                1
            ),

            testRecord(
                Id3v22CanonicalMappingStatus.mapped,
                5,
                1
            )
        ];

    const mutations =
        [
            Id3v22CanonicalFrameMutation.modified,
            Id3v22CanonicalFrameMutation.modified
        ];

    const plan =
        planId3v22ExistingFrameSequenceWrite(
            records,
            mutations
        );

    assert(plan.writable);
    assert(plan.regenerateCount == 2);

    assert(plan.entries[0].plan.canonicalStart == 5);
    assert(plan.entries[1].plan.canonicalStart == 5);
    assert(plan.entries[0].plan.canonicalCount == 1);
    assert(plan.entries[1].plan.canonicalCount == 1);
}
