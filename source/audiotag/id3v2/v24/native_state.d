/++
Unified semantic state view for native ID3v2.4 frames.

Each semantic frame codec retains its own strongly typed outcome and
availability enum. Higher layers should not need to know all of those
codec-specific enum types merely to determine whether semantic content
is decoded, requires a transformation, or is unknown.

This module provides that common read-only view. It does not modify or
replace the underlying codec outcome stored in `Id3v24NativeFrame`.
+/
module audiotag.id3v2.v24.native_state;

import std.sumtype :
    match;

import audiotag.id3v2.v24.attached_picture :
    Id3v24AttachedPictureOutcome;

import audiotag.id3v2.v24.comment :
    Id3v24CommentOutcome;

import audiotag.id3v2.v24.lyrics_text :
    Id3v24LyricsTextOutcome;

import audiotag.id3v2.v24.native_frame :
    Id3v24NativeFrame,
    Id3v24NativeFrameContent,
    Id3v24UnknownFrame;

import audiotag.id3v2.v24.private_frame :
    Id3v24PrivateOutcome;

import audiotag.id3v2.v24.text_information :
    Id3v24TextInformationAvailability,
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
Unified semantic state of one native ID3v2.4 frame.

All states are successful native representations. Parse failures remain
`ParseError`s returned by the decoder and therefore never appear here.
+/
enum Id3v24NativeFrameState : ubyte
{
    /// Semantic content has been decoded.
    decoded,

    /// Semantic decoding requires decompression.
    requiresDecompression,

    /// Semantic decoding requires decryption.
    requiresDecryption,

    /// Semantic decoding requires both decryption and decompression.
    requiresDecryptionAndDecompression,

    /// The frame is structurally valid but has no selected semantic codec.
    unknownSemanticFrame
}


/++
Returns the unified semantic state of one native ID3v2.4 frame.

The underlying codec outcome is retained unchanged. This function only
projects its codec-specific availability into the common native-frame
state model.
+/
Id3v24NativeFrameState id3v24NativeFrameState(
    Id3v24NativeFrame frame
)
    @safe
{
    return frame.content.match!(
        (Id3v24TextInformationOutcome outcome) =>
            mapAvailability(outcome.availability),

        (Id3v24UserTextOutcome outcome) =>
            mapAvailability(outcome.availability),

        (Id3v24UrlLinkOutcome outcome) =>
            mapAvailability(outcome.availability),

        (Id3v24UserUrlOutcome outcome) =>
            mapAvailability(outcome.availability),

        (Id3v24CommentOutcome outcome) =>
            mapAvailability(outcome.availability),

        (Id3v24LyricsTextOutcome outcome) =>
            mapAvailability(outcome.availability),

        (Id3v24AttachedPictureOutcome outcome) =>
            mapAvailability(outcome.availability),

        (Id3v24PrivateOutcome outcome) =>
            mapAvailability(outcome.availability),

        (Id3v24UniqueFileIdentifierOutcome outcome) =>
            mapAvailability(outcome.availability),

        (Id3v24UnknownFrame unknown) =>
            Id3v24NativeFrameState.unknownSemanticFrame
    );
}


/++
Maps one codec-specific availability enum to the common native state.

All current semantic codec availability enums intentionally expose the
same four states. The template keeps that common contract centralized
without converting the stored codec outcome itself.
+/
private Id3v24NativeFrameState mapAvailability(A)(
    A availability
)
    @safe pure nothrow @nogc
{
    if (availability == A.decoded)
    {
        return Id3v24NativeFrameState.decoded;
    }

    if (availability == A.requiresDecompression)
    {
        return
            Id3v24NativeFrameState.requiresDecompression;
    }

    if (availability == A.requiresDecryption)
    {
        return
            Id3v24NativeFrameState.requiresDecryption;
    }

    if (
        availability ==
        A.requiresDecryptionAndDecompression
    )
    {
        return
            Id3v24NativeFrameState
                .requiresDecryptionAndDecompression;
    }

    // Reaching this point would mean a codec availability enum gained
    // a state without this common view being updated.
    assert(0);
}


import audiotag.id3v2.v24.frame :
    Id3v24FrameEnvelope;


/++
Constructs a native frame around one outcome for state-view tests.
+/
private Id3v24NativeFrame testNativeFrame(T)(
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


/// A decoded codec outcome projects to the common decoded state.
unittest
{
    auto outcome =
        Id3v24TextInformationOutcome.init;

    outcome.availability =
        Id3v24TextInformationAvailability.decoded;

    assert(
        id3v24NativeFrameState(
            testNativeFrame(outcome)
        ) ==
        Id3v24NativeFrameState.decoded
    );
}


/// Decompression remains a successful transformation requirement.
unittest
{
    auto outcome =
        Id3v24TextInformationOutcome.init;

    outcome.availability =
        Id3v24TextInformationAvailability
            .requiresDecompression;

    assert(
        id3v24NativeFrameState(
            testNativeFrame(outcome)
        ) ==
        Id3v24NativeFrameState
            .requiresDecompression
    );
}


/// Decryption remains a successful transformation requirement.
unittest
{
    auto outcome =
        Id3v24TextInformationOutcome.init;

    outcome.availability =
        Id3v24TextInformationAvailability
            .requiresDecryption;

    assert(
        id3v24NativeFrameState(
            testNativeFrame(outcome)
        ) ==
        Id3v24NativeFrameState
            .requiresDecryption
    );
}


/// Combined transformation requirements remain explicit.
unittest
{
    auto outcome =
        Id3v24TextInformationOutcome.init;

    outcome.availability =
        Id3v24TextInformationAvailability
            .requiresDecryptionAndDecompression;

    assert(
        id3v24NativeFrameState(
            testNativeFrame(outcome)
        ) ==
        Id3v24NativeFrameState
            .requiresDecryptionAndDecompression
    );
}


/// Unknown valid frames have a distinct successful native state.
unittest
{
    auto native =
        testNativeFrame(
            Id3v24UnknownFrame()
        );

    assert(
        id3v24NativeFrameState(native) ==
        Id3v24NativeFrameState
            .unknownSemanticFrame
    );
}
