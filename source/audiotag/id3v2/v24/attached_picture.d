/++
ID3v2.4 attached-picture frame decoding.

An `APIC` frame contains:

- one text-encoding marker;
- one null-terminated ISO-8859-1 MIME type;
- one picture-type byte;
- one terminated description using the selected encoding;
- binary picture data or, for MIME type `"-->"`, a linked URL.

Physical picture bytes are preserved exactly as stored. The effective
ID3 byte-unsynchronisation state is retained separately so later
consumers can obtain the logical byte stream without losing
provenance.

Compressed or encrypted frames remain structurally valid but cannot
yet be semantically decoded.
+/
module audiotag.id3v2.v24.attached_picture;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.picture :
    Id3v2PicturePayloadKind,
    Id3v2PictureType,
    isValidId3v2PictureType;

import audiotag.id3v2.v24.frame :
    Id3v24FrameEnvelope;

import audiotag.id3v2.v24.frame_data :
    parseId3v24FrameDataLayout;

import audiotag.id3v2.v24.text_decode :
    decodeId3v24TextSpan;

import audiotag.id3v2.v24.text_encoding :
    Id3v24TextEncoding,
    parseId3v24TextEncoding;

import audiotag.id3v2.v24.text_segment :
    takeId3v24TerminatedTextSegment;


/++
Backward-compatible ID3v2.4 name for the shared ID3v2 picture type.
+/
alias Id3v24PictureType =
    Id3v2PictureType;


/++
Backward-compatible ID3v2.4 name for the shared picture payload kind.
+/
alias Id3v24PicturePayloadKind =
    Id3v2PicturePayloadKind;


/++
Semantic availability of an attached-picture frame.
+/
enum Id3v24AttachedPictureAvailability : ubyte
{
    decoded,
    requiresDecompression,
    requiresDecryption,
    requiresDecryptionAndDecompression
}


/++
Decoded ID3v2.4 `APIC` frame.
+/
struct Id3v24AttachedPictureFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Encoding used by the description.
    Id3v24TextEncoding descriptionEncoding;

    /// MIME type exactly as stored.
    string mimeType;

    /// Physical MIME bytes excluding the null terminator.
    ByteSpan rawMimeType;

    /// Declared picture type.
    Id3v24PictureType pictureType;

    /// Absolute source offset of the picture-type byte.
    size_t pictureTypeSourceOffset;

    /// Decoded content description.
    string description;

    /// Physical description bytes excluding its terminator.
    ByteSpan rawDescription;

    /// Whether the payload is embedded binary data or a URL.
    Id3v24PicturePayloadKind payloadKind;

    /// Physical payload bytes extending to the frame boundary.
    ByteSpan rawPictureData;

    /// Decoded URL when `payloadKind == linkedUrl`.
    string linkedUrl;

    /// Whether ID3 byte unsynchronisation was effective.
    bool effectiveUnsynchronisation;

    /// Whether this APIC frame refers to an external image.
    @property
    bool linked() const
        @safe pure nothrow @nogc
    {
        return payloadKind == Id3v24PicturePayloadKind.linkedUrl;
    }
}


/++
Outcome of attempting semantic APIC decoding.
+/
struct Id3v24AttachedPictureOutcome
{
    Id3v24AttachedPictureAvailability availability;
    Id3v24AttachedPictureFrame picture;
    ByteSpan rawPayload;

    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v24AttachedPictureAvailability.decoded;
    }
}


/++
Decodes an ID3v2.4 attached-picture (`APIC`) frame.

The MIME type and native binary payload are preserved exactly. No
attempt is made here to decode JPEG, PNG or other image formats.

MIME type `"-->"` changes the final field from embedded image bytes
to an ISO-8859-1 URL.

Picture-type values outside the ID3v2.4-defined range `$00` through
`$14` are rejected in strict decoding.

Compressed or encrypted frames return a successful transformation-
pending outcome.

Params:
    frame = Previously validated and bounded ID3v2.4 frame.
    tagUnsynchronised = Whether tag-level byte unsynchronisation applies.

Returns:
    Decoded or transformation-pending APIC outcome, or a structured
    parsing/text error.
