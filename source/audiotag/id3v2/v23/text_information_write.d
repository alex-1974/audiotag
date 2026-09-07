/++
ID3v2.3 ordinary text-information payload serialization.

This module serializes only the semantic payload of ordinary `T***`
frames, excluding `TXXX`.

ID3v2.3 ordinary text-information frames contain exactly one native text
string:

    <encoding marker> <encoded text>

The final text normally needs no terminator because the enclosing frame
defines its extent.

Writer encoding is selected deterministically:

- ISO-8859-1 when the complete native text is losslessly representable;
- otherwise strict ID3v2.3 UCS-2 with BOM;
- otherwise serialization fails.

The module also provides the version-specific inverse of canonical TPE1
mapping. An ordered canonical artist list is represented as one native
slash-separated string.

Because the canonical reader splits TPE1 at every `/` and ID3v2.3
defines no escaping mechanism for that separator, an individual artist
value containing `/` cannot be represented losslessly and is rejected.

Empty slash-list components are retained:

    [""]         -> ""
    ["A", "B"]   -> "A/B"
    ["A", "", "B"] -> "A//B"
    ["", "A"]    -> "/A"
    ["A", ""]    -> "A/"

An empty canonical artist list has no lossless native representation.

Embedded U+0000 is rejected because the existing native decoder treats
the encoding-dependent zero sequence as the end of the single
information string.

No frame header, frame-format addition or tag-level unsynchronisation is
emitted here.
+/
module audiotag.id3v2.v23.text_information_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.text_encode :
    measureId3v23EncodedText,
    serializeId3v23EncodedText;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding;

import audiotag.id3v2.v23.text_encoding_policy :
    chooseId3v23TextEncoding;


/++
Maximum frame-data size representable by the ordinary unsigned 32-bit
ID3v2.3 frame-size field.
+/
private enum size_t maximumFrameDataSize =
    uint.max;


/++
Validates one canonical scalar text value for use as the single native
ID3v2.3 ordinary text-information string.

Encoding validity and representability are established by
`chooseId3v23TextEncoding`.

U+0000 is rejected separately because encoded-text primitives allow it,
while an ordinary text-information frame would interpret it as a native
string terminator.

Params:
    value = Canonical UTF-8 text value.

Returns:
    Selected native encoding or a structured serialization failure.
+/
private SerializationResult!Id3v23TextEncoding
validateId3v23TextInformationValue(
    string value
)
    @safe
{
    const(string)[] values =
        [
            value
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


    /*
     * U+0000 is encoded as one zero UTF-8 code unit, so the raw UTF-8
     * byte index is also the canonical string offset of that scalar.
     *
     * Encoding validity was already established above.
     */
    foreach (
        byteIndex,
        valueByte;
        value
    )
    {
        if (
            valueByte ==
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
Measures one scalar ordinary ID3v2.3 text-information payload.

The returned size includes the one-byte native encoding marker.

No trailing terminator is required. Therefore an empty scalar value is
represented by the encoding marker alone.

Params:
    value = Canonical UTF-8 text.

Returns:
    Complete semantic payload size or a structured serialization
    failure.
+/
SerializationResult!size_t
measureId3v23TextInformationPayload(
    string value
)
    @safe
{
    auto encoding =
        validateId3v23TextInformationValue(
            value
        );


    if (
        encoding.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    encoding.error
                );
    }


    auto encoded =
        measureId3v23EncodedText(
            value,
            encoding.value
        );


    if (
        encoded.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    encoded.error
                );
    }


    /*
     * The complete payload also contains the one-byte encoding marker.
     */
    if (
        encoded.value >
        maximumFrameDataSize -
        1
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
                            encoded.value +
                            1UL,
                        maximumFrameDataSize
                    )
                );
    }


    return
        SerializationResult!size_t
            .success(
                encoded.value +
                1
            );
}


/++
Serializes one scalar ordinary ID3v2.3 text-information payload.

The output begins with the selected encoding marker and is followed by
exactly one encoded native information string.

Params:
    value = Canonical UTF-8 text.

Returns:
    Owned semantic payload bytes or the validation error reported by
    `measureId3v23TextInformationPayload`.
