/++
Lossless canonical-field encoding for ID3v1.

This module maps one already selected canonical metadata field to the native
ID3v1 slot/value required by the fixed 128-byte tag serializer.

It deliberately does not decide whether a source field is preserved, replaced,
removed or newly introduced. Those edit-overlay decisions belong to the later
ID3v1 write planner.

Supported canonical targets:

- `title`       -> 30-byte ISO-8859-1 text;
- `artist`      -> one 30-byte ISO-8859-1 text value;
- `album`       -> 30-byte ISO-8859-1 text;
- `releaseDate` -> exactly one year-only value, formatted as four digits;
- `comment`     -> 30 bytes for ID3v1.0 or 28 bytes for ID3v1.1;
- `track`       -> one non-zero ID3v1.1 track byte;
- `genre`       -> one recognized shared-ID3 genre code.

The mapping is intentionally lossless. Canonical shapes that ID3v1 cannot
represent exactly are rejected rather than truncated, flattened or guessed.
+/
module audiotag.id3v1.canonical_write;

import std.sumtype :
    match;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3.genre :
    findId3GenreByName;

import audiotag.id3v1.tag :
    Id3v1Revision;

import audiotag.id3v1.text_encode :
    encodeId3v1Latin1Text;

import audiotag.metadata.field :
    MetadataField;

import audiotag.metadata.value :
    MetadataDateTimeList,
    MetadataPosition,
    MetadataText,
    MetadataTextList;


/++
Physical ID3v1 destination represented by one canonical field.
+/
enum Id3v1CanonicalWriteTarget : ubyte
{
    title,
    artist,
    album,
    year,
    comment,
    track,
    genre
}


/++
Native representation of one losslessly encoded canonical ID3v1 field.

For `title`, `artist`, `album`, `year` and `comment`, `bytes` contains the
complete fixed-width native field.

For `track` and `genre`, `scalar` contains the native one-byte value.
+/
struct Id3v1CanonicalFieldEncoding
{
    Id3v1CanonicalWriteTarget target;
    ubyte[] bytes;
    ubyte scalar;
}


private SerializationResult!(Id3v1CanonicalFieldEncoding)
unsupportedField(
    size_t index = 0
)
    @safe pure nothrow @nogc
{
    return
        SerializationResult!(Id3v1CanonicalFieldEncoding)
            .failure(
                SerializationError(
                    SerializationErrorCode
                        .unsupportedRepresentation,
                    index
                )
            );
}


private SerializationResult!(Id3v1CanonicalFieldEncoding)
encodeScalarText(
    Id3v1CanonicalWriteTarget target,
    const(MetadataField) field,
    size_t width
)
    @safe
{
    return
        field.value.match!(
            (const(MetadataText) text)
            {
                if (text.value.length == 0)
                    return unsupportedField();

                auto encoded =
                    encodeId3v1Latin1Text(
                        text.value,
                        width
                    );

                if (encoded.hasError)
                {
                    return
                        SerializationResult!(
                            Id3v1CanonicalFieldEncoding
                        ).failure(
                            encoded.error
                        );
                }

                return
                    SerializationResult!(
                        Id3v1CanonicalFieldEncoding
                    ).success(
                        Id3v1CanonicalFieldEncoding(
                            target,
                            encoded.value.dup,
                            0
                        )
                    );
            },

            _ =>
                unsupportedField()
        );
}


private SerializationResult!(Id3v1CanonicalFieldEncoding)
encodeArtist(
    const(MetadataField) field
)
    @safe
{
    return
        field.value.match!(
            (const(MetadataTextList) list)
            {
                if (
                    list.values.length != 1 ||
                    list.values[0].length == 0
                )
                {
                    return unsupportedField();
                }

                auto encoded =
                    encodeId3v1Latin1Text(
                        list.values[0],
                        30
                    );

                if (encoded.hasError)
                {
                    return
                        SerializationResult!(
                            Id3v1CanonicalFieldEncoding
                        ).failure(
                            encoded.error
                        );
                }

                return
                    SerializationResult!(
                        Id3v1CanonicalFieldEncoding
                    ).success(
                        Id3v1CanonicalFieldEncoding(
                            Id3v1CanonicalWriteTarget.artist,
                            encoded.value.dup,
                            0
                        )
                    );
            },

            _ =>
                unsupportedField()
        );
}


