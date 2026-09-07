/++
Complete semantic write planning for one canonical ID3v2.3 tag edit.

This module combines:

- format-independent canonical multiplicity validation;
- derivation of mutations for existing native frames;
- preservation/discard/regeneration planning for existing frames;
- representability validation for replacement canonical fields;
- planning of newly introduced canonical fields.

No bytes are serialized here.

A writable result means that the complete edit is semantically
representable under the selected writer policy. Physical serialization,
tag sizing, unsynchronisation, extended-header handling, padding and
container updating remain later steps.
+/
module audiotag.id3v2.v23.tag_write_plan;

import audiotag.metadata.edit :
    MetadataSourceFieldEditState,
    MetadataTreeEdit;

import audiotag.metadata.edit_validation :
    MetadataTreeEditMultiplicityResult,
    validateMetadataTreeEditMultiplicity;

import audiotag.id3v2.v23.canonical_projection :
    Id3v23CanonicalFrameRecord,
    Id3v23CanonicalProjection;

import audiotag.id3v2.v23.edit_mutation :
    deriveId3v23CanonicalFrameMutations;

import audiotag.id3v2.v23.frame_write_plan :
    Id3v23CanonicalFrameMutation;

import audiotag.id3v2.v23.new_frame_plan :
    Id3v23CanonicalFieldPlan,
    Id3v23NewFramePlan,
    planId3v23CanonicalField,
    planId3v23NewCanonicalFrame;

import audiotag.id3v2.v23.sequence_write_plan :
    Id3v23FrameSequenceWritePlan,
    planId3v23ExistingFrameSequenceWrite;

import audiotag.id3v2.v23.writer_policy :
    Id3v23WriteContext,
    Id3v23WriterPolicy;


/++
Planning outcome for regeneration of one modified existing native frame.

Current implemented canonical mappings are one-native-frame to
one-canonical-field. The explicit `unsupportedCanonicalShape` outcome
prevents future one-to-many mappings from being silently serialized
incorrectly before a corresponding native regeneration model exists.
+/
enum Id3v23ExistingFrameRegenerationStatus : ubyte
{
    ready,
    unsupportedCanonicalShape,
    unrepresentableField
}


/++
Regeneration plan for one modified existing native frame.
+/
struct Id3v23ExistingFrameRegenerationPlan
{
    /// Index in the original native frame sequence.
    size_t sourceFrameIndex;

    /// First canonical source-field index associated with the frame.
    size_t canonicalSourceIndex;

    /// Regeneration planning outcome.
    Id3v23ExistingFrameRegenerationStatus status;

    /// Canonical-field target plan when the shape is supported.
    Id3v23CanonicalFieldPlan fieldPlan;

    /++
    Returns whether this modified existing frame can be regenerated.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return status ==
            Id3v23ExistingFrameRegenerationStatus.ready;
    }
}


/++
Complete semantic write plan for one edited ID3v2.3 tag.

The plan retains every relevant sub-plan so callers can inspect why a
write is blocked instead of receiving only a boolean result.
+/
struct Id3v23TagWritePlan
{
private:
    Id3v23ExistingFrameRegenerationPlan[] _regenerations;
    Id3v23NewFramePlan[] _newFrames;

    size_t _regenerationRejectCount;
    size_t _newFrameRejectCount;

public:
    /// Canonical resulting-tree multiplicity validation.
    MetadataTreeEditMultiplicityResult multiplicity;

    /// Preservation actions for every existing native frame.
    Id3v23FrameSequenceWritePlan existingFrames;

    /++
    Regeneration details for modified existing native frames.

    Entries preserve original native frame order.
    +/
    @property
    const(Id3v23ExistingFrameRegenerationPlan)[]
    regenerations() const
        @safe pure nothrow @nogc
    {
        return _regenerations;
    }

    /++
    Plans for newly introduced canonical fields.

    Entries preserve `MetadataTreeEdit.newFields` insertion order.
    +/
    @property
    const(Id3v23NewFramePlan)[] newFrames() const
        @safe pure nothrow @nogc
    {
        return _newFrames;
    }

    /// Number of modified existing frames requiring regeneration.
    @property
    size_t regenerationCount() const
        @safe pure nothrow @nogc
    {
        return _regenerations.length;
    }

    /// Number of newly introduced canonical fields.
    @property
    size_t newFrameCount() const
        @safe pure nothrow @nogc
    {
        return _newFrames.length;
    }

    /// Number of replacement/regeneration plans that block writing.
    @property
    size_t regenerationRejectCount() const
        @safe pure nothrow @nogc
    {
        return _regenerationRejectCount;
    }

    /// Number of new canonical fields that cannot currently be written.
    @property
    size_t newFrameRejectCount() const
        @safe pure nothrow @nogc
    {
        return _newFrameRejectCount;
    }

    /++
    Returns whether the complete semantic edit can proceed to physical
    ID3v2.3 serialization.

    `true` requires:

