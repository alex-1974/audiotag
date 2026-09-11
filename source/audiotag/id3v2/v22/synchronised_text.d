/++
ID3v2.2 synchronised-lyrics/text (`SLT`) frame decoding.

An `SLT` frame contains:

- one text-encoding marker;
- one three-byte ISO-639-2 language field;
- one timestamp-format discriminator;
- one v2.2 content-type byte;
- one terminated content descriptor;
- zero or more synchronised text cues, each consisting of terminated text
  followed by one absolute unsigned 32-bit big-endian timestamp.

ID3v2.2 defines content types `$00` through `$05`. Later ID3v2 revisions add
further values, so the content-type enum remains revision-specific.

Whole-tag byte unsynchronisation is reversed during logical traversal and text
decoding. Raw language, descriptor, cue-text and timestamp spans preserve the
exact physical source representation.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.synchronised_text;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.synchronised_text :
    Id3v2SynchronisedTextCue;

import audiotag.id3v2.common.timestamp :
    Id3v2TimestampFormat,
    isValidId3v2TimestampFormat;

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
ID3v2.2 `SLT` content-type values.
+/
enum Id3v22SynchronisedTextContentType : ubyte
{
    other = 0x00,
    lyrics = 0x01,
    textTranscription = 0x02,
    movementPartName = 0x03,
    events = 0x04,
    chord = 0x05
}


/++
Returns whether one raw byte is a defined ID3v2.2 `SLT` content type.
+/
bool
isValidId3v22SynchronisedTextContentType(
    ubyte value
)
    @safe pure nothrow @nogc
{
    return
        value <=
        cast(ubyte)
            Id3v22SynchronisedTextContentType.chord;
}


/++
One provenance-preserving native ID3v2.2 synchronised-text cue.
+/
struct Id3v22SynchronisedTextCue
{
    /// Shared decoded cue semantics.
    Id3v2SynchronisedTextCue cue;

    /// Physical cue-text bytes excluding the mandatory terminator.
    ByteSpan rawText;

    /// Physical bytes that produced the four logical timestamp bytes.
    ByteSpan rawTimestamp;
}


/++
Decoded native ID3v2.2 `SLT` frame.

Cue ordering is preserved exactly. ID3v2.2 says timestamps should be sorted
chronologically, so this native decoder neither rejects nor reorders an
out-of-order source sequence.
+/
struct Id3v22SynchronisedTextFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Encoding used by descriptor and cue text.
    Id3v22TextEncoding encoding;

    /// Three-byte language field as stored logically.
    char[3] language;

    /// Physical language bytes as stored.
    ByteSpan rawLanguage;

    /// Unit used by every cue timestamp.
    Id3v2TimestampFormat timestampFormat;

    /// Physical source offset of the timestamp-format byte.
    size_t timestampFormatSourceOffset;

    /// ID3v2.2 content type.
    Id3v22SynchronisedTextContentType contentType;

    /// Physical source offset of the content-type byte.
    size_t contentTypeSourceOffset;

    /// Decoded content descriptor.
    string descriptor;

    /// Physical descriptor bytes excluding its mandatory terminator.
    ByteSpan rawDescriptor;

    /// Ordered native synchronised text cues.
    Id3v22SynchronisedTextCue[] cues;

    /// Whether ID3v2.2 whole-tag byte unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes one ID3v2.2 synchronised-lyrics/text (`SLT`) frame.

Timestamp-format values other than `$01` and `$02` are rejected.
Content-type values above `$05` are not part of ID3v2.2 and are rejected.

The descriptor terminator and every cue-text terminator are mandatory.
A cue timestamp contains exactly four logical bytes.

