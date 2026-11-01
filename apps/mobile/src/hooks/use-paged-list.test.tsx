import { createElement } from 'react';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';

import { usePagedList, type PagedList, type PageResult } from '@/hooks/use-paged-list';

// usePagedList's focus behaviour and a page's own `hasMore`, through the real
// hook. Focus is simulated by re-running the registered focus callbacks, as
// expo-router does on return from a detail.
let mockFocusCallbacks: (() => void)[] = [];
jest.mock('expo-router', () => {
  const { useEffect } = jest.requireActual<typeof import('react')>('react');
  return {
    useFocusEffect: (callback: () => void) => {
      useEffect(() => {
        mockFocusCallbacks.push(callback);
        callback();
        return () => {
          mockFocusCallbacks = mockFocusCallbacks.filter((registered) => registered !== callback);
        };
      }, [callback]);
    },
  };
});

type Row = { id: string };
const PAGE_SIZE = 2;
const rows = (...ids: string[]): Row[] => ids.map((id) => ({ id }));

let latest: PagedList<Row, never>;
let tree: ReactTestRenderer;
function remember(list: PagedList<Row, never>) {
  latest = list;
}

// Stable, as in every real list hook: a new `cursorOf` would be a new read.
const idOf = (row: Row) => row.id;
const cursorOf = (row: Row) => row.id;
const isAccessDenied = () => false;
const errorKeyOf = () => 'pagedList.refreshError' as const;
const onAccessLost = () => {};

function Harness({
  readPage,
  refreshOnFocus,
  onRender = remember,
}: {
  readPage: (cursor: string | null) => Promise<PageResult<Row, never>>;
  refreshOnFocus?: boolean;
  onRender?: (list: PagedList<Row, never>) => void;
}) {
  const list = usePagedList<Row, string, never>({
    active: true,
    pageSize: PAGE_SIZE,
    refreshOnFocus,
    readPage,
    idOf,
    cursorOf,
    isAccessDenied,
    errorKeyOf,
    onAccessLost,
  });
  onRender(list);
  return null;
}

/** A keyset backend over a-b-c-d-e: the page after the cursor's row. */
const server = ['a', 'b', 'c', 'd', 'e'];
function keysetRead(hasMoreOf?: (page: string[]) => boolean) {
  return jest.fn(async (cursor: string | null): Promise<PageResult<Row, never>> => {
    const start = cursor === null ? 0 : server.indexOf(cursor) + 1;
    const page = server.slice(start, start + PAGE_SIZE);
    return {
      data: { rows: rows(...page), meta: null, ...(hasMoreOf ? { hasMore: hasMoreOf(page) } : {}) },
      error: null,
    };
  });
}

async function mount(element: ReturnType<typeof createElement>) {
  await act(async () => {
    tree = create(element);
  });
}
async function focusAgain() {
  await act(async () => {
    for (const callback of [...mockFocusCallbacks]) callback();
  });
}
const shownIds = () => (latest.state.rows ?? []).map((row) => row.id);

beforeEach(() => {
  mockFocusCallbacks = [];
});
afterEach(() => act(() => tree.unmount()));

it('by default a focus restarts the list from its first page', async () => {
  const read = keysetRead();
  await mount(createElement(Harness, { readPage: read }));
  await act(async () => latest.loadMore());
  expect(shownIds()).toEqual(['a', 'b', 'c', 'd']);

  await focusAgain();
  expect(read).toHaveBeenCalledTimes(3);
  expect(read).toHaveBeenLastCalledWith(null);
  expect(shownIds()).toEqual(['a', 'b']);
});

it('refreshOnFocus false: the first entry reads the first page once', async () => {
  const read = keysetRead();
  await mount(createElement(Harness, { readPage: read, refreshOnFocus: false }));
  expect(read).toHaveBeenCalledTimes(1);
  expect(read).toHaveBeenCalledWith(null);
  expect(shownIds()).toEqual(['a', 'b']);
});

it('refreshOnFocus false: a focus keeps every loaded page and the cursor', async () => {
  const read = keysetRead();
  await mount(createElement(Harness, { readPage: read, refreshOnFocus: false }));
  await act(async () => latest.loadMore());
  expect(shownIds()).toEqual(['a', 'b', 'c', 'd']);

  await focusAgain();
  await focusAgain();
  expect(read).toHaveBeenCalledTimes(2);
  expect(shownIds()).toEqual(['a', 'b', 'c', 'd']);

  // "Load more" continues from the kept cursor.
  await act(async () => latest.loadMore());
  expect(read).toHaveBeenLastCalledWith('d');
  expect(shownIds()).toEqual(['a', 'b', 'c', 'd', 'e']);
});

it('refreshOnFocus false: a new readPage still reads and withdraws the previous rows', async () => {
  const first = keysetRead();
  await mount(createElement(Harness, { readPage: first, refreshOnFocus: false }));
  expect(shownIds()).toEqual(['a', 'b']);

  let resolveSecond: (result: PageResult<Row, never>) => void = () => {};
  const second = jest.fn(
    () =>
      new Promise<PageResult<Row, never>>((resolve) => {
        resolveSecond = resolve;
      }),
  );
  await act(async () =>
    tree.update(createElement(Harness, { readPage: second, refreshOnFocus: false })),
  );
  expect(second).toHaveBeenCalledTimes(1);
  expect(latest.state.rows).toBeNull();
  expect(latest.state.loading).toBe('first');

  await act(async () => resolveSecond({ data: { rows: rows('x'), meta: null }, error: null }));
  expect(shownIds()).toEqual(['x']);
});

it('a page that reports hasMore overrides the full-page rule', async () => {
  // Full last page: the read says nothing follows.
  const exact = keysetRead((page) => page.at(-1) !== 'b');
  await mount(createElement(Harness, { readPage: exact }));
  expect(shownIds()).toEqual(['a', 'b']);
  expect(latest.state.hasMore).toBe(false);
  act(() => tree.unmount());

  // Short page: the read says more follows.
  const short = jest.fn(async (): Promise<PageResult<Row, never>> => ({
    data: { rows: rows('a'), meta: null, hasMore: true },
    error: null,
  }));
  await mount(createElement(Harness, { readPage: short }));
  expect(latest.state.hasMore).toBe(true);
});

it('without hasMore a full page still means more may exist', async () => {
  const read = keysetRead();
  await mount(createElement(Harness, { readPage: read }));
  expect(latest.state.hasMore).toBe(true);
  await act(async () => latest.loadMore());
  await act(async () => latest.loadMore());
  expect(shownIds()).toEqual(['a', 'b', 'c', 'd', 'e']);
  expect(latest.state.hasMore).toBe(false);
});
