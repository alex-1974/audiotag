/++
ID3v2.3 user-defined URL (`WXXX`) payload serialization.

One native WXXX semantic payload consists of:

    <description encoding marker>
    <description according to that encoding>
    <mandatory encoding-dependent description terminator>
    <URL as ISO-8859-1>

The encoding marker applies only to the description.

The writer chooses the description encoding deterministically:

- ISO-8859-1 when the description is losslessly representable there;
- otherwise strict ID3v2.3 UCS-2 with BOM;
- otherwise serialization fails.

A non-empty UCS-2 description receives its own deterministic big-endian
BOM through the shared encoded-text primitive. An empty description
contains no BOM.

The URL is independent of the description encoding and is always
serialized as ISO-8859-1.

The URL occupies the remainder of the bounded semantic payload. Its
optional native terminator is therefore omitted. In particular, an
empty WXXX URL contributes zero bytes after the mandatory description
terminator.

This differs intentionally from an empty ordinary W*** payload, where
one zero byte is emitted to preserve non-zero frame data. WXXX already
contains its encoding marker and description terminator, so no such
special case is necessary.

Embedded U+0000 is rejected in the description and URL because it would
introduce native termination semantics.

No frame header, frame-format additions or tag-level
unsynchronisation are emitted here.
+/
module audiotag.id3v2.v23.user_url_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.text_encode :
    measureId3v23EncodedText,
    serializeId3v23EncodedText;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding,
    terminatorWidth;

import audiotag.id3v2.v23.text_encoding_policy :
    chooseId3v23TextEncoding;

import audiotag.id3v2.v23.url_link_write :
    measureId3v23UrlLinkPayload,
    serializeId3v23UrlLinkPayload;


/++
Maximum semantic frame-data size representable by the ordinary unsigned
32-bit ID3v2.3 frame-size field.
+/
private enum size_t maximumFrameDataSize =
    uint.max;


/++
Validates and selects the native encoding for one WXXX description.

The shared encoding policy establishes UTF-8 validity and native
character-set representability.

Embedded U+0000 is rejected separately because it would terminate the
native description before its intended boundary.

Params:
    description = Canonical WXXX description.

Returns:
    Selected native description encoding or a structured serialization
    failure.
+/
private SerializationResult!Id3v23TextEncoding
validateId3v23UserUrlDescription(
    string description
)
    @safe
{
    const(string)[] values =
        [
            description
        ];


    auto encoding =
        chooseId3v23TextEncoding(
            values
        );


    if (
        encoding.hasError
    )
    {
        return encoding;
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
                SerializationResult!Id3v23TextEncoding
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


    return encoding;
}


/++
Measures and validates one deterministic ID3v2.3 WXXX semantic payload.

The returned size includes:

- one description-encoding marker;
- encoded description bytes;
- the mandatory encoding-dependent description terminator;
- ISO-8859-1 URL bytes.

An empty URL contributes zero bytes. No optional URL terminator is
included.

Params:
    description = User-defined WXXX description.
    url = Canonical UTF-8 URL.

Returns:
    Complete semantic payload size or a structured serialization error.
+/
SerializationResult!size_t
measureId3v23UserUrlPayload(
    string description,
    string url
)
    @safe
{
    auto encodingResult =
        validateId3v23UserUrlDescription(
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


    size_t total =
        1; // Description encoding marker.


    if (
        descriptionSize.value >
        maximumFrameDataSize -
        total
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        0,
                        cast(ulong)
                            total +
                            cast(ulong)
                                descriptionSize.value,
                        maximumFrameDataSize
                    )
                );
    }


    total +=
        descriptionSize.value;


    const terminatorSize =
        cast(size_t)
            terminatorWidth(
                encoding
            );


    if (
        terminatorSize >
        maximumFrameDataSize -
        total
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        0,
                        cast(ulong)
                            total +
                            cast(ulong)
                                terminatorSize,
                        maximumFrameDataSize
                    )
                );
    }


    total +=
        terminatorSize;


    /*
     * WXXX already has non-empty structural frame data at this point.
     *
     * Unlike an ordinary W*** frame, an empty URL therefore needs no
     * explicit zero terminator.
     */
    if (
        url.length ==
        0
    )
    {
        return
            SerializationResult!size_t
                .success(
                    total
                );
    }


    auto urlSize =
        measureId3v23UrlLinkPayload(
            url
        );


    if (
        urlSize.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    urlSize.error
                );
    }


    /*
     * For non-empty input the ordinary URL writer emits exactly the
     * ISO-8859-1 URL bytes and no terminator.
     */
    assert(
        urlSize.value !=
        0
    );


    if (
        urlSize.value >
        maximumFrameDataSize -
        total
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        0,
                        cast(ulong)
                            total +
                            cast(ulong)
                                urlSize.value,
                        maximumFrameDataSize
                    )
                );
    }


    total +=
        urlSize.value;


    return
        SerializationResult!size_t
            .success(
                total
            );
}


