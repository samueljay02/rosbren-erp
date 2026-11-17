import { q } from './test-db.mjs';
const show = (t, r) => { console.log('\n== ' + t); console.table(r); };
show('monthly revenue by stream', await q(`select to_char(s.sale_date,'YYYY-MM') m,
  round(sum(sl.line_total) filter (where i.item_type<>'service')) pharmacy,
  round(sum(sl.line_total) filter (where i.sku='SVC-CONSULT')) clinic, round(sum(sl.line_total) filter (where i.sku='SVC-LAB')) lab, count(distinct s.id) n
  from sales s join sale_lines sl on sl.sale_id=s.id join items i on i.id=sl.item_id group by 1 order by 1`));
const rep = (await q(`select get_replenishment() r`))[0].r;
show('replenishment sample', rep.items.slice(0,12).map(x=>({sku:x.sku,ad:x.avg_daily,sd:x.sd_daily,L:x.lead_time_days,ss:x.safety_stock,rop:x.calc_rop,stored:x.reorder_point,eoq:x.eoq,pos:x.position,sugg:x.suggested_qty,by:x.order_by_date})));
const sc = (await q(`select get_supplier_scorecards() r`))[0].r;
show('scorecards', sc.map(x=>({n:x.name.slice(0,22),pos:x.po_count,ot:x.on_time_pct,lt:x.lead_time_days,act:x.avg_actual_lead,fill:x.fill_rate_pct,owed:x.owed,overdue:x.overdue,score:x.score,rating:x.rating})));
const pnl = (await q(`select get_pnl(current_date-179, current_date) r`))[0].r; const {monthly, expenses, ...rest} = pnl; console.log(rest);
const inv = (await q(`select get_inventory_valuation() r`))[0].r; console.log('inv', inv.total_value, 'turnover', inv.turnover, 'days', inv.days_on_hand, inv.by_location);
const pr = (await q(`select get_production_report(current_date-60, current_date) r`))[0].r; console.log(pr.metrics, pr.by_reason.slice(0,3));
const st = (await q(`select get_inventory_status() r`))[0].r; show('status kits/backorder', st.filter(x=>x.item_type==='kit'||x.backordered>0).map(x=>({sku:x.sku,oh:x.on_hand,alloc:x.allocated,onord:x.on_order,inprod:x.in_production,bo:x.backordered,eta:x.est_available_date,basis:x.eta_basis,below:x.below_rop})));
const dash = (await q(`select get_dashboard() r`))[0].r; console.log({...dash, daily: dash.daily.length, activity: dash.activity.length});
