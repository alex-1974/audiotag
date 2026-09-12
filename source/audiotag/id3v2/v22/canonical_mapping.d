/++
ID3v2.2 names for the shared ID3v2 canonical-mapping outcome types.

Mapping outcome semantics are revision-independent. ID3v2.2 currently has no
per-frame transformation states, so its mappers normally produce `mapped`,
`unsupportedFrame` or `unrepresentableValueShape`; the shared
`requiresTransformation` state remains available for uniform higher layers.


Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.canonical_mapping;

import audiotag.id3v2.common.canonical_mapping :
    Id3v2CanonicalMappingResult,
    Id3v2CanonicalMappingStatus;


/++
ID3v2.2 public name for the shared canonical-mapping status.
+/
alias Id3v22CanonicalMappingStatus =
    Id3v2CanonicalMappingStatus;


/++
ID3v2.2 public name for the shared canonical-mapping result.
+/
alias Id3v22CanonicalMappingResult =
    Id3v2CanonicalMappingResult;
