import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import { calculate, type Input } from "../functions/_shared/calculator.ts";

type Expected = ReturnType<typeof calculate>;
type Fixture = { name: string; now: string; input: Input; expected: Expected };
const fixtures = JSON.parse(
  await Deno.readTextFile(
    new URL("../../SharedContracts/calculator-fixtures.json", import.meta.url),
  ),
) as Fixture[];

for (const fixture of fixtures) {
  Deno.test(`calculator golden: ${fixture.name}`, () => {
    const result = calculate(fixture.input, new Date(fixture.now));
    assertEquals({ ...result, projected_weekly_change_kg: 0 }, {
      ...fixture.expected,
      projected_weekly_change_kg: 0,
    });
    assertAlmostEquals(
      result.projected_weekly_change_kg,
      fixture.expected.projected_weekly_change_kg,
      1e-12,
    );
  });
}
