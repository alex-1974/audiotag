/++
Write planning for an existing ID3v2.3 native frame sequence.

The revision-independent sequence container and iteration algorithm live
in `audiotag.id3v2.common.sequence_write_plan`.

This module retains explicit ID3v2.3 public names and supplies the
revision-specific types and frame planner through compile-time traits.

No bytes are emitted here.
+/
module audiotag.id3v2.v23.sequence_write_plan;

import audiotag.id3v2.common.sequence_write_plan :
    Id3v2FrameSequenceWriteEntry,
    Id3v2FrameSequenceWritePlan,
    planId3v2ExistingFrameSequenceWrite;

import audiotag.id3v2.v23.canonical_projection :
    Id3v23CanonicalFrameRecord;

import audiotag.id3v2.v23.frame_write_plan :
    Id3v23CanonicalFrameMutation,
    Id3v23FrameWriteAction,
    Id3v23FrameWritePlan,
    planId3v23CanonicalFrameWrite;

import audiotag.id3v2.v23.writer_policy :
    Id3v23WriteContext,
    Id3v23WriterPolicy;


/++
Compile-time bindings required by the shared ID3v2 sequence planner.

This type contains no runtime state.
+/
struct Id3v23FrameSequenceWriteTraits
{
    alias CanonicalFrameRecord =
        Id3v23CanonicalFrameRecord;

    alias CanonicalFrameMutation =
        Id3v23CanonicalFrameMutation;

    alias FrameWriteAction =
        Id3v23FrameWriteAction;

    alias FrameWritePlan =
        Id3v23FrameWritePlan;

    alias WriteContext =
        Id3v23WriteContext;

    alias WriterPolicy =
        Id3v23WriterPolicy;

    alias planCanonicalFrameWrite =
        planId3v23CanonicalFrameWrite;
}


/++
One frame-level plan together with its position in the original native
frame sequence.
+/
alias Id3v23FrameSequenceWriteEntry =
    Id3v2FrameSequenceWriteEntry!(
        Id3v23FrameSequenceWriteTraits
    );


/++
Complete write plan for all existing native frames in one ID3v2.3 tag.
+/
alias Id3v23FrameSequenceWritePlan =
    Id3v2FrameSequenceWritePlan!(
        Id3v23FrameSequenceWriteTraits
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
Id3v23FrameSequenceWritePlan
planId3v23ExistingFrameSequenceWrite(
    const(Id3v23CanonicalFrameRecord)[] records,
    const(Id3v23CanonicalFrameMutation)[] mutations,
    Id3v23WriteContext context,
    Id3v23WriterPolicy policy =
        Id3v23WriterPolicy.init
)
    @safe
{
    return
        planId3v2ExistingFrameSequenceWrite!(
            Id3v23FrameSequenceWriteTraits
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

    import audiotag.id3v2.v23.canonical_mapping :
        Id3v23CanonicalMappingStatus;

    import audiotag.id3v2.v23.frame_header :
        Id3v23FrameHeader,
        parseId3v23FrameHeader;

    import audiotag.id3v2.v23.writer_policy :
        Id3v23RequiredDiscardPolicy;


    private Id3v23FrameHeader testHeader(
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
            cursor.parseId3v23FrameHeader();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }


    private Id3v23CanonicalFrameRecord testRecord(
        Id3v23CanonicalMappingStatus status,
        ubyte statusFlags = 0x00,
        size_t canonicalStart = 0,
        size_t canonicalCount = 0
    )
        @safe
    {
        auto record =
            Id3v23CanonicalFrameRecord.init;

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
    const Id3v23CanonicalFrameRecord[] records = [];
    const Id3v23CanonicalFrameMutation[] mutations = [];

    const plan =
        planId3v23ExistingFrameSequenceWrite(
            records,
            mutations,
            Id3v23WriteContext.unchanged()
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
                Id3v23CanonicalMappingStatus.mapped,
                0x00,
                0,
                1
            ),

            testRecord(
                Id3v23CanonicalMappingStatus
                    .unsupportedFrame
            ),

            testRecord(
                Id3v23CanonicalMappingStatus.mapped,
                0x00,
                1,
                1
            )
        ];

    const mutations =
        [
            Id3v23CanonicalFrameMutation.unchanged,
            Id3v23CanonicalFrameMutation.unchanged,
            Id3v23CanonicalFrameMutation.modified
        ];

    const plan =
        planId3v23ExistingFrameSequenceWrite(
            records,
            mutations,
            Id3v23WriteContext.tagOnly()
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
        Id3v23FrameWriteAction
            .preserveOriginal
    );

    assert(
        plan.entries[1].plan.action ==
        Id3v23FrameWriteAction
            .preserveOriginal
    );

    assert(
        plan.entries[2].plan.action ==
        Id3v23FrameWriteAction
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
                Id3v23CanonicalMappingStatus.mapped
            ),

            // Unknown/non-regenerable and tag-alter-sensitive.
            testRecord(
                Id3v23CanonicalMappingStatus
                    .unsupportedFrame,
                0x80
            ),

            testRecord(
                Id3v23CanonicalMappingStatus.mapped
            )
        ];

    const mutations =
        [
            Id3v23CanonicalFrameMutation.unchanged,
            Id3v23CanonicalFrameMutation.unchanged,
            Id3v23CanonicalFrameMutation.modified
        ];

    const plan =
        planId3v23ExistingFrameSequenceWrite(
            records,
            mutations,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.length == 3);
    assert(!plan.writable);

    assert(plan.preserveCount == 1);
    assert(plan.regenerateCount == 1);
    assert(plan.discardCount == 0);
    assert(plan.rejectCount == 1);

    assert(
        plan.entries[1].plan.action ==
        Id3v23FrameWriteAction.rejectWrite
    );
}


/// Explicit discard policy is reflected in aggregate action counts.
unittest
{
    const records =
        [
            testRecord(
                Id3v23CanonicalMappingStatus
                    .unsupportedFrame,
                0x80
            ),

            testRecord(
                Id3v23CanonicalMappingStatus
                    .requiresTransformation
            )
        ];

    const mutations =
        [
            Id3v23CanonicalFrameMutation.unchanged,
            Id3v23CanonicalFrameMutation.unchanged
        ];

    auto policy =
        Id3v23WriterPolicy.init;

    policy.requiredDiscard =
        Id3v23RequiredDiscardPolicy.discard;

    const plan =
        planId3v23ExistingFrameSequenceWrite(
            records,
            mutations,
            Id3v23WriteContext.tagOnly(),
            policy
        );

    assert(plan.writable);

    assert(plan.preserveCount == 1);
    assert(plan.regenerateCount == 0);
    assert(plan.discardCount == 1);
    assert(plan.rejectCount == 0);

    assert(
        plan.entries[0].plan.action ==
        Id3v23FrameWriteAction.discard
    );

    assert(
        plan.entries[1].plan.action ==
        Id3v23FrameWriteAction
            .preserveOriginal
    );
}


/// Read-only canonical modification blocks the complete sequence.
unittest
{
    const records =
        [
            testRecord(
                Id3v23CanonicalMappingStatus.mapped,
                0x20,
                0,
                1
            )
        ];

    const mutations =
        [
            Id3v23CanonicalFrameMutation.modified
        ];

    const plan =
        planId3v23ExistingFrameSequenceWrite(
            records,
            mutations,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);
    assert(plan.rejectCount == 1);

    assert(
        plan.entries[0].plan.action ==
        Id3v23FrameWriteAction.rejectWrite
    );
}
