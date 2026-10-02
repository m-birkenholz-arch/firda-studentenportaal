-- Run this once in Supabase SQL Editor.
-- Lets an authenticated teacher find exactly one student by email
-- without exposing the full auth.users table to the browser.
create or replace function public.find_student_by_email(student_email text)
returns table(id uuid, full_name text, student_number text)
language sql
security definer
set search_path = public, auth
as $$
  select p.id, p.full_name, p.student_number
  from auth.users u
  join public.profiles p on p.id = u.id
  where lower(u.email) = lower(trim(student_email))
    and p.role = 'student'
    and public.is_teacher()
  limit 1;
$$;

revoke all on function public.find_student_by_email(text) from public;
grant execute on function public.find_student_by_email(text) to authenticated;
