-- Lets teachers/admins list active student accounts for class membership.
create or replace function public.list_available_students(target_class_id uuid)
returns table(id uuid, full_name text, email text, student_number text)
language sql
security definer
set search_path = public, auth
as $$
  select p.id,p.full_name,u.email::text,p.student_number
  from public.profiles p
  join auth.users u on u.id=p.id
  where p.role='student'
    and exists(
      select 1 from public.profiles me
      where me.id=auth.uid() and me.role in ('teacher','admin')
    )
    and not exists(
      select 1 from public.class_members cm
      where cm.class_id=target_class_id and cm.student_id=p.id
    )
  order by p.full_name nulls last,u.email;
$$;
revoke all on function public.list_available_students(uuid) from public;
grant execute on function public.list_available_students(uuid) to authenticated;