+/
SerializationResult!(ubyte[])
serializeId3v23TextInformationPayload(
    string value
)
    @safe
{
    auto measured =
        measureId3v23TextInformationPayload(
            value
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


    const(string)[] values =
        [
            value
        ];


    auto encoding =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        encoding.hasValue
    );


    auto encoded =
        serializeId3v23EncodedText(
            value,
            encoding.value
        );


    assert(
        encoded.hasValue
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
            encoding.value;


    if (
        encoded.value.length !=
        0
    )
    {
        output[
            position ..
            position + encoded.value.length
        ] =
            encoded.value[];


        position +=
            encoded.value.length;
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
Constructs the one native slash-separated TPE1 information string from
an ordered canonical artist list.

No escaping mechanism exists in the current ID3v2.3 canonical mapping.
Therefore `/` inside one logical artist component is rejected.

Empty components themselves are valid and preserved exactly.

Params:
    values = Ordered canonical artist values.

Returns:
    Owned UTF-8 native information string or a structured serialization
    failure.
+/
private SerializationResult!string
joinId3v23SlashList(
    const(string)[] values
)
    @safe
{
    if (
        values.length ==
        0
    )
    {
        return
            SerializationResult!string
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidLength
                    )
                );
    }


    char[] joined;


    foreach (
        valueIndex,
        value;
        values
    )
    {
        /*
         * A slash inside one canonical component would be interpreted as
         * another list boundary when the resulting TPE1 is parsed again.
         */
        foreach (
            byteIndex,
            valueByte;
            value
        )
        {
            if (
                valueByte ==
                '/'
            )
            {
                size_t joinedOffset;


                foreach (
                    priorValueIndex;
                    0 ..
                    valueIndex
                )
                {
                    joinedOffset +=
                        values[
                            priorValueIndex
                        ].length;


                    /*
                     * Separator after every preceding component.
                     */
                    ++joinedOffset;
                }


                joinedOffset +=
                    byteIndex;


                return
                    SerializationResult!string
                        .failure(
                            SerializationError(
                                SerializationErrorCode
                                    .unsupportedRepresentation,
                                joinedOffset,
                                '/'
                            )
                        );
            }
        }


        joined ~=
            value;


        if (
            valueIndex + 1 <
            values.length
        )
        {
            joined ~=
                '/';
        }
    }


    return
        SerializationResult!string
            .success(
                joined.idup
            );
}


/++
Measures the ID3v2.3 ordinary text-information payload required for one
canonical ordered TPE1 artist list.

The list is first transformed to the exact native slash-separated
single-string representation and then measured through the ordinary
scalar payload codec.

Params:
    values = Ordered canonical artist values.

Returns:
    Complete semantic payload size or a structured serialization
    failure.
+/
SerializationResult!size_t
measureId3v23SlashListTextInformationPayload(
    const(string)[] values
)
    @safe
{
    auto joined =
        joinId3v23SlashList(
            values
        );


    if (
        joined.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    joined.error
                );
    }


    return
        measureId3v23TextInformationPayload(
            joined.value
        );
}


/++
Serializes one canonical ordered TPE1 artist list as a single native
ID3v2.3 slash-separated text-information payload.

Params:
    values = Ordered canonical artist values.

Returns:
    Owned semantic payload bytes or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeId3v23SlashListTextInformationPayload(
    const(string)[] values
)
    @safe
{
    auto joined =
        joinId3v23SlashList(
            values
        );


    if (
        joined.hasError
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    joined.error
                );
    }


    return
        serializeId3v23TextInformationPayload(
            joined.value
        );
}


/// A normal scalar title uses compact Latin-1.
unittest
{
    auto measured =
        measureId3v23TextInformationPayload(
            "Title"
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        6
    );


    auto serialized =
        serializeId3v23TextInformationPayload(
            "Title"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,
            'T', 'i', 't', 'l', 'e'
        ]
    );
}


/// Latin-1 non-ASCII text remains on encoding marker $00.
unittest
{
    auto serialized =
        serializeId3v23TextInformationPayload(
            "Gr\u00F6\u00DFe"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,
            'G', 'r',
            0xF6,
            0xDF,
            'e'
        ]
    );
}


