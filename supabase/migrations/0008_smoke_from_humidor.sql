-- Moving a cigar out of the humidor and into the log.
--
-- This is the one write in the app that is not a single statement. A humidor
-- entry carries a quantity, so smoking one of three has to insert a smoked
-- entry *and* leave two behind. Done as two calls from the app, a failure
-- between them leaves either a cigar smoked twice or one that was never
-- deducted — and the second is silent.
--
-- SECURITY INVOKER on purpose. This function is here for atomicity, not for
-- privilege: it runs as the caller, so the same RLS policies decide what may be
-- read and written as would apply to the statements individually. A viewer
-- calling it directly gets nothing, exactly as they would from PostgREST.
create function public.smoke_from_humidor(
  p_cigar_id      uuid,
  p_slug          text,
  p_date_smoked   date,
  p_smoked_at     text default '',
  p_pairing       text default '',
  p_note          text default '',
  p_rating        numeric default null,
  p_tasting_notes text default ''
) returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  src    public.cl_cigars%rowtype;
  new_id uuid;
begin
  -- FOR UPDATE so two people smoking from the same box at the same moment
  -- queue rather than both reading a quantity of 3 and both writing 2.
  select * into src from public.cl_cigars where id = p_cigar_id for update;

  if not found then
    raise exception 'that cigar is not in this humidor' using errcode = 'no_data_found';
  end if;
  if src.status <> 'humidor' then
    raise exception 'that cigar has already been smoked' using errcode = 'check_violation';
  end if;

  if src.quantity > 1 then
    -- Split one off the stack: the rest stay resting, and the smoked one is a
    -- new entry that needs a slug of its own.
    insert into public.cl_cigars (
      workspace_id, slug, status, quantity, name, brand, vitola, wrapper,
      length_text, ring_gauge, country, strength, bought_at, smoked_at,
      date_acquired, date_smoked, price_text, price_gbp, price_approximate,
      rating, pairing, note, tasting_notes
    ) values (
      src.workspace_id, p_slug, 'smoked', 1, src.name, src.brand, src.vitola,
      src.wrapper, src.length_text, src.ring_gauge, src.country, src.strength,
      src.bought_at, coalesce(p_smoked_at, ''), src.date_acquired, p_date_smoked,
      src.price_text, src.price_gbp, src.price_approximate,
      p_rating, coalesce(p_pairing, ''), coalesce(p_note, ''),
      coalesce(p_tasting_notes, '')
    )
    returning id into new_id;

    update public.cl_cigars set quantity = quantity - 1 where id = src.id;
  else
    -- The last one becomes the smoked entry in place, keeping its id and its
    -- URL — which is what the single table was for.
    update public.cl_cigars
       set status        = 'smoked',
           quantity      = 1,
           date_smoked   = p_date_smoked,
           smoked_at     = coalesce(p_smoked_at, ''),
           rating        = p_rating,
           pairing       = coalesce(p_pairing, ''),
           note          = coalesce(p_note, ''),
           tasting_notes = coalesce(p_tasting_notes, '')
     where id = src.id
    returning id into new_id;
  end if;

  return new_id;
end;
$$;

-- Anonymous visitors have no business calling this even though RLS would stop
-- it doing anything; keeping it off the public surface saves the argument.
revoke execute on function public.smoke_from_humidor(uuid, text, date, text, text, text, numeric, text) from public, anon;
grant execute on function public.smoke_from_humidor(uuid, text, date, text, text, text, numeric, text) to authenticated;
