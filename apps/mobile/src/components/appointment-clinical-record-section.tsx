import { useNavigation } from 'expo-router';
import { usePreventRemove } from 'expo-router/react-navigation';
import { uuid } from 'expo-modules-core';
import { Fragment, useEffect, useRef, useState, type ReactNode } from 'react';
import { AccessibilityInfo, Alert, StyleSheet, Text, View } from 'react-native';

import { ClinicalEntryEditor, type ClinicalEditorMode } from '@/components/clinical-entry-editor';
import { ClinicalRecordEntryRow } from '@/components/clinical-record-entry-row';
import { Button } from '@/components/design-system/button';
import { CompactAction } from '@/components/design-system/compact-action';
import { Notice } from '@/components/design-system/notice';
import {
  createAppointmentClinicalEntry,
  editAppointmentClinicalEntry,
  viewAppointmentClinicalRecord,
  type AppointmentClinicalEntry,
  type AppointmentClinicalRecord,
  type AppointmentClinicalRecordRead,
  type ClinicalEntryFields,
} from '@/data/appointment-clinical-record';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import {
  canClarifyEntry,
  canEditEntry,
  documentationUnavailableKey,
  draftFromEntry,
  editSaveOutcome,
  EMPTY_CLINICAL_ENTRY_DRAFT,
  entryFieldsFromDraft,
  entrySaveOutcome,
  findSubmittedEntry,
  isAssignmentRejection,
  isEntryDraftDirty,
  isSubmittedEditCurrent,
  type ClinicalEntryDraft,
  type ClinicalEntryField,
  type ClinicalNotice,
} from '@/lib/appointment-clinical-record';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type RecordState =
  | { kind: 'loading' }
  | { kind: 'error'; messageKey: TranslationKey }
  /** Denied: nothing clinical is kept on screen except the reader's own unsaved text. */
  | { kind: 'unavailable' }
  | { kind: 'loaded'; record: AppointmentClinicalRecord };

/** What the open editor writes. */
type EditorTarget =
  | {
      kind: 'new';
      clarifying: boolean;
      /** The Entries already recorded when the editor opened (lost-response reconciliation). */
      knownEntryIds: ReadonlySet<string>;
    }
  | {
      kind: 'edit';
      entryId: string;
      /** The version the editor was opened on (BR-23b). */
      openedVersion: number;
      /** That version, as a draft: leaving asks first only when something differs. */
      initial: ClinicalEntryDraft;
    };

/** One write intent: its draft and the idempotency key every retry reuses. */
type EditorState = { draft: ClinicalEntryDraft; key: string; target: EditorTarget };

/** A read's effect on what is shown: a failed refresh keeps the record already shown. */
function nextRecordState(current: RecordState, result: AppointmentClinicalRecordRead): RecordState {
  if (result.kind === 'permitted') return { kind: 'loaded', record: result.record };
  if (result.kind === 'denied') return { kind: 'unavailable' };
  if (current.kind === 'loaded') return current;
  return {
    kind: 'error',
    messageKey:
      result.kind === 'authenticationRequired'
        ? 'errors.sessionExpired'
        : 'clinicalRecord.loadError',
  };
}

function editorMode(target: EditorTarget): ClinicalEditorMode {
  if (target.kind === 'edit') return 'edit';
  return target.clarifying ? 'clarifying' : 'new';
}

/** Opens an edit of `entry` on its current version, with a fresh key. */
function editorForEntry(entry: AppointmentClinicalEntry, draft?: ClinicalEntryDraft): EditorState {
  const initial = draftFromEntry(entry);
  return {
    draft: draft ?? initial,
    key: uuid.v4(),
    target: { kind: 'edit', entryId: entry.entryId, openedVersion: entry.version, initial },
  };
}

