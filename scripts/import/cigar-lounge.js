#!/usr/bin/env node
// Emits idempotent SQL that loads the Cigar Lounge markdown entries into
// Supabase.
//
//   CIGAR_LOUNGE_REPO=/path/to/cigarLounge node scripts/import/cigar-lounge.js > cigars.sql
//
// Each entry is one markdown file: YAML frontmatter plus a body of tasting
// notes. The filename stem is the slug, which is also the URL, so it carries
// over unchanged and existing links keep working.

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import yaml from 'js-yaml';
import { lit, text, num, bool, date, valuesList } from './lib/sql.js';

const REPO = process.env.CIGAR_LOUNGE_REPO ?? '/workspace/cigarlounge';
const CONTENT = join(REPO, 'src/content/cigars');

const OWNER_EMAIL = process.env.OWNER_EMAIL ?? 'alexander.jameswatts@gmail.com';
const WS_SLUG = process.env.WORKSPACE_SLUG ?? 'jamie';
const WS_NAME = process.env.WORKSPACE_NAME ?? 'Cigar Lounge';
// Private by default — a cigar lounge is a personal log, not a showcase, and
// the brief was that Jamie and Rob keep separate ones and invite each other in.
const WS_VISIBILITY = process.env.WORKSPACE_VISIBILITY ?? 'private';

/** Splits `---\n<yaml>\n---\n<body>`. Avoids a gray-matter dependency. */
function parseFrontmatter(raw) {
  const m = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
  if (!m) throw new Error('missing frontmatter');
  return { data: yaml.load(m[1]) ?? {}, body: m[2].trim() };
}

/**
 * Mirrors parsePrice() in the cigar lounge's src/lib/cigars.ts. The written
 * form is kept verbatim because ">£40" is the honest record; the parsed number
 * rides alongside so the stats page can still total a humidor.
 */
function parsePrice(raw) {
  if (raw === undefined || raw === null || raw === '') {
    return { display: '', value: null, approximate: false };
  }
  if (typeof raw === 'number') return { display: `£${raw.toFixed(2)}`, value: raw, approximate: false };

  const str = String(raw).trim();
  const approximate = /[>~<≈]|approx|about|around|over|under|\bc\.\s/i.test(str);
  const match = str.match(/\d+(?:[.,]\d+)?/);
  const value = match ? Number(match[0].replace(',', '')) : null;
  return { display: str, value: Number.isFinite(value) ? value : null, approximate };
}

const files = readdirSync(CONTENT).filter(f => f.endsWith('.md')).sort();

const WS = `(select id from public.workspaces where app = 'cigar-lounge' and slug = ${lit(WS_SLUG)})`;

const rows = files.map(file => {
  const { data, body } = parseFrontmatter(readFileSync(join(CONTENT, file), 'utf-8'));
  const price = parsePrice(data.pricePaid);
  // A file with a dateSmoked is a smoked entry even if status is absent —
  // the same default the content collection schema applies.
  const status = data.status ?? 'smoked';

  return [
    WS,
    lit(file.replace(/\.md$/, '')),
    lit(status),
    num(data.quantity ?? 1),
    text(data.name),
    text(data.brand),
    text(data.vitola),
    text(data.wrapper),
    text(data.length),
    num(data.ringGauge),
    text(data.country),
    data.strength ? lit(data.strength) : 'null',
    text(data.boughtAt),
    text(data.smokedAt),
    date(data.dateAcquired),
    date(data.dateSmoked),
    text(price.display),
    price.value === null ? 'null' : String(price.value),
    bool(price.approximate),
    num(data.rating),
    text(data.pairing),
    text(data.note),
    text(data.photo),
    text(body),
  ];
});

process.stdout.write(`-- Cigar Lounge import — ${rows.length} entries
begin;

insert into public.workspaces (app, slug, name, description, visibility, owner_id)
select 'cigar-lounge', ${lit(WS_SLUG)}, ${lit(WS_NAME)}, '', ${lit(WS_VISIBILITY)}::public.visibility, p.id
from public.profiles p
where p.email = ${lit(OWNER_EMAIL)}
on conflict (app, slug) do update
  set name = excluded.name, visibility = excluded.visibility;

insert into public.cl_cigars (
  workspace_id, slug, status, quantity, name, brand, vitola, wrapper,
  length_text, ring_gauge, country, strength, bought_at, smoked_at,
  date_acquired, date_smoked, price_text, price_gbp, price_approximate,
  rating, pairing, note, photo_path, tasting_notes
)
values
${valuesList(rows)}
on conflict (workspace_id, slug) do update
  set status = excluded.status, quantity = excluded.quantity, name = excluded.name,
      brand = excluded.brand, vitola = excluded.vitola, wrapper = excluded.wrapper,
      length_text = excluded.length_text, ring_gauge = excluded.ring_gauge,
      country = excluded.country, strength = excluded.strength,
      bought_at = excluded.bought_at, smoked_at = excluded.smoked_at,
      date_acquired = excluded.date_acquired, date_smoked = excluded.date_smoked,
      price_text = excluded.price_text, price_gbp = excluded.price_gbp,
      price_approximate = excluded.price_approximate, rating = excluded.rating,
      pairing = excluded.pairing, note = excluded.note,
      photo_path = excluded.photo_path, tasting_notes = excluded.tasting_notes;

commit;
`);

process.stderr.write(`${rows.length} cigar entries\n`);