    - valid canonical multiplicity;
    - no rejected existing-frame preservation action;
    - every modified existing frame to have a writable regeneration
      plan;
    - every new canonical field to have a writable native target.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            multiplicity.valid &&
            existingFrames.writable &&
            _regenerationRejectCount == 0 &&
            _newFrameRejectCount == 0;
    }

package:
    void appendRegeneration(
        Id3v23ExistingFrameRegenerationPlan plan
    )
        @safe
    {
        _regenerations ~= plan;

        if (!plan.writable)
            ++_regenerationRejectCount;
    }

    void appendNewFrame(
        Id3v23NewFramePlan plan
    )
        @safe
    {
        _newFrames ~= plan;

        if (!plan.writable)
            ++_newFrameRejectCount;
    }
}


/++
Plans regeneration of one modified existing native frame.

For the current reader mappings, one native mapped frame contributes one
canonical field. A future mapping contributing multiple canonical
fields requires an explicit native regeneration model and is rejected
until that model exists.

Params:
    sourceFrameIndex = Position in the original native frame sequence.
    record = Projection relationship of the modified native frame.
    edit = Canonical edit overlay.

Returns:
    Explicit regeneration plan.
+/
private Id3v23ExistingFrameRegenerationPlan
planExistingFrameRegeneration(
    size_t sourceFrameIndex,
    const(Id3v23CanonicalFrameRecord) record,
    const(MetadataTreeEdit) edit
)
    @safe
{
    if (record.canonicalCount != 1)
    {
        return
            Id3v23ExistingFrameRegenerationPlan(
                sourceFrameIndex,
                record.canonicalStart,
                Id3v23ExistingFrameRegenerationStatus
                    .unsupportedCanonicalShape,
                Id3v23CanonicalFieldPlan.init
            );
    }

    const canonicalSourceIndex =
        record.canonicalStart;

    const sourceEdit =
        edit.sourceEdit(
            canonicalSourceIndex
        );

    /*
     * With exactly one canonical field, `modified` native-frame
     * mutation can only arise from a canonical replacement.
     *
     * A removed field derives `removed`, and an unchanged field derives
     * `unchanged`. Therefore any other state is an internal planner
     * inconsistency.
     */
    assert(
        sourceEdit.state ==
        MetadataSourceFieldEditState.modified
    );

    const fieldPlan =
        planId3v23CanonicalField(
            sourceEdit.replacement
        );

    return
        Id3v23ExistingFrameRegenerationPlan(
            sourceFrameIndex,
            canonicalSourceIndex,
            fieldPlan.writable
                ? Id3v23ExistingFrameRegenerationStatus.ready
                : Id3v23ExistingFrameRegenerationStatus
                    .unrepresentableField,
            fieldPlan
        );
}


/++
Builds the complete semantic write plan for an edited ID3v2.3
canonical projection.

The edit overlay must correspond exactly to the projection's canonical
metadata tree.

The function deliberately continues planning after individual semantic
failures so the returned plan exposes all blockers that can be
determined at this stage.

Preconditions:
    `edit.sourceFieldCount == projection.metadata.length`.

Params:
    projection = Provenance-preserving native-plus-canonical reader
        projection.
    edit = Canonical edit overlay associated with `projection.metadata`.
    context = Whether the enclosing tag and/or file is being altered.
    policy = Native preservation policy.

Returns:
    Complete semantic tag write plan.
+/
Id3v23TagWritePlan
planId3v23CanonicalTagWrite(
    const(Id3v23CanonicalProjection) projection,
    const(MetadataTreeEdit) edit,
    Id3v23WriteContext context,
    Id3v23WriterPolicy policy =
        Id3v23WriterPolicy.init
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
        Id3v23TagWritePlan.init;

    result.multiplicity =
        validateMetadataTreeEditMultiplicity(
            source,
            edit
        );

    const mutations =
        deriveId3v23CanonicalFrameMutations(
            projection.frames,
            edit
        );

    result.existingFrames =
        planId3v23ExistingFrameSequenceWrite(
            projection.frames,
            mutations,
            context,
            policy
        );

    foreach (
        sourceFrameIndex,
        const record;
        projection.frames
    )
    {
        if (
            mutations[sourceFrameIndex] !=
            Id3v23CanonicalFrameMutation.modified
        )
        {
            continue;
        }

        result.appendRegeneration(
            planExistingFrameRegeneration(
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
            planId3v23NewCanonicalFrame(
                newFieldIndex,
                field
            )
        );
    }

    return result;
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.metadata.field :
        MetadataField,
        MetadataKey,
        MetadataLanguage;

    import audiotag.metadata.value :
        MetadataText,
        MetadataValue;

    import audiotag.id3v2.v23.canonical_mapping :
        Id3v23CanonicalMappingResult;

    import audiotag.id3v2.v23.frame_header :
        Id3v23FrameHeader,
        parseId3v23FrameHeader;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrame;


    private Id3v23FrameHeader testHeader(
        ubyte statusFlags = 0x00
    )
        @safe
    {
        const ubyte[] bytes =
            [
                'T', 'I', 'T', '2',
                0x00, 0x00, 0x00, 0x01,
                statusFlags,
                0x00
            ];

        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto parsed =
            cursor.parseId3v23FrameHeader();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }


    private Id3v23NativeFrame testNative(
        ubyte statusFlags = 0x00
    )
        @safe
    {
        auto native =
            Id3v23NativeFrame.init;

        native.envelope.header =
            testHeader(statusFlags);

        return native;
    }


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


    private Id3v23CanonicalProjection
    projectionWithMappedTitle(
        ubyte statusFlags = 0x00
    )
        @safe
    {
        auto projection =
            Id3v23CanonicalProjection.init;

        projection.append(
            testNative(statusFlags),
            Id3v23CanonicalMappingResult.success(
                textField(
                    "title",
                    "Original title"
                )
            )
        );

        return projection;
    }
}


/// A no-op edit preserves the original mapped frame and is writable.
unittest
{
    const projection =
        projectionWithMappedTitle();

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.unchanged()
        );

    assert(plan.writable);
    assert(plan.multiplicity.valid);

    assert(plan.existingFrames.length == 1);
    assert(plan.existingFrames.preserveCount == 1);
    assert(plan.existingFrames.regenerateCount == 0);

    assert(plan.regenerationCount == 0);
    assert(plan.regenerationRejectCount == 0);

    assert(plan.newFrameCount == 0);
    assert(plan.newFrameRejectCount == 0);
}


