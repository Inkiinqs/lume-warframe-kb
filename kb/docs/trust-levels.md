# Trust Levels

Use these trust levels mentally when working with repository data.

## Level 1: scaffold

Structure-first records added to define repository shape.

Characteristics:

- may use placeholders
- may omit exact values
- should not be treated as patch-accurate truth

## Level 2: curated

Manually reviewed records that are intentionally authored and checked.

Characteristics:

- reliable for broad logic
- may still need exact-value updates after patches

## Level 3: sourced and validated

Records replaced or refreshed from known sources and validated against the repository contracts.

Characteristics:

- safe for production queries
- should carry accurate provenance in `sources`

The current repository is mostly Level 1 with some curated structural decisions.