/**
 * The Clinical record section of the professional Appointment detail
 * (SPEC-MED-010 Part F), shown by the detail only to actors holding
 * CLINICAL_DOCUMENTATION. Its read is the audited `view_appointment_clinical_record`
 * (BR-20/BR-21), keyed by Clinic and Appointment and repeated whenever
 * `refreshKey` changes; the latest read wins and a failed refresh keeps what
 * is shown.
 *
 * One card: "Clinical record" with a compact "Add" (only when the server says
 * the reader can record; otherwise one calm line says why), then the visit's
 * records oldest first, each a row in its current version between discreet
 * dividers, and the detail's `footer` (the prior-history row) last. Opening
 * an editor calls nothing; it opens inside the card. "Save
 * record" and "Save changes" send one request per tap with the editor's key —
 * a retry after a lost response reuses it, so nothing is duplicated — and
 * re-read after any outcome. On failure the typed text stays on screen; it is
 * never stored on the device or logged. Leaving with unsaved changes asks
 * first.
 *
 * The pencil, on the reader's own record, opens the same editor beneath it, filled
 * with its current version; if the record changed meanwhile the save is
 * refused, the text stays, the newer version shows above, and the next save
 * applies on top of it. "Add a clarifying record" opens the new-record editor
 * with its note, on another Veterinarian's record, when the reader can record.
 */
