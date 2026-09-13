/++
Write planning for one provenance-preserved ID3v2.2 frame.

ID3v2.2 frames have no per-frame status or preservation flags. Frame-level
writer policy is therefore revision-specific and deliberately simpler than the
ID3v2.3/ID3v2.4 policy:

- a mapped unchanged frame preserves its original representation;
- a mapped modified frame is regenerated;
- a mapped removed frame is omitted;
- an unsupported, transformation-pending, or canonically unrepresentable
  frame is preserved when unchanged;
- a canonical mutation applied to such a non-mapped frame rejects the write.

No bytes are serialized here.

Whether a mapped frame family actually has an implemented semantic serializer
is decided by the later regeneration plan. `regenerate` means that semantic
regeneration is required, not that it is already guaranteed to succeed.

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
module audiotag.id3v2.v22.frame_write_plan;

import audiotag.id3v2.v22.canonical_mapping :
    Id3v22CanonicalMappingStatus;

import audiotag.id3v2.v22.canonical_projection :
    Id3v22CanonicalFrameRecord;


/++
Whether the canonical assertion associated with one native ID3v2.2 frame has
changed since projection.

Mutation tracking belongs to the canonical editing/diff layer. The frame
planner consumes the already derived state.
+/
enum Id3v22CanonicalFrameMutation : ubyte
{
    /// Canonical assertion remains unchanged.
    unchanged,

    /// Canonical assertion has a replacement value.
    modified,

    /// Canonical assertion is absent from the resulting metadata.
    removed
}


/++
Concrete writer action for one existing native ID3v2.2 frame.
+/
enum Id3v22FrameWriteAction : ubyte
{
    /++
    Retain the original frame representation.

    For a source tag that used whole-tag unsynchronisation, the later sequence
    writer must reconstruct the preserved frame in the logical/native byte
    domain before any new whole-tag unsynchronisation is applied.
    +/
    preserveOriginal,

    /// Regenerate this frame from the resulting canonical value.
    regenerate,

    /// Omit this existing frame from the resulting tag.
    discard,

    /// Refuse the write because the requested mutation is not representable.
    rejectWrite
}


/++
Write plan for one provenance-preserved native ID3v2.2 frame.
+/
struct Id3v22FrameWritePlan
{
    /// Canonical mapping state produced during projection.
    Id3v22CanonicalMappingStatus mappingStatus;

    /// Canonical mutation associated with this native frame.
    Id3v22CanonicalFrameMutation mutation;

    /// Selected writer action.
    Id3v22FrameWriteAction action;

    /// First associated canonical field position.
    size_t canonicalStart;

    /// Number of associated canonical fields.
    size_t canonicalCount;


    /++
    Returns whether this frame-level decision permits writing to continue.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            action !=
                Id3v22FrameWriteAction.rejectWrite;
    }
}


/++
Plans writing of one existing native ID3v2.2 frame.

ID3v2.2 has no native frame-level read-only, tag-alter-preservation or
file-alter-preservation flags. No enclosing write context is therefore needed
for this decision.

Mapped frames follow the canonical mutation directly:

- unchanged -> preserve;
- modified -> regenerate;
- removed -> discard.

Frames without a current canonical representation can only be preserved
unchanged. A modified or removed mutation for such a frame is rejected rather
than silently losing native metadata.

Params:
    record = Native frame plus canonical projection relationship.
    mutation = Canonical mutation associated with the frame.

Returns:
    Explicit frame-level write plan.

Safety:
    No source bytes are retained or modified.

Complexity:
    O(1) time and space.
+/
Id3v22FrameWritePlan
planId3v22CanonicalFrameWrite(
    const(Id3v22CanonicalFrameRecord) record,
    Id3v22CanonicalFrameMutation mutation
)
    @safe pure nothrow @nogc
{
    Id3v22FrameWriteAction action;

    final switch (record.status)
    {
        case Id3v22CanonicalMappingStatus.mapped:
        {
            final switch (mutation)
            {
                case Id3v22CanonicalFrameMutation.unchanged:
                    action =
                        Id3v22FrameWriteAction
                            .preserveOriginal;
                    break;

                case Id3v22CanonicalFrameMutation.modified:
                    action =
                        Id3v22FrameWriteAction
                            .regenerate;
                    break;

                case Id3v22CanonicalFrameMutation.removed:
                    action =
                        Id3v22FrameWriteAction
                            .discard;
                    break;
            }

            break;
        }

        case Id3v22CanonicalMappingStatus.unsupportedFrame:
        case Id3v22CanonicalMappingStatus.requiresTransformation:
        case Id3v22CanonicalMappingStatus.unrepresentableValueShape:
        {
            if (
                mutation ==
                Id3v22CanonicalFrameMutation.unchanged
            )
            {
                action =
                    Id3v22FrameWriteAction
                        .preserveOriginal;
            }
            else
            {
                action =
                    Id3v22FrameWriteAction
                        .rejectWrite;
            }

            break;
        }
    }

    return
        Id3v22FrameWritePlan(
            record.status,
            mutation,
            action,
            record.canonicalStart,
            record.canonicalCount
        );
}


