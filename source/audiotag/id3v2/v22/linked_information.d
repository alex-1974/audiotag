/++
ID3v2.2 linked-information (`LNK`) frame decoding.

The logical payload contains:

- a three-byte target frame identifier;
- one null-terminated ISO-8859-1 URL;
- target-specific additional identity data.

ID3v2.2 defines three additional-identity shapes:

- no additional data for the explicitly listed singleton frames, ordinary
  text-information frames, and URL-link frames;
- one content descriptor for `TXX`, `PIC`, `GEO`, `CRM`, and `CRA`;
- three language bytes followed by a content descriptor for `COM`, `SLT`,
  and `ULT`.

The published v2.2 linked-information section lists `LLT` among linkable
frames, although the declared MPEG-location frame is `MLL` and its v2.3
successor is `MLLT`. This decoder treats `MLL` as the intended v2.2 target
and does not accept the undeclared `LLT` identifier.

This codec describes the link only. It never opens or resolves the referenced
URL.

Whole-tag unsynchronisation is reversed during logical traversal. Raw spans
retain the exact physical source representation, including stuffing bytes.

This module performs no canonical metadata mapping.


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
module audiotag.id3v2.v22.linked_information;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.linked_information :
    Id3v2LinkedAdditionalIdKind,
    Id3v2LinkedInformation;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

import audiotag.id3v2.v22.text_decode :
    decodeId3v22TextSpan;

import audiotag.id3v2.v22.text_encoding :
    Id3v22TextEncoding;

import audiotag.id3v2.v22.text_segment :
    takeId3v22TerminatedTextSegment;

struct Id3v22LinkedInformationFrame
{
    size_t sourceOffset;
    char[3] linkedFrameId;
    ByteSpan rawLinkedFrameId;
    Id3v2LinkedInformation linked;
    ByteSpan rawUrl;
    size_t urlTerminatorSourceOffset;
    ByteSpan rawLanguage;
    ByteSpan rawDescriptor;
    bool effectiveUnsynchronisation;
}

private bool
isId3v22FrameIdByte(
    ubyte value
)
    @safe pure nothrow @nogc
{
    return
        (
            value >= 'A' &&
            value <= 'Z'
        ) ||
        (
            value >= '0' &&
            value <= '9'
        );
}

private bool
idEquals(
    const(char[3]) id,
    string expected
)
    @safe pure nothrow @nogc
{
    assert(expected.length == 3);

    return
        id[0] == expected[0] &&
        id[1] == expected[1] &&
        id[2] == expected[2];
}

private ParseResult!Id3v2LinkedAdditionalIdKind
classifyId3v22LinkedTarget(
    const(char[3]) id,
    size_t sourceOffset
)
    @safe pure nothrow @nogc
{
    if (idEquals(id, "TXX"))
    {
        return
            ParseResult!Id3v2LinkedAdditionalIdKind
                .success(
                    Id3v2LinkedAdditionalIdKind.descriptor
                );
    }

    if (id[0] == 'T')
    {
        return
            ParseResult!Id3v2LinkedAdditionalIdKind
                .success(
                    Id3v2LinkedAdditionalIdKind.none
                );
    }

    if (id[0] == 'W')
    {
        return
            ParseResult!Id3v2LinkedAdditionalIdKind
                .success(
                    Id3v2LinkedAdditionalIdKind.none
                );
    }

    if (
        idEquals(id, "IPL") ||
        idEquals(id, "MCI") ||
        idEquals(id, "ETC") ||
        idEquals(id, "MLL") ||
        idEquals(id, "STC") ||
        idEquals(id, "RVA") ||
        idEquals(id, "EQU") ||
        idEquals(id, "REV") ||
        idEquals(id, "BUF")
    )
    {
        return
            ParseResult!Id3v2LinkedAdditionalIdKind
                .success(
                    Id3v2LinkedAdditionalIdKind.none
                );
    }

    if (
        idEquals(id, "PIC") ||
        idEquals(id, "GEO") ||
        idEquals(id, "CRM") ||
        idEquals(id, "CRA")
    )
    {
        return
            ParseResult!Id3v2LinkedAdditionalIdKind
                .success(
                    Id3v2LinkedAdditionalIdKind.descriptor
                );
    }

    if (
        idEquals(id, "COM") ||
        idEquals(id, "SLT") ||
        idEquals(id, "ULT")
    )
    {
        return
            ParseResult!Id3v2LinkedAdditionalIdKind
                .success(
                    Id3v2LinkedAdditionalIdKind.languageAndDescriptor
                );
    }

    return
        ParseResult!Id3v2LinkedAdditionalIdKind
            .failure(
                ParseError(
                    ParseErrorCode.inconsistentStructure,
                    sourceOffset
                )
            );
}

