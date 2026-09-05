/++
Write planning for one provenance-preserved ID3v2.4 frame.

This module converts canonical mapping state, canonical mutation state
and writer preservation policy into one explicit frame-level write
action.

No bytes are serialized here.

ID3v2.4 tag-alter and file-alter preservation flags formally describe
how software should handle frames unknown to it. For writer planning,
a frame that cannot currently be regenerated is treated conservatively
like an unknown frame: its original bytes are preserved unless the
native preservation flags require discard, in which case policy decides
between explicit discard and rejecting the write.

Mapped frames whose canonical value has not changed retain their exact
original physical representation.
+/
module audiotag.id3v2.v24.frame_write_plan;

import audiotag.id3v2.v24.canonical_mapping :
    Id3v24CanonicalMappingStatus;

import audiotag.id3v2.v24.canonical_projection :
    Id3v24CanonicalFrameRecord;

import audiotag.id3v2.v24.writer_policy :
    Id3v24MappedFrameModificationAction,
    Id3v24UnregenerableFrameAction,
    Id3v24WriteContext,
    Id3v24WriterPolicy,
    decideId3v24MappedFrameModificationAction,
    decideId3v24UnregenerableFrameAction;


/++
Whether the canonical assertion associated with a native frame has
changed since parsing.

This is deliberately supplied to the planner rather than inferred here.
Canonical mutation tracking belongs to a later editing/diff layer.
+/
enum Id3v24CanonicalFrameMutation : ubyte
{
    unchanged,
    modified
}


/++
Concrete writer action for one existing native ID3v2.4 frame.
+/
enum Id3v24FrameWriteAction : ubyte
{
    /// Reuse the complete original physical frame bytes.
    preserveOriginal,

    /// Serialize the modified canonical value as a new native frame.
    regenerate,

    /// Omit the original native frame from the written tag.
    discard,

    /// Refuse the write because safe preservation is not possible.
    rejectWrite
}


/++
Write plan for one provenance-preserved native frame.

The canonical range is copied from the projection record so later
sequence-level planning can retain the relationship between native
frame order and canonical fields.
+/
struct Id3v24FrameWritePlan
{
    /// Mapping state produced by canonical projection.
    Id3v24CanonicalMappingStatus mappingStatus;

    /// Whether the associated canonical assertion changed.
    Id3v24CanonicalFrameMutation mutation;

    /// Writer action selected for this frame.
    Id3v24FrameWriteAction action;

    /// First associated canonical field position.
    size_t canonicalStart;

    /// Number of associated canonical fields.
    size_t canonicalCount;

    /++
    Returns whether this plan permits writing to continue.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return action !=
            Id3v24FrameWriteAction.rejectWrite;
    }
}


/++
Plans writing of one existing ID3v2.4 native frame.

Mapped and unchanged frames preserve their exact original bytes.

Mapped and modified frames may be regenerated only when native
read-only policy permits it.

Unsupported, transformation-pending and canonically unrepresentable
frames cannot currently be regenerated. They therefore use the
conservative unregenerable-frame preservation policy.

A `modified` mutation state for a non-mapped frame cannot currently be
represented by the canonical editing model and therefore rejects the
write.

Params:
    record = Native frame plus canonical projection relationship.
    mutation = Whether its canonical assertion changed.
    context = Whether the enclosing tag and/or file is being altered.
    policy = Writer preservation policy.

Returns:
    Explicit frame-level write plan.
