/++
ID3v2.3 attached-picture (`APIC`) payload serialization.

This module serializes the two semantic APIC payload forms supported by
the ID3v2.3 reader:

- embedded binary image data;
- linked image URLs using the reserved MIME value `"-->"`.

The physical semantic payload is:

    <description encoding marker>
    <MIME as ISO-8859-1> $00
    <picture type>
    <description according to encoding>
    <mandatory description terminator>
    <picture data>

For linked pictures the MIME field is the reserved value `"-->"` and
the final picture-data field is an ISO-8859-1 URL extending to the
payload boundary.

The description encoding is selected deterministically:

- ISO-8859-1 when the description is losslessly representable there;
- otherwise strict ID3v2.3 UCS-2 with its own BOM;
- otherwise serialization fails.

The MIME field and linked URL are independent of the description
encoding and always use ISO-8859-1.

An empty embedded MIME value remains representable because the v2.3
reader accepts a terminated empty MIME field and preserves native MIME
spelling exactly. The reserved value `"-->"` cannot be used for
embedded binary data.

Empty descriptions, empty embedded image data and empty linked URLs are
representable.

Embedded U+0000 is rejected in MIME and description because those fields
are terminated. Linked URLs occupy the remainder of the payload and may
therefore contain zero bytes as ordinary ISO-8859-1 data.

This module emits logical semantic payload bytes only. It does not emit
an APIC frame header, grouping identity, compression/encryption
additions or ID3v2.3 whole-tag unsynchronisation.
+/
module audiotag.id3v2.v23.attached_picture_write;

import std.encoding :
    validLength;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.attached_picture :
    Id3v23PictureType;

import audiotag.id3v2.v23.text_encode :
    measureId3v23EncodedText,
    serializeId3v23EncodedText;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding,
    terminatorWidth;

import audiotag.id3v2.v23.text_encoding_policy :
    chooseId3v23TextEncoding;


/++
Maximum semantic frame-data size representable by the ordinary unsigned
32-bit ID3v2.3 frame-size field.
+/
private enum size_t maximumFrameDataSize =
    uint.max;


/++
Adds one component to a bounded ID3v2.3 APIC payload size.
+/
private SerializationResult!size_t
addPayloadLength(
    size_t current,
    size_t addition
)
    @safe
{
    if (
        current >
        maximumFrameDataSize ||
        addition >
            maximumFrameDataSize -
                current
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidLength,
                        current,
                        addition,
                        maximumFrameDataSize -
                            current
                    )
                );
    }


    return
        SerializationResult!size_t
            .success(
                current +
                addition
            );
}


/++
Measures one canonical UTF-8 string after lossless conversion to native
ISO-8859-1.

Params:
    value = Canonical UTF-8 text.
    payloadOffset = Semantic payload offset used for diagnostics.
    rejectNull = Whether U+0000 is structurally forbidden.

Returns:
    Number of native ISO-8859-1 bytes or a structured serialization
    error.
+/
private SerializationResult!size_t
measureLatin1(
    string value,
    size_t payloadOffset,
    bool rejectNull
)
    @safe
{
    const valid =
        validLength(
            value
        );


    if (
        valid !=
        value.length
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        payloadOffset +
                            valid
                    )
                );
    }


    size_t encodedLength;


    foreach (
        dchar codePoint;
        value
    )
    {
        if (
            rejectNull &&
            codePoint ==
            0
        )
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            payloadOffset +
                                encodedLength,
                            0
                        )
                    );
        }


        if (
            codePoint >
            0xFF
        )
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            payloadOffset +
                                encodedLength,
                            cast(ulong)
                                codePoint,
                            0xFF
                        )
                    );
        }


        ++encodedLength;
    }


    return
        SerializationResult!size_t
            .success(
                encodedLength
            );
}


/++
Validates one canonical APIC description.

Descriptions are terminated native strings, so embedded U+0000 cannot
be represented by the canonical scalar model.

