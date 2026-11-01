import { PDFDocument, PDFHexString, PDFName } from "@cantoo/pdf-lib";

const encoder = new TextEncoder();

interface PdfBuildOptions {
  readonly catalogExtra?: string;
  readonly pageExtra?: string;
  readonly extraObjects?: Readonly<Record<number, string>>;
  readonly trailerExtra?: string;
  readonly pageCount?: number;
  readonly content?: string;
}

interface BuiltPdf {
  readonly bytes: Uint8Array;
  readonly xrefOffset: number;
}

function ascii(value: string): Uint8Array {
  return encoder.encode(value);
}

function concat(chunks: readonly Uint8Array[]): Uint8Array {
  const size = chunks.reduce((total, chunk) => total + chunk.byteLength, 0);
  const output = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}

export function buildPdf(options: PdfBuildOptions = {}): BuiltPdf {
  const pageCount = options.pageCount ?? 1;
  const objects = new Map<number, string>();
  const pageRefs: string[] = [];
  let nextObjectNumber = 3;
  for (let page = 0; page < pageCount; page += 1) {
    const pageObject = nextObjectNumber++;
    const contentObject = nextObjectNumber++;
    pageRefs.push(`${pageObject} 0 R`);
    const content = page === 0 ? options.content ?? "" : "";
    objects.set(
      pageObject,
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents ${contentObject} 0 R ${
        options.pageExtra ?? ""
      } >>`,
    );
    objects.set(
      contentObject,
      `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
    );
  }
  objects.set(
    1,
    `<< /Type /Catalog /Pages 2 0 R ${options.catalogExtra ?? ""} >>`,
  );
  objects.set(
    2,
    `<< /Type /Pages /Kids [${pageRefs.join(" ")}] /Count ${pageCount} >>`,
  );
  for (
    const [objectNumber, body] of Object.entries(options.extraObjects ?? {})
  ) {
    objects.set(Number(objectNumber), body);
  }

  const maxObjectNumber = Math.max(...objects.keys());
  const chunks: Uint8Array[] = [ascii("%PDF-1.7\n")];
  const offsets = new Map<number, number>();
  let currentOffset = chunks[0].byteLength;
  for (
    let objectNumber = 1;
    objectNumber <= maxObjectNumber;
    objectNumber += 1
  ) {
    const body = objects.get(objectNumber);
    if (body === undefined) continue;
    offsets.set(objectNumber, currentOffset);
    const objectBytes = ascii(`${objectNumber} 0 obj\n${body}\nendobj\n`);
    chunks.push(objectBytes);
    currentOffset += objectBytes.byteLength;
  }

  const xrefOffset = currentOffset;
  let xref = `xref\n0 ${maxObjectNumber + 1}\n0000000000 65535 f \n`;
  for (
    let objectNumber = 1;
    objectNumber <= maxObjectNumber;
    objectNumber += 1
  ) {
    const objectOffset = offsets.get(objectNumber);
    xref += objectOffset === undefined
      ? "0000000000 00000 f \n"
      : `${String(objectOffset).padStart(10, "0")} 00000 n \n`;
  }
  xref += `trailer\n<< /Size ${maxObjectNumber + 1} /Root 1 0 R ${
    options.trailerExtra ?? ""
  } >>\n`;
  xref += `startxref\n${xrefOffset}\n%%EOF\n`;
  chunks.push(ascii(xref));
  return { bytes: concat(chunks), xrefOffset };
}

export function minimalValidPdf(): Uint8Array {
  return buildPdf().bytes;
}

export function ordinaryMultiPagePdf(): Uint8Array {
  return buildPdf({
    pageCount: 3,
    content: "BT /F1 12 Tf 72 720 Td (Clinical report) Tj ET",
  }).bytes;
}

export async function objectStreamPdf(): Promise<Uint8Array> {
  const document = await PDFDocument.create({ updateMetadata: false });
  document.addPage([612, 792]);
  return document.save({
    useObjectStreams: true,
    updateFieldAppearances: false,
  });
}

export async function adversarialCompressedObjectStreamPdf(): Promise<
  Uint8Array
> {
  const document = await PDFDocument.create({ updateMetadata: false });
  document.addPage([612, 792]);
  const references = [];
  const payload = "a".repeat(256);
  for (let index = 0; index < 6_000; index += 1) {
    references.push(document.context.register(document.context.obj({
      Index: index,
      Payload: PDFHexString.fromText(`${payload}${index}`),
    })));
  }
  document.catalog.set(
    PDFName.of("LoadStressObjects"),
    document.context.obj(references),
  );
  return document.save({
    useObjectStreams: true,
    objectsPerTick: Number.POSITIVE_INFINITY,
    updateFieldAppearances: false,
  });
}

