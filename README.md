# ShopMate — Shop Management System
College project: HTML, CSS, vanilla JavaScript and Supabase Auth/PostgreSQL/Storage.

## Run locally
From this folder run `python -m http.server 8000 --directory dist`, then open http://localhost:8000.
`dist/config.js` contains the existing project's public URL and publishable key. It contains no secret key. Use your own project's public configuration for an independent installation.

## Database setup for a NEW Supabase project
Run these files in order in Supabase SQL Editor:
1. supabase/migrations/202610260001_shop_backend.sql
2. backend/user-management.sql
3. backend/admin-orders.sql
4. backend/product-specifications.sql
5. backend/product-images.sql
Do not rerun these scripts on the existing configured database: they are already applied.
Enable email/password Auth and configure the site URL and email redirects. Register and confirm an account, then a database owner can insert its UUID into public.shop_admins. Existing admins can promote registered accounts from Manage Users. Never place a service-role key in frontend files.

## Features
Admin product CRUD, category overview, product information/specifications, image upload with preview (JPG/PNG/WebP, 5 MB), inventory, customer cart, atomic checkout, saved receipts, admin customer orders and user-role management. Images use private Storage with signed viewing links. Customers cannot edit products or promote themselves. No payment processing is implemented.

## Source folders
- dist/: complete frontend and assets
- supabase/: base schema, RLS and transactional checkout
- backend/: SQL feature extensions
- tests/: database and DOM/API test scripts
Tests use Node.js, jsdom 26.1.0 and, for local database checks, @electric-sql/pglite 0.5.11. Test scripts may reference the original workspace dependency path; set JSDOM_PATH where supported or adjust module paths locally. Live-flow tests require explicitly provisioned disposable QA accounts; do not run them against real accounts.

## Upload to GitHub
Extract the ZIP. On GitHub choose Add file → Upload files and drag the CONTENTS of this folder, then Commit changes. Do not upload just the ZIP if you want the source files browsable on GitHub.
No passwords, customer/order exports, node_modules, Git history, or hosting credentials are included. The original BACKEND_REVIEW.md is historical and may contain outdated setup status; this README describes the packaged version.
