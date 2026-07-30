-- Per-app tables for Grackles.
--
-- Every table carries workspace_id and gets the same four policies, so access
-- control is identical everywhere: members read, editors write, and anonymous
-- visitors see public workspaces only.
--
-- The integrity rules these apps currently enforce in JavaScript at build time
-- become real constraints here. Where a rule is a direct translation, the
-- original is cited in a comment.

-- ── Shared ────────────────────────────────────────────────────────
create function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ══ Listening Party ═══════════════════════════════════════════════

-- user_id is nullable on purpose. Chris is a contributor in contributors.yaml
-- with picks scheduled for 2027 and no account; picks must be attributable
-- before someone signs up, and link to a real user later.
create table public.lp_contributors (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  slug         text not null check (slug <> ''),
  name         text not null check (name <> ''),
  color        text not null check (color <> ''),
  user_id      uuid references public.profiles(id) on delete set null,
  sort_order   int  not null default 0,
  created_at   timestamptz not null default now(),
  unique (workspace_id, slug)
);

create table public.lp_seasons (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  slug         text not null check (slug <> ''),
  title        text not null check (title <> ''),
  description  text not null default '',
  total_weeks  int  not null check (total_weeks >= 1),
  status       text not null default 'upcoming'
                 check (status in ('upcoming', 'active', 'complete')),
  sort_order   int  not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (workspace_id, slug)
);

-- Which contributors are playing in a given season. seasons.yaml carries this
-- as a `contributors: [jamie, nick]` list; keeping it explicit preserves the
-- fact that Chris is in 2027 but not 2026, even before he has any picks.
create table public.lp_season_contributors (
  season_id      uuid not null references public.lp_seasons(id) on delete cascade,
  contributor_id uuid not null references public.lp_contributors(id) on delete cascade,
  sort_order     int  not null default 0,
  primary key (season_id, contributor_id)
);

create table public.lp_selections (
  id             uuid primary key default gen_random_uuid(),
  workspace_id   uuid not null references public.workspaces(id) on delete cascade,
  season_id      uuid not null references public.lp_seasons(id) on delete cascade,
  contributor_id uuid not null references public.lp_contributors(id) on delete restrict,
  week           int  not null check (week >= 1),
  year_slot      int  not null,
  album          text not null default '',
  artist         text not null default '',
  status         text not null check (status in ('completed', 'upcoming')),
  artwork_url    text not null default '',
  link_wikipedia text not null default '',
  link_spotify   text not null default '',
  link_youtube   text not null default '',
  notes          text not null default '',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  -- A week may host more than one pick (2027 week 52 has three, one per
  -- contributor) but never two from the same person.
  -- Was: the seenWeekContributors loop in src/lib/data.ts:133-141.
  unique (season_id, week, contributor_id),

  -- Was: the superRefine in src/lib/data.ts:44-51.
  constraint lp_selections_completed_has_album
    check (status <> 'completed' or (album <> '' and artist <> ''))
);

create index lp_selections_season_idx      on public.lp_selections (season_id, week);
create index lp_selections_contributor_idx on public.lp_selections (contributor_id);
-- The artists page groups by exact artist string across all seasons.
create index lp_selections_artist_idx      on public.lp_selections (workspace_id, artist)
  where status = 'completed';

-- ══ Reading List ══════════════════════════════════════════════════

create table public.rl_years (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  year         int  not null,
  status       text not null default 'active' check (status in ('active', 'complete')),
  total_books  int,
  created_at   timestamptz not null default now(),
  unique (workspace_id, year)
);

create table public.rl_books (
  id                    uuid primary key default gen_random_uuid(),
  workspace_id          uuid not null references public.workspaces(id) on delete cascade,
  year_id               uuid not null references public.rl_years(id) on delete cascade,
  order_read            int  not null check (order_read >= 1),
  title                 text not null check (title <> ''),
  author                text not null default '',
  pages                 int  check (pages is null or pages > 0),
  date_started          date,
  date_finished         date,
  format                text not null default 'print'
                          check (format in ('print', 'audio', 'graphic')),
  year_published        int,
  genre                 text not null default '',
  publisher             text not null default '',
  -- Written on save by the alias table currently in scripts/publisher-aliases.js,
  -- so the publishers page groups imprints without re-deriving on every read.
  publisher_normalised  text not null default '',
  cover_url             text not null default '',
  isbn                  text not null default '',
  description           text not null default '',
  tags                  text[] not null default '{}',
  notes                 text not null default '',
  reading               boolean not null default false,
  coming_up             boolean not null default false,
  link_openlibrary      text not null default '',
  link_wikipedia        text not null default '',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  unique (year_id, order_read),
  constraint rl_books_dates_ordered
    check (date_started is null or date_finished is null or date_started <= date_finished)
);

create index rl_books_year_idx      on public.rl_books (year_id, order_read);
create index rl_books_author_idx    on public.rl_books (workspace_id, author);
create index rl_books_publisher_idx on public.rl_books (workspace_id, publisher_normalised);
create index rl_books_tags_idx      on public.rl_books using gin (tags);

-- ══ Cigar Lounge ══════════════════════════════════════════════════

