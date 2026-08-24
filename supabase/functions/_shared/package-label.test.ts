import { assertEquals } from "jsr:@std/assert";
import { applyNutritionFootnoteDeclarations } from "./package-label.ts";

Deno.test("nutrition footnote becomes explicit declarations without duplicates", () => {
  const result = applyNutritionFootnoteDeclarations(
    [{ code: "energy_kcal", amount_per_serving: 10, unit: "kcal" }, {
      code: "saturated_fat_g",
      amount_per_serving: 0,
      unit: "g",
    }],
    "Not a significant source of saturated fat, trans fat, cholesterol, dietary fiber, total sugars, added sugars, vitamin D, iron, and potassium.",
  );

  assertEquals(
    result.filter((item) => item.code === "saturated_fat_g").length,
    1,
  );
  assertEquals(
    result.find((item) => item.code === "trans_fat_g")?.declaration_type,
    "not_significant_source",
  );
  assertEquals(
    result.find((item) => item.code === "potassium_mg")?.amount_per_serving,
    0,
  );
  assertEquals(result.length, 10);
});
