/++
Shared canonical picture-role mapping across ID3v2 revisions.

ID3v2.2 `PIC` and ID3v2.3/v2.4 `APIC` use the same picture-type byte
semantics. Canonical role names must therefore be identical across revisions.

Revision-specific modules retain their public lookup/type names as compatibility
aliases to this registry.
+/
module audiotag.id3v2.common.picture_role;

import audiotag.id3v2.common.picture :
    Id3v2PictureType;


/++
One canonical ID3v2 picture-role definition.
+/
struct Id3v2PictureRoleDefinition
{
    /// Stable canonical `pictureRole` qualifier value.
    string name;

    /// Shared native ID3v2 picture type.
    Id3v2PictureType pictureType;
}


/++
Result of looking up one canonical ID3v2 picture role.

`definition` is meaningful only when `found` is true.
+/
struct Id3v2PictureRoleLookup
{
    bool found;
    Id3v2PictureRoleDefinition definition;
}


/++
Complete ID3v2 picture-role registry.
+/
private immutable Id3v2PictureRoleDefinition[] definitions =
[
    Id3v2PictureRoleDefinition("other", Id3v2PictureType.other),
    Id3v2PictureRoleDefinition("fileIcon", Id3v2PictureType.fileIcon),
    Id3v2PictureRoleDefinition("otherFileIcon", Id3v2PictureType.otherFileIcon),
    Id3v2PictureRoleDefinition("frontCover", Id3v2PictureType.frontCover),
    Id3v2PictureRoleDefinition("backCover", Id3v2PictureType.backCover),
    Id3v2PictureRoleDefinition("leafletPage", Id3v2PictureType.leafletPage),
    Id3v2PictureRoleDefinition("media", Id3v2PictureType.media),
    Id3v2PictureRoleDefinition("leadArtist", Id3v2PictureType.leadArtist),
    Id3v2PictureRoleDefinition("artist", Id3v2PictureType.artist),
    Id3v2PictureRoleDefinition("conductor", Id3v2PictureType.conductor),
    Id3v2PictureRoleDefinition("band", Id3v2PictureType.band),
    Id3v2PictureRoleDefinition("composer", Id3v2PictureType.composer),
    Id3v2PictureRoleDefinition("lyricist", Id3v2PictureType.lyricist),
    Id3v2PictureRoleDefinition(
        "recordingLocation",
        Id3v2PictureType.recordingLocation
    ),
    Id3v2PictureRoleDefinition(
        "duringRecording",
        Id3v2PictureType.duringRecording
    ),
    Id3v2PictureRoleDefinition(
        "duringPerformance",
        Id3v2PictureType.duringPerformance
    ),
    Id3v2PictureRoleDefinition(
        "videoCapture",
        Id3v2PictureType.videoCapture
    ),
    Id3v2PictureRoleDefinition(
        "brightColouredFish",
        Id3v2PictureType.brightColouredFish
    ),
    Id3v2PictureRoleDefinition(
        "illustration",
        Id3v2PictureType.illustration
    ),
    Id3v2PictureRoleDefinition(
        "artistLogotype",
        Id3v2PictureType.artistLogotype
    ),
    Id3v2PictureRoleDefinition(
        "publisherLogotype",
        Id3v2PictureType.publisherLogotype
    )
];


/++
Looks up one native picture type by stable canonical role name.
+/
Id3v2PictureRoleLookup
findId3v2PictureRole(
    string name
)
    @safe
{
    foreach (definition; definitions)
    {
        if (definition.name == name)
        {
            return
                Id3v2PictureRoleLookup(
                    true,
                    definition
                );
        }
    }

    return Id3v2PictureRoleLookup.init;
}


/++
Looks up the stable canonical role for one native picture type.
+/
Id3v2PictureRoleLookup
findId3v2PictureRole(
    Id3v2PictureType pictureType
)
    @safe
{
    foreach (definition; definitions)
    {
        if (definition.pictureType == pictureType)
        {
            return
                Id3v2PictureRoleLookup(
                    true,
                    definition
                );
        }
    }

    return Id3v2PictureRoleLookup.init;
}


/// Every defined native picture type round-trips through its role name.
unittest
{
    foreach (raw; 0 .. 0x15)
    {
        const pictureType =
            cast(Id3v2PictureType) raw;

        const byType =
            findId3v2PictureRole(
                pictureType
            );

        assert(byType.found);

        const byName =
            findId3v2PictureRole(
                byType.definition.name
            );

        assert(byName.found);
        assert(byName.definition.pictureType == pictureType);
        assert(byName.definition.name == byType.definition.name);
    }
}


/// Stable canonical role names retain their native values.
unittest
{
    const front =
        findId3v2PictureRole(
            "frontCover"
        );

    assert(front.found);
    assert(
        front.definition.pictureType ==
        Id3v2PictureType.frontCover
    );

    const publisher =
        findId3v2PictureRole(
            "publisherLogotype"
        );

    assert(publisher.found);
    assert(
        publisher.definition.pictureType ==
        Id3v2PictureType.publisherLogotype
    );
}


/// Unknown canonical role names receive no native fallback.
unittest
{
    const result =
        findId3v2PictureRole(
            "futurePictureRole"
        );

    assert(!result.found);
}


/// Undefined native picture types receive no canonical fallback.
unittest
{
    const result =
        findId3v2PictureRole(
            cast(Id3v2PictureType) 0x15
        );

    assert(!result.found);
}
