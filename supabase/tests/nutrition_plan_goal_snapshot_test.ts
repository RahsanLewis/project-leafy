import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1'

const CONSTRAINT = 'nutrition_plans_input_snapshot_goal_check'
const migration = await Deno.readTextFile(
  new URL(
    '../migrations/202609030001_nutrition_plans_input_snapshot_goal_check.sql',
    import.meta.url,
  ),
)

function checkExpression(sql: string): string {
  const match = sql.match(
    /add constraint\s+nutrition_plans_input_snapshot_goal_check\s+check\s*\(([\s\S]*?)\)\s*not valid/i,
  )
  if (!match) {
    throw new Error('Could not extract CHECK expression from ADD CONSTRAINT ... NOT VALID')
  }
  return match[1]
}

Deno.test('nutrition_plans input_snapshot goal CHECK is added NOT VALID then VALIDATE', () => {
  const addMatch = migration.match(/add constraint\s+(\w+)\s+check/i)
  const validateMatch = migration.match(/validate constraint\s+(\w+)/i)
  assertEquals(addMatch?.[1], CONSTRAINT)
  assertEquals(validateMatch?.[1], CONSTRAINT)
  assertEquals(addMatch?.[1], validateMatch?.[1])
  assert(/add constraint[\s\S]+not valid/i.test(migration))
  assertStringIncludes(migration, `validate constraint ${CONSTRAINT}`)
})

Deno.test('nutrition_plans input_snapshot goal CHECK requires the key and a coalesce-wrapped label', () => {
  const check = checkExpression(migration)
  assertStringIncludes(check, "input_snapshot ? 'goal'")
  assert(
    /coalesce\s*\(\s*input_snapshot->>'goal'\s+in\s*\(/i.test(check),
    "CHECK must wrap input_snapshot->>'goal' IN (...) with coalesce so SQL NULL is false, not UNKNOWN",
  )
  assertStringIncludes(check, 'lose')
  assertStringIncludes(check, 'maintain')
  assertStringIncludes(check, 'gain')
  const inListWithoutWrapper = check.replace(/coalesce\s*\(\s*input_snapshot->>'goal'\s+in\s*\([^)]*\)\s*,\s*false\s*\)/gi, '')
  assert(
    !/->>'goal'\s+in\s*\(/i.test(inListWithoutWrapper),
    "bare ->>'goal' IN (...) without a null-forcing wrapper is not accepted",
  )
})

Deno.test('nutrition_plans input_snapshot CHECK is goal-only and does not constrain pace or target weight', () => {
  const check = checkExpression(migration)
  assert(!/\bpace\b/.test(check), 'pace must not appear in the CHECK expression')
  assert(!/target_weight_kg/.test(check), 'target_weight_kg must not appear in the CHECK expression')
  assert(!/\bpace\b/.test(migration), 'migration must not mention pace as a constrained field')
  assert(
    !/target_weight_kg/.test(migration),
    'migration must not mention target_weight_kg as a constrained field',
  )
})

// Required cases (source-string CI; no live Postgres). How the CHECK treats them:
// - missing key → reject (`input_snapshot ? 'goal'` is false)
// - JSON null goal (`{"goal": null}`) → reject
//     This is the three-valued-logic hole: `? 'goal'` passes, `->>'goal'` is
//     SQL NULL, `NULL IN (...)` is UNKNOWN, and CHECK treats UNKNOWN as pass.
//     `coalesce(..., false)` forces false on SQL NULL.
// - invalid string (e.g. "maintainence") → reject (not in lose/maintain/gain)
// - valid lose / maintain / gain → accept
// - maintain with missing or null target_weight_kg → accept (not constrained)
Deno.test('nutrition_plans input_snapshot goal CHECK documents required accept/reject cases', () => {
  const check = checkExpression(migration)
  assertStringIncludes(check, "input_snapshot ? 'goal'")
  assertStringIncludes(check, 'coalesce(')
  assertStringIncludes(check, 'false')
  assertStringIncludes(check, "'lose'")
  assertStringIncludes(check, "'maintain'")
  assertStringIncludes(check, "'gain'")
  assert(!/target_weight_kg/.test(check))
})
