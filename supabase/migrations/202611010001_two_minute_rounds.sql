-- New rounds use a shared server deadline two minutes in the future.
create or replace function public.start_round(p_code text,p_token text,p_category text,p_question text)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare r game_rooms;
begin
  select * into r from game_rooms where code=upper(p_code) for update;
  perform room_state(p_code,p_token);
  if r.player2_name is null then raise exception 'Waiting for the other player'; end if;
  if r.status<>'waiting' then raise exception 'Room is not ready for a new round'; end if;
  update game_rooms set
    category=p_category, question=p_question, round_no=round_no+1,
    status='playing', deadline=now()+interval '120 seconds',
    answer1=null, answer2=null, submitted1=false, submitted2=false,
    analysis=null, vote1=false, vote2=false,
    used_questions=case
      when cardinality(used_questions)>0 and
        (select count(*) from unnest(used_questions) x where x=any(array[p_question]))=1
      then '{}' else used_questions end||p_question
  where id=r.id;
end $$;

create or replace function public.vote_next(p_code text,p_token text,p_category text,p_question text)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare r game_rooms; s int;
begin
  select * into r from game_rooms where code=upper(p_code) for update;
  perform room_state(p_code,p_token);
  s:=case when digest(p_token,'sha256')::text=r.player1_token_hash then 1 else 2 end;
  if r.status<>'revealed' then raise exception 'Finish this reveal first'; end if;
  if s=1 then update game_rooms set vote1=true where id=r.id;
  else update game_rooms set vote2=true where id=r.id; end if;
  select * into r from game_rooms where id=r.id;
  if r.vote1 and r.vote2 then
    update game_rooms set
      category=p_category, question=p_question, round_no=round_no+1,
      status='playing', deadline=now()+interval '120 seconds',
      answer1=null, answer2=null, submitted1=false, submitted2=false,
      analysis=null, vote1=false, vote2=false,
      used_questions=used_questions||p_question
    where id=r.id;
  end if;
end $$;
