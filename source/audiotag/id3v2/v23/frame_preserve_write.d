/++
Logical native serialization of one unchanged preserved ID3v2.3 frame.

An unchanged native frame is reconstructed without semantic
regeneration:

- the parsed fixed frame-header values are serialized back into their
  unique ordinary ID3v2.3 ten-byte representation;
- for a normal source tag, the bounded native frame-data region is
  copied unchanged;
- for a whole-tag-unsynchronised source, the bounded physical frame-data
  region is traversed logically and stuffing bytes are removed.

The result is always an ordinary logical/native frame. Any required
ID3v2.3 whole-tag unsynchronisation is applied later to the complete
assembled tag body.

This preserves:

- native frame identifier;
- logical frame-data size;
- status flags;
- format flags;
- grouping/encryption/compression additions inside frame data;
- compressed or encrypted payload bytes;
- unknown semantic payload bytes.

`sourceOffset` is provenance and is intentionally not serialized.

Unlike ID3v2.4 frame-level unsynchronisation, v2.3 unsynchronisation is
applied across the complete tag body. Stuffing bytes may therefore occur
inside both frame headers and frame data.

The parsed frame header already represents its logical values and can be
serialized canonically. The bounded physical frame-data span is decoded
through `Id3v23DataCursor` when the source tag was unsynchronised.

This deliberately preserves native logical bytes rather than attempting
to preserve source physical stuffing. The complete tag writer later
decides and applies one coherent whole-tag unsynchronisation transform.

No tag header, padding or container bytes are serialized here.
+/
module audiotag.id3v2.v23.frame_preserve_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.frame :
    Id3v23FrameEnvelope;

import audiotag.id3v2.v23.frame_header_write :
    serializeId3v23FrameHeader;


/++
Serializes one unchanged provenance-preserved ID3v2.3 frame.

Preservation is defined at the native logical-frame level. For a
whole-tag-unsynchronised source, physical stuffing is removed before the
frame is returned to the sequence/tag writer.

Params:
    frame = Original unchanged frame envelope.
    sourceTagUnsynchronised = Whether the enclosing source ID3v2.3 tag
        used whole-tag unsynchronisation.

Returns:
    Complete owned logical/native frame bytes, or a structured
    serialization failure when the supplied preserved envelope is
    inconsistent with its declared logical frame-data size.

Safety:
    No source bytes are modified. Output owns its copied bytes.
+/
SerializationResult!(ubyte[])
serializePreservedId3v23Frame(
    const(Id3v23FrameEnvelope) frame,
    bool sourceTagUnsynchronised = false
)
    @safe
{
    auto encodedHeader =
        serializeId3v23FrameHeader(
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

    ubyte[] logicalData;

    if (sourceTagUnsynchronised)
    {
        /*
         * `frame.data` retains the physical bytes consumed for exactly
         * `frame.header.size` logical frame-data bytes. Decode that
         * bounded region without interpreting its native contents.
         *
         * This works equally for unknown, compressed and encrypted frame
         * data because whole-tag unsynchronisation is purely a byte-stream
         * transformation.
         */
        logicalData =
            new ubyte[
                cast(size_t)
                    frame.header.size
            ];

        auto cursor =
            Id3v23DataCursor(
                frame.data,
                true
            );

        foreach (index; 0 .. logicalData.length)
        {
            auto decoded =
                cursor.takeByte();

            if (decoded.hasError)
            {
                return
                    SerializationResult!(ubyte[])
                        .failure(
                            SerializationError(
                                SerializationErrorCode
                                    .inconsistentStructure,
                                index,
                                frame.data.length,
                                frame.header.size
                            )
                        );
            }

            logicalData[index] =
                decoded.value.value;
        }

        /*
         * A parser-produced frame envelope must contain neither fewer nor
         * additional physical bytes after exactly the declared logical
         * frame data have been recovered.
         */
        if (!cursor.empty)
        {
            return
                SerializationResult!(ubyte[])
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .inconsistentStructure,
                            logicalData.length,
                            frame.data.length,
                            frame.header.size
                        )
                    );
        }
    }
    else
    {
        if (
            frame.data.length !=
            frame.header.size
        )
        {
            return
                SerializationResult!(ubyte[])
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .inconsistentStructure,
                            0,
                            frame.data.length,
                            frame.header.size
                        )
                    );
        }

        logicalData =
            frame.data.data.dup;
    }

    auto output =
        new ubyte[
            encodedHeader.value.length +
            logicalData.length
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
        logicalData;

    return
        SerializationResult!(ubyte[])
            .success(output);
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.data_cursor :
        Id3v23DataCursor;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;


    private Id3v23FrameEnvelope
    parseTestFrame(
        const(ubyte)[] bytes,
        size_t sourceOffset = 0,
        bool tagUnsynchronised = false
    )
        @safe
    {
        auto cursor =
            Id3v23DataCursor(
                ByteSpan(
                    bytes,
                    sourceOffset
                ),
                tagUnsynchronised
            );

        auto parsed =
            cursor.parseId3v23FrameEnvelope();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }
}


