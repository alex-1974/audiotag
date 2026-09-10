/++
High-level in-memory API for updating edge metadata in an MP3 byte source.

This module composes the existing MP3 edge stages for:

- prepended ID3v2.3/ID3v2.4 insertion, replacement and removal;
- trailing ID3v1 insertion, replacement and removal.

Supplied replacement bytes are already serialized tag blocks. No ID3
semantic serialization is performed here and no file or other external I/O
takes place.
+/
module audiotag.mp3.api;

import audiotag.core.result :
    ParseResult;

import audiotag.core.serialization :
    SerializationErrorCode,
    SerializationResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.mp3.prefix :
    parseMp3Prefix;

import audiotag.mp3.prefix_write :
    Mp3LeadingId3v2WriteResult,
    materializeMp3LeadingId3v2Write;

import audiotag.mp3.prefix_write_plan :
    planMp3LeadingId3v2Write;

import audiotag.mp3.suffix :
    locateMp3TrailingId3v1;

import audiotag.mp3.suffix_write :
    Mp3TrailingId3v1WriteResult,
    materializeMp3TrailingId3v1Write;

import audiotag.mp3.suffix_write_plan :
    planMp3TrailingId3v1Write;


/++
Result of one complete in-memory leading-ID3v2 update.

The outer `ParseResult` reports malformed or unsupported source-prefix
input. The inner `SerializationResult` reports output-materialization
failures. This keeps source parsing and output generation as separate
error domains.
+/
alias Mp3LeadingId3v2UpdateResult =
    ParseResult!(
        SerializationResult!(ubyte[])
    );


/++
Updates the prepended ID3v2 region of a bounded MP3 byte source in memory.

Supported source behavior is inherited from `parseMp3Prefix()`:

- no leading ID3 signature: the replacement is inserted at the beginning;
- leading ID3v2.3 or ID3v2.4: the complete tag envelope is replaced;
- malformed/truncated supported ID3: a structured parse error is returned;
- unsupported ID3 major versions: `unsupportedVersion` is returned.

An empty replacement removes an existing leading tag. On an untagged
source, an empty replacement produces a byte-for-byte copy of the source.

The replacement is not validated as ID3 data. Normal callers should pass
complete bytes produced by an ID3 serializer.

Params:
    source = Complete bounded source bytes to update.
    serializedId3v2 = Complete replacement tag bytes, or an empty slice to
        remove the current leading tag.

Returns:
    A newly allocated complete output buffer in the inner successful
    result, or a structured parse/serialization error.

Safety:
    The returned buffer owns its storage and does not alias `source` or
    `serializedId3v2`. No file I/O is performed.
+/
Mp3LeadingId3v2UpdateResult
updateMp3LeadingId3v2(
    ByteSpan source,
    const(ubyte)[] serializedId3v2
)
    @safe
{
    auto parsed =
        parseMp3Prefix(source);

    if (parsed.hasError)
    {
        return
            Mp3LeadingId3v2UpdateResult
                .failure(
                    parsed.error
                );
    }

    const plan =
        planMp3LeadingId3v2Write(
            parsed.value,
            serializedId3v2
        );

    return
        Mp3LeadingId3v2UpdateResult
            .success(
                materializeMp3LeadingId3v2Write(
                    plan
                )
            );
}


/++
Result of one complete in-memory trailing-ID3v1 update.

The suffix locator cannot fail: absence of ID3v1 is a normal layout result.
Therefore both replacement validation and output materialization use the
single common serialization-error domain.
+/
alias Mp3TrailingId3v1UpdateResult =
    Mp3TrailingId3v1WriteResult;


/++
Updates the trailing ID3v1 region of a bounded MP3 byte source in memory.

Behavior:

- no trailing ID3v1 + valid 128-byte tag -> append at source end;
- existing trailing ID3v1 + valid tag   -> replace final 128 bytes;
- existing trailing ID3v1 + empty input -> remove final 128 bytes;
- no trailing ID3v1 + empty input       -> return an owned byte-for-byte copy.

A non-empty replacement must have the fixed physical ID3v1 shape required by
`planMp3TrailingId3v1Write`: exactly 128 bytes beginning with `TAG`.

No ID3v1 semantic parsing or serialization is performed here. Normal callers
should pass bytes produced by `audiotag.id3v1.serializeId3v1Tag()` or another
valid ID3v1 serializer.

Params:
    source = Complete bounded source bytes to update.
    serializedId3v1 = Complete 128-byte replacement tag, or empty to remove
        the current trailing ID3v1 block.

Returns:
    A newly allocated complete output buffer or a structured serialization
    error.

Safety:
    The returned buffer owns its storage and does not alias `source` or
    `serializedId3v1`. No file I/O is performed.
