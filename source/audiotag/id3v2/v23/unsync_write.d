/++
ID3v2.3 whole-tag unsynchronisation encoding primitives.

ID3v2.3 unsynchronisation is a transformation of the complete logical
tag body. It must therefore be applied only after extended-header,
frame-sequence and padding bytes have been assembled logically.

When the scheme is active, a zero byte is inserted after `$FF` when the
following logical byte is either:

- `$E0 .. $FF`, which could form a false MPEG synchronisation; or
- `$00`, which must be protected because the decoder removes `$FF $00`
  stuffing.

Thus:

    FF E1       -> FF 00 E1
    FF 00       -> FF 00 00

A trailing logical `$FF` is deliberately left unchanged by this
primitive. ID3v2.3 instead requires the enclosing tag writer to ensure
that at least one padding byte follows when unsynchronisation is needed
elsewhere in a tag whose logical body would otherwise end in `$FF`.

This module does not decide whether the tag header's unsynchronisation
flag should be set. `requiresId3v23Unsynchronisation` detects the false
synchronisation condition that requires activation of the scheme;
`serializeId3v23UnsynchronisedBytes` performs the transformation when
the caller has decided that the scheme is active.
+/
module audiotag.id3v2.v23.unsync_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;


/++
Returns whether a logical ID3v2.3 tag body contains a false MPEG
synchronisation pattern and therefore requires whole-tag
unsynchronisation.

Only `$FF` followed by `$E0 .. $FF` requires activation of the scheme.

A logical `$FF $00` pair by itself does not require enabling
unsynchronisation. It only needs protection if the scheme is already
active for some other false synchronisation in the tag.

A trailing `$FF` likewise does not itself activate the scheme.
+/
bool
requiresId3v23Unsynchronisation(
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
Measures the physical byte length produced when ID3v2.3
unsynchronisation is actively applied to `logical`.

The function counts stuffing required for both false synchronisation
patterns and logical `$FF $00` pairs.

A trailing `$FF` does not receive stuffing here.

Returns:
    Resulting physical length or a structured overflow failure.
+/
SerializationResult!size_t
measureId3v23UnsynchronisedLength(
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
Applies ID3v2.3 whole-tag unsynchronisation to logical bytes.

This function assumes that the caller has already decided to enable the
scheme. It therefore protects both false synchronisation sequences and
logical `$FF $00` pairs.

The transformation is performed across the supplied byte sequence
without regard to internal structure boundaries. Passing a complete
logical tag body therefore correctly handles sequences spanning:

- extended-header fields;
- frame headers;
- frame payloads;
- adjacent frames;
- the frame/padding boundary.

A trailing `$FF` is not modified. Terminal-padding policy belongs to the
enclosing tag-body planner.

Returns:
    Newly allocated physical bytes or a structured overflow failure.
+/
SerializationResult!(ubyte[])
serializeId3v23UnsynchronisedBytes(
    const(ubyte)[] logical
)
    @safe
{
    auto measured =
        measureId3v23UnsynchronisedLength(
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
            index + 1 >= logical.length
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
            .success(output);
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.data_cursor :
        Id3v23DataCursor;
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
        !requiresId3v23Unsynchronisation(
            logical
        )
    );

    auto measured =
        measureId3v23UnsynchronisedLength(
            logical
        );

    assert(measured.hasValue);
    assert(measured.value == 3);

    auto encoded =
        serializeId3v23UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        logical
    );
}


/// A possible MPEG sync requires one stuffing zero.
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
        requiresId3v23Unsynchronisation(
            logical
        )
    );

    auto measured =
        measureId3v23UnsynchronisedLength(
            logical
        );

    assert(measured.hasValue);
    assert(measured.value == 5);

    auto encoded =
        serializeId3v23UnsynchronisedBytes(
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


/// Every second byte in the MPEG sync range E0..FF requires stuffing.
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
            requiresId3v23Unsynchronisation(
                logical
            )
        );

        auto encoded =
            serializeId3v23UnsynchronisedBytes(
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


/// Bytes below E0 do not constitute false synchronisation.
unittest
{
    foreach (
        next;
        [
            0x01,
            0x7F,
            0xDF
        ]
    )
    {
        const ubyte[] logical =
            [
                0xFF,
                cast(ubyte) next
            ];

        assert(
            !requiresId3v23Unsynchronisation(
                logical
            )
        );

        auto encoded =
            serializeId3v23UnsynchronisedBytes(
                logical
            );

        assert(encoded.hasValue);

        assert(
            encoded.value ==
            logical
        );
    }
}


/// Logical FF 00 is protected whenever the scheme is active.
unittest
{
    const ubyte[] logical =
        [
            0xFF,
            0x00
        ];

    /*
     * FF 00 alone is not a false MPEG synchronisation, so it does not
     * itself require activating the scheme.
     */
    assert(
        !requiresId3v23Unsynchronisation(
            logical
        )
    );

    /*
     * If the enclosing tag has activated unsynchronisation because of
     * another false sync, however, this pair must be protected.
     */
    auto encoded =
        serializeId3v23UnsynchronisedBytes(
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


/// Multiple stuffing sites are measured and serialized independently.
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

    assert(
        requiresId3v23Unsynchronisation(
            logical
        )
    );

    auto measured =
        measureId3v23UnsynchronisedLength(
            logical
        );

    assert(measured.hasValue);
    assert(measured.value == 11);

    auto encoded =
        serializeId3v23UnsynchronisedBytes(
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


/// A trailing FF is not converted into stuffing by this primitive.
unittest
{
    const ubyte[] logical =
        [
            0x11,
            0xFF
        ];

    assert(
        !requiresId3v23Unsynchronisation(
            logical
        )
    );

    auto encoded =
        serializeId3v23UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        logical
    );
}


/// Whole-body transformation naturally crosses a frame/padding boundary.
unittest
{
    /*
     * Interpret FF as the final logical frame byte and the two zeros as
     * logical padding.
     *
     * The first zero after FF must be protected by stuffing:
     *
     *   logical:   FF 00 00
     *   physical:  FF 00 00 00
     *
     * The inserted first zero is stuffing; the following two remain
     * logical padding bytes.
     */
    const ubyte[] logical =
        [
            0xFF,
            0x00,
            0x00
        ];

    auto encoded =
        serializeId3v23UnsynchronisedBytes(
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
        Id3v23DataCursor(
            ByteSpan(
                encoded.value[]
            ),
            true
        );

    foreach (expected; logical)
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


/// Encoding followed by the existing logical cursor recovers exact bytes.
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

    auto encoded =
        serializeId3v23UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                encoded.value[],
                5000
            ),
            true
        );

    foreach (
        index,
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

        /*
         * Physical offsets need not equal logical indices once stuffing
         * has been crossed, but must remain inside the encoded source.
         */
        assert(
            decoded.value.sourceOffset >=
            5000
        );

        assert(
            decoded.value.sourceOffset <
            5000 + encoded.value.length
        );
    }

    assert(cursor.empty);
}


/// Already-unsynchronisation-like logical bytes remain reversible data.
unittest
{
    /*
     * The input here is logical data FF 00 E1, not already encoded
     * physical data. Protecting FF 00 is therefore required if the scheme
     * is active.
     */
    const ubyte[] logical =
        [
            0xFF,
            0x00,
            0xE1
        ];

    auto encoded =
        serializeId3v23UnsynchronisedBytes(
            logical
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            0xFF,
            0x00,
            0x00,
            0xE1
        ]
    );

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                encoded.value[]
            ),
            true
        );

    foreach (expected; logical)
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
