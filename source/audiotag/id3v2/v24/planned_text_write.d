/++
Execution of semantically planned ID3v2.4 ordinary text-information
frame regeneration.

This module connects the existing semantic tag write plan to the
physical TIT2/TPE1/TALB regeneration serializer.

It deliberately executes only one already-planned regeneration entry.
Whole-tag ordering, preservation of unchanged original bytes, discard
actions, new-frame insertion, tag sizing, padding and container writing
remain later layers.

Two error domains remain explicit:

- the outer `ParseResult` reports failure while re-reading structural
  information from the preserved native source frame;
- the inner `SerializationResult` reports writer/planner or output
  representation failures.

This avoids translating malformed source structure into a writer error
or writer limitations into a parser error.
+/
module audiotag.id3v2.v24.planned_text_write;

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
    Id3v24CanonicalTargetFamily;

import audiotag.id3v2.v24.frame_write_plan :
    Id3v24FrameWriteAction;

import audiotag.id3v2.v24.regeneration_policy :
    planId3v24MappedFrameRegenerationFormat;

import audiotag.id3v2.v24.tag_write_plan :
    Id3v24TagWritePlan;

import audiotag.id3v2.v24.text_information_frame_write :
    serializeRegeneratedId3v24TextInformationFrame;


/++
Result type for executing one planned ordinary text-frame regeneration.

The outer result represents preserved-source structural parsing.
The inner result represents physical serialization.
+/
alias Id3v24PlannedTextRegenerationResult =
    ParseResult!(
        SerializationResult!(ubyte[])
    );


/++
Returns a writer failure inside a successful source-structure result.

This helper is used for semantic-plan inconsistencies or unsupported
serializer families, neither of which is malformed source input.
+/
private Id3v24PlannedTextRegenerationResult
writerFailure(
    SerializationError error
)
    @safe
{
    return
        Id3v24PlannedTextRegenerationResult
            .success(
                SerializationResult!(ubyte[])
                    .failure(error)
            );
}


/++
Executes one regeneration entry from a complete semantic tag write plan.

The function verifies the links already established by planning:

- the complete tag plan is writable;
- the requested regeneration entry exists;
- its source frame still corresponds to the existing-frame `regenerate`
  action;
- its canonical source index still refers to a modified replacement;
- its serializer family is ordinary text information.

The original native frame envelope is then passed through the structural
regeneration policy. A valid writable format plan and the replacement
canonical field are finally passed to the existing complete text-frame
serializer.

Params:
    projection = Original provenance-preserving canonical projection.
    edit = Canonical edit overlay used to construct `plan`.
    plan = Complete semantic tag write plan.
    regenerationIndex = Index in `plan.regenerations`.
    sourceTagUnsynchronised = Whether source tag-level unsynchronisation
        applied to the preserved native frame.

Returns:
    Outer parse failure for invalid preserved native structure, otherwise
    an inner serialization success/failure.
+/
Id3v24PlannedTextRegenerationResult
serializeId3v24PlannedTextRegeneration(
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
     * Existing-frame sequence plans retain one entry per original native
     * frame in the same source order.
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

    if (
        regeneration.fieldPlan.target.family !=
        Id3v24CanonicalTargetFamily
            .textInformation
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .unsupportedRepresentation,
                    regeneration.sourceFrameIndex
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
            Id3v24PlannedTextRegenerationResult
                .failure(
                    formatPlan.error
                );
    }

    auto serialized =
        serializeRegeneratedId3v24TextInformationFrame(
            sourceEdit.replacement,
            formatPlan.value
        );

    return
        Id3v24PlannedTextRegenerationResult
            .success(serialized);
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
        MetadataValue;

    import audiotag.id3v2.v24.canonical_mapping :
        Id3v24CanonicalMappingResult;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.frame_data :
        parseId3v24FrameDataLayout;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrame;

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


/// A semantic TIT2 regeneration plan executes into valid replacement bytes.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            0x03,
            'O', 'r', 'i', 'g', 'i', 'n', 'a', 'l'
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            textField(
                "title",
                "Original"
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
            "Replacement"
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
        serializeId3v24PlannedTextRegeneration(
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

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.text.values ==
        ["Replacement"]
    );
}


/// Planned TPE1 regeneration retains ordered canonical artist values.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x03,
            'A', 0x00, 'B'
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            textListField(
                "artist",
                ["A", "B"]
            )
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        textListField(
            "artist",
            ["C", "D"]
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto executed =
        serializeId3v24PlannedTextRegeneration(
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
            ByteSpan(
                serialized.value[]
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);

    assert(
        decoded.value.text.values ==
        ["C", "D"]
    );
}


/// Grouping and DLI survive the complete plan-to-byte execution path.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x07,
            0x60, 0x41,

            // Grouping identity.
            0x2A,

            // Old semantic payload length = 2.
            0x00, 0x00, 0x00, 0x02,

            0x03, 'X'
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            textField(
                "title",
                "X"
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
            "Long"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto executed =
        serializeId3v24PlannedTextRegeneration(
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
            ByteSpan(
                serialized.value[],
                2000
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    assert(
        envelope.value.header.statusFlags ==
        0x60
    );

    assert(
        envelope.value.header.formatFlags ==
        0x41
    );

    /*
     * grouping 1 + DLI 4 + semantic payload 5
     */
    assert(
        envelope.value.header.size ==
        10
    );

    auto layout =
        envelope.value
            .parseId3v24FrameDataLayout();

    assert(layout.hasValue);

    assert(layout.value.hasGroupingIdentity);
    assert(layout.value.groupingIdentity == 0x2A);

    assert(layout.value.hasDataLengthIndicator);
    assert(layout.value.dataLengthIndicator == 5);

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);

    assert(
        decoded.value.text.values ==
        ["Long"]
    );
}


/// A blocked complete tag plan cannot be partially executed.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x10, 0x00,

            0x03, 'X'
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            textField(
                "title",
                "X"
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
            "Y"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(!plan.writable);

    auto executed =
        serializeId3v24PlannedTextRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);

    auto serialized =
        executed.value;

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