/// A plain unchanged v2.3 frame roundtrips byte-for-byte.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x00,
            'T', 'i', 't', 'l', 'e'
        ];

    const frame =
        parseTestFrame(
            bytes,
            1000
        );

    auto serialized =
        serializePreservedId3v23Frame(
            frame
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        bytes
    );
}


/// Native v2.3 status and format flags are retained exactly.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x05,

            /*
             * discard-on-tag,
             * discard-on-file,
             * read-only
             */
            0xE0,

            /*
             * compression,
             * encryption,
             * grouping
             */
            0xE0,

            /*
             * Opaque physical frame-data region.
             */
            0x2A,
            0x10,
            0x20,
            0x30,
            0x40
        ];

    const frame =
        parseTestFrame(bytes);

    auto serialized =
        serializePreservedId3v23Frame(
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
        serializePreservedId3v23Frame(
            frame
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        bytes
    );

    /*
     * Absolute source provenance is not emitted.
     */
    assert(
        serialized.value.length ==
        15
    );
}


/// Ordinary zero and FF bytes require no transformation by preservation.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            0x00,
            0xFF,
            0xE1,
            0xFF,
            0x00
        ];

    const frame =
        parseTestFrame(bytes);

    auto serialized =
        serializePreservedId3v23Frame(
            frame
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        bytes
    );
}


/// Whole-tag-unsynchronised source data are restored to logical bytes.
unittest
{
    /*
     * Logical frame data:
     *
     *     FF E1
     *
     * Physical whole-tag-unsynchronised source data:
     *
     *     FF 00 E1
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0xFF, 0x00, 0xE1
        ];

    const frame =
        parseTestFrame(
            bytes,
            3000,
            true
        );

    assert(frame.header.size == 2);
    assert(frame.data.length == 3);

    auto serialized =
        serializePreservedId3v23Frame(
            frame,
            true
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0xFF, 0xE1
        ]
    );
}


/// Logical FF 00 source data remain exact native bytes after decoding.
unittest
{
    /*
     * With whole-tag unsynchronisation active:
     *
     *     logical  FF 00
     *     physical FF 00 00
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0xFF, 0x00, 0x00
        ];

    const frame =
        parseTestFrame(
            bytes,
            4000,
            true
        );

    auto serialized =
        serializePreservedId3v23Frame(
            frame,
            true
        );

    assert(serialized.hasValue);

    assert(
        serialized.value[$ - 2 .. $] ==
        [0xFF, 0x00]
    );
}


/// Stuffing inside the physical frame header is not preserved physically.
unittest
{
    /*
     * Logical header:
     *
     *     size   = 00 00 00 FF
     *     status = 00
     *
     * With whole-tag unsynchronisation active the boundary becomes:
     *
     *     FF 00 00
     *        ^  ^
     *        |  logical status
     *        stuffing
     */
    ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0xFF,

            // Stuffing after the final size byte.
            0x00,

            // Logical status and format flags.
            0x00, 0x00
        ];

    bytes.length =
        bytes.length + 255;

    foreach (
        index;
        bytes.length - 255 ..
        bytes.length
    )
    {
        bytes[index] =
            0x42;
    }

    const frame =
        parseTestFrame(
            bytes,
            5000,
            true
        );

    assert(frame.header.size == 255);
    assert(frame.data.length == 255);

    auto serialized =
        serializePreservedId3v23Frame(
            frame,
            true
        );

    assert(serialized.hasValue);

    /*
     * The result is the logical/native frame, so the header is exactly ten
     * bytes again and contains no source stuffing.
     */
    assert(serialized.value.length == 10 + 255);

    assert(
        serialized.value[0 .. 10] ==
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0xFF,
            0x00, 0x00
        ]
    );

    foreach (
        value;
        serialized.value[10 .. $]
    )
    {
        assert(value == 0x42);
    }
}


/// Inconsistent unsynchronised physical data are rejected defensively.
unittest
{
    /*
     * Header declares two logical bytes, but physical FF 00 decodes to
     * only one logical byte.
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0xFF, 0x00
        ];

    /*
     * Construct directly because the structural parser correctly rejects
     * this truncated logical frame.
     */
    import audiotag.id3v2.v23.frame_header :
        Id3v23FrameHeader;

    const frame =
        Id3v23FrameEnvelope(
            Id3v23FrameHeader(
                0,
                ['A', 'B', 'C', '1'],
                2,
                0,
                0
            ),
            ByteSpan(
                bytes[10 .. $],
                10
            )
        );

    auto serialized =
        serializePreservedId3v23Frame(
            frame,
            true
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );
}
