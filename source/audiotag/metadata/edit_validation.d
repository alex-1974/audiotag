/++
Validation of the canonical tree resulting from a metadata edit overlay.

`MetadataTree` deliberately preserves repeated fields without enforcing
registry multiplicity. Editing can therefore produce a semantically
invalid result even when every individual field is well formed.

This module validates registry multiplicity across the effective result:

- unchanged source fields remain present;
- modified source fields contribute their replacement field;
- removed source fields contribute nothing;
- newly appended fields contribute in edit insertion order.

Unknown canonical keys remain valid here because the canonical registry
is intentionally extensible. Target metadata codecs may later reject
keys they cannot represent.

This module does not materialize a new `MetadataTree`.
+/
module audiotag.metadata.edit_validation;

import audiotag.metadata.edit :
    MetadataSourceFieldEditState,
    MetadataTreeEdit;

import audiotag.metadata.field :
    MetadataKey;

import audiotag.metadata.registry :
    metadataFieldDefinitions;

import audiotag.metadata.tree :
    MetadataTree;


/++
Outcome of canonical edit multiplicity validation.
+/
enum MetadataTreeEditMultiplicityStatus : ubyte
{
    valid,
    multiplicityExceeded
}


/++
Result of validating registry multiplicity for an edited canonical tree.
+/
struct MetadataTreeEditMultiplicityResult
{
    /// Validation outcome.
    MetadataTreeEditMultiplicityStatus status;

    /// Canonical key causing a multiplicity violation.
    MetadataKey key;

    /// Effective number of occurrences when validation failed.
    size_t count;

    /++
    Returns whether registry multiplicity remains valid.
    +/
    @property
    bool valid() const
        @safe pure nothrow @nogc
    {
        return status ==
            MetadataTreeEditMultiplicityStatus.valid;
    }

    /++
    Constructs a successful validation result.
    +/
    static MetadataTreeEditMultiplicityResult success()
        @safe pure nothrow @nogc
    {
        return
            MetadataTreeEditMultiplicityResult(
                MetadataTreeEditMultiplicityStatus.valid,
                MetadataKey.init,
                0
            );
    }

    /++
    Constructs a multiplicity violation.
    +/
    static MetadataTreeEditMultiplicityResult exceeded(
        string key,
        size_t count
    )
        @safe pure nothrow @nogc
    {
        return
            MetadataTreeEditMultiplicityResult(
                MetadataTreeEditMultiplicityStatus
                    .multiplicityExceeded,
                MetadataKey(key),
                count
            );
    }
}


/++
Accounts one effective canonical field against registry multiplicity.

Unknown keys are intentionally ignored because the format-independent
canonical model permits extension semantics not yet present in the
registry.
+/
private MetadataTreeEditMultiplicityResult
accountCanonicalKey(
    string key,
    ref size_t[] counts
)
    @safe
{
    const definitions =
        metadataFieldDefinitions();

    foreach (index, const definition; definitions)
    {
        if (
            definition.key.name !=
            key
        )
        {
            continue;
        }

        ++counts[index];

        if (
            !definition.repeated &&
            counts[index] > 1
        )
        {
            return
                MetadataTreeEditMultiplicityResult
                    .exceeded(
                        key,
                        counts[index]
                    );
        }

        break;
    }

    return
        MetadataTreeEditMultiplicityResult
            .success();
}


/++
Validates canonical registry multiplicity after applying an edit overlay.

The edit overlay must correspond to `source`. A source-field-count
mismatch is a caller/programmer error rather than malformed external
metadata.

Unknown canonical keys remain permitted by this format-independent
validation.

Preconditions:
    `edit.sourceFieldCount == source.length`.

Params:
    source = Original canonical metadata tree.
    edit = Editing overlay associated with `source`.

Returns:
    First registry multiplicity violation in effective result order, or
    a successful result.
+/
MetadataTreeEditMultiplicityResult
validateMetadataTreeEditMultiplicity(
    const(MetadataTree) source,
    const(MetadataTreeEdit) edit
)
    @safe
{
    assert(
        edit.sourceFieldCount ==
        source.length
    );

    const definitions =
        metadataFieldDefinitions();

    auto counts =
        new size_t[
            definitions.length
        ];

    foreach (
        sourceIndex;
        0 .. source.length
    )
    {
        const sourceEdit =
            edit.sourceEdit(
                sourceIndex
            );

        string effectiveKey;

        final switch (sourceEdit.state)
        {
            case MetadataSourceFieldEditState.unchanged:
                effectiveKey =
                    source[sourceIndex]
                        .key.name;
                break;

            case MetadataSourceFieldEditState.modified:
                effectiveKey =
                    sourceEdit
                        .replacement
                        .key.name;
                break;

            case MetadataSourceFieldEditState.removed:
                continue;
        }

        const result =
            accountCanonicalKey(
                effectiveKey,
                counts
            );

        if (!result.valid)
            return result;
    }

    foreach (const field; edit.newFields)
    {
        const result =
            accountCanonicalKey(
                field.key.name,
                counts
            );

        if (!result.valid)
            return result;
    }

    return
        MetadataTreeEditMultiplicityResult
            .success();
}


