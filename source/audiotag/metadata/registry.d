/++
Canonical metadata field registry.

The registry defines stable semantic keys independently of any native
metadata system. Native-to-canonical mappings such as `TIT2 -> title`
belong to separate codec/mapping modules.

This initial registry deliberately contains only semantics for which
the canonical value model is already sufficiently defined.
+/
module audiotag.metadata.registry;

import std.sumtype :
    match;

import audiotag.metadata.field :
    MetadataKey;

import audiotag.metadata.value :
    MetadataBinary,
    MetadataInteger,
    MetadataPicture,
    MetadataPictureSource,
    MetadataPosition,
    MetadataText,
    MetadataTextList,
    MetadataUrl,
    MetadataValue;


/++
Canonical value family expected by a registered metadata field.

This mirrors the initial alternatives of `MetadataValue` without
coupling registry entries to D type introspection.
+/
enum MetadataValueKind : ubyte
{
    text,
    textList,
    integer,
    url,
    binary,
    picture,
    position
}


/++
Permitted field multiplicity in the canonical metadata tree.

The tree always preserves physical insertion order. Multiplicity only
states whether more than one field with the same semantic key is valid.
+/
enum MetadataMultiplicity : ubyte
{
    /// At most one canonical field is normally expected.
    single,

    /// Multiple independent fields are valid.
    repeated
}


/++
Registry definition for one canonical metadata field.
+/
struct MetadataFieldDefinition
{
    /// Stable canonical semantic key.
    MetadataKey key;

    /// Required canonical value family.
    MetadataValueKind valueKind;

    /// Whether the field may occur more than once.
    MetadataMultiplicity multiplicity;

    /++
    Returns whether `value` belongs to the registered value family.
    +/
    bool accepts(MetadataValue value) const
        @safe
    {
        return metadataValueKind(value) == valueKind;
    }

    /++
    Returns whether multiple fields with this key are permitted.
    +/
    @property
    bool repeated() const
        @safe pure nothrow @nogc
    {
        return multiplicity == MetadataMultiplicity.repeated;
    }
}


/++
Result of looking up one canonical field definition.
+/
struct MetadataFieldDefinitionLookup
{
    /// Whether a registry definition was found.
    bool found;

    /// Definition when `found` is true.
    MetadataFieldDefinition definition;

    /++
    Constructs a successful registry lookup.
    +/
    static MetadataFieldDefinitionLookup success(
        MetadataFieldDefinition definition
    )
        @safe pure nothrow @nogc
    {
        return MetadataFieldDefinitionLookup(
            true,
            definition
        );
    }

    /++
    Constructs a registry lookup without a match.
    +/
    static MetadataFieldDefinitionLookup notFound()
        @safe pure nothrow @nogc
    {
        return MetadataFieldDefinitionLookup(
            false,
            MetadataFieldDefinition.init
        );
    }
}


/++
Returns the canonical value family represented by `value`.
+/
MetadataValueKind metadataValueKind(MetadataValue value)
    @safe
{
    return value.match!(
        (MetadataText text) =>
            MetadataValueKind.text,

        (MetadataTextList list) =>
            MetadataValueKind.textList,

        (MetadataInteger integer) =>
            MetadataValueKind.integer,

        (MetadataUrl url) =>
            MetadataValueKind.url,

        (MetadataBinary binary) =>
            MetadataValueKind.binary,

        (MetadataPicture picture) =>
            MetadataValueKind.picture,

        (MetadataPosition position) =>
            MetadataValueKind.position
    );
}


/++
Initial canonical metadata registry.

Only keys whose semantics fit the current canonical value model are
registered here. More specialized concepts such as dates and roles should
be added only after their canonical representation has been decided.
+/
private immutable MetadataFieldDefinition[] definitions =
[
    MetadataFieldDefinition(
        MetadataKey("title"),
        MetadataValueKind.text,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("artist"),
        MetadataValueKind.textList,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("album"),
        MetadataValueKind.text,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("comment"),
        MetadataValueKind.text,
        MetadataMultiplicity.repeated
    ),

    MetadataFieldDefinition(
        MetadataKey("lyrics"),
        MetadataValueKind.text,
        MetadataMultiplicity.repeated
    ),

    MetadataFieldDefinition(
        MetadataKey("artwork"),
        MetadataValueKind.picture,
        MetadataMultiplicity.repeated
    ),

    MetadataFieldDefinition(
        MetadataKey("commercialUrl"),
        MetadataValueKind.url,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("copyrightUrl"),
        MetadataValueKind.url,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("audioFileUrl"),
        MetadataValueKind.url,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("artistUrl"),
        MetadataValueKind.url,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("audioSourceUrl"),
        MetadataValueKind.url,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("radioStationUrl"),
        MetadataValueKind.url,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("paymentUrl"),
        MetadataValueKind.url,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("publisherUrl"),
        MetadataValueKind.url,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("userUrl"),
        MetadataValueKind.url,
        MetadataMultiplicity.repeated
    ),

    MetadataFieldDefinition(
        MetadataKey("userText"),
        MetadataValueKind.text,
        MetadataMultiplicity.repeated
    ),

    MetadataFieldDefinition(
        MetadataKey("privateData"),
        MetadataValueKind.binary,
        MetadataMultiplicity.repeated
    ),

    MetadataFieldDefinition(
        MetadataKey("uniqueFileIdentifier"),
        MetadataValueKind.binary,
        MetadataMultiplicity.repeated
    ),

    MetadataFieldDefinition(
        MetadataKey("track"),
        MetadataValueKind.position,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("disc"),
        MetadataValueKind.position,
        MetadataMultiplicity.single
    ),

    MetadataFieldDefinition(
        MetadataKey("genre"),
        MetadataValueKind.textList,
        MetadataMultiplicity.single
    )
];


