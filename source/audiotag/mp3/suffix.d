/++
Zero-copy location of a trailing ID3v1 tag inside an MP3 byte source.

ID3v1 is physically identified by a fixed 128-byte block at the end of the
file whose first three bytes are `TAG`. This module owns only that container
placement rule. It does not parse ID3v1 fields; callers may pass
`trailingId3v1` to `audiotag.id3v1.parseId3v1Tag()`.

Absence of a trailing ID3v1 block is a normal result rather than a parse
failure.
+/
module audiotag.mp3.suffix;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v1.tag :
    id3v1TagSize;


/++
Zero-copy split of an MP3 source around an optional trailing ID3v1 block.

When `hasTrailingId3v1` is false, `remainder` is the complete input source and
`trailingId3v1` is an empty span positioned at the end of that source.

When `hasTrailingId3v1` is true, `trailingId3v1` is exactly the final 128
source bytes and `remainder` is every byte before that block.
+/
struct Mp3SuffixLayout
{
    bool hasTrailingId3v1;
    ByteSpan remainder;
    ByteSpan trailingId3v1;
}


/++
Locates one trailing ID3v1 block without parsing its fields.

The function checks only the ID3v1 container-placement invariant:

1. at least 128 source bytes must exist;
2. the first three bytes of the final 128-byte region must equal `TAG`.

No text, revision, track or genre interpretation is performed here.
+/
Mp3SuffixLayout
locateMp3TrailingId3v1(
    ByteSpan source
)
    @safe pure nothrow @nogc
{
    const emptyTrailer =
        source.subspan(
            source.length,
            0
        );

    if (
        source.length <
        id3v1TagSize
    )
    {
        return
            Mp3SuffixLayout(
                false,
                source,
                emptyTrailer
            );
    }

    const candidateOffset =
        source.length -
        id3v1TagSize;

    const candidate =
        source.subspan(
            candidateOffset,
            id3v1TagSize
        );

    const bytes =
        candidate.data;

    if (
        bytes[0] != 'T' ||
        bytes[1] != 'A' ||
        bytes[2] != 'G'
    )
    {
        return
            Mp3SuffixLayout(
                false,
                source,
                emptyTrailer
            );
    }

    return
        Mp3SuffixLayout(
            true,
            source.subspan(
                0,
                candidateOffset
            ),
            candidate
        );
}


/// Sources shorter than one ID3v1 block cannot contain a trailing tag.
unittest
{
    const ubyte[] source =
        [
            0xFF,
            0xFB,
            0x90,
            0x64
        ];

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(
                source,
                100
            )
        );

    assert(!layout.hasTrailingId3v1);
    assert(layout.remainder.data == source);
    assert(layout.remainder.sourceOffset == 100);
    assert(layout.trailingId3v1.empty);
    assert(layout.trailingId3v1.sourceOffset == 104);
}


/// An exact 128-byte source without TAG remains wholly in the remainder.
unittest
{
    ubyte[128] source;

    source[0] = 'B';
    source[1] = 'A';
    source[2] = 'D';

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(
                source[],
                200
            )
        );

    assert(!layout.hasTrailingId3v1);
    assert(layout.remainder.length == 128);
    assert(layout.remainder.sourceOffset == 200);
    assert(layout.trailingId3v1.empty);
    assert(layout.trailingId3v1.sourceOffset == 328);
}


/// An exact 128-byte TAG block is entirely classified as trailing ID3v1.
unittest
{
    ubyte[128] source;

    source[0] = 'T';
    source[1] = 'A';
    source[2] = 'G';
    source[127] = 13;

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(
                source[],
                300
            )
        );

    assert(layout.hasTrailingId3v1);
    assert(layout.remainder.empty);
    assert(layout.remainder.sourceOffset == 300);
    assert(layout.trailingId3v1.length == 128);
    assert(layout.trailingId3v1.sourceOffset == 300);
    assert(layout.trailingId3v1.data[127] == 13);
}


/// A trailing TAG block is split from all bytes that precede it.
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
    source[131] = 17;

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(
                source[],
                1000
            )
        );

    assert(layout.hasTrailingId3v1);
    assert(layout.remainder.length == 4);
    assert(layout.remainder.sourceOffset == 1000);

    assert(
        layout.remainder.data ==
        [
            0xFF,
            0xFB,
            0x90,
            0x64
        ]
    );

    assert(layout.trailingId3v1.length == 128);
    assert(layout.trailingId3v1.sourceOffset == 1004);
    assert(layout.trailingId3v1.data[0] == 'T');
    assert(layout.trailingId3v1.data[1] == 'A');
    assert(layout.trailingId3v1.data[2] == 'G');
    assert(layout.trailingId3v1.data[127] == 17);
}


/// TAG bytes elsewhere do not create an ID3v1 suffix.
unittest
{
    ubyte[132] source;

    source[0] = 'T';
    source[1] = 'A';
    source[2] = 'G';

    // The actual final 128-byte candidate begins at index 4.
    source[4] = 'N';
    source[5] = 'O';
    source[6] = 'T';

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(
                source[],
                2000
            )
        );

    assert(!layout.hasTrailingId3v1);
    assert(layout.remainder.length == source.length);
    assert(layout.remainder.sourceOffset == 2000);
    assert(layout.trailingId3v1.empty);
    assert(layout.trailingId3v1.sourceOffset == 2132);
}


/// Located suffix spans remain zero-copy views of the source storage.
unittest
{
    ubyte[128] source;

    source[0] = 'T';
    source[1] = 'A';
    source[2] = 'G';
    source[3] = 'A';

    const layout =
        locateMp3TrailingId3v1(
            ByteSpan(source[])
        );

    assert(layout.hasTrailingId3v1);
    assert(layout.trailingId3v1.data[3] == 'A');

    source[3] = 'B';

    assert(layout.trailingId3v1.data[3] == 'B');
}
