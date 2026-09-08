/++
Execution of semantically planned ID3v2.3 frame serialization.

This module is the dispatch layer between semantic tag-write planning
and concrete native frame serializers.

Currently executable canonical target families:

- ordinary text information (`T***`);
- ordinary URL links (`W***`, excluding `WXXX`);
- user-defined text (`TXXX`);
- user-defined URL (`WXXX`);
- language-qualified text (`COMM`/`USLT`);
- attached pictures (`APIC`);
- private binary data (`PRIV`);
- unique file identifiers (`UFID`).

Other semantically valid target families remain explicit
`unsupportedRepresentation` results until their complete native frame
serializers are implemented. They are never silently omitted.

Existing-frame regeneration retains two distinct error domains:

- outer `ParseResult`: malformed preserved source-frame structure;
- inner `SerializationResult`: planner/writer/output failure.

New frames have no preserved native structure and therefore return only
`SerializationResult`.

Whole-tag ordering, whole-tag unsynchronisation, padding, tag sizing and
container updating remain later layers.
+/
module audiotag.id3v2.v23.planned_frame_write;

import audiotag.core.result :
    ParseResult;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.metadata.edit :
    MetadataSourceFieldEditState,
    MetadataTreeEdit;

import audiotag.id3v2.v23.canonical_projection :
    Id3v23CanonicalProjection;

import audiotag.id3v2.v23.canonical_target :
    Id3v23CanonicalTargetDefinition,
    Id3v23CanonicalTargetFamily;

import audiotag.id3v2.v23.frame_write_plan :
    Id3v23FrameWriteAction;

import audiotag.id3v2.v23.new_frame_plan :
    Id3v23CanonicalFieldPlan,
    planId3v23CanonicalField;

import audiotag.id3v2.v23.regeneration_policy :
    planId3v23MappedFrameRegenerationFormat;

import audiotag.id3v2.v23.tag_write_plan :
    Id3v23TagWritePlan;

import audiotag.id3v2.v23.text_information_frame_write :
    serializeNewId3v23TextInformationFrame,
    serializeRegeneratedId3v23TextInformationFrame;

import audiotag.id3v2.v23.url_link_frame_write :
    serializeNewId3v23UrlLinkFrame,
    serializeRegeneratedId3v23UrlLinkFrame;

import audiotag.id3v2.v23.user_text_frame_write :
    serializeNewId3v23UserTextFrame,
    serializeRegeneratedId3v23UserTextFrame;

import audiotag.id3v2.v23.user_url_frame_write :
    serializeNewId3v23UserUrlFrame,
    serializeRegeneratedId3v23UserUrlFrame;

import audiotag.id3v2.v23.language_text_frame_write :
    serializeNewId3v23LanguageTextFrame,
    serializeRegeneratedId3v23LanguageTextFrame;

import audiotag.id3v2.v23.attached_picture_frame_write :
    serializeNewId3v23AttachedPictureFrame,
    serializeRegeneratedId3v23AttachedPictureFrame;

import audiotag.id3v2.v23.private_frame_write :
    serializeNewId3v23PrivateFrame,
    serializeRegeneratedId3v23PrivateFrame;

import audiotag.id3v2.v23.unique_file_identifier_frame_write :
    serializeNewId3v23UniqueFileIdentifierFrame,
    serializeRegeneratedId3v23UniqueFileIdentifierFrame;


/++
Result type for executing one planned existing-frame regeneration.

The outer result represents preserved-source structural parsing.
The inner result represents physical serialization.
+/
alias Id3v23PlannedRegenerationResult =
    ParseResult!(
        SerializationResult!(ubyte[])
    );


/++
Wraps a writer failure without converting it into a parse failure.
+/
private Id3v23PlannedRegenerationResult
writerFailure(
    SerializationError error
)
    @safe
{
    return
        Id3v23PlannedRegenerationResult
            .success(
                SerializationResult!(ubyte[])
                    .failure(error)
            );
}


/++
Returns whether two canonical target definitions identify the same
planned native representation.

