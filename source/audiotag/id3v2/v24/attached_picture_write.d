/++
ID3v2.4 attached-picture payload serialization.

This module serializes the two semantic APIC payload forms supported by
the reader:

- embedded binary image data;
- linked image URLs using the reserved MIME value `"-->"`.

Descriptions are emitted deterministically as UTF-8:

    $03 <MIME ISO-8859-1> $00 <picture type>
        <description UTF-8> $00 <picture data>

or:

    $03 "-->" $00 <picture type>
        <description UTF-8> $00 <URL ISO-8859-1>

No APIC frame header, grouping byte, DLI or other frame-format
transformation is emitted here.
+/
module audiotag.id3v2.v24.attached_picture_write;

import std.encoding :
    validLength;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v24.attached_picture :
    Id3v24PictureType;


/++
Maximum ID3v2.4 frame-data size representable by the four-byte
synchsafe frame-size field.
+/
private enum size_t maximumFrameDataSize =
    0x0FFF_FFFF;


/++
Validates one UTF-8 string that will be followed by a one-byte UTF-8
terminator.

Embedded U+0000 cannot be represented because it would terminate the
description early.
+/
private SerializationResult!size_t
measureTerminatedUtf8(
    string value,
    size_t payloadOffset
)
    @safe
{
    const valid =
        validLength(value);

    if (valid != value.length)
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode.invalidValue,
                        payloadOffset + valid
                    )
                );
    }

    foreach (index, codeUnit; value)
    {
        if (codeUnit == '\0')
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            payloadOffset + index,
                            0
                        )
                    );
        }
    }

    return
        SerializationResult!size_t
            .success(value.length);
}


/++
Measures the number of bytes required to represent one UTF-8 D string
as ID3 ISO-8859-1.

Each Unicode scalar value must fit in one ISO-8859-1 byte.
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
        validLength(value);

    if (valid != value.length)
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode.invalidValue,
                        payloadOffset + valid
                    )
                );
    }

    size_t encodedLength;

    foreach (inputIndex, dchar codePoint; value)
    {
        if (
            rejectNull &&
            codePoint == 0
        )
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            payloadOffset + encodedLength,
                            0
                        )
                    );
        }

        if (codePoint > 0xFF)
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            payloadOffset + encodedLength,
                            cast(ulong) codePoint,
                            0xFF
                        )
                    );
        }

        ++encodedLength;
    }

    return
        SerializationResult!size_t
            .success(encodedLength);
}


/++
Adds one component to a bounded APIC payload size.
+/
private SerializationResult!size_t
addPayloadLength(
    size_t current,
    size_t addition
)
    @safe
{
    if (
        current > maximumFrameDataSize ||
        addition >
            maximumFrameDataSize - current
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode.invalidLength,
                        current,
                        addition,
                        maximumFrameDataSize - current
                    )
                );
    }

    return
        SerializationResult!size_t
            .success(
                current + addition
            );
}


/++
Validates one ID3v2.4 picture-type value.
+/
private SerializationResult!size_t
validatePictureType(
    Id3v24PictureType pictureType,
    size_t payloadOffset
)
    @safe
{
    const raw =
        cast(ubyte) pictureType;

    if (raw > 0x14)
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode.invalidValue,
                        payloadOffset,
                        raw,
                        0x14
                    )
                );
    }

    return
        SerializationResult!size_t
            .success(1);
}


/++
Measures and validates one deterministic embedded-image APIC payload.

The MIME type must:

- be non-empty;
- fit ISO-8859-1;
- contain no embedded U+0000;
- not equal the reserved linked-picture marker `"-->"`.

Empty descriptions and empty binary image data remain representable.
+/
SerializationResult!size_t
measureId3v24Utf8EmbeddedPicturePayload(
    string mimeType,
    Id3v24PictureType pictureType,
    string description,
    const(ubyte)[] pictureData
)
    @safe
{
    if (mimeType.length == 0)
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode.invalidValue,
                        1
                    )
                );
    }

    if (mimeType == "-->")
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

    auto mime =
        measureLatin1(
            mimeType,
            1,
            true
        );

    if (mime.hasError)
    {
        return mime;
    }

    size_t total = 1;

    auto added =
        addPayloadLength(
            total,
            mime.value
        );

    if (added.hasError)
    {
        return added;
    }

    total = added.value;

    added =
        addPayloadLength(total, 1);

    if (added.hasError)
    {
        return added;
    }

    total = added.value;

    auto type =
        validatePictureType(
            pictureType,
            total
        );

    if (type.hasError)
    {
        return type;
    }

    added =
        addPayloadLength(
            total,
            type.value
        );

    if (added.hasError)
    {
        return added;
    }

    total = added.value;

    auto descriptionMeasure =
        measureTerminatedUtf8(
            description,
            total
        );

    if (descriptionMeasure.hasError)
    {
        return descriptionMeasure;
    }

    added =
        addPayloadLength(
            total,
            descriptionMeasure.value
        );

    if (added.hasError)
    {
        return added;
    }

    total = added.value;

    added =
        addPayloadLength(total, 1);

    if (added.hasError)
    {
        return added;
    }

    total = added.value;

    added =
        addPayloadLength(
            total,
            pictureData.length
        );

    if (added.hasError)
    {
        return added;
    }

    return added;
}