private SerializationResult!(Id3v1CanonicalFieldEncoding)
encodeReleaseDate(
    const(MetadataField) field
)
    @safe
{
    return
        field.value.match!(
            (const(MetadataDateTimeList) list)
            {
                if (list.values.length != 1)
                    return unsupportedField();

                const value =
                    list.values[0];

                if (
                    !value.hasYear ||
                    value.hasMonth ||
                    value.hasDay ||
                    value.hasHour ||
                    value.hasMinute ||
                    value.hasSecond ||
                    value.hasFractionalSecond ||
                    value.hasUtcOffset
                )
                {
                    return unsupportedField();
                }

                if (
                    value.year < 0 ||
                    value.year > 9999
                )
                {
                    return
                        SerializationResult!(
                            Id3v1CanonicalFieldEncoding
                        ).failure(
                            SerializationError(
                                SerializationErrorCode
                                    .valueOutOfRange,
                                0,
                                value.year < 0
                                    ? 0
                                    : cast(ulong)
                                        value.year,
                                9999
                            )
                        );
                }

                const year =
                    cast(uint)
                        value.year;

                auto bytes =
                    new ubyte[4];

                bytes[0] =
                    cast(ubyte)
                        ('0' + (year / 1000) % 10);

                bytes[1] =
                    cast(ubyte)
                        ('0' + (year / 100) % 10);

                bytes[2] =
                    cast(ubyte)
                        ('0' + (year / 10) % 10);

                bytes[3] =
                    cast(ubyte)
                        ('0' + year % 10);

                return
                    SerializationResult!(
                        Id3v1CanonicalFieldEncoding
                    ).success(
                        Id3v1CanonicalFieldEncoding(
                            Id3v1CanonicalWriteTarget.year,
                            bytes,
                            0
                        )
                    );
            },

            _ =>
                unsupportedField()
        );
}


private SerializationResult!(Id3v1CanonicalFieldEncoding)
encodeTrack(
    const(MetadataField) field
)
    @safe
{
    return
        field.value.match!(
            (const(MetadataPosition) position)
            {
                if (
                    !position.hasNumber ||
                    position.hasTotal
                )
                {
                    return unsupportedField();
                }

                if (
                    position.number == 0 ||
                    position.number > 255
                )
                {
                    return
                        SerializationResult!(
                            Id3v1CanonicalFieldEncoding
                        ).failure(
                            SerializationError(
                                SerializationErrorCode
                                    .valueOutOfRange,
                                0,
                                position.number,
                                255
                            )
                        );
                }

                return
                    SerializationResult!(
                        Id3v1CanonicalFieldEncoding
                    ).success(
                        Id3v1CanonicalFieldEncoding(
                            Id3v1CanonicalWriteTarget.track,
                            [],
                            cast(ubyte)
                                position.number
                        )
                    );
            },

            _ =>
                unsupportedField()
        );
}


private SerializationResult!(Id3v1CanonicalFieldEncoding)
encodeGenre(
    const(MetadataField) field
)
    @safe
{
    return
        field.value.match!(
            (const(MetadataTextList) list)
            {
                if (list.values.length != 1)
                    return unsupportedField();

                const lookup =
                    findId3GenreByName(
                        list.values[0]
                    );

                if (!lookup.found)
                    return unsupportedField();

                return
                    SerializationResult!(
                        Id3v1CanonicalFieldEncoding
                    ).success(
                        Id3v1CanonicalFieldEncoding(
                            Id3v1CanonicalWriteTarget.genre,
                            [],
                            lookup.code
                        )
                    );
            },

            _ =>
                unsupportedField()
        );
}


/++
Losslessly maps one canonical metadata field to an ID3v1 native target.

Language, description and qualifiers are rejected for every target because
ID3v1 has nowhere to store them. Provenance does not affect encoding.

