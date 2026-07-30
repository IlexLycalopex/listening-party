# YAML → Supabase importers

One-off scripts that load the existing file-based records into the Grackles
Supabase project. They **emit SQL to disk**; they never talk to the network.
That is deliberate — an import can be read as a diff before it touches the
database, and replayed later without a service-role key in a shell.

Every statement carries `ON CONFLICT` on the table's natural key, so re-running
updates in place rather than duplicating. The YAML stays in git as the
historical record.

## Running them

```bash
npm ci

# Listening Party — reads this repo's own src/data/
node scripts/import/listening-party.js > out/listening-party.sql

# Reading List — one file per year, because 245 books with OpenLibrary
# descriptions is too much for a single paste into the SQL editor
READING_LIST_REPO=../readinglist \
  node scripts/import/reading-list.js --out out/reading-list

# Cigar Lounge
CIGAR_LOUNGE_REPO=../cigarLounge \
  node scripts/import/cigar-lounge.js > out/cigar-lounge.sql
```

Then apply, in filename order, either through the Supabase SQL editor or:

```bash
psql "$SUPABASE_DB_URL" -f out/listening-party.sql
for f in out/reading-list/*.sql; do psql "$SUPABASE_DB_URL" -f "$f"; done
```

## Environment

| Variable | Default | Notes |
|---|---|---|
| `OWNER_EMAIL` | `alexander.jameswatts@gmail.com` | Must already exist in `auth.users`; the workspace is created owned by them |
| `WORKSPACE_SLUG` | `brothers` / `jamie` / `jamie` | Second path segment in the URL |
| `WORKSPACE_NAME` | app name | Display name |
| `WORKSPACE_VISIBILITY` | `public` (LP, RL) · `private` (cigars) | `private` \| `unlisted` \| `public` |
| `READING_LIST_REPO` | `/workspace/readinglist` | Checkout to read from |
| `CIGAR_LOUNGE_REPO` | `/workspace/cigarlounge` | Checkout to read from |

Set `WORKSPACE_SLUG` to give someone their own instance — e.g.
`WORKSPACE_SLUG=nick OWNER_EMAIL=nick@… node scripts/import/reading-list.js`
creates a second, independent reading list at `/reading/nick`.

## Import status

| App | Records | Loaded |
|---|---|---|
| Listening Party | 3 contributors, 2 seasons, 106 selections (31 completed) | all |
| Cigar Lounge | 1 entry | all |
| Reading List | 7 years, 245 books | years + 2020 (13 books); 2021–2026 generated, not yet applied |

The remaining reading-list years are generated and valid — they were left
unapplied only because this session could reach the database solely through the
MCP SQL bridge, which is a poor fit for ~150 KB of book descriptions. Applying
them is the `psql` loop above, or six pastes into the SQL editor.

## Schema notes worth carrying forward

- **`lp_contributors.user_id` is nullable.** Chris has picks scheduled for 2027
  and no account. Linking a contributor to a real user is a separate, later
  step; picks must be attributable before then.
- **Cigar prices are stored twice.** `price_text` keeps what was written
  (`>£40`), `price_gbp` holds the parsed number and `price_approximate` records
  that it was hedged — mirroring `parsePrice()` in the cigar lounge's
  `src/lib/cigars.ts`.
- **Publisher normalisation happens on write.** `publisher_normalised` is filled
  from the reading list's own `scripts/publisher-aliases.js`, so the publishers
  page groups imprints without re-deriving on every read.
- **The enrichment scripts have not moved yet.** `fetch-artwork.js` (iTunes) and
  the reading list's `fetch-metadata.js` (OpenLibrary) still run at build time
  against YAML. They belong in an Edge Function called after a save, plus a
  nightly backfill — that is Phase 3 work, not part of the import.
