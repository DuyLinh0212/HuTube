export const MAX_COMMENT_TEMPLATES = 100;

/** One RFC 4180 column named comment; quoted commas, quotes and newlines are preserved. */
export function parseCommentCsv(csv: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], field = '', quoted = false, closed = false;
  const text = csv.replace(/^\uFEFF/, '');
  const finishRow = () => {
    row.push(field);
    if (row.some(value => value.trim())) rows.push(row);
    row = []; field = ''; closed = false;
  };
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (quoted) {
      if (char !== '"') field += char;
      else if (text[i + 1] === '"') { field += '"'; i++; }
      else { quoted = false; closed = true; }
    } else if (char === ',') {
      row.push(field); field = ''; closed = false;
    } else if (char === '\n' || char === '\r') {
      if (char === '\r' && text[i + 1] === '\n') i++;
      finishRow();
    } else if (closed) {
      if (char !== ' ' && char !== '\t') throw new Error('INVALID_COMMENT_CSV');
    } else if (char === '"') {
      if (field.length) throw new Error('INVALID_COMMENT_CSV');
      quoted = true;
    } else field += char;
  }
  if (quoted) throw new Error('INVALID_COMMENT_CSV');
  finishRow();
  const header = rows.shift();
  if (header?.length !== 1 || header[0].trim().toLowerCase() !== 'comment') throw new Error('INVALID_COMMENT_CSV');
  return rows;
}

export function mergeCommentTemplates(existing: string[], rows: string[][]) {
  const templates = [...existing];
  const seen = new Set(existing);
  let added = 0, duplicates = 0, invalid = 0, overflow = 0;
  for (const row of rows) {
    const text = row[0]?.trim() ?? '';
    if (row.length !== 1 || text.length < 3 || text.length > 5000) { invalid++; continue; }
    if (seen.has(text)) { duplicates++; continue; }
    seen.add(text);
    if (templates.length >= MAX_COMMENT_TEMPLATES) { overflow++; continue; }
    templates.push(text); added++;
  }
  return { templates, added, duplicates, invalid, overflow };
}
