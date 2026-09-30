-- Admin-only bootstrap and invitation functions use the service-role API key.
-- RLS bypass does not replace table privileges; explicitly grant both existing
-- and multi-context tables to this trusted server role.
grant usage on schema public to service_role;
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
