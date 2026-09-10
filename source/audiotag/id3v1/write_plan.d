/++
Canonical edit planning for one existing ID3v1 tag.

The planner bridges the format-independent `MetadataTreeEdit` overlay and the
native fixed-size ID3v1 serializer.

Core preservation rule:

- begin with the parsed native tag bytes;
- leave unchanged canonical slots byte-for-byte native;
- clear only source slots whose canonical field was removed or retargeted;
- encode only modified/new canonical fields;
- preserve native-only year/genre/text bytes unless an edit explicitly targets
  that native slot.

Because ID3v1 has exactly one physical slot for each supported semantic target,
format-independent metadata multiplicity is not sufficient. In particular,
canonical `comment` is repeatable in the common model but ID3v1 can store only
one comment. This planner therefore rejects effective slot collisions.

Revision changes are also explicit. A resulting track field requires ID3v1.1.
Removing the final track yields ID3v1.0. Upgrading an untouched v1.0 comment to
v1.1 would shorten its native region from 30 to 28 bytes, so that transition is
allowed only when the two displaced source bytes are both zero. If the comment
slot is itself intentionally edited/removed, those source bytes may be replaced.
+/
module audiotag.id3v1.write_plan;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode;

import audiotag.id3v1.canonical :
    Id3v1CanonicalTag;

import audiotag.id3v1.canonical_write :
    Id3v1CanonicalFieldEncoding,
    Id3v1CanonicalWriteTarget,
    encodeId3v1CanonicalField;

import audiotag.id3v1.tag :
    Id3v1Revision;

import audiotag.id3v1.tag_write :
    Id3v1NativeTagWriteFields;

import audiotag.metadata.edit :
    MetadataSourceFieldEditState,
    MetadataTreeEdit;

import audiotag.metadata.edit_validation :
    MetadataTreeEditMultiplicityResult,
    validateMetadataTreeEditMultiplicity;

import audiotag.metadata.field :
    MetadataField;


/++
Primary result of ID3v1 canonical edit planning.
+/
enum Id3v1CanonicalTagWriteStatus : ubyte
{
    ready,

    /// The effective canonical tree violates common registry multiplicity.
    multiplicityExceeded,

    /// More than one effective canonical field maps to one fixed ID3v1 slot.
    slotConflict,

    /// A changed/new canonical field cannot be represented losslessly.
    unrepresentableField,

    /// Source canonical projection contains an unexpected target.
    inconsistentProjection,

    /// v1.0 -> v1.1 would discard untouched native comment-tail bytes.
    nativeTransitionWouldDiscardData
}


/++
Complete plan for serializing one edited existing ID3v1 tag.

When `writable` is true, `nativeFields` already contains the complete resulting
native field set and can be passed directly to `serializeId3v1NativeTag`.

`fieldIndex` identifies the source canonical index for a failed modified field,
or the new-field index when `newField` is true.

`error` carries the underlying canonical-field encoding failure when status is
`unrepresentableField`.
+/
struct Id3v1CanonicalTagWritePlan
{
    Id3v1CanonicalTagWriteStatus status;

    MetadataTreeEditMultiplicityResult multiplicity;

    Id3v1Revision revision;
    Id3v1NativeTagWriteFields nativeFields;

    Id3v1CanonicalWriteTarget conflictTarget;

    bool newField;
    size_t fieldIndex;

    SerializationError error;


    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            status ==
                Id3v1CanonicalTagWriteStatus.ready &&
            multiplicity.valid;
    }
}