/++
Returns all currently registered canonical field definitions.

The returned array is immutable registry data.
+/
const(MetadataFieldDefinition)[] metadataFieldDefinitions()
    @safe pure nothrow @nogc
{
    return definitions;
}


/++
Looks up one canonical field definition by semantic key.

Unknown keys are not errors. The registry is intentionally extensible,
and unregistered native metadata may later be represented through an
extension mechanism rather than being discarded.
+/
MetadataFieldDefinitionLookup
findMetadataFieldDefinition(MetadataKey key)
    @safe
{
    foreach (definition; definitions)
    {
        if (definition.key.name == key.name)
        {
            return MetadataFieldDefinitionLookup.success(
                definition
            );
        }
    }

    return MetadataFieldDefinitionLookup.notFound();
}


/// Each MetadataValue alternative maps to one explicit registry kind.
unittest
{
    assert(
        metadataValueKind(
            MetadataValue(
                MetadataText("x")
            )
        ) == MetadataValueKind.text
    );

    assert(
        metadataValueKind(
            MetadataValue(
                MetadataTextList(["x", "y"])
            )
        ) == MetadataValueKind.textList
    );

    assert(
        metadataValueKind(
            MetadataValue(
                MetadataInteger(42)
            )
        ) == MetadataValueKind.integer
    );

    assert(
        metadataValueKind(
            MetadataValue(
                MetadataUrl("https://example.invalid/")
            )
        ) == MetadataValueKind.url
    );

    assert(
        metadataValueKind(
            MetadataValue(
                MetadataBinary.copyFrom(
                    [cast(ubyte) 0x01]
                )
            )
        ) == MetadataValueKind.binary
    );

    MetadataPictureSource pictureSource =
        MetadataBinary.copyFrom(
            [cast(ubyte) 0xFF],
            "image/jpeg"
        );

    assert(
        metadataValueKind(
            MetadataValue(
                MetadataPicture(
                    "",
                    pictureSource
                )
            )
        ) == MetadataValueKind.picture
    );

    assert(
        metadataValueKind(
            MetadataValue(
                MetadataPosition.numberAndTotal(
                    3,
                    12
                )
            )
        ) == MetadataValueKind.position
    );
}


/// Registered keys are stable canonical names.
unittest
{
    auto title =
        findMetadataFieldDefinition(
            MetadataKey("title")
        );

    assert(title.found);
    assert(title.definition.key.name == "title");

    assert(
        title.definition.valueKind ==
        MetadataValueKind.text
    );

    assert(!title.definition.repeated);


    auto comment =
        findMetadataFieldDefinition(
            MetadataKey("comment")
        );

    assert(comment.found);
    assert(comment.definition.repeated);
}


/// Registry definitions can validate canonical value families.
unittest
{
    auto artist =
        findMetadataFieldDefinition(
            MetadataKey("artist")
        );

    assert(artist.found);

    assert(
        artist.definition.accepts(
            MetadataValue(
                MetadataTextList(
                    ["Artist A", "Artist B"]
                )
            )
        )
    );

    assert(
        !artist.definition.accepts(
            MetadataValue(
                MetadataText("Artist A")
            )
        )
    );
}


/// Artwork is explicitly repeatable and picture-typed.
unittest
{
    auto artwork =
        findMetadataFieldDefinition(
            MetadataKey("artwork")
        );

    assert(artwork.found);
    assert(artwork.definition.repeated);

    assert(
        artwork.definition.valueKind ==
        MetadataValueKind.picture
    );
}