+/
Mp3TrailingId3v1UpdateResult
updateMp3TrailingId3v1(
    ByteSpan source,
    const(ubyte)[] serializedId3v1
)
    @safe
{
    const layout =
        locateMp3TrailingId3v1(
            source
        );

    const planned =
        planMp3TrailingId3v1Write(
            layout,
            serializedId3v1
        );

    if (planned.hasError)
    {
        return
            Mp3TrailingId3v1UpdateResult
                .failure(
                    planned.error
                );
    }

    return
        materializeMp3TrailingId3v1Write(
            planned.value
        );
}


version (unittest)
{
    import std.sumtype :
        match;

    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.metadata.edit :
        MetadataTreeEdit;

    import audiotag.metadata.field :
        MetadataField,
        MetadataKey;

    import audiotag.metadata.value :
        MetadataText,
        MetadataValue;

    import audiotag.id3v2.v23.api :
        serializeId3v23Tag;

    import audiotag.id3v2.v23.canonical_tag :
        parseId3v23CanonicalTag;

    import audiotag.id3v2.v24.api :
        serializeId3v24Tag;

    import audiotag.id3v2.v24.canonical_tag :
        parseId3v24CanonicalTag;

    import audiotag.id3v1.api :
        serializeId3v1Tag;

    import audiotag.id3v1.canonical :
        parseId3v1CanonicalTag;
}


/// Replaces an existing prepended ID3v2.3 tag in one operation.
unittest
{
    const ubyte[] source =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x02,
            0xAA, 0xBB,
            0xFF, 0xFB
        ];

    const ubyte[] replacement =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    auto result =
        updateMp3LeadingId3v2(
            ByteSpan(source),
            replacement
        );

    assert(result.hasValue);
    assert(result.value.hasValue);

    const ubyte[] expected =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00,
            0xFF, 0xFB
        ];

    assert(
        result.value.value ==
        expected
    );
}


/// Inserts a new leading tag before an untagged source.
unittest
{
    const ubyte[] source =
        [0xFF, 0xFB];

    const ubyte[] replacement =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    auto result =
        updateMp3LeadingId3v2(
            ByteSpan(source),
            replacement
        );

    assert(result.hasValue);
    assert(result.value.hasValue);

    const ubyte[] expected =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00,
            0xFF, 0xFB
        ];

    assert(
        result.value.value ==
        expected
    );
}


/// Removes an existing leading tag when the replacement is empty.
unittest
{
    const ubyte[] source =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x01,
            0xAA,
            0xFF, 0xFB
        ];

    const ubyte[] replacement = [];

    auto result =
        updateMp3LeadingId3v2(
            ByteSpan(source),
            replacement
        );

    assert(result.hasValue);
    assert(result.value.hasValue);

    assert(
        result.value.value ==
        [0xFF, 0xFB]
    );
}


/// An empty replacement on an untagged source copies the source unchanged.
unittest
{
    ubyte[] source =
        [0xFF, 0xFB];

    const ubyte[] replacement = [];

    auto result =
        updateMp3LeadingId3v2(
            ByteSpan(source),
            replacement
        );

    assert(result.hasValue);
    assert(result.value.hasValue);
    assert(result.value.value == source);

    source[0] = 0x00;

    assert(
        result.value.value ==
        [0xFF, 0xFB]
    );
}


/// Source parse errors propagate through the outer result unchanged.
unittest
{
    const ubyte[] source =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x03,
            0xAA
        ];

    auto result =
        updateMp3LeadingId3v2(
            ByteSpan(source, 100),
            []
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 110);
    assert(result.error.requested == 3);
    assert(result.error.available == 1);
}


/// Unsupported leading ID3 revisions remain source parse failures.
unittest
{
    const ubyte[] source =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    auto result =
        updateMp3LeadingId3v2(
            ByteSpan(source, 200),
            []
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.unsupportedVersion
    );

    assert(result.error.offset == 203);
}