private bool
targetForKey(
    string key,
    out Id3v1CanonicalWriteTarget target
)
    @safe pure nothrow @nogc
{
    if (key == "title")
    {
        target = Id3v1CanonicalWriteTarget.title;
        return true;
    }

    if (key == "artist")
    {
        target = Id3v1CanonicalWriteTarget.artist;
        return true;
    }

    if (key == "album")
    {
        target = Id3v1CanonicalWriteTarget.album;
        return true;
    }

    if (key == "releaseDate")
    {
        target = Id3v1CanonicalWriteTarget.year;
        return true;
    }

    if (key == "comment")
    {
        target = Id3v1CanonicalWriteTarget.comment;
        return true;
    }

    if (key == "track")
    {
        target = Id3v1CanonicalWriteTarget.track;
        return true;
    }

    if (key == "genre")
    {
        target = Id3v1CanonicalWriteTarget.genre;
        return true;
    }

    return false;
}


private Id3v1NativeTagWriteFields
sourceNativeFields(
    const(Id3v1CanonicalTag) source
)
    @safe pure nothrow @nogc
{
    return
        Id3v1NativeTagWriteFields(
            source.native.revision,
            source.native.title.data,
            source.native.artist.data,
            source.native.album.data,
            source.native.year.data,
            source.native.comment.data,
            source.native.track,
            source.native.genre
        );
}


private bool
claimTarget(
    ref bool[7] occupied,
    Id3v1CanonicalWriteTarget target
)
    @safe pure nothrow @nogc
{
    const index =
        cast(size_t)
            target;

    assert(index < occupied.length);

    if (occupied[index])
        return false;

    occupied[index] =
        true;

    return true;
}


private bool
effectiveTrackPresent(
    const bool[7] occupied
)
    @safe pure nothrow @nogc
{
    return
        occupied[
            cast(size_t)
                Id3v1CanonicalWriteTarget.track
        ];
}


private bool
sourceCommentWasIntentionallyChanged(
    const(Id3v1CanonicalTag) source,
    const(MetadataTreeEdit) edit,
    const bool[7] occupied
)
    @safe pure nothrow @nogc
{
    bool sourceHasComment;
    bool sourceCommentUnchanged;

    foreach (
        sourceIndex;
        0 .. source.metadata.length
    )
    {
        if (
            source.metadata[sourceIndex]
                .key.name !=
            "comment"
        )
        {
            continue;
        }

        sourceHasComment = true;

        sourceCommentUnchanged =
            edit.sourceEdit(sourceIndex)
                .state ==
            MetadataSourceFieldEditState.unchanged;

        break;
    }

    if (
        sourceHasComment &&
        !sourceCommentUnchanged
    )
    {
        return true;
    }

    const effectiveCommentPresent =
        occupied[
            cast(size_t)
                Id3v1CanonicalWriteTarget.comment
        ];

    /*
     * If there was no unchanged source comment but one effective comment now
     * exists, some modified/new field intentionally targets the comment slot.
     */
    if (
        effectiveCommentPresent &&
        !sourceCommentUnchanged
    )
    {
        return true;
    }

    return false;
}


private void
adaptRevision(
    ref Id3v1NativeTagWriteFields fields,
    const(Id3v1CanonicalTag) source,
    Id3v1Revision targetRevision,
    bool commentSlotIntentionallyChanged
)
    @safe
{
    if (
        source.native.revision ==
        targetRevision
    )
    {
        fields.revision =
            targetRevision;

        return;
    }

    if (
        source.native.revision ==
            Id3v1Revision.v11 &&
        targetRevision ==
            Id3v1Revision.v10
    )
    {
        auto expanded =
            new ubyte[30];

        expanded[0 .. 28] =
            source.native.comment.data[];

        /*
         * Bytes 28 and 29 remain zero. They replace the old v1.1 marker and
         * track byte after the explicit removal/retargeting of the track.
         */
        fields.comment =
            expanded;

        fields.track = 0;
        fields.revision =
            Id3v1Revision.v10;

        return;
    }

    assert(
        source.native.revision ==
            Id3v1Revision.v10 &&
        targetRevision ==
            Id3v1Revision.v11
    );

    if (commentSlotIntentionallyChanged)
    {
        fields.comment =
            new ubyte[28];
    }
    else
    {
        /*
         * Caller checked the displaced bytes before reaching this helper.
         * Preserve the first 28 bytes zero-copy.
         */
        fields.comment =
            source.native.comment.data[
                0 .. 28
            ];
    }

    fields.track = 0;
    fields.revision =
        Id3v1Revision.v11;
}


