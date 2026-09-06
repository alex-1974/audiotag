/++
Reverse canonical-target registry for ID3v2.3 writing.

The canonical registry is format-independent. This module records the
deterministic ID3v2.3 target for every canonical semantic key currently
produced by the implemented ID3v2.3 reader.

A target definition identifies:

- the canonical semantic key;
- the canonical value kind expected by that key;
- the native ID3v2.3 frame identifier;
- the serializer family that will eventually encode the frame.

Finding a target does not yet guarantee that one concrete
`MetadataField` is losslessly serializable. Context such as language,
descriptions, owner qualifiers, picture roles and ID3v2.3 encoding
limits belongs to the subsequent new-frame planning layer.

No bytes are serialized here.
+/
module audiotag.id3v2.v23.canonical_target;

import audiotag.metadata.field :
    MetadataKey;

import audiotag.metadata.registry :
    MetadataValueKind;


/++
ID3v2.3 serializer family required by a canonical target.

These families correspond to the semantic codec families already used
by the reader while keeping the exact native frame identifier separate.
+/
enum Id3v23CanonicalTargetFamily : ubyte
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
One deterministic canonical-to-ID3v2.3 target definition.
+/
struct Id3v23CanonicalTargetDefinition
{
    /// Format-independent canonical semantic key.
    MetadataKey key;

    /// Canonical value family accepted by this target.
    MetadataValueKind valueKind;

    /// Four-character native ID3v2.3 frame identifier.
    string frameId;

    /// Serializer family required to encode the target.
    Id3v23CanonicalTargetFamily family;
}


/++
Result of looking up one canonical ID3v2.3 target.
+/
struct Id3v23CanonicalTargetLookup
{
    /// Whether a deterministic ID3v2.3 target exists.
    bool found;

    /// Target definition when `found` is true.
    Id3v23CanonicalTargetDefinition definition;


    /++
    Constructs a successful target lookup.
    +/
    static Id3v23CanonicalTargetLookup success(
        Id3v23CanonicalTargetDefinition definition
    )
        @safe pure nothrow @nogc
    {
        return
            Id3v23CanonicalTargetLookup(
                true,
                definition
            );
    }


    /++
    Constructs a lookup without an ID3v2.3 target.
    +/
    static Id3v23CanonicalTargetLookup notFound()
        @safe pure nothrow @nogc
    {
        return
            Id3v23CanonicalTargetLookup(
                false,
                Id3v23CanonicalTargetDefinition.init
            );
    }
}


/++
Current deterministic canonical-to-ID3v2.3 target registry.

The registry deliberately mirrors only canonical semantics already
supported by the active ID3v2.3 reader.
+/
private immutable
Id3v23CanonicalTargetDefinition[] definitions =
[
    Id3v23CanonicalTargetDefinition(
        MetadataKey("title"),
        MetadataValueKind.text,
        "TIT2",
        Id3v23CanonicalTargetFamily.textInformation
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("artist"),
        MetadataValueKind.textList,
        "TPE1",
        Id3v23CanonicalTargetFamily.textInformation
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("album"),
        MetadataValueKind.text,
        "TALB",
        Id3v23CanonicalTargetFamily.textInformation
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("comment"),
        MetadataValueKind.text,
        "COMM",
        Id3v23CanonicalTargetFamily.languageText
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("lyrics"),
        MetadataValueKind.text,
        "USLT",
        Id3v23CanonicalTargetFamily.languageText
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("artwork"),
        MetadataValueKind.picture,
        "APIC",
        Id3v23CanonicalTargetFamily.attachedPicture
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("commercialUrl"),
        MetadataValueKind.url,
        "WCOM",
        Id3v23CanonicalTargetFamily.urlLink
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("copyrightUrl"),
        MetadataValueKind.url,
        "WCOP",
        Id3v23CanonicalTargetFamily.urlLink
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("audioFileUrl"),
        MetadataValueKind.url,
        "WOAF",
        Id3v23CanonicalTargetFamily.urlLink
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("artistUrl"),
        MetadataValueKind.url,
        "WOAR",
        Id3v23CanonicalTargetFamily.urlLink
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("audioSourceUrl"),
        MetadataValueKind.url,
        "WOAS",
        Id3v23CanonicalTargetFamily.urlLink
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("radioStationUrl"),
        MetadataValueKind.url,
        "WORS",
        Id3v23CanonicalTargetFamily.urlLink
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("paymentUrl"),
        MetadataValueKind.url,
        "WPAY",
        Id3v23CanonicalTargetFamily.urlLink
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("publisherUrl"),
        MetadataValueKind.url,
        "WPUB",
        Id3v23CanonicalTargetFamily.urlLink
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("userUrl"),
        MetadataValueKind.url,
        "WXXX",
        Id3v23CanonicalTargetFamily.userUrl
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("userText"),
        MetadataValueKind.text,
        "TXXX",
        Id3v23CanonicalTargetFamily.userText
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("privateData"),
        MetadataValueKind.binary,
        "PRIV",
        Id3v23CanonicalTargetFamily.privateData
    ),

    Id3v23CanonicalTargetDefinition(
        MetadataKey("uniqueFileIdentifier"),
        MetadataValueKind.binary,
        "UFID",
        Id3v23CanonicalTargetFamily.uniqueFileIdentifier
    )
];


