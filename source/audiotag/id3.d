module audiotag.id3;

import std.stdio;
import std.file;
import std.range;
import std.bitmanip;
import std.system;
import std.conv;
import std.algorithm;
import std.ascii;
import audiotag.id3_utils;

auto getId3Tags(string filename) {
    ubyte[] header;
    try {
        header = cast(ubyte[]) read(filename, 10);
    }
    catch (FileException ex)
    {
        // Handle errors
    }
    writeln(header);
    auto identifier = cast(string) header[0..3];
    auto versions = [header[3], header[4]];
    auto flags = header[5];
    auto size = header[6..10];
    writeln(identifier);
    writeln(versions);
    writeln(flags);
    writeln(size);
}

auto byteToBools(ubyte value) {
    bool[8] result;
    result[0] = (value & 1) != 0;
    result[1] = (value & 2) != 0;
    result[2] = (value & 4) != 0;
    result[3] = (value & 8) != 0;
    result[4] = (value & 16) != 0;
    result[5] = (value & 32) != 0;
    result[6] = (value & 64) != 0;
    result[7] = (value & 128) != 0;
    return result;
}
unittest {
    //writefln("bools %s", byteToBools(1));
    //writefln("bools %s", byteToBools(2));
    //writefln("bools %s", byteToBools(3));
    //writefln("bools %s", byteToBools(64));
}
/***************
 * Decode synchsafe integer to normal integer
 *
 * Params:
 *  value = Synchsafe-integer to decode
 * Returns: normal integer
****************/
auto synchsafeDecode (uint value) {
    uint a, b, c, d, result;
    if (value & 0x808080) value = value & 0x7f7f7f;
    a = value & 0xff;
    b = (value >> 8) & 0xff;
    c = (value >> 16) & 0xff;
    d = (value >> 24) & 0xff;

    result = result | a;
    result = result | (b << 7);
    result = result | (c << 14);
    result = result | (d << 21);
    return result;
}
unittest {
    writefln("synchsafe decode 126 %s", synchsafeDecode(256));
}
auto synchsafeDecode (ubyte[] value) {
    return synchsafeDecode(peek!(uint, Endian.bigEndian)(value));
}

/***************
 * Encode integer to synchsafe integer
 *
 * Params:
 *  value = integer to encode
 * Returns: synchsafe integer
****************/
auto synchsafeEncode (uint value) {
    uint a, b, c, d, result;
    if (value & 0xf0000000) debug writeln ("Invalid decoded size");
    a = value & 0x7f;
    b = (value >> 7) & 0x7f;
    c = (value >> 14) & 0x7f;
    d = (value >> 21) & 0x7f;

    result = result | a;
    result = result | (b << 8);
    result = result | (c << 16);
    result = result | (d << 24);
    return result;
}
unittest {
    uint x = 256;
    uint dec = synchsafeEncode(x);
    assert (x == synchsafeDecode(dec));
}
struct id3v2frame {
    string id;
    uint size;
    mixin(bitfields!(
        bool, "alterTag",    1,
        bool, "alterFile",    1,
        bool, "readOnly",    1,
        bool, "group", 1,
        bool, "compression", 1,
        bool, "encryption", 1,
        bool, "unsynchronisation", 1,
        bool, "lengthIndicator", 1
    ));
    ubyte[] data;
}
struct id3v2header {
    uint versions;
    uint revision;
    uint size;
    mixin(bitfields!(
        bool, "unsync",    1,
        bool, "extended",    1,
        bool, "experimental",    1,
        bool, "footer", 1,
        uint, "", 4
    ));
}
struct id3v2extendedHeader {
    uint size;
}
struct frame {
    string key;
    string[] value;
}
auto parseHeader (ubyte[] buffer) {
    id3v2header header;
    header.versions = cast(uint) buffer[3];
    header.revision = cast(uint) buffer[4];
    auto flags = byteToBools(cast(uint) buffer[5]);
    header.unsync =        flags[7];
    header.extended =      flags[6];
    header.experimental =  flags[5];
    header.footer =        flags[4];
    header.size = synchsafeDecode(buffer[6..10]);
    return header;
}

