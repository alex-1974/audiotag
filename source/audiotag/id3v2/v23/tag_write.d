/++
Physical execution of one complete planned ID3v2.3 tag write.

This module composes the existing writer layers:

1. execute the planned native frame sequence;
2. compare the resulting frame bytes with the preserved source sequence;
3. plan the tag body from that actual physical change state;
4. serialize the body;
5. serialize a header with the resulting physical body size;
6. concatenate the complete tag.

No container/file update is performed here.

Current lower-layer limitations remain explicit, including:

- changed CRC-bearing extended headers are rejected;
- only currently implemented canonical frame serializer families are
  writable.

Source whole-tag unsynchronisation is treated as physical provenance.
Preserved source frames are reconstructed in the logical/native byte
domain, and the complete resulting logical body independently determines
whether whole-tag unsynchronisation is required for output.

The outer result preserves parser errors that can occur while recovering
structural information from a preserved native frame during regeneration.
The inner result represents writer/planner/output failures.
+/
module audiotag.id3v2.v23.tag_write;

import audiotag.core.result :
    ParseResult;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.metadata.edit :
    MetadataTreeEdit;

import audiotag.id3v2.v23.canonical_projection :
    Id3v23CanonicalProjection;

import audiotag.id3v2.v23.frame_sequence_write :
    serializeId3v23PlannedFrameSequence;

import audiotag.id3v2.v23.header :
    Id3v23Header;

import audiotag.id3v2.v23.structure :
    Id3v23TagStructure;

import audiotag.id3v2.v23.tag_body_write :
    serializeId3v23TagBody;

import audiotag.id3v2.v23.tag_body_write_policy :
    Id3v23ExtendedHeaderWriteAction,
    Id3v23TagBodyWritePlan,
    planId3v23TagBodyWrite;

import audiotag.id3v2.v23.tag_header_write :
    serializeId3v23Header;

import audiotag.id3v2.v23.tag_write_plan :
    Id3v23TagWritePlan;

import audiotag.id3v2.v23.unsync_write :
    requiresId3v23Unsynchronisation,
    serializeId3v23UnsynchronisedBytes;


/++
Result of complete planned ID3v2.3 tag serialization.
+/
alias Id3v23TagSerializationResult =
    ParseResult!(
        SerializationResult!(ubyte[])
    );


/++
Wraps a writer failure without converting it into malformed source input.
+/
private Id3v23TagSerializationResult
writerFailure(
    SerializationError error
)
    @safe
{
    return
        Id3v23TagSerializationResult
            .success(
                SerializationResult!(ubyte[])
                    .failure(error)
            );
}


/++
Serializes one complete ID3v2.3 tag from a semantic write plan.

`source`, `projection`, `edit` and `plan` must describe the same source
tag and edit operation.

The function does not require a caller-supplied change indicator.
After frame-sequence execution it compares the actual output bytes with
`source.frames.frameBytes`. This physical comparison determines whether
an existing extended-header CRC would become stale and whether body
padding must be adjusted.

The source revision and defined header flags are retained. `tagSize` is
recomputed from the resulting physical body.

For ID3v2.3 an extended header remains present both when it can be copied
byte-for-byte and when it must be regenerated solely to update its
stored padding-size field.

Params:
    source = Strict structural representation of the source tag.
    projection = Provenance-preserving canonical projection of its frames.
    edit = Canonical edit overlay used to construct `plan`.
    plan = Complete semantic write plan.

Returns:
    Complete owned ID3v2.3 tag bytes, an outer source-parse failure, or
    an inner writer failure.
+/
/++
Materializes the validated source frame sequence in logical/native form.

For an ordinary source this is byte-identical to `frameBytes`.

For a whole-tag-unsynchronised source, physical stuffing is removed.
This provides the correct comparison domain for the newly assembled
logical/native frame sequence.
+/
private ParseResult!(ubyte[])
materializeLogicalSourceFrameSequence(
    const(Id3v23TagStructure) source
)
    @safe
{
    auto cursor =
        source.frameCursor();

    /*
     * Physical length is an upper bound on logical length because
     * whole-tag unsynchronisation only inserts bytes.
     */
    auto output =
        new ubyte[
            source.frames.frameBytes.length
        ];

    size_t position;

    while (!cursor.empty)
    {
        auto decoded =
            cursor.takeByte();

        if (decoded.hasError)
        {
            return
                ParseResult!(ubyte[])
                    .failure(
                        decoded.error
                    );
        }

        assert(position < output.length);

        output[position] =
            decoded.value.value;

        ++position;
    }

    output.length =
        position;

    return
        ParseResult!(ubyte[])
            .success(output);
}


