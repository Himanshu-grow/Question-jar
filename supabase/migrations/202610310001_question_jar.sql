create extension if not exists pgcrypto;
create table if not exists public.game_rooms (
 id uuid primary key default gen_random_uuid(), code text not null unique,
 player1_name text not null, player2_name text, player1_token_hash text not null, player2_token_hash text,
 category text not null default 'Love & Romance', question text,
 round_no integer not null default 0, status text not null default 'waiting' check(status in ('waiting','playing','revealed')),
 deadline timestamptz, answer1 text, answer2 text, submitted1 boolean not null default false, submitted2 boolean not null default false,
 analysis jsonb, vote1 boolean not null default false, vote2 boolean not null default false,
 used_questions text[] not null default '{}', created_at timestamptz not null default now()
);
create index if not exists game_rooms_code_idx on public.game_rooms(code);
alter table public.game_rooms enable row level security;
-- Only a stripped mirror is visible to Realtime. Answer fields remain RPC-only.
create table if not exists public.room_events(code text primary key,player1_name text not null,player2_name text,category text not null,question text,round_no integer not null,status text not null,deadline timestamptz,submitted1 boolean not null,submitted2 boolean not null,analysis jsonb,vote1 boolean not null,vote2 boolean not null);
alter table public.room_events enable row level security;
create policy "room events readable" on public.room_events for select to anon,authenticated using(true);
grant select on public.room_events to anon,authenticated;
revoke all on public.game_rooms from anon,authenticated;

create or replace function public.room_state(p_code text,p_token text) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r game_rooms; s int; revealed boolean;
begin
 select * into r from game_rooms where code=upper(p_code); if not found then raise exception 'Room not found'; end if;
 if digest(p_token,'sha256')::text=r.player1_token_hash then s:=1; elsif r.player2_token_hash is not null and digest(p_token,'sha256')::text=r.player2_token_hash then s:=2; else raise exception 'Invalid room invitation'; end if;
 revealed:=r.status='revealed';
 return jsonb_build_object('code',r.code,'players',jsonb_build_array(jsonb_build_object('name',r.player1_name),case when r.player2_name is not null then jsonb_build_object('name',r.player2_name) else null end),'category',r.category,'question',r.question,'round_no',r.round_no,'status',r.status,'deadline',r.deadline,'submitted_by_me',case when s=1 then r.submitted1 else r.submitted2 end,'other_submitted',case when s=1 then r.submitted2 else r.submitted1 end,'my_answer',case when s=1 then r.answer1 else r.answer2 end,'answer_one',case when revealed then r.answer1 else null end,'answer_two',case when revealed then r.answer2 else null end,'analysis',case when revealed then r.analysis else null end,'next_votes',((r.vote1)::int+(r.vote2)::int),'voted_by_me',case when s=1 then r.vote1 else r.vote2 end);