-- One table: a humidor entry becomes a smoked entry in place, keeping its id
-- and URL, exactly as the markdown file does today.
create table public.cl_cigars (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references public.workspaces(id) on delete cascade,
  slug          text not null check (slug <> ''),
  status        text not null default 'smoked' check (status in ('humidor', 'smoked')),
  quantity      int  not null default 1 check (quantity > 0),
  name          text not null check (name <> ''),
  brand         text not null default '',
  vitola        text not null default '',
  wrapper       text not null default '',
  length_text   text not null default '',   -- as written on the box: '4 7/8"', '124mm'
  ring_gauge    int  check (ring_gauge is null or ring_gauge > 0),
  country       text not null default '',
  strength      text check (strength is null or strength in ('mild', 'medium', 'full')),
  bought_at     text not null default '',
  smoked_at     text not null default '',
  date_acquired date,
  date_smoked   date,

  -- Price is kept as written ('>£40', '~£25') because that is the honest
  -- record, with the parsed value alongside so the stats page can still sum.
  -- Mirrors parsePrice() in src/lib/cigars.ts:94-109.
  price_text        text not null default '',
  price_gbp         numeric(10, 2) check (price_gbp is null or price_gbp >= 0),
  price_approximate boolean not null default false,

  rating        numeric(2, 1)
                  check (rating is null or (rating >= 0 and rating <= 5 and (rating * 2) % 1 = 0)),
  pairing       text not null default '',
  note          text not null default '',
  photo_path    text not null default '',   -- key in the cigar-photos bucket, or an absolute URL
  tasting_notes text not null default '',   -- the markdown body
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  unique (workspace_id, slug),

  -- The four superRefine rules from src/content.config.ts:70-96.
  constraint cl_smoked_needs_date    check (status <> 'smoked'  or date_smoked is not null),
  constraint cl_humidor_has_no_date  check (status <> 'humidor' or date_smoked is null),
  constraint cl_smoked_is_singular   check (status <> 'smoked'  or quantity = 1),
  constraint cl_acquired_before_smoked
    check (date_acquired is null or date_smoked is null or date_acquired <= date_smoked)
);

create index cl_cigars_status_idx on public.cl_cigars (workspace_id, status);
create index cl_cigars_smoked_idx on public.cl_cigars (workspace_id, date_smoked desc);
create index cl_cigars_brand_idx  on public.cl_cigars (workspace_id, brand);

-- ── updated_at triggers ───────────────────────────────────────────
create trigger touch_lp_seasons    before update on public.lp_seasons
  for each row execute function public.touch_updated_at();
create trigger touch_lp_selections before update on public.lp_selections
  for each row execute function public.touch_updated_at();
create trigger touch_rl_books      before update on public.rl_books
  for each row execute function public.touch_updated_at();
create trigger touch_cl_cigars     before update on public.cl_cigars
  for each row execute function public.touch_updated_at();
create trigger touch_workspaces    before update on public.workspaces
  for each row execute function public.touch_updated_at();

-- ── Row level security ────────────────────────────────────────────
-- Same four policies on every table. The two join tables have no workspace_id
-- of their own, so they resolve it through their parent season.
do $$
declare t text;
begin
  foreach t in array array[
    'lp_contributors', 'lp_seasons', 'lp_selections',
    'rl_years', 'rl_books',
    'cl_cigars'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for select using (public.can_read(workspace_id))',
      t || '_read', t);
    execute format(
      'create policy %I on public.%I for insert with check (public.can_write(workspace_id))',
      t || '_insert', t);
    execute format(
      'create policy %I on public.%I for update using (public.can_write(workspace_id)) with check (public.can_write(workspace_id))',
      t || '_update', t);
    execute format(
      'create policy %I on public.%I for delete using (public.can_write(workspace_id))',
      t || '_delete', t);
  end loop;
end;
$$;

alter table public.lp_season_contributors enable row level security;

create policy lp_season_contributors_read on public.lp_season_contributors
  for select using (exists (
    select 1 from public.lp_seasons s
    where s.id = season_id and public.can_read(s.workspace_id)
  ));

create policy lp_season_contributors_write on public.lp_season_contributors
  for all using (exists (
    select 1 from public.lp_seasons s
    where s.id = season_id and public.can_write(s.workspace_id)
  )) with check (exists (
    select 1 from public.lp_seasons s
    where s.id = season_id and public.can_write(s.workspace_id)
  ));

-- ── Storage: cigar photos ─────────────────────────────────────────
-- Objects are keyed {workspace_id}/{filename}, so the same can_read/can_write
-- helpers gate them by reading the first path segment.
insert into storage.buckets (id, name, public)
values ('cigar-photos', 'cigar-photos', false)
on conflict (id) do nothing;

create policy cigar_photos_read on storage.objects
  for select using (
    bucket_id = 'cigar-photos'
    and public.can_read(((storage.foldername(name))[1])::uuid)
  );

create policy cigar_photos_insert on storage.objects
  for insert with check (
    bucket_id = 'cigar-photos'
    and public.can_write(((storage.foldername(name))[1])::uuid)
  );

create policy cigar_photos_update on storage.objects
  for update using (
    bucket_id = 'cigar-photos'
    and public.can_write(((storage.foldername(name))[1])::uuid)
  );

create policy cigar_photos_delete on storage.objects
  for delete using (
    bucket_id = 'cigar-photos'
    and public.can_write(((storage.foldername(name))[1])::uuid)
  );