The specification allows multiple SLT frames but only one with the same
language and content descriptor; that tag-level multiplicity rule is outside
this single-frame decoder.
+/
ParseResult!Id3v22SynchronisedTextFrame
decodeId3v22SynchronisedTextFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "SLT"
    )
    {
        return
            ParseResult!Id3v22SynchronisedTextFrame
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

    if (encodingResult.hasError)
    {
        return
            ParseResult!Id3v22SynchronisedTextFrame
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;

    const languageStart =
        payload.remainingRaw;

    char[3] language;

    foreach (
        i;
        0 .. 3
    )
    {
        auto languageByteResult =
            payload.takeByte();

        if (languageByteResult.hasError)
        {
            return
                ParseResult!Id3v22SynchronisedTextFrame
                    .failure(
                        languageByteResult.error
                    );
        }

        language[i] =
            cast(char)
                languageByteResult.value.value;
    }

    const languagePhysicalLength =
        languageStart.length -
        payload.remainingRaw.length;

    const rawLanguage =
        languageStart.subspan(
            0,
            languagePhysicalLength
        );

    auto timestampFormatResult =
        payload.takeByte();

    if (timestampFormatResult.hasError)
    {
        return
            ParseResult!Id3v22SynchronisedTextFrame
                .failure(
                    timestampFormatResult.error
                );
    }

    const timestampFormatByte =
        timestampFormatResult.value;

    if (
        !isValidId3v2TimestampFormat(
            timestampFormatByte.value
        )
    )
    {
        return
            ParseResult!Id3v22SynchronisedTextFrame
                .failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        timestampFormatByte.sourceOffset
                    )
                );
    }

    const timestampFormat =
        cast(Id3v2TimestampFormat)
            timestampFormatByte.value;

    auto contentTypeResult =
        payload.takeByte();

    if (contentTypeResult.hasError)
    {
        return
            ParseResult!Id3v22SynchronisedTextFrame
                .failure(
                    contentTypeResult.error
                );
    }

    const contentTypeByte =
        contentTypeResult.value;

    if (
        !isValidId3v22SynchronisedTextContentType(
            contentTypeByte.value
        )
    )
    {
        return
            ParseResult!Id3v22SynchronisedTextFrame
                .failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        contentTypeByte.sourceOffset
                    )
                );
    }

    const contentType =
        cast(Id3v22SynchronisedTextContentType)
            contentTypeByte.value;

    auto descriptorResult =
        payload.takeId3v22TerminatedTextSegment(
            encoding
        );

    if (descriptorResult.hasError)
    {
        return
            ParseResult!Id3v22SynchronisedTextFrame
                .failure(
                    descriptorResult.error
                );
    }

    const descriptorSegment =
        descriptorResult.value;

    auto descriptor =
        decodeId3v22TextSpan(
            descriptorSegment.raw,
            encoding,
            tagUnsynchronised
        );

    if (descriptor.hasError)
    {
        return
            ParseResult!Id3v22SynchronisedTextFrame
                .failure(
                    descriptor.error
                );
    }

    Id3v22SynchronisedTextCue[] cues;

    while (!payload.empty)
    {
        auto textResult =
            payload.takeId3v22TerminatedTextSegment(
                encoding
            );

        if (textResult.hasError)
        {
            return
                ParseResult!Id3v22SynchronisedTextFrame
                    .failure(
                        textResult.error
                    );
        }

        const textSegment =
            textResult.value;

        auto text =
            decodeId3v22TextSpan(
                textSegment.raw,
                encoding,
                tagUnsynchronised
            );

        if (text.hasError)
        {
            return
                ParseResult!Id3v22SynchronisedTextFrame
                    .failure(
                        text.error
                    );
        }

        const timestampStart =
            payload.remainingRaw;

        auto timestampResult =
            payload.takeU32BE();

        if (timestampResult.hasError)
        {
            return
                ParseResult!Id3v22SynchronisedTextFrame
                    .failure(
                        timestampResult.error
                    );
        }

        const timestampPhysicalLength =
            timestampStart.length -
            payload.remainingRaw.length;

        const rawTimestamp =
            timestampStart.subspan(
                0,
                timestampPhysicalLength
            );

        cues ~=
            Id3v22SynchronisedTextCue(
                Id3v2SynchronisedTextCue(
                    text.value,
                    timestampResult.value
                ),
                textSegment.raw,
                rawTimestamp
            );
    }

    return
        ParseResult!Id3v22SynchronisedTextFrame
            .success(
                Id3v22SynchronisedTextFrame(
                    frame.header.sourceOffset,
                    encoding,
                    language,
                    rawLanguage,
                    timestampFormat,
                    timestampFormatByte.sourceOffset,
                    contentType,
                    contentTypeByte.sourceOffset,
                    descriptor.value,
                    descriptorSegment.raw,
                    cues,
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


/// Latin-1 SLT decodes language, descriptor and ordered cue timestamps.
unittest
{
    const ubyte[] bytes =
        [
            'S', 'L', 'T',
            0x00, 0x00, 0x1C,

            0x00,
            'e', 'n', 'g',
            0x02,
            0x01,

            'l', 'y', 'r', 'i', 'c', 's',
            0x00,

            'H', 'e', 'l',
            0x00,
            0x00, 0x00, 0x03, 0xE8,

            'l', 'o',
            0x00,
            0x00, 0x00, 0x07, 0xD0
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
            .decodeId3v22SynchronisedTextFrame();

    assert(result.hasValue);

    const text =
        result.value;

    assert(text.sourceOffset == 100);
    assert(text.encoding == Id3v22TextEncoding.latin1);
    assert(text.language[] == "eng");
    assert(text.rawLanguage.sourceOffset == 107);
    assert(text.rawLanguage.data == ['e', 'n', 'g']);

    assert(
        text.timestampFormat ==
        Id3v2TimestampFormat.milliseconds
    );

    assert(text.timestampFormatSourceOffset == 110);

    assert(
        text.contentType ==
        Id3v22SynchronisedTextContentType.lyrics
    );

    assert(text.contentTypeSourceOffset == 111);
    assert(text.descriptor == "lyrics");
    assert(text.rawDescriptor.sourceOffset == 112);

    assert(text.cues.length == 2);

    assert(text.cues[0].cue.text == "Hel");
    assert(text.cues[0].cue.timestamp == 1000);
    assert(text.cues[0].rawText.sourceOffset == 119);
    assert(text.cues[0].rawTimestamp.sourceOffset == 123);

    assert(text.cues[1].cue.text == "lo");
    assert(text.cues[1].cue.timestamp == 2000);
    assert(text.cues[1].rawText.sourceOffset == 127);
    assert(text.cues[1].rawTimestamp.sourceOffset == 130);

    assert(!text.effectiveUnsynchronisation);
}


/// BOM-less UCS-2 descriptor and cue text use the v2.2 big-endian default.
unittest
{
    const ubyte[] bytes =
        [
            'S', 'L', 'T',
            0x00, 0x00, 0x12,

            0x01,
            'e', 'n', 'g',
            0x02,
            0x01,

            0x00, 'D',
            0x00, 0x00,

            0x00, 'A',
            0x00, 0x00,
            0x00, 0x00, 0x00, 0x2A
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
            .decodeId3v22SynchronisedTextFrame();

    assert(result.hasValue);
    assert(result.value.descriptor == "D");
    assert(result.value.cues.length == 1);
    assert(result.value.cues[0].cue.text == "A");
    assert(result.value.cues[0].cue.timestamp == 42);
}


/// Empty descriptor and empty cue text remain valid native strings.
unittest
{
    const ubyte[] bytes =
        [
            'S', 'L', 'T',
            0x00, 0x00, 0x0C,

            0x00,
            'd', 'e', 'u',
            0x01,
            0x02,

            0x00,

            0x00,
            0x00, 0x00, 0x00, 0x00
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
            .decodeId3v22SynchronisedTextFrame();

    assert(result.hasValue);
    assert(result.value.descriptor.length == 0);
    assert(result.value.cues.length == 1);
    assert(result.value.cues[0].cue.text.length == 0);
    assert(result.value.cues[0].cue.timestamp == 0);
}


/// Invalid timestamp-format discriminators are rejected.
unittest
{
    const ubyte[] bytes =
        [
            'S', 'L', 'T',
            0x00, 0x00, 0x05,

            0x00,
            'e', 'n', 'g',
            0x03
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
            .decodeId3v22SynchronisedTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 410);
}


/// Content type 06 belongs to later revisions, not ID3v2.2.
unittest
{
    const ubyte[] bytes =
        [
            'S', 'L', 'T',
            0x00, 0x00, 0x06,

            0x00,
            'e', 'n', 'g',
            0x02,
            0x06
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
            .decodeId3v22SynchronisedTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 511);
}


/// Missing descriptor termination is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'S', 'L', 'T',
            0x00, 0x00, 0x09,

            0x00,
            'e', 'n', 'g',
            0x02,
            0x01,
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
            .decodeId3v22SynchronisedTextFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
}


/// A cue without a text terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'S', 'L', 'T',
            0x00, 0x00, 0x0C,

            0x00,
            'e', 'n', 'g',
            0x02,
            0x01,
            0x00,

            'a', 'b', 'c', 'd', 'e'
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
            .decodeId3v22SynchronisedTextFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
}


/// A terminated cue without four timestamp bytes is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'S', 'L', 'T',
            0x00, 0x00, 0x0C,

            0x00,
            'e', 'n', 'g',
            0x02,
            0x01,
            0x00,

            'A', 0x00,
            0x11, 0x22, 0x33
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
            .decodeId3v22SynchronisedTextFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
}


/// SLT rejects a different native frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'L', 'T',
            0x00, 0x00, 0x01,
            0x00
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
            .decodeId3v22SynchronisedTextFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 900);
}


