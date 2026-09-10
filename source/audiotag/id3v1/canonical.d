/++
Canonical projection of parsed ID3v1 metadata.

ID3v1 has a fixed native field layout. This module projects only semantics
whose representation is already stable in the format-independent metadata
registry:

- title;
- artist;
- album;
- comment;
- ID3v1.1 track number;
- recognized numeric genre.

The fixed year field remains available in the preserved native `Id3v1Tag` but
is intentionally not projected until canonical date semantics are defined.
Genre bytes not recognized by the shared ID3 compatibility registry likewise
remain available only in the native representation.

Unused NUL-padded text fields produce no canonical field. No whitespace or
other text normalization is performed.
+/
module audiotag.id3v1.canonical;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3.genre :
    findId3GenreByCode;

import audiotag.id3v1.tag :
    Id3v1Tag,
    parseId3v1Tag;

import audiotag.id3v1.text_decode :
    decodeId3v1Latin1Text,
    id3v1TextContent;

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

import audiotag.metadata.tree :
    MetadataTree;

import audiotag.metadata.value :
    MetadataPosition,
    MetadataText,
    MetadataTextList,
    MetadataValue;


/++
Native-plus-canonical representation of one parsed ID3v1 tag.

`native` retains the complete zero-copy structural tag representation.
`metadata` contains the currently supported canonical semantic view.
+/
struct Id3v1CanonicalTag
{
    /// Complete parsed native ID3v1 representation.
    Id3v1Tag native;

    /// Supported canonical metadata projected from the native fields.
    MetadataTree metadata;
}


/++
Projects one already parsed ID3v1 tag into canonical metadata.

Canonical fields are emitted in native field order among the semantics that
are currently representable:

1. title;
2. artist;
3. album;
4. comment;
5. ID3v1.1 track, when present;
6. recognized genre.

An ID3v1 artist is one native scalar string, while canonical `artist` is a
text list. Therefore a non-empty native artist becomes a one-element canonical
list; no separator heuristics are applied.

NUL-empty fixed-width fields are omitted. The preserved `native` member still
retains their complete source bytes.

Params:
    tag = Already parsed ID3v1.0 or ID3v1.1 tag.

Returns:
    The preserved native tag together with its supported canonical metadata.
+/
Id3v1CanonicalTag
projectId3v1TagToCanonical(
    Id3v1Tag tag
)
    @safe
{
    auto metadata =
        MetadataTree.init;

    appendScalarTextIfPresent(
        metadata,
        "title",
        tag.title
    );

    appendArtistIfPresent(
        metadata,
        tag.artist
    );

    appendScalarTextIfPresent(
        metadata,
        "album",
        tag.album
    );

    appendScalarTextIfPresent(
        metadata,
        "comment",
        tag.comment
    );

    appendTrackIfPresent(
        metadata,
        tag
    );

    appendGenreIfKnown(
        metadata,
        tag
    );

    return
        Id3v1CanonicalTag(
            tag,
            metadata
        );
}


/++
Strictly parses one exact ID3v1 block and projects its supported semantics.

Structural parse errors are returned unchanged. Canonical projection itself
does not introduce a second error domain.

Params:
    source = Exact bounded 128-byte ID3v1 candidate block.

Returns:
    A native-plus-canonical tag representation, or the structural ID3v1 parse
    error.
+/
ParseResult!Id3v1CanonicalTag
parseId3v1CanonicalTag(
    ByteSpan source
)
    @safe
{
    auto tagResult =
        parseId3v1Tag(source);

    if (tagResult.hasError)
    {
        return
            ParseResult!Id3v1CanonicalTag
                .failure(
                    tagResult.error
                );
    }

    return
        ParseResult!Id3v1CanonicalTag
            .success(
                projectId3v1TagToCanonical(
                    tagResult.value
                )
            );
}


/++
Appends one non-empty scalar ID3v1 text field.
+/
private void
appendScalarTextIfPresent(
    ref MetadataTree metadata,
    string canonicalKey,
    ByteSpan raw
)
    @safe
{
    if (
        id3v1TextContent(raw)
            .empty
    )
    {
        return;
    }

    auto field =
        MetadataField(
            MetadataKey(
                canonicalKey
            ),
            MetadataValue(
                MetadataText(
                    decodeId3v1Latin1Text(
                        raw
                    )
                )
            ),
            [
                makeProvenance(
                    canonicalKey,
                    raw
                )
            ]
        );

    assertRegisteredShape(
        field
    );

    metadata.append(
        field
    );
}