This prevents a semantic plan created for another or subsequently
changed edit overlay from silently selecting an unrelated serializer.
+/
private bool
sameTarget(
    const(Id3v23CanonicalTargetDefinition) first,
    const(Id3v23CanonicalTargetDefinition) second
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
    const(Id3v23CanonicalFieldPlan) current,
    const(Id3v23CanonicalFieldPlan) stored
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

Before physical dispatch the function verifies:

- the complete tag plan is writable;
- the regeneration index exists;
- source-frame and canonical-source indices remain in range;
- the existing-frame action is still `regenerate`;
- the source frame still maps to exactly the planned canonical field;
- the corresponding source edit is still `modified`;
- re-planning the replacement produces the same target;
- the preserved source frame still yields a structural regeneration plan.

At present the ordinary text-information, ordinary URL-link,
user-defined text and user-defined URL families are physically executable.

Params:
    projection = Original provenance-preserving canonical projection.
    edit = Canonical edit overlay used to construct `plan`.
    plan = Complete semantic tag-write plan.
    regenerationIndex = Index in `plan.regenerations`.
    sourceTagUnsynchronised = Whether ID3v2.3 whole-tag
        unsynchronisation applied while parsing the preserved source
        frame.

Returns:
    Outer parse failure for malformed preserved native structure;
    otherwise inner physical serialization success/failure.
+/
Id3v23PlannedRegenerationResult
serializeId3v23PlannedRegeneration(
    const(Id3v23CanonicalProjection) projection,
    const(MetadataTreeEdit) edit,
    const(Id3v23TagWritePlan) plan,
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
            Id3v23FrameWriteAction.regenerate
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
     * Re-plan the current replacement so a semantic plan from another
     * or subsequently changed edit overlay cannot select a serializer
     * using stale target information.
     */
    const currentFieldPlan =
        planId3v23CanonicalField(
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
        planId3v23MappedFrameRegenerationFormat(
            record.native.envelope,
            sourceTagUnsynchronised
        );

    if (formatPlan.hasError)
    {
        return
            Id3v23PlannedRegenerationResult
                .failure(
                    formatPlan.error
                );
    }

    SerializationResult!(ubyte[]) serialized;

    switch (
        regeneration.fieldPlan.target.family
    )
    {
        case Id3v23CanonicalTargetFamily
            .textInformation:
        {
            serialized =
                serializeRegeneratedId3v23TextInformationFrame(
                    sourceEdit.replacement,
                    formatPlan.value
                );

            break;
        }

        case Id3v23CanonicalTargetFamily
            .urlLink:
        {
            serialized =
                serializeRegeneratedId3v23UrlLinkFrame(
                    sourceEdit.replacement,
                    formatPlan.value
                );

            break;
        }

        case Id3v23CanonicalTargetFamily
            .userText:
        {
            serialized =
                serializeRegeneratedId3v23UserTextFrame(
                    sourceEdit.replacement,
                    formatPlan.value
                );

            break;
        }

        case Id3v23CanonicalTargetFamily
            .userUrl:
        {
            serialized =
                serializeRegeneratedId3v23UserUrlFrame(
                    sourceEdit.replacement,
                    formatPlan.value
                );

            break;
        }

        case Id3v23CanonicalTargetFamily
            .languageText:
        {
            serialized =
                serializeRegeneratedId3v23LanguageTextFrame(
                    sourceEdit.replacement,
                    formatPlan.value
                );

            break;
        }

        case Id3v23CanonicalTargetFamily
            .attachedPicture:
        {
            serialized =
                serializeRegeneratedId3v23AttachedPictureFrame(
                    sourceEdit.replacement,
                    formatPlan.value
                );

            break;
        }

        case Id3v23CanonicalTargetFamily
            .privateData:
        {
            serialized =
                serializeRegeneratedId3v23PrivateFrame(
                    sourceEdit.replacement,
                    formatPlan.value
                );

            break;
        }

        case Id3v23CanonicalTargetFamily
            .uniqueFileIdentifier:
        {
            serialized =
                serializeRegeneratedId3v23UniqueFileIdentifierFrame(
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
        Id3v23PlannedRegenerationResult
            .success(serialized);
}


/++
Executes one planned newly introduced canonical frame.

The function validates that the supplied semantic plan still refers to
the same canonical edit field before selecting the concrete serializer.

At present the ordinary text-information, ordinary URL-link,
user-defined text and user-defined URL target families are physically
executable.

Params:
    edit = Canonical edit overlay used to construct `plan`.
    plan = Complete semantic tag-write plan.
    newFramePlanIndex = Position in `plan.newFrames`.

Returns:
    Complete new native frame bytes or a structured writer failure.
+/
SerializationResult!(ubyte[])
serializeId3v23PlannedNewFrame(
    const(MetadataTreeEdit) edit,
    const(Id3v23TagWritePlan) plan,
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

    /*
     * Re-plan the referenced field so a plan from another or changed
     * edit overlay cannot silently serialize unrelated metadata.
     */
    const currentFieldPlan =
        planId3v23CanonicalField(
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
        case Id3v23CanonicalTargetFamily
            .textInformation:
            return
                serializeNewId3v23TextInformationFrame(
                    newFields[
                        newFramePlan.newFieldIndex
                    ]
                );

        case Id3v23CanonicalTargetFamily
            .urlLink:
            return
                serializeNewId3v23UrlLinkFrame(
                    newFields[
                        newFramePlan.newFieldIndex
                    ]
                );

        case Id3v23CanonicalTargetFamily
            .userText:
            return
                serializeNewId3v23UserTextFrame(
                    newFields[
                        newFramePlan.newFieldIndex
                    ]
                );

        case Id3v23CanonicalTargetFamily
            .userUrl:
            return
                serializeNewId3v23UserUrlFrame(
                    newFields[
                        newFramePlan.newFieldIndex
                    ]
                );

        case Id3v23CanonicalTargetFamily
            .languageText:
            return
                serializeNewId3v23LanguageTextFrame(
                    newFields[
                        newFramePlan.newFieldIndex
                    ]
                );

        case Id3v23CanonicalTargetFamily
            .attachedPicture:
            return
                serializeNewId3v23AttachedPictureFrame(
                    newFields[
                        newFramePlan.newFieldIndex
                    ]
                );

        case Id3v23CanonicalTargetFamily
            .privateData:
            return
                serializeNewId3v23PrivateFrame(
                    newFields[
                        newFramePlan.newFieldIndex
                    ]
                );

        case Id3v23CanonicalTargetFamily
            .uniqueFileIdentifier:
            return
                serializeNewId3v23UniqueFileIdentifierFrame(
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

    import audiotag.id3v2.v23.canonical_mapping :
        Id3v23CanonicalMappingResult;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrame;

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


    private MetadataField userTextField(
        string description,
        string value
    )
        @safe
    {
        auto result =
            textField(
                "userText",
                value
            );

        result.description =
            description;

        return result;
    }


    private MetadataField userUrlField(
        string description,
        string value
    )
        @safe
    {
        auto result =
            urlField(
                "userUrl",
                value
            );

        result.description =
            description;

        return result;
    }


    private MetadataField languageTextField(
        string key,
        string language,
        string description,
        string value
    )
        @safe
    {
        auto result =
            textField(
                key,
                value
            );

        result.language =
            typeof(result.language)(language);

        result.description =
            description;

        return result;
    }


    private MetadataField privateField(
        string owner,
        const(ubyte)[] data
    )
        @safe
    {
        import audiotag.metadata.field :
            MetadataQualifier;

        import audiotag.metadata.value :
            MetadataBinary;

        MetadataValue wrapped =
            MetadataBinary.copyFrom(
                data
            );

        auto result =
            MetadataField(
                MetadataKey("privateData"),
                wrapped
            );

        result.qualifiers =
            [
                MetadataQualifier(
                    "owner",
                    owner
                )
            ];

        return result;
    }


    private MetadataField uniqueFileIdentifierField(
        string owner,
        const(ubyte)[] identifier
    )
        @safe
    {
        import audiotag.metadata.field :
            MetadataQualifier;

        import audiotag.metadata.value :
            MetadataBinary;

        MetadataValue wrapped =
            MetadataBinary.copyFrom(
                identifier
            );

        auto result =
            MetadataField(
                MetadataKey(
                    "uniqueFileIdentifier"
                ),
                wrapped
            );

        result.qualifiers =
            [
                MetadataQualifier(
                    "owner",
                    owner
                )
            ];

        return result;
    }


    private MetadataField embeddedPictureField(
        string role,
        string description,
        string mimeType,
        const(ubyte)[] data
    )
        @safe
    {
        import audiotag.metadata.field :
            MetadataQualifier;

        import audiotag.metadata.value :
            MetadataBinary,
            MetadataPicture,
            MetadataPictureSource;

        MetadataPictureSource pictureSource =
            MetadataBinary.copyFrom(
                data,
                mimeType
            );

        MetadataValue wrapped =
            MetadataPicture(
                description,
                pictureSource
            );

        auto result =
            MetadataField(
                MetadataKey("artwork"),
                wrapped
            );

        result.qualifiers =
            [
                MetadataQualifier(
                    "pictureRole",
                    role
                )
            ];

        return result;
    }


    private Id3v23CanonicalProjection
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
            cursor.parseId3v23FrameEnvelope();

        assert(envelope.hasValue);
        assert(cursor.empty);

        auto native =
            Id3v23NativeFrame.init;

        native.envelope =
            envelope.value;

        auto projection =
            Id3v23CanonicalProjection.init;

        projection.append(
            native,
            Id3v23CanonicalMappingResult
                .success(mappedField)
        );

        return projection;
    }
}


/// A planned new title dispatches through the v2.3 T*** serializer.
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
            "New"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 1);

    auto serialized =
        serializeId3v23PlannedNewFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,
            0x00, 'N', 'e', 'w'
        ]
    );
}


/// A modified mapped text frame dispatches to v2.3 regeneration.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,
            0x00, 'O', 'l', 'd'
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
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.regenerationCount == 1);

    auto executed =
        serializeId3v23PlannedRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);

    auto serialized =
        executed.value;

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,
            0x00, 'N', 'e', 'w'
        ]
    );
}


