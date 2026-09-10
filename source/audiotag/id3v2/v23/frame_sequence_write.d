/++
Logical assembly of a planned ID3v2.3 frame sequence.

This module executes all existing-frame actions of
`Id3v23TagWritePlan` together:

- `preserveOriginal` emits the unchanged native frame representation;
- `regenerate` executes the planned canonical frame regeneration;
- `discard` emits no bytes;
- `rejectWrite` blocks serialization.

Surviving existing frames retain original native order. Newly
introduced canonical frames are appended afterwards in
`Id3v23TagWritePlan.newFrames` order.

The assembler always produces one ordinary logical/native frame
sequence.

For a whole-tag-unsynchronised source:

- preserved frames reconstruct their logical native bytes;
- regenerated frames parse preserved source structure through the
  corresponding logical unsynchronisation state;
- newly introduced frames already produce ordinary logical/native bytes.

ID3v2.3 whole-tag unsynchronisation is applied later, once, to the
complete resulting tag body.

No tag header, extended header, padding or container bytes are
serialized here.
+/
module audiotag.id3v2.v23.frame_sequence_write;

import audiotag.core.result :
    ParseResult;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.metadata.edit :
    MetadataTreeEdit;

import audiotag.id3v2.v23.canonical_projection :
    Id3v23CanonicalProjection;

import audiotag.id3v2.v23.frame_preserve_write :
    serializePreservedId3v23Frame;

import audiotag.id3v2.v23.frame_write_plan :
    Id3v23FrameWriteAction;

import audiotag.id3v2.v23.recording_time_frame_write :
    serializeNewId3v23RecordingTimeComponentFrame,
    serializeRegeneratedId3v23RecordingTimeComponentFrame;

import audiotag.id3v2.v23.recording_time_group_write_plan :
    Id3v23RecordingTimeComponentWriteAction,
    Id3v23RecordingTimeComponentWritePlan,
    Id3v23RecordingTimeGroupWritePlan,
    Id3v23RecordingTimeGroupWriteStatus;

import audiotag.id3v2.v23.regeneration_policy :
    planId3v23MappedFrameRegenerationFormat;

import audiotag.id3v2.v23.planned_frame_write :
    serializeId3v23PlannedNewFrame,
    serializeId3v23PlannedRegeneration;

import audiotag.id3v2.v23.tag_write_plan :
    Id3v23TagWritePlan;


/++
Result of assembling one complete currently supported ID3v2.3 frame
sequence.

The outer parse result retains source-structure failures which may occur
while executing regeneration of an existing native frame.

The inner serialization result retains writer, planner and output
failures.
+/
alias Id3v23FrameSequenceSerializationResult =
    ParseResult!(
        SerializationResult!(ubyte[])
    );


/++
Wraps a writer failure without misclassifying it as malformed source
input.
+/
private Id3v23FrameSequenceSerializationResult
writerFailure(
    SerializationError error
)
    @safe
{
    return
        Id3v23FrameSequenceSerializationResult
            .success(
                SerializationResult!(ubyte[])
                    .failure(error)
            );
}


/++
Appends one complete serialized frame to the locally assembled sequence.
+/
private void appendFrameBytes(
    ref ubyte[] output,
    const(ubyte)[] frame
)
    @safe
{
    output ~= frame;
}


private struct RecordingTimeComponentLookup
{
    bool found;
    Id3v23RecordingTimeComponentWritePlan plan;
}


private RecordingTimeComponentLookup
findRecordingTimeSourceComponent(
    const(Id3v23RecordingTimeGroupWritePlan) group,
    size_t sourceFrameIndex
)
    @safe pure nothrow @nogc
{
    if (group.year.hasSourceFrame &&
        group.year.sourceFrameIndex == sourceFrameIndex)
        return RecordingTimeComponentLookup(true, group.year);

    if (group.date.hasSourceFrame &&
        group.date.sourceFrameIndex == sourceFrameIndex)
        return RecordingTimeComponentLookup(true, group.date);

    if (group.time.hasSourceFrame &&
        group.time.sourceFrameIndex == sourceFrameIndex)
        return RecordingTimeComponentLookup(true, group.time);

    return RecordingTimeComponentLookup.init;
}


