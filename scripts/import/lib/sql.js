// Helpers for emitting SQL literals.
//
// The importers write SQL to stdout rather than talking to Supabase directly,
// so an import can be reviewed as a diff before it touches the database and
// replayed later without handing a service-role key to a script.

/** A single-quoted SQL string literal, or NULL for null/undefined. */
export function lit(value) {
  if (value === null || value === undefined) return 'null';
  return `'${String(value).replace(/'/g, "''")}'`;
}

/** Same, but empty/absent collapses to '' — matches the NOT NULL DEFAULT '' columns. */
export function text(value) {
  return lit(value ?? '');
}

/** A number, or NULL if it isn't finite. YAML gives us strings and nulls alike. */
export function num(value) {
  if (value === null || value === undefined || value === '') return 'null';
  const n = Number(value);
  return Number.isFinite(n) ? String(n) : 'null';
}

export function bool(value) {
  return value === true ? 'true' : 'false';
}

/** A DATE literal. Accepts a JS Date (js-yaml parses unquoted dates) or a string. */
export function date(value) {
  if (!value) return 'null';
  const iso = value instanceof Date ? value.toISOString().slice(0, 10) : String(value).slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(iso) ? `'${iso}'::date` : 'null';
}

/** A text[] literal. */
export function textArray(values) {
  if (!Array.isArray(values) || values.length === 0) return `'{}'::text[]`;
  return `array[${values.map(lit).join(', ')}]::text[]`;
}

/** The slug rule enforced by workspaces.slug's CHECK constraint. */
export function slugify(name) {
  return String(name)
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

/** Wraps row tuples into a VALUES list, or returns null when there is nothing to write. */
export function valuesList(rows) {
  if (rows.length === 0) return null;
  return rows.map(cols => `    (${cols.join(', ')})`).join(',\n');
}
