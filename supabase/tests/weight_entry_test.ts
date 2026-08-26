import { assertEquals } from 'jsr:@std/assert'
import { canonicalUUID, findWeightEntryIndex } from '../functions/_shared/weight-entry.ts'

const lowercaseID = 'ed93f64a-7dc5-4145-91cd-c6c0afea81dc'

Deno.test('weight entry IDs compare canonically regardless of UUID case', () => {
  const entries = [{ id: lowercaseID }]

  assertEquals(findWeightEntryIndex(entries, lowercaseID.toUpperCase()), 0)
  assertEquals(findWeightEntryIndex(entries, lowercaseID), 0)
})

Deno.test('missing or genuinely unknown weight entry IDs do not match', () => {
  const entries = [{ id: lowercaseID }]

  assertEquals(findWeightEntryIndex(entries, undefined), -1)
  assertEquals(findWeightEntryIndex(entries, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), -1)
})

Deno.test('UUID canonicalization trims and lowercases values', () => {
  assertEquals(canonicalUUID(`  ${lowercaseID.toUpperCase()}  `), lowercaseID)
})
