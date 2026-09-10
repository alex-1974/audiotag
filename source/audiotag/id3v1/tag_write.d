/++
Deterministic physical serialization of fixed-size ID3v1 tags.

This module writes one already bound native ID3v1 field set into the exact
128-byte tag layout. Text encoding and canonical metadata interpretation are
deliberately separate concerns.

Keeping this layer native is important for later canonical writeback: an
existing tag may contain native-only information, such as an unrecognized
genre byte or a non-canonical four-byte year spelling. A higher-level planner
can begin with `Id3v1NativeTagWriteFields.fromTag`, replace only fields affected
by a canonical edit, and preserve all other native bytes exactly.

Layout:

    0..2      "TAG"
    3..32     title   (30 bytes)
    33..62    artist  (30 bytes)
    63..92    album   (30 bytes)
    93..96    year    (4 bytes)
    97..126   comment (30 bytes, ID3v1.0)

or for ID3v1.1:

    97..124   comment (28 bytes)
    125       zero marker
    126       non-zero track number

    127       genre byte

No MP3/container placement is handled here.
+/
module audiotag.id3v1.tag_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v1.tag :
    Id3v1Revision,
    Id3v1Tag,
    id3v1TagSize;


/++
Already encoded native fields required to serialize one ID3v1 tag.

Text-like fields contain exact native bytes, not Unicode text. Their required
lengths are validated by `serializeId3v1NativeTag`.

`genre` is deliberately an unconstrained raw byte. This allows exact
preservation of unknown/unassigned source values. Canonical genre-name
validation belongs to the higher-level canonical write planner.

For ID3v1.0 `track` must be zero and `comment` must contain 30 bytes.
For ID3v1.1 `track` must be non-zero and `comment` must contain 28 bytes.
+/
struct Id3v1NativeTagWriteFields
{
    Id3v1Revision revision;

    const(ubyte)[] title;
    const(ubyte)[] artist;
    const(ubyte)[] album;
    const(ubyte)[] year;
    const(ubyte)[] comment;

    ubyte track;
    ubyte genre;


    /++
    Binds an existing parsed tag for exact native reserialization.

    All slices remain zero-copy views into the parsed tag's source storage.
    No decoding, normalization or allocation occurs.
    +/
    static Id3v1NativeTagWriteFields
    fromTag(
        Id3v1Tag tag
    )
        @safe pure nothrow @nogc
    {
        return
            Id3v1NativeTagWriteFields(
                tag.revision,
                tag.title.data,
                tag.artist.data,
                tag.album.data,
                tag.year.data,
                tag.comment.data,
                tag.track,
                tag.genre
            );
    }
}


private SerializationResult!(ubyte[])
invalidFieldLength(
    size_t destinationOffset,
    size_t actual,
    size_t expected
)
    @safe pure nothrow @nogc
{
    return
        SerializationResult!(ubyte[])
            .failure(
                SerializationError(
                    SerializationErrorCode.invalidLength,
                    destinationOffset,
                    actual,
                    expected
                )
            );
}


private void
copyField(
    ref ubyte[] output,
    size_t destinationOffset,
    const(ubyte)[] source
)
    @safe pure nothrow @nogc
{
    assert(
        destinationOffset + source.length <=
        output.length
    );

    output[
        destinationOffset ..
        destinationOffset + source.length
    ] =
        source[];
}


/++
Serializes one exact native ID3v1.0 or ID3v1.1 field set.

The function never truncates, pads, decodes or otherwise interprets the
supplied native field slices. Their lengths must already match the physical
layout exactly.

Revision-specific invariants:

- ID3v1.0 requires 30 comment bytes and `track == 0`;
- ID3v1.1 requires 28 comment bytes and `track != 0`;
- the v1.1 zero marker at byte 125 is always emitted by this serializer.

The genre byte is copied verbatim, including unassigned values and 255.

Returns:
    Exactly 128 serialized bytes, or a structured serialization error.
