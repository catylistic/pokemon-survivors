-- Daily Challenge leaderboard for Pokémon Survivors.
-- Paste this whole file into Supabase: SQL Editor -> New query -> Run. Safe to run again.
-- Adds a "daily" date to scores (empty for regular runs) and only accepts daily scores
-- for today's challenge (with a day of slack for time zones).

alter table public.scores add column if not exists daily text
  check (daily is null or daily ~ '^\d{4}-\d{2}-\d{2}$');
create index if not exists scores_daily_score_idx on public.scores (daily, score desc);

create or replace function public.scores_daily_guard() returns trigger
language plpgsql as $$
begin
  if new.daily is not null and new.daily::date not between (now() at time zone 'utc')::date - 1
                                                    and (now() at time zone 'utc')::date + 1 then
    raise exception 'implausible score: not today''s daily challenge' using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists scores_daily_guard on public.scores;
create trigger scores_daily_guard before insert on public.scores
  for each row execute function public.scores_daily_guard();
