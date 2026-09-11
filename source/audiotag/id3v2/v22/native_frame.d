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

import audiotag.id3v2.v22.recommended_buffer :
    Id3v22RecommendedBufferFrame,
    decodeId3v22RecommendedBufferFrame;

import audiotag.id3v2.v22.equalisation :
    Id3v22EqualisationFrame,
    decodeId3v22EqualisationFrame;

import audiotag.id3v2.v22.event_timing :
    Id3v22EventTimingFrame,
    decodeId3v22EventTimingFrame;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

import audiotag.id3v2.v22.general_encapsulated_object :
    Id3v22GeneralEncapsulatedObjectFrame,
    decodeId3v22GeneralEncapsulatedObjectFrame;

import audiotag.id3v2.v22.involved_people :
    Id3v22InvolvedPeopleFrame,
    decodeId3v22InvolvedPeopleFrame;

import audiotag.id3v2.v22.lyrics_text :
    Id3v22LyricsTextFrame,
    decodeId3v22LyricsTextFrame;

import audiotag.id3v2.v22.mpeg_location_lookup :
    Id3v22MpegLocationLookupFrame,
    decodeId3v22MpegLocationLookupFrame;

import audiotag.id3v2.v22.play_counter :
    Id3v22PlayCounterFrame,
    decodeId3v22PlayCounterFrame;

import audiotag.id3v2.v22.popularity_meter :
    Id3v22PopularityMeterFrame,
    decodeId3v22PopularityMeterFrame;

import audiotag.id3v2.v22.relative_volume :
    Id3v22RelativeVolumeChannel,
    Id3v22RelativeVolumeFrame,
    decodeId3v22RelativeVolumeFrame;

import audiotag.id3v2.v22.reverb :
    Id3v22ReverbFrame,
    decodeId3v22ReverbFrame;

import audiotag.id3v2.v22.synchronised_tempo :
    Id3v22SynchronisedTempoFrame,
    decodeId3v22SynchronisedTempoFrame;

import audiotag.id3v2.v22.synchronised_text :
    Id3v22SynchronisedTextContentType,
    Id3v22SynchronisedTextFrame,
    decodeId3v22SynchronisedTextFrame;

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
        Id3v22RecommendedBufferFrame,
        Id3v22EqualisationFrame,
        Id3v22EventTimingFrame,
        Id3v22GeneralEncapsulatedObjectFrame,
        Id3v22InvolvedPeopleFrame,
        Id3v22LyricsTextFrame,
        Id3v22MpegLocationLookupFrame,
        Id3v22AttachedPictureFrame,
        Id3v22UniqueFileIdentifierFrame,
        Id3v22PlayCounterFrame,
        Id3v22PopularityMeterFrame,
        Id3v22RelativeVolumeFrame,
        Id3v22ReverbFrame,
        Id3v22SynchronisedTempoFrame,
        Id3v22SynchronisedTextFrame,
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
- `BUF`, `COM`, `EQU`, `ETC`, `GEO`, `IPL`, `MLL`, `ULT`, `PIC`, `UFI`, `CNT`, `POP`, `REV`, `RVA`, `SLT` and `STC` use their dedicated codecs;
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
            "BUF"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22RecommendedBufferFrame(
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
            "EQU"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22EqualisationFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "ETC"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22EventTimingFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "GEO"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22GeneralEncapsulatedObjectFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "IPL"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22InvolvedPeopleFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "MLL"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22MpegLocationLookupFrame(
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


    if (
        idEquals(
            frame.header.id,
            "CNT"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22PlayCounterFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "POP"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22PopularityMeterFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "REV"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22ReverbFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "RVA"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22RelativeVolumeFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "SLT"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22SynchronisedTextFrame(
                    tagUnsynchronised
                )
            );
    }


    if (
        idEquals(
            frame.header.id,
            "STC"
        )
    )
    {
        return
            wrapDecoded(
                frame,
                frame.decodeId3v22SynchronisedTempoFrame(
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

    import audiotag.id3v2.common.tempo :
        Id3v2TempoKind;

    import audiotag.id3v2.common.timestamp :
        Id3v2TimestampFormat;

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
            'Z', 'Z', 'Z',
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
    assert(native.envelope.header.id[] == "ZZZ");

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


/// CNT dispatches to the dedicated arbitrary-width play-counter codec.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'N', 'T',
            0x00, 0x00, 0x04,

            0x00, 0x00, 0x00, 0x2A
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                850
            )
        );

    assert(result.hasValue);

    const isPlayCounter =
        result.value.content.match!(
            (Id3v22PlayCounterFrame counter) =>
                counter.counter.bigEndianBytes ==
                    [
                        0x00, 0x00, 0x00, 0x2A
                    ],

            _ =>
                false
        );

    assert(isPlayCounter);
}


/// POP dispatches to the dedicated popularity-meter codec.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'O', 'P',
            0x00, 0x00, 0x09,

            'a', '@', 'b',
            0x00,
            0xC8,
            0x00, 0x00, 0x00, 0x2A
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                900
            )
        );

    assert(result.hasValue);

    const isPopularityMeter =
        result.value.content.match!(
            (Id3v22PopularityMeterFrame meter) =>
                meter.popularity.email == "a@b" &&
                meter.popularity.rating == 0xC8 &&
                meter.popularity.hasCounter &&
                meter.popularity.counter.bigEndianBytes ==
                    [
                        0x00, 0x00, 0x00, 0x2A
                    ],

            _ =>
                false
        );

    assert(isPopularityMeter);
}

