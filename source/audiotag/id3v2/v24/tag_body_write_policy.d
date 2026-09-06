/++
ID3v2.4 tag-body write policy.

This module decides how an already serialized frame sequence fits into
the body of an existing provenance-preserved tag.

No bytes are emitted here.

Current conservative policy:

Padding:
- with a footer: always zero, as required by ID3v2.4;
- without a footer: preserve the original frames-plus-padding capacity
  when the new frame sequence fits inside it;
- if the new sequence exceeds that capacity, padding becomes zero and
  the tag body grows.

Extended header:
- absent remains absent;
- an existing extended header is preserved byte-for-byte;
- an existing CRC blocks a changed frame sequence until CRC generation
  is implemented;
- existing restrictions block a changed frame sequence until the writer
  can validate the resulting tag against those restrictions.

Global tag-level unsynchronisation:
- currently unsupported for body reconstruction because the frame
  sequence writer deliberately emits ordinary non-global-unsynchronised
  output.

Footer:
- footer presence is retained from the source tag;
- footer bytes themselves are serialized by the outer tag writer.

The resulting tag size includes the optional extended header, complete
frame sequence and padding. It excludes the fixed ten-byte tag header
and optional ten-byte footer.
+/
module audiotag.id3v2.v24.tag_body_write_policy;

import audiotag.id3v2.v24.structure :
    Id3v24TagStructure;


/++
Primary structural status of tag-body planning.

CRC and restriction blockers are retained separately so both may be
reported simultaneously.
+/
enum Id3v24TagBodyWriteStatus : ubyte
{
    ready,

    /// The active strict reader does not accept a frame-less tag body.
    emptyFrameSequence,

    /// Whole-tag byte unsynchronisation writing is not implemented yet.
    tagLevelUnsynchronisationUnsupported,

    /// Resulting body size exceeds the 28-bit synchsafe tag-size domain.
    tagSizeOverflow
}


/++
Treatment of the source extended header.
+/
enum Id3v24ExtendedHeaderWriteAction : ubyte
{
    /// No extended header exists in the source tag.
    absent,

    /// Copy the complete original extended-header bytes unchanged.
    preserveOriginal
}


/++
Complete policy plan for one resulting ID3v2.4 tag body.
+/
struct Id3v24TagBodyWritePlan
{
    /// Primary structural planning status.
    Id3v24TagBodyWriteStatus status;

    /// How the optional source extended header is handled.
    Id3v24ExtendedHeaderWriteAction extendedHeaderAction;

    /// Number of extended-header bytes in the resulting body.
    size_t extendedHeaderLength;

    /// Number of already serialized native frame bytes.
    size_t frameSequenceLength;

    /// Number of trailing zero padding bytes to emit.
    size_t paddingLength;

    /// Final ID3 header tag-size value when representable.
    uint tagSize;

    /// Whether the resulting outer tag retains a footer.
    bool footerPresent;

    /// A source CRC would become stale after frame-sequence modification.
    bool crcBlocksChange;

    /// Source restrictions require validation before changed output.
    bool restrictionsBlockChange;

    /++
    Returns whether body serialization may proceed.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            status ==
                Id3v24TagBodyWriteStatus.ready &&
            !crcBlocksChange &&
            !restrictionsBlockChange;
    }
}


/++
Plans one resulting tag body around an already serialized frame sequence.

`frameSequenceChanged` describes physical change relative to the source
native frame sequence. It must be true not only for canonical edits but
also when preservation policy discards or otherwise changes native
frames.

The original frames-plus-padding region acts as capacity when no footer
exists. This means shrinking a frame sequence increases padding and
moderate growth consumes padding before increasing the tag body size.

Params:
    source = Strictly validated source tag structure.
    frameSequenceLength = Number of bytes in the resulting frame sequence.
    frameSequenceChanged = Whether resulting frame bytes differ from the
        source frame sequence.

Returns:
    Explicit body policy plan.
