import { petSummary } from '@/lib/pet-summary';

describe('petSummary', () => {
  it('joins species and breed when a breed is recorded', () => {
    expect(petSummary({ species: 'Perro', breed: 'Beagle' })).toBe('Perro · Beagle');
  });

  it('shows only the species when breed is null', () => {
    expect(petSummary({ species: 'Gato', breed: null })).toBe('Gato');
  });

  it('treats an empty-string breed as not recorded', () => {
    expect(petSummary({ species: 'Gato', breed: '' })).toBe('Gato');
  });
});
