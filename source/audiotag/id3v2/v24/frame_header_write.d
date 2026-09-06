/++
ID3v2.4 fixed frame-header serialization.

This module serializes exactly the ten-byte native frame header:

- four-byte frame identifier;
- four-byte synchsafe frame-data size;
- status flags;
- format flags.

Frame payload serialization is deliberately separate.

The same structural constraints accepted by the active reader are
enforced before any output bytes are returned.
+/
module audiotag.id3v2.v24.frame_header_write;

import audiotag.core.numeric :
    encodeSynchsafe32;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v24.frame_header :
    Id3v24FrameHeader;


/++
Returns whether one byte is valid in an ID3v2.4 frame identifier.
+/
private bool isValidId3v24FrameIdByte(
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
Serializes one validated ID3v2.4 frame header.

`sourceOffset` is parser provenance and is intentionally not encoded.

The frame-data size:

- excludes the ten-byte frame header;
- must be non-zero;
- must fit the 28-bit synchsafe representation.

The function also rejects reserved flag bits and compression without the
required Data Length Indicator.

Params:
    header = Native frame header values to serialize.

Returns:
    Exact ten encoded bytes or a structured serialization failure.
+/
SerializationResult!(ubyte[10])
serializeId3v24FrameHeader(
    const(Id3v24FrameHeader) header
)
    @safe pure nothrow @nogc
{
    foreach (index; 0 .. 4)
    {
        const value =
            header.id[index];

        if (
            !isValidId3v24FrameIdByte(
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
                        0x0FFF_FFFF
                    )
                );
    }

    if (
        header.size >
        0x0FFF_FFFF
    )
    {
        return
            SerializationResult!(ubyte[10])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        4,
                        header.size,
                        0x0FFF_FFFF
                    )
                );
    }

    // Status flags are %0abc0000.
    if (
        (
            header.statusFlags &
            0x8F
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
                        0x70
                    )
                );
    }

    // Format flags are %0h00kmnp.
    if (
        (
            header.formatFlags &
            0xB0
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
                        0x4F
                    )
                );
    }

    if (
        header.compressed &&
        !header.hasDataLengthIndicator
    )
    {
        return
            SerializationResult!(ubyte[10])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        9,
                        header.formatFlags
                    )
                );
    }

    const sizeResult =
        encodeSynchsafe32(
            header.size
        );

    /*
     * The explicit size-domain check above guarantees this internal
     * encoder call cannot fail.
     */
    assert(sizeResult.hasValue);

    ubyte[10] result;

    foreach (index; 0 .. 4)
    {
        result[index] =
            cast(ubyte)
                header.id[index];
    }

    foreach (index; 0 .. 4)
    {
        result[4 + index] =
            sizeResult.value[index];
    }

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

    import audiotag.id3v2.v24.frame_header :
        parseId3v24FrameHeader;


    private Id3v24FrameHeader testHeader(
        uint size = 33140,
        ubyte statusFlags = 0,
        ubyte formatFlags = 0
    )
        @safe pure nothrow @nogc
    {
        Id3v24FrameHeader result;

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
        serializeId3v24FrameHeader(
            header
        );

    assert(encoded.hasValue);

    assert(
        encoded.value[] ==
        [
            'T', 'I', 'T', '2',
            0x00, 0x02, 0x02, 0x74,
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
            0x70,
            0x4F
        );

    const encoded =
        serializeId3v24FrameHeader(
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
        cursor.parseId3v24FrameHeader();

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
        serializeId3v24FrameHeader(
            first
        );

    const encodedSecond =
        serializeId3v24FrameHeader(
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
        serializeId3v24FrameHeader(
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


/// Zero-sized frames are invalid in ID3v2.4.
unittest
{
    const encoded =
        serializeId3v24FrameHeader(
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


/// Frame sizes must fit the 28-bit synchsafe domain.
unittest
{
    const encoded =
        serializeId3v24FrameHeader(
            testHeader(
                0x1000_0000
            )
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .valueOutOfRange
    );

    assert(
        encoded.error.value ==
        0x1000_0000
    );
}


/// Reserved status flag bits are rejected.
unittest
{
    const encoded =
        serializeId3v24FrameHeader(
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
        serializeId3v24FrameHeader(
            testHeader(
                1,
                0x00,
                0x10
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


/// Compression without a Data Length Indicator is inconsistent.
unittest
{
    const encoded =
        serializeId3v24FrameHeader(
            testHeader(
                1,
                0x00,
                0x08
            )
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );

    assert(encoded.error.index == 9);
}


/// Compression with its required DLI remains structurally serializable.
unittest
{
    const encoded =
        serializeId3v24FrameHeader(
            testHeader(
                1,
                0x00,
                0x09
            )
        );

    assert(encoded.hasValue);

    assert(encoded.value[8] == 0x00);
    assert(encoded.value[9] == 0x09);
}
