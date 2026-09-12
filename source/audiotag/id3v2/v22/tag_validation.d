/++
ID3v2.2.0 tag-level conformance validation.

Frame codecs deliberately validate one bounded frame at a time. Rules that
depend on the complete tag belong here instead:

- singleton frame cardinalities;
- identity-key cardinalities such as owner, description, email, or
  language-plus-descriptor;
- attached-picture descriptor and icon-type restrictions;
- `MCI` requiring a present and syntactically valid `TRK`;
- `LNK` duplicate-content rules and locally verifiable restrictions inherited
  from the linked frame.

Validation is a sidecar operation over an already decoded native frame
sequence. It never removes, rewrites, dereferences, or otherwise mutates native
metadata.

A linked frame is treated as a virtual occurrence when the `LNK` payload
contains enough identity information to check the corresponding restriction.
Some linked-frame restrictions cannot be proven locally. In particular, the
v2.2.0 `LNK` grammar does not expose the `WXX` description, the `CRA`/`CRM`
owner identifier, or the `PIC` picture type. Such cases are reported as
`indeterminate` instead of being silently accepted.

Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.tag_validation;

import std.sumtype :
    match;

import audiotag.id3v2.common.position :
    parseId3v2Position;

import audiotag.id3v2.v22.attached_picture :
    Id3v22AttachedPictureFrame;

import audiotag.id3v2.v22.audio_encryption :
    Id3v22AudioEncryptionFrame;

import audiotag.id3v2.v22.comment :
    Id3v22CommentFrame;

import audiotag.id3v2.v22.encrypted_meta :
    Id3v22EncryptedMetaFrame;

import audiotag.id3v2.v22.general_encapsulated_object :
    Id3v22GeneralEncapsulatedObjectFrame;

import audiotag.id3v2.v22.linked_information :
    Id3v22LinkedInformationFrame;

import audiotag.id3v2.v22.lyrics_text :
    Id3v22LyricsTextFrame;

import audiotag.id3v2.v22.native_frame :
    Id3v22NativeFrame;

import audiotag.id3v2.v22.native_sequence :
    Id3v22NativeFrameSequence;

import audiotag.id3v2.v22.popularity_meter :
    Id3v22PopularityMeterFrame;

import audiotag.id3v2.v22.synchronised_text :
    Id3v22SynchronisedTextFrame;

import audiotag.id3v2.v22.text_information :
    Id3v22TextInformationFrame;

import audiotag.id3v2.v22.unique_file_identifier :
    Id3v22UniqueFileIdentifierFrame;

import audiotag.id3v2.v22.user_text :
    Id3v22UserTextFrame;

import audiotag.id3v2.v22.user_url :
    Id3v22UserUrlFrame;


/++
Severity of one ID3v2.2.0 tag-conformance diagnostic.
+/
enum Id3v22TagValidationSeverity : ubyte
{
    /// A locally provable violation of a normative tag-level restriction.
    error,

    /// Local bytes are insufficient to prove or disprove the restriction.
    indeterminate
}


/++
Machine-readable ID3v2.2.0 tag-conformance diagnostic code.
+/
enum Id3v22TagValidationCode : ubyte
{
    /// A non-compressed ID3v2.2 tag contains no frames.
    emptyTag,

    /// A frame or virtual linked frame violates a one-per-kind restriction.
    duplicateSingleton,

    /// Two repeatable frames use the same specification-defined identity key.
    duplicateIdentity,

    /// More than one `PIC` uses picture type `$01` or `$02`.
    duplicatePictureType,

    /// Two `LNK` frames have the same semantic contents.
    duplicateLinkContents,

    /// `MCI` is present but no `TRK` occurrence is present.
    missingRequiredFrame,

    /// `MCI` is present and local `TRK` text exists but is not valid position text.
    invalidRequiredFrame,

    /// A linked-frame restriction cannot be completely validated locally.
    unverifiableLinkedConstraint
}


/++
One tag-level ID3v2.2.0 conformance diagnostic.

`frameId` identifies the physical frame that caused the diagnostic.
For `LNK`, `subjectFrameId` identifies the linked frame whose restriction is
being evaluated.

`relatedFrameIndex` is `size_t.max` when no second local/virtual occurrence is
involved.