Id3v23TagSerializationResult
serializeId3v23PlannedTag(
    const(Id3v23TagStructure) source,
    const(Id3v23CanonicalProjection) projection,
    const(MetadataTreeEdit) edit,
    const(Id3v23TagWritePlan) plan
)
    @safe
{
    if (
        projection.frameCount !=
        source.frameCount
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    0,
                    projection.frameCount,
                    source.frameCount
                )
            );
    }

    auto assembled =
        serializeId3v23PlannedFrameSequence(
            projection,
            edit,
            plan,
            source.envelope.header
                .unsynchronisation
        );

    if (assembled.hasError)
    {
        return
            Id3v23TagSerializationResult
                .failure(
                    assembled.error
                );
    }

    auto frameSequenceResult =
        assembled.value;

    if (frameSequenceResult.hasError)
    {
        return
            writerFailure(
                frameSequenceResult.error
            );
    }

    const frameSequence =
        frameSequenceResult.value;

    /*
     * Compare like with like.
     *
     * `frameSequence` is logical/native output. For an unsynchronised
     * source, `source.frames.frameBytes` still contains physical stuffing,
     * so reconstruct its logical/native representation before deriving
     * actual change.
     *
     * This also catches native policy changes such as discarding an
     * unmapped frame even when no canonical source field was edited.
     */
    auto sourceFrameSequenceResult =
        materializeLogicalSourceFrameSequence(
            source
        );

    if (sourceFrameSequenceResult.hasError)
    {
        return
            Id3v23TagSerializationResult
                .failure(
                    sourceFrameSequenceResult.error
                );
    }

    const sourceFrameSequence =
        sourceFrameSequenceResult.value;

    const frameSequenceChanged =
        frameSequence !=
        sourceFrameSequence;

    Id3v23TagBodyWritePlan bodyPlan =
        planId3v23TagBodyWrite(
            source,
            frameSequence.length,
            frameSequenceChanged
        );

    auto bodyResult =
        serializeId3v23TagBody(
            source,
            bodyPlan,
            frameSequence
        );

    if (bodyResult.hasError)
    {
        return
            writerFailure(
                bodyResult.error
            );
    }

    const(ubyte)[] logicalBody =
        bodyResult.value;

    assert(
        logicalBody.length ==
        bodyPlan.logicalBodyLength
    );

    /*
     * ID3v2.3 activates whole-tag unsynchronisation only when the
     * resulting logical body contains a false MPEG synchronisation.
     *
     * Once active, the transformation is applied to the complete body,
     * including extended-header bytes, frame headers, frame payloads and
     * padding boundaries.
     */
    const unsynchronisationRequired =
        requiresId3v23Unsynchronisation(
            logicalBody
        );

    /*
     * ID3v2.3 requires at least one padding byte when unsynchronisation is
     * needed elsewhere and the logical tag would otherwise end in FF.
     *
     * This must be real logical padding, not merely an inserted stuffing
     * byte. If an extended header exists, its stored padding-size field
     * must therefore be regenerated as well.
     */
    if (
        unsynchronisationRequired &&
        logicalBody.length != 0 &&
        logicalBody[$ - 1] == 0xFF &&
        bodyPlan.paddingLength == 0
    )
    {
        if (
            bodyPlan.logicalBodyLength >=
            0x0FFF_FFFF
        )
        {
            return
                writerFailure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        6,
                        bodyPlan.logicalBodyLength + 1,
                        0x0FFF_FFFF
                    )
                );
        }

        ++bodyPlan.paddingLength;
        ++bodyPlan.logicalBodyLength;

        if (
            bodyPlan.extendedHeaderAction !=
            Id3v23ExtendedHeaderWriteAction.absent
        )
        {
            bodyPlan.extendedHeaderAction =
                Id3v23ExtendedHeaderWriteAction
                    .regenerate;
        }

        auto adjustedBodyResult =
            serializeId3v23TagBody(
                source,
                bodyPlan,
                frameSequence
            );

        if (adjustedBodyResult.hasError)
        {
            return
                writerFailure(
                    adjustedBodyResult.error
                );
        }

        logicalBody =
            adjustedBodyResult.value;

        assert(
            logicalBody.length ==
            bodyPlan.logicalBodyLength
        );

        assert(
            logicalBody[$ - 1] ==
            0x00
        );
    }

    const(ubyte)[] body;

    if (unsynchronisationRequired)
    {
        auto unsynchronised =
            serializeId3v23UnsynchronisedBytes(
                logicalBody
            );

        if (unsynchronised.hasError)
        {
            return
                writerFailure(
                    unsynchronised.error
                );
        }

        body =
            unsynchronised.value;
    }
    else
    {
        body =
            logicalBody;
    }

    /*
     * tagSize describes the physical stored body after whole-tag
     * unsynchronisation.
     */
    if (
        body.length >
        0x0FFF_FFFF
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .valueOutOfRange,
                    6,
                    body.length,
                    0x0FFF_FFFF
                )
            );
    }

    const physicalTagSize =
        cast(uint)
            body.length;

    ubyte outputFlags =
        cast(ubyte)
            (
                source.envelope.header.flags &
                0x7F
            );

    if (unsynchronisationRequired)
    {
        outputFlags =
            cast(ubyte)
                (
                    outputFlags |
                    0x80
                );
    }

    /*
     * Construct a fresh mutable output header explicitly.
     *
     * Source offset is provenance only and is not part of serialization.
     */
    Id3v23Header outputHeader =
        Id3v23Header(
            0,
            source.envelope.header.revision,
            outputFlags,
            physicalTagSize
        );

    /*
     * In v2.3 both preservation and regeneration mean that an extended
     * header is physically present in the resulting body.
     */
    const extendedHeaderPresent =
        bodyPlan.extendedHeaderAction !=
        Id3v23ExtendedHeaderWriteAction.absent;

    if (
        outputHeader.hasExtendedHeader !=
        extendedHeaderPresent
    )
    {
        return
            writerFailure(
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    5,
                    outputHeader.flags
                )
            );
    }

    auto headerResult =
        serializeId3v23Header(
            outputHeader
        );

    if (headerResult.hasError)
    {
        return
            writerFailure(
                headerResult.error
            );
    }

    auto output =
        new ubyte[
            headerResult.value.length +
            body.length
        ];

    size_t position;

    output[
        position ..
        position + headerResult.value.length
    ] =
        headerResult.value[];

    position +=
        headerResult.value.length;

    output[
        position ..
        position + body.length
    ] =
        body;

    position +=
        body.length;

    assert(position == output.length);

    return
        Id3v23TagSerializationResult
            .success(
                SerializationResult!(ubyte[])
                    .success(output)
            );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.metadata.field :
        MetadataField,
        MetadataKey;

    import audiotag.metadata.value :
        MetadataText,
        MetadataValue;

    import audiotag.id3v2.v23.canonical_mapping :
        Id3v23CanonicalMappingResult;

    import audiotag.id3v2.v23.frame :
        Id3v23FrameEnvelope,
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrame,
        Id3v23NativeFrameContent,
        Id3v23UnknownFrame;

    import audiotag.id3v2.v23.structure :
        parseId3v23TagStructure;

    import audiotag.id3v2.v23.tag_write_plan :
        planId3v23CanonicalTagWrite;

    import audiotag.id3v2.v23.writer_policy :
        Id3v23WriteContext;


    private MetadataField textField(
        string key,
        string value
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataText(value);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
    }


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


    private Id3v23NativeFrame
    nativeFromEnvelope(
        Id3v23FrameEnvelope envelope
    )
        @safe
    {
        Id3v23NativeFrameContent content =
            Id3v23UnknownFrame();

        return
            Id3v23NativeFrame(
                envelope,
                content
            );
    }


    private Id3v23FrameEnvelope
    onlySourceFrame(
        const(Id3v23TagStructure) source
    )
        @safe
    {
        auto cursor =
            source.frameCursor();

        auto frame =
            cursor.parseId3v23FrameEnvelope();

        assert(frame.hasValue);
        assert(cursor.empty);

        return frame.value;
    }
}


