/++
Compound write planning for legacy ID3v2.3 recording-time metadata.

One canonical `recordingDate` may correspond to up to three native frames:

- `TYER`;
- `TDAT`;
- `TIME`.

The ordinary ID3v2 writer plans one existing native frame at a time. That
model is insufficient for this many-native-to-one-canonical relationship
because replacing one canonical value may require a mixture of:

- preserving an existing component;
- regenerating an existing component;
- discarding an existing component;
- appending a previously absent component.

This module models that group decision only. It does not yet integrate the
group into the complete tag write plan and emits no bytes.
+/
module audiotag.id3v2.v23.recording_time_group_write_plan;

import std.sumtype :
    match;

import audiotag.id3v2.v23.canonical_mapping :
    Id3v23CanonicalMappingStatus;

import audiotag.id3v2.v23.canonical_projection :
    Id3v23CanonicalFrameRecord,
    Id3v23CanonicalProjection;

import audiotag.id3v2.v23.canonical_recording_time :
    isId3v23RecordingTimeFrameId;

import audiotag.id3v2.v23.frame_write_plan :
    Id3v23CanonicalFrameMutation,
    Id3v23FrameWriteAction,
    planId3v23CanonicalFrameWrite;

import audiotag.id3v2.v23.recording_time_write :
    Id3v23RecordingTimeWritePlan,
    planId3v23RecordingTimeWrite;

import audiotag.id3v2.v23.writer_policy :
    Id3v23WriteContext,
    Id3v23WriterPolicy;

import audiotag.metadata.edit :
    MetadataSourceFieldEditState,
    MetadataTreeEdit;

import audiotag.metadata.field :
    MetadataField;

import audiotag.metadata.value :
    MetadataDateTimeList;


/++
Native semantic component in the ID3v2.3 recording-time group.
+/
enum Id3v23RecordingTimeComponent : ubyte
{
    year,
    date,
    time
}


/++
Action required for one native recording-time component.

`appendNew` is intentionally distinct from `regenerateExisting`: the former
has no source-frame position or preserved native format to inherit.
+/
enum Id3v23RecordingTimeComponentWriteAction : ubyte
{
    absent,
    preserveOriginal,
    regenerateExisting,
    discardExisting,
    appendNew,
    rejectWrite
}


/++
One component decision in a compound recording-time write plan.

`value` is meaningful for `regenerateExisting` and `appendNew` and already
contains the exact four-character semantic text required by the native frame.
+/
struct Id3v23RecordingTimeComponentWritePlan
{
    Id3v23RecordingTimeComponent component;
    Id3v23RecordingTimeComponentWriteAction action;

    bool hasSourceFrame;
    size_t sourceFrameIndex;

    string value;

    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            action !=
            Id3v23RecordingTimeComponentWriteAction.rejectWrite;
    }
}


/++
Overall state of one recording-time group plan.
+/
enum Id3v23RecordingTimeGroupWriteStatus : ubyte
{
    /// No mapped source recording-time group exists.
    absent,

    /// Group planning succeeded.
    ready,

    /// Projection relationships are internally inconsistent.
    inconsistentProjection,

    /// Replacement/new canonical metadata is not losslessly representable.
    unrepresentableCanonicalField,

    /// A required change is blocked by native frame preservation policy.
    blockedByNativeFramePolicy
}


/++
Compound plan for one legacy recording-time group.

For an existing mapped group, `hasCanonicalSource` identifies the one
canonical source field shared by every contributing native frame.

For a newly introduced group there is no canonical source index.
+/
struct Id3v23RecordingTimeGroupWritePlan
{
    Id3v23RecordingTimeGroupWriteStatus status;

    bool hasCanonicalSource;
    size_t canonicalSourceIndex;

    Id3v23RecordingTimeComponentWritePlan year;
    Id3v23RecordingTimeComponentWritePlan date;
    Id3v23RecordingTimeComponentWritePlan time;

    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            status ==
                Id3v23RecordingTimeGroupWriteStatus.absent ||
            status ==
                Id3v23RecordingTimeGroupWriteStatus.ready;
    }
}


private struct SourceComponent
{
    bool found;
    size_t sourceFrameIndex;
}


private struct FieldDecomposition
{
    bool supportedShape;
    Id3v23RecordingTimeWritePlan native;
}


