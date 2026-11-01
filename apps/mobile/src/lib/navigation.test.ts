import { router } from 'expo-router';

import { goBackOr } from '@/lib/navigation';

jest.mock('expo-router', () => ({
  router: {
    canGoBack: jest.fn(),
    back: jest.fn(),
    replace: jest.fn(),
  },
}));

const mockedRouter = router as jest.Mocked<typeof router>;

describe('goBackOr', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('pops back when there is a screen beneath, without replacing', () => {
    mockedRouter.canGoBack.mockReturnValue(true);

    goBackOr('/pets');

    expect(mockedRouter.back).toHaveBeenCalledTimes(1);
    expect(mockedRouter.replace).not.toHaveBeenCalled();
  });

  it('replaces with the fallback when there is nothing to pop', () => {
    mockedRouter.canGoBack.mockReturnValue(false);

    goBackOr('/pets');

    expect(mockedRouter.replace).toHaveBeenCalledWith('/pets');
    expect(mockedRouter.back).not.toHaveBeenCalled();
  });
});
