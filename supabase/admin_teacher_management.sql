-- Run once in the Supabase SQL Editor.
-- Admin-only teacher management. The browser never receives auth.users.

create or replace function public.admin_list_teachers()
returns table(id uuid, full_name text, email text)
language sql
security definer
set search_path = public, auth
as $$
  select p.id, p.full_name, u.email::text
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.role in ('teacher','admin')
    and exists (
      select 1 from public.profiles me
      where me.id = auth.uid() and me.role = 'admin'
    )
  order by p.full_name nulls last, u.email;
$$;

create or replace function public.admin_promote_teacher(account_email text)
returns table(id uuid, full_name text, email text)
language plpgsql
security definer
set search_path = public, auth
as $$
declare target_id uuid;
begin
  if not exists (
    select 1 from public.profiles me
    where me.id = auth.uid() and me.role = 'admin'
  ) then
    raise exception 'Alleen een beheerder kan docenten toevoegen.';
  end if;

  select u.id into target_id
  from auth.users u
  where lower(u.email) = lower(trim(account_email))
  limit 1;

  if target_id is null then
    raise exception 'Geen bestaand account gevonden met dit e-mailadres.';
  end if;

  update public.profiles
  set role = 'teacher'
  where profiles.id = target_id
    and role <> 'admin';

  return query
  select p.id, p.full_name, u.email::text
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = target_id;
end;
$$;

revoke all on function public.admin_list_teachers() from public;
revoke all on function public.admin_promote_teacher(text) from public;
grant execute on function public.admin_list_teachers() to authenticated;
grant execute on function public.admin_promote_teacher(text) to authenticated;
