/++
ID3v2.3 fixed frame-header serialization.

This module serializes exactly the ten-byte native frame header:

- four-byte frame identifier;
- four-byte unsigned big-endian frame-data size;
- status flags;
- format flags.

Frame payload serialization and frame-format additions are deliberately
separate.

The same structural constraints accepted by the active reader are
enforced before any output bytes are returned.
+/
module audiotag.id3v2.v23.frame_header_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.frame_header :
    Id3v23FrameHeader;


/++
Returns whether one byte is valid in an ID3v2.3 frame identifier.
+/
private bool isValidId3v23FrameIdByte(
    char value
)
    @safe pure nothrow @nogc
{
    return
        (
            value >= 'A' &&
            value <= 'Z'
        ) ||
        (
            value >= '0' &&
            value <= '9'
        );
}


/++
Serializes one validated ID3v2.3 frame header.

`sourceOffset` is parser provenance and is intentionally not encoded.

The frame-data size:

- excludes the ten-byte frame header;
- must be non-zero;
- uses the complete unsigned 32-bit big-endian domain.

Only the three ID3v2.3-defined bits in each flag byte are accepted.

Params:
    header = Native frame header values to serialize.

Returns:
    Exact ten encoded bytes or a structured serialization failure.
+/
SerializationResult!(ubyte[10])
serializeId3v23FrameHeader(
    const(Id3v23FrameHeader) header
)
    @safe pure nothrow @nogc
{
    foreach (index; 0 .. 4)
    {
        const value =
            header.id[index];

        if (
            !isValidId3v23FrameIdByte(
                value
            )
        )
        {
            return
                SerializationResult!(ubyte[10])
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .invalidValue,
                            index,
                            cast(ubyte) value
                        )
                    );
        }
    }

    if (header.size == 0)
    {
        return
            SerializationResult!(ubyte[10])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidLength,
                        4,
                        0,
                        0xFFFF_FFFF
                    )
                );
    }

    /*
     * ID3v2.3 status flags are %abc00000:
     *
     *   0x80 discard on tag alter
     *   0x40 discard on file alter
     *   0x20 read only
     */
    if (
        (
            header.statusFlags &
            0x1F
        ) != 0
    )
    {
        return
            SerializationResult!(ubyte[10])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidFlags,
                        8,
                        header.statusFlags,
                        0xE0
                    )
                );
    }

    /*
     * ID3v2.3 format flags are %ijk00000:
     *
     *   0x80 compression
     *   0x40 encryption
     *   0x20 grouping identity
     */
    if (
        (
            header.formatFlags &
            0x1F
        ) != 0
    )
    {
        return
            SerializationResult!(ubyte[10])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidFlags,
                        9,
                        header.formatFlags,
                        0xE0
                    )
                );
    }

    ubyte[10] result;

    foreach (index; 0 .. 4)
    {
        result[index] =
            cast(ubyte)
                header.id[index];
    }

    /*
     * Unlike ID3v2.4, the ID3v2.3 frame size is not synchsafe.
     * Serialize the complete uint value directly as big-endian bytes.
     */
    result[4] =
        cast(ubyte)
            (header.size >> 24);

    result[5] =
        cast(ubyte)
            (header.size >> 16);

    result[6] =
        cast(ubyte)
            (header.size >> 8);

    result[7] =
        cast(ubyte)
            header.size;

    result[8] =
        header.statusFlags;

    result[9] =
        header.formatFlags;

    return
        SerializationResult!(ubyte[10])
            .success(result);
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.frame_header :
        parseId3v23FrameHeader;


    private Id3v23FrameHeader testHeader(
        uint size = 33140,
        ubyte statusFlags = 0,
        ubyte formatFlags = 0
    )
        @safe pure nothrow @nogc
    {
        Id3v23FrameHeader result;

        result.sourceOffset =
            12345;

        result.id =
            ['T', 'I', 'T', '2'];

        result.size =
            size;

        result.statusFlags =
            statusFlags;

        result.formatFlags =
            formatFlags;

        return result;
    }
}


/// A normal frame header serializes to its exact ten-byte representation.
unittest
{
    const header =
        testHeader();

    const encoded =
        serializeId3v23FrameHeader(
            header
        );

    assert(encoded.hasValue);

    assert(
        encoded.value[] ==
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x81, 0x74,
            0x00, 0x00
        ]
    );
}


/// Serialized headers round-trip through the active strict parser.
unittest
{
    const original =
        testHeader(
            33140,
            0xE0,
            0xE0
        );

    const encoded =
        serializeId3v23FrameHeader(
            original
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                700
            )
        );

    auto parsed =
        cursor.parseId3v23FrameHeader();

    assert(parsed.hasValue);
    assert(cursor.empty);

    assert(parsed.value.sourceOffset == 700);

    assert(
        parsed.value.id ==
        original.id
    );

    assert(
        parsed.value.size ==
        original.size
    );

    assert(
        parsed.value.statusFlags ==
        original.statusFlags
    );

    assert(
        parsed.value.formatFlags ==
        original.formatFlags
    );
}


/// Parser provenance is not serialized into frame bytes.
unittest
{
    auto first =
        testHeader();

    auto second =
        first;

    first.sourceOffset = 10;
    second.sourceOffset = 999999;

    const encodedFirst =
        serializeId3v23FrameHeader(
            first
        );

    const encodedSecond =
        serializeId3v23FrameHeader(
            second
        );

    assert(encodedFirst.hasValue);
    assert(encodedSecond.hasValue);

    assert(
        encodedFirst.value[] ==
        encodedSecond.value[]
    );
}


/// Frame identifiers use the same strict domain as the reader.
unittest
{
    auto header =
        testHeader();

    header.id =
        ['T', 'i', 'T', '2'];

    const encoded =
        serializeId3v23FrameHeader(
            header
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .invalidValue
    );

    assert(encoded.error.index == 1);
}


/// Zero-sized frames are invalid in ID3v2.3.
unittest
{
    const encoded =
        serializeId3v23FrameHeader(
            testHeader(0)
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .invalidLength
    );

    assert(encoded.error.index == 4);
}


/// The complete unsigned 32-bit frame-size domain is representable.
unittest
{
    const encoded =
        serializeId3v23FrameHeader(
            testHeader(
                0xFFFF_FFFF
            )
        );

    assert(encoded.hasValue);

    assert(
        encoded.value[4 .. 8] ==
        [
            0xFF,
            0xFF,
            0xFF,
            0xFF
        ]
    );
}


/// Reserved status flag bits are rejected.
unittest
{
    const encoded =
        serializeId3v23FrameHeader(
            testHeader(
                1,
                0x01,
                0x00
            )
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .invalidFlags
    );

    assert(encoded.error.index == 8);
}


/// Reserved format flag bits are rejected.
unittest
{
    const encoded =
        serializeId3v23FrameHeader(
            testHeader(
                1,
                0x00,
                0x01
            )
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .invalidFlags
    );

    assert(encoded.error.index == 9);
}


/// All defined ID3v2.3 frame flags remain serializable.
unittest
{
    const encoded =
        serializeId3v23FrameHeader(
            testHeader(
                1,
                0xE0,
                0xE0
            )
        );

    assert(encoded.hasValue);

    assert(encoded.value[8] == 0xE0);
    assert(encoded.value[9] == 0xE0);
}