/++
Appends the non-empty native artist as one canonical list element.
+/
private void
appendArtistIfPresent(
    ref MetadataTree metadata,
    ByteSpan raw
)
    @safe
{
    if (
        id3v1TextContent(raw)
            .empty
    )
    {
        return;
    }

    auto field =
        MetadataField(
            MetadataKey(
                "artist"
            ),
            MetadataValue(
                MetadataTextList(
                    [
                        decodeId3v1Latin1Text(
                            raw
                        )
                    ]
                )
            ),
            [
                makeProvenance(
                    "artist",
                    raw
                )
            ]
        );

    assertRegisteredShape(
        field
    );

    metadata.append(
        field
    );
}


/++
Appends the ID3v1.1 track number when the structural parser recognized one.

The canonical position contains only a number because ID3v1.1 has no native
track-total field. Provenance covers exactly byte 126 of the 128-byte tag.
+/
private void
appendTrackIfPresent(
    ref MetadataTree metadata,
    Id3v1Tag tag
)
    @safe
{
    if (!tag.hasTrack)
    {
        return;
    }

    const rawTrack =
        tag.raw.subspan(
            126,
            1
        );

    auto field =
        MetadataField(
            MetadataKey(
                "track"
            ),
            MetadataValue(
                MetadataPosition.numberOnly(
                    tag.track
                )
            ),
            [
                makeProvenance(
                    "track",
                    rawTrack
                )
            ]
        );

    assertRegisteredShape(
        field
    );

    metadata.append(
        field
    );
}


/++
Appends a canonical genre when the raw ID3v1 genre byte is recognized.

The shared ID3 compatibility registry maps numeric genre codes to stable text
labels. Unassigned codes and the ID3v1 unknown/no-genre sentinel are preserved
only in the native tag and deliberately produce no canonical field.

Provenance covers exactly byte 127 of the 128-byte tag.
+/
private void
appendGenreIfKnown(
    ref MetadataTree metadata,
    Id3v1Tag tag
)
    @safe
{
    const lookup =
        findId3GenreByCode(
            tag.genre
        );

    if (!lookup.found)
    {
        return;
    }

    const rawGenre =
        tag.raw.subspan(
            127,
            1
        );

    auto field =
        MetadataField(
            MetadataKey(
                "genre"
            ),
            MetadataValue(
                MetadataTextList(
                    [
                        lookup.name
                    ]
                )
            ),
            [
                makeProvenance(
                    "genre",
                    rawGenre
                )
            ]
        );

    assertRegisteredShape(
        field
    );

    metadata.append(
        field
    );
}


/++
Constructs exact provenance for one fixed-width native ID3v1 field.
+/
private MetadataProvenance
makeProvenance(
    string nativeIdentifier,
    ByteSpan raw
)
    @safe pure nothrow @nogc
{
    return
        MetadataProvenance(
            NativeMetadataIdentifier(
                MetadataSystem.id3v1,
                nativeIdentifier
            ),
            raw.sourceOffset,
            raw.length,
            MetadataConfidence.exact
        );
}


/++
Checks the mapper/registry contract as a programmer invariant.
+/
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

    assert(
        definition.found
    );

    assert(
        definition.definition
            .accepts(
                field.value
            )
    );
}


version (unittest)
{
    import std.sumtype :
        match;

    private void
    setSignature(
        ref ubyte[128] bytes
    )
        @safe pure nothrow @nogc
    {
        bytes[0] = 'T';
        bytes[1] = 'A';
        bytes[2] = 'G';

        // Avoid an accidental code-0 ("Blues") genre in unrelated tests.
        bytes[127] = 255;
    }

    private void
    putText(
        ref ubyte[128] bytes,
        size_t offset,
        string value
    )
        @safe pure nothrow @nogc
    {
        assert(
            offset + value.length <=
            bytes.length
        );

        foreach (index, character; value)
        {
            bytes[offset + index] =
                cast(ubyte)
                    character;
        }
    }
}