ParseResult!Id3v22LinkedInformationFrame
decodeId3v22LinkedInformationFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "LNK"
    )
    {
        return
            ParseResult!Id3v22LinkedInformationFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }

    if (frame.header.size < 4)
    {
        return
            ParseResult!Id3v22LinkedInformationFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        frame.data.sourceOffset,
                        4,
                        frame.header.size
                    )
                );
    }

    auto payload =
        Id3v22DataCursor(
            frame.data,
            tagUnsynchronised
        );

    const idStart =
        payload.remainingRaw;

    char[3] linkedFrameId;

    foreach (
        index;
        0 .. 3
    )
    {
        auto byteResult =
            payload.takeByte();

        if (byteResult.hasError)
        {
            return
                ParseResult!Id3v22LinkedInformationFrame
                    .failure(
                        byteResult.error
                    );
        }

        const value =
            byteResult.value.value;

        if (!isId3v22FrameIdByte(value))
        {
            return
                ParseResult!Id3v22LinkedInformationFrame
                    .failure(
                        ParseError(
                            ParseErrorCode.invalidSignature,
                            byteResult.value.sourceOffset
                        )
                    );
        }

        linkedFrameId[index] =
            cast(char) value;
    }

    const rawLinkedFrameId =
        idStart.subspan(
            0,
            idStart.length -
                payload.remainingRaw.length
        );

    auto kindResult =
        classifyId3v22LinkedTarget(
            linkedFrameId,
            rawLinkedFrameId.sourceOffset
        );

    if (kindResult.hasError)
    {
        return
            ParseResult!Id3v22LinkedInformationFrame
                .failure(
                    kindResult.error
                );
    }

    const additionalKind =
        kindResult.value;

    auto urlSegmentResult =
        payload.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
        );

    if (urlSegmentResult.hasError)
    {
        return
            ParseResult!Id3v22LinkedInformationFrame
                .failure(
                    urlSegmentResult.error
                );
    }

    const urlSegment =
        urlSegmentResult.value;

    auto urlResult =
        decodeId3v22TextSpan(
            urlSegment.raw,
            Id3v22TextEncoding.latin1,
            tagUnsynchronised
        );

    if (urlResult.hasError)
    {
        return
            ParseResult!Id3v22LinkedInformationFrame
                .failure(
                    urlResult.error
                );
    }

    char[3] language;

    ByteSpan rawLanguage =
        payload.remainingRaw.subspan(
            0,
            0
        );

    ByteSpan rawDescriptor =
        rawLanguage;

    string descriptor;

    final switch (additionalKind)
    {
        case Id3v2LinkedAdditionalIdKind.none:
        {
            if (!payload.empty)
            {
                return
                    ParseResult!Id3v22LinkedInformationFrame
                        .failure(
                            ParseError(
                                ParseErrorCode.inconsistentStructure,
                                payload.absoluteOffset
                            )
                        );
            }

            break;
        }

        case Id3v2LinkedAdditionalIdKind.descriptor:
        {
            rawDescriptor =
                payload.remainingRaw;

            auto descriptorResult =
                decodeId3v22TextSpan(
                    rawDescriptor,
                    Id3v22TextEncoding.latin1,
                    tagUnsynchronised
                );

            if (descriptorResult.hasError)
            {
                return
                    ParseResult!Id3v22LinkedInformationFrame
                        .failure(
                            descriptorResult.error
                        );
            }

            descriptor =
                descriptorResult.value;

            break;
        }

        case Id3v2LinkedAdditionalIdKind.languageAndDescriptor:
        {
            const languageStart =
                payload.remainingRaw;

            foreach (
                index;
                0 .. 3
            )
            {
                auto byteResult =
                    payload.takeByte();

                if (byteResult.hasError)
                {
                    return
                        ParseResult!Id3v22LinkedInformationFrame
                            .failure(
                                byteResult.error
                            );
                }

                language[index] =
                    cast(char)
                        byteResult.value.value;
            }

            rawLanguage =
                languageStart.subspan(
                    0,
                    languageStart.length -
                        payload.remainingRaw.length
                );

            rawDescriptor =
                payload.remainingRaw;

            auto descriptorResult =
                decodeId3v22TextSpan(
                    rawDescriptor,
                    Id3v22TextEncoding.latin1,
                    tagUnsynchronised
                );

            if (descriptorResult.hasError)
            {
                return
                    ParseResult!Id3v22LinkedInformationFrame
                        .failure(
                            descriptorResult.error
                        );
            }

            descriptor =
                descriptorResult.value;

            break;
        }
    }

    return
        ParseResult!Id3v22LinkedInformationFrame
            .success(
                Id3v22LinkedInformationFrame(
                    frame.header.sourceOffset,
                    linkedFrameId,
                    rawLinkedFrameId,
                    Id3v2LinkedInformation(
                        urlResult.value,
                        additionalKind,
                        language,
                        descriptor
                    ),
                    urlSegment.raw,
                    urlSegment.terminatorSourceOffset,
                    rawLanguage,
                    rawDescriptor,
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

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x0D,
            'R', 'E', 'V',
            'o', 't', 'h', 'e', 'r', '.', 'm', 'p', '3',
            0x00
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
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasValue);
    assert(result.value.linkedFrameId[] == "REV");
    assert(result.value.linked.url == "other.mp3");
    assert(
        result.value.linked.additionalKind ==
        Id3v2LinkedAdditionalIdKind.none
    );
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x10,
            'T', 'X', 'X',
            'm', 'e', 't', 'a', '.', 'i', 'd', '3',
            0x00,
            'm', 'o', 'o', 'd'
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
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasValue);
    assert(result.value.linkedFrameId[] == "TXX");
    assert(result.value.linked.url == "meta.id3");
    assert(
        result.value.linked.additionalKind ==
        Id3v2LinkedAdditionalIdKind.descriptor
    );
    assert(result.value.linked.descriptor == "mood");
    assert(result.value.rawDescriptor.data == ['m', 'o', 'o', 'd']);
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x15,
            'C', 'O', 'M',
            'c', 'o', 'm', 'm', 'o', 'n', '.', 'i', 'd', '3',
            0x00,
            'e', 'n', 'g',
            'n', 'o', 't', 'e'
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
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasValue);
    assert(
        result.value.linked.additionalKind ==
        Id3v2LinkedAdditionalIdKind.languageAndDescriptor
    );
    assert(result.value.linked.language[] == "eng");
    assert(result.value.linked.descriptor == "note");
    assert(result.value.rawLanguage.data == ['e', 'n', 'g']);
    assert(result.value.rawDescriptor.data == ['n', 'o', 't', 'e']);
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x09,
            'T', 'T', '2',
            'x', '.', 'i', 'd', '3',
            0x00
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
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasValue);
    assert(result.value.linkedFrameId[] == "TT2");
    assert(
        result.value.linked.additionalKind ==
        Id3v2LinkedAdditionalIdKind.none
    );
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x05,
            'M', 'L', 'L',
            'x',
            0x00
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
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasValue);
    assert(result.value.linkedFrameId[] == "MLL");
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x05,
            'L', 'L', 'T',
            'x',
            0x00
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
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.inconsistentStructure);
    assert(result.error.offset == 606);
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x05,
            'P', 'O', 'P',
            'x',
            0x00
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
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.inconsistentStructure);
    assert(result.error.offset == 706);
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x05,
            'T', '?', '2',
            'x',
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
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 807);
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x06,
            'R', 'E', 'V',
            'u', 'r', 'l'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x07,
            'R', 'E', 'V',
            'x',
            0x00,
            'n', 'o'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1000
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.inconsistentStructure);
    assert(result.error.offset == 1011);
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x07,
            'C', 'O', 'M',
            'x',
            0x00,
            'e', 'n'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1100
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
}

unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x08,
            'T', 'X', 'X',
            'x',
            0xFF, 0x00,
            0xE1,
            0x00,
            'd'
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1200
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 8);
    assert(frame.value.data.length == 9);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22LinkedInformationFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.effectiveUnsynchronisation);
    assert(result.value.linked.descriptor == "d");

    assert(
        result.value.rawUrl.data ==
        [
            'x',
            0xFF, 0x00,
            0xE1
        ]
    );
}

unittest
{
    const ubyte[] bytes =
        [
            'B', 'U', 'F',
            0x00, 0x00, 0x04,
            'R', 'E', 'V',
            0x00
        ];

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

    auto result =
        frame.value
            .decodeId3v22LinkedInformationFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 1300);
}
