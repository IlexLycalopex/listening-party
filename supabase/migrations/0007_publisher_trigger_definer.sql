-- set_publisher_normalised() was SECURITY INVOKER, so it ran with the writer's
-- own rights and needed USAGE on the private `app` schema. Only anon and
-- authenticated had that, so any write by service_role — an Edge Function, a
-- server-side import, a scheduled job — failed with
-- "permission denied for schema app" and took the whole insert down with it.
--
-- A trigger that derives a column from NEW should not depend on who is writing.
-- SECURITY DEFINER makes it work for every writer; search_path stays pinned and
-- it only reads the alias lookup table.

create or replace function public.set_publisher_normalised()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  new.publisher_normalised := app.canonical_publisher(new.publisher);
  return new;
end;
$$;

revoke execute on function public.set_publisher_normalised() from public, anon, authenticated;
