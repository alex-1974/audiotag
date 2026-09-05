/++
Unified native representation and semantic dispatch for one ID3v2.4
frame.

The structural frame envelope is always retained. Known semantic frame
families are dispatched to their existing codecs while unknown but
structurally valid frames remain represented explicitly.

Codec outcomes are preserved rather than flattened. Consequently,
states such as `requiresDecompression` and `requiresDecryption` remain
successful native outcomes and are not confused with malformed input.

This module does not perform canonical metadata mapping.
+/
module audiotag.id3v2.v24.native_frame;

import std.sumtype :
    SumType,
    match;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v24.attached_picture :
    Id3v24AttachedPictureOutcome,
    decodeId3v24AttachedPictureFrame;

import audiotag.id3v2.v24.comment :
    Id3v24CommentOutcome,
    decodeId3v24CommentFrame;

import audiotag.id3v2.v24.frame :
    Id3v24FrameEnvelope;

import audiotag.id3v2.v24.lyrics_text :
    Id3v24LyricsTextOutcome,
    decodeId3v24LyricsTextFrame;

import audiotag.id3v2.v24.private_frame :
    Id3v24PrivateOutcome,
    decodeId3v24PrivateFrame;

import audiotag.id3v2.v24.text_information :
    Id3v24TextInformationOutcome,
    decodeId3v24TextInformationFrame;

import audiotag.id3v2.v24.unique_file_identifier :
    Id3v24UniqueFileIdentifierOutcome,
    decodeId3v24UniqueFileIdentifierFrame;

import audiotag.id3v2.v24.url_link :
    Id3v24UrlLinkOutcome,
    decodeId3v24UrlLinkFrame;

import audiotag.id3v2.v24.user_text :
    Id3v24UserTextOutcome,
    decodeId3v24UserTextFrame;

import audiotag.id3v2.v24.user_url :
    Id3v24UserUrlOutcome,
    decodeId3v24UserUrlFrame;


/++
Marker for a structurally valid frame for which no semantic codec is
currently selected.

The complete frame envelope remains available in the surrounding
`Id3v24NativeFrame`, including its native identifier, flags and raw
frame-data span.
+/
struct Id3v24UnknownFrame
{
}


/++
Native semantic content associated with one ID3v2.4 frame.

Known alternatives retain the complete outcome returned by their
existing codec. This deliberately preserves transformation-pending
availability states rather than reducing them to errors.

`Id3v24UnknownFrame` represents structurally valid content for which
this dispatcher has no semantic codec.
+/
alias Id3v24NativeFrameContent =
    SumType!(
        Id3v24TextInformationOutcome,
        Id3v24UserTextOutcome,
        Id3v24UrlLinkOutcome,
        Id3v24UserUrlOutcome,
        Id3v24CommentOutcome,
        Id3v24LyricsTextOutcome,
        Id3v24AttachedPictureOutcome,
        Id3v24PrivateOutcome,
        Id3v24UniqueFileIdentifierOutcome,
        Id3v24UnknownFrame
    );


/++
One provenance-preserving native ID3v2.4 frame.

`envelope` retains the bounded structural representation and therefore
the complete raw frame-data span.

`content` contains either the semantic codec outcome or an explicit
unknown-frame marker.
+/
struct Id3v24NativeFrame
{
    /// Original bounded structural frame.
    Id3v24FrameEnvelope envelope;

    /// Decoded/pending semantic outcome or unknown marker.
    Id3v24NativeFrameContent content;

    /++
    Returns the absolute source offset of the frame header.
    +/
    @property
    size_t sourceOffset() const
        @safe pure nothrow @nogc
    {
        return envelope.header.sourceOffset;
    }

    /++
    Returns the absolute source offset immediately following the frame.
    +/
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return envelope.endOffset;
    }

    /++
    Returns the complete physical frame length including its ten-byte
    header.

    The envelope parser guarantees that the data region follows its
    header in the same bounded source.
    +/
    @property
    size_t sourceLength() const
        @safe pure nothrow @nogc
    {
        assert(endOffset >= sourceOffset);

        return endOffset - sourceOffset;
    }
}


/++
Dispatches one structurally parsed ID3v2.4 frame to its semantic codec.

Routing rules:

- `TXXX` uses the user-defined text codec;
- other `T***` frames use the ordinary text-information codec;
- `WXXX` uses the user-defined URL codec;
- other `W***` frames use the ordinary URL-link codec;
- `COMM`, `USLT`, `APIC`, `PRIV` and `UFID` use their dedicated codecs;
- all other structurally valid frame identifiers remain unknown.

Params:
    frame = Complete bounded ID3v2.4 frame envelope.
    tagUnsynchronised = Whether tag-level unsynchronisation applies.

Returns:
    A native frame containing the semantic codec outcome or an
    unknown-frame marker. Semantic codec failures are propagated as
    their structured `ParseError`.

Notes:
    Compression or encryption that requires a future transformation
    remains a successful codec outcome. It is not converted into a
    parse failure.
