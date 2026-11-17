# Rosbren ERP — Live Demo Guide (10 minutes, Dr. Wright picks the order)

Every screen has a **"How this works"** panel. Open it whenever you need the concept in one breath.

## Before class
- Settings → **Regenerate demo data** (morning of the demo). Sign in as admin on the laptop and as a **second user on a phone or second laptop** to show real-time sync.
- Bring printed labels (Barcode Labels → *Add demo set* → Print) and a USB scanner if you have one. Otherwise use the phone camera.
- Dress professionally. Every teammate presents at least one feature (suggested split below).

## Requirement → where → what to show → concept to say

| # | Requirement | Screen | 30-second demo | Concept to explain |
|---|---|---|---|---|
| 1 | **Point of Sale** | Point of Sale | Scan 3 labels, add a consultation, give 10% line discount, complete → receipt | One atomic transaction: stock ↓ at location, revenue + COGS at weighted-avg cost, ledger + audit. VAT only on taxable items. Kits short on the shelf are **assembled on the spot** (backflush) |
| 4 | **Sales Orders** | Sales Orders | New order for Kasana VHT → open → Fulfill → Close | Order Placed → Fulfilled → Closed; open orders **allocate** stock and drive **MRP** |
| 2 | **Inventory** | Stock & Locations | Filter *Backordered* → Coartem shows backorder + est. available date from the open PO. Transfer 5 ORS STORE→MAIN. Scan a label → cycle count with reason code | On hand vs allocated vs available; inventory position; ETA from PO expected date or supplier lead time |
| 3 | **Barcodes** | POS / PO receiving / Stock count | Scan printed label with phone camera **and** USB scanner | EAN-13, prefix 20 = in-house range; the check digit catches mis-scans |
| 5 | **Returns & Exchanges** | Returns | Scan the receipt barcode → return 1 item as *Defective* (quality) → Exchange for a new one | Revenue and COGS reversed at the original paid price and cost; quality failures are quarantined & written off |
| 6 | **Production Orders** | Production Orders | Open a Planned order → Start (components issued) → Complete with 2 scrapped, reason *Seal failure* → Production & quality report | Rolled-up cost = component cost ÷ good units; metrics: yield, first-pass yield, scrap rate, on-time, cycle time, throughput |
| 7 | **Purchasing & Suppliers** | Purchase Orders → Suppliers & Scorecards | Create PO → Send (expected date = lead time) → Receive by scanning → see on-time badge & bill due date. Scorecards: Lakeside = *Replace* | Scorecards are computed from PO history: on-time %, actual vs quoted lead time, fill rate, money owed. Score 40/35/25 → Keep / Watch / Replace |
| 7b | **ROP / EOQ / periodic review** | Reorder Points & EOQ | Click an item → formula breakdown. **Change ordering cost 25,000 → 100,000 → EOQ doubles (√4)** | ROP = d·L + z·σ·√L; EOQ = √(2DS/H); periodic order-up-to = d(R+L)+zσ√(R+L) |
| 8 | **MRP** | MRP Planner | Show Clean Delivery Kit demand → BOM explosion to cord clamps etc. → toggle *Net parent kits* → Create draft POs | Gross → net of on-hand & scheduled receipts → planned orders → **lead-time offset** order-by dates; *LATE* = expedite |
| 9 | **Financials** | Financial Statements | Make a POS sale, then refresh the P&L: revenue/COGS move. Valuation & turnover tab | Weighted-average cost; turnover = annualised COGS ÷ inventory value; days on hand |
| 10 | **Reports** | Management Reports | Sales by day/week, top sellers, low stock with order-by dates, inventory by location, supplier lead-time chart | Managers act on exceptions |
| 11 | **Customer portal** | Sign in as customer | See availability by location and shelf → place pickup order → it appears instantly in Sales Orders on the staff screen | Self-service channel feeding the same order pipeline |
| 12 | **Multi-user** | Two devices | Sell on the phone → the laptop dashboard and stock update within a second (green *Live* dot pulses) | Supabase Realtime; single source of truth |
| ★ | **Wow: Outreach Readiness Planner** | Outreach Planner | Kasana Village clinic → kits required from expected attendance → **Prepare event**: transfers posted + kit build orders + component POs with order-by dates | Ties inventory → production → MRP → purchasing to Rosbren’s real mission (mobile village clinics) |
| ★ | **Wow: Security** | Users & Security | Sign-in with authenticator code; role-based menus; activity log of sign-ins | Real patient-adjacent & financial data needs MFA + RLS + audit |
| ★ | **Wow: Real data** | About & Tech Stack | Item master cleaned from their spreadsheet; sales calibrated to their real monthly revenue & daily visits | Master-data cleansing is half of every ERP implementation |
| ★ | **Wow: Impact dashboard** | Dashboard | “Mothers equipped for a clean birth”, “malaria cases tested & treated” | Donor-ready impact reporting from transactions |

## Likely “change an input and re-show” questions
- *Change holding cost / ordering cost* → Reorder Points & EOQ → Save & recalculate → EOQ changes.
- *Change a supplier’s lead time* → Suppliers → Edit → Reorder points (after *Apply calculated ROP*), MRP order-by dates and new PO expected dates move.
- *Change a BOM quantity* → Bills of Material → MRP component requirements and kit rolled-up cost change.
- *Add a sales order for 50 Mama Kits next week* → MRP shows new planned builds and purchases immediately.
- *Receive a PO late* → set the receipt date after the expected date → supplier on-time % and score drop.
- *Change VAT rate or a price* → Settings / Items → next POS sale reflects it.

## Suggested team split (6 people)
1. POS + barcodes + returns
2. Inventory (transfers, counts, backorders) + customer portal + multi-user
3. Production orders + quality report + BOMs
4. Purchasing + supplier scorecards
5. ROP/EOQ + MRP
6. Financials + reports + Outreach wow + security

## Tools used (also documented in-app: About & Tech Stack)
Claude (Anthropic) as the AI coding tool · Supabase (PostgreSQL, Auth with MFA, Realtime) · React + Vite + Tailwind · Recharts · JsBarcode · html5-qrcode · GitHub · Vercel.
