import type { ParsedIngredient } from './types.ts'

export function canonicalizeIngredient(value: string) {
  return value
    .normalize('NFKC')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[®™]/g, '')
    .replace(/^contains\s+(?:two|2)\s*%\s+or\s+less\s+(?:of\s*)?:?/i, '')
    .replace(/^less\s+than\s+(?:two|2)\s*%\s+(?:of\s*)?:?/i, '')
    .replace(/\s+/g, ' ')
    .replace(/^[\s:;,.-]+|[\s:;,.-]+$/g, '')
    .trim()
}

export function parseIngredients(raw: string): ParsedIngredient[] {
  return splitTopLevel(raw).flatMap((segment, index) => {
    const parsed = parseSegment(segment, index + 1, null)
    return parsed.name ? [parsed] : []
  })
}

export function flattenIngredients(items: ParsedIngredient[]): ParsedIngredient[] {
  return items.flatMap((item) => [item, ...flattenIngredients(item.subingredients)])
}

function parseSegment(rawSegment: string, position: number, parent: string | null): ParsedIngredient {
  const raw = rawSegment.trim()
  const percentage = parsePercentage(raw)
  const open = firstOpeningBracket(raw)
  let nameText = raw
  let childText = ''
  if (open >= 0) {
    const close = matchingClose(raw, open)
    if (close > open) {
      nameText = `${raw.slice(0, open)} ${raw.slice(close + 1)}`
      childText = raw.slice(open + 1, close)
    }
  }
  nameText = nameText
    .replace(/^\s*\d+(?:\.\d+)?\s*%\s*/i, '')
    .replace(/\s*\d+(?:\.\d+)?\s*%\s*$/i, '')
  const canonical = canonicalizeIngredient(nameText)
  const children = childText
    ? splitTopLevel(childText).map((item, index) => parseSegment(item, index + 1, canonical))
    : []
  return { raw, name: nameText.trim(), canonical_name: canonical, position, percentage, parent, subingredients: children }
}

function splitTopLevel(value: string) {
  const parts: string[] = []
  let depth = 0
  let start = 0
  for (let index = 0; index < value.length; index += 1) {
    const character = value[index]
    if (character === '(' || character === '[' || character === '{') depth += 1
    if (character === ')' || character === ']' || character === '}') depth = Math.max(0, depth - 1)
    if ((character === ',' || character === ';') && depth === 0) {
      const part = value.slice(start, index).trim()
      if (part) parts.push(part)
      start = index + 1
    }
  }
  const final = value.slice(start).trim()
  if (final) parts.push(final)
  return parts
}

function parsePercentage(value: string) {
  const leading = value.match(/^\s*(\d+(?:\.\d+)?)\s*%/)
  const trailing = value.match(/(\d+(?:\.\d+)?)\s*%\s*$/)
  const parsed = Number(leading?.[1] ?? trailing?.[1])
  return Number.isFinite(parsed) ? parsed : null
}

function firstOpeningBracket(value: string) {
  const indexes = ['(', '[', '{'].map((item) => value.indexOf(item)).filter((index) => index >= 0)
  return indexes.length ? Math.min(...indexes) : -1
}

function matchingClose(value: string, openingIndex: number) {
  const opening = value[openingIndex]
  const closing = opening === '(' ? ')' : opening === '[' ? ']' : '}'
  let depth = 0
  for (let index = openingIndex; index < value.length; index += 1) {
    if (value[index] === opening) depth += 1
    if (value[index] === closing) {
      depth -= 1
      if (depth === 0) return index
    }
  }
  return -1
}
