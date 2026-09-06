/++
Format-independent editing overlay for a canonical metadata tree.

The canonical `MetadataTree` preserves source-derived insertion order
and exposes its fields read-only. Editing is therefore represented
separately rather than by mutating the parsed source tree in place.

One edit entry exists for every source canonical field and records
whether that field remains unchanged, is replaced, or is removed.

Canonical fields newly introduced by an editing layer are retained
separately in edit insertion order. Their eventual placement in a
target native metadata format belongs to format-specific write
planning.

This module performs no automatic equality comparison and no native
format mapping.
+/
module audiotag.metadata.edit;

import audiotag.metadata.field :
    MetadataField;

import audiotag.metadata.tree :
    MetadataTree;


/++
Edit state of one field originating in the source canonical tree.

`unchanged` is deliberately the default value so a freshly constructed
edit overlay begins as a no-op.
+/
enum MetadataSourceFieldEditState : ubyte
{
    unchanged,
    modified,
    removed
}


/++
Edit information for one source canonical field.

`replacement` is meaningful only when `state == modified`.
+/
struct MetadataSourceFieldEdit
{
    /// Current edit state of the source field.
    MetadataSourceFieldEditState state;

    /// Replacement canonical field when `state == modified`.
    MetadataField replacement;

    /++
    Returns whether this source field has a replacement value.
    +/
    @property
    bool hasReplacement() const
        @safe pure nothrow @nogc
    {
        return state ==
            MetadataSourceFieldEditState.modified;
    }

    /++
    Returns whether this source field contributes unchanged metadata.
    +/
    @property
    bool unchanged() const
        @safe pure nothrow @nogc
    {
        return state ==
            MetadataSourceFieldEditState.unchanged;
    }

    /++
    Returns whether this source field has been removed.
    +/
    @property
    bool removed() const
        @safe pure nothrow @nogc
    {
        return state ==
            MetadataSourceFieldEditState.removed;
    }
}



/++
Assigns one canonical field through the generated `MetadataField`
assignment operator.

`MetadataField` contains `std.sumtype.SumType`. With the currently
supported DMD/Phobos implementation, its generated assignment operator
is `@system` even though assigning these value types does not perform
unchecked memory access in this use.

Keep that compiler/library limitation isolated here rather than
weakening the public edit API.
+/
private void assignMetadataField(
    ref MetadataField target,
    MetadataField source
)
    @trusted
{
    target = source;
}


/++
Editing overlay associated with one canonical source tree.

Source fields are addressed by their original insertion-order index.
The overlay does not own or duplicate the source tree itself.

New fields are retained separately because deciding their final native
position is a target-format writer concern.
+/
struct MetadataTreeEdit
{
private:
    MetadataSourceFieldEdit[] _sourceEdits;
    MetadataField[] _newFields;

public:
    /++
    Constructs a no-op edit overlay for `source`.

    Every source field initially has state `unchanged`.
    +/
    static MetadataTreeEdit forSource(
        const(MetadataTree) source
    )
        @safe
    {
        auto result =
            MetadataTreeEdit.init;

        result._sourceEdits.length =
            source.length;

        return result;
    }

    /++
    Constructs a no-op edit overlay for a known source field count.

    This overload is useful to planning layers that already know the
    canonical source size without retaining a `MetadataTree` value.
    +/
    static MetadataTreeEdit forSourceFieldCount(
        size_t sourceFieldCount
    )
        @safe
    {
        auto result =
            MetadataTreeEdit.init;

        result._sourceEdits.length =
            sourceFieldCount;

        return result;
    }

    /// Number of fields in the original canonical source tree.
    @property
    size_t sourceFieldCount() const
        @safe pure nothrow @nogc
    {
        return _sourceEdits.length;
    }

    /// Number of newly introduced canonical fields.
    @property
    size_t newFieldCount() const
        @safe pure nothrow @nogc
    {
        return _newFields.length;
    }

    /// Source-field edits in original canonical insertion order.
    @property
    const(MetadataSourceFieldEdit)[] sourceEdits() const
        @safe pure nothrow @nogc
    {
        return _sourceEdits;
    }

    /// Newly introduced canonical fields in edit insertion order.
    @property
    const(MetadataField)[] newFields() const
        @safe pure nothrow @nogc
    {
        return _newFields;
    }

    /++
    Returns whether the overlay represents no canonical changes.
    +/
    @property
    bool unchanged() const
        @safe pure nothrow @nogc
    {
        if (_newFields.length != 0)
            return false;

        foreach (const edit; _sourceEdits)
        {
            if (
                edit.state !=
                MetadataSourceFieldEditState.unchanged
            )
            {
                return false;
            }
        }

        return true;
    }

    /++
    Returns the edit associated with one original source field.

    Preconditions:
        `sourceIndex < sourceFieldCount`.
    +/
    ref const(MetadataSourceFieldEdit)
    sourceEdit(size_t sourceIndex) const
        @safe pure nothrow @nogc
    {
        assert(
            sourceIndex <
            _sourceEdits.length
        );

        return _sourceEdits[sourceIndex];
    }