Malformed UTF-8 is rejected before native encoding selection.
+/
private SerializationResult!bool
validateDescription(
    string description
)
    @safe
{
    const valid =
        validLength(
            description
        );


    if (
        valid !=
        description.length
    )
    {
        return
            SerializationResult!bool
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        valid
                    )
                );
    }


    foreach (
        byteIndex,
        descriptionByte;
        description
    )
    {
        if (
            descriptionByte ==
            '\0'
        )
        {
            return
                SerializationResult!bool
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            byteIndex,
                            0
                        )
                    );
        }
    }


    return
        SerializationResult!bool
            .success(
                true
            );
}


/++
Selects the deterministic ID3v2.3 encoding for one APIC description.

Only the description participates in text-encoding selection. MIME and
linked URLs remain ISO-8859-1 regardless of this result.
+/
private SerializationResult!Id3v23TextEncoding
chooseDescriptionEncoding(
    string description
)
    @safe
{
    auto valid =
        validateDescription(
            description
        );


    if (
        valid.hasError
    )
    {
        return
            SerializationResult!Id3v23TextEncoding
                .failure(
                    valid.error
                );
    }


    const(string)[] values =
        [
            description
        ];


    return
        chooseId3v23TextEncoding(
            values
        );
}


/++
Validates one ID3v2.3 picture-type byte.
+/
private SerializationResult!size_t
validatePictureType(
    Id3v23PictureType pictureType,
    size_t payloadOffset
)
    @safe
{
    const raw =
        cast(ubyte)
            pictureType;


    if (
        raw >
        0x14
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        payloadOffset,
                        raw,
                        0x14
                    )
                );
    }


    return
        SerializationResult!size_t
            .success(
                1
            );
}


/++
Measures and validates one deterministic embedded-image ID3v2.3 APIC
semantic payload.

The MIME value:

- is converted losslessly to ISO-8859-1;
- may be empty;
- must not contain U+0000;
- must not equal reserved linked-picture marker `"-->"`.

The description uses deterministic ID3v2.3 Latin-1/UCS-2 selection.

Empty binary image data remains representable.

Params:
    mimeType = Canonical/native MIME spelling associated with the image.
    pictureType = Native APIC picture type.
    description = Canonical picture description.
    pictureData = Opaque logical embedded image bytes.

Returns:
    Complete semantic payload size or a structured serialization error.
+/
SerializationResult!size_t
measureId3v23EmbeddedPicturePayload(
    string mimeType,
    Id3v23PictureType pictureType,
    string description,
    const(ubyte)[] pictureData
)
    @safe
{
    if (
        mimeType ==
        "-->"
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation,
                        1
                    )
                );
    }


    /*
     * First semantic byte is the description encoding marker.
     */
    size_t total =
        1;


    auto mime =
        measureLatin1(
            mimeType,
            total,
            true
        );


    if (
        mime.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    mime.error
                );
    }


    auto added =
        addPayloadLength(
            total,
            mime.value
        );


    if (
        added.hasError
    )
    {
        return added;
    }


    total =
        added.value;


    /*
     * Mandatory one-byte MIME terminator.
     */
    added =
        addPayloadLength(
            total,
            1
        );


    if (
        added.hasError
    )
    {
        return added;
    }


    total =
        added.value;


    auto type =
        validatePictureType(
            pictureType,
            total
        );


    if (
        type.hasError
    )
    {
        return type;
    }


    added =
        addPayloadLength(
            total,
            type.value
        );


    if (
        added.hasError
    )
    {
        return added;
    }


    total =
        added.value;


    auto encodingResult =
        chooseDescriptionEncoding(
            description
        );


    if (
        encodingResult.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    encodingResult.error
                );
    }


    const encoding =
        encodingResult.value;


    auto descriptionSize =
        measureId3v23EncodedText(
            description,
            encoding
        );


    if (
        descriptionSize.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    descriptionSize.error
                );
    }


    added =
        addPayloadLength(
            total,
            descriptionSize.value
        );


    if (
        added.hasError
    )
    {
        return added;
    }


    total =
        added.value;


    added =
        addPayloadLength(
            total,
            cast(size_t)
                terminatorWidth(
                    encoding
                )
        );


    if (
        added.hasError
    )
    {
        return added;
    }


    total =
        added.value;


    added =
        addPayloadLength(
            total,
            pictureData.length
        );


    if (
        added.hasError
    )
    {
        return added;
    }


    return added;
}


