/++
Integrity validation for the optional ID3v2.3 extended-header CRC-32.

CRC validation is deliberately separate from structural parsing.

A CRC mismatch does not make the tag structurally malformed: the fixed
header, extended header, frame boundaries, frame-format additions and
padding may all remain valid while the stored checksum no longer
describes the frame sequence.

Validation operates over an already validated `Id3v23TagStructure`.

The CRC domain is the complete logical/native frame sequence only:

- fixed tag header excluded;
- extended header excluded;
- padding excluded;
- whole-tag unsynchronisation stuffing excluded.

No allocation is required.
+/
module audiotag.id3v2.v23.crc_validation;

import std.digest.crc :
    CRC32;

import audiotag.id3v2.v23.structure :
    Id3v23TagStructure;


/++
Integrity state of the optional ID3v2.3 CRC field.
+/
enum Id3v23CrcValidationStatus : ubyte
{
    /// No CRC field exists in the source tag.
    absent,

    /// Stored and calculated CRC values are identical.
    valid,

    /// A CRC field exists but does not match the logical frame sequence.
    mismatch
}


/++
Result of validating the optional ID3v2.3 extended-header CRC.

`storedCrc32` and `computedCrc32` are meaningful when `status` is
`valid` or `mismatch`.
+/
struct Id3v23CrcValidationResult
{
    Id3v23CrcValidationStatus status;

    /// CRC value stored in the source extended header.
    uint storedCrc32;

    /// CRC calculated from the logical/native frame sequence.
    uint computedCrc32;


    /// Whether the source tag carries a CRC field.
    @property
    bool hasCrc() const
        @safe pure nothrow @nogc
    {
        return
            status !=
            Id3v23CrcValidationStatus.absent;
    }


    /// Whether a present CRC was successfully verified.
    @property
    bool verified() const
        @safe pure nothrow @nogc
    {
        return
            status ==
            Id3v23CrcValidationStatus.valid;
    }
}


/++
Converts the Phobos CRC32 digest byte representation into the ordinary
numeric `uint` representation used by the ID3v2.3 extended-header model.
+/
private uint
crc32DigestValue(
    const ubyte[4] digest
)
    @safe pure nothrow @nogc
{
    return
        (cast(uint) digest[3] << 24) |
        (cast(uint) digest[2] << 16) |
        (cast(uint) digest[1] << 8) |
        cast(uint) digest[0];
}


/++
Validates the optional CRC-32 of one structurally valid ID3v2.3 tag.

The function always returns a validation result. Structural failures
belong to `parseId3v23TagStructure()` and therefore cannot arise here.

For whole-tag-unsynchronised input, `frameCursor()` automatically
removes physical stuffing while the checksum is calculated.

Params:
    tag = Already structurally validated ID3v2.3 tag.

Returns:
    `absent`, `valid`, or `mismatch` together with stored/calculated
    numeric CRC values.
+/
Id3v23CrcValidationResult
validateId3v23TagCrc(
    const(Id3v23TagStructure) tag
)
    @safe pure nothrow @nogc
{
    if (
        !tag.body.hasExtendedHeader ||
        !tag.body.extendedHeader.hasCrc
    )
    {
        return
            Id3v23CrcValidationResult(
                Id3v23CrcValidationStatus.absent,
                0,
                0
            );
    }

    CRC32 crc;
    crc.start();

    auto cursor =
        tag.frameCursor();

    while (!cursor.empty)
    {
        auto decoded =
            cursor.takeByte();

        /*
         * `tag` has already passed strict structural validation over this
         * exact logical frame region. Failure here would therefore be an
         * internal invariant violation rather than malformed new input.
         */
        assert(decoded.hasValue);

        crc.put(
            decoded.value.value
        );
    }

    const computed =
        crc32DigestValue(
            crc.finish()
        );

    const stored =
        tag.body.extendedHeader
            .crc32;

    return
        Id3v23CrcValidationResult(
            computed == stored
                ? Id3v23CrcValidationStatus.valid
                : Id3v23CrcValidationStatus.mismatch,
            stored,
            computed
        );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.structure :
        parseId3v23TagStructure;


    private Id3v23TagStructure
    parseTestTag(
        const(ubyte)[] bytes
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto parsed =
            cursor.parseId3v23TagStructure();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }
}


