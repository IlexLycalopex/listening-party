-- Publisher normalisation, moved from the reading list's build script into the
-- database so it happens on write rather than depending on whoever inserted the
-- row remembering to do it.
--
-- Open Library returns the publisher of whichever edition matched, so the same
-- imprint arrives spelled many ways ("Charco" / "Charco Press", "HARPERCOLLINS"
-- / "Harper"). Distinct imprints are kept; corporate-level duplicates merge. A
-- null canonical means the value is not a publisher at all (distributors,
-- library binders, Open Library noise) and should group as nothing.
--
-- Ported from readinglist/scripts/publisher-aliases.js.

create table public.rl_publisher_aliases (
  alias     text primary key,
  canonical text
);

insert into public.rl_publisher_aliases (alias, canonical) values
  ('penguin', 'Penguin Random House'),
  ('penguin books', 'Penguin Random House'),
  ('penguin press', 'Penguin Random House'),
  ('penguin publishing group', 'Penguin Random House'),
  ('penguin group usa', 'Penguin Random House'),
  ('penguin random house audio', 'Penguin Random House'),
  ('random house', 'Penguin Random House'),
  ('random house.', 'Penguin Random House'),
  ('random house publishing group', 'Penguin Random House'),
  ('random house lcc us', 'Penguin Random House'),
  ('random house large print', 'Penguin Random House'),
  ('random house audio', 'Penguin Random House'),
  ('harper', 'HarperCollins'),
  ('harpercollins', 'HarperCollins'),
  ('harpercollins publishers', 'HarperCollins'),
  ('harpercollins publishers and blackstone audio', 'HarperCollins'),
  ('harper paperbacks', 'HarperCollins'),
  ('harperperennial', 'HarperCollins'),
  ('harperluxe', 'HarperCollins'),
  ('charco', 'Charco Press'),
  ('fitzcarraldo', 'Fitzcarraldo Editions'),
  ('aberdeenuniversity press', 'Aberdeen University Press'),
  ('canongate', 'Canongate'),
  ('canongate books', 'Canongate'),
  ('bloomsbury publishing', 'Bloomsbury'),
  ('everyman publishers', 'Everyman'),
  ('faber and faber', 'Faber & Faber'),
  ('simon and schuster', 'Simon & Schuster'),
  ('w. w. norton & company', 'W. W. Norton'),
  ('norton & company limited, w. w.', 'W. W. Norton'),
  ('murray press, john', 'John Murray'),
  ('vintage books', 'Vintage'),
  ('vintage books usa', 'Vintage'),
  ('vintage (rand)', 'Vintage'),
  ('knopf doubleday publishing group', 'Knopf'),
  ('doubleday canada', 'Doubleday'),
  ('st. martin''s griffin', 'St. Martin''s Press'),
  ('dark horse books', 'Dark Horse Comics'),
  ('tor.com', 'Tor'),
  ('paidos', 'Paidós'),
  ('blackstone audio', 'Blackstone Publishing'),
  ('little, brown book group', 'Little, Brown'),
  ('macmillan audio', 'Macmillan'),
  ('orion mass market paperback', 'Orion'),
  ('atlantic monthly pr', 'Atlantic Monthly Press'),
  ('turner publicaciones s.l.', 'Turner'),
  ('signet, new american library', 'Signet'),
  ('holt rinehart and winston (reinhart editions)', 'Holt, Rinehart and Winston'),
  ('basic books, a member of the perseus book group', 'Basic Books'),
  ('vertebrate graphics', 'Vertebrate Publishing'),
  ('northland pub', 'Northland Publishing'),
  ('center point pub', 'Center Point Publishing'),
  ('generic', null),
  ('book club', null),
  ('imusti', null),
  ('tandem library', null),
  ('contemporary french fiction', null),
  ('indypublish.com', null),
  ('galaxy plus', null),
  ('distribooks', null),
  ('ye ren/tsai fong books', null),
  ('qi ming chu ban shi ye gu fen you xian gong si', null);

alter table public.rl_publisher_aliases enable row level security;

-- Reference data: everyone reads it, nobody writes it through the API.
create policy rl_publisher_aliases_read on public.rl_publisher_aliases
  for select using (true);

grant select on public.rl_publisher_aliases to anon, authenticated;

-- Mirrors canonicalPublisher(): collapse whitespace, drop a trailing corporate
-- suffix, then map known variants.
create function app.canonical_publisher(raw text)
returns text
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  clean  text;
  mapped text;
begin
  if raw is null or btrim(raw) = '' then
    return '';
  end if;

  clean := regexp_replace(btrim(raw), '\s+', ' ', 'g');
  clean := regexp_replace(clean, ',?\s+(limited|ltd\.?|llc\.?|inc\.?)$', '', 'i');

  if exists (select 1 from public.rl_publisher_aliases a where a.alias = lower(clean)) then
    select a.canonical into mapped from public.rl_publisher_aliases a where a.alias = lower(clean);
    return coalesce(mapped, '');
  end if;

  return clean;
end;
$$;

revoke execute on function app.canonical_publisher(text) from public;
grant execute on function app.canonical_publisher(text) to anon, authenticated;

create function public.set_publisher_normalised()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.publisher_normalised := app.canonical_publisher(new.publisher);
  return new;
end;
$$;

revoke execute on function public.set_publisher_normalised() from public, anon, authenticated;

create trigger rl_books_normalise_publisher
  before insert or update of publisher on public.rl_books
  for each row execute function public.set_publisher_normalised();

-- Backfill anything imported before the trigger existed.
update public.rl_books
set publisher_normalised = app.canonical_publisher(publisher)
where publisher_normalised is distinct from app.canonical_publisher(publisher);
