/++
Central canonical dispatcher for one native ID3v2.4 frame.

The native layer has already classified every structurally valid frame
into one semantic outcome type. This module only routes that outcome to
the corresponding canonical mapper.

No parsing, semantic decoding or frame-identifier heuristics are
performed here.

Unknown native frames remain valid native metadata and return
`unsupportedFrame`.
+/
module audiotag.id3v2.v24.canonical_dispatch;

import std.sumtype :
    match;

import audiotag.id3v2.v24.attached_picture :
    Id3v24AttachedPictureOutcome;

import audiotag.id3v2.v24.canonical_language_text :
    mapId3v24NativeLanguageTextFrameToCanonical;

import audiotag.id3v2.v24.canonical_mapping :
    Id3v24CanonicalMappingResult,
    Id3v24CanonicalMappingStatus;

import audiotag.id3v2.v24.canonical_picture :
    mapId3v24NativePictureFrameToCanonical;

import audiotag.id3v2.v24.canonical_private :
    mapId3v24NativePrivateFrameToCanonical;

import audiotag.id3v2.v24.canonical_text :
    mapId3v24NativeTextFrameToCanonical;

import audiotag.id3v2.v24.canonical_unique_file_identifier :
    mapId3v24NativeUniqueFileIdentifierFrameToCanonical;

import audiotag.id3v2.v24.canonical_url :
    mapId3v24NativeUrlFrameToCanonical;

import audiotag.id3v2.v24.canonical_user_text :
    mapId3v24NativeUserTextFrameToCanonical;

import audiotag.id3v2.v24.comment :
    Id3v24CommentOutcome;

import audiotag.id3v2.v24.lyrics_text :
    Id3v24LyricsTextOutcome;

import audiotag.id3v2.v24.native_frame :
    Id3v24NativeFrame;

import audiotag.id3v2.v24.private_frame :
    Id3v24PrivateOutcome;

import audiotag.id3v2.v24.text_information :
    Id3v24TextInformationOutcome;

import audiotag.id3v2.v24.unique_file_identifier :
    Id3v24UniqueFileIdentifierOutcome;

import audiotag.id3v2.v24.url_link :
    Id3v24UrlLinkOutcome;

import audiotag.id3v2.v24.user_text :
    Id3v24UserTextOutcome;

import audiotag.id3v2.v24.user_url :
    Id3v24UserUrlOutcome;


/++
Maps one unified native ID3v2.4 frame to canonical metadata.

The native semantic outcome type selects the appropriate existing
family mapper. Transformation-pending and unrepresentable states are
therefore propagated unchanged by that mapper.

Params:
    native = Unified native ID3v2.4 frame.

Returns:
    Result of the selected canonical family mapper, or
    `unsupportedFrame` for an unknown native frame.
+/
Id3v24CanonicalMappingResult
mapId3v24NativeFrameToCanonical(
    Id3v24NativeFrame native
)
    @safe
{
    return native.content.match!(
        (Id3v24TextInformationOutcome outcome) =>
            mapId3v24NativeTextFrameToCanonical(
                native
            ),

        (Id3v24UserTextOutcome outcome) =>
            mapId3v24NativeUserTextFrameToCanonical(
                native
            ),

        (Id3v24UrlLinkOutcome outcome) =>
            mapId3v24NativeUrlFrameToCanonical(
                native
            ),

        (Id3v24UserUrlOutcome outcome) =>
            mapId3v24NativeUrlFrameToCanonical(
                native
            ),

        (Id3v24CommentOutcome outcome) =>
            mapId3v24NativeLanguageTextFrameToCanonical(
                native
            ),

        (Id3v24LyricsTextOutcome outcome) =>
            mapId3v24NativeLanguageTextFrameToCanonical(
                native
            ),

        (Id3v24AttachedPictureOutcome outcome) =>
            mapId3v24NativePictureFrameToCanonical(
                native
            ),

        (Id3v24PrivateOutcome outcome) =>
            mapId3v24NativePrivateFrameToCanonical(
                native
            ),

        (Id3v24UniqueFileIdentifierOutcome outcome) =>
            mapId3v24NativeUniqueFileIdentifierFrameToCanonical(
                native
            ),

        _ =>
            Id3v24CanonicalMappingResult
                .unsupported()
    );
}


