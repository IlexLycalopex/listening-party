-- Supabase ships default privileges that grant EXECUTE on new functions in
-- `public` to anon, authenticated and service_role. The `revoke ... from public`
-- in 0001 only dropped the PUBLIC pseudo-role grant, leaving the explicit anon
-- grant in place — so accept_invite stayed reachable at /rest/v1/rpc without a
-- session.
--
-- Calling it signed-out already failed closed (auth.uid() is null, so it raises
-- before it ever looks the token up), but an unauthenticated endpoint that
-- takes an invite token is surface worth not having.

revoke execute on function public.accept_invite(text) from anon;
