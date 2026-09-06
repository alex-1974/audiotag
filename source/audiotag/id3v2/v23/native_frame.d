/++
Unified native representation and semantic dispatch for one ID3v2.3
frame.

The structural frame envelope is always retained. Known semantic frame
families are dispatched to their existing codecs while unknown but
structurally valid frames remain represented explicitly.

Codec outcomes are preserved rather than flattened. Consequently,
states such as `requiresDecompression` and `requiresDecryption` remain
successful native outcomes and are not confused with malformed input.

This module does not perform canonical metadata mapping.
+/
module audiotag.id3v2.v23.native_frame;

import std.sumtype :
    SumType,
    match;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v23.attached_picture :
    Id3v23AttachedPictureOutcome,
    decodeId3v23AttachedPictureFrame;

import audiotag.id3v2.v23.comment :
    Id3v23CommentOutcome,
    decodeId3v23CommentFrame;

import audiotag.id3v2.v23.frame :
    Id3v23FrameEnvelope;

import audiotag.id3v2.v23.lyrics_text :
    Id3v23LyricsTextOutcome,
    decodeId3v23LyricsTextFrame;

import audiotag.id3v2.v23.private_frame :
    Id3v23PrivateOutcome,
    decodeId3v23PrivateFrame;

import audiotag.id3v2.v23.text_information :
    Id3v23TextInformationOutcome,
    decodeId3v23TextInformationFrame;

import audiotag.id3v2.v23.unique_file_identifier :
    Id3v23UniqueFileIdentifierOutcome,
    decodeId3v23UniqueFileIdentifierFrame;

import audiotag.id3v2.v23.url_link :
    Id3v23UrlLinkOutcome,
    decodeId3v23UrlLinkFrame;

import audiotag.id3v2.v23.user_text :
    Id3v23UserTextOutcome,
    decodeId3v23UserTextFrame;

import audiotag.id3v2.v23.user_url :
    Id3v23UserUrlOutcome,
    decodeId3v23UserUrlFrame;


/++
Marker for a structurally valid ID3v2.3 frame for which no semantic
codec is currently selected.

The complete frame envelope remains available in the surrounding
`Id3v23NativeFrame`, including its native identifier, flags and raw
frame-data span.
+/
struct Id3v23UnknownFrame
{
}


/++
Native semantic content associated with one ID3v2.3 frame.

Known alternatives retain the complete outcome returned by their
existing codec. Transformation-pending availability states therefore
remain explicit.

`Id3v23UnknownFrame` represents structurally valid content for which
this dispatcher has no semantic codec.
+/
alias Id3v23NativeFrameContent =
    SumType!(
        Id3v23TextInformationOutcome,
        Id3v23UserTextOutcome,
        Id3v23UrlLinkOutcome,
        Id3v23UserUrlOutcome,
        Id3v23CommentOutcome,
        Id3v23LyricsTextOutcome,
        Id3v23AttachedPictureOutcome,
        Id3v23PrivateOutcome,
        Id3v23UniqueFileIdentifierOutcome,
        Id3v23UnknownFrame
    );


/++
One provenance-preserving native ID3v2.3 frame.

`envelope` retains the complete bounded structural representation.

`content` contains either the semantic codec outcome or an explicit
unknown-frame marker.
+/
struct Id3v23NativeFrame
{
    /// Original bounded structural frame.
    Id3v23FrameEnvelope envelope;

    /// Decoded/pending semantic outcome or unknown marker.
    Id3v23NativeFrameContent content;


    /++
    Returns the absolute source offset of the frame header.
    +/
    @property
    size_t sourceOffset() const
        @safe pure nothrow @nogc
    {
        return
            envelope.header.sourceOffset;
    }


    /++
    Returns the absolute source offset immediately following the
    physical frame.
    +/
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return
            envelope.endOffset;
    }


    /++
    Returns the complete physical frame length including its ten-byte
    frame header.

    Under ID3v2.3 whole-tag unsynchronisation the physical frame-data
    span may be longer than the logical frame size stored in the header.
    +/
    @property
    size_t sourceLength() const
        @safe pure nothrow @nogc
    {
        assert(
            endOffset >=
            sourceOffset
        );

        return
            endOffset -
            sourceOffset;
    }
}


/++
Dispatches one structurally parsed ID3v2.3 frame to its semantic codec.

Routing rules:

- `TXXX` uses the user-defined text codec;
- other `T***` frames use the ordinary text-information codec;
- `WXXX` uses the user-defined URL codec;
- other `W***` frames use the ordinary URL-link codec;
- `COMM`, `USLT`, `APIC`, `PRIV` and `UFID` use their dedicated codecs;
- all other structurally valid frame identifiers remain unknown.

The specific `TXXX` and `WXXX` checks must precede the generic family
checks.

Params:
    frame = Complete bounded ID3v2.3 frame envelope.
    tagUnsynchronised = Whether ID3v2.3 whole-tag unsynchronisation
        applies.

