/++
Unified semantic state view for native ID3v2.3 frames.

Each semantic frame codec retains its own strongly typed outcome and
availability enum. Higher layers should not need to know all of those
codec-specific enum types merely to determine whether semantic content
is decoded, requires a transformation, or is unknown.

This module provides that common read-only view. It does not modify or
replace the underlying codec outcome stored in `Id3v23NativeFrame`.
+/
module audiotag.id3v2.v23.native_state;

import std.sumtype :
    match;

import audiotag.id3v2.v23.attached_picture :
    Id3v23AttachedPictureOutcome;

import audiotag.id3v2.v23.comment :
    Id3v23CommentOutcome;

import audiotag.id3v2.v23.lyrics_text :
    Id3v23LyricsTextOutcome;

import audiotag.id3v2.v23.native_frame :
    Id3v23NativeFrame,
    Id3v23NativeFrameContent,
    Id3v23UnknownFrame;

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
Unified semantic state of one native ID3v2.3 frame.

All states represent successful native nodes.

Malformed input remains a `ParseError` returned by the semantic decoder
and therefore never appears here.
+/
enum Id3v23NativeFrameState : ubyte
{
    /// Semantic content has been decoded.
    decoded,

    /// Semantic decoding requires decompression.
    requiresDecompression,

    /// Semantic decoding requires decryption.
    requiresDecryption,

    /// Semantic decoding requires both decryption and decompression.
    requiresDecryptionAndDecompression,

    /// Structurally valid frame without a selected semantic codec.
    unknownSemanticFrame
}


/++
Returns the unified semantic state of one native ID3v2.3 frame.

The underlying codec outcome remains stored unchanged in the native
frame. This function only projects its codec-specific availability into
the common state model.
+/
Id3v23NativeFrameState
id3v23NativeFrameState(
    Id3v23NativeFrame frame
)
    @safe
{
    return
        frame.content.match!(
            (Id3v23TextInformationOutcome outcome) =>
                mapAvailability(
                    outcome.availability
                ),

            (Id3v23UserTextOutcome outcome) =>
                mapAvailability(
                    outcome.availability
                ),

            (Id3v23UrlLinkOutcome outcome) =>
                mapAvailability(
                    outcome.availability
                ),

            (Id3v23UserUrlOutcome outcome) =>
                mapAvailability(
                    outcome.availability
                ),

            (Id3v23CommentOutcome outcome) =>
                mapAvailability(
                    outcome.availability
                ),

            (Id3v23LyricsTextOutcome outcome) =>
                mapAvailability(
                    outcome.availability
                ),

            (Id3v23AttachedPictureOutcome outcome) =>
                mapAvailability(
                    outcome.availability
                ),

            (Id3v23PrivateOutcome outcome) =>
                mapAvailability(
                    outcome.availability
                ),

            (Id3v23UniqueFileIdentifierOutcome outcome) =>
                mapAvailability(
                    outcome.availability
                ),

            (Id3v23UnknownFrame unknown) =>
                Id3v23NativeFrameState
                    .unknownSemanticFrame
        );
}


/++
Maps one codec-specific availability enum to the common native state.

All current ID3v2.3 semantic codecs intentionally expose the same four
availability states. The template centralizes that common contract
without changing the stored codec outcome.
+/
private Id3v23NativeFrameState
mapAvailability(A)(
    A availability
)
    @safe pure nothrow @nogc
{
    if (
        availability ==
        A.decoded
    )
    {
        return
            Id3v23NativeFrameState.decoded;
    }


    if (
        availability ==
        A.requiresDecompression
    )
    {
        return
            Id3v23NativeFrameState
                .requiresDecompression;
    }


    if (
        availability ==
        A.requiresDecryption
    )
    {
        return
            Id3v23NativeFrameState
                .requiresDecryption;
    }


    if (
        availability ==
        A.requiresDecryptionAndDecompression
    )
    {
        return
            Id3v23NativeFrameState
                .requiresDecryptionAndDecompression;
    }


    /*
     * Reaching this point means a semantic codec availability enum
     * gained a state without this common view being updated.
     *
     * This is an internal exhaustiveness invariant, not malformed
     * external input.
     */
    assert(0);
}


