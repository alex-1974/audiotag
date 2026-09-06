/++
ID3v2.4 fixed tag-header and footer serialization.

This module serializes only the fixed ten-byte outer structures:

- the ID3v2.4 tag header beginning with `ID3`;
- the optional footer beginning with `3DI`.

The encoded `tagSize` describes only the tag body following the header.
It excludes both the ten-byte header itself and an optional ten-byte
footer.

Body construction, extended-header handling, CRC generation, padding,
tag-level unsynchronisation and container writing remain separate
writer layers.

`sourceOffset` is parser provenance and is intentionally not encoded.
+/
module audiotag.id3v2.v24.tag_header_write;

import audiotag.core.numeric :
    encodeSynchsafe32;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v24.header :
    Id3v24Header;


private enum uint maximumId3v24TagSize =
    0x0FFF_FFFF;


/++
Validates and serializes one fixed ID3v2.4 tag header.

The major version is always emitted as `4`. The retained revision byte
must not be `0xFF`.

Defined ID3v2.4 header flags occupy the upper nibble:

- `0x80` tag-level unsynchronisation;
- `0x40` extended header;
- `0x20` experimental indicator;
- `0x10` footer present.

The low nibble is reserved and rejected.

Params:
    header = Parsed or constructed ID3v2.4 header values.

Returns:
    Exact ten encoded header bytes or a structured serialization failure.
+/
SerializationResult!(ubyte[10])
serializeId3v24Header(
    const(Id3v24Header) header
)
    @safe pure nothrow @nogc
{
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

    if (
        (
            header.flags &
            0x0F
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
                        0xF0
                    )
                );
    }

    if (
        header.tagSize >
        maximumId3v24TagSize
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
                        maximumId3v24TagSize
                    )
                );
    }

    const encodedSize =
        encodeSynchsafe32(
            header.tagSize
        );

    /*
     * The explicit 28-bit domain check above guarantees that the
     * generic synchsafe encoder cannot fail.
     */
    assert(encodedSize.hasValue);

    ubyte[10] result;

    result[0] = 'I';
    result[1] = 'D';
    result[2] = '3';

    result[3] = 0x04;
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


/++
Serializes the optional ID3v2.4 footer corresponding to one tag header.

A footer is valid only when the header's footer-present flag is set.
Its version, revision, flags and tag size are identical to the header;
only the identifier is reversed from `ID3` to `3DI`.

Params:
    header = Header whose footer is to be produced.

Returns:
    Exact ten footer bytes or a structured serialization failure.
+/
SerializationResult!(ubyte[10])
serializeId3v24Footer(
    const(Id3v24Header) header
)
    @safe pure nothrow @nogc
{
    if (!header.hasFooter)
    {
        return
            SerializationResult!(ubyte[10])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        5,
                        header.flags,
                        0x10
                    )
                );
    }

    auto encodedHeader =
        serializeId3v24Header(
            header
        );

    if (encodedHeader.hasError)
    {
        return
            SerializationResult!(ubyte[10])
                .failure(
                    encodedHeader.error
                );
    }

    ubyte[10] result =
        encodedHeader.value;

    result[0] = '3';
    result[1] = 'D';
    result[2] = 'I';

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

    import audiotag.id3v2.v24.header :
        parseId3v24Header;

    import audiotag.id3v2.v24.tag :
        parseId3v24TagEnvelope;


    private Id3v24Header testHeader(
        uint tagSize = 0,
        ubyte flags = 0,
        ubyte revision = 0,
        size_t sourceOffset = 0
    )
        @safe pure nothrow @nogc
    {
        return
            Id3v24Header(
                sourceOffset,
                revision,
                flags,
                tagSize
            );
    }
}


/// A minimal ID3v2.4.0 header serializes to exactly ten bytes.
unittest
{
    const header =
        testHeader();

    auto serialized =
        serializeId3v24Header(
            header
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ]
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[],
                100
            )
        );

    auto parsed =
        cursor.parseId3v24Header();

    assert(parsed.hasValue);
    assert(cursor.empty);

    assert(parsed.value.sourceOffset == 100);
    assert(parsed.value.revision == 0);
    assert(parsed.value.flags == 0);
    assert(parsed.value.tagSize == 0);
}


