/++
Unified native representation and semantic dispatch for one ID3v2.2 frame.

The complete structural frame envelope is always retained. Known semantic
frame families are dispatched to their existing native codecs while unknown
but structurally valid frames remain represented explicitly.

ID3v2.2 has no per-frame compression/encryption flags. Consequently the
semantic alternatives stored here are the decoded native frame structs
themselves rather than transformation-availability outcomes.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.native_frame;

import std.sumtype :
    SumType,
    match;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v22.attached_picture :
    Id3v22AttachedPictureFrame,
    decodeId3v22AttachedPictureFrame;

import audiotag.id3v2.v22.comment :
    Id3v22CommentFrame,
    decodeId3v22CommentFrame;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

import audiotag.id3v2.v22.lyrics_text :
    Id3v22LyricsTextFrame,
    decodeId3v22LyricsTextFrame;

import audiotag.id3v2.v22.text_information :
    Id3v22TextInformationFrame,
    decodeId3v22TextInformationFrame;

import audiotag.id3v2.v22.unique_file_identifier :
    Id3v22UniqueFileIdentifierFrame,
    decodeId3v22UniqueFileIdentifierFrame;

import audiotag.id3v2.v22.url_link :
    Id3v22UrlLinkFrame,
    decodeId3v22UrlLinkFrame;

import audiotag.id3v2.v22.user_text :
    Id3v22UserTextFrame,
    decodeId3v22UserTextFrame;

import audiotag.id3v2.v22.user_url :
    Id3v22UserUrlFrame,
    decodeId3v22UserUrlFrame;


/++
Marker for a structurally valid ID3v2.2 frame for which no semantic codec is
currently selected.

The complete frame envelope remains available in the surrounding
`Id3v22NativeFrame`, including its native identifier and physical frame-data
span.
+/
struct Id3v22UnknownFrame
{
}


/++
Native semantic content associated with one ID3v2.2 frame.

Known alternatives contain the decoded native result returned by the
corresponding semantic codec.

`Id3v22UnknownFrame` represents structurally valid content for which this
dispatcher has no semantic codec.
+/
alias Id3v22NativeFrameContent =
    SumType!(
        Id3v22TextInformationFrame,
        Id3v22UserTextFrame,
        Id3v22UrlLinkFrame,
        Id3v22UserUrlFrame,
        Id3v22CommentFrame,
        Id3v22LyricsTextFrame,
        Id3v22AttachedPictureFrame,
        Id3v22UniqueFileIdentifierFrame,
        Id3v22UnknownFrame
    );


/++
One provenance-preserving native ID3v2.2 frame.

`envelope` retains the complete bounded structural representation.

`content` contains either decoded semantic content or an explicit unknown-frame
marker.
+/
struct Id3v22NativeFrame
{
    /// Original bounded structural frame.
    Id3v22FrameEnvelope envelope;

    /// Decoded semantic content or unknown marker.
    Id3v22NativeFrameContent content;


    /// Absolute physical source offset of the frame header.
    @property
    size_t sourceOffset() const
        @safe pure nothrow @nogc
    {
        return
            envelope.header.sourceOffset;
    }


    /// Absolute physical source offset immediately following the frame.
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return
            envelope.endOffset;
    }


    /++
    Complete physical frame length including the six-byte ID3v2.2 frame
    header.

    Under whole-tag unsynchronisation the physical frame-data span may be
    longer than the logical frame size stored in the header.
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
Dispatches one structurally parsed ID3v2.2 frame to its semantic codec.

Routing rules:

- `TXX` uses the user-defined text codec;
- other `T**` frames use the ordinary text-information codec;
- `WXX` uses the user-defined URL codec;
- other `W**` frames use the ordinary URL-link codec;
- `COM`, `ULT`, `PIC` and `UFI` use their dedicated codecs;
- all other structurally valid frame identifiers remain unknown.

The specific `TXX` and `WXX` checks must precede the generic family checks.

Params:
    frame = Complete bounded ID3v2.2 frame envelope.
    tagUnsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    A native frame containing decoded semantic content or an unknown-frame
    marker. Semantic codec failures are propagated as their structured
    `ParseError`.
