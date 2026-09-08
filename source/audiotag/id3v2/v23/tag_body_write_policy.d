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

The resulting tag size includes the optional extended header, complete
frame sequence and padding. It excludes the fixed ten-byte tag header.

ID3v2.3 has no footer.
+/
module audiotag.id3v2.v23.tag_body_write_policy;

import audiotag.id3v2.v23.structure :
    Id3v23TagStructure;


/++
Primary structural status of tag-body planning.
+/
enum Id3v23TagBodyWriteStatus : ubyte
{
    ready,

    /// The active strict reader requires at least one frame.
    emptyFrameSequence,

    /// Whole-tag byte unsynchronisation writing is not implemented yet.
    tagLevelUnsynchronisationUnsupported,

    /// Resulting body size exceeds the 28-bit synchsafe tag-size domain.
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

    While whole-tag output transformation is not yet integrated,
    `tagSize` is identical to this value.
    +/
    size_t logicalBodyLength;

    /++
    Final physical ID3 header tag-size value when representable.

    Once whole-tag unsynchronisation output is integrated this value
    will describe the stored physical body length and may therefore be
    greater than `logicalBodyLength`.
    +/
    uint tagSize;

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

`frameSequenceChanged` describes physical change relative to the source
native frame sequence. It must be true not only for canonical edits but
also when preservation policy discards or otherwise changes native
frames.

For a non-unsynchronised source tag, the original frames-plus-padding
region acts as available capacity. Shrinking the frame sequence
increases padding. Moderate growth consumes existing padding before the
body itself grows.

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

    /*
     * The sequence writer cannot currently produce a complete physical
     * whole-tag-unsynchronised representation.
     *
     * Keep computing the descriptive parts of the plan below, but mark
     * the result non-writable.
     */
    if (
        source.envelope.header
            .unsynchronisation
    )
    {
        result.status =
            Id3v23TagBodyWriteStatus
                .tagLevelUnsynchronisationUnsupported;
    }

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
     * Whole-tag-unsynchronised sources are already blocked above.
     *
     * Therefore this physical source region is also the ordinary byte
     * capacity available to the newly serialized frame sequence.
     */
    const originalCapacity =
        source.body.framesAndPadding.length;

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
         * With unsynchronisation blocked, logical and physical extended
         * header lengths are identical.
         *
         * Using logicalLength also describes the size of a regenerated
         * representation directly.
         */
        result.extendedHeaderLength =
            source.body.extendedHeader
                .logicalLength;

        const sourcePaddingLength =
            cast(size_t)
                source.body.extendedHeader
                    .paddingSize;

        if (
            result.paddingLength ==
            sourcePaddingLength
        )
        {
            result.extendedHeaderAction =
                Id3v23ExtendedHeaderWriteAction
                    .preserveOriginal;
        }
        else
        {
            /*
             * The ID3v2.3 extended header contains the padding-size
             * value itself. Keeping the old bytes here would create a
             * structurally inconsistent tag.
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

    /*
     * Until whole-tag unsynchronisation is integrated into physical body
     * serialization, logical and physical body lengths remain identical.
     */
    result.tagSize =
        cast(uint)
            result.logicalBodyLength;

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
    assert(plan.tagSize == 20);
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
    assert(plan.tagSize == 25);
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
    assert(plan.tagSize == 20);
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
    assert(plan.tagSize == 24);
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
    assert(plan.tagSize == 24);
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
    assert(plan.tagSize == 27);
}


/// Global source unsynchronisation remains blocked at the body layer.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x80,

            /*
             * One ordinary eleven-byte frame. Nothing here requires
             * stuffing, but the source tag still carries the global flag.
             */
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
            11,
            false
        );

    assert(
        plan.status ==
        Id3v23TagBodyWriteStatus
            .tagLevelUnsynchronisationUnsupported
    );

    assert(!plan.writable);
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