/++
Serializes one embedded-image APIC payload into owned bytes.
+/
SerializationResult!(ubyte[])
serializeId3v24Utf8EmbeddedPicturePayload(
    string mimeType,
    Id3v24PictureType pictureType,
    string description,
    const(ubyte)[] pictureData
)
    @safe
{
    auto measured =
        measureId3v24Utf8EmbeddedPicturePayload(
            mimeType,
            pictureType,
            description,
            pictureData
        );

    if (measured.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    measured.error
                );
    }

    auto output =
        new ubyte[measured.value];

    size_t position;

    output[position++] = 0x03;

    foreach (dchar codePoint; mimeType)
    {
        output[position++] =
            cast(ubyte) codePoint;
    }

    output[position++] = 0x00;

    output[position++] =
        cast(ubyte) pictureType;

    foreach (codeUnit; description)
    {
        output[position++] =
            cast(ubyte) codeUnit;
    }

    output[position++] = 0x00;

    foreach (byteValue; pictureData)
    {
        output[position++] =
            byteValue;
    }

    assert(position == output.length);

    return
        SerializationResult!(ubyte[])
            .success(output);
}


/++
Measures and validates one deterministic linked-image APIC payload.

The physical MIME field is always the reserved value `"-->"`.
The URL is encoded as ISO-8859-1 to the end of the APIC payload and
therefore receives no terminator.
+/
SerializationResult!size_t
measureId3v24Utf8LinkedPicturePayload(
    Id3v24PictureType pictureType,
    string description,
    string url
)
    @safe
{
    /*
     * $03 + "-->" + $00
     */
    size_t total = 5;

    auto type =
        validatePictureType(
            pictureType,
            total
        );

    if (type.hasError)
    {
        return type;
    }

    auto added =
        addPayloadLength(
            total,
            type.value
        );

    if (added.hasError)
    {
        return added;
    }

    total = added.value;

    auto descriptionMeasure =
        measureTerminatedUtf8(
            description,
            total
        );

    if (descriptionMeasure.hasError)
    {
        return descriptionMeasure;
    }

    added =
        addPayloadLength(
            total,
            descriptionMeasure.value
        );

    if (added.hasError)
    {
        return added;
    }

    total = added.value;

    added =
        addPayloadLength(total, 1);

    if (added.hasError)
    {
        return added;
    }

    total = added.value;

    auto urlMeasure =
        measureLatin1(
            url,
            total,
            false
        );

    if (urlMeasure.hasError)
    {
        return urlMeasure;
    }

    added =
        addPayloadLength(
            total,
            urlMeasure.value
        );

    if (added.hasError)
    {
        return added;
    }

    return added;
}


/++
Serializes one linked-image APIC payload into owned bytes.
+/
SerializationResult!(ubyte[])
serializeId3v24Utf8LinkedPicturePayload(
    Id3v24PictureType pictureType,
    string description,
    string url
)
    @safe
{
    auto measured =
        measureId3v24Utf8LinkedPicturePayload(
            pictureType,
            description,
            url
        );

    if (measured.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    measured.error
                );
    }

    auto output =
        new ubyte[measured.value];

    size_t position;

    output[position++] = 0x03;

    output[position++] = '-';
    output[position++] = '-';
    output[position++] = '>';

    output[position++] = 0x00;

    output[position++] =
        cast(ubyte) pictureType;

    foreach (codeUnit; description)
    {
        output[position++] =
            cast(ubyte) codeUnit;
    }

    output[position++] = 0x00;

    foreach (dchar codePoint; url)
    {
        output[position++] =
            cast(ubyte) codePoint;
    }

    assert(position == output.length);

    return
        SerializationResult!(ubyte[])
            .success(output);
}


