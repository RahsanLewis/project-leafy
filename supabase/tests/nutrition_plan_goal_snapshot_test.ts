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

// STATIC migration-shape coverage only. These tests read the SQL file and pin
// required tokens. They do not connect to Postgres and do not prove CHECK
// evaluation, three-valued logic, or UNKNOWN handling. Live engine evidence
// lives on the PR body (read-only SELECT truth table).

Deno.test('STATIC: nutrition_plans goal CHECK migration adds NOT VALID then VALIDATE', () => {
  const addMatch = migration.match(/add constraint\s+(\w+)\s+check/i)
  const validateMatch = migration.match(/validate constraint\s+(\w+)/i)
  assertEquals(addMatch?.[1], CONSTRAINT)
  assertEquals(validateMatch?.[1], CONSTRAINT)
  assertEquals(addMatch?.[1], validateMatch?.[1])
  assert(/add constraint[\s\S]+not valid/i.test(migration))
  assertStringIncludes(migration, `validate constraint ${CONSTRAINT}`)
})

Deno.test('STATIC: nutrition_plans goal CHECK shape requires key + parenthesized coalesce IN-list', () => {
  const check = checkExpression(migration)
  assertStringIncludes(check, "input_snapshot ? 'goal'")
  assert(
    /coalesce\s*\(\s*\(\s*input_snapshot->>'goal'\s*\)\s+in\s*\(/i.test(check),
    "migration shape must include coalesce((input_snapshot->>'goal') IN (...), false)",
  )
  assertStringIncludes(check, 'lose')
  assertStringIncludes(check, 'maintain')
  assertStringIncludes(check, 'gain')
  const stripped = check.replace(
    /coalesce\s*\(\s*\(\s*input_snapshot->>'goal'\s*\)\s+in\s*\([^)]*\)\s*,\s*false\s*\)/gi,
    '',
  )
  assert(
    !/->>'goal'\s*\)?\s+in\s*\(/i.test(stripped),
    "migration shape must not leave a bare ->>'goal' IN (...) without coalesce((...) IN (...), false)",
  )
})

Deno.test('STATIC: nutrition_plans goal CHECK is goal-only (no pace / target_weight_kg)', () => {
  const check = checkExpression(migration)
  assert(!/\bpace\b/.test(check), 'pace must not appear in the CHECK expression')
  assert(!/target_weight_kg/.test(check), 'target_weight_kg must not appear in the CHECK expression')
  assert(!/\bpace\b/.test(migration), 'migration must not mention pace as a constrained field')
  assert(
    !/target_weight_kg/.test(migration),
    'migration must not mention target_weight_kg as a constrained field',
  )
})
