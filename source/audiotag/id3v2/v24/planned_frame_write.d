/++
Generic execution of semantically planned ID3v2.4 frame serialization.

This module is the family-dispatch layer between semantic tag-write
planning and concrete native frame serializers.

Currently executable canonical target families:

- ordinary text information (`T***`);
- ordinary URL links (`W***`, excluding `WXXX`).

Existing-frame regeneration retains the two explicit error domains used
by the earlier text-only executor:

- outer `ParseResult`: malformed preserved source-frame structure;
- inner `SerializationResult`: writer/planner/output failure.

New frames have no preserved source structure and therefore return only
`SerializationResult`.

Unsupported but semantically valid target families remain explicit
`unsupportedRepresentation` results. They are never silently omitted.

The older text-specific planned executors remain available. This module
provides the generalized execution path that later frame-sequence
assembly will use.
+/
module audiotag.id3v2.v24.planned_frame_write;

import audiotag.core.result :
    ParseResult;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.metadata.edit :
    MetadataSourceFieldEditState,
    MetadataTreeEdit;

import audiotag.id3v2.v24.canonical_projection :
    Id3v24CanonicalProjection;

import audiotag.id3v2.v24.canonical_target :
    Id3v24CanonicalTargetDefinition,
    Id3v24CanonicalTargetFamily;

import audiotag.id3v2.v24.frame_write_plan :
    Id3v24FrameWriteAction;

import audiotag.id3v2.v24.new_frame_plan :
    Id3v24CanonicalFieldPlan,
    planId3v24CanonicalField;

import audiotag.id3v2.v24.regeneration_policy :
    planId3v24MappedFrameRegenerationFormat;

import audiotag.id3v2.v24.tag_write_plan :
    Id3v24TagWritePlan;

import audiotag.id3v2.v24.text_information_frame_write :
    serializeNewId3v24TextInformationFrame,
    serializeRegeneratedId3v24TextInformationFrame;

import audiotag.id3v2.v24.url_link_frame_write :
    serializeNewId3v24UrlLinkFrame,
    serializeRegeneratedId3v24UrlLinkFrame;


/++
Result type for executing one planned existing-frame regeneration.

The outer result represents preserved-source structural parsing.
The inner result represents physical serialization.
+/
alias Id3v24PlannedRegenerationResult =
    ParseResult!(
        SerializationResult!(ubyte[])
    );


/++
Wraps a writer failure without converting it into a parse failure.
+/
private Id3v24PlannedRegenerationResult
writerFailure(
    SerializationError error
)
    @safe
{
    return
        Id3v24PlannedRegenerationResult
            .success(
                SerializationResult!(ubyte[])
                    .failure(error)
            );
}


/++
Returns whether two canonical target definitions identify the same
planned native representation.

This is used defensively when executing a plan against an edit overlay:
a plan constructed from another or subsequently changed edit must not
silently serialize unrelated metadata.
+/
private bool
sameTarget(
    const(Id3v24CanonicalTargetDefinition) first,
    const(Id3v24CanonicalTargetDefinition) second
)
    @safe pure nothrow @nogc
{
    return
        first.key.name ==
            second.key.name &&
        first.valueKind ==
            second.valueKind &&
        first.frameId ==
            second.frameId &&
        first.family ==
            second.family;
}


/++
Returns whether a freshly planned canonical field still matches the
stored semantic field plan.
+/
private bool
sameFieldPlan(
    const(Id3v24CanonicalFieldPlan) current,
    const(Id3v24CanonicalFieldPlan) stored
)
    @safe pure nothrow @nogc
{
    return
        current.status ==
            stored.status &&
        sameTarget(
            current.target,
            stored.target
        );
}


/++
Executes one planned existing-frame regeneration.

The function validates all relationships established during semantic
planning before dispatching to a concrete family serializer:

- the complete tag plan is writable;
- the regeneration index exists;
- source-frame and canonical-source indices remain in range;
- the existing-frame action is still `regenerate`;
- the source frame still maps to exactly the planned canonical field;
- the corresponding source edit is still `modified`;
- re-planning the replacement produces the same target;
- the preserved source frame yields a writable structural regeneration
  format plan.

Currently `textInformation` and `urlLink` are physically executable.
Other semantically valid families return `unsupportedRepresentation`.

Params:
    projection = Original provenance-preserving canonical projection.
    edit = Canonical edit overlay used to construct `plan`.
    plan = Complete semantic tag write plan.
    regenerationIndex = Index in `plan.regenerations`.
    sourceTagUnsynchronised = Whether source tag-level unsynchronisation
        applied while parsing the preserved native frame.

