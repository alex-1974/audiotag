/++
Central canonical dispatcher for one native ID3v2.2 frame.

The native layer has already classified every structurally valid frame into one
semantic frame type. This module only routes that semantic type to the
corresponding canonical mapper.

No parsing, semantic decoding or frame-identifier heuristics are performed
here.

Legacy recording-time text frames (`TYE`, `TDA`, `TIM`) deliberately route
through the ordinary text mapper, which reports them as `unsupportedFrame`.
Their many-to-one `recordingDate` projection belongs to frame-sequence
aggregation.

Unknown native frames remain valid native metadata and return
`unsupportedFrame`.
+/
module audiotag.id3v2.v22.canonical_dispatch;

import std.sumtype :
    match;

import audiotag.id3v2.v22.attached_picture :
    Id3v22AttachedPictureFrame;

import audiotag.id3v2.v22.canonical_language_text :
    mapId3v22NativeLanguageTextFrameToCanonical;

import audiotag.id3v2.v22.canonical_mapping :
    Id3v22CanonicalMappingResult,
    Id3v22CanonicalMappingStatus;

import audiotag.id3v2.v22.canonical_picture :
    mapId3v22NativePictureFrameToCanonical;

import audiotag.id3v2.v22.canonical_text :
    mapId3v22NativeTextFrameToCanonical;

import audiotag.id3v2.v22.canonical_unique_file_identifier :
    mapId3v22NativeUniqueFileIdentifierFrameToCanonical;

import audiotag.id3v2.v22.canonical_url :
    mapId3v22NativeUrlFrameToCanonical;

import audiotag.id3v2.v22.canonical_user_text :
    mapId3v22NativeUserTextFrameToCanonical;

import audiotag.id3v2.v22.comment :
    Id3v22CommentFrame;

import audiotag.id3v2.v22.lyrics_text :
    Id3v22LyricsTextFrame;

import audiotag.id3v2.v22.native_frame :
    Id3v22NativeFrame;

import audiotag.id3v2.v22.text_information :
    Id3v22TextInformationFrame;

import audiotag.id3v2.v22.unique_file_identifier :
    Id3v22UniqueFileIdentifierFrame;

import audiotag.id3v2.v22.url_link :
    Id3v22UrlLinkFrame;

import audiotag.id3v2.v22.user_text :
    Id3v22UserTextFrame;

import audiotag.id3v2.v22.user_url :
    Id3v22UserUrlFrame;


/++
Maps one unified native ID3v2.2 frame to canonical metadata.

The native semantic alternative selects the corresponding family mapper.
Per-frame mapping outcomes are propagated unchanged.

Params:
    native = Unified native ID3v2.2 frame.

Returns:
    Result of the selected canonical family mapper, or `unsupportedFrame` for
    an unknown native frame.
+/
Id3v22CanonicalMappingResult
mapId3v22NativeFrameToCanonical(
    Id3v22NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v22TextInformationFrame frame) =>
                mapId3v22NativeTextFrameToCanonical(
                    native
                ),

            (Id3v22UserTextFrame frame) =>
                mapId3v22NativeUserTextFrameToCanonical(
                    native
                ),

            (Id3v22UrlLinkFrame frame) =>
                mapId3v22NativeUrlFrameToCanonical(
                    native
                ),

            (Id3v22UserUrlFrame frame) =>
                mapId3v22NativeUrlFrameToCanonical(
                    native
                ),

            (Id3v22CommentFrame frame) =>
                mapId3v22NativeLanguageTextFrameToCanonical(
                    native
                ),

            (Id3v22LyricsTextFrame frame) =>
                mapId3v22NativeLanguageTextFrameToCanonical(
                    native
                ),

            (Id3v22AttachedPictureFrame frame) =>
                mapId3v22NativePictureFrameToCanonical(
                    native
                ),

            (Id3v22UniqueFileIdentifierFrame frame) =>
                mapId3v22NativeUniqueFileIdentifierFrameToCanonical(
                    native
                ),

            _ =>
                Id3v22CanonicalMappingResult
                    .unsupported()
        );
}


