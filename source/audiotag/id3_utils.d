module audiotag.id3_utils;

import std.stdio;
import std.string;
import std.algorithm;
import std.range;
import std.typecons;
import std.array;
import std.conv;
import std.bitmanip;
import std.utf;

// basic interface for all music frames (id3, ape, flac, .audiotag .)

interface frame {
    string decode(ubyte[] buffer);
    ubyte[] encode (string value);
}

immutable string[string] id3v2_4_dic;
immutable string[string] id3v2_3_dic;

shared static this() {
    enum id3v2_4_dic_ct = import("id3v2-frame-id.csv")
        .splitLines
        .map!(a => (a.splitter(",")).array)
        .map!(a => tuple(a[3], a[0]))
        .filter!(a => !a[0].empty)
        .assocArray;
    enum id3v2_3_dic_ct = import("id3v2-frame-id.csv")
        .splitLines
        .map!(a => (a.splitter(",")).array)
        .map!(a => tuple(a[2], a[0]))
        .filter!(a => !a[0].empty)
        .assocArray;
    id3v2_3_dic = id3v2_3_dic_ct;
    id3v2_4_dic = id3v2_4_dic_ct;
}

unittest {
    //writefln("%s",id3v2_3_dic);
    //writefln("%s",id3v2_4_dic);
}

ubyte[] ascii(string s) { return cast(typeof(return)) s; }
string ascii(ubyte[] u) { return cast(string) u; }
ubyte[] utf8 (string s) { return cast(ubyte[]) s; }
string utf8 (ubyte[] u) { return cast(string) u; }
ubyte[] utf16BE (string s) { return cast(ubyte[]) s.byUTF!wchar().map!(a => a.nativeToBigEndian).array; }
string utf16BE (ubyte[] u) {
    return u.chunks(wchar.sizeof)
    .map!(x => bigEndianToNative!wchar(x[0 .. wchar.sizeof]))
    .to!string;
}
ubyte[] utf16LE (string s) { return cast(ubyte[]) s.byUTF!wchar().map!(a => a.nativeToLittleEndian).array; }
string utf16LE (ubyte[] u) {
    return u.chunks(wchar.sizeof)
    .map!(x => littleEndianToNative!wchar(x[0 .. wchar.sizeof]))
    .to!string;
}
unittest{
   // writefln("Hello %s ", ascii("Hello"));
    //writefln("%s", ascii("Hello").ascii);
    //auto text = cast(ubyte[]) "Wchar Test"w;
    //writefln("Test %s", text);
    //writefln("Test %s", utf16BE("Test"));
    //auto test2 = "Hello";
    //auto test2b = test2.byUTF!wchar().map!(a => a.nativeToBigEndian);
    //auto test2l = test2.byUTF!wchar().map!(a => a.nativeToLittleEndian);
    //writefln("b: %s", test2b);
    //writefln("l: %s", test2l);
}

string parse(ubyte[] u) {
    // 00 ISO-8859-1 Terminated with $00
    // 01 UTF-16LE with BOM Terminated with $00 00
    // 02 UTF-16BE with BOM Terminated with $00 00
    // 03 UTF-8 Terminated with $00
    return "";
}

