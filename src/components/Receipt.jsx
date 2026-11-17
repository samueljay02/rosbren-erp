import { useEffect, useRef } from 'react';
import JsBarcode from 'jsbarcode';
import { fmt, dt, num } from '../lib/format';
import Logo from './Logo';

export function BarcodeSvg({ value, height = 40, width = 1.6, format = 'CODE128', fontSize = 12, displayValue = true }) {
  const ref = useRef(null);
  useEffect(() => {
    if (!ref.current || !value) return;
    try {
      JsBarcode(ref.current, String(value), { format: format === 'auto' ? (/^\d{13}$/.test(value) ? 'EAN13' : 'CODE128') : format, height, width, fontSize, margin: 4, displayValue });
    } catch { JsBarcode(ref.current, String(value), { format: 'CODE128', height, width, fontSize, margin: 4, displayValue }); }
  }, [value, height, width, format, fontSize, displayValue]);
  return <svg ref={ref} />;
}

// Printable receipt (80mm thermal-printer friendly)
export default function Receipt({ data }) {
  if (!data) return null;
  const { sale: s, lines, company = {} } = data;
  return (
    <div id="receipt" className="mx-auto w-[300px] bg-white p-3 font-mono text-[12px] leading-snug text-black">
      <div className="flex flex-col items-center text-center">
        <Logo size={36} />
        <div className="mt-1 text-sm font-black tracking-wider">{(company.company_name || 'Rosbren Health Clinic').toUpperCase()}</div>
        <div>{company.company_address}</div>
        {company.company_phone && <div>Tel {company.company_phone}</div>}
      </div>
      <div className="my-2 border-t border-dashed border-black" />
      <div className="flex justify-between"><span>Receipt</span><b>{s.sale_number}</b></div>
      <div className="flex justify-between"><span>Date</span><span>{dt(s.sale_date)}</span></div>
      <div className="flex justify-between"><span>Location</span><span>{s.location_name}</span></div>
      {s.customer_name && <div className="flex justify-between"><span>Customer</span><span className="text-right">{s.customer_name}</span></div>}
      <div className="flex justify-between"><span>Served by</span><span>{s.cashier_name}</span></div>
      <div className="my-2 border-t border-dashed border-black" />
      {lines.map((l) => (
        <div key={l.id} className="mb-1">
          <div>{l.name}</div>
          <div className="flex justify-between pl-2"><span>{fmt(l.qty)} × {fmt(l.unit_price)}{num(l.discount_amount) > 0 && ` (−${fmt(l.discount_amount)})`}{num(l.tax_amount) > 0 && ' T'}</span><span>{fmt(num(l.line_total) + num(l.tax_amount))}</span></div>
        </div>))}
      <div className="my-2 border-t border-dashed border-black" />
      <div className="flex justify-between"><span>Subtotal</span><span>{fmt(s.subtotal)}</span></div>
      {num(s.discount_total) > 0 && <div className="flex justify-between"><span>Discounts</span><span>−{fmt(s.discount_total)}</span></div>}
      {num(s.tax_total) > 0 && <div className="flex justify-between"><span>VAT (T)</span><span>{fmt(s.tax_total, 2)}</span></div>}
      <div className="mt-1 flex justify-between text-sm font-black"><span>TOTAL UGX</span><span>{fmt(s.total)}</span></div>
      <div className="flex justify-between"><span>Paid by</span><span>{s.payment_method}</span></div>
      {num(s.amount_tendered) > 0 && <><div className="flex justify-between"><span>Tendered</span><span>{fmt(s.amount_tendered)}</span></div>
        <div className="flex justify-between"><span>Change</span><span>{fmt(num(s.amount_tendered) - num(s.total))}</span></div></>}
      <div className="my-2 border-t border-dashed border-black" />
      <div className="flex justify-center"><BarcodeSvg value={s.sale_number} height={34} width={1.3} fontSize={11} /></div>
      <p className="mt-1 text-center">{company.receipt_footer}</p>
      <p className="text-center text-[10px]">Keep this receipt for returns or exchanges.</p>
    </div>
  );
}

export function printReceipt() {
  const el = document.getElementById('receipt');
  if (!el) return;
  const w = window.open('', '_blank', 'width=380,height=640');
  w.document.write(`<html><head><title>Receipt</title><style>body{margin:0;font-family:ui-monospace,monospace;font-size:12px}
    .flex{display:flex}.justify-between{justify-content:space-between}.justify-center{justify-content:center}.text-center{text-align:center}.text-right{text-align:right}
    .flex-col{flex-direction:column}.items-center{align-items:center}.font-black{font-weight:900}.text-sm{font-size:14px}.pl-2{padding-left:8px}.mb-1{margin-bottom:4px}
    .my-2{margin:8px 0}.mt-1{margin-top:4px}.border-t{border-top:1px dashed #000}.w-\\[300px\\]{width:300px}.p-3{padding:12px}.text-\\[10px\\]{font-size:10px}</style></head>
    <body>${el.outerHTML}<script>window.onload=()=>{window.print();setTimeout(()=>window.close(),300)}<\/script></body></html>`);
  w.document.close();
}
