import { PFQS_QUALITY_COEFFICIENTS } from './config.ts'
import { canonicalizeIngredient } from './ingredient-parser.ts'
import type { ClassifiedIngredient, FrozenIngredientClassification, ParsedIngredient } from './types.ts'
import { recognizedAdditive } from './additive-registry.ts'

type TaxonomyClass = 'A' | 'B' | 'C' | 'D' | 'E'
type TaxonomyEntry = { canonical_name: string; aliases: string[]; quality_class: TaxonomyClass; beneficial: boolean }

function entry(canonical_name: string, aliases: string[], quality_class: TaxonomyClass, beneficial: boolean): TaxonomyEntry {
  return { canonical_name, aliases: [canonical_name, ...aliases].map(canonicalizeIngredient), quality_class, beneficial }
}

// This is deliberately a curated taxonomy, not a sentiment model. New aliases
// must be reviewed and versioned before they affect a score.
export const ingredientTaxonomy: TaxonomyEntry[] = [
  entry('whole grain oats', ['whole oats', 'rolled oats', 'oats', 'oat groats'], 'A', true),
  entry('whole wheat', ['whole wheat flour', 'whole grain wheat', 'whole durum wheat'], 'A', true),
  entry('brown rice', ['whole grain brown rice', 'brown rice flour'], 'A', true),
  entry('quinoa', ['whole grain quinoa'], 'A', true),
  entry('barley', ['whole grain barley', 'hulled barley'], 'A', true),
  entry('corn', ['whole grain corn', 'whole corn', 'popcorn'], 'A', true),
  entry('beans', ['black beans', 'kidney beans', 'pinto beans', 'navy beans', 'white beans'], 'A', true),
  entry('chickpeas', ['garbanzo beans'], 'A', true),
  entry('lentils', ['red lentils', 'green lentils'], 'A', true),
  entry('peas', ['green peas', 'split peas'], 'A', true),
  entry('almonds', ['almond'], 'A', true),
  entry('peanuts', ['peanut'], 'A', true),
  entry('walnuts', ['walnut'], 'A', true),
  entry('cashews', ['cashew'], 'A', true),
  entry('pistachios', ['pistachio'], 'A', true),
  entry('pecans', ['pecan'], 'A', true),
  entry('seeds', ['chia seeds', 'flax seeds', 'sunflower seeds', 'pumpkin seeds', 'sesame seeds'], 'A', true),
  entry('fruit', ['apple', 'apples', 'banana', 'bananas', 'berries', 'strawberries', 'blueberries', 'raisins', 'dates', 'peaches', 'pears', 'mango'], 'A', true),
  entry('vegetables', ['tomatoes', 'tomato', 'carrots', 'carrot', 'spinach', 'broccoli', 'cauliflower', 'potatoes', 'potato', 'sweet potatoes'], 'A', true),
  entry('eggs', ['egg', 'whole eggs'], 'A', true),
  entry('fish', ['salmon', 'tuna', 'sardines', 'cod'], 'A', true),
  entry('seafood', ['shrimp', 'crab', 'lobster'], 'A', true),
  entry('chicken', ['chicken breast', 'chicken meat'], 'A', true),
  entry('turkey', ['turkey breast', 'turkey meat'], 'A', true),
  entry('beef', ['beef meat'], 'A', true),
  entry('pork', ['pork meat'], 'A', true),
  entry('milk', ['whole milk', 'skim milk', 'nonfat milk', 'lowfat milk'], 'A', true),
  entry('plain yogurt', ['yogurt', 'greek yogurt', 'nonfat greek yogurt'], 'B', true),
  entry('tofu', ['firm tofu', 'silken tofu'], 'B', true),
  entry('nut butter', ['peanut butter', 'almond butter', 'cashew butter'], 'B', true),
  entry('cheese', ['cheddar cheese', 'mozzarella cheese', 'swiss cheese', 'parmesan cheese'], 'B', true),
  entry('fruit puree', ['apple puree', 'banana puree', 'strawberry puree'], 'B', true),
  entry('vegetable puree', ['tomato puree', 'carrot puree'], 'B', true),
  entry('olive oil', ['extra virgin olive oil'], 'C', false),
  entry('canola oil', ['rapeseed oil'], 'C', false),
  entry('avocado oil', [], 'C', false),
  entry('sunflower oil', [], 'C', false),
  entry('safflower oil', [], 'C', false),
  entry('soybean oil', [], 'C', false),
  entry('cocoa', ['cocoa powder', 'chocolate liquor'], 'C', false),
  entry('refined wheat flour', ['wheat flour', 'enriched wheat flour', 'white flour', 'enriched flour'], 'D', false),
  entry('refined corn flour', ['corn flour', 'cornmeal'], 'D', false),
  entry('refined rice flour', ['white rice flour', 'rice flour'], 'D', false),
  entry('corn starch', ['cornstarch', 'modified corn starch', 'modified food starch'], 'D', false),
  entry('maltodextrin', [], 'D', false),
  entry('protein isolate', ['soy protein isolate', 'pea protein isolate', 'whey protein isolate', 'milk protein isolate'], 'D', false),
  entry('protein concentrate', ['whey protein concentrate', 'pea protein concentrate', 'soy protein concentrate'], 'D', false),
  entry('sugar', ['cane sugar', 'brown sugar', 'raw sugar', 'invert sugar', 'sucrose'], 'E', false),
  entry('corn syrup', ['high fructose corn syrup', 'glucose syrup', 'rice syrup', 'brown rice syrup'], 'E', false),
  entry('dextrose', ['glucose', 'fructose'], 'E', false),
  entry('honey', ['agave nectar', 'maple syrup'], 'E', false),
  entry('salt', ['sea salt'], 'E', false),
  entry('natural flavor', ['natural flavors'], 'E', false),
  entry('artificial flavor', ['artificial flavors'], 'E', false),
  entry('color', ['artificial color', 'colors', 'color added'], 'E', false),
]

const aliasIndex = new Map(ingredientTaxonomy.flatMap((item) => item.aliases.map((alias) => [alias, item] as const)))

export function classifyTopLevelIngredients(
  ingredients: ParsedIngredient[],
  frozen: FrozenIngredientClassification[] = [],
) {
  const frozenIndex = new Map(frozen.map((item) => [canonicalizeIngredient(item.canonical_name), item]))
  const classified: ClassifiedIngredient[] = []
  const unresolved: ParsedIngredient[] = []
  for (const ingredient of ingredients) {
    const curated = aliasIndex.get(ingredient.canonical_name)
    const stored = frozenIndex.get(ingredient.canonical_name)
    if (curated) {
      classified.push(build(ingredient, curated.quality_class, curated.beneficial, 1, 'curated'))
    } else if (recognizedAdditive(ingredient.canonical_name)) {
      classified.push(build(ingredient, 'E', false, 1, 'curated'))
    } else if (stored && stored.confidence >= 0.90) {
      classified.push(build(ingredient, stored.quality_class, stored.beneficial, stored.confidence, stored.source))
    } else {
      unresolved.push(ingredient)
    }
  }
  return { classified, unresolved }
}

function build(
  ingredient: ParsedIngredient,
  qualityClass: TaxonomyClass,
  beneficial: boolean,
  confidence: number,
  source: ClassifiedIngredient['classification_source'],
): ClassifiedIngredient {
  return {
    ...ingredient,
    quality_class: qualityClass,
    quality_coefficient: PFQS_QUALITY_COEFFICIENTS[qualityClass],
    beneficial,
    confidence,
    classification_source: source,
  }
}
