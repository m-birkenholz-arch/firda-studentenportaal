-- Opdrachtbestanden voor docenten
-- Eenmalig uitvoeren in Supabase > SQL Editor.

create table if not exists public.assignment_files (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null unique references public.assignments(id) on delete cascade,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  original_filename text not null,
  mime_type text,
  size_bytes bigint,
  created_at timestamptz not null default now()
);

alter table public.assignment_files enable row level security;

drop policy if exists "assignment_files_select" on public.assignment_files;
create policy "assignment_files_select"
on public.assignment_files for select
to authenticated
using (
  exists (
    select 1
    from public.assignments a
    where a.id = assignment_files.assignment_id
      and (
        a.teacher_id = auth.uid()
        or exists (
          select 1 from public.class_members cm
          where cm.class_id = a.class_id
            and cm.student_id = auth.uid()
        )
      )
  )
);

drop policy if exists "assignment_files_insert" on public.assignment_files;
create policy "assignment_files_insert"
on public.assignment_files for insert
to authenticated
with check (
  teacher_id = auth.uid()
  and exists (
    select 1 from public.assignments a
    where a.id = assignment_files.assignment_id
      and a.teacher_id = auth.uid()
  )
);

drop policy if exists "assignment_files_delete" on public.assignment_files;
create policy "assignment_files_delete"
on public.assignment_files for delete
to authenticated
using (
  exists (
    select 1 from public.assignments a
    where a.id = assignment_files.assignment_id
      and a.teacher_id = auth.uid()
  )
);

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values (
  'assignment-files',
  'assignment-files',
  false,
  26214400,
  array[
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'image/jpeg',
    'image/png'
  ]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "assignment_storage_insert" on storage.objects;
create policy "assignment_storage_insert"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'assignment-files'
  and exists (
    select 1 from public.assignments a
    where a.id::text = (storage.foldername(name))[1]
      and a.teacher_id = auth.uid()
  )
);

drop policy if exists "assignment_storage_select" on storage.objects;
create policy "assignment_storage_select"
on storage.objects for select
to authenticated
using (
  bucket_id = 'assignment-files'
  and exists (
    select 1
    from public.assignment_files f
    join public.assignments a on a.id = f.assignment_id
    where f.storage_path = name
      and (
        a.teacher_id = auth.uid()
        or exists (
          select 1 from public.class_members cm
          where cm.class_id = a.class_id
            and cm.student_id = auth.uid()
        )
      )
  )
);

drop policy if exists "assignment_storage_delete" on storage.objects;
create policy "assignment_storage_delete"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'assignment-files'
  and exists (
    select 1
    from public.assignment_files f
    join public.assignments a on a.id = f.assignment_id
    where f.storage_path = name
      and a.teacher_id = auth.uid()
  )
);