/// An unchanged unsupported frame allows exact complete-tag reproduction.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            // Body = one eleven-byte frame.
            0x00, 0x00, 0x00, 0x0B,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0xAA
        ];

    const source =
        parseTestTag(sourceBytes);

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromEnvelope(
            onlySourceFrame(source)
        ),
        Id3v23CanonicalMappingResult
            .unsupported()
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);

    auto serialized =
        written.value;

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        sourceBytes
    );
}


/// Regeneration updates both frame size and outer tag size.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            // TIT2 frame = 10 header + 4 payload = 14.
            0x00, 0x00, 0x00, 0x0E,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
            'O', 'l', 'd'
        ];

    const source =
        parseTestTag(sourceBytes);

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromEnvelope(
            onlySourceFrame(source)
        ),
        Id3v23CanonicalMappingResult
            .success(
                textField(
                    "title",
                    "Old"
                )
            )
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        textField(
            "title",
            "Longer"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);
    assert(written.value.hasValue);

    /*
     * New payload:
     *
     *   00 "Longer"
     *
     * = 7 bytes, so frame/body size = 17.
     */
    assert(
        written.value.value ==
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x11,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x07,
            0x00, 0x00,

            0x00,
            'L', 'o', 'n', 'g', 'e', 'r'
        ]
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                written.value.value[]
            )
        );

    auto reparsed =
        cursor.parseId3v23TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(
        reparsed.value.envelope.header
            .tagSize ==
        17
    );

    assert(reparsed.value.frameCount == 1);
}


