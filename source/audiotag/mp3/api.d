/++
High-level in-memory API for updating a prepended ID3v2 tag in an MP3
byte source.

This module composes the existing MP3 prefix stages:

1. locate and bound a supported prepended ID3v2 tag;
2. plan insertion, replacement or removal of that leading tag;
3. materialize the plan into a new owned byte buffer.

The supplied replacement bytes are treated as an opaque, already
serialized ID3v2 tag. No ID3 serialization is performed here and no file
or other external I/O takes place.
+/
module audiotag.mp3.api;

import audiotag.core.result :
    ParseResult;

import audiotag.core.serialization :
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


version (unittest)
{
    import audiotag.core.error :
        ParseErrorCode;
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