end $$;
create or replace function public.create_room(p_name text,p_category text) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare c text; t text:=encode(gen_random_bytes(32),'hex');
begin c:=upper(substr(encode(gen_random_bytes(8),'hex'),1,6)); insert into game_rooms(code,player1_name,player1_token_hash,category) values(c,left(trim(p_name),28),digest(t,'sha256')::text,p_category); return jsonb_build_object('code',c,'token',t); end $$;
create or replace function public.join_room(p_code text,p_name text) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare t text:=encode(gen_random_bytes(32),'hex');
begin update game_rooms set player2_name=left(trim(p_name),28),player2_token_hash=digest(t,'sha256')::text where code=upper(p_code) and player2_name is null and status='waiting'; if not found then raise exception 'This room is unavailable or already has two players'; end if; return jsonb_build_object('token',t); end $$;
create or replace function public.get_room_state(p_code text,p_token text) returns jsonb language sql security definer set search_path=public,extensions as $$ select room_state(p_code,p_token) $$;
create or replace function public.start_round(p_code text,p_token text,p_category text,p_question text) returns void language plpgsql security definer set search_path=public,extensions as $$
declare r game_rooms;
begin select * into r from game_rooms where code=upper(p_code) for update; perform room_state(p_code,p_token); if r.player2_name is null then raise exception 'Waiting for the other player'; end if; if r.status<>'waiting' then raise exception 'Room is not ready for a new round'; end if; update game_rooms set category=p_category,question=p_question,round_no=round_no+1,status='playing',deadline=now()+interval '90 seconds',answer1=null,answer2=null,submitted1=false,submitted2=false,analysis=null,vote1=false,vote2=false,used_questions=case when cardinality(used_questions)>0 and (select count(*) from unnest(used_questions) x where x=any(array[p_question]))=1 then '{}' else used_questions end||p_question where id=r.id; end $$;
create or replace function public.submit_answer(p_code text,p_token text,p_answer text) returns void language plpgsql security definer set search_path=public,extensions as $$
declare r game_rooms; s int; a text;
begin select * into r from game_rooms where code=upper(p_code) for update; perform room_state(p_code,p_token); s:=case when digest(p_token,'sha256')::text=r.player1_token_hash then 1 else 2 end; if r.status<>'playing' then raise exception 'Round is no longer open'; end if; a:=left(coalesce(p_answer,''),1200); if s=1 and not r.submitted1 then update game_rooms set answer1=a,submitted1=true where id=r.id; elsif s=2 and not r.submitted2 then update game_rooms set answer2=a,submitted2=true where id=r.id; else raise exception 'Answer already submitted'; end if; select * into r from game_rooms where id=r.id; if (r.submitted1 and r.submitted2) or now()>=r.deadline then update game_rooms set status='revealed' where id=r.id; end if; end $$;
create or replace function public.vote_next(p_code text,p_token text,p_category text,p_question text) returns void language plpgsql security definer set search_path=public,extensions as $$
declare r game_rooms; s int;
begin select * into r from game_rooms where code=upper(p_code) for update; perform room_state(p_code,p_token); s:=case when digest(p_token,'sha256')::text=r.player1_token_hash then 1 else 2 end; if r.status<>'revealed' then raise exception 'Finish this reveal first'; end if; if s=1 then update game_rooms set vote1=true where id=r.id; else update game_rooms set vote2=true where id=r.id; end if; select * into r from game_rooms where id=r.id; if r.vote1 and r.vote2 then update game_rooms set category=p_category,question=p_question,round_no=round_no+1,status='playing',deadline=now()+interval '90 seconds',answer1=null,answer2=null,submitted1=false,submitted2=false,analysis=null,vote1=false,vote2=false,used_questions=used_questions||p_question where id=r.id; end if; end $$;
create or replace function public.mirror_room_event() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into room_events(code,player1_name,player2_name,category,question,round_no,status,deadline,submitted1,submitted2,analysis,vote1,vote2) values(new.code,new.player1_name,new.player2_name,new.category,new.question,new.round_no,new.status,new.deadline,new.submitted1,new.submitted2,new.analysis,new.vote1,new.vote2) on conflict(code) do update set player1_name=excluded.player1_name,player2_name=excluded.player2_name,category=excluded.category,question=excluded.question,round_no=excluded.round_no,status=excluded.status,deadline=excluded.deadline,submitted1=excluded.submitted1,submitted2=excluded.submitted2,analysis=excluded.analysis,vote1=excluded.vote1,vote2=excluded.vote2; return new; end $$;
create trigger game_room_event_mirror after insert or update on public.game_rooms for each row execute function public.mirror_room_event();
-- All state mutations pass through token-checked functions. No direct table writes are granted.
revoke all on function public.room_state(text,text) from public;
revoke all on function public.create_room(text,text) from public;
revoke all on function public.join_room(text,text) from public;
revoke all on function public.get_room_state(text,text) from public;
revoke all on function public.start_round(text,text,text,text) from public;
revoke all on function public.submit_answer(text,text,text) from public;
revoke all on function public.vote_next(text,text,text,text) from public;
grant execute on function public.create_room(text,text),public.join_room(text,text),public.get_room_state(text,text),public.start_round(text,text,text,text),public.submit_answer(text,text,text),public.vote_next(text,text,text,text) to anon,authenticated;

-- Realtime publishes room status changes; clients fetch their authorized view through get_room_state.
alter publication supabase_realtime add table public.room_events;
