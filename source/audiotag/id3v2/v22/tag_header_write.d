/++
ID3v2.2 fixed tag-header serialization.

This module serializes only the fixed ten-byte ID3v2.2.0 tag header.

The encoded `tagSize` describes the physical tag body following the header and
excludes the ten-byte header itself.

ID3v2.2.0 header layout:

    3 bytes  "ID3"
    1 byte   major version = 2
    1 byte   revision = 0
    1 byte   flags
    4 bytes  28-bit synchsafe tag size

Defined ID3v2.2 header flags are:

- `0x80` whole-tag unsynchronisation;
- `0x40` whole-tag compression.

The lower six flag bits are reserved and must be zero.

`sourceOffset` is parser provenance and is intentionally not serialized.

This low-level serializer validates header syntax only. It does not construct,
compress, unsynchronise, or otherwise transform a tag body. Higher writer
layers are responsible for ensuring that the chosen flags agree with the
physical body representation.

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
module audiotag.id3v2.v22.tag_header_write;

import audiotag.core.numeric :
    encodeSynchsafe32;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v22.header :
    Id3v22Header;


private enum uint maximumId3v22TagSize =
    0x0FFF_FFFF;


/++
Validates and serializes one fixed ID3v2.2.0 tag header.

The major version is always emitted as `2` and the revision as `0`.

The supplied header must therefore describe the exact revision supported by the
writer: `header.revision` must be zero. Only the two ID3v2.2-defined flag bits
may be set.

The tag-size field is encoded as a 28-bit synchsafe integer and describes the
complete physical tag body after any outer transformation such as whole-tag
unsynchronisation.

Params:
    header = Parsed or constructed ID3v2.2 header values.

Returns:
    Exact ten encoded header bytes or a structured serialization failure.

Error semantics:
    A non-zero revision reports `invalidValue` at byte index 4.
    Reserved header flag bits report `invalidFlags` at byte index 5.
    A tag size outside the 28-bit synchsafe domain reports `valueOutOfRange` at
    byte index 6.

Safety:
    No source memory is retained by the result. The function performs no
    allocation and does not mutate `header`.
+/
SerializationResult!(ubyte[10])
serializeId3v22Header(
    const(Id3v22Header) header
)
    @safe pure nothrow @nogc
{
    if (header.revision != 0)
    {
        return
            SerializationResult!(ubyte[10])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        4,
                        header.revision,
                        0
                    )
                );
    }

    /*
     * ID3v2.2 defines only bits 7 and 6:
     *
     *   0x80 whole-tag unsynchronisation
     *   0x40 whole-tag compression
     */
    if (
        (
            header.flags &
            0x3F
        ) != 0
    )
    {
        return
            SerializationResult!(ubyte[10])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidFlags,
                        5,
                        header.flags,
                        0xC0
                    )
                );
    }

    if (
        header.tagSize >
        maximumId3v22TagSize
    )
    {
        return
            SerializationResult!(ubyte[10])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        6,
                        header.tagSize,
                        maximumId3v22TagSize
                    )
                );
    }

    const encodedSize =
        encodeSynchsafe32(
            header.tagSize
        );

    /*
     * The explicit 28-bit range check above guarantees that this internal
     * encoding operation succeeds.
     */
    assert(encodedSize.hasValue);

    ubyte[10] result;

    result[0] = 'I';
    result[1] = 'D';
    result[2] = '3';

    result[3] = 0x02;
    result[4] = 0x00;
    result[5] = header.flags;

    foreach (
        index;
        0 .. 4
    )
    {
        result[6 + index] =
            encodedSize.value[index];
    }

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

    import audiotag.id3v2.v22.header :
        parseId3v22Header;


    private Id3v22Header
    testHeader(
        uint tagSize = 0,
        ubyte flags = 0,
        ubyte revision = 0,
        size_t sourceOffset = 0
    )
        @safe pure nothrow @nogc
    {
        return
            Id3v22Header(
                sourceOffset,
                revision,
                flags,
                tagSize
            );
    }
}


/// A minimal ID3v2.2.0 header serializes to exactly ten bytes.
unittest
{
    const header =
        testHeader();

    const serialized =
        serializeId3v22Header(
            header
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'I', 'D', '3',
            0x02,
            0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ]
    );
}