No diagnostic owns or copies source bytes.
+/
struct Id3v22TagValidationDiagnostic
{
    /// Whether this is a proven violation or an unresolved local check.
    Id3v22TagValidationSeverity severity;

    /// Machine-readable validation code.
    Id3v22TagValidationCode code;

    /// Primary frame index, or `size_t.max` for a tag-wide condition.
    size_t frameIndex;

    /// Earlier conflicting frame index, or `size_t.max`.
    size_t relatedFrameIndex;

    /// Physical source offset of the primary frame or tag body.
    size_t sourceOffset;

    /// Physical frame identifier causing the diagnostic.
    char[3] frameId;

    /// Frame identifier whose tag-level restriction is affected.
    char[3] subjectFrameId;
}


/++
Result of validating one decoded ID3v2.2.0 native frame sequence.

The report is deliberately independent from `ParseResult`: the input was
already parsed successfully, and these diagnostics describe relationships
between otherwise valid native frames.
+/
struct Id3v22TagValidationReport
{
    /// All diagnostics in deterministic source/rule discovery order.
    Id3v22TagValidationDiagnostic[] diagnostics;


    /++
    Whether at least one locally proven conformance violation exists.
    +/
    @property
    bool hasViolations() const
        @safe pure nothrow @nogc
    {
        foreach (const diagnostic; diagnostics)
        {
            if (
                diagnostic.severity ==
                Id3v22TagValidationSeverity.error
            )
            {
                return true;
            }
        }

        return false;
    }


    /++
    Whether at least one restriction cannot be completely checked locally.
    +/
    @property
    bool hasIndeterminate() const
        @safe pure nothrow @nogc
    {
        foreach (const diagnostic; diagnostics)
        {
            if (
                diagnostic.severity ==
                Id3v22TagValidationSeverity.indeterminate
            )
            {
                return true;
            }
        }

        return false;
    }


    /++
    Whether the sequence can be claimed strictly conformant from local data.

    A report containing an indeterminate linked constraint is not considered
    strictly conformant even when no proven violation exists.
    +/
    @property
    bool strictlyConformant() const
        @safe pure nothrow @nogc
    {
        return diagnostics.length == 0;
    }
}


private enum ConstraintRule : ubyte
{
    none,
    singlePerId,
    byIdentity,
    byLanguageAndIdentity
}


private struct ConstraintOccurrence
{
    size_t frameIndex;
    size_t sourceOffset;
    char[3] physicalFrameId;
    char[3] subjectFrameId;
    ConstraintRule rule;
    const(char)[] identity;
    char[3] language;
}


private struct PictureTypeOccurrence
{
    size_t frameIndex;
    size_t sourceOffset;
    char[3] physicalFrameId;
    ubyte pictureType;
}


private bool
idEquals(
    const ref char[3] id,
    string expected
)
    @safe pure nothrow @nogc
{
    return
        expected.length == 3 &&
        id[0] == expected[0] &&
        id[1] == expected[1] &&
        id[2] == expected[2];
}


private bool
idsEqual(
    const ref char[3] left,
    const ref char[3] right
)
    @safe pure nothrow @nogc
{
    return
        left[0] == right[0] &&
        left[1] == right[1] &&
        left[2] == right[2];
}


private char[3]
literalId(
    char first,
    char second,
    char third
)
    @safe pure nothrow @nogc
{
    return [first, second, third];
}


private bool
isSingletonId(
    const ref char[3] id
)
    @safe pure nothrow @nogc
{
    return
        idEquals(id, "IPL") ||
        idEquals(id, "MCI") ||
        idEquals(id, "ETC") ||
        idEquals(id, "MLL") ||
        idEquals(id, "STC") ||
        idEquals(id, "RVA") ||
        idEquals(id, "EQU") ||
        idEquals(id, "REV") ||
        idEquals(id, "CNT") ||
        idEquals(id, "BUF");
}


private ConstraintRule
genericRuleForId(
    const ref char[3] id
)
    @safe pure nothrow @nogc
{
    if (id[0] == 'T')
    {
        return
            idEquals(id, "TXX")
            ? ConstraintRule.none
            : ConstraintRule.singlePerId;
    }

    if (id[0] == 'W')
    {
        if (
            idEquals(id, "WXX") ||
            idEquals(id, "WAR") ||
            idEquals(id, "WCM")
        )
        {
            return ConstraintRule.none;
        }

        return ConstraintRule.singlePerId;
    }

    return
        isSingletonId(id)
        ? ConstraintRule.singlePerId
        : ConstraintRule.none;
}


