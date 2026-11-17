# Rosbren Health Clinic ERP

A mini-ERP for Rosbren Health Clinic: pharmacy point of sale, sales orders, returns and exchanges, inventory across 3 locations, barcode scanning, kit production with bills of material, MRP, purchasing with supplier scorecards, reorder points and EOQ, financial statements, a customer pickup portal, and an Outreach Readiness Planner.

**Stack (all free):** React + Vite (front-end) · Supabase (PostgreSQL database, logins with MFA, real-time updates) · GitHub (private code) · Vercel (HTTPS hosting).

---

## 1. Set up the database (Supabase) — about 10 minutes

1. Go to <https://supabase.com>, sign in with GitHub, and click **New project** (Free plan). Pick a strong database password and a region near you.
2. When it's ready, open **SQL Editor → New query**. Paste the **entire** contents of [`supabase/setup.sql`](supabase/setup.sql) and click **Run**.
   This creates every table, security rule and business function, then generates ~6½ months of starting data. It finishes in a few seconds with a one-row result like `{"sales": 2700, "items": 59, ...}`.
3. **Authentication → Sign In / Providers → Email**
   - Keep **Email** enabled.
   - **Confirm email:** for a class demo you can turn this **off** so new accounts can sign in immediately. Supabase's free email service only sends a few emails per hour.
4. **Authentication → Policies / Passwords** (the name varies by Supabase version):
   - Minimum password length **10**.
   - Password requirements: **lowercase, uppercase, digits and symbols**.
   - Turn on **leaked-password protection** if your plan offers it.
5. **Authentication → Multi-Factor**: make sure **TOTP (Authenticator app)** is enabled. It is on by default.
6. **Project Settings → API**: copy the **Project URL** and the **anon public** key. You'll need both in step 3.

> ⚠️ Never put the `service_role` key in the app or on GitHub. The anon key is safe to expose because every table is protected by Row-Level Security.

## 2. Put the code on GitHub (private)

```bash
cd rosbren-erp
git init && git add . && git commit -m "Rosbren ERP"
# create an EMPTY private repo on github.com named rosbren-erp, then:
git remote add origin https://github.com/<your-username>/rosbren-erp.git
git branch -M main && git push -u origin main
```

Keep the repository **private**. `supabase/setup.sql` contains Rosbren's real product list, prices and expense figures. Add teammates under **Settings → Collaborators**.

## 3. Deploy (Vercel, free)

1. Go to <https://vercel.com>, sign in with GitHub, click **Add New → Project**, and import `rosbren-erp`.
2. Framework preset: **Vite**. This is detected automatically.
3. Under **Environment Variables**, add:
   - `VITE_SUPABASE_URL` = your Project URL
   - `VITE_SUPABASE_ANON_KEY` = your anon public key
4. Click **Deploy**. You get a URL like `https://rosbren-erp.vercel.app`.
5. Back in Supabase → **Authentication → URL Configuration**: set **Site URL** to that Vercel URL, and add it to **Redirect URLs**. This makes password-reset and confirmation links work.

Every `git push` to `main` redeploys automatically. `vercel.json` adds security headers (CSP, HSTS, no framing, no search indexing).

## 4. First login & staff accounts

1. Open the site and click **New customer? Create account**. **The very first account becomes the Administrator.**
2. Sign in. You'll be asked to scan a QR code with Google Authenticator, Microsoft Authenticator or Authy, then enter the 6-digit code. Staff need this code at every sign-in.
3. Each teammate creates an account (they start as *customers*). Then the admin opens **Users & Security** and sets their role:
   - **Manager**: everything, including finance and settings
   - **Pharmacist**: POS, orders, returns, stock
   - **Store keeper**: stock, production, purchasing
   - **Customer**: online pickup portal only

   Their next sign-in requires MFA setup.
4. For the customer-portal demo, create one more account and leave it as a customer.

### Security features (good to mention in the demo)
| Control | How |
|---|---|
| Passwords | Supabase Auth with bcrypt hashing; 10+ characters with complexity, checked in the app and enforced in Supabase settings |
| MFA | TOTP authenticator app. **Enforced in the database**: staff functions and tables return nothing unless the login is AAL2 (password + code) |
| Role-based access | PostgreSQL Row-Level Security. Customers see only their own orders; finance, settings and users are manager-only |
| Business rules | Stock, cost and money change only through validated database functions, each one atomic |
| Sessions | Kept per browser tab (cleared on close); auto sign-out after 15 idle minutes (configurable) |
| Audit | Every transaction, role change, sign-in/out and settings change goes to the Activity Log |
| Transport | HTTPS only (HSTS), strict Content-Security-Policy, no iframing |

## 5. Before every demo

- **Settings → Regenerate demo data** (admin), or run `select reset_demo_data();` in the SQL Editor. History is regenerated so it ends **yesterday**. Users and settings are kept.
- Free Supabase projects **pause after 7 days without activity**. Open the project the day before the demo and click *Restore* if needed.
- Print barcode labels from **Barcode Labels → Add demo set → Print**, cut them out and bring them along.
- Test the camera scanner on your phone with the Vercel URL. Camera access requires HTTPS.

## 6. Run locally (optional)

```bash
npm install
cp .env.example .env.local      # fill in your Supabase URL + anon key
npm run dev                     # http://localhost:5173
```

**Offline developer mode** runs the same SQL inside the browser (PGlite, Postgres in WebAssembly), with demo accounts and no real security. It's handy for practising without internet:

```bash
npm run dev:offline
```

It is automatically left out of production builds.

### Tests
```bash
npm run test:db      # runs setup.sql in PGlite and exercises every transaction + security rule
npm run test:mrp     # MRP netting / BOM explosion against a hand-checked example
npm run check:data   # sanity-checks generated history, ROP/EOQ, scorecards, P&L
```

If you change any `supabase/0*.sql` file, run `npm run build:sql` to regenerate `setup.sql`, then re-run it in Supabase. The script is safe to run again.

## Project layout

```
supabase/
  01_schema.sql      tables, RLS security, MFA enforcement, sign-up trigger
  02_logic.sql       POS, sales orders, returns, transfers, adjustments, production, purchasing, portal
  03_reports.sql     inventory status, ROP/EOQ, MRP inputs, P&L, valuation, production report, scorecards, dashboard, outreach
  04_seed*.sql       starting-data generator (calibrated to Rosbren's real workbooks)
  setup.sql          ← all of the above in one file (paste into Supabase)
src/
  lib/api.js         data access (Supabase) + realtime
  lib/mrp.js         MRP time-phased netting & BOM explosion
  auth/Auth.jsx      sign-in, sign-up, MFA enrolment/verification, password rules, idle timeout
  pages/*.jsx        one file per module
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Connect your Supabase project" screen | Env variables are missing in Vercel. Add them and redeploy. |
| Staff see "Access denied: … MFA" | They signed in without completing the authenticator step. Sign out and back in. |
| Camera scanner won't open | It needs HTTPS (use the Vercel URL, not `http://`) and browser camera permission. A USB scanner always works: click the scan box and scan. |
| Someone lost their authenticator phone | Supabase → Authentication → Users → select the user → remove MFA factor. They'll enrol again at next sign-in. |
| Something blocked by Content-Security-Policy | Check the browser console. Adjust or remove the CSP line in `vercel.json` and redeploy. |