Returns:
    Outer parse failure for malformed preserved native structure;
    otherwise inner physical serialization success/failure.
+/
Id3v24PlannedRegenerationResult
serializeId3v24PlannedRegeneration(
    const(Id3v24CanonicalProjection) projection,
    const(MetadataTreeEdit) edit,
    const(Id3v24TagWritePlan) plan,
    size_t regenerationIndex,
    bool sourceTagUnsynchronised = false
)
    @safe
{
    if (!plan.writable)
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .unsupportedRepresentation
                )
            );
    }

    if (
        regenerationIndex >=
        plan.regenerations.length
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .invalidLength,
                    regenerationIndex,
                    regenerationIndex,
                    plan.regenerations.length
                )
            );
    }

    const regeneration =
        plan.regenerations[
            regenerationIndex
        ];

    if (!regeneration.writable)
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .unsupportedRepresentation,
                    regenerationIndex,
                    cast(ulong) regeneration.status
                )
            );
    }

    if (
        regeneration.sourceFrameIndex >=
        projection.frames.length
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    regeneration.sourceFrameIndex,
                    regeneration.sourceFrameIndex,
                    projection.frames.length
                )
            );
    }

    if (
        regeneration.canonicalSourceIndex >=
        edit.sourceFieldCount
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    regeneration.canonicalSourceIndex,
                    regeneration.canonicalSourceIndex,
                    edit.sourceFieldCount
                )
            );
    }

    /*
     * Existing-frame sequence plans contain one source-ordered entry for
     * every preserved native frame.
     */
    if (
        regeneration.sourceFrameIndex >=
        plan.existingFrames.entries.length
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    regeneration.sourceFrameIndex
                )
            );
    }

    const existingEntry =
        plan.existingFrames.entries[
            regeneration.sourceFrameIndex
        ];

    if (
        existingEntry.sourceFrameIndex !=
            regeneration.sourceFrameIndex ||
        existingEntry.plan.action !=
            Id3v24FrameWriteAction.regenerate
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    regeneration.sourceFrameIndex
                )
            );
    }

    const record =
        projection.frames[
            regeneration.sourceFrameIndex
        ];

    if (
        record.canonicalCount != 1 ||
        record.canonicalStart !=
            regeneration.canonicalSourceIndex
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    regeneration.sourceFrameIndex
                )
            );
    }

    const sourceEdit =
        edit.sourceEdit(
            regeneration.canonicalSourceIndex
        );

    if (
        sourceEdit.state !=
        MetadataSourceFieldEditState.modified
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    regeneration.canonicalSourceIndex
                )
            );
    }

    /*
     * Re-plan the current replacement so a semantic plan from another or
     * changed edit overlay cannot select a serializer using stale target
     * information.
     */
    const currentFieldPlan =
        planId3v24CanonicalField(
            sourceEdit.replacement
        );

    if (
        !currentFieldPlan.writable ||
        !sameFieldPlan(
            currentFieldPlan,
            regeneration.fieldPlan
        )
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    regeneration.canonicalSourceIndex
                )
            );
    }

    auto formatPlan =
        planId3v24MappedFrameRegenerationFormat(
            record.native.envelope,
            sourceTagUnsynchronised
        );

    if (formatPlan.hasError)
    {
        return
            Id3v24PlannedRegenerationResult
                .failure(
                    formatPlan.error
                );
    }

    SerializationResult!(ubyte[]) serialized;

    switch (
        regeneration.fieldPlan.target.family
    )
    {
        case Id3v24CanonicalTargetFamily
            .textInformation:
        {
            serialized =
                serializeRegeneratedId3v24TextInformationFrame(
                    sourceEdit.replacement,
                    formatPlan.value
                );

            break;
        }

        case Id3v24CanonicalTargetFamily
            .urlLink:
        {
            serialized =
                serializeRegeneratedId3v24UrlLinkFrame(
                    sourceEdit.replacement,
                    formatPlan.value
                );

            break;
        }

        default:
        {
            serialized =
                SerializationResult!(ubyte[])
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            regeneration.sourceFrameIndex,
                            cast(ulong)
                                regeneration
                                    .fieldPlan
                                    .target
                                    .family
                        )
                    );

            break;
        }
    }

    return
        Id3v24PlannedRegenerationResult
            .success(serialized);
}


/++
Executes one planned newly introduced canonical frame.

