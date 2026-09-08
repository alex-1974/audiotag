/++
ID3v2.3 fixed tag-header serialization.

This module serializes only the fixed ten-byte ID3v2.3 tag header.

The encoded `tagSize` describes the physical tag body following the
header and excludes the ten-byte header itself.

ID3v2.3 header layout:

    3 bytes  "ID3"
    1 byte   major version = 3
    1 byte   revision
    1 byte   flags
    4 bytes  28-bit synchsafe tag size

Defined ID3v2.3 header flags are:

- `0x80` whole-tag unsynchronisation;
- `0x40` extended header;
- `0x20` experimental indicator.

The lower five flag bits are reserved and must be zero.

`sourceOffset` is parser provenance and is intentionally not serialized.

This module does not construct a tag body and does not apply
whole-tag unsynchronisation.
+/
module audiotag.id3v2.v23.tag_header_write;

import audiotag.core.numeric :
    encodeSynchsafe32;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.header :
    Id3v23Header;


private enum uint maximumId3v23TagSize =
    0x0FFF_FFFF;


/++
Validates and serializes one fixed ID3v2.3 tag header.

The major version is always emitted as `3`. The retained revision byte,
defined header flags and body size are serialized from `header`.

Params:
    header = Parsed or constructed ID3v2.3 header values.

Returns:
    Exact ten encoded header bytes or a structured serialization failure.
+/
SerializationResult!(ubyte[10])
serializeId3v23Header(
    const(Id3v23Header) header
)
    @safe pure nothrow @nogc
{
    /*
     * ID3 major/revision bytes may not use FF.
     *
     * The major version is fixed here at 3, so only the retained revision
     * requires validation.
     */
    if (header.revision == 0xFF)
    {
        return
            SerializationResult!(ubyte[10])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        4,
                        header.revision
                    )
                );
    }

    /*
     * ID3v2.3 defines only the upper three header-flag bits.
     */
    if (
        (
            header.flags &
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
                        5,
                        header.flags,
                        0xE0
                    )
                );
    }

    if (
        header.tagSize >
        maximumId3v23TagSize
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
                        maximumId3v23TagSize
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

    result[3] = 0x03;
    result[4] = header.revision;
    result[5] = header.flags;

    foreach (index; 0 .. 4)
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

    import audiotag.id3v2.v23.header :
        parseId3v23Header;


    private Id3v23Header testHeader(
        uint tagSize = 0,
        ubyte flags = 0,
        ubyte revision = 0,
        size_t sourceOffset = 0
    )
        @safe pure nothrow @nogc
    {
        return
            Id3v23Header(
                sourceOffset,
                revision,
                flags,
                tagSize
            );
    }
}


/// A minimal ID3v2.3.0 header serializes to exactly ten bytes.
unittest
{
    const header =
        testHeader();

    auto serialized =
        serializeId3v23Header(
            header
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'I', 'D', '3',
            0x03,
            0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ]
    );
}


/// All defined ID3v2.3 header flags are retained.
unittest
{
    const header =
        testHeader(
            1,
            0xE0,
            1
        );

    auto serialized =
        serializeId3v23Header(
            header
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'I', 'D', '3',
            0x03,
            0x01,
            0xE0,
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
        cursor.parseId3v23Header();

    assert(parsed.hasValue);
    assert(cursor.empty);

    assert(parsed.value.revision == 1);
    assert(parsed.value.flags == 0xE0);
    assert(parsed.value.unsynchronisation);
    assert(parsed.value.hasExtendedHeader);
    assert(parsed.value.experimentalIndicator);
    assert(parsed.value.tagSize == 1);
}


/// A representative synchsafe size roundtrips through the strict parser.
unittest
{
    const header =
        testHeader(
            0x0012_3456,
            0x40
        );

    auto serialized =
        serializeId3v23Header(
            header
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[],
                500
            )
        );

    auto parsed =
        cursor.parseId3v23Header();

    assert(parsed.hasValue);
    assert(cursor.empty);

    assert(parsed.value.sourceOffset == 500);
    assert(parsed.value.tagSize == 0x0012_3456);
    assert(parsed.value.hasExtendedHeader);
}


/// Parser provenance does not enter serialized header bytes.
unittest
{
    const first =
        testHeader(
            123,
            0x20,
            7,
            100
        );

    const second =
        testHeader(
            123,
            0x20,
            7,
            9000
        );

    auto firstBytes =
        serializeId3v23Header(
            first
        );

    auto secondBytes =
        serializeId3v23Header(
            second
        );

    assert(firstBytes.hasValue);
    assert(secondBytes.hasValue);

    assert(
        firstBytes.value ==
        secondBytes.value
    );
}


/// Revision FF is invalid in an ID3 version identifier.
unittest
{
    const header =
        testHeader(
            0,
            0,
            0xFF
        );

    auto serialized =
        serializeId3v23Header(
            header
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(serialized.error.index == 4);
}


/// Every reserved low header-flag bit is rejected.
unittest
{
    foreach (
        flag;
        [
            0x01,
            0x02,
            0x04,
            0x08,
            0x10
        ]
    )
    {
        const header =
            testHeader(
                0,
                cast(ubyte) flag
            );

        auto serialized =
            serializeId3v23Header(
                header
            );

        assert(serialized.hasError);

        assert(
            serialized.error.code ==
            SerializationErrorCode.invalidFlags
        );

        assert(serialized.error.index == 5);
    }
}


/// The maximum 28-bit ID3 tag size is representable.
unittest
{
    const header =
        testHeader(
            0x0FFF_FFFF
        );

    auto serialized =
        serializeId3v23Header(
            header
        );

    assert(serialized.hasValue);

    assert(
        serialized.value[6 .. 10] ==
        [0x7F, 0x7F, 0x7F, 0x7F]
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[]
            )
        );

    auto parsed =
        cursor.parseId3v23Header();

    assert(parsed.hasValue);

    assert(
        parsed.value.tagSize ==
        0x0FFF_FFFF
    );
}


/// Values beyond the 28-bit synchsafe domain are rejected.
unittest
{
    const header =
        testHeader(
            0x1000_0000
        );

    auto serialized =
        serializeId3v23Header(
            header
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .valueOutOfRange
    );

    assert(serialized.error.index == 6);
}


/// Unsynchronisation is structurally serializable at the header layer.
unittest
{
    /*
     * Whether the corresponding body representation is writable is a
     * higher-level policy decision. The fixed header serializer itself
     * only validates ID3v2.3 header syntax.
     */
    const header =
        testHeader(
            10,
            0x80
        );

    auto serialized =
        serializeId3v23Header(
            header
        );

    assert(serialized.hasValue);
    assert(serialized.value[5] == 0x80);
}
