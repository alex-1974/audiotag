/++
ID3v2.2 general-encapsulated-object (`GEO`) frame decoding.

A `GEO` frame contains:

- one text-encoding marker;
- one terminated ISO-8859-1 MIME type;
- one terminated filename using the selected text encoding;
- one terminated content description using the selected text encoding;
- the remaining bytes as opaque encapsulated-object data.

The ID3v2.2 prose contains an ambiguity about filename encoding, while its
formal field layout gives the filename an encoding-dependent terminator.
This codec follows that field grammar and the semantics carried forward
explicitly by ID3v2.3/v2.4: MIME type is Latin-1, while filename and content
description use the frame's selected text encoding.

Whole-tag unsynchronisation is reversed only during logical traversal and text
decoding. All returned raw spans retain the exact physical source bytes.

This module performs no MIME validation, object-format decoding or canonical
metadata mapping.


Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.general_encapsulated_object;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.encapsulated_object :
    Id3v2EncapsulatedObjectInfo;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

import audiotag.id3v2.v22.text_decode :
    decodeId3v22TextSpan;

import audiotag.id3v2.v22.text_encoding :
    Id3v22TextEncoding,
    parseId3v22TextEncoding;

import audiotag.id3v2.v22.text_segment :
    takeId3v22TerminatedTextSegment;


/++
Decoded native ID3v2.2 `GEO` frame.

`rawMimeType`, `rawFilename` and `rawDescription` exclude their mandatory
terminators while preserving physical whole-tag-unsynchronisation stuffing.

`rawObjectData` is the exact physical remainder of the bounded frame payload.
No attempt is made to interpret, decompress or copy the encapsulated object.
+/
struct Id3v22GeneralEncapsulatedObjectFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Encoding used by filename and content description.
    Id3v22TextEncoding textEncoding;

    /// Shared decoded descriptor.
    Id3v2EncapsulatedObjectInfo info;

    /// Physical ISO-8859-1 MIME-type bytes excluding the terminator.
    ByteSpan rawMimeType;

    /// Physical filename bytes excluding the terminator.
    ByteSpan rawFilename;

    /// Physical content-description bytes excluding the terminator.
    ByteSpan rawDescription;

    /// Exact physical encapsulated-object bytes to the frame boundary.
    ByteSpan rawObjectData;

    /// Whether ID3v2.2 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes one ID3v2.2 general-encapsulated-object (`GEO`) frame.

All three textual fields are structurally terminated. MIME type always uses
ISO-8859-1. Filename and content description use the frame's selected legacy
text encoding.

MIME type and filename may be empty. The specification identifies the content
description as the identity key for repeated GEO frames but does not define a
non-empty requirement here, so an empty description is retained rather than
rejected.

The encapsulated object's binary bytes occupy the remainder of the already
bounded frame payload and may be empty.

Params:
    frame = Previously validated and bounded ID3v2.2 frame.
    tagUnsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    The decoded native `GEO` frame or a structured parse/text error.
+/
ParseResult!Id3v22GeneralEncapsulatedObjectFrame
decodeId3v22GeneralEncapsulatedObjectFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "GEO"
    )
    {
        return
            ParseResult!Id3v22GeneralEncapsulatedObjectFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }

    auto payload =
        Id3v22DataCursor(
            frame.data,
            tagUnsynchronised
        );

    auto encodingResult =
        payload.parseId3v22TextEncoding();

    if (
        encodingResult.hasError
    )
    {
        return
            ParseResult!Id3v22GeneralEncapsulatedObjectFrame
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;

    auto mimeResult =
        payload.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
        );

    if (
        mimeResult.hasError
    )
    {
        return
            ParseResult!Id3v22GeneralEncapsulatedObjectFrame
                .failure(
                    mimeResult.error
                );
    }

    const mimeSegment =
        mimeResult.value;

    auto mimeType =
        decodeId3v22TextSpan(
            mimeSegment.raw,
            Id3v22TextEncoding.latin1,
            tagUnsynchronised
        );

    if (
        mimeType.hasError
    )
    {
        return
            ParseResult!Id3v22GeneralEncapsulatedObjectFrame
                .failure(
                    mimeType.error
                );
    }

    auto filenameResult =
        payload.takeId3v22TerminatedTextSegment(
            encoding
        );

    if (
        filenameResult.hasError
    )
    {
        return
            ParseResult!Id3v22GeneralEncapsulatedObjectFrame
                .failure(
                    filenameResult.error
                );
    }

    const filenameSegment =
        filenameResult.value;

    auto filename =
        decodeId3v22TextSpan(
            filenameSegment.raw,
            encoding,
            tagUnsynchronised
        );

    if (
        filename.hasError
    )
    {
        return
            ParseResult!Id3v22GeneralEncapsulatedObjectFrame
                .failure(
                    filename.error
                );
    }

    auto descriptionResult =
        payload.takeId3v22TerminatedTextSegment(
            encoding
        );

    if (
        descriptionResult.hasError
    )
    {
        return
            ParseResult!Id3v22GeneralEncapsulatedObjectFrame
                .failure(
                    descriptionResult.error
                );
    }

    const descriptionSegment =
        descriptionResult.value;

    auto description =
        decodeId3v22TextSpan(
            descriptionSegment.raw,
            encoding,
            tagUnsynchronised
        );

    if (
        description.hasError
    )
    {
        return
            ParseResult!Id3v22GeneralEncapsulatedObjectFrame
                .failure(
                    description.error
                );
    }

    const rawObjectData =
        payload.remainingRaw;

    return
        ParseResult!Id3v22GeneralEncapsulatedObjectFrame
            .success(
                Id3v22GeneralEncapsulatedObjectFrame(
                    frame.header.sourceOffset,
                    encoding,
                    Id3v2EncapsulatedObjectInfo(
                        mimeType.value,
                        filename.value,
                        description.value
                    ),
                    mimeSegment.raw,
                    filenameSegment.raw,
                    descriptionSegment.raw,
                    rawObjectData,
                    tagUnsynchronised
                )
            );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.id3v2.v22.frame :
        parseId3v22FrameEnvelope;
}