private Id3v23FrameWriteAction
sourceFrameActionFor(
    Id3v23RecordingTimeComponentWriteAction action
)
    @safe pure nothrow @nogc
{
    final switch (action)
    {
        case Id3v23RecordingTimeComponentWriteAction.preserveOriginal:
            return Id3v23FrameWriteAction.preserveOriginal;
        case Id3v23RecordingTimeComponentWriteAction.regenerateExisting:
            return Id3v23FrameWriteAction.regenerate;
        case Id3v23RecordingTimeComponentWriteAction.discardExisting:
            return Id3v23FrameWriteAction.discard;
        case Id3v23RecordingTimeComponentWriteAction.rejectWrite:
            return Id3v23FrameWriteAction.rejectWrite;
        case Id3v23RecordingTimeComponentWriteAction.absent:
        case Id3v23RecordingTimeComponentWriteAction.appendNew:
            assert(false);
    }
}


private size_t
lastRecordingTimeSourceFrameIndex(
    const(Id3v23RecordingTimeGroupWritePlan) group
)
    @safe pure nothrow @nogc
{
    bool found;
    size_t result;

    if (group.year.hasSourceFrame)
    {
        found = true;
        result = group.year.sourceFrameIndex;
    }

    if (group.date.hasSourceFrame &&
        (!found || group.date.sourceFrameIndex > result))
    {
        found = true;
        result = group.date.sourceFrameIndex;
    }

    if (group.time.hasSourceFrame &&
        (!found || group.time.sourceFrameIndex > result))
    {
        found = true;
        result = group.time.sourceFrameIndex;
    }

    assert(found);
    return result;
}


private SerializationResult!(ubyte[])
serializeAppendedRecordingTimeComponents(
    const(Id3v23RecordingTimeGroupWritePlan) group
)
    @safe
{
    if (!group.writable)
    {
        return SerializationResult!(ubyte[]).failure(
            SerializationError(
                SerializationErrorCode.unsupportedRepresentation
            )
        );
    }

    ubyte[] output;

    const components =
        [group.year, group.date, group.time];

    foreach (const component; components)
    {
        if (component.action !=
            Id3v23RecordingTimeComponentWriteAction.appendNew)
            continue;

        auto serialized =
            serializeNewId3v23RecordingTimeComponentFrame(
                component.component,
                component.value
            );

        if (serialized.hasError)
            return SerializationResult!(ubyte[]).failure(serialized.error);

        output ~= serialized.value;
    }

    return SerializationResult!(ubyte[]).success(output);
}


/++
Assembles all currently supported frame output for one semantic
ID3v2.3 tag-write plan.

Existing frames retain original native order. A regenerated frame
occupies the same sequence position as its source frame. Discarded
frames contribute no bytes.

New fields currently have no native insertion point in
`MetadataTreeEdit`, so they are appended after all surviving source
frames while retaining `plan.newFrames` order.

Params:
    projection = Original native-plus-canonical projection.
    edit = Canonical edit overlay used to construct `plan`.
    plan = Complete semantic tag-write plan.
    sourceTagUnsynchronised = Whether preserved source frames were
        parsed from an ID3v2.3 tag using whole-tag unsynchronisation.

Returns:
    Complete concatenated frame bytes, an outer preserved-source parse
    failure, or an inner serialization failure.
