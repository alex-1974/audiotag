/++
Shared semantic representation of one ID3v2 people-credit entry.

Legacy ID3v2.2 `IPL` and ID3v2.3 `IPLS` store generic involvement/involvee
pairs. ID3v2.4 splits the same broad domain into `TIPL` function/name pairs
and `TMCL` instrument/artist pairs.

Only the semantic pair and its explicitly known category are shared here.
Physical text encoding, frame identifiers, raw spans, unsynchronisation and
revision-specific framing remain in revision-specific codecs.
+/
module audiotag.id3v2.common.people_credit;


/++
Semantic category of one ID3v2 people-credit pair.

Legacy `IPL`/`IPLS` do not distinguish function credits from musician credits,
so their entries use `unspecified`.

ID3v2.4 `TIPL` entries may use `functionRole`, while `TMCL` entries may use
`instrument`.
+/
enum Id3v2PeopleCreditKind : ubyte
{
    unspecified,
    functionRole,
    instrument
}


/++
One ordered ID3v2 involvement/involvee pair.

The strings contain decoded text exactly at the semantic field level. No
controlled vocabulary, role normalization or legacy-to-v2.4 classification is
invented by this type.
+/
struct Id3v2PeopleCredit
{
    /// Semantic category explicitly known from the native frame type.
    Id3v2PeopleCreditKind kind;

    /// Involvement, function or instrument text.
    string involvement;

    /// Involvee, name or artist-list text.
    string involvee;
}
