/++
Write planning for an existing ID3v2.4 native frame sequence.

The revision-independent sequence container and iteration algorithm live
in `audiotag.id3v2.common.sequence_write_plan`.

This module retains explicit ID3v2.4 public names and supplies the
revision-specific types and frame planner through compile-time traits.

No bytes are emitted here.
+/
module audiotag.id3v2.v24.sequence_write_plan;

import audiotag.id3v2.common.sequence_write_plan :
    Id3v2FrameSequenceWriteEntry,
    Id3v2FrameSequenceWritePlan,
    planId3v2ExistingFrameSequenceWrite;

import audiotag.id3v2.v24.canonical_projection :
    Id3v24CanonicalFrameRecord;

import audiotag.id3v2.v24.frame_write_plan :
    Id3v24CanonicalFrameMutation,
    Id3v24FrameWriteAction,
    Id3v24FrameWritePlan,
    planId3v24CanonicalFrameWrite;

import audiotag.id3v2.v24.writer_policy :
    Id3v24WriteContext,
    Id3v24WriterPolicy;


/++
Compile-time bindings required by the shared ID3v2 sequence planner.

This type contains no runtime state.
+/
struct Id3v24FrameSequenceWriteTraits
{
    alias CanonicalFrameRecord =
        Id3v24CanonicalFrameRecord;

    alias CanonicalFrameMutation =
        Id3v24CanonicalFrameMutation;

    alias FrameWriteAction =
        Id3v24FrameWriteAction;

    alias FrameWritePlan =
        Id3v24FrameWritePlan;

    alias WriteContext =
        Id3v24WriteContext;

    alias WriterPolicy =
        Id3v24WriterPolicy;

    alias planCanonicalFrameWrite =
        planId3v24CanonicalFrameWrite;
}


/++
One frame-level plan together with its position in the original native
frame sequence.
+/
alias Id3v24FrameSequenceWriteEntry =
    Id3v2FrameSequenceWriteEntry!(
        Id3v24FrameSequenceWriteTraits
    );


/++
Complete write plan for all existing native frames in one ID3v2.4 tag.
+/
alias Id3v24FrameSequenceWritePlan =
    Id3v2FrameSequenceWritePlan!(
        Id3v24FrameSequenceWriteTraits
    );


/++
Plans all existing native frames in original source order.

The returned entries preserve source-frame order exactly.

Params:
    records = Existing provenance-preserved native frame records.
    mutations = Canonical mutation state corresponding one-for-one to
        `records`.
    context = Whether the enclosing tag and/or file is being altered.
    policy = Writer preservation policy.

Returns:
    Complete ordered plan for all existing frames.
+/
Id3v24FrameSequenceWritePlan
planId3v24ExistingFrameSequenceWrite(
    const(Id3v24CanonicalFrameRecord)[] records,
    const(Id3v24CanonicalFrameMutation)[] mutations,
    Id3v24WriteContext context,
    Id3v24WriterPolicy policy =
        Id3v24WriterPolicy.init
)
    @safe
{
    return
        planId3v2ExistingFrameSequenceWrite!(
            Id3v24FrameSequenceWriteTraits
        )(
            records,
            mutations,
            context,
            policy
        );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.canonical_mapping :
        Id3v24CanonicalMappingStatus;

    import audiotag.id3v2.v24.frame_header :
        Id3v24FrameHeader,
        parseId3v24FrameHeader;

    import audiotag.id3v2.v24.writer_policy :
        Id3v24RequiredDiscardPolicy;


    private Id3v24FrameHeader testHeader(
        ubyte statusFlags
    )
        @safe
    {
        const ubyte[] bytes =
            [
                'A', 'B', 'C', '1',
                0x00, 0x00, 0x00, 0x01,
                statusFlags,
                0x00
            ];

        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto parsed =
            cursor.parseId3v24FrameHeader();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }


    private Id3v24CanonicalFrameRecord testRecord(
        Id3v24CanonicalMappingStatus status,
        ubyte statusFlags = 0x00,
        size_t canonicalStart = 0,
        size_t canonicalCount = 0
    )
        @safe
    {
        auto record =
            Id3v24CanonicalFrameRecord.init;

        record.native.envelope.header =
            testHeader(statusFlags);

        record.status =
            status;

        record.canonicalStart =
            canonicalStart;

        record.canonicalCount =
            canonicalCount;

        return record;
    }
}


/// Empty existing-frame input produces an empty writable plan.
unittest
{
    const Id3v24CanonicalFrameRecord[] records = [];
    const Id3v24CanonicalFrameMutation[] mutations = [];

    const plan =
        planId3v24ExistingFrameSequenceWrite(
            records,
            mutations,
            Id3v24WriteContext.unchanged()
        );

    assert(plan.empty);
    assert(plan.length == 0);
    assert(plan.writable);

    assert(plan.preserveCount == 0);
    assert(plan.regenerateCount == 0);
    assert(plan.discardCount == 0);
    assert(plan.rejectCount == 0);
}