`revision` matters only for comment width:

- ID3v1.0 -> 30 bytes;
- ID3v1.1 -> 28 bytes.

A canonical `track` always maps to the ID3v1.1 track slot. The later edit
planner is responsible for upgrading a source v1.0 layout when such a field is
introduced and for downgrading when the last track is removed.

Unknown canonical keys and unsupported value shapes return
`unsupportedRepresentation`.
+/
SerializationResult!(Id3v1CanonicalFieldEncoding)
encodeId3v1CanonicalField(
    const(MetadataField) field,
    Id3v1Revision revision
)
    @safe
{
    if (
        field.hasLanguage ||
        field.hasDescription ||
        field.hasQualifiers
    )
    {
        return unsupportedField();
    }

    if (field.key.name == "title")
    {
        return
            encodeScalarText(
                Id3v1CanonicalWriteTarget.title,
                field,
                30
            );
    }

    if (field.key.name == "artist")
        return encodeArtist(field);

    if (field.key.name == "album")
    {
        return
            encodeScalarText(
                Id3v1CanonicalWriteTarget.album,
                field,
                30
            );
    }

    if (field.key.name == "releaseDate")
        return encodeReleaseDate(field);

    if (field.key.name == "comment")
    {
        size_t width;

        switch (revision)
        {
            case Id3v1Revision.v10:
                width = 30;
                break;

            case Id3v1Revision.v11:
                width = 28;
                break;

            default:
                return
                    SerializationResult!(
                        Id3v1CanonicalFieldEncoding
                    ).failure(
                        SerializationError(
                            SerializationErrorCode.invalidValue,
                            0,
                            cast(ulong)
                                revision
                        )
                    );
        }

        return
            encodeScalarText(
                Id3v1CanonicalWriteTarget.comment,
                field,
                width
            );
    }

    if (field.key.name == "track")
        return encodeTrack(field);

    if (field.key.name == "genre")
        return encodeGenre(field);

    return unsupportedField();
}


version (unittest)
{
    import audiotag.metadata.field :
        MetadataKey;

    import audiotag.metadata.value :
        MetadataDateTime,
        MetadataValue;


    private MetadataField
    field(
        string key,
        MetadataValue value
    )
        @safe
    {
        return
            MetadataField(
                MetadataKey(key),
                value
            );
    }
}


/// Scalar text targets use strict fixed-width Latin-1 encoding.
unittest
{
    MetadataValue value =
        MetadataText(
            "T\u00E4st"
        );

    auto encoded =
        encodeId3v1CanonicalField(
            field("title", value),
            Id3v1Revision.v10
        );

    assert(encoded.hasValue);

    assert(
        encoded.value.target ==
        Id3v1CanonicalWriteTarget.title
    );

    assert(encoded.value.bytes.length == 30);
    assert(encoded.value.bytes[0] == 'T');
    assert(encoded.value.bytes[1] == 0xE4);
    assert(encoded.value.bytes[4] == 0);
}


