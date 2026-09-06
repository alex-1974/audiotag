/++
Exact physical serialization of one unchanged preserved ID3v2.4 frame.

An unchanged native frame must not be regenerated from canonical
metadata. Its parsed fixed header values are serialized back into their
unique ID3v2.4 byte representation and its complete bounded frame-data
region is copied unchanged.

This preserves:

- native frame identifier;
- frame-data size;
- status flags;
- format flags;
- grouping/encryption/DLI bytes inside frame data;
- compression/encryption payload bytes;
- physical unsynchronisation stuffing;
- unknown semantic payload bytes.

`sourceOffset` is provenance and is intentionally not serialized.

This module performs no semantic decoding or transformation.
+/
module audiotag.id3v2.v24.frame_preserve_write;

import audiotag.core.serialization :
    SerializationResult;

import audiotag.id3v2.v24.frame :
    Id3v24FrameEnvelope;

import audiotag.id3v2.v24.frame_header_write :
    serializeId3v24FrameHeader;


/++
Serializes one unchanged provenance-preserved ID3v2.4 frame.

The fixed ten-byte header is reconstructed from its parsed values.
The bounded native frame-data bytes are copied verbatim.

Params:
    frame = Original unchanged frame envelope.

Returns:
    Complete owned native frame bytes or a structured serialization
    failure if the retained header values are internally invalid.
+/
SerializationResult!(ubyte[])
serializePreservedId3v24Frame(
    const(Id3v24FrameEnvelope) frame
)
    @safe
{
    auto encodedHeader =
        serializeId3v24FrameHeader(
            frame.header
        );

    if (encodedHeader.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    encodedHeader.error
                );
    }

    /*
     * A valid frame envelope is constructed from exactly header.size
     * bounded data bytes. A mismatch here is an internal invariant
     * violation, not malformed input newly discovered by the writer.
     */
    assert(
        frame.data.length ==
        frame.header.size
    );

    auto output =
        new ubyte[
            encodedHeader.value.length +
            frame.data.length
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
        frame.data.data;

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

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;


    private Id3v24FrameEnvelope parseTestFrame(
        const(ubyte)[] bytes,
        size_t sourceOffset = 0
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(
                    bytes,
                    sourceOffset
                )
            );

        auto parsed =
            cursor.parseId3v24FrameEnvelope();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }
}


/// A plain unchanged frame roundtrips byte-for-byte.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x03,
            'T', 'i', 't', 'l', 'e'
        ];

    const frame =
        parseTestFrame(
            bytes,
            1000
        );

    auto serialized =
        serializePreservedId3v24Frame(
            frame
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        bytes
    );
}


/// Native status and format flags are retained exactly.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x08,

            // discard-on-tag, discard-on-file
            0x60,

            // grouping + unsynchronisation + DLI
            0x43,

            // Complete opaque physical frame-data region.
            0x2A,
            0x00, 0x00, 0x00, 0x03,
            0xFF, 0x00, 0xE1
        ];

    const frame =
        parseTestFrame(bytes);

    auto serialized =
        serializePreservedId3v24Frame(
            frame
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        bytes
    );
}


/// Physical unsynchronisation stuffing remains untouched.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x02,

            0x03,
            0xFF, 0x00, 0xE1
        ];

    const frame =
        parseTestFrame(bytes);

    auto serialized =
        serializePreservedId3v24Frame(
            frame
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        bytes
    );
}


/// Unknown semantic payload bytes remain byte-identical.
unittest
{
    const ubyte[] bytes =
        [
            'X', 'Y', 'Z', '1',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            0x00,
            0xFF,
            0x7F,
            0x80,
            0x42
        ];

    const frame =
        parseTestFrame(
            bytes,
            5000
        );

    auto serialized =
        serializePreservedId3v24Frame(
            frame
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        bytes
    );

    /*
     * Source provenance itself is not emitted.
     */
    assert(
        serialized.value.length ==
        15
    );
}
