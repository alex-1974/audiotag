/++
ID3v2.2 tag-body write policy.

This module plans how an already serialized logical frame sequence fits into
the body of an existing provenance-preserved ID3v2.2 tag.

No bytes are emitted here.

Current preservation-oriented policy:

- source whole-tag unsynchronisation stuffing is physical provenance and is
  excluded from logical capacity planning;
- preserve the source logical frames-plus-padding capacity while the new frame
  sequence fits;
- consume or grow logical zero padding before growing the body;
- once the new frame sequence exceeds source logical capacity, padding becomes
  zero and the logical body grows;
- whole-tag-compressed opaque sources are not replanned as frames;
- the logical body must remain inside the 28-bit ID3 tag-size domain.

ID3v2.2 has no extended header, footer, per-frame flags, or stored padding-size
field. Whole-tag unsynchronisation and the final physical `tagSize` are outer
writer concerns and are deliberately not part of this plan.

Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-13
+/
module audiotag.id3v2.v22.tag_body_write_policy;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.structure :
    Id3v22TagStructure;


/++
Returns the logical source body length for one validated uncompressed
ID3v2.2 tag.

The source envelope retains exact physical bytes. When whole-tag
unsynchronisation is active, physical stuffing bytes are removed during
logical traversal so capacity planning remains in the same byte domain as
newly serialized frame data.

Params:
    source = Strictly validated uncompressed ID3v2.2 tag structure.

Returns:
    Number of logical bytes in the complete frames-plus-padding body.

Preconditions:
    `source.hasFrameSequence` must be true.

Safety:
    The strict structural parser has already validated the complete source
    body. Logical reads therefore cannot fail while physical bytes remain.

Complexity:
    O(n) time and O(1) additional space.
+/
private size_t
sourceLogicalBodyLength(
    const(Id3v22TagStructure) source
)
    @safe pure nothrow @nogc
{
    assert(source.hasFrameSequence);

    auto cursor =
        Id3v22DataCursor(
            source.envelope.body,
            source.envelope.header
                .unsynchronisation
        );

    while (!cursor.empty)
    {
        auto decoded =
            cursor.takeByte();

        assert(decoded.hasValue);
    }

    return
        cursor.logicalPosition;
}


/++
Primary structural status of ID3v2.2 tag-body planning.
+/
enum Id3v22TagBodyWriteStatus : ubyte
{
    /// Body planning succeeded.
    ready,

    /++
    The source body is whole-tag-compressed opaque data.

    Such a source may be preserved exactly by a higher no-op preservation
    path, but it cannot be reconstructed as a logical frame sequence.
    +/
    compressedOpaqueSource,

    /// The active strict v2.2 reader requires at least one frame.
    emptyFrameSequence,

    /// The planned logical body exceeds the 28-bit ID3 tag-size domain.
    tagSizeOverflow
}


/++
Complete logical body plan for one writable ID3v2.2 tag.
+/
struct Id3v22TagBodyWritePlan
{
    /// Primary structural planning status.
    Id3v22TagBodyWriteStatus status;

    /// Number of already serialized logical/native frame bytes.
    size_t frameSequenceLength;

    /// Number of trailing logical zero padding bytes to emit.
    size_t paddingLength;

    /++
    Complete logical body length before whole-tag unsynchronisation.

    This is `frameSequenceLength + paddingLength`.

    Physical stored-body length is intentionally not planned here because
    whole-tag unsynchronisation may increase it.
    +/
    size_t logicalBodyLength;


    /++
    Returns whether logical body serialization may proceed.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            status ==
                Id3v22TagBodyWriteStatus.ready;
    }
}


/++
Plans one resulting ID3v2.2 logical tag body around an already serialized
frame sequence.

The source frames-plus-padding body acts as logical available capacity.
For an ordinary source logical and physical lengths are identical. For a
whole-tag-unsynchronised source, physical stuffing bytes are excluded.

Shrinking the frame sequence converts unused capacity into logical zero
padding. Moderate growth consumes existing logical capacity before the body
grows. Growth beyond source logical capacity drops padding to zero.

Whole-tag-compressed sources are rejected by this planner because their body
has no validated logical frame representation. Exact opaque preservation is a
separate higher-level writer path.

Params:
    source = Strictly validated source tag structure.
    frameSequenceLength = Number of bytes in the resulting serialized logical
        frame sequence.

Returns:
    Explicit logical-body policy plan.

Safety:
    No source bytes are retained or modified.

Complexity:
    O(n) time for unsynchronised sources because source logical capacity must
    be measured; O(1) additional space.
