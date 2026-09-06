/++
Reverse canonical-target registry for ID3v2.4 writing.

The canonical registry is format-independent. This module records the
deterministic ID3v2.4 target for every canonical semantic key currently
produced by the implemented ID3v2.4 reader.

A target definition identifies:

- the canonical semantic key;
- the canonical value kind expected by that key;
- the native ID3v2.4 frame identifier;
- the serializer family that will eventually encode the frame.

Finding a target does not yet guarantee that one concrete
`MetadataField` is losslessly serializable. Context such as language,
descriptions, owner qualifiers, picture roles and byte-encoding limits
belongs to the subsequent new-frame planning layer.

No bytes are serialized here.
+/
module audiotag.id3v2.v24.canonical_target;

import audiotag.metadata.field :
    MetadataKey;

import audiotag.metadata.registry :
    MetadataValueKind;


/++
ID3v2.4 serializer family required by a canonical target.

These families correspond to the semantic codec families already used
by the reader while keeping the exact native frame identifier separate.
+/
enum Id3v24CanonicalTargetFamily : ubyte
{
    textInformation,
    userText,
    languageText,
    attachedPicture,
    urlLink,
    userUrl,
    privateData,
    uniqueFileIdentifier
}


/++
One deterministic canonical-to-ID3v2.4 target definition.
+/
struct Id3v24CanonicalTargetDefinition
{
    /// Format-independent canonical semantic key.
    MetadataKey key;

    /// Canonical value family accepted by this target.
    MetadataValueKind valueKind;

    /// Four-character native ID3v2.4 frame identifier.
    string frameId;

    /// Serializer family required to encode the target.
    Id3v24CanonicalTargetFamily family;
}


/++
Result of looking up one canonical ID3v2.4 target.
+/
struct Id3v24CanonicalTargetLookup
{
    /// Whether a deterministic ID3v2.4 target exists.
    bool found;

    /// Target definition when `found` is true.
    Id3v24CanonicalTargetDefinition definition;

    /++
    Constructs a successful target lookup.
    +/
    static Id3v24CanonicalTargetLookup success(
        Id3v24CanonicalTargetDefinition definition
    )
        @safe pure nothrow @nogc
    {
        return
            Id3v24CanonicalTargetLookup(
                true,
                definition
            );
    }

    /++
    Constructs a lookup without an ID3v2.4 target.
    +/
    static Id3v24CanonicalTargetLookup notFound()
        @safe pure nothrow @nogc
    {
        return
            Id3v24CanonicalTargetLookup(
                false,
                Id3v24CanonicalTargetDefinition.init
            );
    }
}


/++
Current deterministic canonical-to-ID3v2.4 target registry.

The registry deliberately mirrors only canonical semantics already
supported by the active ID3v2.4 reader.
+/
private immutable
Id3v24CanonicalTargetDefinition[] definitions =
[
    Id3v24CanonicalTargetDefinition(
        MetadataKey("title"),
        MetadataValueKind.text,
        "TIT2",
        Id3v24CanonicalTargetFamily.textInformation
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("artist"),
        MetadataValueKind.textList,
        "TPE1",
        Id3v24CanonicalTargetFamily.textInformation
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("album"),
        MetadataValueKind.text,
        "TALB",
        Id3v24CanonicalTargetFamily.textInformation
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("comment"),
        MetadataValueKind.text,
        "COMM",
        Id3v24CanonicalTargetFamily.languageText
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("lyrics"),
        MetadataValueKind.text,
        "USLT",
        Id3v24CanonicalTargetFamily.languageText
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("artwork"),
        MetadataValueKind.picture,
        "APIC",
        Id3v24CanonicalTargetFamily.attachedPicture
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("commercialUrl"),
        MetadataValueKind.url,
        "WCOM",
        Id3v24CanonicalTargetFamily.urlLink
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("copyrightUrl"),
        MetadataValueKind.url,
        "WCOP",
        Id3v24CanonicalTargetFamily.urlLink
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("audioFileUrl"),
        MetadataValueKind.url,
        "WOAF",
        Id3v24CanonicalTargetFamily.urlLink
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("artistUrl"),
        MetadataValueKind.url,
        "WOAR",
        Id3v24CanonicalTargetFamily.urlLink
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("audioSourceUrl"),
        MetadataValueKind.url,
        "WOAS",
        Id3v24CanonicalTargetFamily.urlLink
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("radioStationUrl"),
        MetadataValueKind.url,
        "WORS",
        Id3v24CanonicalTargetFamily.urlLink
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("paymentUrl"),
        MetadataValueKind.url,
        "WPAY",
        Id3v24CanonicalTargetFamily.urlLink
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("publisherUrl"),
        MetadataValueKind.url,
        "WPUB",
        Id3v24CanonicalTargetFamily.urlLink
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("userUrl"),
        MetadataValueKind.url,
        "WXXX",
        Id3v24CanonicalTargetFamily.userUrl
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("userText"),
        MetadataValueKind.text,
        "TXXX",
        Id3v24CanonicalTargetFamily.userText
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("privateData"),
        MetadataValueKind.binary,
        "PRIV",
        Id3v24CanonicalTargetFamily.privateData
    ),

    Id3v24CanonicalTargetDefinition(
        MetadataKey("uniqueFileIdentifier"),
        MetadataValueKind.binary,
        "UFID",
        Id3v24CanonicalTargetFamily.uniqueFileIdentifier
    )
];


/++
Returns all deterministic canonical ID3v2.4 target definitions.

