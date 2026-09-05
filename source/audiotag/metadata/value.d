/++
Format-independent canonical metadata value types.

The canonical metadata layer owns semantic values independently of
the lifetime of parser input buffers. Native byte ranges therefore do
not appear in this module; source provenance is represented separately.

`MetadataValue` is a discriminated union of the initial canonical
value families required by the metadata tree.
+/
module audiotag.metadata.value;

import std.sumtype :
    SumType,
    match;


/++
Canonical scalar text.
+/
struct MetadataText
{
    /// Decoded Unicode text.
    string value;
}


/++
Canonical ordered multi-value text.

The distinction between one text value and an ordered list of values
is preserved explicitly rather than being inferred from separators.
+/
struct MetadataTextList
{
    /// Decoded values in their semantic order.
    string[] values;
}


/++
Canonical integer value.

A signed 64-bit representation provides one simple initial integer
domain. More specialized numeric structures may be added later where
metadata semantics require them.
+/
struct MetadataInteger
{
    /// Integer value.
    long value;
}


/++
Canonical URL value.

No URL syntax validation is implied by this type. It distinguishes a
URL semantically from ordinary text while preserving the decoded
string exactly.
+/
struct MetadataUrl
{
    /// Decoded URL.
    string value;
}


/++
Owned canonical binary value.

Binary canonical metadata must not depend on the lifetime of a parser
input buffer. Construction through `copyFrom` duplicates source bytes
into immutable storage.

`mediaType` is optional. It may describe payloads such as embedded
image data while remaining empty for opaque binary metadata such as
private identifiers.
+/
struct MetadataBinary
{
    private immutable(ubyte)[] _data;

    /// Optional media type associated with the binary payload.
    string mediaType;

    /++
    Creates an owned immutable copy of binary metadata.

    Params:
        data = Bytes to copy.
        mediaType = Optional media type.

    Returns:
        Independent canonical binary value.
    +/
    static MetadataBinary copyFrom(
        const(ubyte)[] data,
        string mediaType = ""
    )
        @safe
    {
        return MetadataBinary(
            data.idup,
            mediaType
        );
    }

    /++
    Returns the immutable binary payload.
    +/
    @property
    const(ubyte)[] data() const
        @safe pure nothrow @nogc
    {
        return _data;
    }

    /++
    Returns the binary payload length.
    +/
    @property
    size_t length() const
        @safe pure nothrow @nogc
    {
        return _data.length;
    }

    /++
    Returns whether the binary payload is empty.
    +/
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return _data.length == 0;
    }

    private this(
        immutable(ubyte)[] data,
        string mediaType
    )
        @safe pure nothrow @nogc
    {
        _data = data;
        this.mediaType = mediaType;
    }
}


/++
Source of canonical picture content.

An image may either contain embedded binary data or refer to an
external URL. The distinction is semantic and therefore belongs in
the canonical value model.
+/
alias MetadataPictureSource =
    SumType!(
        MetadataBinary,
        MetadataUrl
    );


/++
Canonical picture/artwork value.

Picture role, scope and other qualifiers intentionally do not belong
to this initial value object. They can be represented by the
surrounding canonical field/qualifier model without making image bytes
ID3-specific.
+/
struct MetadataPicture
{
    /// Human-readable image description, if present.
    string description;

    /// Embedded binary data or linked image URL.
    MetadataPictureSource source;
}


/++
Canonical metadata value.

Wrapper structs intentionally distinguish values that share the same
underlying D representation. In particular, ordinary text and URLs
are not interchangeable merely because both contain `string`.
+/
alias MetadataValue =
    SumType!(
        MetadataText,
        MetadataTextList,
        MetadataInteger,
        MetadataUrl,
        MetadataBinary,
        MetadataPicture
    );


/// Scalar text remains distinguishable from other string-like values.
unittest
{
    MetadataValue value =
        MetadataText("Track title");

    const isText =
        value.match!(
            (MetadataText text) =>
                text.value == "Track title",
            _ => false
        );

    assert(isText);
}


/// Ordered text lists retain multiplicity and ordering.
unittest
{
    MetadataValue value =
        MetadataTextList(
            ["one", "two", "three"]
        );

    const matches =
        value.match!(
            (MetadataTextList list) =>
                list.values ==
                ["one", "two", "three"],
            _ => false
        );

    assert(matches);
}


/// Integer metadata remains a distinct canonical value type.
unittest
{
    MetadataValue value =
        MetadataInteger(42);

    const matches =
        value.match!(
            (MetadataInteger integer) =>
                integer.value == 42,
            _ => false
        );

    assert(matches);
}


/// URLs remain semantically distinct from ordinary text.
unittest
{
    MetadataValue value =
        MetadataUrl("https://example.invalid/item");

    const isUrl =
        value.match!(
            (MetadataUrl url) =>
                url.value ==
                "https://example.invalid/item",
            _ => false
        );

    assert(isUrl);
}


/// Canonical binary data is copied away from mutable source storage.
unittest
{
    ubyte[] source =
        [0x01, 0x02, 0x03];

    auto binary =
        MetadataBinary.copyFrom(
            source,
            "application/octet-stream"
        );

    assert(binary.length == 3);
    assert(!binary.empty);

    assert(
        binary.data ==
        [0x01, 0x02, 0x03]
    );

    assert(
        binary.mediaType ==
        "application/octet-stream"
    );

    source[0] = 0xFF;

    assert(binary.data[0] == 0x01);
}


/// Empty binary metadata is a valid owned value.
unittest
{
    const ubyte[] source = [];

    auto binary =
        MetadataBinary.copyFrom(source);

    assert(binary.empty);
    assert(binary.length == 0);
    assert(binary.mediaType.length == 0);
}


/// Pictures may contain embedded binary image data.
unittest
{
    auto binary =
        MetadataBinary.copyFrom(
            [
                cast(ubyte) 0xFF,
                cast(ubyte) 0xD8,
                cast(ubyte) 0xFF,
                cast(ubyte) 0xD9
            ],
            "image/jpeg"
        );

    MetadataPictureSource source =
        binary;

    MetadataValue value =
        MetadataPicture(
            "Front cover",
            source
        );

    const matches =
        value.match!(
            (MetadataPicture picture) =>
                picture.description == "Front cover" &&
                picture.source.match!(
                    (MetadataBinary data) =>
                        data.mediaType == "image/jpeg" &&
                        data.length == 4,
                    _ => false
                ),
            _ => false
        );

    assert(matches);
}


/// Pictures may alternatively refer to an external image URL.
unittest
{
    MetadataPictureSource source =
        MetadataUrl(
            "https://example.invalid/cover.jpg"
        );

    MetadataValue value =
        MetadataPicture(
            "",
            source
        );

    const matches =
        value.match!(
            (MetadataPicture picture) =>
                picture.source.match!(
                    (MetadataUrl url) =>
                        url.value ==
                        "https://example.invalid/cover.jpg",
                    _ => false
                ),
            _ => false
        );

    assert(matches);
}
