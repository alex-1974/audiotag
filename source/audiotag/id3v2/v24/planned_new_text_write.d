/++
Execution of semantically planned newly introduced ID3v2.4 ordinary
text-information frames.

This module connects `Id3v24TagWritePlan.newFrames` to the physical
TIT2/TPE1/TALB serializer.

Unlike existing-frame regeneration, a new frame has no preserved native
source structure. Therefore no parser error domain is involved here;
execution returns only `SerializationResult`.

This module deliberately handles only ordinary text-information targets.
Whole-tag ordering, placement relative to preserved native frames,
padding, tag sizing and container writing remain later layers.
+/
module audiotag.id3v2.v24.planned_new_text_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.metadata.edit :
    MetadataTreeEdit;

import audiotag.id3v2.v24.canonical_target :
    Id3v24CanonicalTargetFamily;

import audiotag.id3v2.v24.new_frame_plan :
    planId3v24CanonicalField;

import audiotag.id3v2.v24.tag_write_plan :
    Id3v24TagWritePlan;

import audiotag.id3v2.v24.text_information_frame_write :
    serializeNewId3v24TextInformationFrame;


/++
Executes one planned newly introduced ordinary text-information frame.

The function verifies that:

- the complete semantic tag plan is writable;
- the requested new-frame plan exists;
- its `newFieldIndex` still refers to an existing edit-overlay field;
- the current field still produces the same canonical target plan;
- the target belongs to the ordinary text-information serializer family.

The final physical serialization is delegated to
`serializeNewId3v24TextInformationFrame`.

Params:
    edit = Canonical edit overlay used to construct `plan`.
    plan = Complete semantic ID3v2.4 tag write plan.
    newFramePlanIndex = Position in `plan.newFrames`.

Returns:
    Complete newly serialized native frame bytes or a structured writer
    failure.
+/
SerializationResult!(ubyte[])
serializeId3v24PlannedNewTextFrame(
    const(MetadataTreeEdit) edit,
    const(Id3v24TagWritePlan) plan,
    size_t newFramePlanIndex
)
    @safe
{
    /*
     * Do not partially execute a semantic plan that is already known to
     * be blocked elsewhere.
     */
    if (!plan.writable)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation
                    )
                );
    }

    if (
        newFramePlanIndex >=
        plan.newFrames.length
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidLength,
                        newFramePlanIndex,
                        newFramePlanIndex,
                        plan.newFrames.length
                    )
                );
    }

    const newFramePlan =
        plan.newFrames[
            newFramePlanIndex
        ];

    if (!newFramePlan.writable)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation,
                        newFramePlanIndex,
                        cast(ulong) newFramePlan.status
                    )
                );
    }

    const newFields =
        edit.newFields;

    if (
        newFramePlan.newFieldIndex >=
        newFields.length
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        newFramePlan.newFieldIndex,
                        newFramePlan.newFieldIndex,
                        newFields.length
                    )
                );
    }

    /*
     * Re-plan the referenced field so a plan from another edit overlay
     * cannot silently serialize unrelated metadata.
     */
    const currentFieldPlan =
        planId3v24CanonicalField(
            newFields[
                newFramePlan.newFieldIndex
            ]
        );

    if (
        !currentFieldPlan.writable ||
        currentFieldPlan.status !=
            newFramePlan.status ||
        currentFieldPlan.target.key.name !=
            newFramePlan.target.key.name ||
        currentFieldPlan.target.valueKind !=
            newFramePlan.target.valueKind ||
        currentFieldPlan.target.frameId !=
            newFramePlan.target.frameId ||
        currentFieldPlan.target.family !=
            newFramePlan.target.family
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        newFramePlan.newFieldIndex
                    )
                );
    }

    if (
        newFramePlan.target.family !=
        Id3v24CanonicalTargetFamily
            .textInformation
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation,
                        newFramePlan.newFieldIndex
                    )
                );
    }

    return
        serializeNewId3v24TextInformationFrame(
            newFields[
                newFramePlan.newFieldIndex
            ]
        );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.metadata.field :
        MetadataField,
        MetadataKey;

    import audiotag.metadata.value :
        MetadataText,
        MetadataTextList,
        MetadataUrl,
        MetadataValue;

    import audiotag.id3v2.v24.canonical_projection :
        Id3v24CanonicalProjection;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.tag_write_plan :
        planId3v24CanonicalTagWrite;

    import audiotag.id3v2.v24.text_information :
        decodeId3v24TextInformationFrame;

    import audiotag.id3v2.v24.writer_policy :
        Id3v24WriteContext;


    private MetadataField textField(
        string key,
        string value
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataText(value);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
    }


    private MetadataField textListField(
        string key,
        string[] values
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataTextList(values);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
    }


    private MetadataField urlField(
        string key,
        string value
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataUrl(value);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
    }


    private MetadataTreeEdit emptySourceEdit()
        @safe
    {
        const projection =
            Id3v24CanonicalProjection.init;

        return
            MetadataTreeEdit.forSource(
                projection.metadata
            );
    }
}


/// A planned new canonical title executes into one valid TIT2 frame.
unittest
{
    const projection =
        Id3v24CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        textField(
            "title",
            "New title"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 1);

    auto serialized =
        serializeId3v24PlannedNewTextFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[],
                1000
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.id[] ==
        "TIT2"
    );

    assert(
        envelope.value.header.statusFlags ==
        0
    );

    assert(
        envelope.value.header.formatFlags ==
        0
    );

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.text.values ==
        ["New title"]
    );
}


/// New-frame plan ordering resolves the correct edit-overlay field.
unittest
{
    const projection =
        Id3v24CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        textField(
            "title",
            "Title"
        )
    );

    edit.appendNewField(
        textListField(
            "artist",
            ["Artist A", "Artist B"]
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 2);

    assert(
        plan.newFrames[0].newFieldIndex ==
        0
    );

    assert(
        plan.newFrames[1].newFieldIndex ==
        1
    );

    auto serialized =
        serializeId3v24PlannedNewTextFrame(
            edit,
            plan,
            1
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[]
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    assert(
        envelope.value.header.id[] ==
        "TPE1"
    );

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);

    assert(
        decoded.value.text.values ==
        ["Artist A", "Artist B"]
    );
}


/// A semantically writable non-text target is rejected by this executor.
unittest
{
    const projection =
        Id3v24CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        urlField(
            "commercialUrl",
            "https://example.test/"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    /*
     * The complete semantic planner supports this target. Only this
     * physical executor is deliberately limited to text information.
     */
    assert(plan.writable);
    assert(plan.newFrameCount == 1);

    auto serialized =
        serializeId3v24PlannedNewTextFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// A blocked complete semantic tag plan cannot be partially executed.
unittest
{
    const projection =
        Id3v24CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    auto field =
        textField(
            "title",
            "Title"
        );

    field.description =
        "unsupported-in-TIT2";

    edit.appendNewField(field);

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(!plan.writable);

    auto serialized =
        serializeId3v24PlannedNewTextFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// A new-frame plan index outside the plan is reported explicitly.
unittest
{
    const projection =
        Id3v24CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        textField(
            "title",
            "Title"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto serialized =
        serializeId3v24PlannedNewTextFrame(
            edit,
            plan,
            1
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode.invalidLength
    );
}
