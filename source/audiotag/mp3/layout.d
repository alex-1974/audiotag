/++
Read-only composition of the currently recognized MP3 edge metadata layout.

This module combines the existing leading-ID3v2 prefix parser and trailing
ID3v1 suffix locator. The middle region remains opaque and is not claimed to
contain valid MPEG audio.

Suffix inspection is deliberately applied only to the bytes remaining after
the leading ID3v2 envelope has been bounded. This prevents bytes inside a
leading tag from being reclassified as a trailing ID3v1 block.
+/
module audiotag.mp3.layout;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.mp3.prefix :
    Mp3LeadingId3v2Kind,
    parseMp3Prefix;

import audiotag.mp3.suffix :
    locateMp3TrailingId3v1;


/++
Zero-copy view of the currently recognized MP3 edge metadata layout.

`middle` is deliberately opaque. It may contain MPEG audio and, in future,
other metadata systems not yet located by this layer.

When no leading ID3v2 tag is present, `leadingId3v2` is empty at the source
start. When no trailing ID3v1 tag is present, `trailingId3v1` is empty at the
end of `middle`.
+/
struct Mp3Layout
{
    /// Supported leading ID3v2 revision, or `none`.
    Mp3LeadingId3v2Kind leadingId3v2Kind;

    /// Complete leading ID3v2 envelope, or an empty source-start span.
    ByteSpan leadingId3v2;

    /// Bytes between the recognized leading and trailing metadata regions.
    ByteSpan middle;

    /// Whether the source ends with a fixed ID3v1 `TAG` block.
    bool hasTrailingId3v1;

    /// Exact trailing 128-byte ID3v1 block, or an empty end-position span.
    ByteSpan trailingId3v1;
}


/++
Composes the MP3 prefix and suffix locators into one bounded layout.

The leading ID3v2 parser runs first because malformed or unsupported ID3v2
input is a structured parse error. ID3v1 absence is not an error.

The suffix locator receives only the prefix remainder, so recognized edge
regions cannot overlap.
+/
ParseResult!Mp3Layout
parseMp3Layout(
    ByteSpan source
)
    @safe pure nothrow @nogc
{
    auto prefixResult =
        parseMp3Prefix(source);

    if (prefixResult.hasError)
    {
        return
            ParseResult!Mp3Layout
                .failure(
                    prefixResult.error
                );
    }

    const prefix =
        prefixResult.value;

    const suffix =
        locateMp3TrailingId3v1(
            prefix.remainder
        );

    return
        ParseResult!Mp3Layout
            .success(
                Mp3Layout(
                    prefix.id3v2Kind,
                    prefix.leadingId3v2,
                    suffix.remainder,
                    suffix.hasTrailingId3v1,
                    suffix.trailingId3v1
                )
            );
}


/// Untagged bytes remain entirely in the opaque middle region.
unittest
{
    const ubyte[] source = [0xFF, 0xFB, 0x90, 0x64];

    auto result = parseMp3Layout(ByteSpan(source, 100));
    assert(result.hasValue);

    const layout = result.value;
    assert(layout.leadingId3v2Kind == Mp3LeadingId3v2Kind.none);
    assert(layout.leadingId3v2.empty);
    assert(layout.leadingId3v2.sourceOffset == 100);
    assert(layout.middle.data == source);
    assert(layout.middle.sourceOffset == 100);
    assert(!layout.hasTrailingId3v1);
    assert(layout.trailingId3v1.empty);
    assert(layout.trailingId3v1.sourceOffset == 104);
}


/// Leading and trailing tags are composed around the opaque middle.
unittest
{
    ubyte[142] source;

    source[0] = 'I';
    source[1] = 'D';
    source[2] = '3';
    source[3] = 0x03;
    source[4] = 0x00;
    source[5] = 0x00;
    source[6] = 0x00;
    source[7] = 0x00;
    source[8] = 0x00;
    source[9] = 0x00;

    source[10] = 0xFF;
    source[11] = 0xFB;
    source[12] = 0x90;
    source[13] = 0x64;

    source[14] = 'T';
    source[15] = 'A';
    source[16] = 'G';

    auto result =
        parseMp3Layout(
            ByteSpan(
                source[],
                1000
            )
        );

    assert(result.hasValue);

    const layout = result.value;
    assert(layout.leadingId3v2Kind == Mp3LeadingId3v2Kind.v23);
    assert(layout.leadingId3v2.length == 10);
    assert(layout.leadingId3v2.sourceOffset == 1000);
    assert(layout.middle.length == 4);
    assert(layout.middle.sourceOffset == 1010);
    assert(layout.hasTrailingId3v1);
    assert(layout.trailingId3v1.length == 128);
    assert(layout.trailingId3v1.sourceOffset == 1014);
}


/// A trailing ID3v1 tag is located even when no leading ID3v2 is present.
unittest
{
    ubyte[132] source;

    source[0] = 0xFF;
    source[1] = 0xFB;
    source[2] = 0x90;
    source[3] = 0x64;
    source[4] = 'T';
    source[5] = 'A';
    source[6] = 'G';

    auto result = parseMp3Layout(ByteSpan(source[], 2000));
    assert(result.hasValue);

    const layout = result.value;
    assert(layout.leadingId3v2Kind == Mp3LeadingId3v2Kind.none);
    assert(layout.leadingId3v2.empty);
    assert(layout.middle.length == 4);
    assert(layout.middle.sourceOffset == 2000);
    assert(layout.hasTrailingId3v1);
    assert(layout.trailingId3v1.sourceOffset == 2004);
}


/// TAG bytes inside a leading ID3v2 body cannot become a suffix.
unittest
{
    ubyte[138] source;

    source[0] = 'I';
    source[1] = 'D';
    source[2] = '3';
    source[3] = 0x03;
    source[4] = 0x00;
    source[5] = 0x00;

    // Synchsafe tag size = 128.
    source[6] = 0x00;
    source[7] = 0x00;
    source[8] = 0x01;
    source[9] = 0x00;

    source[10] = 'T';
    source[11] = 'A';
    source[12] = 'G';

    auto result = parseMp3Layout(ByteSpan(source[], 3000));
    assert(result.hasValue);

    const layout = result.value;
    assert(layout.leadingId3v2Kind == Mp3LeadingId3v2Kind.v23);
    assert(layout.leadingId3v2.length == 138);
    assert(layout.middle.empty);
    assert(layout.middle.sourceOffset == 3138);
    assert(!layout.hasTrailingId3v1);
    assert(layout.trailingId3v1.empty);
    assert(layout.trailingId3v1.sourceOffset == 3138);
}


/// Leading-ID3v2 parse errors are propagated unchanged.
unittest
{
    const ubyte[] source =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x03,
            0xAA
        ];

    auto result = parseMp3Layout(ByteSpan(source, 4000));
    assert(result.hasError);
    assert(result.error.offset == 4010);
    assert(result.error.requested == 3);
    assert(result.error.available == 1);
}