struct frameRange {
    string filename;
    File file;
    id3v2header header;
    id3v2extendedHeader extendedHeader;
    id3v2frame frame;
    bool isEmpty;
    this (string filename) {
        this.filename = filename;
        this.file = File(filename, "r");
        header = parseHeader(file.rawRead(new ubyte[10]));
        if (header.extended) {
            auto buffer = file.rawRead(new ubyte[4]);
            extendedHeader.size = synchsafeDecode(buffer[0..4]);
            buffer = file.rawRead(new ubyte[extendedHeader.size - 4]);
        }
        debug {
            writeln("*******************************");
            writefln("File: %s", filename);
            writeln("Header");
            writefln("\tId: ID3v2.%s.%s", header.versions, header.revision);
            writefln("\tSize: %s bytes", header.size);
            writefln("\tExtended header: %s", header.extended);
            if (header.extended) {
                writefln("\tExtended header size: %s", extendedHeader.size);
            }
            writeln("-------------------------------");
        }
        isEmpty = false;
        popFront();
    }
    bool empty() const {
        //debug { writefln("empty? %s @ file pos %s", file.tell() >= header.size, file.tell()); }
        return (file.tell() >= header.size || isEmpty);
    }
    auto front() {
        //debug{ writefln("front: %s", frame.id); }
        return frame;
    }
    void popFront() {
        //debug { writefln("popFront:" ); }
        // Read frame header
        auto buffer = file.rawRead(new ubyte[10]);
        // Check if padding (consists of 00)
        if (buffer.all!"a == 0") { isEmpty = true; return; }
        // Check if frame consists of garbage
        // frame ids start with at least 3 ascii chars
        if (!buffer[0..3].all!isAlpha || !buffer[3].isAlphaNum) { isEmpty = true; return; }
        frame.id = cast(string) buffer[0..4];
        frame.size = synchsafeDecode(buffer[4..8]);
        // Does frame size reach beyond header size?
        if(frame.size + file.tell() > header.size) { isEmpty = true; return; }
        // Flags:0abc0000 0h00kmnp
        auto flags = byteToBools(cast(uint) buffer[8]);
        frame.alterTag = flags[6];
        frame.alterFile = flags[5];
        frame.readOnly = flags[4];
        flags = byteToBools(cast(uint) buffer[9]);
        frame.group = flags[6];
        frame.compression = flags[3];
        frame.encryption = flags[2];
        frame.unsynchronisation = flags[1];
        frame.lengthIndicator = flags[0];
        debug {
            //writefln("Frame: %s size: %s (compression %s, encryption %s)", frame.id, frame.size, frame.compression, frame.encryption);
        }
        // Read data
        frame.data = file.rawRead(new ubyte[frame.size]);
        //writefln("pos %s", file.tell());
    }
}
auto readFrames (string filename) {
    return frameRange(filename);
}
unittest{
    import std.algorithm;
    import std.range;
    auto filename = "music/Ironic.mp3";
    auto tag = readFrames(filename);
    //writefln("%s", peek!(bool[], Endian.littleEndian)(tag.flags));
    tag.take(20).array;
    auto filename2 = "music/Respect.mp3";
    auto tag2 = readFrames(filename2);
    //writefln("%s", peek!(bool[], Endian.littleEndian)(tag.flags));
   // tag2.take(10).array;
}

string[] frame_text (ubyte[] u) {
    auto lang = cast(uint) u[0];
    ubyte[][] buf = u[1 .. $].split(00);
    string[] result;
    while (buf.length) {
        if (!buf[0].empty) result ~= decodeData(lang, buf[0]);
        buf = buf[1 .. $];
    }
    return result;
}
auto decodeData (uint i, ubyte[] u) {
     switch (i) {
        case 0: return u.ascii;
        case 1: return u.utf16LE;
        case 2: return u.utf16BE;
        case 3: return u.utf8;
        default: return "";
    }
}
string[] frame_txxx (ubyte[] u) {
    auto lang = cast(uint) u[0];
    ubyte[][] buf = u[1 .. $].split(00);
    string[] result;
    while (buf.length) {
        if (!buf[0].empty) result ~= decodeData(lang, buf[0]);
        buf = buf[1 .. $];
    }
    return result;
}
string[] frame_url (ubyte[] u) {
    string[] url;
    url ~= decodeData(0, u);
    return url;
}
string[] frame_priv (ubyte[] u) {
    ubyte[][] buf = u.splitter!("a == b")(0).array;
    string[] result;
    result ~= decodeData(0, buf[0]);
    return result;
}
auto frame_switch (string id, ubyte[] u) {
    switch (id) {
        case "TIT1", "TIT2", "TIT3", "TALB", "TOAL", "TRCK", "TPOS",
             "TSST", "TSRC", "TPE1", "TPE2", "TPE3", "TPE4", "TOPE",
             "TEXT", "TOLY", "TCOM", "TMCL", "TIPL", "TENC", "TBPM",
             "TLEN", "TKEY", "TLAN", "TCON", "TFLT", "TMED", "TMOO",
             "TCOP", "TPRO", "TPUB", "TOWN", "TRSN", "TRSO", "TOFN",
             "TDLY", "TDEN", "TDOR", "TDRC", "TDRL", "TDTG", "TSSE",
             "TSOA", "TSOP", "TSOT": return frame_text(u);
        case "TXXX": return frame_txxx(u);
        case "WCOM", "WCOP", "WOAF", "WOAR", "WOAS", "WORS", "WPAY",
             "WPUB": return frame_url(u);
        case "PRIV": return frame_priv(u);
        default: return [""];
    }
}
struct parseFrame (Range) {
    Range range;
    frame f;
    this (Range range) {
        this.range = range;
    }
    bool empty() const { return range.empty; }
    auto front() { return f; }
    void popFront() {
        auto r = range.front;
        f.key = r.id;
        f.value = frame_switch(r.id, r.data);

        range.popFront;
    }
}
auto parseFrames (Range) (Range range) {
    return parseFrame!Range(range);
}
unittest{
    auto filename = "music/Solo esseri umani.mp3";
    auto tag = readFrames(filename)
        .array
        .parseFrames
        ;
    foreach(t; tag) {
        writefln("Frame: %s", t);

    }
}
