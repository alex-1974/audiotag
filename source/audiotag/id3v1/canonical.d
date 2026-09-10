/++
Canonical projection of parsed ID3v1 metadata.

ID3v1 has a fixed native field layout. This module projects only semantics
whose representation is already stable in the format-independent metadata
registry:

- title;
- artist;
- album;
- four-digit release year;
- comment;
- ID3v1.1 track number;
- recognized numeric genre.

The fixed year field is projected only when all four native bytes are ASCII
decimal digits. Other year spellings remain available only in the preserved
native `Id3v1Tag`. Genre bytes not recognized by the shared ID3 compatibility
registry likewise
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
    MetadataDateTime,
    MetadataDateTimeList,
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
4. release year, when the native year is four decimal digits;
5. comment;
6. ID3v1.1 track, when present;
7. recognized genre.

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

    appendReleaseYearIfValid(
        metadata,
        tag.year
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
Appends the fixed-width ID3v1 year as a canonical release date when valid.

ID3v1 provides exactly four bytes for its year field. Canonical projection is
deliberately conservative: all four bytes must be ASCII decimal digits. No
whitespace trimming, Latin-1 conversion, date inference or range restriction
is applied.

The resulting canonical value contains only a year. ID3v1 supplies no timezone
semantics, so no UTC offset is invented. Provenance covers exactly the four
native year bytes.
+/
private void
appendReleaseYearIfValid(
    ref MetadataTree metadata,
    ByteSpan raw
)
    @safe
{
    ushort year;

    if (!parseId3v1Year(raw, year))
        return;

    auto field =
        MetadataField(
            MetadataKey(
                "releaseDate"
            ),
            MetadataValue(
                MetadataDateTimeList(
                    [
                        MetadataDateTime.yearOnly(
                            year
                        )
                    ]
                )
            ),
            [
                makeProvenance(
                    "year",
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
Parses an exact four-byte ASCII decimal ID3v1 year.
+/
private bool
parseId3v1Year(
    ByteSpan raw,
    out ushort year
)
    @safe pure nothrow @nogc
{
    if (raw.length != 4)
        return false;

    uint value;

    foreach (byteValue; raw.data)
    {
        if (
            byteValue < '0' ||
            byteValue > '9'
        )
        {
            return false;
        }

        value =
            value * 10 +
            cast(uint)
                (byteValue - '0');
    }

    year =
        cast(ushort)
            value;

    return true;
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

    assert(canonical.metadata.length == 6);

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
        "releaseDate"
    );

    assert(
        canonical.metadata[4]
            .key.name ==
        "comment"
    );

    assert(
        canonical.metadata[5]
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
                (const(MetadataDateTimeList) list) =>
                    list.values.length == 1 &&
                    list.values[0].hasYear &&
                    list.values[0].year == 1999 &&
                    !list.values[0].hasMonth &&
                    !list.values[0].hasTime &&
                    !list.values[0].hasUtcOffset,
                _ => false
            )
    );

    assert(
        canonical.metadata[4]
            .value.match!(
                (const(MetadataText) text) =>
                    text.value ==
                    "Comment",
                _ => false
            )
    );

    assert(
        canonical.metadata[5]
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
            .native.identifier ==
        "year"
    );

    assert(
        canonical.metadata[3]
            .provenance[0]
            .sourceOffset ==
        1093
    );

    assert(
        canonical.metadata[3]
            .provenance[0]
            .sourceLength ==
        4
    );

    assert(
        canonical.metadata[4]
            .provenance[0]
            .sourceOffset ==
        1097
    );

    assert(
        canonical.metadata[4]
            .provenance[0]
            .sourceLength ==
        30
    );

    assert(
        canonical.metadata[5]
            .provenance[0]
            .native.identifier ==
        "genre"
    );

    assert(
        canonical.metadata[5]
            .provenance[0]
            .sourceOffset ==
        1127
    );

    assert(
        canonical.metadata[5]
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


/// ID3v1.1 release year, track and recognized genre project canonically.
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
        4
    );

    assert(
        canonical.metadata.count(
            MetadataKey(
                "releaseDate"
            )
        ) ==
        1
    );

    assert(
        canonical.metadata[1]
            .key.name ==
        "releaseDate"
    );

    assert(
        canonical.metadata[1]
            .value.match!(
                (const(MetadataDateTimeList) list) =>
                    list.values.length == 1 &&
                    list.values[0].hasYear &&
                    list.values[0].year == 2001 &&
                    !list.values[0].hasUtcOffset,
                _ => false
            )
    );

    assert(
        canonical.metadata[1]
            .provenance[0]
            .native.identifier ==
        "year"
    );

    assert(
        canonical.metadata[1]
            .provenance[0]
            .sourceOffset ==
        2093
    );

    assert(
        canonical.metadata[1]
            .provenance[0]
            .sourceLength ==
        4
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
        canonical.metadata[2]
            .key.name ==
        "track"
    );

    assert(
        canonical.metadata[2]
            .value.match!(
                (const(MetadataPosition) position) =>
                    position.hasNumber &&
                    position.number == 7 &&
                    !position.hasTotal,
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
        "track"
    );

    assert(
        canonical.metadata[2]
            .provenance[0]
            .sourceOffset ==
        2126
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

    assert(
        canonical.metadata.count(
            MetadataKey(
                "genre"
            )
        ) ==
        1
    );

    assert(
        canonical.metadata[3]
            .key.name ==
        "genre"
    );

    assert(
        canonical.metadata[3]
            .value.match!(
                (const(MetadataTextList) list) =>
                    list.values ==
                    ["Rock"],
                _ => false
            )
    );

    assert(
        canonical.metadata[3]
            .provenance.length ==
        1
    );

    assert(
        canonical.metadata[3]
            .provenance[0]
            .native.system ==
        MetadataSystem.id3v1
    );

    assert(
        canonical.metadata[3]
            .provenance[0]
            .native.identifier ==
        "genre"
    );

    assert(
        canonical.metadata[3]
            .provenance[0]
            .sourceOffset ==
        2127
    );

    assert(
        canonical.metadata[3]
            .provenance[0]
            .sourceLength ==
        1
    );

    assert(
        canonical.metadata[3]
            .provenance[0]
            .confidence ==
        MetadataConfidence.exact
    );
}



/// Non-decimal ID3v1 year bytes remain native-only.
unittest
{
    foreach (
        invalidYear;
        [
            "20A1",
            " 200",
            "200 "
        ]
    )
    {
        ubyte[128] bytes;

        setSignature(bytes);

        putText(
            bytes,
            93,
            invalidYear
        );

        auto result =
            parseId3v1CanonicalTag(
                ByteSpan(
                    bytes[]
                )
            );

        assert(result.hasValue);

        assert(
            result.value.metadata.count(
                MetadataKey(
                    "releaseDate"
                )
            ) ==
            0
        );

        assert(
            decodeId3v1Latin1Text(
                result.value.native.year
            ) ==
            invalidYear
        );
    }

    ubyte[128] nulYear;
    setSignature(nulYear);

    auto result =
        parseId3v1CanonicalTag(
            ByteSpan(
                nulYear[]
            )
        );

    assert(result.hasValue);

    assert(
        result.value.metadata.count(
            MetadataKey(
                "releaseDate"
            )
        ) ==
        0
    );
}


/// Four decimal zeroes remain an explicit year rather than an absence sentinel.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    putText(
        bytes,
        93,
        "0000"
    );

    auto result =
        parseId3v1CanonicalTag(
            ByteSpan(
                bytes[]
            )
        );

    assert(result.hasValue);

    assert(
        result.value.metadata.count(
            MetadataKey(
                "releaseDate"
            )
        ) ==
        1
    );

    assert(
        result.value.metadata[0]
            .value.match!(
                (const(MetadataDateTimeList) list) =>
                    list.values.length == 1 &&
                    list.values[0].hasYear &&
                    list.values[0].year == 0 &&
                    !list.values[0].hasUtcOffset,
                _ => false
            )
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