/// A representable replacement produces one writable regeneration plan.
unittest
{
    const projection =
        projectionWithMappedTitle();

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        textField(
            "title",
            "Replacement title"
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

    assert(plan.regenerationCount == 1);
    assert(plan.regenerationRejectCount == 0);

    assert(
        plan.regenerations[0].writable
    );

    assert(
        plan.regenerations[0]
            .fieldPlan.target.frameId ==
        "TIT2"
    );
}


/// A canonical replacement that TIT2 cannot retain blocks the tag write.
unittest
{
    const projection =
        projectionWithMappedTitle();

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    auto replacement =
        textField(
            "title",
            "Replacement title"
        );

    replacement.description =
        "unsupported-in-TIT2";

    edit.replaceSourceField(
        0,
        replacement
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);

    /*
     * Native preservation planning alone permits regeneration, but the
     * semantic replacement plan correctly blocks the complete write.
     */
    assert(
        plan.existingFrames.regenerateCount ==
        1
    );

    assert(plan.existingFrames.writable);

    assert(plan.regenerationCount == 1);
    assert(plan.regenerationRejectCount == 1);

    assert(
        !plan.regenerations[0].writable
    );
}


/// Removing a writable mapped field discards its native frame cleanly.
unittest
{
    const projection =
        projectionWithMappedTitle();

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.removeSourceField(0);

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    assert(
        plan.existingFrames.discardCount ==
        1
    );

    assert(plan.regenerationCount == 0);
}


/// Removing a read-only mapped field blocks the complete write.
unittest
{
    const projection =
        projectionWithMappedTitle(
            0x20
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.removeSourceField(0);

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);

    assert(
        plan.existingFrames.rejectCount ==
        1
    );
}


/// A valid new canonical field is included in the complete tag plan.
unittest
{
    const projection =
        projectionWithMappedTitle();

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    auto comment =
        textField(
            "comment",
            "New comment"
        );

    comment.language =
        MetadataLanguage("eng");

    edit.appendNewField(
        comment
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 1);
    assert(plan.newFrameRejectCount == 0);

    assert(plan.newFrames[0].writable);

    assert(
        plan.newFrames[0]
            .target.frameId ==
        "COMM"
    );
}


/// An unrepresentable new field blocks the complete tag write.
unittest
{
    const projection =
        projectionWithMappedTitle();

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        textField(
            "comment",
            "Missing language"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);

    assert(plan.newFrameCount == 1);
    assert(plan.newFrameRejectCount == 1);
}


/// Canonical multiplicity violations block otherwise representable fields.
unittest
{
    const projection =
        projectionWithMappedTitle();

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        textField(
            "title",
            "Second title"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);
    assert(!plan.multiplicity.valid);

    /*
     * The new field itself is representable as TIT2; the whole-tree
     * multiplicity rule is what correctly blocks the write.
     */
    assert(plan.newFrameCount == 1);
    assert(plan.newFrames[0].writable);
}


/// Changing a canonical key participates in both target and multiplicity planning.
unittest
{
    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        testNative(),
        Id3v23CanonicalMappingResult.success(
            textField(
                "album",
                "Existing album"
            )
        )
    );

    projection.append(
        testNative(),
        Id3v23CanonicalMappingResult.success(
            textField(
                "title",
                "Original title"
            )
        )
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        1,
        textField(
            "album",
            "Replacement album"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(!plan.writable);
    assert(!plan.multiplicity.valid);

    assert(plan.regenerationCount == 1);

    assert(
        plan.regenerations[0]
            .fieldPlan.target.frameId ==
        "TALB"
    );
}
