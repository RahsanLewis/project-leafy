export type LabelNutrient = {
  code: string;
  amount_per_serving: number;
  unit: string;
  percent_daily_value?: number | null;
  declaration_type?: string;
  printed_text?: string | null;
  evidence_section?: string | null;
  confidence?: number;
};

const FOOTNOTE_NUTRIENTS: Array<
  { code: string; unit: string; aliases: string[] }
> = [
  { code: "saturated_fat_g", unit: "g", aliases: ["saturated fat", "sat fat"] },
  { code: "trans_fat_g", unit: "g", aliases: ["trans fat"] },
  { code: "cholesterol_mg", unit: "mg", aliases: ["cholesterol"] },
  { code: "fiber_g", unit: "g", aliases: ["dietary fiber", "fiber"] },
  { code: "sugars_g", unit: "g", aliases: ["total sugars", "total sugar"] },
  {
    code: "added_sugars_g",
    unit: "g",
    aliases: ["added sugars", "added sugar"],
  },
  { code: "vitamin_d_mcg", unit: "mcg", aliases: ["vitamin d"] },
  { code: "iron_mg", unit: "mg", aliases: ["iron"] },
  { code: "potassium_mg", unit: "mg", aliases: ["potassium"] },
];

// FDA labels use this footnote to declare trace/insignificant amounts. Preserve
// that declaration instead of presenting every named nutrient as missing.
export function applyNutritionFootnoteDeclarations(
  nutrients: LabelNutrient[],
  rawFootnote: string,
): LabelNutrient[] {
  const footnote = rawFootnote.toLowerCase().replace(/[‐‑‒–—]/g, "-").replace(
    /\s+/g,
    " ",
  ).trim();
  if (!footnote.includes("not a significant source")) return nutrients;

  const byCode = new Map(
    nutrients.map((nutrient) => [nutrient.code, nutrient]),
  );
  for (const definition of FOOTNOTE_NUTRIENTS) {
    if (
      !definition.aliases.some((alias) => footnote.includes(alias)) ||
      byCode.has(definition.code)
    ) continue;
    byCode.set(definition.code, {
      code: definition.code,
      amount_per_serving: 0,
      unit: definition.unit,
      percent_daily_value: 0,
      declaration_type: "not_significant_source",
      printed_text: `Not a significant source of ${definition.aliases[0]}`,
      evidence_section: "nutrition_footnote",
      confidence: 1,
    });
  }
  return [...byCode.values()];
}
