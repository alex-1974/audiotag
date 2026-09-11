/++
Shared semantic cue representation for ID3v2 synchronised lyrics/text.

ID3v2.2 `SLT` and ID3v2.3/v2.4 `SYLT` represent their timed body as an
ordered sequence of decoded text fragments paired with absolute 32-bit
timestamps.

Text encoding, timestamp units, content-type vocabularies, terminators,
unsynchronisation and raw source provenance remain outside this semantic type.
+/
module audiotag.id3v2.common.synchronised_text;


/++
One decoded synchronised text cue.

`timestamp` uses the unit selected by the surrounding frame.
+/
struct Id3v2SynchronisedTextCue
{
    string text;
    uint timestamp;
}


unittest
{
    const cue =
        Id3v2SynchronisedTextCue(
            "hello",
            1234
        );

    assert(cue.text == "hello");
    assert(cue.timestamp == 1234);
}
