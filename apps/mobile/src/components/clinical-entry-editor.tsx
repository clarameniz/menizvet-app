import { StyleSheet, Text, View } from 'react-native';

import { ClinicalCategorySelect } from '@/components/clinical-category-select';
import { Button } from '@/components/design-system/button';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import type {
  ClinicalEntryDraft,
  ClinicalEntryField,
  ClinicalNotice,
} from '@/lib/appointment-clinical-record';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/** What the editor writes: a new record, a clarifying record, or an edit of the reader's own. */
export type ClinicalEditorMode = 'new' | 'clarifying' | 'edit';

type ClinicalEntryEditorProps = {
  mode: ClinicalEditorMode;
  draft: ClinicalEntryDraft;
  onChange: (next: ClinicalEntryDraft) => void;
  issue: { field: ClinicalEntryField; messageKey: TranslationKey } | null;
  notice: ClinicalNotice | null;
  saving: boolean;
  onSave: () => void;
  onCancel: () => void;
};

const TITLE_KEYS: Record<ClinicalEditorMode, TranslationKey> = {
  new: 'clinicalRecord.editorTitle',
  clarifying: 'clinicalRecord.editorClarifyTitle',
  edit: 'clinicalRecord.editorEditTitle',
};

/**
 * The inline record editor of the Appointment detail (SPEC-MED-010 Part F),
 * inside the Clinical record card, for a new record and for editing one's
 * own. Presentation only: the draft
 * lives with its owner and is never stored on the device. A compact category
 * selector (nothing preselected for a new record), the clinical text, and the
 * OTHER context only for OTHER. No time is asked for: the server records its
 * own. A new record carries one short notice that the guardians will see it
 * and later changes are documented; there is no second confirmation and no
 * reason for an edit.
 */
export function ClinicalEntryEditor({
  mode,
  draft,
  onChange,
  issue,
  notice,
  saving,
  onSave,
  onCancel,
}: ClinicalEntryEditorProps) {
  const { t } = useLocale();
  const editable = !saving;
  const errorFor = (field: ClinicalEntryField) =>
    issue !== null && issue.field === field ? t(issue.messageKey) : undefined;

  return (
    <View style={styles.editor}>
      <Text style={styles.title} accessibilityRole="header">
        {t(TITLE_KEYS[mode])}
      </Text>
      {mode === 'clarifying' ? (
        <Text style={styles.hint}>{t('clinicalRecord.clarifyNote')}</Text>
      ) : null}

      <ClinicalCategorySelect
        value={draft.category}
        onChange={(category) => onChange({ ...draft, category })}
        error={errorFor('category')}
        disabled={!editable}
      />

      {draft.category === 'OTHER' ? (
        <Input
          label={t('clinicalRecord.otherContextLabel')}
          value={draft.otherContext}
          onChangeText={(otherContext) => onChange({ ...draft, otherContext })}
          editable={editable}
          required
          error={errorFor('otherContext')}
        />
      ) : null}

      <Input
        label={t('clinicalRecord.contentLabel')}
        value={draft.content}
        onChangeText={(content) => onChange({ ...draft, content })}
        multiline
        editable={editable}
        required
        error={errorFor('content')}
      />

      {mode !== 'edit' ? (
        <Text style={styles.hint}>{t('clinicalRecord.publishNotice')}</Text>
      ) : null}
      {notice !== null ? <Notice tone={notice.tone} message={t(notice.messageKey)} /> : null}
      <Button
        label={t(mode === 'edit' ? 'clinicalRecord.saveChanges' : 'clinicalRecord.saveRecord')}
        onPress={onSave}
        loading={saving}
        disabled={saving}
      />
      <Button
        variant="secondary"
        label={t('clinicalRecord.cancelEditor')}
        onPress={onCancel}
        disabled={saving}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  // A soft inset panel inside the Clinical record card — never a second card.
  editor: {
    gap: spacing.md,
    padding: spacing.md,
    borderRadius: radius.small,
    backgroundColor: colors.surfaceSoft,
  },
  title: { ...typography.bodyStrong, color: colors.textPrimary },
  hint: { ...typography.caption, color: colors.textSecondary },
});
