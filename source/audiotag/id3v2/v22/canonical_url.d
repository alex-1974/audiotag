/++
Canonical mapping for ID3v2.2 URL-link frames.

Mappings:

- WCM -> commercialUrl
- WCP -> copyrightUrl
- WAF -> audioFileUrl
- WAR -> artistUrl
- WAS -> audioSourceUrl
- WPB -> publisherUrl
- WXX -> userUrl

Unknown but structurally valid `W**` frames remain preserved natively and are
reported as unsupported at canonical-mapping level.


Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.canonical_url;

import std.sumtype : match;

import audiotag.id3v2.v22.canonical_mapping :
    Id3v22CanonicalMappingResult,
    Id3v22CanonicalMappingStatus;

import audiotag.id3v2.v22.native_frame :
    Id3v22NativeFrame;

import audiotag.id3v2.v22.url_link :
    Id3v22UrlLinkFrame;

import audiotag.id3v2.v22.user_url :
    Id3v22UserUrlFrame;

import audiotag.metadata.field :
    MetadataField,
    MetadataKey;

import audiotag.metadata.provenance :
    MetadataConfidence,
    MetadataProvenance,
    MetadataSystem,
    NativeMetadataIdentifier;

import audiotag.metadata.registry :
    findMetadataFieldDefinition;

import audiotag.metadata.value :
    MetadataUrl,
    MetadataValue;


Id3v22CanonicalMappingResult
mapId3v22UrlLinkFrameToCanonical(
    Id3v22UrlLinkFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    const mapping =
        ordinaryUrlMapping(
            frame.id
        );

    if (!mapping.found)
    {
        return
            Id3v22CanonicalMappingResult
                .unsupported();
    }

    return
        Id3v22CanonicalMappingResult
            .success(
                makeUrlField(
                    mapping.canonicalKey,
                    mapping.nativeIdentifier,
                    frame.url,
                    "",
                    frame.sourceOffset,
                    sourceLength
                )
            );
}


Id3v22CanonicalMappingResult
mapId3v22UserUrlFrameToCanonical(
    Id3v22UserUrlFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    return
        Id3v22CanonicalMappingResult
            .success(
                makeUrlField(
                    "userUrl",
                    "WXX",
                    frame.url,
                    frame.description,
                    frame.sourceOffset,
                    sourceLength
                )
            );
}


Id3v22CanonicalMappingResult
mapId3v22NativeUrlFrameToCanonical(
    Id3v22NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v22UrlLinkFrame frame) =>
                mapId3v22UrlLinkFrameToCanonical(
                    frame,
                    native.sourceLength
                ),

            (Id3v22UserUrlFrame frame) =>
                mapId3v22UserUrlFrameToCanonical(
                    frame,
                    native.sourceLength
                ),

            _ =>
                Id3v22CanonicalMappingResult
                    .unsupported()
        );
}


private struct OrdinaryUrlMapping
{
    bool found;
    string canonicalKey;
    string nativeIdentifier;
}


private OrdinaryUrlMapping
ordinaryUrlMapping(
    const ref char[3] id
)
    @safe pure nothrow @nogc
{
    if (idEquals(id, "WCM"))
        return OrdinaryUrlMapping(
            true,
            "commercialUrl",
            "WCM"
        );

    if (idEquals(id, "WCP"))
        return OrdinaryUrlMapping(
            true,
            "copyrightUrl",
            "WCP"
        );

    if (idEquals(id, "WAF"))
        return OrdinaryUrlMapping(
            true,
            "audioFileUrl",
            "WAF"
        );

    if (idEquals(id, "WAR"))
        return OrdinaryUrlMapping(
            true,
            "artistUrl",
            "WAR"
        );

    if (idEquals(id, "WAS"))
        return OrdinaryUrlMapping(
            true,
            "audioSourceUrl",
            "WAS"
        );

    if (idEquals(id, "WPB"))
        return OrdinaryUrlMapping(
            true,
            "publisherUrl",
            "WPB"
        );

    return OrdinaryUrlMapping.init;
}


private bool
idEquals(
    const ref char[3] id,
    string expected
)
    @safe pure nothrow @nogc
{
    return
        expected.length == 3 &&
        id[0] == expected[0] &&
        id[1] == expected[1] &&
        id[2] == expected[2];
}


private MetadataField
makeUrlField(
    string canonicalKey,
    string nativeIdentifier,
    string url,
    string description,
    size_t sourceOffset,
    size_t sourceLength
)
    @safe
{
    auto field =
        MetadataField(
            MetadataKey(
                canonicalKey
            ),
            MetadataValue(
                MetadataUrl(
                    url
                )
            ),
            [
                makeProvenance(
                    nativeIdentifier,
                    sourceOffset,
                    sourceLength
                )
            ]
        );

    field.description =
        description;

    assertRegisteredShape(
        field
    );

    return field;
}


private MetadataProvenance
makeProvenance(
    string nativeIdentifier,
    size_t sourceOffset,
    size_t sourceLength
)
    @safe pure nothrow @nogc
{
    return
        MetadataProvenance(
            NativeMetadataIdentifier(
                MetadataSystem.id3v2,
                nativeIdentifier
            ),
            sourceOffset,
            sourceLength,
            MetadataConfidence.exact
        );
}


