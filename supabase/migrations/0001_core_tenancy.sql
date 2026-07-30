-- Core tenancy for Grackles.
--
-- Every app (listening party, reading list, cigar lounge) hangs off the same
-- workspace/membership model, so access control is written once and reused.
-- A "workspace" is one instance of one app: Jamie's cigar lounge and Rob's are
-- two workspaces of app 'cigar-lounge', each with their own members.

create extension if not exists citext;

-- ── Enums ─────────────────────────────────────────────────────────
create type public.app_slug    as enum ('listening-party', 'reading-list', 'cigar-lounge');
create type public.member_role as enum ('owner', 'editor', 'viewer');
create type public.visibility  as enum ('private', 'unlisted', 'public');

-- ── Profiles ──────────────────────────────────────────────────────
-- Mirrors auth.users into a table the app is allowed to read and join against.
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  email        citext not null,
  display_name text not null default '',
  avatar_url   text,
  created_at   timestamptz not null default now()
);

-- The auth admin role owns auth.users and has no rights in `public`, so the
-- trigger has to be SECURITY DEFINER to write the profile row.
create function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── Workspaces ────────────────────────────────────────────────────
create table public.workspaces (
  id          uuid primary key default gen_random_uuid(),
  app         public.app_slug not null,
  slug        text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name        text not null check (name <> ''),
  description text not null default '',
  visibility  public.visibility not null default 'private',
  owner_id    uuid not null references public.profiles(id) on delete restrict,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- Slugs only need to be unique within an app, so /reading/jamie and
  -- /cigars/jamie can coexist.
  unique (app, slug)
);

create table public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  role         public.member_role not null,
  created_at   timestamptz not null default now(),
  primary key (workspace_id, user_id)
);
create index workspace_members_user_idx on public.workspace_members (user_id);

create table public.workspace_invites (
  id           uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  email        citext not null,
  role         public.member_role not null default 'viewer',
  -- Two v4 UUIDs of CSPRNG entropy, no pgcrypto dependency.
  token        text not null unique
                 default replace(gen_random_uuid()::text, '-', '')
                      || replace(gen_random_uuid()::text, '-', ''),
  invited_by   uuid not null references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '14 days',
  accepted_at  timestamptz,
  accepted_by  uuid references public.profiles(id) on delete set null
);

-- One live invite per email per workspace; accepted ones stay as history.
create unique index workspace_invites_pending_idx
  on public.workspace_invites (workspace_id, email)
  where accepted_at is null;

-- ── Access helpers ────────────────────────────────────────────────
-- SECURITY DEFINER is load-bearing here, not incidental. A policy on
-- workspace_members that queries workspace_members recurses forever; reading
-- membership through a definer function bypasses RLS on that lookup and breaks
-- the cycle. search_path is pinned so a caller cannot shadow the table with
-- one of their own in a schema they control.

create function public.workspace_role(ws uuid)
returns public.member_role
language sql stable security definer set search_path = public, pg_temp as $$
  select role from public.workspace_members
  where workspace_id = ws and user_id = auth.uid()
$$;

create function public.can_read(ws uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.workspaces w
    where w.id = ws and w.visibility in ('public', 'unlisted')
  ) or public.workspace_role(ws) is not null
$$;

