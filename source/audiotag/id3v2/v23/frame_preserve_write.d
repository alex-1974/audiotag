/++
Exact physical serialization of one unchanged preserved ID3v2.3 frame.

For a source tag without ID3v2.3 whole-tag unsynchronisation, an
unchanged native frame can be emitted without semantic regeneration:

- the parsed fixed frame-header values are serialized back into their
  unique ordinary ID3v2.3 ten-byte representation;
- the complete bounded native frame-data region is copied unchanged.

This preserves:

- native frame identifier;
- logical frame-data size;
- status flags;
- format flags;
- grouping/encryption/compression additions inside frame data;
- compressed or encrypted payload bytes;
- unknown semantic payload bytes.

`sourceOffset` is provenance and is intentionally not serialized.

ID3v2.3 whole-tag unsynchronisation requires separate treatment.

Unlike ID3v2.4 frame-level unsynchronisation, v2.3 unsynchronisation is
applied across the complete tag body. Stuffing bytes may therefore occur
not only inside frame data but also between logical bytes of the frame
header itself.

The current `Id3v23FrameEnvelope` retains the parsed logical header and
the bounded physical frame-data span, but does not independently retain
an exact physical copy of every possibly stuffed header byte.

Consequently this writer deliberately rejects
`sourceTagUnsynchronised == true`.

Whole-tag unsynchronisation writing belongs to the later sequence/tag
writer and must establish one coherent representation for preserved,
regenerated and newly introduced frames.

No tag header, padding or container bytes are serialized here.
+/
module audiotag.id3v2.v23.frame_preserve_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.frame :
    Id3v23FrameEnvelope;

import audiotag.id3v2.v23.frame_header_write :
    serializeId3v23FrameHeader;


/++
Serializes one unchanged provenance-preserved ID3v2.3 frame.

At present exact preservation is supported only when the source tag did
not use ID3v2.3 whole-tag unsynchronisation.

Params:
    frame = Original unchanged frame envelope.
    sourceTagUnsynchronised = Whether the enclosing source ID3v2.3 tag
        used whole-tag unsynchronisation.

Returns:
    Complete owned native frame bytes for a normal source tag, or a
    structured serialization failure when whole-tag unsynchronisation
    would require a later tag-level transformation.

Safety:
    No source bytes are modified. Output owns its copied bytes.
+/
SerializationResult!(ubyte[])
serializePreservedId3v23Frame(
    const(Id3v23FrameEnvelope) frame,
    bool sourceTagUnsynchronised = false
)
    @safe
{
    /*
     * Whole-tag unsynchronisation cannot safely be handled by rebuilding
     * one isolated frame.
     *
     * In particular, stuffing may have occurred inside the physical
     * frame-header representation or across a later frame/tag boundary.
     */
    if (sourceTagUnsynchronised)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation
                    )
                );
    }

    auto encodedHeader =
        serializeId3v23FrameHeader(
            frame.header
        );

    if (encodedHeader.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    encodedHeader.error
                );
    }

    /*
     * Without whole-tag unsynchronisation, the physical frame-data span
     * has exactly the logical length declared by the header.
     *
     * A valid non-unsynchronised frame envelope is produced with this
     * invariant by the structural parser.
     */
    assert(
        frame.data.length ==
        frame.header.size
    );

    auto output =
        new ubyte[
            encodedHeader.value.length +
            frame.data.length
        ];

    output[
        0 ..
        encodedHeader.value.length
    ] =
        encodedHeader.value[];

    output[
        encodedHeader.value.length ..
        $
    ] =
        frame.data.data;

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

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;


    private Id3v23FrameEnvelope
    parseTestFrame(
        const(ubyte)[] bytes,
        size_t sourceOffset = 0,
        bool tagUnsynchronised = false
    )
        @safe
    {
        auto cursor =
            Id3v23DataCursor(
                ByteSpan(
                    bytes,
                    sourceOffset
                ),
                tagUnsynchronised
            );

        auto parsed =
            cursor.parseId3v23FrameEnvelope();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }
}


/// A plain unchanged v2.3 frame roundtrips byte-for-byte.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x00,
            'T', 'i', 't', 'l', 'e'
        ];

    const frame =
        parseTestFrame(
            bytes,
            1000
        );

    auto serialized =
        serializePreservedId3v23Frame(
            frame
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        bytes
    );
}


/// Native v2.3 status and format flags are retained exactly.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x05,

            /*
             * discard-on-tag,
             * discard-on-file,
             * read-only
             */
            0xE0,

            /*
             * compression,
             * encryption,
             * grouping
             */
            0xE0,

            /*
             * Opaque physical frame-data region.
             */
            0x2A,
            0x10,
            0x20,
            0x30,
            0x40
        ];

    const frame =
        parseTestFrame(bytes);

    auto serialized =
        serializePreservedId3v23Frame(
            frame
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        bytes
    );
}


/// Unknown semantic payload bytes remain byte-identical.
unittest
{
    const ubyte[] bytes =
        [
            'X', 'Y', 'Z', '1',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            0x00,
            0xFF,
            0x7F,
            0x80,
            0x42
        ];

    const frame =
        parseTestFrame(
            bytes,
            5000
        );

    auto serialized =
        serializePreservedId3v23Frame(
            frame
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        bytes
    );

    /*
     * Absolute source provenance is not emitted.
     */
    assert(
        serialized.value.length ==
        15
    );
}


/// Ordinary zero and FF bytes require no transformation by preservation.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            0x00,
            0xFF,
            0xE1,
            0xFF,
            0x00
        ];

    const frame =
        parseTestFrame(bytes);

    auto serialized =
        serializePreservedId3v23Frame(
            frame
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        bytes
    );
}


/// Whole-tag-unsynchronised source frames are blocked at this layer.
unittest
{
    /*
     * Logical frame data:
     *
     *     FF E1
     *
     * Physical source frame data after v2.3 whole-tag
     * unsynchronisation:
     *
     *     FF 00 E1
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',

            /*
             * Two logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x02,

            0x00, 0x00,

            0xFF,
            0x00,
            0xE1
        ];

    const frame =
        parseTestFrame(
            bytes,
            7000,
            true
        );

    /*
     * The structural envelope deliberately retains the complete
     * physical data region.
     */
    assert(frame.header.size == 2);
    assert(frame.data.length == 3);

    auto serialized =
        serializePreservedId3v23Frame(
            frame,
            true
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