version (unittest)
{
    import audiotag.id3v2.v23.frame :
        Id3v23FrameEnvelope;

    import audiotag.id3v2.v23.text_information :
        Id3v23TextInformationAvailability;


    /++
    Constructs one synthetic native frame around a codec outcome.
    +/
    private Id3v23NativeFrame testNativeFrame(T)(
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
}


/// A decoded codec outcome projects to the common decoded state.
unittest
{
    auto outcome =
        Id3v23TextInformationOutcome.init;

    outcome.availability =
        Id3v23TextInformationAvailability.decoded;

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                outcome
            )
        ) ==
        Id3v23NativeFrameState.decoded
    );
}


/// Decompression remains a successful transformation requirement.
unittest
{
    auto outcome =
        Id3v23TextInformationOutcome.init;

    outcome.availability =
        Id3v23TextInformationAvailability
            .requiresDecompression;

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                outcome
            )
        ) ==
        Id3v23NativeFrameState
            .requiresDecompression
    );
}


/// Decryption remains a successful transformation requirement.
unittest
{
    auto outcome =
        Id3v23TextInformationOutcome.init;

    outcome.availability =
        Id3v23TextInformationAvailability
            .requiresDecryption;

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                outcome
            )
        ) ==
        Id3v23NativeFrameState
            .requiresDecryption
    );
}


/// Combined transformation requirements remain explicit.
unittest
{
    auto outcome =
        Id3v23TextInformationOutcome.init;

    outcome.availability =
        Id3v23TextInformationAvailability
            .requiresDecryptionAndDecompression;

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                outcome
            )
        ) ==
        Id3v23NativeFrameState
            .requiresDecryptionAndDecompression
    );
}


/// Unknown valid frames have a distinct successful native state.
unittest
{
    auto native =
        testNativeFrame(
            Id3v23UnknownFrame()
        );

    assert(
        id3v23NativeFrameState(
            native
        ) ==
        Id3v23NativeFrameState
            .unknownSemanticFrame
    );
}


/// The common projection works for every semantic outcome family.
unittest
{
    Id3v23TextInformationOutcome textInformation;
    Id3v23UserTextOutcome userText;
    Id3v23UrlLinkOutcome urlLink;
    Id3v23UserUrlOutcome userUrl;
    Id3v23CommentOutcome comment;
    Id3v23LyricsTextOutcome lyrics;
    Id3v23AttachedPictureOutcome picture;
    Id3v23PrivateOutcome privateFrame;
    Id3v23UniqueFileIdentifierOutcome uniqueFileIdentifier;

    /*
     * Every availability enum defines `decoded` as its first member,
     * therefore default-initialized outcomes are decoded outcomes.
     */
    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                textInformation
            )
        ) ==
        Id3v23NativeFrameState.decoded
    );

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                userText
            )
        ) ==
        Id3v23NativeFrameState.decoded
    );

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                urlLink
            )
        ) ==
        Id3v23NativeFrameState.decoded
    );

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                userUrl
            )
        ) ==
        Id3v23NativeFrameState.decoded
    );

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                comment
            )
        ) ==
        Id3v23NativeFrameState.decoded
    );

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                lyrics
            )
        ) ==
        Id3v23NativeFrameState.decoded
    );

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                picture
            )
        ) ==
        Id3v23NativeFrameState.decoded
    );

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                privateFrame
            )
        ) ==
        Id3v23NativeFrameState.decoded
    );

    assert(
        id3v23NativeFrameState(
            testNativeFrame(
                uniqueFileIdentifier
            )
        ) ==
        Id3v23NativeFrameState.decoded
    );
}
