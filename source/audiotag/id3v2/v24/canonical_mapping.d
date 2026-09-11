/++
ID3v2.4 names for the shared ID3v2 canonical-mapping outcome types.

The mapping outcome contract is revision-independent; revision-specific frame
mappers retain these established public names as aliases.
+/
module audiotag.id3v2.v24.canonical_mapping;

import audiotag.id3v2.common.canonical_mapping :
    Id3v2CanonicalMappingResult,
    Id3v2CanonicalMappingStatus;


/++
Backward-compatible ID3v2.4 name for the shared canonical-mapping status.
+/
alias Id3v24CanonicalMappingStatus =
    Id3v2CanonicalMappingStatus;


/++
Backward-compatible ID3v2.4 name for the shared canonical-mapping result.
+/
alias Id3v24CanonicalMappingResult =
    Id3v2CanonicalMappingResult;
