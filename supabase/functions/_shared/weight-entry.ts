export type IdentifiedWeightEntry = { id: string }

export function canonicalUUID(value: string | null | undefined): string | null {
  return value?.trim().toLowerCase() || null
}

export function findWeightEntryIndex<T extends IdentifiedWeightEntry>(
  entries: T[],
  requestedID: string | null | undefined,
): number {
  const canonicalRequestedID = canonicalUUID(requestedID)
  if (!canonicalRequestedID) return -1
  return entries.findIndex((entry) => canonicalUUID(entry.id) === canonicalRequestedID)
}
