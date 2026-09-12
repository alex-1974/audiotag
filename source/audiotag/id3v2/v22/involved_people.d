/++
ID3v2.2 involved-people-list (`IPL`) frame decoding.

An `IPL` frame contains one text-encoding marker followed by an ordered
sequence of terminated string pairs:

    involvement $00 (00)
    involvee    $00 (00)
    involvement $00 (00)
    involvee    $00 (00)
    ...

ID3v2.2 does not distinguish musician credits from other functions. Every
decoded pair therefore uses `Id3v2PeopleCreditKind.unspecified`.

Whole-tag unsynchronisation is reversed only during logical traversal and text
decoding. Native entry spans retain the exact physical source bytes.

This module preserves native v2.2 semantics and performs no canonical mapping.


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
module audiotag.id3v2.v22.involved_people;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.people_credit :
    Id3v2PeopleCredit,
    Id3v2PeopleCreditKind;

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
One provenance-preserving native ID3v2.2 involved-people entry.

`credit` stores the decoded semantic pair.

`rawInvolvement` and `rawInvolvee` contain the physical encoded bytes of the
two strings, excluding their mandatory terminators while retaining any
whole-tag-unsynchronisation stuffing.
+/
struct Id3v22InvolvedPeopleEntry
{
    Id3v2PeopleCredit credit;
    ByteSpan rawInvolvement;
    ByteSpan rawInvolvee;
}


/++
Decoded native ID3v2.2 `IPL` frame.

Entry ordering is preserved exactly. Duplicate involvement strings are not
collapsed or reordered.
+/
struct Id3v22InvolvedPeopleFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Text encoding declared once for the complete people list.
    Id3v22TextEncoding encoding;

    /// Ordered decoded involvement/involvee entries.
    Id3v22InvolvedPeopleEntry[] entries;

    /// Whether ID3v2.2 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes one ID3v2.2 involved-people-list (`IPL`) frame.

Every involvement and every involvee is a mandatory terminated string. The
payload therefore has to contain complete pairs after the initial encoding
marker. An incomplete final pair is rejected rather than guessed or silently
discarded.

ID3v2.2 does not define a controlled vocabulary for involvement strings and
does not classify entries as musician or function credits. No such semantics
are inferred here.

Empty string fields are retained as valid native values because the
specification does not impose an additional non-empty constraint.

Params:
    frame = Previously validated and bounded ID3v2.2 frame.
    tagUnsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    The decoded native `IPL` frame or a structured parse/text error.