/// Supported ID3v1.0 fields project in native order with exact provenance.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    putText(
        bytes,
        3,
        "Title"
    );

    putText(
        bytes,
        33,
        "Artist"
    );

    putText(
        bytes,
        63,
        "Album"
    );

    putText(
        bytes,
        93,
        "1999"
    );

    putText(
        bytes,
        97,
        "Comment"
    );

    bytes[127] = 13;

    auto result =
        parseId3v1CanonicalTag(
            ByteSpan(
                bytes[],
                1000
            )
        );

    assert(result.hasValue);

    const canonical =
        result.value;

    assert(canonical.metadata.length == 5);

    assert(
        canonical.metadata[0]
            .key.name ==
        "title"
    );

    assert(
        canonical.metadata[1]
            .key.name ==
        "artist"
    );

    assert(
        canonical.metadata[2]
            .key.name ==
        "album"
    );

    assert(
        canonical.metadata[3]
            .key.name ==
        "comment"
    );

    assert(
        canonical.metadata[4]
            .key.name ==
        "genre"
    );

    assert(
        canonical.metadata[0]
            .value.match!(
                (const(MetadataText) text) =>
                    text.value ==
                    "Title",
                _ => false
            )
    );

    assert(
        canonical.metadata[1]
            .value.match!(
                (const(MetadataTextList) list) =>
                    list.values ==
                    ["Artist"],
                _ => false
            )
    );

    assert(
        canonical.metadata[2]
            .value.match!(
                (const(MetadataText) text) =>
                    text.value ==
                    "Album",
                _ => false
            )
    );

    assert(
        canonical.metadata[3]
            .value.match!(
                (const(MetadataText) text) =>
                    text.value ==
                    "Comment",
                _ => false
            )
    );

    assert(
        canonical.metadata[4]
            .value.match!(
                (const(MetadataTextList) list) =>
                    list.values ==
                    ["Pop"],
                _ => false
            )
    );

    foreach (field; canonical.metadata.fields)
    {
        assert(field.provenance.length == 1);

        assert(
            field.provenance[0]
                .native.system ==
            MetadataSystem.id3v1
        );

        assert(
            field.provenance[0]
                .confidence ==
            MetadataConfidence.exact
        );
    }

    assert(
        canonical.metadata[0]
            .provenance[0]
            .sourceOffset ==
        1003
    );

    assert(
        canonical.metadata[0]
            .provenance[0]
            .sourceLength ==
        30
    );

    assert(
        canonical.metadata[3]
            .provenance[0]
            .sourceOffset ==
        1097
    );

    assert(
        canonical.metadata[3]
            .provenance[0]
            .sourceLength ==
        30
    );

    assert(
        canonical.metadata[4]
            .provenance[0]
            .native.identifier ==
        "genre"
    );

    assert(
        canonical.metadata[4]
            .provenance[0]
            .sourceOffset ==
        1127
    );

    assert(
        canonical.metadata[4]
            .provenance[0]
            .sourceLength ==
        1
    );
}


/// Empty fixed-width fields are absent from the canonical semantic view.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    putText(
        bytes,
        33,
        "Only Artist"
    );

    auto result =
        parseId3v1CanonicalTag(
            ByteSpan(bytes[])
        );

    assert(result.hasValue);

    const metadata =
        result.value.metadata;

    assert(metadata.length == 1);
    assert(
        metadata[0].key.name ==
        "artist"
    );
}


/// Latin-1 field decoding is reused by canonical projection.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[3] = 'A';
    bytes[4] = 0xE4;

    auto result =
        parseId3v1CanonicalTag(
            ByteSpan(bytes[])
        );

    assert(result.hasValue);

    assert(
        result.value.metadata[0]
            .value.match!(
                (const(MetadataText) text) =>
                    text.value ==
                    "A\u00E4",
                _ => false
            )
    );
}


