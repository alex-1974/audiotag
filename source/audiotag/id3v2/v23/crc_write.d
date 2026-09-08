/++
CRC-32 calculation for logical/native ID3v2.3 frame sequences.

The ID3v2.3 extended header stores the CRC as one ordinary unsigned
32-bit value.

Phobos `crc32Of()` exposes its four digest bytes in least-significant
byte first order. This module converts that representation into the
numeric `uint` form used by the ID3v2.3 parser and extended-header model.

The input is the complete logical/native frame sequence only. It must
not contain:

- the fixed ID3 header;
- the extended header;
- padding;
- whole-tag unsynchronisation stuffing.
+/
module audiotag.id3v2.v23.crc_write;

import std.digest.crc :
    crc32Of;


/++
Calculates the ID3v2.3 CRC-32 over one complete logical/native frame
sequence.

Params:
    logicalFrameSequence = Concatenated logical/native frame bytes.

Returns:
    CRC-32 as the ordinary numeric `uint` value stored by the v2.3
    extended-header model.
+/
uint
computeId3v23FrameCrc32(
    const(ubyte)[] logicalFrameSequence
)
    @safe
{
    const digest =
        crc32Of(
            logicalFrameSequence
        );

    return
        (cast(uint) digest[3] << 24) |
        (cast(uint) digest[2] << 16) |
        (cast(uint) digest[1] << 8) |
        cast(uint) digest[0];
}


/// Standard CRC-32 check value for "123456789".
unittest
{
    const ubyte[] bytes =
        cast(const(ubyte)[])
            "123456789";

    assert(
        computeId3v23FrameCrc32(bytes) ==
        0xCBF4_3926
    );
}


/// A complete logical ID3v2.3 frame is hashed byte-for-byte.
unittest
{
    const ubyte[] frame =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,
            0x00,
            'O', 'l', 'd'
        ];

    /*
     * Independently established with Phobos:
     *
     *     digest bytes = A8 5A 61 96
     *     CRC-32       = 96615AA8
     */
    assert(
        computeId3v23FrameCrc32(frame) ==
        0x9661_5AA8
    );
}
