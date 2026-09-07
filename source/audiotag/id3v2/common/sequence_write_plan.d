/++
Format-independent planning of an existing ID3v2 native frame sequence.

ID3v2 revisions provide compile-time traits containing their concrete
projection, mutation, frame-plan, action, context and policy types plus
the revision-specific frame planner.

This module contains no native frame parsing and emits no bytes.
+/
module audiotag.id3v2.common.sequence_write_plan;


/++
One frame-level plan together with its position in the original native
frame sequence.

`Traits` must provide `FrameWritePlan`.
+/
struct Id3v2FrameSequenceWriteEntry(Traits)
{
    /// Zero-based index in the original native frame sequence.
    size_t sourceFrameIndex;

    /// Preservation/regeneration decision for that frame.
    Traits.FrameWritePlan plan;
}


/++
Complete write plan for all existing native frames of one ID3v2 tag.

`Traits` must provide:

- `FrameWritePlan`
- `FrameWriteAction`
+/
struct Id3v2FrameSequenceWritePlan(Traits)
{
    alias Entry =
        Id3v2FrameSequenceWriteEntry!Traits;

private:
    Entry[] _entries;

    size_t _preserveCount;
    size_t _regenerateCount;
    size_t _discardCount;
    size_t _rejectCount;

public:
    /++
    Returns all frame plans in original native frame order.
    +/
    @property
    const(Entry)[] entries() const
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

    This does not account for newly added canonical fields or whole-tag
    serialization constraints.
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
        Traits.FrameWritePlan plan
    )
        @safe
    {
        _entries ~=
            Entry(
                sourceFrameIndex,
                plan
            );

        final switch (plan.action)
        {
            case Traits.FrameWriteAction.preserveOriginal:
                ++_preserveCount;
                break;

            case Traits.FrameWriteAction.regenerate:
                ++_regenerateCount;
                break;

            case Traits.FrameWriteAction.discard:
                ++_discardCount;
                break;

            case Traits.FrameWriteAction.rejectWrite:
                ++_rejectCount;
                break;
        }
    }
}


/++
Plans all existing native frames in original source order.

`Traits` must provide:

- `CanonicalFrameRecord`
- `CanonicalFrameMutation`
- `FrameWritePlan`
- `FrameWriteAction`
- `WriteContext`
- `WriterPolicy`
- `planCanonicalFrameWrite`

The record and mutation sequences must correspond one-for-one.
+/
Id3v2FrameSequenceWritePlan!Traits
planId3v2ExistingFrameSequenceWrite(Traits)(
    const(Traits.CanonicalFrameRecord)[] records,
    const(Traits.CanonicalFrameMutation)[] mutations,
    Traits.WriteContext context,
    Traits.WriterPolicy policy =
        Traits.WriterPolicy.init
)
    @safe
{
    assert(
        records.length ==
        mutations.length
    );

    auto result =
        Id3v2FrameSequenceWritePlan!Traits.init;

    alias framePlanner =
        Traits.planCanonicalFrameWrite;

    foreach (index, const record; records)
    {
        const framePlan =
            framePlanner(
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