/// ID3v2.3 canonical editing integrates with MP3 prefix replacement end to end.
unittest
{
    const ubyte[] audio =
        [
            0xFF, 0xFB, 0x90, 0x64,
            0x12, 0x34
        ];

    const ubyte[] source =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x00, 'U',

            0xFF, 0xFB, 0x90, 0x64,
            0x12, 0x34
        ];

    auto prefix =
        parseMp3Prefix(
            ByteSpan(source, 100)
        );

    assert(prefix.hasValue);
    assert(
        prefix.value.remainder.data ==
        audio
    );

    auto tagCursor =
        ByteCursor(
            prefix.value.leadingId3v2
        );

    auto parsedTag =
        tagCursor.parseId3v23CanonicalTag();

    assert(parsedTag.hasValue);
    assert(tagCursor.empty);

    auto edit =
        MetadataTreeEdit.forSource(
            parsedTag.value
                .projection
                .metadata
        );

    MetadataValue newTitle =
        MetadataText("V");

    edit.replaceSourceField(
        0,
        MetadataField(
            MetadataKey("title"),
            newTitle
        )
    );

    auto serialized =
        serializeId3v23Tag(
            parsedTag.value,
            edit
        );

    assert(serialized.hasValue);
    assert(serialized.value.hasValue);

    auto updated =
        updateMp3LeadingId3v2(
            ByteSpan(source, 100),
            serialized.value.value
        );

    assert(updated.hasValue);
    assert(updated.value.hasValue);

    auto updatedPrefix =
        parseMp3Prefix(
            ByteSpan(
                updated.value.value,
                100
            )
        );

    assert(updatedPrefix.hasValue);
    assert(
        updatedPrefix.value
            .remainder
            .sourceOffset ==
        122
    );
    assert(
        updatedPrefix.value
            .remainder
            .data ==
        audio
    );

    auto updatedTagCursor =
        ByteCursor(
            updatedPrefix.value
                .leadingId3v2
        );

    auto reparsedTag =
        updatedTagCursor
            .parseId3v23CanonicalTag();

    assert(reparsedTag.hasValue);
    assert(updatedTagCursor.empty);

    assert(
        reparsedTag.value
            .projection
            .metadata
            .length ==
        1
    );

    assert(
        reparsedTag.value
            .projection
            .metadata[0]
            .key
            .name ==
        "title"
    );

    const titleMatches =
        reparsedTag.value
            .projection
            .metadata[0]
            .value
            .match!(
                (MetadataText text) =>
                    text.value == "V",
                _ => false
            );

    assert(titleMatches);
}


/// ID3v2.4 canonical editing integrates with MP3 prefix replacement end to end.
unittest
{
    const ubyte[] audio =
        [
            0xFF, 0xFB, 0x90, 0x64,
            0x56, 0x78
        ];

    const ubyte[] source =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x00, 'U',

            0xFF, 0xFB, 0x90, 0x64,
            0x56, 0x78
        ];

    auto prefix =
        parseMp3Prefix(
            ByteSpan(source, 200)
        );

    assert(prefix.hasValue);
    assert(
        prefix.value.remainder.data ==
        audio
    );

    auto tagCursor =
        ByteCursor(
            prefix.value.leadingId3v2
        );

    auto parsedTag =
        tagCursor.parseId3v24CanonicalTag();

    assert(parsedTag.hasValue);
    assert(tagCursor.empty);

    auto edit =
        MetadataTreeEdit.forSource(
            parsedTag.value
                .projection
                .metadata
        );

    MetadataValue newTitle =
        MetadataText("V");

    edit.replaceSourceField(
        0,
        MetadataField(
            MetadataKey("title"),
            newTitle
        )
    );

    auto serialized =
        serializeId3v24Tag(
            parsedTag.value,
            edit
        );

    assert(serialized.hasValue);
    assert(serialized.value.hasValue);

    auto updated =
        updateMp3LeadingId3v2(
            ByteSpan(source, 200),
            serialized.value.value
        );

    assert(updated.hasValue);
    assert(updated.value.hasValue);

    auto updatedPrefix =
        parseMp3Prefix(
            ByteSpan(
                updated.value.value,
                200
            )
        );

    assert(updatedPrefix.hasValue);
    assert(
        updatedPrefix.value
            .remainder
            .sourceOffset ==
        222
    );
    assert(
        updatedPrefix.value
            .remainder
            .data ==
        audio
    );

    auto updatedTagCursor =
        ByteCursor(
            updatedPrefix.value
                .leadingId3v2
        );

    auto reparsedTag =
        updatedTagCursor
            .parseId3v24CanonicalTag();

    assert(reparsedTag.hasValue);
    assert(updatedTagCursor.empty);

    assert(
        reparsedTag.value
            .projection
            .metadata
            .length ==
        1
    );

    assert(
        reparsedTag.value
            .projection
            .metadata[0]
            .key
            .name ==
        "title"
    );

    const titleMatches =
        reparsedTag.value
            .projection
            .metadata[0]
            .value
            .match!(
                (MetadataText text) =>
                    text.value == "V",
                _ => false
            );

    assert(titleMatches);
}


