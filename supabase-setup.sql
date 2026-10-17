-- World leaderboard for Pokémon Survivors.
-- Paste this whole file into Supabase: SQL Editor -> New query -> Run.
-- Anyone can read scores and add new ones; nobody can edit or delete them
-- through the public key (you can still delete rows from the Supabase dashboard).

create table if not exists public.scores (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  name       text    not null check (char_length(name) between 1 and 14),
  region     smallint not null check (region between 0 and 8),
  starter    text    not null check (char_length(starter) <= 20),
  mon_id     int     not null check (mon_id between 1 and 1100),
  mon        text    not null check (char_length(mon) <= 20),
  score      int     not null check (score between 0 and 20000000),
  t          int     not null check (t between 0 and 7200),
  level      int     not null check (level between 1 and 500),
  kills      int     not null check (kills between 0 and 2000000),
  won        boolean not null default false
);

create index if not exists scores_score_idx        on public.scores (score desc);
create index if not exists scores_region_score_idx on public.scores (region, score desc);

alter table public.scores enable row level security;

drop policy if exists "anyone can read scores" on public.scores;
create policy "anyone can read scores" on public.scores
  for select to anon using (true);

drop policy if exists "anyone can add a score" on public.scores;
create policy "anyone can add a score" on public.scores
  for insert to anon with check (true);

grant select, insert on public.scores to anon;