/// A normal embedded JPEG front cover has deterministic APIC bytes.
unittest
{
    const ubyte[] image =
        [
            0xFF, 0xD8,
            0xFF, 0xD9
        ];

    auto measured =
        measureId3v24Utf8EmbeddedPicturePayload(
            "image/jpeg",
            Id3v24PictureType.frontCover,
            "Front",
            image
        );

    assert(measured.hasValue);

    auto serialized =
        serializeId3v24Utf8EmbeddedPicturePayload(
            "image/jpeg",
            Id3v24PictureType.frontCover,
            "Front",
            image
        );

    assert(serialized.hasValue);
    assert(serialized.value.length == measured.value);

    const ubyte[] expected =
        [
            0x03,

            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g',
            0x00,

            0x03,

            'F', 'r', 'o', 'n', 't',
            0x00,

            0xFF, 0xD8,
            0xFF, 0xD9
        ];

    assert(serialized.value == expected);
}


/// Empty APIC description and embedded data remain representable.
unittest
{
    auto serialized =
        serializeId3v24Utf8EmbeddedPicturePayload(
            "image/png",
            Id3v24PictureType.other,
            "",
            []
        );

    assert(serialized.hasValue);

    const ubyte[] expected =
        [
            0x03,
            'i', 'm', 'a', 'g', 'e', '/',
            'p', 'n', 'g',
            0x00,
            0x00,
            0x00
        ];

    assert(serialized.value == expected);
}


/// UTF-8 APIC descriptions are copied without normalization.
unittest
{
    auto serialized =
        serializeId3v24Utf8EmbeddedPicturePayload(
            "image/jpeg",
            Id3v24PictureType.frontCover,
            "Größe",
            [cast(ubyte) 0xAA]
        );

    assert(serialized.hasValue);

    /*
     * UTF-8 description bytes:
     * "Größe" = 47 72 C3 B6 C3 9F 65
     */
    assert(
        serialized.value[
            serialized.value.length - 9 ..
            serialized.value.length - 2
        ] ==
        [
            cast(ubyte) 0x47,
            cast(ubyte) 0x72,
            cast(ubyte) 0xC3,
            cast(ubyte) 0xB6,
            cast(ubyte) 0xC3,
            cast(ubyte) 0x9F,
            cast(ubyte) 0x65
        ]
    );
}


/// The reserved MIME marker cannot be used for embedded picture bytes.
unittest
{
    auto serialized =
        serializeId3v24Utf8EmbeddedPicturePayload(
            "-->",
            Id3v24PictureType.frontCover,
            "",
            [cast(ubyte) 0xFF]
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Embedded artwork requires a non-empty MIME type.
unittest
{
    auto serialized =
        serializeId3v24Utf8EmbeddedPicturePayload(
            "",
            Id3v24PictureType.frontCover,
            "",
            []
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode.invalidValue
    );
}


/// MIME values outside ISO-8859-1 are rejected.
unittest
{
    auto serialized =
        serializeId3v24Utf8EmbeddedPicturePayload(
            "image/€",
            Id3v24PictureType.frontCover,
            "",
            []
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Embedded NUL cannot silently terminate the APIC MIME field.
unittest
{
    auto serialized =
        serializeId3v24Utf8EmbeddedPicturePayload(
            "image\0/jpeg",
            Id3v24PictureType.frontCover,
            "",
            []
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Embedded NUL cannot silently terminate the APIC description.
unittest
{
    auto serialized =
        serializeId3v24Utf8EmbeddedPicturePayload(
            "image/jpeg",
            Id3v24PictureType.frontCover,
            "Front\0cover",
            []
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Undefined APIC picture types are rejected.
unittest
{
    auto serialized =
        serializeId3v24Utf8EmbeddedPicturePayload(
            "image/jpeg",
            cast(Id3v24PictureType) 0x15,
            "",
            []
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode.invalidValue
    );
}


/// Linked artwork uses the reserved MIME marker and ISO-8859-1 URL.
unittest
{
    auto measured =
        measureId3v24Utf8LinkedPicturePayload(
            Id3v24PictureType.frontCover,
            "cover",
            "http://x"
        );

    assert(measured.hasValue);

    auto serialized =
        serializeId3v24Utf8LinkedPicturePayload(
            Id3v24PictureType.frontCover,
            "cover",
            "http://x"
        );

    assert(serialized.hasValue);
    assert(serialized.value.length == measured.value);

    const ubyte[] expected =
        [
            0x03,
            '-', '-', '>',
            0x00,
            0x03,
            'c', 'o', 'v', 'e', 'r',
            0x00,
            'h', 't', 't', 'p', ':', '/',
            '/', 'x'
        ];

    assert(serialized.value == expected);
}


/// Linked-picture URLs outside ISO-8859-1 are rejected.
unittest
{
    auto serialized =
        serializeId3v24Utf8LinkedPicturePayload(
            Id3v24PictureType.frontCover,
            "",
            "https://example.test/€"
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