/// Replaces an existing trailing ID3v1 block in one operation.
unittest
{
    ubyte[130] source;

    source[0] = 0xFF;
    source[1] = 0xFB;

    source[2] = 'T';
    source[3] = 'A';
    source[4] = 'G';
    source[129] = 17;

    ubyte[128] replacement;

    replacement[0] = 'T';
    replacement[1] = 'A';
    replacement[2] = 'G';
    replacement[127] = 13;

    auto result =
        updateMp3TrailingId3v1(
            ByteSpan(source[]),
            replacement[]
        );

    assert(result.hasValue);
    assert(result.value.length == 130);

    assert(result.value[0] == 0xFF);
    assert(result.value[1] == 0xFB);

    assert(
        result.value[2 .. $] ==
        replacement[]
    );
}


/// Inserts a new trailing ID3v1 block after an untagged source.
unittest
{
    const ubyte[] source =
        [0xFF, 0xFB];

    ubyte[128] replacement;

    replacement[0] = 'T';
    replacement[1] = 'A';
    replacement[2] = 'G';
    replacement[127] = 17;

    auto result =
        updateMp3TrailingId3v1(
            ByteSpan(source),
            replacement[]
        );

    assert(result.hasValue);
    assert(result.value.length == 130);

    assert(
        result.value[0 .. 2] ==
        source
    );

    assert(
        result.value[2 .. $] ==
        replacement[]
    );
}


/// Removes an existing trailing ID3v1 block with an empty replacement.
unittest
{
    ubyte[130] source;

    source[0] = 0xFF;
    source[1] = 0xFB;

    source[2] = 'T';
    source[3] = 'A';
    source[4] = 'G';

    auto result =
        updateMp3TrailingId3v1(
            ByteSpan(source[]),
            []
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [0xFF, 0xFB]
    );
}


/// Empty replacement on an untagged source returns an independent owned copy.
unittest
{
    ubyte[] source =
        [0xFF, 0xFB];

    auto result =
        updateMp3TrailingId3v1(
            ByteSpan(source),
            []
        );

    assert(result.hasValue);
    assert(result.value == source);

    source[0] = 0;

    assert(
        result.value ==
        [0xFF, 0xFB]
    );
}


/// Invalid replacement shape propagates as a serialization failure.
unittest
{
    ubyte[128] replacement;

    replacement[0] = 'T';
    replacement[1] = 'A';
    replacement[2] = 'X';

    auto result =
        updateMp3TrailingId3v1(
            ByteSpan(
                cast(const(ubyte)[])
                    [0xFF, 0xFB]
            ),
            replacement[]
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(result.error.index == 2);
}


/// Canonical ID3v1 editing integrates with MP3 suffix replacement end to end.
unittest
{
    ubyte[130] source;

    source[0] = 0xFF;
    source[1] = 0xFB;

    source[2] = 'T';
    source[3] = 'A';
    source[4] = 'G';

    source[5] = 'A';

    source[95] = '1';
    source[96] = '9';
    source[97] = '9';
    source[98] = '9';

    source[129] = 255;

    const suffix =
        locateMp3TrailingId3v1(
            ByteSpan(
                source[],
                100
            )
        );

    assert(suffix.hasTrailingId3v1);
    assert(suffix.remainder.length == 2);

    auto parsedTag =
        parseId3v1CanonicalTag(
            suffix.trailingId3v1
        );

    assert(parsedTag.hasValue);
    assert(parsedTag.value.metadata.length == 2);
    assert(
        parsedTag.value.metadata[0]
            .key.name ==
        "title"
    );

    auto edit =
        MetadataTreeEdit.forSource(
            parsedTag.value.metadata
        );

    MetadataValue newTitle =
        MetadataText("B");

    edit.replaceSourceField(
        0,
        MetadataField(
            MetadataKey("title"),
            newTitle
        )
    );

    auto serialized =
        serializeId3v1Tag(
            parsedTag.value,
            edit
        );

    assert(serialized.hasValue);
    assert(serialized.value.length == 128);

    auto updated =
        updateMp3TrailingId3v1(
            ByteSpan(
                source[],
                100
            ),
            serialized.value
        );

    assert(updated.hasValue);
    assert(updated.value.length == 130);

    const updatedSuffix =
        locateMp3TrailingId3v1(
            ByteSpan(
                updated.value,
                100
            )
        );

    assert(updatedSuffix.hasTrailingId3v1);
    assert(updatedSuffix.remainder.length == 2);

    assert(
        updatedSuffix.remainder.data ==
        [0xFF, 0xFB]
    );

    auto reparsed =
        parseId3v1CanonicalTag(
            updatedSuffix.trailingId3v1
        );

    assert(reparsed.hasValue);
    assert(reparsed.value.metadata.length == 2);

    const titleMatches =
        reparsed.value.metadata[0]
            .value
            .match!(
                (MetadataText text) =>
                    text.value == "B",
                _ => false
            );

    assert(titleMatches);

    assert(
        reparsed.value.metadata[1]
            .key.name ==
        "releaseDate"
    );
}
