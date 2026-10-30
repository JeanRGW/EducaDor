-- Bucket configuration is DML and is intentionally outside declarative DDL.
-- Keep this provisioning migration for fresh local/hosted installations.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('educador-public', 'educador-public', true, 52428800,
    array['image/webp', 'image/png', 'image/jpeg']),
  ('educador-private', 'educador-private', false, 52428800,
    array['application/pdf', 'audio/mpeg', 'image/gif', 'image/png', 'image/jpeg', 'image/webp']),
  ('educador-backups', 'educador-backups', false, 52428800,
    array['application/gzip', 'application/sql', 'application/octet-stream'])
on conflict (id) do update set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
