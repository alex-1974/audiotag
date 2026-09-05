/++
Ordered canonical metadata tree.

The initial canonical tree is deliberately flat: it preserves field
order and permits repeated semantic keys.

More complex nesting and scoped structures may be added later without
changing the fundamental rule that canonical fields remain ordered
and may occur more than once.
+/
module audiotag.metadata.tree;

import audiotag.metadata.field :
    MetadataField,
    MetadataKey;


/++
Result of looking up one field position in a `MetadataTree`.

An explicit result avoids sentinel indices such as `size_t.max`.
+/
struct MetadataFieldLookup
{
    /// Whether a matching field was found.
    bool found;

    /// Matching field index when `found` is true.
    size_t index;

    /++
    Constructs a successful lookup.
    +/
    static MetadataFieldLookup success(size_t index)
        @safe pure nothrow @nogc
    {
        return MetadataFieldLookup(
            true,
            index
        );
    }

    /++
    Constructs a lookup with no matching field.
    +/
    static MetadataFieldLookup notFound()
        @safe pure nothrow @nogc
    {
        return MetadataFieldLookup(
            false,
            0
        );
    }
}


/++
Ordered collection of canonical metadata fields.

The tree preserves insertion order and allows repeated keys.
Appending does not merge, replace or otherwise normalize fields.

This behavior is intentional:

- repeated native metadata may remain repeated;
- source ordering can remain observable;
- later registry/mapping policy can decide whether particular
  semantic fields should be combined.
+/
struct MetadataTree
{
    private MetadataField[] _fields;

    /++
    Returns the number of canonical fields.
    +/
    @property
    size_t length() const
        @safe pure nothrow @nogc
    {
        return _fields.length;
    }

    /++
    Returns whether the tree contains no fields.
    +/
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return _fields.length == 0;
    }

    /++
    Returns all fields in canonical insertion order.

    The returned slice is read-only through this API.
    +/
    @property
    const(MetadataField)[] fields() const
        @safe pure nothrow @nogc
    {
        return _fields;
    }

    /++
    Appends one canonical field.

    Repeated keys are preserved and no normalization is performed.
    +/
    void append(MetadataField field)
        @safe
    {
        _fields ~= field;
    }

    /++
    Returns the field at `index`.

    Preconditions:
        `index` must be less than `length`.

    Indexing errors are programmer errors. Metadata originating from
    untrusted input must already have been validated before entering
    the canonical tree.
    +/
    ref const(MetadataField) opIndex(size_t index) const
        @safe pure nothrow @nogc
    {
        assert(index < _fields.length);

        return _fields[index];
    }

    /++
    Counts fields having the given canonical key.

    Native metadata identifiers and provenance do not participate in
    this lookup.
    +/
    size_t count(MetadataKey key) const
        @safe
    {
        size_t result;

        foreach (field; _fields)
        {
            if (field.key.name == key.name)
                ++result;
        }

        return result;
    }

    /++
    Finds the first field having the given canonical key.

    Returns:
        An explicit lookup containing the insertion-order index, or a
        not-found result.
    +/
    MetadataFieldLookup firstIndex(MetadataKey key) const
        @safe
    {
        foreach (index, field; _fields)
        {
            if (field.key.name == key.name)
            {
                return MetadataFieldLookup.success(
                    index
                );
            }
        }

        return MetadataFieldLookup.notFound();
    }
}


import audiotag.metadata.provenance :
    MetadataProvenance,
    MetadataSystem,
    NativeMetadataIdentifier;

import audiotag.metadata.value :
    MetadataText,
    MetadataValue;


/// A newly constructed metadata tree is empty.
unittest
{
    const tree =
        MetadataTree.init;

    assert(tree.empty);
    assert(tree.length == 0);
    assert(tree.fields.length == 0);
}


/// Appending fields preserves insertion order.
unittest
{
    auto tree =
        MetadataTree.init;

    MetadataValue title =
        MetadataText("Title");

    MetadataValue artist =
        MetadataText("Artist");

    tree.append(
        MetadataField(
            MetadataKey("title"),
            title
        )
    );

    tree.append(
        MetadataField(
            MetadataKey("artist"),
            artist
        )
    );

    assert(!tree.empty);
    assert(tree.length == 2);

    assert(tree[0].key.name == "title");
    assert(tree[1].key.name == "artist");

    assert(tree.fields[0].key.name == "title");
    assert(tree.fields[1].key.name == "artist");
}


/// Repeated canonical keys remain separate ordered fields.
unittest
{
    auto tree =
        MetadataTree.init;

    MetadataValue firstArtist =
        MetadataText("First artist");

    MetadataValue secondArtist =
        MetadataText("Second artist");

    tree.append(
        MetadataField(
            MetadataKey("artist"),
            firstArtist
        )
    );

    tree.append(
        MetadataField(
            MetadataKey("title"),
            MetadataValue(
                MetadataText("Track")
            )
        )
    );

    tree.append(
        MetadataField(
            MetadataKey("artist"),
            secondArtist
        )
    );

    assert(tree.length == 3);

    assert(
        tree.count(
            MetadataKey("artist")
        ) == 2
    );

    assert(tree[0].key.name == "artist");
    assert(tree[1].key.name == "title");
    assert(tree[2].key.name == "artist");
}


/// First-key lookup returns the insertion-order position.
unittest
{
    auto tree =
        MetadataTree.init;

    tree.append(
        MetadataField(
            MetadataKey("comment"),
            MetadataValue(
                MetadataText("first")
            )
        )
    );

    tree.append(
        MetadataField(
            MetadataKey("comment"),
            MetadataValue(
                MetadataText("second")
            )
        )
    );

    auto result =
        tree.firstIndex(
            MetadataKey("comment")
        );

    assert(result.found);
    assert(result.index == 0);
}


/// Missing-key lookup is explicit and does not use a sentinel index.
unittest
{
    auto tree =
        MetadataTree.init;

    tree.append(
        MetadataField(
            MetadataKey("title"),
            MetadataValue(
                MetadataText("Track")
            )
        )
    );

    auto result =
        tree.firstIndex(
            MetadataKey("artist")
        );

    assert(!result.found);
}


/// Canonical lookup depends on the canonical key, not native provenance.
unittest
{
    auto tree =
        MetadataTree.init;

    MetadataValue value =
        MetadataText("Track");

    tree.append(
        MetadataField(
            MetadataKey("title"),
            value,
            [
                MetadataProvenance(
                    NativeMetadataIdentifier(
                        MetadataSystem.id3v2,
                        "TIT2"
                    ),
                    100,
                    20
                )
            ]
        )
    );

    assert(
        tree.count(
            MetadataKey("title")
        ) == 1
    );

    assert(
        tree.count(
            MetadataKey("TIT2")
        ) == 0
    );
}