/// Standard URL fields are registered as URL-typed single values.
unittest
{
    foreach (key;
        [
            "commercialUrl",
            "copyrightUrl",
            "audioFileUrl",
            "artistUrl",
            "audioSourceUrl",
            "radioStationUrl",
            "paymentUrl",
            "publisherUrl"
        ])
    {
        auto definition =
            findMetadataFieldDefinition(
                MetadataKey(key)
            );

        assert(definition.found);

        assert(
            definition.definition.valueKind ==
            MetadataValueKind.url
        );

        assert(
            definition.definition.multiplicity ==
            MetadataMultiplicity.single
        );
    }
}


/// User-defined URLs retain explicit repeatability.
unittest
{
    auto definition =
        findMetadataFieldDefinition(
            MetadataKey("userUrl")
        );

    assert(definition.found);

    assert(
        definition.definition.valueKind ==
        MetadataValueKind.url
    );

    assert(
        definition.definition.multiplicity ==
        MetadataMultiplicity.repeated
    );
}


/// User-defined text is explicitly repeatable scalar text.
unittest
{
    auto definition =
        findMetadataFieldDefinition(
            MetadataKey("userText")
        );

    assert(definition.found);

    assert(
        definition.definition.valueKind ==
        MetadataValueKind.text
    );

    assert(
        definition.definition.multiplicity ==
        MetadataMultiplicity.repeated
    );
}


/// Opaque private metadata is repeatable canonical binary data.
unittest
{
    auto definition =
        findMetadataFieldDefinition(
            MetadataKey("privateData")
        );

    assert(definition.found);

    assert(
        definition.definition.valueKind ==
        MetadataValueKind.binary
    );

    assert(
        definition.definition.multiplicity ==
        MetadataMultiplicity.repeated
    );
}


/// Unique file identifiers are repeatable canonical binary data.
unittest
{
    auto definition =
        findMetadataFieldDefinition(
            MetadataKey("uniqueFileIdentifier")
        );

    assert(definition.found);

    assert(
        definition.definition.valueKind ==
        MetadataValueKind.binary
    );

    assert(
        definition.definition.multiplicity ==
        MetadataMultiplicity.repeated
    );
}


/// Track and disc use one shared position value family.
unittest
{
    foreach (key; ["track", "disc"])
    {
        auto definition =
            findMetadataFieldDefinition(
                MetadataKey(key)
            );

        assert(definition.found);

        assert(
            definition.definition.valueKind ==
            MetadataValueKind.position
        );

        assert(
            definition.definition.multiplicity ==
            MetadataMultiplicity.single
        );

        assert(
            definition.definition.accepts(
                MetadataValue(
                    MetadataPosition.numberAndTotal(
                        1,
                        2
                    )
                )
            )
        );
    }
}


/// Genre is one semantic field containing an ordered genre list.
unittest
{
    auto definition =
        findMetadataFieldDefinition(
            MetadataKey("genre")
        );

    assert(definition.found);

    assert(
        definition.definition.valueKind ==
        MetadataValueKind.textList
    );

    assert(
        definition.definition.multiplicity ==
        MetadataMultiplicity.single
    );

    assert(
        definition.definition.accepts(
            MetadataValue(
                MetadataTextList(
                    [
                        "Electronic",
                        "Ambient"
                    ]
                )
            )
        )
    );

    assert(
        !definition.definition.accepts(
            MetadataValue(
                MetadataText(
                    "Electronic"
                )
            )
        )
    );
}


/// Unknown canonical keys remain explicitly unregistered.
unittest
{
    auto unknown =
        findMetadataFieldDefinition(
            MetadataKey("not-yet-defined")
        );

    assert(!unknown.found);
}


/// Registry enumeration preserves stable definition order.
unittest
{
    const registry =
        metadataFieldDefinitions();

    assert(registry.length == 21);

    assert(registry[0].key.name == "title");
    assert(registry[1].key.name == "artist");
    assert(registry[2].key.name == "album");
    assert(registry[3].key.name == "comment");
    assert(registry[4].key.name == "lyrics");
    assert(registry[5].key.name == "artwork");
    assert(registry[6].key.name == "commercialUrl");
    assert(registry[7].key.name == "copyrightUrl");
    assert(registry[8].key.name == "audioFileUrl");
    assert(registry[9].key.name == "artistUrl");
    assert(registry[10].key.name == "audioSourceUrl");
    assert(registry[11].key.name == "radioStationUrl");
    assert(registry[12].key.name == "paymentUrl");
    assert(registry[13].key.name == "publisherUrl");
    assert(registry[14].key.name == "userUrl");
    assert(registry[15].key.name == "userText");
    assert(registry[16].key.name == "privateData");
    assert(registry[17].key.name == "uniqueFileIdentifier");
    assert(registry[18].key.name == "track");
    assert(registry[19].key.name == "disc");
    assert(registry[20].key.name == "genre");
}
