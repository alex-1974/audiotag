/++
Physical execution of one complete planned ID3v2.4 tag write.

This module composes the existing writer layers:

1. execute the planned native frame sequence;
2. compare the resulting frame bytes with the preserved source sequence;
3. plan the tag body from that actual physical change state;
4. serialize the body;
5. serialize a header with the resulting body size;
6. optionally serialize the matching footer;
7. concatenate the complete tag.

No container/file update is performed here.

Current lower-layer limitations remain explicit, including:

- only currently implemented canonical frame serializer families;
- no tag-level unsynchronisation writing;
- changed CRC-bearing extended headers are rejected;
- changed tags with unvalidated extended-header restrictions are rejected.

The outer result preserves parser errors that can occur while recovering
structural information from a preserved native frame during regeneration.
The inner result represents writer/planner/output failures.
+/
module audiotag.id3v2.v24.tag_write;

import audiotag.core.result :
    ParseResult;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.metadata.edit :
    MetadataTreeEdit;

import audiotag.id3v2.v24.canonical_projection :
    Id3v24CanonicalProjection;

import audiotag.id3v2.v24.frame_sequence_write :
    serializeId3v24PlannedFrameSequence;

import audiotag.id3v2.v24.header :
    Id3v24Header;

import audiotag.id3v2.v24.structure :
    Id3v24TagStructure;

import audiotag.id3v2.v24.tag_body_write :
    serializeId3v24TagBody;

import audiotag.id3v2.v24.tag_body_write_policy :
    Id3v24ExtendedHeaderWriteAction,
    planId3v24TagBodyWrite;

import audiotag.id3v2.v24.tag_header_write :
    serializeId3v24Footer,
    serializeId3v24Header;

import audiotag.id3v2.v24.tag_write_plan :
    Id3v24TagWritePlan;


/++
Result of complete planned ID3v2.4 tag serialization.
+/
alias Id3v24TagSerializationResult =
    ParseResult!(
        SerializationResult!(ubyte[])
    );


/++
Wraps a writer failure without converting it into malformed source input.
+/
private Id3v24TagSerializationResult
writerFailure(
    SerializationError error
)
    @safe
{
    return
        Id3v24TagSerializationResult
            .success(
                SerializationResult!(ubyte[])
                    .failure(error)
            );
}


/++
Serializes one complete ID3v2.4 tag from a semantic write plan.

`source`, `projection`, `edit` and `plan` must describe the same source
tag and edit operation.

The function does not require a caller-supplied "changed" boolean.
Instead, after frame-sequence execution it compares those actual bytes
with `source.frames.frameBytes`. This physical comparison determines
whether an existing extended-header CRC or restrictions would become
stale.

The source revision and defined header flags are retained. `tagSize` is
recomputed from the resulting body. When a footer is present, it is
regenerated from that updated header.

Params:
    source = Strict structural representation of the source tag.
    projection = Provenance-preserving canonical projection of its frames.
    edit = Canonical edit overlay used to construct `plan`.
    plan = Complete semantic write plan.

Returns:
    Complete owned ID3v2.4 tag bytes, an outer source-parse failure, or
    an inner writer failure.
