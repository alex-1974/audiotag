/++
Shared ID3 genre-code registry.

The numeric genre vocabulary originated with ID3v1 and is also referenced by
ID3v2 content-type syntax. Keeping the lookup in a shared ID3 module avoids
duplicating or diverging code tables between ID3v1 and ID3v2 codecs.

Coverage policy:

- codes 0 through 79: original ID3v1 genre list;
- codes 80 through 125: Winamp extensions recorded in the ID3v2.3 appendix;
- codes 126 through 191: later widely deployed Winamp-compatible extensions
  implemented by established libraries such as TagLib and FFmpeg;
- codes 192 through 254: not assigned by this compatibility registry;
- code 255: conventional ID3v1 unknown/no-genre sentinel.

The names returned by code lookup are stable compatibility display names.
Reverse lookup is exact and case-sensitive. A small set of historical
spellings is accepted as aliases so legacy input can still be encoded without
making those spellings the canonical display form.

This registry is not the canonical metadata genre vocabulary. Canonical genre
metadata remains free-form `MetadataTextList`; numeric ID3 genre codes are a
native codec concern.
+/
module audiotag.id3.genre;


/++ Number of recognized numeric ID3 genre codes. +/
enum size_t id3GenreCount = 192;


/++ Conventional ID3v1 byte value for unknown or absent genre. +/
enum ubyte id3v1UnknownGenreCode = 255;


/++ Successful or unsuccessful genre lookup. +/
struct Id3GenreLookup
{
    /// Whether a recognized code/name was found.
    bool found;

    /// Recognized code when `found` is true.
    ubyte code;

    /// Stable compatibility display name when `found` is true.
    string name;

    private static Id3GenreLookup success(
        ubyte code,
        string name
    )
        @safe pure nothrow @nogc
    {
        return Id3GenreLookup(
            true,
            code,
            name
        );
    }

    private static Id3GenreLookup notFound()
        @safe pure nothrow @nogc
    {
        return Id3GenreLookup.init;
    }
}


/++
Returns the complete ordered list of recognized ID3 genre names.

Array index equals numeric genre code for all returned entries.
+/
const(string)[]
id3GenreNames()
    @safe pure nothrow @nogc
{
    return genreNames[];
}


/++
Looks up one numeric ID3 genre code.

Codes 192 through 255 are intentionally not assigned a name here. In
particular, 255 remains the ID3v1 unknown/no-genre sentinel.
+/
Id3GenreLookup
findId3GenreByCode(
    ubyte code
)
    @safe pure nothrow @nogc
{
    if (code >= id3GenreCount)
        return Id3GenreLookup.notFound();

    return
        Id3GenreLookup.success(
            code,
            genreNames[code]
        );
}


/++
Looks up a numeric ID3 genre code by name.

Stable display names are checked first, followed by known historical aliases.
Matching is exact and case-sensitive; no fuzzy normalization is performed.
+/
Id3GenreLookup
findId3GenreByName(
    string name
)
    @safe
{
    foreach (index, candidate; genreNames)
    {
        if (candidate == name)
        {
            return
                Id3GenreLookup.success(
                    cast(ubyte) index,
                    candidate
                );
        }
    }

    foreach (aliasEntry; legacyAliases)
    {
        if (aliasEntry.name == name)
        {
            return
                Id3GenreLookup.success(
                    aliasEntry.code,
                    genreNames[aliasEntry.code]
                );
        }
    }

    return Id3GenreLookup.notFound();
}