/// IPL dispatches to the dedicated involved-people codec.
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

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                950
            )
        );

    assert(result.hasValue);

    const isInvolvedPeople =
        result.value.content.match!(
            (Id3v22InvolvedPeopleFrame people) =>
                people.entries.length == 1 &&
                people.entries[0].credit.involvement == "guitar" &&
                people.entries[0].credit.involvee == "Alice",

            _ =>
                false
        );

    assert(isInvolvedPeople);
}

/// GEO dispatches to the dedicated general-encapsulated-object codec.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O',
            0x00, 0x00, 0x0A,

            0x00,
            'x', 0x00,
            'f', 0x00,
            'd', 0x00,
            0x01, 0x02, 0x03
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                1000
            )
        );

    assert(result.hasValue);

    const isGeneralObject =
        result.value.content.match!(
            (Id3v22GeneralEncapsulatedObjectFrame object) =>
                object.info.mimeType == "x" &&
                object.info.filename == "f" &&
                object.info.description == "d" &&
                object.rawObjectData.data ==
                    [0x01, 0x02, 0x03],

            _ =>
                false
        );

    assert(isGeneralObject);
}

/// ETC dispatches to the dedicated event-timing codec.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'T', 'C',
            0x00, 0x00, 0x06,

            0x02,
            0x03,
            0x00, 0x00, 0x00, 0x2A
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                1050
            )
        );

    assert(result.hasValue);

    const isEventTiming =
        result.value.content.match!(
            (Id3v22EventTimingFrame timing) =>
                timing.timestampFormat ==
                    Id3v2TimestampFormat.milliseconds &&
                timing.events.length == 1 &&
                timing.events[0].eventType == 0x03 &&
                timing.events[0].timestamp == 42,

            _ =>
                false
        );

    assert(isEventTiming);
}

unittest
{
    const ubyte[] bytes =
        [
            'S', 'T', 'C',
            0x00, 0x00, 0x06,

            0x02,
            120,
            0x00, 0x00, 0x00, 0x2A
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                1100
            )
        );

    assert(result.hasValue);

    const isSynchronisedTempo =
        result.value.content.match!(
            (Id3v22SynchronisedTempoFrame timing) =>
                timing.timestampFormat ==
                    Id3v2TimestampFormat.milliseconds &&
                timing.entries.length == 1 &&
                timing.entries[0].tempo.kind ==
                    Id3v2TempoKind.beatsPerMinute &&
                timing.entries[0].tempo.beatsPerMinute == 120 &&
                timing.entries[0].timestamp == 42,

            _ =>
                false
        );

    assert(isSynchronisedTempo);
}

/// SLT dispatches to the dedicated synchronised-text codec.
unittest
{
    const ubyte[] bytes =
        [
            'S', 'L', 'T',
            0x00, 0x00, 0x0E,

            0x00,
            'e', 'n', 'g',
            0x02,
            0x01,
            0x00,

            'H', 'i',
            0x00,
            0x00, 0x00, 0x00, 0x2A
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                1150
            )
        );

    assert(result.hasValue);

    const isSynchronisedText =
        result.value.content.match!(
            (Id3v22SynchronisedTextFrame text) =>
                text.language[] == "eng" &&
                text.timestampFormat ==
                    Id3v2TimestampFormat.milliseconds &&
                text.contentType ==
                    Id3v22SynchronisedTextContentType.lyrics &&
                text.cues.length == 1 &&
                text.cues[0].cue.text == "Hi" &&
                text.cues[0].cue.timestamp == 42,

            _ =>
                false
        );

    assert(isSynchronisedText);
}

