/++
ID3v2.2 names for the shared ID3v2 canonical picture-role registry.
+/
module audiotag.id3v2.v22.picture_role;

import audiotag.id3v2.common.picture_role :
    Id3v2PictureRoleDefinition,
    Id3v2PictureRoleLookup,
    findId3v2PictureRole;


/++
ID3v2.2 name for one shared picture-role definition.
+/
alias Id3v22PictureRoleDefinition =
    Id3v2PictureRoleDefinition;


/++
ID3v2.2 name for one shared picture-role lookup result.
+/
alias Id3v22PictureRoleLookup =
    Id3v2PictureRoleLookup;


/++
ID3v2.2 name for the shared picture-role lookup overload set.
+/
alias findId3v22PictureRole =
    findId3v2PictureRole;