    /++
    Replaces one source canonical field.

    The original source field remains untouched; only the edit overlay
    receives the replacement.

    Preconditions:
        `sourceIndex < sourceFieldCount`.
    +/
    void replaceSourceField(
        size_t sourceIndex,
        MetadataField replacement
    )
        @safe
    {
        assert(
            sourceIndex <
            _sourceEdits.length
        );

        _sourceEdits[sourceIndex].state =
            MetadataSourceFieldEditState.modified;

        assignMetadataField(
            _sourceEdits[sourceIndex].replacement,
            replacement
        );
    }

    /++
    Marks one original canonical field as removed.

    Preconditions:
        `sourceIndex < sourceFieldCount`.
    +/
    void removeSourceField(
        size_t sourceIndex
    )
        @safe pure nothrow @nogc
    {
        assert(
            sourceIndex <
            _sourceEdits.length
        );

        _sourceEdits[sourceIndex].state =
            MetadataSourceFieldEditState.removed;
    }

    /++
    Restores one source field to the unchanged state.

    Any previously stored replacement becomes semantically irrelevant.

    Preconditions:
        `sourceIndex < sourceFieldCount`.
    +/
    void restoreSourceField(
        size_t sourceIndex
    )
        @safe pure nothrow @nogc
    {
        assert(
            sourceIndex <
            _sourceEdits.length
        );

        _sourceEdits[sourceIndex].state =
            MetadataSourceFieldEditState.unchanged;
    }

    /++
    Adds one new canonical field.

    New-field ordering is retained here, but native placement is
    deliberately deferred to target-format write planning.
    +/
    void appendNewField(
        MetadataField field
    )
        @safe
    {
        _newFields ~= field;
    }
}


version (unittest)
{
    import std.sumtype :
        match;

    import audiotag.metadata.field :
        MetadataKey;

    import audiotag.metadata.value :
        MetadataText,
        MetadataValue;


    private MetadataField textField(
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
}


/// A new edit overlay is a no-op over the complete source tree.
unittest
{
    auto source =
        MetadataTree.init;

    source.append(
        textField(
            "title",
            "Original title"
        )
    );

    source.append(
        textField(
            "artist",
            "Original artist"
        )
    );

    auto edit =
        MetadataTreeEdit.forSource(
            source
        );

    assert(edit.sourceFieldCount == 2);
    assert(edit.newFieldCount == 0);
    assert(edit.unchanged);

    assert(
        edit.sourceEdit(0).state ==
        MetadataSourceFieldEditState.unchanged
    );

    assert(
        edit.sourceEdit(1).state ==
        MetadataSourceFieldEditState.unchanged
    );
}


/// Replacing a source field records its explicit replacement.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(2);

    edit.replaceSourceField(
        1,
        textField(
            "artist",
            "Replacement artist"
        )
    );

    assert(!edit.unchanged);

    assert(
        edit.sourceEdit(0).unchanged
    );

    assert(
        edit.sourceEdit(1).state ==
        MetadataSourceFieldEditState.modified
    );

    assert(
        edit.sourceEdit(1).hasReplacement
    );

    assert(
        edit.sourceEdit(1)
            .replacement.key.name ==
        "artist"
    );

    assert(
        edit.sourceEdit(1)
            .replacement
            .value
            .match!(
                (MetadataText text) =>
                    text.value ==
                        "Replacement artist",

                _ => false
            )
    );
}


/// Removing a source field is distinct from replacing it.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(3);

    edit.removeSourceField(1);

    assert(!edit.unchanged);

    assert(
        edit.sourceEdit(1).removed
    );

    assert(
        !edit.sourceEdit(1)
            .hasReplacement
    );
}


/// A source field can be restored to its original unchanged state.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(1);

    edit.replaceSourceField(
        0,
        textField(
            "title",
            "Temporary title"
        )
    );

    assert(!edit.unchanged);

    edit.restoreSourceField(0);

    assert(edit.unchanged);
    assert(edit.sourceEdit(0).unchanged);
    assert(!edit.sourceEdit(0).hasReplacement);
}


/// Newly introduced fields retain their edit insertion order.
unittest
{
    auto edit =
        MetadataTreeEdit
            .forSourceFieldCount(1);

    edit.appendNewField(
        textField(
            "comment",
            "First"
        )
    );

    edit.appendNewField(
        textField(
            "comment",
            "Second"
        )
    );

    assert(!edit.unchanged);
    assert(edit.newFieldCount == 2);

    assert(
        edit.newFields[0].key.name ==
        "comment"
    );

    assert(
        edit.newFields[1].key.name ==
        "comment"
    );

    assert(
        edit.newFields[0]
            .value
            .match!(
                (MetadataText text) =>
                    text.value == "First",

                _ => false
            )
    );

    assert(
        edit.newFields[1]
            .value
            .match!(
                (MetadataText text) =>
                    text.value == "Second",

                _ => false
            )
    );
}