/// ID3v1.1 track and recognized genre project while year remains native.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    putText(
        bytes,
        3,
        "Track"
    );

    putText(
        bytes,
        93,
        "2001"
    );

    bytes[125] = 0;
    bytes[126] = 7;
    bytes[127] = 17;

    auto result =
        parseId3v1CanonicalTag(
            ByteSpan(
                bytes[],
                2000
            )
        );

    assert(result.hasValue);

    const canonical =
        result.value;

    assert(canonical.native.hasTrack);
    assert(canonical.native.track == 7);
    assert(canonical.native.genre == 17);

    assert(
        decodeId3v1Latin1Text(
            canonical.native.year
        ) ==
        "2001"
    );

    assert(
        canonical.metadata.length ==
        3
    );

    assert(
        canonical.metadata.count(
            MetadataKey(
                "date"
            )
        ) ==
        0
    );

    assert(
        canonical.metadata.count(
            MetadataKey(
                "track"
            )
        ) ==
        1
    );

    assert(
        canonical.metadata[1]
            .key.name ==
        "track"
    );

    assert(
        canonical.metadata[1]
            .value.match!(
                (const(MetadataPosition) position) =>
                    position.hasNumber &&
                    position.number == 7 &&
                    !position.hasTotal,
                _ => false
            )
    );

    assert(
        canonical.metadata[1]
            .provenance.length ==
        1
    );

    assert(
        canonical.metadata[1]
            .provenance[0]
            .native.system ==
        MetadataSystem.id3v1
    );

    assert(
        canonical.metadata[1]
            .provenance[0]
            .native.identifier ==
        "track"
    );

    assert(
        canonical.metadata[1]
            .provenance[0]
            .sourceOffset ==
        2126
    );

    assert(
        canonical.metadata[1]
            .provenance[0]
            .sourceLength ==
        1
    );

    assert(
        canonical.metadata[1]
            .provenance[0]
            .confidence ==
        MetadataConfidence.exact
    );

    assert(
        canonical.metadata.count(
            MetadataKey(
                "genre"
            )
        ) ==
        1
    );

    assert(
        canonical.metadata[2]
            .key.name ==
        "genre"
    );

    assert(
        canonical.metadata[2]
            .value.match!(
                (const(MetadataTextList) list) =>
                    list.values ==
                    ["Rock"],
                _ => false
            )
    );

    assert(
        canonical.metadata[2]
            .provenance.length ==
        1
    );

    assert(
        canonical.metadata[2]
            .provenance[0]
            .native.system ==
        MetadataSystem.id3v1
    );

    assert(
        canonical.metadata[2]
            .provenance[0]
            .native.identifier ==
        "genre"
    );

    assert(
        canonical.metadata[2]
            .provenance[0]
            .sourceOffset ==
        2127
    );

    assert(
        canonical.metadata[2]
            .provenance[0]
            .sourceLength ==
        1
    );

    assert(
        canonical.metadata[2]
            .provenance[0]
            .confidence ==
        MetadataConfidence.exact
    );
}


/// Unassigned and sentinel genre bytes remain native-only without data loss.
unittest
{
    foreach (
        genreCode;
        [
            cast(ubyte) 192,
            cast(ubyte) 254,
            cast(ubyte) 255
        ]
    )
    {
        ubyte[128] bytes;

        setSignature(bytes);
        bytes[127] = genreCode;

        auto result =
            parseId3v1CanonicalTag(
                ByteSpan(
                    bytes[],
                    3000
                )
            );

        assert(result.hasValue);

        const canonical =
            result.value;

        assert(
            canonical.native.genre ==
            genreCode
        );

        assert(
            canonical.metadata.count(
                MetadataKey(
                    "genre"
                )
            ) ==
            0
        );
    }
}


/// Native raw spans remain zero-copy while canonical text is an owned snapshot.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);
    bytes[3] = 'A';

    auto result =
        parseId3v1CanonicalTag(
            ByteSpan(bytes[])
        );

    assert(result.hasValue);

    const canonical =
        result.value;

    assert(
        canonical.native.title
            .data[0] ==
        'A'
    );

    assert(
        canonical.metadata[0]
            .value.match!(
                (const(MetadataText) text) =>
                    text.value ==
                    "A",
                _ => false
            )
    );

    bytes[3] = 'B';

    assert(
        canonical.native.title
            .data[0] ==
        'B'
    );

    assert(
        canonical.metadata[0]
            .value.match!(
                (const(MetadataText) text) =>
                    text.value ==
                    "A",
                _ => false
            )
    );
}


/// Structural parse errors pass through the canonical convenience parser.
unittest
{
    ubyte[127] bytes;

    auto result =
        parseId3v1CanonicalTag(
            ByteSpan(
                bytes[],
                5000
            )
        );

    assert(result.hasError);
    assert(result.error.offset == 5000);
    assert(result.error.requested == 128);
    assert(result.error.available == 127);
}