private FieldDecomposition
decomposeRecordingDateField(
    ref const(MetadataField) field
)
    @safe
{
    if (
        field.key.name !=
        "recordingDate" ||
        field.hasLanguage ||
        field.hasDescription ||
        field.hasQualifiers
    )
    {
        return FieldDecomposition.init;
    }

    return
        field.value.match!(
            (const(MetadataDateTimeList) value) =>
                FieldDecomposition(
                    true,
                    planId3v23RecordingTimeWrite(
                        value
                    )
                ),

            _ =>
                FieldDecomposition.init
        );
}


private bool
idEquals(
    const ref char[4] id,
    string expected
)
    @safe pure nothrow @nogc
{
    return
        expected.length == 4 &&
        id[0] == expected[0] &&
        id[1] == expected[1] &&
        id[2] == expected[2] &&
        id[3] == expected[3];
}


private Id3v23RecordingTimeComponent
componentFor(
    const ref char[4] id
)
    @safe pure nothrow @nogc
{
    assert(
        isId3v23RecordingTimeFrameId(
            id
        )
    );

    if (idEquals(id, "TYER"))
    {
        return
            Id3v23RecordingTimeComponent.year;
    }

    if (idEquals(id, "TDAT"))
    {
        return
            Id3v23RecordingTimeComponent.date;
    }

    return
        Id3v23RecordingTimeComponent.time;
}


private Id3v23RecordingTimeComponentWriteAction
translateExistingAction(
    Id3v23FrameWriteAction action
)
    @safe pure nothrow @nogc
{
    final switch (action)
    {
        case Id3v23FrameWriteAction.preserveOriginal:
            return
                Id3v23RecordingTimeComponentWriteAction
                    .preserveOriginal;

        case Id3v23FrameWriteAction.regenerate:
            return
                Id3v23RecordingTimeComponentWriteAction
                    .regenerateExisting;

        case Id3v23FrameWriteAction.discard:
            return
                Id3v23RecordingTimeComponentWriteAction
                    .discardExisting;

        case Id3v23FrameWriteAction.rejectWrite:
            return
                Id3v23RecordingTimeComponentWriteAction
                    .rejectWrite;
    }
}


private Id3v23RecordingTimeComponentWritePlan
planExistingComponent(
    Id3v23RecordingTimeComponent component,
    SourceComponent source,
    const(Id3v23CanonicalFrameRecord)[] records,
    bool targetPresent,
    string targetValue,
    MetadataSourceFieldEditState sourceEditState,
    Id3v23WriteContext context,
    Id3v23WriterPolicy policy
)
    @safe
{
    if (
        sourceEditState ==
        MetadataSourceFieldEditState.unchanged
    )
    {
        if (!source.found)
        {
            return
                Id3v23RecordingTimeComponentWritePlan(
                    component,
                    Id3v23RecordingTimeComponentWriteAction.absent
                );
        }

        const framePlan =
            planId3v23CanonicalFrameWrite(
                records[
                    source.sourceFrameIndex
                ],
                Id3v23CanonicalFrameMutation.unchanged,
                context,
                policy
            );

        return
            Id3v23RecordingTimeComponentWritePlan(
                component,
                translateExistingAction(
                    framePlan.action
                ),
                true,
                source.sourceFrameIndex
            );
    }

    if (
        sourceEditState ==
        MetadataSourceFieldEditState.removed
    )
    {
        if (!source.found)
        {
            return
                Id3v23RecordingTimeComponentWritePlan(
                    component,
                    Id3v23RecordingTimeComponentWriteAction.absent
                );
        }

        const framePlan =
            planId3v23CanonicalFrameWrite(
                records[
                    source.sourceFrameIndex
                ],
                Id3v23CanonicalFrameMutation.removed,
                context,
                policy
            );

        return
            Id3v23RecordingTimeComponentWritePlan(
                component,
                translateExistingAction(
                    framePlan.action
                ),
                true,
                source.sourceFrameIndex
            );
    }

    assert(
        sourceEditState ==
        MetadataSourceFieldEditState.modified
    );

    if (source.found)
    {
        const mutation =
            targetPresent
                ? Id3v23CanonicalFrameMutation.modified
                : Id3v23CanonicalFrameMutation.removed;

        const framePlan =
            planId3v23CanonicalFrameWrite(
                records[
                    source.sourceFrameIndex
                ],
                mutation,
                context,
                policy
            );

        return
            Id3v23RecordingTimeComponentWritePlan(
                component,
                translateExistingAction(
                    framePlan.action
                ),
                true,
                source.sourceFrameIndex,
                targetPresent
                    ? targetValue
                    : ""
            );
    }

    if (targetPresent)
    {
        return
            Id3v23RecordingTimeComponentWritePlan(
                component,
                Id3v23RecordingTimeComponentWriteAction.appendNew,
                false,
                0,
                targetValue
            );
    }

    return
        Id3v23RecordingTimeComponentWritePlan(
            component,
            Id3v23RecordingTimeComponentWriteAction.absent
        );
}


