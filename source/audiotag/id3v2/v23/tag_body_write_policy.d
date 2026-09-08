/++
ID3v2.3 tag-body write policy.

This module decides how an already serialized frame sequence fits into
the body of an existing provenance-preserved ID3v2.3 tag.

No bytes are emitted here.

Current conservative policy:

Padding:
- preserve the original frames-plus-padding capacity when the new frame
  sequence fits inside it;
- if the new sequence exceeds that capacity, padding becomes zero and
  the tag body grows.

Extended header:
- absent remains absent;
- an existing extended header may be preserved only while its stored
  padding-size value remains correct;
- when the resulting padding size changes, a non-CRC extended header
  must be regenerated with the new padding-size value;
- an existing CRC blocks a changed frame sequence until CRC generation
  is implemented.

Whole-tag unsynchronisation:
- currently unsupported for body reconstruction;
- the frame-sequence writer deliberately emits ordinary
  non-unsynchronised output.

The resulting logical body length includes the optional extended header,
complete frame sequence and padding. It excludes the fixed ten-byte tag
header.

The physical ID3 header `tagSize` is deliberately not part of this plan.
It belongs to the outer tag writer because whole-tag unsynchronisation
may increase the stored body length.

ID3v2.3 has no footer.
+/
module audiotag.id3v2.v23.tag_body_write_policy;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.structure :
    Id3v23TagStructure;


/++
Returns the logical length of the source frames-plus-padding region.

For an ordinary source this equals the physical span length.

For a whole-tag-unsynchronised source the physical region may contain
stuffing bytes. Traverse it through the same logical cursor used by the
reader so body-capacity planning never mixes physical source length with
logical newly serialized frame length.

`source` is required to be a strictly validated tag structure, so a
logical byte read while physical bytes remain cannot fail.
+/
private size_t
sourceLogicalFramesAndPaddingLength(
    const(Id3v23TagStructure) source
)
    @safe pure nothrow @nogc
{
    auto cursor =
        Id3v23DataCursor(
            source.body.framesAndPadding,
            source.envelope.header
                .unsynchronisation
        );

    while (!cursor.empty)
    {
        auto decoded =
            cursor.takeByte();

        assert(decoded.hasValue);
    }

    return cursor.logicalPosition;
}


/++
Primary structural status of tag-body planning.
+/
enum Id3v23TagBodyWriteStatus : ubyte
{
    ready,

    /// The active strict reader requires at least one frame.
    emptyFrameSequence,

    /// Logical body already exceeds the 28-bit tag-size domain.
    tagSizeOverflow
}


/++
Treatment of the source ID3v2.3 extended header.
+/
enum Id3v23ExtendedHeaderWriteAction : ubyte
{
    /// No extended header exists in the source tag.
    absent,

    /// Copy the complete original extended-header bytes unchanged.
    preserveOriginal,

    /// Re-encode the existing structural form with a new padding size.
    regenerate
}


/++
Complete policy plan for one resulting ID3v2.3 tag body.
+/
struct Id3v23TagBodyWritePlan
{
    /// Primary structural planning status.
    Id3v23TagBodyWriteStatus status;

    /// How the optional source extended header is handled.
    Id3v23ExtendedHeaderWriteAction extendedHeaderAction;

    /// Number of extended-header bytes in the resulting body.
    size_t extendedHeaderLength;

    /// Number of already serialized native frame bytes.
    size_t frameSequenceLength;

    /// Number of trailing logical zero padding bytes to emit.
    size_t paddingLength;

    /++
    Complete logical body length before ID3v2.3 whole-tag
    unsynchronisation.

    This includes the optional extended header, complete native frame
    sequence and logical padding.

    Physical stored-body length is intentionally not planned here.
    +/
    size_t logicalBodyLength;

    /// A source CRC would become stale after frame-sequence modification.
    bool crcBlocksChange;


    /++
    Returns whether body serialization may proceed.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            status ==
                Id3v23TagBodyWriteStatus.ready &&
            !crcBlocksChange;
    }
}


/++
Plans one resulting ID3v2.3 tag body around an already serialized frame
sequence.

`frameSequenceChanged` describes logical/native change relative to the
source native frame sequence. It must be true not only for canonical
edits but also when preservation policy discards or otherwise changes
native frames.

The source frames-plus-padding region acts as logical available
capacity. For an ordinary source logical and physical lengths are
identical. For a whole-tag-unsynchronised source, stuffing bytes are
removed before this capacity is calculated.

Shrinking the frame sequence increases logical padding. Moderate growth
consumes that padding before the logical body itself grows.

Unlike ID3v2.4, an ID3v2.3 extended header stores the exact trailing
padding size. Consequently an existing non-CRC extended header must be
regenerated whenever the resulting padding length differs from the
source value.

Params:
    source = Strictly validated source tag structure.
    frameSequenceLength = Number of bytes in the resulting frame
        sequence.
    frameSequenceChanged = Whether resulting frame bytes differ from the
        source frame sequence.

Returns:
    Explicit body policy plan.