Returns:
    A native frame containing the semantic codec outcome or an
    unknown-frame marker. Semantic codec failures are propagated as
    their structured `ParseError`.

Notes:
    Compression or encryption that requires a future transformation
    remains a successful codec outcome. It is not converted into a
    parse failure.
+/
ParseResult!Id3v23NativeFrame
decodeId3v23NativeFrame(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    /*
     * Exact user-defined text must precede generic T*** dispatch.
     */
    if (
        idEquals(
            frame.header.id,
            "TXXX"
        )
    )
    {
        return
            wrapOutcome(
                frame,
                frame.decodeId3v23UserTextFrame(
                    tagUnsynchronised
                )
            );
    }


    /*
     * All remaining structurally valid T*** identifiers use the
     * ordinary text-information codec.
     */
    if (
        frame.header.id[0] ==
        'T'
    )
    {
        return
            wrapOutcome(
                frame,
                frame.decodeId3v23TextInformationFrame(
                    tagUnsynchronised
                )
            );
    }


    /*
     * Exact user-defined URL must precede generic W*** dispatch.
     */
    if (
        idEquals(
            frame.header.id,
            "WXXX"
        )
    )
    {
        return
            wrapOutcome(
                frame,
                frame.decodeId3v23UserUrlFrame(
                    tagUnsynchronised
                )
            );
    }


    /*
     * All remaining structurally valid W*** identifiers use the
     * ordinary URL-link codec.
     */
    if (
        frame.header.id[0] ==
        'W'
    )
    {
        return
            wrapOutcome(
                frame,
                frame.decodeId3v23UrlLinkFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "COMM"
        )
    )
    {
        return
            wrapOutcome(
                frame,
                frame.decodeId3v23CommentFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "USLT"
        )
    )
    {
        return
            wrapOutcome(
                frame,
                frame.decodeId3v23LyricsTextFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "APIC"
        )
    )
    {
        return
            wrapOutcome(
                frame,
                frame.decodeId3v23AttachedPictureFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "PRIV"
        )
    )
    {
        return
            wrapOutcome(
                frame,
                frame.decodeId3v23PrivateFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "UFID"
        )
    )
    {
        return
            wrapOutcome(
                frame,
                frame.decodeId3v23UniqueFileIdentifierFrame(
                    tagUnsynchronised
                )
            );
    }


    /*
     * Unknown semantic content is not malformed. The complete
     * structural envelope remains attached to this native node.
     */
    Id3v23NativeFrameContent content =
        Id3v23UnknownFrame();


    return
        ParseResult!Id3v23NativeFrame
            .success(
                Id3v23NativeFrame(
                    frame,
                    content
                )
            );
}


/++
Wraps one successful semantic codec outcome while preserving failures.

Malformed semantic content stays a parsing failure. Successful outcomes,
including transformation-pending outcomes, are stored unchanged.
+/
private ParseResult!Id3v23NativeFrame
wrapOutcome(T)(
    Id3v23FrameEnvelope frame,
    ParseResult!T outcome
)
    @safe
{
    if (
        outcome.hasError
    )
    {
        return
            ParseResult!Id3v23NativeFrame
                .failure(
                    outcome.error
                );
    }


    Id3v23NativeFrameContent content =
        outcome.value;


    return
        ParseResult!Id3v23NativeFrame
            .success(
                Id3v23NativeFrame(
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


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.data_cursor :
        Id3v23DataCursor;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.text_information :
        Id3v23TextInformationAvailability;
}


version (unittest)
{
    /++
    Parses one synthetic non-unsynchronised frame envelope for dispatcher
    tests.
    +/
    private Id3v23FrameEnvelope testEnvelope(
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
            cursor.parseId3v23FrameEnvelope();

        assert(result.hasValue);
        assert(cursor.empty);

        return
            result.value;
    }
}


/// Ordinary T*** frames dispatch to the text-information codec.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            /*
             * Latin-1 "Title".
             */
            0x00,
            'T', 'i', 't', 'l', 'e'
        ];

    auto result =
        decodeId3v23NativeFrame(
            testEnvelope(
                bytes,
                500
            )
        );

    assert(result.hasValue);

    auto native =
        result.value;

    assert(
        native.sourceOffset ==
        500
    );

    assert(
        native.endOffset ==
        516
    );

    assert(
        native.sourceLength ==
        16
    );

    const isTextInformation =
        native.content.match!(
            (Id3v23TextInformationOutcome outcome) =>
                outcome.availability ==
                Id3v23TextInformationAvailability.decoded,

            _ =>
                false
        );

    assert(isTextInformation);
}


/// TXXX dispatches before the generic T*** family.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0B,
            0x00, 0x00,

            0x00,

            'k', 'i', 'n', 'd',
            0x00,

            'v', 'a', 'l', 'u', 'e'
        ];

    auto result =
        decodeId3v23NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    auto native =
        result.value;

    const isUserText =
        native.content.match!(
            (Id3v23UserTextOutcome outcome) =>
                true,

            _ =>
                false
        );

    assert(isUserText);
}


