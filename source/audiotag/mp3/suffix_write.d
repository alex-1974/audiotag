/++
I/O-free materialization of an MP3 trailing-ID3v1 write plan.

This module executes only the in-memory byte composition described by
`Mp3TrailingId3v1WritePlan`. The plan has already validated the physical
replacement shape.

Output consists of:

1. every source byte preceding the optional old trailing ID3v1 block;
2. the replacement ID3v1 block, or no bytes when the suffix is removed.

No ID3v1 fields are reparsed and no file or other external I/O is performed.
+/
module audiotag.mp3.suffix_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.mp3.suffix_write_plan :
    Mp3TrailingId3v1WritePlan;


/++
Result of materializing one trailing-ID3v1 write plan.

The successful value is a newly allocated complete byte buffer for the
bounded source represented by the plan.
+/
alias Mp3TrailingId3v1WriteResult =
    SerializationResult!(ubyte[]);


/++
Checks whether preserved-prefix and replacement lengths fit in one `size_t`.

This helper is separate so the overflow boundary can be tested without
attempting an impractically large allocation.
+/
private SerializationResult!size_t
checkedMaterializedLength(
    size_t prefixLength,
    size_t replacementLength
)
    @safe pure nothrow @nogc
{
    const limit =
        size_t.max -
        replacementLength;

    if (
        prefixLength >
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
                        prefixLength,
                        limit
                    )
                );
    }

    return
        SerializationResult!size_t
            .success(
                prefixLength +
                replacementLength
            );
}


/++
Materializes one trailing-ID3v1 write plan into a new owned byte buffer.

The plan is expected to have been produced by
`planMp3TrailingId3v1Write()`. Its replacement bytes are therefore either
empty or one physically valid 128-byte ID3v1 block.

The preserved source prefix is copied byte-for-byte before the replacement.
The returned array does not alias either source or replacement storage.

Params:
    plan = Previously validated trailing-ID3v1 write plan.

Returns:
    Newly allocated complete output bytes, or `invalidLength` if the two
    regions cannot be combined within the platform `size_t` domain.
+/
Mp3TrailingId3v1WriteResult
materializeMp3TrailingId3v1Write(
    const(Mp3TrailingId3v1WritePlan) plan
)
    @safe
{
    const lengthResult =
        checkedMaterializedLength(
            plan.preservedPrefix.length,
            plan.replacement.length
        );

    if (lengthResult.hasError)
    {
        return
            Mp3TrailingId3v1WriteResult
                .failure(
                    lengthResult.error
                );
    }

    const prefixLength =
        plan.preservedPrefix.length;

    auto output =
        new ubyte[
            lengthResult.value
        ];

    output[
        0 ..
        prefixLength
    ] =
        plan.preservedPrefix.data;

    output[
        prefixLength ..
        $
    ] =
        plan.replacement;

    return
        Mp3TrailingId3v1WriteResult
            .success(output);
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.mp3.suffix :
        locateMp3TrailingId3v1;

    import audiotag.mp3.suffix_write_plan :
        planMp3TrailingId3v1Write;
}


/// Replacing an existing trailing tag preserves the complete source prefix.
unittest
{
    ubyte[132] source;

    source[0] = 0xFF;
    source[1] = 0xFB;
    source[2] = 0x90;
    source[3] = 0x64;

    source[4] = 'T';
    source[5] = 'A';
    source[6] = 'G';
    source[131] = 17;

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(source[])
        );

    ubyte[128] replacement;

    replacement[0] = 'T';
    replacement[1] = 'A';
    replacement[2] = 'G';
    replacement[127] = 13;

    const planned =
        planMp3TrailingId3v1Write(
            layout,
            replacement[]
        );

    assert(planned.hasValue);

    auto written =
        materializeMp3TrailingId3v1Write(
            planned.value
        );

    assert(written.hasValue);
    assert(written.value.length == 132);

    assert(
        written.value[0 .. 4] ==
        source[0 .. 4]
    );

    assert(
        written.value[4 .. $] ==
        replacement[]
    );
}


/// Inserting a trailing tag appends it after every untagged source byte.
unittest
{
    ubyte[] source =
        [0xFF, 0xFB, 0x90, 0x64];

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(source)
        );

    ubyte[128] replacement;

    replacement[0] = 'T';
    replacement[1] = 'A';
    replacement[2] = 'G';
    replacement[127] = 17;

    const planned =
        planMp3TrailingId3v1Write(
            layout,
            replacement[]
        );

    assert(planned.hasValue);

    auto written =
        materializeMp3TrailingId3v1Write(
            planned.value
        );

    assert(written.hasValue);
    assert(written.value.length == 132);
    assert(written.value[0 .. 4] == source);
    assert(written.value[4 .. $] == replacement[]);
}


/// Removing an existing trailing tag leaves only the preserved prefix.
unittest
{
    ubyte[130] source;

    source[0] = 0xFF;
    source[1] = 0xFB;

    source[2] = 'T';
    source[3] = 'A';
    source[4] = 'G';

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(source[])
        );

    const planned =
        planMp3TrailingId3v1Write(
            layout,
            []
        );

    assert(planned.hasValue);

    auto written =
        materializeMp3TrailingId3v1Write(
            planned.value
        );

    assert(written.hasValue);

    assert(
        written.value ==
        [0xFF, 0xFB]
    );
}


/// Empty replacement on an untagged source produces an owned byte-for-byte copy.
unittest
{
    ubyte[] source =
        [0xFF, 0xFB];

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(source)
        );

    const planned =
        planMp3TrailingId3v1Write(
            layout,
            []
        );

    assert(planned.hasValue);

    auto written =
        materializeMp3TrailingId3v1Write(
            planned.value
        );

    assert(written.hasValue);
    assert(written.value == source);

    source[0] = 0;

    assert(
        written.value ==
        [0xFF, 0xFB]
    );
}


/// Materialized output does not alias replacement storage.
unittest
{
    const ubyte[] source =
        [0xFF, 0xFB];

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(source)
        );

    ubyte[128] replacement;

    replacement[0] = 'T';
    replacement[1] = 'A';
    replacement[2] = 'G';
    replacement[127] = 17;

    const planned =
        planMp3TrailingId3v1Write(
            layout,
            replacement[]
        );

    assert(planned.hasValue);

    auto written =
        materializeMp3TrailingId3v1Write(
            planned.value
        );

    assert(written.hasValue);

    replacement[127] = 13;

    assert(
        written.value[$ - 1] ==
        17
    );
}


/// A tag-only source can materialize to an empty output on removal.
unittest
{
    ubyte[128] source;

    source[0] = 'T';
    source[1] = 'A';
    source[2] = 'G';

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(source[])
        );

    const planned =
        planMp3TrailingId3v1Write(
            layout,
            []
        );

    assert(planned.hasValue);

    auto written =
        materializeMp3TrailingId3v1Write(
            planned.value
        );

    assert(written.hasValue);
    assert(written.value.length == 0);
}


/// Output-length arithmetic accepts its exact boundary and rejects overflow.
unittest
{
    const exact =
        checkedMaterializedLength(
            size_t.max - 128,
            128
        );

    assert(exact.hasValue);
    assert(exact.value == size_t.max);

    const overflow =
        checkedMaterializedLength(
            size_t.max - 127,
            128
        );

    assert(overflow.hasError);

    assert(
        overflow.error.code ==
        SerializationErrorCode.invalidLength
    );

    assert(
        overflow.error.value ==
        size_t.max - 127
    );

    assert(
        overflow.error.limit ==
        size_t.max - 128
    );
}