private bool
componentPlansWritable(
    const(Id3v23RecordingTimeGroupWritePlan) plan
)
    @safe pure nothrow @nogc
{
    return
        plan.year.writable &&
        plan.date.writable &&
        plan.time.writable;
}


/++
Plans the mapped source `recordingDate` group in one canonical projection.

Every mapped TYER/TDAT/TIME frame must:

- map to exactly one canonical field;
- point to the same canonical source index;
- refer to the canonical `recordingDate`;
- occur at most once per native component.

If no mapped temporal group exists, `status == absent`.

A modified canonical field is first decomposed through
`planId3v23RecordingTimeWrite`. Existing native components are regenerated
when still present, discarded when removed from the replacement, and missing
components are marked `appendNew`.

Native read-only constraints are delegated to the ordinary frame writer
policy so group planning retains the same preservation semantics as every
other mapped frame.
+/
Id3v23RecordingTimeGroupWritePlan
planId3v23ExistingRecordingTimeGroup(
    const(Id3v23CanonicalProjection) projection,
    const(MetadataTreeEdit) edit,
    Id3v23WriteContext context,
    Id3v23WriterPolicy policy =
        Id3v23WriterPolicy.init
)
    @safe
{
    assert(
        edit.sourceFieldCount ==
        projection.metadata.length
    );

    SourceComponent yearSource;
    SourceComponent dateSource;
    SourceComponent timeSource;

    bool anyTemporalFrame;
    bool anyMappedTemporalFrame;
    bool canonicalSourceKnown;
    size_t canonicalSourceIndex;

    foreach (
        sourceFrameIndex,
        const record;
        projection.frames
    )
    {
        const ref id =
            record.native.envelope.header.id;

        if (
            !isId3v23RecordingTimeFrameId(
                id
            )
        )
        {
            continue;
        }

        anyTemporalFrame = true;

        if (
            record.status !=
            Id3v23CanonicalMappingStatus.mapped
        )
        {
            continue;
        }

        anyMappedTemporalFrame = true;

        if (record.canonicalCount != 1)
        {
            return
                Id3v23RecordingTimeGroupWritePlan(
                    Id3v23RecordingTimeGroupWriteStatus
                        .inconsistentProjection
                );
        }

        if (!canonicalSourceKnown)
        {
            canonicalSourceKnown = true;
            canonicalSourceIndex =
                record.canonicalStart;
        }
        else if (
            record.canonicalStart !=
            canonicalSourceIndex
        )
        {
            return
                Id3v23RecordingTimeGroupWritePlan(
                    Id3v23RecordingTimeGroupWriteStatus
                        .inconsistentProjection
                );
        }

        if (
            record.canonicalStart >=
            projection.metadata.length
        )
        {
            return
                Id3v23RecordingTimeGroupWritePlan(
                    Id3v23RecordingTimeGroupWriteStatus
                        .inconsistentProjection
                );
        }

        const component =
            componentFor(
                id
            );

        final switch (component)
        {
            case Id3v23RecordingTimeComponent.year:
            {
                if (yearSource.found)
                {
                    return
                        Id3v23RecordingTimeGroupWritePlan(
                            Id3v23RecordingTimeGroupWriteStatus
                                .inconsistentProjection
                        );
                }

                yearSource.found = true;
                yearSource.sourceFrameIndex =
                    sourceFrameIndex;

                break;
            }

            case Id3v23RecordingTimeComponent.date:
            {
                if (dateSource.found)
                {
                    return
                        Id3v23RecordingTimeGroupWritePlan(
                            Id3v23RecordingTimeGroupWriteStatus
                                .inconsistentProjection
                        );
                }

                dateSource.found = true;
                dateSource.sourceFrameIndex =
                    sourceFrameIndex;

                break;
            }

            case Id3v23RecordingTimeComponent.time:
            {
                if (timeSource.found)
                {
                    return
                        Id3v23RecordingTimeGroupWritePlan(
                            Id3v23RecordingTimeGroupWriteStatus
                                .inconsistentProjection
                        );
                }

                timeSource.found = true;
                timeSource.sourceFrameIndex =
                    sourceFrameIndex;

                break;
            }
        }
    }

    if (!anyMappedTemporalFrame)
    {
        return
            Id3v23RecordingTimeGroupWritePlan(
                Id3v23RecordingTimeGroupWriteStatus.absent
            );
    }

    /*
     * A canonically mapped temporal group must include every temporal frame.
     * Otherwise a hidden unsupported/transformation-pending component would
     * be silently ignored during replacement.
     */
    if (anyTemporalFrame)
    {
        foreach (const record; projection.frames)
        {
            if (
                isId3v23RecordingTimeFrameId(
                    record.native.envelope.header.id
                ) &&
                record.status !=
                    Id3v23CanonicalMappingStatus.mapped
            )
            {
                return
                    Id3v23RecordingTimeGroupWritePlan(
                        Id3v23RecordingTimeGroupWriteStatus
                            .inconsistentProjection
                    );
            }
        }
    }

    assert(canonicalSourceKnown);

    if (
        projection.metadata[
            canonicalSourceIndex
        ].key.name !=
        "recordingDate"
    )
    {
        return
            Id3v23RecordingTimeGroupWritePlan(
                Id3v23RecordingTimeGroupWriteStatus
                    .inconsistentProjection
            );
    }

    const sourceEdit =
        edit.sourceEdit(
            canonicalSourceIndex
        );

    Id3v23RecordingTimeWritePlan target;

    if (
        sourceEdit.state ==
        MetadataSourceFieldEditState.modified
    )
    {
        const decomposition =
            decomposeRecordingDateField(
                sourceEdit.replacement
            );

        if (
            !decomposition.supportedShape ||
            !decomposition.native.writable
        )
        {
            return
                Id3v23RecordingTimeGroupWritePlan(
                    Id3v23RecordingTimeGroupWriteStatus
                        .unrepresentableCanonicalField,
                    true,
                    canonicalSourceIndex
                );
        }

        target =
            decomposition.native;
    }

    auto result =
        Id3v23RecordingTimeGroupWritePlan.init;

    result.status =
        Id3v23RecordingTimeGroupWriteStatus.ready;

    result.hasCanonicalSource = true;
    result.canonicalSourceIndex =
        canonicalSourceIndex;

    result.year =
        planExistingComponent(
            Id3v23RecordingTimeComponent.year,
            yearSource,
            projection.frames,
            target.hasYear,
            target.year,
            sourceEdit.state,
            context,
            policy
        );

    result.date =
        planExistingComponent(
            Id3v23RecordingTimeComponent.date,
            dateSource,
            projection.frames,
            target.hasDate,
            target.date,
            sourceEdit.state,
            context,
            policy
        );

    result.time =
        planExistingComponent(
            Id3v23RecordingTimeComponent.time,
            timeSource,
            projection.frames,
            target.hasTime,
            target.time,
            sourceEdit.state,
            context,
            policy
        );

    if (!componentPlansWritable(result))
    {
        result.status =
            Id3v23RecordingTimeGroupWriteStatus
                .blockedByNativeFramePolicy;
    }

    return result;
}


