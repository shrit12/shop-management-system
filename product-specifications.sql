-- Review: additive optional text field; existing products retain empty specs.
-- Column-specific grants still rely on the existing admin-only RLS policies.
alter table public.products add column specifications text not null default ''
  check(length(specifications)<=4000);
grant insert(specifications),update(specifications) on public.products to authenticated;
