export type LocaleCode = 'es' | 'en';
export type LocalePreference = 'system' | LocaleCode;

/**
 * Shape a translation catalog must follow: a set of namespaces, each a flat
 * set of string leaves. Exactly two levels — this is not a general-purpose
 * arbitrary-depth i18n engine, it matches how es.ts/en.ts are actually
 * organized. A fully recursive version of this and DotPaths below was tried
 * first and hit TypeScript's "excessively deep" instantiation limit for no
 * benefit this catalog needs; revisit only if a screen genuinely needs a
 * third nesting level.
 */
export type TranslationTree = { [namespace: string]: { [key: string]: string } };

/**
 * Same namespace/key structure as T, but every leaf widened to plain
 * `string` instead of the literal text of the canonical (Spanish) catalog —
 * so a translated catalog can supply different text at every leaf while
 * TypeScript still enforces that every key (and only those keys) is present.
 */
export type StringLeaves<T extends TranslationTree> = {
  [N in keyof T]: { [K in keyof T[N]]: string };
};

/** Every "namespace.key" path through a translation tree, e.g. "signIn.title". */
export type DotPaths<T extends TranslationTree> = {
  [N in keyof T & string]: `${N}.${keyof T[N] & string}`;
}[keyof T & string];