/++
Serializes one canonical WXXX description/URL pair as deterministic
ID3v2.3 semantic frame data.

The output is either:

    $00 <Latin-1 description> $00 <Latin-1 URL>

or:

    $01 <UCS-2 description with BOM when non-empty>
        $00 $00
        <Latin-1 URL>

The URL remains ISO-8859-1 even when the description uses UCS-2.

No optional URL terminator is emitted.

Params:
    description = User-defined WXXX description.
    url = Canonical UTF-8 URL.

Returns:
    Owned semantic payload bytes or the validation error reported by
    `measureId3v23UserUrlPayload`.
+/
SerializationResult!(ubyte[])
serializeId3v23UserUrlPayload(
    string description,
    string url
)
    @safe
{
    auto measured =
        measureId3v23UserUrlPayload(
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
        validateId3v23UserUrlDescription(
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


    /*
     * WXXX always requires its description terminator.
     */
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
     * An empty WXXX URL contributes no bytes.
     *
     * Calling the ordinary W*** serializer for empty input would add its
     * special one-byte empty-frame representation, which is deliberately
     * not part of WXXX.
     */
    if (
        url.length !=
        0
    )
    {
        auto encodedUrl =
            serializeId3v23UrlLinkPayload(
                url
            );


        assert(
            encodedUrl.hasValue
        );

        assert(
            encodedUrl.value.length !=
            0
        );


        output[
            position ..
            position +
                encodedUrl.value.length
        ] =
            encodedUrl.value[];


        position +=
            encodedUrl.value.length;
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


/// Ordinary ASCII WXXX data uses a Latin-1 description and URL.
unittest
{
    auto measured =
        measureId3v23UserUrlPayload(
            "home",
            "example.com"
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        17
    );


    auto serialized =
        serializeId3v23UserUrlPayload(
            "home",
            "example.com"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,

            'h', 'o', 'm', 'e',
            0x00,

            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm'
        ]
    );
}


/// Empty description and URL need only marker and description terminator.
unittest
{
    auto measured =
        measureId3v23UserUrlPayload(
            "",
            ""
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        2
    );


    auto serialized =
        serializeId3v23UserUrlPayload(
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
            0x00
        ]
    );
}


/// Empty WXXX URL does not inherit the ordinary W*** zero-byte special case.
unittest
{
    auto serialized =
        serializeId3v23UserUrlPayload(
            "home",
            ""
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,

            'h', 'o', 'm', 'e',
            0x00
        ]
    );
}


/// Latin-1 description and URL are transcoded losslessly.
unittest
{
    auto serialized =
        serializeId3v23UserUrlPayload(
            "Gr\u00F6\u00DFe",
            "https://example.test/\u00E9"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value[0] ==
        0x00
    );


    assert(
        serialized.value[
            1 ..
            6
        ] ==
        [
            'G', 'r',
            0xF6,
            0xDF,
            'e'
        ]
    );


    assert(
        serialized.value[6] ==
        0x00
    );


    assert(
        serialized.value[$ - 1] ==
        0xE9
    );
}


/// Wider BMP description uses UCS-2 while URL remains ISO-8859-1.
unittest
{
    auto serialized =
        serializeId3v23UserUrlPayload(
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

            /*
             * Description Ω with deterministic big-endian BOM.
             */
            0xFE, 0xFF,
            0x03, 0xA9,

            /*
             * Mandatory UCS-2 description terminator.
             */
            0x00, 0x00,

            /*
             * URL is still ISO-8859-1.
             */
            'x',
            0xE9
        ]
    );
}


