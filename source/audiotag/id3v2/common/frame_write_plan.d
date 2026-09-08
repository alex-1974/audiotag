/++
Format-independent write planning for one existing ID3v2 native frame.

ID3v2 revisions retain their own concrete mapping, mutation, action and
frame-plan types. This module contains only the decision algorithm shared
by those revisions.

Revision-specific native status bits have already been interpreted by
their frame-header types. Writer decisions therefore consume only the
semantic header properties used by the common writer policy.

No bytes are emitted here.
+/
module audiotag.id3v2.common.frame_write_plan;

import audiotag.id3v2.common.writer_policy :
    Id3v2MappedFrameModificationAction,
    Id3v2UnregenerableFrameAction,
    Id3v2WriteContext,
    Id3v2WriterPolicy,
    decideId3v2MappedFrameModificationAction,
    decideId3v2UnregenerableFrameAction;


/++
Plans writing of one existing ID3v2 native frame.

The concrete revision supplies:

- `Plan`: revision-specific frame write-plan struct;
- `Action`: revision-specific frame write-action enum;
- `MappingStatus`: revision-specific canonical mapping enum.

The record type is inferred and must expose:

- `status`;
- `native.envelope.header`;
- `canonicalStart`;
- `canonicalCount`.

The mutation type is inferred and must expose:

- `unchanged`;
- `modified`;
- `removed`.

Params:
    record = Native frame plus canonical projection relationship.
    mutation = Whether its canonical assertion changed.
    context = Whether the enclosing tag and/or file is being altered.
    policy = Writer preservation policy.

Returns:
    Concrete revision-specific frame-level write plan.
+/
Plan
planId3v2CanonicalFrameWrite(
    Plan,
    Action,
    MappingStatus,
    Record,
    Mutation
)(
    const(Record) record,
    Mutation mutation,
    Id3v2WriteContext context,
    Id3v2WriterPolicy policy =
        Id3v2WriterPolicy.init
)
    @safe pure nothrow @nogc
{
    Action action;

    final switch (record.status)
    {
        case MappingStatus.mapped:
        {
            final switch (mutation)
            {
                case Mutation.unchanged:
                    action =
                        Action.preserveOriginal;
                    break;

                case Mutation.modified:
                {
                    const modificationAction =
                        decideId3v2MappedFrameModificationAction(
                            record.native.envelope.header
                        );

                    final switch (modificationAction)
                    {
                        case Id3v2MappedFrameModificationAction.regenerate:
                            action =
                                Action.regenerate;
                            break;

                        case Id3v2MappedFrameModificationAction.rejectWrite:
                            action =
                                Action.rejectWrite;
                            break;
                    }

                    break;
                }

                case Mutation.removed:
                {
                    const modificationAction =
                        decideId3v2MappedFrameModificationAction(
                            record.native.envelope.header
                        );

                    final switch (modificationAction)
                    {
                        case Id3v2MappedFrameModificationAction.regenerate:
                            action =
                                Action.discard;
                            break;

                        case Id3v2MappedFrameModificationAction.rejectWrite:
                            action =
                                Action.rejectWrite;
                            break;
                    }

                    break;
                }
            }

            break;
        }

        case MappingStatus.unsupportedFrame:
        case MappingStatus.requiresTransformation:
        case MappingStatus.unrepresentableValueShape:
        {
            if (
                mutation !=
                Mutation.unchanged
            )
            {
                action =
                    Action.rejectWrite;

                break;
            }

            const preservationAction =
                decideId3v2UnregenerableFrameAction(
                    record.native.envelope.header,
                    context,
                    policy
                );

            final switch (preservationAction)
            {
                case Id3v2UnregenerableFrameAction.preserveOriginal:
                    action =
                        Action.preserveOriginal;
                    break;

                case Id3v2UnregenerableFrameAction.discard:
                    action =
                        Action.discard;
                    break;

                case Id3v2UnregenerableFrameAction.rejectWrite:
                    action =
                        Action.rejectWrite;
                    break;
            }

            break;
        }
    }

    return
        Plan(
            record.status,
            mutation,
            action,
            record.canonicalStart,
            record.canonicalCount
        );
}
