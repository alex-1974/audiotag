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
        MetadataKey,
        MetadataLanguage,
        MetadataQualifier;

    import audiotag.metadata.value :
        MetadataBinary,
        MetadataPicture,
        MetadataPictureSource,
        MetadataText,
        MetadataTextList,
        MetadataUrl,
        MetadataValue;

    import audiotag.id3v2.v24.canonical_mapping :
        Id3v24CanonicalMappingResult;

    import audiotag.id3v2.v24.attached_picture :
        Id3v24PicturePayloadKind,
        Id3v24PictureType,
        decodeId3v24AttachedPictureFrame;

    import audiotag.id3v2.v24.private_frame :
        decodeId3v24PrivateFrame;

    import audiotag.id3v2.v24.comment :
        decodeId3v24CommentFrame;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.lyrics_text :
        decodeId3v24LyricsTextFrame;

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

    import audiotag.id3v2.v24.user_text :
        decodeId3v24UserTextFrame;

    import audiotag.id3v2.v24.user_url :
        decodeId3v24UserUrlFrame;

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


    private MetadataField userTextField(
        string description,
        string value
    )
        @safe
    {
        auto result =
            textField(
                "userText",
                value
            );

        result.description =
            description;

        return result;
    }


    private MetadataField userUrlField(
        string description,
        string url
    )
        @safe
    {
        auto result =
            urlField(
                "userUrl",
                url
            );

        result.description =
            description;

        return result;
    }


    private MetadataField languageTextField(
        string key,
        string language,
        string description,
        string value
    )
        @safe
    {
        auto result =
            textField(
                key,
                value
            );

        result.language =
            MetadataLanguage(language);

        result.description =
            description;

        return result;
    }


    private MetadataField
    embeddedArtworkField(
        string role,
        string description,
        string mimeType,
        const(ubyte)[] data
    )
        @safe
    {
        MetadataPictureSource source =
            MetadataBinary.copyFrom(
                data,
                mimeType
            );

        MetadataValue wrapped =
            MetadataPicture(
                description,
                source
            );

        auto result =
            MetadataField(
                MetadataKey("artwork"),
                wrapped
            );

        result.qualifiers =
            [
                MetadataQualifier(
                    "pictureRole",
                    role
                )
            ];

        return result;
    }


    private MetadataField
    linkedArtworkField(
        string role,
        string description,
        string url
    )
        @safe
    {
        MetadataPictureSource source =
            MetadataUrl(url);

        MetadataValue wrapped =
            MetadataPicture(
                description,
                source
            );

        auto result =
            MetadataField(
                MetadataKey("artwork"),
                wrapped
            );

        result.qualifiers =
            [
                MetadataQualifier(
                    "pictureRole",
                    role
                )
            ];

        return result;
    }


    private MetadataField
    privateDataField(
        string owner,
        const(ubyte)[] data
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataBinary.copyFrom(
                data
            );

        auto result =
            MetadataField(
                MetadataKey("privateData"),
                wrapped
            );

        result.qualifiers =
            [
                MetadataQualifier(
                    "owner",
                    owner
                )
            ];

        return result;
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


version (unittest)
{
    private Id3v24CanonicalProjection
    projectionWithMappedUserText(
        const(Id3v24TagStructure) source,
        string description,
        string value
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
                userTextField(
                    description,
                    value
                )
            )
        );

        return projection;
    }
}


version (unittest)
{
    private Id3v24CanonicalProjection
    projectionWithMappedUserUrl(
        const(Id3v24TagStructure) source,
        string description,
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
                userUrlField(
                    description,
                    url
                )
            )
        );

        return projection;
    }
}


version (unittest)
{
    private Id3v24CanonicalProjection
    projectionWithMappedLanguageText(
        const(Id3v24TagStructure) source,
        string key,
        string language,
        string description,
        string value
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
                languageTextField(
                    key,
                    language,
                    description,
                    value
                )
            )
        );

        return projection;
    }
}


