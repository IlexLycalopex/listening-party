-- Hardening pass, driven by `get_advisors(type: 'security')`.
--
-- The access helpers have to be SECURITY DEFINER (see 0001) and RLS policies
-- evaluate as the calling role, so anon and authenticated need EXECUTE on them.
-- Left in `public`, that combination also publishes them as callable endpoints
-- at /rest/v1/rpc/*. Moving them to a schema PostgREST does not expose keeps the
-- grants the policies need while removing the API surface.
--
-- accept_invite stays in public on purpose: it is an RPC the app calls.

create schema if not exists app;
grant usage on schema app to anon, authenticated;

-- ── Helpers, relocated ────────────────────────────────────────────
create function app.workspace_role(ws uuid)
returns public.member_role
language sql stable security definer set search_path = public, pg_temp as $$
  select role from public.workspace_members
  where workspace_id = ws and user_id = auth.uid()
$$;

create function app.can_read(ws uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.workspaces w
    where w.id = ws and w.visibility in ('public', 'unlisted')
  ) or app.workspace_role(ws) is not null
$$;

create function app.can_write(ws uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(app.workspace_role(ws) in ('owner', 'editor'), false)
$$;

create function app.is_owner(ws uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(app.workspace_role(ws) = 'owner', false)
$$;

create function app.shares_workspace_with(other uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
    from public.workspace_members mine
    join public.workspace_members theirs on theirs.workspace_id = mine.workspace_id
    where mine.user_id = auth.uid() and theirs.user_id = other
  )
$$;

revoke execute on all functions in schema app from public;
grant execute on function
  app.workspace_role(uuid), app.can_read(uuid), app.can_write(uuid),
  app.is_owner(uuid), app.shares_workspace_with(uuid)
to anon, authenticated;

-- ── Repoint every policy at the new schema ────────────────────────
drop policy profiles_read          on public.profiles;
drop policy workspaces_read        on public.workspaces;
drop policy workspaces_update      on public.workspaces;
drop policy workspaces_delete      on public.workspaces;
drop policy members_read           on public.workspace_members;
drop policy members_manage         on public.workspace_members;
drop policy invites_read           on public.workspace_invites;
drop policy invites_manage         on public.workspace_invites;
drop policy lp_season_contributors_read  on public.lp_season_contributors;
drop policy lp_season_contributors_write on public.lp_season_contributors;
drop policy cigar_photos_read      on storage.objects;
drop policy cigar_photos_insert    on storage.objects;
drop policy cigar_photos_update    on storage.objects;
drop policy cigar_photos_delete    on storage.objects;

do $$
declare t text;
begin
  foreach t in array array[
    'lp_contributors', 'lp_seasons', 'lp_selections',
    'rl_years', 'rl_books', 'cl_cigars'
  ] loop
    execute format('drop policy %I on public.%I', t || '_read', t);
    execute format('drop policy %I on public.%I', t || '_insert', t);
    execute format('drop policy %I on public.%I', t || '_update', t);
    execute format('drop policy %I on public.%I', t || '_delete', t);
  end loop;
end;
$$;

drop function public.workspace_role(uuid);
drop function public.can_read(uuid);
drop function public.can_write(uuid);
drop function public.is_owner(uuid);
drop function public.shares_workspace_with(uuid);

create policy profiles_read on public.profiles
  for select using (id = auth.uid() or app.shares_workspace_with(id));

create policy workspaces_read on public.workspaces
  for select using (
    visibility in ('public', 'unlisted') or app.workspace_role(id) is not null
  );
create policy workspaces_update on public.workspaces
  for update using (app.is_owner(id)) with check (app.is_owner(id));
create policy workspaces_delete on public.workspaces
  for delete using (app.is_owner(id));

create policy members_read on public.workspace_members
  for select using (user_id = auth.uid() or app.can_read(workspace_id));
create policy members_manage on public.workspace_members
  for all using (app.is_owner(workspace_id)) with check (app.is_owner(workspace_id));

create policy invites_read on public.workspace_invites
  for select using (
    app.is_owner(workspace_id)
    or email = (select p.email from public.profiles p where p.id = auth.uid())
  );
create policy invites_manage on public.workspace_invites
  for all using (app.is_owner(workspace_id))
          with check (app.is_owner(workspace_id) and invited_by = auth.uid());

do $$
declare t text;
begin
  foreach t in array array[
    'lp_contributors', 'lp_seasons', 'lp_selections',
    'rl_years', 'rl_books', 'cl_cigars'
  ] loop
    execute format(
      'create policy %I on public.%I for select using (app.can_read(workspace_id))',
      t || '_read', t);
    execute format(
      'create policy %I on public.%I for insert with check (app.can_write(workspace_id))',
      t || '_insert', t);
    execute format(
      'create policy %I on public.%I for update using (app.can_write(workspace_id)) with check (app.can_write(workspace_id))',
      t || '_update', t);
    execute format(
      'create policy %I on public.%I for delete using (app.can_write(workspace_id))',
      t || '_delete', t);
  end loop;
end;
$$;

create policy lp_season_contributors_read on public.lp_season_contributors
  for select using (exists (
    select 1 from public.lp_seasons s
    where s.id = season_id and app.can_read(s.workspace_id)
  ));

create policy lp_season_contributors_write on public.lp_season_contributors
  for all using (exists (
    select 1 from public.lp_seasons s
    where s.id = season_id and app.can_write(s.workspace_id)
  )) with check (exists (
    select 1 from public.lp_seasons s
    where s.id = season_id and app.can_write(s.workspace_id)
  ));

create policy cigar_photos_read on storage.objects
  for select using (
    bucket_id = 'cigar-photos' and app.can_read(((storage.foldername(name))[1])::uuid)
  );
create policy cigar_photos_insert on storage.objects
  for insert with check (
    bucket_id = 'cigar-photos' and app.can_write(((storage.foldername(name))[1])::uuid)
  );
create policy cigar_photos_update on storage.objects
  for update using (
    bucket_id = 'cigar-photos' and app.can_write(((storage.foldername(name))[1])::uuid)
  );
create policy cigar_photos_delete on storage.objects
  for delete using (
    bucket_id = 'cigar-photos' and app.can_write(((storage.foldername(name))[1])::uuid)
  );

-- ── Remaining advisor findings ────────────────────────────────────
-- Trigger functions are only ever reached through their triggers; nothing
-- should be able to call them over the API.
revoke execute on function public.handle_new_user()      from public, anon, authenticated;
revoke execute on function public.handle_new_workspace() from public, anon, authenticated;
revoke execute on function public.guard_last_owner()     from public, anon, authenticated;

-- Not SECURITY DEFINER, so this is hygiene rather than a hole, but an unpinned
-- search_path in a trigger function is worth closing anyway.
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
revoke execute on function public.touch_updated_at() from public, anon, authenticated;

alter extension citext set schema extensions;
