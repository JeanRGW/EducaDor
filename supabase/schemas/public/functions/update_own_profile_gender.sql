CREATE OR REPLACE FUNCTION public.update_own_profile(
  p_name text, p_phone text, p_birth_date date, p_address text, p_gender text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
begin
  if p_gender is not null and p_gender not in ('male','female') then raise exception 'Invalid gender'; end if;
  perform public.update_own_profile(p_name, p_phone, p_birth_date, p_address);
  update public.profiles set gender=p_gender where id=auth.uid();
end $function$;
REVOKE ALL ON FUNCTION public.update_own_profile(text, text, date, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.update_own_profile(text, text, date, text, text) TO authenticated, postgres;
