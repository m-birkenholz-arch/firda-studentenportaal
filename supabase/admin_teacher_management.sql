-- Run this complete script in Supabase SQL Editor.
-- Admins can invite a teacher before registration. Existing accounts are promoted immediately.

create table if not exists public.teacher_invites (
  email text primary key,
  invited_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.teacher_invites enable row level security;

create or replace function public.admin_invite_teacher(account_email text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  clean_email text := lower(trim(account_email));
  target_id uuid;
begin
  if not exists (
    select 1 from public.profiles me
    where me.id = auth.uid() and me.role = 'admin'
  ) then
    raise exception 'Alleen een beheerder kan docenten toevoegen.';
  end if;

  if clean_email = '' then raise exception 'Vul een e-mailadres in.'; end if;

  select u.id into target_id from auth.users u where lower(u.email)=clean_email limit 1;

  if target_id is not null then
    update public.profiles set role='teacher'
    where id=target_id and role <> 'admin';
    delete from public.teacher_invites where email=clean_email;
    return 'promoted';
  end if;

  insert into public.teacher_invites(email,invited_by)
  values(clean_email,auth.uid())
  on conflict(email) do update set invited_by=excluded.invited_by,created_at=now();

  return 'invited';
end;
$$;

create or replace function public.apply_teacher_invite()
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare clean_email text;
begin
  select lower(u.email) into clean_email from auth.users u where u.id=auth.uid();
  if clean_email is null then return false; end if;

  if exists(select 1 from public.teacher_invites i where i.email=clean_email) then
    update public.profiles set role='teacher' where id=auth.uid();
    delete from public.teacher_invites where email=clean_email;
    return true;
  end if;
  return false;
end;
$$;

create or replace function public.admin_list_teachers()
returns table(id uuid, full_name text, email text)
language sql
security definer
set search_path = public, auth
as $$
  select p.id,p.full_name,u.email::text
  from public.profiles p join auth.users u on u.id=p.id
  where p.role in ('teacher','admin')
    and exists(select 1 from public.profiles me where me.id=auth.uid() and me.role='admin')
  order by p.full_name nulls last,u.email;
$$;

revoke all on table public.teacher_invites from public, anon, authenticated;
revoke all on function public.admin_invite_teacher(text) from public;
revoke all on function public.apply_teacher_invite() from public;
revoke all on function public.admin_list_teachers() from public;
grant execute on function public.admin_invite_teacher(text) to authenticated;
grant execute on function public.apply_teacher_invite() to authenticated;
grant execute on function public.admin_list_teachers() to authenticated;