+/
Id3v24TagSerializationResult
serializeId3v24PlannedTag(
    const(Id3v24TagStructure) source,
    const(Id3v24CanonicalProjection) projection,
    const(MetadataTreeEdit) edit,
    const(Id3v24TagWritePlan) plan
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
        serializeId3v24PlannedFrameSequence(
            projection,
            edit,
            plan,
            source.envelope.header
                .unsynchronisation
        );

    if (assembled.hasError)
    {
        return
            Id3v24TagSerializationResult
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
     * Derive physical change from actual output, not from edit intent.
     *
     * This also catches native-policy changes such as discarding a
     * non-canonical frame even when canonical metadata itself was not
     * edited.
     */
    const frameSequenceChanged =
        frameSequence !=
        source.frames.frameBytes.data;

    const bodyPlan =
        planId3v24TagBodyWrite(
            source,
            frameSequence.length,
            frameSequenceChanged
        );

    auto bodyResult =
        serializeId3v24TagBody(
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
     * The body serializer has already verified this relationship, but it
     * is central to the outer tag representation and therefore retained
     * as a programmer invariant here as well.
     */
    assert(
        body.length ==
        bodyPlan.tagSize
    );

    /*
     * Construct a new mutable output header explicitly.
     *
     * `source` is const, so `auto outputHeader = source.envelope.header`
     * would infer a const header and could not be updated with the newly
     * calculated tag size.
     *
     * Source offset is provenance only and therefore becomes zero in the
     * newly constructed representation.
     */
    Id3v24Header outputHeader =
        Id3v24Header(
            0,
            source.envelope.header.revision,
            source.envelope.header.flags,
            bodyPlan.tagSize
        );

    const extendedHeaderPresent =
        bodyPlan.extendedHeaderAction ==
        Id3v24ExtendedHeaderWriteAction
            .preserveOriginal;

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

    if (
        outputHeader.hasFooter !=
        bodyPlan.footerPresent
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
        serializeId3v24Header(
            outputHeader
        );

    if (headerResult.hasError)
    {
        return
            writerFailure(
                headerResult.error
            );
    }

    ubyte[10] footer;
    size_t footerLength;

    if (outputHeader.hasFooter)
    {
        auto footerResult =
            serializeId3v24Footer(
                outputHeader
            );

        if (footerResult.hasError)
        {
            return
                writerFailure(
                    footerResult.error
                );
        }

        footer =
            footerResult.value;

        footerLength =
            footer.length;
    }

    auto output =
        new ubyte[
            headerResult.value.length +
            body.length +
            footerLength
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

    if (footerLength != 0)
    {
        output[
            position ..
            position + footerLength
        ] =
            footer[];

        position +=
            footerLength;
    }

    assert(position == output.length);

    return
        Id3v24TagSerializationResult
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
        MetadataTextList,
        MetadataUrl,
        MetadataValue;

    import audiotag.id3v2.v24.canonical_mapping :
        Id3v24CanonicalMappingResult;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrame;

    import audiotag.id3v2.v24.structure :
        parseId3v24TagStructure;

    import audiotag.id3v2.v24.tag_write_plan :
        planId3v24CanonicalTagWrite;

    import audiotag.id3v2.v24.text_information :
        decodeId3v24TextInformationFrame;

    import audiotag.id3v2.v24.url_link :
        decodeId3v24UrlLinkFrame;

    import audiotag.id3v2.v24.writer_policy :
        Id3v24WriteContext;


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


    private MetadataField textListField(
        string key,
        string[] values
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataTextList(values);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
    }


    private MetadataField urlField(
        string key,
        string value
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataUrl(value);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
    }


    private Id3v24TagStructure
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
            cursor.parseId3v24TagStructure();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }


    private Id3v24CanonicalProjection
    projectionWithMappedTitle(
        const(Id3v24TagStructure) source,
        string title
    )
        @safe
    {
        auto cursor =
            source.frameCursor();

        auto frame =
            cursor.parseId3v24FrameEnvelope();

        assert(frame.hasValue);
        assert(cursor.empty);

        auto native =
            Id3v24NativeFrame.init;

        native.envelope =
            frame.value;

        auto projection =
            Id3v24CanonicalProjection.init;

        projection.append(
            native,
            Id3v24CanonicalMappingResult.success(
                textField(
                    "title",
                    title
                )
            )
        );

        return projection;
    }
}


version (unittest)
{
    private Id3v24CanonicalProjection
    projectionWithMappedUrl(
        const(Id3v24TagStructure) source,
        string key,
        string url
    )
        @safe
    {
        auto cursor =
            source.frameCursor();

        auto frame =
            cursor.parseId3v24FrameEnvelope();

        assert(frame.hasValue);
        assert(cursor.empty);

        auto native =
            Id3v24NativeFrame.init;

        native.envelope =
            frame.value;

        auto projection =
            Id3v24CanonicalProjection.init;

        projection.append(
            native,
            Id3v24CanonicalMappingResult.success(
                urlField(
                    key,
                    url
                )
            )
        );

        return projection;
    }
}


/// Canonical replacement produces a complete strict-readable ID3v2.4 tag.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            // 19-byte TIT2 + one padding byte.
            0x00, 0x00, 0x00, 0x14,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            0x03,
            'O', 'r', 'i', 'g',
            'i', 'n', 'a', 'l',

            0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedTitle(
            source,
            "Original"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        textField(
            "title",
            "New"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto written =
        serializeId3v24PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);

    auto serialized =
        written.value;

    assert(serialized.hasValue);

    /*
     * The shorter regenerated frame remains inside the old body capacity,
     * so the complete physical tag keeps its original length.
     */
    assert(
        serialized.value.length ==
        sourceBytes.length
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[],
                1000
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(
        reparsed.value.envelope.header.tagSize ==
        20
    );

    assert(reparsed.value.frameCount == 1);

    /*
     * New frame is fourteen bytes; remaining six body bytes are padding.
     */
    assert(
        reparsed.value.frames.frameBytes.length ==
        14
    );

    assert(
        reparsed.value.frames.padding.length ==
        6
    );

    auto frameCursor =
        reparsed.value.frameCursor();

    auto frame =
        frameCursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(frameCursor.empty);

    auto decoded =
        frame.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);

    assert(
        decoded.value.text.values ==
        ["New"]
    );
}


/// New canonical fields append as complete native frames in the full tag.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            // One twelve-byte TIT2 frame.
            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x03, 'X'
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedTitle(
            source,
            "X"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        textListField(
            "artist",
            ["A", "B"]
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto written =
        serializeId3v24PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);

    auto serialized =
        written.value;

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[]
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(reparsed.value.frameCount == 2);
    assert(reparsed.value.frames.padding.empty);

    auto frames =
        reparsed.value.frameCursor();

    auto first =
        frames.parseId3v24FrameEnvelope();

    auto second =
        frames.parseId3v24FrameEnvelope();

    assert(first.hasValue);
    assert(second.hasValue);
    assert(frames.empty);

    assert(first.value.header.id[] == "TIT2");
    assert(second.value.header.id[] == "TPE1");

    auto artist =
        second.value
            .decodeId3v24TextInformationFrame();

    assert(artist.hasValue);

    assert(
        artist.value.text.values ==
        ["A", "B"]
    );

    /*
     * Existing 12 bytes + new 14 bytes.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        26
    );
}


/// Canonical URL replacement survives complete tag write and strict reparse.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            // One thirteen-byte WCOM frame.
            0x00, 0x00, 0x00, 0x0D,

            'W', 'C', 'O', 'M',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            'o', 'l', 'd'
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedUrl(
            source,
            "commercialUrl",
            "old"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        urlField(
            "commercialUrl",
            "https://new.test/"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.regenerationCount == 1);

    auto written =
        serializeId3v24PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);

    auto serialized =
        written.value;

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[],
                3000
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(reparsed.value.frameCount == 1);
    assert(reparsed.value.frames.padding.empty);

    /*
     * New WCOM:
     *
     *   10-byte frame header
     *   17-byte URL payload
     *
     * so the new tag body is 27 bytes.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        27
    );

    auto frames =
        reparsed.value.frameCursor();

    auto frame =
        frames.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(frames.empty);

    assert(
        frame.value.header.id[] ==
        "WCOM"
    );

    auto decoded =
        frame.value.decodeId3v24UrlLinkFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.link.url ==
        "https://new.test/"
    );
}


/// A newly appended ordinary URL survives the complete tag writer path.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            // One twelve-byte TIT2 frame.
            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x03, 'X'
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedTitle(
            source,
            "X"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.appendNewField(
        urlField(
            "commercialUrl",
            "https://example.test/"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);
    assert(plan.newFrameCount == 1);

    auto written =
        serializeId3v24PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);

    auto serialized =
        written.value;

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[],
                4000
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(reparsed.value.frameCount == 2);
    assert(reparsed.value.frames.padding.empty);

    /*
     * Existing TIT2 = 12 bytes.
     * New WCOM = 10-byte header + 21-byte URL = 31 bytes.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        43
    );

    auto frames =
        reparsed.value.frameCursor();

    auto first =
        frames.parseId3v24FrameEnvelope();

    auto second =
        frames.parseId3v24FrameEnvelope();

    assert(first.hasValue);
    assert(second.hasValue);
    assert(frames.empty);

    /*
     * Existing native order is retained and new canonical fields append
     * after surviving source frames.
     */
    assert(
        first.value.header.id[] ==
        "TIT2"
    );

    assert(
        second.value.header.id[] ==
        "WCOM"
    );

    auto decoded =
        second.value.decodeId3v24UrlLinkFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.link.url ==
        "https://example.test/"
    );
}


/// A minimal extended header survives a changed tag byte-for-byte.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,

            // ext 6 + frame 12 + padding 3 = 21.
            0x00, 0x00, 0x00, 0x15,

            0x00, 0x00, 0x00, 0x06,
            0x01,
            0x00,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x03, 'X',

            0x00, 0x00, 0x00
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedTitle(
            source,
            "X"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        textField(
            "title",
            "New"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto written =
        serializeId3v24PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);

    auto serialized =
        written.value;

    assert(serialized.hasValue);

    /*
     * Extended-header bytes occupy output body positions 10..16.
     */
    assert(
        serialized.value[10 .. 16] ==
        source.body
            .extendedHeader
            .raw
            .data
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[]
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(reparsed.value.body.hasExtendedHeader);
    assert(reparsed.value.body.extendedHeader.size == 6);

    /*
     * New frame length = 14; old frame+padding capacity = 15.
     */
    assert(reparsed.value.frames.padding.length == 1);
    assert(reparsed.value.envelope.header.tagSize == 21);
}


/// Footer size is regenerated when changed frame data grows.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x10,

            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x03, 'X',

            '3', 'D', 'I',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x0C
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedTitle(
            source,
            "X"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        textField(
            "title",
            "Long"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto written =
        serializeId3v24PlannedTag(
            source,
            projection,
            edit,
            plan
        );

    assert(written.hasValue);

    auto serialized =
        written.value;

    assert(serialized.hasValue);

    /*
     * New TIT2 = 10 header + 5 payload = 15 body bytes.
     * Footer is outside tagSize.
     */
    assert(serialized.value.length == 35);

    assert(
        serialized.value[0 .. 3] ==
        ['I', 'D', '3']
    );

    assert(
        serialized.value[$ - 10 .. $ - 7] ==
        ['3', 'D', 'I']
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[],
                2000
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(reparsed.value.envelope.header.hasFooter);
    assert(reparsed.value.envelope.header.tagSize == 15);

    assert(reparsed.value.envelope.footer.length == 10);
    assert(reparsed.value.frames.padding.empty);
}


/// An unchanged CRC-bearing tag may roundtrip byte-for-byte.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,

            // extended 12 + frame 11 = 23.
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
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedTitle(
            source,
            "Opaque semantic placeholder"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.unchanged()
        );

    assert(plan.writable);

    auto written =
        serializeId3v24PlannedTag(
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


/// Changing a CRC-bearing tag is blocked after actual frame execution.
unittest
{
    const ubyte[] sourceBytes =
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
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedTitle(
            source,
            "Old"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        textField(
            "title",
            "New"
        )
    );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.tagOnly()
        );

    assert(plan.writable);

    auto written =
        serializeId3v24PlannedTag(
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


/// Global source-tag unsynchronisation remains an explicit writer blocker.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x80,

            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x03, 'X'
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedTitle(
            source,
            "X"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    const plan =
        planId3v24CanonicalTagWrite(
            projection,
            edit,
            Id3v24WriteContext.unchanged()
        );

    assert(plan.writable);

    auto written =
        serializeId3v24PlannedTag(
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