private void
clearTarget(
    ref Id3v1NativeTagWriteFields fields,
    Id3v1CanonicalWriteTarget target
)
    @safe
{
    final switch (target)
    {
        case Id3v1CanonicalWriteTarget.title:
            fields.title =
                new ubyte[30];
            return;

        case Id3v1CanonicalWriteTarget.artist:
            fields.artist =
                new ubyte[30];
            return;

        case Id3v1CanonicalWriteTarget.album:
            fields.album =
                new ubyte[30];
            return;

        case Id3v1CanonicalWriteTarget.year:
            fields.year =
                new ubyte[4];
            return;

        case Id3v1CanonicalWriteTarget.comment:
            fields.comment =
                fields.revision ==
                    Id3v1Revision.v11
                        ? new ubyte[28]
                        : new ubyte[30];
            return;

        case Id3v1CanonicalWriteTarget.track:
            fields.track = 0;
            return;

        case Id3v1CanonicalWriteTarget.genre:
            fields.genre = 255;
            return;
    }
}


private void
applyEncoding(
    ref Id3v1NativeTagWriteFields fields,
    const(Id3v1CanonicalFieldEncoding) encoding
)
    @safe pure nothrow @nogc
{
    final switch (encoding.target)
    {
        case Id3v1CanonicalWriteTarget.title:
            fields.title =
                encoding.bytes;
            return;

        case Id3v1CanonicalWriteTarget.artist:
            fields.artist =
                encoding.bytes;
            return;

        case Id3v1CanonicalWriteTarget.album:
            fields.album =
                encoding.bytes;
            return;

        case Id3v1CanonicalWriteTarget.year:
            fields.year =
                encoding.bytes;
            return;

        case Id3v1CanonicalWriteTarget.comment:
            fields.comment =
                encoding.bytes;
            return;

        case Id3v1CanonicalWriteTarget.track:
            fields.track =
                encoding.scalar;
            return;

        case Id3v1CanonicalWriteTarget.genre:
            fields.genre =
                encoding.scalar;
            return;
    }
}


private Id3v1CanonicalTagWritePlan
failedFieldPlan(
    Id3v1CanonicalTagWritePlan plan,
    bool newField,
    size_t fieldIndex,
    SerializationError error
)
    @safe pure nothrow @nogc
{
    plan.status =
        Id3v1CanonicalTagWriteStatus
            .unrepresentableField;

    plan.newField =
        newField;

    plan.fieldIndex =
        fieldIndex;

    plan.error =
        error;

    return plan;
}


/++
Plans canonical edits against one parsed existing ID3v1 tag.

The edit overlay must correspond exactly to `source.metadata`.

A no-op edit returns the source native fields unchanged, including any
native-only bytes.

For changed edits, effective canonical fields are first mapped to fixed ID3v1
targets. Any unknown key or duplicate target is rejected before native mutation.
The presence of an effective `track` target chooses ID3v1.1; otherwise the
result is ID3v1.0.

The planner then clears source slots for modified/removed canonical fields and
applies encodings only for modified/new effective fields. Unchanged source
fields therefore retain their original native bytes.

Preconditions:
    `edit.sourceFieldCount == source.metadata.length`.
