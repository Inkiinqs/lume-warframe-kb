# Placeholder Policy

This repository currently contains two kinds of records:

- sourced records
- scaffold placeholders

## Placeholder rules

- Placeholder records are allowed only when they establish structure that will later be replaced by sourced data.
- Placeholder records should say so in `notes` when the risk of confusion is high.
- Placeholder records must never silently override validated sourced records.
- Import jobs should replace placeholder content record-by-record, not by rewriting whole domains blindly.

## Recommended upgrade pattern

1. keep the existing internal ID if the placeholder represents the same concept
2. replace summary, stats, mechanics, and notes with sourced data
3. update `sources` to reflect the import origin
4. remove placeholder caveats once the record is validated

## High-risk placeholder areas

- relic contents
- exact drop tables
- patch-sensitive formulas
- modern status details
- live rotations and schedules
