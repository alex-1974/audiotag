/++
Canonical mapping for ID3v2.4 URL-link frames.

Ordinary `W***` frames preserve their standardized native semantics
through distinct canonical URL keys:

- WCOM -> commercialUrl
- WCOP -> copyrightUrl
- WOAF -> audioFileUrl
- WOAR -> artistUrl
- WOAS -> audioSourceUrl
- WORS -> radioStationUrl
- WPAY -> paymentUrl
- WPUB -> publisherUrl

`WXXX` maps to the repeatable canonical `userUrl` field and preserves
its user-defined description as canonical field context.

Physical trailing bytes ignored by the ID3 semantic codec remain part
of the native representation and are not copied into the canonical URL
value.

Transformation-pending native outcomes remain valid metadata and return
`requiresTransformation`.
+/
module audiotag.id3v2.v24.canonical_url;

import std.sumtype :
    match;

import audiotag.id3v2.v24.canonical_mapping :
    Id3v24CanonicalMappingResult,
    Id3v24CanonicalMappingStatus;

import audiotag.id3v2.v24.native_frame :
    Id3v24NativeFrame;

import audiotag.id3v2.v24.url_link :
    Id3v24UrlLinkFrame,
    Id3v24UrlLinkOutcome;

import audiotag.id3v2.v24.user_url :
    Id3v24UserUrlFrame,
    Id3v24UserUrlOutcome;

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


/++
Maps one decoded ordinary ID3v2.4 `W***` frame to its canonical URL
field.

Only standardized URL-link identifiers currently represented by the
canonical registry are mapped. Other structurally valid `W***` frames
return `unsupportedFrame`.

Params:
    frame = Decoded ordinary URL-link frame.
    sourceLength = Complete physical frame length when known. Zero
        represents point provenance only.