/// A planned new ordinary URL dispatches through the v2.3 W*** serializer.
unittest
{
    const projection =
        Id3v23CanonicalProjection.init;

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
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 1);

    auto serialized =
        serializeId3v23PlannedNewFrame(
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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    assert(
        frame.value.header.id[] ==
        "WCOM"
    );

    assert(
        frame.value.data.data ==
        cast(const(ubyte)[])
            "https://example.test/"
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
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.regenerationCount == 1);

    auto executed =
        serializeId3v23PlannedRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);
    assert(executed.value.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                executed.value.value[]
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    assert(
        frame.value.header.id[] ==
        "WCOM"
    );

    assert(
        frame.value.data.data ==
        cast(const(ubyte)[]) "new"
    );
}


/// A planned new TXXX field dispatches through the v2.3 user-text serializer.
unittest
{
    const projection =
        Id3v23CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        userTextField(
            "key",
            "value"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 1);

    auto serialized =
        serializeId3v23PlannedNewFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x00,

            0x00,
            'k', 'e', 'y',
            0x00,
            'v', 'a', 'l', 'u', 'e'
        ]
    );
}


/// A modified mapped TXXX frame dispatches to user-text regeneration.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

            0x00,
            'k', 'e', 'y',
            0x00,
            'o', 'l', 'd'
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            userTextField(
                "key",
                "old"
            )
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        userTextField(
            "new-key",
            "new"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.regenerationCount == 1);

    auto executed =
        serializeId3v23PlannedRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);
    assert(executed.value.hasValue);

    assert(
        executed.value.value ==
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0C,
            0x00, 0x00,

            0x00,
            'n', 'e', 'w', '-', 'k', 'e', 'y',
            0x00,
            'n', 'e', 'w'
        ]
    );
}


