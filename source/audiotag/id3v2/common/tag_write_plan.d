/++
Common semantic write planning for an edited ID3v2 tag.

Revision-specific modules retain their concrete projection, frame-plan,
regeneration-plan, new-frame-plan and tag-plan types. A small traits
binding supplies those types and the revision-specific planning
functions to the shared orchestration algorithm.

No bytes are emitted here.
+/
module audiotag.id3v2.common.tag_write_plan;

import audiotag.metadata.edit :
    MetadataSourceFieldEditState,
    MetadataTreeEdit;

import audiotag.metadata.edit_validation :
    validateMetadataTreeEditMultiplicity;

import audiotag.id3v2.common.writer_policy :
    Id3v2WriteContext,
    Id3v2WriterPolicy;


/++
Plans regeneration of one modified existing native frame.

Current implemented canonical mappings are one-native-frame to
one-canonical-field. Any other shape is rejected explicitly until a
corresponding regeneration model exists.
+/
private Traits.ExistingFrameRegenerationPlan
planId3v2ExistingFrameRegeneration(Traits)(
    size_t sourceFrameIndex,
    const(Traits.CanonicalFrameRecord) record,
    const(MetadataTreeEdit) edit
)
    @safe
{
    if (record.canonicalCount != 1)
    {
        return
            Traits.ExistingFrameRegenerationPlan(
                sourceFrameIndex,
                record.canonicalStart,
                Traits.ExistingFrameRegenerationStatus
                    .unsupportedCanonicalShape,
                Traits.CanonicalFieldPlan.init
            );
    }

    const canonicalSourceIndex =
        record.canonicalStart;

    const sourceEdit =
        edit.sourceEdit(
            canonicalSourceIndex
        );

    /*
     * With exactly one canonical field, a modified native-frame
     * mutation can only arise from a canonical replacement.
     *
     * A removed field derives `removed`, and an unchanged field derives
     * `unchanged`. Any other state is therefore an internal planner
     * inconsistency.
     */
    assert(
        sourceEdit.state ==
        MetadataSourceFieldEditState.modified
    );

    const fieldPlan =
        Traits.planCanonicalField(
            sourceEdit.replacement
        );

    return
        Traits.ExistingFrameRegenerationPlan(
            sourceFrameIndex,
            canonicalSourceIndex,
            fieldPlan.writable
                ? Traits.ExistingFrameRegenerationStatus.ready
                : Traits.ExistingFrameRegenerationStatus
                    .unrepresentableField,
            fieldPlan
        );
}


/++
Plans the complete semantic write of one edited ID3v2 tag.

The revision traits bind the concrete plan types and revision-specific
planning functions while this function owns their common orchestration.

Params:
    projection = Canonical projection of the parsed native tag.
    edit = Canonical edit overlay.
    context = Whether the enclosing tag and/or file is being altered.
    policy = Native preservation policy.

Returns:
    Concrete revision-specific semantic tag write plan.
+/
Traits.TagWritePlan
planId3v2CanonicalTagWrite(Traits)(
    const(Traits.CanonicalProjection) projection,
    const(MetadataTreeEdit) edit,
    Id3v2WriteContext context,
    Id3v2WriterPolicy policy =
        Id3v2WriterPolicy.init
)
    @safe
{
    const source =
        projection.metadata;

    assert(
        edit.sourceFieldCount ==
        source.length
    );

    auto result =
        Traits.TagWritePlan.init;

    result.multiplicity =
        validateMetadataTreeEditMultiplicity(
            source,
            edit
        );

    const mutations =
        Traits.deriveMutations(
            projection.frames,
            edit
        );

    result.existingFrames =
        Traits.planExistingSequence(
            projection.frames,
            mutations,
            context,
            policy
        );

    foreach (
        sourceFrameIndex,
        ref const record;
        projection.frames
    )
    {
        if (
            mutations[sourceFrameIndex] !=
            Traits.CanonicalFrameMutation.modified
        )
        {
            continue;
        }

        result.appendRegeneration(
            planId3v2ExistingFrameRegeneration!Traits(
                sourceFrameIndex,
                record,
                edit
            )
        );
    }

    foreach (
        newFieldIndex,
        ref const field;
        edit.newFields
    )
    {
        result.appendNewFrame(
            Traits.planNewFrame(
                newFieldIndex,
                field
            )
        );
    }

    return result;
}
