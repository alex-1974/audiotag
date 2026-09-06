/++
Shared ID3v2.4 attached-picture role mapping.

The native APIC picture-type byte is represented canonically by the
`pictureRole` qualifier. This module owns the stable bidirectional
mapping so reader projection, planning and serialization use exactly
the same role names.
+/
module audiotag.id3v2.v24.picture_role;

import audiotag.id3v2.v24.attached_picture :
    Id3v24PictureType;


/++
One canonical APIC picture-role definition.
+/
struct Id3v24PictureRoleDefinition
{
    /// Stable canonical qualifier value.
    string name;

    /// Native ID3v2.4 APIC picture type.
    Id3v24PictureType pictureType;
}


/++
Result of looking up an APIC picture role.

`definition` is meaningful only when `found` is true.
+/
struct Id3v24PictureRoleLookup
{
    bool found;
    Id3v24PictureRoleDefinition definition;
}


/++
Complete ID3v2.4 APIC picture-role registry.

The canonical names intentionally match the existing projection names.
+/
private immutable Id3v24PictureRoleDefinition[] definitions =
[
    Id3v24PictureRoleDefinition(
        "other",
        Id3v24PictureType.other
    ),
    Id3v24PictureRoleDefinition(
        "fileIcon",
        Id3v24PictureType.fileIcon
    ),
    Id3v24PictureRoleDefinition(
        "otherFileIcon",
        Id3v24PictureType.otherFileIcon
    ),
    Id3v24PictureRoleDefinition(
        "frontCover",
        Id3v24PictureType.frontCover
    ),
    Id3v24PictureRoleDefinition(
        "backCover",
        Id3v24PictureType.backCover
    ),
    Id3v24PictureRoleDefinition(
        "leafletPage",
        Id3v24PictureType.leafletPage
    ),
    Id3v24PictureRoleDefinition(
        "media",
        Id3v24PictureType.media
    ),
    Id3v24PictureRoleDefinition(
        "leadArtist",
        Id3v24PictureType.leadArtist
    ),
    Id3v24PictureRoleDefinition(
        "artist",
        Id3v24PictureType.artist
    ),
    Id3v24PictureRoleDefinition(
        "conductor",
        Id3v24PictureType.conductor
    ),
    Id3v24PictureRoleDefinition(
        "band",
        Id3v24PictureType.band
    ),
    Id3v24PictureRoleDefinition(
        "composer",
        Id3v24PictureType.composer
    ),
    Id3v24PictureRoleDefinition(
        "lyricist",
        Id3v24PictureType.lyricist
    ),
    Id3v24PictureRoleDefinition(
        "recordingLocation",
        Id3v24PictureType.recordingLocation
    ),
    Id3v24PictureRoleDefinition(
        "duringRecording",
        Id3v24PictureType.duringRecording
    ),
    Id3v24PictureRoleDefinition(
        "duringPerformance",
        Id3v24PictureType.duringPerformance
    ),
    Id3v24PictureRoleDefinition(
        "videoCapture",
        Id3v24PictureType.videoCapture
    ),
    Id3v24PictureRoleDefinition(
        "brightColouredFish",
        Id3v24PictureType.brightColouredFish
    ),
    Id3v24PictureRoleDefinition(
        "illustration",
        Id3v24PictureType.illustration
    ),
    Id3v24PictureRoleDefinition(
        "artistLogotype",
        Id3v24PictureType.artistLogotype
    ),
    Id3v24PictureRoleDefinition(
        "publisherLogotype",
        Id3v24PictureType.publisherLogotype
    )
];


/++
Looks up one canonical `pictureRole` value.

Unknown canonical role names remain explicit lookup failures.
+/
Id3v24PictureRoleLookup
findId3v24PictureRole(
    string name
)
    @safe
{
    foreach (definition; definitions)
    {
        if (definition.name == name)
        {
            return Id3v24PictureRoleLookup(
                true,
                definition
            );
        }
    }

    return Id3v24PictureRoleLookup.init;
}


/++
Looks up the canonical role corresponding to one native APIC picture
type.

Invalid enum values remain explicit lookup failures.
+/
Id3v24PictureRoleLookup
findId3v24PictureRole(
    Id3v24PictureType pictureType
)
    @safe
{
    foreach (definition; definitions)
    {
        if (definition.pictureType == pictureType)
        {
            return Id3v24PictureRoleLookup(
                true,
                definition
            );
        }
    }

    return Id3v24PictureRoleLookup.init;
}


/// Every defined ID3v2.4 picture type round-trips through its role name.
unittest
{
    foreach (raw; 0 .. 0x15)
    {
        const pictureType =
            cast(Id3v24PictureType) raw;

        const byType =
            findId3v24PictureRole(
                pictureType
            );

        assert(byType.found);

        const byName =
            findId3v24PictureRole(
                byType.definition.name
            );

        assert(byName.found);

        assert(
            byName.definition.pictureType ==
            pictureType
        );

        assert(
            byName.definition.name ==
            byType.definition.name
        );
    }
}


/// Known stable canonical role names retain their native values.
unittest
{
    const front =
        findId3v24PictureRole(
            "frontCover"
        );

    assert(front.found);

    assert(
        front.definition.pictureType ==
        Id3v24PictureType.frontCover
    );

    const publisher =
        findId3v24PictureRole(
            "publisherLogotype"
        );

    assert(publisher.found);

    assert(
        publisher.definition.pictureType ==
        Id3v24PictureType.publisherLogotype
    );
}


/// Unknown canonical picture-role values do not receive a fallback.
unittest
{
    const result =
        findId3v24PictureRole(
            "futurePictureRole"
        );

    assert(!result.found);
}


/// Undefined native APIC picture types do not receive a canonical role.
unittest
{
    const result =
        findId3v24PictureRole(
            cast(Id3v24PictureType) 0x15
        );

    assert(!result.found);
}