+/
ParseResult!Id3v24AttachedPictureOutcome
decodeId3v24AttachedPictureFrame(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (frame.header.id[] != "APIC")
    {
        return ParseResult!Id3v24AttachedPictureOutcome.failure(
            ParseError(
                ParseErrorCode.invalidSignature,
                frame.header.sourceOffset
            )
        );
    }

    auto layoutResult =
        frame.parseId3v24FrameDataLayout(
            tagUnsynchronised
        );

    if (layoutResult.hasError)
    {
        return ParseResult!Id3v24AttachedPictureOutcome.failure(
            layoutResult.error
        );
    }

    const layout =
        layoutResult.value;

    if (
        frame.header.compressed ||
        frame.header.encrypted
    )
    {
        Id3v24AttachedPictureAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v24AttachedPictureAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (frame.header.compressed)
        {
            availability =
                Id3v24AttachedPictureAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v24AttachedPictureAvailability
                    .requiresDecryption;
        }

        return ParseResult!Id3v24AttachedPictureOutcome.success(
            Id3v24AttachedPictureOutcome(
                availability,
                Id3v24AttachedPictureFrame.init,
                layout.rawPayload
            )
        );
    }

    auto payload =
        layout.payloadCursor();

    auto encodingResult =
        payload.parseId3v24TextEncoding();

    if (encodingResult.hasError)
    {
        return ParseResult!Id3v24AttachedPictureOutcome.failure(
            encodingResult.error
        );
    }

    const encoding =
        encodingResult.value;

    auto mimeResult =
        payload.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.latin1
        );

    if (mimeResult.hasError)
    {
        return ParseResult!Id3v24AttachedPictureOutcome.failure(
            mimeResult.error
        );
    }

    const mimeSegment =
        mimeResult.value;

    auto mime =
        decodeId3v24TextSpan(
            mimeSegment.raw,
            Id3v24TextEncoding.latin1,
            layout.effectiveUnsynchronisation
        );

    if (mime.hasError)
    {
        return ParseResult!Id3v24AttachedPictureOutcome.failure(
            mime.error
        );
    }

    auto typeResult =
        payload.takeByte();

    if (typeResult.hasError)
    {
        return ParseResult!Id3v24AttachedPictureOutcome.failure(
            typeResult.error
        );
    }

    const typeByte =
        typeResult.value;

    if (
        !isValidId3v2PictureType(
            typeByte.value
        )
    )
    {
        return ParseResult!Id3v24AttachedPictureOutcome.failure(
            ParseError(
                ParseErrorCode.inconsistentStructure,
                typeByte.sourceOffset
            )
        );
    }

    const pictureType =
        cast(Id3v24PictureType) typeByte.value;

    auto descriptionResult =
        payload.takeId3v24TerminatedTextSegment(
            encoding
        );

    if (descriptionResult.hasError)
    {
        return ParseResult!Id3v24AttachedPictureOutcome.failure(
            descriptionResult.error
        );
    }

    const descriptionSegment =
        descriptionResult.value;

    auto description =
        decodeId3v24TextSpan(
            descriptionSegment.raw,
            encoding,
            layout.effectiveUnsynchronisation
        );

    if (description.hasError)
    {
        return ParseResult!Id3v24AttachedPictureOutcome.failure(
            description.error
        );
    }

    const rawPictureData =
        payload.remainingRaw;

    Id3v24PicturePayloadKind payloadKind =
        Id3v24PicturePayloadKind.binaryData;

    string linkedUrl;

    if (mime.value == "-->")
    {
        payloadKind =
            Id3v24PicturePayloadKind.linkedUrl;

        auto url =
            decodeId3v24TextSpan(
                rawPictureData,
                Id3v24TextEncoding.latin1,
                layout.effectiveUnsynchronisation
            );

        if (url.hasError)
        {
            return ParseResult!Id3v24AttachedPictureOutcome.failure(
                url.error
            );
        }

        linkedUrl =
            url.value;
    }

    auto picture =
        Id3v24AttachedPictureFrame(
            frame.header.sourceOffset,
            encoding,
            mime.value,
            mimeSegment.raw,
            pictureType,
            typeByte.sourceOffset,
            description.value,
            descriptionSegment.raw,
            payloadKind,
            rawPictureData,
            linkedUrl,
            layout.effectiveUnsynchronisation
        );

    return ParseResult!Id3v24AttachedPictureOutcome.success(
        Id3v24AttachedPictureOutcome(
            Id3v24AttachedPictureAvailability.decoded,
            picture,
            layout.rawPayload
        )
    );
}


