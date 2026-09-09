/++
I/O-free materialization of an MP3 leading-ID3v2 write plan.

This module executes only the in-memory byte composition described by
`Mp3LeadingId3v2WritePlan`. It allocates a new owned byte buffer containing:

1. the opaque replacement bytes;
2. the source remainder preserved byte-for-byte.

No ID3 structure is reparsed and no file or other external I/O is
performed.
+/
module audiotag.mp3.prefix_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.mp3.prefix_write_plan :
    Mp3LeadingId3v2WritePlan;


/++
Result of materializing one leading-ID3v2 write plan.

The successful value is a newly allocated complete byte buffer for the
bounded source represented by the plan.
+/
alias Mp3LeadingId3v2WriteResult =
    SerializationResult!(ubyte[]);


/++
Checks whether two byte-region lengths can be represented as one `size_t`.

This helper exists separately so the overflow boundary can be tested
without attempting an impractically large allocation.
+/
private SerializationResult!size_t
checkedMaterializedLength(
    size_t replacementLength,
    size_t remainderLength
)
    @safe pure nothrow @nogc
{
    const limit =
        size_t.max -
        remainderLength;

    if (
        replacementLength >
        limit
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidLength,
                        0,
                        replacementLength,
                        limit
                    )
                );
    }

    return
        SerializationResult!size_t
            .success(
                replacementLength +
                remainderLength
            );
}


/++
Materializes one leading-ID3v2 write plan into a new owned byte buffer.

The plan is expected to have been produced by
`planMp3LeadingId3v2Write()`. The replacement bytes remain opaque: this
function does not validate or reinterpret ID3 data.

The source remainder is copied byte-for-byte after the replacement. The
returned array does not alias the replacement or source storage.

Params:
    plan = Previously constructed leading-ID3v2 write plan.

Returns:
    A newly allocated complete byte buffer, or `invalidLength` if the
    replacement and preserved remainder cannot be combined within the
    platform `size_t` domain.

Safety:
    Output-length arithmetic is checked before allocation. No source span
    is accessed outside its existing bounds.
+/
Mp3LeadingId3v2WriteResult
materializeMp3LeadingId3v2Write(
    const(Mp3LeadingId3v2WritePlan) plan
)
    @safe
{
    auto lengthResult =
        checkedMaterializedLength(
            plan.replacement.length,
            plan.preservedRemainder.length
        );

    if (lengthResult.hasError)
    {
        return
            Mp3LeadingId3v2WriteResult
                .failure(
                    lengthResult.error
                );
    }

    const replacementLength =
        plan.replacement.length;

    auto output =
        new ubyte[
            lengthResult.value
        ];

    output[
        0 ..
        replacementLength
    ] =
        plan.replacement;

    output[
        replacementLength ..
        $
    ] =
        plan.preservedRemainder.data;

    return
        Mp3LeadingId3v2WriteResult
            .success(output);
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.mp3.prefix :
        parseMp3Prefix;

    import audiotag.mp3.prefix_write_plan :
        planMp3LeadingId3v2Write;
}


/// Replacing a leading tag produces replacement followed by the old remainder.
unittest
{
    const ubyte[] source =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x02,
            0xAA, 0xBB,
            0xFF, 0xFB, 0x90, 0x64
        ];

    auto parsed =
        parseMp3Prefix(
            ByteSpan(source)
        );

    assert(parsed.hasValue);

    const ubyte[] replacement =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    const plan =
        planMp3LeadingId3v2Write(
            parsed.value,
            replacement
        );

    auto written =
        materializeMp3LeadingId3v2Write(
            plan
        );

    assert(written.hasValue);

    const ubyte[] expected =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00,
            0xFF, 0xFB, 0x90, 0x64
        ];

    assert(
        written.value ==
        expected
    );
}


/// Inserting a new tag before an untagged source preserves all source bytes.
unittest
{
    const ubyte[] source =
        [0xFF, 0xFB, 0x90, 0x64];

    auto parsed =
        parseMp3Prefix(
            ByteSpan(source)
        );

    assert(parsed.hasValue);

    const ubyte[] replacement =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    const plan =
        planMp3LeadingId3v2Write(
            parsed.value,
            replacement
        );

    auto written =
        materializeMp3LeadingId3v2Write(
            plan
        );

    assert(written.hasValue);

    const ubyte[] expected =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00,
            0xFF, 0xFB, 0x90, 0x64
        ];

    assert(
        written.value ==
        expected
    );
}


/// Removing the existing leading tag leaves only the preserved remainder.
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

    auto parsed =
        parseMp3Prefix(
            ByteSpan(source)
        );

    assert(parsed.hasValue);

    const ubyte[] replacement = [];

    const plan =
        planMp3LeadingId3v2Write(
            parsed.value,
            replacement
        );

    auto written =
        materializeMp3LeadingId3v2Write(
            plan
        );

    assert(written.hasValue);
    assert(
        written.value ==
        [0xFF, 0xFB]
    );
}


/// Materialized output owns its bytes independently of plan source storage.
unittest
{
    ubyte[] source =
        [0xFF, 0xFB];

    auto parsed =
        parseMp3Prefix(
            ByteSpan(source)
        );

    assert(parsed.hasValue);

    ubyte[] replacement =
        [0x11, 0x22];

    const plan =
        planMp3LeadingId3v2Write(
            parsed.value,
            replacement
        );

    auto written =
        materializeMp3LeadingId3v2Write(
            plan
        );

    assert(written.hasValue);

    replacement[0] = 0x99;
    source[0] = 0x00;

    assert(
        written.value ==
        [0x11, 0x22, 0xFF, 0xFB]
    );
}


/// A tag-only source can be materialized to an empty output on removal.
unittest
{
    const ubyte[] source =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    auto parsed =
        parseMp3Prefix(
            ByteSpan(source)
        );

    assert(parsed.hasValue);

    const ubyte[] replacement = [];

    const plan =
        planMp3LeadingId3v2Write(
            parsed.value,
            replacement
        );

    auto written =
        materializeMp3LeadingId3v2Write(
            plan
        );

    assert(written.hasValue);
    assert(written.value.length == 0);
}


/// Output-length arithmetic accepts the exact boundary and rejects overflow.
unittest
{
    auto exact =
        checkedMaterializedLength(
            size_t.max - 2,
            2
        );

    assert(exact.hasValue);
    assert(exact.value == size_t.max);

    auto overflow =
        checkedMaterializedLength(
            size_t.max,
            1
        );

    assert(overflow.hasError);
    assert(
        overflow.error.code ==
        SerializationErrorCode.invalidLength
    );
    assert(overflow.error.value == size_t.max);
    assert(overflow.error.limit == size_t.max - 1);
}
