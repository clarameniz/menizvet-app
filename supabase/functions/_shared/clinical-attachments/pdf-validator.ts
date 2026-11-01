// @deno-types="npm:@cantoo/pdf-lib@2.9.1"
import {
  ParseSpeeds,
  PDFArray,
  type PDFContext,
  PDFDict,
  PDFDocument,
  PDFInvalidObject,
  PDFName,
  type PDFObject,
  PDFRef,
  PDFStream,
} from "@cantoo/pdf-lib";
import { ATTACHMENT_POLICY, PDF_VALIDATION_LIMITS } from "./policy.ts";

export type PdfRejectionCode =
  | "PDF_EMPTY"
  | "PDF_TOO_LARGE"
  | "PDF_ENCRYPTED"
  | "PDF_PARSE_INVALID"
  | "PDF_UNRESOLVED_REFERENCE"
  | "PDF_JAVASCRIPT"
  | "PDF_XFA"
  | "PDF_EMBEDDED_FILE"
  | "PDF_LAUNCH"
  | "PDF_ACTION_UNSUPPORTED"
  | "PDF_RICH_MEDIA"
  | "PDF_MULTIMEDIA_UNSUPPORTED"
  | "PDF_ACTIVE_FEATURE_UNSUPPORTED"
  | "PDF_UNSUPPORTED_STRUCTURE"
  | "PDF_RESOURCE_LIMIT";

export interface PdfValidationStats {
  readonly byteSize: number;
  readonly pageCount: number;
  readonly indirectObjectCount: number;
  readonly traversedObjectCount: number;
  readonly referenceCount: number;
  readonly elapsedMilliseconds: number;
}

export type PdfValidationResult =
  | { readonly accepted: true; readonly stats: PdfValidationStats }
  | {
    readonly accepted: false;
    readonly rejectionCode: PdfRejectionCode;
    readonly detail: string;
    readonly elapsedMilliseconds: number;
  };

class PolicyRejection extends Error {
  constructor(readonly rejectionCode: PdfRejectionCode, message: string) {
    super(message);
  }
}

const REJECTED_KEYS = new Map<string, PdfRejectionCode>([
  ["JavaScript", "PDF_JAVASCRIPT"],
  ["JS", "PDF_JAVASCRIPT"],
  ["XFA", "PDF_XFA"],
  ["EmbeddedFiles", "PDF_EMBEDDED_FILE"],
  ["EF", "PDF_EMBEDDED_FILE"],
  ["AF", "PDF_EMBEDDED_FILE"],
  ["Collection", "PDF_EMBEDDED_FILE"],
  ["OpenAction", "PDF_ACTION_UNSUPPORTED"],
  ["AA", "PDF_ACTION_UNSUPPORTED"],
  ["RichMediaContent", "PDF_RICH_MEDIA"],
  ["RichMediaSettings", "PDF_RICH_MEDIA"],
  ["3DD", "PDF_MULTIMEDIA_UNSUPPORTED"],
  ["Renditions", "PDF_MULTIMEDIA_UNSUPPORTED"],
  ["AlternatePresentations", "PDF_MULTIMEDIA_UNSUPPORTED"],
  ["PresSteps", "PDF_ACTIVE_FEATURE_UNSUPPORTED"],
  ["Requirements", "PDF_ACTIVE_FEATURE_UNSUPPORTED"],
  ["NeedsRendering", "PDF_ACTIVE_FEATURE_UNSUPPORTED"],
  ["Extensions", "PDF_ACTIVE_FEATURE_UNSUPPORTED"],
]);

const ACTION_NAMES = new Set([
  "GoTo",
  "GoToR",
  "GoToE",
  "Launch",
  "Thread",
  "URI",
  "Sound",
  "Movie",
  "Hide",
  "Named",
  "SubmitForm",
  "ResetForm",
  "ImportData",
  "JavaScript",
  "SetOCGState",
  "Rendition",
  "Trans",
  "GoTo3DView",
]);

const MULTIMEDIA_SUBTYPES = new Set([
  "Movie",
  "Sound",
  "Screen",
  "3D",
]);

const INERT_ANNOTATION_SUBTYPES = new Set([
  "Text",
  "Link",
  "FreeText",
  "Line",
  "Square",
  "Circle",
  "Polygon",
  "PolyLine",
  "Highlight",
  "Underline",
  "Squiggly",
  "StrikeOut",
  "Stamp",
  "Caret",
  "Ink",
  "Popup",
  "Widget",
  "PrinterMark",
  "TrapNet",
  "Watermark",
  "Redact",
]);

const SUPPORTED_STREAM_FILTERS = new Set([
  "FlateDecode",
  "Fl",
  "ASCIIHexDecode",
  "AHx",
  "ASCII85Decode",
  "A85",
  "LZWDecode",
  "LZW",
  "RunLengthDecode",
  "RL",
  "CCITTFaxDecode",
  "CCF",
  "JBIG2Decode",
  "DCTDecode",
  "DCT",
  "JPXDecode",
]);