import audiotag.core.cursor :
    ByteCursor;

import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;


/// A normal JPEG front-cover APIC frame is decoded.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x17,
            0x00, 0x00,

            0x03,

            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g',
            0x00,

            0x03,

            'F', 'r', 'o', 'n', 't',
            0x00,

            0xFF, 0xD8, 0xFF, 0xD9
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 100));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24AttachedPictureFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const picture =
        result.value.picture;

    assert(picture.sourceOffset == 100);
    assert(picture.descriptionEncoding == Id3v24TextEncoding.utf8);
    assert(picture.mimeType == "image/jpeg");

    assert(
        picture.pictureType ==
        Id3v24PictureType.frontCover
    );

    assert(picture.pictureTypeSourceOffset == 122);
    assert(picture.description == "Front");

    assert(
        picture.payloadKind ==
        Id3v24PicturePayloadKind.binaryData
    );

    assert(!picture.linked);

    assert(
        picture.rawPictureData.data ==
        [0xFF, 0xD8, 0xFF, 0xD9]
    );
}


/// An empty description is valid.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x0F,
            0x00, 0x00,

            0x00,
            'i', 'm', 'a', 'g', 'e', '/',
            'p', 'n', 'g',
            0x00,
            0x03,
            0x00,
            0x89, 0x50
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 200));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24AttachedPictureFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.picture.description.length == 0);
    assert(result.value.picture.mimeType == "image/png");
}


/// MIME media-type prefixes are preserved exactly as stored.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0x00,

            0x03,
            'p', 'n', 'g',
            0x00,
            0x03,
            0x00,
            0x89
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 300));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24AttachedPictureFrame();

    assert(result.hasValue);
    assert(result.value.picture.mimeType == "png");
}


/// MIME type "-->" represents a linked image URL.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x14,
            0x00, 0x00,

            0x03,

            '-', '-', '>',
            0x00,

            0x03,

            'c', 'o', 'v', 'e', 'r',
            0x00,

            'h', 't', 't', 'p', ':', '/',
            '/', 'x'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 400));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24AttachedPictureFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const picture =
        result.value.picture;

    assert(picture.linked);

    assert(
        picture.payloadKind ==
        Id3v24PicturePayloadKind.linkedUrl
    );

    assert(picture.linkedUrl == "http://x");

    assert(
        picture.rawPictureData.data ==
        ['h', 't', 't', 'p', ':', '/', '/', 'x']
    );
}


/// Undefined picture-type values are rejected.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x03,
            'x',
            0x00,

            0x15,

            0x00,
            0xAA
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 500));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 513);
}


/// A missing MIME terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x03,
            'j', 'p', 'g'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 600));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );
}


/// A missing description terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x07,
            0x00, 0x00,

            0x03,
            'x',
            0x00,
            0x03,
            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 700));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );
}


/// The APIC codec rejects a different frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0xAA
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 800));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24AttachedPictureFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 800);
}


/// Compressed APIC data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x09,

            0x00, 0x00, 0x00, 0x01,
            0xAA
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 900));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24AttachedPictureFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v24AttachedPictureAvailability
            .requiresDecompression
    );

    assert(result.value.rawPayload.data == [0xAA]);
}


/// Physical picture provenance retains unsynchronisation stuffing.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x02,

            0x00,
            'x',
            0x00,
            0x03,
            0x00,

            0xFF, 0x00,
            0xD8,
            0xFF, 0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 1000));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24AttachedPictureFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.picture.effectiveUnsynchronisation
    );

    assert(
        result.value.picture.rawPictureData.data ==
        [0xFF, 0x00, 0xD8, 0xFF, 0x00]
    );
}
