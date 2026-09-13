/++
ID3v2.2 fixed frame-header serialization.

This module serializes exactly the six-byte native frame header:

- three-byte frame identifier;
- three-byte unsigned big-endian frame-data size.

Frame payload serialization is deliberately separate.

The same structural constraints accepted by the active ID3v2.2.0 reader are
enforced before any output bytes are returned.

Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-13
+/
module audiotag.id3v2.v22.frame_header_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v22.frame_header :
    Id3v22FrameHeader;


/++
Returns whether one byte is valid in an ID3v2.2 frame identifier.

ID3v2.2 frame identifiers use only uppercase ASCII letters `A`-`Z` and digits
`0`-`9`.
+/
private bool
isValidId3v22FrameIdByte(
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
Serializes one validated ID3v2.2 frame header.

`sourceOffset` is parser provenance and is intentionally not encoded.

The frame-data size:

- excludes the six-byte frame header;
- must be non-zero;
- is encoded as an ordinary unsigned 24-bit big-endian integer;
- must not exceed `$FF_FF_FF`.

Params:
    header = Native frame-header values to serialize.

Returns:
    Exact six encoded bytes or a structured serialization failure.

Error semantics:
    Invalid frame-ID bytes report `invalidValue` at their header byte index.
    A zero frame size reports `invalidLength` at byte index 3.
    A size above the unsigned 24-bit domain reports `valueOutOfRange` at byte
    index 3.

Safety:
    No source memory is retained by the result. The function performs no
    allocation and does not mutate `header`.
+/
SerializationResult!(ubyte[6])
serializeId3v22FrameHeader(
    const(Id3v22FrameHeader) header
)
    @safe pure nothrow @nogc
{
    foreach (
        index;
        0 .. 3
    )
    {
        const value =
            header.id[index];

        if (
            !isValidId3v22FrameIdByte(
                value
            )
        )
        {
            return
                SerializationResult!(ubyte[6])
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
            SerializationResult!(ubyte[6])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidLength,
                        3,
                        0,
                        0xFF_FFFF
                    )
                );
    }

    if (
        header.size >
        0xFF_FFFF
    )
    {
        return
            SerializationResult!(ubyte[6])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        3,
                        header.size,
                        0xFF_FFFF
                    )
                );
    }

    ubyte[6] result;

    foreach (
        index;
        0 .. 3
    )
    {
        result[index] =
            cast(ubyte)
                header.id[index];
    }

    result[3] =
        cast(ubyte)
            (header.size >> 16);

    result[4] =
        cast(ubyte)
            (header.size >> 8);

    result[5] =
        cast(ubyte)
            header.size;

    return
        SerializationResult!(ubyte[6])
            .success(result);
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.frame_header :
        parseId3v22FrameHeader;


    private Id3v22FrameHeader
    testHeader(
        uint size = 33140
    )
        @safe pure nothrow @nogc
    {
        Id3v22FrameHeader result;

        result.sourceOffset =
            12345;

        result.id =
            ['T', 'T', '2'];

        result.size =
            size;

        return result;
    }
}


/// A normal frame header serializes to its exact six-byte representation.
unittest
{
    const header =
        testHeader(
            0x01_02_03
        );

    const encoded =
        serializeId3v22FrameHeader(
            header
        );

    assert(encoded.hasValue);

    assert(
        encoded.value[] ==
        [
            'T', 'T', '2',
            0x01, 0x02, 0x03
        ]
    );
}


/// Serialized headers round-trip through the active strict parser.
unittest
{
    const original =
        testHeader(
            33140
        );

    const encoded =
        serializeId3v22FrameHeader(
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
        cursor.parseId3v22FrameHeader();

    assert(parsed.hasValue);
    assert(cursor.empty);

    assert(
        parsed.value.sourceOffset ==
        700
    );

    assert(
        parsed.value.id ==
        original.id
    );

    assert(
        parsed.value.size ==
        original.size
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
        serializeId3v22FrameHeader(
            first
        );

    const encodedSecond =
        serializeId3v22FrameHeader(
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
        ['T', 't', '2'];

    const encoded =
        serializeId3v22FrameHeader(
            header
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .invalidValue
    );

    assert(encoded.error.index == 1);
    assert(encoded.error.value == 't');
}


/// A one-byte frame payload is the minimum representable frame size.
unittest
{
    const encoded =
        serializeId3v22FrameHeader(
            testHeader(1)
        );

    assert(encoded.hasValue);

    assert(
        encoded.value[3 .. 6] ==
        [
            0x00,
            0x00,
            0x01
        ]
    );
}


/// Zero-sized frames are structurally invalid in ID3v2.2.
unittest
{
    const encoded =
        serializeId3v22FrameHeader(
            testHeader(0)
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .invalidLength
    );

    assert(encoded.error.index == 3);
    assert(encoded.error.value == 0);
    assert(encoded.error.limit == 0xFF_FFFF);
}


/// The complete unsigned 24-bit frame-size domain above zero is representable.
unittest
{
    const encoded =
        serializeId3v22FrameHeader(
            testHeader(
                0xFF_FFFF
            )
        );

    assert(encoded.hasValue);

    assert(
        encoded.value[3 .. 6] ==
        [
            0xFF,
            0xFF,
            0xFF
        ]
    );
}


/// Values above the unsigned 24-bit size domain fail explicitly.
unittest
{
    const encoded =
        serializeId3v22FrameHeader(
            testHeader(
                0x01_00_00_00
            )
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .valueOutOfRange
    );

    assert(encoded.error.index == 3);
    assert(
        encoded.error.value ==
        0x01_00_00_00
    );
    assert(
        encoded.error.limit ==
        0xFF_FFFF
    );
}


/// Experimental X/Y/Z identifiers remain structurally serializable.
unittest
{
    foreach (
        identifier;
        [
            "X01",
            "Y99",
            "ZAB"
        ]
    )
    {
        auto header =
            testHeader(1);

        header.id =
            [
                identifier[0],
                identifier[1],
                identifier[2]
            ];

        const encoded =
            serializeId3v22FrameHeader(
                header
            );

        assert(encoded.hasValue);

        assert(
            encoded.value[0 .. 3] ==
            cast(const(ubyte)[])
                identifier
        );
    }
}