The function validates that the supplied semantic plan still refers to
the same canonical edit field before selecting the concrete serializer.

Currently `textInformation` and `urlLink` are physically executable.
Other semantically valid families return `unsupportedRepresentation`.

Params:
    edit = Canonical edit overlay used to construct `plan`.
    plan = Complete semantic tag write plan.
    newFramePlanIndex = Position in `plan.newFrames`.

Returns:
    Complete new native frame bytes or a structured writer failure.
+/
SerializationResult!(ubyte[])
serializeId3v24PlannedNewFrame(
    const(MetadataTreeEdit) edit,
    const(Id3v24TagWritePlan) plan,
    size_t newFramePlanIndex
)
    @safe
{
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
        !sameTarget(
            currentFieldPlan.target,
            newFramePlan.target
        )
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

    switch (newFramePlan.target.family)
    {
        case Id3v24CanonicalTargetFamily
            .textInformation:
            return
                serializeNewId3v24TextInformationFrame(
                    newFields[
                        newFramePlan.newFieldIndex
                    ]
                );

        case Id3v24CanonicalTargetFamily
            .urlLink:
            return
                serializeNewId3v24UrlLinkFrame(
                    newFields[
                        newFramePlan.newFieldIndex
                    ]
                );

        default:
            return
                SerializationResult!(ubyte[])
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            newFramePlan.newFieldIndex,
                            cast(ulong)
                                newFramePlan.target.family
                        )
                    );
    }
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
        MetadataUrl,
        MetadataValue;

    import audiotag.id3v2.v24.canonical_mapping :
        Id3v24CanonicalMappingResult;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrame;

    import audiotag.id3v2.v24.tag_write_plan :
        planId3v24CanonicalTagWrite;

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


    private Id3v24CanonicalProjection
    projectionWithMappedFrame(
        const(ubyte)[] bytes,
        MetadataField mappedField
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto envelope =
            cursor.parseId3v24FrameEnvelope();

        assert(envelope.hasValue);
        assert(cursor.empty);

        auto native =
            Id3v24NativeFrame.init;

        native.envelope =
            envelope.value;

        auto projection =
            Id3v24CanonicalProjection.init;

        projection.append(
            native,
            Id3v24CanonicalMappingResult
                .success(mappedField)
        );

        return projection;
    }
}


/// A planned new title dispatches through the ordinary text serializer.
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
            "New"
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
        serializeId3v24PlannedNewFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    assert(frame.value.header.id[] == "TIT2");

    assert(
        frame.value.data.data ==
        [
            0x03,
            'N', 'e', 'w'
        ]
    );
}


/// A planned new ordinary URL dispatches through the W*** serializer.
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

    assert(plan.writable);

    auto serialized =
        serializeId3v24PlannedNewFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    assert(frame.value.header.id[] == "WCOM");

    assert(
        frame.value.data.data ==
        cast(const(ubyte)[])
            "https://example.test/"
    );
}


/// A modified mapped text frame dispatches to text regeneration.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,
            0x03, 'O', 'l', 'd'
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            textField(
                "title",
                "Old"
            )
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        textField(
            "title",
            "New"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.regenerationCount == 1);

    auto executed =
        serializeId3v24PlannedRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);

    auto serialized =
        executed.value;

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    assert(frame.value.header.id[] == "TIT2");

    assert(
        frame.value.data.data ==
        [
            0x03,
            'N', 'e', 'w'
        ]
    );
}


/// A modified mapped ordinary URL dispatches to URL regeneration.
unittest
{
    const ubyte[] sourceBytes =
        [
            'W', 'C', 'O', 'M',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,
            'o', 'l', 'd'
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            urlField(
                "commercialUrl",
                "old"
            )
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        urlField(
            "commercialUrl",
            "new"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.regenerationCount == 1);

    auto executed =
        serializeId3v24PlannedRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);

    auto serialized =
        executed.value;

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    assert(frame.value.header.id[] == "WCOM");

    assert(
        frame.value.data.data ==
        cast(const(ubyte)[]) "new"
    );
}


/// Semantically valid but not yet executable families remain explicit.
unittest
{
    const projection =
        Id3v24CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    /*
     * TXXX is already semantically planned but does not yet have a
     * physical writer in the generic dispatcher.
     */
    edit.appendNewField(
        textField(
            "userText",
            "value"
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
        serializeId3v24PlannedNewFrame(
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


/// Out-of-range planned-frame indices remain structured writer failures.
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
            "x"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    auto serialized =
        serializeId3v24PlannedNewFrame(
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