/// A planned new WXXX field dispatches through the v2.3 user-URL serializer.
unittest
{
    const projection =
        Id3v23CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        userUrlField(
            "key",
            "abc"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 1);

    auto serialized =
        serializeId3v23PlannedNewFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

            0x00,
            'k', 'e', 'y',
            0x00,
            'a', 'b', 'c'
        ]
    );
}


/// A modified mapped WXXX frame dispatches to user-URL regeneration.
unittest
{
    const ubyte[] sourceBytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

            0x00,
            'k', 'e', 'y',
            0x00,
            'o', 'l', 'd'
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            userUrlField(
                "key",
                "old"
            )
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        userUrlField(
            "new-key",
            "new"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.regenerationCount == 1);

    auto executed =
        serializeId3v23PlannedRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);
    assert(executed.value.hasValue);

    assert(
        executed.value.value ==
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0C,
            0x00, 0x00,

            0x00,
            'n', 'e', 'w', '-', 'k', 'e', 'y',
            0x00,
            'n', 'e', 'w'
        ]
    );
}


/// A planned new COMM field dispatches through the v2.3 language-text serializer.
unittest
{
    const projection =
        Id3v23CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        languageTextField(
            "comment",
            "eng",
            "note",
            "hello"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 1);

    auto serialized =
        serializeId3v23PlannedNewFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            0x00,
            'e', 'n', 'g',
            'n', 'o', 't', 'e',
            0x00,
            'h', 'e', 'l', 'l', 'o'
        ]
    );
}


