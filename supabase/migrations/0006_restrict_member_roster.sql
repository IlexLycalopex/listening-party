-- The members_read policy allowed anyone who could *read* a workspace to read
-- its roster. On a public workspace that meant the world could enumerate the
-- members and their user ids.
--
-- The intent was only ever "members can see who else is in here", so gate it on
-- membership rather than readability. Profiles were never exposed this way
-- (profiles_read already requires a shared workspace), but the user ids and
-- role assignments were.
--
-- This also removed the footgun behind a real bug: resolveWorkspace() in the
-- app read this table without filtering by user, trusting the policy to narrow
-- it, and so reported `owner` to anonymous visitors of a public workspace.

drop policy members_read on public.workspace_members;

create policy members_read on public.workspace_members
  for select using (
    user_id = auth.uid() or app.workspace_role(workspace_id) is not null
  );