export function AppointmentClinicalRecordSection({
  clinicId,
  appointmentId,
  timeZone,
  refreshKey,
  onRecorded,
  onAssignmentStale,
  onEditorOpenChange,
  footer,
  disabled = false,
}: {
  clinicId: string;
  appointmentId: string;
  /** The Appointment's scheduling timezone, in which every time is shown. */
  timeZone: string;
  refreshKey: number;
  /** A record was saved: the detail re-reads the Appointment (its actions depend on records). */
  onRecorded: () => void;
  /** A save was refused because the assignment changed: the detail re-reads it. */
  onAssignmentStale: () => void;
  /** An editor opened or closed: the detail hides "Complete" while one is open. */
  onEditorOpenChange: (open: boolean) => void;
  /** The last row of the card, below a divider; it performs no read of its own here. */
  footer?: ReactNode;
  disabled?: boolean;
}) {
  const { t } = useLocale();
  const navigation = useNavigation();
  const [state, setState] = useState<RecordState>({ kind: 'loading' });
  const [editor, setEditor] = useState<EditorState | null>(null);
  const [issue, setIssue] = useState<{
    field: ClinicalEntryField;
    messageKey: TranslationKey;
  } | null>(null);
  const [editorNotice, setEditorNotice] = useState<ClinicalNotice | null>(null);
  const [notice, setNotice] = useState<ClinicalNotice | null>(null);
  const [saving, setSaving] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const savingRef = useRef(false);
  const isMountedRef = useRef(true);
  const readSeqRef = useRef(0);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  // Latest read wins; each one is numbered when it starts.
  async function read(): Promise<AppointmentClinicalRecord | null> {
    const seq = ++readSeqRef.current;
    const result = await viewAppointmentClinicalRecord(clinicId, appointmentId);
    if (!isMountedRef.current || seq !== readSeqRef.current) return null;
    setState((current) => nextRecordState(current, result));
    return result.kind === 'permitted' ? result.record : null;
  }

  // Re-read on every refresh the detail asks for, and on Retry.
  useEffect(() => {
    const seq = ++readSeqRef.current;
    viewAppointmentClinicalRecord(clinicId, appointmentId).then((result) => {
      if (isMountedRef.current && seq === readSeqRef.current)
        setState((current) => nextRecordState(current, result));
    });
  }, [clinicId, appointmentId, refreshKey, attempt]);

  const dirty =
    editor !== null &&
    isEntryDraftDirty(
      editor.draft,
      editor.target.kind === 'edit' ? editor.target.initial : EMPTY_CLINICAL_ENTRY_DRAFT,
    );

  function updateEditor(next: EditorState | null) {
    setEditor(next);
    onEditorOpenChange(next !== null);
  }

  function confirmDiscard(discard: () => void) {
    Alert.alert(
      t('clinicalRecord.discardTitle'),
      t('clinicalRecord.discardMessage'),
      [
        { text: t('clinicalRecord.discardKeep'), style: 'cancel' },
        { text: t('clinicalRecord.discardConfirm'), style: 'destructive', onPress: discard },
      ],
      { cancelable: true },
    );
  }

  // Back, a gesture, or any navigation away with unsaved changes asks first.
  usePreventRemove(dirty, ({ data }) => {
    confirmDiscard(() => navigation.dispatch(data.action));
  });

  function open(next: EditorState) {
    if (savingRef.current || editor !== null) return;
    setNotice(null);
    setIssue(null);
    setEditorNotice(null);
    updateEditor(next);
  }

  function openNew(clarifying: boolean) {
    const known = state.kind === 'loaded' ? state.record.entries.map((entry) => entry.entryId) : [];
    // One record intent per opening: its key is reused by every retry.
    open({
      draft: EMPTY_CLINICAL_ENTRY_DRAFT,
      key: uuid.v4(),
      target: { kind: 'new', clarifying, knownEntryIds: new Set(known) },
    });
  }

  function closeEditor() {
    if (savingRef.current) return;
    if (dirty) confirmDiscard(() => updateEditor(null));
    else updateEditor(null);
  }

  function change(draft: ClinicalEntryDraft) {
    if (savingRef.current || editor === null) return;
    setEditor({ ...editor, draft });
    setIssue(null);
  }

  function saved(message: ClinicalNotice) {
    updateEditor(null);
    setNotice(message);
    AccessibilityInfo.announceForAccessibility(t(message.messageKey));
  }

  async function saveNew(
    current: EditorState,
    fields: ClinicalEntryFields,
    knownIds: ReadonlySet<string>,
  ) {
    const result = await createAppointmentClinicalEntry(
      clinicId,
      appointmentId,
      current.key,
      fields,
    );
    if (!isMountedRef.current) return;
    // The authoritative re-read, after any outcome.
    const after = await read();
    if (!isMountedRef.current) return;
    const outcome = entrySaveOutcome(result, findSubmittedEntry(after, fields, knownIds));
    if (outcome.kind === 'saved') {
      saved({ tone: 'info', messageKey: 'clinicalRecord.saved' });
      onRecorded();
      return;
    }
    // The text stays; a retry reuses the same key.
    setEditorNotice(outcome.notice);
    if (isAssignmentRejection(result)) onAssignmentStale();
  }

  async function saveEdit(
    current: EditorState,
    fields: ClinicalEntryFields,
    entryId: string,
    openedVersion: number,
  ) {
    const result = await editAppointmentClinicalEntry(
      clinicId,
      appointmentId,
      entryId,
      current.key,
      openedVersion,
      fields,
    );
    if (!isMountedRef.current) return;
    const after = await read();
    if (!isMountedRef.current) return;
    const outcome = editSaveOutcome(
      result,
      result.kind === 'uncertain' && isSubmittedEditCurrent(after, entryId, openedVersion, fields),
    );
    if (outcome.kind === 'saved') {
      saved(outcome.notice);
      return;
    }
    if (outcome.kind === 'stale') {
      // The newer version is shown above; the text stays, and the next save
      // applies on top of that version, with a new key.
      const latest = after?.entries.find((entry) => entry.entryId === entryId);
      if (latest !== undefined) setEditor(editorForEntry(latest, current.draft));
      setEditorNotice({ tone: 'error', messageKey: 'clinicalRecord.staleVersion' });
      return;
    }
    // The text stays; a retry reuses the same key.
    setEditorNotice(outcome.notice);
  }

  async function save() {
    if (savingRef.current || editor === null) return;
    const prepared = entryFieldsFromDraft(editor.draft);
    if (prepared.kind === 'issue') {
      setIssue({ field: prepared.field, messageKey: prepared.messageKey });
      return;
    }
    const current = editor;
    savingRef.current = true;
    setSaving(true);
    setEditorNotice(null);
    try {
      if (current.target.kind === 'new')
        await saveNew(current, prepared.fields, current.target.knownEntryIds);
      else
        await saveEdit(
          current,
          prepared.fields,
          current.target.entryId,
          current.target.openedVersion,
        );
    } finally {
      savingRef.current = false;
      if (isMountedRef.current) setSaving(false);
    }
  }

  const record = state.kind === 'loaded' ? state.record : null;
  const unavailableKey = record === null ? null : documentationUnavailableKey(record);
  const inactive = disabled || saving;
  const editingId = editor?.target.kind === 'edit' ? editor.target.entryId : null;
  const editorView =
    editor !== null ? (
      <ClinicalEntryEditor
        mode={editorMode(editor.target)}
        draft={editor.draft}
        onChange={change}
        issue={issue}
        notice={editorNotice}
        saving={saving}
        onSave={() => void save()}
        onCancel={closeEditor}
      />
    ) : null;

  return (
    <View style={styles.card}>
      <View style={styles.header}>
        <Text style={styles.title} accessibilityRole="header">
          {t('clinicalRecord.sectionTitle')}
        </Text>
        {record !== null && editor === null && unavailableKey === null ? (
          <CompactAction
            icon="add-circle-outline"
            label={t('clinicalRecord.add')}
            accessibilityLabel={t('clinicalRecord.addRecord')}
            onPress={() => openNew(false)}
            disabled={inactive}
          />
        ) : null}
      </View>

      {/* Why "Add" is missing, where it would be. */}
      {record !== null && editor === null && unavailableKey !== null ? (
        <Text style={[styles.meta, styles.block]}>{t(unavailableKey)}</Text>
      ) : null}

      {notice !== null ? (
        <View style={styles.block}>
          <Notice tone={notice.tone} message={t(notice.messageKey)} />
        </View>
      ) : null}

      {state.kind === 'loading' ? (
        <Text style={[styles.meta, styles.block]}>{t('clinicalRecord.loading')}</Text>
      ) : state.kind === 'error' ? (
        <View style={[styles.inline, styles.block]}>
          <Text style={styles.meta}>{t(state.messageKey)}</Text>
          <Button
            variant="tertiary"
            label={t('clinicalRecord.retry')}
            onPress={() => setAttempt((value) => value + 1)}
            disabled={inactive}
          />
        </View>
      ) : state.kind === 'unavailable' ? (
        <Text style={[styles.meta, styles.block]}>{t('clinicalRecord.unavailable')}</Text>
      ) : null}

      {record !== null ? (
        <>
          {record.entries.length === 0 && editor === null ? (
            <Text style={[styles.empty, styles.block]}>{t('clinicalRecord.noEntries')}</Text>
          ) : null}
          {record.entries.map((entry) => (
            <Fragment key={entry.entryId}>
              <View style={styles.divider} />
              <ClinicalRecordEntryRow
                entry={entry}
                timeZone={timeZone}
                onEdit={
                  canEditEntry(entry) && editor === null
                    ? () => open(editorForEntry(entry))
                    : undefined
                }
                onClarify={
                  canClarifyEntry(entry, record) && editor === null
                    ? () => openNew(true)
                    : undefined
                }
                disabled={inactive}
              />
              {/* The edit sits beneath the record it changes. */}
              {editingId === entry.entryId ? <View style={styles.block}>{editorView}</View> : null}
            </Fragment>
          ))}
          {record.entriesTruncated ? (
            <Text style={[styles.meta, styles.block]}>{t('clinicalRecord.entriesTruncated')}</Text>
          ) : null}
        </>
      ) : null}

      {/* Shown whatever the latest read said: unsaved text never disappears. */}
      {editor !== null &&
      (editingId === null ||
        record === null ||
        !record.entries.some((entry) => entry.entryId === editingId)) ? (
        <>
          <View style={styles.divider} />
          <View style={styles.newEditor}>{editorView}</View>
        </>
      ) : null}

      {footer !== undefined ? (
        <>
          <View style={styles.divider} />
          {footer}
        </>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  // One card for the visit's documentation, as the Staff lists: rows between
  // discreet dividers, never a card per record.
  card: {
    paddingHorizontal: spacing.lg,
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  // Title left, "Add" flush right despite its touch padding; on a narrow
  // screen "Add" wraps below instead of squeezing the title.
  header: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    justifyContent: 'space-between',
    columnGap: spacing.sm,
    minHeight: 44,
    paddingTop: spacing.xs,
    marginRight: -spacing.sm,
  },
  title: { ...typography.bodyStrong, color: colors.textPrimary, flexShrink: 1 },
  block: { paddingBottom: spacing.md },
  newEditor: { paddingVertical: spacing.md },
  divider: { height: StyleSheet.hairlineWidth, backgroundColor: colors.border },
  inline: { gap: spacing.xs },
  empty: { ...typography.body, color: colors.textSecondary },
  meta: { ...typography.caption, color: colors.textSecondary },
});