/++
Serializes one deterministic embedded-image ID3v2.3 APIC semantic
payload.

The generated bytes have the form:

    $00 <MIME> $00 <type>
        <Latin-1 description> $00
        <picture data>

or:

    $01 <MIME> $00 <type>
        <UCS-2 description with BOM when non-empty>
        $00 $00
        <picture data>

Whole-tag unsynchronisation is not applied here.
+/
SerializationResult!(ubyte[])
serializeId3v23EmbeddedPicturePayload(
    string mimeType,
    Id3v23PictureType pictureType,
    string description,
    const(ubyte)[] pictureData
)
    @safe
{
    auto measured =
        measureId3v23EmbeddedPicturePayload(
            mimeType,
            pictureType,
            description,
            pictureData
        );


    if (
        measured.hasError
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    measured.error
                );
    }


    auto encodingResult =
        chooseDescriptionEncoding(
            description
        );


    assert(
        encodingResult.hasValue
    );


    const encoding =
        encodingResult.value;


    auto encodedDescription =
        serializeId3v23EncodedText(
            description,
            encoding
        );


    assert(
        encodedDescription.hasValue
    );


    auto output =
        new ubyte[
            measured.value
        ];


    size_t position;


    output[
        position++
    ] =
        cast(ubyte)
            encoding;


    /*
     * Measurement proved lossless one-byte MIME representation.
     */
    foreach (
        dchar codePoint;
        mimeType
    )
    {
        output[
            position++
        ] =
            cast(ubyte)
                codePoint;
    }


    output[
        position++
    ] =
        0x00;


    output[
        position++
    ] =
        cast(ubyte)
            pictureType;


    if (
        encodedDescription.value.length !=
        0
    )
    {
        output[
            position ..
            position +
                encodedDescription.value.length
        ] =
            encodedDescription.value[];


        position +=
            encodedDescription.value.length;
    }


    foreach (
        ignored;
        0 ..
        terminatorWidth(
            encoding
        )
    )
    {
        output[
            position++
        ] =
            0;
    }


    foreach (
        byteValue;
        pictureData
    )
    {
        output[
            position++
        ] =
            byteValue;
    }


    assert(
        position ==
        output.length
    );


    return
        SerializationResult!(ubyte[])
            .success(
                output
            );
}


/++
Measures and validates one deterministic linked-image ID3v2.3 APIC
semantic payload.

The physical MIME field is always:

    "-->" $00

The description follows normal deterministic v2.3 description encoding.

The URL is encoded independently as ISO-8859-1 and extends to the
semantic payload boundary without a terminator.

Because the URL is not terminated, embedded U+0000 remains ordinary URL
data and is not rejected at this layer.

Params:
    pictureType = Native APIC picture type.
    description = Canonical picture description.
    url = Canonical linked image URL.

Returns:
    Complete semantic payload size or a structured serialization error.