version (unittest)
{
    import audiotag.id3v2.v22.frame :
        Id3v22FrameEnvelope;

    import audiotag.id3v2.v22.native_frame :
        Id3v22NativeFrameContent,
        Id3v22UnknownFrame;


    private Id3v22NativeFrame
    testNative(T)(
        T contentValue
    )
        @safe
    {
        Id3v22NativeFrameContent content =
            contentValue;


        return
            Id3v22NativeFrame(
                Id3v22FrameEnvelope.init,
                content
            );
    }


    private void
    assertSameMapping(
        Id3v22CanonicalMappingResult actual,
        Id3v22CanonicalMappingResult expected
    )
        @safe
    {
        assert(
            actual.status ==
            expected.status
        );


        assert(
            actual.mapped ==
            expected.mapped
        );


        if (
            actual.mapped
        )
        {
            assert(
                actual.field.key.name ==
                expected.field.key.name
            );
        }
    }
}


/// Ordinary text-information frames route to the text mapper.
unittest
{
    Id3v22TextInformationFrame frame;


    auto native =
        testNative(
            frame
        );


    assertSameMapping(
        mapId3v22NativeFrameToCanonical(
            native
        ),
        mapId3v22NativeTextFrameToCanonical(
            native
        )
    );
}


/// TXX frames route to the user-text mapper.
unittest
{
    Id3v22UserTextFrame frame;


    auto native =
        testNative(
            frame
        );


    assertSameMapping(
        mapId3v22NativeFrameToCanonical(
            native
        ),
        mapId3v22NativeUserTextFrameToCanonical(
            native
        )
    );
}


/// Ordinary W** frames route to the URL mapper.
unittest
{
    Id3v22UrlLinkFrame frame;


    auto native =
        testNative(
            frame
        );


    assertSameMapping(
        mapId3v22NativeFrameToCanonical(
            native
        ),
        mapId3v22NativeUrlFrameToCanonical(
            native
        )
    );
}


/// WXX frames route to the URL mapper.
unittest
{
    Id3v22UserUrlFrame frame;


    auto native =
        testNative(
            frame
        );


    assertSameMapping(
        mapId3v22NativeFrameToCanonical(
            native
        ),
        mapId3v22NativeUrlFrameToCanonical(
            native
        )
    );
}


/// COM frames route to the language-text mapper.
unittest
{
    Id3v22CommentFrame frame;


    auto native =
        testNative(
            frame
        );


    assertSameMapping(
        mapId3v22NativeFrameToCanonical(
            native
        ),
        mapId3v22NativeLanguageTextFrameToCanonical(
            native
        )
    );
}


/// ULT frames route to the language-text mapper.
unittest
{
    Id3v22LyricsTextFrame frame;


    auto native =
        testNative(
            frame
        );


    assertSameMapping(
        mapId3v22NativeFrameToCanonical(
            native
        ),
        mapId3v22NativeLanguageTextFrameToCanonical(
            native
        )
    );
}


/// PIC frames route to the artwork mapper.
unittest
{
    Id3v22AttachedPictureFrame frame;


    auto native =
        testNative(
            frame
        );


    assertSameMapping(
        mapId3v22NativeFrameToCanonical(
            native
        ),
        mapId3v22NativePictureFrameToCanonical(
            native
        )
    );
}


/// UFI frames route to the unique-file-identifier mapper.
unittest
{
    Id3v22UniqueFileIdentifierFrame frame;


    auto native =
        testNative(
            frame
        );


    assertSameMapping(
        mapId3v22NativeFrameToCanonical(
            native
        ),
        mapId3v22NativeUniqueFileIdentifierFrameToCanonical(
            native
        )
    );
}


/// Unknown native frames remain unsupported rather than malformed.
unittest
{
    auto native =
        testNative(
            Id3v22UnknownFrame()
        );


    auto result =
        mapId3v22NativeFrameToCanonical(
            native
        );


    assert(
        !result.mapped
    );


    assert(
        result.status ==
        Id3v22CanonicalMappingStatus
            .unsupportedFrame
    );
}


/// Legacy recording-time text is deliberately deferred to sequence mapping.
unittest
{
    Id3v22TextInformationFrame frame;

    frame.id[] =
        "TYE";

    frame.value =
        "2000";


    auto native =
        testNative(
            frame
        );


    auto result =
        mapId3v22NativeFrameToCanonical(
            native
        );


    assert(
        !result.mapped
    );


    assert(
        result.status ==
        Id3v22CanonicalMappingStatus
            .unsupportedFrame
    );
}