+/
Id3v24TagBodyWritePlan
planId3v24TagBodyWrite(
    const(Id3v24TagStructure) source,
    size_t frameSequenceLength,
    bool frameSequenceChanged
)
    @safe pure nothrow @nogc
{
    enum size_t maximumTagSize =
        0x0FFF_FFFF;

    auto result =
        Id3v24TagBodyWritePlan.init;

    result.status =
        Id3v24TagBodyWriteStatus.ready;

    result.frameSequenceLength =
        frameSequenceLength;

    result.footerPresent =
        source.envelope.header.hasFooter;

    if (source.body.hasExtendedHeader)
    {
        result.extendedHeaderAction =
            Id3v24ExtendedHeaderWriteAction
                .preserveOriginal;

        result.extendedHeaderLength =
            source.body.extendedHeader.raw.length;

        if (frameSequenceChanged)
        {
            result.crcBlocksChange =
                source.body.extendedHeader.hasCrc;

            result.restrictionsBlockChange =
                source.body.extendedHeader
                    .hasRestrictions;
        }
    }
    else
    {
        result.extendedHeaderAction =
            Id3v24ExtendedHeaderWriteAction.absent;

        result.extendedHeaderLength = 0;
    }

    /*
     * Keep computing the descriptive parts of the plan even when one of
     * the following structural blockers is found.
     */
    if (frameSequenceLength == 0)
    {
        result.status =
            Id3v24TagBodyWriteStatus
                .emptyFrameSequence;
    }
    else if (
        source.envelope.header
            .unsynchronisation
    )
    {
        result.status =
            Id3v24TagBodyWriteStatus
                .tagLevelUnsynchronisationUnsupported;
    }

    if (result.footerPresent)
    {
        /*
         * ID3v2.4 forbids padding when a footer exists.
         */
        result.paddingLength = 0;
    }
    else
    {
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
    }

    /*
     * Calculate without overflowing size_t and without constructing a
     * value outside the 28-bit ID3 synchsafe tag-size domain.
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
            Id3v24TagBodyWriteStatus
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
            Id3v24TagBodyWriteStatus
                .tagSizeOverflow;

        return result;
    }

    const totalBodyLength =
        withoutPadding +
        result.paddingLength;

    result.tagSize =
        cast(uint)
            totalBodyLength;

    return result;
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.structure :
        parseId3v24TagStructure;


    private Id3v24TagStructure parseTestTag(
        const(ubyte)[] bytes
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto parsed =
            cursor.parseId3v24TagStructure();

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
            0x04, 0x00,
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
        planId3v24TagBodyWrite(
            source,
            15,
            true
        );

    assert(plan.writable);

    assert(
        plan.extendedHeaderAction ==
        Id3v24ExtendedHeaderWriteAction.absent
    );

    assert(plan.frameSequenceLength == 15);
    assert(plan.paddingLength == 5);
    assert(plan.tagSize == 20);
    assert(!plan.footerPresent);
}


/// Growth beyond old capacity drops padding and expands the body.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
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
        planId3v24TagBodyWrite(
            source,
            25,
            true
        );

    assert(plan.writable);
    assert(plan.paddingLength == 0);
    assert(plan.tagSize == 25);
}


/// Shrinking frames converts unused source capacity into padding.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
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
        planId3v24TagBodyWrite(
            source,
            11,
            false
        );

    assert(plan.writable);

    assert(plan.paddingLength == 9);
    assert(plan.tagSize == 20);
}


/// Footer tags never receive padding.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x10,

            0x00, 0x00, 0x00, 0x0B,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            '3', 'D', 'I',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x0B
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v24TagBodyWrite(
            source,
            14,
            true
        );

    assert(plan.writable);
    assert(plan.footerPresent);
    assert(plan.paddingLength == 0);
    assert(plan.tagSize == 14);
}


/// A simple extended header may be preserved across frame changes.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,

            // Extended header 6 + frame/padding 14 = 20.
            0x00, 0x00, 0x00, 0x14,

            // Minimal extended header.
            0x00, 0x00, 0x00, 0x06,
            0x01,
            0x00,

            // Eleven-byte frame.
            'T', 'A', 'L', 'B',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            // Three padding bytes.
            0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v24TagBodyWrite(
            source,
            12,
            true
        );

    assert(plan.writable);

    assert(
        plan.extendedHeaderAction ==
        Id3v24ExtendedHeaderWriteAction
            .preserveOriginal
    );

    assert(plan.extendedHeaderLength == 6);
    assert(plan.paddingLength == 2);
    assert(plan.tagSize == 20);
}


/// A changed sequence makes an existing CRC explicitly stale.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,

            // Extended header 12 + frame 11 = 23.
            0x00, 0x00, 0x00, 0x17,

            // CRC extended header, size 12.
            0x00, 0x00, 0x00, 0x0C,
            0x01,
            0x20,

            // CRC data length.
            0x05,

            // CRC = 1.
            0x00, 0x00, 0x00, 0x00, 0x01,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v24TagBodyWrite(
            source,
            11,
            true
        );

    assert(
        plan.status ==
        Id3v24TagBodyWriteStatus.ready
    );

    assert(plan.crcBlocksChange);
    assert(!plan.restrictionsBlockChange);
    assert(!plan.writable);
}


/// An unchanged sequence may retain an opaque source CRC byte-for-byte.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,
            0x00, 0x00, 0x00, 0x17,

            0x00, 0x00, 0x00, 0x0C,
            0x01,
            0x20,
            0x05,
            0x00, 0x00, 0x00, 0x00, 0x01,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v24TagBodyWrite(
            source,
            11,
            false
        );

    assert(plan.writable);
    assert(!plan.crcBlocksChange);

    assert(
        plan.extendedHeaderLength ==
        12
    );

    assert(plan.tagSize == 23);
}


/// Restrictions block changed output until they can be validated.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,

            // Extended header 8 + frame 11 = 19.
            0x00, 0x00, 0x00, 0x13,

            // Restrictions extended header.
            0x00, 0x00, 0x00, 0x08,
            0x01,
            0x10,
            0x01,
            0xA5,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v24TagBodyWrite(
            source,
            11,
            true
        );

    assert(!plan.crcBlocksChange);
    assert(plan.restrictionsBlockChange);
    assert(!plan.writable);
}


/// Global source unsynchronisation remains blocked at the body layer.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x80,

            0x00, 0x00, 0x00, 0x0B,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const source =
        parseTestTag(bytes);

    const plan =
        planId3v24TagBodyWrite(
            source,
            11,
            false
        );

    assert(
        plan.status ==
        Id3v24TagBodyWriteStatus
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
            0x04, 0x00,
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
        planId3v24TagBodyWrite(
            source,
            0,
            true
        );

    assert(
        plan.status ==
        Id3v24TagBodyWriteStatus
            .emptyFrameSequence
    );

    assert(!plan.writable);
}


/// Resulting bodies must fit the ID3v2.4 28-bit size field.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
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
        planId3v24TagBodyWrite(
            source,
            0x1000_0000,
            true
        );

    assert(
        plan.status ==
        Id3v24TagBodyWriteStatus
            .tagSizeOverflow
    );

    assert(!plan.writable);
}