+/
ParseResult!Id3v22NativeFrame
decodeId3v22NativeFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    /*
     * Exact user-defined text must precede generic T** dispatch.
     */
    if (
        idEquals(
            frame.header.id,
            "TXX"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22UserTextFrame(
                    tagUnsynchronised
                )
            );
    }


    /*
     * Every remaining structurally valid T** identifier is a native
     * text-information frame.
     */
    if (
        frame.header.id[0] ==
        'T'
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22TextInformationFrame(
                    tagUnsynchronised
                )
            );
    }


    /*
     * Exact user-defined URL must precede generic W** dispatch.
     */
    if (
        idEquals(
            frame.header.id,
            "WXX"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22UserUrlFrame(
                    tagUnsynchronised
                )
            );
    }


    /*
     * Every remaining structurally valid W** identifier is handled by the
     * ordinary URL-link codec, including experimental/vendor identifiers.
     */
    if (
        frame.header.id[0] ==
        'W'
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22UrlLinkFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "COM"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22CommentFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "ULT"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22LyricsTextFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "PIC"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22AttachedPictureFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "UFI"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22UniqueFileIdentifierFrame(
                    tagUnsynchronised
                )
            );
    }


    /*
     * Unknown semantic content is not malformed. The complete structural
     * envelope remains attached to this native node.
     */
    Id3v22NativeFrameContent content =
        Id3v22UnknownFrame();


    return
        ParseResult!Id3v22NativeFrame
            .success(
                Id3v22NativeFrame(
                    frame,
                    content
                )
            );
}


/++
Wraps one successful semantic codec result while preserving failures.
+/
private ParseResult!Id3v22NativeFrame
wrapDecoded(T)(
    Id3v22FrameEnvelope frame,
    ParseResult!T decoded
)
    @safe
{
    if (
        decoded.hasError
    )
    {
        return
            ParseResult!Id3v22NativeFrame
                .failure(
                    decoded.error
                );
    }


    Id3v22NativeFrameContent content =
        decoded.value;


    return
        ParseResult!Id3v22NativeFrame
            .success(
                Id3v22NativeFrame(
                    frame,
                    content
                )
            );
}


/++
Compares one fixed three-character frame identifier without allocation.
+/
private bool
idEquals(
    const ref char[3] id,
    string expected
)
    @safe pure nothrow @nogc
{
    return
        expected.length == 3 &&
        id[0] == expected[0] &&
        id[1] == expected[1] &&
        id[2] == expected[2];
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.data_cursor :
        Id3v22DataCursor;

    import audiotag.id3v2.v22.frame :
        parseId3v22FrameEnvelope;
}


version (unittest)
{
    /++
    Parses one synthetic non-unsynchronised frame envelope for dispatcher
    tests.
    +/
    private Id3v22FrameEnvelope
    testEnvelope(
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
            cursor.parseId3v22FrameEnvelope();

        assert(result.hasValue);
        assert(cursor.empty);

        return
            result.value;
    }
}


/// Ordinary T** frames dispatch to the text-information codec.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x06,

            0x00,
            'T', 'i', 't', 'l', 'e'
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                500
            )
        );

    assert(result.hasValue);

    auto native =
        result.value;

    assert(native.sourceOffset == 500);
    assert(native.endOffset == 512);
    assert(native.sourceLength == 12);

    const isTextInformation =
        native.content.match!(
            (Id3v22TextInformationFrame text) =>
                text.value == "Title",

            _ =>
                false
        );

    assert(isTextInformation);
}


/// TXX dispatches before the generic T** family.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',
            0x00, 0x00, 0x0B,

            0x00,

            'k', 'i', 'n', 'd',
            0x00,

            'v', 'a', 'l', 'u', 'e'
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isUserText =
        result.value.content.match!(
            (Id3v22UserTextFrame text) =>
                text.description == "kind" &&
                text.value == "value",

            _ =>
                false
        );

    assert(isUserText);
}


/// Ordinary W** frames dispatch to the URL-link codec.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'C', 'M',
            0x00, 0x00, 0x08,

            'h', 't', 't', 'p', ':', '/',
            '/', 'x'
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isUrlLink =
        result.value.content.match!(
            (Id3v22UrlLinkFrame link) =>
                link.id[] == "WCM" &&
                link.url == "http://x",

            _ =>
                false
        );

    assert(isUrlLink);
}


