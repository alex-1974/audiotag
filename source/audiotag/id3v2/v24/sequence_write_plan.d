/++
Write planning for an existing ID3v2.4 native frame sequence.

This module applies the frame-level preservation planner to every
provenance-preserved native frame in original source order.

It plans only frames that already existed in the parsed tag. Canonical
fields newly created by an editing layer are deliberately outside this
model and will be planned separately before serialization.

No bytes are emitted here.
+/
module audiotag.id3v2.v24.sequence_write_plan;

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
One frame-level plan together with its position in the original native
frame sequence.
+/
struct Id3v24FrameSequenceWriteEntry
{
    /// Zero-based index in the original native frame sequence.
    size_t sourceFrameIndex;

    /// Preservation/regeneration decision for that frame.
    Id3v24FrameWritePlan plan;
}


/++
Complete write plan for all existing native frames in one ID3v2.4 tag.

Entries remain in original native frame order.

Action counts are retained explicitly so callers can inspect the plan
without rescanning it.
+/
struct Id3v24FrameSequenceWritePlan
{
private:
    Id3v24FrameSequenceWriteEntry[] _entries;

    size_t _preserveCount;
    size_t _regenerateCount;
    size_t _discardCount;
    size_t _rejectCount;

public:
    /++
    Returns all frame plans in original native frame order.
    +/
    @property
    const(Id3v24FrameSequenceWriteEntry)[] entries() const
        @safe pure nothrow @nogc
    {
        return _entries;
    }

    /// Number of existing native frames represented by this plan.
    @property
    size_t length() const
        @safe pure nothrow @nogc
    {
        return _entries.length;
    }

    /// Whether the sequence contains no existing native frames.
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return _entries.length == 0;
    }

    /// Number of frames whose original bytes will be retained.
    @property
    size_t preserveCount() const
        @safe pure nothrow @nogc
    {
        return _preserveCount;
    }

    /// Number of frames that require canonical regeneration.
    @property
    size_t regenerateCount() const
        @safe pure nothrow @nogc
    {
        return _regenerateCount;
    }

    /// Number of existing native frames explicitly planned for discard.
    @property
    size_t discardCount() const
        @safe pure nothrow @nogc
    {
        return _discardCount;
    }

    /// Number of frame decisions that block writing.
    @property
    size_t rejectCount() const
        @safe pure nothrow @nogc
    {
        return _rejectCount;
    }

    /++
    Returns whether every existing-frame decision permits the write.

    This does not yet account for newly added canonical fields or
    whole-tag serialization constraints.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return _rejectCount == 0;
    }

package:
    /++
    Appends one already planned existing frame.

    This is an internal sequence-planner operation.
    +/
    void append(
        size_t sourceFrameIndex,
        Id3v24FrameWritePlan plan
    )
        @safe
    {
        _entries ~=
            Id3v24FrameSequenceWriteEntry(
                sourceFrameIndex,
                plan
            );

        final switch (plan.action)
        {
            case Id3v24FrameWriteAction.preserveOriginal:
                ++_preserveCount;
                break;

            case Id3v24FrameWriteAction.regenerate:
                ++_regenerateCount;
                break;

            case Id3v24FrameWriteAction.discard:
                ++_discardCount;
                break;

            case Id3v24FrameWriteAction.rejectWrite:
                ++_rejectCount;
                break;
        }
    }
}


/++
Plans all existing native frames in original source order.

One mutation state must be supplied for every native frame record.
Mutation tracking itself belongs to the future canonical editing/diff
layer; this function only consumes its result.

Preconditions:
    `records.length == mutations.length`.

A length mismatch is a programmer/planner error rather than malformed
external metadata.

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
    assert(
        records.length ==
        mutations.length
    );

    auto result =
        Id3v24FrameSequenceWritePlan.init;

    foreach (index, const record; records)
    {
        const framePlan =
            planId3v24CanonicalFrameWrite(
                record,
                mutations[index],
                context,
                policy
            );

        result.append(
            index,
            framePlan
        );
    }

    return result;
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