private void
appendOccurrence(
    ref ConstraintOccurrence[] occurrences,
    size_t frameIndex,
    size_t sourceOffset,
    const ref char[3] physicalFrameId,
    const ref char[3] subjectFrameId,
    ConstraintRule rule,
    const(char)[] identity = null,
    char[3] language = char[3].init
)
    @safe
{
    if (rule == ConstraintRule.none)
        return;

    occurrences ~=
        ConstraintOccurrence(
            frameIndex,
            sourceOffset,
            physicalFrameId,
            subjectFrameId,
            rule,
            identity,
            language
        );
}


private void
appendDiagnostic(
    ref Id3v22TagValidationDiagnostic[] diagnostics,
    Id3v22TagValidationSeverity severity,
    Id3v22TagValidationCode code,
    size_t frameIndex,
    size_t relatedFrameIndex,
    size_t sourceOffset,
    const ref char[3] frameId,
    const ref char[3] subjectFrameId
)
    @safe
{
    diagnostics ~=
        Id3v22TagValidationDiagnostic(
            severity,
            code,
            frameIndex,
            relatedFrameIndex,
            sourceOffset,
            frameId,
            subjectFrameId
        );
}


private bool
sameOccurrenceIdentity(
    const ref ConstraintOccurrence left,
    const ref ConstraintOccurrence right
)
    @safe pure nothrow @nogc
{
    if (!idsEqual(left.subjectFrameId, right.subjectFrameId))
        return false;

    if (left.rule != right.rule)
        return false;

    final switch (left.rule)
    {
        case ConstraintRule.none:
            return false;

        case ConstraintRule.singlePerId:
            return true;

        case ConstraintRule.byIdentity:
            return left.identity == right.identity;

        case ConstraintRule.byLanguageAndIdentity:
            return
                idsEqual(left.language, right.language) &&
                left.identity == right.identity;
    }
}


private bool
sameLinkedContents(
    const ref Id3v22NativeFrame left,
    const ref Id3v22NativeFrame right
)
    @safe
{
    return
        left.content.match!(
            (const(Id3v22LinkedInformationFrame) leftLink) =>
                right.content.match!(
                    (const(Id3v22LinkedInformationFrame) rightLink) =>
                        idsEqual(
                            leftLink.linkedFrameId,
                            rightLink.linkedFrameId
                        ) &&
                        leftLink.linked.url ==
                            rightLink.linked.url &&
                        leftLink.linked.additionalKind ==
                            rightLink.linked.additionalKind &&
                        idsEqual(
                            leftLink.linked.language,
                            rightLink.linked.language
                        ) &&
                        leftLink.linked.descriptor ==
                            rightLink.linked.descriptor,

                    _ =>
                        false
                ),

            _ =>
                false
        );
}