version (unittest)
{
    import audiotag.metadata.field :
        MetadataField;

    import audiotag.metadata.value :
        MetadataText,
        MetadataUrl,
        MetadataValue;


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
}


/// A no-op edit retains valid single canonical fields.
unittest
{
    auto source =
        MetadataTree.init;

    source.append(
        textField(
            "title",
            "Title"
        )
    );

    source.append(
        textField(
            "album",
            "Album"
        )
    );

    const edit =
        MetadataTreeEdit.forSource(
            source
        );

    const result =
        validateMetadataTreeEditMultiplicity(
            source,
            edit
        );

    assert(result.valid);
}


/// Adding a second single-valued canonical title is rejected.
unittest
{
    auto source =
        MetadataTree.init;

    source.append(
        textField(
            "title",
            "Original"
        )
    );

    auto edit =
        MetadataTreeEdit.forSource(
            source
        );

    edit.appendNewField(
        textField(
            "title",
            "Second"
        )
    );

    const result =
        validateMetadataTreeEditMultiplicity(
            source,
            edit
        );

    assert(!result.valid);

    assert(
        result.status ==
        MetadataTreeEditMultiplicityStatus
            .multiplicityExceeded
    );

    assert(result.key.name == "title");
    assert(result.count == 2);
}


/// Replacement keys participate in resulting-tree multiplicity.
unittest
{
    auto source =
        MetadataTree.init;

    source.append(
        textField(
            "album",
            "Existing album"
        )
    );

    source.append(
        textField(
            "title",
            "Original title"
        )
    );

    auto edit =
        MetadataTreeEdit.forSource(
            source
        );

    edit.replaceSourceField(
        1,
        textField(
            "album",
            "Replacement album"
        )
    );

    const result =
        validateMetadataTreeEditMultiplicity(
            source,
            edit
        );

    assert(!result.valid);
    assert(result.key.name == "album");
    assert(result.count == 2);
}


/// Removing a single field before adding its replacement remains valid.
unittest
{
    auto source =
        MetadataTree.init;

    source.append(
        textField(
            "title",
            "Original"
        )
    );

    auto edit =
        MetadataTreeEdit.forSource(
            source
        );

    edit.removeSourceField(0);

    edit.appendNewField(
        textField(
            "title",
            "Replacement"
        )
    );

    const result =
        validateMetadataTreeEditMultiplicity(
            source,
            edit
        );

    assert(result.valid);
}


/// Repeated canonical fields remain freely repeatable.
unittest
{
    auto source =
        MetadataTree.init;

    source.append(
        textField(
            "comment",
            "One"
        )
    );

    source.append(
        textField(
            "comment",
            "Two"
        )
    );

    auto edit =
        MetadataTreeEdit.forSource(
            source
        );

    edit.appendNewField(
        textField(
            "comment",
            "Three"
        )
    );

    const result =
        validateMetadataTreeEditMultiplicity(
            source,
            edit
        );

    assert(result.valid);
}


/// Repeatable standard URL semantics remain valid across source and edits.
unittest
{
    foreach (
        key;
        [
            "commercialUrl",
            "artistUrl"
        ]
    )
    {
        auto source =
            MetadataTree.init;

        source.append(
            urlField(
                key,
                "https://example.invalid/one"
            )
        );

        auto edit =
            MetadataTreeEdit.forSource(
                source
            );

        edit.appendNewField(
            urlField(
                key,
                "https://example.invalid/two"
            )
        );

        const result =
            validateMetadataTreeEditMultiplicity(
                source,
                edit
            );

        assert(result.valid);
    }
}


/// Unknown extension keys remain outside registry multiplicity policy.
unittest
{
    auto source =
        MetadataTree.init;

    source.append(
        textField(
            "futureSemantic",
            "One"
        )
    );

    auto edit =
        MetadataTreeEdit.forSource(
            source
        );

    edit.appendNewField(
        textField(
            "futureSemantic",
            "Two"
        )
    );

    const result =
        validateMetadataTreeEditMultiplicity(
            source,
            edit
        );

    assert(result.valid);
}
