/++
Complete serialization of newly introduced canonical ID3v2.4 ordinary
text-information frames.

Supported canonical targets are currently:

- `title`  -> TIT2
- `artist` -> TPE1
- `album`  -> TALB

This module combines the already separated writer layers:

    canonical field
        -> canonical target / representability plan
        -> UTF-8 text-information payload
        -> fixed ID3v2.4 frame header
        -> complete native frame bytes

New frames use zero status and format flags. Preservation or deliberate
regeneration of structural flags from an existing native frame belongs
to the later existing-frame regeneration layer.

No tag header, padding or container update is performed here.
+/
module audiotag.id3v2.v24.text_information_frame_write;

import std.sumtype :
    match;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.metadata.field :
    MetadataField;

import audiotag.metadata.value :
    MetadataText,
    MetadataTextList;

import audiotag.id3v2.v24.canonical_target :
    Id3v24CanonicalTargetFamily;

import audiotag.id3v2.v24.frame_header :
    Id3v24FrameHeader;

import audiotag.id3v2.v24.frame_header_write :
    serializeId3v24FrameHeader;

import audiotag.id3v2.v24.new_frame_plan :
    planId3v24CanonicalField;

import audiotag.id3v2.v24.text_information_write :
    serializeId3v24Utf8TextInformationPayload;


/++
Serializes the text-information payload contained in one canonical
field.

The caller must already have established that the field targets the
ordinary ID3v2.4 text-information family.
+/
private SerializationResult!(ubyte[])
serializeCanonicalTextInformationPayload(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataText) text)
        {
            const(string)[] values =
                [text.value];

            return
                serializeId3v24Utf8TextInformationPayload(
                    values
                );
        },

        (const(MetadataTextList) list) =>
            serializeId3v24Utf8TextInformationPayload(
                list.values
            ),

        _ =>
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation
                    )
                )
    );
}


/++
Serializes one newly introduced canonical ordinary text-information
field as a complete ID3v2.4 frame.

The canonical planner is consulted first, so this function never
silently discards unsupported language, description, qualifier, value
shape or text-payload information.

New native frames deliberately use:

    statusFlags = 0
    formatFlags = 0

because there is no source-native frame whose structural flags need to
be preserved.

Params:
    field = Canonical `title`, `artist` or `album` field.

Returns:
    Complete owned frame bytes, including the ten-byte ID3v2.4 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v24TextInformationFrame(
    ref const(MetadataField) field
)
    @safe
{
    const plan =
        planId3v24CanonicalField(
            field
        );

    if (!plan.writable)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation,
                        0,
                        cast(ulong) plan.status
                    )
                );
    }

    if (
        plan.target.family !=
        Id3v24CanonicalTargetFamily
            .textInformation
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation
                    )
                );
    }

    auto payload =
        serializeCanonicalTextInformationPayload(
            field
        );

    if (payload.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    payload.error
                );
    }

    /*
     * Canonical target definitions are static writer registry data.
     * A non-four-byte ID here is therefore a programmer/registry bug.
     */
    assert(
        plan.target.frameId.length ==
        4
    );

    /*
     * Successful text-payload serialization already guarantees the
     * ID3v2.4 28-bit frame-size limit.
     */
    assert(
        payload.value.length <=
        0x0FFF_FFFF
    );

    Id3v24FrameHeader header;

    foreach (index; 0 .. 4)
    {
        header.id[index] =
            plan.target.frameId[index];
    }

    header.size =
        cast(uint)
            payload.value.length;

    header.statusFlags = 0;
    header.formatFlags = 0;

    auto encodedHeader =
        serializeId3v24FrameHeader(
            header
        );

    if (encodedHeader.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    encodedHeader.error
                );
    }

    auto output =
        new ubyte[
            encodedHeader.value.length +
            payload.value.length
        ];

    output[
        0 ..
        encodedHeader.value.length
    ] =
        encodedHeader.value[];

    output[
        encodedHeader.value.length ..
        $
    ] =
        payload.value[];

    return
        SerializationResult!(ubyte[])
            .success(output);
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.metadata.field :
        MetadataKey,
        MetadataLanguage;

    import audiotag.metadata.value :
        MetadataValue;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.text_encoding :
        Id3v24TextEncoding;

    import audiotag.id3v2.v24.text_information :
        decodeId3v24TextInformationFrame;


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
}


/// A canonical title becomes one exact UTF-8 TIT2 frame.
unittest
{
    const field =
        textField(
            "title",
            "Title"
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x03,
            'T', 'i', 't', 'l', 'e'
        ]
    );
}


/// An ordered canonical artist list becomes one null-separated TPE1.
unittest
{
    const field =
        textListField(
            "artist",
            [
                "Artist A",
                "Artist B"
            ]
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                100
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.id[] ==
        "TPE1"
    );

    assert(
        envelope.value.header.statusFlags ==
        0
    );

    assert(
        envelope.value.header.formatFlags ==
        0
    );

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.text.encoding ==
        Id3v24TextEncoding.utf8
    );

    assert(
        decoded.value.text.values.length ==
        2
    );

    assert(
        decoded.value.text.values[0] ==
        "Artist A"
    );

    assert(
        decoded.value.text.values[1] ==
        "Artist B"
    );
}


/// Album Unicode survives complete write then strict read.
unittest
{
    const field =
        textField(
            "album",
            "Grüße"
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                500
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.id[] ==
        "TALB"
    );

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.text.values.length ==
        1
    );

    assert(
        decoded.value.text.values[0] ==
        "Grüße"
    );
}


/// Parser provenance comes from the newly serialized byte location.
unittest
{
    const field =
        textField(
            "title",
            "X"
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                1234
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    assert(
        envelope.value.header.sourceOffset ==
        1234
    );

    assert(
        envelope.value.data.sourceOffset ==
        1244
    );
}


/// Canonical context unsupported by TIT2 is rejected before byte output.
unittest
{
    auto field =
        textField(
            "title",
            "Title"
        );

    field.description =
        "not-representable-in-TIT2";

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Embedded NUL remains rejected through the complete frame API.
unittest
{
    const field =
        textField(
            "title",
            "A\0B"
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Empty artist lists never become ambiguous or empty native TPE1 frames.
unittest
{
    const field =
        textListField(
            "artist",
            []
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Other canonical serializer families cannot enter this writer.
unittest
{
    auto field =
        textField(
            "comment",
            "Comment"
        );

    field.language =
        MetadataLanguage(
            "eng"
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