+/
Id3v23TagBodyWritePlan
planId3v23TagBodyWrite(
    const(Id3v23TagStructure) source,
    size_t frameSequenceLength,
    bool frameSequenceChanged
)
    @safe pure nothrow @nogc
{
    enum size_t maximumTagSize =
        0x0FFF_FFFF;

    auto result =
        Id3v23TagBodyWritePlan.init;

    result.status =
        Id3v23TagBodyWriteStatus.ready;

    result.frameSequenceLength =
        frameSequenceLength;

    if (frameSequenceLength == 0)
    {
        /*
         * Match the active strict structural parser, which requires at
         * least one frame in a complete v2.3 tag.
         */
        result.status =
            Id3v23TagBodyWriteStatus
                .emptyFrameSequence;
    }

    /*
     * Capacity is defined in the logical/native byte domain because the
     * supplied frame sequence is likewise logical/native.
     *
     * For unsynchronised sources this deliberately excludes physical
     * stuffing bytes.
     */
    const originalCapacity =
        sourceLogicalFramesAndPaddingLength(
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

    if (source.body.hasExtendedHeader)
    {
        /*
         * The body plan always describes the logical extended-header
         * representation. A whole-tag-unsynchronised source may occupy
         * more physical bytes because its raw provenance retains stuffing.
         */
        result.extendedHeaderLength =
            source.body.extendedHeader
                .logicalLength;

        const sourcePaddingLength =
            cast(size_t)
                source.body.extendedHeader
                    .paddingSize;

        if (
            !source.envelope.header
                .unsynchronisation &&
            result.paddingLength ==
                sourcePaddingLength
        )
        {
            /*
             * Only an ordinary source can be copied byte-for-byte into
             * the logical body.
             */
            result.extendedHeaderAction =
                Id3v23ExtendedHeaderWriteAction
                    .preserveOriginal;
        }
        else
        {
            /*
             * A changed padding size requires regeneration because the
             * value is stored inside the extended header itself.
             *
             * An unsynchronised source also requires regeneration even
             * when padding is unchanged: its raw provenance may already
             * contain physical stuffing and must never be copied into a
             * logical body that will later be unsynchronised again.
             */
            result.extendedHeaderAction =
                Id3v23ExtendedHeaderWriteAction
                    .regenerate;
        }

        if (
            frameSequenceChanged &&
            source.body.extendedHeader
                .hasCrc
        )
        {
            /*
             * The existing checksum belongs to the source frame
             * sequence. Do not emit it after semantic/native changes
             * until CRC generation exists.
             */
            result.crcBlocksChange = true;
        }
    }
    else
    {
        result.extendedHeaderAction =
            Id3v23ExtendedHeaderWriteAction.absent;

        result.extendedHeaderLength = 0;
    }

    /*
     * Calculate in bounded steps so neither size_t overflow nor a value
     * outside the 28-bit ID3 tag-size domain can reach the outer header.
     */
    if (
        result.extendedHeaderLength >
            maximumTagSize ||
        result.frameSequenceLength >
            maximumTagSize -
                result.extendedHeaderLength
    )
    {
        result.status =
            Id3v23TagBodyWriteStatus
                .tagSizeOverflow;

        return result;
    }

    const withoutPadding =
        result.extendedHeaderLength +
        result.frameSequenceLength;

    if (
        result.paddingLength >
        maximumTagSize - withoutPadding
    )
    {
        result.status =
            Id3v23TagBodyWriteStatus
                .tagSizeOverflow;

        return result;
    }

    const totalBodyLength =
        withoutPadding +
        result.paddingLength;

    result.logicalBodyLength =
        totalBodyLength;

    return result;
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.structure :
        parseId3v23TagStructure;


    private Id3v23TagStructure parseTestTag(
        const(ubyte)[] bytes
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto parsed =
            cursor.parseId3v23TagStructure();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }
}


/// Existing capacity is retained by consuming padding before body growth.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            // Body size = 20.
            0x00, 0x00, 0x00, 0x14,

            // Eleven-byte frame.
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            // Nine padding bytes.
            0x00, 0x00, 0x00,
            0x00, 0x00, 0x00,
            0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v23TagBodyWrite(
            source,
            15,
            true
        );

    assert(plan.writable);

    assert(
        plan.extendedHeaderAction ==
        Id3v23ExtendedHeaderWriteAction.absent
    );

    assert(plan.frameSequenceLength == 15);
    assert(plan.paddingLength == 5);
    assert(plan.logicalBodyLength == 20);
}


/// Growth beyond old capacity drops padding and expands the body.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x0F,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v23TagBodyWrite(
            source,
            25,
            true
        );

    assert(plan.writable);
    assert(plan.paddingLength == 0);
    assert(plan.logicalBodyLength == 25);
}


/// Shrinking frames converts unused source capacity into padding.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x14,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00, 0x00,
            0x00, 0x00, 0x00,
            0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v23TagBodyWrite(
            source,
            11,
            false
        );

    assert(plan.writable);
    assert(plan.paddingLength == 9);
    assert(plan.logicalBodyLength == 20);
}


