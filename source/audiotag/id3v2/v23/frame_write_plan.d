/++
Write planning for one provenance-preserved ID3v2.3 frame.

This module converts canonical mapping state, canonical mutation state
and writer preservation policy into one explicit frame-level write
action.

No bytes are serialized here.

ID3v2.3 tag-alter and file-alter preservation flags formally describe
how software should handle frames unknown to it. For writer planning,
a frame that cannot currently be regenerated is treated conservatively
like an unknown frame: its original bytes are preserved unless the
native preservation flags require discard, in which case policy decides
between explicit discard and rejecting the write.

Mapped frames whose canonical value has not changed retain their exact
original physical representation.
+/
module audiotag.id3v2.v23.frame_write_plan;

import audiotag.id3v2.v23.canonical_mapping :
    Id3v23CanonicalMappingStatus;

import audiotag.id3v2.v23.canonical_projection :
    Id3v23CanonicalFrameRecord;

import audiotag.id3v2.v23.writer_policy :
    Id3v23MappedFrameModificationAction,
    Id3v23UnregenerableFrameAction,
    Id3v23WriteContext,
    Id3v23WriterPolicy,
    decideId3v23MappedFrameModificationAction,
    decideId3v23UnregenerableFrameAction;


/++
Whether the canonical assertion associated with a native frame has
changed since parsing.

This is deliberately supplied to the planner rather than inferred here.
Canonical mutation tracking belongs to a later editing/diff layer.
+/
enum Id3v23CanonicalFrameMutation : ubyte
{
    unchanged,
    modified,
    removed
}


/++
Concrete writer action for one existing native ID3v2.3 frame.
+/
enum Id3v23FrameWriteAction : ubyte
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
struct Id3v23FrameWritePlan
{
    /// Mapping state produced by canonical projection.
    Id3v23CanonicalMappingStatus mappingStatus;

    /// Whether the associated canonical assertion changed.
    Id3v23CanonicalFrameMutation mutation;

    /// Writer action selected for this frame.
    Id3v23FrameWriteAction action;

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
            Id3v23FrameWriteAction.rejectWrite;
    }
}


