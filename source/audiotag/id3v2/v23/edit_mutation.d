/++
Derives ID3v2.3 native-frame mutation state from the format-independent
canonical metadata edit overlay.

The revision-independent mutation algorithm lives in
`audiotag.id3v2.common.edit_mutation`. This module retains the explicit
ID3v2.3 API and revision-specific types.

This module performs no serialization.
+/
module audiotag.id3v2.v23.edit_mutation;

import audiotag.metadata.edit :
    MetadataTreeEdit;

import audiotag.id3v2.common.edit_mutation :
    deriveId3v2CanonicalFrameMutation,
    deriveId3v2CanonicalFrameMutations;

import audiotag.id3v2.v23.canonical_projection :
    Id3v23CanonicalFrameRecord;

import audiotag.id3v2.v23.frame_write_plan :
    Id3v23CanonicalFrameMutation;


/++
Derives the mutation state of one provenance-preserved native frame.

The canonical range stored in the frame record must refer to the source
fields represented by `edit`.

Params:
    record = Native-frame projection record.
    edit = Canonical edit overlay for the corresponding source tree.

Returns:
    Mutation state suitable for ID3v2.3 frame write planning.
+/
Id3v23CanonicalFrameMutation
deriveId3v23CanonicalFrameMutation(
    const(Id3v23CanonicalFrameRecord) record,
    const(MetadataTreeEdit) edit
)
    @safe pure nothrow @nogc
{
    return
        deriveId3v2CanonicalFrameMutation!(
            Id3v23CanonicalFrameMutation
        )(
            record,
            edit
        );
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
Id3v23CanonicalFrameMutation[]
deriveId3v23CanonicalFrameMutations(
    const(Id3v23CanonicalFrameRecord)[] records,
    const(MetadataTreeEdit) edit
)
    @safe
{
    return
        deriveId3v2CanonicalFrameMutations!(
            Id3v23CanonicalFrameMutation
        )(
            records,
            edit
        );
}


version (unittest)
{
    import audiotag.metadata.field :
        MetadataField;

    import audiotag.id3v2.v23.canonical_mapping :
        Id3v23CanonicalMappingStatus;


    private Id3v23CanonicalFrameRecord testRecord(
        size_t canonicalStart,
        size_t canonicalCount,
        Id3v23CanonicalMappingStatus status =
            Id3v23CanonicalMappingStatus.mapped
    )
        @safe pure nothrow @nogc
    {
        auto result =
            Id3v23CanonicalFrameRecord.init;

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
            Id3v23CanonicalMappingStatus
                .unsupportedFrame
        );

    assert(
        deriveId3v23CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v23CanonicalFrameMutation
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
        deriveId3v23CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v23CanonicalFrameMutation
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
        deriveId3v23CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v23CanonicalFrameMutation
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
        deriveId3v23CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v23CanonicalFrameMutation
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
        deriveId3v23CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v23CanonicalFrameMutation
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
        deriveId3v23CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v23CanonicalFrameMutation
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
        deriveId3v23CanonicalFrameMutation(
            record,
            edit
        ) ==
        Id3v23CanonicalFrameMutation
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
                Id3v23CanonicalMappingStatus
                    .unsupportedFrame
            )
        ];

    const mutations =
        deriveId3v23CanonicalFrameMutations(
            records,
            edit
        );

    assert(mutations.length == 4);

    assert(
        mutations[0] ==
        Id3v23CanonicalFrameMutation
            .unchanged
    );

    assert(
        mutations[1] ==
        Id3v23CanonicalFrameMutation
            .modified
    );

    assert(
        mutations[2] ==
        Id3v23CanonicalFrameMutation
            .removed
    );

    assert(
        mutations[3] ==
        Id3v23CanonicalFrameMutation
            .unchanged
    );
}
