import type { ClassifiedIngredient, ParsedIngredient, PFQSAdditiveResult, PFQSIngredientResult } from './types.ts'

export function ingredientCanonicalID(name: string) {
  const slug = name.normalize('NFKD').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '')
  return `ingredient_${slug || 'unknown'}`
}

export function buildIngredientCatalog(
  parsed: ParsedIngredient[],
  classified: ClassifiedIngredient[],
  concerns: PFQSAdditiveResult[],
): PFQSIngredientResult[] {
  const classifications = new Map(classified.map((item) => [item.canonical_name, item]))
  const concernAliases = new Map<string, PFQSAdditiveResult>()
  for (const concern of concerns) {
    concernAliases.set(concern.matched_alias.toLowerCase(), concern)
    concernAliases.set(concern.name.toLowerCase(), concern)
  }
  const results: PFQSIngredientResult[] = []
  const walk = (items: ParsedIngredient[], level: number, parentPath = '') => {
    items.forEach((item, index) => {
      const ingredientPath = parentPath ? `${parentPath}.${index + 1}` : `${index + 1}`
    const classification = classifications.get(item.canonical_name)
    const concern = concernAliases.get(item.canonical_name) ?? concernAliases.get(item.raw.toLowerCase())
      results.push({
      canonical_id: ingredientCanonicalID(item.canonical_name),
      canonical_name: item.canonical_name,
      raw: item.raw,
      position: item.position,
      depth: level,
      parent_canonical_id: item.parent ? ingredientCanonicalID(item.parent) : null,
      percentage: item.percentage,
      ingredient_path: ingredientPath,
      quality_class: classification?.quality_class ?? null,
      quality_coefficient: classification?.quality_coefficient ?? null,
      beneficial: classification?.beneficial ?? false,
      classification_confidence: classification?.confidence ?? null,
      classification_source: classification?.classification_source ?? null,
      review_status: concern ? 'reviewed' : classification ? 'classified' : 'unclassified',
      risk_canonical_id: concern?.canonical_id ?? null,
      })
      walk(item.subingredients, level + 1, ingredientPath)
    })
  }
  walk(parsed, 0)
  return results
}