+/
Id3v1CanonicalTagWritePlan
planId3v1CanonicalTagWrite(
    const(Id3v1CanonicalTag) source,
    const(MetadataTreeEdit) edit
)
    @safe
{
    assert(
        edit.sourceFieldCount ==
        source.metadata.length
    );

    auto plan =
        Id3v1CanonicalTagWritePlan.init;

    plan.status =
        Id3v1CanonicalTagWriteStatus.ready;

    plan.multiplicity =
        validateMetadataTreeEditMultiplicity(
            source.metadata,
            edit
        );

    plan.revision =
        source.native.revision;

    plan.nativeFields =
        sourceNativeFields(
            source
        );

    if (!plan.multiplicity.valid)
    {
        plan.status =
            Id3v1CanonicalTagWriteStatus
                .multiplicityExceeded;

        return plan;
    }

    if (edit.unchanged)
        return plan;

    bool[7] occupied;

    /*
     * Preflight every effective source field. This establishes unique physical
     * slot ownership before changing any native field bytes.
     */
    foreach (
        sourceIndex;
        0 .. source.metadata.length
    )
    {
        const sourceEdit =
            edit.sourceEdit(
                sourceIndex
            );

        const(MetadataField)* effective;

        final switch (sourceEdit.state)
        {
            case MetadataSourceFieldEditState.unchanged:
                effective =
                    &source.metadata.fields[
                        sourceIndex
                    ];
                break;

            case MetadataSourceFieldEditState.modified:
                effective =
                    &sourceEdit.replacement;
                break;

            case MetadataSourceFieldEditState.removed:
                continue;
        }

        Id3v1CanonicalWriteTarget target;

        if (
            !targetForKey(
                effective.key.name,
                target
            )
        )
        {
            plan.status =
                Id3v1CanonicalTagWriteStatus
                    .unrepresentableField;

            plan.newField = false;
            plan.fieldIndex = sourceIndex;
            plan.error =
                SerializationError(
                    SerializationErrorCode
                        .unsupportedRepresentation
                );

            return plan;
        }

        if (!claimTarget(occupied, target))
        {
            plan.status =
                Id3v1CanonicalTagWriteStatus
                    .slotConflict;

            plan.conflictTarget =
                target;

            plan.newField = false;
            plan.fieldIndex =
                sourceIndex;

            return plan;
        }
    }

    foreach (
        newIndex, const field;
        edit.newFields
    )
    {
        Id3v1CanonicalWriteTarget target;

        if (
            !targetForKey(
                field.key.name,
                target
            )
        )
        {
            plan.status =
                Id3v1CanonicalTagWriteStatus
                    .unrepresentableField;

            plan.newField = true;
            plan.fieldIndex = newIndex;
            plan.error =
                SerializationError(
                    SerializationErrorCode
                        .unsupportedRepresentation
                );

            return plan;
        }

        if (!claimTarget(occupied, target))
        {
            plan.status =
                Id3v1CanonicalTagWriteStatus
                    .slotConflict;

            plan.conflictTarget =
                target;

            plan.newField = true;
            plan.fieldIndex =
                newIndex;

            return plan;
        }
    }

    const targetRevision =
        effectiveTrackPresent(occupied)
            ? Id3v1Revision.v11
            : Id3v1Revision.v10;

    const commentChanged =
        sourceCommentWasIntentionallyChanged(
            source,
            edit,
            occupied
        );

    if (
        source.native.revision ==
            Id3v1Revision.v10 &&
        targetRevision ==
            Id3v1Revision.v11 &&
        !commentChanged
    )
    {
        assert(
            source.native.comment.length ==
            30
        );

        if (
            source.native.comment.data[28] != 0 ||
            source.native.comment.data[29] != 0
        )
        {
            plan.status =
                Id3v1CanonicalTagWriteStatus
                    .nativeTransitionWouldDiscardData;

            return plan;
        }
    }

    adaptRevision(
        plan.nativeFields,
        source,
        targetRevision,
        commentChanged
    );

    plan.revision =
        targetRevision;

    /*
     * Remove native manifestations of source canonical fields that no longer
     * remain unchanged. Modified fields are cleared first because their
     * replacement is allowed to target a different ID3v1 slot.
     */
    foreach (
        sourceIndex;
        0 .. source.metadata.length
    )
    {
        const sourceEdit =
            edit.sourceEdit(
                sourceIndex
            );

        if (
            sourceEdit.state ==
            MetadataSourceFieldEditState.unchanged
        )
        {
            continue;
        }

        Id3v1CanonicalWriteTarget sourceTarget;

        if (
            !targetForKey(
                source.metadata[sourceIndex]
                    .key.name,
                sourceTarget
            )
        )
        {
            plan.status =
                Id3v1CanonicalTagWriteStatus
                    .inconsistentProjection;

            plan.newField = false;
            plan.fieldIndex =
                sourceIndex;

            return plan;
        }

        clearTarget(
            plan.nativeFields,
            sourceTarget
        );
    }

    /*
     * Encode only changed source fields. Unchanged fields remain in their
     * source-native representation.
     */
    foreach (
        sourceIndex;
        0 .. source.metadata.length
    )
    {
        const sourceEdit =
            edit.sourceEdit(
                sourceIndex
            );

        if (
            sourceEdit.state !=
            MetadataSourceFieldEditState.modified
        )
        {
            continue;
        }

        auto encoded =
            encodeId3v1CanonicalField(
                sourceEdit.replacement,
                targetRevision
            );

        if (encoded.hasError)
        {
            return
                failedFieldPlan(
                    plan,
                    false,
                    sourceIndex,
                    encoded.error
                );
        }

        applyEncoding(
            plan.nativeFields,
            encoded.value
        );
    }

    foreach (
        newIndex, const field;
        edit.newFields
    )
    {
        auto encoded =
            encodeId3v1CanonicalField(
                field,
                targetRevision
            );

        if (encoded.hasError)
        {
            return
                failedFieldPlan(
                    plan,
                    true,
                    newIndex,
                    encoded.error
                );
        }

        applyEncoding(
            plan.nativeFields,
            encoded.value
        );
    }

    /*
     * A ready v1.1 plan must have received one effective non-zero track
     * encoding. A ready v1.0 plan must not retain one.
     */
    if (
        targetRevision ==
            Id3v1Revision.v11 &&
        plan.nativeFields.track == 0
    )
    {
        plan.status =
            Id3v1CanonicalTagWriteStatus
                .inconsistentProjection;

        return plan;
    }

    if (
        targetRevision ==
            Id3v1Revision.v10
    )
    {
        plan.nativeFields.track = 0;
    }

    return plan;
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v1.canonical :
        parseId3v1CanonicalTag;

    import audiotag.metadata.field :
        MetadataField,
        MetadataKey;

    import audiotag.metadata.value :
        MetadataPosition,
        MetadataText,
        MetadataTextList,
        MetadataValue;


    private Id3v1CanonicalTag
    parseTestTag(
        ref ubyte[128] bytes
    )
        @safe
    {
        auto parsed =
            parseId3v1CanonicalTag(
                ByteSpan(
                    bytes[]
                )
            );

        assert(parsed.hasValue);

        return
            parsed.value;
    }


    private void
    setSignature(
        ref ubyte[128] bytes
    )
        @safe pure nothrow @nogc
    {
        bytes[0] = 'T';
        bytes[1] = 'A';
        bytes[2] = 'G';

        /*
         * Avoid accidental canonical genre projection in tests that do not
         * care about genre.
         */
        bytes[127] = 255;
    }


    private MetadataField
    textField(
        string key,
        string text
    )
        @safe
    {
        MetadataValue value =
            MetadataText(text);

        return
            MetadataField(
                MetadataKey(key),
                value
            );
    }


    private MetadataField
    trackField(
        ulong number
    )
        @safe
    {
        MetadataValue value =
            MetadataPosition.numberOnly(
                number
            );

        return
            MetadataField(
                MetadataKey("track"),
                value
            );
    }


    private MetadataField
    genreField(
        string genre
    )
        @safe
    {
        MetadataValue value =
            MetadataTextList(
                [genre]
            );

        return
            MetadataField(
                MetadataKey("genre"),
                value
            );
    }
}


