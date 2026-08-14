# Leafy Score v2.1 hybrid methodology and release gate

Status: **draft — not active in production**

Leafy Score v2 is a non-personalized packaged-food quality score calculated per the labeled serving. It is not medical advice, a safety certification, or an instruction about how much of a food a person should eat.

## Formula

The nutrition base starts at 50. Encouraged nutrients add up to 50 points: fiber 15, protein 10, potassium 8, calcium 6, iron 6, and vitamin D 5. Each benefit scales linearly from 0 to 20% of the current FDA Daily Value.

Nutrients to limit subtract up to 50 points: added sugar 20, saturated fat 15, and sodium 15. No points are removed through 5% Daily Value; the deduction then scales linearly and reaches its maximum at 20% Daily Value. Calories, total carbohydrate, and total fat do not directly change the score.

The nutrition base is clamped to 0–100. A versioned ingredient registry then applies two transparent, package-visible layers. FDA active-review evidence removes 4 points and completed federal action removes 12. Distinct formulation classes remove 3 points each, capped at 15. If an ingredient has both an FDA evidence status and a formulation class, its class is suppressed so the same declaration is not penalized twice. The combined ingredient deduction is capped at 40 points. “Natural flavor” is disclosed without a deduction; “artificial flavor” contributes one formulation class. Unknown declarations receive no penalty. The final score is `max(0, nutrition base − ingredient deduction)`.

The registry version is `leafy-additives-us-v2-hybrid`. It contains 74 additive entries or families across 11 formulation classes. Every entry includes aliases, FDA status, separate evidence and processing rationales, a primary FDA citation, and a review date.

Bands are 80–100 Excellent, 65–79 Good, 50–64 Fair, 30–49 Poor, and 0–29 Very poor. Verified plain water is a documented 100-point exception.

## Label data and eligibility

A score is unavailable unless the product has a verified labeled serving in grams or milliliters; all nine required scoring nutrients; a complete ingredient list or verified single-ingredient exception; and `verified` or `community_confirmed` catalog status. Package-provided Daily Value percentages take precedence over calculated percentages. Otherwise the scorer derives per-serving values only from a compatible package basis. A missing USDA nutrient is never interpreted as zero. Supplements, infant formula, medical food, alcohol, manual entries, and AI estimates are excluded.

## USDA benchmark

The reproducible benchmark runner is `scripts/benchmark-leafy-score-v2.ts`. It streams the fixed USDA FoodData Central Branded Foods April 30, 2026 JSON release, samples 15 products across each of 20 adult packaged-food categories, and produces a local HTML report, reviewer CSV, and run manifest. Artifacts are intentionally gitignored and the runner does not write to Supabase or alter the active score release.

In the expanded-registry run, 206 of 300 products receive an ingredient deduction, versus 11 with the narrow v1 evidence registry. Thirty-nine products have FDA-evidence deductions, 205 have formulation deductions, and 75 products move score bands. The median changes from 46 to 42. The HTML and CSV include old and new scores, separate deduction layers, matches, classes, and band movement. These figures are validation evidence only; v2.1 remains a draft.

## Governance

The formula and additive registry have independent versions. Registry entries require aliases, a rationale, a primary source, and review date. Classification is a transparent policy layer, not an AI judgment. Activation is server controlled in `nutrition_score_releases` and the database rejects activation until benchmark completion and expert review are recorded.

## Required pre-activation checks

- [ ] Golden-corpus boundary and serving-size tests pass.
- [ ] Duplicate aliases and unknown-ingredient cases pass.
- [ ] Plain-water and single-ingredient exceptions pass.
- [ ] At least 100 representative US packaged foods reviewed for face validity.
- [ ] Registered dietitian reviews nutrient weights, user-facing claims, and edge cases.
- [ ] Food-regulatory counsel reviews additive wording and citations.
- [ ] Backfill completes for all eligible active catalog versions.
- [ ] UI and API show unavailable reasons without falling back to v1.
- [ ] App privacy disclosures and App Store answers match the shipped behavior.

Activation requires setting the draft release’s benchmark and expert-review fields, retiring the prior active release, and making v2 active in one transaction.

Run the catalog audit without writes using `deno run --allow-env --allow-net scripts/backfill-leafy-score-v2.ts`. After reviewing the counts, repeat with `--apply`. This operation is idempotent because scores are keyed by food version and algorithm version.
