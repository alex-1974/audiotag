# Format support

This file distinguishes **implemented**, **legacy proof-of-concept**, **planned**, and **future** support.

Legend:

- **Core** — active implementation in the new architecture
- **POC** — experimental legacy implementation; not production-ready
- **Planned** — part of the intended main roadmap
- **Future** — architecture should support it, but no near-term implementation commitment
- **—** — not implemented

| File/container | Metadata/tag system | Read | Write | Status / notes |
|---|---|---:|---:|---|
| MPEG Audio / MP3 | ID3v2.4 | Core | — | Strict bounded structural parser plus initial semantic codecs (`T***`, `TXXX`, `W***`, `WXXX`, `COMM`, `USLT`, `APIC`, `PRIV`, `UFID`); canonical model, writer and broader recovery behavior pending |
| MPEG Audio / MP3 | ID3v2.3 | POC | — | Legacy parser reads header but applies incomplete version-specific rules |
| MPEG Audio / MP3 | ID3v2.2 | — | — | Planned |
| MPEG Audio / MP3 | ID3v1 | — | — | Planned |
| MPEG Audio / MP3 | APEv2 | — | — | Planned |
| MPEG Audio / MP3 | Lyrics3 | — | — | Lower-priority legacy support |
| FLAC | native metadata blocks | signature POC | — | Planned |
| FLAC | Vorbis Comment | — | — | Planned |
| FLAC | PICTURE | — | — | Planned |
| Ogg/Vorbis | Ogg container | signature POC | — | Planned |
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