private immutable string[id3GenreCount] genreNames =
[
    "Blues",
    "Classic Rock",
    "Country",
    "Dance",
    "Disco",
    "Funk",
    "Grunge",
    "Hip-Hop",
    "Jazz",
    "Metal",
    "New Age",
    "Oldies",
    "Other",
    "Pop",
    "R&B",
    "Rap",
    "Reggae",
    "Rock",
    "Techno",
    "Industrial",
    "Alternative",
    "Ska",
    "Death Metal",
    "Pranks",
    "Soundtrack",
    "Euro-Techno",
    "Ambient",
    "Trip-Hop",
    "Vocal",
    "Jazz-Funk",
    "Fusion",
    "Trance",
    "Classical",
    "Instrumental",
    "Acid",
    "House",
    "Game",
    "Sound Clip",
    "Gospel",
    "Noise",
    "Alternative Rock",
    "Bass",
    "Soul",
    "Punk",
    "Space",
    "Meditative",
    "Instrumental Pop",
    "Instrumental Rock",
    "Ethnic",
    "Gothic",
    "Darkwave",
    "Techno-Industrial",
    "Electronic",
    "Pop-Folk",
    "Eurodance",
    "Dream",
    "Southern Rock",
    "Comedy",
    "Cult",
    "Gangsta",
    "Top 40",
    "Christian Rap",
    "Pop/Funk",
    "Jungle",
    "Native American",
    "Cabaret",
    "New Wave",
    "Psychedelic",
    "Rave",
    "Showtunes",
    "Trailer",
    "Lo-Fi",
    "Tribal",
    "Acid Punk",
    "Acid Jazz",
    "Polka",
    "Retro",
    "Musical",
    "Rock & Roll",
    "Hard Rock",
    "Folk",
    "Folk Rock",
    "National Folk",
    "Swing",
    "Fast Fusion",
    "Bebop",
    "Latin",
    "Revival",
    "Celtic",
    "Bluegrass",
    "Avant-garde",
    "Gothic Rock",
    "Progressive Rock",
    "Psychedelic Rock",
    "Symphonic Rock",
    "Slow Rock",
    "Big Band",
    "Chorus",
    "Easy Listening",
    "Acoustic",
    "Humour",
    "Speech",
    "Chanson",
    "Opera",
    "Chamber Music",
    "Sonata",
    "Symphony",
    "Booty Bass",
    "Primus",
    "Porn Groove",
    "Satire",
    "Slow Jam",
    "Club",
    "Tango",
    "Samba",
    "Folklore",
    "Ballad",
    "Power Ballad",
    "Rhythmic Soul",
    "Freestyle",
    "Duet",
    "Punk Rock",
    "Drum Solo",
    "A Cappella",
    "Euro-House",
    "Dancehall",
    "Goa",
    "Drum & Bass",
    "Club-House",
    "Hardcore Techno",
    "Terror",
    "Indie",
    "Britpop",
    "Worldbeat",
    "Polsk Punk",
    "Beat",
    "Christian Gangsta Rap",
    "Heavy Metal",
    "Black Metal",
    "Crossover",
    "Contemporary Christian",
    "Christian Rock",
    "Merengue",
    "Salsa",
    "Thrash Metal",
    "Anime",
    "Jpop",
    "Synthpop",
    "Abstract",
    "Art Rock",
    "Baroque",
    "Bhangra",
    "Big Beat",
    "Breakbeat",
    "Chillout",
    "Downtempo",
    "Dub",
    "EBM",
    "Eclectic",
    "Electro",
    "Electroclash",
    "Emo",
    "Experimental",
    "Garage",
    "Global",
    "IDM",
    "Illbient",
    "Industro-Goth",
    "Jam Band",
    "Krautrock",
    "Leftfield",
    "Lounge",
    "Math Rock",
    "New Romantic",
    "Nu-Breakz",
    "Post-Punk",
    "Post-Rock",
    "Psytrance",
    "Shoegaze",
    "Space Rock",
    "Trop Rock",
    "World Music",
    "Neoclassical",
    "Audiobook",
    "Audio Theatre",
    "Neue Deutsche Welle",
    "Podcast",
    "Indie Rock",
    "G-Funk",
    "Dubstep",
    "Garage Rock",
    "Psybient"
];


private struct Id3GenreAlias
{
    string name;
    ubyte code;
}


/*
 * Historical spellings/labels encountered in specifications and established
 * implementations. They are accepted only for reverse lookup; code lookup
 * always returns the stable display name from `genreNames`.
 */
private immutable Id3GenreAlias[] legacyAliases =
[
    Id3GenreAlias("Jazz+Funk", 29),
    Id3GenreAlias("AlternRock", 40),
    Id3GenreAlias("Psychadelic", 67),
    Id3GenreAlias("Folk-Rock", 81),
    Id3GenreAlias("Folk/Rock", 81),
    Id3GenreAlias("Bebob", 85),
    Id3GenreAlias("Avantgarde", 90),
    Id3GenreAlias("Acapella", 123),
    Id3GenreAlias("A capella", 123),
    Id3GenreAlias("A cappella", 123),
    Id3GenreAlias("Dance Hall", 125),
    Id3GenreAlias("Hardcore", 129),
    Id3GenreAlias("BritPop", 132),
    Id3GenreAlias("Negerpunk", 133),
    Id3GenreAlias("Christian Gangsta", 136),
    Id3GenreAlias("JPop", 146),
    Id3GenreAlias("SynthPop", 147)
];


static assert(
    genreNames.length ==
    id3GenreCount
);


/// Ordered names cover the complete supported 0..191 range.
unittest
{
    const names =
        id3GenreNames();

    assert(names.length == 192);
    assert(names[0] == "Blues");
    assert(names[79] == "Hard Rock");
    assert(names[80] == "Folk");
    assert(names[125] == "Dancehall");
    assert(names[126] == "Goa");
    assert(names[133] == "Worldbeat");
    assert(names[147] == "Synthpop");
    assert(names[148] == "Abstract");
    assert(names[191] == "Psybient");
}


/// Numeric lookup recognizes boundaries and rejects unassigned/sentinel codes.
unittest
{
    auto rock =
        findId3GenreByCode(17);

    assert(rock.found);
    assert(rock.code == 17);
    assert(rock.name == "Rock");

    auto last =
        findId3GenreByCode(191);

    assert(last.found);
    assert(last.name == "Psybient");

    assert(!findId3GenreByCode(192).found);
    assert(!findId3GenreByCode(254).found);
    assert(!findId3GenreByCode(id3v1UnknownGenreCode).found);
    assert(id3v1UnknownGenreCode == 255);
}


/// Reverse lookup supports stable names and exact historical aliases.
unittest
{
    auto canonical =
        findId3GenreByName(
            "Worldbeat"
        );

    assert(canonical.found);
    assert(canonical.code == 133);
    assert(canonical.name == "Worldbeat");

    auto legacy =
        findId3GenreByName(
            "Jazz+Funk"
        );

    assert(legacy.found);
    assert(legacy.code == 29);
    assert(legacy.name == "Jazz-Funk");

    auto oldHardcore =
        findId3GenreByName(
            "Hardcore"
        );

    assert(oldHardcore.found);
    assert(oldHardcore.code == 129);
    assert(oldHardcore.name == "Hardcore Techno");

    assert(
        !findId3GenreByName(
            "rock"
        ).found
    );
}
