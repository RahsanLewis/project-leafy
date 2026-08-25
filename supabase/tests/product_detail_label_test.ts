import { assertStringIncludes } from 'jsr:@std/assert@1'

const discovery = await Deno.readTextFile(new URL('../functions/discover-food-product/index.ts', import.meta.url))
const release = await Deno.readTextFile(new URL('../migrations/202608250001_release_pfqs_and_product_refresh.sql', import.meta.url))

Deno.test('product detail returns package-serving nutrients and every active PFQS status', () => {
  assertStringIncludes(discovery, "from('food_version_serving_nutrients')")
  assertStringIncludes(discovery, 'label_nutrients:')
  assertStringIncludes(discovery, "value_source: item.declaration_type === 'derived'")
  if (discovery.includes(".eq('score_status', 'complete')")) throw new Error('Incomplete PFQS results must remain visible to the client.')
})

Deno.test('PFQS release and catalog replacement are explicit and atomic', () => {
  assertStringIncludes(release, "set status = 'active'")
  assertStringIncludes(release, "set status = 'retired'")
  assertStringIncludes(release, 'create or replace function public.activate_food_version_replacement')
  assertStringIncludes(release, "declaration_type, evidence_section")
  assertStringIncludes(release, "lower(fv.serving_unit) in ('g', 'gram', 'grams', 'grm')")
})
