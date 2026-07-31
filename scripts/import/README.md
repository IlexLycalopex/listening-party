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

# Reading List — one file per year, because ~250 books with OpenLibrary
# descriptions is too much for a single paste into the SQL editor.
# NB: that checkout must be on `main`, not the repo's default branch — see
# "Import status" below.
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
| Reading List | 7 years, 249 books (2 currently reading) | all |

All three imports are complete and verified against the source files.

> **The reading list lives on `readinglist`'s `main` branch.** The repo's
> *default* branch is `claude/build-reading-list-repo-3uY1S`, which is stale —
> at the time of writing, three weeks and four books behind. The first import
> took the default branch and silently loaded an old snapshot. Check `main`, or
> compare book counts across branches, before trusting a checkout.

The reading list did not go in through these scripts in the end. ~150 KB of
book descriptions was a poor fit for the SQL bridge available at the time, so a
throwaway Edge Function fetched the YAML from the public GitHub repo and wrote
it server-side instead. The function has since been emptied and should be
deleted from the dashboard. These scripts remain the supported path for a fresh
import or a new workspace.

## Seeding an auth user with raw SQL

Don't, if you can avoid it — use `auth.admin.createUser()`. If you must (the
workspace importers need an owner to exist before they can run), the row has to
look exactly like the one GoTrue writes:

- An `auth.identities` row for the `email` provider, with `identity_data`
  containing `sub`, `email` and `email_verified`. Its `email` column is
  generated from `identity_data` — do not insert it directly.
- **`confirmation_token`, `recovery_token`, `email_change_token_new` and
  `email_change` must be `''`, not `NULL`.** They are nullable in the schema but
  GoTrue scans them into Go `string`, so a NULL fails every lookup for that user
  with `converting NULL to string is unsupported` — surfacing as a 500 from
  `/otp` and a sign-in that simply never works. The remaining token columns
  already default to `''`.

## Schema notes worth carrying forward

- **`lp_contributors.user_id` is nullable.** Chris has picks scheduled for 2027
  and no account. Linking a contributor to a real user is a separate, later
  step; picks must be attributable before then.
- **Cigar prices are stored twice.** `price_text` keeps what was written
  (`>£40`), `price_gbp` holds the parsed number and `price_approximate` records
  that it was hedged — mirroring `parsePrice()` in the cigar lounge's
  `src/lib/cigars.ts`.
- **Publisher normalisation happens on write, in the database.** The alias table
  from `readinglist/scripts/publisher-aliases.js` now lives in
  `rl_publisher_aliases`, with a trigger on `rl_books` that fills
  `publisher_normalised` via `app.canonical_publisher()` (migration 0005). An
  importer no longer has to remember to do it, and a publisher typed into the
  edit form is normalised the same way one fetched from Open Library is.
- **The enrichment scripts have not moved yet.** `fetch-artwork.js` (iTunes) and
  the reading list's `fetch-metadata.js` (OpenLibrary) still run at build time
  against YAML. They belong in an Edge Function called after a save, plus a
  nightly backfill — that is Phase 3 work, not part of the import.
