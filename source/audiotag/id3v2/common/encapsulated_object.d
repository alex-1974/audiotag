/++
Shared semantic descriptor for ID3v2 general encapsulated objects.

ID3v2.2 `GEO` and ID3v2.3/v2.4 `GEOB` carry the same semantic descriptor:

- MIME type;
- filename;
- content description.

The encapsulated binary payload, physical text encodings, terminators,
unsynchronisation and raw source spans remain revision-specific native data.
+/
module audiotag.id3v2.common.encapsulated_object;


/++
Revision-independent semantic descriptor of one ID3v2 encapsulated object.

Empty `mimeType` and `filename` values are meaningful because the native
formats explicitly permit those strings to be omitted while retaining their
terminators.

No MIME validation, filename normalization or content interpretation is
performed here.
+/
struct Id3v2EncapsulatedObjectInfo
{
    /// Decoded MIME-type text.
    string mimeType;

    /// Decoded case-sensitive filename.
    string filename;

    /// Decoded content description.
    string description;
}
