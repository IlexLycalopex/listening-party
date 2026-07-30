#!/usr/bin/env node
// Emits idempotent SQL that loads the Reading List YAML into Supabase.
//
//   READING_LIST_REPO=/path/to/readinglist \
//     node scripts/import/reading-list.js --out ./out
//
// Output is split one file per year (plus 00-workspace.sql), because the full
// set is ~245 books with long OpenLibrary descriptions and a single statement
// that size is awkward to paste into the SQL editor. Apply them in filename
// order; every statement is ON CONFLICT so re-running is safe.

import { readFileSync, readdirSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import yaml from 'js-yaml';
import { lit, text, num, bool, date, textArray, valuesList } from './lib/sql.js';

const REPO = process.env.READING_LIST_REPO ?? '/workspace/readinglist';
const DATA = join(REPO, 'src/data');
const OUT = resolve(process.argv[process.argv.indexOf('--out') + 1] ?? './import-out');

const OWNER_EMAIL = process.env.OWNER_EMAIL ?? 'alexander.jameswatts@gmail.com';
const WS_SLUG = process.env.WORKSPACE_SLUG ?? 'jamie';
const WS_NAME = process.env.WORKSPACE_NAME ?? 'Reading List';
const WS_VISIBILITY = process.env.WORKSPACE_VISIBILITY ?? 'public';

// The publisher alias table lives in the reading-list repo. It is the same
// normalisation the publishers page relies on, so reuse it rather than
// reimplementing it here; fall back to identity if the repo layout moves.
let canonicalPublisher = name => name ?? '';
try {
  ({ canonicalPublisher } = await import(join(REPO, 'scripts/publisher-aliases.js')));
} catch {
  process.stderr.write('warning: publisher-aliases.js not found, storing publishers verbatim\n');
}

const read = f => yaml.load(readFileSync(join(DATA, f), 'utf-8'));

const years = read('years.yaml');
const bookFiles = readdirSync(join(DATA, 'books')).filter(f => f.endsWith('.yaml')).sort();

const WS = `(select id from public.workspaces where app = 'reading-list' and slug = ${lit(WS_SLUG)})`;

mkdirSync(OUT, { recursive: true });

// ── 00: workspace and year rows ───────────────────────────────────
const yearRows = bookFiles.map(f => {
  const id = f.replace(/\.yaml$/, '');
  const parsed = read(join('books', f));
  const meta = years.find(y => String(y.id) === id);
  return { id, parsed, status: meta?.status ?? 'active' };
});

writeFileSync(join(OUT, '00-workspace.sql'), `-- Reading List: workspace and years
begin;

insert into public.workspaces (app, slug, name, description, visibility, owner_id)
select 'reading-list', ${lit(WS_SLUG)}, ${lit(WS_NAME)}, '', ${lit(WS_VISIBILITY)}::public.visibility, p.id
from public.profiles p
where p.email = ${lit(OWNER_EMAIL)}
on conflict (app, slug) do update
  set name = excluded.name, visibility = excluded.visibility;

insert into public.rl_years (workspace_id, year, status, total_books)
values
${valuesList(yearRows.map(y => [WS, num(y.id), lit(y.status), num(y.parsed.total_books)]))}
on conflict (workspace_id, year) do update
  set status = excluded.status, total_books = excluded.total_books;

commit;
`);

// ── One file per year ─────────────────────────────────────────────
let grandTotal = 0;

for (const { id, parsed } of yearRows) {
  const books = parsed.books ?? [];
  grandTotal += books.length;
  if (books.length === 0) continue;

  const rows = books.map(b => [
    num(b.order),
    text(b.title),
    text(b.author),
    num(b.pages),
    date(b.date_started),
    date(b.date_finished),
    lit(b.format || 'print'),
    num(b.year_published),
    text(b.genre),
    text(b.publisher),
    text(canonicalPublisher(b.publisher) ?? ''),
    text(b.cover_url),
    text(b.isbn),
    text(b.description),
    textArray(b.tags),
    text(b.notes),
    bool(b.reading),
    bool(b.coming_up),
    text(b.links?.openlibrary),
    text(b.links?.wikipedia),
  ]);

  writeFileSync(join(OUT, `${id}-books.sql`), `-- Reading List ${id}: ${books.length} books
begin;

insert into public.rl_books (
  workspace_id, year_id, order_read, title, author, pages,
  date_started, date_finished, format, year_published, genre,
  publisher, publisher_normalised, cover_url, isbn, description,
  tags, notes, reading, coming_up, link_openlibrary, link_wikipedia
)
select ${WS}, y.id, v.*
from (values
${valuesList(rows)}
) as v(order_read, title, author, pages, date_started, date_finished, format,
       year_published, genre, publisher, publisher_normalised, cover_url, isbn,
       description, tags, notes, reading, coming_up, link_openlibrary, link_wikipedia)
join public.rl_years y on y.workspace_id = ${WS} and y.year = ${num(id)}
on conflict (year_id, order_read) do update
  set title = excluded.title, author = excluded.author, pages = excluded.pages,
      date_started = excluded.date_started, date_finished = excluded.date_finished,
      format = excluded.format, year_published = excluded.year_published,
      genre = excluded.genre, publisher = excluded.publisher,
      publisher_normalised = excluded.publisher_normalised,
      cover_url = excluded.cover_url, isbn = excluded.isbn,
      description = excluded.description, tags = excluded.tags, notes = excluded.notes,
      reading = excluded.reading, coming_up = excluded.coming_up,
      link_openlibrary = excluded.link_openlibrary, link_wikipedia = excluded.link_wikipedia;

commit;
`);
}

process.stderr.write(
  `wrote ${yearRows.length + 1} files to ${OUT} — ${grandTotal} books across ${yearRows.length} years\n`
);