/// All defined flag bits and a real-world-sized value roundtrip.
unittest
{
    const header =
        testHeader(
            33140,
            0xF0,
            2
        );

    auto serialized =
        serializeId3v24Header(
            header
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'I', 'D', '3',
            0x04, 0x02,
            0xF0,
            0x00, 0x02, 0x02, 0x74
        ]
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[]
            )
        );

    auto parsed =
        cursor.parseId3v24Header();

    assert(parsed.hasValue);

    assert(parsed.value.revision == 2);
    assert(parsed.value.flags == 0xF0);
    assert(parsed.value.tagSize == 33140);

    assert(parsed.value.unsynchronisation);
    assert(parsed.value.hasExtendedHeader);
    assert(parsed.value.experimentalIndicator);
    assert(parsed.value.hasFooter);
}


/// Parser provenance does not enter serialized header bytes.
unittest
{
    const first =
        testHeader(
            123,
            0x20,
            0,
            100
        );

    const second =
        testHeader(
            123,
            0x20,
            0,
            9000
        );

    auto firstBytes =
        serializeId3v24Header(
            first
        );

    auto secondBytes =
        serializeId3v24Header(
            second
        );

    assert(firstBytes.hasValue);
    assert(secondBytes.hasValue);

    assert(
        firstBytes.value ==
        secondBytes.value
    );
}


/// Revision FF remains invalid for writer output.
unittest
{
    const header =
        testHeader(
            0,
            0,
            0xFF
        );

    auto serialized =
        serializeId3v24Header(
            header
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(serialized.error.index == 4);
}


/// Reserved low header-flag bits are rejected.
unittest
{
    foreach (bit; 0 .. 4)
    {
        const header =
            testHeader(
                0,
                cast(ubyte)
                    (1 << bit)
            );

        auto serialized =
            serializeId3v24Header(
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


/// Tag sizes must fit the 28-bit synchsafe domain.
unittest
{
    const maximum =
        testHeader(
            0x0FFF_FFFF
        );

    auto maximumBytes =
        serializeId3v24Header(
            maximum
        );

    assert(maximumBytes.hasValue);

    const tooLarge =
        testHeader(
            0x1000_0000
        );

    auto rejected =
        serializeId3v24Header(
            tooLarge
        );

    assert(rejected.hasError);

    assert(
        rejected.error.code ==
        SerializationErrorCode
            .valueOutOfRange
    );

    assert(rejected.error.index == 6);
}


/// A footer is the header mirrored with the `3DI` identifier.
unittest
{
    const header =
        testHeader(
            2,
            0x10
        );

    auto footer =
        serializeId3v24Footer(
            header
        );

    assert(footer.hasValue);

    assert(
        footer.value ==
        [
            '3', 'D', 'I',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x02
        ]
    );
}


/// Header, body and generated footer form a valid outer tag envelope.
unittest
{
    const header =
        testHeader(
            2,
            0x10
        );

    auto encodedHeader =
        serializeId3v24Header(
            header
        );

    auto encodedFooter =
        serializeId3v24Footer(
            header
        );

    assert(encodedHeader.hasValue);
    assert(encodedFooter.hasValue);

    auto bytes =
        new ubyte[22];

    bytes[0 .. 10] =
        encodedHeader.value[];

    bytes[10] = 0x11;
    bytes[11] = 0x22;

    bytes[12 .. 22] =
        encodedFooter.value[];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto parsed =
        cursor.parseId3v24TagEnvelope();

    assert(parsed.hasValue);
    assert(cursor.empty);

    assert(parsed.value.header.tagSize == 2);
    assert(parsed.value.body.length == 2);
    assert(parsed.value.body.data == [0x11, 0x22]);

    assert(parsed.value.footer.length == 10);
    assert(parsed.value.endOffset == 522);
}


/// Footer output requires the corresponding header flag.
unittest
{
    const header =
        testHeader(
            10,
            0x00
        );

    auto footer =
        serializeId3v24Footer(
            header
        );

    assert(footer.hasError);

    assert(
        footer.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );

    assert(footer.error.index == 5);
}
