/++
Central canonical dispatcher for one native ID3v2.3 frame.

The native layer has already classified every structurally valid frame
into one semantic outcome type. This module only routes that outcome to
the corresponding canonical mapper.

No parsing, semantic decoding or frame-identifier heuristics are
performed here.

Unknown native frames remain valid native metadata and return
`unsupportedFrame`.
+/
module audiotag.id3v2.v23.canonical_dispatch;

import std.sumtype :
    match;

import audiotag.id3v2.v23.attached_picture :
    Id3v23AttachedPictureOutcome;

import audiotag.id3v2.v23.canonical_language_text :
    mapId3v23NativeLanguageTextFrameToCanonical;

import audiotag.id3v2.v23.canonical_mapping :
    Id3v23CanonicalMappingResult,
    Id3v23CanonicalMappingStatus;

import audiotag.id3v2.v23.canonical_picture :
    mapId3v23NativePictureFrameToCanonical;

import audiotag.id3v2.v23.canonical_private :
    mapId3v23NativePrivateFrameToCanonical;

import audiotag.id3v2.v23.canonical_text :
    mapId3v23NativeTextFrameToCanonical;

import audiotag.id3v2.v23.canonical_unique_file_identifier :
    mapId3v23NativeUniqueFileIdentifierFrameToCanonical;

import audiotag.id3v2.v23.canonical_url :
    mapId3v23NativeUrlFrameToCanonical;

import audiotag.id3v2.v23.canonical_user_text :
    mapId3v23NativeUserTextFrameToCanonical;

import audiotag.id3v2.v23.comment :
    Id3v23CommentOutcome;

import audiotag.id3v2.v23.lyrics_text :
    Id3v23LyricsTextOutcome;

import audiotag.id3v2.v23.native_frame :
    Id3v23NativeFrame;

import audiotag.id3v2.v23.private_frame :
    Id3v23PrivateOutcome;

import audiotag.id3v2.v23.text_information :
    Id3v23TextInformationOutcome;

import audiotag.id3v2.v23.unique_file_identifier :
    Id3v23UniqueFileIdentifierOutcome;

import audiotag.id3v2.v23.url_link :
    Id3v23UrlLinkOutcome;

import audiotag.id3v2.v23.user_text :
    Id3v23UserTextOutcome;

import audiotag.id3v2.v23.user_url :
    Id3v23UserUrlOutcome;


/++
Maps one unified native ID3v2.3 frame to canonical metadata.

The native semantic outcome type selects the appropriate existing
family mapper. Transformation-pending and unrepresentable states are
therefore propagated unchanged by that mapper.

Params:
    native = Unified native ID3v2.3 frame.

Returns:
    Result of the selected canonical family mapper, or
    `unsupportedFrame` for an unknown native frame.
+/
Id3v23CanonicalMappingResult
mapId3v23NativeFrameToCanonical(
    Id3v23NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v23TextInformationOutcome outcome) =>
                mapId3v23NativeTextFrameToCanonical(
                    native
                ),

            (Id3v23UserTextOutcome outcome) =>
                mapId3v23NativeUserTextFrameToCanonical(
                    native
                ),

            (Id3v23UrlLinkOutcome outcome) =>
                mapId3v23NativeUrlFrameToCanonical(
                    native
                ),

            (Id3v23UserUrlOutcome outcome) =>
                mapId3v23NativeUrlFrameToCanonical(
                    native
                ),

            (Id3v23CommentOutcome outcome) =>
                mapId3v23NativeLanguageTextFrameToCanonical(
                    native
                ),

            (Id3v23LyricsTextOutcome outcome) =>
                mapId3v23NativeLanguageTextFrameToCanonical(
                    native
                ),

            (Id3v23AttachedPictureOutcome outcome) =>
                mapId3v23NativePictureFrameToCanonical(
                    native
                ),

            (Id3v23PrivateOutcome outcome) =>
                mapId3v23NativePrivateFrameToCanonical(
                    native
                ),

            (Id3v23UniqueFileIdentifierOutcome outcome) =>
                mapId3v23NativeUniqueFileIdentifierFrameToCanonical(
                    native
                ),

            _ =>
                Id3v23CanonicalMappingResult
                    .unsupported()
        );
}


