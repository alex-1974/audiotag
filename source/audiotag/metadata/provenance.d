/++
Format-independent provenance for canonical metadata.

Canonical metadata must retain enough information to identify where a
value originated without depending on the lifetime of the original
input buffer.

The provenance layer therefore stores source coordinates and native
identifiers as values rather than retaining `ByteSpan` references.
+/
module audiotag.metadata.provenance;


/++
Metadata/tag system from which a canonical value originated.

This identifies the metadata codec, not the enclosing audio container.
For example, an ID3v2 tag may occur in MPEG Audio or another format.
+/
enum MetadataSystem : ubyte
{
    /// Source system has not been identified.
    unknown,

    /// ID3 version 2 metadata.
    id3v2,

    /// ID3 version 1 metadata.
    id3v1,

    /// Vorbis Comment metadata.
    vorbisComment,

    /// APEv2 metadata.
    apev2,

    /// MP4 / QuickTime metadata.
    mp4,

    /// RIFF INFO metadata.
    riffInfo,

    /// Matroska Tags metadata.
    matroska
}


/++
Confidence with which a canonical value represents its native source.

Exact values come directly from valid source data. Recovered values
were obtained through deterministic tolerant parsing. Guessed values
require heuristic interpretation and must never be presented as exact.
+/
enum MetadataConfidence : ubyte
{
    /// Value directly reflects valid source metadata.
    exact,

    /// Value was deterministically recovered from malformed input.
    recovered,

    /// Value depends on an explicit heuristic interpretation.
    guessed
}


/++
Identifies the native metadata field or frame from which a canonical
value originated.

`identifier` deliberately remains a string because native identifier
shapes vary between metadata systems:

- ID3v2 uses identifiers such as `TIT2`;
- Vorbis Comment uses keys such as `ARTIST`;
- MP4 may use atom/key names;
- other systems may use textual names of different lengths.

The metadata system provides the namespace.
+/
struct NativeMetadataIdentifier
{
    /// Metadata system defining the identifier namespace.
    MetadataSystem system;

    /// Native field/frame/key identifier.
    string identifier;
}


/++
Source provenance attached to a canonical metadata value.

Offsets identify the physical region in the original byte source.
No ownership or lifetime relationship with that source is retained.

A zero `sourceLength` is valid for provenance that refers to a point
rather than a non-empty source region.
+/
struct MetadataProvenance
{
    /// Native metadata field/frame/key.
    NativeMetadataIdentifier native;

    /// Absolute byte offset in the original source.
    size_t sourceOffset;

    /// Number of physical source bytes associated with this provenance.
    size_t sourceLength;

    /// Confidence of the canonical interpretation.
    MetadataConfidence confidence = MetadataConfidence.exact;

    /++
    Returns the first source offset immediately after this provenance.

    The caller must ensure that construction did not overflow
    `sourceOffset + sourceLength`; parser/mapping code operating on
    untrusted lengths is responsible for structured overflow handling.
    +/
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return sourceOffset + sourceLength;
    }
}


/// Native identifiers retain their metadata-system namespace.
unittest
{
    const id =
        NativeMetadataIdentifier(
            MetadataSystem.id3v2,
            "TIT2"
        );

    assert(id.system == MetadataSystem.id3v2);
    assert(id.identifier == "TIT2");
}


/// Exact provenance is the default confidence.
unittest
{
    const provenance =
        MetadataProvenance(
            NativeMetadataIdentifier(
                MetadataSystem.id3v2,
                "TIT2"
            ),
            100,
            24
        );

    assert(provenance.sourceOffset == 100);
    assert(provenance.sourceLength == 24);
    assert(provenance.endOffset == 124);
    assert(provenance.confidence == MetadataConfidence.exact);
}


/// Recovery confidence remains explicit.
unittest
{
    const provenance =
        MetadataProvenance(
            NativeMetadataIdentifier(
                MetadataSystem.vorbisComment,
                "ARTIST"
            ),
            500,
            12,
            MetadataConfidence.recovered
        );

    assert(
        provenance.confidence ==
        MetadataConfidence.recovered
    );
}


/// Zero-length provenance identifies a valid source position.
unittest
{
    const provenance =
        MetadataProvenance(
            NativeMetadataIdentifier(
                MetadataSystem.unknown,
                ""
            ),
            42,
            0
        );

    assert(provenance.sourceOffset == 42);
    assert(provenance.endOffset == 42);
}