private void
appendLocalSemanticOccurrences(
    const ref Id3v22NativeFrame frame,
    size_t frameIndex,
    ref ConstraintOccurrence[] occurrences,
    ref PictureTypeOccurrence[] pictureTypes
)
    @safe
{
    const physicalId =
        frame.envelope.header.id;

    const genericRule =
        genericRuleForId(physicalId);

    appendOccurrence(
        occurrences,
        frameIndex,
        frame.sourceOffset,
        physicalId,
        physicalId,
        genericRule
    );

    frame.content.match!(
        (const(Id3v22UserTextFrame) text)
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                physicalId,
                ConstraintRule.byIdentity,
                text.description
            );
        },

        (const(Id3v22UserUrlFrame) url)
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                physicalId,
                ConstraintRule.byIdentity,
                url.description
            );
        },

        (const(Id3v22UniqueFileIdentifierFrame) identifier)
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                physicalId,
                ConstraintRule.byIdentity,
                identifier.ownerIdentifier
            );
        },

        (const(Id3v22AudioEncryptionFrame) encryption)
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                physicalId,
                ConstraintRule.byIdentity,
                encryption.metadata.ownerIdentifier
            );
        },

        (const(Id3v22EncryptedMetaFrame) encrypted)
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                physicalId,
                ConstraintRule.byIdentity,
                encrypted.ownerIdentifier
            );
        },

        (const(Id3v22CommentFrame) comment)
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                physicalId,
                ConstraintRule.byLanguageAndIdentity,
                comment.description,
                comment.language
            );
        },

        (const(Id3v22LyricsTextFrame) lyrics)
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                physicalId,
                ConstraintRule.byLanguageAndIdentity,
                lyrics.descriptor,
                lyrics.language
            );
        },

        (const(Id3v22SynchronisedTextFrame) text)
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                physicalId,
                ConstraintRule.byLanguageAndIdentity,
                text.descriptor,
                text.language
            );
        },

        (const(Id3v22GeneralEncapsulatedObjectFrame) object)
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                physicalId,
                ConstraintRule.byIdentity,
                object.info.description
            );
        },

        (const(Id3v22AttachedPictureFrame) picture)
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                physicalId,
                ConstraintRule.byIdentity,
                picture.description
            );

            const type =
                cast(ubyte) picture.pictureType;

            if (
                type == 0x01 ||
                type == 0x02
            )
            {
                pictureTypes ~=
                    PictureTypeOccurrence(
                        frameIndex,
                        frame.sourceOffset,
                        physicalId,
                        type
                    );
            }
        },

        (const(Id3v22PopularityMeterFrame) meter)
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                physicalId,
                ConstraintRule.byIdentity,
                meter.popularity.email
            );
        },

        (_)
        {
        }
    );
}


private void
appendLinkedOccurrence(
    const ref Id3v22NativeFrame frame,
    size_t frameIndex,
    Id3v22LinkedInformationFrame link,
    ref ConstraintOccurrence[] occurrences,
    ref Id3v22TagValidationDiagnostic[] diagnostics
)
    @safe
{
    const physicalId =
        frame.envelope.header.id;

    const target =
        link.linkedFrameId;

    if (idEquals(target, "TXX"))
    {
        appendOccurrence(
            occurrences,
            frameIndex,
            frame.sourceOffset,
            physicalId,
            target,
            ConstraintRule.byIdentity,
            link.linked.descriptor
        );
        return;
    }

    if (target[0] == 'T')
    {
        appendOccurrence(
            occurrences,
            frameIndex,
            frame.sourceOffset,
            physicalId,
            target,
            ConstraintRule.singlePerId
        );
        return;
    }

    if (idEquals(target, "WXX"))
    {
        appendDiagnostic(
            diagnostics,
            Id3v22TagValidationSeverity.indeterminate,
            Id3v22TagValidationCode.unverifiableLinkedConstraint,
            frameIndex,
            size_t.max,
            frame.sourceOffset,
            physicalId,
            target
        );
        return;
    }

    if (target[0] == 'W')
    {
        if (
            !idEquals(target, "WAR") &&
            !idEquals(target, "WCM")
        )
        {
            appendOccurrence(
                occurrences,
                frameIndex,
                frame.sourceOffset,
                physicalId,
                target,
                ConstraintRule.singlePerId
            );
        }

        return;
    }

    if (isSingletonId(target))
    {
        appendOccurrence(
            occurrences,
            frameIndex,
            frame.sourceOffset,
            physicalId,
            target,
            ConstraintRule.singlePerId
        );
        return;
    }

    if (
        idEquals(target, "PIC") ||
        idEquals(target, "GEO")
    )
    {
        appendOccurrence(
            occurrences,
            frameIndex,
            frame.sourceOffset,
            physicalId,
            target,
            ConstraintRule.byIdentity,
            link.linked.descriptor
        );

        if (idEquals(target, "PIC"))
        {
            appendDiagnostic(
                diagnostics,
                Id3v22TagValidationSeverity.indeterminate,
                Id3v22TagValidationCode.unverifiableLinkedConstraint,
                frameIndex,
                size_t.max,
                frame.sourceOffset,
                physicalId,
                target
            );
        }

        return;
    }

    if (
        idEquals(target, "COM") ||
        idEquals(target, "SLT") ||
        idEquals(target, "ULT")
    )
    {
        appendOccurrence(
            occurrences,
            frameIndex,
            frame.sourceOffset,
            physicalId,
            target,
            ConstraintRule.byLanguageAndIdentity,
            link.linked.descriptor,
            link.linked.language
        );
        return;
    }

    if (
        idEquals(target, "CRA") ||
        idEquals(target, "CRM")
    )
    {
        appendDiagnostic(
            diagnostics,
            Id3v22TagValidationSeverity.indeterminate,
            Id3v22TagValidationCode.unverifiableLinkedConstraint,
            frameIndex,
            size_t.max,
            frame.sourceOffset,
            physicalId,
            target
        );
    }
}