+/
ParseResult!Id3v24NativeFrame decodeId3v24NativeFrame(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (idEquals(frame.header.id, "TXXX"))
    {
        return wrapOutcome(
            frame,
            frame.decodeId3v24UserTextFrame(
                tagUnsynchronised
            )
        );
    }

    if (frame.header.id[0] == 'T')
    {
        return wrapOutcome(
            frame,
            frame.decodeId3v24TextInformationFrame(
                tagUnsynchronised
            )
        );
    }

    if (idEquals(frame.header.id, "WXXX"))
    {
        return wrapOutcome(
            frame,
            frame.decodeId3v24UserUrlFrame(
                tagUnsynchronised
            )
        );
    }

    if (frame.header.id[0] == 'W')
    {
        return wrapOutcome(
            frame,
            frame.decodeId3v24UrlLinkFrame(
                tagUnsynchronised
            )
        );
    }

    if (idEquals(frame.header.id, "COMM"))
    {
        return wrapOutcome(
            frame,
            frame.decodeId3v24CommentFrame(
                tagUnsynchronised
            )
        );
    }

    if (idEquals(frame.header.id, "USLT"))
    {
        return wrapOutcome(
            frame,
            frame.decodeId3v24LyricsTextFrame(
                tagUnsynchronised
            )
        );
    }

    if (idEquals(frame.header.id, "APIC"))
    {
        return wrapOutcome(
            frame,
            frame.decodeId3v24AttachedPictureFrame(
                tagUnsynchronised
            )
        );
    }

    if (idEquals(frame.header.id, "PRIV"))
    {
        return wrapOutcome(
            frame,
            frame.decodeId3v24PrivateFrame(
                tagUnsynchronised
            )
        );
    }

    if (idEquals(frame.header.id, "UFID"))
    {
        return wrapOutcome(
            frame,
            frame.decodeId3v24UniqueFileIdentifierFrame(
                tagUnsynchronised
            )
        );
    }

    Id3v24NativeFrameContent content =
        Id3v24UnknownFrame();

    return ParseResult!Id3v24NativeFrame.success(
        Id3v24NativeFrame(
            frame,
            content
        )
    );
}


/++
Wraps one successful semantic codec outcome while preserving failures.
+/
private ParseResult!Id3v24NativeFrame wrapOutcome(T)(
    Id3v24FrameEnvelope frame,
    ParseResult!T outcome
)
    @safe
{
    if (outcome.hasError)
    {
        return ParseResult!Id3v24NativeFrame.failure(
            outcome.error
        );
    }

    Id3v24NativeFrameContent content =
        outcome.value;

    return ParseResult!Id3v24NativeFrame.success(
        Id3v24NativeFrame(
            frame,
            content
        )
    );
}


/++
Compares one fixed four-character frame identifier without allocation.
+/
private bool idEquals(
    const ref char[4] id,
    string expected
)
    @safe pure nothrow @nogc
{
    return
        expected.length == 4 &&
        id[0] == expected[0] &&
        id[1] == expected[1] &&
        id[2] == expected[2] &&
        id[3] == expected[3];
}


import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.error :
    ParseErrorCode;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;

import audiotag.id3v2.v24.text_information :
    Id3v24TextInformationAvailability;


/++
Parses one synthetic frame envelope for dispatcher tests.
+/
private Id3v24FrameEnvelope testEnvelope(
    const(ubyte)[] bytes,
    size_t sourceOffset = 100
)
    @safe
{
    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                sourceOffset
            )
        );

    auto result =
        cursor.parseId3v24FrameEnvelope();

    assert(result.hasValue);
    assert(cursor.empty);

    return result.value;
}


/// Ordinary T*** frames dispatch to the text-information codec.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x03,
            'T', 'i', 't', 'l', 'e'
        ];

    auto result =
        decodeId3v24NativeFrame(
            testEnvelope(
                bytes,
                500
            )
        );

    assert(result.hasValue);

    auto native =
        result.value;

    assert(native.sourceOffset == 500);
    assert(native.endOffset == 516);
    assert(native.sourceLength == 16);

    const isTextInformation =
        native.content.match!(
            (Id3v24TextInformationOutcome outcome) =>
                outcome.availability ==
                Id3v24TextInformationAvailability.decoded,
            _ => false
        );

    assert(isTextInformation);
}


/// TXXX is routed to the user-defined text codec before generic T***.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0B,
            0x00, 0x00,

            0x03,
            'k', 'i', 'n', 'd',
            0x00,
            'v', 'a', 'l', 'u', 'e'
        ];

    auto result =
        decodeId3v24NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    auto native =
        result.value;

    const isUserText =
        native.content.match!(
            (Id3v24UserTextOutcome outcome) =>
                true,
            _ => false
        );

    assert(isUserText);
}


/// Unknown but structurally valid frames remain successful native nodes.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O', 'B',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0x11, 0x22, 0x33
        ];

    auto result =
        decodeId3v24NativeFrame(
            testEnvelope(
                bytes,
                1000
            )
        );

    assert(result.hasValue);

    auto native =
        result.value;

    const isUnknown =
        native.content.match!(
            (Id3v24UnknownFrame unknown) =>
                true,
            _ => false
        );

    assert(isUnknown);

    assert(native.sourceOffset == 1000);
    assert(native.sourceLength == 13);

    assert(
        native.envelope.header.id[] ==
        "GEOB"
    );

    assert(
        native.envelope.data.data ==
        [0x11, 0x22, 0x33]
    );
}


/// Malformed semantic content from a known codec remains a parse error.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            // Invalid ID3v2.4 text-encoding marker.
            0x04
        ];

    auto result =
        decodeId3v24NativeFrame(
            testEnvelope(
                bytes,
                2000
            )
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 2010);
}


/// Compression requirements remain successful transformation-pending outcomes.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x09,

            // Data-length indicator for one logical byte.
            0x00, 0x00, 0x00, 0x01,

            // Opaque compressed payload.
            0xAA
        ];

    auto result =
        decodeId3v24NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    auto native =
        result.value;

    const pending =
        native.content.match!(
            (Id3v24TextInformationOutcome outcome) =>
                outcome.availability ==
                Id3v24TextInformationAvailability
                    .requiresDecompression,
            _ => false
        );

    assert(pending);
}
