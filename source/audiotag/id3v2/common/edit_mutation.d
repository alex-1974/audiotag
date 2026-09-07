/++
Format-independent derivation of native-frame mutation state from a
canonical metadata edit overlay.

ID3v2 revisions retain their own native frame-record and mutation types.
This module contains only the algorithm shared by those revisions.

The record type is required to expose:

- `canonicalStart`
- `canonicalCount`

The mutation type is required to expose:

- `unchanged`
- `modified`
- `removed`

No serialization or native-frame interpretation occurs here.
+/
module audiotag.id3v2.common.edit_mutation;

import audiotag.metadata.edit :
    MetadataSourceFieldEditState,
    MetadataTreeEdit;


/++
Derives the mutation state of one provenance-preserved native frame.

Params:
    Mutation = Revision-specific native-frame mutation enum.
    record = Revision-specific projection record.
    edit = Canonical edit overlay for the corresponding source tree.

Returns:
    Revision-specific mutation state.
+/
Mutation
deriveId3v2CanonicalFrameMutation(
    Mutation,
    Record
)(
    const(Record) record,
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
            Mutation.unchanged;
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
            Mutation.unchanged;
    }

    if (
        !anyUnchanged &&
        !anyModified &&
        anyRemoved
    )
    {
        return
            Mutation.removed;
    }

    return
        Mutation.modified;
}


/++
Derives mutation states for all existing native frame records.

The returned array preserves native frame order exactly.

Params:
    Mutation = Revision-specific native-frame mutation enum.
    records = Existing native frame records in source order.
    edit = Canonical edit overlay corresponding to their projection.

Returns:
    One revision-specific mutation state per native frame record.
+/
Mutation[]
deriveId3v2CanonicalFrameMutations(
    Mutation,
    Record
)(
    const(Record)[] records,
    const(MetadataTreeEdit) edit
)
    @safe
{
    auto result =
        new Mutation[
            records.length
        ];

    foreach (index, const record; records)
    {
        result[index] =
            deriveId3v2CanonicalFrameMutation!(
                Mutation
            )(
                record,
                edit
            );
    }

    return result;
}