/// Changed padding regenerates the v2.3 extended header in a complete tag.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            // Extended-header flag.
            0x40,

            /*
             * 10 extended-header bytes
             * 12 frame bytes
             *  3 padding bytes
             * = 25 body bytes.
             */
            0x00, 0x00, 0x00, 0x19,

            // Extended header: size = 6.
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            // Source padding size = 3.
            0x00, 0x00, 0x00, 0x03,

            // TIT2 payload = 00 "X".
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x00, 'X',

            0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromEnvelope(
            onlySourceFrame(source)
        ),
        Id3v23CanonicalMappingResult
            .success(
                textField(
                    "title",
                    "X"
                )
            )
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    /*
     * One additional payload byte grows the frame from 12 to 13 bytes.
     * Existing capacity therefore leaves two padding bytes.
     */
    edit.replaceSourceField(
        0,
        textField(
            "title",
            "YY"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);
    assert(written.value.hasValue);

    const serialized =
        written.value.value;

    /*
     * Overall body capacity remains 25 bytes.
     */
    assert(serialized.length == 35);

    assert(
        serialized[6 .. 10] ==
        [0x00, 0x00, 0x00, 0x19]
    );

    /*
     * Regenerated extended-header padding size = 2.
     */
    assert(
        serialized[16 .. 20] ==
        [0x00, 0x00, 0x00, 0x02]
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized[]
            )
        );

    auto reparsed =
        cursor.parseId3v23TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(
        reparsed.value.body
            .extendedHeader
            .paddingSize ==
        2
    );

    assert(
        reparsed.value.frames.padding.length ==
        2
    );

    assert(
        reparsed.value.envelope.header
            .tagSize ==
        25
    );
}


/// An unchanged whole-tag-unsynchronised source roundtrips stably.
unittest
{
    /*
     * Logical payload:
     *
     *   FF E1
     *
     * Physical source payload:
     *
     *   FF 00 E1
     */
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            // Whole-tag unsynchronisation.
            0x80,

            // Physical body size = 13.
            0x00, 0x00, 0x00, 0x0D,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0xFF, 0x00, 0xE1
        ];

    const source =
        parseTestTag(sourceBytes);

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromEnvelope(
            onlySourceFrame(source)
        ),
        Id3v23CanonicalMappingResult
            .unsupported()
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);
    assert(written.value.hasValue);

    /*
     * Logical preservation followed by one fresh whole-tag
     * unsynchronisation pass reproduces this canonical physical source.
     */
    assert(
        written.value.value ==
        sourceBytes
    );

    const reparsed =
        parseTestTag(
            written.value.value
        );

    assert(
        reparsed.envelope.header
            .unsynchronisation
    );

    assert(
        reparsed.envelope.header
            .tagSize ==
        13
    );

    assert(reparsed.frameCount == 1);
    assert(reparsed.frames.padding.empty);
}


/// Projection/source frame-count disagreement is rejected defensively.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x0B,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        Id3v23CanonicalProjection.init;

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);

    auto serialized =
        written.value;

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );
}



/// A false MPEG synchronisation activates whole-tag unsynchronisation.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            // One 13-byte frame.
            0x00, 0x00, 0x00, 0x0D,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0x10,
            0xFF, 0xE1
        ];

    const source =
        parseTestTag(sourceBytes);

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromEnvelope(
            onlySourceFrame(source)
        ),
        Id3v23CanonicalMappingResult
            .unsupported()
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);
    assert(written.value.hasValue);

    assert(
        written.value.value ==
        [
            'I', 'D', '3',
            0x03, 0x00,

            // Whole-tag unsynchronisation.
            0x80,

            // Physical body grew from 13 to 14 bytes.
            0x00, 0x00, 0x00, 0x0E,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0x10,
            0xFF, 0x00, 0xE1
        ]
    );

    const reparsed =
        parseTestTag(
            written.value.value
        );

    assert(
        reparsed.envelope.header
            .unsynchronisation
    );

    assert(
        reparsed.envelope.header
            .tagSize ==
        14
    );

    assert(reparsed.frameCount == 1);
    assert(reparsed.frames.padding.empty);
}


