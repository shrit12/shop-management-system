-- Reviewed extension: no new table grants. Only verified admins can list users
-- or alter memberships; passwords/hashes are never returned. Keep last admin.
create function public.shop_list_users(p_search text default '')
returns table(user_id uuid,email text,email_confirmed boolean,is_admin boolean,registered_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.shop_admins a where a.user_id=auth.uid()) then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  if p_search is null or length(p_search)>100 then raise exception 'Invalid search'; end if;
  return query select u.id,u.email::text,u.email_confirmed_at is not null,a.user_id is not null,u.created_at
    from auth.users u left join public.shop_admins a on a.user_id=u.id
    where position(lower(p_search) in lower(u.email))>0
    order by u.created_at desc limit 100;
end; $$;
revoke all on function public.shop_list_users(text) from public,anon,authenticated;
grant execute on function public.shop_list_users(text) to authenticated;

create function public.shop_set_admin(p_user_id uuid,p_is_admin boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
  -- Serialize role changes, including the last-admin check and caller lookup.
  lock table public.shop_admins in share row exclusive mode;
  if auth.uid() is null or not exists(select 1 from public.shop_admins a where a.user_id=auth.uid()) then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  if p_user_id is null or p_is_admin is null then raise exception 'User and role are required'; end if;
  if not exists(select 1 from auth.users u where u.id=p_user_id) then raise exception 'User not found'; end if;
  if p_is_admin then
    if not exists(select 1 from auth.users u where u.id=p_user_id and u.email_confirmed_at is not null) then
      raise exception 'User must confirm their email first';
    end if;
    insert into public.shop_admins(user_id) values(p_user_id) on conflict do nothing;
  else
    if exists(select 1 from public.shop_admins a where a.user_id=p_user_id)
       and (select count(*) from public.shop_admins)<=1 then
      raise exception 'Cannot remove the last administrator';
    end if;
    delete from public.shop_admins a where a.user_id=p_user_id;
  end if;
end; $$;
revoke all on function public.shop_set_admin(uuid,boolean) from public,anon,authenticated;
grant execute on function public.shop_set_admin(uuid,boolean) to authenticated;
