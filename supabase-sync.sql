-- Cloud save (sync progress between devices) for Pokémon Survivors.
-- Paste this whole file into Supabase: SQL Editor -> New query -> Run ("with RLS" if asked).
-- Run supabase-hardening.sql first (this reuses its private rate-limit log). Safe to run again.
--
-- Each save is stored under a random 16-character sync code. The public key can't read or
-- list the table at all; it can only call the two functions below, which save or load ONE
-- save by its exact code. With 32^16 possible codes, guessing someone else's is hopeless.

create table if not exists public.saves (
  code       text primary key check (code ~ '^[A-HJ-NP-Z2-9]{16}$'),
  data       jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.saves enable row level security;   -- no policies: no direct access
revoke all on public.saves from anon, authenticated;

create or replace function public.save_progress(p_code text, p_data jsonb) returns void
language plpgsql security definer set search_path = public, private as $$
declare
  hdrs json := coalesce(nullif(current_setting('request.headers', true), '')::json, '{}'::json);
  v_ip text := coalesce(nullif(hdrs->>'cf-connecting-ip', ''), nullif(split_part(hdrs->>'x-forwarded-for', ',', 1), ''), 'unknown');
begin
  if p_code is null or p_code !~ '^[A-HJ-NP-Z2-9]{16}$' then raise exception 'bad sync code' using errcode = 'P0001'; end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'bad save' using errcode = 'P0001'; end if;
  if octet_length(p_data::text) > 100000 then raise exception 'save too large' using errcode = 'P0001'; end if;
  -- at most 120 saves an hour from one internet address
  if v_ip <> 'unknown' then
    if (select count(*) from private.post_log where ip = 'save:' || v_ip and at > now() - interval '1 hour') >= 120 then
      raise exception 'rate limited: too many saves' using errcode = 'P0001';
    end if;
    insert into private.post_log (ip) values ('save:' || v_ip);
    delete from private.post_log where at < now() - interval '1 day';
  end if;
  insert into public.saves (code, data, updated_at) values (p_code, p_data, now())
    on conflict (code) do update set data = excluded.data, updated_at = now();
end $$;

create or replace function public.load_progress(p_code text) returns jsonb
language sql stable security definer set search_path = public as $$
  select data from public.saves where code = p_code;
$$;

revoke all on function public.save_progress(text, jsonb) from public;
revoke all on function public.load_progress(text) from public;
grant execute on function public.save_progress(text, jsonb) to anon;
grant execute on function public.load_progress(text) to anon;
