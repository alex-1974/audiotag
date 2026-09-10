/++
I/O-free write planning for the trailing ID3v1 region of an MP3 source.

This module consumes a previously located `Mp3SuffixLayout` and plans only
replacement of the optional final ID3v1 block.

Unlike ID3v2, ID3v1 has one fixed physical representation. A non-empty
replacement must therefore:

- contain exactly 128 bytes;
- begin with the `TAG` signature.

These are container-placement invariants rather than semantic field parsing.
No ID3v1 text, revision, track or genre interpretation is performed here.

No output buffer or file is written. Source bytes preceding the optional tag
remain preserved as the original zero-copy `ByteSpan`.
+/
module audiotag.mp3.suffix_write_plan;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v1.tag :
    id3v1TagSize;

import audiotag.mp3.suffix :
    Mp3SuffixLayout;


/++
Describes replacement, insertion or removal of the trailing ID3v1 region.

`replaceOffset` and `replaceLength` identify the source range to replace.
`replacement` contains the complete already serialized ID3v1 block, or an
empty slice for removal.

`preservedPrefix` references every source byte before the current trailing
ID3v1 block. When no trailing block exists it is the complete source.

The plan does not own `replacement` or `preservedPrefix` storage.
+/
struct Mp3TrailingId3v1WritePlan
{
    /// Absolute source offset at which replacement begins.
    size_t replaceOffset;

    /// Number of existing source bytes replaced at that offset.
    size_t replaceLength;

    /// Complete serialized ID3v1 replacement bytes, or empty for removal.
    const(ubyte)[] replacement;

    /// Source bytes preceding the suffix replacement, preserved unchanged.
    ByteSpan preservedPrefix;
}


/++
Validates the physical shape of an ID3v1 suffix replacement.

An empty replacement is always valid and represents removal/no insertion.
A non-empty replacement must be exactly 128 bytes and begin with `TAG`.

No remaining ID3v1 fields are interpreted.
+/
private SerializationResult!bool
validateReplacement(
    const(ubyte)[] replacement
)
    @safe pure nothrow @nogc
{
    if (replacement.length == 0)
    {
        return
            SerializationResult!bool
                .success(true);
    }

    if (
        replacement.length !=
        id3v1TagSize
    )
    {
        return
            SerializationResult!bool
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidLength,
                        0,
                        replacement.length,
                        id3v1TagSize
                    )
                );
    }

    static immutable ubyte[3] signature =
        ['T', 'A', 'G'];

    foreach (index; 0 .. signature.length)
    {
        if (
            replacement[index] !=
            signature[index]
        )
        {
            return
                SerializationResult!bool
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .invalidValue,
                            index,
                            replacement[index],
                            signature[index]
                        )
                    );
        }
    }

    return
        SerializationResult!bool
            .success(true);
}


/++
Plans replacement, insertion or removal of the trailing ID3v1 region.

The supplied layout is expected to come from
`locateMp3TrailingId3v1()` or obey its invariants.

Behavior:

- existing tag + non-empty valid replacement -> replace final 128 bytes;
- no tag + non-empty valid replacement       -> append at source end;
- existing tag + empty replacement           -> remove final 128 bytes;
- no tag + empty replacement                  -> no-op at source end.

The source prefix is never copied or modified during planning.

Params:
    layout = Previously located MP3 suffix layout.
    serializedId3v1 = Complete serialized ID3v1 block, or empty for removal.

Returns:
    A zero-copy write plan, or a structured serialization error when a
    non-empty replacement does not have the required physical ID3v1 shape.
+/
SerializationResult!Mp3TrailingId3v1WritePlan
planMp3TrailingId3v1Write(
    const(Mp3SuffixLayout) layout,
    const(ubyte)[] serializedId3v1
)
    @safe pure nothrow @nogc
{
    const validation =
        validateReplacement(
            serializedId3v1
        );

    if (validation.hasError)
    {
        return
            SerializationResult!(
                Mp3TrailingId3v1WritePlan
            ).failure(
                validation.error
            );
    }

    return
        SerializationResult!(
            Mp3TrailingId3v1WritePlan
        ).success(
            Mp3TrailingId3v1WritePlan(
                layout.trailingId3v1
                    .sourceOffset,
                layout.trailingId3v1
                    .length,
                serializedId3v1,
                layout.remainder
            )
        );
}