/// Whole-tag unsynchronisation preserves physical cue provenance.
unittest
{
    /*
     * Logical payload:
     *
     *   00
     *   eng
     *   02
     *   01
     *   00
     *   A FF E1 00
     *   00 FF E2 03
     *
     * Physical payload inserts one zero after each FF.
     */
    const ubyte[] bytes =
        [
            'S', 'L', 'T',
            0x00, 0x00, 0x0F,

            0x00,
            'e', 'n', 'g',
            0x02,
            0x01,
            0x00,

            'A',
            0xFF, 0x00,
            0xE1,
            0x00,

            0x00,
            0xFF, 0x00,
            0xE2,
            0x03
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1000
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 15);
    assert(frame.value.data.length == 17);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22SynchronisedTextFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.effectiveUnsynchronisation);
    assert(result.value.cues.length == 1);

    const cue =
        result.value.cues[0];

    assert(cue.cue.text == "A\u00FF\u00E1");
    assert(cue.cue.timestamp == 0x00_FF_E2_03);

    assert(
        cue.rawText.data ==
        [
            'A',
            0xFF, 0x00,
            0xE1
        ]
    );

    assert(
        cue.rawTimestamp.data ==
        [
            0x00,
            0xFF, 0x00,
            0xE2,
            0x03
        ]
    );
}
