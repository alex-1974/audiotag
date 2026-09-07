/++
Shared ID3v2.3 attached-picture role mapping.

The native APIC picture-type byte is represented canonically by the
`pictureRole` qualifier.

This module owns the stable bidirectional mapping so canonical
projection, write planning and later serialization use exactly the same
role names.
+/
module audiotag.id3v2.v23.picture_role;

import audiotag.id3v2.v23.attached_picture :
    Id3v23PictureType;


/++
One canonical APIC picture-role definition.
+/
struct Id3v23PictureRoleDefinition
{
    /// Stable canonical qualifier value.
    string name;

    /// Native ID3v2.3 APIC picture type.
    Id3v23PictureType pictureType;
}


/++
Result of looking up one APIC picture role.

`definition` is meaningful only when `found` is true.
+/
struct Id3v23PictureRoleLookup
{
    bool found;
    Id3v23PictureRoleDefinition definition;
}


/++
Complete ID3v2.3 APIC picture-role registry.

The canonical names intentionally match the current v2.3 projection
names.
+/
private immutable Id3v23PictureRoleDefinition[] definitions =
[
    Id3v23PictureRoleDefinition(
        "other",
        Id3v23PictureType.other
    ),
    Id3v23PictureRoleDefinition(
        "fileIcon",
        Id3v23PictureType.fileIcon
    ),
    Id3v23PictureRoleDefinition(
        "otherFileIcon",
        Id3v23PictureType.otherFileIcon
    ),
    Id3v23PictureRoleDefinition(
        "frontCover",
        Id3v23PictureType.frontCover
    ),
    Id3v23PictureRoleDefinition(
        "backCover",
        Id3v23PictureType.backCover
    ),
    Id3v23PictureRoleDefinition(
        "leafletPage",
        Id3v23PictureType.leafletPage
    ),
    Id3v23PictureRoleDefinition(
        "media",
        Id3v23PictureType.media
    ),
    Id3v23PictureRoleDefinition(
        "leadArtist",
        Id3v23PictureType.leadArtist
    ),
    Id3v23PictureRoleDefinition(
        "artist",
        Id3v23PictureType.artist
    ),
    Id3v23PictureRoleDefinition(
        "conductor",
        Id3v23PictureType.conductor
    ),
    Id3v23PictureRoleDefinition(
        "band",
        Id3v23PictureType.band
    ),
    Id3v23PictureRoleDefinition(
        "composer",
        Id3v23PictureType.composer
    ),
    Id3v23PictureRoleDefinition(
        "lyricist",
        Id3v23PictureType.lyricist
    ),
    Id3v23PictureRoleDefinition(
        "recordingLocation",
        Id3v23PictureType.recordingLocation
    ),
    Id3v23PictureRoleDefinition(
        "duringRecording",
        Id3v23PictureType.duringRecording
    ),
    Id3v23PictureRoleDefinition(
        "duringPerformance",
        Id3v23PictureType.duringPerformance
    ),
    Id3v23PictureRoleDefinition(
        "videoCapture",
        Id3v23PictureType.videoCapture
    ),
    Id3v23PictureRoleDefinition(
        "brightColouredFish",
        Id3v23PictureType.brightColouredFish
    ),
    Id3v23PictureRoleDefinition(
        "illustration",
        Id3v23PictureType.illustration
    ),
    Id3v23PictureRoleDefinition(
        "artistLogotype",
        Id3v23PictureType.artistLogotype
    ),
    Id3v23PictureRoleDefinition(
        "publisherLogotype",
        Id3v23PictureType.publisherLogotype
    )
];


/++
Looks up one canonical `pictureRole` value.

Unknown canonical role names remain explicit lookup failures.
+/
Id3v23PictureRoleLookup
findId3v23PictureRole(
    string name
)
    @safe
{
    foreach (
        definition;
        definitions
    )
    {
        if (
            definition.name ==
            name
        )
        {
            return
                Id3v23PictureRoleLookup(
                    true,
                    definition
                );
        }
    }


    return
        Id3v23PictureRoleLookup.init;
}


/++
Looks up the canonical role corresponding to one native APIC picture
type.

Invalid enum values remain explicit lookup failures.
+/
Id3v23PictureRoleLookup
findId3v23PictureRole(
    Id3v23PictureType pictureType
)
    @safe
{
    foreach (
        definition;
        definitions
    )
    {
        if (
            definition.pictureType ==
            pictureType
        )
        {
            return
                Id3v23PictureRoleLookup(
                    true,
                    definition
                );
        }
    }


    return
        Id3v23PictureRoleLookup.init;
}


/// Every defined ID3v2.3 picture type round-trips through its role name.
unittest
{
    foreach (
        raw;
        0 ..
        0x15
    )
    {
        const pictureType =
            cast(Id3v23PictureType)
                raw;


        const byType =
            findId3v23PictureRole(
                pictureType
            );


        assert(
            byType.found
        );


        const byName =
            findId3v23PictureRole(
                byType.definition.name
            );


        assert(
            byName.found
        );


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


/// Stable canonical role names retain their native values.
unittest
{
    const front =
        findId3v23PictureRole(
            "frontCover"
        );


    assert(
        front.found
    );


    assert(
        front.definition.pictureType ==
        Id3v23PictureType.frontCover
    );


    const publisher =
        findId3v23PictureRole(
            "publisherLogotype"
        );


    assert(
        publisher.found
    );


    assert(
        publisher.definition.pictureType ==
        Id3v23PictureType.publisherLogotype
    );
}


/// Unknown canonical picture roles receive no native fallback.
unittest
{
    const result =
        findId3v23PictureRole(
            "futurePictureRole"
        );


    assert(
        !result.found
    );
}


/// Undefined native picture types receive no canonical fallback.
unittest
{
    const result =
        findId3v23PictureRole(
            cast(Id3v23PictureType)
                0x15
        );


    assert(
        !result.found
    );
}
