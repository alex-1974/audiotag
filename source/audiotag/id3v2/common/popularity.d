/++
Shared semantic representation of an ID3v2 popularity meter.

ID3v2.2 `POP` and ID3v2.3/v2.4 `POPM` carry the same semantic fields:

- a null-terminated ISO-8859-1 user email/identity string;
- one rating byte;
- an optional arbitrary-width play counter.

The physical frame representation and revision-specific unsynchronisation rules
remain in the revision-specific codecs.
+/
module audiotag.id3v2.common.popularity;

import audiotag.id3v2.common.counter :
    Id3v2Counter;


/++
Semantic value shared by ID3v2 popularity-meter revisions.

`rating` uses the native ID3 scale: zero means unknown, while 1 through 255
range from worst to best.

When `hasCounter` is true, `counter` contains the exact logical big-endian
counter bytes and the surrounding frame codec has validated a minimum width of
four bytes. When `hasCounter` is false, the counter was omitted from the native
frame.
+/
struct Id3v2Popularity
{
    /// Decoded ISO-8859-1 user email/identity string.
    string email;

    /// Native popularity rating byte.
    ubyte rating;

    /// Whether the optional personal play counter is present.
    bool hasCounter;

    /// Exact logical arbitrary-width counter bytes when present.
    Id3v2Counter counter;
}