create function public.can_write(ws uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(public.workspace_role(ws) in ('owner', 'editor'), false)
$$;

create function public.is_owner(ws uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(public.workspace_role(ws) = 'owner', false)
$$;

-- Used by the profiles policy, for the same anti-recursion reason.
create function public.shares_workspace_with(other uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
    from public.workspace_members mine
    join public.workspace_members theirs on theirs.workspace_id = mine.workspace_id
    where mine.user_id = auth.uid() and theirs.user_id = other
  )
$$;

-- ── Ownership invariants ──────────────────────────────────────────
-- The creator becomes a member immediately, otherwise is_owner() would be
-- false for their own brand-new workspace and they could not edit it.
create function public.handle_new_workspace()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.workspace_members (workspace_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (workspace_id, user_id) do update set role = 'owner';
  return new;
end;
$$;

create trigger on_workspace_created
  after insert on public.workspaces
  for each row execute function public.handle_new_workspace();

-- A workspace must never be left ownerless. Deferred so that handing ownership
-- over in a single transaction (demote me, promote you) still works.
create function public.guard_last_owner()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  ws uuid := coalesce(old.workspace_id, new.workspace_id);
begin
  -- The workspace itself is going away; the cascade is allowed to empty it.
  if not exists (select 1 from public.workspaces where id = ws) then
    return coalesce(new, old);
  end if;
  if not exists (
    select 1 from public.workspace_members
    where workspace_id = ws and role = 'owner'
  ) then
    raise exception 'workspace % must keep at least one owner', ws;
  end if;
  return coalesce(new, old);
end;
$$;

create constraint trigger workspace_members_keep_owner
  after update or delete on public.workspace_members
  deferrable initially deferred
  for each row execute function public.guard_last_owner();

-- ── Row level security ────────────────────────────────────────────
alter table public.profiles          enable row level security;
alter table public.workspaces        enable row level security;
alter table public.workspace_members enable row level security;
alter table public.workspace_invites enable row level security;

-- Profiles: yourself, plus anyone you share a workspace with (so collaborator
-- names and avatars render).
create policy profiles_read on public.profiles
  for select using (id = auth.uid() or public.shares_workspace_with(id));

create policy profiles_update_self on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());
-- No insert policy: rows arrive only via the definer trigger on auth.users.

create policy workspaces_read on public.workspaces
  for select using (
    visibility in ('public', 'unlisted') or public.workspace_role(id) is not null
  );

create policy workspaces_insert on public.workspaces
  for insert with check (owner_id = auth.uid());

create policy workspaces_update on public.workspaces
  for update using (public.is_owner(id)) with check (public.is_owner(id));

create policy workspaces_delete on public.workspaces
  for delete using (public.is_owner(id));

-- Members can see the roster of any workspace they can read; only owners can
-- change it.
create policy members_read on public.workspace_members
  for select using (user_id = auth.uid() or public.can_read(workspace_id));

create policy members_manage on public.workspace_members
  for all using (public.is_owner(workspace_id))
          with check (public.is_owner(workspace_id));

-- Invites are visible to the workspace owner and to their recipient. The token
-- is never needed client-side: acceptance goes through accept_invite().
create policy invites_read on public.workspace_invites
  for select using (
    public.is_owner(workspace_id)
    or email = (select p.email from public.profiles p where p.id = auth.uid())
  );

create policy invites_manage on public.workspace_invites
  for all using (public.is_owner(workspace_id))
          with check (public.is_owner(workspace_id) and invited_by = auth.uid());

-- ── Invite acceptance ─────────────────────────────────────────────
create function public.accept_invite(invite_token text)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  inv      public.workspace_invites;
  me       uuid := auth.uid();
  my_email citext;
begin
  if me is null then
    raise exception 'you must be signed in to accept an invite';
  end if;
  select email into my_email from public.profiles where id = me;

  select * into inv from public.workspace_invites
  where token = invite_token and accepted_at is null and expires_at > now();

  if not found then
    raise exception 'that invite is invalid, expired, or already used';
  end if;
  if inv.email <> my_email then
    raise exception 'that invite was issued to a different email address';
  end if;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (inv.workspace_id, me, inv.role)
  on conflict (workspace_id, user_id) do nothing;

  update public.workspace_invites
  set accepted_at = now(), accepted_by = me
  where id = inv.id;

  return inv.workspace_id;
end;
$$;

-- ── Function grants ───────────────────────────────────────────────
-- Helpers are readable by both roles (anon needs can_read for public
-- workspaces); the mutating RPC is for signed-in users only.
revoke execute on function
  public.workspace_role(uuid), public.can_read(uuid), public.can_write(uuid),
  public.is_owner(uuid), public.shares_workspace_with(uuid),
  public.accept_invite(text)
from public;

grant execute on function
  public.workspace_role(uuid), public.can_read(uuid), public.can_write(uuid),
  public.is_owner(uuid), public.shares_workspace_with(uuid)
to anon, authenticated;

grant execute on function public.accept_invite(text) to authenticated;
