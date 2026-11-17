import { ResponsiveContainer, LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, Cell } from 'recharts';
import { compact, dShort, fmt } from '../lib/format';

// Validated categorical palette (dataviz reference palette, light mode): fixed order, never cycled
export const SERIES = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#6250d6'];
const axis = { fontSize: 11, fill: '#52514e' };
const grid = <CartesianGrid stroke="#ebeae6" vertical={false} />;

function Tip({ active, payload, label, money = true, labelFmt }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2 text-xs shadow-lg">
      <div className="mb-1 font-bold text-slate-800">{labelFmt ? labelFmt(label) : label}</div>
      {payload.map((p) => (
        <div key={p.dataKey} className="flex items-center gap-2 text-slate-700">
          <span className="h-2 w-2 rounded-full" style={{ background: p.color }} />{p.name}: <b className="tabular-nums">{money ? 'UGX ' + fmt(p.value) : fmt(p.value, 1)}</b>
        </div>))}
    </div>
  );
}

// lines over time (one y-axis only)
export function TimeLines({ data, x = 'date', series, height = 260, money = true, xFmt = dShort }) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <LineChart data={data} margin={{ top: 8, right: 12, left: 0, bottom: 0 }}>
        {grid}
        <XAxis dataKey={x} tick={axis} tickFormatter={xFmt} tickLine={false} axisLine={{ stroke: '#d6d5d0' }} minTickGap={24} />
        <YAxis tick={axis} tickFormatter={compact} tickLine={false} axisLine={false} width={48} />
        <Tooltip content={<Tip money={money} labelFmt={xFmt} />} cursor={{ stroke: '#a3a29b', strokeDasharray: '3 3' }} />
        {series.length > 1 && <Legend iconType="circle" wrapperStyle={{ fontSize: 12 }} />}
        {series.map((s, i) => <Line key={s.key} type="monotone" dataKey={s.key} name={s.label} stroke={s.color || SERIES[i]} strokeWidth={2} dot={false} activeDot={{ r: 5, strokeWidth: 2, stroke: '#fff' }} />)}
      </LineChart>
    </ResponsiveContainer>
  );
}

// vertical bars by category / period
export function Bars({ data, x, series, height = 260, money = true, xFmt = (v) => v, stacked }) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} margin={{ top: 8, right: 12, left: 0, bottom: 0 }} barGap={2}>
        {grid}
        <XAxis dataKey={x} tick={axis} tickFormatter={xFmt} tickLine={false} axisLine={{ stroke: '#d6d5d0' }} minTickGap={8} />
        <YAxis tick={axis} tickFormatter={compact} tickLine={false} axisLine={false} width={48} />
        <Tooltip content={<Tip money={money} labelFmt={xFmt} />} cursor={{ fill: '#f2f1ed' }} />
        {series.length > 1 && <Legend iconType="circle" wrapperStyle={{ fontSize: 12 }} />}
        {series.map((s, i) => <Bar key={s.key} dataKey={s.key} name={s.label} fill={s.color || SERIES[i]} radius={stacked ? 0 : [4, 4, 0, 0]} stackId={stacked ? 'a' : undefined} maxBarSize={36} stroke="#fff" strokeWidth={stacked ? 1 : 0} />)}
      </BarChart>
    </ResponsiveContainer>
  );
}

// horizontal ranked bars (single series, value labels at bar end)
export function RankBars({ data, label = 'name', value = 'revenue', height, money = true, color = SERIES[0], highlight }) {
  const h = height || Math.max(160, data.length * 30 + 20);
  return (
    <ResponsiveContainer width="100%" height={h}>
      <BarChart data={data} layout="vertical" margin={{ top: 0, right: 56, left: 8, bottom: 0 }}>
        <XAxis type="number" hide />
        <YAxis type="category" dataKey={label} tick={{ ...axis, fill: '#0b0b0b' }} width={190} tickLine={false} axisLine={false}
          tickFormatter={(v) => (v.length > 28 ? v.slice(0, 27) + '…' : v)} />
        <Tooltip content={<Tip money={money} />} cursor={{ fill: '#f2f1ed' }} />
        <Bar dataKey={value} name={money ? 'Revenue' : 'Value'} fill={color} radius={[0, 4, 4, 0]} maxBarSize={18}
          label={{ position: 'right', fontSize: 11, fill: '#52514e', formatter: (v) => compact(v) }}>
          {highlight && data.map((d, i) => <Cell key={i} fill={highlight(d) || color} />)}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
