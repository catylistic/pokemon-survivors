-- Leaderboard hardening for Pokémon Survivors.
-- Paste this whole file into Supabase: SQL Editor -> New query -> Run.
-- Safe to run more than once.
--
-- What it adds:
--   1. Believability checks: the score must add up exactly from the run's KOs, time, level,
--      bosses and region (the same formula the game uses), and the numbers must be realistic.
--   2. Rate limiting: one score every 15 seconds per internet address, at most 30 per hour.
--      Addresses are kept in a private table the public key can't read, and only for a day.
--   3. A "hidden" switch: tick it on a row in Table Editor to hide that score from the board.

alter table public.scores add column if not exists shiny  boolean not null default false;
alter table public.scores add column if not exists hidden boolean not null default false;

-- 3. new scores always start visible, and the public can only see visible ones
drop policy if exists "anyone can read scores" on public.scores;
create policy "anyone can read scores" on public.scores
  for select to anon using (not hidden);

drop policy if exists "anyone can add a score" on public.scores;
create policy "anyone can add a score" on public.scores
  for insert to anon with check (not hidden);

revoke update, delete, truncate on public.scores from anon;

-- 2. private log of who posted when (not exposed through the API)
create schema if not exists private;
revoke all on schema private from anon, authenticated;
create table if not exists private.post_log (
  ip text not null,
  at timestamptz not null default now()
);
create index if not exists post_log_ip_at on private.post_log (ip, at desc);
create index if not exists post_log_at    on private.post_log (at);

create or replace function public.scores_guard() returns trigger
language plpgsql security definer set search_path = public, private as $$
declare
  hdrs json := coalesce(nullif(current_setting('request.headers', true), '')::json, '{}'::json);
  v_ip text := coalesce(nullif(hdrs->>'cf-connecting-ip', ''), nullif(split_part(hdrs->>'x-forwarded-for', ',', 1), ''), 'unknown');
  mul numeric := 1 + 0.5 * new.region;
  adds_up boolean := false;
begin
  -- 2. rate limit (skipped if the address can't be seen, so players are never lumped together)
  if v_ip <> 'unknown' then
    if exists (select 1 from private.post_log where ip = v_ip and at > now() - interval '15 seconds') then
      raise exception 'rate limited: please wait a few seconds' using errcode = 'P0001';
    end if;
    if (select count(*) from private.post_log where ip = v_ip and at > now() - interval '1 hour') >= 30 then
      raise exception 'rate limited: too many scores this hour' using errcode = 'P0001';
    end if;
    insert into private.post_log (ip) values (v_ip);
    delete from private.post_log where at < now() - interval '1 day';
  end if;

  -- 1. the score has to add up: (KOs*10 + seconds*5 + level*100 + bosses*2500 + win bonus) x region multiplier
  for b in 0..5 loop
    if round((new.kills*10 + new.t*5 + new.level*100 + b*2500 + case when new.won then 25000 else 0 end) * mul) = new.score then
      adds_up := true; exit;
    end if;
  end loop;
  if not adds_up                         then raise exception 'implausible score: does not add up' using errcode = 'P0001'; end if;
  -- ...and the numbers have to be realistic
  if new.t > 3600                        then raise exception 'implausible score: run too long' using errcode = 'P0001'; end if;
  if new.won and new.t < 900             then raise exception 'implausible score: won too early' using errcode = 'P0001'; end if;
  if new.kills > new.t * 40 + 50         then raise exception 'implausible score: too many KOs' using errcode = 'P0001'; end if;
  if new.level > new.t / 4 + 25          then raise exception 'implausible score: level too high' using errcode = 'P0001'; end if;

  new.created_at := now();
  new.hidden := false;
  return new;
end $$;

drop trigger if exists scores_guard on public.scores;
create trigger scores_guard before insert on public.scores
  for each row execute function public.scores_guard();