export function incrementalRevisionPdf(): Uint8Array {
  const base = buildPdf();
  const updatedCatalogOffset = base.bytes.byteLength;
  const updatedCatalog = ascii(
    "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
  );
  const xrefOffset = updatedCatalogOffset + updatedCatalog.byteLength;
  const incremental = ascii(
    `xref\n1 1\n${String(updatedCatalogOffset).padStart(10, "0")} 00000 n \n` +
      `trailer\n<< /Size 5 /Root 1 0 R /Prev ${base.xrefOffset} >>\n` +
      `startxref\n${xrefOffset}\n%%EOF\n`,
  );
  return concat([base.bytes, updatedCatalog, incremental]);
}

export function nearSizeLimitValidPdf(): Uint8Array {
  return buildPdf({ content: " ".repeat(10_300_000) }).bytes;
}

export function encryptedPdf(): Uint8Array {
  return buildPdf({
    trailerExtra: "/Encrypt 5 0 R /ID [(fixture-id)(fixture-id)]",
    extraObjects: {
      5: "<< /Filter /Standard /V 1 /R 2 /O (owner) /U (user) /P -4 >>",
    },
  }).bytes;
}

export function javascriptPdf(): Uint8Array {
  return buildPdf({
    catalogExtra: "/Names << /JavaScript << /Names [(fixture) 5 0 R] >> >>",
    extraObjects: {
      5: "<< /Type /Action /S /JavaScript /JS (app.alert\\(1\\)) >>",
    },
  }).bytes;
}

export function openActionPdf(): Uint8Array {
  return buildPdf({
    catalogExtra: "/OpenAction 5 0 R",
    extraObjects: { 5: "<< /Type /Action /S /GoTo /D [3 0 R /Fit] >>" },
  }).bytes;
}

export function additionalActionPdf(): Uint8Array {
  return buildPdf({
    pageExtra: "/AA << /O 5 0 R >>",
    extraObjects: { 5: "<< /Type /Action /S /GoTo /D [3 0 R /Fit] >>" },
  }).bytes;
}

export function embeddedFilePdf(): Uint8Array {
  return buildPdf({
    catalogExtra:
      "/Names << /EmbeddedFiles << /Names [(report.txt) 5 0 R] >> >>",
    extraObjects: {
      5: "<< /Type /Filespec /F (report.txt) /EF << /F 6 0 R >> >>",
      6: "<< /Type /EmbeddedFile /Length 4 >>\nstream\ntest\nendstream",
    },
  }).bytes;
}

export function launchActionPdf(): Uint8Array {
  return buildPdf({
    extraObjects: { 5: "<< /Type /Action /S /Launch /F (payload.exe) >>" },
  }).bytes;
}

export function xfaPdf(): Uint8Array {
  return buildPdf({
    catalogExtra: "/AcroForm << /XFA 5 0 R >>",
    extraObjects: { 5: "<< /Length 7 >>\nstream\n<xfa/>\nendstream" },
  }).bytes;
}

export function annotationPdf(subtype: string): Uint8Array {
  return buildPdf({
    pageExtra: "/Annots [5 0 R]",
    extraObjects: {
      5: `<< /Type /Annot /Subtype /${subtype} /Rect [0 0 10 10] >>`,
    },
  }).bytes;
}

export function unsupportedFilterPdf(): Uint8Array {
  return buildPdf({
    extraObjects: {
      5: "<< /Length 4 /Filter /UnknownClinicalFilter >>\nstream\ntest\nendstream",
    },
  }).bytes;
}

export function deeplyNestedPdf(): Uint8Array {
  return buildPdf({
    extraObjects: { 5: `${"[".repeat(70)} 0 ${"]".repeat(70)}` },
  }).bytes;
}

export function unresolvedReferencePdf(): Uint8Array {
  return buildPdf({ extraObjects: { 5: "<< /Broken 999 0 R >>" } }).bytes;
}

export function cyclicReferencePdf(): Uint8Array {
  return buildPdf({
    extraObjects: {
      5: "<< /Next 6 0 R >>",
      6: "<< /Next 5 0 R >>",
    },
  }).bytes;
}
