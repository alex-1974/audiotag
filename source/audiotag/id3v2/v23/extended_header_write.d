/++
Physical serialization of an ID3v2.3 extended header.

ID3v2.3 defines two structural forms:

Without CRC:

    4 bytes  extended-header size = 6
    2 bytes  flags = 0
    4 bytes  padding size

With CRC:

    4 bytes  extended-header size = 10
    2 bytes  flags = 0x8000
    4 bytes  padding size
    4 bytes  CRC-32

The encoded size excludes its own four bytes.

This writer regenerates the structural form of an already parsed
extended header while allowing the declared padding size to change.

The original `sourceOffset` and `raw` provenance are not serialized.

No ID3v2.3 whole-tag unsynchronisation is applied here. The returned
bytes are the ordinary logical/native extended-header representation.
If the resulting tag uses whole-tag unsynchronisation, that later
transformation must operate across the complete tag body.
+/
module audiotag.id3v2.v23.extended_header_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.extended_header :
    Id3v23ExtendedHeader;


/++
Serializes the structural form of an existing ID3v2.3 extended header
with a supplied resulting padding size.

For the CRC form the existing CRC value is copied unchanged. The caller
must therefore ensure that preserving that CRC is semantically valid.
The tag-body policy blocks changed frame sequences with an existing CRC
until CRC generation is implemented.

Params:
    source = Parsed source extended header whose structural form and
        optional CRC value are retained.
    paddingSize = Number of trailing padding bytes in the resulting tag.

Returns:
    Ten-byte non-CRC or fourteen-byte CRC extended-header bytes, or a
    structured failure if `source` does not describe one of the two
    valid ID3v2.3 structural forms.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v23ExtendedHeader(
    const(Id3v23ExtendedHeader) source,
    uint paddingSize
)
    @safe
{
    const hasCrc =
        source.hasCrc;

    if (hasCrc)
    {
        if (
            source.size != 10 ||
            source.flags != 0x8000
        )
        {
            return
                SerializationResult!(ubyte[])
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .inconsistentStructure
                        )
                    );
        }
    }
    else
    {
        if (
            source.size != 6 ||
            source.flags != 0
        )
        {
            return
                SerializationResult!(ubyte[])
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .inconsistentStructure
                        )
                    );
        }
    }

    const outputLength =
        hasCrc
            ? 14
            : 10;

    auto output =
        new ubyte[outputLength];

    /*
     * Extended-header size: ordinary unsigned big-endian integer.
     */
    output[0] =
        cast(ubyte)
            (source.size >> 24);

    output[1] =
        cast(ubyte)
            (source.size >> 16);

    output[2] =
        cast(ubyte)
            (source.size >> 8);

    output[3] =
        cast(ubyte)
            source.size;

    /*
     * Extended flags.
     */
    output[4] =
        cast(ubyte)
            (source.flags >> 8);

    output[5] =
        cast(ubyte)
            source.flags;

    /*
     * Resulting padding size.
     */
    output[6] =
        cast(ubyte)
            (paddingSize >> 24);

    output[7] =
        cast(ubyte)
            (paddingSize >> 16);

    output[8] =
        cast(ubyte)
            (paddingSize >> 8);

    output[9] =
        cast(ubyte)
            paddingSize;

    if (hasCrc)
    {
        /*
         * Preserve the source CRC value. Recalculation belongs to a
         * later CRC writer/policy extension.
         */
        output[10] =
            cast(ubyte)
                (source.crc32 >> 24);

        output[11] =
            cast(ubyte)
                (source.crc32 >> 16);

        output[12] =
            cast(ubyte)
                (source.crc32 >> 8);

        output[13] =
            cast(ubyte)
                source.crc32;
    }

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

    import audiotag.id3v2.v23.extended_header :
        parseId3v23ExtendedHeader;


    private Id3v23ExtendedHeader
    testExtendedHeader(
        uint size,
        ushort flags,
        uint paddingSize,
        uint crc32 = 0
    )
        @safe pure nothrow @nogc
    {
        return
            Id3v23ExtendedHeader(
                1234,
                size,
                flags,
                paddingSize,
                crc32,
                ByteSpan.init
            );
    }
}


