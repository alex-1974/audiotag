# ADR 0005: Tests and documentation are part of the definition of done

## Status

Accepted.

## Context

Binary parser bugs frequently occur at boundaries and malformed inputs. Retrofitting tests after many formats are implemented would make regressions difficult to isolate.

D provides integrated `unittest` blocks and Ddoc documentation.

## Decision

Every new public/core function requires:

- implementation;
- Ddoc documentation;
- direct unit tests.

Parser fixes require regression tests.

Malformed-input behavior must be tested explicitly.

Public examples should use documented `unittest` blocks where practical.

Git commits should remain small enough that build/test regressions can be bisected.

## Consequences

- development is somewhat slower per feature;
- parser invariants become executable specifications;
- documentation examples remain compilable;
- regression history becomes significantly more reliable.