/++
Plans writing of one existing ID3v2.3 native frame.

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
Id3v23FrameWritePlan
planId3v23CanonicalFrameWrite(
    const(Id3v23CanonicalFrameRecord) record,
    Id3v23CanonicalFrameMutation mutation,
    Id3v23WriteContext context,
    Id3v23WriterPolicy policy =
        Id3v23WriterPolicy.init
)
    @safe pure nothrow @nogc
{
    Id3v23FrameWriteAction action;

    final switch (record.status)
    {
        case Id3v23CanonicalMappingStatus.mapped:
        {
            final switch (mutation)
            {
                case Id3v23CanonicalFrameMutation.unchanged:
                    action =
                        Id3v23FrameWriteAction
                            .preserveOriginal;
                    break;

                case Id3v23CanonicalFrameMutation.modified:
                {
                    const modificationAction =
                        decideId3v23MappedFrameModificationAction(
                            record.native.envelope.header
                        );

                    final switch (modificationAction)
                    {
                        case Id3v23MappedFrameModificationAction.regenerate:
                            action =
                                Id3v23FrameWriteAction
                                    .regenerate;
                            break;

                        case Id3v23MappedFrameModificationAction.rejectWrite:
                            action =
                                Id3v23FrameWriteAction
                                    .rejectWrite;
                            break;
                    }

                    break;
                }

                case Id3v23CanonicalFrameMutation.removed:
                {
                    const modificationAction =
                        decideId3v23MappedFrameModificationAction(
                            record.native.envelope.header
                        );

                    final switch (modificationAction)
                    {
                        case Id3v23MappedFrameModificationAction.regenerate:
                            action =
                                Id3v23FrameWriteAction
                                    .discard;
                            break;

                        case Id3v23MappedFrameModificationAction.rejectWrite:
                            action =
                                Id3v23FrameWriteAction
                                    .rejectWrite;
                            break;
                    }

                    break;
                }
            }

            break;
        }

        case Id3v23CanonicalMappingStatus.unsupportedFrame:
        case Id3v23CanonicalMappingStatus.requiresTransformation:
        case Id3v23CanonicalMappingStatus.unrepresentableValueShape:
        {
            if (
                mutation !=
                Id3v23CanonicalFrameMutation.unchanged
            )
            {
                action =
                    Id3v23FrameWriteAction
                        .rejectWrite;

                break;
            }

            const preservationAction =
                decideId3v23UnregenerableFrameAction(
                    record.native.envelope.header,
                    context,
                    policy
                );

            final switch (preservationAction)
            {
                case Id3v23UnregenerableFrameAction.preserveOriginal:
                    action =
                        Id3v23FrameWriteAction
                            .preserveOriginal;
                    break;

                case Id3v23UnregenerableFrameAction.discard:
                    action =
                        Id3v23FrameWriteAction
                            .discard;
                    break;

                case Id3v23UnregenerableFrameAction.rejectWrite:
                    action =
                        Id3v23FrameWriteAction
                            .rejectWrite;
                    break;
            }

            break;
        }
    }

    return
        Id3v23FrameWritePlan(
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

        auto result =
            cursor.parseId3v23FrameHeader();

        assert(result.hasValue);
        assert(cursor.empty);

        return result.value;
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


/// An unchanged mapped frame reuses its exact original representation.
unittest
{
    const record =
        testRecord(
            Id3v23CanonicalMappingStatus.mapped,
            0x00,
            4,
            1
        );

    const plan =
        planId3v23CanonicalFrameWrite(
            record,
            Id3v23CanonicalFrameMutation.unchanged,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    assert(
        plan.action ==
        Id3v23FrameWriteAction.preserveOriginal
    );

    assert(plan.canonicalStart == 4);
    assert(plan.canonicalCount == 1);
}


/// A modified writable mapped frame is regenerated.
unittest
{
    const record =
        testRecord(
            Id3v23CanonicalMappingStatus.mapped
        );

    const plan =
        planId3v23CanonicalFrameWrite(
            record,
            Id3v23CanonicalFrameMutation.modified,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    assert(
        plan.action ==
        Id3v23FrameWriteAction.regenerate
    );
}


/// A modified read-only mapped frame rejects the write.
unittest
{
    const record =
        testRecord(
            Id3v23CanonicalMappingStatus.mapped,
            0x20
        );

    const plan =
        planId3v23CanonicalFrameWrite(
            record,
            Id3v23CanonicalFrameMutation.modified,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);

    assert(
        plan.action ==
        Id3v23FrameWriteAction.rejectWrite
    );
}


/// Unsupported content without discard flags preserves original bytes.
unittest
{
    const record =
        testRecord(
            Id3v23CanonicalMappingStatus
                .unsupportedFrame
        );

    const plan =
        planId3v23CanonicalFrameWrite(
            record,
            Id3v23CanonicalFrameMutation.unchanged,
            Id3v23WriteContext.tagAndFile()
        );

    assert(plan.writable);

    assert(
        plan.action ==
        Id3v23FrameWriteAction.preserveOriginal
    );
}


/// Transformation-pending content is likewise preserved when possible.
unittest
{
    const record =
        testRecord(
            Id3v23CanonicalMappingStatus
                .requiresTransformation
        );

    const plan =
        planId3v23CanonicalFrameWrite(
            record,
            Id3v23CanonicalFrameMutation.unchanged,
            Id3v23WriteContext.tagOnly()
        );

    assert(
        plan.action ==
        Id3v23FrameWriteAction.preserveOriginal
    );
}


/// Unrepresentable semantics remain preserved when no discard is required.
unittest
{
    const record =
        testRecord(
            Id3v23CanonicalMappingStatus
                .unrepresentableValueShape
        );

    const plan =
        planId3v23CanonicalFrameWrite(
            record,
            Id3v23CanonicalFrameMutation.unchanged,
            Id3v23WriteContext.tagOnly()
        );

    assert(
        plan.action ==
        Id3v23FrameWriteAction.preserveOriginal
    );
}


/// A required discard of non-regenerable data rejects by default.
unittest
{
    const record =
        testRecord(
            Id3v23CanonicalMappingStatus
                .unsupportedFrame,
            0x80
        );

    const plan =
        planId3v23CanonicalFrameWrite(
            record,
            Id3v23CanonicalFrameMutation.unchanged,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);

    assert(
        plan.action ==
        Id3v23FrameWriteAction.rejectWrite
    );
}


/// Explicit loss policy converts a required discard into a discard plan.
unittest
{
    const record =
        testRecord(
            Id3v23CanonicalMappingStatus
                .unsupportedFrame,
            0x80
        );

    auto policy =
        Id3v23WriterPolicy.init;

    policy.requiredDiscard =
        Id3v23RequiredDiscardPolicy.discard;

    const plan =
        planId3v23CanonicalFrameWrite(
            record,
            Id3v23CanonicalFrameMutation.unchanged,
            Id3v23WriteContext.tagOnly(),
            policy
        );

    assert(plan.writable);

    assert(
        plan.action ==
        Id3v23FrameWriteAction.discard
    );
}


/// Non-mapped content cannot currently receive canonical modification.
unittest
{
    const record =
        testRecord(
            Id3v23CanonicalMappingStatus
                .requiresTransformation
        );

    const plan =
        planId3v23CanonicalFrameWrite(
            record,
            Id3v23CanonicalFrameMutation.modified,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);

    assert(
        plan.action ==
        Id3v23FrameWriteAction.rejectWrite
    );
}


/// Removing a writable mapped field discards its original native frame.
unittest
{
    const record =
        testRecord(
            Id3v23CanonicalMappingStatus.mapped
        );

    const plan =
        planId3v23CanonicalFrameWrite(
            record,
            Id3v23CanonicalFrameMutation.removed,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    assert(
        plan.action ==
        Id3v23FrameWriteAction.discard
    );
}


/// Removing a native read-only mapped field rejects the write.
unittest
{
    const record =
        testRecord(
            Id3v23CanonicalMappingStatus.mapped,
            0x20
        );

    const plan =
        planId3v23CanonicalFrameWrite(
            record,
            Id3v23CanonicalFrameMutation.removed,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);

    assert(
        plan.action ==
        Id3v23FrameWriteAction.rejectWrite
    );
}