The returned slice is immutable registry data.
+/
const(Id3v24CanonicalTargetDefinition)[]
id3v24CanonicalTargetDefinitions()
    @safe pure nothrow @nogc
{
    return definitions;
}


/++
Finds the deterministic ID3v2.4 target for one canonical key.

Unknown canonical keys are not errors. They simply have no currently
defined ID3v2.4 target.

Params:
    key = Canonical semantic key.

Returns:
    Explicit found/not-found target lookup.
+/
Id3v24CanonicalTargetLookup
findId3v24CanonicalTarget(
    MetadataKey key
)
    @safe pure nothrow @nogc
{
    foreach (definition; definitions)
    {
        if (
            definition.key.name ==
            key.name
        )
        {
            return
                Id3v24CanonicalTargetLookup
                    .success(definition);
        }
    }

    return
        Id3v24CanonicalTargetLookup
            .notFound();
}


version (unittest)
{
    import audiotag.metadata.registry :
        findMetadataFieldDefinition;
}


/// The reverse target registry covers the complete current canonical registry.
unittest
{
    const targets =
        id3v24CanonicalTargetDefinitions();

    assert(targets.length == 18);

    foreach (target; targets)
    {
        assert(target.frameId.length == 4);

        const canonical =
            findMetadataFieldDefinition(
                target.key
            );

        assert(canonical.found);

        assert(
            canonical.definition.valueKind ==
            target.valueKind
        );
    }
}


/// Ordinary text semantics have deterministic native frame targets.
unittest
{
    const title =
        findId3v24CanonicalTarget(
            MetadataKey("title")
        );

    assert(title.found);
    assert(title.definition.frameId == "TIT2");

    assert(
        title.definition.family ==
        Id3v24CanonicalTargetFamily
            .textInformation
    );

    const artist =
        findId3v24CanonicalTarget(
            MetadataKey("artist")
        );

    assert(artist.found);
    assert(artist.definition.frameId == "TPE1");

    const album =
        findId3v24CanonicalTarget(
            MetadataKey("album")
        );

    assert(album.found);
    assert(album.definition.frameId == "TALB");
}


/// Language-bearing canonical text maps to COMM and USLT.
unittest
{
    const comment =
        findId3v24CanonicalTarget(
            MetadataKey("comment")
        );

    assert(comment.found);
    assert(comment.definition.frameId == "COMM");

    assert(
        comment.definition.family ==
        Id3v24CanonicalTargetFamily
            .languageText
    );

    const lyrics =
        findId3v24CanonicalTarget(
            MetadataKey("lyrics")
        );

    assert(lyrics.found);
    assert(lyrics.definition.frameId == "USLT");
}


/// Artwork maps uniquely to APIC.
unittest
{
    const artwork =
        findId3v24CanonicalTarget(
            MetadataKey("artwork")
        );

    assert(artwork.found);
    assert(artwork.definition.frameId == "APIC");

    assert(
        artwork.definition.valueKind ==
        MetadataValueKind.picture
    );

    assert(
        artwork.definition.family ==
        Id3v24CanonicalTargetFamily
            .attachedPicture
    );
}


/// Standard canonical URL keys retain their exact ID3v2.4 identifiers.
unittest
{
    struct Case
    {
        string key;
        string frameId;
    }

    foreach (testCase;
        [
            Case("commercialUrl", "WCOM"),
            Case("copyrightUrl", "WCOP"),
            Case("audioFileUrl", "WOAF"),
            Case("artistUrl", "WOAR"),
            Case("audioSourceUrl", "WOAS"),
            Case("radioStationUrl", "WORS"),
            Case("paymentUrl", "WPAY"),
            Case("publisherUrl", "WPUB")
        ])
    {
        const target =
            findId3v24CanonicalTarget(
                MetadataKey(testCase.key)
            );

        assert(target.found);

        assert(
            target.definition.frameId ==
            testCase.frameId
        );

        assert(
            target.definition.valueKind ==
            MetadataValueKind.url
        );

        assert(
            target.definition.family ==
            Id3v24CanonicalTargetFamily
                .urlLink
        );
    }
}


/// User-defined canonical fields map to their dedicated ID3 frames.
unittest
{
    const userText =
        findId3v24CanonicalTarget(
            MetadataKey("userText")
        );

    assert(userText.found);
    assert(userText.definition.frameId == "TXXX");

    assert(
        userText.definition.family ==
        Id3v24CanonicalTargetFamily.userText
    );

    const userUrl =
        findId3v24CanonicalTarget(
            MetadataKey("userUrl")
        );

    assert(userUrl.found);
    assert(userUrl.definition.frameId == "WXXX");

    assert(
        userUrl.definition.family ==
        Id3v24CanonicalTargetFamily.userUrl
    );
}


/// Opaque binary fields retain distinct native target families.
unittest
{
    const privateData =
        findId3v24CanonicalTarget(
            MetadataKey("privateData")
        );

    assert(privateData.found);
    assert(privateData.definition.frameId == "PRIV");

    assert(
        privateData.definition.family ==
        Id3v24CanonicalTargetFamily
            .privateData
    );

    const identifier =
        findId3v24CanonicalTarget(
            MetadataKey("uniqueFileIdentifier")
        );

    assert(identifier.found);
    assert(identifier.definition.frameId == "UFID");

    assert(
        identifier.definition.family ==
        Id3v24CanonicalTargetFamily
            .uniqueFileIdentifier
    );
}


/// Unknown canonical semantics remain explicitly unmapped.
unittest
{
    const target =
        findId3v24CanonicalTarget(
            MetadataKey("futureSemantic")
        );

    assert(!target.found);
}