+/
SerializationResult!size_t
measureId3v23LinkedPicturePayload(
    Id3v23PictureType pictureType,
    string description,
    string url
)
    @safe
{
    /*
     * Encoding marker + "-->" + MIME terminator.
     */
    size_t total =
        5;


    auto type =
        validatePictureType(
            pictureType,
            total
        );


    if (
        type.hasError
    )
    {
        return type;
    }


    auto added =
        addPayloadLength(
            total,
            type.value
        );


    if (
        added.hasError
    )
    {
        return added;
    }


    total =
        added.value;


    auto encodingResult =
        chooseDescriptionEncoding(
            description
        );


    if (
        encodingResult.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    encodingResult.error
                );
    }


    const encoding =
        encodingResult.value;


    auto descriptionSize =
        measureId3v23EncodedText(
            description,
            encoding
        );


    if (
        descriptionSize.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    descriptionSize.error
                );
    }


    added =
        addPayloadLength(
            total,
            descriptionSize.value
        );


    if (
        added.hasError
    )
    {
        return added;
    }


    total =
        added.value;


    added =
        addPayloadLength(
            total,
            cast(size_t)
                terminatorWidth(
                    encoding
                )
        );


    if (
        added.hasError
    )
    {
        return added;
    }


    total =
        added.value;


    /*
     * The URL is the final field. It is not terminated and therefore
     * U+0000 is not a native delimiter here.
     */
    auto urlMeasure =
        measureLatin1(
            url,
            total,
            false
        );


    if (
        urlMeasure.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    urlMeasure.error
                );
    }


    added =
        addPayloadLength(
            total,
            urlMeasure.value
        );


    if (
        added.hasError
    )
    {
        return added;
    }


    return added;
}


/++
Serializes one linked-image ID3v2.3 APIC semantic payload.

The generated bytes have the form:

    $00 "-->" $00 <type>
        <Latin-1 description> $00
        <ISO-8859-1 URL>

or:

    $01 "-->" $00 <type>
        <UCS-2 description with BOM when non-empty>
        $00 $00
        <ISO-8859-1 URL>

The URL receives no trailing terminator.
+/
SerializationResult!(ubyte[])
serializeId3v23LinkedPicturePayload(
    Id3v23PictureType pictureType,
    string description,
    string url
)
    @safe
{
    auto measured =
        measureId3v23LinkedPicturePayload(
            pictureType,
            description,
            url
        );


    if (
        measured.hasError
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    measured.error
                );
    }


    auto encodingResult =
        chooseDescriptionEncoding(
            description
        );


    assert(
        encodingResult.hasValue
    );


    const encoding =
        encodingResult.value;


    auto encodedDescription =
        serializeId3v23EncodedText(
            description,
            encoding
        );


    assert(
        encodedDescription.hasValue
    );


    auto output =
        new ubyte[
            measured.value
        ];


    size_t position;


    output[
        position++
    ] =
        cast(ubyte)
            encoding;


    output[position++] = '-';
    output[position++] = '-';
    output[position++] = '>';


    output[
        position++
    ] =
        0x00;


    output[
        position++
    ] =
        cast(ubyte)
            pictureType;


    if (
        encodedDescription.value.length !=
        0
    )
    {
        output[
            position ..
            position +
                encodedDescription.value.length
        ] =
            encodedDescription.value[];


        position +=
            encodedDescription.value.length;
    }


    foreach (
        ignored;
        0 ..
        terminatorWidth(
            encoding
        )
    )
    {
        output[
            position++
        ] =
            0;
    }


    /*
     * Measurement proved one-byte ISO-8859-1 representability. NUL is
     * allowed because this final field is not terminated.
     */
    foreach (
        dchar codePoint;
        url
    )
    {
        output[
            position++
        ] =
            cast(ubyte)
                codePoint;
    }


    assert(
        position ==
        output.length
    );


    return
        SerializationResult!(ubyte[])
            .success(
                output
            );
}


/// Normal JPEG front-cover data uses deterministic Latin-1 description.
unittest
{
    const(ubyte)[] image =
        [
            0xFF,
            0xD8,
            0xFF,
            0xD9
        ];


    auto measured =
        measureId3v23EmbeddedPicturePayload(
            "image/jpeg",
            Id3v23PictureType.frontCover,
            "Front",
            image
        );


    assert(
        measured.hasValue
    );


    auto serialized =
        serializeId3v23EmbeddedPicturePayload(
            "image/jpeg",
            Id3v23PictureType.frontCover,
            "Front",
            image
        );


    assert(
        serialized.hasValue
    );


    assert(
        measured.value ==
        serialized.value.length
    );


    assert(
        serialized.value ==
        [
            0x00,

            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g',
            0x00,

            0x03,

            'F', 'r', 'o', 'n', 't',
            0x00,

            0xFF,
            0xD8,
            0xFF,
            0xD9
        ]
    );
}