/// Existing native frame order remains unchanged in the sequence plan.
unittest
{
    const records =
        [
            testRecord(
                Id3v24CanonicalMappingStatus.mapped,
                0x00,
                0,
                1
            ),

            testRecord(
                Id3v24CanonicalMappingStatus
                    .unsupportedFrame
            ),

            testRecord(
                Id3v24CanonicalMappingStatus.mapped,
                0x00,
                1,
                1
            )
        ];

    const mutations =
        [
            Id3v24CanonicalFrameMutation.unchanged,
            Id3v24CanonicalFrameMutation.unchanged,
            Id3v24CanonicalFrameMutation.modified
        ];

    const plan =
        planId3v24ExistingFrameSequenceWrite(
            records,
            mutations,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.length == 3);
    assert(plan.writable);

    assert(
        plan.entries[0].sourceFrameIndex ==
        0
    );

    assert(
        plan.entries[1].sourceFrameIndex ==
        1
    );

    assert(
        plan.entries[2].sourceFrameIndex ==
        2
    );

    assert(
        plan.entries[0].plan.action ==
        Id3v24FrameWriteAction
            .preserveOriginal
    );

    assert(
        plan.entries[1].plan.action ==
        Id3v24FrameWriteAction
            .preserveOriginal
    );

    assert(
        plan.entries[2].plan.action ==
        Id3v24FrameWriteAction
            .regenerate
    );

    assert(plan.preserveCount == 2);
    assert(plan.regenerateCount == 1);
    assert(plan.discardCount == 0);
    assert(plan.rejectCount == 0);
}


/// One rejected frame makes the existing-frame sequence non-writable.
unittest
{
    const records =
        [
            testRecord(
                Id3v24CanonicalMappingStatus.mapped
            ),

            // Unknown/non-regenerable and tag-alter-sensitive.
            testRecord(
                Id3v24CanonicalMappingStatus
                    .unsupportedFrame,
                0x40
            ),

            testRecord(
                Id3v24CanonicalMappingStatus.mapped
            )
        ];

    const mutations =
        [
            Id3v24CanonicalFrameMutation.unchanged,
            Id3v24CanonicalFrameMutation.unchanged,
            Id3v24CanonicalFrameMutation.modified
        ];

    const plan =
        planId3v24ExistingFrameSequenceWrite(
            records,
            mutations,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.length == 3);
    assert(!plan.writable);

    assert(plan.preserveCount == 1);
    assert(plan.regenerateCount == 1);
    assert(plan.discardCount == 0);
    assert(plan.rejectCount == 1);

    assert(
        plan.entries[1].plan.action ==
        Id3v24FrameWriteAction.rejectWrite
    );
}


/// Explicit discard policy is reflected in aggregate action counts.
unittest
{
    const records =
        [
            testRecord(
                Id3v24CanonicalMappingStatus
                    .unsupportedFrame,
                0x40
            ),

            testRecord(
                Id3v24CanonicalMappingStatus
                    .requiresTransformation
            )
        ];

    const mutations =
        [
            Id3v24CanonicalFrameMutation.unchanged,
            Id3v24CanonicalFrameMutation.unchanged
        ];

    auto policy =
        Id3v24WriterPolicy.init;

    policy.requiredDiscard =
        Id3v24RequiredDiscardPolicy.discard;

    const plan =
        planId3v24ExistingFrameSequenceWrite(
            records,
            mutations,
            Id3v24WriteContext.tagOnly(),
            policy
        );

    assert(plan.writable);

    assert(plan.preserveCount == 1);
    assert(plan.regenerateCount == 0);
    assert(plan.discardCount == 1);
    assert(plan.rejectCount == 0);

    assert(
        plan.entries[0].plan.action ==
        Id3v24FrameWriteAction.discard
    );

    assert(
        plan.entries[1].plan.action ==
        Id3v24FrameWriteAction
            .preserveOriginal
    );
}


/// Read-only canonical modification blocks the complete sequence.
unittest
{
    const records =
        [
            testRecord(
                Id3v24CanonicalMappingStatus.mapped,
                0x10,
                0,
                1
            )
        ];

    const mutations =
        [
            Id3v24CanonicalFrameMutation.modified
        ];

    const plan =
        planId3v24ExistingFrameSequenceWrite(
            records,
            mutations,
            Id3v24WriteContext.tagOnly()
        );

    assert(!plan.writable);
    assert(plan.rejectCount == 1);

    assert(
        plan.entries[0].plan.action ==
        Id3v24FrameWriteAction.rejectWrite
    );
}
