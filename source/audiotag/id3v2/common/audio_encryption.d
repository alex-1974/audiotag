/++
Shared semantic representation for ID3v2 audio-encryption metadata.

ID3v2.2 `CRA` and ID3v2.3/v2.4 `AENC` use the same semantic fields:
an owner identifier, a preview start and preview length expressed in audio
frames, followed by optional encryption-specific binary data.

The encryption-specific data itself remains revision/native-codec data. This
shared type deliberately does not model or execute any cryptographic method.
+/
module audiotag.id3v2.common.audio_encryption;


/++
Revision-independent semantic metadata for an ID3v2 audio-encryption frame.
+/
struct Id3v2AudioEncryptionMetadata
{
    /// Organisation or contact identifier responsible for the encryption.
    string ownerIdentifier;

    /// Start of the unencrypted preview, measured in audio frames.
    ushort previewStartFrames;

    /// Length of the unencrypted preview, measured in audio frames.
    ushort previewLengthFrames;
}


unittest
{
    const value =
        Id3v2AudioEncryptionMetadata(
            "owner@example.invalid",
            120,
            240
        );

    assert(value.ownerIdentifier == "owner@example.invalid");
    assert(value.previewStartFrames == 120);
    assert(value.previewLengthFrames == 240);
}
