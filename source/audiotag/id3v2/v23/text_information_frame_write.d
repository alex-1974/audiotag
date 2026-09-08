/++
Complete serialization of newly introduced canonical ID3v2.3 ordinary
text-information frames.

Supported canonical targets are currently:

- `title`  -> TIT2
- `artist` -> TPE1
- `album`  -> TALB

This module combines the already separated writer layers:

    canonical field
        -> canonical target / representability plan
        -> ID3v2.3 text-information payload
        -> fixed ID3v2.3 frame header
        -> complete native frame bytes

New frames use zero status and format flags because there is no
source-native frame whose structural flags need to be preserved.

Existing-frame regeneration is deliberately not implemented here.
ID3v2.3 regeneration requires a separate format policy for status flags,
compression, encryption and grouping identity.

No tag-level unsynchronisation, tag header, padding or container update
is performed here.
+/
module audiotag.id3v2.v23.text_information_frame_write;

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

import audiotag.id3v2.v23.canonical_target :
    Id3v23CanonicalTargetFamily;

import audiotag.id3v2.v23.frame_header :
    Id3v23FrameHeader;

import audiotag.id3v2.v23.frame_header_write :
    serializeId3v23FrameHeader;

import audiotag.id3v2.v23.new_frame_plan :
    planId3v23CanonicalField;

import audiotag.id3v2.v23.text_information_write :
    serializeId3v23SlashListTextInformationPayload,
    serializeId3v23TextInformationPayload;


/++
Serializes the ordinary text-information payload contained in one
canonical field.

Scalar canonical text is serialized as one ID3v2.3 information string.

The canonical `artist` representation is an ordered `MetadataTextList`;
its native TPE1 representation is the ID3v2.3 slash-separated form
provided by `serializeId3v23SlashListTextInformationPayload`.

The caller must already have established that the field targets the
ordinary ID3v2.3 text-information family.
+/
private SerializationResult!(ubyte[])
serializeCanonicalTextInformationPayload(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataText) text) =>
            serializeId3v23TextInformationPayload(
                text.value
            ),

        (const(MetadataTextList) list) =>
            serializeId3v23SlashListTextInformationPayload(
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
field as a complete ID3v2.3 frame.

The canonical planner is consulted first, so unsupported canonical
context or values are rejected before physical frame output begins.

New native frames deliberately use:

    statusFlags = 0
    formatFlags = 0

because no source-native structural state exists to preserve.

Params:
    field = Canonical `title`, `artist` or `album` field.

Returns:
    Complete owned frame bytes, including the ten-byte ID3v2.3 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v23TextInformationFrame(
    ref const(MetadataField) field
)
    @safe
{
    const plan =
        planId3v23CanonicalField(
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
        Id3v23CanonicalTargetFamily
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
     * Canonical target definitions are static writer-registry data.
     * A non-four-byte ID here is therefore a programmer/registry bug.
     */
    assert(
        plan.target.frameId.length ==
        4
    );

    /*
     * The v2.3 payload codecs enforce the complete uint frame-data
     * size domain before returning successful output.
     */
    assert(
        payload.value.length <=
        uint.max
    );

    /*
     * Every ordinary text-information payload contains at least the
     * one-byte encoding marker.
     */
    assert(
        payload.value.length !=
        0
    );

    Id3v23FrameHeader header;

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
        serializeId3v23FrameHeader(
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
        MetadataKey;

    import audiotag.metadata.value :
        MetadataUrl,
        MetadataValue;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;


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
}


/// A new scalar title becomes a complete zero-flag TIT2 frame.
unittest
{
    auto field =
        textField(
            "title",
            "Title"
        );

    auto encoded =
        serializeNewId3v23TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,
            0x00,
            'T', 'i', 't', 'l', 'e'
        ]
    );
}


/// Complete newly serialized text frames round-trip structurally.
unittest
{
    auto field =
        textField(
            "album",
            "Album"
        );

    auto encoded =
        serializeNewId3v23TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                700
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    assert(
        frame.value.header.sourceOffset ==
        700
    );

    assert(
        frame.value.header.id[] ==
        "TALB"
    );

    assert(
        frame.value.header.size ==
        6
    );

    assert(
        frame.value.header.statusFlags ==
        0
    );

    assert(
        frame.value.header.formatFlags ==
        0
    );
}


/// Canonical artist lists use the ID3v2.3 TPE1 slash representation.
unittest
{
    auto field =
        textListField(
            "artist",
            [
                "A",
                "B"
            ]
        );

    auto encoded =
        serializeNewId3v23TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,
            0x00,
            'A', '/', 'B'
        ]
    );
}


/// Empty scalar text still produces the mandatory encoding marker.
unittest
{
    auto field =
        textField(
            "title",
            ""
        );

    auto encoded =
        serializeNewId3v23TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x00
        ]
    );
}


/// Lossy slash-containing artist components are rejected before output.
unittest
{
    auto field =
        textListField(
            "artist",
            [
                "AC/DC"
            ]
        );

    auto encoded =
        serializeNewId3v23TextInformationFrame(
            field
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Unsupported canonical context is rejected before frame serialization.
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
        serializeNewId3v23TextInformationFrame(
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
        urlField(
            "commercialUrl",
            "https://example.invalid/"
        );

    auto encoded =
        serializeNewId3v23TextInformationFrame(
            field
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
