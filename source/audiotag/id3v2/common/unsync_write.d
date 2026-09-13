/++
Shared ID3v2.2/ID3v2.3 unsynchronisation encoding primitives.

ID3v2.2.0 and ID3v2.3.0 use the same byte-stuffing transformation:

- a false MPEG synchronisation prefix `$FF $E0 .. $FF` is protected by
  inserting `$00` after `$FF`;
- once unsynchronisation is active, a logical `$FF $00` pair is encoded as
  `$FF $00 $00` so decoding does not lose the original zero byte.

This module implements only that revision-independent byte transformation.

It deliberately does not decide:

- where a revision applies unsynchronisation;
- whether the enclosing tag/frame flag should be set;
- compression ordering;
- padding or terminal-byte policy.

Those decisions remain revision-specific.

Standards:
    ID3v2.2.0, https://id3.org/id3v2-00
    ID3v2.3.0, https://id3.org/id3v2.3.0

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-13
+/
module audiotag.id3v2.common.unsync_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;


/++
Returns whether `logical` contains a false MPEG synchronisation that requires
activation of the ID3v2.2/ID3v2.3 unsynchronisation scheme.

Only `$FF` followed by `$E0 .. $FF` activates the scheme.

A logical `$FF $00` pair does not by itself require activation. It must,
however, be protected when the scheme is active because the corresponding
decoder removes one zero byte following `$FF`.

A trailing `$FF` likewise does not by itself activate this primitive.

Params:
    logical = Complete logical byte region to inspect.

Returns:
    `true` when at least one false synchronisation is present.

Complexity:
    O(n) time and O(1) additional space.
+/
bool
requiresId3v2Unsynchronisation(
    const(ubyte)[] logical
)
    @safe pure nothrow @nogc
{
    if (logical.length < 2)
        return false;

    foreach (
        index;
        0 ..
        logical.length - 1
    )
    {
        if (
            logical[index] == 0xFF &&
            logical[index + 1] >= 0xE0
        )
        {
            return true;
        }
    }

    return false;
}


/++
Measures the physical byte length produced when the ID3v2.2/ID3v2.3
unsynchronisation transformation is actively applied to `logical`.

Stuffing is counted after `$FF` whenever the following logical byte is either:

- `$00`; or
- `$E0 .. $FF`.

A trailing `$FF` receives no stuffing in this primitive. Any revision-specific
terminal-padding requirement belongs to the enclosing writer.

Params:
    logical = Logical bytes to measure.

Returns:
    Resulting physical length or `valueOutOfRange` if the length would overflow
    `size_t`.

Complexity:
    O(n) time and O(1) additional space.
+/
SerializationResult!size_t
measureId3v2UnsynchronisedLength(
    const(ubyte)[] logical
)
    @safe pure nothrow @nogc
{
    size_t physicalLength =
        logical.length;

    if (logical.length < 2)
    {
        return
            SerializationResult!size_t
                .success(
                    physicalLength
                );
    }

    foreach (
        index;
        0 ..
        logical.length - 1
    )
    {
        const current =
            logical[index];

        const next =
            logical[index + 1];

        const stuffingRequired =
            current == 0xFF &&
            (
                next == 0x00 ||
                next >= 0xE0
            );

        if (!stuffingRequired)
            continue;

        if (physicalLength == size_t.max)
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .valueOutOfRange,
                            index,
                            cast(ulong)
                                logical.length,
                            cast(ulong)
                                size_t.max
                        )
                    );
        }

        ++physicalLength;
    }

    return
        SerializationResult!size_t
            .success(
                physicalLength
            );
}


/++
Applies the shared ID3v2.2/ID3v2.3 unsynchronisation byte transformation.

This function assumes the caller has already decided that unsynchronisation is
active. It therefore protects both false synchronisation sequences and logical
`$FF $00` pairs.

The supplied byte sequence is treated as one continuous logical region, so
stuffing may naturally occur across structural boundaries selected by the
caller.

A trailing `$FF` is not modified here. Revision-specific terminal-padding
policy belongs to the enclosing writer.

Params:
    logical = Complete logical byte region to transform.

Returns:
    Newly allocated physical bytes or a structured overflow failure.

Safety:
    The returned buffer owns its bytes and retains no view into `logical`.

Complexity:
    O(n) time and O(n) output space.
+/
SerializationResult!(ubyte[])
serializeId3v2UnsynchronisedBytes(
    const(ubyte)[] logical
)
    @safe
{
    const measured =
        measureId3v2UnsynchronisedLength(
            logical
        );

    if (measured.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    measured.error
                );
    }

    auto output =
        new ubyte[
            measured.value
        ];

    size_t position;

    foreach (
        index,
        value;
        logical
    )
    {
        output[position++] =
            value;

        if (
            value != 0xFF ||
            index + 1 >=
                logical.length
        )
        {
            continue;
        }

        const next =
            logical[index + 1];

        if (
            next == 0x00 ||
            next >= 0xE0
        )
        {
            output[position++] =
                0x00;
        }
    }

    assert(
        position ==
        output.length
    );

    return
        SerializationResult!(ubyte[])
            .success(
                output
            );
}


/// Ordinary data neither requires nor changes under the transformation.
unittest
{
    const ubyte[] logical =
        [
            0x11,
            0x22,
            0x33
        ];

    assert(
        !requiresId3v2Unsynchronisation(
            logical
        )
    );

    const measured =
        measureId3v2UnsynchronisedLength(
            logical
        );

    assert(measured.hasValue);
    assert(measured.value == 3);

    const encoded =
        serializeId3v2UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);
    assert(encoded.value == logical);
}


/// Every false-sync second byte in E0..FF requires one stuffing zero.
unittest
{
    foreach (
        next;
        0xE0 ..
        0x100
    )
    {
        const ubyte[] logical =
            [
                0xFF,
                cast(ubyte) next
            ];

        assert(
            requiresId3v2Unsynchronisation(
                logical
            )
        );

        const encoded =
            serializeId3v2UnsynchronisedBytes(
                logical
            );

        assert(encoded.hasValue);

        assert(
            encoded.value ==
            [
                0xFF,
                0x00,
                cast(ubyte) next
            ]
        );
    }
}


/// Logical FF 00 is protected whenever the transformation is active.
unittest
{
    const ubyte[] logical =
        [
            0xFF,
            0x00
        ];

    assert(
        !requiresId3v2Unsynchronisation(
            logical
        )
    );

    const encoded =
        serializeId3v2UnsynchronisedBytes(
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


/// Multiple stuffing sites are measured and emitted independently.
unittest
{
    const ubyte[] logical =
        [
            0xFF, 0x00,
            0x11,
            0xFF, 0xE0,
            0x22,
            0xFF, 0xFF
        ];

    const measured =
        measureId3v2UnsynchronisedLength(
            logical
        );

    assert(measured.hasValue);
    assert(measured.value == 11);

    const encoded =
        serializeId3v2UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            0xFF, 0x00, 0x00,
            0x11,
            0xFF, 0x00, 0xE0,
            0x22,
            0xFF, 0x00, 0xFF
        ]
    );
}


/// A trailing FF is deliberately left unchanged by the shared primitive.
unittest
{
    const ubyte[] logical =
        [
            0x11,
            0xFF
        ];

    assert(
        !requiresId3v2Unsynchronisation(
            logical
        )
    );

    const encoded =
        serializeId3v2UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);
    assert(encoded.value == logical);
}
