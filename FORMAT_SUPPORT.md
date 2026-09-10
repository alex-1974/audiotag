# Format support

This file distinguishes **implemented**, **planned**, and **future** support.

Legend:

- **Core** — active implementation in the current architecture
- **Planned** — part of the intended main roadmap
- **Future** — architecture should support it, but no near-term implementation commitment
- **—** — not implemented

| File/container | Metadata/tag system | Read | Write | Status / notes |
|---|---|---:|---:|---|
| MPEG Audio / MP3 | ID3v2.4 | Core | Core | Active bounded parser, canonical mapping, complete tag codec writer and POSIX path-based leading-ID3v2 insertion/replacement/removal; MPEG audio remainder is preserved opaquely rather than validated |
| MPEG Audio / MP3 | ID3v2.3 | Core | Core | Active bounded parser, canonical mapping, complete tag codec writer with whole-tag unsynchronisation and extended-header CRC support, plus POSIX path-based leading-ID3v2 insertion/replacement/removal; MPEG audio remainder is preserved opaquely rather than validated |
| MPEG Audio / MP3 | ID3v2.2 | — | — | Planned |
| MPEG Audio / MP3 | ID3v1 | Core | — | Raw fixed-size ID3v1.0/ID3v1.1 tag parser, strict ISO-8859-1 text decoding, canonical title/artist/album/comment plus ID3v1.1 track projection and zero-copy MP3 trailing-tag locator; year/genre canonical semantics and writer still pending |
| MPEG Audio / MP3 | APEv2 | — | — | Planned |
| MPEG Audio / MP3 | Lyrics3 | — | — | Lower-priority planned support |
| FLAC | native metadata blocks | — | — | Planned |
| FLAC | Vorbis Comment | — | — | Planned |
| FLAC | PICTURE | — | — | Planned |
| Ogg/Vorbis | Ogg container | — | — | Planned |
| Ogg/Vorbis | Vorbis Comment | — | — | Planned |
| Ogg/Opus | Ogg container | — | — | Planned |
| Ogg/Opus | OpusTags | — | — | Planned |
| APE / WavPack / Musepack | APEv2 | — | — | Planned reusable tag codec |
| MP4 / M4A / M4B | MP4 metadata boxes | — | — | Planned |
| RIFF/WAVE | LIST/INFO | — | — | Future |
| BWF/RF64/BW64 | BWF/ADM-related metadata | — | — | Future |
| AIFF/AIFC | native chunks | — | — | Future |
| ASF/WMA | ASF attributes | — | — | Future |
| Matroska/WebM | Matroska Tags / attachments | — | — | Future |
| DSF | ID3v2 via metadata pointer | — | — | Future; should reuse ID3 codec |
| DSDIFF/DFF | native metadata / ID3 extensions | — | — | Future |
| TrueAudio | ID3/APEv2 | — | — | Future |

## Architecture coverage

The parser core should be proven against structurally different families:

1. **ID3v2.4** — frame-based and encoding-heavy;
2. **FLAC** — strictly length-delimited metadata blocks;
3. **Ogg** — page/packet reconstruction;
4. **MP4** — recursive size-delimited tree.

If the same byte-range core supports these cleanly, it is likely suitable for most later formats.

## Canonical model requirements derived from formats

The common metadata tree must support:

- repeated values;
- ordered values;
- typed values;
- artwork/binary payloads;
- nested metadata;
- scope/target;
- language/locale;
- descriptions/qualifiers;
- unknown fields;
- native provenance;
- recovery confidence and diagnostics.
