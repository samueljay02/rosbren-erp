// Concatenates the SQL parts into supabase/setup.sql (the one file you paste into Supabase)
import fs from 'node:fs';
const dir = new URL('../supabase/', import.meta.url);
const parts = ['01_schema.sql', '02_logic.sql', '03_reports.sql', '04_seed.sql', '04b_seed_body.sql'];
let out = '-- ROSBREN HEALTH CLINIC ERP — complete database setup\n-- Paste this whole file into Supabase → SQL Editor → Run.\n\n';
for (const p of parts) out += fs.readFileSync(new URL(p, dir), 'utf8') + '\n\n';
out += '-- generate starting data (re-run any time to refresh history up to yesterday)\nselect reset_demo_data();\n';
fs.writeFileSync(new URL('setup.sql', dir), out);
console.log('setup.sql', (out.length / 1024).toFixed(0) + ' KB');
