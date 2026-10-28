-- Run once after the base migration. Private catalog photos; admin uploads only.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('product-images','product-images',false,5242880,array['image/jpeg','image/png','image/webp']);
create policy product_images_admin_insert on storage.objects for insert to authenticated
with check (bucket_id='product-images' and exists(select 1 from public.shop_admins where user_id=(select auth.uid())));
create policy product_images_signed_read on storage.objects for select to authenticated using(bucket_id='product-images');
alter table public.products drop constraint products_image_url_check;
alter table public.products add constraint products_image_url_check check(image_url is null or
(length(image_url)<=2048 and (image_url ~ '^https?://' or image_url ~ '^product-images/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$')));
