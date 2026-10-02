-- Beheerder: alle actieve studentaccounts tonen
create or replace function public.admin_list_students()
returns table (
  id uuid,
  full_name text,
  student_number text,
  email text
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  ) then
    raise exception 'Alleen een beheerder kan studenten bekijken.';
  end if;

  return query
  select
    p.id,
    p.full_name,
    p.student_number,
    u.email::text
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.role = 'student'
  order by p.full_name nulls last, u.email;
end;
$$;

revoke all on function public.admin_list_students() from public;
grant execute on function public.admin_list_students() to authenticated;