/// Experimental/vendor W** frames retain their native identifier.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'Z', '9',
            0x00, 0x00, 0x03,

            'u', 'r', 'l'
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const preserved =
        result.value.content.match!(
            (Id3v22UrlLinkFrame link) =>
                link.id[] == "WZ9" &&
                link.url == "url",

            _ =>
                false
        );

    assert(preserved);
}


/// WXX dispatches before the generic W** family.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X',
            0x00, 0x00, 0x04,

            0x00,

            'd',
            0x00,

            'x'
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isUserUrl =
        result.value.content.match!(
            (Id3v22UserUrlFrame link) =>
                link.description == "d" &&
                link.url == "x",

            _ =>
                false
        );

    assert(isUserUrl);
}


/// COM dispatches to the dedicated comment codec.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',
            0x00, 0x00, 0x06,

            0x00,
            'e', 'n', 'g',
            0x00,
            'A'
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isComment =
        result.value.content.match!(
            (Id3v22CommentFrame comment) =>
                comment.language[] == "eng" &&
                comment.text == "A",

            _ =>
                false
        );

    assert(isComment);
}


/// ULT dispatches to the dedicated lyrics/text codec.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'L', 'T',
            0x00, 0x00, 0x06,

            0x00,
            'e', 'n', 'g',
            0x00,
            'A'
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isLyrics =
        result.value.content.match!(
            (Id3v22LyricsTextFrame lyrics) =>
                lyrics.language[] == "eng" &&
                lyrics.text == "A",

            _ =>
                false
        );

    assert(isLyrics);
}


/// PIC dispatches to the dedicated attached-picture codec.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',
            0x00, 0x00, 0x07,

            0x00,
            'J', 'P', 'G',
            0x03,
            0x00,
            0xAA
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isPicture =
        result.value.content.match!(
            (Id3v22AttachedPictureFrame picture) =>
                picture.imageFormat[] == "JPG" &&
                picture.description.length == 0 &&
                picture.rawPictureData.data == [0xAA],

            _ =>
                false
        );

    assert(isPicture);
}


/// UFI dispatches to the dedicated unique-file-identifier codec.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x03,

            'x',
            0x00,
            0xAA
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(bytes)
        );

    assert(result.hasValue);

    const isUniqueFileIdentifier =
        result.value.content.match!(
            (Id3v22UniqueFileIdentifierFrame identifier) =>
                identifier.ownerIdentifier == "x" &&
                identifier.logicalIdentifierLength == 1,

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
            'G', 'E', 'O',
            0x00, 0x00, 0x03,

            0x11, 0x22, 0x33
        ];

    auto result =
        decodeId3v22NativeFrame(
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
            (Id3v22UnknownFrame unknown) =>
                true,

            _ =>
                false
        );

    assert(isUnknown);

    assert(native.sourceOffset == 2000);
    assert(native.sourceLength == 9);
    assert(native.envelope.header.id[] == "GEO");

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
            'T', 'T', '2',
            0x00, 0x00, 0x01,

            /*
             * Only 00 and 01 are valid v2.2 text-encoding markers.
             */
            0x02
        ];

    auto result =
        decodeId3v22NativeFrame(
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

    assert(result.error.offset == 2106);
}


/// Whole-tag unsynchronisation is forwarded to the selected codec.
unittest
{
    /*
     * Logical UFI frame data:
     *
     *   x 00 FF E0
     *
     * Header size therefore remains four logical bytes.
     *
     * Physical frame data:
     *
     *   x 00 FF 00 E0
     */
    const ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x04,

            'x',
            0x00,

            0xFF, 0x00,
            0xE0
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                3000
            ),
            true
        );

    auto envelope =
        cursor.parseId3v22FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    auto result =
        decodeId3v22NativeFrame(
            envelope.value,
            true
        );

    assert(result.hasValue);

    auto native =
        result.value;

    /*
     * Six physical header bytes plus five physical frame-data bytes.
     */
    assert(native.sourceLength == 11);

    const preserved =
        native.content.match!(
            (Id3v22UniqueFileIdentifierFrame identifier)
            {
                return
                    identifier.effectiveUnsynchronisation &&
                    identifier.ownerIdentifier == "x" &&
                    identifier.logicalIdentifierLength == 2 &&
                    identifier.rawIdentifier.data ==
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
