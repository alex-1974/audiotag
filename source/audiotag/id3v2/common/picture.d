/++
Shared semantic picture concepts across ID3v2 revisions.

ID3v2.2 `PIC` and ID3v2.3/v2.4 `APIC` use the same picture-type byte values
and the same distinction between embedded picture bytes and a linked image
URL.

The physical media-format field differs by revision:

- ID3v2.2 stores a fixed three-byte image format;
- ID3v2.3/v2.4 store a terminated MIME type.

Those native representation differences remain in revision-specific codecs.
+/
module audiotag.id3v2.common.picture;


/++
Semantic ID3v2 attached-picture type shared by v2.2, v2.3 and v2.4.
+/
enum Id3v2PictureType : ubyte
{
    other = 0x00,
    fileIcon = 0x01,
    otherFileIcon = 0x02,
    frontCover = 0x03,
    backCover = 0x04,
    leafletPage = 0x05,
    media = 0x06,
    leadArtist = 0x07,
    artist = 0x08,
    conductor = 0x09,
    band = 0x0A,
    composer = 0x0B,
    lyricist = 0x0C,
    recordingLocation = 0x0D,
    duringRecording = 0x0E,
    duringPerformance = 0x0F,
    videoCapture = 0x10,
    brightColouredFish = 0x11,
    illustration = 0x12,
    artistLogotype = 0x13,
    publisherLogotype = 0x14
}


/++
Kind of final payload carried by an ID3v2 attached-picture frame.
+/
enum Id3v2PicturePayloadKind : ubyte
{
    /// Embedded binary image data.
    binaryData,

    /// Native `-->` media marker indicates a linked image URL.
    linkedUrl
}


/++
Returns whether a raw picture-type byte is defined by ID3v2.
+/
bool
isValidId3v2PictureType(
    ubyte value
)
    @safe pure nothrow @nogc
{
    return
        value <=
        cast(ubyte)
            Id3v2PictureType.publisherLogotype;
}


/// The complete defined picture-type range is accepted.
unittest
{
    foreach (
        value;
        0x00 .. 0x15
    )
    {
        assert(
            isValidId3v2PictureType(
                cast(ubyte) value
            )
        );
    }
}


/// Values above the defined picture-type range are rejected.
unittest
{
    assert(
        !isValidId3v2PictureType(0x15)
    );

    assert(
        !isValidId3v2PictureType(0xFF)
    );
}