/// A modified mapped USLT frame dispatches to language-text regeneration.
unittest
{
    const ubyte[] sourceBytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x0B,
            0x00, 0x00,

            0x00,
            'e', 'n', 'g',
            'k', 'e', 'y',
            0x00,
            'o', 'l', 'd'
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            languageTextField(
                "lyrics",
                "eng",
                "key",
                "old"
            )
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        languageTextField(
            "lyrics",
            "eng",
            "new-key",
            "new"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.regenerationCount == 1);

    auto executed =
        serializeId3v23PlannedRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);
    assert(executed.value.hasValue);

    assert(
        executed.value.value ==
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x0F,
            0x00, 0x00,

            0x00,
            'e', 'n', 'g',
            'n', 'e', 'w', '-', 'k', 'e', 'y',
            0x00,
            'n', 'e', 'w'
        ]
    );
}


/// A planned new PRIV field dispatches through the v2.3 private serializer.
unittest
{
    const projection =
        Id3v23CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        privateField(
            "owner",
            [
                cast(ubyte) 0x01,
                cast(ubyte) 0x00,
                cast(ubyte) 0xFF
            ]
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 1);

    auto serialized =
        serializeId3v23PlannedNewFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            'o', 'w', 'n', 'e', 'r',
            0x00,

            0x01,
            0x00,
            0xFF
        ]
    );
}


/// A modified mapped PRIV frame dispatches to private-data regeneration.
unittest
{
    const ubyte[] sourceBytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

            'o', 'w', 'n', 'e', 'r',
            0x00,
            0x01,
            0x02
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            privateField(
                "owner",
                [
                    cast(ubyte) 0x01,
                    cast(ubyte) 0x02
                ]
            )
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        privateField(
            "new-owner",
            [
                cast(ubyte) 0xAA,
                cast(ubyte) 0x00
            ]
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.regenerationCount == 1);

    auto executed =
        serializeId3v23PlannedRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);
    assert(executed.value.hasValue);

    assert(
        executed.value.value ==
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x0C,
            0x00, 0x00,

            'n', 'e', 'w', '-', 'o', 'w', 'n', 'e', 'r',
            0x00,

            0xAA,
            0x00
        ]
    );
}


