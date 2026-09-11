/++
ID3v2.2 music-CD-identifier (`MCI`) frame decoding.

`MCI` contains a binary dump of the source CD's Table Of Contents (TOC).
ID3v2.2 describes the payload as a four-byte TOC header followed by eight-byte
TOC entries, with a maximum complete payload size of 804 bytes.

The TOC remains opaque in this codec. No CD-ROM descriptor parsing, CDDB
lookup, track-address conversion or other external interpretation is
performed.

The specification also requires a present and valid `TRK` frame. That is a
relationship between frames and therefore belongs to tag-level validation,
not this single-frame decoder.

Whole-tag unsynchronisation is reversed by the enclosing v2.2 frame parser
when determining the logical frame extent. `rawToc` retains the exact
physical source representation, including any inserted stuffing bytes.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.music_cd_identifier;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.music_cd_identifier :
    isValidId3v2MusicCdTocLength;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

struct Id3v22MusicCdIdentifierFrame
{
    size_t sourceOffset;
    size_t logicalTocLength;
    ByteSpan rawToc;
    bool effectiveUnsynchronisation;
}

ParseResult!Id3v22MusicCdIdentifierFrame
decodeId3v22MusicCdIdentifierFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe pure nothrow @nogc
{
    if (
        frame.header.id[] !=
        "MCI"
    )
    {
        return
            ParseResult!Id3v22MusicCdIdentifierFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }

    if (
        !isValidId3v2MusicCdTocLength(
            frame.header.size
        )
    )
    {
        return
            ParseResult!Id3v22MusicCdIdentifierFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        frame.data.sourceOffset,
                        4,
                        frame.header.size
                    )
                );
    }

    return
        ParseResult!Id3v22MusicCdIdentifierFrame
            .success(
                Id3v22MusicCdIdentifierFrame(
                    frame.header.sourceOffset,
                    frame.header.size,
                    frame.data,
                    tagUnsynchronised
                )
            );
}

version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.id3v2.v22.data_cursor :
        Id3v22DataCursor;

    import audiotag.id3v2.v22.frame :
        parseId3v22FrameEnvelope;
}

unittest
{
    const ubyte[] bytes =
        [
            'M', 'C', 'I',
            0x00, 0x00, 0x04,
            0x00, 0x02, 0x01, 0x01
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22MusicCdIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.sourceOffset == 100);
    assert(result.value.logicalTocLength == 4);
    assert(result.value.rawToc.sourceOffset == 106);
    assert(
        result.value.rawToc.data ==
        [
            0x00, 0x02, 0x01, 0x01
        ]
    );
    assert(!result.value.effectiveUnsynchronisation);
}

unittest
{
    const ubyte[] bytes =
        [
            'M', 'C', 'I',
            0x00, 0x00, 0x0C,

            0x00, 0x0A, 0x01, 0x01,

            0x00, 0x14, 0x01, 0x00,
            0x00, 0x00, 0x02, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                200
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22MusicCdIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.logicalTocLength == 12);
    assert(result.value.rawToc.length == 12);
}

unittest
{
    const ubyte[] bytes =
        [
            'M', 'C', 'I',
            0x00, 0x00, 0x0B,

            0x00, 0x09, 0x01, 0x01,
            0x00, 0x14, 0x01, 0x00,
            0x00, 0x00, 0x02
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22MusicCdIdentifierFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
}

unittest
{
    ubyte[] bytes;

    bytes ~=
        [
            'M', 'C', 'I',
            0x00, 0x03, 0x24
        ];

    bytes.length +=
        804;

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 804);

    auto result =
        frame.value
            .decodeId3v22MusicCdIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.logicalTocLength == 804);
}

unittest
{
    ubyte[] bytes;

    bytes ~=
        [
            'M', 'C', 'I',
            0x00, 0x03, 0x2C
        ];

    bytes.length +=
        812;

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1300
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 812);

    auto result =
        frame.value
            .decodeId3v22MusicCdIdentifierFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
}

unittest
{
    const ubyte[] bytes =
        [
            'M', 'C', 'I',
            0x00, 0x00, 0x0C,

            0x00, 0x0A, 0x01, 0x01,

            0x00, 0x14,
            0xFF, 0x00, 0xE1,
            0x00, 0x00,
            0x02, 0x00
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                2200
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 12);
    assert(frame.value.data.length == 13);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22MusicCdIdentifierFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.logicalTocLength == 12);
    assert(result.value.rawToc.length == 13);
    assert(result.value.effectiveUnsynchronisation);

    assert(
        result.value.rawToc.data[6 .. 9] ==
        [
            0xFF, 0x00, 0xE1
        ]
    );
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x04,
            0x00, 0x02, 0x01, 0x01
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                3000
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22MusicCdIdentifierFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 3000);
}
