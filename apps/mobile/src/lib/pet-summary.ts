import type { Pet } from '@/data/pets';

/**
 * "Species · Breed", or just the species when no breed is recorded — the
 * one-line Pet summary used by the My Pets card and the Pet detail header.
 * Both values are shown exactly as stored (free text; no mapping).
 */
export function petSummary(pet: Pick<Pet, 'species' | 'breed'>): string {
  return pet.breed ? `${pet.species} · ${pet.breed}` : pet.species;
}