+/
Id3v22TagBodyWritePlan
planId3v22TagBodyWrite(
    const(Id3v22TagStructure) source,
    size_t frameSequenceLength
)
    @safe pure nothrow @nogc
{
    enum size_t maximumTagSize =
        0x0FFF_FFFF;

    auto result =
        Id3v22TagBodyWritePlan.init;

    result.status =
        Id3v22TagBodyWriteStatus.ready;

    result.frameSequenceLength =
        frameSequenceLength;

    if (source.compressedOpaque)
    {
        result.status =
            Id3v22TagBodyWriteStatus
                .compressedOpaqueSource;

        return result;
    }

    assert(source.hasFrameSequence);

    if (frameSequenceLength == 0)
    {
        result.status =
            Id3v22TagBodyWriteStatus
                .emptyFrameSequence;

        return result;
    }

    if (
        frameSequenceLength >
        maximumTagSize
    )
    {
        result.status =
            Id3v22TagBodyWriteStatus
                .tagSizeOverflow;

        return result;
    }

    const originalCapacity =
        sourceLogicalBodyLength(
            source
        );

    if (
        frameSequenceLength <=
        originalCapacity
    )
    {
        result.paddingLength =
            originalCapacity -
            frameSequenceLength;
    }
    else
    {
        result.paddingLength = 0;
    }

    if (
        result.paddingLength >
        maximumTagSize -
            result.frameSequenceLength
    )
    {
        result.status =
            Id3v22TagBodyWriteStatus
                .tagSizeOverflow;

        return result;
    }

    result.logicalBodyLength =
        result.frameSequenceLength +
        result.paddingLength;

    return result;
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.structure :
        parseId3v22TagStructure;


    private Id3v22TagStructure
    parseTestTag(
        const(ubyte)[] bytes
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto parsed =
            cursor.parseId3v22TagStructure();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return
            parsed.value;
    }
}


/// Existing logical capacity is retained while growth fits inside padding.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            // Body size = 11.
            0x00, 0x00, 0x00, 0x0B,

            // Seven-byte frame.
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55,

            // Four padding bytes.
            0x00, 0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v22TagBodyWrite(
            source,
            9
        );

    assert(plan.writable);
    assert(plan.frameSequenceLength == 9);
    assert(plan.paddingLength == 2);
    assert(plan.logicalBodyLength == 11);
}


/// Growth beyond source logical capacity drops padding and grows the body.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x0B,

            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55,

            0x00, 0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v22TagBodyWrite(
            source,
            13
        );

    assert(plan.writable);
    assert(plan.paddingLength == 0);
    assert(plan.logicalBodyLength == 13);
}


/// Shrinking frames converts unused source capacity into padding.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x0B,

            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55,

            0x00, 0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v22TagBodyWrite(
            source,
            7
        );

    assert(plan.writable);
    assert(plan.paddingLength == 4);
    assert(plan.logicalBodyLength == 11);
}


/// Physical unsynchronisation stuffing is excluded from source capacity.
unittest
{
    /*
     * Logical body:
     *
     *   frame header = 6
     *   payload      = 3: 11 FF E1
     *   padding      = 2
     *
     * Logical capacity = 11.
     *
     * The stored payload is 11 FF 00 E1, so physical body size is 12.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x80,

            0x00, 0x00, 0x00, 0x0C,

            'T', 'T', '2',
            0x00, 0x00, 0x03,

            0x11,
            0xFF, 0x00, 0xE1,

            0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v22TagBodyWrite(
            source,
            10
        );

    assert(plan.writable);

    /*
     * Correct logical planning leaves one padding byte.
     * Counting physical stuffing as capacity would incorrectly leave two.
     */
    assert(plan.paddingLength == 1);
    assert(plan.logicalBodyLength == 11);
}


/// A compressed opaque source cannot be replanned as frames.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x40,

            0x00, 0x00, 0x00, 0x04,

            0xDE, 0xAD, 0xBE, 0xEF
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v22TagBodyWrite(
            source,
            7
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v22TagBodyWriteStatus
            .compressedOpaqueSource
    );

    assert(plan.frameSequenceLength == 7);
    assert(plan.paddingLength == 0);
    assert(plan.logicalBodyLength == 0);
}


/// An empty resulting frame sequence is rejected explicitly.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x07,

            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v22TagBodyWrite(
            source,
            0
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v22TagBodyWriteStatus
            .emptyFrameSequence
    );
}


/// Logical bodies beyond the 28-bit tag-size domain fail without allocation.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x07,

            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v22TagBodyWrite(
            source,
            0x1000_0000
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v22TagBodyWriteStatus
            .tagSizeOverflow
    );

    assert(
        plan.frameSequenceLength ==
        0x1000_0000
    );
}