/++
Plans one newly introduced canonical `recordingDate` field.

The field must contain exactly the lossless shape accepted by
`planId3v23RecordingTimeWrite` and must not carry language, description or
qualifiers that TYER/TDAT/TIME cannot represent.

Each present native component is returned as `appendNew`.
+/
Id3v23RecordingTimeGroupWritePlan
planId3v23NewRecordingTimeGroup(
    ref const(MetadataField) field
)
    @safe
{
    const decomposition =
        decomposeRecordingDateField(
            field
        );

    if (
        !decomposition.supportedShape ||
        !decomposition.native.writable
    )
    {
        return
            Id3v23RecordingTimeGroupWritePlan(
                Id3v23RecordingTimeGroupWriteStatus
                    .unrepresentableCanonicalField
            );
    }

    const target =
        decomposition.native;

    auto result =
        Id3v23RecordingTimeGroupWritePlan.init;

    result.status =
        Id3v23RecordingTimeGroupWriteStatus.ready;

    result.year =
        Id3v23RecordingTimeComponentWritePlan(
            Id3v23RecordingTimeComponent.year,
            target.hasYear
                ? Id3v23RecordingTimeComponentWriteAction.appendNew
                : Id3v23RecordingTimeComponentWriteAction.absent,
            false,
            0,
            target.hasYear
                ? target.year
                : ""
        );

    result.date =
        Id3v23RecordingTimeComponentWritePlan(
            Id3v23RecordingTimeComponent.date,
            target.hasDate
                ? Id3v23RecordingTimeComponentWriteAction.appendNew
                : Id3v23RecordingTimeComponentWriteAction.absent,
            false,
            0,
            target.hasDate
                ? target.date
                : ""
        );

    result.time =
        Id3v23RecordingTimeComponentWritePlan(
            Id3v23RecordingTimeComponent.time,
            target.hasTime
                ? Id3v23RecordingTimeComponentWriteAction.appendNew
                : Id3v23RecordingTimeComponentWriteAction.absent,
            false,
            0,
            target.hasTime
                ? target.time
                : ""
        );

    return result;
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.canonical_mapping :
        Id3v23CanonicalMappingResult;

    import audiotag.id3v2.v23.frame_header :
        parseId3v23FrameHeader;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrame;

    import audiotag.metadata.field :
        MetadataKey;

    import audiotag.metadata.value :
        MetadataDateTime,
        MetadataValue;


    private Id3v23NativeFrame
    testNative(
        string id,
        ubyte statusFlags = 0x00
    )
        @safe
    {
        assert(id.length == 4);

        const ubyte[] bytes =
            [
                cast(ubyte) id[0],
                cast(ubyte) id[1],
                cast(ubyte) id[2],
                cast(ubyte) id[3],
                0x00, 0x00, 0x00, 0x01,
                statusFlags,
                0x00
            ];

        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto header =
            cursor.parseId3v23FrameHeader();

        assert(header.hasValue);
        assert(cursor.empty);

        Id3v23NativeFrame native;
        native.envelope.header =
            header.value;

        return native;
    }


    private MetadataField
    recordingDateField(
        MetadataDateTime timestamp
    )
        @safe
    {
        MetadataValue value =
            MetadataDateTimeList(
                [
                    timestamp
                ]
            );

        return
            MetadataField(
                MetadataKey(
                    "recordingDate"
                ),
                value
            );
    }


    private Id3v23CanonicalProjection
    fullRecordingTimeProjection(
        ubyte yearFlags = 0x00,
        ubyte dateFlags = 0x00,
        ubyte timeFlags = 0x00
    )
        @safe
    {
        auto timestamp =
            MetadataDateTime.calendarDate(
                2000,
                2,
                29
            );

        timestamp.hasHour = true;
        timestamp.hour = 23;
        timestamp.hasMinute = true;
        timestamp.minute = 59;

        auto projection =
            Id3v23CanonicalProjection.init;

        projection.append(
            testNative(
                "TYER",
                yearFlags
            ),
            Id3v23CanonicalMappingResult
                .success(
                    recordingDateField(
                        timestamp
                    )
                )
        );

        projection.appendLinkedMapped(
            testNative(
                "TDAT",
                dateFlags
            ),
            0
        );

        projection.appendLinkedMapped(
            testNative(
                "TIME",
                timeFlags
            ),
            0
        );

        return projection;
    }
}