version (unittest)
{
    import audiotag.id3v2.v23.frame :
        Id3v23FrameEnvelope;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrameContent,
        Id3v23UnknownFrame;


    private Id3v23NativeFrame testNative(T)(
        T outcome
    )
        @safe
    {
        Id3v23NativeFrameContent content =
            outcome;


        return
            Id3v23NativeFrame(
                Id3v23FrameEnvelope.init,
                content
            );
    }


    private void assertSameMapping(
        Id3v23CanonicalMappingResult actual,
        Id3v23CanonicalMappingResult expected
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


/// Ordinary text-information outcomes route to the text mapper.
unittest
{
    Id3v23TextInformationOutcome outcome;


    auto native =
        testNative(
            outcome
        );


    assertSameMapping(
        mapId3v23NativeFrameToCanonical(
            native
        ),
        mapId3v23NativeTextFrameToCanonical(
            native
        )
    );
}


/// TXXX outcomes route to the user-text mapper.
unittest
{
    Id3v23UserTextOutcome outcome;


    auto native =
        testNative(
            outcome
        );


    assertSameMapping(
        mapId3v23NativeFrameToCanonical(
            native
        ),
        mapId3v23NativeUserTextFrameToCanonical(
            native
        )
    );
}


/// Ordinary URL outcomes route to the URL mapper.
unittest
{
    Id3v23UrlLinkOutcome outcome;


    auto native =
        testNative(
            outcome
        );


    assertSameMapping(
        mapId3v23NativeFrameToCanonical(
            native
        ),
        mapId3v23NativeUrlFrameToCanonical(
            native
        )
    );
}


/// WXXX outcomes route to the URL mapper.
unittest
{
    Id3v23UserUrlOutcome outcome;


    auto native =
        testNative(
            outcome
        );


    assertSameMapping(
        mapId3v23NativeFrameToCanonical(
            native
        ),
        mapId3v23NativeUrlFrameToCanonical(
            native
        )
    );
}


/// COMM outcomes route to the language-text mapper.
unittest
{
    Id3v23CommentOutcome outcome;


    auto native =
        testNative(
            outcome
        );


    assertSameMapping(
        mapId3v23NativeFrameToCanonical(
            native
        ),
        mapId3v23NativeLanguageTextFrameToCanonical(
            native
        )
    );
}


/// USLT outcomes route to the language-text mapper.
unittest
{
    Id3v23LyricsTextOutcome outcome;


    auto native =
        testNative(
            outcome
        );


    assertSameMapping(
        mapId3v23NativeFrameToCanonical(
            native
        ),
        mapId3v23NativeLanguageTextFrameToCanonical(
            native
        )
    );
}


/// APIC outcomes route to the picture mapper.
unittest
{
    Id3v23AttachedPictureOutcome outcome;


    auto native =
        testNative(
            outcome
        );


    assertSameMapping(
        mapId3v23NativeFrameToCanonical(
            native
        ),
        mapId3v23NativePictureFrameToCanonical(
            native
        )
    );
}


/// PRIV outcomes route to the private-data mapper.
unittest
{
    Id3v23PrivateOutcome outcome;


    auto native =
        testNative(
            outcome
        );


    assertSameMapping(
        mapId3v23NativeFrameToCanonical(
            native
        ),
        mapId3v23NativePrivateFrameToCanonical(
            native
        )
    );
}


/// UFID outcomes route to the unique-file-identifier mapper.
unittest
{
    Id3v23UniqueFileIdentifierOutcome outcome;


    auto native =
        testNative(
            outcome
        );


    assertSameMapping(
        mapId3v23NativeFrameToCanonical(
            native
        ),
        mapId3v23NativeUniqueFileIdentifierFrameToCanonical(
            native
        )
    );
}


/// Unknown native frames remain unsupported rather than malformed.
unittest
{
    auto native =
        testNative(
            Id3v23UnknownFrame()
        );


    auto result =
        mapId3v23NativeFrameToCanonical(
            native
        );


    assert(
        !result.mapped
    );


    assert(
        result.status ==
        Id3v23CanonicalMappingStatus
            .unsupportedFrame
    );
}
