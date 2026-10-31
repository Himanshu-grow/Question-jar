-- The edge function validates the complete analysis before it writes it. Keep the
-- database as a second guard against incomplete or out-of-range score payloads.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'game_rooms_analysis_shape_check'
      and conrelid = 'public.game_rooms'::regclass
  ) then
    alter table public.game_rooms
      add constraint game_rooms_analysis_shape_check check (
        analysis is null or (
          jsonb_typeof(analysis) = 'object'
          and analysis ?& array['score','label','common','difference','observation','follow_up']
          and jsonb_typeof(analysis->'score') = 'number'
          and (analysis->>'score') ~ '^(100|[0-9]{1,2})$'
          and analysis->>'label' in ('Beautifully in Sync','Great Connection','Some Common Ground','Different Perspectives','Opposites Attract')
          and jsonb_typeof(analysis->'common') = 'string'
          and length(trim(analysis->>'common')) >= 12
          and jsonb_typeof(analysis->'difference') = 'string'
          and length(trim(analysis->>'difference')) >= 12
          and jsonb_typeof(analysis->'observation') = 'string'
          and length(trim(analysis->>'observation')) >= 12
          and jsonb_typeof(analysis->'follow_up') = 'string'
          and length(trim(analysis->>'follow_up')) >= 12
        )
      ) not valid;
  end if;
end $$;