/// An unchanged source recording time preserves every native component.
unittest
{
    const projection =
        fullRecordingTimeProjection();

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23ExistingRecordingTimeGroup(
            projection,
            edit,
            Id3v23WriteContext.unchanged()
        );

    assert(plan.writable);
    assert(plan.hasCanonicalSource);
    assert(plan.canonicalSourceIndex == 0);

    assert(
        plan.year.action ==
        Id3v23RecordingTimeComponentWriteAction
            .preserveOriginal
    );

    assert(
        plan.date.action ==
        Id3v23RecordingTimeComponentWriteAction
            .preserveOriginal
    );

    assert(
        plan.time.action ==
        Id3v23RecordingTimeComponentWriteAction
            .preserveOriginal
    );
}


/// Replacing a full source timestamp with year-only regenerates/removes exactly.
unittest
{
    const projection =
        fullRecordingTimeProjection();

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        recordingDateField(
            MetadataDateTime.yearOnly(
                1999
            )
        )
    );

    const plan =
        planId3v23ExistingRecordingTimeGroup(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    assert(
        plan.year.action ==
        Id3v23RecordingTimeComponentWriteAction
            .regenerateExisting
    );

    assert(plan.year.value == "1999");

    assert(
        plan.date.action ==
        Id3v23RecordingTimeComponentWriteAction
            .discardExisting
    );

    assert(
        plan.time.action ==
        Id3v23RecordingTimeComponentWriteAction
            .discardExisting
    );
}