+/
SerializationResult!(ubyte[])
serializeId3v1NativeTag(
    const(Id3v1NativeTagWriteFields) fields
)
    @safe
{
    if (fields.title.length != 30)
        return invalidFieldLength(3, fields.title.length, 30);

    if (fields.artist.length != 30)
        return invalidFieldLength(33, fields.artist.length, 30);

    if (fields.album.length != 30)
        return invalidFieldLength(63, fields.album.length, 30);

    if (fields.year.length != 4)
        return invalidFieldLength(93, fields.year.length, 4);

    size_t commentLength;

    switch (fields.revision)
    {
        case Id3v1Revision.v10:
            commentLength = 30;

            if (fields.track != 0)
            {
                return
                    SerializationResult!(ubyte[])
                        .failure(
                            SerializationError(
                                SerializationErrorCode
                                    .inconsistentStructure,
                                126,
                                fields.track,
                                0
                            )
                        );
            }

            break;

        case Id3v1Revision.v11:
            commentLength = 28;

            if (fields.track == 0)
            {
                return
                    SerializationResult!(ubyte[])
                        .failure(
                            SerializationError(
                                SerializationErrorCode
                                    .invalidValue,
                                126,
                                0,
                                255
                            )
                        );
            }

            break;

        default:
            return
                SerializationResult!(ubyte[])
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .invalidValue,
                            0,
                            cast(ulong)
                                fields.revision
                        )
                    );
    }

    if (fields.comment.length != commentLength)
    {
        return
            invalidFieldLength(
                97,
                fields.comment.length,
                commentLength
            );
    }

    auto output =
        new ubyte[id3v1TagSize];

    output[0] = 'T';
    output[1] = 'A';
    output[2] = 'G';

    copyField(output, 3, fields.title);
    copyField(output, 33, fields.artist);
    copyField(output, 63, fields.album);
    copyField(output, 93, fields.year);
    copyField(output, 97, fields.comment);

    if (fields.revision == Id3v1Revision.v11)
    {
        output[125] = 0;
        output[126] = fields.track;
    }

    output[127] =
        fields.genre;

    return
        SerializationResult!(ubyte[])
            .success(output);
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v1.tag :
        parseId3v1Tag;


    private void
    setSignature(
        ref ubyte[128] bytes
    )
        @safe pure nothrow @nogc
    {
        bytes[0] = 'T';
        bytes[1] = 'A';
        bytes[2] = 'G';
    }
}


/// Parsed ID3v1.0 data can be serialized byte-for-byte, including native-only bytes.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[3] = 0xC4;
    bytes[32] = 'X';

    bytes[33] = 'A';
    bytes[62] = 'B';

    bytes[63] = 'L';
    bytes[92] = 'M';

    /*
     * Deliberately non-canonical year text. A canonical projection should not
     * manufacture semantics for it, but native preservation must keep it.
     */
    bytes[93] = '2';
    bytes[94] = '0';
    bytes[95] = 'X';
    bytes[96] = '6';

    bytes[97] = 'C';

    /*
     * Ensure the v1.1 marker condition is false while preserving arbitrary
     * source bytes in the v1.0 comment region.
     */
    bytes[125] = 'Q';
    bytes[126] = 'R';

    /*
     * Unassigned by the shared canonical genre registry.
     */
    bytes[127] = 250;

    auto parsed =
        parseId3v1Tag(
            ByteSpan(bytes[])
        );

    assert(parsed.hasValue);
    assert(parsed.value.revision == Id3v1Revision.v10);

    const fields =
        Id3v1NativeTagWriteFields.fromTag(
            parsed.value
        );

    auto serialized =
        serializeId3v1NativeTag(
            fields
        );

    assert(serialized.hasValue);
    assert(serialized.value.length == 128);
    assert(serialized.value == bytes[]);
}


