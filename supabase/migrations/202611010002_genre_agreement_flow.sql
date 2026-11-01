-- Track the next-round genre proposal separately from the active genre.
-- vote1/vote2 are the two explicit approvals for either the current genre or proposal.
alter table public.game_rooms add column if not exists next_category text;
alter table public.room_events add column if not exists next_category text;

create or replace function public.room_state(p_code text,p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r game_rooms; s int; revealed boolean;
begin
  select * into r from game_rooms where code=upper(p_code);
  if not found then raise exception 'Room not found'; end if;
  if digest(p_token,'sha256')::text=r.player1_token_hash then s:=1;
  elsif r.player2_token_hash is not null and digest(p_token,'sha256')::text=r.player2_token_hash then s:=2;
  else raise exception 'Invalid room invitation'; end if;
  revealed:=r.status='revealed';
  return jsonb_build_object(
    'code',r.code,
    'players',jsonb_build_array(
      jsonb_build_object('name',r.player1_name),
      case when r.player2_name is not null then jsonb_build_object('name',r.player2_name) else null end
    ),
    'category',r.category,
    'next_category',r.next_category,
    'question',r.question,
    'round_no',r.round_no,
    'status',r.status,
    'deadline',r.deadline,
    'submitted_by_me',case when s=1 then r.submitted1 else r.submitted2 end,
    'other_submitted',case when s=1 then r.submitted2 else r.submitted1 end,
    'my_answer',case when s=1 then r.answer1 else r.answer2 end,
    'answer_one',case when revealed then r.answer1 else null end,
    'answer_two',case when revealed then r.answer2 else null end,
    'analysis',case when revealed then r.analysis else null end,
    'next_votes',(r.vote1::int+r.vote2::int),
    'voted_by_me',case when s=1 then r.vote1 else r.vote2 end,
    'other_agreed',case when s=1 then r.vote2 else r.vote1 end
  );
end $$;

-- Selecting a new proposal clears both approvals. Selecting the active genre
-- means "keep current" and clears any pending proposal.
create or replace function public.propose_next_genre(p_code text,p_token text,p_category text)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare r game_rooms; proposed text;
begin
  select * into r from game_rooms where code=upper(p_code) for update;
  if not found then raise exception 'Room not found'; end if;
  perform room_state(p_code,p_token);
  if r.status<>'revealed' then raise exception 'A genre can only be proposed after the reveal'; end if;
  if p_category is null or p_category not in (
    'Love & Romance','Childhood & Nostalgia','Psychology & Personality','Dreams & Ambitions',
    'Philosophy & Life','Vulnerability & Deep Talks','Random & Ridiculous','Travel & Adventures',
    'Art, Music & Literature','Us & Our Future','What If?','Secrets & Confessions','Surprise Me'
  ) then raise exception 'Unknown question genre'; end if;
  proposed:=case when p_category=r.category then null else p_category end;
  if proposed is distinct from r.next_category then
    update game_rooms set next_category=proposed,vote1=false,vote2=false where id=r.id;
  end if;
end $$;

-- Each player's ready vote is an explicit agreement with the current proposal.
-- The row lock serializes simultaneous confirmations; only the second distinct
-- approval can transition the room, and only while it is still revealed.
create or replace function public.vote_next(p_code text,p_token text,p_category text,p_question text)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare r game_rooms; s int; target_category text;
begin
  select * into r from game_rooms where code=upper(p_code) for update;
  if not found then raise exception 'Room not found'; end if;
  perform room_state(p_code,p_token);
  if r.status<>'revealed' then raise exception 'Finish this reveal first'; end if;
  target_category:=coalesce(r.next_category,r.category);
  if p_category is distinct from target_category then
    raise exception 'The next genre changed. Refresh the room and choose a question for the active proposal.';
  end if;
  if p_category not in (
    'Love & Romance','Childhood & Nostalgia','Psychology & Personality','Dreams & Ambitions',
    'Philosophy & Life','Vulnerability & Deep Talks','Random & Ridiculous','Travel & Adventures',
    'Art, Music & Literature','Us & Our Future','What If?','Secrets & Confessions','Surprise Me'
  ) then raise exception 'Unknown question genre'; end if;
  if p_question is null or length(trim(p_question))=0 then raise exception 'A next question is required'; end if;
  s:=case when digest(p_token,'sha256')::text=r.player1_token_hash then 1 else 2 end;
  if s=1 then update game_rooms set vote1=true where id=r.id;
  else update game_rooms set vote2=true where id=r.id; end if;
  select * into r from game_rooms where id=r.id;
  if r.vote1 and r.vote2 then
    update game_rooms set
      category=target_category,
      question=p_question,
      round_no=round_no+1,
      status='playing',
      deadline=now()+interval '120 seconds',
      answer1=null,
      answer2=null,
      submitted1=false,
      submitted2=false,
      analysis=null,
      vote1=false,
      vote2=false,
      next_category=null,
      used_questions=used_questions||p_question
    where id=r.id;
  end if;
end $$;

-- Keep Realtime's safe mirror in sync with the proposal and agreement votes.
create or replace function public.mirror_room_event()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into room_events(code,player1_name,player2_name,category,next_category,question,round_no,status,deadline,submitted1,submitted2,analysis,vote1,vote2)
  values(new.code,new.player1_name,new.player2_name,new.category,new.next_category,new.question,new.round_no,new.status,new.deadline,new.submitted1,new.submitted2,new.analysis,new.vote1,new.vote2)
  on conflict(code) do update set
    player1_name=excluded.player1_name,
    player2_name=excluded.player2_name,
    category=excluded.category,
    next_category=excluded.next_category,
    question=excluded.question,
    round_no=excluded.round_no,
    status=excluded.status,
    deadline=excluded.deadline,
    submitted1=excluded.submitted1,
    submitted2=excluded.submitted2,
    analysis=excluded.analysis,
    vote1=excluded.vote1,
    vote2=excluded.vote2;
  return new;
end $$;

revoke all on function public.propose_next_genre(text,text,text) from public;
grant execute on function public.propose_next_genre(text,text,text) to anon,authenticated;
revoke all on function public.vote_next(text,text,text,text) from public;
grant execute on function public.vote_next(text,text,text,text) to anon,authenticated;
