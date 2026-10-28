-- Admin-only order read endpoint; customer RLS policies are unchanged.
create function public.shop_list_orders()
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if auth.uid() is null or not exists(select 1 from public.shop_admins a where a.user_id=auth.uid()) then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'order_id',o.id,'customer_email',u.email,'total_amount',o.total_amount,
    'status',o.status,'created_at',o.created_at,
    'items',(select coalesce(jsonb_agg(jsonb_build_object(
      'product_name',i.product_name,'quantity',i.quantity,
      'unit_price',i.unit_price,'subtotal',i.subtotal) order by i.id),'[]'::jsonb)
      from public.order_items i where i.order_id=o.id)
    ) order by o.created_at desc),'[]'::jsonb) into result
  from (select * from public.orders order by created_at desc limit 100) o
  join auth.users u on u.id=o.customer_id;
  return result;
end; $$;
revoke all on function public.shop_list_orders() from public,anon,authenticated;
grant execute on function public.shop_list_orders() to authenticated;
