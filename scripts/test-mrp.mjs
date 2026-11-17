import { runMRP } from '../src/lib/mrp.js';
import assert from 'node:assert';
// hand-checkable example: Kit K = 2×A + 1×B. SO: 10 K in week 2. K on hand 4, A on hand 5, B on hand 0; PO for 3 B arriving day 3.
const input = { today: '2026-11-16',
  items: [{ id: 1, sku: 'K', name: 'Kit', item_type: 'kit', on_hand: 4, lead_time_days: 1, avg_cost: 10 },
          { id: 2, sku: 'A', name: 'Comp A', item_type: 'purchased', on_hand: 5, lead_time_days: 7, avg_cost: 1 },
          { id: 3, sku: 'B', name: 'Comp B', item_type: 'purchased', on_hand: 0, lead_time_days: 14, avg_cost: 2 }],
  bom: [{ parent: 1, component: 2, qty_per: 2 }, { parent: 1, component: 3, qty_per: 1 }],
  demand: [{ item_id: 1, qty: 10, date: '2026-11-25', so_number: 'SO-1', customer: 'X' }],
  receipts: [{ item_id: 3, qty: 3, date: '2026-11-19', ref: 'PO-1' }], production: [] };
const r = runMRP(input, { netParents: true });
const s = Object.fromEntries(r.suggestions.map(x => [x.sku, x]));
assert.equal(s.K.qty, 6); assert.equal(s.K.order_by, '2026-11-24');      // 10 − 4 on hand, 1-day assembly offset
assert.equal(s.A.qty, 7); assert.equal(s.A.order_by, '2026-11-17');      // 6×2=12 − 5 on hand; need 11-24, 7-day offset
assert.equal(s.B.qty, 3); assert.equal(s.B.late, true);                   // 6 − 3 on PO; 14-day lead time → already late
const r2 = runMRP(input, { netParents: false });
assert.equal(r2.suggestions.find(x => x.sku === 'A').qty, 15);            // 10×2 − 5
console.log('MRP tests passed', r.weeks, JSON.stringify(r.rows.find(x=>x.sku==='A')));