/// A no-op plan preserves every native byte, including non-canonical data.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[3] = 'T';

    bytes[93] = '2';
    bytes[94] = '0';
    bytes[95] = 'X';
    bytes[96] = '6';

    bytes[127] = 250;

    auto source =
        parseTestTag(bytes);

    auto edit =
        MetadataTreeEdit.forSource(
            source.metadata
        );

    auto plan =
        planId3v1CanonicalTagWrite(
            source,
            edit
        );

    assert(plan.writable);
    assert(plan.revision == Id3v1Revision.v10);

    assert(plan.nativeFields.title == bytes[3 .. 33]);
    assert(plan.nativeFields.year == bytes[93 .. 97]);
    assert(plan.nativeFields.genre == 250);
}


/// Modifying title preserves unrelated native-only year and genre bytes.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[3] = 'A';

    bytes[93] = 'X';
    bytes[94] = 'X';
    bytes[95] = 'X';
    bytes[96] = 'X';

    bytes[127] = 250;

    auto source =
        parseTestTag(bytes);

    assert(source.metadata.length == 1);
    assert(source.metadata[0].key.name == "title");

    auto edit =
        MetadataTreeEdit.forSource(
            source.metadata
        );

    edit.replaceSourceField(
        0,
        textField(
            "title",
            "B"
        )
    );

    auto plan =
        planId3v1CanonicalTagWrite(
            source,
            edit
        );

    assert(plan.writable);
    assert(plan.nativeFields.title[0] == 'B');
    assert(plan.nativeFields.title[1] == 0);

    assert(
        plan.nativeFields.year ==
        bytes[93 .. 97]
    );

    assert(plan.nativeFields.genre == 250);
}


