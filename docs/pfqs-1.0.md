# Packaged Food Quality Score (PFQS) 1.0

PFQS 1.0 is Leafy's deterministic packaged-food scoring model. In the app it is presented as **Leafy Score**.

## Score architecture

The base score is the sum of seven independently explainable components:

| Component | Maximum |
| --- | ---: |
| Added sugar | 20 |
| Fiber | 15 |
| Sodium | 15 |
| Saturated/trans fat | 10 |
| Protein | 10 |
| Whole-food ingredient quality | 20 |
| Beneficial food contribution | 10 |

Nutrients are evaluated per 100 calories using a 50-calorie normalization floor. The ingredient components use the first five top-level ingredients with weights of 0.45, 0.25, 0.15, 0.10, and 0.05. Products with fewer than five ingredients normalize the available weights.

An independently versioned additive registry may subtract up to 25 points. An additive is penalized only when a jurisdiction- and date-specific rule assigns it a nonzero tier. Unknown or unclassified additives receive no penalty. Tier 4 also limits the final score to 50 and produces a separate regulatory flag.

## Eligibility

An official score requires:

- a verified or community-confirmed packaged food;
- a labeled serving;
- explicitly reported calories, added sugar, fiber, sodium, saturated fat, trans fat, and protein;
- a complete ingredient list; and
- confident classifications for every top-five ingredient.

Missing data returns `score_status = incomplete`. Scores are not rescaled from partial data. Supplements, infant formula, medical foods, alcohol, restaurant entries, manual entries, and AI estimates are ineligible.

## Versioning and release gate

Every result stores its model, taxonomy, additive database, assessment date, jurisdiction, input snapshot, components, and explanation. Historical scores remain reproducible.

`PFQS-1.0` is inserted as a draft release. The consumer API reads only an active PFQS release, which intentionally hides legacy scores and prevents an unvalidated PFQS build from reaching users. Activation should occur only after:

1. threshold and integration tests pass;
2. the fixed USDA validation corpus is reviewed;
3. additive alias coverage reaches the launch gate;
4. every penalty-bearing additive record is human-reviewed; and
5. the validation report is attached to the release row.

## Module boundaries

- `pfqs/scorer.ts`: deterministic nutrition, ingredient, penalty, ceiling, and explanation rules
- `pfqs/ingredient-parser.ts`: top-level and nested ingredient parsing
- `pfqs/ingredient-taxonomy.ts`: curated food-quality classifications
- `pfqs/additive-registry.ts`: canonical aliases and date/jurisdiction rules
- `pfqs/persistence.ts`: immutable score and ingredient snapshots
- `202608130002_pfqs_1_0_foundation.sql`: release, label nutrient, evidence, and score schema

PFQS is consumer wellness guidance. It is not a medical diagnosis, toxicological risk assessment, or government-approved healthy-food definition.