private void
collectOccurrences(
    Id3v22NativeFrameSequence sequence,
    ref ConstraintOccurrence[] occurrences,
    ref PictureTypeOccurrence[] pictureTypes,
    ref Id3v22TagValidationDiagnostic[] diagnostics
)
    @safe
{
    foreach (
        frameIndex,
        ref frame;
        sequence.frames
    )
    {
        appendLocalSemanticOccurrences(
            frame,
            frameIndex,
            occurrences,
            pictureTypes
        );

        frame.content.match!(
            (const(Id3v22LinkedInformationFrame) link)
            {
                appendLinkedOccurrence(
                    frame,
                    frameIndex,
                    link,
                    occurrences,
                    diagnostics
                );
            },

            (_)
            {
            }
        );
    }
}


private void
validateOccurrenceDuplicates(
    const(ConstraintOccurrence)[] occurrences,
    ref Id3v22TagValidationDiagnostic[] diagnostics
)
    @safe
{
    foreach (
        rightIndex;
        0 .. occurrences.length
    )
    {
        const right =
            occurrences[rightIndex];

        foreach (
            leftIndex;
            0 .. rightIndex
        )
        {
            const left =
                occurrences[leftIndex];

            if (!sameOccurrenceIdentity(left, right))
                continue;

            appendDiagnostic(
                diagnostics,
                Id3v22TagValidationSeverity.error,
                right.rule == ConstraintRule.singlePerId
                    ? Id3v22TagValidationCode.duplicateSingleton
                    : Id3v22TagValidationCode.duplicateIdentity,
                right.frameIndex,
                left.frameIndex,
                right.sourceOffset,
                right.physicalFrameId,
                right.subjectFrameId
            );

            break;
        }
    }
}


private void
validatePictureTypes(
    const(PictureTypeOccurrence)[] pictures,
    ref Id3v22TagValidationDiagnostic[] diagnostics
)
    @safe
{
    foreach (
        rightIndex;
        0 .. pictures.length
    )
    {
        const right =
            pictures[rightIndex];

        foreach (
            leftIndex;
            0 .. rightIndex
        )
        {
            const left =
                pictures[leftIndex];

            if (left.pictureType != right.pictureType)
                continue;

            appendDiagnostic(
                diagnostics,
                Id3v22TagValidationSeverity.error,
                Id3v22TagValidationCode.duplicatePictureType,
                right.frameIndex,
                left.frameIndex,
                right.sourceOffset,
                right.physicalFrameId,
                right.physicalFrameId
            );

            break;
        }
    }
}


private void
validateDuplicateLinks(
    Id3v22NativeFrameSequence sequence,
    ref Id3v22TagValidationDiagnostic[] diagnostics
)
    @safe
{
    foreach (
        rightIndex;
        0 .. sequence.frames.length
    )
    {
        const right =
            sequence.frames[rightIndex];

        if (!idEquals(right.envelope.header.id, "LNK"))
            continue;

        foreach (
            leftIndex;
            0 .. rightIndex
        )
        {
            const left =
                sequence.frames[leftIndex];

            if (!sameLinkedContents(left, right))
                continue;

            appendDiagnostic(
                diagnostics,
                Id3v22TagValidationSeverity.error,
                Id3v22TagValidationCode.duplicateLinkContents,
                rightIndex,
                leftIndex,
                right.sourceOffset,
                right.envelope.header.id,
                right.envelope.header.id
            );

            break;
        }
    }
}