Returns:
    Canonical URL mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24UrlLinkFrameToCanonical(
    Id3v24UrlLinkFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    const mapping =
        ordinaryUrlMapping(frame.id);

    if (!mapping.found)
    {
        return
            Id3v24CanonicalMappingResult
                .unsupported();
    }

    return Id3v24CanonicalMappingResult.success(
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


/++
Maps one decoded ID3v2.4 `WXXX` frame to canonical `userUrl`.

The native description is retained as canonical field description
context.

Params:
    frame = Decoded WXXX frame.
    sourceLength = Complete physical frame length when known. Zero
        represents point provenance only.

Returns:
    Canonical URL mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24UserUrlFrameToCanonical(
    Id3v24UserUrlFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    return Id3v24CanonicalMappingResult.success(
        makeUrlField(
            "userUrl",
            "WXXX",
            frame.url,
            frame.description,
            frame.sourceOffset,
            sourceLength
        )
    );
}


/++
Maps one unified native ID3v2.4 frame through the URL canonical mapper.

Ordinary `W***` and user-defined `WXXX` outcomes are handled here.
Decoded outcomes are mapped; compressed or encrypted outcomes return an
explicit transformation requirement.

Params:
    native = Unified native ID3v2.4 frame.

Returns:
    Canonical URL mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24NativeUrlFrameToCanonical(
    Id3v24NativeFrame native
)
    @safe
{
    return native.content.match!(
        (Id3v24UrlLinkOutcome outcome) =>
            outcome.decoded
                ? mapId3v24UrlLinkFrameToCanonical(
                    outcome.link,
                    native.sourceLength
                )
                : Id3v24CanonicalMappingResult
                    .transformationRequired(),

        (Id3v24UserUrlOutcome outcome) =>
            outcome.decoded
                ? mapId3v24UserUrlFrameToCanonical(
                    outcome.link,
                    native.sourceLength
                )
                : Id3v24CanonicalMappingResult
                    .transformationRequired(),

        _ =>
            Id3v24CanonicalMappingResult
                .unsupported()
    );
}


/++
Mapping information for one standardized ordinary URL-link identifier.
+/
private struct OrdinaryUrlMapping
{
    bool found;
    string canonicalKey;
    string nativeIdentifier;
}


/++
Returns the canonical mapping for one ordinary ID3v2.4 URL identifier.
+/
private OrdinaryUrlMapping ordinaryUrlMapping(
    const ref char[4] id
)
    @safe pure nothrow @nogc
{
    if (idEquals(id, "WCOM"))
    {
        return OrdinaryUrlMapping(
            true,
            "commercialUrl",
            "WCOM"
        );
    }

    if (idEquals(id, "WCOP"))
    {
        return OrdinaryUrlMapping(
            true,
            "copyrightUrl",
            "WCOP"
        );
    }

    if (idEquals(id, "WOAF"))
    {
        return OrdinaryUrlMapping(
            true,
            "audioFileUrl",
            "WOAF"
        );
    }

    if (idEquals(id, "WOAR"))
    {
        return OrdinaryUrlMapping(
            true,
            "artistUrl",
            "WOAR"
        );
    }

    if (idEquals(id, "WOAS"))
    {
        return OrdinaryUrlMapping(
            true,
            "audioSourceUrl",
            "WOAS"
        );
    }

    if (idEquals(id, "WORS"))
    {
        return OrdinaryUrlMapping(
            true,
            "radioStationUrl",
            "WORS"
        );
    }

    if (idEquals(id, "WPAY"))
    {
        return OrdinaryUrlMapping(
            true,
            "paymentUrl",
            "WPAY"
        );
    }

    if (idEquals(id, "WPUB"))
    {
        return OrdinaryUrlMapping(
            true,
            "publisherUrl",
            "WPUB"
        );
    }

    return OrdinaryUrlMapping.init;
}


/++
Tests a fixed four-character frame identifier without allocating.
+/
private bool idEquals(
    const ref char[4] id,
    string expected
)
    @safe pure nothrow @nogc
{
    return
        expected.length == 4 &&
        id[0] == expected[0] &&
        id[1] == expected[1] &&
        id[2] == expected[2] &&
        id[3] == expected[3];
}


/++
Constructs one canonical URL field.
+/
private MetadataField makeUrlField(
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
            MetadataKey(canonicalKey),
            MetadataValue(
                MetadataUrl(url)
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

    assertRegisteredShape(field);

    return field;
}


/++
Constructs exact provenance for one mapped native URL frame.
+/
private MetadataProvenance makeProvenance(
    string nativeIdentifier,
    size_t sourceOffset,
    size_t sourceLength
)
    @safe pure nothrow @nogc
{
    return MetadataProvenance(
        NativeMetadataIdentifier(
            MetadataSystem.id3v2,
            nativeIdentifier
        ),
        sourceOffset,
        sourceLength,
        MetadataConfidence.exact
    );
}


/++
Checks the mapper/registry contract as a programmer invariant.
+/
private void assertRegisteredShape(
    MetadataField field
)
    @safe
{
    auto definition =
        findMetadataFieldDefinition(
            field.key
        );

    assert(definition.found);

    assert(
        definition.definition.accepts(
            field.value
        )
    );
}


/++
Creates one decoded ordinary URL frame for mapping tests.
+/
private Id3v24UrlLinkFrame testUrlFrame(
    string id,
    string url,
    size_t sourceOffset = 100
)
    @safe
{
    assert(id.length == 4);

    Id3v24UrlLinkFrame frame;

    frame.sourceOffset =
        sourceOffset;

    frame.id[] =
        id[];

    frame.url =
        url;

    return frame;
}


/// Every standardized ordinary URL frame keeps distinct semantics.
unittest
{
    struct Case
    {
        string id;
        string canonicalKey;
    }

    const cases =
        [
            Case("WCOM", "commercialUrl"),
            Case("WCOP", "copyrightUrl"),
            Case("WOAF", "audioFileUrl"),
            Case("WOAR", "artistUrl"),
            Case("WOAS", "audioSourceUrl"),
            Case("WORS", "radioStationUrl"),
            Case("WPAY", "paymentUrl"),
            Case("WPUB", "publisherUrl")
        ];

    foreach (entry; cases)
    {
        auto result =
            mapId3v24UrlLinkFrameToCanonical(
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
            result.field.provenance.length ==
            1
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

                _ => false
            );

        assert(matches);
    }
}


/// An unregistered ordinary W*** identifier is not collapsed generically.
unittest
{
    auto result =
        mapId3v24UrlLinkFrameToCanonical(
            testUrlFrame(
                "WZZZ",
                "https://example.invalid/"
            )
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .unsupportedFrame
    );
}


/// WXXX preserves its URL and user-defined description.
unittest
{
    Id3v24UserUrlFrame frame;

    frame.sourceOffset = 321;
    frame.description = "project";
    frame.url =
        "https://example.invalid/project";

    auto result =
        mapId3v24UserUrlFrameToCanonical(
            frame
        );

    assert(result.mapped);

    assert(
        result.field.key.name ==
        "userUrl"
    );

    assert(result.field.hasDescription);

    assert(
        result.field.description ==
        "project"
    );

    assert(
        result.field.provenance[0]
            .native.identifier ==
        "WXXX"
    );

    assert(
        result.field.provenance[0]
            .sourceOffset ==
        321
    );

    assert(
        result.field.provenance[0]
            .sourceLength ==
        0
    );

    const matches =
        result.field.value.match!(
            (MetadataUrl url) =>
                url.value ==
                    "https://example.invalid/project",

            _ => false
        );

    assert(matches);
}


/// Native ordinary URL mapping records the whole physical frame.
unittest
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        decodeId3v24NativeFrame;

    const ubyte[] bytes =
        [
            'W', 'C', 'O', 'M',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

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
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    auto native =
        decodeId3v24NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v24NativeUrlFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);

    assert(
        mapped.field.key.name ==
        "commercialUrl"
    );

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

    const matches =
        mapped.field.value.match!(
            (MetadataUrl url) =>
                url.value == "http://a",

            _ => false
        );

    assert(matches);
}


/// Native WXXX mapping records the whole frame and description.
unittest
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        decodeId3v24NativeFrame;

    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            0x03,
            's', 'i', 't', 'e', 0x00,
            'h', 't', 't', 'p',
            ':', '/', '/', 'a'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    auto native =
        decodeId3v24NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v24NativeUrlFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);

    assert(
        mapped.field.key.name ==
        "userUrl"
    );

    assert(
        mapped.field.description ==
        "site"
    );

    assert(
        mapped.field.provenance[0]
            .sourceOffset ==
        900
    );

    assert(
        mapped.field.provenance[0]
            .sourceLength ==
        bytes.length
    );

    const matches =
        mapped.field.value.match!(
            (MetadataUrl url) =>
                url.value == "http://a",

            _ => false
        );

    assert(matches);
}


/// Transformation-pending URL metadata remains valid native data.
unittest
{
    import audiotag.id3v2.v24.frame :
        Id3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrameContent;

    import audiotag.id3v2.v24.url_link :
        Id3v24UrlLinkAvailability;

    Id3v24UrlLinkOutcome outcome;

    outcome.availability =
        Id3v24UrlLinkAvailability
            .requiresDecompression;

    Id3v24NativeFrameContent content =
        outcome;

    auto native =
        Id3v24NativeFrame(
            Id3v24FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v24NativeUrlFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .requiresTransformation
    );
}


/// Other native frame families remain unsupported by the URL mapper.
unittest
{
    import audiotag.id3v2.v24.frame :
        Id3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrameContent,
        Id3v24UnknownFrame;

    Id3v24NativeFrameContent content =
        Id3v24UnknownFrame();

    auto native =
        Id3v24NativeFrame(
            Id3v24FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v24NativeUrlFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .unsupportedFrame
    );
}