/// Ordinary W*** frames dispatch to the URL-link codec.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'C', 'O', 'M',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

            'h', 't', 't', 'p', ':', '/',
            '/', 'x'
        ];

    auto result =
        decodeId3v23NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    auto native =
        result.value;

    const isUrlLink =
        native.content.match!(
            (Id3v23UrlLinkOutcome outcome) =>
                true,

            _ =>
                false
        );

    assert(isUrlLink);
}


/// WXXX dispatches before the generic W*** family.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,

            'd',
            0x00,

            'x'
        ];

    auto result =
        decodeId3v23NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    auto native =
        result.value;

    const isUserUrl =
        native.content.match!(
            (Id3v23UserUrlOutcome outcome) =>
                true,

            _ =>
                false
        );

    assert(isUserUrl);
}


/// COMM dispatches to the dedicated comment codec.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x00,
            'e', 'n', 'g',
            0x00,
            'A'
        ];

    auto result =
        decodeId3v23NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isComment =
        result.value.content.match!(
            (Id3v23CommentOutcome outcome) =>
                true,

            _ =>
                false
        );

    assert(isComment);
}


/// USLT dispatches to the dedicated lyrics/text codec.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x00,
            'e', 'n', 'g',
            0x00,
            'A'
        ];

    auto result =
        decodeId3v23NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isLyrics =
        result.value.content.match!(
            (Id3v23LyricsTextOutcome outcome) =>
                true,

            _ =>
                false
        );

    assert(isLyrics);
}


/// APIC dispatches to the dedicated attached-picture codec.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x00,

            'x',
            0x00,

            0x03,

            0x00,

            0xAA
        ];

    auto result =
        decodeId3v23NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isPicture =
        result.value.content.match!(
            (Id3v23AttachedPictureOutcome outcome) =>
                true,

            _ =>
                false
        );

    assert(isPicture);
}


/// PRIV dispatches to the dedicated private-frame codec.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            'x',
            0x00,
            0xAA
        ];

    auto result =
        decodeId3v23NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isPrivate =
        result.value.content.match!(
            (Id3v23PrivateOutcome outcome) =>
                true,

            _ =>
                false
        );

    assert(isPrivate);
}


/// UFID dispatches to the dedicated unique-file-identifier codec.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            'x',
            0x00,
            0xAA
        ];

    auto result =
        decodeId3v23NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isUniqueFileIdentifier =
        result.value.content.match!(
            (Id3v23UniqueFileIdentifierOutcome outcome) =>
                true,

            _ =>
                false
        );

    assert(isUniqueFileIdentifier);
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
        decodeId3v23NativeFrame(
            testEnvelope(
                bytes,
                2000
            )
        );

    assert(result.hasValue);

    auto native =
        result.value;

    const isUnknown =
        native.content.match!(
            (Id3v23UnknownFrame unknown) =>
                true,

            _ =>
                false
        );

    assert(isUnknown);

    assert(
        native.sourceOffset ==
        2000
    );

    assert(
        native.sourceLength ==
        13
    );

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

            /*
             * UTF-8 marker is invalid in ID3v2.3.
             */
            0x03
        ];

    auto result =
        decodeId3v23NativeFrame(
            testEnvelope(
                bytes,
                2100
            )
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(
        result.error.offset ==
        2110
    );
}


/// Compression requirements remain successful native outcomes.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',

            /*
             * Four-byte decompressed-size addition plus opaque payload.
             */
            0x00, 0x00, 0x00, 0x05,

            0x00, 0x80,

            0x00, 0x00, 0x00, 0x01,
            0xAA
        ];

    auto result =
        decodeId3v23NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    auto native =
        result.value;

    const pending =
        native.content.match!(
            (Id3v23TextInformationOutcome outcome) =>
                outcome.availability ==
                Id3v23TextInformationAvailability
                    .requiresDecompression,

            _ =>
                false
        );

    assert(pending);
}


/// Whole-tag unsynchronisation is forwarded to the selected codec.
unittest
{
    /*
     * Logical PRIV frame data:
     *
     *   x 00 FF E0
     *
     * Header size therefore remains four logical bytes.
     *
     * Physical data:
     *
     *   x 00 FF 00 E0
     */
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            'x',
            0x00,

            0xFF, 0x00,
            0xE0
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                3000
            ),
            true
        );

    auto envelope =
        cursor.parseId3v23FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    auto result =
        decodeId3v23NativeFrame(
            envelope.value,
            true
        );

    assert(result.hasValue);

    auto native =
        result.value;

    /*
     * Ten physical header bytes plus five physical frame-data bytes.
     */
    assert(
        native.sourceLength ==
        15
    );

    const preserved =
        native.content.match!(
            (Id3v23PrivateOutcome outcome)
            {
                return
                    outcome.decoded &&
                    outcome.privateFrame
                        .effectiveUnsynchronisation &&
                    outcome.privateFrame
                        .rawPrivateData.data ==
                        [
                            0xFF, 0x00,
                            0xE0
                        ];
            },

            _ =>
                false
        );

    assert(preserved);
}