/// A normal Latin-1 GEO frame decodes all descriptor fields and raw data.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O',
            0x00, 0x00, 0x26,

            0x00,

            'a', 'p', 'p', 'l', 'i', 'c', 'a', 't',
            'i', 'o', 'n', '/', 'p', 'd', 'f',
            0x00,

            'm', 'a', 'n', 'u', 'a', 'l', '.', 'p', 'd', 'f',
            0x00,

            'M', 'a', 'n', 'u', 'a', 'l',
            0x00,

            0x25, 0x50, 0x44
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
            .decodeId3v22GeneralEncapsulatedObjectFrame();

    assert(result.hasValue);

    const object =
        result.value;

    assert(object.sourceOffset == 100);
    assert(object.textEncoding == Id3v22TextEncoding.latin1);
    assert(object.info.mimeType == "application/pdf");
    assert(object.info.filename == "manual.pdf");
    assert(object.info.description == "Manual");

    assert(object.rawMimeType.sourceOffset == 107);
    assert(object.rawFilename.sourceOffset == 123);
    assert(object.rawDescription.sourceOffset == 134);
    assert(object.rawObjectData.sourceOffset == 141);

    assert(
        object.rawObjectData.data ==
        [0x25, 0x50, 0x44]
    );

    assert(!object.effectiveUnsynchronisation);
}


/// MIME type and filename may both be empty.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O',
            0x00, 0x00, 0x06,

            0x00,
            0x00,
            0x00,
            'x', 0x00,
            0x7F
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
            .decodeId3v22GeneralEncapsulatedObjectFrame();

    assert(result.hasValue);

    assert(result.value.info.mimeType.length == 0);
    assert(result.value.info.filename.length == 0);
    assert(result.value.info.description == "x");

    assert(
        result.value.rawObjectData.data ==
        [0x7F]
    );
}


/// The encapsulated object itself may be empty.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O',
            0x00, 0x00, 0x07,

            0x00,
            'x', 0x00,
            'f', 0x00,
            'd', 0x00
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
            .decodeId3v22GeneralEncapsulatedObjectFrame();

    assert(result.hasValue);
    assert(result.value.rawObjectData.empty);
}


/// MIME type stays Latin-1 while filename and description may use UCS-2.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O',
            0x00, 0x00, 0x12,

            0x01,

            'c', 'a', 'f', 0xE9,
            0x00,

            0x00, 'A',
            0x00, 0x00,

            0x00, 'B',
            0x00, 0x00,

            0x01, 0x02, 0x03, 0x04
        ];

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

    auto result =
        frame.value
            .decodeId3v22GeneralEncapsulatedObjectFrame();

    assert(result.hasValue);

    assert(result.value.info.mimeType == "caf\u00E9");
    assert(result.value.info.filename == "A");
    assert(result.value.info.description == "B");

    assert(
        result.value.rawObjectData.data ==
        [0x01, 0x02, 0x03, 0x04]
    );
}


/// A missing MIME terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O',
            0x00, 0x00, 0x04,

            0x00,
            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22GeneralEncapsulatedObjectFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
    assert(result.error.offset == 507);
}


/// A missing filename terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O',
            0x00, 0x00, 0x06,

            0x00,
            'x', 0x00,
            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22GeneralEncapsulatedObjectFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
    assert(result.error.offset == 609);
}


/// A missing content-description terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O',
            0x00, 0x00, 0x08,

            0x00,
            'x', 0x00,
            'f', 0x00,
            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22GeneralEncapsulatedObjectFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
    assert(result.error.offset == 711);
}


/// GEO rejects another native frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',
            0x00, 0x00, 0x01,

            0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                800
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22GeneralEncapsulatedObjectFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 800);
}


/// Whole-tag unsynchronisation preserves physical spans and decoded text.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O',
            0x00, 0x00, 0x0B,

            0x00,

            'a',
            0x00,

            'r',
            0xFF, 0x00,
            0xE1,
            0x00,

            'A',
            0x00,

            0xFF, 0x00,
            0xE2
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                900
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 11);
    assert(frame.value.data.length == 13);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22GeneralEncapsulatedObjectFrame(
                true
            );

    assert(result.hasValue);

    const object =
        result.value;

    assert(object.effectiveUnsynchronisation);
    assert(object.info.mimeType == "a");
    assert(object.info.filename == "r\u00FF\u00E1");
    assert(object.info.description == "A");

    assert(
        object.rawFilename.data ==
        [
            'r',
            0xFF, 0x00,
            0xE1
        ]
    );

    assert(
        object.rawObjectData.data ==
        [
            0xFF, 0x00,
            0xE2
        ]
    );
}
