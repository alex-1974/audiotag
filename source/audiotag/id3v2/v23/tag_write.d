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

- whole-tag unsynchronisation writing is not implemented;
- changed CRC-bearing extended headers are rejected;
- only currently implemented canonical frame serializer families are
  writable.

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
    planId3v23TagBodyWrite;

import audiotag.id3v2.v23.tag_header_write :
    serializeId3v23Header;

import audiotag.id3v2.v23.tag_write_plan :
    Id3v23TagWritePlan;


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
     * Derive physical change from actual output rather than from edit
     * intent.
     *
     * This also catches native policy changes such as discarding an
     * unmapped frame even when no canonical source field was edited.
     */
    const frameSequenceChanged =
        frameSequence !=
        source.frames.frameBytes.data;

    const bodyPlan =
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

    const body =
        bodyResult.value;

    /*
     * The body serializer already validates this relationship. Retain it
     * here as the central outer-tag representation invariant.
     */
    assert(
        body.length ==
        bodyPlan.logicalBodyLength
    );

    /*
     * The body writer currently returns the stored body directly because
     * whole-tag unsynchronisation is still blocked.
     *
     * Derive the physical header size here rather than carrying it in the
     * logical body plan. Once whole-tag unsynchronisation is integrated,
     * this value will instead be taken from the transformed body.
     */
    assert(
        body.length <=
        0x0FFF_FFFF
    );

    const physicalTagSize =
        cast(uint)
            body.length;

    /*
     * Construct a fresh mutable output header explicitly.
     *
     * Source offset is provenance only and is not part of serialization.
     */
    Id3v23Header outputHeader =
        Id3v23Header(
            0,
            source.envelope.header.revision,
            source.envelope.header.flags,
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

    /*
     * Whole-tag unsynchronisation should already have been rejected by
     * the sequence/body layers. Reaching this point with the flag set
     * would mean the supplied planning/execution layers disagree.
     */
    if (outputHeader.unsynchronisation)
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


/// Whole-tag-unsynchronised source tags remain explicitly non-writable.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            // Whole-tag unsynchronisation flag.
            0x80,

            0x00, 0x00, 0x00, 0x0B,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
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

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
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