+/
Id3v23FrameSequenceSerializationResult
serializeId3v23PlannedFrameSequence(
    const(Id3v23CanonicalProjection) projection,
    const(MetadataTreeEdit) edit,
    const(Id3v23TagWritePlan) plan,
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
        plan.existingFrames.length !=
        projection.frames.length
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    plan.existingFrames.length,
                    plan.existingFrames.length,
                    projection.frames.length
                )
            );
    }

    if (
        plan.newFrames.length +
            plan.newRecordingTimeGroups.length !=
        edit.newFields.length
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    plan.newFrames.length +
                        plan.newRecordingTimeGroups.length,
                    plan.newFrames.length +
                        plan.newRecordingTimeGroups.length,
                    edit.newFields.length
                )
            );
    }

    ubyte[] output;

    /*
     * Existing-frame entries are produced by sequence planning in
     * source-native order.
     *
     * Verify that relationship defensively rather than relying on it
     * silently during physical execution.
     */
    foreach (
        sequenceIndex,
        const entry;
        plan.existingFrames.entries
    )
    {
        if (
            entry.sourceFrameIndex !=
            sequenceIndex
        )
        {
            return
                writerFailure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        sequenceIndex,
                        entry.sourceFrameIndex,
                        projection.frames.length
                    )
                );
        }

        if (
            entry.sourceFrameIndex >=
            projection.frames.length
        )
        {
            return
                writerFailure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        entry.sourceFrameIndex,
                        entry.sourceFrameIndex,
                        projection.frames.length
                    )
                );
        }

        const recordingTime =
            findRecordingTimeSourceComponent(
                plan.recordingTimeGroup,
                entry.sourceFrameIndex
            );

        if (
            recordingTime.found &&
            sourceFrameActionFor(recordingTime.plan.action) !=
                entry.plan.action
        )
        {
            return
                writerFailure(
                    SerializationError(
                        SerializationErrorCode.inconsistentStructure,
                        entry.sourceFrameIndex
                    )
                );
        }

        final switch (entry.plan.action)
        {
            case Id3v23FrameWriteAction
                .preserveOriginal:
            {
                auto serialized =
                    serializePreservedId3v23Frame(
                        projection.frames[
                            entry.sourceFrameIndex
                        ].native.envelope,
                        sourceTagUnsynchronised
                    );

                if (serialized.hasError)
                {
                    return
                        writerFailure(
                            serialized.error
                        );
                }

                appendFrameBytes(
                    output,
                    serialized.value
                );

                break;
            }

            case Id3v23FrameWriteAction
                .regenerate:
            {
                if (recordingTime.found)
                {
                    auto formatPlan =
                        planId3v23MappedFrameRegenerationFormat(
                            projection.frames[
                                entry.sourceFrameIndex
                            ].native.envelope,
                            sourceTagUnsynchronised
                        );

                    if (formatPlan.hasError)
                    {
                        return
                            Id3v23FrameSequenceSerializationResult
                                .failure(formatPlan.error);
                    }

                    auto serialized =
                        serializeRegeneratedId3v23RecordingTimeComponentFrame(
                            recordingTime.plan.component,
                            recordingTime.plan.value,
                            formatPlan.value
                        );

                    if (serialized.hasError)
                        return writerFailure(serialized.error);

                    appendFrameBytes(output, serialized.value);
                    break;
                }

                /*
                 * The sequence plan identifies the source frame while
                 * `plan.regenerations` carries the semantic regeneration
                 * details. Exactly one relationship must exist.
                 */
                size_t regenerationIndex;
                size_t matchCount;

                foreach (
                    candidateIndex,
                    const regeneration;
                    plan.regenerations
                )
                {
                    if (
                        regeneration.sourceFrameIndex ==
                        entry.sourceFrameIndex
                    )
                    {
                        regenerationIndex =
                            candidateIndex;

                        ++matchCount;
                    }
                }

                if (matchCount != 1)
                {
                    return
                        writerFailure(
                            SerializationError(
                                SerializationErrorCode
                                    .inconsistentStructure,
                                entry.sourceFrameIndex,
                                matchCount,
                                1
                            )
                        );
                }

                auto executed =
                    serializeId3v23PlannedRegeneration(
                        projection,
                        edit,
                        plan,
                        regenerationIndex,
                        sourceTagUnsynchronised
                    );

                if (executed.hasError)
                {
                    return
                        Id3v23FrameSequenceSerializationResult
                            .failure(
                                executed.error
                            );
                }

                auto serialized =
                    executed.value;

                if (serialized.hasError)
                {
                    return
                        writerFailure(
                            serialized.error
                        );
                }

                appendFrameBytes(
                    output,
                    serialized.value
                );

                break;
            }

            case Id3v23FrameWriteAction
                .discard:
                /*
                 * Explicit semantic decision: this source frame contributes
                 * no bytes to the resulting sequence.
                 */
                break;

            case Id3v23FrameWriteAction
                .rejectWrite:
                /*
                 * `plan.writable` should already have blocked this state.
                 * A contradictory externally supplied plan is nevertheless
                 * handled defensively as a writer-plan inconsistency.
                 */
                return
                    writerFailure(
                        SerializationError(
                            SerializationErrorCode
                                .inconsistentStructure,
                            entry.sourceFrameIndex
                        )
                    );
        }

        if (
            plan.recordingTimeGroup.status ==
                Id3v23RecordingTimeGroupWriteStatus.ready &&
            entry.sourceFrameIndex ==
                lastRecordingTimeSourceFrameIndex(
                    plan.recordingTimeGroup
                )
        )
        {
            auto appended =
                serializeAppendedRecordingTimeComponents(
                    plan.recordingTimeGroup
                );

            if (appended.hasError)
                return writerFailure(appended.error);

            appendFrameBytes(output, appended.value);
        }
    }

    /*
     * New canonical fields have no source-native insertion point. Preserve
     * canonical edit order across ordinary and compound targets.
     */
    foreach (newFieldIndex; 0 .. edit.newFields.length)
    {
        size_t ordinaryPlanIndex;
        size_t ordinaryMatchCount;

        foreach (candidateIndex, const candidate; plan.newFrames)
        {
            if (candidate.newFieldIndex == newFieldIndex)
            {
                ordinaryPlanIndex = candidateIndex;
                ++ordinaryMatchCount;
            }
        }

        size_t recordingTimePlanIndex;
        size_t recordingTimeMatchCount;

        foreach (candidateIndex, const candidate; plan.newRecordingTimeGroups)
        {
            if (candidate.newFieldIndex == newFieldIndex)
            {
                recordingTimePlanIndex = candidateIndex;
                ++recordingTimeMatchCount;
            }
        }

        if (ordinaryMatchCount + recordingTimeMatchCount != 1)
        {
            return
                writerFailure(
                    SerializationError(
                        SerializationErrorCode.inconsistentStructure,
                        newFieldIndex,
                        ordinaryMatchCount + recordingTimeMatchCount,
                        1
                    )
                );
        }

        if (ordinaryMatchCount == 1)
        {
            auto serialized =
                serializeId3v23PlannedNewFrame(
                    edit,
                    plan,
                    ordinaryPlanIndex
                );

            if (serialized.hasError)
                return writerFailure(serialized.error);

            appendFrameBytes(output, serialized.value);
            continue;
        }

        const recordingTimePlan =
            plan.newRecordingTimeGroups[recordingTimePlanIndex];

        if (!recordingTimePlan.writable)
        {
            return
                writerFailure(
                    SerializationError(
                        SerializationErrorCode.unsupportedRepresentation,
                        newFieldIndex
                    )
                );
        }

        auto serialized =
            serializeAppendedRecordingTimeComponents(
                recordingTimePlan.group
            );

        if (serialized.hasError)
            return writerFailure(serialized.error);

        appendFrameBytes(output, serialized.value);
    }

    return
        Id3v23FrameSequenceSerializationResult
            .success(
                SerializationResult!(ubyte[])
                    .success(output)
            );
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.metadata.field :
        MetadataField,
        MetadataKey;

    import audiotag.metadata.value :
        MetadataText,
        MetadataTextList,
        MetadataValue;

    import audiotag.id3v2.v23.canonical_mapping :
        Id3v23CanonicalMappingResult;

    import audiotag.id3v2.v23.data_cursor :
        Id3v23DataCursor;

    import audiotag.id3v2.v23.frame :
        Id3v23FrameEnvelope,
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrame,
        Id3v23NativeFrameContent,
        Id3v23UnknownFrame;

    import audiotag.id3v2.v23.tag_write_plan :
        planId3v23CanonicalTagWrite;

    import audiotag.id3v2.v23.writer_policy :
        Id3v23WriteContext;


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


    private Id3v23FrameEnvelope parseSourceFrame(
        const(ubyte)[] bytes,
        size_t sourceOffset = 0
    )
        @safe
    {
        auto cursor =
            Id3v23DataCursor(
                ByteSpan(
                    bytes,
                    sourceOffset
                ),
                false
            );

        auto parsed =
            cursor.parseId3v23FrameEnvelope();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }


    private Id3v23NativeFrame nativeFromBytes(
        const(ubyte)[] bytes,
        size_t sourceOffset = 0
    )
        @safe
    {
        Id3v23NativeFrameContent content =
            Id3v23UnknownFrame();

        return
            Id3v23NativeFrame(
                parseSourceFrame(
                    bytes,
                    sourceOffset
                ),
                content
            );
    }
}


