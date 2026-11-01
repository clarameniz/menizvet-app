import { router } from 'expo-router';

import {
  PETS_LIST_HREF,
  petDetailHref,
  returnToPetDetail,
  returnToPetsList,
} from '@/lib/pets-navigation';

jest.mock('expo-router', () => ({
  router: {
    dismissTo: jest.fn(),
    replace: jest.fn(),
    push: jest.fn(),
    back: jest.fn(),
  },
}));

const mockedRouter = router as jest.Mocked<typeof router>;

describe('pets navigation', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('builds the Pet detail href for a Pet id', () => {
    expect(petDetailHref('5b1f2c3d-0000-4000-8000-000000000001')).toBe(
      '/pets/5b1f2c3d-0000-4000-8000-000000000001',
    );
  });

  it('returns from Pet detail to My Pets with dismissTo, never replace/push (no duplicate list)', () => {
    returnToPetsList();

    expect(mockedRouter.dismissTo).toHaveBeenCalledWith(PETS_LIST_HREF);
    expect(PETS_LIST_HREF).toBe('/pets');
    expect(mockedRouter.replace).not.toHaveBeenCalled();
    expect(mockedRouter.push).not.toHaveBeenCalled();
  });

  it('returns from Edit Pet to that Pet detail with dismissTo, never replace/push (no duplicate detail)', () => {
    returnToPetDetail('pet-1');

    expect(mockedRouter.dismissTo).toHaveBeenCalledWith('/pets/pet-1');
    expect(mockedRouter.replace).not.toHaveBeenCalled();
    expect(mockedRouter.push).not.toHaveBeenCalled();
  });
});