+/
Id3v24FrameWritePlan
planId3v24CanonicalFrameWrite(
    const(Id3v24CanonicalFrameRecord) record,
    Id3v24CanonicalFrameMutation mutation,
    Id3v24WriteContext context,
    Id3v24WriterPolicy policy =
        Id3v24WriterPolicy.init
)
    @safe pure nothrow @nogc
{
    Id3v24FrameWriteAction action;

    final switch (record.status)
    {
        case Id3v24CanonicalMappingStatus.mapped:
        {
            if (
                mutation ==
                Id3v24CanonicalFrameMutation.unchanged
            )
            {
                action =
                    Id3v24FrameWriteAction
                        .preserveOriginal;

                break;
            }

            const modificationAction =
                decideId3v24MappedFrameModificationAction(
                    record.native.envelope.header
                );

            final switch (modificationAction)
            {
                case Id3v24MappedFrameModificationAction.regenerate:
                    action =
                        Id3v24FrameWriteAction
                            .regenerate;
                    break;

                case Id3v24MappedFrameModificationAction.rejectWrite:
                    action =
                        Id3v24FrameWriteAction
                            .rejectWrite;
                    break;
            }

            break;
        }

        case Id3v24CanonicalMappingStatus.unsupportedFrame:
        case Id3v24CanonicalMappingStatus.requiresTransformation:
        case Id3v24CanonicalMappingStatus.unrepresentableValueShape:
        {
            if (
                mutation ==
                Id3v24CanonicalFrameMutation.modified
            )
            {
                action =
                    Id3v24FrameWriteAction
                        .rejectWrite;

                break;
            }

            const preservationAction =
                decideId3v24UnregenerableFrameAction(
                    record.native.envelope.header,
                    context,
                    policy
                );

            final switch (preservationAction)
            {
                case Id3v24UnregenerableFrameAction.preserveOriginal:
                    action =
                        Id3v24FrameWriteAction
                            .preserveOriginal;
                    break;

                case Id3v24UnregenerableFrameAction.discard:
                    action =
                        Id3v24FrameWriteAction
                            .discard;
                    break;

                case Id3v24UnregenerableFrameAction.rejectWrite:
                    action =
                        Id3v24FrameWriteAction
                            .rejectWrite;
                    break;
            }

            break;
        }
    }

    return
        Id3v24FrameWritePlan(
            record.status,
            mutation,
            action,
            record.canonicalStart,
            record.canonicalCount
        );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

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

        auto result =
            cursor.parseId3v24FrameHeader();

        assert(result.hasValue);
        assert(cursor.empty);

        return result.value;
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


/// An unchanged mapped frame reuses its exact original representation.
unittest
{
    const record =
        testRecord(
            Id3v24CanonicalMappingStatus.mapped,
            0x00,
            4,
            1
        );

    const plan =
        planId3v24CanonicalFrameWrite(
            record,
            Id3v24CanonicalFrameMutation.unchanged,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);

    assert(
        plan.action ==
        Id3v24FrameWriteAction.preserveOriginal
    );

    assert(plan.canonicalStart == 4);
    assert(plan.canonicalCount == 1);
}


/// A modified writable mapped frame is regenerated.
unittest
{
    const record =
        testRecord(
            Id3v24CanonicalMappingStatus.mapped
        );

    const plan =
        planId3v24CanonicalFrameWrite(
            record,
            Id3v24CanonicalFrameMutation.modified,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);

    assert(
        plan.action ==
        Id3v24FrameWriteAction.regenerate
    );
}


/// A modified read-only mapped frame rejects the write.
unittest
{
    const record =
        testRecord(
            Id3v24CanonicalMappingStatus.mapped,
            0x10
        );

    const plan =
        planId3v24CanonicalFrameWrite(
            record,
            Id3v24CanonicalFrameMutation.modified,
            Id3v24WriteContext.tagOnly()
        );

    assert(!plan.writable);

    assert(
        plan.action ==
        Id3v24FrameWriteAction.rejectWrite
    );
}


/// Unsupported content without discard flags preserves original bytes.
unittest
{
    const record =
        testRecord(
            Id3v24CanonicalMappingStatus
                .unsupportedFrame
        );

    const plan =
        planId3v24CanonicalFrameWrite(
            record,
            Id3v24CanonicalFrameMutation.unchanged,
            Id3v24WriteContext.tagAndFile()
        );

    assert(plan.writable);

    assert(
        plan.action ==
        Id3v24FrameWriteAction.preserveOriginal
    );
}


/// Transformation-pending content is likewise preserved when possible.
unittest
{
    const record =
        testRecord(
            Id3v24CanonicalMappingStatus
                .requiresTransformation
        );

    const plan =
        planId3v24CanonicalFrameWrite(
            record,
            Id3v24CanonicalFrameMutation.unchanged,
            Id3v24WriteContext.tagOnly()
        );

    assert(
        plan.action ==
        Id3v24FrameWriteAction.preserveOriginal
    );
}


/// Unrepresentable semantics remain preserved when no discard is required.
unittest
{
    const record =
        testRecord(
            Id3v24CanonicalMappingStatus
                .unrepresentableValueShape
        );

    const plan =
        planId3v24CanonicalFrameWrite(
            record,
            Id3v24CanonicalFrameMutation.unchanged,
            Id3v24WriteContext.tagOnly()
        );

    assert(
        plan.action ==
        Id3v24FrameWriteAction.preserveOriginal
    );
}


/// A required discard of non-regenerable data rejects by default.
unittest
{
    const record =
        testRecord(
            Id3v24CanonicalMappingStatus
                .unsupportedFrame,
            0x40
        );

    const plan =
        planId3v24CanonicalFrameWrite(
            record,
            Id3v24CanonicalFrameMutation.unchanged,
            Id3v24WriteContext.tagOnly()
        );

    assert(!plan.writable);

    assert(
        plan.action ==
        Id3v24FrameWriteAction.rejectWrite
    );
}


/// Explicit loss policy converts a required discard into a discard plan.
unittest
{
    const record =
        testRecord(
            Id3v24CanonicalMappingStatus
                .unsupportedFrame,
            0x40
        );

    auto policy =
        Id3v24WriterPolicy.init;

    policy.requiredDiscard =
        Id3v24RequiredDiscardPolicy.discard;

    const plan =
        planId3v24CanonicalFrameWrite(
            record,
            Id3v24CanonicalFrameMutation.unchanged,
            Id3v24WriteContext.tagOnly(),
            policy
        );

    assert(plan.writable);

    assert(
        plan.action ==
        Id3v24FrameWriteAction.discard
    );
}


/// Non-mapped content cannot currently receive canonical modification.
unittest
{
    const record =
        testRecord(
            Id3v24CanonicalMappingStatus
                .requiresTransformation
        );

    const plan =
        planId3v24CanonicalFrameWrite(
            record,
            Id3v24CanonicalFrameMutation.modified,
            Id3v24WriteContext.tagOnly()
        );

    assert(!plan.writable);

    assert(
        plan.action ==
        Id3v24FrameWriteAction.rejectWrite
    );
}
