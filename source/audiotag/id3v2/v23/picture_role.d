/++
ID3v2.3 compatibility names for the shared ID3v2 canonical picture-role
registry.

The native picture-type semantics are shared by ID3v2.2, v2.3 and v2.4.
+/
module audiotag.id3v2.v23.picture_role;

import audiotag.id3v2.common.picture_role :
    Id3v2PictureRoleDefinition,
    Id3v2PictureRoleLookup,
    findId3v2PictureRole;


/++
Backward-compatible ID3v2.3 name for one shared picture-role definition.
+/
alias Id3v23PictureRoleDefinition =
    Id3v2PictureRoleDefinition;


/++
Backward-compatible ID3v2.3 name for one shared picture-role lookup result.
+/
alias Id3v23PictureRoleLookup =
    Id3v2PictureRoleLookup;


/++
Backward-compatible ID3v2.3 name for the shared picture-role lookup overload
set.
+/
alias findId3v23PictureRole =
    findId3v2PictureRole;