/// MLL dispatches to the dedicated MPEG-location codec.
unittest
{
    const ubyte[] bytes =
        [
            'M', 'L', 'L',
            0x00, 0x00, 0x0B,

            0x00, 0x02,
            0x00, 0x03, 0xE8,
            0x00, 0x00, 0x1A,
            0x04,
            0x04,

            0xAB
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                1200
            )
        );

    assert(result.hasValue);

    const isMpegLocationLookup =
        result.value.content.match!(
            (Id3v22MpegLocationLookupFrame lookup) =>
                lookup.parameters.mpegFramesBetweenReference == 2 &&
                lookup.parameters.bytesBetweenReference == 1000 &&
                lookup.references.length == 1 &&
                lookup.references[0]
                    .reference.bytesDeviation == 10 &&
                lookup.references[0]
                    .reference.millisecondsDeviation == 11,

            _ =>
                false
        );

    assert(isMpegLocationLookup);
}

/// RVA dispatches to the dedicated relative-volume codec.
unittest
{
    const ubyte[] bytes =
        [
            'R', 'V', 'A',
            0x00, 0x00, 0x04,

            0x03,
            0x08,
            0x10,
            0x20
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                1250
            )
        );

    assert(result.hasValue);

    const isRelativeVolume =
        result.value.content.match!(
            (Id3v22RelativeVolumeFrame volume) =>
                volume.bitsUsed == 8 &&
                volume.channels.length == 2 &&
                volume.channels[0].channel ==
                    Id3v22RelativeVolumeChannel.right &&
                volume.channels[0].adjustment.increment &&
                volume.channels[0].adjustment.changeMagnitude == 16 &&
                volume.channels[1].channel ==
                    Id3v22RelativeVolumeChannel.left &&
                volume.channels[1].adjustment.increment &&
                volume.channels[1].adjustment.changeMagnitude == 32,

            _ =>
                false
        );

    assert(isRelativeVolume);
}

/// EQU dispatches to the dedicated legacy equalisation codec.
unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x04,

            0x08,
            0x83, 0xE8,
            0x20
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                1300
            )
        );

    assert(result.hasValue);

    const isEqualisation =
        result.value.content.match!(
            (Id3v22EqualisationFrame equalisation) =>
                equalisation.adjustmentBits == 8 &&
                equalisation.bands.length == 1 &&
                equalisation.bands[0].band.increment &&
                equalisation.bands[0].band.frequencyHz == 1000 &&
                equalisation.bands[0].band.adjustmentMagnitude == 32,

            _ =>
                false
        );

    assert(isEqualisation);
}

/// REV dispatches to the dedicated reverb codec.
unittest
{
    const ubyte[] bytes =
        [
            'R', 'E', 'V',
            0x00, 0x00, 0x0C,
            0x00, 0x64,
            0x00, 0xC8,
            0x03,
            0x04,
            0x10,
            0x20,
            0x30,
            0x40,
            0x50,
            0x60
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                1350
            )
        );

    assert(result.hasValue);

    const isReverb =
        result.value.content.match!(
            (Id3v22ReverbFrame reverb) =>
                reverb.settings.leftDelayMilliseconds == 100 &&
                reverb.settings.rightDelayMilliseconds == 200 &&
                reverb.settings.leftBounces.finiteCount == 3 &&
                reverb.settings.rightBounces.finiteCount == 4 &&
                reverb.settings.feedbackLeftToLeft == 0x10 &&
                reverb.settings.premixRightToLeft == 0x60,

            _ =>
                false
        );

    assert(isReverb);
}

/// BUF dispatches to the dedicated recommended-buffer codec.
unittest
{
    const ubyte[] bytes =
        [
            'B', 'U', 'F',
            0x00, 0x00, 0x04,

            0x00, 0x10, 0x00,
            0x01
        ];

    auto result =
        decodeId3v22NativeFrame(
            testEnvelope(
                bytes,
                1400
            )
        );

    assert(result.hasValue);

    const isRecommendedBuffer =
        result.value.content.match!(
            (Id3v22RecommendedBufferFrame buffer) =>
                buffer.value.bufferSize == 4096 &&
                buffer.value.embeddedInfo &&
                !buffer.value.hasNextTagOffset,

            _ =>
                false
        );

    assert(isRecommendedBuffer);
}