/// A shortened v2.3 MIME spelling is preserved rather than normalized.
unittest
{
    auto serialized =
        serializeId3v23EmbeddedPicturePayload(
            "png",
            Id3v23PictureType.frontCover,
            "",
            [
                cast(ubyte)
                    0x89
            ]
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,

            'p', 'n', 'g',
            0x00,

            0x03,

            0x00,

            0x89
        ]
    );
}


/// A terminated empty MIME field remains representable by the v2.3 codec.
unittest
{
    auto serialized =
        serializeId3v23EmbeddedPicturePayload(
            "",
            Id3v23PictureType.other,
            "",
            []
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,
            0x00,
            0x00,
            0x00
        ]
    );
}


/// Empty description and empty embedded picture data remain valid.
unittest
{
    auto serialized =
        serializeId3v23EmbeddedPicturePayload(
            "image/png",
            Id3v23PictureType.other,
            "",
            []
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,

            'i', 'm', 'a', 'g', 'e', '/',
            'p', 'n', 'g',
            0x00,

            0x00,

            0x00
        ]
    );
}


/// Latin-1 non-ASCII description remains on marker $00.
unittest
{
    auto serialized =
        serializeId3v23EmbeddedPicturePayload(
            "image/jpeg",
            Id3v23PictureType.frontCover,
            "Gr\u00F6\u00DFe",
            [
                cast(ubyte)
                    0xAA
            ]
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value[
            0
        ] ==
        0x00
    );


    assert(
        serialized.value[
            $ - 7 ..
            $ - 1
        ] ==
        [
            'G', 'r',
            0xF6,
            0xDF,
            'e',
            0x00
        ]
    );
}


/// Wider BMP description uses strict UCS-2 with its own BOM.
unittest
{
    auto serialized =
        serializeId3v23EmbeddedPicturePayload(
            "image/png",
            Id3v23PictureType.frontCover,
            "\u03A9",
            [
                cast(ubyte)
                    0x89
            ]
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x01,

            'i', 'm', 'a', 'g', 'e', '/',
            'p', 'n', 'g',
            0x00,

            0x03,

            0xFE, 0xFF,
            0x03, 0xA9,

            0x00, 0x00,

            0x89
        ]
    );
}