/// FF 00 alone does not activate whole-tag unsynchronisation.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x0C,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0xFF, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromEnvelope(
            onlySourceFrame(source)
        ),
        Id3v23CanonicalMappingResult
            .unsupported()
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);
    assert(written.value.hasValue);

    assert(
        written.value.value ==
        sourceBytes
    );
}


/// Active whole-tag unsynchronisation also protects logical FF 00 data.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x0E,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0xFF, 0xE1,
            0xFF, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromEnvelope(
            onlySourceFrame(source)
        ),
        Id3v23CanonicalMappingResult
            .unsupported()
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);
    assert(written.value.hasValue);

    const serialized =
        written.value.value;

    assert(serialized[5] == 0x80);

    /*
     * Two stuffing bytes were inserted:
     *
     *   FF E1 -> FF 00 E1
     *   FF 00 -> FF 00 00
     */
    assert(
        serialized[6 .. 10] ==
        [0x00, 0x00, 0x00, 0x10]
    );

    const reparsed =
        parseTestTag(serialized);

    assert(reparsed.frameCount == 1);
    assert(reparsed.frames.padding.empty);

    auto frames =
        reparsed.frameCursor();

    auto frame =
        frames.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 4);
    assert(frames.empty);
}


/// A terminal FF gains real logical padding before unsynchronisation.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x0D,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0xFF, 0xE1,
            0xFF
        ];

    const source =
        parseTestTag(sourceBytes);

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromEnvelope(
            onlySourceFrame(source)
        ),
        Id3v23CanonicalMappingResult
            .unsupported()
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);
    assert(written.value.hasValue);

    const serialized =
        written.value.value;

    assert(serialized[5] == 0x80);

    /*
     * Logical body:
     *
     *   13 frame bytes + 1 padding byte = 14
     *
     * Two stuffing bytes are then inserted physically.
     */
    assert(
        serialized[6 .. 10] ==
        [0x00, 0x00, 0x00, 0x10]
    );

    assert(
        serialized[$ - 6 .. $] ==
        [
            0xFF, 0x00, 0xE1,
            0xFF, 0x00,
            0x00
        ]
    );

    const reparsed =
        parseTestTag(serialized);

    assert(
        reparsed.envelope.header
            .tagSize ==
        16
    );

    assert(
        reparsed.frames.padding.length ==
        1
    );

    assert(
        reparsed.frames.frameBytes.length ==
        15
    );
}


/// Terminal-padding insertion regenerates an existing extended header.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            // Extended header.
            0x40,

            // 10-byte extended header + 13-byte frame.
            0x00, 0x00, 0x00, 0x17,

            // Extended-header size = 6.
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            // Source padding size = 0.
            0x00, 0x00, 0x00, 0x00,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0xFF, 0xE1,
            0xFF
        ];

    const source =
        parseTestTag(sourceBytes);

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromEnvelope(
            onlySourceFrame(source)
        ),
        Id3v23CanonicalMappingResult
            .unsupported()
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);
    assert(written.value.hasValue);

    const serialized =
        written.value.value;

    /*
     * Extended header + unsynchronisation.
     */
    assert(serialized[5] == 0xC0);

    /*
     * Logical body:
     *
     *   10 extended-header bytes
     *   13 frame bytes
     *    1 padding byte
     * = 24
     *
     * Two stuffing bytes -> physical size 26.
     */
    assert(
        serialized[6 .. 10] ==
        [0x00, 0x00, 0x00, 0x1A]
    );

    const reparsed =
        parseTestTag(serialized);

    assert(
        reparsed.body.extendedHeader
            .paddingSize ==
        1
    );

    assert(
        reparsed.frames.padding.length ==
        1
    );

    assert(
        reparsed.envelope.header
            .tagSize ==
        26
    );
}


