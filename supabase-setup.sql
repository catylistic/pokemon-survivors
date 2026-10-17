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

-- Trainer-name filter: the same check the game runs (see NameFilter in index.html).
-- Word lists are ROT13-encoded; the name is ROT13-encoded too before matching.
create or replace function public.name_ok(n text) returns boolean
language plpgsql immutable as $$
declare
  rot13 constant text := 'nopqrstuvwxyzabcdefghijklm';
  abc   constant text := 'abcdefghijklmnopqrstuvwxyz';
  s text; r text; tok text;
begin
  -- lowercase and undo leetspeak (0->o, 1->i, 3->e, 4->a, 5->s, 7->t, 8->b, 9->g ...)
  s := translate(lower(n), '01!|34@5$7+896', 'oiiieaassttbgg');
  -- 1. short words only count as a whole word
  foreach tok in array regexp_split_to_array(s, '[^a-z]+') loop
    if translate(tok, abc, rot13) = any (array['nff','nefr','phz','nany','nahf','fcvp','xlf','gvg','ubr']) then
      return false;
    end if;
  end loop;
  -- 2. letters only, encoded, with harmless words that contain bad ones removed
  r := translate(regexp_replace(s, '[^a-z]', '', 'g'), abc, rot13);
  r := regexp_replace(r, 'pbpxngbb|crnpbpx|unapbpx|qvpxraf|fphagubecr|tencr|qencr|fpencr|gencrmr|cnencrg|gbecrqb|crqbzrgre|pbsntevthf|funecrqb|frkgnag|rffrk|fhffrk|avtrevn|avtre', '', 'g');
  if r ~ 'shpx|shx|spx|fuvg|ovgpu|ogpu|phag|qvpx|pbpx|chffl|cravf|intvan|nffubyr|nffjvcr|qhzonff|wnpxnff|onfgneq|fyhg|juber|jnax|gjng|obbo|gvgf|gvggl|cbea|ahqr|anxrq|encr|qvyqb|ubeal|zvys|avttre|avttn|puvax|xvxr|snt|qlxr|genaal|ergneq|anmv|uvgyre|xxx|wvmm|betnfz|uragnv|crqb|zbyrfg|frk' then
    return false;
  end if;
  -- 3. stretched letters squashed (fuuuck -> fuck)
  r := regexp_replace(r, '(.)\1+', '\1', 'g');
  if r ~ 'shpx|shx|spx|fuvg|ovgpu|ogpu|phag|qvpx|pbpx|chfl|cravf|intvan|nfubyr|nfjvcr|qhzonf|wnpxnf|onfgneq|fyhg|juber|jnax|gjng|gvgf|gvgl|cbea|ahqr|anxrq|encr|qvyqb|ubeal|zvys|avtre|avtn|puvax|xvxr|snt|qlxr|genal|ergneq|anmv|uvgyre|wvm|betnfz|uragnv|crqb|zbyrfg|frk' then
    return false;
  end if;
  return true;
end $$;

alter table public.scores drop constraint if exists scores_name_ok;
alter table public.scores add constraint scores_name_ok check (public.name_ok(name));

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
-- belt and braces: the policies above already block edits and deletes
revoke update, delete, truncate on public.scores from anon;