/// Unchanged v2.3 extended-header padding permits exact preservation.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            /*
             * 10-byte extended header +
             * 11-byte frame +
             * 3-byte padding = 24.
             */
            0x00, 0x00, 0x00, 0x18,

            /*
             * Extended-header size = 6.
             */
            0x00, 0x00, 0x00, 0x06,

            /*
             * No CRC.
             */
            0x00, 0x00,

            /*
             * Padding size = 3.
             */
            0x00, 0x00, 0x00, 0x03,

            'T', 'A', 'L', 'B',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    /*
     * Same physical sequence length. The bytes may have changed, but
     * the extended header does not depend on frame contents when no CRC
     * exists.
     */
    const plan =
        planId3v23TagBodyWrite(
            source,
            11,
            true
        );

    assert(plan.writable);

    assert(
        plan.extendedHeaderAction ==
        Id3v23ExtendedHeaderWriteAction
            .preserveOriginal
    );

    assert(plan.extendedHeaderLength == 10);
    assert(plan.paddingLength == 3);
    assert(plan.logicalBodyLength == 24);
}


/// Changed v2.3 padding requires extended-header regeneration.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            /*
             * 10 extended + 11 frame + 3 padding = 24.
             */
            0x00, 0x00, 0x00, 0x18,

            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            /*
             * Source padding size = 3.
             */
            0x00, 0x00, 0x00, 0x03,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    /*
     * Twelve frame bytes consume one original padding byte.
     * Resulting padding is therefore two and the stored padding-size
     * field must change from three to two.
     */
    const plan =
        planId3v23TagBodyWrite(
            source,
            12,
            true
        );

    assert(plan.writable);

    assert(
        plan.extendedHeaderAction ==
        Id3v23ExtendedHeaderWriteAction
            .regenerate
    );

    assert(plan.extendedHeaderLength == 10);
    assert(plan.paddingLength == 2);
    assert(plan.logicalBodyLength == 24);
}


/// A changed sequence makes an existing v2.3 CRC explicitly stale.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            /*
             * 14 extended + 11 frame + 2 padding = 27.
             */
            0x00, 0x00, 0x00, 0x1B,

            /*
             * Extended-header size = 10.
             */
            0x00, 0x00, 0x00, 0x0A,

            /*
             * CRC present.
             */
            0x80, 0x00,

            /*
             * Padding size = 2.
             */
            0x00, 0x00, 0x00, 0x02,

            /*
             * Existing CRC.
             */
            0x12, 0x34, 0x56, 0x78,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v23TagBodyWrite(
            source,
            11,
            true
        );

    assert(
        plan.status ==
        Id3v23TagBodyWriteStatus.ready
    );

    assert(plan.crcBlocksChange);
    assert(!plan.writable);

    assert(
        plan.extendedHeaderAction ==
        Id3v23ExtendedHeaderWriteAction
            .preserveOriginal
    );
}


/// An unchanged CRC-bearing source extended header may remain opaque.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            0x00, 0x00, 0x00, 0x1B,

            0x00, 0x00, 0x00, 0x0A,
            0x80, 0x00,
            0x00, 0x00, 0x00, 0x02,
            0x12, 0x34, 0x56, 0x78,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v23TagBodyWrite(
            source,
            11,
            false
        );

    assert(plan.writable);
    assert(!plan.crcBlocksChange);

    assert(
        plan.extendedHeaderAction ==
        Id3v23ExtendedHeaderWriteAction
            .preserveOriginal
    );

    assert(plan.extendedHeaderLength == 14);
    assert(plan.paddingLength == 2);
    assert(plan.logicalBodyLength == 27);
}


/// Unsynchronised source capacity is calculated in logical bytes.
unittest
{
    /*
     * Logical frame:
     *
     *   10-byte header
     *    2-byte payload FF E1
     *
     * Whole-tag unsynchronisation makes the physical source frame one
     * byte larger:
     *
     *   FF E1 -> FF 00 E1
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x80,

            // Physical body size = 13.
            0x00, 0x00, 0x00, 0x0D,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0xFF, 0x00, 0xE1
        ];

    const source =
        parseTestTag(bytes);

    assert(
        source.body.framesAndPadding.length ==
        13
    );

    const plan =
        planId3v23TagBodyWrite(
            source,

            // Resulting logical/native frame sequence.
            12,

            false
        );

    assert(
        plan.status ==
        Id3v23TagBodyWriteStatus.ready
    );

    assert(plan.writable);

    /*
     * Physical stuffing must not become reusable logical padding.
     */
    assert(plan.frameSequenceLength == 12);
    assert(plan.paddingLength == 0);
    assert(plan.logicalBodyLength == 12);
}


/// Removing every frame is rejected to match the active strict reader.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x0B,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v23TagBodyWrite(
            source,
            0,
            true
        );

    assert(
        plan.status ==
        Id3v23TagBodyWriteStatus
            .emptyFrameSequence
    );

    assert(!plan.writable);
}


/// Resulting bodies must fit the ID3 28-bit synchsafe tag-size field.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x0B,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v23TagBodyWrite(
            source,
            0x1000_0000,
            true
        );

    assert(
        plan.status ==
        Id3v23TagBodyWriteStatus
            .tagSizeOverflow
    );

    assert(!plan.writable);
}