/// An unchanged unsynchronised CRC-bearing source keeps its CRC valid.
unittest
{
    /*
     * Logical body:
     *
     *   14-byte CRC extended header
     *   12-byte unknown frame with payload FF E1
     *
     * Whole-tag unsynchronisation expands the frame payload physically:
     *
     *   FF E1 -> FF 00 E1
     *
     * Logical body size  = 26
     * Physical body size = 27
     */
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            // Unsynchronisation + extended header.
            0xC0,

            // Physical body size = 27.
            0x00, 0x00, 0x00, 0x1B,

            // Extended-header size = 10.
            0x00, 0x00, 0x00, 0x0A,

            // CRC present.
            0x80, 0x00,

            // Padding size = 0.
            0x00, 0x00, 0x00, 0x00,

            // Existing CRC.
            0x12, 0x34, 0x56, 0x78,

            // Unknown preserved frame.
            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            // Logical FF E1 with physical stuffing.
            0xFF, 0x00, 0xE1
        ];

    const source =
        parseTestTag(sourceBytes);

    assert(
        source.envelope.header
            .unsynchronisation
    );

    assert(
        source.body.extendedHeader
            .hasCrc
    );

    assert(
        source.body.extendedHeader
            .crc32 ==
        0x1234_5678
    );

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromEnvelope(
            onlySourceFrame(source)
        ),
        Id3v23CanonicalMappingResult
            .unsupported()
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);
    assert(written.value.hasValue);

    /*
     * The source physical stuffing must not be mistaken for a logical
     * frame change. Reconstructing the same logical body and applying one
     * fresh whole-tag unsynchronisation pass reproduces the source.
     */
    assert(
        written.value.value ==
        sourceBytes
    );

    const reparsed =
        parseTestTag(
            written.value.value
        );

    assert(
        reparsed.body.extendedHeader
            .hasCrc
    );

    assert(
        reparsed.body.extendedHeader
            .crc32 ==
        0x1234_5678
    );

    assert(
        reparsed.envelope.header
            .unsynchronisation
    );

    assert(
        reparsed.envelope.header
            .tagSize ==
        27
    );
}


/// A logical frame change still invalidates an unsynchronised source CRC.
unittest
{
    /*
     * The first frame exists only to require source whole-tag
     * unsynchronisation.
     *
     * The second frame is a mapped TIT2 frame which will be changed while
     * the source extended header contains a CRC.
     */
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            // Unsynchronisation + extended header.
            0xC0,

            /*
             * Physical body:
             *
             *   14 extended header
             *   13 first physical frame
             *   14 TIT2 frame
             * = 41
             */
            0x00, 0x00, 0x00, 0x29,

            // Extended-header size = 10.
            0x00, 0x00, 0x00, 0x0A,

            // CRC present.
            0x80, 0x00,

            // Padding size = 0.
            0x00, 0x00, 0x00, 0x00,

            // Existing CRC.
            0x12, 0x34, 0x56, 0x78,

            // First frame: logical payload FF E1.
            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            // Physical whole-tag-unsynchronised representation.
            0xFF, 0x00, 0xE1,

            // Second frame: TIT2 = "Old".
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
            'O', 'l', 'd'
        ];

    const source =
        parseTestTag(sourceBytes);

    assert(source.frameCount == 2);

    auto frames =
        source.frameCursor();

    auto first =
        frames.parseId3v23FrameEnvelope();

    assert(first.hasValue);

    auto second =
        frames.parseId3v23FrameEnvelope();

    assert(second.hasValue);
    assert(frames.empty);

    auto projection =
        Id3v23CanonicalProjection.init;

    projection.append(
        nativeFromEnvelope(
            first.value
        ),
        Id3v23CanonicalMappingResult
            .unsupported()
    );

    projection.append(
        nativeFromEnvelope(
            second.value
        ),
        Id3v23CanonicalMappingResult
            .success(
                textField(
                    "title",
                    "Old"
                )
            )
    );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    /*
     * There is exactly one canonical source field. It belongs to the
     * second native frame.
     *
     * Keep the replacement the same length so this test isolates CRC
     * invalidation rather than body-capacity changes.
     */
    edit.replaceSourceField(
        0,
        textField(
            "title",
            "New"
        )
    );

    const plan =
        planId3v23CanonicalTagWrite(
            projection,
            edit,
            Id3v23WriteContext.tagOnly()
        );

    /*
     * Semantic/native planning itself is valid. The later body policy is
     * responsible for rejecting reuse of a stale source CRC.
     */
    assert(plan.writable);

    auto written =
        serializeId3v23PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);
    assert(written.value.hasError);

    assert(
        written.value.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