/// The reserved MIME marker cannot describe embedded picture bytes.
unittest
{
    auto measured =
        measureId3v23EmbeddedPicturePayload(
            "-->",
            Id3v23PictureType.frontCover,
            "",
            [
                cast(ubyte)
                    0xFF
            ]
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// MIME values outside ISO-8859-1 cannot be represented.
unittest
{
    auto measured =
        measureId3v23EmbeddedPicturePayload(
            "image/\u20AC",
            Id3v23PictureType.frontCover,
            "",
            []
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );


    assert(
        measured.error.value ==
        0x20AC
    );
}


/// Embedded NUL cannot terminate the MIME field early.
unittest
{
    auto measured =
        measureId3v23EmbeddedPicturePayload(
            "image\0/jpeg",
            Id3v23PictureType.frontCover,
            "",
            []
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Embedded NUL cannot terminate the APIC description early.
unittest
{
    auto measured =
        measureId3v23EmbeddedPicturePayload(
            "image/jpeg",
            Id3v23PictureType.frontCover,
            "Front\0cover",
            []
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Supplementary Unicode is outside strict ID3v2.3 UCS-2.
unittest
{
    auto measured =
        measureId3v23EmbeddedPicturePayload(
            "image/jpeg",
            Id3v23PictureType.frontCover,
            "\U0001F600",
            []
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );


    assert(
        measured.error.value ==
        0x1F600
    );


    assert(
        measured.error.limit ==
        0xFFFF
    );
}


/// Undefined APIC picture types are rejected.
unittest
{
    auto measured =
        measureId3v23EmbeddedPicturePayload(
            "image/jpeg",
            cast(Id3v23PictureType)
                0x15,
            "",
            []
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .invalidValue
    );


    assert(
        measured.error.value ==
        0x15
    );


    assert(
        measured.error.limit ==
        0x14
    );
}


/// Linked artwork uses reserved MIME marker and Latin-1 description.
unittest
{
    auto measured =
        measureId3v23LinkedPicturePayload(
            Id3v23PictureType.frontCover,
            "cover",
            "http://x"
        );


    assert(
        measured.hasValue
    );


    auto serialized =
        serializeId3v23LinkedPicturePayload(
            Id3v23PictureType.frontCover,
            "cover",
            "http://x"
        );


    assert(
        serialized.hasValue
    );


    assert(
        measured.value ==
        serialized.value.length
    );


    assert(
        serialized.value ==
        [
            0x00,

            '-', '-', '>',
            0x00,

            0x03,

            'c', 'o', 'v', 'e', 'r',
            0x00,

            'h', 't', 't', 'p', ':', '/',
            '/', 'x'
        ]
    );
}


/// Linked URL remains ISO-8859-1 when description requires UCS-2.
unittest
{
    auto serialized =
        serializeId3v23LinkedPicturePayload(
            Id3v23PictureType.frontCover,
            "\u03A9",
            "x\u00E9"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x01,

            '-', '-', '>',
            0x00,

            0x03,

            0xFE, 0xFF,
            0x03, 0xA9,

            0x00, 0x00,

            'x',
            0xE9
        ]
    );
}


/// Empty linked URL contributes zero bytes after description terminator.
unittest
{
    auto serialized =
        serializeId3v23LinkedPicturePayload(
            Id3v23PictureType.backCover,
            "",
            ""
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,

            '-', '-', '>',
            0x00,

            0x04,

            0x00
        ]
    );
}


/// Linked-picture URL may contain NUL because it is not terminated.
unittest
{
    auto serialized =
        serializeId3v23LinkedPicturePayload(
            Id3v23PictureType.other,
            "",
            "a\0b"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,

            '-', '-', '>',
            0x00,

            0x00,

            0x00,

            'a',
            0x00,
            'b'
        ]
    );
}


/// Linked URLs outside ISO-8859-1 cannot be represented.
unittest
{
    auto measured =
        measureId3v23LinkedPicturePayload(
            Id3v23PictureType.frontCover,
            "",
            "https://example.test/\u20AC"
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );


    assert(
        measured.error.value ==
        0x20AC
    );
}


/// Whole-tag-unsynchronisation-like image bytes remain logical bytes here.
unittest
{
    const(ubyte)[] image =
        [
            0xFF,
            0xE1,
            0xFF
        ];


    auto serialized =
        serializeId3v23EmbeddedPicturePayload(
            "image/jpeg",
            Id3v23PictureType.other,
            "",
            image
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value[
            $ - 3 ..
            $
        ] ==
        image
    );
}


/// Measurement and serialization remain exactly synchronized.
unittest
{
    const(ubyte)[] image =
        [
            0x89,
            0x50,
            0x00,
            0xFF
        ];


    auto embeddedMeasured =
        measureId3v23EmbeddedPicturePayload(
            "image/png",
            Id3v23PictureType.frontCover,
            "\u03A9",
            image
        );


    auto embeddedSerialized =
        serializeId3v23EmbeddedPicturePayload(
            "image/png",
            Id3v23PictureType.frontCover,
            "\u03A9",
            image
        );


    assert(embeddedMeasured.hasValue);
    assert(embeddedSerialized.hasValue);

    assert(
        embeddedMeasured.value ==
        embeddedSerialized.value.length
    );


    auto linkedMeasured =
        measureId3v23LinkedPicturePayload(
            Id3v23PictureType.backCover,
            "Back",
            "x\u00E9"
        );


    auto linkedSerialized =
        serializeId3v23LinkedPicturePayload(
            Id3v23PictureType.backCover,
            "Back",
            "x\u00E9"
        );


    assert(linkedMeasured.hasValue);
    assert(linkedSerialized.hasValue);

    assert(
        linkedMeasured.value ==
        linkedSerialized.value.length
    );
}
