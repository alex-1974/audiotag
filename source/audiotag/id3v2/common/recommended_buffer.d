/++
Shared semantic representation for ID3v2 recommended-buffer frames.

ID3v2.2 `BUF` and ID3v2.3/v2.4 `RBUF` carry the same semantics: a 24-bit
recommended buffer size, one embedded-info flag and an optional 32-bit offset
to the next tag.

Physical byte layout, frame identifiers, unsynchronisation and source
provenance remain revision-specific.
+/
module audiotag.id3v2.common.recommended_buffer;


/++
Revision-independent recommended-buffer semantics.
+/
struct Id3v2RecommendedBuffer
{
    /// Recommended buffer size in bytes.
    uint bufferSize;

    /// Whether embedded ID3 information may occur in the audio stream.
    bool embeddedInfo;

    /// Whether an offset to the next tag was present.
    bool hasNextTagOffset;

    /// Offset from the end of the containing tag to the next tag header.
    uint nextTagOffset;
}


unittest
{
    const value =
        Id3v2RecommendedBuffer(
            4096,
            true,
            true,
            123456
        );

    assert(value.bufferSize == 4096);
    assert(value.embeddedInfo);
    assert(value.hasNextTagOffset);
    assert(value.nextTagOffset == 123456);
}