/++
Returns all deterministic canonical ID3v2.3 target definitions.

The returned slice is immutable registry data.
+/
const(Id3v23CanonicalTargetDefinition)[]
id3v23CanonicalTargetDefinitions()
    @safe pure nothrow @nogc
{
    return definitions;
}


/++
Finds the deterministic ID3v2.3 target for one canonical key.

Unknown canonical keys are not errors. They simply have no currently
defined ID3v2.3 target.

Params:
    key = Canonical semantic key.

Returns:
    Explicit found/not-found target lookup.
+/
Id3v23CanonicalTargetLookup
findId3v23CanonicalTarget(
    MetadataKey key
)
    @safe pure nothrow @nogc
{
    foreach (
        definition;
        definitions
    )
    {
        if (
            definition.key.name ==
            key.name
        )
        {
            return
                Id3v23CanonicalTargetLookup
                    .success(
                        definition
                    );
        }
    }


    return
        Id3v23CanonicalTargetLookup
            .notFound();
}


version (unittest)
{
    import audiotag.metadata.registry :
        findMetadataFieldDefinition;
}


/// The reverse target registry covers the current canonical ID3 surface.
unittest
{
    const targets =
        id3v23CanonicalTargetDefinitions();


    assert(
        targets.length ==
        18
    );


    foreach (
        target;
        targets
    )
    {
        assert(
            target.frameId.length ==
            4
        );


        const canonical =
            findMetadataFieldDefinition(
                target.key
            );


        assert(
            canonical.found
        );


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
        findId3v23CanonicalTarget(
            MetadataKey("title")
        );


    assert(title.found);
    assert(title.definition.frameId == "TIT2");

    assert(
        title.definition.family ==
        Id3v23CanonicalTargetFamily
            .textInformation
    );


    const artist =
        findId3v23CanonicalTarget(
            MetadataKey("artist")
        );


    assert(artist.found);
    assert(artist.definition.frameId == "TPE1");

    assert(
        artist.definition.valueKind ==
        MetadataValueKind.textList
    );


    const album =
        findId3v23CanonicalTarget(
            MetadataKey("album")
        );


    assert(album.found);
    assert(album.definition.frameId == "TALB");
}


/// Language-bearing canonical text maps to COMM and USLT.
unittest
{
    const comment =
        findId3v23CanonicalTarget(
            MetadataKey("comment")
        );


    assert(comment.found);
    assert(comment.definition.frameId == "COMM");

    assert(
        comment.definition.family ==
        Id3v23CanonicalTargetFamily
            .languageText
    );


    const lyrics =
        findId3v23CanonicalTarget(
            MetadataKey("lyrics")
        );


    assert(lyrics.found);
    assert(lyrics.definition.frameId == "USLT");
}


/// Artwork maps uniquely to APIC.
unittest
{
    const artwork =
        findId3v23CanonicalTarget(
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
        Id3v23CanonicalTargetFamily
            .attachedPicture
    );
}


/// Standard canonical URL keys retain their exact ID3v2.3 identifiers.
unittest
{
    struct Case
    {
        string key;
        string frameId;
    }


    foreach (
        testCase;
        [
            Case("commercialUrl", "WCOM"),
            Case("copyrightUrl", "WCOP"),
            Case("audioFileUrl", "WOAF"),
            Case("artistUrl", "WOAR"),
            Case("audioSourceUrl", "WOAS"),
            Case("radioStationUrl", "WORS"),
            Case("paymentUrl", "WPAY"),
            Case("publisherUrl", "WPUB")
        ]
    )
    {
        const target =
            findId3v23CanonicalTarget(
                MetadataKey(
                    testCase.key
                )
            );


        assert(
            target.found
        );


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
            Id3v23CanonicalTargetFamily
                .urlLink
        );
    }
}


/// User-defined canonical fields map to their dedicated ID3 frames.
unittest
{
    const userText =
        findId3v23CanonicalTarget(
            MetadataKey("userText")
        );


    assert(userText.found);
    assert(userText.definition.frameId == "TXXX");

    assert(
        userText.definition.family ==
        Id3v23CanonicalTargetFamily
            .userText
    );


    const userUrl =
        findId3v23CanonicalTarget(
            MetadataKey("userUrl")
        );


    assert(userUrl.found);
    assert(userUrl.definition.frameId == "WXXX");

    assert(
        userUrl.definition.family ==
        Id3v23CanonicalTargetFamily
            .userUrl
    );
}


/// Opaque binary fields retain distinct native target families.
unittest
{
    const privateData =
        findId3v23CanonicalTarget(
            MetadataKey("privateData")
        );


    assert(privateData.found);
    assert(privateData.definition.frameId == "PRIV");

    assert(
        privateData.definition.family ==
        Id3v23CanonicalTargetFamily
            .privateData
    );


    const identifier =
        findId3v23CanonicalTarget(
            MetadataKey(
                "uniqueFileIdentifier"
            )
        );


    assert(identifier.found);
    assert(identifier.definition.frameId == "UFID");

    assert(
        identifier.definition.family ==
        Id3v23CanonicalTargetFamily
            .uniqueFileIdentifier
    );
}


/// Unknown canonical semantics remain explicitly unmapped.
unittest
{
    const target =
        findId3v23CanonicalTarget(
            MetadataKey("futureSemantic")
        );


    assert(
        !target.found
    );
}
