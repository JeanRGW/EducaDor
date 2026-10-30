-- Declarative baseline safety checks. Run locally after a clean reset.
begin;
do $$
declare obj record; privilege text;
begin
  if (select count(*) from pg_tables where schemaname='public') <> 15 then
    raise exception 'Unexpected application table set';
  end if;
  for obj in select tablename, rowsecurity from pg_tables where schemaname='public' loop
    if not obj.rowsecurity then raise exception 'RLS missing on %', obj.tablename; end if;
    foreach privilege in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES'] loop
      if has_table_privilege('anon', format('public.%I',obj.tablename), privilege) then
        raise exception 'Anonymous % grant on %', privilege, obj.tablename;
      end if;
    end loop;
    if has_table_privilege('authenticated', format('public.%I',obj.tablename), 'TRUNCATE') then
      raise exception 'Client can bypass RLS with TRUNCATE on %', obj.tablename;
    end if;
  end loop;
  -- Report views deliberately use owner reads plus explicit context guards:
  -- empresa needs aggregates without permission to read the underlying lessons.
  for obj in select c.oid::regclass as name from pg_class c
    join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='v' loop
    if has_table_privilege('anon',obj.name,'SELECT')
      or has_table_privilege('authenticated',obj.name,'TRUNCATE') then
      raise exception 'Unexpected client privilege on report view %',obj.name;
    end if;
  end loop;
  for obj in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' loop
    if has_function_privilege('anon',obj.oid,'EXECUTE') then
      raise exception 'Anonymous function grant: %',obj.oid::regprocedure;
    end if;
  end loop;
  if has_function_privilege('authenticated','public.custom_access_token_hook(jsonb)','EXECUTE')
    or not has_function_privilege('supabase_auth_admin','public.custom_access_token_hook(jsonb)','EXECUTE') then
    raise exception 'Auth hook grant mismatch';
  end if;
  if (select count(*) from storage.buckets where id in ('educador-public','educador-private','educador-backups'))<>3
    or exists(select 1 from storage.buckets where id in ('educador-private','educador-backups') and public)
    or not exists(select 1 from storage.buckets where id='educador-public' and public)
    or not exists(select 1 from storage.buckets where id='educador-private' and 'image/gif'=any(allowed_mime_types))
    or exists(select 1 from storage.buckets where 'video/mp4'=any(allowed_mime_types)) then
    raise exception 'Storage provisioning mismatch';
  end if;
end $$;
rollback;