interface TraversalState {
  readonly context: PDFContext;
  readonly startedAt: number;
  readonly visitedObjects: WeakSet<object>;
  readonly visitedReferences: Set<string>;
  traversedObjectCount: number;
  referenceCount: number;
}

function elapsed(startedAt: number): number {
  return performance.now() - startedAt;
}

function checkBudget(state: TraversalState, depth: number): void {
  if (depth > PDF_VALIDATION_LIMITS.maxTraversalDepth) {
    throw new PolicyRejection(
      "PDF_RESOURCE_LIMIT",
      "PDF object graph exceeds the traversal-depth limit",
    );
  }
  if (state.traversedObjectCount > PDF_VALIDATION_LIMITS.maxTraversedObjects) {
    throw new PolicyRejection(
      "PDF_RESOURCE_LIMIT",
      "PDF object graph exceeds the traversed-object limit",
    );
  }
  if (state.referenceCount > PDF_VALIDATION_LIMITS.maxReferences) {
    throw new PolicyRejection(
      "PDF_RESOURCE_LIMIT",
      "PDF object graph exceeds the reference limit",
    );
  }
  if (
    elapsed(state.startedAt) > PDF_VALIDATION_LIMITS.maxValidationMilliseconds
  ) {
    throw new PolicyRejection(
      "PDF_RESOURCE_LIMIT",
      "PDF validation exceeded the processing budget",
    );
  }
}

function resolveReference(state: TraversalState, ref: PDFRef): PDFObject {
  state.referenceCount += 1;
  checkBudget(state, 0);
  const resolved = state.context.lookup(ref);
  if (!resolved) {
    throw new PolicyRejection(
      "PDF_UNRESOLVED_REFERENCE",
      `Unresolved indirect reference ${ref.tag}`,
    );
  }
  return resolved;
}

function resolvedName(
  state: TraversalState,
  value: PDFObject | undefined,
): string | null {
  if (value instanceof PDFRef) value = resolveReference(state, value);
  return value instanceof PDFName ? value.decodeText() : null;
}

function rejectActiveDictionary(
  state: TraversalState,
  dictionary: PDFDict,
): void {
  const typeName = resolvedName(state, dictionary.get(PDFName.of("Type")));
  const subtypeName = resolvedName(
    state,
    dictionary.get(PDFName.of("Subtype")),
  );
  const actionName = resolvedName(state, dictionary.get(PDFName.of("S")));

  if (typeName === "EmbeddedFile" || typeName === "Filespec") {
    throw new PolicyRejection(
      "PDF_EMBEDDED_FILE",
      `Unsupported embedded-file structure /${typeName}`,
    );
  }
  if (typeName === "Action") {
    const code = actionName === "Launch"
      ? "PDF_LAUNCH"
      : actionName === "JavaScript"
      ? "PDF_JAVASCRIPT"
      : "PDF_ACTION_UNSUPPORTED";
    throw new PolicyRejection(
      code,
      "Action dictionaries are not supported by phase1-pdf-v1",
    );
  }
  if (actionName && ACTION_NAMES.has(actionName)) {
    const code = actionName === "Launch"
      ? "PDF_LAUNCH"
      : actionName === "JavaScript"
      ? "PDF_JAVASCRIPT"
      : "PDF_ACTION_UNSUPPORTED";
    throw new PolicyRejection(code, `Unsupported PDF action /${actionName}`);
  }
  if (subtypeName === "FileAttachment") {
    throw new PolicyRejection(
      "PDF_EMBEDDED_FILE",
      "File-attachment annotations are not supported",
    );
  }
  if (subtypeName === "RichMedia") {
    throw new PolicyRejection(
      "PDF_RICH_MEDIA",
      "RichMedia annotations are not supported",
    );
  }
  if (subtypeName && MULTIMEDIA_SUBTYPES.has(subtypeName)) {
    throw new PolicyRejection(
      "PDF_MULTIMEDIA_UNSUPPORTED",
      `Unsupported multimedia annotation /${subtypeName}`,
    );
  }
  if (
    typeName === "Annot" && subtypeName &&
    !INERT_ANNOTATION_SUBTYPES.has(subtypeName)
  ) {
    throw new PolicyRejection(
      "PDF_ACTIVE_FEATURE_UNSUPPORTED",
      `Unsupported annotation subtype /${subtypeName}`,
    );
  }

  for (const [key] of dictionary.entries()) {
    const keyName = key.decodeText();
    const code = REJECTED_KEYS.get(keyName);
    if (code) {
      throw new PolicyRejection(code, `Unsupported PDF structure /${keyName}`);
    }
  }
}

function inspectStreamFilters(state: TraversalState, stream: PDFStream): void {
  let filter = stream.dict.get(PDFName.of("Filter"));
  if (!filter) return;
  if (filter instanceof PDFRef) filter = resolveReference(state, filter);
  const filters = filter instanceof PDFArray ? filter.asArray() : [filter];
  for (let item of filters) {
    if (item instanceof PDFRef) item = resolveReference(state, item);
    if (
      !(item instanceof PDFName) ||
      !SUPPORTED_STREAM_FILTERS.has(item.decodeText())
    ) {
      throw new PolicyRejection(
        "PDF_UNSUPPORTED_STRUCTURE",
        "Unsupported or inconclusive stream filter",
      );
    }
  }
}

