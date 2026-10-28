# Backend review — applied and connected

Target: Supabase project `leyajhycrxjpaiffedda`, PostgreSQL + Supabase Auth. The public schema was inspected before application and was empty. The migration was reviewed and applied successfully; see deployment verification below. Future updates must inspect the current schema and append compatible migrations.

## Schema decisions
The three requested tables are included. Prices use fixed-precision numeric columns; quantities have nonnegative/integer constraints. Auth users are referenced by UUID. Passwords remain exclusively in Supabase Auth. Additional fields are `orders.checkout_key` for idempotency and `order_items.product_name` to preserve historical bill labels. Product deletion retains old line items through a nullable product foreign key. Order and customer deletion are restricted to preserve billing records.

A fourth table, `shop_admins`, stores only trusted admin membership. Missing membership means customer. There is no client-write grant or policy on membership, and no role is taken from user-editable metadata. Assign the initial administrator through a trusted database-owner operation after verifying the intended auth user UUID. No account is automatically promoted.

## Access matrix
| Resource | Anonymous | Customer | Admin |
|---|---|---|---|
| Products | Denied | Read | Read/create/update/delete |
| Admin membership | Denied | Read own row only | Read own row only; no writes |
| Orders and items | Denied | Read own | Read own |
| Order writes | Denied | Checkout function only | Checkout function only |

Table grants and RLS both apply. Anonymous requests are denied. Customer writes to product prices are blocked by RLS. No direct client writes to orders/items are permitted. The privileged checkout function has an empty search path, fully qualified references, caller identity checks, explicit execute grants and strictly validated inputs.

## Checkout integrity review
Only product IDs, quantities and an idempotency UUID are accepted. Any client price/total fields are rejected. The function takes prices from locked product rows. Rows lock in ID order; overlapping requests serialize, preventing overselling. Stock checks, header/item insertion and stock deductions share one transaction, so a failure rolls back all changes. A customer-level advisory lock serializes retries; a unique customer/key constraint prevents duplicate bills. Repeat requests with the same key return the original bill. Fresh checkout attempts must use a new key. No payment collection is implemented; confirmed means an accepted shop order, not payment success.

## Deployment update — 26 October 2026
Project `leyajhycrxjpaiffedda` was inspected: empty public schema, zero auth users,
no initial security advisories. Migration `shop_backend` was applied successfully.
The public URL and publishable key are configured; the browser adapter is enabled.
Eight sample catalog items were saved separately from the schema migration.

Verification completed:
- 34 local PostgreSQL checks.
- 17 live Auth/HTTP/RLS checks: product CRUD, denied customer price edits and
  role escalation, trusted totals, idempotency, customer order isolation,
  historical bill snapshots, and two simultaneous requests for one remaining unit.
- DOM integration using the real frontend handlers and live API: admin creates
  product, customer signs in, adds to cart, confirms checkout and sees saved receipt.
- Browser review of the existing home page and login form. Full visual browser
  checkout was not exercised; the complete handler flow was verified in a DOM test.
- Performance advisor returned no findings.

The security advisor reports the intentional authenticated SECURITY DEFINER
checkout RPC. This is a reviewed privileged entry point, not unrestricted table
write access: it checks auth.uid(), rejects price/total inputs, locks rows and
runs atomically with a fixed empty search_path. EXECUTE is revoked from PUBLIC
and anon and granted only to authenticated. See the advisor explanation:
https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable

Configuration still pending: designate the real administrator after that user
registers and confirms their email; configure Supabase Auth Site URL/confirmation
redirect allowlist for the deployed URL. Current email/password sign-in and token
refresh were tested. New-account email delivery and confirmation were not tested;
email confirmation remains enabled. No SMTP or Auth redirect settings were changed.
Passwords/tokens are not stored in application tables or localStorage. Signing out
clears tab state; reloading requires signing in again. No online payment integration.

## Admin user management
The Manage Users screen lists registered email addresses and verification/role
status only. `shop_list_users` and `shop_set_admin` re-check admin membership on
every call. No client gets direct write access to the membership table or access
to password hashes. Promotions require a confirmed email. Role changes serialize
and the last admin cannot be removed. Existing users were not changed by tests;
live role tests ran in a rolled-back transaction. UI wiring tests use a mocked API.
These two guarded privileged endpoints produce the same intentional advisor notice
as checkout. The advisor also reports leaked-password protection disabled in Auth;
this pre-existing configuration was not changed. Remediation:
https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

## Admin customer orders
`shop_list_orders` lists the latest 100 orders with customer email and snapshot
line items, prices, totals, status and date. It checks current admin membership
on each request. Customer table policies are unchanged. Admin-role and customer-
denial cases passed against the live database with a rolled-back order fixture.
UI tests verified product/quantity display and itemized bill details. This guarded
privileged read endpoint has the same reviewed advisor classification as the
other SECURITY DEFINER endpoints; no passwords or tokens are returned.