private void
validateMciTrackRequirement(
    Id3v22NativeFrameSequence sequence,
    const(ConstraintOccurrence)[] occurrences,
    ref Id3v22TagValidationDiagnostic[] diagnostics
)
    @safe
{
    bool hasMci;
    ConstraintOccurrence firstMci;

    bool hasLinkedTrk;
    bool hasLocalTrk;
    bool hasValidLocalTrk;

    foreach (const occurrence; occurrences)
    {
        if (
            !hasMci &&
            idEquals(
                occurrence.subjectFrameId,
                "MCI"
            )
        )
        {
            hasMci = true;
            firstMci = occurrence;
        }

        if (
            idEquals(
                occurrence.subjectFrameId,
                "TRK"
            ) &&
            idEquals(
                occurrence.physicalFrameId,
                "LNK"
            )
        )
        {
            hasLinkedTrk = true;
        }
    }

    if (!hasMci)
        return;

    foreach (const frame; sequence.frames)
    {
        frame.content.match!(
            (const(Id3v22TextInformationFrame) text)
            {
                if (!idEquals(text.id, "TRK"))
                    return;

                hasLocalTrk = true;

                if (
                    parseId3v2Position(
                        text.value
                    ).parsed
                )
                {
                    hasValidLocalTrk = true;
                }
            },

            (_)
            {
            }
        );
    }

    if (hasValidLocalTrk)
        return;

    const trkId =
        literalId(
            'T',
            'R',
            'K'
        );

    if (hasLinkedTrk)
    {
        appendDiagnostic(
            diagnostics,
            Id3v22TagValidationSeverity.indeterminate,
            Id3v22TagValidationCode.unverifiableLinkedConstraint,
            firstMci.frameIndex,
            size_t.max,
            firstMci.sourceOffset,
            firstMci.physicalFrameId,
            trkId
        );
        return;
    }

    appendDiagnostic(
        diagnostics,
        Id3v22TagValidationSeverity.error,
        hasLocalTrk
            ? Id3v22TagValidationCode.invalidRequiredFrame
            : Id3v22TagValidationCode.missingRequiredFrame,
        firstMci.frameIndex,
        size_t.max,
        firstMci.sourceOffset,
        firstMci.physicalFrameId,
        trkId
    );
}


/++
Validates tag-wide ID3v2.2.0 restrictions on an already decoded native frame
sequence.

Unknown frames remain untouched and do not cause diagnostics merely because
their semantics are unknown.

The validator performs no I/O and never dereferences `LNK` URLs. A restriction
that would require the linked frame body is reported as
`unverifiableLinkedConstraint`.

Params:
    sequence = Successfully decoded native ID3v2.2.0 frame sequence.

Returns:
    A deterministic report containing every locally discovered violation or
    indeterminate linked constraint.

Safety:
    Validation only reads decoded native values and allocates report arrays.
    It never reads outside source spans because all byte parsing has already
    completed before this function is called.

Complexity:
    O(n²) in the number of frames/virtual linked occurrences. ID3 tag frame
    counts are normally small, and the quadratic pass keeps identity semantics
    explicit and deterministic without hidden hash-normalisation policy.
+/
Id3v22TagValidationReport
validateId3v22NativeFrameSequence(
    Id3v22NativeFrameSequence sequence
)
    @safe
{
    Id3v22TagValidationDiagnostic[] diagnostics;

    if (sequence.frames.length == 0)
    {
        const none =
            char[3].init;

        appendDiagnostic(
            diagnostics,
            Id3v22TagValidationSeverity.error,
            Id3v22TagValidationCode.emptyTag,
            size_t.max,
            size_t.max,
            sequence.layout.frameBytes.sourceOffset,
            none,
            none
        );

        return
            Id3v22TagValidationReport(
                diagnostics
            );
    }

    ConstraintOccurrence[] occurrences;
    PictureTypeOccurrence[] pictureTypes;

    collectOccurrences(
        sequence,
        occurrences,
        pictureTypes,
        diagnostics
    );

    validateOccurrenceDuplicates(
        occurrences,
        diagnostics
    );

    validatePictureTypes(
        pictureTypes,
        diagnostics
    );

    validateDuplicateLinks(
        sequence,
        diagnostics
    );

    validateMciTrackRequirement(
        sequence,
        occurrences,
        diagnostics
    );

    return
        Id3v22TagValidationReport(
            diagnostics
        );
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.frame_sequence :
        parseId3v22FrameSequenceLayout;

    import audiotag.id3v2.v22.native_sequence :
        decodeId3v22NativeFrameSequence;


    private Id3v22NativeFrameSequence
    testSequence(
        const(ubyte)[] bytes,
        size_t sourceOffset = 100
    )
        @safe
    {
        auto layout =
            parseId3v22FrameSequenceLayout(
                ByteSpan(
                    bytes,
                    sourceOffset
                )
            );

        assert(layout.hasValue);

        auto sequence =
            decodeId3v22NativeFrameSequence(
                layout.value
            );

        assert(sequence.hasValue);

        return sequence.value;
    }


    private bool
    hasDiagnostic(
        const Id3v22TagValidationReport report,
        Id3v22TagValidationCode code,
        Id3v22TagValidationSeverity severity =
            Id3v22TagValidationSeverity.error
    )
        @safe pure nothrow @nogc
    {
        foreach (const diagnostic; report.diagnostics)
        {
            if (
                diagnostic.code == code &&
                diagnostic.severity == severity
            )
            {
                return true;
            }
        }

        return false;
    }
}


