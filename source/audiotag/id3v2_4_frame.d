module audiotag.id3v2_4_frame;

import audiotag.id3_utils;
import std.stdio;
//import std.bitmanip;
import std.algorithm;
import std.range;

class id3v2_4_frame {
    string data;
    string decode(ubyte[] u) {
        return data;
    }
    ubyte[] encode() {
        return[];
    }
}

auto decode2 (ubyte[] u, uint lang) {
    switch (lang) {
        case 0: return u.ascii;
        case 1: return u.utf16LE;
        case 2: return u.utf16BE;
        case 3: return u.utf8;
        default: return "";
    }
}
auto decode2 (ubyte[] u) {
    return decode2(u[1..$], cast(uint) u[0]);
}
auto splitRange(R, E) (R range, E delim) {
    struct Chunk {
        private R r;
        bool empty() { writefln("Chunk.empty %s", r.empty); return r.empty; }
        auto front() { writefln("Chunk.front %s", r.front); return r.front; }
        void popFront() { writeln("Chunk.popFront"); r.popFront; }
    }
    struct ChunkBy {
        private R r;
        private E delim;
        this(R r, E d) {
            this.r = r;
            this.delim = delim;
        }
        bool empty() { writefln("ChunkBy.empty %s", r.empty); return r.empty; }
        auto front() { writefln("ChunkBy.front %s", r.front); return Chunk(r); }
        void popFront() {
            writeln("ChunkBy.popFront");
            while (!r.empty) {
                r.popFront();
            }

        }
    }
    return ChunkBy(range, delim);
}
unittest{
    ubyte[] r = [1,2,3,4,5,0,0,1,2,3,4,5];
    ubyte[] d = [0x00,0x00];
    auto result = splitRange(r, d);
    writefln("%s", result);
}
auto decodeSplit(ubyte[] u, uint lang) {
    ubyte[] term = (lang == 1 || lang == 2)? [0x00]:[0x00,0x00];
    u.popFront;
    auto buf = u.split(term)
        .map!(a => decode2(a, lang));
    return buf;
}
auto decodeSplit(ubyte[] u) {
    return decodeSplit(u[1..$], cast(uint) u[0]);
}
class id3v2_4_frame_text : id3v2_4_frame {
    override string decode(ubyte[] u) {
        auto lang = cast(uint) u[0];
        ubyte[][] buf = u.split(00);
        string[] result;
        while (buf.length) {
            if (!buf[0].empty) result ~= decode2(buf[0], lang);
           buf = buf[1 .. $];
        }
        return "";
    }
}

class id3v2_4_frame_talb : id3v2_4_frame_text {
}
unittest{
    ubyte[] term1 = [0x00];
    ubyte[] term2 = [0x00,0x00];
    writefln("00 %s", term1);
    writefln("00 00 %s", term2);
    ubyte[] bytes = cast(ubyte[])"собака" ~ term1 ~ cast(ubyte[])"Kakao";
    writefln("Kakao %s", bytes);
    ubyte[][] splitted = bytes.split(term1);
    writefln("splitted %s", splitted);
    writefln("decodeSplit %s", decodeSplit(bytes,3));
}
