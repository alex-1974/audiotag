/++
Format-independent canonical metadata fields.

A canonical field combines:

- one canonical semantic key;
- one typed canonical value;
- zero or more native provenance records;
- optional language and description context;
- optional ordered qualifiers.

Native metadata identifiers remain in `MetadataProvenance`; they are
deliberately not reused as canonical keys.
+/
module audiotag.metadata.field;

import audiotag.metadata.provenance :
    MetadataProvenance;

import audiotag.metadata.value :
    MetadataValue,
    MetadataText;


/++
Stable semantic identifier of a canonical metadata field.

Examples may later include identifiers such as:

- `title`
- `artist`
- `album`
- `comment`
- `lyrics`
- `artwork`

This type does not currently impose a registry or naming syntax.
Those rules belong to the later canonical field registry.
+/
struct MetadataKey
{
    /// Canonical semantic identifier.
    string name;

    /++
    Returns whether this key has a non-empty identifier.
    +/
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return name.length == 0;
    }
}


/++
Optional language context associated with a canonical field.

The representation intentionally does not yet require one specific
language-tag standard. Native mappings may initially supply ISO-639
codes or other normalized language identifiers; registry/mapping
policy will define normalization later.
+/
struct MetadataLanguage
{
    /// Language identifier/tag, or an empty string when unspecified.
    string tag;

    /++
    Returns whether no language was specified.
    +/
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return tag.length == 0;
    }
}


/++
Additional named context attached to a canonical field.

Qualifiers are intentionally separate from the main semantic key.
They may later express dimensions that are meaningful but do not
justify creating unrelated canonical keys.

Their interpretation belongs to the canonical registry/mapping layer.
+/
struct MetadataQualifier
{
    /// Qualifier name.
    string name;

    /// Qualifier value.
    string value;
}


/++
One canonical metadata field.

A field carries one semantic key and one typed value. Repetition and
ordering of multiple fields belong to the later `MetadataTree`.

`provenance` may contain more than one origin when several native
fields were intentionally combined into one canonical value.

An empty language or description means that context is unspecified,
not that the native format necessarily contained an explicit empty
field.
+/
struct MetadataField
{
    /// Canonical semantic key.
    MetadataKey key;

    /// Typed canonical value.
    MetadataValue value;

    /// Native origins contributing to this value.
    MetadataProvenance[] provenance;

    /// Optional language context.
    MetadataLanguage language;

    /// Optional human-readable description/qualifier text.
    string description;

    /// Additional ordered contextual qualifiers.
    MetadataQualifier[] qualifiers;

    /++
    Returns whether at least one native provenance record exists.
    +/
    @property
    bool hasProvenance() const
        @safe pure nothrow @nogc
    {
        return provenance.length != 0;
    }

    /++
    Returns whether language context is present.
    +/
    @property
    bool hasLanguage() const
        @safe pure nothrow @nogc
    {
        return !language.empty;
    }

    /++
    Returns whether a description is present.
    +/
    @property
    bool hasDescription() const
        @safe pure nothrow @nogc
    {
        return description.length != 0;
    }

    /++
    Returns whether additional qualifiers are present.
    +/
    @property
    bool hasQualifiers() const
        @safe pure nothrow @nogc
    {
        return qualifiers.length != 0;
    }
}


import audiotag.metadata.provenance :
    MetadataConfidence,
    MetadataSystem,
    NativeMetadataIdentifier;


/// Canonical keys remain separate from native identifiers.
unittest
{
    MetadataValue value =
        MetadataText("Example title");

    auto field =
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
                    24
                )
            ]
        );

    assert(field.key.name == "title");
    assert(!field.key.empty);

    assert(field.hasProvenance);
    assert(field.provenance.length == 1);

    assert(
        field.provenance[0].native.identifier ==
        "TIT2"
    );

    assert(
        field.provenance[0].native.identifier !=
        field.key.name
    );

    assert(!field.hasLanguage);
    assert(!field.hasDescription);
    assert(!field.hasQualifiers);
}


/// Language and description are optional field context.
unittest
{
    MetadataValue value =
        MetadataText("A comment");

    auto field =
        MetadataField(
            MetadataKey("comment"),
            value,
            [],
            MetadataLanguage("eng"),
            "short description"
        );

    assert(field.hasLanguage);
    assert(field.language.tag == "eng");

    assert(field.hasDescription);
    assert(field.description == "short description");

    assert(!field.hasProvenance);
}


/// Multiple native origins may contribute to one canonical field.
unittest
{
    MetadataValue value =
        MetadataText("Combined artist");

    auto field =
        MetadataField(
            MetadataKey("artist"),
            value,
            [
                MetadataProvenance(
                    NativeMetadataIdentifier(
                        MetadataSystem.id3v2,
                        "TPE1"
                    ),
                    200,
                    10,
                    MetadataConfidence.exact
                ),
                MetadataProvenance(
                    NativeMetadataIdentifier(
                        MetadataSystem.vorbisComment,
                        "ARTIST"
                    ),
                    500,
                    16,
                    MetadataConfidence.exact
                )
            ]
        );

    assert(field.provenance.length == 2);

    assert(
        field.provenance[0].native.system ==
        MetadataSystem.id3v2
    );

    assert(
        field.provenance[1].native.system ==
        MetadataSystem.vorbisComment
    );
}


/// Qualifiers preserve their explicit ordering.
unittest
{
    MetadataValue value =
        MetadataText("Example");

    auto field =
        MetadataField(
            MetadataKey("custom"),
            value,
            [],
            MetadataLanguage.init,
            "",
            [
                MetadataQualifier("role", "composer"),
                MetadataQualifier("scope", "movement")
            ]
        );

    assert(field.hasQualifiers);
    assert(field.qualifiers.length == 2);

    assert(field.qualifiers[0].name == "role");
    assert(field.qualifiers[0].value == "composer");

    assert(field.qualifiers[1].name == "scope");
    assert(field.qualifiers[1].value == "movement");
}


/// Empty canonical keys remain representable but detectable.
unittest
{
    const key =
        MetadataKey("");

    assert(key.empty);
}
