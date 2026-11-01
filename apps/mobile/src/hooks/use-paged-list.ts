import { useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';

import type { TranslationKey } from '@/i18n/i18n';

/**
 * What one keyset-paged list shows. The last good `rows` survive a failed
 * refresh or a failed "load more", so an error never erases what is shown;
 * `rows === null` means never loaded.
 */
export type PagedListState<TRow, TMeta> = {
  rows: TRow[] | null;
  /** Per-reading values carried by the pages (e.g. Pending's totals); `null` when none. */
  meta: TMeta | null;
  /** The last page was full, so more may exist. */
  hasMore: boolean;
  /** The read in flight: the first page (first load or refresh) or the next one. */
  loading: 'first' | 'more' | null;
  error: { during: 'first' | 'more'; messageKey: TranslationKey } | null;
};

/**
 * One page as a data read returns it; `meta` is `null` when the page carries
 * none. `hasMore`, when the read reports it, replaces the "full page means
 * more may exist" rule.
 */
export type Page<TRow, TMeta> = { rows: TRow[]; meta: TMeta | null; hasMore?: boolean };

/** The `{data, error}` shape every data read settles into. */
export type PageResult<TRow, TMeta> =
  { data: Page<TRow, TMeta>; error: null } | { data: null; error: string };

/** What a paged list hands to its view: its state and its commands. */
export type PagedList<TRow, TMeta> = {
  state: PagedListState<TRow, TMeta>;
  loadMore: () => void;
  retry: () => void;
  /** Restarts from the first page now, e.g. after a write on this list; resolves when it settles. */
  reload: () => Promise<void>;
};

export type PagedListConfig<TRow, TCursor, TMeta> = {
  active: boolean;
  pageSize: number;
  /**
   * Whether every screen focus restarts the active list from its first page
   * (the default, for lists whose rows change through writes elsewhere).
   * `false` keeps what is shown when the screen is focused again; the first
   * read and a new `readPage` still read.
   */
  refreshOnFocus?: boolean;
  /**
   * Stable for the list's owner (e.g. per Clinic, or per search); `null` reads
   * the first page. A new `readPage` is a new list: what was shown is dropped.
   */
  readPage: (cursor: TCursor | null) => Promise<PageResult<TRow, TMeta>>;
  idOf: (row: TRow) => string;
  cursorOf: (row: TRow) => TCursor;
  /** Whether a read's error means access to the whole screen was lost (its 42501). */
  isAccessDenied: (error: string) => boolean;
  errorKeyOf: (error: string) => TranslationKey;
  onAccessLost: () => void;
};

const INITIAL_STATE = {
  rows: null,
  meta: null,
  hasMore: false,
  loading: null,
  error: null,
} as const;

/**
 * One keyset-paged list, read only while its tab is `active`:
 *
 * - nothing is read until the list is first shown;
 * - on every screen focus (e.g. back from a detail, where writes happen) the
 *   active list restarts from its first page; an inactive one is only marked
 *   stale and restarts when shown again. With `refreshOnFocus: false` a focus
 *   keeps the rows, cursor and position already shown for the same
 *   `readPage`;
 * - a restart drops the previous cursor and starts a new generation, so any
 *   answer of an older generation — including a "load more" still in flight —
 *   is ignored;
 * - a restart for a new `readPage` (another owner or search) also withdraws
 *   the rows at once: the list shows its first-page loading state, never the
 *   previous owner's rows; a restart for the same `readPage` keeps them;
 * - "load more" continues from the complete key of the last row the backend
 *   returned, at most one read at a time, and never appends a row already
 *   shown;
 * - a full page means more may exist; a shorter or empty one ends the list —
 *   unless the page reports its own `hasMore`. An empty later page keeps the
 *   meta of the previous page;
 * - an access denial replaces the whole screen (`onAccessLost`); any other
 *   failure keeps what is shown and offers a retry.
 */
export function usePagedList<TRow, TCursor, TMeta>({
  active,
  pageSize,
  refreshOnFocus = true,
  readPage,
  idOf,
  cursorOf,
  isAccessDenied,
  errorKeyOf,
  onAccessLost,
}: PagedListConfig<TRow, TCursor, TMeta>): PagedList<TRow, TMeta> {
  const [state, setState] = useState<PagedListState<TRow, TMeta>>(INITIAL_STATE);

  const isMountedRef = useRef(true);
  const stateRef = useRef<PagedListState<TRow, TMeta>>(INITIAL_STATE);
  const generationRef = useRef(0);
  const cursorRef = useRef<TCursor | null>(null);
  const activeRef = useRef(active);
  const staleRef = useRef(true);
  // The `readPage` whose rows are shown.
  const ownerRef = useRef(readPage);
  // How failures are reported may change identity on any render (e.g. a new
  // `t`); only `readPage` decides what is read, so only it may restart a read.
  const reportRef = useRef({ isAccessDenied, errorKeyOf, onAccessLost });
  useEffect(() => {
    reportRef.current = { isAccessDenied, errorKeyOf, onAccessLost };
  }, [errorKeyOf, isAccessDenied, onAccessLost]);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  const update = useCallback(
    (change: (current: PagedListState<TRow, TMeta>) => PagedListState<TRow, TMeta>) => {
      stateRef.current = change(stateRef.current);
      setState(stateRef.current);
    },
    [],
  );

  const failed = useCallback(
    (error: string, during: 'first' | 'more') => {
      const report = reportRef.current;
      if (report.isAccessDenied(error)) {
        update((current) => ({ ...current, loading: null }));
        report.onAccessLost();
        return;
      }
      update((current) => ({
        ...current,
        loading: null,
        error: { during, messageKey: report.errorKeyOf(error) },
      }));
    },
    [update],
  );

  const readFirstPage = useCallback(async () => {
    staleRef.current = false;
    const generation = ++generationRef.current;
    if (ownerRef.current !== readPage) {
      ownerRef.current = readPage;
      cursorRef.current = null;
      update(() => ({ ...INITIAL_STATE, loading: 'first' }));
    } else {
      update((current) => ({ ...current, loading: 'first', error: null }));
    }

    const result = await readPage(null);
    if (!isMountedRef.current || generation !== generationRef.current) return;
    if (result.error !== null) {
      failed(result.error, 'first');
      return;
    }
    const { rows, meta } = result.data;
    cursorRef.current = rows.length > 0 ? cursorOf(rows[rows.length - 1]) : null;
    update(() => ({
      rows,
      meta,
      hasMore: result.data.hasMore ?? rows.length === pageSize,
      loading: null,
      error: null,
    }));
  }, [cursorOf, failed, pageSize, readPage, update]);

  const loadMore = useCallback(async () => {
    const current = stateRef.current;
    const cursor = cursorRef.current;
    if (current.loading !== null || !current.hasMore || current.rows === null || cursor === null) {
      return;
    }
    const generation = generationRef.current;
    update((previous) => ({ ...previous, loading: 'more', error: null }));

    const result = await readPage(cursor);
    if (!isMountedRef.current || generation !== generationRef.current) return;
    if (result.error !== null) {
      failed(result.error, 'more');
      return;
    }
    const { rows, meta } = result.data;
    if (rows.length > 0) cursorRef.current = cursorOf(rows[rows.length - 1]);
    update((previous) => {
      const shown = previous.rows ?? [];
      const known = new Set(shown.map(idOf));
      return {
        rows: [...shown, ...rows.filter((row) => !known.has(idOf(row)))],
        meta: meta ?? previous.meta,
        hasMore: result.data.hasMore ?? rows.length === pageSize,
        loading: null,
        error: null,
      };
    });
  }, [cursorOf, failed, idOf, pageSize, readPage, update]);

  const retry = useCallback(() => {
    const current = stateRef.current;
    if (current.loading !== null) return;
    if (current.error?.during === 'more') loadMore();
    else readFirstPage();
  }, [loadMore, readFirstPage]);

  // Declared before the activation effect, so a list active on mount reads once.
  useFocusEffect(
    useCallback(() => {
      // Without refresh on focus, a list already read (or being read) for
      // this `readPage` keeps what it shows; a new `readPage` still restarts.
      if (!refreshOnFocus && ownerRef.current === readPage && !staleRef.current) return;
      if (activeRef.current) readFirstPage();
      else staleRef.current = true;
    }, [readFirstPage, readPage, refreshOnFocus]),
  );

  useEffect(() => {
    activeRef.current = active;
    if (active && staleRef.current) readFirstPage();
  }, [active, readFirstPage]);

  return { state, loadMore, retry, reload: readFirstPage };
}
