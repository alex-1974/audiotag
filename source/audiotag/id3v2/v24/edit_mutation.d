/++
Derives ID3v2.4 native-frame mutation state from the format-independent
canonical metadata edit overlay.

A native frame may contribute zero, one or eventually multiple canonical
fields. `canonicalStart` and `canonicalCount` in the provenance
projection identify that source range.

Rules:

- no associated canonical fields -> unchanged;
- all associated source fields unchanged -> unchanged;
- all associated source fields removed -> removed;
- every other changed combination -> modified.

The final rule deliberately includes partial removal, replacement of one
field in a multi-field mapping, and combinations of replacement and
removal. Such a native frame must eventually be regenerated from the
resulting canonical state rather than partially patched.

This module performs no serialization.
+/
module audiotag.id3v2.v24.edit_mutation;

import audiotag.metadata.edit :
    MetadataSourceFieldEditState,
    MetadataTreeEdit;

import audiotag.id3v2.v24.canonical_projection :
    Id3v24CanonicalFrameRecord;

import audiotag.id3v2.v24.frame_write_plan :
    Id3v24CanonicalFrameMutation;


/++
Derives the mutation state of one provenance-preserved native frame.

The canonical range stored in the frame record must refer to the source
fields represented by `edit`.

Preconditions:
    `record.canonicalStart <= edit.sourceFieldCount`.
    `record.canonicalCount <=
        edit.sourceFieldCount - record.canonicalStart`.

Params:
    record = Native-frame projection record.
    edit = Canonical edit overlay for the corresponding source tree.

Returns:
    Mutation state suitable for ID3v2.4 frame write planning.
+/
Id3v24CanonicalFrameMutation
deriveId3v24CanonicalFrameMutation(
    const(Id3v24CanonicalFrameRecord) record,
    const(MetadataTreeEdit) edit
)
    @safe pure nothrow @nogc
{
    assert(
        record.canonicalStart <=
        edit.sourceFieldCount
    );

    assert(
        record.canonicalCount <=
        edit.sourceFieldCount -
            record.canonicalStart
    );

    if (record.canonicalCount == 0)
    {
        return
            Id3v24CanonicalFrameMutation
                .unchanged;
    }

    bool anyUnchanged;
    bool anyModified;
    bool anyRemoved;

    foreach (
        offset;
        0 .. record.canonicalCount
    )
    {
        const sourceIndex =
            record.canonicalStart +
            offset;

        final switch (
            edit.sourceEdit(sourceIndex).state
        )
        {
            case MetadataSourceFieldEditState.unchanged:
                anyUnchanged = true;
                break;

            case MetadataSourceFieldEditState.modified:
                anyModified = true;
                break;

            case MetadataSourceFieldEditState.removed:
                anyRemoved = true;
                break;
        }
    }

    if (
        anyUnchanged &&
        !anyModified &&
        !anyRemoved
    )
    {
        return
            Id3v24CanonicalFrameMutation
                .unchanged;
    }

    if (
        !anyUnchanged &&
        !anyModified &&
        anyRemoved
    )
    {
        return
            Id3v24CanonicalFrameMutation
                .removed;
    }

    return
        Id3v24CanonicalFrameMutation
            .modified;
}


/++
Derives mutation states for all existing native frame records.

The returned array preserves native frame order exactly.

New canonical fields are intentionally absent from this result because
they have no source native frame. Their target-frame planning is a
separate writer step.

Params:
    records = Existing native frame records in source order.
    edit = Canonical edit overlay corresponding to their projection.

Returns:
    One mutation state per native frame record.
+/
Id3v24CanonicalFrameMutation[]
deriveId3v24CanonicalFrameMutations(
    const(Id3v24CanonicalFrameRecord)[] records,
    const(MetadataTreeEdit) edit
)
    @safe
{
    auto result =
        new Id3v24CanonicalFrameMutation[
            records.length
        ];

    foreach (index, const record; records)
    {
        result[index] =
            deriveId3v24CanonicalFrameMutation(
                record,
                edit
            );
    }

    return result;
}


version (unittest)
{
    import audiotag.metadata.field :
        MetadataField;

    import audiotag.id3v2.v24.canonical_mapping :
        Id3v24CanonicalMappingStatus;


    private Id3v24CanonicalFrameRecord testRecord(
        size_t canonicalStart,
        size_t canonicalCount,
        Id3v24CanonicalMappingStatus status =
            Id3v24CanonicalMappingStatus.mapped
    )
        @safe pure nothrow @nogc
    {
        auto result =
            Id3v24CanonicalFrameRecord.init;

        result.status =
            status;

        result.canonicalStart =
            canonicalStart;

        result.canonicalCount =
            canonicalCount;

        return result;
    }


    private void markModified(
        ref MetadataTreeEdit edit,
        size_t index
    )
        @safe
    {
        edit.replaceSourceField(
            index,
            MetadataField.init
        );
    }
}


/// A frame without canonical output remains unchanged.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(2);

    const record =
        testRecord(
            1,
            0,
            Id3v24CanonicalMappingStatus
                .unsupportedFrame
        );

    assert(
        deriveId3v24CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v24CanonicalFrameMutation
            .unchanged
    );
}


/// One unchanged canonical assertion preserves its native frame.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(1);

    const record =
        testRecord(0, 1);

    assert(
        deriveId3v24CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v24CanonicalFrameMutation
            .unchanged
    );
}


/// Replacing the canonical assertion marks the frame modified.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(1);

    markModified(edit, 0);

    const record =
        testRecord(0, 1);

    assert(
        deriveId3v24CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v24CanonicalFrameMutation
            .modified
    );
}


/// Removing the complete canonical contribution removes the native frame.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(1);

    edit.removeSourceField(0);

    const record =
        testRecord(0, 1);

    assert(
        deriveId3v24CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v24CanonicalFrameMutation
            .removed
    );
}


/// Removing every field of a future one-to-many mapping removes the frame.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(3);

    edit.removeSourceField(0);
    edit.removeSourceField(1);
    edit.removeSourceField(2);

    const record =
        testRecord(0, 3);

    assert(
        deriveId3v24CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v24CanonicalFrameMutation
            .removed
    );
}


/// Partial removal of a multi-field mapping requires regeneration.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(3);

    edit.removeSourceField(1);

    const record =
        testRecord(0, 3);

    assert(
        deriveId3v24CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v24CanonicalFrameMutation
            .modified
    );
}


/// Mixed replacement and removal likewise requires regeneration.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(3);

    markModified(edit, 0);
    edit.removeSourceField(1);

    const record =
        testRecord(0, 3);

    assert(
        deriveId3v24CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v24CanonicalFrameMutation
            .modified
    );
}


/// Batch derivation preserves native frame order.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(3);

    markModified(edit, 1);
    edit.removeSourceField(2);

    const records =
        [
            testRecord(0, 1),
            testRecord(1, 1),
            testRecord(2, 1),
            testRecord(
                3,
                0,
                Id3v24CanonicalMappingStatus
                    .unsupportedFrame
            )
        ];

    const mutations =
        deriveId3v24CanonicalFrameMutations(
            records,
            edit
        );

    assert(mutations.length == 4);

    assert(
        mutations[0] ==
        Id3v24CanonicalFrameMutation
            .unchanged
    );

    assert(
        mutations[1] ==
        Id3v24CanonicalFrameMutation
            .modified
    );

    assert(
        mutations[2] ==
        Id3v24CanonicalFrameMutation
            .removed
    );

    assert(
        mutations[3] ==
        Id3v24CanonicalFrameMutation
            .unchanged
    );
}
