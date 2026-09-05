module audiotag.utils;

import std.stdio;
import std.file;
//import std.digest.digest;
import std.encoding;
import audiotag.id3;

ubyte[][string] audioHeader;

static this() {
    audioHeader["id3"] = cast(ubyte[])"ID3";
    audioHeader["flac"] = cast(ubyte[])"fLaC";
    audioHeader["ogg"] = cast(ubyte[])"OggS";
}

/***********************************
 * Get the type of audio tag
 *
 * Params:
 *  filename = Filename
 * Returns:
 *  Type of Audiotag or "unknown"
 * Examples:
 *  getAudioTagType("filename");
 */
auto getAudioTagType (string filename) {
    ubyte[] data;
    size_t size;
    foreach(ah; audioHeader) { if (ah.length > size) size = ah.length; }
    try
    {
        data = cast(ubyte[]) read(filename, size);
    }
    catch (FileException ex)
    {
        // Handle errors
    }
    foreach(key,value; audioHeader) {
        if (data[0..value.length] == value) return(key);
    }
    return("unknown");
}

auto getAudioTags (string filename) {
    auto type = getAudioTagType(filename);
    if (type == "unknown") return;
    switch (type) {
        default: throw new Exception("unknown audiotype");
        case "id3": getId3Tags(filename);
    }

}

unittest {
    writeln(getAudioTagType("music/Ironic.mp3"));
    writeln(getAudioTagType("music/Quimbara.flac"));
    writeln(getAudioTagType("music/Radio Nowhere.ogg"));

    getAudioTags("music/Ironic.mp3");
 ubyte[] data;
 try
    {
        data = cast(ubyte[]) read("music/Ironic.mp3", 4);
        writeln(data);
        writeln(cast(string)data);
        writeln(data.decode);
    }
    catch (FileException ex)
    {
        // Handle errors
    }
    try
    {
        data = cast(ubyte[]) read("music/Quimbara.flac", 4);
        writeln(cast(string)data);
        writeln(data.decode);
    }
    catch (FileException ex)
    {
        // Handle errors
    }
    try
    {
        data = cast(ubyte[]) read("music/Radio Nowhere.ogg", 4);
        writeln(cast(string)data);
        writeln(data.decode);
    }
    catch (FileException ex)
    {
        // Handle errors
    }
    writeln(audioHeader["id3"]);
    writeln(audioHeader["flac"]);
}