/// Ordinary text-information frames are singleton by native frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x02,
            0x00, 'A',

            'T', 'T', '2',
            0x00, 0x00, 0x02,
            0x00, 'B'
        ];

    const report =
        validateId3v22NativeFrameSequence(
            testSequence(bytes)
        );

    assert(report.hasViolations);
    assert(
        hasDiagnostic(
            report,
            Id3v22TagValidationCode.duplicateSingleton
        )
    );
}


/// WAR is explicitly repeatable and therefore does not trigger URL singleton logic.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'A', 'R',
            0x00, 0x00, 0x01,
            'a',

            'W', 'A', 'R',
            0x00, 0x00, 0x01,
            'b'
        ];

    const report =
        validateId3v22NativeFrameSequence(
            testSequence(bytes)
        );

    assert(report.strictlyConformant);
}


/// TXX uniqueness is keyed by the decoded description rather than frame ID alone.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X',
            0x00, 0x00, 0x04,
            0x00, 'x', 0x00, '1',

            'T', 'X', 'X',
            0x00, 0x00, 0x04,
            0x00, 'x', 0x00, '2'
        ];

    const report =
        validateId3v22NativeFrameSequence(
            testSequence(bytes)
        );

    assert(
        hasDiagnostic(
            report,
            Id3v22TagValidationCode.duplicateIdentity
        )
    );
}


/// Owner-keyed UFI multiplicity is enforced tag-wide.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x03,
            'x', 0x00, 0x01,

            'U', 'F', 'I',
            0x00, 0x00, 0x03,
            'x', 0x00, 0x02
        ];

    const report =
        validateId3v22NativeFrameSequence(
            testSequence(bytes)
        );

    assert(
        hasDiagnostic(
            report,
            Id3v22TagValidationCode.duplicateIdentity
        )
    );
}


/// COM identity is language plus short content description.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',
            0x00, 0x00, 0x07,
            0x00,
            'e', 'n', 'g',
            'x', 0x00,
            'A',

            'C', 'O', 'M',
            0x00, 0x00, 0x07,
            0x00,
            'e', 'n', 'g',
            'x', 0x00,
            'B'
        ];

    const report =
        validateId3v22NativeFrameSequence(
            testSequence(bytes)
        );

    assert(
        hasDiagnostic(
            report,
            Id3v22TagValidationCode.duplicateIdentity
        )
    );
}


/// PIC enforces both descriptor identity and the special $01/$02 type cardinality.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',
            0x00, 0x00, 0x08,
            0x00,
            'J', 'P', 'G',
            0x01,
            'a', 0x00,
            0x11,

            'P', 'I', 'C',
            0x00, 0x00, 0x08,
            0x00,
            'P', 'N', 'G',
            0x01,
            'b', 0x00,
            0x22
        ];

    const report =
        validateId3v22NativeFrameSequence(
            testSequence(bytes)
        );

    assert(
        hasDiagnostic(
            report,
            Id3v22TagValidationCode.duplicatePictureType
        )
    );

    assert(
        !hasDiagnostic(
            report,
            Id3v22TagValidationCode.duplicateIdentity
        )
    );
}


/// A linked singleton counts as if the target frame were physically present.
unittest
{
    const ubyte[] bytes =
        [
            'R', 'E', 'V',
            0x00, 0x00, 0x0C,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,

            'L', 'N', 'K',
            0x00, 0x00, 0x05,
            'R', 'E', 'V',
            'x', 0x00
        ];

    const report =
        validateId3v22NativeFrameSequence(
            testSequence(bytes)
        );

    assert(
        hasDiagnostic(
            report,
            Id3v22TagValidationCode.duplicateSingleton
        )
    );
}