function traverseObject(
  state: TraversalState,
  object: PDFObject,
  depth: number,
): void {
  checkBudget(state, depth);
  if (object instanceof PDFRef) {
    if (state.visitedReferences.has(object.tag)) return;
    state.visitedReferences.add(object.tag);
    traverseObject(state, resolveReference(state, object), depth + 1);
    return;
  }
  if (object instanceof PDFInvalidObject) {
    throw new PolicyRejection(
      "PDF_PARSE_INVALID",
      "Parser produced an invalid PDF object",
    );
  }
  if (typeof object === "object" && object !== null) {
    if (state.visitedObjects.has(object)) return;
    state.visitedObjects.add(object);
  }
  state.traversedObjectCount += 1;
  checkBudget(state, depth);

  if (object instanceof PDFStream) {
    inspectStreamFilters(state, object);
    traverseObject(state, object.dict, depth + 1);
    return;
  }
  if (object instanceof PDFDict) {
    const entries = object.entries();
    if (entries.length > PDF_VALIDATION_LIMITS.maxDictionaryEntries) {
      throw new PolicyRejection(
        "PDF_RESOURCE_LIMIT",
        "PDF dictionary exceeds the entry limit",
      );
    }
    rejectActiveDictionary(state, object);
    for (const [, value] of entries) traverseObject(state, value, depth + 1);
    return;
  }
  if (object instanceof PDFArray) {
    if (object.size() > PDF_VALIDATION_LIMITS.maxArrayEntries) {
      throw new PolicyRejection(
        "PDF_RESOURCE_LIMIT",
        "PDF array exceeds the entry limit",
      );
    }
    for (const value of object.asArray()) {
      traverseObject(state, value, depth + 1);
    }
  }
}

function rejected(
  startedAt: number,
  rejectionCode: PdfRejectionCode,
  detail: string,
): PdfValidationResult {
  return Object.freeze({
    accepted: false,
    rejectionCode,
    detail,
    elapsedMilliseconds: elapsed(startedAt),
  });
}

export async function validatePhase1Pdf(
  bytes: Uint8Array,
): Promise<PdfValidationResult> {
  const startedAt = performance.now();
  if (bytes.byteLength === 0) {
    return rejected(startedAt, "PDF_EMPTY", "PDF is empty");
  }
  if (bytes.byteLength > ATTACHMENT_POLICY.maxBytes) {
    return rejected(
      startedAt,
      "PDF_TOO_LARGE",
      "PDF exceeds the Phase-1 byte limit",
    );
  }

  try {
    const document = await PDFDocument.load(bytes, {
      ignoreEncryption: false,
      parseSpeed: ParseSpeeds.Fastest,
      throwOnInvalidObject: true,
      warnOnInvalidObjects: false,
      updateMetadata: false,
      capNumbers: true,
      preserveXFA: true,
    });
    if (document.isEncrypted) {
      throw new PolicyRejection(
        "PDF_ENCRYPTED",
        "Encrypted PDFs are not supported",
      );
    }
    const pageCount = document.getPageCount();
    if (pageCount < 1) {
      throw new PolicyRejection(
        "PDF_PARSE_INVALID",
        "PDF must contain at least one structurally valid page",
      );
    }

    const indirectObjects = document.context.enumerateIndirectObjects();
    if (indirectObjects.length > PDF_VALIDATION_LIMITS.maxIndirectObjects) {
      throw new PolicyRejection(
        "PDF_RESOURCE_LIMIT",
        "PDF exceeds the indirect-object limit",
      );
    }
    const state: TraversalState = {
      context: document.context,
      startedAt,
      visitedObjects: new WeakSet<object>(),
      visitedReferences: new Set<string>(),
      traversedObjectCount: 0,
      referenceCount: 0,
    };
    for (const [, object] of indirectObjects) traverseObject(state, object, 0);
    checkBudget(state, 0);

    return Object.freeze({
      accepted: true,
      stats: Object.freeze({
        byteSize: bytes.byteLength,
        pageCount,
        indirectObjectCount: indirectObjects.length,
        traversedObjectCount: state.traversedObjectCount,
        referenceCount: state.referenceCount,
        elapsedMilliseconds: elapsed(startedAt),
      }),
    });
  } catch (error) {
    if (error instanceof PolicyRejection) {
      return rejected(startedAt, error.rejectionCode, error.message);
    }
    const message = error instanceof Error
      ? error.message
      : "Unknown PDF parser failure";
    const encrypted = /encrypt|password/i.test(message);
    return rejected(
      startedAt,
      encrypted ? "PDF_ENCRYPTED" : "PDF_PARSE_INVALID",
      encrypted
        ? "Encrypted or password-protected PDF"
        : "PDF parser could not conclusively inspect the document",
    );
  }
}