/// Empty Unicode description has no BOM, only its mandatory terminator.
unittest
{
    /*
     * The empty description itself prefers Latin-1, so force this semantic
     * case through a non-empty Unicode description elsewhere is impossible:
     * WXXX has only one description string controlling the marker.
     *
     * Therefore the deterministic writer correctly uses Latin-1 here.
     */
    auto serialized =
        serializeId3v23UserUrlPayload(
            "",
            "url"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,
            0x00,
            'u', 'r', 'l'
        ]
    );
}


/// Unicode description with empty URL still needs no URL terminator.
unittest
{
    auto serialized =
        serializeId3v23UserUrlPayload(
            "\u03A9",
            ""
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x01,

            0xFE, 0xFF,
            0x03, 0xA9,

            0x00, 0x00
        ]
    );
}


/// Embedded NUL would terminate the WXXX description early.
unittest
{
    auto measured =
        measureId3v23UserUrlPayload(
            "a\0b",
            "example.com"
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
        measured.error.index ==
        1
    );
}


/// Embedded NUL in the URL would truncate its native semantics.
unittest
{
    auto measured =
        measureId3v23UserUrlPayload(
            "key",
            "a\0b"
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
        measured.error.index ==
        1
    );
}


/// URL Unicode outside ISO-8859-1 is rejected independently of description.
unittest
{
    auto measured =
        measureId3v23UserUrlPayload(
            "key",
            "x\u20AC"
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


    assert(
        measured.error.limit ==
        0xFF
    );
}


/// Supplementary Unicode description cannot be represented by strict UCS-2.
unittest
{
    auto measured =
        measureId3v23UserUrlPayload(
            "\U0001F600",
            "example.com"
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


/// Malformed UTF-8 description remains a structured serialization error.
unittest
{
    const malformed =
        cast(string)
            [
                cast(char) 'A',
                cast(char) 0xC3
            ];


    auto measured =
        measureId3v23UserUrlPayload(
            malformed,
            "example.com"
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
        measured.error.index ==
        1
    );
}


/// Malformed UTF-8 URL remains a structured serialization error.
unittest
{
    const malformed =
        cast(string)
            [
                cast(char) 'x',
                cast(char) 0xC3
            ];


    auto measured =
        measureId3v23UserUrlPayload(
            "home",
            malformed
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
        measured.error.index ==
        1
    );
}


/// Measurement and serialization remain exactly synchronized.
unittest
{
    auto latinMeasured =
        measureId3v23UserUrlPayload(
            "homepage",
            "https://example.test/"
        );


    auto latinSerialized =
        serializeId3v23UserUrlPayload(
            "homepage",
            "https://example.test/"
        );


    assert(latinMeasured.hasValue);
    assert(latinSerialized.hasValue);

    assert(
        latinMeasured.value ==
        latinSerialized.value.length
    );


    auto unicodeMeasured =
        measureId3v23UserUrlPayload(
            "\u03A9",
            "x\u00E9"
        );


    auto unicodeSerialized =
        serializeId3v23UserUrlPayload(
            "\u03A9",
            "x\u00E9"
        );


    assert(unicodeMeasured.hasValue);
    assert(unicodeSerialized.hasValue);

    assert(
        unicodeMeasured.value ==
        unicodeSerialized.value.length
    );
}