version (unittest)
{
    import audiotag.mp3.suffix :
        locateMp3TrailingId3v1;
}


/// Replacing an existing trailing ID3v1 block preserves the complete prefix.
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
            ByteSpan(
                source[],
                100
            )
        );

    ubyte[128] replacement;

    replacement[0] = 'T';
    replacement[1] = 'A';
    replacement[2] = 'G';
    replacement[127] = 13;

    const result =
        planMp3TrailingId3v1Write(
            layout,
            replacement[]
        );

    assert(result.hasValue);

    const plan =
        result.value;

    assert(plan.replaceOffset == 104);
    assert(plan.replaceLength == 128);
    assert(plan.replacement == replacement[]);
    assert(plan.preservedPrefix.sourceOffset == 100);
    assert(plan.preservedPrefix.length == 4);

    assert(
        plan.preservedPrefix.data ==
        [0xFF, 0xFB, 0x90, 0x64]
    );
}


/// An untagged source plans insertion exactly at the source end.
unittest
{
    const ubyte[] source =
        [0xFF, 0xFB, 0x90, 0x64];

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(
                source,
                200
            )
        );

    ubyte[128] replacement;

    replacement[0] = 'T';
    replacement[1] = 'A';
    replacement[2] = 'G';

    const result =
        planMp3TrailingId3v1Write(
            layout,
            replacement[]
        );

    assert(result.hasValue);

    const plan =
        result.value;

    assert(plan.replaceOffset == 204);
    assert(plan.replaceLength == 0);
    assert(plan.replacement.length == 128);
    assert(plan.preservedPrefix.data == source);
    assert(plan.preservedPrefix.sourceOffset == 200);
}


/// An empty replacement removes an existing trailing ID3v1 block.
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
            ByteSpan(
                source[],
                300
            )
        );

    const result =
        planMp3TrailingId3v1Write(
            layout,
            []
        );

    assert(result.hasValue);

    const plan =
        result.value;

    assert(plan.replaceOffset == 302);
    assert(plan.replaceLength == 128);
    assert(plan.replacement.length == 0);
    assert(plan.preservedPrefix.data == [0xFF, 0xFB]);
}


/// Empty replacement on an untagged source is a no-op planned at source end.
unittest
{
    const ubyte[] source =
        [0xFF, 0xFB];

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(
                source,
                400
            )
        );

    const result =
        planMp3TrailingId3v1Write(
            layout,
            []
        );

    assert(result.hasValue);

    const plan =
        result.value;

    assert(plan.replaceOffset == 402);
    assert(plan.replaceLength == 0);
    assert(plan.replacement.length == 0);
    assert(plan.preservedPrefix.data == source);
}


/// Non-empty replacements must have the fixed ID3v1 length.
unittest
{
    ubyte[127] replacement;

    replacement[0] = 'T';
    replacement[1] = 'A';
    replacement[2] = 'G';

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(
                cast(const(ubyte)[])
                    [0xFF, 0xFB]
            )
        );

    const result =
        planMp3TrailingId3v1Write(
            layout,
            replacement[]
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidLength
    );

    assert(result.error.value == 127);
    assert(result.error.limit == 128);
}


/// A fixed-size replacement must carry the trailing-tag TAG signature.
unittest
{
    ubyte[128] replacement;

    replacement[0] = 'T';
    replacement[1] = 'A';
    replacement[2] = 'X';

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(
                cast(const(ubyte)[])
                    [0xFF, 0xFB]
            )
        );

    const result =
        planMp3TrailingId3v1Write(
            layout,
            replacement[]
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(result.error.index == 2);
    assert(result.error.value == 'X');
    assert(result.error.limit == 'G');
}


/// Replacement bytes remain a zero-copy read-only view until execution.
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

    const result =
        planMp3TrailingId3v1Write(
            layout,
            replacement[]
        );

    assert(result.hasValue);

    replacement[127] = 13;

    assert(
        result.value
            .replacement[127] ==
        13
    );
}
