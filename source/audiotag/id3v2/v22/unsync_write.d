/++
ID3v2.2 whole-tag unsynchronisation encoding surface.

ID3v2.2.0 applies unsynchronisation to the complete tag body. The byte-stuffing
algorithm is shared with ID3v2.3 and lives in
`audiotag.id3v2.common.unsync_write`.

This module keeps the v2.2 writer surface revision-specific while delegating
only the byte-identical transformation.

The functions here do not decide compression policy, body padding, final tag
size, or header flags. Those remain responsibilities of later v2.2 writer
layers.

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
module audiotag.id3v2.v22.unsync_write;

import audiotag.core.serialization :
    SerializationResult;

import audiotag.id3v2.common.unsync_write :
    measureId3v2UnsynchronisedLength,
    requiresId3v2Unsynchronisation,
    serializeId3v2UnsynchronisedBytes;


/++
Returns whether a logical ID3v2.2 tag body contains a false MPEG
synchronisation and therefore requires whole-tag unsynchronisation.

Only `$FF` followed by `$E0 .. $FF` activates the scheme.

A logical `$FF $00` pair does not by itself activate unsynchronisation, but it
must be protected if unsynchronisation is active because of another false sync.

Params:
    logical = Complete logical ID3v2.2 tag body.

Returns:
    `true` when the v2.2 unsynchronisation flag is required by a false sync.

Complexity:
    O(n) time and O(1) additional space.
+/
bool
requiresId3v22Unsynchronisation(
    const(ubyte)[] logical
)
    @safe pure nothrow @nogc
{
    return
        requiresId3v2Unsynchronisation(
            logical
        );
}


/++
Measures the physical body length produced when ID3v2.2 whole-tag
unsynchronisation is actively applied.

The measurement includes stuffing for both false synchronisation patterns and
logical `$FF $00` pairs.

A trailing `$FF` is unchanged by this primitive.

Params:
    logical = Complete logical ID3v2.2 tag body.

Returns:
    Resulting physical length or a structured overflow failure.

Complexity:
    O(n) time and O(1) additional space.
+/
SerializationResult!size_t
measureId3v22UnsynchronisedLength(
    const(ubyte)[] logical
)
    @safe pure nothrow @nogc
{
    return
        measureId3v2UnsynchronisedLength(
            logical
        );
}


/++
Applies ID3v2.2 whole-tag unsynchronisation to one complete logical tag body.

The caller must already have decided to enable unsynchronisation. The complete
body is transformed as one byte region so false synchronisations crossing frame
or frame/padding boundaries are handled correctly.

This function does not set the header flag or compute the final tag size.

Params:
    logical = Complete logical ID3v2.2 tag body.

Returns:
    Newly allocated physical body bytes or a structured overflow failure.

Safety:
    The returned buffer owns its bytes and retains no view into `logical`.

Complexity:
    O(n) time and O(n) output space.
+/
SerializationResult!(ubyte[])
serializeId3v22UnsynchronisedBytes(
    const(ubyte)[] logical
)
    @safe
{
    return
        serializeId3v2UnsynchronisedBytes(
            logical
        );
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.data_cursor :
        Id3v22DataCursor;
}


/// Ordinary data neither activates nor changes under v2.2 unsynchronisation.
unittest
{
    const ubyte[] logical =
        [
            0x11,
            0x22,
            0x33
        ];

    assert(
        !requiresId3v22Unsynchronisation(
            logical
        )
    );

    const encoded =
        serializeId3v22UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);
    assert(encoded.value == logical);
}


/// A false MPEG sync activates v2.2 whole-tag unsynchronisation.
unittest
{
    const ubyte[] logical =
        [
            0x11,
            0xFF,
            0xE1,
            0x22
        ];

    assert(
        requiresId3v22Unsynchronisation(
            logical
        )
    );

    const measured =
        measureId3v22UnsynchronisedLength(
            logical
        );

    assert(measured.hasValue);
    assert(measured.value == 5);

    const encoded =
        serializeId3v22UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            0x11,
            0xFF, 0x00, 0xE1,
            0x22
        ]
    );
}


/// FF 00 alone does not activate the scheme but is protected when active.
unittest
{
    const ubyte[] logical =
        [
            0xFF,
            0x00
        ];

    assert(
        !requiresId3v22Unsynchronisation(
            logical
        )
    );

    const encoded =
        serializeId3v22UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            0xFF,
            0x00,
            0x00
        ]
    );
}


/// Encoding followed by the existing v2.2 logical cursor recovers exact bytes.
unittest
{
    const ubyte[] logical =
        [
            0x10,
            0xFF, 0xE1,
            0x20,
            0xFF, 0x00,
            0x30,
            0xFF
        ];

    const encoded =
        serializeId3v22UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                encoded.value[],
                5000
            ),
            true
        );

    foreach (
        expected;
        logical
    )
    {
        auto decoded =
            cursor.takeByte();

        assert(decoded.hasValue);
        assert(
            decoded.value.value ==
            expected
        );
    }

    assert(cursor.empty);
}


/// Whole-body encoding naturally crosses a frame/padding-like boundary.
unittest
{
    /*
     * Interpret the first FF as the final logical frame byte and the two zero
     * bytes as logical padding.
     */
    const ubyte[] logical =
        [
            0xFF,
            0x00,
            0x00
        ];

    const encoded =
        serializeId3v22UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            0xFF,
            0x00,
            0x00,
            0x00
        ]
    );

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                encoded.value[]
            ),
            true
        );

    foreach (
        expected;
        logical
    )
    {
        auto decoded =
            cursor.takeByte();

        assert(decoded.hasValue);
        assert(
            decoded.value.value ==
            expected
        );
    }

    assert(cursor.empty);
}


/// A trailing FF is not changed by the v2.2 stuffing primitive.
unittest
{
    const ubyte[] logical =
        [
            0x11,
            0xFF
        ];

    assert(
        !requiresId3v22Unsynchronisation(
            logical
        )
    );

    const encoded =
        serializeId3v22UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);
    assert(encoded.value == logical);
}