version (unittest)
{
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


/// An unchanged mapped frame preserves its source position relationship.
unittest
{
    const record =
        testRecord(
            Id3v22CanonicalMappingStatus.mapped,
            4,
            1
        );

    const plan =
        planId3v22CanonicalFrameWrite(
            record,
            Id3v22CanonicalFrameMutation.unchanged
        );

    assert(plan.writable);

    assert(
        plan.mappingStatus ==
        Id3v22CanonicalMappingStatus.mapped
    );

    assert(
        plan.mutation ==
        Id3v22CanonicalFrameMutation.unchanged
    );

    assert(
        plan.action ==
        Id3v22FrameWriteAction.preserveOriginal
    );

    assert(plan.canonicalStart == 4);
    assert(plan.canonicalCount == 1);
}


/// A modified mapped frame requires semantic regeneration.
unittest
{
    const record =
        testRecord(
            Id3v22CanonicalMappingStatus.mapped,
            2,
            1
        );

    const plan =
        planId3v22CanonicalFrameWrite(
            record,
            Id3v22CanonicalFrameMutation.modified
        );

    assert(plan.writable);

    assert(
        plan.action ==
        Id3v22FrameWriteAction.regenerate
    );

    assert(plan.canonicalStart == 2);
    assert(plan.canonicalCount == 1);
}


/// A removed mapped frame is omitted from the resulting sequence.
unittest
{
    const record =
        testRecord(
            Id3v22CanonicalMappingStatus.mapped,
            7,
            1
        );

    const plan =
        planId3v22CanonicalFrameWrite(
            record,
            Id3v22CanonicalFrameMutation.removed
        );

    assert(plan.writable);

    assert(
        plan.action ==
        Id3v22FrameWriteAction.discard
    );
}


/// Every non-mapped canonical status preserves unchanged native metadata.
unittest
{
    foreach (
        status;
        [
            Id3v22CanonicalMappingStatus
                .unsupportedFrame,

            Id3v22CanonicalMappingStatus
                .requiresTransformation,

            Id3v22CanonicalMappingStatus
                .unrepresentableValueShape
        ]
    )
    {
        const record =
            testRecord(status);

        const plan =
            planId3v22CanonicalFrameWrite(
                record,
                Id3v22CanonicalFrameMutation.unchanged
            );

        assert(plan.writable);

        assert(
            plan.action ==
            Id3v22FrameWriteAction
                .preserveOriginal
        );

        assert(plan.mappingStatus == status);
        assert(plan.canonicalCount == 0);
    }
}


/// Modified non-mapped native metadata cannot be represented canonically.
unittest
{
    foreach (
        status;
        [
            Id3v22CanonicalMappingStatus
                .unsupportedFrame,

            Id3v22CanonicalMappingStatus
                .requiresTransformation,

            Id3v22CanonicalMappingStatus
                .unrepresentableValueShape
        ]
    )
    {
        const record =
            testRecord(status);

        const plan =
            planId3v22CanonicalFrameWrite(
                record,
                Id3v22CanonicalFrameMutation.modified
            );

        assert(!plan.writable);

        assert(
            plan.action ==
            Id3v22FrameWriteAction.rejectWrite
        );
    }
}


/// Removal cannot silently discard non-mapped native metadata.
unittest
{
    foreach (
        status;
        [
            Id3v22CanonicalMappingStatus
                .unsupportedFrame,

            Id3v22CanonicalMappingStatus
                .requiresTransformation,

            Id3v22CanonicalMappingStatus
                .unrepresentableValueShape
        ]
    )
    {
        const record =
            testRecord(status);

        const plan =
            planId3v22CanonicalFrameWrite(
                record,
                Id3v22CanonicalFrameMutation.removed
            );

        assert(!plan.writable);

        assert(
            plan.action ==
            Id3v22FrameWriteAction.rejectWrite
        );
    }
}


/// Many-to-one canonical relationships remain explicit in frame plans.
unittest
{
    const first =
        testRecord(
            Id3v22CanonicalMappingStatus.mapped,
            3,
            1
        );

    const second =
        testRecord(
            Id3v22CanonicalMappingStatus.mapped,
            3,
            1
        );

    const firstPlan =
        planId3v22CanonicalFrameWrite(
            first,
            Id3v22CanonicalFrameMutation.modified
        );

    const secondPlan =
        planId3v22CanonicalFrameWrite(
            second,
            Id3v22CanonicalFrameMutation.modified
        );

    assert(firstPlan.writable);
    assert(secondPlan.writable);

    assert(
        firstPlan.action ==
        Id3v22FrameWriteAction.regenerate
    );

    assert(
        secondPlan.action ==
        Id3v22FrameWriteAction.regenerate
    );

    assert(firstPlan.canonicalStart == 3);
    assert(secondPlan.canonicalStart == 3);
    assert(firstPlan.canonicalCount == 1);
    assert(secondPlan.canonicalCount == 1);
}
