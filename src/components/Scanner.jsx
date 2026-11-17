import { useEffect, useRef, useState, useMemo } from 'react';
import { Camera, ScanLine, X } from 'lucide-react';
import { useLookups, useToast } from '../lib/hooks';
import { cx } from './ui';

// Phone/laptop camera barcode scanner (needs HTTPS — Vercel/GitHub Pages provide it)
export function CameraScanner({ open, onClose, onScan }) {
  const ref = useRef(null);
  const [err, setErr] = useState('');
  useEffect(() => {
    if (!open) return;
    let scanner; let stopped = false; let last = '';
    (async () => {
      try {
        const { Html5Qrcode, Html5QrcodeSupportedFormats: F } = await import('html5-qrcode');
        scanner = new Html5Qrcode('cam-reader', { formatsToSupport: [F.EAN_13, F.CODE_128, F.EAN_8, F.UPC_A, F.CODE_39, F.QR_CODE], verbose: false });
        await scanner.start({ facingMode: 'environment' }, { fps: 12, qrbox: { width: 280, height: 140 } }, (text) => {
          if (stopped || text === last) return;
          last = text; setTimeout(() => { last = ''; }, 1500);
          if (navigator.vibrate) navigator.vibrate(60);
          onScan(text);
        }, () => {});
      } catch (e) { setErr(e?.message || String(e)); }
    })();
    return () => { stopped = true; scanner?.isScanning && scanner.stop().then(() => scanner.clear()).catch(() => {}); };
  }, [open, onScan]);
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/70 p-4">
      <div className="w-full max-w-md rounded-xl bg-white p-4">
        <div className="mb-2 flex items-center justify-between"><b className="text-brand-800">Scan barcode with camera</b>
          <button onClick={onClose} aria-label="Close"><X /></button></div>
        <div id="cam-reader" ref={ref} className="overflow-hidden rounded-lg bg-black" />
        {err && <p className="mt-2 text-sm text-red-700">Camera unavailable: {err}. Use a USB scanner or type the barcode.</p>}
        <p className="mt-2 text-xs text-slate-500">Hold the printed label 10–20 cm from the camera. Each successful scan beeps/vibrates and stays open for the next item.</p>
      </div>
    </div>
  );
}

// Text box that works with USB/Bluetooth "keyboard wedge" scanners (they type the code + Enter)
// and also opens the camera scanner. Also lets the user search items by name/SKU.
export function ScanInput({ onItem, placeholder = 'Scan barcode or search item…', filter, autoFocus = true, className }) {
  const L = useLookups();
  const toast = useToast();
  const [q, setQ] = useState('');
  const [open, setOpen] = useState(false);
  const [cam, setCam] = useState(false);
  const [hi, setHi] = useState(0);
  const inputRef = useRef(null);
  const pool = useMemo(() => (L.items || []).filter((i) => i.active && (!filter || filter(i))), [L.items, filter]);
  const matches = useMemo(() => {
    if (!q) return [];
    const s = q.toLowerCase();
    return pool.filter((i) => i.name.toLowerCase().includes(s) || i.sku.toLowerCase().includes(s) || String(i.barcode).includes(s)).slice(0, 8);
  }, [q, pool]);
  const handleCode = (code) => {
    const it = L.itemByBarcode?.[String(code).trim()];
    if (it && (!filter || filter(it))) { onItem(it); setQ(''); setOpen(false); return true; }
    toast(`No item with barcode ${code}`, 'error'); return false;
  };
  const pick = (it) => { onItem(it); setQ(''); setOpen(false); inputRef.current?.focus(); };
  return (
    <div className={cx('relative', className)}>
      <div className="flex gap-2">
        <div className="relative flex-1">
          <ScanLine size={18} className="absolute left-3 top-2.5 text-brand-500" />
          <input ref={inputRef} autoFocus={autoFocus} value={q} placeholder={placeholder}
            onChange={(e) => { setQ(e.target.value); setOpen(true); setHi(0); }}
            onKeyDown={(e) => {
              if (e.key === 'ArrowDown') { setHi((h) => Math.min(h + 1, matches.length - 1)); e.preventDefault(); }
              if (e.key === 'ArrowUp') { setHi((h) => Math.max(h - 1, 0)); e.preventDefault(); }
              if (e.key === 'Enter') {
                e.preventDefault();
                if (/^\d{6,}$/.test(q.trim())) handleCode(q.trim());
                else if (matches[hi]) pick(matches[hi]);
              }
            }}
            onBlur={() => setTimeout(() => setOpen(false), 150)}
            className="w-full rounded-lg border-2 border-brand-200 bg-white py-2 pl-10 pr-3 text-sm focus:border-brand-500 focus:outline-none" />
        </div>
        <button type="button" onClick={() => setCam(true)} title="Scan with camera"
          className="inline-flex items-center gap-1 rounded-lg bg-brand-600 px-3 text-sm font-bold text-white hover:bg-brand-700"><Camera size={16} /><span className="hidden sm:inline">Camera</span></button>
      </div>
      {open && matches.length > 0 && (
        <ul className="absolute z-30 mt-1 max-h-72 w-full overflow-auto rounded-lg border border-slate-200 bg-white shadow-lg">
          {matches.map((m, i) => (
            <li key={m.id} onMouseDown={() => pick(m)} className={cx('flex cursor-pointer justify-between gap-2 px-3 py-2 text-sm', i === hi ? 'bg-brand-50' : 'hover:bg-slate-50')}>
              <span><b>{m.name}</b> <span className="text-xs text-slate-500">{m.sku}</span></span>
              <span className="font-mono text-xs text-slate-400">{m.barcode}</span>
            </li>))}
        </ul>
      )}
      <CameraScanner open={cam} onClose={() => setCam(false)} onScan={(code) => handleCode(code)} />
    </div>
  );
}

// Simple item dropdown (non-scan use)
export function ItemSelect({ value, onChange, filter, placeholder = 'Select item…', className }) {
  const L = useLookups();
  const opts = (L.items || []).filter((i) => i.active && (!filter || filter(i)));
  return (
    <select value={value || ''} onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)}
      className={cx('w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm focus:border-brand-500 focus:outline-none', className)}>
      <option value="">{placeholder}</option>
      {opts.map((i) => <option key={i.id} value={i.id}>{i.name} ({i.sku})</option>)}
    </select>
  );
}