version (unittest)
{
    private Id3v24CanonicalProjection
    projectionWithMappedEmbeddedArtwork(
        const(Id3v24TagStructure) source,
        string role,
        string description,
        string mimeType,
        const(ubyte)[] data
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
                embeddedArtworkField(
                    role,
                    description,
                    mimeType,
                    data
                )
            )
        );

        return projection;
    }
}


version (unittest)
{
    private Id3v24CanonicalProjection
    projectionWithMappedPrivateData(
        const(Id3v24TagStructure) source,
        string owner,
        const(ubyte)[] data
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
                privateDataField(
                    owner,
                    data
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


/// Canonical TXXX replacement survives complete tag write and strict reparse.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            // One eighteen-byte TXXX frame.
            0x00, 0x00, 0x00, 0x12,

            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

            0x03,
            'k', 'e', 'y',
            0x00,
            'o', 'l', 'd'
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedUserText(
            source,
            "key",
            "old"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        userTextField(
            "new-key",
            "new"
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
                5000
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(reparsed.value.frameCount == 1);
    assert(reparsed.value.frames.padding.empty);

    /*
     * Regenerated TXXX semantic payload:
     *
     *   $03 + "new-key" + $00 + "new"
     *
     * = 12 bytes.
     *
     * Complete frame = 10 + 12 = 22-byte tag body.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        22
    );

    auto frames =
        reparsed.value.frameCursor();

    auto frame =
        frames.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(frames.empty);

    assert(
        frame.value.header.id[] ==
        "TXXX"
    );

    auto decoded =
        frame.value.decodeId3v24UserTextFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.text.description ==
        "new-key"
    );

    assert(
        decoded.value.text.value ==
        "new"
    );
}


/// A newly appended TXXX survives the complete tag writer path.
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
        userTextField(
            "MusicBrainz Album Id",
            "abc-123"
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
                6000
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
     *
     * New TXXX payload:
     *   $03
     *   "MusicBrainz Album Id" = 20 bytes
     *   $00
     *   "abc-123" = 7 bytes
     *
     * Payload = 29, complete TXXX = 39.
     * Total body = 12 + 39 = 51.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        51
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

    assert(
        first.value.header.id[] ==
        "TIT2"
    );

    assert(
        second.value.header.id[] ==
        "TXXX"
    );

    auto decoded =
        second.value.decodeId3v24UserTextFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.text.description ==
        "MusicBrainz Album Id"
    );

    assert(
        decoded.value.text.value ==
        "abc-123"
    );
}


/// Canonical WXXX replacement survives complete tag write and strict reparse.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            // One eighteen-byte WXXX frame.
            0x00, 0x00, 0x00, 0x12,

            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

            0x03,
            'k', 'e', 'y',
            0x00,
            'o', 'l', 'd'
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedUserUrl(
            source,
            "key",
            "old"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        userUrlField(
            "new-key",
            "new"
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
                7000
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(reparsed.value.frameCount == 1);
    assert(reparsed.value.frames.padding.empty);

    /*
     * Regenerated WXXX semantic payload:
     *
     *   $03 + "new-key" + $00 + "new"
     *
     * = 12 bytes.
     *
     * Complete WXXX frame = 10 + 12 = 22-byte tag body.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        22
    );

    auto frames =
        reparsed.value.frameCursor();

    auto frame =
        frames.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(frames.empty);

    assert(
        frame.value.header.id[] ==
        "WXXX"
    );

    auto decoded =
        frame.value.decodeId3v24UserUrlFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.link.description ==
        "new-key"
    );

    assert(
        decoded.value.link.url ==
        "new"
    );
}


/// A newly appended WXXX survives the complete tag writer path.
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
        userUrlField(
            "homepage",
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
                8000
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
     *
     * New WXXX payload:
     *
     *   $03
     *   "homepage" = 8 bytes
     *   $00
     *   "https://example.test/" = 21 bytes
     *
     * Payload = 31 bytes.
     * Complete WXXX = 10 + 31 = 41 bytes.
     * Total tag body = 12 + 41 = 53 bytes.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        53
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
     * Existing native order is retained; new canonical frames append.
     */
    assert(
        first.value.header.id[] ==
        "TIT2"
    );

    assert(
        second.value.header.id[] ==
        "WXXX"
    );

    auto decoded =
        second.value.decodeId3v24UserUrlFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.link.description ==
        "homepage"
    );

    assert(
        decoded.value.link.url ==
        "https://example.test/"
    );
}


/// Canonical COMM replacement survives complete tag write and strict reparse.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            // One twenty-one-byte COMM frame.
            0x00, 0x00, 0x00, 0x15,

            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x0B,
            0x00, 0x00,

            0x03,
            'e', 'n', 'g',
            'k', 'e', 'y',
            0x00,
            'o', 'l', 'd'
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedLanguageText(
            source,
            "comment",
            "eng",
            "key",
            "old"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        languageTextField(
            "comment",
            "deu",
            "note",
            "neu"
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
                9000
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(reparsed.value.frameCount == 1);
    assert(reparsed.value.frames.padding.empty);

    /*
     * Regenerated COMM payload:
     *
     *   $03 + "deu" + "note" + $00 + "neu"
     *
     * = 12 bytes.
     *
     * Complete COMM frame = 10 + 12 = 22-byte tag body.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        22
    );

    auto frames =
        reparsed.value.frameCursor();

    auto frame =
        frames.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(frames.empty);

    assert(
        frame.value.header.id[] ==
        "COMM"
    );

    auto decoded =
        frame.value.decodeId3v24CommentFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.comment.language[] ==
        "deu"
    );

    assert(
        decoded.value.comment.description ==
        "note"
    );

    assert(
        decoded.value.comment.text ==
        "neu"
    );
}


/// A newly appended COMM survives the complete tag writer path.
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
        languageTextField(
            "comment",
            "eng",
            "note",
            "hello"
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
                10000
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
     *
     * COMM payload:
     *
     *   $03 + "eng" + "note" + $00 + "hello"
     *
     * = 14 bytes.
     *
     * Complete COMM = 24 bytes.
     * Total tag body = 12 + 24 = 36.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        36
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

    assert(
        first.value.header.id[] ==
        "TIT2"
    );

    assert(
        second.value.header.id[] ==
        "COMM"
    );

    auto decoded =
        second.value.decodeId3v24CommentFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.comment.language[] ==
        "eng"
    );

    assert(
        decoded.value.comment.description ==
        "note"
    );

    assert(
        decoded.value.comment.text ==
        "hello"
    );
}


/// Canonical USLT replacement survives complete tag write and strict reparse.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            // One twenty-one-byte USLT frame.
            0x00, 0x00, 0x00, 0x15,

            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x0B,
            0x00, 0x00,

            0x03,
            'e', 'n', 'g',
            'k', 'e', 'y',
            0x00,
            'o', 'l', 'd'
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedLanguageText(
            source,
            "lyrics",
            "eng",
            "key",
            "old"
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        languageTextField(
            "lyrics",
            "deu",
            "vers",
            "zeile"
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
                11000
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(reparsed.value.frameCount == 1);
    assert(reparsed.value.frames.padding.empty);

    /*
     * Regenerated USLT payload:
     *
     *   $03 + "deu" + "vers" + $00 + "zeile"
     *
     * = 14 bytes.
     *
     * Complete USLT frame = 10 + 14 = 24-byte tag body.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        24
    );

    auto frames =
        reparsed.value.frameCursor();

    auto frame =
        frames.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(frames.empty);

    assert(
        frame.value.header.id[] ==
        "USLT"
    );

    auto decoded =
        frame.value.decodeId3v24LyricsTextFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.lyrics.language[] ==
        "deu"
    );

    assert(
        decoded.value.lyrics.descriptor ==
        "vers"
    );

    assert(
        decoded.value.lyrics.text ==
        "zeile"
    );
}


/// A newly appended USLT survives the complete tag writer path.
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
        languageTextField(
            "lyrics",
            "eng",
            "lyrics",
            "line1
line2"
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
                12000
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
     *
     * USLT payload:
     *
     *   $03
     *   "eng" = 3 bytes
     *   "lyrics" = 6 bytes
     *   $00
     *   "line1\nline2" = 11 bytes
     *
     * Payload = 22 bytes.
     * Complete USLT = 32 bytes.
     * Total tag body = 12 + 32 = 44.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        44
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

    assert(
        first.value.header.id[] ==
        "TIT2"
    );

    assert(
        second.value.header.id[] ==
        "USLT"
    );

    auto decoded =
        second.value.decodeId3v24LyricsTextFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.lyrics.language[] ==
        "eng"
    );

    assert(
        decoded.value.lyrics.descriptor ==
        "lyrics"
    );

    assert(
        decoded.value.lyrics.text ==
        "line1
line2"
    );
}


/// Canonical embedded artwork replacement survives the complete tag writer path.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            // One 29-byte APIC frame.
            0x00, 0x00, 0x00, 0x1D,

            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x13,
            0x00, 0x00,

            0x03,

            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g',
            0x00,

            0x03,

            'O', 'l', 'd',
            0x00,

            0xFF, 0xD8
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedEmbeddedArtwork(
            source,
            "frontCover",
            "Old",
            "image/jpeg",
            [
                cast(ubyte) 0xFF,
                cast(ubyte) 0xD8
            ]
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        embeddedArtworkField(
            "backCover",
            "New",
            "image/png",
            [
                cast(ubyte) 0x89,
                cast(ubyte) 0x50,
                cast(ubyte) 0x4E,
                cast(ubyte) 0x47
            ]
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
                8000
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(reparsed.value.frameCount == 1);
    assert(reparsed.value.frames.padding.empty);

    /*
     * Regenerated semantic APIC payload:
     *
     *   03
     *   "image/png" 00
     *   backCover = 04
     *   "New" 00
     *   89 50 4E 47
     *
     * = 20 bytes.
     *
     * Complete APIC = 10 + 20 = 30-byte tag body.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        30
    );

    auto frames =
        reparsed.value.frameCursor();

    auto frame =
        frames.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(frames.empty);

    assert(
        frame.value.header.id[] ==
        "APIC"
    );

    auto decoded =
        frame.value.decodeId3v24AttachedPictureFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.picture.mimeType ==
        "image/png"
    );

    assert(
        decoded.value.picture.pictureType ==
        Id3v24PictureType.backCover
    );

    assert(
        decoded.value.picture.description ==
        "New"
    );

    assert(
        decoded.value.picture.payloadKind ==
        Id3v24PicturePayloadKind.binaryData
    );

    assert(!decoded.value.picture.linked);

    assert(
        decoded.value.picture.rawPictureData.data ==
        [
            0x89,
            0x50,
            0x4E,
            0x47
        ]
    );
}


/// Newly appended embedded artwork survives the complete tag writer path.
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
        embeddedArtworkField(
            "frontCover",
            "Front",
            "image/jpeg",
            [
                cast(ubyte) 0xFF,
                cast(ubyte) 0xD8
            ]
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
                9000
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
     *
     * New APIC semantic payload:
     *
     *   03
     *   "image/jpeg" 00
     *   frontCover = 03
     *   "Front" 00
     *   FF D8
     *
     * = 21 bytes.
     *
     * APIC frame = 10 + 21 = 31 bytes.
     * Complete tag body = 12 + 31 = 43 bytes.
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

    assert(
        first.value.header.id[] ==
        "TIT2"
    );

    assert(
        second.value.header.id[] ==
        "APIC"
    );

    auto decoded =
        second.value.decodeId3v24AttachedPictureFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.picture.mimeType ==
        "image/jpeg"
    );

    assert(
        decoded.value.picture.pictureType ==
        Id3v24PictureType.frontCover
    );

    assert(
        decoded.value.picture.description ==
        "Front"
    );

    assert(
        decoded.value.picture.payloadKind ==
        Id3v24PicturePayloadKind.binaryData
    );

    assert(
        decoded.value.picture.rawPictureData.data ==
        [0xFF, 0xD8]
    );
}


/// Newly appended linked artwork survives the complete tag writer path.
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
        linkedArtworkField(
            "backCover",
            "Cover",
            "http://x"
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
                10000
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
     *
     * Linked APIC semantic payload:
     *
     *   03 "-->" 00
     *   backCover = 04
     *   "Cover" 00
     *   "http://x"
     *
     * = 20 bytes.
     *
     * APIC frame = 30 bytes.
     * Complete tag body = 42 bytes.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        42
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

    assert(
        first.value.header.id[] ==
        "TIT2"
    );

    assert(
        second.value.header.id[] ==
        "APIC"
    );

    auto decoded =
        second.value.decodeId3v24AttachedPictureFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(decoded.value.picture.linked);

    assert(
        decoded.value.picture.mimeType ==
        "-->"
    );

    assert(
        decoded.value.picture.pictureType ==
        Id3v24PictureType.backCover
    );

    assert(
        decoded.value.picture.description ==
        "Cover"
    );

    assert(
        decoded.value.picture.payloadKind ==
        Id3v24PicturePayloadKind.linkedUrl
    );

    assert(
        decoded.value.picture.linkedUrl ==
        "http://x"
    );
}


/// Canonical private-data replacement survives the complete tag writer path.
unittest
{
    const ubyte[] sourceBytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,

            // Complete tag body = one 24-byte PRIV frame.
            0x00, 0x00, 0x00, 0x18,

            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            'o', 'l', 'd', '.',
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            0x00,

            0x01, 0x02
        ];

    const source =
        parseTestTag(sourceBytes);

    const projection =
        projectionWithMappedPrivateData(
            source,
            "old.example",
            [
                cast(ubyte) 0x01,
                cast(ubyte) 0x02
            ]
        );

    auto edit =
        MetadataTreeEdit.forSource(
            projection.metadata
        );

    edit.replaceSourceField(
        0,
        privateDataField(
            "new.example",
            [
                cast(ubyte) 0xAA,
                cast(ubyte) 0x00,
                cast(ubyte) 0xFF
            ]
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
                11000
            )
        );

    auto reparsed =
        cursor.parseId3v24TagStructure();

    assert(reparsed.hasValue);
    assert(cursor.empty);

    assert(reparsed.value.frameCount == 1);
    assert(reparsed.value.frames.padding.empty);

    /*
     * Regenerated semantic PRIV payload:
     *
     *   "new.example" 00 AA 00 FF
     *
     * owner = 11 bytes
     * terminator = 1 byte
     * private data = 3 bytes
     *
     * payload = 15 bytes
     * frame   = 10 + 15 = 25 bytes
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        25
    );

    auto frames =
        reparsed.value.frameCursor();

    auto frame =
        frames.parseId3v24FrameEnvelope();

    assert(frame.hasValue);
    assert(frames.empty);

    assert(
        frame.value.header.id[] ==
        "PRIV"
    );

    auto decoded =
        frame.value.decodeId3v24PrivateFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.privateFrame.ownerIdentifier ==
        "new.example"
    );

    assert(
        decoded.value.privateFrame.rawPrivateData.data ==
        [
            0xAA,
            0x00,
            0xFF
        ]
    );
}


/// Newly appended private data survives the complete tag writer path.
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
        privateDataField(
            "example.com",
            [
                cast(ubyte) 0x01,
                cast(ubyte) 0x00,
                cast(ubyte) 0xFE,
                cast(ubyte) 0xFF
            ]
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
                12000
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
     *
     * New PRIV semantic payload:
     *
     *   "example.com" 00 01 00 FE FF
     *
     * = 16 bytes.
     *
     * Complete PRIV frame = 10 + 16 = 26 bytes.
     *
     * Complete tag body = 12 + 26 = 38 bytes.
     */
    assert(
        reparsed.value.envelope.header.tagSize ==
        38
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

    assert(
        first.value.header.id[] ==
        "TIT2"
    );

    assert(
        second.value.header.id[] ==
        "PRIV"
    );

    auto decoded =
        second.value.decodeId3v24PrivateFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.privateFrame.ownerIdentifier ==
        "example.com"
    );

    assert(
        decoded.value.privateFrame.rawPrivateData.data ==
        [
            0x01,
            0x00,
            0xFE,
            0xFF
        ]
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