/// Removing a recognized canonical genre writes the native unknown sentinel.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);
    bytes[127] = 17;

    auto source =
        parseTestTag(bytes);

    assert(source.metadata.length == 1);
    assert(source.metadata[0].key.name == "genre");

    auto edit =
        MetadataTreeEdit.forSource(
            source.metadata
        );

    edit.removeSourceField(0);

    auto plan =
        planId3v1CanonicalTagWrite(
            source,
            edit
        );

    assert(plan.writable);
    assert(plan.nativeFields.genre == 255);
}


/// Adding a track upgrades v1.0 when displaced untouched comment bytes are zero.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[97] = 'C';

    /*
     * v1.0 comment tail is zero-filled, so converting bytes 125/126 into the
     * v1.1 marker/track pair loses no native-only bytes.
     */
    bytes[125] = 0;
    bytes[126] = 0;

    auto source =
        parseTestTag(bytes);

    assert(source.native.revision == Id3v1Revision.v10);

    auto edit =
        MetadataTreeEdit.forSource(
            source.metadata
        );

    edit.appendNewField(
        trackField(7)
    );

    auto plan =
        planId3v1CanonicalTagWrite(
            source,
            edit
        );

    assert(plan.writable);
    assert(plan.revision == Id3v1Revision.v11);
    assert(plan.nativeFields.comment.length == 28);
    assert(plan.nativeFields.comment[0] == 'C');
    assert(plan.nativeFields.track == 7);
}


/// v1.0 -> v1.1 refuses to discard untouched native comment-tail bytes.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[97] = 'C';

    /*
     * Non-zero byte 125 prevents v1.1 detection and is part of the native
     * 30-byte v1.0 comment field.
     */
    bytes[125] = 'X';
    bytes[126] = 'Y';

    auto source =
        parseTestTag(bytes);

    assert(source.native.revision == Id3v1Revision.v10);

    auto edit =
        MetadataTreeEdit.forSource(
            source.metadata
        );

    edit.appendNewField(
        trackField(7)
    );

    auto plan =
        planId3v1CanonicalTagWrite(
            source,
            edit
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v1CanonicalTagWriteStatus
            .nativeTransitionWouldDiscardData
    );
}