/// A planned new UFID field dispatches through the v2.3 identifier serializer.
unittest
{
    const projection =
        Id3v23CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        uniqueFileIdentifierField(
            "owner",
            [
                cast(ubyte) 0x11,
                cast(ubyte) 0x00,
                cast(ubyte) 0xFF
            ]
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 1);

    auto serialized =
        serializeId3v23PlannedNewFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            'o', 'w', 'n', 'e', 'r',
            0x00,

            0x11,
            0x00,
            0xFF
        ]
    );
}


/// A modified mapped UFID frame dispatches to identifier regeneration.
unittest
{
    const ubyte[] sourceBytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

            'o', 'w', 'n', 'e', 'r',
            0x00,
            0x01,
            0x02
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            uniqueFileIdentifierField(
                "owner",
                [
                    cast(ubyte) 0x01,
                    cast(ubyte) 0x02
                ]
            )
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        uniqueFileIdentifierField(
            "new-owner",
            [
                cast(ubyte) 0xAA,
                cast(ubyte) 0x00
            ]
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.regenerationCount == 1);

    auto executed =
        serializeId3v23PlannedRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);
    assert(executed.value.hasValue);

    assert(
        executed.value.value ==
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x0C,
            0x00, 0x00,

            'n', 'e', 'w', '-', 'o', 'w', 'n', 'e', 'r',
            0x00,

            0xAA,
            0x00
        ]
    );
}


/// A planned new APIC field dispatches through the v2.3 picture serializer.
unittest
{
    const projection =
        Id3v23CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        embeddedPictureField(
            "frontCover",
            "Front",
            "image/jpeg",
            [
                cast(ubyte) 0xFF,
                cast(ubyte) 0xD8
            ]
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 1);

    auto serialized =
        serializeId3v23PlannedNewFrame(
            edit,
            plan,
            0
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x15,
            0x00, 0x00,

            0x00,

            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g',
            0x00,

            0x03,

            'F', 'r', 'o', 'n', 't',
            0x00,

            0xFF,
            0xD8
        ]
    );
}


/// A modified mapped APIC frame dispatches to picture regeneration.
unittest
{
    const ubyte[] sourceBytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x10,
            0x00, 0x00,

            0x00,

            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g',
            0x00,

            0x03,

            0x00,

            0x01,
            0x02
        ];

    const projection =
        projectionWithMappedFrame(
            sourceBytes,
            embeddedPictureField(
                "frontCover",
                "",
                "image/jpeg",
                [
                    cast(ubyte) 0x01,
                    cast(ubyte) 0x02
                ]
            )
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        embeddedPictureField(
            "frontCover",
            "Front",
            "image/jpeg",
            [
                cast(ubyte) 0xAA,
                cast(ubyte) 0x00
            ]
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.regenerationCount == 1);

    auto executed =
        serializeId3v23PlannedRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);
    assert(executed.value.hasValue);

    assert(
        executed.value.value ==
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x15,
            0x00, 0x00,

            0x00,

            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g',
            0x00,

            0x03,

            'F', 'r', 'o', 'n', 't',
            0x00,

            0xAA,
            0x00
        ]
    );
}


/// A plan cannot be executed against an unrelated replacement overlay.
unittest
{
    const projection =
        Id3v23CanonicalProjection.init;

    auto plannedEdit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    plannedEdit.appendNewField(
        textField(
            "title",
            "Title"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            plannedEdit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto otherEdit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    otherEdit.appendNewField(
        textField(
            "album",
            "Album"
        )
    );

    auto serialized =
        serializeId3v23PlannedNewFrame(
            otherEdit,
            plan,
            0
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );
}


/// Out-of-range new-frame plan indices remain structured writer failures.
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

    auto serialized =
        serializeId3v23PlannedNewFrame(
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


/// Unsupported source transformations remain inner writer failures.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x80,

            // Declared decompressed size.
            0x00, 0x00, 0x00, 0x01,

            // Opaque compressed payload.
            0x55
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
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto executed =
        serializeId3v23PlannedRegeneration(
            projection,
            edit,
            plan,
            0
        );

    assert(executed.hasValue);

    assert(executed.value.hasError);

    assert(
        executed.value.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