/// Preserve, regenerate, discard and new-frame output form one sequence.
unittest
{
    const ubyte[] originalTitle =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            0x00,
            'O', 'r', 'i', 'g',
            'i', 'n', 'a', 'l'
        ];

    const ubyte[] unknownFrame =
        [
            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0xAA,
            0xBB
        ];

    const ubyte[] originalAlbum =
        [
            'T', 'A', 'L', 'B',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
            'O', 'l', 'd'
        ];

    auto projection =
        Id3v23CanonicalProjection.init;

    /*
     * Native source order:
     *
     *   0 TIT2 -> regenerate
     *   1 X001 -> preserve
     *   2 TALB -> discard
     */
    projection.append(
        nativeFromBytes(
            originalTitle,
            100
        ),
        Id3v23CanonicalMappingResult
            .success(
                textField(
                    "title",
                    "Original"
                )
            )
    );

    projection.append(
        nativeFromBytes(
            unknownFrame,
            200
        ),
        Id3v23CanonicalMappingResult
            .unsupported()
    );

    projection.append(
        nativeFromBytes(
            originalAlbum,
            300
        ),
        Id3v23CanonicalMappingResult
            .success(
                textField(
                    "album",
                    "Old"
                )
            )
    );

    /*
     * Canonical source indices:
     *
     *   title = 0
     *   album = 1
     *
     * The unsupported native X001 frame contributes no canonical field.
     */
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

    edit.removeSourceField(1);

    /*
     * ID3v2.3 represents the ordered artist list in TPE1 using "/".
     */
    edit.appendNewField(
        textListField(
            "artist",
            ["A", "B"]
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    assert(
        plan.existingFrames.regenerateCount ==
        1
    );

    assert(
        plan.existingFrames.preserveCount ==
        1
    );

    assert(
        plan.existingFrames.discardCount ==
        1
    );

    assert(plan.newFrameCount == 1);

    auto assembled =
        serializeId3v23PlannedFrameSequence(
            projection,
            edit,
            plan
        );

    assert(assembled.hasValue);

    auto serialized =
        assembled.value;

    assert(serialized.hasValue);

    /*
     * Existing frame 0 stays first but is regenerated.
     *
     * Existing frame 1 is copied exactly.
     *
     * Existing frame 2 is omitted.
     *
     * New TPE1 follows all surviving source frames.
     */
    assert(
        serialized.value ==
        [
            /*
             * Regenerated TIT2 = Latin-1 "New".
             */
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
            'N', 'e', 'w',

            /*
             * Preserved unknown X001.
             */
            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0xAA,
            0xBB,

            /*
             * New TPE1 = Latin-1 "A/B".
             */
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
            'A', '/', 'B'
        ]
    );
}


/// Multiple new fields retain edit insertion order at the sequence tail.
unittest
{
    const projection =
        Id3v23CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        textField(
            "title",
            "T"
        )
    );

    edit.appendNewField(
        textField(
            "album",
            "A"
        )
    );

    edit.appendNewField(
        textListField(
            "artist",
            ["P"]
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto assembled =
        serializeId3v23PlannedFrameSequence(
            projection,
            edit,
            plan
        );

    assert(assembled.hasValue);
    assert(assembled.value.hasValue);

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                assembled.value.value[]
            ),
            false
        );

    auto first =
        cursor.parseId3v23FrameEnvelope();

    auto second =
        cursor.parseId3v23FrameEnvelope();

    auto third =
        cursor.parseId3v23FrameEnvelope();

    assert(first.hasValue);
    assert(second.hasValue);
    assert(third.hasValue);

    assert(first.value.header.id[] == "TIT2");
    assert(second.value.header.id[] == "TALB");
    assert(third.value.header.id[] == "TPE1");

    assert(cursor.empty);
}


/// A blocked semantic plan cannot produce a partial frame sequence.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,

            /*
             * Native read-only flag.
             */
            0x20,
            0x00,

            0x00,
            'X'
        ];

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromBytes(bytes),
        Id3v23CanonicalMappingResult
            .success(
                textField(
                    "title",
                    "X"
                )
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
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);

    auto assembled =
        serializeId3v23PlannedFrameSequence(
            projection,
            edit,
            plan
        );

    assert(assembled.hasValue);

    auto serialized =
        assembled.value;

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Source unsynchronisation does not block an otherwise writable sequence.
unittest
{
    const projection =
        Id3v23CanonicalProjection.init;

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
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto assembled =
        serializeId3v23PlannedFrameSequence(
            projection,
            edit,
            plan,
            true
        );

    assert(assembled.hasValue);

    auto serialized =
        assembled.value;

    assert(serialized.hasValue);

    /*
     * Newly generated frames are ordinary logical/native bytes regardless
     * of the source tag's former whole-tag unsynchronisation state.
     */
    assert(serialized.value.length != 0);
}