/// Tags without an extended header have no CRC to verify.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            // One eleven-byte frame.
            0x00, 0x00, 0x00, 0x0B,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const tag =
        parseTestTag(bytes);

    const validation =
        validateId3v23TagCrc(tag);

    assert(
        validation.status ==
        Id3v23CrcValidationStatus.absent
    );

    assert(!validation.hasCrc);
    assert(!validation.verified);
}


/// A non-CRC extended header likewise reports no CRC.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            // 10 extended-header bytes + 11 frame bytes.
            0x00, 0x00, 0x00, 0x15,

            // Extended-header size = 6.
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            // Padding size = 0.
            0x00, 0x00, 0x00, 0x00,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const tag =
        parseTestTag(bytes);

    const validation =
        validateId3v23TagCrc(tag);

    assert(
        validation.status ==
        Id3v23CrcValidationStatus.absent
    );
}


/// A matching CRC verifies successfully.
unittest
{
    /*
     * CRC-32 of the eleven logical frame bytes below:
     *
     *     8AA4B544
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            // 14 extended-header bytes + 11 frame bytes.
            0x00, 0x00, 0x00, 0x19,

            0x00, 0x00, 0x00, 0x0A,
            0x80, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x8A, 0xA4, 0xB5, 0x44,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const tag =
        parseTestTag(bytes);

    const validation =
        validateId3v23TagCrc(tag);

    assert(
        validation.status ==
        Id3v23CrcValidationStatus.valid
    );

    assert(validation.hasCrc);
    assert(validation.verified);

    assert(
        validation.storedCrc32 ==
        0x8AA4_B544
    );

    assert(
        validation.computedCrc32 ==
        0x8AA4_B544
    );
}


/// A checksum mismatch remains a validation outcome, not a parse failure.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            0x00, 0x00, 0x00, 0x19,

            0x00, 0x00, 0x00, 0x0A,
            0x80, 0x00,
            0x00, 0x00, 0x00, 0x00,

            // Deliberately stale CRC.
            0x12, 0x34, 0x56, 0x78,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    /*
     * Structural parsing succeeds before integrity validation begins.
     */
    const tag =
        parseTestTag(bytes);

    const validation =
        validateId3v23TagCrc(tag);

    assert(
        validation.status ==
        Id3v23CrcValidationStatus.mismatch
    );

    assert(validation.hasCrc);
    assert(!validation.verified);

    assert(
        validation.storedCrc32 ==
        0x1234_5678
    );

    assert(
        validation.computedCrc32 ==
        0x8AA4_B544
    );
}


/// Whole-tag stuffing is excluded from CRC validation.
unittest
{
    /*
     * Logical frame:
     *
     *     X001 + size 2 + flags 0 + FF E1
     *
     * CRC-32 of those twelve logical bytes:
     *
     *     06988BD4
     *
     * Physical source representation contains one inserted zero after FF.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            // Unsynchronisation + extended header.
            0xC0,

            // 14 logical extended bytes + 13 physical frame bytes.
            0x00, 0x00, 0x00, 0x1B,

            0x00, 0x00, 0x00, 0x0A,
            0x80, 0x00,
            0x00, 0x00, 0x00, 0x00,

            // CRC over logical/native frame bytes.
            0x06, 0x98, 0x8B, 0xD4,

            'X', '0', '0', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            // Physical whole-tag-unsynchronised FF E1.
            0xFF, 0x00, 0xE1
        ];

    const tag =
        parseTestTag(bytes);

    assert(
        tag.envelope.header
            .unsynchronisation
    );

    const validation =
        validateId3v23TagCrc(tag);

    assert(
        validation.status ==
        Id3v23CrcValidationStatus.valid
    );

    assert(
        validation.computedCrc32 ==
        0x0698_8BD4
    );
}