version (unittest)
{
    import audiotag.id3v2.v24.frame :
        Id3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrameContent,
        Id3v24UnknownFrame;


    private Id3v24NativeFrame testNative(T)(
        T outcome
    )
        @safe
    {
        Id3v24NativeFrameContent content =
            outcome;

        return Id3v24NativeFrame(
            Id3v24FrameEnvelope.init,
            content
        );
    }


    private void assertSameMapping(
        Id3v24CanonicalMappingResult actual,
        Id3v24CanonicalMappingResult expected
    )
        @safe
    {
        assert(actual.status == expected.status);
        assert(actual.mapped == expected.mapped);

        if (actual.mapped)
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
    Id3v24TextInformationOutcome outcome;
    auto native = testNative(outcome);

    assertSameMapping(
        mapId3v24NativeFrameToCanonical(native),
        mapId3v24NativeTextFrameToCanonical(native)
    );
}


/// TXXX outcomes route to the user-text mapper.
unittest
{
    Id3v24UserTextOutcome outcome;
    auto native = testNative(outcome);

    assertSameMapping(
        mapId3v24NativeFrameToCanonical(native),
        mapId3v24NativeUserTextFrameToCanonical(native)
    );
}


/// Ordinary URL outcomes route to the URL mapper.
unittest
{
    Id3v24UrlLinkOutcome outcome;
    auto native = testNative(outcome);

    assertSameMapping(
        mapId3v24NativeFrameToCanonical(native),
        mapId3v24NativeUrlFrameToCanonical(native)
    );
}


/// WXXX outcomes route to the URL mapper.
unittest
{
    Id3v24UserUrlOutcome outcome;
    auto native = testNative(outcome);

    assertSameMapping(
        mapId3v24NativeFrameToCanonical(native),
        mapId3v24NativeUrlFrameToCanonical(native)
    );
}


/// COMM outcomes route to the language-text mapper.
unittest
{
    Id3v24CommentOutcome outcome;
    auto native = testNative(outcome);

    assertSameMapping(
        mapId3v24NativeFrameToCanonical(native),
        mapId3v24NativeLanguageTextFrameToCanonical(native)
    );
}


/// USLT outcomes route to the language-text mapper.
unittest
{
    Id3v24LyricsTextOutcome outcome;
    auto native = testNative(outcome);

    assertSameMapping(
        mapId3v24NativeFrameToCanonical(native),
        mapId3v24NativeLanguageTextFrameToCanonical(native)
    );
}


/// APIC outcomes route to the picture mapper.
unittest
{
    Id3v24AttachedPictureOutcome outcome;
    auto native = testNative(outcome);

    assertSameMapping(
        mapId3v24NativeFrameToCanonical(native),
        mapId3v24NativePictureFrameToCanonical(native)
    );
}


/// PRIV outcomes route to the private-data mapper.
unittest
{
    Id3v24PrivateOutcome outcome;
    auto native = testNative(outcome);

    assertSameMapping(
        mapId3v24NativeFrameToCanonical(native),
        mapId3v24NativePrivateFrameToCanonical(native)
    );
}


/// UFID outcomes route to the unique-file-identifier mapper.
unittest
{
    Id3v24UniqueFileIdentifierOutcome outcome;
    auto native = testNative(outcome);

    assertSameMapping(
        mapId3v24NativeFrameToCanonical(native),
        mapId3v24NativeUniqueFileIdentifierFrameToCanonical(native)
    );
}


/// Unknown native frames remain unsupported rather than malformed.
unittest
{
    auto native =
        testNative(
            Id3v24UnknownFrame()
        );

    auto result =
        mapId3v24NativeFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .unsupportedFrame
    );
}