/// Explicit comment replacement permits v1.0 -> v1.1 despite old tail bytes.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[97] = 'C';
    bytes[125] = 'X';
    bytes[126] = 'Y';

    auto source =
        parseTestTag(bytes);

    size_t commentIndex =
        size_t.max;

    foreach (
        index;
        0 .. source.metadata.length
    )
    {
        if (
            source.metadata[index]
                .key.name ==
            "comment"
        )
        {
            commentIndex =
                index;
            break;
        }
    }

    assert(commentIndex != size_t.max);

    auto edit =
        MetadataTreeEdit.forSource(
            source.metadata
        );

    edit.replaceSourceField(
        commentIndex,
        textField(
            "comment",
            "New"
        )
    );

    edit.appendNewField(
        trackField(12)
    );

    auto plan =
        planId3v1CanonicalTagWrite(
            source,
            edit
        );

    assert(plan.writable);
    assert(plan.revision == Id3v1Revision.v11);
    assert(plan.nativeFields.comment.length == 28);
    assert(plan.nativeFields.comment[0] == 'N');
    assert(plan.nativeFields.comment[3] == 0);
    assert(plan.nativeFields.track == 12);
}


/// Removing the only track downgrades v1.1 and expands comment with two zeroes.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[97] = 'C';
    bytes[124] = 'Z';
    bytes[125] = 0;
    bytes[126] = 9;

    auto source =
        parseTestTag(bytes);

    assert(source.native.revision == Id3v1Revision.v11);

    size_t trackIndex =
        size_t.max;

    foreach (
        index;
        0 .. source.metadata.length
    )
    {
        if (
            source.metadata[index]
                .key.name ==
            "track"
        )
        {
            trackIndex =
                index;
            break;
        }
    }

    assert(trackIndex != size_t.max);

    auto edit =
        MetadataTreeEdit.forSource(
            source.metadata
        );

    edit.removeSourceField(
        trackIndex
    );

    auto plan =
        planId3v1CanonicalTagWrite(
            source,
            edit
        );

    assert(plan.writable);
    assert(plan.revision == Id3v1Revision.v10);
    assert(plan.nativeFields.comment.length == 30);
    assert(plan.nativeFields.comment[0] == 'C');
    assert(plan.nativeFields.comment[27] == 'Z');
    assert(plan.nativeFields.comment[28] == 0);
    assert(plan.nativeFields.comment[29] == 0);
    assert(plan.nativeFields.track == 0);
}


/// Canonically repeatable comments still collide in the one physical ID3v1 slot.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);
    bytes[97] = 'A';

    auto source =
        parseTestTag(bytes);

    auto edit =
        MetadataTreeEdit.forSource(
            source.metadata
        );

    edit.appendNewField(
        textField(
            "comment",
            "B"
        )
    );

    auto plan =
        planId3v1CanonicalTagWrite(
            source,
            edit
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v1CanonicalTagWriteStatus
            .slotConflict
    );

    assert(
        plan.conflictTarget ==
        Id3v1CanonicalWriteTarget.comment
    );
}


/// Unsupported changed canonical shapes retain the underlying encoding error.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);
    bytes[3] = 'T';

    auto source =
        parseTestTag(bytes);

    auto edit =
        MetadataTreeEdit.forSource(
            source.metadata
        );

    MetadataValue invalidGenre =
        MetadataTextList(
            [
                "Free form genre"
            ]
        );

    edit.replaceSourceField(
        0,
        MetadataField(
            MetadataKey("genre"),
            invalidGenre
        )
    );

    auto plan =
        planId3v1CanonicalTagWrite(
            source,
            edit
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v1CanonicalTagWriteStatus
            .unrepresentableField
    );

    assert(!plan.newField);
    assert(plan.fieldIndex == 0);

    assert(
        plan.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
