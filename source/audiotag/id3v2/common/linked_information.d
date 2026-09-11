/++
Shared semantic representation for ID3v2 linked-information identity data.

ID3v2.2 `LNK` and ID3v2.3/v2.4 `LINK` use the same conceptual structure:
a target frame identifier, a URL locating another ID3v2 tag, and optional
identity data used to select one frame from that tag.

The width and spelling of the target frame identifier remain
revision-specific. This module models only the revision-independent URL and
additional-identity semantics.
+/
module audiotag.id3v2.common.linked_information;

enum Id3v2LinkedAdditionalIdKind : ubyte
{
    none,
    descriptor,
    languageAndDescriptor
}

struct Id3v2LinkedInformation
{
    string url;
    Id3v2LinkedAdditionalIdKind additionalKind;
    char[3] language;
    string descriptor;
}

unittest
{
    char[3] language =
        ['e', 'n', 'g'];

    const linked =
        Id3v2LinkedInformation(
            "other.mp3",
            Id3v2LinkedAdditionalIdKind.languageAndDescriptor,
            language,
            "notes"
        );

    assert(linked.url == "other.mp3");
    assert(
        linked.additionalKind ==
        Id3v2LinkedAdditionalIdKind.languageAndDescriptor
    );
    assert(linked.language[] == "eng");
    assert(linked.descriptor == "notes");
}