private void
assertRegisteredShape(
    MetadataField field
)
    @safe
{
    const definition =
        findMetadataFieldDefinition(
            field.key
        );

    assert(definition.found);
    assert(
        definition.definition
            .accepts(
                field.value
            )
    );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.frame :
        Id3v22FrameEnvelope,
        parseId3v22FrameEnvelope;

    import audiotag.id3v2.v22.native_frame :
        Id3v22NativeFrameContent,
        Id3v22UnknownFrame,
        decodeId3v22NativeFrame;


    private Id3v22UrlLinkFrame
    testUrlFrame(
        string id,
        string url,
        size_t sourceOffset = 100
    )
        @safe
    {
        assert(id.length == 3);

        Id3v22UrlLinkFrame frame;

        frame.sourceOffset =
            sourceOffset;

        frame.id[] =
            id[];

        frame.url =
            url;

        return frame;
    }
}


/// Every standardized ordinary ID3v2.2 URL frame maps distinctly.
unittest
{
    struct Case
    {
        string id;
        string canonicalKey;
    }

    const cases =
        [
            Case("WCM", "commercialUrl"),
            Case("WCP", "copyrightUrl"),
            Case("WAF", "audioFileUrl"),
            Case("WAR", "artistUrl"),
            Case("WAS", "audioSourceUrl"),
            Case("WPB", "publisherUrl")
        ];

    foreach (entry; cases)
    {
        auto result =
            mapId3v22UrlLinkFrameToCanonical(
                testUrlFrame(
                    entry.id,
                    "https://example.invalid/item",
                    123
                )
            );

        assert(result.mapped);
        assert(
            result.field.key.name ==
            entry.canonicalKey
        );

        assert(
            result.field.provenance[0]
                .native.identifier ==
            entry.id
        );

        assert(
            result.field.provenance[0]
                .sourceOffset ==
            123
        );

        const matches =
            result.field.value.match!(
                (MetadataUrl url) =>
                    url.value ==
                    "https://example.invalid/item",

                _ =>
                    false
            );

        assert(matches);
    }
}


/// Experimental/vendor ordinary URL frames are not invented canonically.
unittest
{
    auto result =
        mapId3v22UrlLinkFrameToCanonical(
            testUrlFrame(
                "WZ9",
                "https://example.invalid/"
            )
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v22CanonicalMappingStatus
            .unsupportedFrame
    );
}


/// WXX preserves URL and user-defined description.
unittest
{
    Id3v22UserUrlFrame frame;

    frame.sourceOffset =
        321;

    frame.description =
        "project";

    frame.url =
        "https://example.invalid/project";

    auto result =
        mapId3v22UserUrlFrameToCanonical(
            frame
        );

    assert(result.mapped);
    assert(result.field.key.name == "userUrl");
    assert(result.field.hasDescription);
    assert(result.field.description == "project");

    assert(
        result.field.provenance[0]
            .native.identifier ==
        "WXX"
    );

    const matches =
        result.field.value.match!(
            (MetadataUrl url) =>
                url.value ==
                "https://example.invalid/project",

            _ =>
                false
        );

    assert(matches);
}


/// Empty WXX descriptions remain unspecified canonical descriptions.
unittest
{
    Id3v22UserUrlFrame frame;

    frame.url =
        "https://example.invalid/";

    auto result =
        mapId3v22UserUrlFrameToCanonical(
            frame
        );

    assert(result.mapped);
    assert(!result.field.hasDescription);
}


/// Native ordinary URL mapping records the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'C', 'M',
            0x00, 0x00, 0x08,

            'h', 't', 't', 'p',
            ':', '/', '/', 'a'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto envelope =
        cursor.parseId3v22FrameEnvelope();

    assert(envelope.hasValue);

    auto native =
        decodeId3v22NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v22NativeUrlFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);
    assert(mapped.field.key.name == "commercialUrl");

    assert(
        mapped.field.provenance[0]
            .sourceOffset ==
        700
    );

    assert(
        mapped.field.provenance[0]
            .sourceLength ==
        bytes.length
    );
}


/// Native WXX mapping records the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X',
            0x00, 0x00, 0x04,

            0x00,
            'p',
            0x00,
            'x'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                800
            )
        );

    auto envelope =
        cursor.parseId3v22FrameEnvelope();

    assert(envelope.hasValue);

    auto native =
        decodeId3v22NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v22NativeUrlFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);
    assert(mapped.field.key.name == "userUrl");
    assert(mapped.field.description == "p");

    assert(
        mapped.field.provenance[0]
            .sourceOffset ==
        800
    );

    assert(
        mapped.field.provenance[0]
            .sourceLength ==
        bytes.length
    );
}


/// Other native frame families remain unsupported.
unittest
{
    Id3v22NativeFrameContent content =
        Id3v22UnknownFrame();

    auto native =
        Id3v22NativeFrame(
            Id3v22FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v22NativeUrlFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v22CanonicalMappingStatus
            .unsupportedFrame
    );
}
