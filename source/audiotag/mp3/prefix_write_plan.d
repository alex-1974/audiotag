/++
I/O-free write planning for the leading ID3v2 region of an MP3 source.

This module consumes a previously validated `Mp3PrefixLayout` and plans
only the byte replacement at the beginning of the source. The replacement
bytes are treated as an opaque, already serialized ID3v2 tag.

No ID3 structure is reparsed here and no output buffer or file is written.
The source remainder is preserved as the original zero-copy `ByteSpan`.
+/
module audiotag.mp3.prefix_write_plan;

import audiotag.core.span :
    ByteSpan;

import audiotag.mp3.prefix :
    Mp3PrefixLayout;


/++
Describes replacement of the currently prepended ID3v2 region.

`replaceOffset` and `replaceLength` identify the source range to replace.
`replacement` contains the already serialized bytes that should occupy
that range in a later execution step. `preservedRemainder` references the
source bytes that must be copied or otherwise retained byte-for-byte after
the replacement.

The plan does not own `replacement` or `preservedRemainder` storage.
Callers must keep the underlying storage alive until the plan is consumed.
+/
struct Mp3LeadingId3v2WritePlan
{
    /// Absolute source offset at which replacement begins.
    size_t replaceOffset;

    /// Number of existing source bytes replaced at that offset.
    size_t replaceLength;

    /// Opaque already serialized ID3v2 replacement bytes.
    const(ubyte)[] replacement;

    /// Source bytes following the old leading tag, preserved unchanged.
    ByteSpan preservedRemainder;
}


/++
Plans replacement, insertion or removal of the leading ID3v2 region.

The supplied layout is expected to come from `parseMp3Prefix()` or to obey
its invariants:

- `leadingId3v2` begins at the inspected source offset;
- `remainder` begins immediately after `leadingId3v2`;
- both spans reference the same original source in order.

The replacement is deliberately not validated as ID3 here. The normal
caller is expected to provide complete bytes produced by an ID3 serializer.
An empty replacement removes an existing leading tag. When the layout has
no leading tag, `replaceLength` is zero and a non-empty replacement becomes
an insertion at the source beginning.

Params:
    layout = Previously validated MP3 prefix layout.
    serializedId3v2 = Complete replacement bytes, or empty bytes to remove
        the existing leading tag.

Returns:
    A zero-copy write plan. Planning itself cannot fail.
+/
Mp3LeadingId3v2WritePlan
planMp3LeadingId3v2Write(
    const(Mp3PrefixLayout) layout,
    const(ubyte)[] serializedId3v2
)
    @safe pure nothrow @nogc
{
    return
        Mp3LeadingId3v2WritePlan(
            layout.leadingId3v2.sourceOffset,
            layout.leadingId3v2.length,
            serializedId3v2,
            layout.remainder
        );
}


version (unittest)
{
    import audiotag.mp3.prefix :
        parseMp3Prefix;
}


/// Replacing an existing leading tag preserves the complete remainder.
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
            ByteSpan(source, 100)
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

    assert(plan.replaceOffset == 100);
    assert(plan.replaceLength == 12);
    assert(plan.replacement == replacement);
    assert(plan.preservedRemainder.sourceOffset == 112);
    assert(
        plan.preservedRemainder.data ==
        [0xFF, 0xFB, 0x90, 0x64]
    );
}


/// A source without a leading tag plans insertion at its first byte.
unittest
{
    const ubyte[] source =
        [0xFF, 0xFB, 0x90, 0x64];

    auto parsed =
        parseMp3Prefix(
            ByteSpan(source, 200)
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

    assert(plan.replaceOffset == 200);
    assert(plan.replaceLength == 0);
    assert(plan.replacement == replacement);
    assert(plan.preservedRemainder.sourceOffset == 200);
    assert(plan.preservedRemainder.data == source);
}


/// An empty replacement removes the entire existing leading tag.
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
            ByteSpan(source, 300)
        );

    assert(parsed.hasValue);

    const ubyte[] replacement = [];

    const plan =
        planMp3LeadingId3v2Write(
            parsed.value,
            replacement
        );

    assert(plan.replaceOffset == 300);
    assert(plan.replaceLength == 11);
    assert(plan.replacement.length == 0);
    assert(plan.preservedRemainder.sourceOffset == 311);
    assert(plan.preservedRemainder.data == [0xFF, 0xFB]);
}


/// A v2.4 footer is included in the range replaced by the plan.
unittest
{
    const ubyte[] source =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x00,

            '3', 'D', 'I',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x00,

            0xFF, 0xFB
        ];

    auto parsed =
        parseMp3Prefix(
            ByteSpan(source, 400)
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

    assert(plan.replaceOffset == 400);
    assert(plan.replaceLength == 20);
    assert(plan.preservedRemainder.sourceOffset == 420);
    assert(plan.preservedRemainder.data == [0xFF, 0xFB]);
}


/// The replacement is retained as a zero-copy read-only view.
unittest
{
    const ubyte[] source =
        [0xFF, 0xFB];

    auto parsed =
        parseMp3Prefix(
            ByteSpan(source, 500)
        );

    assert(parsed.hasValue);

    ubyte[] replacement =
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

    replacement[9] = 0x01;

    assert(plan.replacement[9] == 0x01);
}