+/
ParseResult!Id3v22InvolvedPeopleFrame
decodeId3v22InvolvedPeopleFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "IPL"
    )
    {
        return
            ParseResult!Id3v22InvolvedPeopleFrame
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
            ParseResult!Id3v22InvolvedPeopleFrame
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;

    Id3v22InvolvedPeopleEntry[] entries;

    while (
        !payload.empty
    )
    {
        auto involvementResult =
            payload.takeId3v22TerminatedTextSegment(
                encoding
            );

        if (
            involvementResult.hasError
        )
        {
            return
                ParseResult!Id3v22InvolvedPeopleFrame
                    .failure(
                        involvementResult.error
                    );
        }

        const involvementSegment =
            involvementResult.value;

        auto involvement =
            decodeId3v22TextSpan(
                involvementSegment.raw,
                encoding,
                tagUnsynchronised
            );

        if (
            involvement.hasError
        )
        {
            return
                ParseResult!Id3v22InvolvedPeopleFrame
                    .failure(
                        involvement.error
                    );
        }

        auto involveeResult =
            payload.takeId3v22TerminatedTextSegment(
                encoding
            );

        if (
            involveeResult.hasError
        )
        {
            return
                ParseResult!Id3v22InvolvedPeopleFrame
                    .failure(
                        involveeResult.error
                    );
        }

        const involveeSegment =
            involveeResult.value;

        auto involvee =
            decodeId3v22TextSpan(
                involveeSegment.raw,
                encoding,
                tagUnsynchronised
            );

        if (
            involvee.hasError
        )
        {
            return
                ParseResult!Id3v22InvolvedPeopleFrame
                    .failure(
                        involvee.error
                    );
        }

        entries ~=
            Id3v22InvolvedPeopleEntry(
                Id3v2PeopleCredit(
                    Id3v2PeopleCreditKind.unspecified,
                    involvement.value,
                    involvee.value
                ),
                involvementSegment.raw,
                involveeSegment.raw
            );
    }

    return
        ParseResult!Id3v22InvolvedPeopleFrame
            .success(
                Id3v22InvolvedPeopleFrame(
                    frame.header.sourceOffset,
                    encoding,
                    entries,
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


/// One Latin-1 involvement/involvee pair decodes with physical provenance.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'P', 'L',
            0x00, 0x00, 0x0E,

            0x00,

            'g', 'u', 'i', 't', 'a', 'r',
            0x00,

            'A', 'l', 'i', 'c', 'e',
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
            .decodeId3v22InvolvedPeopleFrame();

    assert(result.hasValue);

    const people =
        result.value;

    assert(people.sourceOffset == 100);
    assert(people.encoding == Id3v22TextEncoding.latin1);
    assert(people.entries.length == 1);
    assert(!people.effectiveUnsynchronisation);

    const entry =
        people.entries[0];

    assert(
        entry.credit.kind ==
        Id3v2PeopleCreditKind.unspecified
    );

    assert(entry.credit.involvement == "guitar");
    assert(entry.credit.involvee == "Alice");

    assert(entry.rawInvolvement.sourceOffset == 107);
    assert(entry.rawInvolvement.data == cast(const(ubyte)[]) "guitar");

    assert(entry.rawInvolvee.sourceOffset == 114);
    assert(entry.rawInvolvee.data == cast(const(ubyte)[]) "Alice");
}


/// Multiple entries preserve source order and duplicate involvement labels.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'P', 'L',
            0x00, 0x00, 0x19,

            0x00,

            'g', 'u', 'i', 't', 'a', 'r',
            0x00,
            'A', 'l', 'i', 'c', 'e',
            0x00,

            'g', 'u', 'i', 't', 'a', 'r',
            0x00,
            'B', 'o', 'b',
            0x00
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
            .decodeId3v22InvolvedPeopleFrame();

    assert(result.hasValue);
    assert(result.value.entries.length == 2);

    assert(
        result.value.entries[0].credit.involvement ==
        "guitar"
    );

    assert(
        result.value.entries[0].credit.involvee ==
        "Alice"
    );

    assert(
        result.value.entries[1].credit.involvement ==
        "guitar"
    );

    assert(
        result.value.entries[1].credit.involvee ==
        "Bob"
    );
}


/// Empty involvement and involvee strings are retained rather than invented.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'P', 'L',
            0x00, 0x00, 0x03,

            0x00,
            0x00,
            0x00
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
            .decodeId3v22InvolvedPeopleFrame();

    assert(result.hasValue);
    assert(result.value.entries.length == 1);
    assert(result.value.entries[0].credit.involvement.length == 0);
    assert(result.value.entries[0].credit.involvee.length == 0);
}


/// A frame containing only the encoding marker is an empty native list.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'P', 'L',
            0x00, 0x00, 0x01,

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
            .decodeId3v22InvolvedPeopleFrame();

    assert(result.hasValue);
    assert(result.value.entries.length == 0);
}


/// An unterminated involvement string is rejected.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'P', 'L',
            0x00, 0x00, 0x07,

            0x00,
            'g', 'u', 'i', 't', 'a', 'r'
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
            .decodeId3v22InvolvedPeopleFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
    assert(result.error.offset == 507);
}


/// An odd terminated-string count is rejected as an incomplete final pair.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'P', 'L',
            0x00, 0x00, 0x08,

            0x00,
            'g', 'u', 'i', 't', 'a', 'r',
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
            .decodeId3v22InvolvedPeopleFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
    assert(result.error.offset == 614);
}


/// UCS-2 pair parsing uses the shared aligned terminator logic.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'P', 'L',
            0x00, 0x00, 0x09,

            0x01,

            0x00, 'g',
            0x00, 0x00,

            0x00, 'A',
            0x00, 0x00
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
            .decodeId3v22InvolvedPeopleFrame();

    assert(result.hasValue);
    assert(result.value.entries.length == 1);
    assert(result.value.entries[0].credit.involvement == "g");
    assert(result.value.entries[0].credit.involvee == "A");
}



/// The IPL codec rejects a different native frame identifier.
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
            .decodeId3v22InvolvedPeopleFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 800);
}


/// Whole-tag unsynchronisation preserves raw and decoded pair representations.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'P', 'L',
            0x00, 0x00, 0x07,

            0x00,

            'r',
            0xFF, 0x00,
            0xE1,
            0x00,

            'A',
            0x00
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
    assert(frame.value.header.size == 7);
    assert(frame.value.data.length == 8);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22InvolvedPeopleFrame(
                true
            );

    assert(result.hasValue);

    const entry =
        result.value.entries[0];

    assert(result.value.effectiveUnsynchronisation);
    assert(result.value.entries.length == 1);

    assert(
        entry.credit.involvement ==
        "r\u00FF\u00E1"
    );

    assert(entry.credit.involvee == "A");

    assert(
        entry.rawInvolvement.data ==
        [
            'r',
            0xFF, 0x00,
            0xE1
        ]
    );

    assert(entry.rawInvolvee.data == ['A']);
}
