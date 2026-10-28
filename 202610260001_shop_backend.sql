-- Review BACKEND_REVIEW.md and inspect the target schema before applying.
-- Intentionally no IF NOT EXISTS: existing tables require a tailored migration.
begin;
create table public.products (
  id bigint generated always as identity primary key,
  name text not null check (length(trim(name)) between 1 and 80),
  category text not null check (length(trim(category)) between 1 and 40),
  description text not null check (length(trim(description)) between 1 and 400),
  price numeric(12,2) not null check (price > 0 and price <= 99999999),
  stock_quantity integer not null default 0 check (stock_quantity between 0 and 999999),
  image_url text check (image_url is null or (length(image_url) <= 2048 and image_url ~ '^https?://')),
  created_at timestamptz not null default now()
);
-- Membership only, never credentials. No client may write this table.
create table public.shop_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete restrict,
  total_amount numeric(16,2) not null check (total_amount > 0),
  status text not null default 'confirmed' check (status = 'confirmed'),
  created_at timestamptz not null default now(),
  -- Same key returns the same bill if the client retries a timed-out request.
  checkout_key uuid not null,
  unique (customer_id, checkout_key)
);
create table public.order_items (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete restrict,
  product_id bigint references public.products(id) on delete set null,
  -- Snapshot keeps old bills readable after a product is renamed or deleted.
  product_name text not null,
  quantity integer not null check (quantity between 1 and 999999),
  unit_price numeric(12,2) not null check (unit_price > 0),
  subtotal numeric(16,2) generated always as (quantity * unit_price) stored
);
create index orders_customer_idx on public.orders(customer_id);
create index order_items_order_idx on public.order_items(order_id);
create index order_items_product_idx on public.order_items(product_id);

alter table public.products enable row level security;
alter table public.shop_admins enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

-- Non-recursive: customers only see their own membership (usually zero rows).
create policy own_admin_membership on public.shop_admins for select to authenticated
  using (user_id = (select auth.uid()));
create policy signed_in_product_read on public.products for select to authenticated using (true);
create policy admin_product_insert on public.products for insert to authenticated
  with check (exists (select 1 from public.shop_admins where user_id = (select auth.uid())));
create policy admin_product_update on public.products for update to authenticated
  using (exists (select 1 from public.shop_admins where user_id = (select auth.uid())))
  with check (exists (select 1 from public.shop_admins where user_id = (select auth.uid())));
create policy admin_product_delete on public.products for delete to authenticated
  using (exists (select 1 from public.shop_admins where user_id = (select auth.uid())));
create policy own_order_read on public.orders for select to authenticated
  using (customer_id = (select auth.uid()));
create policy own_item_read on public.order_items for select to authenticated
  using (exists (select 1 from public.orders where orders.id = order_id and customer_id = (select auth.uid())));

-- Remove Supabase's default grants; explicitly allow only necessary operations.
revoke all on public.products, public.shop_admins, public.orders, public.order_items from public, anon, authenticated;
grant select on public.products, public.shop_admins, public.orders, public.order_items to authenticated;
grant insert(name, category, description, price, stock_quantity, image_url),
      update(name, category, description, price, stock_quantity, image_url), delete
      on public.products to authenticated;
revoke all on sequence public.products_id_seq, public.order_items_id_seq from public, anon, authenticated;
grant usage on sequence public.products_id_seq to authenticated;

-- One RPC is the only client order-write path. All SQL executes in one transaction.
create function public.checkout_shop(p_items jsonb, p_checkout_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_customer uuid := auth.uid();
  v_order public.orders%rowtype;
  v_product public.products%rowtype;
  v_line record;
  v_total numeric(16,2) := 0;
  v_expected integer;
  v_found integer := 0;
begin
  if v_customer is null then raise exception 'Sign in before checkout' using errcode = '42501'; end if;
  if p_checkout_key is null then raise exception 'Checkout key required' using errcode = '22023'; end if;
  -- Serializes retries per customer, even across simultaneous requests.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_customer::text, 0));
  select * into v_order from public.orders where customer_id = v_customer and checkout_key = p_checkout_key;
  if found then return pg_catalog.jsonb_build_object('order_id',v_order.id,'total_amount',v_order.total_amount); end if;
  if p_items is null or pg_catalog.jsonb_typeof(p_items) <> 'array' then
    raise exception 'Cart must be an array' using errcode = '22023';
  end if;
  if pg_catalog.jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'Cart must contain between 1 and 100 products' using errcode = '22023';
  end if;
  for v_line in select value from pg_catalog.jsonb_array_elements(p_items) loop
    if pg_catalog.jsonb_typeof(v_line.value) <> 'object'
       or not (v_line.value ? 'product_id' and v_line.value ? 'quantity')
       or (v_line.value - 'product_id' - 'quantity') <> '{}'::jsonb
       or (v_line.value->>'product_id') !~ '^[1-9][0-9]{0,14}$'
       or (v_line.value->>'quantity') !~ '^[1-9][0-9]{0,5}$'
       or v_line.value->>'product_id' is null or v_line.value->>'quantity' is null then
      raise exception 'Only product_id and positive integer quantity are accepted' using errcode = '22023';
    end if;
  end loop;
  select count(distinct (value->>'product_id')::bigint) into v_expected from pg_catalog.jsonb_array_elements(p_items);
  if v_expected <> pg_catalog.jsonb_array_length(p_items) then
    raise exception 'Duplicate products are not accepted' using errcode = '22023';
  end if;
  -- Stable lock order avoids deadlocks between carts containing the same products.
  for v_product in select p.* from public.products p
    where p.id in (select (value->>'product_id')::bigint from pg_catalog.jsonb_array_elements(p_items))
    order by p.id for update
  loop
    v_found := v_found + 1;
    select (value->>'quantity')::integer as quantity into v_line
      from pg_catalog.jsonb_array_elements(p_items) where (value->>'product_id')::bigint = v_product.id;
    if v_product.stock_quantity < v_line.quantity then
      raise exception 'Insufficient stock for %',v_product.name using errcode = 'P0001';
    end if;
    v_total := v_total + v_product.price * v_line.quantity;
  end loop;
  if v_found <> v_expected then raise exception 'A product is no longer available' using errcode = 'P0001'; end if;
  insert into public.orders(customer_id,total_amount,checkout_key)
    values(v_customer,v_total,p_checkout_key) returning * into v_order;
  insert into public.order_items(order_id,product_id,product_name,quantity,unit_price)
    select v_order.id,p.id,p.name,(i.value->>'quantity')::integer,p.price
    from pg_catalog.jsonb_array_elements(p_items) i join public.products p on p.id=(i.value->>'product_id')::bigint;
  update public.products p set stock_quantity = p.stock_quantity - oi.quantity
    from public.order_items oi where oi.order_id=v_order.id and oi.product_id=p.id;
  return pg_catalog.jsonb_build_object('order_id',v_order.id,'total_amount',v_order.total_amount);
end;
$$;
revoke all on function public.checkout_shop(jsonb,uuid) from public, anon, authenticated;
grant execute on function public.checkout_shop(jsonb,uuid) to authenticated;
commit;