/// Both defined ID3v2.2 header flags are retained structurally.
unittest
{
    const header =
        testHeader(
            1,
            0xC0
        );

    const serialized =
        serializeId3v22Header(
            header
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'I', 'D', '3',
            0x02,
            0x00,
            0xC0,
            0x00, 0x00, 0x00, 0x01
        ]
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[]
            )
        );

    auto parsed =
        cursor.parseId3v22Header();

    assert(parsed.hasValue);
    assert(cursor.empty);

    assert(parsed.value.revision == 0);
    assert(parsed.value.flags == 0xC0);
    assert(parsed.value.unsynchronisation);
    assert(parsed.value.compressed);
    assert(parsed.value.tagSize == 1);
}


/// A representative synchsafe size round-trips through the strict parser.
unittest
{
    const header =
        testHeader(
            33140,
            0x80
        );

    const serialized =
        serializeId3v22Header(
            header
        );

    assert(serialized.hasValue);

    assert(
        serialized.value[6 .. 10] ==
        [
            0x00,
            0x02,
            0x02,
            0x74
        ]
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[],
                500
            )
        );

    auto parsed =
        cursor.parseId3v22Header();

    assert(parsed.hasValue);
    assert(cursor.empty);

    assert(parsed.value.sourceOffset == 500);
    assert(parsed.value.revision == 0);
    assert(parsed.value.unsynchronisation);
    assert(!parsed.value.compressed);
    assert(parsed.value.tagSize == 33140);
}


/// Parser provenance does not enter serialized header bytes.
unittest
{
    const first =
        testHeader(
            123,
            0x40,
            0,
            100
        );

    const second =
        testHeader(
            123,
            0x40,
            0,
            9000
        );

    const firstBytes =
        serializeId3v22Header(
            first
        );

    const secondBytes =
        serializeId3v22Header(
            second
        );

    assert(firstBytes.hasValue);
    assert(secondBytes.hasValue);

    assert(
        firstBytes.value ==
        secondBytes.value
    );
}


/// The v2.2 writer emits revision zero only.
unittest
{
    foreach (
        revision;
        [
            0x01,
            0x7F,
            0xFF
        ]
    )
    {
        const serialized =
            serializeId3v22Header(
                testHeader(
                    0,
                    0,
                    cast(ubyte) revision
                )
            );

        assert(serialized.hasError);

        assert(
            serialized.error.code ==
            SerializationErrorCode
                .invalidValue
        );

        assert(serialized.error.index == 4);
        assert(
            serialized.error.value ==
            revision
        );
        assert(serialized.error.limit == 0);
    }
}


/// Every reserved low header-flag bit is rejected.
unittest
{
    foreach (
        bit;
        0 .. 6
    )
    {
        const flag =
            cast(ubyte)
                (1u << bit);

        const serialized =
            serializeId3v22Header(
                testHeader(
                    0,
                    flag
                )
            );

        assert(serialized.hasError);

        assert(
            serialized.error.code ==
            SerializationErrorCode
                .invalidFlags
        );

        assert(serialized.error.index == 5);
        assert(serialized.error.value == flag);
        assert(serialized.error.limit == 0xC0);
    }
}


/// The maximum 28-bit ID3 tag size is representable.
unittest
{
    const serialized =
        serializeId3v22Header(
            testHeader(
                0x0FFF_FFFF
            )
        );

    assert(serialized.hasValue);

    assert(
        serialized.value[6 .. 10] ==
        [
            0x7F,
            0x7F,
            0x7F,
            0x7F
        ]
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[]
            )
        );

    auto parsed =
        cursor.parseId3v22Header();

    assert(parsed.hasValue);
    assert(cursor.empty);

    assert(
        parsed.value.tagSize ==
        0x0FFF_FFFF
    );
}


/// Values beyond the 28-bit synchsafe size domain are rejected.
unittest
{
    const serialized =
        serializeId3v22Header(
            testHeader(
                0x1000_0000
            )
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .valueOutOfRange
    );

    assert(serialized.error.index == 6);
    assert(
        serialized.error.value ==
        0x1000_0000
    );
    assert(
        serialized.error.limit ==
        0x0FFF_FFFF
    );
}


/// Unsynchronisation alone is structurally serializable at the header layer.
unittest
{
    const serialized =
        serializeId3v22Header(
            testHeader(
                10,
                0x80
            )
        );

    assert(serialized.hasValue);
    assert(serialized.value[5] == 0x80);
}


/// Compression alone is structurally serializable at the header layer.
unittest
{
    /*
     * Whether a compressed source can be regenerated is a higher-level writer
     * policy decision. The fixed header serializer only validates v2.2 syntax.
     */
    const serialized =
        serializeId3v22Header(
            testHeader(
                10,
                0x40
            )
        );

    assert(serialized.hasValue);
    assert(serialized.value[5] == 0x40);
}
