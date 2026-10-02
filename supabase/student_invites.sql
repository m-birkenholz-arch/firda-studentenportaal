-- Student invitation flow. Run once in Supabase SQL Editor.

create table if not exists public.student_invites (
  email text not null,
  class_id uuid not null references public.classes(id) on delete cascade,
  invited_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (email, class_id)
);

alter table public.student_invites enable row level security;

create or replace function public.invite_student_to_class(student_email text, target_class_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text := lower(trim(student_email));
  v_student uuid;
  v_teacher uuid;
begin
  select teacher_id into v_teacher from public.classes where id=target_class_id;
  if v_teacher is null or (v_teacher <> auth.uid() and not public.is_teacher()) then
    raise exception 'Geen toegang tot deze klas.';
  end if;

  select p.id into v_student
  from auth.users u join public.profiles p on p.id=u.id
  where lower(u.email)=v_email and p.role='student'
  limit 1;

  if v_student is not null then
    if exists(select 1 from public.class_members where class_id=target_class_id and student_id=v_student) then
      return jsonb_build_object('status','member');
    end if;
    insert into public.class_members(class_id,student_id) values(target_class_id,v_student);
    return jsonb_build_object('status','added');
  end if;

  insert into public.student_invites(email,class_id,invited_by)
  values(v_email,target_class_id,auth.uid())
  on conflict(email,class_id) do update set invited_by=excluded.invited_by,created_at=now();

  return jsonb_build_object('status','invited');
end;
$$;

create or replace function public.apply_student_invites()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
  v_count integer := 0;
begin
  select lower(email) into v_email from auth.users where id=auth.uid();
  if v_email is null then return 0; end if;

  insert into public.class_members(class_id,student_id)
  select i.class_id,auth.uid()
  from public.student_invites i
  where lower(i.email)=v_email
  on conflict do nothing;
  get diagnostics v_count = row_count;

  delete from public.student_invites where lower(email)=v_email;
  return v_count;
end;
$$;

revoke all on function public.invite_student_to_class(text,uuid) from public;
revoke all on function public.apply_student_invites() from public;
grant execute on function public.invite_student_to_class(text,uuid) to authenticated;
grant execute on function public.apply_student_invites() to authenticated;