/// Artist must remain exactly one semantic value.
unittest
{
    MetadataValue single =
        MetadataTextList(
            ["Artist"]
        );

    auto encoded =
        encodeId3v1CanonicalField(
            field("artist", single),
            Id3v1Revision.v10
        );

    assert(encoded.hasValue);
    assert(encoded.value.bytes.length == 30);

    MetadataValue multiple =
        MetadataTextList(
            ["A", "B"]
        );

    auto rejected =
        encodeId3v1CanonicalField(
            field("artist", multiple),
            Id3v1Revision.v10
        );

    assert(rejected.hasError);

    assert(
        rejected.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Release date requires one year-only value and preserves year zero.
unittest
{
    MetadataValue yearZero =
        MetadataDateTimeList(
            [
                MetadataDateTime.yearOnly(0)
            ]
        );

    auto encoded =
        encodeId3v1CanonicalField(
            field("releaseDate", yearZero),
            Id3v1Revision.v10
        );

    assert(encoded.hasValue);

    assert(
        encoded.value.bytes ==
        cast(const(ubyte)[])
            "0000"
    );

    MetadataValue tooPrecise =
        MetadataDateTimeList(
            [
                MetadataDateTime.calendarDate(
                    2001,
                    6,
                    12
                )
            ]
        );

    auto rejected =
        encodeId3v1CanonicalField(
            field("releaseDate", tooPrecise),
            Id3v1Revision.v10
        );

    assert(rejected.hasError);

    assert(
        rejected.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Release years outside the four-digit native domain are rejected.
unittest
{
    MetadataValue tooLarge =
        MetadataDateTimeList(
            [
                MetadataDateTime.yearOnly(
                    10_000
                )
            ]
        );

    auto result =
        encodeId3v1CanonicalField(
            field("releaseDate", tooLarge),
            Id3v1Revision.v10
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.valueOutOfRange
    );

    assert(result.error.limit == 9999);
}


/// Comment capacity follows the selected ID3v1 revision.
unittest
{
    MetadataValue value =
        MetadataText(
            "12345678901234567890123456789"
        );

    auto v10 =
        encodeId3v1CanonicalField(
            field("comment", value),
            Id3v1Revision.v10
        );

    assert(v10.hasValue);
    assert(v10.value.bytes.length == 30);

    auto v11 =
        encodeId3v1CanonicalField(
            field("comment", value),
            Id3v1Revision.v11
        );

    assert(v11.hasError);

    assert(
        v11.error.code ==
        SerializationErrorCode.invalidLength
    );
}


/// Track is exactly one non-zero byte with no total component.
unittest
{
    MetadataValue value =
        MetadataPosition.numberOnly(
            255
        );

    auto encoded =
        encodeId3v1CanonicalField(
            field("track", value),
            Id3v1Revision.v11
        );

    assert(encoded.hasValue);

    assert(
        encoded.value.target ==
        Id3v1CanonicalWriteTarget.track
    );

    assert(encoded.value.scalar == 255);

    MetadataValue zero =
        MetadataPosition.numberOnly(
            0
        );

    auto zeroRejected =
        encodeId3v1CanonicalField(
            field("track", zero),
            Id3v1Revision.v11
        );

    assert(zeroRejected.hasError);

    MetadataValue withTotal =
        MetadataPosition.numberAndTotal(
            3,
            12
        );

    auto totalRejected =
        encodeId3v1CanonicalField(
            field("track", withTotal),
            Id3v1Revision.v11
        );

    assert(totalRejected.hasError);

    assert(
        totalRejected.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Genre reverse lookup is exact and produces the shared numeric code.
unittest
{
    MetadataValue value =
        MetadataTextList(
            ["Rock"]
        );

    auto encoded =
        encodeId3v1CanonicalField(
            field("genre", value),
            Id3v1Revision.v10
        );

    assert(encoded.hasValue);

    assert(
        encoded.value.target ==
        Id3v1CanonicalWriteTarget.genre
    );

    assert(encoded.value.scalar == 17);

    MetadataValue freeForm =
        MetadataTextList(
            ["Not a registered ID3 genre"]
        );

    auto rejected =
        encodeId3v1CanonicalField(
            field("genre", freeForm),
            Id3v1Revision.v10
        );

    assert(rejected.hasError);

    assert(
        rejected.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Empty semantic text and target-specific context cannot roundtrip exactly.
unittest
{
    MetadataValue emptyText =
        MetadataText("");

    auto empty =
        encodeId3v1CanonicalField(
            field("title", emptyText),
            Id3v1Revision.v10
        );

    assert(empty.hasError);

    MetadataValue contextualValue =
        MetadataText("Title");

    auto contextual =
        field(
            "title",
            contextualValue
        );

    contextual.description =
        "alternate";

    auto rejected =
        encodeId3v1CanonicalField(
            contextual,
            Id3v1Revision.v10
        );

    assert(rejected.hasError);

    assert(
        rejected.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Unknown canonical keys are not guessed into ID3v1 slots.
unittest
{
    MetadataValue value =
        MetadataText(
            "value"
        );

    auto result =
        encodeId3v1CanonicalField(
            field("futureSemantic", value),
            Id3v1Revision.v10
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