/// Replacing year-only with a full timestamp plans missing components as new.
unittest
{
    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        testNative("TYER"),
        Id3v23CanonicalMappingResult
            .success(
                recordingDateField(
                    MetadataDateTime.yearOnly(
                        2000
                    )
                )
            )
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    auto replacement =
        MetadataDateTime.calendarDate(
            2001,
            6,
            12
        );

    replacement.hasHour = true;
    replacement.hour = 7;
    replacement.hasMinute = true;
    replacement.minute = 45;

    edit.replaceSourceField(
        0,
        recordingDateField(
            replacement
        )
    );

    const plan =
        planId3v23ExistingRecordingTimeGroup(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    assert(
        plan.year.action ==
        Id3v23RecordingTimeComponentWriteAction
            .regenerateExisting
    );

    assert(plan.year.value == "2001");

    assert(
        plan.date.action ==
        Id3v23RecordingTimeComponentWriteAction
            .appendNew
    );

    assert(plan.date.value == "1206");

    assert(
        plan.time.action ==
        Id3v23RecordingTimeComponentWriteAction
            .appendNew
    );

    assert(plan.time.value == "0745");
}


/// Removing the canonical source field discards all writable source components.
unittest
{
    const projection =
        fullRecordingTimeProjection();

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.removeSourceField(0);

    const plan =
        planId3v23ExistingRecordingTimeGroup(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    assert(
        plan.year.action ==
        Id3v23RecordingTimeComponentWriteAction
            .discardExisting
    );

    assert(
        plan.date.action ==
        Id3v23RecordingTimeComponentWriteAction
            .discardExisting
    );

    assert(
        plan.time.action ==
        Id3v23RecordingTimeComponentWriteAction
            .discardExisting
    );
}


/// A read-only source component blocks a required compound modification.
unittest
{
    const projection =
        fullRecordingTimeProjection(
            0x20
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        recordingDateField(
            MetadataDateTime.yearOnly(
                1999
            )
        )
    );

    const plan =
        planId3v23ExistingRecordingTimeGroup(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23RecordingTimeGroupWriteStatus
            .blockedByNativeFramePolicy
    );

    assert(
        plan.year.action ==
        Id3v23RecordingTimeComponentWriteAction
            .rejectWrite
    );
}


/// Unsupported canonical precision blocks group planning before frame actions.
unittest
{
    const projection =
        fullRecordingTimeProjection();

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    auto replacement =
        MetadataDateTime.yearOnly(
            2000
        );

    replacement.hasSecond = true;
    replacement.second = 30;

    edit.replaceSourceField(
        0,
        recordingDateField(
            replacement
        )
    );

    const plan =
        planId3v23ExistingRecordingTimeGroup(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23RecordingTimeGroupWriteStatus
            .unrepresentableCanonicalField
    );
}


/// A newly introduced recording date creates only its present native components.
unittest
{
    MetadataDateTime timestamp;

    timestamp.hasMonth = true;
    timestamp.month = 6;

    timestamp.hasDay = true;
    timestamp.day = 12;

    auto field =
        recordingDateField(
            timestamp
        );

    const plan =
        planId3v23NewRecordingTimeGroup(
            field
        );

    assert(plan.writable);
    assert(!plan.hasCanonicalSource);

    assert(
        plan.year.action ==
        Id3v23RecordingTimeComponentWriteAction
            .absent
    );

    assert(
        plan.date.action ==
        Id3v23RecordingTimeComponentWriteAction
            .appendNew
    );

    assert(plan.date.value == "1206");

    assert(
        plan.time.action ==
        Id3v23RecordingTimeComponentWriteAction
            .absent
    );
}


/// A projection without mapped recording-time frames has no existing group.
unittest
{
    const projection =
        Id3v23CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23ExistingRecordingTimeGroup(
            projection,
            edit,
            Id3v23WriteContext.unchanged()
        );

    assert(plan.writable);

    assert(
        plan.status ==
        Id3v23RecordingTimeGroupWriteStatus.absent
    );
}