/// Equal LNK semantic contents are rejected independently of target cardinality.
unittest
{
    const ubyte[] bytes =
        [
            'L', 'N', 'K',
            0x00, 0x00, 0x05,
            'R', 'E', 'V',
            'x', 0x00,

            'L', 'N', 'K',
            0x00, 0x00, 0x05,
            'R', 'E', 'V',
            'x', 0x00
        ];

    const report =
        validateId3v22NativeFrameSequence(
            testSequence(bytes)
        );

    assert(
        hasDiagnostic(
            report,
            Id3v22TagValidationCode.duplicateLinkContents
        )
    );
}


/// MCI requires a local syntactically valid TRK when no linked TRK is available.
unittest
{
    const ubyte[] missingBytes =
        [
            'M', 'C', 'I',
            0x00, 0x00, 0x04,
            0x00, 0x00, 0x00, 0x00
        ];

    const missing =
        validateId3v22NativeFrameSequence(
            testSequence(missingBytes)
        );

    assert(
        hasDiagnostic(
            missing,
            Id3v22TagValidationCode.missingRequiredFrame
        )
    );

    const ubyte[] invalidBytes =
        [
            'T', 'R', 'K',
            0x00, 0x00, 0x02,
            0x00, 'x',

            'M', 'C', 'I',
            0x00, 0x00, 0x04,
            0x00, 0x00, 0x00, 0x00
        ];

    const invalid =
        validateId3v22NativeFrameSequence(
            testSequence(invalidBytes)
        );

    assert(
        hasDiagnostic(
            invalid,
            Id3v22TagValidationCode.invalidRequiredFrame
        )
    );

    const ubyte[] validBytes =
        [
            'T', 'R', 'K',
            0x00, 0x00, 0x04,
            0x00, '4', '/', '9',

            'M', 'C', 'I',
            0x00, 0x00, 0x04,
            0x00, 0x00, 0x00, 0x00
        ];

    const valid =
        validateId3v22NativeFrameSequence(
            testSequence(validBytes)
        );

    assert(valid.strictlyConformant);
}


/// A linked TRK can satisfy MCI only after dereferencing, so the result is indeterminate.
unittest
{
    const ubyte[] bytes =
        [
            'M', 'C', 'I',
            0x00, 0x00, 0x04,
            0x00, 0x00, 0x00, 0x00,

            'L', 'N', 'K',
            0x00, 0x00, 0x05,
            'T', 'R', 'K',
            'x', 0x00
        ];

    const report =
        validateId3v22NativeFrameSequence(
            testSequence(bytes)
        );

    assert(!report.hasViolations);
    assert(report.hasIndeterminate);
    assert(!report.strictlyConformant);

    assert(
        hasDiagnostic(
            report,
            Id3v22TagValidationCode.unverifiableLinkedConstraint,
            Id3v22TagValidationSeverity.indeterminate
        )
    );
}


/// Linked PIC preserves descriptor checking but leaves picture-type cardinality indeterminate.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',
            0x00, 0x00, 0x08,
            0x00,
            'J', 'P', 'G',
            0x03,
            'x', 0x00,
            0x11,

            'L', 'N', 'K',
            0x00, 0x00, 0x06,
            'P', 'I', 'C',
            'u', 0x00,
            'x'
        ];

    const report =
        validateId3v22NativeFrameSequence(
            testSequence(bytes)
        );

    assert(
        hasDiagnostic(
            report,
            Id3v22TagValidationCode.duplicateIdentity
        )
    );

    assert(
        hasDiagnostic(
            report,
            Id3v22TagValidationCode.unverifiableLinkedConstraint,
            Id3v22TagValidationSeverity.indeterminate
        )
    );
}


/// An empty decoded sequence cannot represent a conformant non-compressed tag.
unittest
{
    Id3v22NativeFrameSequence sequence;

    const report =
        validateId3v22NativeFrameSequence(
            sequence
        );

    assert(
        hasDiagnostic(
            report,
            Id3v22TagValidationCode.emptyTag
        )
    );
}
