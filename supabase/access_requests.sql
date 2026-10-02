-- Access request workflow. Run once in Supabase SQL Editor.

create table if not exists public.access_requests (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);
create unique index if not exists access_requests_pending_email on public.access_requests(lower(email)) where status='pending';
alter table public.access_requests enable row level security;
revoke all on table public.access_requests from public, anon, authenticated;

create or replace function public.list_access_requests()
returns table(id uuid,full_name text,email text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select r.id,r.full_name,r.email,r.created_at
 from public.access_requests r
 where r.status='pending'
 and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('teacher','admin'))
 order by r.created_at;
$$;

create or replace function public.approve_access_request(request_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare r public.access_requests%rowtype;
begin
 if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('teacher','admin')) then raise exception 'Geen toegang.'; end if;
 select * into r from public.access_requests where id=request_id and status='pending' for update;
 if r.id is null then raise exception 'Aanvraag niet gevonden.'; end if;
 insert into public.account_invites(email,role,invited_by) values(lower(r.email),'student',auth.uid())
 on conflict(email) do update set role='student',invited_by=excluded.invited_by,created_at=now();
 update public.access_requests set status='approved',reviewed_at=now(),reviewed_by=auth.uid() where id=request_id;
 return true;
end;$$;

create or replace function public.reject_access_request(request_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('teacher','admin')) then raise exception 'Geen toegang.'; end if;
 update public.access_requests set status='rejected',reviewed_at=now(),reviewed_by=auth.uid() where id=request_id and status='pending';
 return found;
end;$$;

revoke all on function public.list_access_requests() from public;
revoke all on function public.approve_access_request(uuid) from public;
revoke all on function public.reject_access_request(uuid) from public;
grant execute on function public.list_access_requests() to authenticated;
grant execute on function public.approve_access_request(uuid) to authenticated;
grant execute on function public.reject_access_request(uuid) to authenticated;