/// Parsed ID3v1.1 data roundtrips exactly through native write fields.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[3] = 'T';
    bytes[33] = 'A';
    bytes[63] = 'L';

    bytes[93] = '1';
    bytes[94] = '9';
    bytes[95] = '9';
    bytes[96] = '9';

    bytes[97] = 'C';
    bytes[124] = 'Z';

    bytes[125] = 0;
    bytes[126] = 7;
    bytes[127] = 17;

    auto parsed =
        parseId3v1Tag(
            ByteSpan(bytes[])
        );

    assert(parsed.hasValue);
    assert(parsed.value.revision == Id3v1Revision.v11);

    auto serialized =
        serializeId3v1NativeTag(
            Id3v1NativeTagWriteFields.fromTag(
                parsed.value
            )
        );

    assert(serialized.hasValue);
    assert(serialized.value == bytes[]);
}


/// Explicit v1.1 fields emit the zero marker and non-zero track byte.
unittest
{
    ubyte[30] title;
    ubyte[30] artist;
    ubyte[30] album;
    ubyte[4] year;
    ubyte[28] comment;

    title[0] = 'T';
    artist[0] = 'A';
    album[0] = 'L';
    year[] = ['2', '0', '0', '1'];
    comment[0] = 'C';

    const fields =
        Id3v1NativeTagWriteFields(
            Id3v1Revision.v11,
            title[],
            artist[],
            album[],
            year[],
            comment[],
            42,
            13
        );

    auto serialized =
        serializeId3v1NativeTag(
            fields
        );

    assert(serialized.hasValue);
    assert(serialized.value.length == 128);

    assert(
        serialized.value[0 .. 3] ==
        cast(const(ubyte)[])
            "TAG"
    );

    assert(serialized.value[3] == 'T');
    assert(serialized.value[33] == 'A');
    assert(serialized.value[63] == 'L');

    assert(
        serialized.value[93 .. 97] ==
        cast(const(ubyte)[])
            "2001"
    );

    assert(serialized.value[97] == 'C');
    assert(serialized.value[125] == 0);
    assert(serialized.value[126] == 42);
    assert(serialized.value[127] == 13);

    auto parsed =
        parseId3v1Tag(
            ByteSpan(
                serialized.value
            )
        );

    assert(parsed.hasValue);
    assert(parsed.value.revision == Id3v1Revision.v11);
    assert(parsed.value.track == 42);
    assert(parsed.value.genre == 13);
}


/// Every fixed native field length is validated rather than truncated or padded.
unittest
{
    ubyte[29] shortTitle;
    ubyte[30] artist;
    ubyte[30] album;
    ubyte[4] year;
    ubyte[30] comment;

    const fields =
        Id3v1NativeTagWriteFields(
            Id3v1Revision.v10,
            shortTitle[],
            artist[],
            album[],
            year[],
            comment[],
            0,
            255
        );

    auto result =
        serializeId3v1NativeTag(
            fields
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidLength
    );

    assert(result.error.index == 3);
    assert(result.error.value == 29);
    assert(result.error.limit == 30);
}


/// Revision and track semantics cannot contradict the parser's detection rule.
unittest
{
    ubyte[30] title;
    ubyte[30] artist;
    ubyte[30] album;
    ubyte[4] year;
    ubyte[30] comment10;
    ubyte[28] comment11;

    auto v10 =
        serializeId3v1NativeTag(
            Id3v1NativeTagWriteFields(
                Id3v1Revision.v10,
                title[],
                artist[],
                album[],
                year[],
                comment10[],
                1,
                255
            )
        );

    assert(v10.hasError);

    assert(
        v10.error.code ==
        SerializationErrorCode.inconsistentStructure
    );

    auto v11 =
        serializeId3v1NativeTag(
            Id3v1NativeTagWriteFields(
                Id3v1Revision.v11,
                title[],
                artist[],
                album[],
                year[],
                comment11[],
                0,
                255
            )
        );

    assert(v11.hasError);

    assert(
        v11.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(v11.error.index == 126);
}