/// The six-byte structural form serializes to ten complete bytes.
unittest
{
    const source =
        testExtendedHeader(
            6,
            0,
            3
        );

    auto serialized =
        serializeRegeneratedId3v23ExtendedHeader(
            source,
            7
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,
            0x00, 0x00, 0x00, 0x07
        ]
    );
}


/// The CRC form retains the existing checksum while changing padding.
unittest
{
    const source =
        testExtendedHeader(
            10,
            0x8000,
            2,
            0x1234_5678
        );

    auto serialized =
        serializeRegeneratedId3v23ExtendedHeader(
            source,
            9
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            0x00, 0x00, 0x00, 0x0A,
            0x80, 0x00,
            0x00, 0x00, 0x00, 0x09,
            0x12, 0x34, 0x56, 0x78
        ]
    );
}


/// Regenerated ordinary bytes roundtrip through the strict parser.
unittest
{
    const source =
        testExtendedHeader(
            6,
            0,
            100
        );

    auto serialized =
        serializeRegeneratedId3v23ExtendedHeader(
            source,
            42
        );

    assert(serialized.hasValue);

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                serialized.value[],
                5000
            ),
            false
        );

    auto parsed =
        cursor.parseId3v23ExtendedHeader();

    assert(parsed.hasValue);
    assert(cursor.empty);

    assert(parsed.value.sourceOffset == 5000);
    assert(parsed.value.size == 6);
    assert(parsed.value.flags == 0);
    assert(!parsed.value.hasCrc);
    assert(parsed.value.paddingSize == 42);
    assert(parsed.value.crc32 == 0);
    assert(parsed.value.raw.length == 10);
}


/// CRC regeneration likewise remains structurally parseable.
unittest
{
    const source =
        testExtendedHeader(
            10,
            0x8000,
            1,
            0xDEAD_BEEF
        );

    auto serialized =
        serializeRegeneratedId3v23ExtendedHeader(
            source,
            4
        );

    assert(serialized.hasValue);

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                serialized.value[]
            ),
            false
        );

    auto parsed =
        cursor.parseId3v23ExtendedHeader();

    assert(parsed.hasValue);
    assert(cursor.empty);

    assert(parsed.value.size == 10);
    assert(parsed.value.flags == 0x8000);
    assert(parsed.value.hasCrc);
    assert(parsed.value.paddingSize == 4);
    assert(parsed.value.crc32 == 0xDEAD_BEEF);
    assert(parsed.value.raw.length == 14);
}


/// Whole-tag unsynchronisation is deliberately not applied here.
unittest
{
    /*
     * FF E1 in the CRC would require FF 00 E1 in an unsynchronised
     * physical tag body.
     *
     * This writer intentionally emits the ordinary logical/native form.
     */
    const source =
        testExtendedHeader(
            10,
            0x8000,
            0,
            0x12FF_E134
        );

    auto serialized =
        serializeRegeneratedId3v23ExtendedHeader(
            source,
            0
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            0x00, 0x00, 0x00, 0x0A,
            0x80, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x12, 0xFF, 0xE1, 0x34
        ]
    );
}


/// A CRC flag cannot be combined with the six-byte form.
unittest
{
    const source =
        testExtendedHeader(
            6,
            0x8000,
            0,
            0x1234_5678
        );

    auto serialized =
        serializeRegeneratedId3v23ExtendedHeader(
            source,
            0
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );
}


/// The ten-byte form requires the CRC flag.
unittest
{
    const source =
        testExtendedHeader(
            10,
            0,
            0
        );

    auto serialized =
        serializeRegeneratedId3v23ExtendedHeader(
            source,
            0
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );
}


/// Undefined extended-header flag bits are rejected.
unittest
{
    const source =
        testExtendedHeader(
            10,
            0xC000,
            0,
            0x1234_5678
        );

    auto serialized =
        serializeRegeneratedId3v23ExtendedHeader(
            source,
            0
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );
}