/// Wider BMP text promotes the native payload to UCS-2.
unittest
{
    auto serialized =
        serializeId3v23TextInformationPayload(
            "A\u03A9"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x01,
            0xFE, 0xFF,
            0x00, 0x41,
            0x03, 0xA9
        ]
    );
}


/// An empty scalar value is represented by the encoding marker alone.
unittest
{
    auto measured =
        measureId3v23TextInformationPayload(
            ""
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        1
    );


    auto serialized =
        serializeId3v23TextInformationPayload(
            ""
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [0x00]
    );
}


/// Embedded NUL would terminate the native value and is rejected.
unittest
{
    auto measured =
        measureId3v23TextInformationPayload(
            "A\0B"
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


/// Supplementary Unicode remains outside strict ID3v2.3 UCS-2.
unittest
{
    auto measured =
        measureId3v23TextInformationPayload(
            "\U0001F600"
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
}


/// Malformed UTF-8 remains a structured writer error.
unittest
{
    const malformed =
        cast(string)
            [
                cast(char) 'A',
                cast(char) 0xC3
            ];


    auto measured =
        measureId3v23TextInformationPayload(
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


/// Ordered canonical artists become one slash-separated native TPE1 value.
unittest
{
    const(string)[] values =
        [
            "Artist A",
            "Artist B",
            "Artist C"
        ];


    auto serialized =
        serializeId3v23SlashListTextInformationPayload(
            values
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,

            'A', 'r', 't', 'i', 's', 't', ' ', 'A',
            '/',

            'A', 'r', 't', 'i', 's', 't', ' ', 'B',
            '/',

            'A', 'r', 't', 'i', 's', 't', ' ', 'C'
        ]
    );
}


/// Empty artist components survive exact slash-list reconstruction.
unittest
{
    const(string)[] values =
        [
            "",
            "A",
            "",
            "B",
            ""
        ];


    auto serialized =
        serializeId3v23SlashListTextInformationPayload(
            values
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,
            '/',
            'A',
            '/',
            '/',
            'B',
            '/'
        ]
    );
}


/// One explicit empty canonical artist remains one empty native TPE1.
unittest
{
    const(string)[] values =
        [
            ""
        ];


    auto serialized =
        serializeId3v23SlashListTextInformationPayload(
            values
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [0x00]
    );
}


/// An empty canonical artist list has no native inverse.
unittest
{
    const(string)[] values = [];


    auto measured =
        measureId3v23SlashListTextInformationPayload(
            values
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .invalidLength
    );
}


/// Slash inside one artist component would change canonical cardinality.
unittest
{
    const(string)[] values =
        [
            "AC/DC",
            "Guest"
        ];


    auto measured =
        measureId3v23SlashListTextInformationPayload(
            values
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
        '/'
    );
}


/// Wider characters promote the complete reconstructed TPE1 to UCS-2.
unittest
{
    const(string)[] values =
        [
            "A",
            "\u03A9"
        ];


    auto serialized =
        serializeId3v23SlashListTextInformationPayload(
            values
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x01,
            0xFE, 0xFF,

            0x00, 0x41,
            0x00, 0x2F,
            0x03, 0xA9
        ]
    );
}


/// NUL inside a list component remains unrepresentable after joining.
unittest
{
    const(string)[] values =
        [
            "A",
            "B\0C"
        ];


    auto measured =
        measureId3v23SlashListTextInformationPayload(
            values
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


/// Measurement and serialization agree for scalar and slash-list payloads.
unittest
{
    auto scalarMeasured =
        measureId3v23TextInformationPayload(
            "\u03A9"
        );


    auto scalarSerialized =
        serializeId3v23TextInformationPayload(
            "\u03A9"
        );


    assert(scalarMeasured.hasValue);
    assert(scalarSerialized.hasValue);

    assert(
        scalarMeasured.value ==
        scalarSerialized.value.length
    );


    const(string)[] artists =
        [
            "A",
            "",
            "B"
        ];


    auto listMeasured =
        measureId3v23SlashListTextInformationPayload(
            artists
        );


    auto listSerialized =
        serializeId3v23SlashListTextInformationPayload(
            artists
        );


    assert(listMeasured.hasValue);
    assert(listSerialized.hasValue);

    assert(
        listMeasured.value ==
        listSerialized.value.length
    );
}
